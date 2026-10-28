BeforeAll {
    $scriptPath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..') 'UniversalUsernameFinder.ps1'))
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw ('Не найден скрипт приложения: ' + $scriptPath) }

    $fullText = [System.IO.File]::ReadAllText($scriptPath)

    $workerMarker = '$workerScript = @'
    $workerStart = $fullText.IndexOf($workerMarker)
    if ($workerStart -lt 0) { throw 'Не найден here-string воркера' }
    $global:UufMainText = $fullText.Substring(0, $workerStart)
    $global:UufWorkerText = $fullText.Substring($workerStart)
    $global:UufFullText = $fullText
    $global:UufScriptPath = $scriptPath

    $global:UufExtractFunction = {
        param([string]$Source, [string]$Name)
        $pattern = '(?ms)^function\s+' + [regex]::Escape($Name) + '\s*\{'
        $match = [regex]::Match($Source, $pattern)
        if (-not $match.Success) { throw ('Функция не найдена в скрипте: ' + $Name) }
        $index = $match.Index + $match.Length
        $depth = 1
        while ($index -lt $Source.Length -and $depth -gt 0) {
            $char = $Source[$index]
            if ($char -eq '{') { $depth++ }
            elseif ($char -eq '}') { $depth-- }
            $index++
        }
        if ($depth -ne 0) { throw ('Не удалось определить конец функции: ' + $Name) }
        return $Source.Substring($match.Index, $index - $match.Index)
    }

    $functionNames = @(
        'Test-RobloxUsernameFormat',
        'Test-UsernameFormat',
        'Test-SupportedPlatform',
        'Get-CryptoRandomIndex',
        'New-SecurePassword',
        'Convert-ToNickToken',
        'Get-ShuffledArray',
        'Write-AtomicFile',
        'Write-AtomicJsonFile',
        'Export-AppSettings',
        'Import-AppSettings',
        'Get-HistoryKey',
        'Initialize-SeedIndex',
        'Get-SeedForWord',
        'Get-NickStructure',
        'Get-PlatformLengthRule',
        'Get-PlatformDomain',
        'Get-DisplayNick',
        'Get-RegistrationUrl',
        'Open-UrlInIncognito',
        'Update-AccountPlatformUi',
        'New-InventedWord',
        'Convert-ToLeetWord',
        'New-AdvancedCandidatePool'
    )

    foreach ($functionName in $functionNames) {
        $definition = & $global:UufExtractFunction $global:UufMainText $functionName
        $definition = $definition -replace '\$script:', '$$global:'
        Invoke-Expression $definition
    }

    $platformNeedle = '$script:SupportedPlatforms = @('
    $platformStart = $global:UufMainText.IndexOf($platformNeedle)
    if ($platformStart -lt 0) { throw 'Не найден список поддерживаемых платформ' }
    $valueStart = $platformStart + $platformNeedle.Length
    $valueEnd = $global:UufMainText.IndexOf(')', $valueStart)
    $rawPlatforms = $global:UufMainText.Substring($valueStart, $valueEnd - $valueStart)
    $global:SupportedPlatforms = @(
        $rawPlatforms -split ',' |
            ForEach-Object { $_.Trim().Trim('"').Trim([char]39) } |
            Where-Object { $_ }
    )

    $rulesNeedle = '$script:PlatformLengthRules = @{'
    $rulesStart = $global:UufMainText.IndexOf($rulesNeedle)
    if ($rulesStart -lt 0) { throw 'Не найдена таблица правил длины платформ' }
    $rulesBraceStart = $global:UufMainText.IndexOf('{', $rulesStart)
    $rulesDepth = 0
    $rulesEnd = -1
    for ($rulesIndex = $rulesBraceStart; $rulesIndex -lt $global:UufMainText.Length; $rulesIndex++) {
        $rulesChar = $global:UufMainText[$rulesIndex]
        if ($rulesChar -eq '{') { $rulesDepth++ }
        elseif ($rulesChar -eq '}') {
            $rulesDepth--
            if ($rulesDepth -eq 0) { $rulesEnd = $rulesIndex; break }
        }
    }
    if ($rulesEnd -lt 0) { throw 'Не найден конец таблицы правил длины платформ' }
    $rulesText = $global:UufMainText.Substring($rulesStart, $rulesEnd + 1 - $rulesStart)
    $rulesText = $rulesText -replace '\$script:', '$$global:'
    Invoke-Expression $rulesText
    if (-not $global:PlatformLengthRules -or $global:PlatformLengthRules.Count -lt 1) {
        throw 'Таблица правил длины платформ извлечена пустой'
    }

    $domainsNeedle = '$script:PlatformDomains = @{'
    $domainsStart = $global:UufMainText.IndexOf($domainsNeedle)
    if ($domainsStart -lt 0) { throw 'Не найдена таблица доменов платформ' }
    $domainsBraceStart = $global:UufMainText.IndexOf('{', $domainsStart)
    $domainsDepth = 0
    $domainsEnd = -1
    for ($domainsIndex = $domainsBraceStart; $domainsIndex -lt $global:UufMainText.Length; $domainsIndex++) {
        $domainsChar = $global:UufMainText[$domainsIndex]
        if ($domainsChar -eq '{') { $domainsDepth++ }
        elseif ($domainsChar -eq '}') {
            $domainsDepth--
            if ($domainsDepth -eq 0) { $domainsEnd = $domainsIndex; break }
        }
    }
    if ($domainsEnd -lt 0) { throw 'Не найден конец таблицы доменов платформ' }
    $domainsText = $global:UufMainText.Substring($domainsStart, $domainsEnd + 1 - $domainsStart)
    $domainsText = $domainsText -replace '\$script:', '$$global:'
    Invoke-Expression $domainsText
    if (-not $global:PlatformDomains -or $global:PlatformDomains.Count -lt 1) {
        throw 'Таблица доменов платформ извлечена пустой'
    }

    $branchPrefix = '                ' + [char]39
    $branchSuffix = [string][char]39 + ' {'
    $branches = New-Object System.Collections.Generic.List[string]
    foreach ($rawLine in $global:UufWorkerText.Split([char]10)) {
        $line = $rawLine.TrimEnd([char]13)
        if ($line.StartsWith($branchPrefix) -and $line.EndsWith($branchSuffix)) {
            $branchName = $line.Substring($branchPrefix.Length, $line.Length - $branchPrefix.Length - $branchSuffix.Length)
            if ($branchName -and -not $branchName.Contains([string][char]39)) { [void]$branches.Add($branchName) }
        }
    }
    $global:UufWorkerBranches = $branches.ToArray()

    $global:AppSeeds = @()
    $global:NatureSeeds = @()
    $global:MythSeeds = @()
    $global:GamingSeeds = @()
    $global:MinimalSeeds = @()
    $global:MeaningSeeds = @(
        @{ Word = 'Boom'; Meaning = 'взрыв' },
        @{ Word = 'Square'; Meaning = 'квадрат' },
        @{ Word = 'Nova'; Meaning = 'новая звезда' }
    )
    $global:Modifiers = @(
        @{ Word = 'Void'; Meaning = 'пустота' },
        @{ Word = 'Storm'; Meaning = 'буря' },
        @{ Word = 'Pixel'; Meaning = 'пиксель' },
        @{ Word = 'Core'; Meaning = 'ядро' },
        @{ Word = 'Flux'; Meaning = 'поток' }
    )
    $global:MeaningGroups = @{ 'Тестовая' = @('Nova', 'Echo', 'Pulse', 'Orbit', 'Frost', 'Shadow', 'Raven', 'Comet') }
    $global:StyleWords = @{ 'Двусловный' = @('Nova', 'Echo', 'Pulse') }
    $global:InventedOnsets = @('Kr', 'Dav', 'Vel', 'Zan', 'Tor')
    $global:InventedNuclei = @('a', 'e', 'i', 'o')
    $global:InventedCodas = @('n', 'l', 'r', 's', 'k', 'nn')
    $global:RareShortWords = @('Nyx', 'Lux', 'Vex', 'Zed', 'Ryn', 'Kai')
    $global:SeedIndex = $null

    $global:PasswordRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
}

