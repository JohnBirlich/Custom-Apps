
[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'

$buildDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($buildDirectory)) { $buildDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path }
$repositoryRoot = Split-Path -Parent $buildDirectory
$scriptPath = Join-Path $repositoryRoot 'UniversalUsernameFinder.ps1'
$launcherPath = Join-Path $repositoryRoot 'launcher\UUF.Launcher.cs'

if (-not [System.IO.File]::Exists($scriptPath)) {
    throw ('Не найден исходный скрипт: ' + $scriptPath)
}
if (-not [System.IO.File]::Exists($launcherPath)) {
    throw ('Не найден исходный код лаунчера: ' + $launcherPath)
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

$cscPath = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not [System.IO.File]::Exists($cscPath)) {
    throw ('Не найден компилятор C# (csc.exe): ' + $cscPath)
}

$smaRoot = Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation'
$smaDll = Get-ChildItem -LiteralPath $smaRoot -Recurse -Filter 'System.Management.Automation.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $smaDll) {
    throw ('Не найдена сборка System.Management.Automation (Windows PowerShell 5.1): ' + $smaRoot)
}

Write-Host ('Репозиторий:      ' + $repositoryRoot)
Write-Host ('Исходный скрипт:  ' + $scriptPath)
Write-Host ('Версия:           ' + $appVersion + ' (файл: ' + $fileVersion + ')')
Write-Host ('Компилятор:       ' + $cscPath)
Write-Host ('Результат:        ' + $outputPath)

if ([System.IO.File]::Exists($outputPath)) {
    try { [System.IO.File]::Delete($outputPath) } catch { }
}

$iconFile = Join-Path $repositoryRoot 'assets\uuf.ico'
$videoSourcePath = Join-Path $repositoryRoot 'assets\digital_word_eye.mp4'
$embeddedText = $scriptText
$videoEmbedded = $false
if ([System.IO.File]::Exists($videoSourcePath)) {
    $videoBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($videoSourcePath))
    $chunkSize = 500000
    $chunks = New-Object System.Collections.Generic.List[string]
    for ($offset = 0; $offset -lt $videoBase64.Length; $offset += $chunkSize) {
        $length = [Math]::Min($chunkSize, $videoBase64.Length - $offset)
        $chunks.Add("'" + $videoBase64.Substring($offset, $length) + "'")
    }
    $placeholder = '$script:EmbeddedVideoParts = @()'
    if (-not $scriptText.Contains($placeholder)) {
        throw 'В UniversalUsernameFinder.ps1 не найдена метка для встраивания видео'
    }
    $replacement = '$script:EmbeddedVideoParts = @(' + [string]::Join(',' + [Environment]::NewLine, $chunks) + ')'
    $embeddedText = $scriptText.Replace($placeholder, $replacement)
    $videoEmbedded = $true
    Write-Host ('Видео встраивается в exe: ' + ([System.IO.FileInfo]$videoSourcePath).Length + ' байт')
}

$workDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('uuf-embedded-' + [guid]::NewGuid().ToString('N'))
$null = [System.IO.Directory]::CreateDirectory($workDirectory)
$embeddedScriptPath = Join-Path $workDirectory 'UniversalUsernameFinder.ps1'
$assemblyInfoPath = Join-Path $workDirectory 'AssemblyInfo.cs'

$utf8Bom = New-Object System.Text.UTF8Encoding -ArgumentList $true
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[System.IO.File]::WriteAllText($embeddedScriptPath, $embeddedText, $utf8Bom)

$exeMetadata = @{
    title       = 'Universal Username Finder'
    description = 'Генератор никнеймов и проверка доступности на платформах и в Telegram-каналах'
    product     = 'Universal Username Finder'
    copyright   = 'GPL-3.0-or-later'
    company     = 'Hasberd'
}

$assemblyInfo = @(
    'using System.Reflection;',
    ('[assembly: AssemblyTitle("' + $exeMetadata.title + '")]'),
    ('[assembly: AssemblyDescription("' + $exeMetadata.description + '")]'),
    ('[assembly: AssemblyProduct("' + $exeMetadata.product + '")]'),
    ('[assembly: AssemblyCompany("' + $exeMetadata.company + '")]'),
    ('[assembly: AssemblyCopyright("' + $exeMetadata.copyright + '")]'),
    ('[assembly: AssemblyVersion("' + $fileVersion + '")]'),
    ('[assembly: AssemblyFileVersion("' + $fileVersion + '")]')
) -join [Environment]::NewLine
[System.IO.File]::WriteAllText($assemblyInfoPath, $assemblyInfo, $utf8NoBom)

$compilerArguments = @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    '/platform:anycpu',
    ('/reference:' + $smaDll.FullName),
    ('/out:' + $outputPath),
    ('/win32icon:' + $iconFile),
    ('/resource:' + $embeddedScriptPath + ',UniversalUsernameFinder.ps1'),
    $launcherPath,
    $assemblyInfoPath
)

try {
    $compilerOutput = @(& $cscPath @compilerArguments 2>&1 | ForEach-Object { [string]$_ })
    foreach ($line in $compilerOutput) { Write-Host $line }
    if ($LASTEXITCODE -ne 0) {
        throw ('csc.exe завершился с кодом ' + $LASTEXITCODE + ': ' + (($compilerOutput | Select-Object -Last 8) -join ' | '))
    }
} finally {
    if ([System.IO.Directory]::Exists($workDirectory)) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force
    }
}

if (-not [System.IO.File]::Exists($outputPath)) {
    throw ('Сборка завершилась без результата: файл не создан (' + $outputPath + ')')
}

$sizeKb = [int][Math]::Round(([System.IO.FileInfo]$outputPath).Length / 1KB)
if ($videoEmbedded -and $sizeKb -lt 8000) {
    throw ('Видео не вшилось в exe: размер ' + $sizeKb + ' КБ')
}
if ($sizeKb -lt 20) {
    throw ('Собранный файл подозрительно мал (' + $sizeKb + ' КБ): вероятно, сборка прошла некорректно')
}

$signScript = Join-Path $buildDirectory 'Sign-Uuf.ps1'
if ([System.IO.File]::Exists($signScript)) {
    & $signScript -ExePath $outputPath
}

$videoSource = Join-Path $repositoryRoot 'assets\digital_word_eye.mp4'
if ([System.IO.File]::Exists($videoSource)) {
    Copy-Item -LiteralPath $videoSource -Destination (Join-Path $OutputDirectory 'digital_word_eye.mp4') -Force
}

Write-Host ''
Write-Host ('Готово: ' + $outputPath + ' (' + $sizeKb + ' КБ)')
Write-Host 'Важно: скрипт приложения лежит в ресурсах exe в открытом виде.'
Write-Host 'Это удобная оболочка для запуска, а не защита кода.'
return $outputPath
