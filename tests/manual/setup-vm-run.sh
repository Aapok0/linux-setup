#!/usr/bin/env bash
# Run full setup (HEADLESS=0) on a manual test VM over SSH, then reboot for GUI login.
#
# Usage:
#   export SETUP_VM_HOST=192.168.122.10
#   export SETUP_VM_USER=youruser
#   export SETUP_VM_SSH_KEY=~/.ssh/id_ed25519   # optional
#   tests/manual/setup-vm-run.sh debian
#
# Exit codes:
#   0 - success
#   1 - error
#   3 - invalid usage
#
# See instructions/tests/setup-full-vm.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/tests/manual/lib/common.sh"

usage() {
    sed -n '2,11p' "$0"
}

ssh_cmd() {
    local target
    target=$(manual_ssh_target)
    local -a opts
    mapfile -t opts < <(manual_ssh_opts)
    # shellcheck disable=SC2029
    ssh "${opts[@]}" "$target" "$@"
}

cmd_run() {
    local distro=$1
    manual_need ssh
    manual_need rsync

    : "${SETUP_VM_HOST:?set SETUP_VM_HOST to guest IP (virsh net-dhcp-leases default)}"
    : "${SETUP_VM_USER:?set SETUP_VM_USER to guest login user}"

    local vm_name target repo
    vm_name=$(manual_setup_vm_name "$distro")
    target=$(manual_ssh_target)
    repo=$(manual_repo_root)

    echo "=== setup-vm-run: syncing repo to ${target}:linux-setup/ ==="
    manual_rsync_repo "$target"

    echo "=== setup-vm-run: full setup (HEADLESS=0) on ${target} ==="
    ssh_cmd bash -s "$distro" <<'REMOTE'
set -euo pipefail
distro=$1
repo=~/linux-setup
export LINUX_SETUP_NONINTERACTIVE=1
export LINUX_SETUP_HEADLESS=0
export LINUX_SETUP_LOGGING=1

mkdir -p "${repo}/logs"
mkdir -p "$HOME/.config/git"
if [ ! -f "$HOME/.config/git/config.local" ]; then
    cat >"$HOME/.config/git/config.local" <<'EOF'
[user]
    name = Manual VM Test
    email = manual-vm@example.com
EOF
fi

cd "$repo"
./setup

sudo systemctl set-default graphical.target 2>/dev/null || true
sudo systemctl enable sddm 2>/dev/null || true
REMOTE

    echo "=== setup-vm-run: rebooting guest ==="
    ssh_cmd sudo reboot || true
    sleep 5

    cat <<EOF

Setup finished. Open SPICE and log in:

  virsh domdisplay ${vm_name}
  virt-viewer \$(virsh domdisplay ${vm_name})

Optional SSH preflight (after guest is back):

  tests/manual/preflight.sh ${target}

EOF
    manual_print_setup_log_hint "$repo"
    manual_open_viewer "$vm_name" || true
}

main() {
    case ${1:-help} in
        debian | fedora | arch) cmd_run "$1" ;;
        help | -h | --help) usage ;;
        *)
            echo "usage: $0 <debian|fedora|arch>" >&2
            exit 3
            ;;
    esac
}

main "$@"
