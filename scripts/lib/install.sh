#!/usr/bin/env bash
# Shared Arch install/reinstall helpers.
#
# Source from scripts/install-arch or scripts/install-arch-reinstall:
#   REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "${REPO_ROOT}/scripts/lib/install.sh"

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${_LIB_DIR}/../.." && pwd)}"
# shellcheck source=common.sh
source "${_LIB_DIR}/common.sh"

# Defaults — callers override as needed
: "${MNT:=/mnt}"
: "${BTRFS_MOUNT_OPTS:=noatime,ssd,compress=zstd,space_cache=v2,discard=async,commit=120}"
: "${REFLECTOR_COUNTRY:=Finland}"
: "${REFLECTOR_AGE:=12}"
: "${REFLECTOR_COUNTRIES:=Finland,Sweden}"
: "${TIMEZONE:=Europe/Helsinki}"
: "${KEYMAP:=fi}"
: "${VG_ROOT:=arch}"
: "${VG_HOME:=arch_home}"
: "${LV_ROOT:=root}"
: "${LV_HOME:=home}"
: "${LV_SWAP:=swap}"
: "${ENCRYPTION_ENABLED:=false}"
: "${HIBERNATION_ENABLED:=false}"
: "${SWAP_TYPE:=}"
: "${INSTALL_PRESERVE_HOME:=false}"

# ============================================================================
# Tool checks
# ============================================================================

_check_filesystem_tools() {
    local cmd missing=()

    for cmd in mkfs.btrfs mkfs.fat mkfs.ext4 mkswap mount btrfs umount findmnt; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        _error "Missing filesystem tools: ${missing[*]}"
        return 1
    fi

    return 0
}

_check_bootstrap_tools() {
    local cmd missing=()

    for cmd in reflector pacstrap genfstab arch-chroot; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        _error "Missing bootstrap tools: ${missing[*]}"
        return 1
    fi

    return 0
}

_check_crypt_tools() {
    command -v cryptsetup &>/dev/null || {
        _error "cryptsetup not found. Install it or use the Arch live ISO."
        return 1
    }
    return 0
}

# ============================================================================
# Device / mount helpers
# ============================================================================

_get_swap_device() {
    if [ -n "${SWAP_DEVICE:-}" ]; then
        echo "$SWAP_DEVICE"
        return 0
    fi

    if [ "$SWAP_TYPE" = "lvm" ] && [ -n "${SWAP_LV:-}" ]; then
        echo "$SWAP_LV"
    elif [ -n "${SWAP_PARTITION:-}" ]; then
        echo "$SWAP_PARTITION"
    fi
}

_chroot_run() {
    _log "RUN" "arch-chroot ${MNT} $*"
    arch-chroot "$MNT" "$@"
}

_get_uuid() {
    blkid -s UUID -o value "$1"
}

_reinstall_backup_root() {
    echo "${MNT}/home/${INSTALL_USERNAME}/install"
}

_resolve_live_backup_root() {
    local username backup_home

    if [ -n "${INSTALL_BACKUP_ROOT:-}" ]; then
        echo "$INSTALL_BACKUP_ROOT"
        return 0
    fi

    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        username="$SUDO_USER"
    elif [ -n "${INSTALL_USERNAME:-}" ]; then
        username="$INSTALL_USERNAME"
    else
        username="${USER:-$(whoami)}"
    fi

    if [ "$username" = "root" ]; then
        _error "Run with sudo as your normal user, or set INSTALL_USERNAME"
        return 1
    fi

    backup_home=$(getent passwd "$username" | cut -d: -f6)
    if [ -z "$backup_home" ] || [ ! -d "$backup_home" ]; then
        _error "Home directory not found for user: ${username}"
        return 1
    fi

    echo "${backup_home}/install"
}

