# ubuntu_server_setup

One script that turns a fresh Ubuntu Server (24.04+) into a ready server for a
Laravel project running in Docker Compose: users from SSH keys, hardened SSH,
firewall, fail2ban, Docker, the project cloned from GitHub, and a small set of
`app-*` commands the team can run with `sudo`, without getting full root access.

The script is **idempotent**: run it again after any change (a new key, a new
setting) and it brings the server to the described state without breaking what
is already there.

**Version:** 1.2.0

---

## Contents

- [ubuntu\_server\_setup](#ubuntu_server_setup)
  - [Contents](#contents)
  - [What it does](#what-it-does)
  - [Quick start](#quick-start)
  - [Settings](#settings)
  - [Production vs test server (`IS_PRODUCTION`)](#production-vs-test-server-is_production)
  - [Commands for the team](#commands-for-the-team)
  - [Testing a branch on the test server](#testing-a-branch-on-the-test-server)
  - [The `.env` file](#the-env-file)
  - [Users and access](#users-and-access)
    - [Storing the keys in git](#storing-the-keys-in-git)
  - [Commands for admins](#commands-for-admins)
  - [Repository structure](#repository-structure)
    - [Changing the `app-*` commands](#changing-the-app--commands)
  - [Logs and troubleshooting](#logs-and-troubleshooting)
  - [Changelog](#changelog)
    - [1.2.0](#120)
    - [1.1.2](#112)
    - [1.1.1](#111)
    - [1.1.0](#110)
    - [1.0.0](#100)
  - [License](#license)

---

## What it does

In order:

1. Installs base tools (`curl`, `git`, `vim`, `htop`, `tmux`, `jq`, `ufw`, `fail2ban`, …), plus `superfile` and Tailscale.
2. Sets the timezone and automatic security updates.
3. Keeps a laptop running as a server with the lid closed (all sleep modes off).
4. Creates one user per `keys/<name>.pub` and removes team users whose key file was deleted.
5. Gives admins (`ADMIN_USERS`) full `sudo`.
6. Hardens SSH: key login only, no root login, no password login, no port forwarding
   (a test server can allow `ssh -L` to `TUNNEL_PORTS`).
7. Firewall (UFW): only SSH and `FIREWALL_PORTS` (80 and 443 by default) are open. Enables fail2ban.
8. Installs Docker CE + Compose plugin, with log rotation.
9. Clones the project into `APP_DIR` with a read-only deploy key and **creates `.env` from `.env.example`**
   (they can be in a subfolder, see [The `.env` file](#the-env-file)).
10. Installs the `app-*` scripts and lets team members run them with `sudo`, plus admin-only
    commands (`ADMIN_SCRIPTS`, e.g. `app-db`).

## Quick start

```bash
git clone https://github.com/ADONYARIIK/ubuntu_server_setup_public.git
cd ubuntu_server_setup_public

# 1. One public key per person: the file name is the login name
cp ~/admin.pub  keys/admin.pub
cp ~/anna.pub   keys/anna.pub

# 2. Edit the settings block at the top of setup.sh
#    (at least REPO_URL and IS_PRODUCTION; ENV_FILE / ENV_EXAMPLE
#    if Laravel is not in the root of the project)
vim setup.sh

# 3. Run
sudo ./setup.sh
```

After the first run, once:

1. `sudo tailscale up` - authorize the server in Tailscale.
2. Add root's deploy key (printed by the script, `/root/.ssh/deploy_key.pub`) to GitHub:
   project repo → **Settings → Deploy keys** (read-only). If the clone failed because of this, run `sudo ./setup.sh` again.
3. Fill in the real values in `.env`: `sudo vim /srv/app/.env` (the path is `APP_DIR/ENV_FILE`,
   e.g. `/srv/app/backend/.env`).
4. First start: `sudo app-deploy`.

> ⚠️ Make sure at least one admin has a key in `keys/` **before** the first run:
> password login over SSH is turned off. The script refuses to continue if no admin has a key.

## Settings

All settings are at the top of `setup.sh`.

| Variable | Default | Description |
|---|---|---|
| `IS_PRODUCTION` | `true` | `true` = production server, `false` = test server (see below) |
| `SSH_PORT` | `22` | SSH port (firewall uses the same value) |
| `FIREWALL_PORTS` | `(80/tcp 443/tcp)` | Ports UFW opens besides SSH. `()` when the app is reached only through an outbound tunnel (Cloudflare Tunnel): nothing has to be open |
| `ADMIN_USERS` | `("admin")` | Users with full `sudo`. Need a key in `keys/` or an existing account with `authorized_keys` |
| `TEAM_GROUP` | `team` | Group that marks users created from `keys/`. Only its members can be removed automatically |
| `TIMEZONE` | `Europe/Warsaw` | Server timezone |
| `APP_DIR` | `/srv/app` | Where the project is cloned |
| `COMPOSE_FILE_PROD` | `compose.prod.yaml` | Compose file of a production server (path inside `APP_DIR`, e.g. `backend/compose.prod.yaml`) |
| `COMPOSE_FILE_DEV` | *(empty)* | Compose file of a test server (`IS_PRODUCTION=false`), e.g. `compose.dev.yaml`. Empty = `COMPOSE_FILE_PROD` |
| `APP_SERVICE` | `app` | Laravel service name (used for `php artisan`) |
| `DB_SERVICE` | `pgsql` | Database service (official PostgreSQL, MySQL or MariaDB image), used by the admin command `app-db` |
| `TRANSLATE_SERVICE` | *(empty)* | Translation service name (e.g. LibreTranslate). Set = the team gets `app-update-languages` (see "Commands for the team") |
| `ENV_TRANSLATE_UPDATE_MODELS` | `LIBRETRANSLATE_UPDATE_MODELS` | Variable `app-update-languages` sets to `true` for one run to download models. The compose file must use it as `${...}` in `environment:` |
| `ENV_TRANSLATE_LANGUAGES` | `LIBRETRANSLATE_LANGUAGES` | Variable in `.env` with the list of languages (only shown in the output of `app-update-languages`) |
| `APP_SCRIPTS` | `app-start … app-fetch` | Scripts the team may run with `sudo` (`app-branch` and `app-update-languages` are added automatically, see above) |
| `ADMIN_SCRIPTS` | `(app-db)` | Commands for admins only (see "Commands for admins") |
| `APP_LOGS_TAIL` | `200` | Lines shown by `sudo app-logs` |
| `APP_LOGS_MAX` | `5000` | Most lines `sudo app-logs <N>` may ask for |
| `TUNNEL_PORTS` | `()` | Test server only: ports on the server's `127.0.0.1` reachable through `ssh -L`, e.g. `(8025 9001)`. Empty = no forwarding |
| `REPO_URL` | `git@github.com:USER/REPO.git` | SSH URL of the project |
| `REPO_BRANCH` | `main` | Main branch: cloned first, the only one on production |
| `DEPLOY_KEY` | `/root/.ssh/deploy_key` | Root's private key for GitHub |
| `ENV_EXAMPLE` | `.env.example` | Template the `.env` is created from (path inside `APP_DIR`, e.g. `backend/.env.example`) |
| `ENV_FILE` | `.env` | The project's `.env` (path inside `APP_DIR`, e.g. `backend/.env`). Must be the same file the compose files use |

Before anything on the server is changed, `setup.sh` checks the settings and stops
with an error that names the wrong one:

- `IS_PRODUCTION` is `true` or `false`;
- `COMPOSE_FILE_PROD`, `COMPOSE_FILE_DEV`, `ENV_EXAMPLE`, `ENV_FILE` are paths inside `APP_DIR`:
  not absolute, no `..`, not empty (only `COMPOSE_FILE_DEV` may be empty);
- `APP_LOGS_TAIL` and `APP_LOGS_MAX` are positive numbers, `APP_LOGS_TAIL` ≤ `APP_LOGS_MAX`;
- `TUNNEL_PORTS` are port numbers (1-65535);
- the old `COMPOSE_FILE` (renamed in 1.2.0) is not set.

## Production vs test server (`IS_PRODUCTION`)

| | `IS_PRODUCTION=true` (production) | `IS_PRODUCTION=false` (test) |
|---|---|---|
| Branch | always `REPO_BRANCH` | any branch from GitHub |
| `app-branch` | **does not exist** (file and sudo rule removed) | installed, available to the team |
| `app-deploy` | switches back to `REPO_BRANCH` if needed, then deploys | deploys the current branch |
| `app-fetch` | available | available |
| Compose file | `COMPOSE_FILE_PROD` | `COMPOSE_FILE_DEV` |
| SSH port forwarding | off | `ssh -L` only, only to `127.0.0.1:<TUNNEL_PORTS>` (off while `TUNNEL_PORTS` is empty) |

Any value other than `true` / `false` stops the script with an error, so a typo
(`True`, `yes`) never picks a mode silently.

You can change the mode at any time: edit the variable and run `sudo ./setup.sh`
again. When a test server becomes production, `app-branch` is deleted and the
next `sudo app-deploy` returns the code to `REPO_BRANCH`.

> When the mode changes, the `app-*` commands switch to the other compose file.
> What happens to the old stack depends on the **compose project name**: the `name:` in the
> file, or, without it, the name of the file's folder.
>
> - **Different names** (files in different folders, or different `name:`): two separate
>   projects. The old stack keeps running: it still holds its ports, and a tunnel in it
>   still serves its domain. Stop it first, e.g.
>   `sudo docker compose -f /srv/app/backend/compose.dev.yaml down` (volumes are kept),
>   then `sudo app-deploy`.
> - **Same name** (e.g. both files in `backend/`): one project. `sudo app-deploy` recreates
>   its containers from the new file and removes services the new file does not have
>   (`--remove-orphans`); the volumes, including the database, are shared by both modes.

A test server may run developer tools (e.g. Mailpit, a storage console) that the
compose file publishes on the server's `127.0.0.1` only (`ports: ['127.0.0.1:8025:8025']`):
Docker's published ports bypass UFW, so anything else would be open to the internet.
List those ports in `TUNNEL_PORTS=(8025 9001)` and open them through an SSH tunnel:

```bash
ssh -N -L 8025:127.0.0.1:8025 -L 9001:127.0.0.1:9001 <user>@<server>
```

sshd refuses any destination not listed in `TUNNEL_PORTS` (`administratively prohibited`).

## Commands for the team

Team members (every `keys/*.pub` except admins) can run exactly these commands
with `sudo`, **without arguments** (the only exception: the number of lines for
`app-logs`), and nothing else as root:

| Command | What it does |
|---|---|
| `sudo app-start` | Start the containers (`up -d`) |
| `sudo app-stop` | Stop the containers |
| `sudo app-restart` | Restart the containers |
| `sudo app-status` | Container status (`ps`) |
| `sudo app-logs [N]` | Last `APP_LOGS_TAIL` log lines, or the last `N` (up to `APP_LOGS_MAX`) |
| `sudo app-deploy` | `git pull` → build → recreate containers → `migrate --force` → `optimize` |
| `sudo app-fetch` | Update the branch list from GitHub, show the current branch and whether it is behind |
| `sudo app-branch` | **Test server only.** Pick a branch from a list, switch to it and redeploy |
| `sudo app-update-languages` | **Only with `TRANSLATE_SERVICE`.** Download the models of languages added to `ENV_TRANSLATE_LANGUAGES` (`LIBRETRANSLATE_LANGUAGES`) in `.env`, then restart the service with updates off again |

`app-update-languages` starts the service once with `ENV_TRANSLATE_UPDATE_MODELS=true`
set in the shell. That only works if the compose file takes the switch from this variable
through `${...}` in `environment:` (a value from `env_file:` is not overridden by the
shell), and the models must be kept in a volume. For LibreTranslate:

```yaml
libretranslate:
    environment:
        LT_UPDATE_MODELS: '${LIBRETRANSLATE_UPDATE_MODELS:-false}'
    volumes:
        - 'libretranslate:/home/libretranslate/.local'
```

`app-deploy`, `app-fetch`, `app-branch` and `app-update-languages` share one lock: if someone else is
deploying right now, the second command stops with a message instead of
mixing up two builds.

Read-only git commands work without `sudo`, e.g. `git -C /srv/app log --oneline -5`.

## Commands for admins

`ADMIN_SCRIPTS` are installed as `root:sudo 0750`: team members cannot run or even
read them. Admins type them **without** `sudo`, the command asks for the password itself.

| Command | What it does |
|---|---|
| `app-db [args]` | Database console in `DB_SERVICE` as the app's database user: `psql`, `mariadb` or `mysql`, picked by the container's `POSTGRES_USER` / `MARIADB_USER` / `MYSQL_USER`. Arguments go to the client: `app-db -c 'select 1'` (PostgreSQL), `app-db -e 'select 1'` (MySQL), `app-db < dump.sql` |

A new admin command: add `templates/<name>.sh`, put the name into `ADMIN_SCRIPTS`,
run `sudo ./setup.sh`.

## Testing a branch on the test server

Goal: check a feature branch on a real server **before** it is merged into `main`.

```text
$ sudo app-fetch
Current branch: main
Branches on GitHub:
    feature/login
    fix/typo
  * main

$ sudo app-branch
Updating the branch list from GitHub...

Current branch: main   (main branch: main)

1) feature/login
2) fix/typo
3) main
Branch number (Ctrl+C to cancel): 1
Switch to 'feature/login' and redeploy (build, migrate)? [y/N] y
Now on branch: feature/login (8ded04a login v2)
...
Done. Branch 'feature/login' is running. Back to the main branch: sudo app-branch -> main
```

- **New commits pushed to the same branch?** `sudo app-deploy`.
- **Branch was force-pushed (rebase)?** `app-deploy` stops (`--ff-only`); run `sudo app-branch` and pick the same branch again - it resets to the GitHub version.
- **Done testing?** `sudo app-branch` → `main`.
- **New variables in `.env.example` of the branch?** `app-branch` compares `ENV_EXAMPLE` with `ENV_FILE` and prints the names
  of the missing ones (never values). Ask an admin to add them to `.env`.
- **Branch was merged and deleted on GitHub?** `app-deploy` fails ("no such ref was fetched"): run `sudo app-branch` → `main`.

Things to keep in mind:

- Migrations of the test branch run on the test server's database. Switching back to `main` does **not** roll them back.
- `app-branch` refuses to switch if someone changed files in `/srv/app` by hand.
- Only branches that exist on GitHub can be chosen; the branch name is never typed in.

## The `.env` file

The `.env` does not have to be in the root of the project. If Laravel lives in a
subfolder (for example next to a frontend), point both settings there:

```bash
ENV_EXAMPLE="backend/.env.example"
ENV_FILE="backend/.env"
```

Both are paths inside `APP_DIR`. An absolute path, `..` or an empty value stops
the script with an error (see the checks under [Settings](#settings)).

Right after the project is cloned, `setup.sh`:

1. copies `APP_DIR/ENV_EXAMPLE` → `APP_DIR/ENV_FILE` (only if `ENV_FILE` does not exist yet);
2. sets owner `root:root` and mode `600` - the project directory is readable by every
   user, the secrets are not;
3. warns if `ENV_FILE` is not ignored by git (a `.gitignore` in its own subfolder counts too).

An existing `ENV_FILE` is **never overwritten**: re-running `setup.sh` only fixes its
permissions. If the project has no `ENV_EXAMPLE`, the script warns and you
create the file by hand.

> `ENV_FILE` only tells `setup.sh` and the `app-*` commands where the file is.
> The compose file must use the same file itself. The `app-*` commands run compose
> from the compose file's own directory, so with `backend/compose.prod.yaml` a plain
> `env_file: .env` already means `backend/.env` (and that `.env` also fills `${VAR}` in the file).

The admin then only edits the values:

```bash
sudo vim /srv/app/.env      # APP_DIR/ENV_FILE, e.g. /srv/app/backend/.env
sudo app-deploy
```

`app-deploy` also re-applies `chmod 600` to `ENV_FILE` on every run.

## Users and access

- **New team member:** add `keys/<name>.pub` (lowercase: `a-z`, `0-9`, `-`, `_`, starting with a letter), run `sudo ./setup.sh`.
  The user gets SSH access by key and the `app-*` commands. No password.
- **Remove a team member:** delete their `.pub`, run `sudo ./setup.sh`. Their sessions are
  closed, sudo rules removed, home directory archived to `/var/backups/server_setup/`, then the account is deleted.
  Admins, system accounts and the user running the script are never removed.
- **Admin:** add the name to `ADMIN_USERS`. Admins need a password for `sudo`: `sudo passwd <name>`.

### Storing the keys in git

By default `keys/.gitignore` ignores every `*.pub`, so no one's keys end up in
this public template: you copy them next to `setup.sh` on the server by hand.

If you keep **your own private copy** of this repository and want the keys to
live in it (then a new team member is just `git pull && sudo ./setup.sh` on the
server), delete that file and commit the keys:

```bash
git rm keys/.gitignore
git add keys/*.pub
git commit -m "Add team keys"
```

> ⚠️ Do this only in a **private** repository. A public key cannot be used to log in,
> but the file names are the logins on your server, and anyone who can push to the
> repository can add their own key and get SSH access after the next `sudo ./setup.sh`.
> A GitHub fork of a public repository is always public, so do not fork:
> create a new private repository and push this code there.

## Repository structure

```text
setup.sh            entry point and all settings
keys/               <name>.pub - one public key per user (git-ignored by default, see "Storing the keys in git")
lib/
  common.sh         log/warn/error, exit handler, root check, run lock
  config.sh         write_config: write a file only if changed, with backup
  packages.sh       apt install/remove helpers
  tools.sh          tools installed from install scripts
  system.sh         timezone, automatic updates
  laptop.sh         lid / sleep settings for a laptop server
  users.sh          team users, admins, stale user removal
  ssh.sh            SSH hardening, admin key check
  firewall.sh       UFW
  docker.sh         Docker CE and daemon config
  repo.sh           deploy key, project clone, .env creation
  app.sh            app-* and admin scripts: builds them from templates/
  scripts.sh        install/remove scripts, sudo rules
  systemd.sh, autostart.sh   systemd helpers
templates/
  app-common.sh     helpers shared by the scripts below: lock, branch list, deploy
  app-start.sh, app-stop.sh, app-restart.sh, app-status.sh, app-logs.sh
  app-deploy.sh     body of app-deploy
  app-fetch.sh      body of app-fetch
  app-branch.sh     body of app-branch (installed on a test server only)
  app-update-languages.sh   body of app-update-languages (only with TRANSLATE_SERVICE)
  app-db.sh         body of the admin command app-db
```

### Changing the `app-*` commands

The commands in `/usr/local/bin` are generated on every run of `setup.sh`, so
**do not edit them on the server**: the next run overwrites them.

- Every command (team and admin) is built by `lib/app.sh` from three parts:
  1. the settings (`APP_DIR`, `REPO_BRANCH`, `IS_PRODUCTION`, …) written at the top
     (admin commands start with one more line that re-runs them through `sudo`);
  2. `templates/app-common.sh`;
  3. `templates/<name>.sh`.

To change a command, edit its template and run `sudo ./setup.sh` again. If a
template is missing or has a syntax error, `setup.sh` stops and the installed
command stays as it was.

A new command: add `templates/<name>.sh` and put the name into `APP_SCRIPTS` (team,
run with `sudo`, no arguments) or `ADMIN_SCRIPTS` (admins only).

The templates are normal bash files, so editors highlight them and they can be
checked before a run:

```bash
bash -n setup.sh lib/*.sh templates/*.sh
shellcheck templates/*.sh
```

## Logs and troubleshooting

- Each run writes `/var/log/server_setup_<date>_<time>.log`.
- Two copies of `setup.sh` cannot run at the same time (lock file).
- Replaced config files are backed up to `/var/backups/server_setup/`.
- Effective SSH config: `sudo sshd -T`. Firewall: `sudo ufw status verbose`.
- sudo asks for a password for an `app-*` command → the command was run with arguments (only
  `app-logs <N>` with a number is allowed), or it is not in `APP_SCRIPTS` (e.g. `app-branch` on production).
- `Permission denied` for `app-db` → it is an admin command (`ADMIN_SCRIPTS`), team members cannot run it.

## Changelog

### 1.2.0

- `COMPOSE_FILE` is replaced by **`COMPOSE_FILE_PROD`** / **`COMPOSE_FILE_DEV`**: `IS_PRODUCTION` picks the one
  the `app-*` commands use (an empty `COMPOSE_FILE_DEV` = the production file, as before).
  **Rename the variable** in your copy of `setup.sh`: the old name stops the script with an error.
- Compose now runs from the compose file's own directory (`--project-directory`), so a compose file in a
  subfolder (`backend/compose.prod.yaml`) works with its own relative paths and `.env`. For a compose file
  in the root of `APP_DIR` nothing changes.
  ⚠️ Without `name:` in the compose file the project is named after its folder: moving the file from the
  root into `backend/` starts a new project `backend` with **new, empty volumes** (database included),
  while the old one keeps running. Put `name: app` (the old name) into the file before the move.
- `sudo app-logs <N>`: number of lines on request (`APP_LOGS_TAIL` default, `APP_LOGS_MAX` limit).
- **`app-update-languages`** for the team (only when `TRANSLATE_SERVICE` is set; the variable names are
  `ENV_TRANSLATE_UPDATE_MODELS` / `ENV_TRANSLATE_LANGUAGES`, LibreTranslate's by default).
- **Admin commands** (`ADMIN_SCRIPTS`, `root:sudo 0750`), first one: `app-db`.
- Test server: SSH allows `ssh -L` to `127.0.0.1:<TUNNEL_PORTS>` (empty by default = no forwarding);
  production still allows no forwarding. Unix socket forwarding is now off in both modes.
- Compose files in a subfolder that were written with paths relative to `APP_DIR` (because of the old
  `--project-directory`) must use paths relative to their own folder now.
- Every `app-*` command is built from `templates/<name>.sh`.
- **`FIREWALL_PORTS`**: the ports UFW opens besides SSH (were fixed to 80/443, still the default).
- All path settings are checked at start, the compose files too: `COMPOSE_FILE_PROD`, `COMPOSE_FILE_DEV`,
  `ENV_EXAMPLE` and `ENV_FILE` must be inside `APP_DIR` (no absolute path, no `..`), and only
  `COMPOSE_FILE_DEV` may be empty. The new `APP_LOGS_TAIL` / `APP_LOGS_MAX` and `TUNNEL_PORTS` are checked
  as well. The error names the wrong setting.

### 1.1.2

- **`ENV_FILE`** setting: path of the project's `.env` inside `APP_DIR` (default `.env`), for projects
  where Laravel is in a subfolder (`backend/.env`). Used to create the file, set its `600` permissions,
  check `.gitignore` and find missing variables in `app-branch`. With the default value nothing changes.
- `ENV_EXAMPLE` and `ENV_FILE` are checked at start: an absolute path or `..` stops the script with an error.

### 1.1.1

- The bodies of `app-deploy` / `app-fetch` / `app-branch` moved from heredocs in `lib/app.sh`
  to `templates/*.sh`: normal bash files that `bash -n` and `shellcheck` can check.
  The commands work the same as in 1.1.0.

### 1.1.0

- **`IS_PRODUCTION`** setting: production servers always run `REPO_BRANCH`; test servers get `app-branch`.
- **`app-branch`** (test servers only): interactive branch switch + redeploy, with a check for missing `.env` variables.
- **`app-fetch`**: update the branch list from GitHub and show what is deployed.
- **`.env` is created automatically** from `.env.example` after the clone, with `600 root:root` permissions.
- `app-deploy` / `app-fetch` / `app-branch` share a lock, no parallel deploys.
- `app-deploy` on production switches back to `REPO_BRANCH` if the server was a test server before.
- Fresh server: apt waits for `unattended-upgrades` instead of failing with "Could not get lock".
  `apt-get install/remove` wait up to 10 minutes (`DPkg::Lock::Timeout` in `/etc/apt/apt.conf.d/90lock-timeout`),
  `apt-get update` is retried up to 10 times.
- SSH config check no longer fails when the script is run from the local console
  (`/run/sshd` is created before `sshd -t`).
- A new `SSH_PORT` takes effect right away: on Ubuntu 24.04 `ssh.socket` is regenerated and restarted,
  so the server no longer listens on the old port until a reboot.
- Key file names are checked before users are created: a name `adduser` would reject
  (`Anna.pub`, `john.doe.pub`) stops the script with a clear error instead of a failure visible only in the log.

### 1.0.0

- First version.

## License

MIT, see [LICENSE](LICENSE).
