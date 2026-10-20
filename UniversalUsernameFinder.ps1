$ErrorActionPreference = 'Stop'
$script:AppVersion = '2.5.4'

# Каталог приложения. При запуске из .ps1 это каталог скрипта, а в скомпилированном
# .exe переменная $PSScriptRoot пуста — ps2exe вместо неё задаёт $ScriptRoot. Если и он
# недоступен, берётся каталог сборки процесса. Без этого журнал в .exe уезжал бы в
# непредсказуемое место.
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

# Журнал: предпочитаем папку скрипта, но если она недоступна для записи
# (например, программа распакована в Program Files), уходим в профиль пользователя.
# Раньше запись молча глоталась catch-блоком, и диагностика пропадала.
function Resolve-LogPath {
    $primary = Join-Path (Get-AppDirectory) 'UniversalUsernameFinder.log'
    try {
        $directory = Split-Path -Parent $primary
        $probe = Join-Path $directory ('.uuf-write-probe-' + [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($probe, 'probe')
        [System.IO.File]::Delete($probe)
        return $primary
    } catch { }
    try {
        $fallbackDirectory = Join-Path $env:LOCALAPPDATA 'UniversalUsernameFinder'
        $null = [System.IO.Directory]::CreateDirectory($fallbackDirectory)
        return (Join-Path $fallbackDirectory 'UniversalUsernameFinder.log')
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

$script:LogPath = Resolve-LogPath
Rotate-AppLog

Add-Type -AssemblyName System.Security
# До версии 2.5.4 зашифрованное хранилище аккаунтов лежало в папке RobloxNickFinder:
# приложение тогда работало только с Roblox. Теперь платформ 12, поэтому хранилище
# переносится в общую папку приложения. Старый путь сохранён для миграции.
$script:VaultDirectory = Join-Path $env:LOCALAPPDATA 'UniversalUsernameFinder'
$script:VaultPath = Join-Path $script:VaultDirectory 'accounts.dat'
$script:LegacyVaultDirectory = Join-Path $env:LOCALAPPDATA 'RobloxNickFinder'
$script:LegacyVaultPath = Join-Path $script:LegacyVaultDirectory 'accounts.dat'
# Значение энтропии намеренно оставлено прежним: оно участвует в расшифровке уже
# созданных хранилищ, и его смена сделала бы сохранённые аккаунты нечитаемыми.
# Секретом эта строка не является (она лежит в открытом репозитории) — реальную
# защиту даёт область DPAPI CurrentUser: данные расшифровывает только тот же
# пользователь Windows на той же машине. Подробности в README.
$script:VaultEntropy = [System.Text.Encoding]::UTF8.GetBytes('RobloxNickFinder:account-vault:v1')
$script:PasswordRng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::DefaultConnectionLimit = 10

# Два запущенных экземпляра одновременно пишут историю ников и хранилище аккаунтов,
# поэтому второй экземпляр не запускаем. Ссылку на Mutex держим в переменной скрипта,
# иначе сборщик мусора освободит её и защита перестанет работать.
$script:SingleInstanceMutex = $null
try {
    $createdNew = $false
    $script:SingleInstanceMutex = New-Object System.Threading.Mutex($true, 'Local\UniversalUsernameFinder.SingleInstance', [ref]$createdNew)
    if (-not $createdNew) {
        [System.Windows.Forms.MessageBox]::Show('Universal Username Finder уже запущен. Второе окно не открыто, чтобы не повредить историю ников и зашифрованное хранилище.','Приложение уже запущено','OK','Information') | Out-Null
        exit 0
    }
} catch {
    # Если Mutex создать не удалось, не блокируем запуск: пишем причину в журнал.
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
    # Переносит зашифрованное хранилище из старой папки RobloxNickFinder в общую
    # папку приложения. DPAPI привязан к пользователю Windows, а не к пути файла,
    # поэтому перенос не мешает расшифровке. Старый файл не удаляется, а
    # переименовывается в accounts.dat.migrated — это запасной вариант на случай,
    # если что-то пойдёт не так.
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

# Необработанные исключения больше не закрывают приложение молча: они пишутся в журнал
# и показываются пользователю. Регистрация обёрнута в try/catch, чтобы сбой самого
# механизма не мешал запуску.
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
    @{Word='Drift'; Meaning='дрейф или контролируемый занос'}, @{Word='Pulse'; Meaning='пульс, ритм'}, @{Word='Rogue'; Meaning='независимый боец'}
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

$script:MeaningGroups = @{
    'Свет и энергия' = @('Aurora','Ember','Blaze','Nova','Pulse','Solar','Stellar','Lux','Radiant','Cinder')
    'Космос' = @('Orion','Lyra','Nova','Lunar','Solar','Comet','Orbit','Nebula','Cosmos','Meteor','Stellar','Astra','Altair','Auriga')
    'Природа' = @('Tundra','Willow','Aspen','River','Ocean','Coral','Storm','Frost','Glacier','Rain','Cloud','Sierra','Moss','Flora','Fauna','Petal','Breeze','Raven','Lynx','Ivy')
    'Эмоции' = @('Haven','Serenity','Valor','Solace','Karma','Mystic','Fable','Sage','Ever','Lucid')
    'Скорость' = @('Flux','Drift','Strafe','Vector','Raptor','Pulse','Hyper','Ultra','Vortex','Ace')
    'Абстрактное' = @('Cipher','Flux','Vortex','Nexus','Void','Echo','Meta','Quantum','Zenith','Mirage','Glitch','Rune')
    'Короткие' = @('Nyx','Kai','Neo','Zen','Rune','Echo','Void','Sol','Lux','Vex','Zed','Kiro','Nox','Milo','Luma','Koda','Ryn','Aero','Zora','Ari','Rex','Lynx','Juno','Omen')
    'Эстетика' = @('Astra','Velvet','Crystal','Mirage','Lyra','Solace','Luma','Serenity','Aether','Zephyr','Elysium','Celeste')
    'Мифология' = @('Atlas','Nyx','Orion','Phoenix','Aether','Hermes','Athena','Apollo','Loki','Freya','Odin','Titan','Valkyrie','Medusa','Draco','Cerberus','Artemis','Perseus','Hades','Elysium','Ares','Icarus','Pegasus','Hydra','Argos','Midas','Juno','Vesta','Morpheus')
}
$script:MeaningGroups['Цельные слова'] = @($script:MeaningSeeds | ForEach-Object { [string]$_.Word }) + @('Velora','Auralis','Nymera','Solara','Lunara','Lumora','Zephyra','Caelum','Vesper','Elara','Halcyon','Reverie','Meridian','Equinox','Saffron','Indigo','Sable','Glimmer','Celeste','Azure','Astraea','Caldera','Ardent','Seraph','Evora','Virelia','Novara','Zyra','Aven','Orlune','Nyxen','Aetheris','Aurix','Elarion','Solune','Auralyn','Zephryn','Caelix','Faylen','Oryn')

$script:StyleWords = @{
    'Минималистичный' = @('Neo','Zen','Nox','Nyx','Lux','Ryn')
    'Киберспортивный' = @('Clutch','Rift','Vex','Rogue','Ace','Strafe')
    'Футуристический' = @('Quantum','Vector','Nexus','Cyber','Hyper','Pulse','Nova')
    'Тёмный' = @('Noctis','Shadow','Obsidian','Void','Phantom','Onyx','Raven')
    'Эстетичный' = @('Lunar','Velvet','Astra','Serene','Luma','Aether')
    'Редкий' = @('Aether','Zephyr','Elysium','Solace','Altair','Auriga')
    'Короткий' = @('Nyx','Lux','Nox','Vex','Zed','Ryn')
    'Двусловный' = @('Nova','Echo','Pulse','Orbit','Frost','Shadow')
}
$script:CheckedNames = @{}
$script:Candidates = New-Object 'System.Collections.Generic.List[object]'
# Индекс «платформа|ник» → кандидат: без него каждый результат проверки искался
# линейным перебором всего списка (O(n²) на прогон) и подтормаживал интерфейс.
$script:CandidateIndex = @{}
# Ревизия списка кандидатов и ревизия, до которой уже посчитаны свободные ники.
# Пока они равны, Update-AvailableNames не пересчитывает списки заново.
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
# Палитра статусов таблицы вынесена из цикла перерисовки: раньше switch с
# FromArgb выполнялся для каждой строки при каждом обновлении сетки.
$script:StatusColors = @{
    'Свободен'            = [System.Drawing.Color]::FromArgb(99,222,151)
    'Вероятно свободен'   = [System.Drawing.Color]::FromArgb(120,205,250)
    'Занят'               = [System.Drawing.Color]::FromArgb(245,120,120)
    'Недопустимый'        = [System.Drawing.Color]::FromArgb(180,188,203)
    'Не подтверждено'      = [System.Drawing.Color]::FromArgb(207,185,255)
    'Ошибка сети'         = [System.Drawing.Color]::FromArgb(255,190,92)
    'Проверяется'         = [System.Drawing.Color]::FromArgb(105,185,255)
}
try {
    if (Test-Path -LiteralPath $script:HistoryPath) {
        # ReadAllText вместо Get-Content: в Windows PowerShell 5.1 Get-Content без
        # -Encoding читает файл без BOM как ANSI. Файлы истории, созданные до версии
        # 2.5.2, записывались без BOM, поэтому кириллические статусы («Свободен»)
        # превращались в нечитаемые символы и сравнения переставали срабатывать.
        $historyJson = [System.IO.File]::ReadAllText($script:HistoryPath)
        if (-not [string]::IsNullOrWhiteSpace($historyJson)) {
            $historyData = $historyJson | ConvertFrom-Json -ErrorAction Stop
            $script:FreeHistory = @($historyData.FreeHistory | Where-Object { $_.Name -and $_.Platform })
            foreach ($retiredKey in @($historyData.RetiredNames)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$retiredKey)) { $script:RetiredNames[[string]$retiredKey] = $true }
            }
        }
    }
} catch {
    $script:FreeHistory = @()
    $script:RetiredNames = @{}
    Write-StartupLog ('Не удалось прочитать историю ников, начинаем с пустой: ' + $_.Exception.Message)
}

# Индекс «слово → значение» строится один раз за сеанс.
# Раньше Get-SeedForWord на каждый вызов склеивал семь массивов (около 300 объектов)
# и выполнял линейный поиск через Where-Object; вызовов за одну генерацию сотни,
# поэтому сборка кандидатов была заметно медленнее самой проверки.
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
    # ContainsKey с пустым или null-ключом бросил бы исключение, поэтому проверка выше.
    if ($script:SeedIndex.ContainsKey($Word)) { return $script:SeedIndex[$Word] }
    return [pscustomobject]@{ Word = $Word; Meaning = $FallbackMeaning }
}

# Определяет, из скольких слов состоит ник. Для сгенерированных кандидатов структура
# известна в момент создания и задаётся явно; функция нужна для ручного ввода и для
# собственных слов пользователя, где состав заранее неизвестен.
function Get-NickStructure {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return 'Одно слово' }
    $letters = [regex]::Replace($Name, '[^A-Za-z]', '')
    if ($letters.Length -lt 2) { return 'Одно слово' }
    # Внутренняя заглавная буква — признак склейки: все словарные токены приложения
    # начинаются с заглавной и внутренних не имеют (Nova, Aurora, Shadow).
    # BoomSquare -> граница перед S, то есть два слова.
    for ($i = 1; $i -lt $letters.Length; $i++) {
        if ([char]::IsUpper($letters[$i])) { return 'Два слова' }
    }
    # Разделитель тоже означает два слова: Boom_Square.
    if ($Name.IndexOf('_') -ge 0) { return 'Два слова' }
    # Слитное написание без заглавных проверяем разбиением по словарю.
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
    return ($Username.Length -ge 3 -and $Username.Length -le 20 -and $Username -match '^[A-Za-z0-9][A-Za-z0-9_]*$' -and $Username -notmatch '__|_$' -and ([regex]::Matches($Username, '_').Count -le 1))
}

# Единый источник правды: платформы, для которых в воркере реализована реальная проверка.
# Список используется и для заполнения ComboBox, и для валидации, чтобы они не расходились.
$script:SupportedPlatforms = @('Roblox','Google','Mail.ru','VK','Discord','TikTok','Microsoft','Outlook','Telegram','GitHub','YouTube','Apple')

function Test-SupportedPlatform {
    param([string]$Platform)
    if ([string]::IsNullOrWhiteSpace($Platform)) { return $false }
    return ($script:SupportedPlatforms -contains $Platform)
}

function Test-UsernameFormat {
    param([string]$Username, [string]$Platform)
    if ([string]::IsNullOrWhiteSpace($Username)) { return $false }
    switch ($Platform) {
        'Roblox' { return (Test-RobloxUsernameFormat $Username) }
        'Google' { return ($Username.Length -ge 6 -and $Username.Length -le 30 -and $Username -match '^[A-Za-z0-9.]+$' -and $Username -notmatch '(^\.|\.$|\.\.)') }
        'Mail.ru' { return ($Username.Length -ge 4 -and $Username.Length -le 31 -and $Username -match '^[A-Za-z][A-Za-z0-9._-]*$' -and $Username -notmatch '([._-]$|\.\.)') }
        'VK' { return ($Username.Length -ge 5 -and $Username.Length -le 32 -and $Username -match '^[A-Za-z0-9._]+$' -and $Username -notmatch '(^[._]|[._]$|\.\.)' -and $Username -notmatch '^\d+$') }
        'Microsoft' { return ($Username.Length -ge 3 -and $Username.Length -le 64 -and $Username -match '^[A-Za-z0-9._-]+$' -and $Username -notmatch '(^[._-]|[._-]$|\.\.)') }
        'Outlook' { return ($Username.Length -ge 3 -and $Username.Length -le 64 -and $Username -match '^[A-Za-z][A-Za-z0-9._-]*$' -and $Username -notmatch '([._-]$|\.\.)') }
        'Apple' { return ($Username.Length -ge 3 -and $Username.Length -le 64 -and $Username -match '^[A-Za-z0-9._-]+$' -and $Username -notmatch '(^[._-]|[._-]$|\.\.)') }
        'GitHub' { return ($Username.Length -ge 1 -and $Username.Length -le 39 -and $Username -match '^(?!-)(?!.*--)[A-Za-z0-9-]+(?<!-)$') }
        'Discord' {
            $discordNameForFormat = $Username.ToLowerInvariant()
            return ($Username.Length -ge 2 -and $Username.Length -le 32 -and $Username -match '^[A-Za-z0-9_.]+$' -and $Username -notmatch '(^\.|\.$|\.\.)' -and $discordNameForFormat -notin @('discord','clyde','nitro','here','everyone','system'))
        }
        'YouTube' { return ($Username.Length -ge 3 -and $Username.Length -le 30 -and $Username -match '^[A-Za-z0-9._-]+$' -and $Username -notmatch '\.\.$') }
        'TikTok' { return ($Username.Length -ge 2 -and $Username.Length -le 24 -and $Username -match '^[A-Za-z0-9_.]+$' -and $Username -notmatch '(^\.|\.$|\.\.)') }
        'Telegram' { return ($Username.Length -ge 5 -and $Username.Length -le 32 -and $Username -match '^[A-Za-z][A-Za-z0-9_]*$') }
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
        'Microsoft' { return 'https://signup.live.com/' }
        'Outlook' { return 'https://signup.live.com/' }
        'Apple' { return 'https://account.apple.com/' }
        'GitHub' { if ($Username) { return ('https://github.com/' + $safeName) }; return 'https://github.com/signup' }
        'Discord' { return 'https://discord.com/register' }
        'YouTube' { if ($Username) { return ('https://www.youtube.com/@' + $safeName) }; return 'https://www.youtube.com/' }
        'TikTok' { if ($Username) { return ('https://www.tiktok.com/@' + $safeName) }; return 'https://www.tiktok.com/signup' }
        'Telegram' { if ($Username) { return ('https://t.me/' + $safeName) }; return 'https://telegram.org/' }
        default { return 'https://www.google.com/search?q=' + [uri]::EscapeDataString($Platform + ' username ' + $Username) }
    }
}

# Fisher–Yates вместо Sort-Object { Get-Random }: последний пересчитывает ключ сортировки
# и даёт смещённую, нестабильную выборку, к тому же O(n log n) вместо O(n).
function Get-ShuffledArray {
    param([object[]]$Items)
    # Копия обязательна: @($Items) для уже готового object[] возвращает ту же ссылку,
    # и перемешивание изменило бы массив вызывающего кода.
    $array = @($Items).Clone()
    for ($i = $array.Length - 1; $i -gt 0; $i--) {
        $j = Get-Random -Minimum 0 -Maximum ($i + 1)
        $temp = $array[$i]
        $array[$i] = $array[$j]
        $array[$j] = $temp
    }
    return $array
}

function New-AdvancedCandidatePool {
    param(
        [string[]]$SelectedWordCategories,
        [string]$CustomWords,
        [string]$CustomTheme,
        [string]$Style,
        [string]$Platform,
        [string]$Prefix,
        [string]$Suffix,
        [int]$MinLength,
        [int]$MaxLength,
        [int]$Count,
        [bool]$UseNumbers,
        [bool]$UseUnderscore,
        [bool]$OneWord,
        [bool]$TwoWords,
        [bool]$OnlyShort,
        [string[]]$ExcludeTokens,
        [hashtable]$ExcludeKeys
    )
    # ExcludeKeys — уже занятые и уже проверенные ники в формате «платформа|ник».
    # Генератор отсеивает их сам: раньше это делал вызывающий код после получения
    # списка, и запрошенное количество из-за этого не добиралось (просили 40 — получали 37).
    if ($null -eq $ExcludeKeys) { $ExcludeKeys = @{} }
    $stats = @{ Attempts = 0; ByLength = 0; ByFormat = 0; ByExcludedToken = 0; ByDuplicate = 0; ByAlreadyUsed = 0 }
    $bases = New-Object System.Collections.ArrayList
    foreach ($group in $SelectedWordCategories) {
        if ($script:MeaningGroups.ContainsKey($group)) {
            foreach ($word in $script:MeaningGroups[$group]) {
                $seed = Get-SeedForWord -Word $word -FallbackMeaning $group
                [void]$bases.Add([pscustomobject]@{Word=[string]$seed.Word; Meaning=[string]$seed.Meaning; Category=$group})
            }
        }
    }
    # Свои слова разбиваются и по разделителям, и по пробелам: раньше «boom square»
    # склеивалось Convert-ToNickToken в один токен BoomSquare и считалось одним словом.
    foreach ($rawWord in ($CustomWords -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $word = Convert-ToNickToken $rawWord
        if ($word.Length -gt 0) { [void]$bases.Add([pscustomobject]@{Word=$word; Meaning='ваше ключевое слово'; Category='Свои слова'}) }
    }
    foreach ($rawWord in ($CustomTheme -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $word = Convert-ToNickToken $rawWord
        if ($word.Length -gt 0) { [void]$bases.Add([pscustomobject]@{Word=$word; Meaning='ваша тематика'; Category='Своя тематика'}) }
    }

    $modifiers = @($script:Modifiers)
    if ($Style -and $Style -ne '— без стиля —' -and $script:StyleWords.ContainsKey($Style)) {
        foreach ($word in $script:StyleWords[$Style]) {
            $seed = Get-SeedForWord -Word $word -FallbackMeaning ("стиль: {0}" -f $Style)
            $modifiers += [pscustomobject]@{Word=[string]$seed.Word; Meaning=[string]$seed.Meaning}
        }
    }
    # Стиль «Двусловный» обязан давать два слова: раньше он лишь добавлял модификаторы,
    # и при снятой галочке «Два осмысленных слова» выдавал однословные ники.
    if ($Style -eq 'Двусловный') { $TwoWords = $true }
    if (-not $OneWord -and -not $TwoWords) { $OneWord = $true }

    $prefixClean = [regex]::Replace([string]$Prefix, '[^A-Za-z0-9_.-]', '')
    $suffixClean = [regex]::Replace([string]$Suffix, '[^A-Za-z0-9_.-]', '')
    $maximum = $MaxLength
    if ($OnlyShort) { $maximum = [Math]::Min($maximum, 12) }

    $result = New-Object System.Collections.ArrayList
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    # Счётчики ведутся в hashtable, а не в обычных переменных: scriptblock видит
    # переменные функции только на чтение, а hashtable — ссылочный тип, поэтому
    # изменения внутри блоков заполнения сохраняются.
    # Флаги исчерпания нужны, чтобы финальный добор не запускал повторно источник,
    # который уже просмотрен целиком: повтор ничего не добавляет, но раздувает
    # счётчики отсева в диагностике.
    $counters = @{ Single = 0; Pair = 0; Number = 0; SingleExhausted = $false; PairExhausted = $false }

    # Единая точка приёма кандидата: все фильтры применяются здесь, поэтому статистика
    # отсева и итоговое количество согласованы, а не расходятся, как было раньше.
    $tryAccept = {
        param([string]$RawName, [string]$Meaning, [string]$Category, [string]$Structure, [switch]$SkipAffixes)
        $stats['Attempts'] = $stats['Attempts'] + 1
        $name = $RawName
        if (-not $SkipAffixes) {
            if ($prefixClean) { $name = $prefixClean + $name }
            if ($suffixClean) { $name = $name + $suffixClean }
            $name = [regex]::Replace($name, '[^A-Za-z0-9_.-]', '')
        }
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

    # Блок заполнения одиночными словами: набор конечен, поэтому перебираем перемешанные
    # базы и останавливаемся, когда общий результат достиг целевого значения.
    $fillSingle = {
        param([int]$StopAtTotal)
        if ($bases.Count -lt 1) { $counters['SingleExhausted'] = $true; return }
        if ($result.Count -ge $StopAtTotal) { return }
        foreach ($base in (Get-ShuffledArray -Items $bases.ToArray())) {
            if ($result.Count -ge $StopAtTotal) { break }
            $word = [regex]::Replace([string]$base.Word, '[^A-Za-z0-9]', '')
            if ($word.Length -lt 1) { continue }
            if (& $tryAccept $word ([string]$base.Meaning) ([string]$base.Category) 'Одно слово') {
                $counters['Single'] = $counters['Single'] + 1
            }
        }
        # Набор баз конечен: если он просмотрен целиком, а цель не достигнута, источник
        # исчерпан. Повторный проход дал бы только отказы по повторам и раздул бы
        # статистику отсева, которая показывается пользователю как причина нехватки.
        if ($result.Count -lt $StopAtTotal) { $counters['SingleExhausted'] = $true }
    }

    # Блок заполнения парами слов. Комбинации не материализуются: раньше создавались все
    # пары «база × модификатор» (десятки тысяч объектов), и только потом брались первые
    # Count. Теперь пара выбирается случайно; предел по числу неудач подряд означает,
    # что пространство имён при текущих фильтрах исчерпано.
    $fillPairs = {
        param([int]$StopAtTotal)
        if ($bases.Count -lt 1 -or $modifiers.Count -lt 1) { $counters['PairExhausted'] = $true; return }
        if ($result.Count -ge $StopAtTotal) { return }
        $joiner = ''
        if ($UseUnderscore) { $joiner = '_' }
        $baseArray = @($bases.ToArray())
        $modArray = @($modifiers)
        $budget = [Math]::Max(400, ($StopAtTotal - $result.Count) * 40)
        $failureLimit = 400
        $consecutiveFailures = 0
        $attempts = 0
        while ($result.Count -lt $StopAtTotal -and $attempts -lt $budget -and $consecutiveFailures -lt $failureLimit) {
            $attempts++
            $base = $baseArray[(Get-Random -Minimum 0 -Maximum $baseArray.Length)]
            $mod = $modArray[(Get-Random -Minimum 0 -Maximum $modArray.Length)]
            $word = [regex]::Replace([string]$base.Word, '[^A-Za-z0-9]', '')
            $modWord = [regex]::Replace([string]$mod.Word, '[^A-Za-z0-9]', '')
            if ($word.Length -lt 1 -or $modWord.Length -lt 1 -or $modWord -ieq $word) { $consecutiveFailures++; continue }
            if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) {
                $pairName = $word + $joiner + $modWord
                $pairMeaning = ('{0} + {1}' -f [string]$base.Meaning, [string]$mod.Meaning)
            } else {
                $pairName = $modWord + $joiner + $word
                $pairMeaning = ('{0} + {1}' -f [string]$mod.Meaning, [string]$base.Meaning)
            }
            if (& $tryAccept $pairName $pairMeaning 'Двусловные' 'Два слова') {
                $consecutiveFailures = 0
                $counters['Pair'] = $counters['Pair'] + 1
            } else { $consecutiveFailures++ }
        }
        # Выход из цикла по пределу неудач подряд или по бюджету попыток означает, что
        # пространство пар при текущих фильтрах фактически исчерпано.
        if ($result.Count -lt $StopAtTotal) { $counters['PairExhausted'] = $true }
    }

    # Квоты между источниками. Раньше этапы шли строго последовательно и одиночные слова
    # заполняли весь запрос, поэтому при отмеченной галочке «Два осмысленных слова» пары
    # не создавались вовсе: по умолчанию отмечено шесть категорий, это около 189 базовых
    # слов, а запрос по умолчанию — 40 ников.
    $numberTarget = 0
    if ($UseNumbers) { $numberTarget = [Math]::Min([int][Math]::Ceiling($Count * 0.3), [Math]::Max(0, $Count - 1)) }
    $wordBudget = $Count - $numberTarget
    if ($wordBudget -lt 1) { $wordBudget = 1 }
    if ($OneWord -and $TwoWords) { $singleTarget = [int][Math]::Ceiling($wordBudget / 2) }
    elseif ($OneWord) { $singleTarget = $wordBudget }
    else { $singleTarget = 0 }

    if ($OneWord) { & $fillSingle $singleTarget }
    if ($TwoWords) { & $fillPairs $wordBudget }

    # Цифры — часть квоты, а не добор при нехватке. Раньше вариант с цифрами создавался
    # только если количество не набиралось, поэтому при большом пространстве имён
    # галочка «Использовать цифры» не давала ничего.
    if ($numberTarget -gt 0 -and $result.Count -gt 0) {
        # Снимок списка делается один раз: иначе числовые варианты наслаивались бы
        # друг на друга (Nova -> Nova42 -> Nova4217), и каждый проход стоил бы O(n).
        $numberSources = @(Get-ShuffledArray -Items $result.ToArray())
        $numberBudget = [Math]::Max(200, $numberTarget * 20)
        $numberAttempts = 0
        $sourceIndex = 0
        while ($counters['Number'] -lt $numberTarget -and $result.Count -lt $Count -and $numberAttempts -lt $numberBudget) {
            $numberAttempts++
            if ($sourceIndex -ge $numberSources.Length) { $sourceIndex = 0 }
            $entry = $numberSources[$sourceIndex]
            $sourceIndex++
            $baseName = [string]$entry.Name
            $number = Get-Random -Minimum 2 -Maximum 10000
            $withNumber = $baseName + $number
            if ($withNumber.Length -gt $maximum) { continue }
            # Префикс и суффикс уже входят в имя, поэтому повторно не подставляются.
            $meaningWithNumber = ([string]$entry.Meaning) + (' + число {0}' -f $number)
            if (& $tryAccept $withNumber $meaningWithNumber ([string]$entry.Category) ([string]$entry.Structure) -SkipAffixes) {
                $counters['Number'] = $counters['Number'] + 1
            }
        }
    }

    # Финальный добор: если источник исчерпан или на цифры не хватило места,
    # остаток закрывается другим источником, чтобы количество совпало с запрошенным.
    # Исчерпанные источники повторно не запускаются: повторный проход ничего не даёт,
    # но увеличивает счётчики отсева, которые показываются пользователю как причина
    # нехватки, и превращает честную диагностику в завышенную.
    if ($result.Count -lt $Count) {
        if ($TwoWords -and -not $counters['PairExhausted']) { & $fillPairs $Count }
        if ($result.Count -lt $Count -and $OneWord -and -not $counters['SingleExhausted']) { & $fillSingle $Count }
    }

    $stats['Single'] = $counters['Single']
    $stats['Pair'] = $counters['Pair']
    $stats['Number'] = $counters['Number']
    $script:GenerationStats = $stats
    if ($result.Count -eq 0) { return @() }
    $shuffled = @(Get-ShuffledArray -Items $result.ToArray())
    $take = [Math]::Min($Count, $shuffled.Count)
    return @($shuffled | Select-Object -First $take)
}

$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = ('Universal Username Finder v{0}' -f $script:AppVersion)
$script:Form.StartPosition = 'CenterScreen'
# Размер окна и его минимум подгоняются под рабочую область экрана.
# Фиксированный минимум 1240x910 на ноутбуках с экраном 1366x768 не помещался по высоте:
# нижняя часть интерфейса оказывалась за пределами экрана, а уменьшить окно было нельзя.
# На больших экранах значения остаются прежними — меняется только поведение на тесных.
$designWindowSize = New-Object System.Drawing.Size(1480, 960)
$designMinimumSize = New-Object System.Drawing.Size(1240, 910)
try {
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $minimumWidth = [Math]::Min($designMinimumSize.Width, [Math]::Max(760, $workingArea.Width - 32))
    $minimumHeight = [Math]::Min($designMinimumSize.Height, [Math]::Max(520, $workingArea.Height - 32))
    $windowWidth = [Math]::Max($minimumWidth, [Math]::Min($designWindowSize.Width, $workingArea.Width))
    $windowHeight = [Math]::Max($minimumHeight, [Math]::Min($designWindowSize.Height, $workingArea.Height))
} catch {
    # Если экран определить не удалось, остаются проектные значения.
    $minimumWidth = $designMinimumSize.Width
    $minimumHeight = $designMinimumSize.Height
    $windowWidth = $designWindowSize.Width
    $windowHeight = $designWindowSize.Height
}
# MinimumSize задаётся до Size: иначе WinForms поднимет размер окна обратно до минимума.
$script:Form.MinimumSize = New-Object System.Drawing.Size($minimumWidth, $minimumHeight)
$script:Form.Size = New-Object System.Drawing.Size($windowWidth, $windowHeight)
$script:Form.BackColor = [System.Drawing.Color]::FromArgb(15, 19, 27)
$script:Form.ForeColor = [System.Drawing.Color]::FromArgb(235, 240, 248)
$script:Form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.Size = New-Object System.Drawing.Size(1480, 76)
$header.Anchor = 'Top, Left, Right'
$header.BackColor = [System.Drawing.Color]::FromArgb(23, 30, 42)
$script:Form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = ('UNIVERSAL USERNAME FINDER  •  v{0}' -f $script:AppVersion)
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 19, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(112, 164, 255)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(22, 12)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Автоматическая генерация и проверка имён для популярных платформ'
$subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(177, 188, 207)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(25, 48)
$header.Controls.Add($subtitle)

$script:ApiDocsButton = New-Object System.Windows.Forms.Button
$script:ApiDocsButton.Text = 'Помощь'
$script:ApiDocsButton.Location = New-Object System.Drawing.Point(1000, 19)
$script:ApiDocsButton.Size = New-Object System.Drawing.Size(100, 38)
$script:ApiDocsButton.Anchor = 'Top, Right'
$script:ApiDocsButton.FlatStyle = 'Flat'
$script:ApiDocsButton.FlatAppearance.BorderSize = 0
$script:ApiDocsButton.BackColor = [System.Drawing.Color]::FromArgb(42, 52, 70)
$script:ApiDocsButton.ForeColor = [System.Drawing.Color]::White
$header.Controls.Add($script:ApiDocsButton)
$script:HistoryButton = New-Object System.Windows.Forms.Button
$script:HistoryButton.Text = 'Свободные ники'
$script:HistoryButton.Location = New-Object System.Drawing.Point(1110, 19)
$script:HistoryButton.Size = New-Object System.Drawing.Size(150, 38)
$script:HistoryButton.Anchor = 'Top, Right'
$script:HistoryButton.FlatStyle = 'Flat'
$script:HistoryButton.FlatAppearance.BorderSize = 0
$script:HistoryButton.BackColor = [System.Drawing.Color]::FromArgb(42, 52, 70)
$script:HistoryButton.ForeColor = [System.Drawing.Color]::White
$header.Controls.Add($script:HistoryButton)
$script:AccountButton = New-Object System.Windows.Forms.Button
$script:AccountButton.Text = 'Пароль / регистрация'
$script:AccountButton.Location = New-Object System.Drawing.Point(1270, 17)
$script:AccountButton.Size = New-Object System.Drawing.Size(167, 42)
$script:AccountButton.Anchor = 'Top, Right'
$script:AccountButton.FlatStyle = 'Flat'
$script:AccountButton.FlatAppearance.BorderSize = 0
$script:AccountButton.BackColor = [System.Drawing.Color]::FromArgb(67, 123, 235)
$script:AccountButton.ForeColor = [System.Drawing.Color]::White
$script:AccountButton.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9.5, [System.Drawing.FontStyle]::Bold)
$script:AccountButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$header.Controls.Add($script:AccountButton)

$left = New-Object System.Windows.Forms.Panel
$left.Location = New-Object System.Drawing.Point(14, 88)
$left.Size = New-Object System.Drawing.Size(390, 790)
$left.Anchor = 'Top, Bottom, Left'
$left.BackColor = [System.Drawing.Color]::FromArgb(23, 30, 42)
$left.AutoScroll = $true
$script:Form.Controls.Add($left)

function Add-UiLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width=350, [int]$Height=22, [System.Windows.Forms.Control]$Parent=$left)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, $Height)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 228)
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
        $button.BackColor = [System.Drawing.Color]::FromArgb(93, 73, 222)
        $button.ForeColor = [System.Drawing.Color]::White
    } else {
        $button.BackColor = [System.Drawing.Color]::FromArgb(42, 52, 70)
        $button.ForeColor = [System.Drawing.Color]::FromArgb(235, 240, 248)
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
        # Подсказка больше не считается значением поля: при получении фокуса она
        # стирается, при потере фокуса и пустом поле возвращается. Раньше строка
        # «Pixel, Void, Storm» просто лежала в .Text, и если пользователь дописывал
        # свои слова вместо полной замены, Pixel и Void молча становились базовыми
        # словами и участвовали в генерации.
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
    # Возвращает текст поля, но пустую строку, если в поле осталась подсказка.
    # Заменяет сравнение с литералом «Pixel, Void, Storm» в обработчиках.
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
    $box.ForeColor = [System.Drawing.Color]::White
    $left.Controls.Add($box)
    return $box
}

