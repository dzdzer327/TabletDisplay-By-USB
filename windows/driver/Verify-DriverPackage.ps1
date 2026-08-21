[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$WdkRoot = 'D:\DevTools\WindowsKits'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$driverRoot = Join-Path $repoRoot 'windows\driver'
$packageRoot = Join-Path $driverRoot "package\$Configuration-x64"
$certificatePath = Join-Path $driverRoot 'certificates\TabletDisplayTestCertificate.cer'
$catalogPath = Join-Path $packageRoot 'TabletDisplayDriver.cat'
$infPath = Join-Path $packageRoot 'TabletDisplayDriver.inf'
$dllPath = Join-Path $packageRoot 'TabletDisplayDriver.dll'
$signTool = Join-Path $WdkRoot 'bin\10.0.26100.0\x64\signtool.exe'

foreach ($requiredPath in @($certificatePath, $catalogPath, $infPath, $dllPath, $signTool)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required verification file was not found: $requiredPath"
    }
}

$certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    (Resolve-Path -LiteralPath $certificatePath)
)
$rootTrusted = Test-Path -LiteralPath "Cert:\LocalMachine\Root\$($certificate.Thumbprint)"
$publisherTrusted = Test-Path -LiteralPath "Cert:\LocalMachine\TrustedPublisher\$($certificate.Thumbprint)"
if (-not $rootTrusted -or -not $publisherTrusted) {
    throw 'The development certificate is not trusted in both LocalMachine stores.'
}

$catalogSignature = Get-AuthenticodeSignature -LiteralPath $catalogPath
if ($catalogSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw "Catalog Authenticode validation failed: $($catalogSignature.StatusMessage)"
}

& $signTool verify '/pa' '/v' '/sha1' $certificate.Thumbprint $catalogPath
if ($LASTEXITCODE -ne 0) {
    throw "Catalog signature verification failed with exit code $LASTEXITCODE"
}

foreach ($packageMember in @($infPath, $dllPath)) {
    & $signTool verify '/pa' '/v' '/sha1' $certificate.Thumbprint '/c' $catalogPath $packageMember
    if ($LASTEXITCODE -ne 0) {
        throw "Catalog member verification failed for $packageMember with exit code $LASTEXITCODE"
    }
}

Write-Host 'Tablet Display driver package security and integrity verification passed.'
[pscustomobject]@{
    CatalogSigner = $catalogSignature.SignerCertificate.Subject
    CertificateThumbprint = $certificate.Thumbprint
    CatalogSignature = $catalogSignature.Status
    InfCatalogMembership = 'Valid'
    DllCatalogMembership = 'Valid'
    DriverInstalled = $false
    BootConfigurationChanged = $false
}
