# Arch manual install guide

For installing Arch Linux with my personal preferences.

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
```

##### Home

```bash
mount --mkdir /dev/mapper/arch_home-home /mnt/home
cd /mnt/home

btrfs subvol create @home
btrfs subvol create @snapshots
btrfs subvol create @media
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
mount --mkdir /dev/<boot_partition> /mnt/boot
mount --mkdir /dev/<EFI_partition> /mnt/boot/efi
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@home /dev/mapper/arch_home-home /mnt/home
mount --mkdir -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120,subvol=/@home/@snapshots /dev/mapper/arch_home-home /mnt/home/.snapshots
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
pacman -S mesa lib32-mesa libva-mesa-driver vulkan-radeon lib32-vulkan-radeon
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

Might need to write decrypt passphrase with US keyboard layout and set Finnish keyboard again... Need to find a fix for this.

```bash
localectl --no-convert set-keymap fi
localectl --no-convert set-x11-keymap fi pc106 winkeys

mkinitcpio -p linux
mkinitcpio -p linux-lts
```

Upgrade all packages:

```bash
pacman -Syu
```

Install tools for automatic btrfs snapshots:

```bash
sudo pacman -S grub-btrfs inotify-tools snapper
```

Stop updatedb from indexing snapshots:

```bash
sudo nvim /etc/updatedb.conf

# Add the following line
PRUNENAMES = ".snapshots"
```

Unmount snapshot subvolumes and remove the directories for snapper to create them:

```bash
sudo umount /.snapshots /home/.snapshots
sudo rm -r /.snapshots /home/.snapshots
```

Have snapper create configs for the root and home subvolumes:

```bash
sudo snapper -c root create-config /
# Set to liking
sudo nvim /etc/snapper/configs/root

# Set to liking (at least change subvolume)
sudo snapper -c home create-config /home
sudo nvim /etc/snapper/configs/home
```

Delete the resulting subvolumes and remount the subvolumes created in the install:

```bash
sudo btrfs subvol delete /.snapshots
sudo btrfs subvol delete /home/.snapshots
sudo mount /.snapshots /home/.snapshots
```

Enable snapper systemd timers:

```bash
sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
```

Add snapshots to grub menu:

```bash
sudo systemctl edit --full grub-btrfsd

# Change this line
ExecStart=/usr/bin/grub-btrfsd --syslog /.snapshots
```

Enable grub-btrfsd:

```bash
sudo systemctl enable --now grub-btrfsd
```

## Next steps

Run the personal setup script:

```bash
cd ~/Workspace/linux-setup
./setup arch
```

Install automatic snapshot tool

```bash
paru -S snap-pac
```
