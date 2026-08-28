# postgres-backup-sidecar

A lightweight Docker sidecar for automated PostgreSQL backups and restores.

The container periodically creates PostgreSQL backups using `pg_dump`, stores them in a mounted directory, and automatically removes backups older than the configured retention period. It also provides a `pg-restore` command for restoring an existing backup.

The image includes the PostgreSQL client tools required to perform backup and restore operations.

## Usage

A project using this image can define a dedicated backup service alongside PostgreSQL:

```yaml
services:
  postgres:
    image: postgres:18
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: super-secret-password
    volumes:
      - postgres-data:/var/lib/postgresql/data

  postgres-backup:
    image: yourusername/postgres-backup-sidecar:0.1.0

    environment:
      PGHOST: postgres
      PGPORT: 5432
      PGDATABASE: myapp
      PGUSER: myapp
      PGPASSWORD: super-secret-password

      BACKUP_INTERVAL_SECONDS: 3600
      BACKUP_RETENTION_DAYS: 14
      BACKUP_COMPRESSION: 6

      BACKUP_ON_START: "true"
      BACKUP_ON_SHUTDOWN: "true"

    volumes:
      - ./backups:/backups

    depends_on:
      - postgres

    restart: unless-stopped

    stop_grace_period: 2m

volumes:
  postgres-data:
```

Backups will be written to `./backups` on the host.

Each backup is created in PostgreSQL custom format and named using the database name and a UTC timestamp, for example:

```text
myapp_20260828T090000Z.dump
```

## Configuration

The PostgreSQL connection is configured through the standard variables:

```text
PGHOST
PGPORT
PGDATABASE
PGUSER
PGPASSWORD
```

`PGHOST`, `PGDATABASE`, and `PGUSER` are required. `PGPORT` defaults to `5432`.

The backup behaviour can be configured with:

```text
BACKUP_INTERVAL_SECONDS   Default: 3600
BACKUP_RETENTION_DAYS     Default: 14
BACKUP_COMPRESSION        Default: 6
BACKUP_ON_START           Default: true
BACKUP_ON_SHUTDOWN        Default: true
```

Setting `BACKUP_RETENTION_DAYS` to `0` disables automatic deletion of old backups.

## Manual backup

A backup can also be triggered manually:

```bash
docker compose run --rm postgres-backup pg-backup
```

## Restore

To restore a backup available in the mounted `/backups` directory:

```bash
docker compose run --rm postgres-backup \
  pg-restore /backups/myapp_20260828T090000Z.dump
```

The restore operation terminates active connections to the target database, recreates the database, and restores the selected dump.

For production environments, consider providing the PostgreSQL password through `PGPASSWORD_FILE` instead of storing it directly in the Compose file.
