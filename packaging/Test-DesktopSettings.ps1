[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run this test with powershell.exe -STA.'}
$repo=Split-Path -Parent $PSScriptRoot
$desktop=Join-Path $repo 'windows\desktop\TabletDisplayDesktop\bin\Release\TabletDisplayDesktop.exe'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
$assembly=[Reflection.Assembly]::LoadFile($desktop)
$app=[Activator]::CreateInstance($assembly.GetType('TabletDisplayDesktop.App',$true))
$app.InitializeComponent()
$window=[Activator]::CreateInstance($assembly.GetType('TabletDisplayDesktop.MainWindow',$true))
$read=$window.GetType().GetMethod('ReadSettingsControls',[Reflection.BindingFlags]'Instance,NonPublic')
$checks=0
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw $Name};$script:checks++;Write-Host "PASS: $Name"}
try {
    $quick=$window.FindName('QuickFpsCombo');$full=$window.FindName('StreamFpsCombo');$hz=$window.FindName('DisplayRefreshCombo')
    $quick.SelectedIndex=2
    $settings=$read.Invoke($window,@())
    Check ($full.SelectedIndex -eq 2 -and $hz.SelectedIndex -eq 1 -and $settings.FrameRate -eq 120 -and $settings.RefreshRate -eq 120) 'Home 120fps selection changes video cap and Windows refresh controls'
    $hz.SelectedIndex=0
    Check ($quick.SelectedIndex -eq 1 -and $full.SelectedIndex -eq 1) 'Selecting 60Hz prevents an inconsistent 120fps cap'
    $window.FindName('DisplayResolutionCombo').SelectedIndex=0
    $settings=$read.Invoke($window,@())
    Check ($window.FindName('QuickResolutionCombo').SelectedIndex -eq 0 -and $settings.Width -eq 1280 -and $settings.Height -eq 720) 'Display resolution changes synchronize with home controls'
    $window.FindName('PresetLatency').IsChecked=$true
    $settings=$read.Invoke($window,@())
    Check ($settings.FrameRate -eq 120 -and $settings.RefreshRate -eq 120 -and $settings.BitrateMbps -eq 12) 'Low latency preset changes actual session values'
    $window.FindName('TargetBitrateSlider').Value=22
    $settings=$read.Invoke($window,@())
    Check ($settings.BitrateMbps -eq 22 -and $settings.Preset -eq -1) 'Bitrate slider updates settings and clears preset selection'
    $window.FindName('QuickTouchCombo').SelectedIndex=1
    $settings=$read.Invoke($window,@())
    Check (-not $settings.TouchEnabled -and $window.FindName('TouchEnabledBox').IsChecked -eq $false) 'Display-only control disables native touch in session settings'
    $window.FindName('TouchEnabledBox').IsChecked=$true
    Check ($window.FindName('QuickTouchCombo').SelectedIndex -eq 0) 'Input-page touch switch synchronizes with home control'
    Check ($window.FindName('QuickApplyButton').IsEnabled -and $window.FindName('DisplayApplyButton').IsEnabled -and $window.FindName('VideoApplyButton').IsEnabled) 'All three apply actions are enabled and initialized'
    Write-Host "Desktop settings checks: $checks passed. No user settings were saved and no display session was started."
} finally {$window.Close();$app.Shutdown()}
