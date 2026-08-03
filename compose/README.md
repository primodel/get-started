# Primodel — Docker Compose quickstart

Runs Primodel and its required backing services on your machine with one command.

## What it starts

| Service | Image | Purpose |
| --- | --- | --- |
| `primodel` | `ghcr.io/primodel/primodel` | The app — UI, REST, GraphQL and OpenAPI on a **single port** (`:8080`) |
| `postgres` | `postgres:18` | Canonical + metadata store (**required**) |
| `nats` | `nats:2.10` (JetStream) | Ingestion queue, change events, GraphQL subscriptions (**required**) |

The object store defaults to the **local filesystem** (on a Docker volume), so no S3/MinIO is needed to
get started. Data persists in the `pgdata`, `natsdata` and `objectstore` volumes.

## Run it

```bash
cp .env.example .env
# edit .env — at minimum set PRIMODEL_ENCRYPTION_KEY (e.g. `openssl rand -base64 48`)
docker compose up -d
```

Then open <http://localhost:8080> and sign in as **`admin`** with the `PRIMODEL_BOOTSTRAP_PASSWORD`
you set (if you left it blank, a random one is printed in the logs: `docker compose logs primodel`).

The container applies database migrations and seeds the initial admin automatically on first start.

## Everyday commands

```bash
docker compose logs -f primodel   # follow logs
docker compose pull && docker compose up -d   # upgrade to the latest image
docker compose down               # stop (keeps data)
docker compose down -v            # stop and DELETE all data (fresh start)
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