Add-UiLabel 'ЕДИНЫЙ ВЫБОР КАТЕГОРИЙ НИКНЕЙМОВ' 14 12 355 22 | Out-Null
$script:CategoryList = New-Object System.Windows.Forms.CheckedListBox
$script:CategoryList.Location = New-Object System.Drawing.Point(14, 36)
$script:CategoryList.Size = New-Object System.Drawing.Size(350, 340)
$script:CategoryList.CheckOnClick = $true
$script:CategoryList.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:CategoryList.ForeColor = [System.Drawing.Color]::FromArgb(225,232,242)
$script:CategoryList.BorderStyle = 'FixedSingle'
[void]$script:CategoryList.Items.AddRange([object[]]@('Цельные слова','Короткие','Космос','Свет и энергия','Природа','Мифология','Эмоции','Скорость','Абстрактное','Эстетика'))
foreach ($category in @('Цельные слова','Короткие','Космос','Природа','Мифология','Эстетика')) {
    $index = $script:CategoryList.Items.IndexOf($category)
    if ($index -ge 0) { $script:CategoryList.SetItemChecked($index,$true) }
}
$left.Controls.Add($script:CategoryList)

Add-UiLabel 'Игровой стиль' 14 392 150 22 | Out-Null
$script:StyleBox = New-Object System.Windows.Forms.ComboBox
$script:StyleBox.Location = New-Object System.Drawing.Point(14,416)
$script:StyleBox.Size = New-Object System.Drawing.Size(350,27)
$script:StyleBox.DropDownStyle = 'DropDownList'
$script:StyleBox.BackColor = [System.Drawing.Color]::FromArgb(32,41,56)
$script:StyleBox.ForeColor = [System.Drawing.Color]::White
[void]$script:StyleBox.Items.AddRange([object[]]@('Минималистичный','Киберспортивный','Футуристический','Тёмный','Эстетичный','Редкий','Короткий','Двусловный','— без стиля —'))
$script:StyleBox.SelectedItem = 'Футуристический'
$left.Controls.Add($script:StyleBox)

Add-UiLabel 'Свои слова через запятую' 14 450 350 22 | Out-Null
$script:CustomBox = New-TextBox 14 473 350 27 'Pixel, Void, Storm'
Add-UiLabel 'Своя тематика (например: океан, киберпанк)' 14 506 350 22 | Out-Null
$script:ThemeBox = New-TextBox 14 529 350 27 ''
Add-UiLabel 'Ручные ники для проверки (каждый с новой строки или через запятую)' 14 562 350 35 | Out-Null
$script:ManualNickBox = New-TextBox 14 597 350 60 ''
$script:ManualNickBox.Multiline = $true
$script:ManualNickBox.ScrollBars = 'Vertical'

Add-UiLabel 'НАСТРОЙКИ ГЕНЕРАЦИИ' 14 666 350 22 | Out-Null
Add-UiLabel 'Количество' 14 690 90 18 | Out-Null
$script:CountBox = New-NumberBox 14 709 90 5 2000 40
Add-UiLabel 'Мин. длина' 120 690 90 18 | Out-Null
$script:MinLengthBox = New-NumberBox 120 709 80 1 39 3
Add-UiLabel 'Макс. длина' 216 690 100 18 | Out-Null
$script:MaxLengthBox = New-NumberBox 216 709 80 1 39 16
Add-UiLabel 'Префикс' 14 741 155 18 | Out-Null
$script:PrefixBox = New-TextBox 14 760 165 27 ''
Add-UiLabel 'Суффикс' 194 741 155 18 | Out-Null
$script:SuffixBox = New-TextBox 194 760 170 27 ''

