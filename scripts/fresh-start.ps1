# Fresh-start mCare3 locally: wipe the DB, re-migrate, install synthetic data,
# then serve the Laravel API, the realtime stack and the Flutter web app.
#
# The realtime stack is three long-running hidden processes with logs under
# backend/storage/logs/local-runtime/:
#   reverb:start   the websocket server clients subscribe to
#   queue:work     drains broadcasts; without it they pile up in `jobs`
#   schedule:work  ticks the hourly vitals SLA escalation
# Without all three the app still works; it falls back to a 30s REST poll.
#
# Run from Windows PowerShell anywhere:
#   .\scripts\fresh-start.ps1
#
# Prerequisites:
#   - XAMPP MySQL running on 127.0.0.1:3306
#   - php, composer and flutter on PATH
#
# Examples:
#   .\scripts\fresh-start.ps1                  # full reset, prompts before dropping tables
#   .\scripts\fresh-start.ps1 -Force           # no prompt (CI / repeat runs)
#   .\scripts\fresh-start.ps1 -SkipDeps        # skip composer install + flutter clean/pub get
#   .\scripts\fresh-start.ps1 -SkipFrontend    # backend reset + API only
#   .\scripts\fresh-start.ps1 -MockMode        # frontend only, in-memory demo data, no backend
#   .\scripts\fresh-start.ps1 -ResetOnly       # reseed the DB and exit without serving
#   .\scripts\fresh-start.ps1 -SkipReset       # start services without changing stored data
#   .\scripts\fresh-start.ps1 -FlutterDevice web-server
#       # headless web server; open the printed app URL before hot restart

param(
  [int]$ApiPort      = 8000,
  [int]$WebPort      = 8090,
  [switch]$Force,
  [switch]$SkipDeps,
  [switch]$SkipFrontend,
  [switch]$MockMode,
  [switch]$ResetOnly,
  [switch]$SkipReset,
  [int]$ReverbPort   = 8080,
  [switch]$NoRealtime,
  [string]$FlutterDevice = "chrome"
)

$ErrorActionPreference = "Stop"

$LocalRoot = Split-Path -Parent $PSScriptRoot
$Backend   = Join-Path $LocalRoot "backend"
$Frontend  = Join-Path $LocalRoot "frontend"
$ApiUrl    = "http://127.0.0.1:$ApiPort"
$RuntimeLogDirectory = Join-Path $Backend "storage\logs\local-runtime"
$RuntimePidDirectory = Join-Path $Backend "storage\framework\mcare-runtime"
$StartedRuntimeProcesses = @()
$FlutterExecutable = $null

function Require-Command($name, $hint) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    Write-Host "'$name' not found on PATH. $hint" -ForegroundColor Red
    exit 1
  }
}

function Invoke-Flutter([string[]]$Defines) {
  $flutterArguments = @("run", "-d", $FlutterDevice)
  if ($FlutterDevice -in @("chrome", "web-server")) {
    $flutterArguments += @("--web-hostname", "localhost", "--web-port", "$WebPort")
  }
  $flutterArguments += $Defines

  if ($FlutterDevice -eq "web-server") {
    Write-Host "Open http://localhost:$WebPort in a browser before using hot restart." -ForegroundColor Yellow
  }

  & $script:FlutterExecutable @flutterArguments
}

# ---------------------------------------------------------------- mock mode
if ($MockMode) {
  Require-Command flutter.bat "Install Flutter and re-open the terminal."
  $FlutterExecutable = (Get-Command flutter.bat -All | Select-Object -First 1).Source
  Write-Host "==> Explicit UI fixture mode: in-memory data, no backend" -ForegroundColor Cyan
  Push-Location $Frontend
  try {
    Invoke-Flutter @(
      "--dart-define=MCARE_USE_BACKEND=false",
      "--dart-define=MCARE_ALLOW_DEMO_DATA=true"
    )
  } finally { Pop-Location }
  exit $LASTEXITCODE
}

Require-Command php "Add C:\xampp\php to PATH."
if (-not $SkipDeps) { Require-Command composer "Install Composer from getcomposer.org." }

