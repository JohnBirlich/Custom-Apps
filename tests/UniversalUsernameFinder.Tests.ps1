#requires -Version 5.1

<#
    Тесты чистой логики Universal Username Finder.

    Скрипт приложения — монолитный WinForms-файл, который при импорте создаёт окна,
    поэтому dot-source здесь неприменим (тем более на Linux в CI). Вместо этого нужные
    функции извлекаются из текста скрипта и определяются в тестовой сессии: это даёт
    регрессионную защиту без рефакторинга приложения.

    Отдельно проверяются структурные инварианты, которые раньше ломались незаметно:
    соответствие списка платформ и реальных веток проверки в воркере, наличие BOM,
    отсутствие дублирующихся определений функций.

    Намеренно не используются регулярные выражения там, где в искомом тексте есть
    символы $ и кавычки: строковый поиск предсказуемее и не зависит от экранирования.
#>

BeforeAll {
    $scriptPath = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..') 'UniversalUsernameFinder.ps1'))
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw ('Не найден скрипт приложения: ' + $scriptPath) }

    $fullText = [System.IO.File]::ReadAllText($scriptPath)

    # Основная часть и here-string воркера разбираются отдельно: в воркере свои локальные
    # функции, и они не должны подмешиваться в тесты.
    $workerMarker = '$workerScript = @'
    $workerStart = $fullText.IndexOf($workerMarker)
    if ($workerStart -lt 0) { throw 'Не найден here-string воркера' }
    $global:UufMainText = $fullText.Substring(0, $workerStart)
    $global:UufWorkerText = $fullText.Substring($workerStart)
    # Полный текст нужен для структурных проверок кода, который расположен ПОСЛЕ
    # here-string воркера (экспорт CSV, обработчик кнопки генерации): в UufMainText
    # его нет, и поиск по нему давал ложный отказ.
    $global:UufFullText = $fullText
    $global:UufScriptPath = $scriptPath

    # Извлечение определения функции по имени с учётом вложенности фигурных скобок.
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
        'New-InventedWord',
        'Convert-ToLeetWord',
        'New-AdvancedCandidatePool'
    )

    foreach ($functionName in $functionNames) {
        $definition = & $global:UufExtractFunction $global:UufMainText $functionName
        # Обращения к области видимости скрипта приложения заменяются на global,
        # чтобы извлечённые функции работали независимо от области определения.
        $definition = $definition -replace '\$script:', '$$global:'
        Invoke-Expression $definition
    }

    # Список поддерживаемых платформ читается из самого скрипта, а не дублируется в тесте.
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

    # Таблица правил длины платформ извлекается из скрипта, а не дублируется в тесте:
    # иначе правило в интерфейсе могло бы разойтись с правилом валидации формата.
    $rulesNeedle = '$script:PlatformLengthRules = @{'
    $rulesStart = $global:UufMainText.IndexOf($rulesNeedle)
    if ($rulesStart -lt 0) { throw 'Не найдена таблица правил длины платформ' }
    # Конец таблицы ищем подсчётом вложенности фигурных скобок, а не по «}\n» в начале
    # строки: вырезанный фрагмент обязан включать закрывающую скобку, иначе
    # Invoke-Expression получит незакрытый хештейб и упадёт с ошибкой разбора.
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

    # Ветки switch в воркере: строки вида "                'Имя' {" (16 пробелов).
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

    # Небольшие фиксированные словари: проверяется логика генератора и определения
    # структуры ника, а не наполнение категорий (реальные словари в скрипте содержат
    # несколько сотен слов). Индекс словарей обнуляется, чтобы он построился заново
    # из этих фикстур.
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
    # Наборы слогов для выдуманных слов и список редких коротких слов: генератор
    # обращается к ним напрямую, поэтому без фикстур он не смог бы работать.
    $global:InventedOnsets = @('Kr', 'Dav', 'Vel', 'Zan', 'Tor')
    $global:InventedNuclei = @('a', 'e', 'i', 'o')
    $global:InventedCodas = @('n', 'l', 'r', 's', 'k', 'nn')
    $global:RareShortWords = @('Nyx', 'Lux', 'Vex', 'Zed', 'Ryn', 'Kai')
    $global:SeedIndex = $null

    # RNGCryptoServiceProvider в .NET Core устарел; тестам достаточно любого
    # RandomNumberGenerator с тем же методом GetBytes.
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
        # Именно эта комбинация давала ProtocolViolationException в Windows PowerShell 5.1.
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
        # Ограничение частоты обрабатывается откатом темпа, а не обрывом прогона:
        # остановка только после трёх HTTP 429 подряд.
        $global:UufWorkerText.Contains('consecutiveRateLimits -ge 3') | Should -BeTrue
        # Прежняя фиксированная пауза не должна вернуться.
        $global:UufWorkerText.Contains('$elapsed -lt $DelayMs') | Should -BeFalse
        $global:UufWorkerText.Contains('[Math]::Max(1200,[int]$DelayMs)') | Should -BeFalse
    }

    It 'пол паузы зависит от платформы' {
        $global:UufWorkerText.Contains('''GitHub'' { $platformFloorMs = 1000 }') | Should -BeTrue
        $global:UufWorkerText.Contains('''Roblox'' { $platformFloorMs = 600 }') | Should -BeTrue
    }

    It 'лимит количества ников за генерацию поднят до 2000' {
        $global:UufMainText.Contains('$script:CountBox = New-NumberBox 14 694 90 5 2000 40') | Should -BeTrue
    }

    It 'колонка «СТРУКТУРА» убрана из таблицы, но свойство Structure сохранено' {
        # Колонка дублировала смысл категории и дробила строку таблицы, поэтому её нет.
        $global:UufMainText.Contains("Columns.Add('Structure'") | Should -BeFalse
        $global:UufMainText.Contains("'СТРУКТУРА'") | Should -BeFalse
        $global:UufMainText.Contains('Sort-Object Structure') | Should -BeFalse
        # Свойство Structure по-прежнему используется логикой и видно в экспорте CSV.
        # Экспорт CSV расположен после here-string воркера, поэтому ищем в полном тексте.
        $global:UufFullText.Contains('Name=''Структура'';Expression={$_.Structure}') | Should -BeTrue
        $global:UufMainText.Contains('function Get-NickStructure') | Should -BeTrue
    }

    It 'исключения передаются в генератор до его запуска' {
        # Обработчик кнопки генерации тоже расположен после here-string воркера.
        $global:UufFullText.Contains('-ExcludeKeys $excludeKeys') | Should -BeTrue
        $global:UufFullText.Contains('Создано {0} из {1}') | Should -BeTrue
    }

    It 'Roblox повторяет POST с токеном X-CSRF-Token' {
        $global:UufWorkerText.Contains('X-CSRF-Token') | Should -BeTrue
    }

    It 'история ников читается с явным UTF-8, а не через Get-Content' {
        # Регрессия: в Windows PowerShell 5.1 Get-Content без -Encoding читает файл
        # без BOM как ANSI. История, созданная до версии 2.5.2, записывалась без BOM,
        # поэтому кириллические статусы превращались в нечитаемые символы.
        $global:UufMainText.Contains('[System.IO.File]::ReadAllText($script:HistoryPath)') | Should -BeTrue
        $global:UufMainText.Contains('Get-Content -LiteralPath $script:HistoryPath -Raw') | Should -BeFalse
    }

    It 'автоширина столбцов отключается на время массовой вставки строк' {
        # При AutoSizeMode=Fill ширина пересчитывается на каждой добавленной строке,
        # и SuspendLayout этого не блокирует.
        $global:UufMainText.Contains('$script:Grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None') | Should -BeTrue
        $global:UufMainText.Contains('$script:Grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill') | Should -BeTrue
        $global:UufMainText.Contains('if ($restoreAutoSize) {') | Should -BeTrue
    }

    It 'палитра статусов вынесена из цикла перерисовки' {
        $global:UufMainText.Contains('$script:StatusColors = @{') | Should -BeTrue
        $global:UufMainText.Contains('$color = $script:StatusColors[[string]$item.Status]') | Should -BeTrue
    }

    It 'подсказка поля ввода не считается значением' {
        # Регрессия: строка «Pixel, Void, Storm» лежала в .Text, и при дописывании
        # своих слов Pixel и Void молча становились базовыми словами генератора.
        $global:UufMainText.Contains('function Get-TextBoxValue') | Should -BeTrue
        $global:UufMainText.Contains('$box.Add_GotFocus({') | Should -BeTrue
        # Обработчик кнопки генерации расположен после here-string воркера.
        $global:UufFullText.Contains('Get-TextBoxValue $script:CustomBox') | Should -BeTrue
        # Сам литерал остался только как текст подсказки; сравнивать с ним значение
        # поля больше нигде не должны.
        $global:UufFullText.Contains('-eq ''Pixel, Void, Storm''') | Should -BeFalse
    }

    It 'свободные ники пересчитываются только при изменении списка' {
        # Update-ResultGrid вызывается таймером примерно каждые 250 мс во время прогона,
        # и полный пересчёт свободных ников каждый раз был лишней работой.
        $global:UufMainText.Contains('function Touch-Candidates') | Should -BeTrue
        $global:UufMainText.Contains('$script:CandidateRevision -eq $script:AvailableNamesRevision') | Should -BeTrue
        # Точки повышения ревизии разбросаны по всему файлу: часть из них расположена
        # после here-string воркера, поэтому считаем по полному тексту.
        $touchCount = ([regex]::Matches($global:UufFullText, [regex]::Escape('Touch-Candidates'))).Count
        # Одно определение и не меньше пяти вызовов в точках изменения списка и статусов.
        $touchCount | Should -BeGreaterOrEqual 6
    }

    It 'хранилище аккаунтов перенесено из папки RobloxNickFinder с миграцией' {
        $global:UufMainText.Contains('$script:VaultDirectory = Join-Path $env:LOCALAPPDATA ''UniversalUsernameFinder''') | Should -BeTrue
        $global:UufMainText.Contains('$script:LegacyVaultPath = Join-Path $script:LegacyVaultDirectory ''accounts.dat''') | Should -BeTrue
        $global:UufMainText.Contains('function Migrate-LegacyVault') | Should -BeTrue
        # Миграция обязана сохранять старый файл, а не удалять его.
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
        Test-SupportedPlatform -Platform 'Steam' | Should -BeFalse
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
        $allowed = 'ABCDEFGHJKLMNPQRSTUVWXYZ' + 'abcdefghjkmnpqrstuvwxyz' + '23456789'
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
        # Регрессия: Encoding.GetBytes() не добавляет BOM, его возвращает только GetPreamble().
        # Без BOM Windows PowerShell 5.1 читает файл как ANSI, и кириллица ломается.
        $file = Join-Path $script:AtomicDirectory 'bom.json'
        Write-AtomicJsonFile -Path $file -Json (@{ Style = 'Английские' } | ConvertTo-Json -Depth 3)
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
        ([System.IO.File]::ReadAllText($file) | ConvertFrom-Json).Style | Should -Be 'Английские'
    }

    It 'перезаписывает существующий файл' {
        # Регрессия: резервный путь использовал File.Move поверх существующего файла,
        # что в .NET Framework даёт IOException «Cannot create a file when that file
        # already exists». Перезапись должна идти через File.Copy(..., true).
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
        # Старые ключи не должны «протекать» из предыдущей версии файла.
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
        # ConvertTo-Json разворачивает массив из одного элемента в скаляр —
        # Import-AppSettings не должен из-за этого ломаться.
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
        # Именно этот случай пользователь видел как «цельное слово»: BoomSquare —
        # это Boom + Square, соединённые без разделителя.
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
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 5 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $false -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 5
        @($pool | Where-Object { [string]$_.Structure -ne 'Одно слово' }) | Should -HaveCount 0
    }

    It 'при обеих галочках создаются и однословные, и двухсловные ники' {
        # Регрессия 2.5.3: этапы генерации шли строго последовательно, и одиночные
        # слова заполняли весь запрос (по умолчанию отмечено шесть категорий — около
        # 189 баз против запрошенных 40), поэтому пары не создавались вовсе.
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 20
        $single = @($pool | Where-Object { [string]$_.Structure -eq 'Одно слово' })
        $pair = @($pool | Where-Object { [string]$_.Structure -eq 'Два слова' })
        # В тестовом наборе восемь базовых слов, поэтому одиночными заполняется
        # не больше восьми; остальное обязано прийти парами.
        $single.Count | Should -BeGreaterThan 0
        $pair.Count | Should -BeGreaterOrEqual 8
        $global:GenerationStats['Single'] | Should -Be $single.Count
        $global:GenerationStats['Pair'] | Should -Be $pair.Count
    }

    It 'галочка «Использовать цифры» даёт числовые варианты даже при полном пространстве имён' {
        # Регрессия 2.5.3: цифры добирались только при нехватке количества, поэтому
        # при большом пространстве имён галочка не давала ничего.
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $true -UseUnderscore $false -OneWord $true -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 20
        $numeric = @($pool | Where-Object { ([string]$_.Name) -match '[0-9]' })
        # Квота цифр — 30 % от запрошенного количества, то есть 6 из 20.
        $numeric.Count | Should -BeGreaterOrEqual 5
        $global:GenerationStats['Number'] | Should -BeGreaterOrEqual 5
    }

    It 'без галочки «Использовать цифры» числовых вариантов нет' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        @($pool | Where-Object { ([string]$_.Name) -match '[0-9]' }) | Should -HaveCount 0
        $global:GenerationStats['Number'] | Should -Be 0
    }

    It 'двухсловная генерация помечает склейки как «Два слова» и относит к категории «Двусловные»' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 30 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 30
        @($pool | Where-Object { [string]$_.Structure -ne 'Два слова' }) | Should -HaveCount 0
        # Регрессия: раньше склейка наследовала категорию базового слова и попадала
        # в «Цельные слова», выглядя одним словом.
        @($pool | Where-Object { [string]$_.Category -ne 'Двусловные' }) | Should -HaveCount 0
    }

    It 'структура, заданная генератором, совпадает с определением по имени' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $pool.Count | Should -BeGreaterThan 0
        foreach ($candidate in $pool) {
            Get-NickStructure -Name ([string]$candidate.Name) | Should -Be ([string]$candidate.Structure)
        }
    }

    It 'уже использованные ники отсеиваются внутри генератора, и количество добирается' {
        $excludeKeys = @{}
        $first = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $first | Should -HaveCount 10
        foreach ($candidate in $first) {
            $excludeKeys[(Get-HistoryKey -Name ([string]$candidate.Name) -Platform 'Roblox')] = $true
        }
        # Регрессия: раньше исключения применялись после генерации без добора,
        # поэтому вместо 40 ников добавлялось 37.
        $second = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @() -ExcludeKeys $excludeKeys)
        $second | Should -HaveCount 10
        foreach ($candidate in $second) {
            $excludeKeys.ContainsKey((Get-HistoryKey -Name ([string]$candidate.Name) -Platform 'Roblox')) | Should -BeFalse
        }
    }

    It 'при исчерпании пространства возвращается меньше, а статистика объясняет причину' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 5 -MaxLength 20 -Count 50 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $false -OnlyShort $false -ExcludeTokens @())
        # Из восьми базовых слов минимальной длине 5 удовлетворяют шесть.
        $pool | Should -HaveCount 6
        $global:GenerationStats['ByLength'] | Should -Be 2
    }

    It 'стиль «Двусловный» даёт два слова, даже если галочка двухсловной генерации снята' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style 'Двусловный' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $false -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 10
        @($pool | Where-Object { [string]$_.Structure -ne 'Два слова' }) | Should -HaveCount 0
    }

    It 'свои слова через пробел не склеиваются в один ник' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @() -CustomWords 'boom square' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $false -OnlyShort $false -ExcludeTokens @())
        @($pool | Where-Object { [string]$_.Name -eq 'BoomSquare' }) | Should -HaveCount 0
        @($pool | Where-Object { [string]$_.Name -eq 'Boom' }) | Should -HaveCount 1
        @($pool | Where-Object { [string]$_.Name -eq 'Square' }) | Should -HaveCount 1
    }

    It 'с разделителем каждая склейка содержит подчёркивание' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $true -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 10
        @($pool | Where-Object { ([string]$_.Name).IndexOf('_') -lt 0 }) | Should -HaveCount 0
    }

    It 'слова-исключения отсеиваются и учитываются в статистике' {
        # Количество намеренно большое: пары выбираются случайно, поэтому при малом
        # запросе модификатор-исключение мог бы ни разу не попасться, и проверка
        # счётчика стала бы вероятностной.
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 40 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @('Void'))
        @($pool | Where-Object { ([string]$_.Name).IndexOf('Void') -ge 0 }) | Should -HaveCount 0
        $global:GenerationStats['ByExcludedToken'] | Should -BeGreaterThan 0
    }

    It 'большое количество ников создаётся без материализации всех пар' {
        $measure = Measure-Command {
            $global:BigPool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 60 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $true -OnlyShort $false -ExcludeTokens @())
        }
        $global:BigPool | Should -HaveCount 60
        # Пространство из восьми баз и пяти модификаторов даёт 80 комбинаций,
        # поэтому 60 набираются быстро; прежняя реализация перебирала все пары.
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
        # Правила Mail.ru, Outlook и Telegram требуют начинать имя с буквы.
        Convert-ToLeetWord -Word 'anna' -MaxSubstitutions 5 | Should -Be 'ann4'
    }

    It 'сохраняет заглавную букву в середине слова' {
        # Заглавной отмечается граница слов в склейке: заменив её цифрой, ник потерял
        # бы вид двух слов, и структура по имени разошлась бы с заданной генератором.
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
        (Get-PlatformLengthRule -Platform 'TikTok').Max | Should -Be 24
        (Get-PlatformLengthRule -Platform 'GitHub').Min | Should -Be 1
    }

    It 'для неизвестной платформы возвращает нейтральные границы' {
        $rule = Get-PlatformLengthRule -Platform 'Несуществующая'
        $rule.Min | Should -Be 3
        $rule.Max | Should -Be 32
    }

    It 'границы из правила совпадают с валидатором формата для всех платформ' {
        # Регрессия: правило в интерфейсе и правило валидации жили отдельно и могли
        # разойтись. При расхождении сгенерированные ники отбраковывались бы уже после
        # генерации как недопустимые, и количество в таблице не совпадало бы с запросом.
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
        # Регрессия: при включённом «Исключать проверенные» словарь со временем
        # заканчивался, и генерация возвращала ноль вариантов.
        $excludeKeys = @{}
        foreach ($word in @('Nova', 'Echo', 'Pulse', 'Orbit', 'Frost', 'Shadow', 'Raven', 'Comet')) {
            $excludeKeys[(Get-HistoryKey -Name $word -Platform 'Roblox')] = $true
        }
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $false -InventedWords $true -OnlyShort $false -ExcludeTokens @() -ExcludeKeys $excludeKeys)
        $pool | Should -HaveCount 10
        $global:GenerationStats['Single'] | Should -Be 0
        $global:GenerationStats['Invented'] | Should -Be 10
    }

    It 'своё слово входит в каждый созданный ник' {
        # Регрессия: свои слова лишь добавлялись в общий пул из сотен слов, поэтому
        # слово Void встречалось в лучшем случае в одном нике из двадцати.
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords 'Void' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 12 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -InventedWords $true -InventedPairs $true -RareShort $false -LeetWords $false -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 12
        @($pool | Where-Object { ([string]$_.Name).IndexOf('Void', [StringComparison]::OrdinalIgnoreCase) -lt 0 }) | Should -HaveCount 0
    }

    It 'замена символами даёт ники с цифрами без галочки «Использовать цифры»' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 10 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $false -LeetWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 10
        @($pool | Where-Object { ([string]$_.Name) -notmatch '[0-9]' }) | Should -HaveCount 0
        $global:GenerationStats['Number'] | Should -Be 0
        $global:GenerationStats['Leet'] | Should -Be 10
    }

    It 'редкие короткие ники укладываются в 3-6 символов' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 8 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $false -RareShort $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 8
        @($pool | Where-Object { ([string]$_.Name).Length -lt 3 -or ([string]$_.Name).Length -gt 6 }) | Should -HaveCount 0
        $global:GenerationStats['Rare'] | Should -Be 8
    }

    It 'выдуманные словосочетания помечаются как два слова' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @() -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 8 -UseNumbers $false -UseUnderscore $false -OneWord $false -TwoWords $false -InventedPairs $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 8
        @($pool | Where-Object { [string]$_.Structure -ne 'Два слова' }) | Should -HaveCount 0
        @($pool | Where-Object { [string]$_.Category -ne 'Выдуманные словосочетания' }) | Should -HaveCount 0
    }

    It 'структура ников из новых источников совпадает с определением по имени' {
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords 'Void' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $true -UseUnderscore $false -OneWord $true -TwoWords $true -InventedWords $true -InventedPairs $true -RareShort $true -LeetWords $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 20
        foreach ($candidate in $pool) {
            Get-NickStructure -Name ([string]$candidate.Name) | Should -Be ([string]$candidate.Structure)
        }
    }

    It 'генерация по порядку сохраняет последовательность источников' {
        # Восемь слов тестовой категории заполняют однословную квоту, дальше идут пары.
        # Без перемешивания источники видны в выдаче подряд.
        $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -Ordered $true -OnlyShort $false -ExcludeTokens @())
        $pool | Should -HaveCount 20
        @($pool[0..7] | Where-Object { [string]$_.Structure -ne 'Одно слово' }) | Should -HaveCount 0
        @($pool[8..19] | Where-Object { [string]$_.Structure -ne 'Два слова' }) | Should -HaveCount 0
    }

    It 'без галочки «Генерация по порядку» выдача перемешивается' {
        $firstNames = New-Object System.Collections.ArrayList
        for ($run = 0; $run -lt 5; $run++) {
            $pool = @(New-AdvancedCandidatePool -SelectedWordCategories @('Тестовая') -CustomWords '' -CustomTheme '' -Style '— без стиля —' -Platform 'Roblox' -Prefix '' -Suffix '' -MinLength 3 -MaxLength 20 -Count 20 -UseNumbers $false -UseUnderscore $false -OneWord $true -TwoWords $true -OnlyShort $false -ExcludeTokens @())
            [void]$firstNames.Add([string]$pool[0].Name)
        }
        (@($firstNames | Select-Object -Unique)).Count | Should -BeGreaterThan 1
    }
}

