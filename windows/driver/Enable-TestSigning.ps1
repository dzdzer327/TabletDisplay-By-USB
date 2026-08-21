[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell window (Run as administrator).'
}

try {
    if (Confirm-SecureBootUEFI) {
        throw 'Secure Boot is enabled. Windows will not enable test-signing mode until Secure Boot is disabled in UEFI.'
    }
}
catch [System.PlatformNotSupportedException] {
    # Legacy BIOS systems do not expose Secure Boot and can continue.
}

& bcdedit.exe '/set' 'testsigning' 'on'
if ($LASTEXITCODE -ne 0) {
    throw "BCDEdit failed with exit code $LASTEXITCODE"
}

Write-Host 'Windows test-signing mode was enabled. Restart Windows before installing the development driver.'