# ------------------------------------------------------------- preflight
Write-Host "==> Checking MySQL on 127.0.0.1:3306" -ForegroundColor Cyan
$mysqlUp = Test-NetConnection -ComputerName 127.0.0.1 -Port 3306 -InformationLevel Quiet -WarningAction SilentlyContinue
if (-not $mysqlUp) {
  Write-Host "MySQL is not accepting connections on 3306." -ForegroundColor Red
  Write-Host "Start it from the XAMPP Control Panel (C:\xampp\xampp-control.exe), then re-run."
  exit 1
}

$envFile = Join-Path $Backend ".env"
if (-not (Test-Path $envFile)) {
  Write-Host "backend\.env is missing. Copy .env.example to .env and set DB_DATABASE first." -ForegroundColor Red
  exit 1
}
$envText = Get-Content $envFile -Raw

# APP_URL pointing at production breaks locally generated storage/asset URLs.
$appUrl = ([regex]::Match($envText, '(?m)^APP_URL=(.*)$')).Groups[1].Value.Trim()
if ($appUrl -and $appUrl -notmatch '127\.0\.0\.1|localhost') {
  Write-Host "WARNING: APP_URL is '$appUrl'; storage and asset URLs will point away from localhost." -ForegroundColor Yellow
  Write-Host "         Set APP_URL=$ApiUrl in backend\.env for local work." -ForegroundColor Yellow
}

$dbName = ([regex]::Match($envText, '(?m)^DB_DATABASE=(.*)$')).Groups[1].Value.Trim()
if (-not $dbName) { $dbName = "(unset)" }

# ---------------------------------------------------------------- confirm
if (-not $SkipReset -and -not $Force) {
  Write-Host ""
  Write-Host "This DROPS EVERY TABLE in database '$dbName' and installs synthetic test data." -ForegroundColor Yellow
  $answer = Read-Host "Type 'yes' to continue"
  if ($answer -ne "yes") { Write-Host "Aborted."; exit 1 }
}

Push-Location $Backend
try {
  if (-not $SkipDeps) {
    Write-Host "==> composer install" -ForegroundColor Cyan
    & composer install
    if ($LASTEXITCODE -ne 0) { throw "composer install failed" }
  }

  if ($envText -notmatch '(?m)^APP_KEY=.+$') {
    Write-Host "==> Generating APP_KEY" -ForegroundColor Cyan
    & php artisan key:generate
  }

  Write-Host "==> Clearing cached config, routes and views" -ForegroundColor Cyan
  & php artisan optimize:clear

  if ($SkipReset) {
    Write-Host "==> Preserving the existing database (-SkipReset)" -ForegroundColor Green
  } else {
    Write-Host "==> migrate:fresh --seed  (24 migrations, 7 domain seeders)" -ForegroundColor Cyan
    & php artisan migrate:fresh --seed
    if ($LASTEXITCODE -ne 0) { throw "migrate:fresh --seed failed" }

    Write-Host "==> Linking public storage" -ForegroundColor Cyan
    & php artisan storage:link 2>&1 | Out-Null

    Write-Host "==> Verifying seed data" -ForegroundColor Cyan
    & php artisan mcare:demo-status --strict
    if ($LASTEXITCODE -ne 0) { throw "seed dataset verification failed" }
    Write-Host ""
  }
} finally {
  Pop-Location
}

if ($ResetOnly) {
  Write-Host "Database reset complete. Skipping servers (-ResetOnly)." -ForegroundColor Green
  exit 0
}

# ------------------------------------------------- long-running processes
$phpExecutable = (Get-Command php).Source
New-Item -ItemType Directory -Path $RuntimeLogDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $RuntimePidDirectory -Force | Out-Null

function Get-TrackedPhpProcess([string]$Name) {
  $pidFile = Join-Path $RuntimePidDirectory "$Name.pid"
  if (-not (Test-Path $pidFile)) { return $null }

  $trackedPid = 0
  if (-not [int]::TryParse((Get-Content $pidFile -Raw).Trim(), [ref]$trackedPid)) {
    Remove-Item -LiteralPath $pidFile -Force
    return $null
  }

  $process = Get-Process -Id $trackedPid -ErrorAction SilentlyContinue
  if ($process -and $process.ProcessName -match '^php') { return $process }

  Remove-Item -LiteralPath $pidFile -Force
  return $null
}

