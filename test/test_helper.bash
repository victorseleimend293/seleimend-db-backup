#!/usr/bin/env bash
# ==============================================================================
# Bats Test Helper: Sandbox & Mock Utilities
# ==============================================================================

# Determine repository root
if [[ -n "${COVERAGE_MODE:-}" ]]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/coverage/instrumented" && pwd)"
else
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export REPO_ROOT

setup_test_sandbox() {
  if [[ -n "${BASH_ENV:-}" ]] && [[ -f "${BASH_ENV}" ]]; then
    # shellcheck source=/dev/null
    source "${BASH_ENV}"
  fi

  TEST_TMP_DIR="$(mktemp -d)"
  export TEST_TMP_DIR

  MOCK_BIN="${TEST_TMP_DIR}/mock_bin"
  mkdir -p "${MOCK_BIN}"
  export MOCK_BIN
  export PATH="${MOCK_BIN}:${PATH}"

  # Default mock commands
  create_mock "pg_isready" 0 "postgres:5432 - accepting connections"
  create_mock "pg_dump" 0 "mock_pg_dump_output"
  create_mock "pg_restore" 0 "mock_pg_restore_output"
  create_mock "aws" 0 "mock_aws_output"
  create_mock "curl" 0 ""
  create_mock "supercronic" 0 "mock_supercronic_running"
  create_mock "psql" 0 "1"
  create_mock "terraform" 0 "Apply complete! Resources: 1 added, 0 changed, 0 destroyed."
}

teardown_test_sandbox() {
  if [[ -n "${TEST_TMP_DIR:-}" ]] && [[ -d "${TEST_TMP_DIR}" ]]; then
    rm -rf "${TEST_TMP_DIR}"
  fi
}

create_mock() {
  local cmd_name="$1"
  local exit_code="${2:-0}"
  local output="${3:-}"

  cat << EOF > "${MOCK_BIN}/${cmd_name}"
#!/usr/bin/env bash
# Consume stdin if piped to prevent SIGPIPE in callers
if [ ! -t 0 ]; then
  cat > /dev/null
fi
echo "\$*" >> "\${TEST_TMP_DIR}/${cmd_name}.log"
if [[ -n "\${MOCK_${cmd_name^^}_FAIL:-}" ]]; then
  echo "Mock ${cmd_name} failure" >&2
  exit "\${MOCK_${cmd_name^^}_FAIL}"
fi
if [[ -n "${output}" ]]; then
  echo "${output}"
fi
exit ${exit_code}
EOF
  chmod +x "${MOCK_BIN}/${cmd_name}"
}
