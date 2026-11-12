#!/usr/bin/env pwsh
#
# Carries persistent state from the old ./data bind-mount layout into the named Docker volumes this
# stack now uses (postgres, nats, softhsm, and - if the lake overlay is present - object-store and
# clickhouse). Safe to run any number of times:
#   - a ./data/<x> directory that doesn't exist, or is empty, is skipped;
#   - a volume that already has data is left alone - this never overwrites anything;
#   - the copy runs `cp -a` in a throwaway alpine container, so ownership and permissions (including
#     the softhsm token directory's) carry over exactly as they were on disk.
#
# install.ps1 (and install.sh) call this automatically on every run, so upgrading users never have to
# think about it. Run it by hand if you set up compose/ yourself instead of using the installer:
#
#   cd compose; .\migrate-data-to-volumes.ps1
#
# Must be run from the directory that holds docker-compose.yml and the .\data directory being
# migrated - the same directory you run `docker compose` from. If you use the lake overlay, run this
# from a directory that also has docker-compose.lake.yml so object-store/clickhouse are included.
$ErrorActionPreference = 'Stop'

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Die($m) { Write-Host "Error: $m" -ForegroundColor Red; exit 1 }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Die 'Docker is required.' }
if (-not (Test-Path 'docker-compose.yml')) { Die 'Run this from the directory that holds docker-compose.yml (and .\data).' }

$ComposeFiles = @('-f', 'docker-compose.yml')
if (Test-Path 'docker-compose.lake.yml') { $ComposeFiles += @('-f', 'docker-compose.lake.yml') }

# Resolve the project name the way `docker compose` itself would (name: in docker-compose.yml,
# overridable with -p/COMPOSE_PROJECT_NAME) instead of hard-coding "primodel" - a second install
# started with -p must migrate into ITS OWN volumes, never another project's.
$Project = $env:COMPOSE_PROJECT_NAME
if (-not $Project) {
  $configOut = (docker compose @ComposeFiles config 2>$null) -join "`n"
  if ($configOut -match '(?m)^name:\s*(\S+)') { $Project = $Matches[1] }
}
if (-not $Project) { Die 'Could not resolve the compose project name.' }

# @{ Src = "<.\data subdirectory>"; Volume = "<volume's short name, as declared in the compose files>" }
$Mappings = @(
  @{ Src = 'data/postgres';       Volume = 'postgres-data' }
  @{ Src = 'data/nats';           Volume = 'nats-data' }
  @{ Src = 'data/softhsm/tokens'; Volume = 'softhsm-tokens' }
  @{ Src = 'data/softhsm/etc';    Volume = 'softhsm-etc' }
  @{ Src = 'data/softhsm/lib';    Volume = 'softhsm-lib' }
  @{ Src = 'data/object-store';   Volume = 'object-store-data' }
  @{ Src = 'data/clickhouse';     Volume = 'clickhouse-data' }
)

$migratedAny = $false
foreach ($m in $Mappings) {
  $src = $m.Src
  $short = $m.Volume

  if (-not (Test-Path $src)) { continue }
  if (-not (Get-ChildItem -Force $src -ErrorAction SilentlyContinue)) { continue }   # exists but empty

  # Prefer a volume compose already created (handles its exact name-sanitising and -p); fall back to
  # the documented default prefix if it doesn't exist yet (e.g. migrating before the first `up`).
  $volume = docker volume ls -q `
    --filter "label=com.docker.compose.volume=$short" `
    --filter "label=com.docker.compose.project=$Project" | Select-Object -First 1
  if (-not $volume) { $volume = "${Project}_$short" }

  docker volume create $volume | Out-Null

  docker run --rm -v "${volume}:/to" alpine sh -c '[ -z "$(ls -A /to 2>/dev/null)" ]' | Out-Null
  if ($LASTEXITCODE -eq 0) {
    $absSrc = (Resolve-Path $src).Path
    Say "Migrating .\$src -> volume $volume"
    docker run --rm -v "${absSrc}:/from:ro" -v "${volume}:/to" alpine cp -a /from/. /to/
    $migratedAny = $true
  } else {
    Say "Volume $volume already has data - leaving it alone (.\$src untouched)."
  }
}

if ($migratedAny) {
  Say "Migration complete. The old .\data directory is left as-is - once you've confirmed the stack"
  Say "starts cleanly and has your data, remove it yourself: Remove-Item -Recurse -Force .\data"
} else {
  Say "Nothing to migrate (no old .\data state found, or it's already in the named volumes)."
}
