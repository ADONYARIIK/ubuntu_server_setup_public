# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Admin only. Fill the database with the project's seeders (database/seeders), so a new
# server does not start with an empty app:
#   app-seed                 run DatabaseSeeder on the current database (adds records to it)
#   app-seed --class=NAME    run only the seeder NAME (e.g. --class=CategorySeeder)
#   app-seed --fresh         TEST SERVER ONLY: drop every table, run all migrations again, then seed
#   app-seed --yes           do not ask for confirmation (for scripts; also needed without a terminal)
# The options can be combined: app-seed --fresh --class=NAME.
# Seeders that build records with Faker need the dev packages in the image (composer install
# without --no-dev); a production image usually has none, and the run fails with "Class Faker\... not found"

usage="Usage: app-seed [--fresh] [--class=SEEDER] [--yes]   (admins only, no sudo needed)

Fill the database with the project's seeders, so the app does not start empty.
  app-seed                 run DatabaseSeeder: adds records to the current database
  app-seed --class=NAME    run only the seeder NAME (e.g. --class=CategorySeeder)
  app-seed --fresh         test server only: drop EVERY table, migrate again, then seed
  app-seed --yes           do not ask for confirmation (also needed without a terminal)
Options can be combined: app-seed --fresh --class=NAME.
Seeders that use Faker need the dev packages in the image (composer install without --no-dev)."
handle_help "$usage" "$@"

fresh=false
seeder=""
assume_yes=false

for arg in "$@"; do
    case "$arg" in
        --fresh) fresh=true ;;
        --class=*) seeder="${arg#--class=}" ;;
        -y|--yes) assume_yes=true ;;
        -h|--help ) printf '%s\n' "$usage"
                    exit 0 ;;
        *) printf 'Unknown option: %s\n\n%s\n' "$arg" "$usage" >&2
           exit 1 ;;
    esac
done

# A class name or a namespaced one (Database\Seeders\UserSeeder); anything else is a typo
if [ -n "$seeder" ] && ! [[ "$seeder" =~ ^[A-Za-z_][A-Za-z0-9_\\]*$ ]]; then
    echo "--class must be a seeder class name, got: ${seeder}" >&2
    exit 1
fi

# Wiping the database of a production server would delete the real users' data.
# Laravel apps may block it too (DB::prohibitDestructiveCommands), this check does not rely on that
if [ "$fresh" = true ] && [ "$IS_PRODUCTION" = true ]; then
    echo "--fresh is refused on a production server: it deletes every table with the real data." >&2
    echo "Without --fresh, app-seed only adds records." >&2
    exit 1
fi

# The same lock as app-deploy: seeding in the middle of a build or a migration would mix them up
take_lock

if [ -z "$("${COMPOSE[@]}" ps --status running --quiet "$APP_SERVICE" 2>/dev/null)" ]; then
    echo "${APP_SERVICE} is not running. Start the app first: sudo app-start (or sudo app-deploy)" >&2
    exit 1
fi

# What is about to happen, then one confirmation for all of it
target="${seeder:-DatabaseSeeder}"
if [ "$fresh" = true ]; then
    echo "app-seed --fresh: EVERY table of the database is dropped, all migrations run again, then ${target} fills it."
else
    echo "app-seed: ${target} adds records to the current database. Records that are already there stay;"
    echo "a seeder that creates a fixed record (e.g. an admin with a set e-mail) can fail on a second run."
    echo "To start over from an empty database on a test server: app-seed --fresh"
fi
if [ "$IS_PRODUCTION" = true ]; then
    echo "This is a PRODUCTION server."
fi

if [ "$assume_yes" != true ]; then
    if [ ! -t 0 ]; then
        echo "No terminal to ask for confirmation: add --yes" >&2
        exit 1
    fi
    read -r -p "Type yes to continue: " answer
    if [ "$answer" != yes ]; then
        echo "Cancelled."
        exit 1
    fi
fi

# Seeders that translate their data (TRANSLATE_SERVICE set) need the service to answer:
# wait until it is healthy (no-op when it already is). Model downloads stay off here,
# new languages are added by app-update-languages
if [ -n "$TRANSLATE_SERVICE" ]; then
    echo "Waiting for ${TRANSLATE_SERVICE}..."
    "${COMPOSE[@]}" up -d --wait --wait-timeout 1800 "$TRANSLATE_SERVICE"
fi

# Keep a terminal for artisan when there is one: it shows the progress of every seeder.
# --force: the confirmation above replaces artisan's own "Are you sure?" on production
tty=()
if [ ! -t 0 ]; then
    tty=(-T)
fi
artisan=("${COMPOSE[@]}" exec "${tty[@]}" "$APP_SERVICE" php artisan)

if [ "$fresh" = true ]; then
    fresh_args=(--seed --force)
    if [ -n "$seeder" ]; then
        fresh_args+=("--seeder=${seeder}")
    fi
    # PostgreSQL keeps enum types apart from tables; without --drop-types the next migration
    # fails with "type ... already exists". Other databases have no such option (artisan stops with
    # an error), so it is added only when the database container is PostgreSQL, the same check as app-db
    # shellcheck disable=SC2016 # expanded by sh inside the container
    if "${COMPOSE[@]}" exec -T "$DB_SERVICE" sh -c '[ -n "${POSTGRES_USER:-}" ]' 2>/dev/null; then
        fresh_args+=(--drop-types)
    fi
    "${artisan[@]}" migrate:fresh "${fresh_args[@]}"
else
    seed_args=(--force)
    if [ -n "$seeder" ]; then
        seed_args+=("--class=${seeder}")
    fi
    "${artisan[@]}" db:seed "${seed_args[@]}"
fi

# Lists cached before the seeding (e.g. "no recipes yet") would hide the new records until they expire
"${artisan[@]}" cache:clear

echo "Done: the database is seeded."
