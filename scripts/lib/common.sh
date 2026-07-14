#!/usr/bin/env bash
# Shared helpers for linux-setup scripts.
#
# Source from a script under scripts/:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# Sections:
#   1. Logging
#   2. Setup runtime (headless mode, error counter, init_logging)
#   3. Interactive prompts
#   4. Shared setup helpers (_cursor_installed, _install_nvm, _install_flatpak_apps, docker, virt, …)
#   5. Snapper helpers (btrfs setup-arch + setup-fedora)
#
# Exit codes:
#   0 - success
#   1 - error
#   2 - user cancelled

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${_LIB_DIR}/../.." && pwd)}"

# ============================================================================
# Logging
# ============================================================================

_log() {
    local level="$1"
    shift
    printf "[%s] %s: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >&2
}

_out() {
    _log "OUT" "$@"
}

_section() {
    _out "=========================================="
    _out "$1"
    _out "=========================================="
}

_info() {
    _log "INFO" "$@"
}

_error() {
    _log "ERROR" "$@"
}

_warn() {
    _log "WARN" "$@"
}

_log_cmd_output() {
    local output rc=0

    _log "RUN" "$*"
    output=$("$@" 2>&1) || rc=$?

    if [ -n "$output" ]; then
        while IFS= read -r line; do
            _log "OUT" "$line"
        done <<<"$output"
    fi

    return "$rc"
}

_log_interactive() {
    _log "RUN" "$* (interactive)"
}

# ============================================================================
# Setup runtime
# ============================================================================

SETUP_ERRORS=0

# When LINUX_SETUP_NONINTERACTIVE=1, prompts use fixed defaults (see _prompt_yes_no).
# When LINUX_SETUP_HEADLESS=1, setup-* skips desktop/gaming/VPN stacks (default for automated VM smoke).
_linux_setup_headless() {
    [ "${LINUX_SETUP_HEADLESS:-}" = "1" ]
}

_linux_setup_apply_headless_defaults() {
    _linux_setup_headless || return 0
    _info "Headless mode enabled (LINUX_SETUP_HEADLESS=1)"
    SETUP_BTRFS_SNAPPER=false
    SETUP_GRUB_BTRFS=false
    SETUP_GRUB_CRYPTOMOUNT=false
    SETUP_FEDORA_HIBERNATE=false
}

_setup_record_error() {
    SETUP_ERRORS=$((SETUP_ERRORS + 1))
}

_echo_run() {
    _log "RUN" "$*"
    local rc=0
    "$@" || rc=$?
    if [ "$rc" -eq 0 ]; then
        return 0
    fi
    _error "Command failed (exit ${rc}): $*"
    _setup_record_error
    return 1
}

_setup_finalize() {
    if [ "${SETUP_ERRORS:-0}" -gt 0 ]; then
        _error "Setup finished with ${SETUP_ERRORS} error(s). See ${LOGFILE}"
        return 1
    fi
    return 0
}

init_logging() {
    local log_basename=$1
    local timestamp

    if [ -z "${LOGFILE:-}" ]; then
        timestamp=$(date +"%Y-%m-%d_%H:%M:%S")
        LOGFILE="${REPO_ROOT}/logs/${timestamp}_${log_basename}.log"
    fi

    mkdir -p "${REPO_ROOT}/logs"

    if [ "${LINUX_SETUP_LOGGING:-}" = "1" ]; then
        return 0
    fi

    exec 1> >(tee -a "$LOGFILE") 2>&1
    export LINUX_SETUP_LOGGING=1
    export LOGFILE
    _log "INFO" "Logging to: ${LOGFILE}"
}

# ============================================================================
# Interactive prompts
# ============================================================================

