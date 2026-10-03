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
      "${SCRIPT_DIR}/provision_b2.sh"
      exec "${SCRIPT_DIR}/backup.sh" "$@"
      ;;
    restore)
      shift
      exec "${SCRIPT_DIR}/restore.sh" "$@"
      ;;
    dr-test | test-dr)
      shift
      exec "${SCRIPT_DIR}/dr_test.sh" "$@"
      ;;
    *)
      exec "$@"
      ;;
  esac
fi

# Run B2 auto-provisioning
"${SCRIPT_DIR}/provision_b2.sh"

# If CRON_SCHEDULE or DR_SCHEDULE is defined, run as a daemon using supercronic
if [[ -n "${CRON_SCHEDULE:-}" ]] || [[ -n "${DR_SCHEDULE:-}" ]]; then
  log_info "Initializing supercronic daemon mode..."

  CRONTAB_FILE="/tmp/crontab"
  rm -f "${CRONTAB_FILE}"
  touch "${CRONTAB_FILE}"

  if [[ -n "${CRON_SCHEDULE:-}" ]]; then
    log_info "Configuring backup schedule: '${CRON_SCHEDULE}'"
    echo "${CRON_SCHEDULE} ${SCRIPT_DIR}/backup.sh" >> "${CRONTAB_FILE}"
  fi

  if [[ -n "${DR_SCHEDULE:-}" ]]; then
    log_info "Configuring disaster recovery drill schedule: '${DR_SCHEDULE}'"
    echo "${DR_SCHEDULE} ${SCRIPT_DIR}/dr_test.sh" >> "${CRONTAB_FILE}"
  fi

  log_info "Starting supercronic with crontab:"
  cat "${CRONTAB_FILE}"
  exec supercronic "${CRONTAB_FILE}"
fi

# Default: execute a single backup run and exit (Kubernetes CronJob pattern)
log_info "No schedule specified. Running single backup execution..."
exec "${SCRIPT_DIR}/backup.sh"
