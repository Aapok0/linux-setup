#!/usr/bin/env bash
# Loopback "disk" smoke test for scripts/install-arch.
#
# Runs the REAL installer against loop-backed image files, so partitioning,
# LVM, btrfs subvolumes and mounting are exercised for real — everything short
# of an actual boot (which still needs a VM). Only the chroot/Arch/network
# commands that can't run on a generic host are stubbed (arch-chroot, pacstrap,
# genfstab, reflector, reboot, ping); every disk operation is genuine.
#
# MUST run as root (loop devices, LVM, mount):  sudo tests/install-smoke.sh
#
# Usage:
#   sudo tests/install-smoke.sh [scenario...]
#     scenario  partition | lvm | sized | samedevice   (default: all)
#                 partition  = swap partition, root=all, separate /home
#                 lvm        = swap as an LVM logical volume, root=all
#                 sized      = swap partition + an explicit root size, which
#                              exercises the swap-offset partition arithmetic in
#                              _setup_disk_partitions
#                 samedevice = root + home on one device, both sized, which
#                              exercises the home-on-same-device branch (absolute
#                              parted end computation)
#
# Not covered here (VM/manual): LUKS encryption (interactive passphrase) and
# verifying the result actually boots (GRUB/initramfs/EFI).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "install-smoke: must run as root (loop devices/LVM/mount). Use: sudo $0" >&2
    exit 2
fi

# Unique names so cleanup never touches a real system's VGs.
VG_ROOT="archsmoke"
VG_HOME="archsmoke_home"

# Per-scenario state (set in run_scenario, read by cleanup_scenario).
WORK=""
LOOP_ROOT=""
LOOP_HOME=""
MNT=""

# Defect-class bash runtime errors (benign stub artifacts excluded on purpose).
FATAL_RE='unbound variable|bad substitution|syntax error|ambiguous redirect|division by 0|bad array subscript|integer expression expected|parameter null or not set'

_have() { command -v "$1" &>/dev/null; }

cleanup_scenario() {
    # Best-effort teardown; every step tolerates "already gone". Only disable
    # swap that belongs to THIS run (our loop devices or our VGs) so we never
    # touch the host's swap. Empty LOOP_* guards avoid a bare "*" glob match.
    local s mp lv part vg saved_work=$WORK saved_mnt=$MNT
    saved_work=$WORK
    saved_mnt=$MNT

    # Swap may appear as /dev/mapper/vg-lv or /dev/dm-N; target our VGs by name.
    for vg in "$VG_ROOT" "$VG_HOME"; do
        vgs "$vg" &>/dev/null || continue
        while read -r lv; do
            [ -z "$lv" ] && continue
            swapoff "/dev/mapper/${vg}-${lv}" 2>/dev/null || true
            swapoff "/dev/${vg}/${lv}" 2>/dev/null || true
        done < <(lvs --noheadings -o lv_name "$vg" 2>/dev/null)
    done
    for s in $(swapon --show=NAME --noheadings 2>/dev/null); do
        if { [ -n "$LOOP_ROOT" ] && [[ "$s" == "$LOOP_ROOT"* ]]; } ||
            { [ -n "$LOOP_HOME" ] && [[ "$s" == "$LOOP_HOME"* ]]; } ||
            [[ "$s" == "/dev/mapper/${VG_ROOT}-"* ]] ||
            [[ "$s" == "/dev/mapper/${VG_HOME}-"* ]]; then
            swapoff "$s" 2>/dev/null || true
        fi
    done

    # Installer leaves the full mount tree up when reboot is declined; unmount
    # deepest targets first (many btrfs subvol mounts under $MNT).
    if [ -n "$saved_mnt" ]; then
        while IFS= read -r mp; do
            [ -n "$mp" ] && umount -l "$mp" 2>/dev/null || true
        done < <(findmnt -Rno TARGET "$saved_mnt" 2>/dev/null | awk '{print length, $0}' | sort -rn | cut -d' ' -f2-)
    fi

    for vg in "$VG_ROOT" "$VG_HOME"; do
        if vgs "$vg" &>/dev/null; then
            lvchange -an "$vg" 2>/dev/null || true
            vgchange -an "$vg" 2>/dev/null || true
            vgremove -ff "$vg" 2>/dev/null || true
        elif [ -e "/dev/$vg" ]; then
            dmsetup remove "$vg" 2>/dev/null || true
        fi
    done

    for s in "$LOOP_ROOT" "$LOOP_HOME"; do
        [ -z "$s" ] && continue
        for part in "${s}"p*; do
            [ -e "$part" ] || continue
            pvremove -ff "$part" 2>/dev/null || true
            wipefs -a "$part" 2>/dev/null || true
        done
        losetup -d "$s" 2>/dev/null || true
    done

    [ -n "$saved_work" ] && rm -rf "$saved_work" 2>/dev/null || true
    WORK=""
    MNT=""
    LOOP_ROOT=""
    LOOP_HOME=""
}

trap cleanup_scenario EXIT

check_host_tools() {
    local cmd missing=()
    for cmd in losetup parted partprobe lsblk findmnt pvcreate vgcreate lvcreate \
        mkfs.btrfs mkfs.fat mkfs.ext4 mkswap btrfs truncate wipefs; do
        _have "$cmd" || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "install-smoke: missing host tools: ${missing[*]}" >&2
        echo "  install: parted lvm2 btrfs-progs dosfstools e2fsprogs util-linux" >&2
        exit 2
    fi
}

