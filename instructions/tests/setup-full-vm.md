# Full setup VM test (GUI login)

Run the **full** post-install `setup-*.sh` (KDE, apps, flatpak, docker, virt, …) in a libvirt VM with SPICE graphics. You log in and verify visually.

Headless automated smoke stays on `tests/run vm test` (Vagrant). This workflow is separate.

## Overview

```text
  [Path A: ISO install]  or  [Path B: golden qcow2]
            │
            ▼
  tests/manual/setup-vm-run.sh  →  full setup (HEADLESS=0)
            │
            ▼
  reboot → virt-viewer / virt-manager → you log in → checklist
```

## Path A — First time (install OS from ISO)

### 1. Create the VM

```bash
export DEBIAN_ISO=/path/to/debian.iso   # or FEDORA_ISO / ARCH_ISO
tests/manual/setup-vm-create.sh debian
```

Opens a SPICE window (or use virt-manager). Install the base OS:

- **Debian:** [../install/debian.md](../install/debian.md) — minimal install, create user with sudo, **do not** install a full desktop stack (let `setup-debian.sh` install KDE).
- **Fedora:** [../install/fedora.md](../install/fedora.md) — Workstation or minimal + SSH; same idea: avoid duplicating what the setup script installs.
- **Arch:** prefer [arch-install-full-vm.md](arch-install-full-vm.md) (`./install arch` on a SPICE VM, then optional phase 2 setup). `setup-vm-create.sh arch` remains available for a single-disk ISO install if you want a separate setup-only golden image.

Enable **SSH** on the guest (`openssh-server` / `sshd`) so the run script can connect.

### 2. Save a golden image (optional, for Path B)

After OS install, shut down the VM and copy the disk (on btrfs, `cp --reflink=auto` avoids a full duplicate):

```bash
cp ~/.local/share/linux-setup/manual-vm/linux-setup-manual-debian.qcow2 \
   ~/.local/share/linux-setup/golden/debian12-base.qcow2

# Or in btrfs:
cp --reflink=auto ~/.local/share/linux-setup/manual-vm/linux-setup-manual-debian.qcow2 \
   ~/.local/share/linux-setup/golden/debian12-base.qcow2
```

## Disk locations

Defaults (under `$HOME`, usually outside root Snapper timelines):

- `MANUAL_VM_DIR` — `~/.local/share/linux-setup/manual-vm`
- `MANUAL_GOLDEN_DIR` — `~/.local/share/linux-setup/golden`

Override when you want qcow2 files somewhere else (e.g. next to other libvirt disks):

```bash
# Default pool path on this host:
virsh pool-dumpxml default | grep -E '<path>|</path>'

export MANUAL_VM_DIR=/var/lib/libvirt/images/linux-setup/manual-vm
export MANUAL_GOLDEN_DIR=/var/lib/libvirt/images/linux-setup/golden
```

Set these before `setup-vm-create.sh` / `arch-install-vm-create.sh`. Setup VM disk size defaults to **48G** sparse (`MANUAL_SETUP_DISK_GB`); raise if full setup runs out of space.

## Path B — Repeat runs (golden qcow2)

```bash
tests/manual/setup-vm-create.sh debian --from-golden
```

Boots a copy of your saved template. SSH as the same user you created in Path A.

## Run full setup over SSH

On the **host** (repo root):

```bash
export SETUP_VM_HOST=192.168.122.XXX    # guest IP (virsh net-dhcp-leases default)
export SETUP_VM_USER=youruser
export SETUP_VM_SSH_KEY=~/.ssh/id_ed25519   # optional

tests/manual/setup-vm-run.sh debian
```

The script:

1. Rsyncs the repo to `~/linux-setup` on the guest (or uses existing clone).
2. Runs `./setup` with `LINUX_SETUP_NONINTERACTIVE=1`, `LINUX_SETUP_HEADLESS=0`.
3. Enables graphical target if needed, reboots.
4. Prints SPICE URI and log path.

Open the display:

```bash
virsh domdisplay linux-setup-manual-debian
virt-viewer spice://...
```

Or: virt-manager → your VM → **Open**.

### Optional preflight (SSH only)

```bash
tests/manual/preflight.sh "${SETUP_VM_USER}@${SETUP_VM_HOST}"
```

Checks sddm, docker, virsh, and that the latest setup log has no `SETUP_ERRORS` summary.

## Manual checklist

After logging into Plasma as your test user:

- [ ] SDDM login works; Plasma shell loads
- [ ] `ghostty` launches (menu or terminal)
- [ ] Firefox opens (Wayland if Fedora)
- [ ] `docker run hello-world` in a terminal (may need `newgrp docker` or re-login)
- [ ] `virt-manager` opens (libvirt group)
- [ ] Dotfiles: `ls -l ~/.config/nvim` → symlink into `~/Workspace/dotfiles`
- [ ] `cursor` in app menu (Debian/Fedora; Arch AUR path)
- [ ] Steam / gaming apps if you care about that slice
- [ ] Review `logs/*_setup.log` on the guest for warnings

## Troubleshooting

| Issue | Check |
|-------|--------|
| Black SPICE screen | `systemctl status sddm`; `journalctl -u sddm -b` |
| Setup failed | Latest file in `logs/` on guest; re-run with `LINUX_SETUP_LOGGING=1` |
| SSH refused | Guest IP, firewall, `sshd` enabled |
| OOM during setup | Bump RAM in `tests/manual/lib/common.sh` (`MANUAL_VM_MEMORY`) |

## Tear down

```bash
virsh destroy linux-setup-manual-debian
virsh undefine linux-setup-manual-debian --remove-all-storage
```

Adjust VM name per distro (`linux-setup-manual-fedora`, etc.).
