[CmdletBinding()]
param(
    [string]$Version = '0.2.5',
    [string]$AndroidSdk = 'D:\DevTools\Android\Sdk'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$distRoot = Join-Path $repoRoot 'dist'
$windowsArchive = Join-Path $distRoot "TabletDisplay-Windows-x64-v$Version.zip"
$androidArchive = Join-Path $distRoot "TabletDisplay-Android-v$Version.apk"
$checksumPath = Join-Path $distRoot 'SHA256SUMS.txt'

foreach ($path in @($windowsArchive, $androidArchive, $checksumPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Release output was not found: $path"
    }
}

foreach ($line in Get-Content -LiteralPath $checksumPath) {
    if ($line -notmatch '^([0-9A-F]{64})  (.+)$') {
        throw "Invalid release checksum line: $line"
    }
    $target = Join-Path $distRoot $Matches[2]
    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if ($actual -ne $Matches[1]) {
        throw "Release checksum mismatch: $target"
    }
}
Write-Host 'Release download checksums passed.'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("USBTabletDisplayReleaseTest-" + [Guid]::NewGuid().ToString('N'))
try {
    Expand-Archive -LiteralPath $windowsArchive -DestinationPath $testRoot
    $root = Get-ChildItem -LiteralPath $testRoot -Directory | Select-Object -First 1
    if ($null -eq $root) {
        throw 'The Windows archive did not contain a package root directory.'
    }

    $required = @(
        'USB Tablet Display.exe',
        "TabletDisplay-Android-v$Version.apk",
        'Setup-Windows.cmd',
        'Uninstall.cmd',
        'README.md',
        'MANIFEST.sha256',
        'runtime\TabletDisplayController.exe',
        'runtime\Start-TabletDisplayPrototype.ps1',
        'runtime\Sync-TabletDisplayAndroidApp.ps1',
        'android-app.json',
        'driver\TabletDisplayDriver.inf',
        'driver\TabletDisplayDriver.dll',
        'driver\TabletDisplayDriver.cat',
        'driver\TabletDisplayTestCertificate.cer'
    )
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $root.FullName $relative))) {
            throw "Required archive member is missing: $relative"
        }
    }

    $unexpected = Get-ChildItem -LiteralPath $root.FullName -Recurse -File |
        Where-Object { $_.Extension -in @('.pdb', '.obj', '.log', '.cpp', '.cs') }
    if ($unexpected) {
        throw "Development-only files were included: $($unexpected.FullName -join ', ')"
    }

    $manifest = Get-Content -LiteralPath (Join-Path $root.FullName 'MANIFEST.sha256')
    foreach ($line in $manifest) {
        if ($line -notmatch '^([0-9a-f]{64})  (.+)$') {
            throw "Invalid package manifest line: $line"
        }
        $target = Join-Path $root.FullName $Matches[2].Replace('/', '\')
        $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $Matches[1]) {
            throw "Package manifest mismatch: $target"
        }
    }
    Write-Host "Package manifest passed for $($manifest.Count) files."

    Get-ChildItem -LiteralPath $root.FullName -Filter '*.ps1' -File -Recurse |
        ForEach-Object {
            $null = [ScriptBlock]::Create((Get-Content -LiteralPath $_.FullName -Raw))
        }
    Write-Host 'All packaged PowerShell scripts parsed successfully.'

    $desktop = Join-Path $root.FullName 'USB Tablet Display.exe'
    $assembly = [Reflection.AssemblyName]::GetAssemblyName($desktop)
    if ($assembly.Version.ToString() -ne "$Version.0") {
        throw "Unexpected desktop assembly version: $($assembly.Version)"
    }
    $process = Start-Process -FilePath $desktop -WorkingDirectory $root.FullName -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3
    if ($process.HasExited) {
        throw "Desktop application exited during smoke test with code $($process.ExitCode)."
    }
    Write-Host "Desktop application smoke test passed (PID $($process.Id))."
    $null = $process.CloseMainWindow()
    if (-not $process.WaitForExit(3000)) {
        $process.Kill()
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

$aapt = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Filter 'aapt.exe' -Recurse |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if ($null -eq $aapt) {
    throw "AAPT was not found below: $AndroidSdk"
}
$badging = & $aapt.FullName dump badging $androidArchive
if ($LASTEXITCODE -ne 0) {
    throw 'AAPT could not read the Android package.'
}
$expectedBadging = @(
    "versionName='$Version'",
    "sdkVersion:'29'",
    "targetSdkVersion:'36'",
    "application-label:'USB Tablet Display'"
)
foreach ($expected in $expectedBadging) {
    if (-not ($badging | Select-String -SimpleMatch $expected)) {
        throw "Android package metadata is missing: $expected"
    }
}
Write-Host 'Android package metadata passed.'

Get-Item -LiteralPath $windowsArchive, $androidArchive, $checksumPath |
    Select-Object FullName, Length, LastWriteTime
