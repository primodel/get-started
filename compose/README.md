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

## Production

For real deployments, point `ConnectionStrings__DefaultConnection`, `Nats__Url` and the `ObjectStore__*`
settings at managed Postgres, NATS and S3 rather than the bundled single-node services. A Helm chart is
planned — see the repository root.