Describe 'Структура скрипта' {
    It 'файл сохранён с UTF-8 BOM (без него Windows PowerShell 5.1 ломает кириллицу)' {
        $bytes = [System.IO.File]::ReadAllBytes($global:UufScriptPath)
        $bytes.Length | Should -BeGreaterThan 3
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
    }

    It 'скрипт разбирается парсером PowerShell без ошибок' {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($global:UufScriptPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        @($parseErrors) | Should -HaveCount 0
    }

    It 'в скрипте нет дублирующихся определений функций' {
        $names = [regex]::Matches($global:UufMainText, '(?m)^\s*function\s+([A-Za-z][A-Za-z0-9_-]*)') |
            ForEach-Object { $_.Groups[1].Value }
        $duplicates = @($names | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
        $duplicates | Should -HaveCount 0
    }

    It 'для каждой поддерживаемой платформы в воркере есть ветка проверки' {
        $global:UufWorkerBranches.Count | Should -BeGreaterThan 0
        @($global:UufWorkerBranches | Sort-Object) | Should -Be @($global:SupportedPlatforms | Sort-Object)
    }

    It 'в воркере есть ветка default для неизвестной платформы' {
        $defaultNeedle = '                default {'
        $global:UufWorkerText.Contains($defaultNeedle) | Should -BeTrue
    }

    It 'список платформ интерфейса берётся из единого источника' {
        $comboNeedle = 'PlatformBox.Items.AddRange([object[]]@($script:SupportedPlatforms))'
        $global:UufMainText.Contains($comboNeedle) | Should -BeTrue
    }

    It 'воркер отключил авто-редирект и не отправляет тело при GET и HEAD' {
        $global:UufWorkerText.Contains('MaximumRedirection=0') | Should -BeTrue
        $methodGuard = '$currentMethod -ne '
        $guardCount = ([regex]::Matches($global:UufWorkerText, [regex]::Escape($methodGuard))).Count
        $guardCount | Should -BeGreaterOrEqual 2
    }

    It 'резервный GET-запрос к валидатору Roblox удалён' {
        $global:UufWorkerText.Contains('request.username=') | Should -BeFalse
    }

    It 'воркер использует адаптивную паузу, а не фиксированную задержку' {
        $global:UufWorkerText.Contains('$currentDelayMs') | Should -BeTrue
        $global:UufWorkerText.Contains('$minDelayMs') | Should -BeTrue
        $global:UufWorkerText.Contains('$successStreak') | Should -BeTrue
        $global:UufWorkerText.Contains('consecutiveRateLimits -ge 3') | Should -BeTrue
        $global:UufWorkerText.Contains('$elapsed -lt $DelayMs') | Should -BeFalse
        $global:UufWorkerText.Contains('[Math]::Max(1200,[int]$DelayMs)') | Should -BeFalse
    }

    It 'пол паузы зависит от платформы' {
        $global:UufWorkerText.Contains('''GitHub'' { $platformFloorMs = 1000 }') | Should -BeTrue
        $global:UufWorkerText.Contains('''Roblox'' { $platformFloorMs = 600 }') | Should -BeTrue
    }

    It 'лимит количества ников за генерацию поднят до 2000' {
        $global:UufMainText.Contains('$script:CountBox = New-NumberBox 14 624 90 5 2000 40') | Should -BeTrue
    }

    It 'колонка «СТРУКТУРА» убрана из таблицы, но свойство Structure сохранено' {
        $global:UufMainText.Contains("Columns.Add('Structure'") | Should -BeFalse
        $global:UufMainText.Contains("'СТРУКТУРА'") | Should -BeFalse
        $global:UufMainText.Contains('Sort-Object Structure') | Should -BeFalse
        $global:UufFullText.Contains('Name=''Структура'';Expression={$_.Structure}') | Should -BeTrue
        $global:UufMainText.Contains('function Get-NickStructure') | Should -BeTrue
    }

    It 'исключения передаются в генератор до его запуска' {
        $global:UufFullText.Contains('-ExcludeKeys $excludeKeys') | Should -BeTrue
        $global:UufFullText.Contains('Создано {0} из {1}') | Should -BeTrue
    }

    It 'Roblox повторяет POST с токеном X-CSRF-Token' {
        $global:UufWorkerText.Contains('X-CSRF-Token') | Should -BeTrue
    }

    It 'история ников читается с явным UTF-8, а не через Get-Content' {
        $global:UufMainText.Contains('[System.IO.File]::ReadAllText($script:HistoryPath)') | Should -BeTrue
        $global:UufMainText.Contains('Get-Content -LiteralPath $script:HistoryPath -Raw') | Should -BeFalse
    }

    It 'автоширина столбцов отключается на время массовой вставки строк' {
        $global:UufMainText.Contains('$script:Grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None') | Should -BeTrue
        $global:UufMainText.Contains('$script:Grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill') | Should -BeTrue
        $global:UufMainText.Contains('if ($restoreAutoSize) {') | Should -BeTrue
    }

    It 'палитра статусов вынесена из цикла перерисовки' {
        $global:UufMainText.Contains('$script:StatusColors = @{') | Should -BeTrue
        $global:UufMainText.Contains('$color = $script:StatusColors[[string]$item.Status]') | Should -BeTrue
    }

    It 'подсказка поля ввода не считается значением' {
        $global:UufMainText.Contains('function Get-TextBoxValue') | Should -BeTrue
        $global:UufMainText.Contains('$box.Add_GotFocus({') | Should -BeTrue
        $global:UufFullText.Contains('Get-TextBoxValue $script:CustomBox') | Should -BeTrue
        $global:UufFullText.Contains('-eq ''Pixel, Void, Storm''') | Should -BeFalse
    }

    It 'свободные ники пересчитываются только при изменении списка' {
        $global:UufMainText.Contains('function Touch-Candidates') | Should -BeTrue
        $global:UufMainText.Contains('$script:CandidateRevision -eq $script:AvailableNamesRevision') | Should -BeTrue
        $touchCount = ([regex]::Matches($global:UufFullText, [regex]::Escape('Touch-Candidates'))).Count
        $touchCount | Should -BeGreaterOrEqual 6
    }

    It 'хранилище аккаунтов перенесено из папки RobloxNickFinder с миграцией' {
        $global:UufMainText.Contains('$script:VaultDirectory = Join-Path $env:LOCALAPPDATA ''UniversalUsernameFinder''') | Should -BeTrue
        $global:UufMainText.Contains('$script:LegacyVaultPath = Join-Path $script:LegacyVaultDirectory ''accounts.dat''') | Should -BeTrue
        $global:UufMainText.Contains('function Migrate-LegacyVault') | Should -BeTrue
        $global:UufMainText.Contains('.migrated') | Should -BeTrue
    }
}

Describe 'Test-UsernameFormat' {
    It 'принимает допустимый ник Roblox' {
        Test-UsernameFormat -Username 'AstraNova' -Platform 'Roblox' | Should -BeTrue
    }

    It 'принимает ник Roblox с одним подчёркиванием' {
        Test-UsernameFormat -Username 'Astra_Nova' -Platform 'Roblox' | Should -BeTrue
    }

    It 'отклоняет ник Roblox с двумя подчёркиваниями' {
        Test-UsernameFormat -Username 'Astra__Nova' -Platform 'Roblox' | Should -BeFalse
    }

    It 'отклоняет ник Roblox с подчёркиванием в конце' {
        Test-UsernameFormat -Username 'AstraNova_' -Platform 'Roblox' | Should -BeFalse
    }

    It 'отклоняет ник Roblox короче трёх и длиннее двадцати символов' {
        Test-UsernameFormat -Username 'Ab' -Platform 'Roblox' | Should -BeFalse
        Test-UsernameFormat -Username ('A' * 21) -Platform 'Roblox' | Should -BeFalse
    }

    It 'GitHub: принимает дефис, отклоняет двойной дефис и дефис по краям' {
        Test-UsernameFormat -Username 'astra-nova' -Platform 'GitHub' | Should -BeTrue
        Test-UsernameFormat -Username 'as--df' -Platform 'GitHub' | Should -BeFalse
        Test-UsernameFormat -Username '-astra' -Platform 'GitHub' | Should -BeFalse
        Test-UsernameFormat -Username 'astra-' -Platform 'GitHub' | Should -BeFalse
    }

    It 'Telegram: требует минимум пять символов и начало с буквы' {
        Test-UsernameFormat -Username 'Astra' -Platform 'Telegram' | Should -BeTrue
        Test-UsernameFormat -Username 'Astr' -Platform 'Telegram' | Should -BeFalse
        Test-UsernameFormat -Username '1astra' -Platform 'Telegram' | Should -BeFalse
    }

    It 'Discord: отклоняет зарезервированные имена' {
        Test-UsernameFormat -Username 'astra' -Platform 'Discord' | Should -BeTrue
        Test-UsernameFormat -Username 'clyde' -Platform 'Discord' | Should -BeFalse
        Test-UsernameFormat -Username 'everyone' -Platform 'Discord' | Should -BeFalse
    }

    It 'Google: точка допустима, две подряд и точка по краям — нет' {
        Test-UsernameFormat -Username 'astra.nova' -Platform 'Google' | Should -BeTrue
        Test-UsernameFormat -Username 'astra..nova' -Platform 'Google' | Should -BeFalse
        Test-UsernameFormat -Username '.astra' -Platform 'Google' | Should -BeFalse
    }

    It 'пустое имя недопустимо для любой платформы' {
        Test-UsernameFormat -Username '' -Platform 'Roblox' | Should -BeFalse
        Test-UsernameFormat -Username '   ' -Platform 'GitHub' | Should -BeFalse
    }
}

Describe 'Test-SupportedPlatform' {
    It 'признаёт все платформы из списка' {
        foreach ($platform in $global:SupportedPlatforms) {
            Test-SupportedPlatform -Platform $platform | Should -BeTrue
        }
    }

    It 'отклоняет платформы без реализации проверки' {
        Test-SupportedPlatform -Platform 'Steam' | Should -BeTrue
        Test-UsernameFormat -Username 'ab' -Platform 'Steam' | Should -BeFalse
        Test-UsernameFormat -Username 'goodNick-1' -Platform 'Steam' | Should -BeTrue
        Test-SupportedPlatform -Platform 'Reddit' | Should -BeFalse
        Test-SupportedPlatform -Platform 'Instagram' | Should -BeFalse
    }

    It 'отклоняет пустое значение' {
        Test-SupportedPlatform -Platform '' | Should -BeFalse
    }
}

Describe 'Get-ShuffledArray' {
    It 'сохраняет состав и количество элементов' {
        $items = 1..60
        $shuffled = @(Get-ShuffledArray -Items $items)
        $shuffled | Should -HaveCount 60
        (($shuffled | Sort-Object) -join ',') | Should -Be ((1..60 | Sort-Object) -join ',')
    }

    It 'не изменяет исходный массив' {
        $items = @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
        $before = $items -join ','
        $null = Get-ShuffledArray -Items $items
        ($items -join ',') | Should -Be $before
    }

    It 'действительно меняет порядок' {
        $items = 1..60
        $shuffled = @(Get-ShuffledArray -Items $items)
        ($shuffled -join ',') | Should -Not -Be (($items) -join ',')
    }

    It 'корректно работает с пустым массивом и одним элементом' {
        @(Get-ShuffledArray -Items @()) | Should -HaveCount 0
        (@(Get-ShuffledArray -Items @('x')) -join ',') | Should -Be 'x'
    }
}

Describe 'New-SecurePassword' {
    It 'возвращает пароль запрошенной длины' {
        (New-SecurePassword -Length 20).Length | Should -Be 20
        (New-SecurePassword -Length 16).Length | Should -Be 16
        (New-SecurePassword -Length 32).Length | Should -Be 32
    }

    It 'использует только допустимые символы без неоднозначных' {
        $allowed = 'ABCDEFGHJKLMNPQRSTUVWXYZ' + 'abcdefghjkmnpqrstuvwxyz' + '23456789' + '!@#$%^&*-_=+?'
        $passwords = @(1..20 | ForEach-Object { New-SecurePassword -Length 24 })
        foreach ($password in $passwords) {
            foreach ($char in $password.ToCharArray()) {
                $allowed.Contains([string]$char) | Should -BeTrue
            }
        }
    }

    It 'содержит заглавную, строчную букву и цифру' {
        $password = New-SecurePassword -Length 20
        $password | Should -Match '[A-Z]'
        $password | Should -Match '[a-z]'
        $password | Should -Match '[0-9]'
    }

    It 'не повторяется от запуска к запуску' {
        $passwords = @(1..50 | ForEach-Object { New-SecurePassword -Length 20 })
        @($passwords | Select-Object -Unique) | Should -HaveCount 50
    }

    It 'отклоняет длину вне диапазона 16-32' {
        { New-SecurePassword -Length 15 } | Should -Throw
        { New-SecurePassword -Length 33 } | Should -Throw
    }
}

Describe 'Write-AtomicJsonFile и Write-AtomicFile' {
    BeforeAll {
        $script:AtomicDirectory = Join-Path $TestDrive ('atomic-' + [guid]::NewGuid().ToString('N'))
        $null = [System.IO.Directory]::CreateDirectory($script:AtomicDirectory)
    }

    It 'пишет JSON в UTF-8 с BOM' {
        $file = Join-Path $script:AtomicDirectory 'bom.json'
        Write-AtomicJsonFile -Path $file -Json (@{ Style = 'Английские' } | ConvertTo-Json -Depth 3)
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
        ([System.IO.File]::ReadAllText($file) | ConvertFrom-Json).Style | Should -Be 'Английские'
    }

    It 'перезаписывает существующий файл' {
        $file = Join-Path $script:AtomicDirectory 'overwrite.json'
        Write-AtomicJsonFile -Path $file -Json '{"a":1}'
        Write-AtomicJsonFile -Path $file -Json '{"b":2}'
        $loaded = [System.IO.File]::ReadAllText($file) | ConvertFrom-Json
        $loaded.b | Should -Be 2
        $loaded.PSObject.Properties.Name -contains 'a' | Should -BeFalse
    }

    It 'создаёт отсутствующую папку и не оставляет временных файлов' {
        $nested = Join-Path (Join-Path $script:AtomicDirectory 'deep') 'inner'
        $file = Join-Path $nested 'created.json'
        Write-AtomicFile -Path $file -Bytes ([byte[]](0xEF, 0xBB, 0xBF, 0x7B, 0x7D))
        Test-Path -LiteralPath $file | Should -BeTrue
        [System.IO.File]::ReadAllText($file) | Should -Be '{}'
        @(Get-ChildItem -LiteralPath $nested -Filter '*.tmp').Count | Should -Be 0
    }

    It 'записывает пустую строку как валидный пустой JSON' {
        $file = Join-Path $script:AtomicDirectory 'empty.json'
        Write-AtomicJsonFile -Path $file -Json ''
        ([System.IO.File]::ReadAllText($file)).Length | Should -Be 0
    }
}

Describe 'Export-AppSettings и Import-AppSettings' {
    BeforeAll {
        $script:SettingsDirectory = Join-Path $TestDrive ('settings-' + [guid]::NewGuid().ToString('N'))
        $null = [System.IO.Directory]::CreateDirectory($script:SettingsDirectory)
        $script:SettingsFile = Join-Path $script:SettingsDirectory 'settings.json'
        $script:SampleSettings = @{
            AppVersion = '2.5.2'
            Platform = 'Roblox'
            Style = 'Английские'
            Count = 150
            MinLength = 3
            MaxLength = 20
            DelayMs = 2500
            TimeoutMs = 15000
            UseNumbers = $true
            OnlyFree = $false
            Categories = @('Киберпанк', 'Фэнтези')
            WindowState = 'Normal'
            WindowBounds = @{ X = 100; Y = 80; Width = 1240; Height = 900 }
        }
    }

    It 'сохраняет настройки и читает их обратно без потерь' {
        Export-AppSettings -Settings $script:SampleSettings -Path $script:SettingsFile
        Test-Path -LiteralPath $script:SettingsFile | Should -BeTrue
        $loaded = Import-AppSettings -Path $script:SettingsFile
        $loaded['Platform'] | Should -Be 'Roblox'
        $loaded['Style'] | Should -Be 'Английские'
        [int]$loaded['Count'] | Should -Be 150
        [int]$loaded['DelayMs'] | Should -Be 2500
        [bool]$loaded['UseNumbers'] | Should -BeTrue
        [bool]$loaded['OnlyFree'] | Should -BeFalse
        @($loaded['Categories']).Count | Should -Be 2
        @($loaded['Categories']) -contains 'Фэнтези' | Should -BeTrue
        [int]$loaded['WindowBounds'].X | Should -Be 100
        [int]$loaded['WindowBounds'].Width | Should -Be 1240
    }

    It 'пишет файл в UTF-8 с BOM, чтобы кириллица не ломалась в Windows PowerShell 5.1' {
        $bytes = [System.IO.File]::ReadAllBytes($script:SettingsFile)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
    }

    It 'не оставляет временных файлов после записи' {
        @(Get-ChildItem -LiteralPath $script:SettingsDirectory -Filter '*.tmp').Count | Should -Be 0
    }

    It 'перезапись существующего файла сохраняет валидный JSON' {
        $changed = @{ Platform = 'GitHub'; Count = 40 }
        Export-AppSettings -Settings $changed -Path $script:SettingsFile
        $loaded = Import-AppSettings -Path $script:SettingsFile
        $loaded['Platform'] | Should -Be 'GitHub'
        [int]$loaded['Count'] | Should -Be 40
        $loaded.ContainsKey('DelayMs') | Should -BeFalse
    }

    It 'возвращает пустой набор для отсутствующего файла' {
        $missing = Join-Path $script:SettingsDirectory 'no-such-settings.json'
        $loaded = Import-AppSettings -Path $missing
        $loaded.Count | Should -Be 0
    }

    It 'не падает на повреждённом файле настроек' {
        $corrupt = Join-Path $script:SettingsDirectory 'corrupt.json'
        [System.IO.File]::WriteAllText($corrupt, '{ "Platform": "Roblox", "Count": ')
        $loaded = Import-AppSettings -Path $corrupt
        $loaded.Count | Should -Be 0
    }

    It 'не падает на пустом файле настроек' {
        $empty = Join-Path $script:SettingsDirectory 'empty.json'
        [System.IO.File]::WriteAllText($empty, '   ')
        (Import-AppSettings -Path $empty).Count | Should -Be 0
    }

    It 'корректно сохраняет набор с одной категорией' {
        $single = @{ Categories = @('Фэнтези') }
        $file = Join-Path $script:SettingsDirectory 'single.json'
        Export-AppSettings -Settings $single -Path $file
        $loaded = Import-AppSettings -Path $file
        @($loaded['Categories']).Count | Should -Be 1
        @($loaded['Categories'])[0] | Should -Be 'Фэнтези'
    }
}

Describe 'Get-NickStructure' {
    It 'распознаёт склейку двух слов по внутренней заглавной букве' {
        Get-NickStructure -Name 'BoomSquare' | Should -Be 'Два слова'
        Get-NickStructure -Name 'NovaVoid' | Should -Be 'Два слова'
        Get-NickStructure -Name 'StormPixel' | Should -Be 'Два слова'
    }

    It 'распознаёт два слова через разделитель' {
        Get-NickStructure -Name 'Boom_Square' | Should -Be 'Два слова'
        Get-NickStructure -Name 'Nova_Void' | Should -Be 'Два слова'
    }

    It 'распознаёт слитное написание разбиением по словарю' {
        Get-NickStructure -Name 'boomsquare' | Should -Be 'Два слова'
    }

    It 'одиночное слово остаётся одиночным' {
        Get-NickStructure -Name 'Nova' | Should -Be 'Одно слово'
        Get-NickStructure -Name 'Shadow' | Should -Be 'Одно слово'
        Get-NickStructure -Name 'Orbit' | Should -Be 'Одно слово'
    }

    It 'пустое имя и имя с цифрами не ломают определение' {
        Get-NickStructure -Name '' | Should -Be 'Одно слово'
        Get-NickStructure -Name '   ' | Should -Be 'Одно слово'
        Get-NickStructure -Name 'Nova42' | Should -Be 'Одно слово'
        Get-NickStructure -Name 'NovaVoid42' | Should -Be 'Два слова'
    }
}

Describe 'New-AdvancedCandidatePool' {
    It 'однословная генерация возвращает ровно запрошенное количество' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 5 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $false -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 5
        @($pool | Where-Object { [string]$_.Structure -ne 'Одно слово' }) | Should -HaveCount 0
    }

    It 'при обеих галочках создаются и однословные, и двухсловные ники' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 20
        $single = @($pool | Where-Object { [string]$_.Structure -eq 'Одно слово' })
        $pair = @($pool | Where-Object { [string]$_.Structure -eq 'Два слова' })
        $single.Count | Should -BeGreaterThan 0
        $pair.Count | Should -BeGreaterOrEqual 8
        $global:GenerationStats['Single'] | Should -Be $single.Count
        $global:GenerationStats['Pair'] | Should -Be $pair.Count
    }

    It 'галочка «Использовать цифры» даёт числовые варианты даже при полном пространстве имён' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $true -UseUnderscore $false -OneWord $true -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 20
        $numeric = @($pool | Where-Object { ([string]$_.Name) -match '[0-9]' })
        $numeric.Count | Should -BeGreaterOrEqual 5
        $global:GenerationStats['Number'] | Should -BeGreaterOrEqual 5
    }

    It 'без галочки «Использовать цифры» числовых вариантов нет' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        @($pool | Where-Object { ([string]$_.Name) -match '[0-9]' }) | Should -HaveCount 0
        $global:GenerationStats['Number'] | Should -Be 0
    }

    It 'двухсловная генерация помечает склейки как «Два слова» и относит к категории «Двусловные»' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 30 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 30
        @($pool | Where-Object { [string]$_.Structure -ne 'Два слова' }) | Should -HaveCount 0
        @($pool | Where-Object { [string]$_.Category -ne 'Двусловные' }) | Should -HaveCount 0
    }

    It 'структура, заданная генератором, совпадает с определением по имени' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $pool.Count | Should -BeGreaterThan 0
        foreach ($candidate in $pool) {
            Get-NickStructure -Name ([string]$candidate.Name) | Should -Be ([string]$candidate.Structure)
        }
    }

    It 'уже использованные ники отсеиваются внутри генератора, и количество добирается' {
        $excludeKeys = @{}
        $first = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $first | Should -HaveCount 10
        foreach ($candidate in $first) {
            $excludeKeys[(Get-HistoryKey -Name ([string]$candidate.Name) -Platform 'Roblox')] = $true
        }
        $second = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @() -ExcludeKeys $excludeKeys)
        $second | Should -HaveCount 10
        foreach ($candidate in $second) {
            $excludeKeys.ContainsKey((Get-HistoryKey -Name ([string]$candidate.Name) -Platform 'Roblox')) | Should -BeFalse
        }
    }

    It 'при исчерпании пространства возвращается меньше, а статистика объясняет причину' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 5 -MaxLength 20 -Count 50 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $false -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 6
        $global:GenerationStats['ByLength'] | Should -Be 2
    }

    It 'стиль «Двусловный» даёт два слова, даже если галочка двухсловной генерации снята' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style 'Двусловный' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $false -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 10
        @($pool | Where-Object { [string]$_.Structure -ne 'Два слова' }) | Should -HaveCount 0
    }

    It 'свои слова через пробел не склеиваются в один ник' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @() -CustomWords 'boom square' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $false -OnlyShort $false -ExcludeTokens @())
        @($pool | Where-Object { [string]$_.Name -eq 'BoomSquare' }) | Should -HaveCount 0
        @($pool | Where-Object { [string]$_.Name -eq 'Boom' }) | Should -HaveCount 1
        @($pool | Where-Object { [string]$_.Name -eq 'Square' }) | Should -HaveCount 1
    }

    It 'с разделителем каждая склейка содержит подчёркивание' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $true -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 10
        @($pool | Where-Object { ([string]$_.Name).IndexOf('_') -lt 0 }) | Should -HaveCount 0
    }

    It 'слова-исключения отсеиваются и учитываются в статистике' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 40 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @('Void'))
        @($pool | Where-Object { ([string]$_.Name).IndexOf('Void') -ge 0 }) | Should -HaveCount 0
        $global:GenerationStats['ByExcludedToken'] | Should -BeGreaterThan 0
    }

    It 'большое количество ников создаётся без материализации всех пар' {
        $measure = Measure-Command {
            $global:BigPool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 60 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        }
        $global:BigPool | Should -HaveCount 60
        $measure.TotalSeconds | Should -BeLessThan 10
    }
}

