$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$assembly=[Reflection.Assembly]::LoadFile((Join-Path $repo 'dist\TabletDisplay-Windows-x64-v0.2.5-Setup.exe'))
$method=$assembly.GetType('Installer',$true).GetMethod('DeleteProductFiles',[Reflection.BindingFlags]'Static,NonPublic')
$target=Join-Path $repo ('dist\uninstall-recovery-tests\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $target -Force|Out-Null
foreach($name in @('USB Tablet Display.exe','Uninstall.exe','Uninstall-Product.ps1','installed-product.json')){[IO.File]::WriteAllText((Join-Path $target $name),'isolated recovery test fixture')}
$lock=[IO.File]::Open((Join-Path $target 'USB Tablet Display.exe'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try{
 $failed=$false;try{$method.Invoke($null,[object[]]@([string]$target))}catch{if($_.Exception.InnerException -isnot [IO.IOException]){throw};$failed=$true}
 if(-not $failed){throw 'Locked payload unexpectedly deleted'}
 foreach($name in @('Uninstall.exe','Uninstall-Product.ps1','installed-product.json')){if(-not(Test-Path (Join-Path $target $name))){throw "Recovery file lost: $name"}}
 Write-Host 'PASS: locked payload failure preserves all uninstall recovery files'
}finally{$lock.Dispose()}
$method.Invoke($null,[object[]]@([string]$target))
if(Test-Path -LiteralPath $target){throw 'Retry after releasing the file lock did not finish'}
Write-Host 'PASS: retry succeeds after releasing the payload lock; no product registration or real driver modified'
