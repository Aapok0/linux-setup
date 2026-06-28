#!/usr/bin/env bash
# Run the container-based tests for the setup-* scripts locally.
#
# Usage:
#   tests/run.sh [tier] [distro...]
#     tier    source | smoke           (default: smoke)
#     distro  arch | debian | fedora   (default: all three)
#
# Container runtime is taken from $RUNTIME (default: docker). It may contain
# arguments, e.g. RUNTIME="sudo docker" tests/run.sh  or  RUNTIME=podman ...
set -euo pipefail
cd "$(dirname "$0")/.."

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
    echo "==================== $d ($img) ===================="
    # ':z' relabels the bind mount for SELinux hosts; harmless elsewhere.
    "${runtime[@]}" run --rm -v "$PWD:/repo:ro,z" "$img" \
        bash /repo/tests/smoke.sh "$d" "$tier" || rc=1
done

exit "$rc"
