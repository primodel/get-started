locals {
  tags = merge({ "app.kubernetes.io/name" = "primodel", "managed-by" = "terraform" }, var.tags)
}

resource "random_password" "db" {
  length  = 32
  special = false # URL-safe for PRIMODEL_DATABASE_URL
}

# ── PostgreSQL Flexible Server (private, VNet-integrated) ───────────────────────────────────────
resource "azurerm_postgresql_flexible_server" "this" {
  name                = "${var.name}-pg"
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = var.db_version

  administrator_login    = var.db_username
  administrator_password = random_password.db.result

  sku_name   = var.db_sku_name
  storage_mb = var.db_storage_mb
  zone       = var.db_zone

  delegated_subnet_id = var.delegated_subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  # public_network_access is disabled implicitly when a delegated subnet is set.

  dynamic "high_availability" {
    for_each = var.db_high_availability ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  tags = local.tags
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.this.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}
