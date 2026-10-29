[CmdletBinding()]
param(
    [string]$Serial,
    [switch]$SkipBuild,
    [string]$SettingsPath,
    [switch]$ForceAndroidInstall
)

$ErrorActionPreference = 'Stop'

$portableController = Join-Path $PSScriptRoot 'TabletDisplayController.exe'
$controllerDirectory = if (Test-Path -LiteralPath $portableController) {
    $PSScriptRoot
} else {
    Join-Path $PSScriptRoot 'TabletDisplayController'
}
$releaseController = Join-Path $controllerDirectory 'x64\Release\TabletDisplayController.exe'
$debugController = Join-Path $controllerDirectory 'x64\Debug\TabletDisplayController.exe'
$controller = if (Test-Path -LiteralPath $portableController) {
    $portableController
} elseif (Test-Path -LiteralPath $releaseController) {
    $releaseController
} else {
    $debugController
}
$buildScript = Join-Path $PSScriptRoot 'Build-TabletDisplayController.ps1'
$androidRoot = Join-Path $PSScriptRoot '..\..\android'
$androidBuildScript = Join-Path $androidRoot 'Build-TabletDisplayApp.ps1'
$developmentApk = Join-Path $androidRoot 'TabletDisplayApp\app\build\outputs\apk\debug\app-debug.apk'
$portableRoot = Split-Path -Parent $PSScriptRoot
$portableApk = Get-ChildItem -LiteralPath $portableRoot -Filter 'TabletDisplay-Android-v*.apk' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -ExpandProperty FullName -First 1
$androidApk = if ($portableApk) { $portableApk } else { $developmentApk }

$adbCandidates = @(
    (Join-Path $portableRoot 'tools\platform-tools\adb.exe'),
    $(if ($env:ANDROID_HOME) { Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe' }),
    $(if ($env:ANDROID_SDK_ROOT) { Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe' }),
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
    'D:\DevTools\Android\Sdk\platform-tools\adb.exe',
    $(Get-Command adb.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$adb = $adbCandidates | Select-Object -First 1

if (-not $adb) {
    throw 'ADB was not found. Run Install-ADB.cmd in the Windows package, or add Android platform-tools to PATH.'
}

if (-not $SkipBuild) {
    if (-not (Test-Path -LiteralPath $buildScript)) {
        throw 'This portable package does not contain build tools. Start it from USB Tablet Display.exe.'
    }
    & $buildScript
    if ($LASTEXITCODE -ne 0) {
        throw "Controller build failed with exit code $LASTEXITCODE"
    }
    & $androidBuildScript -Configuration Debug | Out-Host
}

if (-not (Test-Path -LiteralPath $controller)) {
    throw "Required prototype file was not found: $controller"
}

$connectedSerials = @(
    & $adb devices |
        Select-Object -Skip 1 |
        ForEach-Object {
            if ($_ -match '^([^\s]+)\s+device(?:\s|$)') {
                $candidate=$Matches[1]
                if (-not $candidate.StartsWith('emulator-') -and -not $candidate.Contains(':')) { $candidate }
            }
        }
)

if (-not $Serial) {
    if ($connectedSerials.Count -ne 1) {
        throw "Expected exactly one authorized Android device, found $($connectedSerials.Count). Pass -Serial when more than one is connected."
    }
    $Serial = $connectedSerials[0]
}
elseif ($Serial -notin $connectedSerials) {
    throw "Android device is not connected or authorized: $Serial"
}

$syncScript=Join-Path $PSScriptRoot 'Sync-TabletDisplayAndroidApp.ps1'
if (-not (Test-Path -LiteralPath $syncScript)) { throw 'Android application sync script is missing. Reinstall the Windows package.' }
. $syncScript
$portableMetadata=Join-Path $portableRoot 'android-app.json'
$metadataPath=if (Test-Path -LiteralPath $portableMetadata) {
    $info=Get-Content -LiteralPath $portableMetadata -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([IO.Path]::GetFileName([string]$info.FileName) -ne $info.FileName) { throw 'Invalid Android APK manifest filename.' }
    $androidApk=Join-Path $portableRoot $info.FileName
    $portableMetadata
} else {
    Join-Path (Split-Path -Parent $developmentApk) 'output-metadata.json'
}
$appSync=Sync-TabletDisplayAndroidApp -Adb $adb -Serial $Serial -ApkPath $androidApk -MetadataPath $metadataPath -ForceInstall:$ForceAndroidInstall
Write-Host "ANDROID_APP_STATUS=$($appSync.Action)"

& $adb -s $Serial forward tcp:27183 tcp:27183 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Could not create the ADB video-port forwarding rule.'
}

& $adb -s $Serial reverse tcp:27184 tcp:27184 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Could not create the ADB touch-input reverse rule.'
}

& $adb -s $Serial shell am force-stop com.example.tabletdisplay | Out-Null
& $adb -s $Serial shell monkey -p com.example.tabletdisplay -c android.intent.category.LAUNCHER 1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Could not start USB Tablet Display on Android. Deploy the app first.'
}

Write-Host "Android receiver is ready on $Serial."
Write-Host 'Approve the Windows administrator prompt to create the virtual display.'
if (-not $SettingsPath) { $SettingsPath=Join-Path $env:LOCALAPPDATA 'USB Tablet Display\settings.ini' }
Start-Process -FilePath $controller -ArgumentList @('--settings',('"'+$SettingsPath+'"')) -WorkingDirectory $controllerDirectory -Verb RunAs -WindowStyle Hidden
