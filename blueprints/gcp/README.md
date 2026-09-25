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

## Supply-chain verification — PENDING

> **PENDING — see [`SECURITY.md`](../../SECURITY.md#signature-verification--pending).** Published images
> are signed today with keyless cosign (Sigstore Fulcio/Rekor), but the signing model is still an open
> owner decision, and keyless verification needs the verifier to reach Rekor/Fulcio — which an air-gapped
> GKE cluster can't do. No `cosign verify` command is published here yet; a command tied to the wrong
> signing model would fail in exactly the offline/private-cluster setups this blueprint targets.

### Optional: admission policy (illustrative only)

Once the signing model above is settled, you can enforce that only signed Primodel images run in the
cluster with a [Sigstore `policy-controller`](https://docs.sigstore.dev/policy-controller/overview/)
`ClusterImagePolicy`. This is **not wired up by this Terraform module** — it's an example to adapt:

```yaml
# EXAMPLE — illustrative only, not applied by this module.
# Requires policy-controller installed in the cluster (see Sigstore docs).
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: primodel-image-policy
spec:
  images:
    - glob: "ghcr.io/primodel/primodel:**"
  authorities:
    - keyless:
        # TODO once the signing model is finalised (see SECURITY.md):
        #   - url: the Fulcio instance that issued the signing cert (public Sigstore, or a
        #     private Fulcio if Primodel moves off public keyless)
        url: https://fulcio.sigstore.dev
        identities:
          # TODO: fill in the actual OIDC issuer + subject the release pipeline signs with
          - issuer: "https://token.actions.githubusercontent.com"
            subject: "https://github.com/primodel/REPLACE_ME/.github/workflows/REPLACE_ME.yml@refs/heads/main"
      ctlog:
        url: https://rekor.sigstore.dev
```

Fields to fill in once the signing decision is made: `authorities[].keyless.url` (or switch to
`authorities[].key.data` if the project moves to a static/KMS-backed key instead of keyless), and
`authorities[].keyless.identities[].issuer` / `subject` to match the actual release workflow.
