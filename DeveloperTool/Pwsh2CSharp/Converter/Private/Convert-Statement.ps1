function Convert-Statement {
    <#
    .SYNOPSIS
        Converts a single PowerShell statement AST node to C#.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast,
        [hashtable]$Context
    )

    $indent = Get-Indent -Context $Context
    $typeName = $Ast.GetType().Name

    switch ($typeName) {

        'IfStatementAst' {
            return Convert-IfStatement -Ast $Ast -Context $Context
        }

        'ForEachStatementAst' {
            return Convert-ForEachStatement -Ast $Ast -Context $Context
        }

        'ForStatementAst' {
            return Convert-ForStatement -Ast $Ast -Context $Context
        }

        'WhileStatementAst' {
            $rawCond = Convert-AstNode -Ast $Ast.Condition -Context $Context
            $cond = Wrap-TruthinessCondition -CsCondition $rawCond -ConditionAst $Ast.Condition
            $bodyCtx = $Context.Clone()
            $bodyCtx.IndentLevel = $Context.IndentLevel + 1
            $body = Convert-StatementBlock -Statements $Ast.Body.Statements -Context $bodyCtx
            return "${indent}while ($cond)`n$indent{`n$body$indent}`n"
        }

        'DoWhileStatementAst' {
            $rawCond = Convert-AstNode -Ast $Ast.Condition -Context $Context
            $cond = Wrap-TruthinessCondition -CsCondition $rawCond -ConditionAst $Ast.Condition
            $bodyCtx = $Context.Clone()
            $bodyCtx.IndentLevel = $Context.IndentLevel + 1
            $body = Convert-StatementBlock -Statements $Ast.Body.Statements -Context $bodyCtx
            return "${indent}do`n$indent{`n$body$indent}`nwhile ($cond);`n"
        }

        'DoUntilStatementAst' {
            $rawCond = Convert-AstNode -Ast $Ast.Condition -Context $Context
            $cond = Wrap-TruthinessCondition -CsCondition $rawCond -ConditionAst $Ast.Condition
            $bodyCtx = $Context.Clone()
            $bodyCtx.IndentLevel = $Context.IndentLevel + 1
            $body = Convert-StatementBlock -Statements $Ast.Body.Statements -Context $bodyCtx
            return "${indent}do`n$indent{`n$body$indent}`nwhile (!($cond));`n"
        }

        'SwitchStatementAst' {
            return Convert-SwitchStatement -Ast $Ast -Context $Context
        }

        'TryStatementAst' {
            return Convert-TryStatement -Ast $Ast -Context $Context
        }

        'ThrowStatementAst' {
            if ($Ast.Pipeline) {
                $expr = Convert-AstNode -Ast $Ast.Pipeline -Context $Context
                return "${indent}throw new Exception($expr);`n"
            }
            return "${indent}throw;`n"
        }

        'ReturnStatementAst' {
            if ($Ast.Pipeline) {
                $expr = Convert-AstNode -Ast $Ast.Pipeline -Context $Context
                return "${indent}return $expr;`n"
            }
            return "${indent}return;`n"
        }

        'BreakStatementAst' {
            return "${indent}break;`n"
        }

        'ContinueStatementAst' {
            return "${indent}continue;`n"
        }

        'ExitStatementAst' {
            if ($Ast.Pipeline) {
                $code = Convert-AstNode -Ast $Ast.Pipeline -Context $Context
                return "${indent}Environment.Exit($code);`n"
            }
            return "${indent}Environment.Exit(0);`n"
        }

        'AssignmentStatementAst' {
            return Convert-AssignmentStatement -Ast $Ast -Context $Context
        }

        default {
            return $null
        }
    }
}

