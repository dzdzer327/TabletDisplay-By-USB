[CmdletBinding()]
param(
    [switch]$RemoveSigningCertificate
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell window (Run as administrator).'
}

if (Get-Process -Name 'TabletDisplayController' -ErrorAction SilentlyContinue) {
    throw 'Exit TabletDisplayController by pressing X before uninstalling the driver.'
}

$installedDrivers = Get-WindowsDriver -Online -All |
    Where-Object { $_.ProviderName -eq 'Tablet Display Project' }

foreach ($driver in $installedDrivers) {
    & pnputil.exe '/delete-driver' $driver.Driver '/uninstall' '/force'
    if ($LASTEXITCODE -ne 0) {
        throw "Could not remove driver package $($driver.Driver). PnPUtil exit code: $LASTEXITCODE"
    }
}

$trustedCertificates = @(
    Get-ChildItem -Path 'Cert:\LocalMachine\Root' -ErrorAction SilentlyContinue
    Get-ChildItem -Path 'Cert:\LocalMachine\TrustedPublisher' -ErrorAction SilentlyContinue
) | Where-Object { $_.Subject -eq 'CN=Tablet Display Test Certificate' }

foreach ($certificate in $trustedCertificates) {
    Remove-Item -LiteralPath $certificate.PSPath
}

if ($RemoveSigningCertificate) {
    Get-ChildItem -Path 'Cert:\CurrentUser\My' |
        Where-Object { $_.Subject -eq 'CN=Tablet Display Test Certificate' } |
        ForEach-Object { Remove-Item -LiteralPath $_.PSPath }
}

Write-Host 'USB Tablet Display test driver and its system trust entries were removed.'
Write-Host 'Use Disable-TestSigning.ps1 and restart Windows when no other test drivers need test mode.'
