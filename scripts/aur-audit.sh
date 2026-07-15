#!/usr/bin/env bash
# Compare installed AUR packages to the expected footprint in vars/arch-vars.
# Writes a changelog with PKGBUILDs for expected packages (paru -Gp).
#
# Usage:
#   ./scripts/aur-audit.sh                    # full desktop profile; summary on stdout
#   ./scripts/aur-audit.sh -q                 # changelog path only
#   ./scripts/aur-audit.sh --no-pkgbuilds     # skip PKGBUILD fetch
#   ./scripts/aur-audit.sh --headless         # match LINUX_SETUP_HEADLESS=1 setup profile
#
# Exit codes:
#   0 - success
#   1 - error (wrong distro, no AUR query tool, PKGBUILD fetch failure, write failure)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUIET=false
INCLUDE_PKGBUILDS=true
HEADLESS=false

usage() {
    cat <<'EOF'
Usage: aur-audit.sh [-q] [--no-pkgbuilds] [--headless]

  -q               quiet: print only the absolute changelog file path
  --no-pkgbuilds   skip PKGBUILD fetch (package lists only)
  --headless       expect headless setup footprint (also set via LINUX_SETUP_HEADLESS=1)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -q) QUIET=true ;;
        --no-pkgbuilds) INCLUDE_PKGBUILDS=false ;;
        --headless) HEADLESS=true ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "aur-audit: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

[ "${LINUX_SETUP_HEADLESS:-}" = "1" ] && HEADLESS=true

_ensure_arch() {
    local id id_like
    [ -f /etc/os-release ] || {
        echo "aur-audit: /etc/os-release not found" >&2
        exit 1
    }
    # shellcheck source=/dev/null
    source /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
    [[ "$id" =~ arch ]] || [[ "$id_like" =~ arch ]] || {
        echo "aur-audit: Arch Linux required (ID=${id:-unknown})" >&2
        exit 1
    }
}

_is_btrfs_root() {
    findmnt -n -o FSTYPE / 2>/dev/null | grep -qx btrfs
}

_should_include_aur_array() {
    local arr_name=$1
    if $HEADLESS; then
        case "$arr_name" in
            apps_aur | gaming_packages_aur) return 1 ;;
        esac
    fi
    return 0
}

