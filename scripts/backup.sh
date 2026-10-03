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

SUCCESS_MSG="Successfully backed up ${IDENTIFIER} to ${DESTINATION} at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
log_success "${SUCCESS_MSG}"
notify_healthcheck "success" "${SUCCESS_MSG}"
