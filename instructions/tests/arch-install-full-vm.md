# Full arch install VM test (GUI login)

Run `install arch` on real virtio disks in a SPICE VM, reboot into the installed
system, then **log in graphically** as `testuser`.

Loopback smoke (`tests/run install loopback`) does not boot. Headless
`tests/run install vm` uses serial console only. This workflow is for boot +
login verification.

## Overview

```text
  tests/manual/arch-install-vm-create.sh
            │
            ▼
  Live ISO → install arch (answer file, reboot=yes)
            │
            ▼
  virt-viewer → login testuser → checklist
            │
            ▼ (optional phase 2)
  ./setup on installed system → full desktop test
```

## 1. Create VM (SPICE, 8 GB RAM)

```bash
export ARCH_ISO=/path/to/archlinux.iso
tests/manual/arch-install-vm-create.sh create
```

Disks (default):

- `~/.local/share/linux-setup/manual-vm/linux-setup-arch-install-full-root.qcow2` (32G) → `/dev/vda`
- `...-home.qcow2` (16G) → `/dev/vdb`

VM name: `linux-setup-arch-install-full`

## 2. Run installer from live ISO

```bash
tests/manual/arch-install-vm-run.sh
```

Follow printed steps. Summary:

1. Boot into Arch live environment (SPICE window).
2. Clone this repo (or mount from host if you set that up).
3. Run:

```bash
cd linux-setup
sudo ./install arch < tests/manual/arch-vm-full.answers
```

Answer file ends with **`y`** (reboot). Installer unmounts and reboots into the
installed system.

Install log on live session: `logs/<timestamp>_install-arch.log` in the repo
directory (if writable) or path printed by the script.

## 3. Log in and verify

After reboot:

```bash
virsh start linux-setup-arch-install-full   # if shut down
```

Open the display with **virt-manager** (double-click the VM → **Open**) or:

```bash
virsh domdisplay linux-setup-arch-install-full
virt-viewer spice://...
```

Log in as **`testuser`** (password set during install).

### Install-phase checklist

- [ ] System boots from disk (not ISO)
- [ ] Login reaches a session (tty or SDDM if you enabled desktop in install)
- [ ] `findmnt /` shows btrfs subvol `@` (or expected layout)
- [ ] `ls /home` — home on separate device if you used two disks
- [ ] Network works (`ping -c1 archlinux.org`)
- [ ] Install log: no fatal errors; review `logs/*_install-arch.log` if copied to host

## 4. Optional phase 2 — full setup on installed system

Same VM, after install succeeds:

```bash
export SETUP_VM_HOST=<guest-ip>
export SETUP_VM_USER=testuser
tests/manual/setup-vm-run.sh arch
```

Then use the [setup-full-vm.md](setup-full-vm.md) manual checklist for KDE/apps.

## Tear down

```bash
tests/manual/arch-install-vm-create.sh destroy
```

## Answer file

[`tests/manual/arch-vm-full.answers`](../../tests/manual/arch-vm-full.answers) —
same partition layout as `tests/install/arch-vm.answers` but **reboot = yes**.