_backup_reinstall_configs() {
    local backup_root src dest rel optional missing_required=0

    backup_root=$(_resolve_live_backup_root) || return 1

    _section "Reinstall config backup"
    _info "Destination: ${backup_root}/etc/"

    _echo_run mkdir -p \
        "${backup_root}/etc/default" \
        "${backup_root}/etc/xdg/reflector" \
        "${backup_root}/etc/snapper/configs" \
        "${backup_root}/etc/systemd"

    declare -a required_files=(
        "/etc/pacman.conf|etc/pacman.conf"
        "/etc/default/grub|etc/default/grub"
        "/etc/mkinitcpio.conf|etc/mkinitcpio.conf"
        "/etc/locale.conf|etc/locale.conf"
        "/etc/vconsole.conf|etc/vconsole.conf"
        "/etc/hostname|etc/hostname"
        "/etc/hosts|etc/hosts"
        "/etc/systemd/timesyncd.conf|etc/systemd/timesyncd.conf"
        "/etc/xdg/reflector/reflector.conf|etc/xdg/reflector/reflector.conf"
    )

    declare -a optional_files=(
        "/etc/crypttab|etc/crypttab"
    )

    declare -a optional_dirs=(
        "/etc/luks_keys|etc/luks_keys"
        "/etc/snapper/configs|etc/snapper/configs"
    )

    for rel in "${required_files[@]}"; do
        src="${rel%%|*}"
        dest="${backup_root}/${rel#*|}"

        if [ ! -e "$src" ]; then
            _warn "Missing required source: ${src}"
            missing_required=1
            continue
        fi

        _info "Copying ${src}"
        _echo_run cp -a "$src" "$dest"
    done

    for rel in "${optional_files[@]}"; do
        src="${rel%%|*}"
        dest="${backup_root}/${rel#*|}"

        if [ ! -e "$src" ]; then
            _info "Skipping optional: ${src}"
            continue
        fi

        _info "Copying ${src}"
        _echo_run cp -a "$src" "$dest"
    done

    for rel in "${optional_dirs[@]}"; do
        src="${rel%%|*}"
        dest="${backup_root}/${rel#*|}"

        if [ ! -e "$src" ]; then
            _info "Skipping optional: ${src}"
            continue
        fi

        _info "Copying ${src}"
        _echo_run mkdir -p "$(dirname "$dest")"
        _echo_run cp -a "$src" "$dest"
    done

    if [ "$missing_required" -eq 1 ]; then
        _error "Some required config files were missing"
        return 1
    fi

    _info "Config backup completed: ${backup_root}/etc/"
    return 0
}

# ============================================================================
# Btrfs subvolumes and mounts
# ============================================================================

_create_root_btrfs_subvolumes() {
    local root_lv=$1

    _info "Creating root btrfs subvolumes on ${root_lv}..."

    if mountpoint -q "$MNT"; then
        _error "$MNT is already mounted. Unmount it before continuing."
        return 1
    fi

    _echo_run mount "$root_lv" "$MNT" || return 1
    _echo_run btrfs subvolume create "$MNT/@" || return 1
    _echo_run btrfs subvolume create "$MNT/@snapshots" || return 1
    _echo_run btrfs subvolume create "$MNT/@var_log" || return 1
    _echo_run btrfs subvolume create "$MNT/@var_cache" || return 1
    _echo_run btrfs subvolume create "$MNT/@var_tmp" || return 1
    _echo_run btrfs subvolume create "$MNT/@var_spool" || return 1
    _echo_run btrfs subvolume create "$MNT/@var_lib_containers" || return 1
    _echo_run btrfs subvolume create "$MNT/@var_lib_docker" || return 1
    _echo_run btrfs subvolume create "$MNT/@var_lib_libvirt" || return 1
    _echo_run umount -R "$MNT" || return 1

    return 0
}

_create_home_btrfs_subvolumes() {
    local home_lv=$1

    _info "Creating home btrfs subvolumes on ${home_lv}..."

    _echo_run mount --mkdir "$home_lv" "${MNT}/home" || return 1
    _echo_run btrfs subvolume create "${MNT}/home/@home" || return 1
    _echo_run btrfs subvolume create "${MNT}/home/@home_snapshots" || return 1
    _echo_run btrfs subvolume create "${MNT}/home/@home/@media" || return 1
    _echo_run umount -R "$MNT" || return 1

    return 0
}

_create_btrfs_subvolumes() {
    _create_root_btrfs_subvolumes "$ROOT_LV" || return 1

    if [ "$INSTALL_PRESERVE_HOME" != true ]; then
        _create_home_btrfs_subvolumes "$HOME_LV" || return 1
    fi

    return 0
}

_mount_installation() {
    local btrfs_opts="$BTRFS_MOUNT_OPTS"
    local swap_device

    _info "Mounting installation target at $MNT..."

    if mountpoint -q "$MNT"; then
        _error "$MNT is already mounted. Unmount it before continuing."
        return 1
    fi

    _echo_run mount -o "$btrfs_opts,subvol=/@" "$ROOT_LV" "$MNT" || return 1
    _echo_run mount --mkdir -o "$btrfs_opts,subvol=/@snapshots" "$ROOT_LV" "${MNT}/.snapshots" || return 1
    _echo_run mount --mkdir -o "$btrfs_opts,subvol=/@var_log" "$ROOT_LV" "${MNT}/var/log" || return 1
    _echo_run mount --mkdir -o "$btrfs_opts,subvol=/@var_cache" "$ROOT_LV" "${MNT}/var/cache" || return 1
    _echo_run mount --mkdir -o "$btrfs_opts,subvol=/@var_tmp" "$ROOT_LV" "${MNT}/var/tmp" || return 1
    _echo_run mount --mkdir -o "$btrfs_opts,subvol=/@var_spool" "$ROOT_LV" "${MNT}/var/spool" || return 1
    _echo_run mount --mkdir -o "$btrfs_opts,subvol=/@var_lib_containers" "$ROOT_LV" "${MNT}/var/lib/containers" || return 1
    _echo_run mount --mkdir -o "$btrfs_opts,subvol=/@var_lib_docker" "$ROOT_LV" "${MNT}/var/lib/docker" || return 1
    _echo_run mount --mkdir -o "$btrfs_opts,subvol=/@var_lib_libvirt" "$ROOT_LV" "${MNT}/var/lib/libvirt" || return 1
    _echo_run mount --mkdir "$BOOT_PARTITION" "${MNT}/boot" || return 1
    _echo_run mount --mkdir "$EFI_PARTITION" "${MNT}/boot/efi" || return 1
    _echo_run mount --mkdir -o "$btrfs_opts,subvol=/@home" "$HOME_LV" "${MNT}/home" || return 1
    _echo_run mount --mkdir -o "$btrfs_opts,subvol=/@home_snapshots" "$HOME_LV" "${MNT}/home/.snapshots" || return 1

    if [ "$INSTALL_PRESERVE_HOME" != true ] && [ -n "${INSTALL_USERNAME:-}" ]; then
        _echo_run mount --mkdir -o "$btrfs_opts,subvol=/@home/@media" "$HOME_LV" "${MNT}/home/${INSTALL_USERNAME}/Media" || return 1
    fi

    swap_device=$(_get_swap_device)
    if [ -n "$swap_device" ]; then
        _info "Enabling swap: $swap_device"
        _echo_run swapon "$swap_device" || return 1
    fi

    return 0
}