Describe 'Convert-ToNickToken' {
    It 'переводит известные русские тематики в английские токены' {
        Convert-ToNickToken -Text 'океан' | Should -Be 'Ocean'
        Convert-ToNickToken -Text 'киберпанк' | Should -Be 'Cyberpunk'
        Convert-ToNickToken -Text 'ночь' | Should -Be 'Night'
    }

    It 'транслитерирует произвольное русское слово и начинает с заглавной' {
        Convert-ToNickToken -Text 'тест' | Should -Be 'Test'
        Convert-ToNickToken -Text 'медведь' | Should -Be 'Medved'
        Convert-ToNickToken -Text 'ясень' | Should -Be 'Yasen'
    }

    It 'отбрасывает пробелы и недопустимые символы, сохраняя цифры' {
        Convert-ToNickToken -Text 'тест 123' | Should -Be 'Test123'
    }

    It 'возвращает пустую строку для пустого ввода' {
        Convert-ToNickToken -Text '' | Should -Be ''
        Convert-ToNickToken -Text '   ' | Should -Be ''
    }
}

Describe 'New-InventedWord' {
    It 'возвращает слово в заданных границах длины' {
        for ($i = 0; $i -lt 40; $i++) {
            $word = [string](New-InventedWord -MinLength 4 -MaxLength 9)
            $word.Length | Should -BeGreaterOrEqual 4
            $word.Length | Should -BeLessOrEqual 9
        }
    }

    It 'слово начинается с заглавной буквы и состоит только из букв' {
        for ($i = 0; $i -lt 40; $i++) {
            [string](New-InventedWord -MinLength 3 -MaxLength 8) | Should -Match '^[A-Z][a-z]+$'
        }
    }

    It 'даёт разные слова от вызова к вызову' {
        $words = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt 25; $i++) { [void]$words.Add([string](New-InventedWord -MinLength 4 -MaxLength 9)) }
        (@($words | Select-Object -Unique)).Count | Should -BeGreaterThan 1
    }

    It 'не падает, если минимальная длина больше максимальной' {
        $word = [string](New-InventedWord -MinLength 9 -MaxLength 3)
        $word.Length | Should -BeGreaterThan 0
        $word.Length | Should -BeLessOrEqual 9
    }
}

Describe 'Convert-ToLeetWord' {
    It 'заменяет буквы похожими цифрами' {
        Convert-ToLeetWord -Word 'Void' -MaxSubstitutions 2 | Should -Be 'V01d'
    }

    It 'никогда не заменяет первую букву' {
        Convert-ToLeetWord -Word 'anna' -MaxSubstitutions 5 | Should -Be 'ann4'
    }

    It 'сохраняет заглавную букву в середине слова' {
        Convert-ToLeetWord -Word 'VoidStorm' -MaxSubstitutions 10 | Should -Match '^[A-Za-z0-9]*S[A-Za-z0-9]*$'
        ([string](Convert-ToLeetWord -Word 'VoidStorm' -MaxSubstitutions 10)).Contains('S') | Should -BeTrue
    }

    It 'не трогает слово, в котором нечего заменять' {
        Convert-ToLeetWord -Word 'Puff' -MaxSubstitutions 3 | Should -Be 'Puff'
    }

    It 'при пределе замен меньше единицы возвращает слово без изменений' {
        Convert-ToLeetWord -Word 'Void' -MaxSubstitutions 0 | Should -Be 'Void'
    }

    It 'число замен не превышает заданный предел' {
        $result = [string](Convert-ToLeetWord -Word 'Senses' -MaxSubstitutions 1)
        $result.Length | Should -Be 6
        @([regex]::Matches($result, '[0-9]')).Count | Should -Be 1
    }

    It 'пустая строка возвращается как есть' {
        Convert-ToLeetWord -Word '' -MaxSubstitutions 2 | Should -Be ''
    }
}

Describe 'Get-PlatformLengthRule' {
    It 'возвращает границы длины для известных платформ' {
        $roblox = Get-PlatformLengthRule -Platform 'Roblox'
        $roblox.Min | Should -Be 3
        $roblox.Max | Should -Be 20
        (Get-PlatformLengthRule -Platform 'Google').Min | Should -Be 6
        (Get-PlatformLengthRule -Platform 'Steam').Max | Should -Be 30
        (Get-PlatformLengthRule -Platform 'Steam').Min | Should -Be 3
        (Get-PlatformLengthRule -Platform 'GitHub').Min | Should -Be 1
    }

    It 'для неизвестной платформы возвращает нейтральные границы' {
        $rule = Get-PlatformLengthRule -Platform 'Несуществующая'
        $rule.Min | Should -Be 3
        $rule.Max | Should -Be 32
    }

    It 'границы из правила совпадают с валидатором формата для всех платформ' {
        foreach ($platform in $global:SupportedPlatforms) {
            $rule = Get-PlatformLengthRule -Platform $platform
            Test-UsernameFormat -Username ('a' * $rule.Min) -Platform $platform | Should -BeTrue
            Test-UsernameFormat -Username ('a' * $rule.Max) -Platform $platform | Should -BeTrue
            Test-UsernameFormat -Username ('a' * ($rule.Max + 1)) -Platform $platform | Should -BeFalse
        }
    }
}

