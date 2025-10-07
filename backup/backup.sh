#!/usr/bin/env bash
set -euo pipefail

log(){ echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - $*"; }

# Configurable via environment
BACKUP_DIR=${BACKUP_DIR:-/backups}
N8N_DATA_PATH=${N8N_DATA_PATH:-/n8n}    # should point to the mounted n8n data volume (e.g. /n8n)
POSTGRES_HOST=${POSTGRES_HOST:-postgres}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_DB=${POSTGRES_DB:-postgres}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-}
KEEP=${KEEP:-14}

# Optional restic configuration
RESTIC_ENABLED=${RESTIC_ENABLED:-false}
RESTIC_REPOSITORY=${RESTIC_REPOSITORY:-}
RESTIC_PASSWORD=${RESTIC_PASSWORD:-}
RESTIC_RETENTION_DAILY=${RESTIC_RETENTION_DAILY:-14}
RESTIC_RETENTION_WEEKLY=${RESTIC_RETENTION_WEEKLY:-8}
RESTIC_RETENTION_MONTHLY=${RESTIC_RETENTION_MONTHLY:-6}
RESTIC_RETENTION_YEARLY=${RESTIC_RETENTION_YEARLY:-2}

# Ensure backup dir exists
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
TMPDIR="$BACKUP_DIR/.tmp-$TIMESTAMP"
mkdir -p "$TMPDIR"

log "Starting backup: $TIMESTAMP"

# 1) Dump Postgres DB to gzipped SQL
export PGPASSWORD="${POSTGRES_PASSWORD}"
DB_DUMP_FILE="$TMPDIR/${POSTGRES_DB// /_}-$TIMESTAMP.sql.gz"

log "Running pg_dump against ${POSTGRES_HOST}:${POSTGRES_PORT} database ${POSTGRES_DB}"
if ! pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip > "$DB_DUMP_FILE"; then
  log "ERROR: pg_dump failed"
  rm -rf "$TMPDIR"
  exit 2
fi

log "Database dump written: $DB_DUMP_FILE"

# 2) Archive n8n data directory
N8N_BASENAME="$(basename "$N8N_DATA_PATH")"
N8N_PARENT="$(dirname "$N8N_DATA_PATH")"
N8N_TAR_FILE="$TMPDIR/n8n-data-$TIMESTAMP.tar.gz"

log "Archiving n8n data from $N8N_DATA_PATH"
if ! tar -C "$N8N_PARENT" -czf "$N8N_TAR_FILE" "$N8N_BASENAME"; then
  log "ERROR: tar of n8n data failed"
  rm -rf "$TMPDIR"
  exit 3
fi

log "n8n data archive written: $N8N_TAR_FILE"

# 3) Create a single archive containing both artifacts
FINAL_FILE="$BACKUP_DIR/n8n-backup-$TIMESTAMP.tar.gz"
log "Creating final archive: $FINAL_FILE"
if ! tar -C "$TMPDIR" -czf "$FINAL_FILE" .; then
  log "ERROR: failed to create final archive"
  rm -rf "$TMPDIR"
  exit 4
fi

# Cleanup tmp
rm -rf "$TMPDIR"
log "Backup created: $FINAL_FILE"

# 5) Optional: Upload to restic repository
if [ "$RESTIC_ENABLED" = "true" ] && [ -n "$RESTIC_REPOSITORY" ] && [ -n "$RESTIC_PASSWORD" ]; then
  log "Uploading to restic repository: $RESTIC_REPOSITORY"
  
  # Export restic environment
  export RESTIC_REPOSITORY="$RESTIC_REPOSITORY"
  export RESTIC_PASSWORD="$RESTIC_PASSWORD"
  
  # Initialize repository if it doesn't exist (will fail silently if it exists)
  restic init 2>/dev/null || true
  
  # Backup the final archive
  if restic backup "$FINAL_FILE" --tag "n8n-backup" --tag "$(date -u +%Y-%m-%d)"; then
    log "Successfully uploaded to restic repository"
    
    # Apply retention policy
    log "Applying restic retention policy"
    restic forget \
      --keep-daily "$RESTIC_RETENTION_DAILY" \
      --keep-weekly "$RESTIC_RETENTION_WEEKLY" \
      --keep-monthly "$RESTIC_RETENTION_MONTHLY" \
      --keep-yearly "$RESTIC_RETENTION_YEARLY" \
      --tag "n8n-backup" \
      --prune
    
    log "Restic retention policy applied"
  else
    log "ERROR: Failed to upload to restic repository"
  fi
else
  log "Restic upload disabled or not configured"
fi

# 6) Rotation: keep latest $KEEP backups, delete older ones
log "Pruning old backups, keeping latest $KEEP files"
# shellcheck disable=SC2012
files=( $(ls -1t "$BACKUP_DIR"/n8n-backup-*.tar.gz 2>/dev/null || true) )
if [ ${#files[@]} -gt "$KEEP" ]; then
  # remove files after the first $KEEP
  to_remove=( "${files[@]:$KEEP}" )
  for f in "${to_remove[@]}"; do
    log "Removing old backup: $f"
    rm -f -- "$f"
  done
fi

log "Backup run completed"
exit 0
