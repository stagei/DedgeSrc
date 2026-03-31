function Convert-Expression {
    <#
    .SYNOPSIS
        Converts a PowerShell expression AST node to a C# expression string.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast,
        [hashtable]$Context
    )

    $typeName = $Ast.GetType().Name

    switch ($typeName) {

        'ConstantExpressionAst' {
            $val = $Ast.Value
            if ($null -eq $val)          { return 'null' }
            if ($val -is [bool])         { return if ($val) { 'true' } else { 'false' } }
            if ($val -is [int])          { return $val.ToString() }
            if ($val -is [long])         { return "$($val)L" }
            if ($val -is [double])       { return "$($val)d" }
            if ($val -is [decimal])      { return "$($val)m" }
            return $val.ToString()
        }

        'StringConstantExpressionAst' {
            $text = $Ast.Value
            $style = $Ast.StringConstantType.ToString()
            if ($style -eq 'BareWord') { return """$text""" }
            $escaped = $text.Replace('\', '\\').Replace('"', '\"')
            return """$escaped"""
        }

        'ExpandableStringExpressionAst' {
            return Convert-InterpolatedString -Ast $Ast -Context $Context
        }

        'VariableExpressionAst' {
            $varName = $Ast.VariablePath.UserPath
            switch ($varName) {
                'true'               { return 'true' }
                'false'              { return 'false' }
                'null'               { return 'null' }
                '_'                  { return 'item' }
                'PSScriptRoot'       { return 'AppContext.BaseDirectory' }
                'env:USERNAME'       { return 'Environment.UserName' }
                'LASTEXITCODE'       { return 'exitCode' }
                'ErrorActionPreference' { return '/* ErrorActionPreference */' }
                default {
                    if ($varName -match '^env:(.+)$') {
                        $envVar = $Matches[1]
                        return "Environment.GetEnvironmentVariable(""$envVar"")"
                    }
                    return Convert-VariableName -Name $varName
                }
            }
        }

        'BinaryExpressionAst' {
            $left  = Convert-Expression -Ast $Ast.Left -Context $Context
            $right = Convert-Expression -Ast $Ast.Right -Context $Context
            $op = Convert-BinaryOperator -Operator $Ast.Operator -Left $left -Right $right
            if ($op -match 'Regex\.(IsMatch|Replace|Match)') {
                [void]$Context.Usings.Add('System.Text.RegularExpressions')
            }
            if ($op -match 'Enumerable\.Range') {
                [void]$Context.Usings.Add('System.Linq')
            }
            return $op
        }

        'UnaryExpressionAst' {
            $child = Convert-Expression -Ast $Ast.Child -Context $Context
            switch ($Ast.TokenKind.ToString()) {
                'Not'          { return "!($child)" }
                'Exclaim'      { return "!($child)" }
                'Minus'        { return "-($child)" }
                'Plus'         { return "+($child)" }
                'PlusPlus'     { return "$($child)++" }
                'MinusMinus'   { return "$($child)--" }
                'PostfixPlusPlus'  { return "$($child)++" }
                'PostfixMinusMinus' { return "$($child)--" }
                default        { return "/* Unary $($Ast.TokenKind) */ $child" }
            }
        }

        'ParenExpressionAst' {
            $inner = Convert-AstNode -Ast $Ast.Pipeline -Context $Context
            return "($inner)"
        }

        'SubExpressionAst' {
            $inner = Convert-AstNode -Ast $Ast.SubExpression -Context $Context
            return $inner
        }

        'ArrayExpressionAst' {
            $stmts = @($Ast.SubExpression.Statements)
            if ($stmts.Count -eq 0) { return 'new List<object>()' }
            $elements = @()
            foreach ($stmt in $stmts) {
                $converted = Convert-AstNode -Ast $stmt -Context $Context
                $converted = $converted.Trim().TrimEnd(';').Trim()
                if (-not [string]::IsNullOrWhiteSpace($converted)) {
                    $elements += $converted
                }
            }
            if ($elements.Count -eq 0) { return 'new List<object>()' }
            $body = $elements -join ", "
            return "new List<object> { $body }"
        }

        'ArrayLiteralAst' {
            $elements = @()
            foreach ($elem in $Ast.Elements) {
                $elements += Convert-Expression -Ast $elem -Context $Context
            }
            return ($elements -join ', ')
        }

        'HashtableAst' {
            $entries = [System.Collections.ArrayList]::new()
            foreach ($pair in $Ast.KeyValuePairs) {
                $key   = Convert-Expression -Ast $pair.Item1 -Context $Context
                $value = Convert-AstNode -Ast $pair.Item2 -Context $Context
                $keyStr = $key.Trim('"')
                [void]$entries.Add("[""$keyStr""] = $value")
            }
            $body = $entries -join ", `n    "
            return "new Dictionary<string, object?>`n{`n    $body`n}"
        }

        'MemberExpressionAst' {
            $member = $Ast.Member.ToString()
            $csMember = Convert-PropertyName -Name $member
            if ($Ast.Static -and $Ast.Expression -is [System.Management.Automation.Language.TypeExpressionAst]) {
                $csType = Resolve-TypeName -PsTypeName $Ast.Expression.TypeName.FullName
                return "$($csType).$csMember"
            }
            $expr = Convert-Expression -Ast $Ast.Expression -Context $Context
            return "$($expr).$csMember"
        }

        'InvokeMemberExpressionAst' {
            $method = $Ast.Member.ToString()
            $csMethod = Convert-PropertyName -Name $method
            $args = @()
            if ($Ast.Arguments) {
                foreach ($arg in $Ast.Arguments) {
                    $args += Convert-Expression -Ast $arg -Context $Context
                }
            }
            $argStr = $args -join ', '
            if ($Ast.Static -and $Ast.Expression -is [System.Management.Automation.Language.TypeExpressionAst]) {
                $csType = Resolve-TypeName -PsTypeName $Ast.Expression.TypeName.FullName
                return "$($csType).$($csMethod)($argStr)"
            }
            $expr = Convert-Expression -Ast $Ast.Expression -Context $Context
            return "$($expr).$($csMethod)($argStr)"
        }

        'IndexExpressionAst' {
            $target = Convert-Expression -Ast $Ast.Target -Context $Context
            $index  = Convert-Expression -Ast $Ast.Index -Context $Context
            return "$($target)[$index]"
        }

        'TypeExpressionAst' {
            $csType = Resolve-TypeName -PsTypeName $Ast.TypeName.FullName
            return "typeof($csType)"
        }

        'ConvertExpressionAst' {
            $csType = Resolve-TypeName -PsTypeName $Ast.Type.TypeName.FullName
            $child  = Convert-Expression -Ast $Ast.Child -Context $Context
            return "($csType)$child"
        }

        'AttributedExpressionAst' {
            return Convert-Expression -Ast $Ast.Child -Context $Context
        }

        'UsingExpressionAst' {
            return Convert-Expression -Ast $Ast.SubExpression -Context $Context
        }

        'ScriptBlockExpressionAst' {
            # { ... } as expression (e.g. Where-Object { $_ })
            $body = Convert-AstNode -Ast $Ast.ScriptBlock -Context $Context
            return "($body)"
        }

        'TernaryExpressionAst' {
            $cond = Convert-Expression -Ast $Ast.Condition -Context $Context
            $ifTrue  = Convert-Expression -Ast $Ast.IfTrue -Context $Context
            $ifFalse = Convert-Expression -Ast $Ast.IfFalse -Context $Context
            return "$cond ? $ifTrue : $ifFalse"
        }

        default {
            return Write-AiTag -TagName 'UNHANDLED_AST' `
                -OriginalSource $Ast.Extent.Text `
                -AstTypeName $typeName `
                -Hint "Unhandled expression type — needs C# equivalent" `
                -Context $Context
        }
    }
}

