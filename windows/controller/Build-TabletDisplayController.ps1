[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'

$controllerRoot = Join-Path (Split-Path -Parent $PSCommandPath) 'TabletDisplayController'
$project = Join-Path $controllerRoot 'TabletDisplayController.vcxproj'
$msbuild = 'D:\Visual Studio\Community\MSBuild\Current\Bin\MSBuild.exe'

foreach ($requiredPath in @($project, $msbuild)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required controller build file was not found: $requiredPath"
    }
}

& $msbuild $project '/m' "/p:Configuration=$Configuration" '/p:Platform=x64' '/verbosity:minimal'
if ($LASTEXITCODE -ne 0) {
    throw "USB Tablet Display controller build failed with exit code $LASTEXITCODE"
}
