#!/bin/bash -e
source ~/secrect.env
NOW=$(date --iso-8601=minutes | sed 's/:/-/g' | cut -c 1-10)
DELETE_OLDEST=$(date -d "$BACKUP_TIME ago" --iso-8601=minutes | sed 's/:/-/g' | cut -c 1-10)
LAST_SNAPSHOT=$(zfs list -t snapshot | tail -n1 | cut -d " " -f 1)


# Switch remote PostgreSQL to backup mode, take a ZFS snapshot, and exit from PostgreSQL backup mode

psql --host=$PGHOST --username=$PGUSER -c  "SELECT pg_start_backup('$NOW', true);"
sudo zfs snapshot $ZFS_POOL_NAME/data@$NOW
psql --host=$PGHOST --username=$PGUSER -c  "SELECT pg_stop_backup();"

# Destroy oldest snapshot on local server
sudo zfs destroy -v $ZFS_POOL_NAME/data@$DELETE_OLDEST && zfs destroy -v $ZFS_POOL_NAME/data@$DELETE_OLDEST

# Copy newly taken snapshot from remote server

sudo zfs send $LAST_SNAPSHOT | ssh $BACKUP_SERVER sudo zfs receive -vF $BACKUP_DIRECTORY/data/data@$NOW