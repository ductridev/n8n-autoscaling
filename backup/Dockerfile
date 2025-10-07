FROM alpine:3.19

# Install required packages: bash, postgresql client, tar, gzip, restic
RUN apk add --no-cache bash postgresql-client tar gzip ca-certificates tzdata curl && \
    # Install restic
    RESTIC_VERSION=0.16.4 && \
    curl -L "https://github.com/restic/restic/releases/download/v${RESTIC_VERSION}/restic_${RESTIC_VERSION}_linux_amd64.bz2" | \
    bunzip2 > /usr/local/bin/restic && \
    chmod +x /usr/local/bin/restic

WORKDIR /app

COPY entrypoint.sh /entrypoint.sh
COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/backup.sh

ENV BACKUP_DIR=/backups \
    N8N_DATA_PATH=/n8n \
    KEEP=14 \
    SLEEP_SECONDS=86400 \
    RESTIC_ENABLED=false

VOLUME ["/backups", "/n8n"]

ENTRYPOINT ["/entrypoint.sh"]
