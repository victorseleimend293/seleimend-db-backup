output "bucket_name" {
  description = "The name of the Backblaze B2 backup bucket"
  value       = b2_bucket.backup_bucket.bucket_name
}

output "bucket_id" {
  description = "The unique ID of the Backblaze B2 backup bucket"
  value       = b2_bucket.backup_bucket.bucket_id
}

output "b2_application_key_id" {
  description = "Scoped Application Key ID for seleimend-db-backup"
  value       = try(b2_application_key.backup_agent_key[0].application_key_id, null)
}

output "b2_application_key" {
  description = "Scoped Application Key (Secret) for seleimend-db-backup"
  value       = try(b2_application_key.backup_agent_key[0].application_key, null)
  sensitive   = true
}

output "k8s_secret_config" {
  description = "Kubernetes Secret stringData snippet ready to use"
  value       = <<-EOT
    B2_ENDPOINT: "s3.<your-region>.backblazeb2.com"
    B2_APPLICATION_KEY_ID: "${try(b2_application_key.backup_agent_key[0].application_key_id, "<your-b2-app-key-id>")}"
    B2_APPLICATION_KEY: "<sensitive - view via terraform output -raw b2_application_key>"
    B2_BUCKET: "${b2_bucket.backup_bucket.bucket_name}"
    B2_PREFIX: "${var.backup_prefix}"
  EOT
}
