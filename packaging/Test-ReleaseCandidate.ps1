param([Parameter(Mandatory=$true)][string]$Serial)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$target='C:\Program Files\USB Tablet Display Release Test'
if(Test-Path -LiteralPath $target){throw 'Dedicated test installation already exists'}
& (Join-Path $PSScriptRoot 'Test-CleanWindows.ps1') -InstallerPath (Join-Path $repo 'dist\TabletDisplay-Windows-x64-v0.2.5-Setup.exe') -InstallDirectory $target -AllowDeveloperMachine
if($LASTEXITCODE -ne 0){throw 'Installation regression failed; preserve installation for diagnostics'}
. (Join-Path $repo 'windows\controller\Sync-TabletDisplayAndroidApp.ps1')
$metadata=Join-Path $target 'android-app.json'
$info=Get-Content -LiteralPath $metadata -Raw -Encoding UTF8|ConvertFrom-Json
Sync-TabletDisplayAndroidApp -Adb (Join-Path $target 'tools\platform-tools\adb.exe') -Serial $Serial -ApkPath (Join-Path $target $info.FileName) -MetadataPath $metadata
& (Join-Path $PSScriptRoot 'Test-RealUsbSession.ps1') -Serial $Serial -InstallDirectory $target -UninstallAfterTest
