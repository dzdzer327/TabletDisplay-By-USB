[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$InstallDirectory)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$productId = 'USBTabletDisplay'
$version = '0.2.5'
$registryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\USBTabletDisplay'
$stateRoot = Join-Path $env:ProgramData 'USB Tablet Display'
$logRoot = Join-Path $stateRoot 'Logs'
$statePath = Join-Path $stateRoot 'install-state.json'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run the installer as administrator.'
}
if (-not [Environment]::Is64BitOperatingSystem -or
    @(Get-CimInstance Win32_Processor | Where-Object { $_.Architecture -ne 9 }).Count -gt 0 -or
    [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber -lt 19045) {
    throw 'Windows 10 22H2 or Windows 11 x64 is required.'
}

$InstallDirectory = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\')
$markerPath = Join-Path $InstallDirectory 'installed-product.json'
$previousState = $null
if (Test-Path -LiteralPath $statePath) {
    $previousState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($previousState.ProductId -ne $productId -or $previousState.InstallDirectory -ne $InstallDirectory) {
        throw 'An existing installation uses another directory. Uninstall it before choosing a different directory.'
    }
}
if (Test-Path -LiteralPath $InstallDirectory) {
    if (@(Get-ChildItem -LiteralPath $InstallDirectory -Force).Count -gt 0) {
        if (-not (Test-Path -LiteralPath $markerPath)) { throw 'Choose an empty directory or the existing USB Tablet Display installation.' }
        $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        if ($marker.ProductId -ne $productId) { throw 'The selected directory belongs to a different product.' }
    }
}

Write-Output 'Checking embedded payload integrity...'
$payloadPrefix = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
foreach ($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'MANIFEST.sha256')) {
    if ($line -notmatch '^([0-9a-fA-F]{64})  (.+)$') { throw 'Invalid embedded payload manifest.' }
    $expected = $Matches[1]
    $member = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Matches[2].Replace('/', '\')))
    if (-not $member.StartsWith($payloadPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Payload entry escapes the installer directory.' }
    if ((Get-FileHash -LiteralPath $member -Algorithm SHA256).Hash -ne $expected) { throw "Payload hash mismatch: $member" }
}

$existingPackages = @(Get-WindowsDriver -Online -All | Where-Object { $_.ProviderName -eq 'Tablet Display Project' })
$newer = @($existingPackages | Where-Object { [version]$_.Version -gt [version]'0.2.5.0' })
if ($newer.Count -gt 0) { throw 'A newer USB Tablet Display driver is installed. Use an installer of the same or newer version.' }

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$acl = Get-Acl -LiteralPath $logRoot
$users = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
$rule = [Security.AccessControl.FileSystemAccessRule]::new($users, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.SetAccessRule($rule)
Set-Acl -LiteralPath $logRoot -AclObject $acl

Write-Output 'Stopping any active USB Tablet Display session...'
try {
    $stop = [Threading.EventWaitHandle]::OpenExisting('Global\TabletDisplayControllerStop', [Security.AccessControl.EventWaitHandleRights]::Modify)
    try { [void]$stop.Set() } finally { $stop.Dispose() }
} catch [Threading.WaitHandleCannotBeOpenedException] { }
$deadline = (Get-Date).AddSeconds(12)
while ((Get-Process TabletDisplayController -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
if (Get-Process TabletDisplayController -ErrorAction SilentlyContinue) { throw 'The controller did not stop. Close the active session before installing.' }
Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -in @('USB Tablet Display','TabletDisplayDesktop') -and $_.Path -eq (Join-Path $InstallDirectory 'USB Tablet Display.exe')
} | ForEach-Object { [void]$_.CloseMainWindow(); if (-not $_.WaitForExit(5000)) { throw 'Close the installed desktop app before upgrading.' } }

$restartRequired = $false
function Install-MicrosoftRuntime([string]$Name, [string[]]$Arguments) {
    $path = Join-Path $PSScriptRoot "prerequisites\$Name"
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw "Microsoft runtime signature could not be verified: $Name"
    }
    Write-Output "Installing $Name..."
    $process = Start-Process -FilePath $path -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -notin @(0,1638,3010)) { throw "$Name failed with exit code $($process.ExitCode)." }
    if ($process.ExitCode -eq 3010) { $script:restartRequired = $true }
}
$framework = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
if ($null -eq $framework -or $framework.Release -lt 533320) {
    Install-MicrosoftRuntime 'ndp481-x86-x64-allos-enu.exe' @('/q','/norestart')
}
$runtime = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
if ($null -eq $runtime -or $runtime.Installed -ne 1 -or [version]$runtime.Version.TrimStart('v') -lt [version]'14.44.35211.0') {
    Install-MicrosoftRuntime 'vc_redist.x64.exe' @('/install','/quiet','/norestart')
}

Write-Output 'Copying application, Android APK, ADB and driver files...'
New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
foreach ($item in Get-ChildItem -LiteralPath $PSScriptRoot -Force) {
    if ($item.Name -in @('prerequisites','MANIFEST.sha256','Install-Product.ps1')) { continue }
    Copy-Item -LiteralPath $item.FullName -Destination $InstallDirectory -Recurse -Force
}
[ordered]@{ProductId=$productId;Version=$version;InstallDirectory=$InstallDirectory} |
    ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding UTF8
& (Join-Path $InstallDirectory 'runtime\TabletDisplayController.exe') '--dependency-check'
if ($LASTEXITCODE -ne 0) { throw 'The native controller dependency check failed.' }

$certificatePath = Join-Path $InstallDirectory 'driver\TabletDisplayTestCertificate.cer'
$certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
$catalogPath = Join-Path $InstallDirectory 'driver\TabletDisplayDriver.cat'
$signature = Get-AuthenticodeSignature -LiteralPath $catalogPath
if ($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint -or $certificate.NotAfter -lt (Get-Date)) {
    throw 'The embedded driver catalog certificate is invalid or expired.'
}
$rootExisting = Test-Path -LiteralPath "Cert:\LocalMachine\Root\$($certificate.Thumbprint)"
$publisherExisting = Test-Path -LiteralPath "Cert:\LocalMachine\TrustedPublisher\$($certificate.Thumbprint)"
$state = [ordered]@{
    ProductId=$productId; Version=$version; InstallDirectory=$InstallDirectory
    CertificateThumbprint=$certificate.Thumbprint
    AddedRootTrust=((-not $rootExisting) -or ($previousState -and $previousState.AddedRootTrust))
    AddedPublisherTrust=((-not $publisherExisting) -or ($previousState -and $previousState.AddedPublisherTrust))
    DriverPackages=@(); DriverPackageRecords=@(); RestartRequired=$restartRequired; Status='Installing'
}
if ($previousState) {
    $state.DriverPackages = @($previousState.DriverPackages)
    foreach ($name in $state.DriverPackages) {
        $owned=$existingPackages | Where-Object { $_.Driver -eq $name } | Select-Object -First 1
        if ($owned) { $state.DriverPackageRecords+=@{PublishedName=$owned.Driver;Version=$owned.Version;OriginalFileName=$owned.OriginalFileName} }
    }
}
# Keep the original ownership record on repair/upgrade. A subsequent install
# must not reinterpret trust introduced by the first installation as pre-existing.
function Save-InstallState {
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $markerPath -Encoding UTF8
}
Save-InstallState

# Register an uninstall entry before changing trust/driver state so a failed install is recoverable.
New-Item -Path $registryPath -Force | Out-Null
$uninstaller = Join-Path $InstallDirectory 'Uninstall.exe'
(@{DisplayName='USB Tablet Display';DisplayVersion=$version;Publisher='USB Tablet Display Project';
    InstallLocation=$InstallDirectory;UninstallString=('"'+$uninstaller+'"');QuietUninstallString=('"'+$uninstaller+'" --silent');
    DisplayIcon=(Join-Path $InstallDirectory 'USB Tablet Display.exe')}).GetEnumerator() | ForEach-Object {
        New-ItemProperty -Path $registryPath -Name $_.Key -Value $_.Value -PropertyType String -Force | Out-Null
    }
New-ItemProperty -Path $registryPath -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $registryPath -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null

Write-Output 'Trusting the project development certificate and staging the display driver...'
Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
Import-Certificate -FilePath $certificatePath -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
if ((Get-AuthenticodeSignature -LiteralPath $catalogPath).Status -ne 'Valid') { throw 'Driver catalog trust verification failed.' }
& pnputil.exe '/add-driver' (Join-Path $InstallDirectory 'driver\TabletDisplayDriver.inf') '/install'
if ($LASTEXITCODE -notin @(0,3010)) { throw "Driver staging failed: $LASTEXITCODE" }
if ($LASTEXITCODE -eq 3010) { $state.RestartRequired = $true }
$installed = @(Get-WindowsDriver -Online -All | Where-Object { $_.ProviderName -eq 'Tablet Display Project' -and $_.Version -eq '0.2.5.0' })
if ($installed.Count -eq 0) { throw 'The expected 0.2.5.0 display driver was not found in the Driver Store.' }
$newNames = @($installed | Where-Object { $_.Driver -notin $existingPackages.Driver } | Select-Object -ExpandProperty Driver)
$state.DriverPackages = @(@($state.DriverPackages) + $newNames | Select-Object -Unique)
foreach ($driver in $installed | Where-Object { $_.Driver -in $newNames }) {
    $state.DriverPackageRecords+=@{PublishedName=$driver.Driver;Version=$driver.Version;OriginalFileName=$driver.OriginalFileName}
}
Save-InstallState

Write-Output 'Creating desktop and Start menu shortcuts...'
$shell = New-Object -ComObject WScript.Shell
$menu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'USB Tablet Display'
New-Item -ItemType Directory -Path $menu -Force | Out-Null
foreach ($shortcutPath in @((Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'USB Tablet Display.lnk'), (Join-Path $menu 'USB Tablet Display.lnk'))) {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $InstallDirectory 'USB Tablet Display.exe'
    $shortcut.WorkingDirectory = $InstallDirectory
    $shortcut.Save()
}
$state.Status = 'Installed'
Save-InstallState
if ($state.RestartRequired) { Write-Output 'RESTART REQUIRED: restart Windows before first use. The installer did not restart automatically.' }
Write-Output "Installed USB Tablet Display $version. No boot or Secure Boot settings were changed."
