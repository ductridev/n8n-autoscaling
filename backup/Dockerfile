FROM alpine:3.19

# Install required packages and PostgreSQL 17 client
RUN apk add --no-cache bash tar gzip ca-certificates tzdata curl && \
    # Add PostgreSQL 17 repository and install client
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache postgresql17-client && \
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
