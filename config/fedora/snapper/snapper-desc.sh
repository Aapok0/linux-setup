#!/usr/bin/env bash
# Determines a human-readable description for a DNF5 transaction.
# Adapted from SysGuides sysguides-snapper-fedora (https://github.com/SysGuides/sysguides-snapper-fedora)
# by Madhu Desai / https://sysguides.com — used here with attribution.

PID="$1"

cmd=$(ps -o command --no-headers -p "$PID" 2>/dev/null || echo "Unknown Task")

case "$cmd" in
    */dnf5daemon* | */packagekitd*)
        echo "GUI"
        ;;
    *)
        echo "$cmd"
        ;;
esac
