# Primodel on Azure — Terraform

Provisions **Azure Database for PostgreSQL Flexible Server** (private, VNet-integrated) for Primodel, and
outputs the values to deploy the workload with the [Helm chart](../../helm/primodel).

NATS runs inside the cluster (bundled by the chart). **Object storage**: Azure Blob is *not*
S3-compatible, so the default is a **filesystem PVC** (an Azure Disk via the chart). For S3 semantics,
run **MinIO** in the cluster and set `config.storage: s3` with its endpoint.

## Prerequisites (bring your own)

- A **resource group**, a **VNet** with a **subnet delegated** to
  `Microsoft.DBforPostgreSQL/flexibleServers`, and a **Private DNS zone**
  (`*.private.postgres.database.azure.com`) linked to that VNet.
- An **AKS** cluster and an ingress path (Application Gateway/AGIC or nginx + cert-manager) for TLS —
  see [TLS & HTTPS](https://primodel.io/docs/deployment/tls-and-https/).

## Usage

> **Uses OpenTofu** (`tofu`). Terraform is a drop-in — swap `terraform` for `tofu` if you prefer; these modules validate on both.

```hcl
module "primodel" {
  source = "github.com/primodel/get-started//blueprints/azure"

  resource_group_name = "primodel-rg"
  location            = "westeurope"
  delegated_subnet_id = azurerm_subnet.db.id
  private_dns_zone_id = azurerm_private_dns_zone.pg.id

  db_sku_name          = "GP_Standard_D2ds_v5" # bump for production
  db_high_availability = true
}

output "primodel_database_url" { value = module.primodel.database_url, sensitive = true }
output "primodel_helm_values" { value = module.primodel.helm_values }
```

```bash
tofu init && tofu plan && tofu apply
```

## Deploy the workload

```bash
tofu output -raw database_url    # → secrets.databaseUrl (already includes ?sslmode=require)
tofu output helm_values          # → config.storage + persistence
```

Then follow the [Azure blueprint](https://primodel.io/docs/blueprints/azure/) to `helm install`. Set
`secrets.encryptionKey` (`openssl rand -base64 48`) and `secrets.bootstrapPassword`.
