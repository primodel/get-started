output "database_url" {
  description = "PRIMODEL_DATABASE_URL — put this in the Helm chart's secrets.databaseUrl."
  value       = "postgres://${var.db_username}:${random_password.db.result}@${azurerm_postgresql_flexible_server.this.fqdn}:5432/${var.db_name}?sslmode=require"
  sensitive   = true
}

output "postgres_fqdn" {
  description = "Private FQDN of the Flexible Server."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "helm_values" {
  description = "Helm values snippet. Object store defaults to a filesystem PVC (Azure Blob is not S3-compatible)."
  value       = <<-EOT
    config:
      storage: filesystem      # Azure Blob is not S3-compatible; use a PVC, or MinIO for S3 semantics
    persistence:
      enabled: true
      size: 20Gi
  EOT
}
