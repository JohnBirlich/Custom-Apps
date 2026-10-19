@{
    # Замечания выводим все, но сборку роняет только Severity = Error (см. ci.yml).
    Severity = @('Error', 'Warning', 'Information')

    # Правила, которые не применимы к настольному WinForms-приложению на PowerShell
    # или намеренно нарушены (пустые catch-блоки для «лучше без журнала, чем падение»).
    ExcludeRules = @(
        'PSUseApprovedVerbs',
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingInvokeExpression',
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingUsernameAndPasswordParams',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSUseSingularNouns',
        'PSAvoidGlobalVars',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidAssignmentToAutomaticVariable',
        'PSAvoidUsingWMICmdlet'
    )
}