$script:NumbersCheck = New-CheckBox 'Использовать цифры' 14 795 170 $false
$script:UnderscoreCheck = New-CheckBox 'Разделитель _' 194 795 170 $false
$script:OneWordCheck = New-CheckBox 'Однословные ники' 14 820 180 $true
$script:TwoWordsCheck = New-CheckBox 'Два осмысленных слова' 194 820 170 $true
$script:ShortOnlyCheck = New-CheckBox 'Только короткие (≤12)' 14 845 180 $false
$script:ExcludeCheckedCheck = New-CheckBox 'Исключать проверенные' 194 845 170 $true
$script:OnlyFreeCheck = New-CheckBox 'Показывать только свободные' 14 870 220 $false
Add-UiLabel 'Исключить слова/части ника (пример: xxx, test, 123)' 14 897 350 20 | Out-Null
$script:ExcludeBox = New-TextBox 14 918 350 27 ''
Add-UiLabel 'Пауза (мс)   •   Тайм-аут (мс)' 14 950 350 20 | Out-Null
# Минимальная пауза ограничена снизу (1200 мс): слишком частые последовательные запросы
# к одной платформе приводят к HTTP 429, временным блокировкам по IP и нарушают правила
# использования сервисов. Предел задан в самом контроле, поэтому он виден пользователю.
# Пауза адаптивная: значение в этом поле — стартовая точка, а не жёсткая задержка.
# Воркер увеличивает её при HTTP 429/403 (с учётом Retry-After) и постепенно снижает
# после серии успешных ответов, поэтому средний темп выше прежнего фиксированного порога,
# а защита от ограничения частоты и блокировки IP сохраняется.
$script:DelayBox = New-NumberBox 14 971 145 500 15000 700
$script:TimeoutBox = New-NumberBox 194 971 145 1000 30000 8000
$script:ThreadsLabel = Add-UiLabel 'Потоки: 1 • пауза адаптивная: старт 700 мс, рост при HTTP 429, снижение после успехов' 14 1002 350 30

$script:GenerateButton = Add-UiButton '✨ Сгенерировать и проверить' 14 1040 350 $true 37
$script:StartButton = Add-UiButton '▶ Найти свободные' 14 1083 350 $true 37
$script:StartButton.Visible = $false
$script:StopButton = Add-UiButton '■ Остановить проверку' 14 1083 350 $false 35
$script:StopButton.Enabled = $false
$script:RetryButton = Add-UiButton '↻ Повторить ошибки' 14 1123 170 $false 33
$script:ClearButton = Add-UiButton 'Очистить результаты' 194 1123 170 $false 33
$script:SaveButton = Add-UiButton '⬇ TXT доступные/возможные' 14 1163 170 $false 33
$script:CsvButton = Add-UiButton '⬇ CSV все результаты' 194 1163 170 $false 33
$script:CopyButton = Add-UiButton 'Копировать доступные/возможные' 14 1203 350 $false 33

$right = New-Object System.Windows.Forms.Panel
$right.Location = New-Object System.Drawing.Point(418, 88)
$right.Size = New-Object System.Drawing.Size(1040, 790)
$right.Anchor = 'Top, Bottom, Left, Right'
$right.BackColor = [System.Drawing.Color]::FromArgb(23, 30, 42)
$script:Form.Controls.Add($right)

$script:StatTotal = New-Object System.Windows.Forms.Label
$script:StatFree = New-Object System.Windows.Forms.Label
$script:StatTaken = New-Object System.Windows.Forms.Label
$script:StatInvalid = New-Object System.Windows.Forms.Label
$script:StatErrors = New-Object System.Windows.Forms.Label
$script:StatChecked = New-Object System.Windows.Forms.Label
$statLabels = @($script:StatTotal,$script:StatChecked,$script:StatFree,$script:StatTaken,$script:StatInvalid,$script:StatErrors)
$statTexts = @('Всего: 0','Проверено: 0','Свободно: 0','Занято: 0','Недопустимо: 0','Ошибки: 0')
$statColors = @([System.Drawing.Color]::White,[System.Drawing.Color]::FromArgb(200,210,226),[System.Drawing.Color]::FromArgb(99,222,151),[System.Drawing.Color]::FromArgb(245,120,120),[System.Drawing.Color]::FromArgb(186,194,207),[System.Drawing.Color]::FromArgb(255,190,92))
for ($i=0; $i -lt $statLabels.Count; $i++) {
    $statLabels[$i].Text = $statTexts[$i]
    $statLabels[$i].Location = New-Object System.Drawing.Point((12 + 168*$i), 10)
    $statLabels[$i].Size = New-Object System.Drawing.Size(160,26)
    $statLabels[$i].BackColor = [System.Drawing.Color]::FromArgb(31,40,56)
    $statLabels[$i].ForeColor = $statColors[$i]
    $statLabels[$i].TextAlign = 'MiddleCenter'
    $statLabels[$i].Font = New-Object System.Drawing.Font('Segoe UI Semibold',8.5,[System.Drawing.FontStyle]::Bold)
    $right.Controls.Add($statLabels[$i])
}

$script:ProgressCaption = New-Object System.Windows.Forms.Label
$script:ProgressCaption.Text = 'Прогресс проверки'
$script:ProgressCaption.Location = New-Object System.Drawing.Point(14,40)
$script:ProgressCaption.Size = New-Object System.Drawing.Size(500,18)
$script:ProgressCaption.ForeColor = [System.Drawing.Color]::FromArgb(149,164,187)
$right.Controls.Add($script:ProgressCaption)
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(14,59)
$script:ProgressBar.Size = New-Object System.Drawing.Size(1008,10)
$script:ProgressBar.Minimum = 0
$script:ProgressBar.Maximum = 100
$script:ProgressBar.Value = 0
$right.Controls.Add($script:ProgressBar)

$script:StatusFilterBox = New-Object System.Windows.Forms.ComboBox
$script:StatusFilterBox.Location = New-Object System.Drawing.Point(14,78)
$script:StatusFilterBox.Size = New-Object System.Drawing.Size(160,27)
$script:StatusFilterBox.DropDownStyle = 'DropDownList'
$script:StatusFilterBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:StatusFilterBox.ForeColor = [System.Drawing.Color]::White
[void]$script:StatusFilterBox.Items.AddRange([object[]]@('Все статусы','Свободен','Вероятно свободен','Занят','Недопустимый','Не подтверждено','Ошибка сети','Ожидает','Проверяется'))
$script:StatusFilterBox.SelectedIndex = 0
$right.Controls.Add($script:StatusFilterBox)
$script:SortBox = New-Object System.Windows.Forms.ComboBox
$script:SortBox.Location = New-Object System.Drawing.Point(184,78)
$script:SortBox.Size = New-Object System.Drawing.Size(150,27)
$script:SortBox.DropDownStyle = 'DropDownList'
$script:SortBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:SortBox.ForeColor = [System.Drawing.Color]::White
[void]$script:SortBox.Items.AddRange([object[]]@('Ник','Статус','Категория','Структура','Короткие сначала','Свободные первыми'))
$script:SortBox.SelectedIndex = 0
$right.Controls.Add($script:SortBox)
$script:SearchBox = New-Object System.Windows.Forms.TextBox
$script:SearchBox.Location = New-Object System.Drawing.Point(344,78)
$script:SearchBox.Size = New-Object System.Drawing.Size(678,27)
$script:SearchBox.Anchor = 'Top, Left, Right'
$script:SearchBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:SearchBox.ForeColor = [System.Drawing.Color]::White
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
$script:PlatformBox.ForeColor = [System.Drawing.Color]::White
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
$script:OpenPlatformButton.ForeColor = [System.Drawing.Color]::White
$right.Controls.Add($script:OpenPlatformButton)
$platformNote = New-Object System.Windows.Forms.Label
$platformNote.Text = 'Для каждой платформы используется отдельный способ проверки.'
$platformNote.Location = New-Object System.Drawing.Point(550, 112)
$platformNote.Size = New-Object System.Drawing.Size(470, 27)
$platformNote.ForeColor = [System.Drawing.Color]::FromArgb(149,164,187)
$platformNote.TextAlign = 'MiddleLeft'
$right.Controls.Add($platformNote)

$script:Grid = New-Object System.Windows.Forms.DataGridView
$script:Grid.Location = New-Object System.Drawing.Point(14,146)
$script:Grid.Size = New-Object System.Drawing.Size(1008,431)
$script:Grid.Anchor = 'Top, Bottom, Left, Right'
$script:Grid.BackgroundColor = [System.Drawing.Color]::FromArgb(17,23,32)
$script:Grid.BorderStyle = 'None'
$script:Grid.GridColor = [System.Drawing.Color]::FromArgb(42,52,70)
$script:Grid.EnableHeadersVisualStyles = $false
$script:Grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(35,46,63)
$script:Grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::White
$script:Grid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font('Segoe UI Semibold',8.5,[System.Drawing.FontStyle]::Bold)
$script:Grid.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(20,27,38)
$script:Grid.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(225,232,242)
$script:Grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(50,75,112)
$script:Grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
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
# Колонка «СТРУКТУРА» показывает, из скольких слов состоит ник. Без неё склейка двух
# слов (BoomSquare) попадала в категорию «Цельные слова» и выглядела одним словом:
# при снятой галочке «Разделитель _» слова соединяются без разделителя.
[void]$script:Grid.Columns.Add('Structure','СТРУКТУРА')
[void]$script:Grid.Columns.Add('Meaning','ЗНАЧЕНИЕ')
[void]$script:Grid.Columns.Add('Time','ВРЕМЯ')
[void]$script:Grid.Columns.Add('Reason','ПРИЧИНА')
$script:Grid.Columns['Nick'].FillWeight = 16
$script:Grid.Columns['Platform'].FillWeight = 12
$script:Grid.Columns['Status'].FillWeight = 13
$script:Grid.Columns['Category'].FillWeight = 15
$script:Grid.Columns['Structure'].FillWeight = 12
$script:Grid.Columns['Meaning'].FillWeight = 17
$script:Grid.Columns['Time'].FillWeight = 8
$script:Grid.Columns['Reason'].FillWeight = 20
$script:Grid.RowTemplate.Height = 27
# Двойная буферизация убирает мерцание при частой перерисовке таблицы.
# Свойство защищённое, поэтому включаем его через отражение; сбой не критичен.
try {
    $doubleBuffered = $script:Grid.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
    if ($doubleBuffered) { $doubleBuffered.SetValue($script:Grid, $true, $null) }
} catch { }
$script:Grid.add_CellDoubleClick({
    param($sender,$e)
    if ($e.RowIndex -ge 0) {
        $n = [string]$script:Grid.Rows[$e.RowIndex].Cells['Nick'].Value
        $st = [string]$script:Grid.Rows[$e.RowIndex].Cells['Status'].Value
        if (($st -eq 'Свободен' -or $st -eq 'Вероятно свободен') -and $n) {
            [System.Windows.Forms.Clipboard]::SetText($n)
            Add-Diagnostic "Скопирован ник: $n (статус: $st)"
        }
    }
})
$right.Controls.Add($script:Grid)

$diagnosticHeader = New-Object System.Windows.Forms.Label
$diagnosticHeader.Text = 'ДИАГНОСТИКА И ЖУРНАЛ'
$diagnosticHeader.Location = New-Object System.Drawing.Point(14,584)
$diagnosticHeader.Size = New-Object System.Drawing.Size(250,20)
$diagnosticHeader.Font = New-Object System.Drawing.Font('Segoe UI Semibold',8.5,[System.Drawing.FontStyle]::Bold)
$diagnosticHeader.ForeColor = [System.Drawing.Color]::FromArgb(194,207,226)
$right.Controls.Add($diagnosticHeader)
$script:DiagnosticBox = New-Object System.Windows.Forms.TextBox
$script:DiagnosticBox.Location = New-Object System.Drawing.Point(14,606)
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
$script:CopyLogButton = Add-UiButton 'Копировать журнал' 14 708 180 $false 28 $right
$script:ClearLogButton = Add-UiButton 'Очистить журнал' 202 708 170 $false 28 $right
$script:SummaryLabel = New-Object System.Windows.Forms.Label
$script:SummaryLabel.Text = 'Готово к генерации'
$script:SummaryLabel.Location = New-Object System.Drawing.Point(390,708)
$script:SummaryLabel.Size = New-Object System.Drawing.Size(632,28)
$script:SummaryLabel.Anchor = 'Bottom, Left, Right'
$script:SummaryLabel.ForeColor = [System.Drawing.Color]::FromArgb(149,164,187)
$script:SummaryLabel.TextAlign = 'MiddleRight'
$right.Controls.Add($script:SummaryLabel)
$footer = New-Object System.Windows.Forms.Label
$footer.Text = '⚠  Доступность имени зависит от платформы. «Вероятно свободен» означает, что профиль не найден, но регистрация должна подтвердить доступность.'
$footer.Location = New-Object System.Drawing.Point(14,744)
$footer.Size = New-Object System.Drawing.Size(1008,34)
$footer.Anchor = 'Bottom, Left, Right'
$footer.ForeColor = [System.Drawing.Color]::FromArgb(20,20,24)
$footer.BackColor = [System.Drawing.Color]::FromArgb(248,185,65)
$footer.Font = New-Object System.Drawing.Font('Segoe UI',9.5,[System.Drawing.FontStyle]::Bold)
$footer.TextAlign = 'MiddleLeft'
$footer.Padding = New-Object System.Windows.Forms.Padding(8,0,4,0)
$right.Controls.Add($footer)

$script:AvailableNames = New-Object System.Collections.Generic.List[string]
$script:RobloxAvailableNames = New-Object System.Collections.Generic.List[string]
$script:CheckQueue = $null
$script:Cancellation = $null
$script:WorkerPowerShell = $null
$script:WorkerRunspace = $null
$script:AsyncHandle = $null
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

