# Start mCare locally without resetting or reseeding the database.
# Use fresh-start.ps1 only when a destructive database rebuild is intended.

param(
  [int]$ApiPort = 8000,
  [int]$WebPort = 8090,
  [int]$ReverbPort = 8080,
  [string]$FlutterDevice = "chrome",
  [switch]$SkipFrontend,
  [switch]$NoRealtime,
  [switch]$MockMode,
  [switch]$InstallDeps
)

$arguments = @{
  ApiPort = $ApiPort
  WebPort = $WebPort
  ReverbPort = $ReverbPort
  FlutterDevice = $FlutterDevice
  SkipReset = $true
  Force = $true
  SkipFrontend = $SkipFrontend
  NoRealtime = $NoRealtime
  MockMode = $MockMode
}

if (-not $InstallDeps) {
  $arguments.SkipDeps = $true
}

& (Join-Path $PSScriptRoot "fresh-start.ps1") @arguments
exit $LASTEXITCODE
