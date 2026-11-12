#!/usr/bin/env bash
#
# Carries persistent state from the old ./data bind-mount layout into the named Docker volumes this
# stack now uses (postgres, nats, softhsm, and — if the lake overlay is present — object-store and
# clickhouse). Safe to run any number of times:
#   - a ./data/<x> directory that doesn't exist, or is empty, is skipped;
#   - a volume that already has data is left alone — this never overwrites anything;
#   - the copy runs `cp -a` in a throwaway alpine container, so ownership and permissions (including
#     the softhsm token directory's) carry over exactly as they were on disk.
#
# install.sh and install.ps1 call this automatically on every run, so upgrading users never have to
# think about it. Run it by hand if you set up compose/ yourself instead of using the installer:
#
#   cd compose && ./migrate-data-to-volumes.sh
#
# Must be run from the directory that holds docker-compose.yml and the ./data directory being
# migrated — the same directory you run `docker compose` from. If you use the lake overlay, run this
# from a directory that also has docker-compose.lake.yml so object-store/clickhouse are included.
set -euo pipefail

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "Docker is required."
[ -f docker-compose.yml ] || die "Run this from the directory that holds docker-compose.yml (and ./data)."

# Git Bash on Windows (MSYS) rewrites absolute-looking arguments before they reach docker, which
# mangles container-side paths like /from and /to below. This script only runs host-path resolution
# through `cd .. && pwd`, which MSYS already renders as a Windows-usable path, so disable that
# rewriting for the rest of the arguments.
export MSYS_NO_PATHCONV=1

COMPOSE_FILES=(-f docker-compose.yml)
[ -f docker-compose.lake.yml ] && COMPOSE_FILES+=(-f docker-compose.lake.yml)
dc() { docker compose "${COMPOSE_FILES[@]}" "$@"; }

# Resolve the project name the way `docker compose` itself would (name: in docker-compose.yml,
# overridable with -p/COMPOSE_PROJECT_NAME) instead of hard-coding "primodel" — a second install
# started with -p must migrate into ITS OWN volumes, never another project's.
PROJECT="${COMPOSE_PROJECT_NAME:-}"
if [ -z "$PROJECT" ]; then
  PROJECT="$(dc config 2>/dev/null | awk -F': ' '/^name:/{print $2; exit}')"
fi
[ -n "$PROJECT" ] || die "Could not resolve the compose project name."

# "<./data subdirectory>:<volume's short name, as declared in the compose files>"
MAPPINGS=(
  "data/postgres:postgres-data"
  "data/nats:nats-data"
  "data/softhsm/tokens:softhsm-tokens"
  "data/softhsm/etc:softhsm-etc"
  "data/softhsm/lib:softhsm-lib"
  "data/object-store:object-store-data"
  "data/clickhouse:clickhouse-data"
)

migrated_any=0
for mapping in "${MAPPINGS[@]}"; do
  src="${mapping%%:*}"
  short="${mapping##*:}"

  [ -d "$src" ] || continue
  [ -n "$(ls -A "$src" 2>/dev/null)" ] || continue   # directory exists but is empty

  # Prefer a volume compose already created (handles its exact name-sanitising and -p); fall back to
  # the documented default prefix if it doesn't exist yet (e.g. migrating before the first `up`).
  volume="$(docker volume ls -q \
    --filter "label=com.docker.compose.volume=${short}" \
    --filter "label=com.docker.compose.project=${PROJECT}" 2>/dev/null | head -n1)"
  [ -n "$volume" ] || volume="${PROJECT}_${short}"

  docker volume create "$volume" >/dev/null

  if docker run --rm -v "${volume}:/to" alpine sh -c '[ -z "$(ls -A /to 2>/dev/null)" ]'; then
    say "Migrating ./${src} -> volume ${volume}"
    docker run --rm \
      -v "$(cd "$src" && pwd)":/from:ro \
      -v "${volume}:/to" \
      alpine cp -a /from/. /to/
    migrated_any=1
  else
    say "Volume ${volume} already has data — leaving it alone (./${src} untouched)."
  fi
done

if [ "$migrated_any" = 1 ]; then
  say "Migration complete. The old ./data directory is left as-is — once you've confirmed the stack"
  say "starts cleanly and has your data, remove it yourself: rm -rf ./data"
else
  say "Nothing to migrate (no old ./data state found, or it's already in the named volumes)."
fi
