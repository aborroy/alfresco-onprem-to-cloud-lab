#!/usr/bin/env bash
set -euo pipefail

# Run this script from the stage directory you want to populate:
#   cd stages/09-addons
#   ../../shared/fetch-addons.sh
#
# Addon files are downloaded relative to the current working directory.

TARGET_DIR="${PWD}"
REPO_AMPS_DIR="${TARGET_DIR}/addons/repository/amps"
REPO_JARS_DIR="${TARGET_DIR}/addons/repository/jars"
SHARE_AMPS_DIR="${TARGET_DIR}/addons/share/amps"
SHARE_JARS_DIR="${TARGET_DIR}/addons/share/jars"

FORCE=0

if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

mkdir -p "${REPO_AMPS_DIR}" "${REPO_JARS_DIR}" "${SHARE_AMPS_DIR}" "${SHARE_JARS_DIR}"

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

json_assets() {
  sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

release_assets_by_tag() {
  local repo="$1"
  local tag="$2"

  curl --fail --silent --show-error --location \
    "https://api.github.com/repos/${repo}/releases/tags/${tag}" | json_assets || true
}

release_assets_all() {
  local repo="$1"

  curl --fail --silent --show-error --location \
    "https://api.github.com/repos/${repo}/releases?per_page=40" | json_assets || true
}

classify_target_dir() {
  local file_name="$1"
  local ext="${file_name##*.}"
  local lower_name

  lower_name="$(printf '%s' "${file_name}" | tr '[:upper:]' '[:lower:]')"

  case "${ext}" in
    amp)
      if [[ "${lower_name}" =~ (share|surf|aikau) ]]; then
        printf '%s\n' "${SHARE_AMPS_DIR}"
      else
        printf '%s\n' "${REPO_AMPS_DIR}"
      fi
      ;;
    jar)
      if [[ "${lower_name}" =~ (share|surf|aikau) ]]; then
        printf '%s\n' "${SHARE_JARS_DIR}"
      else
        printf '%s\n' "${REPO_JARS_DIR}"
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

download_asset() {
  local url="$1"
  local file_name target_dir target_file

  file_name="$(basename "${url%%\?*}")"
  target_dir="$(classify_target_dir "${file_name}")"
  target_file="${target_dir}/${file_name}"

  if [[ -f "${target_file}" && "${FORCE}" -ne 1 ]]; then
    log "skip ${file_name} (already exists)"
    return 0
  fi

  log "download ${file_name}"
  curl --fail --silent --show-error --location "${url}" -o "${target_file}"
}

fetch_addon() {
  local addon_name="$1"
  local repo="$2"
  local tag="$3"
  local regex="$4"
  local assets assets_to_download

  log ""
  log "== ${addon_name} =="
  log "repo: ${repo}"

  assets="$(release_assets_by_tag "${repo}" "${tag}")"
  if [[ -z "${assets}" ]]; then
    warn "no assets for tag ${tag}; trying all releases"
    assets="$(release_assets_all "${repo}")"
  fi

  if [[ -z "${assets}" ]]; then
    warn "no release assets found for ${repo}"
    warn "check manually: https://github.com/${repo}/releases"
    return 0
  fi

  assets_to_download="$(printf '%s\n' "${assets}" | grep -E -i "${regex}" | grep -E -i '\.(amp|jar)(\?.*)?$' | sort -u || true)"

  if [[ -z "${assets_to_download}" ]]; then
    warn "no matching AMP/JAR assets with regex: ${regex}"
    warn "check manually: https://github.com/${repo}/releases"
    return 0
  fi

  while IFS= read -r url; do
    [[ -z "${url}" ]] && continue
    download_asset "${url}"
  done <<< "${assets_to_download}"
}

cat <<'BANNER'
Alfresco Addons Fetcher

Downloads addon AMP/JAR artifacts into:
- addons/repository/amps
- addons/repository/jars
- addons/share/amps
- addons/share/jars

Use --force to re-download existing files.
BANNER

# Addon list aligned with alfresco-ubuntu-installer/ADDONS.md
# Regexes are intentionally broad to tolerate upstream naming differences.

fetch_addon "Google Docs Integration (3.1.0)"              "Alfresco/googledrive"                        "3.1.0"          '(google|googledocs|drive)'
fetch_addon "OOTBee Support Tools (1.2.2.0)"               "OrderOfTheBee/ootbee-support-tools"          "1.2.2.0"        '(support-tools|ootbee)'
fetch_addon "Javascript Console (0.7)"                     "share-extras/js-console"                     "0.7"            '(javascript-console|js-console)'
fetch_addon "Share Site Creators (0.0.8)"                  "aborroy/share-site-creators"                 "0.0.8"          '(site-creators|share-site-creators)'
fetch_addon "Share Site Space Templates (1.1.4-SNAPSHOT)"  "jpotts/share-site-space-templates"           "1.1.4-SNAPSHOT" '(site-space-templates|space-templates)'
fetch_addon "Share Online Edition Addon (0.3.0)"           "zylklab/alfresco-share-online-edition-addon" "0.3.0"          '(online-edition|libreoffice|share-online)'
fetch_addon "ESign Certification Addon (1.8.4)"            "ambientelivre/alfresco-esign-cert"           "1.8.4"          '(esign|cert)'
fetch_addon "Alfresco PDF Toolkit (1.4)"                   "OrderOfTheBee/alfresco-pdf-toolkit"          "1.4"            '(pdf-toolkit|pdftoolkit|pdf)'
fetch_addon "Alfresco T-Engine OCR Addon"                  "aborroy/alf-tengine-ocr"                     "1.0.0"          '(ocr|tengine)'

log ""
log "done"
log "review downloaded files under ${TARGET_DIR}/addons before building."
