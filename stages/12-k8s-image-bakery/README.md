# Stage 12 - Kubernetes Image Bakery

This stage is a **build/release track** (not a runtime Docker Compose stack).
It prepares custom images for Kubernetes deployments by integrating local
customizations with [alfresco-dockerfiles-bakery](https://github.com/Alfresco/alfresco-dockerfiles-bakery).

## Goal

Build and optionally push Enterprise images that include your custom modules,
then generate Helm image overrides for `acs-deployment`.

## Inputs

By default this stage takes addons from Stage 11:

- `../11-security-local/addons/repository/amps`
- `../11-security-local/addons/repository/jars`
- `../11-security-local/addons/share/amps`
- `../11-security-local/addons/share/jars`

## Prerequisites

- Local clone of `alfresco-dockerfiles-bakery`
- Docker with Buildx
- `make`, `python3`, `yq`, `jq`
- Enterprise artifact credentials in `~/.netrc` when building Enterprise images

## Quick Start

1. Copy environment template:

```bash
cd stages/12-k8s-image-bakery
cp bakery.env.example bakery.env
```

2. Edit `bakery.env` and set at least:

- `BAKERY_DIR`
- `REGISTRY`, `REGISTRY_NAMESPACE`, `TAG`

3. Load environment:

```bash
set -a; source ./bakery.env; set +a
```

4. Sync addons into bakery folders:

```bash
./scripts/prepare-bakery-workspace.sh --bakery-dir "$BAKERY_DIR"
```

5. Build Enterprise images:

```bash
./scripts/build-enterprise-images.sh --env-file ./bakery.env
```

6. Render Helm image overrides:

```bash
./scripts/render-helm-overrides.sh --env-file ./bakery.env
```

Output file:

- `./helm-values.overrides.yaml`

## Push to Registry

To push images, set real registry values in `bakery.env` and run:

```bash
./scripts/build-enterprise-images.sh --env-file ./bakery.env --push
```

## Helm Usage Example

Use the generated overrides with `acs-deployment` chart:

```bash
helm upgrade --install acs alfresco/alfresco-content-services \
  -f values.yaml \
  -f stages/12-k8s-image-bakery/helm-values.overrides.yaml
```

## Notes

- This stage intentionally does not provide `compose.yaml`.
- Runtime concerns remain in stages 01-11.
- Stage 12 only standardizes image build/publish handoff to Kubernetes.
