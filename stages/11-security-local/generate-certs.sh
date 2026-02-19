#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="${SCRIPT_DIR}/proxy/certs"
KEY_FILE="${CERT_DIR}/alfresco.key"
CRT_FILE="${CERT_DIR}/alfresco.crt"
DAYS="${DAYS:-365}"
SERVER_NAME="${NGINX_SERVER_NAME:-localhost}"
FORCE=0

if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

mkdir -p "${CERT_DIR}"

if [[ -f "${KEY_FILE}" || -f "${CRT_FILE}" ]] && [[ "${FORCE}" -ne 1 ]]; then
  echo "Certificate files already exist in ${CERT_DIR}. Use --force to replace them."
  exit 0
fi

openssl req -x509 -nodes -days "${DAYS}" -newkey rsa:2048 \
  -keyout "${KEY_FILE}" \
  -out "${CRT_FILE}" \
  -subj "/C=US/ST=Local/L=Local/O=Alfresco/CN=${SERVER_NAME}" \
  -addext "subjectAltName=DNS:${SERVER_NAME},IP:127.0.0.1"

chmod 600 "${KEY_FILE}"
chmod 644 "${CRT_FILE}"

echo "Generated self-signed certificate:"
echo "- ${CRT_FILE}"
echo "- ${KEY_FILE}"
echo "CN=${SERVER_NAME}, days=${DAYS}"
