#!/usr/bin/env pwsh
#Requires -Version 7
<#
.SYNOPSIS
    Post-conversion cleanup of mechanically converted C# using Cursor Agent CLI.

.DESCRIPTION
    Takes a raw .cs file produced by the AST converter, the original .ps1 source,
    and runs the Cursor Agent CLI in --force mode to:
      - Fix compilation errors and missing types
      - Apply C# naming conventions (PascalCase, camelCase, _field)
      - Replace dynamic/object with concrete types where inferable
      - Convert cmdlet stubs to real .NET API calls
      - Apply DB2 ODBC→IBM.Data.Db2 conversions
      - Add using statements, XML docs, async/await
      - Refactor into classes and methods

.PARAMETER RawCsPath
    Path to the mechanically converted .cs file.

.PARAMETER OriginalPs1Path
    Path to the original PowerShell source (for intent/context).

.PARAMETER OutputCsPath
    Where to write the cleaned C# result.

.PARAMETER TargetProjectPath
    Optional .csproj directory. When set, the Agent CLI uses this as
    workspace and can edit the file in place.

.PARAMETER Model
    Cursor Agent CLI model. Default: claude-sonnet-4-20250514.

.PARAMETER PassNumber
    Current pass number (1-based). Affects prompt focus.

.PARAMETER TotalPasses
    Total planned passes. Affects prompt focus.

.EXAMPLE
    .\Invoke-PostConversionCleanup.ps1 -RawCsPath .\raw\Script.cs -OriginalPs1Path .\Script.ps1 -OutputCsPath .\cleaned\Script.cs
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RawCsPath,

    [Parameter(Mandatory)]
    [string]$OriginalPs1Path,

    [Parameter(Mandatory)]
    [string]$OutputCsPath,

    [string]$TargetProjectPath,

    [string]$Model = 'claude-sonnet-4-20250514',

    [int]$PassNumber = 1,

    [int]$TotalPasses = 2,

    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force
Import-Module (Join-Path $PSScriptRoot 'Converter\PwshToCSharpConverter.psm1') -Force

# Load project config for AI provider selection
$projectConfig = @{}
if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
    $projectConfig = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
}
$aiProvider = if ($projectConfig.aiProvider) { $projectConfig.aiProvider } else { 'cursor-cli' }

# Resolve Cursor Agent CLI path (needed for cursor-cli provider)
$agentScript = 'C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-AgentCLI\Invoke-CursorAgent.ps1'
if (-not (Test-Path -LiteralPath $agentScript)) {
    $agentScript = Join-Path $env:OptPath 'DedgePshApps\Cursor-AgentCLI\Invoke-CursorAgent.ps1'
}
if ($aiProvider -eq 'cursor-cli' -and -not (Test-Path -LiteralPath $agentScript)) {
    if ($aiProvider -eq 'cursor-cli') {
        Write-LogMessage "Cursor Agent CLI not found. Skipping cleanup." -Level WARN
        Copy-Item -LiteralPath $RawCsPath -Destination $OutputCsPath -Force
        return
    }
}

$rulesPath = Join-Path $PSScriptRoot '.cursor\rules'
$promptsDir = Join-Path $PSScriptRoot 'ConversionPrompts'
$cleanupTemplatePath = Join-Path $promptsDir 'cleanup-prompt-template.md'
$validationTemplatePath = Join-Path $promptsDir 'validation-prompt-template.md'

$rawCs = Get-Content -LiteralPath $RawCsPath -Raw -Encoding UTF8
$originalPs1 = Get-Content -LiteralPath $OriginalPs1Path -Raw -Encoding UTF8
$baseName = [IO.Path]::GetFileNameWithoutExtension($RawCsPath)

# Truncate very large files for prompt size management
$maxPromptChars = 200000
$csForPrompt = if ($rawCs.Length -gt $maxPromptChars) {
    $rawCs.Substring(0, $maxPromptChars) + "`n// ... TRUNCATED ($(($rawCs.Length - $maxPromptChars)) more chars) ..."
} else { $rawCs }

$ps1ForPrompt = if ($originalPs1.Length -gt $maxPromptChars) {
    $originalPs1.Substring(0, $maxPromptChars) + "`n# ... TRUNCATED ($(($originalPs1.Length - $maxPromptChars)) more chars) ..."
} else { $originalPs1 }

# Build the prompt based on pass number
$promptTemplate = if (($PassNumber -eq 1) -and (Test-Path -LiteralPath $cleanupTemplatePath)) {
    Get-Content -LiteralPath $cleanupTemplatePath -Raw -Encoding UTF8
} elseif (($PassNumber -gt 1) -and (Test-Path -LiteralPath $validationTemplatePath)) {
    Get-Content -LiteralPath $validationTemplatePath -Raw -Encoding UTF8
} else {
    $null
}

