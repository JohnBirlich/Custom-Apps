# Установка Universal Username Finder (Windows PowerShell 5.1+).
#
# Установщик сам проверяет зависимости (платформа .NET, Windows PowerShell, TLS),
# кладёт UUF.exe в %LOCALAPPDATA%\Programs\UniversalUsernameFinder, снимает метку
# интернета со всех файлов, добавляет сертификат издателя Hasberd в доверенные
# текущего пользователя (без администратора; отключение — ключ -NoTrust), создаёт
# ярлыки на рабочем столе и в меню «Пуск» и регистрирует программу в
# «Приложения и возможности», откуда её можно удалить одной кнопкой.
# Рядом с программой кладётся Uninstall-UUF.ps1 — программа полного удаления.
#
# Быстрый старт: двойной щелчок по Install-UUF.bat (или .ps1).
# Ручной запуск: powershell -ExecutionPolicy Bypass -File .\Install-UUF.ps1
# Быстрое удаление: powershell -ExecutionPolicy Bypass -File .\Install-UUF.ps1 -Uninstall

[CmdletBinding()]
param(
    [string]$ExePath = '',
    [switch]$Uninstall,
    [switch]$RemoveData,
    # Совместимость со старыми инструкциями: доверие сертификату теперь включено по умолчанию.
    [switch]$TrustSelfSigned,
    # Не добавлять UUF-signing.cer в доверенные (если доверяешь сертификат сам).
    [switch]$NoTrust,
    # Пропустить проверку .NET / PowerShell / TLS (не рекомендуется).
    [switch]$SkipDependencyCheck,
    # Без паузы в конце — для автоматизации и ярлыка удаления из «Приложений».
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$installerVersion = '2.9.3'

# --- Любая непройденная ошибка печатается в окно и ждёт Enter: двойной клик по .ps1 не должен закрывать PowerShell мгновенно.
trap {
    Write-Host ''
    Write-Host ('ОШИБКА: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Установка не завершена. Скопируй текст ошибки в чат — починим.' -ForegroundColor Yellow
    if (-not $Silent -and $Host.Name -eq 'ConsoleHost') { $null = Read-Host 'Нажмите Enter, чтобы закрыть окно' }
    exit 1
}

$installerDirectory = if ($PSScriptRoot) { [string]$PSScriptRoot } else { (Get-Location).Path }
$appName = 'Universal Username Finder'
$targetDirectory = Join-Path $env:LOCALAPPDATA 'Programs\UniversalUsernameFinder'
$targetExe = Join-Path $targetDirectory 'UUF.exe'
$targetCertificatePath = Join-Path $targetDirectory 'UUF-signing.cer'
$targetUninstaller = Join-Path $targetDirectory 'AppUninstaller.exe'
$targetUninstallerScript = Join-Path $targetDirectory 'Uninstall-UUF.ps1'
$dataDirectory = Join-Path $env:LOCALAPPDATA 'UniversalUsernameFinder'
$desktopDirectory = [Environment]::GetFolderPath('Desktop')
$programsDirectory = [Environment]::GetFolderPath('Programs')
$shortcutNames = @($appName + '.lnk', 'UniversalUsernameFinder.lnk')
$uninstallRegistryKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\UniversalUsernameFinder'
$powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Write-Step {
    param([string]$Text)
    Write-Host ('· ' + $Text)
}

function Request-ExitPause {
    if (-not $Silent -and $Host.Name -eq 'ConsoleHost') { $null = Read-Host 'Нажмите Enter, чтобы закрыть окно' }
}

function Get-UninstallerExeSource {
    foreach ($candidate in @((Join-Path $installerDirectory 'AppUninstaller.exe'), (Join-Path (Split-Path -Parent $installerDirectory) 'dist\AppUninstaller.exe'), (Join-Path $installerDirectory 'dist\AppUninstaller.exe'))) {
        if ([System.IO.File]::Exists($candidate)) { return $candidate }
    }
    return ''
}

function Get-UninstallerSource {
    foreach ($candidate in @((Join-Path $installerDirectory 'Uninstall-UUF.ps1'), (Join-Path $installerDirectory 'build\Uninstall-UUF.ps1'))) {
        if ([System.IO.File]::Exists($candidate)) { return $candidate }
    }
    return ''
}

function Test-UufDependencies {
    $problems = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $netRelease = 0
    try {
        $netKey = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
        if (Test-Path -LiteralPath $netKey) { $netRelease = [int](Get-ItemProperty -LiteralPath $netKey -Name Release).Release }
    } catch { }
    if ($netRelease -lt 394802) {
        $problems.Add('Нужен .NET Framework 4.6.2 или новее (в реестре найдено: ' + $netRelease + '). Установи .NET 4.8: https://dotnet.microsoft.com/download/dotnet-framework/net48')
    }
    $psVersionText = '0'
    try {
        $psKey = 'HKLM:\SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine'
        if (Test-Path -LiteralPath $psKey) { $psVersionText = [string](Get-ItemProperty -LiteralPath $psKey -Name PowerShellVersion).PowerShellVersion }
    } catch { }
    $psVersionValue = 0.0
    if ($psVersionText -match '^[0-9]+') { $psVersionValue = [double]$Matches[0] }
    if ($psVersionValue -lt 5) {
        $problems.Add('Нужна Windows PowerShell 5.1 (в системе: ' + $psVersionText + '). На Windows 7/8.1 установи WMF 5.1: https://www.microsoft.com/download/details.aspx?id=54616')
    }
    if (-not (Test-Path -LiteralPath $powershellPath)) {
        $problems.Add('Не найден ' + $powershellPath + ' — программа построена на Windows PowerShell и без него не запустится.')
    }
    $osBuild = 0
    try { $osBuild = [Environment]::OSVersion.Version.Build } catch { }
    if ($osBuild -gt 0 -and $osBuild -lt 10240) {
        $strongCrypto = 0
        try {
            $tlsKey = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
            if (Test-Path -LiteralPath $tlsKey) { $strongCrypto = [int](Get-ItemProperty -LiteralPath $tlsKey -Name SchUseStrongCrypto -ErrorAction SilentlyContinue).SchUseStrongCrypto }
        } catch { }
        if ($strongCrypto -ne 1) {
            $warnings.Add('Windows старше 10 и не включён TLS 1.2 для .NET: проверь сетевые проверки ников; при ошибках выполни от администратора: Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" -Name SchUseStrongCrypto -Value 1 (и то же для HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319) и перезагрузись.')
        }
    }
    $info = ('Зависимости: .NET Release={0} (нужно от 394802), PowerShell={1}' -f $netRelease, $psVersionText)
    return [pscustomobject]@{ Problems = @($problems); Warnings = @($warnings); Info = $info }
}

function Remove-InstallShortcuts {
    foreach ($directory in @($desktopDirectory, $programsDirectory)) {
        foreach ($shortcutName in $shortcutNames) {
            $shortcutPath = Join-Path $directory $shortcutName
            if ([System.IO.File]::Exists($shortcutPath)) {
                Remove-Item -LiteralPath $shortcutPath -Force
                Write-Step ('Ярлык удалён: ' + $shortcutPath)
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
        Write-Step ('Ярлык: ' + $shortcutPath)
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

function Add-CertificateTrust {
    param([string]$candidatePath)
    if (Get-Command Import-Certificate -ErrorAction SilentlyContinue) {
        $null = Import-Certificate -FilePath $candidatePath -CertStoreLocation 'Cert:\CurrentUser\Root'
        $null = Import-Certificate -FilePath $candidatePath -CertStoreLocation 'Cert:\CurrentUser\TrustedPublisher'
    } else {
        $null = & certutil.exe -addstore -user Root $candidatePath
        $null = & certutil.exe -addstore -user TrustedPublisher $candidatePath
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
        } catch { }
    }
    return $removed
}

function Remove-UufRegistryEntry {
    try {
        if (Test-Path -LiteralPath $uninstallRegistryKey) { Remove-Item -LiteralPath $uninstallRegistryKey -Recurse -Force }
        Write-Step 'Запись в «Приложения и возможности» удалена.'
    } catch { }
}

if ($Uninstall) {
    $uninstallerExe = ''
    if ([System.IO.File]::Exists($targetUninstaller)) { $uninstallerExe = $targetUninstaller }
    else { $uninstallerExe = Get-UninstallerExeSource }
    if ($uninstallerExe) {
        $uufUninstallArgs = @()
        if ([bool]$RemoveData) { $uufUninstallArgs += '-RemoveData' } else { $uufUninstallArgs += '-KeepData' }
        if ($Silent) { $uufUninstallArgs += '-Silent' }
        & $uninstallerExe @uufUninstallArgs
        exit $LASTEXITCODE
    }
    $uninstallerSource = Get-UninstallerSource
    if ($uninstallerSource) {
        & $uninstallerSource -KeepData:(-not [bool]$RemoveData) -Silent:$Silent
        exit $LASTEXITCODE
    }
    # --- Удаление без внешнего деинсталлятора (если он потерян): минимум — программа и ярлыки
    Stop-RunningApp
    Remove-InstallShortcuts
    Remove-UufRegistryEntry
    $thumbprint = Get-InstalledCertificateThumbprint
    if ($thumbprint) {
        $null = Remove-UufCertificateTrust
        Write-Step 'Доверие к сертификату Hasberd удалено из хранилища текущего пользователя.'
    }
    if ([System.IO.File]::Exists($targetExe)) {
        Remove-Item -LiteralPath $targetExe -Force
        Write-Step ('Программа удалена: ' + $targetExe)
    }
    if ($RemoveData -and [System.IO.Directory]::Exists($dataDirectory)) {
        Remove-Item -LiteralPath $dataDirectory -Recurse -Force
        Write-Step ('Данные удалены: ' + $dataDirectory)
    } elseif ([System.IO.Directory]::Exists($dataDirectory)) {
        Write-Host ('История, настройки и сейф сохранены: ' + $dataDirectory)
    }
    Request-ExitPause
    exit 0
}

if (-not $SkipDependencyCheck) {
    Write-Step 'Проверяю зависимости...'
    $dependencyCheck = Test-UufDependencies
    Write-Host ('  ' + $dependencyCheck.Info)
    foreach ($warning in $dependencyCheck.Warnings) { Write-Host ('  ВНИМАНИЕ: ' + $warning) -ForegroundColor Yellow }
    if ($dependencyCheck.Problems.Count -gt 0) {
        Write-Host ''
        Write-Host 'Установка прервана — не выполнены системные требования:' -ForegroundColor Red
        foreach ($problem in $dependencyCheck.Problems) { Write-Host ('  - ' + $problem) }
        Write-Host 'После установки недостающих компонентов повтори запуск. Проверку можно пропустить ключом -SkipDependencyCheck (на свой страх и риск).' -ForegroundColor Yellow
        Request-ExitPause
        exit 2
    }
}

if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $candidate = Join-Path $installerDirectory 'UUF.exe'
    if (-not [System.IO.File]::Exists($candidate)) { $candidate = Join-Path (Get-Location) 'UUF.exe' }
    $ExePath = $candidate
}
if (-not [System.IO.File]::Exists($ExePath)) {
    throw 'UUF.exe не найден рядом со скриптом установки. Распакуй архив UniversalUsernameFinder-windows в одну папку с Install-UUF.ps1 или укажи путь: -ExePath C:\путь\UUF.exe'
}

Stop-RunningApp
New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
$exeSourceFull = [System.IO.Path]::GetFullPath($ExePath)
Copy-Item -LiteralPath $exeSourceFull -Destination $targetExe -Force
$certificateSource = Join-Path (Split-Path -Parent $exeSourceFull) 'UUF-signing.cer'
if ([System.IO.File]::Exists($certificateSource)) {
    Copy-Item -LiteralPath $certificateSource -Destination $targetCertificatePath -Force
}

# --- Кладём программу полного удаления рядом с приложением: AppUninstaller.exe — основной вариант,
# Uninstall-UUF.ps1/.bat — резервный исходник на случай, если .exe будет заблокирован антивирусом.
$uninstallerExeSource = Get-UninstallerExeSource
if ($uninstallerExeSource) {
    Copy-Item -LiteralPath $uninstallerExeSource -Destination $targetUninstaller -Force
    Write-Step 'Программа полного удаления AppUninstaller.exe установлена рядом с UUF.exe.'
}
$uninstallerSource = Get-UninstallerSource
if ($uninstallerSource) {
    Copy-Item -LiteralPath $uninstallerSource -Destination $targetUninstallerScript -Force
    $uninstallerBatSource = $uninstallerSource -replace '\.ps1$','.bat'
    if ([System.IO.File]::Exists($uninstallerBatSource)) {
        Copy-Item -LiteralPath $uninstallerBatSource -Destination (Join-Path $targetDirectory 'Uninstall-UUF.bat') -Force
    }
}
if (-not [System.IO.File]::Exists($targetUninstaller) -and -not [System.IO.File]::Exists($targetUninstallerScript)) {
    Write-Host '  ВНИМАНИЕ: ни AppUninstaller.exe, ни Uninstall-UUF.ps1 не найдены рядом с установщиком — полное удаление доступно только командой -Uninstall.' -ForegroundColor Yellow
}

New-InstallShortcut -Directory $desktopDirectory
New-InstallShortcut -Directory $programsDirectory

# --- Метку интернета снимаем со всей папки установки и папки распаковки: иначе SmartScreen цепляет ярлыки и ручные запуски
foreach ($uufFile in @(Get-ChildItem -LiteralPath $targetDirectory -File -ErrorAction SilentlyContinue)) {
    try { Unblock-File -LiteralPath $uufFile.FullName } catch { }
}
foreach ($uufFile in @(Get-ChildItem -LiteralPath (Split-Path -Parent $exeSourceFull) -File -ErrorAction SilentlyContinue)) {
    try { Unblock-File -LiteralPath $uufFile.FullName } catch { }
}
Write-Step 'Метка интернета снята с файлов установки и папки распаковки.'

$trustAppliedNow = $false
if (-not $NoTrust) {
    $certificateImported = $false
    foreach ($candidatePath in @($targetCertificatePath, (Join-Path (Split-Path -Parent $exeSourceFull) 'UUF-signing.cer'))) {
        if (-not [System.IO.File]::Exists($candidatePath)) { continue }
        $thumbprint = Get-InstalledCertificateThumbprint
        $already = $false
        if ($thumbprint) {
            $already = @(@(Get-ChildItem -CertStoreLocation 'Cert:\CurrentUser\TrustedPublisher' -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumbprint })).Count -gt 0
        }
        if ($already) { Write-Step 'Сертификат Hasberd уже в доверенных издателях.'; $trustAppliedNow = $true; break }
        Add-CertificateTrust -candidatePath $candidatePath
        Write-Step 'Сертификат издателя Hasberd добавлен в «Доверенные корневые» и «Доверенные издатели» текущего пользователя — предупреждение SmartScreen «Неизвестный издатель» для подписанных сборок уйдёт.'
        $certificateImported = $true
        $trustAppliedNow = $true
        break
    }
    if (-not $certificateImported) { Write-Host '  UUF-signing.cer не найден рядом с UUF.exe — доверьте сертификат вручную: двойной щелчок по .cer → Установить сертификат → Текущий пользователь → Доверенные корневые центры сертификации.' -ForegroundColor Yellow }
} else {
    Write-Step 'Доверие сертификату пропущено (-NoTrust).'
}

# --- Регистрируем программу в «Приложения и возможности» (HKCU): удаление оттуда вызывает Uninstall-UUF.ps1
try {
    $displayVersion = $installerVersion
    try {
        $versionInfo = (Get-Item -LiteralPath $targetExe).VersionInfo
        if ($null -ne $versionInfo -and -not [string]::IsNullOrWhiteSpace([string]$versionInfo.FileVersion)) {
            $displayVersion = [string]$versionInfo.FileVersion
            if ($displayVersion -match '^([0-9]+(\.[0-9]+)+)') { $displayVersion = $Matches[1] }
        }
    } catch { }
    New-Item -Path $uninstallRegistryKey -Force | Out-Null
    $sizeBytes = 0L
    foreach ($installedFile in @(Get-ChildItem -LiteralPath $targetDirectory -File -ErrorAction SilentlyContinue)) { $sizeBytes += [int64]$installedFile.Length }
    $uninstallCommand = ''
    if ([System.IO.File]::Exists($targetUninstaller)) { $uninstallCommand = '"' + $targetUninstaller + '"' }
    elseif ([System.IO.File]::Exists($targetUninstallerScript)) { $uninstallCommand = '"' + $powershellPath + '" -NoProfile -ExecutionPolicy Bypass -File "' + $targetUninstallerScript + '"' }
    else { $uninstallCommand = '"' + $powershellPath + '" -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $targetDirectory 'Install-UUF.ps1') + '" -Uninstall -RemoveData' }
    Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name DisplayName -Value $appName
    Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name Publisher -Value 'Hasberd'
    Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name DisplayVersion -Value $displayVersion
    Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name InstallLocation -Value $targetDirectory
    Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name DisplayIcon -Value $targetExe
    Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name UninstallString -Value $uninstallCommand
        if ([System.IO.File]::Exists($targetUninstaller) -or [System.IO.File]::Exists($targetUninstallerScript)) {
        Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name QuietUninstallString -Value ($uninstallCommand + ' -Silent')
    } else {
        Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name QuietUninstallString -Value ($uninstallCommand + ' -RemoveData -Silent')
    }
    Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name NoRepair -Value 1 -Type DWord
    Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name EstimatedSize -Value ([int][Math]::Round($sizeBytes / 1KB))
    Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name HelpLink -Value 'https://github.com/JohnBirlich/Custom-Apps'
    Write-Step ('Записан в «Приложения и возможности» (версия ' + $displayVersion + ', издатель Hasberd).')
} catch {
    Write-Host ('  Не удалось зарегистрировать удаление в «Приложениях»: ' + $_.Exception.Message) -ForegroundColor Yellow
}

$signatureStatus = 'неизвестно'
try {
    $signature = Get-AuthenticodeSignature -FilePath $targetExe
    $signerName = ''
    if ($signature.SignerCertificate) { $signerName = ' — ' + $signature.SignerCertificate.Subject }
    $signatureStatus = [string]$signature.SignatureStatus + $signerName
    if ($signature.SignatureStatus -eq 'Valid') {
        Write-Step 'Подпись проверена: издатель Hasberd в доверенных на этом компьютере.'
    } elseif ($signature.SignatureStatus -eq 'NotSigned') {
        Write-Host 'Внимание: файл не подписан — это сборка до включения подписи. Скачайте свежий артефакт из GitHub Actions.' -ForegroundColor Yellow
    } elseif ($trustAppliedNow) {
        Write-Step 'Сертификат добавлен в доверенные; если окно SmartScreen для уже скачанного файла осталось, выполните: Unblock-File "' + $targetExe + '" и перезапустите браузер перед новой загрузкой.'
    } elseif ([System.IO.File]::Exists($targetCertificatePath)) {
        Write-Host ('Издатель не в доверенных. Решается одной командой: powershell -ExecutionPolicy Bypass -File "' + (Join-Path $targetDirectory 'Install-UUF.ps1') + '" -TrustSelfSigned — либо двойным щелчком по UUF-signing.cer → «Установить сертификат» → «Локальный компьютер» → «Доверенные корневые центры сертификации» (потребуются права администратора).') -ForegroundColor Yellow
    }
} catch { }

Write-Host ''
Write-Host ('Готово! UUF установлен: ' + $targetExe)
Write-Host ('Подпись exe: ' + $signatureStatus)
Write-Host ('Ярлык «' + $appName + '» лежит на рабочем столе и в меню «Пуск».')
Write-Host ('Данные (история, настройки, сейф, журнал): ' + $dataDirectory)
$uninstallerHint = 'AppUninstaller.exe'
if (-not [System.IO.File]::Exists($targetUninstaller)) { $uninstallerHint = 'Uninstall-UUF.bat' }
Write-Host ('Полное удаление: двойным щелчком по «' + (Join-Path $targetDirectory $uninstallerHint) + '» или через «Приложения и возможности» → Universal Username Finder → Удалить.')
Request-ExitPause
exit 0
