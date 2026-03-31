function Convert-ParamBlock {
    <#
    .SYNOPSIS
        Converts a ParamBlockAst to C# method/constructor parameters.
    .OUTPUTS
        Hashtable with keys: params (string), paramList (array of hashtable with name/type/default)
    #>
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ParamBlockAst]$Ast,
        [hashtable]$Context
    )

    $paramList = [System.Collections.ArrayList]::new()

    foreach ($p in $Ast.Parameters) {
        $info = Convert-SingleParameter -Ast $p -Context $Context
        [void]$paramList.Add($info)
    }

    $paramStrings = @()
    foreach ($info in $paramList) {
        $s = "$($info.Type) $($info.Name)"
        if ($null -ne $info.Default -and $info.Default -ne '') {
            $s += " = $($info.Default)"
        }
        $paramStrings += $s
    }

    return @{
        Params    = ($paramStrings -join ', ')
        ParamList = @($paramList)
    }
}

function Convert-SingleParameter {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.ParameterAst]$Ast,
        [hashtable]$Context
    )

    $varName = $Ast.Name.VariablePath.UserPath
    $csName  = Convert-VariableName -Name $varName

    # Resolve type from type constraint attributes
    $csType = 'object'
    foreach ($attr in $Ast.Attributes) {
        if ($attr -is [System.Management.Automation.Language.TypeConstraintAst]) {
            $csType = Resolve-TypeName -PsTypeName $attr.TypeName.FullName
            break
        }
    }

    # Check for [switch] → bool
    $isSwitch = $false
    foreach ($attr in $Ast.Attributes) {
        if ($attr -is [System.Management.Automation.Language.TypeConstraintAst]) {
            $tn = $attr.TypeName.FullName.ToLowerInvariant()
            if ($tn -eq 'switch' -or $tn -eq 'switchparameter') {
                $csType   = 'bool'
                $isSwitch = $true
            }
        }
    }

    # Default value
    $csDefault = $null
    if ($Ast.DefaultValue) {
        $csDefault = Convert-Expression -Ast $Ast.DefaultValue -Context $Context
    }
    elseif ($isSwitch) {
        $csDefault = 'false'
    }

    # Check for [Parameter(Mandatory)] to know if we should skip default
    $isMandatory = $false
    foreach ($attr in $Ast.Attributes) {
        if ($attr -is [System.Management.Automation.Language.AttributeAst]) {
            if ($attr.TypeName.Name -eq 'Parameter') {
                foreach ($na in $attr.NamedArguments) {
                    if ($na.ArgumentName -eq 'Mandatory') {
                        $isMandatory = $true
                    }
                }
            }
        }
    }

    return @{
        Name        = $csName
        Type        = $csType
        Default     = $csDefault
        IsMandatory = $isMandatory
        IsSwitch    = $isSwitch
        OriginalName = $varName
    }
}
