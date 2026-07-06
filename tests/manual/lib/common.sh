#!/usr/bin/env bash
# Shared helpers for tests/manual/* (full GUI VM workflows).
#
# Source from a script under tests/manual/:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# Exit codes:
#   0 - success
#   1 - error
#   2 - user cancelled
#   3 - invalid usage (entry scripts)
#   4 - missing host prerequisite (required command not in PATH)

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

manual_repo_root() {
    cd "${_LIB_DIR}/../../.." && pwd
}

# Default under $HOME. Override with MANUAL_VM_DIR / MANUAL_GOLDEN_DIR (see instructions/tests/README.md).
MANUAL_VM_DIR=${MANUAL_VM_DIR:-"${HOME}/.local/share/linux-setup/manual-vm"}
MANUAL_GOLDEN_DIR=${MANUAL_GOLDEN_DIR:-"${HOME}/.local/share/linux-setup/golden"}
MANUAL_VM_MEMORY=${MANUAL_VM_MEMORY:-8192}
MANUAL_VM_VCPUS=${MANUAL_VM_VCPUS:-4}
MANUAL_SETUP_DISK_GB=${MANUAL_SETUP_DISK_GB:-48}

manual_need() {
    command -v "$1" &>/dev/null || {
        echo "manual: missing command: $1" >&2
        exit 4
    }
}

manual_confirm() {
    local prompt_msg=$1
    local response
    while true; do
        read -r -p "$prompt_msg" response
        case $response in
            [Yy] | [Yy][Ee][Ss]) return 0 ;;
            [Nn] | [Nn][Oo])
                echo "Cancelled." >&2
                exit 2
                ;;
            *) echo "Please enter y or n" >&2 ;;
        esac
    done
}

manual_setup_vm_name() {
    local distro=$1
    echo "linux-setup-manual-${distro}"
}

manual_arch_install_vm_name() {
    echo "linux-setup-arch-install-full"
}

manual_golden_path() {
    local distro=$1
    case "$distro" in
        debian) echo "${MANUAL_GOLDEN_DIR}/debian12-base.qcow2" ;;
        fedora) echo "${MANUAL_GOLDEN_DIR}/fedora42-base.qcow2" ;;
        arch) echo "${MANUAL_GOLDEN_DIR}/arch-base.qcow2" ;;
        *)
            echo "manual: unknown distro for golden: $distro" >&2
            return 1
            ;;
    esac
}

manual_os_variant() {
    local distro=$1
    case "$distro" in
        debian) echo "debian12" ;;
        fedora) echo "fedora42" ;;
        arch) echo "archlinux" ;;
        *)
            echo "manual: unknown distro: $distro" >&2
            return 1
            ;;
    esac
}

manual_iso_var() {
    local distro=$1
    case "$distro" in
        debian) echo "${DEBIAN_ISO:-}" ;;
        fedora) echo "${FEDORA_ISO:-}" ;;
        arch) echo "${ARCH_ISO:-}" ;;
    esac
}

manual_spice_uri() {
    local vm_name=$1
    manual_need virsh
    virsh domdisplay "$vm_name" 2>/dev/null || true
}

manual_open_viewer() {
    local vm_name=$1
    local uri
    uri=$(manual_spice_uri "$vm_name")
    if [ -z "$uri" ]; then
        echo "manual: no display URI for ${vm_name} (is the VM running?)" >&2
        return 1
    fi
    if command -v virt-viewer &>/dev/null; then
        echo "Opening virt-viewer ${uri}"
        virt-viewer --wait "$uri" &
    else
        echo "Open display: virt-viewer ${uri}"
        echo "Or use virt-manager → ${vm_name} → Open"
    fi
}

manual_print_setup_log_hint() {
    local repo=${1:-$(manual_repo_root)}
    echo "Setup logs: ${repo}/logs/ on guest (if repo synced there)"
    echo "  tail -f ${repo}/logs/*_setup.log"
}

manual_print_install_log_hint() {
    local repo=${1:-$(manual_repo_root)}
    echo "Install logs: ${repo}/logs/*_install-arch.log"
}

manual_ensure_dir() {
    mkdir -p "$MANUAL_VM_DIR" "$MANUAL_GOLDEN_DIR"
}

manual_ssh_target() {
    local user=${SETUP_VM_USER:?set SETUP_VM_USER}
    local host=${SETUP_VM_HOST:?set SETUP_VM_HOST}
    echo "${user}@${host}"
}

manual_ssh_opts() {
    local opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
    if [ -n "${SETUP_VM_SSH_KEY:-}" ]; then
        opts+=(-i "$SETUP_VM_SSH_KEY")
    fi
    printf '%s\n' "${opts[@]}"
}

manual_rsync_repo() {
    local target=$1
    local repo
    repo=$(manual_repo_root)
    manual_need rsync
    rsync -az --delete \
        --exclude '.git/' --exclude 'logs/' --exclude '.vagrant/' \
        -e "ssh $(manual_ssh_opts | tr '\n' ' ')" \
        "${repo}/" "${target}:linux-setup/"
}
