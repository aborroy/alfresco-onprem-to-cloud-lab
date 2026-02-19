# Stage 10 - Restore From Linux On-Prem Installation

This stage restores data from an installation created with
`alfresco-ubuntu-installer`, importing:

- PostgreSQL database dump
- `alf_data` content store
- custom repository extension/config files

Then it rebuilds search indexes from scratch in OpenSearch.

## 0) Search Backend Verification (Feb 19, 2026)

Official ACS deployment compose currently uses **Elasticsearch** (not OpenSearch):

- `elasticsearch:8.17.3`
- `alfresco-elasticsearch-live-indexing`
- `alfresco-elasticsearch-reindexing`

Source:
- https://github.com/Alfresco/acs-deployment/blob/master/docker-compose/compose.yaml

For migration from Solr in this stage, we run **OpenSearch** as the index engine
and perform a full reindex.

## 1) Create Backup on the Old Linux Server

Follow the installer backup flow from:
- https://github.com/aborroy/alfresco-ubuntu-installer/blob/main/README.md#backup-and-restore
- https://github.com/aborroy/alfresco-ubuntu-installer/blob/main/scripts/13-backup.sh

Recommended for Solr -> OpenSearch migration (skip Solr indexes):

```bash
cd /path/to/alfresco-ubuntu-installer
bash scripts/12-stop_services.sh
bash scripts/13-backup.sh --no-solr --name pre-docker-migration
```

Copy the generated backup archive (or backup directory) to a local path accessible
from this machine (it will be unpacked in the next step).

## 2) Extract and Place Backup Files

From this repository root:

```bash
cd stages/10-restore-onprem

# Example: extract full backup archive into temporary folder
tmp_dir="./import/_extracted"
mkdir -p "$tmp_dir"
tar -xzf /path/to/alfresco-backup_YYYYMMDD_HHMMSS.tar.gz -C "$tmp_dir"
```

Identify extracted folder (contains `database_*.sql`/`.dump`, `alf_data`, `config`).
Then place assets:

```bash
# Database dump (pick .dump if available, otherwise .sql)
dump_file="$(find "$tmp_dir" -type f -name 'database_*.dump' | head -1 || true)"
sql_file="$(find "$tmp_dir" -type f -name 'database_*.sql' | head -1 || true)"
[ -n "$dump_file" ] && cp "$dump_file" ./import/db/
[ -n "$sql_file" ] && cp "$sql_file" ./import/db/

# Content store
alf_data_dir="$(find "$tmp_dir" -type d -name 'alf_data' | head -1)"
rsync -a "$alf_data_dir"/ ./import/alf_data/

# Custom repository extension/config
# backup contains absolute-style paths under config/, for example:
# config/home/ubuntu/tomcat/shared/classes/alfresco/
extension_dir="$(find "$tmp_dir" -type d -path '*/config/home/ubuntu/tomcat/shared/classes/alfresco' | head -1 || true)"
[ -n "$extension_dir" ] && rsync -a "$extension_dir"/ ./import/config/alfresco-extension/
```

## 3) Start Infrastructure Services

```bash
cd stages/10-restore-onprem
set -a; source ../../.env; set +a

docker compose --env-file ../../.env -f compose.yaml up -d \
  postgres opensearch activemq shared-file-store transform-core-aio transform-router
```

## 4) Restore PostgreSQL

Drop and recreate target DB:

```bash
docker compose --env-file ../../.env -f compose.yaml exec -T postgres \
  psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$POSTGRES_DB\";"

docker compose --env-file ../../.env -f compose.yaml exec -T postgres \
  psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$POSTGRES_DB\" OWNER \"$POSTGRES_USER\";"
```

Restore from custom dump (`.dump`) if present:

```bash
dump_file="$(ls -1 ./import/db/database_*.dump 2>/dev/null | head -1)"
cat "$dump_file" | \
  docker compose --env-file ../../.env -f compose.yaml exec -T postgres \
  pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges
```

Or restore plain SQL (`.sql`):

```bash
sql_file="$(ls -1 ./import/db/database_*.sql 2>/dev/null | head -1)"
cat "$sql_file" | \
  docker compose --env-file ../../.env -f compose.yaml exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

## 5) Start Full Stage 10

```bash
docker compose --env-file ../../.env -f compose.yaml up -d
```

Notes:
- `alf_data` is mounted from `./import/alf_data`.
- repository extension config is mounted from `./import/config/alfresco-extension` to
  `/usr/local/tomcat/shared/classes/alfresco/extension`.

## 6) Reindex From Scratch in OpenSearch

Delete previous indices and run reindexing service:

```bash
# Delete Alfresco-related indexes (ignore if they do not exist yet)
docker compose --env-file ../../.env -f compose.yaml exec -T opensearch \
  curl -fsS -X DELETE "http://localhost:9200/alfresco*" || true

# Run full reindex
docker compose --env-file ../../.env -f compose.yaml up -d search-reindexing

# Follow reindex logs
docker compose --env-file ../../.env -f compose.yaml logs -f search-reindexing
```

Quick index check:

```bash
docker compose --env-file ../../.env -f compose.yaml exec -T opensearch \
  curl -fsS "http://localhost:9200/_cat/indices?v"
```

## 7) Validation

1. Open `http://localhost:${PROXY_HTTP_PORT}/share` and authenticate.
2. Confirm documents are present and preview works.
3. Search for known content from previous installation.
4. Verify no startup errors in `alfresco`, `search-live-indexing`, and `search-reindexing` logs.
