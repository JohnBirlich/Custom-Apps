

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
$scriptPath = Join-Path $repositoryRoot 'UniversalUsernameFinder.ps1'

if (-not [System.IO.File]::Exists($scriptPath)) {
    throw ('Не найден исходный скрипт: ' + $scriptPath)
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repositoryRoot 'dist'
}
$null = [System.IO.Directory]::CreateDirectory($OutputDirectory)
$outputPath = Join-Path $OutputDirectory 'UUF.exe'

$scriptText = [System.IO.File]::ReadAllText($scriptPath)
$quote = [char]39
$versionPattern = '\$script:AppVersion\s*=\s*' + $quote + '([0-9]+(?:\.[0-9]+)*)' + $quote
$versionMatch = [regex]::Match($scriptText, $versionPattern)
if (-not $versionMatch.Success) {
    throw 'Не удалось определить $script:AppVersion в UniversalUsernameFinder.ps1'
}
$appVersion = $versionMatch.Groups[1].Value
$fileVersion = $appVersion
while (([regex]::Matches($fileVersion, '\.')).Count -lt 3) { $fileVersion = $fileVersion + '.0' }

Write-Host ('Репозиторий:      ' + $repositoryRoot)
Write-Host ('Исходный скрипт:  ' + $scriptPath)
Write-Host ('Версия:           ' + $appVersion + ' (файл: ' + $fileVersion + ')')
Write-Host ('Результат:        ' + $outputPath)

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
Write-Host ('ps2exe:            ' + (Get-Module ps2exe).Version.ToString())

if ([System.IO.File]::Exists($outputPath)) {
    try { [System.IO.File]::Delete($outputPath) } catch { }
}

$iconPath = Join-Path $repositoryRoot 'assets\uuf.ico'
$buildArguments = @{
    inputFile   = $scriptPath
    outputFile  = $outputPath
    noConsole   = $true
    STA         = $true
    noOutput    = $true
    noError     = $true
    title       = 'Universal Username Finder'
    product     = 'Universal Username Finder'
    description = 'Генератор никнеймов и проверка доступности на платформах и в Telegram-каналах'
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
if ($sizeKb -lt 20) {
    throw ('Собранный файл подозрительно мал (' + $sizeKb + ' КБ): вероятно, сборка прошла некорректно')
}

# Заставка загрузки: видео кладём рядом с UUF.exe (программа ищет его там).
$videoSource = Join-Path $repositoryRoot 'assets\digital_word_eye.mp4'
if ([System.IO.File]::Exists($videoSource)) {
    Copy-Item -LiteralPath $videoSource -Destination (Join-Path $OutputDirectory 'digital_word_eye.mp4') -Force
}

Write-Host ''
Write-Host ('Готово: ' + $outputPath + ' (' + $sizeKb + ' КБ)')
Write-Host 'Важно: .exe содержит исходный скрипт в открытом виде (ps2exe извлекает его'
Write-Host 'параметром -extract). Это удобная оболочка для запуска, а не защита кода.'
return $outputPath
