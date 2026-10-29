[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$InstallDirectory)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$stateRoot = Join-Path $env:ProgramData 'USB Tablet Display'
$statePath = Join-Path $stateRoot 'install-state.json'
$marker = Get-Content -LiteralPath (Join-Path $InstallDirectory 'installed-product.json') -Raw | ConvertFrom-Json
$registered = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\USBTabletDisplay'
if ($marker.ProductId -ne 'USBTabletDisplay' -or $marker.InstallDirectory -ne $InstallDirectory -or $registered.InstallLocation -ne $InstallDirectory) {
    throw 'Uninstall target does not match the registered application.'
}
try {
    $stop=[Threading.EventWaitHandle]::OpenExisting('Global\TabletDisplayControllerStop',[Security.AccessControl.EventWaitHandleRights]::Modify)
    try { [void]$stop.Set() } finally { $stop.Dispose() }
} catch [Threading.WaitHandleCannotBeOpenedException] { }
$deadline = (Get-Date).AddSeconds(12)
while ((Get-Process TabletDisplayController -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
if (Get-Process TabletDisplayController -ErrorAction SilentlyContinue) { throw 'The active display session has not stopped. Retry after stopping it.' }
Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -in @('USB Tablet Display','TabletDisplayDesktop') -and $_.Path -eq (Join-Path $InstallDirectory 'USB Tablet Display.exe')
} | ForEach-Object { [void]$_.CloseMainWindow(); if (-not $_.WaitForExit(5000)) { throw 'Close the desktop app before uninstalling.' } }

$packages = @(Get-WindowsDriver -Online -All | Where-Object { $_.ProviderName -eq 'Tablet Display Project' })
foreach ($name in @($marker.DriverPackages)) {
    if ($name -notmatch '^oem\d+\.inf$') { throw "Invalid recorded driver package name: $name" }
    $record = @($marker.DriverPackageRecords | Where-Object { $_.PublishedName -eq $name }) | Select-Object -First 1
    $package = $packages | Where-Object {
        $_.Driver -eq $name -and (
            ($record -and $_.Version -eq $record.Version -and $_.OriginalFileName -eq $record.OriginalFileName) -or
            (-not $record -and $_.Version -eq ($marker.Version + '.0'))
        )
    }
    if ($package) {
        & pnputil.exe '/delete-driver' $name '/uninstall'
        if ($LASTEXITCODE -notin @(0,3010)) { throw "Could not remove driver $name. Restart Windows and retry uninstall." }
    }
}
$remaining = @(Get-WindowsDriver -Online -All | Where-Object { $_.ProviderName -eq 'Tablet Display Project' })
if ($remaining.Count -eq 0) {
    foreach ($entry in @(@{Store='Root';Owned=$marker.AddedRootTrust}, @{Store='TrustedPublisher';Owned=$marker.AddedPublisherTrust})) {
        if ($entry.Owned) {
            if ($marker.CertificateThumbprint -notmatch '^[0-9A-Fa-f]{40}$') { throw 'Invalid certificate thumbprint in the installation record.' }
            $path = "Cert:\LocalMachine\$($entry.Store)\$($marker.CertificateThumbprint)"
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }
}
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'USB Tablet Display.lnk'
$menu = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'USB Tablet Display'
foreach ($path in @($desktopShortcut, (Join-Path $menu 'USB Tablet Display.lnk'))) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
if ((Test-Path -LiteralPath $menu) -and @(Get-ChildItem -LiteralPath $menu -Force).Count -eq 0) { Remove-Item -LiteralPath $menu }
# The native uninstaller removes install-state.json only after deleting payload
# files successfully. Keep ownership information available for a failed retry.
Write-Output 'Product drivers and shortcuts removed. Pre-existing certificates, other driver versions, shared runtimes, and diagnostic logs were retained.'
