<div align="center">

# debkit

**Secure administration of Debian servers, by menu or by commands — starting with a Samba file server.**

🇧🇷 [Português](README.md) · 🇬🇧 English

![Debian 12/13](https://img.shields.io/badge/Debian-12%20%7C%2013-A81D33?logo=debian&logoColor=white)
![Bash](https://img.shields.io/badge/made%20with-Bash-4EAA25?logo=gnubash&logoColor=white)
![Samba](https://img.shields.io/badge/Samba-standalone%20%2B%20tdbsam-1E73BE)
![MIT License](https://img.shields.io/badge/license-MIT-blue)
[![CI](https://github.com/ThiagoCarrere/debkit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ThiagoCarrere/debkit/actions/workflows/ci.yml)

</div>

---

**debkit** is a kit of administration modules for Debian servers. You pick
what you want to do in a menu (or run a command) and it takes care of the
rest: it validates first, shows what is going to happen, asks for **one**
confirmation, checks the result and **undoes** everything if something
fails halfway.

The first module, **samba**, manages a complete file server: users, groups,
home folders, shares and permissions.

> [!NOTE]
> Phases 0 to 4 are complete (see the [roadmap](#roadmap)). As with any
> tool that changes the server, try it on a virtual machine first.

## Why debkit

On a file server, almost every user only needs to open folders from
Windows — and should not be able to log into the server. Doing that right
by hand takes work and it is easy to miss a detail. debkit does it by
default:

| | File user (default) | User with server access |
|---|---|---|
| Folders over Samba | ✅ | ✅ |
| Linux password | 🔒 locked | its own |
| Shell | `nologin` | `/bin/bash` |
| SSH (tunnels included) | ❌ refused by debkit | ✅ allowed by an administrator |

## Highlights

- 🛡️ **Secure by default** — passwords never show on screen, in the log or
  on the command line; **system** users and groups are never touched (they
  do not even appear in the lists); debkit refuses to load code that
  someone else could change.
- ↩️ **All or nothing** — every operation checks the real result and, if
  something fails halfway, undoes what it had already done.
- ⚡ **Effective immediately** — added someone to a group? The folder opens
  right away. Removed them? Access is gone right away, even for whoever was
  connected (debkit only resets that person's session; Windows reconnects
  by itself).
- 🧰 **Sets the server up by itself** — installs what is missing, turns off
  what gets in the way (domain packages, password sync from Windows),
  applies the SSH block and, if ufw or firewalld is blocking Samba, opens
  only port 445 and only to the local networks. Always showing the plan
  first.
- 💾 **Traceable** — automatic backup (with rotation) before any change and
  an audit log: who did what and when.
- ⌨️ **Menu or commands** — everything the menu does also exists as a
  direct command, for scripts and cron, with the same validations and
  confirmations (`--yes` answers for you).
- 🌐 **Portuguese and English** — it speaks the system's language.
- 🔍 **Warns you about what you would not see** — when removing a group or
  deleting a user, it shows who loses access, where it is used in
  `smb.conf` and how many files stay on disk.

## What it does

| Area | Functions |
|---|---|
| **Environment** | full check (system, Samba, SSH, firewall) and guided setup, with a plan and a confirmation; Samba authentication log (successful and failed logins) with rotation |
| **SSH protection** | its own file in `sshd_config.d` (`sshd_config` is not touched), validated before reloading, without dropping sessions |
| **Users** | create (two account types, full name, groups, home folder), list, change password, delete, check and fix accounts |
| **Groups** | create, list, add/remove members with immediate effect, remove |
| **Home folders** | on the data disk (backed up with the rest), at creation or later, and the `[homes]` share |
| **Shares** | list (including hand-made ones, with alerts), create bound to a group whose members get full access (folder in `/mnt` or `/srv`), change the group, adjust the content permissions, remove (the files stay on disk) and bring hand-made ones to the pattern |
| **Diagnostics** | active sessions (who is connected, from which machine, open files) and disconnecting a session; logins (failures with the reason and each user's last login); health report (service, port, disk, alerts); audit query (by period, affected item and type) |
| **Direct commands** | every menu action from the command line (`debkit samba <group> <action>`), passwords from standard input, exit codes 0/1/2 for scripts |
| **Installation** | `install.sh` (installs; updates by swapping the folder at once, only if the new one works) and `debkit --uninstall` (users and shares stay) |

## Installation

```bash
git clone https://github.com/ThiagoCarrere/debkit.git
cd debkit
sudo ./install.sh        # installs in /opt/debkit and creates the "debkit" command
sudo debkit              # menu: the first time, it sets up the server
```

The installer copies only the program to `/opt/debkit` (owned by root, no
write for group/others: debkit refuses to load code that someone else
could change), creates the command `/usr/local/sbin/debkit` and offers to
set up the server. If you clone straight into `/opt/debkit`, it only
creates the command. The configuration lives in `/etc/debkit/debkit.conf`
(commented template in [`debkit.conf.exemplo`](debkit.conf.exemplo)).

- **Update:** `git pull` and `sudo ./install.sh` again (the new version
  only takes the place of the old one if it works).
- **Check without changing anything:** `sudo debkit --check`.
- **Uninstall:** `sudo debkit --uninstall` removes the program and the
  command; with `--all`, also the configuration, the log and the backups.
  Users, groups, shares and `smb.conf` stay, and the SSH protection is only
  removed if there are no file users.

## Direct commands

The same actions as the menu, for scripts and cron (full list:
`debkit samba --help`):

```bash
sudo debkit samba user list
printf '%s\n' "$PASSWORD" | sudo debkit samba user create ana --name "Ana Souza" --groups finance --yes
sudo debkit samba group members finance --add pedro --yes
sudo debkit samba share create finance --group finance --yes
sudo debkit samba diagnostics health         # exits with 1 if there is a problem
sudo debkit samba diagnostics audit --days 7 --type users
```

Passwords never go on the command line: they are asked (no echo) or read
from standard input. Without `--yes`, the command shows the summary and
asks, like the menu. Exit: 0 ok, 1 refused/cancelled/failed, 2 incorrect
usage. The Portuguese names also work (`debkit samba usuario criar ...`).

## Language

Portuguese or English, from the system's language (`LANG`/`LANGUAGE`). To
pin it: `IDIOMA=pt_BR` or `IDIOMA=en` in `debkit.conf`.

## Quality

- **More than 2,600 automated checks** in a sandbox: log, configuration,
  `smb.conf`, the Samba password database and packages are isolated. A
  guard compares the real system before and after each test file and fails
  on any leak.
- **Real proofs** (`DEBKIT_TESTE_REAL=1`; more than 450 checks), with real
  Samba, SSH and ufw: login, SSH tunnel refused, access by group, an open
  session losing access right away.
- **CI on every push:** on a fresh Debian 13 (a container with systemd),
  debkit itself sets the server up (installs Samba), the whole suite runs
  and debkit is installed, used and uninstalled for real.
- `shellcheck` with no warnings.

```bash
sudo tests/run.sh                                           # normal suite
sudo DEBKIT_TESTE_REAL=1 tests/run.sh t13b_grupos_real.sh   # one real proof
```

## Roadmap

| Phase | Content | |
|---|---|---|
| 0. Foundation | environment detection and setup, backups, SSH protection, firewall | ✅ |
| 1. Users and groups | users, home folders, groups, Linux x Samba consistency | ✅ |
| 2. Shares | create, list, folder permissions, remove, existing ones | ✅ |
| 3. Diagnostics | login failures, active sessions, Samba health, audit | ✅ |
| 4. Publishing | CI, log rotation, direct commands, installer and uninstall, Portuguese and English | ✅ |

The decisions and the reason for each one are in the
[planning document](docs/PLANEJAMENTO.md) (in Portuguese); the changes, in
the [CHANGELOG](CHANGELOG.md).

## Development

Everything is written and tested on a Debian 13 VM with snapshots. Scripts
in [`dev/`](dev/) (the VM ones refuse a machine that is not virtual):

```bash
sudo dev/vmnova.sh --simular   # shows the snapshot and the command, does nothing
sudo dev/vmnova.sh             # goes back to the "limpa" Timeshift snapshot and REBOOTS
sudo dev/vmprepara.sh          # then: installs shellcheck, smbclient and ufw (inactive)
sudo dev/ci.sh                 # the suite on a fresh Debian 13, in a container (like the CI)
```

Structure: `debkit` (entry point), `lib/nucleo.sh` (common core) and
`modulos/*.sh` (one file per module; new modules come in just by placing
the file in the folder).

## Compatibility

Made for **Debian 12 and 13**. Ubuntu, a Debian derivative, tends to work.
Samba in **standalone server** mode (`tdbsam` database); a domain
controller (AD DC) is not supported.

## Authors

Developed by **Thiago Carrere** in partnership with **Claude** (Anthropic).

## License

[MIT](LICENSE)
