#!/usr/bin/env pwsh
#
# Primodel quickstart bootstrap (Windows / PowerShell).
#
#   irm https://primodel.io/install.ps1 | iex
#
# Downloads the compose quickstart into .\primodel, generates secrets, and starts it.
$ErrorActionPreference = 'Stop'

# Overridable so a fork, an internal mirror, or a local checkout can be installed from - and so the
# installer itself can be exercised end-to-end without publishing anything.
$RepoRaw   = if ($env:PRIMODEL_REPO_RAW) { $env:PRIMODEL_REPO_RAW } else { 'https://raw.githubusercontent.com/primodel/get-started/main/compose' }
$TargetDir = if ($env:PRIMODEL_DIR) { $env:PRIMODEL_DIR } else { 'primodel' }

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Die($m) { Write-Host "Error: $m" -ForegroundColor Red; exit 1 }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Die 'Docker is required. Install Docker Desktop: https://docs.docker.com/get-docker/'
}
try { docker compose version *> $null } catch { Die 'Docker Compose v2 is required (`docker compose`). Update Docker Desktop.' }

function New-Secret([int]$bytes) {
  $b = New-Object byte[] $bytes
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  [Convert]::ToBase64String($b)
}
function New-Password([int]$len) { ((New-Secret 32) -replace '[/+=]', '').Substring(0, $len) }

function Fetch($url, $dest) {
  $dir = Split-Path $dest
  if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Invoke-WebRequest -UseBasicParsing $url -OutFile $dest
}

# -- Which stack? -------------------------------------------------------------
# quick = Primodel + Postgres + NATS + Caddy.
# lake  = the above PLUS MinIO + Iceberg REST catalog + ClickHouse, so the demo shows the governed
#         lakehouse round-trip (canonical store -> Iceberg silver -> queried back through ClickHouse).
#
# Resolution order: -Lake/-Quick argument, then $env:PRIMODEL_MODE, then an interactive prompt, then
# quick. Arguments only arrive when the script is RUN AS A FILE; the documented `irm ... | iex` form
# cannot pass any, which is why the environment variable exists as the non-interactive escape hatch.
$mode = $env:PRIMODEL_MODE
foreach ($a in $args) {
  switch -Regex ($a) {
    '^-{1,2}(lake|full)$' { $mode = 'lake' }
    '^-{1,2}quick$'       { $mode = 'quick' }
    default { Die "Unknown option: $a (use -Quick or -Lake)" }
  }
}

if (-not $mode) {
  # Read-Host throws where no console is attached (CI, a scheduled task). That is not an error worth
  # failing an install over - it just means nobody is there to answer, so take the quick default.
  try {
    Write-Host ''
    Write-Host '  Which demo would you like?'
    Write-Host ''
    Write-Host '    1) Quick start    Primodel + Postgres + NATS. Fastest, smallest download.'
    Write-Host '    2) Data lakehouse Adds MinIO + Iceberg + ClickHouse, and shows the governed'
    Write-Host '                      round-trip: canonical store -> Iceberg -> queried back via ClickHouse.'
    Write-Host '                      Pulls ~1 GB more and takes a few minutes longer to start.'
    Write-Host ''
    $answer = Read-Host '  Choice [1]'
    Write-Host ''
    $mode = if ($answer -match '^\s*(2|lake)\s*$') { 'lake' } else { 'quick' }
  } catch {
    $mode = 'quick'
  }
}

if ($mode -eq 'lake') {
  $ComposeFiles = @('-f', 'docker-compose.yml', '-f', 'docker-compose.lake.yml')
  Say 'Installing the data-lakehouse demo (Primodel + Postgres + NATS + MinIO + Iceberg + ClickHouse)'
} else {
  $ComposeFiles = @('-f', 'docker-compose.yml')
  Say 'Installing the quick-start demo (Primodel + Postgres + NATS)'
}