_prompt_yes_no() {
    local prompt_msg=$1
    local noninteractive_default=${2:-y}
    local response

    if [ "${LINUX_SETUP_NONINTERACTIVE:-}" = "1" ]; then
        case "$noninteractive_default" in
            [Yy] | [Yy][Ee][Ss])
                _out "${prompt_msg} yes (noninteractive)"
                return 0
                ;;
            *)
                _out "${prompt_msg} no (noninteractive)"
                return 1
                ;;
        esac
    fi

    while true; do
        read -r -p "$prompt_msg" response

        case $response in
            [Yy] | [Yy][Ee][Ss])
                _out "${prompt_msg} yes"
                return 0
                ;;
            [Nn] | [Nn][Oo])
                _out "${prompt_msg} no"
                return 1
                ;;
            *)
                _warn "Please enter y or n"
                ;;
        esac
    done
}

# ============================================================================
# Shared setup helpers
# ============================================================================

_to_ssh_url() {
    local url=$1
    case "$url" in
        https://github.com/*) echo "git@github.com:${url#https://github.com/}" ;;
        *) echo "$url" ;;
    esac
}

_set_ssh_remote() {
    local repo_path=$1
    local https_url ssh_url

    cd "$repo_path" || return 1
    https_url=$(git config --get remote.origin.url)
    ssh_url=$(_to_ssh_url "$https_url")
    if [ "$https_url" != "$ssh_url" ]; then
        _echo_run git remote set-url origin "$ssh_url"
    fi
    cd - >/dev/null || return 1
}

_check_firewall_service() {
    command -v "$2" &>/dev/null && systemctl is-active --quiet "$1" && {
        SETUP_UFW=false
        _info "Service $1 already installed/enabled. Check rules manually."
    }
}

_ensure_group() {
    local group=$1

    if getent group "$group" &>/dev/null; then
        _info "Group ${group} already exists"
        return 0
    fi

    _info "Creating group ${group}..."
    _echo_run sudo groupadd -r "$group"
}

_user_in_group() {
    local user=$1
    local group=$2

    id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx "$group"
}

_ensure_user_in_group() {
    local user=$1
    local group=$2

    if _user_in_group "$user" "$group"; then
        _info "User ${user} already in group ${group}"
        return 0
    fi

    if ! getent group "$group" &>/dev/null; then
        _error "Group ${group} does not exist"
        return 1
    fi

    _info "Adding ${user} to group ${group}..."
    if _echo_run sudo usermod -aG "$group" "$user"; then
        return 0
    fi

    _echo_run sudo gpasswd -a "$user" "$group"
}

_ensure_systemd_unit() {
    local unit=$1
    local also_start=${2:-false}

    if systemctl is-enabled "$unit" &>/dev/null; then
        _info "systemd unit ${unit} already enabled"
    else
        _info "Enabling systemd unit ${unit}..."
        _echo_run sudo systemctl enable "$unit"
    fi

    if [ "$also_start" = true ]; then
        if systemctl is-active --quiet "$unit"; then
            _info "systemd unit ${unit} already active"
        else
            _info "Starting systemd unit ${unit}..."
            _echo_run sudo systemctl start "$unit"
        fi
    fi
}

_ensure_systemd_enabled_now() {
    _ensure_systemd_unit "$1" true
}

_setup_systemd_resolved() {
    if [ -f "/etc/resolv.conf.bak" ]; then
        _info "systemd-resolved already setup"
        return 0
    fi

    if [ -L /etc/resolv.conf ] && readlink /etc/resolv.conf | grep -q systemd; then
        _info "systemd-resolved already in use"
        _echo_run sudo systemctl enable --now systemd-resolved.service
        return 0
    fi

    _echo_run sudo systemctl enable --now systemd-resolved.service
    _echo_run sudo mv /etc/resolv.conf /etc/resolv.conf.bak
    _echo_run sudo ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
}

# --- Identity ---

_pip_user_pkg_installed() {
    python3 -m pip show "$1" &>/dev/null
}

