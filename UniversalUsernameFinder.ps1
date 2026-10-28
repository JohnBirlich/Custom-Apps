$ErrorActionPreference = 'Stop'
# --- Шрифт интерфейса: Tahoma (шрифт Windows XP, есть в любой версии Windows)
$script:UiFontFamily = 'Tahoma'
$script:AppVersion = '2.10.6'

trap {
    $trapMessage = $_.Exception.Message
    $trapPosition = ''
    try { $trapPosition = [string]$_.InvocationInfo.PositionMessage } catch { }
    try {
        $trapLine = '[{0}] Необработанная ошибка запуска: {1}{2}{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.ToString(), $trapPosition, [Environment]::NewLine
        $trapPath = if ($script:LogPath) { [string]$script:LogPath } else { Join-Path ([System.AppDomain]::CurrentDomain.BaseDirectory) 'UniversalUsernameFinder.log' }
        [System.IO.File]::AppendAllText($trapPath, $trapLine, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
    } catch { }
    try {
        $trapShown = ('Приложение завершилось из-за ошибки:`r`n`r`n{0}`r`n`r`n{1}`r`n`r`nПодробности: UniversalUsernameFinder.log' -f $trapMessage, $trapPosition)
        if ($trapShown.Length -gt 900) { $trapShown = $trapShown.Substring(0, 900) }
        try { $null = $Host.UI.RawUI.FlushInputBuffer() } catch { }
        [System.Windows.Forms.MessageBox]::Show($trapShown, 'UUF: ошибка запуска', 'OK', 'Error') | Out-Null
    } catch { }
    exit 1
}

function Get-AppDirectory {
    $candidate = ''
    try { $candidate = [string]$ScriptRoot } catch { }
    if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = [string]$PSScriptRoot }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        try { $candidate = [string][System.AppDomain]::CurrentDomain.BaseDirectory } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = [string](Get-Location).Path }
    return $candidate
}

function Resolve-LogPath {
    # --- Журнал пишется в %LOCALAPPDATA%\UniversalUsernameFinder, где его не затирает сборка; папка программы — portable-резерв
    $primary = Join-Path (Get-AppDirectory) 'UniversalUsernameFinder.log'
    try {
        $preferredDirectory = Join-Path $env:LOCALAPPDATA 'UniversalUsernameFinder'
        $null = [System.IO.Directory]::CreateDirectory($preferredDirectory)
        $probe = Join-Path $preferredDirectory ('.uuf-write-probe-' + [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($probe, 'probe')
        [System.IO.File]::Delete($probe)
        return (Join-Path $preferredDirectory 'UniversalUsernameFinder.log')
    } catch { }
    try {
        $directory = Split-Path -Parent $primary
        $probe = Join-Path $directory ('.uuf-write-probe-' + [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($probe, 'probe')
        [System.IO.File]::Delete($probe)
        return $primary
    } catch {
        return $primary
    }
}

function Rotate-AppLog {
    param([long]$MaxBytes = 2097152)
    try {
        $info = New-Object System.IO.FileInfo($script:LogPath)
        if ($info.Exists -and $info.Length -gt $MaxBytes) {
            $old = [System.IO.Path]::ChangeExtension($script:LogPath, '.old.log')
            if ([System.IO.File]::Exists($old)) { [System.IO.File]::Delete($old) }
            [System.IO.File]::Move($script:LogPath, $old)
        }
    } catch { }
}

# --- Журнал и стартовая диагностика
$script:LogPath = Resolve-LogPath
Rotate-AppLog

# --- Статус подписи запускаемого файла: по таким строкам в журнале видно, собрана ли подпись и доверен ли издатель
try {
    $uufSelfPath = [string]([Environment]::GetCommandLineArgs()[0])
    if ($uufSelfPath -and (Test-Path -LiteralPath $uufSelfPath) -and ($uufSelfPath -notmatch '(?i)\\(powershell(_ise)?|pwsh)(\.cat)?(\.exe)?$')) {
        $uufSelfSig = Get-AuthenticodeSignature -FilePath $uufSelfPath -ErrorAction SilentlyContinue
        $uufSelfSigner = 'нет данных о подписи'
        if ($uufSelfSig.SignerCertificate) { $uufSelfSigner = [string]$uufSelfSig.SignerCertificate.Subject }
        Write-StartupLog ('Подпись: ' + [string]$uufSelfSig.SignatureStatus + ' — ' + $uufSelfSigner)
    } else {
        Write-StartupLog 'Подпись: пропуск (запуск из powershell/pwsh — подписывать нечего)'
    }
} catch { }

Add-Type -AssemblyName System.Security
$script:VaultDirectory = Join-Path $env:LOCALAPPDATA 'UniversalUsernameFinder'
$script:VaultPath = Join-Path $script:VaultDirectory 'accounts.dat'
$script:LegacyVaultDirectory = Join-Path $env:LOCALAPPDATA 'RobloxNickFinder'
$script:LegacyVaultPath = Join-Path $script:LegacyVaultDirectory 'accounts.dat'
$script:VaultEntropy = [System.Text.Encoding]::UTF8.GetBytes('RobloxNickFinder:account-vault:v1')
$script:PasswordRng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::DefaultConnectionLimit = 10

$script:SingleInstanceMutex = $null
try {
    $createdNew = $false
    $script:SingleInstanceMutex = New-Object System.Threading.Mutex($true, 'Local\UniversalUsernameFinder.SingleInstance', [ref]$createdNew)
    if (-not $createdNew) {
        try { $null = $Host.UI.RawUI.FlushInputBuffer() } catch { }
        [System.Windows.Forms.MessageBox]::Show('Universal Username Finder уже запущен. Второе окно не открыто, чтобы не повредить историю ников и зашифрованное хранилище. Если окно не находится, завершите процесс UUF или UniversalUsernameFinder в Диспетчере задач.','Приложение уже запущено','OK','Information','Button1','DefaultDesktopOnly') | Out-Null
        exit 0
    }
} catch {
    try {
        $line = '[{0}] {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), ('Не удалось создать Mutex единственного экземпляра: ' + $_.Exception.Message), [Environment]::NewLine
        [System.IO.File]::AppendAllText($script:LogPath, $line, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
    } catch { }
}

function Write-StartupLog {
    param([string]$Message)
    try {
        $logPath = $script:LogPath
        if ([string]::IsNullOrWhiteSpace($logPath)) { $logPath = Join-Path (Get-AppDirectory) 'UniversalUsernameFinder.log' }
        $line = '[{0}] {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message, [Environment]::NewLine
        [System.IO.File]::AppendAllText($logPath, $line, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
    } catch { }
}

function Migrate-LegacyVault {
    try {
        if (-not [System.IO.File]::Exists($script:LegacyVaultPath)) { return }
        if ([System.IO.File]::Exists($script:VaultPath)) { return }
        $null = [System.IO.Directory]::CreateDirectory($script:VaultDirectory)
        [System.IO.File]::Copy($script:LegacyVaultPath, $script:VaultPath, $false)
        try { [System.IO.File]::Move($script:LegacyVaultPath, ($script:LegacyVaultPath + '.migrated')) } catch { }
        Write-StartupLog 'Хранилище аккаунтов перенесено из папки RobloxNickFinder в UniversalUsernameFinder.'
    } catch {
        Write-StartupLog ('Не удалось перенести хранилище аккаунтов из старой папки: ' + $_.Exception.Message)
    }
}
Migrate-LegacyVault

function Show-FatalError {
    param([string]$Title, [string]$Message)
    try { [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', 'Error') | Out-Null } catch { }
}

try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::Add_ThreadException({
        param($sender, $e)
        $detail = 'неизвестная ошибка интерфейса'
        try { $detail = [string]$e.Exception } catch { }
        Write-StartupLog ('Необработанное исключение интерфейса: ' + $detail)
        Show-FatalError 'Ошибка интерфейса' ("Произошла непредвиденная ошибка:`r`n`r`n{0}`r`n`r`nПодробности записаны в UniversalUsernameFinder.log. Приложение продолжает работу." -f $detail)
    })
    [System.AppDomain]::CurrentDomain.add_UnhandledException({
        param($sender, $e)
        $detail = 'неизвестная ошибка'
        try { $detail = [string]$e.ExceptionObject } catch { }
        Write-StartupLog ('Критическое необработанное исключение: ' + $detail)
        if ($e.IsTerminating) {
            Show-FatalError 'Критическая ошибка' ("Приложение будет закрыто:`r`n`r`n{0}`r`n`r`nПодробности: UniversalUsernameFinder.log" -f $detail)
        }
    })
} catch {
    Write-StartupLog ('Не удалось зарегистрировать обработчики необработанных исключений: ' + $_.Exception.Message)
}

$script:AppSeeds = @(
    @{Word='Discord'; Meaning='приложение для общения'}, @{Word='Spotify'; Meaning='музыкальный сервис'}, @{Word='Steam'; Meaning='игровая платформа'},
    @{Word='Twitch'; Meaning='стриминг игр'}, @{Word='YouTube'; Meaning='видеоплатформа'}, @{Word='TikTok'; Meaning='короткие видео'},
    @{Word='Netflix'; Meaning='стриминг фильмов'}, @{Word='Nvidia'; Meaning='графика и технологии'}, @{Word='Xbox'; Meaning='игровая консоль'},
    @{Word='PlayStation'; Meaning='игровая консоль'}, @{Word='Minecraft'; Meaning='песочница и крафт'}, @{Word='Telegram'; Meaning='мессенджер'},
    @{Word='Reddit'; Meaning='форумы и сообщества'}, @{Word='GitHub'; Meaning='код и разработка'}, @{Word='Google'; Meaning='поиск и технологии'},
    @{Word='Chrome'; Meaning='веб-браузер'}, @{Word='Firefox'; Meaning='веб-браузер'}, @{Word='Notion'; Meaning='заметки и организация'},
    @{Word='Figma'; Meaning='дизайн интерфейсов'}, @{Word='Blender'; Meaning='3D-графика'}, @{Word='Unity'; Meaning='игровой движок'},
    @{Word='Unreal'; Meaning='игровой движок'}, @{Word='Canva'; Meaning='графический дизайн'}, @{Word='CapCut'; Meaning='видеомонтаж'},
    @{Word='Duolingo'; Meaning='изучение языков'}, @{Word='Valorant'; Meaning='тактический шутер'}, @{Word='Fortnite'; Meaning='королевская битва'},
    @{Word='Terraria'; Meaning='приключения и строительство'}, @{Word='WhatsApp'; Meaning='мессенджер'}, @{Word='Pinterest'; Meaning='идеи и изображения'},
    @{Word='Snapchat'; Meaning='социальное приложение'}, @{Word='SoundCloud'; Meaning='музыкальная платформа'}, @{Word='Opera'; Meaning='веб-браузер'},
    @{Word='Epic'; Meaning='игровой издатель'}, @{Word='Razer'; Meaning='игровые устройства'}, @{Word='Asus'; Meaning='компьютерная техника'},
    @{Word='Apple'; Meaning='технологический бренд'}, @{Word='Android'; Meaning='мобильная платформа'}, @{Word='Adobe'; Meaning='творческие приложения'}
)
$script:MeaningSeeds = @(
    @{Word='Aurora'; Meaning='полярное сияние'}, @{Word='Ember'; Meaning='тлеющий уголёк'}, @{Word='Echo'; Meaning='эхо, отражённый звук'},
    @{Word='Haven'; Meaning='тихое безопасное место'}, @{Word='Onyx'; Meaning='чёрный драгоценный камень'}, @{Word='Solstice'; Meaning='солнцестояние'},
    @{Word='Nimbus'; Meaning='светящееся облако или облачный ореол'}, @{Word='Zephyr'; Meaning='лёгкий западный ветер'}, @{Word='Aether'; Meaning='эфир, небесная стихия'},
    @{Word='Rune'; Meaning='древний символ'}, @{Word='Atlas'; Meaning='атлас или титан из мифов'}, @{Word='Nyx'; Meaning='ночь в греческой мифологии'},
    @{Word='Lyra'; Meaning='созвездие Лиры'}, @{Word='Orion'; Meaning='созвездие Ориона'}, @{Word='Phoenix'; Meaning='феникс, возрождение'},
    @{Word='Vortex'; Meaning='водоворот или вихрь'}, @{Word='Cipher'; Meaning='шифр, тайный код'}, @{Word='Flux'; Meaning='поток, постоянное изменение'},
    @{Word='Frost'; Meaning='мороз, иней'}, @{Word='Blaze'; Meaning='яркое пламя'}, @{Word='Raven'; Meaning='ворон'},
    @{Word='Sage'; Meaning='мудрец'}, @{Word='Wisp'; Meaning='тонкий след или огонёк'}, @{Word='Drift'; Meaning='дрейф, плавное движение'},
    @{Word='Dusk'; Meaning='сумерки'}, @{Word='Dawn'; Meaning='рассвет'}, @{Word='Shadow'; Meaning='тень'},
    @{Word='Cobalt'; Meaning='кобальтовый синий цвет'}, @{Word='Quartz'; Meaning='кварц'}, @{Word='Nova'; Meaning='вспышка новой звезды'},
    @{Word='Pulse'; Meaning='пульс, ритм'}, @{Word='Pixel'; Meaning='пиксель, элемент изображения'}, @{Word='Orbit'; Meaning='орбита'},
    @{Word='Comet'; Meaning='комета'}, @{Word='Stellar'; Meaning='звёздный'}, @{Word='Lunar'; Meaning='лунный'},
    @{Word='Solar'; Meaning='солнечный'}, @{Word='Mystic'; Meaning='таинственный'}, @{Word='Valor'; Meaning='отвага'},
    @{Word='Serenity'; Meaning='спокойствие'}, @{Word='Zenith'; Meaning='зенит, высшая точка'}, @{Word='Velvet'; Meaning='бархат'},
    @{Word='Fable'; Meaning='сказание или басня'}, @{Word='Mirage'; Meaning='мираж'}, @{Word='Ever'; Meaning='вечность или неизменность'},
    @{Word='Crystal'; Meaning='кристалл'}, @{Word='Astra'; Meaning='звёзды'}, @{Word='Solace'; Meaning='утешение'},
    @{Word='Karma'; Meaning='карма, последствия поступков'}, @{Word='Lucid'; Meaning='ясный, осознанный'}
)
$script:MeaningSeeds += @(
    @{Word='Velora'; Meaning='вымышленное имя, мягкое и редкое звучание'}, @{Word='Auralis'; Meaning='имя, вдохновлённое aurora и светом'},
    @{Word='Nymera'; Meaning='фэнтезийное имя с ночным звучанием'}, @{Word='Solara'; Meaning='солнечная энергия'},
    @{Word='Lunara'; Meaning='лунный свет'}, @{Word='Lumora'; Meaning='свет и сияние'},
    @{Word='Zephyra'; Meaning='лёгкий ветер'}, @{Word='Caelum'; Meaning='небо по-латыни'},
    @{Word='Vesper'; Meaning='вечерняя звезда или вечер'}, @{Word='Elara'; Meaning='спутник Юпитера и имя'},
    @{Word='Halcyon'; Meaning='безмятежность и спокойствие'}, @{Word='Reverie'; Meaning='мечтательность, грёзы'},
    @{Word='Meridian'; Meaning='меридиан, высшая точка'}, @{Word='Equinox'; Meaning='равноденствие'},
    @{Word='Saffron'; Meaning='шафран, тёплый золотистый оттенок'}, @{Word='Indigo'; Meaning='индиго, глубокий синий цвет'},
    @{Word='Sable'; Meaning='соболиный, тёмный оттенок'}, @{Word='Glimmer'; Meaning='мерцание'},
    @{Word='Celeste'; Meaning='небесный'}, @{Word='Azure'; Meaning='лазурь, небесно-синий'},
    @{Word='Astraea'; Meaning='имя из греческой мифологии'}, @{Word='Caldera'; Meaning='вулканическая котловина'},
    @{Word='Ardent'; Meaning='пылкий, пламенный'}, @{Word='Seraph'; Meaning='серафим, небесное существо'},
    @{Word='Evora'; Meaning='короткое звучное имя'}, @{Word='Virelia'; Meaning='вымышленное имя, ассоциация с природой'},
    @{Word='Novara'; Meaning='новизна, новое начало'}, @{Word='Zyra'; Meaning='короткое фантазийное имя'},
    @{Word='Aven'; Meaning='короткое имя, ассоциация с природой'}, @{Word='Orlune'; Meaning='вымышленное имя с лунным оттенком'},
    @{Word='Nyxen'; Meaning='имя, вдохновлённое мифологической ночью'}, @{Word='Aetheris'; Meaning='небесный эфир'},
    @{Word='Aurix'; Meaning='имя, вдохновлённое aurum — золото'}, @{Word='Elarion'; Meaning='фэнтезийное имя'},
    @{Word='Solune'; Meaning='солнце и луна'}, @{Word='Auralyn'; Meaning='сияние и мягкое звучание'},
    @{Word='Zephryn'; Meaning='имя, вдохновлённое ветром'}, @{Word='Caelix'; Meaning='небесная тематика'},
    @{Word='Faylen'; Meaning='фэнтезийное имя'}, @{Word='Oryn'; Meaning='короткое оригинальное имя'}
)
$script:NatureSeeds = @(
    @{Word='Aurora'; Meaning='полярное сияние'}, @{Word='Ember'; Meaning='тлеющий уголёк'}, @{Word='Zephyr'; Meaning='лёгкий ветер'},
    @{Word='Nimbus'; Meaning='облако'}, @{Word='Orion'; Meaning='созвездие Ориона'}, @{Word='Lyra'; Meaning='созвездие Лиры'},
    @{Word='Nova'; Meaning='вспышка новой звезды'}, @{Word='Lunar'; Meaning='лунный'}, @{Word='Solar'; Meaning='солнечный'},
    @{Word='Comet'; Meaning='комета'}, @{Word='Orbit'; Meaning='орбита'}, @{Word='Nebula'; Meaning='космическая туманность'},
    @{Word='Cosmos'; Meaning='космос и мироздание'}, @{Word='Meteor'; Meaning='метеор'}, @{Word='Stellar'; Meaning='звёздный'},
    @{Word='Tundra'; Meaning='северная природная зона'}, @{Word='Willow'; Meaning='ива'}, @{Word='Aspen'; Meaning='осина'},
    @{Word='River'; Meaning='река'}, @{Word='Ocean'; Meaning='океан'}, @{Word='Coral'; Meaning='коралл'},
    @{Word='Cinder'; Meaning='зола, уголёк'}, @{Word='Storm'; Meaning='буря'}, @{Word='Frost'; Meaning='иней'},
    @{Word='Glacier'; Meaning='ледник'}, @{Word='Rain'; Meaning='дождь'}, @{Word='Cloud'; Meaning='облако'},
    @{Word='Sierra'; Meaning='горный хребет'}, @{Word='Moss'; Meaning='мох'}, @{Word='Flora'; Meaning='растительный мир'},
    @{Word='Fauna'; Meaning='животный мир'}, @{Word='Petal'; Meaning='лепесток'}, @{Word='Breeze'; Meaning='лёгкий ветерок'}
)
$script:MythSeeds = @(
    @{Word='Atlas'; Meaning='титан, державший небесный свод'}, @{Word='Nyx'; Meaning='богиня ночи'}, @{Word='Orion'; Meaning='мифический охотник и созвездие'},
    @{Word='Phoenix'; Meaning='птица возрождения'}, @{Word='Aether'; Meaning='персонификация небесного эфира'}, @{Word='Hermes'; Meaning='вестник богов'},
    @{Word='Athena'; Meaning='богиня мудрости'}, @{Word='Apollo'; Meaning='бог искусств и света'}, @{Word='Loki'; Meaning='хитрый персонаж скандинавских мифов'},
    @{Word='Freya'; Meaning='скандинавская богиня любви и магии'}, @{Word='Odin'; Meaning='верховный бог скандинавских мифов'}, @{Word='Titan'; Meaning='могущественный древний бог'},
    @{Word='Valkyrie'; Meaning='воительница из скандинавских мифов'}, @{Word='Medusa'; Meaning='горгона из греческих мифов'}, @{Word='Draco'; Meaning='дракон; также название созвездия'},
    @{Word='Cerberus'; Meaning='страж подземного мира'}, @{Word='Artemis'; Meaning='богиня охоты'}, @{Word='Perseus'; Meaning='герой греческих мифов'},
    @{Word='Hades'; Meaning='владыка подземного мира'}, @{Word='Elysium'; Meaning='обитель блаженных'}, @{Word='Ares'; Meaning='бог войны'},
    @{Word='Icarus'; Meaning='герой мифа о полёте к солнцу'}, @{Word='Pegasus'; Meaning='крылатый конь'}, @{Word='Hydra'; Meaning='многоголовое чудовище'},
    @{Word='Argos'; Meaning='имя из древнегреческих мифов'}, @{Word='Midas'; Meaning='царь с золотым прикосновением'}, @{Word='Juno'; Meaning='римская богиня'},
    @{Word='Vesta'; Meaning='римская богиня домашнего очага'}, @{Word='Morpheus'; Meaning='бог сновидений в поздней мифологии'}
)
$script:GamingSeeds = @(
    @{Word='Shadow'; Meaning='тень, скрытность'}, @{Word='Frost'; Meaning='холод и иней'}, @{Word='Blaze'; Meaning='пламя'},
    @{Word='Vortex'; Meaning='вихрь'}, @{Word='Venom'; Meaning='яд, опасность'}, @{Word='Rogue'; Meaning='одиночка вне правил'},
    @{Word='Phantom'; Meaning='призрак'}, @{Word='Ghost'; Meaning='дух, призрак'}, @{Word='Reaper'; Meaning='жнец'},
    @{Word='Rift'; Meaning='разлом'}, @{Word='Clutch'; Meaning='решающий момент в игре'}, @{Word='Strafe'; Meaning='движение в сторону в шутерах'},
    @{Word='Nova'; Meaning='звёздная вспышка'}, @{Word='Hex'; Meaning='заклинание или шестнадцатеричный код'}, @{Word='Havoc'; Meaning='хаос и разрушение'},
    @{Word='Storm'; Meaning='буря'}, @{Word='Ace'; Meaning='ас, мастер своего дела'}, @{Word='Raptor'; Meaning='хищник'},
    @{Word='Spectre'; Meaning='призрачный силуэт'}, @{Word='Glitch'; Meaning='сбой или визуальный глитч'}, @{Word='Pixel'; Meaning='пиксель'},
    @{Word='Nexus'; Meaning='узел или связь'}, @{Word='Raven'; Meaning='ворон'}, @{Word='Zero'; Meaning='ноль, точка отсчёта'},
    @{Word='Viper'; Meaning='гадюка'}, @{Word='Talon'; Meaning='коготь'}, @{Word='Onyx'; Meaning='чёрный камень'},
    @{Word='Inferno'; Meaning='адское пламя'}, @{Word='Fable'; Meaning='легенда или сказание'}, @{Word='Zenith'; Meaning='высшая точка'},
    @{Word='Drift'; Meaning='дрейф или контролируемый занос'}, @{Word='Pulse'; Meaning='пульс, ритм'}, @{Word='Rush'; Meaning='напор и рывок вперёд'}
)
$script:MinimalSeeds = @(
    @{Word='Nyx'; Meaning='ночь в греческой мифологии'}, @{Word='Kai'; Meaning='короткое имя с разными значениями в языках'}, @{Word='Neo'; Meaning='новый'},
    @{Word='Zen'; Meaning='спокойствие и сосредоточенность'}, @{Word='Rune'; Meaning='древний символ'}, @{Word='Echo'; Meaning='эхо'},
    @{Word='Void'; Meaning='пустота'}, @{Word='Sol'; Meaning='солнце по-латыни'}, @{Word='Lux'; Meaning='свет по-латыни'},
    @{Word='Vex'; Meaning='короткое резкое звучание; англ. vex — раздражать'}, @{Word='Zed'; Meaning='название буквы Z'}, @{Word='Kiro'; Meaning='короткое имя'},
    @{Word='Nox'; Meaning='ночь по-латыни'}, @{Word='Milo'; Meaning='короткое имя'}, @{Word='Luma'; Meaning='мягкое звучание, ассоциация со светом'},
    @{Word='Koda'; Meaning='короткое имя'}, @{Word='Ryn'; Meaning='короткое фантазийное имя'}, @{Word='Aero'; Meaning='воздух'},
    @{Word='Zora'; Meaning='рассвет в некоторых славянских языках'}, @{Word='Ari'; Meaning='короткое имя'}, @{Word='Rex'; Meaning='король по-латыни'},
    @{Word='Lynx'; Meaning='рысь'}, @{Word='Juno'; Meaning='римская богиня'}, @{Word='Omen'; Meaning='знак или предзнаменование'}
)
$script:Modifiers = @(
    @{Word='Nova'; Meaning='новая звезда'}, @{Word='Pixel'; Meaning='пиксель'}, @{Word='Echo'; Meaning='эхо'}, @{Word='Pulse'; Meaning='пульс'},
    @{Word='Vortex'; Meaning='вихрь'}, @{Word='Frost'; Meaning='иней'}, @{Word='Shadow'; Meaning='тень'}, @{Word='Lunar'; Meaning='лунный'},
    @{Word='Solar'; Meaning='солнечный'}, @{Word='Orbit'; Meaning='орбита'}, @{Word='Flux'; Meaning='поток изменений'}, @{Word='Zen'; Meaning='спокойствие'},
    @{Word='Storm'; Meaning='буря'}, @{Word='Byte'; Meaning='единица цифровых данных'}, @{Word='Astra'; Meaning='звёзды'}, @{Word='Void'; Meaning='пустота'},
    @{Word='Ghost'; Meaning='призрак'}, @{Word='Drift'; Meaning='дрейф'}, @{Word='Blaze'; Meaning='пламя'}, @{Word='Sky'; Meaning='небо'},
    @{Word='Core'; Meaning='ядро'}, @{Word='Wave'; Meaning='волна'}, @{Word='Hyper'; Meaning='ускоренный, усиленный'}, @{Word='Ultra'; Meaning='сверх-'},
    @{Word='Neo'; Meaning='новый'}, @{Word='Prime'; Meaning='первый, основной'}, @{Word='Rare'; Meaning='редкий'}, @{Word='True'; Meaning='истинный'},
    @{Word='One'; Meaning='один, единственный'}, @{Word='X'; Meaning='загадочный символ'}
)

# --- Словарь: категории и слова
$script:WordCategories = @(
    'Космос','Свет и энергия','Природа','Мифология','Эмоции и характер','Скорость',
    'Абстрактное','Эстетика','Технологии и кибер','Игры и киберспорт','Животные',
    'Океан и вода','Огонь и пламя','Тьма и ночь','Музыка и звук','Драгоценности',
    'Цвета','Латинские корни','Северные саги','Восток и аниме','Растения и цветы',
    'Горы и земли','Небо и погода','Фэнтези-неологизмы',
    'Кино и сериалы','Еда и напитки','Спорт и состязания','Транспорт и машины',
    'Профессии и ремёсла','Инструменты и механизмы','Ткани и материалы',
    'Камни и минералы','Сад и цветение','Птицы','Корабли и походы',
    'Пустыня и дюны','Север и лёд','Вулканы и магма','Созвездия и звёзды',
    'Средневековье и рыцари','Ретро и винтаж','Книги и предания',
    'Роботы и механизмы','Игры и настольные игры',
    'Имя, Фамилия','Русские слова латиницей'
)

$script:MeaningGroups = @{
    'Космос' = @('Orion','Lyra','Nova','Lunar','Solar','Comet','Orbit','Nebula','Cosmos','Meteor','Stellar','Astra','Altair','Auriga','Quasar','Pulsar','Zenith','Apollo','Stardust','Galaxy','Eclipse','Cosmic','Vega','Nebulon')
    'Свет и энергия' = @('Aurora','Ember','Blaze','Nova','Pulse','Solar','Stellar','Lux','Radiant','Cinder','Lumen','Glow','Spark','Beam','Flare','Prism','Halo','Shine','Volt','Energy','Solstice','Lucent','Ardor','Kindle')
    'Природа' = @('Tundra','Willow','Aspen','River','Ocean','Coral','Storm','Frost','Glacier','Rain','Cloud','Sierra','Moss','Flora','Fauna','Petal','Breeze','Raven','Lynx','Ivy','Fern','Grove','Cedar','Sage')
    'Эмоции и характер' = @('Haven','Serenity','Valor','Solace','Karma','Mystic','Fable','Sage','Ever','Lucid','Brave','Calm','Wild','Proud','Bold','Grim','Merry','Noble','Wise','Ardent','Reverie','Halcyon','Verity','Amity')
    'Скорость' = @('Flux','Drift','Strafe','Vector','Raptor','Pulse','Hyper','Ultra','Vortex','Ace','Swift','Dash','Rush','Sprint','Bolt','Zip','Dart','Rapid','Fleet','Mach','Velocity','Quicken','Dartle','Tempest')
    'Абстрактное' = @('Cipher','Flux','Vortex','Nexus','Void','Echo','Meta','Quantum','Zenith','Mirage','Glitch','Rune','Axiom','Paradox','Enigma','Logos','Nihil','Omen','Sigil','Aether','Nyx','Solstice','Meridian','Equinox')
    'Эстетика' = @('Astra','Velvet','Crystal','Mirage','Lyra','Solace','Luma','Serenity','Aether','Zephyr','Elysium','Celeste','Porcelain','Ivory','Silk','Amber','Pearl','Marble','Opal','Satin','Gossamer','Ethereal','Halcyon','Vesper')
    'Мифология' = @('Atlas','Nyx','Orion','Phoenix','Aether','Hermes','Athena','Apollo','Loki','Freya','Odin','Titan','Valkyrie','Medusa','Draco','Cerberus','Artemis','Perseus','Hades','Elysium','Ares','Icarus','Pegasus','Hydra','Argos','Midas','Juno','Vesta','Morpheus','Thor')
    'Технологии и кибер' = @('Cyber','Quantum','Vector','Nexus','Glitch','Byte','Pixel','Neon','Circuit','Data','Matrix','Synth','Chrome','Laser','Digital','Code','Binary','Robot','Android','Techno','Servo','Crypto','Nano','Protocol')
    'Игры и киберспорт' = @('Clutch','Rift','Rogue','Ace','Strafe','Frag','Respawn','Loot','Quest','Guild','Raid','Combo','Snipe','Meta','Buff','Carry','Tank','Boss','Level','Crit','Spawn','Arena','Rank','Victory')
    'Животные' = @('Raven','Lynx','Wolf','Fox','Bear','Hawk','Eagle','Shark','Tiger','Panther','Falcon','Viper','Cobra','Dragon','Kraken','Unicorn','Gryphon','Serpent','Stallion','Jaguar','Osprey','Badger','Otter','Heron')
    'Океан и вода' = @('Ocean','Coral','Tide','Wave','Reef','Abyss','Marine','Aqua','Lagoon','Tsunami','Neptune','Pearl','Sail','Anchor','Deep','Current','Surf','Mist','Fjord','Delta','Cascade','Harbor','Nerida','Pelagic')
    'Огонь и пламя' = @('Blaze','Ember','Cinder','Flame','Inferno','Pyre','Ash','Scorch','Magma','Vulcan','Phoenix','Kindle','Sear','Torch','Flare','Smoke','Coal','Ignite','Spark','Furnace','Helios','Caldera','Brand','Salamander')
    'Тьма и ночь' = @('Noctis','Shadow','Obsidian','Void','Phantom','Onyx','Raven','Midnight','Eclipse','Umbra','Dusk','Noir','Gloom','Wraith','Specter','Nightfall','Crypt','Shade','Murk','Tenebris','Styx','Erebus','Vesper','Moros')
    'Музыка и звук' = @('Echo','Pulse','Rhythm','Melody','Bass','Chord','Tempo','Verse','Lyric','Sonar','Harmony','Octave','Refrain','Anthem','Nocturne','Cadence','Beat','Treble','Sonic','Reverb','Aria','Cadenza','Sonata','Fortis')
    'Драгоценности' = @('Onyx','Crystal','Diamond','Ruby','Sapphire','Emerald','Amber','Jade','Opal','Pearl','Topaz','Garnet','Ivory','Silver','Gold','Platinum','Quartz','Zircon','Beryl','Obsidian','Amethyst','Malachite','Jasper','Citrine')
    'Цвета' = @('Azure','Indigo','Violet','Crimson','Scarlet','Cobalt','Ivory','Sable','Amber','Cyan','Magenta','Vermilion','Cerulean','Emerald','Jet','Rose','Rust','Slate','Ochre','Sepia','Viridian','Cardinal','Lilac','Umber')
    'Латинские корни' = @('Sol','Lux','Nox','Rex','Vox','Astra','Terra','Ignis','Aqua','Ventus','Bellum','Pax','Vita','Tempus','Lumen','Umbra','Ferrum','Caelum','Nexus','Veritas','Fortis','Novus','Sanctus','Aeternum')
    'Северные саги' = @('Odin','Thor','Loki','Freya','Rune','Fjord','Valhalla','Skald','Ymir','Fenrir','Sleipnir','Mjolnir','Asgard','Midgard','Njord','Saga','Viking','Nordic','Frost','Berserk','Skadi','Ulf','Havard','Ragnar')
    'Восток и аниме' = @('Kai','Zen','Ryu','Kira','Yuki','Sora','Hana','Tora','Kaze','Tsuki','Sakura','Ronin','Shogun','Akira','Hikari','Yami','Kumo','Ryo','Senshi','Kitsune','Shinobi','Tsuru','Yokai','Kage')
    'Растения и цветы' = @('Willow','Aspen','Ivy','Fern','Moss','Flora','Petal','Rose','Lily','Jasmine','Orchid','Lotus','Clover','Thistle','Laurel','Olive','Cactus','Bamboo','Sequoia','Verbena','Dahlia','Iris','Myrtle','Sage')
    'Горы и земли' = @('Sierra','Tundra','Canyon','Summit','Ridge','Cliff','Valley','Plateau','Crater','Dune','Gorge','Mesa','Alpine','Basalt','Granite','Quarry','Steppe','Fjord','Volcano','Terrace','Highland','Badlands','Stone','Cairn')
    'Небо и погода' = @('Cloud','Storm','Rain','Breeze','Mist','Frost','Halo','Nimbus','Zephyr','Thunder','Lightning','Cyclone','Monsoon','Blizzard','Squall','Aurora','Sky','Fog','Gale','Tempest','Dew','Haze','Sirocco','Cirro')
    'Фэнтези-неологизмы' = @('Velora','Auralis','Nymera','Solara','Lunara','Lumora','Zephyra','Caelum','Vesper','Elara','Halcyon','Reverie','Meridian','Equinox','Astraea','Caldera','Ardent','Seraph','Evora','Virelia','Novara','Zyra','Aven','Orlune','Nyxen','Aetheris','Aurix','Elarion','Solune','Auralyn','Zephryn','Caelix','Faylen','Oryn','Saffron','Indigo','Sable','Glimmer','Celeste','Azure')
    'Кино и сериалы' = @('Cinema','Film','Scene','Reel','Premier','Saga','Episode','Pilot','Trailer','Studio','Montage','Frame','Cut','Serial')
    'Еда и напитки' = @('Honey','Cocoa','Mango','Peach','Cherry','Berry','Maple','Vanilla','Caramel','Espresso','Matcha','Citrus','Ginger','Saffron')
    'Спорт и состязания' = @('Derby','Match','League','Team','Goal','Strike','Spar','Tackle','Dribble','Penalty','Champion','Marathon','Hurdle','Relay')
    'Транспорт и машины' = @('Turbo','Rotor','Piston','Chassis','Motor','Gearbox','Cabin','Fuselage','Torque','Axle','Cargo','Voyage','Driver','Convoy')
    'Профессии и ремёсла' = @('Smith','Baker','Miner','Pilot','Ranger','Scribe','Keeper','Hunter','Warden','Envoy','Artisan','Mason','Courier','Skipper')
    'Инструменты и механизмы' = @('Anvil','Chisel','Lathe','Forge','Hammer','Compass','Caliper','Lever','Pulley','Winch','Gauge','Drill','Vise','Plane')
    'Ткани и материалы' = @('Denim','Linen','Wool','Velour','Flannel','Canvas','Suede','Brocade','Damask','Cashmere','Tweed','Cord','Weave','Yarn')
    'Камни и минералы' = @('Flint','Agate','Cornelian','Sardonyx','Aventurine','Labradorite','Charoite','Rodonite','Amazonite','Morion','Heliotrope','Uvarovite')
    'Сад и цветение' = @('Bloom','Blossom','Peony','Tulip','Aster','Magnolia','Camellia','Wisteria','Hyacinth','Narcissus','Lavender','Azalea','Garden','Sprout')
    'Птицы' = @('Kestrel','Condor','Ibis','Albatross','Pelican','Puffin','Grouse','Magpie','Stork','Crane','Swallow','Finch','Oriole','Bunting')
    'Корабли и походы' = @('Corsair','Galleon','Brig','Schooner','Regatta','Sextant','Helm','Ballast','Frigate','Caravel','Armada','Skipper','Voyage','Anchor')
    'Пустыня и дюны' = @('Dune','Oasis','Sirocco','Sahara','Caravan','Sand','Dusty','Bedouin','Mirage','Scorch','Argil','Khan','Steppe','Mirage')
    'Север и лёд' = @('Blizzard','Polar','Igloo','Narwhal','Walrus','Snow','Sledge','Ice','Frostbite','Nord','Winter','Hoarfrost','Packice','Boreal')
    'Вулканы и магма' = @('Lava','Geysir','Sulfur','Vesuvius','Etna','Krakatoa','Fumarole','Magma','Caldera','Basalt','Ignite','Cinder','Pyro','Tephra')
    'Созвездия и звёзды' = @('Andromeda','Cassiopeia','Centaurus','Aquila','Cygnus','Cepheus','Aries','Taurus','Gemini','Libra','Orion','Polaris','Sirius','Rigel')
    'Средневековье и рыцари' = @('Knight','Squire','Herald','Banner','Citadel','Moat','Tourney','Joust','Crown','Sovereign','Fief','Baron','Duke','Castellan')
    'Ретро и винтаж' = @('Vinyl','Cassette','Polaroid','Retro','Vintage','Gramophone','Jukebox','Diner','Lounge','Cruiser','Sepia','Patina','Archive','Classic')
    'Книги и предания' = @('Folio','Tome','Legend','Myth','Chronicle','Ballad','Epic','Sonnet','Chapter','Volume','Manuscript','Parchment','Saga','Verse')
    'Роботы и механизмы' = @('Automaton','Droid','Actuator','Gizmo','Widget','Cog','Sprocket','Dynamo','Turbine','Mecha','Servo','Circuit','Android','Piston')
    'Игры и настольные игры' = @('Dice','Pawn','Rook','Gambit','Checkmate','Board','Token','Shuffle','Dealer','Trump','Suit','Hand','Round','Turn')
    'Имя, Фамилия' = @('John','Birlich','Mark','Cukerberk','Mask','Ilon','Alex','Dean','Kate','River','Ryan','Blake')
    'Русские слова латиницей' = @('Privet','Phizik','Shizik','Cloun','Debil','Poka','Khorosho','Avos','Nibudo','Bardak','Kefir','Pelmeni','Shaurma','Tovarich','Kartoshka','Arbuz')
}

# --- Слоги и редкие слова
$script:InventedOnsets = @(
    'k','kr','v','vr','d','dr','t','tr','n','z','s','st','r','l','m','p','b','g','gr','f','fl',
    'th','sh','ch','x','qu','br','pr','sn','sl','sm','sk','c','h','j','w','y','kl','gl','bl',
    'fr','pl','gn','kn','rh','ph','str','skr','thr','zar','kor','vel','dra','myr','syl','tha'
)
$script:InventedNuclei = @('a','e','i','o','u','y','ae','ia','ou','ee','ai','eo','io','ua','ei','oa','au','ie')
$script:InventedCodas = @(
    'n','r','l','s','x','th','sh','m','k','v','d','t','ng','nn','ss','rn','ld','nk','rk','ll',
    'ny','ry','vy','ly','dy','sy','na','ra','la','ka','va','re','ne','le','ce','ze','xis','ron',
    'kan','tar','vin','dor','mith','ryn','los','mir','dan','fer','gon','nar','sil','tor','van',
    'zar','lune','vire','neth','quis','mara','drel','thos','kin','zar','vyn','lok','ren','dal'
)

$script:RareShortWords = @($script:MinimalSeeds | ForEach-Object { [string]$_.Word })

$script:StyleWords = @{
    'Минималистичный' = @('Neo','Zen','Nox','Nyx','Lux','Ryn')
    'Киберспортивный' = @('Clutch','Rift','Vex','Rogue','Ace','Strafe')
    'Футуристический' = @('Quantum','Vector','Nexus','Cyber','Hyper','Pulse','Nova')
    'Тёмный' = @('Noctis','Shadow','Obsidian','Void','Phantom','Onyx','Raven')
    'Эстетичный' = @('Lunar','Velvet','Astra','Serene','Luma','Aether')
    'Редкий' = @('Aether','Zephyr','Elysium','Solace','Altair','Auriga')
    'Короткий' = @('Nyx','Lux','Nox','Vex','Zed','Ryn')
    'Двусловный' = @('Nova','Echo','Pulse','Orbit','Frost','Shadow')
    'Аниме' = @('Kai','Zen','Ryu','Kira','Yuki','Sora','Kage','Ronin')
    'Готический' = @('Raven','Crypt','Gargoyle','Nocturne','Obsidian','Veil','Shade','Mourne')
    'Древний мир' = @('Atlas','Titan','Pharaoh','Spartan','Legion','Oracle','Dynasty')
    'Космический' = @('Orbit','Quasar','Pulsar','Vega','Stardust','Cosmos','Nebula')
    'Латинский' = @('Rex','Lux','Nox','Vox','Fortis','Veritas','Novus','Aeternum')
    'Милый' = @('Candy','Mochi','Berry','Peach','Honey','Cookie','Biscuit')
    'Морской' = @('Anchor','Fjord','Corsair','Tide','Neptune','Harbor','Marlin')
    'Неоновый' = @('Neon','Synth','Chrome','Laser','Glow','Arcade','Vapor')
    'Природный' = @('Willow','Aspen','Glacier','River','Coral','Meadow','Cedar')
    'Скандинавский' = @('Rune','Skald','Fenrir','Torvald','Bjorn','Halvard','Stig')
    'Хардкорный' = @('Reaper','Havoc','Mayhem','Brutal','Onslaught','Torment','Raze')
}
$script:CheckedNames = @{}
$script:Candidates = New-Object 'System.Collections.Generic.List[object]'
$script:CandidateIndex = @{}
$script:CandidateRevision = 0
$script:AvailableNamesRevision = -1
$script:HistoryDirectory = Join-Path $env:LOCALAPPDATA 'UniversalUsernameFinder'
$script:HistoryPath = Join-Path $script:HistoryDirectory 'username_history.json'
$script:SettingsPath = Join-Path $script:HistoryDirectory 'settings.json'
$script:FreeHistory = @()
$script:RetiredNames = @{}
$script:HistoryDirty = $false
$script:HistoryDirtySince = $null
$script:LastGridRefresh = [DateTime]::MinValue
$script:GridRefreshPending = $false
$script:StatusColors = @{
    'Свободен'            = [System.Drawing.Color]::FromArgb(99,222,151)
    'Вероятно свободен'   = [System.Drawing.Color]::FromArgb(120,205,250) # legacy: старые записи истории
    'Занят'               = [System.Drawing.Color]::FromArgb(245,120,120)
    'Недопустимый'        = [System.Drawing.Color]::FromArgb(180,188,203)
    'Не подтверждено'      = [System.Drawing.Color]::FromArgb(207,185,255)
    'Ошибка сети'         = [System.Drawing.Color]::FromArgb(255,190,92)
    'Проверяется'         = [System.Drawing.Color]::FromArgb(105,185,255)
    'Ожидает'             = [System.Drawing.Color]::FromArgb(170,173,178)
}
try {
    if (Test-Path -LiteralPath $script:HistoryPath) {
        $historyJson = [System.IO.File]::ReadAllText($script:HistoryPath)
        if (-not [string]::IsNullOrWhiteSpace($historyJson)) {
            $historyData = $historyJson | ConvertFrom-Json -ErrorAction Stop
            $script:FreeHistory = @($historyData.FreeHistory | Where-Object { $_.Name -and $_.Platform })
            foreach ($retiredKey in @($historyData.RetiredNames)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$retiredKey)) { $script:RetiredNames[[string]$retiredKey] = $true }
            }
            foreach ($checkedKey in @($historyData.CheckedNames)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$checkedKey)) { $script:CheckedNames[[string]$checkedKey] = $true }
            }
        }
    }
} catch {
    $script:FreeHistory = @()
    $script:RetiredNames = @{}
    $script:CheckedNames = @{}
    Write-StartupLog ('Не удалось прочитать историю ников, начинаем с пустой: ' + $_.Exception.Message)
}

$script:SeedIndex = $null

function Initialize-SeedIndex {
    if ($null -ne $script:SeedIndex) { return }
    $index = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $seedArrays = @(
        $script:AppSeeds, $script:MeaningSeeds, $script:NatureSeeds,
        $script:MythSeeds, $script:GamingSeeds, $script:MinimalSeeds, $script:Modifiers
    )
    foreach ($seedArray in $seedArrays) {
        foreach ($seed in $seedArray) {
            if ($null -eq $seed) { continue }
            $word = [string]$seed.Word
            if ($word -and -not $index.ContainsKey($word)) { $index[$word] = $seed }
        }
    }
    $script:SeedIndex = $index
}

function Get-SeedForWord {
    param([string]$Word, [string]$FallbackMeaning = 'осмысленное слово')
    if ([string]::IsNullOrWhiteSpace($Word)) {
        return [pscustomobject]@{ Word = $Word; Meaning = $FallbackMeaning }
    }
    Initialize-SeedIndex
    if ($script:SeedIndex.ContainsKey($Word)) { return $script:SeedIndex[$Word] }
    return [pscustomobject]@{ Word = $Word; Meaning = $FallbackMeaning }
}

function Get-NickStructure {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return 'Одно слово' }
    $letters = [regex]::Replace($Name, '[^A-Za-z]', '')
    if ($letters.Length -lt 2) { return 'Одно слово' }
    for ($i = 1; $i -lt $letters.Length; $i++) {
        if ([char]::IsUpper($letters[$i])) { return 'Два слова' }
    }
    if ($Name.IndexOf('_') -ge 0) { return 'Два слова' }
    Initialize-SeedIndex
    for ($i = 3; $i -le $letters.Length - 3; $i++) {
        $left = $letters.Substring(0, $i)
        if (-not $script:SeedIndex.ContainsKey($left)) { continue }
        if ($script:SeedIndex.ContainsKey($letters.Substring($i))) { return 'Два слова' }
    }
    return 'Одно слово'
}

function Convert-ToNickToken {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $value = $Text.Trim().ToLowerInvariant()
    $known = @{
        'океан'='Ocean'; 'киберпанк'='Cyberpunk'; 'животные'='Animals'; 'животное'='Animal'; 'космос'='Cosmos'; 'природа'='Nature';
        'свет'='Light'; 'энергия'='Energy'; 'скорость'='Speed'; 'эмоции'='Emotion'; 'мифология'='Mythology'; 'огонь'='Fire';
        'вода'='Water'; 'лёд'='Ice'; 'лед'='Ice'; 'звезда'='Star'; 'ночь'='Night'; 'дождь'='Rain'; 'буря'='Storm';
        'луна'='Moon'; 'солнце'='Sun'; 'тень'='Shadow'; 'волк'='Wolf'; 'кот'='Cat'; 'кошка'='Cat'; 'лес'='Forest'; 'море'='Sea'
    }
    if ($known.ContainsKey($value)) { return [string]$known[$value] }
    $map = @{
        'а'='a'; 'б'='b'; 'в'='v'; 'г'='g'; 'д'='d'; 'е'='e'; 'ё'='yo'; 'ж'='zh'; 'з'='z'; 'и'='i'; 'й'='y'; 'к'='k';
        'л'='l'; 'м'='m'; 'н'='n'; 'о'='o'; 'п'='p'; 'р'='r'; 'с'='s'; 'т'='t'; 'у'='u'; 'ф'='f'; 'х'='kh'; 'ц'='ts';
        'ч'='ch'; 'ш'='sh'; 'щ'='shch'; 'ъ'=''; 'ы'='y'; 'ь'=''; 'э'='e'; 'ю'='yu'; 'я'='ya'
    }
    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $value.ToCharArray()) {
        $character = [string]$char
        if ($map.ContainsKey($character)) { [void]$builder.Append([string]$map[$character]) }
        elseif ($character -match '[a-z0-9]') { [void]$builder.Append($character) }
    }
    $result = $builder.ToString()
    if ($result.Length -gt 0) { return $result.Substring(0,1).ToUpperInvariant() + $result.Substring(1) }
    return ''
}

function Test-RobloxUsernameFormat {
    param([string]$Username)
    if ([string]::IsNullOrWhiteSpace($Username)) { return $false }
    return ($Username.Length -ge 3 -and $Username.Length -le 20 -and $Username -match '^[A-Za-z0-9_]+$' -and $Username -match '[A-Za-z0-9]' -and $Username -notmatch '^_|_$|__')
}

# --- Платформы и правила длины
$script:SupportedPlatforms = @('Roblox','Google','Mail.ru','VK','Discord','Outlook','Telegram','Steam','GitHub','YouTube')

function Test-SupportedPlatform {
    param([string]$Platform)
    if ([string]::IsNullOrWhiteSpace($Platform)) { return $false }
    return ($script:SupportedPlatforms -contains $Platform)
}

$script:PlatformLengthRules = @{
    'Roblox'    = @{ Min = 3; Max = 20 }
    'Google'    = @{ Min = 6; Max = 30 }
    'Mail.ru'   = @{ Min = 5; Max = 31 }
    'VK'        = @{ Min = 5; Max = 32 }
    'Discord'   = @{ Min = 2; Max = 32 }
    'Outlook'   = @{ Min = 3; Max = 64 }
    'Telegram'  = @{ Min = 5; Max = 32 }
    'GitHub'    = @{ Min = 1; Max = 39 }
    'YouTube'   = @{ Min = 3; Max = 30 }
    'Steam'      = @{ Min = 3; Max = 30 }
}

function Get-PlatformLengthRule {
    param([string]$Platform)
    $rules = $script:PlatformLengthRules
    if ($rules.ContainsKey($Platform)) {
        $rule = $rules[$Platform]
        return [pscustomobject]@{ Min = [int]$rule['Min']; Max = [int]$rule['Max'] }
    }
    return [pscustomobject]@{ Min = 3; Max = 32 }
}

$script:PlatformFormatHints = @{
    'Roblox'   = '3–20 символов: латиница, цифры и «_»; «_» не в начале, не в конце и не идут подряд'
    'Google'   = '6–30 символов: латиница, цифры и точки; точка не в начале, не в конце и не подряд — Gmail игнорирует точки, «a.b» и «ab» это один адрес'
    'Mail.ru'  = '5–31 символ: латиница, цифры и «. _ -»; спецсимволы не в начале, не в конце и не идут подряд'
    'VK'       = '5–32 символа: латиница, цифры, точка и «_», без повторов подряд'
    'Discord'  = '2–32 символа: латиница, цифры, точка и «_»; зарезервированные имена запрещены'
    'Outlook'  = '3–64 символа: латиница, цифры, «. _ -»; начинается с буквы или цифры, спецсимволы не подряд и не в конце'
    'Telegram' = '5–32 символа: начинается с буквы, далее латиница, цифры и «_»'
    'Steam'    = '3–30 символов: начинается с буквы или цифры, далее латиница, цифры, «_» и «-»'
    'GitHub'   = '1–39 символов: латиница, цифры и «-», без «--» и без «-» по краям'
    'YouTube'  = '3–30 символов: латиница, цифры, точка, «_» и «-»'
}

$script:PlatformDomains = @{
    'Google'  = 'gmail.com'
    'Mail.ru' = 'mail.ru'
    'Outlook' = 'outlook.com'
}

function Get-PlatformFormatHint {
    param([string]$Platform)
    if ($script:PlatformFormatHints.ContainsKey($Platform)) { return [string]$script:PlatformFormatHints[$Platform] }
    return 'уточните правила на странице регистрации платформы'
}

function Get-PlatformDomain {
    param([string]$Platform)
    if ($script:PlatformDomains.ContainsKey($Platform)) { return [string]$script:PlatformDomains[$Platform] }
    return ''
}

function Get-DisplayNick {
    param([string]$Platform, [string]$Name)
    $domain = Get-PlatformDomain -Platform $Platform
    if ($domain) { return ($Name + '@' + $domain) }
    return $Name
}

function Test-UsernameFormat {
    param([string]$Username, [string]$Platform)
    if ([string]::IsNullOrWhiteSpace($Username)) { return $false }
    switch ($Platform) {
        'Roblox' { return (Test-RobloxUsernameFormat $Username) }
        'Google' { return ($Username.Length -ge 6 -and $Username.Length -le 30 -and $Username -match '^[A-Za-z0-9.]+$' -and $Username -notmatch '(^\.|\.$|\.\.)') }
        'Mail.ru' { return ($Username.Length -ge 5 -and $Username.Length -le 31 -and $Username -match '^[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9]$' -and $Username -notmatch '[._-]{2}') }
        'VK' { return ($Username.Length -ge 5 -and $Username.Length -le 32 -and $Username -match '^[A-Za-z0-9._]+$' -and $Username -notmatch '(^[._]|[._]$|\.\.|__)' -and $Username -notmatch '^\d+$') }
        'Outlook' { return ($Username.Length -ge 3 -and $Username.Length -le 64 -and $Username -match '^[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9]?$' -and $Username -notmatch '([._-]$|[._-]{2})') }
        'GitHub' { return ($Username.Length -ge 1 -and $Username.Length -le 39 -and $Username -match '^(?!-)(?!.*--)[A-Za-z0-9-]+(?<!-)$') }
# --- Discord Api
        'Discord' {
            $discordNameForFormat = $Username.ToLowerInvariant()
            return ($Username.Length -ge 2 -and $Username.Length -le 32 -and $Username -match '^[A-Za-z0-9_.]+$' -and $Username -notmatch '(^\.|\.$|\.\.)' -and $discordNameForFormat -notin @('discord','clyde','nitro','here','everyone','system'))
        }
        'YouTube' { return ($Username.Length -ge 3 -and $Username.Length -le 30 -and $Username -match '^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$' -and $Username -notmatch '\.\.') }
        'Telegram' { return ($Username.Length -ge 5 -and $Username.Length -le 32 -and $Username -match '^[A-Za-z][A-Za-z0-9_]*$') }
        'Steam' { return ($Username.Length -ge 3 -and $Username.Length -le 30 -and $Username -match '^[A-Za-z0-9][A-Za-z0-9_-]*$') }
        default { return ($Username.Length -ge 3 -and $Username.Length -le 32 -and $Username -match '^[A-Za-z0-9_.-]+$') }
    }
}

function Get-PlatformWebsiteUrl {
    param([string]$Platform, [string]$Username = '')
    $safeName = [uri]::EscapeDataString(([string]$Username).Trim())
    switch ($Platform) {
        'Roblox' { if ($Username) { return ('https://www.roblox.com/search/users?keyword=' + $safeName) }; return 'https://www.roblox.com/' }
        'Google' { return 'https://accounts.google.com/signup' }
        'Mail.ru' { return 'https://account.mail.ru/signup' }
        'VK' { if ($Username) { return ('https://vk.com/' + $safeName) }; return 'https://vk.com/' }
        'Outlook' { return 'https://signup.live.com/' }
        'GitHub' { if ($Username) { return ('https://github.com/' + $safeName) }; return 'https://github.com/signup' }
        'Discord' { return 'https://discord.com/register' }
        'YouTube' { if ($Username) { return ('https://www.youtube.com/@' + $safeName) }; return 'https://www.youtube.com/' }
        'Telegram' { if ($Username) { return ('https://t.me/' + $safeName) }; return 'https://telegram.org/' }
        'Steam' { return ('https://steamcommunity.com/id/' + ([string]$Username).Trim()) }
        default { return 'https://www.google.com/search?q=' + [uri]::EscapeDataString($Platform + ' username ' + $Username) }
    }
}

function Get-ShuffledArray {
    param([object[]]$Items)
    $array = @($Items).Clone()
    for ($i = $array.Length - 1; $i -gt 0; $i--) {
        $j = -1
        if ($i -lt 256) { try { $j = Get-CryptoRandomIndex ($i + 1) } catch { $j = -1 } }
        if ($j -lt 0) { $j = Get-Random -Minimum 0 -Maximum ($i + 1) }
        $temp = $array[$i]
        $array[$i] = $array[$j]
        $array[$j] = $temp
    }
    return $array
}

function New-InventedWord {
    param([int]$MinLength = 3, [int]$MaxLength = 9)
    if ($MinLength -lt 1) { $MinLength = 1 }
    if ($MaxLength -lt $MinLength) { $MaxLength = $MinLength }
    $onsets = $script:InventedOnsets
    $nuclei = $script:InventedNuclei
    $codas = $script:InventedCodas
    $last = ''
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $word = [string]$onsets[(Get-Random -Minimum 0 -Maximum $onsets.Count)] + [string]$nuclei[(Get-Random -Minimum 0 -Maximum $nuclei.Count)] + [string]$codas[(Get-Random -Minimum 0 -Maximum $codas.Count)]
        if ($word.Length -lt $MinLength -or (Get-Random -Minimum 0 -Maximum 3) -eq 0) {
            $word = $word + [string]$nuclei[(Get-Random -Minimum 0 -Maximum $nuclei.Count)] + [string]$codas[(Get-Random -Minimum 0 -Maximum $codas.Count)]
        }
        $last = $word
        if ($word.Length -ge $MinLength -and $word.Length -le $MaxLength) { break }
    }
    if ($last.Length -gt $MaxLength) { $last = $last.Substring(0, $MaxLength) }
    return ([string][char]::ToUpperInvariant($last[0]) + $last.Substring(1))
}

function Convert-ToLeetWord {
    param([string]$Word, [int]$MaxSubstitutions = 2)
    if ([string]::IsNullOrWhiteSpace($Word)) { return $Word }
    if ($MaxSubstitutions -lt 1) { return $Word }
    $map = @{ 'a'='4'; 'e'='3'; 'i'='1'; 'o'='0'; 's'='5'; 't'='7'; 'b'='8'; 'g'='6'; 'z'='2' }
    $chars = $Word.ToCharArray()
    $candidates = New-Object System.Collections.ArrayList
    for ($i = 1; $i -lt $chars.Length; $i++) {
        if ([char]::IsUpper($chars[$i])) { continue }
        $lower = [string]$chars[$i]
        if ($map.ContainsKey($lower)) { [void]$candidates.Add($i) }
    }
    if ($candidates.Count -eq 0) { return $Word }
    $take = [Math]::Min($MaxSubstitutions, $candidates.Count)
    $picked = @(Get-ShuffledArray -Items $candidates.ToArray()) | Select-Object -First $take
    foreach ($index in $picked) {
        $lower = [string][char]::ToLowerInvariant($chars[$index])
        $chars[$index] = [char]$map[$lower]
    }
    return (-join $chars)
}

# --- Генератор ников
function New-AdvancedCandidatePool {
    param(
        [string[]]$SelectedWordCategories,
        [string]$CustomWords,
        [string]$Style,
        [string]$Platform,
        [int]$MinLength,
        [int]$MaxLength,
        [int]$Count,
        [bool]$UseNumbers,
        [bool]$UseUnderscore,
        [bool]$OneWord,
        [bool]$TwoWords,
        [bool]$OnlyShort,
        [string[]]$ExcludeTokens,
        [hashtable]$ExcludeKeys,
        [bool]$InventedWords,
        [bool]$InventedPairs,
        [bool]$LeetWords,
        [bool]$RareShort,
        [bool]$Ordered,
        [bool]$RandomChars
    )
    if ($null -eq $ExcludeKeys) { $ExcludeKeys = @{} }
    if ($Count -lt 1) { $Count = 1 }
    $stats = @{ Attempts = 0; ByLength = 0; ByFormat = 0; ByExcludedToken = 0; ByDuplicate = 0; ByAlreadyUsed = 0 }

    $anchors = New-Object System.Collections.ArrayList
    $categoryWords = New-Object System.Collections.ArrayList
    foreach ($group in $SelectedWordCategories) {
        if ($script:MeaningGroups.ContainsKey($group)) {
            foreach ($word in $script:MeaningGroups[$group]) {
                $seed = Get-SeedForWord -Word $word -FallbackMeaning $group
                [void]$categoryWords.Add([pscustomobject]@{Word=[string]$seed.Word; Meaning=[string]$seed.Meaning; Category=$group})
            }
        }
    }
    foreach ($rawWord in ($CustomWords -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $word = Convert-ToNickToken $rawWord
        if ($word.Length -gt 0) { [void]$anchors.Add([pscustomobject]@{Word=$word; Meaning='ваше ключевое слово'; Category='Свои слова'}) }
    }

    $modifiers = @($script:Modifiers)
    if ($Style -and $Style -ne '— без стиля —' -and $script:StyleWords.ContainsKey($Style)) {
        foreach ($word in $script:StyleWords[$Style]) {
            $seed = Get-SeedForWord -Word $word -FallbackMeaning ('стиль: {0}' -f $Style)
            $modifiers += [pscustomobject]@{Word=[string]$seed.Word; Meaning=[string]$seed.Meaning}
        }
    }
    if ($Style -eq 'Двусловный') { $TwoWords = $true }

    $bases = New-Object System.Collections.ArrayList
    $secondParts = New-Object System.Collections.ArrayList
    if ($anchors.Count -gt 0) {
        foreach ($item in $anchors) { [void]$bases.Add($item) }
        foreach ($item in $modifiers) { [void]$secondParts.Add($item) }
        foreach ($item in $categoryWords) { [void]$secondParts.Add($item) }
    } else {
        foreach ($item in $categoryWords) { [void]$bases.Add($item) }
        foreach ($item in $modifiers) { [void]$secondParts.Add($item) }
    }
    $hasAnchors = $anchors.Count -gt 0
    $rareWords = @($script:RareShortWords)

    $maximum = $MaxLength
    if ($OnlyShort) { $maximum = [Math]::Min($maximum, 12) }
    $joiner = ''
    if ($UseUnderscore) { $joiner = '_' }

    $result = New-Object System.Collections.ArrayList
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $counters = @{
        Single = 0; Pair = 0; Invented = 0; InventedPair = 0; Leet = 0; Rare = 0; Number = 0; Random = 0
        SingleExhausted = $false; PairExhausted = $false; InventedExhausted = $false
        InventedPairExhausted = $false; LeetExhausted = $false; RareExhausted = $false
        NumberExhausted = $false; RandomExhausted = $false; PairCursor = 0
    }

    $tryAccept = {
        param([string]$RawName, [string]$Meaning, [string]$Category, [string]$Structure)
        $stats['Attempts'] = $stats['Attempts'] + 1
        $name = $RawName
        if ([string]::IsNullOrWhiteSpace($name)) { return $false }
        if ($name.Length -lt $MinLength -or $name.Length -gt $maximum) { $stats['ByLength'] = $stats['ByLength'] + 1; return $false }
        if (-not (Test-UsernameFormat -Username $name -Platform $Platform)) { $stats['ByFormat'] = $stats['ByFormat'] + 1; return $false }
        foreach ($token in $ExcludeTokens) {
            if (-not [string]::IsNullOrWhiteSpace($token) -and $name.IndexOf($token.Trim(), [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $stats['ByExcludedToken'] = $stats['ByExcludedToken'] + 1
                return $false
            }
        }
        if (-not $seen.Add($name)) { $stats['ByDuplicate'] = $stats['ByDuplicate'] + 1; return $false }
        if ($ExcludeKeys.ContainsKey((Get-HistoryKey -Name $name -Platform $Platform))) {
            $stats['ByAlreadyUsed'] = $stats['ByAlreadyUsed'] + 1
            return $false
        }
        [void]$result.Add([pscustomobject]@{
            Name = $name
            Platform = $Platform
            Meaning = $Meaning
            Category = $Category
            Structure = $Structure
            Status = 'Ожидает'
            Time = ''
            Reason = 'Ожидает проверки'
            Checked = $false
        })
        return $true
    }

    $fillSingle = {
        param([int]$StopAtTotal)
        if ($result.Count -ge $StopAtTotal) { return }
        if ($bases.Count -lt 1) {
            $budget = [Math]::Max(300, ($StopAtTotal - $result.Count) * 40)
            $attempts = 0
            $failStreak = 0
            while ($result.Count -lt $StopAtTotal -and $attempts -lt $budget -and $failStreak -lt 400) {
                $attempts++
                $word = New-InventedWord -MinLength ([Math]::Max(3, $MinLength)) -MaxLength $maximum
                if (& $tryAccept $word 'выдуманное слово' 'Выдуманные слова' 'Одно слово') {
                    $counters['Single'] = $counters['Single'] + 1
                    $failStreak = 0
                } else { $failStreak++ }
            }
            if ($result.Count -lt $StopAtTotal) { $counters['SingleExhausted'] = $true }
            return
        }
        $items = $bases.ToArray()
        if (-not $Ordered) { $items = Get-ShuffledArray -Items $items }
        foreach ($base in $items) {
            if ($result.Count -ge $StopAtTotal) { break }
            $word = [regex]::Replace([string]$base.Word, '[^A-Za-z0-9]', '')
            if ($word.Length -lt 1) { continue }
            if (& $tryAccept $word ([string]$base.Meaning) ([string]$base.Category) 'Одно слово') {
                $counters['Single'] = $counters['Single'] + 1
            }
        }
        if ($result.Count -lt $StopAtTotal) { $counters['SingleExhausted'] = $true }
    }

    $fillPair = {
        param([int]$StopAtTotal)
        if ($result.Count -ge $StopAtTotal) { return }
        $baseArray = @($bases.ToArray())
        $secondArray = @($secondParts.ToArray())
        if ($baseArray.Count -lt 1 -or $secondArray.Count -lt 1) {
            $budget = [Math]::Max(300, ($StopAtTotal - $result.Count) * 40)
            $attempts = 0
            $failStreak = 0
            while ($result.Count -lt $StopAtTotal -and $attempts -lt $budget -and $failStreak -lt 400) {
                $attempts++
                $left = New-InventedWord -MinLength 3 -MaxLength 9
                $right = New-InventedWord -MinLength 3 -MaxLength 9
                if (& $tryAccept ($left + $joiner + $right) 'два выдуманных слова' 'Двусловные' 'Два слова') {
                    $counters['Pair'] = $counters['Pair'] + 1
                    $failStreak = 0
                } else { $failStreak++ }
            }
            if ($result.Count -lt $StopAtTotal) { $counters['PairExhausted'] = $true }
            return
        }
        if ($Ordered) {
            $combos = $baseArray.Count * $secondArray.Count
            $total = $combos * 2
            while ($counters['PairCursor'] -lt $total -and $result.Count -lt $StopAtTotal) {
                $index = $counters['PairCursor']
                $counters['PairCursor'] = $index + 1
                $combo = [int][Math]::Floor($index / 2)
                $reverse = ($index % 2) -eq 1
                $baseItem = $baseArray[[int][Math]::Floor($combo / $secondArray.Count)]
                $secondItem = $secondArray[$combo % $secondArray.Count]
                $left = [regex]::Replace([string]$baseItem.Word, '[^A-Za-z0-9]', '')
                $right = [regex]::Replace([string]$secondItem.Word, '[^A-Za-z0-9]', '')
                if ($left.Length -lt 1 -or $right.Length -lt 1 -or $left -ieq $right) { continue }
                if ($reverse) {
                    $name = $right + $joiner + $left
                    $meaning = '{0} + {1}' -f [string]$secondItem.Meaning, [string]$baseItem.Meaning
                } else {
                    $name = $left + $joiner + $right
                    $meaning = '{0} + {1}' -f [string]$baseItem.Meaning, [string]$secondItem.Meaning
                }
                if (& $tryAccept $name $meaning 'Двусловные' 'Два слова') {
                    $counters['Pair'] = $counters['Pair'] + 1
                }
            }
            if ($result.Count -lt $StopAtTotal) { $counters['PairExhausted'] = $true }
            return
        }
        $budget = [Math]::Max(400, ($StopAtTotal - $result.Count) * 40)
        $attempts = 0
        $failStreak = 0
        while ($result.Count -lt $StopAtTotal -and $attempts -lt $budget -and $failStreak -lt 400) {
            $attempts++
            $baseItem = $baseArray[(Get-Random -Minimum 0 -Maximum $baseArray.Count)]
            $secondItem = $secondArray[(Get-Random -Minimum 0 -Maximum $secondArray.Count)]
            $left = [regex]::Replace([string]$baseItem.Word, '[^A-Za-z0-9]', '')
            $right = [regex]::Replace([string]$secondItem.Word, '[^A-Za-z0-9]', '')
            if ($left.Length -lt 1 -or $right.Length -lt 1 -or $left -ieq $right) { $failStreak++; continue }
            if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) {
                $name = $left + $joiner + $right
                $meaning = '{0} + {1}' -f [string]$baseItem.Meaning, [string]$secondItem.Meaning
            } else {
                $name = $right + $joiner + $left
                $meaning = '{0} + {1}' -f [string]$secondItem.Meaning, [string]$baseItem.Meaning
            }
            if (& $tryAccept $name $meaning 'Двусловные' 'Два слова') {
                $counters['Pair'] = $counters['Pair'] + 1
                $failStreak = 0
            } else { $failStreak++ }
        }
        if ($result.Count -lt $StopAtTotal) { $counters['PairExhausted'] = $true }
    }

    $fillInvented = {
        param([int]$StopAtTotal)
        if ($result.Count -ge $StopAtTotal) { return }
        $budget = [Math]::Max(300, ($StopAtTotal - $result.Count) * 40)
        $attempts = 0
        $failStreak = 0
        while ($result.Count -lt $StopAtTotal -and $attempts -lt $budget -and $failStreak -lt 400) {
            $attempts++
            $word = New-InventedWord -MinLength ([Math]::Max(3, $MinLength)) -MaxLength $maximum
            $structure = 'Одно слово'
            if ($hasAnchors) {
                $anchor = $bases[(Get-Random -Minimum 0 -Maximum $bases.Count)]
                $anchorWord = [regex]::Replace([string]$anchor.Word, '[^A-Za-z0-9]', '')
                if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) {
                    $name = $anchorWord + $joiner + $word
                    $meaning = '{0} + выдуманное слово' -f [string]$anchor.Meaning
                } else {
                    $name = $word + $joiner + $anchorWord
                    $meaning = 'выдуманное слово + {0}' -f [string]$anchor.Meaning
                }
                $structure = 'Два слова'
            } else {
                $name = $word
                $meaning = 'выдуманное слово'
            }
            if (& $tryAccept $name $meaning 'Выдуманные слова' $structure) {
                $counters['Invented'] = $counters['Invented'] + 1
                $failStreak = 0
            } else { $failStreak++ }
        }
        if ($result.Count -lt $StopAtTotal) { $counters['InventedExhausted'] = $true }
    }

    $fillInventedPair = {
        param([int]$StopAtTotal)
        if ($result.Count -ge $StopAtTotal) { return }
        $baseArray = @($bases.ToArray())
        $secondArray = @($secondParts.ToArray())
        $budget = [Math]::Max(300, ($StopAtTotal - $result.Count) * 40)
        $attempts = 0
        $failStreak = 0
        while ($result.Count -lt $StopAtTotal -and $attempts -lt $budget -and $failStreak -lt 400) {
            $attempts++
            $left = New-InventedWord -MinLength 3 -MaxLength 9
            $right = New-InventedWord -MinLength 3 -MaxLength 9
            $meaning = 'два выдуманных слова'
            if ($hasAnchors -and $baseArray.Count -ge 1) {
                $anchor = $baseArray[(Get-Random -Minimum 0 -Maximum $baseArray.Count)]
                $anchorWord = [regex]::Replace([string]$anchor.Word, '[^A-Za-z0-9]', '')
                if ($anchorWord.Length -ge 1) {
                    if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { $left = $anchorWord } else { $right = $anchorWord }
                    $meaning = '{0} + выдуманное слово' -f [string]$anchor.Meaning
                }
            } elseif ($baseArray.Count -ge 1 -and $secondArray.Count -ge 1 -and (Get-Random -Minimum 0 -Maximum 2) -eq 0) {
                $item = $secondArray[(Get-Random -Minimum 0 -Maximum $secondArray.Count)]
                $itemWord = [regex]::Replace([string]$item.Word, '[^A-Za-z0-9]', '')
                if ($itemWord.Length -ge 1) {
                    if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { $right = $itemWord } else { $left = $itemWord }
                    $meaning = 'выдуманное слово + {0}' -f [string]$item.Meaning
                }
            }
            if (& $tryAccept ($left + $joiner + $right) $meaning 'Выдуманные словосочетания' 'Два слова') {
                $counters['InventedPair'] = $counters['InventedPair'] + 1
                $failStreak = 0
            } else { $failStreak++ }
        }
        if ($result.Count -lt $StopAtTotal) { $counters['InventedPairExhausted'] = $true }
    }

    $fillLeet = {
        param([int]$StopAtTotal)
        if ($result.Count -ge $StopAtTotal) { return }
        $baseArray = @($bases.ToArray())
        $secondArray = @($secondParts.ToArray())
        $budget = [Math]::Max(300, ($StopAtTotal - $result.Count) * 40)
        $attempts = 0
        $failStreak = 0
        while ($result.Count -lt $StopAtTotal -and $attempts -lt $budget -and $failStreak -lt 400) {
            $attempts++
            $structure = 'Одно слово'
            $category = 'Замена символами'
            $meaning = 'замена букв цифрами'
            $sourceName = ''
            $mode = Get-Random -Minimum 0 -Maximum 3
            if ($baseArray.Count -ge 1 -and $secondArray.Count -ge 1 -and $mode -eq 1) {
                $baseItem = $baseArray[(Get-Random -Minimum 0 -Maximum $baseArray.Count)]
                $secondItem = $secondArray[(Get-Random -Minimum 0 -Maximum $secondArray.Count)]
                $left = [regex]::Replace([string]$baseItem.Word, '[^A-Za-z0-9]', '')
                $right = [regex]::Replace([string]$secondItem.Word, '[^A-Za-z0-9]', '')
                if ($left.Length -ge 1 -and $right.Length -ge 1 -and $left -ine $right) {
                    $sourceName = $left + $joiner + $right
                    $structure = 'Два слова'
                    $category = 'Двусловные'
                    $meaning = '{0} + {1} + замена символами' -f [string]$baseItem.Meaning, [string]$secondItem.Meaning
                }
            } elseif ($baseArray.Count -ge 1 -and $mode -eq 0) {
                $item = $baseArray[(Get-Random -Minimum 0 -Maximum $baseArray.Count)]
                $sourceName = [regex]::Replace([string]$item.Word, '[^A-Za-z0-9]', '')
                $meaning = '{0} + замена символами' -f [string]$item.Meaning
            }
            if ([string]::IsNullOrWhiteSpace($sourceName)) {
                $inventedWord = New-InventedWord -MinLength ([Math]::Max(3, $MinLength)) -MaxLength $maximum
                if ($hasAnchors -and $baseArray.Count -ge 1) {
                    $anchor = $baseArray[(Get-Random -Minimum 0 -Maximum $baseArray.Count)]
                    $anchorWord = [regex]::Replace([string]$anchor.Word, '[^A-Za-z0-9]', '')
                    if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { $sourceName = $anchorWord + $joiner + $inventedWord } else { $sourceName = $inventedWord + $joiner + $anchorWord }
                    $structure = 'Два слова'
                    $meaning = '{0} + выдуманное слово + замена символами' -f [string]$anchor.Meaning
                } else {
                    $sourceName = $inventedWord
                    $meaning = 'выдуманное слово + замена символами'
                }
                $category = 'Выдуманные слова'
            }
            $leet = Convert-ToLeetWord -Word $sourceName -MaxSubstitutions (Get-Random -Minimum 1 -Maximum 3)
            if ($leet -ceq $sourceName) { $failStreak++; continue }
            $structure = Get-NickStructure -Name $leet
            if (& $tryAccept $leet $meaning $category $structure) {
                $counters['Leet'] = $counters['Leet'] + 1
                $failStreak = 0
            } else { $failStreak++ }
        }
        if ($result.Count -lt $StopAtTotal) { $counters['LeetExhausted'] = $true }
    }

    $fillRare = {
        param([int]$StopAtTotal)
        if ($result.Count -ge $StopAtTotal) { return }
        $rareMax = [Math]::Min(6, $maximum)
        $rareMin = [Math]::Max(3, $MinLength)
        if ($rareMin -gt $rareMax) { $counters['RareExhausted'] = $true; return }
        $baseArray = @($bases.ToArray())
        $budget = [Math]::Max(300, ($StopAtTotal - $result.Count) * 40)
        $attempts = 0
        $failStreak = 0
        while ($result.Count -lt $StopAtTotal -and $attempts -lt $budget -and $failStreak -lt 400) {
            $attempts++
            $structure = 'Одно слово'
            $meaning = 'редкое короткое слово'
            if ($rareWords.Count -ge 1 -and (Get-Random -Minimum 0 -Maximum 4) -gt 0) {
                $name = [string]$rareWords[(Get-Random -Minimum 0 -Maximum $rareWords.Count)]
            } else {
                $name = New-InventedWord -MinLength 3 -MaxLength 6
            }
            if ($hasAnchors -and $baseArray.Count -ge 1) {
                $anchor = $baseArray[(Get-Random -Minimum 0 -Maximum $baseArray.Count)]
                $anchorWord = [regex]::Replace([string]$anchor.Word, '[^A-Za-z0-9]', '')
                if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) {
                    $name = $anchorWord + $joiner + $name
                    $meaning = '{0} + редкое короткое слово' -f [string]$anchor.Meaning
                } else {
                    $name = $name + $joiner + $anchorWord
                    $meaning = 'редкое короткое слово + {0}' -f [string]$anchor.Meaning
                }
                $structure = 'Два слова'
            }
            if ($name.Length -lt $rareMin -or $name.Length -gt $rareMax) { $failStreak++; continue }
            if (& $tryAccept $name $meaning 'Редкие короткие' $structure) {
                $counters['Rare'] = $counters['Rare'] + 1
                $failStreak = 0
            } else { $failStreak++ }
        }
        if ($result.Count -lt $StopAtTotal) { $counters['RareExhausted'] = $true }
    }

    $fillNumber = {
        param([int]$StopAtTotal)
        if ($result.Count -ge $StopAtTotal) { return }
        $sources = @($result.ToArray())
        $baseArray = @($bases.ToArray())
        $budget = [Math]::Max(300, ($StopAtTotal - $result.Count) * 40)
        $attempts = 0
        $failStreak = 0
        $cursor = 0
        while ($result.Count -lt $StopAtTotal -and $attempts -lt $budget -and $failStreak -lt 400) {
            $attempts++
            if ($sources.Count -gt 0) {
                if ($cursor -ge $sources.Count) { $cursor = 0 }
                $entry = $sources[$cursor]
                $cursor++
                $baseName = [string]$entry.Name
                $meaning = '{0} + число' -f [string]$entry.Meaning
                $category = [string]$entry.Category
                $structure = [string]$entry.Structure
            } else {
                if ($baseArray.Count -ge 1) {
                    $item = $baseArray[(Get-Random -Minimum 0 -Maximum $baseArray.Count)]
                    $baseName = [regex]::Replace([string]$item.Word, '[^A-Za-z0-9]', '')
                    $meaning = '{0} + число' -f [string]$item.Meaning
                    $category = [string]$item.Category
                } else {
                    $baseName = New-InventedWord -MinLength ([Math]::Max(3, $MinLength)) -MaxLength $maximum
                    $meaning = 'выдуманное слово + число'
                    $category = 'Выдуманные слова'
                }
                $structure = 'Одно слово'
            }
            if ([string]::IsNullOrWhiteSpace($baseName)) { $failStreak++; continue }
            $number = Get-Random -Minimum 2 -Maximum 10000
            $withNumber = $baseName + $number
            if ($withNumber.Length -gt $maximum) { $failStreak++; continue }
            if (& $tryAccept $withNumber $meaning $category $structure) {
                $counters['Number'] = $counters['Number'] + 1
                $failStreak = 0
            } else { $failStreak++ }
        }
        if ($result.Count -lt $StopAtTotal) { $counters['NumberExhausted'] = $true }
    }

    $fillRandom = {
        param([int]$StopAtTotal)
        if ($result.Count -ge $StopAtTotal) { return }
        $budget = [Math]::Max(300, ($StopAtTotal - $result.Count) * 40)
        $attempts = 0
        $failStreak = 0
        $letters = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
        while ($result.Count -lt $StopAtTotal -and $attempts -lt $budget -and $failStreak -lt 400) {
            $attempts++
            $partCount = 1
            if ($joiner -and (Get-Random -Minimum 0 -Maximum 2) -eq 0) { $partCount = 2 }
            $parts = @()
            for ($partIndex = 0; $partIndex -lt $partCount; $partIndex++) {
                $partLen = Get-Random -Minimum ([Math]::Max(2, $MinLength)) -Maximum ([Math]::Max(4, $maximum + 1))
                $chars = New-Object System.Collections.ArrayList
                for ($charIndex = 0; $charIndex -lt $partLen; $charIndex++) {
                    [void]$chars.Add([string]$letters[(Get-Random -Minimum 0 -Maximum $letters.Length)])
                }
                $parts += (-join $chars.ToArray())
            }
            $name = $parts -join $joiner
            if ($parts.Count -eq 1 -and -not $joiner -and $name.Length -gt 4 -and (Get-Random -Minimum 0 -Maximum 4) -eq 0) {
                $name = $name.Insert((Get-Random -Minimum 2 -Maximum ($name.Length - 1)), '_')
            }
            $name = [char]::ToUpperInvariant($name[0]) + $name.Substring(1)
            if (& $tryAccept $name 'случайный набор символов' 'Случайные символы' (Get-NickStructure -Name $name)) {
                $counters['Random'] = $counters['Random'] + 1
                $failStreak = 0
            } else { $failStreak++ }
        }
        if ($result.Count -lt $StopAtTotal) { $counters['RandomExhausted'] = $true }
    }

    $activeSources = New-Object System.Collections.ArrayList
    if ($OneWord) { [void]$activeSources.Add('Single') }
    if ($TwoWords) { [void]$activeSources.Add('Pair') }
    if ($InventedWords) { [void]$activeSources.Add('Invented') }
    if ($InventedPairs) { [void]$activeSources.Add('InventedPair') }
    if ($LeetWords) { [void]$activeSources.Add('Leet') }
    if ($RareShort) { [void]$activeSources.Add('Rare') }
    if ($RandomChars) { [void]$activeSources.Add('Random') }
    if ($UseNumbers) { [void]$activeSources.Add('Number') }
    if ($activeSources.Count -eq 0) { [void]$activeSources.Add('Single') }

    $sourceBlocks = @{
        Single = $fillSingle; Pair = $fillPair; Invented = $fillInvented
        InventedPair = $fillInventedPair; Leet = $fillLeet; Rare = $fillRare; Number = $fillNumber
        Random = $fillRandom
    }

    $perSource = [int][Math]::Ceiling($Count / $activeSources.Count)
    if ($perSource -lt 1) { $perSource = 1 }
    $target = 0
    foreach ($sourceName in $activeSources) {
        if ($result.Count -ge $Count) { break }
        $target = $target + $perSource
        if ($target -gt $Count) { $target = $Count }
        & $sourceBlocks[[string]$sourceName] $target
    }
    for ($pass = 0; $pass -lt 4 -and $result.Count -lt $Count; $pass++) {
        $progressed = $false
        $before = $result.Count
        foreach ($sourceName in $activeSources) {
            if ($counters[[string]$sourceName + 'Exhausted']) { continue }
            if ($result.Count -ge $Count) { break }
            & $sourceBlocks[[string]$sourceName] $Count
        }
        if ($result.Count -gt $before) { $progressed = $true }
        if (-not $progressed) { break }
    }

    foreach ($key in @('Single','Pair','Invented','InventedPair','Leet','Rare','Number','Random')) {
        $stats[$key] = $counters[$key]
    }
    $script:GenerationStats = $stats
    if ($result.Count -eq 0) { return @() }
    if ($Ordered) {
        $take = [Math]::Min($Count, $result.Count)
        return @($result | Select-Object -First $take)
    }
    $shuffled = @(Get-ShuffledArray -Items $result.ToArray())
    $take = [Math]::Min($Count, $shuffled.Count)
    return @($shuffled | Select-Object -First $take)
}

# --- Интерфейс: окно и заголовок
$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = ('Universal Username Finder v{0}' -f $script:AppVersion)
$script:Form.StartPosition = 'CenterScreen'
$designWindowSize = New-Object System.Drawing.Size(1480, 1040)
$designMinimumSize = New-Object System.Drawing.Size(1240, 960)
$minimumWidth = 1240
$minimumHeight = 960
$windowWidth = 1480
$windowHeight = 1010
try {
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $areaWidth = [int](@($workingArea.Width)[0])
    $areaHeight = [int](@($workingArea.Height)[0])
    if ($areaWidth -ge 600 -and $areaHeight -ge 480) {
        $minimumWidth = [int][Math]::Min([int]$designMinimumSize.Width, [Math]::Max(760, $areaWidth - 32))
        $minimumHeight = [int][Math]::Min([int]$designMinimumSize.Height, [Math]::Max(520, $areaHeight - 32))
        $windowWidth = [int][Math]::Max($minimumWidth, [int][Math]::Min([int]$designWindowSize.Width, $areaWidth))
        $windowHeight = [int][Math]::Max($minimumHeight, [int][Math]::Min([int]$designWindowSize.Height, $areaHeight))
        if ($windowWidth -lt $minimumWidth) { $windowWidth = $minimumWidth }
        if ($windowHeight -lt $minimumHeight) { $windowHeight = $minimumHeight }
    }
} catch { }
$script:Form.MinimumSize = New-Object System.Drawing.Size($minimumWidth, $minimumHeight)
$script:Form.Size = New-Object System.Drawing.Size($windowWidth, $windowHeight)
$script:Form.BackColor = [System.Drawing.Color]::FromArgb(15,19,27)
$script:Form.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
$script:Form.Font = New-Object System.Drawing.Font($script:UiFontFamily, 9)
$script:Form.FormBorderStyle = 'None'
$script:Form.MinimizeBox = $true
$script:Form.MaximizeBox = $true
$script:AppLogoImage = $null
$script:AppIconCached = $null
$script:AppLogoB64 = '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'
$script:AppIconB64 = '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'
$script:UufDwmAvailable = $false
try {
    $null = Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class UufDwmCorners {
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    public static void Round(IntPtr hwnd) {
        int preference = 2;
        DwmSetWindowAttribute(hwnd, 33, ref preference, 4);
    }
}

public static class UufUser32 {
    [DllImport("user32.dll")]
    public static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int newLong);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint flags);
}
'@
    $script:UufDwmAvailable = $true
} catch { }

function Set-WindowChrome {
    param([object]$Window)
    if ($null -eq $Window) { return }
    try {
        if ($script:AppIconCached) { $Window.Icon = $script:AppIconCached; $Window.ShowIcon = $true }
    } catch { }
    if ($script:UufDwmAvailable) {
        try { $Window.Add_Load({ param($sender,$e) try { [UufDwmCorners]::Round($sender.Handle) } catch { } }) } catch { }
    }
}

function Set-ButtonEdgeStyle {
    param([object]$Root)
    if ($null -eq $Root) { return }
    foreach ($child in @($Root.Controls)) {
        if ($child -is [System.Windows.Forms.Button]) {
            try {
                $child.FlatAppearance.BorderSize = 1
                $child.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(64,78,104)
            } catch { }
        }
        if ($child.Controls.Count -gt 0) { Set-ButtonEdgeStyle -Root $child }
    }
}

try {
    $assetsDirectory = [System.IO.Path]::Combine((Get-AppDirectory), 'assets')
    $logoPngPath = [System.IO.Path]::Combine($assetsDirectory, 'logo.png')
    if ([System.IO.File]::Exists($logoPngPath)) { $script:AppLogoImage = [System.Drawing.Image]::FromFile($logoPngPath) }
    $uufIcoPath = [System.IO.Path]::Combine($assetsDirectory, 'uuf.ico')
    if ([System.IO.File]::Exists($uufIcoPath)) { $script:AppIconCached = New-Object System.Drawing.Icon($uufIcoPath) }
} catch { }
if ((-not $script:AppLogoImage) -and $script:AppLogoB64) {
    try {
        $logoMemoryStream = New-Object System.IO.MemoryStream -ArgumentList @(,[System.Convert]::FromBase64String($script:AppLogoB64))
        $script:AppLogoStream = $logoMemoryStream
        $script:AppLogoImage = [System.Drawing.Image]::FromStream($logoMemoryStream)
    } catch { }
}
if ((-not $script:AppIconCached) -and $script:AppIconB64) {
    try {
        $iconMemoryStream = New-Object System.IO.MemoryStream -ArgumentList @(,[System.Convert]::FromBase64String($script:AppIconB64))
        $script:AppIconStream = $iconMemoryStream
        $script:AppIconCached = New-Object System.Drawing.Icon -ArgumentList $iconMemoryStream
    } catch { }
}
Set-WindowChrome -Window $script:Form

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(1480, 92)
$header.Anchor = 'Top, Left, Right'
$header.BackColor = [System.Drawing.Color]::FromArgb(23,30,42)
$script:Form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = ('UNIVERSAL USERNAME FINDER  •  v{0}' -f $script:AppVersion)
$title.Font = New-Object System.Drawing.Font($script:UiFontFamily, 17, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(112,164,255)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(66, 14)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Автоматическая генерация и проверка имён для популярных платформ'
$subtitle.Font = New-Object System.Drawing.Font($script:UiFontFamily, 9)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(177,188,207)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(66, 50)
$header.Controls.Add($subtitle)

$script:ApiDocsButton = New-Object System.Windows.Forms.Button
$script:ApiDocsButton.Text = 'Помощь'
$script:ApiDocsButton.Location = New-Object System.Drawing.Point(1037, 34)
$script:ApiDocsButton.Size = New-Object System.Drawing.Size(100, 38)
$script:ApiDocsButton.Anchor = 'Top, Right'
$script:ApiDocsButton.FlatStyle = 'Flat'
$script:ApiDocsButton.FlatAppearance.BorderSize = 0
$script:ApiDocsButton.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
$script:ApiDocsButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
$header.Controls.Add($script:ApiDocsButton)
if ($script:AppLogoImage) {
    $headerLogo = New-Object System.Windows.Forms.PictureBox
    $headerLogo.Location = New-Object System.Drawing.Point(14, 22)
    $headerLogo.Size = New-Object System.Drawing.Size(44, 44)
    $headerLogo.SizeMode = 'Zoom'
    $headerLogo.BackColor = [System.Drawing.Color]::Transparent
    $headerLogo.Anchor = 'Top, Left'
    $headerLogo.Image = $script:AppLogoImage
    $header.Controls.Add($headerLogo)
}
$script:HistoryButton = New-Object System.Windows.Forms.Button
$script:HistoryButton.Text = 'Свободные ники'
$script:HistoryButton.Location = New-Object System.Drawing.Point(1147, 34)
$script:HistoryButton.Size = New-Object System.Drawing.Size(150, 38)
$script:HistoryButton.Anchor = 'Top, Right'
$script:HistoryButton.FlatStyle = 'Flat'
$script:HistoryButton.FlatAppearance.BorderSize = 0
$script:HistoryButton.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
$script:HistoryButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
$header.Controls.Add($script:HistoryButton)
$script:AccountButton = New-Object System.Windows.Forms.Button
$script:AccountButton.Text = 'Регистрация и пароль'
$script:AccountButton.Location = New-Object System.Drawing.Point(1307, 34)
$script:AccountButton.Size = New-Object System.Drawing.Size(167, 38)
$script:AccountButton.Anchor = 'Top, Right'
$script:AccountButton.FlatStyle = 'Flat'
$script:AccountButton.FlatAppearance.BorderSize = 0
$script:AccountButton.BackColor = [System.Drawing.Color]::FromArgb(67,123,235)
$script:AccountButton.ForeColor = [System.Drawing.Color]::FromArgb(255,255,255)
$script:AccountButton.Font = New-Object System.Drawing.Font($script:UiFontFamily, 9.5, [System.Drawing.FontStyle]::Bold)
$script:AccountButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$header.Controls.Add($script:AccountButton)

# --- Интерфейс: кастомная строка заголовка
$script:UufEdgeColor = [System.Drawing.Color]::FromArgb(15,19,27)
$uufCaptionMouseDown = {
    param($sender,$e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    try {
        [void][UufUser32]::ReleaseCapture()
        [void][UufUser32]::SendMessage($script:Form.Handle, 0x00A1, [IntPtr]2, [IntPtr]::Zero)
    } catch { }
}
$uufResizeEdgeMouseDown = {
    param($sender,$e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $hit = [int]$sender.Tag
    if ($sender.Name -eq 'ResizeEdgeLeft' -and $sender.Height - $e.Y -le 18) { $hit = 16 }
    if ($sender.Name -eq 'ResizeEdgeRight' -and $sender.Height - $e.Y -le 18) { $hit = 17 }
    if ($sender.Name -eq 'ResizeEdgeBottom') {
        if ($e.X -le 18) { $hit = 16 }
        if ($sender.Width - $e.X -le 18) { $hit = 17 }
    }
    try {
        [void][UufUser32]::ReleaseCapture()
        [void][UufUser32]::SendMessage($script:Form.Handle, 0x00A1, [IntPtr]$hit, [IntPtr]::Zero)
    } catch { }
}
function New-UufCaptionButton {
    param([string]$Name, [int]$CodePoint, [int]$X)
    $captionButton = New-Object System.Windows.Forms.Button
    $captionButton.Name = $Name
    $captionButton.Text = [string][char]$CodePoint
    $captionButton.Font = New-Object System.Drawing.Font('Segoe MDL2 Assets', 9)
    $captionButton.Location = New-Object System.Drawing.Point($X, 0)
    $captionButton.Size = New-Object System.Drawing.Size(46, 26)
    $captionButton.Anchor = 'Top, Right'
    $captionButton.FlatStyle = 'Flat'
    $captionButton.FlatAppearance.BorderSize = 0
    $captionButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(38,48,68)
    $captionButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(30,38,54)
    $captionButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(23,30,42)
    $captionButton.UseVisualStyleBackColor = $false
    $captionButton.BackColor = [System.Drawing.Color]::FromArgb(23,30,42)
    $captionButton.ForeColor = [System.Drawing.Color]::FromArgb(196,206,224)
    $captionButton.TabStop = $false
    $header.Controls.Add($captionButton)
    return $captionButton
}
function New-UufResizeEdge {
    param([string]$Name,[int]$X,[int]$Y,[int]$W,[int]$H,[string]$EdgeAnchor,[object]$EdgeCursor,[int]$HitTest)
    $edge = New-Object System.Windows.Forms.Panel
    $edge.Name = $Name
    $edge.Location = New-Object System.Drawing.Point($X,$Y)
    $edge.Size = New-Object System.Drawing.Size($W,$H)
    $edge.Anchor = $EdgeAnchor
    $edge.Cursor = $EdgeCursor
    $edge.BackColor = $script:UufEdgeColor
    $edge.Tag = $HitTest
    $edge.Add_MouseDown($uufResizeEdgeMouseDown)
    $script:Form.Controls.Add($edge)
    $script:Form.Controls.SetChildIndex($edge, 0)
    return $edge
}
$script:MinimizeButton = New-UufCaptionButton 'MinimizeButton' 0xE921 1336
$script:MaximizeButton = New-UufCaptionButton 'MaximizeButton' 0xE922 1382
$script:CloseButton = New-UufCaptionButton 'CloseButton' 0xE8BB 1428
$script:CloseButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(196,43,28)
$script:CloseButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(179,37,24)
$script:MinimizeButton.Add_Click({ $script:Form.WindowState = 'Minimized' })
$script:MaximizeButton.Add_Click({ if ($script:Form.WindowState -eq 'Maximized') { $script:Form.WindowState = 'Normal' } else { $script:Form.WindowState = 'Maximized' } })
$script:CloseButton.Add_Click({ $script:Form.Close() })
$script:Form.Add_Resize({ if ($script:MaximizeButton) { if ($script:Form.WindowState -eq 'Maximized') { $script:MaximizeButton.Text = [string][char]0xE923 } else { $script:MaximizeButton.Text = [string][char]0xE922 } } })
$script:Form.Add_Load({
    try { $script:Form.MaximizedBounds = [System.Windows.Forms.Screen]::FromHandle($script:Form.Handle).WorkingArea } catch { }
    try {
        $windowStyle = [UufUser32]::GetWindowLong($script:Form.Handle, -16)
        [void][UufUser32]::SetWindowLong($script:Form.Handle, -16, ($windowStyle -bor 0x00040000 -bor 0x00020000 -bor 0x00010000 -bor 0x00080000))
        [void][UufUser32]::SetWindowPos($script:Form.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x0027)
    } catch { }
})
$header.Add_MouseDown($uufCaptionMouseDown)
$title.Add_MouseDown($uufCaptionMouseDown)
$subtitle.Add_MouseDown($uufCaptionMouseDown)
if ($headerLogo) { $headerLogo.Add_MouseDown($uufCaptionMouseDown) }
# --- Полка шапки: подгоняем под фактическую ширину окна, чтобы кнопки не вылезали за край
try { $header.Width = [Math]::Max(880,[int]$script:Form.ClientSize.Width) } catch { }

# --- Интерфейс: левая панель
$left = New-Object System.Windows.Forms.Panel
$left.Location = New-Object System.Drawing.Point(14, 104)
$left.Size = New-Object System.Drawing.Size(390, [Math]::Max(320,[int]$script:Form.ClientSize.Height - 114))
$left.Anchor = 'Top, Bottom, Left'
$left.BackColor = [System.Drawing.Color]::FromArgb(23,30,42)
$left.AutoScroll = $true
$script:Form.Controls.Add($left)

function Get-PlatformNickInput {
    param([string]$Platform,[string]$Raw)
    $trimmed = ([string]$Raw).Trim()
    $domain = Get-PlatformDomain -Platform $Platform
    if ($domain -and $trimmed -match ('(?i)@' + [regex]::Escape($domain) + '$')) { $trimmed = $trimmed.Substring(0, $trimmed.LastIndexOf('@')) }
    return $trimmed
}

function Copy-UufTextToClipboard {
    param([string]$Text,[string]$Context='копирование')
    if ($null -eq $Text) { $Text = '' }
    for ($clipAttempt = 1; $clipAttempt -le 6; $clipAttempt++) {
        try { [System.Windows.Forms.Clipboard]::SetText($Text); return $true } catch { Start-Sleep -Milliseconds (50 * $clipAttempt) }
    }
    Add-Diagnostic ('Буфер обмена занят другой программой (' + $Context + ') — копирование не выполнено, попробуй ещё раз через секунду.')
    return $false
}

function Set-UufTabStyle {
    param($Tabs,[int]$TabWidth)
    $Tabs.Appearance = 'FlatButtons'
    $Tabs.ItemSize = New-Object System.Drawing.Size($TabWidth, 30)
    $Tabs.Padding = New-Object System.Drawing.Point(12, 3)
    $Tabs.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $Tabs.DrawMode = 'OwnerDrawFixed'
    $Tabs.Add_DrawItem({
        param($tabSender,$tabArgs)
        try {
            if ($null -eq $tabArgs -or $null -eq $tabArgs.Graphics) { return }
            if ($null -eq $tabSender -or $tabSender.TabPages.Count -lt 1) { return }
            $tabIndex = [int]$tabArgs.Index
            if ($tabIndex -lt 0 -or $tabIndex -ge $tabSender.TabPages.Count) { return }
            $tabBounds = $tabArgs.Bounds
            $tabG = $tabArgs.Graphics
            $tabSelected = ($tabSender.SelectedIndex -eq $tabIndex)
            if ($tabSelected) { $tabBack = [System.Drawing.Color]::FromArgb(44,56,82) } else { $tabBack = [System.Drawing.Color]::FromArgb(26,33,47) }
            $tabBrush = New-Object System.Drawing.SolidBrush($tabBack)
            $tabG.FillRectangle($tabBrush, $tabBounds)
            $tabBrush.Dispose()
            if ($tabSelected) {
                $tabAccent = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(129,108,255))
                $tabG.FillRectangle($tabAccent, $tabBounds.X, ($tabBounds.Bottom - 3), $tabBounds.Width, 3)
                $tabAccent.Dispose()
            }
            if ($tabSelected) { $tabText = [System.Drawing.Color]::FromArgb(235,240,248) } else { $tabText = [System.Drawing.Color]::FromArgb(148,161,186) }
            $tabFlags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis
            [System.Windows.Forms.TextRenderer]::DrawText($tabG, [string]$tabSender.TabPages[$tabIndex].Text, $tabSender.Font, $tabBounds, $tabText, $tabFlags)
        } catch { }
    })
}

function Add-UiLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width=350, [int]$Height=22, [System.Windows.Forms.Control]$Parent=$left)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(203,213,228)
    $Parent.Controls.Add($label)
    return $label
}
function Add-UiButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width=350, [bool]$Primary=$false, [int]$Height=35, [System.Windows.Forms.Control]$Parent=$left)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, $Height)
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($Primary) {
        $button.BackColor = [System.Drawing.Color]::FromArgb(93,73,222)
        $button.ForeColor = [System.Drawing.Color]::White
    } else {
        $button.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
        $button.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    }
    $Parent.Controls.Add($button)
    return $button
}
function New-TextBox {
    param([int]$X,[int]$Y,[int]$Width,[int]$Height=27,[string]$Placeholder='')
    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point($X,$Y)
    $box.Size = New-Object System.Drawing.Size($Width,$Height)
    $box.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $box.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $box.BorderStyle = 'FixedSingle'
    if ($Placeholder) {
        $box.Tag = $Placeholder
        $box.Text = $Placeholder
        $box.ForeColor = [System.Drawing.Color]::FromArgb(149,164,187)
        $box.Add_GotFocus({
            $hint = [string]$this.Tag
            if ($hint -and $this.Text -eq $hint) {
                $this.Text = ''
                $this.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
            }
        })
        $box.Add_LostFocus({
            $hint = [string]$this.Tag
            if ($hint -and [string]::IsNullOrWhiteSpace($this.Text)) {
                $this.Text = $hint
                $this.ForeColor = [System.Drawing.Color]::FromArgb(149,164,187)
            }
        })
    }
    $left.Controls.Add($box)
    return $box
}
function Get-TextBoxValue {
    param($Box)
    if (-not $Box) { return '' }
    $value = [string]$Box.Text
    $hint = [string]$Box.Tag
    if ($hint -and $value -eq $hint) { return '' }
    return $value
}
function New-CheckBox {
    param([string]$Text,[int]$X,[int]$Y,[int]$Width=170,[bool]$Checked=$false)
    $box = New-Object System.Windows.Forms.CheckBox
    $box.Text = $Text
    $box.Location = New-Object System.Drawing.Point($X,$Y)
    $box.Size = New-Object System.Drawing.Size($Width,23)
    $box.ForeColor = [System.Drawing.Color]::FromArgb(203,213,228)
    $box.Checked = $Checked
    $left.Controls.Add($box)
    return $box
}
function New-NumberBox {
    param([int]$X,[int]$Y,[int]$Width,[int]$Min,[int]$Max,[int]$Value)
    $box = New-Object System.Windows.Forms.NumericUpDown
    $box.Location = New-Object System.Drawing.Point($X,$Y)
    $box.Size = New-Object System.Drawing.Size($Width,25)
    $box.Minimum = $Min
    $box.Maximum = $Max
    $box.Value = $Value
    $box.BackColor = [System.Drawing.Color]::FromArgb(32,41,56)
    $box.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $left.Controls.Add($box)
    return $box
}

Add-UiLabel 'ЕДИНЫЙ ВЫБОР КАТЕГОРИЙ НИКНЕЙМОВ' 14 12 355 22 | Out-Null
$script:CategoryList = New-Object System.Windows.Forms.CheckedListBox
$script:CategoryList.Location = New-Object System.Drawing.Point(14, 36)
$script:CategoryList.Size = New-Object System.Drawing.Size(350, 306)
$script:CategoryList.CheckOnClick = $true
$script:CategoryList.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:CategoryList.ForeColor = [System.Drawing.Color]::FromArgb(225,232,242)
$script:CategoryList.BorderStyle = 'FixedSingle'
$script:CategoryList.Font = New-Object System.Drawing.Font($script:UiFontFamily, 10)
$script:CategoryList.IntegralHeight = $false
$script:CategoryList.HorizontalScrollbar = $true
[void]$script:CategoryList.Items.AddRange([object[]]@($script:WordCategories | Sort-Object))
for ($categoryIndex = 0; $categoryIndex -lt $script:CategoryList.Items.Count; $categoryIndex++) {
    $script:CategoryList.SetItemChecked($categoryIndex, $true)
}
$left.Controls.Add($script:CategoryList)

$script:CheckAllCategoriesButton = Add-UiButton 'Выделить все' 14 340 170 $false 24
$script:UncheckAllCategoriesButton = Add-UiButton 'Снять все' 194 340 170 $false 24
$script:CheckAllCategoriesButton.Add_Click({
    for ($i = 0; $i -lt $script:CategoryList.Items.Count; $i++) {
        $script:CategoryList.SetItemChecked($i, $true)
    }
})
$script:UncheckAllCategoriesButton.Add_Click({
    for ($i = 0; $i -lt $script:CategoryList.Items.Count; $i++) {
        $script:CategoryList.SetItemChecked($i, $false)
    }
})

Add-UiLabel 'Стиль слова' 14 372 150 22 | Out-Null
$script:StyleBox = New-Object System.Windows.Forms.ComboBox
$script:StyleBox.Location = New-Object System.Drawing.Point(14,396)
$script:StyleBox.Size = New-Object System.Drawing.Size(350,27)
$script:StyleBox.DropDownStyle = 'DropDownList'
$script:StyleBox.BackColor = [System.Drawing.Color]::FromArgb(32,41,56)
$script:StyleBox.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
[void]$script:StyleBox.Items.AddRange([object[]]@('Аниме','Готический','Двусловный','Древний мир','Киберспортивный','Космический','Короткий','Латинский','Милый','Минималистичный','Морской','Неоновый','Природный','Редкий','Скандинавский','Тёмный','Футуристический','Хардкорный','Эстетичный','— без стиля —'))
$script:StyleBox.SelectedItem = '— без стиля —'
$left.Controls.Add($script:StyleBox)

Add-UiLabel 'Свои слова через запятую' 14 431 350 22 | Out-Null
$script:CustomBox = New-TextBox 14 454 350 27 'Pixel, Void, Storm'
Add-UiLabel 'Ручные ники для проверки' 14 483 350 18 | Out-Null
$script:ManualNickBox = New-TextBox 14 505 350 66 'каждый с новой строки или через запятую'
$script:ManualNickBox.Multiline = $true
$script:ManualNickBox.ScrollBars = 'Vertical'

Add-UiLabel 'НАСТРОЙКИ ГЕНЕРАЦИИ' 14 581 350 22 | Out-Null
Add-UiLabel 'Количество' 14 605 90 18 | Out-Null
$script:CountBox = New-NumberBox 14 624 90 5 2000 40
Add-UiLabel 'Мин. длина' 120 605 90 18 | Out-Null
$script:MinLengthBox = New-NumberBox 120 624 80 1 64 3
Add-UiLabel 'Макс. длина' 216 605 100 18 | Out-Null
$script:MaxLengthBox = New-NumberBox 216 624 80 1 64 25

$script:NumbersCheck = New-CheckBox 'Использовать цифры' 14 659 170 $false
$script:UnderscoreCheck = New-CheckBox 'Разделитель _' 194 659 170 $false
$script:OneWordCheck = New-CheckBox 'Однословные ники' 14 683 180 $true
$script:TwoWordsCheck = New-CheckBox 'Два осмысленных слова' 194 683 170 $false
$script:InventedWordsCheck = New-CheckBox 'Выдуманные слова' 14 707 180 $true
$script:InventedPairsCheck = New-CheckBox 'Выдуманные сочетания' 194 707 170 $false
$script:LeetCheck = New-CheckBox 'Замена символами' 14 731 180 $false
$script:RareShortCheck = New-CheckBox 'Редкие короткие (3-6)' 194 731 170 $true
$script:ShortOnlyCheck = New-CheckBox 'Только короткие (≤12)' 14 755 180 $true
$script:ExcludeCheckedCheck = New-CheckBox 'Исключать проверенные' 194 755 170 $true
$script:OnlyFreeCheck = New-CheckBox 'Показывать свободные' 14 779 180 $false
$script:OrderedCheck = New-CheckBox 'Генерация по порядку' 194 779 170 $false
$script:RandomCharsCheck = New-CheckBox 'Случайные символы' 14 803 180 $true

Add-UiLabel 'Исключить слова/части ника (пример: xxx, test, 123)' 14 835 350 20 | Out-Null
$script:ExcludeBox = New-TextBox 14 856 350 27 ''
Add-UiLabel 'Пауза (мс)' 14 891 110 18 | Out-Null
Add-UiLabel 'Тайм-аут (мс)' 134 891 110 18 | Out-Null
Add-UiLabel 'Потоки' 254 891 110 18 | Out-Null
$script:DelayBox = New-NumberBox 14 910 110 500 15000 700
$script:TimeoutBox = New-NumberBox 134 910 110 1000 30000 8000
$script:ThreadsBox = New-NumberBox 254 910 110 1 8 2
$script:ThreadsLabel = Add-UiLabel 'Рекомендуется 2–4 потока. Пауза адаптивная: растёт при HTTP 429 и снижается после успехов.' 14 943 350 40

$script:GenerateButton = Add-UiButton 'Сгенерировать и проверить' 14 991 350 $true 37
$script:StartButton = Add-UiButton '▶  Найти свободные' 14 1034 350 $true 37
$script:StartButton.Visible = $false
$script:StopButton = Add-UiButton '■  Остановить проверку' 14 1034 350 $false 35
$script:StopButton.Enabled = $false
$script:RetryButton = Add-UiButton '↻  Повторить ошибки' 14 1077 170 $false 33
$script:ClearButton = Add-UiButton '✕  Очистить результаты' 194 1077 170 $false 33
$script:SaveButton = Add-UiButton '↓  TXT свободные' 14 1117 170 $false 33
$script:CsvButton = Add-UiButton '↓  CSV все результаты' 194 1117 170 $false 33
$script:CopyButton = Add-UiButton '⧉  Копировать свободные' 14 1157 350 $false 33
$script:CheckedNamesButton = Add-UiButton '≡  Проверенные ники (0)' 14 1197 350 $false 33
$script:ConnectionTestButton = Add-UiButton '⇄  Проверка соединения' 14 1237 350 $false 33

$right = New-Object System.Windows.Forms.Panel
$right.Location = New-Object System.Drawing.Point(418, 104)
$right.Size = New-Object System.Drawing.Size(1040, 926)  # design size; below, after all children are added, snapped to the client
$right.Anchor = 'Top, Bottom, Left, Right'
$right.BackColor = [System.Drawing.Color]::FromArgb(23,30,42)
$script:Form.Controls.Add($right)

$script:StatTotal = New-Object System.Windows.Forms.Label
$script:StatFree = New-Object System.Windows.Forms.Label
$script:StatTaken = New-Object System.Windows.Forms.Label
$script:StatInvalid = New-Object System.Windows.Forms.Label
$script:StatErrors = New-Object System.Windows.Forms.Label
$script:StatChecked = New-Object System.Windows.Forms.Label
$statLabels = @($script:StatTotal,$script:StatChecked,$script:StatFree,$script:StatTaken,$script:StatInvalid,$script:StatErrors)
$script:StatLabels = $statLabels
$statTexts = @('Всего: 0','Проверено: 0','Свободно: 0','Занято: 0','Недопустимо: 0','Ошибки: 0')
$statColors = @([System.Drawing.Color]::White,[System.Drawing.Color]::FromArgb(200,210,226),[System.Drawing.Color]::FromArgb(99,222,151),[System.Drawing.Color]::FromArgb(245,120,120),[System.Drawing.Color]::FromArgb(186,194,207),[System.Drawing.Color]::FromArgb(255,190,92))
for ($i=0; $i -lt $statLabels.Count; $i++) {
    $statLabels[$i].Text = $statTexts[$i]
    $statLabels[$i].Location = New-Object System.Drawing.Point((12 + 168*$i), 10)
    $statLabels[$i].Size = New-Object System.Drawing.Size(160,26)
    $statLabels[$i].BackColor = [System.Drawing.Color]::FromArgb(31,40,56)
    $statLabels[$i].ForeColor = $statColors[$i]
    $statLabels[$i].TextAlign = 'MiddleCenter'
    $statLabels[$i].Font = New-Object System.Drawing.Font($script:UiFontFamily,8.5,[System.Drawing.FontStyle]::Bold)
    $right.Controls.Add($statLabels[$i])
}
# --- Полоса статистики: ширины блоков считаются от фактической панели, поэтому «Недопустимо» и «Ошибки» не вылезают за край ни на одном разрешении
$right.Add_SizeChanged({
    $uufPanelW = [int]$script:Form.ClientSize.Width - 440
    if ($uufPanelW -lt 520) { $uufPanelW = 520 }
    $uufBlockW = [Math]::Max(84,[int](($uufPanelW - 64) / 6))
    if ($uufBlockW -gt 190) { $uufBlockW = 190 }
    for ($uufI = 0; $uufI -lt $script:StatLabels.Count; $uufI++) {
        $script:StatLabels[$uufI].Size = New-Object System.Drawing.Size($uufBlockW, 26)
        $script:StatLabels[$uufI].Location = New-Object System.Drawing.Point((12 + [int]($uufI * ($uufBlockW + 8))), 10)
    }
})

$script:ProgressCaption = New-Object System.Windows.Forms.Label
$script:ProgressCaption.Text = 'Прогресс проверки'
$script:ProgressCaption.Location = New-Object System.Drawing.Point(14,40)
$script:ProgressCaption.Size = New-Object System.Drawing.Size(500,18)
$script:ProgressCaption.ForeColor = [System.Drawing.Color]::FromArgb(149,164,187)
$right.Controls.Add($script:ProgressCaption)
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(14,59)
$script:ProgressBar.Size = New-Object System.Drawing.Size(1008,10)
$script:ProgressBar.Anchor = 'Top, Left, Right'
$script:ProgressBar.Minimum = 0
$script:ProgressBar.Maximum = 100
$script:ProgressBar.Value = 0
$right.Controls.Add($script:ProgressBar)

$script:StatusFilterBox = New-Object System.Windows.Forms.ComboBox
$script:StatusFilterBox.Location = New-Object System.Drawing.Point(14,78)
$script:StatusFilterBox.Size = New-Object System.Drawing.Size(160,27)
$script:StatusFilterBox.DropDownStyle = 'DropDownList'
$script:StatusFilterBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:StatusFilterBox.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
[void]$script:StatusFilterBox.Items.AddRange([object[]]@('Все статусы','Свободен','Занят','Недопустимый','Не подтверждено','Ошибка сети','Ожидает','Проверяется'))
$script:StatusFilterBox.SelectedIndex = 0
$right.Controls.Add($script:StatusFilterBox)
$script:SortBox = New-Object System.Windows.Forms.ComboBox
$script:SortBox.Location = New-Object System.Drawing.Point(184,78)
$script:SortBox.Size = New-Object System.Drawing.Size(150,27)
$script:SortBox.DropDownStyle = 'DropDownList'
$script:SortBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:SortBox.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
[void]$script:SortBox.Items.AddRange([object[]]@('Порядок генерации','Ник','Статус','Категория','Короткие сначала','Свободные первыми'))
$script:SortBox.SelectedIndex = 0
$right.Controls.Add($script:SortBox)
$script:SearchBox = New-Object System.Windows.Forms.TextBox
$script:SearchBox.Location = New-Object System.Drawing.Point(344,78)
$script:SearchBox.Size = New-Object System.Drawing.Size(678,27)
$script:SearchBox.Anchor = 'Top, Left, Right'
$script:SearchBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:SearchBox.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
$script:SearchBox.BorderStyle = 'FixedSingle'
$script:SearchBox.Text = ''
$right.Controls.Add($script:SearchBox)

$platformRowLabel = New-Object System.Windows.Forms.Label
$platformRowLabel.Text = 'Платформа проверки:'
$platformRowLabel.Location = New-Object System.Drawing.Point(14, 112)
$platformRowLabel.Size = New-Object System.Drawing.Size(125, 27)
$platformRowLabel.TextAlign = 'MiddleLeft'
$platformRowLabel.ForeColor = [System.Drawing.Color]::FromArgb(203,213,228)
$right.Controls.Add($platformRowLabel)
$script:PlatformBox = New-Object System.Windows.Forms.ComboBox
$script:PlatformBox.Location = New-Object System.Drawing.Point(140, 112)
$script:PlatformBox.Size = New-Object System.Drawing.Size(220, 27)
$script:PlatformBox.DropDownStyle = 'DropDownList'
$script:PlatformBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:PlatformBox.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
[void]$script:PlatformBox.Items.AddRange([object[]]@($script:SupportedPlatforms))
$script:PlatformBox.SelectedItem = 'Roblox'
$right.Controls.Add($script:PlatformBox)
$script:OpenPlatformButton = New-Object System.Windows.Forms.Button
$script:OpenPlatformButton.Text = 'Открыть сайт / ник'
$script:OpenPlatformButton.Location = New-Object System.Drawing.Point(370, 112)
$script:OpenPlatformButton.Size = New-Object System.Drawing.Size(170, 27)
$script:OpenPlatformButton.FlatStyle = 'Flat'
$script:OpenPlatformButton.FlatAppearance.BorderSize = 0
$script:OpenPlatformButton.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
$script:OpenPlatformButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
$right.Controls.Add($script:OpenPlatformButton)
$platformNote = New-Object System.Windows.Forms.Label
$platformNote.Text = 'Для каждой платформы — свой способ проверки.'
$platformNote.Location = New-Object System.Drawing.Point(788, 112)
$platformNote.Size = New-Object System.Drawing.Size(234, 27)
$platformNote.ForeColor = [System.Drawing.Color]::FromArgb(149,164,187)
$platformNote.TextAlign = 'MiddleRight'
$right.Controls.Add($platformNote)
$proxyLabel = New-Object System.Windows.Forms.Label
$proxyLabel.Text = 'Прокси:'
$proxyLabel.Location = New-Object System.Drawing.Point(550, 112)
$proxyLabel.Size = New-Object System.Drawing.Size(58, 27)
$proxyLabel.ForeColor = [System.Drawing.Color]::FromArgb(203,213,228)
$proxyLabel.TextAlign = 'MiddleLeft'
$right.Controls.Add($proxyLabel)
$script:ProxyBox = New-Object System.Windows.Forms.TextBox
$script:ProxyBox.Location = New-Object System.Drawing.Point(612, 112)
$script:ProxyBox.Size = New-Object System.Drawing.Size(170, 27)
$script:ProxyBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:ProxyBox.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
$script:ProxyBox.BorderStyle = 'FixedSingle'
$script:ProxyBox.Text = ''
$right.Controls.Add($script:ProxyBox)
$script:ProxyBox.Add_TextChanged({ Save-AppSettings })
$proxyTooltip = New-Object System.Windows.Forms.ToolTip
$proxyTooltip.SetToolTip($proxyLabel, 'Необязательный HTTP-прокси для всех проверок (например http://127.0.0.1:8080). Помогает, когда сайт платформы недоступен из региона: t.me и YouTube в РФ блокируются без обхода.')
$proxyTooltip.SetToolTip($script:ProxyBox, 'Необязательный прокси для всех проверок. Пусто — напрямую.')

$script:Grid = New-Object System.Windows.Forms.DataGridView
$script:Grid.Location = New-Object System.Drawing.Point(14,146)
$script:Grid.Size = New-Object System.Drawing.Size(1008,568)
$script:Grid.Anchor = 'Top, Bottom, Left, Right'
$script:Grid.BackgroundColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:Grid.BorderStyle = 'None'
$script:Grid.GridColor = [System.Drawing.Color]::FromArgb(42,52,70)
$script:Grid.EnableHeadersVisualStyles = $false
$script:Grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(35,46,63)
$script:Grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
$script:Grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font($script:UiFontFamily,8.5,[System.Drawing.FontStyle]::Bold)
$script:Grid.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(20,27,38)
$script:Grid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(225,232,242)
$script:Grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(50,75,112)
$script:Grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
$script:Grid.RowHeadersVisible = $false
$script:Grid.AllowUserToAddRows = $false
$script:Grid.AllowUserToDeleteRows = $false
$script:Grid.ReadOnly = $true
$script:Grid.SelectionMode = 'FullRowSelect'
$script:Grid.MultiSelect = $true
$script:Grid.AutoSizeColumnsMode = 'Fill'
[void]$script:Grid.Columns.Add('Nick','НИК')
[void]$script:Grid.Columns.Add('Platform','ПЛАТФОРМА')
[void]$script:Grid.Columns.Add('Status','СТАТУС')
[void]$script:Grid.Columns.Add('Category','КАТЕГОРИЯ')
[void]$script:Grid.Columns.Add('Meaning','ЗНАЧЕНИЕ')
[void]$script:Grid.Columns.Add('Time','ВРЕМЯ')
[void]$script:Grid.Columns.Add('Reason','ПРИЧИНА')
$script:Grid.Columns['Nick'].FillWeight = 18
$script:Grid.Columns['Platform'].FillWeight = 13
$script:Grid.Columns['Status'].FillWeight = 14
$script:Grid.Columns['Category'].FillWeight = 17
$script:Grid.Columns['Meaning'].FillWeight = 19
$script:Grid.Columns['Time'].FillWeight = 8
$script:Grid.Columns['Reason'].FillWeight = 22
$script:Grid.RowTemplate.Height = 27
try {
    $doubleBuffered = $script:Grid.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
    if ($doubleBuffered) { $doubleBuffered.SetValue($script:Grid, $true, $null) }
} catch { }
$script:Grid.add_CellDoubleClick({
    param($sender,$e)
    if ($e.RowIndex -ge 0) {
        $n = [string]$script:Grid.Rows[$e.RowIndex].Cells['Nick'].Value
        $st = [string]$script:Grid.Rows[$e.RowIndex].Cells['Status'].Value
        if ($st -eq 'Свободен' -and $n) {
            if (Copy-UufTextToClipboard -Text $n -Context 'копирование ника из таблицы') { Add-Diagnostic "Скопирован ник: $n (статус: $st)" }
        }
    }
})
# --- Подсказки статуса: оформление не должно уметь ронять запуск
try {
    $script:GridToolTip = New-Object System.Windows.Forms.ToolTip
    $script:GridToolTip.InitialDelay = 250
    $script:GridToolTip.ReshowDelay = 250
    $script:GridToolTip.AutoPopDelay = 12000
    $script:GridToolTip.UseFading = $true
    $script:Grid.ToolTip = $script:GridToolTip
} catch { $script:GridToolTip = $null }
function Get-StatusTooltip {
    param($Item)
    $st = [string]$Item.Status
    $platform = [string]$Item.Platform
    $reason = [string]$Item.Reason
    switch ($st) {
        'Недопустимый' {
            $hint = ''
            try { $hint = Get-PlatformFormatHint -Platform $platform } catch { }
            $tip = "Имя не проходит правила платформы $platform.`r`n"
            if ($hint) { $tip += "Правила: $hint" + [Environment]::NewLine }
            if ($reason) { $tip += $reason }
            return $tip.TrimEnd()
        }
        'Ошибка сети' {
            $tip = "Платформа не ответила: запрос оборвался, тайм-аут или HTTP-ошибка 5xx.`r`nДетали: $reason`r`nЧто делать: повторите проверку, увеличьте тайм-аут или паузу; при блокировке сайта в регионе задайте прокси."
            return $tip
        }
        'Не подтверждено' {
            $tip = "Проверка не дала точного ответа — так работает публичный (без входа) способ проверки платформы $platform.`r`n$reason`r`nТочную доступность подтвердит только форма регистрации."
            return $tip.TrimEnd()
        }
        default {
            if ($reason) { return $reason }
            return $null
        }
    }
}
$right.Controls.Add($script:Grid)

$diagnosticHeader = New-Object System.Windows.Forms.Label
$diagnosticHeader.Text = 'ДИАГНОСТИКА И ЖУРНАЛ'
$diagnosticHeader.Location = New-Object System.Drawing.Point(14,720)
$diagnosticHeader.Anchor = 'Bottom, Left'
$diagnosticHeader.Size = New-Object System.Drawing.Size(250,20)
$diagnosticHeader.Font = New-Object System.Drawing.Font($script:UiFontFamily,8.5,[System.Drawing.FontStyle]::Bold)
$diagnosticHeader.ForeColor = [System.Drawing.Color]::FromArgb(194,207,226)
$right.Controls.Add($diagnosticHeader)
$script:DiagnosticBox = New-Object System.Windows.Forms.TextBox
$script:DiagnosticBox.Location = New-Object System.Drawing.Point(14,742)
$script:DiagnosticBox.Size = New-Object System.Drawing.Size(1008,96)
$script:DiagnosticBox.Anchor = 'Bottom, Left, Right'
$script:DiagnosticBox.Multiline = $true
$script:DiagnosticBox.ReadOnly = $true
$script:DiagnosticBox.ScrollBars = 'Vertical'
$script:DiagnosticBox.WordWrap = $true
$script:DiagnosticBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:DiagnosticBox.ForeColor = [System.Drawing.Color]::FromArgb(255,198,112)
$script:DiagnosticBox.Font = New-Object System.Drawing.Font('Consolas',8.5)
$script:DiagnosticBox.Text = 'Готово. Здесь отображаются события, ошибки сети и ответы API.'
$right.Controls.Add($script:DiagnosticBox)
$script:DiagnosticHeader = $diagnosticHeader
$script:DiagnosticsExpanded = $false
$script:DiagnosticsToggleButton = Add-UiButton '▲  Развернуть журнал' 880 716 144 $false 26 $right
$script:DiagnosticsToggleButton.Anchor = 'Bottom, Right'
$script:DiagnosticsToggleButton.Add_Click({
    $script:DiagnosticsExpanded = -not $script:DiagnosticsExpanded
    if ($script:DiagnosticsExpanded) { $script:DiagnosticsToggleButton.Text = '▼  Вернуть стандартно' } else { $script:DiagnosticsToggleButton.Text = '▲  Развернуть журнал' }
    Set-UufRightLayout
})
$script:CopyLogButton = Add-UiButton 'Копировать журнал' 14 844 184 $false 28 $right
$script:CopyLogButton.Anchor = 'Bottom, Left'
$script:ClearLogButton = Add-UiButton 'Очистить журнал' 208 844 184 $false 28 $right
$script:ClearLogButton.Anchor = 'Bottom, Left'
$script:SummaryLabel = New-Object System.Windows.Forms.Label
$script:SummaryLabel.Text = 'Готово к генерации'
$script:SummaryLabel.Location = New-Object System.Drawing.Point(402,844)
$script:SummaryLabel.Size = New-Object System.Drawing.Size(620,28)
$script:SummaryLabel.Anchor = 'Bottom, Left, Right'
$script:SummaryLabel.ForeColor = [System.Drawing.Color]::FromArgb(149,164,187)
$script:SummaryLabel.TextAlign = 'MiddleRight'
$right.Controls.Add($script:SummaryLabel)
# --- Нижняя плашка: VPN/Proxy только для платформ, где возможны региональные блокировки
$script:VpnNoticePlatforms = @('YouTube','Telegram','Outlook','Google','Discord')
$script:VpnNoticeText = 'Проверка некоторых платформ возможно потребует VPN/Proxy, если вы проживаете в странах СНГ, где работают блокировки.'
function Update-VpnNotice {
    if ($null -eq $script:FooterNotice -or $null -eq $script:PlatformBox) { return }
    $noticePlatform = [string]$script:PlatformBox.SelectedItem
    $needNotice = ($script:VpnNoticePlatforms -contains $noticePlatform)
    $script:FooterNotice.Visible = $needNotice
    if ($needNotice) { $script:FooterNotice.Text = '!  ' + $script:VpnNoticeText }
}
$footer = New-Object System.Windows.Forms.Label
$footer.Text = ''
$footer.Location = New-Object System.Drawing.Point(14,878)
$footer.Size = New-Object System.Drawing.Size(1008,34)
$footer.Anchor = 'Bottom, Left, Right'
$footer.ForeColor = [System.Drawing.Color]::FromArgb(20,20,24)
$footer.BackColor = [System.Drawing.Color]::FromArgb(248,185,65)
$footer.Font = New-Object System.Drawing.Font($script:UiFontFamily,9.5,[System.Drawing.FontStyle]::Bold)
$footer.TextAlign = 'MiddleLeft'
$footer.Padding = New-Object System.Windows.Forms.Padding(8,0,4,0)
$right.Controls.Add($footer)
$script:FooterNotice = $footer
Update-VpnNotice
# --- Раскладка правой панели: журнал разворачивается вверх над таблицей и возвращается в стандартное положение
function Set-UufRightLayout {
    if ($null -eq $script:DiagnosticBox -or $null -eq $script:Grid -or $null -eq $script:DiagnosticHeader) { return }
    $layoutPanel = $script:DiagnosticBox.Parent
    $panelHeight = [int]$layoutPanel.ClientSize.Height
    $panelWidth = [int]$layoutPanel.ClientSize.Width
    if ($panelHeight -lt 420 -or $panelWidth -lt 520) { return }
    $contentWidth = $panelWidth - 32
    $standardGridHeight = $panelHeight - 358
    $expandPx = 0
    if ($script:DiagnosticsExpanded) { $expandPx = [Math]::Max(0, [Math]::Min(300, $standardGridHeight - 180)) }
    $script:Grid.Location = New-Object System.Drawing.Point(14,146)
    $script:Grid.Size = New-Object System.Drawing.Size($contentWidth, ($standardGridHeight - $expandPx))
    $headerTop = $panelHeight - 206 - $expandPx
    $boxTop = $panelHeight - 184 - $expandPx
    $script:DiagnosticHeader.Location = New-Object System.Drawing.Point(14,$headerTop)
    $script:DiagnosticBox.Location = New-Object System.Drawing.Point(14,$boxTop)
    $script:DiagnosticBox.Size = New-Object System.Drawing.Size($contentWidth, ($panelHeight - 88 - $boxTop))
    if ($script:DiagnosticsToggleButton) { $script:DiagnosticsToggleButton.Location = New-Object System.Drawing.Point(($contentWidth - 130), ($headerTop - 3)) }
    if ($script:CopyLogButton) { $script:CopyLogButton.Location = New-Object System.Drawing.Point(14,($panelHeight - 82)) }
    if ($script:ClearLogButton) { $script:ClearLogButton.Location = New-Object System.Drawing.Point(208,($panelHeight - 82)) }
    if ($script:SummaryLabel) { $script:SummaryLabel.Location = New-Object System.Drawing.Point(402,($panelHeight - 82)); $script:SummaryLabel.Size = New-Object System.Drawing.Size([Math]::Max(200,$contentWidth - 388),28) }
    if ($script:FooterNotice) { $script:FooterNotice.Location = New-Object System.Drawing.Point(14,($panelHeight - 48)); $script:FooterNotice.Size = New-Object System.Drawing.Size($contentWidth,34) }
}

# --- Правая панель: подгонка под клиентское окно после добавления детей — якоря Bottom поднимают журнал и футер вверх
try {
    $uufClientFit = $script:Form.ClientSize
    $right.Size = New-Object System.Drawing.Size([Math]::Max(520,[int]$uufClientFit.Width - 440),[Math]::Max(320,[int]$uufClientFit.Height - 114))
} catch { }
$right.Add_Resize({ Set-UufRightLayout })
Set-UufRightLayout

$script:AvailableNames = New-Object System.Collections.Generic.List[string]
$script:PlatformAvailableNames = New-Object System.Collections.Generic.List[string]
$script:CheckQueue = $null
$script:CheckInputQueue = $null
$script:Cancellation = $null
$script:WorkerPowerShells = New-Object 'System.Collections.Generic.List[object]'
$script:WorkerRunspaces = New-Object 'System.Collections.Generic.List[object]'
$script:AsyncHandles = New-Object 'System.Collections.Generic.List[object]'
$script:WorkerThreadCount = 1
$script:WorkerDonePerThread = @{}
$script:CompletedWorkers = 0
$script:CheckStartedAt = $null
$script:CompletionEvent = $null
$script:UnhandledWorkerError = $null
$script:PollTimer = New-Object System.Windows.Forms.Timer
$script:PollTimer.Interval = 120
$script:CurrentBatchTotal = 0
$script:CurrentBatchDone = 0

function Write-AppLog {
    param([string]$Message)
    try {
        $logPath = $script:LogPath
        if ([string]::IsNullOrWhiteSpace($logPath)) { $logPath = Join-Path (Get-AppDirectory) 'UniversalUsernameFinder.log' }
        $line = '[{0}] {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message, [Environment]::NewLine
        [System.IO.File]::AppendAllText($logPath, $line, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
    } catch { }
}

function Get-CryptoRandomIndex {
    param([int]$MaxExclusive)
    if ($MaxExclusive -lt 1 -or $MaxExclusive -gt 256) { throw 'Недопустимый диапазон для генератора случайных чисел.' }
    $limit = 256 - (256 % $MaxExclusive)
    $buffer = New-Object byte[] 1
    do {
        $script:PasswordRng.GetBytes($buffer)
        $value = [int]$buffer[0]
    } while ($value -ge $limit)
    return [int]($value % $MaxExclusive)
}

# --- Пароль и регистрация
function New-SecurePassword {
    param([ValidateRange(16,32)][int]$Length = 20)
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghjkmnpqrstuvwxyz'
    $digits = '23456789'
    $special = '!@#$%^&*-_=+?'
    $all = $upper + $lower + $digits + $special
    $characters = New-Object 'System.Collections.Generic.List[char]'
    [void]$characters.Add([char]$upper[(Get-CryptoRandomIndex $upper.Length)])
    [void]$characters.Add([char]$lower[(Get-CryptoRandomIndex $lower.Length)])
    [void]$characters.Add([char]$digits[(Get-CryptoRandomIndex $digits.Length)])
    [void]$characters.Add([char]$special[(Get-CryptoRandomIndex $special.Length)])
    while ($characters.Count -lt $Length) {
        [void]$characters.Add([char]$all[(Get-CryptoRandomIndex $all.Length)])
    }
    $array = $characters.ToArray()
    for ($i = $array.Length - 1; $i -gt 0; $i--) {
        $j = Get-CryptoRandomIndex ($i + 1)
        $temp = $array[$i]
        $array[$i] = $array[$j]
        $array[$j] = $temp
    }
    return (-join $array)
}

function Get-SavedAccountRecords {
    if (-not (Test-Path -LiteralPath $script:VaultPath)) { return @() }
    try {
        $cipher = [System.IO.File]::ReadAllBytes($script:VaultPath)
        $plain = [System.Security.Cryptography.ProtectedData]::Unprotect($cipher, $script:VaultEntropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        $json = [System.Text.Encoding]::UTF8.GetString($plain)
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        $records = ConvertFrom-Json -InputObject $json -ErrorAction Stop
        return @($records)
    } catch {
        Write-AppLog ('Не удалось прочитать зашифрованное хранилище: ' + $_.Exception.ToString())
        throw 'Не удалось открыть зашифрованное хранилище. Оно доступно только тому же пользователю Windows, который его создал. Подробности в UniversalUsernameFinder.log.'
    }
}

function Save-EncryptedAccountRecords {
    param([object[]]$Records)
    $null = [System.IO.Directory]::CreateDirectory($script:VaultDirectory)
    $directoryFull = [System.IO.Path]::GetFullPath($script:VaultDirectory)
    $vaultFull = [System.IO.Path]::GetFullPath($script:VaultPath)
    $json = ConvertTo-Json -InputObject @($Records) -Depth 5 -Compress
    if ([string]::IsNullOrWhiteSpace($json)) { $json = '[]' }
    $plain = [System.Text.Encoding]::UTF8.GetBytes($json)
    $cipher = [System.Security.Cryptography.ProtectedData]::Protect($plain, $script:VaultEntropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    $suffix = [guid]::NewGuid().ToString('N')
    $tempPath = [System.IO.Path]::Combine($directoryFull, 'accounts.dat.' + $suffix + '.tmp')
    $backupPath = [System.IO.Path]::Combine($directoryFull, 'accounts.dat.' + $suffix + '.bak')
    $oldMoved = $false
    try {
        [System.IO.File]::WriteAllBytes($tempPath, $cipher)
        if ([System.IO.File]::Exists($vaultFull)) {
            try {
                [System.IO.File]::Replace($tempPath, $vaultFull, $backupPath)
            } catch {
                if ([System.IO.File]::Exists($tempPath)) {
                    if ([System.IO.File]::Exists($vaultFull)) {
                        [System.IO.File]::Move($vaultFull, $backupPath)
                        $oldMoved = $true
                    }
                    try {
                        [System.IO.File]::Move($tempPath, $vaultFull)
                        $oldMoved = $false
                    } catch {
                        if ($oldMoved -and [System.IO.File]::Exists($backupPath) -and -not [System.IO.File]::Exists($vaultFull)) {
                            try { [System.IO.File]::Move($backupPath, $vaultFull); $oldMoved = $false } catch { }
                        }
                        throw
                    }
                } elseif (-not [System.IO.File]::Exists($vaultFull)) {
                    throw
                }
            }
            if ([System.IO.File]::Exists($backupPath)) {
                try { [System.IO.File]::Delete($backupPath) } catch { }
            }
        } else {
            [System.IO.File]::Move($tempPath, $vaultFull)
        }
    } catch {
        if ($oldMoved -and [System.IO.File]::Exists($backupPath) -and -not [System.IO.File]::Exists($vaultFull)) {
            try { [System.IO.File]::Move($backupPath, $vaultFull); $oldMoved = $false } catch { }
        }
        throw
    } finally {
        if ([System.IO.File]::Exists($tempPath)) { try { [System.IO.File]::Delete($tempPath) } catch { } }
    }
}

function Refresh-SavedAccountList {
    $script:AccountListBox.Items.Clear()
    $script:AccountRecords = @(Get-SavedAccountRecords)
    foreach ($record in $script:AccountRecords) {
        $stamp = ''
        try { $stamp = ([datetime]$record.CreatedAt).ToString('yyyy-MM-dd HH:mm') } catch { $stamp = 'дата не указана' }
        [void]$script:AccountListBox.Items.Add("$($record.Username)  —  $stamp")
    }
    $script:SavedPasswordBox.Clear()
    if ($script:AccountRecords.Count -eq 0) {
        $script:VaultStatusLabel.Text = 'Сохранённых записей пока нет.'
    } else {
        $script:VaultStatusLabel.Text = "Записей в зашифрованном хранилище: $($script:AccountRecords.Count)"
    }
}

function Get-RegistrationUrl {
    param([string]$Platform)
    switch ($Platform) {
        'Roblox' { return 'https://www.roblox.com/' }
        'Google' { return 'https://accounts.google.com/signup' }
        'Mail.ru' { return 'https://account.mail.ru/signup' }
        'VK' { return 'https://vk.com/' }
        'Discord' { return 'https://discord.com/register' }
        'Outlook' { return 'https://signup.live.com/' }
        'Telegram' { return 'https://telegram.org/' }
        'Steam' { return 'https://store.steampowered.com/join/' }
        'GitHub' { return 'https://github.com/signup' }
        'YouTube' { return 'https://www.youtube.com/' }
        default { return 'https://www.google.com/' }
    }
}

function Open-UrlInIncognito {
    param([string]$Url)
    $candidates = @(
        @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", '--incognito'),
        @("${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", '--incognito'),
        @("$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe", '--incognito'),
        @("$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe", '--inprivate'),
        @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", '--inprivate'),
        @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe", '--incognito'),
        @("$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe", '--incognito'),
        @("$env:LOCALAPPDATA\Vivaldi\Application\vivaldi.exe", '--incognito')
    )
    foreach ($candidate in $candidates) {
        if ([System.IO.File]::Exists([string]$candidate[0])) {
            Start-Process -FilePath ([string]$candidate[0]) -ArgumentList @([string]$candidate[1], $Url) | Out-Null
            return $true
        }
    }
    Start-Process $Url | Out-Null
    return $false
}

function Get-AccountSafetyText {
    param([string]$Platform)
    $platformName = 'платформу'
    if ($Platform) { $platformName = [string]$Platform }
    $passPart = ' и пароль'
    if ($platformName -eq 'Mail.ru') { $passPart = '' }
    $lines = @(
        ('1) Скопируй ник{0} → открой {1} → заполни форму и пройди проверки.' -f $passPart,$platformName),
        '2) Вернись сюда: отметь галочку подтверждения и нажми «Сохранить».',
        'Пароль хранится в DPAPI-шифровании Windows для текущего пользователя. Автоматический ввод или обход проверок не выполняется.')
    if ($platformName -eq 'Mail.ru') { $lines = @($lines[0],'Для Mail.ru ник — это имя почтового ящика: регистрация идёт как ник@' + (Get-PlatformDomain -Platform 'Mail.ru') + ', пароль по желанию (нужен только для хранения).') + @($lines[1..2]) }
    return ($lines -join "`r`n")
}

# --- Случайные имя и фамилия для формы регистрации Google (только для Google)
$script:GoogleFirstNames = @('Alex','Daniel','Maria','Sophie','Liam','Emma','Lucas','Olivia','Ethan','Mia','Noah','Anna','Leo','Clara','Max','Julia','Ryan','Nora','Adam','Lena','Oscar','Eva','Henry','Ruby')
$script:GoogleLastNames = @('Miller','Schmidt','Brown','Novak','Weber','Clark','Wagner','Hughes','Fischer','Bennett','Hoffmann','Reed','Keller','Morgan','Becker','Carter','Lang','Foster','Wolf','Hayes','Berger','Ward','Krause','Shaw')
function Set-RandomGoogleNameFields {
    if ($null -eq $script:GoogleFirstNameBox -or $null -eq $script:GoogleLastNameBox) { return }
    $firstPick = $script:GoogleFirstNames[(Get-Random -Minimum 0 -Maximum $script:GoogleFirstNames.Count)]
    $lastPick = $script:GoogleLastNames[(Get-Random -Minimum 0 -Maximum $script:GoogleLastNames.Count)]
    $script:GoogleFirstNameBox.Text = [string]$firstPick
    $script:GoogleLastNameBox.Text = [string]$lastPick
}

function Update-AccountPlatformUi {
    $platform = [string]$script:PlatformBox.SelectedItem
    if ([string]::IsNullOrWhiteSpace($platform)) { return }
    $script:AccountPlatform = $platform
    $domain = Get-PlatformDomain -Platform $platform
    $suffix = ''
    if ($domain) { $suffix = ' (регистрация как ник@' + $domain + ')' }
    if ($script:AccountForm) { $script:AccountForm.Text = 'UUF — регистрация: ' + $platform }
    if ($script:AccountUsernameLabel) { $script:AccountUsernameLabel.Text = 'Никнейм ' + $platform + $suffix }
    if ($script:OpenRegisterButton) { $script:OpenRegisterButton.Text = 'Открыть ' + $platform + ' для регистрации' }
    if ($script:SafetyInfoLabel) { $script:SafetyInfoLabel.Text = Get-AccountSafetyText -Platform $platform }
    $isGoogleAccount = ($platform -eq 'Google')
    foreach ($googleNameControl in @($script:GoogleNameLabel, $script:GoogleFirstNameBox, $script:GoogleLastNameBox, $script:GoogleRandomNameButton)) {
        if ($googleNameControl) { $googleNameControl.Visible = $isGoogleAccount }
    }
    if ($isGoogleAccount -and $script:GoogleFirstNameBox -and [string]::IsNullOrWhiteSpace($script:GoogleFirstNameBox.Text)) { Set-RandomGoogleNameFields }
}

function Open-AccountTools {
    $script:AccountForm = New-Object System.Windows.Forms.Form
    $script:AccountForm.Text = 'UUF — регистрация'
    $script:AccountForm.StartPosition = 'CenterParent'
    $script:AccountForm.Size = New-Object System.Drawing.Size(780, 690)
    $script:AccountForm.MinimumSize = New-Object System.Drawing.Size(780, 690)
    $script:AccountForm.MaximizeBox = $false
    $script:AccountForm.MinimizeBox = $false
    $script:AccountForm.BackColor = [System.Drawing.Color]::FromArgb(15,19,27)
    $script:AccountForm.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $script:AccountForm.Font = New-Object System.Drawing.Font($script:UiFontFamily, 9)
    Set-WindowChrome -Window $script:AccountForm

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(14, 14)
    $tabs.Size = New-Object System.Drawing.Size(738, 600)
    $tabs.Anchor = 'Top, Bottom, Left, Right'
    $prepareTab = New-Object System.Windows.Forms.TabPage
    $prepareTab.Text = 'Регистрация и пароль'
    $prepareTab.BackColor = [System.Drawing.Color]::FromArgb(23,30,42)
    $prepareTab.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $vaultTab = New-Object System.Windows.Forms.TabPage
    $vaultTab.Text = 'Сохранённые аккаунты'
    $vaultTab.BackColor = [System.Drawing.Color]::FromArgb(23,30,42)
    $vaultTab.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    [void]$tabs.TabPages.Add($prepareTab)
    [void]$tabs.TabPages.Add($vaultTab)
    Set-UufTabStyle -Tabs $tabs -TabWidth 190
    $script:AccountTabs = $tabs
    $script:AccountVaultTab = $vaultTab
    $script:AccountForm.Controls.Add($tabs)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = 'Выбери ник из списка или введи свой. Платформа берётся из выбранной строки таблицы или из списка «Платформа проверки». Пароль генерируется локально и никуда не отправляется.'
    $intro.Location = New-Object System.Drawing.Point(18, 16)
    $intro.Size = New-Object System.Drawing.Size(680, 38)
    $intro.ForeColor = [System.Drawing.Color]::FromArgb(203,213,228)
    $prepareTab.Controls.Add($intro)

    $script:AccountUsernameLabel = New-Object System.Windows.Forms.Label
    $script:AccountUsernameLabel.Text = 'Никнейм платформы'
    $script:AccountUsernameLabel.Location = New-Object System.Drawing.Point(18, 60)
    $script:AccountUsernameLabel.Size = New-Object System.Drawing.Size(440, 22)
    $script:AccountUsernameLabel.ForeColor = [System.Drawing.Color]::FromArgb(149,164,187)
    $prepareTab.Controls.Add($script:AccountUsernameLabel)

    $script:AccountUsernameBox = New-Object System.Windows.Forms.ComboBox
    $script:AccountUsernameBox.Location = New-Object System.Drawing.Point(18, 84)
    $script:AccountUsernameBox.Size = New-Object System.Drawing.Size(445, 29)
    $script:AccountUsernameBox.DropDownStyle = 'DropDown'
    $script:AccountUsernameBox.AutoCompleteMode = 'SuggestAppend'
    $script:AccountUsernameBox.AutoCompleteSource = 'ListItems'
    $script:AccountUsernameBox.BackColor = [System.Drawing.Color]::FromArgb(32,41,56)
    $script:AccountUsernameBox.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $prepareTab.Controls.Add($script:AccountUsernameBox)

    $refreshNicks = New-Object System.Windows.Forms.Button
    $refreshNicks.Text = 'Обновить список ников'
    $refreshNicks.Location = New-Object System.Drawing.Point(475, 82)
    $refreshNicks.Size = New-Object System.Drawing.Size(220, 32)
    $refreshNicks.FlatStyle = 'Flat'
    $refreshNicks.FlatAppearance.BorderSize = 0
    $refreshNicks.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $refreshNicks.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $prepareTab.Controls.Add($refreshNicks)

    $passwordLabel = New-Object System.Windows.Forms.Label
    $passwordLabel.Text = 'Пароль — не обязателен для Mail.ru (буквы, цифры и спецсимволы)'
    $passwordLabel.Location = New-Object System.Drawing.Point(18, 129)
    $passwordLabel.Size = New-Object System.Drawing.Size(440, 22)
    $passwordLabel.ForeColor = [System.Drawing.Color]::FromArgb(203,213,228)
    $prepareTab.Controls.Add($passwordLabel)

    $script:PasswordLengthBox = New-Object System.Windows.Forms.NumericUpDown
    $script:PasswordLengthBox.Location = New-Object System.Drawing.Point(18, 155)
    $script:PasswordLengthBox.Size = New-Object System.Drawing.Size(70, 28)
    $script:PasswordLengthBox.Minimum = 16
    $script:PasswordLengthBox.Maximum = 32
    $script:PasswordLengthBox.Value = 20
    $script:PasswordLengthBox.BackColor = [System.Drawing.Color]::FromArgb(32,41,56)
    $script:PasswordLengthBox.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $prepareTab.Controls.Add($script:PasswordLengthBox)

    $generateButton = New-Object System.Windows.Forms.Button
    $generateButton.Text = 'Сгенерировать пароль'
    $generateButton.Location = New-Object System.Drawing.Point(101, 151)
    $generateButton.Size = New-Object System.Drawing.Size(190, 36)
    $generateButton.FlatStyle = 'Flat'
    $generateButton.FlatAppearance.BorderSize = 0
    $generateButton.BackColor = [System.Drawing.Color]::FromArgb(67,123,235)
    $generateButton.ForeColor = [System.Drawing.Color]::FromArgb(255,255,255)
    $prepareTab.Controls.Add($generateButton)

    $script:AccountPasswordBox = New-Object System.Windows.Forms.TextBox
    $script:AccountPasswordBox.Location = New-Object System.Drawing.Point(18, 198)
    $script:AccountPasswordBox.Size = New-Object System.Drawing.Size(677, 29)
    $script:AccountPasswordBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:AccountPasswordBox.ForeColor = [System.Drawing.Color]::FromArgb(149,222,176)
    $script:AccountPasswordBox.Font = New-Object System.Drawing.Font('Consolas', 11)
    $script:AccountPasswordBox.BorderStyle = 'FixedSingle'
    $prepareTab.Controls.Add($script:AccountPasswordBox)

    $copyPassButton = New-Object System.Windows.Forms.Button
    $copyPassButton.Text = 'Копировать пароль'
    $copyPassButton.Location = New-Object System.Drawing.Point(18, 240)
    $copyPassButton.Size = New-Object System.Drawing.Size(180, 36)
    $copyPassButton.FlatStyle = 'Flat'
    $copyPassButton.FlatAppearance.BorderSize = 0
    $copyPassButton.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $copyPassButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $prepareTab.Controls.Add($copyPassButton)

    $script:OpenRegisterButton = New-Object System.Windows.Forms.Button
    $script:OpenRegisterButton.Text = 'Открыть страницу регистрации'
    $script:OpenRegisterButton.Location = New-Object System.Drawing.Point(210, 240)
    $script:OpenRegisterButton.Size = New-Object System.Drawing.Size(260, 36)
    $script:OpenRegisterButton.FlatStyle = 'Flat'
    $script:OpenRegisterButton.FlatAppearance.BorderSize = 0
    $script:OpenRegisterButton.BackColor = [System.Drawing.Color]::FromArgb(67,123,235)
    $script:OpenRegisterButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $prepareTab.Controls.Add($script:OpenRegisterButton)

    $copyNickButton = New-Object System.Windows.Forms.Button
    $copyNickButton.Text = 'Копировать ник'
    $copyNickButton.Location = New-Object System.Drawing.Point(482, 240)
    $copyNickButton.Size = New-Object System.Drawing.Size(213, 36)
    $copyNickButton.FlatStyle = 'Flat'
    $copyNickButton.FlatAppearance.BorderSize = 0
    $copyNickButton.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $copyNickButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $prepareTab.Controls.Add($copyNickButton)

    $script:RegistrationConfirmedCheck = New-Object System.Windows.Forms.CheckBox
    $script:RegistrationConfirmedCheck.Text = 'Я завершил регистрацию с этими данными'
    $script:RegistrationConfirmedCheck.Location = New-Object System.Drawing.Point(18, 294)
    $script:RegistrationConfirmedCheck.Size = New-Object System.Drawing.Size(677, 28)
    $script:RegistrationConfirmedCheck.ForeColor = [System.Drawing.Color]::FromArgb(203,213,228)
    $prepareTab.Controls.Add($script:RegistrationConfirmedCheck)

    $saveAccountButton = New-Object System.Windows.Forms.Button
    $saveAccountButton.Text = 'Сохранить в зашифрованное хранилище'
    $saveAccountButton.Location = New-Object System.Drawing.Point(18, 331)
    $saveAccountButton.Size = New-Object System.Drawing.Size(677, 42)
    $saveAccountButton.FlatStyle = 'Flat'
    $saveAccountButton.FlatAppearance.BorderSize = 0
    $saveAccountButton.BackColor = [System.Drawing.Color]::FromArgb(37,125,83)
    $saveAccountButton.ForeColor = [System.Drawing.Color]::FromArgb(255,255,255)
    $prepareTab.Controls.Add($saveAccountButton)

    $safetyInfo = New-Object System.Windows.Forms.Label
    $safetyInfo.Text = Get-AccountSafetyText -Platform ([string]$script:AccountPlatform)
    $safetyInfo.Location = New-Object System.Drawing.Point(18, 384)
    $safetyInfo.Size = New-Object System.Drawing.Size(713, 92)
    $safetyInfo.ForeColor = [System.Drawing.Color]::FromArgb(177,188,207)
    $safetyInfo.BackColor = [System.Drawing.Color]::FromArgb(32,41,56)
    $safetyInfo.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 4)
    $script:SafetyInfoLabel = $safetyInfo
    $prepareTab.Controls.Add($safetyInfo)
    $script:GoogleNameLabel = New-Object System.Windows.Forms.Label
    $script:GoogleNameLabel.Text = 'Имя и фамилия для формы Google'
    $script:GoogleNameLabel.Location = New-Object System.Drawing.Point(18, 486)
    $script:GoogleNameLabel.Size = New-Object System.Drawing.Size(677, 20)
    $script:GoogleNameLabel.ForeColor = [System.Drawing.Color]::FromArgb(203,213,228)
    $script:GoogleNameLabel.Visible = $false
    $prepareTab.Controls.Add($script:GoogleNameLabel)
    $script:GoogleFirstNameBox = New-Object System.Windows.Forms.TextBox
    $script:GoogleFirstNameBox.Location = New-Object System.Drawing.Point(18, 510)
    $script:GoogleFirstNameBox.Size = New-Object System.Drawing.Size(220, 28)
    $script:GoogleFirstNameBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:GoogleFirstNameBox.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $script:GoogleFirstNameBox.Visible = $false
    $prepareTab.Controls.Add($script:GoogleFirstNameBox)
    $script:GoogleLastNameBox = New-Object System.Windows.Forms.TextBox
    $script:GoogleLastNameBox.Location = New-Object System.Drawing.Point(248, 510)
    $script:GoogleLastNameBox.Size = New-Object System.Drawing.Size(220, 28)
    $script:GoogleLastNameBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:GoogleLastNameBox.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $script:GoogleLastNameBox.Visible = $false
    $prepareTab.Controls.Add($script:GoogleLastNameBox)
    $script:GoogleRandomNameButton = New-Object System.Windows.Forms.Button
    $script:GoogleRandomNameButton.Text = 'Случайное имя и фамилия'
    $script:GoogleRandomNameButton.Location = New-Object System.Drawing.Point(478, 508)
    $script:GoogleRandomNameButton.Size = New-Object System.Drawing.Size(217, 32)
    $script:GoogleRandomNameButton.FlatStyle = 'Flat'
    $script:GoogleRandomNameButton.FlatAppearance.BorderSize = 0
    $script:GoogleRandomNameButton.BackColor = [System.Drawing.Color]::FromArgb(93,73,222)
    $script:GoogleRandomNameButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $script:GoogleRandomNameButton.Visible = $false
    $script:GoogleRandomNameButton.Add_Click({ Set-RandomGoogleNameFields })
    $prepareTab.Controls.Add($script:GoogleRandomNameButton)

    $script:AccountListBox = New-Object System.Windows.Forms.ListBox
    $script:AccountListBox.Location = New-Object System.Drawing.Point(18, 18)
    $script:AccountListBox.Size = New-Object System.Drawing.Size(677, 275)
    $script:AccountListBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:AccountListBox.ForeColor = [System.Drawing.Color]::FromArgb(225,232,242)
    $vaultTab.Controls.Add($script:AccountListBox)

    $vaultPasswordLabel = New-Object System.Windows.Forms.Label
    $vaultPasswordLabel.Text = 'Пароль выбранной записи'
    $vaultPasswordLabel.Location = New-Object System.Drawing.Point(18, 304)
    $vaultPasswordLabel.Size = New-Object System.Drawing.Size(400, 22)
    $vaultPasswordLabel.ForeColor = [System.Drawing.Color]::FromArgb(203,213,228)
    $vaultTab.Controls.Add($vaultPasswordLabel)

    $script:SavedPasswordBox = New-Object System.Windows.Forms.TextBox
    $script:SavedPasswordBox.Location = New-Object System.Drawing.Point(18, 330)
    $script:SavedPasswordBox.Size = New-Object System.Drawing.Size(677, 29)
    $script:SavedPasswordBox.ReadOnly = $true
    $script:SavedPasswordBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:SavedPasswordBox.ForeColor = [System.Drawing.Color]::FromArgb(149,222,176)
    $script:SavedPasswordBox.Font = New-Object System.Drawing.Font('Consolas', 10)
    $vaultTab.Controls.Add($script:SavedPasswordBox)

    $copySavedPasswordButton = New-Object System.Windows.Forms.Button
    $copySavedPasswordButton.Text = 'Копировать пароль'
    $copySavedPasswordButton.Location = New-Object System.Drawing.Point(18, 374)
    $copySavedPasswordButton.Size = New-Object System.Drawing.Size(180, 36)
    $copySavedPasswordButton.FlatStyle = 'Flat'
    $copySavedPasswordButton.FlatAppearance.BorderSize = 0
    $copySavedPasswordButton.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $copySavedPasswordButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $vaultTab.Controls.Add($copySavedPasswordButton)

    $copySavedUsernameButton = New-Object System.Windows.Forms.Button
    $copySavedUsernameButton.Text = 'Копировать ник'
    $copySavedUsernameButton.Location = New-Object System.Drawing.Point(210, 374)
    $copySavedUsernameButton.Size = New-Object System.Drawing.Size(180, 36)
    $copySavedUsernameButton.FlatStyle = 'Flat'
    $copySavedUsernameButton.FlatAppearance.BorderSize = 0
    $copySavedUsernameButton.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $copySavedUsernameButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $vaultTab.Controls.Add($copySavedUsernameButton)

    $deleteAccountButton = New-Object System.Windows.Forms.Button
    $deleteAccountButton.Text = 'Удалить запись'
    $deleteAccountButton.Location = New-Object System.Drawing.Point(402, 374)
    $deleteAccountButton.Size = New-Object System.Drawing.Size(180, 36)
    $deleteAccountButton.FlatStyle = 'Flat'
    $deleteAccountButton.FlatAppearance.BorderSize = 0
    $deleteAccountButton.BackColor = [System.Drawing.Color]::FromArgb(115,47,55)
    $deleteAccountButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $vaultTab.Controls.Add($deleteAccountButton)

    $script:VaultStatusLabel = New-Object System.Windows.Forms.Label
    $script:VaultStatusLabel.Location = New-Object System.Drawing.Point(18, 425)
    $script:VaultStatusLabel.Size = New-Object System.Drawing.Size(677, 35)
    $script:VaultStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(177,188,207)
    $vaultTab.Controls.Add($script:VaultStatusLabel)

    $script:AccountUsernameBox.Add_TextChanged({
        if ($script:RegistrationConfirmedCheck) { $script:RegistrationConfirmedCheck.Checked = $false }
    })
    $script:AccountPasswordBox.Add_TextChanged({
        if ($script:RegistrationConfirmedCheck) { $script:RegistrationConfirmedCheck.Checked = $false }
    })

    $refreshNicks.Add_Click({
        $keep = $script:AccountUsernameBox.Text.Trim()
        $script:AccountUsernameBox.Items.Clear()
        foreach ($availableNick in $script:PlatformAvailableNames) { [void]$script:AccountUsernameBox.Items.Add([string]$availableNick) }
        $script:AccountUsernameBox.Text = $keep
        if ($script:AccountUsernameBox.Items.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('В основном окне пока нет найденных свободных ников. Можно ввести ник вручную, но его доступность не подтверждена.', 'Список ников', 'OK', 'Information') | Out-Null
        }
    })

    $generateButton.Add_Click({
        try {
            $script:AccountPasswordBox.Text = New-SecurePassword -Length ([int]$script:PasswordLengthBox.Value)
            $script:RegistrationConfirmedCheck.Checked = $false
        } catch {
            Write-AppLog ('Ошибка генерации пароля: ' + $_.Exception.ToString())
            [System.Windows.Forms.MessageBox]::Show('Не удалось создать пароль: ' + $_.Exception.Message, 'Ошибка', 'OK', 'Error') | Out-Null
        }
    })

    $copyPassButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($script:AccountPasswordBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show('Сначала сгенерируй пароль.', 'Копирование', 'OK', 'Information') | Out-Null
            return
        }
        Copy-UufTextToClipboard -Text $script:AccountPasswordBox.Text -Context 'копирование пароля' | Out-Null
    })

    $copyNickButton.Add_Click({
        $nick = Get-PlatformNickInput -Platform ([string]$script:AccountPlatform) -Raw $script:AccountUsernameBox.Text
        if ([string]::IsNullOrWhiteSpace($nick)) {
            [System.Windows.Forms.MessageBox]::Show('Сначала выбери или введи ник.', 'Копирование', 'OK', 'Information') | Out-Null
            return
        }
        Copy-UufTextToClipboard -Text $nick -Context 'копирование ника' | Out-Null
    })

    $script:OpenRegisterButton.Add_Click({
        $registerPlatform = [string]$script:AccountPlatform
        $registerNick = Get-PlatformNickInput -Platform $registerPlatform -Raw $script:AccountUsernameBox.Text
        if (-not (Test-UsernameFormat -Username $registerNick -Platform $registerPlatform)) {
            [System.Windows.Forms.MessageBox]::Show(('Ник не подходит для платформы ' + $registerPlatform + '.' + [Environment]::NewLine + [Environment]::NewLine + 'Правила: ' + (Get-PlatformFormatHint -Platform $registerPlatform) + '.'), 'Проверь ник', 'OK', 'Warning') | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($script:AccountPasswordBox.Text)) {
            $script:AccountPasswordBox.Text = New-SecurePassword -Length ([int]$script:PasswordLengthBox.Value)
        }
        try {
            $openedIncognito = Open-UrlInIncognito -Url (Get-RegistrationUrl -Platform $registerPlatform)
            if ($openedIncognito) { $modeNote = 'Открыл страницу регистрации ' + $registerPlatform + ' в окне инкогнито.' } else { $modeNote = 'Открыл страницу регистрации ' + $registerPlatform + ' в браузере по умолчанию.' }
            [System.Windows.Forms.MessageBox]::Show(($modeNote + "`r`n`r`nСкопируй ник и пароль в форму вручную и пройди все проверки. Платформа может потребовать CAPTCHA или дополнительное подтверждение."), 'Регистрация', 'OK', 'Information') | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show('Не удалось открыть сайт: ' + $_.Exception.Message, 'Ошибка', 'OK', 'Error') | Out-Null
        }
    })

    $saveAccountButton.Add_Click({
        $nick = Get-PlatformNickInput -Platform ([string]$script:AccountPlatform) -Raw $script:AccountUsernameBox.Text
        $password = $script:AccountPasswordBox.Text
        if (-not (Test-UsernameFormat -Username $nick -Platform ([string]$script:AccountPlatform))) {
            [System.Windows.Forms.MessageBox]::Show(('Проверь ник: ' + (Get-PlatformFormatHint -Platform ([string]$script:AccountPlatform)) + '.'), 'Неверный ник', 'OK', 'Warning') | Out-Null
            return
        }
        # --- Пункт 6: для Mail.ru пароль при регистрации создаётся сайтом, поэтому сохранение без пароля допустимо
        $passwordOptionalPlatform = ([string]$script:AccountPlatform -eq 'Mail.ru')
        if ([string]::IsNullOrWhiteSpace($password)) {
            if (-not $passwordOptionalPlatform) {
                [System.Windows.Forms.MessageBox]::Show('Сначала сгенерируй пароль длиной от 16 символов.', 'Нет пароля', 'OK', 'Warning') | Out-Null
                return
            }
            $password = ''
        } elseif ($password.Length -lt 16) {
            [System.Windows.Forms.MessageBox]::Show('Сначала сгенерируй пароль длиной от 16 символов.', 'Нет пароля', 'OK', 'Warning') | Out-Null
            return
        }
        if (-not $script:RegistrationConfirmedCheck.Checked) {
            [System.Windows.Forms.MessageBox]::Show(('Сначала заверши регистрацию на сайте ' + [string]$script:AccountPlatform + ' и отметь галочку подтверждения.'), 'Регистрация не подтверждена', 'OK', 'Information') | Out-Null
            return
        }
        try {
            # --- Формат как в генерации: для почтовых платформ сохраняем адрес целиком (ник@домен)
            $storedNick = Get-DisplayNick -Platform ([string]$script:AccountPlatform) -Name $nick
            $records = @(Get-SavedAccountRecords)
            $existing = @($records | Where-Object { [string]$_.Username -ieq $storedNick -or [string]$_.Username -ieq $nick })
            if ($existing.Count -gt 0) {
                $choice = [System.Windows.Forms.MessageBox]::Show("Запись для ника $storedNick уже существует. Перезаписать пароль?", 'Запись уже есть', 'YesNo', 'Question')
                if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { return }
                $records = @($records | Where-Object { [string]$_.Username -ine $storedNick -and [string]$_.Username -ine $nick })
            }
            $record = [pscustomobject]@{Username=$storedNick; Password=$password; Platform=([string]$script:AccountPlatform); CreatedAt=(Get-Date).ToString('o')}
            $records = @($records) + @($record)
            Save-EncryptedAccountRecords -Records $records
            $script:RegistrationConfirmedCheck.Checked = $false
            Refresh-SavedAccountList
            $script:AccountTabs.SelectedTab = $script:AccountVaultTab
            [System.Windows.Forms.MessageBox]::Show("Данные для $storedNick сохранены в зашифрованное хранилище текущего пользователя Windows.", 'Сохранено', 'OK', 'Information') | Out-Null
        } catch {
            Write-AppLog ('Не удалось сохранить учётные данные: ' + $_.Exception.ToString())
            [System.Windows.Forms.MessageBox]::Show('Не удалось сохранить данные. ' + $_.Exception.Message + "`r`n`r`nСм. UniversalUsernameFinder.log.", 'Ошибка сохранения', 'OK', 'Error') | Out-Null
        }
    })

    $script:AccountListBox.Add_SelectedIndexChanged({
        if ($script:AccountListBox.SelectedIndex -ge 0 -and $script:AccountListBox.SelectedIndex -lt $script:AccountRecords.Count) {
            $script:SavedPasswordBox.Text = [string]$script:AccountRecords[$script:AccountListBox.SelectedIndex].Password
        } else {
            $script:SavedPasswordBox.Clear()
        }
    })

    $copySavedPasswordButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($script:SavedPasswordBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show('Сначала выбери запись в списке.', 'Копирование', 'OK', 'Information') | Out-Null
            return
        }
        Copy-UufTextToClipboard -Text $script:SavedPasswordBox.Text -Context 'копирование сохранённого пароля' | Out-Null
    })

    $copySavedUsernameButton.Add_Click({
        $index = $script:AccountListBox.SelectedIndex
        if ($index -lt 0 -or $index -ge $script:AccountRecords.Count) {
            [System.Windows.Forms.MessageBox]::Show('Сначала выбери запись в списке.', 'Копирование', 'OK', 'Information') | Out-Null
            return
        }
        Copy-UufTextToClipboard -Text ([string]$script:AccountRecords[$index].Username) -Context 'копирование сохранённого ника' | Out-Null
    })

    $deleteAccountButton.Add_Click({
        $index = $script:AccountListBox.SelectedIndex
        if ($index -lt 0 -or $index -ge $script:AccountRecords.Count) {
            [System.Windows.Forms.MessageBox]::Show('Сначала выбери запись для удаления.', 'Удаление', 'OK', 'Information') | Out-Null
            return
        }
        $nick = [string]$script:AccountRecords[$index].Username
        $answer = [System.Windows.Forms.MessageBox]::Show("Удалить сохранённые данные для $nick?", 'Подтверждение удаления', 'YesNo', 'Warning')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        try {
            $records = @()
            for ($i = 0; $i -lt $script:AccountRecords.Count; $i++) {
                if ($i -ne $index) { $records += $script:AccountRecords[$i] }
            }
            Save-EncryptedAccountRecords -Records $records
            Refresh-SavedAccountList
        } catch {
            Write-AppLog ('Не удалось удалить запись из хранилища: ' + $_.Exception.ToString())
            [System.Windows.Forms.MessageBox]::Show('Не удалось изменить хранилище: ' + $_.Exception.Message, 'Ошибка', 'OK', 'Error') | Out-Null
        }
    })

    try {
        foreach ($availableNick in $script:PlatformAvailableNames) { [void]$script:AccountUsernameBox.Items.Add([string]$availableNick) }
        $preferredNick = ''
        if ($script:Grid.CurrentRow -and $script:Grid.CurrentRow.Index -ge 0) {
            $candidateNick = [string]$script:Grid.CurrentRow.Cells['Nick'].Value
            $candidateStatus = [string]$script:Grid.CurrentRow.Cells['Status'].Value
            if ($candidateStatus -eq 'Свободен') { $preferredNick = $candidateNick }
        }
        if (-not $preferredNick -and $script:PlatformAvailableNames.Count -gt 0) { $preferredNick = [string]$script:PlatformAvailableNames[0] }
        $script:AccountUsernameBox.Text = $preferredNick
        $script:AccountPasswordBox.Text = New-SecurePassword -Length ([int]$script:PasswordLengthBox.Value)
        Refresh-SavedAccountList
    } catch {
        $script:VaultStatusLabel.Text = 'Не удалось прочитать хранилище: ' + $_.Exception.Message
        Write-AppLog ('Ошибка открытия инструментов аккаунта: ' + $_.Exception.ToString())
    }
    try {
        if ($script:Grid.CurrentRow -and $script:Grid.CurrentRow.Index -ge 0) {
            $rowPlatform = [string]$script:Grid.CurrentRow.Cells['Platform'].Value
            if ($rowPlatform -and ($script:SupportedPlatforms -contains $rowPlatform) -and $rowPlatform -ne [string]$script:PlatformBox.SelectedItem) { $script:PlatformBox.SelectedItem = $rowPlatform }
        }
    } catch { }
    Set-ButtonEdgeStyle -Root $script:AccountForm
    Update-AccountPlatformUi
    [void]$script:AccountForm.ShowDialog($script:Form)
}

function Add-Diagnostic {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    if ($script:DiagnosticBox) {
        $script:DiagnosticBox.AppendText($line + [Environment]::NewLine)
        $script:DiagnosticBox.SelectionStart = $script:DiagnosticBox.TextLength
        $script:DiagnosticBox.ScrollToCaret()
    }
    Write-AppLog $Message
}

function Get-HistoryKey {
    param([string]$Name, [string]$Platform)
    return (($Platform + '|' + $Name).ToLowerInvariant())
}

function Register-Candidate {
    param($Candidate)
    if (-not $Candidate) { return }
    $key = Get-HistoryKey -Name ([string]$Candidate.Name) -Platform ([string]$Candidate.Platform)
    $script:CandidateIndex[$key] = $Candidate
}

function Find-Candidate {
    param([string]$Name, [string]$Platform)
    $key = Get-HistoryKey -Name $Name -Platform $Platform
    if ($script:CandidateIndex.ContainsKey($key)) { return $script:CandidateIndex[$key] }
    return $null
}

function Clear-CandidateIndex {
    $script:CandidateIndex = @{}
}
function Touch-Candidates {
    $script:CandidateRevision = $script:CandidateRevision + 1
}

# --- Атомарная запись файлов

function Write-AtomicFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = [System.IO.Path]::GetDirectoryName($fullPath)
    if (-not [string]::IsNullOrWhiteSpace($directory)) { $null = [System.IO.Directory]::CreateDirectory($directory) }
    $fileName = [System.IO.Path]::GetFileName($fullPath)
    $tempPath = [System.IO.Path]::Combine($directory, ($fileName + '.' + [guid]::NewGuid().ToString('N') + '.tmp'))
    try {
        [System.IO.File]::WriteAllBytes($tempPath, $Bytes)
        if (-not [System.IO.File]::Exists($fullPath)) {
            [System.IO.File]::Move($tempPath, $fullPath)
            return
        }
        try {
            [System.IO.File]::Replace($tempPath, $fullPath, $null)
        } catch {
            [System.IO.File]::Copy($tempPath, $fullPath, $true)
        }
    } finally {
        if ([System.IO.File]::Exists($tempPath)) { try { [System.IO.File]::Delete($tempPath) } catch { } }
    }
}

function Write-AtomicJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Json
    )
    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $true
    $preamble = $encoding.GetPreamble()
    $body = $encoding.GetBytes($Json)
    $bytes = New-Object byte[] ($preamble.Length + $body.Length)
    [System.Array]::Copy($preamble, 0, $bytes, 0, $preamble.Length)
    [System.Array]::Copy($body, 0, $bytes, $preamble.Length, $body.Length)
    Write-AtomicFile -Path $Path -Bytes $bytes
}

# --- Хранилище истории ников
function Save-UsernameHistory {
    try {
        if (-not (Test-Path -LiteralPath $script:HistoryDirectory)) { [void](New-Item -ItemType Directory -Path $script:HistoryDirectory -Force) }
        $data = [pscustomobject]@{
            FreeHistory = @($script:FreeHistory | Select-Object -First 5000)
            RetiredNames = @($script:RetiredNames.Keys | Select-Object -First 20000)
            CheckedNames = @($script:CheckedNames.Keys | Select-Object -First 20000)
        }
        $json = ConvertTo-Json -InputObject $data -Depth 6
        if ([string]::IsNullOrWhiteSpace($json)) { $json = '{}' }
        $historyFull = [System.IO.Path]::GetFullPath($script:HistoryPath)
        Write-AtomicJsonFile -Path $historyFull -Json $json
        $script:HistoryDirty = $false
        $script:HistoryDirtySince = $null
    } catch { Write-AppLog ('Не удалось сохранить историю ников: ' + $_.Exception.Message) }
}

function Mark-HistoryDirty {
    $script:HistoryDirty = $true
    if (-not $script:HistoryDirtySince) { $script:HistoryDirtySince = [DateTime]::UtcNow }
}

function Flush-HistoryIfDue {
    param([int]$IntervalSeconds = 5)
    if (-not $script:HistoryDirty) { return }
    if (-not $script:HistoryDirtySince) { $script:HistoryDirtySince = [DateTime]::UtcNow; return }
    if (([DateTime]::UtcNow - $script:HistoryDirtySince).TotalSeconds -ge $IntervalSeconds) { Save-UsernameHistory }
}

# --- Настройки приложения

function Export-AppSettings {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Settings,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $json = ConvertTo-Json -InputObject $Settings -Depth 5
    if ([string]::IsNullOrWhiteSpace($json)) { $json = '{}' }
    Write-AtomicJsonFile -Path $Path -Json $json
}

function Import-AppSettings {
    param([Parameter(Mandatory = $true)][string]$Path)
    $result = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    try {
        $json = [System.IO.File]::ReadAllText($Path)
        if ([string]::IsNullOrWhiteSpace($json)) { return $result }
        $data = $json | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $data) { return $result }
        foreach ($property in $data.PSObject.Properties) { $result[$property.Name] = $property.Value }
    } catch {
        return @{}
    }
    return $result
}

# --- Безопасное применение значений к контролам

function Add-SettingValue {
    param([hashtable]$Target, [string]$Key, [scriptblock]$Getter)
    try { $Target[$Key] = & $Getter } catch { }
}

function Set-NumericFromSettings {
    param($Control, $Value, [int]$Default)
    if ($null -eq $Control) { return }
    $number = $Default
    try { if ($null -ne $Value) { $number = [int]$Value } } catch { $number = $Default }
    $minimum = [int]$Control.Minimum
    $maximum = [int]$Control.Maximum
    if ($number -lt $minimum) { $number = $minimum }
    if ($number -gt $maximum) { $number = $maximum }
    $Control.Value = $number
}

function Set-ComboFromSettings {
    param($Control, $Value)
    if ($null -eq $Control -or $null -eq $Value) { return }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    if ($Control.Items.Contains($text)) { $Control.SelectedItem = $text }
}

function Set-CheckFromSettings {
    param($Control, $Value)
    if ($null -eq $Control -or $null -eq $Value) { return }
    try { $Control.Checked = [bool]$Value } catch { }
}

function Set-CheckedListFromSettings {
    param($Control, $Values)
    if ($null -eq $Control -or $null -eq $Values) { return }
    $names = @($Values | ForEach-Object { [string]$_ } | Where-Object { $_ })
    if ($names.Count -eq 0) { return }
    for ($index = 0; $index -lt $Control.Items.Count; $index++) {
        $item = [string]$Control.Items[$index]
        $Control.SetItemChecked($index, ($names -contains $item))
    }
}

# --- Настройки и геометрия окна
function Get-AppSettingsFromUi {
    $settings = @{}
    Add-SettingValue $settings 'AppVersion' { $script:AppVersion }
    Add-SettingValue $settings 'WindowState' { [string]$script:Form.WindowState }
    Add-SettingValue $settings 'WindowBounds' {
        $bounds = if ($script:Form.WindowState -eq 'Normal') { $script:Form.Bounds } else { $script:Form.RestoreBounds }
        @{ X = [int]$bounds.X; Y = [int]$bounds.Y; Width = [int]$bounds.Width; Height = [int]$bounds.Height }
    }
    Add-SettingValue $settings 'StatusFilter' { [string]$script:StatusFilterBox.SelectedItem }
    Add-SettingValue $settings 'ProxyUrl' { [string]$script:ProxyBox.Text.Trim() }
    Add-SettingValue $settings 'SortMode' { [string]$script:SortBox.SelectedItem }
    return $settings
}

function Restore-AppSettingsToUi {
    param([hashtable]$Settings)
    if ($null -eq $Settings -or $Settings.Count -eq 0) { return }

    if ($Settings.ContainsKey('WindowBounds')) {
        try {
            $raw = $Settings['WindowBounds']
            $rect = New-Object System.Drawing.Rectangle([int]$raw.X, [int]$raw.Y, [int]$raw.Width, [int]$raw.Height)
            if ($rect.Width -ge 400 -and $rect.Height -ge 300) {
                $visible = $false
                foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
                    if ($screen.WorkingArea.IntersectsWith($rect)) { $visible = $true; break }
                }
                if ($visible) {
                    $script:Form.StartPosition = 'Manual'
                    $script:Form.Bounds = $rect
                }
            }
        } catch { }
    }
    if ($Settings.ContainsKey('WindowState')) {
        try { $script:Form.WindowState = [System.Windows.Forms.FormWindowState]([string]$Settings['WindowState']) } catch { }
    }

    Set-ComboFromSettings $script:StatusFilterBox $Settings['StatusFilter']
    Set-ComboFromSettings $script:SortBox $Settings['SortMode']
    if ($Settings.ContainsKey('ProxyUrl') -and $script:ProxyBox) { $script:ProxyBox.Text = [string]$Settings['ProxyUrl'] }
}

function Save-AppSettings {
    try {
        Export-AppSettings -Settings (Get-AppSettingsFromUi) -Path $script:SettingsPath
    } catch { Write-AppLog ('Не удалось сохранить настройки: ' + $_.Exception.Message) }
}

function Restore-AppSettings {
    try {
        $settings = Import-AppSettings -Path $script:SettingsPath
        if ($settings.Count -eq 0) {
            if (Test-Path -LiteralPath $script:SettingsPath) {
                Write-AppLog 'Файл настроек повреждён или пуст; применены значения по умолчанию.'
            }
            return
        }
        Restore-AppSettingsToUi -Settings $settings
        Add-Diagnostic ('Восстановлены настройки предыдущего сеанса (платформа: {0}).' -f [string]$script:PlatformBox.SelectedItem)
    } catch { Write-AppLog ('Не удалось восстановить настройки: ' + $_.Exception.Message) }
}

function Update-FreeHistoryFromCandidate {
    param($Candidate)
    if (-not $Candidate) { return }
    $name = [string]$Candidate.Name
    $platform = [string]$Candidate.Platform
    if (-not $name -or -not $platform) { return }
    $key = Get-HistoryKey -Name $name -Platform $platform
    $status = [string]$Candidate.Status
    if ($status -eq 'Свободен') {
        if ($script:RetiredNames.ContainsKey($key)) { return }
        $entry = [pscustomobject]@{ Name=$name; Platform=$platform; Status=$status; Time=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
        $remaining = @($script:FreeHistory | Where-Object { (Get-HistoryKey -Name ([string]$_.Name) -Platform ([string]$_.Platform)) -ne $key })
        $script:FreeHistory = @(@($entry) + @($remaining))
    } elseif ($status -eq 'Занят') {
        $script:FreeHistory = @($script:FreeHistory | Where-Object { (Get-HistoryKey -Name ([string]$_.Name) -Platform ([string]$_.Platform)) -ne $key })
        $script:RetiredNames[$key] = $true
    } else { return }
    if ($script:HistoryButton) { $script:HistoryButton.Text = "Свободные ники ($($script:FreeHistory.Count))" }
    Mark-HistoryDirty
}

function Refresh-FreeHistoryList {
    if ($script:HistoryListBox -and $script:HistoryListBox.IsDisposed) { return }
    if (-not $script:HistoryListBox) { return }
    $script:HistoryListBox.BeginUpdate()
    $script:HistoryListBox.Items.Clear()
    $historyItems = @($script:FreeHistory)
    if ($script:HistoryPlatformList) {
        $platformFilter = @($script:HistoryPlatformList.CheckedItems | ForEach-Object { [string]$_ })
        if ($platformFilter.Count -gt 0) { $historyItems = @($historyItems | Where-Object { $platformFilter -contains [string]$_.Platform }) }
    }
    foreach ($item in $historyItems) {
        $display = '{0} — {1}' -f (Get-DisplayNick -Platform ([string]$item.Platform) -Name ([string]$item.Name)), [string]$item.Platform
        [void]$script:HistoryListBox.Items.Add([pscustomobject]@{Display=$display; Name=[string]$item.Name; Platform=[string]$item.Platform; Status=[string]$item.Status})
    }
    $script:HistoryListBox.EndUpdate()
    if ($script:HistoryListBox.Items.Count -eq 0) {
        $script:HistoryDescription.Text = 'Пока нет имён, которые проверка признала свободными.'
    } else {
        $script:HistoryDescription.Text = 'Выбери один или несколько ников (Ctrl/Shift или «Выделить все») и нажми «Повторная проверка». Если ник уже занят, он исчезнет из истории и больше не будет генерироваться.'
    }
}

# --- Проверенные ники и история свободных
function Update-CheckedNamesButtonText {
    if (-not $script:CheckedNamesButton) { return }
    $script:CheckedNamesButton.Text = ('Проверенные ники ({0})' -f $script:CheckedNames.Count)
}

function Refresh-CheckedNamesList {
    if (-not $script:CheckedNamesListBox) { return }
    $filter = ''
    if ($script:CheckedNamesSearchBox) { $filter = ([string]$script:CheckedNamesSearchBox.Text).Trim() }
    $script:CheckedNamesListBox.BeginUpdate()
    $script:CheckedNamesListBox.Items.Clear()
    foreach ($checkedKey in @($script:CheckedNames.Keys | Sort-Object)) {
        $key = [string]$checkedKey
        if ($filter -and $key.IndexOf($filter,[StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $separatorIndex = $key.IndexOf('|')
        if ($separatorIndex -gt 0) {
            $keyPlatform = $key.Substring(0,$separatorIndex)
            $keyName = $key.Substring($separatorIndex + 1)
        } else {
            $keyPlatform = ''
            $keyName = $key
        }
        [void]$script:CheckedNamesListBox.Items.Add([pscustomobject]@{Display=(('{0} — {1}') -f (Get-DisplayNick -Platform $keyPlatform -Name $keyName),$keyPlatform); Name=$keyName; Platform=$keyPlatform; Key=$key})
    }
    $script:CheckedNamesListBox.EndUpdate()
    if ($script:CheckedNamesListBox.Items.Count -eq 0) {
        $script:CheckedNamesDescription.Text = 'Список пуст. Он заполняется автоматически после каждой проверки и хранится в файле username_history.json.'
    } else {
        $script:CheckedNamesDescription.Text = ('Показано имён: {0}. Они не предлагаются повторно, пока включена галочка «Исключать проверенные». Выдели нужные и нажми «Проверить снова».' -f $script:CheckedNamesListBox.Items.Count)
    }
}

function Open-CheckedNamesWindow {
    if (Test-CheckRunning) {
        [System.Windows.Forms.MessageBox]::Show('Идёт проверка. Дождись завершения или останови её.','Проверенные ники','OK','Information') | Out-Null
        return
    }
    $checkedForm = New-Object System.Windows.Forms.Form
    $checkedForm.Text = 'Проверенные ники'
    $checkedForm.StartPosition = 'CenterParent'
    $checkedForm.Size = New-Object System.Drawing.Size(560,600)
    $checkedForm.MinimumSize = New-Object System.Drawing.Size(480,480)
    $checkedForm.BackColor = [System.Drawing.Color]::FromArgb(15,19,27)
    $checkedForm.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $checkedForm.Font = New-Object System.Drawing.Font($script:UiFontFamily,9)
    Set-WindowChrome -Window $checkedForm
    $script:CheckedNamesDescription = New-Object System.Windows.Forms.Label
    $script:CheckedNamesDescription.Location = New-Object System.Drawing.Point(16,14)
    $script:CheckedNamesDescription.Size = New-Object System.Drawing.Size(516,50)
    $script:CheckedNamesDescription.ForeColor = [System.Drawing.Color]::FromArgb(190,202,221)
    $checkedForm.Controls.Add($script:CheckedNamesDescription)
    $script:CheckedNamesSearchBox = New-Object System.Windows.Forms.TextBox
    $script:CheckedNamesSearchBox.Location = New-Object System.Drawing.Point(16,70)
    $script:CheckedNamesSearchBox.Size = New-Object System.Drawing.Size(516,27)
    $script:CheckedNamesSearchBox.Anchor = 'Top, Left, Right'
    $script:CheckedNamesSearchBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:CheckedNamesSearchBox.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $script:CheckedNamesSearchBox.BorderStyle = 'FixedSingle'
    $checkedForm.Controls.Add($script:CheckedNamesSearchBox)
    $script:CheckedNamesListBox = New-Object System.Windows.Forms.ListBox
    $script:CheckedNamesListBox.Location = New-Object System.Drawing.Point(16,104)
    $script:CheckedNamesListBox.Size = New-Object System.Drawing.Size(516,380)
    $script:CheckedNamesListBox.Anchor = 'Top, Bottom, Left, Right'
    $script:CheckedNamesListBox.DisplayMember = 'Display'
    $script:CheckedNamesListBox.SelectionMode = 'MultiExtended'
    $script:CheckedNamesListBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:CheckedNamesListBox.ForeColor = [System.Drawing.Color]::FromArgb(225,232,242)
    $checkedForm.Controls.Add($script:CheckedNamesListBox)
    $recheckChecked = New-Object System.Windows.Forms.Button
    $recheckChecked.Text = '↻ Проверить снова'
    $recheckChecked.Location = New-Object System.Drawing.Point(16,500)
    $recheckChecked.Size = New-Object System.Drawing.Size(180,34)
    $recheckChecked.Anchor = 'Bottom, Left'
    $recheckChecked.FlatStyle = 'Flat'
    $recheckChecked.BackColor = [System.Drawing.Color]::FromArgb(93,73,222)
    $recheckChecked.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $checkedForm.Controls.Add($recheckChecked)
    $deleteChecked = New-Object System.Windows.Forms.Button
    $deleteChecked.Text = 'Удалить из списка'
    $deleteChecked.Location = New-Object System.Drawing.Point(204,500)
    $deleteChecked.Size = New-Object System.Drawing.Size(160,34)
    $deleteChecked.Anchor = 'Bottom, Left'
    $deleteChecked.FlatStyle = 'Flat'
    $deleteChecked.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $deleteChecked.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $checkedForm.Controls.Add($deleteChecked)
    $clearChecked = New-Object System.Windows.Forms.Button
    $clearChecked.Text = 'Очистить весь список'
    $clearChecked.Location = New-Object System.Drawing.Point(372,500)
    $clearChecked.Size = New-Object System.Drawing.Size(160,34)
    $clearChecked.Anchor = 'Bottom, Left'
    $clearChecked.FlatStyle = 'Flat'
    $clearChecked.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $clearChecked.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $checkedForm.Controls.Add($clearChecked)
    $script:CheckedNamesSearchBox.Add_TextChanged({ Refresh-CheckedNamesList })
    $deleteChecked.Add_Click({
        $selectedItems = @($script:CheckedNamesListBox.SelectedItems)
        if ($selectedItems.Count -lt 1) {
            [System.Windows.Forms.MessageBox]::Show('Сначала выдели имена в списке.','Проверенные ники','OK','Information') | Out-Null
            return
        }
        foreach ($selectedItem in $selectedItems) { $script:CheckedNames.Remove([string]$selectedItem.Key) }
        Mark-HistoryDirty
        Refresh-CheckedNamesList
        Update-CheckedNamesButtonText
        Add-Diagnostic ('Из списка проверенных удалено имён: {0}. Теперь они снова могут попасть в выдачу.' -f $selectedItems.Count)
    })
    $clearChecked.Add_Click({
        if ($script:CheckedNames.Count -lt 1) {
            [System.Windows.Forms.MessageBox]::Show('Список проверенных имён уже пуст.','Проверенные ники','OK','Information') | Out-Null
            return
        }
        $removedCount = $script:CheckedNames.Count
        $confirm = [System.Windows.Forms.MessageBox]::Show(('Удалить все проверенные имена ({0}) из списка? Они снова смогут попасть в выдачу.' -f $removedCount),'Очистка списка','YesNo','Question')
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $script:CheckedNames.Clear()
        Mark-HistoryDirty
        Refresh-CheckedNamesList
        Update-CheckedNamesButtonText
        Add-Diagnostic ('Список проверенных имён очищен: удалено {0}.' -f $removedCount)
    })
    $recheckChecked.Add_Click({
        $selectedItems = @($script:CheckedNamesListBox.SelectedItems)
        if ($selectedItems.Count -lt 1) {
            [System.Windows.Forms.MessageBox]::Show('Сначала выдели имена в списке.','Повторная проверка','OK','Information') | Out-Null
            return
        }
        $targetPlatform = [string]$selectedItems[0].Platform
        if (-not (Test-SupportedPlatform -Platform $targetPlatform)) {
            [System.Windows.Forms.MessageBox]::Show(("Платформа «{0}» больше не поддерживается этой версией программы.`r`n`r`nПовторная проверка доступна для: {1}." -f $targetPlatform, ($script:SupportedPlatforms -join ', ')),'Повторная проверка','OK','Information') | Out-Null
            return
        }
        $queued = 0
        $skipped = 0
        foreach ($selectedItem in $selectedItems) {
            if ([string]$selectedItem.Platform -ne $targetPlatform) { $skipped++; continue }
            $recheckName = [string]$selectedItem.Name
            $script:CheckedNames.Remove([string]$selectedItem.Key)
            $existing = Find-Candidate -Name $recheckName -Platform $targetPlatform
            if (-not $existing) {
                $existing = [pscustomobject]@{Name=$recheckName; Platform=$targetPlatform; Meaning='Повторная проверка из списка проверенных'; Category='Проверенные ранее'; Structure=(Get-NickStructure -Name $recheckName); Status='Ожидает'; Time=''; Reason='Запрошена повторная проверка'; Checked=$false}
                [void]$script:Candidates.Add($existing)
                Register-Candidate $existing
            }
            $existing.Status = 'Ожидает'
            $existing.Time = ''
            $existing.Reason = 'Запрошена повторная проверка'
            $existing.Checked = $false
            $queued++
        }
        if ($queued -lt 1) {
            [System.Windows.Forms.MessageBox]::Show('Не удалось поставить имена в очередь проверки.','Повторная проверка','OK','Information') | Out-Null
            return
        }
        Mark-HistoryDirty
        Touch-Candidates
        Update-CheckedNamesButtonText
        $checkedForm.Close()
        $script:PlatformBox.SelectedItem = $targetPlatform
        Update-ResultGrid
        $skipNote = ''
        if ($skipped -gt 0) { $skipNote = ('; пропущено имён другой платформы: {0}' -f $skipped) }
        Add-Diagnostic ('Повторная проверка: {0} имён ({1}){2}.' -f $queued, $targetPlatform, $skipNote)
        Start-Checking -RetryErrorsOnly $false
    })
    $checkedForm.Add_FormClosed({
        $script:CheckedNamesListBox = $null
        $script:CheckedNamesSearchBox = $null
        $script:CheckedNamesDescription = $null
    })
    Refresh-CheckedNamesList
    $checkedForm.Add_Shown({ $checkedForm.Activate() })
    [void]$checkedForm.ShowDialog($script:Form)
}

function Open-FreeHistoryWindow {
    $script:HistoryForm = New-Object System.Windows.Forms.Form
    $script:HistoryForm.Text = 'Последние свободные ники'
    $script:HistoryForm.StartPosition = 'CenterParent'
    $script:HistoryForm.Size = New-Object System.Drawing.Size(700,580)
    $script:HistoryForm.MinimumSize = New-Object System.Drawing.Size(560,480)
    $script:HistoryForm.BackColor = [System.Drawing.Color]::FromArgb(15,19,27)
    $script:HistoryForm.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $script:HistoryForm.Font = New-Object System.Drawing.Font($script:UiFontFamily,9)
    Set-WindowChrome -Window $script:HistoryForm
    $script:HistoryDescription = New-Object System.Windows.Forms.Label
    $script:HistoryDescription.Location = New-Object System.Drawing.Point(16,12)
    $script:HistoryDescription.Size = New-Object System.Drawing.Size(650,40)
    $script:HistoryDescription.ForeColor = [System.Drawing.Color]::FromArgb(190,202,221)
    $script:HistoryForm.Controls.Add($script:HistoryDescription)
    $historyPlatformLabel = New-Object System.Windows.Forms.Label
    $historyPlatformLabel.Text = 'Показывать платформы (пусто = все)'
    $historyPlatformLabel.Location = New-Object System.Drawing.Point(16,66)
    $historyPlatformLabel.Size = New-Object System.Drawing.Size(360,20)
    $historyPlatformLabel.ForeColor = [System.Drawing.Color]::FromArgb(203,213,228)
    $script:HistoryForm.Controls.Add($historyPlatformLabel)
    $script:HistoryPlatformList = New-Object System.Windows.Forms.CheckedListBox
    $script:HistoryPlatformList.Location = New-Object System.Drawing.Point(16,90)
    $script:HistoryPlatformList.Size = New-Object System.Drawing.Size(160,360)
    $script:HistoryPlatformList.Anchor = 'Top, Bottom, Left'
    $script:HistoryPlatformList.CheckOnClick = $true
    $script:HistoryPlatformList.IntegralHeight = $false
    $script:HistoryPlatformList.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:HistoryPlatformList.ForeColor = [System.Drawing.Color]::FromArgb(225,232,242)
    $script:HistoryPlatformList.BorderStyle = 'FixedSingle'
    $script:HistoryPlatformList.Add_ItemCheck({ if ($script:HistoryFilterReady -and $script:HistoryForm -and -not $script:HistoryForm.IsDisposed -and $script:HistoryForm.IsHandleCreated) { $script:HistoryForm.BeginInvoke([System.Action]{ Refresh-FreeHistoryList }) } })
    $script:HistoryForm.Controls.Add($script:HistoryPlatformList)
    $script:HistoryListBox = New-Object System.Windows.Forms.ListBox
    $script:HistoryListBox.Location = New-Object System.Drawing.Point(188,90)
    $script:HistoryListBox.Size = New-Object System.Drawing.Size(480,360)
    $script:HistoryListBox.Anchor = 'Top, Bottom, Left, Right'
    $script:HistoryListBox.DisplayMember = 'Display'
    $script:HistoryListBox.SelectionMode = 'MultiExtended'
    $script:HistoryListBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:HistoryListBox.ForeColor = [System.Drawing.Color]::FromArgb(225,232,242)
    $script:HistoryForm.Controls.Add($script:HistoryListBox)
    $selectAllHistory = New-Object System.Windows.Forms.Button
    $selectAllHistory.Text = 'Выделить все'
    $selectAllHistory.Location = New-Object System.Drawing.Point(16,466)
    $selectAllHistory.Size = New-Object System.Drawing.Size(84,34)
    $selectAllHistory.Anchor = 'Bottom, Left'
    $selectAllHistory.FlatStyle = 'Flat'
    $selectAllHistory.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $selectAllHistory.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $script:HistoryForm.Controls.Add($selectAllHistory)
    $clearHistorySelection = New-Object System.Windows.Forms.Button
    $clearHistorySelection.Text = 'Снять все'
    $clearHistorySelection.Location = New-Object System.Drawing.Point(104,466)
    $clearHistorySelection.Size = New-Object System.Drawing.Size(76,34)
    $clearHistorySelection.Anchor = 'Bottom, Left'
    $clearHistorySelection.FlatStyle = 'Flat'
    $clearHistorySelection.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $clearHistorySelection.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $script:HistoryForm.Controls.Add($clearHistorySelection)
    $selectAllHistory.Add_Click({
        if ($script:HistoryListBox) { for ($historyIndex = 0; $historyIndex -lt $script:HistoryListBox.Items.Count; $historyIndex++) { $script:HistoryListBox.SetSelected($historyIndex, $true) } }
    })
    $clearHistorySelection.Add_Click({
        if ($script:HistoryListBox) { $script:HistoryListBox.ClearSelected() }
    })
    $recheck = New-Object System.Windows.Forms.Button
    $recheck.Text = '↻ Повторная проверка'
    $recheck.Location = New-Object System.Drawing.Point(188,466)
    $recheck.Size = New-Object System.Drawing.Size(150,34)
    $recheck.Anchor = 'Bottom, Left'
    $recheck.FlatStyle = 'Flat'
    $recheck.BackColor = [System.Drawing.Color]::FromArgb(93,73,222)
    $recheck.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $recheck.Enabled = -not (Test-CheckRunning)
    $script:HistoryForm.Controls.Add($recheck)
    $copy = New-Object System.Windows.Forms.Button
    $copy.Text = 'Копировать ник'
    $copy.Location = New-Object System.Drawing.Point(346,466)
    $copy.Size = New-Object System.Drawing.Size(150,34)
    $copy.Anchor = 'Bottom, Left'
    $copy.FlatStyle = 'Flat'
    $copy.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $copy.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $script:HistoryForm.Controls.Add($copy)
    $open = New-Object System.Windows.Forms.Button
    $open.Text = 'Открыть сайт'
    $open.Location = New-Object System.Drawing.Point(504,466)
    $open.Size = New-Object System.Drawing.Size(164,34)
    $open.Anchor = 'Bottom, Right'
    $open.FlatStyle = 'Flat'
    $open.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $open.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $script:HistoryForm.Controls.Add($open)
    $copy.Add_Click({
        $selectedItems = @($script:HistoryListBox.SelectedItems)
        if ($selectedItems.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Сначала выбери ник (или несколько) в списке.','Копирование','OK','Information') | Out-Null; return }
        $selectedNames = @($selectedItems | ForEach-Object { [string]$_.Name })
        Copy-UufTextToClipboard -Text ($selectedNames -join [Environment]::NewLine) -Context 'копирование ников из свободных' | Out-Null
    })
    $open.Add_Click({
        $selected = $script:HistoryListBox.SelectedItem
        if ($selected) { Start-Process (Get-PlatformWebsiteUrl -Platform ([string]$selected.Platform) -Username ([string]$selected.Name)) }
    })
    $recheck.Add_Click({
        $selectedItems = @($script:HistoryListBox.SelectedItems)
        if ($selectedItems.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Сначала выбери ник (или несколько) в списке.','Повторная проверка','OK','Information') | Out-Null; return }
        $selectedPlatforms = @($selectedItems | ForEach-Object { [string]$_.Platform } | Sort-Object -Unique)
        if ($selectedPlatforms.Count -gt 1) {
            [System.Windows.Forms.MessageBox]::Show('Повторная проверка работает для ников одной платформы за раз. Выдели ники только одной платформы.','Повторная проверка','OK','Information') | Out-Null
            return
        }
        $selectedPlatform = [string]$selectedPlatforms[0]
        if (-not (Test-SupportedPlatform -Platform $selectedPlatform)) {
            [System.Windows.Forms.MessageBox]::Show(("Платформа «{0}» больше не поддерживается этой версией программы." -f $selectedPlatform),'Повторная проверка','OK','Information') | Out-Null
            Add-Diagnostic ("Повторная проверка отменена: платформа $selectedPlatform не поддерживается.")
            return
        }
        if (Test-CheckRunning) {
            [System.Windows.Forms.MessageBox]::Show('Идёт проверка. Дождись завершения или останови её.','Повторная проверка','OK','Information') | Out-Null
            return
        }
        $script:HistoryForm.Close()
        $script:PlatformBox.SelectedItem = $selectedPlatform
        foreach ($selectedItem in $selectedItems) {
            $selectedName = [string]$selectedItem.Name
            $candidate = Find-Candidate -Name $selectedName -Platform $selectedPlatform
            if (-not $candidate) {
                $candidate = [pscustomobject]@{Name=$selectedName; Platform=$selectedPlatform; Meaning='Повторная проверка из истории'; Category='История свободных'; Structure=(Get-NickStructure -Name $selectedName); Status='Ожидает'; Time=''; Reason='Запрошена повторная проверка'; Checked=$false}
                [void]$script:Candidates.Add($candidate)
                Register-Candidate $candidate
            }
            $candidate.Status = 'Ожидает'
            $candidate.Time = ''
            $candidate.Reason = 'Запрошена повторная проверка'
            $candidate.Checked = $false
            $script:CheckedNames.Remove((Get-HistoryKey -Name $selectedName -Platform $selectedPlatform))
        }
        Touch-Candidates
        Update-ResultGrid
        Add-Diagnostic ("Повторная проверка: {0} ник(ов), платформа {1}." -f $selectedItems.Count, $selectedPlatform)
        # --- Возобновляем только выбранные ники (статус «Ожидает»), остальные таблицы не трогаем
        Start-Checking -RetryErrorsOnly $false -ResumePending $true
    })
    Set-ButtonEdgeStyle -Root $script:HistoryForm
    $historyOrderedPlatforms = @($script:SupportedPlatforms)
    $historyPlatforms = @($script:FreeHistory | ForEach-Object { [string]$_.Platform } | Sort-Object -Unique)
    foreach ($orphanPlatform in $historyPlatforms) { if ($historyOrderedPlatforms -notcontains $orphanPlatform) { $historyOrderedPlatforms += $orphanPlatform } }
    $script:HistoryFilterReady = $false
    $script:HistoryPlatformList.Items.Clear()
    [void]$script:HistoryPlatformList.Items.AddRange([object[]]@($historyOrderedPlatforms))
    for ($historyPlatformIndex = 0; $historyPlatformIndex -lt $script:HistoryPlatformList.Items.Count; $historyPlatformIndex++) {
        $historyItemPlatform = [string]$script:HistoryPlatformList.Items[$historyPlatformIndex]
        $script:HistoryPlatformList.SetItemChecked($historyPlatformIndex, ($historyPlatforms -contains $historyItemPlatform))
    }
    $script:HistoryFilterReady = $true
    Refresh-FreeHistoryList
    $script:HistoryForm.Add_FormClosed({
        $script:HistoryListBox = $null
        $script:HistoryPlatformList = $null
        $script:HistoryDescription = $null
        $script:HistoryFilterReady = $false
        $script:HistoryForm = $null
    })
    $script:HistoryForm.Add_Shown({ $script:HistoryForm.Activate() })
    [void]$script:HistoryForm.ShowDialog($script:Form)
}

# --- Проверка соединения: доступность платформ, время ответа и HTTP-статус
# --- Пинг здесь — время HTTP-ответа (ICMP-ping веб-сервисы часто блокируют). Запросы только GET, без входа и без обхода защит.
$script:ConnectionEndpoints = @(
    [pscustomobject]@{Platform='Telegram';  Url='https://t.me/'},
    [pscustomobject]@{Platform='YouTube';   Url='https://www.youtube.com/'},
    [pscustomobject]@{Platform='Google';    Url='https://accounts.google.com/'},
    [pscustomobject]@{Platform='Outlook';   Url='https://signup.live.com/'},
    [pscustomobject]@{Platform='Discord';   Url='https://discord.com/api/v9/gateway'},
    [pscustomobject]@{Platform='GitHub';    Url='https://api.github.com/zen'},
    [pscustomobject]@{Platform='Steam';     Url='https://steamcommunity.com/'},
    [pscustomobject]@{Platform='Roblox';    Url='https://www.roblox.com/'},
    [pscustomobject]@{Platform='VK';        Url='https://vk.com/'},
    [pscustomobject]@{Platform='Mail.ru';   Url='https://account.mail.ru/'}
)
# --- Описания HTTP-кодов по MDN: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status
$script:HttpStatusNotes = @{
    200 = 'OK — запрос выполнен';
    201 = 'Created — ресурс создан';
    204 = 'No Content — успех без тела ответа';
    301 = 'Moved Permanently — адрес перенесён навсегда';
    302 = 'Found — временное перенаправление';
    303 = 'See Other — смотри другой адрес';
    304 = 'Not Modified — ресурс не изменился';
    307 = 'Temporary Redirect — временное перенаправление';
    308 = 'Permanent Redirect — постоянное перенаправление';
    400 = 'Bad Request — неверный запрос';
    401 = 'Unauthorized — нужна аутентификация';
    403 = 'Forbidden — доступ запрещён сервером';
    404 = 'Not Found — ресурс не найден';
    405 = 'Method Not Allowed — метод не разрешён';
    408 = 'Request Timeout — сервер не дождался запроса';
    409 = 'Conflict — конфликт с состоянием ресурса';
    410 = 'Gone — ресурс удалён';
    418 = 'I''m a teapot — сервер отказывается варить кофе';
    429 = 'Too Many Requests — превышен лимит запросов';
    500 = 'Internal Server Error — ошибка на стороне сервера';
    501 = 'Not Implemented — метод не поддерживается';
    502 = 'Bad Gateway — плохой ответ вышестоящего сервера';
    503 = 'Service Unavailable — сервис временно недоступен';
    504 = 'Gateway Timeout — вышестоящий сервер не ответил вовремя'
}

function Get-ConnectionVerdict {
    param([int]$Code, [string]$ErrorText)
    if ($Code -le 0) {
        if ($ErrorText -match 'timed out|timeout|время|таймаут') { return [pscustomobject]@{Result='Долго отвечает'; Note=('таймаут: ' + $ErrorText)} }
        $noteText = 'соединение не установлено'
        if ($ErrorText) { $noteText = $ErrorText }
        return [pscustomobject]@{Result='Нет связи'; Note=$noteText}
    }
    $codeNote = 'HTTP ' + $Code
    if ($script:HttpStatusNotes.ContainsKey($Code)) { $codeNote = [string]$script:HttpStatusNotes[$Code] }
    if ($Code -ge 200 -and $Code -lt 400) { return [pscustomobject]@{Result='pass'; Note='Clear'} }
    if ($Code -ge 400 -and $Code -lt 500) { return [pscustomobject]@{Result='denied'; Note=$codeNote} }
    if ($Code -ge 500) { return [pscustomobject]@{Result='error'; Note=$codeNote} }
    return [pscustomobject]@{Result='unknown'; Note=$codeNote}
}

# --- Скрипт фонового запроса: выполняется в отдельном runspace, окно не зависает
$script:ConnectionScript = @'
param($Url, $TimeoutSec, $Proxy, $UserAgent, $Queue, $Platform)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
$code = 0
$errorText = ''
$watch = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $requestArgs = @{ Uri = $Url; Method = 'Get'; TimeoutSec = $TimeoutSec; UseBasicParsing = $true; Headers = @{ 'User-Agent' = $UserAgent }; MaximumRedirection = 0 }
    if ($Proxy) { $requestArgs.Proxy = $Proxy }
    $response = Invoke-WebRequest @requestArgs
    $code = [int]$response.StatusCode
} catch {
    try { if ($null -ne $_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } } catch { $code = 0 }
    if ($code -eq 0) {
        $inner = $_.Exception
        while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
        $errorText = [string]$inner.Message
    }
}
$watch.Stop()
$null = $Queue.Enqueue([pscustomobject]@{ Platform = $Platform; Code = $code; Ms = [int]$watch.ElapsedMilliseconds; Error = $errorText })
'@

function Stop-ConnectionTest {
    if ($script:ConnTimer) { try { $script:ConnTimer.Stop() } catch { } }
    foreach ($connPs in @($script:ConnPowerShells)) { try { if ($connPs) { $connPs.Stop(); $connPs.Dispose() } } catch { } }
    foreach ($connRs in @($script:ConnRunspaces)) { try { if ($connRs) { $connRs.Close(); $connRs.Dispose() } } catch { } }
    $script:ConnPowerShells = New-Object 'System.Collections.Generic.List[object]'
    $script:ConnRunspaces = New-Object 'System.Collections.Generic.List[object]'
}

function Get-ConnectionReportLines {
    $reportLines = New-Object 'System.Collections.Generic.List[string]'
    $reportIndex = 0
    if ($null -eq $script:ConnGrid) { return @() }
    foreach ($reportRow in $script:ConnGrid.Rows) {
        $reportIndex++
        $pingCell = [string]$reportRow.Cells['Ping'].Value
        $resultCell = [string]$reportRow.Cells['Result'].Value
        $noteCell = [string]$reportRow.Cells['Note'].Value
        $reportLines.Add(("{0}. {1}.api - {2}, ping: {3}, Error: {4}" -f $reportIndex, [string]$reportRow.Cells['Platform'].Value, $resultCell, $pingCell, $noteCell))
    }
    return @($reportLines)
}

function Start-ConnectionTest {
    if ($null -eq $script:ConnGrid) { return }
    Stop-ConnectionTest
    $script:ConnGrid.Rows.Clear()
    $connProxy = ''
    try { $connProxy = [string]$script:ProxyBox.Text.Trim() } catch { $connProxy = '' }
    if ($connProxy -and $connProxy -notmatch '^[A-Za-z][A-Za-z0-9+.-]*://') { $connProxy = 'http://' + $connProxy }
    $connUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36'
    $script:ConnQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $script:ConnTotal = @($script:ConnectionEndpoints).Count
    $script:ConnDone = 0
    foreach ($connEndpoint in $script:ConnectionEndpoints) {
        [void]$script:ConnGrid.Rows.Add([object[]]@([string]$connEndpoint.Platform, [string]$connEndpoint.Url, 'проверяется…', '—', '—', ''))
        $connRunspace = [RunspaceFactory]::CreateRunspace()
        $connRunspace.Open()
        $connPowerShell = [PowerShell]::Create()
        $connPowerShell.Runspace = $connRunspace
        [void]$connPowerShell.AddScript($script:ConnectionScript).AddArgument([string]$connEndpoint.Url).AddArgument(8).AddArgument($connProxy).AddArgument($connUserAgent).AddArgument($script:ConnQueue).AddArgument([string]$connEndpoint.Platform)
        $null = $connPowerShell.BeginInvoke()
        $script:ConnPowerShells.Add($connPowerShell)
        $script:ConnRunspaces.Add($connRunspace)
    }
    if ($null -eq $script:ConnTimer) {
        $script:ConnTimer = New-Object System.Windows.Forms.Timer
        $script:ConnTimer.Interval = 150
        $script:ConnTimer.Add_Tick({
            $connEntry = $null
            while ($script:ConnQueue -and $script:ConnQueue.TryDequeue([ref]$connEntry)) {
                if ($null -eq $connEntry) { continue }
                $verdict = Get-ConnectionVerdict -Code ([int]$connEntry.Code) -ErrorText ([string]$connEntry.Error)
                $pingText = ('{0}ms' -f [int]$connEntry.Ms)
                if ([int]$connEntry.Code -le 0) { $pingText = 'нет ответа' }
                $codeText = '—'
                if ([int]$connEntry.Code -gt 0) { $codeText = [string]$connEntry.Code }
                foreach ($connRow in $script:ConnGrid.Rows) {
                    if ([string]$connRow.Cells['Platform'].Value -eq [string]$connEntry.Platform) {
                        $connRow.Cells['Result'].Value = $verdict.Result
                        $connRow.Cells['Ping'].Value = $pingText
                        $connRow.Cells['Code'].Value = $codeText
                        $connRow.Cells['Note'].Value = [string]$verdict.Note
                        if ($verdict.Result -eq 'pass') { $connRow.Cells['Result'].Style.ForeColor = [System.Drawing.Color]::FromArgb(110,220,150) }
                        elseif ($verdict.Result -eq 'denied' -or $verdict.Result -eq 'error' -or $verdict.Result -eq 'Нет связи' -or $verdict.Result -eq 'Долго отвечает') { $connRow.Cells['Result'].Style.ForeColor = [System.Drawing.Color]::FromArgb(255,138,128) }
                        break
                    }
                }
                $script:ConnDone++
                Add-Diagnostic ('Соединение: {0}.api - {1}, ping: {2}, HTTP: {3}' -f [string]$connEntry.Platform, $verdict.Result, $pingText, $codeText)
                $connEntry = $null
            }
            if ($script:ConnTotal -gt 0 -and $script:ConnDone -ge $script:ConnTotal) {
                $script:ConnTimer.Stop()
                if ($script:ConnStatus) { $script:ConnStatus.Text = ('Готово: проверено платформ — {0}. Пинг — время HTTP-ответа.' -f $script:ConnDone) }
                Stop-ConnectionTest
            }
        })
    }
    if ($script:ConnStatus) { $script:ConnStatus.Text = 'Проверка идёт…' }
    $script:ConnTimer.Start()
}

function Open-ConnectionTestWindow {
    $connForm = New-Object System.Windows.Forms.Form
    $connForm.Text = 'Проверка соединения'
    $connForm.StartPosition = 'CenterParent'
    $connForm.Size = New-Object System.Drawing.Size(900,640)
    $connForm.MinimumSize = New-Object System.Drawing.Size(760,600)
    $connForm.BackColor = [System.Drawing.Color]::FromArgb(15,19,27)
    $connForm.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $connForm.Font = New-Object System.Drawing.Font($script:UiFontFamily,9)
    Set-WindowChrome -Window $connForm
    $connInfo = New-Object System.Windows.Forms.Label
    $connInfo.Text = 'Тестовый запрос к публичным адресам платформ. «pass» — сервер ответил (2xx/3xx), «denied» — отказ (4xx), «error» — ошибка сервера (5xx), «Нет связи» — соединение не открылось. Пинг — время ответа сервера.'
    $connInfo.Location = New-Object System.Drawing.Point(16,12)
    $connInfo.Size = New-Object System.Drawing.Size(856,44)
    $connInfo.Anchor = 'Top, Left, Right'
    $connInfo.ForeColor = [System.Drawing.Color]::FromArgb(190,202,221)
    $connForm.Controls.Add($connInfo)
    $script:ConnGrid = New-Object System.Windows.Forms.DataGridView
    $script:ConnGrid.Location = New-Object System.Drawing.Point(16,62)
    $script:ConnGrid.Size = New-Object System.Drawing.Size(856,280)
    $script:ConnGrid.Anchor = 'Top, Left, Right'
    $script:ConnGrid.BackgroundColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:ConnGrid.BorderStyle = 'None'
    $script:ConnGrid.GridColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $script:ConnGrid.EnableHeadersVisualStyles = $false
    $script:ConnGrid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(30,38,52)
    $script:ConnGrid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(203,213,228)
    $script:ConnGrid.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:ConnGrid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(225,232,242)
    $script:ConnGrid.ReadOnly = $true
    $script:ConnGrid.AllowUserToAddRows = $false
    $script:ConnGrid.AllowUserToDeleteRows = $false
    $script:ConnGrid.RowHeadersVisible = $false
    $script:ConnGrid.SelectionMode = 'FullRowSelect'
    $script:ConnGrid.AutoSizeColumnsMode = 'Fill'
    foreach ($colSpec in @(@('Platform','Платформа',110),@('Url','Адрес',250),@('Result','Результат',120),@('Ping','Пинг',90),@('Code','HTTP',60),@('Note','Error (пояснение HTTP-кода)',226))) {
        $column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $column.Name = $colSpec[0]
        $column.HeaderText = $colSpec[1]
        $column.FillWeight = [int]$colSpec[2]
        [void]$script:ConnGrid.Columns.Add($column)
    }
    $connForm.Controls.Add($script:ConnGrid)
    $legendBox = New-Object System.Windows.Forms.TextBox
    $legendBox.Multiline = $true
    $legendBox.ReadOnly = $true
    $legendBox.ScrollBars = 'Vertical'
    $legendBox.Location = New-Object System.Drawing.Point(16,352)
    $legendBox.Size = New-Object System.Drawing.Size(856,200)
    $legendBox.Anchor = 'Top, Bottom, Left, Right'
    $legendBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $legendBox.ForeColor = [System.Drawing.Color]::FromArgb(190,202,221)
    $legendBox.Font = New-Object System.Drawing.Font('Consolas',8.5)
    $legendLines = @('Таблица HTTP-кодов (MDN Web Docs):')
    foreach ($legendCode in @($script:HttpStatusNotes.Keys | Sort-Object)) { $legendLines += ('{0} — {1}' -f $legendCode, $script:HttpStatusNotes[$legendCode]) }
    $legendBox.Text = ($legendLines -join [Environment]::NewLine)
    $connForm.Controls.Add($legendBox)
    $connRunButton = New-Object System.Windows.Forms.Button
    $connRunButton.Text = '↻ Проверить снова'
    $connRunButton.Location = New-Object System.Drawing.Point(16,566)
    $connRunButton.Size = New-Object System.Drawing.Size(160,34)
    $connRunButton.Anchor = 'Bottom, Left'
    $connRunButton.FlatStyle = 'Flat'
    $connRunButton.BackColor = [System.Drawing.Color]::FromArgb(93,73,222)
    $connRunButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $connForm.Controls.Add($connRunButton)
    $connCopyButton = New-Object System.Windows.Forms.Button
    $connCopyButton.Text = 'Копировать отчёт'
    $connCopyButton.Location = New-Object System.Drawing.Point(184,566)
    $connCopyButton.Size = New-Object System.Drawing.Size(160,34)
    $connCopyButton.Anchor = 'Bottom, Left'
    $connCopyButton.FlatStyle = 'Flat'
    $connCopyButton.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $connCopyButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $connForm.Controls.Add($connCopyButton)
    $script:ConnStatus = New-Object System.Windows.Forms.Label
    $script:ConnStatus.Location = New-Object System.Drawing.Point(358,570)
    $script:ConnStatus.Size = New-Object System.Drawing.Size(514,26)
    $script:ConnStatus.Anchor = 'Bottom, Left, Right'
    $script:ConnStatus.ForeColor = [System.Drawing.Color]::FromArgb(149,164,187)
    $script:ConnStatus.TextAlign = 'MiddleRight'
    $connForm.Controls.Add($script:ConnStatus)
    $connRunButton.Add_Click({ Start-ConnectionTest })
    $connCopyButton.Add_Click({
        $reportText = (Get-ConnectionReportLines) -join [Environment]::NewLine
        if ($reportText) { Copy-UufTextToClipboard -Text $reportText -Context 'копирование отчёта о соединении' | Out-Null }
    })
    $connForm.Add_Shown({ Start-ConnectionTest })
    $connForm.Add_FormClosed({
        Stop-ConnectionTest
        $script:ConnGrid = $null
        $script:ConnStatus = $null
    })
    Set-ButtonEdgeStyle -Root $connForm
    [void]$connForm.ShowDialog($script:Form)
}

# --- Помощь
# --- Окно помощи: ряд кнопок-разделов сверху и одна страница карточек (без вкладок и пересчёта по Resize)
function Add-HelpCard {
    param([System.Windows.Forms.Panel]$CardHost, [string]$Heading, [string]$Body, [System.Drawing.Font]$HeadingFont, [System.Drawing.Font]$BodyFont)
    $Body = $Body.Replace('<br>', [Environment]::NewLine)
    $card = New-Object System.Windows.Forms.Panel
    $card.BackColor = [System.Drawing.Color]::FromArgb(23,30,42)
    $accent = New-Object System.Windows.Forms.Panel
    $accent.Dock = 'Left'
    $accent.Width = 4
    $accent.BackColor = [System.Drawing.Color]::FromArgb(93,73,222)
    $headingLabel = New-Object System.Windows.Forms.Label
    $headingLabel.Text = $Heading
    $headingLabel.Location = New-Object System.Drawing.Point(18,10)
    $headingLabel.Size = New-Object System.Drawing.Size(600,22)
    $headingLabel.Font = $HeadingFont
    $headingLabel.ForeColor = [System.Drawing.Color]::FromArgb(147,189,255)
    $headingLabel.BackColor = [System.Drawing.Color]::FromArgb(23,30,42)
    $bodyLabel = New-Object System.Windows.Forms.Label
    $bodyLabel.Text = $Body
    $bodyLabel.Location = New-Object System.Drawing.Point(18,36)
    $bodyLabel.Size = New-Object System.Drawing.Size(600,20)
    $bodyLabel.Font = $BodyFont
    $bodyLabel.ForeColor = [System.Drawing.Color]::FromArgb(208,216,230)
    $bodyLabel.BackColor = [System.Drawing.Color]::FromArgb(23,30,42)
    $card.Controls.Add($bodyLabel)
    $card.Controls.Add($headingLabel)
    $card.Controls.Add($accent)
    $card.Tag = $bodyLabel
    $CardHost.Controls.Add($card)
}

function Set-HelpCardLayout {
    param([System.Windows.Forms.Panel]$CardHost)
    # --- Защита от повторного входа: смена размеров вызывает Resize и снова эту функцию
    if ($script:HelpLayoutBusy) { return }
    $script:HelpLayoutBusy = $true
    try {
        $cardWidth = [Math]::Max(300, $CardHost.ClientSize.Width - 40)
        $bodyWidth = $cardWidth - 40
        $y = 12
        foreach ($card in @($CardHost.Controls)) {
            $bodyLabel = $card.Tag
            if ($null -eq $bodyLabel) { continue }
            $measured = [System.Windows.Forms.TextRenderer]::MeasureText([string]$bodyLabel.Text, $bodyLabel.Font, (New-Object System.Drawing.Size($bodyWidth, 5000)), [System.Windows.Forms.TextFormatFlags]::WordBreak)
            $bodyHeight = [int]$measured.Height + 6
            $bodySize = New-Object System.Drawing.Size($bodyWidth, $bodyHeight)
            if ($bodyLabel.Size -ne $bodySize) { $bodyLabel.Size = $bodySize }
            foreach ($inner in @($card.Controls)) {
                if ($inner -is [System.Windows.Forms.Label] -and $inner -ne $bodyLabel) {
                    $innerSize = New-Object System.Drawing.Size($bodyWidth, 22)
                    if ($inner.Size -ne $innerSize) { $inner.Size = $innerSize }
                }
            }
            $cardSize = New-Object System.Drawing.Size($cardWidth, (46 + $bodyHeight))
            if ($card.Size -ne $cardSize) { $card.Size = $cardSize }
            $cardLocation = New-Object System.Drawing.Point(16,$y)
            if ($card.Location -ne $cardLocation) { $card.Location = $cardLocation }
            $y += $card.Height + 12
        }
        $minSize = New-Object System.Drawing.Size(0, ($y + 8))
        if ($CardHost.AutoScrollMinSize -ne $minSize) { $CardHost.AutoScrollMinSize = $minSize }
    } finally {
        $script:HelpLayoutBusy = $false
    }
}

function Show-HelpPage {
    param([System.Windows.Forms.Panel]$PageHost, $Pages, [int]$Index, $NavButtons, $HeadingFont, $BodyFont)
    if ($Index -lt 0 -or $Index -ge @($Pages).Count) { return }
    $PageHost.SuspendLayout()
    foreach ($oldCard in @($PageHost.Controls)) {
        $PageHost.Controls.Remove($oldCard)
        $oldCard.Dispose()
    }
    foreach ($cardItem in $Pages[$Index].Cards) {
        Add-HelpCard -CardHost $PageHost -Heading ([string]$cardItem[0]) -Body ([string]$cardItem[1]) -HeadingFont $HeadingFont -BodyFont $BodyFont
    }
    Set-HelpCardLayout -CardHost $PageHost
    $PageHost.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    $PageHost.ResumeLayout()
    foreach ($navButton in @($NavButtons)) {
        if ([int]$navButton.Tag -eq $Index) {
            $navButton.BackColor = [System.Drawing.Color]::FromArgb(44,56,82)
            $navButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(129,108,255)
        } else {
            $navButton.BackColor = [System.Drawing.Color]::FromArgb(26,33,47)
            $navButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(64,78,104)
        }
    }
}

function Show-UsernameFinderHelp {
    $helpForm = New-Object System.Windows.Forms.Form
    $helpForm.Text = 'UUF — помощь'
    $helpForm.StartPosition = 'CenterParent'
    $helpForm.ClientSize = New-Object System.Drawing.Size(900,680)
    $helpForm.FormBorderStyle = 'FixedSingle'
    $helpForm.MaximizeBox = $false
    $helpForm.BackColor = [System.Drawing.Color]::FromArgb(15,19,27)
    $helpForm.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
    $helpForm.Font = New-Object System.Drawing.Font($script:UiFontFamily,9)
    Set-WindowChrome -Window $helpForm

    $headingFont = New-Object System.Drawing.Font($script:UiFontFamily,11,[System.Drawing.FontStyle]::Bold)
    $bodyFont = New-Object System.Drawing.Font($script:UiFontFamily,9.5)
    $navFont = New-Object System.Drawing.Font($script:UiFontFamily,10,[System.Drawing.FontStyle]::Bold)

    $helpPages = @(
        @{ Title = 'Дисклеймер'; Cards = @(
            @('Назначение программы', 'UUF (Universal Username Finder) помогает подбирать свободные никнеймы и логины для регистрации на популярных платформах и проверять, занято ли имя, по открытым публичным признакам: страницам регистрации и публичным API.'),
            @('Что программа не делает', 'Программа не взламывает аккаунты, не подбирает пароли, не входит в чужие учётные записи, не крадёт логины и пароли и не отправляет письма или сообщения от вашего имени.'),
            @('Как устроена проверка', 'Проверка безопасна: это обычные запросы, похожие на открытие страницы регистрации в браузере. Программа не обходит CAPTCHA, блокировки и защитные механизмы платформ. Если платформа ограничила запросы, проверка приостанавливается.'),
            @('Пользовательское соглашение', 'Используя программу, вы подтверждаете, что сами соблюдаете правила платформ и законы своей страны. Не используйте результаты для выдачи себя за другого человека, спама, мошенничества или обхода ограничений сервисов. Ответственность за дальнейшее использование ника и аккаунта лежит на пользователе.'),
            @('Хранение данных', 'Пароли, созданные в программе, сохраняются только локально в зашифрованном хранилище текущего пользователя Windows.'),
            @('Точность результатов', 'Статус «свободен» показывает состояние на момент проверки. Платформа может изменить правила или занять ник раньше вас, поэтому перед регистрацией проверяйте ник на сайте платформы.')
        ) },
        @{ Title = 'Пользование'; Cards = @(
            @('1. Выбор платформы', 'Выберите платформу в списке «Платформа». У каждой платформы свои правила формата: длина, допустимые символы, запрещённые слова.'),
            @('2. Настройка генерации', 'Отметьте стили в блоке «Настройки генерации», задайте количество и границы длины. Ручные ники и свои слова добавляются в генерацию, только если поля заполнены.'),
            @('3. Запуск', 'Нажмите «▶ Найти свободные». Генерация и проверка идут в фоне, таблица заполняется по мере работы. Остановить можно кнопкой «■ Остановить проверку».'),
            @('4. Возобновление', 'После остановки кнопка станет «▶ Возобновить проверку (N)», где N — сколько ников ещё не проверено. Продолжаются только ники со статусом «Ожидает»: уже проверенные не повторяются.'),
            @('5. Свободные ники', 'Свободные ники попадают в «Последние свободные ники». Там можно выделить один или несколько ников («Выделить все» / «Снять все»), скопировать их, открыть сайт или повторить проверку.'),
            @('6. Регистрация и пароль', 'Кнопка «Регистрация и пароль» открывает генератор пароля, страницу регистрации, поля имени и фамилии (для Google) и сохранение записи в зашифрованное хранилище. «Сохранённые аккаунты» открывает список сохранённых записей.'),
            @('7. Проверка соединения', 'Кнопка «Проверка соединения» показывает доступность платформ: результат, время ответа (пинг) и HTTP-код.'),
            @('8. Журнал', 'Кнопка «Развернуть журнал» поднимает журнал над таблицей, «Вернуть стандартно» возвращает прежнее положение.')
        ) },
        @{ Title = 'Как устроено?'; Cards = @(
            @('Генерация', 'Программа собирает кандидатов из выбранных источников: однословные ники, сочетания слов, выдуманные слова, замену символов, цифры. Каждый кандидат проходит проверку формата выбранной платформы. Ники, не подходящие по формату, отбрасываются сразу, без запроса к сайту.'),
            @('Проверка', 'Для каждого ника программа делает обычный запрос к публичному признаку платформы (страница регистрации или публичный API) и разбирает ответ. Проверка идёт в фоне с паузой между запросами, которую можно настроить.'),
            @('Статусы', 'Ожидает — ещё не проверен. Проверяется — запрос выполняется. Свободен / Занят — результат проверки. Недопустимый — не проходит формат платформы. Ошибка сети — сайт не ответил, ник можно проверить снова.'),
            @('Защита от повторов', 'Опция «Исключать проверенные» не даёт проверять один и тот же ник дважды. Свободные ники сохраняются в историю «Последние свободные ники».'),
            @('Ограничения и CAPTCHA', 'Если платформа показывает CAPTCHA или ограничивает частоту запросов, программа не обходит это. Проверка приостанавливается: попробуйте позже, увеличьте задержку или проверьте другую платформу.'),
            @('Почему возможны сбои', 'Некоторые платформы отвечают не сразу или по-разному в разных странах. Для YouTube, Telegram, Outlook, Google и Discord в нижней плашке появляется подсказка про VPN/Proxy.')
        ) },
        @{ Title = 'Настройки'; Cards = @(
            @('Однословные ники', 'Один смысловой корень, без лишних частей.<br>  Пример: lonelesee, fine, group'),
            @('Два осмысленных слова', 'Два понятных слова подряд. С разделителем «_» — через подчёркивание.<br>  Пример: darkriver, bluefox, silent_lake'),
            @('Выдуманные слова', 'Произносимые несуществующие слова.<br>  Пример: lorvesh, mavitel, quendra'),
            @('Выдуманные сочетания', 'Пары выдуманных частей.<br>  Пример: vorntiel, kasmora'),
            @('Замена символами', 'Буквы заменяются похожими цифрами и знаками (leet).<br>  Пример: fine → f1n3, group → gr0up'),
            @('Редкие короткие (3-6)', 'Ники длиной 3–6 символов. Такие имена обычно заняты первыми, свободных мало.<br>  Пример: xqv7, zorn, kvei'),
            @('Использовать цифры', 'Добавляет цифры к нику.<br>  Пример: lonelesee24'),
            @('Разделитель _', 'Вставляет подчёркивание между частями. Не работает для Google и GitHub: эти платформы его не допускают.<br>  Пример: lone_see'),
            @('Случайные символы', 'Случайные буквы и цифры.<br>  Пример: k7qzd2'),
            @('Тонкая настройка', 'Количество — сколько ников выдать. Мин. и макс. длина — границы длины. «Только короткие (≤12)» оставляет ники не длиннее 12 символов.<br>Важно: если «Только короткие» включено, а минимальная длина больше 12, ников не будет. Программа предупредит и не запустит генерацию.'),
            @('Свои слова и ручные ники', 'Свои слова — через запятую, точку с запятой или пробел, из них собираются варианты. Ручные ники — по одному на строке или через запятую, проверяются как есть. Пустое поле ничего не добавляет.'),
            @('Если не выбран ни один источник', 'Программа сообщит об этом в журнале и возьмёт однословные ники как запасной вариант.'),
            @('Скорость и сеть', 'Задержка — пауза между запросами, мс: больше значит мягче для сайтов. Таймаут — сколько ждать ответ. Потоки — число одновременных проверок. Прокси — адрес вида http://host:port, если нужен.')
        ) },
        @{ Title = 'Правила ввода'; Cards = @(
            @('Общие правила', 'Вводите латиницу, цифры и символы, которые допускает платформа. Кириллица и пробелы внутри ника не принимаются.'),
            @('Свои слова', 'Через запятую, точку с запятой или пробел.<br>  Пример: anna, blue;cloud fox'),
            @('Ручные ники', 'По одному на строке или через запятую.<br>  Пример: alex_1990, my.nick'),
            @('Google', 'От 6 до 30 символов: латиница, цифры и точка. Точка не в начале, не в конце и не подряд. Подчёркивание не допускается.'),
            @('YouTube (правила YTKits)', 'От 3 до 30 символов: латиница, цифры, точка, подчёркивание и дефис. Начинается и заканчивается буквой или цифрой.'),
            @('Telegram', 'От 5 до 32 символов: латиница, цифры и подчёркивание. Начинается с буквы.'),
            @('Outlook', 'От 3 до 64 символов: латиница, цифры, точка, подчёркивание и дефис. Не заканчивается точкой, подчёркиванием или дефисом и не содержит их подряд.'),
            @('GitHub', 'От 1 до 39 символов: латиница, цифры и дефис. Не начинается и не заканчивается дефисом, двух дефисов подряд нет.'),
            @('Остальные платформы', 'Обычно 3–32 символа: латиница, цифры, подчёркивание, точка и дефис.')
        ) }
    )

    $navButtons = @()
    $pageHost = New-Object System.Windows.Forms.Panel
    $pageHost.Location = New-Object System.Drawing.Point(16,72)
    $pageHost.Size = New-Object System.Drawing.Size(868,592)
    $pageHost.AutoScroll = $true
    $pageHost.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $helpForm.Controls.Add($pageHost)

    $buttonWidth = [int][Math]::Floor((868 - 8 * ($helpPages.Count - 1)) / $helpPages.Count)
    for ($i = 0; $i -lt $helpPages.Count; $i++) {
        $navButton = New-Object System.Windows.Forms.Button
        $navButton.Text = [string]$helpPages[$i].Title
        $navButton.Location = New-Object System.Drawing.Point((16 + $i * ($buttonWidth + 8)), 16)
        $navButton.Size = New-Object System.Drawing.Size($buttonWidth, 40)
        $navButton.FlatStyle = 'Flat'
        $navButton.FlatAppearance.BorderSize = 1
        $navButton.Font = $navFont
        $navButton.ForeColor = [System.Drawing.Color]::FromArgb(235,240,248)
        $navButton.UseVisualStyleBackColor = $false
        $navButton.Tag = $i
        $navButton.Add_Click({ param($clickSender, $clickArgs) Show-HelpPage -PageHost $pageHost -Pages $helpPages -Index ([int]$clickSender.Tag) -NavButtons $navButtons -HeadingFont $headingFont -BodyFont $bodyFont })
        $helpForm.Controls.Add($navButton)
        $navButtons += $navButton
    }

    Show-HelpPage -PageHost $pageHost -Pages $helpPages -Index 0 -NavButtons $navButtons -HeadingFont $headingFont -BodyFont $bodyFont
    [void]$helpForm.ShowDialog($script:Form)
}

function Test-CheckRunning {
    if ($null -eq $script:AsyncHandles) { return $false }
    if ($script:AsyncHandles.Count -lt 1) { return $false }
    foreach ($handle in $script:AsyncHandles) {
        if ($null -ne $handle -and -not $handle.IsCompleted) { return $true }
    }
    return $false
}

function Update-BatchProgress {
    param($Item)
    if ($null -eq $Item) { return }
    $workerKey = [string]$Item.WorkerId
    if (-not $script:WorkerDonePerThread.ContainsKey($workerKey)) { $script:WorkerDonePerThread[$workerKey] = 0 }
    $script:WorkerDonePerThread[$workerKey] = [int]$Item.Index
    $doneTotal = 0
    foreach ($perThreadDone in $script:WorkerDonePerThread.Values) { $doneTotal += [int]$perThreadDone }
    $script:CurrentBatchDone = [Math]::Min($doneTotal, [Math]::Max(0,[int]$script:CurrentBatchTotal))
}

function Get-CheckEtaText {
    param([int]$Done, [int]$Total)
    if (-not $script:CheckStartedAt) { return '' }
    if ($Done -lt 1 -or $Total -le 0 -or $Done -ge $Total) { return '' }
    $elapsedSeconds = ([DateTime]::UtcNow - $script:CheckStartedAt).TotalSeconds
    if ($elapsedSeconds -lt 0.5) { return '' }
    $perItemSeconds = $elapsedSeconds / $Done
    $remainingSeconds = [int][Math]::Ceiling($perItemSeconds * ($Total - $Done))
    if ($remainingSeconds -lt 0) { $remainingSeconds = 0 }
    $minutes = [int][Math]::Floor($remainingSeconds / 60)
    $seconds = $remainingSeconds % 60
    $finishAt = (Get-Date).AddSeconds($remainingSeconds).ToString('HH:mm:ss')
    if ($minutes -gt 0) {
        return ("осталось ~{0} мин {1} с · завершение ~{2}" -f $minutes, $seconds, $finishAt)
    }
    return ("осталось ~{0} с · завершение ~{1}" -f $seconds, $finishAt)
}

function Add-CompletionEvent {
    param($Entry)
    if ($null -eq $Entry) { return }
    if ($null -eq $script:CompletionEvent) {
        $script:CompletionEvent = [pscustomobject]@{Cancelled=$false; Error=$null; StopReason=$null; Checked=0; Total=[int]$script:CurrentBatchTotal}
    }
    if ([bool]$Entry.Cancelled) { $script:CompletionEvent.Cancelled = $true }
    if ($Entry.Error -and -not $script:CompletionEvent.Error) { $script:CompletionEvent.Error = [string]$Entry.Error }
    if ($Entry.StopReason -and -not $script:CompletionEvent.StopReason) { $script:CompletionEvent.StopReason = [string]$Entry.StopReason }
    $script:CompletionEvent.Checked = [int]$script:CompletionEvent.Checked + [int]$Entry.Checked
}

function Reset-CheckControls {
    $script:StartButton.Enabled = $true
    $script:GenerateButton.Enabled = $true
    $script:StopButton.Enabled = $false
    $script:CategoryList.Enabled = $true
    $script:CountBox.Enabled = $true
    $script:NumbersCheck.Enabled = $true
    $script:UnderscoreCheck.Enabled = $true
    $script:CustomBox.Enabled = $true
    $script:ManualNickBox.Enabled = $true
    $script:DelayBox.Enabled = $true
    $script:TimeoutBox.Enabled = $true
    if ($script:ThreadsBox) { $script:ThreadsBox.Enabled = $true }
    if ($script:PlatformBox) { $script:PlatformBox.Enabled = $true }
    if ($script:ProxyBox) { $script:ProxyBox.Enabled = $true }
    $pendingLeft = Get-PendingCandidateCount
    if ($pendingLeft -gt 0) { $script:StartButton.Visible = $true; $script:StartButton.Text = ('▶  Возобновить проверку ({0})' -f $pendingLeft) } else { $script:StartButton.Visible = $false; $script:StartButton.Text = '▶  Найти свободные' }
}

function Close-CheckRunspace {
    foreach ($worker in $script:WorkerPowerShells) {
        try { if ($worker) { $worker.Dispose() } } catch { }
    }
    foreach ($runspace in $script:WorkerRunspaces) {
        try { if ($runspace) { $runspace.Close(); $runspace.Dispose() } } catch { }
    }
    try { if ($script:Cancellation) { $script:Cancellation.Dispose() } } catch { }
    $script:WorkerPowerShells = New-Object 'System.Collections.Generic.List[object]'
    $script:WorkerRunspaces = New-Object 'System.Collections.Generic.List[object]'
    $script:AsyncHandles = New-Object 'System.Collections.Generic.List[object]'
    $script:WorkerDonePerThread = @{}
    $script:CompletedWorkers = 0
    $script:WorkerThreadCount = 1
    $script:CheckStartedAt = $null
    $script:Cancellation = $null
    $script:CheckQueue = $null
    $script:CheckInputQueue = $null
    $script:CompletionEvent = $null
    $script:UnhandledWorkerError = $null
}

function Update-AvailableNames {
    if ($script:CandidateRevision -eq $script:AvailableNamesRevision) { return }
    $script:AvailableNamesRevision = $script:CandidateRevision
    $script:AvailableNames.Clear()
    $script:PlatformAvailableNames.Clear()
    foreach ($candidate in $script:Candidates) {
        $status = [string]$candidate.Status
        $platform = [string]$candidate.Platform
        if ($status -eq 'Свободен') {
            $script:PlatformAvailableNames.Add((Get-DisplayNick -Platform $platform -Name ([string]$candidate.Name)))
            $script:AvailableNames.Add(('{0}: {1} [{2}]' -f $platform,(Get-DisplayNick -Platform $platform -Name ([string]$candidate.Name)),$status))
        }
    }
}

function Update-Stats {
    $total = $script:Candidates.Count
    $checked = 0; $free = 0; $taken = 0; $invalid = 0; $errors = 0
    foreach ($candidate in $script:Candidates) {
        if ($candidate.Checked) { $checked++ }
        switch ([string]$candidate.Status) {
            'Свободен' { $free++ }
            'Занят' { $taken++ }
            'Недопустимый' { $invalid++ }
            'Ошибка сети' { $errors++ }
        }
    }
    $script:StatTotal.Text = "Всего: $total"
    $script:StatChecked.Text = "Проверено: $checked"
    $script:StatFree.Text = "Свободно/возможно: $free"
    $script:StatTaken.Text = "Занято: $taken"
    $script:StatInvalid.Text = "Недопустимо: $invalid"
    $script:StatErrors.Text = "Ошибки: $errors"
    Update-CheckedNamesButtonText
}

function Update-ResultGrid {
    if (-not $script:Grid) { return }
    $script:Grid.SuspendLayout()
    $restoreAutoSize = $false
    if ($script:Grid.AutoSizeColumnsMode -eq [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill) {
        $script:Grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
        $restoreAutoSize = $true
    }
    $scrollIndex = -1
    try { $scrollIndex = $script:Grid.FirstDisplayedScrollingRowIndex } catch { $scrollIndex = -1 }
    $script:Grid.Rows.Clear()
    $filterStatus = [string]$script:StatusFilterBox.SelectedItem
    $query = ''
    if ($script:SearchBox) { $query = $script:SearchBox.Text.Trim() }
    $items = @($script:Candidates.ToArray())
    switch ([string]$script:SortBox.SelectedItem) {
        'Ник' { $items = @($items | Sort-Object Platform, Name) }
        'Статус' { $items = @($items | Sort-Object Status, Platform, Name) }
        'Категория' { $items = @($items | Sort-Object Category, Platform, Name) }
        'Короткие сначала' { $items = @($items | Sort-Object @{Expression={$_.Name.Length}}, Platform, Name) }
        'Свободные первыми' { $items = @($items | Sort-Object @{Expression={ switch ([string]$_.Status) { 'Свободен' {0}; 'Не подтверждено' {1}; 'Ожидает' {2}; 'Проверяется' {3}; 'Ошибка сети' {4}; 'Занят' {5}; default {6} } }}, Platform, Name) }
        default { }
    }
    foreach ($item in $items) {
        if ($script:OnlyFreeCheck.Checked -and [string]$item.Status -ne 'Свободен') { continue }
        if ($filterStatus -and $filterStatus -ne 'Все статусы' -and [string]$item.Status -ne $filterStatus) { continue }
        $searchText = ([string]$item.Name + ' ' + [string]$item.Platform + ' ' + [string]$item.Category + ' ' + [string]$item.Meaning + ' ' + [string]$item.Reason)
        if ($query -and $searchText.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $row = $script:Grid.Rows.Add((Get-DisplayNick -Platform ([string]$item.Platform) -Name ([string]$item.Name)),[string]$item.Platform,[string]$item.Status,[string]$item.Category,[string]$item.Meaning,[string]$item.Time,[string]$item.Reason)
        $color = $script:StatusColors[[string]$item.Status]
        if ($null -eq $color) { $color = $script:StatusColors['Ошибка сети'] }
        $script:Grid.Rows[$row].Cells['Nick'].Style.ForeColor = $color
        $script:Grid.Rows[$row].Cells['Status'].Style.ForeColor = $color
        $cellTip = Get-StatusTooltip -Item $item
        if ($cellTip) {
            $script:Grid.Rows[$row].Cells['Status'].ToolTipText = $cellTip
            $script:Grid.Rows[$row].Cells['Reason'].ToolTipText = $cellTip
        }
    }
    if ($restoreAutoSize) {
        $script:Grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    }
    if ($scrollIndex -ge 0 -and $script:Grid.Rows.Count -gt 0) {
        $targetIndex = [Math]::Min($scrollIndex, $script:Grid.Rows.Count - 1)
        try { $script:Grid.FirstDisplayedScrollingRowIndex = $targetIndex } catch { }
    }
    $script:Grid.ResumeLayout()
    Update-Stats
    Update-AvailableNames
}

# --- Запуск прогона проверки
function Get-PendingCandidateCount {
    $pendingPlatform = [string]$script:PlatformBox.SelectedItem
    $pendingCount = 0
    foreach ($pendingCandidate in $script:Candidates) {
        if ([string]$pendingCandidate.Platform -eq $pendingPlatform -and [string]$pendingCandidate.Status -eq 'Ожидает') { $pendingCount++ }
    }
    return $pendingCount
}

function Start-Checking {
    param([bool]$RetryErrorsOnly = $false, [bool]$ResumePending = $false)
    if (Test-CheckRunning) { return }
    $eligible = New-Object System.Collections.ArrayList
    $selectedPlatform = [string]$script:PlatformBox.SelectedItem
    foreach ($candidate in $script:Candidates) {
        if ([string]$candidate.Platform -ne $selectedPlatform) { continue }
        if ($ResumePending) {
            if ([string]$candidate.Status -eq 'Ожидает') { [void]$eligible.Add($candidate) }
            continue
        }
        $historyKey = (($selectedPlatform + '|' + [string]$candidate.Name).ToLowerInvariant())
        if ($RetryErrorsOnly) {
            if ($candidate.Status -eq 'Ошибка сети') { [void]$eligible.Add($candidate) }
            continue
        }
        if ($candidate.Status -eq 'Недопустимый' -or $candidate.Status -eq 'Проверяется') { continue }
        if ($script:ExcludeCheckedCheck.Checked -and $script:CheckedNames.ContainsKey($historyKey)) { continue }
        if ($candidate.Status -eq 'Ожидает' -or $candidate.Status -eq 'Ошибка сети' -or -not $script:ExcludeCheckedCheck.Checked) { [void]$eligible.Add($candidate) }
    }
    if ($eligible.Count -eq 0) {
        $msg = if ($ResumePending) { 'Нечего возобновлять: все ники уже проверены или отсеяны.' } elseif ($RetryErrorsOnly) { 'Ошибок для повторной проверки нет.' } else { 'Нет подходящих ников. Сначала сгенерируй варианты или отключи исключение уже проверенных.' }
        [System.Windows.Forms.MessageBox]::Show($msg,'Проверка','OK','Information') | Out-Null
        return
    }
    $validCandidates = New-Object System.Collections.ArrayList
    foreach ($candidate in $eligible) {
        if (-not (Test-UsernameFormat -Username ([string]$candidate.Name) -Platform $selectedPlatform)) {
            $candidate.Status = 'Недопустимый'
            $candidate.Time = (Get-Date).ToString('HH:mm:ss')
            $candidate.Reason = "Неподходящий формат для платформы $selectedPlatform"
            continue
        }
        $candidate.Status = 'Проверяется'
        $candidate.Reason = "Подготовка проверки для $selectedPlatform"
        [void]$validCandidates.Add([pscustomobject]@{Name=[string]$candidate.Name; Platform=$selectedPlatform; Meaning=[string]$candidate.Meaning; Category=[string]$candidate.Category; Structure=[string]$candidate.Structure})
    }
    Touch-Candidates
    if ($validCandidates.Count -eq 0) { Update-ResultGrid; return }
    Update-ResultGrid
    $threadCount = 2
    try { $threadCount = [int]$script:ThreadsBox.Value } catch { $threadCount = 2 }
    if ($threadCount -lt 1) { $threadCount = 1 }
    if ($threadCount -gt 8) { $threadCount = 8 }
    if ($threadCount -gt $validCandidates.Count) { $threadCount = [Math]::Max(1,$validCandidates.Count) }
    $script:WorkerThreadCount = $threadCount
    if ($ResumePending) { Add-Diagnostic 'Возобновление проверки: продолжаю с ников, которые ещё не проверены. Уже проверенные не повторяются.' }
    Add-Diagnostic ("Начата проверка: {0} ников; пауза {1} мс; тайм-аут {2} мс; потоков {3}; платформа {4}." -f $validCandidates.Count,[int]$script:DelayBox.Value,[int]$script:TimeoutBox.Value,$threadCount,$selectedPlatform)
    if ($script:OrderedCheck.Checked) { Add-Diagnostic 'Порядок проверки: по порядку — галочка «Генерация по порядку» включена, строки и очередь идут сверху вниз.' }
    else { Add-Diagnostic 'Порядок проверки: вразнобой — и порядок строк, и очередь проверки перемешаны; статусы появятся в случайных строках.' }
    if ($threadCount -gt 4) {
        Add-Diagnostic ("Потоков {0}: это выше рекомендованных 2–4. При HTTP 429 каждый поток сам увеличит паузу, но общий темп может быть ограничен платформой." -f $threadCount)
    }
    $script:CurrentBatchTotal = $validCandidates.Count
    $script:CurrentBatchDone = 0
    $script:ProgressBar.Value = 0
    $script:ProgressCaption.Text = "Проверка 0 из $($script:CurrentBatchTotal) · потоков $threadCount"
# --- Воркер: проверка платформ
    $workerScript = @'
param($InputQueue, $Queue, $Cancellation, $DelayMs, $TimeoutMs, $Platform, $AppVersion, $WorkerId, $BatchTotal, $ProxyUrl)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace([string]$ProxyUrl)) { $script:WorkerProxy = '' } else {
    $script:WorkerProxy = ([string]$ProxyUrl).Trim()
    if ($script:WorkerProxy -notmatch '^[A-Za-z][A-Za-z0-9+.-]*://') { $script:WorkerProxy = 'http://' + $script:WorkerProxy }
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::DefaultConnectionLimit = 10
if ([string]::IsNullOrWhiteSpace([string]$AppVersion)) { $AppVersion = '2.10.6' }
$TimeoutMs = [Math]::Max(1000,[int]$TimeoutMs)
$platformFloorMs = 400
switch ($Platform) {
    'GitHub' { $platformFloorMs = 1000 }
    'Roblox' { $platformFloorMs = 600 }
}
$minDelayMs = $platformFloorMs
$maxDelayMs = 20000
$currentDelayMs = [Math]::Max($minDelayMs,[int]$DelayMs)
$successStreak = 0
$consecutiveRateLimits = 0
$total = [Math]::Max(1,[int]$BatchTotal)
$done = 0
$consecutiveErrors = 0
$consecutiveProtocolErrors = 0
$stopReason = $null
$timeoutSec = [Math]::Max(1,[int][Math]::Ceiling(([double]$TimeoutMs)/1000.0))
function Get-HttpResult {
    param(
        [string]$Url,
        [int]$Timeout,
        [hashtable]$Headers,
        [string]$Method = 'Get',
        [string]$Body = $null,
        [string]$ContentType = 'application/json; charset=utf-8',
        $WebSession = $null,
        [int]$MaxRedirects = 5
    )
    $currentUrl = $Url
    $currentMethod = $Method
    $currentBody = $Body
    $redirects = 0
    $code = 0
    $content = ''
    $responseHeaders = $null
    $transportError = $null
    $transportKind = $null
    while ($true) {
        $code = 0
        $content = ''
        $responseHeaders = $null
        $transportError = $null
        $transportKind = $null
        $webResponse = $null
        $errorRecord = $null
        try {
            $requestArgs = @{ Uri=$currentUrl; Method=$currentMethod; TimeoutSec=$Timeout; UseBasicParsing=$true; Headers=$Headers; MaximumRedirection=0 }
            if ($null -ne $currentBody -and $currentMethod -ne 'Get' -and $currentMethod -ne 'Head') {
                $requestArgs.Body = $currentBody
                $requestArgs.ContentType = $ContentType
            }
            if ($null -ne $WebSession) { $requestArgs.WebSession = $WebSession }
            if ($script:WorkerProxy) { $requestArgs.Proxy = $script:WorkerProxy }
            $r = Invoke-WebRequest @requestArgs
            $code = [int]$r.StatusCode
            $content = [string]$r.Content
            $responseHeaders = $r.Headers
        } catch {
            $errorRecord = $_
            try { $webResponse = $_.Exception.Response } catch { }
            if ($null -eq $webResponse) {
                $inner = $_.Exception
                while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
                $transportError = [string]$inner.Message
                if ([string]::IsNullOrWhiteSpace($transportError)) { $transportError = [string]$_.Exception.Message }
                $transportKind = 'transport'
                if (($inner -is [System.Net.ProtocolViolationException]) -or ($transportError -match '(?i)content-body|тело содержимого|verb type|тип предиката')) {
                    $transportKind = 'protocol'
                }
                break
            }
            try { $code = [int]$webResponse.StatusCode } catch { }
            try { $responseHeaders = $webResponse.Headers } catch { }
            try {
                $stream = $webResponse.GetResponseStream()
                if ($null -ne $stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    $content = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            } catch { }
            if ([string]::IsNullOrWhiteSpace($content)) {
                try { if ($errorRecord.ErrorDetails -and $errorRecord.ErrorDetails.Message) { $content = [string]$errorRecord.ErrorDetails.Message } } catch { }
            }
        }
        if ($code -ge 300 -and $code -lt 400 -and $redirects -lt $MaxRedirects) {
            $location = $null
            try { $location = [string]$responseHeaders['Location'] } catch { }
            if ([string]::IsNullOrWhiteSpace($location)) {
                try { $location = [string]$webResponse.Headers.Location } catch { }
            }
            if ([string]::IsNullOrWhiteSpace($location)) { break }
            try { $currentUrl = ([uri]::new([uri]$currentUrl, $location)).AbsoluteUri } catch { break }
            if (($code -eq 301 -or $code -eq 302 -or $code -eq 303) -and $currentMethod -ne 'Get' -and $currentMethod -ne 'Head') {
                $currentMethod = 'Get'
                $currentBody = $null
            }
            $redirects++
            continue
        }
        break
    }
    return [pscustomobject]@{
        Code=$code
        Content=$content
        Headers=$responseHeaders
        TransportError=$transportError
        TransportKind=$transportKind
        Redirects=$redirects
        FinalUrl=$currentUrl
    }
}
$browserHeaders = @{
    'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36'
    'Accept'='text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
}
$googleSession = $null
$googleSetupToken = ''
$msSession = $null
$msContext = $null
$githubSession = $null
$githubSignupUrl = 'https://github.com/signup?source=form-home-signup'
if ($Platform -eq 'Google') {
    try {
        $googleSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $googleInitUrls = @('https://accounts.google.com/signup/v2/webcreateaccount?service=mail&flowEntry=SignUp','https://accounts.google.com/signup?service=mail')
        foreach ($googleInitUrl in $googleInitUrls) {
            $googlePage = Get-HttpResult -Url $googleInitUrl -Timeout $timeoutSec -Headers $browserHeaders -WebSession $googleSession
            $googlePageText = [string]$googlePage.Content
            $setupMatch = [regex]::Match($googlePageText, 'data-initial-setup-data="([^"]+)"')
            if (-not $setupMatch.Success) { $setupMatch = [regex]::Match($googlePageText, "data-initial-setup-data='([^']+)'") }
            if ($setupMatch.Success) {
                $setupData = [System.Net.WebUtility]::HtmlDecode($setupMatch.Groups[1].Value)
                $setupParts = $setupData.Split(',')
                if ($setupParts.Length -gt 13) { $googleSetupToken = $setupParts[13].Trim() }
            }
            if (-not $googleSetupToken) {
                $tokenMatch = [regex]::Match($googlePageText, '(AFoagU[A-Za-z0-9_-]{10,})')
                if ($tokenMatch.Success) { $googleSetupToken = $tokenMatch.Groups[1].Value }
            }
            if ($googleSetupToken) { break }
        }
        if (-not $googleSetupToken) { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message='Google: контекст регистрации не извлечён, включена резервная проверка через форму входа.'}) }
    } catch { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=('Google: инициализация проверки не удалась: ' + $_.Exception.Message)}) }
}
if ($Platform -eq 'GitHub') {
    try {
        $githubSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $null = Get-HttpResult -Url $githubSignupUrl -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='text/html,application/xhtml+xml'} -WebSession $githubSession
    } catch { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=('GitHub: инициализация сессии не удалась: ' + $_.Exception.Message)}) }
}
if ($Platform -eq 'Outlook') {
    try {
        $msSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        foreach ($msInitUrl in @('https://signup.live.com/?lic=1','https://signup.live.com/CreateAccount?lic=1&signup=1')) {
            $msPage = Get-HttpResult -Url $msInitUrl -Timeout $timeoutSec -Headers $browserHeaders -WebSession $msSession
            $msPageText = [string]$msPage.Content
        $contextMatch = [regex]::Match($msPageText, '(?s)var\s+t0\s*=\s*(\{.*?\})\s*;')
        if ($contextMatch.Success) { try { $msContext = ConvertFrom-Json -InputObject $contextMatch.Groups[1].Value } catch { } }
        if ($null -eq $msContext -or -not $msContext.apiCanary) {
            $canaryMatch = [regex]::Match($msPageText, '(?i)"?apiCanary"?\s*[:=]\s*"([^"]+)"')
            if ($canaryMatch.Success) { $msContext = [pscustomobject]@{ apiCanary=$canaryMatch.Groups[1].Value; uaid=[string][guid]::NewGuid(); cpgids=$null } }
        }
            if ($null -ne $msContext -and $msContext.apiCanary) { break }
        }
        if ($null -eq $msContext -or -not $msContext.apiCanary) { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message='Microsoft/Outlook: токен формы регистрации не найден — доступность сможет только подтверждать заняность через GetCredentialType.'}) }
    } catch { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=('Microsoft/Outlook: инициализация проверки не удалась: ' + $_.Exception.Message)}) }
}
try {
    while ($true) {
        $item = $null
        if (-not $InputQueue.TryDequeue([ref]$item)) { break }
        if ($null -eq $item) { continue }
        if ($Cancellation.IsCancellationRequested) { break }
        $name = [string]$item.Name
        $status = 'Ошибка сети'
        $reason = 'Не удалось определить статус'
        $errorDetail = $null
        $httpStatus = 0
        $retryAfter = 0
        $r = $null
        try {
            switch ($Platform) {
# --- Roblox Api
                'Roblox' {
                    $payload = @{username=$name; birthday='2000-01-01T00:00:00.000Z'; context='Signup'} | ConvertTo-Json -Compress
                    $robloxHeaders = @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'; 'Origin'='https://www.roblox.com'; 'Referer'='https://www.roblox.com/'}
                    $csrfAttempts = 0
                    while ($true) {
                        $r = Get-HttpResult -Url 'https://auth.roblox.com/v1/usernames/validate' -Timeout $timeoutSec -Headers $robloxHeaders -Method Post -Body $payload -ContentType 'application/json; charset=UTF-8'
                        $httpStatus = [int]$r.Code
                        if ($httpStatus -eq 403 -and [string]$r.TransportKind -ne 'protocol' -and $csrfAttempts -lt 2) {
                            $csrfToken = $null
                            try { $csrfToken = [string]$r.Headers['X-CSRF-Token'] } catch { }
                            if (-not [string]::IsNullOrWhiteSpace($csrfToken)) {
                                $robloxHeaders['X-CSRF-Token'] = $csrfToken
                                $csrfAttempts++
                                continue
                            }
                        }
                        break
                    }
                    if ($httpStatus -eq 200) {
                        $response = ConvertFrom-Json -InputObject $r.Content -ErrorAction Stop
                        if ($null -eq $response -or $null -eq $response.PSObject.Properties['code']) { throw 'Roblox вернул пустой или непонятный ответ.' }
                        $code = [int]$response.code
                        if ($code -eq 0) { $status = 'Свободен'; $reason = 'Регистрационный валидатор Roblox сообщил, что имя доступно'; $consecutiveErrors = 0 }
                        elseif ($code -eq 1) { $status = 'Занят'; $reason = 'Roblox сообщил, что имя уже используется'; $consecutiveErrors = 0 }
                        elseif ($code -eq 2) { $status = 'Недопустимый'; $reason = 'Roblox отклонил имя фильтром содержания'; $consecutiveErrors = 0 }
                        elseif ($code -eq 3 -or $code -eq 10) { $status = 'Недопустимый'; $reason = 'Roblox отклонил формат имени'; $consecutiveErrors = 0 }
                        else { $status = 'Не подтверждено'; $reason = 'Roblox вернул неизвестный код валидатора: ' + $code; $consecutiveErrors = 0 }
                    } elseif ($httpStatus -eq 403) {
                        $status = 'Не подтверждено'; $reason = 'Roblox отклонил запрос (403): антибот-защита или CSRF-токен не принят'; $consecutiveErrors = 0
                    } elseif ($httpStatus -ge 400) {
                        $status = 'Не подтверждено'; $reason = "Roblox ответил HTTP $httpStatus без распознаваемого результата валидации"; $consecutiveErrors = 0
                    }
                }
# --- Google Api
                'Google' {
                    # --- Google закрыл анонимные опросы (400 на «холодные» запросы), поэтому первым идёт signin-lookup с прогретой сессией
                    $email = $name + '@gmail.com'
                    $googleCode = ''
                    $googleHttpNote = ''
                    if ($null -ne $googleSession -and $googleSession.Cookies.Count -lt 1) {
                        $null = Get-HttpResult -Url 'https://accounts.google.com/signin/v2/identifier?service=mail&hl=en' -Timeout $timeoutSec -Headers $browserHeaders -WebSession $googleSession
                    }
                    if ($null -ne $googleSession) {
                        $lookupCells = @()
                        for ($nullIndex = 0; $nullIndex -lt 4; $nullIndex++) { $lookupCells += 'null' }
                        $lookupCells += ('"' + $email + '"')
                        for ($nullIndex = 0; $nullIndex -lt 42; $nullIndex++) { $lookupCells += 'null' }
                        $lookupBody = 'f.req=[[' + ($lookupCells -join ',') + ']]'
                        try {
                            $r = Get-HttpResult -Url 'https://accounts.google.com/_/signin/sl/lookup?hl=en' -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='*/*'; 'X-Same-Domain'='1'; 'Origin'='https://accounts.google.com'; 'Referer'='https://accounts.google.com/signin/v2/identifier?service=mail'} -Method Post -Body $lookupBody -ContentType 'application/x-www-form-urlencoded;charset=UTF-8' -WebSession $googleSession
                            $httpStatus = [int]$r.Code
                            if ($httpStatus -eq 200) {
                                $lookupText = [string]$r.Content
                                if ($lookupText -match '(?s)[,\[]\s*105\s*[,.\]]') { $googleCode = '1' }
                                elseif ($lookupText.IndexOf($email, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $lookupText -match '(?i)"gf"|"pr"') { $googleCode = '2' }
                            }
                        } catch { }
                    }
                    $googleCells = @()
                    for ($nullIndex = 0; $nullIndex -lt 8; $nullIndex++) { $googleCells += 'null' }
                    $googleCells += ('"' + $email + '"')
                    $googleCells += 'null'
                    $googleCells += '0'
                    for ($nullIndex = 0; $nullIndex -lt 6; $nullIndex++) { $googleCells += 'null' }
                    $googleCells += '[1]'
                    $googlePlainBody = 'f.req=[[' + ($googleCells -join ',') + ']]'
                    $googleVariants = @()
                    $googleVariants += @{Url='https://accounts.google.com/_/signup/webusernameavailability'; Body=$googlePlainBody; NeedToken=$false}
                    $googleTokenBody = ''
                    if ($googleSetupToken) { $googleTokenBody = 'f.req=[' + '"' + $googleSetupToken.Replace('"','') + '","","","' + $email + '"]' }
                    $googleVariants += @{Url='https://accounts.google.com/_/signup/usernameavailability?hl=en'; Body=$googleTokenBody; NeedToken=$true}
                    if (-not $googleCode) {
                        $googleHeaders = @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='*/*'; 'Accept-Language'='en-US,en;q=0.9'; 'Google-Accounts-Xsrf'='1'; 'Origin'='https://accounts.google.com'; 'Referer'='https://accounts.google.com/signup/v2/webcreateaccount?service=mail&flowEntry=SignUp'}
                        foreach ($googleVariant in $googleVariants) {
                            if ($googleVariant.NeedToken -and (-not $googleSetupToken -or $null -eq $googleSession -or [string]::IsNullOrWhiteSpace([string]$googleVariant.Body))) { continue }
                            $googleBody = [string]$googleVariant.Body
                            $httpStatus = 0
                            try {
                                $r = Get-HttpResult -Url ([string]$googleVariant.Url) -Timeout $timeoutSec -Headers $googleHeaders -Method Post -Body $googleBody -ContentType 'application/x-www-form-urlencoded; charset=UTF-8' -WebSession $googleSession
                                $httpStatus = [int]$r.Code
                                if ($httpStatus -eq 400) { $googleHttpNote = 'валидатор регистрации ответил 400 (Google закрыл его для автоматических запросов)' }
                                if ($httpStatus -eq 200) {
                                    $bodyText = ([string]$r.Content).Trim()
                                    if ($bodyText -match '\[\[\s*null\s*,\s*\[\s*([12])\s*(?:,|\])') { $googleCode = $Matches[1] }
                                    elseif ($bodyText -match '(?is)\[\s*null\s*,\s*([12])\s*(?:,|\])') { $googleCode = $Matches[1] }
                                    elseif ($bodyText -match '(?i)"(?:usernameAvailable|available)"\s*:\s*(true|false)') { if ($Matches[1] -ieq 'true') { $googleCode = '1' } else { $googleCode = '2' } }
                                    elseif ($bodyText -match '(?i)IDENTIFIER_EXISTS|username.{0,80}(?:taken|not available)|email.{0,80}already') { $googleCode = '2' }
                                }
                            } catch { }
                            if ($googleCode) { break }
                            if ($httpStatus -eq 429 -or $httpStatus -ge 500) { break }
                        }
                    }
                    if ($googleCode -eq '1') { $status='Свободен'; $reason='Google: страница входа не нашла аккаунт с этим адресом'; $consecutiveErrors=0 }
                    elseif ($googleCode -eq '2') { $status='Занят'; $reason='Google: адрес Gmail используется'; $consecutiveErrors=0 }
                    else { $status='Не подтверждено'; if ($googleHttpNote) { $reason='Google: ' + $googleHttpNote + '; lookup тоже молчит — проверьте позже или через «Прокси»' } else { $reason='Google не вернул распознаваемого ответа — точную доступность покажет только форма регистрации' }; $consecutiveErrors=0 }
                }
# --- Mail.ru Api
                'Mail.ru' {
                    $email = $name + '@mail.ru'
                    $url = 'https://account.mail.ru/api/v1/user/exists?email=' + [uri]::EscapeDataString($email)
                    $r = Get-HttpResult -Url $url -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'; 'Referer'='https://account.mail.ru/signup'}
                    $httpStatus = [int]$r.Code
                    if ($httpStatus -eq 200) {
                        $response = ConvertFrom-Json -InputObject $r.Content -ErrorAction Stop
                        $existsProperty = $null
                        if ($null -ne $response.body) { $existsProperty = $response.body.PSObject.Properties['exists'] }
                        if ($null -eq $existsProperty) { $existsProperty = $response.PSObject.Properties['exists'] }
                        if ($null -ne $existsProperty) {
                            if ([bool]$existsProperty.Value) { $status='Занят'; $reason='Mail.ru подтвердил существование адреса'; $consecutiveErrors=0 }
                            else { $status='Свободен'; $reason='Mail.ru сообщил, что адрес не занят'; $consecutiveErrors=0 }
                        } else { $status='Не подтверждено'; $reason='Mail.ru вернул неожиданный формат ответа'; $consecutiveErrors=0 }
                    }
                }
# --- VK Api
                'VK' {
                    $url = 'https://api.vk.com/method/utils.resolveScreenName?screen_name=' + [uri]::EscapeDataString($name) + '&v=5.199'
                    $r = Get-HttpResult -Url $url -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'}
                    $httpStatus = [int]$r.Code
                    if ($httpStatus -eq 200) {
                        $response = ConvertFrom-Json -InputObject $r.Content -ErrorAction Stop
                        if ($null -ne $response.response -and $response.response.object_id) { $status='Занят'; $reason='VK разрешил screen name в существующий профиль'; $consecutiveErrors=0 }
                        elseif ($null -ne $response.PSObject.Properties['response'] -and $null -eq $response.response) { $status='Свободен'; $reason='VK не разрешил screen name в публичный профиль — имя не занято (зарезервированные исключения покажет регистрация)'; $consecutiveErrors=0 }
                        else {
                            $profileUrl = 'https://vk.com/' + [uri]::EscapeDataString($name)
                            $pr = Get-HttpResult -Url $profileUrl -Timeout $timeoutSec -Headers $browserHeaders
                            $httpStatus = [int]$pr.Code
                            if ($pr.Content -match ('(?is)id="profile_short"|id="profile_full"|"screen_name"\s*:\s*"' + [regex]::Escape($name) + '"')) { $status='Занят'; $reason='Публичный профиль VK найден'; $consecutiveErrors=0 }
                            elseif ([int]$pr.Code -eq 404 -or $pr.Content -match '(?i)страница удалена|пользователь не найден|page not found|profile is unavailable') { $status='Свободен'; $reason='VK не нашёл публичный профиль с таким screen name'; $consecutiveErrors=0 }
                            else { $status='Не подтверждено'; $reason='VK не раскрыл однозначный статус screen name'; $consecutiveErrors=0 }
                        }
                    }
                }
                'Discord' {
                    $normalizedDiscordName = $name.ToLowerInvariant()
                    $body = ConvertTo-Json -InputObject @{username=$normalizedDiscordName} -Compress
                    $r = Get-HttpResult -Url 'https://discord.com/api/v9/unique-username/username-attempt-unauthed' -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'; 'Content-Type'='application/json'; 'Origin'='https://discord.com'; 'Referer'='https://discord.com/register'} -Method Post -Body $body -ContentType 'application/json' 
                    $httpStatus = [int]$r.Code
                    if ($httpStatus -eq 200) {
                        $response = ConvertFrom-Json -InputObject $r.Content -ErrorAction Stop
                        $takenProperty = $response.PSObject.Properties['taken']
                        if ($null -eq $takenProperty) { $takenProperty = $response.PSObject.Properties['username_taken'] }
                        if ($null -ne $takenProperty) {
                            if ([bool]$takenProperty.Value) { $status='Занят'; $reason='Discord сообщил, что имя занято'; $consecutiveErrors=0 }
                            else { $status='Свободен'; $reason='Discord вернул taken=false для username'; $consecutiveErrors=0 }
                        } elseif ($response.PSObject.Properties['message'] -and ([string]$response.message -match '(?i)already taken|username is taken')) {
                            $status='Занят'; $reason='Discord сообщил, что имя занято'; $consecutiveErrors=0
                        } else { $status='Не подтверждено'; $reason='Discord не вернул признак занятости имени'; $consecutiveErrors=0 }
                    } elseif ($httpStatus -eq 400 -or $httpStatus -eq 422) { $status='Недопустимый'; $reason='Discord отклонил формат имени'; $consecutiveErrors=0 }
                }
# --- Outlook Api
                'Outlook' {
                    $signInName = $name + '@outlook.com'
                    $credentialBody = ConvertTo-Json -InputObject @{username=$signInName; isOtherIdEntry=$false} -Compress
                    $gctHeaders = @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'; 'Origin'='https://login.microsoftonline.com'; 'Referer'='https://login.microsoftonline.com/common/oauth2/v2.0/authorize'}
                    try {
                        $r = Get-HttpResult -Url 'https://login.microsoftonline.com/common/GetCredentialType' -Timeout $timeoutSec -Headers $gctHeaders -Method Post -Body $credentialBody -ContentType 'application/json; charset=UTF-8'
                        $httpStatus = [int]$r.Code
                        $gctText = [string]$r.Content
                        $existsMatch = [regex]::Match($gctText, '(?i)"IfExistsResult"\s*:\s*(-?[0-9]+)')
                        $errorCodeMatch = [regex]::Match($gctText, '"code"\s*:\s*([0-9]+)')
                        $errorThrottle = $errorCodeMatch.Success -and [int]$errorCodeMatch.Groups[1].Value -in @(1000,1065)
                        if ($httpStatus -eq 200 -and $existsMatch.Success) {
                            $credentialCode = [int]$existsMatch.Groups[1].Value
                            if ($credentialCode -eq 0) { $status='Занят'; $reason='Outlook: IfExistsResult=0 — Microsoft сообщает, что пользователь с таким адресом существует'; $consecutiveErrors=0 }
                            elseif ($credentialCode -eq 1) { $status='Не подтверждено'; $reason='Outlook: аккаунта для входа нет (IfExistsResult=1), но форма регистрации может отказать (резерв/ограничения). Ответа signup.live.com не получил — не считаю имя свободным'; $consecutiveErrors=0 }
                            elseif ($credentialCode -eq 4) { $status='Не подтверждено'; $reason='Outlook: IfExistsResult=4 — федеративный домен, доступность личного адреса не подтверждена'; $consecutiveErrors=0 }
                            elseif ($credentialCode -eq 5 -or $credentialCode -eq 6) { $status='Не подтверждено'; $reason='Outlook: IfExistsResult=' + $credentialCode + ' — домен не найден или ошибка домена'; $consecutiveErrors=0 }
                            else { $status='Не подтверждено'; $reason='Outlook: неизвестный IfExistsResult=' + $credentialCode; $consecutiveErrors=0 }
                        } elseif ($errorThrottle) {
                            $status='Не подтверждено'; $reason='Outlook: Microsoft ограничил частоту проверок (код ' + $errorCodeMatch.Groups[1].Value + '); увеличьте паузу'; $consecutiveErrors=0
                        } elseif ($httpStatus -eq 200) {
                            $status='Не подтверждено'; $reason='Outlook: GetCredentialType ответил без поля IfExistsResult; включаю резервную проверку регистрации'; $consecutiveErrors=0
                        }
                    } catch { }
                    if ($status -notin @('Занят','Свободен')) {
                        $msNote = ''
                        for ($msAttempt = 1; $msAttempt -le 2; $msAttempt++) {
                            if ($null -eq $msSession) { $msSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession }
                            $msCanaryNow = $null
                            foreach ($msInitUrl in @('https://signup.live.com/CreateAccount?lic=1&uiflvr=1103&scid=200055&signup=1','https://signup.live.com/?lic=1')) {
                                $msPageFresh = Get-HttpResult -Url $msInitUrl -Timeout $timeoutSec -Headers $browserHeaders -WebSession $msSession
                                $msPageText = [string]$msPageFresh.Content
                                $canaryMatch = [regex]::Match($msPageText, '(?i)"apiCanary"\s*[:=]\s*"([^"]+)"')
                                if ($canaryMatch.Success) { $msCanaryNow = $canaryMatch.Groups[1].Value; break }
                                $bootMatch = [regex]::Match($msPageText, '(?s)var\s+t0\s*=\s*(\{.*?\})\s*;')
                                if ($bootMatch.Success) {
                                    try { $bootJson = ConvertFrom-Json -InputObject $bootMatch.Groups[1].Value; if ($null -ne $bootJson -and $null -ne $bootJson.apiCanary) { $msCanaryNow = [string]$bootJson.apiCanary; break } } catch { }
                                }
                            }
                            if ([string]::IsNullOrWhiteSpace($msCanaryNow) -and $null -ne $msContext -and $msContext.apiCanary) { $msCanaryNow = [string]$msContext.apiCanary }
                            if ([string]::IsNullOrWhiteSpace($msCanaryNow)) { $msNote = 'страница регистрации не отдала canary'; break }
                            $msUaid = [string][guid]::NewGuid()
                            $hpgidValue = 1001
                            try { if ($null -ne $msContext -and $null -ne $msContext.cpgids -and $null -ne $msContext.cpgids.Signup_MemberNamePage_Client) { $hpgidValue = [int]$msContext.cpgids.Signup_MemberNamePage_Client } } catch { }
                            $payload = @{signInName=$signInName; includePhone=$false; countryCode='RU'; uaid=$msUaid; uiflvr=1103; scid=1001; hpgid=$hpgidValue} | ConvertTo-Json -Compress
                            $msHeaders = @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'; 'canary'=$msCanaryNow; 'Origin'='https://signup.live.com'; 'Referer'=('https://signup.live.com/CreateAccount?lic=1&uiflvr=1103&scid=200055&signup=1&uaid=' + $msUaid)}
                            try {
                                $r2 = Get-HttpResult -Url 'https://signup.live.com/API/CheckAvailableSigninNames' -Timeout $timeoutSec -Headers $msHeaders -Method Post -Body $payload -ContentType 'application/json; charset=UTF-8' -WebSession $msSession
                                $status2 = [int]$r2.Code
                                $responseText = [string]$r2.Content
                                $availableMatch = [regex]::Match($responseText, '(?i)"isAvailable"\s*:\s*(true|false)')
                                if ($status2 -eq 200 -and $availableMatch.Success) {
                                    if ($availableMatch.Groups[1].Value -ieq 'true') { $status='Свободен'; $reason='Outlook: форма регистрации подтвердила доступность адреса ' + $signInName; $consecutiveErrors=0 }
                                    else { $status='Занят'; $reason='Outlook: форма регистрации отклонила адрес ' + $signInName + ' как недоступный'; $consecutiveErrors=0 }
                                    break
                                }
                                if ($responseText -match '(?i)"type"\s*:\s*"MemberNameUnavailable"') { $status='Занят'; $reason='Outlook: форма регистрации сообщает, что адрес занят или недоступен'; $consecutiveErrors=0; break }
                                if ($status2 -eq 400 -or $responseText -match '(?i)"errorDefinitions"') {
                                    $msErrorText = [regex]::Match($responseText, '(?i)"message"\s*:\s*"([^"]+)"').Groups[1].Value
                                    if ($msErrorText -match '(?i)alread|taken|not available|unavailable|недоступен') { $status='Занят'; $reason='Outlook: форма регистрации сообщает, что адрес занят или недоступен'; $consecutiveErrors=0; break }
                                    if ($msErrorText -match '(?i)forbidden|reserved|not allowed|invalid') { $status='Недопустимый'; $reason='Outlook: форма регистрации отклонила имя как недопустимое или зарезервированное'; $consecutiveErrors=0; break }
                                    if ($msErrorText) { $msNote = 'форма регистрации: ' + $msErrorText.Substring(0,[Math]::Min(120,$msErrorText.Length)) }
                                }
                                $existsMatch2 = [regex]::Match($responseText, '(?i)"IfExistsResult"\s*:\s*(-?[0-9]+)')
                                if ($existsMatch2.Success) {
                                    $existsCode = [int]$existsMatch2.Groups[1].Value
                                    if ($existsCode -eq 0) { $status='Занят'; $reason='Outlook: форма регистрации вернула IfExistsResult=0 — аккаунт существует'; $consecutiveErrors=0; break }
                                    $msNote = 'форма регистрации вернула IfExistsResult=' + $existsCode
                                }
                                if ($status2 -eq 401 -or $status2 -eq 403 -or $responseText -match '(?i)canary|invalid_request') { $msNote = 'canary устарел или запрос отклонён (HTTP ' + $status2 + '), обновляю страницу'; if ($msAttempt -eq 2) { break } else { continue } }
                                if (-not $msNote) {
                                    $msPreview = ($responseText -replace '\s+',' ').Trim()
                                    if ($msPreview.Length -gt 90) { $msPreview = $msPreview.Substring(0,90) }
                                    if ($msPreview.StartsWith('<')) { $msNote = 'форма регистрации отдала HTML вместо JSON (включилась защита Microsoft) — повтори позже или задай «Прокси»' }
                                    else { $msNote = 'ответ формы регистрации непонятен (HTTP ' + $status2 + '): ' + $msPreview }
                                }
                            } catch { $msNote = 'запрос к форме регистрации не прошёл: ' + $_.Exception.Message }
                        }
                        if ($status -notin @('Занят','Свободен','Недопустимый')) {
                            if ($msNote) { $reason = 'Outlook: ' + $msNote + ' — точный ответ даёт только форма регистрации, статус не подтверждён' }
                            $consecutiveErrors=0
                        }
                    }
                }
# --- GitHub Api
                'GitHub' {
                    if ($null -eq $githubSession) {
                        $githubSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                        $null = Get-HttpResult -Url $githubSignupUrl -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='text/html,application/xhtml+xml'} -WebSession $githubSession
                    }
                    $checkUrl = 'https://github.com/signup_check/username?value=' + [uri]::EscapeDataString($name)
                    $r = Get-HttpResult -Url $checkUrl -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='*/*'; 'X-Requested-With'='XMLHttpRequest'; 'Referer'=$githubSignupUrl} -WebSession $githubSession
                    $httpStatus = [int]$r.Code
                    $githubBody = ([string]$r.Content).Trim()
                    if ($httpStatus -eq 200 -and ($githubBody -eq '' -or $githubBody -match '(?i)^(available|true|username is available)\.?$')) {
                        $status='Свободен'; $reason='Регистрационный endpoint GitHub не сообщил о занятости имени'; $consecutiveErrors=0
                    } elseif (($httpStatus -eq 403 -or $httpStatus -eq 422) -and $githubBody -match '(?i)already taken|reserved word|username is taken|not available|unavailable') {
                        if ($githubBody -match '(?i)reserved word|invalid') { $status='Недопустимый'; $reason='GitHub отклонил имя как зарезервированное или недопустимое' }
                        else { $status='Занят'; $reason='Регистрационный endpoint GitHub сообщил, что имя занято' }
                        $consecutiveErrors=0
                    } else {
                        $url = 'https://api.github.com/users/' + [uri]::EscapeDataString($name)
                        $r = Get-HttpResult -Url $url -Timeout $timeoutSec -Headers @{'User-Agent'=('UniversalUsernameFinder/{0}' -f $AppVersion); 'Accept'='application/vnd.github+json'; 'X-GitHub-Api-Version'='2026-03-10'}
                        $httpStatus = [int]$r.Code
                        $rateRemaining = -1
                        try {
                            if ($null -ne $r.Headers) {
                                $rawRemaining = [string]$r.Headers['X-RateLimit-Remaining']
                                if (-not [string]::IsNullOrWhiteSpace($rawRemaining)) { $rateRemaining = [int]$rawRemaining }
                            }
                        } catch { }
                        if ($httpStatus -eq 200) { $status='Занят'; $reason='Публичный профиль GitHub найден'; $consecutiveErrors=0 }
                        elseif ($httpStatus -eq 404) { $status='Свободен'; $reason='GitHub: регистрационный endpoint не нашёл профиль с таким именем'; $consecutiveErrors=0 }
                        elseif ($httpStatus -eq 403) { $status='Ошибка сети'; $reason='GitHub ограничил анонимный API (403/возможный лимит)'; $stopReason='GitHub ограничил запросы; проверка остановлена' }
                        if ($rateRemaining -eq 0 -and -not $stopReason) {
                            $stopReason = 'Исчерпан часовой лимит анонимного API GitHub (60 запросов); проверка остановлена. Повтори позже или используй только регистрационный endpoint.'
                        }
                    }
                }
# --- YouTube Api
                'YouTube' {
                    $url = 'https://www.youtube.com/@' + [uri]::EscapeDataString($name)
                    $ytHeaders = @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'=$browserHeaders['Accept']; 'Accept-Language'='en-US,en;q=0.9'; 'Cookie'='CONSENT=YES+cb; SOCS=CAI; GPS=1'}
                    $r = Get-HttpResult -Url $url -Timeout $timeoutSec -Headers $ytHeaders
                    $httpStatus = [int]$r.Code
                    $content = [string]$r.Content
                    $escapedHandle = [regex]::Escape($name)
                    $matchingCanonical = $content -match ('(?is)"canonicalBaseUrl"\s*:\s*"/@' + $escapedHandle + '"') -or $content -match ('(?is)<link[^>]+rel="canonical"[^>]+href="https?://www\.youtube\.com/@' + $escapedHandle + '"') -or $content -match ('(?is)property="og:url"[^>]+content="https?://www\.youtube\.com/@' + $escapedHandle + '"') -or $content -match ('(?is)"canonicalChannelUrl"\s*:\s*"https?://www\.youtube\.com/@' + $escapedHandle + '"')
                    $channelMetadata = $content -match '(?is)"channelMetadataRenderer"\s*:\s*\{'
                    # --- Категории как в YTKits: «Канал найден» — занято; «Не найден» — свободно (подтверждается в Studio); иное — «Неизвестно»
                    $ytNotFound = ($httpStatus -eq 404) -or ($content -match '(?i)channelNotFound|This page isn.t available|channel does not exist|"errorScreen"|Страница недоступна')
                    if ($httpStatus -eq 200 -and $matchingCanonical -and $channelMetadata) { $status='Занят'; $reason='YouTube: канал найден, canonical handle совпадает с запрошенным'; $consecutiveErrors=0 }
                    elseif ($ytNotFound -and -not $channelMetadata) { $status='Свободен'; $reason='YouTube: канал с этим handle не найден — подтверди в YouTube Studio (резерв и ограничения видны только там)'; $consecutiveErrors=0 }
                    else { $status='Не подтверждено'; $reason='YouTube: результат неизвестен — страница не подтвердила ни канал с этим handle, ни его отсутствие; повтори позже или проверь на youtube.com/handle'; $consecutiveErrors=0 }
                }
# --- Telegram Api
                'Telegram' {
                    # --- Публичный метод: t.me и зеркала telegram.dog/telegram.me — первый однозначный ответ выигрывает, как в веб-версии
                    # --- Занятый ник отдаёт заголовок профиля (tgme_page_title) или счётчики канала/группы (подписчики, участники).
                    # --- Свободный ник отдаёт страницу-заглушку «If you have Telegram, you can contact @ник» без заголовка профиля.
                    # --- og:title «Telegram: Contact @ник» есть на обеих страницах, поэтому по нему статус не определяем.
                    $tgResolved = $false
                    $tgNoProfileSeen = $false
                    $tgLastNote = ''
                    foreach ($tgBase in @('https://t.me/','https://telegram.dog/','https://telegram.me/')) {
                        if ($Cancellation.IsCancellationRequested) { break }
                        $tgName = 't.me'
                        if ($tgBase -ne 'https://t.me/') { $tgName = $tgBase.Substring(8).TrimEnd('/') }
                        $tgTimeoutSec = [Math]::Min($timeoutSec,12)
                        $r = Get-HttpResult -Url ($tgBase + [uri]::EscapeDataString($name)) -Timeout $tgTimeoutSec -Headers $browserHeaders
                        $httpStatus = [int]$r.Code
                        $content = [string]$r.Content
                        $blockedPage = $content -match '(?i)доступ к странице ограничен|access is restricted|reestr|roskomnadzor'
                        $profileTitle = $content -match '(?is)class="tgme_page_title"[^>]*>\s*(<span[^>]*>\s*)?[^<\s]'
                        $channelCounters = $content -match '(?i)class="tgme_page_extra"[^<]*(subscribers|members|monthly listeners|online)'
                        $reservedPage = $content -match '(?i)username has been reserved|reserved for payment|this username is reserved|has been frozen'
                        $freePage = $content -match '(?i)if you have (a )?telegram( account|,)|reserve this username|doesn.t seem to exist|username not found|tgme_page_error'
                        if ($blockedPage) { $tgLastNote = $tgName + ' блокируется провайдером — задай «Прокси» над таблицей или включи VPN'; continue }
                        if ($httpStatus -eq 404) { $status='Свободен'; $reason='Telegram: ' + $tgName + ' вернул 404 — страница @' + $name + ' никем не занята'; $consecutiveErrors=0; $tgResolved=$true; break }
                        if ($httpStatus -eq 200 -and $reservedPage) { $status='Занят'; $reason='Telegram: тег @' + $name + ' зарезервирован платформой (резерв или платный ник) — регистрация закрыта'; $consecutiveErrors=0; $tgResolved=$true; break }
                        if ($httpStatus -eq 200 -and ($profileTitle -or $channelCounters)) { $status='Занят'; $reason='Telegram: ' + $tgName + ' отдаёт публичную страницу профиля или канала @' + $name; $consecutiveErrors=0; $tgResolved=$true; break }
                        if ($httpStatus -eq 200 -and $freePage) { $status='Свободен'; $reason='Telegram: страница @' + $name + ' на ' + $tgName + ' без профиля и предлагает открыть чат — тег свободен'; $consecutiveErrors=0; $tgResolved=$true; break }
                        if ($httpStatus -eq 200) { $tgNoProfileSeen = $true; $tgLastNote = $tgName + ' ответил без распознаваемых маркеров профиля'; continue }
                        if ($httpStatus -eq 0) { $tgLastNote = $tgName + ' недоступен: соединение не установлено (сетевая блокировка) — поставь «Прокси» над таблицей или включи VPN' } else { $tgLastNote = $tgName + ' вернул неожиданный HTTP ' + $httpStatus }
                    }
                    # --- Страница открылась, но профиля на ней нет: тег свободен
                    if (-not $tgResolved -and $tgNoProfileSeen) { $status='Свободен'; $reason='Telegram: страница @' + $name + ' открылась без профиля и без признаков занятости — тег свободен'; $consecutiveErrors=0; $tgResolved=$true }
                    if (-not $tgResolved) { $status='Не подтверждено'; $reason='Telegram: ' + $tgLastNote + '; попробуй повторить или задать прокси'; $consecutiveErrors=0 }
                }
# --- Steam Api
                'Steam' {
                    $url = 'https://steamcommunity.com/id/' + $name
                    $r = Get-HttpResult -Url $url -Timeout $timeoutSec -Headers $browserHeaders
                    $httpStatus = [int]$r.Code
                    $content = [string]$r.Content
                    $profileMarker = $content -match '(?is)class="profile_header"|id="personaName"|profile_rightcolumn|profileHeader'
                    $errorMarker = ($httpStatus -eq 404) -or ($content -match '(?is)The specified profile could not be found|Steam Community :: Error')
                    if ($httpStatus -eq 200 -and $profileMarker -and -not $errorMarker) {
                        $titleMatch = [regex]::Match($content, '(?is)<title>\s*Steam Community :: (.*?)\s*</title>')
                        $profileName = ''
                        if ($titleMatch.Success) { $profileName = [System.Net.WebUtility]::HtmlDecode($titleMatch.Groups[1].Value).Trim() }
                        $status='Занят'
                        if ($profileName) { $reason = 'Профиль сообщества занят: ' + $profileName } else { $reason = 'Профиль сообщества занят' }
                        $consecutiveErrors=0
                    } elseif ($errorMarker) {
                        $status='Свободен'; $reason='Адрес steamcommunity.com/id не занят — профиль не найден'; $consecutiveErrors=0
                    } else { $status='Не подтверждено'; $reason='Steam не раскрыл статус публичного адреса'; $consecutiveErrors=0 }
                }
                default {
                    $status='Не подтверждено'
                    $reason='Платформа не вернула проверяемый статус доступности через доступный интерфейс'
                    $consecutiveErrors=0
                }
            }
            if ($null -ne $r -and [string]$r.TransportKind -eq 'protocol') {
                $status = 'Не подтверждено'
                $reason = ('{0} отклонил запрос на уровне протокола: {1}' -f $Platform, [string]$r.TransportError)
                $errorDetail = [string]$r.TransportError
                $consecutiveProtocolErrors++
                $consecutiveErrors = 0
            } else {
                $consecutiveProtocolErrors = 0
            }
            if ($httpStatus -eq 429) {
                $consecutiveRateLimits++
                $successStreak = 0
                $retryAfter = 0
                try { if ($null -ne $r -and $r.Headers['Retry-After']) { $retryAfter = [int]$r.Headers['Retry-After'] } } catch { }
                if ($retryAfter -lt 0) { $retryAfter = 0 }
                if ($retryAfter -gt 120) { $retryAfter = 120 }
                $currentDelayMs = [Math]::Min($maxDelayMs,[Math]::Max($currentDelayMs * 2, $retryAfter * 1000))
                $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=("HTTP 429 для {0} ({1}). Пауза увеличена до {2} мс; ограничение подряд: {3} из 3." -f $name,$Platform,$currentDelayMs,$consecutiveRateLimits)})
                if ($retryAfter -gt 0) {
                    $waitUntil = [DateTime]::UtcNow.AddSeconds($retryAfter)
                    while ([DateTime]::UtcNow -lt $waitUntil -and -not $Cancellation.IsCancellationRequested) { Start-Sleep -Milliseconds 100 }
                }
                $status = 'Ошибка сети'; $reason = "HTTP 429 — ограничение частоты запросов $Platform; пауза увеличена"
                if ($consecutiveRateLimits -ge 3) { $stopReason = "$Platform ограничил частоту запросов три раза подряд (HTTP 429); прогон остановлен" }
            } elseif ($httpStatus -eq 403 -and $Platform -eq 'GitHub') {
                $status = 'Ошибка сети'; $reason = 'GitHub HTTP 403: возможен лимит анонимного API'; $stopReason = 'GitHub ограничил запросы; проверка остановлена'
            } elseif ($httpStatus -ge 500) {
                $status = 'Ошибка сети'; $reason = "HTTP $httpStatus от $Platform"; $consecutiveErrors++
            } elseif ($httpStatus -eq 0) {
                if ($status -ne 'Не подтверждено') {
                    $status = 'Ошибка сети'
                    $transportDetail = ''
                    if ($null -ne $r) { $transportDetail = [string]$r.TransportError }
                    if ([string]::IsNullOrWhiteSpace($transportDetail)) { $transportDetail = 'Ответ без HTTP-статуса' }
                    $reason = "Сетевая ошибка: $transportDetail"
                    if ($Platform -eq 'Telegram' -or $Platform -eq 'YouTube') { $reason += ' — сайты t.me и YouTube могут быть недоступны из региона: включите VPN или заполните поле «Прокси»' }
                    $errorDetail = $transportDetail
                    $consecutiveErrors++
                }
            } elseif ($httpStatus -ge 400 -and $status -eq 'Ошибка сети') {
                $status = 'Ошибка сети'; $reason = "HTTP $httpStatus от $Platform"; $consecutiveErrors++
            } elseif ($httpStatus -ge 400 -and $status -eq 'Не подтверждено') {
                $reason = "Платформа ответила HTTP $httpStatus; доступность не подтверждена"
            }
        } catch {
            $errorDetail = $_.Exception.Message
            $status = 'Ошибка сети'
            $reason = 'Ошибка сети или непредвиденный ответ API'
            $consecutiveErrors++
        }
        if ($Cancellation.IsCancellationRequested) { break }
        if ($httpStatus -gt 0 -and $httpStatus -ne 429 -and $status -ne 'Ошибка сети') {
            $successStreak++
            $consecutiveRateLimits = 0
            if ($successStreak -ge 5 -and $currentDelayMs -gt $minDelayMs) {
                $currentDelayMs = [Math]::Max($minDelayMs,[int]($currentDelayMs * 0.8))
                $successStreak = 0
            }
        }
        $done++
        $now = (Get-Date).ToString('HH:mm:ss')
        $null = $Queue.Enqueue([pscustomobject]@{Type='Progress'; Item=[pscustomobject]@{Name=$name; Platform=$Platform; Category=[string]$item.Category; Structure=[string]$item.Structure; Meaning=[string]$item.Meaning; Status=$status; Reason=$reason; ErrorDetail=$errorDetail; Time=$now; Index=$done; Total=$total; WorkerId=[int]$WorkerId}})
        if ($errorDetail) { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=("{0} ({1}): {2}" -f $name,$Platform,$errorDetail)}) }
        if (-not $stopReason -and $consecutiveProtocolErrors -ge 3) {
            $stopReason = "Три запроса подряд к $Platform отклонены на уровне протокола/антибот-защиты; проверка остановлена. Endpoint мог измениться."
        }
        if ($stopReason -or $consecutiveErrors -ge 3) {
            if (-not $stopReason) { $stopReason = 'Три сетевые ошибки подряд; проверка остановлена для защиты от повторных запросов' }
            break
        }
        if (-not $InputQueue.IsEmpty) {
            $elapsed = 0
            while ($elapsed -lt $currentDelayMs -and -not $Cancellation.IsCancellationRequested) {
                $step = [Math]::Min(100,($currentDelayMs - $elapsed))
                Start-Sleep -Milliseconds $step
                $elapsed += $step
            }
        }
    }
    $null = $Queue.Enqueue([pscustomobject]@{Type='Complete'; Cancelled=[bool]$Cancellation.IsCancellationRequested; Error=$null; StopReason=$stopReason; Checked=$done; Total=$total; WorkerId=[int]$WorkerId})
} catch {
    $null = $Queue.Enqueue([pscustomobject]@{Type='Complete'; Cancelled=[bool]$Cancellation.IsCancellationRequested; Error=$_.Exception.ToString(); StopReason=$stopReason; Checked=$done; Total=$total; WorkerId=[int]$WorkerId})
}
'@
    $script:StartButton.Enabled = $false
    $script:StartButton.Visible = $false
    $script:GenerateButton.Enabled = $false
    $script:StopButton.Enabled = $true
    $script:CategoryList.Enabled = $false
    $script:CountBox.Enabled = $false
    $script:NumbersCheck.Enabled = $false
    $script:UnderscoreCheck.Enabled = $false
    $script:CustomBox.Enabled = $false
    $script:ManualNickBox.Enabled = $false
    $script:DelayBox.Enabled = $false
    $script:TimeoutBox.Enabled = $false
    if ($script:ThreadsBox) { $script:ThreadsBox.Enabled = $false }
    $script:PlatformBox.Enabled = $false
    $script:ProxyBox.Enabled = $false
    try {
        $script:CheckQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $script:CheckInputQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $feedOrder = @($validCandidates)
        if (-not $script:OrderedCheck.Checked -and $feedOrder.Count -gt 1) { $feedOrder = @(Get-ShuffledArray -Items $feedOrder) }
        foreach ($queuedCandidate in $feedOrder) { $script:CheckInputQueue.Enqueue($queuedCandidate) }
        $script:Cancellation = New-Object System.Threading.CancellationTokenSource
        $script:WorkerPowerShells = New-Object 'System.Collections.Generic.List[object]'
        $script:WorkerRunspaces = New-Object 'System.Collections.Generic.List[object]'
        $script:AsyncHandles = New-Object 'System.Collections.Generic.List[object]'
        $script:WorkerDonePerThread = @{}
        $script:CompletedWorkers = 0
        $script:CompletionEvent = $null
        $script:UnhandledWorkerError = $null
        for ($workerIndex = 1; $workerIndex -le $threadCount; $workerIndex++) {
            $script:WorkerDonePerThread[[string]$workerIndex] = 0
            $workerRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
            $workerRunspace.Open()
            $workerPowerShell = [powershell]::Create()
            $workerPowerShell.Runspace = $workerRunspace
            [void]$workerPowerShell.AddScript($workerScript).AddArgument($script:CheckInputQueue).AddArgument($script:CheckQueue).AddArgument($script:Cancellation).AddArgument([int]$script:DelayBox.Value).AddArgument([int]$script:TimeoutBox.Value).AddArgument([string]$selectedPlatform).AddArgument([string]$script:AppVersion).AddArgument([int]$workerIndex).AddArgument([int]$script:CurrentBatchTotal).AddArgument([string]$script:ProxyBox.Text.Trim())
            $script:WorkerRunspaces.Add($workerRunspace)
            $script:WorkerPowerShells.Add($workerPowerShell)
            $script:AsyncHandles.Add($workerPowerShell.BeginInvoke())
        }
        $script:CheckStartedAt = [DateTime]::UtcNow
        $script:PollTimer.Start()
    } catch {
        $message = $_.Exception.ToString()
        Add-Diagnostic ('Не удалось запустить runspace: ' + $message)
        Close-CheckRunspace
        Reset-CheckControls
        $script:SummaryLabel.Text = 'Не удалось запустить проверку'
        [System.Windows.Forms.MessageBox]::Show("Не удалось запустить проверку.`r`n`r`n$message",'Ошибка запуска','OK','Error') | Out-Null
    }
}

$script:PollTimer.Add_Tick({
    if ($script:CheckQueue) {
        $entry = $null
        while ($script:CheckQueue.TryDequeue([ref]$entry)) {
            if ($null -eq $entry) { continue }
            if ($entry.Type -eq 'Progress') {
                $item = $entry.Item
                $candidate = Find-Candidate -Name ([string]$item.Name) -Platform ([string]$item.Platform)
                if ($candidate) {
                    $script:CheckedNames[((([string]$candidate.Platform) + '|' + [string]$candidate.Name).ToLowerInvariant())] = $true
                    $candidate.Status = [string]$item.Status
                    $candidate.Time = [string]$item.Time
                    $candidate.Reason = [string]$item.Reason
                    $candidate.Checked = $true
                    Update-FreeHistoryFromCandidate $candidate
                    Touch-Candidates
                }
                Update-BatchProgress $item
                $script:ProgressBar.Value = [Math]::Min(100,[int](100 * $script:CurrentBatchDone / [Math]::Max(1,$script:CurrentBatchTotal)))
                $captionText = "Прогресс: $($script:CurrentBatchDone)/$($script:CurrentBatchTotal) · $($item.Name)"
                $etaText = Get-CheckEtaText -Done ([int]$script:CurrentBatchDone) -Total ([int]$script:CurrentBatchTotal)
                if ($etaText) { $captionText = "$captionText · $etaText" }
                $script:ProgressCaption.Text = $captionText
                $script:GridRefreshPending = $true
            } elseif ($entry.Type -eq 'Log') {
                Add-Diagnostic ([string]$entry.Message)
            } elseif ($entry.Type -eq 'Complete') {
                Add-CompletionEvent $entry
                $script:CompletedWorkers = $script:CompletedWorkers + 1
            }
            $entry = $null
        }
    }
    if ($script:GridRefreshPending -and (([DateTime]::UtcNow - $script:LastGridRefresh).TotalMilliseconds -ge 250)) {
        $script:GridRefreshPending = $false
        $script:LastGridRefresh = [DateTime]::UtcNow
        Update-ResultGrid
    }
    Flush-HistoryIfDue -IntervalSeconds 5
    if ($null -ne $script:AsyncHandles -and $script:AsyncHandles.Count -gt 0 -and -not (Test-CheckRunning)) {
        $script:PollTimer.Stop()
        foreach ($workerIndex in 0..($script:AsyncHandles.Count - 1)) {
            try { $null = $script:WorkerPowerShells[$workerIndex].EndInvoke($script:AsyncHandles[$workerIndex]) } catch { $script:UnhandledWorkerError = $_.Exception.ToString() }
        }
        if ($script:CheckQueue) {
            $entry = $null
            while ($script:CheckQueue.TryDequeue([ref]$entry)) {
                if ($entry.Type -eq 'Progress') {
                    $item = $entry.Item
                    $candidate = Find-Candidate -Name ([string]$item.Name) -Platform ([string]$item.Platform)
                    if ($candidate) { $script:CheckedNames[((([string]$candidate.Platform) + '|' + [string]$candidate.Name).ToLowerInvariant())] = $true; $candidate.Status=[string]$item.Status; $candidate.Time=[string]$item.Time; $candidate.Reason=[string]$item.Reason; $candidate.Checked=$true; Update-FreeHistoryFromCandidate $candidate; Touch-Candidates }
                    Update-BatchProgress $item
                } elseif ($entry.Type -eq 'Log') { Add-Diagnostic ([string]$entry.Message) }
                elseif ($entry.Type -eq 'Complete') { Add-CompletionEvent $entry; $script:CompletedWorkers = $script:CompletedWorkers + 1 }
                $entry = $null
            }
        }
        $completed = $script:CompletionEvent
        $unhandledError = $script:UnhandledWorkerError
        $workerErrors = ''
        $workerErrorLines = New-Object System.Collections.ArrayList
        foreach ($worker in $script:WorkerPowerShells) {
            try {
                if ($worker -and $worker.Streams.Error.Count -gt 0) {
                    foreach ($workerError in $worker.Streams.Error) { [void]$workerErrorLines.Add($workerError.ToString()) }
                }
            } catch { }
        }
        $workerErrors = ($workerErrorLines -join [Environment]::NewLine)
        Close-CheckRunspace
        Reset-CheckControls
        if ($completed -and ($completed.Cancelled -or $completed.StopReason)) {
            foreach ($candidate in $script:Candidates) {
                if ($candidate.Status -eq 'Проверяется') { $candidate.Status='Ожидает'; $candidate.Reason='Проверка не завершена; можно запустить повторно' }
            }
        }
        $script:GridRefreshPending = $false
        $script:LastGridRefresh = [DateTime]::UtcNow
        if ($script:HistoryDirty) { Save-UsernameHistory }
        Update-ResultGrid
        $script:ProgressBar.Value = [Math]::Min(100,[int](100 * $script:CurrentBatchDone / [Math]::Max(1,$script:CurrentBatchTotal)))
        if ($completed -and $completed.Error) {
            $message = [string]$completed.Error
            $script:SummaryLabel.Text = 'Ошибка проверки — см. журнал'
            Add-Diagnostic $message
            [System.Windows.Forms.MessageBox]::Show("Не удалось завершить проверку.`r`n`r`n$message`r`n`r`nПодробности: UniversalUsernameFinder.log",'Ошибка проверки','OK','Error') | Out-Null
        } elseif ($unhandledError -or $workerErrors) {
            $message = [string]$unhandledError
            if ([string]::IsNullOrWhiteSpace($message)) { $message = $workerErrors }
            $script:SummaryLabel.Text = 'Ошибка проверки — см. журнал'
            Add-Diagnostic $message
            [System.Windows.Forms.MessageBox]::Show("Произошла ошибка при проверке.`r`n`r`n$message`r`n`r`nПодробности: UniversalUsernameFinder.log",'Ошибка проверки','OK','Error') | Out-Null
        } elseif ($completed -and $completed.Cancelled) {
            $script:SummaryLabel.Text = "Остановлено · проверено: $($completed.Checked) · свободно: $($script:AvailableNames.Count) · осталось: $(Get-PendingCandidateCount) — нажми «Возобновить проверку»"
            Add-Diagnostic $script:SummaryLabel.Text
        } elseif ($completed -and $completed.StopReason) {
            $script:SummaryLabel.Text = "Остановлено: $($completed.StopReason) · проверено: $($completed.Checked) · свободно: $($script:AvailableNames.Count)"
            Add-Diagnostic $script:SummaryLabel.Text
        } else {
            $script:SummaryLabel.Text = "Готово · проверено: $($completed.Checked) · свободно/возможно: $($script:AvailableNames.Count)"
            Add-Diagnostic $script:SummaryLabel.Text
        }
    }
})

$script:GenerateButton.Add_Click({
    if (Test-CheckRunning) { return }
    if ([int]$script:MinLengthBox.Value -gt [int]$script:MaxLengthBox.Value) {
        [System.Windows.Forms.MessageBox]::Show('Минимальная длина не может быть больше максимальной.','Настройки','OK','Warning') | Out-Null
        return
    }
    $platform = [string]$script:PlatformBox.SelectedItem
    $categories = @($script:CategoryList.CheckedItems | ForEach-Object { [string]$_ })
    $customWords = Get-TextBoxValue $script:CustomBox
    $excludeTokens = @($script:ExcludeBox.Text -split '[,;\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $requestedCount = [int]$script:CountBox.Value
    # --- Конфликты настроек: предупреждаем до генерации, а не молча теряем ники
    $enabledSources = @($script:OneWordCheck, $script:TwoWordsCheck, $script:InventedWordsCheck, $script:InventedPairsCheck, $script:LeetCheck, $script:RareShortCheck, $script:RandomCharsCheck, $script:NumbersCheck) | Where-Object { $_.Checked }
    if (@($enabledSources).Count -eq 0) { Add-Diagnostic 'Ни один источник генерации не выбран: использую однословные ники как запасной вариант. Включи нужные галочки в «Настройки генерации».' }
    if ([bool]$script:ShortOnlyCheck.Checked -and [int]$script:MinLengthBox.Value -gt 12) {
        [System.Windows.Forms.MessageBox]::Show('«Только короткие (≤12)» не совместимо с минимальной длиной больше 12 символов: ников не будет. Уменьши минимальную длину или сними галочку «Только короткие».', 'Настройки', 'OK', 'Warning') | Out-Null
        return
    }
    if ([bool]$script:UnderscoreCheck.Checked -and ($platform -eq 'Google' -or $platform -eq 'GitHub')) {
        Add-Diagnostic ('Разделитель «_» не допускает платформа ' + $platform + ': ники с подчёркиванием будут отброшены по формату. Сними галочку «Разделитель _».')
    }
    Update-VpnNotice
    $script:Candidates.Clear()
    Clear-CandidateIndex
    $script:AvailableNames.Clear()
    $seen = @{}
    $excludeKeys = @{}
    foreach ($retiredKey in $script:RetiredNames.Keys) { $excludeKeys[[string]$retiredKey] = $true }
    if ($script:ExcludeCheckedCheck.Checked) {
        foreach ($checkedKey in $script:CheckedNames.Keys) { $excludeKeys[[string]$checkedKey] = $true }
    }
    $candidates = @(New-AdvancedCandidatePool -SelectedWordCategories $categories -CustomWords $customWords -Style ([string]$script:StyleBox.SelectedItem) -Platform $platform -MinLength ([int]$script:MinLengthBox.Value) -MaxLength ([int]$script:MaxLengthBox.Value) -Count $requestedCount -UseNumbers ([bool]$script:NumbersCheck.Checked) -UseUnderscore ([bool]$script:UnderscoreCheck.Checked) -OneWord ([bool]$script:OneWordCheck.Checked) -TwoWords ([bool]$script:TwoWordsCheck.Checked) -InventedWords ([bool]$script:InventedWordsCheck.Checked) -InventedPairs ([bool]$script:InventedPairsCheck.Checked) -LeetWords ([bool]$script:LeetCheck.Checked) -RareShort ([bool]$script:RareShortCheck.Checked) -Ordered ([bool]$script:OrderedCheck.Checked) -RandomChars ([bool]$script:RandomCharsCheck.Checked) -OnlyShort ([bool]$script:ShortOnlyCheck.Checked) -ExcludeTokens $excludeTokens -ExcludeKeys $excludeKeys)
    # --- Разнобой: гарантированно перемешиваем и сам вывод пула (страховка от тихого сбоя перемешивания внутри)
    if (-not $script:OrderedCheck.Checked -and @($candidates).Count -gt 1) { $candidates = @(Get-ShuffledArray -Items @($candidates)) }
    $poolStats = $script:GenerationStats
    if ($null -eq $poolStats) { $poolStats = @{} }
    if ($candidates.Count -lt $requestedCount) {
        Add-Diagnostic ("Создано {0} из {1}: пространство имён исчерпано при текущих фильтрах. Отсеяно — по длине {2}, по формату платформы {3}, по словам-исключениям {4}, повторов {5}, уже проверено/занято {6}." -f $candidates.Count, $requestedCount, $poolStats['ByLength'], $poolStats['ByFormat'], $poolStats['ByExcludedToken'], $poolStats['ByDuplicate'], $poolStats['ByAlreadyUsed'])
        Add-Diagnostic ("По источникам — однословные {0}, двусловные {1}, выдуманные {2}, выдуманные сочетания {3}, с заменой символами {4}, редкие короткие {5}, с цифрами {6}." -f $poolStats['Single'], $poolStats['Pair'], $poolStats['Invented'], $poolStats['InventedPair'], $poolStats['Leet'], $poolStats['Rare'], $poolStats['Number'])
    }
    $manualNickText = Get-TextBoxValue $script:ManualNickBox
    $manualBoxHasText = -not [string]::IsNullOrWhiteSpace($manualNickText)
    if ($candidates.Count -eq 0 -and -not $manualBoxHasText) {
        if ($categories.Count -lt 1 -and [string]::IsNullOrWhiteSpace($customWords)) {
            $noVariantHint = 'Не выбрана ни одна категория и не введены свои слова. Нажми «Выделить все» или впиши свои слова через запятую.'
        } elseif ($excludeKeys.Count -gt 0) {
            $noVariantHint = ("Запас имён исчерпан: уже проверено или занято {0}. Сними галочку «Исключать проверенные», включи «Выдуманные слова» и «Выдуманные словосочетания» или очисти список проверенных имён в окне «Свободные ники»." -f $excludeKeys.Count)
        } else {
            $noVariantHint = 'Под текущие фильтры не подошёл ни один вариант. Проверь диапазон длины, слова-исключения и требования выбранной платформы.'
        }
        [System.Windows.Forms.MessageBox]::Show($noVariantHint,'Нет вариантов','OK','Warning') | Out-Null
        Add-Diagnostic $noVariantHint
        return
    }
    if ($candidates.Count -eq 0 -and $manualBoxHasText) {
        Add-Diagnostic 'Генерация по настройкам не дала новых имён — все варианты уже проверены или отсеяны фильтрами, в таблицу берутся только ручные ники. Сними «Исключать проверенные» или ослабь фильтры, чтобы вернуть пул.'
    }
    $added = 0
    $addedManual = 0
    $dropped = 0
    foreach ($candidate in $candidates) {
        $key = (($platform + '|' + [string]$candidate.Name).ToLowerInvariant())
        if ($script:RetiredNames.ContainsKey($key)) { $dropped++; continue }
        if ($script:ExcludeCheckedCheck.Checked -and $script:CheckedNames.ContainsKey($key)) { $dropped++; continue }
        if ($seen.ContainsKey($key)) { $dropped++; continue }
        [void]$script:Candidates.Add($candidate)
        Register-Candidate $candidate
        $seen[$key] = $true
        $added++
    }
    if ($dropped -gt 0) { Add-Diagnostic ("Отброшено после генерации: {0} (совпали с уже проверенными или занятыми)." -f $dropped) }
    foreach ($nickRaw in ($manualNickText -split '[,;\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $nick = Get-PlatformNickInput -Platform $platform -Raw $nickRaw
        $key = (($platform + '|' + $nick).ToLowerInvariant())
        if ($seen.ContainsKey($key) -or $script:RetiredNames.ContainsKey($key)) { continue }
        $status = 'Ожидает'; $reason = 'Ожидает проверки'
        if (-not (Test-UsernameFormat -Username $nick -Platform $platform)) { $status = 'Недопустимый'; $reason = "Неверный формат имени для платформы $platform" }
        $manualTime = ''
        if ($status -eq 'Недопустимый') { $manualTime = (Get-Date).ToString('HH:mm:ss') }
        $manualCandidate = [pscustomobject]@{Name=$nick; Platform=$platform; Meaning='Введён вручную'; Category='Ручной ввод'; Structure=(Get-NickStructure -Name $nick); Status=$status; Time=$manualTime; Reason=$reason; Checked=($status -eq 'Недопустимый')}
        [void]$script:Candidates.Add($manualCandidate)
        Register-Candidate $manualCandidate
        $seen[$key]=$true; $added++; $addedManual++
    }
    Touch-Candidates
    if ($script:Candidates.Count -gt 5000) { [System.Windows.Forms.MessageBox]::Show('В списке больше 5000 записей: таблица может перерисовываться медленнее. Экспортируй результаты или очисти список.','Размер списка','OK','Information') | Out-Null }
    Update-ResultGrid
    if ($added -eq $requestedCount) {
        Add-Diagnostic ("Для платформы {0} создано ровно {1} ников. Всего в таблице: {2}." -f $platform, $added, $script:Candidates.Count)
    } else {
        Add-Diagnostic ("Для платформы {0} добавлено новых ников: {1} из запрошенных {2}. Всего в таблице: {3}." -f $platform, $added, $requestedCount, $script:Candidates.Count)
    }
    if ($addedManual -gt 0) { $script:SummaryLabel.Text = "Сгенерировано: $added · ручных: $addedManual · проверка запускается" } else { $script:SummaryLabel.Text = "Сгенерировано: $added · автоматическая проверка запускается" }
    if ($added -gt 0) { Start-Checking -RetryErrorsOnly $false }
})

$script:StartButton.Add_Click({ Start-Checking -RetryErrorsOnly $false -ResumePending $true })
$script:RetryButton.Add_Click({ Start-Checking -RetryErrorsOnly $true })
$script:StopButton.Add_Click({
    if ($script:Cancellation -and -not $script:Cancellation.IsCancellationRequested) {
        $script:Cancellation.Cancel()
        $script:StopButton.Enabled = $false
        $script:SummaryLabel.Text = 'Остановка после текущего запроса...'
        Add-Diagnostic 'Запрошена остановка проверки.'
    }
})

$script:SaveButton.Add_Click({
    Update-AvailableNames
    if ($script:AvailableNames.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Пока нет свободных ников.','Сохранение','OK','Information') | Out-Null; return }
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'Текстовый файл (*.txt)|*.txt'
    $dialog.FileName = 'Universal_Usernames_Free_' + (Get-Date -Format 'yyyy-MM-dd_HH-mm') + '.txt'
    $dialog.Title = 'Сохранить свободные ники'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        [System.IO.File]::WriteAllLines($dialog.FileName,$script:AvailableNames.ToArray(),(New-Object System.Text.UTF8Encoding -ArgumentList $true))
        Add-Diagnostic "TXT экспортировано свободных ников: $($script:AvailableNames.Count) → $($dialog.FileName)"
    }
})
$script:CsvButton.Add_Click({
    if ($script:Candidates.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Таблица пока пуста.','Экспорт','OK','Information') | Out-Null; return }
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'CSV (*.csv)|*.csv'
    $dialog.FileName = 'Universal_Usernames_All_' + (Get-Date -Format 'yyyy-MM-dd_HH-mm') + '.csv'
    $dialog.Title = 'Экспорт всех результатов'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:Candidates | Select-Object @{Name='Платформа';Expression={$_.Platform}},@{Name='Ник';Expression={(Get-DisplayNick -Platform ([string]$_.Platform) -Name ([string]$_.Name))}},@{Name='Статус';Expression={$_.Status}},@{Name='Категория';Expression={$_.Category}},@{Name='Структура';Expression={$_.Structure}},@{Name='Значение';Expression={$_.Meaning}},@{Name='Время';Expression={$_.Time}},@{Name='Причина';Expression={$_.Reason}} | Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Encoding UTF8
        Add-Diagnostic "CSV экспортировано записей: $($script:Candidates.Count) → $($dialog.FileName)"
    }
})
$script:CopyButton.Add_Click({
    Update-AvailableNames
    if ($script:AvailableNames.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Пока нет свободных ников.','Копирование','OK','Information') | Out-Null; return }
    if (Copy-UufTextToClipboard -Text ($script:AvailableNames -join [Environment]::NewLine) -Context 'копирование свободных ников') { $script:SummaryLabel.Text = "Скопировано свободных ников: $($script:AvailableNames.Count)" }
})
$script:ClearButton.Add_Click({
    if (Test-CheckRunning) { return }
    $script:Candidates.Clear()
    Clear-CandidateIndex
    $script:AvailableNames.Clear()
    Touch-Candidates
    $script:ProgressBar.Value = 0
    $script:ProgressCaption.Text = 'Прогресс проверки'
    Update-ResultGrid
    $script:SummaryLabel.Text = 'Результаты очищены'
    Add-Diagnostic ('Таблица очищена. Список проверенных имён сохранён ({0}); управлять им можно в окне «Проверенные ники».' -f $script:CheckedNames.Count)
})
$script:CopyLogButton.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($script:DiagnosticBox.Text)) { Copy-UufTextToClipboard -Text $script:DiagnosticBox.Text -Context 'копирование журнала' | Out-Null }
})
$script:ClearLogButton.Add_Click({ $script:DiagnosticBox.Clear(); Add-Diagnostic 'Журнал очищен.' })
$script:StatusFilterBox.Add_SelectedIndexChanged({ Update-ResultGrid })
$script:SortBox.Add_SelectedIndexChanged({ Update-ResultGrid })
$script:SearchBox.Add_TextChanged({ Update-ResultGrid })
$script:OnlyFreeCheck.Add_CheckedChanged({ Update-ResultGrid })
$script:ExcludeCheckedCheck.Add_CheckedChanged({ })
$script:OpenPlatformButton.Add_Click({
    try {
        $platform = [string]$script:PlatformBox.SelectedItem
        $username = ''
        if ($script:Grid.SelectedRows.Count -gt 0) {
            $selectedRow = $script:Grid.SelectedRows[0]
            $username = [string]$selectedRow.Cells['Nick'].Value
            $selectedPlatform = [string]$selectedRow.Cells['Platform'].Value
            if ($selectedPlatform) { $platform = $selectedPlatform }
        }
        $url = Get-PlatformWebsiteUrl -Platform $platform -Username $username
        Start-Process $url
        Add-Diagnostic ("Открыт сайт платформы: {0} ({1})" -f $platform,$url)
    } catch {
        Add-Diagnostic ('Не удалось открыть сайт платформы: ' + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show('Не удалось открыть сайт: ' + $_.Exception.Message,'Ошибка','OK','Error') | Out-Null
    }
})
$script:Grid.Add_SelectionChanged({
    try {
        if ($null -ne $script:AccountForm -and -not $script:AccountForm.IsDisposed -and $script:Grid.CurrentRow -and $script:Grid.CurrentRow.Index -ge 0) {
            $rowPlatform = [string]$script:Grid.CurrentRow.Cells['Platform'].Value
            if ($rowPlatform -and ($script:SupportedPlatforms -contains $rowPlatform) -and $rowPlatform -ne [string]$script:PlatformBox.SelectedItem) { $script:PlatformBox.SelectedItem = $rowPlatform }
        }
    } catch { }
})
$script:PlatformBox.Add_SelectedIndexChanged({ Update-VpnNotice })
$script:PlatformBox.Add_SelectedIndexChanged({
    if ($script:PlatformBox.SelectedItem) {
        $selectedPlatform = [string]$script:PlatformBox.SelectedItem
        $script:SummaryLabel.Text = "Выбрана платформа: $selectedPlatform"
        Update-AccountPlatformUi
        Add-Diagnostic "Выбрана платформа проверки: $selectedPlatform. Для проверки используются только строки этой платформы."
        try {
            $rule = Get-PlatformLengthRule -Platform $selectedPlatform
            $ruleMin = [int]$rule.Min
            $ruleMax = [Math]::Min([int]$rule.Max, [int]$script:MaxLengthBox.Maximum)
            if ($ruleMin -ge $script:MinLengthBox.Minimum -and $ruleMin -le $script:MinLengthBox.Maximum) {
                $script:MinLengthBox.Value = $ruleMin
            }
            if ($ruleMax -ge $script:MaxLengthBox.Minimum -and $ruleMax -le $script:MaxLengthBox.Maximum) {
                $script:MaxLengthBox.Value = $ruleMax
            }
            if ([int]$script:MinLengthBox.Value -gt [int]$script:MaxLengthBox.Value) {
                $script:MinLengthBox.Value = [int]$script:MaxLengthBox.Value
            }
            Add-Diagnostic ("Длина ника для {0}: от {1} до {2} символов — значения подставлены в поля минимальной и максимальной длины." -f $selectedPlatform, [int]$script:MinLengthBox.Value, [int]$script:MaxLengthBox.Value)
        } catch {
            Add-Diagnostic ('Не удалось подставить правило длины для платформы: ' + $_.Exception.Message)
        }
    }
})

$script:ApiDocsButton.Add_Click({ Show-UsernameFinderHelp })
$script:HistoryButton.Add_Click({ Open-FreeHistoryWindow })
$script:CheckedNamesButton.Add_Click({ Open-CheckedNamesWindow })
$script:ConnectionTestButton.Add_Click({ Open-ConnectionTestWindow })
Update-CheckedNamesButtonText
$script:HistoryButton.Text = "Свободные ники ($($script:FreeHistory.Count))"
$script:AccountButton.Add_Click({ Open-AccountTools })

Restore-AppSettings
try { if ($script:OnlyFreeCheck.Checked) { Refresh-FreeHistoryList } } catch { }
Update-ResultGrid
Add-Diagnostic ('Universal Username Finder v{0} запущен. Генерация автоматически запускает проверку выбранной платформы в несколько потоков; число потоков задаётся в настройках слева.' -f $script:AppVersion)

$script:Form.Add_FormClosing({
    try { if ($script:Cancellation -and -not $script:Cancellation.IsCancellationRequested) { $script:Cancellation.Cancel() } } catch { }
    try { if ($script:PollTimer) { $script:PollTimer.Stop() } } catch { }
    foreach ($worker in $script:WorkerPowerShells) { try { if ($worker) { $worker.Stop() } } catch { } }
    foreach ($runspace in $script:WorkerRunspaces) { try { if ($runspace) { $runspace.Close() } } catch { } }
    try { if ($script:PasswordRng) { $script:PasswordRng.Dispose() } } catch { }
    try { if ($script:HistoryDirty) { Save-UsernameHistory } } catch { }
    try { Save-AppSettings } catch { }
    try {
        if ($script:SingleInstanceMutex) {
            try { [void]$script:SingleInstanceMutex.ReleaseMutex() } catch { }
            $script:SingleInstanceMutex.Dispose()
            $script:SingleInstanceMutex = $null
        }
    } catch { }
})

$uufClientSize = $script:Form.ClientSize
$uufClientWidth = [int]$uufClientSize.Width
$uufClientHeight = [int]$uufClientSize.Height
$uufEdgeRightX = $uufClientWidth - 6
$uufEdgeBottomY = $uufClientHeight - 6
$uufResizeEdgeLeft = New-UufResizeEdge 'ResizeEdgeLeft' 0 0 6 $uufClientHeight 'Top, Bottom, Left' ([System.Windows.Forms.Cursors]::SizeWE) 10
$uufResizeEdgeRight = New-UufResizeEdge 'ResizeEdgeRight' $uufEdgeRightX 0 6 $uufClientHeight 'Top, Bottom, Right' ([System.Windows.Forms.Cursors]::SizeWE) 11
$uufResizeEdgeBottom = New-UufResizeEdge 'ResizeEdgeBottom' 0 $uufEdgeBottomY $uufClientWidth 6 'Bottom, Left, Right' ([System.Windows.Forms.Cursors]::SizeNS) 15

try {
    Set-ButtonEdgeStyle -Root $script:Form
    try { if ($script:UufDwmAvailable) { [UufDwmCorners]::Round($script:Form.Handle) } } catch { }
    [void]$script:Form.ShowDialog()
} catch {
    Write-StartupLog ('Фатальная ошибка главного окна: ' + $_.Exception.ToString())
    Show-FatalError 'Фатальная ошибка' ("Приложение не может продолжить работу:`r`n`r`n{0}`r`n`r`nПодробности: UniversalUsernameFinder.log" -f $_.Exception.Message)
    exit 1
}
