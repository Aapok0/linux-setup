# Fedora manual install guide

For installing Fedora with my personal preferences via the Anaconda Web UI installer.

Target: **Fedora 44+** amd64, **Fedora KDE Plasma Spin** ISO. The installer is a four-step linear wizard; user account, timezone, and hostname are configured on first boot via **Plasma Setup** (not in Anaconda).

## Installer flow (Fedora 44 Web UI)

| Step | Screen | What you configure |
|------|--------|-------------------|
| 1 | **Welcome** | Language, keyboard layout |
| 2 | **Installation method** | Destination disk, install method (see below) |
| 2b | **Storage editor** *(optional)* | ⋮ menu → **Launch storage editor** — manual partitioning via Cockpit Storage |
| 3 | **Storage configuration** | **Encrypt my data** *(if not already set in storage editor)*, LUKS passphrase, keyboard layout at boot |
| 4 | **Review and install** | Confirm layout, start install |

**Installation method** options (under *How would you like to install?*):

- **Share disk with other operating systems** — dual boot; uses unallocated space or reclaim dialog
- **Use entire disk** — wipe selected disk, automatic btrfs layout
- **Mount point assignment** — assign existing partitions to mount points (`/`, `/boot`, `/boot/efi`, …)

If Fedora is already on the disk, a **Reinstall Fedora** option may appear at the top (fresh install, keeps `/home` data).

> **Dual boot + small ESP:** Anaconda warns if `/boot/efi` is under **500 MiB**. Windows often ships a 100–260 MiB ESP; Fedora can reuse it, but expanding the ESP in Windows/GParted before install avoids boot issues.

Steps **not** in the Fedora 44 installer (moved to first boot):

- Time & date / timezone
- Hostname
- User account creation
- Software / desktop selection (KDE Plasma is baked into the Spin ISO)

