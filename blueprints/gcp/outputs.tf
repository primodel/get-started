output "database_url" {
  description = "PRIMODEL_DATABASE_URL — put this in the Helm chart's secrets.databaseUrl (Cloud SQL private IP)."
  value       = "postgres://${var.db_username}:${random_password.db.result}@${google_sql_database_instance.this.private_ip_address}:5432/${var.db_name}?sslmode=require"
  sensitive   = true
}

output "s3_access_key" {
  description = "GCS HMAC access id — secrets.s3.accessKey."
  value       = google_storage_hmac_key.this.access_id
  sensitive   = true
}

output "s3_secret_key" {
  description = "GCS HMAC secret — secrets.s3.secretKey."
  value       = google_storage_hmac_key.this.secret
  sensitive   = true
}

output "helm_values" {
  description = "Helm values snippet for the GCS S3-compatible object store (feed the HMAC secrets separately)."
  value       = <<-EOT
    config:
      storage: s3
      s3:
        endpoint: https://storage.googleapis.com
        bucket: ${google_storage_bucket.this.name}
        region: auto
  EOT
}