make_stubs() {
    # Commands that can't run on a generic host: no-op them (success). pacstrap
    # also seeds a minimal /etc skeleton so later writes to $MNT/etc succeed.
    local dir=$1
    mkdir -p "$dir"

    local c
    for c in arch-chroot genfstab reflector reboot ping; do
        printf '#!/usr/bin/env bash\nexit 0\n' >"$dir/$c"
        chmod +x "$dir/$c"
    done

    cat >"$dir/pacstrap" <<'EOF'
#!/usr/bin/env bash
target=${1:-/mnt}
mkdir -p "$target"/etc/default "$target"/etc/systemd \
    "$target"/etc/xdg/reflector "$target"/etc/sudoers.d \
    "$target"/etc/pacman.d "$target"/boot 2>/dev/null || true
exit 0
EOF
    chmod +x "$dir/pacstrap"
}

# scenario: "partition", "lvm", "sized" or "samedevice"
run_scenario() {
    local scenario=$1
    local swap_choice root_size home_target home_size
    case "$scenario" in
        partition)
            swap_choice=1
            root_size=all
            home_target=home
            home_size=all
            ;;
        lvm)
            swap_choice=2
            root_size=all
            home_target=home
            home_size=all
            ;;
        sized)
            swap_choice=1
            root_size=8G
            home_target=home
            home_size=all
            ;;
        samedevice)
            # root and home share one device, both sized -> exercises the
            # home-on-same-device branch (absolute parted end computation).
            swap_choice=1
            root_size=8G
            home_target=root
            home_size=6G
            ;;
        *)
            echo "install-smoke: unknown scenario '$scenario' (use partition|lvm|sized|samedevice)" >&2
            return 2
            ;;
    esac

    echo "########## install-arch smoke: scenario=$scenario ##########"

    WORK="$(mktemp -d /tmp/archsmoke.XXXXXX)"
    MNT="$WORK/mnt"
    mkdir -p "$MNT"

    # Sparse images: root 32G (boot 5G + swap + sized/remaining root), home 16G.
    truncate -s 32G "$WORK/root.img"
    truncate -s 16G "$WORK/home.img"
    LOOP_ROOT="$(losetup --find --show -P "$WORK/root.img")"
    LOOP_HOME="$(losetup --find --show -P "$WORK/home.img")"
    echo "--- loop devices: root=$LOOP_ROOT home=$LOOP_HOME ---"

    local home_dev="$LOOP_HOME"
    [ "$home_target" = root ] && home_dev="$LOOP_ROOT"

    make_stubs "$WORK/stubs"

    # Answer stream consumed by the installer's prompts, in order. The home
    # device only gets a separate format confirmation when it differs from root.
    {
        printf '%s\n' "$LOOP_ROOT"                           # root device
        printf '%s\n' "$home_dev"                            # home device
        printf '%s\n' "$swap_choice"                         # swap type (1=partition, 2=lvm)
        printf '%s\n' n                                      # hibernation
        printf '%s\n' "$root_size"                           # root size
        printf '%s\n' "$home_size"                           # home size
        printf '%s\n' yes                                    # confirm configuration
        printf '%s\n' yes                                    # format root device
        [ "$home_dev" != "$LOOP_ROOT" ] && printf '%s\n' yes # format home device
        printf '%s\n' n                                      # encrypt? no
        printf '%s\n' testuser                               # install username
        printf '%s\n' y                                      # create filesystems
        printf '%s\n' archtest                               # hostname
        printf '%s\n' ''                                     # timezone (default)
        printf '%s\n' 3                                      # cpu microcode: skip
        printf '%s\n' 5                                      # gpu drivers: skip
        printf '%s\n' n                                      # unmount/reboot? no
    } >"$WORK/answers"

    local rc=0
    LINUX_SETUP_LOGGING=1 \
        LOGFILE="$WORK/install.log" \
        MNT="$MNT" \
        VG_ROOT="$VG_ROOT" \
        VG_HOME="$VG_HOME" \
        PATH="$WORK/stubs:$PATH" \
        timeout 600 bash scripts/install-arch <"$WORK/answers" >"$WORK/out" 2>&1 || rc=$?

    echo "=== last 20 log lines ==="
    tail -20 "$WORK/out"

    local fatal completed=no
    fatal="$(grep -nE "$FATAL_RE" "$WORK/out" || true)"
    if [ "$rc" -eq 0 ] || grep -q 'Installation Complete' "$WORK/out"; then
        completed=yes
    fi

    if [ -n "$fatal" ]; then
        echo "INSTALL-SMOKE FAIL (scenario=$scenario): bash runtime error(s):"
        echo "$fatal"
        cleanup_scenario
        return 1
    fi
    if [ "$completed" != yes ]; then
        echo "INSTALL-SMOKE FAIL (scenario=$scenario): installer did not complete (rc=$rc; timeout or early exit)"
        cleanup_scenario
        return 1
    fi

    echo "INSTALL-SMOKE OK (scenario=$scenario): real partition/LVM/btrfs/mount completed (rc=$rc)"
    cleanup_scenario
    return 0
}

main() {
    check_host_tools

    local scenarios=("$@")
    [ ${#scenarios[@]} -gt 0 ] || scenarios=(partition lvm sized samedevice)

    local rc=0 s
    for s in "${scenarios[@]}"; do
        run_scenario "$s" || rc=1
    done

    if [ "$rc" -eq 0 ]; then
        echo "ALL INSTALL-SMOKE SCENARIOS PASSED"
    fi
    return "$rc"
}

main "$@"
