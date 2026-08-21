[CmdletBinding()]
param(
    [string]$Subject = 'CN=Tablet Display Test Certificate',
    [string]$WdkRoot = 'D:\DevTools\WindowsKits'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$certificateDirectory = Join-Path $repoRoot 'windows\driver\certificates'
$publicCertificatePath = Join-Path $certificateDirectory 'TabletDisplayTestCertificate.cer'

$certificate = Get-ChildItem -Path 'Cert:\CurrentUser\My' |
    Where-Object { $_.Subject -eq $Subject -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date).AddDays(30) } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if ($null -eq $certificate) {
    $certificate = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject $Subject `
        -FriendlyName 'Tablet Display Development Test Signing' `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -HashAlgorithm SHA256 `
        -KeyExportPolicy NonExportable `
        -NotAfter (Get-Date).AddYears(3)
}

New-Item -ItemType Directory -Path $certificateDirectory -Force | Out-Null
Export-Certificate -Cert $certificate -FilePath $publicCertificatePath -Force | Out-Null

Write-Host 'Development test certificate is ready.'
[pscustomobject]@{
    Subject = $certificate.Subject
    Thumbprint = $certificate.Thumbprint
    Expires = $certificate.NotAfter
    PublicCertificate = $publicCertificatePath
}
