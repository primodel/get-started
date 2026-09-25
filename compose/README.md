# Primodel — Docker Compose quickstart

> **Examples, not supported deliverables; customise for your environment.**

Runs Primodel and its required backing services on your machine with one command.

## What it starts

| Service | Image | Purpose |
| --- | --- | --- |
| `caddy` | `caddy:2` | Front door on `:8080` — same-origin routing to the app and the bundled GraphiQL explorer |
| `primodel` | `ghcr.io/primodel/primodel` | The app — UI, REST, GraphQL and OpenAPI (internal; reached via Caddy) |
| `postgres` | `postgres:18` | Canonical + metadata store (**required**) |
| `nats` | `nats:2.10` (JetStream) | Ingestion queue, change events, GraphQL subscriptions (**required**) |
| `http-demo` | `nginx:alpine` | [DEMO ONLY] Serves demo source data files (JSON/XML/CSV) to the seeded integrations |
| `softhsm-init` | built from `softhsm/` | One-shot: initializes the SoftHSM PKCS#11 token used as the KEK backend, then exits |

The object store defaults to the **local filesystem**, so no S3/MinIO is needed to get started. All
persistent state is **bind-mounted under `./data`** next to the compose file — no Docker named volumes.
That keeps each install directory self-contained: a fresh directory is a fresh install, and deleting
`./data` removes all data.

## Run it

```bash
cp .env.example .env
# edit .env — at minimum set PRIMODEL_ENCRYPTION_KEY (e.g. `openssl rand -base64 48`)
docker compose up -d
```

Then open <http://localhost:8080> and sign in as **`admin`** with the `PRIMODEL_BOOTSTRAP_PASSWORD`
you set (if you left it blank, a random one is printed in the logs: `docker compose logs primodel`).

The container applies database migrations and seeds the initial admin automatically on first start.

### GraphQL explorer

**GraphiQL** — <http://localhost:8080/graphiql> — is vendored (offline once images are pulled) and served
same-origin through Caddy. Your **signed-in browser session authenticates via its cookie** — no header
needed.

## Demo [DEMO ONLY — INSECURE]

> **INSECURE: for evaluation only.** `PRIMODEL_DEMO_SEED_INSECURE=true` is set in the compose file.
> This maps `POST /api/seed-demo-data` and seeds well-known demo passwords. **Remove it (or set to
> `false`) before using Primodel with real data.**

The install script (run from the repo root) calls `POST /api/seed-demo-data` after the stack is
healthy, blocking until all integrations complete. Demo personas:

| Username | Password | Role |
| --- | --- | --- |
| `admin` | `pri-model-is-great` | System Administrator |
| `ada` | `lovelace` | Owner — HR + Finance (Restricted clearance) |
| `frank` | `borland` | Schema Steward — HR + Finance |
| `blaise` | `pascal` | Integrator — HR + Finance |
| `grace` | `hopper` | Data Reader — HR only (Internal clearance) |

See the [root README](../README.md) for the full demo tour.

## Everyday commands

```bash
docker compose logs -f primodel   # follow logs
docker compose pull && docker compose up -d   # upgrade to the latest image
docker compose down               # stop (keeps data — state lives in ./data)
docker compose down && rm -rf data   # stop and DELETE all data (fresh start)
```

## Configuration

All settings are environment variables on the `primodel` service (ASP.NET Core `Section__Key` form).
The compose wires the essentials; common overrides:

| Variable | Default | Notes |
| --- | --- | --- |
| `PRIMODEL_PORT` | `8080` | Host port for the UI/API |
| `PRIMODEL_IMAGE` | `…/primodel:latest` | Pin a version tag for reproducible installs |
| `PRIMODEL_ENCRYPTION_KEY` | — | **Required.** Field-level encryption key; keep it stable |
| `PRIMODEL_BOOTSTRAP_PASSWORD` | — | First-run admin password; blank → random, logged |

### KEK / field-level secret store (SoftHSM)

The `primodel` service's KEK (Key-Encryption-Key) backend is a **real PKCS#11/Cryptoki token**,
provided by the bundled `softhsm-init` sidecar — not `PRIMODEL_KEK=none` and not raw key material in
an env var:

- `softhsm-init` runs once at startup: it initializes the SoftHSM token (well under a second — it's
  local state creation, not network I/O) and publishes the PKCS#11 module (`libsofthsm2.so`) + its
  config onto `./data/softhsm/{tokens,etc,lib}`, which `primodel` also mounts. It then exits, and
  `primodel` waits on that exit (`service_completed_successfully`) before starting — the app's first
  boot never races an uninitialized token.
- `PRIMODEL_KEK` is the **non-secret pointer**: `pkcs11:module=<path>;token=<label>;label=<keylabel>`
  — no key material, ever. `PRIMODEL_KEK_PKCS11_PIN` authenticates to the SoftHSM token (not the KEK
  itself); it must match `SOFTHSM_PIN` in `.env`.
- `PRIMODEL_KEK_PKCS11_CREATE_IF_MISSING=true` lets the app generate the AES-256 KEK object on the
  token itself, the first time it logs in — the sidecar only creates the *token*, not the key.
  Production deployments leave this unset/false and provision the KEK out-of-band.
- Deleting `./data/softhsm` (part of the full-reset `rm -rf ./data`) removes the token and the KEK
  with it — same lifecycle as the rest of `./data`.

See `compose/softhsm/entrypoint.sh` for the full rationale, and the app's `Primodel.Providers.Kek`
namespace for the other supported backends (`local:`, `awskms:`, `azurekv:`, `gcpkms:`).

