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
  export DR_VERIFY_QUERY="SELECT 1 FROM users;"
}

teardown() {
  teardown_test_sandbox
}

# ------------------------------------------------------------------------------
# CLI options and usage
# ------------------------------------------------------------------------------
@test "dr_test: displays usage on --help or -h" {
  run "${REPO_ROOT}/scripts/dr_test.sh" --help
  assert_failure 1
  assert_output --partial "Usage: dr_test.sh [OPTIONS]"

  run "${REPO_ROOT}/scripts/dr_test.sh" -h
  assert_failure 1
  assert_output --partial "Usage: dr_test.sh [OPTIONS]"
}

@test "dr_test: fails on unknown options" {
  run "${REPO_ROOT}/scripts/dr_test.sh" --unknown
  assert_failure 1
  assert_output --partial "Unknown option: --unknown"
  assert_output --partial "Usage: dr_test.sh [OPTIONS]"
}

@test "dr_test: fails if --file is missing argument" {
  run "${REPO_ROOT}/scripts/dr_test.sh" --file
  assert_failure 1
  assert_output --partial "Option --file requires a filename argument"
}

@test "dr_test: fails if DR_VERIFY_QUERY is not set" {
  unset DR_VERIFY_QUERY

  run "${REPO_ROOT}/scripts/dr_test.sh" --latest
  assert_failure 1
  assert_output --partial "Missing required environment variable: DR_VERIFY_QUERY"
}

# ------------------------------------------------------------------------------
# Snapshot discovery
# ------------------------------------------------------------------------------
@test "dr_test: fails if latest snapshot cannot be found in bucket" {
  cat <<'EOF' > "${MOCK_BIN}/aws"
#!/usr/bin/env bash
if [ ! -t 0 ]; then cat > /dev/null; fi
echo "$*" >> "${TEST_TMP_DIR}/aws.log"
exit 0
EOF
  chmod +x "${MOCK_BIN}/aws"

  run "${REPO_ROOT}/scripts/dr_test.sh" --latest
  assert_failure 1
  assert_output --partial "No snapshots found in s3://test-bucket/backups/test/"
}

# ------------------------------------------------------------------------------
# Full drill execution with auto-created test database
# ------------------------------------------------------------------------------
@test "dr_test: executes automated drill, verifies tables, and tears down test database (DATABASE_URL)" {
  export HEALTHCHECK_URL="https://hc-ping.com/dr-test-id"

  cat <<'EOF' > "${MOCK_BIN}/aws"
#!/usr/bin/env bash
if [ ! -t 0 ]; then cat > /dev/null; fi
echo "$*" >> "${TEST_TMP_DIR}/aws.log"
if [[ "$*" == *"s3 ls s3://test-bucket/backups/test/"* ]]; then
  echo "2026-10-02 02:00:00 50000000 app_production_20261002_020000Z.dump"
  exit 0
fi
exit 0
EOF
  chmod +x "${MOCK_BIN}/aws"

  # Mock psql to return 5 tables for table count query
  cat <<'EOF' > "${MOCK_BIN}/psql"
#!/usr/bin/env bash
if [ ! -t 0 ]; then cat > /dev/null; fi
echo "$*" >> "${TEST_TMP_DIR}/psql.log"
if [[ "$*" == *"information_schema.tables"* ]]; then
  echo "5"
  exit 0
fi
exit 0
EOF
  chmod +x "${MOCK_BIN}/psql"

  export DR_VERIFY_QUERY="SELECT 1 FROM users LIMIT 1;"

  run "${REPO_ROOT}/scripts/dr_test.sh" --latest
  assert_success
  assert_output --partial "Starting automated disaster recovery drill..."
  assert_output --partial "Target snapshot identified: app_production_20261002_020000Z.dump"
  assert_output --partial "Provisioning temporary isolated test database: dr_test_app_production_"
  assert_output --partial "Restoration verified: 5 table(s) found in public schema."
  assert_output --partial "Running custom verification query: SELECT 1 FROM users LIMIT 1;"
  assert_output --partial "Disaster recovery drill passed successfully!"
  assert_output --partial "Tearing down temporary test database: dr_test_app_production_"

  # Verify psql CREATE and DROP were called
  run cat "${TEST_TMP_DIR}/psql.log"
  assert_output --partial "CREATE DATABASE \"dr_test_app_production_"
  assert_output --partial "DROP DATABASE IF EXISTS \"dr_test_app_production_"
  assert_output --partial "SELECT 1 FROM users LIMIT 1;"

  # Verify healthcheck was called
  run cat "${TEST_TMP_DIR}/curl.log"
  assert_output --partial "https://hc-ping.com/dr-test-id/start"
  assert_output --partial "Disaster recovery drill passed successfully!"
}

