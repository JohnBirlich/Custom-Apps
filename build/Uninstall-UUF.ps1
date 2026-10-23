# Полное удаление Universal Username Finder (Windows PowerShell 5.1+).
#
# Программа удаляет всё, что оставил установщик:
#   - файлы в %LOCALAPPDATA%\Programs\UniversalUsernameFinder (UUF.exe, сертификат, этот скрипт);
#   - ярлыки на рабочем столе и в меню «Пуск»;
#   - запись в «Приложения и возможности» (HKCU);
#   - доверие к сертификату издателя Hasberd из хранилищ текущего пользователя
#     («Доверенные корневые» и «Доверенные издатели») — только самоподписанный сертификат CN=Hasberd;
#   - данные приложения: историю ников, настройки, зашифрованный сейф и журнал
#     (%LOCALAPPDATA%\UniversalUsernameFinder) — по умолчанию спрашивает подтверждение.
#
# Запуск: двойной щелчок по Uninstall-UUF.bat, кнопка «Удалить» в «Приложениях» или
# powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-UUF.ps1 [-KeepData] [-Silent]

[CmdletBinding()]
param(
    # Оставить историю, настройки, сейф и журнал (по умолчанию при запуске спрашивается).
    [switch]$KeepData,
    # Без вопросов и пауз: удаляет всё сразу (для QuietUninstallString из реестра).
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'

# --- Ошибка не должна закрывать окно молча: печатаем её и ждём Enter
trap {
    Write-Host ''
    Write-Host ('ОШИБКА: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Удаление не завершено. Скопируй текст ошибки в чат — починим.' -ForegroundColor Yellow
    if (-not $Silent -and $Host.Name -eq 'ConsoleHost') { $null = Read-Host 'Нажмите Enter, чтобы закрыть окно' }
    exit 1
}

$appName = 'Universal Username Finder'
$targetDirectory = Join-Path $env:LOCALAPPDATA 'Programs\UniversalUsernameFinder'
$dataDirectory = Join-Path $env:LOCALAPPDATA 'UniversalUsernameFinder'
$desktopDirectory = [Environment]::GetFolderPath('Desktop')
$programsDirectory = [Environment]::GetFolderPath('Programs')
$shortcutNames = @($appName + '.lnk', 'UniversalUsernameFinder.lnk')
$uninstallRegistryKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\UniversalUsernameFinder'

function Write-Step {
    param([string]$Text)
    Write-Host ('· ' + $Text)
}

function Stop-RunningApp {
    $running = @(Get-Process -Name 'UUF' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Write-Step 'Закрываю запущенный UUF...'
        $running | ForEach-Object { $_.CloseMainWindow() | Out-Null }
        Start-Sleep -Milliseconds 800
        Get-Process -Name 'UUF' -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Milliseconds 300
    }
}

function Remove-UufShortcuts {
    $removed = 0
    foreach ($directory in @($desktopDirectory, $programsDirectory)) {
        foreach ($shortcutName in $shortcutNames) {
            $shortcutPath = Join-Path $directory $shortcutName
            if ([System.IO.File]::Exists($shortcutPath)) {
                try {
                    Remove-Item -LiteralPath $shortcutPath -Force
                    $removed++
                    Write-Step ('Ярлык удалён: ' + $shortcutPath)
                } catch {
                    Write-Host ('  Не удалось удалить ярлык ' + $shortcutPath + ': ' + $_.Exception.Message) -ForegroundColor Yellow
                }
            }
        }
    }
    return $removed
}

function Remove-UufRegistryEntry {
    try {
        if (Test-Path -LiteralPath $uninstallRegistryKey) {
            Remove-Item -LiteralPath $uninstallRegistryKey -Recurse -Force
            Write-Step 'Запись в «Приложения и возможности» удалена.'
        }
    } catch {
        Write-Host ('  Не удалось удалить запись реестра: ' + $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Remove-UufCertificateTrust {
    $removed = 0
    foreach ($storeName in @('Root','TrustedPublisher')) {
        try {
            $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName,'CurrentUser')
            try {
                $store.Open('ReadWrite')
                foreach ($cert in @($store.Certificates)) {
                    if (([string]$cert.Subject -like 'CN=Hasberd*') -and ([string]$cert.Issuer -like 'CN=Hasberd*')) {
                        $store.Remove($cert)
                        $removed++
                    }
                }
            } finally { $store.Close() }
        } catch {
            Write-Host ('  Хранилище ' + $storeName + ': ' + $_.Exception.Message) -ForegroundColor Yellow
        }
    }
    if ($removed -gt 0) { Write-Step ('Доверие к сертификату Hasberd удалено из хранилищ ({0} шт.).' -f $removed) }
    else { Write-Step 'Самоподписанный сертификат Hasberd в хранилищах не найден — удалять доверие не нужно.' }
    return $removed
}

function Remove-UufDirectory {
    param([string]$Path,[string]$Label)
    if (-not [System.IO.Directory]::Exists($Path)) { return $false }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force
        Write-Step ($Label + ' удалено: ' + $Path)
        return $true
    } catch {
        # --- Этот скрипт лежит внутри папки и может быть залочен при самоудалении: дочищаем detached-командой
        Write-Step ($Label + ' занят — поставил доочистку через 3 секунды (' + $Path + ')')
        try {
            $delayThen = 'ping -n 3 127.0.0.1 >nul & rd /s /q "' + $Path + '"'
            Start-Process -FilePath $env:ComSpec -ArgumentList @('/c', $delayThen) -WindowStyle Hidden
        } catch {
            Write-Host ('  Доудали вручную: rmdir /s /q "' + $Path + '"') -ForegroundColor Yellow
        }
        return $false
    }
}

Write-Host ''
Write-Host ('Полное удаление ' + $appName) -ForegroundColor Cyan
Write-Host ('  Программа: ' + $targetDirectory)
Write-Host ('  Данные:    ' + $dataDirectory)
Write-Host ''

$removeData = $true
if ($KeepData) {
    $removeData = $false
} elseif (-not $Silent) {
    $answer = Read-Host 'Удалить также историю, настройки, сейф и журнал? [Д/н]'
    if ($answer -match '^(н|n|Н|N)') { $removeData = $false }
}

Stop-RunningApp
$null = Remove-UufShortcuts
Remove-UufRegistryEntry
$null = Remove-UufCertificateTrust
$programRemoved = Remove-UufDirectory -Path $targetDirectory -Label 'Программа'
if ($removeData) {
    $null = Remove-UufDirectory -Path $dataDirectory -Label 'Данные'
} else {
    Write-Step ('История, настройки и сейф сохранены: ' + $dataDirectory)
}
if ($programRemoved) {
    Write-Step 'Папка программы удалена полностью.'
}
Write-Host ''
Write-Host 'Готово: программа удалена с компьютера.' -ForegroundColor Green
Write-Host 'Если архив-папка с установщиком осталась в загрузках — удали её вручную, она больше не нужна.'
if (-not $Silent -and $Host.Name -eq 'ConsoleHost') { $null = Read-Host 'Нажмите Enter, чтобы закрыть окно' }
exit 0
