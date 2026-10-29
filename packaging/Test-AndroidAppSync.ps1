[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'windows\controller\Sync-TabletDisplayAndroidApp.ps1')
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('USBTabletDisplay-AppSync-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$apk=Join-Path $temporary 'TabletDisplay-Android-v0.2.3.apk'
$manifest=Join-Path $temporary 'android-app.json'
[IO.File]::WriteAllBytes($apk,[Text.Encoding]::ASCII.GetBytes('isolated test APK fixture; not an Android application'))
$hash=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash
$script:passed=0

function Test-SyncCase {
    param([string]$Name,[object]$InitialCode,[string]$ExpectedAction,[string]$ExpectedError,[string]$InstallError,
        [switch]$Force,[switch]$BadHash,[switch]$Offline,[switch]$UnknownVersion,[switch]$PostInstallWrong,[switch]$MissingApk)
    $state=@{Code=$InitialCode;Calls=[Collections.Generic.List[object]]::new();InstallError=$InstallError;
        Offline=$Offline.IsPresent;UnknownVersion=$UnknownVersion.IsPresent;PostInstallWrong=$PostInstallWrong.IsPresent}
    [ordered]@{PackageName='com.example.tabletdisplay';VersionCode=4;VersionName='0.2.3';FileName=(Split-Path -Leaf $apk);
        Sha256=$(if($BadHash){'0'*64}else{$hash})} | ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding UTF8
    $runner={
        param($Tool,$Arguments,$Timeout)
        if ($Tool -ne 'mock-adb' -or $Arguments[0] -ne '-s' -or $Arguments[1] -ne 'ONLY-TARGET-TABLET') { throw 'Wrong device selection in the sync operation.' }
        $state.Calls.Add(@($Arguments))
        if ($Arguments -contains 'uninstall' -or $Arguments -contains '-d') { throw 'Unexpected destructive install/downgrade operation.' }
        if ($Arguments -contains 'pm') {
            if ($state.Offline) { return [pscustomobject]@{ExitCode=1;Output='error: device offline'} }
            if ($null -eq $state.Code) { return [pscustomobject]@{ExitCode=1;Output=''} }
            return [pscustomobject]@{ExitCode=0;Output='package:/data/app/com.example.tabletdisplay/base.apk'}
        }
        if ($Arguments -contains 'dumpsys') {
            return [pscustomobject]@{ExitCode=0;Output=$(if($state.UnknownVersion){'version unavailable'}else{"versionCode=$($state.Code) minSdk=29 targetSdk=36"})}
        }
        if ($Arguments -contains 'install') {
            if ($Timeout -ne 180000 -or $Arguments -notcontains '-r') { throw 'Expected a bounded, data-preserving update operation.' }
            if ($state.InstallError) { return [pscustomobject]@{ExitCode=1;Output=$state.InstallError} }
            if (-not $state.PostInstallWrong) { $state.Code=4 }
            return [pscustomobject]@{ExitCode=0;Output="Performing Push Install`nSuccess"}
        }
        throw 'Unexpected ADB call.'
    }.GetNewClosure()
    $result=$null
    $caught=$null
    try {
        $path=if($MissingApk){Join-Path $temporary 'missing\TabletDisplay-Android-v0.2.3.apk'}else{$apk}
        $result=Sync-TabletDisplayAndroidApp -Adb 'mock-adb' -Serial 'ONLY-TARGET-TABLET' -ApkPath $path -MetadataPath $manifest -ForceInstall:$Force -AdbCommand $runner
    } catch { $caught=$_.Exception.Message }
    if ($ExpectedError) {
        if (-not $caught -or -not $caught.Contains($ExpectedError)) { throw "$Name expected $ExpectedError, received: $caught" }
    } elseif ($caught -or $result.Action -ne $ExpectedAction) { throw "$Name expected $ExpectedAction, received: $($result.Action) $caught" }
    $installCount=@($state.Calls | Where-Object { $_ -contains 'install' }).Count
    if ($ExpectedAction -in @('Current','Newer') -and $installCount -ne 0) { throw "$Name unexpectedly reinstalled the application." }
    if ($ExpectedAction -in @('Installed','Updated','Reinstalled') -and $installCount -ne 1) { throw "$Name should install exactly once." }
    if ($ExpectedError -in @('APK_HASH_MISMATCH','APK_NOT_FOUND','ADB_DEVICE_QUERY_FAILED','ADB_PACKAGE_VERSION_UNKNOWN') -and $installCount -ne 0) { throw "$Name changed Android despite a preflight failure." }
    $script:passed++
    Write-Host "PASS: $Name"
}

try {
    Test-SyncCase 'First installation' $null 'Installed'
    Test-SyncCase 'Older version updated' 3 'Updated'
    Test-SyncCase 'Same version not reinstalled' 4 'Current'
    Test-SyncCase 'Newer version retained' 5 'Newer'
    Test-SyncCase 'Forced repair of same version' 4 'Reinstalled' -Force
    Test-SyncCase 'Forced install does not downgrade' 5 'Newer' -Force
    Test-SyncCase 'Signing conflict preserves old app' 3 -ExpectedError 'ADB_UPDATE_SIGNATURE_MISMATCH' -InstallError 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]'
    Test-SyncCase 'Device installation approval required' $null -ExpectedError 'ADB_INSTALL_USER_ACTION' -InstallError 'Failure [INSTALL_FAILED_USER_RESTRICTED]'
    Test-SyncCase 'Offline device is not treated as absent app' $null -ExpectedError 'ADB_DEVICE_QUERY_FAILED' -Offline
    Test-SyncCase 'Unknown installed version fails safely' 3 -ExpectedError 'ADB_PACKAGE_VERSION_UNKNOWN' -UnknownVersion
    Test-SyncCase 'APK integrity checked before installation' $null -ExpectedError 'APK_HASH_MISMATCH' -BadHash
    Test-SyncCase 'Missing APK reports failure' $null -ExpectedError 'APK_NOT_FOUND' -MissingApk
    Test-SyncCase 'Installed version verified after success' 3 -ExpectedError 'ADB_INSTALL_VERIFY_FAILED' -PostInstallWrong
    $adb=Join-Path 'D:\DevTools\Android\Sdk' 'platform-tools\adb.exe'
    if (Test-Path -LiteralPath $adb) {
        $native=Invoke-TabletDisplayAdb -Adb $adb -AdbArguments @('version')
        if ($native.ExitCode -ne 0 -or $native.Output -notmatch 'Android Debug Bridge') { throw 'Actual ADB process wrapper failed.' }
        $script:passed++
        Write-Host 'PASS: actual ADB process output capture'
    }
    $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $timed=Invoke-TabletDisplayAdb -Adb $powershell -AdbArguments @('-NoProfile','-Command','Start-Sleep -Seconds 10') -TimeoutMs 100
    if ($timed.ExitCode -ne 124) { throw 'The child process timeout did not fire.' }
    $script:passed++
    Write-Host 'PASS: bounded command timeout'
    Write-Host "Android app sync regression checks passed: $script:passed. Device installation scenarios were mocked; no physical device was modified."
} finally {
    $resolved=[IO.Path]::GetFullPath($temporary)
    $prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\USBTabletDisplay-AppSync-'
    if (-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing cleanup outside the generated test directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
