#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# seleimend-db-backup: PostgreSQL Disaster Recovery Restore Script
# ==============================================================================
# Downloads and restores a selected or latest snapshot from Backblaze B2.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat << EOF
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
      if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
        log_error "Option --file requires a filename argument"
        usage
      fi
      TARGET_FILE="$2"
      shift 2
      ;;
    --help | -h)
      usage
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ -z "${ACTION}" ]]; then
  usage
fi

# Initialize Backblaze B2 configuration
init_b2_config

if [[ "${ACTION}" = "list" ]]; then
  # shellcheck disable=SC2154
  log_info "Available snapshots in s3://${B2_BUCKET}/${B2_PREFIX}/:"
  # shellcheck disable=SC2154
  aws --endpoint-url="${B2_ENDPOINT}" s3 ls "s3://${B2_BUCKET}/${B2_PREFIX}/"
  exit 0
fi

if [[ "${ACTION}" = "latest" ]]; then
  log_info "Finding latest snapshot in s3://${B2_BUCKET}/${B2_PREFIX}/..."
  TARGET_FILE=$(aws --endpoint-url="${B2_ENDPOINT}" s3 ls "s3://${B2_BUCKET}/${B2_PREFIX}/" | sort | tail -n 1 | awk '{print $4}')
  if [[ -z "${TARGET_FILE}" ]]; then
    log_error "No snapshots found in s3://${B2_BUCKET}/${B2_PREFIX}/"
    exit 1
  fi
  log_info "Latest snapshot identified: ${TARGET_FILE}"
fi

# Initialize and verify target database connection
init_db_config
check_db_connectivity

SOURCE_S3="s3://${B2_BUCKET}/${B2_PREFIX}/${TARGET_FILE}"
LOCAL_TMP="/tmp/${TARGET_FILE}"

log_info "Downloading ${SOURCE_S3} to temporary storage..."
aws --endpoint-url="${B2_ENDPOINT}" s3 cp "${SOURCE_S3}" "${LOCAL_TMP}"

log_info "Restoring database schema and data via pg_restore..."
# shellcheck disable=SC2154
pg_restore "${RESTORE_TARGET[@]}" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  --verbose \
  "${LOCAL_TMP}" || true

rm -f "${LOCAL_TMP}"
log_success "Database restore completed successfully from ${TARGET_FILE}!"
