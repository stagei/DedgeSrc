function Write-AiTag {
    <#
    .SYNOPSIS
        Emits a structured AI tag comment block for patterns the mechanical
        converter cannot handle. The AI cleanup pass resolves these tags.
    .OUTPUTS
        [string] A C# comment block with the AI tag and optional best-effort code.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$TagName,

        [Parameter(Mandatory)]
        [string]$OriginalSource,

        [string]$AstTypeName = '',

        [string]$Hint = '',

        [string]$BestEffort = '',

        [hashtable]$Context
    )

    if ($Context -and $Context.SharedState) {
        [void]$Context.SharedState.AiTags.Add($TagName)
    }

    $src = $OriginalSource -replace '\*/', '* /'
    if ($src.Length -gt 500) { $src = $src.Substring(0, 500) + '...' }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("/* AI:$TagName")
    [void]$sb.AppendLine(" * Source: $src")
    if ($AstTypeName) {
        [void]$sb.AppendLine(" * AstType: $AstTypeName")
    }
    if ($Hint) {
        [void]$sb.AppendLine(" * Hint: $Hint")
    }
    [void]$sb.Append(' */')

    if ($BestEffort) {
        [void]$sb.AppendLine()
        [void]$sb.Append($BestEffort)
    }

    return $sb.ToString()
}
