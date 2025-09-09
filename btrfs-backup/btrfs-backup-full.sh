#!/usr/bin/env bash
set -euo pipefail

# ================== CONFIG ==================
# PGDATA on HOST (must be a Btrfs subvolume)
PGDATA="/storage/pgdata"

# Where to store snapshots (same Btrfs filesystem)
SNAP_PARENT="/storage/.snapshots"

# Keep last N full snapshots (older ones will be deleted)
KEEP_FULL=8

# Optional: load connection vars if you keep them in ~/secrets.env
# Expected vars: POSTGRES_HOST, POSTGRES_PORT, POSTGRES_USER, PGPASSWORD (optional if using .pgpass/peer)
if [[ -f "${HOME}/secrets.env" ]]; then
  # shellcheck disable=SC1090
  source "${HOME}/secrets.env"
fi

PGHOST="${POSTGRES_HOST:-localhost}"
PGPORT="${POSTGRES_PORT:-5432}"
PGUSER="${POSTGRES_USER:-postgres}"

# psql command to query replica state
PSQL=(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -At -c)
# ============================================

timestamp() { date +%Y%m%d_%H%M%S; }

echo "==> Btrfs FULL snapshot from REPLICA (pause/replay only) @ $(date -Is)"

# 0) Preconditions: ensure PGDATA is a Btrfs subvolume on a Btrfs FS
if ! findmnt -no FSTYPE --target "$PGDATA" | grep -qi btrfs; then
  echo "ERROR: $PGDATA is not on Btrfs." >&2; exit 1
fi
if ! btrfs subvolume show "$PGDATA" >/dev/null 2>&1; then
  echo "ERROR: $PGDATA is not a Btrfs subvolume." >&2; exit 1
fi
mkdir -p "$SNAP_PARENT"

# 1) Verify this node is a standby and healthy enough
echo "==> Checking replica health…"
is_standby="$("${PSQL[@]}" "SELECT pg_is_in_recovery();")"
[[ "$is_standby" = "t" ]] || { echo "ERROR: Not a standby (pg_is_in_recovery=false)."; exit 1; }

replay_lag="$("${PSQL[@]}" "SELECT now() - pg_last_xact_replay_timestamp();")"
apply_backlog_bytes="$("${PSQL[@]}" "SELECT COALESCE(pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()),0);")"
echo "    replay_lag=$replay_lag"
echo "    apply_backlog(bytes)=$apply_backlog_bytes"

# Optional warning if backlog large (>64MB)
if [[ "$apply_backlog_bytes" =~ ^[0-9]+$ ]] && (( apply_backlog_bytes > 67108864 )); then
  echo "WARNING: apply_backlog > 64MB; consider waiting until it drains." >&2
fi

# 2) Pause WAL replay briefly to reduce churn during snapshot
echo "==> Pausing WAL replay…"
"${PSQL[@]}" "SELECT pg_wal_replay_pause();" >/dev/null || true

# Always resume replay on exit, no matter what happens
resume_replay() {
  echo "==> Resuming WAL replay…"
  "${PSQL[@]}" "SELECT pg_wal_replay_resume();" >/dev/null || true
}
trap resume_replay EXIT INT TERM

# 3) Create read-only snapshot (near-instant; no fsfreeze on Btrfs)
SNAP_NAME="pgdata_full_$(timestamp)_ro"
SNAP_PATH="${SNAP_PARENT}/${SNAP_NAME}"
echo "==> Creating snapshot: $SNAP_PATH"
btrfs subvolume snapshot -r "$PGDATA" "$SNAP_PATH"

# 4) Minimal sanity check
[[ -f "$SNAP_PATH/PG_VERSION" ]] || echo "WARNING: $SNAP_PATH missing PG_VERSION (verify PGDATA path)."

echo "==> Snapshot created: $SNAP_PATH"

# 5) Retention policy: keep last N full snapshots named pgdata_full_*_ro
echo "==> Retention: keep last $KEEP_FULL full snapshots"
mapfile -t snaps < <(ls -1 "${SNAP_PARENT}"/pgdata_full_*_ro 2>/dev/null | sort)
count=${#snaps[@]}
if (( count > KEEP_FULL )); then
  to_delete=$((count - KEEP_FULL))
  echo "    Found $count snapshots, deleting $to_delete oldest…"
  for ((i=0; i<to_delete; i++)); do
    old="${snaps[$i]}"
    echo "    Deleting $old"
    btrfs subvolume delete "$old"
  done
else
  echo "    Nothing to delete ($count <= $KEEP_FULL)."
fi

# 6) Done (trap will resume replay)
trap - EXIT INT TERM
resume_replay
echo "==> DONE: $SNAP_PATH"