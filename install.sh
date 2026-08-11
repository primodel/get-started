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

say "Downloading docker-compose.yml"
curl -fsSL "$REPO_RAW/docker-compose.yml" -o docker-compose.yml

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

cat <<EOF

$(say "Primodel is starting.")

  URL:      http://localhost:${PORT:-8080}
  Sign in:  admin / ${ADMIN_PW:-<see: docker compose logs primodel>}

  Logs:     (cd ${TARGET_DIR} && docker compose logs -f primodel)
  Stop:     (cd ${TARGET_DIR} && docker compose down)
  Reset:    (cd ${TARGET_DIR} && docker compose down -v)   # also deletes data

The credentials above are stored in ./${TARGET_DIR}/.env.
EOF
