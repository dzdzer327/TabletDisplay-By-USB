param([string]$Version='0.2.5')
$ErrorActionPreference='Stop'
$dist=Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $dist "TabletDisplay-TestKit-v$Version.zip"))
try{
 foreach($name in @("TabletDisplay-Windows-x64-v$Version-Setup.exe","TabletDisplay-Android-v$Version.apk",'Test-CleanWindows.ps1')){
  $entries=@($zip.Entries|Where-Object {$_.Name -eq $name})
  if($entries.Count -ne 1){throw "Missing/duplicate member: $name"}
  $stream=$entries[0].Open();$sha=[Security.Cryptography.SHA256]::Create()
  try{$actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
  if($actual -ne (Get-FileHash (Join-Path $dist $name)).Hash){throw "Test kit differs from standalone artifact: $name"}
  Write-Host "PASS: ZIP member is byte-identical to standalone artifact: $name"
 }
}finally{$zip.Dispose()}
