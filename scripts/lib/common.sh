#!/usr/bin/env bash
# Shared helpers for linux-setup scripts.
#
# Source from a script under scripts/:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# Exit codes (install-arch):
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
        done <<< "$output"
    fi

    return "$rc"
}

_echo_run() {
    _log "RUN" "$*"
    "$@" || {
        _error "Command failed (exit $?): $*"
        return 1
    }
}

_log_interactive() {
    _log "RUN" "$* (interactive)"
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
# Error handling (install-arch)
# ============================================================================

_propagate_rc() {
    local rc=$1
    local err_msg=${2:-}

    case $rc in
        0) return 0 ;;
        2) return 2 ;;
        *)
            if [ -n "$err_msg" ]; then
                _error "$err_msg"
            fi
            return 1
            ;;
    esac
}

_run_phase() {
    local name=$1 rc
    shift

    _section "Phase: ${name}"
    _info "Starting phase: ${name}"
    "$@"
    rc=$?
    if [ $rc -eq 0 ]; then
        _info "Phase completed: ${name}"
    fi
    _propagate_rc $rc "${name} failed"
}

_exit_on_rc() {
    local rc=$1

    case $rc in
        0) return 0 ;;
        2)
            _info "Installation cancelled by user. Exiting."
            exit 0
            ;;
        *)
            exit 1
            ;;
    esac
}

_prompt_yes_no() {
    local prompt_msg=$1
    local response

    while true; do
        read -r -p "$prompt_msg" response

        case $response in
            [Yy]|[Yy][Ee][Ss])
                _out "${prompt_msg} yes"
                return 0
                ;;
            [Nn]|[Nn][Oo])
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
    echo "$url" | sed 's|https://github\.com/|git@github.com:|'
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
    cd - > /dev/null || return 1
}

_check_firewall_service() {
    command -v "$2" &> /dev/null && systemctl is-active --quiet "$1" && {
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

_pacman_multilib_enabled() {
    [ -f /etc/pacman.conf ] \
        && grep -A1 '^\[multilib\]' /etc/pacman.conf | grep -q '^Include = '
}

_ensure_pacman_multilib() {
    if _pacman_multilib_enabled; then
        _info "multilib repository already enabled"
        return 0
    fi

    _info "Enabling multilib repository..."
    _echo_run sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
}

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

    _info "Enter your Git user name or real name (or press Enter to skip):"
    read -r -p "  → " git_name

    if [ -z "$git_name" ]; then
        _warn "Skipped git config setup"
        return 0
    fi

    _info "Enter your Git email:"
    read -r -p "  → " git_email

    _echo_run mkdir -p "$config_dir"
    cat > "$config_file" << EOF
[user]
    name = $git_name
    email = $git_email
EOF
    _info "Git user config created at $config_file"
}

_setup_hostname() {
    local hostname current

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
        _echo_run sudo tee /etc/hostname > /dev/null <<< "$hostname"
        _echo_run sudo hostname "$hostname"
    fi
}

_wheel_sudo_nopasswd_enabled() {
    grep -rE '^[[:space:]]*#?[[:space:]]*%wheel[[:space:]].*NOPASSWD' \
        /etc/sudoers /etc/sudoers.d/* 2>/dev/null \
        | grep -qvE '^[[:space:]]*#'
}

_setup_wheel_nopasswd_sudo() {
    local user=$1
    local sudoers_file=/etc/sudoers.d/99-linux-setup-wheel

    _section "Passwordless sudo (wheel group)"

    if _wheel_sudo_nopasswd_enabled; then
        _info "NOPASSWD for %wheel already configured"
    elif ! _prompt_yes_no "Enable passwordless sudo for wheel group? (y/n): "; then
        _ensure_user_in_group "$user" wheel
        return 0
    else
        _info "Enabling NOPASSWD for %wheel in ${sudoers_file}..."
        printf '%s\n' '%wheel ALL=(ALL) NOPASSWD: ALL' | _echo_run sudo tee "$sudoers_file" > /dev/null
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