function New-SecurePassword {
    param([ValidateRange(16,32)][int]$Length = 20)
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghjkmnpqrstuvwxyz'
    $digits = '23456789'
    $all = $upper + $lower + $digits
    $characters = New-Object 'System.Collections.Generic.List[char]'
    [void]$characters.Add([char]$upper[(Get-CryptoRandomIndex $upper.Length)])
    [void]$characters.Add([char]$lower[(Get-CryptoRandomIndex $lower.Length)])
    [void]$characters.Add([char]$digits[(Get-CryptoRandomIndex $digits.Length)])
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

function Open-AccountTools {
    $script:AccountForm = New-Object System.Windows.Forms.Form
    $script:AccountForm.Text = 'Universal Username Finder — регистрация Roblox'
    $script:AccountForm.StartPosition = 'CenterParent'
    $script:AccountForm.Size = New-Object System.Drawing.Size(780, 610)
    $script:AccountForm.MinimumSize = New-Object System.Drawing.Size(780, 610)
    $script:AccountForm.MaximizeBox = $false
    $script:AccountForm.MinimizeBox = $false
    $script:AccountForm.BackColor = [System.Drawing.Color]::FromArgb(15, 19, 27)
    $script:AccountForm.ForeColor = [System.Drawing.Color]::FromArgb(235, 240, 248)
    $script:AccountForm.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(14, 14)
    $tabs.Size = New-Object System.Drawing.Size(738, 535)
    $tabs.Anchor = 'Top, Bottom, Left, Right'
    $prepareTab = New-Object System.Windows.Forms.TabPage
    $prepareTab.Text = 'Пароль и регистрация'
    $prepareTab.BackColor = [System.Drawing.Color]::FromArgb(23, 30, 42)
    $prepareTab.ForeColor = [System.Drawing.Color]::FromArgb(235, 240, 248)
    $vaultTab = New-Object System.Windows.Forms.TabPage
    $vaultTab.Text = 'Сохранённые аккаунты'
    $vaultTab.BackColor = [System.Drawing.Color]::FromArgb(23, 30, 42)
    $vaultTab.ForeColor = [System.Drawing.Color]::FromArgb(235, 240, 248)
    [void]$tabs.TabPages.Add($prepareTab)
    [void]$tabs.TabPages.Add($vaultTab)
    $script:AccountTabs = $tabs
    $script:AccountVaultTab = $vaultTab
    $script:AccountForm.Controls.Add($tabs)

    $intro = New-Object System.Windows.Forms.Label
    $intro.Text = 'Выбери ник из списка или введи свой. Пароль генерируется локально; программа не отправляет его Roblox.'
    $intro.Location = New-Object System.Drawing.Point(18, 16)
    $intro.Size = New-Object System.Drawing.Size(680, 38)
    $intro.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 228)
    $prepareTab.Controls.Add($intro)

    $usernameLabel = New-Object System.Windows.Forms.Label
    $usernameLabel.Text = 'Никнейм Roblox'
    $usernameLabel.Location = New-Object System.Drawing.Point(18, 60)
    $usernameLabel.Size = New-Object System.Drawing.Size(440, 22)
    $usernameLabel.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 228)
    $prepareTab.Controls.Add($usernameLabel)

    $script:AccountUsernameBox = New-Object System.Windows.Forms.ComboBox
    $script:AccountUsernameBox.Location = New-Object System.Drawing.Point(18, 84)
    $script:AccountUsernameBox.Size = New-Object System.Drawing.Size(445, 29)
    $script:AccountUsernameBox.DropDownStyle = 'DropDown'
    $script:AccountUsernameBox.AutoCompleteMode = 'SuggestAppend'
    $script:AccountUsernameBox.AutoCompleteSource = 'ListItems'
    $script:AccountUsernameBox.BackColor = [System.Drawing.Color]::FromArgb(32, 41, 56)
    $script:AccountUsernameBox.ForeColor = [System.Drawing.Color]::White
    $prepareTab.Controls.Add($script:AccountUsernameBox)

    $refreshNicks = New-Object System.Windows.Forms.Button
    $refreshNicks.Text = 'Обновить список ников'
    $refreshNicks.Location = New-Object System.Drawing.Point(475, 82)
    $refreshNicks.Size = New-Object System.Drawing.Size(220, 32)
    $refreshNicks.FlatStyle = 'Flat'
    $refreshNicks.FlatAppearance.BorderSize = 0
    $refreshNicks.BackColor = [System.Drawing.Color]::FromArgb(42, 52, 70)
    $refreshNicks.ForeColor = [System.Drawing.Color]::White
    $prepareTab.Controls.Add($refreshNicks)

    $passwordLabel = New-Object System.Windows.Forms.Label
    $passwordLabel.Text = 'Случайный пароль (латинские буквы и цифры)'
    $passwordLabel.Location = New-Object System.Drawing.Point(18, 129)
    $passwordLabel.Size = New-Object System.Drawing.Size(440, 22)
    $passwordLabel.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 228)
    $prepareTab.Controls.Add($passwordLabel)

    $script:PasswordLengthBox = New-Object System.Windows.Forms.NumericUpDown
    $script:PasswordLengthBox.Location = New-Object System.Drawing.Point(18, 155)
    $script:PasswordLengthBox.Size = New-Object System.Drawing.Size(70, 28)
    $script:PasswordLengthBox.Minimum = 16
    $script:PasswordLengthBox.Maximum = 32
    $script:PasswordLengthBox.Value = 20
    $script:PasswordLengthBox.BackColor = [System.Drawing.Color]::FromArgb(32, 41, 56)
    $script:PasswordLengthBox.ForeColor = [System.Drawing.Color]::White
    $prepareTab.Controls.Add($script:PasswordLengthBox)

    $generateButton = New-Object System.Windows.Forms.Button
    $generateButton.Text = 'Сгенерировать пароль'
    $generateButton.Location = New-Object System.Drawing.Point(101, 151)
    $generateButton.Size = New-Object System.Drawing.Size(190, 36)
    $generateButton.FlatStyle = 'Flat'
    $generateButton.FlatAppearance.BorderSize = 0
    $generateButton.BackColor = [System.Drawing.Color]::FromArgb(67, 123, 235)
    $generateButton.ForeColor = [System.Drawing.Color]::White
    $prepareTab.Controls.Add($generateButton)

    $script:AccountPasswordBox = New-Object System.Windows.Forms.TextBox
    $script:AccountPasswordBox.Location = New-Object System.Drawing.Point(18, 198)
    $script:AccountPasswordBox.Size = New-Object System.Drawing.Size(677, 29)
    $script:AccountPasswordBox.BackColor = [System.Drawing.Color]::FromArgb(17, 23, 32)
    $script:AccountPasswordBox.ForeColor = [System.Drawing.Color]::FromArgb(149, 222, 176)
    $script:AccountPasswordBox.Font = New-Object System.Drawing.Font('Consolas', 11)
    $script:AccountPasswordBox.BorderStyle = 'FixedSingle'
    $prepareTab.Controls.Add($script:AccountPasswordBox)

    $copyPassButton = New-Object System.Windows.Forms.Button
    $copyPassButton.Text = 'Копировать пароль'
    $copyPassButton.Location = New-Object System.Drawing.Point(18, 240)
    $copyPassButton.Size = New-Object System.Drawing.Size(180, 36)
    $copyPassButton.FlatStyle = 'Flat'
    $copyPassButton.FlatAppearance.BorderSize = 0
    $copyPassButton.BackColor = [System.Drawing.Color]::FromArgb(42, 52, 70)
    $copyPassButton.ForeColor = [System.Drawing.Color]::White
    $prepareTab.Controls.Add($copyPassButton)

    $openRegisterButton = New-Object System.Windows.Forms.Button
    $openRegisterButton.Text = 'Открыть Roblox для регистрации'
    $openRegisterButton.Location = New-Object System.Drawing.Point(210, 240)
    $openRegisterButton.Size = New-Object System.Drawing.Size(260, 36)
    $openRegisterButton.FlatStyle = 'Flat'
    $openRegisterButton.FlatAppearance.BorderSize = 0
    $openRegisterButton.BackColor = [System.Drawing.Color]::FromArgb(42, 52, 70)
    $openRegisterButton.ForeColor = [System.Drawing.Color]::White
    $prepareTab.Controls.Add($openRegisterButton)

    $copyNickButton = New-Object System.Windows.Forms.Button
    $copyNickButton.Text = 'Копировать ник'
    $copyNickButton.Location = New-Object System.Drawing.Point(482, 240)
    $copyNickButton.Size = New-Object System.Drawing.Size(213, 36)
    $copyNickButton.FlatStyle = 'Flat'
    $copyNickButton.FlatAppearance.BorderSize = 0
    $copyNickButton.BackColor = [System.Drawing.Color]::FromArgb(42, 52, 70)
    $copyNickButton.ForeColor = [System.Drawing.Color]::White
    $prepareTab.Controls.Add($copyNickButton)

    $script:RegistrationConfirmedCheck = New-Object System.Windows.Forms.CheckBox
    $script:RegistrationConfirmedCheck.Text = 'Я завершил регистрацию с этими данными'
    $script:RegistrationConfirmedCheck.Location = New-Object System.Drawing.Point(18, 294)
    $script:RegistrationConfirmedCheck.Size = New-Object System.Drawing.Size(677, 28)
    $script:RegistrationConfirmedCheck.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 228)
    $prepareTab.Controls.Add($script:RegistrationConfirmedCheck)

    $saveAccountButton = New-Object System.Windows.Forms.Button
    $saveAccountButton.Text = 'Сохранить в зашифрованное хранилище'
    $saveAccountButton.Location = New-Object System.Drawing.Point(18, 331)
    $saveAccountButton.Size = New-Object System.Drawing.Size(677, 42)
    $saveAccountButton.FlatStyle = 'Flat'
    $saveAccountButton.FlatAppearance.BorderSize = 0
    $saveAccountButton.BackColor = [System.Drawing.Color]::FromArgb(37, 125, 83)
    $saveAccountButton.ForeColor = [System.Drawing.Color]::White
    $prepareTab.Controls.Add($saveAccountButton)

    $safetyInfo = New-Object System.Windows.Forms.Label
    $safetyInfo.Text = "Порядок действий: скопируй ник и пароль → открой Roblox → заполни форму и пройди проверку → отметь галочку и сохрани данные.`r`nПароль хранится в DPAPI-шифровании Windows для текущего пользователя. Автоматический ввод или обход проверок не выполняется."
    $safetyInfo.Location = New-Object System.Drawing.Point(18, 390)
    $safetyInfo.Size = New-Object System.Drawing.Size(677, 70)
    $safetyInfo.ForeColor = [System.Drawing.Color]::FromArgb(177, 188, 207)
    $safetyInfo.BackColor = [System.Drawing.Color]::FromArgb(32, 41, 56)
    $safetyInfo.Padding = New-Object System.Windows.Forms.Padding(8, 7, 8, 5)
    $prepareTab.Controls.Add($safetyInfo)

    $script:AccountListBox = New-Object System.Windows.Forms.ListBox
    $script:AccountListBox.Location = New-Object System.Drawing.Point(18, 18)
    $script:AccountListBox.Size = New-Object System.Drawing.Size(677, 275)
    $script:AccountListBox.BackColor = [System.Drawing.Color]::FromArgb(17, 23, 32)
    $script:AccountListBox.ForeColor = [System.Drawing.Color]::FromArgb(225, 232, 242)
    $vaultTab.Controls.Add($script:AccountListBox)

    $vaultPasswordLabel = New-Object System.Windows.Forms.Label
    $vaultPasswordLabel.Text = 'Пароль выбранной записи'
    $vaultPasswordLabel.Location = New-Object System.Drawing.Point(18, 304)
    $vaultPasswordLabel.Size = New-Object System.Drawing.Size(400, 22)
    $vaultPasswordLabel.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 228)
    $vaultTab.Controls.Add($vaultPasswordLabel)

    $script:SavedPasswordBox = New-Object System.Windows.Forms.TextBox
    $script:SavedPasswordBox.Location = New-Object System.Drawing.Point(18, 330)
    $script:SavedPasswordBox.Size = New-Object System.Drawing.Size(677, 29)
    $script:SavedPasswordBox.ReadOnly = $true
    $script:SavedPasswordBox.BackColor = [System.Drawing.Color]::FromArgb(17, 23, 32)
    $script:SavedPasswordBox.ForeColor = [System.Drawing.Color]::FromArgb(149, 222, 176)
    $script:SavedPasswordBox.Font = New-Object System.Drawing.Font('Consolas', 10)
    $vaultTab.Controls.Add($script:SavedPasswordBox)

    $copySavedPasswordButton = New-Object System.Windows.Forms.Button
    $copySavedPasswordButton.Text = 'Копировать пароль'
    $copySavedPasswordButton.Location = New-Object System.Drawing.Point(18, 374)
    $copySavedPasswordButton.Size = New-Object System.Drawing.Size(180, 36)
    $copySavedPasswordButton.FlatStyle = 'Flat'
    $copySavedPasswordButton.FlatAppearance.BorderSize = 0
    $copySavedPasswordButton.BackColor = [System.Drawing.Color]::FromArgb(42, 52, 70)
    $copySavedPasswordButton.ForeColor = [System.Drawing.Color]::White
    $vaultTab.Controls.Add($copySavedPasswordButton)

    $copySavedUsernameButton = New-Object System.Windows.Forms.Button
    $copySavedUsernameButton.Text = 'Копировать ник'
    $copySavedUsernameButton.Location = New-Object System.Drawing.Point(210, 374)
    $copySavedUsernameButton.Size = New-Object System.Drawing.Size(180, 36)
    $copySavedUsernameButton.FlatStyle = 'Flat'
    $copySavedUsernameButton.FlatAppearance.BorderSize = 0
    $copySavedUsernameButton.BackColor = [System.Drawing.Color]::FromArgb(42, 52, 70)
    $copySavedUsernameButton.ForeColor = [System.Drawing.Color]::White
    $vaultTab.Controls.Add($copySavedUsernameButton)

    $deleteAccountButton = New-Object System.Windows.Forms.Button
    $deleteAccountButton.Text = 'Удалить запись'
    $deleteAccountButton.Location = New-Object System.Drawing.Point(402, 374)
    $deleteAccountButton.Size = New-Object System.Drawing.Size(180, 36)
    $deleteAccountButton.FlatStyle = 'Flat'
    $deleteAccountButton.FlatAppearance.BorderSize = 0
    $deleteAccountButton.BackColor = [System.Drawing.Color]::FromArgb(115, 47, 55)
    $deleteAccountButton.ForeColor = [System.Drawing.Color]::White
    $vaultTab.Controls.Add($deleteAccountButton)

    $script:VaultStatusLabel = New-Object System.Windows.Forms.Label
    $script:VaultStatusLabel.Location = New-Object System.Drawing.Point(18, 425)
    $script:VaultStatusLabel.Size = New-Object System.Drawing.Size(677, 35)
    $script:VaultStatusLabel.ForeColor = [System.Drawing.Color]::FromArgb(177, 188, 207)
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
        foreach ($availableNick in $script:RobloxAvailableNames) { [void]$script:AccountUsernameBox.Items.Add([string]$availableNick) }
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
        [System.Windows.Forms.Clipboard]::SetText($script:AccountPasswordBox.Text)
    })

    $copyNickButton.Add_Click({
        $nick = $script:AccountUsernameBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($nick)) {
            [System.Windows.Forms.MessageBox]::Show('Сначала выбери или введи ник.', 'Копирование', 'OK', 'Information') | Out-Null
            return
        }
        [System.Windows.Forms.Clipboard]::SetText($nick)
    })

    $openRegisterButton.Add_Click({
        if (-not (Test-RobloxUsernameFormat $script:AccountUsernameBox.Text.Trim())) {
            [System.Windows.Forms.MessageBox]::Show('Ник должен содержать 3–20 символов: латинские буквы, цифры и не более одного подчёркивания внутри. Нельзя начинать или заканчивать ник подчёркиванием.', 'Проверь ник', 'OK', 'Warning') | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($script:AccountPasswordBox.Text)) {
            $script:AccountPasswordBox.Text = New-SecurePassword -Length ([int]$script:PasswordLengthBox.Value)
        }
        try {
            Start-Process 'https://www.roblox.com/'
            [System.Windows.Forms.MessageBox]::Show("Открыл официальную страницу Roblox.`r`n`r`nСкопируй ник и пароль в форму вручную и пройди все проверки. Roblox может потребовать CAPTCHA или дополнительное подтверждение.", 'Регистрация', 'OK', 'Information') | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show('Не удалось открыть сайт: ' + $_.Exception.Message, 'Ошибка', 'OK', 'Error') | Out-Null
        }
    })

    $saveAccountButton.Add_Click({
        $nick = $script:AccountUsernameBox.Text.Trim()
        $password = $script:AccountPasswordBox.Text
        if (-not (Test-RobloxUsernameFormat $nick)) {
            [System.Windows.Forms.MessageBox]::Show('Проверь ник: 3–20 символов, латинские буквы и цифры; одиночное подчёркивание допускается внутри.', 'Неверный ник', 'OK', 'Warning') | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($password) -or $password.Length -lt 16) {
            [System.Windows.Forms.MessageBox]::Show('Сначала сгенерируй пароль длиной от 16 символов.', 'Нет пароля', 'OK', 'Warning') | Out-Null
            return
        }
        if (-not $script:RegistrationConfirmedCheck.Checked) {
            [System.Windows.Forms.MessageBox]::Show('Сначала заверши регистрацию на сайте Roblox и отметь галочку подтверждения.', 'Регистрация не подтверждена', 'OK', 'Information') | Out-Null
            return
        }
        try {
            $records = @(Get-SavedAccountRecords)
            $existing = @($records | Where-Object { [string]$_.Username -ieq $nick })
            if ($existing.Count -gt 0) {
                $choice = [System.Windows.Forms.MessageBox]::Show("Запись для ника $nick уже существует. Перезаписать пароль?", 'Запись уже есть', 'YesNo', 'Question')
                if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { return }
                $records = @($records | Where-Object { [string]$_.Username -ine $nick })
            }
            $record = [pscustomobject]@{Username=$nick; Password=$password; CreatedAt=(Get-Date).ToString('o')}
            $records = @($records) + @($record)
            Save-EncryptedAccountRecords -Records $records
            $script:RegistrationConfirmedCheck.Checked = $false
            Refresh-SavedAccountList
            $script:AccountTabs.SelectedTab = $script:AccountVaultTab
            [System.Windows.Forms.MessageBox]::Show("Данные для $nick сохранены в зашифрованное хранилище текущего пользователя Windows.", 'Сохранено', 'OK', 'Information') | Out-Null
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
        [System.Windows.Forms.Clipboard]::SetText($script:SavedPasswordBox.Text)
    })

    $copySavedUsernameButton.Add_Click({
        $index = $script:AccountListBox.SelectedIndex
        if ($index -lt 0 -or $index -ge $script:AccountRecords.Count) {
            [System.Windows.Forms.MessageBox]::Show('Сначала выбери запись в списке.', 'Копирование', 'OK', 'Information') | Out-Null
            return
        }
        [System.Windows.Forms.Clipboard]::SetText([string]$script:AccountRecords[$index].Username)
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
        foreach ($availableNick in $script:RobloxAvailableNames) { [void]$script:AccountUsernameBox.Items.Add([string]$availableNick) }
        $preferredNick = ''
        if ($script:Grid.CurrentRow -and $script:Grid.CurrentRow.Index -ge 0) {
            $candidateNick = [string]$script:Grid.CurrentRow.Cells['Nick'].Value
            $candidateStatus = [string]$script:Grid.CurrentRow.Cells['Status'].Value
            if ($candidateStatus -eq 'Свободен') { $preferredNick = $candidateNick }
        }
        if (-not $preferredNick -and $script:RobloxAvailableNames.Count -gt 0) { $preferredNick = [string]$script:RobloxAvailableNames[0] }
        $script:AccountUsernameBox.Text = $preferredNick
        $script:AccountPasswordBox.Text = New-SecurePassword -Length ([int]$script:PasswordLengthBox.Value)
        Refresh-SavedAccountList
    } catch {
        $script:VaultStatusLabel.Text = 'Не удалось прочитать хранилище: ' + $_.Exception.Message
        Write-AppLog ('Ошибка открытия инструментов аккаунта: ' + $_.Exception.ToString())
    }
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
    # Любое добавление кандидата, смена его статуса или очистка списка повышает
    # ревизию. Update-AvailableNames сравнивает её с уже обработанной и не
    # пересчитывает свободные ники, если ничего не изменилось.
    $script:CandidateRevision = $script:CandidateRevision + 1
}

# --- Атомарная запись файлов ----------------------------------------------------
# Используется и для истории ников, и для настроек: оба файла содержат кириллицу и
# пишутся во время работы, поэтому сбой посреди записи не должен их портить.

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
            # File.Replace требует того же тома и поддержки со стороны файловой системы,
            # и в части окружений завершается ошибкой. Резервный путь — перезапись
            # копированием: перегрузки Move с перезаписью в .NET Framework (Windows
            # PowerShell 5.1) не существует, а Move поверх существующего файла бросает
            # IOException «Cannot create a file when that file already exists».
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
    # Encoding.GetBytes() не добавляет BOM — его возвращает только GetPreamble().
    # Без BOM Windows PowerShell 5.1 читает файл как ANSI (Get-Content без -Encoding),
    # и кириллица в сохранённых настройках и истории ников ломается.
    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $true
    $preamble = $encoding.GetPreamble()
    $body = $encoding.GetBytes($Json)
    $bytes = New-Object byte[] ($preamble.Length + $body.Length)
    [System.Array]::Copy($preamble, 0, $bytes, 0, $preamble.Length)
    [System.Array]::Copy($body, 0, $bytes, $preamble.Length, $body.Length)
    Write-AtomicFile -Path $Path -Bytes $bytes
}

function Save-UsernameHistory {
    try {
        if (-not (Test-Path -LiteralPath $script:HistoryDirectory)) { [void](New-Item -ItemType Directory -Path $script:HistoryDirectory -Force) }
        $data = [pscustomobject]@{
            FreeHistory = @($script:FreeHistory | Select-Object -First 30)
            RetiredNames = @($script:RetiredNames.Keys | Select-Object -First 20000)
        }
        $json = ConvertTo-Json -InputObject $data -Depth 6
        if ([string]::IsNullOrWhiteSpace($json)) { $json = '{}' }
        # Атомарная запись: раньше Set-Content писал прямо в целевой файл, и падение
        # программы посреди записи оставляло побитый username_history.json.
        $historyFull = [System.IO.Path]::GetFullPath($script:HistoryPath)
        Write-AtomicJsonFile -Path $historyFull -Json $json
        $script:HistoryDirty = $false
        $script:HistoryDirtySince = $null
    } catch { Write-AppLog ('Не удалось сохранить историю ников: ' + $_.Exception.Message) }
}

# История меняется на каждый проверенный ник; писать файл на каждое событие дорого.
# Помечаем данные «грязными» и сбрасываем на диск не чаще раза в несколько секунд,
# а также по завершении прогона и при закрытии окна.
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

# --- Настройки приложения -------------------------------------------------------
# Export-/Import- функции намеренно чистые (без обращений к контролам и к области
# видимости скрипта): их можно тестировать без создания окон.

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
        # Повреждённые настройки не должны мешать запуску: возвращаем пустой набор.
        return @{}
    }
    return $result
}