_install_pip_user_packages() {
    local pkg

    for pkg in "$@"; do
        if _pip_user_pkg_installed "$pkg"; then
            _info "pip package ${pkg} already installed"
            continue
        fi
        _out "Installing pip package ${pkg}"
        _echo_run python3 -m pip install --user "$pkg"
    done
}

_setup_git_config() {
    local config_dir="$HOME/.config/git"
    local config_file="$config_dir/config.local"
    local git_name git_email

    [ -d "$config_dir" ] || _echo_run mkdir -p "$config_dir"

    if [ -f "$config_file" ]; then
        _info "Git config already exists at $config_file"
        return 0
    fi

    if [ "${LINUX_SETUP_NONINTERACTIVE:-}" = "1" ]; then
        git_name=${LINUX_SETUP_GIT_NAME:-}
        git_email=${LINUX_SETUP_GIT_EMAIL:-}
        if [ -z "$git_name" ] || [ -z "$git_email" ]; then
            _info "Skipping git config setup (noninteractive; set LINUX_SETUP_GIT_NAME/EMAIL or pre-seed $config_file)"
            return 0
        fi
        _echo_run mkdir -p "$config_dir"
        cat >"$config_file" <<EOF
[user]
    name = $git_name
    email = $git_email
EOF
        _info "Git user config created at $config_file (noninteractive)"
        return 0
    fi

    _info "Enter your Git user name or real name (or press Enter to skip):"
    read -r -p "  → " git_name

    if [ -z "$git_name" ]; then
        _warn "Skipped git config setup"
        return 0
    fi

    _info "Enter your Git email:"
    read -r -p "  → " git_email

    _echo_run mkdir -p "$config_dir"
    cat >"$config_file" <<EOF
[user]
    name = $git_name
    email = $git_email
EOF
    _info "Git user config created at $config_file"
}

