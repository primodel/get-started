## What and why

<!-- What this change does and why. Link the issue, alert or case it closes. -->

## Security self-review (SEC §2)

<!-- Tick what you checked. Strike through or write "n/a" for items that don't apply; don't delete them. -->

- [ ] **Data and tenant boundary.** Which data does this touch? Tenant isolation holds in the data access layer.
- [ ] **Authentication and authorisation.** Every new or changed endpoint checks who is calling and what they may do.
- [ ] **Input and output.** Input is validated server-side, output is encoded, and framework protections aren't bypassed.
- [ ] **Queries.** Parameterised; no string-built SQL or shell commands.
- [ ] **Secrets.** No secrets, keys or tokens in code, config, logs or tests.
- [ ] **Logging.** No credentials, personal data or customer content beyond identifiers; untrusted values are neutralised before logging.
- [ ] **Data lifecycle and residency.** Retention, deletion and location of any new stored data are defined.
- [ ] **Secure defaults.** New settings default to the safe option; no default credentials.
- [ ] **Dependencies.** New packages are checked for licence and security posture and pass the 7-day release-age gate.
- [ ] **Configuration and CI.** Workflow permissions stay least-privilege; no gate is weakened.
- [ ] **OWASP Top 10.** Considered for anything user-facing.
- [ ] **AI-assisted changes.** If this change could compromise the security or integrity of the product or customer data (always for: auth, tenant isolation, crypto/signing, licensing, release pipeline and CI, data retention), the owner reviewed the diff before merge.

## Threat consideration

<!-- Required for significant changes: architecture, authentication, tenant isolation, licensing, signing, release pipeline.
     What could go wrong, who could abuse it, and what stops them. Otherwise write "Not a significant change". -->
