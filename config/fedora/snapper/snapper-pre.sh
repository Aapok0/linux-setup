#!/usr/bin/env bash
set -e
# Creates a PRE snapshot before a DNF5 transaction.
# Adapted from SysGuides sysguides-snapper-fedora (https://github.com/SysGuides/sysguides-snapper-fedora)
# by Madhu Desai / https://sysguides.com — used here with attribution.

PID="$1"
STATE_DIR="/run/snapper-actions"

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

if [[ ! -d /usr/lib/sysimage/libdnf5 ]]; then
    mkdir -p /usr/lib/sysimage/libdnf5
    restorecon -q /usr/lib/sysimage/libdnf5 2>/dev/null || true
fi

desc=$(/usr/local/bin/snapper-desc.sh "$PID")
echo "$desc" >"$STATE_DIR/snapper_desc_${PID}"

pre=$(snapper -c root create -c number -t pre -p -d "$desc") || exit 1
echo "$pre" >"$STATE_DIR/snapper_pre_${PID}"
