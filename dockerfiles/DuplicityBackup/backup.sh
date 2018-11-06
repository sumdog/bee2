#!/bin/sh

mkdir -p $BACKUP_SQL_DIR
mkdir -p $BACKUP_VOL_DIR


if [ "$VOLUME_ENABLED" = "enabled" ]; then
  echo "Backing up Docker Volumes in /backup"
  duplicity --no-encryption /backup b2://$BB_APP_ID:$BB_APP_KEY@$BB_VOL_BUCKET
else
  echo "Volume backups disabled"
fi

if [ "$DATABASE_ENABLED" = "enabled" ]; then
  echo "Backup up SQL Files"
  b2 authorize-account $BB_APP_ID $BB_APP_KEY
  /db_backup.py
else
  echo "Database backups disabled"
fi