**Reading order:** [Windows prep](#windows-dual-boot--prepare-before-partitioning) (dual boot only) → [Boot live image](#boot-installer) → [Live session setup](#live-session--before-the-installer) → installer **1–2** → [storage editor](#storage-editor-manual-layouts) if using Option A / custom layout → **3–4** → [encryption](#full-disk-encryption-option-a) GRUB steps if needed → [First boot](#first-boot--plasma-setup) → [Post-install](#post-install-setup).

## Windows dual boot — prepare before partitioning

Skip this section on a dedicated Linux disk. Required when installing Fedora **alongside Windows on the same drive**.

### Install order

Install **Windows first**, then Fedora. Windows overwrites the shared EFI boot chain if installed after Linux.

### In Windows (before Fedora install)

1. **Back up** important data
2. **Disable Fast Startup**
   - Control Panel → Power Options → **Choose what the power buttons do**
   - **Change settings that are currently unavailable**
   - Uncheck **Turn on fast startup**
   - Full shutdown (not “Restart” with Fast Startup) in an elevated Command Prompt:

     ```cmd
     shutdown /s /t 0
     ```
3. **BitLocker** (if enabled — common on Windows 11 Pro)
   - Suspend BitLocker for the install, or decrypt the Windows partition temporarily
   - Linux installer cannot shrink a BitLocker-encrypted volume safely
   - Re-enable after Fedora is installed and verified
4. **Shrink Windows partition** — create unallocated space for Fedora
   - `Win + R` → `diskmgmt.msc`
   - Right-click Windows partition (usually `C:`) → **Shrink Volume**
   - Allocate **≥ 80 GiB** (81920 MiB) for Fedora; more if you install games or dev tools
   - Leave resulting space as **Unallocated** — do not create a new Windows volume there
5. **Optional:** note existing **EFI System Partition** size (usually 100–260 MiB). Fedora reuses it; do not delete it

### Firmware

- UEFI boot mode (not legacy BIOS)
- **SATA mode / storage controller** → **AHCI** or **NVMe** (not **RAID** / **Intel RST**). Linux cannot see Windows volumes on an RST/RAID array without dmraid setup; switch before installing either OS when possible
- **Secure Boot** can stay enabled for Fedora; disable only if install media or NVIDIA drivers fail to boot

## Boot installer

1. Boot the Fedora KDE Plasma Spin live image (UEFI)
2. Choose **Try Fedora** (live session)
3. Complete [Live session — before the installer](#live-session--before-the-installer) (keyboard, network, encryption prep)
4. Launch **Install to Hard Drive** from the desktop (or the welcome dialog)

## Live session — before the installer

Do this in the **live desktop session** before opening **Install to Hard Drive**. You need a working keyboard layout for terminal work (encryption patch, post-install GRUB steps) and for typing passphrases consistently.

### Finnish keyboard

The Anaconda **Welcome** screen also sets keyboard layout, but the **live session terminal** uses the layout below until then. Set both console and graphical layouts:

```bash
localectl set-keymap fi
localectl set-x11-keymap fi
```

Verify:

```bash
localectl status
```

### Internet connection

Ethernet usually works immediately. Check:

```bash
ip link
ping -c 1 fedoraproject.org
```

Wi-Fi (if needed): use the NetworkManager applet in the panel, or `nmcli` / `nmtui` from a terminal.

### Option A full disk encryption — Anaconda patch

If you plan [Option A](#option-a--snapper-ready-btrfs-recommended) with **`/boot` on encrypted root** ([Full disk encryption](#full-disk-encryption-option-a)), patch Anaconda **now** — before starting the installer. The Web UI blocks encrypted `/boot` otherwise.

See [Before install — Anaconda patch](#before-install--anaconda-patch-live-iso) for the full steps (`localectl` above first so `sudo` password entry uses Finnish layout).

Rebooting the live session clears the patch — complete the install in the same session, or re-apply after reboot.

## 1. Welcome

1. Language → **English (United States)**
2. Keyboard layout → **Finnish**
3. Continue

## 2. Installation method

Select **Destination** (target disk). On multi-disk systems, use **Change destination** if the default is wrong.

Do **not** choose **Use entire disk** when dual-booting — that wipes Windows.

### Linux only — whole disk

1. Select the target disk
2. **How would you like to install?** → **Use entire disk**
3. Continue to [Storage configuration](#3-storage-configuration)

Anaconda creates a default btrfs layout (approximate):

| Partition | Size | FS | Mount |
|-----------|------|----|-------|
| EFI System Partition | ~629 MiB | FAT | `/boot/efi` |
| `/boot` | ~2 GiB | ext4 | `/boot` |
| remainder | rest | btrfs (subvols `root`, `home`) | `/`, `/home` |

Add a **swap partition** sized for hibernate in the storage editor if needed ([Swap](#swap-optional--all-layouts)). For Snapper rollbacks use [Option A](#option-a--snapper-ready-btrfs-recommended) instead of this default layout.

### Dual boot — share disk with Windows

1. Select the disk that contains Windows and the unallocated space
2. **How would you like to install?** → **Share disk with other operating systems**
   - Anaconda installs into **unallocated space** only
   - If no free space exists, the **reclaim** dialog can delete or resize supported partitions (NTFS/BitLocker volumes must be prepared in Windows first)
3. **Reuse the existing EFI System Partition** — mount `/boot/efi`, **do not reformat**
4. Do **not** delete or reformat Windows (`ntfs`) partitions
5. Optional **swap** partition in unallocated space ([Swap](#swap-optional--all-layouts))
6. Continue to [Storage configuration](#3-storage-configuration)

For btrfs + Snapper on unallocated space, use the storage editor and follow [Option A — dual boot variant](#variant-dual-boot-with-windows-same-disk) instead of the guided reclaim flow alone.

### Mount point assignment (pre-partitioned or custom reuse)

Use when partitions are already laid out (external tool, previous Linux install, or after using the storage editor):

1. **How would you like to install?** → **Mount point assignment**
2. Assign mandatory mount points starting with **`/`** (root), then **`/boot`**, then **`/boot/efi`**
3. Add optional mount points (`/home`, swap, …) as needed
4. Continue to [Storage configuration](#3-storage-configuration)

For btrfs + Snapper or custom layouts, use the [storage editor](#storage-editor-manual-layouts) from step 2 before continuing to step 3.

## Storage editor (manual layouts)

Open **⋮** (top-right) → **Launch storage editor** from the installation method / storage screen (step 2).

Cockpit Storage applies changes **immediately** on disk (unlike the main Anaconda flow, which commits on **Review and install**). All layouts assume UEFI.

Layout inspired by [SysGuides: Fedora 44 btrfs snapshot and rollback](https://sysguides.com/fedora-44-with-btrfs-snapshot-and-rollback-support). Post-install: [Post-install setup](#post-install-setup).

> **Btrfs snapshot basics**
>
> - Snapper snapshots the **`root`** subvolume only — sibling subvolumes (`log`, `cache`, `plasmalogin`, `media`, …) are excluded from rollback.
> - **`plasmalogin`** stays writable when booting a read-only snapshot from GRUB; large rollbacks can still mismatch login state with rolled-back `/usr` ([recovery](#login-broken-after-a-large-rollback)).
> - **`flatpak`** rollback does not revert runtimes in `/var/lib/flatpak` — use Flatpak tools for app issues.
> - **`.snapshots`** is created by `snapper create-config /` on first setup, not at install time.

#### Swap (optional — all layouts)

Fedora defaults to **zram** swap (no partition). zram cannot hibernate.

| Goal | Action |
|------|--------|
| No hibernate | Skip swap partition; accept zram defaults |
| Hibernate | Add a **linux-swap** partition in the storage editor |

**Size:** `swap ≥ RAM + √RAM` (GiB). Round up to whole GiB.

| RAM | Minimum swap |
|-----|--------------|
| 16 GiB | 20 GiB |
| 32 GiB | 38 GiB |
| 64 GiB | 72 GiB |

General formula: for `R` GiB RAM, allocate at least `R + sqrt(R)` GiB swap (round up to whole GiB).

After install:

```bash
swapon --show          # confirm disk swap meets minimum
sudo systemctl hibernate
```

Alternatively use a [btrfs swap file](https://fedoramagazine.org/update-on-hibernation-in-fedora-workstation/) post-install (Option A only).

#### Option A — Snapper-ready btrfs (recommended)

Single btrfs layout for Snapper rollbacks: **no separate `/boot` partition** — kernels and initramfs live on `root` and roll back with the system.

Works on **one disk**, **dual boot with Windows**, or **split across multiple disks** (system on disk 1; home on disk 2; media on disk 2 or its own disk 3).

**Partitions (single disk)**

| Name | Size | Type | Mount |
|------|------|------|-------|
| `ESP` | 1 GiB | EFI System | `/boot/efi` |
| `swap` | RAM + √RAM *(optional)* | linux-swap | — |
| `FEDORA` | remainder | btrfs | *(subvolumes below)* |

**Subvolumes** (create under the btrfs partition via **Create subvolume** on top-level):

| Subvolume name | Mount point | Purpose |
|----------------|-------------|---------|
| `root` | `/` | System files — **Snapper snapshots this** |
| `home` | `/home` | User data — optional Snapper config |
| `media` | `/home/Media` | Games, movies, large files — excluded from `home` snapshots |
| `cache` | `/var/cache` | dnf cache — excluded from root snapshots |
| `log` | `/var/log` | Logs preserved across rollbacks |
| `spool` | `/var/spool` | Spool data |
| `tmp` | `/var/tmp` | Temp files |
| `containers` | `/var/lib/containers` | Podman/container storage |
| `docker` | `/var/lib/docker` | Docker Engine (Moby) storage |
| `flatpak` | `/var/lib/flatpak` | Flatpak apps |
| `plasmalogin` | `/var/lib/plasmalogin` | KDE Plasma Login Manager |
| `libvirt` | `/var/lib/libvirt` | VM disk images |

**Subvolume tradeoffs**

| Subvolume | Why separate | Risk |
|-----------|--------------|------|
| `plasmalogin` | Stays **writable** when booting a **read-only** snapshot from GRUB (grub-btrfs) — login manager can still write session state | After a **large** `snapper rollback`, old `/usr` + current plasmalogin state can mismatch → login loop or blank screen |
| `flatpak` | Keeps large runtimes out of `root` snapshots | System rollback does **not** revert Flatpak runtimes/apps in `/var/lib/flatpak`; fix Flatpak issues with Flatpak tools, not `snapper rollback` on `/`. User app data is normally in `~/.var` on `home`, not here |

**Common steps (all variants)**

1. Create partitions and subvolumes per variant below
2. **Return to installation** → **Use configured storage**
3. Enable **LUKS** on btrfs partition(s) in the storage editor *or* [Storage configuration](#3-storage-configuration) — see [Full disk encryption](#full-disk-encryption-option-a)

**Variant: single disk (Linux-only)**

1. Initialize disk → **GPT**; create **ESP**, optional **swap**, **FEDORA** btrfs
2. Create all subvolumes on `FEDORA`

**Variant: dual boot with Windows (same disk)**

Complete [Windows dual boot prep](#windows-dual-boot--prepare-before-partitioning) first.

1. **Do not** use **Use entire disk** or reinitialize the Windows disk
2. **Share disk with other operating systems** or **Mount point assignment** after storage editor
3. Storage editor — **unallocated space only**; preserve Windows (`ntfs`) partitions
4. **Reuse existing ESP** → `/boot/efi`, **do not reformat**
5. Create **swap** *(optional)* + **FEDORA** btrfs in unallocated space; all subvolumes on `FEDORA`
6. Confirm Windows partitions show **preserve** before install

```
Disk with Windows + Fedora
├── ESP (shared)     → /boot/efi   [preserve]
├── Windows (ntfs)   [preserve]
├── swap (optional)
└── FEDORA (btrfs)   → root, home, media, log, cache, plasmalogin, …
```

**Variant: multi-disk (2–3 disks)**

Select **all** target disks under **Destination** (**Change destination** if needed).

**2 disks — home and media together**

| Disk | Contents |
|------|----------|
| **1 — system** | Shared **ESP** (dual boot) + optional **swap** + **FEDORA** btrfs with **system subvolumes only** — `root`, `cache`, `log`, `spool`, `tmp`, `containers`, `docker`, `flatpak`, `plasmalogin`, `libvirt` (**no `home` / `media`**) |
| **2 — home** | One btrfs partition: subvolumes `home` → `/home`, `media` → `/home/Media` |

**3 disks — media on separate disk**

| Disk | Contents |
|------|----------|
| **1 — system** | Same as 2-disk layout |
| **2 — home** | One btrfs partition: subvolume `home` → `/home` only |
| **3 — media** | ext4/xfs partition → `/home/Media` |

Post-install Snapper:

```bash
sudo snapper -c root create-config /
sudo snapper -c home create-config /home # Do this on home disk, if it's on a separate disk.
```

Verify mounts and encryption:

```bash
cat /etc/fstab
cat /etc/crypttab
```

**Encryption on multi-disk:** [Full disk encryption](#full-disk-encryption-option-a) covers the **system** btrfs volume. If **home on disk 2 is also LUKS-encrypted**, enable LUKS on that partition during install and complete [Encrypted `/home` on a separate disk](#encrypted-home-on-a-separate-disk) in chroot. Unencrypted home only needs a correct `/etc/fstab` entry.

#### Option A-simple — btrfs without Snapper layout

Fedora guided equivalent: separate ext4 `/boot`, only `root` + `home` subvolumes. No Snapper/rollback.

<details>
<summary>Partition tables and variants</summary>

**Partitions (single disk)**

| Name | Size | Type | Mount |
|------|------|------|-------|
| `ESP` | 600 MiB–1 GiB | EFI System | `/boot/efi` |
| `/boot` | 2 GiB | ext4 | `/boot` |
| `swap` | RAM + √RAM *(optional)* | linux-swap | — |
| remainder | rest | btrfs | `root` → `/`, `home` → `/home`, optional `media` → `/home/Media` |

**Common steps (all variants)**

1. Create partitions and subvolumes per variant below
2. **Return to installation** → **Use configured storage**
3. Enable **LUKS** if encrypting (standard separate `/boot` layout — no [FDE patch](#full-disk-encryption-option-a) needed)

**Variant: single disk (Linux-only)**

1. Initialize disk → **GPT**; create **ESP**, **`/boot`**, optional **swap**, btrfs partition
2. Subvolumes on btrfs: `root` → `/`, `home` → `/home`; optional `media` → `/home/Media`

**Variant: dual boot with Windows (same disk)**

Complete [Windows dual boot prep](#windows-dual-boot--prepare-before-partitioning) first.

1. **Do not** use **Use entire disk** or reinitialize the Windows disk
2. **Share disk with other operating systems** or **Mount point assignment** after storage editor
3. Storage editor — **unallocated space only**; preserve Windows (`ntfs`) partitions
4. **Reuse existing ESP** → `/boot/efi`, **do not reformat**
5. Create **`/boot`**, optional **swap**, and btrfs partition in unallocated space; subvolumes `root`, `home`
6. Confirm Windows partitions show **preserve** before install

**Variant: multi-disk (2–3 disks)**

Select **all** target disks under **Destination** (**Change destination** if needed).

**2 disks — home and media together**

| Disk | Contents |
|------|----------|
| **1 — system** | Shared **ESP** (dual boot) + optional **swap** + **`/boot`** ext4 + btrfs with **`root` only** (**no `home` / `media`**) |
| **2 — home** | One btrfs partition: subvolumes `home` → `/home`, `media` → `/home/Media` |

**3 disks — media on separate disk**

| Disk | Contents |
|------|----------|
| **1 — system** | Same as 2-disk layout |
| **2 — home** | One btrfs partition: subvolume `home` → `/home` only |
| **3 — media** | ext4/xfs partition → `/home/Media` |

Verify `/etc/fstab` and `/etc/crypttab` after install:

```bash
cat /etc/fstab
cat /etc/crypttab
```

For Snapper rollbacks use [Option A](#option-a--snapper-ready-btrfs-recommended) instead.

</details>

#### Option B — ext4 (legacy / compatibility)

Use when you prefer ext4 over btrfs.

<details>
<summary>Partition tables and variants</summary>

**Partitions (single disk)**

| Name | Size | Type | Mount |
|------|------|------|-------|
| `ESP` | 600 MiB–1 GiB | EFI System | `/boot/efi` |
| `/boot` | 2 GiB | ext4 | `/boot` |
| `swap` | RAM + √RAM *(optional)* | linux-swap | — |
| `/` | 50–100 GiB | ext4 | `/` |
| `/home` | remainder | ext4 | `/home` |
| `/home/Media` | *(optional)* | ext4/xfs | `/home/Media` |

**Common steps (all variants)**

1. Create partitions per variant below
2. **Return to installation** → **Use configured storage**
3. Enable **LUKS2** on `/` and `/home` (and other data partitions) if encrypting

**Variant: single disk (Linux-only)**

1. Initialize disk → **GPT**; create **ESP**, **`/boot`**, optional **swap**, **`/`**, **`/home`**
2. Optional **`/home/Media`** partition on the same disk

**Variant: dual boot with Windows (same disk)**

Complete [Windows dual boot prep](#windows-dual-boot--prepare-before-partitioning) first.

1. **Do not** use **Use entire disk** or reinitialize the Windows disk
2. **Share disk with other operating systems** or **Mount point assignment** after storage editor
3. Storage editor — **unallocated space only**; preserve Windows (`ntfs`) partitions
4. **Reuse existing ESP** → `/boot/efi`, **do not reformat**
5. Create **`/boot`**, optional **swap**, **`/`**, **`/home`** in unallocated space
6. Confirm Windows partitions show **preserve** before install

**Variant: multi-disk (2–3 disks)**

Select **all** target disks under **Destination** (**Change destination** if needed).

**2 disks — home and media together**

| Disk | Contents |
|------|----------|
| **1 — system** | Shared **ESP** (dual boot) + optional **swap** + **`/boot`** ext4 + **`/`** ext4 (**no `/home`**) |
| **2 — home** | ext4 → `/home`; optional second ext4/xfs partition → `/home/Media` on same disk |

**3 disks — media on separate disk**

| Disk | Contents |
|------|----------|
| **1 — system** | Same as 2-disk layout |
| **2 — home** | ext4 → `/home` only |
| **3 — media** | ext4/xfs → `/home/Media` |

Verify `/etc/fstab` and `/etc/crypttab` after install:

```bash
cat /etc/fstab
cat /etc/crypttab
```

</details>


## 3. Storage configuration

Skip or confirm encryption here if you already enabled **LUKS2** on the btrfs partition in the storage editor.

1. **Encrypt my data** — enable if the btrfs system partition is not yet encrypted (recommended on Linux-only installs; dual boot encrypts Fedora volumes only, not Windows)
2. If enabling encryption (here or already done in storage editor):
   - Set **passphrase** (typed with the layout active in the live session / installer — see [Live session](#live-session--before-the-installer) and step 1)
   - Choose **keyboard layout during boot** (LUKS prompt; may default to US layout)
3. Continue

## 4. Review and install

1. Review summary — language, keyboard, disk, partition layout
2. On dual boot: confirm Windows partitions show **preserve**, not **reformat**
3. **Begin installation** (button text may read **Erase data and install** on whole-disk installs)
4. Wait for completion
5. **Encrypted Option A:** complete [GRUB setup from the live ISO](#after-install--grub-setup-from-live-iso) — do **not** reboot yet
6. Reboot and remove installation media

## Full disk encryption (Option A)

For Option A with **`/boot` inside encrypted root** — ESP stays unencrypted (`/boot/efi`); GRUB must unlock LUKS before reading boot files. Fedora’s default encrypted layout uses a **separate unencrypted `/boot`**; this layout does **not**.

Enable LUKS in the storage editor or [Storage configuration](#3-storage-configuration). Dual boot: only the **Fedora btrfs partition** is encrypted.

**Boot flow**

```
UEFI → shim (ESP) → GRUB cryptomount (system LUKS only) → LUKS passphrase
     → load kernel/initramfs → initramfs unlocks system + other LUKS volumes (/etc/crypttab, e.g. /home)
     → mount / and /home → boot
```

##### Before install — Anaconda patch (live ISO)

Web UI blocks encrypted `/boot` unless you patch Anaconda on the **live ISO** first. Complete [Live session — Finnish keyboard](#finnish-keyboard) before this — you need Finnish layout for `sudo` and passphrase work in the terminal.

1. Open a terminal on the live session (**before** launching **Install to Hard Drive**)
2. Set Finnish keyboard if not already done:

   ```bash
   localectl set-keymap fi
   localectl set-x11-keymap fi
   ```

3. Become root:

   ```bash
   sudo -i
   ```

4. Find the file (Python version on the ISO may differ):

   ```bash
   find /usr/lib -path '*/pyanaconda/modules/storage/bootloader/base.py' 2>/dev/null
   ```

5. Edit that file, e.g.:

   ```bash
   nano --linenumbers /usr/lib64/python3.14/site-packages/pyanaconda/modules/storage/bootloader/base.py
   ```

6. Go to line ~184: `Ctrl+_`, enter `184`, Enter
7. Change `encryption_support = False` → `encryption_support = True`
8. Save and exit: `Ctrl+O`, Enter, then `Ctrl+X`

Rebooting the live session clears this patch — complete the install in the same session, or re-apply after reboot.

##### LUKS1 vs LUKS2

| Version | GRUB with encrypted `/boot` |
|---------|-------------------------------|
| **LUKS1** | Often works after patch + [post-install GRUB steps](#after-install--grub-setup-from-live-iso) — no extra key slot |
| **LUKS2** *(default)* | Add a **PBKDF2** key slot for GRUB (same passphrase) — Argon2id slot is not GRUB-compatible |

**PBKDF2 iterations** apply only to the **GRUB key slot** — affects passphrase delay at the GRUB prompt, not overall boot.

| Iterations | Tradeoff |
|------------|----------|
| **500000** | Stronger; ~5–15 s at GRUB prompt |
| **200000** | Recommended balance |
| **100000** | Faster GRUB unlock; weaker on that slot only |

##### After install — GRUB setup (from live ISO)

**Do not reboot** after installation completes. Stay in the live session and open a terminal.

Re-apply [Finnish keyboard](#finnish-keyboard) if you rebooted the live session since the Anaconda patch.

1. Find the **system** disk and its LUKS partition (home disk is handled separately — see below):

   ```bash
   lsblk -pd
   lsblk -p /dev/nvme0n1          # replace with your root disk
   ```

   Note the **LUKS partition** (e.g. `/dev/nvme0n1p3`) — the block device behind btrfs, not the mapper.

2. Inspect existing key slots:

   ```bash
   sudo cryptsetup luksDump /dev/nvme0n1p3
   ```

3. **LUKS2 only** — add a GRUB-compatible PBKDF2 key slot (use the **same passphrase** as during install):

   ```bash
   sudo cryptsetup luksAddKey --pbkdf pbkdf2 --pbkdf-force-iterations 200000 /dev/nvme0n1p3
   ```

4. Chroot into the installed system. Anaconda usually mounts it at `/mnt/sysroot` (some builds use `/mnt/sysimage`):

   ```bash
   ls /mnt/sysroot/etc/fedora-release /mnt/sysimage/etc/fedora-release 2>/dev/null
   sudo chroot /mnt/sysroot /bin/bash --login    # or /mnt/sysimage
   ```

5. Get the LUKS UUID (dashes removed for GRUB):

   ```bash
   lsblk -pf /dev/nvme0n1
   # UUID on the crypto_LUKS line, e.g. 563b9fda-bd6a-4c14-97a3-7317d34818ea → 563b9fdabd6a4c1497a37317d34818ea
   ```

6. Prepend to ESP GRUB config:

   ```bash
   sudo nano /boot/efi/EFI/fedora/grub.cfg
   ```

   First line:

   ```
   cryptomount -u <UUID_WITHOUT_DASHES>
   ```

   Save and exit: `Ctrl+O`, Enter, then `Ctrl+X`

7. Configure GRUB cryptodisk:

   ```bash
   sudo nano /etc/default/grub
   ```

   Add at the end:

   ```
   GRUB_ENABLE_CRYPTODISK=y
   GRUB_PRELOAD_MODULES="cryptodisk luks"
   ```

   Save and exit: `Ctrl+O`, Enter, then `Ctrl+X`

8. Regenerate GRUB config and initramfs:

   ```bash
   sudo grub2-mkconfig -o /boot/grub2/grub.cfg
   sudo dracut -vf
   ```

9. **Optional — TPM2 auto-unlock** (GRUB still prompts unless configured otherwise):

   ```bash
   sudo systemd-cryptenroll --tpm2-device=list
   sudo systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p3
   sudo systemd-cryptenroll /dev/nvme0n1p3    # list enrolled methods
   sudo dracut -vf
   ```

10. Exit chroot and reboot:

    ```bash
    exit
    sudo reboot
    ```

##### Encrypted `/home` on a separate disk

Applies to **Option A**, **A-simple**, and **Option B** multi-disk layouts when the home-disk partition is LUKS-encrypted.

GRUB **`cryptomount`** and the **PBKDF2 key slot** are only for the **system** volume (`/boot` lives there on Option A FDE). `/home` on another disk is unlocked by **initramfs** via `/etc/crypttab` — do **not** add a second GRUB `cryptomount` line for home.

**During install:** enable **LUKS** on the home-disk partition in the storage editor (in addition to the system partition).

**In chroot** (after system GRUB steps above, before final `dracut -vf`):

1. List all disks and LUKS partitions:

   ```bash
   lsblk -pf
   ```

2. Verify `/etc/crypttab` lists **every** encrypted partition:

   ```bash
   cat /etc/crypttab
   ```

   Expect one entry for the system volume and one for home (names vary). Example:

   ```
   luks-563b9fda-bd6a-4c14-97a3-7317d34818ea UUID=563b9fda-... none
   home UUID=7a2b1c0d-... none
   ```

3. If the **home entry is missing**, add it:

   ```bash
   sudo nano /etc/crypttab
   ```

   Add (use home LUKS UUID from `lsblk -pf`):

   ```
   home UUID=<HOME_LUKS_UUID> none
   ```

   Save and exit: `Ctrl+O`, Enter, then `Ctrl+X`

4. Verify `/etc/fstab` mounts `/home` from the **unlocked mapper**, not the raw LUKS partition:

   ```bash
   grep -E '[[:space:]]/home[[:space:]]' /etc/fstab
   ```

   Btrfs subvol example (device name must match the `crypttab` name):

   ```
   /dev/mapper/home /home btrfs subvol=home,defaults 0 0
   ```

   If `/home` points at `/dev/nvme1n1p1` (pre-unlock block device), fix it to use `/dev/mapper/home` or the post-unlock btrfs UUID.

5. Rebuild initramfs (one run picks up **all** `crypttab` entries — system and home):

   ```bash
   sudo dracut -vf
   ```

   **Optional TPM2** on the home partition (in addition to system):

   ```bash
   sudo systemd-cryptenroll --tpm2-device=auto /dev/nvme1n1p1   # home LUKS partition
   sudo dracut -vf
   ```

**At boot:** GRUB unlocks the system volume → initramfs may prompt for root and/or home LUKS (often the same passphrase if you used one key during install) → `/home` mounts.

If Anaconda configured both encrypted partitions correctly, steps 3–4 may already be done — still verify before first reboot.

##### After first boot — persist `cryptomount`

`./setup fedora` installs the [grub-cryptomount auto-fix](../../config/fedora/grub-cryptomount/README.md) when encrypted root with `/boot` on root is detected.

Manual test (after setup):

```bash
sudo sed -i '1{/^cryptomount/d;}' /boot/efi/EFI/fedora/grub.cfg
sleep 3
head -n 1 /boot/efi/EFI/fedora/grub.cfg    # cryptomount line should return
sudo systemctl status cryptomount-check.path
```

**Verify after reboot**

```bash
lsblk -f
sudo cryptsetup status "$(findmnt -n -o SOURCE /)"
findmnt /home    # should show /dev/mapper/... when home is on separate encrypted disk
cat /etc/crypttab
grep GRUB_ENABLE_CRYPTODISK /etc/default/grub
head -n 1 /boot/efi/EFI/fedora/grub.cfg
sudo lsinitrd /boot/initramfs-$(uname -r).img | grep -i luks
```

LUKS prompt may use **US keyboard layout** — see [First boot — LUKS passphrase](#luks-passphrase).

## First boot — Plasma Setup

Fedora KDE defers account and system settings to **Plasma Setup** on first boot (replaces the old Anaconda user/timezone steps).

Complete the wizard:

1. **Language** and **keyboard** — verify **Finnish** if needed
2. **Timezone** → **Europe/Helsinki**
3. **Network** — connect if prompted (optional for offline install)
4. **User account** — create user, strong password, **administrator** / `wheel` for `sudo`
5. Remaining privacy / welcome screens → your preference

Root has no password by default; use `sudo` for admin tasks.

### LUKS passphrase

Decrypt prompt at early boot may use **US keyboard layout**. Enter passphrase as typed during install.

Verify Finnish layout after login:

```bash
localectl status
```

Fix only if wrong:

```bash
sudo localectl set-keymap fi
sudo localectl set-x11-keymap fi pc106 winkeys
```

### Basic checks

```bash
sudo dnf upgrade --refresh -y
timedatectl status    # confirm Europe/Helsinki, NTP active
```

### Windows dual boot — verify GRUB

GRUB should list **Windows Boot Manager** and Fedora. If Windows is missing:

```bash
sudo grub2-probe --target=fs_uuid /boot/efi
# Ensure os-prober is enabled
sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo reboot
```

**Windows Feature Updates** sometimes reset the UEFI boot order to Windows-only. Fix in firmware boot menu, or:

```bash
sudo efibootmgr
# Set Fedora entry first, or use firmware "UEFI boot order"
```

Re-enable **BitLocker** in Windows after confirming both OSes boot.

### Hibernate (only if swap partition was configured)

See [Swap (optional)](#swap-optional--all-layouts). If you added a swap partition during install:

```bash
swapon --show    # confirm swap ≥ RAM + √RAM
sudo systemctl hibernate
```

For a btrfs swap file instead, see [Hibernation in Fedora Workstation](https://fedoramagazine.org/update-on-hibernation-in-fedora-workstation/).

## Post-install setup

After Plasma Setup and [basic checks](#basic-checks):

```bash
git clone https://github.com/Aapok0/linux-setup.git ~/Workspace/linux-setup
cd ~/Workspace/linux-setup
chmod u+x setup scripts/*
./setup fedora
```

`setup-fedora` upgrades the system, enables RPM Fusion, installs packages from `vars/fedora-vars` (KDE, apps, gaming, flatpaks, `fwupd`, `snapper`, …), stows dotfiles, and configures NordVPN.

On **btrfs root** it also applies btrfs mount options to `/etc/fstab` and runs Snapper setup (when root is btrfs). Toggle Snapper/grub-btrfs at the top of `scripts/setup-fedora` (`SETUP_BTRFS_SNAPPER`, `SETUP_GRUB_BTRFS`). See [config/fedora/snapper/README.md](../../config/fedora/snapper/README.md) for dnf5 hooks.

On **encrypted root with `/boot` on root** (Option A FDE), it installs the GRUB `cryptomount` auto-fix from [config/fedora/grub-cryptomount/](../../config/fedora/grub-cryptomount/README.md) (`SETUP_GRUB_CRYPTOMOUNT`). Complete the [live-ISO GRUB steps](#after-install--grub-setup-from-live-iso) before first reboot; run `./setup fedora` after Plasma Setup.

### Btrfs layout check (Option A)

```bash
sudo btrfs filesystem show /
lsblk -p
sudo btrfs subvolume list /
```

### Snapper verify (after `./setup fedora`, btrfs root)

```bash
snapper list
snapper list-configs
sudo dnf install htop -y    # should create pre/post snapshots
snapper list
```

Rollback:

```bash
sudo snapper rollback <number>
sudo reboot
```

With grub-btrfs: pick a snapshot from the GRUB menu.

#### Login broken after a large rollback

`plasmalogin` is outside `root` snapshots — a big rollback can leave old system libraries with current login-manager state.

1. Switch to a TTY: `Ctrl+Alt+F3`, log in as your user (or root)
2. Clear plasmalogin runtime state and fix SELinux labels:

```bash
sudo systemctl stop plasmalogin
sudo find /var/lib/plasmalogin -mindepth 1 -delete
sudo restorecon -RFv /var/lib/plasmalogin
sudo systemctl start plasmalogin
```

3. If still broken: boot an **older snapshot from GRUB** (grub-btrfs), roll back to a different snapshot, or roll forward:

```bash
sudo snapper rollback <number>
sudo dnf upgrade --refresh -y
```

TTY unavailable: boot a snapshot from the GRUB menu instead of the default entry.

#### Manual Snapper setup (optional)

Same steps as `setup-fedora` — use if skipping the script or re-running individually. Requires `config/fedora/snapper/` from this repo (adapted from [SysGuides sysguides-snapper-fedora](https://github.com/SysGuides/sysguides-snapper-fedora)).

The `snapper` package does **not** ship dnf5 hooks; `libdnf5-plugin-actions` runs `snapper.actions`, which calls helper scripts installed to `/usr/local/bin/` from `config/fedora/snapper/*.sh`.

<details>
<summary>Manual commands</summary>

```bash
REPO=~/Workspace/linux-setup

# Mount opts (or let setup-fedora apply: noatime,ssd,compress=zstd:1,space_cache=v2,discard=async,commit=120)
sudo cp /etc/fstab /etc/fstab.bkp
# See scripts/setup-fedora _setup_btrfs_mount_opts for full fstab update logic
sudo reboot

sudo dnf install -y snapper libdnf5-plugin-actions inotify-tools make

[ -d /.snapshots ] || sudo snapper -c root create-config /
[ -d /home/.snapshots ] || sudo snapper -c home create-config /home
sudo snapper -c root set-config ALLOW_USERS="$USER" SYNC_ACL=yes
sudo snapper -c home set-config ALLOW_USERS="$USER" SYNC_ACL=yes TIMELINE_CREATE=no
sudo restorecon -RFv /.snapshots /home/.snapshots

sudo install -m 755 "$REPO/config/fedora/snapper/"*.sh /usr/local/bin/
sudo install -m 644 "$REPO/config/fedora/snapper/snapper.actions" \
    /etc/dnf/libdnf5-plugins/actions.d/

# grub-btrfs: build from https://github.com/Antynea/grub-btrfs (see setup-fedora)

sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
```

</details>

### Drivers

RPM Fusion and most packages are installed by `./setup fedora`. If something is still missing:

```bash
lspci | grep -i vga
sudo dnf install akmod-nvidia    # NVIDIA only, if needed
```

CPU microcode: `microcode_ctl` (AMD) or `intel-microcode` (Intel).

See [README.md](../../README.md) for further post-setup steps.
