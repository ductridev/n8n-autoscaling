#!/usr/bin/env bash
set -euo pipefail

SLEEP_SECONDS=${SLEEP_SECONDS:-86400}

# Run one backup at start, then loop sleeping SLEEP_SECONDS (default 24h)
/usr/local/bin/backup.sh || echo "Initial backup failed at $(date -u)"

while true; do
  sleep "$SLEEP_SECONDS"
  /usr/local/bin/backup.sh || echo "Backup failed at $(date -u)"
done