_collect_expected_aur() {
    local -n _out=$1
    local arr_name pkg single

    _out=()
    # shellcheck disable=SC2154 # aur_package_arrays from arch-vars
    for arr_name in "${aur_package_arrays[@]}"; do
        _should_include_aur_array "$arr_name" || continue
        local -n arr_ref="$arr_name"
        for pkg in "${arr_ref[@]}"; do
            [ -z "$pkg" ] && continue
            [[ "$pkg" == \#* ]] && continue
            # Word-split: arch-vars entries may list multiple packages in one string.
            for single in $pkg; do
                _out+=("$single")
            done
        done
    done
    # shellcheck disable=SC2154 # aur_setup_packages from arch-vars
    for pkg in "${aur_setup_packages[@]}"; do
        [ -z "$pkg" ] && continue
        _out+=("$pkg")
    done
    if ! $HEADLESS && _is_btrfs_root; then
        _out+=("snapper-rollback")
    fi
}

_list_installed_aur() {
    if command -v paru &>/dev/null; then
        paru -Qm | awk '{print $1}'
        return 0
    fi
    if pacman -Qm &>/dev/null; then
        pacman -Qm | awk '{print $1}'
        return 0
    fi
    echo "aur-audit: paru or pacman -Qm required" >&2
    exit 1
}

_in_array() {
    local needle=$1
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

_sort_unique() {
    if [ $# -eq 0 ]; then
        return 0
    fi
    printf '%s\n' "$@" | LC_ALL=C sort -u
}

_intersection() {
    local -n _left=$1
    local -n _right=$2
    local item
    local -a result=()
    for item in "${_left[@]}"; do
        _in_array "$item" "${_right[@]}" && result+=("$item")
    done
    _sort_unique "${result[@]}"
}

_difference() {
    local -n _left=$1
    local -n _right=$2
    local item
    local -a result=()
    for item in "${_left[@]}"; do
        _in_array "$item" "${_right[@]}" || result+=("$item")
    done
    _sort_unique "${result[@]}"
}

_write_section() {
    local title=$1
    shift
    local -a items=("$@")
    local count=${#items[@]}

    {
        printf '== %s (%d) ==\n' "$title" "$count"
        if [ "$count" -eq 0 ]; then
            echo "(none)"
        else
            local i
            for i in "${!items[@]}"; do
                printf '%s' "${items[$i]}"
                [ "$i" -lt $((count - 1)) ] && printf ', '
            done
            echo
        fi
        echo
    } >>"$OUTFILE"
}

_write_pkgbuilds() {
    local -n _packages=$1
    local pkg
    local -i failed=0

    {
        echo "== PKGBUILDs (${#_packages[@]}, paru -Gp) =="
        echo
    } >>"$OUTFILE"

    for pkg in "${_packages[@]}"; do
        {
            printf '== PKGBUILD: %s ==\n' "$pkg"
            if paru -Gp "$pkg" 2>&1; then
                :
            else
                echo "(fetch failed: paru -Gp ${pkg})"
                failed=$((failed + 1))
            fi
            echo
        } >>"$OUTFILE"
    done

    PKGBUILD_FETCH_FAILED=$failed
}

_ensure_arch

# shellcheck source=../vars/arch-vars
source "${REPO_ROOT}/vars/arch-vars"

timestamp=$(date +"%Y-%m-%d_%H%M%S")
mkdir -p "${REPO_ROOT}/logs"
OUTFILE="${REPO_ROOT}/logs/${timestamp}_aur-audit.log"
PKGBUILD_FETCH_FAILED=0

declare -a expected_aur=()
_collect_expected_aur expected_aur

mapfile -t installed_raw < <(_list_installed_aur)
mapfile -t installed < <(_sort_unique "${installed_raw[@]}")
mapfile -t expected < <(_sort_unique "${expected_aur[@]}")
mapfile -t keep < <(_intersection installed expected)
mapfile -t missing < <(_difference expected installed)
mapfile -t unexpected < <(_difference installed expected)

{
    echo "# AUR audit changelog"
    echo "# Generated: $(date -Iseconds)"
    echo "# Host: $(hostname 2>/dev/null || echo unknown)"
    echo "# Repo: ${REPO_ROOT}"
    if command -v git &>/dev/null && [ -d "${REPO_ROOT}/.git" ]; then
        echo "# Git: $(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    fi
    if $HEADLESS; then
        echo "# Profile: headless"
    else
        echo "# Profile: full"
    fi
    if $INCLUDE_PKGBUILDS; then
        echo "# PKGBUILDs: included (current AUR via paru -Gp)"
    else
        echo "# PKGBUILDs: skipped (--no-pkgbuilds)"
    fi
    echo
} >"$OUTFILE"

_write_section "Installed AUR" "${installed[@]}"
_write_section "Expected AUR" "${expected[@]}"
_write_section "Keep" "${keep[@]}"
_write_section "Missing" "${missing[@]}"
_write_section "Unexpected" "${unexpected[@]}"

if $INCLUDE_PKGBUILDS; then
    if command -v paru &>/dev/null; then
        _write_pkgbuilds expected
    else
        {
            echo "== PKGBUILDs (0) =="
            echo "(skipped: paru required for paru -Gp)"
            echo
        } >>"$OUTFILE"
    fi
fi

changelog_path="$OUTFILE"
if command -v realpath &>/dev/null; then
    changelog_path=$(realpath "$OUTFILE")
fi

if ! $QUIET; then
    sed '/^== PKGBUILDs /,$d' "$OUTFILE" | sed 's/^/  /'
    if $INCLUDE_PKGBUILDS && [ "${PKGBUILD_FETCH_FAILED:-0}" -gt 0 ]; then
        echo "  aur-audit: ${PKGBUILD_FETCH_FAILED} PKGBUILD fetch(es) failed (see changelog)" >&2
    fi
    echo
fi
echo "$changelog_path"

if $INCLUDE_PKGBUILDS && [ "${PKGBUILD_FETCH_FAILED:-0}" -gt 0 ]; then
    exit 1
fi
