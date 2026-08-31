<#
.SYNOPSIS
  Builds the Flutter web bundle with the project's dart-defines.

.DESCRIPTION
  deploy/README.md says to "build Flutter web with the production API, WSS,
  Google, Apple and Firebase dart-defines", and deploy-mcare3.ps1 excludes
  frontend/build and leaves the build as a manual step. A plain
  `flutter build web` therefore produces a bundle with none of them, and the
  app tells users that Google sign-in "is not configured for this application
  build" - the feature is not broken, it was simply never told its client ID.

  This wraps the build so those values always come along, from the same
  frontend/config/app_config.local.json the dev runner uses.

.PARAMETER ApiUrl
  Overrides MCARE_API_URL from the config file, e.g. for a staging bundle.

.PARAMETER Release
  Build in release mode (default). Use -Profile for a profile build.

.EXAMPLE
  ./scripts/build-web.ps1
  ./scripts/build-web.ps1 -ApiUrl https://staging.matendocare.com/api/v1
#>

[CmdletBinding()]
param(
  [string] $ApiUrl,
  [switch] $ProfileBuild,
  [string] $ConfigFile
)

$ErrorActionPreference = "Stop"

$LocalRoot = Split-Path -Parent $PSScriptRoot
$Frontend = Join-Path $LocalRoot "frontend"
if (-not $ConfigFile) {
  $ConfigFile = Join-Path $Frontend "config\app_config.local.json"
}

. (Join-Path $PSScriptRoot "dart-defines.ps1")

if (-not (Get-Command flutter.bat -ErrorAction SilentlyContinue)) {
  Write-Host "'flutter' not found on PATH. Install Flutter and re-open the terminal." -ForegroundColor Red
  exit 1
}
$FlutterExecutable = (Get-Command flutter.bat -All | Select-Object -First 1).Source

Write-Host "==> Collecting dart-defines" -ForegroundColor Cyan
$fromConfig = Get-McareConfigDefines $ConfigFile

$explicit = @()
if ($ApiUrl) {
  $explicit += "--dart-define=MCARE_API_URL=$ApiUrl"
}
$defines = Merge-McareDefines -FromConfig $fromConfig -Explicit $explicit

# A web bundle with no client ID builds and deploys perfectly happily, and the
# failure only appears when a user taps Google. Say so at build time instead.
if (-not ($defines | Where-Object { $_ -like '--dart-define=MCARE_GOOGLE_CLIENT_ID=*' })) {
  Write-Host ""
  Write-Host "  WARNING: no MCARE_GOOGLE_CLIENT_ID in this build." -ForegroundColor Yellow
  Write-Host "  Google sign-in will report itself unconfigured to every user." -ForegroundColor Yellow
  Write-Host "  It must be the same client ID as backend/.env GOOGLE_CLIENT_ID," -ForegroundColor Yellow
  Write-Host "  or the API will reject the token it returns as an audience mismatch." -ForegroundColor Yellow
  Write-Host ""
}

$mode = if ($ProfileBuild) { "--profile" } else { "--release" }

Push-Location $Frontend
try {
  Write-Host "==> flutter build web $mode" -ForegroundColor Cyan
  $flutterArguments = @("build", "web", $mode) + $defines
  & $FlutterExecutable @flutterArguments
  if ($LASTEXITCODE -ne 0) { throw "flutter build web failed" }
} finally {
  Pop-Location
}

Write-Host ""
Write-Host "Built frontend/build/web" -ForegroundColor Green
Write-Host "Upload that directory to the web root (see scripts/deploy-mcare3.ps1)." -ForegroundColor Green
