#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# seleimend-db-backup: Container Entrypoint
# ==============================================================================
# Dispatches between one-off execution (default in Kubernetes CronJobs) and
# scheduled daemon execution (via supercronic for Docker Compose).
# ==============================================================================

if [ $# -gt 0 ]; then
  case "$1" in
    backup)
      shift
      exec /scripts/backup.sh "$@"
      ;;
    restore)
      shift
      exec /scripts/restore.sh "$@"
      ;;
    *)
      exec "$@"
      ;;
  esac
fi

# If CRON_SCHEDULE is defined, run as a daemon using supercronic
if [ -n "${CRON_SCHEDULE:-}" ]; then
  echo "==> [Entrypoint] CRON_SCHEDULE is defined: '${CRON_SCHEDULE}'"
  echo "==> [Entrypoint] Initializing supercronic daemon mode..."

  CRONTAB_FILE="/tmp/crontab"
  echo "${CRON_SCHEDULE} /scripts/backup.sh" > "${CRONTAB_FILE}"

  echo "==> [Entrypoint] Starting supercronic with crontab:"
  cat "${CRONTAB_FILE}"
  exec supercronic "${CRONTAB_FILE}"
fi

# Default: execute a single backup run and exit (Kubernetes CronJob pattern)
echo "==> [Entrypoint] No CRON_SCHEDULE specified. Running single backup execution..."
exec /scripts/backup.sh
