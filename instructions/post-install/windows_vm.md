# Windows VM (KVM/QEMU/libvirt)

Setup uses virt-manager on top of the KVM/QEMU/libvirt stack installed by the setup scripts.

## Prep

- Keep VM disk images off btrfs snapshot paths. Default libvirt pool is
  `/var/lib/libvirt/images`; point it elsewhere if that subvolume is snapshotted.
- Install software TPM 2.0 (Windows 11 requires it):

```bash
# Arch
paru -S swtpm
# Fedora
sudo dnf install -y swtpm
# Debian
sudo apt-get install -y swtpm swtpm-tools
```

- UEFI firmware (OVMF) is already pulled in by the setup scripts (`ovmf` / `edk2-ovmf`).
- Download the Windows 11 ISO: https://www.microsoft.com/en-us/software-download/windows11
- Get the virtio-win driver ISO (storage + network + guest tools): 
  https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

## Create the VM (virt-manager)

- New VM → Local install media → select the Windows 11 ISO.
- Before finishing, tick "Customize configuration":
  - Firmware: **UEFI** (OVMF).
  - Add TPM → Emulated → TPM 2.0 (swtpm).
  - Disk bus: **VirtIO** (attach virtio-win ISO as a second CD-ROM).
  - NIC model: **virtio**.
- During Windows setup, "Load driver" → browse the virtio ISO for the storage
  (`vioscsi`/`viostor`) driver so the disk is visible.

## After install (guest tools)

- From the mounted virtio-win ISO, run `virtio-win-guest-tools.exe` inside the guest (installs virtio drivers + QEMU guest agent + SPICE agent).
- Reboot. Display auto-resize and clipboard work via the SPICE agent.

## Notes

- Manage from CLI with `virsh` (e.g. `virsh list --all`, `virsh start win11`).
- Default network is libvirt NAT (`default`); ensure it's active:

```bash
sudo virsh net-autostart default && sudo virsh net-start default
```
