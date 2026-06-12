#!/usr/bin/env bash

# Arch Linux reinstall — preserves /home, reformats root only.
# Automates instructions/install/arch-reinstall.md
#
# Exit codes:
#   0 - success
#   1 - error
#   2 - user cancelled

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/install.sh
source "${REPO_ROOT}/scripts/lib/install.sh"
init_logging "install-arch-reinstall"

INSTALL_PRESERVE_HOME=true

# Resolved paths (prompted or defaulted)
ROOT_PARTITION=""
HOME_PARTITION=""
BOOT_PARTITION=""
EFI_PARTITION=""
SWAP_DEVICE=""
ROOT_LV="/dev/mapper/${VG_ROOT}-${LV_ROOT}"
HOME_LV="/dev/mapper/${VG_HOME}-${LV_HOME}"

# ============================================================================
# Reinstall prompts
# ============================================================================

_prompt_block_device() {
    local prompt_msg=$1
    local var_name=$2
    local default=${3:-}
    local value

    while true; do
        if [ -n "$default" ]; then
            read -r -p "${prompt_msg} [${default}]: " value
            value=${value:-$default}
        else
            read -r -p "${prompt_msg}: " value
        fi

        if [[ ! "$value" =~ ^/dev/ ]]; then
            value="/dev/${value}"
        fi

        if [ -b "$value" ]; then
            printf -v "$var_name" '%s' "$value"
            _info "Using ${var_name//_/}: $value"
            return 0
        fi

        _error "Block device not found: $value"
    done
}

_prompt_optional_block_device() {
    local prompt_msg=$1
    local var_name=$2
    local value

    read -r -p "${prompt_msg} (leave empty to skip): " value

    if [ -z "$value" ]; then
        printf -v "$var_name" '%s' ""
        _info "Skipping ${var_name//_/}"
        return 0
    fi

    if [[ ! "$value" =~ ^/dev/ ]]; then
        value="/dev/${value}"
    fi

    if [ -b "$value" ]; then
        printf -v "$var_name" '%s' "$value"
        _info "Using ${var_name//_/}: $value"
        return 0
    fi

    _error "Block device not found: $value"
    return 1
}

_prompt_lv_path() {
    local prompt_msg=$1
    local var_name=$2
    local default=$3
    local value

    while true; do
        read -r -p "${prompt_msg} [${default}]: " value
        value=${value:-$default}

        if [ -b "$value" ]; then
            printf -v "$var_name" '%s' "$value"
            _info "Using ${var_name//_/}: $value"
            return 0
        fi

        _error "Logical volume not found: $value (open LUKS/LVM first?)"
    done
}

_prompt_reinstall_layout() {
    _section "Reinstall storage layout"
    _out "Back up configs first: sudo ./install arch --backup (see arch-reinstall.md)."
    _out ""

    _prompt_install_username
    _propagate_rc $? || return $?

    _out ""
    if _prompt_yes_no "Are root and home on LUKS-encrypted partitions? (y/n): "; then
        ENCRYPTION_ENABLED=true
        _prompt_block_device "Root LUKS partition" ROOT_PARTITION
        _propagate_rc $? || return $?
        _prompt_block_device "Home LUKS partition" HOME_PARTITION
        _propagate_rc $? || return $?
    else
        ENCRYPTION_ENABLED=false
        _warn "Non-encrypted reinstall: enter LVM logical volume paths directly."
    fi

    _prompt_block_device "Boot partition (ext4, not reformatted)" BOOT_PARTITION
    _propagate_rc $? || return $?

    _prompt_block_device "EFI partition (vfat, not reformatted)" EFI_PARTITION
    _propagate_rc $? || return $?

    _prompt_optional_block_device "Swap partition or LV" SWAP_DEVICE || return $?

    _prompt_lv_path "Root logical volume" ROOT_LV "$ROOT_LV"
    _propagate_rc $? || return $?

    _prompt_lv_path "Home logical volume" HOME_LV "$HOME_LV"
    _propagate_rc $? || return $?

    return 0
}

# ============================================================================
# Reinstall phases
# ============================================================================

_setup_reinstall_storage() {
    if [ "$ENCRYPTION_ENABLED" = true ]; then
        _check_crypt_tools
        _propagate_rc $? || return $?

        _load_crypt_modules
        _propagate_rc $? || return $?

        _open_luks_partition "$ROOT_PARTITION" luks_root
        _propagate_rc $? || return $?

        _open_luks_partition "$HOME_PARTITION" luks_home
        _propagate_rc $? || return $?

        _activate_volume_groups
        _propagate_rc $? || return $?
    fi

    if [ ! -b "$ROOT_LV" ] || [ ! -b "$HOME_LV" ]; then
        _error "Root or home logical volume not found. Check LUKS/LVM state."
        return 1
    fi

    _format_root_btrfs
    _propagate_rc $? || return $?

    _create_root_btrfs_subvolumes "$ROOT_LV"
    _propagate_rc $? "Failed to create root btrfs subvolumes" || return $?

    _mount_installation
    _propagate_rc $? "Failed to mount installation target" || return $?

    _print_mount_summary

    _verify_reinstall_backup
    _propagate_rc $? || return $?

    _info "Reinstall storage setup completed"
    return 0
}

_setup_reinstall_localization() {
    _setup_localization_reinstall
    _propagate_rc $? || return $?
    return 0
}

_setup_reinstall_users() {
    _setup_users_reinstall
    _propagate_rc $? || return $?
    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    _info "Arch Linux Reinstall Script (preserves /home)"

    if [ "$EUID" -ne 0 ]; then
        _error "This script must be run as root. Exiting."
        exit 1
    fi

    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        _warn "Internet connection not available. Some features may not work."
    fi

    _run_phase "Storage layout" _prompt_reinstall_layout
    _exit_on_rc $?

    _run_phase "Storage setup" _setup_reinstall_storage
    _exit_on_rc $?

    _run_phase "Bootstrap" _setup_bootstrap
    _exit_on_rc $?

    _run_phase "Boot setup" _setup_chroot_boot_reinstall
    _exit_on_rc $?

    _run_phase "Localization" _setup_reinstall_localization
    _exit_on_rc $?

    _run_phase "User setup" _setup_reinstall_users
    _exit_on_rc $?

    _run_phase "Desktop setup" _setup_desktop
    _exit_on_rc $?

    _finish_installation "Reinstallation"

    exit 0
}

main "$@"
