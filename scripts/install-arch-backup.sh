#!/usr/bin/env bash

# Back up system configs for Arch reinstall (run on installed system, not live ISO).
#
# Exit codes:
#   0 - success
#   1 - error

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/install.sh
source "${REPO_ROOT}/scripts/lib/install.sh"
init_logging "install-arch-backup"

main() {
    if [ "$EUID" -ne 0 ]; then
        _error "This script must be run as root. Use: sudo ./install arch --backup"
        exit 1
    fi

    _info "Arch reinstall config backup (live system)"

    _backup_reinstall_configs || exit 1

    _info "Backup completed. Log saved to: ${LOGFILE}"
    exit 0
}

main "$@"
