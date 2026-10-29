[CmdletBinding()]
param(
    [switch]$SkipAdb,
    [switch]$SkipShortcut
)

$ErrorActionPreference = 'Stop'

if (-not $SkipAdb -and -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'tools\platform-tools\adb.exe'))) {
    & (Join-Path $PSScriptRoot 'Install-ADB.ps1')
}

$driverInstaller = Join-Path $PSScriptRoot 'Install-Driver.ps1'
$process = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"' + $driverInstaller + '"')
) -Verb RunAs -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Driver installer exited with code $($process.ExitCode)."
}

if (-not $SkipShortcut) {
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    $shortcutPath = Join-Path $desktop 'USB Tablet Display.lnk'
    $target = Join-Path $PSScriptRoot 'USB Tablet Display.exe'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $target
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.Description = 'USB Tablet Display'
    $shortcut.Save()
    Write-Host "Desktop shortcut created: $shortcutPath"
}

Write-Host 'Windows setup completed. Install the Android APK, enable USB debugging, connect the tablet, then open USB Tablet Display.'
