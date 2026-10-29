[CmdletBinding()]
param([string]$Version='0.2.5',[switch]$Refresh)

$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
$dist=Join-Path $repoRoot 'dist'
$name="TabletDisplay-TestKit-v$Version"
$root=Join-Path $dist $name
$archive=Join-Path $dist ($name+'.zip')
$required=@("TabletDisplay-Windows-x64-v$Version-Setup.exe","TabletDisplay-Android-v$Version.apk",'Test-CleanWindows.ps1')
foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $dist $file))) { throw "Required release file is missing: $file" }
}
if ((Test-Path -LiteralPath $archive) -and -not $Refresh) { throw "Test kit archive already exists: $archive" }
if (Test-Path -LiteralPath $root) {
    if (-not $Refresh) { throw "Test kit staging directory already exists: $root" }
    $allowed=@($required)+@('README-FIRST.txt','SHA256SUMS.txt')+@(Get-ChildItem (Join-Path $PSScriptRoot 'testkit') -File|Select-Object -ExpandProperty Name)
    foreach($item in Get-ChildItem -LiteralPath $root -Force){if($item.PSIsContainer -or $item.Name -notin $allowed){throw "Unexpected test kit content: $($item.FullName)"}}
} else {New-Item -ItemType Directory -Path $root | Out-Null}
foreach ($file in $required) { Copy-Item -LiteralPath (Join-Path $dist $file) -Destination $root }
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'testkit') -File |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $root }
$guide=Get-Content -LiteralPath (Join-Path $repoRoot 'docs\other-pc-quickstart.md') -Raw -Encoding UTF8
$guide | Set-Content -LiteralPath (Join-Path $root 'README-FIRST.txt') -Encoding UTF8
Get-ChildItem -LiteralPath $root -File | Where-Object {$_.Name -ne 'SHA256SUMS.txt'} | Sort-Object Name | ForEach-Object {
    "$(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 | Select-Object -ExpandProperty Hash)  $($_.Name)"
} | Set-Content -LiteralPath (Join-Path $root 'SHA256SUMS.txt') -Encoding UTF8
Compress-Archive -LiteralPath $root -DestinationPath $archive -CompressionLevel Optimal -Force
foreach($file in $required){if((Get-FileHash (Join-Path $root $file)).Hash -ne (Get-FileHash (Join-Path $dist $file)).Hash){throw "Test kit source mismatch: $file"}}
"$(Get-FileHash -LiteralPath $archive -Algorithm SHA256 | Select-Object -ExpandProperty Hash)  $(Split-Path -Leaf $archive)" |
    Set-Content -LiteralPath (Join-Path $dist ($name+'.sha256.txt')) -Encoding ASCII
Get-Item -LiteralPath $archive | Select-Object FullName,Length,LastWriteTime
