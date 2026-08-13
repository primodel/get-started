#!/usr/bin/env bash
#
# Primodel quickstart bootstrap.
#
#   curl -fsSL https://raw.githubusercontent.com/primodel/get-started/main/install.sh | bash
#
# Downloads the compose quickstart into ./primodel, generates secrets, and starts it.
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/primodel/get-started/main/compose"
TARGET_DIR="${PRIMODEL_DIR:-primodel}"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "Docker is required. Install Docker Desktop or Engine: https://docs.docker.com/get-docker/"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required (\`docker compose\`). Update Docker."

rand() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -base64 "$1"
  else head -c "$1" /dev/urandom | base64; fi
}

say "Setting up Primodel in ./${TARGET_DIR}"
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

say "Downloading compose files"
curl -fsSL "$REPO_RAW/docker-compose.yml" -o docker-compose.yml
curl -fsSL "$REPO_RAW/Caddyfile"          -o Caddyfile

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
  ENC_KEY="$(rand 48)"
  ADMIN_PW="$(rand 12 | tr -d '/+=' | cut -c1-16)"
  cat > .env <<EOF
PRIMODEL_PORT=8080
PRIMODEL_IMAGE=ghcr.io/primodel/primodel:latest
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

say "Starting Primodel (docker compose up -d)"
docker compose up -d

PORT="$(grep -E '^PRIMODEL_PORT=' .env | cut -d= -f2)"
ADMIN_PW="$(grep -E '^PRIMODEL_BOOTSTRAP_PASSWORD=' .env | cut -d= -f2)"
PORT="${PORT:-8080}"

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

# ── Seed demo data [DEMO ONLY — INSECURE] ────────────────────────────────────
# POST /api/seed-demo-data BLOCKS until all ingests complete (~30–120 s).
# Returns 200 on success, 409 if data already exists (idempotent).
# INSECURE: seeds well-known demo passwords — never set PRIMODEL_DEMO_SEED_INSECURE on a real install.
say "Seeding demo data — this may take 1–2 minutes while integrations run… [DEMO ONLY — INSECURE]"
SEED_URL="http://localhost:${PORT}/api/seed-demo-data"
SEED_STATUS=""
if command -v curl >/dev/null 2>&1; then
  SEED_STATUS="$(curl -s -o /dev/null -w '%{http_code}' -X POST --max-time 300 "$SEED_URL")"
else
  SEED_STATUS="$(wget -q --server-response -O /dev/null --method=POST --timeout=300 "$SEED_URL" 2>&1 | awk '/HTTP\//{print $2}' | tail -1)"
fi

case "$SEED_STATUS" in
  200) say "Demo data seeded successfully." ;;
  409) say "Demo data already present — skipping seed." ;;
  *)   printf '\033[1;33mWarning:\033[0m Seed returned HTTP %s. Demo data may be incomplete.\n' "$SEED_STATUS" >&2 ;;
esac

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

  Logs:     (cd ${TARGET_DIR} && docker compose logs -f primodel)
  Stop:     (cd ${TARGET_DIR} && docker compose down)
  Reset:    (cd ${TARGET_DIR} && docker compose down && rm -rf data)

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
