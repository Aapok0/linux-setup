#!/usr/bin/env bash
# Host-side Docker/Podman runner for container smoke tests.
# Called by tests/run — do not invoke directly.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

read -r -a runtime <<<"${RUNTIME:-docker}"
tier=${1:-smoke}
shift || true
distros=("$@")
[ ${#distros[@]} -gt 0 ] || distros=(debian fedora arch)

declare -A IMG=(
    [debian]=debian:stable
    [fedora]=fedora:latest
    [arch]=archlinux:latest
)

rc=0
for d in "${distros[@]}"; do
    img=${IMG[$d]:?unknown distro: $d (use arch|debian|fedora)}
    echo "==================== $d ($img) / $tier ===================="
    "${runtime[@]}" run --rm -v "$PWD:/repo:ro,z" "$img" \
        bash /repo/tests/container/smoke.sh "$d" "$tier" || rc=1
done

exit "$rc"
