# PostgreSQL + ZFS installation instructions

These instructions are how to set up a large ZFS volume for PostgreSQL with compression.

# Assumptions

- PostgreSQL will be installed through a Docker like [TimescaleDB docker](https://hub.docker.com/r/timescale/timescaledb)

# Preface

- Get a server from Hetzner
- Set up 1 root drive (512GB) + 4x 3.8TB storage drives 
- Install using `installimage` from Hetzner rescue system
- Install Ubuntu 22.04
- Format only root drive

# Server initial set up

Setup the server for usage.

```shell
apt update && apt upgrade -y
# Get rid of knocking traffic
apt install -y fail2ban
reboot now
```

# Setting up ZFS 

Check out drives

```shell
fdisk -l
```

```
Disk /dev/nvme0n1: 894.25 GiB, 960197124096 bytes, 1875385008 sectors
Disk model: SAMSUNG MZQL2960HCJR-00A07
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 4096 bytes
I/O size (minimum/optimal): 131072 bytes / 131072 bytes
Disklabel type: dos
Disk identifier: 0x333af7fe

Device         Boot    Start        End    Sectors   Size Id Type
/dev/nvme0n1p1          2048    8390655    8388608     4G 82 Linux swap / Solaris
/dev/nvme0n1p2       8390656   10487807    2097152     1G 83 Linux
/dev/nvme0n1p3      10487808 1875382959 1864895152 889.3G 83 Linux


Disk /dev/sda: 3.49 TiB, 3840755982336 bytes, 7501476528 sectors
Disk model: SAMSUNG MZ7L33T8
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 4096 bytes
I/O size (minimum/optimal): 4096 bytes / 4096 bytes


Disk /dev/sdb: 3.49 TiB, 3840755982336 bytes, 7501476528 sectors
Disk model: SAMSUNG MZ7L33T8
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 4096 bytes
I/O size (minimum/optimal): 4096 bytes / 4096 bytes


Disk /dev/sdc: 3.49 TiB, 3840755982336 bytes, 7501476528 sectors
Disk model: SAMSUNG MZ7LH3T8
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 4096 bytes
I/O size (minimum/optimal): 4096 bytes / 4096 bytes


Disk /dev/sdd: 3.49 TiB, 3840755982336 bytes, 7501476528 sectors
Disk model: SAMSUNG MZ7L33T8
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 4096 bytes
I/O size (minimum/optimal): 4096 bytes / 4096 bytes
```

Then create a striped pool:

```shell
apt install -y zfsutils-linux
POOL_NAME=large-storage-pool
zpool create $POOL_NAME /dev/sda /dev/sdb /dev/sdc /dev/sdd
```

Check the newly created pool

```shell
zpool status
```

```
  pool: large-storage-pool
 state: ONLINE
config:

	NAME                STATE     READ WRITE CKSUM
	large-storage-pool  ONLINE       0     0     0
	  sda               ONLINE       0     0     0
	  sdb               ONLINE       0     0     0
	  sdc               ONLINE       0     0     0
	  sdd               ONLINE       0     0     0

```

Configure ZFS ([taken from here](https://bun.uptrace.dev/postgres/tuning-zfs-aws-ebs.html#basic-zfs-setup))

```shell
# same as default
zfs set recordsize=128k $POOL_NAME

# enable lz4 compression
zfs set compression=lz4 $POOL_NAME

# or zstd compression
#zfs set compression=zstd-3 $POOL_NAME

# disable access time updates
zfs set atime=off $POOL_NAME

# enable improved extended attributes
zfs set xattr=sa $POOL_NAME

# same as default
zfs set logbias=latency $POOL_NAME

# reduce amount of metadata (may improve random writes)
zfs set redundant_metadata=most $POOL_NAME
```
TODO: Add zfs_txg_timeout as a systemd service.

Then create the mount point:

```shell
zfs create $POOL_NAME/data -o mountpoint=/$POOL_NAME
```

Now you should see 14 TB volume:

```shell
df -h
```

```
tmpfs                     13G   16M   13G   1% /run
/dev/nvme0n1p3           875G  2.8G  828G   1% /
tmpfs                     63G     0   63G   0% /dev/shm
tmpfs                    5.0M     0  5.0M   0% /run/lock
/dev/nvme0n1p2           975M  248M  677M  27% /boot
tmpfs                     13G     0   13G   0% /run/user/0
large-storage-pool/data   14T  128K   14T   1% /large-storage-pool
```

# Checking the compress ratio

Check that the compression is on and what is the compress ratio:

```shell
zfs get all $POOL_NAME|grep compress
```

```
large-storage-pool  compressratio         1.22x                  -
large-storage-pool  compression           lz4                    local
large-storage-pool  refcompressratio      1.00x                  -```
```

# Sources

- [Setting up ZFS on Ubuntu]()https://ubuntu.com/tutorials/setup-zfs-storage-pool#3-creating-a-zfs-pool
- [Running PostgreSQL using ZFS and AWS EBS](https://bun.uptrace.dev/postgres/tuning-zfs-aws-ebs.html#basic-zfs-setup)
- [PostgreSQL + ZFS Best Practices and Standard Procedures](https://people.freebsd.org/~seanc/postgresql/scale15x-2017-postgresql_zfs_best_practices.pdf)
- [Everything I've seen on optimizing Postgres on ZFS](https://vadosware.io/post/everything-ive-seen-on-optimizing-postgres-on-zfs-on-linux/)
- [HackerNews discussion](https://news.ycombinator.com/item?id=29647645)
- [Setting zfs_txg_timeout on Ubuntu Linux](https://www.reddit.com/r/zfs/comments/mgibzy/comment/gsuzmxi/?utm_source=share&utm_medium=web2x&context=3)
- [Reddit discussion on txg_timeout](https://www.reddit.com/r/zfs/comments/rlfhxb/why_not_txg_timeout1/)