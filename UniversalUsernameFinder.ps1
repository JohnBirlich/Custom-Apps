$ErrorActionPreference = 'Stop'
$script:LogPath = Join-Path $PSScriptRoot 'UniversalUsernameFinder.log'
Add-Type -AssemblyName System.Security
$script:VaultDirectory = Join-Path $env:LOCALAPPDATA 'RobloxNickFinder'
$script:VaultPath = Join-Path $script:VaultDirectory 'accounts.dat'
$script:VaultEntropy = [System.Text.Encoding]::UTF8.GetBytes('RobloxNickFinder:account-vault:v1')
$script:PasswordRng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
$script:LastErrorDetail = ''
$script:HadRequestError = $false
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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

function Add-PoolEntry {
    param($Pool, $Seen, [string]$Name, [string]$Meaning, [bool]$UseNumbers)
    $clean = [regex]::Replace($Name, '[^A-Za-z0-9_]', '')
    if ($clean -notmatch '^[A-Za-z0-9][A-Za-z0-9_]{2,19}$' -or $clean -match '__|_$') { return }
    $key = $clean.ToLowerInvariant()
    if (-not $Seen.ContainsKey($key)) {
        $Seen[$key] = $true
        [void]$Pool.Add([pscustomobject]@{Name=$clean; Meaning=$Meaning})
    }
    if ($UseNumbers -and $clean.Length -le 17 -and (Get-Random -Minimum 0 -Maximum 100) -lt 40) {
        $number = Get-Random -Minimum 2 -Maximum 999
        $withNumber = "$clean$number"
        $numberKey = $withNumber.ToLowerInvariant()
        if ($withNumber -match '^[A-Za-z0-9][A-Za-z0-9_]{2,19}$' -and -not $Seen.ContainsKey($numberKey)) {
            $Seen[$numberKey] = $true
            [void]$Pool.Add([pscustomobject]@{Name=$withNumber; Meaning="$Meaning + число $number"})
        }
    }
}

function New-CandidatePool {
    param([string]$Category, [string]$CustomWord, [bool]$UseNumbers, [int]$Count)
    switch ($Category) {
        'Приложения и бренды' { $bases = @($script:AppSeeds) }
        'Осмысленные слова' { $bases = @($script:MeaningSeeds) }
        'Природа и космос' { $bases = @($script:NatureSeeds) }
        'Мифология' { $bases = @($script:MythSeeds) }
        'Игровой стиль' { $bases = @($script:GamingSeeds) }
        'Короткие и минималистичные' { $bases = @($script:MinimalSeeds); $localMods = @($script:Modifiers | Where-Object { $_.Word.Length -le 5 }) }
        default { $bases = @($script:AppSeeds + $script:MeaningSeeds + $script:NatureSeeds + $script:MythSeeds + $script:GamingSeeds + $script:MinimalSeeds) }
    }
    if (-not $localMods) { $localMods = @($script:Modifiers) }
    if (-not [string]::IsNullOrWhiteSpace($CustomWord)) {
        $customClean = [regex]::Replace($CustomWord, '[^A-Za-z0-9_]', '')
        if ($customClean.Length -ge 1) {
            $bases += @{Word=$customClean; Meaning='ваше ключевое слово'}
        }
    }
    $pool = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($base in $bases) {
        Add-PoolEntry $pool $seen $base.Word $base.Meaning $UseNumbers
        foreach ($mod in $localMods) {
            if ($mod.Word.ToLowerInvariant() -ne $base.Word.ToLowerInvariant()) {
                Add-PoolEntry $pool $seen ($base.Word + $mod.Word) ("{0} + {1}" -f $base.Meaning, $mod.Meaning) $UseNumbers
                Add-PoolEntry $pool $seen ($mod.Word + $base.Word) ("{0} + {1}" -f $mod.Meaning, $base.Meaning) $UseNumbers
            }
        }
    }
    $array = $pool.ToArray()
    if ($array.Count -eq 0) { return @() }
    $take = [Math]::Min($Count, $array.Count)
    return @((Get-Random -InputObject $array -Count $take))
}

$script:AppGroups = @{
    'Мессенджеры' = @('Discord','Telegram','WhatsApp','Viber','Signal')
    'Музыка' = @('Spotify','SoundCloud','Deezer','AppleMusic')
    'Игровые платформы' = @('Roblox','Steam','Xbox','PlayStation','Nintendo','EpicGames')
    'Стриминг и видео' = @('YouTube','Twitch','TikTok','Netflix')
    'Разработка' = @('GitHub','GitLab','VisualStudio','JetBrains')
    'Графика и дизайн' = @('Blender','Figma','Photoshop','Canva','CapCut')
    'Технологии' = @('NVIDIA','Intel','AMD','ASUS','Apple','Android','Adobe')
    'Браузеры' = @('Firefox','Chrome','Opera','Edge')
    'Продуктивность' = @('Notion','Trello','Slack','Google')
}
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
$script:HistoryDirectory = Join-Path $env:LOCALAPPDATA 'UniversalUsernameFinder'
$script:HistoryPath = Join-Path $script:HistoryDirectory 'username_history.json'
$script:FreeHistory = @()
$script:RetiredNames = @{}
try {
    if (Test-Path -LiteralPath $script:HistoryPath) {
        $historyData = Get-Content -LiteralPath $script:HistoryPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $script:FreeHistory = @($historyData.FreeHistory | Where-Object { $_.Name -and $_.Platform })
        foreach ($retiredKey in @($historyData.RetiredNames)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$retiredKey)) { $script:RetiredNames[[string]$retiredKey] = $true }
        }
    }
} catch {
    $script:FreeHistory = @()
    $script:RetiredNames = @{}
}