function Convert-StatementBlock {
    param(
        [array]$Statements,
        [hashtable]$Context
    )

    $sb = [System.Text.StringBuilder]::new()

    foreach ($stmt in $Statements) {
        if ($null -eq $stmt) { continue }

        $result = Convert-AstNode -Ast $stmt -Context $Context
        if (-not [string]::IsNullOrWhiteSpace($result)) {
            # If the result doesn't end with newline or semicolon, add one
            $trimmed = $result.TrimEnd()
            if ($trimmed -and -not $trimmed.EndsWith('}') -and -not $trimmed.EndsWith(';') -and -not $trimmed.EndsWith('*/') -and -not $trimmed.EndsWith("`n")) {
                $indent = Get-Indent -Context $Context
                [void]$sb.AppendLine("$indent$($trimmed);")
            }
            else {
                [void]$sb.Append($result)
            }
        }
    }

    return $sb.ToString()
}

function Convert-IfStatement {
    param(
        [System.Management.Automation.Language.IfStatementAst]$Ast,
        [hashtable]$Context
    )

    $indent = Get-Indent -Context $Context
    $sb = [System.Text.StringBuilder]::new()
    $bodyCtx = $Context.Clone()
    $bodyCtx.IndentLevel = $Context.IndentLevel + 1

    for ($i = 0; $i -lt $Ast.Clauses.Count; $i++) {
        $clause = $Ast.Clauses[$i]
        $rawCond = Convert-AstNode -Ast $clause.Item1 -Context $Context
        $cond = Wrap-TruthinessCondition -CsCondition $rawCond -ConditionAst $clause.Item1
        $body = Convert-StatementBlock -Statements $clause.Item2.Statements -Context $bodyCtx

        if ($i -eq 0) {
            [void]$sb.AppendLine("${indent}if ($cond)")
        }
        else {
            [void]$sb.AppendLine("${indent}else if ($cond)")
        }
        [void]$sb.AppendLine("$indent{")
        [void]$sb.Append($body)
        [void]$sb.AppendLine("$indent}")
    }

    if ($Ast.ElseClause) {
        $elseBody = Convert-StatementBlock -Statements $Ast.ElseClause.Statements -Context $bodyCtx
        [void]$sb.AppendLine("${indent}else")
        [void]$sb.AppendLine("$indent{")
        [void]$sb.Append($elseBody)
        [void]$sb.AppendLine("$indent}")
    }

    return $sb.ToString()
}

function Convert-ForEachStatement {
    param(
        [System.Management.Automation.Language.ForEachStatementAst]$Ast,
        [hashtable]$Context
    )

    $indent  = Get-Indent -Context $Context
    $varName = Convert-VariableName -Name $Ast.Variable.VariablePath.UserPath
    $coll    = Convert-AstNode -Ast $Ast.Condition -Context $Context
    $bodyCtx = $Context.Clone()
    $bodyCtx.IndentLevel = $Context.IndentLevel + 1
    $body    = Convert-StatementBlock -Statements $Ast.Body.Statements -Context $bodyCtx

    return "${indent}foreach (var $varName in $coll)`n$indent{`n$body$indent}`n"
}

function Convert-ForStatement {
    param(
        [System.Management.Automation.Language.ForStatementAst]$Ast,
        [hashtable]$Context
    )

    $indent = Get-Indent -Context $Context

    $init = ''
    if ($Ast.Initializer) {
        $init = Convert-AstNode -Ast $Ast.Initializer -Context $Context
        $init = $init.TrimEnd(';', ' ', "`n")
    }

    $cond = ''
    if ($Ast.Condition) {
        $cond = Convert-Expression -Ast $Ast.Condition -Context $Context
    }

    $iter = ''
    if ($Ast.Iterator) {
        $iter = Convert-AstNode -Ast $Ast.Iterator -Context $Context
        $iter = $iter.TrimEnd(';', ' ', "`n")
    }

    $bodyCtx = $Context.Clone()
    $bodyCtx.IndentLevel = $Context.IndentLevel + 1
    $body = Convert-StatementBlock -Statements $Ast.Body.Statements -Context $bodyCtx

    return "${indent}for ($init; $cond; $iter)`n$indent{`n$body$indent}`n"
}

