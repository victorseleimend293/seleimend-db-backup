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
}

teardown() {
  teardown_test_sandbox
}

# ------------------------------------------------------------------------------
# Feature toggle tests
# ------------------------------------------------------------------------------
@test "provision_b2: skips provisioning when AUTO_PROVISION_B2 is false" {
  export AUTO_PROVISION_B2="false"

  run "${REPO_ROOT}/scripts/provision_b2.sh"
  assert_success
  assert_output --partial "Backblaze B2 auto-provisioning is disabled (AUTO_PROVISION_B2=false)."
}

# ------------------------------------------------------------------------------
# Missing template directory handling
# ------------------------------------------------------------------------------
@test "provision_b2: warns and exits gracefully when terraform template directory is missing" {
  export AUTO_PROVISION_B2="true"
  export TF_TEMPLATE_DIR="${TEST_TMP_DIR}/nonexistent_template_dir"

  run "${REPO_ROOT}/scripts/provision_b2.sh"
  assert_success
  assert_output --partial "Terraform template directory not found. Skipping auto-provisioning."
}

# ------------------------------------------------------------------------------
# Complete provisioning workflow
# ------------------------------------------------------------------------------
@test "provision_b2: successfully provisions bucket, applies lifecycle and SSE-B2, and syncs state" {
  export AUTO_PROVISION_B2="true"
  export RETENTION_DAYS="45"
  export ENABLE_B2_ENCRYPTION="true"
  export TF_WORK_DIR="${TEST_TMP_DIR}/tf_work"

  # Mock terraform to touch state file upon apply inside -chdir directory
  cat <<'EOF' > "${MOCK_BIN}/terraform"
#!/usr/bin/env bash
echo "$*" >> "${TEST_TMP_DIR}/terraform.log"
workdir=""
for arg in "$@"; do
  if [[ "$arg" == -chdir=* ]]; then
    workdir="${arg#-chdir=}"
  fi
done
if [[ "$*" == *"apply"* ]] && [[ -n "$workdir" ]]; then
  echo '{"version": 4, "terraform_version": "1.9.8"}' > "${workdir}/terraform.tfstate"
fi
echo "Apply complete! Resources: 1 added, 0 changed, 0 destroyed."
exit 0
EOF
  chmod +x "${MOCK_BIN}/terraform"

  run "${REPO_ROOT}/scripts/provision_b2.sh"
  assert_success
  assert_output --partial "Initializing Backblaze B2 auto-provisioning via Terraform..."
  assert_output --partial "Checking for existing Terraform state in s3://test-bucket/.terraform/terraform.tfstate..."
  assert_output --partial "Applying Backblaze B2 bucket configuration (Bucket: test-bucket, Retention: 45 days)..."
  assert_output --partial "Persisting updated Terraform state to s3://test-bucket/.terraform/terraform.tfstate..."
  assert_output --partial "Backblaze B2 bucket 'test-bucket' successfully configured with SSE-B2 encryption and lifecycle rules!"

  # Verify terraform calls
  run cat "${TEST_TMP_DIR}/terraform.log"
  assert_output --partial "init -backend=false -input=false"
  assert_output --partial "apply -auto-approve -input=false"

  # Verify aws calls for state pull and state push
  run cat "${TEST_TMP_DIR}/aws.log"
  assert_output --partial "s3 cp s3://test-bucket/.terraform/terraform.tfstate"
  assert_output --partial "s3 cp ${TEST_TMP_DIR}/tf_work/terraform.tfstate s3://test-bucket/.terraform/terraform.tfstate"
}
