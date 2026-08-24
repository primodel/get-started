#!/usr/bin/env bash
#
# Primodel quickstart bootstrap.
#
#   curl -fsSL https://raw.githubusercontent.com/primodel/get-started/main/install.sh | bash
#
# Downloads the compose quickstart into ./primodel, generates secrets, and starts it.
set -euo pipefail

# Overridable so a fork, an internal mirror, or a local checkout can be installed from — and so the
# installer itself can be exercised end-to-end without publishing anything.
REPO_RAW="${PRIMODEL_REPO_RAW:-https://raw.githubusercontent.com/primodel/get-started/main/compose}"
TARGET_DIR="${PRIMODEL_DIR:-primodel}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "Docker is required. Install Docker Desktop or Engine: https://docs.docker.com/get-docker/"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required (\`docker compose\`). Update Docker."

rand() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -base64 "$1"
  else head -c "$1" /dev/urandom | base64; fi
}

# ── Which stack? ─────────────────────────────────────────────────────────────
# quick = Primodel + Postgres + NATS + Caddy.
# lake  = the above PLUS MinIO + Iceberg REST catalog + ClickHouse, so the demo shows the governed
#         lakehouse round-trip (canonical store -> Iceberg silver -> queried back through ClickHouse).
#
# Resolution order: flag, then PRIMODEL_MODE, then an interactive prompt, then quick. The prompt reads
# from /dev/tty rather than stdin ON PURPOSE: the documented install is `curl … | bash`, where stdin is
# the SCRIPT ITSELF — a plain `read` would swallow the rest of the script instead of waiting for a key.
# Where no terminal exists at all (CI, a Dockerfile) that read is impossible, so we take the quick
# default rather than hanging forever.
MODE="${PRIMODEL_MODE:-}"
for arg in "$@"; do
  case "$arg" in
    --lake|--full) MODE=lake ;;
    --quick)       MODE=quick ;;
    -h|--help)
      cat <<'USAGE'
Primodel quickstart.

  install.sh [--quick|--lake]

  --quick   Primodel + Postgres + NATS (default)
  --lake    also MinIO + Iceberg REST catalog + ClickHouse (governed lakehouse demo)

Non-interactive: set PRIMODEL_MODE=quick|lake. With no flag, no PRIMODEL_MODE and no
terminal to prompt on, --quick is used.
USAGE
      exit 0 ;;
    *) die "Unknown option: $arg (try --help)" ;;
  esac
done

if [ -z "$MODE" ]; then
  if [ -r /dev/tty ]; then
    printf '
'
    printf '  Which demo would you like?

'
    printf '    1) Quick start    Primodel + Postgres + NATS. Fastest, smallest download.
'
    printf '    2) Data lakehouse Adds MinIO + Iceberg + ClickHouse, and shows the governed
'
    printf '                      round-trip: canonical store -> Iceberg -> queried back via ClickHouse.
'
    printf '                      Pulls ~1 GB more and takes a few minutes longer to start.

'
    printf '  Choice [1]: '
    read -r REPLY_MODE < /dev/tty || REPLY_MODE=""
    printf '
'
    case "$REPLY_MODE" in
      2|lake|Lake|LAKE) MODE=lake ;;
      *)                MODE=quick ;;
    esac
  else
    MODE=quick
  fi
fi

if [ "$MODE" = lake ]; then
  COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.lake.yml)
  say "Installing the data-lakehouse demo (Primodel + Postgres + NATS + MinIO + Iceberg + ClickHouse)"
else
  COMPOSE_FILES=(-f docker-compose.yml)
  say "Installing the quick-start demo (Primodel + Postgres + NATS)"
fi

# Every compose call goes through this so the overlay can never be applied to `up` but forgotten on
# `down` — a mismatch there leaves orphan lake containers running against a stopped stack.
dc() { docker compose "${COMPOSE_FILES[@]}" "$@"; }

# Echoes $1 if nothing holds it, otherwise the next free port above it. A demo that dies because the
# machine already runs a MinIO on 9001 - and then asks the operator to edit .env and start over - is a
# demo that fails in front of an audience. Pick a port that works and say which one.
free_port() {
  preferred="$1"; label="$2"; p="$preferred"; limit=$((preferred + 50))
  while [ "$p" -lt "$limit" ]; do
    # A host binding question, so ask the host: nothing listening on loopback means a container can
    # publish there. Uses whatever is available - bash's /dev/tcp, else nc, else assume free.
    if { exec 3<>"/dev/tcp/127.0.0.1/$p"; } 2>/dev/null; then
      exec 3>&- 3<&-           # something answered: in use
    else
      [ "$p" != "$preferred" ] && say "$label port $preferred is taken on this machine - using $p instead"
      printf '%s' "$p"; return 0
    fi
    p=$((p + 1))
  done
  die "No free port found for $label near $preferred."
}

