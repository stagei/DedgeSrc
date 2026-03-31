<#
.SYNOPSIS
    Stops a running Db2-ShadowDatabase command on a remote server via Cursor-ServerOrchestrator.

.EXAMPLE
    pwsh.exe -NoProfile -File .\Stop-RemoteShadowPipeline.ps1 -ConfigName fkmvft
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigName = "",

    [Parameter(Mandatory = $false)]
    [string]$Reason = "Stop requested for Db2-ShadowDatabase pipeline"
)

Import-Module GlobalFunctions -Force

$cursorAgentPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "CodingTools\Cursor-ServerOrchestrator\_helpers\_CursorAgent.ps1"
if (-not (Test-Path $cursorAgentPath -PathType Leaf)) {
    throw "Cursor-ServerOrchestrator helper not found: $($cursorAgentPath)"
}
. $cursorAgentPath

if ([string]::IsNullOrWhiteSpace($ConfigName)) {
    throw "ConfigName is required (example: -ConfigName fkmvft)."
}

$cfgFile = Join-Path $PSScriptRoot "config.$($ConfigName).json"
if (-not (Test-Path $cfgFile -PathType Leaf)) {
    throw "Config file not found: $($cfgFile)"
}
$cfg = Get-Content $cfgFile -Raw -ErrorAction Stop | ConvertFrom-Json
$serverName = $cfg.ServerFqdn.Split('.')[0]
if ([string]::IsNullOrWhiteSpace($serverName)) {
    throw "Could not resolve server name from $($cfgFile)"
}

Write-LogMessage "Stopping remote process on $($serverName). Reason: $($Reason)" -Level WARN
$stopped = Stop-ServerProcess -ServerName $serverName -Reason $Reason
if (-not $stopped) {
    Write-LogMessage "No running command detected on $($serverName)" -Level INFO
}
