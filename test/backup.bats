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

# ------------------------------------------------------------------------------
# Retention cleanup tests
# ------------------------------------------------------------------------------
@test "backup: retention cleanup ignores pruning when RETENTION_DAYS is 0" {
  export RETENTION_DAYS="0"

  run "${REPO_ROOT}/scripts/backup.sh"
  assert_success
  refute_output --partial "Pruning snapshots older than"
}

@test "backup: retention cleanup prunes expired snapshots and keeps recent ones" {
  export RETENTION_DAYS="14"

  # Custom aws mock that returns a simulated file list for "s3 ls s3://..."
  cat <<'EOF' > "${MOCK_BIN}/aws"
#!/usr/bin/env bash
if [ ! -t 0 ]; then cat > /dev/null; fi
echo "$*" >> "${TEST_TMP_DIR}/aws.log"
if [[ "$*" == *"s3 ls s3://test-bucket/backups/test/"* ]]; then
  echo "2020-01-01 02:00:00 50000000 app_production_20200101_020000Z.dump"
  echo "2099-01-01 02:00:00 50000000 app_production_20990101_020000Z.dump"
  echo "2020-01-01 02:00:00 50000000 non_matching_snapshot.dump"
  exit 0
fi
exit 0
EOF
  chmod +x "${MOCK_BIN}/aws"

  run "${REPO_ROOT}/scripts/backup.sh"
  assert_success
  assert_output --partial "Pruning snapshots older than 14 days"
  assert_output --partial "Deleting expired snapshot: app_production_20200101_020000Z.dump"
  refute_output --partial "Deleting expired snapshot: app_production_20990101_020000Z.dump"
  refute_output --partial "Deleting expired snapshot: non_matching_snapshot.dump"

  # Check that s3 rm was invoked for the expired file
  run cat "${TEST_TMP_DIR}/aws.log"
  assert_output --partial "s3 rm s3://test-bucket/backups/test/app_production_20200101_020000Z.dump"
  refute_output --partial "s3 rm s3://test-bucket/backups/test/app_production_20990101_020000Z.dump"
}
