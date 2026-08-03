# Primodel on Google Cloud — Terraform

Provisions the managed backing services for Primodel and the S3-compatible access to GCS, then outputs
the values to deploy the workload with the [Helm chart](../../helm/primodel):

- **Cloud SQL for PostgreSQL** (private IP, encrypted) — the canonical + metadata store.
- **GCS bucket** + a **service account with an HMAC key** — the object store, via GCS's
  **S3-compatible** interoperability API.

NATS runs inside the cluster (bundled by the chart), so it isn't provisioned here.

## Prerequisites (bring your own)

- A **VPC** with **private services access** (VPC peering for Cloud SQL private IP) already configured.
- A **GKE** cluster and an ingress path (GKE managed cert or nginx + cert-manager) for TLS — see
  [TLS & HTTPS](https://primodel.io/docs/deployment/tls-and-https/).

## Usage

> **Uses OpenTofu** (`tofu`). Terraform is a drop-in — swap `terraform` for `tofu` if you prefer; these modules validate on both.

```hcl
module "primodel" {
  source = "github.com/primodel/get-started//blueprints/gcp"

  project_id      = "acme-prod"
  region          = "europe-west1"
  private_network = google_compute_network.vpc.self_link
  bucket_name     = "acme-primodel-euw1"

  db_tier              = "db-custom-2-7680" # bump for production
  db_availability_type = "REGIONAL"
}

output "primodel_database_url" { value = module.primodel.database_url, sensitive = true }
output "primodel_s3_access_key" { value = module.primodel.s3_access_key, sensitive = true }
output "primodel_s3_secret_key" { value = module.primodel.s3_secret_key, sensitive = true }
output "primodel_helm_values" { value = module.primodel.helm_values }
```

```bash
tofu init && tofu plan && tofu apply
```

## Deploy the workload

```bash
tofu output -raw database_url    # → secrets.databaseUrl
tofu output -raw s3_access_key   # → secrets.s3.accessKey
tofu output -raw s3_secret_key   # → secrets.s3.secretKey
tofu output helm_values          # → config.storage + config.s3.*
```

Reach Cloud SQL over its **private IP** (shown in `database_url`) from GKE — nodes must be on the peered
VPC, or use the Cloud SQL Auth Proxy. Then follow the
[Google Cloud blueprint](https://primodel.io/docs/blueprints/gcp/) to `helm install`. Set
`secrets.encryptionKey` (`openssl rand -base64 48`) and `secrets.bootstrapPassword`.
