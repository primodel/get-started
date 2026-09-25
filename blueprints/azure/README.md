# Primodel on Azure — Terraform

> **Examples, not supported deliverables; customise for your environment.**

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

## Supply-chain verification — PENDING

> **PENDING — see [`SECURITY.md`](../../SECURITY.md#signature-verification--pending).** Published images
> are signed today with keyless cosign (Sigstore Fulcio/Rekor), but the signing model is still an open
> owner decision, and keyless verification needs the verifier to reach Rekor/Fulcio — which an air-gapped
> AKS cluster can't do. No `cosign verify` command is published here yet; a command tied to the wrong
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
