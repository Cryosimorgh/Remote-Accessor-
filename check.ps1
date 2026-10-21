# One-shot broker diagnostics. Does not start the monitoring agent.
$ErrorActionPreference = 'Stop'
$Python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw 'Run .\setup.ps1 first.' }
. (Join-Path $PSScriptRoot 'config.ps1')
Import-RAConfig
& $Python (Join-Path $PSScriptRoot 'broker_check.py')
if ($LASTEXITCODE -ne 0) { throw 'Broker check failed. Correct the reported issue, then run .\check.ps1 again.' }
