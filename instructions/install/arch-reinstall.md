# Arch reinstall guide

For reinstalling Arch Linux with my personal preferences while preserving /home partition and existing configurations.

> **Automation:** On the running system before live boot: `sudo ./install arch --backup` (or manual steps in [Backup configuration files](#backup-configuration-files)). From the live ISO (as root): `./install arch --reinstall` — preserves `/home`, reformats root, restores configs from `~/install/etc/`. After reboot: `./setup arch` for [Post-install steps](#post-install-steps). This document remains the manual reference.

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

### Backup configuration files

Before starting the reinstall, back up system configs to `~/install/etc/`:

```bash
sudo ./install arch --backup
```

Or copy manually to `/home/<user>/install/`:

```bash
mkdir -p /home/<user>/install/etc/{default,xdg/reflector,snapper/configs}
mkdir -p /home/<user>/install/etc/systemd

cp /etc/pacman.conf /home/<user>/install/etc/
cp /etc/default/grub /home/<user>/install/etc/default/
cp /etc/mkinitcpio.conf /home/<user>/install/etc/
cp /etc/crypttab /home/<user>/install/etc/
cp /etc/systemd/timesyncd.conf /home/<user>/install/etc/systemd/
cp /etc/locale.conf /home/<user>/install/etc/
cp /etc/vconsole.conf /home/<user>/install/etc/
cp /etc/xdg/reflector/reflector.conf /home/<user>/install/etc/xdg/reflector/
cp /etc/hostname /home/<user>/install/etc/
cp /etc/hosts /home/<user>/install/etc/
cp -r /etc/luks_keys /home/<user>/install/etc/
cp -r /etc/snapper/configs /home/<user>/install/etc/snapper/
```

### Disk setup

#### Decrypt partitions

Open the encrypted root and home partitions with their passphrases:

```bash
cryptsetup open /dev/<root_partition> luks_root
cryptsetup open /dev/<home_partition> luks_home
```

#### Format and prepare root partition

Format only the root partition to start fresh while leaving /home intact:

```bash
mkfs.btrfs -fL root /dev/mapper/arch-root
```

#### Create btrfs subvolumes for root

Create fresh subvolumes for the root filesystem:

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

cd
umount /mnt
```

#### Mount subvolumes and partitions

Mount all partitions with the same mount options as a fresh install, preserving the /home filesystem:

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

# swap partition
swapon /dev/<swap_partition>
# or swap logical volume
swapon /dev/mapper/arch-swap
```

## Reinstallation steps

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

### Restore pacman configuration and install more needed packages

Install a text editor first:

```bash
pacman -S neovim
```

Restore and verify your pacman configuration:

```bash
mv /etc/pacman.conf /etc/pacman.conf.bak
cp /home/<user>/install/etc/pacman.conf /etc/pacman.conf

# Verify (especially ParallelDownloads = <cpu thread count>)
nvim /etc/pacman.conf
```

Install Linux kernel and related packages:

```bash
pacman -S linux linux-headers linux-lts linux-lts-headers linux-firmware sof-firmware dosfstools lvm2 sudo cryptsetup btrfs-progs vim man-db man-pages texinfo git xdg-user-dirs
```

### Restore mkinitcpio configuration

Restore your mkinitcpio configuration:

```bash
cp /home/<user>/install/etc/mkinitcpio.conf /etc/mkinitcpio.conf

# Verify
nvim /etc/mkinitcpio.conf
```

### Setup grub bootloader

Install grub and UEFI boot entry manager:

```bash
pacman -S grub efibootmgr
grub-install --efi-directory=/boot/efi
```

Restore grub configuration:

```bash
mv /etc/default/grub /etc/default/grub.bak
cp /home/<user>/install/etc/default/grub /etc/default/grub

# Verify
nvim /etc/default/grub
```

### Restore decryption to boot (optional)

Verify GRUB_CMDLINE_LINUX_DEFAULT has the correct UUIDs for your encrypted partitions.

```bash
# Get UUIDs with
blkid /dev/<root_partition>
blkid /dev/mapper/arch-root

nvim /etc/default/grub
```

Restore encryption keyfiles:

```bash
cp -r /home/<user>/install/etc/luks_keys /etc/
```

Verify mkinitcpio config has the root key file in FILES:

```bash
nvim /etc/mkinitcpio.conf

# Check this line
FILES(/etc/luks_keys/root_keyfile.bin)
```

Restore crypttab configuration for automatic partition decryption:

```bash
mv /etc/crypttab /etc/crypttab.bak
cp /home/<user>/install/etc/crypttab /etc/crypttab
```

Verify the crypttab entries are correct for your encryption setup.

```bash
# Get UUID with
blkid /dev/<home_partition>

nvim /etc/crypttab
```

### Add localization

#### Set time and date

Set your timezone:

```bash
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc
```

Restore time sync configuration:

```bash
mv /etc/systemd/timesyncd.conf /etc/systemd/timesyncd.conf.bak
cp /home/<user>/install/etc/systemd/timesyncd.conf /etc/systemd/timesyncd.conf

# Verify
nvim /etc/systemd/timesyncd.conf
```

Enable time synchronization:

```bash
systemctl enable systemd-timesyncd.service
timedatectl set-ntp true
```

#### Set language and other localization

Generate locales:

```bash
nvim /etc/locale.gen

# Uncomment locales you want:
en_US.UTF-8 UTF-8
fi_FI.UTF-8 UTF-8

locale-gen
```

Restore your locale configuration:

```bash
cp /home/<user>/install/etc/locale.conf /etc/locale.conf

# Verify
nvim /etc/locale.conf
```

Copy grub locale support:

```bash
cp /usr/share/locale/en@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo
```

#### Set keyboard and hostname

Restore console keyboard configuration:

```bash
cp /home/<user>/install/etc/vconsole.conf /etc/vconsole.conf

#Verify
nvim /etc/vconsole.conf
```

### Set hostname, add root password and create an admin user

Add your chosen hostname for the computer to this file:

```bash
nvim /etc/hostname
```

Or restore from your backup:

```bash
cp /home/<user>/install/etc/hostname /etc/hostname

# Verify
nvim /etc/hostname
```

Restore hosts from backup:

```bash
cp /home/<user>/install/etc/hosts /etc/hosts

# Verify
nvim /etc/hosts
```

Add password for the root user:

```bash
passwd
```

Recreate your admin user:

```bash
useradd -m -G wheel -s /bin/bash <username>
passwd <username>

# Add sudo permissions by uncommenting wheel group at the bottom (with or without password)
EDITOR=nvim visudo
```

### Install KDE plasma and packages for basic functionality

Install basic utilities with systemd daemons or timers:

```bash
pacman -S networkmanager bluez bluez-utils reflector
```

Restore reflector configuration:

```bash
cp /home/<user>/install/etc/xdg/reflector/reflector.conf /etc/xdg/reflector/reflector.conf

# Verify
nvim /etc/xdg/reflector/reflector.conf
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
# Check what CPU you have
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
pacman -S mesa lib32-mesa libva-mesa-driver vulkan-radeon lib32-vulkan-radeon
# Intel (Broadwell or newer)
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

### Finish reinstallation

Exit chroot, unmount everything and reboot:

```bash
exit
umount -R /mnt
reboot now
```

## Post-install steps

Same as a fresh install — see [arch-install.md — Post install steps](arch-install.md#post-install-steps) and [Rollback and restore](arch-install.md#rollback-and-restore).

> **Shortcut:** `cd ~/Workspace/linux-setup && ./setup arch`

Restored `/etc/snapper/configs/` from backup may be reused; still run Snapper remount dance if `/.snapshots` paths changed. Reinstall **must** restore `/boot` from `/.bootbackup` after any `@` rollback (see arch-install.md).

## Next steps

```bash
cd ~/Workspace/linux-setup
./setup arch
```
