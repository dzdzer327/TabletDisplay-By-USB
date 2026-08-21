[CmdletBinding()]
param(
    [string]$Serial,
    [switch]$SkipBuild,
    [string]$AndroidSdk = $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\DevTools\Android\Sdk' })
)

$ErrorActionPreference = 'Stop'

$androidRoot = Split-Path -Parent $PSCommandPath
$buildScript = Join-Path $androidRoot 'Build-TabletDisplayApp.ps1'
$apkPath = Join-Path $androidRoot 'TabletDisplayApp\app\build\outputs\apk\debug\app-debug.apk'
$adb = Join-Path $AndroidSdk 'platform-tools\adb.exe'

if (-not $SkipBuild) {
    & $buildScript -Configuration Debug -AndroidSdk $AndroidSdk | Out-Host
}

foreach ($requiredFile in @($adb, $apkPath)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required deployment file was not found: $requiredFile"
    }
}

if ([string]::IsNullOrWhiteSpace($Serial)) {
    $devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' })
    if ($devices.Count -ne 1) {
        throw "Expected exactly one authorized Android device, but found $($devices.Count). Pass -Serial when multiple devices are connected."
    }
    $Serial = ($devices[0] -split '\s+')[0]
}

Write-Host "Installing Tablet Display on Android device: $Serial"
& $adb -s $Serial install '--no-streaming' '-r' $apkPath
if ($LASTEXITCODE -ne 0) {
    throw "ADB installation failed with exit code $LASTEXITCODE"
}

& $adb -s $Serial forward '--remove' 'tcp:27183' 2>$null
& $adb -s $Serial forward 'tcp:27183' 'tcp:27183'
if ($LASTEXITCODE -ne 0) {
    throw "ADB port forwarding failed with exit code $LASTEXITCODE"
}

& $adb -s $Serial shell am force-stop com.example.tabletdisplay
& $adb -s $Serial shell am start -n 'com.example.tabletdisplay/.MainActivity'
if ($LASTEXITCODE -ne 0) {
    throw "Tablet Display launch failed with exit code $LASTEXITCODE"
}

[pscustomobject]@{
    DeviceSerial = $Serial
    Package = 'com.example.tabletdisplay'
    ForwardedPort = 27183
    AppStarted = $true
}