_print_mount_summary() {
    _section "Mount Summary"
    _log_cmd_output findmnt -R "$MNT"
    _out "=========================================="
    _out ""
}

# ============================================================================
# Bootstrap
# ============================================================================

_configure_live_mirrors() {
    _info "Configuring pacman mirrors (${REFLECTOR_COUNTRY})..."
    _echo_run reflector \
        -c "$REFLECTOR_COUNTRY" \
        -a "$REFLECTOR_AGE" \
        --protocol https \
        --sort rate \
        --download-timeout 60 \
        --save /etc/pacman.d/mirrorlist || return 1
}

_pacstrap_base_packages() {
    _info "Installing base packages with pacstrap (this may take a while)..."
    _echo_run pacstrap "$MNT" base base-devel || return 1
}

_generate_fstab() {
    _info "Generating fstab..."
    _echo_run genfstab -U "$MNT" >>"${MNT}/etc/fstab" || return 1
}

_setup_bootstrap() {
    _check_bootstrap_tools
    _propagate_rc $? || return $?

    _configure_live_mirrors
    _propagate_rc $? || return $?

    _pacstrap_base_packages
    _propagate_rc $? || return $?

    _generate_fstab
    _propagate_rc $? || return $?

    _info "Bootstrap completed"
    return 0
}

# ============================================================================
# Chroot boot (fresh install)
# ============================================================================

_build_mkinitcpio_hooks() {
    local hooks="base udev autodetect modconf kms keyboard keymap consolefont block"

    if [ "$ENCRYPTION_ENABLED" = true ]; then
        hooks+=" encrypt"
    fi

    hooks+=" lvm2 filesystems"

    if [ "$HIBERNATION_ENABLED" = true ]; then
        hooks+=" resume"
    fi

    hooks+=" fsck"
    echo "$hooks"
}

_configure_pacman_chroot() {
    local threads

    threads=$(nproc)
    _info "Setting ParallelDownloads to ${threads} in pacman.conf..."

    _chroot_run sed -i \
        -e "s/^#ParallelDownloads = .*/ParallelDownloads = ${threads}/" \
        -e "s/^ParallelDownloads = .*/ParallelDownloads = ${threads}/" \
        /etc/pacman.conf || return 1
}

_install_system_packages() {
    _info "Installing kernel, firmware, and system packages..."

    _chroot_run pacman -S --noconfirm \
        neovim \
        linux linux-headers linux-lts linux-lts-headers \
        linux-firmware sof-firmware \
        dosfstools lvm2 sudo cryptsetup btrfs-progs \
        vim man-db man-pages texinfo git xdg-user-dirs || return 1
}

_configure_mkinitcpio() {
    local hooks

    hooks=$(_build_mkinitcpio_hooks)
    _info "Configuring mkinitcpio (MODULES=btrfs, HOOKS=${hooks})..."

    _chroot_run sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf || return 1
    _chroot_run sed -i "s/^HOOKS=.*/HOOKS=(${hooks})/" /etc/mkinitcpio.conf || return 1

    if [ "$ENCRYPTION_ENABLED" != true ]; then
        _chroot_run sed -i \
            -e 's/^#FILES=.*/FILES=()/' \
            -e 's/^FILES=.*/FILES=()/' \
            /etc/mkinitcpio.conf || return 1
    fi
}

_install_grub_bootloader() {
    _info "Installing GRUB bootloader..."

    _chroot_run pacman -S --noconfirm grub efibootmgr || return 1
    _chroot_run grub-install --efi-directory=/boot/efi || return 1
}