# --- Безопасное применение значений к контролам ---------------------------------
# Каждое значение проверяется: выход за границы NumericUpDown и отсутствующий пункт
# ComboBox раньше приводили к исключениям или к обнулению выбора.

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

function Get-AppSettingsFromUi {
    $settings = @{}
    Add-SettingValue $settings 'AppVersion' { $script:AppVersion }
    Add-SettingValue $settings 'WindowState' { [string]$script:Form.WindowState }
    Add-SettingValue $settings 'WindowBounds' {
        $bounds = if ($script:Form.WindowState -eq 'Normal') { $script:Form.Bounds } else { $script:Form.RestoreBounds }
        @{ X = [int]$bounds.X; Y = [int]$bounds.Y; Width = [int]$bounds.Width; Height = [int]$bounds.Height }
    }
    Add-SettingValue $settings 'Platform' { [string]$script:PlatformBox.SelectedItem }
    Add-SettingValue $settings 'StatusFilter' { [string]$script:StatusFilterBox.SelectedItem }
    Add-SettingValue $settings 'SortMode' { [string]$script:SortBox.SelectedItem }
    Add-SettingValue $settings 'Style' { [string]$script:StyleBox.SelectedItem }
    Add-SettingValue $settings 'Categories' { @($script:CategoryList.CheckedItems | ForEach-Object { [string]$_ }) }
    Add-SettingValue $settings 'Count' { [int]$script:CountBox.Value }
    Add-SettingValue $settings 'MinLength' { [int]$script:MinLengthBox.Value }
    Add-SettingValue $settings 'MaxLength' { [int]$script:MaxLengthBox.Value }
    Add-SettingValue $settings 'DelayMs' { [int]$script:DelayBox.Value }
    Add-SettingValue $settings 'TimeoutMs' { [int]$script:TimeoutBox.Value }
    Add-SettingValue $settings 'UseNumbers' { [bool]$script:NumbersCheck.Checked }
    Add-SettingValue $settings 'UseUnderscore' { [bool]$script:UnderscoreCheck.Checked }
    Add-SettingValue $settings 'OneWord' { [bool]$script:OneWordCheck.Checked }
    Add-SettingValue $settings 'TwoWords' { [bool]$script:TwoWordsCheck.Checked }
    Add-SettingValue $settings 'OnlyShort' { [bool]$script:ShortOnlyCheck.Checked }
    Add-SettingValue $settings 'ExcludeChecked' { [bool]$script:ExcludeCheckedCheck.Checked }
    Add-SettingValue $settings 'OnlyFree' { [bool]$script:OnlyFreeCheck.Checked }
    return $settings
}

function Restore-AppSettingsToUi {
    param([hashtable]$Settings)
    if ($null -eq $Settings -or $Settings.Count -eq 0) { return }

    # Геометрия окна: сохраняем только если окно попадает в границы текущего экрана,
    # иначе после отключения второго монитора окно оказалось бы за пределами видимости.
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

    Set-ComboFromSettings $script:PlatformBox $Settings['Platform']
    Set-ComboFromSettings $script:StatusFilterBox $Settings['StatusFilter']
    Set-ComboFromSettings $script:SortBox $Settings['SortMode']
    Set-ComboFromSettings $script:StyleBox $Settings['Style']
    Set-CheckedListFromSettings $script:CategoryList $Settings['Categories']

    Set-NumericFromSettings $script:CountBox $Settings['Count'] ([int]$script:CountBox.Value)
    Set-NumericFromSettings $script:MinLengthBox $Settings['MinLength'] ([int]$script:MinLengthBox.Value)
    Set-NumericFromSettings $script:MaxLengthBox $Settings['MaxLength'] ([int]$script:MaxLengthBox.Value)
    Set-NumericFromSettings $script:DelayBox $Settings['DelayMs'] ([int]$script:DelayBox.Value)
    Set-NumericFromSettings $script:TimeoutBox $Settings['TimeoutMs'] ([int]$script:TimeoutBox.Value)

    Set-CheckFromSettings $script:NumbersCheck $Settings['UseNumbers']
    Set-CheckFromSettings $script:UnderscoreCheck $Settings['UseUnderscore']
    Set-CheckFromSettings $script:OneWordCheck $Settings['OneWord']
    Set-CheckFromSettings $script:TwoWordsCheck $Settings['TwoWords']
    Set-CheckFromSettings $script:ShortOnlyCheck $Settings['OnlyShort']
    Set-CheckFromSettings $script:ExcludeCheckedCheck $Settings['ExcludeChecked']
    Set-CheckFromSettings $script:OnlyFreeCheck $Settings['OnlyFree']

    # Минимальная длина не должна превышать максимальную после восстановления.
    try {
        if ([int]$script:MinLengthBox.Value -gt [int]$script:MaxLengthBox.Value) {
            $script:MinLengthBox.Value = $script:MaxLengthBox.Value
        }
    } catch { }
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
    if ($status -eq 'Свободен' -or $status -eq 'Вероятно свободен') {
        if ($script:RetiredNames.ContainsKey($key)) { return }
        $entry = [pscustomobject]@{ Name=$name; Platform=$platform; Status=$status; Time=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
        $remaining = @($script:FreeHistory | Where-Object { (Get-HistoryKey -Name ([string]$_.Name) -Platform ([string]$_.Platform)) -ne $key })
        $script:FreeHistory = @(@($entry) + @($remaining | Select-Object -First 29))
    } elseif ($status -eq 'Занят') {
        $script:FreeHistory = @($script:FreeHistory | Where-Object { (Get-HistoryKey -Name ([string]$_.Name) -Platform ([string]$_.Platform)) -ne $key })
        $script:RetiredNames[$key] = $true
    } else { return }
    if ($script:HistoryButton) { $script:HistoryButton.Text = "Свободные ники ($($script:FreeHistory.Count))" }
    Mark-HistoryDirty
}

function Refresh-FreeHistoryList {
    if (-not $script:HistoryListBox) { return }
    $script:HistoryListBox.BeginUpdate()
    $script:HistoryListBox.Items.Clear()
    foreach ($item in @($script:FreeHistory | Sort-Object Time -Descending)) {
        $display = '{0} — {1}' -f [string]$item.Name, [string]$item.Platform
        [void]$script:HistoryListBox.Items.Add([pscustomobject]@{Display=$display; Name=[string]$item.Name; Platform=[string]$item.Platform; Status=[string]$item.Status})
    }
    $script:HistoryListBox.EndUpdate()
    if ($script:HistoryListBox.Items.Count -eq 0) {
        $script:HistoryDescription.Text = 'Пока нет имён, которые проверка признала свободными или вероятно свободными.'
    } else {
        $script:HistoryDescription.Text = 'Выбери ник и нажми «Повторная проверка». Если он уже занят, он исчезнет из истории и больше не будет генерироваться.'
    }
}

function Open-FreeHistoryWindow {
    $script:HistoryForm = New-Object System.Windows.Forms.Form
    $script:HistoryForm.Text = 'Последние свободные ники'
    $script:HistoryForm.StartPosition = 'CenterParent'
    $script:HistoryForm.Size = New-Object System.Drawing.Size(520,560)
    $script:HistoryForm.MinimumSize = New-Object System.Drawing.Size(480,480)
    $script:HistoryForm.BackColor = [System.Drawing.Color]::FromArgb(15,19,27)
    $script:HistoryForm.ForeColor = [System.Drawing.Color]::White
    $script:HistoryForm.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $script:HistoryDescription = New-Object System.Windows.Forms.Label
    $script:HistoryDescription.Location = New-Object System.Drawing.Point(16,14)
    $script:HistoryDescription.Size = New-Object System.Drawing.Size(470,50)
    $script:HistoryDescription.ForeColor = [System.Drawing.Color]::FromArgb(190,202,221)
    $script:HistoryForm.Controls.Add($script:HistoryDescription)
    $script:HistoryListBox = New-Object System.Windows.Forms.ListBox
    $script:HistoryListBox.Location = New-Object System.Drawing.Point(16,70)
    $script:HistoryListBox.Size = New-Object System.Drawing.Size(470,370)
    $script:HistoryListBox.Anchor = 'Top, Bottom, Left, Right'
    $script:HistoryListBox.DisplayMember = 'Display'
    $script:HistoryListBox.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $script:HistoryListBox.ForeColor = [System.Drawing.Color]::FromArgb(225,232,242)
    $script:HistoryForm.Controls.Add($script:HistoryListBox)
    $recheck = New-Object System.Windows.Forms.Button
    $recheck.Text = '↻ Повторная проверка'
    $recheck.Location = New-Object System.Drawing.Point(16,452)
    $recheck.Size = New-Object System.Drawing.Size(190,34)
    $recheck.Anchor = 'Bottom, Left'
    $recheck.FlatStyle = 'Flat'
    $recheck.BackColor = [System.Drawing.Color]::FromArgb(93,73,222)
    $recheck.ForeColor = [System.Drawing.Color]::White
    $recheck.Enabled = -not ($script:AsyncHandle -and -not $script:AsyncHandle.IsCompleted)
    $script:HistoryForm.Controls.Add($recheck)
    $copy = New-Object System.Windows.Forms.Button
    $copy.Text = 'Копировать ник'
    $copy.Location = New-Object System.Drawing.Point(214,452)
    $copy.Size = New-Object System.Drawing.Size(130,34)
    $copy.Anchor = 'Bottom, Left'
    $copy.FlatStyle = 'Flat'
    $copy.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $copy.ForeColor = [System.Drawing.Color]::White
    $script:HistoryForm.Controls.Add($copy)
    $open = New-Object System.Windows.Forms.Button
    $open.Text = 'Открыть сайт'
    $open.Location = New-Object System.Drawing.Point(352,452)
    $open.Size = New-Object System.Drawing.Size(134,34)
    $open.Anchor = 'Bottom, Right'
    $open.FlatStyle = 'Flat'
    $open.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $open.ForeColor = [System.Drawing.Color]::White
    $script:HistoryForm.Controls.Add($open)
    $copy.Add_Click({
        $selected = $script:HistoryListBox.SelectedItem
        if ($selected) { [System.Windows.Forms.Clipboard]::SetText([string]$selected.Name) }
    })
    $open.Add_Click({
        $selected = $script:HistoryListBox.SelectedItem
        if ($selected) { Start-Process (Get-PlatformWebsiteUrl -Platform ([string]$selected.Platform) -Username ([string]$selected.Name)) }
    })
    $recheck.Add_Click({
        $selected = $script:HistoryListBox.SelectedItem
        if (-not $selected) { [System.Windows.Forms.MessageBox]::Show('Сначала выбери ник в списке.','Повторная проверка','OK','Information') | Out-Null; return }
        $selectedName = [string]$selected.Name
        $selectedPlatform = [string]$selected.Platform
        # Платформа из старой истории может больше не поддерживаться: иначе ComboBox обнулится
        # и проверка уйдёт с пустой платформой.
        if (-not (Test-SupportedPlatform -Platform $selectedPlatform)) {
            [System.Windows.Forms.MessageBox]::Show(("Платформа «{0}» больше не поддерживается этой версией программы.`r`n`r`nПовторная проверка доступна для: {1}." -f $selectedPlatform, ($script:SupportedPlatforms -join ', ')),'Повторная проверка','OK','Information') | Out-Null
            Add-Diagnostic ("Повторная проверка отменена: платформа $selectedPlatform не поддерживается.")
            return
        }
        if ($script:AsyncHandle -and -not $script:AsyncHandle.IsCompleted) {
            [System.Windows.Forms.MessageBox]::Show('Идёт проверка. Дождись завершения или останови её.','Повторная проверка','OK','Information') | Out-Null
            return
        }
        $script:HistoryForm.Close()
        $script:PlatformBox.SelectedItem = $selectedPlatform
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
        Touch-Candidates
        $key = Get-HistoryKey -Name $selectedName -Platform $selectedPlatform
        $script:CheckedNames.Remove($key)
        Update-ResultGrid
        Add-Diagnostic "Повторная проверка: $selectedName ($selectedPlatform)."
        Start-Checking -RetryErrorsOnly $false
    })
    Refresh-FreeHistoryList
    $script:HistoryForm.Add_Shown({ $script:HistoryForm.Activate() })
    [void]$script:HistoryForm.ShowDialog($script:Form)
}

function Show-UsernameFinderHelp {
    $helpForm = New-Object System.Windows.Forms.Form
    $helpForm.Text = 'Помощь — Universal Username Finder'
    $helpForm.StartPosition = 'CenterParent'
    $helpForm.Size = New-Object System.Drawing.Size(760,650)
    $helpForm.MinimumSize = New-Object System.Drawing.Size(620,500)
    $helpForm.BackColor = [System.Drawing.Color]::FromArgb(15,19,27)
    $helpForm.Font = New-Object System.Drawing.Font('Segoe UI',9)
    $helpText = New-Object System.Windows.Forms.RichTextBox
    $helpText.Location = New-Object System.Drawing.Point(16,16)
    $helpText.Size = New-Object System.Drawing.Size(710,550)
    $helpText.Anchor = 'Top, Bottom, Left, Right'
    $helpText.ReadOnly = $true
    $helpText.DetectUrls = $false
    $helpText.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)
    $helpText.ForeColor = [System.Drawing.Color]::FromArgb(225,232,242)
    $helpText.BorderStyle = 'FixedSingle'
    $helpText.Font = New-Object System.Drawing.Font('Segoe UI',10)
    $helpText.Text = @'
UNIVERSAL USERNAME FINDER — ПОМОЩЬ

1. Платформа
Выбери сервис, для которого хочешь подобрать имя. Каждый кандидат проверяется с учётом примерных правил длины и символов именно этой платформы.

2. Единые категории
В одном списке можно отметить несколько тем: цельные слова, короткие, космос, свет и энергия, природа, мифология, эмоции, скорость, абстрактное и эстетика. Категории не связаны с названиями брендов.

3. Генерация и проверка
Нажми «Сгенерировать и проверить» один раз. Программа создаст кандидатов, добавит собственные слова и ручные ники, отфильтрует неподходящие варианты и начнёт проверку автоматически. Запросы идут последовательно; можно остановить процесс.

4. Значения статусов
«Свободен» — платформа сообщила, что имя доступно на момент проверки.
«Вероятно свободен» — публичная проверка не нашла профиль или handle. Имя может быть зарезервировано.
«Занят» — платформа нашла профиль или сообщила, что имя уже используется.
«Не подтверждено» — сайт не раскрыл однозначный результат, например из-за защитного ограничения или изменения ответа. Это не означает, что имя свободно.
«Ошибка сети» — запрос не удалось завершить; можно нажать «Повторить ошибки».

5. Таблица и экспорт
Используй фильтр статусов и строку поиска. Двойной щелчок по свободному/вероятно свободному имени копирует его. TXT сохраняет доступные и вероятно доступные варианты; CSV сохраняет все результаты.

6. Последние свободные ники
Кнопка «Свободные ники» открывает историю в формате «Ник — Платформа». Выбери запись и нажми «Повторная проверка». Если сервис сообщает, что имя занято, запись удаляется из истории, а ник заносится в список исключений и больше не генерируется этой программой. История хранится локально в профиле Windows.

7. Методы проверки платформ
Roblox — POST регистрационный валидатор /v1/usernames/validate; разбор code=0/1/2/3/10, неизвестный код не считается свободным.
Google — проверка Gmail через контекст страницы регистрации; если ответ не распознан, результат остаётся неподтверждённым.
Mail.ru — GET account.mail.ru/api/v1/user/exists?email=...; анализ body.exists/exists.
VK — попытка utils.resolveScreenName и проверка публичной страницы профиля; отсутствие профиля не гарантирует возможность регистрации.
Discord — попытка endpoint уникального username с нормализацией к нижнему регистру и анализом taken/username_taken.
TikTok — сначала attempt регистрации passport/web/account/check_name; при нераспознанном ответе используется публичная страница как резервная проверка.
Microsoft/Outlook — signup.live.com CheckAvailableSigninNames для @hotmail.com и @outlook.com; разбираются isAvailable и доступный IfExistsResult.
GitHub — signup_check/username с cookie-сессией; при неоднозначном ответе используется REST API профилей. Отсутствие профиля означает только вероятную доступность.
YouTube — сравнение canonical handle целевой страницы и channel metadata. 404 трактуется как вероятная, но не гарантированная доступность.
Telegram — проверка публичной страницы t.me; при неясном ответе ставится «Не подтверждено», так как account.checkUsername требует авторизованной сессии.
Apple — запрос проверки адреса {ник}@icloud.com к account/validation/appleid; при отсутствии нужного контекста ответ остаётся неподтверждённым.
Каждый сервис проверяется своим сетевым методом. При изменении endpoint или защитном ограничении программа не объявляет имя свободным без понятного ответа.

8. Пароль / регистрация
Генератор паролей создаёт случайный пароль. Регистрацию нужно завершить на официальном сайте самостоятельно; программа не обходит CAPTCHA. Хранилище паролей защищается Windows DPAPI для текущего пользователя.

Доступность имени может измениться после проверки. Окончательное решение принимает сама платформа во время регистрации.
'@
    $helpForm.Controls.Add($helpText)
    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Закрыть'
    $close.Location = New-Object System.Drawing.Point(616,574)
    $close.Size = New-Object System.Drawing.Size(110,30)
    $close.Anchor = 'Bottom, Right'
    $close.FlatStyle = 'Flat'
    $close.BackColor = [System.Drawing.Color]::FromArgb(42,52,70)
    $close.ForeColor = [System.Drawing.Color]::White
    $close.Add_Click({ param($sender,$e); $sender.FindForm().Close() })
    $helpForm.Controls.Add($close)
    [void]$helpForm.ShowDialog($script:Form)
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
    $script:ThemeBox.Enabled = $true
    $script:ManualNickBox.Enabled = $true
    $script:DelayBox.Enabled = $true
    $script:TimeoutBox.Enabled = $true
    if ($script:PlatformBox) { $script:PlatformBox.Enabled = $true }
}

function Close-CheckRunspace {
    try { if ($script:WorkerPowerShell) { $script:WorkerPowerShell.Dispose() } } catch { }
    try { if ($script:WorkerRunspace) { $script:WorkerRunspace.Close(); $script:WorkerRunspace.Dispose() } } catch { }
    try { if ($script:Cancellation) { $script:Cancellation.Dispose() } } catch { }
    $script:WorkerPowerShell = $null
    $script:WorkerRunspace = $null
    $script:AsyncHandle = $null
    $script:Cancellation = $null
    $script:CheckQueue = $null
    $script:CompletionEvent = $null
    $script:UnhandledWorkerError = $null
}

