# Arch manual install guide

For installing Arch Linux with my personal preferences.

> **Automation:** From the Arch live ISO (as root): `./install arch` — partitioning, btrfs layout, chroot install. After first boot: `./setup arch` for [Post-install steps](#post-install-steps) (Snapper, snap-pac, `/boot` backup hooks, grub-btrfs, overlayfs initramfs). Keep this document for manual installs or step-by-step control.

## Initial steps

### Load Finnish keybaord layout

```bash
loadkeys fi
```

### Setup internet connection

If ethernet cable is connected, the connection should work immediately. Check with:

```bash
ip link
ping google.com
```

If trying to connect with WI-FI:

```bash
iwctl device list

# Look for the device and power it on, if it isn't (for example wlan0).
iwctl device wlan0 set-property Powered on

# Scan for networks and look for the one you want to connect to,
iwstl station wlan0 get-networks
iwctl station wlan0 connect <your_SSID>
```

### Disk setup

#### Root partitioning

Look for the storage device (disk) you want to format:

```bash
lsblk
gdisk /dev/<root_device_name>
```

In `gdisk` you have the following options:

- p = show partition table
- o = empty the partition table
- n = create new partition
- t = set type for partition
- w = write partitions

Create the following partitions to the disk you want to use as root and optionally partition home either to the same as root or another disk. Make swap either as a partition here or as a logical volume later on:

##### Boot

/boot/efi
1. n
2. default (Enter)
3. default (Enter)
4. +1G
5. ef00

/boot
1. n
2. default (Enter)
3. default (Enter)
4. +4G
5. ef02

##### Swap (optional)

Option 1: /swap (non-hibernate)
1. n
2. default (Enter)
3. default (Enter)
4. +< root of RAM>G
5. 8200

Option 2: /swap (hibernate)
1. n
2. default (Enter)
3. default (Enter)
4. +<RAM + root of RAM>G
5. 8200

##### Root

/
1. n
2. default (Enter)
3. default (Enter)
4. +<100+>G
5. 8309

#### Home

If adding to same disk as root, add it straight away here:

/home
1. n
2. default (Enter)
3. default (Enter)
4. default (Enter)
5. 8302

##### Finishing partitioning

1. Check the partitioning table with: p
2. Write the partitions to the disk with: w
    - This actions is destructive to any data already on the disk. Make sure you are sure about this.

#### Home partitioning (optional)

If you are using separate disk for home, partition it the same way as root:

```bash
lsblk
gdisk /dev/<home_device_name>
```

##### Home

/home
1. n
2. default (Enter)
3. default (Enter)
4. default (Enter)
5. 8302

##### Finishing partitioning

1. Check the partitioning table with: p
2. Write the partitions to the disk with: w
    - This actions is destructive to any data already on the disk. Make sure you are sure about this.

#### Encrypt partitions (optional)

Make sure the related kernel modules are loaded:

```bash
modprobe dm-crypt
modprobe dm-mod
```

Encrypt and open the root and home partitions (remember to actually save the password somewhere):

```bash
cryptsetup luksFormat -v -s 512 -h sha512 --type luks2 /dev/<root_partition>
cryptsetup open /dev/<root_partition> luks_root

cryptsetup luksFormat -v -s 512 -h sha512 --type luks2 /dev/<home_partition>
cryptsetup open /dev/<home_partition> luks_home
```

#### Create logicaL volumes

##### Root and swap (optional)

Create swap here, if you didn't create it as a partition earlier.

```bash
pvcreate /dev/mapper/luks_root
vgcreate arch /dev/mapper/luks_root
# Swap without hibernate
lvcreate -n swap -L +<root of RAM>G -C y arch
# Swap with hibernate
lvcreate -n swap -L +<RAM + root of RAM>G -C y arch
# Add percentage of leftover space to root
lvcreate -n root -l +100%FREE arch
# Or add certain amount to root
lvcreate -n root -L 600G arch
```

##### Home

```bash
pvcreate /dev/mapper/luks_home
vgcreate arch_home /dev/mapper/luks_home
# Add percentage of leftover space to root
lvcreate -n home -l +100%FREE arch_home
# Or add certain amount to root
lvcreate -n home -L 3T arch_home
```

##### Scan and change

```bash
vgscan
vgchange -ay
```

#### Add file systems to the logical volumes and partitions

```bash
mkfs.fat -F 32 /dev/<EFI_partition>
mkfs.ext4 /dev/<boot_partition>

# swap partition
mkswap /dev/<swap_partition>
# or swap logical volume
mkswap /dev/mapper/arch-swap

mkfs.btrfs -L root /dev/mapper/arch-root
mkfs.btrfs -L home /dev/mapper/arch_home-home
```

#### Create btrfs subvolumes

##### Root

```bash
mount /dev/mapper/arch-root /mnt
cd /mnt

btrfs subvol create @
btrfs subvol create @snapshots
btrfs subvol create @var_log
btrfs subvol create @var_cache
btrfs subvol create @var_tmp
btrfs subvol create @var_spool
btrfs subvol create @var_lib_containers
btrfs subvol create @var_lib_docker
btrfs subvol create @var_lib_libvirt
```

##### Why pre-create `@snapshots`?

The [Arch Wiki suggested layout](https://wiki.archlinux.org/title/Snapper#Suggested_filesystem_layout) **still lists `@snapshots` as a top-level sibling** of `@`. That has not been withdrawn.

What **archinstall ≥ 3.0.5** changed: it stopped mounting a pre-created `@.snapshots` directory before `snapper create-config`, because that conflicted with Snapper creating `.snapshots` **inside** `@`. The fix is the [post-install remount dance](#configure-snapper), not dropping `@snapshots` entirely.

- **Pre-create `@snapshots`** at install → snapshots live outside `@` → you can replace `@` without losing history.
- **Do not** leave Snapper's default `.snapshots` inside `@` — delete it after `create-config` and mount `@snapshots` at `/.snapshots` instead.

##### Optional root subvolumes

| Subvolume | Mount | When to add |
|-----------|-------|-------------|
| `@var_lib_machines` | `/var/lib/machines` | systemd-nspawn machine images |
| `@var_lib_postgres` | `/var/lib/postgres` | PostgreSQL data directory |

**`@var_lib_containers` vs `@var_lib_docker`:** `/var/lib/containers` is **Podman/CRI-O** storage; `/var/lib/docker` is **Docker Engine** (Moby). Both are included by default here — separate stacks, separate subvolumes.

Snapper does **not** create any subvolumes automatically — layout is chosen at install time.

##### Home

```bash
mount --mkdir /dev/mapper/arch_home-home /mnt/home
cd /mnt/home

btrfs subvol create @home
btrfs subvol create @home_snapshots
btrfs subvol create @home/@media
```

##### Unmount

```bash
cd
umount -R /mnt
```

#### Mount subvolumes and partitions

```bash
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@ /dev/mapper/arch-root /mnt
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@snapshots /dev/mapper/arch-root /mnt/.snapshots
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@var_log /dev/mapper/arch-root /mnt/var/log
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@var_cache /dev/mapper/arch-root /mnt/var/cache
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@var_tmp /dev/mapper/arch-root /mnt/var/tmp
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@var_spool /dev/mapper/arch-root /mnt/var/spool
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@var_lib_containers /dev/mapper/arch-root /mnt/var/lib/containers
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@var_lib_docker /dev/mapper/arch-root /mnt/var/lib/docker
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@var_lib_libvirt /dev/mapper/arch-root /mnt/var/lib/libvirt
mount --mkdir /dev/<boot_partition> /mnt/boot
mount --mkdir /dev/<EFI_partition> /mnt/boot/efi
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@home /dev/mapper/arch_home-home /mnt/home
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@home_snapshots /dev/mapper/arch_home-home /mnt/home/.snapshots
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@home/@media /dev/mapper/arch_home-home /mnt/home/<planned_username>/Media

# swap partition
swapon /dev/<swap_partition>
# or swap logical volume
swapon /dev/mapper/arch-swap
```

## Arch install

### Install basic packages and chroot into the installation

Make sure you have good mirrors close to you:

```bash
reflector -c Finland -a 12 --protocol https --sort rate --download-timeout 60 --save /etc/pacman.d/mirrorlist
```

Install Arch with basic packages (this will take some time):

```bash
pacstrap -Ki /mnt base base-devel
```

Generate fstab file for all the mounted volumes:

```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

Chroot into the installation mounted in /mnt:

```bash
arch-chroot /mnt
```

### Make pacman faster and install more needed packages

Install a text editor to edit files:

```bash
pacman -S neovim
```

Set pacman parallel downloads to as high as the thread count of your CPU:

```bash
nvim /etc/pacman.conf

# Change this line
ParallelDownloads = <cpu thread count>
```

Install linux kernel and other needed firmware and packages;

```bash
pacman -S linux linux-headers linux-lts linux-lts-headers linux-firmware sof-firmware dosfstools lvm2 sudo cryptsetup btrfs-progs vim man-db man-pages texinfo git xdg-user-dirs
```

### Setup mkinitcpio and grub

Add needed modules and hooks to mkinitcpio config (encrypt only needed, if using disk encryption):

```bash
nvim /etc/mkinitcpio.conf

# Change these lines
MODULES=(btrfs)
HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems resume fsck)
```

Install grub and UEFI boot entry manager:

```bash
pacman -S grub efibootmgr
grub-install --efi-directory=/boot/efi
```

Set initramfs images to correct permissions:

```bash
chmod 600 /boot/initramfs-linux*
```

### Setup decryption to boot (optional)

Add cryptdevices to grub config:

```bash
# Get UUIDs with
blkid /dev/<root_partition>
blkid /dev/mapper/arch-root

nvim /etc/default/grub

# Change this line
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet root==UUID=<root_lv_uuid> cryptdevice=UUID=<root_partition_uuid>:luks_root"
```

Create and set encrypt/decrypt keys for encrypted volumes:

```bash
mdkir /etc/luks_keys
dd if=/dev/random of=/etc/luks_keys/root_keyfile.bin bs=512 count=8
dd if=/dev/random of=/etc/luks_keys/home_keyfile.bin bs=512 count=8

chmod 700 /etc/luks_keys
chmod 000 /etc/luks_keys/*

cryptsetup luksAddKey /dev/<root_partition> /etc/luks_keys/root_keyfile.bin
cryptsetup luksAddKey /dev/<home_partition> /etc/luks_keys/home_keyfile.bin

nvim /etc/mkinitcpio.conf

# Change this line
FILES(/etc/luks_keys/root_keyfile.bin)

# Get UUID with
blkid /dev/<home_partition>

nvim /etc/crypttab

# Add this line
luks_home	UUID=<home_partition_uuid>	/etc/luks_keys/home_keyfile.bin		luks,initramfs
```

### Add localization

#### Set time and date

Set your timezone and configure time synchronization:

```bash
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc

nvim /etc/systemd/timesyncd.conf

# Change these lines
NTP=0.arch.pool.ntp.org 1.arch.pool.ntp.org 2.arch.pool.ntp.org 3.arch.pool.ntp.org
FallbackNTP=0.pool.ntp.org 1.pool.ntp.org

# Enable time synchronization
systemctl enable systemd-timesyncd.service
timedatectl set-ntp true
```

#### Set language and other localization

Generate locales, set locale configuration and grub locale support:

```bash
nvim /etc/locale.gen

# Uncomment locales you want:
en_US.UTF-8 UTF-8
fi_FI.UTF-8 UTF-8

locale-gen

nvim /etc/locale.conf

# Set following lines
LANG=en_US.UTF-8
LANGUAGE=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
LC_NUMERIC=fi_FI.UTF-8
LC_TIME=fi_FI.UTF-8
LC_COLLATE=en_US.UTF-8
LC_MONETARY=fi_FI.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_PAPER=fi_FI.UTF-8
LC_NAME=fi_FI.UTF-8
LC_ADDRESS=fi_FI.UTF-8
LC_TELEPHONE=fi_FI.UTF-8
LC_MEASUREMENT=fi_FI.UTF-8
LC_IDENTIFICATION=fi_FI.UTF-8
LC_ALL=

cp /usr/share/locale/en@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
```

#### Set keyboard

```bash
nvim /etc/vconsole.conf

# Set following lines
KEYMAP=fi
XKBLAYOUT=fi
XKBMODEL=pc106
XKBVARIANT=winkeys
```

### Set hostname, add root password and create an admin user

Add your chosen hostname for the computer to this file:

```bash
nvim /etc/hostname
```

Add password for the root user:

```bash
passwd
```

Create an admin user:

```bash
# Unmount Media subvolume and remove the planned user home directory
#   - This way xdg-user-dirs package creates default directories
umount /home/<username>/Games
rm -rf home/<username>

# Create user with the group planned to use for sudo permissions and add password
useradd -m -G wheel -s /bin/bash <username>
passwd <username>

# Add sudo permissions by uncommenting wheel group at the bottom (with or without password)
EDITOR=nvim visudo

# Remount Media submvolume and give it correct ownership
mount /home/<username>/Games
chown <username>:<username> /home/<username>/Games
```

### Install KDE plasma and packages for basic functionality

Install basic utilities with systemd daemons or timers:

```bash
pacman -S networkmanager bluez bluez-utils reflector
```

Set reflector options

```bash
vim /etc/xdg/reflector/reflector.conf

# Set following options
--save /etc/pacman.d/mirrorlist
--protocol https
--country Finland,Sweden
--latest 5
--sort age
```

Enable the utilities:

```bash
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable reflector.timer
systemctl enable fstrim.timer
```

Install microcode for CPU stability:

```bash
# Check what CPU have
lscpu

# AMD
pacman -S amd-ucode
# Intel
pacman -S intel-ucode
```

Install GPU drivers:

```bash
# Check what GPU you have
lspci

# AMD
pacman -S mesa lib32-mesa libva-mesa-driver vulkan-radeon lib32-vulkan-radeon vulkan-mesa-implicit-layers lib32-vulkan-mesa-implicit-layers
# Intel broadwell or newer
pacman -S mesa lib32-mesa intel-media-driver
# Nvidia
pacman -S nvidia nvidia-utils nvidia-lts
# VMWare
pacman -S xf86-video-vmware
```

Install KDE plasma related packages and other packages for basic function:

```bash
pacman -S xorg plasma-desktop plasma-nm plasma-pa bluedevil kscreen kcron ibus sddm kitty
```

Enable the display manager:

```bash
systemctl enable sddm
```

### Generate GRUB and initramfs configurations

Generate grub configs and initramfs images:

```bash
grub-mkconfig -o /boot/grub/grub.cfg
grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg

mkinitcpio -p linux
mkinitcpio -p linux-lts
```

### Finish installation

Exit chroot, unmount everything and reboot

```bash
exit
umount -R /mnt
reboot now
```

## Post install steps

> **Shortcut:** `cd ~/Workspace/linux-setup && ./setup arch` runs these Snapper/btrfs steps automatically (plus the rest of your environment setup). The manual steps below match what the script does.

Might need to write decrypt passphrase with US keyboard layout and set Finnish keyboard again... Need to find a fix for this.

```bash
localectl --no-convert set-keymap fi
localectl --no-convert set-x11-keymap fi pc106 winkeys

sudo mkinitcpio -P
```

Upgrade all packages:

```bash
paru -Syu
```

### Install snapshot and boot tools

```bash
paru -S snapper snap-pac grub-btrfs inotify-tools rsync snapper-rollback
```

- **snap-pac** — [extra] repo; pre/post Snapper snapshots around `pacman` transactions
- **grub-btrfs** — [extra]; btrfs snapshot entries in GRUB (`grub-btrfsd` watches `/.snapshots`)
- **snapper-rollback** — [AUR]; CLI live-ISO / emergency `@` subvolume restore (see [rollback](#c--restore--from-live-iso))

Optional AUR: **snap-pac-grub** — refreshes GRUB immediately after snap-pac (usually redundant if `grub-btrfsd` is running).

### Exclude snapshots from locate

```bash
sudo nvim /etc/updatedb.conf
# Add or extend:
PRUNENAMES = ".snapshots"
```

### Back up /boot into btrfs

`/boot` is ext4 and is **not** included in `@` snapshots. Copy it into `/.bootbackup` on kernel changes so post-transaction snapshots carry a matching boot tree.

Install hooks from this repo (or create equivalent files under `/etc/pacman.d/hooks/`):

```bash
sudo install -Dm644 ~/Workspace/linux-setup/config/arch/pacman/hooks/55-bootbackup_pre.hook /etc/pacman.d/hooks/
sudo install -Dm644 ~/Workspace/linux-setup/config/arch/pacman/hooks/95-bootbackup_post.hook /etc/pacman.d/hooks/
```

Hook `95` must sort **before** `zz-snap-pac-post.hook` so the backup is captured inside snap-pac's post snapshot. After the next kernel update, confirm:

```bash
ls -la /.bootbackup/
```

### Configure Snapper

Snapper's `create-config` places `.snapshots` **inside** `@`. This layout uses sibling `@snapshots` / `@home_snapshots` instead ([Arch Wiki](https://wiki.archlinux.org/title/Snapper#Suggested_filesystem_layout)).

**Root:**

```bash
sudo umount /.snapshots
sudo rm -rf /.snapshots

sudo snapper -c root create-config /

sudo btrfs subvolume delete /.snapshots
sudo mkdir /.snapshots
sudo mount -a
sudo chmod 750 /.snapshots
```

**Home** (if btrfs):

```bash
sudo umount /home/.snapshots
sudo rm -rf /home/.snapshots

sudo snapper -c home create-config /home

sudo btrfs subvolume delete /home/.snapshots
sudo mkdir /home/.snapshots
sudo mount -a
sudo chmod 750 /home/.snapshots
```

Tune configs if desired:

```bash
sudo nvim /etc/snapper/configs/root
sudo nvim /etc/snapper/configs/home   # TIMELINE_CREATE="no" is reasonable for /home
```

Allow your user to run snapper:

```bash
sudo snapper -c root set-config ALLOW_USERS=<username> SYNC_ACL=yes
sudo snapper -c home set-config ALLOW_USERS=<username> SYNC_ACL=yes TIMELINE_CREATE=no
```

### snapper-rollback config (live ISO restore)

`./setup arch` writes `/etc/snapper-rollback.conf` from `config/arch/snapper-rollback.conf` with `dev=` set to your `/` block device. From a live ISO you may need to edit `mountpoint` / `dev` after unlocking LUKS:

```bash
sudo nvim /etc/snapper-rollback.conf
# [root]
# subvol_main = @
# subvol_snapshots = @snapshots
# mountpoint = /btrfsroot
# dev = /dev/mapper/luks_root
```

### Boot read-only snapshots (overlayfs)

Snapper snapshots are read-only. KDE and other services need a writable `/var`. On Arch, use the **grub-btrfs-overlayfs** mkinitcpio hook (ships with the `grub-btrfs` package).

```bash
sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bkp
sudo nvim /etc/mkinitcpio.conf
# Append to HOOKS (requires udev, not systemd):
# HOOKS=(... fsck grub-btrfs-overlayfs)
sudo mkinitcpio -P
```

### GRUB snapshot menu

```bash
sudo mkdir -p /etc/systemd/system/grub-btrfsd.service.d
sudo tee /etc/systemd/system/grub-btrfsd.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog /.snapshots
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now grub-btrfsd
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### Snapper timers

```bash
sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
```

Verify:

```bash
snapper list
paru -S htop    # should create pre/post snapshots
snapper list
ls /.bootbackup/
command -v snapper-rollback
```

## Next steps

```bash
cd ~/Workspace/linux-setup
./setup arch
```

Install **btrfs-assistant** (optional GUI; also in `setup arch` via AUR apps):

```bash
paru -S btrfs-assistant
```

---

## Rollback and restore

This layout follows the [Arch Wiki suggested btrfs + Snapper layout](https://wiki.archlinux.org/title/Snapper#Suggested_filesystem_layout).

### Tools compared

| Tool | What it does | Restores `/boot`? |
|------|----------------|-------------------|
| **btrfs-assistant** (GUI, extra/AUR) | Replaces `@` (or `@home`) with a Snapper snapshot subvolume; backs up current `@` first | **No** — restore `/boot` separately (below) |
| **snapper-rollback** (AUR CLI) | Same `@` subvolume swap as Wiki/live ISO procedure; best when system won't boot | **No** — restore `/boot` separately |
| **grub-btrfs menu** | Boots a **read-only** snapshot for testing/recovery | N/A — overlay session; use Restore to make permanent |

**btrfs-assistant** and **snapper-rollback** both replace `@` from a snapshot; use the GUI when the system boots, **snapper-rollback** when you are on a live ISO or prefer CLI. Neither replaces the **`/.bootbackup` → `/boot` rsync** step while `/boot` stays on ext4.

### A — Restore `/` from a running system (btrfs-assistant)

Best when the system still boots.

1. `sudo snapper -c root list` — pick snapshot number `N`.
2. Open **btrfs-assistant** → Snapper → select snapshot → **Restore** (replaces `@`, keeps `@snapshots`).
3. [Restore `/boot`](#restore-boot-from-bootbackup) from `/.bootbackup`.
4. Reboot.

If btrfs-assistant warns about `subvolid` in `/etc/fstab`, prefer `subvol=@` over `subvolid=` entries (see [Troubleshooting](#troubleshooting)).

### B — Restore `/` from GRUB snapshot entry

Use to **test** a snapshot or recover when the installed system will not start normally.

1. Reboot → GRUB → **Snapshots** → pick a snapshot (read-only + overlayfs).
2. Log in, confirm the system is the state you want.
3. Either:
   - **Make permanent:** btrfs-assistant → Restore that snapshot (as in A), then restore `/boot`, reboot; or
   - **One-off session:** reboot without restoring — changes made in the overlay session are discarded.

### C — Restore `/` from live ISO

Use when the installed system does not boot or you want maximum control. Pick **manual** or **snapper-rollback** — same result for `@`; both still need [/boot restore](#restore-boot-from-bootbackup).

#### C1 — Manual (Arch Wiki)

From [Restoring / to its previous snapshot](https://wiki.archlinux.org/title/Snapper#Restoring_/_to_its_previous_snapshot):

1. Boot Arch live ISO, unlock LUKS if needed.
2. Mount top-level btrfs (no `subvol=`): `mount /dev/mapper/luks_root /mnt`
3. Find snapshot: `grep -r '<date>' /mnt/@snapshots/*/info.xml` → note `N`
4. Move broken `@`: `mv /mnt/@ /mnt/@.broken` (or `btrfs subvolume delete /mnt/@`)
5. `btrfs subvolume snapshot /mnt/@snapshots/N/snapshot /mnt/@`
6. Mount `@` at `/mnt` (if needed), mount `/boot` and ESP; `arch-chroot /mnt`
7. [Restore `/boot`](#restore-boot-from-bootbackup)
8. `mkinitcpio -P && grub-mkconfig -o /boot/grub/grub.cfg`
9. Reboot.

#### C2 — snapper-rollback (same steps, automated)

Requires `snapper-rollback` (AUR) and `/etc/snapper-rollback.conf` (installed by `./setup arch`).

1. Boot Arch live ISO, unlock LUKS: `cryptsetup open /dev/<root_partition> luks_root`
2. Edit config if device names differ on live ISO:

   ```bash
   sudo mkdir -p /btrfsroot
   sudo nvim /etc/snapper-rollback.conf   # or copy from your backup
   # mountpoint = /btrfsroot
   # dev = /dev/mapper/luks_root
   ```

3. List snapshots (mount top-level first if `snapper` not available in live session):

   ```bash
   sudo mount /dev/mapper/luks_root /btrfsroot
   sudo snapper -c root list   # if snapper installed in live ISO
   # or: grep -r '<date>' /btrfsroot/@snapshots/*/info.xml
   ```

4. Run rollback (script mounts `dev` → `mountpoint`, replaces `@` from snapshot `N`):

   ```bash
   sudo snapper-rollback N
   # Type CONFIRM when prompted
   ```

5. Mount restored system, `arch-chroot`, [restore `/boot`](#restore-boot-from-bootbackup), `mkinitcpio -P`, `grub-mkconfig`, reboot.

**What snapper-rollback does *not* do:** copy `/.bootbackup` to `/boot`, regenerate initramfs, or fix fstab — those remain manual (steps 5+ above).

### D — Restore `/home`

Same pattern on the home volume: replace `@home` from `/home/.snapshots/N/snapshot` (live ISO or btrfs-assistant home config). `/boot` is unaffected.

### Restore `/boot` from `/.bootbackup`

After any `@` restore, ext4 `/boot` still reflects the **current** kernel tree until you copy a backup from the **restored** snapshot:

```bash
# List backups captured inside the running (or chrooted) system
ls -lt /.bootbackup/

# Prefer a *_post backup from before the failure, ideally matching snapshot date
sudo rsync -a --delete /.bootbackup/YYYY_MM_DD_HH.MM.SS_post/ /boot/

sudo mkinitcpio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

If `/.bootbackup` is empty, backups only start after hooks are installed and a kernel-affecting `pacman` transaction runs once.

### Troubleshooting

| Symptom | Likely cause | Fix |
|---------|----------------|-----|
| Boot fails after restore | `/boot` not restored | rsync from `/.bootbackup/*_post/` (above) |
| Empty `/.bootbackup` | Hooks missing or no kernel update since install | Install hooks; run `paru -S linux` (reinstall) — `mkinitcpio -P` alone does not trigger bootbackup hooks |
| KDE/login fails from GRUB snapshot | Read-only `/var` | Add `grub-btrfs-overlayfs` to mkinitcpio HOOKS; regenerate initramfs |
| `grub-btrfs-overlayfs` silent failure | `systemd` hook in mkinitcpio | Use `udev` hook instead (Arch Wiki) |
| btrfs-assistant restore warning | `subvolid=` in `/etc/fstab` | Use `subvol=@` paths; backup fstab first |
| No GRUB snapshot entries | `grub-btrfsd` not running or wrong path | Check `systemctl status grub-btrfsd`; override uses `--syslog /.snapshots` |
| snap-pac snapshots missing `/boot` state | bootbackup runs after snap-pac post | Rename hook to `95-bootbackup_post.hook` (before `zz-snap-pac-post`) |
| `snapper create-config` fails | `/.snapshots` already mounted from install | umount + rm, then follow [Configure Snapper](#configure-snapper) |
