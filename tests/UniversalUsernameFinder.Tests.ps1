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
        'Import-AppSettings'
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

    It 'Roblox повторяет POST с токеном X-CSRF-Token' {
        $global:UufWorkerText.Contains('X-CSRF-Token') | Should -BeTrue
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
