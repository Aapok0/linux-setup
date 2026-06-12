# GRUB cryptomount auto-fix (encrypted root, no separate `/boot`)

When `/boot` lives inside a LUKS-encrypted btrfs root, GRUB needs this as the **first line** of `/boot/efi/EFI/fedora/grub.cfg`:

```
cryptomount -u <LUKS_UUID_WITHOUT_DASHES>
```

Fedora updates can regenerate that file and drop the line, which leaves the system at a GRUB rescue prompt on the next reboot.

| File | Installed to |
|------|----------------|
| `99_cryptomount_check` | `/etc/grub.d/99_cryptomount_check` |
| `cryptomount-check.service` | `/etc/systemd/system/cryptomount-check.service` |
| `cryptomount-check.path` | `/etc/systemd/system/cryptomount-check.path` |

The grub.d script runs after `grub2-mkconfig`. The path unit watches `/boot/efi/EFI/fedora/` and re-runs the check when `grub.cfg` is replaced outside `grub2-mkconfig`.

`setup-fedora` installs these only when root is LUKS-encrypted and `/boot` is not on a separate unencrypted partition.

Adapted from [SysGuides sysguides-grub-cryptomount-fix](https://github.com/SysGuides/sysguides-grub-cryptomount-fix) (Madhu Desai / [sysguides.com](https://sysguides.com)).
