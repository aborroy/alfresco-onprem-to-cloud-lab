#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STAGE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

BAKERY_DIR="${BAKERY_DIR:-}"
SOURCE_STAGE_DIR="${SOURCE_STAGE_DIR:-${STAGE_DIR}/../11-security-local}"
CLEAN=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") --bakery-dir <path> [options]

Options:
  --bakery-dir <path>      Path to local alfresco-dockerfiles-bakery clone
  --source-stage <path>    Source stage path (default: ../11-security-local)
  --clean                  Remove existing AMP/JAR files in destination folders
  -h, --help               Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bakery-dir)
      BAKERY_DIR="$2"
      shift 2
      ;;
    --source-stage)
      SOURCE_STAGE_DIR="$2"
      shift 2
      ;;
    --clean)
      CLEAN=1
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

if [[ -z "${BAKERY_DIR}" ]]; then
  echo "--bakery-dir is required" >&2
  usage
  exit 1
fi

if [[ ! -f "${BAKERY_DIR}/Makefile" ]]; then
  echo "Invalid bakery directory: ${BAKERY_DIR} (Makefile not found)" >&2
  exit 1
fi

SRC_REPO_AMPS="${SOURCE_STAGE_DIR}/addons/repository/amps"
SRC_REPO_JARS="${SOURCE_STAGE_DIR}/addons/repository/jars"
SRC_SHARE_AMPS="${SOURCE_STAGE_DIR}/addons/share/amps"
SRC_SHARE_JARS="${SOURCE_STAGE_DIR}/addons/share/jars"

DST_REPO_AMPS="${BAKERY_DIR}/repository/amps_enterprise"
DST_REPO_JARS="${BAKERY_DIR}/repository/simple_modules"
DST_SHARE_AMPS="${BAKERY_DIR}/share/amps"
DST_SHARE_JARS="${BAKERY_DIR}/share/simple_modules"

mkdir -p "${DST_REPO_AMPS}" "${DST_REPO_JARS}" "${DST_SHARE_AMPS}" "${DST_SHARE_JARS}"

if [[ "${CLEAN}" -eq 1 ]]; then
  find "${DST_REPO_AMPS}" -maxdepth 1 -type f -name '*.amp' -delete
  find "${DST_REPO_JARS}" -maxdepth 1 -type f -name '*.jar' -delete
  find "${DST_SHARE_AMPS}" -maxdepth 1 -type f -name '*.amp' -delete
  find "${DST_SHARE_JARS}" -maxdepth 1 -type f -name '*.jar' -delete
fi

copy_files() {
  local src_dir="$1"
  local pattern="$2"
  local dst_dir="$3"
  local copied=0

  if [[ -d "${src_dir}" ]]; then
    while IFS= read -r -d '' f; do
      cp -f "${f}" "${dst_dir}/"
      copied=$((copied + 1))
    done < <(find "${src_dir}" -maxdepth 1 -type f -name "${pattern}" -print0)
  fi

  echo "${copied}"
}

repo_amp_count="$(copy_files "${SRC_REPO_AMPS}" '*.amp' "${DST_REPO_AMPS}")"
repo_jar_count="$(copy_files "${SRC_REPO_JARS}" '*.jar' "${DST_REPO_JARS}")"
share_amp_count="$(copy_files "${SRC_SHARE_AMPS}" '*.amp' "${DST_SHARE_AMPS}")"
share_jar_count="$(copy_files "${SRC_SHARE_JARS}" '*.jar' "${DST_SHARE_JARS}")"

echo "Prepared bakery workspace: ${BAKERY_DIR}"
echo "- repository/amps_enterprise: ${repo_amp_count} file(s)"
echo "- repository/simple_modules: ${repo_jar_count} file(s)"
echo "- share/amps: ${share_amp_count} file(s)"
echo "- share/simple_modules: ${share_jar_count} file(s)"
