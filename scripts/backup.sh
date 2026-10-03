#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# seleimend-db-backup: PostgreSQL to Backblaze B2 Streaming Backup
# ==============================================================================
# Streams pg_dump directly into Backblaze B2 (S3-compatible API) with zero
# disk overhead, optional healthcheck monitoring, and retention cleanup.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

on_error() {
  local exit_code=$1
  local line_no=$2
  log_error "Backup failed at line ${line_no} with exit code ${exit_code}"
  notify_healthcheck "fail" "Backup failed at line ${line_no} with exit code ${exit_code}"
  exit "${exit_code}"
}

trap 'on_error $? ${LINENO}' ERR

log_info "Starting database backup procedure..."
notify_healthcheck "start"

# Initialize configurations and verify connectivity
init_b2_config
init_db_config
check_db_connectivity

TIMESTAMP="$(date -u +"%Y%m%d_%H%M%SZ")"
# shellcheck disable=SC2154
SNAPSHOT_FILENAME="${IDENTIFIER}_${TIMESTAMP}.dump"
# shellcheck disable=SC2154
DESTINATION="s3://${B2_BUCKET}/${B2_PREFIX}/${SNAPSHOT_FILENAME}"

log_info "Target snapshot: ${DESTINATION}"
log_info "Dumping and streaming directly to Backblaze B2 (Format: custom compressed)..."

# Stream pg_dump custom format directly into B2 via AWS CLI streaming stdin
# shellcheck disable=SC2154
pg_dump "${DUMP_TARGET[@]}" \
  --format=custom \
  --blobs \
  --verbose \
  --no-owner \
  --no-privileges 2> >(grep -v "^pg_dump: dumping contents" >&2) \
  | aws --endpoint-url="${B2_ENDPOINT}" s3 cp - "${DESTINATION}" --expected-size "${EXPECTED_SIZE:-104857600}"

log_info "Checking uploaded object metadata on B2..."
aws --endpoint-url="${B2_ENDPOINT}" s3 ls "${DESTINATION}"

# Optional Retention Cleanup
RETENTION_DAYS="${RETENTION_DAYS:-0}"
if [[ "${RETENTION_DAYS}" -gt 0 ]]; then
  log_info "Pruning snapshots older than ${RETENTION_DAYS} days in s3://${B2_BUCKET}/${B2_PREFIX}/..."
  CUTOFF_TIMESTAMP="$(date -u -d "${RETENTION_DAYS} days ago" +"%Y%m%d_%H%M%SZ" 2> /dev/null || date -u -v-"${RETENTION_DAYS}"d +"%Y%m%d_%H%M%SZ")"

  aws --endpoint-url="${B2_ENDPOINT}" s3 ls "s3://${B2_BUCKET}/${B2_PREFIX}/" | while read -r line; do
    OBJ_FILE=$(echo "${line}" | awk '{print $4}')
    if [[ "${OBJ_FILE}" =~ ^${IDENTIFIER}_([0-9]{8}_[0-9]{6}Z)\.dump$ ]]; then
      FILE_TIMESTAMP="${BASH_REMATCH[1]}"
      if [[ "${FILE_TIMESTAMP}" < "${CUTOFF_TIMESTAMP}" ]]; then
        log_info "Deleting expired snapshot: ${OBJ_FILE}"
        aws --endpoint-url="${B2_ENDPOINT}" s3 rm "s3://${B2_BUCKET}/${B2_PREFIX}/${OBJ_FILE}"
      fi
    fi
  done
fi

SUCCESS_MSG="Successfully backed up ${IDENTIFIER} to ${DESTINATION} at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
log_success "${SUCCESS_MSG}"
notify_healthcheck "success" "${SUCCESS_MSG}"
