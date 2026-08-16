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

## Demo tour [DEMO ONLY — INSECURE]

> **INSECURE: demo only, never on a real install.** The compose stack sets `PRIMODEL_DEMO_SEED_INSECURE=true`, which maps a seed endpoint that creates well-known demo passwords. Remove or set to `false` before using Primodel with real data.

The install script seeds a realistic HR + Finance dataset and creates five well-known personas so you can explore the platform from different role perspectives without configuring anything yourself.

### Personas

| Username | Password | Role | What they can do |
| --- | --- | --- | --- |
| `admin` | `pri-model-is-great` | System Administrator | User management, data store CRUD, platform settings. No direct data access (break-glass for that). |
| `ada` | `lovelace` | Owner — HR + Finance (Restricted clearance) | Full domain control on both domains. Sees all fields unmasked (Restricted clearance). |
| `frank` | `borland` | Schema Steward — HR + Finance | Author schema (entities, fields, sensitivity tags, DQ rules). Cannot run integrations or see data above clearance. |
| `blaise` | `pascal` | Integrator — HR + Finance | Author and run integrations. Can query data within clearance. |
| `grace` | `hopper` | Data Reader — HR only (Internal clearance) | Read HR records up to Internal clearance. `national_id` and `bank_account` (Restricted) are hard-masked. |

Sign in at <http://localhost:8080>.

### What to explore

1. **Field-level masking** — Sign in as `ada` (Owner, Restricted) and open the Person entity. All fields are visible. Then sign in as `grace` (Data Reader, Internal) and view the same entity — `national_id` and `bank_account` are hard-masked server-side.

2. **GraphiQL cross-domain query** — Open <http://localhost:8080/graphiql> (sign into Studio first so the auth cookie carries over). The default query joins HR `Person` with `Assignment.salary` — run it as `ada` to see salary cleartext, then as `grace` to see it masked.

3. **Integration runs** — Sign in as `blaise` (Integrator) and browse to Integrations. The demo has pre-seeded runs for HR (JSON), Payroll (CSV), Organisations (XML), Assignments (XML), Cost Centers (CSV), and Invoices (JSON). Re-run any integration to see the pipeline in action.

4. **MDM golden record + quarantine** — Browse to the `Person` golden entity. The HR and Payroll sources deliberately share `national_id = 19990101-9999` for two different keys — the Uniqueness Context DQ rule fires on survivorship and quarantines one of them for a steward to resolve.

5. **Temporal version history** — The seeded survivorship runs twice with different `full_name` values for persons 3–7, producing two `__version` rows per key in the temporal golden `Person` table. Query `/api/data/Demo/HR/Person/records?history=true` to see version history.

6. **DQ workbench** — Sign in as `frank` (Schema Steward). Browse to the DQ rules for `person_source`: a Regex rule on `national_id`, a NotNull rule on `email`, and a Range rule on `assignment.salary`. Several bad rows are quarantined — review and resolve them.

7. **Diagrams** — Open the HR Model and Finance Model diagrams (as `ada` or `frank`). Both include cross-domain entity references. The Finance diagram shows Invoice → Person (cross-domain reference to HR).

8. **Reset** — To start fresh: `docker compose down && rm -rf data`, then re-run the install script.

## Data lake (opt-in)

> **DEMO ONLY — opt-in.** The default `docker compose up` is completely unchanged. The lake stack (MinIO + Iceberg REST catalog + ClickHouse) is an optional overlay you start explicitly.

Primodel's governed replication engine writes an open data lake alongside the canonical Postgres store: raw source bytes in the bronze layer and Apache Iceberg tables in the silver layer. Once those Iceberg tables exist, ClickHouse can query them back via its native `iceberg()` table function — demonstrating the full lake round-trip without any proprietary format lock-in.

### Start the lake stack

```bash
cd compose
docker compose -f docker-compose.yml -f docker-compose.lake.yml up -d
```

This adds three services to the running stack:

| Service | What |
| --- | --- |
| **MinIO** | S3-compatible object store. Hosts both the bronze raw bytes and the Iceberg data/metadata files. Console at <http://localhost:9001> (user: `minioadmin` / `minioadmin`). |
| **iceberg-rest** | [tabulario/iceberg-rest](https://github.com/tabular-io/iceberg-rest-image) — the Iceberg REST catalog server. Tracks table metadata on MinIO; the Primodel replication engine writes silver Iceberg tables here. |
| **ClickHouse** | Query-back engine. Reads Iceberg silver tables from MinIO via its native `iceberg()` table function. HTTP interface at <http://localhost:8123>. |

The `PRIMODEL_DEMO_LAKE=true` flag passed to the Primodel container activates the opt-in lake seed on the next `POST /api/seed-demo-data` call (or a fresh install): it registers the MinIO connection + REST catalog config as the sysadmin lake config, flips the `Person` entity's lake-participation flag, and seeds a disabled "Iceberg → Person (lake query-back)" integration ready to be enabled.

### Explore the lake

1. **Browse bronze objects in MinIO** — open <http://localhost:9001>, sign in as `minioadmin / minioadmin`, and navigate to the `primodel-lake` bucket. After the first integration run you'll see raw source files (JSON/CSV/XML) written by the lake tee under `bronze/`.

2. **Inspect the Iceberg REST catalog** — the catalog exposes a JSON API:
   ```bash
   # List namespaces
   curl http://localhost:8181/v1/namespaces
   # List tables in the primodel namespace
   curl http://localhost:8181/v1/namespaces/primodel/tables
   ```

3. **Query Iceberg silver tables via ClickHouse** — once Primodel has run at least one replication pass the `Person` Iceberg table appears in the catalog. Query it from ClickHouse:
   ```bash
   curl 'http://localhost:8123/?query=SELECT+*+FROM+iceberg(%27http://iceberg-rest:8181%27,%27primodel%27,%27person%27)+LIMIT+5'
   ```
   Or open the ClickHouse HTTP interface directly: <http://localhost:8123/play>

4. **Enable the query-back integration in Primodel** — sign in as `blaise` (Integrator). Navigate to **Integrations** and enable the seeded "Iceberg → Person (lake query-back)" integration. Run it: Primodel will read the Iceberg silver `Person` table via ClickHouse and deliver the rows back into the canonical Postgres `Person` entity. This demonstrates that the lake is a governed, query-able data source — not just a write-only archive.

### Teardown

```bash
docker compose -f docker-compose.yml -f docker-compose.lake.yml down
# Optionally remove lake data volumes:
rm -rf compose/data/minio compose/data/clickhouse
```

Removing the lake data drops all Iceberg metadata and bronze objects. The canonical Postgres data (under `compose/data/postgres`) is unaffected.

## Documentation

Full docs, including production deployment guidance, live at <https://primodel.io/docs/>.
