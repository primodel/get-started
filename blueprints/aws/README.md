# Primodel on AWS — Terraform

> **Examples, not supported deliverables; customise for your environment.**

Provisions the managed backing services for Primodel and the keyless S3 access it needs, then hands you
the values to deploy the workload with the [Helm chart](../../helm/primodel):

- **RDS PostgreSQL** (encrypted, private) — the canonical + metadata store.
- **S3 bucket** (versioned, encrypted, public access blocked) — the object store.
- **IAM role for IRSA** — the Primodel ServiceAccount assumes it for S3 access, so **no static keys**.

NATS runs inside the cluster (bundled by the Helm chart), so it isn't provisioned here.

## Prerequisites (bring your own)

- A **VPC** with private subnets, and an **EKS cluster** with an **IAM OIDC provider** enabled. Use
  [`terraform-aws-modules/vpc`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws) and
  [`terraform-aws-modules/eks`](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws) if
  you don't have them — this module intentionally doesn't reinvent the cluster.
- An ingress path (AWS Load Balancer Controller + ACM) for TLS — see
  [TLS & HTTPS](https://primodel.io/docs/deployment/tls-and-https/).

## Usage

> **Uses OpenTofu** (`tofu`). Terraform is a drop-in — swap `terraform` for `tofu` if you prefer; these modules validate on both.

```hcl
module "primodel" {
  source = "github.com/primodel/get-started//blueprints/aws"

  region                 = "eu-west-1"
  vpc_id                 = module.vpc.vpc_id
  database_subnet_ids    = module.vpc.private_subnets
  db_ingress_cidr_blocks = module.vpc.private_subnets_cidr_blocks
  bucket_name            = "acme-primodel-eu-west-1"

  # from the EKS module
  eks_oidc_provider_arn = module.eks.oidc_provider_arn
  eks_oidc_provider_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")

  db_instance_class = "db.t4g.medium" # bump for production
  db_multi_az       = true
}

output "primodel_database_url" { value = module.primodel.database_url, sensitive = true }
output "primodel_helm_values" { value = module.primodel.helm_values }
```

```bash
tofu init
tofu plan
tofu apply
```

## Deploy the workload

Feed the outputs into the Helm chart. Put the sensitive `database_url` in your values (or an
`existingSecret`), and use the `helm_values` snippet for the S3 + IRSA wiring:

```bash
tofu output -raw database_url    # → secrets.databaseUrl
tofu output helm_values          # → config.s3.* + serviceAccount annotation
```

Then follow the [AWS blueprint](https://primodel.io/docs/blueprints/aws/) to `helm install`. Remember to
set `secrets.encryptionKey` (generate with `openssl rand -base64 48`) and `secrets.bootstrapPassword`.

## Supply-chain verification — PENDING

> **PENDING — see [`SECURITY.md`](../../SECURITY.md#signature-verification--pending).** Published images
> are signed today with keyless cosign (Sigstore Fulcio/Rekor), but the signing model is still an open
> owner decision, and keyless verification needs the verifier to reach Rekor/Fulcio — which an air-gapped
> EKS cluster can't do. No `cosign verify` command is published here yet; a command tied to the wrong
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
