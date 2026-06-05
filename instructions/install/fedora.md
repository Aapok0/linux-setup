# Fedora manual install guide

For installing Fedora with my personal preferences via the Anaconda installer.

Target: Fedora 42+ amd64, **Fedora KDE Plasma Spin** ISO. Steps follow the order shown in the Anaconda Web UI installer.

## Boot installer

1. Boot the Fedora KDE Plasma Spin live image (UEFI)
2. Choose **Try Fedora** (live session)
3. Launch **Install to Hard Drive** from the desktop

## Welcome

1. Language → **English (United States)**
2. Continue

## Keyboard

- Layout → **Finnish**

## Time & date

1. Region → **Europe/Helsinki**
2. Enable **Network Time** (uses `systemd-timesyncd`)

## Windows dual boot — prepare before partitioning

Skip this section on a dedicated Linux disk. Required when installing Fedora **alongside Windows on the same drive**.

### Install order

Install **Windows first**, then Fedora. Windows overwrites the shared EFI boot chain if installed after Linux.

### In Windows (before Fedora install)

1. **Back up** important data
2. **Disable Fast Startup**
   - Control Panel → Power Options → **Choose what the power buttons do**
   - **Change settings that are currently unavailable**
   - Uncheck **Turn on fast startup**
   - Full shutdown (not “Restart” with Fast Startup): `shutdown /s /t 0` in an elevated Command Prompt
3. **BitLocker** (if enabled — common on Windows 11 Pro)
   - Suspend BitLocker for the install, or decrypt the Windows partition temporarily
   - Linux installer cannot shrink a BitLocker-encrypted volume safely
   - Re-enable after Fedora is installed and verified
4. **Shrink Windows partition** — create unallocated space for Fedora
   - `Win + R` → `diskmgmt.msc`
   - Right-click Windows partition (usually `C:`) → **Shrink Volume**
   - Allocate **≥ 80 GiB** (81920 MiB) for Fedora; more if you install games or dev tools
   - Leave resulting space as **Unallocated** — do not create a new Windows volume there
5. **Optional:** note existing **EFI System Partition** size (usually 100–260 MiB). Fedora reuses it; do not delete it

### Firmware

- UEFI boot mode (not legacy BIOS)
- **Secure Boot** can stay enabled for Fedora; disable only if install media or NVIDIA drivers fail to boot

## Installation destination

Do **not** choose **Use entire disk** when dual-booting. That wipes Windows.

### Single disk, Linux only

1. Select the target disk
2. **Use entire disk** — acceptable only when the disk has no data to keep
3. **Encrypt my data** → enable for LUKS (recommended); set passphrase when prompted
4. Accept the automatic btrfs layout Anaconda proposes

### Single disk, Windows dual boot

1. Select the disk that contains Windows and the unallocated space
2. Choose **Mount point assignment** (or open the storage editor — see custom layouts below)
3. Assign Fedora to **unallocated space only**
4. **Reuse the existing EFI System Partition** — mount `/boot/efi`, **do not reformat**
5. Do **not** delete or reformat Windows (`ntfs`) partitions
6. **Encrypt my data** → optional; encrypts the Fedora btrfs volume, not Windows

### Storage editor (custom layouts)

Open the **⋮** menu → **Launch storage editor** for manual control.

All layouts assume UEFI.

#### Option A — btrfs (Fedora default, recommended)

Fedora creates btrfs subvolumes `root` and `home` on one volume. Swap uses **zram** (in RAM) — no swap partition by default.

**Linux-only, whole disk**

1. Delete existing partitions on target disk (if clean install)
2. Create partitions:
   - **EFI System Partition** — 600 MiB, FAT, mount `/boot/efi`
   - **`/boot`** — 2 GiB, ext4
   - **Remaining space** — btrfs; add subvolumes:
     - `root` → mount `/`
     - `home` → mount `/home`
3. Enable **LUKS2** on the btrfs partition if encrypting

**Dual boot**

1. Leave Windows and ESP partitions untouched
2. In **unallocated space**, create:
   - **`/boot`** — 2 GiB, ext4 (Fedora keeps `/boot` unencrypted)
   - **Remaining unallocated** — btrfs + subvolumes `root` (`/`) and `home` (`/home`)
3. Mount the **existing ESP** at `/boot/efi` without reformatting
4. Enable **LUKS2** on the btrfs partition if encrypting

**Swap (btrfs default — zram)**

| Goal | What to do |
|------|------------|
| No hibernate | Accept defaults. Fedora uses **zram** via `zram-generator`; no swap partition needed. |
| Hibernate | Add a **swap partition or swap file ≥ RAM** during custom layout, or create a btrfs swap file post-install (see First boot). zram alone cannot hibernate. |

**Hibernate with btrfs (manual partition swap)**

Add a swap partition in unallocated/custom layout:

| RAM | Swap partition size |
|-----|---------------------|
| Any | **≥ RAM** (e.g. 32 GiB RAM → 32 GiB swap) |