function Convert-SwitchStatement {
    param(
        [System.Management.Automation.Language.SwitchStatementAst]$Ast,
        [hashtable]$Context
    )

    $indent = Get-Indent -Context $Context
    $sb = [System.Text.StringBuilder]::new()

    $switchExpr = Convert-AstNode -Ast $Ast.Condition -Context $Context
    [void]$sb.AppendLine("${indent}switch ($switchExpr)")
    [void]$sb.AppendLine("$indent{")

    $caseCtx = $Context.Clone()
    $caseCtx.IndentLevel = $Context.IndentLevel + 1
    $bodyCtx = $Context.Clone()
    $bodyCtx.IndentLevel = $Context.IndentLevel + 2
    $caseIndent = Get-Indent -Context $caseCtx

    foreach ($clause in $Ast.Clauses) {
        $label = $clause.Item1
        $body  = $clause.Item2

        $labelText = Convert-Expression -Ast $label -Context $Context
        [void]$sb.AppendLine("${caseIndent}case ${labelText}:")

        $caseBody = Convert-StatementBlock -Statements $body.Statements -Context $bodyCtx
        [void]$sb.Append($caseBody)

        $bodyIndent = Get-Indent -Context $bodyCtx
        [void]$sb.AppendLine("${bodyIndent}break;")
    }

    if ($Ast.Default) {
        [void]$sb.AppendLine("${caseIndent}default:")
        $defaultBody = Convert-StatementBlock -Statements $Ast.Default.Statements -Context $bodyCtx
        [void]$sb.Append($defaultBody)
        $bodyIndent = Get-Indent -Context $bodyCtx
        [void]$sb.AppendLine("${bodyIndent}break;")
    }

    [void]$sb.AppendLine("$indent}")
    return $sb.ToString()
}

function Convert-TryStatement {
    param(
        [System.Management.Automation.Language.TryStatementAst]$Ast,
        [hashtable]$Context
    )

    $indent = Get-Indent -Context $Context
    $sb = [System.Text.StringBuilder]::new()
    $bodyCtx = $Context.Clone()
    $bodyCtx.IndentLevel = $Context.IndentLevel + 1

    $tryBody = Convert-StatementBlock -Statements $Ast.Body.Statements -Context $bodyCtx
    [void]$sb.AppendLine("${indent}try")
    [void]$sb.AppendLine("$indent{")
    [void]$sb.Append($tryBody)
    [void]$sb.AppendLine("$indent}")

    foreach ($catch in $Ast.CatchClauses) {
        $catchType = 'Exception'
        if ($catch.CatchTypes.Count -gt 0) {
            $catchType = Resolve-TypeName -PsTypeName $catch.CatchTypes[0].TypeName.FullName
        }

        $catchBody = Convert-StatementBlock -Statements $catch.Body.Statements -Context $bodyCtx

        if ($catch.IsCatchAll -or $catchType -eq 'Exception') {
            [void]$sb.AppendLine("${indent}catch (Exception ex)")
        }
        else {
            [void]$sb.AppendLine("${indent}catch ($catchType ex)")
        }
        [void]$sb.AppendLine("$indent{")
        [void]$sb.Append($catchBody)
        [void]$sb.AppendLine("$indent}")
    }

    if ($Ast.Finally) {
        $finallyBody = Convert-StatementBlock -Statements $Ast.Finally.Statements -Context $bodyCtx
        [void]$sb.AppendLine("${indent}finally")
        [void]$sb.AppendLine("$indent{")
        [void]$sb.Append($finallyBody)
        [void]$sb.AppendLine("$indent}")
    }

    return $sb.ToString()
}

