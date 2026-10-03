#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# seleimend-db-backup: Backblaze B2 Automated Provisioning via Terraform
# ==============================================================================
# Uses container environment variables to automatically provision or update the
# Backblaze B2 bucket, applying default server-side encryption (SSE-B2 / AES-256)
# and bucket lifecycle rules for retention.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

AUTO_PROVISION_B2="${AUTO_PROVISION_B2:-true}"

if [[ "${AUTO_PROVISION_B2}" = "false" ]]; then
  log_info "Backblaze B2 auto-provisioning is disabled (AUTO_PROVISION_B2=false)."
  exit 0
fi

log_info "Initializing Backblaze B2 auto-provisioning via Terraform..."
init_b2_config

TF_TEMPLATE_DIR="${TF_TEMPLATE_DIR:-}"
if [[ -z "${TF_TEMPLATE_DIR}" ]]; then
  TF_TEMPLATE_DIR="$(cd "${SCRIPT_DIR}/terraform" 2> /dev/null && pwd || cd "${SCRIPT_DIR}/../terraform" 2> /dev/null && pwd || echo "")"
fi

if [[ -z "${TF_TEMPLATE_DIR}" ]] || [[ ! -d "${TF_TEMPLATE_DIR}" ]]; then
  log_warn "Terraform template directory not found. Skipping auto-provisioning."
  exit 0
fi

WORK_DIR="${TF_WORK_DIR:-/tmp/terraform}"
mkdir -p "${WORK_DIR}"
rm -rf "${WORK_DIR:?}"/*
cp -r "${TF_TEMPLATE_DIR}"/* "${WORK_DIR}/"

# shellcheck disable=SC2154
STATE_S3="s3://${B2_BUCKET}/.terraform/terraform.tfstate"

# Attempt to pull existing state from S3 if available
log_info "Checking for existing Terraform state in ${STATE_S3}..."
# shellcheck disable=SC2154
aws --endpoint-url="${B2_ENDPOINT}" s3 cp "${STATE_S3}" "${WORK_DIR}/terraform.tfstate" > /dev/null 2>&1 || true

# Export Terraform variables
# shellcheck disable=SC2154
export TF_VAR_b2_application_key_id="${B2_KEY_ID}"
# shellcheck disable=SC2154
export TF_VAR_b2_application_key="${B2_KEY}"
export TF_VAR_bucket_name="${B2_BUCKET}"
export TF_VAR_retention_days="${RETENTION_DAYS:-30}"
export TF_VAR_enable_b2_encryption="${ENABLE_B2_ENCRYPTION:-true}"
# shellcheck disable=SC2154
export TF_VAR_backup_prefix="${B2_PREFIX}"
export TF_VAR_create_app_key="false"

log_info "Applying Backblaze B2 bucket configuration (Bucket: ${B2_BUCKET}, Retention: ${RETENTION_DAYS:-30} days)..."
terraform -chdir="${WORK_DIR}" init -backend=false -input=false
terraform -chdir="${WORK_DIR}" apply -auto-approve -input=false

# Sync state file back to B2
if [[ -f "${WORK_DIR}/terraform.tfstate" ]]; then
  log_info "Persisting updated Terraform state to ${STATE_S3}..."
  aws --endpoint-url="${B2_ENDPOINT}" s3 cp "${WORK_DIR}/terraform.tfstate" "${STATE_S3}" > /dev/null 2>&1 || true
fi

log_success "Backblaze B2 bucket '${B2_BUCKET}' successfully configured with SSE-B2 encryption and lifecycle rules!"
