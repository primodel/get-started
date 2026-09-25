# Security Policy

This document is Primodel's coordinated vulnerability disclosure (CVD) policy for the container image,
its published artifacts, and this repository's deployment blueprints. It follows the coordinated
disclosure expectations of EU CRA Annex I, Part II, points 5–6.

## How to report

Please report suspected vulnerabilities privately — do not open a public GitHub issue.

**With a GitHub account** — the quickest route:

> **[Report privately on GitHub →](https://github.com/primodel/releases/security/advisories/new)**

You will need to sign in. Your report is visible only to you and to us, and you can follow its status in
the same thread. (Reports for every Primodel repository come in through `primodel/releases`, which is the
repository that carries the images, SBOMs and the signing key.)

**Without a GitHub account** — email **security@primodel.io**. You do not need an account to report a
vulnerability to us. That mailbox is for security reports only; customer support is support@primodel.io and
is not a disclosure channel.

Please include:

- the affected Primodel version;
- steps to reproduce;
- the impact — what an attacker could achieve; and
- any proof-of-concept, if you have one.

Please do **not** report vulnerabilities in public GitHub issues, forums or on social media — that exposes
other users before a fix exists.

**What happens next:** we confirm receipt, assess the report within **seven (7) working days**, and release
a fix within **thirty (30) days** of confirming it (see **Commitment** below, and the
[security page](https://primodel.io/security/)).

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

In line with the EU Cyber Resilience Act, Primodel's Support Period has a current end date, reviewed annually; it
may be extended but will not be shortened. This document does not restate that date, since a static file cannot
keep it current — the authoritative current end date is always published at:

- the security page: [primodel.io/security](https://primodel.io/security)
- the machine-readable copy: [support-period.json](https://github.com/primodel/releases/blob/main/support-period.json)
  in [github.com/primodel/releases](https://github.com/primodel/releases)

## Regulatory reporting

Actively exploited vulnerabilities are reported to ENISA and/or the coordinating CSIRT as required under
EU CRA Art. 14.

## Signature verification

Published images are signed **keylessly with cosign** (Sigstore Fulcio/Rekor), and will **additionally**
be signed with a dedicated key pair. The public key, `primodel.pub`, is published at
[github.com/primodel/releases](https://github.com/primodel/releases), on the
[security page](https://primodel.io/security), and linked from each release's notes.

> **Key-based signing starts at 3.1.2.** The `--key` command below applies to 3.1.2 and every release
> after it. Images published earlier are keyless-signed only and will not verify against
> `primodel.pub` — verify those with the keyless command above.

**Offline / air-gapped (recommended when mirroring into an internal registry):**

```bash
cosign verify --key primodel.pub ghcr.io/primodel/primodel:<version>
```

This needs no network access to Sigstore. Verify at mirror time — before the image enters your internal
registry.

**Online (keyless):**

```bash
cosign verify ghcr.io/primodel/primodel:<version> \
  --certificate-identity-regexp '^https://github.com/Wadman-IT/Primodel/.github/workflows/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

This requires the verifier to reach Sigstore's Fulcio and Rekor services over the network at verification
time.
