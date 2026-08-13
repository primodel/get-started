#!/usr/bin/env pwsh
#
# Primodel quickstart bootstrap (Windows / PowerShell).
#
#   irm https://primodel.io/install.ps1 | iex
#
# Downloads the compose quickstart into .\primodel, generates secrets, and starts it.
$ErrorActionPreference = 'Stop'

$RepoRaw   = 'https://raw.githubusercontent.com/primodel/get-started/main/compose'
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

Say "Setting up Primodel in .\$TargetDir"
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
Set-Location $TargetDir

Say 'Downloading compose files'
Fetch "$RepoRaw/docker-compose.yml" 'docker-compose.yml'
Fetch "$RepoRaw/Caddyfile"          'Caddyfile'

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

Say 'Starting Primodel (docker compose up -d)'
docker compose up -d

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

# ── Seed demo data [DEMO ONLY — INSECURE] ────────────────────────────────────
# POST /api/seed-demo-data BLOCKS until all ingests complete (~30–120 s).
# Returns 200 on success, 409 if data already exists (idempotent).
# INSECURE: seeds well-known demo passwords — never set PRIMODEL_DEMO_SEED_INSECURE on a real install.
Say 'Seeding demo data — this may take 1–2 minutes while integrations run… [DEMO ONLY — INSECURE]'
$seedUrl    = "http://localhost:$port/api/seed-demo-data"
$seedStatus = 0
try {
  $resp = Invoke-WebRequest -Method Post -Uri $seedUrl -TimeoutSec 300 -UseBasicParsing
  $seedStatus = $resp.StatusCode
} catch {
  if ($_.Exception.Response) { $seedStatus = [int]$_.Exception.Response.StatusCode }
}

switch ($seedStatus) {
  200   { Say 'Demo data seeded successfully.' }
  409   { Say 'Demo data already present — skipping seed.' }
  default { Write-Host "Warning: Seed returned HTTP $seedStatus. Demo data may be incomplete." -ForegroundColor Yellow }
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
Write-Host "  Logs:     cd $TargetDir; docker compose logs -f primodel"
Write-Host "  Stop:     cd $TargetDir; docker compose down"
Write-Host "  Reset:    cd $TargetDir; docker compose down; Remove-Item -Recurse -Force data"
Write-Host ''
Write-Host "  [DEMO ONLY] See README for the full demo tour: masking, integrations, MDM golden/quarantine,"
Write-Host '  DQ workbench, diagrams, and GraphiQL.'
Write-Host ''
Write-Host "Credentials are stored in .\$TargetDir\.env"

# Open Studio in the default browser
Start-Process "http://localhost:$port"
