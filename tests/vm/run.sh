#!/usr/bin/env bash
# Host-side Vagrant test runner for setup-* headless smoke.
# Called by tests/run vm — do not invoke directly.
#
# Usage:
#   tests/run vm test [distro...]
#   tests/run vm snapshot-save [name] [distro...]
set -euo pipefail
cd "$(dirname "$0")/../.."

cmd=${1:-test}
shift || true
snap_name=clean
if [ "$cmd" = "snapshot-save" ] || [ "$cmd" = "snapshot-restore" ]; then
    snap_name=${1:-clean}
    shift || true
fi
distros=("$@")
[ ${#distros[@]} -gt 0 ] || distros=(debian fedora arch)

if ! command -v vagrant &>/dev/null; then
    echo "vm/run: vagrant not found" >&2
    exit 2
fi

_run_one() {
    local d=$1
    case "$cmd" in
        test)
            echo "==================== vm test: $d ===================="
            vagrant up "$d" --provision
            vagrant ssh "$d" -c 'bash /vagrant/tests/vm/assert.sh'
            ;;
        up)
            vagrant up "$d" "$@"
            ;;
        provision)
            vagrant provision "$d"
            ;;
        assert)
            vagrant ssh "$d" -c 'bash /vagrant/tests/vm/assert.sh'
            ;;
        snapshot-save)
            vagrant snapshot save "$d" "$snap_name"
            ;;
        snapshot-restore)
            vagrant snapshot restore "$d" "$snap_name"
            ;;
        destroy)
            vagrant destroy -f "$d"
            ;;
        status)
            vagrant status "$d"
            ;;
        *)
            echo "vm/run: unknown command '$cmd'" >&2
            echo "usage: tests/run vm [test|up|provision|assert|snapshot-save|snapshot-restore|destroy|status] [distro...]" >&2
            exit 2
            ;;
    esac
}

rc=0
for d in "${distros[@]}"; do
    _run_one "$d" || rc=1
done
exit "$rc"
