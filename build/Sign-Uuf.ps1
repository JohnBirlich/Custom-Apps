

[CmdletBinding()]
param(
    [string]$ExePath = '',
    [string]$PfxPath = '',
    [string]$Subject = 'CN=Hasberd',
    [string]$TimestampUrl = 'http://timestamp.digicert.com',
    [switch]$SelfSign,
    [string[]]$ExtraExePaths = @()
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
$certGeneratedInMemory = $false
try {
    if ([string]::IsNullOrWhiteSpace($PfxPath) -and -not [string]::IsNullOrWhiteSpace($env:UUF_SIGN_PFX_BASE64)) {
        $tempPfx = Join-Path $env:TEMP ('uuf-sign-' + [guid]::NewGuid().ToString('N') + '.pfx')
        [System.IO.File]::WriteAllBytes($tempPfx, [System.Convert]::FromBase64String($env:UUF_SIGN_PFX_BASE64.Trim()))
        $PfxPath = $tempPfx
        Write-Host 'Сертификат подписи получен из секрета UUF_SIGN_PFX_BASE64.'
    }
    if ([string]::IsNullOrWhiteSpace($PfxPath) -and $SelfSign) {
        $selfPassword = [guid]::NewGuid().ToString('N')
        $tempPfx = Join-Path $env:TEMP ('uuf-sign-' + [guid]::NewGuid().ToString('N') + '.pfx')
        $rsaKey = [System.Security.Cryptography.RSA]::Create(3072)
        $dnType = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]
        $requestType = [System.Security.Cryptography.X509Certificates.CertificateRequest]
        $hashSha256 = [System.Security.Cryptography.HashAlgorithmName]::SHA256
        $paddingPkcs1 = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        $distinguishedName = $dnType::new($Subject)
        $request = $requestType::new($distinguishedName, $rsaKey, $hashSha256, $paddingPkcs1)
        $keyUsage = [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new([System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature, $true)
        $request.CertificateExtensions.Add($keyUsage)
        $ekuOids = [System.Security.Cryptography.OidCollection]::new()
        $null = $ekuOids.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
        $eku = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($ekuOids, $false)
        $request.CertificateExtensions.Add($eku)
        $certificate = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1), [DateTimeOffset]::UtcNow.AddYears(3))
        $pfxBytes = $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $selfPassword)
        [System.IO.File]::WriteAllBytes($tempPfx, $pfxBytes)
        $PfxPath = $tempPfx
        $pfxPlainPassword = $selfPassword
        $cerPath = Join-Path $distDirectory 'UUF-signing.cer'
        [System.IO.File]::WriteAllBytes($cerPath, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
        $certGeneratedInMemory = $true
        Write-Host ('Самоподписанный сертификат: ' + $certificate.Thumbprint + '; публичный ключ: ' + $cerPath)
        $certificate.Dispose()
        $rsaKey.Dispose()
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
    foreach ($extraPath in @($ExtraExePaths)) {
        $extraFull = ''
        try { $extraFull = [System.IO.Path]::GetFullPath([string]$extraPath) } catch { }
        if (-not $extraFull -or -not [System.IO.File]::Exists($extraFull)) {
            Write-Host ('::warning::Дополнительный файл для подписи не найден: ' + $extraPath)
            continue
        }
        $extraArgs = @('sign', '/fd', 'SHA256', '/f', $PfxPath)
        if (-not [string]::IsNullOrWhiteSpace($pfxPlainPassword)) { $extraArgs += @('/p', $pfxPlainPassword) }
        $extraArgs += @('/d', 'Universal Username Finder', '/tr', $TimestampUrl, '/td', 'SHA256', $extraFull)
        & $signtool @extraArgs | Out-Host
        if ($LASTEXITCODE -ne 0) {
            $extraRetry = @('sign', '/fd', 'SHA256', '/f', $PfxPath)
            if (-not [string]::IsNullOrWhiteSpace($pfxPlainPassword)) { $extraRetry += @('/p', $pfxPlainPassword) }
            $extraRetry += @('/d', 'Universal Username Finder', $extraFull)
            & $signtool @extraRetry | Out-Host
            if ($LASTEXITCODE -ne 0) { throw ('signtool для ' + $extraFull + ' завершился с кодом ' + $LASTEXITCODE) }
        }
        $extraSignature = Get-AuthenticodeSignature -FilePath $extraFull
        Write-Host ('Дополнительная подпись: ' + [System.IO.Path]::GetFileName($extraFull) + ' — ' + $extraSignature.SignatureStatus)
    }
    $cerPath = Join-Path $distDirectory 'UUF-signing.cer'
    if (-not $certGeneratedInMemory) {
        try {
            $pfxPasswordForExport = ''
            if ($pfxPlainPassword) { $pfxPasswordForExport = [string]$pfxPlainPassword }
            $storageFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
            $signerCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($PfxPath, $pfxPasswordForExport, $storageFlags)
            [System.IO.File]::WriteAllBytes($cerPath, $signerCertificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            $signerCertificate.Dispose()
            Write-Host ('Публичный ключ подписанта: ' + $cerPath)
        } catch {
            Write-Host ('::warning::Публичный ключ подписанта экспортировать не удалось: ' + $_.Exception.Message)
        }
    }
} finally {
    if ($tempPfx -and [System.IO.File]::Exists($tempPfx)) {
        try { Remove-Item -LiteralPath $tempPfx -Force } catch { }
    }
}
