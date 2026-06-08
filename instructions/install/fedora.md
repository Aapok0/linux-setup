# Fedora manual install guide

For installing Fedora with my personal preferences via the Anaconda Web UI installer.

Target: **Fedora 44+** amd64, **Fedora KDE Plasma Spin** ISO. The installer is a four-step linear wizard; user account, timezone, and hostname are configured on first boot via **Plasma Setup** (not in Anaconda).

## Installer flow (Fedora 44 Web UI)

| Step | Screen | What you configure |
|------|--------|-------------------|
| 1 | **Welcome** | Language, keyboard layout |
| 2 | **Installation method** | Destination disk, install method (see below) |
| 2b | **Storage editor** *(optional)* | ⋮ menu → **Launch storage editor** — manual partitioning via Cockpit Storage |
| 3 | **Storage configuration** | **Encrypt my data**, LUKS passphrase, keyboard layout at boot |
| 4 | **Review and install** | Confirm layout, start install |

**Installation method** options (under *How would you like to install?*):

- **Share disk with other operating systems** — dual boot; uses unallocated space or reclaim dialog
- **Use entire disk** — wipe selected disk, automatic btrfs layout
- **Mount point assignment** — assign existing partitions to mount points (`/`, `/boot`, `/boot/efi`, …)

If Fedora is already on the disk, a **Reinstall Fedora** option may appear at the top (fresh install, keeps `/home` data).

> **Dual boot + small ESP:** Anaconda warns if `/boot/efi` is under **500 MiB**. Windows often ships a 100–260 MiB ESP; Fedora can reuse it, but expanding the ESP in Windows/GParted before install avoids boot issues.

Steps **not** in the Fedora 44 installer (moved to first boot):

- Time & date / timezone
- Hostname
- User account creation
- Software / desktop selection (KDE Plasma is baked into the Spin ISO)

## Boot installer

1. Boot the Fedora KDE Plasma Spin live image (UEFI)
2. Choose **Try Fedora** (live session)
3. Launch **Install to Hard Drive** from the desktop (or the welcome dialog)

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
- **SATA mode / storage controller** → **AHCI** or **NVMe** (not **RAID** / **Intel RST**). Linux cannot see Windows volumes on an RST/RAID array without dmraid setup; switch before installing either OS when possible
- **Secure Boot** can stay enabled for Fedora; disable only if install media or NVIDIA drivers fail to boot

## 1. Welcome

1. Language → **English (United States)**
2. Keyboard layout → **Finnish**
3. Continue

## 2. Installation method

Select **Destination** (target disk). On multi-disk systems, use **Change destination** if the default is wrong.

Do **not** choose **Use entire disk** when dual-booting — that wipes Windows.

### Linux only — whole disk