function Start-Php-Service([string]$Name, [string[]]$Arguments) {
  $existing = Get-TrackedPhpProcess $Name
  if ($existing) {
    Write-Host "==> $Name already running (PID $($existing.Id))" -ForegroundColor DarkYellow
    return
  }

  $stdout = Join-Path $RuntimeLogDirectory "$Name.stdout.log"
  $stderr = Join-Path $RuntimeLogDirectory "$Name.stderr.log"
  $process = Start-Process -FilePath $phpExecutable -ArgumentList $Arguments `
    -WorkingDirectory $Backend -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr

  Start-Sleep -Milliseconds 300
  if ($process.HasExited) {
    throw "$Name stopped during startup. Review $stderr"
  }

  Set-Content -LiteralPath (Join-Path $RuntimePidDirectory "$Name.pid") `
    -Value $process.Id -Encoding ascii
  $script:StartedRuntimeProcesses += $process
  Write-Host "==> $Name started (PID $($process.Id))" -ForegroundColor Cyan
}

Write-Host "==> Starting Laravel API on $ApiUrl" -ForegroundColor Cyan
Start-Php-Service "api" @("artisan", "serve", "--host=127.0.0.1", "--port=$ApiPort")

$wsUrl = ""
$wsKey = ""

if ($NoRealtime) {
  Write-Host "==> Realtime skipped (-NoRealtime): the app will poll every 30s." -ForegroundColor Yellow
} else {
  # The client needs the same app key Reverb was started with, so read it
  # from the one place that already holds it.
  $wsKey = ([regex]::Match($envText, '(?m)^REVERB_APP_KEY=(.*)$')).Groups[1].Value.Trim().Trim('"')

  if (-not $wsKey) {
    Write-Host "REVERB_APP_KEY is not set in backend\.env; starting without realtime." -ForegroundColor Yellow
    Write-Host "Run 'php artisan reverb:install' to generate one, then re-run." -ForegroundColor Yellow
  } else {
    Write-Host "==> Starting Reverb on ws://127.0.0.1:$ReverbPort" -ForegroundColor Cyan
    Start-Php-Service "reverb" @("artisan", "reverb:start", "--host=127.0.0.1", "--port=$ReverbPort")

    # Broadcasts are queued, so without a worker they sit in `jobs` and no
    # client ever hears them. This is the piece that is easiest to forget.
    Write-Host "==> Starting queue worker (drains broadcasts)" -ForegroundColor Cyan
    Start-Php-Service "queue" @("artisan", "queue:work", "--tries=3", "--sleep=1", "--timeout=120")

    Write-Host "==> Starting scheduler (hourly vitals SLA escalation)" -ForegroundColor Cyan
    Start-Php-Service "scheduler" @("artisan", "schedule:work")

    $wsUrl = "ws://127.0.0.1:$ReverbPort"
  }
}

Write-Host ""
Write-Host "  API      $ApiUrl/api/v1"
if ($wsUrl) {
  Write-Host "  Realtime $wsUrl"
} else {
  Write-Host "  Realtime off; 30s polling"
}
Write-Host "  Admin    admin@mcare.health      / demo-password"
Write-Host "  Doctor   dr.mensah@mcare.health  / demo-password"
Write-Host "  Patient  amara.okonkwo@example.com / demo-password"
Write-Host ""

if ($SkipFrontend) {
  Write-Host "Frontend skipped (-SkipFrontend)." -ForegroundColor Green
  exit 0
}

# -------------------------------------------------------- serve frontend
Require-Command flutter.bat "Install Flutter and re-open the terminal."
$FlutterExecutable = (Get-Command flutter.bat -All | Select-Object -First 1).Source
Push-Location $Frontend
try {
  if (-not $SkipDeps) {
    Write-Host "==> flutter clean && flutter pub get" -ForegroundColor Cyan
    & flutter clean
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
  }

  Write-Host "==> Running Flutter on '$FlutterDevice'" -ForegroundColor Cyan
  # AppEnv.realtimeEnabled needs BOTH defines; with either missing the client
  # silently falls back to polling, so they are passed as a pair or not at all.
  $defines = @(
    "--dart-define=MCARE_USE_BACKEND=true",
    "--dart-define=MCARE_API_URL=$ApiUrl/api/v1"
  )
  if ($wsUrl -and $wsKey) {
    $defines += "--dart-define=MCARE_WS_URL=$wsUrl"
    $defines += "--dart-define=MCARE_WS_APP_KEY=$wsKey"
  }

  Invoke-Flutter $defines
} finally {
  Pop-Location
}
