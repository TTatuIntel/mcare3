# Stop only the local mCare PHP services tracked by fresh-start.ps1.
# Runtime PID files are kept below backend/storage/framework/mcare-runtime.

param()

$ErrorActionPreference = "Stop"

$LocalRoot = Split-Path -Parent $PSScriptRoot
$Backend = Join-Path $LocalRoot "backend"
$RuntimePidDirectory = Join-Path $Backend "storage\framework\mcare-runtime"

if (-not (Test-Path $RuntimePidDirectory)) {
  Write-Host "No tracked mCare runtime services were found." -ForegroundColor Yellow
  exit 0
}

$stopped = 0
foreach ($name in @("scheduler", "queue", "reverb", "api")) {
  $pidFile = Join-Path $RuntimePidDirectory "$name.pid"
  if (-not (Test-Path $pidFile)) { continue }

  $trackedPid = 0
  $validPid = [int]::TryParse(
    (Get-Content $pidFile -Raw).Trim(),
    [ref]$trackedPid
  )
  $process = if ($validPid) {
    Get-Process -Id $trackedPid -ErrorAction SilentlyContinue
  } else {
    $null
  }

  # PID reuse is possible. Never stop an unrelated process if a stale PID file
  # happens to point at a non-PHP executable.
  if ($process -and $process.ProcessName -match '^php') {
    Stop-Process -Id $trackedPid
    Wait-Process -Id $trackedPid -Timeout 5 -ErrorAction SilentlyContinue
    Write-Host "Stopped $name (PID $trackedPid)." -ForegroundColor Green
    $stopped++
  }

  Remove-Item -LiteralPath $pidFile -Force
}

if ($stopped -eq 0) {
  Write-Host "No tracked mCare runtime services were running." -ForegroundColor Yellow
}
