# Native Windows PowerShell helper for Remote Accessor Phase 1.
# Run: .\setup.ps1 [setup|run|test]
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('setup', 'run', 'test')]
    [string]$Action = 'setup'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $Root '.venv\Scripts\python.exe'
$ConfigFile = Join-Path $Root '.env.windows.json'

function Assert-Success([string]$Operation) {
    if ($LASTEXITCODE -ne 0) { throw "$Operation failed (exit code $LASTEXITCODE)." }
}

function Install-Agent {
    if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
        if (Get-Command py -ErrorAction SilentlyContinue) {
            $launcher = 'py'
            $prefix = @('-3')
        } elseif (Get-Command python -ErrorAction SilentlyContinue) {
            $launcher = 'python'
            $prefix = @()
        } else {
            throw 'Python 3.9+ is required. Install Python, then rerun this script.'
        }
        & $launcher @prefix -c 'import sys; sys.exit(sys.version_info < (3, 9))'
        Assert-Success 'Python version check (requires 3.9+)'
        & $launcher @prefix -m venv (Join-Path $Root '.venv')
        Assert-Success 'Creating virtual environment'
    }
    & $Python -m pip install -r (Join-Path $Root 'requirements.txt')
    Assert-Success 'Installing dependencies'
}

function Read-Setting([string]$Name, [string]$Label, [string]$Default = '', [switch]$Secret) {
    $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrEmpty($value)) {
        if ($Secret) {
            $secure = Read-Host -Prompt $Label -AsSecureString
            $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        } else {
            $suffix = if ($Default) { " [$Default]" } else { '' }
            $value = Read-Host -Prompt "$Label$suffix"
        }
    }
    if ([string]::IsNullOrEmpty($value)) { $value = $Default }
    if ([string]::IsNullOrEmpty($value)) { throw "$Name cannot be empty." }
    return $value
}

function Configure-Agent {
    if (Test-Path -LiteralPath $ConfigFile) {
        Write-Host "Keeping existing configuration at $ConfigFile"
        return
    }
    $hostName = Read-Setting 'RA_MQTT_HOST' 'MQTT broker TLS hostname (without mqtts://)'
    $port = Read-Setting 'RA_MQTT_PORT' 'MQTT broker TLS port' '8883'
    $user = Read-Setting 'RA_MQTT_USERNAME' 'Agent MQTT username'
    $password = Read-Setting 'RA_MQTT_PASSWORD' 'Agent MQTT password (input hidden)' -Secret
    $device = Read-Setting 'RA_DEVICE_ID' 'Device ID (letters, numbers, - or _)'

    $parsedPort = 0
    if (-not [int]::TryParse($port, [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
        throw 'RA_MQTT_PORT must be between 1 and 65535.'
    }
    if ($device -cnotmatch '^[A-Za-z0-9_-]{1,64}$') {
        throw 'RA_DEVICE_ID must contain 1-64 letters, numbers, hyphens or underscores.'
    }

    # Windows DPAPI encrypts the saved password for the current OS user.
    $protectedPassword = ConvertFrom-SecureString (ConvertTo-SecureString $password -AsPlainText -Force)
    $config = [ordered]@{
        RA_MQTT_HOST = $hostName
        RA_MQTT_PORT = "$parsedPort"
        RA_MQTT_USERNAME = $user
        RA_MQTT_PASSWORD_DPAPI = $protectedPassword
        RA_DEVICE_ID = $device
    }
    $config | ConvertTo-Json | Set-Content -LiteralPath $ConfigFile -Encoding UTF8
    Write-Host "Saved settings to $ConfigFile (password encrypted for your Windows account)."
}

function Start-Agent {
    if (-not (Test-Path -LiteralPath $ConfigFile)) { Configure-Agent }
    $config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
    foreach ($key in @('RA_MQTT_HOST', 'RA_MQTT_PORT', 'RA_MQTT_USERNAME', 'RA_DEVICE_ID')) {
        $value = [string]$config.$key
        if ([string]::IsNullOrEmpty($value)) { throw "$key missing from $ConfigFile" }
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
    $secure = ConvertTo-SecureString ([string]$config.RA_MQTT_PASSWORD_DPAPI)
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    [Environment]::SetEnvironmentVariable('RA_MQTT_PASSWORD', $password, 'Process')

    & $Python (Join-Path $Root 'agent.py')
    Assert-Success 'Agent'
}

switch ($Action) {
    'setup' {
        Install-Agent
        Configure-Agent
        Write-Host 'Ready. Start the agent with: .\setup.ps1 run'
    }
    'run' {
        if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { Install-Agent }
        Start-Agent
    }
    'test' {
        if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { Install-Agent }
        & $Python -m unittest -v (Join-Path $Root 'test_agent.py')
        Assert-Success 'Local tests'
    }
}
