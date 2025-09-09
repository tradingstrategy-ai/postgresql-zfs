#!/usr/bin/env bash
set -euo pipefail

# ===== CONFIG =====
PGDATA="/storage/pgdata"             # Btrfs subvolume containing PGDATA
SNAP_PARENT="/storage/.snapshots"    # Snapshot directory (same FS)

# Optional: load DB connection vars
[[ -f "${HOME}/secrets.env" ]] && source "${HOME}/secrets.env"
PGHOST="${POSTGRES_HOST:-localhost}"
PGPORT="${POSTGRES_PORT:-5432}"
PGUSER="${POSTGRES_USER:-postgres}"
PSQL=(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -At -c)
# ===================

ts() { date +%Y%m%d_%H%M%S; }

echo "==> INCREMENTAL snapshot on REPLICA @ $(date -Is)"

# Preconditions
findmnt -no FSTYPE --target "$PGDATA" | grep -qi btrfs || { echo "ERROR: $PGDATA not on Btrfs"; exit 1; }
btrfs subvolume show "$PGDATA" >/dev/null 2>&1 || { echo "ERROR: $PGDATA not a Btrfs subvolume"; exit 1; }
mkdir -p "$SNAP_PARENT"

# Find latest FULL snapshot (requirement)
latest_full="$(ls -1 "${SNAP_PARENT}"/pgdata_full_*_ro 2>/dev/null | sort | tail -n1 || true)"
[[ -n "$latest_full" ]] || { echo "ERROR: No FULL snapshot found. Run btrfs_backup_full.sh first."; exit 1; }
echo "    latest FULL = $latest_full"

# Replica health
echo "==> Checking replica health…"
[[ "$("${PSQL[@]}" "SELECT pg_is_in_recovery();")" = "t" ]] || { echo "ERROR: Not a standby"; exit 1; }
replay_lag="$("${PSQL[@]}" "SELECT now() - pg_last_xact_replay_timestamp();")"
backlog="$("${PSQL[@]}" "SELECT COALESCE(pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()),0);")"
echo "    replay_lag=$replay_lag  apply_backlog(bytes)=$backlog"

# Pause replay
echo "==> Pausing WAL replay"
"${PSQL[@]}" "SELECT pg_wal_replay_pause();" >/dev/null || true
trap '"${PSQL[@]}" "SELECT pg_wal_replay_resume();" >/dev/null || true' EXIT INT TERM

# Create INCR snapshot
SNAP="${SNAP_PARENT}/pgdata_incr_$(ts)_ro"
echo "==> Creating INCREMENTAL snapshot (local RO): $SNAP"
btrfs subvolume snapshot -r "$PGDATA" "$SNAP"
[[ -f "$SNAP/PG_VERSION" ]] || echo "WARNING: $SNAP missing PG_VERSION"

# Resume replay
echo "==> Resuming WAL replay"
"${PSQL[@]}" "SELECT pg_wal_replay_resume();" >/dev/null || true
trap - EXIT INT TERM

# Retention: keep only incrementals since the latest FULL
echo "==> Cleaning old incremental snapshots (older than latest FULL)"
# Any incr with timestamp < latest_full timestamp will be removed.
full_ts="$(basename "$latest_full" | sed -E 's/^pgdata_full_([0-9]{8}_[0-9]{6})_ro$/\1/')"
mapfile -t incrs < <(ls -1 "${SNAP_PARENT}"/pgdata_incr_*_ro 2>/dev/null | sort)
for s in "${incrs[@]}"; do
  s_ts="$(basename "$s" | sed -E 's/^pgdata_incr_([0-9]{8}_[0-9]{6})_ro$/\1/')"
  [[ -z "$s_ts" || -z "$full_ts" ]] && continue
  if [[ "$s_ts" < "$full_ts" ]]; then
    echo "    deleting old incr $s (older than FULL $latest_full)"
    btrfs subvolume delete "$s"
  fi
done

echo "==> DONE INCR: $SNAP"