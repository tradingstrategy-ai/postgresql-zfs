# ZFS snapshot
## Update secrect file
```
export PGHOST=
export PGUSER=
export ZFS_POOL_NAME=
export BACKUP_USER=
export BACKUP_DIRECTORY=
export BACKUP_SERVER=
exoirt BACKUP_TIME=
```

## Create ssh config file 
`vim ~/.ssh/config`
```
Host BACKUP_SERVER
    HostName BACKUP_SERVER_IPADDRESS
    User BACKUP_USER
    IdentityFile  ~/.ssh/BACKUP_USER_PRIVATE_KEY
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
sudo zfs send -cRi $LAST_SNAPSHOT $ZFS_POOL_NAME/data@$NOW" | ssh $BACKUP_SERVER sudo zfs receive -vF $BACKUP_DIRECTORY/data/data@$NOW 
```

### Restore data from zfs snapshot
```
zfs rollback $LAST_SNAPSHOT
```

### Deleted snapshot
```
zfs destroy $SNAPSHOT_NAME
```
