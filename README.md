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

**Arch-specific:** Enables multilib, installs `paru` (AUR helper).

**Debian-specific:** Installs `nala` and apt tools, installs `pyenv`/`nvm`/`tfswitch` manually (no AUR), adds NordVPN repo.

**Fedora-specific:** Enables RPM Fusion, installs packages from `dnf_*`, `rpmfusion_*`, and `flatpak_*` groups in `vars/fedora-vars`, installs `pyenv`/`nvm`/`tfswitch` manually, adds NordVPN repo.

Output is logged to `logs/<timestamp>_setup.log`.

## Repository structure

```
├── setup                       # Entry point — detects distro and dispatches
├── scripts/
│   ├── setup-arch              # Full Arch (KDE) setup
│   ├── setup-debian            # Full Debian (KDE) setup
│   ├── setup-fedora            # Full Fedora (KDE) setup
│   ├── setup-arch-i3           # Older i3-based Arch setup (unused)
│   └── install-arch            # Arch Linux installation script (partitioning, etc.)
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

2. Make scripts executable:

```bash
chmod u+x setup scripts/*
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
6. Open Neovim and install Mason tools:
   ```bash
   nvim
   # Let lazy.nvim install plugins, then run:
   # :MasonInstall shellcheck shfmt stylua prettier ruff hadolint tflint ansible-lint
   ```
7. Open tmux and install plugins: `tmux` then `ctrl+space I`.

## Unfinished / TODO

- **`install-arch`** — Arch installation (partitioning/formatting) script; work in progress.
- **`apps.md`** — Several apps still marked as not done (app launcher, tiling WM, Docker, RDP, mouse/keyboard tools, etc.).
- Swap file creation (with hibernation?)
- Configurable package selection (interactive options)
- Clean package caches at the end?
