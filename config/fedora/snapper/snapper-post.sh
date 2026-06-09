#!/usr/bin/env bash
# Creates a POST snapshot after a DNF5 transaction completes.
# Adapted from SysGuides sysguides-snapper-fedora (https://github.com/SysGuides/sysguides-snapper-fedora)
# by Madhu Desai / https://sysguides.com — used here with attribution.

PID="$1"
STATE_DIR="/run/snapper-actions"

DESC_FILE="$STATE_DIR/snapper_desc_${PID}"
PRE_FILE="$STATE_DIR/snapper_pre_${PID}"
GUI_FILE="$STATE_DIR/snapper_gui_${PID}"

desc=$(cat "$DESC_FILE" 2>/dev/null || echo "")
pre=$(cat "$PRE_FILE" 2>/dev/null || echo "")
gui_pkg=$(cat "$GUI_FILE" 2>/dev/null || echo "")

[[ -z "$pre" ]] && exit 0

if [[ -n "$gui_pkg" ]]; then
    desc="$gui_pkg"
    snapper -c root modify -d "$desc" "$pre" || true
fi

/usr/local/bin/snapper-wal-checkpoint.sh || true

snapper -c root create -c number -t post \
    --pre-number "$pre" -d "$desc"

rm -f "$DESC_FILE" "$PRE_FILE" "$GUI_FILE"
