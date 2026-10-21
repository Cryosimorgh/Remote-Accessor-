# Remote Accessor: configure a REAL hosted MQTT broker; validate before saving.
$ErrorActionPreference = 'Stop'
$Python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
$ConfigFile = Join-Path $PSScriptRoot '.env.windows.json'

Write-Host ''
Write-Host 'REMOTE ACCESSOR - HOSTED MQTT SETUP'
Write-Host 'The broker is a third-party service, NOT your own PC.'
Write-Host 'No broker account? Set one up first:'
Write-Host '  https://www.emqx.com/en/cloud/serverless-mqtt'
Write-Host '  1. Sign in, create project, New Deployment -> Serverless.'
Write-Host '  2. Set monthly Spend Limit to 0 (free quota only). Deploy.'
Write-Host '  3. Deployment Overview -> copy Address; TLS port is usually 8883.'
Write-Host '  4. Access Control -> Authentication -> Add username/password.'
Write-Host '  5. Then run this script again.'
Write-Host '  Provider instructions: https://docs.emqx.com/en/cloud/latest/create/serverless.html'
Write-Host 'You can already test CPU locally with .\test.ps1 (NO BROKER NEEDED).'
Write-Host ''

$ready = Read-Host 'Do you already have a RUNNING broker endpoint and its MQTT username/password? [y/N]'
if ($ready -notin @('y','Y','yes','YES','Yes')) {
    Write-Host 'No configuration saved. Create the hosted broker first, or use .\test.ps1.'
    return
}
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
    throw 'First run .\setup.ps1 to install Python dependencies; then return to .\configure.ps1.'
}

function Read-Required([string]$Name, [string]$Prompt, [string]$Default = '') {
    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) {
        $suffix = if ($Default) { " [$Default]" } else { '' }
        $value = Read-Host "$Prompt$suffix"
    }
    if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$Name is required; configuration NOT saved." }
    return $value.Trim()
}

$brokerHost = Read-Required 'RA_MQTT_HOST' 'Copy the broker Address from its Overview (without scheme)'
$port = Read-Required 'RA_MQTT_PORT' 'Copy the MQTT TLS port from its Overview' '8883'
$userName = Read-Required 'RA_MQTT_USERNAME' 'MQTT username you created under Authentication'
$deviceId = Read-Required 'RA_DEVICE_ID' 'Your PC device ID (e.g. my-pc)' 'my-pc'

# Reject obvious placeholders and malformed hostnames before any network activity.
if ($brokerHost -match '^\d+$' -or $brokerHost -match '(^|\.)example\.(com|net|org)$' -or
    $brokerHost -match '^your-' -or $brokerHost -match '://|/|\s' -or
    [Uri]::CheckHostName($brokerHost) -eq [UriHostNameType]::Unknown) {
    throw "'$brokerHost' is not a valid broker address. Copy the real Address from your provider dashboard. Nothing saved."
}
$parsedPort = 0
if (-not [int]::TryParse($port, [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
    throw "Port '$port' must be 1-65535. Check provider TLS port; nothing saved."
}
if ($deviceId -cnotmatch '^[A-Za-z0-9_-]{1,64}$') {
    throw 'Device ID must use 1-64 letters/digits/-/_. Nothing saved.'
}

$password = [Environment]::GetEnvironmentVariable('RA_MQTT_PASSWORD', 'Process')
if ([string]::IsNullOrEmpty($password)) {
    $secret = Read-Host 'MQTT password you created under Authentication (hidden)' -AsSecureString
    if ($secret.Length -eq 0) { throw 'MQTT password required. Nothing saved.' }
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
$keys = @('RA_MQTT_HOST','RA_MQTT_PORT','RA_MQTT_USERNAME','RA_MQTT_PASSWORD','RA_DEVICE_ID')
$oldEnv = @{}
foreach ($key in $keys) { $oldEnv[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }

try {
    [Environment]::SetEnvironmentVariable('RA_MQTT_HOST', $brokerHost, 'Process')
    [Environment]::SetEnvironmentVariable('RA_MQTT_PORT', "$parsedPort", 'Process')
    [Environment]::SetEnvironmentVariable('RA_MQTT_USERNAME', $userName, 'Process')
    [Environment]::SetEnvironmentVariable('RA_MQTT_PASSWORD', $password, 'Process')
    [Environment]::SetEnvironmentVariable('RA_DEVICE_ID', $deviceId, 'Process')
    Write-Host ''
    Write-Host 'VALIDATING: DNS -> TCP/TLS -> MQTT login -> subscribe. No settings saved yet.'
    & $Python (Join-Path $PSScriptRoot 'broker_check.py')
    if ($LASTEXITCODE -ne 0) {
        throw 'Live broker check FAILED. Configuration NOT saved. Fix the broker or entered settings; run .\configure.ps1 again.'
    }
} finally {
    foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key, $oldEnv[$key], 'Process') }
}

# Save only after a real authenticated TLS connection and topic subscription succeeded.
$secret = ConvertTo-SecureString $password -AsPlainText -Force
$config = [ordered]@{
    RA_MQTT_HOST = $brokerHost
    RA_MQTT_PORT = "$parsedPort"
    RA_MQTT_USERNAME = $userName
    RA_MQTT_PASSWORD_DPAPI = (ConvertFrom-SecureString $secret)
    RA_DEVICE_ID = $deviceId
}
$config | ConvertTo-Json | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
Write-Host ''
Write-Host "VERIFIED and saved to $ConfigFile (password encrypted with Windows DPAPI)."
Write-Host 'Next: .\run.ps1   # starts agent; phone test still required for full end-to-end verification'
