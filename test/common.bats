#!/usr/bin/env bats

load "../node_modules/bats-support/load"
load "../node_modules/bats-assert/load"
load "test_helper.bash"

setup() {
  setup_test_sandbox
  source "${REPO_ROOT}/scripts/common.sh"
}

teardown() {
  teardown_test_sandbox
}

# ------------------------------------------------------------------------------
# Logging tests
# ------------------------------------------------------------------------------
@test "common: log helpers output formatted messages" {
  run log_info "test info message"
  assert_success
  assert_output --partial "[INFO] test info message"

  run log_success "test success message"
  assert_success
  assert_output --partial "[SUCCESS] test success message"

  run log_warn "test warning message"
  assert_success
  assert_output --partial "[WARN] test warning message"

  run log_error "test error message"
  assert_success
  assert_output --partial "[ERROR] test error message"
}

# ------------------------------------------------------------------------------
# Healthcheck tests
# ------------------------------------------------------------------------------
@test "common: notify_healthcheck does nothing if HEALTHCHECK_URL is not set" {
  unset HEALTHCHECK_URL
  run notify_healthcheck "start"
  assert_success
  assert [ ! -f "${TEST_TMP_DIR}/curl.log" ]
}

@test "common: notify_healthcheck calls curl for start, success, fail" {
  export HEALTHCHECK_URL="https://hc-ping.com/fake-uuid"

  notify_healthcheck "start"
  run cat "${TEST_TMP_DIR}/curl.log"
  assert_output --partial "https://hc-ping.com/fake-uuid/start"

  notify_healthcheck "success" "Backup OK"
  run cat "${TEST_TMP_DIR}/curl.log"
  assert_output --partial "--data-raw Backup OK https://hc-ping.com/fake-uuid"

  notify_healthcheck "fail" "Backup Failed"
  run cat "${TEST_TMP_DIR}/curl.log"
  assert_output --partial "--data-raw Backup Failed https://hc-ping.com/fake-uuid/fail"

  # Unknown state should not invoke curl
  rm -f "${TEST_TMP_DIR}/curl.log"
  notify_healthcheck "unknown" "something"
  assert [ ! -f "${TEST_TMP_DIR}/curl.log" ]
}

@test "common: notify_healthcheck does not fail script if curl fails" {
  export HEALTHCHECK_URL="https://hc-ping.com/fake-uuid"
  export MOCK_CURL_FAIL=1

  run notify_healthcheck "start"
  assert_success
}

@test "common: notify_healthcheck supports custom target url" {
  unset HEALTHCHECK_URL
  notify_healthcheck "start" "" "https://hc-ping.com/custom-url"
  run cat "${TEST_TMP_DIR}/curl.log"
  assert_output --partial "https://hc-ping.com/custom-url/start"
}


# ------------------------------------------------------------------------------
# B2 configuration tests
# ------------------------------------------------------------------------------
@test "common: init_b2_config fails if credentials are missing" {
  unset B2_APPLICATION_KEY_ID AWS_ACCESS_KEY_ID
  unset B2_APPLICATION_KEY AWS_SECRET_ACCESS_KEY

  run init_b2_config
  assert_failure 1
  assert_output --partial "Missing Backblaze B2 credentials"
}

@test "common: init_b2_config fails if endpoint is missing" {
  export B2_APPLICATION_KEY_ID="test_id"
  export B2_APPLICATION_KEY="test_key"
  unset B2_ENDPOINT AWS_ENDPOINT_URL

  run init_b2_config
  assert_failure 1
  assert_output --partial "Missing Backblaze B2 endpoint"
}

@test "common: init_b2_config fails if bucket is missing" {
  export B2_APPLICATION_KEY_ID="test_id"
  export B2_APPLICATION_KEY="test_key"
  export B2_ENDPOINT="s3.us-west-004.backblazeb2.com"
  unset B2_BUCKET

  run init_b2_config
  assert_failure 1
  assert_output --partial "Missing B2 bucket name"
}

