# Stage 10 - Restore From Linux On-Prem Installation

This stage restores data from an environment installed with
`alfresco-ubuntu-installer`:

- PostgreSQL dump from `scripts/13-backup.sh`
- `alf_data` content store
- repository extension files from backup `config/.../tomcat/shared/classes/alfresco/extension`

Then it rebuilds search indexes in OpenSearch from scratch.

Important for real migrated data:
- install repository addon `model-ns-prefix-mapping`
- generate `../../shared/reindex/reindex.prefixes-file.json` from
  `/alfresco/s/model/ns-prefix-map` before running `search-reindexing`
- addon source: https://github.com/AlfrescoLabs/model-ns-prefix-mapping

## 1) Create Backup on the Old Linux Server

Reference:
- https://github.com/aborroy/alfresco-ubuntu-installer/blob/main/README.md#backup-and-restore
- https://github.com/aborroy/alfresco-ubuntu-installer/blob/main/scripts/13-backup.sh

Recommended for Solr -> OpenSearch migration (skip Solr index backup):

```bash
cd /path/to/alfresco-ubuntu-installer
bash scripts/12-stop_services.sh
bash scripts/13-backup.sh --no-solr --name pre-docker-migration
```

`13-backup.sh` creates (compressed by default):
- backup file like `pre-docker-migration_YYYYMMDD_HHMMSS.tar.gz`
- default output directory `${ALFRESCO_HOME}/backups` (installer default
  `ALFRESCO_HOME=/home/ubuntu`)

Expected backup content:

```text
<backup_name>_<timestamp>/
  database_alfresco.dump
  database_alfresco.sql
  alf_data/
  config/
  manifest.txt
  # optional: solr/
```

Copy that backup archive (or extracted directory) to this lab machine.

## 2) Extract and Place Backup Files

From this repository root:

```bash
cd stages/10-restore-onprem
mkdir -p ./import/_extracted ./import/db ./import/alf_data ./import/config/alfresco-extension

# Example with compressed backup from installer
tar -xzf /path/to/pre-docker-migration_YYYYMMDD_HHMMSS.tar.gz -C ./import/_extracted

manifest_file="$(find ./import/_extracted -type f -name manifest.txt | head -1 || true)"
test -n "$manifest_file" || { echo "manifest.txt not found in extracted backup"; exit 1; }
backup_root="$(dirname "$manifest_file")"
echo "Using backup directory: $backup_root"
```

Copy data used by Stage 10:

```bash
# Database dumps
cp "$backup_root"/database_*.dump ./import/db/ 2>/dev/null || true
cp "$backup_root"/database_*.sql ./import/db/ 2>/dev/null || true

# Content store
rsync -a "$backup_root"/alf_data/ ./import/alf_data/

# Extension files from installer backup config tree
# Works with default /home/ubuntu and custom ALFRESCO_HOME values
extension_dir="$(find "$backup_root/config" -type d -path '*/tomcat/shared/classes/alfresco/extension' | head -1 || true)"
if [ -n "$extension_dir" ]; then
  rsync -a "$extension_dir"/ ./import/config/alfresco-extension/
else
  echo "No extension directory found in backup config (OK if source had no custom extensions)."
fi
```

## 3) Start Infrastructure Services

```bash
cd stages/10-restore-onprem
set -a; source ../../.env; set +a

docker compose --env-file ../../.env -f compose.yaml up -d \
  postgres opensearch activemq shared-file-store transform-core-aio transform-router
```

## 4) Restore PostgreSQL

Drop and recreate the target database:

```bash
docker compose --env-file ../../.env -f compose.yaml exec -T postgres \
  psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$POSTGRES_DB\";"

docker compose --env-file ../../.env -f compose.yaml exec -T postgres \
  psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$POSTGRES_DB\" OWNER \"$POSTGRES_USER\";"
```

Restore from `.dump` (preferred) or `.sql`:

```bash
dump_file="$(ls -1 ./import/db/database_*.dump 2>/dev/null | head -1 || true)"
sql_file="$(ls -1 ./import/db/database_*.sql 2>/dev/null | head -1 || true)"

if [ -n "$dump_file" ]; then
  cat "$dump_file" | docker compose --env-file ../../.env -f compose.yaml exec -T postgres \
    pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges
elif [ -n "$sql_file" ]; then
  cat "$sql_file" | docker compose --env-file ../../.env -f compose.yaml exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
else
  echo "No database_*.dump or database_*.sql found in ./import/db"
  exit 1
fi
```

## 5) Prepare Addons for Stage 10 (Required)

Populate Stage 10 addon folders and ensure `model-ns-prefix-mapping` is present
in `addons/repository/jars`:

```bash
cd stages/10-restore-onprem
../../shared/fetch-addons.sh
```

For exact parity with your on-prem installation, follow [ADDONS.md](./ADDONS.md)
to copy the same AMP/JAR files from the old server.

## 6) Start Full Stage 10

```bash
docker compose --env-file ../../.env -f compose.yaml up -d
```

Mounted import paths:
- `./import/alf_data` -> `/usr/local/tomcat/alf_data`
- `./import/config/alfresco-extension` ->
  `/usr/local/tomcat/shared/classes/alfresco/extension`

## 7) Generate Namespace Prefix Map (Required Before Reindex)

Default proxy port in this lab is `8080` (from `.env`):

```bash
cd stages/10-restore-onprem
curl -fsS "http://localhost:8080/alfresco/s/model/ns-prefix-map" \
  > ../../shared/reindex/reindex.prefixes-file.json
```

Validate the file is non-empty:

```bash
test -s ../../shared/reindex/reindex.prefixes-file.json && echo "prefix map generated"
```

If this endpoint fails, rebuild Stage 10 after installing
`model-ns-prefix-mapping` into `addons/repository/jars`.

## 8) Reindex From Scratch in OpenSearch

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

## 9) Validation

1. Open `http://localhost:8080/share` and authenticate.
2. Confirm documents are present and preview works.
3. Search for known content from previous installation.
4. Verify no startup errors in `alfresco`, `search-live-indexing`, and `search-reindexing` logs.
