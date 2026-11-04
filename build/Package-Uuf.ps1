[CmdletBinding()]
param(
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$buildDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($buildDirectory)) { $buildDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path }
$repositoryRoot = Split-Path -Parent $buildDirectory

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot 'dist'
}
$null = [System.IO.Directory]::CreateDirectory($OutputDirectory)
$stageDirectory = Join-Path $OutputDirectory 'UniversalUsernameFinder'
if ([System.IO.Directory]::Exists($stageDirectory)) { Remove-Item -LiteralPath $stageDirectory -Recurse -Force }
$null = [System.IO.Directory]::CreateDirectory($stageDirectory)

$packageFiles = @(
    'UniversalUsernameFinder.ps1',
    'Start-UUF.bat',
    'assets\digital_word_eye.mp4',
    'assets\uuf.ico',
    'build\Install-UUF.ps1',
    'build\Install-UUF.bat',
    'build\Uninstall-UUF.ps1',
    'build\Uninstall-UUF.bat'
)

foreach ($relative in $packageFiles) {
    $source = Join-Path $repositoryRoot $relative
    if (-not [System.IO.File]::Exists($source)) {
        throw ('В пакет не найден файл: ' + $source)
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $stageDirectory ([System.IO.Path]::GetFileName($source))) -Force
}

$zipName = 'UniversalUsernameFinder-windows.zip'
$zipPath = Join-Path $OutputDirectory $zipName
if ([System.IO.File]::Exists($zipPath)) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stageDirectory '*') -DestinationPath $zipPath -Force

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
[System.IO.File]::WriteAllText(($zipPath + '.sha256'), ($hash + '  ' + $zipName), (New-Object System.Text.UTF8Encoding -ArgumentList $false))

Write-Host ('Пакет: ' + $zipPath)
Write-Host ('SHA256: ' + $hash)
return $zipPath