_configure_encryption_boot() {
    local root_part_uuid root_lv_uuid home_part_uuid
    local grub_cmdline

    root_part_uuid=$(_get_uuid "$ROOT_PARTITION")
    root_lv_uuid=$(_get_uuid "$ROOT_LV")
    home_part_uuid=$(_get_uuid "$HOME_PARTITION")

    if [ -z "$root_part_uuid" ] || [ -z "$root_lv_uuid" ] || [ -z "$home_part_uuid" ]; then
        _error "Failed to resolve UUIDs for encrypted boot configuration"
        return 1
    fi

    _info "Configuring encrypted boot (GRUB, keyfiles, crypttab)..."

    _chroot_run mkdir -p /etc/luks_keys || return 1
    _chroot_run dd if=/dev/urandom of=/etc/luks_keys/root_keyfile.bin bs=512 count=8 status=none || return 1
    _chroot_run dd if=/dev/urandom of=/etc/luks_keys/home_keyfile.bin bs=512 count=8 status=none || return 1
    _chroot_run chmod 700 /etc/luks_keys || return 1
    _chroot_run chmod 000 /etc/luks_keys/root_keyfile.bin /etc/luks_keys/home_keyfile.bin || return 1

    _info "Adding LUKS keyfiles to encrypted partitions..."
    _log_interactive cryptsetup luksAddKey "$ROOT_PARTITION" "${MNT}/etc/luks_keys/root_keyfile.bin"
    cryptsetup luksAddKey "$ROOT_PARTITION" "${MNT}/etc/luks_keys/root_keyfile.bin" || return 1
    _log_interactive cryptsetup luksAddKey "$HOME_PARTITION" "${MNT}/etc/luks_keys/home_keyfile.bin"
    cryptsetup luksAddKey "$HOME_PARTITION" "${MNT}/etc/luks_keys/home_keyfile.bin" || return 1

    grub_cmdline="loglevel=3 quiet root=UUID=${root_lv_uuid} cryptdevice=UUID=${root_part_uuid}:luks_root"
    _chroot_run sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${grub_cmdline}\"|" \
        /etc/default/grub || return 1

    _chroot_run sed -i \
        -e 's/^#FILES=.*/FILES=(\/etc\/luks_keys\/root_keyfile.bin)/' \
        -e 's/^FILES=.*/FILES=(\/etc\/luks_keys\/root_keyfile.bin)/' \
        /etc/mkinitcpio.conf || return 1

    printf '%s\t%s\t%s\t%s\n' \
        "luks_home" "UUID=${home_part_uuid}" "/etc/luks_keys/home_keyfile.bin" "luks,initramfs" \
        >>"${MNT}/etc/crypttab"

    return 0
}

_generate_boot_images() {
    _info "Generating GRUB config and initramfs images..."

    _chroot_run grub-mkconfig -o /boot/grub/grub.cfg || return 1
    _chroot_run grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg || return 1
    _chroot_run mkinitcpio -p linux || return 1
    _chroot_run mkinitcpio -p linux-lts || return 1
    _chroot_run bash -c 'chmod 600 /boot/initramfs-linux* 2>/dev/null || true'
}

_setup_chroot_boot() {
    _info "Configuring bootable system inside chroot"

    _configure_pacman_chroot
    _propagate_rc $? || return $?

    _install_system_packages
    _propagate_rc $? "Failed to install system packages" || return $?

    _configure_mkinitcpio
    _propagate_rc $? || return $?

    _install_grub_bootloader
    _propagate_rc $? "Failed to install GRUB" || return $?

    if [ "$ENCRYPTION_ENABLED" = true ]; then
        _configure_encryption_boot
        _propagate_rc $? "Failed to configure encrypted boot" || return $?
    fi

    _generate_boot_images
    _propagate_rc $? "Failed to generate boot images" || return $?

    _info "Boot setup completed"
    return 0
}

# ============================================================================
# Reinstall: LUKS, root format, config restore
# ============================================================================

_load_crypt_modules() {
    _info "Loading encryption kernel modules..."
    _echo_run modprobe dm-crypt || return 1
    _echo_run modprobe dm-mod || return 1
}

_open_luks_partition() {
    local partition=$1
    local mapper_name=$2

    if [ -e "/dev/mapper/${mapper_name}" ]; then
        _info "LUKS device /dev/mapper/${mapper_name} already open"
        return 0
    fi

    _info "Opening ${partition} as ${mapper_name}..."
    _log_interactive cryptsetup open "$partition" "$mapper_name"
    cryptsetup open "$partition" "$mapper_name" || {
        _error "Failed to open $partition as $mapper_name"
        return 1
    }

    return 0
}

_activate_volume_groups() {
    _info "Scanning and activating volume groups..."
    _echo_run vgscan || return 1
    _echo_run vgchange -ay || return 1
}

_format_root_btrfs() {
    _out ""
    _warn "WARNING: This will format ${ROOT_LV} and destroy all data on the root volume."
    _warn "The /home volume (${HOME_LV}) will NOT be formatted."
    _out ""

    if ! _prompt_yes_no "Format ${ROOT_LV} with btrfs? (y/n): "; then
        _info "Root format cancelled by user"
        return 2
    fi

    _info "Formatting root volume: ${ROOT_LV}"
    _echo_run mkfs.btrfs -f -L root "$ROOT_LV" || return 1

    return 0
}

