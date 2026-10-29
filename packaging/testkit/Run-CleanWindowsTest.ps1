[CmdletBinding()]
param([switch]$ResumeAfterRestart)

$ErrorActionPreference='Stop'
$powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
try {
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'))
        if ($ResumeAfterRestart) { $arguments+='-ResumeAfterRestart' }
        $process=Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        exit $process.ExitCode
    }
    $test=Join-Path $PSScriptRoot 'Test-CleanWindows.ps1'
    if (-not (Test-Path -LiteralPath $test)) { throw 'Test-CleanWindows.ps1 is missing. Extract the entire test kit first.' }
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$test)
    if ($ResumeAfterRestart) { $arguments+='-ResumeAfterRestart' }
    & $powershell @arguments
    $code=$LASTEXITCODE
    Write-Host "Test exit code: $code"
    if ($code -eq 3010) { Write-Host 'Restart Windows, then double-click Resume-Test.cmd to continue.' }
    Write-Host ('Results folder: '+(Join-Path $PSScriptRoot 'clean-windows-results'))
    [void](Read-Host 'Press Enter to close')
    exit $code
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    [void](Read-Host 'Press Enter to close')
    exit 1
}
