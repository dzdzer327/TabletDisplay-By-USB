[CmdletBinding()]
param(
    [string]$Version = '0.2.5',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$distRoot = Join-Path $repoRoot 'dist'
$stageBase = Join-Path $distRoot 'staging'
$packageName = "USB-Tablet-Display-v$Version"
$stageRoot = Join-Path $stageBase $packageName
$windowsArchive = Join-Path $distRoot "TabletDisplay-Windows-x64-v$Version.zip"
$androidArchive = Join-Path $distRoot "TabletDisplay-Android-v$Version.apk"

$desktopExe = Join-Path $repoRoot 'windows\desktop\TabletDisplayDesktop\bin\Release\TabletDisplayDesktop.exe'
$controllerExe = Join-Path $repoRoot 'windows\controller\TabletDisplayController\x64\Release\TabletDisplayController.exe'
$controllerScript = Join-Path $repoRoot 'windows\controller\Start-TabletDisplayPrototype.ps1'
$driverPackage = Join-Path $repoRoot 'windows\driver\package\Release-x64'
$certificate = Join-Path $repoRoot 'windows\driver\certificates\TabletDisplayTestCertificate.cer'
$androidApk = Join-Path $repoRoot 'android\TabletDisplayApp\app\build\outputs\apk\debug\app-debug.apk'
$androidMetadata = Join-Path (Split-Path -Parent $androidApk) 'output-metadata.json'
$androidSync = Join-Path $repoRoot 'windows\controller\Sync-TabletDisplayAndroidApp.ps1'
$windowsAssets = Join-Path $PSScriptRoot 'windows'

if (-not $SkipBuild) {
    & (Join-Path $repoRoot 'windows\desktop\Build-TabletDisplayDesktop.ps1') -Configuration Release
    & (Join-Path $repoRoot 'windows\controller\Build-TabletDisplayController.ps1') -Configuration Release
    & (Join-Path $repoRoot 'android\Build-TabletDisplayApp.ps1') -Configuration Debug
    & (Join-Path $repoRoot 'windows\driver\Sign-DriverPackage.ps1') -Configuration Release
    & (Join-Path $repoRoot 'windows\driver\Verify-DriverPackage.ps1') -Configuration Release
}

$requiredPaths = @(
    $desktopExe,
    $controllerExe,
    $controllerScript,
    (Join-Path $driverPackage 'TabletDisplayDriver.inf'),
    (Join-Path $driverPackage 'TabletDisplayDriver.dll'),
    (Join-Path $driverPackage 'TabletDisplayDriver.cat'),
    $certificate,
    $androidApk,
    $androidMetadata,
    $androidSync,
    $windowsAssets
)
foreach ($path in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required release input was not found: $path"
    }
}

New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
if (Test-Path -LiteralPath $stageBase) {
    $resolvedDist = [IO.Path]::GetFullPath($distRoot).TrimEnd('\') + '\'
    $resolvedStage = [IO.Path]::GetFullPath($stageBase).TrimEnd('\') + '\'
    if (-not $resolvedStage.StartsWith($resolvedDist, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean a staging path outside dist: $resolvedStage"
    }
    Remove-Item -LiteralPath $stageBase -Recurse -Force
}

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stageRoot 'runtime') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stageRoot 'driver') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stageRoot 'tools') -Force | Out-Null

Copy-Item -LiteralPath $desktopExe -Destination (Join-Path $stageRoot 'USB Tablet Display.exe')
Copy-Item -LiteralPath $controllerExe -Destination (Join-Path $stageRoot 'runtime\TabletDisplayController.exe')
Copy-Item -LiteralPath $controllerScript -Destination (Join-Path $stageRoot 'runtime\Start-TabletDisplayPrototype.ps1')
Copy-Item -LiteralPath $androidSync -Destination (Join-Path $stageRoot 'runtime\Sync-TabletDisplayAndroidApp.ps1')
Copy-Item -Path (Join-Path $driverPackage '*') -Destination (Join-Path $stageRoot 'driver') -Recurse
Copy-Item -LiteralPath $certificate -Destination (Join-Path $stageRoot 'driver\TabletDisplayTestCertificate.cer')
Copy-Item -LiteralPath $androidApk -Destination (Join-Path $stageRoot "TabletDisplay-Android-v$Version.apk")
$built=Get-Content -LiteralPath $androidMetadata -Raw -Encoding UTF8 | ConvertFrom-Json
if ($built.applicationId -ne 'com.example.tabletdisplay' -or @($built.elements).Count -ne 1 -or $built.elements[0].versionName -ne $Version) {
    throw 'Android APK metadata does not match the requested release version. Rebuild Android before packaging.'
}
[ordered]@{
    PackageName=$built.applicationId
    VersionCode=$built.elements[0].versionCode
    VersionName=$built.elements[0].versionName
    FileName="TabletDisplay-Android-v$Version.apk"
    Sha256=(Get-FileHash -LiteralPath $androidApk -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stageRoot 'android-app.json') -Encoding UTF8
Copy-Item -Path (Join-Path $windowsAssets '*') -Destination $stageRoot -Recurse

$readme = Get-Content -LiteralPath (Join-Path $windowsAssets 'README.md') -Raw -Encoding UTF8
$readme = $readme.Replace('{{VERSION}}', $Version)
Set-Content -LiteralPath (Join-Path $stageRoot 'README.md') -Value $readme -Encoding UTF8

$manifestLines = Get-ChildItem -LiteralPath $stageRoot -File -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($stageRoot.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
Set-Content -LiteralPath (Join-Path $stageRoot 'MANIFEST.sha256') -Value $manifestLines -Encoding ASCII

Copy-Item -LiteralPath $androidApk -Destination $androidArchive -Force
if (Test-Path -LiteralPath $windowsArchive) {
    Remove-Item -LiteralPath $windowsArchive -Force
}
Compress-Archive -LiteralPath $stageRoot -DestinationPath $windowsArchive -CompressionLevel Optimal

$checksums = @(
    "$(Get-FileHash -LiteralPath $windowsArchive -Algorithm SHA256 | Select-Object -ExpandProperty Hash)  $(Split-Path -Leaf $windowsArchive)",
    "$(Get-FileHash -LiteralPath $androidArchive -Algorithm SHA256 | Select-Object -ExpandProperty Hash)  $(Split-Path -Leaf $androidArchive)"
)
Set-Content -LiteralPath (Join-Path $distRoot 'SHA256SUMS.txt') -Value $checksums -Encoding ASCII

Write-Host 'Release packages created:'
Get-Item -LiteralPath $windowsArchive, $androidArchive, (Join-Path $distRoot 'SHA256SUMS.txt') |
    Select-Object FullName, Length, LastWriteTime