_reinstall_restore_path() {
    local rel_path=$1
    local backup_root dest src

    backup_root=$(_reinstall_backup_root)
    src="${backup_root}/${rel_path}"
    dest="${MNT}/${rel_path}"

    if [ ! -e "$src" ]; then
        _warn "Backup missing: ${src}"
        return 1
    fi

    if [ -e "$dest" ]; then
        _info "Backing up existing ${rel_path} to ${rel_path}.bak"
        _echo_run mv "$dest" "${dest}.bak"
    fi

    if [ -d "$src" ]; then
        _echo_run mkdir -p "$(dirname "$dest")"
        _echo_run cp -a "$src" "$dest"
    else
        _echo_run mkdir -p "$(dirname "$dest")"
        _echo_run cp -a "$src" "$dest"
    fi

    return 0
}

_verify_reinstall_backup() {
    local backup_root required missing=0

    backup_root=$(_reinstall_backup_root)

    if [ ! -d "$backup_root/etc" ]; then
        _error "Reinstall backup not found at ${backup_root}/etc"
        _error "Back up configs to ~/install/etc/ before reinstalling (see arch-reinstall.md)"
        return 1
    fi

    for required in etc/pacman.conf etc/mkinitcpio.conf etc/default/grub; do
        if [ ! -f "${backup_root}/${required}" ]; then
            _warn "Missing backup file: ${required}"
            missing=1
        fi
    done

    if [ "$missing" -eq 1 ]; then
        if ! _prompt_yes_no "Some backup files are missing. Continue anyway? (y/n): "; then
            return 2
        fi
    fi

    _info "Reinstall backup found at ${backup_root}"
    return 0
}

_setup_chroot_boot_reinstall() {
    _info "Restoring boot configuration from reinstall backup"

    _reinstall_restore_path etc/pacman.conf || return 1

    _install_system_packages
    _propagate_rc $? "Failed to install system packages" || return $?

    _reinstall_restore_path etc/mkinitcpio.conf || return 1

    _install_grub_bootloader
    _propagate_rc $? "Failed to install GRUB" || return $?

    _reinstall_restore_path etc/default/grub || return 1

    if [ -f "$(_reinstall_backup_root)/etc/crypttab" ]; then
        ENCRYPTION_ENABLED=true
        _reinstall_restore_path etc/crypttab || return 1
        _reinstall_restore_path etc/luks_keys || return 1
    fi

    _generate_boot_images
    _propagate_rc $? "Failed to generate boot images" || return $?

    _info "Reinstall boot setup completed"
    return 0
}

# ============================================================================
# Localization
# ============================================================================

