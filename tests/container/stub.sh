#!/usr/bin/env bash
# Generic command stub for the container smoke tests: log the call and succeed.
# A few commands whose output the scripts parse get smart-cased so control flow
# behaves like a real (empty) system rather than erroring out.
name="$(basename "$0")"
echo "STUB $name $*" >>"${STUB_LOG:-/tmp/stub.log}"
case "$name" in
    lsb_release) # report a codename so the Debian repo paths proceed
        [ "${1:-}" = "-sc" ] && echo bookworm
        exit 0
        ;;
    findmnt) # report non-btrfs -> skip snapper paths
        echo ext4
        exit 0
        ;;
    systemctl) exit 1 ;; # is-active/is-enabled -> "not yet"
    dnf)                 # answer the dnf5-vs-dnf3 version probe
        [ "${1:-}" = "--version" ] && echo "dnf5 version 5.0.0"
        exit 0
        ;;
    *) exit 0 ;;
esac
