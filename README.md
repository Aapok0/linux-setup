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
8. Installs Cursor IDE (official vendor repo on Fedora/Debian; official `.deb` extract on Arch)
9. Sets up NordVPN with systemd-resolved

**Arch-specific:** Enables multilib, installs `paru` (AUR helper), configures btrfs Snapper rollback (when root is btrfs). Desktop apps use **extra**, **Flatpak**, vendor installs (Cursor), or a small reviewed AUR set as needed. Set `PARU_SKIP_REVIEW=1` only for CI/containers. Audit installed vs expected AUR packages:

```bash
./scripts/aur-audit.sh   # full profile; PKGBUILDs in logs/<timestamp>_aur-audit.log; exit 1 on fetch failure
./scripts/aur-audit.sh --headless   # match LINUX_SETUP_HEADLESS=1 setup footprint
```

**Debian-specific:** Installs `nala` and apt tools, `ghostty` via [debian.griffo.io](https://ghostty.org/docs/install/binary#debian), Cursor via official APT repo, `pyenv`/`nvm` manually (no AUR), adds NordVPN repo.

**Fedora-specific:** Enables RPM Fusion, installs packages from `dnf_*`, `rpmfusion_*`, and `flatpak_*` groups in `vars/fedora-vars`, configures btrfs Snapper (when root is btrfs), `ghostty` via COPR `scottames/ghostty`, Firefox Wayland (`MOZ_ENABLE_WAYLAND=1`), Cursor via official DNF repo, system-scope Flatpak installs, `pyenv`/`nvm` manually, adds NordVPN repo. Skips `power-profiles-daemon` when `tuned-ppd` is installed.

Setup scripts record errors in a counter (`SETUP_ERRORS`) and exit non-zero at the end if any step failed; interactive prompts are not aborted by `set -e`.

Setup scripts are safe to re-run: package installs skip already-installed packages, and shared helpers in `scripts/lib/common.sh` guard groups, systemd units, multilib, pip user installs, systemd-resolved (including existing `/etc/resolv.conf` symlinks), and Snapper access settings (only empty `ALLOW_USERS` / non-`yes` `SYNC_ACL` are filled in; customized values and `TIMELINE_CREATE` on existing home configs are left alone). System upgrades (`paru -Syu`, `apt upgrade`, `dnf upgrade`) still run each time.

Output is logged to `logs/<timestamp>_setup.log` (absolute path under repo root).

**Logging:** All scripts source `scripts/lib/common.sh` for shared logging (`INFO`, `OUT`, `WARN`, `ERROR`, `RUN` levels with timestamps) and post-install setup helpers. Arch install orchestration lives in `scripts/lib/install.sh`. Logs are written to `logs/` via `tee` regardless of current working directory.

## Repository structure

```
├── setup                       # Entry point — post-install setup (detects distro)
├── install                     # Entry point — Arch install / reinstall / backup
├── scripts/
│   ├── lib/
│   │   ├── common.sh           # Shared logging and setup helpers
│   │   └── install.sh          # Shared Arch install/reinstall helpers
│   ├── setup-arch.sh           # Full Arch (KDE) setup
│   ├── setup-debian.sh         # Full Debian (KDE) setup
│   ├── setup-fedora.sh         # Full Fedora (KDE) setup
│   ├── install-arch.sh         # Arch Linux fresh install (live ISO)
│   ├── install-arch-reinstall.sh  # Arch reinstall (preserves /home)
│   └── install-arch-backup.sh  # Arch reinstall config backup (live system)
├── tests/
│   ├── run                     # Test entrypoint (container / install / vm)
│   ├── container/              # Stubbed setup-* smoke (CI)
│   ├── install/                # install-arch loopback + ISO VM harness
│   └── vm/                     # Vagrant headless setup-* smoke
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

Or uncomment line for wheel group that has NOPASSWD:

```
%wheel ALL=(ALL) NOPASSWD: ALL
```

And add your user to wheel group:

```bash
sudo usermod -a -G wheel your_username
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

## Testing locally

Linting and a stubbed end-to-end smoke run can be done locally; the same lint
checks run in CI (`.github/workflows/lint.yml`, pinned `shellcheck`/`shfmt`).

### Lint & format

```bash
bash -n scripts/*.sh                  # quick parse check, no tools needed
shellcheck -x setup install tests/run scripts/*.sh scripts/lib/*.sh tests/**/*.sh
shfmt -d -i 4 -ci setup install tests/run scripts/*.sh scripts/lib/*.sh tests/**/*.sh
```

Repo-specific `shellcheck` disables (cross-file globals, sourced helpers, the
`install-arch.sh`/`install.sh` call graph) are documented in `.shellcheckrc`.

### Test layout

```
tests/run                 # entrypoint (no extension)
tests/container/          # stubbed setup-* smoke (CI)
tests/install/            # install-arch loopback + libvirt ISO harness
tests/vm/                 # Vagrant headless setup-* smoke (local/self-hosted)
```

### Container smoke tests

`tests/run container smoke` runs each `setup-<distro>.sh` script end to end inside
a throwaway container with every privileged/network command stubbed
(`tests/container/stub.sh`). It catches what static analysis cannot: unbound
variables, bad substitutions, runtime control flow, wrong flags,
distro-detection branches, and the order of privileged calls.

```bash
tests/run container smoke            # all three distros (uses docker)
tests/run container smoke debian       # one distro
tests/run container source             # lighter tier: source libs + vars, assert key fns
RUNTIME="sudo docker" tests/run container smoke
RUNTIME=podman tests/run container smoke
```

- No privilege is needed for the setup smoke — the stubs turn `sudo`,
  `systemctl`, and the package managers into no-ops.
- A non-zero script exit is **expected** (stubbed steps bump `SETUP_ERRORS`); a
  run passes when it reaches completion with no fatal shell errors.
- Only the distro base images are required; they pull on first run.

### Arch install testing

`tests/run install loopback` runs the real `install-arch.sh` against loop-backed
image files, so partitioning, LVM, btrfs subvolumes and mounting are exercised
**for real** — only the chroot/Arch/network commands that can't run on a generic
host are stubbed (`arch-chroot`, `pacstrap`, `genfstab`, `reflector`, `reboot`,
`ping`). It needs root for loop devices, LVM and mounts, and only ever touches
its own throwaway images and uniquely-named volume groups (`archsmoke*`).

```bash
sudo tests/run install loopback              # all scenarios
sudo tests/run install loopback partition    # swap partition, root=all, separate /home
sudo tests/run install loopback lvm          # swap as an LVM logical volume, root=all
sudo tests/run install loopback sized        # swap partition + explicit root size
sudo tests/run install loopback samedevice   # root + home on one device, both sized
```

Host tools required: `parted lvm2 btrfs-progs dosfstools e2fsprogs util-linux`.

Coverage and limits:

- `sized` exercises an explicit root size (the swap-offset partition
  arithmetic); `samedevice` puts root and home on one disk (the absolute home
  end computation); `partition`/`lvm` use `root=all` with a separate `/home`.
- Encryption (LUKS) is skipped — its interactive `cryptsetup` passphrase flow is
  left to manual/VM testing.
- This validates everything short of an actual **boot**. Verifying GRUB,
  initramfs, LUKS unlock and EFI still requires a VM (e.g. QEMU).

CI runs this on every PR that touches scripts/tests/workflows (the
`arch install (loopback)` job in `.github/workflows/smoke-test.yml`).

### VM smoke tests (setup-*)

Automated **headless** provisioning of `setup-debian.sh`, `setup-fedora.sh`, and
`setup-arch.sh` inside libvirt VMs via Vagrant. Exercises real package managers,
`just install`, docker, and the virt stack — not KDE, flatpaks, or gaming.
Intended for local or self-hosted pre-merge checks (nested virt, long runtime;
not GitHub-hosted CI).

#### Prerequisites

```bash
# Nested virtualization enabled on the host
# Fedora/Debian: distro package (also installed by setup-* virt_packages)
sudo dnf install vagrant vagrant-libvirt      # Fedora
sudo apt install vagrant vagrant-libvirt      # Debian
# Arch: vagrant is AUR-only (virt_packages_aur); plugin not in repos
paru -S vagrant
vagrant plugin install vagrant-libvirt
```

#### Basic flow (first run)

```bash
# 1. Create VM from cloud box, run headless setup, run assert checks (~15–45 min)
tests/run vm test debian # or fedora/arch

# Equivalent steps:
vagrant up debian --provision          # downloads box, runs tests/vm/provision.sh
vagrant ssh debian -c 'bash /vagrant/tests/vm/assert.sh'
```

What happens:

1. **Host:** `vagrant up` boots a minimal cloud image (no desktop).
2. **Provisioner** (`tests/vm/provision.sh`) sets `LINUX_SETUP_NONINTERACTIVE=1` and
   `LINUX_SETUP_HEADLESS=1`, pre-seeds git config, runs `scripts/setup-<distro>.sh`.
3. **Assert** (`tests/vm/assert.sh`) checks a small set of binaries/paths and that
   the setup log has no `SETUP_ERRORS` summary.

Environment flags (set automatically by `tests/vm/provision.sh`):

| Variable | Effect |
|----------|--------|
| `LINUX_SETUP_NONINTERACTIVE=1` | Auto-answer wheel-sudo (yes), skip hostname/git prompts when pre-seeded |
| `LINUX_SETUP_HEADLESS=1` | Skip KDE/gaming/flatpak/VPN/pyenv/nvm; keep core packages, dotfiles, docker, virt |
| `PARU_SKIP_REVIEW=1` | Arch only: pass `--skipreview` to `paru` (CI/containers; default is PKGBUILD review) |

Optional overrides: `LINUX_SETUP_GIT_NAME`, `LINUX_SETUP_GIT_EMAIL`, `LINUX_SETUP_HOSTNAME`.

#### Snapshot flow (iterating without full reprovision)

After a **passing** run, save a checkpoint; restore it when the VM has been mutated.

```bash
# 2. Save baseline (once, after tests/run vm test debian succeeds)
tests/run vm snapshot-save clean debian

# 3. Iterate: reprovision or assert only
tests/run vm provision debian
tests/run vm assert debian

# 4. Reset disk to the saved baseline (~minutes, not a full reinstall)
tests/run vm snapshot-restore clean debian
```

| Command | What it does | When to use |
|---------|----------------|-------------|
| `tests/run vm test` | `up --provision` + assert | First run, or after `destroy` |
| `tests/run vm provision` | Re-run shell provisioner only | Changed setup script / provisioner |
| `tests/run vm assert` | SSH assert script only | Quick check after manual tweaks |
| `tests/run vm snapshot-save clean` | `vagrant snapshot save` | After a known-good state |
| `tests/run vm snapshot-restore clean` | `vagrant snapshot restore` | Undo package/config drift |
| `tests/run vm destroy` | Delete VM and disks | Start completely fresh |

**Destroy vs snapshot:** `destroy` + `tests/run vm test` always works — re-downloads
nothing if the box is cached, but re-runs the full provisioner (upgrade, dotfiles
clone, `just install`, docker, virt). That is the reliable clean-room path.
Snapshots skip the expensive middle: restore rewinds the disk to the saved point
so you can re-provision or re-assert without reinstalling from scratch. They are
optional; provider support required; not used in CI.

#### Full desktop VM flow

Full desktop / login verification (SPICE, manual checklist):
[instructions/tests/](instructions/tests/).

### install-arch VM (local boot validation)

Loopback smoke (`tests/install/loopback-smoke.sh`) exercises disk logic; a
libvirt VM adds real ISO boot, pacstrap, and bootloader validation:

```bash
export ARCH_ISO=/path/to/archlinux.iso
tests/run install vm create
tests/run install vm console
# on live ISO: clone repo, then:
sudo LINUX_SETUP_LOGGING=1 ./install arch < tests/install/arch-vm.answers
```

See `tests/run install vm help` for `start`, `destroy`, and `answers`.

## Post-setup

These steps are also printed by the script on completion:

1. Reboot the machine.
2. Open Ghostty (terminal emulator).
3. Open Cursor (`cursor` in app menu or terminal).
4. If a firewall was already installed, check its rules.
5. Install nvm and Node.js:
   ```bash
   # Get install command from: https://github.com/nvm-sh/nvm#installing-and-updating
   exec zsh
   nvm install node
   ```
6. Set up Python with pyenv:
   ```bash
   pyenv install -l | less
   pyenv install <version>
   pyenv global <version>
   mkdir -p ~/Python && cd ~/Python
   python -m venv <name>
   ```
7. Open Neovim if you want to verify plugins (`just install` already syncs Lazy.nvim and Mason tools).
8. Open tmux and install plugins: `tmux` then `ctrl+space I` (TPM runs during `just install`; reload tmux config if needed).

## Unfinished / TODO

- **`apps.md`** — Several apps still marked as not done (app launcher, tiling WM, Docker, RDP, mouse/keyboard tools, etc.).
- Configurable package selection (interactive options)