_prompt_hostname() {
    _section "System Hostname"

    while true; do
        read -p "Enter hostname: " INSTALL_HOSTNAME

        if [[ $INSTALL_HOSTNAME =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
            _info "Hostname set to: $INSTALL_HOSTNAME"
            return 0
        fi

        _error "Invalid hostname. Use letters, numbers, underscore, or hyphen."
    done
}

_prompt_timezone() {
    local timezone

    _section "Timezone"
    _out "Default: $TIMEZONE"
    _out "Format: Region/City (e.g. Europe/Helsinki)"
    _out ""

    while true; do
        read -p "Enter timezone [${TIMEZONE}]: " timezone
        timezone=${timezone:-$TIMEZONE}

        if [ -f "/usr/share/zoneinfo/${timezone}" ] || [ -f "${MNT}/usr/share/zoneinfo/${timezone}" ]; then
            TIMEZONE=$timezone
            _info "Timezone set to: $TIMEZONE"
            return 0
        fi

        _error "Invalid timezone: $timezone"
    done
}

_prompt_install_username() {
    local username

    _section "Installation Username"
    _out "Used for home path and reinstall backup (~/install/etc/)."
    _out ""

    while true; do
        read -p "Enter username: " username

        if [[ $username =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            INSTALL_USERNAME=$username
            _info "Username set to: $INSTALL_USERNAME"
            return 0
        fi

        _error "Invalid username. Use lowercase letters, numbers, underscore, or hyphen."
    done
}

_configure_timezone() {
    _info "Setting timezone to $TIMEZONE..."

    _chroot_run ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime || return 1
    _chroot_run hwclock --systohc || return 1
}

_configure_timesyncd() {
    _info "Configuring systemd-timesyncd..."

    _chroot_run sed -i \
        -e 's/^#NTP=.*/NTP=0.arch.pool.ntp.org 1.arch.pool.ntp.org 2.arch.pool.ntp.org 3.arch.pool.ntp.org/' \
        -e 's/^NTP=.*/NTP=0.arch.pool.ntp.org 1.arch.pool.ntp.org 2.arch.pool.ntp.org 3.arch.pool.ntp.org/' \
        -e 's/^#FallbackNTP=.*/FallbackNTP=0.pool.ntp.org 1.pool.ntp.org/' \
        -e 's/^FallbackNTP=.*/FallbackNTP=0.pool.ntp.org 1.pool.ntp.org/' \
        /etc/systemd/timesyncd.conf || return 1

    _chroot_run systemctl enable systemd-timesyncd.service || return 1
    _chroot_run timedatectl set-ntp true || return 1
}

_configure_locales() {
    _info "Configuring locales (en_US.UTF-8, fi_FI.UTF-8)..."

    _chroot_run sed -i \
        -e 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' \
        -e 's/^#fi_FI.UTF-8 UTF-8/fi_FI.UTF-8 UTF-8/' \
        /etc/locale.gen || return 1
    _chroot_run locale-gen || return 1

    cat >"${MNT}/etc/locale.conf" <<'EOF'
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
EOF

    _chroot_run mkdir -p /boot/grub/locale || return 1
    _chroot_run cp /usr/share/locale/en@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo || return 1
}

_configure_keyboard() {
    _info "Configuring console keyboard (${KEYMAP})..."

    cat >"${MNT}/etc/vconsole.conf" <<EOF
KEYMAP=${KEYMAP}
XKBLAYOUT=${KEYMAP}
XKBMODEL=pc106
XKBVARIANT=winkeys
EOF
}

_setup_localization() {
    _prompt_hostname
    _propagate_rc $? || return $?

    _prompt_timezone
    _propagate_rc $? || return $?

    _info "Configuring localization"

    _configure_timezone
    _propagate_rc $? || return $?

    _configure_timesyncd
    _propagate_rc $? || return $?

    _configure_locales
    _propagate_rc $? || return $?

    _configure_keyboard
    _propagate_rc $? || return $?

    _info "Localization completed"
    return 0
}

_setup_localization_reinstall() {
    _prompt_timezone
    _propagate_rc $? || return $?

    _info "Restoring localization from reinstall backup"

    _configure_timezone
    _propagate_rc $? || return $?

    if [ -f "$(_reinstall_backup_root)/etc/systemd/timesyncd.conf" ]; then
        _reinstall_restore_path etc/systemd/timesyncd.conf || return 1
    else
        _configure_timesyncd
        _propagate_rc $? || return $?
    fi

    _chroot_run sed -i \
        -e 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' \
        -e 's/^#fi_FI.UTF-8 UTF-8/fi_FI.UTF-8 UTF-8/' \
        /etc/locale.gen || return 1
    _chroot_run locale-gen || return 1

    if [ -f "$(_reinstall_backup_root)/etc/locale.conf" ]; then
        _reinstall_restore_path etc/locale.conf || return 1
    else
        _configure_locales
        _propagate_rc $? || return $?
    fi

    if [ -f "$(_reinstall_backup_root)/etc/vconsole.conf" ]; then
        _reinstall_restore_path etc/vconsole.conf || return 1
    else
        _configure_keyboard
        _propagate_rc $? || return $?
    fi

    _chroot_run mkdir -p /boot/grub/locale || return 1
    _chroot_run cp /usr/share/locale/en@quot/LC_MESSAGES/grub.mo /boot/grub/locale/en.mo 2>/dev/null || true

    _info "Localization restore completed"
    return 0
}

# ============================================================================
# Users
# ============================================================================

_configure_hostname() {
    _info "Setting hostname to $INSTALL_HOSTNAME..."
    printf '%s\n' "$INSTALL_HOSTNAME" >"${MNT}/etc/hostname"
}

_setup_root_password() {
    _section "Root Password"
    _info "Set password for root user..."

    _log_interactive arch-chroot "$MNT" passwd root
    arch-chroot "$MNT" passwd root || return 1
}

_enable_wheel_sudo() {
    _info "Granting sudo access to wheel group..."

    printf '%%wheel ALL=(ALL:ALL) ALL\n' >"${MNT}/etc/sudoers.d/wheel"
    _chroot_run chmod 440 /etc/sudoers.d/wheel || return 1
}

_remount_media_subvolume() {
    _info "Remounting Media subvolume for $INSTALL_USERNAME..."

    _echo_run mount --mkdir \
        -o "${BTRFS_MOUNT_OPTS},subvol=/@home/@media" \
        "$HOME_LV" "${MNT}/home/${INSTALL_USERNAME}/Media" || return 1

    _chroot_run chown "${INSTALL_USERNAME}:${INSTALL_USERNAME}" \
        "/home/${INSTALL_USERNAME}/Media" || return 1
}

_setup_admin_user() {
    local media_mount="${MNT}/home/${INSTALL_USERNAME}/Media"

    _info "Creating admin user: $INSTALL_USERNAME"

    if mountpoint -q "$media_mount"; then
        _echo_run umount "$media_mount" || return 1
    fi

    _chroot_run rm -rf "/home/${INSTALL_USERNAME}" || return 1
    _chroot_run useradd -m -G wheel -s /bin/bash "$INSTALL_USERNAME" || return 1

    _section "User Password: $INSTALL_USERNAME"
    _info "Set password for $INSTALL_USERNAME..."

    _log_interactive arch-chroot "$MNT" passwd "$INSTALL_USERNAME"
    arch-chroot "$MNT" passwd "$INSTALL_USERNAME" || return 1

    _enable_wheel_sudo || return 1
    _remount_media_subvolume || return 1

    return 0
}

_setup_users() {
    _info "Configuring hostname and users"

    _configure_hostname
    _propagate_rc $? || return $?

    _setup_root_password
    _propagate_rc $? "Failed to set root password" || return $?

    _setup_admin_user
    _propagate_rc $? "Failed to create admin user" || return $?

    _info "User setup completed"
    return 0
}

_setup_users_reinstall() {
    _info "Restoring hostname and recreating admin user (preserving /home)"

    if [ -f "$(_reinstall_backup_root)/etc/hostname" ]; then
        _reinstall_restore_path etc/hostname || return 1
        INSTALL_HOSTNAME=$(cat "${MNT}/etc/hostname")
    else
        _prompt_hostname
        _propagate_rc $? || return $?
        _configure_hostname
        _propagate_rc $? || return $?
    fi

    if [ -f "$(_reinstall_backup_root)/etc/hosts" ]; then
        _reinstall_restore_path etc/hosts || return 1
    fi

    _setup_root_password
    _propagate_rc $? "Failed to set root password" || return $?

    _info "Creating admin user: $INSTALL_USERNAME (preserving existing home)"

    if _chroot_run id "$INSTALL_USERNAME" &>/dev/null; then
        _info "User $INSTALL_USERNAME already exists in target system"
        _chroot_run usermod -aG wheel "$INSTALL_USERNAME" || return 1
    elif _chroot_run test -d "/home/${INSTALL_USERNAME}"; then
        _chroot_run useradd -G wheel -s /bin/bash "$INSTALL_USERNAME" || return 1
    else
        _chroot_run useradd -m -G wheel -s /bin/bash "$INSTALL_USERNAME" || return 1
    fi

    _section "User Password: $INSTALL_USERNAME"
    _log_interactive arch-chroot "$MNT" passwd "$INSTALL_USERNAME"
    arch-chroot "$MNT" passwd "$INSTALL_USERNAME" || return 1

    _enable_wheel_sudo || return 1

    _info "User setup completed"
    return 0
}

# ============================================================================
# Desktop
# ============================================================================

_enable_multilib() {
    if _chroot_run grep -q '^\[multilib\]' /etc/pacman.conf; then
        return 0
    fi

    _info "Enabling multilib repository..."
    _chroot_run sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf || return 1
    _chroot_run pacman -Sy --noconfirm || return 1
}

_detect_cpu_microcode_package() {
    local vendor

    vendor=$(arch-chroot "$MNT" lscpu 2>/dev/null | awk -F: '/Vendor ID/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')

    case $vendor in
        *AuthenticAMD* | *AMD*)
            echo "amd-ucode"
            ;;
        *GenuineIntel* | *Intel*)
            echo "intel-ucode"
            ;;
        *)
            echo ""
            ;;
    esac
}

_prompt_cpu_microcode_package() {
    local choice

    _out ""
    _out "CPU vendor not detected automatically."
    _out "[1] amd-ucode"
    _out "[2] intel-ucode"
    _out "[3] Skip microcode"

    while true; do
        read -p "Select microcode package [1-3]: " choice

        case $choice in
            1)
                echo "amd-ucode"
                return 0
                ;;
            2)
                echo "intel-ucode"
                return 0
                ;;
            3)
                echo ""
                return 0
                ;;
            *) _error "Invalid choice." ;;
        esac
    done
}

