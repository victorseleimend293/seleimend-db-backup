#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# seleimend-db-backup: PostgreSQL to Backblaze B2 Streaming Backup
# ==============================================================================
# Streams pg_dump directly into Backblaze B2 (S3-compatible API) with zero
# disk overhead, optional healthcheck monitoring, and retention cleanup.
# ==============================================================================

# Notify monitoring webhook (e.g. healthchecks.io)
notify_healthcheck() {
  local state="${1:-}"
  local msg="${2:-}"
  if [ -n "${HEALTHCHECK_URL:-}" ]; then
    case "${state}" in
      start)
        curl -fsS -m 10 --retry 3 "${HEALTHCHECK_URL}/start" >/dev/null 2>&1 || true
        ;;
      success)
        curl -fsS -m 10 --retry 3 --data-raw "${msg}" "${HEALTHCHECK_URL}" >/dev/null 2>&1 || true
        ;;
      fail)
        curl -fsS -m 10 --retry 3 --data-raw "${msg}" "${HEALTHCHECK_URL}/fail" >/dev/null 2>&1 || true
        ;;
    esac
  fi
}

on_error() {
  local exit_code=$?
  local line_no=$1
  echo "==> [ERROR] Backup failed at line ${line_no} with exit code ${exit_code}" >&2
  notify_healthcheck "fail" "Backup failed at line ${line_no} with exit code ${exit_code}"
  exit "${exit_code}"
}

trap 'on_error ${LINENO}' ERR

echo "==> [$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Starting database backup procedure..."
notify_healthcheck "start"

# 1. Validate Backblaze B2 / S3 Configuration
B2_KEY_ID="${B2_APPLICATION_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
B2_KEY="${B2_APPLICATION_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
B2_ENDPOINT="${B2_ENDPOINT:-${AWS_ENDPOINT_URL:-}}"
B2_BUCKET="${B2_BUCKET:-}"
B2_PREFIX="${B2_PREFIX:-backups/postgres}"
B2_REGION="${B2_REGION:-us-east-005}"

if [ -z "${B2_KEY_ID}" ] || [ -z "${B2_KEY}" ]; then
  echo "==> [ERROR] Missing Backblaze B2 credentials (B2_APPLICATION_KEY_ID / B2_APPLICATION_KEY)" >&2
  exit 1
fi

if [ -z "${B2_ENDPOINT}" ]; then
  echo "==> [ERROR] Missing Backblaze B2 endpoint (B2_ENDPOINT, e.g. s3.us-west-004.backblazeb2.com)" >&2
  exit 1
fi

if [ -z "${B2_BUCKET}" ]; then
  echo "==> [ERROR] Missing B2 bucket name (B2_BUCKET)" >&2
  exit 1
fi

# Clean prefix (strip leading/trailing slashes)
B2_PREFIX="$(echo "${B2_PREFIX}" | sed 's|^/||;s|/$||')"

