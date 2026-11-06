# shellcheck shell=bash
# shellcheck disable=SC2154,SC2164 # variables come from the generated header, "set -e" is added by create_script

# Admin only. Database console inside DB_SERVICE, as the app's database user.
# User, password and database come from the container's own environment (set from
# .env by the compose file), so nothing is copied here. Works with the official
# PostgreSQL (psql), MariaDB (mariadb) and MySQL (mysql) images.
# Extra arguments go to the client:
#   app-db                                   interactive session
#   app-db -c 'select count(*) from users'   one query (PostgreSQL; MySQL/MariaDB: -e)
#   app-db < dump.sql                        run a file

usage="Usage: app-db [CLIENT ARGUMENTS]   (admins only, no sudo needed)

Database console in the ${DB_SERVICE} container, as the app's database user
(psql, mariadb or mysql, picked by the container's environment).
  app-db                                   interactive session
  app-db -c 'select count(*) from users'   one query (PostgreSQL; MySQL/MariaDB: -e)
  app-db < dump.sql                        run a file
The client's own help: app-db -?"
handle_help "$usage" "$@"

# No TTY when the input is a file or a pipe: with one, the client would mangle the input
tty=()
if [ ! -t 0 ]; then
    tty=(-T)
fi

# Runs inside the container. The MySQL/MariaDB password goes through MYSQL_PWD,
# not "-p<password>": a command line is visible to every user of the server in "ps",
# the environment of a process only to root
# shellcheck disable=SC2016 # expanded by sh inside the container, not here
console='
if [ -n "${POSTGRES_USER:-}" ]; then
    exec psql -U "$POSTGRES_USER" "${POSTGRES_DB:-$POSTGRES_USER}" "$@"
elif [ -n "${MARIADB_USER:-}" ]; then
    export MYSQL_PWD="${MARIADB_PASSWORD:-}"
    exec mariadb -u "$MARIADB_USER" ${MARIADB_DATABASE:+"$MARIADB_DATABASE"} "$@"
elif [ -n "${MYSQL_USER:-}" ]; then
    export MYSQL_PWD="${MYSQL_PASSWORD:-}"
    exec mysql -u "$MYSQL_USER" ${MYSQL_DATABASE:+"$MYSQL_DATABASE"} "$@"
else
    echo "No POSTGRES_USER, MARIADB_USER or MYSQL_USER in this container: is it the database?" >&2
    exit 1
fi'

"${COMPOSE[@]}" exec "${tty[@]}" "$DB_SERVICE" sh -c "$console" db-console "$@"