_detect_gpu_packages() {
    local vga_line

    vga_line=$(arch-chroot "$MNT" lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1)

    if echo "$vga_line" | grep -qi 'nvidia'; then
        echo "nvidia nvidia-utils nvidia-lts"
    elif echo "$vga_line" | grep -qiE 'amd|ati|radeon'; then
        echo "mesa lib32-mesa libva-mesa-driver vulkan-radeon lib32-vulkan-radeon vulkan-mesa-implicit-layers lib32-vulkan-mesa-implicit-layers"
    elif echo "$vga_line" | grep -qi 'intel'; then
        echo "mesa lib32-mesa intel-media-driver"
    elif echo "$vga_line" | grep -qi 'vmware'; then
        echo "xf86-video-vmware"
    else
        echo ""
    fi
}

_prompt_gpu_packages() {
    local choice

    _out ""
    _out "GPU not detected automatically."
    _out "[1] AMD"
    _out "[2] Intel"
    _out "[3] Nvidia"
    _out "[4] VMware"
    _out "[5] Skip GPU drivers"

    while true; do
        read -p "Select GPU driver set [1-5]: " choice

        case $choice in
            1)
                echo "mesa lib32-mesa libva-mesa-driver vulkan-radeon lib32-vulkan-radeon vulkan-mesa-implicit-layers lib32-vulkan-mesa-implicit-layers"
                return 0
                ;;
            2)
                echo "mesa lib32-mesa intel-media-driver"
                return 0
                ;;
            3)
                echo "nvidia nvidia-utils nvidia-lts"
                return 0
                ;;
            4)
                echo "xf86-video-vmware"
                return 0
                ;;
            5)
                echo ""
                return 0
                ;;
            *) _error "Invalid choice." ;;
        esac
    done
}