# Shown in the closing hints so Stop/Reset target the SAME stack that was started - a `docker compose
# down` without the overlay leaves the lake containers running against a stopped Primodel.
$ComposeArgs = $ComposeFiles -join ' '

Say "Setting up Primodel in .\$TargetDir"
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
Set-Location $TargetDir

Say 'Downloading compose files'
Fetch "$RepoRaw/docker-compose.yml" 'docker-compose.yml'
Fetch "$RepoRaw/Caddyfile"          'Caddyfile'
Fetch "$RepoRaw/primodel.toml"      'primodel.toml'

# The KEK lives in a SoftHSM token whose image is BUILT from this directory by the compose file -
# without these two files `docker compose up` fails on a missing build context before anything starts.
Fetch "$RepoRaw/softhsm/Dockerfile"    'softhsm/Dockerfile'
Fetch "$RepoRaw/softhsm/entrypoint.sh" 'softhsm/entrypoint.sh'

if ($mode -eq 'lake') {
  Say 'Downloading data-lakehouse overlay (MinIO + Iceberg REST + ClickHouse)'
  Fetch "$RepoRaw/docker-compose.lake.yml" 'docker-compose.lake.yml'
  # ClickHouse reads the MinIO credentials for the iceberg() table function from this named collection,
  # so the query-back cannot work without it.
  Fetch "$RepoRaw/clickhouse-config/named-collections.xml" 'clickhouse-config/named-collections.xml'
}

Say 'Downloading GraphiQL explorer (vendored — offline capable)'
Fetch "$RepoRaw/graphiql/index.html"                  'graphiql/index.html'
Fetch "$RepoRaw/graphiql/graphiql.umd.js"             'graphiql/graphiql.umd.js'
Fetch "$RepoRaw/graphiql/graphiql.css"                'graphiql/graphiql.css'
Fetch "$RepoRaw/graphiql/react.production.min.js"     'graphiql/react.production.min.js'
Fetch "$RepoRaw/graphiql/react-dom.production.min.js" 'graphiql/react-dom.production.min.js'

# [DEMO ONLY — INSECURE] Download postgres init scripts and demo source data files.
# The compose stack sets PRIMODEL_DEMO_SEED_INSECURE=true which seeds well-known demo passwords.
# NEVER use PRIMODEL_DEMO_SEED_INSECURE on a real install — for evaluation only.
Say 'Downloading postgres init scripts and demo data files [DEMO ONLY — INSECURE]'
Fetch "$RepoRaw/postgres-init/01-create-demo-db.sql" 'postgres-init/01-create-demo-db.sql'
foreach ($f in @('organisations.xml','persons.json','persons_payroll.csv','persons_r2.json','persons_payroll_r2.csv','assignments.xml','costcenters.csv','invoices.json')) {
  Fetch "$RepoRaw/demo-data/$f" "demo-data/$f"
}

$freshEnv = $false
if (Test-Path '.env') {
  Say 'Reusing existing .env'
} else {
  $freshEnv = $true
  Say 'Generating .env with fresh secrets'
  $enc     = New-Secret 48
  $adminPw = New-Password 16
  $pgPw    = New-Password 16
  @"
PRIMODEL_PORT=8080
PRIMODEL_IMAGE=ghcr.io/primodel/primodel:latest
PRIMODEL_ENCRYPTION_KEY=$enc
PRIMODEL_BOOTSTRAP_PASSWORD=$adminPw
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$pgPw
POSTGRES_DB=primodel
"@ | Set-Content -Path '.env'
}

