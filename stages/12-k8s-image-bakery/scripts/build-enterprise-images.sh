#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE_DEFAULT="${STAGE_DIR}/bakery.env"

BAKERY_DIR="${BAKERY_DIR:-}"
TARGETS="${TARGETS:-repo share search_enterprise ats tengines sync adf_apps}"
PUSH=0
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --env-file <path>        Env file to source (default: stages/12-k8s-image-bakery/bakery.env)
  --bakery-dir <path>      Path to local alfresco-dockerfiles-bakery clone
  --targets "..."          Space-separated make targets
  --push                   Expect REGISTRY/REGISTRY_NAMESPACE and push images
  --dry-run                Print planned command only
  -h, --help               Show this help
USAGE
}

ENV_FILE="${ENV_FILE_DEFAULT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --bakery-dir)
      BAKERY_DIR="$2"
      shift 2
      ;;
    --targets)
      TARGETS="$2"
      shift 2
      ;;
    --push)
      PUSH=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

if [[ -z "${BAKERY_DIR}" ]]; then
  echo "BAKERY_DIR is required. Set it in env file or pass --bakery-dir." >&2
  exit 1
fi

if [[ ! -f "${BAKERY_DIR}/Makefile" ]]; then
  echo "Invalid bakery directory: ${BAKERY_DIR} (Makefile not found)" >&2
  exit 1
fi

export ACS_VERSION="${ACS_VERSION:-25}"
export TARGETARCH="${TARGETARCH:-linux/amd64}"
export TAG="${TAG:-25.3.0-custom}"

if [[ "${PUSH}" -eq 1 ]]; then
  : "${REGISTRY:?REGISTRY is required when --push is used}"
  : "${REGISTRY_NAMESPACE:?REGISTRY_NAMESPACE is required when --push is used}"
else
  # local-only build/load
  export REGISTRY="${REGISTRY:-localhost}"
  export REGISTRY_NAMESPACE="${REGISTRY_NAMESPACE:-alfresco}"
fi

echo "Bakery directory : ${BAKERY_DIR}"
echo "ACS_VERSION      : ${ACS_VERSION}"
echo "TARGETARCH       : ${TARGETARCH}"
echo "REGISTRY         : ${REGISTRY}"
echo "REGISTRY_NAMESPACE: ${REGISTRY_NAMESPACE}"
echo "TAG              : ${TAG}"
echo "TARGETS          : ${TARGETS}"

cmd=(make)
for t in ${TARGETS}; do
  cmd+=("${t}")
done

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "Dry run command: (cd ${BAKERY_DIR} && ${cmd[*]})"
  exit 0
fi

(
  cd "${BAKERY_DIR}"
  "${cmd[@]}"
)

echo "Build complete."
