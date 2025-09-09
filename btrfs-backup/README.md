# PostgreSQL Backup with Btrfs Snapshots

This repository provides two shell scripts to manage PostgreSQL backups using **Btrfs snapshots** on a replica server:

- `btrfs_snapshot.sh` – creates **weekly incremental** and **monthly full** snapshots of the PostgreSQL data directory.  
- `btrfs_send_snapshots.sh` – transfers snapshots to a **remote backup server** using `btrfs send` / `btrfs receive` (full + incremental).  

This approach avoids stopping the master PostgreSQL instance and leverages the replica for backup safety.

---

## 1. Requirements

- **PostgreSQL streaming replication** already configured (master → replica).
- The **replica PostgreSQL data directory** must reside on a **Btrfs filesystem**.  
- Tools required:
  - `btrfs-progs`
  - `psql` (PostgreSQL client)
  - `ssh` (with key-based authentication to backup server)
  - `zstd` (optional, for stream compression)
- Ensure replication lag is small (`replay_lag ~ 0s`) before snapshotting.

---

## 2. Scripts Overview

### 📌 `btrfs_snapshot.sh`

- Creates snapshots under `LOCAL_SNAP_DIR` (default `/storage/.snapshots`).
- Types:
  - **Weekly incremental** → `pgdata_incr_<timestamp>_ro`
  - **Monthly full** → `pgdata_full_<timestamp>_ro`
- Retention:
  - When a new **full** is created, old full + older incrementals are removed.
  - Only incrementals after the latest full are kept.

Usage:
```bash
# Weekly incremental snapshot
./btrfs_snapshot.sh weekly

# Monthly full snapshot
./btrfs_snapshot.sh monthly
```

---

### 📌 `btrfs_send_snapshots.sh`

- Transfers snapshots from replica → backup server.  
- Steps:
  1. Send latest **full** if not present remotely.  
  2. Send all **incrementals** after that full (in order).  
  3. Skips snapshots already existing at remote.  

Features:
- **Compression** with zstd (`USE_ZSTD=1`) to save bandwidth.  
- **Dry-run mode** (`DRY_RUN=1`) shows plan without sending.  
- Works idempotently – safe to run multiple times.  

Usage:
```bash
# Simulate transfer (dry-run)
DRY_RUN=1 ./btrfs_send_snapshots.sh

# Real transfer
./btrfs_send_snapshots.sh
```

---

## 3. Example Cron Jobs

- **Weekly incremental** snapshot (every Sunday at 02:00):
```cron
0 2 * * 0 /root/btrfs_snapshot.sh weekly >> /var/log/pg_snapshots.log 2>&1
```

- **Monthly full** snapshot (1st day of month at 02:00):
```cron
0 2 1 * * /root/btrfs_snapshot.sh monthly >> /var/log/pg_snapshots.log 2>&1
```

- **Send snapshots** to backup server (after snapshots are created):
```cron
0 3 * * 0 /root/btrfs_send_snapshots.sh >> /var/log/pg_send.log 2>&1
```

---

## 4. Recovery Workflow

1. On the backup server, rollback or mount a snapshot:
   ```bash
   btrfs subvolume snapshot /backup/.snapshots/pgdata_full_20250901_ro /backup/restore_pgdata
   ```
2. Start PostgreSQL with the restored `PGDATA`.
3. Point applications or standby to the restored instance.

---

## 5. Notes & Limitations

- **Snapshots are crash-consistent**. Since they are taken on a replica in recovery, PostgreSQL will perform crash recovery at startup if restored.  
- **WAL retention**: only the snapshots + incrementals after the last full are kept; make sure your restore plan matches this.  
- **Stream interruptions**: `btrfs send` does not support resume. Consider running through `tmux` or `mbuffer` for long transfers.  
- **Compression trade-off**: `zstd` saves bandwidth but increases CPU usage.

---

## 6. Example Folder Layout

Local (`/storage/.snapshots`):
```
pgdata_full_20250901_ro
pgdata_incr_20250908_ro
pgdata_incr_20250915_ro
```

Remote (`/backup/.snapshots` after sync):
```
pgdata_full_20250901_ro
pgdata_incr_20250908_ro
pgdata_incr_20250915_ro
```

---

## 7. License

MIT License. Use at your own risk. Test recovery procedures regularly.
