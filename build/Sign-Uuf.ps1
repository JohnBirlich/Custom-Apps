# Подписание UUF.exe сертификатом Authenticode (signtool, SHA-256 + метка времени).
#
# Два режима:
#   1. Боевой сертификат: PFX из -PfxPath либо из переменной окружения
#      UUF_SIGN_PFX_BASE64 (пароль — UUF_SIGN_PFX_PASSWORD). В GitHub Actions
#      секреты называются так же. Только подпись центром доверия снимает у
#      SmartScreen статус «неизвестный издатель» и заметно глушит ML-эвристики
#      антивирусов.
#   2. -SelfSign: если PFX нет, в текущем профиле создаётся (или переиспользуется)
#      самоподписанный сертификат CN=Hasberb; публичный ключ экспортируется рядом
#      с exe в UUF-signing.cer — пользователь может добавить его в доверенные,
#      чтобы подпись его машины считалась валидной.
#
# Если signtool.exe (Windows SDK) не найден, скрипт предупреждает и выходит с
# кодом 0: сборка не должна зависеть от наличия SDK.
#
# Запуск:  powershell -ExecutionPolicy Bypass -File build\Sign-Uuf.ps1 [-SelfSign]

[CmdletBinding()]
param(
    # Подписываемый файл. По умолчанию — dist\UUF.exe в корне репозитория.
    [string]$ExePath = '',
    # Файл PFX с боевым сертификатом подписи кода.
    [string]$PfxPath = '',
    # Идентичность самоподписанного сертификата.
    [string]$Subject = 'CN=Hasberb',
    # Сервер метки времени RFC 3161; при недоступности подпись ставится без неё.
    [string]$TimestampUrl = 'http://timestamp.digicert.com',
    # Разрешить сгенерировать самоподписанный сертификат, если PFX не задан.
    [switch]$SelfSign
)

$ErrorActionPreference = 'Stop'

function Find-SignTool {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return [string]$cmd.Source }
    $roots = @('C:\Program Files (x86)\Windows Kits\10\bin', 'C:\Program Files\Windows Kits\10\bin')
    foreach ($root in $roots) {
        if (-not [System.IO.Directory]::Exists($root)) { continue }
        $found = @(Get-ChildItem -Path $root -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\x64\\' })
        if ($found.Count -gt 0) {
            $pick = $null
            try { $pick = @($found | Sort-Object { [version]$_.Directory.Parent.Parent.Name })[-1] } catch { $pick = $found[0] }
            return [string]$pick.FullName
        }
    }
    return $null
}

if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $scriptDirectory = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($scriptDirectory)) { $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $ExePath = Join-Path (Split-Path -Parent $scriptDirectory) 'dist\UUF.exe'
}
if (-not [System.IO.File]::Exists($ExePath)) {
    throw ('Подписываемый файл не найден: ' + $ExePath)
}
$exeFull = [System.IO.Path]::GetFullPath($ExePath)
$distDirectory = [System.IO.Path]::GetDirectoryName($exeFull)

$signtool = Find-SignTool
if (-not $signtool) {
    Write-Host '::warning::signtool.exe не найден (нужен Windows SDK); UUF.exe остаётся неподписанным.'
    return
}

$tempPfx = $null
$pfxPlainPassword = $env:UUF_SIGN_PFX_PASSWORD
try {
    if ([string]::IsNullOrWhiteSpace($PfxPath) -and -not [string]::IsNullOrWhiteSpace($env:UUF_SIGN_PFX_BASE64)) {
        $tempPfx = Join-Path $env:TEMP ('uuf-sign-' + [guid]::NewGuid().ToString('N') + '.pfx')
        [System.IO.File]::WriteAllBytes($tempPfx, [System.Convert]::FromBase64String($env:UUF_SIGN_PFX_BASE64.Trim()))
        $PfxPath = $tempPfx
        Write-Host 'Сертификат подписи получен из секрета UUF_SIGN_PFX_BASE64.'
    }
    if ([string]::IsNullOrWhiteSpace($PfxPath) -and $SelfSign) {
        $securePassword = ConvertTo-SecureString -String ([guid]::NewGuid().ToString('N')) -Force
        $pfxPlainPassword = $null
        $certificate = $null
        $existing = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq $Subject -and $_.NotAfter -gt (Get-Date) })
        if ($existing.Count -gt 0) {
            $certificate = @($existing | Sort-Object NotAfter)[-1]
            Write-Host ('Переиспользован самоподписанный сертификат: ' + $certificate.Thumbprint)
        } else {
            $certificate = New-SelfSignedCertificate -Subject $Subject -Type CodeSigningCert -CertStoreLocation Cert:\CurrentUser\My -HashAlgorithm SHA256 -KeyLength 3072 -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(3)
            Write-Host ('Создан самоподписанный сертификат: ' + $certificate.Thumbprint)
        }
        $tempPfx = Join-Path $env:TEMP ('uuf-sign-' + [guid]::NewGuid().ToString('N') + '.pfx')
        $null = Export-PfxCertificate -Cert $certificate.PSPath -FilePath $tempPfx -Password $securePassword
        $PfxPath = $tempPfx
        $cerPath = Join-Path $distDirectory 'UUF-signing.cer'
        $null = Export-Certificate -Cert $certificate.PSPath -FilePath $cerPath
        Write-Host ('Публичный ключ сертификата: ' + $cerPath)
    }
    if ([string]::IsNullOrWhiteSpace($PfxPath)) {
        Write-Host '::warning::Нет сертификата подписи (секрет UUF_SIGN_PFX_BASE64 или ключ -SelfSign); UUF.exe остаётся неподписанным.'
        return
    }
    $signArgs = @('sign', '/fd', 'SHA256', '/f', $PfxPath)
    if (-not [string]::IsNullOrWhiteSpace($pfxPlainPassword)) { $signArgs += @('/p', $pfxPlainPassword) }
    $signArgs += @('/d', 'Universal Username Finder', '/tr', $TimestampUrl, '/td', 'SHA256', $exeFull)
    & $signtool @signArgs | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host '::warning::Подпись с меткой времени не удалась; повторяю без метки времени.'
        $retryArgs = @('sign', '/fd', 'SHA256', '/f', $PfxPath)
        if (-not [string]::IsNullOrWhiteSpace($pfxPlainPassword)) { $retryArgs += @('/p', $pfxPlainPassword) }
        $retryArgs += @('/d', 'Universal Username Finder', $exeFull)
        & $signtool @retryArgs | Out-Host
        if ($LASTEXITCODE -ne 0) { throw ('signtool завершился с кодом ' + $LASTEXITCODE) }
    }
    $signature = Get-AuthenticodeSignature -FilePath $exeFull
    $signer = 'нет данных'
    if ($signature.SignerCertificate) { $signer = $signature.SignerCertificate.Subject + ' [' + $signature.SignerCertificate.Thumbprint + ']' }
    Write-Host ('Подпись: ' + $signature.SignatureStatus + '; издатель: ' + $signer)
    if (-not $signature.SignerCertificate) { throw 'signtool завершился без ошибок, но подпись не обнаружена' }
    if ($signature.SignatureStatus -ne 'Valid') {
        Write-Host 'Справка: статус не Valid ожидаем для самоподписанного сертификата — файл целостен, но издатель не в списке доверенных на этой машине.'
    }
} finally {
    if ($tempPfx -and [System.IO.File]::Exists($tempPfx)) {
        try { Remove-Item -LiteralPath $tempPfx -Force } catch { }
    }
}
