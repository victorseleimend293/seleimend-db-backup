variable "b2_application_key_id" {
  description = "Backblaze B2 Account Key ID or Master Key ID used by Terraform to provision resources"
  type        = string
  sensitive   = true
}

variable "b2_application_key" {
  description = "Backblaze B2 Account Key or Master Key used by Terraform to provision resources"
  type        = string
  sensitive   = true
}

variable "bucket_name" {
  description = "Globally unique name for the Backblaze B2 backup bucket"
  type        = string
  default     = "seleimend-db-backups"
}

variable "bucket_type" {
  description = "Bucket access type ('allPrivate' or 'allPublic')"
  type        = string
  default     = "allPrivate"
}

variable "backup_prefix" {
  description = "Path prefix for backup objects inside the bucket for lifecycle retention rules"
  type        = string
  default     = "backups/postgres"
}

variable "retention_days" {
  description = "Number of days before Backblaze B2 automatically hides and deletes old backups (0 to disable lifecycle rules)"
  type        = number
  default     = 30
}

variable "enable_b2_encryption" {
  description = "Enable Backblaze B2 default server-side encryption (SSE-B2 with AES256)"
  type        = bool
  default     = true
}

variable "create_app_key" {
  description = "Whether to create a scoped application key (set true when running standalone)"
  type        = bool
  default     = false
}

variable "app_key_name" {
  description = "Name for the scoped application key dedicated to the backup agent"
  type        = string
  default     = "seleimend-db-backup-agent"
}