if ($PassNumber -eq 1) {
    $prompt = @"
You are converting PowerShell 7 code to C# (.NET 10). Below is the original PowerShell source and a mechanically converted C# version. The mechanical conversion is rough and needs significant cleanup.

YOUR TASK (Pass $($PassNumber) of $($TotalPasses) — Fix Compilation and Types):
1. Fix all compilation errors in the C# code
2. Replace all dynamic/object types with concrete types where inferable from context
3. Replace PowerShell cmdlet stubs with real .NET API calls (see mapping rules below)
4. Add proper using statements
5. Apply C# naming: PascalCase for methods/properties, camelCase for locals, _camelCase for fields
6. Convert synchronous code to async/await where appropriate
7. If the PowerShell uses System.Data.Odbc for DB2, convert to IBM.Data.Db2 (DB2Connection, DB2Command, DB2DataReader)
8. If the PowerShell uses Invoke-RestMethod/Invoke-WebRequest, convert to HttpClient
9. Add XML documentation on public members
10. Output the complete corrected C# file

KEY MAPPINGS:
- Write-LogMessage "X" -Level INFO  →  _logger.Info("X")  (using NLog)
- Get-Content -Raw  →  File.ReadAllText / File.ReadAllTextAsync
- ConvertFrom-Json  →  JsonSerializer.Deserialize<T>
- ConvertTo-Json  →  JsonSerializer.Serialize
- System.Data.Odbc.OdbcConnection("DSN=X")  →  new DB2Connection("Database=X;")  (using IBM.Data.Db2)
- Invoke-RestMethod  →  HttpClient.GetFromJsonAsync / PostAsJsonAsync
- `$script:var`  →  private field `_var`
- [ordered]@{}  →  Dictionary or typed record class

Write the file to: $($OutputCsPath)

=== ORIGINAL POWERSHELL SOURCE ($($baseName).ps1) ===
$ps1ForPrompt

=== MECHANICALLY CONVERTED C# (needs cleanup) ===
$csForPrompt
"@
} else {
    $prompt = @"
You are refactoring a C# file that was converted from PowerShell. The previous pass fixed basic compilation issues. Now refactor for quality.

YOUR TASK (Pass $($PassNumber) of $($TotalPasses) — Refactor and Structure):
1. Break monolithic code into well-named classes and methods (single responsibility)
2. Extract configuration into an Options/Settings class bindable from appsettings.json
3. Apply dependency injection patterns (interfaces for services, constructor injection)
4. Ensure all DB2 access uses IBM.Data.Db2 (DB2Connection, DB2Command) not System.Data.Odbc
5. Ensure all HTTP calls use IHttpClientFactory / named HttpClient
6. Apply proper error handling: DB2Exception specifically for DB2, HttpRequestException for HTTP
7. Verify every function from the original PowerShell has a C# equivalent
8. Add NLog logging matching the original Write-LogMessage calls
9. Ensure the file compiles (no missing types, no unresolved references)
10. Output the complete refactored C# file

Write the file to: $($OutputCsPath)

=== ORIGINAL POWERSHELL SOURCE (for reference) ===
$ps1ForPrompt

=== CURRENT C# CODE (needs refactoring) ===
$csForPrompt
"@
}

if ($promptTemplate) {
    $prompt = $promptTemplate `
        -replace '\{\{PASS_NUMBER\}\}', $PassNumber `
        -replace '\{\{TOTAL_PASSES\}\}', $TotalPasses `
        -replace '\{\{BASE_NAME\}\}', $baseName `
        -replace '\{\{OUTPUT_CS_PATH\}\}', $OutputCsPath `
        -replace '\{\{PS1_SOURCE\}\}', $ps1ForPrompt `
        -replace '\{\{CS_SOURCE\}\}', $csForPrompt
}

# Build Agent CLI arguments
$agentArgs = @{
    Prompt       = $prompt
    Model        = $Model
    Force        = $true
    OutputFormat = 'text'
    FilePaths    = @($RawCsPath, $OriginalPs1Path)
}

if ($TargetProjectPath -and (Test-Path -LiteralPath $TargetProjectPath)) {
    $agentArgs.WorkspacePath = $TargetProjectPath
}

if (Test-Path -LiteralPath $rulesPath) {
    $agentArgs.RulesPath = (Split-Path $rulesPath -Parent)
}

Write-LogMessage "    Invoking AI cleanup (provider: $($aiProvider), pass $($PassNumber), model: $($Model))..." -Level INFO

try {
    $aiResponse = $null

    if ($aiProvider -eq 'ollama') {
        $aiResponse = Invoke-AiCompletion -Prompt $prompt -Config $projectConfig
    }
    else {
        # Cursor CLI path
        $result = & $agentScript @agentArgs

        if ($result -and $result.Result) {
            if (Test-Path -LiteralPath $OutputCsPath) {
                Write-LogMessage "    Agent wrote output to $($OutputCsPath)" -Level INFO
                return
            }
            $aiResponse = $result.Result
        }
    }

    if ($aiResponse) {
        $csContent = $aiResponse
        # Extract code block if wrapped in markdown fences
        if ($csContent -match '(?s)```csharp\s*\n(.+?)\n```') {
            $csContent = $Matches[1]
        } elseif ($csContent -match '(?s)```\s*\n(.+?)\n```') {
            $csContent = $Matches[1]
        }
        Set-Content -LiteralPath $OutputCsPath -Value $csContent -Encoding UTF8
        Write-LogMessage "    AI cleanup produced $($csContent.Length) chars" -Level INFO
    } else {
        Write-LogMessage "    AI returned no result, copying raw input" -Level WARN
        Copy-Item -LiteralPath $RawCsPath -Destination $OutputCsPath -Force
    }
} catch {
    Write-LogMessage "    AI cleanup error: $($_.Exception.Message)" -Level WARN
    Copy-Item -LiteralPath $RawCsPath -Destination $OutputCsPath -Force
}
