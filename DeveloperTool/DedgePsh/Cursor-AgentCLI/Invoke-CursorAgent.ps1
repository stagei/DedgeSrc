<#
.SYNOPSIS
    Invokes the Cursor Agent CLI programmatically from PowerShell.

.DESCRIPTION
    A full-featured wrapper for the Cursor Agent CLI in headless mode.
    Supports folder-as-context (workspace search), strict file arrays,
    automatic MCP server detection (RAG + query), model selection,
    and structured JSON output.

    Context modes:
    - FolderPath  : The agent gets --workspace access to browse/search the folder
    - FilePaths   : Files are embedded directly into the prompt (strict context)
    - EmbedFolder : All matching files in the folder are embedded (strict context)
    You can combine FilePaths + FolderPath (files embedded, folder as workspace).

    MCP behaviour (default: auto):
    - Auto-reads ~/.cursor/mcp.json to discover MCP servers
    - Categorises servers as RAG (documentation search) or Query (database)
    - Enables unapproved servers and passes --approve-mcps
    - Injects a brief MCP-awareness block into the prompt so the model
      knows which tools exist and when to use them
    - Suppress with -NoMcp

.PARAMETER Prompt
    The question or instruction for the model.

.PARAMETER Model
    Which model to use. Default: "composer-2".
    Run with -ListModels to see all available models.

.PARAMETER FilePaths
    One or more file paths whose content is embedded directly in the prompt.
    The model sees ONLY these files plus anything in FolderPath (if set).
    This is "strict context" — the agent cannot read other files.

.PARAMETER FolderPath
    A folder the agent can browse and search via its built-in tools (Read,
    Grep, Glob). Passed as --workspace to the CLI. The agent decides which
    files to read based on the prompt.

.PARAMETER FolderFilter
    Glob filter for -EmbedFolder (e.g. "*.ps1", "*.cs"). Default: "*".
    Only used when -EmbedFolder is set.

.PARAMETER FolderMaxFiles
    Maximum number of files to embed from -FolderPath when -EmbedFolder is
    set. Default: 50. Prevents token overflow on large directories.

.PARAMETER FolderMaxChars
    Maximum total characters to embed from folder files. Default: 500000.
    Files are added until this budget is exhausted.

.PARAMETER EmbedFolder
    When set together with -FolderPath, all matching files are embedded
    directly in the prompt (strict context) instead of using --workspace.

.PARAMETER WorkspacePath
    Explicit --workspace override. If FolderPath is set and EmbedFolder is
    not, FolderPath is used as workspace automatically.

.PARAMETER Mode
    Agent mode: "ask" (read-only, default) or "plan" (planning, no edits).
    Omit for full agent mode (can edit files and run commands).

.PARAMETER OutputFormat
    Output format: "json" (default, structured), "text" (final answer only),
    "stream-json" (NDJSON with events).

.PARAMETER Force
    Allow the agent to modify files and run commands without confirmation.

.PARAMETER NoMcp
    Suppress automatic MCP server detection and approval.

.PARAMETER McpServers
    Explicit list of MCP server names to enable (overrides auto-detection).