Place it in unallocated space or as a logical partition. Fedora installer can format it as `linux-swap`.

#### Option B — ext4 (legacy / compatibility)

Use when you prefer ext4 over btrfs.

1. Open storage editor
2. Create:
   - EFI → `/boot/efi` (reuse existing ESP when dual-booting)
   - `/boot` — 2 GiB, ext4
   - `/` — 50–100 GiB, ext4
   - `/home` — remaining space, ext4
   - `swap` — see swap table above (optional with zram; required for hibernate)
3. Enable **LUKS2** on `/` and `/home` if encrypting (Fedora encrypts per-volume in custom mode)

**Swap size (ext4 manual)**

| Goal | Swap partition |
|------|----------------|
| No hibernate | 2–8 GiB, or rely on zram and skip swap partition |
| Hibernate | **≥ RAM** |

#### Option C — multiple disks

Use storage editor, **Custom** scheme.

| Disk | Role | Layout |
|------|------|--------|
| 1 | System (+ Windows if dual-boot) | ESP (shared) + `/boot` + btrfs or ext4 root |
| 2 | Home | btrfs or ext4, mount `/home` |
| 3+ | Games/media | ext4/xfs, mount `/home/<user>/Games` or `/mnt/…` |

> Multi-disk layouts are not fully tested in this repo. Verify `/etc/fstab` and `/etc/crypttab` after install.

### Confirm storage

1. Review the summary — confirm Windows partitions show **preserve**, not **reformat**
2. Apply changes and enter LUKS passphrase if encryption is enabled

## Software selection

On the KDE Spin, the environment defaults to **KDE Plasma Workstation**. Verify it is selected.

Optional add-ons (enable if wanted):

- **Development Tools** — compilers, headers
- **Third-party repositories** are configured post-install via RPM Fusion (not in base installer)

## User creation

Fedora Workstation/KDE may defer account creation to **Initial Setup** on first boot. If the installer offers user creation:

1. Create your user account
2. Set a strong password
3. **Make this user administrator** (adds to `wheel` group for `sudo`)

Root has no password by default; use `sudo` for admin tasks.

## Review and install

1. Review summary (language, keyboard, timezone, disk layout, software)
2. **Begin installation**
3. Wait for completion
4. Reboot and remove installation media

## First boot

### Initial Setup (if shown)

Complete the Fedora/KDE first-login wizard:

1. Create user/password (if not done in installer)
2. Privacy settings → your preference
3. Skip online accounts unless wanted

### LUKS passphrase

Decrypt prompt at early boot may use **US keyboard layout**. Enter passphrase as typed during install.

Verify Finnish layout after login:

```bash
localectl status
```

Fix only if wrong:

```bash
sudo localectl set-keymap fi
sudo localectl set-x11-keymap fi pc106 winkeys
```

### Basic checks

```bash
sudo dnf upgrade --refresh -y
systemctl status systemd-timesyncd
```

### Windows dual boot — verify GRUB

GRUB should list **Windows Boot Manager** and Fedora. If Windows is missing:

```bash
sudo grub2-probe --target=fs_uuid /boot/efi
# Ensure os-prober is enabled
sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo reboot
```

**Windows Feature Updates** sometimes reset the UEFI boot order to Windows-only. Fix in firmware boot menu, or:

```bash
sudo efibootmgr
# Set Fedora entry first, or use firmware "UEFI boot order"
```

Re-enable **BitLocker** in Windows after confirming both OSes boot.

### Hibernate (only if swap ≥ RAM was configured)

Fedora defaults to zram; hibernate needs disk swap. If you added a swap partition during install:

```bash
swapon --show    # confirm disk swap ≥ RAM
sudo systemctl hibernate
```

If using a **swap file on btrfs** instead (Fedora Magazine method), see [Hibernation in Fedora Workstation](https://fedoramagazine.org/hibernation-in-fedora-36-workstation/) or the [updated guide](https://fedoramagazine.org/update-on-hibernation-in-fedora-workstation/).

### Firmware and drivers (if hardware is missing)

```bash
# RPM Fusion (needed for many codecs and NVIDIA)
sudo dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# CPU microcode
sudo dnf install microcode_ctl   # AMD
sudo dnf install intel-microcode # Intel

# GPU — check: lspci | grep -i vga
# AMD / Intel: usually works with inbox Mesa after updates
sudo dnf install akmod-nvidia           # NVIDIA (RPM Fusion nonfree)
```

Reboot after microcode or NVIDIA driver install.

## Post-install setup

Run this repo's Fedora setup script (enables RPM Fusion, installs packages, dotfiles, NordVPN, etc.):

```bash
git clone https://github.com/Aapok0/linux-setup.git ~/Workspace/linux-setup
cd ~/Workspace/linux-setup
chmod u+x setup scripts/*
./setup fedora
```

Pick optional dnf helpers and extra packages in `vars/fedora-vars` before running.

See [README.md](../../README.md) for further post-setup steps.
