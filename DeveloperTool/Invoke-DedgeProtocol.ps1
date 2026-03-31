<#
.SYNOPSIS
    Runs a Dedge AI protocol: loads a .protocol.json definition, fills the
    prompt template, calls Invoke-CursorAgent.ps1, validates the response,
    and writes output files.

.DESCRIPTION
    Protocol definitions live in AiProtocols/{name}.protocol.json alongside
    matching {name}.prompt.md templates.  Placeholders use {{Key}} syntax.

    The runner resolves Invoke-CursorAgent.ps1 from the DedgePsh tree,
    constructs the call with model/mode/output/context parameters from the
    protocol, then validates and persists the result.

.PARAMETER ProtocolName
    Base name of the protocol (e.g. "competitor-research").

.PARAMETER Placeholders
    Hashtable of key/value pairs injected into the prompt template.

.PARAMETER ProtocolsRoot
    Folder containing .protocol.json + .prompt.md files.
    Default: $PSScriptRoot\AiProtocols

.PARAMETER OutputRoot
    Base folder for relative output paths declared in the protocol.
    Default: $PSScriptRoot  (DeveloperTool root)

.PARAMETER OverwriteExisting
    Ignore the protocol's skipIfExists flag and regenerate outputs.

.PARAMETER DryRun
    Show what would happen without calling the agent or writing files.

.EXAMPLE
    .\Invoke-DedgeProtocol.ps1 -ProtocolName competitor-research `
        -Placeholders @{ ProductName = 'DbExplorer'; ProductDescription = '...'; ProductCategory = 'Commercial Product'; ProductStack = '.NET 10 WPF' }

.EXAMPLE
    .\Invoke-DedgeProtocol.ps1 -ProtocolName web-screenshot `
        -Placeholders @{ AppKey = 'AiDoc.WebNew'; Port = '18484'; UrlPaths = '/AiDocNew/scalar/v1,/AiDocNew/'; Project = 'C:\opt\src\AiDoc.WebNew\AiDoc.WebNew.csproj' } -OverwriteExisting
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProtocolName,

    [Parameter(Mandatory)]
    [hashtable]$Placeholders,

    [string]$ProtocolsRoot = (Join-Path $PSScriptRoot 'AiProtocols'),

    [string]$OutputRoot = $PSScriptRoot,

    [switch]$OverwriteExisting,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module GlobalFunctions -Force

# ═════════════════════════════════════════════════════════════════════════════
#  Resolve Invoke-CursorAgent.ps1
# ═════════════════════════════════════════════════════════════════════════════

$agentScript = Join-Path $PSScriptRoot 'DedgePsh\Cursor-AgentCLI\Invoke-CursorAgent.ps1'
if (-not (Test-Path -LiteralPath $agentScript)) {
    $agentScript = 'C:\opt\src\FKMenyPSH\DevTools\CodingTools\Cursor-AgentCLI\Invoke-CursorAgent.ps1'
}
if (-not (Test-Path -LiteralPath $agentScript)) {
    $agentScript = Join-Path $env:OptPath 'FkPshApps\Cursor-AgentCLI\Invoke-CursorAgent.ps1'
}
if (-not (Test-Path -LiteralPath $agentScript)) {
    throw "Invoke-CursorAgent.ps1 not found. Ensure Cursor-AgentCLI is available."
}
Write-LogMessage "Agent CLI: $($agentScript)" -Level DEBUG

# ═════════════════════════════════════════════════════════════════════════════
#  Load protocol definition
# ═════════════════════════════════════════════════════════════════════════════

$protocolPath = Join-Path $ProtocolsRoot "$($ProtocolName).protocol.json"
$templatePath = Join-Path $ProtocolsRoot "$($ProtocolName).prompt.md"

if (-not (Test-Path -LiteralPath $protocolPath)) {
    throw "Protocol definition not found: $($protocolPath)"
}
if (-not (Test-Path -LiteralPath $templatePath)) {
    throw "Prompt template not found: $($templatePath)"
}

$protocol = Get-Content -LiteralPath $protocolPath -Raw -Encoding UTF8 | ConvertFrom-Json
$promptTemplate = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8

Write-LogMessage "Protocol: $($protocol.id) — $($protocol.description)" -Level INFO

# ═════════════════════════════════════════════════════════════════════════════
#  Resolve output paths and check skipIfExists
# ═════════════════════════════════════════════════════════════════════════════

function Expand-Placeholders {
    param([string]$Text, [hashtable]$Tokens)
    foreach ($key in $Tokens.Keys) {
        $Text = $Text -replace [regex]::Escape("{{$key}}"), $Tokens[$key]
    }
    return $Text
}

$outputPaths = @{}
if ($protocol.output) {
    foreach ($prop in $protocol.output.PSObject.Properties) {
        if ($prop.Name -eq 'skipIfExists') { continue }
        $resolved = Expand-Placeholders -Text $prop.Value -Tokens $Placeholders
        if (-not [System.IO.Path]::IsPathRooted($resolved)) {
            $resolved = Join-Path $OutputRoot $resolved
        }
        $outputPaths[$prop.Name] = $resolved
    }
}

