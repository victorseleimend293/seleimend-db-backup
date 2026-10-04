#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# seleimend-db-backup: PostgreSQL Disaster Recovery Automated Drill & Verification
# ==============================================================================
# Automatically provisions an isolated test database using the database credentials,
# restores the latest (or selected) snapshot from Backblaze B2, verifies data
# integrity (tables & optional health queries), alerts on failures, and tears down
# the test database.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

TARGET_FILE=""
ACTION="latest"

usage() {
  cat << EOF
Usage: dr_test.sh [OPTIONS]

Options:
  --latest               Test disaster recovery with the most recent snapshot (default)
  --file <FILENAME>      Test disaster recovery with a specific snapshot file name
  --help                 Show this help message

Environment Variables:
  DATABASE_URL (or DB_HOST, DB_NAME, DB_USER, DB_PASSWORD)
  B2_ENDPOINT, B2_APPLICATION_KEY_ID, B2_APPLICATION_KEY, B2_BUCKET
  DR_VERIFY_QUERY       (required: SQL query asserting restored database validity)
  DR_DATABASE_URL       (optional: explicit test database URL instead of auto-creation)
  HEALTHCHECK_URL       (optional: webhook URL for start/fail/success alerts)
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

AUTO_CREATED_DB=""
MAINT_PSQL_CMD=()

cleanup() {
  local exit_code="${1:-0}"
  if [[ -n "${AUTO_CREATED_DB}" ]] && [[ ${#MAINT_PSQL_CMD[@]} -gt 0 ]]; then
    log_info "Tearing down temporary test database: ${AUTO_CREATED_DB}..."
    "${MAINT_PSQL_CMD[@]}" -c "DROP DATABASE IF EXISTS \"${AUTO_CREATED_DB}\" WITH (FORCE);" > /dev/null 2>&1 || true
  fi
  if [[ ${exit_code} -ne 0 ]]; then
    local err_msg="Disaster recovery drill failed for ${IDENTIFIER:-database} with exit code ${exit_code}"
    log_error "${err_msg}"
    notify_healthcheck "fail" "${err_msg}"
  fi
  exit "${exit_code}"
}

trap 'cleanup $?' EXIT INT TERM

log_info "Starting automated disaster recovery drill..."
notify_healthcheck "start"

# Initialize configurations
init_b2_config
init_db_config
check_db_connectivity

# Verify required DR_VERIFY_QUERY is provided
if [[ -z "${DR_VERIFY_QUERY:-}" ]]; then
  log_error "Missing required environment variable: DR_VERIFY_QUERY"
  exit 1
fi

# Identify target snapshot
if [[ "${ACTION}" = "latest" ]]; then
  # shellcheck disable=SC2154
  log_info "Locating latest snapshot in s3://${B2_BUCKET}/${B2_PREFIX}/..."
  # shellcheck disable=SC2154
  TARGET_FILE=$(aws --endpoint-url="${B2_ENDPOINT}" s3 ls "s3://${B2_BUCKET}/${B2_PREFIX}/" | sort | tail -n 1 | awk '{print $4}')
  if [[ -z "${TARGET_FILE}" ]]; then
    log_error "No snapshots found in s3://${B2_BUCKET}/${B2_PREFIX}/"
    exit 1
  fi
  log_info "Target snapshot identified: ${TARGET_FILE}"
fi

# Determine maintenance connection command for creating/dropping databases
if [[ -n "${DATABASE_URL:-}" ]]; then
  MAINT_URL="$(echo "${DATABASE_URL}" | sed -E 's|/[^/?]+(\?.*)?$|/postgres\1|')"
  MAINT_PSQL_CMD=("psql" "${MAINT_URL}")
else
  # shellcheck disable=SC2154
  MAINT_PSQL_CMD=("psql" "-h" "${DB_HOST}" "-p" "${DB_PORT}" "-U" "${DB_USER}" "-d" "postgres")
fi

# Setup isolated target database
if [[ -n "${DR_DATABASE_URL:-}" ]]; then
  TEST_DB_URL="${DR_DATABASE_URL}"
  log_info "Using explicit disaster recovery target database: ${TEST_DB_URL}"
else
  TIMESTAMP_DR="$(date -u +"%Y%m%d%H%M%S")"
  # shellcheck disable=SC2154
  AUTO_CREATED_DB="dr_test_${IDENTIFIER}_${TIMESTAMP_DR}"
  log_info "Provisioning temporary isolated test database: ${AUTO_CREATED_DB}..."
  "${MAINT_PSQL_CMD[@]}" -c "CREATE DATABASE \"${AUTO_CREATED_DB}\";"

  if [[ -n "${DATABASE_URL:-}" ]]; then
    TEST_DB_URL="$(echo "${DATABASE_URL}" | sed -E "s|/[^/?]+(\\?.*)?$|/${AUTO_CREATED_DB}\\1|")"
  else
    # shellcheck disable=SC2154
    TEST_DB_URL="postgresql://${DB_USER}:${DB_PASSWORD:-}@${DB_HOST}:${DB_PORT}/${AUTO_CREATED_DB}"
  fi
fi

# Restore snapshot into the test database
log_info "Restoring snapshot ${TARGET_FILE} into test database..."
DATABASE_URL="${TEST_DB_URL}" DB_HOST="" DB_NAME="" DB_USER="" DB_PASSWORD="" "${SCRIPT_DIR}/restore.sh" --file "${TARGET_FILE}"

# Verification Phase
log_info "Verifying database integrity and restored schema..."
TABLE_COUNT_RAW=$(psql "${TEST_DB_URL}" -t -A -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")
TABLE_COUNT="${TABLE_COUNT_RAW//[^0-9]/}"

if [[ -z "${TABLE_COUNT}" ]] || [[ "${TABLE_COUNT}" -eq 0 ]]; then
  log_error "Disaster recovery verification failed: no tables found in restored database!"
  exit 1
fi
log_info "Restoration verified: ${TABLE_COUNT} table(s) found in public schema."

# Execute required custom SQL verification query
log_info "Running custom verification query: ${DR_VERIFY_QUERY}"
psql "${TEST_DB_URL}" -c "${DR_VERIFY_QUERY}"

SUCCESS_MSG="Disaster recovery drill passed successfully! Snapshot ${TARGET_FILE} verified with ${TABLE_COUNT} table(s)."
log_success "${SUCCESS_MSG}"
notify_healthcheck "success" "${SUCCESS_MSG}"
