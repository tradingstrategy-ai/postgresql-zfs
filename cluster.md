# TimescaleDB Master–Read-only Replica Cluster with ZFS Snapshots

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [I. Master Server Setup](#i-master-server-setup)
- [III. Slave Server Setup](#iii-slave-server-setup)
- [IV. Monitoring and Best Practices](#iv-monitoring-and-best-practices)
- [V. Troubleshooting & FAQ](#v-troubleshooting--faq)
- [References](#references)

---

## Overview

This guide describes how to deploy a **TimescaleDB cluster** with a primary/master and one or more read-only replicas, using traditional replication methods for initial data transfer. The steps apply TimescaleDB/PostgreSQL best practices and are suitable for very large databases (4TB+).

---

## Requirements

- **Two Linux servers** (`master` and `slave`) with:
  - ZFS (for fast snapshot and transfer)
  - Docker & Docker Compose installed
  - Open network (SSH and PostgreSQL port 5432) between servers
  - Enough storage for WAL and full data
  - Synchronized time (NTP)
- Basic knowledge of Linux, ZFS, Docker

---

## I. Master Server Setup

### 1. Prepare Directories

```bash
mkdir -p $PWD/data $PWD/logs $PWD/wal_archive
```

### 2. `docker-compose.yaml` for Master

```yaml
services:
  timescaledb-zfs:
    container_name: timescaledb-zfs
    image: timescale/timescaledb:2.19.1-pg14

    network_mode: host
    shm_size: 1g

    command:
      - -ctimescaledb.max_background_workers=128
      - -cmax_parallel_workers=128
      - -cmax_worker_processes=256
      - -cmax_connections=3072  
      - -cmax_wal_size=4GB
      - -cmax_pred_locks_per_transaction=4096
      - -cstatement_timeout=180min
      - -cidle_in_transaction_session_timeout=3600000
      - -cfull_page_writes=off
      - -csynchronous_commit=off
      - -cshared_buffers=32GB
      # Enable stat_statements
      - -cshared_preload_libraries=timescaledb,pg_stat_statements
      - -ctrack_activity_query_size=4096
      - -ctrack_io_timing=on
      - -cpg_stat_statements.track=all
      - -cpg_stat_statements.max=10000
      # --- Replication & WAL for ZFS snapshot ---
      - -cwal_level=replica
      - -cmax_wal_senders=10
      - -cwal_keep_size=32GB     
      - -chot_standby=on
      - -carchive_mode=on
      - -carchive_command=cp %p /var/lib/postgresql/wal_archive/%f

    environment:
      POSTGRES_USER: postgres
      POSTGRES_DB: dex_ohlcv
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"

    ports:
      - "5432:5432"
    volumes:
      - $PWD/data/:/var/lib/postgresql/data
      - $PWD/logs/:/var/log/timescaledb
      - $PWD/wal_archive/:/var/lib/postgresql/wal_archive 
```

### 3. Start TimescaleDB Master

```bash
docker-compose up -d timescaledb-master
```

### 4. Create Replication User

```bash
docker exec -it timescaledb-master psql -U postgres
```
```sql
CREATE USER repl_user REPLICATION LOGIN ENCRYPTED PASSWORD 'yourStrongPass';
```

### 5. Edit `pg_hba.conf` to Allow Slave Replication

- Find or mount `$PWD/data/pg_hba.conf`
- Add:
  ```
  host    replication    repl_user    <SLAVE_IP>/32   md5
  ```
- Reload config:
  ```bash
  docker exec timescaledb-master pg_ctl reload
  ```

### 6. Ensure WAL Archive

```bash
ls $PWD/wal_archive/
```
You should see files like `0000000100000001000000A2`...

---

## III. Slave Server Setup

### 1. Prepare Directories

```bash
mkdir -p $PWD/data $PWD/logs
```

### 2. Initialize Slave Data Directory

- Use traditional backup/restore or base backup methods to initialize slave data directory, e.g., via `pg_basebackup` or restoring from backup.

### 3. Create `standby.signal`

```bash
touch $PWD/data/standby.signal
```

### 4. Create/Edit `postgresql.auto.conf`

```bash
echo "primary_conninfo = 'host=<MASTER_IP> port=5432 user=repl_user password=yourStrongPass'" > $PWD/data/postgresql.auto.conf
```
*Replace `<MASTER_IP>`, `repl_user`, and password appropriately.*

### 5. `docker-compose.yaml` for Slave

```yaml
version: "3.8"

services:
  timescaledb-slave:
    container_name: timescaledb-slave
    image: timescale/timescaledb:2.19.1-pg14

    network_mode: host
    shm_size: 1g

    command:
      - -ctimescaledb.max_background_workers=128
      - -cmax_parallel_workers=128
      - -cmax_worker_processes=256
      - -cmax_connections=3072  
      - -cmax_wal_size=4GB
      - -cmax_pred_locks_per_transaction=4096
      - -cstatement_timeout=180min
      - -cidle_in_transaction_session_timeout=3600000
      - -cfull_page_writes=off
      - -csynchronous_commit=off
      - -cshared_buffers=32GB
      # Enable stat_statements
      - -cshared_preload_libraries=timescaledb,pg_stat_statements
      - -ctrack_activity_query_size=4096
      - -ctrack_io_timing=on
      - -cpg_stat_statements.track=all
      - -cpg_stat_statements.max=10000
      # --- Replication/Read-only ---
      - -chot_standby=on                    
      - -cdefault_transaction_read_only=on  

    environment:
      POSTGRES_USER: postgres
      POSTGRES_DB: dex_ohlcv
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"

    ports:
      - "5432:5432"
    volumes:
      - $PWD/data/:/var/lib/postgresql/data
      - $PWD/logs/:/var/log/timescaledb
```

### 6. Start TimescaleDB Slave

```bash
docker-compose up -d timescaledb-slave
```

---

## IV. Monitoring and Best Practices

### 1. Validate Replication

**On master:**
```sql
SELECT * FROM pg_stat_replication;
```
You will get something like:
| pid    | usesysid | usename | application_name | client_addr    | client_hostname | client_port | backend_start               | backend_xmin | state     | sent_lsn      | write_lsn     | flush_lsn     | replay_lsn    | write_lag         | flush_lag         | replay_lag        | sync_priority | sync_state | reply_time                   |
|--------|----------|---------|------------------|---------------|-----------------|-------------|-----------------------------|--------------|-----------|---------------|---------------|---------------|---------------|--------------------|--------------------|--------------------|---------------|------------|------------------------------|
| 582913 |  4920001 | standby | walreceiver      | 10.0.1.45     | standby01.local | 54321       | 2025-05-01 08:00:00.00000+00|      2000034 | streaming | 70A2/340BCD22  | 70A2/340BCD22 | 70A2/340BCD22 | 70A2/340BCD22 | 00:00:00.000321   | 00:00:00.000658   | 00:00:00.000734   |             1 | sync       | 2025-05-01 09:01:12.34567+00 |

**On slave:**
```sql
SELECT * FROM pg_stat_wal_receiver;
```
You will get something like:
| pid  |  status   | receive_start_lsn | receive_start_tli |  written_lsn   |  flushed_lsn   | received_tli |      last_msg_send_time      |     last_msg_receipt_time    | latest_end_lsn  |       latest_end_time        | slot_name |  sender_host    | sender_port | conninfo                                                                                                                                                                                                                                        |
|------|-----------|-------------------|-------------------|----------------|----------------|--------------|-----------------------------|------------------------------|------------------|------------------------------|-----------|------------------|-------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 3412 | streaming | 71CF/4D000000     |         2         | 71FA/4D8AB123  | 71FA/4D8AB123  |     2        | 2025-05-01 10:21:45.998123+00 | 2025-05-01 10:21:45.997654+00 | 71FA/4D8AB123   | 2025-05-01 10:21:45.998123+00 | standby1  | 10.0.1.100       |     5432    | user=replica password=******** channel_binding=prefer dbname=replication host=10.0.1.100 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=postgres target_session_attrs=any |

### 2. Test Read-only Behavior

- `SELECT` queries should work on slave.
- Any `INSERT/UPDATE/DELETE` should fail with "read-only transaction" error.

### 3. Storage & WAL Management

- Monitor `$PWD/wal_archive` disk usage.
- Regularly remove old WALs once replicas are caught up.

### 4. Monitoring

- Set up replication lag and WAL usage alerts.
- Use tools like Prometheus, Datadog, etc.

### 5. Production Hardening

- Limit replication access in `pg_hba.conf` by IP.
- Sync system time with NTP.
- Test failover & restore procedures.
- Document and automate steps where possible.

---

## V. Troubleshooting & FAQ

### Q: Replica is lagging or needs rebuild?
- Take a fresh base backup from master and repeat the slave setup process.
- Ensure WAL retention is set high enough (`wal_keep_size`, WAL archiving).

### Q: Can I use env vars in `postgresql.auto.conf`?
- Not directly; use a script to generate this file using env variables before starting the container.

### Q: Can I add more read replicas?
- Yes. Take new base backups from master and repeat the slave setup for each.

### Q: Can I promote a slave to master?
- Yes, follow TimescaleDB/Postgres documentation for promotion and updating application connections.

### Q: How to automate the `postgresql.auto.conf`?
```bash
echo "primary_conninfo = 'host=${MASTER_IP} port=5432 user=${REPL_USER} password=${REPL_PASS}'" > $PWD/data/postgresql.auto.conf
```
Add this to your setup/CI scripts.

---

## References

- [TimescaleDB Replication Best Practices](https://www.timescale.com/learn/best-practices-for-postgres-database-replication)
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html)
- [Docker + ZFS documentation](https://docs.docker.com/storage/storagedriver/zfs-driver/)
- [TimescaleDB Documentation](https://docs.timescale.com/)

---
