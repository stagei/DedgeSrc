function Convert-FunctionDef {
    <#
    .SYNOPSIS
        Converts a FunctionDefinitionAst to a C# method definition.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$Ast,
        [hashtable]$Context
    )

    $sb = [System.Text.StringBuilder]::new()
    $indent = Get-Indent -Context $Context

    $methodName = Convert-FunctionNameToCSharp -Name $Ast.Name

    # Extract params
    $paramStr = ''
    if ($Ast.Body.ParamBlock) {
        $paramResult = Convert-ParamBlock -Ast $Ast.Body.ParamBlock -Context $Context
        $paramStr = $paramResult.Params
    }

    # Try to infer return type from body
    $returnType = Resolve-FunctionReturnType -Ast $Ast

    # XML doc comment from help block
    $helpComment = Get-FunctionHelpComment -Ast $Ast
    if ($helpComment) {
        [void]$sb.AppendLine("$indent/// <summary>")
        [void]$sb.AppendLine("$indent/// $helpComment")
        [void]$sb.AppendLine("$indent/// </summary>")
    }

    [void]$sb.AppendLine("${indent}public $returnType $methodName($paramStr)")
    [void]$sb.AppendLine("$indent{")

    # Convert function body
    $bodyCtx = $Context.Clone()
    $bodyCtx.IndentLevel = $Context.IndentLevel + 1
    $bodyStr = Convert-StatementBlock -Statements (Get-BodyStatements -Ast $Ast.Body) -Context $bodyCtx

    if ([string]::IsNullOrWhiteSpace($bodyStr)) {
        $innerIndent = Get-Indent -Context $bodyCtx
        [void]$sb.AppendLine("${innerIndent}throw new NotImplementedException();")
    }
    else {
        [void]$sb.Append($bodyStr)
    }

    [void]$sb.AppendLine("$indent}")

    return $sb.ToString()
}

function Convert-FunctionNameToCSharp {
    param([string]$Name)

    # Remove verb-noun dash and PascalCase: "Get-Content" → "GetContent"
    $parts = $Name -split '-'
    $result = ($parts | ForEach-Object {
        if ($_.Length -gt 0) {
            $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
        }
    }) -join ''

    if ([string]::IsNullOrEmpty($result)) { return 'UnknownMethod' }
    return $result
}

function Resolve-FunctionReturnType {
    param(
        [System.Management.Automation.Language.FunctionDefinitionAst]$Ast
    )

    # Check [OutputType] attribute
    if ($Ast.Body.ParamBlock) {
        foreach ($attr in $Ast.Body.ParamBlock.Attributes) {
            if ($attr -is [System.Management.Automation.Language.AttributeAst]) {
                if ($attr.TypeName.Name -eq 'OutputType') {
                    if ($attr.PositionalArguments.Count -gt 0) {
                        $typeArg = $attr.PositionalArguments[0]
                        if ($typeArg -is [System.Management.Automation.Language.TypeExpressionAst]) {
                            return Resolve-TypeName -PsTypeName $typeArg.TypeName.FullName
                        }
                    }
                }
            }
        }
    }

    # Search body for return statements
    $returns = $Ast.Body.FindAll({ param($a) $a -is [System.Management.Automation.Language.ReturnStatementAst] }, $false)
    if ($returns.Count -gt 0) {
        foreach ($ret in $returns) {
            if ($ret.Pipeline) { return 'object' }
        }
    }

    return 'void'
}

function Get-FunctionHelpComment {
    param(
        [System.Management.Automation.Language.FunctionDefinitionAst]$Ast
    )

    # Look for .SYNOPSIS in comment-based help
    $helpText = $Ast.GetHelpContent()
    if ($helpText -and $helpText.Synopsis) {
        return $helpText.Synopsis.Trim()
    }
    return $null
}

function Get-BodyStatements {
    param(
        [System.Management.Automation.Language.ScriptBlockAst]$Ast
    )

    $stmts = [System.Collections.ArrayList]::new()

    if ($Ast.BeginBlock -and $Ast.BeginBlock.Statements) {
        foreach ($s in $Ast.BeginBlock.Statements) { [void]$stmts.Add($s) }
    }
    if ($Ast.ProcessBlock -and $Ast.ProcessBlock.Statements) {
        foreach ($s in $Ast.ProcessBlock.Statements) { [void]$stmts.Add($s) }
    }
    if ($Ast.EndBlock -and $Ast.EndBlock.Statements) {
        foreach ($s in $Ast.EndBlock.Statements) { [void]$stmts.Add($s) }
    }

    return @($stmts)
}

function Get-Indent {
    param([hashtable]$Context)
    $level = if ($Context.IndentLevel) { $Context.IndentLevel } else { 0 }
    return ('    ' * $level)
}
