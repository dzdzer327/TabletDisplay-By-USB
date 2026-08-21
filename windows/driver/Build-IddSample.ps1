[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$WdkRoot = 'D:\DevTools\WindowsKits'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
$sampleRoot = Join-Path $repoRoot 'windows\driver\upstream\video\IndirectDisplay'
$solution = Join-Path $sampleRoot 'IddSampleDriver.sln'
$driverDirectory = Join-Path $sampleRoot 'IddSampleDriver'
$traceWpp = Join-Path $WdkRoot 'bin\10.0.26100.0\x64\tracewpp.exe'
$wppConfigDirectory = Join-Path $WdkRoot 'bin\10.0.26100.0\WppConfig\Rev1'
$msbuild = 'D:\Visual Studio\Community\MSBuild\Current\Bin\MSBuild.exe'
$toolsetProps = Join-Path $repoRoot 'windows\driver\LocalWdkToolset.props'

foreach ($requiredPath in @($solution, $traceWpp, $wppConfigDirectory, $msbuild, $toolsetProps)) {
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
}
finally {
    Pop-Location
}

& $msbuild $solution '/m' "/p:Configuration=$Configuration" '/p:Platform=x64' '/p:PlatformToolset=v143' "/p:ForceImportBeforeCppTargets=$toolsetProps" "/p:TabletDisplayWdkRoot=$WdkRoot\" '/verbosity:minimal'
if ($LASTEXITCODE -ne 0) {
    throw "IddSample build failed with exit code $LASTEXITCODE"
}
