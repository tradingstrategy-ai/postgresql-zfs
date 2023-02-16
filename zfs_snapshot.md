# ZFS snapshot
## Update secrect file
```
export POOL_NAME=
export USER=
export BACKUP_DIRECTORY=
export BACKUP_SERVER=
```

### Create zfs snapshot 
```
sudo zfs snapshot $POOL_NAME/data@$NOW
```
### Show all of snapshot
```
sudo zfs list -t snapshot 
```
### Add permission to user can send/receive snapshot
```
zfs allow $USER compression,mountpoint,create,mount,send,receive $POOL_NAME
```

### zfs backup snapshot to another server
```
sudo zfs send -cRi $LAST_SNAPSHOT $POOL_NAME/data@$NOW" | ssh $BACKUP_SERVER sudo zfs receive -vF $BACKUP_DIRECTORY/data/data@$NOW 
```

### Restore data from zfs snapshot
```
zfs rollback $LAST_SNAPSHOT
```

### Deleted snapshot
```
zfs destroy $SNAPSHOT_NAME
```
