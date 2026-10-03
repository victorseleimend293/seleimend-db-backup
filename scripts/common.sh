#!/usr/bin/env bash
# ==============================================================================
# seleimend-db-backup: Shared Utilities & Configuration Module
# ==============================================================================
# Encapsulates logging, healthcheck webhooks, B2 S3 credentials validation,
# and PostgreSQL connection verification following DRY & KISS principles.
# ==============================================================================

# Standardized logging helpers
log_info() {
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "==> [${now}] [INFO] $*"
}

log_success() {
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "==> [${now}] [SUCCESS] $*"
}

log_warn() {
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "==> [${now}] [WARN] $*" >&2
}

log_error() {
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "==> [${now}] [ERROR] $*" >&2
}

# Webhook notification (e.g. healthchecks.io, BetterStack)
notify_healthcheck() {
  local state="${1:-}"
  local msg="${2:-}"
  if [[ -n "${HEALTHCHECK_URL:-}" ]]; then
    case "${state}" in
      start)
        curl -fsS -m 10 --retry 3 "${HEALTHCHECK_URL}/start" > /dev/null 2>&1 || true
        ;;
      success)
        curl -fsS -m 10 --retry 3 --data-raw "${msg}" "${HEALTHCHECK_URL}" > /dev/null 2>&1 || true
        ;;
      fail)
        curl -fsS -m 10 --retry 3 --data-raw "${msg}" "${HEALTHCHECK_URL}/fail" > /dev/null 2>&1 || true
        ;;
      *) ;;

    esac
  fi
}

# Validate and initialize Backblaze B2 S3 API configuration
# shellcheck disable=SC2034
init_b2_config() {
  B2_KEY_ID="${B2_APPLICATION_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
  B2_KEY="${B2_APPLICATION_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
  B2_ENDPOINT="${B2_ENDPOINT:-${AWS_ENDPOINT_URL:-}}"
  B2_BUCKET="${B2_BUCKET:-}"
  B2_PREFIX="${B2_PREFIX:-backups/postgres}"
  B2_REGION="${B2_REGION:-us-east-005}"

  if [[ -z "${B2_KEY_ID}" ]] || [[ -z "${B2_KEY}" ]]; then
    log_error "Missing Backblaze B2 credentials (B2_APPLICATION_KEY_ID / B2_APPLICATION_KEY)"
    exit 1
  fi

  if [[ -z "${B2_ENDPOINT}" ]]; then
    log_error "Missing Backblaze B2 endpoint (B2_ENDPOINT, e.g. s3.us-west-004.backblazeb2.com)"
    exit 1
  fi

  if [[ -z "${B2_BUCKET}" ]]; then
    log_error "Missing B2 bucket name (B2_BUCKET)"
    exit 1
  fi

  # Clean prefix (strip leading and trailing slashes)
  B2_PREFIX="$(echo "${B2_PREFIX}" | sed 's|^/||;s|/$||')"

  # Ensure endpoint has protocol
  if [[ "${B2_ENDPOINT}" != http://* ]] && [[ "${B2_ENDPOINT}" != https://* ]]; then
    B2_ENDPOINT="https://${B2_ENDPOINT}"
  fi

  # Export AWS CLI credentials for S3 API compatibility
  export AWS_ACCESS_KEY_ID="${B2_KEY_ID}"
  export AWS_SECRET_ACCESS_KEY="${B2_KEY}"
  export AWS_DEFAULT_REGION="${B2_REGION}"
}

# Validate and initialize PostgreSQL connection configuration
# shellcheck disable=SC2034
init_db_config() {
  DATABASE_URL="${DATABASE_URL:-}"
  DB_HOST="${DB_HOST:-}"
  DB_PORT="${DB_PORT:-5432}"
  DB_NAME="${DB_NAME:-}"
  DB_USER="${DB_USER:-}"
  DB_PASSWORD="${DB_PASSWORD:-}"

  if [[ -z "${DATABASE_URL}" ]] && { [[ -z "${DB_HOST}" ]] || [[ -z "${DB_NAME}" ]] || [[ -z "${DB_USER}" ]]; }; then
    log_error "Database connection parameters missing. Provide DATABASE_URL or DB_HOST, DB_NAME, and DB_USER."
    exit 1
  fi

  if [[ -n "${DATABASE_URL}" ]]; then
    DUMP_TARGET=("${DATABASE_URL}")
    RESTORE_TARGET=("-d" "${DATABASE_URL}")
    # Extract DB name from URL if possible for filename tagging
    IDENTIFIER="$(echo "${DATABASE_URL}" | sed -E 's/.*\///; s/\?.*//')"
    if [[ -z "${IDENTIFIER}" ]]; then
      IDENTIFIER="postgres"
    fi
  else
    if [[ -n "${DB_PASSWORD}" ]]; then
      export PGPASSWORD="${DB_PASSWORD}"
    fi
    DUMP_TARGET=("-h" "${DB_HOST}" "-p" "${DB_PORT}" "-U" "${DB_USER}" "-d" "${DB_NAME}")
    RESTORE_TARGET=("-h" "${DB_HOST}" "-p" "${DB_PORT}" "-U" "${DB_USER}" "-d" "${DB_NAME}")
    IDENTIFIER="${DB_NAME}"
  fi
}

# Verify database reachability
check_db_connectivity() {
  log_info "Verifying PostgreSQL connectivity..."
  if [[ -n "${DATABASE_URL:-}" ]]; then
    pg_isready -d "${DATABASE_URL}" -t 15 || {
      log_error "PostgreSQL database is not reachable at DATABASE_URL"
      exit 1
    }
  else
    pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -t 15 || {
      log_error "PostgreSQL database is not reachable at ${DB_HOST}:${DB_PORT}/${DB_NAME}"
      exit 1
    }
  fi
}
