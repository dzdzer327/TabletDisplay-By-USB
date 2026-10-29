$ErrorActionPreference='Stop'
$target='C:\Program Files\USB Tablet Display Release Test'
$registration='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\USBTabletDisplay'
$repo=Split-Path -Parent $PSScriptRoot
$result=Join-Path $repo 'dist\release-validation-20261029\cleanup.json'
$report=[ordered]@{Date=(Get-Date -Format o);Status='Running'}
try{
 if([IO.Path]::GetFullPath($target) -ne 'C:\Program Files\USB Tablet Display Release Test'){throw 'Unexpected test directory'}
 $registered=Get-ItemProperty -LiteralPath $registration
 if($registered.InstallLocation -ne $target){throw 'Refusing to change a different product registration'}
 $files=@(Get-ChildItem -LiteralPath $target -Force)
 if($files.Count -ne 1 -or $files[0].Name -ne 'USB Tablet Display.exe' -or $files[0].PSIsContainer){throw 'Unexpected leftover files; manual review required'}
 $expected=(Get-FileHash -LiteralPath (Join-Path $repo 'dist\staging\USB-Tablet-Display-v0.2.4\USB Tablet Display.exe')).Hash
 if((Get-FileHash -LiteralPath $files[0].FullName).Hash -ne $expected){throw 'Leftover binary differs from tested release'}
 Remove-Item -LiteralPath $files[0].FullName -Force
 Remove-Item -LiteralPath $target
 Remove-Item -LiteralPath $registration -Force
 $remaining=@(Get-WindowsDriver -Online -All|Where-Object {$_.ProviderName -eq 'Tablet Display Project'}|Select-Object -ExpandProperty Driver)
 if('oem49.inf' -in $remaining -or 'oem39.inf' -notin $remaining){throw 'Driver restoration differs from initial state'}
 $report.Status='Passed';$report.Detail='Only the verified test EXE, its empty directory and matching stale uninstall registration were removed. oem49.inf was removed by the product uninstaller; pre-existing oem39.inf is retained.'
}catch{$report.Status='Failed';$report.Error=$_.Exception.Message}
$report|ConvertTo-Json|Set-Content -LiteralPath $result -Encoding UTF8
if($report.Status -ne 'Passed'){exit 1}