# Ensure endpoint has protocol
if [[ "${B2_ENDPOINT}" != http://* ]] && [[ "${B2_ENDPOINT}" != https://* ]]; then
  B2_ENDPOINT="https://${B2_ENDPOINT}"
fi

# Export AWS CLI credentials for B2 S3 API
export AWS_ACCESS_KEY_ID="${B2_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${B2_KEY}"
export AWS_DEFAULT_REGION="${B2_REGION}"

# 2. Validate Database Configuration
DATABASE_URL="${DATABASE_URL:-}"
DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASSWORD="${DB_PASSWORD:-}"

if [ -z "${DATABASE_URL}" ] && { [ -z "${DB_HOST}" ] || [ -z "${DB_NAME}" ] || [ -z "${DB_USER}" ]; }; then
  echo "==> [ERROR] Database connection parameters missing. Provide DATABASE_URL or DB_HOST, DB_NAME, and DB_USER." >&2
  exit 1
fi

# Build connection parameters and verify readiness
echo "==> [Check] Verifying PostgreSQL connectivity..."
if [ -n "${DATABASE_URL}" ]; then
  pg_isready -d "${DATABASE_URL}" -t 15 || {
    echo "==> [ERROR] PostgreSQL database is not reachable at DATABASE_URL" >&2
    exit 1
  }
  DUMP_TARGET=("${DATABASE_URL}")
  # Extract DB name from URL if possible for filename tagging
  IDENTIFIER="$(echo "${DATABASE_URL}" | sed -E 's/.*\///; s/\?.*//')"
  [ -z "${IDENTIFIER}" ] && IDENTIFIER="postgres"
else
  export PGPASSWORD="${DB_PASSWORD}"
  pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t 15 || {
    echo "==> [ERROR] PostgreSQL database is not reachable at ${DB_HOST}:${DB_PORT}/${DB_NAME}" >&2
    exit 1
  }
  DUMP_TARGET=("-h" "${DB_HOST}" "-p" "${DB_PORT}" "-U" "${DB_USER}" "-d" "${DB_NAME}")
  IDENTIFIER="${DB_NAME}"
fi

TIMESTAMP="$(date -u +"%Y%m%d_%H%M%SZ")"
SNAPSHOT_FILENAME="${IDENTIFIER}_${TIMESTAMP}.dump"
DESTINATION="s3://${B2_BUCKET}/${B2_PREFIX}/${SNAPSHOT_FILENAME}"

echo "==> [Backup] Target snapshot: ${DESTINATION}"
echo "==> [Backup] Dumping and streaming directly to Backblaze B2 (Format: custom compressed)..."

# Stream pg_dump custom format directly into B2 via AWS CLI streaming stdin
pg_dump "${DUMP_TARGET[@]}" \
  --format=custom \
  --blobs \
  --verbose \
  --no-owner \
  --no-privileges 2> >(grep -v "^pg_dump: dumping contents" >&2) | \
  aws --endpoint-url="${B2_ENDPOINT}" s3 cp - "${DESTINATION}" --expected-size "${EXPECTED_SIZE:-104857600}"

echo "==> [Verify] Checking uploaded object metadata on B2..."
aws --endpoint-url="${B2_ENDPOINT}" s3 ls "${DESTINATION}"

# 3. Optional Retention Cleanup
RETENTION_DAYS="${RETENTION_DAYS:-0}"
if [ "${RETENTION_DAYS}" -gt 0 ]; then
  echo "==> [Retention] Pruning snapshots older than ${RETENTION_DAYS} days in s3://${B2_BUCKET}/${B2_PREFIX}/..."
  CUTOFF_TIMESTAMP="$(date -u -d "${RETENTION_DAYS} days ago" +"%Y%m%d_%H%M%SZ" 2>/dev/null || date -u -v-"${RETENTION_DAYS}"d +"%Y%m%d_%H%M%SZ")"
  
  aws --endpoint-url="${B2_ENDPOINT}" s3 ls "s3://${B2_BUCKET}/${B2_PREFIX}/" | while read -r line; do
    OBJ_FILE=$(echo "${line}" | awk '{print $4}')
    if [[ "${OBJ_FILE}" =~ ^${IDENTIFIER}_([0-9]{8}_[0-9]{6}Z)\.dump$ ]]; then
      FILE_TIMESTAMP="${BASH_REMATCH[1]}"
      if [[ "${FILE_TIMESTAMP}" < "${CUTOFF_TIMESTAMP}" ]]; then
        echo "==> [Retention] Deleting expired snapshot: ${OBJ_FILE}"
        aws --endpoint-url="${B2_ENDPOINT}" s3 rm "s3://${B2_BUCKET}/${B2_PREFIX}/${OBJ_FILE}"
      fi
    fi
  done
fi

SUCCESS_MSG="Successfully backed up ${IDENTIFIER} to ${DESTINATION} at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "==> [Success] ${SUCCESS_MSG}"
notify_healthcheck "success" "${SUCCESS_MSG}"
