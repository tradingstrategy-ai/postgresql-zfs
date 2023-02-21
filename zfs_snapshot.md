# ZFS snapshot
## Update secrect file
```
export PGHOST=
export PGUSER=
export ZFS_POOL_NAME=
export BACKUP_USER=
export BACKUP_DIRECTORY=
export BACKUP_SERVER=
export BACKUP_TIME=
export BACKUP_SSH_KEY=
```

### Create zfs snapshot 
```
sudo zfs snapshot $ZFS_POOL_NAME/data@$NOW
```
### Show all of snapshot
```
sudo zfs list -t snapshot 
```
### Add permission to user of server can send/receive snapshot
Database server: If you are root user please skip this command
```
zfs allow $BACKUP_USER compression,mountpoint,create,mount,send,receive $ZFS_POOL_NAME
```
Backup server
```
zfs allow $BACKUP_USER compression,mountpoint,create,mount,send,receive $BACKUP_DIRECTORY
```

### zfs backup snapshot to another server
```
sudo zfs send $LAST_SNAPSHOT | ssh -i $BACKUP_SSH_KEY  $BACKUP_USER@$BACKUP_SERVER  sudo zfs receive -vF $BACKUP_DIRECTORY/data/$NOW
```

### Restore data from zfs snapshot
```
zfs rollback $LAST_SNAPSHOT
```

### Deleted snapshot
```
zfs destroy $SNAPSHOT_NAME
```
