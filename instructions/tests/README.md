# Manual VM tests

Guides for **full** installs you verify by logging into a graphical session (SPICE / virt-manager). Not CI — run locally before large setup or install changes.

## When to use which test

| Track | Command / doc | What it proves |
|-------|----------------|----------------|
| Container smoke | `tests/run container smoke` | Setup script logic (stubbed `sudo`/package managers) |
| Loopback install | `sudo tests/run install loopback` | `install-arch.sh` disk/LVM/btrfs without boot |
| Headless VM | `tests/run vm test` | Real packages + `just install` + docker/virt (no desktop) |
| **Full setup VM** | [setup-full-vm.md](setup-full-vm.md) | Full `setup-*.sh` → log into KDE |
| **Full arch install VM** | [arch-install-full-vm.md](arch-install-full-vm.md) | `install arch` → first boot → log in |

Helpers live in [`tests/manual/`](../../tests/manual/). Docs are the source of truth; scripts create VMs and print SPICE URIs / log paths.

## Host prerequisites

- KVM + libvirt (`virt-manager`, `virt-viewer`, `virt-install`)
- Nested virtualization enabled (if testing inside a VM)
- This repo checked out on the host
- Enough disk for qcow2 images (≥48 GB per setup VM; arch install uses 32+16 GB)

## Disk locations

Helpers default to `~/.local/share/linux-setup/{manual-vm,golden}`. Override with `MANUAL_VM_DIR` and `MANUAL_GOLDEN_DIR` if you prefer another path (e.g. the libvirt default pool):

```bash
virsh pool-dumpxml default | grep -E '<path>|</path>'
export MANUAL_VM_DIR=/var/lib/libvirt/images/linux-setup/manual-vm
export MANUAL_GOLDEN_DIR=/var/lib/libvirt/images/linux-setup/golden
```

See [setup-full-vm.md](setup-full-vm.md) for golden copies and `MANUAL_SETUP_DISK_GB`.

## Logs

| Workflow | Log location |
|----------|----------------|
| Full setup | `logs/<timestamp>_setup.log` under repo root (on guest if repo is there) |
| Arch install | `logs/<timestamp>_install-arch.log` |
| Display manager | `journalctl -u sddm -b` on guest |

Optional SSH preflight before opening the console: `tests/manual/preflight.sh user@host`.
