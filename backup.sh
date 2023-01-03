#!/bin/bash

source ~/secrets.env

backuptime=`date +"%Y_%m_%d"`

# REMOVE ALL OLD BACKUP
rm -f /large-storage-pool/dumps/*

pg_dump \
  --compress=0 \
  --format custom \
  --create \
  --file=/large-storage-pool/dumps/$ORACLE_DATABASE.$backuptime.bin.psql \
  postgresql://postgres:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$ORACLE_DATABASE


pzstd \
  -19 \
  --verbose \
  /large-storage-pool/dumps/$ORACLE_DATABASE.$backuptime.bin.psql \
  -o /large-storage-pool/dumps/$ORACLE_DATABASE.$backuptime.bin.psql.zstd


rsync -avz /large-storage-pool/dumps/$ORACLE_DATABASE.$backuptime.bin.psql.zstd  $BACKUP_SERVER:/backup/


discord_url="$DISCORD_URL"

generate_post_data() {
  cat <<EOF
{
  "embeds": [{
    "title": "Backup database finished at  $backuptime",
    "color": "45973"
  }]
}
EOF
}


# POST request to Discord Webhook
curl -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" $discord_url