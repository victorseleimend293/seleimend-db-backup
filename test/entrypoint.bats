#!/usr/bin/env bats

load "../node_modules/bats-support/load"
load "../node_modules/bats-assert/load"
load "test_helper.bash"

setup() {
  setup_test_sandbox
  export B2_APPLICATION_KEY_ID="test_key_id"
  export B2_APPLICATION_KEY="test_secret_key"
  export B2_ENDPOINT="s3.us-west-004.backblazeb2.com"
  export B2_BUCKET="test-bucket"
  export B2_PREFIX="backups/test"
  export DATABASE_URL="postgresql://user:pass@localhost:5432/app_production"
}

teardown() {
  teardown_test_sandbox
}

# ------------------------------------------------------------------------------
# Dispatch tests
# ------------------------------------------------------------------------------
@test "entrypoint: dispatches 'backup' to backup.sh" {
  run "${REPO_ROOT}/scripts/entrypoint.sh" backup
  assert_success
  assert_output --partial "Starting database backup procedure..."
  assert_output --partial "Successfully backed up app_production"
}

@test "entrypoint: dispatches 'restore' to restore.sh" {
  run "${REPO_ROOT}/scripts/entrypoint.sh" restore --list
  assert_success
  assert_output --partial "Available snapshots in s3://test-bucket/backups/test/:"
}

@test "entrypoint: dispatches arbitrary commands directly" {
  run "${REPO_ROOT}/scripts/entrypoint.sh" echo "custom command executed"
  assert_success
  assert_output "custom command executed"
}

# ------------------------------------------------------------------------------
# Daemon / Supercronic tests
# ------------------------------------------------------------------------------
@test "entrypoint: starts supercronic daemon when CRON_SCHEDULE is set" {
  export CRON_SCHEDULE="*/15 * * * *"

  run "${REPO_ROOT}/scripts/entrypoint.sh"
  assert_success
  assert_output --partial "CRON_SCHEDULE is defined: '*/15 * * * *'"
  assert_output --partial "Initializing supercronic daemon mode..."
  assert_output --partial "Starting supercronic with crontab:"
  assert_output --partial "*/15 * * * * ${REPO_ROOT}/scripts/backup.sh"

  run cat "${TEST_TMP_DIR}/supercronic.log"
  assert_output --partial "/tmp/crontab"
}

# ------------------------------------------------------------------------------
# Default mode tests
# ------------------------------------------------------------------------------
@test "entrypoint: defaults to single backup execution when no CRON_SCHEDULE specified" {
  unset CRON_SCHEDULE

  run "${REPO_ROOT}/scripts/entrypoint.sh"
  assert_success
  assert_output --partial "No CRON_SCHEDULE specified. Running single backup execution..."
  assert_output --partial "Starting database backup procedure..."
  assert_output --partial "Successfully backed up app_production"
}
