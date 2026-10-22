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
    [switch]$RemoveData,
    # Добавить UUF-signing.cer в доверенные корневые и доверенные издатели текущего
    # пользователя (без администратора): после этого SmartScreen показывает
    # «Издатель: Hasberd» вместо красного окна «Неизвестный издатель».
    [switch]$TrustSelfSigned
)

$ErrorActionPreference = 'Stop'

# --- Любая непройденная ошибка печатается в окно и ждёт Enter: двойной клик по .ps1 не должен закрывать PowerShell мгновенно.
trap {
    Write-Host ''
    Write-Host ('ОШИБКА: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Установка не завершена. Скопируй текст ошибки в чат — починим.' -ForegroundColor Yellow
    if ($Host.Name -eq 'ConsoleHost') { $null = Read-Host 'Нажмите Enter, чтобы закрыть окно' }
    exit 1
}

$appName = 'Universal Username Finder'
$targetDirectory = Join-Path $env:LOCALAPPDATA 'Programs\UniversalUsernameFinder'
$targetExe = Join-Path $targetDirectory 'UUF.exe'
$targetCertificatePath = Join-Path $targetDirectory 'UUF-signing.cer'
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

function Get-InstalledCertificateThumbprint {
    $certificateCandidates = @((Join-Path $targetDirectory 'UUF-signing.cer'))
    if (-not [string]::IsNullOrWhiteSpace($ExePath)) {
        $certificateCandidates += (Join-Path (Split-Path -Parent ([System.IO.Path]::GetFullPath($ExePath))) 'UUF-signing.cer')
    }
    foreach ($candidatePath in $certificateCandidates) {
        if ([System.IO.File]::Exists($candidatePath)) {
            try {
                $cer = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($candidatePath)
                return [string]$cer.Thumbprint
            } catch { }
        }
    }
    return ''
}

if ($Uninstall) {
    Stop-RunningApp
    Remove-InstallShortcuts
    $thumbprint = Get-InstalledCertificateThumbprint
    if ($thumbprint) {
        foreach ($storePath in @('Cert:\CurrentUser\Root', 'Cert:\CurrentUser\TrustedPublisher')) {
            try {
                $stale = @(Get-ChildItem -CertStoreLocation $storePath -ErrorAction Stop | Where-Object { $_.Thumbprint -eq $thumbprint })
                foreach ($item in $stale) { Remove-Item -LiteralPath $item.PSPath -Force }
            } catch { }
        }
        Write-Host 'Доверие к сертификату Hasberd из хранилища текущего пользователя удалено.'
    }
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
$exeSourceFull = [System.IO.Path]::GetFullPath($ExePath)
$certificateSource = Join-Path (Split-Path -Parent $exeSourceFull) 'UUF-signing.cer'
if ([System.IO.File]::Exists($certificateSource)) {
    Copy-Item -LiteralPath $certificateSource -Destination (Join-Path $targetDirectory 'UUF-signing.cer') -Force
}
New-InstallShortcut -Directory $desktopDirectory
New-InstallShortcut -Directory $programsDirectory
try { Get-Item -LiteralPath $targetExe | Unblock-File } catch { }
$trustAppliedNow = $false
if ($TrustSelfSigned) {
    # Снимаем метку интернета со всех файлов папки распаковки: даже запуск
    # UUF.exe двойным кликом «из архива» после этого не показывает окно SmartScreen.
    $uufSourceDir = Split-Path -Parent $exeSourceFull
    foreach ($uufFile in @(Get-ChildItem -LiteralPath $uufSourceDir -File -ErrorAction SilentlyContinue)) {
        try { Unblock-File -LiteralPath $uufFile.FullName } catch { }
    }
    Write-Host 'Файлы папки распаковки разблокированы (метка интернета снята).'
    $certificateImported = $false
    foreach ($candidatePath in @($targetCertificatePath, (Join-Path (Split-Path -Parent $exeSourceFull) 'UUF-signing.cer'))) {
        if (-not [System.IO.File]::Exists($candidatePath)) { continue }
        $thumbprint = Get-InstalledCertificateThumbprint
        $already = $false
        if ($thumbprint) {
            $already = @(@(Get-ChildItem -CertStoreLocation 'Cert:\CurrentUser\TrustedPublisher' -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumbprint })).Count -gt 0
        }
        if ($already) { Write-Host 'Сертификат Hasberd уже в доверенных издателях.'; $certificateImported = $true; $trustAppliedNow = $true; break }
        $null = Import-Certificate -FilePath $candidatePath -CertStoreLocation 'Cert:\CurrentUser\Root'
        $null = Import-Certificate -FilePath $candidatePath -CertStoreLocation 'Cert:\CurrentUser\TrustedPublisher'
        Write-Host 'Сертификат издателя Hasberd добавлен в «Доверенные корневые» и «Доверенные издатели» текущего пользователя — предупреждение SmartScreen «Неизвестный издатель» для подписанных сборок уйдёт.'
        $certificateImported = $true
        $trustAppliedNow = $true
        break
    }
    if (-not $certificateImported) { Write-Host 'UUF-signing.cer не найден рядом с UUF.exe — доверьте сертификат вручную: двойной щелчок по .cer → Установить сертификат → Текущий пользователь → Доверенные корневые центры сертификации.' }
}

$signatureStatus = 'неизвестно'
try {
    $signature = Get-AuthenticodeSignature -FilePath $targetExe
    $signerName = ''
    if ($signature.SignerCertificate) { $signerName = ' — ' + $signature.SignerCertificate.Subject }
    $signatureStatus = [string]$signature.SignatureStatus + $signerName
    if ($signature.SignatureStatus -eq 'Valid') {
        Write-Host 'Подпись проверена: издатель Hasberd в доверенных на этом компьютере.'
    } elseif ($signature.SignatureStatus -eq 'NotSigned') {
        Write-Host 'Внимание: файл не подписан — это сборка до включения подписи. Скачайте свежий артефакт из GitHub Actions.'
    } elseif ($trustAppliedNow) {
        Write-Host 'Сертификат добавлен в доверенные; если окно SmartScreen для уже скачанного файла осталось, выполните: Unblock-File "' + $targetExe + '" и перезапустите браузер перед новой загрузкой.'
    } elseif ([System.IO.File]::Exists($targetCertificatePath)) {
        Write-Host 'Издатель не в доверенных. Решается одной командой: powershell -ExecutionPolicy Bypass -File "' + (Join-Path $targetDirectory 'Install-UUF.ps1') + '" -TrustSelfSigned — либо двойным щелчком по UUF-signing.cer → «Установить сертификат» → «Локальный компьютер» → «Доверенные корневые центры сертификации» (потребуются права администратора).'
    }
} catch { }

Write-Host ''
Write-Host ('Готово! UUF установлен: ' + $targetExe)
Write-Host ('Подпись exe: ' + $signatureStatus)
Write-Host ('Ярлык «' + $appName + '» лежит на рабочем столе и в меню «Пуск».')
Write-Host ('Данные (история, настройки, сейф, журнал): ' + $dataDirectory)
if ($Host.Name -eq 'ConsoleHost') { $null = Read-Host 'Нажмите Enter, чтобы закрыть окно' }
