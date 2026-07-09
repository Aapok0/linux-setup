#!/usr/bin/env bash
# Local libvirt VM harness for install-arch (boot validation).
# NOT for CI — needs nested virt, an Arch ISO, and a long unattended window.
#
# Usage:
#   tests/run install vm create
#   tests/run install vm start
#   tests/run install vm console
#   tests/run install vm answers
#   tests/run install vm destroy
#
# After booting the Arch ISO, on the live environment:
#   git clone <this-repo> && cd linux-setup
#   sudo LINUX_SETUP_LOGGING=1 ./install arch < tests/install/arch-vm.answers
#
# Environment:
#   ARCH_ISO   path to archlinux*.iso (required for create)
#   VM_NAME    default: linux-setup-arch-install
#   VM_DIR     default: $HOME/.local/share/linux-setup/vm
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VM_NAME=${VM_NAME:-linux-setup-arch-install}
VM_DIR=${VM_DIR:-"$HOME/.local/share/linux-setup/vm"}
DISK_ROOT="${VM_DIR}/${VM_NAME}-root.qcow2"
DISK_HOME="${VM_DIR}/${VM_NAME}-home.qcow2"
ARCH_ISO=${ARCH_ISO:-}

_need() {
    command -v "$1" &>/dev/null || {
        echo "arch-vm: missing command: $1" >&2
        exit 2
    }
}

cmd_create() {
    _need virt-install
    _need virsh
    [ -n "$ARCH_ISO" ] && [ -f "$ARCH_ISO" ] || {
        echo "arch-vm: set ARCH_ISO to a valid archlinux ISO path" >&2
        exit 2
    }
    mkdir -p "$VM_DIR"
    [ -f "$DISK_ROOT" ] || qemu-img create -f qcow2 "$DISK_ROOT" 32G
    [ -f "$DISK_HOME" ] || qemu-img create -f qcow2 "$DISK_HOME" 16G

    if virsh dominfo "$VM_NAME" &>/dev/null; then
        echo "arch-vm: domain $VM_NAME already exists (use destroy first)" >&2
        exit 1
    fi

    virt-install \
        --name "$VM_NAME" \
        --memory 4096 \
        --vcpus 2 \
        --cpu host-passthrough \
        --disk "path=${DISK_ROOT},format=qcow2,bus=virtio" \
        --disk "path=${DISK_HOME},format=qcow2,bus=virtio" \
        --cdrom "$ARCH_ISO" \
        --os-variant archlinux \
        --network network=default \
        --graphics none \
        --console pty,target_type=serial \
        --boot uefi,hd,cdrom \
        --noautoconsole

    cat <<EOF

VM '${VM_NAME}' created.
  root disk: ${DISK_ROOT}  -> /dev/vda in guest
  home disk: ${DISK_HOME}  -> /dev/vdb in guest

Next:
  tests/run install vm console
  # on live ISO: clone repo, then:
  sudo LINUX_SETUP_LOGGING=1 ./install arch < ${REPO_ROOT}/tests/install/arch-vm.answers

EOF
}

cmd_start() {
    _need virsh
    virsh start "$VM_NAME"
}

cmd_console() {
    _need virsh
    echo "Attach with Ctrl+] to detach. Login as root on the live ISO."
    virsh console "$VM_NAME"
}

cmd_answers() {
    cat "${REPO_ROOT}/tests/install/arch-vm.answers"
    echo "--- (saved at tests/install/arch-vm.answers) ---"
}

cmd_destroy() {
    _need virsh
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || virsh undefine "$VM_NAME" 2>/dev/null || true
    rm -f "$DISK_ROOT" "$DISK_HOME"
    echo "arch-vm: removed ${VM_NAME}"
}

main() {
    local sub=${1:-help}
    case "$sub" in
        create) cmd_create ;;
        start) cmd_start ;;
        console) cmd_console ;;
        answers) cmd_answers ;;
        destroy) cmd_destroy ;;
        help | -h | --help)
            sed -n '2,20p' "$0"
            ;;
        *)
            echo "arch-vm: unknown subcommand '$sub' (try: create|start|console|answers|destroy)" >&2
            exit 2
            ;;
    esac
}

main "$@"
