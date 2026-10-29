[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$WdkRoot = 'D:\DevTools\WindowsKits'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$driverDirectory = Join-Path $repoRoot 'windows\driver\TabletDisplayDriver'
$project = Join-Path $driverDirectory 'TabletDisplayDriver.vcxproj'
$traceWpp = Join-Path $WdkRoot 'bin\10.0.26100.0\x64\tracewpp.exe'
$wppConfigDirectory = Join-Path $WdkRoot 'bin\10.0.26100.0\WppConfig\Rev1'
$msbuild = 'D:\Visual Studio\Community\MSBuild\Current\Bin\MSBuild.exe'

foreach ($requiredPath in @($project, $traceWpp, $wppConfigDirectory, $msbuild)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required build file was not found: $requiredPath"
    }
}

Push-Location $driverDirectory
try {
    & $traceWpp "-CfgDir:$wppConfigDirectory" '-Scan:Trace.h' '-dll' 'Driver.cpp'
    if ($LASTEXITCODE -ne 0) {
        throw "tracewpp failed with exit code $LASTEXITCODE"
    }

    & $msbuild $project '/m' "/p:Configuration=$Configuration" '/p:Platform=x64' '/verbosity:minimal' "/p:TabletDisplayWdkRoot=$WdkRoot\"
    if ($LASTEXITCODE -ne 0) {
        throw "USB Tablet Display driver build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