say "Setting up Primodel in ./${TARGET_DIR}"
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

say "Downloading compose files"
curl -fsSL "$REPO_RAW/docker-compose.yml" -o docker-compose.yml
curl -fsSL "$REPO_RAW/Caddyfile"          -o Caddyfile
curl -fsSL "$REPO_RAW/primodel.toml"      -o primodel.toml

# The KEK lives in a SoftHSM token, and its image is BUILT from this directory by the compose file —
# without these two files `docker compose up` fails on a missing build context before anything starts.
mkdir -p softhsm
curl -fsSL "$REPO_RAW/softhsm/Dockerfile"   -o softhsm/Dockerfile
curl -fsSL "$REPO_RAW/softhsm/entrypoint.sh" -o softhsm/entrypoint.sh

if [ "$MODE" = lake ]; then
  say "Downloading data-lakehouse overlay (MinIO + Iceberg REST + ClickHouse)"
  curl -fsSL "$REPO_RAW/docker-compose.lake.yml" -o docker-compose.lake.yml
  mkdir -p clickhouse-config
  # ClickHouse reads the MinIO credentials for the iceberg() table function from this named collection,
  # so the query-back cannot work without it.
  curl -fsSL "$REPO_RAW/clickhouse-config/named-collections.xml" -o clickhouse-config/named-collections.xml
fi

say "Downloading GraphiQL explorer (vendored — offline capable)"
mkdir -p graphiql
curl -fsSL "$REPO_RAW/graphiql/index.html"                   -o graphiql/index.html
curl -fsSL "$REPO_RAW/graphiql/graphiql.umd.js"              -o graphiql/graphiql.umd.js
curl -fsSL "$REPO_RAW/graphiql/graphiql.css"                 -o graphiql/graphiql.css
curl -fsSL "$REPO_RAW/graphiql/react.production.min.js"      -o graphiql/react.production.min.js
curl -fsSL "$REPO_RAW/graphiql/react-dom.production.min.js"  -o graphiql/react-dom.production.min.js

# [DEMO ONLY — INSECURE] Download postgres init scripts and demo source data files.
# The compose stack sets PRIMODEL_DEMO_SEED_INSECURE=true which seeds well-known demo passwords.
# NEVER use PRIMODEL_DEMO_SEED_INSECURE on a real install — for evaluation only.
say "Downloading postgres init scripts and demo data files [DEMO ONLY — INSECURE]"
mkdir -p postgres-init demo-data
curl -fsSL "$REPO_RAW/postgres-init/01-create-demo-db.sql" -o postgres-init/01-create-demo-db.sql
for f in organisations.xml persons.json persons_payroll.csv persons_r2.json persons_payroll_r2.csv assignments.xml costcenters.csv invoices.json; do
  curl -fsSL "$REPO_RAW/demo-data/$f" -o "demo-data/$f"
done

FRESH_ENV=0
if [ -f .env ]; then
  say "Reusing existing .env"
else
  FRESH_ENV=1
  say "Generating .env with fresh secrets"
  PRIMODEL_PORT="${PRIMODEL_PORT:-$(free_port 8080 'Studio')}"
  MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-$(free_port 9001 'MinIO console')}"
  CLICKHOUSE_HTTP_PORT="${CLICKHOUSE_HTTP_PORT:-$(free_port 8123 'ClickHouse')}"
  ENC_KEY="$(rand 48)"
  ADMIN_PW="$(rand 12 | tr -d '/+=' | cut -c1-16)"
  cat > .env <<EOF
PRIMODEL_PORT=${PRIMODEL_PORT}
MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT}
CLICKHOUSE_HTTP_PORT=${CLICKHOUSE_HTTP_PORT}
PRIMODEL_IMAGE=${PRIMODEL_IMAGE:-ghcr.io/primodel/primodel:latest}
PRIMODEL_ENCRYPTION_KEY=${ENC_KEY}
PRIMODEL_BOOTSTRAP_PASSWORD=${ADMIN_PW}
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(rand 12 | tr -d '/+=' | cut -c1-16)
POSTGRES_DB=primodel
EOF
  chmod 600 .env
fi

