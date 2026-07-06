#!/usr/bin/env bash
# Print steps and open display for manual arch install (live ISO phase).
#
# Usage:
#   tests/manual/arch-install-vm-run.sh
#
# Exit codes:
#   0 - success
#   1 - error
#
# See instructions/tests/arch-install-full-vm.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/tests/manual/lib/common.sh"

VM_NAME=$(manual_arch_install_vm_name)
ANSWERS="${REPO_ROOT}/tests/manual/arch-vm-full.answers"

manual_need virsh

if ! virsh dominfo "$VM_NAME" &>/dev/null; then
    echo "arch-install-vm-run: VM ${VM_NAME} not found. Run arch-install-vm-create.sh create first." >&2
    exit 1
fi

if ! virsh domstate "$VM_NAME" 2>/dev/null | grep -q running; then
    echo "Starting ${VM_NAME}..."
    virsh start "$VM_NAME"
fi

spice_uri=$(manual_spice_uri "$VM_NAME")

cat <<EOF
=== Arch install (manual full VM) ===

1. SPICE window should open (or run: virt-viewer ${spice_uri})

2. On the live ISO, as root:
     git clone <this-repo> && cd linux-setup
     sudo ./install arch < ${ANSWERS}

3. Installer reboots when done (last answer: y).

4. Log in as testuser via SPICE.

Answers file:
EOF
cat "$ANSWERS"
echo "---"
manual_print_install_log_hint "$REPO_ROOT"

manual_open_viewer "$VM_NAME" || true
