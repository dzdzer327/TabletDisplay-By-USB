[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'Build-TabletDisplayDesktop.ps1')
}

$desktop = Join-Path $PSScriptRoot 'TabletDisplayDesktop\bin\Debug\TabletDisplayDesktop.exe'
if (-not (Test-Path -LiteralPath $desktop)) {
    throw "USB Tablet Display Desktop was not found: $desktop"
}

Start-Process -FilePath $desktop -WorkingDirectory (Split-Path -Parent $desktop)
