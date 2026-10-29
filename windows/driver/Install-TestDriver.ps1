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

$bootConfiguration = bcdedit /enum '{current}' 2>&1
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the current boot configuration.'
}

$testSigningEnabled = $bootConfiguration | Select-String -Pattern '^testsigning\s+(Yes|On|是|开)$'
if ($null -eq $testSigningEnabled) {
    throw 'Windows test-signing mode is not enabled. Do not install the development driver yet.'
}

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$driverRoot = Join-Path $repoRoot 'windows\driver'
$packageRoot = Join-Path $driverRoot "package\$Configuration-x64"
$infPath = Join-Path $packageRoot 'TabletDisplayDriver.inf'
$catalogPath = Join-Path $packageRoot 'TabletDisplayDriver.cat'
$certificatePath = Join-Path $driverRoot 'certificates\TabletDisplayTestCertificate.cer'

foreach ($requiredPath in @($infPath, $catalogPath, $certificatePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required installation file was not found: $requiredPath"
    }
}

$signature = Get-AuthenticodeSignature -LiteralPath $catalogPath
if ($null -eq $signature.SignerCertificate) {
    throw 'TabletDisplayDriver.cat is not signed.'
}

Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null

& pnputil.exe '/add-driver' $infPath '/install'
if ($LASTEXITCODE -ne 0) {
    throw "PnPUtil failed with exit code $LASTEXITCODE"
}

Write-Host 'USB Tablet Display test driver is trusted and staged in the Windows driver store.'
Write-Host 'Start TabletDisplayController.exe to create the virtual display device.'
