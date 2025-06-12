# PostgreSQL (TimeScaleDB) + compressed ZFS/btrfs installation instructions

These instructions are how to set up a large ZFS volume for PostgreSQL with compression.

# Assumptions

- PostgreSQL will be installed through a Docker like [TimescaleDB docker](https://hub.docker.com/r/timescale/timescaledb)

# Preface

- Get a server from Hetzner
- Set up 1 root drive (512GB) + 4x 3.8TB storage drives 
- Assume 64 core server
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

Important bit is enabling zfs compression (assume the server is not CPU limited)

```shell
# same as default
zfs set recordsize=128k $POOL_NAME

# zstd compression
zfs set compression=zstd-3 $POOL_NAME

# disable access time updates
zfs set atime=off $POOL_NAME

# enable improved extended attributes
zfs set xattr=sa $POOL_NAME

# same as default
zfs set logbias=latency $POOL_NAME

# reduce amount of metadata (may improve random writes)
zfs set redundant_metadata=most $POOL_NAME
```

Create a service [to tune ZFS TGX timeout](https://people.freebsd.org/~seanc/postgresql/scale15x-2017-postgresql_zfs_best_practices.pdf):

```shell
cp set-zfs-txg-timeout.service /etc/systemd/system/set-zfs-txg-timeout.service
sudo systemctl enable set-zfs-txg-timeout.service
sudo service set-zfs-txg-timeout start
```

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

After the file system is online, manually test its speed and record the value so you can later detect degration in the performance:

First write down version numbers as they may accidentally change in a kernel update:

```shell
zfs version
```

```shell
dd if=/dev/zero of=/large-storage-pool/testfile bs=1k count=1000
```

```
1000+0 records in
1000+0 records out
1024000 bytes (1.0 MB, 1000 KiB) copied, 0.0206098 s, 49.7 MB/s
```

Or with `fio`:

```shell
fio --name=write_test --filename=/large-storage-pool/testfile --rw=write --bs=1M --size=1G --numjobs=1 --iodepth=1 --runtime=60 --time_based --group_reporting --ioengine=posixaio
```

Then during `fio` run in another terminal:

```shell
zpool iostat -v large-storage-pool 2
```

Another metric to confirm the IO speed is to run `scrub` command and monitor `issued at` in `zpool status`:

```
zpool status large-storage-pool
  pool: large-storage-pool
 state: ONLINE
  scan: scrub in progress since Wed Jun 11 08:53:31 2025
	1.93T scanned at 3.47G/s, 312G issued at 561M/s, 1.93T total
	0B repaired, 15.80% done, 00:50:33 to go
config:
```

# Setting up brtfs

Using Hetzner's `installimage` just choose to create `/storage` partition with all existing space and btrfs file system.

Do initial reboot, edit `/etc/fstab`, change `/storage` partition to use zstd:

```
/dev/sdX /mnt btrfs defaults,compress=zstd:3 0 2
```

Reboot again.

Check with `mount`:

```
/dev/md4 on /storage type btrfs (rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvolid=5,subvol=/)
binfmt_misc on /proc/sys/fs/binfmt_misc type binfmt_misc (rw,nosuid,nodev,noexec,relatime)
tmpfs on /run/user/0 type tmpfs (rw,nosuid,nodev,relatime,size=13182216k,nr_inodes=3295554,mode=700,inode64)
```

Test write speed:

```shell
apt update
apt install -y fio
fio --name=write_test --filename=/storage/testfile --rw=write --bs=1M --size=1G --numjobs=1 --iodepth=1 --runtime=60 --time_based --group_reporting --ioengine=posixaio
```

You should see something like:

```
  write: IOPS=1000, BW=1001MiB/s (1049MB/s)(22.0GiB/22511msec); 0 zone resets
```

# Manually mounting and unmounting the ZFS file system

Check status that all disks are connected

```shell
zpool status -v large-storage-pool
```

Unmount:

```shell
zfs umount large-storage-pool
ls -lha /large-storage-pool/
```

Mount:

```shell
zfs mount large-storage-pool/data
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

## Setting ARC cache size

ZFS is an advanced file system initially created by Sun Microsystems. ARC is an acronym for Adaptive Replacement Cache. It is a modern algorithm for caching data in DRAM. 

[It is preferred to use ARC over PSQL shared buffers cache](https://bun.uptrace.dev/postgres/tuning-zfs-aws-ebs.html#arc-and-shared-buffers) 
because ARC 1) might be more efficient 2) can cache compressed pages.

### Check ARC status

```shell
arcstat
```

Displays the current cache size (should be around ~50% of RAM):

```shell
arcstat
    time  read  miss  miss%  dmis  dm%  pmis  pm%  mmis  mm%  size     c  avail
12:37:19   124     0      0     0    0     0    0     0    0   39G   45G    53G
```

More ARC stats:

```shell
arc_summary | less
```

### Setting boot parameters

You likely do not need to do this, unless you want to hand tune the server.

ARC is a boot configuration parameter: Set up ARC by creating a modprobe config:

```shell
cp modprobe-zfs.conf /etc/modprobe.d/zfs.conf
```

Then regenerate Linux boot config.

```shell
sudo update-initramfs -u -k all
```

Then reboot

```shell
sudo reboot now
```

[See this tutorial for further information](https://www.cyberciti.biz/faq/how-to-set-up-zfs-arc-size-on-ubuntu-debian-linux/).

# Setting up PostgreSQL (TimescaleDB) using Docker

## Install Docker

[Install Docker](https://docs.docker.com/engine/install/ubuntu/)

```shell
apt install -y ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

## Setting up environment variables

Create `~/secrets.env`:

```shell
nano ~/secrets.env
```

Add:

```
# For TimescaleDB processes
export POSTGRES_PASSWORD="add password here"

# For PSQL based CLI tools
export PGPASSWORD=$POSTGRES_PASSWORD
```

## Sync compose to the server

We assume `docker-compose.yml` is copied to `/large-storage-pool/timescaledb/`

## PostgreSQL tuning options

[PostgreSQL tuning options are in docker-compose.yml](docker-compose.yml).

# Starting TimescaleDB

Test launch:

```shell
cd /large-storage-pool/timescaledb
source ~/secrets.env
docker compose up
```

A successful launch should print:

```
timescaledb-prod  | 2022-07-28 15:24:20.828 UTC [27] LOG:  TimescaleDB background worker launcher connected to shared catalogs
```

Launch for real:

```shell
docker compose up -d
```

# Testing local PSQL connection to TimescaleDB Docker

Install `psql`

```
apt install -y postgresql-client-common postgresql-client-14
```

Connect with `psql`:

```shell
# Reads password from PGPASSWORD
source ~/secrets.env
psql --host=localhost --username=postgres
````

Then display versions:

```sql
\dx
```

Should print:

```
                                      List of installed extensions
    Name     | Version |   Schema   |                            Description
-------------+---------+------------+-------------------------------------------------------------------
 plpgsql     | 1.0     | pg_catalog | PL/pgSQL procedural language
 timescaledb | 2.7.2   | public     | Enables scalable inserts and complex queries for time-series data
```

## Disable PostgresSQL's internal TOAST compression

There is no point to compress data twice.

[From PSQL manual](https://www.postgresql.org/docs/current/storage-toast.htmlhttps://www.postgresql.org/docs/current/storage-toast.html):

> Only certain data types support TOAST — there is no need to impose the overhead on data types that cannot produce large field values. To support TOAST, a data type must have a variable-length (varlena) representation, in which, ordinarily, the first four-byte word of any stored value contains the total length of the value in bytes (including itself). 

TOAST compression mostly affects columns with values spawning more than 2 kilobytes.

- JSONB
- BYTEA
- TEXT

TOAST compression can be disabled

- Per database
- For each existing column
- For not yet created columns by setting the column creation defaults

[See dba.stackexchange.com post for discussion](https://dba.stackexchange.com/questions/315063/disable-toast-compression-for-all-columns/315067#315067).

To make `EXTENDED` and `MAIN` column storage types to not compress data
run the patch against chosen database before creating any new tables:

```shell
psql --host=localhost --username=postgres < toast-patch.sql
```

After the patch check that the database was correctly updated:

```psql
SELECT typname, typstorage FROM pg_catalog.pg_type;
```

# Maintenance

Change parameters and restart

Sync new `docker-compoer.yml` to the server. Then:

```shell
source ~/secrets.env  # Get POSTGRES_PASSWORD env
# use docker compose stop for clean shutdown
docker compose stop timescaledb-zfs && docker compose up -d --force-recreate timescaledb-zfs
```

To see the real usage (uncompressed) of files:

```shell
zfs list -o name,used,logicalused,referenced,logicalreferenced,compressratio
```

This will show LUSED (Logical used) that is the size of the files if they were uncompresed:

```
NAME                      USED  LUSED     REFER  LREFER  RATIO
large-storage-pool       1.96T  6.66T       96K     42K  3.41x
large-storage-pool/data  1.96T  6.65T     1.14T   4.31T  3.41x
```

To see the disk usage of snapshots:

```shell
zfs list -r -o space
```

Gives you:

```
NAME                     AVAIL   USED  USEDSNAP  USEDDS  USEDREFRESERV  USEDCHILD
large-storage-pool       11.9T  1.96T        0B     96K             0B      1.96T
large-storage-pool/data  11.9T  1.96T      841G   1.14T             0B         0B
```

# Backup
## Create folder backup
```
mkdir -p /large-storage-pool/dump
```
## Sync backup script to the server

We assume `backup.sh` is copied to `/large-storage-pool/`

## Create crontab to backup weekly
```
crontab -e
0 0 * * 6 /large-storage-pool/backup.sh
```


# Other

Use [btop++](https://github.com/aristocratos/btop) for monitoring.

# Sources

- [Setting up ZFS on Ubuntu](https://ubuntu.com/tutorials/setup-zfs-storage-pool#3-creating-a-zfs-pool)
- [Running PostgreSQL using ZFS and AWS EBS](https://bun.uptrace.dev/postgres/tuning-zfs-aws-ebs.html#basic-zfs-setup)
- [PostgreSQL + ZFS Best Practices and Standard Procedures](https://people.freebsd.org/~seanc/postgresql/scale15x-2017-postgresql_zfs_best_practices.pdf)
- [Everything I've seen on optimizing Postgres on ZFS](https://vadosware.io/post/everything-ive-seen-on-optimizing-postgres-on-zfs-on-linux/)
- [HackerNews discussion](https://news.ycombinator.com/item?id=29647645)
- [Setting zfs_txg_timeout on Ubuntu Linux](https://www.reddit.com/r/zfs/comments/mgibzy/comment/gsuzmxi/?utm_source=share&utm_medium=web2x&context=3)
- [Reddit discussion on txg_timeout](https://www.reddit.com/r/zfs/comments/rlfhxb/why_not_txg_timeout1/)
- [ZFS lz4 vs. zstd](https://www.reddit.com/r/zfs/comments/orzpuy/zstd_vs_lz4_for_nvme_ssds/)
- [ZFS and zstd compression speeds](https://www.reddit.com/r/zfs/comments/sxx9p7/a_simple_real_world_zfs_compression_speed_an/)
- [PostgreSQL TOAST](https://www.gojek.io/blog/a-toast-from-postgresql)
