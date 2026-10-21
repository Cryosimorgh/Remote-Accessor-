# Offline unit test + real local CPU sample. Never reads broker config or makes a broker connection.
$ErrorActionPreference = 'Stop'
$Python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw 'Run .\setup.ps1 first.' }

Push-Location $PSScriptRoot
try {
    & $Python -m unittest -v test_agent
    if ($LASTEXITCODE -ne 0) { throw 'Local unit tests failed.' }
    Write-Host ''
    Write-Host 'Actual CPU measurement from this PC:'
    & $Python -c 'import agent; print(agent.cpu_response("local-test"))'
    if ($LASTEXITCODE -ne 0) { throw 'CPU measurement failed.' }
    Write-Host 'Local test passed. No broker was contacted.'
} finally {
    Pop-Location
}
