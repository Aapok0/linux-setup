# Fedora manual install guide

For installing Fedora with my personal preferences via the Anaconda Web UI installer.

Target: **Fedora 44+** amd64, **Fedora KDE Plasma Spin** ISO. The installer is a four-step linear wizard; user account, timezone, and hostname are configured on first boot via **Plasma Setup** (not in Anaconda).

## Installer flow (Fedora 44 Web UI)

| Step | Screen | What you configure |
|------|--------|-------------------|
| 1 | **Welcome** | Language, keyboard layout |
| 2 | **Installation method** | Destination disk, install method (see below) |
| 2b | **Storage editor** *(optional)* | ⋮ menu → **Launch storage editor** — manual partitioning via Cockpit Storage |
| 3 | **Storage configuration** | **Guided install only:** **Encrypt my data**, LUKS passphrase, keyboard at boot. **Manual layout (storage editor):** no encryption here — set **LUKS** when creating partitions in the storage editor |
| 4 | **Review and install** | Confirm layout, start install |

**Installation method** options (under *How would you like to install?*):

- **Share disk with other operating systems** — dual boot; uses unallocated space or reclaim dialog
- **Use entire disk** — wipe selected disk, automatic btrfs layout
- **Mount point assignment** — assign existing partitions/subvolumes to mount points (`/`, `/boot/efi`, …). **Use this after the [storage editor](#storage-editor-manual-layouts)** — there is no separate “use configured storage” option.

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
2. Assign mandatory mount points starting with **`/`** (root), then **`/boot/efi`**
   - **Option A:** no separate **`/boot`** partition — remove or leave empty the installer’s recommended **`/boot`** slot; kernels live on the `root` subvolume (`/boot` is a directory on `/`, not its own mount)
   - **Option A-simple / B / C:** assign **`/boot`** ext4 as well
3. Add optional mount points (`/home`, `/var/cache`, swap, …) as needed; set **Reformat** per [Reformat](#reformat--when-to-choose-yes-or-no)
4. Continue to [Storage configuration](#3-storage-configuration)

For btrfs + Snapper or custom layouts, use the [storage editor](#storage-editor-manual-layouts) from step 2 before continuing to step 3.

### Reformat — when to choose yes or no

The **Reformat** toggle appears when you assign a partition to a mount point in **Mount point assignment**. It means *format this partition during installation* (erase existing filesystem). The **Review and install** screen lists **preserve** vs **reformat** per partition — verify there before starting.

**Guided installs** (**Use entire disk**, **Share disk with other operating systems**) handle formatting for you; you do not pick reformat per partition. This section applies to **Mount point assignment** and to checking the review screen.

#### Always **no** reformat (preserve)

| Partition | Mount | Situation |
|-----------|-------|-----------|
| **EFI System Partition** | `/boot/efi` | **Dual boot** — must keep Windows boot files. **Linux-only** with ESP created in storage editor — already FAT32; no need to reformat |
| **Windows** | — | Any `ntfs` / BitLocker volume — never assign to a Linux mount; must show **preserve** on review |
| **Existing Linux `/home`** | `/home` | **Reinstall Fedora** — only if you intend to keep user data on that partition |

#### **No** reformat after storage editor (typical Option A / A-simple / B / C)

If you created partitions in the [storage editor](#storage-editor-manual-layouts), Cockpit already formatted them. In **Mount point assignment**, leave **Reformat** **off** for every Fedora volume:

| What you created | Mount(s) | Reformat |
|------------------|----------|----------|
| New ESP | `/boot/efi` | **No** (already FAT; dual boot must preserve) |
| New btrfs + subvolumes | `/`, `/home`, `/var/cache`, … | **No** — **yes wipes the whole btrfs partition and destroys all subvolumes** |
| New swap | *(swap)* | **No** (already `linux-swap`) |
| New ext4 `/boot` (A-simple / B / C) | `/boot` | **No** if already ext4 from storage editor |
| New ext4/xfs data disk | `/home`, `/home/Media` | **No** if already formatted in storage editor |

#### **Yes** reformat (less common)

Use **yes** only when assigning a partition that still has old data or no usable filesystem and you **want it erased**:

| Situation | Example |
|-----------|---------|
| Reusing a partition from an old install you want wiped | Old ext4 `/` from previous distro |
| Partition shows as empty / unknown type in mount point list | Leftover partition not formatted in storage editor |
| Intentional clean install on a partition that still contains files | Replacing an old Linux root, not keeping `/home` |

Do **not** use **yes** on btrfs that already has subvolumes — recreate the layout in the storage editor instead.

#### By install path

| Path | Reformat choices |
|------|------------------|
| **Use entire disk** | Anaconda formats automatically — no per-partition toggle |
| **Share disk with Windows** | Anaconda formats **new** Fedora space only; ESP and Windows **preserved** — confirm on review |
| **Mount point assignment** after storage editor | **No** for all volumes you just created (see table above) |
| **Mount point assignment** reusing old partitions | **Yes** on root (and `/boot` if separate) you want wiped; **no** on ESP (dual boot), Windows, `/home` you keep |
| **Option A** | No `/boot` mount; **no** reformat on ESP, btrfs subvolumes, swap |
| **Option A-simple / B / C** | **No** reformat on `/boot` ext4 if already formatted in storage editor; **yes** only if reusing an unformatted or old `/boot` you want recreated |

#### Review screen (step 4)

Before **Begin installation**, confirm:

- **Dual boot:** Windows partitions → **preserve**; shared ESP → **preserve** (not reformat)
- **After storage editor:** Fedora btrfs, swap, new ESP (Linux-only) → **preserve** / not set to reformat
- **Reinstall keeping `/home`:** `/home` → **preserve**; `/` (and `/boot` if used) → reformat only if you intend to wipe them

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

#### Encryption (storage editor)

With **Mount point assignment** (manual layout), **Storage configuration** does **not** offer **Encrypt my data** — enable **LUKS** here when creating each partition, **before** btrfs subvolumes.

1. When creating a partition (⋮ on free space → **Create partition**), set **Type** (`btrfs`, `ext4`, …)
2. Set **Encryption** → **LUKS2** *(or LUKS1 only if you accept GRUB tradeoffs — see [LUKS1 vs LUKS2](#luks1-vs-luks2))*
3. Enter **Passphrase** (use [Finnish keyboard](#finnish-keyboard) in the live session first)
4. Enable **Store passphrase** if offered (helps the installer unlock during setup)
5. **Create** the partition, then add btrfs **subvolumes** on the encrypted btrfs top-level (encryption wraps the whole partition, not individual subvolumes)

| Partition | Encrypt? |
|-----------|----------|
| **ESP** (`/boot/efi`) | **No** — must stay unencrypted for UEFI boot |
| **Fedora btrfs** (Option A system volume) | **Yes** for encrypted install |
| **Separate `/home` disk/partition** | **Yes** if you want encrypted `/home` ([separate disk](#encrypted-home-on-a-separate-disk)) |
| **swap** | Usually **no** (suspend with encrypted swap needs extra setup) |
| **Windows / ntfs** | **No** |

Dual boot: encrypt **Fedora partitions only**, not Windows or the shared ESP.

Option A FDE (`/boot` on btrfs `root`): apply the [Anaconda patch](#before-install--anaconda-patch-live-iso) before install, then enable LUKS on the btrfs partition in the storage editor.

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

**Subvolumes** (create under the btrfs partition via **Create subvolume** on the btrfs top-level row). For each subvolume, set **Name** and **Mount point** in the dialog (Anaconda only installs subvolumes that have a mount point):

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

1. Create partitions per variant below — enable **LUKS** on btrfs (and other data) partitions in the storage editor when creating them ([Encryption](#encryption-storage-editor)); then create subvolumes (set **Mount point** on each)
2. **Return to installation** (button in the storage editor)
3. On **Installation method** → **How would you like to install?** → **Mount point assignment**
   - **Do not** choose **Use entire disk** — that wipes the disk and replaces your layout
   - **Do not** rely on **Share disk with other operating systems** alone after a custom storage-editor layout — it uses guided reclaim, not your subvolumes
   - In **Mount point assignment**, verify every subvolume is bound: start with **`/`** on the `root` subvolume, then **`/boot/efi`** on ESP, then `/home`, `/var/cache`, `/var/log`, …
   - **Skip `/boot`:** Anaconda lists **`/boot`** as recommended — leave it **unassigned** or remove it (Option A has no `/boot` partition; do not create one to fill the slot)
   - **Reformat:** see [Reformat — when to choose yes or no](#reformat--when-to-choose-yes-or-no) — after storage editor, **no** for ESP, btrfs subvolumes, and swap
   - If Anaconda reports *no root partition defined*, assign `root` → `/` here
4. [Storage configuration](#3-storage-configuration) — skip **Encrypt my data** (not available for manual layout); continue to review. Post-install: [Full disk encryption](#full-disk-encryption-option-a) GRUB steps if using Option A FDE

**Variant: single disk (Linux-only)**

1. Initialize disk → **GPT**; create **ESP**, optional **swap**, **FEDORA** btrfs
2. Create all subvolumes on `FEDORA` (each with its mount point)

**Variant: dual boot with Windows (same disk)**

Complete [Windows dual boot prep](#windows-dual-boot--prepare-before-partitioning) first.

1. **Do not** use **Use entire disk** or reinitialize the Windows disk
2. After the storage editor → **Mount point assignment** (preserve Windows partitions; reuse ESP → `/boot/efi` without reformat)
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

1. Create partitions and subvolumes per variant below — **LUKS** in the storage editor when creating data partitions ([Encryption](#encryption-storage-editor)); set mount points on subvolumes
2. **Return to installation** → **Mount point assignment** on the installation method screen
3. [Storage configuration](#3-storage-configuration) — skip encryption (manual layout); separate `/boot` needs no [FDE patch](#full-disk-encryption-option-a)

**Variant: single disk (Linux-only)**

1. Initialize disk → **GPT**; create **ESP**, **`/boot`**, optional **swap**, btrfs partition
2. Subvolumes on btrfs: `root` → `/`, `home` → `/home`; optional `media` → `/home/Media`

**Variant: dual boot with Windows (same disk)**

Complete [Windows dual boot prep](#windows-dual-boot--prepare-before-partitioning) first.

1. **Do not** use **Use entire disk** or reinitialize the Windows disk
2. After the storage editor → **Mount point assignment**
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

1. Create partitions per variant below — enable **LUKS2** in the storage editor when creating `/`, `/home`, and other data partitions ([Encryption](#encryption-storage-editor))
2. **Return to installation** → **Mount point assignment**
3. [Storage configuration](#3-storage-configuration) — skip encryption (manual layout)

**Variant: single disk (Linux-only)**

1. Initialize disk → **GPT**; create **ESP**, **`/boot`**, optional **swap**, **`/`**, **`/home`**
2. Optional **`/home/Media`** partition on the same disk

**Variant: dual boot with Windows (same disk)**

Complete [Windows dual boot prep](#windows-dual-boot--prepare-before-partitioning) first.

1. **Do not** use **Use entire disk** or reinitialize the Windows disk
2. After the storage editor → **Mount point assignment**
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

Depends on how you partitioned in step 2.

### Guided install (**Use entire disk** or **Share disk with Windows**)

1. **Encrypt my data** — enable for encrypted install (Linux-only: whole disk; dual boot: Fedora volumes only, not Windows)
2. Set **passphrase** (see [Live session](#live-session--before-the-installer) for keyboard layout)
3. Choose **keyboard layout during boot** (LUKS prompt; may default to US layout)
4. Continue

### Manual layout (storage editor + **Mount point assignment**)

**Encrypt my data** is **not** available — you cannot enable encryption on this screen. LUKS must already be set in the [storage editor](#encryption-storage-editor) when each partition was created.

1. Continue through storage configuration (no encryption options to set)
2. Confirm encrypted partitions show as LUKS in the summary on the next screen

If you forgot encryption in the storage editor, go back to the storage editor or start the partition layout again — do not expect to add LUKS here.

## 4. Review and install

1. Review summary — language, keyboard, disk, partition layout
2. Confirm **preserve** vs **reformat** on every partition ([Reformat](#reformat--when-to-choose-yes-or-no)); dual boot: Windows and shared ESP must be **preserve**
3. **Begin installation** (button text may read **Erase data and install** on whole-disk installs)
4. Wait for completion
5. **Encrypted Option A:** complete [GRUB setup from the live ISO](#after-install--grub-setup-from-live-iso) — do **not** reboot yet
6. Reboot and remove installation media

## Full disk encryption (Option A)

For Option A with **`/boot` inside encrypted root** — ESP stays unencrypted (`/boot/efi`); GRUB must unlock LUKS before reading boot files. Fedora’s default encrypted layout uses a **separate unencrypted `/boot`**; this layout does **not**.

Enable LUKS in the [storage editor](#encryption-storage-editor) when creating the btrfs partition (**not** in [Storage configuration](#3-storage-configuration) — unavailable for manual layout). Dual boot: only the **Fedora btrfs partition** is encrypted.

**Boot flow**

```
UEFI → shim (ESP) → GRUB cryptomount (system LUKS only) → LUKS passphrase
     → load kernel/initramfs → initramfs unlocks system + other LUKS volumes (/etc/crypttab, e.g. /home)
     → mount / and /home → boot
```

**GRUB passphrase and keyboard layout**

The **first** LUKS prompt (before the GRUB menu) comes from **GRUB `cryptomount`** — not initramfs, not TPM. It defaults to **US keyboard layout**.

| Approach | Passphrase rules |
|----------|------------------|
| **US layout at GRUB prompt** *(default)* | Type as **US physical keys** on a Finnish keyboard. **Capital letters** (`A`–`Z`) work via Shift. Symbols work when typed as US keys — know US positions for `&` `+` etc. |
| **Custom GRUB keymap** *(e.g. Finnish `fi.gkb` on ESP)* | Unreliable — Shift/AltGr often fail (`unknown key`) at the cryptomount prompt. If used: **lowercase `a-z` and `0-9` only** — no capitals, no symbols |

Choose the passphrase during install with this in mind. To change it later from the **live ISO**:

```bash
sudo localectl set-keymap us    # match GRUB typing when testing
```

**Argon2id slot** (Linux / initramfs) — `luksChangeKey` is fine:

```bash
sudo cryptsetup luksChangeKey -S 0 /dev/nvme0n1p3    # adjust slot number from luksDump
```

**PBKDF2 slot** (GRUB) — **do not** use `luksChangeKey` (converts slot to argon2id and breaks GRUB). Kill and re-add:

```bash
sudo cryptsetup luksKillSlot /dev/nvme0n1p3 1         # pbkdf2 slot — adjust number
sudo cryptsetup luksAddKey --pbkdf pbkdf2 --pbkdf-force-iterations 200000 /dev/nvme0n1p3
```

Use the **same passphrase** on both slots if you want one password for GRUB and Linux.

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

3. **LUKS2 only** — add a GRUB-compatible PBKDF2 key slot (use the **same passphrase** as during install — must meet [GRUB keyboard rules](#grub-passphrase-and-keyboard-layout)):

   ```bash
   sudo cryptsetup luksAddKey --pbkdf pbkdf2 --pbkdf-force-iterations 200000 /dev/nvme0n1p3
   ```

4. Chroot into the installed system. Anaconda usually mounts it at `/mnt/sysroot` (some builds use `/mnt/sysimage`):

   ```bash
   ls /mnt/sysroot/etc/fedora-release /mnt/sysimage/etc/fedora-release 2>/dev/null
   sudo chroot /mnt/sysroot /bin/bash --login    # or /mnt/sysimage
   ```

   Inside chroot you are **root** — run `grub2-mkconfig`, `nano`, `dracut` **without** `sudo` (`sudo` inside this chroot can fail with *unable to allocate pty*).

   ```bash
   grub2-probe --target=device /
   ls /boot/grub2/grub.cfg /boot/vmlinuz-*
   ```

5. LUKS UUID for `cryptomount` (GRUB wants UUID **without** dashes). Flag is `--target=device` (equals), **not** `--target-device`.

   **Option A — `grub2-probe` + `cryptsetup`** (inside chroot):

   ```bash
   LUKS_DEVICE="$(grub2-probe --target=device /)"
   LUKS_UUID="$(cryptsetup luksUUID "$LUKS_DEVICE")"
   echo "$LUKS_DEVICE  $LUKS_UUID  (GRUB: ${LUKS_UUID//-/})"
   ```

   **Option B — `lsblk -pf`**:

   ```bash
   lsblk -pf /dev/nvme0n1    # adjust disk
   ```

   UUID from the **`crypto_LUKS`** line (e.g. `nvme0n1p3`), not ESP or btrfs. Remove dashes for GRUB:

   ```
   /dev/nvme0n1p3  ...  crypto_LUKS  ...  UUID=563b9fda-bd6a-4c14-97a3-7317d34818ea
   → cryptomount -u 563b9fdabd6a4c1497a37317d34818ea
   ```

6. Fix ESP GRUB config (`/boot/efi/EFI/fedora/grub.cfg`).

   **Read the file first** — do not blindly rewrite the `prefix` line:

   ```bash
   cat /boot/efi/EFI/fedora/grub.cfg
   ```

   Option A with btrfs subvolume `root` usually already has the **correct** prefix:

   ```text
   set prefix=($dev)/root/boot/grub2
   ```

   Here **`root` is the btrfs subvolume name**, not a mistake. **Leave this line alone** if it already looks like that.

   Only if the prefix is the short Anaconda form `set prefix=($dev)/grub2`, change it to include the subvolume:

   ```bash
   SUBVOL="$(btrfs subvolume show / | awk '/^Name:/ {print $2}')"   # usually root
   sed -i "s#(\$dev)/grub2#(\$dev)/${SUBVOL}/boot/grub2#g" /boot/efi/EFI/fedora/grub.cfg
   ```

   **Always** prepend `cryptomount` if line 1 is not already `cryptomount -u …`:

   ```bash
   # LUKS_DEVICE / LUKS_UUID from step 5
   cp -a /boot/efi/EFI/fedora/grub.cfg /boot/efi/EFI/fedora/grub.cfg.bak
   grep -q '^cryptomount -u ' /boot/efi/EFI/fedora/grub.cfg || \
       sed -i "1i cryptomount -u ${LUKS_UUID//-/}" /boot/efi/EFI/fedora/grub.cfg
   cat /boot/efi/EFI/fedora/grub.cfg
   ```

   Expected shape (UUIDs differ):

   ```
   cryptomount -u <LUKS_UUID_WITHOUT_DASHES>
   search --no-floppy --fs-uuid --set=dev <ROOT_BTRFS_FS_UUID>
   set prefix=($dev)/root/boot/grub2
   export $prefix
   configfile $prefix/grub.cfg
   ```

7. Configure GRUB cryptodisk:

   ```bash
   nano /etc/default/grub
   ```

   Add at the end if missing:

   ```
   GRUB_ENABLE_CRYPTODISK=y
   GRUB_PRELOAD_MODULES="cryptodisk luks"
   ```

8. Regenerate GRUB config and initramfs (no `sudo` — already root in chroot):

   ```bash
   grub2-mkconfig -o /boot/grub2/grub.cfg
   dracut -vf
   ```

9. **Optional — TPM2 auto-unlock** (GRUB still prompts unless configured otherwise). Use the **LUKS partition** from step 1 (e.g. `/dev/nvme0n1p3`)
   ```bash
   systemd-cryptenroll --tpm2-device=list
   systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p3
   systemd-cryptenroll /dev/nvme0n1p3
   dracut -vf
   ```

10. **Do not reboot** until all of the following pass inside chroot:

    ```bash
    test -f /boot/grub2/grub.cfg && test -n "$(ls /boot/vmlinuz-* 2>/dev/null)" || echo "MISSING KERNEL"
    head -n 1 /boot/efi/EFI/fedora/grub.cfg | grep -q '^cryptomount -u ' || echo "MISSING cryptomount"
    grep -qE 'prefix=\(\$dev\)/[^/]+/boot/grub2' /boot/efi/EFI/fedora/grub.cfg || echo "WRONG prefix — need (\$dev)/<subvol>/boot/grub2"
    cryptsetup luksDump /dev/nvme0n1p3 | grep -q pbkdf2 || echo "MISSING PBKDF2 slot for GRUB"
    ```

11. Exit chroot and reboot:

    ```bash
    exit
    sudo reboot
    ```

##### GRUB rescue (`grub>`) after reboot — recovery

A **`grub>`** prompt means GRUB started from the ESP but **failed to load `grub.cfg`**. Boot the **live USB** again. This path differs from step 4 above — you mount the system yourself:

```bash
sudo cryptsetup open /dev/nvme0n1p3 luks_root          # adjust
sudo mount -o subvol=root /dev/mapper/luks_root /mnt
sudo mount /dev/nvme0n1p1 /mnt/boot/efi
```

If `grub2-probe --target=device /` fails after chroot, add bind mounts **only then** ([recovery chroot](#recovery-chroot-bind-mounts)). Otherwise:

```bash
sudo chroot /mnt /bin/bash --login
```

Re-run [steps 3–8](#after-install--grub-setup-from-live-iso). Reboot; then `./setup fedora` for the [cryptomount auto-fix](../../config/fedora/grub-cryptomount/README.md).

<details>
<summary>Recovery chroot bind mounts (only if <code>grub2-probe</code> fails)</summary>

```bash
sudo mount --bind /dev  /mnt/dev
sudo mount --bind /proc /mnt/proc
sudo mount --bind /sys  /mnt/sys
sudo mount --bind /run /mnt/run
sudo chroot /mnt /bin/bash --login
```

</details>

**Common causes**

| Symptom / mistake | What happened |
|-------------------|---------------|
| Rebooted right after Anaconda finished | [Post-install GRUB steps](#after-install--grub-setup-from-live-iso) never run |
| Missing `cryptomount` as first line of ESP `grub.cfg` | GRUB cannot open LUKS before `configfile` |
| Changed `($dev)/root/boot/grub2` → `($dev)/boot/grub2` | Broke a correct prefix — `root` is the btrfs subvolume name |
| Prefix still `($dev)/grub2` (short form) | Needs `($dev)/root/boot/grub2` for Option A |
| LUKS2 without PBKDF2 slot | GRUB cannot unlock the volume |
| `grub2-mkconfig` / `dracut` never completed | No usable `/boot/grub2/grub.cfg` or initramfs |
| Anaconda patch not applied | Boot files may be missing or mislaid on encrypted btrfs |
| `cryptomount` UUID has dashes | Must be `cryptomount -u <uuid-without-dashes>` |

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

LUKS prompt keyboard — see [GRUB passphrase and keyboard layout](#grub-passphrase-and-keyboard-layout) and [First boot — LUKS passphrase](#luks-passphrase).

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

The **GRUB** decrypt prompt (before the kernel menu) uses **US layout** unless you added a custom keymap on the ESP — see [GRUB passphrase and keyboard layout](#grub-passphrase-and-keyboard-layout).

- **Default (US at GRUB):** enter passphrase as **US physical keys** — capitals via Shift work; symbols need US key positions
- **Custom non-US keymap at GRUB:** unreliable — use **lowercase `a-z` and `0-9` only** if you must

Initramfs prompts (if any) follow `/etc/vconsole.conf` after login setup.

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