# ------------------------------------------------------------------------------
# Full drill execution with individual DB env vars and explicit DR_DATABASE_URL
# ------------------------------------------------------------------------------
@test "dr_test: executes drill with explicit DR_DATABASE_URL and individual db variables" {
  unset DATABASE_URL
  export DB_HOST="db.internal"
  export DB_PORT="5432"
  export DB_USER="backup_user"
  export DB_NAME="primary_app"
  export DB_PASSWORD="db_pass"
  export DR_DATABASE_URL="postgresql://backup_user:db_pass@db.internal:5432/dr_sandbox"

  cat <<'EOF' > "${MOCK_BIN}/psql"
#!/usr/bin/env bash
if [ ! -t 0 ]; then cat > /dev/null; fi
echo "$*" >> "${TEST_TMP_DIR}/psql.log"
if [[ "$*" == *"information_schema.tables"* ]]; then
  echo "3"
  exit 0
fi
exit 0
EOF
  chmod +x "${MOCK_BIN}/psql"

  run "${REPO_ROOT}/scripts/dr_test.sh" --file "primary_app_custom.dump"
  assert_success
  assert_output --partial "Using explicit disaster recovery target database: postgresql://backup_user:db_pass@db.internal:5432/dr_sandbox"
  assert_output --partial "Restoration verified: 3 table(s) found in public schema."
  assert_output --partial "Disaster recovery drill passed successfully!"
  refute_output --partial "Tearing down temporary test database:"
}

# ------------------------------------------------------------------------------
# Failure alerting and teardown on verification failure
# ------------------------------------------------------------------------------
@test "dr_test: fails and dispatches alerts when no tables are found in restored database" {
  export HEALTHCHECK_URL="https://hc-ping.com/dr-test-id"

  cat <<'EOF' > "${MOCK_BIN}/psql"
#!/usr/bin/env bash
if [ ! -t 0 ]; then cat > /dev/null; fi
echo "$*" >> "${TEST_TMP_DIR}/psql.log"
if [[ "$*" == *"information_schema.tables"* ]]; then
  echo "0"
  exit 0
fi
exit 0
EOF
  chmod +x "${MOCK_BIN}/psql"

  run "${REPO_ROOT}/scripts/dr_test.sh" --file "empty.dump"
  assert_failure 1
  assert_output --partial "Disaster recovery verification failed: no tables found in restored database!"
  assert_output --partial "Tearing down temporary test database:"

  # Verify alert was dispatched to healthcheck
  run cat "${TEST_TMP_DIR}/curl.log"
  assert_output --partial "https://hc-ping.com/dr-test-id/fail"
  assert_output --partial "Disaster recovery drill failed for app_production with exit code 1"
}

@test "dr_test: executes drill with auto-created test database using individual db variables" {
  unset DATABASE_URL
  export DB_HOST="db.internal"
  export DB_PORT="5432"
  export DB_USER="backup_user"
  export DB_NAME="primary_app"
  export DB_PASSWORD="db_pass"

  cat <<'EOF' > "${MOCK_BIN}/psql"
#!/usr/bin/env bash
if [ ! -t 0 ]; then cat > /dev/null; fi
echo "$*" >> "${TEST_TMP_DIR}/psql.log"
if [[ "$*" == *"information_schema.tables"* ]]; then
  echo "2"
  exit 0
fi
exit 0
EOF
  chmod +x "${MOCK_BIN}/psql"

  run "${REPO_ROOT}/scripts/dr_test.sh" --file "primary_app.dump"
  assert_success
  assert_output --partial "Provisioning temporary isolated test database: dr_test_primary_app_"
  assert_output --partial "Tearing down temporary test database: dr_test_primary_app_"
}

@test "dr_test: fails and tears down test database when CREATE DATABASE fails" {
  unset DATABASE_URL
  export DB_HOST="db.internal"
  export DB_PORT="5432"
  export DB_USER="backup_user"
  export DB_NAME="primary_app"
  export DB_PASSWORD="db_pass"

  # Force psql CREATE DATABASE failure
  export MOCK_PSQL_FAIL=1

  run "${REPO_ROOT}/scripts/dr_test.sh" --file "primary_app.dump"
  assert_failure 1
  assert_output --partial "Disaster recovery drill failed for primary_app"
}
