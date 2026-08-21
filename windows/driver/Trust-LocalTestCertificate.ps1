[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell window (Run as administrator).'
}

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$driverRoot = Join-Path $repoRoot 'windows\driver'
$certificatePath = Join-Path $driverRoot 'certificates\TabletDisplayTestCertificate.cer'
$catalogPath = Join-Path $driverRoot 'package\Debug-x64\TabletDisplayDriver.cat'

foreach ($requiredPath in @($certificatePath, $catalogPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required trust file was not found: $requiredPath"
    }
}

$certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    (Resolve-Path -LiteralPath $certificatePath)
)
$catalogSignature = Get-AuthenticodeSignature -LiteralPath $catalogPath

if ($certificate.Subject -ne 'CN=Tablet Display Test Certificate') {
    throw "Unexpected certificate subject: $($certificate.Subject)"
}

if ($null -eq $catalogSignature.SignerCertificate -or
    $catalogSignature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
    throw 'The public certificate does not match the certificate that signed the catalog.'
}

$codeSigningEku = '1.3.6.1.5.5.7.3.3'
$ekuExtension = $certificate.Extensions |
    Where-Object { $_.Oid.Value -eq '2.5.29.37' } |
    Select-Object -First 1
if ($null -eq $ekuExtension) {
    throw 'The certificate does not contain an Enhanced Key Usage extension.'
}

$parsedEkuExtension = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new(
    $ekuExtension,
    $ekuExtension.Critical
)
$hasCodeSigningEku = $parsedEkuExtension.EnhancedKeyUsages |
    Where-Object { $_.Value -eq $codeSigningEku }
if ($null -eq $hasCodeSigningEku) {
    throw 'The certificate does not contain the Code Signing enhanced key usage.'
}

Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null

$rootTrusted = Test-Path -LiteralPath "Cert:\LocalMachine\Root\$($certificate.Thumbprint)"
$publisherTrusted = Test-Path -LiteralPath "Cert:\LocalMachine\TrustedPublisher\$($certificate.Thumbprint)"
if (-not $rootTrusted -or -not $publisherTrusted) {
    throw 'The certificate was not found in both required local-machine trust stores after import.'
}

Write-Host 'Tablet Display development certificate is trusted by this computer.'
Write-Host "Certificate thumbprint: $($certificate.Thumbprint)"
Write-Host 'No driver was installed and no boot configuration was changed.'