# Stale-data guard: Postgres keeps the password from its FIRST initialization. If a data dir from a
# previous run is still here but we just generated fresh secrets, startup fails with 28P01. We never
# touch existing data (it may be a running/production install) — we only warn.
if [ "$FRESH_ENV" = 1 ] && [ -d data/postgres ] && [ -n "$(ls -A data/postgres 2>/dev/null || true)" ]; then
  printf '\033[1;33mWarning:\033[0m Existing database data in ./%s/data/postgres, but fresh secrets were just generated.\n' "$TARGET_DIR" >&2
  printf '         Postgres will reject the new password (28P01). Either start fresh (DELETES that data):\n' >&2
  printf '           rm -rf ./data     # then re-run\n' >&2
  printf '         or restore the .env that created it (matching POSTGRES_PASSWORD). Not touching your data.\n' >&2
fi

if [ "$MODE" = lake ]; then
  say "Starting Primodel and the lake services — first run pulls ~1 GB, please be patient"
else
  say "Starting Primodel"
fi
if ! dc up -d; then
  printf '[1;33mHint:[0m if a port is already allocated, another service on this machine holds it.
' >&2
  printf '      Override PRIMODEL_PORT (Studio, 8080) or MINIO_CONSOLE_PORT (9001) in ./%s/.env and re-run.
' "$TARGET_DIR" >&2
  die "docker compose could not start the stack (see the error above)."
fi

PORT="$(grep -E '^PRIMODEL_PORT=' .env | cut -d= -f2)"
ADMIN_PW="$(grep -E '^PRIMODEL_BOOTSTRAP_PASSWORD=' .env | cut -d= -f2)"
PORT="${PORT:-8080}"
# Read back rather than reuse this run's default: an EXISTING .env is reused as-is, so ITS ports are the
# ones actually published. Printing 9001 while MinIO listens on 9101 sends a demo viewer to a dead link.
MINIO_CONSOLE="$(grep -E '^MINIO_CONSOLE_PORT=' .env | cut -d= -f2)"
MINIO_CONSOLE="${MINIO_CONSOLE:-9001}"
CH_HTTP="$(grep -E '^CLICKHOUSE_HTTP_PORT=' .env | cut -d= -f2)"
CH_HTTP="${CH_HTTP:-8123}"

# ── Wait for Primodel to become healthy ──────────────────────────────────────
say "Waiting for Primodel to become healthy (this may take up to 2 minutes)…"
HEALTH_URL="http://localhost:${PORT}/api/app-info"
RETRIES=60
until curl -fsS "$HEALTH_URL" >/dev/null 2>&1 || [ "$RETRIES" -eq 0 ]; do
  RETRIES=$((RETRIES - 1))
  printf '.'
  sleep 2
done
echo

if [ "$RETRIES" -eq 0 ]; then
  printf '\033[1;31mError:\033[0m Primodel did not become healthy within 2 minutes.\n' >&2
  printf 'Check logs: docker compose logs primodel\n' >&2
  exit 1
fi

# -- Seed demo data [DEMO ONLY - INSECURE] ------------------------------------
# POST /api/seed-demo-data returns 202 and seeds in the BACKGROUND - the HTTP call returning is not the
# seed finishing. Progress is polled from /api/seed-demo-data/status until it leaves Running, so the
# installer never claims "ready with the demo dataset" over a half-populated database.
# Returns 409 if data already exists (idempotent).
# INSECURE: seeds well-known demo passwords - never set PRIMODEL_DEMO_SEED_INSECURE on a real install.
say "Seeding demo data - this may take 1-2 minutes while integrations run... [DEMO ONLY - INSECURE]"
SEED_URL="http://localhost:${PORT}/api/seed-demo-data"
SEED_STATUS=""
if command -v curl >/dev/null 2>&1; then
  SEED_STATUS="$(curl -s -o /dev/null -w '%{http_code}' -X POST --max-time 300 "$SEED_URL")"
else
  SEED_STATUS="$(wget -q --server-response -O /dev/null --method=POST --timeout=300 "$SEED_URL" 2>&1 | awk '/HTTP\//{print $2}' | tail -1)"
fi

# The seed state as a bare word (Idle|Running|Seeded|Failed|SystemNotEmpty). Parsed with sed rather than
# jq, which is not a dependency we can assume on a machine that has just installed Docker.
seed_state() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS "${SEED_URL}/status" 2>/dev/null | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  else
    wget -qO- "${SEED_URL}/status" 2>/dev/null | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  fi
}