Describe 'Новые источники генерации' {
    It 'выдуманные слова добирают количество, когда словарь уже исчерпан' {
        $excludeKeys = @{}
        foreach ($word in @('Nova', 'Echo', 'Pulse', 'Orbit', 'Frost', 'Shadow', 'Raven', 'Comet')) {
            $excludeKeys[(Get-HistoryKey -Name $word -Platform 'Roblox')] = $true
        }
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $false -InventedWords $true -OnlyShort $false -ExcludeTokens @() -ExcludeKeys $excludeKeys)
        $pool | Should -HaveCount 10
        $global:GenerationStats['Single'] | Should -Be 0
        $global:GenerationStats['Invented'] | Should -Be 10
    }

    It 'своё слово входит в каждый созданный ник' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords 'Void' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 12 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -InventedWords $true -InventedPairs $true -RareShort $false -LeetWords $false -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 12
        @($pool | Where-Object { ([string]$_.Name).IndexOf('Void', [StringComparison]::OrdinalIgnoreCase) -lt 0 }) | Should -HaveCount 0
    }

    It 'замена символами даёт ники с цифрами без галочки «Использовать цифры»' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $false -LeetWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 10
        @($pool | Where-Object { ([string]$_.Name) -notmatch '[0-9]' }) | Should -HaveCount 0
        $global:GenerationStats['Number'] | Should -Be 0
        $global:GenerationStats['Leet'] | Should -Be 10
    }

    It 'редкие короткие ники укладываются в 3-6 символов' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 8 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $false -RareShort $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 8
        @($pool | Where-Object { ([string]$_.Name).Length -lt 3 -or ([string]$_.Name).Length -gt 6 }) | Should -HaveCount 0
        $global:GenerationStats['Rare'] | Should -Be 8
    }

    It 'выдуманные словосочетания помечаются как два слова' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @() -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 8 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $false -InventedPairs $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 8
        @($pool | Where-Object { [string]$_.Structure -ne 'Два слова' }) | Should -HaveCount 0
        @($pool | Where-Object { [string]$_.Category -ne 'Выдуманные словосочетания' }) | Should -HaveCount 0
    }

    It 'структура ников из новых источников совпадает с определением по имени' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords 'Void' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $true -UseUnderscore $false -OneWord $true -TwoWords $true -InventedWords $true -InventedPairs $true -RareShort $true -LeetWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 20
        foreach ($candidate in $pool) {
            Get-NickStructure -Name ([string]$candidate.Name) | Should -Be ([string]$candidate.Structure)
        }
    }

    It 'генерация по порядку сохраняет последовательность источников' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -Ordered $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 20
        @($pool[0..7] | Where-Object { [string]$_.Structure -ne 'Одно слово' }) | Should -HaveCount 0
        @($pool[8..19] | Where-Object { [string]$_.Structure -ne 'Два слова' }) | Should -HaveCount 0
    }

    It 'без галочки «Генерация по порядку» выдача перемешивается' {
        $firstNames = New-Object System.Collections.ArrayList
        for ($run = 0; $run -lt 5; $run++) {
            $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -OnlyShort $false -ExcludeTokens @())
            [void]$firstNames.Add([string]$pool[0].Name)
        }
        (@($firstNames | Select-Object -Unique)).Count | Should -BeGreaterThan 1
    }
}

Describe 'Интерфейс и поведение версии 2.5.5' {
    It 'список категорий строится из того же массива, которым пользуется генератор' {
        # v2.8.3: список тот же, но отсортирован по алфавиту
        $global:UufMainText.Contains('AddRange([object[]]@($script:WordCategories | Sort-Object))') | Should -BeTrue
        $global:UufMainText.Contains('$script:WordCategories = @(') | Should -BeTrue
    }

    It 'категории «Цельные слова» и «Короткие» убраны из выбора' {
        $global:UufFullText.Contains("'Цельные слова'") | Should -BeFalse
        $global:UufMainText.Contains('$script:RareShortCheck = New-CheckBox') | Should -BeTrue
    }

    It 'есть кнопки выделить и снять все категории' {
        $global:UufMainText.Contains('$script:CheckAllCategoriesButton') | Should -BeTrue
        $global:UufMainText.Contains('$script:UncheckAllCategoriesButton') | Should -BeTrue
    }

    It 'все новые источники генерации доступны в настройках' {
        $global:UufMainText.Contains('$script:InventedWordsCheck = New-CheckBox') | Should -BeTrue
        $global:UufMainText.Contains('$script:InventedPairsCheck = New-CheckBox') | Should -BeTrue
        $global:UufMainText.Contains('$script:LeetCheck = New-CheckBox') | Should -BeTrue
        $global:UufMainText.Contains('$script:RareShortCheck = New-CheckBox') | Should -BeTrue
        $global:UufMainText.Contains('$script:OrderedCheck = New-CheckBox') | Should -BeTrue
        $global:UufFullText.Contains('-InventedWords ([bool]$script:InventedWordsCheck.Checked)') | Should -BeTrue
        $global:UufFullText.Contains('-InventedPairs ([bool]$script:InventedPairsCheck.Checked)') | Should -BeTrue
        $global:UufFullText.Contains('-LeetWords ([bool]$script:LeetCheck.Checked)') | Should -BeTrue
        $global:UufFullText.Contains('-RareShort ([bool]$script:RareShortCheck.Checked)') | Should -BeTrue
        $global:UufFullText.Contains('-Ordered ([bool]$script:OrderedCheck.Checked)') | Should -BeTrue
    }

    It 'число потоков задаётся в интерфейсе и ограничено восемью' {
        $global:UufMainText.Contains('$script:ThreadsBox = New-NumberBox 254 910 110 1 8 2') | Should -BeTrue
        $global:UufMainText.Contains('Рекомендуется 2–4 потока') | Should -BeTrue
        $global:UufMainText.Contains('if ($threadCount -gt 8) { $threadCount = 8 }') | Should -BeTrue
    }

    It 'проверка идёт в несколько потоков через общую очередь' {
        $global:UufFullText.Contains('for ($workerIndex = 1; $workerIndex -le $threadCount; $workerIndex++)') | Should -BeTrue
        $global:UufWorkerText.Contains('$InputQueue.TryDequeue([ref]$item)') | Should -BeTrue
        $global:UufMainText.Contains('function Test-CheckRunning') | Should -BeTrue
        $global:UufFullText.Contains('-and -not (Test-CheckRunning)) {') | Should -BeTrue
    }

    It 'сортировка по умолчанию — порядок генерации, а не алфавит' {
        $global:UufMainText.Contains("'Порядок генерации'") | Should -BeTrue
        $global:UufMainText.Contains('$script:SortBox.SelectedIndex = 0') | Should -BeTrue
    }

    It 'под полосой прогресса выводится оценка оставшегося времени' {
        $global:UufMainText.Contains('function Get-CheckEtaText') | Should -BeTrue
        $global:UufMainText.Contains('осталось ~') | Should -BeTrue
        $global:UufFullText.Contains('$script:CheckStartedAt = [DateTime]::UtcNow') | Should -BeTrue
    }

    It 'позиция прокрутки таблицы сохраняется при перерисовке' {
        $global:UufMainText.Contains('FirstDisplayedScrollingRowIndex') | Should -BeTrue
    }

    It 'таблица очищается перед каждой генерацией' {
        $global:UufFullText.Contains('$script:Candidates.Clear()') | Should -BeTrue
    }

    It 'список проверенных имён сохраняется между сеансами' {
        $global:UufMainText.Contains('CheckedNames = @($script:CheckedNames.Keys') | Should -BeTrue
        $global:UufMainText.Contains('$historyData.CheckedNames') | Should -BeTrue
        $global:UufMainText.Contains('function Update-CheckedNamesButtonText') | Should -BeTrue
    }

    It 'потолок в 30 свободных ников снят' {
        $global:UufFullText.Contains('Select-Object -First 29') | Should -BeFalse
        $global:UufMainText.Contains('$script:FreeHistory = @(@($entry) + @($remaining))') | Should -BeTrue
    }

    It 'выбор платформы подставляет правило длины' {
        $global:UufFullText.Contains('Get-PlatformLengthRule -Platform $selectedPlatform') | Should -BeTrue
    }
}

Describe 'Платформы, домены и интерфейс версии 2.6.0' {
    It 'почтовые платформы добавляют домен к нику' {
        Get-PlatformDomain -Platform 'Google' | Should -Be 'gmail.com'
        Get-PlatformDomain -Platform 'Mail.ru' | Should -Be 'mail.ru'
        Get-PlatformDomain -Platform 'Outlook' | Should -Be 'outlook.com'
        Get-PlatformDomain -Platform 'Roblox' | Should -Be ''
        Get-DisplayNick -Platform 'Google' -Name 'voidstorm' | Should -Be 'voidstorm@gmail.com'
        Get-DisplayNick -Platform 'GitHub' -Name 'voidstorm' | Should -Be 'voidstorm'
    }
    It 'Telegram Channel убрана, Steam добавлена' {
        $global:SupportedPlatforms -contains 'TikTok' | Should -BeFalse
        $global:SupportedPlatforms -contains 'Apple' | Should -BeFalse
        $global:SupportedPlatforms -contains 'Microsoft' | Should -BeFalse
        $global:SupportedPlatforms -contains 'Telegram Channel' | Should -BeFalse
        $global:SupportedPlatforms -contains 'Steam' | Should -BeTrue
        $global:UufWorkerText.Contains('# --- Steam Api') | Should -BeTrue
    }
    It 'источник случайных символов работает автономно' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @() -CustomWords '' -Style '— без стиля —' -Platform 'Roblox' -MinLength 4 -MaxLength 12 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $false -OnlyShort $false -ExcludeTokens @() -RandomChars $true)
        $pool.Count | Should -Be 10
        foreach ($item in $pool) { $item.Category | Should -Be 'Случайные символы' }
    }
    It 'регистрация открывается в инкогнито под текущую платформу' {
        Get-RegistrationUrl -Platform 'Google' | Should -Be 'https://accounts.google.com/signup'
        Get-RegistrationUrl -Platform 'Outlook' | Should -Be 'https://signup.live.com/'
        $global:UufMainText.Contains('--incognito') | Should -BeTrue
        $global:UufMainText.Contains('function Open-UrlInIncognito') | Should -BeTrue
        $global:UufMainText.Contains('function Update-AccountPlatformUi') | Should -BeTrue
    }
    It 'стандартный набор выставлен при запуске' {
        $global:UufMainText.Contains('$script:StyleBox.SelectedItem = ' + [char]39 + '— без стиля —' + [char]39) | Should -BeTrue
        $global:UufMainText.Contains('$script:MaxLengthBox = New-NumberBox 216 624 80 1 64 25') | Should -BeTrue
        $global:UufMainText.Contains('$script:RandomCharsCheck = New-CheckBox ' + [char]39 + 'Случайные символы' + [char]39 + ' 14 803 180 $true') | Should -BeTrue
        $global:UufMainText.Contains('$script:TwoWordsCheck = New-CheckBox ' + [char]39 + 'Два осмысленных слова' + [char]39 + ' 194 683 170 $false') | Should -BeTrue
        $global:UufMainText.Contains('$script:DelayBox = New-NumberBox 14 910 110 500 15000 700') | Should -BeTrue
    }
    It 'интерфейс тёмный v2.5.5, кастомная строка заголовка, без анимаций' {
        $global:UufMainText.Contains('$script:Form.FormBorderStyle = ' + [char]39 + 'None' + [char]39) | Should -BeTrue
        $global:UufMainText.Contains('UufResizeFrame') | Should -BeFalse
        $global:UufMainText.Contains('CaptionBar') | Should -BeFalse
        $global:UufMainText.Contains('$script:SplashForm') | Should -BeFalse
        $global:UufMainText.Contains('Start-ColorTransition') | Should -BeFalse
        $global:UufMainText.Contains('New-Object System.Drawing.Point($windowWidth -') | Should -BeFalse
        $global:UufMainText.Contains('$script:Form.BackColor = [System.Drawing.Color]::FromArgb(15,19,27)') | Should -BeTrue
        $global:UufMainText.Contains('[System.Drawing.Color]::FromArgb(93,73,222)') | Should -BeTrue
        $global:UufMainText.Contains('[System.Drawing.Image]::FromFile($logoPngPath)') | Should -BeTrue
        $global:UufMainText.Contains('$Window.Icon = $script:AppIconCached') | Should -BeTrue
    }
    It 'история свободных ников показывается в порядке генерации без выбора сортировки' {
        $global:UufMainText.Contains('HistorySortBox') | Should -BeFalse
        $global:UufMainText.Contains('По платформе и дате') | Should -BeFalse
        $global:UufMainText.Contains('$historyItems = @($script:FreeHistory)') | Should -BeTrue
    }
    It 'помощь стала полноценным разделом с вкладками' {
        $global:UufMainText.Contains('$helpForm.Text = ' + [char]39 + 'UUF — помощь' + [char]39) | Should -BeTrue
        $global:UufMainText.Contains("@{ Title = 'Дисклеймер'") | Should -BeTrue
        $global:UufMainText.Contains("@{ Title = 'Пользование'") | Should -BeTrue
        $global:UufMainText.Contains("@{ Title = 'Как устроено?'") | Should -BeTrue
        $global:UufMainText.Contains("@{ Title = 'Настройки'") | Should -BeTrue
        $global:UufMainText.Contains("@{ Title = 'Правила ввода'") | Should -BeTrue
    }
    It 'исполняемый файл переименован в UUF и получает иконку' {
        $buildText = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\build\Build-Exe.ps1'), [System.Text.Encoding]::UTF8)
        $buildText.Contains('Join-Path $OutputDirectory ' + [char]39 + 'UUF.exe' + [char]39) | Should -BeTrue
        $buildText.Contains('iconFile') | Should -BeTrue
    }
    It 'в коде не осталось пояснительных комментариев, только маркеры блоков' {
        $longComments = @($global:UufFullText -split "`n" | Where-Object { $_ -match '^\s*#' -and $_ -notmatch '^\s*#\s*---' })
        $longComments.Count | Should -Be 0
    }
}