1. Select the target disk
2. **How would you like to install?** → **Use entire disk**
3. Continue to [Storage configuration](#3-storage-configuration)

Anaconda creates a default btrfs layout (approximate):

| Partition | Size | FS | Mount |
|-----------|------|----|-------|
| EFI System Partition | ~629 MiB | FAT | `/boot/efi` |
| `/boot` | ~2 GiB | ext4 | `/boot` |
| remainder | rest | btrfs (subvols `root`, `home`) | `/`, `/home` |

### Dual boot — share disk with Windows

1. Select the disk that contains Windows and the unallocated space
2. **How would you like to install?** → **Share disk with other operating systems**
   - Anaconda installs into **unallocated space** only
   - If no free space exists, the **reclaim** dialog can delete or resize supported partitions (NTFS/BitLocker volumes must be prepared in Windows first)
3. **Reuse the existing EFI System Partition** — mount `/boot/efi`, **do not reformat**
4. Do **not** delete or reformat Windows (`ntfs`) partitions
5. Continue to [Storage configuration](#3-storage-configuration)

### Mount point assignment (pre-partitioned or custom reuse)

Use when partitions are already laid out (external tool, previous Linux install, or after using the storage editor):

1. **How would you like to install?** → **Mount point assignment**
2. Assign mandatory mount points starting with **`/`** (root), then **`/boot`**, then **`/boot/efi`**
3. Add optional mount points (`/home`, swap, …) as needed
4. Continue to [Storage configuration](#3-storage-configuration)

### Storage editor (manual layouts)

Open **⋮** (top-right) → **Launch storage editor** from the installation method / storage screen.

This launches **Cockpit Storage**. Changes apply **immediately** on disk (unlike the main Anaconda flow, which only commits on **Review and install**).

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
3. Return to installation; Anaconda switches to **Use configured storage**
4. Enable **LUKS2** on the btrfs partition in [Storage configuration](#3-storage-configuration) if encrypting

**Dual boot**

1. Leave Windows and ESP partitions untouched
2. In **unallocated space**, create:
   - **`/boot`** — 2 GiB, ext4 (Fedora keeps `/boot` unencrypted)
   - **Remaining unallocated** — btrfs + subvolumes `root` (`/`) and `home` (`/home`)
3. Mount the **existing ESP** at `/boot/efi` without reformatting
4. Return to installation; enable **LUKS2** on the btrfs partition if encrypting

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

Place it in unallocated space or as a logical partition. Format as `linux-swap`.

#### Option B — ext4 (legacy / compatibility)

Use when you prefer ext4 over btrfs.

1. Open storage editor
2. Create:
   - EFI → `/boot/efi` (reuse existing ESP when dual-booting)
   - `/boot` — 2 GiB, ext4
   - `/` — 50–100 GiB, ext4
   - `/home` — remaining space, ext4
   - `swap` — see swap table above (optional with zram; required for hibernate)
3. Return to installation; enable **LUKS2** on `/` and `/home` if encrypting (Fedora encrypts per-volume in custom mode)

**Swap size (ext4 manual)**

| Goal | Swap partition |
|------|----------------|
| No hibernate | 2–8 GiB, or rely on zram and skip swap partition |
| Hibernate | **≥ RAM** |

#### Option C — multiple disks

Use storage editor on each disk as needed.

| Disk | Role | Layout |
|------|------|--------|
| 1 | System (+ Windows if dual-boot) | ESP (shared) + `/boot` + btrfs or ext4 root |
| 2 | Home | btrfs or ext4, mount `/home` |
| 3+ | Games/media | ext4/xfs, mount `/home/<user>/Games` or `/mnt/…` |

> Multi-disk layouts are not fully tested in this repo. Verify `/etc/fstab` and `/etc/crypttab` after install.

## 3. Storage configuration

1. **Encrypt my data** — enable for LUKS (recommended on Linux-only installs; optional on dual boot — encrypts Fedora volumes only, not Windows)
2. If enabled:
   - Set **passphrase**
   - Choose **keyboard layout during boot** (LUKS prompt may default to US layout even if system keyboard is Finnish)
3. Continue

## 4. Review and install

1. Review summary — language, keyboard, disk, partition layout
2. On dual boot: confirm Windows partitions show **preserve**, not **reformat**
3. **Begin installation** (button text may read **Erase data and install** on whole-disk installs)
4. Wait for completion
5. Reboot and remove installation media

## First boot — Plasma Setup

Fedora KDE defers account and system settings to **Plasma Setup** on first boot (replaces the old Anaconda user/timezone steps).

Complete the wizard:

1. **Language** and **keyboard** — verify **Finnish** if needed
2. **Timezone** → **Europe/Helsinki**
3. **Network** — connect if prompted (optional for offline install)
4. **User account** — create user, strong password, **administrator** / `wheel` for `sudo`
5. Remaining privacy / welcome screens → your preference

Root has no password by default; use `sudo` for admin tasks.

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
timedatectl status    # confirm Europe/Helsinki, NTP active
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
