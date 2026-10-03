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
# Backup standard flow
# ------------------------------------------------------------------------------
@test "backup: executes complete streaming backup successfully" {
  export HEALTHCHECK_URL="https://hc-ping.com/fake-id"

  run "${REPO_ROOT}/scripts/backup.sh"
  assert_success
  assert_output --partial "Starting database backup procedure..."
  assert_output --partial "Target snapshot: s3://test-bucket/backups/test/app_production_"
  assert_output --partial "Successfully backed up app_production"

  # Verify pg_dump and aws were invoked
  run cat "${TEST_TMP_DIR}/pg_dump.log"
  assert_output --partial "postgresql://user:pass@localhost:5432/app_production"
  assert_output --partial "--format=custom --blobs --verbose --no-owner --no-privileges"

  run cat "${TEST_TMP_DIR}/aws.log"
  assert_output --partial "s3 cp - s3://test-bucket/backups/test/app_production_"

  # Verify healthcheck was called
  run cat "${TEST_TMP_DIR}/curl.log"
  assert_output --partial "https://hc-ping.com/fake-id/start"
  assert_output --partial "Successfully backed up app_production"
}

# ------------------------------------------------------------------------------
# Error handling and trapping
# ------------------------------------------------------------------------------
@test "backup: traps error and notifies healthcheck when pg_dump fails" {
  export HEALTHCHECK_URL="https://hc-ping.com/fake-id"
  export MOCK_PG_DUMP_FAIL=1

  run "${REPO_ROOT}/scripts/backup.sh"
  assert_failure 1
  assert_output --partial "Backup failed at line"

  run cat "${TEST_TMP_DIR}/curl.log"
  assert_output --partial "https://hc-ping.com/fake-id/fail"
}

@test "backup: traps error when aws s3 cp fails" {
  export MOCK_AWS_FAIL=2

  run "${REPO_ROOT}/scripts/backup.sh"
  assert_failure 2
  assert_output --partial "Backup failed at line"
}

