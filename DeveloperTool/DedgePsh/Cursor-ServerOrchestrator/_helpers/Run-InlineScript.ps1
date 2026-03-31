<#
.SYNOPSIS
    Server-side script that executes a base64-encoded PowerShell command.
    Deployed to the server via _deploy.ps1, invoked by the orchestrator.

.PARAMETER EncodedCommand
    Base64-encoded UTF-8 PowerShell script to execute.

.EXAMPLE
    Invoke-CursorOrchestrator picks this up via next_command.json:
    {
      "command": "%OptPath%\\DedgePshApps\\Cursor-ServerOrchestrator\\_helpers\\Run-InlineScript.ps1",
      "arguments": "-EncodedCommand <base64string>"
    }
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$EncodedCommand
)

try {
    $decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($EncodedCommand))
    $scriptBlock = [scriptblock]::Create($decoded)
    & $scriptBlock
}
catch {
    Write-Error "Run-InlineScript failed: $($_.Exception.Message)"
    exit 1
}
