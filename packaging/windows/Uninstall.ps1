[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $PSCommandPath + '"')
    ) -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

Get-Process -Name 'TabletDisplayController' -ErrorAction SilentlyContinue | Stop-Process -Force
& pnputil.exe '/remove-device' 'SWD\TABLETDISPLAYDRIVER\TABLETDISPLAYDRIVER'

$packages = Get-WindowsDriver -Online -All |
    Where-Object { $_.ProviderName -eq 'Tablet Display Project' }
foreach ($package in $packages) {
    & pnputil.exe '/delete-driver' $package.Driver '/uninstall' '/force'
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not remove driver package $($package.Driver)."
    }
}

$certificatePath = Join-Path $PSScriptRoot 'driver\TabletDisplayTestCertificate.cer'
if (Test-Path -LiteralPath $certificatePath) {
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
        (Resolve-Path -LiteralPath $certificatePath)
    )
    foreach ($store in @('Root', 'TrustedPublisher')) {
        $path = "Cert:\LocalMachine\$store\$($certificate.Thumbprint)"
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

$shortcut = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'USB Tablet Display.lnk'
if (Test-Path -LiteralPath $shortcut) {
    Remove-Item -LiteralPath $shortcut -Force
}

Write-Host 'USB Tablet Display driver, test-certificate trust, and desktop shortcut were removed.'
Write-Host 'You can now delete this package folder and uninstall the Android app normally.'
