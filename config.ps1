# Shared Windows configuration loader. Not an entry point.
function Import-RAConfig {
    $path = Join-Path $PSScriptRoot '.env.windows.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Broker not configured. Run .\configure.ps1 first. Local tests use .\test.ps1.'
    }
    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    foreach ($key in @('RA_MQTT_HOST', 'RA_MQTT_PORT', 'RA_MQTT_USERNAME', 'RA_DEVICE_ID')) {
        $value = [string]$data.$key
        if ([string]::IsNullOrWhiteSpace($value)) { throw "Missing $key in config. Run .\configure.ps1." }
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
    if ([string]::IsNullOrWhiteSpace([string]$data.RA_MQTT_PASSWORD_DPAPI)) {
        throw 'No saved password. Run .\configure.ps1.'
    }
    try {
        $secure = ConvertTo-SecureString ([string]$data.RA_MQTT_PASSWORD_DPAPI)
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    } catch {
        throw 'Cannot decrypt the saved broker password with this Windows account. Run .\configure.ps1.'
    }
    [Environment]::SetEnvironmentVariable('RA_MQTT_PASSWORD', $plain, 'Process')
}
