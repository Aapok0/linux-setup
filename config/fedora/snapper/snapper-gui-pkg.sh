#!/usr/bin/env bash
# Records the first package in a GUI-based DNF5 transaction for snapshot descriptions.
# Adapted from SysGuides sysguides-snapper-fedora (https://github.com/SysGuides/sysguides-snapper-fedora)
# by Madhu Desai / https://sysguides.com — used here with attribution.

PID="$1"
ACTION="$2"
NAME="$3"

STATE_DIR="/run/snapper-actions"
DESC_FILE="$STATE_DIR/snapper_desc_${PID}"
PKG_FILE="$STATE_DIR/snapper_gui_${PID}"

desc=$(cat "$DESC_FILE" 2>/dev/null || echo "")

[[ "$desc" != "GUI" ]] && exit 0
[[ -f "$PKG_FILE" ]] && exit 0

case "$ACTION" in
    I | U | D | R)
        echo "GUI install ${NAME}" >"$PKG_FILE"
        ;;
    E | O)
        echo "GUI remove ${NAME}" >"$PKG_FILE"
        ;;
esac
