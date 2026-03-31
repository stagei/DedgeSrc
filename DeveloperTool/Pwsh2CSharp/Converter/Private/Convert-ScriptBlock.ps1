function Convert-ScriptBlock {
    <#
    .SYNOPSIS
        Converts a top-level ScriptBlockAst into a C# class file.
        Script-level params become constructor params, script-level code becomes Run() method,
        function definitions become class methods.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ScriptBlockAst]$Ast,
        [hashtable]$Context
    )

    $sb = [System.Text.StringBuilder]::new()
    $className = $Context.ClassName
    $namespace = $Context.Namespace

    # Separate function definitions from statements
    $functions  = [System.Collections.ArrayList]::new()
    $statements = [System.Collections.ArrayList]::new()

    $bodyStmts = Get-BodyStatements -Ast $Ast
    foreach ($stmt in $bodyStmts) {
        if ($stmt -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            [void]$functions.Add($stmt)
        }
        else {
            [void]$statements.Add($stmt)
        }
    }

    # Convert params to class fields + constructor
    $paramResult = $null
    if ($Ast.ParamBlock) {
        $paramResult = Convert-ParamBlock -Ast $Ast.ParamBlock -Context $Context
    }

    # Convert all function bodies and main body first so usings are collected
    $methodCtx = $Context.Clone()
    $methodCtx.IndentLevel = 2

    $methodStrings = [System.Collections.ArrayList]::new()
    foreach ($func in $functions) {
        $funcCtx = $Context.Clone()
        $funcCtx.IndentLevel = 2
        $funcStr = Convert-FunctionDef -Ast $func -Context $funcCtx
        [void]$methodStrings.Add($funcStr)
    }

    # Convert main body statements
    $mainBodyCtx = $Context.Clone()
    $mainBodyCtx.IndentLevel = 3
    $mainBody = Convert-StatementBlock -Statements @($statements) -Context $mainBodyCtx

    # -- Emit the file --

    # Usings (always include basics, plus collected)
    $defaultUsings = @(
        'System',
        'System.Collections.Generic',
        'System.IO',
        'System.Linq',
        'System.Text',
        'System.Threading.Tasks'
    )

    $allUsings = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($u in $defaultUsings) { [void]$allUsings.Add($u) }
    foreach ($u in $Context.Usings)  { [void]$allUsings.Add($u) }

    foreach ($u in ($allUsings | Sort-Object)) {
        [void]$sb.AppendLine("using $u;")
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine("namespace $namespace;")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("/// <summary>")
    [void]$sb.AppendLine("/// Converted from $($Context.SourceFileName)")
    [void]$sb.AppendLine("/// </summary>")
    [void]$sb.AppendLine("public class $className")
    [void]$sb.AppendLine('{')

    # Logger field
    [void]$sb.AppendLine('    private static readonly NLog.Logger Logger = NLog.LogManager.GetCurrentClassLogger();')
    [void]$sb.AppendLine()

    # Fields from params
    if ($paramResult -and $paramResult.ParamList.Count -gt 0) {
        foreach ($p in $paramResult.ParamList) {
            $fieldName = "_$($p.Name)"
            [void]$sb.AppendLine("    private readonly $($p.Type) $fieldName;")
        }
        [void]$sb.AppendLine()

        # Constructor
        [void]$sb.AppendLine("    public $className($($paramResult.Params))")
        [void]$sb.AppendLine('    {')
        foreach ($p in $paramResult.ParamList) {
            [void]$sb.AppendLine("        _$($p.Name) = $($p.Name);")
        }
        [void]$sb.AppendLine('    }')
        [void]$sb.AppendLine()
    }

    # Run method for main body
    if ($statements.Count -gt 0) {
        [void]$sb.AppendLine('    /// <summary>')
        [void]$sb.AppendLine('    /// Main execution entry point.')
        [void]$sb.AppendLine('    /// </summary>')
        $runSignature = if ($Context.SharedState -and $Context.SharedState.HasAsync) {
            'public async Task<int> Run()'
        } else {
            'public int Run()'
        }
        [void]$sb.AppendLine("    $runSignature")
        [void]$sb.AppendLine('    {')

        if ([string]::IsNullOrWhiteSpace($mainBody)) {
            [void]$sb.AppendLine('        throw new NotImplementedException();')
        }
        else {
            [void]$sb.Append($mainBody)
            # Ensure a return statement
            if ($mainBody -notmatch 'return\s') {
                [void]$sb.AppendLine('        return 0;')
            }
        }

        [void]$sb.AppendLine('    }')
        [void]$sb.AppendLine()
    }

    # Methods from functions
    foreach ($methodStr in $methodStrings) {
        [void]$sb.Append($methodStr)
        [void]$sb.AppendLine()
    }

    [void]$sb.AppendLine('}')

    return $sb.ToString()
}
