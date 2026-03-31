function Convert-AstNode {
    <#
    .SYNOPSIS
        Central dispatcher: converts any AST node to C# by switching on its type name.
        Delegates to specialised Convert-* functions for each category.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast,
        [hashtable]$Context
    )

    $typeName = $Ast.GetType().Name

    switch ($typeName) {

        # ── Top-level structures ──
        'ScriptBlockAst' {
            if ($Context.IsTopLevel) {
                $ctx = $Context.Clone()
                $ctx.IsTopLevel = $false
                return Convert-ScriptBlock -Ast $Ast -Context $ctx
            }
            # Nested script block: convert body statements
            $stmts = Get-BodyStatements -Ast $Ast
            if ($stmts.Count -eq 1) {
                return Convert-AstNode -Ast $stmts[0] -Context $Context
            }
            $sb = [System.Text.StringBuilder]::new()
            foreach ($s in $stmts) {
                $result = Convert-AstNode -Ast $s -Context $Context
                if ($result) { [void]$sb.Append($result) }
            }
            return $sb.ToString()
        }

        'NamedBlockAst' {
            return Convert-StatementBlock -Statements @($Ast.Statements) -Context $Context
        }

        'StatementBlockAst' {
            return Convert-StatementBlock -Statements @($Ast.Statements) -Context $Context
        }

        # ── Functions ──
        'FunctionDefinitionAst' {
            return Convert-FunctionDef -Ast $Ast -Context $Context
        }

        # ── Param block ──
        'ParamBlockAst' {
            $result = Convert-ParamBlock -Ast $Ast -Context $Context
            return $result.Params
        }

        # ── Pipelines ──
        'PipelineAst' {
            return Convert-Pipeline -Ast $Ast -Context $Context
        }

        'PipelineChainAst' {
            $left  = Convert-AstNode -Ast $Ast.LhsPipelineChain -Context $Context
            $right = Convert-AstNode -Ast $Ast.RhsPipeline -Context $Context
            $op = if ($Ast.Operator.ToString() -eq 'AndAnd') { '&&' } else { '||' }
            return "$left $op $right"
        }

        # ── Commands ──
        'CommandAst' {
            return Convert-Command -Ast $Ast -Context $Context
        }

        'CommandExpressionAst' {
            return Convert-Expression -Ast $Ast.Expression -Context $Context
        }

        # ── Statements (if/for/while/try/switch/assignment/return/etc.) ──
        'IfStatementAst'          { return Convert-Statement -Ast $Ast -Context $Context }
        'ForEachStatementAst'     { return Convert-Statement -Ast $Ast -Context $Context }
        'ForStatementAst'         { return Convert-Statement -Ast $Ast -Context $Context }
        'WhileStatementAst'       { return Convert-Statement -Ast $Ast -Context $Context }
        'DoWhileStatementAst'     { return Convert-Statement -Ast $Ast -Context $Context }
        'DoUntilStatementAst'     { return Convert-Statement -Ast $Ast -Context $Context }
        'SwitchStatementAst'      { return Convert-Statement -Ast $Ast -Context $Context }
        'TryStatementAst'         { return Convert-Statement -Ast $Ast -Context $Context }
        'ThrowStatementAst'       { return Convert-Statement -Ast $Ast -Context $Context }
        'ReturnStatementAst'      { return Convert-Statement -Ast $Ast -Context $Context }
        'BreakStatementAst'       { return Convert-Statement -Ast $Ast -Context $Context }
        'ContinueStatementAst'    { return Convert-Statement -Ast $Ast -Context $Context }
        'ExitStatementAst'        { return Convert-Statement -Ast $Ast -Context $Context }
        'AssignmentStatementAst'  { return Convert-Statement -Ast $Ast -Context $Context }

        # ── Expressions (handled by Convert-Expression) ──
        'ConstantExpressionAst'         { return Convert-Expression -Ast $Ast -Context $Context }
        'StringConstantExpressionAst'   { return Convert-Expression -Ast $Ast -Context $Context }
        'ExpandableStringExpressionAst' { return Convert-Expression -Ast $Ast -Context $Context }
        'VariableExpressionAst'         { return Convert-Expression -Ast $Ast -Context $Context }
        'BinaryExpressionAst'           { return Convert-Expression -Ast $Ast -Context $Context }
        'UnaryExpressionAst'            { return Convert-Expression -Ast $Ast -Context $Context }
        'ParenExpressionAst'            { return Convert-Expression -Ast $Ast -Context $Context }
        'SubExpressionAst'              { return Convert-Expression -Ast $Ast -Context $Context }
        'ArrayExpressionAst'            { return Convert-Expression -Ast $Ast -Context $Context }
        'ArrayLiteralAst'               { return Convert-Expression -Ast $Ast -Context $Context }
        'HashtableAst'                  { return Convert-Expression -Ast $Ast -Context $Context }
        'MemberExpressionAst'           { return Convert-Expression -Ast $Ast -Context $Context }
        'InvokeMemberExpressionAst'     { return Convert-Expression -Ast $Ast -Context $Context }
        'IndexExpressionAst'            { return Convert-Expression -Ast $Ast -Context $Context }
        'TypeExpressionAst'             { return Convert-Expression -Ast $Ast -Context $Context }
        'ConvertExpressionAst'          { return Convert-Expression -Ast $Ast -Context $Context }
        'AttributedExpressionAst'       { return Convert-Expression -Ast $Ast -Context $Context }
        'UsingExpressionAst'            { return Convert-Expression -Ast $Ast -Context $Context }
        'ScriptBlockExpressionAst'      { return Convert-Expression -Ast $Ast -Context $Context }
        'TernaryExpressionAst'          { return Convert-Expression -Ast $Ast -Context $Context }

        # ── Nodes we skip ──
        'TypeConstraintAst'  { return '' }
        'AttributeAst'       { return '' }
        'UsingStatementAst'  { return '' }

        # ── Fallback ──
        default {
            return Write-AiTag -TagName 'UNHANDLED_AST' `
                -OriginalSource $Ast.Extent.Text `
                -AstTypeName $typeName `
                -Hint "Unhandled AST node type — needs manual C# conversion" `
                -Context $Context
        }
    }
}
