#!/usr/bin/env bash
# Vagrant provisioner: run setup-<distro> headless inside the VM.
# Invoked by Vagrantfile (do not run directly on the host).
set -euo pipefail

REPO=${REPO:-/vagrant}
USERNAME=${1:-${LINUX_SETUP_VM_USER:-$(whoami)}}

export LINUX_SETUP_NONINTERACTIVE=${LINUX_SETUP_NONINTERACTIVE:-1}
export LINUX_SETUP_HEADLESS=${LINUX_SETUP_HEADLESS:-1}
export LINUX_SETUP_LOGGING=1

mkdir -p "$HOME/.config/git"
if [ ! -f "$HOME/.config/git/config.local" ]; then
    cat >"$HOME/.config/git/config.local" <<'EOF'
[user]
    name = VM Smoke Test
    email = vm-smoke@example.com
EOF
fi

# Passwordless sudo for wheel (generic/* boxes usually ship this; ensure for headless).
if ! sudo grep -rE '^[[:space:]]*#?[[:space:]]*%wheel[[:space:]].*NOPASSWD' \
    /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -qvE '^[[:space:]]*#'; then
    echo '%wheel ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/99-linux-setup-wheel >/dev/null
    sudo chmod 440 /etc/sudoers.d/99-linux-setup-wheel
fi
if getent group wheel &>/dev/null; then
    sudo usermod -aG wheel "$USERNAME" 2>/dev/null || true
fi

if [ -r /etc/os-release ]; then
    . /etc/os-release
else
    echo "vm-provision: cannot detect distro (no /etc/os-release)" >&2
    exit 1
fi

case "${ID:-}" in
    debian) script=setup-debian.sh ;;
    fedora) script=setup-fedora.sh ;;
    arch) script=setup-arch.sh ;;
    *)
        echo "vm-provision: unsupported ID=${ID:-?}" >&2
        exit 1
        ;;
esac

mkdir -p "${REPO}/logs"
LOGFILE="${REPO}/logs/vm-${ID}-$(date +%Y%m%d_%H%M%S).log"
export LOGFILE

echo "=== vm-provision: ${script} user=${USERNAME} log=${LOGFILE} ==="
cd "$REPO"
bash "${REPO}/scripts/${script}" "$USERNAME"
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "=== vm-provision OK (rc=0) ==="
else
    echo "=== vm-provision finished with errors (rc=${rc}); see ${LOGFILE} ===" >&2
fi
exit "$rc"
