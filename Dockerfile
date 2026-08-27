FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

ARG POSTGRESQL_VERSION=18

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  curl \
  findutils \
  gnupg \
  && mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  "postgresql-client-${POSTGRESQL_VERSION}" \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 10001 pgbackup \
  && useradd \
  --uid 10001 \
  --gid pgbackup \
  --no-create-home \
  --shell /usr/sbin/nologin \
  pgbackup

RUN mkdir -p /backups /var/lib/pg-backup \
  && chown -R pgbackup:pgbackup /backups /var/lib/pg-backup

COPY scripts/pg_backup.sh /usr/local/bin/pg-backup
COPY scripts/pg_restore.sh /usr/local/bin/pg-restore
COPY scripts/entrypoint.sh /usr/local/bin/pg-backup-entrypoint
COPY scripts/healthcheck.sh /usr/local/bin/pg-backup-healthcheck
COPY scripts/lib/logging.sh /usr/local/lib/pg-backup/logging.sh

RUN chmod 0755 \
  /usr/local/bin/pg-backup \
  /usr/local/bin/pg-restore \
  /usr/local/bin/pg-backup-entrypoint \
  /usr/local/bin/pg-backup-healthcheck

ENV PGPORT=5432 \
  PG_BACKUP_LIB_DIR=/usr/local/lib/pg-backup \
  BACKUP_DIR=/backups \
  BACKUP_INTERVAL_SECONDS=3600 \
  BACKUP_RETENTION_DAYS=14 \
  BACKUP_COMPRESSION=6 \
  BACKUP_ON_START=true \
  BACKUP_ON_SHUTDOWN=true \
  PGCONNECT_TIMEOUT=10

VOLUME ["/backups"]

USER pgbackup

HEALTHCHECK \
  --interval=60s \
  --timeout=10s \
  --start-period=30s \
  --retries=3 \
  CMD ["/usr/local/bin/pg-backup-healthcheck"]

ENTRYPOINT ["/usr/local/bin/pg-backup-entrypoint"]
