# Сборка AppUninstaller.exe — самостоятельной программы полного удаления
# Universal Username Finder (исходник: build\Uninstall-UUF.ps1, ps2exe, консольный режим).
#
# .exe двойной клик без PowerShell: удаляет программу, ярлыки, запись в
# «Приложения и возможности», доверие сертификату Hasberd и (после подтверждения) данные.
#
# Запуск:  powershell -ExecutionPolicy Bypass -File build\Build-Uninstaller.ps1
# Результат: ..\dist\AppUninstaller.exe

[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$buildDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($buildDirectory)) { $buildDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path }
$repositoryRoot = Split-Path -Parent $buildDirectory
$scriptPath = Join-Path $buildDirectory 'Uninstall-UUF.ps1'
if (-not [System.IO.File]::Exists($scriptPath)) {
    throw ('Не найден исходный скрипт удаления: ' + $scriptPath)
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot 'dist'
}
$null = [System.IO.Directory]::CreateDirectory($OutputDirectory)
$outputPath = Join-Path $OutputDirectory 'AppUninstaller.exe'

# --- Версия берётся из главного скрипта приложения, чтобы установщик и деинсталлятор не разъезжались по метаданным
$mainScriptPath = Join-Path $repositoryRoot 'UniversalUsernameFinder.ps1'
$appVersion = '0.0.0'
if ([System.IO.File]::Exists($mainScriptPath)) {
    $scriptText = [System.IO.File]::ReadAllText($mainScriptPath)
    $quote = [char]39
    $versionPattern = '\$script:AppVersion\s*=\s*' + $quote + '([0-9]+(?:\.[0-9]+)*)' + $quote
    $versionMatch = [regex]::Match($scriptText, $versionPattern)
    if ($versionMatch.Success) { $appVersion = $versionMatch.Groups[1].Value }
}
$fileVersion = $appVersion
while (([regex]::Matches($fileVersion, '\.')).Count -lt 3) { $fileVersion = $fileVersion + '.0' }

Write-Host ('Исходный скрипт: ' + $scriptPath)
Write-Host ('Версия:          ' + $appVersion + ' (файл: ' + $fileVersion + ')')
Write-Host ('Результат:       ' + $outputPath)

$ps2exe = Get-Module -ListAvailable -Name ps2exe | Select-Object -First 1
if (-not $ps2exe -and -not $SkipInstall) {
    try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch { }
    foreach ($attempt in 1..4) {
        try {
            Install-Module ps2exe -Force -Scope CurrentUser -Repository PSGallery -AllowClobber -ErrorAction Stop
            break
        } catch {
            Write-Host ('Попытка установки ps2exe ' + $attempt + ' не удалась: ' + $_.Exception.Message)
            Start-Sleep -Seconds (10 * $attempt)
        }
    }
    $ps2exe = Get-Module -ListAvailable -Name ps2exe | Select-Object -First 1
}
if (-not $ps2exe) {
    throw 'Модуль ps2exe недоступен. Установите его командой: Install-Module ps2exe -Scope CurrentUser'
}
Import-Module ps2exe

if ([System.IO.File]::Exists($outputPath)) {
    try { [System.IO.File]::Delete($outputPath) } catch { }
}

# --- Консольный режим (без -noConsole): видны шаги удаления и работает подтверждение ввода.
$iconPath = Join-Path $repositoryRoot 'assets\uuf.ico'
$buildArguments = @{
    inputFile   = $scriptPath
    outputFile  = $outputPath
    title       = 'Universal Username Finder - Uninstaller'
    product     = 'Universal Username Finder Uninstaller'
    description = 'Полное удаление Universal Username Finder: файлы, ярлыки, реестр, доверие сертификату, данные'
    copyright   = 'GPL-3.0-or-later'
    company     = 'Hasberd'
    version     = $fileVersion
}
if ([System.IO.File]::Exists($iconPath)) { $buildArguments['iconFile'] = $iconPath }

Invoke-ps2exe @buildArguments

if (-not [System.IO.File]::Exists($outputPath)) {
    throw ('Сборка завершилась без результата: файл не создан (' + $outputPath + ')')
}
$sizeKb = [int][Math]::Round(([System.IO.FileInfo]$outputPath).Length / 1KB)
if ($sizeKb -lt 15) {
    throw ('Собранный файл подозрительно мал (' + $sizeKb + ' КБ): вероятно, сборка прошла некорректно')
}
Write-Host ''
Write-Host ('Готово: ' + $outputPath + ' (' + $sizeKb + ' КБ)')
return $outputPath
