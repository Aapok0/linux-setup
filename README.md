# Linux Setup

Scripts to set up my preferred environment on Arch, Debian, or Fedora based distributions.

## What it does

The setup script detects (or accepts as argument) whether the system is Arch, Debian, or Fedora based, then:

1. Updates system packages
2. Checks for existing firewalls and installs/enables `ufw` if none found
3. Creates `~/Workspace` and clones [dotfiles](https://github.com/Aapok0/dotfiles) (converted to SSH remote)
4. Runs dotfiles `justfile` (`just install`) which handles core tools, shell setup (ZSH, plugins, starship), font installation, stowing configs, and more
5. Installs additional packages not covered by the justfile (see `vars/`)
6. Prompts for git user configuration (`~/.config/git/config.local`)
7. Installs KDE Plasma packages, apps, and gaming packages
8. Sets up NordVPN with systemd-resolved
9. Registers Steam Tinker Launch as a Steam compatibility tool

**Arch-specific:** Enables multilib, installs `paru` (AUR helper), configures btrfs Snapper rollback (when root is btrfs).

**Debian-specific:** Installs `nala` and apt tools, installs `pyenv`/`nvm`/`tfswitch` manually (no AUR), adds NordVPN repo.

**Fedora-specific:** Enables RPM Fusion, installs packages from `dnf_*`, `rpmfusion_*`, and `flatpak_*` groups in `vars/fedora-vars`, configures btrfs Snapper (when root is btrfs), installs `pyenv`/`nvm`/`tfswitch` manually, adds NordVPN repo.

Setup scripts are safe to re-run: package installs skip already-installed packages, and shared helpers in `scripts/lib/common.sh` guard groups, systemd units, multilib, and pip user installs. System upgrades (`paru -Syu`, `apt upgrade`, `dnf upgrade`) still run each time.

Output is logged to `logs/<timestamp>_setup.log` (absolute path under repo root).

**Logging:** All scripts source `scripts/lib/common.sh` for shared logging (`INFO`, `OUT`, `WARN`, `ERROR`, `RUN` levels with timestamps). Logs are written to `logs/` via `tee` regardless of current working directory.

## Repository structure

```
├── setup                       # Entry point — post-install setup (detects distro)
├── install                     # Entry point — Arch install / reinstall / backup
├── scripts/
│   ├── lib/
│   │   ├── common.sh           # Shared logging and setup helpers
│   │   └── install.sh          # Shared Arch install/reinstall helpers
│   ├── setup-arch              # Full Arch (KDE) setup
│   ├── setup-debian            # Full Debian (KDE) setup
│   ├── setup-fedora            # Full Fedora (KDE) setup
│   ├── setup-arch-i3           # Older i3-based Arch setup (unused)
│   ├── install-arch            # Arch Linux fresh install (live ISO)
│   ├── install-arch-reinstall  # Arch reinstall (preserves /home)
│   └── install-arch-backup     # Arch reinstall config backup (live system)
├── vars/
│   ├── arch-vars               # Package lists for Arch (pacman & paru/AUR)
│   ├── debian-vars             # Package lists for Debian (apt & extras)
│   └── fedora-vars             # Package lists for Fedora (dnf & extras)
├── instructions/
│   ├── install/                # Arch, Debian & Fedora install guides
│   └── post-install/           # App-specific settings & configuration notes
├── apps.md                     # App decision log (done / not done / to investigate)
└── logs/                       # Created at runtime (gitignored)
```

## Prerequisites

- A working internet connection
- `git` available to clone this repo and dotfiles
- **Arch:** `base-devel` installed (needed to build `paru`)
- **Debian:** `sudo` and `apt` working
- **Fedora:** `sudo` and `dnf` working

## Pre-setup

Optional: allow passwordless sudo by editing sudoers safely:

```bash
sudo visudo
# or with vim:
sudo VISUAL=vim visudo
```

Add to the end of the file:

```
your_username ALL=(ALL:ALL) NOPASSWD: ALL
```

## Usage

1. Clone this repo and enter the directory.

2. Make scripts executable, if not already:

```bash
chmod u+x setup install scripts/*
```

3. Run:

```bash
./setup
# or explicitly:
./setup arch
./setup debian
./setup fedora
```

The script auto-detects the distro from `/etc/os-release`. Pass `arch`, `debian`, or `fedora` manually if detection fails.

### Arch install

Entry point: `./install arch`

**Fresh install (live ISO, as root):**

```bash
./install arch
```

Destroys target disks. Automates `instructions/install/arch-install.md`: partitioning, optional LUKS encryption, LVM, btrfs subvolumes, pacstrap, boot setup (GRUB/mkinitcpio), localization, user creation, KDE Plasma, and optional reboot.

**Reinstall (live ISO, as root):**

```bash
./install arch --reinstall
```

Preserves `/home`, reformats root only, restores boot configs from backup, recreates users, installs KDE Plasma.

**Config backup (running system, before rebooting to live ISO):**

```bash
sudo ./install arch --backup
```

Copies `/etc` configs to `~/install/etc/` for reinstall restore (see `instructions/install/arch-reinstall.md`).

Logs: `logs/<timestamp>_install-arch.log`, `_install-arch-reinstall.log`, or `_install-arch-backup.log`.

## Post-setup

These steps are also printed by the script on completion:

1. Reboot the machine.
2. Open Ghostty (terminal emulator).
3. If a firewall was already installed, check its rules.
4. Install nvm and Node.js:
   ```bash
   # Get install command from: https://github.com/nvm-sh/nvm#installing-and-updating
   exec zsh
   nvm install node
   ```
5. Set up Python with pyenv:
   ```bash
   pyenv install -l | less
   pyenv install <version>
   pyenv global <version>
   mkdir -p ~/Python && cd ~/Python
   python -m venv <name>
   ```
6. Open Neovim if you want to verify plugins (`just install` already syncs Lazy.nvim and Mason tools).
7. Open tmux and install plugins: `tmux` then `ctrl+space I` (TPM runs during `just install`; reload tmux config if needed).

## Unfinished / TODO

- **`apps.md`** — Several apps still marked as not done (app launcher, tiling WM, Docker, RDP, mouse/keyboard tools, etc.).
- Configurable package selection (interactive options)
- Clean package caches at the end?
