# Shared by the desktop startup script and offline regression tests.
function Invoke-TabletDisplayAdb {
    param([string]$Adb, [string[]]$AdbArguments, [int]$TimeoutMs=30000)
    $process=[Diagnostics.Process]::new()
    try {
        $process.StartInfo=[Diagnostics.ProcessStartInfo]::new()
        $process.StartInfo.FileName=$Adb
        $process.StartInfo.Arguments=($AdbArguments | ForEach-Object {
            $escaped=[regex]::Replace($_,'(\\*)"','$1$1\"')
            '"'+[regex]::Replace($escaped,'(\\+)$','$1$1')+'"'
        }) -join ' '
        $process.StartInfo.UseShellExecute=$false
        $process.StartInfo.CreateNoWindow=$true
        $process.StartInfo.RedirectStandardOutput=$true
        $process.StartInfo.RedirectStandardError=$true
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMs)) {
            $process.Kill()
            $process.WaitForExit()
            return [pscustomobject]@{ExitCode=124;Output='ADB_COMMAND_TIMEOUT: unlock the tablet and check for an installation confirmation.'}
        }
        return [pscustomobject]@{ExitCode=$process.ExitCode;Output=($stdout.Result+"`n"+$stderr.Result).Trim()}
    } finally { $process.Dispose() }
}

function Sync-TabletDisplayAndroidApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Adb,
        [Parameter(Mandatory=$true)][string]$Serial,
        [Parameter(Mandatory=$true)][string]$ApkPath,
        [Parameter(Mandatory=$true)][string]$MetadataPath,
        [switch]$ForceInstall,
        [scriptblock]$AdbCommand={param($Tool,$Arguments,$Timeout) Invoke-TabletDisplayAdb -Adb $Tool -AdbArguments $Arguments -TimeoutMs $Timeout}
    )

    $packageName='com.example.tabletdisplay'
    if (-not (Test-Path -LiteralPath $MetadataPath)) { throw 'APK_METADATA_MISSING: reinstall the latest Windows package.' }
    $metadata=Get-Content -LiteralPath $MetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($metadata.elements) {
        if (@($metadata.elements).Count -ne 1 -or $metadata.applicationId -ne $packageName) { throw 'APK_METADATA_INVALID: unsupported Android build metadata.' }
        $targetCode=[long]$metadata.elements[0].versionCode
        $targetName=[string]$metadata.elements[0].versionName
        $expectedHash=$null
    } else {
        if ($metadata.PackageName -ne $packageName -or $metadata.Sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'APK_METADATA_INVALID: invalid Android package information.' }
        $targetCode=[long]$metadata.VersionCode
        $targetName=[string]$metadata.VersionName
        $expectedHash=[string]$metadata.Sha256
        if ([IO.Path]::GetFileName($ApkPath) -ne $metadata.FileName) { throw 'APK_METADATA_INVALID: APK filename does not match its manifest.' }
    }
    if ($targetCode -le 0 -or [string]::IsNullOrWhiteSpace($targetName)) { throw 'APK_METADATA_INVALID: missing Android version.' }

    $pathResult=& $AdbCommand $Adb @('-s',$Serial,'shell','pm','path',$packageName) 30000
    if ($pathResult.ExitCode -notin @(0,1) -or $pathResult.Output -match '(?im)^(?:adb:|error:)|unauthorized|device offline') {
        throw "ADB_DEVICE_QUERY_FAILED: $($pathResult.Output)"
    }
    $installed=$pathResult.Output -match '(?m)^package:'
    $installedCode=$null
    if ($installed) {
        $versionResult=& $AdbCommand $Adb @('-s',$Serial,'shell','dumpsys','package',$packageName) 30000
        if ($versionResult.ExitCode -ne 0 -or $versionResult.Output -notmatch '\bversionCode=(\d+)\b') {
            throw "ADB_PACKAGE_VERSION_UNKNOWN: $($versionResult.Output)"
        }
        $installedCode=[long]$Matches[1]
        if ($installedCode -gt $targetCode) {
            Write-Host "Android has a newer version ($installedCode > $targetCode); keeping it."
            return [pscustomobject]@{Action='Newer';VersionCode=$installedCode;TargetVersion=$targetName}
        }
        if ($installedCode -eq $targetCode -and -not $ForceInstall) {
            Write-Host "Android app is current ($targetName); skipping APK installation."
            return [pscustomobject]@{Action='Current';VersionCode=$installedCode;TargetVersion=$targetName}
        }
    }

    if (-not (Test-Path -LiteralPath $ApkPath)) { throw 'APK_NOT_FOUND: the Android APK is missing from the Windows installation.' }
    if ($expectedHash -and (Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash -ne $expectedHash) { throw 'APK_HASH_MISMATCH: the bundled Android APK failed integrity verification.' }
    $action=if (-not $installed) { 'Installed' } elseif ($installedCode -lt $targetCode) { 'Updated' } else { 'Reinstalled' }
    Write-Host "Preparing Android app $targetName ($action). Unlock the tablet and approve its installation prompt if shown."
    $installResult=& $AdbCommand $Adb @('-s',$Serial,'install','--no-streaming','-r',$ApkPath) 180000
    if ($installResult.ExitCode -ne 0 -or $installResult.Output -notmatch '(?m)^Success\s*$') {
        if ($installResult.Output -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE|INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES') {
            throw 'ADB_UPDATE_SIGNATURE_MISMATCH: the installed Android app uses another signing key. It was not uninstalled; review the conflict before replacing it.'
        }
        if ($installResult.Output -match 'INSTALL_FAILED_USER_RESTRICTED|INSTALL_CANCELED_BY_USER|ADB_COMMAND_TIMEOUT') {
            throw "ADB_INSTALL_USER_ACTION: unlock the tablet, approve USB installation, and retry. $($installResult.Output)"
        }
        throw "ADB_INSTALL_FAILED: $($installResult.Output)"
    }
    $verify=& $AdbCommand $Adb @('-s',$Serial,'shell','dumpsys','package',$packageName) 30000
    if ($verify.ExitCode -ne 0 -or $verify.Output -notmatch '\bversionCode=(\d+)\b' -or [long]$Matches[1] -ne $targetCode) {
        throw 'ADB_INSTALL_VERIFY_FAILED: Android did not report the expected installed version.'
    }
    Write-Host "Android app ready: $targetName."
    return [pscustomobject]@{Action=$action;VersionCode=$targetCode;TargetVersion=$targetName}
}