_configure_reflector() {
    _info "Configuring reflector..."

    if [ -f "$(_reinstall_backup_root)/etc/xdg/reflector/reflector.conf" ] && [ "$INSTALL_PRESERVE_HOME" = true ]; then
        _reinstall_restore_path etc/xdg/reflector/reflector.conf || return 1
        return 0
    fi

    cat >"${MNT}/etc/xdg/reflector/reflector.conf" <<EOF
--save /etc/pacman.d/mirrorlist
--protocol https
--country ${REFLECTOR_COUNTRIES}
--latest 5
--sort age
EOF
}

_install_desktop_packages() {
    local microcode_pkg gpu_pkgs

    _info "Installing desktop environment and services..."

    _chroot_run pacman -S --noconfirm \
        networkmanager bluez bluez-utils reflector || return 1

    _configure_reflector || return 1

    _chroot_run systemctl enable NetworkManager || return 1
    _chroot_run systemctl enable bluetooth || return 1
    _chroot_run systemctl enable reflector.timer || return 1
    _chroot_run systemctl enable fstrim.timer || return 1

    microcode_pkg=$(_detect_cpu_microcode_package)
    if [ -z "$microcode_pkg" ]; then
        microcode_pkg=$(_prompt_cpu_microcode_package)
    fi

    if [ -n "$microcode_pkg" ]; then
        _info "Installing CPU microcode: $microcode_pkg"
        _chroot_run pacman -S --noconfirm "$microcode_pkg" || return 1
    else
        _warn "Skipping CPU microcode installation"
    fi

    _enable_multilib || return 1

    gpu_pkgs=$(_detect_gpu_packages)
    if [ -z "$gpu_pkgs" ]; then
        gpu_pkgs=$(_prompt_gpu_packages)
    fi

    if [ -n "$gpu_pkgs" ]; then
        _info "Installing GPU drivers: $gpu_pkgs"
        # shellcheck disable=SC2086
        _chroot_run pacman -S --noconfirm $gpu_pkgs || return 1
    else
        _warn "Skipping GPU driver installation"
    fi

    _chroot_run pacman -S --noconfirm \
        xorg plasma-desktop plasma-nm plasma-pa bluedevil \
        kscreen kcron ibus sddm ghostty || return 1

    _chroot_run systemctl enable sddm || return 1

    if [ "$INSTALL_PRESERVE_HOME" = true ] && [ -d "$(_reinstall_backup_root)/etc/snapper/configs" ]; then
        _info "Restoring snapper configs from backup..."
        _reinstall_restore_path etc/snapper/configs || true
    fi

    return 0
}

_setup_desktop() {
    _install_desktop_packages
    _propagate_rc $? "Failed to install desktop packages" || return $?

    _generate_boot_images
    _propagate_rc $? "Failed to regenerate boot images" || return $?

    _info "Desktop setup completed"
    return 0
}

# ============================================================================
# Finish
# ============================================================================

_finish_installation() {
    local finish_label=${1:-"Installation"}

    _section "${finish_label} Complete"
    _out "Hostname:  ${INSTALL_HOSTNAME:-<not set>}"
    _out "User:      ${INSTALL_USERNAME:-<not set>}"
    _out "Timezone:  $TIMEZONE"
    _out ""
    _out "Post-install (after reboot):"
    _out "  cd ~/Workspace/linux-setup && ./setup arch"
    _out ""
    _out "See: instructions/install/arch-install.md (Post install steps)"
    _out "     and instructions/post-install/ (App configuration steps)"
    _out "=========================================="
    _out ""

    if ! _prompt_yes_no "Unmount ${MNT} and reboot now? (y/n): "; then
        _info "Skipping reboot. Remember to umount -R ${MNT} before rebooting manually."
        return 0
    fi

    local swap_device
    swap_device=$(_get_swap_device)

    if [ -n "$swap_device" ]; then
        _info "Disabling swap: $swap_device"
        swapoff "$swap_device" 2>/dev/null || true
    fi

    if [ "$ENCRYPTION_ENABLED" = true ]; then
        _info "Closing LUKS devices..."
        cryptsetup close luks_home 2>/dev/null || true
        cryptsetup close luks_root 2>/dev/null || true
    fi

    _info "Unmounting ${MNT}..."
    umount -R "$MNT" || {
        _error "Failed to unmount ${MNT}. Reboot manually when ready."
        return 1
    }

    _info "Rebooting..."
    reboot
}