### Config file (primodel.toml)

`appsettings.json` has been replaced by `primodel.toml`, layered:

```
base image primodel.toml  <  /etc/primodel/primodel.toml  <  /mnt/primodel/primodel.toml  <  PRIMODEL_* env  <  DB runtime_settings
```

This compose mounts `./primodel.toml` at the volume-overlay layer (`/mnt/primodel/primodel.toml`,
the default `PRIMODEL_CONFIG_PATH`). Use it for settings with **no** `PRIMODEL_*` env var mapping
(e.g. `[Scheduler] PollSeconds`) — edit `compose/primodel.toml` and `docker compose up -d` to
re-mount it (Caddy/Postgres/NATS are unaffected; only `primodel` restarts).

> **TOML scoping gotcha:** a bare key belongs to the most recent `[Table]` header above it — a
> root-level key placed after a table header is silently absorbed into that table (comments do NOT
> re-scope). Put every root-level key **above** the first `[Table]` header. See the comment at the
> top of `compose/primodel.toml`.

### Two-phase startup (production secret stores)

Not used by this local stack (plain `PRIMODEL_DATABASE_URL` covers it), but available for
production deployments that resolve credentials from a secret store instead of plaintext env vars:

| Variable | Purpose |
| --- | --- |
| `PRIMODEL_METADATA_SECRET_REF` | Resolves the metadata DB credential from AWS Secrets Manager / Azure Key Vault / a Kubernetes Secret at boot, replacing `PRIMODEL_DATABASE_URL` |
| `PRIMODEL_KEK` | The KEK pointer (see above) — `awskms:`/`azurekv:`/`gcpkms:`/`pkcs11:` all resolve against a real key store rather than this local SoftHSM sidecar |

### Using S3 / MinIO instead of the filesystem store

Set these on the `primodel` service (and add a MinIO service, or point at any S3-compatible endpoint):

```yaml
ObjectStore__UseFileSystem: "false"
ObjectStore__ServiceUrl: "http://minio:9000"
ObjectStore__Bucket: "primodel-ingestion"
ObjectStore__AccessKey: "..."
ObjectStore__SecretKey: "..."
ObjectStore__ForcePathStyle: "true"
```

## Process roles

Primodel supports three process roles via `PRIMODEL_ROLE`. The default (`all`) runs
everything in one container — suitable for local eval and single-node production.

| `PRIMODEL_ROLE` | What runs | HTTP surface |
| --- | --- | --- |
| `all` (default) | API + workers + scheduler + streaming supervisor | Full — UI, REST, GraphQL, MCP, health |
| `api` | HTTP/GraphQL/MCP endpoints only; no background workers | Full API + health |
| `worker` | Ingestion engine, scheduler, streaming supervisor; no API | `/health/live`, `/health/ready` only |

### Must-nail rules for split topology

When using `api` + `worker` instead of `all`:

1. **Worker pairing is required.** An `api` node queues ingestion and integration jobs
   durably on NATS. Jobs are processed only when at least one `worker` node is running.
   Never run `role=api` without a paired `role=worker` (or `role=all`) process.

2. **Worker binds health only.** The worker container listens on port 8080 for
   `/health/live` and `/health/ready` only. The full REST/GraphQL/MCP surface is not
   available on worker pods — route user traffic to `api` pods only.

### Splitting with Docker Compose

The default compose keeps a single `primodel` service with `role=all`. To split into
separate api and worker services, add a `PRIMODEL_ROLE` environment variable to each:

```yaml
services:
  primodel-api:
    image: ${PRIMODEL_IMAGE:-ghcr.io/primodel/primodel:latest}
    environment:
      PRIMODEL_ROLE: "api"
      # ... same backing-service vars as the single-container setup
    ports:
      - "8080:8080"

  primodel-worker:
    image: ${PRIMODEL_IMAGE:-ghcr.io/primodel/primodel:latest}
    environment:
      PRIMODEL_ROLE: "worker"
      # ... same backing-service vars (no ports needed — health-only)
    # Worker exposes no host port; health probes via docker compose internally.
```

Both services share the same image, database, and NATS connection. The worker applies
no migrations (migrations run only in `all` and `api`); ensure the api service starts
first if running a fresh install.

### Observability note — streaming-state live lag

Each worker process tracks per-partition streaming lag in memory (StreamingMetrics).
Prometheus scrapes each worker pod independently. The `/api/streaming-state` REST
endpoint reflects only the node that handles the HTTP request — for a multi-worker
deployment this is best-effort (you may hit a different node each time). The authoritative
committed offset is always in the database and is node-agnostic.

## Production

For real deployments, point `ConnectionStrings__DefaultConnection`, `Nats__Url` and the `ObjectStore__*`
settings at managed Postgres, NATS and S3 rather than the bundled single-node services.
Use the included Helm chart (`helm/primodel`) for Kubernetes deployments — it supports
both the single-container (`role=all`) and split (`worker.enabled=true`) topologies.

## Supply-chain verification

See [`../SECURITY.md`](../SECURITY.md#signature-verification) for the full picture. Short version: images
are signed keylessly with cosign (Sigstore Fulcio/Rekor) today, and will additionally be signed with a key
pair (`primodel.pub`, from github.com/primodel/releases) — offline/air-gapped verification with
`cosign verify --key primodel.pub` applies to 3.1.2 and every release after it. Earlier images are
keyless-signed only and will not verify against `primodel.pub`.