Describe 'Изменения версии 2.8.0' {
    It 'логотип и иконка встроены в скрипт и подхватываются без папки assets' {
        $global:UufMainText.Contains('$script:AppLogoB64 = ') | Should -BeTrue
        $global:UufMainText.Contains('$script:AppIconB64 = ') | Should -BeTrue
        $global:UufMainText.Contains('[System.Convert]::FromBase64String($script:AppIconB64)') | Should -BeTrue
        $global:UufMainText.Contains('function Set-WindowChrome') | Should -BeTrue
    }
    It 'история свободных ников фильтруется по выбранным платформам' {
        $global:UufMainText.Contains('$script:HistoryPlatformList = New-Object System.Windows.Forms.CheckedListBox') | Should -BeTrue
        $global:UufMainText.Contains('$platformFilter -contains [string]$_.Platform') | Should -BeTrue
    }
    It 'правила формата почты соответствуют официальным требованиям' {
        Test-UsernameFormat -Username '2move_x' -Platform 'Mail.ru' | Should -BeTrue
        Test-UsernameFormat -Username 'ivan.petrov-1' -Platform 'Mail.ru' | Should -BeTrue
        Test-UsernameFormat -Username 'bad..name' -Platform 'Mail.ru' | Should -BeFalse
        Test-UsernameFormat -Username '_lead' -Platform 'Mail.ru' | Should -BeFalse
        Test-UsernameFormat -Username 'ab.cd' -Platform 'Google' | Should -BeFalse
        Test-UsernameFormat -Username 'ab.cd.12' -Platform 'Google' | Should -BeTrue
        (Get-PlatformLengthRule -Platform 'Mail.ru').Min | Should -Be 5
    }
    It 'подсказка формата платформы показывается пользователю' {
        $global:UufMainText.Contains('function Get-PlatformFormatHint') | Should -BeTrue
        $global:UufMainText.Contains('$script:PlatformFormatHints = @{') | Should -BeTrue
    }
    It 'интерфейс собирается в легальной геометрии без наложений' {
        $global:UufMainText.Contains('$script:CountBox = New-NumberBox 14 624 90 5 2000 40') | Should -BeTrue
        $global:UufMainText.Contains('$designWindowSize = New-Object System.Drawing.Size(1480, 1040)') | Should -BeTrue
        $global:UufMainText.Contains('$script:CategoryList.Size = New-Object System.Drawing.Size(350, 306)') | Should -BeTrue
    }
}

Describe 'Изменения версии 2.8.1' {
    It 'логотип в шапке прижат к левому краю к слову Universal' {
        $global:UufMainText.Contains('$headerLogo.Anchor = ' + [char]39 + 'Top, Left' + [char]39) | Should -BeTrue
        $global:UufMainText.Contains('$headerLogo.Location = New-Object System.Drawing.Point(14, 22)') | Should -BeTrue
    }
    It 'фильтр истории показывает все платформы, а не только встреченные' {
        $global:UufMainText.Contains('$historyOrderedPlatforms = @($script:SupportedPlatforms)') | Should -BeTrue
        $global:UufMainText.Contains('$script:HistoryPlatformList.SetItemChecked($historyPlatformIndex, ($historyPlatforms -contains $historyItemPlatform))') | Should -BeTrue
    }
    It 'перерисовка истории совместима с Windows PowerShell 5.1' {
        $global:UufMainText.Contains('BeginInvoke([System.Action]{ Refresh-FreeHistoryList })') | Should -BeTrue
        $global:UufMainText.Contains('BeginInvoke({ Refresh-FreeHistoryList })') | Should -BeFalse
    }
    It 'помощь выровнена висячими отступами без плашек' {
        $global:UufMainText.Contains('function Add-HelpCard {') | Should -BeTrue
        $global:UufMainText.Contains('function Set-HelpCardLayout {') | Should -BeTrue
        $global:UufMainText.Contains('$pageBox.SelectionBackColor = [System.Drawing.Color]::FromArgb(32,41,56)') | Should -BeFalse
    }
    It 'в интерфейсе не осталось перенесённых якорей и мусора сортировки' {
        $global:UufMainText.Contains('$historySort') | Should -BeFalse
        $global:UufMainText.Contains('По времени') | Should -BeFalse
    }
}

Describe 'Изменения версии 2.8.2' {
    It 'кастомная строка заголовка: кнопки свернуть, в полный экран и закрыть' {
        $global:UufMainText.Contains('$script:MinimizeButton = New-UufCaptionButton ') | Should -BeTrue
        $global:UufMainText.Contains('$script:MaximizeButton = New-UufCaptionButton ') | Should -BeTrue
        $global:UufMainText.Contains('$script:CloseButton = New-UufCaptionButton ') | Should -BeTrue
        $global:UufMainText.Contains('public static class UufUser32') | Should -BeTrue
        $global:UufMainText.Contains('$script:Form.Add_Resize({ if ($script:MaximizeButton)') | Should -BeTrue
        $global:UufMainText.Contains('$header.Add_MouseDown($uufCaptionMouseDown)') | Should -BeTrue
    }
    It 'безрамочное окно сохраняет нативные изменение размера, максимальный размер и меню панели задач' {
        $global:UufMainText.Contains('$script:Form.MaximizedBounds') | Should -BeTrue
        $global:UufMainText.Contains('-bor 0x00040000') | Should -BeTrue
        $global:UufMainText.Contains('New-UufResizeEdge ') | Should -BeTrue
        $global:UufMainText.Contains('$script:Form.Controls.SetChildIndex($edge, 0)') | Should -BeTrue
    }
    It 'нижняя полоса журнала прижата к низу и живёт вместе с окном' {
        $global:UufMainText.Contains('$diagnosticHeader.Anchor = ' + [char]39 + 'Bottom, Left' + [char]39) | Should -BeTrue
        $global:UufMainText.Contains('$script:CopyLogButton = Add-UiButton ' + [char]39 + 'Копировать журнал' + [char]39 + ' 14 844 184 $false 28 $right') | Should -BeTrue
        $global:UufMainText.Contains('$script:CopyLogButton.Anchor = ' + [char]39 + 'Bottom, Left' + [char]39) | Should -BeTrue
        $global:UufMainText.Contains('$script:ClearLogButton.Anchor = ' + [char]39 + 'Bottom, Left' + [char]39) | Should -BeTrue
        $global:UufMainText.Contains('$script:Grid.Size = New-Object System.Drawing.Size(1008,568)') | Should -BeTrue
        $global:UufMainText.Contains('function Set-UufRightLayout {') | Should -BeTrue
        $global:UufMainText.Contains('$script:DiagnosticsToggleButton = Add-UiButton') | Should -BeTrue
    }
    It 'правила VK и YouTube запрещают повторные точки и точки по краям' {
        Test-UsernameFormat -Username 'good_nick' -Platform 'VK' | Should -BeTrue
        Test-UsernameFormat -Username 'bad__name' -Platform 'VK' | Should -BeFalse
        Test-UsernameFormat -Username 'a..b' -Platform 'YouTube' | Should -BeFalse
        Test-UsernameFormat -Username '.start' -Platform 'YouTube' | Should -BeFalse
        Test-UsernameFormat -Username 'cool.handle' -Platform 'YouTube' | Should -BeTrue
    }
}

