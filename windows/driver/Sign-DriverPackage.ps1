[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$WdkRoot = 'D:\DevTools\WindowsKits',
    [string]$CertificateSubject = 'CN=Tablet Display Test Certificate'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$driverRoot = Join-Path $repoRoot 'windows\driver'
$packageRoot = Join-Path $driverRoot "package\$Configuration-x64"
$catalogPath = Join-Path $packageRoot 'TabletDisplayDriver.cat'
$packageScript = Join-Path $driverRoot 'Build-DriverPackage.ps1'
$signTool = Join-Path $WdkRoot 'bin\10.0.26100.0\x64\signtool.exe'

foreach ($requiredPath in @($packageScript, $signTool)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required signing file was not found: $requiredPath"
    }
}

& $packageScript -Configuration $Configuration -WdkRoot $WdkRoot
if ($LASTEXITCODE -ne 0) {
    throw "Driver package build failed with exit code $LASTEXITCODE"
}

$certificate = Get-ChildItem -Path 'Cert:\CurrentUser\My' |
    Where-Object { $_.Subject -eq $CertificateSubject -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if ($null -eq $certificate) {
    throw "A current-user signing certificate was not found for: $CertificateSubject"
}

& $signTool sign '/v' '/fd' 'SHA256' '/s' 'My' '/sha1' $certificate.Thumbprint $catalogPath
if ($LASTEXITCODE -ne 0) {
    throw "SignTool failed with exit code $LASTEXITCODE"
}

$signature = Get-AuthenticodeSignature -LiteralPath $catalogPath
if ($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
    throw 'The catalog signature does not match the selected development certificate.'
}

Write-Host "Catalog signed with development certificate: $($certificate.Subject)"
[pscustomobject]@{
    Catalog = $catalogPath
    SignatureStatus = $signature.Status
    Signer = $signature.SignerCertificate.Subject
    Thumbprint = $signature.SignerCertificate.Thumbprint
}
