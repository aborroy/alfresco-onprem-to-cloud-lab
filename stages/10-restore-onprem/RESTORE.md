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

Prerequisites:
- `docker login quay.io` on the lab host (Alfresco enterprise images live there).
- An Enterprise `.lic` file. The on-prem installer ran in trial mode, so the
  restored DB does not carry a valid license — without one, the docker repo
  boots read-only and Step 7 fails. See Step 6 for placement.
- The admin password is **not** `admin/admin`. The
  `alfresco-ubuntu-installer` generates one and stores its MD4 hash in the DB,
  which Stage 10 inherits via the database restore. Read the cleartext from
  `<installer-dir>/config/alfresco.env` (`ALFRESCO_ADMIN_PASSWORD`) and use
  it for every `curl -u admin:...` and Share login below.

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

If the Docker lab runs on the **same machine** as the old installation, the
archive is already available locally at
`/home/ubuntu/backups/pre-docker-migration_*.tar.gz` — no copy needed.
Otherwise, copy it to the lab machine first:

```bash
scp ubuntu@<OLD_SERVER_IP>:/home/ubuntu/backups/pre-docker-migration_*.tar.gz \
  /home/ubuntu/
```

## 2) Extract and Place Backup Files

From the **lab repository root** (where you cloned `alfresco-onprem-to-cloud-lab`):

```bash
cd stages/10-restore-onprem
mkdir -p ./import/_extracted ./import/db ./import/alf_data ./import/config/alfresco-extension/keystore

# Set this to the actual archive produced in Step 1 before running
# Default location from alfresco-ubuntu-installer: /home/ubuntu/backups/
BACKUP_ARCHIVE="/home/ubuntu/backups/pre-docker-migration_YYYYMMDD_HHMMSS.tar.gz"

test -f "$BACKUP_ARCHIVE" || { echo "ERROR: backup archive not found: $BACKUP_ARCHIVE"; exit 1; }
tar -xzf "$BACKUP_ARCHIVE" -C ./import/_extracted

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

# Metadata keystore — required. The on-prem installer keeps it under
# <ALFRESCO_HOME>/keystore/metadata-keystore, NOT inside extension/, so the
# rsync above does not pick it up. Without these two files the docker repo
# fails on startup with "04310000 Keystores are invalid / Key metadata is
# missing".
keystore_dir="$(find "$backup_root/config" -type d -name metadata-keystore | head -1 || true)"
if [ -n "$keystore_dir" ]; then
  rsync -a "$keystore_dir"/ ./import/config/alfresco-extension/keystore/
else
  echo "ERROR: metadata-keystore not found in backup; restore will fail."
  exit 1
fi
```

Verify the import directories before continuing:

```bash
ls ./import/db/                                       # database_alfresco.dump and/or .sql
du -sh ./import/alf_data/                             # matches the content store size on the old server
ls ./import/config/alfresco-extension/keystore/keystore   # metadata keystore present
```

## 3) Start Infrastructure Services

Start only infrastructure services — Alfresco is excluded intentionally to
avoid it initializing against an empty or wrong database before the restore.

```bash
cd stages/10-restore-onprem
set -a; source ../../.env; set +a

docker compose --env-file ../../.env -f compose.yaml up -d \
  postgres opensearch activemq shared-file-store transform-core-aio transform-router
```

Wait until all services are healthy before proceeding to Step 4:

```bash
docker compose --env-file ../../.env -f compose.yaml ps
# all 6 services should show "healthy" or "running"
```

## 4) Restore PostgreSQL

Drop and recreate the target database (the container init script creates an
empty one on first start; this replaces it with the backup):

```bash
docker compose --env-file ../../.env -f compose.yaml exec -T postgres \
  psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$POSTGRES_DB\";"

docker compose --env-file ../../.env -f compose.yaml exec -T postgres \
  psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$POSTGRES_DB\" OWNER \"$POSTGRES_USER\";"
```

Restore from `.dump` (preferred) or `.sql`. `--no-owner --no-privileges` is
required because the backup was created by the system `postgres` user on the
old server, which does not exist in the container:

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

Verify the restore succeeded:

```bash
docker compose --env-file ../../.env -f compose.yaml exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT count(*) FROM alf_node;"
# should return a non-zero row count matching the old installation
```

## 5) Prepare Addons for Stage 10 (Required)

Populate Stage 10 addon folders and ensure `model-ns-prefix-mapping` is present
in `addons/repository/jars`. This addon is mandatory — it exposes the endpoint
used in Step 7 to generate the namespace prefix map for reindexing:

```bash
cd stages/10-restore-onprem
../../shared/fetch-addons.sh
```

Verify the required addon is present:

```bash
ls addons/repository/jars/model-ns-prefix-mapping-*.jar   # must exist
```

For exact parity with your on-prem installation, follow [ADDONS.md](./ADDONS.md)
to copy the same AMP/JAR files from the old server.

## 6) Start Full Stage 10

