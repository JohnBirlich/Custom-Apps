# Установка Universal Username Finder на рабочий стол (Windows PowerShell 5.1+).
#
# Кладёт UUF.exe в %LOCALAPPDATA%\Programs\UniversalUsernameFinder и создаёт ярлыки
# на рабочем столе и в меню «Пуск». История, настройки, сейф и журнал живут в
# %LOCALAPPDATA%\UniversalUsernameFinder и при переустановке не трогаются.
#
# Распакуй архив UniversalUsernameFinder-windows (в нём UUF.exe и этот скрипт рядом)
# и выполни:  powershell -ExecutionPolicy Bypass -File .\Install-UUF.ps1
# Удаление:   powershell -ExecutionPolicy Bypass -File .\Install-UUF.ps1 -Uninstall

[CmdletBinding()]
param(
    [string]$ExePath = '',
    [switch]$Uninstall,
    [switch]$RemoveData
)

$ErrorActionPreference = 'Stop'

$appName = 'Universal Username Finder'
$targetDirectory = Join-Path $env:LOCALAPPDATA 'Programs\UniversalUsernameFinder'
$targetExe = Join-Path $targetDirectory 'UUF.exe'
$dataDirectory = Join-Path $env:LOCALAPPDATA 'UniversalUsernameFinder'
$desktopDirectory = [Environment]::GetFolderPath('Desktop')
$programsDirectory = [Environment]::GetFolderPath('Programs')
$shortcutNames = @($appName + '.lnk', 'UniversalUsernameFinder.lnk')

function Remove-InstallShortcuts {
    foreach ($directory in @($desktopDirectory, $programsDirectory)) {
        foreach ($shortcutName in $shortcutNames) {
            $shortcutPath = Join-Path $directory $shortcutName
            if ([System.IO.File]::Exists($shortcutPath)) {
                Remove-Item -LiteralPath $shortcutPath -Force
                Write-Host ('Ярлык удалён: ' + $shortcutPath)
            }
        }
    }
}

function New-InstallShortcut {
    param([string]$Directory)
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcutName in @($appName + '.lnk')) {
        $shortcutPath = Join-Path $Directory $shortcutName
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetExe
        $shortcut.WorkingDirectory = $targetDirectory
        $shortcut.IconLocation = $targetExe + ',0'
        $shortcut.Description = 'Поиск свободных ников и регистрация'
        $shortcut.Save()
        Write-Host ('Ярлык: ' + $shortcutPath)
    }
}

function Stop-RunningApp {
    $running = @(Get-Process -Name 'UUF' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Write-Host 'UUF запущен — закрываю для обновления...'
        $running | ForEach-Object { $_.CloseMainWindow() | Out-Null }
        Start-Sleep -Milliseconds 800
        Get-Process -Name 'UUF' -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Milliseconds 300
    }
}

if ($Uninstall) {
    Stop-RunningApp
    Remove-InstallShortcuts
    if ([System.IO.File]::Exists($targetExe)) {
        Remove-Item -LiteralPath $targetExe -Force
        Write-Host ('Программа удалена: ' + $targetExe)
    }
    try {
        if ((@(Get-ChildItem -LiteralPath $targetDirectory -Force -ErrorAction Stop).Count) -eq 0) {
            Remove-Item -LiteralPath $targetDirectory -Force -Recurse
        }
    } catch { }
    if ($RemoveData) {
        if ([System.IO.Directory]::Exists($dataDirectory)) {
            Remove-Item -LiteralPath $dataDirectory -Recurse -Force
            Write-Host ('Данные удалены: ' + $dataDirectory)
        }
    } else {
        Write-Host ('История, настройки и сейф сохранены: ' + $dataDirectory)
    }
    return
}

if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $scriptDirectory = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDirectory)) { $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $candidate = Join-Path $scriptDirectory 'UUF.exe'
    if (-not [System.IO.File]::Exists($candidate)) { $candidate = Join-Path (Get-Location) 'UUF.exe' }
    $ExePath = $candidate
}
if (-not [System.IO.File]::Exists($ExePath)) {
    throw 'UUF.exe не найден рядом со скриптом установки. Распакуй архив UniversalUsernameFinder-windows в одну папку с Install-UUF.ps1 или укажи путь: -ExePath C:\путь\UUF.exe'
}

Stop-RunningApp
New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
Copy-Item -LiteralPath ([System.IO.Path]::GetFullPath($ExePath)) -Destination $targetExe -Force
New-InstallShortcut -Directory $desktopDirectory
New-InstallShortcut -Directory $programsDirectory
try { Get-Item -LiteralPath $targetExe | Unblock-File } catch { }

Write-Host ''
Write-Host ('Готово! UUF установлен: ' + $targetExe)
Write-Host ('Ярлык «' + $appName + '» лежит на рабочем столе и в меню «Пуск».')
Write-Host ('Данные (история, настройки, сейф, журнал): ' + $dataDirectory)