function Update-AvailableNames {
    if ($script:CandidateRevision -eq $script:AvailableNamesRevision) { return }
    $script:AvailableNamesRevision = $script:CandidateRevision
    $script:AvailableNames.Clear()
    $script:RobloxAvailableNames.Clear()
    foreach ($candidate in $script:Candidates) {
        $status = [string]$candidate.Status
        $platform = [string]$candidate.Platform
        if ($platform -eq 'Roblox' -and $status -eq 'Свободен') { $script:RobloxAvailableNames.Add([string]$candidate.Name) }
        if ($status -eq 'Свободен' -or $status -eq 'Вероятно свободен') {
            $script:AvailableNames.Add(('{0}: {1} [{2}]' -f $platform,[string]$candidate.Name,$status))
        }
    }
}

function Update-Stats {
    $total = $script:Candidates.Count
    $checked = 0; $free = 0; $taken = 0; $invalid = 0; $errors = 0
    # Один проход вместо пяти: статистика пересчитывается на каждую перерисовку таблицы.
    foreach ($candidate in $script:Candidates) {
        if ($candidate.Checked) { $checked++ }
        switch ([string]$candidate.Status) {
            'Свободен' { $free++ }
            'Вероятно свободен' { $free++ }
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
}

function Update-ResultGrid {
    if (-not $script:Grid) { return }
    # При AutoSizeMode='Fill' ширина столбцов пересчитывается на КАЖДОЙ добавленной
    # строке, и SuspendLayout этого не блокирует. На лимитах до 2000 кандидатов
    # (с учётом мультиплатформенности — тысячи строк) перерисовка занимала секунды.
    # Поэтому на время массовой вставки автоширина отключается и включается обратно
    # один раз в конце.
    $script:Grid.SuspendLayout()
    $restoreAutoSize = $false
    if ($script:Grid.AutoSizeColumnsMode -eq [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill) {
        $script:Grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
        $restoreAutoSize = $true
    }
    $script:Grid.Rows.Clear()
    $filterStatus = [string]$script:StatusFilterBox.SelectedItem
    $query = ''
    if ($script:SearchBox) { $query = $script:SearchBox.Text.Trim() }
    $items = @($script:Candidates.ToArray())
    switch ([string]$script:SortBox.SelectedItem) {
        'Статус' { $items = @($items | Sort-Object Status, Platform, Name) }
        'Категория' { $items = @($items | Sort-Object Category, Platform, Name) }
        'Структура' { $items = @($items | Sort-Object Structure, Category, Platform, Name) }
        'Короткие сначала' { $items = @($items | Sort-Object @{Expression={$_.Name.Length}}, Platform, Name) }
        'Свободные первыми' { $items = @($items | Sort-Object @{Expression={ switch ([string]$_.Status) { 'Свободен' {0}; 'Вероятно свободен' {1}; 'Не подтверждено' {2}; 'Ожидает' {3}; 'Проверяется' {4}; 'Ошибка сети' {5}; 'Занят' {6}; default {7} } }}, Platform, Name) }
        default { $items = @($items | Sort-Object Platform, Name) }
    }
    foreach ($item in $items) {
        if ($script:OnlyFreeCheck.Checked -and ([string]$item.Status -ne 'Свободен' -and [string]$item.Status -ne 'Вероятно свободен')) { continue }
        if ($filterStatus -and $filterStatus -ne 'Все статусы' -and [string]$item.Status -ne $filterStatus) { continue }
        $searchText = ([string]$item.Name + ' ' + [string]$item.Platform + ' ' + [string]$item.Category + ' ' + [string]$item.Structure + ' ' + [string]$item.Meaning + ' ' + [string]$item.Reason)
        if ($query -and $searchText.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $row = $script:Grid.Rows.Add([string]$item.Name,[string]$item.Platform,[string]$item.Status,[string]$item.Category,[string]$item.Structure,[string]$item.Meaning,[string]$item.Time,[string]$item.Reason)
        $color = $script:StatusColors[[string]$item.Status]
        if ($null -eq $color) { $color = $script:StatusColors['Ошибка сети'] }
        $script:Grid.Rows[$row].Cells['Nick'].Style.ForeColor = $color
        $script:Grid.Rows[$row].Cells['Status'].Style.ForeColor = $color
    }
    if ($restoreAutoSize) {
        $script:Grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    }
    $script:Grid.ResumeLayout()
    Update-Stats
    Update-AvailableNames
}

function Start-Checking {
    param([bool]$RetryErrorsOnly = $false)
    if ($script:AsyncHandle -and -not $script:AsyncHandle.IsCompleted) { return }
    $eligible = New-Object System.Collections.ArrayList
    $selectedPlatform = [string]$script:PlatformBox.SelectedItem
    foreach ($candidate in $script:Candidates) {
        if ([string]$candidate.Platform -ne $selectedPlatform) { continue }
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
        $msg = if ($RetryErrorsOnly) { 'Ошибок для повторной проверки нет.' } else { 'Нет подходящих ников. Сначала сгенерируй варианты или отключи исключение уже проверенных.' }
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
    Add-Diagnostic ("Начата проверка: {0} ников; пауза {1} мс; тайм-аут {2} мс; потоков 1; платформа {3}." -f $validCandidates.Count,[int]$script:DelayBox.Value,[int]$script:TimeoutBox.Value,$selectedPlatform)
    $script:CurrentBatchTotal = $validCandidates.Count
    $script:CurrentBatchDone = 0
    $script:ProgressBar.Value = 0
    $script:ProgressCaption.Text = "Проверка 0 из $($script:CurrentBatchTotal)"
    $workerScript = @'
param($Candidates, $Queue, $Cancellation, $DelayMs, $TimeoutMs, $Platform, $AppVersion)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::DefaultConnectionLimit = 10
if ([string]::IsNullOrWhiteSpace([string]$AppVersion)) { $AppVersion = '2.5.4' }
$TimeoutMs = [Math]::Max(1000,[int]$TimeoutMs)
# Пауза адаптивная (AIMD): значение из интерфейса — стартовая точка, а не жёсткая задержка.
# Пол задаётся профилем платформы и не зависит от состояния контролов, потому что
# аргументы приходят извне; потолок защищает от ухода в бесконечное ожидание.
$platformFloorMs = 400
switch ($Platform) {
    # GitHub: анонимный лимит 60 запросов в час, то есть ограничивает количество,
    # а не темп. Ускорение здесь бессмысленно — важнее раньше остановиться на 403.
    'GitHub' { $platformFloorMs = 1000 }
    # Roblox: активная антибот-защита, поэтому старт осторожнее общего пола.
    'Roblox' { $platformFloorMs = 600 }
}
$minDelayMs = $platformFloorMs
$maxDelayMs = 20000
$currentDelayMs = [Math]::Max($minDelayMs,[int]$DelayMs)
$successStreak = 0
$consecutiveRateLimits = 0
$total = @($Candidates).Count
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
    # Редиректы сопровождаются вручную (MaximumRedirection 0). Причина: в Windows PowerShell 5.1
    # авто-редирект для POST с телом приводит HttpWebRequest к ProtocolViolationException
    # "Cannot send a content-body with this verb type" — именно так падали все проверки Roblox.
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
            $r = Invoke-WebRequest @requestArgs
            $code = [int]$r.StatusCode
            $content = [string]$r.Content
            $responseHeaders = $r.Headers
        } catch {
            $errorRecord = $_
            try { $webResponse = $_.Exception.Response } catch { }
            if ($null -eq $webResponse) {
                # Ответа нет вообще: DNS, TLS, тайм-аут, сброс соединения или нарушение протокола.
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
                # По RFC тело при таком редиректе теряется, а метод становится GET.
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
$appleSession = $null
$appleApiKey = ''
if ($Platform -eq 'Google') {
    try {
        $googleSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $googlePage = Get-HttpResult -Url 'https://accounts.google.com/signup/v2/webcreateaccount?service=mail&flowEntry=SignUp' -Timeout $timeoutSec -Headers $browserHeaders -WebSession $googleSession
        $setupMatch = [regex]::Match([string]$googlePage.Content, 'data-initial-setup-data="([^"]+)"')
        if (-not $setupMatch.Success) { $setupMatch = [regex]::Match([string]$googlePage.Content, "data-initial-setup-data='([^']+)'") }
        if ($setupMatch.Success) {
            $setupData = [System.Net.WebUtility]::HtmlDecode($setupMatch.Groups[1].Value)
            $setupParts = $setupData.Split(',')
            if ($setupParts.Length -gt 13) { $googleSetupToken = $setupParts[13].Trim() }
            if (-not $googleSetupToken) {
                $tokenMatch = [regex]::Match($setupData, '(?i)(?:signup|usernameavailability)[^,]{0,30},\s*"([^"]{8,})"')
                if ($tokenMatch.Success) { $googleSetupToken = $tokenMatch.Groups[1].Value }
            }
        }
        if (-not $googleSetupToken) { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message='Google: не удалось извлечь контекст регистрации; результаты будут помечены как неподтверждённые.'}) }
    } catch { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=('Google: инициализация проверки не удалась: ' + $_.Exception.Message)}) }
}
if ($Platform -eq 'GitHub') {
    # Сессия и cookie создаются один раз на прогон: раньше на каждый ник выполнялись
    # два лишних запроса (новая сессия + загрузка страницы регистрации).
    try {
        $githubSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $null = Get-HttpResult -Url $githubSignupUrl -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='text/html,application/xhtml+xml'} -WebSession $githubSession
    } catch { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=('GitHub: инициализация сессии не удалась: ' + $_.Exception.Message)}) }
}
if ($Platform -eq 'Apple') {
    try {
        $appleSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $appleInit = Get-HttpResult -Url 'https://appleid.apple.com/account' -Timeout $timeoutSec -Headers $browserHeaders -WebSession $appleSession
        $apiKeyMatch = [regex]::Match([string]$appleInit.Content, '(?i)(?:X-Apple-Api-Key|apiKey)\s*["''\s:=]+([A-Za-z0-9_-]{20,})')
        if ($apiKeyMatch.Success) { $appleApiKey = $apiKeyMatch.Groups[1].Value }
        if (-not $appleApiKey) { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message='Apple: не удалось извлечь API-ключ из страницы регистрации; результаты могут остаться неподтверждёнными.'}) }
    } catch { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=('Apple: инициализация проверки не удалась: ' + $_.Exception.Message)}) }
}
if ($Platform -eq 'Microsoft' -or $Platform -eq 'Outlook') {
    try {
        $msSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $msPage = Get-HttpResult -Url 'https://signup.live.com/?lic=1' -Timeout $timeoutSec -Headers $browserHeaders -WebSession $msSession
        $contextMatch = [regex]::Match([string]$msPage.Content, '(?s)var\s+t0\s*=\s*(\{.*?\})\s*;')
        if ($contextMatch.Success) { $msContext = ConvertFrom-Json -InputObject $contextMatch.Groups[1].Value -ErrorAction Stop }
        if ($null -eq $msContext -or -not $msContext.apiCanary) { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message='Microsoft/Outlook: регистрационная сессия не вернула токен проверки.'}) }
    } catch { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=('Microsoft/Outlook: инициализация проверки не удалась: ' + $_.Exception.Message)}) }
}
try {
    foreach ($item in $Candidates) {
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
                'Roblox' {
                    $payload = @{username=$name; birthday='2000-01-01T00:00:00.000Z'; context='Signup'} | ConvertTo-Json -Compress
                    $robloxHeaders = @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'; 'Origin'='https://www.roblox.com'; 'Referer'='https://www.roblox.com/'}
                    # Roblox отвечает 403 "Token Validation Failed" и отдаёт токен в заголовке X-CSRF-Token.
                    # Повторяем POST с этим токеном; GET-запрос к /v1/usernames/validate не поддерживается.
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
                'Google' {
                    if (-not $googleSetupToken -or $null -eq $googleSession) {
                        $status = 'Не подтверждено'; $reason = 'Google не предоставил контекст своей проверки регистрации'; $consecutiveErrors = 0
                    } else {
                        $email = $name + '@gmail.com'
                        $googleBody = 'f.req=[' + $googleSetupToken + ',"","","' + $email + '"]'
                        $googleCode = ''
                        $googleEndpoints = @('https://accounts.google.com/_/signup/usernameavailability?hl=en','https://accounts.google.com/_/signup/webusernameavailability')
                        foreach ($googleEndpoint in $googleEndpoints) {
                            $r = Get-HttpResult -Url $googleEndpoint -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='*/*'; 'Google-Accounts-Xsrf'='1'; 'Origin'='https://accounts.google.com'; 'Referer'='https://accounts.google.com/signup/v2/webcreateaccount?service=mail&flowEntry=SignUp'} -Method Post -Body $googleBody -ContentType 'application/x-www-form-urlencoded; charset=UTF-8' -WebSession $googleSession
                            $httpStatus = [int]$r.Code
                            if ($httpStatus -eq 200) {
                                $bodyText = ([string]$r.Content).Trim()
                                if ($bodyText -match '(?is)\[\s*null\s*,\s*([12])\s*(?:,|\])') { $googleCode = $Matches[1] }
                                elseif ($bodyText -match '(?i)"(?:usernameAvailable|available)"\s*:\s*(true|false)') { if ($Matches[1] -ieq 'true') { $googleCode = '1' } else { $googleCode = '2' } }
                                elseif ($bodyText -match '(?i)IDENTIFIER_EXISTS|username.{0,80}(?:taken|not available)|email.{0,80}already') { $googleCode = '2' }
                            }
                            if ($googleCode) { break }
                            if ($httpStatus -eq 429 -or $httpStatus -ge 500) { break }
                        }
                        if ($googleCode -eq '1') { $status='Свободен'; $reason='Регистрационный валидатор Google сообщил, что имя Gmail доступно'; $consecutiveErrors=0 }
                        elseif ($googleCode -eq '2') { $status='Занят'; $reason='Регистрационный валидатор Google сообщил, что имя Gmail занято'; $consecutiveErrors=0 }
                        else { $status='Не подтверждено'; $reason='Google не вернул распознаваемый код доступности Gmail'; $consecutiveErrors=0 }
                    }
                }
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
                'VK' {
                    $url = 'https://api.vk.com/method/utils.resolveScreenName?screen_name=' + [uri]::EscapeDataString($name) + '&v=5.199'
                    $r = Get-HttpResult -Url $url -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'}
                    $httpStatus = [int]$r.Code
                    if ($httpStatus -eq 200) {
                        $response = ConvertFrom-Json -InputObject $r.Content -ErrorAction Stop
                        if ($null -ne $response.response -and $response.response.object_id) { $status='Занят'; $reason='VK разрешил screen name в существующий профиль'; $consecutiveErrors=0 }
                        elseif ($null -ne $response.PSObject.Properties['response'] -and $null -eq $response.response) { $status='Вероятно свободен'; $reason='VK не разрешил screen name в публичный профиль; зарезервированные имена могут быть недоступны'; $consecutiveErrors=0 }
                        else {
                            $profileUrl = 'https://vk.com/' + [uri]::EscapeDataString($name)
                            $pr = Get-HttpResult -Url $profileUrl -Timeout $timeoutSec -Headers $browserHeaders
                            $httpStatus = [int]$pr.Code
                            if ($pr.Content -match ('(?is)id="profile_short"|id="profile_full"|"screen_name"\s*:\s*"' + [regex]::Escape($name) + '"')) { $status='Занят'; $reason='Публичный профиль VK найден'; $consecutiveErrors=0 }
                            elseif ([int]$pr.Code -eq 404 -or $pr.Content -match '(?i)страница удалена|пользователь не найден|page not found|profile is unavailable') { $status='Вероятно свободен'; $reason='VK не нашёл публичный профиль с таким screen name; имя может быть зарезервировано'; $consecutiveErrors=0 }
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
                'TikTok' {
                    $normalizedTikTokName = $name.ToLowerInvariant()
                    $checkUrl = 'https://www.tiktok.com/passport/web/account/check_name/?aid=1459&app_language=en&app_name=tiktok_web'
                    $checkBody = ConvertTo-Json -InputObject @{username=$normalizedTikTokName; unique_id=$normalizedTikTokName} -Compress
                    $r = Get-HttpResult -Url $checkUrl -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json, text/plain, */*'; 'Origin'='https://www.tiktok.com'; 'Referer'='https://www.tiktok.com/signup'; 'Content-Type'='application/json'} -Method Post -Body $checkBody -ContentType 'application/json; charset=UTF-8'
                    $httpStatus = [int]$r.Code
                    $checkedBySignupEndpoint = $false
                    if ($httpStatus -eq 200) {
                        try {
                            $response = ConvertFrom-Json -InputObject $r.Content -ErrorAction Stop
                            $availableProperty = $response.PSObject.Properties['is_available']
                            if ($null -eq $availableProperty -and $null -ne $response.data) { $availableProperty = $response.data.PSObject.Properties['is_available'] }
                            if ($null -eq $availableProperty -and $null -ne $response.data) { $availableProperty = $response.data.PSObject.Properties['isAvailable'] }
                            if ($null -ne $availableProperty) {
                                $checkedBySignupEndpoint = $true
                                if ([bool]$availableProperty.Value) { $status='Свободен'; $reason='Регистрационный endpoint TikTok сообщил, что username доступен'; $consecutiveErrors=0 }
                                else { $status='Занят'; $reason='Регистрационный endpoint TikTok сообщил, что username недоступен'; $consecutiveErrors=0 }
                            } elseif ($null -ne $response.data -and $null -ne $response.data.PSObject.Properties['is_valid'] -and -not [bool]$response.data.is_valid) {
                                $checkedBySignupEndpoint = $true; $status='Недопустимый'; $reason='TikTok отклонил формат имени'; $consecutiveErrors=0
                            }
                        } catch { }
                    }
                    if (-not $checkedBySignupEndpoint -and $httpStatus -ne 429 -and $httpStatus -lt 500) {
                        $url = 'https://www.tiktok.com/@' + [uri]::EscapeDataString($normalizedTikTokName)
                        $r = Get-HttpResult -Url $url -Timeout $timeoutSec -Headers $browserHeaders
                        $httpStatus = [int]$r.Code
                        $content = [string]$r.Content
                        $escapedForRegex = [regex]::Escape($normalizedTikTokName)
                        if ($httpStatus -eq 200 -and $content -match ('(?is)"userInfo"\s*:\s*\{.*?"user"\s*:\s*\{.*?"uniqueId"\s*:\s*"' + $escapedForRegex + '"')) { $status='Занят'; $reason='Найден публичный профиль TikTok с этим uniqueId'; $consecutiveErrors=0 }
                        elseif ($httpStatus -eq 200 -and $content -match '(?i)"statusCode"\s*:\s*(10202|10221)|user not found|account not found') { $status='Вероятно свободен'; $reason='TikTok сообщает, что публичный профиль не найден; зарезервированные имена могут быть недоступны'; $consecutiveErrors=0 }
                        elseif ($httpStatus -eq 404) { $status='Вероятно свободен'; $reason='TikTok вернул 404 для страницы профиля; имя может быть зарезервировано'; $consecutiveErrors=0 }
                        else { $status='Не подтверждено'; $reason='TikTok не выдал распознаваемый регистрационный ответ и скрыл/не нашёл однозначные данные профиля'; $consecutiveErrors=0 }
                    }
                }
                'Microsoft' {
                    if ($null -eq $msContext -or $null -eq $msSession -or -not $msContext.apiCanary) {
                        $signInName = $name + '@hotmail.com'
                        $credentialBody = ConvertTo-Json -InputObject @{username=$signInName; isOtherIdEntry=$true} -Compress
                        $r = Get-HttpResult -Url 'https://login.live.com/GetCredentialType.srf' -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'; 'Content-Type'='application/json'; 'Origin'='https://login.live.com'; 'Referer'='https://login.live.com/'} -Method Post -Body $credentialBody -ContentType 'application/json; charset=UTF-8'
                        $httpStatus = [int]$r.Code
                        if ($httpStatus -eq 200) {
                            $credentialResponse = ConvertFrom-Json -InputObject $r.Content -ErrorAction Stop
                            if ($null -ne $credentialResponse.PSObject.Properties['IfExistsResult']) {
                                $credentialCode = [int]$credentialResponse.IfExistsResult
                                if ($credentialCode -eq 0) { $status='Вероятно свободен'; $reason='Microsoft: Microsoft не нашёл существующий аккаунт, но регистрационная доступность отдельно не подтверждена'; $consecutiveErrors=0 }
                                elseif ($credentialCode -eq 1) { $status='Занят'; $reason='Microsoft: Microsoft сообщил о существующем аккаунте'; $consecutiveErrors=0 }
                                elseif ($credentialCode -eq 5 -or $credentialCode -eq 6) { $status='Не подтверждено'; $reason='Microsoft: Microsoft вернул доменную/регистрационную ошибку'; $consecutiveErrors=0 }
                                else { $status='Не подтверждено'; $reason='Microsoft: неизвестный IfExistsResult=' + $credentialCode; $consecutiveErrors=0 }
                            } else { $status='Не подтверждено'; $reason='Microsoft: GetCredentialType не вернул IfExistsResult'; $consecutiveErrors=0 }
                        } else { $status='Не подтверждено'; $reason='Microsoft: ни регистрационный контекст, ни проверка GetCredentialType не дали подтверждённого статуса'; $consecutiveErrors=0 }
                    } else {
                        $signInName = $name + '@hotmail.com'
                        $hpgid = $null
                        try { $hpgid = $msContext.cpgids.Signup_MemberNamePage_Client } catch { }
                        $payload = @{signInName=$signInName; includeSuggestions=$false; uaid=$msContext.uaid; uiflvr=$msContext.uiflvr; scid=$msContext.scid; hpgid=$hpgid} | ConvertTo-Json -Compress
                        $r = Get-HttpResult -Url 'https://signup.live.com/API/CheckAvailableSigninNames' -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'; 'canary'=[string]$msContext.apiCanary; 'Origin'='https://signup.live.com'; 'Referer'='https://signup.live.com/'} -Method Post -Body $payload -ContentType 'application/json; charset=UTF-8' -WebSession $msSession
                        $httpStatus = [int]$r.Code
                        if ($httpStatus -eq 200) {
                            $response = ConvertFrom-Json -InputObject $r.Content -ErrorAction Stop
                            $availableProperty = $response.PSObject.Properties['isAvailable']
                            if ($null -ne $availableProperty) {
                                if ([bool]$availableProperty.Value) { $status='Свободен'; $reason='Microsoft сообщил, что адрес @hotmail.com доступен'; $consecutiveErrors=0 }
                                else { $status='Занят'; $reason='Microsoft сообщил, что адрес @hotmail.com недоступен или зарезервирован'; $consecutiveErrors=0 }
                            } elseif ($null -ne $response.PSObject.Properties['IfExistsResult']) {
                                $existsCode = [int]$response.IfExistsResult
                                if ($existsCode -eq 0) { $status='Вероятно свободен'; $reason='Microsoft: Microsoft не обнаружил существующий аккаунт; проверь окончательную доступность при регистрации'; $consecutiveErrors=0 }
                                elseif ($existsCode -eq 1) { $status='Занят'; $reason='Microsoft: Microsoft обнаружил существующий аккаунт'; $consecutiveErrors=0 }
                                elseif ($existsCode -in @(5,6)) { $status='Не подтверждено'; $reason='Microsoft: Microsoft вернул код доменной/регистрационной ошибки ' + $existsCode; $consecutiveErrors=0 }
                                else { $status='Не подтверждено'; $reason='Microsoft: неизвестный IfExistsResult=' + $existsCode; $consecutiveErrors=0 }
                            } else { $status='Не подтверждено'; $reason='Microsoft вернул неизвестную структуру ответа'; $consecutiveErrors=0 }
                        }
                    }
                }
                'Outlook' {
                    if ($null -eq $msContext -or $null -eq $msSession -or -not $msContext.apiCanary) {
                        $signInName = $name + '@outlook.com'
                        $credentialBody = ConvertTo-Json -InputObject @{username=$signInName; isOtherIdEntry=$true} -Compress
                        $r = Get-HttpResult -Url 'https://login.live.com/GetCredentialType.srf' -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'; 'Content-Type'='application/json'; 'Origin'='https://login.live.com'; 'Referer'='https://login.live.com/'} -Method Post -Body $credentialBody -ContentType 'application/json; charset=UTF-8'
                        $httpStatus = [int]$r.Code
                        if ($httpStatus -eq 200) {
                            $credentialResponse = ConvertFrom-Json -InputObject $r.Content -ErrorAction Stop
                            if ($null -ne $credentialResponse.PSObject.Properties['IfExistsResult']) {
                                $credentialCode = [int]$credentialResponse.IfExistsResult
                                if ($credentialCode -eq 0) { $status='Вероятно свободен'; $reason='Outlook: Microsoft не нашёл существующий аккаунт, но регистрационная доступность отдельно не подтверждена'; $consecutiveErrors=0 }
                                elseif ($credentialCode -eq 1) { $status='Занят'; $reason='Outlook: Microsoft сообщил о существующем аккаунте'; $consecutiveErrors=0 }
                                elseif ($credentialCode -eq 5 -or $credentialCode -eq 6) { $status='Не подтверждено'; $reason='Outlook: Microsoft вернул доменную/регистрационную ошибку'; $consecutiveErrors=0 }
                                else { $status='Не подтверждено'; $reason='Outlook: неизвестный IfExistsResult=' + $credentialCode; $consecutiveErrors=0 }
                            } else { $status='Не подтверждено'; $reason='Outlook: GetCredentialType не вернул IfExistsResult'; $consecutiveErrors=0 }
                        } else { $status='Не подтверждено'; $reason='Outlook: ни регистрационный контекст, ни проверка GetCredentialType не дали подтверждённого статуса'; $consecutiveErrors=0 }
                    } else {
                        $signInName = $name + '@outlook.com'
                        $hpgid = $null
                        try { $hpgid = $msContext.cpgids.Signup_MemberNamePage_Client } catch { }
                        $payload = @{signInName=$signInName; includeSuggestions=$false; uaid=$msContext.uaid; uiflvr=$msContext.uiflvr; scid=$msContext.scid; hpgid=$hpgid} | ConvertTo-Json -Compress
                        $r = Get-HttpResult -Url 'https://signup.live.com/API/CheckAvailableSigninNames' -Timeout $timeoutSec -Headers @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'; 'canary'=[string]$msContext.apiCanary; 'Origin'='https://signup.live.com'; 'Referer'='https://signup.live.com/'} -Method Post -Body $payload -ContentType 'application/json; charset=UTF-8' -WebSession $msSession
                        $httpStatus = [int]$r.Code
                        if ($httpStatus -eq 200) {
                            $response = ConvertFrom-Json -InputObject $r.Content -ErrorAction Stop
                            $availableProperty = $response.PSObject.Properties['isAvailable']
                            if ($null -ne $availableProperty) {
                                if ([bool]$availableProperty.Value) { $status='Свободен'; $reason='Outlook сообщил, что адрес @outlook.com доступен'; $consecutiveErrors=0 }
                                else { $status='Занят'; $reason='Outlook сообщил, что адрес @outlook.com недоступен или зарезервирован'; $consecutiveErrors=0 }
                            } elseif ($null -ne $response.PSObject.Properties['IfExistsResult']) {
                                $existsCode = [int]$response.IfExistsResult
                                if ($existsCode -eq 0) { $status='Вероятно свободен'; $reason='Outlook: Microsoft не обнаружил существующий аккаунт; проверь окончательную доступность при регистрации'; $consecutiveErrors=0 }
                                elseif ($existsCode -eq 1) { $status='Занят'; $reason='Outlook: Microsoft обнаружил существующий аккаунт'; $consecutiveErrors=0 }
                                elseif ($existsCode -in @(5,6)) { $status='Не подтверждено'; $reason='Outlook: Microsoft вернул код доменной/регистрационной ошибки ' + $existsCode; $consecutiveErrors=0 }
                                else { $status='Не подтверждено'; $reason='Outlook: неизвестный IfExistsResult=' + $existsCode; $consecutiveErrors=0 }
                            } else { $status='Не подтверждено'; $reason='Outlook вернул неизвестную структуру ответа'; $consecutiveErrors=0 }
                        }
                    }
                }
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
                        # Анонимный лимит API GitHub — 60 запросов в час. Останавливаемся, когда
                        # запас исчерпан, а не после первого 403, чтобы не долбить сервис.
                        $rateRemaining = -1
                        try {
                            if ($null -ne $r.Headers) {
                                $rawRemaining = [string]$r.Headers['X-RateLimit-Remaining']
                                if (-not [string]::IsNullOrWhiteSpace($rawRemaining)) { $rateRemaining = [int]$rawRemaining }
                            }
                        } catch { }
                        if ($httpStatus -eq 200) { $status='Занят'; $reason='Публичный профиль GitHub найден'; $consecutiveErrors=0 }
                        elseif ($httpStatus -eq 404) { $status='Вероятно свободен'; $reason='Профиль GitHub не найден; имя может быть зарезервировано регистрационной формой'; $consecutiveErrors=0 }
                        elseif ($httpStatus -eq 403) { $status='Ошибка сети'; $reason='GitHub ограничил анонимный API (403/возможный лимит)'; $stopReason='GitHub ограничил запросы; проверка остановлена' }
                        if ($rateRemaining -eq 0 -and -not $stopReason) {
                            $stopReason = 'Исчерпан часовой лимит анонимного API GitHub (60 запросов); проверка остановлена. Повтори позже или используй только регистрационный endpoint.'
                        }
                    }
                }
                'YouTube' {
                    $url = 'https://www.youtube.com/@' + [uri]::EscapeDataString($name)
                    $r = Get-HttpResult -Url $url -Timeout $timeoutSec -Headers $browserHeaders
                    $httpStatus = [int]$r.Code
                    $content = [string]$r.Content
                    $escapedHandle = [regex]::Escape($name)
                    $matchingCanonical = $content -match ('(?is)"canonicalBaseUrl"\s*:\s*"/@' + $escapedHandle + '"') -or $content -match ('(?is)<link[^>]+rel="canonical"[^>]+href="https?://www\.youtube\.com/@' + $escapedHandle + '"')
                    $channelMetadata = $content -match '(?is)"channelMetadataRenderer"\s*:\s*\{'
                    if ($httpStatus -eq 200 -and $matchingCanonical -and $channelMetadata) { $status='Занят'; $reason='YouTube вернул страницу канала, canonical handle совпадает с запрошенным'; $consecutiveErrors=0 }
                    elseif (($httpStatus -eq 404 -or $content -match '(?i)channelNotFound|This page isn.t available|channel does not exist') -and -not $channelMetadata) { $status='Вероятно свободен'; $reason='YouTube не нашёл канал с этим handle; зарезервированность имени не исключена'; $consecutiveErrors=0 }
                    else { $status='Не подтверждено'; $reason='Публичная страница не подтвердила ни существование канала с этим canonical handle, ни регистрационную доступность'; $consecutiveErrors=0 }
                }
                'Telegram' {
                    $url = 'https://t.me/' + [uri]::EscapeDataString($name)
                    $r = Get-HttpResult -Url $url -Timeout $timeoutSec -Headers $browserHeaders
                    $httpStatus = [int]$r.Code
                    $content = [string]$r.Content
                    $normalizedHandle = [regex]::Escape($name)
                    $directHandleMarker = $content -match ('(?is)class="tgme_page_extra"[^>]*>\s*@?' + $normalizedHandle + '\s*</')
                    $hasProfileTitle = $content -match '(?is)class="tgme_page_title"[^>]*>\s*<span[^>]*>\s*[^<\s][^<]*</span>'
                    $hasProfileData = $content -match '(?i)tgme_page_photo|tgme_page_profile|tgme_page_extra'
                    $genericNotFound = $content -match '(?i)this user doesn.t seem to exist|page not found|username not found|tgme_page_error'
                    if ($httpStatus -eq 200 -and -not $genericNotFound -and ($directHandleMarker -or ($hasProfileTitle -and $hasProfileData -and $content -notmatch '(?i)if you have telegram|contact @'))) { $status='Занят'; $reason='Публичная страница Telegram содержит данные целевого профиля/канала'; $consecutiveErrors=0 }
                    elseif ($httpStatus -eq 404 -or $genericNotFound) { $status='Вероятно свободен'; $reason='Публичная страница Telegram не найдена; авторизованный метод может выявить резервирование'; $consecutiveErrors=0 }
                    else { $status='Не подтверждено'; $reason='Публичная страница не дала однозначного результата; account.checkUsername требует авторизованной пользовательской сессии'; $consecutiveErrors=0 }
                }
                'Apple' {
                    if ($null -eq $appleSession) {
                        $appleSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                        $appleInit = Get-HttpResult -Url 'https://appleid.apple.com/account' -Timeout $timeoutSec -Headers $browserHeaders -WebSession $appleSession
                        $apiKeyMatch = [regex]::Match([string]$appleInit.Content, '(?i)(?:X-Apple-Api-Key|apiKey)\s*["''\s:=]+([A-Za-z0-9_-]{20,})')
                        if ($apiKeyMatch.Success) { $appleApiKey = $apiKeyMatch.Groups[1].Value }
                    }
                    $appleEmail = $name + '@icloud.com'
                    $appleHeaders = @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json, text/javascript, */*; q=0.01'; 'Content-Type'='application/json'; 'Origin'='https://appleid.apple.com'; 'Referer'='https://appleid.apple.com/account'; 'X-Requested-With'='XMLHttpRequest'; 'X-Apple-Request-Context'='create'}
                    if ($appleApiKey) { $appleHeaders['X-Apple-Api-Key'] = $appleApiKey }
                    try {
                        $appleCookies = $appleSession.Cookies.GetCookies([uri]'https://appleid.apple.com')
                        foreach ($cookie in $appleCookies) { if ($cookie.Name -eq 'scnt') { $appleHeaders['scnt'] = $cookie.Value }; if ($cookie.Name -eq 'aidsp') { $appleHeaders['X-Apple-ID-Session-Id'] = $cookie.Value } }
                    } catch { }
                    $appleBody = ConvertTo-Json -InputObject @{emailAddress=$appleEmail} -Compress
                    $r = Get-HttpResult -Url 'https://appleid.apple.com/account/validation/appleid' -Timeout $timeoutSec -Headers $appleHeaders -Method Post -Body $appleBody -ContentType 'application/json; charset=UTF-8' -WebSession $appleSession
                    $httpStatus = [int]$r.Code
                    if ($httpStatus -eq 200) {
                        try {
                            $response = ConvertFrom-Json -InputObject $r.Content -ErrorAction Stop
                            if ($null -ne $response.PSObject.Properties['used']) {
                                if ([bool]$response.used) { $status='Занят'; $reason='Apple сообщил, что указанный адрес уже используется'; $consecutiveErrors=0 }
                                else { $status='Вероятно свободен'; $reason='Apple не сообщил, что адрес уже используется; окончательное подтверждение выполняется при создании Apple Account'; $consecutiveErrors=0 }
                            } elseif ($null -ne $response.PSObject.Properties['emailAddress'] -and $null -ne $response.PSObject.Properties['valid']) {
                                if (-not [bool]$response.valid) { $status='Недопустимый'; $reason='Apple отклонил формат адреса'; $consecutiveErrors=0 }
                                else { $status='Не подтверждено'; $reason='Apple подтвердил формат, но не вернул флаг занятости адреса'; $consecutiveErrors=0 }
                            } else { $status='Не подтверждено'; $reason='Apple не вернул распознаваемый результат проверки адреса'; $consecutiveErrors=0 }
                        } catch { $status='Не подтверждено'; $reason='Apple вернул нераспознанный ответ проверки'; $consecutiveErrors=0 }
                    } elseif ($httpStatus -eq 400 -and [string]$r.Content -match '(?i)already.*used|email.*used') {
                        $status='Занят'; $reason='Apple отклонил адрес как уже используемый'; $consecutiveErrors=0
                    } else { $status='Не подтверждено'; $reason='Apple потребовал дополнительный контекст/защитные параметры либо изменил endpoint; доступность адреса не подтверждена'; $consecutiveErrors=0 }
                }
                default {
                    $status='Не подтверждено'
                    $reason='Платформа не вернула проверяемый статус доступности через доступный интерфейс'
                    $consecutiveErrors=0
                }
            }
            if ($null -ne $r -and [string]$r.TransportKind -eq 'protocol') {
                # Нарушение протокола (например, редирект POST→GET с телом) — это не «сеть упала»,
                # а системная проблема запроса: не считаем её сетевой ошибкой, но и не долбим сервис.
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
                # Сброс обязателен: иначе значение Retry-After от прошлого ника
                # переиспользовалось бы для текущего.
                $retryAfter = 0
                try { if ($null -ne $r -and $r.Headers['Retry-After']) { $retryAfter = [int]$r.Headers['Retry-After'] } } catch { }
                if ($retryAfter -lt 0) { $retryAfter = 0 }
                if ($retryAfter -gt 120) { $retryAfter = 120 }
                # Мультипликативный рост паузы; Retry-After служит нижним порогом.
                $currentDelayMs = [Math]::Min($maxDelayMs,[Math]::Max($currentDelayMs * 2, $retryAfter * 1000))
                $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=("HTTP 429 для {0} ({1}). Пауза увеличена до {2} мс; ограничение подряд: {3} из 3." -f $name,$Platform,$currentDelayMs,$consecutiveRateLimits)})
                if ($retryAfter -gt 0) {
                    $waitUntil = [DateTime]::UtcNow.AddSeconds($retryAfter)
                    while ([DateTime]::UtcNow -lt $waitUntil -and -not $Cancellation.IsCancellationRequested) { Start-Sleep -Milliseconds 100 }
                }
                $status = 'Ошибка сети'; $reason = "HTTP 429 — ограничение частоты запросов $Platform; пауза увеличена"
                # Единичный 429 больше не обрывает прогон: воркер откатывает темп и
                # продолжает. Остановка — только если платформа упорно ограничивает.
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
        # Аддитивное снижение паузы: после серии ответов без ограничения частоты темп
        # постепенно возвращается к стартовому, но не ниже пола профиля платформы.
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
        $null = $Queue.Enqueue([pscustomobject]@{Type='Progress'; Item=[pscustomobject]@{Name=$name; Platform=$Platform; Category=[string]$item.Category; Structure=[string]$item.Structure; Meaning=[string]$item.Meaning; Status=$status; Reason=$reason; ErrorDetail=$errorDetail; Time=$now; Index=$done; Total=$total}})
        if ($errorDetail) { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=("{0} ({1}): {2}" -f $name,$Platform,$errorDetail)}) }
        if (-not $stopReason -and $consecutiveProtocolErrors -ge 3) {
            $stopReason = "Три запроса подряд к $Platform отклонены на уровне протокола/антибот-защиты; проверка остановлена. Endpoint мог измениться."
        }
        if ($stopReason -or $consecutiveErrors -ge 3) {
            if (-not $stopReason) { $stopReason = 'Три сетевые ошибки подряд; проверка остановлена для защиты от повторных запросов' }
            break
        }
        if ($done -lt $total) {
            $elapsed = 0
            while ($elapsed -lt $currentDelayMs -and -not $Cancellation.IsCancellationRequested) {
                $step = [Math]::Min(100,($currentDelayMs - $elapsed))
                Start-Sleep -Milliseconds $step
                $elapsed += $step
            }
        }
    }
    $null = $Queue.Enqueue([pscustomobject]@{Type='Complete'; Cancelled=[bool]$Cancellation.IsCancellationRequested; Error=$null; StopReason=$stopReason; Checked=$done; Total=$total})
} catch {
    $null = $Queue.Enqueue([pscustomobject]@{Type='Complete'; Cancelled=[bool]$Cancellation.IsCancellationRequested; Error=$_.Exception.ToString(); StopReason=$stopReason; Checked=$done; Total=$total})
}
'@
    $script:StartButton.Enabled = $false
    $script:GenerateButton.Enabled = $false
    $script:StopButton.Enabled = $true
    $script:CategoryList.Enabled = $false
    $script:CountBox.Enabled = $false
    $script:NumbersCheck.Enabled = $false
    $script:UnderscoreCheck.Enabled = $false
    $script:CustomBox.Enabled = $false
    $script:ThemeBox.Enabled = $false
    $script:ManualNickBox.Enabled = $false
    $script:DelayBox.Enabled = $false
    $script:TimeoutBox.Enabled = $false
    $script:PlatformBox.Enabled = $false
    try {
        $script:CheckQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $script:Cancellation = New-Object System.Threading.CancellationTokenSource
        $script:WorkerRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $script:WorkerRunspace.Open()
        $script:WorkerPowerShell = [powershell]::Create()
        $script:WorkerPowerShell.Runspace = $script:WorkerRunspace
        [void]$script:WorkerPowerShell.AddScript($workerScript).AddArgument(@($validCandidates.ToArray())).AddArgument($script:CheckQueue).AddArgument($script:Cancellation).AddArgument([int]$script:DelayBox.Value).AddArgument([int]$script:TimeoutBox.Value).AddArgument([string]$selectedPlatform).AddArgument([string]$script:AppVersion)
        $script:CompletionEvent = $null
        $script:UnhandledWorkerError = $null
        $script:AsyncHandle = $script:WorkerPowerShell.BeginInvoke()
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
                $script:CurrentBatchDone = [int]$item.Index
                $script:ProgressBar.Value = [Math]::Min(100,[int](100 * $script:CurrentBatchDone / [Math]::Max(1,$script:CurrentBatchTotal)))
                $script:ProgressCaption.Text = "Прогресс: $($script:CurrentBatchDone)/$($script:CurrentBatchTotal) · $($item.Name)"
                $script:GridRefreshPending = $true
            } elseif ($entry.Type -eq 'Log') {
                Add-Diagnostic ([string]$entry.Message)
            } elseif ($entry.Type -eq 'Complete') {
                $script:CompletionEvent = $entry
            }
            $entry = $null
        }
    }
    # Таблица перерисовывается не на каждый результат, а не чаще ~4 раз в секунду:
    # полная перестройка строк на каждую проверку заметно тормозила интерфейс.
    if ($script:GridRefreshPending -and (([DateTime]::UtcNow - $script:LastGridRefresh).TotalMilliseconds -ge 250)) {
        $script:GridRefreshPending = $false
        $script:LastGridRefresh = [DateTime]::UtcNow
        Update-ResultGrid
    }
    Flush-HistoryIfDue -IntervalSeconds 5
    if ($script:AsyncHandle -and $script:AsyncHandle.IsCompleted) {
        $script:PollTimer.Stop()
        try { $null = $script:WorkerPowerShell.EndInvoke($script:AsyncHandle) } catch { $script:UnhandledWorkerError = $_.Exception.ToString() }
        if ($script:CheckQueue) {
            $entry = $null
            while ($script:CheckQueue.TryDequeue([ref]$entry)) {
                if ($entry.Type -eq 'Progress') {
                    $item = $entry.Item
                    $candidate = Find-Candidate -Name ([string]$item.Name) -Platform ([string]$item.Platform)
                    if ($candidate) { $script:CheckedNames[((([string]$candidate.Platform) + '|' + [string]$candidate.Name).ToLowerInvariant())] = $true; $candidate.Status=[string]$item.Status; $candidate.Time=[string]$item.Time; $candidate.Reason=[string]$item.Reason; $candidate.Checked=$true; Update-FreeHistoryFromCandidate $candidate; Touch-Candidates }
                    $script:CurrentBatchDone = [int]$item.Index
                } elseif ($entry.Type -eq 'Log') { Add-Diagnostic ([string]$entry.Message) }
                elseif ($entry.Type -eq 'Complete') { $script:CompletionEvent = $entry }
                $entry = $null
            }
        }
        $completed = $script:CompletionEvent
        $unhandledError = $script:UnhandledWorkerError
        $workerErrors = ''
        try { if ($script:WorkerPowerShell -and $script:WorkerPowerShell.Streams.Error.Count -gt 0) { $workerErrors = ($script:WorkerPowerShell.Streams.Error | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine } } catch { }
        Close-CheckRunspace
        Reset-CheckControls
        if ($completed -and ($completed.Cancelled -or $completed.StopReason)) {
            foreach ($candidate in $script:Candidates) {
                if ($candidate.Status -eq 'Проверяется') { $candidate.Status='Ожидает'; $candidate.Reason='Проверка не завершена; можно запустить повторно' }
            }
        }
        # Таймер после завершения останавливается, поэтому сбрасываем историю на диск здесь.
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
            $script:SummaryLabel.Text = "Остановлено · проверено: $($completed.Checked) · свободно: $($script:AvailableNames.Count)"
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
    if ($script:AsyncHandle -and -not $script:AsyncHandle.IsCompleted) { return }
    if ([int]$script:MinLengthBox.Value -gt [int]$script:MaxLengthBox.Value) {
        [System.Windows.Forms.MessageBox]::Show('Минимальная длина не может быть больше максимальной.','Настройки','OK','Warning') | Out-Null
        return
    }
    $platform = [string]$script:PlatformBox.SelectedItem
    $categories = @($script:CategoryList.CheckedItems | ForEach-Object { [string]$_ })
    $customWords = Get-TextBoxValue $script:CustomBox
    $customTheme = Get-TextBoxValue $script:ThemeBox
    $excludeTokens = @($script:ExcludeBox.Text -split '[,;\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $seen = @{}
    foreach ($existing in $script:Candidates) { $existingPlatform = [string]$existing.Platform; if (-not $existingPlatform) { $existingPlatform = 'Roblox' }; $seen[(($existingPlatform + '|' + [string]$existing.Name).ToLowerInvariant())] = $true }
    # Исключения собираются ДО генерации и передаются в генератор: он отсеивает занятые
    # и уже проверенные ники сам и добирает замену, поэтому запрошенное количество
    # совпадает с результатом. Раньше отсев шёл после получения списка без добора,
    # и вместо 40 ников в таблицу попадало 37, а вместо 200 — 187.
    $excludeKeys = @{}
    foreach ($existingKey in $seen.Keys) { $excludeKeys[[string]$existingKey] = $true }
    foreach ($retiredKey in $script:RetiredNames.Keys) { $excludeKeys[[string]$retiredKey] = $true }
    if ($script:ExcludeCheckedCheck.Checked) {
        foreach ($checkedKey in $script:CheckedNames.Keys) { $excludeKeys[[string]$checkedKey] = $true }
    }
    $requestedCount = [int]$script:CountBox.Value
    $candidates = @(New-AdvancedCandidatePool -SelectedWordCategories $categories -CustomWords $customWords -CustomTheme $customTheme -Style ([string]$script:StyleBox.SelectedItem) -Platform $platform -Prefix $script:PrefixBox.Text -Suffix $script:SuffixBox.Text -MinLength ([int]$script:MinLengthBox.Value) -MaxLength ([int]$script:MaxLengthBox.Value) -Count $requestedCount -UseNumbers ([bool]$script:NumbersCheck.Checked) -UseUnderscore ([bool]$script:UnderscoreCheck.Checked) -OneWord ([bool]$script:OneWordCheck.Checked) -TwoWords ([bool]$script:TwoWordsCheck.Checked) -OnlyShort ([bool]$script:ShortOnlyCheck.Checked) -ExcludeTokens $excludeTokens -ExcludeKeys $excludeKeys)
    $poolStats = $script:GenerationStats
    if ($null -eq $poolStats) { $poolStats = @{} }
    if ($candidates.Count -lt $requestedCount) {
        Add-Diagnostic ("Создано {0} из {1}: пространство имён исчерпано при текущих фильтрах. Отсеяно — по длине {2}, по формату платформы {3}, по словам-исключениям {4}, повторов {5}, уже проверено/занято {6}." -f $candidates.Count, $requestedCount, $poolStats['ByLength'], $poolStats['ByFormat'], $poolStats['ByExcludedToken'], $poolStats['ByDuplicate'], $poolStats['ByAlreadyUsed'])
    }
    if ($candidates.Count -eq 0 -and [string]::IsNullOrWhiteSpace($script:ManualNickBox.Text)) {
        [System.Windows.Forms.MessageBox]::Show('Не удалось создать ники. Выбери хотя бы одну категорию или введи свои слова. Проверь длину и фильтры исключения.','Нет вариантов','OK','Warning') | Out-Null
        return
    }
    $added = 0
    $dropped = 0
    foreach ($candidate in $candidates) {
        $key = (($platform + '|' + [string]$candidate.Name).ToLowerInvariant())
        # Страховка: генератор уже отсек эти ключи, но список мог измениться за время работы.
        if ($script:RetiredNames.ContainsKey($key)) { $dropped++; continue }
        if ($script:ExcludeCheckedCheck.Checked -and $script:CheckedNames.ContainsKey($key)) { $dropped++; continue }
        if ($seen.ContainsKey($key)) { $dropped++; continue }
        [void]$script:Candidates.Add($candidate)
        Register-Candidate $candidate
        $seen[$key] = $true
        $added++
    }
    if ($dropped -gt 0) { Add-Diagnostic ("Отброшено после генерации: {0} (совпали с уже проверенными или занятыми)." -f $dropped) }
    foreach ($nickRaw in ($script:ManualNickBox.Text -split '[,;\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $nick = $nickRaw.Trim()
        $key = (($platform + '|' + $nick).ToLowerInvariant())
        if ($seen.ContainsKey($key) -or $script:RetiredNames.ContainsKey($key)) { continue }
        $status = 'Ожидает'; $reason = 'Ожидает проверки'
        if (-not (Test-UsernameFormat -Username $nick -Platform $platform)) { $status = 'Недопустимый'; $reason = "Неверный формат имени для платформы $platform" }
        $manualTime = ''
        if ($status -eq 'Недопустимый') { $manualTime = (Get-Date).ToString('HH:mm:ss') }
        $manualCandidate = [pscustomobject]@{Name=$nick; Platform=$platform; Meaning='Введён вручную'; Category='Ручной ввод'; Structure=(Get-NickStructure -Name $nick); Status=$status; Time=$manualTime; Reason=$reason; Checked=($status -eq 'Недопустимый')}
        [void]$script:Candidates.Add($manualCandidate)
        Register-Candidate $manualCandidate
        $seen[$key]=$true; $added++
    }
    Touch-Candidates
    # Порог поднят до 5000: максимум количества за одну генерацию теперь 2000, и прежний
    # порог 2000 срабатывал бы сразу после запрошенного большого прогона.
    # Это предупреждение, а не запрет — работа не прерывается.
    if ($script:Candidates.Count -gt 5000) { [System.Windows.Forms.MessageBox]::Show('В списке больше 5000 записей: таблица может перерисовываться медленнее. Экспортируй результаты или очисти список.','Размер списка','OK','Information') | Out-Null }
    Update-ResultGrid
    if ($added -eq $requestedCount) {
        Add-Diagnostic ("Для платформы {0} создано ровно {1} ников. Всего в таблице: {2}." -f $platform, $added, $script:Candidates.Count)
    } else {
        Add-Diagnostic ("Для платформы {0} добавлено новых ников: {1} из запрошенных {2}. Всего в таблице: {3}." -f $platform, $added, $requestedCount, $script:Candidates.Count)
    }
    $script:SummaryLabel.Text = "Сгенерировано: $added · автоматическая проверка запускается"
    if ($added -gt 0) { Start-Checking -RetryErrorsOnly $false }
})

$script:StartButton.Add_Click({ Start-Checking -RetryErrorsOnly $false })
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
    if ($script:AvailableNames.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Пока нет подтверждённых или вероятных вариантов.','Сохранение','OK','Information') | Out-Null; return }
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'Текстовый файл (*.txt)|*.txt'
    $dialog.FileName = 'Universal_Usernames_Free_Or_Possible_' + (Get-Date -Format 'yyyy-MM-dd_HH-mm') + '.txt'
    $dialog.Title = 'Сохранить свободные ники'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        [System.IO.File]::WriteAllLines($dialog.FileName,$script:AvailableNames.ToArray(),(New-Object System.Text.UTF8Encoding -ArgumentList $true))
        Add-Diagnostic "TXT экспортировано подтверждённых/предположительных вариантов: $($script:AvailableNames.Count) → $($dialog.FileName)"
    }
})
$script:CsvButton.Add_Click({
    if ($script:Candidates.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Таблица пока пуста.','Экспорт','OK','Information') | Out-Null; return }
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'CSV (*.csv)|*.csv'
    $dialog.FileName = 'Universal_Usernames_All_' + (Get-Date -Format 'yyyy-MM-dd_HH-mm') + '.csv'
    $dialog.Title = 'Экспорт всех результатов'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:Candidates | Select-Object @{Name='Платформа';Expression={$_.Platform}},@{Name='Ник';Expression={$_.Name}},@{Name='Статус';Expression={$_.Status}},@{Name='Категория';Expression={$_.Category}},@{Name='Структура';Expression={$_.Structure}},@{Name='Значение';Expression={$_.Meaning}},@{Name='Время';Expression={$_.Time}},@{Name='Причина';Expression={$_.Reason}} | Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Encoding UTF8
        Add-Diagnostic "CSV экспортировано записей: $($script:Candidates.Count) → $($dialog.FileName)"
    }
})
$script:CopyButton.Add_Click({
    Update-AvailableNames
    if ($script:AvailableNames.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Пока нет подтверждённых или вероятных вариантов.','Копирование','OK','Information') | Out-Null; return }
    [System.Windows.Forms.Clipboard]::SetText(($script:AvailableNames -join [Environment]::NewLine))
    $script:SummaryLabel.Text = "Скопировано подтверждённых/вероятных вариантов: $($script:AvailableNames.Count)"
})
$script:ClearButton.Add_Click({
    if ($script:AsyncHandle -and -not $script:AsyncHandle.IsCompleted) { return }
    $script:Candidates.Clear()
    Clear-CandidateIndex
    $script:AvailableNames.Clear()
    Touch-Candidates
    $script:CheckedNames.Clear()
    $script:ProgressBar.Value = 0
    $script:ProgressCaption.Text = 'Прогресс проверки'
    Update-ResultGrid
    $script:SummaryLabel.Text = 'Результаты очищены'
    Add-Diagnostic 'Результаты и история проверок очищены.'
})
$script:CopyLogButton.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($script:DiagnosticBox.Text)) { [System.Windows.Forms.Clipboard]::SetText($script:DiagnosticBox.Text) }
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
$script:PlatformBox.Add_SelectedIndexChanged({
    if ($script:PlatformBox.SelectedItem) {
        $script:SummaryLabel.Text = "Выбрана платформа: $($script:PlatformBox.SelectedItem)"
        Add-Diagnostic "Выбрана платформа проверки: $($script:PlatformBox.SelectedItem). Для проверки используются только строки этой платформы."
    }
})