function Convert-AssignmentStatement {
    param(
        [System.Management.Automation.Language.AssignmentStatementAst]$Ast,
        [hashtable]$Context
    )

    $indent = Get-Indent -Context $Context

    # Detect PS automatic/preference variable assignments and emit as comments
    $psAutoVars = @(
        'ErrorActionPreference', 'ProgressPreference', 'VerbosePreference',
        'WarningPreference', 'InformationPreference', 'ConfirmPreference',
        'DebugPreference', 'WhatIfPreference', 'OFS'
    )
    if ($Ast.Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $rawVarName = $Ast.Left.VariablePath.UserPath
        if ($rawVarName -in $psAutoVars) {
            $rightText = $Ast.Right.Extent.Text
            return "${indent}// PS: `$$($rawVarName) = $rightText (handled by C# exception/config flow)`n"
        }
    }

    $left  = Convert-Expression -Ast $Ast.Left -Context $Context
    $right = Convert-AstNode -Ast $Ast.Right -Context $Context

    $op = switch ($Ast.Operator.ToString()) {
        'Equals'          { '=' }
        'PlusEquals'      { '+=' }
        'MinusEquals'     { '-=' }
        'MultiplyEquals'  { '*=' }
        'DivideEquals'    { '/=' }
        'RemainderEquals' { '%=' }
        default           { '=' }
    }

    $varName = $left.Trim()

    # Only emit 'var' for simple variable names (VariableExpressionAst), not member/index access
    $isSimpleVar = $Ast.Left -is [System.Management.Automation.Language.VariableExpressionAst]

    if ($op -eq '=' -and $isSimpleVar -and -not $Context.DeclaredVars.Contains($varName)) {
        $Context.DeclaredVars.Add($varName) | Out-Null
        return "${indent}var $left $op $right;`n"
    }

    return "${indent}$left $op $right;`n"
}

function Wrap-TruthinessCondition {
    <#
    .SYNOPSIS
        Wraps a C# condition string with proper null/empty checks when the
        PowerShell source relies on implicit truthiness (e.g. if ($x) { ... }).
    #>
    param(
        [string]$CsCondition,
        [System.Management.Automation.Language.Ast]$ConditionAst
    )

    $trimmed = $CsCondition.Trim()

    # Already a C# boolean expression (contains comparison/logical operators) — leave as-is
    # [regex]: (==|!=|>=|<=|(?<!=)>(?!=)|(?<!=)<(?!=)|\bis\b|\bis not\b)
    #   ==, !=, >=, <=  — equality/comparison operators
    #   (?<!=)>(?!=)     — greater-than not part of => or >=
    #   (?<!=)<(?!=)     — less-than not part of <= or =>
    #   \bis\b, \bis not\b — C# type check operators
    if ($trimmed -match '(==|!=|>=|<=|(?<!=)>(?!=)|(?<!=)<(?!=)|\bis\b|\bis not\b)') {
        return $trimmed
    }

    # Contains LINQ/method calls that return bool — leave as-is
    if ($trimmed -match '\.(Contains|Any|Exists|StartsWith|EndsWith|Equals|IsMatch)\(') {
        return $trimmed
    }

    # Boolean literals
    if ($trimmed -eq 'true' -or $trimmed -eq 'false') { return $trimmed }

    # Ends with () — method call, likely returns bool already
    if ($trimmed -match '[a-zA-Z0-9_]\)\s*$' -and $trimmed -notmatch '^\!\s*\(') {
        return $trimmed
    }

    # Numeric literal — compare to zero
    if ($trimmed -match '^\d+$') { return "$trimmed != 0" }

    # Negated simple variable: !(varName) → string.IsNullOrEmpty(varName)
    # [regex]: ^\!\s*\(([a-zA-Z_][a-zA-Z0-9_]*)\)$
    #   ^\!\s*\(  — starts with ! and optional whitespace then (
    #   ([a-zA-Z_][a-zA-Z0-9_]*)  — group 1: simple identifier
    #   \)$       — closing paren at end
    if ($trimmed -match '^\!\s*\(([a-zA-Z_][a-zA-Z0-9_]*)\)$') {
        return "string.IsNullOrEmpty($($Matches[1]))"
    }

    # Negated member access: !(obj.Prop) → obj.Prop == null
    if ($trimmed -match '^\!\s*\(([a-zA-Z_][a-zA-Z0-9_.]+)\)$') {
        return "$($Matches[1]) == null"
    }

    # Simple identifier (variable name) → null/empty check
    if ($trimmed -match '^[a-zA-Z_][a-zA-Z0-9_]*$') {
        return "!string.IsNullOrEmpty($trimmed)"
    }

    # Member access (obj.Prop) → null check
    if ($trimmed -match '^[a-zA-Z_][a-zA-Z0-9_.]+$') {
        return "$trimmed != null"
    }

    return $trimmed
}
