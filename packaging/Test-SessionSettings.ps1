[CmdletBinding()]
param([switch]$Live)

$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$controller=Join-Path $repo 'windows\controller\TabletDisplayController\x64\Release\TabletDisplayController.exe'
$desktop=Join-Path $repo 'windows\desktop\TabletDisplayDesktop\bin\Release\TabletDisplayDesktop.exe'
$resultRoot=Join-Path $repo ('dist\settings-tests\'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $resultRoot -Force | Out-Null
$config=Join-Path $resultRoot 'settings.ini'
$report=[ordered]@{Date=(Get-Date -Format o);Status='Running';Checks=@();Live=$Live.IsPresent;AndroidConnected='NotProbed';AndroidRendering='NotValidatedByThisScript'}
$process=$null
$assembly=[Reflection.Assembly]::LoadFile($desktop)
$type=$assembly.GetType('TabletDisplayDesktop.SessionPreferences',$true)
function Assert([bool]$Condition,[string]$Message) { if(-not $Condition){throw $Message} }
function New-Settings([int]$Width,[int]$Height,[int]$Hz,[int]$Fps,[int]$Mbps,[bool]$Touch) {
    $settings=[Activator]::CreateInstance($type)
    $settings.Width=$Width; $settings.Height=$Height; $settings.RefreshRate=$Hz
    $settings.FrameRate=$Fps; $settings.BitrateMbps=$Mbps; $settings.TouchEnabled=$Touch
    return $settings
}
function Probe-Native {
    $p=[Diagnostics.Process]::new()
    try {
        $p.StartInfo=[Diagnostics.ProcessStartInfo]::new($controller,('--validate-settings "'+$config+'"'))
        $p.StartInfo.UseShellExecute=$false; $p.StartInfo.CreateNoWindow=$true
        $p.StartInfo.RedirectStandardOutput=$true; $p.StartInfo.RedirectStandardError=$true
        [void]$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        Assert ($p.WaitForExit(10000)) 'Native settings probe timed out.'
        return [pscustomobject]@{ExitCode=$p.ExitCode;Output=$stdout.Result+' '+$stderr.Result}
    } finally { if(-not $p.HasExited){$p.Kill()};$p.Dispose() }
}
function Pass([string]$Name,[string]$Detail) {
    $report.Checks+=@{Name=$Name;Passed=$true;Detail=[string]::Copy($Detail)}
    Write-Host "PASS: $Name"
}
function Read-LiveStatus {
    $log=Join-Path $env:ProgramData 'USB Tablet Display\Logs\TabletDisplayController.runtime.log'
    if(-not(Test-Path -LiteralPath $log)){ $log=Join-Path (Split-Path -Parent $controller) 'TabletDisplayController.runtime.log' }
    if(-not(Test-Path -LiteralPath $log)){return $null}
    $line=[string]::Copy([string](Get-Content -LiteralPath $log -Tail 1))
    if($line -notmatch '^driverFrames='){return $null}
    $values=@{}
    foreach($key in @('requestedRevision','streamRevision','settingsError','displayWidth','displayHeight','displayHz','targetFps','targetBitrate','touchEnabled')) {
        if($line -match ('(?:^|\s)'+$key+'=(-?\d+)')){$values[$key]=[long]$Matches[1]}
    }
    $values['Line']=$line
    return $values
}
function Wait-LiveSettings($Settings) {
    $deadline=(Get-Date).AddSeconds(45)
    $last=$null
    while((Get-Date) -lt $deadline) {
        Assert (-not $process.HasExited) 'The controller exited before acknowledging settings.'
        $last=Read-LiveStatus
        if($last -and $last.requestedRevision -eq $Settings.Revision -and $last.streamRevision -eq $Settings.Revision) {
            Assert ($last.settingsError -eq 0) "Windows rejected the display mode: $($last.settingsError)"
            Assert ($last.displayWidth -eq $Settings.Width -and $last.displayHeight -eq $Settings.Height) 'Actual display resolution does not match the setting.'
            Assert ($last.displayHz -eq $Settings.RefreshRate) 'Actual Windows refresh rate does not match.'
            Assert ($last.targetFps -eq $Settings.FrameRate -and $last.targetBitrate -eq $Settings.BitrateMbps*1000000) 'Encoder target values do not match.'
            Assert ($last.touchEnabled -eq [int]$Settings.TouchEnabled) 'Touch control was not applied.'
            return $last
        }
        Start-Sleep -Milliseconds 250
    }
    throw "Timed out waiting for the controller. Last status: $($last.Line)"
}

try {
    foreach($case in @(@(1280,720,60,30,6,$false),@(1920,1080,60,60,8,$true),@(1920,1200,120,120,16,$true),@(2560,1600,120,60,24,$true))) {
        $s=New-Settings @case; $s.Save($config)
        $loaded=$type::Load([string]$config)
        Assert ($loaded.FrameRate -eq $s.FrameRate -and $loaded.BitrateMbps -eq $s.BitrateMbps -and $loaded.Revision -eq $s.Revision) 'Windows settings persistence failed.'
        $probe=Probe-Native
        Assert ($probe.ExitCode -eq 0 -and $probe.Output.Contains("fps=$($s.FrameRate)") -and $probe.Output.Contains("bitrate=$($s.BitrateMbps*1000000)")) 'Controller and desktop interpret settings differently.'
        Pass "Persistence and native interpretation: $($s.Width)x$($s.Height) $($s.RefreshRate)Hz / $($s.FrameRate)fps" $probe.Output
    }
    $bad=New-Settings 1920 1080 60 120 8 $true
    $rejected=$false;try{$bad.Save($config)}catch{$rejected=$true}
    Assert $rejected 'Desktop accepted 120fps with a 60Hz display mode.'
    Pass 'Desktop rejects inconsistent refresh/frame-rate settings' ''
    [IO.File]::WriteAllText($config,"FrameRate=999`r`nRevision=1`r`n",[Text.Encoding]::ASCII)
    Assert ((Probe-Native).ExitCode -eq 2) 'Controller accepted an invalid frame rate.'
    Pass 'Controller rejects invalid configuration' ''
    [IO.File]::WriteAllText($config,"BitRate=-1`r`n",[Text.Encoding]::ASCII)
    Assert ((Probe-Native).ExitCode -eq 2) 'Controller accepted a negative bitrate.'
    Pass 'Controller rejects negative bitrate' ''

    if($Live) {
        $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
        Assert ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) 'Live display test requires an elevated Windows PowerShell.'
        Assert (-not(Get-Process TabletDisplayController -ErrorAction SilentlyContinue)) 'Stop the existing display session before the live test.'
        $first=New-Settings 1920 1080 60 30 6 $false; $first.Save($config)
        $process=Start-Process -FilePath $controller -ArgumentList @('--settings',('"'+$config+'"')) -WindowStyle Hidden -PassThru
        $id=$process.Id
        $status=Wait-LiveSettings $first
        Pass 'Live initial 1080p / 60Hz / 30fps / 6Mbps / display-only' $status.Line
        $second=New-Settings 1920 1200 120 120 16 $true; $second.Save($config)
        $status=Wait-LiveSettings $second
        Assert ($process.Id -eq $id -and -not $process.HasExited) 'Settings change replaced the controller process.'
        Pass 'Live switch to 1920x1200 / 120Hz / 120fps / 16Mbps' $status.Line
        $third=New-Settings 1280 720 60 60 8 $true; $third.Save($config)
        $status=Wait-LiveSettings $third
        Pass 'Live switch back to 720p / 60Hz / 60fps / 8Mbps' $status.Line
        [IO.File]::WriteAllText($config,"FrameRate=999`r`nRevision=123`r`n",[Text.Encoding]::ASCII)
        $deadline=(Get-Date).AddSeconds(5)
        do{$status=Read-LiveStatus;if($status -and $status.settingsError -eq -5){break};Start-Sleep -Milliseconds 250}while((Get-Date) -lt $deadline)
        Assert ($status.settingsError -eq -5 -and $status.streamRevision -eq $third.Revision -and -not $process.HasExited) 'Invalid live settings disrupted the existing pipeline.'
        Pass 'Invalid live request rejected while previous session remains active' $status.Line
        $third.Save($config)
        $status=Wait-LiveSettings $third
        Pass 'Valid settings recover after a rejected request' $status.Line
    }
    $report.Status='Passed'
} catch {
    $report.Status='Failed';$report.Error=$_.Exception.Message
    Write-Error $_ -ErrorAction Continue
} finally {
    if($process -and -not $process.HasExited) {
        try{$stop=[Threading.EventWaitHandle]::OpenExisting('Global\TabletDisplayControllerStop',[Security.AccessControl.EventWaitHandleRights]::Modify);[void]$stop.Set();$stop.Dispose()}catch{}
        if(-not $process.WaitForExit(15000)){$process.Kill();$report.Status='Failed';$report.Error='Controller did not stop gracefully after live settings test.'}
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $resultRoot 'result.json') -Encoding UTF8
    Write-Host "Settings test result: $($report.Status). Report: $resultRoot\result.json"
}
if($report.Status -ne 'Passed'){exit 1}
