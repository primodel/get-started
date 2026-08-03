output "database_url" {
  description = "PRIMODEL_DATABASE_URL — put this in the Helm chart's secrets.databaseUrl."
  value       = "postgres://${var.db_username}:${random_password.db.result}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}?sslmode=require"
  sensitive   = true
}

output "s3_bucket" {
  description = "S3 bucket name — config.s3.bucket."
  value       = aws_s3_bucket.this.bucket
}

output "s3_region" {
  description = "S3 region — config.s3.region."
  value       = var.region
}

output "irsa_role_arn" {
  description = "IAM role ARN — set on the ServiceAccount (eks.amazonaws.com/role-arn) for keyless S3 access."
  value       = aws_iam_role.irsa.arn
}

output "helm_values" {
  description = "A ready-to-use Helm values snippet (feed the sensitive database_url separately)."
  value       = <<-EOT
    config:
      storage: s3
      s3:
        bucket: ${aws_s3_bucket.this.bucket}
        region: ${var.region}
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${aws_iam_role.irsa.arn}
  EOT
}
