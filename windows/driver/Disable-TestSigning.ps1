[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell window (Run as administrator).'
}

& bcdedit.exe '/set' 'testsigning' 'off'
if ($LASTEXITCODE -ne 0) {
    throw "BCDEdit failed with exit code $LASTEXITCODE"
}

Write-Host 'Windows test-signing mode was disabled. Restart Windows to return to normal driver enforcement.'
