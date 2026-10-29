[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Driver installation must run as administrator.'
}

$driverRoot = Join-Path $PSScriptRoot 'driver'
$certificatePath = Join-Path $driverRoot 'TabletDisplayTestCertificate.cer'
$catalogPath = Join-Path $driverRoot 'TabletDisplayDriver.cat'
$infPath = Join-Path $driverRoot 'TabletDisplayDriver.inf'
$dllPath = Join-Path $driverRoot 'TabletDisplayDriver.dll'
foreach ($path in @($certificatePath, $catalogPath, $infPath, $dllPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required driver file was not found: $path"
    }
}

$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
    (Resolve-Path -LiteralPath $certificatePath)
)
$catalogSignature = Get-AuthenticodeSignature -LiteralPath $catalogPath
if ($null -eq $catalogSignature.SignerCertificate -or
    $catalogSignature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
    throw 'The driver catalog signer does not match the bundled certificate.'
}

Write-Warning 'This preview driver uses a project self-signed certificate, not Microsoft production signing.'
Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null

$trustedSignature = Get-AuthenticodeSignature -LiteralPath $catalogPath
if ($trustedSignature.Status -ne [Management.Automation.SignatureStatus]::Valid) {
    throw "Driver catalog validation failed after trust import: $($trustedSignature.StatusMessage)"
}

& pnputil.exe '/add-driver' $infPath '/install'
if ($LASTEXITCODE -ne 0) {
    throw "PnPUtil failed with exit code $LASTEXITCODE"
}

Write-Host 'USB Tablet Display driver package installed successfully.'
