<#
.SYNOPSIS
    Configure Ollama to use the AutoDocJson MCP query tools via Ask-AutoDoc function.
.DESCRIPTION
    Adds an Ask-AutoDoc PowerShell function to the current user's profile that
    queries the AutoDocJson Streamable HTTP MCP server. Supports listing, searching,
    and retrieving documentation files.
.PARAMETER ServerHost
    Hostname of the server running AutoDocJson. Default: dedge-server
.PARAMETER Remove
    Remove Ask-AutoDoc from PowerShell profile.
.EXAMPLE
    pwsh.exe -NoProfile -File Setup-AutoDocMcpOllama.ps1
.EXAMPLE
    pwsh.exe -NoProfile -File Setup-AutoDocMcpOllama.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$ServerHost = 'dedge-server',
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$profilePath = $PROFILE.CurrentUserAllHosts
$markerBegin = '# >>> AiDoc Ask-AutoDoc >>>'
$markerEnd   = '# <<< AiDoc Ask-AutoDoc <<<'

if ($Remove) {
    if (Test-Path -LiteralPath $profilePath) {
        $content = Get-Content -LiteralPath $profilePath -Raw
        $pattern = "(?m)$([regex]::Escape($markerBegin))[\s\S]*?$([regex]::Escape($markerEnd))\r?\n?"
        $cleaned = [regex]::Replace($content, $pattern, '')
        Set-Content -LiteralPath $profilePath -Value $cleaned.TrimEnd() -Encoding utf8
        Write-LogMessage "Removed Ask-AutoDoc from profile. Restart PowerShell." -Level INFO
    }
    return
}

$mcpUrl = "http://$($ServerHost)/AutoDocJson/mcp"

Write-LogMessage "[1/3] Verifying AutoDocJson MCP at $($mcpUrl)..." -Level INFO
try {
    $healthUrl = "http://$($ServerHost)/AutoDocJson/health"
    $null = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5
    Write-LogMessage "       AutoDocJson is healthy" -Level INFO
} catch {
    Write-LogMessage "       AutoDocJson health check failed: $($_.Exception.Message)" -Level WARN
    Write-LogMessage "       Continuing anyway (server may start later)" -Level WARN
}

Write-LogMessage "[2/3] Checking Ollama..." -Level INFO
$ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
if (-not $ollamaCmd) {
    Write-LogMessage "Ollama not found. Install from https://ollama.com" -Level ERROR
    exit 1
}
Write-LogMessage "       Ollama OK" -Level INFO

Write-LogMessage "[3/3] Adding Ask-AutoDoc to profile..." -Level INFO
$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path -LiteralPath $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }

if (Test-Path -LiteralPath $profilePath) {
    $content = Get-Content -LiteralPath $profilePath -Raw
    $pattern = "(?m)$([regex]::Escape($markerBegin))[\s\S]*?$([regex]::Escape($markerEnd))\r?\n?"
    $cleaned = [regex]::Replace($content, $pattern, '')
    if ($content -ne $cleaned) {
        Set-Content -LiteralPath $profilePath -Value $cleaned.TrimEnd() -Encoding utf8
        Write-LogMessage "       Removed old Ask-AutoDoc config." -Level INFO
    }
}

$functionBlock = @"