$skipIfExists = ($protocol.output.skipIfExists -eq $true) -and (-not $OverwriteExisting)
if ($skipIfExists) {
    $allExist = $true
    foreach ($p in $outputPaths.Values) {
        if (-not (Test-Path -LiteralPath $p)) { $allExist = $false; break }
    }
    if ($allExist -and $outputPaths.Count -gt 0) {
        Write-LogMessage "SKIP $($ProtocolName) for $($Placeholders['ProductName'] ?? $ProtocolName): all outputs exist" -Level INFO
        return [PSCustomObject]@{
            Status      = 'Skipped'
            Protocol    = $ProtocolName
            ProductName = $Placeholders['ProductName']
            OutputPaths = $outputPaths
            DurationMs  = 0
            SessionId   = $null
            IsError     = $false
            Message     = 'All output files already exist (skipIfExists).'
        }
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  Fill prompt template
# ═════════════════════════════════════════════════════════════════════════════

$filledPrompt = Expand-Placeholders -Text $promptTemplate -Tokens $Placeholders

# ═════════════════════════════════════════════════════════════════════════════
#  DryRun early exit
# ═════════════════════════════════════════════════════════════════════════════

if ($DryRun) {
    Write-LogMessage "[DryRun] Would call agent for protocol $($ProtocolName)" -Level WARN
    Write-LogMessage "[DryRun] Model: $($protocol.model)  Mode: $($protocol.mode)  Format: $($protocol.outputFormat)" -Level WARN
    foreach ($k in $outputPaths.Keys) {
        Write-LogMessage "[DryRun] Output $($k): $($outputPaths[$k])" -Level WARN
    }
    return [PSCustomObject]@{
        Status      = 'DryRun'
        Protocol    = $ProtocolName
        ProductName = $Placeholders['ProductName']
        OutputPaths = $outputPaths
        DurationMs  = 0
        SessionId   = $null
        IsError     = $false
        Message     = 'Dry run — no agent call made.'
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  Build agent call arguments
# ═════════════════════════════════════════════════════════════════════════════

$agentArgs = @{
    Prompt       = $filledPrompt
    Model        = ($protocol.model ?? 'claude-sonnet-4-20250514')
    OutputFormat = ($protocol.outputFormat ?? 'json')
}

if ($protocol.mode -and $protocol.mode -ne 'agent') {
    $agentArgs.Mode = $protocol.mode
}

if ($protocol.force -eq $true) {
    $agentArgs.Force = $true
}

if ($protocol.noMcp -eq $true) {
    $agentArgs.NoMcp = $true
}

if ($protocol.contextFiles -and $protocol.contextFiles.Count -gt 0) {
    $resolved = @()
    foreach ($cf in $protocol.contextFiles) {
        $expanded = Expand-Placeholders -Text $cf -Tokens $Placeholders
        if (-not [System.IO.Path]::IsPathRooted($expanded)) {
            $expanded = Join-Path $OutputRoot $expanded
        }
        if (Test-Path -LiteralPath $expanded) { $resolved += $expanded }
    }
    if ($resolved.Count -gt 0) { $agentArgs.FilePaths = $resolved }
}

if ($protocol.contextFolder) {
    $folder = Expand-Placeholders -Text $protocol.contextFolder -Tokens $Placeholders
    if (-not [System.IO.Path]::IsPathRooted($folder)) {
        $folder = Join-Path $OutputRoot $folder
    }
    if (Test-Path -LiteralPath $folder) {
        $agentArgs.FolderPath = $folder
    }
}

if ($protocol.workspacePath) {
    $ws = Expand-Placeholders -Text $protocol.workspacePath -Tokens $Placeholders
    if (-not [System.IO.Path]::IsPathRooted($ws)) {
        $ws = Join-Path $OutputRoot $ws
    }
    if (Test-Path -LiteralPath $ws) {
        $agentArgs.WorkspacePath = $ws
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  Invoke the agent
# ═════════════════════════════════════════════════════════════════════════════

Write-LogMessage "Calling agent: protocol=$($ProtocolName) model=$($agentArgs.Model) format=$($agentArgs.OutputFormat)" -Level INFO
$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $result = & $agentScript @agentArgs
} catch {
    $sw.Stop()
    Write-LogMessage "Agent call failed: $($_.Exception.Message)" -Level ERROR
    return [PSCustomObject]@{
        Status      = 'Error'
        Protocol    = $ProtocolName
        ProductName = $Placeholders['ProductName']
        OutputPaths = $outputPaths
        DurationMs  = $sw.ElapsedMilliseconds
        SessionId   = $null
        IsError     = $true
        Message     = $_.Exception.Message
    }
}
$sw.Stop()

$responseText = if ($result -and $result.Result) { $result.Result } elseif ($result -is [string]) { $result } else { '' }
$sessionId    = if ($result -and $result.SessionId) { $result.SessionId } else { $null }
$durationMs   = if ($result -and $result.DurationMs) { $result.DurationMs } else { $sw.ElapsedMilliseconds }

if (-not $responseText) {
    Write-LogMessage "Empty response from agent for $($ProtocolName)" -Level ERROR
    return [PSCustomObject]@{
        Status      = 'Error'
        Protocol    = $ProtocolName
        ProductName = $Placeholders['ProductName']
        OutputPaths = $outputPaths
        DurationMs  = $durationMs
        SessionId   = $sessionId
        IsError     = $true
        Message     = 'Agent returned empty response.'
    }
}

Write-LogMessage "Agent responded in $($durationMs)ms (session: $($sessionId))" -Level INFO

# ═════════════════════════════════════════════════════════════════════════════
#  Parse and validate response
# ═════════════════════════════════════════════════════════════════════════════

$parsedJson = $null
if ($protocol.validation -and $protocol.validation.responseFormat -eq 'json') {
    $jsonText = $responseText.Trim()
    $jsonText = $jsonText -replace '```json\s*', '' -replace '```\s*$', ''
    $jsonText = $jsonText.Trim()

    try {
        $parsedJson = $jsonText | ConvertFrom-Json
    } catch {
        Write-LogMessage "JSON parse failed for $($ProtocolName): $($_.Exception.Message)" -Level WARN
    }

    if ($parsedJson -and $protocol.validation.requiredFields) {
        foreach ($field in $protocol.validation.requiredFields) {
            if ($null -eq $parsedJson.$field) {
                Write-LogMessage "Validation: missing required field '$($field)' in $($ProtocolName) response" -Level WARN
            }
        }
    }

    if ($parsedJson -and $protocol.validation.minArrayLength) {
        foreach ($prop in $protocol.validation.minArrayLength.PSObject.Properties) {
            $arr = $parsedJson.$($prop.Name)
            if ($arr -and $arr.Count -lt $prop.Value) {
                Write-LogMessage "Validation: '$($prop.Name)' has $($arr.Count) items, expected >= $($prop.Value)" -Level WARN
            }
        }
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  Helper: build competitor markdown from parsed JSON
# ═════════════════════════════════════════════════════════════════════════════

function Convert-JsonToCompetitorMarkdown {
    param([PSCustomObject]$Json, [string]$ProductName)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# $($ProductName) — Competitor Analysis")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Product:** $($Json.product)")
    [void]$sb.AppendLine("**Category:** $($Json.category)")
    [void]$sb.AppendLine("**Research Date:** $($Json.searchDate)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("## Competitor Summary Table")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("| # | Name | URL | Pricing |")
    [void]$sb.AppendLine("|---|------|-----|---------|")

    $i = 0
    foreach ($c in $Json.competitors) {
        $i++
        [void]$sb.AppendLine("| $($i) | $($c.name) | $($c.url) | $($c.pricing) |")
    }

    [void]$sb.AppendLine()
    [void]$sb.AppendLine("## Detailed Competitor Profiles")
    [void]$sb.AppendLine()

    $i = 0
    foreach ($c in $Json.competitors) {
        $i++
        [void]$sb.AppendLine("### $($i). $($c.name)")
        [void]$sb.AppendLine("**URL:** $($c.url)")
        [void]$sb.AppendLine("**Pricing:** $($c.pricing)")
        [void]$sb.AppendLine($c.notes)
        [void]$sb.AppendLine("**Key difference from $($ProductName):** $($c.keyDifference)")
        [void]$sb.AppendLine()
    }

    return $sb.ToString()
}

# ═════════════════════════════════════════════════════════════════════════════
#  Write output files
# ═════════════════════════════════════════════════════════════════════════════

foreach ($key in $outputPaths.Keys) {
    $outPath = $outputPaths[$key]
    $dir = Split-Path $outPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if ($key -eq 'jsonPath' -and $parsedJson) {
        $parsedJson | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outPath -Encoding UTF8
        Write-LogMessage "Wrote JSON: $($outPath)" -Level INFO
    } elseif ($key -eq 'markdownPath') {
        if ($protocol.output.markdownFromJson -eq $true -and $parsedJson) {
            $mdContent = Convert-JsonToCompetitorMarkdown -Json $parsedJson -ProductName ($Placeholders['ProductName'] ?? $ProtocolName)
            $mdContent | Set-Content -LiteralPath $outPath -Encoding UTF8
        } else {
            $responseText | Set-Content -LiteralPath $outPath -Encoding UTF8
        }
        Write-LogMessage "Wrote MD: $($outPath)" -Level INFO
    } elseif ($key -match 'Path$') {
        $responseText | Set-Content -LiteralPath $outPath -Encoding UTF8
        Write-LogMessage "Wrote output: $($outPath)" -Level INFO
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  Return structured result
# ═════════════════════════════════════════════════════════════════════════════

return [PSCustomObject]@{
    Status      = 'OK'
    Protocol    = $ProtocolName
    ProductName = $Placeholders['ProductName']
    OutputPaths = $outputPaths
    DurationMs  = $durationMs
    SessionId   = $sessionId
    IsError     = $false
    Message     = "Protocol $($ProtocolName) completed successfully."
    ParsedJson  = $parsedJson
}
