#!/usr/bin/env bash
# Create a SPICE VM for full manual setup testing (GUI login after setup).
#
# Usage:
#   export DEBIAN_ISO=/path/to/debian.iso
#   tests/manual/setup-vm-create.sh debian
#
#   tests/manual/setup-vm-create.sh debian --from-golden
#   tests/manual/setup-vm-create.sh destroy debian
#
# Exit codes:
#   0 - success
#   1 - error
#   2 - user cancelled
#   3 - invalid usage
#
# See instructions/tests/setup-full-vm.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/tests/manual/lib/common.sh"

usage() {
    sed -n '2,12p' "$0"
}

cmd_create_from_iso() {
    local distro=$1
    manual_need virt-install
    manual_need virsh
    manual_ensure_dir

    local vm_name iso variant
    vm_name=$(manual_setup_vm_name "$distro")
    iso=$(manual_iso_var "$distro")
    variant=$(manual_os_variant "$distro")

    [ -n "$iso" ] && [ -f "$iso" ] || {
        local var
        var=$(echo "$distro" | tr '[:lower:]' '[:upper:]')_ISO
        echo "setup-vm-create: set ${var} to a valid ISO path" >&2
        exit 3
    }

    if virsh dominfo "$vm_name" &>/dev/null; then
        echo "setup-vm-create: domain ${vm_name} exists (destroy first)" >&2
        exit 1
    fi

    local disk="${MANUAL_VM_DIR}/${vm_name}.qcow2"
    [ -f "$disk" ] || qemu-img create -f qcow2 "$disk" "${MANUAL_SETUP_DISK_GB}G"

    virt-install \
        --name "$vm_name" \
        --memory "$MANUAL_VM_MEMORY" \
        --vcpus "$MANUAL_VM_VCPUS" \
        --cpu host-passthrough \
        --disk "path=${disk},format=qcow2,bus=virtio" \
        --cdrom "$iso" \
        --os-variant "$variant" \
        --network network=default \
        --graphics spice,listen=127.0.0.1 \
        --video virtio \
        --boot uefi,hd,cdrom \
        --noautoconsole

    cat <<EOF

VM '${vm_name}' created from ISO (SPICE).
  disk: ${disk}

Install base OS via SPICE (see instructions/tests/setup-full-vm.md).
Enable SSH, then:

  export SETUP_VM_HOST=<guest-ip>
  export SETUP_VM_USER=<your-user>
  tests/manual/setup-vm-run.sh ${distro}

EOF
    manual_open_viewer "$vm_name" || true
}

cmd_create_from_golden() {
    local distro=$1
    manual_need virt-install
    manual_need virsh
    manual_ensure_dir

    local vm_name golden disk
    vm_name=$(manual_setup_vm_name "$distro")
    golden=$(manual_golden_path "$distro")
    disk="${MANUAL_VM_DIR}/${vm_name}.qcow2"

    [ -f "$golden" ] || {
        echo "setup-vm-create: golden image not found: ${golden}" >&2
        echo "Create it after Path A (see instructions/tests/setup-full-vm.md)" >&2
        exit 3
    }

    if virsh dominfo "$vm_name" &>/dev/null; then
        echo "setup-vm-create: domain ${vm_name} exists (destroy first)" >&2
        exit 1
    fi

    cp -f "$golden" "$disk"

    virt-install \
        --name "$vm_name" \
        --memory "$MANUAL_VM_MEMORY" \
        --vcpus "$MANUAL_VM_VCPUS" \
        --cpu host-passthrough \
        --disk "path=${disk},format=qcow2,bus=virtio" \
        --os-variant "$(manual_os_variant "$distro")" \
        --network network=default \
        --graphics spice,listen=127.0.0.1 \
        --video virtio \
        --boot uefi \
        --import \
        --noautoconsole

    cat <<EOF

VM '${vm_name}' created from golden image.
  disk: ${disk}

Boot and SSH, then:

  export SETUP_VM_HOST=<guest-ip>
  export SETUP_VM_USER=<your-user>
  tests/manual/setup-vm-run.sh ${distro}

EOF
    manual_open_viewer "$vm_name" || true
}

cmd_destroy() {
    local distro=$1
    manual_need virsh
    local vm_name disk
    vm_name=$(manual_setup_vm_name "$distro")
    disk="${MANUAL_VM_DIR}/${vm_name}.qcow2"

    manual_confirm "Destroy ${vm_name} and delete ${disk}? (y/n): "

    virsh destroy "$vm_name" 2>/dev/null || true
    virsh undefine "$vm_name" --remove-all-storage 2>/dev/null || virsh undefine "$vm_name" 2>/dev/null || true
    rm -f "$disk"
    echo "setup-vm-create: removed ${vm_name}"
}

main() {
    local cmd=${1:-help}
    case "$cmd" in
        destroy)
            [ -n "${2:-}" ] || {
                echo "usage: $0 destroy <debian|fedora|arch>" >&2
                exit 3
            }
            cmd_destroy "$2"
            ;;
        debian | fedora | arch)
            if [ "${2:-}" = "--from-golden" ]; then
                cmd_create_from_golden "$cmd"
            else
                cmd_create_from_iso "$cmd"
            fi
            ;;
        help | -h | --help)
            usage
            ;;
        *)
            echo "usage: $0 <debian|fedora|arch> [--from-golden]" >&2
            echo "       $0 destroy <debian|fedora|arch>" >&2
            exit 3
            ;;
    esac
}

main "$@"
