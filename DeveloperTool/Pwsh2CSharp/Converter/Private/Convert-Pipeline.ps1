function Convert-Pipeline {
    <#
    .SYNOPSIS
        Converts a PipelineAst (one or more pipeline elements) to C#.
        Single-element pipelines delegate to Convert-Command or Convert-Expression.
        Multi-element pipelines map to LINQ chains.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.PipelineAst]$Ast,
        [hashtable]$Context
    )

    $elements = @($Ast.PipelineElements)

    if ($elements.Count -eq 0) { return '' }

    # Single-element pipeline: just convert the element directly
    if ($elements.Count -eq 1) {
        return Convert-PipelineElement -Ast $elements[0] -Context $Context
    }

    # Multi-element pipeline: first element is the source, rest are chained
    $source = Convert-PipelineElement -Ast $elements[0] -Context $Context

    for ($i = 1; $i -lt $elements.Count; $i++) {
        $elem = $elements[$i]
        $source = Convert-PipelineStep -Source $source -Ast $elem -Context $Context
    }

    return $source
}

function Convert-PipelineElement {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast,
        [hashtable]$Context
    )

    $typeName = $Ast.GetType().Name

    switch ($typeName) {
        'CommandAst' {
            return Convert-Command -Ast $Ast -Context $Context
        }
        'CommandExpressionAst' {
            return Convert-Expression -Ast $Ast.Expression -Context $Context
        }
        default {
            return Convert-AstNode -Ast $Ast -Context $Context
        }
    }
}

