# ubuntu_server_setup

One script that turns a fresh Ubuntu Server (24.04+) into a ready server for a
Laravel project running in Docker Compose: users from SSH keys, hardened SSH,
firewall, fail2ban, Docker, the project cloned from GitHub, and a small set of
`app-*` commands the team can run with `sudo`, without getting full root access.

The script is **idempotent**: run it again after any change (a new key, a new
setting) and it brings the server to the described state without breaking what
is already there.

**Version:** 1.1.1

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
  - [Repository structure](#repository-structure)
    - [Changing the `app-*` commands](#changing-the-app--commands)
  - [Logs and troubleshooting](#logs-and-troubleshooting)
  - [Changelog](#changelog)
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
6. Hardens SSH: key login only, no root login, no password login.
7. Firewall (UFW): only SSH, 80 and 443 are open. Enables fail2ban.
8. Installs Docker CE + Compose plugin, with log rotation.
9. Clones the project into `APP_DIR` with a read-only deploy key and **creates `.env` from `.env.example`**.
10. Installs the `app-*` scripts and lets team members run them with `sudo`.

## Quick start

```bash
git clone https://github.com/ADONYARIIK/ubuntu_server_setup_public.git
cd ubuntu_server_setup_public

# 1. One public key per person: the file name is the login name
cp ~/admin.pub  keys/admin.pub
cp ~/anna.pub   keys/anna.pub

# 2. Edit the settings block at the top of setup.sh
#    (at least REPO_URL and IS_PRODUCTION)
vim setup.sh

# 3. Run
sudo ./setup.sh
```

After the first run, once:

1. `sudo tailscale up` - authorize the server in Tailscale.
2. Add root's deploy key (printed by the script, `/root/.ssh/deploy_key.pub`) to GitHub:
   project repo → **Settings → Deploy keys** (read-only). If the clone failed because of this, run `sudo ./setup.sh` again.
3. Fill in the real values in `.env`: `sudo vim /srv/app/.env`.
4. First start: `sudo app-deploy`.

> ⚠️ Make sure at least one admin has a key in `keys/` **before** the first run:
> password login over SSH is turned off. The script refuses to continue if no admin has a key.

## Settings

All settings are at the top of `setup.sh`.

| Variable | Default | Description |
|---|---|---|
| `IS_PRODUCTION` | `true` | `true` = production server, `false` = test server (see below) |
| `SSH_PORT` | `22` | SSH port (firewall uses the same value) |
| `ADMIN_USERS` | `("admin")` | Users with full `sudo`. Need a key in `keys/` or an existing account with `authorized_keys` |
| `TEAM_GROUP` | `team` | Group that marks users created from `keys/`. Only its members can be removed automatically |
| `TIMEZONE` | `Europe/Warsaw` | Server timezone |
| `APP_DIR` | `/srv/app` | Where the project is cloned |
| `COMPOSE_FILE` | `compose.prod.yaml` | Compose file inside the project |
| `APP_SERVICE` | `app` | Laravel service name (used for `php artisan`) |
| `APP_SCRIPTS` | `app-start … app-fetch` | Scripts the team may run with `sudo` (`app-branch` is added automatically on a test server) |
| `REPO_URL` | `git@github.com:USER/REPO.git` | SSH URL of the project |
| `REPO_BRANCH` | `main` | Main branch: cloned first, the only one on production |
| `DEPLOY_KEY` | `/root/.ssh/deploy_key` | Root's private key for GitHub |
| `ENV_EXAMPLE` | `.env.example` | Template `.env` is created from (path inside `APP_DIR`) |

## Production vs test server (`IS_PRODUCTION`)

| | `IS_PRODUCTION=true` (production) | `IS_PRODUCTION=false` (test) |
|---|---|---|
| Branch | always `REPO_BRANCH` | any branch from GitHub |
| `app-branch` | **does not exist** (file and sudo rule removed) | installed, available to the team |
| `app-deploy` | switches back to `REPO_BRANCH` if needed, then deploys | deploys the current branch |
| `app-fetch` | available | available |

Any value other than `true` / `false` stops the script with an error, so a typo
(`True`, `yes`) never picks a mode silently.

You can change the mode at any time: edit the variable and run `sudo ./setup.sh`
again. When a test server becomes production, `app-branch` is deleted and the
next `sudo app-deploy` returns the code to `REPO_BRANCH`.

## Commands for the team

Team members (every `keys/*.pub` except admins) can run exactly these commands
with `sudo`, **without arguments**, and nothing else as root:

| Command | What it does |
|---|---|
| `sudo app-start` | Start the containers (`up -d`) |
| `sudo app-stop` | Stop the containers |
| `sudo app-restart` | Restart the containers |
| `sudo app-status` | Container status (`ps`) |
| `sudo app-logs` | Last 200 log lines |
| `sudo app-deploy` | `git pull` → build → recreate containers → `migrate --force` → `optimize` |
| `sudo app-fetch` | Update the branch list from GitHub, show the current branch and whether it is behind |
| `sudo app-branch` | **Test server only.** Pick a branch from a list, switch to it and redeploy |

`app-deploy`, `app-fetch` and `app-branch` share one lock: if someone else is
deploying right now, the second command stops with a message instead of
mixing up two builds.

Read-only git commands work without `sudo`, e.g. `git -C /srv/app log --oneline -5`.

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
- **New variables in `.env.example` of the branch?** `app-branch` prints their names (never values). Ask an admin to add them to `.env`.
- **Branch was merged and deleted on GitHub?** `app-deploy` fails ("no such ref was fetched"): run `sudo app-branch` → `main`.

Things to keep in mind:

- Migrations of the test branch run on the test server's database. Switching back to `main` does **not** roll them back.
- `app-branch` refuses to switch if someone changed files in `/srv/app` by hand.
- Only branches that exist on GitHub can be chosen; the branch name is never typed in.

## The `.env` file

Right after the project is cloned, `setup.sh`:

1. copies `APP_DIR/.env.example` → `APP_DIR/.env` (only if `.env` does not exist yet);
2. sets owner `root:root` and mode `600` - the project directory is readable by every
   user, the secrets are not;
3. warns if `.env` is not listed in the project's `.gitignore`.

An existing `.env` is **never overwritten**: re-running `setup.sh` only fixes its
permissions. If the project has no `.env.example`, the script warns and you
create `.env` by hand.

The admin then only edits the values:

```bash
sudo vim /srv/app/.env
sudo app-deploy
```

`app-deploy` also re-applies `chmod 600` on every run.

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
  app.sh            app-* scripts: builds them from templates/
  scripts.sh        install/remove scripts, sudo rules
  systemd.sh, autostart.sh   systemd helpers
templates/
  app-common.sh     helpers shared by the scripts below: lock, branch list, deploy
  app-deploy.sh     body of app-deploy
  app-fetch.sh      body of app-fetch
  app-branch.sh     body of app-branch (installed on a test server only)
```

### Changing the `app-*` commands

The commands in `/usr/local/bin` are generated on every run of `setup.sh`, so
**do not edit them on the server**: the next run overwrites them.

- `app-start`, `app-stop`, `app-restart`, `app-status`, `app-logs` are one-line
  `docker compose` calls in `lib/app.sh`.
- `app-deploy`, `app-fetch`, `app-branch` are built by `lib/app.sh` from three parts:
  1. the settings (`APP_DIR`, `REPO_BRANCH`, `IS_PRODUCTION`, …) written at the top;
  2. `templates/app-common.sh`;
  3. `templates/<name>.sh`.

To change a command, edit its template and run `sudo ./setup.sh` again. If a
template is missing or has a syntax error, `setup.sh` stops and the installed
command stays as it was.

The templates are normal bash files, so editors highlight them and they can be
checked before a run:ц

```bash
bash -n setup.sh lib/*.sh templates/*.sh
shellcheck templates/*.sh
```

## Logs and troubleshooting

- Each run writes `/var/log/server_setup_<date>_<time>.log`.
- Two copies of `setup.sh` cannot run at the same time (lock file).
- Replaced config files are backed up to `/var/backups/server_setup/`.
- Effective SSH config: `sudo sshd -T`. Firewall: `sudo ufw status verbose`.
- sudo asks for a password for an `app-*` command → the command was run with arguments, or it is not in `APP_SCRIPTS` (e.g. `app-branch` on production).

## Changelog

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
