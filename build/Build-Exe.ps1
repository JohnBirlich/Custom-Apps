# Сборка Universal Username Finder в самостоятельный .exe через модуль ps2exe.
#
# ps2exe встраивает исходный скрипт в исполняемый файл и поднимает для него среду
# PowerShell, поэтому .ps1 остаётся единственным источником правды: правки вносятся
# в скрипт, а .exe пересобирается. Отдельного кода на C# в репозитории нет.
#
# Запуск из папки build:  .\Build-Exe.ps1
# Запуск из любого места:  powershell -ExecutionPolicy Bypass -File build\Build-Exe.ps1
# Результат:               ..\dist\UUF.exe

[CmdletBinding()]
param(
    # Каталог для готового .exe. По умолчанию — dist в корне репозитория.
    [string]$OutputDirectory = '',
    # Не устанавливать ps2exe, а только использовать уже имеющийся.
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

# Версия берётся из самого приложения, чтобы метаданные .exe не разъезжались с ним.
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

# Модуль ps2exe. PSGallery периодически отвечает «No match was found for the
# specified search criteria», поэтому установка повторяется несколько раз.
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

# Флаги сборки:
#   -noConsole  приложение Windows Forms без консольного окна;
#   -STA        однопоточный режим, обязателен для Windows Forms;
#   -noOutput / -noError  подавляют стандартный вывод и поток ошибок. В GUI-режиме
#               ps2exe показывает каждую строку вывода отдельным диалогом, а у
#               приложения весь вывод идёт в интерфейс и журнал, поэтому каналы
#               закрываются, чтобы случайная строка не превратилась в окно с кнопкой OK.
# Флаг -DPIAware намеренно не используется: он объявляет процесс DPI-осведомлённым,
# и при масштабировании 125-150 % вместо растянутого, но целого окна можно получить
# мелкую и обрезанную раскладку. Интерфейс размечен абсолютными координатами, поэтому
# вопрос требует проверки на живой машине, а не в сборке.
$iconPath = Join-Path $repositoryRoot 'assets\uuf.ico'
$buildArguments = @{
    inputFile   = $scriptPath
    outputFile  = $outputPath
    noConsole   = $true
    STA         = $true
    noOutput    = $true
    noError     = $true
    title       = 'UUF'
    product     = 'UUF'
    description = 'Генератор никнеймов и проверка доступности на платформах и в Telegram-каналах'
    copyright   = 'GPL-3.0-or-later'
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

Write-Host ''
Write-Host ('Готово: ' + $outputPath + ' (' + $sizeKb + ' КБ)')
Write-Host 'Важно: .exe содержит исходный скрипт в открытом виде (ps2exe извлекает его'
Write-Host 'параметром -extract). Это удобная оболочка для запуска, а не защита кода.'
return $outputPath
