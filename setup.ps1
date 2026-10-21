# Phase 1: install dependencies only. No broker credentials or network connection.
$ErrorActionPreference = 'Stop'
if ($args.Count -gt 0) { throw 'setup.ps1 only installs dependencies. Use .\test.ps1, .\configure.ps1, .\check.ps1, or .\run.ps1.' }
$Root = $PSScriptRoot
$Python = Join-Path $Root '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $Launcher = 'py'
        $Prefix = @('-3')
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        $Launcher = 'python'
        $Prefix = @()
    } else {
        throw 'Python 3.9+ is required. Install Python, then rerun .\setup.ps1.'
    }

    & $Launcher @Prefix -c 'import sys; sys.exit(sys.version_info < (3, 9))'
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.9+ is required.' }

    & $Launcher @Prefix -m venv (Join-Path $Root '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'Could not create Python virtual environment.' }
}

& $Python -m pip install -r (Join-Path $Root 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }

Write-Host ''
Write-Host 'Installed. No broker settings needed for the local test.'
Write-Host '  .\test.ps1           # Offline CPU test (do this first)'
Write-Host '  .\configure.ps1      # Enter REAL hosted broker details'
Write-Host '  .\check.ps1          # Check broker DNS, TLS, credentials and subscription'
Write-Host '  .\run.ps1            # Start monitoring'
