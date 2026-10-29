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

if (Get-Process -Name 'TabletDisplayController' -ErrorAction SilentlyContinue) {
    throw 'Exit TabletDisplayController before updating the driver package.'
}

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$installScript = Join-Path $repoRoot 'windows\driver\Install-LocalTrustedDriver.ps1'
if (-not (Test-Path -LiteralPath $installScript)) {
    throw "Local installation script was not found: $installScript"
}

$existingPackages = Get-WindowsDriver -Online -All |
    Where-Object { $_.ProviderName -eq 'Tablet Display Project' }

foreach ($package in $existingPackages) {
    Write-Host "Removing previous USB Tablet Display package: $($package.Driver)"
    & pnputil.exe '/delete-driver' $package.Driver '/uninstall' '/force'
    if ($LASTEXITCODE -ne 0) {
        throw "Could not remove $($package.Driver). PnPUtil exit code: $LASTEXITCODE"
    }
}

& $installScript -Configuration $Configuration
if ($LASTEXITCODE -ne 0) {
    throw "Local driver installation failed with exit code $LASTEXITCODE"
}
