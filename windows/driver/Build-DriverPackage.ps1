[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$WdkRoot = 'D:\DevTools\WindowsKits'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$driverRoot = Join-Path $repoRoot 'windows\driver'
$projectRoot = Join-Path $driverRoot 'TabletDisplayDriver'
$packageRoot = Join-Path $driverRoot "package\$Configuration-x64"
$buildScript = Join-Path $driverRoot 'Build-TabletDisplayDriver.ps1'
$driverInf = Join-Path $projectRoot 'TabletDisplayDriver.inf'
$driverDll = Join-Path $projectRoot "x64\$Configuration\TabletDisplayDriver.dll"
$inf2Cat = Join-Path $WdkRoot 'bin\10.0.26100.0\x86\Inf2Cat.exe'

foreach ($requiredPath in @($buildScript, $driverInf, $inf2Cat)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required package file was not found: $requiredPath"
    }
}

& $buildScript -Configuration $Configuration -WdkRoot $WdkRoot
if ($LASTEXITCODE -ne 0) {
    throw "Driver build failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $driverDll)) {
    throw "Compiled driver was not found: $driverDll"
}

New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
Copy-Item -LiteralPath $driverInf -Destination $packageRoot -Force
Copy-Item -LiteralPath $driverDll -Destination $packageRoot -Force

& $inf2Cat "/driver:$packageRoot" '/os:10_X64'
if ($LASTEXITCODE -ne 0) {
    throw "Inf2Cat failed with exit code $LASTEXITCODE"
}

Write-Host "Unsigned driver package created at: $packageRoot"
Get-ChildItem -LiteralPath $packageRoot -File | Select-Object Name, Length, LastWriteTime
