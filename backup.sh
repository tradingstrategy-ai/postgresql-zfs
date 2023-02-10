#!/bin/bash

source ~/secrets.env

backuptime=`date +"%Y_%m_%d"`

pg_dump \
  --compress=0 \
  --format custom \
  --create \
  --file=/large-storage-pool/dumps/$ORACLE_DATABASE.$backuptime.bin.psql \
  postgresql://postgres:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$ORACLE_DATABASE

pg_dump \
  --compress=0 \
  --format custom \
  --create \
  --file=/large-storage-pool/dumps/$BACKEND_DATABASE.$backuptime.bin.psql \
  postgresql://postgres:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$BACKEND_DATABASE

pzstd \
  -19 \
  -p 12 \
  --verbose \
  /large-storage-pool/dumps/$ORACLE_DATABASE.$backuptime.bin.psql \
  -o /large-storage-pool/dumps/$ORACLE_DATABASE.$backuptime.bin.psql.zstd


pzstd \
  -19 \
  -p 12 \
  --verbose \
  /large-storage-pool/dumps/$BACKEND_DATABASE.$backuptime.bin.psql \
  -o /large-storage-pool/dumps/$BACKEND_DATABASE.$backuptime.bin.psql.zstd

#Sync backup to backup server
rsync -avz /large-storage-pool/dumps/$ORACLE_DATABASE.$backuptime.bin.psql.zstd  $BACKUP_SERVER:/backup/oracle/
rsync -avz /large-storage-pool/dumps/$BACKEND_DATABASE.$backuptime.bin.psql.zstd  $BACKUP_SERVER:/backup/backend/

discord_url="$DISCORD_URL"

generate_post_data() {
  cat <<EOF
{
  "content": "Backup database finished at $backuptime",
  "embeds": [{
    "title": "Backup database finished at $backuptime",
    "color": "45973"
  }]
}
EOF
}


# POST request to Discord Webhook
curl -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" $discord_url
