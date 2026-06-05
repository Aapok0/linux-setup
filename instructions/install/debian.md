# Debian manual install guide

For installing Debian with my personal preferences via the graphical expert installer.

Target: Debian 13 (trixie) amd64. Steps follow the order shown in the installer.

## Install menu

- **Advanced options** → **Graphical expert install**

## Choose language

1. Language → **English**
2. Location → **other** → **Europe** → **Finland**
3. Locale → **en_US.UTF-8**
4. Additional locale → **fi_FI.UTF-8**
5. Default locale → **fi_FI.UTF-8**

## Configure the keyboard

- Keymap → **Finnish**

## Detect and mount installation media

- Load any modules the installer requests (uncommon on recent hardware)

## Load installer components from installation media

- Accept defaults; no extra components needed

## Detect network hardware

- Let detection finish

## Configure the network

1. **Auto-configure** with DHCP
2. Keep default DHCP timeout
3. Set hostname (example: `debian-pc`)
4. Leave domain name empty

## Set up users and passwords

1. **Do not allow root login** — Debian recommends this. Your user gets `sudo` via the `sudo` group.
   - If locked out later: boot the installer → **Advanced options** → **Rescue mode**, or use recovery root shell from the installed system's GRUB menu.
2. Create your username and password

## Configure the clock

1. Enable **NTP**
2. NTP servers — either keep installer default (`0.debian.pool.ntp.org` …) or use Finland pool:
   ```
   0.fi.pool.ntp.org 1.fi.pool.ntp.org 2.fi.pool.ntp.org 3.fi.pool.ntp.org
   ```
3. Timezone → **Europe/Helsinki**

## Detect disks

- Confirm installer sees expected disks before continuing to partitioning

## Partition disks

Pick one layout below. All paths assume UEFI.

### Option A — ext4 with guided encrypted LVM (simplest)

Best default for a single system disk. Installer handles LUKS, LVM, `/boot`, EFI, `/`, `/home`, and `swap`.

1. **Guided - use entire disk and set up encrypted LVM**
2. Select the install disk (not USB installer media)
3. **Separate /home partition**
4. Review layout → **Write the changes to disks**
5. LUKS passphrase — store safely; required at every boot
6. Volume group name — default `debian` is fine
7. Use all space in the volume group
8. Accept remaining defaults (filesystems will be **ext4**)

**Swap size (guided)**

| Goal | What to do |
|------|------------|
| No hibernate | Guided layout is fine. Swap is usually sized to RAM. To use a smaller swap, use Option B manual instead. |
| Hibernate | Keep guided swap at **≥ RAM**. Debian `initramfs-tools` usually auto-detects the resume device on encrypted LVM. Verify after install (see Post-install). |

### Option B — ext4 with manual encrypted LVM

Use for custom swap size, multiple disks, or fixed root/home sizes.

1. **Manual**
2. **Disk 1 (system)**
   - EFI: 1 GiB, FAT32, mount `/boot/efi`, **boot** flag
   - `/boot`: 1–2 GiB, ext4
   - Remaining space → **physical volume for encryption** → **Configure encrypted volumes** → create encrypted PV
   - On encrypted PV → **Configure the Logical Volume Manager** → create volume group `debian`
   - Logical volumes:
     - `swap` — see swap table below
     - `root` — 100–150 GiB (or more), ext4, mount `/`
     - `home` — remaining space, ext4, mount `/home`
3. **Disk 2+ (optional home/data)** — separate PV/LV or plain partition with mount `/home` or e.g. `/home/<user>/Games`
4. **Write the changes to disks** and set LUKS passphrases

**Swap size (manual ext4)**

| Goal | `swap` logical volume size |
|------|---------------------------|
| No hibernate | `sqrt(RAM)` rounded up, or 2–8 GiB if disk is tight |
| Hibernate | **≥ RAM** (e.g. 32 GiB RAM → swap LV ≥ 32 GiB) |

### Option C — btrfs with encrypted LVM

Debian installer can format LVs as btrfs but does not create custom subvolume layouts (e.g. `@`, `@home`) without extra steps. Two sub-options:

#### C1 — btrfs, installer defaults (low effort)

1. Follow **Option A** or **Option B** through LVM creation
2. In manual mode, set **Use as** → **btrfs journaling file system** on `root` and `home` LVs instead of ext4
3. Installer creates a default root subvolume (e.g. `@rootfs`). Usable as-is; rename or add subvolumes post-install if you want Timeshift-style naming

#### C2 — btrfs with `@` and `@home` subvolumes (Timeshift-friendly)

1. **Manual** partitioning — same EFI, `/boot`, and encrypted LVM shell as Option B
2. On the root LV: **Use as** → **btrfs journaling file system**, mount point `/` (installer creates `@rootfs`)
3. **Write the changes to disks**
4. **Before** choosing **Install the base system**, open installer shell (**Ctrl+Alt+F2**), then:

```bash
# Adjust device names to match your layout
ROOT_DEV=/dev/mapper/debian--vg-root   # example LVM mapper name
TARGET=/target

btrfs subvolume rename /mnt/@rootfs /mnt/@
btrfs subvolume create /mnt/@home
mv /mnt/home/* /mnt/@home/ 2>/dev/null || true
rmdir /mnt/home 2>/dev/null || true
mkdir /mnt/@home

# Remount for installer
umount /mnt
mount -o subvol=@,compress=zstd:3 $ROOT_DEV /target
mkdir -p /target/home
mount -o subvol=@home,compress=zstd:3 $ROOT_DEV /target/home

# Fix fstab the installer already started
sed -i 's|/.*btrfs.*defaults|&,subvol=@,compress=zstd:3|' /target/etc/fstab
# Add /home subvol line if missing — match UUID from existing fstab root entry
```

5. Return to installer (**Ctrl+Alt+F1**) and continue

Swap rules: same table as Option B. btrfs root does not change swap sizing.

### Option D — multiple disks (root + home + data)

Use **Manual** only.

| Disk | Role | Suggested layout |
|------|------|------------------|
| 1 | System | EFI + `/boot` + encrypted LVM (`swap`, `root`) — ext4 or btrfs per options above |
| 2 | Home | Encrypted LVM or LUKS + ext4/btrfs, mount `/home` |
| 3+ | Games/media | Plain ext4/xfs, mount under `/home/<user>/…` or `/mnt/…`; encryption optional |

> Multi-disk layouts are not fully tested in this repo. Double-check `/etc/fstab` and `/etc/crypttab` after install.

## Install the base system

1. Kernel → **linux-image-amd64**
2. Initramfs drivers → **targeted**

## Configure the package manager

1. No extra installation media
2. **Use a network mirror**
3. **Use HTTPS** for downloads
4. Mirror country → **Finland** (or nearest), pick a mirror
5. No HTTP proxy
6. Enable **non-free firmware** (`firmware-linux` and friends — needed for many Wi-Fi/GPU chips)
7. Enable **source repositories**
8. Enable **security updates** and **release updates**
9. Skip **backports** for now

## Select and install software

1. **No automatic updates** (manage with `apt` later)
2. **Do not** send package usage data to Debian (popularity contest)
3. Desktop → **KDE Plasma** + default tools (`tasksel` KDE task)
4. **Connect to Debian debuginfod server**
5. `libpaper2` default → **A4**
6. PAM defaults → accept (configure fingerprint later in PAM if hardware supports it)
7. Fontconfig defaults → accept
8. Do **not** set mandb to run as man uid
9. `apt-listchanges` — list changes with pager: **Yes**
10. Show APT news: **Yes**
11. Email for APT changes: leave **empty**
12. Ask confirmation after showing changes: **Yes**
13. Show headers: **No**
14. Show changes in reverse order: **Yes**
15. Skip already shown changes: **Yes**
16. Do **not** set up BSD LPD printing
17. CUPS — allow printing of **unknown** jobs: **Yes**
18. CUPS extensions → defaults
19. Add `saned` user to scanner group: **Yes** if you use network scanners, else **No**

## Install the GRUB boot loader

1. Install GRUB to the **EFI System Partition** on the boot drive
2. **Do not** force install to removable media unless you need USB-bootable install
3. Accept other defaults — installer runs `grub-install` and `update-grub`

Dual-boot: if another OS is present, confirm the installer detected it. Back up the other bootloader before writing partitions.

## Finish the installation

1. Complete any remaining prompts
2. Eject/remove installation media
3. Reboot

## First boot

### LUKS passphrase

Early boot decrypt prompt may use **US keyboard layout** even though Finnish was chosen in the installer. Enter passphrase exactly as typed during install.

After login:

```bash
localectl status
sudo localectl set-keymap fi
sudo localectl set-x11-keymap fi pc106 winkeys
```

### Basic checks

```bash
sudo apt update && sudo apt full-upgrade -y
sudo systemctl status systemd-timesyncd
```

### Hibernate setup (only if swap ≥ RAM was configured)

Debian usually auto-configures resume for encrypted LVM swap. Verify:

```bash
swapon --show          # swap size ≥ RAM
cat /etc/initramfs-tools/conf.d/resume
sudo systemctl hibernate
```

If resume fails, set resume device explicitly:

```bash
SWAP_UUID=$(blkid -o value -s UUID "$(swapon --show=NAME --noheadings | head -1)")
echo "RESUME=UUID=$SWAP_UUID" | sudo tee /etc/initramfs-tools/conf.d/resume
sudo update-initramfs -u -k all
sudo update-grub
```

For a **separate encrypted swap** mapping (not plain LVM swap LV), see `/usr/share/doc/cryptsetup/README.initramfs.gz` and `decrypt_derived` in `/etc/crypttab`.

### Firmware and drivers (if hardware is missing)

```bash
# CPU microcode
sudo apt install firmware-amd-microcode    # AMD
sudo apt install firmware-intel-microcode  # Intel

# GPU — check: lspci | grep -i vga
sudo apt install mesa-vulkan-drivers libgl1-mesa-dri           # AMD / Intel
sudo apt install nvidia-driver firmware-misc-nonfree           # NVIDIA
```

Reboot after microcode or NVIDIA driver install.

## Post-install setup

Run this repo's Debian setup script:

```bash
git clone https://github.com/Aapok0/linux-setup.git ~/Workspace/linux-setup
cd ~/Workspace/linux-setup
chmod u+x setup scripts/*
./setup debian
```

See [README.md](../../README.md) for further post-setup steps.
