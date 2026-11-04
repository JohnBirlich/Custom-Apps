@{
    Severity = @('Error', 'Warning', 'Information')

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
