variable "name" {
  description = "Name prefix for created resources."
  type        = string
  default     = "primodel"
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

# ── Network (bring your own VPC) ────────────────────────────────────────────────────────────────
variable "vpc_id" {
  description = "VPC to place RDS in."
  type        = string
}

variable "database_subnet_ids" {
  description = "Private subnet IDs for the RDS subnet group (spread across AZs)."
  type        = list(string)
}

variable "db_ingress_cidr_blocks" {
  description = "CIDRs allowed to reach Postgres on 5432 (e.g. the EKS node/pod subnets)."
  type        = list(string)
}

# ── PostgreSQL (RDS) ────────────────────────────────────────────────────────────────────────────
variable "db_engine_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "RDS instance class. Bump for production."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage (GiB)."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "primodel"
}

variable "db_username" {
  description = "Master username."
  type        = string
  default     = "primodel"
}

variable "db_multi_az" {
  description = "Multi-AZ for high availability (recommended for production)."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Automated backup retention in days."
  type        = number
  default     = 7
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (true for eval only)."
  type        = bool
  default     = true
}

# ── Object store (S3) ───────────────────────────────────────────────────────────────────────────
variable "bucket_name" {
  description = "Globally-unique S3 bucket name for the object store."
  type        = string
}

# ── Workload identity (IRSA) ────────────────────────────────────────────────────────────────────
# Bring your own EKS cluster. These come from the cluster's IAM OIDC provider
# (e.g. terraform-aws-modules/eks outputs `oidc_provider_arn` and `cluster_oidc_issuer_url`).
variable "eks_oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider."
  type        = string
}

variable "eks_oidc_provider_url" {
  description = "Cluster OIDC issuer URL WITHOUT the https:// scheme (e.g. oidc.eks.eu-west-1.amazonaws.com/id/ABC123)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the Primodel ServiceAccount lives in."
  type        = string
  default     = "primodel"
}

variable "service_account_name" {
  description = "Kubernetes ServiceAccount name the IAM role is bound to (matches the Helm chart)."
  type        = string
  default     = "primodel"
}
