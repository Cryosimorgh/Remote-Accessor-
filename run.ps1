# Start agent only. Does not install packages or ask for credentials.
$ErrorActionPreference = 'Stop'
$Python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw 'Run .\setup.ps1 first.' }
. (Join-Path $PSScriptRoot 'config.ps1')
Import-RAConfig
Write-Host 'Starting monitoring. Press Ctrl+C to stop. For one-shot diagnostics use .\check.ps1.'
& $Python (Join-Path $PSScriptRoot 'agent.py')
if ($LASTEXITCODE -ne 0) { throw "Agent exited with code $LASTEXITCODE." }
