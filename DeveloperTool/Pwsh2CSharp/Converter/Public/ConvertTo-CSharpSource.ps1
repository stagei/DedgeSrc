function ConvertTo-CSharpSource {
    <#
    .SYNOPSIS
        Converts a PowerShell script file or code string to C# source code.

    .PARAMETER InputFile
        Path to a .ps1 file to convert.

    .PARAMETER InputCode
        PowerShell source code as a string.

    .PARAMETER ClassName
        Name for the generated C# class. Defaults to the script filename without extension.

    .PARAMETER Namespace
        C# namespace. Defaults to 'ConvertedScripts'.

    .OUTPUTS
        [string] The generated C# source code.

    .EXAMPLE
        ConvertTo-CSharpSource -InputFile .\MyScript.ps1

    .EXAMPLE
        ConvertTo-CSharpSource -InputCode 'param([string]$Name) Write-Host $Name' -ClassName 'Greeter'
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'File', Position = 0)]
        [string]$InputFile,

        [Parameter(Mandatory, ParameterSetName = 'Code')]
        [string]$InputCode,

        [string]$ClassName,

        [string]$Namespace = 'ConvertedScripts'
    )

    # Parse the input
    $tokens = $null
    $errors = $null

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $resolvedPath = (Resolve-Path -LiteralPath $InputFile -ErrorAction Stop).Path

        if (-not $ClassName) {
            $ClassName = [IO.Path]::GetFileNameWithoutExtension($resolvedPath) -replace '[^a-zA-Z0-9]', ''
        }

        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $resolvedPath,
            [ref]$tokens,
            [ref]$errors
        )
        $sourceFileName = [IO.Path]::GetFileName($resolvedPath)
    }
    else {
        if (-not $ClassName) { $ClassName = 'ConvertedScript' }

        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $InputCode,
            [ref]$tokens,
            [ref]$errors
        )
        $sourceFileName = "$ClassName.ps1"
    }

    if ($errors.Count -gt 0) {
        Write-Warning "Parser found $($errors.Count) error(s) in the source — conversion may be incomplete."
        foreach ($e in $errors) {
            Write-Warning "  Parse error: $($e.Message) at line $($e.Extent.StartLineNumber)"
        }
    }

    # SharedState holds mutable flags that must survive hashtable .Clone() across
    # nested converter calls. Since PSCustomObject is a reference type, all cloned
    # contexts share the same instance.
    $sharedState = [PSCustomObject]@{
        HasAsync = $false
        AiTags   = [System.Collections.ArrayList]::new()
    }

    # Build conversion context
    $context = @{
        ClassName      = $ClassName
        Namespace      = $Namespace
        SourceFileName = $sourceFileName
        IndentLevel    = 0
        IsTopLevel     = $true
        Usings         = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        DeclaredVars   = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        SharedState    = $sharedState
    }

    # Run the converter
    $csharp = Convert-AstNode -Ast $ast -Context $context

    # Append conversion summary if AI tags were emitted
    $aiTags = $sharedState.AiTags
    if ($aiTags.Count -gt 0) {
        $tagGroups = @{}
        foreach ($tag in $aiTags) {
            if (-not $tagGroups.ContainsKey($tag)) { $tagGroups[$tag] = 0 }
            $tagGroups[$tag]++
        }

        $summaryLines = [System.Text.StringBuilder]::new()
        [void]$summaryLines.AppendLine('')
        [void]$summaryLines.AppendLine('/* === CONVERSION SUMMARY ===')
        [void]$summaryLines.AppendLine(" * AI tags remaining: $($aiTags.Count)")
        foreach ($kv in $tagGroups.GetEnumerator() | Sort-Object Key) {
            [void]$summaryLines.AppendLine(" *   - $($kv.Value)x $($kv.Key)")
        }
        [void]$summaryLines.AppendLine(' */')

        $csharp += $summaryLines.ToString()
    }

    return $csharp
}
