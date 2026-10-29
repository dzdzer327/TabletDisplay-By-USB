[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [string]$JavaHome = $(if ($env:JAVA_HOME) { $env:JAVA_HOME } else { 'D:\DevTools\Java\jdk-17.0.20.1+1' }),
    [string]$AndroidSdk = $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\DevTools\Android\Sdk' })
)

$ErrorActionPreference = 'Stop'

$androidRoot = Split-Path -Parent $PSCommandPath
$projectRoot = Join-Path $androidRoot 'TabletDisplayApp'
$gradleWrapper = Join-Path $projectRoot 'gradlew.bat'
$environmentCheck = Join-Path $androidRoot 'Check-AndroidEnvironment.ps1'

& $environmentCheck -JavaHome $JavaHome -AndroidSdk $AndroidSdk | Out-Host

if (-not (Test-Path -LiteralPath $gradleWrapper)) {
    throw "Gradle Wrapper was not found: $gradleWrapper"
}

$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk

$task = "assemble$Configuration"
Push-Location $projectRoot
try {
    & $gradleWrapper '--no-daemon' $task
    $buildExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

if ($buildExitCode -ne 0) {
    throw "Android application build failed with exit code $buildExitCode"
}

$apkName = if ($Configuration -eq 'Debug') { 'app-debug.apk' } else { 'app-release-unsigned.apk' }
$apkPath = Join-Path $projectRoot "app\build\outputs\apk\$($Configuration.ToLowerInvariant())\$apkName"
if (-not (Test-Path -LiteralPath $apkPath)) {
    throw "Gradle returned success, but the APK was not found: $apkPath"
}

Write-Host "USB Tablet Display Android APK created: $apkPath"
Get-Item -LiteralPath $apkPath | Select-Object FullName, Length, LastWriteTime