# Stale-data guard: Postgres keeps the password from its first init. Fresh secrets + a leftover data
# dir from a previous run => 28P01 at startup. We never touch existing data — just warn.
if ($freshEnv -and (Test-Path 'data/postgres') -and (Get-ChildItem 'data/postgres' -Force -ErrorAction SilentlyContinue)) {
  Write-Host "Warning: Existing database data in .\$TargetDir\data\postgres, but fresh secrets were just generated." -ForegroundColor Yellow
  Write-Host "         Postgres will reject the new password (28P01). Start fresh (DELETES that data):" -ForegroundColor Yellow
  Write-Host "           Remove-Item -Recurse -Force .\data     # then re-run" -ForegroundColor Yellow
  Write-Host "         or restore the .env that created it (matching POSTGRES_PASSWORD). Not touching your data." -ForegroundColor Yellow
}

if ($mode -eq 'lake') {
  Say 'Starting Primodel and the lake services - first run pulls ~1 GB, please be patient'
} else {
  Say 'Starting Primodel'
}
docker compose @ComposeFiles up -d

$port    = (Select-String -Path '.env' -Pattern '^PRIMODEL_PORT=(.*)$').Matches.Groups[1].Value
$adminPw = (Select-String -Path '.env' -Pattern '^PRIMODEL_BOOTSTRAP_PASSWORD=(.*)$').Matches.Groups[1].Value
if (-not $port) { $port = '8080' }

# ── Wait for Primodel to become healthy ──────────────────────────────────────
Say 'Waiting for Primodel to become healthy (this may take up to 2 minutes)…'
$healthUrl = "http://localhost:$port/api/app-info"
$retries   = 60
$healthy   = $false
while ($retries -gt 0 -and -not $healthy) {
  try {
    Invoke-RestMethod $healthUrl -Method Get -TimeoutSec 3 | Out-Null
    $healthy = $true
  } catch {
    $retries--
    Write-Host -NoNewline '.'
    Start-Sleep 2
  }
}
Write-Host ''

if (-not $healthy) {
  Write-Host 'Error: Primodel did not become healthy within 2 minutes.' -ForegroundColor Red
  Write-Host 'Check logs: docker compose logs primodel' -ForegroundColor Red
  exit 1
}

# -- Seed demo data [DEMO ONLY - INSECURE] ------------------------------------
# POST /api/seed-demo-data returns 202 and seeds in the BACKGROUND - the HTTP call returning is not the
# seed finishing. Progress is polled from /api/seed-demo-data/status until it leaves Running, so the
# installer never claims "ready with the demo dataset" over a half-populated database.
# Returns 409 if data already exists (idempotent).
# INSECURE: seeds well-known demo passwords - never set PRIMODEL_DEMO_SEED_INSECURE on a real install.
Say 'Seeding demo data - this may take 1-2 minutes while integrations run... [DEMO ONLY - INSECURE]'
$seedUrl    = "http://localhost:$port/api/seed-demo-data"
$seedStatus = 0
try {
  $resp = Invoke-WebRequest -Method Post -Uri $seedUrl -TimeoutSec 300 -UseBasicParsing
  $seedStatus = $resp.StatusCode
} catch {
  if ($_.Exception.Response) { $seedStatus = [int]$_.Exception.Response.StatusCode }
}

if ($seedStatus -eq 200 -or $seedStatus -eq 202) {
  # 300 polls x 2 s = 10 minutes. Generous on purpose: on a cold machine the lake seed also writes
  # Iceberg metadata to MinIO, and giving up early would report failure on a seed that is fine.
  $seedWait  = 300
  $seedFinal = ''
  while ($seedWait -gt 0 -and $seedFinal -notin @('Seeded', 'Failed', 'SystemNotEmpty')) {
    try { $seedFinal = (Invoke-RestMethod "$seedUrl/status" -TimeoutSec 5).state } catch { $seedFinal = '' }
    if ($seedFinal -in @('Seeded', 'Failed', 'SystemNotEmpty')) { break }
    $seedWait--
    Write-Host -NoNewline '.'
    Start-Sleep 2
  }
  Write-Host ''
  switch ($seedFinal) {
    'Seeded'         { Say 'Demo data seeded successfully.' }
    'SystemNotEmpty' { Say 'Demo data already present - skipping seed.' }
    'Failed'         { Write-Host 'Warning: Demo seed FAILED. See: docker compose logs primodel' -ForegroundColor Yellow }
    default          { Write-Host 'Warning: Demo seed still running after 10 minutes. Check: docker compose logs primodel' -ForegroundColor Yellow }
  }
} elseif ($seedStatus -eq 409) {
  Say 'Demo data already present - skipping seed.'
} else {
  Write-Host "Warning: Seed returned HTTP $seedStatus. Demo data may be incomplete." -ForegroundColor Yellow
}