Describe 'Изменения версии 2.8.3' {
    It 'шапка стала компактнее, кнопки в две выверенные линии' {
        $global:UufMainText.Contains('$header.Size = New-Object System.Drawing.Size(1480, 92)') | Should -BeTrue
        $global:UufMainText.Contains('$title.Location = New-Object System.Drawing.Point(66, 14)') | Should -BeTrue
        $global:UufMainText.Contains('$subtitle.Location = New-Object System.Drawing.Point(66, 50)') | Should -BeTrue
        $global:UufMainText.Contains('$script:AccountButton.Location = New-Object System.Drawing.Point(1307, 34)') | Should -BeTrue
        $global:UufMainText.Contains('$script:ApiDocsButton.Location = New-Object System.Drawing.Point(1037, 34)') | Should -BeTrue
        $global:UufMainText.Contains('$script:HistoryButton.Location = New-Object System.Drawing.Point(1147, 34)') | Should -BeTrue
        $global:UufMainText.Contains('$script:AccountButton.Size = New-Object System.Drawing.Size(167, 38)') | Should -BeTrue
        $global:UufMainText.Contains('$captionButton.Size = New-Object System.Drawing.Size(46, 26)') | Should -BeTrue
        $global:UufMainText.Contains('$script:MinimizeButton = New-UufCaptionButton ''MinimizeButton'' 0xE921 1336') | Should -BeTrue
        $global:UufMainText.Contains('$script:CloseButton = New-UufCaptionButton ''CloseButton'' 0xE8BB 1428') | Should -BeTrue
    }
    It 'панели и нижняя полоса выровнены под уменьшенную шапку' {
        $global:UufMainText.Contains('$left.Location = New-Object System.Drawing.Point(14, 104)') | Should -BeTrue
        $global:UufMainText.Contains('$left.Size = New-Object System.Drawing.Size(390, [Math]::Max(320,[int]$script:Form.ClientSize.Height - 114))') | Should -BeTrue
        $global:UufMainText.Contains('$right.Location = New-Object System.Drawing.Point(418, 104)') | Should -BeTrue
        $global:UufMainText.Contains('$right.Size = New-Object System.Drawing.Size(1040, 926)') | Should -BeTrue
        $global:UufMainText.Contains('$diagnosticHeader.Location = New-Object System.Drawing.Point(14,720)') | Should -BeTrue
        $global:UufMainText.Contains('$script:CopyLogButton = Add-UiButton ''Копировать журнал'' 14 844 184 $false 28 $right') | Should -BeTrue
        $global:UufMainText.Contains('$script:ClearLogButton = Add-UiButton ''Очистить журнал'' 208 844 184 $false 28 $right') | Should -BeTrue
        $global:UufMainText.Contains('$script:SummaryLabel.Location = New-Object System.Drawing.Point(402,844)') | Should -BeTrue
        $global:UufMainText.Contains('$footer.Location = New-Object System.Drawing.Point(14,878)') | Should -BeTrue
    }
    It 'разнобой гарантирован на выдаче пула и перемешивание крипто-индексами' {
        $global:UufMainText.Contains('try { $j = Get-CryptoRandomIndex ($i + 1) }') | Should -BeTrue  # v2.8.4: форма с резервом по диапазону проверяется в блоке 2.8.4
    }
    It 'новые категории и алфавитный список' {
        $global:UufMainText.Contains('''Имя, Фамилия'' = @(''John'',''Birlich'',''Mark'',''Cukerberk'',''Mask'',''Ilon''') | Should -BeTrue
        $global:UufMainText.Contains('''Русские слова латиницей'' = @(''Privet'',''Phizik'',''Shizik'',''Cloun'',''Debil''') | Should -BeTrue
        $global:UufMainText.Contains('[void]$script:CategoryList.Items.AddRange([object[]]@($script:WordCategories | Sort-Object))') | Should -BeTrue
        $global:UufMainText.Contains('''Имя, Фамилия'',''Русские слова латиницей''') | Should -BeTrue
    }
    It 'пароль Mail.ru необязателен при сохранении' {
        $global:UufMainText.Contains('$passwordOptionalPlatform = ([string]$script:AccountPlatform -eq ''Mail.ru'')') | Should -BeTrue
    }
    It 'подсказки статуса в таблице' {
        $global:UufMainText.Contains('function Get-StatusTooltip') | Should -BeTrue
        $global:UufMainText.Contains('$script:Grid.ToolTip = $script:GridToolTip') | Should -BeTrue
        $global:UufMainText.Contains('$script:Grid.Rows[$row].Cells[''Status''].ToolTipText = $cellTip') | Should -BeTrue
        $global:UufMainText.Contains('$script:Grid.Rows[$row].Cells[''Reason''].ToolTipText = $cellTip') | Should -BeTrue
    }
    It 'стиль переименован и расширен' {
        $global:UufMainText.Contains('Add-UiLabel ''Стиль слова'' 14 372 150 22') | Should -BeTrue
        $global:UufMainText.Contains('''Хардкорный'' = @(''Reaper'',''Havoc'',''Mayhem'',''Brutal'',''Onslaught'',''Torment'',''Raze'')') | Should -BeTrue
        $global:UufMainText.Contains('''Скандинавский'' = @(''Rune'',''Skald'',''Fenrir'',''Torvald'',''Bjorn'',''Halvard'',''Stig'')') | Should -BeTrue
        $global:UufMainText.Contains('''Готический'' = @(''Raven'',''Crypt'',''Gargoyle'',''Nocturne'',''Obsidian'',''Veil'',''Shade'',''Mourne'')') | Should -BeTrue
    }
    It 'поле прокси в интерфейсе и в настройках' {
        $global:UufMainText.Contains('$script:ProxyBox = New-Object System.Windows.Forms.TextBox') | Should -BeTrue
        $global:UufMainText.Contains('Add-SettingValue $settings ''ProxyUrl'' { [string]$script:ProxyBox.Text.Trim() }') | Should -BeTrue
        $global:UufMainText.Contains('if ($script:ProxyBox) { $script:ProxyBox.Enabled = $true }') | Should -BeTrue
    }
    It 'очередь проверки идёт вразнобой при выключенном порядке' {
        $global:UufWorkerText.Contains('$feedOrder = @(Get-ShuffledArray -Items $feedOrder)') | Should -BeTrue
        $global:UufWorkerText.Contains('if (-not $script:OrderedCheck.Checked -and @($candidates).Count -gt 1) { $candidates = @(Get-ShuffledArray -Items @($candidates)) }') | Should -BeTrue
    }
    It 'Google: безтокенный эндпоинт доступности и терпимый парсинг' {
        $global:UufWorkerText.Contains('https://accounts.google.com/_/signup/webusernameavailability') | Should -BeTrue
        $global:UufWorkerText.Contains('f.req=[['' + ($googleCells -join '','') + '']]') | Should -BeTrue
        $global:UufWorkerText.Contains('\[\[\s*null\s*,\s*\[\s*([12])\s*(?:,|\])') | Should -BeTrue
    }
    It 'Outlook: IfExistsResult=0 подтверждает занявость, =1 больше не выдаётся за свободу' {
        $global:UufWorkerText.Contains('https://login.microsoftonline.com/common/GetCredentialType') | Should -BeTrue
        $global:UufWorkerText.Contains('$existsMatch = [regex]::Match($gctText, ''(?i)"IfExistsResult"\s*:\s*(-?[0-9]+)'')') | Should -BeTrue
        $global:UufWorkerText.Contains('IfExistsResult=0 — Microsoft сообщает, что пользователь с таким адресом существует') | Should -BeTrue
        $global:UufWorkerText.Contains('Outlook: аккаунта для входа нет (IfExistsResult=1)') | Should -BeTrue
    }
    It 'YouTube: cookie согласия и дополнительные маркеры канала' {
        $global:UufWorkerText.Contains('''Cookie''=''CONSENT=YES+cb; SOCS=CAI; GPS=1''') | Should -BeTrue
        $global:UufWorkerText.Contains('property="og:url"[^>]+content="https?://www\.youtube\.com/@') | Should -BeTrue
    }
    It 'Telegram: детерминированный ответ t.me (404 — свободен, профиль — занят)' {
        $global:UufWorkerText.Contains('$profileTitle = $content -match') | Should -BeTrue
        $global:UufWorkerText.Contains('if ($httpStatus -eq 200 -and $reservedPage)') | Should -BeTrue
        $global:UufWorkerText.Contains('if ($httpStatus -eq 200 -and $freePage)') | Should -BeTrue
    }
    It 'региональные блокировки подсказывают прокси, воркер умеет прокси' {
        $global:UufWorkerText.Contains('сайты t.me и YouTube могут быть недоступны из региона') | Should -BeTrue
        $global:UufWorkerText.Contains('$script:WorkerProxy') | Should -BeTrue
        $global:UufWorkerText.Contains('if ($script:WorkerProxy) { $requestArgs.Proxy = $script:WorkerProxy }') | Should -BeTrue
        $global:UufWorkerText.Contains('$script:ProxyBox.Enabled = $false') | Should -BeTrue
        $global:UufWorkerText.Contains('.AddArgument([string]$script:ProxyBox.Text.Trim())') | Should -BeTrue
    }
}

Describe 'Доработка версии 2.8.4' {
    It 'версия не ниже 2.8.4 в скрипте' {
        $global:UufMainText | Should -Match '\$script:AppVersion = ''2\.(?:[89]|10)\.\d'''
    }
    It 'журнал печатает режим очереди проверки' {
        $global:UufMainText.Contains('Порядок проверки: вразнобой') | Should -BeTrue
        $global:UufMainText.Contains('Порядок проверки: по порядку') | Should -BeTrue
    }
    It 'перемешивание не спотыкается о диапазон 256' {
        $global:UufMainText.Contains('if ($i -lt 256) { try { $j = Get-CryptoRandomIndex ($i + 1) } catch { $j = -1 } }') | Should -BeTrue
        $global:UufMainText.Contains('if ($j -lt 0) { $j = Get-Random -Minimum 0 -Maximum ($i + 1) }') | Should -BeTrue
    }
}

Describe 'Исправление версии 2.8.5' {
    It 'подсказки грида не используют несуществующее свойство ToolTip (краш запуска в 2.8.3/2.8.4)' {
        $global:UufMainText.Contains('ReselectionDelay') | Should -BeFalse
        $global:UufMainText.Contains('$script:GridToolTip.ReshowDelay = 250') | Should -BeTrue
        $global:UufMainText.Contains('# --- Подсказки статуса: оформление не должно уметь ронять запуск') | Should -BeTrue
    }
    It 'поле прокси честно обещает только HTTP-прокси' {
        $global:UufMainText.Contains('socks5://127.0.0.1:1080') | Should -BeFalse
        $global:UufMainText.Contains('Необязательный HTTP-прокси для всех проверок') | Should -BeTrue
    }
}

Describe 'Изменения версии 2.8.6' {
    It 'версия не ниже 2.8.6 в скрипте' {
        $global:UufMainText | Should -Match '\$script:AppVersion = ''2\.(?:[89]|10)\.\d'''
    }
    It 'статуса «Вероятно свободен» в проверках больше нет' {
        $global:UufWorkerText.Contains('Вероятно свободен') | Should -BeFalse
        $global:UufMainText.Contains(',''Вероятно свободен'',''Занят'',''Недопустимый''') | Should -BeFalse
    }
    It 'фильтр статусов без «Вероятно свободен»' {
        $global:UufMainText.Contains("@('Все статусы','Свободен','Занят','Недопустимый'") | Should -BeTrue
    }
    It 'шапка и панели подгоняются под реальный размер окна' {
        $global:UufMainText.Contains('$header.Width = [Math]::Max(880,[int]$script:Form.ClientSize.Width)') | Should -BeTrue
        $global:UufMainText.Contains('$uufClientFit = $script:Form.ClientSize') | Should -BeTrue
        $global:UufMainText.Contains('[Math]::Max(320,[int]$uufClientFit.Height - 114)') | Should -BeTrue
    }
    It 'кнопки экспорта переименованы под свободные ники' {
        $global:UufMainText.Contains("'↓  TXT свободные'") | Should -BeTrue
        $global:UufMainText.Contains("'⧉  Копировать свободные'") | Should -BeTrue
        $global:UufMainText.Contains('TXT доступные/возможные') | Should -BeFalse
    }
    It 'Outlook: только ответ формы регистрации даёт «Свободен»' {
        $global:UufWorkerText.Contains("`$credentialCode -eq 1) { `$status='Не подтверждено'") | Should -BeTrue
        $global:UufWorkerText.Contains("`$status -notin @('Занят','Свободен')") | Should -BeTrue
        $global:UufWorkerText.Contains('signup.live.com/CreateAccount?lic=1') | Should -BeTrue
    }
    It 'Google: signin-lookup идёт первым, валидаторы прогреваются сессией' {
        $idxLookup = $global:UufWorkerText.IndexOf('signin/sl/lookup?hl=en')
        $idxPlain = $global:UufWorkerText.IndexOf('signup/webusernameavailability')
        $idxLookup | Should -BeGreaterOrEqual 0
        $idxPlain | Should -BeGreaterThan $idxLookup
        $global:UufWorkerText.Contains("'application/x-www-form-urlencoded; charset=UTF-8' -WebSession `$googleSession") | Should -BeTrue
    }
    It 'Telegram: 404 — свободен, блокировка подсказывает прокси' {
        $global:UufWorkerText.Contains('вернул 404 — страница') | Should -BeTrue
        $global:UufWorkerText.Contains('$blockedPage') | Should -BeTrue
    }
    It 'инструкция аккаунта строится под выбранную платформу' {
        $global:UufMainText.Contains('function Get-AccountSafetyText') | Should -BeTrue
        $global:UufMainText.Contains('$script:SafetyInfoLabel.Text = Get-AccountSafetyText -Platform $platform') | Should -BeTrue
        $global:UufMainText.Contains('открой Roblox') | Should -BeFalse
    }
    It 'журнал предпочитает LOCALAPPDATA, а не папку программы' {
        $global:UufMainText.Contains("`$preferredDirectory = Join-Path `$env:LOCALAPPDATA 'UniversalUsernameFinder'") | Should -BeTrue
    }
    It 'скрипт установки на рабочий стол лежит в build и умеет удалять' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $installPath = [System.IO.Path]::Combine($repoRoot, 'build', 'Install-UUF.ps1')
        [System.IO.File]::Exists($installPath) | Should -BeTrue
        $installText = [System.IO.File]::ReadAllText($installPath, [System.Text.Encoding]::UTF8)
        $installText.Contains('Programs\UniversalUsernameFinder') | Should -BeTrue
        $installText.Contains('WScript.Shell') | Should -BeTrue
        $installText.Contains('[switch]$Uninstall') | Should -BeTrue
        $installBytes = [System.IO.File]::ReadAllBytes($installPath)
        $installBytes[0] | Should -Be 0xEF
        $installBytes[1] | Should -Be 0xBB
        $installBytes[2] | Should -Be 0xBF
    }
    It 'футер честно описывает смысл статусов' {
        $global:UufMainText.Contains('Проверка некоторых платформ возможно потребует VPN/Proxy, если вы проживаете в странах СНГ, где работают блокировки') | Should -BeTrue
    }
}

Describe 'Версия 2.8.7: подпись сборки и антивирусное доверие' {
    It 'собираемый exe получает метаданные издателя Hasberd' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $buildText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'build', 'Build-Exe.ps1'), [System.Text.Encoding]::UTF8)
        $buildText.Contains("company     = 'Hasberd'") | Should -BeTrue
        $buildText.Contains("title       = 'Universal Username Finder'") | Should -BeTrue
    }
    It 'скрипт подписи умеет секретный PFX и самоподпись CN=Hasberd без хранилища' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $signPath = [System.IO.Path]::Combine($repoRoot, 'build', 'Sign-Uuf.ps1')
        [System.IO.File]::Exists($signPath) | Should -BeTrue
        $signBytes = [System.IO.File]::ReadAllBytes($signPath)
        $signBytes[0] | Should -Be 0xEF
        $signBytes[1] | Should -Be 0xBB
        $signBytes[2] | Should -Be 0xBF
        $signText = [System.IO.File]::ReadAllText($signPath, [System.Text.Encoding]::UTF8)
        $signText.Contains('UUF_SIGN_PFX_BASE64') | Should -BeTrue
        $signText.Contains('CertificateRequest') | Should -BeTrue
        $signText.Contains('CreateSelfSigned') | Should -BeTrue
        $signText.Contains('X509ContentType') | Should -BeTrue
        $signText.Contains("'CN=Hasberd'") | Should -BeTrue
        $signText.Contains('/fd') | Should -BeTrue
        $signText.Contains('/tr') | Should -BeTrue
        $signText.Contains('Get-AuthenticodeSignature') | Should -BeTrue
        $signText.Contains('EphemeralKeySet') | Should -BeTrue
    }
    It 'CI подписывает exe и публикует sha256 вместе с публичным сертификатом' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $ciText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, '.github', 'workflows', 'ci.yml'), [System.Text.Encoding]::UTF8)
        $ciText.Contains('build\Sign-Uuf.ps1') | Should -BeTrue
        $ciText.Contains('secrets.UUF_SIGN_PFX_BASE64') | Should -BeTrue
        $ciText.Contains('dist/UUF.exe.sha256') | Should -BeTrue
        $ciText.Contains('Get-FileHash') | Should -BeTrue
    }
    It 'установщик сообщает о подписи и копирует сертификат издателя' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $installText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'build', 'Install-UUF.ps1'), [System.Text.Encoding]::UTF8)
        $installText.Contains('Get-AuthenticodeSignature') | Should -BeTrue
        $installText.Contains('UUF-signing.cer') | Should -BeTrue
    }
    It 'README объясняет ложные срабатывания ML-движков' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $readmeText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'README.md'), [System.Text.Encoding]::UTF8)
        $readmeText.Contains('Если антивирус подозревает') | Should -BeTrue
        $readmeText.Contains('UUF_SIGN_PFX_BASE64') | Should -BeTrue
    }
}

Describe 'Версия 2.8.8: статистика по размеру окна и доверие подписи' {
    It 'полоса счётчиков пересчитывается от фактической ширины панели' {
        $global:UufMainText.Contains('$script:StatLabels = $statLabels') | Should -BeTrue
        $global:UufMainText.Contains('$right.Add_SizeChanged({') | Should -BeTrue
        $global:UufMainText.Contains('$uufBlockW = [Math]::Max(84,[int](($uufPanelW - 64) / 6))') | Should -BeTrue
    }
    It 'прогресс-бар прижат правым якорем' {
        $global:UufMainText.Contains("`$script:ProgressBar.Anchor = 'Top, Left, Right'") | Should -BeTrue
    }
    It 'установщик умеет доверять сертификату и снимать доверие' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $installText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'build', 'Install-UUF.ps1'), [System.Text.Encoding]::UTF8)
        $installText.Contains('[switch]$TrustCertificate') | Should -BeTrue
        $installText.Contains('Import-Certificate -FilePath $candidatePath -CertStoreLocation ''Cert:\CurrentUser\TrustedPublisher''') | Should -BeTrue
        $installText.Contains("'Cert:\CurrentUser\Root'") | Should -BeTrue
    }
    It 'README объясняет SmartScreen и отчёт Dr.Web' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $readmeText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'README.md'), [System.Text.Encoding]::UTF8)
        $readmeText.Contains('-TrustCertificate') | Should -BeTrue
        $readmeText.Contains('doctor@drweb.com') | Should -BeTrue
        $readmeText.Contains('Подробнее → Выполнить в любом случае') | Should -BeTrue
    }
}

