# Shared dart-define assembly for every Flutter entry point.
#
# The Flutter build only knows what it is told on the command line. Google and
# Apple sign-in, Reverb, Maps and Firebase all read compile-time values via
# String.fromEnvironment, so a build launched without them ships an app that
# reports those features as "not configured for this application build" - which
# is exactly what happens when a run script passes only the API URL.
#
# frontend/config/app_config.local.json is the single place those values live.
# It is gitignored, so this is deliberately tolerant: a missing file is a
# warning and a normal build, never a hard stop.

function Get-McareConfigDefines {
  param(
    [Parameter(Mandatory = $true)][string] $ConfigPath,
    [switch] $Quiet
  )

  if (-not (Test-Path $ConfigPath)) {
    if (-not $Quiet) {
      Write-Host "    No $(Split-Path $ConfigPath -Leaf) - social sign-in, realtime and push will report themselves unconfigured." -ForegroundColor Yellow
      Write-Host "    Copy frontend/config/app_config.example.json to app_config.local.json and fill it in." -ForegroundColor Yellow
    }
    return @()
  }

  try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
  } catch {
    Write-Host "    $ConfigPath is not valid JSON - ignoring it. ($($_.Exception.Message))" -ForegroundColor Yellow
    return @()
  }

  $defines = @()
  $skipped = @()
  foreach ($property in $config.PSObject.Properties) {
    $value = "$($property.Value)".Trim()

    # Unfilled template values are worse than absent ones: they look
    # configured on the command line and are then rejected at runtime by
    # AppEnv.isConfiguredValue, so drop them here and say which.
    if ($value -eq '' -or $value -like 'REPLACE_*' -or $value -like 'YOUR_*') {
      $skipped += $property.Name
      continue
    }

    $defines += "--dart-define=$($property.Name)=$value"
  }

  if (-not $Quiet) {
    Write-Host "    Loaded $($defines.Count) defines from $(Split-Path $ConfigPath -Leaf)." -ForegroundColor DarkGray
    if ($skipped.Count -gt 0) {
      Write-Host "    Still unfilled: $($skipped -join ', ')" -ForegroundColor DarkGray
    }
  }

  return $defines
}

# Explicit defines win over the config file, matching Flutter's own precedence
# for --dart-define over --dart-define-from-file: the compiler takes the last
# definition of a duplicated key. That is what lets one config file describe
# the project while a single run still points at localhost.
function Merge-McareDefines {
  param(
    [string[]] $FromConfig = @(),
    [string[]] $Explicit = @()
  )

  return @($FromConfig) + @($Explicit)
}
