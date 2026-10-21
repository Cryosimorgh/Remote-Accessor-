# Start agent only. Does not install packages or ask for credentials.
$ErrorActionPreference = 'Stop'
$Python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw 'Run .\setup.ps1 first.' }
. (Join-Path $PSScriptRoot 'config.ps1')
Import-RAConfig
try {
    Write-Host 'Checking broker once before starting (no endless retry on invalid settings)...'
    & $Python (Join-Path $PSScriptRoot 'broker_check.py')
    if ($LASTEXITCODE -ne 0) { throw 'Cannot start: broker check failed. Fix settings with .\configure.ps1.' }
    Write-Host 'Starting monitoring. Press Ctrl+C to stop.'
    & $Python (Join-Path $PSScriptRoot 'agent.py')
    if ($LASTEXITCODE -ne 0) { throw "Agent exited with code $LASTEXITCODE." }
} finally {
    [Environment]::SetEnvironmentVariable('RA_MQTT_PASSWORD', $null, 'Process')
}
