[CmdletBinding()]
param(
    [string]$Commit = "main"
)

$ErrorActionPreference = "Stop"

$scriptDirectory = Split-Path -Parent $PSCommandPath
$destination = Join-Path $scriptDirectory "upstream"
$archivePath = Join-Path $env:TEMP "windows-driver-samples-$Commit.zip"
$sourceRoot = "Windows-driver-samples-$Commit"
$sourcePath = Join-Path $sourceRoot "video\IndirectDisplay"
$downloadUri = "https://github.com/microsoft/Windows-driver-samples/archive/$Commit.zip"

if (Test-Path -LiteralPath $destination) {
    Write-Host "上游样例已存在：$destination"
    Write-Host "如需重新下载，请先手动删除该目录。"
    exit 0
}

New-Item -ItemType Directory -Path $destination | Out-Null

try {
    Write-Host "正在取得 Microsoft Windows Driver Samples ($Commit)…"
    Invoke-WebRequest -Uri $downloadUri -OutFile $archivePath

    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("idd-sample-" + [guid]::NewGuid())
    Expand-Archive -LiteralPath $archivePath -DestinationPath $temporaryDirectory
    $indirectDisplayPath = Join-Path $temporaryDirectory $sourcePath

    if (-not (Test-Path -LiteralPath $indirectDisplayPath)) {
        throw "下载包中未找到 $sourcePath"
    }

    Get-ChildItem -LiteralPath $indirectDisplayPath | Copy-Item -Destination $destination -Recurse
    Write-Host "完成：$destination"
    Write-Host "请打开 $destination\IddSampleDriver.sln 并以 Debug|x64 构建。"
}
catch {
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    if ($temporaryDirectory -and (Test-Path -LiteralPath $temporaryDirectory)) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}