_setup_hostname() {
    local hostname current

    if [ "${LINUX_SETUP_NONINTERACTIVE:-}" = "1" ]; then
        if [ -n "${LINUX_SETUP_HOSTNAME:-}" ]; then
            current=$(cat /etc/hostname 2>/dev/null || hostname -s 2>/dev/null || echo "")
            hostname="$LINUX_SETUP_HOSTNAME"
            if [ "$hostname" = "$current" ]; then
                _info "Hostname already ${hostname} (noninteractive)"
                return 0
            fi
            _info "Setting hostname to ${hostname} (noninteractive)..."
            if command -v hostnamectl &>/dev/null; then
                _echo_run sudo hostnamectl set-hostname "$hostname"
            else
                _echo_run sudo tee /etc/hostname >/dev/null <<<"$hostname"
                _echo_run sudo hostname "$hostname"
            fi
        else
            _info "Skipping hostname setup (noninteractive)"
        fi
        return 0
    fi

    current=$(cat /etc/hostname 2>/dev/null || hostname -s 2>/dev/null || echo "")
    _section "System hostname"
    [ -n "$current" ] && _out "Current: ${current}"

    if ! _prompt_yes_no "Set hostname? (y/n): "; then
        return 0
    fi

    while true; do
        read -r -p "Enter hostname [${current}]: " hostname
        hostname=${hostname:-$current}

        if [[ $hostname =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
            break
        fi

        _error "Invalid hostname. Use letters, numbers, underscore, or hyphen."
    done

    if [ "$hostname" = "$current" ]; then
        _info "Hostname unchanged"
        return 0
    fi

    _info "Setting hostname to ${hostname}..."
    if command -v hostnamectl &>/dev/null; then
        _echo_run sudo hostnamectl set-hostname "$hostname"
    else
        _echo_run sudo tee /etc/hostname >/dev/null <<<"$hostname"
        _echo_run sudo hostname "$hostname"
    fi
}

_wheel_sudo_nopasswd_enabled() {
    grep -rE '^[[:space:]]*#?[[:space:]]*%wheel[[:space:]].*NOPASSWD' \
        /etc/sudoers /etc/sudoers.d/* 2>/dev/null |
        grep -qvE '^[[:space:]]*#'
}

_setup_wheel_nopasswd_sudo() {
    local user=$1
    local sudoers_file=/etc/sudoers.d/99-linux-setup-wheel

    _section "Passwordless sudo (wheel group)"

    if _wheel_sudo_nopasswd_enabled; then
        _info "NOPASSWD for %wheel already configured"
    elif ! _prompt_yes_no "Enable passwordless sudo for wheel group? (y/n): " y; then
        _ensure_user_in_group "$user" wheel
        return 0
    else
        _info "Enabling NOPASSWD for %wheel in ${sudoers_file}..."
        printf '%s\n' '%wheel ALL=(ALL) NOPASSWD: ALL' | _echo_run sudo tee "$sudoers_file" >/dev/null
        _echo_run sudo chmod 440 "$sudoers_file"
        _echo_run sudo visudo -cf "$sudoers_file" || {
            _error "sudoers validation failed; removing ${sudoers_file}"
            _echo_run sudo rm -f "$sudoers_file"
            return 1
        }
    fi

    _ensure_user_in_group "$user" wheel
}

_ensure_ssh_ed25519_key() {
    local key="${HOME}/.ssh/id_ed25519"

    if [ -f "$key" ]; then
        _info "SSH key already exists: ${key}"
        return 0
    fi

    command -v ssh-keygen &>/dev/null || {
        _warn "ssh-keygen not found; skipping SSH key generation"
        return 0
    }

    _info "Generating ed25519 SSH key (no passphrase) at ${key}..."
    _echo_run mkdir -p "${HOME}/.ssh"
    _echo_run chmod 700 "${HOME}/.ssh"
    _echo_run ssh-keygen -t ed25519 -f "$key" -N "" -q
    _echo_run chmod 600 "$key"
    [ -f "${key}.pub" ] && _echo_run chmod 644 "${key}.pub"
}

# --- Applications (shared detection + cross-distro installers) ---

_cursor_installed() {
    command -v cursor &>/dev/null && return 0
    [ -x /usr/share/cursor/cursor ] && return 0
    rpm -q cursor &>/dev/null && return 0
    dpkg -l cursor 2>/dev/null | grep -q '^ii'
}

_install_nvm() {
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        _info "nvm already installed at ~/.nvm"
        return 0
    fi

    _info "Downloading and installing nvm..."
    _echo_run bash -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash'
    _info "nvm installed"
    _info "Add the following to your shell startup file if not already present:"
    _out '  export NVM_DIR="$HOME/.nvm"'
    _out '  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
    _out '  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
}

_install_flatpak_apps() {
    local category="$1"
    shift
    local apps=("$@")
    [ ${#apps[@]} -eq 0 ] && return 0

    if ! command -v flatpak &>/dev/null; then
        _info "flatpak not found; installing..."
        if command -v pacman &>/dev/null; then
            _echo_run sudo pacman -S --needed --noconfirm flatpak
        elif command -v dnf &>/dev/null; then
            _echo_run sudo dnf install -y flatpak
        elif command -v nala &>/dev/null; then
            _echo_run sudo nala install -y flatpak
        elif command -v apt-get &>/dev/null; then
            _echo_run sudo apt-get install -y flatpak
        else
            _warn "flatpak not installed and no supported package manager found; skipping $category"
            return 0
        fi
    fi

    command -v flatpak &>/dev/null || {
        _warn "flatpak still not available after install attempt; skipping $category"
        return 0
    }

    _info "Installing $category..."
    if flatpak remote-list --system 2>/dev/null | grep -qx 'flathub'; then
        _info "Flathub system remote already configured"
    else
        _echo_run sudo flatpak remote-add --if-not-exists --system flathub \
            https://flathub.org/repo/flathub.flatpakrepo
    fi
    for app in "${apps[@]}"; do
        [ -z "$app" ] && continue
        [[ "$app" == \#* ]] && continue
        flatpak list --app --system 2>/dev/null | grep -q "$app" && {
            _info "Flatpak $app already installed"
            continue
        }
        _out "Installing flatpak $app"
        _echo_run sudo flatpak install -y --system flathub "$app"
    done
}

# --- Services (caller must define _install_packages in setup-*.sh) ---

_setup_docker() {
    local user=$1
    shift
    local packages=("$@")

    _info "Setting up Docker..."
    _install_packages "docker" "${packages[@]}"

    _ensure_group docker
    _ensure_user_in_group "$user" docker
    _ensure_systemd_enabled_now docker.service
}

_setup_virtualization() {
    local user=$1
    shift
    local packages=("$@")

    _info "Setting up virtualization (KVM/QEMU/libvirt + Vagrant)..."
    _install_packages "virtualization" "${packages[@]}"

    _ensure_user_in_group "$user" libvirt
    if getent group kvm &>/dev/null; then
        _ensure_user_in_group "$user" kvm
    fi
    _ensure_systemd_enabled_now libvirtd.service

    _info "Virtualization ready. Log out/in for group membership to apply."
    _info "Manage VMs with virt-manager / virsh; default URI qemu:///system."
}

# --- Desktop ---

_install_ghostty_desktop_override() {
    [ "$(uname -s)" = "Linux" ] || return 0
    command -v ghostty &>/dev/null || return 0
    [ -d "$HOME/Workspace/dotfiles" ] || {
        _warn "dotfiles not found; skip Ghostty desktop override (run: cd ~/Workspace/dotfiles && just ghostty-desktop)"
        return 0
    }

    _info "Installing Ghostty desktop override (GTK dead keys / Finnish ~)..."
    _echo_run bash -c 'cd "$HOME/Workspace/dotfiles" && just ghostty-desktop'
}

# ============================================================================
# Snapper helpers (setup-arch + setup-fedora btrfs paths)
# ============================================================================

_snapper_config_value() {
    local config=$1
    local key=$2
    local line

    line=$(sudo snapper -c "$config" get-config "$key" 2>/dev/null) || return 1
    sed -n "s/^${key}=\"\\(.*\\)\"$/\\1/p" <<<"$line"
}

_snapper_allow_users_contains() {
    local allow_users=$1
    local username=$2
    local user

    [ -z "$allow_users" ] && return 1
    for user in ${allow_users//,/ }; do
        user=${user#\"}
        user=${user%\"}
        [ "$user" = "$username" ] && return 0
    done
    return 1
}

_ensure_snapper_access() {
    local config=$1
    local username=$2
    local allow_users sync_acl
    local updates=()

    allow_users=$(_snapper_config_value "$config" ALLOW_USERS || true)
    sync_acl=$(_snapper_config_value "$config" SYNC_ACL || true)

    if [ -z "$allow_users" ]; then
        updates+=("ALLOW_USERS=${username}")
    elif ! _snapper_allow_users_contains "$allow_users" "$username"; then
        _info "Snapper config '${config}' ALLOW_USERS already set (${allow_users}); leaving unchanged"
    else
        _info "Snapper config '${config}' ALLOW_USERS already includes ${username}"
    fi

    if [ "$sync_acl" != "yes" ]; then
        updates+=("SYNC_ACL=yes")
    else
        _info "Snapper config '${config}' SYNC_ACL already yes"
    fi

    if [ ${#updates[@]} -eq 0 ]; then
        _info "Snapper config '${config}' user access already configured"
        return 0
    fi

    _info "Updating Snapper config '${config}': ${updates[*]}"
    _echo_run sudo snapper -c "$config" set-config "${updates[@]}"
}

_apply_snapper_home_timeline() {
    local config=$1

    _info "Setting Snapper config '${config}' TIMELINE_CREATE=no (new home config)"
    _echo_run sudo snapper -c "$config" set-config TIMELINE_CREATE=no
}