$script:ApiDocsButton.Add_Click({ Show-UsernameFinderHelp })
$script:HistoryButton.Add_Click({ Open-FreeHistoryWindow })
$script:HistoryButton.Text = "Свободные ники ($($script:FreeHistory.Count))"
$script:AccountButton.Add_Click({ Open-AccountTools })

# Настройки предыдущего сеанса восстанавливаются после создания всех контролов
# и до показа окна, чтобы пользователь не видел «прыжка» значений.
Restore-AppSettings
try { if ($script:OnlyFreeCheck.Checked) { Refresh-FreeHistoryList } } catch { }
Update-ResultGrid
Add-Diagnostic ('Universal Username Finder v{0} запущен. Генерация автоматически запускает последовательную проверку выбранной платформы.' -f $script:AppVersion)

$script:Form.Add_FormClosing({
    try { if ($script:Cancellation -and -not $script:Cancellation.IsCancellationRequested) { $script:Cancellation.Cancel() } } catch { }
    try { if ($script:PollTimer) { $script:PollTimer.Stop() } } catch { }
    try { if ($script:WorkerPowerShell) { $script:WorkerPowerShell.Stop() } } catch { }
    try { if ($script:WorkerRunspace) { $script:WorkerRunspace.Close() } } catch { }
    try { if ($script:PasswordRng) { $script:PasswordRng.Dispose() } } catch { }
    # История пишется с задержкой (дебаунс), поэтому при закрытии сохраняем принудительно.
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

try {
    [void]$script:Form.ShowDialog()
} catch {
    # Без этого любое исключение на уровне формы закрывало приложение без сообщения.
    Write-StartupLog ('Фатальная ошибка главного окна: ' + $_.Exception.ToString())
    Show-FatalError 'Фатальная ошибка' ("Приложение не может продолжить работу:`r`n`r`n{0}`r`n`r`nПодробности: UniversalUsernameFinder.log" -f $_.Exception.Message)
    exit 1
}