Place the Enterprise license file before the first start. The on-prem
installer ran in trial mode, so the restored DB has no valid license — without
this file the repo boots in read-only mode and Step 7 fails with
`04310039 Access Denied. The system is currently in read-only mode`. The
`license/` folder under the bind-mounted extension dir is loaded by Alfresco
on startup:

```bash
mkdir -p ./import/config/alfresco-extension/license
cp /path/to/alfresco.lic ./import/config/alfresco-extension/license/alfresco.lic
```

`*.lic` is git-ignored at the repo root — never commit a license.

Builds and starts all remaining services including `alfresco` and `share` with
the addons baked in. Alfresco will detect the restored database schema and skip
initialization.

```bash
docker compose --env-file ../../.env -f compose.yaml up -d
```

Mounted import paths:
- `./import/alf_data` -> `/usr/local/tomcat/alf_data`
- `./import/config/alfresco-extension` ->
  `/usr/local/tomcat/shared/classes/alfresco/extension`

Wait until Alfresco is healthy before proceeding to Step 7 (takes 2–3 min):

```bash
docker compose --env-file ../../.env -f compose.yaml logs -f alfresco
# look for: "Server startup in"
docker compose --env-file ../../.env -f compose.yaml ps alfresco
# should show: healthy
```

## 7) Generate Namespace Prefix Map (Required Before Reindex)

This step must run after Alfresco is healthy (Step 6) and before starting
`search-reindexing` (Step 8). The prefix map is mounted read-only into the
reindexing container and cannot be regenerated without restarting it.

Default proxy port in this lab is `8080` (from `.env`). Use the on-prem admin
password generated by the installer (see prerequisites at the top of this
document) — `admin/admin` will not work because the database carries the
hash from the Linux installation:

```bash
cd stages/10-restore-onprem
ADMIN_PASS="$(grep ALFRESCO_ADMIN_PASSWORD= /path/to/alfresco-ubuntu-installer/config/alfresco.env | cut -d'"' -f2)"

curl -fsS -u "admin:$ADMIN_PASS" \
  "http://localhost:8080/alfresco/s/model/ns-prefix-map" \
  > ../../shared/reindex/reindex.prefixes-file.json
```

Validate the file is non-empty:

```bash
test -s ../../shared/reindex/reindex.prefixes-file.json && echo "prefix map generated"
```

If the curl fails, check Alfresco startup and addon presence:

```bash
docker compose --env-file ../../.env -f compose.yaml logs alfresco | grep -i "startup\|error"
ls addons/repository/jars/model-ns-prefix-mapping-*.jar
```

If `model-ns-prefix-mapping` was missing, add it, rebuild Stage 10
(`docker compose ... up -d --build`), and re-run this step.

## 8) Reindex From Scratch in OpenSearch

`search-live-indexing` depends on `search-reindexing` completing successfully —
it will not start until the batch job exits cleanly. This is expected behavior.

```bash
# Delete Alfresco-related indexes (ignore if they do not exist yet)
docker compose --env-file ../../.env -f compose.yaml exec -T opensearch \
  curl -fsS -X DELETE "http://localhost:9200/alfresco*" || true

# Pre-create the `alfresco` index by issuing one search through Alfresco.
# The reindexing job's validateDbSchemaStep reads metadata from this index
# and fails with [index_not_found_exception] if it does not exist yet.
# Alfresco creates the index lazily on first ES interaction.
curl -s -u "admin:$ADMIN_PASS" -X POST \
  "http://localhost:8080/alfresco/api/-default-/public/search/versions/1/search" \
  -H "Content-Type: application/json" \
  -d '{"query":{"query":"PATH:\"/app:company_home\"","language":"afts"}}' >/dev/null

# Run full reindex
docker compose --env-file ../../.env -f compose.yaml up -d search-reindexing

# Follow reindex logs
docker compose --env-file ../../.env -f compose.yaml logs -f search-reindexing
```

Confirm reindex completed and live indexing is running:

```bash
docker compose --env-file ../../.env -f compose.yaml ps search-reindexing search-live-indexing
# search-reindexing: exited (0)   search-live-indexing: healthy/running

docker compose --env-file ../../.env -f compose.yaml exec -T opensearch \
  curl -s "http://localhost:9200/_cat/indices?v" | grep alfresco
# should show alfresco index with docs.count > 0
```

## 9) Validation

1. Open `http://localhost:8080/share` and authenticate.
2. Confirm documents are present and preview works.
3. Search for known content from previous installation.
4. Verify no startup errors in `alfresco`, `search-live-indexing`, and `search-reindexing` logs.

```bash
# Confirm restore mounts are present inside the container
docker compose --env-file ../../.env -f compose.yaml exec -T alfresco sh -c \
  'test -d /usr/local/tomcat/alf_data && test -d /usr/local/tomcat/shared/classes/alfresco/extension && echo "restore mounts present"'

# Check for startup errors
docker compose --env-file ../../.env -f compose.yaml logs alfresco | grep -i "error\|exception" | tail -20
docker compose --env-file ../../.env -f compose.yaml logs search-live-indexing | grep -i "error\|exception" | tail -20

# Confirm all services are healthy
docker compose --env-file ../../.env -f compose.yaml ps
```