Describe 'Версия 2.8.9: SmartScreen-нюансы' {
    It 'установщик разблокирует папку распаковки и диагностирует подпись' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $installText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'build', 'Install-UUF.ps1'), [System.Text.Encoding]::UTF8)
        $installText.Contains('Unblock-File -LiteralPath $targetExe') | Should -BeTrue
        $installText.Contains('$trustAppliedNow') | Should -BeTrue
        $installText.Contains('Внимание: файл не подписан') | Should -BeTrue
        $installText.Contains('Подпись проверена: издатель Hasberd') | Should -BeTrue
    }
    It 'журнал приложения фиксирует статус подписи запускаемого файла' {
        $global:UufMainText.Contains("Write-StartupLog ('Подпись: '") | Should -BeTrue
        $global:UufMainText.Contains('(powershell(_ise)?|pwsh)') | Should -BeTrue
        $global:UufMainText.Contains('запуск из powershell/pwsh') | Should -BeTrue
    }
    It 'README содержит чек-лист из трёх способов против SmartScreen' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $readmeText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'README.md'), [System.Text.Encoding]::UTF8)
        $readmeText.Contains('Если SmartScreen по-прежнему показывает') | Should -BeTrue
        $readmeText.Contains('Подробнее → Выполнить в любом случае') | Should -BeTrue
        $readmeText.Contains('Установить сертификат') | Should -BeTrue
    }
    It 'версия поднята' {
        $global:UufMainText | Should -Match '\$script:AppVersion = ''2\.(?:9\.[0-9]|10\.[0-9])'''
    }
}

Describe 'Версия 2.9.0: ручной ввод, вкладки, зеркала Telegram, форма Outlook, буфер' {
    It 'поле ручных ников не перекрывается подписью, подсказка видна первой строкой' {
        $global:UufMainText.Contains('Ручные ники для проверки') | Should -BeTrue
        $global:UufMainText.Contains('$script:ManualNickBox = New-TextBox 14 505 350 66') | Should -BeTrue
    }
    It 'вкладки рисуются вручную: без белой полоски, кнопки угла в цвете таба' {
        $global:UufMainText.Contains('function Set-UufTabStyle {') | Should -BeTrue
        $global:UufMainText.Contains("`$Tabs.Appearance = 'FlatButtons'") | Should -BeTrue
        $global:UufMainText.Contains("`$Tabs.DrawMode = 'OwnerDrawFixed'") | Should -BeTrue
        $global:UufMainText.Contains('Set-UufTabStyle -Tabs $tabs -TabWidth 190') | Should -BeTrue
        $global:UufMainText.Contains('function Show-HelpPage {') | Should -BeTrue
    }
    It 'буфер обмена через безопасную функцию с повторами, прямых вызовов не осталось' {
        $global:UufMainText.Contains('function Copy-UufTextToClipboard {') | Should -BeTrue
        $global:UufMainText.Contains('[System.Windows.Forms.Clipboard]::SetText($Text); return $true') | Should -BeTrue
        $clipDirect = @([regex]::Matches($global:UufMainText, [regex]::Escape('[System.Windows.Forms.Clipboard]::SetText('))).Count
        $clipDirect | Should -Be 1
    }
    It 'почтовый суффикс ника отсекается до проверки формата' {
        $global:UufMainText.Contains('function Get-PlatformNickInput {') | Should -BeTrue
        $global:UufMainText.Contains('Get-PlatformNickInput -Platform ([string]$script:AccountPlatform) -Raw $script:AccountUsernameBox.Text') | Should -BeTrue
        $global:UufFullText.Contains('Get-PlatformNickInput -Platform $platform -Raw $nickRaw') | Should -BeTrue
    }
    It 'ручные ники не глушат генерацию молча: есть диагностика и счётчик' {
        $global:UufFullText.Contains('в таблицу берутся только ручные ники') | Should -BeTrue
        $global:UufFullText.Contains('$addedManual') | Should -BeTrue
        $global:UufFullText.Contains('ручных: $addedManual') | Should -BeTrue
    }
    It 'Telegram: обход t.me и зеркал, первый однозначный ответ выигрывает' {
        $global:UufWorkerText.Contains("`$tgBase in @('https://t.me/','https://telegram.dog/','https://telegram.me/')") | Should -BeTrue
        $global:UufWorkerText.Contains('$tgResolved') | Should -BeTrue
    }
    It 'Outlook: доступность подтверждает форма регистрации с обновлением canary' {
        $global:UufWorkerText.Contains('CheckAvailableSigninNames') | Should -BeTrue
        $global:UufWorkerText.Contains('$msAttempt') | Should -BeTrue
        $global:UufWorkerText.Contains('форма регистрации подтвердила доступность') | Should -BeTrue
    }
    It 'версия поднята до 2.9.0' {
        $global:UufMainText | Should -Match '\$script:AppVersion = ''2\.(?:9\.[0-9]|10\.[0-9])'''
    }
}

Describe 'Версия 2.9.1: дорисовка вкладок, возобновление проверки, устойчивость остановок' {
    It 'обработчик вкладок привязывает аргументы через param и защищён от падения' {
        $global:UufMainText.Contains('param($tabSender,$tabArgs)') | Should -BeTrue
        $global:UufMainText.Contains('if ($tabIndex -lt 0 -or $tabIndex -ge $tabSender.TabPages.Count) { return }') | Should -BeTrue
        $global:UufMainText | Should -Not -Match '\$args\[1\]\.TabIndex'
    }
    It 'кнопки заголовка не рисуют системных рамок' {
        $global:UufMainText.Contains('$captionButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(23,30,42)') | Should -BeTrue
        $global:UufMainText.Contains('$captionButton.UseVisualStyleBackColor = $false') | Should -BeTrue
    }
    It 'после остановки появляется кнопка «Возобновить проверку» и прячется во время прогона' {
        $global:UufMainText.Contains('Возобновить проверку') | Should -BeTrue
        $global:UufMainText.Contains('$script:StartButton.Visible = $true') | Should -BeTrue
        $global:UufMainText.Contains('$script:StartButton.Visible = $false') | Should -BeTrue
    }
    It 'Telegram: отмена проверяется между зеркалами, таймаут запроса урезан, HTTP 0 объяснён' {
        $global:UufWorkerText.Contains('$tgTimeoutSec = [Math]::Min($timeoutSec,12)') | Should -BeTrue
        $global:UufWorkerText.Contains('соединение не установлено (сетевая блокировка)') | Should -BeTrue
    }
    It 'Outlook: непонятный ответ формы разбирается детальнее (values, errorDefinitions, HTML-защита)' {
        $global:UufWorkerText.Contains('MemberNameUnavailable') | Should -BeTrue
        $global:UufWorkerText.Contains('"errorDefinitions"') | Should -BeTrue
        $global:UufWorkerText.Contains('отдала HTML вместо JSON') | Should -BeTrue
    }
    It 'Google: сессия догревается на месте, если стартовый прогрев не оставил cookies' {
        $global:UufWorkerText.Contains('$googleSession.Cookies.Count -lt 1') | Should -BeTrue
        $global:UufWorkerText.Contains('signin/v2/identifier?service=mail&hl=en') | Should -BeTrue
    }
    It 'установщик не закрывается молча: trap с паузой плюс bat-обёртка в артефакте' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $installerText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'build', 'Install-UUF.ps1'), [System.Text.Encoding]::UTF8)
        $installerText.Contains('trap {') | Should -BeTrue
        $installerText.Contains('Нажмите Enter, чтобы закрыть окно') | Should -BeTrue
        Test-Path ([System.IO.Path]::Combine($repoRoot, 'build', 'Install-UUF.bat')) | Should -BeTrue
        $ciText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, '.github', 'workflows', 'ci.yml'), [System.Text.Encoding]::UTF8)
        $ciText.Contains('build/Install-UUF.bat') | Should -BeTrue
    }
    It 'версия поднята до 2.9.1' {
        $global:UufMainText | Should -Match '\$script:AppVersion = ''2\.(?:9\.[0-9]|10\.[0-9])'''
    }
}

Describe 'Версия 2.9.2: установщик зависимостей и программа полного удаления' {
    It 'установщик проверяет .NET, PowerShell и TLS и регистрирует удаление в реестре' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $installText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'build', 'Install-UUF.ps1'), [System.Text.Encoding]::UTF8)
        $installText.Contains('function Test-UufDependencies') | Should -BeTrue
        $installText.Contains('394802') | Should -BeTrue
        $installText.Contains('SchUseStrongCrypto') | Should -BeTrue
        $installText.Contains('[switch]$SkipDependencyCheck') | Should -BeTrue
        $installText.Contains('[switch]$NoTrust') | Should -BeTrue
        $installText.Contains('CurrentVersion\Uninstall\UniversalUsernameFinder') | Should -BeTrue
        $installText.Contains('UninstallString') | Should -BeTrue
        $installText.Contains('Set-ItemProperty -LiteralPath $uninstallRegistryKey -Name Publisher -Value ''Hasberd''') | Should -BeTrue
    }
    It 'доверие сертификату включено по умолчанию, старый ключ совместим, удаление делегируется' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $installText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'build', 'Install-UUF.ps1'), [System.Text.Encoding]::UTF8)
        $installText.Contains('if ($TrustCertificate -and -not $NoTrust) {') | Should -BeTrue
        $installText.Contains('[switch]$TrustCertificate') | Should -BeTrue
        $installText.Contains('& $uninstallerSource') | Should -BeTrue
        $installText.Contains('Copy-Item -LiteralPath $uninstallerExeSource -Destination $targetUninstaller -Force') | Should -BeTrue
    }
    It 'Uninstall-UUF.ps1 стирает файлы, ярлыки, реестр, доверие сертификата и данные' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $uninstallerPath = [System.IO.Path]::Combine($repoRoot, 'build', 'Uninstall-UUF.ps1')
        Test-Path -LiteralPath $uninstallerPath | Should -BeTrue
        $uninstallText = [System.IO.File]::ReadAllText($uninstallerPath, [System.Text.Encoding]::UTF8)
        $uninstallText.Contains('function Remove-UufCertificateTrust') | Should -BeTrue
        $uninstallText.Contains("'CN=Hasberd*'") | Should -BeTrue
        $uninstallText.Contains('[switch]$KeepData') | Should -BeTrue
        $uninstallText.Contains('rd /s /q') | Should -BeTrue
        $uninstallText.Contains('while (Get-Process -Id $p -ErrorAction SilentlyContinue)') | Should -BeTrue
        $uninstallText.Contains('Remove-UufDirectory -Path $dataDirectory -Label ''Данные''') | Should -BeTrue
    }
    It 'bat-обёртки есть и у установки, и у удаления; артефакт их содержит' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        Test-Path ([System.IO.Path]::Combine($repoRoot, 'build', 'Uninstall-UUF.bat')) | Should -BeTrue
        $uninstallBatText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'build', 'Uninstall-UUF.bat'))
        $uninstallBatText.Contains('Uninstall-UUF.ps1') | Should -BeTrue
        $ciText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, '.github', 'workflows', 'ci.yml'), [System.Text.Encoding]::UTF8)
        $ciText.Contains('build/Uninstall-UUF.ps1') | Should -BeTrue
        $ciText.Contains('build/Uninstall-UUF.bat') | Should -BeTrue
    }
    It 'README описывает автодоверие, проверку зависимостей и полное удаление' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $readmeText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'README.md'), [System.Text.Encoding]::UTF8)
        $readmeText.Contains('Uninstall-UUF.bat') | Should -BeTrue
        $readmeText.Contains('Приложения и возможности') | Should -BeTrue
        $readmeText.Contains('-TrustCertificate') | Should -BeTrue
        $readmeText.Contains('394802') | Should -BeFalse
    }
    It 'версия не ниже 2.9.2' {
        $global:UufMainText | Should -Match '\$script:AppVersion = ''2\.(?:9\.[2-9]|10\.[0-9])'''
    }
}

