provider "b2" {
  application_key_id = var.b2_application_key_id
  application_key    = var.b2_application_key
}

# Dedicated private Backblaze B2 bucket for database backups
resource "b2_bucket" "backup_bucket" {
  bucket_name = var.bucket_name
  bucket_type = var.bucket_type

  dynamic "default_server_side_encryption" {
    for_each = var.enable_b2_encryption ? [1] : []
    content {
      algorithm = "AES256"
      mode      = "SSE-B2"
    }
  }

  dynamic "lifecycle_rules" {
    for_each = var.retention_days > 0 ? [1] : []
    content {
      file_name_prefix              = var.backup_prefix
      days_from_uploading_to_hiding = var.retention_days
      days_from_hiding_to_deleting  = 1
    }
  }
}

# Optional scoped Application Key (for standalone provisioning)
resource "b2_application_key" "backup_agent_key" {
  count      = var.create_app_key ? 1 : 0
  key_name   = var.app_key_name
  bucket_ids = [b2_bucket.backup_bucket.bucket_id]

  capabilities = [
    "listBuckets",
    "listFiles",
    "readFiles",
    "writeFiles",
    "deleteFiles"
  ]
}
