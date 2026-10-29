[CmdletBinding()]
param(
    [string]$InstallerPath=(Join-Path $PSScriptRoot 'TabletDisplay-Windows-x64-v0.2.5-Setup.exe'),
    [string]$InstallDirectory=(Join-Path $env:ProgramFiles 'USB Tablet Display'),
    [switch]$AllowDeveloperMachine,
    [switch]$ResumeAfterRestart,
    [switch]$TestUninstall
)

$ErrorActionPreference='Stop'
$resultsRoot=Join-Path $PSScriptRoot 'clean-windows-results'
New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null
$reportPath=Join-Path $resultsRoot ('result-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
$report=[ordered]@{Date=(Get-Date -Format o);Computer=$env:COMPUTERNAME;OS=$null;EnvironmentClean=$false;DeveloperIndicators=@();Checks=@();Status='Running';RealUsbDisplay='NotTested'}
function Save-Report { $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8 }
function Check([string]$Name,[scriptblock]$Operation) {
    try {
        $detail=& $Operation
        $report.Checks+=@([ordered]@{Name=$Name;Passed=$true;Detail=($detail -join "`n")})
        Write-Host "PASS: $Name"
        Save-Report
    } catch {
        $report.Checks+=@([ordered]@{Name=$Name;Passed=$false;Detail=$_.Exception.Message})
        throw
    }
}
try {
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script in Windows PowerShell as administrator.' }
    $report.OS=(Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,OSArchitecture)
    $software=@(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue)
    $indicators=@($software | Where-Object { $_.DisplayName -match 'Visual Studio (Community|Professional|Enterprise|Build Tools)|Windows Driver Kit|Windows Software Development Kit|Android Studio|Development Kit|JDK' } | Select-Object -ExpandProperty DisplayName)
    foreach ($name in @('JAVA_HOME','ANDROID_HOME','ANDROID_SDK_ROOT','VSINSTALLDIR','WindowsSdkDir')) {
        $value=[Environment]::GetEnvironmentVariable($name)
        if ($value) { $indicators+="$name=$value" }
    }
    $vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $instances=& $vswhere '-all' '-products' '*' '-property' 'installationPath'
        $indicators+=@($instances | Where-Object { $_ })
    }
    $report.DeveloperIndicators=@($indicators | Select-Object -Unique)
    $report.EnvironmentClean=$report.DeveloperIndicators.Count -eq 0
    Save-Report
    if (-not $report.EnvironmentClean -and -not $AllowDeveloperMachine) { throw 'Development tools were detected. Use a clean Windows PC or explicitly pass -AllowDeveloperMachine for a developer-machine smoke test.' }
    if (-not $report.EnvironmentClean) { Write-Warning 'DEVELOPER MACHINE: these results do not constitute clean-Windows validation.' }
    if (-not (Test-Path -LiteralPath $InstallerPath)) { throw "Installer not found: $InstallerPath" }
    $report.InstallerSHA256=(Get-FileHash -LiteralPath $InstallerPath -Algorithm SHA256).Hash
    Save-Report
    if ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\USBTabletDisplay') -and -not $ResumeAfterRestart) { throw 'The unified installer is already registered. Use -ResumeAfterRestart only when continuing a test that requested a reboot.' }
    if ((Test-Path -LiteralPath $InstallDirectory) -and @(Get-ChildItem -LiteralPath $InstallDirectory -Force).Count -gt 0 -and -not $ResumeAfterRestart) { throw 'The test install directory is not empty.' }
    $beforeDrivers=@(Get-WindowsDriver -Online -All | Where-Object { $_.ProviderName -eq 'Tablet Display Project' } | Select-Object -ExpandProperty Driver)
    if ($ResumeAfterRestart) {
        $resumeState=Get-Content -LiteralPath (Join-Path $InstallDirectory 'installed-product.json') -Raw | ConvertFrom-Json
        if ($resumeState.ProductId -ne 'USBTabletDisplay') { throw 'No valid installation record exists for resume.' }
        $beforeDrivers=@($beforeDrivers | Where-Object { $_ -notin $resumeState.DriverPackages })
    }

    Check 'Unified installation' {
        $process=Start-Process -FilePath $InstallerPath -ArgumentList @('--silent','--install-dir',('"'+$InstallDirectory+'"')) -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) { throw "Installer failed: $($process.ExitCode). See ProgramData\USB Tablet Display\Logs\installer.log." }
        $record=Get-Content -LiteralPath (Join-Path $InstallDirectory 'installed-product.json') -Raw | ConvertFrom-Json
        if ($record.Status -ne 'Installed' -or $record.Version -ne '0.2.5') { throw 'Expected installed product record not found.' }
        if ($record.RestartRequired) { throw 'RESTART_REQUIRED: reboot Windows, then rerun this script with -ResumeAfterRestart.' }
        'Installer exit code 0; product registered as 0.2.5.'
    }
    Check '.NET runtime' {
        $release=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Release
        if ($release -lt 533320) { throw '.NET Framework 4.8.1 is missing.' }
        "Release=$release"
    }
    Check 'Native controller dependency load' {
        $output=& (Join-Path $InstallDirectory 'runtime\TabletDisplayController.exe') '--dependency-check'
        if ($LASTEXITCODE -ne 0) { throw 'Native dependency probe failed.' }
        $output
    }
    Check 'Bundled ADB' {
        $output=& (Join-Path $InstallDirectory 'tools\platform-tools\adb.exe') 'version'
        if ($LASTEXITCODE -ne 0) { throw 'Bundled ADB failed.' }
        $output
    }
    Check 'Driver Store package' {
        $drivers=@(Get-WindowsDriver -Online -All | Where-Object { $_.ProviderName -eq 'Tablet Display Project' -and $_.Version -eq '0.2.5.0' })
        if ($drivers.Count -eq 0) { throw 'Driver version 0.2.5.0 is not staged.' }
        $drivers | ForEach-Object { "$($_.Driver) $($_.Version)" }
    }
    Check 'Shortcuts and uninstall registration' {
        $desktop=Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'USB Tablet Display.lnk'
        $menu=Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'USB Tablet Display\USB Tablet Display.lnk'
        foreach ($path in @($desktop,$menu,(Join-Path $InstallDirectory 'Uninstall.exe'))) { if (-not (Test-Path -LiteralPath $path)) { throw "Missing: $path" } }
        $installed=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\USBTabletDisplay'
        if ($installed.InstallLocation -ne $InstallDirectory) { throw 'Incorrect install directory registered.' }
        'Desktop, Start menu, and Windows uninstall entry are present.'
    }
    Check 'Desktop application launch' {
        $process=Start-Process -FilePath (Join-Path $InstallDirectory 'USB Tablet Display.exe') -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 4
        if ($process.HasExited) { throw "Desktop exited early: $($process.ExitCode)" }
        [void]$process.CloseMainWindow()
        if (-not $process.WaitForExit(4000)) { throw 'Desktop did not close normally.' }
        'WPF application stayed running and closed normally.'
    }
    Check 'Repeat installation' {
        $process=Start-Process -FilePath $InstallerPath -ArgumentList @('--silent','--install-dir',('"'+$InstallDirectory+'"')) -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) { throw "Repeat installation failed: $($process.ExitCode)" }
        'Repeat installation returned 0.'
    }
    if ($TestUninstall) {
        Check 'Uninstall and restore' {
            $process=Start-Process -FilePath (Join-Path $InstallDirectory 'Uninstall.exe') -ArgumentList '--silent' -PassThru -WindowStyle Hidden
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) { throw "Uninstaller failed to start: $($process.ExitCode)" }
            $deadline=(Get-Date).AddSeconds(90)
            while ((Test-Path -LiteralPath $InstallDirectory) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
            if (Test-Path -LiteralPath $InstallDirectory) { throw 'Uninstall did not remove the registered application directory.' }
            if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\USBTabletDisplay') { throw 'Uninstall registration remains.' }
            $afterDrivers=@(Get-WindowsDriver -Online -All | Where-Object { $_.ProviderName -eq 'Tablet Display Project' } | Select-Object -ExpandProperty Driver)
            foreach ($name in $beforeDrivers) { if ($name -notin $afterDrivers) { throw "Pre-existing driver was incorrectly removed: $name" } }
            if (@($afterDrivers | Where-Object { $_ -notin $beforeDrivers }).Count -gt 0) { throw 'A driver introduced by the installer remains.' }
            'Application and installer-owned driver removed; pre-existing drivers retained.'
        }
    }
    $report.Status='Passed'
} catch {
    $report.Status=if ($_.Exception.Message.StartsWith('RESTART_REQUIRED:')) { 'RestartRequired' } else { 'Failed' }
    $report.Error=$_.Exception.Message
    Write-Error $_ -ErrorAction Continue
} finally {
    Save-Report
    Write-Host "Report: $reportPath"
}
if ($report.Status -eq 'RestartRequired') { exit 3010 }
if ($report.Status -ne 'Passed') { exit 1 }
