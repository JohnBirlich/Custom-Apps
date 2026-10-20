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
        $global:UufMainText.Contains('$script:CountBox = New-NumberBox 14 709 90 5 2000 40') | Should -BeTrue
    }

    It 'поле Structure проходит через таблицу, поиск, сортировку и CSV' {
        $global:UufMainText.Contains("Columns.Add('Structure','СТРУКТУРА')") | Should -BeTrue
        $global:UufMainText.Contains('[string]$item.Structure') | Should -BeTrue
        $global:UufMainText.Contains('Sort-Object Structure') | Should -BeTrue
        # Экспорт CSV расположен после here-string воркера, поэтому ищем в полном тексте.
        $global:UufFullText.Contains('Name=''Структура'';Expression={$_.Structure}') | Should -BeTrue
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
