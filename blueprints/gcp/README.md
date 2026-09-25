# Primodel on Google Cloud — Terraform

> **Examples, not supported deliverables; customise for your environment.**

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

## Supply-chain verification

See [`SECURITY.md`](../../SECURITY.md#signature-verification) for the full picture. Images are signed
keylessly with cosign (Sigstore Fulcio/Rekor) today, and will additionally be signed with a key pair —
the recommended path for an air-gapped GKE cluster, since offline verification with
`cosign verify --key primodel.pub` needs no network access to Rekor/Fulcio. That command applies from the
first key-signed release onward; it is not yet live. The public key, `primodel.pub`, will be published at
[github.com/primodel/releases](https://github.com/primodel/releases) and on the
[security page](https://primodel.io/security).

### Optional: admission policy (illustrative only)

Once `primodel.pub` is published, you can enforce that only signed Primodel images run in the cluster
with a [Sigstore `policy-controller`](https://docs.sigstore.dev/policy-controller/overview/)
`ClusterImagePolicy`. This is **not wired up by this Terraform module** — it's an example to adapt:

```yaml
# EXAMPLE — illustrative only, not applied by this module.
# Requires policy-controller installed in the cluster (see Sigstore docs).
# Key-based verification against primodel.pub (github.com/primodel/releases) — available from the
# first key-signed release onward (see SECURITY.md).
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: primodel-image-policy
spec:
  images:
    - glob: "ghcr.io/primodel/primodel:**"
  authorities:
    - key:
        # Paste the contents of primodel.pub here.
        data: |
          -----BEGIN PUBLIC KEY-----
          REPLACE_ME
          -----END PUBLIC KEY-----
```

Field to fill in once `primodel.pub` is published: `authorities[].key.data` — the contents of the key
itself.
