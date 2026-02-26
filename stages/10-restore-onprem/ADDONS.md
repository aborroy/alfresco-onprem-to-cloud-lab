# Stage 10 Addons

This stage bakes addons into custom `alfresco` and `share` images.

It assumes your source on-prem system was installed with:
- https://github.com/aborroy/alfresco-ubuntu-installer

## 1) Important: What Backup Does Not Include

Installer backup script `scripts/13-backup.sh` includes DB/content/config, but
it does not back up addon binaries from:

- `${ALFRESCO_HOME}/amps`
- `${ALFRESCO_HOME}/amps_share`
- `${ALFRESCO_HOME}/modules/platform`
- `${ALFRESCO_HOME}/modules/share`

So for migration parity, copy or re-download addons separately.

## 2) Stage 10 Addon Folders

Place addon artifacts here before building:

- `stages/10-restore-onprem/addons/repository/amps` for repository `.amp`
- `stages/10-restore-onprem/addons/repository/jars` for repository `.jar`
- `stages/10-restore-onprem/addons/share/amps` for Share `.amp`
- `stages/10-restore-onprem/addons/share/jars` for Share `.jar`

On-prem installer path mapping (default `ALFRESCO_HOME=/home/ubuntu`):

- `${ALFRESCO_HOME}/amps/*.amp` -> `addons/repository/amps/`
- `${ALFRESCO_HOME}/modules/platform/*.jar` -> `addons/repository/jars/`
- `${ALFRESCO_HOME}/amps_share/*.amp` -> `addons/share/amps/`
- `${ALFRESCO_HOME}/modules/share/*.jar` -> `addons/share/jars/`

## 3) Option A: Copy Exact Addons from On-Prem

From this stage folder, copy artifacts exported from your Linux server:

```bash
cd stages/10-restore-onprem

# Example local copy paths after transferring files from the old server:
cp /path/from/onprem/amps/*.amp addons/repository/amps/ 2>/dev/null || true
cp /path/from/onprem/modules-platform/*.jar addons/repository/jars/ 2>/dev/null || true
cp /path/from/onprem/amps_share/*.amp addons/share/amps/ 2>/dev/null || true
cp /path/from/onprem/modules-share/*.jar addons/share/jars/ 2>/dev/null || true
```

## 4) Option B: Fetch Curated Addons Automatically

```bash
cd stages/10-restore-onprem
../../shared/fetch-addons.sh
```

Re-download all files:

```bash
cd stages/10-restore-onprem
../../shared/fetch-addons.sh --force
```

The script is best-effort. If an asset cannot be resolved from GitHub release
metadata, it prints a warning with the release URL for manual download.

The fetched list is aligned with installer `ADDONS.md` plus migration helper:

- Google Docs Integration (3.1.0)
- OOTBee Support Tools (1.2.2.0)
- Javascript Console (0.7)
- Alfresco Share Site Creators (0.0.8)
- Alfresco Share Site Space Templates (1.1.4-SNAPSHOT)
- Alfresco Share Online Edition Addon (0.3.0)
- ESign Certification Addon (1.8.4)
- Alfresco PDF Toolkit (1.4)
- Alfresco T-Engine OCR Addon
- Model NS Prefix Mapping (required for migration reindex)

## 5) Required For Real Migration Data

`model-ns-prefix-mapping` must exist in repository image
(`addons/repository/jars`). It exposes:

- https://github.com/AlfrescoLabs/model-ns-prefix-mapping
- `/alfresco/s/model/ns-prefix-map`

That endpoint is required in Stage 10 to generate:
- `../../shared/reindex/reindex.prefixes-file.json`

before running `search-reindexing`.

## 6) Build and Start Stage 10

```bash
cd stages/10-restore-onprem
docker compose --env-file ../../.env -f compose.yaml up -d --build
```
