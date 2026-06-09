# Fedora Snapper + dnf5 hooks

The `snapper` RPM provides the CLI, configs, and timers only — **not** these dnf5 integration scripts.

| File | Role |
|------|------|
| `snapper.actions` | Hooks for `libdnf5-plugin-actions` (pre/post `dnf` transactions) |
| `snapper-pre.sh` | Creates PRE snapshot; stores state in `/run/snapper-actions/` |
| `snapper-post.sh` | Creates POST snapshot linked to PRE; WAL checkpoint for dnf5 |
| `snapper-desc.sh` | Snapshot description from CLI vs GUI (Discover/PackageKit) |
| `snapper-gui-pkg.sh` | Records first package name for GUI transaction descriptions |
| `snapper-wal-checkpoint.sh` | Flushes libdnf5 SQLite WAL before POST snapshot |

`setup-fedora` installs `*.sh` → `/usr/local/bin/` and `snapper.actions` → `/etc/dnf/libdnf5-plugins/actions.d/`.

Shell scripts adapted from [SysGuides sysguides-snapper-fedora](https://github.com/SysGuides/sysguides-snapper-fedora) (Madhu Desai / [sysguides.com](https://sysguides.com)).
