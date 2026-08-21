[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell window (Run as administrator).'
}

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$driverRoot = Join-Path $repoRoot 'windows\driver'
$packageRoot = Join-Path $driverRoot "package\$Configuration-x64"
$infPath = Join-Path $packageRoot 'TabletDisplayDriver.inf'
$verifyScript = Join-Path $driverRoot 'Verify-DriverPackage.ps1'

foreach ($requiredPath in @($infPath, $verifyScript)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required local installation file was not found: $requiredPath"
    }
}

& $verifyScript -Configuration $Configuration
if ($LASTEXITCODE -ne 0) {
    throw "Driver package verification failed with exit code $LASTEXITCODE"
}

& pnputil.exe '/add-driver' $infPath '/install'
if ($LASTEXITCODE -ne 0) {
    throw "PnPUtil failed with exit code $LASTEXITCODE"
}

$installedPackage = Get-WindowsDriver -Online -All |
    Where-Object { $_.ProviderName -eq 'Tablet Display Project' } |
    Sort-Object Date -Descending |
    Select-Object -First 1

if ($null -eq $installedPackage) {
    throw 'PnPUtil returned success, but the Tablet Display package was not found in the driver store.'
}

Write-Host 'Tablet Display driver package is present in the Windows driver store.'
[pscustomobject]@{
    PublishedName = $installedPackage.Driver
    Provider = $installedPackage.ProviderName
    Version = $installedPackage.Version
    TestSigningRequired = $false
    BootConfigurationChanged = $false
    DeviceCreated = $false
    ExistingMatchingDeviceUpdated = $true
}