function Convert-InterpolatedString {
    param(
        [System.Management.Automation.Language.ExpandableStringExpressionAst]$Ast,
        [hashtable]$Context
    )

    $original = $Ast.Extent.Text
    if ($original.StartsWith('"'))  { $original = $original.Substring(1) }
    if ($original.EndsWith('"'))    { $original = $original.Substring(0, $original.Length - 1) }

    # Sort nested expressions by their position (descending) so replacements don't shift offsets
    $sortedNested = @($Ast.NestedExpressions | Sort-Object { $_.Extent.StartOffset } -Descending)

    # Get the full extent start offset to compute relative positions
    $extentStart = $Ast.Extent.StartOffset + 1  # +1 for opening quote

    $csString = $original
    foreach ($nested in $sortedNested) {
        $csExpr = Convert-AstNode -Ast $nested -Context $Context
        # Clean up: remove trailing semicolons/newlines that statement converters might add
        $csExpr = $csExpr.Trim().TrimEnd(';').Trim()
        $psText = $nested.Extent.Text
        $csString = $csString.Replace($psText, "{$csExpr}")
    }

    return "`$""$csString"""
}

function Convert-BinaryOperator {
    param(
        [string]$Operator,
        [string]$Left,
        [string]$Right
    )

    switch ($Operator) {
        'Ieq'          { return "$Left == $Right" }
        'Ceq'          { return "string.Equals($Left, $Right, StringComparison.Ordinal)" }
        'Ine'          { return "$Left != $Right" }
        'Cne'          { return "!string.Equals($Left, $Right, StringComparison.Ordinal)" }
        'Igt'          { return "$Left > $Right" }
        'Ige'          { return "$Left >= $Right" }
        'Ilt'          { return "$Left < $Right" }
        'Ile'          { return "$Left <= $Right" }
        'And'          { return "$Left && $Right" }
        'Or'           { return "$Left || $Right" }
        'Xor'          { return "$Left ^ $Right" }
        'Band'         { return "$Left & $Right" }
        'Bor'          { return "$Left | $Right" }
        'Bxor'         { return "$Left ^ $Right" }
        'Plus'         { return "$Left + $Right" }
        'Minus'        { return "$Left - $Right" }
        'Multiply'     { return "$Left * $Right" }
        'Divide'       { return "$Left / $Right" }
        'Rem'          { return "$Left % $Right" }
        'Shl'          { return "$Left << $Right" }
        'Shr'          { return "$Left >> $Right" }
        'DotDot'       { return "Enumerable.Range($Left, $Right - $Left + 1)" }
        'Imatch'       { return "Regex.IsMatch($Left, $Right, RegexOptions.IgnoreCase)" }
        'Cmatch'       { return "Regex.IsMatch($Left, $Right)" }
        'Inotmatch'    { return "!Regex.IsMatch($Left, $Right, RegexOptions.IgnoreCase)" }
        'Ilike'        { return "/* -like */ $Left.Contains($Right)" }
        'Inotlike'     { return "/* -notlike */ !$Left.Contains($Right)" }
        'Ireplace'     { return "Regex.Replace($Left, $Right)" }
        'Is' {
            # [regex]: ^typeof\((.+)\)$ — strip typeof() wrapper from type operand
            # ^typeof\(  — match literal prefix
            # (.+)       — capture group 1: the type name inside
            # \)$        — match closing paren at end
            $rhs = if ($Right -match '^typeof\((.+)\)$') { $Matches[1] } else { $Right }
            return "$Left is $rhs"
        }
        'IsNot' {
            $rhs = if ($Right -match '^typeof\((.+)\)$') { $Matches[1] } else { $Right }
            return "$Left is not $rhs"
        }
        'As' {
            $rhs = if ($Right -match '^typeof\((.+)\)$') { $Matches[1] } else { $Right }
            return "$Left as $rhs"
        }
        'Icontains'    { return "$Left.Contains($Right)" }
        'Inotcontains' { return "!$Left.Contains($Right)" }
        'Iin'          { return "$Right.Contains($Left)" }
        'Inotin'       { return "!$Right.Contains($Left)" }
        'Isplit'       { return "$Left.Split($Right)" }
        'Join'         { return "string.Join($Right, $Left)" }
        'Format'       { return "string.Format($Left, $Right)" }

        # Assignment operators
        'Equals'            { return "$Left = $Right" }
        'PlusEquals'        { return "$Left += $Right" }
        'MinusEquals'       { return "$Left -= $Right" }
        'MultiplyEquals'    { return "$Left *= $Right" }
        'DivideEquals'      { return "$Left /= $Right" }
        'RemainderEquals'   { return "$Left %= $Right" }

        default        { return "/* Op:$Operator */ $Left $Right" }
    }
}

function Convert-VariableName {
    param([string]$Name)

    # camelCase convention for local variables
    if ($Name.Length -le 1) { return $Name.ToLowerInvariant() }
    return $Name.Substring(0, 1).ToLowerInvariant() + $Name.Substring(1)
}

function Convert-PropertyName {
    param([string]$Name)

    # PascalCase convention for properties/methods
    if ($Name.Length -le 1) { return $Name.ToUpperInvariant() }
    return $Name.Substring(0, 1).ToUpperInvariant() + $Name.Substring(1)
}
