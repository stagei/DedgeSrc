function Invoke-AiCompletion {
    <#
    .SYNOPSIS
        Dispatches an AI completion request to either Cursor CLI or Ollama
        based on the Pwsh2CSharp-Config.json settings.
    .PARAMETER Prompt
        The prompt text to send to the AI provider.
    .PARAMETER FilePaths
        Optional file paths to include as context (Cursor CLI only).
    .PARAMETER Config
        Hashtable loaded from Pwsh2CSharp-Config.json.
    .OUTPUTS
        [string] The AI response text.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [string[]]$FilePaths = @(),

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $provider = $Config.aiProvider
    if (-not $provider) { $provider = 'cursor-cli' }

    switch ($provider) {
        'cursor-cli' {
            return Invoke-CursorCliCompletion -Prompt $Prompt -FilePaths $FilePaths -Config $Config.cursorCli
        }
        'ollama' {
            return Invoke-OllamaCompletion -Prompt $Prompt -Config $Config.ollama
        }
        default {
            Write-LogMessage "Unknown AI provider: $($provider). Falling back to cursor-cli." -Level WARN
            return Invoke-CursorCliCompletion -Prompt $Prompt -FilePaths $FilePaths -Config $Config.cursorCli
        }
    }
}

function Invoke-CursorCliCompletion {
    param(
        [string]$Prompt,
        [string[]]$FilePaths,
        [hashtable]$Config
    )

    $agentScript = 'C:\opt\src\DedgePsh\DevTools\CodingTools\Cursor-AgentCLI\Invoke-CursorAgent.ps1'
    if (-not (Test-Path -LiteralPath $agentScript)) {
        $agentScript = Join-Path $env:OptPath 'DedgePshApps\Cursor-AgentCLI\Invoke-CursorAgent.ps1'
    }
    if (-not (Test-Path -LiteralPath $agentScript)) {
        throw 'Cursor Agent CLI not found. Install or switch aiProvider to ollama.'
    }

    $model = if ($Config.model) { $Config.model } else { 'claude-sonnet-4-20250514' }

    $agentArgs = @{
        Prompt       = $Prompt
        Model        = $model
        Force        = $true
        OutputFormat = 'text'
    }

    if ($FilePaths.Count -gt 0) {
        $agentArgs.FilePaths = $FilePaths
    }

    $result = & $agentScript @agentArgs
    if ($result -and $result.Result) {
        return $result.Result
    }
    return ''
}

function Invoke-OllamaCompletion {
    param(
        [string]$Prompt,
        [hashtable]$Config
    )

    $ollamaUrl = if ($Config.url) { $Config.url } else { 'http://localhost:11434' }
    $model     = if ($Config.model) { $Config.model } else { 'qwen2.5:32b' }
    $timeout   = if ($Config.timeout) { $Config.timeout } else { 120 }

    $body = @{
        model  = $model
        prompt = $Prompt
        stream = $false
        options = @{
            temperature = 0.1
            num_predict = 16384
        }
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri "$($ollamaUrl)/api/generate" `
            -Method Post `
            -Body $body `
            -ContentType 'application/json' `
            -TimeoutSec $timeout

        if ($response.response) {
            return $response.response
        }
        return ''
    }
    catch {
        Write-LogMessage "Ollama request failed: $($_.Exception.Message)" -Level WARN
        return ''
    }
}
