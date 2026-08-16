# Primodel — Docker Compose quickstart

Runs Primodel and its required backing services on your machine with one command.

## What it starts

| Service | Image | Purpose |
| --- | --- | --- |
| `caddy` | `caddy:2` | Front door on `:8080` — same-origin routing to the app and the bundled GraphiQL explorer |
| `primodel` | `ghcr.io/primodel/primodel` | The app — UI, REST, GraphQL and OpenAPI (internal; reached via Caddy) |
| `postgres` | `postgres:18` | Canonical + metadata store (**required**) |
| `nats` | `nats:2.10` (JetStream) | Ingestion queue, change events, GraphQL subscriptions (**required**) |
| `http-demo` | `nginx:alpine` | [DEMO ONLY] Serves demo source data files (JSON/XML/CSV) to the seeded integrations |

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
