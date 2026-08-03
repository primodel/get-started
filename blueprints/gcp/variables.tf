variable "project_id" {
  description = "GCP project id."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "name" {
  description = "Name prefix for created resources."
  type        = string
  default     = "primodel"
}

variable "labels" {
  description = "Labels applied to supported resources."
  type        = map(string)
  default     = {}
}

# ── Cloud SQL (PostgreSQL, private IP) ──────────────────────────────────────────────────────────
variable "private_network" {
  description = "Self-link of the VPC for the Cloud SQL private IP. Requires private services access (VPC peering) already configured on it."
  type        = string
}

variable "db_version" {
  description = "Cloud SQL PostgreSQL version."
  type        = string
  default     = "POSTGRES_16"
}

variable "db_tier" {
  description = "Cloud SQL machine tier. Bump for production."
  type        = string
  default     = "db-custom-1-3840"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "primodel"
}

variable "db_username" {
  description = "Database user."
  type        = string
  default     = "primodel"
}

variable "db_availability_type" {
  description = "ZONAL or REGIONAL (REGIONAL = HA, recommended for production)."
  type        = string
  default     = "ZONAL"
}

variable "db_deletion_protection" {
  description = "Protect the instance from deletion."
  type        = bool
  default     = true
}

# ── Object store (GCS via the S3-compatible API) ────────────────────────────────────────────────
variable "bucket_name" {
  description = "Globally-unique GCS bucket name."
  type        = string
}

variable "bucket_location" {
  description = "GCS bucket location (region or multi-region)."
  type        = string
  default     = "EU"
}
