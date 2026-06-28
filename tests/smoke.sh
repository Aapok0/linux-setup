#!/usr/bin/env bash
# In-container test harness for the setup-* scripts. Runs UNPRIVILEGED: every
# destructive/network command is shimmed (see stub.sh) so the real scripts can
# execute end to end. Meant to run inside a distro container (see tests/run.sh).
#
# Usage (inside container):  bash /repo/tests/smoke.sh <arch|debian|fedora> [source|smoke]
#
# Tiers:
#   source  Source lib/common.sh + vars/<distro>-vars, assert key fns exist.
#   smoke   Run scripts/setup-<distro> to completion under stubs. It fails on
#           two things static linting cannot catch:
#             1. a defect-class bash runtime error (unbound variable, bad
#                substitution, syntax error, arithmetic/redirect/array faults,
#                required-but-unset parameter) — these never arise as stub
#                artifacts, so a hit is a real bug;
#             2. not reaching _setup_finalize (early exit / hang).
#           A non-zero script exit is otherwise EXPECTED: stubbed steps (missing
#           groups, un-created ssh key, un-cloned pyenv, ...) record SETUP_ERRORS,
#           so finalize logs "Setup finished with N error(s)" — which doubles as
#           the completion marker. (rc==0 also counts as completed.)
#
#   Intentionally NOT failed on (benign under stubs, would be false positives):
#     - "cd: ...: No such file or directory" / missing relative execs (a stubbed
#       git clone never created the target dir);
#     - "command not found" (an un-stubbed optional tool absent from the image).
#   NOTE: this catches runtime shell faults, not semantics. Stubs exit 0, so a
#         wrong flag to a stubbed command cannot fail, and a genuine failure of a
#         stubbed step is indistinguishable from an expected SETUP_ERRORS bump.
#         The match list is English/C-locale (containers default to C).
set -uo pipefail

REPO=${REPO:-/repo}
distro=${1:?usage: smoke.sh <arch|debian|fedora> [source|smoke]}
tier=${2:-smoke}
export STUB_LOG=/tmp/stub.log

mkdir -p /opt/stub
for c in sudo nala apt-get apt-key dnf paru pacman gpg curl wget systemctl \
    hostnamectl visudo just stow lsb_release findmnt flatpak snap \
    gsettings fc-cache dconf ssh-keygen git python3 make pipx npm cargo; do
    ln -sf "$REPO/tests/stub.sh" "/opt/stub/$c"
done
export PATH="/opt/stub:$PATH"
: >"$STUB_LOG"

echo "########## $distro / tier=$tier ##########"

case "$tier" in
    source)
        REPO_ROOT=$REPO
        export REPO_ROOT
        # shellcheck disable=SC1090,SC1091
        source "$REPO/scripts/lib/common.sh"
        # shellcheck disable=SC1090,SC1091
        source "$REPO/vars/${distro}-vars"
        for fn in _info _warn _error _echo_run _to_ssh_url _ensure_systemd_unit; do
            declare -F "$fn" >/dev/null || {
                echo "FAIL: missing function $fn"
                exit 3
            }
        done
        echo "SOURCE OK ($distro): common.sh + ${distro}-vars sourced; key fns defined"
        echo "  _to_ssh_url check -> $(_to_ssh_url https://github.com/a/b.git)"
        ;;
    smoke)
        export LOGFILE=/tmp/setup.log HOME=/root
        mkdir -p "$HOME/Workspace/dotfiles" "$HOME/.config/git"
        printf '[user]\n\tname = test\n\temail = test@example.com\n' \
            >"$HOME/.config/git/config.local"
        # Repo is mounted read-only; copy to a writable tree to run.
        cp -a "$REPO" /work
        cd /work || exit 1
        echo "--- scripts/setup-$distro testuser (stdin=yes, 120s cap) ---"
        rc=0
        # Feed prompts via process substitution (not a pipe) so 'yes' getting
        # SIGPIPE cannot pollute the captured exit code.
        timeout 120 bash "scripts/setup-$distro" testuser < <(yes) >/tmp/setup.out 2>&1 || rc=$?
        echo "=== last 15 log lines ==="
        tail -15 /tmp/setup.out
        echo "=== privileged/external calls captured ==="
        awk '{print $2}' "$STUB_LOG" | sort | uniq -c | sort -rn

        # 1. Defect-class bash runtime errors (see header for what's excluded).
        fatal=$(grep -nE 'unbound variable|bad substitution|syntax error|ambiguous redirect|division by 0|bad array subscript|integer expression expected|parameter null or not set' /tmp/setup.out || true)
        # 2. Completion: finalize logged its summary, or the script exited 0.
        completed=no
        if [ "$rc" -eq 0 ] || grep -q 'Setup finished with' /tmp/setup.out; then
            completed=yes
        fi

        if [ -n "$fatal" ]; then
            echo "SMOKE FAIL ($distro): bash runtime error(s):"
            echo "$fatal"
            exit 1
        fi
        if [ "$completed" != yes ]; then
            echo "SMOKE FAIL ($distro): did not reach _setup_finalize (early exit or 120s timeout; rc=$rc)"
            exit 1
        fi
        echo "SMOKE OK ($distro): reached _setup_finalize, no bash runtime errors (rc=$rc; non-zero is expected under stubs)"
        ;;
    *)
        echo "unknown tier: $tier (use 'source' or 'smoke')"
        exit 2
        ;;
esac
