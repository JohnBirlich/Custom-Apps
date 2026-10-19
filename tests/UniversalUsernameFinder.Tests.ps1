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
        'Get-ShuffledArray'
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
