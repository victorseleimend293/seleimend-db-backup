#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# seleimend-db-backup: PostgreSQL Disaster Recovery Restore Script
# ==============================================================================
# Downloads and restores a selected or latest snapshot from Backblaze B2.
# ==============================================================================

usage() {
  cat <<EOF
Usage: restore.sh [OPTIONS]

Options:
  --list                 List all available snapshots in B2
  --latest               Restore the most recent snapshot
  --file <FILENAME>      Restore a specific snapshot file name
  --help                 Show this help message

Environment Variables Required:
  B2_ENDPOINT, B2_APPLICATION_KEY_ID, B2_APPLICATION_KEY, B2_BUCKET
  DATABASE_URL (or DB_HOST, DB_NAME, DB_USER, DB_PASSWORD)
EOF
  exit 1
}

# 1. Validate Backblaze B2 / S3 Configuration
B2_KEY_ID="${B2_APPLICATION_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
B2_KEY="${B2_APPLICATION_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
B2_ENDPOINT="${B2_ENDPOINT:-${AWS_ENDPOINT_URL:-}}"
B2_BUCKET="${B2_BUCKET:-}"
B2_PREFIX="${B2_PREFIX:-backups/postgres}"
B2_REGION="${B2_REGION:-us-east-005}"

if [ -z "${B2_KEY_ID}" ] || [ -z "${B2_KEY}" ] || [ -z "${B2_ENDPOINT}" ] || [ -z "${B2_BUCKET}" ]; then
  echo "==> [ERROR] Missing Backblaze B2 configuration (endpoint, credentials, or bucket)." >&2
  exit 1
fi

B2_PREFIX="$(echo "${B2_PREFIX}" | sed 's|^/||;s|/$||')"

if [[ "${B2_ENDPOINT}" != http://* ]] && [[ "${B2_ENDPOINT}" != https://* ]]; then
  B2_ENDPOINT="https://${B2_ENDPOINT}"
fi

export AWS_ACCESS_KEY_ID="${B2_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${B2_KEY}"
export AWS_DEFAULT_REGION="${B2_REGION}"

ACTION=""
TARGET_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      ACTION="list"
      shift
      ;;
    --latest)
      ACTION="latest"
      shift
      ;;
    --file)
      ACTION="file"
      TARGET_FILE="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

if [ -z "${ACTION}" ]; then
  usage
fi

if [ "${ACTION}" = "list" ]; then
  echo "==> [B2] Available snapshots in s3://${B2_BUCKET}/${B2_PREFIX}/:"
  aws --endpoint-url="${B2_ENDPOINT}" s3 ls "s3://${B2_BUCKET}/${B2_PREFIX}/"
  exit 0
fi

if [ "${ACTION}" = "latest" ]; then
  echo "==> [B2] Finding latest snapshot in s3://${B2_BUCKET}/${B2_PREFIX}/..."
  TARGET_FILE=$(aws --endpoint-url="${B2_ENDPOINT}" s3 ls "s3://${B2_BUCKET}/${B2_PREFIX}/" | sort | tail -n 1 | awk '{print $4}')
  if [ -z "${TARGET_FILE}" ]; then
    echo "==> [ERROR] No snapshots found in s3://${B2_BUCKET}/${B2_PREFIX}/" >&2
    exit 1
  fi
  echo "==> [B2] Latest snapshot identified: ${TARGET_FILE}"
fi

if [ -z "${TARGET_FILE}" ]; then
  echo "==> [ERROR] No target snapshot specified." >&2
  exit 1
fi

# 2. Validate Database Configuration
DATABASE_URL="${DATABASE_URL:-}"
DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASSWORD="${DB_PASSWORD:-}"

if [ -z "${DATABASE_URL}" ] && { [ -z "${DB_HOST}" ] || [ -z "${DB_NAME}" ] || [ -z "${DB_USER}" ]; }; then
  echo "==> [ERROR] Target database connection parameters missing." >&2
  exit 1
fi

echo "==> [Check] Verifying target PostgreSQL connectivity..."
if [ -n "${DATABASE_URL}" ]; then
  pg_isready -d "${DATABASE_URL}" -t 15
  RESTORE_TARGET=("-d" "${DATABASE_URL}")
else
  export PGPASSWORD="${DB_PASSWORD}"
  pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t 15
  RESTORE_TARGET=("-h" "${DB_HOST}" "-p" "${DB_PORT}" "-U" "${DB_USER}" "-d" "${DB_NAME}")
fi

SOURCE_S3="s3://${B2_BUCKET}/${B2_PREFIX}/${TARGET_FILE}"
LOCAL_TMP="/tmp/${TARGET_FILE}"

echo "==> [Restore] Downloading ${SOURCE_S3} to temporary storage..."
aws --endpoint-url="${B2_ENDPOINT}" s3 cp "${SOURCE_S3}" "${LOCAL_TMP}"

echo "==> [Restore] Restoring database schema and data via pg_restore..."
pg_restore "${RESTORE_TARGET[@]}" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --verbose \
  "${LOCAL_TMP}" || true

rm -f "${LOCAL_TMP}"
echo "==> [Success] Database restore completed successfully from ${TARGET_FILE}!"