.PARAMETER RulesPath
    Path to a folder containing .cursor/rules/*.mdc files. The script reads
    all .mdc files and injects them as system-level instructions in the prompt.
    If omitted, auto-detects from FolderPath, WorkspacePath, or $PWD.

.PARAMETER NoRules
    Suppress automatic rule injection. By default, rules are loaded if a
    .cursor/rules/ folder is found in the workspace hierarchy.

.PARAMETER SessionId
    Resume a previous conversation by session ID. The model sees the full
    conversation history from that session. Combine with -Prompt for a
    follow-up question.

.PARAMETER Continue
    Resume the most recent session (equivalent to --continue).

.PARAMETER ListModels
    List all available models and exit.

.PARAMETER ListMcp
    List all configured MCP servers from ~/.cursor/mcp.json and exit.
    Shows name, category (rag/query/other), and transport (URL or command).

.PARAMETER ListRules
    List all rules that would be injected from the resolved rules path and exit.
    Useful to verify which .mdc files are picked up.

.PARAMETER ListSessions
    List previous chat sessions and exit.

.EXAMPLE
    # Simple question
    .\Invoke-CursorAgent.ps1 -Prompt "What is INNER JOIN vs LEFT JOIN?"

.EXAMPLE
    # Analyse specific files (strict context — model sees only these)
    .\Invoke-CursorAgent.ps1 -Prompt "Summarise these scripts" `
        -FilePaths "C:\opt\src\Script1.ps1","C:\opt\src\Script2.ps1"

.EXAMPLE
    # Let the agent search an entire project folder
    .\Invoke-CursorAgent.ps1 -Prompt "List all API endpoints" `
        -FolderPath "C:\opt\src\MyProject"

.EXAMPLE
    # Embed all .cs files from a folder as strict context
    .\Invoke-CursorAgent.ps1 -Prompt "Find security issues" `
        -FolderPath "C:\opt\src\MyProject\Controllers" `
        -EmbedFolder -FolderFilter "*.cs"

.EXAMPLE
    # Use a specific model, with MCP RAG servers for documentation
    .\Invoke-CursorAgent.ps1 -Prompt "Explain SQL30082N reason code 36" `
        -Model "claude-4.5-sonnet"

.EXAMPLE
    # Suppress MCP, text output
    .\Invoke-CursorAgent.ps1 -Prompt "Write a haiku about PowerShell" `
        -OutputFormat text -NoMcp
#>
[CmdletBinding(DefaultParameterSetName = 'Query')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Query')]
    [string]$Prompt,

    [string]$Model = 'composer-2',

    [string[]]$FilePaths,

    [string]$FolderPath,

    [string]$FolderFilter = '*',

    [int]$FolderMaxFiles = 50,

    [int]$FolderMaxChars = 500000,

    [switch]$EmbedFolder,

    [string]$WorkspacePath,

    [ValidateSet('ask', 'plan')]
    [string]$Mode = 'ask',

    [ValidateSet('json', 'text', 'stream-json')]
    [string]$OutputFormat = 'json',

    [switch]$Force,

    [switch]$NoMcp,

    [string[]]$McpServers,

    [string]$RulesPath,

    [switch]$NoRules,

    [string]$SessionId,

    [switch]$Continue,

    [Parameter(ParameterSetName = 'ListModels')]
    [switch]$ListModels,

    [Parameter(ParameterSetName = 'ListMcp')]
    [switch]$ListMcp,

    [Parameter(ParameterSetName = 'ListRules')]
    [switch]$ListRules,

    [Parameter(ParameterSetName = 'ListSessions')]
    [switch]$ListSessions
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ════════════════════════════════════════════════════════════════════════════════
# Module imports and data folder setup
# ════════════════════════════════════════════════════════════════════════════════

Import-Module GlobalFunctions -Force
Set-OverrideAppDataFolder -Path (Join-Path $env:OptPath 'data\Cursor-AgentCLI')
$script:AppDataPath = Get-ApplicationDataPath
$script:SessionsFolder = Join-Path $script:AppDataPath 'sessions'
if (-not (Test-Path $script:SessionsFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $script:SessionsFolder -Force | Out-Null
}
Write-LogMessage "Invoke-CursorAgent started — Prompt: $(if ($Prompt) { $Prompt.Substring(0, [Math]::Min(100, $Prompt.Length)) } else { '(none)' })" -Level INFO

# ════════════════════════════════════════════════════════════════════════════════
# Encoding helpers: all text in/out of this script is UTF-8
# ════════════════════════════════════════════════════════════════════════════════

function Read-FileContentAsUtf8 {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { return '' }

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }

    $utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        return $utf8Strict.GetString($bytes)
    }
    catch [System.Text.DecoderFallbackException] {
        return [System.Text.Encoding]::GetEncoding(1252).GetString($bytes)
    }
}

function Repair-NorwegianBytes {
    <#
    .SYNOPSIS
        Scans a byte array for bare ANSI-1252 Norwegian characters (æøåÆØÅ)
        that are NOT part of a valid UTF-8 multi-byte sequence and replaces
        them with the correct UTF-8 byte pairs.
    #>
    param([byte[]]$Bytes)
    if (-not $Bytes -or $Bytes.Length -eq 0) { return $Bytes }

    # cp1252 single byte  →  UTF-8 two-byte equivalent
    #   Å 0xC5 → C3 85    å 0xE5 → C3 A5
    #   Æ 0xC6 → C3 86    æ 0xE6 → C3 A6
    #   Ø 0xD8 → C3 98    ø 0xF8 → C3 B8
    $map = @{
        0xC5 = [byte[]]@(0xC3, 0x85)
        0xC6 = [byte[]]@(0xC3, 0x86)
        0xD8 = [byte[]]@(0xC3, 0x98)
        0xE5 = [byte[]]@(0xC3, 0xA5)
        0xE6 = [byte[]]@(0xC3, 0xA6)
        0xF8 = [byte[]]@(0xC3, 0xB8)
    }
    $targets = [System.Collections.Generic.HashSet[byte]]::new([byte[]]@(0xC5,0xC6,0xD8,0xE5,0xE6,0xF8))

    $out = [System.Collections.Generic.List[byte]]::new($Bytes.Length + 64)
    $i = 0
    while ($i -lt $Bytes.Length) {
        $b = $Bytes[$i]

        if ($targets.Contains($b)) {
            $isUtf8 = $false

            # 0xC5, 0xC6, 0xD8 are in the 2-byte lead range (C2-DF):
            # valid only if next byte is a continuation byte (10xxxxxx)
            if ($b -le 0xDF) {
                if (($i + 1) -lt $Bytes.Length -and ($Bytes[$i + 1] -band 0xC0) -eq 0x80) {
                    $isUtf8 = $true
                }
            }
            # 0xE5, 0xE6 are in the 3-byte lead range (E0-EF):
            # valid only if next 2 bytes are continuation bytes
            elseif ($b -le 0xEF) {
                if (($i + 2) -lt $Bytes.Length -and
                    ($Bytes[$i + 1] -band 0xC0) -eq 0x80 -and
                    ($Bytes[$i + 2] -band 0xC0) -eq 0x80) {
                    $isUtf8 = $true
                }
            }
            # 0xF8 is beyond valid UTF-8 lead range (max F4) → always bare cp1252

            if ($isUtf8) {
                $out.Add($b)
            }
            else {
                foreach ($rb in $map[[int]$b]) { $out.Add($rb) }
            }
        }
        else {
            $out.Add($b)
        }
        $i++
    }
    return [byte[]]$out.ToArray()
}

# ════════════════════════════════════════════════════════════════════════════════
# Resolve the Cursor Agent CLI binary
# ════════════════════════════════════════════════════════════════════════════════

function Find-CursorAgent {
    $agentBase = Join-Path $env:LOCALAPPDATA 'cursor-agent'
    if (-not (Test-Path $agentBase)) { return $null }
    $versionsDir = Join-Path $agentBase 'versions'
    if (-not (Test-Path $versionsDir)) { return $null }

    # ^\d{4}\.\d{1,2}\.\d{1,2}-[a-f0-9]+$  — version dirs like 2026.02.13-41ac335
    $latest = Get-ChildItem $versionsDir -Directory |
        Where-Object { $_.Name -match '^\d{4}\.\d{1,2}\.\d{1,2}-[a-f0-9]+$' } |
        Sort-Object { [int]($_.Name.Split('-')[0] -replace '\.','') } -Descending |
        Select-Object -First 1

    if (-not $latest) { return $null }

    $node  = Join-Path $latest.FullName 'node.exe'
    $index = Join-Path $latest.FullName 'index.js'
    if ((Test-Path $node) -and (Test-Path $index)) {
        return @{ NodeExe = $node; IndexJs = $index; Version = $latest.Name }
    }
    return $null
}

$agent = Find-CursorAgent
if (-not $agent) {
    Write-Host 'Cursor Agent CLI not installed. Installing...' -ForegroundColor Yellow
    try {
        Invoke-Expression (Invoke-RestMethod 'https://cursor.com/install?win32=true')
        $agent = Find-CursorAgent
    } catch {
        Write-Error "Failed to install Cursor Agent CLI: $($_.Exception.Message)"
        exit 1
    }
    if (-not $agent) {
        Write-Error 'Installation completed but agent binary not found. Try restarting your terminal.'
        exit 1
    }
}

$env:CURSOR_INVOKED_AS = 'agent.cmd'
Write-Host "Cursor Agent CLI v$($agent.Version)" -ForegroundColor DarkGray
Write-LogMessage "Using Cursor Agent CLI v$($agent.Version)" -Level INFO

# ════════════════════════════════════════════════════════════════════════════════
# Ensure authenticated
# ════════════════════════════════════════════════════════════════════════════════

$statusOutput = & $agent.NodeExe $agent.IndexJs status 2>&1 | Out-String
if ($statusOutput -notmatch 'Logged in') {
    Write-Host 'Not logged in. Opening browser for Cursor authentication...' -ForegroundColor Yellow
    $loginProc = Start-Process -FilePath $agent.NodeExe -ArgumentList $agent.IndexJs, 'login' -PassThru -NoNewWindow
    $loginProc.WaitForExit(120000)
    if ($loginProc.ExitCode -ne 0) {
        Write-Error 'Login failed or timed out. Run "agent login" manually.'
        exit 1
    }
    Write-Host 'Login successful.' -ForegroundColor Green
}

# ════════════════════════════════════════════════════════════════════════════════
# Handle -ListModels
# ════════════════════════════════════════════════════════════════════════════════

if ($ListModels) {
    & $agent.NodeExe $agent.IndexJs models 2>&1
    exit 0
}

# ════════════════════════════════════════════════════════════════════════════════
# Handle -ListSessions
# ════════════════════════════════════════════════════════════════════════════════

if ($ListSessions) {
    $storedSessions = @(Get-ChildItem -Path $script:SessionsFolder -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($storedSessions.Count -eq 0) {
        Write-Host 'No stored sessions found.' -ForegroundColor Yellow
        Write-Host "Sessions folder: $($script:SessionsFolder)" -ForegroundColor DarkGray
        exit 0
    }
    Write-Host "`nStored conversation sessions ($($storedSessions.Count)):" -ForegroundColor Cyan
    Write-Host ('-' * 90) -ForegroundColor DarkGray
    foreach ($sf in $storedSessions | Select-Object -First 30) {
        $meta = try { Get-Content $sf.FullName -Raw -Encoding utf8 | ConvertFrom-Json } catch { $null }
        $sid  = if ($meta -and $meta.SessionId) { $meta.SessionId.Substring(0, [Math]::Min(12, $meta.SessionId.Length)) + '...' } else { '?' }
        $model = if ($meta -and $meta.Model) { $meta.Model } else { '?' }
        $resumed = if ($meta -and $meta.ResumedFrom) { " (resumed)" } else { '' }
        $prompt = if ($meta -and $meta.PromptPreview) {
            $pv = $meta.PromptPreview
            if ($pv.Length -gt 60) { $pv.Substring(0, 60) + '...' } else { $pv }
        } else { '?' }
        Write-Host "  $($sf.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor DarkGray -NoNewline
        Write-Host "  $sid" -ForegroundColor White -NoNewline
        Write-Host "  [$model]$resumed" -ForegroundColor Yellow -NoNewline
        Write-Host "  $prompt" -ForegroundColor Gray
    }
    if ($storedSessions.Count -gt 30) {
        Write-Host "  ... and $($storedSessions.Count - 30) more" -ForegroundColor DarkGray
    }
    Write-Host "`nSession files: $($script:SessionsFolder)" -ForegroundColor DarkGray
    Write-Host "To resume:     -SessionId '<full-session-id>' -Prompt 'follow-up question'" -ForegroundColor DarkGray
    Write-Host "               -Continue -Prompt 'follow-up question'  (resumes most recent)" -ForegroundColor DarkGray
    exit 0
}

# ════════════════════════════════════════════════════════════════════════════════
# MCP auto-detection
# ════════════════════════════════════════════════════════════════════════════════

$mcpInfo = @{ Servers = @(); RagServers = @(); QueryServers = @(); Enabled = $false }

function Get-McpServerList {
    $mcpJsonPath = Join-Path $env:USERPROFILE '.cursor\mcp.json'
    if (-not (Test-Path $mcpJsonPath)) {
        Write-Host 'No ~/.cursor/mcp.json found.' -ForegroundColor Yellow
        return @()
    }
    $mcpConfig = Get-Content $mcpJsonPath -Raw | ConvertFrom-Json
    if (-not $mcpConfig.mcpServers) {
        Write-Host 'No MCP servers configured.' -ForegroundColor Yellow
        return @()
    }
    $servers = @()
    foreach ($prop in $mcpConfig.mcpServers.PSObject.Properties) {
        $name = $prop.Name
        $def  = $prop.Value
        $defProps = $def.PSObject.Properties
        $argsStr = if ($defProps['args']) { ($def.args -join ' ') } else { '' }

        $category = 'other'
        $transport = if ($defProps['url']) { $def.url } elseif ($defProps['command']) { $def.command } else { '?' }

        if ($argsStr -match 'server_mcp_proxy\.py.*--rag\s+(\S+)') {
            $category = 'rag'
        }
        elseif ($name -match 'query' -or $argsStr -match 'query') {
            $category = 'query'
        }

        $servers += [PSCustomObject]@{
            Name      = $name
            Category  = $category
            Transport = $transport
        }
    }
    return $servers
}

if ($ListMcp) {
    $servers = Get-McpServerList
    if ($servers.Count -eq 0) { exit 0 }
    Write-Host "`nConfigured MCP Servers ($($servers.Count)):" -ForegroundColor Cyan
    Write-Host ('-' * 70) -ForegroundColor DarkGray
    $servers | Sort-Object Category, Name | ForEach-Object {
        $catColor = switch ($_.Category) { 'rag' { 'Green' } 'query' { 'Yellow' } default { 'Gray' } }
        $cat = $_.Category.PadRight(6)
        Write-Host "  [$cat] " -ForegroundColor $catColor -NoNewline
        Write-Host "$($_.Name)" -ForegroundColor White -NoNewline
        Write-Host "  $($_.Transport)" -ForegroundColor DarkGray
    }
    Write-Host ''
    exit 0
}

if (-not $NoMcp) {
    $mcpJsonPath = Join-Path $env:USERPROFILE '.cursor\mcp.json'
    if (Test-Path $mcpJsonPath) {
        try {
            $mcpConfig = Get-Content $mcpJsonPath -Raw | ConvertFrom-Json
            $allServers = @()

            if ($mcpConfig.mcpServers) {
                foreach ($prop in $mcpConfig.mcpServers.PSObject.Properties) {
                    $serverName = $prop.Name
                    $serverDef  = $prop.Value

                    $category = 'other'
                    $description = ''

                    $serverProps = $serverDef.PSObject.Properties
                    $argsStr = ''
                    if ($serverProps['args']) { $argsStr = ($serverDef.args -join ' ') }

                    if ($argsStr -match 'server_mcp_proxy\.py.*--rag\s+(\S+)') {
                        $category = 'rag'
                        $ragName  = $Matches[1]
                        switch ($ragName) {
                            'db2-docs'          { $description = 'DB2/LUW documentation — SQL errors, security, configuration' }
                            'visual-cobol-docs' { $description = 'Visual COBOL / Rocket COBOL — compiler messages, language reference' }
                            'Dedge-code'       { $description = 'Dedge source code — function locations, module structure, COBOL programs' }
                            default             { $description = "RAG documentation: $($ragName)" }
                        }
                    }
                    elseif ($serverName -match 'query' -or $argsStr -match 'query') {
                        $category = 'query'
                        switch -Wildcard ($serverName) {
                            '*db2*'        { $description = 'DB2 database query (read-only SQL)' }
                            '*postgresql*' { $description = 'PostgreSQL database query' }
                            '*autodoc*'    { $description = 'AutoDocJson — pre-parsed COBOL analysis data' }
                            default        { $description = "Database query: $($serverName)" }
                        }
                    }

                    $allServers += [PSCustomObject]@{
                        Name        = $serverName
                        Category    = $category
                        Description = $description
                        HasUrl      = [bool]($serverProps['url'])
                        HasCommand  = [bool]($serverProps['command'])
                    }
                }
            }

            $serversToEnable = if ($McpServers) {
                $allServers | Where-Object { $_.Name -in $McpServers }
            } else {
                $allServers
            }

            if ($serversToEnable.Count -gt 0) {
                Write-Host "MCP: Detected $($allServers.Count) server(s), enabling $($serversToEnable.Count)..." -ForegroundColor DarkGray
                Write-LogMessage "MCP: Detected $($allServers.Count) server(s), enabling $($serversToEnable.Count)" -Level INFO

                foreach ($srv in $serversToEnable) {
                    $enableOut = & $agent.NodeExe $agent.IndexJs mcp enable $srv.Name 2>&1 | Out-String
                    $status = if ($enableOut -match 'already (enabled|approved)') { 'already enabled' }
                              elseif ($enableOut -match 'Enabled') { 'enabled' }
                              else { 'unknown' }
                    Write-Host "  $($srv.Name) ($($srv.Category)): $($status)" -ForegroundColor DarkGray
                }

                $mcpInfo.Servers      = $serversToEnable
                $mcpInfo.RagServers   = @($serversToEnable | Where-Object { $_.Category -eq 'rag' })
                $mcpInfo.QueryServers = @($serversToEnable | Where-Object { $_.Category -eq 'query' })
                $mcpInfo.Enabled      = $true
            }
        } catch {
            Write-Warning "MCP auto-detection failed: $($_.Exception.Message). Continuing without MCP."
        }
    } else {
        Write-Host 'MCP: No ~/.cursor/mcp.json found, skipping MCP.' -ForegroundColor DarkGray
    }
}

# ════════════════════════════════════════════════════════════════════════════════
# Rules resolution: find and load .cursor/rules/*.mdc
# ════════════════════════════════════════════════════════════════════════════════

function Find-RulesFolderUpward {
    param([string]$StartDir)
    $dir = $StartDir
    while ($dir) {
        $rulesDir = Join-Path $dir '.cursor\rules'
        if (Test-Path $rulesDir -PathType Container) { return $rulesDir }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Resolve-RulesFolder {
    param([string]$Explicit, [string]$Workspace, [string]$Folder, [string[]]$Files)

    # 1. Explicit -RulesPath (walk up from it)
    if ($Explicit) {
        $found = Find-RulesFolderUpward -StartDir $Explicit
        if ($found) { return $found }
    }

    # 2. Workspace or FolderPath
    foreach ($base in @($Workspace, $Folder)) {
        if (-not $base) { continue }
        $found = Find-RulesFolderUpward -StartDir $base
        if ($found) { return $found }
    }

    # 3. First -FilePaths entry: walk up from the file's directory
    if ($Files -and $Files.Count -gt 0) {
        $firstFile = $Files[0]
        if (Test-Path $firstFile) {
            $fileDir = if (Test-Path $firstFile -PathType Container) { $firstFile } else { Split-Path $firstFile -Parent }
            $found = Find-RulesFolderUpward -StartDir $fileDir
            if ($found) { return $found }
        }
    }

    # 4. Current directory
    $found = Find-RulesFolderUpward -StartDir $PWD.Path
    if ($found) { return $found }

    # 5. Script's own project (Cursor-AgentCLI lives inside DedgePsh)
    $found = Find-RulesFolderUpward -StartDir $PSScriptRoot
    if ($found) { return $found }

    return $null
}

$rulesInfo = @{ Folder = $null; Files = @(); TotalChars = 0 }

if (-not $NoRules) {
    $resolvedRulesFolder = Resolve-RulesFolder -Explicit $RulesPath -Workspace $WorkspacePath -Folder $FolderPath -Files $FilePaths
    if ($resolvedRulesFolder) {
        $mdcFiles = @(Get-ChildItem -Path $resolvedRulesFolder -Filter '*.mdc' -File -ErrorAction SilentlyContinue |
            Sort-Object Name)
        if ($mdcFiles.Count -gt 0) {
            $rulesInfo.Folder = $resolvedRulesFolder
            $rulesInfo.Files  = $mdcFiles
            $totalRuleChars = 0
            foreach ($f in $mdcFiles) { $totalRuleChars += $f.Length }
            $rulesInfo.TotalChars = $totalRuleChars
            Write-Host "Rules: $($mdcFiles.Count) rule(s) from $($resolvedRulesFolder) ($($totalRuleChars) chars)" -ForegroundColor DarkGray
            Write-LogMessage "Rules: $($mdcFiles.Count) rule(s) from $($resolvedRulesFolder) ($($totalRuleChars) chars)" -Level INFO
        }
    }
    if (-not $rulesInfo.Folder) {
        Write-Host 'Rules: No .cursor/rules/ found in workspace hierarchy.' -ForegroundColor DarkGray
    }
}

if ($ListRules) {
    $resolvedRulesFolder = Resolve-RulesFolder -Explicit $RulesPath -Workspace $WorkspacePath -Folder $FolderPath -Files $FilePaths
    if (-not $resolvedRulesFolder) {
        Write-Host 'No .cursor/rules/ folder found.' -ForegroundColor Yellow
        Write-Host "Searched: $($RulesPath), $($WorkspacePath), $($FolderPath), $($FilePaths), $($PWD.Path)" -ForegroundColor DarkGray
        exit 0
    }
    $mdcFiles = @(Get-ChildItem -Path $resolvedRulesFolder -Filter '*.mdc' -File -ErrorAction SilentlyContinue |
        Sort-Object Name)
    if ($mdcFiles.Count -eq 0) {
        Write-Host "No .mdc files in: $($resolvedRulesFolder)" -ForegroundColor Yellow
        exit 0
    }
    Write-Host "`nProject Rules from: $($resolvedRulesFolder)" -ForegroundColor Cyan
    Write-Host ('-' * 70) -ForegroundColor DarkGray
    foreach ($f in $mdcFiles) {
        $sizeKb = [Math]::Round($f.Length / 1024, 1)
        $firstLine = (Get-Content $f.FullName -TotalCount 3 | Where-Object { $_ -match '^\s*#' } | Select-Object -First 1) -replace '^\s*#\s*', ''
        if (-not $firstLine) { $firstLine = $f.BaseName }
        Write-Host "  $($f.Name)" -ForegroundColor White -NoNewline
        Write-Host " ($($sizeKb) KB)" -ForegroundColor DarkGray -NoNewline
        Write-Host "  $firstLine" -ForegroundColor Gray
    }
    Write-Host "`n$($mdcFiles.Count) rule file(s), $('{0:N0}' -f ($mdcFiles | Measure-Object -Property Length -Sum).Sum) bytes total" -ForegroundColor DarkGray
    exit 0
}

# ════════════════════════════════════════════════════════════════════════════════
# Build the prompt
# ════════════════════════════════════════════════════════════════════════════════

$fullPrompt  = $Prompt
$totalEmbeddedChars = 0

# --- Inject rules as system instructions ---
if ($rulesInfo.Files.Count -gt 0) {
    $rulesBlock = @()
    $rulesBlock += "`n`n--- PROJECT RULES (from $($rulesInfo.Folder)) ---"
    $rulesBlock += "Follow these project rules and conventions when answering:`n"
    foreach ($ruleFile in $rulesInfo.Files) {
        $ruleContent = Read-FileContentAsUtf8 -Path $ruleFile.FullName
        $rulesBlock += "### $($ruleFile.BaseName)"
        $rulesBlock += $ruleContent
        $rulesBlock += ''
    }
    $rulesBlock += "--- END PROJECT RULES ---"
    $rulesBlock += ""
    $rulesBlock += "IMPORTANT: At the end of your answer, include a short 'Rules applied' section listing which of the above rules (by name) influenced your answer. Only list rules that were actually relevant."
    $fullPrompt = ($rulesBlock -join "`n") + "`n`n" + $fullPrompt
    $totalEmbeddedChars += $rulesInfo.TotalChars
    Write-Host "Rules injected: $($rulesInfo.Files.Count) file(s), $($rulesInfo.TotalChars) chars" -ForegroundColor DarkGray
}

# --- Inject MCP awareness block ---
if ($mcpInfo.Enabled -and ($mcpInfo.RagServers.Count -gt 0 -or $mcpInfo.QueryServers.Count -gt 0)) {
    $mcpBlock = @()
    $mcpBlock += "`n`n--- MCP TOOLS AVAILABLE ---"
    $mcpBlock += "You have access to the following MCP tool servers. Use them when relevant."

    if ($mcpInfo.RagServers.Count -gt 0) {
        $mcpBlock += "`nRAG documentation servers (use query_docs tool to search by meaning):"
        foreach ($rag in $mcpInfo.RagServers) {
            $mcpBlock += "  - $($rag.Name): $($rag.Description)"
        }
    }

    if ($mcpInfo.QueryServers.Count -gt 0) {
        $mcpBlock += "`nQuery servers (database/API, read-only):"
        foreach ($qry in $mcpInfo.QueryServers) {
            $mcpBlock += "  - $($qry.Name): $($qry.Description)"
        }
    }

    $mcpBlock += "--- END MCP TOOLS ---"
    $fullPrompt = ($mcpBlock -join "`n") + "`n`n" + $fullPrompt
}

# --- Embed explicit files ---
if ($FilePaths) {
    foreach ($fp in $FilePaths) {
        if (-not (Test-Path $fp)) {
            Write-Warning "File not found, skipping: $($fp)"
            continue
        }
        $fileName = Split-Path $fp -Leaf
        $content  = Read-FileContentAsUtf8 -Path $fp
        if ($content.Length + $totalEmbeddedChars -gt 1000000) {
            Write-Warning "Skipping $($fileName): would exceed 1M char embed limit"
            continue
        }
        $fullPrompt += "`n`n--- FILE: $($fileName) ---`n$($content)`n--- END FILE ---"
        $totalEmbeddedChars += $content.Length
        Write-Host "Embedded file: $($fileName) ($($content.Length) chars)" -ForegroundColor DarkGray
    }
}

# --- Embed folder files (strict context mode) ---
if ($FolderPath -and $EmbedFolder) {
    if (-not (Test-Path $FolderPath -PathType Container)) {
        Write-Error "FolderPath not found or not a directory: $($FolderPath)"
        exit 1
    }

    $folderFiles = Get-ChildItem -Path $FolderPath -File -Filter $FolderFilter -Recurse -ErrorAction SilentlyContinue |
        Sort-Object Length |
        Select-Object -First ($FolderMaxFiles * 2)

    $embeddedCount = 0
    foreach ($file in $folderFiles) {
        if ($embeddedCount -ge $FolderMaxFiles) { break }
        if ($totalEmbeddedChars -ge $FolderMaxChars) {
            Write-Warning "Char budget exhausted ($($FolderMaxChars)). Embedded $($embeddedCount) of $($folderFiles.Count) files."
            break
        }

        try {
            $content = Read-FileContentAsUtf8 -Path $file.FullName
        } catch {
            continue
        }
        if (-not $content) { continue }
        if ($content.Length -gt 100000) {
            Write-Warning "Skipping large file ($($content.Length) chars): $($file.Name)"
            continue
        }
        if ($content.Length + $totalEmbeddedChars -gt $FolderMaxChars) {
            Write-Warning "Skipping $($file.Name): would exceed char budget"
            continue
        }

        $relativePath = $file.FullName.Substring($FolderPath.TrimEnd('\').Length + 1)
        $fullPrompt += "`n`n--- FILE: $($relativePath) ---`n$($content)`n--- END FILE ---"
        $totalEmbeddedChars += $content.Length
        $embeddedCount++
    }

    Write-Host "Embedded $($embeddedCount) files from folder ($($totalEmbeddedChars) total chars)" -ForegroundColor DarkGray
}

# ════════════════════════════════════════════════════════════════════════════════
# Resolve workspace
# ════════════════════════════════════════════════════════════════════════════════

$effectiveWorkspace = $WorkspacePath
if ($FolderPath -and (-not $EmbedFolder) -and (-not $WorkspacePath)) {
    $effectiveWorkspace = $FolderPath
    Write-Host "Workspace: $($FolderPath) (agent can browse/search)" -ForegroundColor DarkGray
}

# ════════════════════════════════════════════════════════════════════════════════
# Build CLI arguments
# ════════════════════════════════════════════════════════════════════════════════

$cliArgs = @($agent.IndexJs, '-p', '--trust', '--model', $Model, '--output-format', $OutputFormat)

if ($Mode) {
    $cliArgs += @('--mode', $Mode)
}
if ($Force) {
    $cliArgs += '--force'
}
if ($effectiveWorkspace) {
    $cliArgs += @('--workspace', $effectiveWorkspace)
}
if ($mcpInfo.Enabled) {
    $cliArgs += '--approve-mcps'
}
if ($SessionId) {
    $cliArgs += @('--resume', $SessionId)
    Write-Host "Resuming session: $($SessionId)" -ForegroundColor DarkGray
    Write-LogMessage "Resuming session: $($SessionId)" -Level INFO
}
elseif ($Continue) {
    $cliArgs += '--continue'
    Write-Host 'Continuing most recent session...' -ForegroundColor DarkGray
    Write-LogMessage 'Continuing most recent session' -Level INFO
}

# ════════════════════════════════════════════════════════════════════════════════
# Call the agent (pipe prompt through stdin — required on Windows)
# ════════════════════════════════════════════════════════════════════════════════

$contextSummary = @()
if ($FilePaths)                      { $contextSummary += "$($FilePaths.Count) file(s) embedded" }
if ($FolderPath -and $EmbedFolder)   { $contextSummary += "folder embedded ($($FolderFilter))" }
if ($FolderPath -and !$EmbedFolder)  { $contextSummary += "folder workspace" }
if ($mcpInfo.Enabled)                { $contextSummary += "$($mcpInfo.Servers.Count) MCP(s)" }
$contextStr = if ($contextSummary.Count) { $contextSummary -join ' + ' } else { 'none' }

Write-Host "Model: $($Model) | Mode: $($Mode) | Format: $($OutputFormat) | Context: $($contextStr)" -ForegroundColor DarkGray
$promptPreview = $Prompt.Substring(0, [Math]::Min(100, $Prompt.Length))
Write-Host "Prompt: $($promptPreview)..." -ForegroundColor DarkGray
Write-LogMessage "Calling agent: Model=$($Model), Mode=$($Mode), Format=$($OutputFormat), Context=$($contextStr), PromptLen=$($fullPrompt.Length)" -Level INFO

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName  = $agent.NodeExe
$psi.Arguments = ($cliArgs | ForEach-Object {
    if ($_ -match '\s') { "`"$_`"" } else { $_ }
}) -join ' '
$psi.RedirectStandardInput  = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow  = $true

$proc = [System.Diagnostics.Process]::Start($psi)

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$promptBytes = $utf8NoBom.GetBytes($fullPrompt)
$proc.StandardInput.BaseStream.Write($promptBytes, 0, $promptBytes.Length)
$proc.StandardInput.BaseStream.Flush()
$proc.StandardInput.Close()

$outMs  = [System.IO.MemoryStream]::new()
$errMs  = [System.IO.MemoryStream]::new()
$outTask = $proc.StandardOutput.BaseStream.CopyToAsync($outMs)
$errTask = $proc.StandardError.BaseStream.CopyToAsync($errMs)
[System.Threading.Tasks.Task]::WaitAll(@($outTask, $errTask))
$proc.WaitForExit()

$outBytes = $outMs.ToArray(); $outMs.Dispose()
$errBytes = $errMs.ToArray(); $errMs.Dispose()

$fixedOut  = Repair-NorwegianBytes -Bytes $outBytes
$rawString = $utf8NoBom.GetString($fixedOut).Trim()

if ($errBytes.Length -gt 0) {
    $fixedErr = Repair-NorwegianBytes -Bytes $errBytes
    $errString = $utf8NoBom.GetString($fixedErr).Trim()
    if ($errString) { $rawString = "$rawString`n$errString" }
}

$stopwatch.Stop()

Write-Host "Completed in $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
Write-LogMessage "Agent call completed in $($stopwatch.ElapsedMilliseconds)ms (exit code $($proc.ExitCode))" -Level INFO

# ════════════════════════════════════════════════════════════════════════════════
# Parse, store, and return the result
# ════════════════════════════════════════════════════════════════════════════════

function Save-SessionResult {
    param(
        [string]$SessionIdValue,
        [string]$ResultText,
        [string]$ModelName,
        [long]$DurationMs,
        [bool]$IsError,
        [bool]$McpUsed,
        [string]$PromptText,
        [string]$OutputFmt,
        [string]$ResumedFrom
    )
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $sidSafe = if ($SessionIdValue) {
        $SessionIdValue -replace '[^a-zA-Z0-9_-]', '_'
    } else {
        'unknown'
    }
    $fileName = "$($sidSafe)_$($ts).json"
    $filePath = Join-Path $script:SessionsFolder $fileName

    $promptPreview = if ($PromptText.Length -gt 200) { $PromptText.Substring(0, 200) + '...' } else { $PromptText }

    $record = [ordered]@{
        SessionId     = $SessionIdValue
        Timestamp     = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Model         = $ModelName
        DurationMs    = $DurationMs
        IsError       = $IsError
        McpUsed       = $McpUsed
        OutputFormat  = $OutputFmt
        ResumedFrom   = $ResumedFrom
        PromptPreview = $promptPreview
        Result        = $ResultText
    }

    $record | ConvertTo-Json -Depth 10 | Out-File -FilePath $filePath -Encoding utf8 -Force
    Write-LogMessage "Session result saved: $($filePath)" -Level INFO
    return $filePath
}

$resumedFrom = if ($SessionId) { $SessionId } elseif ($Continue) { '(continue)' } else { '' }

if ($OutputFormat -eq 'json') {
    try {
        $envelope = $rawString | ConvertFrom-Json
    } catch {
        Write-LogMessage "Failed to parse JSON response: $($_.Exception.Message)" -Level ERROR
        Write-Error "Failed to parse JSON: $($_.Exception.Message)`nRaw: $($rawString.Substring(0, [Math]::Min(300, $rawString.Length)))"
        exit 1
    }

    if ($envelope.is_error) {
        Write-LogMessage "Agent returned error: $($envelope.result)" -Level ERROR
        $savedPath = Save-SessionResult -SessionIdValue $envelope.session_id -ResultText $envelope.result `
            -ModelName $Model -DurationMs $envelope.duration_ms -IsError $true -McpUsed $mcpInfo.Enabled `
            -PromptText $Prompt -OutputFmt $OutputFormat -ResumedFrom $resumedFrom
        Write-Error "Agent error: $($envelope.result)"
        exit 1
    }

    $savedPath = Save-SessionResult -SessionIdValue $envelope.session_id -ResultText $envelope.result `
        -ModelName $Model -DurationMs $envelope.duration_ms -IsError $false -McpUsed $mcpInfo.Enabled `
        -PromptText $Prompt -OutputFmt $OutputFormat -ResumedFrom $resumedFrom

    Write-Host "Session stored: $($savedPath)" -ForegroundColor DarkGray
    Write-LogMessage "Session $($envelope.session_id) completed successfully" -Level INFO

    [PSCustomObject]@{
        Result      = $envelope.result
        DurationMs  = $envelope.duration_ms
        SessionId   = $envelope.session_id
        Model       = $Model
        IsError     = $envelope.is_error
        McpUsed     = $mcpInfo.Enabled
        StoredAt    = $savedPath
    }
} elseif ($OutputFormat -eq 'text') {
    $savedPath = Save-SessionResult -SessionIdValue 'text-mode' -ResultText $rawString `
        -ModelName $Model -DurationMs $stopwatch.ElapsedMilliseconds -IsError $false -McpUsed $mcpInfo.Enabled `
        -PromptText $Prompt -OutputFmt $OutputFormat -ResumedFrom $resumedFrom
    Write-Host "Session stored: $($savedPath)" -ForegroundColor DarkGray
    Write-LogMessage "Text-mode response stored: $($savedPath)" -Level INFO
    $rawString
} else {
    $savedPath = Save-SessionResult -SessionIdValue 'stream-mode' -ResultText $rawString `
        -ModelName $Model -DurationMs $stopwatch.ElapsedMilliseconds -IsError $false -McpUsed $mcpInfo.Enabled `
        -PromptText $Prompt -OutputFmt $OutputFormat -ResumedFrom $resumedFrom
    Write-Host "Session stored: $($savedPath)" -ForegroundColor DarkGray
    Write-LogMessage "Stream-mode response stored: $($savedPath)" -Level INFO
    $rawString
}
