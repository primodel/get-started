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

Say "Setting up Primodel in .\$TargetDir"
New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
Set-Location $TargetDir

Say 'Downloading docker-compose.yml'
Invoke-WebRequest -UseBasicParsing "$RepoRaw/docker-compose.yml" -OutFile 'docker-compose.yml'

if (Test-Path '.env') {
  Say 'Reusing existing .env'
} else {
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

Say 'Starting Primodel (docker compose up -d)'
docker compose up -d

$port    = (Select-String -Path '.env' -Pattern '^PRIMODEL_PORT=(.*)$').Matches.Groups[1].Value
$adminPw = (Select-String -Path '.env' -Pattern '^PRIMODEL_BOOTSTRAP_PASSWORD=(.*)$').Matches.Groups[1].Value

Write-Host ''
Say 'Primodel is starting.'
Write-Host ''
Write-Host "  URL:      http://localhost:$port"
Write-Host "  Sign in:  admin / $adminPw"
Write-Host ''
Write-Host "  Logs:     cd $TargetDir; docker compose logs -f primodel"
Write-Host "  Stop:     cd $TargetDir; docker compose down"
Write-Host "  Reset:    cd $TargetDir; docker compose down -v   # also deletes data"
Write-Host ''
Write-Host "Credentials are stored in .\$TargetDir\.env"
