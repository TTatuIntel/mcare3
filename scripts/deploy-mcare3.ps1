# Deploy mCare → EC2 /var/www/mcare3
# Run from Windows PowerShell in the project root.
#
# Prerequisites:
#   - OpenSSH client (Windows 10+)
#   - Your EC2 .pem key
#   - Replace KEY and HOST below

param(
  [string]$Key = "$env:USERPROFILE\.ssh\tattuintel.pem",
  [string]$HostName = "ubuntu@184.73.16.70",
  [string]$RemotePath = "/var/www/mcare3"
)

$ErrorActionPreference = "Stop"
$LocalRoot = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $Key)) {
  Write-Host "SSH key not found: $Key"
  Write-Host "Pass -Key path\to\your.pem"
  exit 1
}

Write-Host "==> Ensuring remote directory $RemotePath"
ssh -i $Key $HostName "sudo mkdir -p $RemotePath && sudo chown -R ubuntu:ubuntu $RemotePath"

Write-Host "==> Uploading code (excludes vendor, node_modules, .git, local build junk)"
# Requires tar + ssh. Uses a filtered archive for speed.
$exclude = @(
  "--exclude=.git",
  "--exclude=backend/vendor",
  "--exclude=backend/node_modules",
  "--exclude=backend/storage/logs/*",
  "--exclude=backend/storage/framework/cache/*",
  "--exclude=backend/storage/framework/sessions/*",
  "--exclude=backend/storage/framework/views/*",
  "--exclude=frontend/.dart_tool",
  "--exclude=frontend/build",
  "--exclude=frontend/.flutter-plugins-dependencies",
  "--exclude=**/.DS_Store"
)

# Git Bash / WSL tar preferred; fall back message if missing
$tar = Get-Command tar -ErrorAction SilentlyContinue
if (-not $tar) {
  Write-Host "tar not found. Install Git for Windows or use WSL, then re-run."
  exit 1
}

Push-Location $LocalRoot
try {
  & tar -czf - @exclude backend frontend scripts resources README.md 2>$null |
    ssh -i $Key $HostName "tar -xzf - -C $RemotePath"
} finally {
  Pop-Location
}

Write-Host "==> Upload .env separately (never commit secrets)"
$envFile = Join-Path $LocalRoot "backend\.env"
if (Test-Path $envFile) {
  scp -i $Key $envFile "${HostName}:${RemotePath}/backend/.env"
} else {
  Write-Host "No local backend/.env — create one on the server"
}

Write-Host "==> Remote bootstrap"
ssh -i $Key $HostName "sudo bash $RemotePath/scripts/server-bootstrap-mcare3.sh"

Write-Host @"

Next on server:
  1) Edit $RemotePath/backend/.env
       APP_ENV=production
       APP_DEBUG=false
       DB_DATABASE=mcare3
       DB_USERNAME=mcare3
       DB_PASSWORD=<strong>
  2) sudo MCARE3_DB_PASSWORD='...' bash $RemotePath/scripts/db-migrate-mcare3.sh fresh
     OR import old dump:
       mysqldump ... > /tmp/mcare_old.sql
       sudo MCARE3_DB_PASSWORD='...' bash $RemotePath/scripts/db-migrate-mcare3.sh import /tmp/mcare_old.sql
  3) cd $RemotePath/backend && php artisan migrate --force
  4) Build web locally and upload frontend/build/web
  5) After live OK: sudo bash $RemotePath/scripts/db-migrate-mcare3.sh drop-old OLD_DB_NAME
"@