Write-Host ''

Say 'Primodel is ready with the demo dataset! [DEMO ONLY — INSECURE]'
Write-Host ''
Write-Host '  +---------------------------------------------------------------------------+'
Write-Host '  |  DEMO ONLY — well-known personas for role-based evaluation                |'
Write-Host '  |  INSECURE: these passwords are publicly known — never use on real install |'
Write-Host '  +---------------+--------------------+-------------------------------------+'
Write-Host '  |  Username     |  Password          |  Role                               |'
Write-Host '  +---------------+--------------------+-------------------------------------+'
Write-Host '  |  admin        |  pri-model-is-great|  System Administrator               |'
Write-Host '  |  ada          |  lovelace          |  Owner (HR + Finance, Restricted)   |'
Write-Host '  |  frank        |  borland           |  Schema Steward (HR + Finance)      |'
Write-Host '  |  blaise       |  pascal            |  Integrator (HR + Finance)          |'
Write-Host '  |  grace        |  hopper            |  Data Reader (HR only, Internal)    |'
Write-Host '  +---------------+--------------------+-------------------------------------+'
Write-Host ''
Write-Host "  Sign in at: http://localhost:$port"
Write-Host ''
Write-Host "  Endpoints (all on http://localhost:$port):"
Write-Host "    Studio    http://localhost:$port"
Write-Host "    REST      http://localhost:$port/api"
Write-Host "    GraphQL   http://localhost:$port/graphql"
Write-Host "    OpenAPI   http://localhost:$port/openapi/v1.json"
Write-Host "    GraphiQL  http://localhost:$port/graphiql  (log into Studio first — auth cookie carries over)"
Write-Host ''
Write-Host '  REST example (as ada — Owner sees unmasked salary):'
Write-Host "    Invoke-RestMethod http://localhost:$port/api/data/Demo/HR/Person/records -Credential (Get-Credential)"
Write-Host ''
Write-Host "  Logs:     cd $TargetDir; docker compose $ComposeArgs logs -f primodel"
Write-Host "  Stop:     cd $TargetDir; docker compose $ComposeArgs down"
Write-Host "  Reset:    cd $TargetDir; docker compose $ComposeArgs down; Remove-Item -Recurse -Force data"
if ($mode -eq 'lake') {
  Write-Host ''
  Write-Host '  Lake services:'
  Write-Host '    MinIO console   http://localhost:9001  (minioadmin / minioadmin)'
  Write-Host '    Iceberg REST    http://localhost:8181/v1/namespaces/primodel/tables'
  Write-Host '    ClickHouse      http://localhost:8123/play'
  Write-Host ''
  Write-Host '  The seed replicates the golden Person entity into Iceberg silver on MinIO. Query it back'
  Write-Host '  from ClickHouse at http://localhost:8123/play :'
  Write-Host "    SELECT * FROM iceberg(primodel_lake, filename='silver/hr/person') LIMIT 5"
}
Write-Host ''
Write-Host "  [DEMO ONLY] See README for the full demo tour: masking, integrations, MDM golden/quarantine,"
Write-Host '  DQ workbench, diagrams, and GraphiQL.'
Write-Host ''
Write-Host "Credentials are stored in .\$TargetDir\.env"

# Open Studio in the default browser
Start-Process "http://localhost:$port"
