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
# Usage and option parsing tests
# ------------------------------------------------------------------------------
@test "restore: fails with usage when called without arguments" {
  run "${REPO_ROOT}/scripts/restore.sh"
  assert_failure 1
  assert_output --partial "Usage: restore.sh [OPTIONS]"
}

@test "restore: displays usage on --help or -h" {
  run "${REPO_ROOT}/scripts/restore.sh" --help
  assert_failure 1
  assert_output --partial "Usage: restore.sh [OPTIONS]"

  run "${REPO_ROOT}/scripts/restore.sh" -h
  assert_failure 1
  assert_output --partial "Usage: restore.sh [OPTIONS]"
}

@test "restore: fails on unknown options" {
  run "${REPO_ROOT}/scripts/restore.sh" --invalid-flag
  assert_failure 1
  assert_output --partial "Unknown option: --invalid-flag"
  assert_output --partial "Usage: restore.sh [OPTIONS]"
}

# ------------------------------------------------------------------------------
# Action: --list
# ------------------------------------------------------------------------------
@test "restore: lists available snapshots with --list" {
  run "${REPO_ROOT}/scripts/restore.sh" --list
  assert_success
  assert_output --partial "Available snapshots in s3://test-bucket/backups/test/:"

  run cat "${TEST_TMP_DIR}/aws.log"
  assert_output --partial "s3 ls s3://test-bucket/backups/test/"
}

# ------------------------------------------------------------------------------
# Action: --latest
# ------------------------------------------------------------------------------
@test "restore: restores latest snapshot with --latest" {
  # Mock aws s3 ls returning sorted snapshot list
  cat <<'EOF' > "${MOCK_BIN}/aws"
#!/usr/bin/env bash
if [ ! -t 0 ]; then cat > /dev/null; fi
echo "$*" >> "${TEST_TMP_DIR}/aws.log"
if [[ "$*" == *"s3 ls s3://test-bucket/backups/test/"* ]]; then
  echo "2026-10-01 02:00:00 50000000 app_production_20261001_020000Z.dump"
  echo "2026-10-02 02:00:00 50000000 app_production_20261002_020000Z.dump"
  exit 0
fi
exit 0
EOF
  chmod +x "${MOCK_BIN}/aws"

  run "${REPO_ROOT}/scripts/restore.sh" --latest
  assert_success
  assert_output --partial "Finding latest snapshot in s3://test-bucket/backups/test/..."
  assert_output --partial "Latest snapshot identified: app_production_20261002_020000Z.dump"
  assert_output --partial "Downloading s3://test-bucket/backups/test/app_production_20261002_020000Z.dump"
  assert_output --partial "Restoring database schema and data via pg_restore..."
  assert_output --partial "Database restore completed successfully from app_production_20261002_020000Z.dump!"

  # Check that pg_restore was invoked
  run cat "${TEST_TMP_DIR}/pg_restore.log"
  assert_output --partial "-d postgresql://user:pass@localhost:5432/app_production"
  assert_output --partial "--clean --if-exists --no-owner --no-privileges --verbose /tmp/app_production_20261002_020000Z.dump"
}

@test "restore: fails if --latest finds no snapshots in bucket" {
  cat <<'EOF' > "${MOCK_BIN}/aws"
#!/usr/bin/env bash
if [ ! -t 0 ]; then cat > /dev/null; fi
echo "$*" >> "${TEST_TMP_DIR}/aws.log"
exit 0
EOF
  chmod +x "${MOCK_BIN}/aws"

  run "${REPO_ROOT}/scripts/restore.sh" --latest
  assert_failure 1
  assert_output --partial "No snapshots found in s3://test-bucket/backups/test/"
}

# ------------------------------------------------------------------------------
# Action: --file
# ------------------------------------------------------------------------------
@test "restore: restores specified snapshot file with --file" {
  run "${REPO_ROOT}/scripts/restore.sh" --file "app_custom_20260930.dump"
  assert_success
  assert_output --partial "Downloading s3://test-bucket/backups/test/app_custom_20260930.dump"
  assert_output --partial "Database restore completed successfully from app_custom_20260930.dump!"

  run cat "${TEST_TMP_DIR}/aws.log"
  assert_output --partial "s3 cp s3://test-bucket/backups/test/app_custom_20260930.dump /tmp/app_custom_20260930.dump"

  run cat "${TEST_TMP_DIR}/pg_restore.log"
  assert_output --partial "/tmp/app_custom_20260930.dump"
}

@test "restore: fails if --file is missing argument" {
  run "${REPO_ROOT}/scripts/restore.sh" --file
  assert_failure 1
  assert_output --partial "Option --file requires a filename argument"
}