function Get-SeedForWord {
    param([string]$Word, [string]$FallbackMeaning = 'осмысленное слово')
    $all = @($script:AppSeeds) + @($script:MeaningSeeds) + @($script:NatureSeeds) + @($script:MythSeeds) + @($script:GamingSeeds) + @($script:MinimalSeeds) + @($script:Modifiers)
    $found = $all | Where-Object { [string]$_.Word -ieq $Word } | Select-Object -First 1
    if ($found) { return $found }
    return [pscustomobject]@{ Word = $Word; Meaning = $FallbackMeaning }
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
        'GitLab' { return ($Username.Length -ge 2 -and $Username.Length -le 255 -and $Username -match '^[A-Za-z0-9_][A-Za-z0-9_.-]*$') }
        'Minecraft Java' { return ($Username.Length -ge 3 -and $Username.Length -le 16 -and $Username -match '^[A-Za-z0-9_]+$') }
        'Reddit' { return ($Username.Length -ge 3 -and $Username.Length -le 20 -and $Username -match '^[A-Za-z0-9_-]+$') }
        'Discord' {
            $discordNameForFormat = $Username.ToLowerInvariant()
            return ($Username.Length -ge 2 -and $Username.Length -le 32 -and $Username -match '^[A-Za-z0-9_.]+$' -and $Username -notmatch '(^\.|\.$|\.\.)' -and $discordNameForFormat -notin @('discord','clyde','nitro','here','everyone','system'))
        }
        'SoundCloud' { return ($Username.Length -ge 3 -and $Username.Length -le 25 -and $Username -match '^[A-Za-z0-9_-]+$') }
        'Pinterest' { return ($Username.Length -ge 3 -and $Username.Length -le 30 -and $Username -match '^[A-Za-z0-9_]+$') }
        'Snapchat' { return ($Username.Length -ge 3 -and $Username.Length -le 15 -and $Username -match '^[A-Za-z][A-Za-z0-9._-]*$') }
        'Facebook' { return ($Username.Length -ge 5 -and $Username.Length -le 50 -and $Username -match '^[A-Za-z0-9.]+$' -and $Username -notmatch '(^\.|\.$|\.\.)') }
        'X / Twitter' { return ($Username.Length -ge 4 -and $Username.Length -le 15 -and $Username -match '^[A-Za-z0-9_]+$') }
        'Bluesky' { return ($Username.Length -ge 3 -and $Username.Length -le 30 -and $Username -match '^[A-Za-z0-9.-]+$') }
        'Kick' { return ($Username.Length -ge 3 -and $Username.Length -le 25 -and $Username -match '^[A-Za-z0-9_]+$') }
        'Twitch' { return ($Username.Length -ge 4 -and $Username.Length -le 25 -and $Username -match '^[A-Za-z0-9_]+$') }
        'YouTube' { return ($Username.Length -ge 3 -and $Username.Length -le 30 -and $Username -match '^[A-Za-z0-9._-]+$' -and $Username -notmatch '\.\.$') }
        'TikTok' { return ($Username.Length -ge 2 -and $Username.Length -le 24 -and $Username -match '^[A-Za-z0-9_.]+$' -and $Username -notmatch '(^\.|\.$|\.\.)') }
        'Instagram' { return ($Username.Length -ge 1 -and $Username.Length -le 30 -and $Username -match '^[A-Za-z0-9._]+$' -and $Username -notmatch '(^\.|\.$|\.\.)') }
        'Telegram' { return ($Username.Length -ge 5 -and $Username.Length -le 32 -and $Username -match '^[A-Za-z][A-Za-z0-9_]*$') }
        'Steam' { return ($Username.Length -ge 2 -and $Username.Length -le 32 -and $Username -match '^[A-Za-z0-9_-]+$') }
        'Xbox' { return ($Username.Length -ge 3 -and $Username.Length -le 12 -and $Username -match '^[A-Za-z0-9]+$') }
        'PlayStation' { return ($Username.Length -ge 3 -and $Username.Length -le 16 -and $Username -match '^[A-Za-z][A-Za-z0-9_-]*$' -and $Username -notmatch '[-_]$') }
        'Spotify' { return ($Username.Length -ge 1 -and $Username.Length -le 30 -and $Username -match '^[A-Za-z0-9_.-]+$') }
        'Epic Games' { return ($Username.Length -ge 3 -and $Username.Length -le 16 -and $Username -match '^[A-Za-z0-9_-]+$') }
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
        'GitLab' { if ($Username) { return ('https://gitlab.com/' + $safeName) }; return 'https://gitlab.com/users/sign_up' }
        'SoundCloud' { if ($Username) { return ('https://soundcloud.com/' + $safeName) }; return 'https://soundcloud.com/' }
        'Pinterest' { if ($Username) { return ('https://www.pinterest.com/' + $safeName + '/') }; return 'https://www.pinterest.com/' }
        'Snapchat' { if ($Username) { return ('https://www.snapchat.com/add/' + $safeName) }; return 'https://www.snapchat.com/' }
        'Facebook' { if ($Username) { return ('https://www.facebook.com/' + $safeName) }; return 'https://www.facebook.com/' }
        'X / Twitter' { if ($Username) { return ('https://x.com/' + $safeName) }; return 'https://x.com/' }
        'Bluesky' { if ($Username) { return ('https://bsky.app/profile/' + $safeName) }; return 'https://bsky.app/' }
        'Kick' { if ($Username) { return ('https://kick.com/' + $safeName) }; return 'https://kick.com/' }
        'Minecraft Java' { if ($Username) { return ('https://namemc.com/search?q=' + $safeName) }; return 'https://www.minecraft.net/' }
        'Reddit' { if ($Username) { return ('https://www.reddit.com/user/' + $safeName + '/') }; return 'https://www.reddit.com/register/' }
        'Discord' { return 'https://discord.com/register' }
        'Twitch' { if ($Username) { return ('https://www.twitch.tv/' + $safeName) }; return 'https://www.twitch.tv/signup' }
        'YouTube' { if ($Username) { return ('https://www.youtube.com/@' + $safeName) }; return 'https://www.youtube.com/' }
        'TikTok' { if ($Username) { return ('https://www.tiktok.com/@' + $safeName) }; return 'https://www.tiktok.com/signup' }
        'Instagram' { if ($Username) { return ('https://www.instagram.com/' + $safeName + '/') }; return 'https://www.instagram.com/accounts/emailsignup/' }
        'Telegram' { if ($Username) { return ('https://t.me/' + $safeName) }; return 'https://telegram.org/' }
        'Steam' { if ($Username) { return ('https://steamcommunity.com/id/' + $safeName + '/') }; return 'https://store.steampowered.com/join/' }
        'Xbox' { return 'https://account.microsoft.com/' }
        'PlayStation' { return 'https://www.playstation.com/' }
        'Spotify' { if ($Username) { return ('https://open.spotify.com/user/' + $safeName) }; return 'https://www.spotify.com/signup/' }
        'Epic Games' { return 'https://www.epicgames.com/id/register' }
        default { return 'https://www.google.com/search?q=' + [uri]::EscapeDataString($Platform + ' username ' + $Username) }
    }
}

