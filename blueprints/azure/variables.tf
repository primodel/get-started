variable "name" {
  description = "Name prefix for created resources."
  type        = string
  default     = "primodel"
}

variable "resource_group_name" {
  description = "Existing resource group to create resources in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

# ── PostgreSQL Flexible Server ──────────────────────────────────────────────────────────────────
# VNet-integrated (private). Bring a delegated subnet and a linked Private DNS zone.
variable "delegated_subnet_id" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers."
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private DNS zone id (e.g. <name>.private.postgres.database.azure.com) linked to the VNet."
  type        = string
}

variable "db_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "db_sku_name" {
  description = "Flexible Server SKU. Bump for production."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "db_storage_mb" {
  description = "Storage in MB."
  type        = number
  default     = 32768
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "primodel"
}

variable "db_username" {
  description = "Administrator login."
  type        = string
  default     = "primodel"
}

variable "db_zone" {
  description = "Availability zone for the server."
  type        = string
  default     = "1"
}

variable "db_high_availability" {
  description = "Enable zone-redundant HA (recommended for production)."
  type        = bool
  default     = false
}
