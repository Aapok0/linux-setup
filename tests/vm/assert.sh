#!/usr/bin/env bash
# Post-provision assertions inside a Vagrant VM.
# Usage (in VM):  bash /vagrant/tests/vm/assert.sh
set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
missing=0

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

echo "=== vm-assert ==="

check "dotfiles cloned" test -d "$HOME/Workspace/dotfiles"
check "git available" command -v git
check "zsh available" command -v zsh
check "docker available" command -v docker
check "virsh available" command -v virsh
check "shellcheck available" command -v shellcheck
check "ruff available" command -v ruff

latest=""
if [ -d /vagrant/logs ]; then
    latest=$(find /vagrant/logs -maxdepth 1 -name 'vm-*' -type f -printf '%T@ %p\n' 2>/dev/null |
        sort -rn | head -1 | cut -d' ' -f2-)
fi
if [ -n "$latest" ]; then
    if grep -q 'Setup finished with' "$latest" 2>/dev/null; then
        printf '  ✗ setup log reports errors: %s\n' "$latest"
        missing=1
    else
        printf '  ✓ setup log has no SETUP_ERRORS summary (%s)\n' "$latest"
    fi
fi

if [ "$missing" -eq 0 ]; then
    echo "VM ASSERT OK"
    exit 0
fi

echo "VM ASSERT FAIL"
exit 1
