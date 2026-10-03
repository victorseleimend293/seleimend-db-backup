#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

COVERAGE_DIR="${PROJECT_ROOT}/coverage"
mkdir -p "${COVERAGE_DIR}"
rm -f "${COVERAGE_DIR}/trace.log"
touch "${COVERAGE_DIR}/trace.log"

echo "==> Instrumenting scripts for code coverage tracking..."
node test/instrument.mjs

export COVERAGE_MODE=1
export COVERAGE_TRACE_FILE="${COVERAGE_DIR}/trace.log"

echo "==> Running Bats test suite with line execution tracking..."
pnpm exec bats test/common.bats test/backup.bats test/restore.bats test/entrypoint.bats

echo "==> Analyzing coverage against 100% threshold..."
node test/analyze_coverage.mjs
