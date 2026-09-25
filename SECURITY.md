# Security Policy

This document is Primodel's coordinated vulnerability disclosure (CVD) policy for the container image,
its published artifacts, and this repository's deployment blueprints. It follows the coordinated
disclosure expectations of EU CRA Annex I, Part II, points 5–6.

## How to report

Please report suspected vulnerabilities privately — do not open a public GitHub issue.

- **Preferred: GitHub private vulnerability reporting** on this repository — go to the
  [Security tab](https://github.com/primodel/get-started/security) and select **Report a vulnerability**
  (or use the direct link:
  [github.com/primodel/get-started/security/advisories/new](https://github.com/primodel/get-started/security/advisories/new)).
  This opens a private advisory visible only to maintainers until it is published.
- **Email**: `{{SECURITY_EMAIL — OWNER DECISION PENDING}}`

Please include: affected component/version, a description of the issue, reproduction steps or a
proof-of-concept, and the potential impact. We will acknowledge receipt and work with you on a
coordinated disclosure timeline (see **Commitment** below).

## Scope

**In scope:**

- The Primodel container image (`ghcr.io/primodel/primodel`) and its published artifacts (release
  binaries, SBOMs, signatures).
- This repository's deployment blueprints — the Docker Compose quickstart (`compose/`), the Terraform
  blueprints (`blueprints/aws`, `blueprints/azure`, `blueprints/gcp`), and the Helm chart (`helm/`) — as
  shipped.

**Out of scope:**

- Customer-operated infrastructure (your cloud account, cluster configuration, network policy, secrets
  management, and any modifications you make to the blueprints).
- Third-party services the blueprints integrate with (cloud provider managed services, container
  registries, DNS, etc.) — report those to the respective vendor.
- The demo/evaluation data and demo personas (`compose/demo-data/`, the seeded demo accounts) — these are
  intentionally insecure, well-known credentials for local evaluation only and are not a vulnerability.

## Commitment

Vulnerabilities are triaged and confirmed or rejected within seven (7) working days of Licensor becoming
aware of them; a patched release is made available within thirty (30) days of confirmation; interim
mitigation guidance may be published before the patch; remediation is provided in the then-current
version.

## Advisories

Published advisories are announced through
[GitHub Security Advisories](https://github.com/primodel/get-started/security/advisories) on this
repository.

## SBOM

Per-platform SPDX documents are published at
[github.com/primodel/releases](https://github.com/primodel/releases) under `sbom/`, named:

```
primodel-<version>-linux-amd64.spdx.json
primodel-<version>-linux-arm64.spdx.json
```

> **Warning:** the combined `primodel-<version>.spdx.json` is keyed **by platform**. Handed to a scanner
> as-is, it matches zero packages against your (single-platform) image and reports a false all-clear.
> Always feed your scanner the **per-platform** file that matches the image you actually run
> (`linux-amd64` or `linux-arm64`), never the combined document.

## VEX statements

VEX (Vulnerability Exploitability eXchange) statements are published when available.

## Support Period

The end date of the support period for each release line is published on the security page at
[primodel.io/security](https://primodel.io/security). Current end date:
`{{SUPPORT_PERIOD_END — OWNER DECISION PENDING}}`.

## Regulatory reporting

Actively exploited vulnerabilities are reported to ENISA and/or the coordinating CSIRT as required under
EU CRA Art. 14.

## Signature verification — PENDING

> **PENDING — signing model is an open owner decision.** Published images **are** signed today with
> **keyless cosign** (Sigstore Fulcio/Rekor). However, keyless verification requires the verifier to
> reach Rekor/Fulcio over the network at verification time, which an air-gapped or fully offline
> environment cannot do. Whether the long-term signing model stays keyless, moves to a KMS-backed key, or
> offers both is not yet decided. Until that decision is made and documented here, we are **not**
> publishing a `cosign verify` command, because a command tied to the wrong signing model would fail
> silently or fail outright in offline environments. Check back here, or the
> [Security tab](https://github.com/primodel/get-started/security), once this is resolved.