Describe 'Версия 2.9.3: полное удаление — самостоятельный AppUninstaller.exe' {
    It 'деинсталлятор собирается ps2exe из исходника удаления' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $builderPath = [System.IO.Path]::Combine($repoRoot, 'build', 'Build-Uninstaller.ps1')
        Test-Path -LiteralPath $builderPath | Should -BeTrue
        $builderText = [System.IO.File]::ReadAllText($builderPath, [System.Text.Encoding]::UTF8)
        $builderText.Contains('AppUninstaller.exe') | Should -BeTrue
        $builderText.Contains('Uninstall-UUF.ps1') | Should -BeTrue
        $builderText.Contains('Invoke-ps2exe') | Should -BeTrue
    }
    It 'AppUninstaller.exe подписывается общим сертификатом и попадает в артефакт с хэшем' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $ciText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, '.github', 'workflows', 'ci.yml'), [System.Text.Encoding]::UTF8)
        $ciText.Contains('Compile AppUninstaller.exe') | Should -BeTrue
        $ciText.Contains('dist/AppUninstaller.exe') | Should -BeTrue
        $ciText.Contains('dist/AppUninstaller.exe.sha256') | Should -BeTrue
        $ciText.Contains('-ExtraExePaths') | Should -BeTrue
        $signText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'build', 'Sign-Uuf.ps1'), [System.Text.Encoding]::UTF8)
        $signText.Contains('[string[]]$ExtraExePaths = @()') | Should -BeTrue
    }
    It 'установщик кладёт AppUninstaller.exe и регистрирует его кнопкой удаления' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $installText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'build', 'Install-UUF.ps1'), [System.Text.Encoding]::UTF8)
        $installText.Contains('Join-Path $targetDirectory ''AppUninstaller.exe''') | Should -BeTrue
        $installText.Contains('Get-UninstallerExeSource') | Should -BeTrue
        $installText.Contains('& $uninstallerExe @uufUninstallArgs') | Should -BeTrue
        $installText.Contains('$uninstallCommand = ''"'' + $targetUninstaller + ''"''') | Should -BeTrue
    }
    It 'README ведёт полное удаление через AppUninstaller.exe' {
        $repoRoot = Split-Path -Parent $global:UufScriptPath
        $readmeText = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($repoRoot, 'README.md'), [System.Text.Encoding]::UTF8)
        $readmeText.Contains('AppUninstaller.exe') | Should -BeTrue
        $readmeText.Contains('Build-Uninstaller.ps1') | Should -BeTrue
    }
    It 'версия поднята до 2.10.0' {
        $global:UufMainText | Should -Match '\$script:AppVersion = ''2\.10\.[0-9]'''
    }
}

Describe 'Версия 2.10.0: поправки 1-16' {
    It 'YouTube: правила YTKits — латиница, цифры, точка, подчёркивание, дефис; начало и конец буква или цифра' {
        Test-UsernameFormat -Username 'cool.handle_1' -Platform 'YouTube' | Should -BeTrue
        Test-UsernameFormat -Username 'ab' -Platform 'YouTube' | Should -BeFalse
        Test-UsernameFormat -Username '.start' -Platform 'YouTube' | Should -BeFalse
        Test-UsernameFormat -Username 'end-' -Platform 'YouTube' | Should -BeFalse
        Test-UsernameFormat -Username 'a..b' -Platform 'YouTube' | Should -BeFalse
        Test-UsernameFormat -Username ('a' * 31) -Platform 'YouTube' | Should -BeFalse
    }
    It 'пункт 1: пустое поле ручных ников читается через Get-TextBoxValue, служебный текст не попадает' {
        $global:UufFullText.Contains('$manualNickText = Get-TextBoxValue $script:ManualNickBox') | Should -BeTrue
    }
    It 'пункт 6: VPN-подсказка только для YouTube, Telegram, Outlook, Google и Discord' {
        $global:UufFullText.Contains("`$script:VpnNoticePlatforms = @('YouTube','Telegram','Outlook','Google','Discord')") | Should -BeTrue
        $global:UufFullText.Contains('function Update-VpnNotice {') | Should -BeTrue
        $global:UufFullText.Contains('$footer.Text = ' + [char]39 + [char]39) | Should -BeTrue
    }
    It 'пункт 8: возобновление проверки по ожидающим никам и счётчик осталось' {
        $global:UufFullText.Contains('function Get-PendingCandidateCount {') | Should -BeTrue
        $global:UufFullText.Contains('[bool]$ResumePending = $false') | Should -BeTrue
        $global:UufFullText.Contains('-RetryErrorsOnly $false -ResumePending $true') | Should -BeTrue
        $global:UufFullText.Contains('осталось: $(Get-PendingCandidateCount)') | Should -BeTrue
    }
    It 'пункт 9: в хранилище ник сохраняется с доменом через Get-DisplayNick' {
        $global:UufFullText.Contains('$storedNick = Get-DisplayNick -Platform ([string]$script:AccountPlatform) -Name $nick') | Should -BeTrue
        $global:UufFullText.Contains('Username=$storedNick') | Should -BeTrue
    }
    It 'пункты 10-12: кнопки и разделы помощи названы по ТЗ' {
        $global:UufFullText.Contains("'Регистрация и пароль'") | Should -BeTrue
        $global:UufFullText.Contains("'Сохранённые аккаунты'") | Should -BeTrue
        $global:UufFullText.Contains("@{ Title = 'Дисклеймер'") | Should -BeTrue
        $global:UufFullText.Contains("@{ Title = 'Правила ввода'") | Should -BeTrue
    }
    It 'пункт 13: история свободных — множественный выбор, Выделить все и Снять все' {
        $global:UufFullText.Contains("`$script:HistoryListBox.SelectionMode = 'MultiExtended'") | Should -BeTrue
        $global:UufFullText.Contains("'Выделить все'") | Should -BeTrue
        $global:UufFullText.Contains("'Снять все'") | Should -BeTrue
        $global:UufFullText.Contains('$selectedItems = @($script:HistoryListBox.SelectedItems)') | Should -BeTrue
    }
    It 'пункт 14: поля имени и фамилии и случайный выбор только для Google' {
        $global:UufFullText.Contains('function Set-RandomGoogleNameFields {') | Should -BeTrue
        $global:UufFullText.Contains("'Случайное имя и фамилия'") | Should -BeTrue
        $global:UufFullText.Contains('$isGoogleAccount = ($platform -eq ' + [char]39 + 'Google' + [char]39 + ')') | Should -BeTrue
    }
    It 'пункт 15: кнопка «Проверка соединения», таблица HTTP-кодов и формат строки результата' {
        $global:UufFullText.Contains("'⇄  Проверка соединения' 14 1237 350") | Should -BeTrue
        $global:UufFullText.Contains('function Open-ConnectionTestWindow {') | Should -BeTrue
        $global:UufFullText.Contains('$script:HttpStatusNotes = @{') | Should -BeTrue
        $global:UufFullText.Contains('https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status') | Should -BeTrue
        $global:UufFullText.Contains('"{0}. {1}.api - {2}, ping: {3}, Error: {4}"') | Should -BeTrue
    }
    It 'пункт 16: журнал разворачивается вверх и возвращается в стандартное положение' {
        $global:UufFullText.Contains("'▲  Развернуть журнал'") | Should -BeTrue
        $global:UufFullText.Contains("'▼  Вернуть стандартно'") | Should -BeTrue
        $global:UufFullText.Contains('$expandPx = [Math]::Max(0, [Math]::Min(300, $standardGridHeight - 180))') | Should -BeTrue
    }
    It 'пункт 7: предупреждения о конфликтах настроек перед генерацией' {
        $global:UufFullText.Contains('«Только короткие (≤12)» не совместимо с минимальной длиной больше 12') | Should -BeTrue
        $global:UufFullText.Contains('Ни один источник генерации не выбран') | Should -BeTrue
    }
}

Describe 'Версия 2.10.1: Telegram, белый фон и вкладки помощи' {
    It 'Telegram: открытая страница без профиля даёт «Свободен», а не «Не подтверждено»' {
        $global:UufWorkerText.Contains('$tgNoProfileSeen = $true') | Should -BeTrue
        $global:UufWorkerText.Contains('if (-not $tgResolved -and $tgNoProfileSeen) { $status=''Свободен''') | Should -BeTrue
    }
    It 'помощь: подписи карточек с тёмным фоном, без белых полей' {
        $global:UufMainText.Contains('$headingLabel.BackColor = [System.Drawing.Color]::FromArgb(23,30,42)') | Should -BeTrue
        $global:UufMainText.Contains('$bodyLabel.BackColor = [System.Drawing.Color]::FromArgb(23,30,42)') | Should -BeTrue
        $global:UufMainText.Contains('$pageHost.BackColor = [System.Drawing.Color]::FromArgb(17,23,32)') | Should -BeTrue
    }
    It 'помощь: кнопки-разделы и заголовки шрифта Tahoma' {
        $global:UufMainText.Contains('$script:UiFontFamily,11,[System.Drawing.FontStyle]::Bold') | Should -BeTrue
        $global:UufMainText.Contains('$navButton.Text = [string]$helpPages[$i].Title') | Should -BeTrue
    }
}

Describe 'Версия 2.10.2: установщик не доверяет сертификату без явного ключа' {
    It 'bat не передаёт ключ доверия' {
        $batText = [System.IO.File]::ReadAllText((Join-Path (Join-Path $PSScriptRoot '..') 'build\Install-UUF.bat'))
        $batText.Contains('TrustSelfSigned') | Should -BeFalse
        $batText.Contains('TrustCertificate') | Should -BeFalse
    }
    It 'метка интернета снимается только с установленного UUF.exe' {
        $installText = [System.IO.File]::ReadAllText((Join-Path (Join-Path $PSScriptRoot '..') 'build\Install-UUF.ps1'), [System.Text.Encoding]::UTF8)
        $installText.Contains('try { Unblock-File -LiteralPath $targetExe } catch { }') | Should -BeTrue
        $installText.Contains('Unblock-File -LiteralPath $uufFile.FullName') | Should -BeFalse
    }
}

Describe 'Версия 2.10.5: окно помощи не зацикливается при перекладке' {
    It 'Set-HelpCardLayout защищён от повторного входа' {
        $global:UufMainText.Contains('if ($script:HelpLayoutBusy) { return }') | Should -BeTrue
        $global:UufMainText.Contains('$script:HelpLayoutBusy = $false') | Should -BeTrue
    }
    It 'размеры меняются только при реальном изменении' {
        $global:UufMainText.Contains('if ($CardHost.AutoScrollMinSize -ne $minSize) { $CardHost.AutoScrollMinSize = $minSize }') | Should -BeTrue
    }
}

Describe 'Версия 2.10.6: окно помощи без вкладок и без пересчёта по Resize' {
    It 'разделы — кнопки, страница строится при выборе' {
        $global:UufMainText.Contains('function Show-HelpPage {') | Should -BeTrue
        $global:UufMainText.Contains('$navButton.FlatStyle = ''Flat''') | Should -BeTrue
        $global:UufMainText.Contains('Show-HelpPage -PageHost $pageHost -Pages $helpPages -Index ([int]$clickSender.Tag)') | Should -BeTrue
    }
    It 'старые вкладки помощи и пересчёт размеров удалены' {
        $global:UufMainText.Contains('Set-HelpTabSize') | Should -BeFalse
        $global:UufMainText.Contains('$helpTabs') | Should -BeFalse
        $global:UufMainText.Contains('SetWindowTheme') | Should -BeFalse
        $global:UufMainText.Contains('Add_Resize({ param($resizeSender') | Should -BeFalse
    }
    It 'окно фиксированного размера' {
        $global:UufMainText.Contains('$helpForm.FormBorderStyle = ''FixedSingle''') | Should -BeTrue
    }
}

Describe 'Версия 2.10.7: закрытие окна проверки соединения без ошибки таймера' {
    It 'Tick проверяет, что окно закрыто, и останавливает таймер' {
        $global:UufMainText.Contains('if ($null -eq $script:ConnGrid -or $null -eq $script:ConnQueue) { $script:ConnTimer.Stop(); return }') | Should -BeTrue
    }
    It 'ошибка таймера не всплывает в окно, а пишется в журнал' {
        $global:UufMainText.Contains('Write-AppLog (''Ошибка проверки соединения: '' + [string]$_.Exception.Message)') | Should -BeTrue
    }
}

Describe 'Версия 2.10.8: закрытие окна проверки соединения без @() над обобщёнными списками' {
    It 'Stop-ConnectionTest обходит списки по индексу' {
        $global:UufMainText.Contains('for ($psIndex = 0; $psIndex -lt $oldPowerShells.Count; $psIndex++) {') | Should -BeTrue
        $global:UufMainText.Contains('foreach ($connPs in @($script:ConnPowerShells))') | Should -BeFalse
        $global:UufMainText.Contains('foreach ($connRs in @($script:ConnRunspaces))') | Should -BeFalse
    }
    It 'обработчик закрытия окна защищён try' {
        $global:UufMainText.Contains('try { Stop-ConnectionTest } catch { }') | Should -BeTrue
    }
}

Describe 'Версия 2.10.9: стиль окна регистрации и выравнивание проверки соединения' {
    It 'вкладки регистрации в стиле кнопок помощи' {
        $global:UufMainText.Contains('$tabs.SizeMode = ''Fixed''') | Should -BeTrue
        $global:UufMainText.Contains('$tabs.ItemSize = New-Object System.Drawing.Size(366, 40)') | Should -BeTrue
    }
    It 'кнопка «Копировать отчёт» убрана из проверки соединения' {
        $global:UufMainText.Contains('Копировать отчёт') | Should -BeFalse
        $global:UufMainText.Contains('connCopyButton') | Should -BeFalse
        $global:UufMainText.Contains('connCopyButton.Add_Click') | Should -BeFalse
    }
    It 'окно проверки соединения выровнено по сетке 868 px' {
        $global:UufMainText.Contains('$connForm.ClientSize = New-Object System.Drawing.Size(900,660)') | Should -BeTrue
        $global:UufMainText.Contains('$script:ConnGrid.Size = New-Object System.Drawing.Size(868,280)') | Should -BeTrue
    }
}

