#!/usr/bin/env bash
set -euo pipefail

log() { echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - $*"; }

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <backup-archive.tar.gz>"
    echo "Example: $0 ./backups/n8n-backup-20241007T120000Z.tar.gz"
    exit 1
fi

BACKUP_FILE="$1"
if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Backup file not found: $BACKUP_FILE"
    exit 2
fi

# Environment variables for restore target
POSTGRES_HOST=${POSTGRES_HOST:-postgres}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_DB=${POSTGRES_DB:-postgres}
POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-}
N8N_VOLUME_NAME=${N8N_VOLUME_NAME:-n8n_main}

# Create temporary directory for extraction
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

log "Extracting backup archive: $BACKUP_FILE"
tar -xzf "$BACKUP_FILE" -C "$TMPDIR"

# Find the SQL dump and n8n data archive
SQL_DUMP=$(find "$TMPDIR" -name "*.sql.gz" | head -1)
N8N_TAR=$(find "$TMPDIR" -name "n8n-data-*.tar.gz" | head -1)

if [ -z "$SQL_DUMP" ] || [ -z "$N8N_TAR" ]; then
    log "ERROR: Could not find SQL dump or n8n data archive in backup"
    exit 3
fi

log "Found SQL dump: $(basename "$SQL_DUMP")"
log "Found n8n data: $(basename "$N8N_TAR")"

echo ""
echo "WARNING: This will REPLACE your current n8n database and data!"
echo "Make sure you have:"
echo "1. Stopped all n8n services (docker compose stop)"
echo "2. Have a recent backup of current data"
echo ""
read -p "Continue with restore? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    log "Restore cancelled"
    exit 0
fi

# Restore database
log "Restoring database..."
export PGPASSWORD="$POSTGRES_PASSWORD"

# Drop and recreate database to ensure clean state
log "Recreating database $POSTGRES_DB"
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$POSTGRES_DB\";"
psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$POSTGRES_DB\";"

# Restore from dump
log "Importing SQL dump"
gunzip -c "$SQL_DUMP" | psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB"

log "Database restore completed"

# Restore n8n data volume
log "Restoring n8n data volume..."

# Create a temporary container to restore data to the volume
docker run --rm \
    -v "$N8N_VOLUME_NAME:/n8n" \
    -v "$TMPDIR:/restore" \
    alpine:3.19 sh -c "
        cd /n8n
        rm -rf ./* ./.[!.]* 2>/dev/null || true
        tar -xzf /restore/$(basename "$N8N_TAR") --strip-components=1
        chown -R 1000:1000 /n8n 2>/dev/null || true
    "

log "n8n data volume restore completed"

echo ""
echo "Restore completed successfully!"
echo ""
echo "Next steps:"
echo "1. Start your services: docker compose up -d"
echo "2. Check logs: docker compose logs -f n8n"
echo "3. Verify n8n is accessible at your configured port"
echo ""