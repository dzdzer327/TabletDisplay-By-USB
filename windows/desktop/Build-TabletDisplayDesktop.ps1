[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'

$msbuild = 'D:\Visual Studio\Community\MSBuild\Current\Bin\MSBuild.exe'
$project = Join-Path $PSScriptRoot 'TabletDisplayDesktop\TabletDisplayDesktop.csproj'

if (-not (Test-Path -LiteralPath $msbuild)) {
    throw "MSBuild was not found: $msbuild"
}

& $msbuild $project /nologo /m /restore "/p:Configuration=$Configuration" /p:Platform=AnyCPU
if ($LASTEXITCODE -ne 0) {
    throw "USB Tablet Display Desktop build failed with exit code $LASTEXITCODE"
}

$output = Join-Path $PSScriptRoot "TabletDisplayDesktop\bin\$Configuration\TabletDisplayDesktop.exe"
Write-Host "USB Tablet Display Desktop: $output"
