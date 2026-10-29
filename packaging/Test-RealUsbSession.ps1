[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Serial,[string]$InstallDirectory='C:\Program Files\USB Tablet Display Release Test',[switch]$UninstallAfterTest)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'windows\controller\Sync-TabletDisplayAndroidApp.ps1')
$evidence=Join-Path $repo ('dist\usb-session-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $evidence -Force|Out-Null
$adb='D:\DevTools\Android\Sdk\platform-tools\adb.exe'
$controller=$null;$pattern=$null
$originalAutoRotation=$null;$originalUserRotation=$null
$report=[ordered]@{Date=(Get-Date -Format o);Status='Running';Checks=@();Issues=@();Evidence=$evidence;TestsPhysicalCableUnplug=$false}
function Record([string]$Name,[string]$Detail){$report.Checks+=@{Name=$Name;Passed=$true;Detail=[string]::Copy($Detail)};$report|ConvertTo-Json -Depth 5|Set-Content (Join-Path $evidence 'result.json') -Encoding UTF8}
function Adb([string[]]$Arguments){$result=Invoke-TabletDisplayAdb -Adb $adb -AdbArguments (@('-s',$serial)+$Arguments);if($result.ExitCode -ne 0){throw $result.Output};return $result.Output}
function Status {
 $line=[string]::Copy([string](Get-Content 'C:\ProgramData\USB Tablet Display\Logs\TabletDisplayController.runtime.log' -Tail 1))
 $result=@{Line=$line};foreach($key in @('streamRevision','targetFps','targetBitrate','displayHz','encoded','sentBytes','touchFrames','inputConnected','videoFps','touchEnabled')){if($line -match ('(?:^|\s)'+$key+'=(\d+)')){$result[$key]=[long]$Matches[1]}};return $result
}
function Wait-Settings($Settings){$deadline=(Get-Date).AddSeconds(45);do{if($controller.HasExited){throw 'Controller exited'};$s=Status;if($s.streamRevision -eq $Settings.Revision -and $s.displayHz -eq $Settings.RefreshRate -and $s.targetFps -eq $Settings.FrameRate){return $s};Start-Sleep -Milliseconds 300}while((Get-Date) -lt $deadline);throw 'Settings confirmation timed out'}
try {
 if(Get-Process TabletDisplayController -ErrorAction SilentlyContinue){throw 'An existing controller must not be interrupted'}
 $model=Join-Path $evidence 'settings-model.exe'
 Copy-Item -LiteralPath (Join-Path $InstallDirectory 'USB Tablet Display.exe') -Destination $model
 $asm=[Reflection.Assembly]::LoadFile($model)
 $settings=[Activator]::CreateInstance($asm.GetType('TabletDisplayDesktop.SessionPreferences',$true))
 $settings.Width=1920;$settings.Height=1200;$settings.RefreshRate=120;$settings.FrameRate=120;$settings.BitrateMbps=16
 $config=Join-Path $evidence 'settings.ini';$settings.Save($config)
 Adb @('forward','tcp:27183','tcp:27183')|Out-Null;Adb @('reverse','tcp:27184','tcp:27184')|Out-Null
 $originalAutoRotation=(Adb @('shell','settings','get','system','accelerometer_rotation')).Trim()
 $originalUserRotation=(Adb @('shell','settings','get','system','user_rotation')).Trim()
 Adb @('shell','wm','user-rotation','lock','0')|Out-Null
 Adb @('shell','am','force-stop','com.example.tabletdisplay')|Out-Null
 Adb @('shell','am','start','-n','com.example.tabletdisplay/.MainActivity')|Out-Null
 $controller=Start-Process (Join-Path $InstallDirectory 'runtime\TabletDisplayController.exe') -ArgumentList @('--settings',('"'+$config+'"')) -WindowStyle Hidden -PassThru
 $s=Wait-Settings $settings;Record 'Installed controller 120Hz settings' $s.Line
 $pattern=Start-Process powershell.exe -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Run-DisplayTestPattern.ps1')+'"'),'-EvidenceDirectory',('"'+$evidence+'"'),'-Seconds','180') -WindowStyle Hidden -PassThru
 Start-Sleep -Seconds 12
 if($pattern.HasExited -or -not(Test-Path (Join-Path $evidence 'pattern-display.txt'))){throw 'Isolated test pattern did not start'}
 $s=Status;if($s.encoded -lt 30 -or $s.sentBytes -lt 10000){throw 'No sustained encoded video was sent'};Record 'Dynamic USB video at 120Hz target' $s.Line
 Adb @('shell','screencap','-p','/sdcard/tabletdisplay-test.png')|Out-Null
 Adb @('pull','/sdcard/tabletdisplay-test.png',(Join-Path $evidence 'tablet-120.png'))|Out-Null
 Adb @('shell','input','tap','1280','800')|Out-Null
 Adb @('shell','input','swipe','900','900','1400','1000','700')|Out-Null
 Start-Sleep -Seconds 3
 $inputText=[string](Get-Content (Join-Path $evidence 'pattern-input.txt'))
 if($inputText -notmatch 'clicks=([1-9]\d*)' -or $inputText -notmatch 'dragMoves=([1-9]\d*)'){throw "Touch/drag not confirmed by fixture: $inputText"};Record 'Android tap and drag reach isolated Windows test application' $inputText
 $before=[string](Get-Content (Join-Path $evidence 'pattern-input.txt'));Adb @('shell','input','tap','800','100')|Out-Null;Start-Sleep -Seconds 2
 $after=[string](Get-Content (Join-Path $evidence 'pattern-input.txt'));if($before -ne $after){throw 'Letterbox area incorrectly injects touch'};Record 'Portrait letterbox area does not inject desktop input' $after
 $settings.TouchEnabled=$false;$settings.Save($config);$s=Wait-Settings $settings;Start-Sleep -Seconds 2
 foreach($attempt in 1..3){Adb @('shell','input','tap','1280','800')|Out-Null;Start-Sleep -Seconds 1}
 if((Status).inputConnected -ne 1 -or (Status).touchEnabled -ne 0){throw 'Display-only input transport was not reconnected for a valid isolation test'}
 $before=[string](Get-Content (Join-Path $evidence 'pattern-input.txt'));Adb @('shell','input','tap','1280','800')|Out-Null;Start-Sleep -Seconds 2
 $after=[string](Get-Content (Join-Path $evidence 'pattern-input.txt'));if($before -ne $after){throw 'Display-only mode still injected a click'};Record 'Display-only mode blocks Android touch' $after
 $settings.TouchEnabled=$true;$settings.RefreshRate=60;$settings.FrameRate=30;$settings.BitrateMbps=6;$settings.Save($config);$s=Wait-Settings $settings;Start-Sleep -Seconds 6;$s=Status;Record 'Live switch to 60Hz / 30fps / 6Mbps' $s.Line
 $before=[string](Get-Content (Join-Path $evidence 'pattern-input.txt'));Adb @('shell','input','tap','1280','800')|Out-Null;Start-Sleep -Seconds 3
 $after=[string](Get-Content (Join-Path $evidence 'pattern-input.txt'))
 if($before -eq $after){$report.Issues+='First tap after applying settings was lost; touch transport reconnects lazily.'}else{Record 'First tap after enabling touch reaches Windows' $after}
 Adb @('shell','input','tap','1280','800')|Out-Null;Start-Sleep -Seconds 2
 $after=[string](Get-Content (Join-Path $evidence 'pattern-input.txt'));if($before -eq $after){throw 'Touch does not recover after re-enabling'};Record 'Touch works again after settings changes' $after
 Adb @('shell','screencap','-p','/sdcard/tabletdisplay-test.png')|Out-Null;Adb @('pull','/sdcard/tabletdisplay-test.png',(Join-Path $evidence 'tablet-30.png'))|Out-Null
 Adb @('shell','am','force-stop','com.example.tabletdisplay')|Out-Null;Start-Sleep -Seconds 3
 Adb @('shell','am','start','-n','com.example.tabletdisplay/.MainActivity')|Out-Null;Start-Sleep -Seconds 8
 $s=Status;if($s.Line -notmatch 'Streaming to Android'){throw 'Receiver restart did not reconnect'};Record 'Android app restart reconnects without reinstall' $s.Line
 Adb @('shell','dumpsys','display')|Set-Content (Join-Path $evidence 'android-display.txt') -Encoding UTF8
 Copy-Item 'C:\ProgramData\USB Tablet Display\Logs\TabletDisplayController.runtime.log' (Join-Path $evidence 'controller-runtime.log')
 $report.Status=if($report.Issues.Count){'PassedWithIssues'}else{'Passed'}
}catch{$report.Status='Failed';$report.Error=$_.Exception.Message
}finally{
 if($controller -and -not $controller.HasExited){try{$stop=[Threading.EventWaitHandle]::OpenExisting('Global\TabletDisplayControllerStop',[Security.AccessControl.EventWaitHandleRights]::Modify);[void]$stop.Set();$stop.Dispose()}catch{};if(-not $controller.WaitForExit(15000)){$report.Cleanup='Controller did not stop gracefully'}}
 if($pattern -and -not $pattern.HasExited){[void]$pattern.CloseMainWindow();if(-not $pattern.WaitForExit(3000)){$pattern.Kill()}}
 if($null -ne $originalAutoRotation){try{if($originalAutoRotation -eq '1'){Adb @('shell','wm','user-rotation','free')|Out-Null}else{Adb @('shell','wm','user-rotation','lock',$originalUserRotation)|Out-Null}}catch{$report.Issues+='Could not restore Android rotation: '+$_.Exception.Message}}
 if($UninstallAfterTest){
  try{
   if($InstallDirectory -ne 'C:\Program Files\USB Tablet Display Release Test'){throw 'Only the dedicated test installation may be removed'}
   $record=Get-Content (Join-Path $InstallDirectory 'installed-product.json') -Raw|ConvertFrom-Json
   if($record.InstallDirectory -ne $InstallDirectory -or $record.ProductId -ne 'USBTabletDisplay'){throw 'Unexpected installation ownership record'}
   $uninstaller=Start-Process (Join-Path $InstallDirectory 'Uninstall.exe') -ArgumentList '--silent' -WindowStyle Hidden -PassThru
   [void]$uninstaller.WaitForExit(60000);$deadline=(Get-Date).AddSeconds(60)
   while((Test-Path -LiteralPath $InstallDirectory) -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 500}
   if((Test-Path -LiteralPath $InstallDirectory) -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\USBTabletDisplay')){throw 'Test installation remains after uninstall'}
   $remaining=@(Get-WindowsDriver -Online -All|Where-Object {$_.ProviderName -eq 'Tablet Display Project'}|Select-Object -ExpandProperty Driver)
   if('oem49.inf' -in $remaining -or 'oem39.inf' -notin $remaining){throw 'Driver restoration check failed'}
   $report.Uninstall='Passed: dedicated app, registration and oem49.inf removed; oem39.inf retained'
  }catch{$report.Uninstall=$_.Exception.Message;$report.Status='Failed'}
 }
 $report|ConvertTo-Json -Depth 5|Set-Content (Join-Path $evidence 'result.json') -Encoding UTF8
}
if($report.Status -notin @('Passed','PassedWithIssues')){exit 1}