Describe 'Интерфейс и поведение версии 2.5.5' {
    It 'список категорий строится из того же массива, которым пользуется генератор' {
        # Раньше названия были зашиты в интерфейсе строками и расходились со словарём.
        $global:UufMainText.Contains('AddRange([object[]]@($script:WordCategories))') | Should -BeTrue
        $global:UufMainText.Contains('$script:WordCategories = @(') | Should -BeTrue
    }

    It 'категории «Цельные слова» и «Короткие» убраны из выбора' {
        # Они дублировали галочки «Однословные ники» и «Только короткие», а короткие
        # слова теперь приходят из источника «Редкие короткие (3-6)».
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
        # Все пять галочек должны доходить до генератора.
        $global:UufFullText.Contains('-InventedWords ([bool]$script:InventedWordsCheck.Checked)') | Should -BeTrue
        $global:UufFullText.Contains('-InventedPairs ([bool]$script:InventedPairsCheck.Checked)') | Should -BeTrue
        $global:UufFullText.Contains('-LeetWords ([bool]$script:LeetCheck.Checked)') | Should -BeTrue
        $global:UufFullText.Contains('-RareShort ([bool]$script:RareShortCheck.Checked)') | Should -BeTrue
        $global:UufFullText.Contains('-Ordered ([bool]$script:OrderedCheck.Checked)') | Should -BeTrue
    }

    It 'число потоков задаётся в интерфейсе и ограничено восемью' {
        $global:UufMainText.Contains('$script:ThreadsBox = New-NumberBox 254 1007 110 1 8 2') | Should -BeTrue
        # Рекомендация 2–4 потока видна пользователю рядом с полем.
        $global:UufMainText.Contains('Рекомендуется 2–4 потока') | Should -BeTrue
        $global:UufMainText.Contains('if ($threadCount -gt 8) { $threadCount = 8 }') | Should -BeTrue
    }

    It 'проверка идёт в несколько потоков через общую очередь' {
        # Код запуска потоков расположен после here-string воркера, поэтому ищем в
        # полном тексте; сам цикл разбора очереди — внутри воркера.
        $global:UufFullText.Contains('for ($workerIndex = 1; $workerIndex -le $threadCount; $workerIndex++)') | Should -BeTrue
        $global:UufWorkerText.Contains('$InputQueue.TryDequeue([ref]$item)') | Should -BeTrue
        $global:UufMainText.Contains('function Test-CheckRunning') | Should -BeTrue
        # Прогон завершается только когда закончились все потоки. Проверка расположена
        # в PollTimer, то есть после here-string воркера, поэтому ищем в полном тексте.
        $global:UufFullText.Contains('-and -not (Test-CheckRunning)) {') | Should -BeTrue
    }

    It 'сортировка по умолчанию — порядок генерации, а не алфавит' {
        $global:UufMainText.Contains("'Порядок генерации'") | Should -BeTrue
        $global:UufMainText.Contains('$script:SortBox.SelectedIndex = 0') | Should -BeTrue
    }

    It 'под полосой прогресса выводится оценка оставшегося времени' {
        $global:UufMainText.Contains('function Get-CheckEtaText') | Should -BeTrue
        $global:UufMainText.Contains('осталось ~') | Should -BeTrue
        # Момент старта прогона фиксируется в Start-Checking — тоже после here-string.
        $global:UufFullText.Contains('$script:CheckStartedAt = [DateTime]::UtcNow') | Should -BeTrue
    }

    It 'позиция прокрутки таблицы сохраняется при перерисовке' {
        # Регрессия: таблица пересобирается целиком, и список прыгал наверх на каждом
        # результате проверки — смотреть нижние строки во время прогона было нельзя.
        $global:UufMainText.Contains('FirstDisplayedScrollingRowIndex') | Should -BeTrue
    }

    It 'таблица очищается перед каждой генерацией' {
        # Без очистки результаты накапливались, и вместо 1000 ников показывалось 1978.
        $global:UufFullText.Contains('$script:Candidates.Clear()') | Should -BeTrue
    }

    It 'список проверенных имён сохраняется между сеансами' {
        $global:UufMainText.Contains('CheckedNames = @($script:CheckedNames.Keys') | Should -BeTrue
        $global:UufMainText.Contains('$historyData.CheckedNames') | Should -BeTrue
        # Очистка таблицы не должна стирать постоянный список.
        $global:UufMainText.Contains('function Update-CheckedNamesButtonText') | Should -BeTrue
    }

    It 'потолок в 30 свободных ников снят' {
        # Из-за него новые свободные ники переставали попадать в историю после
        # тридцатого, хотя проверка продолжала их находить.
        $global:UufFullText.Contains('Select-Object -First 29') | Should -BeFalse
        $global:UufMainText.Contains('$script:FreeHistory = @(@($entry) + @($remaining))') | Should -BeTrue
    }

    It 'выбор платформы подставляет правило длины' {
        $global:UufFullText.Contains('Get-PlatformLengthRule -Platform $selectedPlatform') | Should -BeTrue
    }
}
