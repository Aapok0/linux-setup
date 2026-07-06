#!/usr/bin/env bash
# SSH preflight checks before opening SPICE for manual GUI verification.
#
# Usage:
#   tests/manual/preflight.sh user@192.168.122.10
#   SETUP_VM_SSH_KEY=~/.ssh/id_ed25519 tests/manual/preflight.sh user@host
#
# Exit codes:
#   0 - success (preflight passed)
#   1 - error (preflight failed)
#   3 - invalid usage
#
# See instructions/tests/setup-full-vm.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/tests/manual/lib/common.sh"

usage() {
    sed -n '2,8p' "$0"
}

ssh_cmd() {
    local target=$1
    shift
    local -a opts
    mapfile -t opts < <(manual_ssh_opts)
    # shellcheck disable=SC2029
    ssh "${opts[@]}" "$target" "$@"
}

cmd_preflight() {
    local target=${1:-}
    [ -n "$target" ] || {
        if [ -n "${SETUP_VM_USER:-}" ] && [ -n "${SETUP_VM_HOST:-}" ]; then
            target=$(manual_ssh_target)
        else
            usage >&2
            exit 3
        fi
    }

    manual_need ssh
    local missing=0

    check() {
        local label=$1
        shift
        if "$@"; then
            printf '  ✓ %s\n' "$label"
        else
            printf '  ✗ %s\n' "$label"
            missing=1
        fi
    }

    echo "=== preflight: ${target} ==="

    check "ssh reachable" ssh_cmd "$target" true
    check "sddm active" ssh_cmd "$target" systemctl is-active --quiet sddm
    check "docker present" ssh_cmd "$target" command -v docker
    check "virsh present" ssh_cmd "$target" command -v virsh

    local log_status
    log_status=$(
        ssh_cmd "$target" bash -s <<'REMOTE' || true
set -euo pipefail
repo=~/linux-setup
if [ ! -d "${repo}/logs" ]; then
    echo "no_logs"
    exit 0
fi
latest=$(find "${repo}/logs" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null |
    sort -rn | head -1 | cut -d' ' -f2-)
if [ -z "$latest" ]; then
    echo "no_logs"
    exit 0
fi
if grep -q 'Setup finished with' "$latest" 2>/dev/null; then
    echo "errors:${latest}"
else
    echo "ok:${latest}"
fi
REMOTE
    )

    case "$log_status" in
        ok:*)
            printf '  ✓ setup log has no SETUP_ERRORS summary (%s)\n' "${log_status#ok:}"
            ;;
        errors:*)
            printf '  ✗ setup log reports errors: %s\n' "${log_status#errors:}"
            missing=1
            ;;
        no_logs)
            printf '  ✗ no setup logs in ~/linux-setup/logs\n'
            missing=1
            ;;
        *)
            printf '  ✗ could not read setup log status\n'
            missing=1
            ;;
    esac

    if [ "$missing" -eq 0 ]; then
        echo "PREFLIGHT OK — open SPICE and run the manual checklist"
        exit 0
    fi

    echo "PREFLIGHT FAIL — fix SSH issues before GUI verification"
    exit 1
}

main() {
    case ${1:-} in
        help | -h | --help) usage ;;
        "")
            usage >&2
            exit 3
            ;;
        *) cmd_preflight "$1" ;;
    esac
}

main "$@"