$markerBegin
function Ask-AutoDoc {
    <#
    .SYNOPSIS
        Query AutoDocJson documentation via MCP.
    .PARAMETER Action
        Action to perform: Search, List, or Get. Default: Search
    .PARAMETER Query
        Search query string (for Search action).
    .PARAMETER FileType
        Filter by file type: CBL, BAT, PS1, REX, SQL, CSharp (for List action).
    .PARAMETER FileName
        JSON file name to retrieve (for Get action), e.g. 'BSAUTOS.CBL.json'.
    .PARAMETER Types
        Comma-separated file types to search, e.g. 'CBL,BAT' (for Search action).
    .EXAMPLE
        Ask-AutoDoc "batch processing"
    .EXAMPLE
        Ask-AutoDoc -Action List -FileType CBL
    .EXAMPLE
        Ask-AutoDoc -Action Get -FileName "BSAUTOS.CBL.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]`$Query,
        [ValidateSet('Search', 'List', 'Get')]
        [string]`$Action = 'Search',
        [string]`$FileType,
        [string]`$FileName,
        [string]`$Types
    )
    `$mcpUrl = '$mcpUrl'
    `$headers = @{ 'Content-Type' = 'application/json'; 'Accept' = 'application/json, text/event-stream' }
    function Send-Mcp(`$method, `$params, `$id, `$sid) {
        `$body = @{ jsonrpc = '2.0'; id = `$id; method = `$method; params = `$params } | ConvertTo-Json -Depth 10
        `$h = @{} + `$headers
        if (`$sid) { `$h['Mcp-Session-Id'] = `$sid }
        `$r = Invoke-WebRequest -Uri `$mcpUrl -Method POST -Body `$body -Headers `$h -UseBasicParsing
        `$sessionId = `$r.Headers['Mcp-Session-Id']
        if (`$sessionId -is [array]) { `$sessionId = `$sessionId[0] }
        `$lines = `$r.Content -split "``n" | Where-Object { `$_ -match '^data:\s*' }
        `$data = if (`$lines) { (`$lines | Select-Object -Last 1) -replace '^data:\s*', '' | ConvertFrom-Json } else { `$r.Content | ConvertFrom-Json }
        return @{ Data = `$data; SessionId = `$sessionId }
    }
    try {
        `$init = Send-Mcp 'initialize' @{ protocolVersion = '2025-03-26'; capabilities = @{}; clientInfo = @{ name = 'Ask-AutoDoc'; version = '1.0' } } 1 `$null
        `$sid = `$init.SessionId
        Send-Mcp 'notifications/initialized' @{} `$null `$sid | Out-Null
        `$toolName = switch (`$Action) {
            'Search' { 'search_documents' }
            'List'   { 'list_documents' }
            'Get'    { 'get_document' }
        }
        `$args2 = @{}
        switch (`$Action) {
            'Search' { `$args2.query = `$Query; if (`$Types) { `$args2.types = `$Types } }
            'List'   { if (`$FileType) { `$args2.fileType = `$FileType } }
            'Get'    { `$args2.fileName = `$FileName }
        }
        `$result = Send-Mcp 'tools/call' @{ name = `$toolName; arguments = `$args2 } 2 `$sid
        `$text = `$result.Data.result.content[0].text
        `$text | ConvertFrom-Json | ConvertTo-Json -Depth 20
    } catch {
        Write-Error "Ask-AutoDoc failed: `$(`$_.Exception.Message)"
    }
}
$markerEnd
"@

if (Test-Path -LiteralPath $profilePath) {
    Add-Content -LiteralPath $profilePath -Value $functionBlock -Encoding utf8
} else {
    Set-Content -LiteralPath $profilePath -Value $functionBlock.TrimStart() -Encoding utf8
}

$result = [PSCustomObject]@{
    Script  = $MyInvocation.MyCommand.Name
    Status  = "OK"
    Message = "Installed Ask-AutoDoc in PowerShell profile"
}
Write-LogMessage "RESULT: $($result.Status) - $($result.Message)" -Level INFO
Write-LogMessage "Usage:" -Level INFO
Write-LogMessage "  Ask-AutoDoc `"search terms`"                        # Search docs" -Level INFO
Write-LogMessage "  Ask-AutoDoc -Action List -FileType CBL              # List CBL docs" -Level INFO
Write-LogMessage "  Ask-AutoDoc -Action Get -FileName `"BSAUTOS.CBL.json`"  # Get specific doc" -Level INFO
Write-LogMessage "Restart PowerShell to activate." -Level INFO
Write-Output $result