function Convert-PipelineStep {
    <#
    .SYNOPSIS
        Converts a pipeline element into a chained LINQ call on $Source.
    #>
    param(
        [string]$Source,
        [System.Management.Automation.Language.Ast]$Ast,
        [hashtable]$Context
    )

    if ($Ast -isnot [System.Management.Automation.Language.CommandAst]) {
        $expr = Convert-PipelineElement -Ast $Ast -Context $Context
        return "$Source /* | */ $expr"
    }

    $cmdName = Get-CommandName -Ast $Ast
    $params  = Get-CommandParams -Ast $Ast

    switch ($cmdName) {
        'Where-Object' {
            $predicate = Get-ScriptBlockArg -Params $params -Context $Context
            if ($predicate) {
                return "$($Source).Where(item => $predicate)"
            }
            # Property-based: Where-Object Property -eq Value
            $propFilter = Get-PropertyFilter -Params $params -Context $Context
            if ($propFilter) { return "$($Source).Where(item => $propFilter)" }
            return "$($Source).Where(item => /* TODO: filter */ true)"
        }

        'ForEach-Object' {
            $body = Get-ScriptBlockArg -Params $params -Context $Context
            if ($body) {
                return "$($Source).Select(item => $body)"
            }
            # -MemberName pattern
            $memberName = Get-NamedArgValue -Params $params -Name 'MemberName'
            if ($memberName) {
                $csMember = Convert-PropertyName -Name $memberName
                return "$($Source).Select(item => item.$csMember)"
            }
            return "$($Source).Select(item => /* TODO: ForEach body */ item)"
        }

        'Sort-Object' {
            $prop = Get-FirstPositionalArg -Params $params
            if ($prop) {
                $csProp = Convert-PropertyName -Name $prop
                return "$($Source).OrderBy(item => item.$csProp)"
            }
            return "$($Source).OrderBy(item => item)"
        }

        'Select-Object' {
            $first = Get-NamedArgValue -Params $params -Name 'First'
            if ($first) { return "$($Source).Take($first)" }
            $last = Get-NamedArgValue -Params $params -Name 'Last'
            if ($last) { return "$($Source).TakeLast($last)" }
            $skip = Get-NamedArgValue -Params $params -Name 'Skip'
            if ($skip) { return "$($Source).Skip($skip)" }
            $expandProp = Get-NamedArgValue -Params $params -Name 'ExpandProperty'
            if ($expandProp) {
                $csProp = Convert-PropertyName -Name $expandProp
                return "$($Source).Select(item => item.$csProp)"
            }
            return "$Source /* Select-Object */"
        }

        'Measure-Object' {
            $sumProp = Get-NamedArgValue -Params $params -Name 'Sum'
            $avgProp = Get-NamedArgValue -Params $params -Name 'Average'
            $prop = Get-NamedArgValue -Params $params -Name 'Property'
            if ($sumProp -or ($params | Where-Object { $_.Name -eq 'Sum' -and $_.IsSwitch })) {
                if ($prop) {
                    $csProp = Convert-PropertyName -Name $prop
                    return "$($Source).Sum(item => item.$csProp)"
                }
                return "$($Source).Sum()"
            }
            if ($avgProp -or ($params | Where-Object { $_.Name -eq 'Average' -and $_.IsSwitch })) {
                if ($prop) {
                    $csProp = Convert-PropertyName -Name $prop
                    return "$($Source).Average(item => item.$csProp)"
                }
                return "$($Source).Average()"
            }
            return "$($Source).Count()"
        }

        'Group-Object' {
            $prop = Get-FirstPositionalArg -Params $params
            if ($prop) {
                $csProp = Convert-PropertyName -Name $prop
                return "$($Source).GroupBy(item => item.$csProp)"
            }
            return "$($Source).GroupBy(item => item)"
        }

        'Out-Null' {
            return $Source
        }

        default {
            $tag = Write-AiTag -TagName 'PIPELINE_COMPLEX' `
                -OriginalSource $Ast.Extent.Text `
                -AstTypeName 'CommandAst' `
                -Hint "Pipeline step '$cmdName' has no LINQ equivalent — convert manually" `
                -BestEffort "$Source /* | $cmdName ... */" `
                -Context $Context
            return $tag
        }
    }
}

function Get-CommandName {
    param([System.Management.Automation.Language.CommandAst]$Ast)
    if ($Ast.CommandElements.Count -gt 0) {
        return $Ast.CommandElements[0].Extent.Text
    }
    return ''
}

function Get-CommandParams {
    <#
    .SYNOPSIS
        Extracts command parameters into a structured list from CommandAst elements.
        Returns list of: @{ Name = '-ParamName' or $null; Value = <Ast>; IsSwitch = $bool }
    #>
    param([System.Management.Automation.Language.CommandAst]$Ast)

    $result = [System.Collections.ArrayList]::new()
    $elements = @($Ast.CommandElements)
    $i = 1  # skip command name at index 0

    while ($i -lt $elements.Count) {
        $elem = $elements[$i]

        if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
            $paramName = $elem.ParameterName
            if ($elem.Argument) {
                [void]$result.Add(@{ Name = $paramName; Value = $elem.Argument; IsSwitch = $false })
            }
            elseif (($i + 1) -lt $elements.Count -and $elements[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                $i++
                [void]$result.Add(@{ Name = $paramName; Value = $elements[$i]; IsSwitch = $false })
            }
            else {
                [void]$result.Add(@{ Name = $paramName; Value = $null; IsSwitch = $true })
            }
        }
        else {
            [void]$result.Add(@{ Name = $null; Value = $elem; IsSwitch = $false })
        }
        $i++
    }

    return @($result)
}

function Get-ScriptBlockArg {
    param([array]$Params, [hashtable]$Context)

    foreach ($p in $Params) {
        $scriptBlockAst = $null

        if ($null -eq $p.Name -and $null -ne $p.Value -and
            $p.Value -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            $scriptBlockAst = $p.Value.ScriptBlock
        }
        elseif ($p.Name -eq 'FilterScript' -and $null -ne $p.Value -and
            $p.Value -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
            $scriptBlockAst = $p.Value.ScriptBlock
        }

        if ($scriptBlockAst) {
            $body = Get-BodyStatements -Ast $scriptBlockAst
            if ($body.Count -eq 1) {
                return Convert-AstNode -Ast $body[0] -Context $Context
            }
            if ($body.Count -gt 1) {
                $parts = @()
                foreach ($stmt in $body) {
                    $converted = Convert-AstNode -Ast $stmt -Context $Context
                    $converted = $converted.Trim().TrimEnd(';').Trim()
                    if ($converted) { $parts += $converted }
                }
                return "{ $($parts -join '; ') }"
            }
        }
    }
    return $null
}

function Get-PropertyFilter {
    param([array]$Params, [hashtable]$Context)

    # Where-Object Property -Operator Value pattern
    $prop = $null; $op = $null; $val = $null
    foreach ($p in $Params) {
        if ($p.Name -eq 'Property' -and $p.Value) { $prop = $p.Value.Extent.Text }
        if ($p.Name -eq 'EQ' -and $p.Value)       { $op = '=='; $val = Convert-Expression -Ast $p.Value -Context $Context }
        if ($p.Name -eq 'NE' -and $p.Value)       { $op = '!='; $val = Convert-Expression -Ast $p.Value -Context $Context }
        if ($p.Name -eq 'GT' -and $p.Value)       { $op = '>'; $val = Convert-Expression -Ast $p.Value -Context $Context }
        if ($p.Name -eq 'LT' -and $p.Value)       { $op = '<'; $val = Convert-Expression -Ast $p.Value -Context $Context }
    }
    if ($prop -and $op -and $val) {
        $csProp = Convert-PropertyName -Name $prop
        return "item.$csProp $op $val"
    }

    # Positional: Where-Object Name -eq Value → elements[1]=prop elements[2]=-eq elements[3]=val
    $positionals = @($Params | Where-Object { $null -eq $_.Name })
    if ($positionals.Count -ge 1) {
        $prop = $positionals[0].Value.Extent.Text
        $csProp = Convert-PropertyName -Name $prop
        foreach ($p in $Params) {
            if ($p.Name -eq 'eq' -and $p.Value)  { return "item.$csProp == $(Convert-Expression -Ast $p.Value -Context $Context)" }
            if ($p.Name -eq 'ne' -and $p.Value)  { return "item.$csProp != $(Convert-Expression -Ast $p.Value -Context $Context)" }
            if ($p.Name -eq 'like' -and $p.Value) { return "item.$csProp.Contains($(Convert-Expression -Ast $p.Value -Context $Context))" }
            if ($p.Name -eq 'match' -and $p.Value) { return "Regex.IsMatch(item.$csProp, $(Convert-Expression -Ast $p.Value -Context $Context))" }
        }
    }

    return $null
}

function Get-NamedArgValue {
    param([array]$Params, [string]$Name)
    foreach ($p in $Params) {
        if ($p.Name -eq $Name -and $null -ne $p.Value) {
            return $p.Value.Extent.Text.Trim("'", '"')
        }
    }
    return $null
}

function Get-FirstPositionalArg {
    param([array]$Params)
    foreach ($p in $Params) {
        if ($null -eq $p.Name -and $null -ne $p.Value) {
            return $p.Value.Extent.Text.Trim("'", '"')
        }
    }
    return $null
}