function New-AdvancedCandidatePool {
    param(
        [string[]]$SelectedAppCategories,
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
        [string[]]$ExcludeTokens
    )
    $bases = New-Object System.Collections.ArrayList
    foreach ($selection in $SelectedAppCategories) {
        if ($selection -match '^(.+?)\s+·\s+(.+)$') {
            $word = $matches[1].Trim()
            $group = $matches[2].Trim()
            $seed = Get-SeedForWord -Word $word -FallbackMeaning $group
            [void]$bases.Add([pscustomobject]@{Word=[string]$seed.Word; Meaning=[string]$seed.Meaning; Category=$group})
        } elseif ($script:AppGroups.ContainsKey($selection)) {
            foreach ($word in $script:AppGroups[$selection]) {
                $seed = Get-SeedForWord -Word $word -FallbackMeaning $selection
                [void]$bases.Add([pscustomobject]@{Word=[string]$seed.Word; Meaning=[string]$seed.Meaning; Category=$selection})
            }
        }
    }
    foreach ($group in $SelectedWordCategories) {
        if ($script:MeaningGroups.ContainsKey($group)) {
            foreach ($word in $script:MeaningGroups[$group]) {
                $seed = Get-SeedForWord -Word $word -FallbackMeaning $group
                [void]$bases.Add([pscustomobject]@{Word=[string]$seed.Word; Meaning=[string]$seed.Meaning; Category=$group})
            }
        }
    }
    foreach ($rawWord in ($CustomWords -split '[,;\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
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
    if (-not $OneWord -and -not $TwoWords) { $OneWord = $true }
    $rawCandidates = New-Object System.Collections.ArrayList
    $seenRaw = @{}
    foreach ($base in $bases) {
        $word = [regex]::Replace([string]$base.Word, '[^A-Za-z0-9]', '')
        if ($word.Length -ge 1 -and $OneWord) {
            [void]$rawCandidates.Add([pscustomobject]@{Name=$word; Meaning=[string]$base.Meaning; Category=[string]$base.Category})
        }
        if ($TwoWords) {
            foreach ($mod in $modifiers) {
                $modWord = [regex]::Replace([string]$mod.Word, '[^A-Za-z0-9]', '')
                if ($modWord.Length -lt 1 -or $modWord -ieq $word) { continue }
                $joiner = ''
                if ($UseUnderscore) { $joiner = '_' }
                $pair1 = $word + $joiner + $modWord
                $pair2 = $modWord + $joiner + $word
                [void]$rawCandidates.Add([pscustomobject]@{Name=$pair1; Meaning=("{0} + {1}" -f $base.Meaning, $mod.Meaning); Category=[string]$base.Category})
                [void]$rawCandidates.Add([pscustomobject]@{Name=$pair2; Meaning=("{0} + {1}" -f $mod.Meaning, $base.Meaning); Category=[string]$base.Category})
            }
        }
    }
    $prefixClean = [regex]::Replace([string]$Prefix, '[^A-Za-z0-9_.-]', '')
    $suffixClean = [regex]::Replace([string]$Suffix, '[^A-Za-z0-9_.-]', '')
    $filtered = New-Object System.Collections.ArrayList
    $seen = @{}
    $rawArray = @($rawCandidates.ToArray() | Sort-Object { Get-Random })
    foreach ($entry in $rawArray) {
        $name = [string]$entry.Name
        if ($prefixClean) { $name = $prefixClean + $name }
        if ($suffixClean) { $name = $name + $suffixClean }
        $name = [regex]::Replace($name, '[^A-Za-z0-9_.-]', '')
        $maximum = $MaxLength
        if ($OnlyShort) { $maximum = [Math]::Min($maximum, 12) }
        if ($name.Length -lt $MinLength -or $name.Length -gt $maximum -or -not (Test-UsernameFormat -Username $name -Platform $Platform)) { continue }
        $excluded = $false
        foreach ($token in $ExcludeTokens) {
            if (-not [string]::IsNullOrWhiteSpace($token) -and $name.IndexOf($token.Trim(), [StringComparison]::OrdinalIgnoreCase) -ge 0) { $excluded = $true; break }
        }
        if ($excluded) { continue }
        $key = $name.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$filtered.Add([pscustomobject]@{Name=$name; Platform=$Platform; Meaning=[string]$entry.Meaning; Category=[string]$entry.Category; Status='Ожидает'; Time=''; Reason='Ожидает проверки'; Checked=$false})
        }
        if ($UseNumbers -and $name.Length -le ($maximum - 2) -and (Get-Random -Minimum 0 -Maximum 100) -lt 30) {
            $number = Get-Random -Minimum 2 -Maximum 1000
            $withNumber = "$name$number"
            if ($withNumber.Length -ge $MinLength -and $withNumber.Length -le $maximum -and (Test-UsernameFormat -Username $withNumber -Platform $Platform)) {
                $numberKey = $withNumber.ToLowerInvariant()
                if (-not $seen.ContainsKey($numberKey)) {
                    $seen[$numberKey] = $true
                    [void]$filtered.Add([pscustomobject]@{Name=$withNumber; Platform=$Platform; Meaning=([string]$entry.Meaning + " + число $number"); Category=[string]$entry.Category; Status='Ожидает'; Time=''; Reason='Ожидает проверки'; Checked=$false})
                }
            }
        }
        if ($filtered.Count -ge ($Count * 4)) { break }
    }
    if ($filtered.Count -eq 0) { return @() }
    $shuffled = @($filtered.ToArray() | Sort-Object { Get-Random })
    $take = [Math]::Min($Count, $shuffled.Count)
    return @($shuffled | Select-Object -First $take)
}

$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = 'Universal Username Finder v2.5'
$script:Form.StartPosition = 'CenterScreen'
$script:Form.Size = New-Object System.Drawing.Size(1480, 960)
$script:Form.MinimumSize = New-Object System.Drawing.Size(1240, 910)
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
$title.Text = 'UNIVERSAL USERNAME FINDER  •  v2.5'
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
    if ($Placeholder) { $box.Text = $Placeholder; $box.ForeColor = [System.Drawing.Color]::FromArgb(149,164,187) }
    $left.Controls.Add($box)
    return $box
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
$script:CountBox = New-NumberBox 14 709 90 5 200 40
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
$script:DelayBox = New-NumberBox 14 971 145 900 15000 1000
$script:TimeoutBox = New-NumberBox 194 971 145 1000 30000 8000
$script:ThreadsLabel = Add-UiLabel 'Потоки: 1 (рекомендуется для защиты от HTTP 429)' 14 1002 350 30

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
[void]$script:SortBox.Items.AddRange([object[]]@('Ник','Статус','Категория','Короткие сначала','Свободные первыми'))
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
[void]$script:PlatformBox.Items.AddRange([object[]]@('Roblox','Google','Mail.ru','VK','Discord','TikTok','Microsoft','Outlook','Telegram','GitHub','YouTube','Apple'))
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
[void]$script:Grid.Columns.Add('Meaning','ЗНАЧЕНИЕ')
[void]$script:Grid.Columns.Add('Time','ВРЕМЯ')
[void]$script:Grid.Columns.Add('Reason','ПРИЧИНА')
$script:Grid.Columns['Nick'].FillWeight = 17
$script:Grid.Columns['Platform'].FillWeight = 14
$script:Grid.Columns['Status'].FillWeight = 15
$script:Grid.Columns['Category'].FillWeight = 18
$script:Grid.Columns['Meaning'].FillWeight = 20
$script:Grid.Columns['Time'].FillWeight = 10
$script:Grid.Columns['Reason'].FillWeight = 24
$script:Grid.RowTemplate.Height = 27
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
        $logPath = Join-Path $PSScriptRoot 'UniversalUsernameFinder.log'
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

function Test-RobloxUsernameFormat {
    param([string]$Username)
    if ([string]::IsNullOrWhiteSpace($Username)) { return $false }
    return ($Username.Length -ge 3 -and $Username.Length -le 20 -and $Username -match '^[A-Za-z0-9][A-Za-z0-9_]*$' -and $Username -notmatch '__|_$' -and ([regex]::Matches($Username, '_').Count -le 1))
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

function Write-AppLog {
    param([string]$Message)
    try {
        $logPath = Join-Path $PSScriptRoot 'UniversalUsernameFinder.log'
        $line = '[{0}] {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message, [Environment]::NewLine
        [System.IO.File]::AppendAllText($logPath, $line, (New-Object System.Text.UTF8Encoding -ArgumentList $true))
    } catch { }
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

function Save-UsernameHistory {
    try {
        if (-not (Test-Path -LiteralPath $script:HistoryDirectory)) { [void](New-Item -ItemType Directory -Path $script:HistoryDirectory -Force) }
        $data = [pscustomobject]@{
            FreeHistory = @($script:FreeHistory | Select-Object -First 30)
            RetiredNames = @($script:RetiredNames.Keys | Select-Object -First 20000)
        }
        ConvertTo-Json -InputObject $data -Depth 6 | Set-Content -LiteralPath $script:HistoryPath -Encoding UTF8
    } catch { Write-AppLog ('Не удалось сохранить историю ников: ' + $_.Exception.Message) }
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
    Save-UsernameHistory
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
        $script:HistoryForm.Close()
        $script:PlatformBox.SelectedItem = $selectedPlatform
        $candidate = $script:Candidates | Where-Object { [string]$_.Name -ieq $selectedName -and [string]$_.Platform -eq $selectedPlatform } | Select-Object -First 1
        if (-not $candidate) {
            $candidate = [pscustomobject]@{Name=$selectedName; Platform=$selectedPlatform; Meaning='Повторная проверка из истории'; Category='История свободных'; Status='Ожидает'; Time=''; Reason='Запрошена повторная проверка'; Checked=$false}
            [void]$script:Candidates.Add($candidate)
        }
        $candidate.Status = 'Ожидает'
        $candidate.Time = ''
        $candidate.Reason = 'Запрошена повторная проверка'
        $candidate.Checked = $false
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
    $checked = @($script:Candidates | Where-Object { $_.Checked }).Count
    $free = @($script:Candidates | Where-Object { $_.Status -eq 'Свободен' -or $_.Status -eq 'Вероятно свободен' }).Count
    $taken = @($script:Candidates | Where-Object { $_.Status -eq 'Занят' }).Count
    $invalid = @($script:Candidates | Where-Object { $_.Status -eq 'Недопустимый' }).Count
    $errors = @($script:Candidates | Where-Object { $_.Status -eq 'Ошибка сети' }).Count
    $script:StatTotal.Text = "Всего: $total"
    $script:StatChecked.Text = "Проверено: $checked"
    $script:StatFree.Text = "Свободно/возможно: $free"
    $script:StatTaken.Text = "Занято: $taken"
    $script:StatInvalid.Text = "Недопустимо: $invalid"
    $script:StatErrors.Text = "Ошибки: $errors"
}

function Update-ResultGrid {
    if (-not $script:Grid) { return }
    $script:Grid.SuspendLayout()
    $script:Grid.Rows.Clear()
    $filterStatus = [string]$script:StatusFilterBox.SelectedItem
    $query = ''
    if ($script:SearchBox) { $query = $script:SearchBox.Text.Trim() }
    $items = @($script:Candidates.ToArray())
    switch ([string]$script:SortBox.SelectedItem) {
        'Статус' { $items = @($items | Sort-Object Status, Platform, Name) }
        'Категория' { $items = @($items | Sort-Object Category, Platform, Name) }
        'Короткие сначала' { $items = @($items | Sort-Object @{Expression={$_.Name.Length}}, Platform, Name) }
        'Свободные первыми' { $items = @($items | Sort-Object @{Expression={ switch ([string]$_.Status) { 'Свободен' {0}; 'Вероятно свободен' {1}; 'Не подтверждено' {2}; 'Ожидает' {3}; 'Проверяется' {4}; 'Ошибка сети' {5}; 'Занят' {6}; default {7} } }}, Platform, Name) }
        default { $items = @($items | Sort-Object Platform, Name) }
    }
    foreach ($item in $items) {
        if ($script:OnlyFreeCheck.Checked -and ([string]$item.Status -ne 'Свободен' -and [string]$item.Status -ne 'Вероятно свободен')) { continue }
        if ($filterStatus -and $filterStatus -ne 'Все статусы' -and [string]$item.Status -ne $filterStatus) { continue }
        $searchText = ([string]$item.Name + ' ' + [string]$item.Platform + ' ' + [string]$item.Category + ' ' + [string]$item.Meaning + ' ' + [string]$item.Reason)
        if ($query -and $searchText.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $row = $script:Grid.Rows.Add([string]$item.Name,[string]$item.Platform,[string]$item.Status,[string]$item.Category,[string]$item.Meaning,[string]$item.Time,[string]$item.Reason)
        $color = [System.Drawing.Color]::FromArgb(255,190,92)
        switch ([string]$item.Status) {
            'Свободен' { $color = [System.Drawing.Color]::FromArgb(99,222,151) }
            'Вероятно свободен' { $color = [System.Drawing.Color]::FromArgb(120,205,250) }
            'Занят' { $color = [System.Drawing.Color]::FromArgb(245,120,120) }
            'Недопустимый' { $color = [System.Drawing.Color]::FromArgb(180,188,203) }
            'Не подтверждено' { $color = [System.Drawing.Color]::FromArgb(207,185,255) }
            'Ошибка сети' { $color = [System.Drawing.Color]::FromArgb(255,190,92) }
            'Проверяется' { $color = [System.Drawing.Color]::FromArgb(105,185,255) }
        }
        $script:Grid.Rows[$row].Cells['Nick'].Style.ForeColor = $color
        $script:Grid.Rows[$row].Cells['Status'].Style.ForeColor = $color
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
        [void]$validCandidates.Add([pscustomobject]@{Name=[string]$candidate.Name; Platform=$selectedPlatform; Meaning=[string]$candidate.Meaning; Category=[string]$candidate.Category})
    }
    if ($validCandidates.Count -eq 0) { Update-ResultGrid; return }
    Update-ResultGrid
    $script:ErrorBox = $script:DiagnosticBox
    Add-Diagnostic ("Начата проверка: {0} ников; пауза {1} мс; тайм-аут {2} мс; потоков 1; платформа {3}." -f $validCandidates.Count,[int]$script:DelayBox.Value,[int]$script:TimeoutBox.Value,$selectedPlatform)
    $script:CurrentBatchTotal = $validCandidates.Count
    $script:CurrentBatchDone = 0
    $script:ProgressBar.Value = 0
    $script:ProgressCaption.Text = "Проверка 0 из $($script:CurrentBatchTotal)"
    $workerScript = @'
param($Candidates, $Queue, $Cancellation, $DelayMs, $TimeoutMs, $Platform)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$total = @($Candidates).Count
$done = 0
$consecutiveErrors = 0
$stopReason = $null
$timeoutSec = [Math]::Max(1,[int][Math]::Ceiling(([double]$TimeoutMs)/1000.0))
function Get-HttpResult {
    param([string]$Url, [int]$Timeout, [hashtable]$Headers, [string]$Method='Get', [string]$Body=$null, [string]$ContentType='application/json; charset=utf-8', $WebSession=$null)
    $code = 0
    $content = ''
    $responseHeaders = $null
    try {
        $requestArgs = @{ Uri=$Url; Method=$Method; TimeoutSec=$Timeout; UseBasicParsing=$true; Headers=$Headers }
        if ($null -ne $Body) { $requestArgs.Body = $Body; $requestArgs.ContentType = $ContentType }
        if ($null -ne $WebSession) { $requestArgs.WebSession = $WebSession }
        $r = Invoke-WebRequest @requestArgs
        $code = [int]$r.StatusCode
        $content = [string]$r.Content
        $responseHeaders = $r.Headers
    } catch {
        $webResponse = $null
        try { $webResponse = $_.Exception.Response } catch { }
        if ($null -eq $webResponse) { throw }
        try { $code = [int]$webResponse.StatusCode } catch { }
        try { $responseHeaders = $webResponse.Headers } catch { }
        try {
            $stream = $webResponse.GetResponseStream()
            if ($stream) {
                $reader = New-Object System.IO.StreamReader($stream)
                $content = $reader.ReadToEnd()
                $reader.Dispose()
            }
        } catch { }
    }
    return [pscustomobject]@{Code=$code; Content=$content; Headers=$responseHeaders}
}
$browserHeaders = @{
    'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36'
    'Accept'='text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
}
$googleSession = $null
$googleSetupToken = ''
$msSession = $null
$msContext = $null
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
        $headers = @{'User-Agent'='UniversalUsernameFinder/2.5 (username availability checker)'; 'Accept'='application/json'}
        try {
            switch ($Platform) {
                'Roblox' {
                    $payload = @{username=$name; birthday='2000-01-01T00:00:00.000Z'; context='Signup'} | ConvertTo-Json -Compress
                    $robloxHeaders = @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json'; 'Origin'='https://www.roblox.com'; 'Referer'='https://www.roblox.com/'}
                    $r = Get-HttpResult -Url 'https://auth.roblox.com/v1/usernames/validate' -Timeout $timeoutSec -Headers $robloxHeaders -Method Post -Body $payload -ContentType 'application/json; charset=UTF-8'
                    $httpStatus = [int]$r.Code
                    if ($httpStatus -eq 403 -or $httpStatus -eq 404 -or $httpStatus -eq 405) {
                        $escapedName = [uri]::EscapeDataString($name)
                        $birthday = [uri]::EscapeDataString('2000-01-01T00:00:00.000Z')
                        $url = "https://auth.roblox.com/v1/usernames/validate?request.username=$escapedName&request.birthday=$birthday&request.context=Signup"
                        $r = Get-HttpResult -Url $url -Timeout $timeoutSec -Headers $robloxHeaders
                        $httpStatus = [int]$r.Code
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
                    $githubSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                    $signupUrl = 'https://github.com/signup?source=form-home-signup'
                    $null = Get-HttpResult -Url $signupUrl -Timeout $timeoutSec -Headers @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/129.0.0.0 Safari/537.36'; 'Accept'='text/html,application/xhtml+xml'} -WebSession $githubSession
                    $checkUrl = 'https://github.com/signup_check/username?value=' + [uri]::EscapeDataString($name)
                    $r = Get-HttpResult -Url $checkUrl -Timeout $timeoutSec -Headers @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/129.0.0.0 Safari/537.36'; 'Accept'='*/*'; 'X-Requested-With'='XMLHttpRequest'; 'Referer'=$signupUrl} -WebSession $githubSession
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
                        $r = Get-HttpResult -Url $url -Timeout $timeoutSec -Headers @{'User-Agent'='UniversalUsernameFinder/2.5'; 'Accept'='application/vnd.github+json'; 'X-GitHub-Api-Version'='2026-03-10'}
                        $httpStatus = [int]$r.Code
                        if ($httpStatus -eq 200) { $status='Занят'; $reason='Публичный профиль GitHub найден'; $consecutiveErrors=0 }
                        elseif ($httpStatus -eq 404) { $status='Вероятно свободен'; $reason='Профиль GitHub не найден; имя может быть зарезервировано регистрационной формой'; $consecutiveErrors=0 }
                        elseif ($httpStatus -eq 403) { $status='Ошибка сети'; $reason='GitHub ограничил анонимный API (403/возможный лимит)'; $stopReason='GitHub ограничил запросы; проверка остановлена' }
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
                    $appleSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                    $appleInit = Get-HttpResult -Url 'https://appleid.apple.com/account' -Timeout $timeoutSec -Headers $browserHeaders -WebSession $appleSession
                    $appleEmail = $name + '@icloud.com'
                    $appleHeaders = @{'User-Agent'=$browserHeaders['User-Agent']; 'Accept'='application/json, text/javascript, */*; q=0.01'; 'Content-Type'='application/json'; 'Origin'='https://appleid.apple.com'; 'Referer'='https://appleid.apple.com/account'; 'X-Requested-With'='XMLHttpRequest'; 'X-Apple-Request-Context'='create'}
                    $apiKeyMatch = [regex]::Match([string]$appleInit.Content, '(?i)(?:X-Apple-Api-Key|apiKey)\s*["''\s:=]+([A-Za-z0-9_-]{20,})')
                    if ($apiKeyMatch.Success) { $appleHeaders['X-Apple-Api-Key'] = $apiKeyMatch.Groups[1].Value }
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
            if ($httpStatus -eq 429) {
                try { if ($r.Headers['Retry-After']) { $retryAfter = [int]$r.Headers['Retry-After'] } } catch { }
                if ($retryAfter -lt 1) { $retryAfter = 15 }
                if ($retryAfter -gt 120) { $retryAfter = 120 }
                $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=("HTTP 429 для {0} ({1}). Пауза Retry-After: {2} сек." -f $name,$Platform,$retryAfter)})
                $waitUntil = [DateTime]::UtcNow.AddSeconds($retryAfter)
                while ([DateTime]::UtcNow -lt $waitUntil -and -not $Cancellation.IsCancellationRequested) { Start-Sleep -Milliseconds 100 }
                $status = 'Ошибка сети'; $reason = "HTTP 429 — ограничение частоты запросов $Platform; повторите позже"; $stopReason = "$Platform продолжает ограничивать частоту запросов"
            } elseif ($httpStatus -eq 403 -and $Platform -eq 'GitHub') {
                $status = 'Ошибка сети'; $reason = 'GitHub HTTP 403: возможен лимит анонимного API'; $stopReason = 'GitHub ограничил запросы; проверка остановлена'
            } elseif ($httpStatus -ge 500) {
                $status = 'Ошибка сети'; $reason = "HTTP $httpStatus от $Platform"; $consecutiveErrors++
            } elseif ($httpStatus -eq 0) {
                if ($status -ne 'Не подтверждено') { $status = 'Ошибка сети'; $reason = 'Ответ без HTTP-статуса'; $consecutiveErrors++ }
            } elseif ($httpStatus -ge 400 -and $status -eq 'Ошибка сети' -and $Platform -ne 'Reddit') {
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
        $done++
        $now = (Get-Date).ToString('HH:mm:ss')
        $null = $Queue.Enqueue([pscustomobject]@{Type='Progress'; Item=[pscustomobject]@{Name=$name; Platform=$Platform; Category=[string]$item.Category; Meaning=[string]$item.Meaning; Status=$status; Reason=$reason; ErrorDetail=$errorDetail; Time=$now; Index=$done; Total=$total}})
        if ($errorDetail) { $null = $Queue.Enqueue([pscustomobject]@{Type='Log'; Message=("{0} ({1}): {2}" -f $name,$Platform,$errorDetail)}) }
        if ($stopReason -or $consecutiveErrors -ge 3) {
            if (-not $stopReason) { $stopReason = 'Три сетевые ошибки подряд; проверка остановлена для защиты от повторных запросов' }
            break
        }
        if ($done -lt $total) {
            $elapsed = 0
            while ($elapsed -lt $DelayMs -and -not $Cancellation.IsCancellationRequested) {
                $step = [Math]::Min(100,($DelayMs - $elapsed))
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
        [void]$script:WorkerPowerShell.AddScript($workerScript).AddArgument(@($validCandidates.ToArray())).AddArgument($script:CheckQueue).AddArgument($script:Cancellation).AddArgument([int]$script:DelayBox.Value).AddArgument([int]$script:TimeoutBox.Value).AddArgument([string]$selectedPlatform)
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
                $candidate = $script:Candidates | Where-Object { [string]$_.Name -ieq [string]$item.Name -and [string]$_.Platform -eq [string]$item.Platform } | Select-Object -First 1
                if ($candidate) {
                    $script:CheckedNames[((([string]$candidate.Platform) + '|' + [string]$candidate.Name).ToLowerInvariant())] = $true
                    $candidate.Status = [string]$item.Status
                    $candidate.Time = [string]$item.Time
                    $candidate.Reason = [string]$item.Reason
                    $candidate.Checked = $true
                    Update-FreeHistoryFromCandidate $candidate
                }
                $script:CurrentBatchDone = [int]$item.Index
                $script:ProgressBar.Value = [Math]::Min(100,[int](100 * $script:CurrentBatchDone / [Math]::Max(1,$script:CurrentBatchTotal)))
                $script:ProgressCaption.Text = "Прогресс: $($script:CurrentBatchDone)/$($script:CurrentBatchTotal) · $($item.Name)"
                Update-ResultGrid
            } elseif ($entry.Type -eq 'Log') {
                Add-Diagnostic ([string]$entry.Message)
            } elseif ($entry.Type -eq 'Complete') {
                $script:CompletionEvent = $entry
            }
            $entry = $null
        }
    }
    if ($script:AsyncHandle -and $script:AsyncHandle.IsCompleted) {
        $script:PollTimer.Stop()
        try { $null = $script:WorkerPowerShell.EndInvoke($script:AsyncHandle) } catch { $script:UnhandledWorkerError = $_.Exception.ToString() }
        if ($script:CheckQueue) {
            $entry = $null
            while ($script:CheckQueue.TryDequeue([ref]$entry)) {
                if ($entry.Type -eq 'Progress') {
                    $item = $entry.Item
                    $candidate = $script:Candidates | Where-Object { [string]$_.Name -ieq [string]$item.Name -and [string]$_.Platform -eq [string]$item.Platform } | Select-Object -First 1
                    if ($candidate) { $script:CheckedNames[((([string]$candidate.Platform) + '|' + [string]$candidate.Name).ToLowerInvariant())] = $true; $candidate.Status=[string]$item.Status; $candidate.Time=[string]$item.Time; $candidate.Reason=[string]$item.Reason; $candidate.Checked=$true; Update-FreeHistoryFromCandidate $candidate }
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
    $customWords = $script:CustomBox.Text
    if ($customWords -eq 'Pixel, Void, Storm') { $customWords = '' }
    $customTheme = $script:ThemeBox.Text
    $excludeTokens = @($script:ExcludeBox.Text -split '[,;\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $candidates = @(New-AdvancedCandidatePool -SelectedAppCategories @() -SelectedWordCategories $categories -CustomWords $customWords -CustomTheme $customTheme -Style ([string]$script:StyleBox.SelectedItem) -Platform $platform -Prefix $script:PrefixBox.Text -Suffix $script:SuffixBox.Text -MinLength ([int]$script:MinLengthBox.Value) -MaxLength ([int]$script:MaxLengthBox.Value) -Count ([int]$script:CountBox.Value) -UseNumbers ([bool]$script:NumbersCheck.Checked) -UseUnderscore ([bool]$script:UnderscoreCheck.Checked) -OneWord ([bool]$script:OneWordCheck.Checked) -TwoWords ([bool]$script:TwoWordsCheck.Checked) -OnlyShort ([bool]$script:ShortOnlyCheck.Checked) -ExcludeTokens $excludeTokens)
    if ($candidates.Count -eq 0 -and [string]::IsNullOrWhiteSpace($script:ManualNickBox.Text)) {
        [System.Windows.Forms.MessageBox]::Show('Не удалось создать ники. Выбери хотя бы одну категорию или введи свои слова. Проверь длину и фильтры исключения.','Нет вариантов','OK','Warning') | Out-Null
        return
    }
    $seen = @{}
    foreach ($existing in $script:Candidates) { $existingPlatform = [string]$existing.Platform; if (-not $existingPlatform) { $existingPlatform = 'Roblox' }; $seen[(($existingPlatform + '|' + [string]$existing.Name).ToLowerInvariant())] = $true }
    $added = 0
    foreach ($candidate in $candidates) {
        $key = (($platform + '|' + [string]$candidate.Name).ToLowerInvariant())
        if ($script:RetiredNames.ContainsKey($key)) { continue }
        if ($script:ExcludeCheckedCheck.Checked -and $script:CheckedNames.ContainsKey($key)) { continue }
        if (-not $seen.ContainsKey($key)) { [void]$script:Candidates.Add($candidate); $seen[$key]=$true; $added++ }
    }
    foreach ($nickRaw in ($script:ManualNickBox.Text -split '[,;\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $nick = $nickRaw.Trim()
        $key = (($platform + '|' + $nick).ToLowerInvariant())
        if ($seen.ContainsKey($key) -or $script:RetiredNames.ContainsKey($key)) { continue }
        $status = 'Ожидает'; $reason = 'Ожидает проверки'
        if (-not (Test-UsernameFormat -Username $nick -Platform $platform)) { $status = 'Недопустимый'; $reason = "Неверный формат имени для платформы $platform" }
        $manualTime = ''
        if ($status -eq 'Недопустимый') { $manualTime = (Get-Date).ToString('HH:mm:ss') }
        [void]$script:Candidates.Add([pscustomobject]@{Name=$nick; Platform=$platform; Meaning='Введён вручную'; Category='Ручной ввод'; Status=$status; Time=$manualTime; Reason=$reason; Checked=($status -eq 'Недопустимый')})
        $seen[$key]=$true; $added++
    }
    if ($script:Candidates.Count -gt 2000) { [System.Windows.Forms.MessageBox]::Show('В списке слишком много записей. Экспортируй результаты или очисти список перед новой генерацией.','Лимит списка','OK','Information') | Out-Null }
    Update-ResultGrid
    Add-Diagnostic "Для платформы $platform сгенерировано новых кандидатов: $added. Всего в таблице: $($script:Candidates.Count)."
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
        $script:Candidates | Select-Object @{Name='Платформа';Expression={$_.Platform}},@{Name='Ник';Expression={$_.Name}},@{Name='Статус';Expression={$_.Status}},@{Name='Категория';Expression={$_.Category}},@{Name='Значение';Expression={$_.Meaning}},@{Name='Время';Expression={$_.Time}},@{Name='Причина';Expression={$_.Reason}} | Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Encoding UTF8
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
    $script:AvailableNames.Clear()
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

Add-Diagnostic 'Universal Username Finder v2.5 запущен. Генерация автоматически запускает последовательную проверку выбранной платформы.'

$script:Form.Add_FormClosing({
    try { if ($script:Cancellation -and -not $script:Cancellation.IsCancellationRequested) { $script:Cancellation.Cancel() } } catch { }
    try { if ($script:PollTimer) { $script:PollTimer.Stop() } } catch { }
    try { if ($script:WorkerPowerShell) { $script:WorkerPowerShell.Stop() } } catch { }
    try { if ($script:WorkerRunspace) { $script:WorkerRunspace.Close() } } catch { }
    try { if ($script:PasswordRng) { $script:PasswordRng.Dispose() } } catch { }
})

[void]$script:Form.ShowDialog()
