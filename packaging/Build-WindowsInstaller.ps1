[CmdletBinding()]
param(
    [string]$Version='0.2.5',
    [switch]$SkipBuild,
    [string]$AndroidSdk='D:\DevTools\Android\Sdk'
)

$ErrorActionPreference='Stop'
if ($Version -ne '0.2.5') { throw 'Update the component version declarations before building another version.' }
$repoRoot=Split-Path -Parent $PSScriptRoot
$distRoot=Join-Path $repoRoot 'dist'
$workRoot=Join-Path $distRoot 'installer-build'
$payload=Join-Path $workRoot 'payload'
$dependencies=Join-Path $distRoot 'installer-dependencies'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$source=Join-Path $PSScriptRoot 'installer\Installer.cs'
$manifest=Join-Path $PSScriptRoot 'installer\app.manifest'

& (Join-Path $PSScriptRoot 'Build-ReleasePackages.ps1') -Version $Version -SkipBuild:$SkipBuild
if (-not (Test-Path -LiteralPath $compiler)) { throw "Windows .NET C# compiler not found: $compiler" }
New-Item -ItemType Directory -Path $dependencies -Force | Out-Null
$dotnet=Join-Path $dependencies 'ndp481-x86-x64-allos-enu.exe'
$vc=Join-Path $dependencies 'vc_redist.x64.exe'
if (-not (Test-Path -LiteralPath $dotnet)) {
    Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2203305' -OutFile $dotnet -UseBasicParsing
}
if (-not (Test-Path -LiteralPath $vc)) {
    Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vc -UseBasicParsing
}
foreach ($runtime in @($dotnet,$vc)) {
    $signature=Get-AuthenticodeSignature -LiteralPath $runtime
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw "The runtime does not have a valid Microsoft signature: $runtime"
    }
}

if (Test-Path -LiteralPath $workRoot) {
    $expected=[IO.Path]::GetFullPath((Join-Path $repoRoot 'dist\installer-build'))
    if ([IO.Path]::GetFullPath($workRoot) -ne $expected) { throw 'Installer staging path validation failed.' }
    Remove-Item -LiteralPath $workRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $payload -Force | Out-Null
$staged=Join-Path $distRoot "staging\USB-Tablet-Display-v$Version"
Get-ChildItem -LiteralPath $staged -Force | Where-Object { $_.Name -ne 'MANIFEST.sha256' } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $payload -Recurse -Force }
foreach ($obsolete in @('Setup-Windows.cmd','Setup-Windows.ps1','Uninstall.cmd','Uninstall.ps1','Install-Driver.ps1','Install-ADB.cmd','Install-ADB.ps1')) {
    $path=Join-Path $payload $obsolete
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
}
foreach ($name in @('Install-Product.ps1','Uninstall-Product.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "installer\$name") -Destination $payload
}
$toolsDestination=Join-Path $payload 'tools'
$platformTools=Join-Path $AndroidSdk 'platform-tools'
if (-not (Test-Path -LiteralPath (Join-Path $platformTools 'adb.exe'))) { throw 'Android Platform-Tools are required to build the offline installer.' }
Copy-Item -LiteralPath $platformTools -Destination $toolsDestination -Recurse -Force
Get-ChildItem -LiteralPath (Join-Path $toolsDestination 'platform-tools') -Filter '*.log' -File | Remove-Item -Force
$prerequisites=Join-Path $payload 'prerequisites'
New-Item -ItemType Directory -Path $prerequisites -Force | Out-Null
Copy-Item -LiteralPath $dotnet,$vc -Destination $prerequisites
$notices=Join-Path $PSScriptRoot 'installer\README.md'
Copy-Item -LiteralPath $notices -Destination (Join-Path $payload 'README.md') -Force

$references=@('/r:System.Windows.Forms.dll','/r:System.Drawing.dll','/r:System.IO.Compression.dll','/r:System.IO.Compression.FileSystem.dll')
$common=@('/nologo','/target:winexe','/platform:x64','/optimize+','/codepage:65001',('/win32manifest:'+$manifest))
& $compiler @common @references '/define:UNINSTALLER' (('/out:')+(Join-Path $payload 'Uninstall.exe')) $source
if ($LASTEXITCODE -ne 0) { throw 'Uninstaller compilation failed.' }

Get-ChildItem -LiteralPath $payload -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative=$_.FullName.Substring($payload.Length+1).Replace('\','/')
    "$(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 | Select-Object -ExpandProperty Hash)  $relative"
} | Set-Content -LiteralPath (Join-Path $payload 'MANIFEST.sha256') -Encoding ASCII
$archive=Join-Path $workRoot 'payload.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($payload,$archive,[IO.Compression.CompressionLevel]::Optimal,$false)
$installer=Join-Path $distRoot "TabletDisplay-Windows-x64-v$Version-Setup.exe"
& $compiler @common @references (('/resource:')+$archive+',payload.zip') (('/out:')+$installer) $source
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Test-CleanWindows.ps1') -Destination $distRoot -Force
& (Join-Path $PSScriptRoot 'Build-TestKit.ps1') -Version $Version -Refresh
if ($LASTEXITCODE -ne 0) { throw 'Test kit assembly failed.' }
Get-ChildItem -LiteralPath $distRoot -File | Where-Object { $_.Name -match '^(TabletDisplay-.*\.(exe|apk|zip)|Test-CleanWindows\.ps1)$' } |
    Sort-Object Name | ForEach-Object {
        "$(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 | Select-Object -ExpandProperty Hash)  $($_.Name)"
    } | Set-Content -LiteralPath (Join-Path $distRoot 'SHA256SUMS.txt') -Encoding ASCII
Get-Item -LiteralPath $installer | Select-Object FullName,Length,LastWriteTime
