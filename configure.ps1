# Explicit broker configuration. Does not install or connect to anything.
$ErrorActionPreference = 'Stop'
$ConfigFile = Join-Path $PSScriptRoot '.env.windows.json'

Write-Host ''
Write-Host 'A broker is a real hosted MQTT service you already have or create separately.'
Write-Host 'Find its MQTT TLS hostname, TLS port and username/password in the provider dashboard.'
Write-Host 'Example HOST FORMAT: xxxxx.s1.eu.hivemq.cloud (illustration, not a working hostname).'
Write-Host 'Never enter arbitrary numbers or placeholders. No broker? Run .\test.ps1 offline instead.'
Write-Host ''

function Read-Required([string]$Name, [string]$Prompt, [string]$Default = '') {
    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) {
        $suffix = if ($Default) { " [$Default]" } else { '' }
        $value = Read-Host "$Prompt$suffix"
    }
    if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$Name is required; configuration not saved." }
    return $value.Trim()
}

$brokerHost = Read-Required 'RA_MQTT_HOST' 'REAL broker hostname (no mqtts://, e.g. xyz.s1.eu.hivemq.cloud)'
$port = Read-Required 'RA_MQTT_PORT' 'Broker TLS port (from provider dashboard)' '8883'
$userName = Read-Required 'RA_MQTT_USERNAME' 'Username configured on broker'
$deviceId = Read-Required 'RA_DEVICE_ID' 'Device ID (e.g. my-pc)' 'pc-01'

if ($brokerHost -match '^\d+$' -or $brokerHost -match '(^|\.)example\.(com|net|org)$' -or
    $brokerHost -match '^your-' -or $brokerHost -match '://|/|\s' -or
    [Uri]::CheckHostName($brokerHost) -eq [UriHostNameType]::Unknown) {
    throw "'$brokerHost' is not an actual broker address. Copy the hostname from your broker provider dashboard; configuration not saved."
}
$parsedPort = 0
if (-not [int]::TryParse($port, [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
    throw "TLS port '$port' must be a number from 1 to 65535; configuration not saved."
}
if ($deviceId -cnotmatch '^[A-Za-z0-9_-]{1,64}$') {
    throw 'Device ID must be 1-64 letters/numbers/-/_; configuration not saved.'
}

$passwordText = [Environment]::GetEnvironmentVariable('RA_MQTT_PASSWORD', 'Process')
if (-not [string]::IsNullOrEmpty($passwordText)) {
    $secret = ConvertTo-SecureString $passwordText -AsPlainText -Force
} else {
    $secret = Read-Host 'Password configured on broker (hidden)' -AsSecureString
}
if ($secret.Length -lt 1) { throw 'Broker password required; configuration not saved.' }
$encrypted = ConvertFrom-SecureString $secret  # Windows DPAPI, current user account.

$data = [ordered]@{
    RA_MQTT_HOST = $brokerHost
    RA_MQTT_PORT = "$parsedPort"
    RA_MQTT_USERNAME = $userName
    RA_MQTT_PASSWORD_DPAPI = $encrypted
    RA_DEVICE_ID = $deviceId
}
$data | ConvertTo-Json | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
Write-Host ''
Write-Host "Configuration saved to $ConfigFile"
Write-Host 'Password encrypted for this Windows account (DPAPI); the file is ignored by Git.'
Write-Host 'Next: .\check.ps1  (single connection attempt with diagnostics)'
