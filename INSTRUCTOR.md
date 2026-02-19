# INSTRUCTOR GUIDE
## Class 4 - Alfresco On-prem to Cloud-Ready

Student-facing instructions are in `README.md`.

## 1) Session Plan

Recommended timeline:

1. Baseline capture and extension readiness discussion - 30 min
2. Incremental Compose build (Stages 01-06) - 120 min
3. Search migration deep-dive (Stage 02 Solr -> Stage 03 OpenSearch) - 30 min
4. Transform architecture migration (Stage 04 core-aio -> Stage 05 ATS) - 30 min
5. Proxy + hardening patterns (Stages 07-08) - 25 min
6. Migration execution (Stages 09-11) - 45 min
7. Compose to Kubernetes handoff (Stage 12) - 30 min

## 2) Instructor Pre-Checks

Before class:

1. Validate image pulls from `quay.io`/`docker.io` on student VMs.
2. Confirm `.env` values are aligned with your entitlement.
3. Verify ports are free on VM: `8080`, `8081`, `8082`, `8161`, `8443`, `8983`.
4. Prepare one known-good on-prem backup archive for Stage 10 fallback.
5. Confirm Stage 11 cert generation works:
   - `cd stages/11-security-local && NGINX_SERVER_NAME=localhost ./generate-certs.sh`

## 3) Stage-to-Objective Mapping

| Stage | Teaching objective |
|---|---|
| 01 | Base repository + DB bootstrap (no search) |
| 02 | Legacy Solr search topology |
| 03 | OpenSearch topology and migration target |
| 04 | Direct transform with `transform-core-aio` |
| 05 | Enterprise ATS async topology (ActiveMQ + SFS + T-Router) |
| 06 | UI services (ADW + Share) without proxy |
| 07 | Reverse proxy and unified endpoints |
| 08 | Operational hardening patterns |
| 09 | Addon packaging into custom images |
| 10 | On-prem restore and migration execution |
| 11 | Security hardening for local deployment |
| 12 | Build/publish path for Kubernetes consumption |

## 4) Live Checkpoints (Go/No-Go)

### Checkpoint A (after Stage 01)

```bash
curl -f http://localhost:${REPO_HTTP_PORT}/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-
```

### Checkpoint B (after Stage 02)

```bash
curl -f http://localhost:${REPO_HTTP_PORT}/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-
curl -f http://localhost:${SOLR_HTTP_PORT}/solr
```

### Checkpoint C (after Stage 03)

```bash
curl -f http://localhost:${REPO_HTTP_PORT}/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-
docker compose --env-file .env -f stages/03-repo-search-opensearch/compose.yaml exec -T opensearch \
  curl -fsS http://localhost:9200/_cluster/health
```

### Checkpoint D (after Stage 05)

```bash
curl -f http://localhost:${REPO_HTTP_PORT}/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-
curl -f http://localhost:${ACTIVEMQ_WEB_PORT}
```

### Checkpoint E (after Stage 07)

```bash
curl -f http://localhost:${PROXY_HTTP_PORT}/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-
curl -f http://localhost:${PROXY_HTTP_PORT}/workspace
curl -f http://localhost:${PROXY_HTTP_PORT}/share
```

### Checkpoint F (after Stage 10)

1. Database restored without errors.
2. `search-reindexing` runs and completes expected indexing.
3. Search returns restored content.

Primary runbook: `stages/10-restore-onprem/RESTORE.md`

### Checkpoint G (after Stage 11)

```bash
curl -k https://localhost:${PROXY_HTTPS_PORT}/alfresco/api/-default-/public/alfresco/versions/1/probes/-ready-
openssl s_client -connect localhost:${PROXY_HTTPS_PORT} -tls1_3
```

## 5) Common Failure Modes and Fast Fixes

### 1. Port collision when switching stages

```bash
docker compose --env-file .env -f <current-stage-compose.yaml> down
```

### 2. Registry/auth pull failures

1. Re-authenticate to registry.
2. Confirm entitlement for enterprise images.
3. Re-run stage startup.

### 3. OpenSearch/reindexing not progressing (Stage 10)

```bash
docker compose --env-file .env -f stages/10-restore-onprem/compose.yaml up -d search-reindexing
docker compose --env-file .env -f stages/10-restore-onprem/compose.yaml logs -f search-reindexing
```

### 4. TLS stage fails to boot proxy (Stage 11)

```bash
cd stages/11-security-local
NGINX_SERVER_NAME=localhost ./generate-certs.sh --force
```

### 5. Stage 12 bakery build errors

1. Validate prerequisites: `make`, `python3`, `yq`, `jq`, Docker Buildx.
2. Validate `BAKERY_DIR` in `stages/12-k8s-image-bakery/bakery.env`.
3. Validate enterprise artifact credentials (`~/.netrc`).

## 6) Facilitation Notes

1. Ask students to explain why each layer is introduced, not only run commands.
2. Pause at Stage 03 to compare Solr and OpenSearch operational differences.
3. Pause at Stage 05 to compare direct core-aio vs ATS async transform.
4. During Stage 10, emphasize that data restore and search index rebuild are separate concerns.
5. During Stage 12, emphasize image immutability and registry/Helm handoff.

## 7) Debrief Questions

1. What changed in architecture from previous stage?
2. What dependencies became critical in this stage?
3. Which validation proved readiness best?
4. What would break first at production scale?

Final discussion:

1. Which settings should move from Compose envs to Kubernetes Secrets/ConfigMaps?
2. Which services scale horizontally first (repo/search/transform)?
3. What operational checks are missing before production go-live?

## 8) Cleanup and Reset

```bash
# Example: stop one stage
docker compose --env-file .env -f stages/11-security-local/compose.yaml down

# Optional cleanup
docker system prune -f
```

Use prune carefully in classroom environments.

## 9) Remaining Build Items (Post-Class Backlog)

1. Environment snapshot script/report (Guide Project 1)
2. Extension inspector wrapper/checklist output (Guide Project 2)
3. Properties migration conversion script (Guide Project 4)
4. Search validation/performance scripts (Guide Project 5)
5. Automated smoke test suite (Guide Project 8)
6. Scaling diagrams and talk-track package (Guide Project 9)
