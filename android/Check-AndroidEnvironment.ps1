[CmdletBinding()]
param(
    [string]$JavaHome = $(if ($env:JAVA_HOME) { $env:JAVA_HOME } else { 'D:\DevTools\Java\jdk-17.0.20.1+1' }),
    [string]$AndroidSdk = $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\DevTools\Android\Sdk' })
)

$ErrorActionPreference = 'Stop'

$java = Join-Path $JavaHome 'bin\java.exe'
$javac = Join-Path $JavaHome 'bin\javac.exe'
$adb = Join-Path $AndroidSdk 'platform-tools\adb.exe'
$android = Join-Path $AndroidSdk 'cmdline-tools\latest\bin\android.exe'

$requiredFiles = @($java, $javac, $adb, $android)
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Required Android development tool was not found: $file"
    }
}

$requiredDirectories = @(
    (Join-Path $AndroidSdk 'platforms\android-36'),
    (Join-Path $AndroidSdk 'build-tools\36.0.0')
)
foreach ($directory in $requiredDirectories) {
    if (-not (Test-Path -LiteralPath $directory)) {
        throw "Required Android SDK package was not found: $directory"
    }
}

$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk

Write-Host 'Java:'
& $java -version
& $javac -version

Write-Host "`nADB:"
& $adb version

Write-Host "`nConnected Android devices:"
& $adb devices -l

[pscustomobject]@{
    JavaHome = $JavaHome
    AndroidSdk = $AndroidSdk
    CompileSdk = 36
    MinimumAndroidApi = 29
    EnvironmentReady = $true
}
