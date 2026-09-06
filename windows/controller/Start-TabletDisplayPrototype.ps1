[CmdletBinding()]
param(
    [string]$Serial,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$controllerDirectory = Join-Path $PSScriptRoot 'TabletDisplayController'
$controller = Join-Path $controllerDirectory 'x64\Debug\TabletDisplayController.exe'
$buildScript = Join-Path $PSScriptRoot 'Build-TabletDisplayController.ps1'
$adb = 'D:\DevTools\Android\Sdk\platform-tools\adb.exe'

if (-not (Test-Path -LiteralPath $adb)) {
    throw "ADB was not found: $adb"
}

if (-not $SkipBuild) {
    & $buildScript
    if ($LASTEXITCODE -ne 0) {
        throw "Controller build failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath $controller)) {
    throw "Controller executable was not found: $controller"
}

$connectedSerials = @(
    & $adb devices |
        Select-Object -Skip 1 |
        ForEach-Object {
            if ($_ -match '^([^\s]+)\s+device(?:\s|$)') { $Matches[1] }
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

& $adb -s $Serial forward tcp:27183 tcp:27183 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Could not create the ADB video-port forwarding rule.'
}

& $adb -s $Serial shell am force-stop com.example.tabletdisplay | Out-Null
& $adb -s $Serial shell monkey -p com.example.tabletdisplay -c android.intent.category.LAUNCHER 1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Could not start Tablet Display on Android. Deploy the app first.'
}

Write-Host "Android receiver is ready on $Serial."
Write-Host 'Approve the Windows administrator prompt to create the virtual display.'
Start-Process -FilePath $controller -WorkingDirectory $controllerDirectory -Verb RunAs
