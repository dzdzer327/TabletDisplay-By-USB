[CmdletBinding()]
param([string]$Version='0.2.5')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$dist=Join-Path $repo 'dist'
$destination=Join-Path $dist "github-release-v$Version"
$files=@("TabletDisplay-Windows-x64-v$Version-Setup.exe","TabletDisplay-Android-v$Version.apk","TabletDisplay-TestKit-v$Version.zip")
foreach($name in $files){if(-not(Test-Path -LiteralPath (Join-Path $dist $name))){throw "Missing release artifact: $name"}}
New-Item -ItemType Directory -Path $destination -Force|Out-Null
foreach($name in $files){Copy-Item -LiteralPath (Join-Path $dist $name) -Destination (Join-Path $destination $name) -Force}
$checksums=foreach($name in $files){"$((Get-FileHash -LiteralPath (Join-Path $destination $name)).Hash)  $name"}
$checksums|Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding ASCII
Copy-Item -LiteralPath (Join-Path $repo "docs\release-notes-v$Version.md") -Destination (Join-Path $destination 'release-notes.md') -Force
Write-Host "Upload the EXE, APK, TestKit ZIP and SHA256SUMS.txt as Release assets. Use release-notes.md as the description and mark the release as Pre-release."
Get-ChildItem -LiteralPath $destination -File|Select-Object Name,Length
