#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# seleimend-db-backup: Container Entrypoint
# ==============================================================================
# Dispatches between one-off execution (default in Kubernetes CronJobs) and
# scheduled daemon execution (via supercronic for Docker Compose).
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

if [[ $# -gt 0 ]]; then
  case "$1" in
    backup)
      shift
      exec "${SCRIPT_DIR}/backup.sh" "$@"
      ;;
    restore)
      shift
      exec "${SCRIPT_DIR}/restore.sh" "$@"
      ;;
    *)
      exec "$@"
      ;;
  esac
fi

# If CRON_SCHEDULE is defined, run as a daemon using supercronic
if [[ -n "${CRON_SCHEDULE:-}" ]]; then
  log_info "CRON_SCHEDULE is defined: '${CRON_SCHEDULE}'"
  log_info "Initializing supercronic daemon mode..."

  CRONTAB_FILE="/tmp/crontab"
  echo "${CRON_SCHEDULE} ${SCRIPT_DIR}/backup.sh" > "${CRONTAB_FILE}"

  log_info "Starting supercronic with crontab:"
  cat "${CRONTAB_FILE}"
  exec supercronic "${CRONTAB_FILE}"
fi

# Default: execute a single backup run and exit (Kubernetes CronJob pattern)
log_info "No CRON_SCHEDULE specified. Running single backup execution..."
exec "${SCRIPT_DIR}/backup.sh"
