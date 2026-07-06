#!/usr/bin/env bash
# Create a SPICE VM for full manual arch install (GUI login after reboot).
#
# Usage:
#   export ARCH_ISO=/path/to/archlinux.iso
#   tests/manual/arch-install-vm-create.sh create
#   tests/manual/arch-install-vm-create.sh destroy
#
# Exit codes:
#   0 - success
#   1 - error
#   2 - user cancelled
#   3 - invalid usage
#
# See instructions/tests/arch-install-full-vm.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/tests/manual/lib/common.sh"

VM_NAME=$(manual_arch_install_vm_name)
DISK_ROOT="${MANUAL_VM_DIR}/${VM_NAME}-root.qcow2"
DISK_HOME="${MANUAL_VM_DIR}/${VM_NAME}-home.qcow2"

cmd_create() {
    manual_need virt-install
    manual_need virsh
    manual_ensure_dir

    local iso
    iso=$(manual_iso_var arch)
    [ -n "$iso" ] && [ -f "$iso" ] || {
        echo "arch-install-vm-create: set ARCH_ISO to a valid archlinux ISO" >&2
        exit 3
    }

    if virsh dominfo "$VM_NAME" &>/dev/null; then
        echo "arch-install-vm-create: domain ${VM_NAME} exists (destroy first)" >&2
        exit 1
    fi

    [ -f "$DISK_ROOT" ] || qemu-img create -f qcow2 "$DISK_ROOT" 32G
    [ -f "$DISK_HOME" ] || qemu-img create -f qcow2 "$DISK_HOME" 16G

    virt-install \
        --name "$VM_NAME" \
        --memory "$MANUAL_VM_MEMORY" \
        --vcpus "$MANUAL_VM_VCPUS" \
        --cpu host-passthrough \
        --disk "path=${DISK_ROOT},format=qcow2,bus=virtio" \
        --disk "path=${DISK_HOME},format=qcow2,bus=virtio" \
        --cdrom "$iso" \
        --os-variant archlinux \
        --network network=default \
        --graphics spice,listen=127.0.0.1 \
        --video virtio \
        --boot uefi,hd,cdrom \
        --noautoconsole

    cat <<EOF

VM '${VM_NAME}' created (SPICE, ${MANUAL_VM_MEMORY} MiB RAM).
  root: ${DISK_ROOT}  -> /dev/vda
  home: ${DISK_HOME}  -> /dev/vdb

Next:
  tests/manual/arch-install-vm-run.sh

EOF
    manual_open_viewer "$VM_NAME" || true
}

cmd_destroy() {
    manual_need virsh
    manual_confirm "Destroy ${VM_NAME} and delete disks under ${MANUAL_VM_DIR}? (y/n): "
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || virsh undefine "$VM_NAME" 2>/dev/null || true
    rm -f "$DISK_ROOT" "$DISK_HOME"
    echo "arch-install-vm-create: removed ${VM_NAME}"
}

main() {
    case ${1:-help} in
        create) cmd_create ;;
        destroy) cmd_destroy ;;
        help | -h | --help)
            sed -n '2,12p' "$0"
            ;;
        *)
            echo "usage: $0 create|destroy" >&2
            exit 3
            ;;
    esac
}

main "$@"
