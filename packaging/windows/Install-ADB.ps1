[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$downloadUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
$toolsRoot = Join-Path $PSScriptRoot 'tools'
$destination = Join-Path $toolsRoot 'platform-tools'

if (Test-Path -LiteralPath (Join-Path $destination 'adb.exe')) {
    Write-Host "ADB is already installed: $destination"
    exit 0
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("USBTabletDisplay-" + [Guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $temporaryRoot 'platform-tools.zip'
$extractPath = Join-Path $temporaryRoot 'expanded'

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    Write-Host 'Downloading the official Android SDK Platform-Tools package from Google...'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath
    $source = Join-Path $extractPath 'platform-tools'
    if (-not (Test-Path -LiteralPath (Join-Path $source 'adb.exe'))) {
        throw 'The downloaded archive did not contain platform-tools\adb.exe.'
    }
    New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $toolsRoot -Recurse -Force
    & (Join-Path $destination 'adb.exe') version
    Write-Host "ADB installed for USB Tablet Display: $destination"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