case "$SEED_STATUS" in
  200|202)
    # 300 polls x 2 s = 10 minutes. Generous on purpose: on a cold machine the lake seed also writes
    # Iceberg metadata to MinIO, and giving up early would report failure on a seed that is fine.
    SEED_WAIT=300
    SEED_FINAL=""
    while [ "$SEED_WAIT" -gt 0 ]; do
      SEED_FINAL="$(seed_state)"
      case "$SEED_FINAL" in
        Seeded|Failed|SystemNotEmpty) break ;;
      esac
      SEED_WAIT=$((SEED_WAIT - 1))
      printf '.'
      sleep 2
    done
    echo
    case "$SEED_FINAL" in
      Seeded)         say "Demo data seeded successfully." ;;
      SystemNotEmpty) say "Demo data already present - skipping seed." ;;
      Failed)         printf '\033[1;33mWarning:\033[0m Demo seed FAILED. See: docker compose logs primodel\n' >&2 ;;
      *)              printf '\033[1;33mWarning:\033[0m Demo seed still running after 10 minutes. Check: docker compose logs primodel\n' >&2 ;;
    esac
    ;;
  409) say "Demo data already present - skipping seed." ;;
  *)   printf '\033[1;33mWarning:\033[0m Seed returned HTTP %s. Demo data may be incomplete.\n' "$SEED_STATUS" >&2 ;;
esac

# Lake-only endpoints, appended to the summary. Empty in quick mode so the heredoc stays identical.
if [ "$MODE" = lake ]; then
  LAKE_HELP="
  Lake services:
    MinIO console   http://localhost:${MINIO_CONSOLE}  (minioadmin / minioadmin)
    ClickHouse      http://localhost:${CH_HTTP}/play
    Iceberg REST    internal only — docker compose exec clickhouse curl http://iceberg-rest:8181/v1/namespaces/primodel/tables

  The seed replicates the golden Person entity into Iceberg silver on MinIO. Query it back:
    curl 'http://localhost:${CH_HTTP}/?query=SELECT+*+FROM+iceberg(primodel_lake,filename=%27silver/hr/person%27)+LIMIT+5'
"
else
  LAKE_HELP=""
fi

cat <<EOF

$(say "Primodel is ready with the demo dataset! [DEMO ONLY — INSECURE]")

  ┌─────────────────────────────────────────────────────────────────────────────┐
  │  DEMO ONLY — well-known personas for role-based evaluation                  │
  │  INSECURE: these passwords are publicly known — never use on a real install │
  ├──────────────┬──────────────────┬──────────────────────────────────────────┤
  │  Username    │  Password        │  Role                                     │
  ├──────────────┼──────────────────┼──────────────────────────────────────────┤
  │  admin       │  pri-model-is-great  │  System Administrator               │
  │  ada         │  lovelace        │  Owner (HR + Finance, Restricted)        │
  │  frank       │  borland         │  Schema Steward (HR + Finance)           │
  │  blaise      │  pascal          │  Integrator (HR + Finance)               │
  │  grace       │  hopper          │  Data Reader (HR only, Internal)         │
  └──────────────┴──────────────────┴──────────────────────────────────────────┘

  Sign in at: http://localhost:${PORT}

  Endpoints (all on http://localhost:${PORT}):
    Studio    http://localhost:${PORT}
    REST      http://localhost:${PORT}/api
    GraphQL   http://localhost:${PORT}/graphql
    OpenAPI   http://localhost:${PORT}/openapi/v1.json
    GraphiQL  http://localhost:${PORT}/graphiql  (log into Studio first — auth cookie carries over)

  REST example (as ada — Owner sees unmasked salary):
    curl -u ada:lovelace http://localhost:${PORT}/api/data/Demo/HR/Person/records

  Logs:     (cd ${TARGET_DIR} && docker compose ${COMPOSE_FILES[*]} logs -f primodel)
  Stop:     (cd ${TARGET_DIR} && docker compose ${COMPOSE_FILES[*]} down)
  Reset:    (cd ${TARGET_DIR} && docker compose ${COMPOSE_FILES[*]} down && rm -rf data)
${LAKE_HELP}
Credentials are stored in ./${TARGET_DIR}/.env.

  [DEMO ONLY] See README for the full demo tour: masking, integrations, MDM golden/quarantine,
  DQ workbench, diagrams, and GraphiQL.
EOF

# Open Studio in the default browser
STUDIO_URL="http://localhost:${PORT}"
if command -v open >/dev/null 2>&1; then
  open "$STUDIO_URL"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$STUDIO_URL"
fi
