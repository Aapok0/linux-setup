#!/usr/bin/env bash
# Best-effort SQLite WAL checkpoint for libdnf5 RPM database before POST snapshots.
# Adapted from SysGuides sysguides-snapper-fedora (https://github.com/SysGuides/sysguides-snapper-fedora)
# by Madhu Desai / https://sysguides.com — used here with attribution.

python3 - <<'EOF'
import sqlite3
import time
import sys

DB = "/usr/lib/sysimage/rpm/rpmdb.sqlite"

for i in range(10):
    try:
        conn = sqlite3.connect(DB, timeout=3)
        conn.execute("PRAGMA busy_timeout=3000")
        result = conn.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        conn.close()
        if result and result[1] == 0:
            sys.exit(0)
    except sqlite3.OperationalError:
        pass
    time.sleep(0.5)

sys.exit(1)
EOF
