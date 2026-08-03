# Get started with Primodel

Ways to run [Primodel](https://primodel.io) — the governed canonical data platform — locally or in your
own infrastructure. Each method lives in its own directory so you can pick what fits.

## Quickstart (Docker Compose)

One command downloads the compose setup, generates secrets, and starts everything:

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/primodel/get-started/main/install.sh | bash
```

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/primodel/get-started/main/install.ps1 | iex
```

Then open <http://localhost:8080>. The script prints the generated `admin` password. (Both need Docker
Desktop / Engine with Compose v2.)

Prefer to do it by hand? See [`compose/`](./compose/):

```bash
git clone https://github.com/primodel/get-started.git
cd get-started/compose
cp .env.example .env   # set PRIMODEL_ENCRYPTION_KEY
docker compose up -d
```

## What you get

A single Primodel container serving the **UI, REST, GraphQL and OpenAPI on one port**, plus its two
required backing services:

- **Postgres** — the canonical + metadata store.
- **NATS (JetStream)** — the ingestion queue, change events, and GraphQL subscriptions.

The object store defaults to the local filesystem, so nothing else is needed to try it out.

## Contents

| Path | What |
| --- | --- |
| [`compose/`](./compose/) | Docker Compose quickstart (recommended for local eval) |
| `install.sh` | The `curl \| bash` bootstrap (macOS / Linux) |
| `install.ps1` | The `irm \| iex` bootstrap (Windows / PowerShell) |
| `helm/` | Kubernetes Helm chart — _planned_ |
| `examples/` | Sample models & integrations — _planned_ |

## Documentation

Full docs, including production deployment guidance, live at <https://primodel.io/docs/>.