@test "common: init_b2_config initializes environment and exports AWS variables" {
  export B2_APPLICATION_KEY_ID="my_key_id"
  export B2_APPLICATION_KEY="my_secret_key"
  export B2_ENDPOINT="s3.us-west-004.backblazeb2.com"
  export B2_BUCKET="my-backup-bucket"
  export B2_PREFIX="/custom/prefix/"
  export B2_REGION="us-west-004"

  init_b2_config

  assert_equal "${AWS_ACCESS_KEY_ID}" "my_key_id"
  assert_equal "${AWS_SECRET_ACCESS_KEY}" "my_secret_key"
  assert_equal "${AWS_DEFAULT_REGION}" "us-west-004"
  assert_equal "${B2_PREFIX}" "custom/prefix"
  assert_equal "${B2_ENDPOINT}" "https://s3.us-west-004.backblazeb2.com"
}

@test "common: init_b2_config preserves http/https if present" {
  export B2_APPLICATION_KEY_ID="id"
  export B2_APPLICATION_KEY="key"
  export B2_BUCKET="bucket"
  export B2_ENDPOINT="http://localhost:9000"

  init_b2_config
  assert_equal "${B2_ENDPOINT}" "http://localhost:9000"
}

# ------------------------------------------------------------------------------
# DB configuration tests
# ------------------------------------------------------------------------------
@test "common: init_db_config fails if no database connection info provided" {
  unset DATABASE_URL DB_HOST DB_NAME DB_USER

  run init_db_config
  assert_failure 1
  assert_output --partial "Database connection parameters missing"
}

@test "common: init_db_config configures targets from DATABASE_URL" {
  export DATABASE_URL="postgresql://user:pass@localhost:5432/my_production_db"

  init_db_config
  assert_equal "${IDENTIFIER}" "my_production_db"
  assert_equal "${DUMP_TARGET[0]}" "postgresql://user:pass@localhost:5432/my_production_db"
  assert_equal "${RESTORE_TARGET[0]}" "-d"
  assert_equal "${RESTORE_TARGET[1]}" "postgresql://user:pass@localhost:5432/my_production_db"
}

@test "common: init_db_config defaults identifier to postgres if url has no path" {
  export DATABASE_URL="postgresql://user:pass@localhost:5432/"

  init_db_config
  assert_equal "${IDENTIFIER}" "postgres"
}

@test "common: init_db_config configures targets from individual environment variables" {
  unset DATABASE_URL
  export DB_HOST="db.internal"
  export DB_PORT="5433"
  export DB_NAME="custom_db"
  export DB_USER="db_user"
  export DB_PASSWORD="secure_password"

  init_db_config
  assert_equal "${IDENTIFIER}" "custom_db"
  assert_equal "${PGPASSWORD}" "secure_password"
  assert_equal "${DUMP_TARGET[*]}" "-h db.internal -p 5433 -U db_user -d custom_db"
  assert_equal "${RESTORE_TARGET[*]}" "-h db.internal -p 5433 -U db_user -d custom_db"
}

# ------------------------------------------------------------------------------
# Database connectivity check tests
# ------------------------------------------------------------------------------
@test "common: check_db_connectivity succeeds when pg_isready succeeds (DATABASE_URL)" {
  export DATABASE_URL="postgresql://localhost:5432/test"
  run check_db_connectivity
  assert_success
  assert_output --partial "Verifying PostgreSQL connectivity..."
}

@test "common: check_db_connectivity fails when pg_isready fails (DATABASE_URL)" {
  export DATABASE_URL="postgresql://localhost:5432/test"
  export MOCK_PG_ISREADY_FAIL=1

  run check_db_connectivity
  assert_failure 1
  assert_output --partial "PostgreSQL database is not reachable at DATABASE_URL"
}

@test "common: check_db_connectivity succeeds when pg_isready succeeds (individual vars)" {
  unset DATABASE_URL
  export DB_HOST="localhost"
  export DB_PORT="5432"
  export DB_NAME="test"
  export DB_USER="user"

  run check_db_connectivity
  assert_success
}

@test "common: check_db_connectivity fails when pg_isready fails (individual vars)" {
  unset DATABASE_URL
  export DB_HOST="localhost"
  export DB_PORT="5432"
  export DB_NAME="test"
  export DB_USER="user"
  export MOCK_PG_ISREADY_FAIL=1

  run check_db_connectivity
  assert_failure 1
  assert_output --partial "PostgreSQL database is not reachable at localhost:5432/test"
}
