<#
.SYNOPSIS
    Runs Db2-ShadowDatabase scripts remotely via Cursor-ServerOrchestrator.

.DESCRIPTION
    This is the standard remoting entrypoint for this project.
    It submits a command to Cursor-ServerOrchestrator on the target DB server
    and waits for completion.

    Supported modes:
    - Full pipeline: Run-FullShadowPipeline.ps1
    - Single step:   Step-1..Step-5 scripts

.EXAMPLE
    pwsh.exe -NoProfile -File .\Invoke-RemoteShadowPipeline.ps1 -ConfigName fkmvft -RunFull

.EXAMPLE
    pwsh.exe -NoProfile -File .\Invoke-RemoteShadowPipeline.ps1 -ConfigName fkmvft -Step Step-4-MoveToOriginalInstance.ps1 -StepArguments "-DropExistingTarget"
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigName = "",

    [Parameter(Mandatory = $false)]
    [switch]$RunFull,

    [Parameter(Mandatory = $false)]
    [ValidateSet(
        "Step-1-CreateShadowDatabase.ps1",
        "Step-2-CopyDatabaseContent.ps1",
        "Step-3-CleanupShadowDatabase.ps1",
        "Step-4-MoveToOriginalInstance.ps1",
        "Step-5-VerifyRowCounts.ps1",
        "Verify-LocalDb2Connection.ps1"
    )]
    [string]$Step = "",

    [Parameter(Mandatory = $false)]
    [string]$StepArguments = "",

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 43200,

    [Parameter(Mandatory = $false)]
    [string]$Project = "db2-shadow-database"
)

Import-Module GlobalFunctions -Force

$cursorAgentPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "CodingTools\Cursor-ServerOrchestrator\_helpers\_CursorAgent.ps1"
if (-not (Test-Path $cursorAgentPath -PathType Leaf)) {
    throw "Cursor-ServerOrchestrator helper not found: $($cursorAgentPath)"
}
. $cursorAgentPath

if ($RunFull -and -not [string]::IsNullOrWhiteSpace($Step)) {
    throw "Specify either -RunFull or -Step, not both."
}
if (-not $RunFull -and [string]::IsNullOrWhiteSpace($Step)) {
    throw "Specify one of: -RunFull or -Step <script>."
}

if ([string]::IsNullOrWhiteSpace($ConfigName)) {
    throw "ConfigName is required for remote mode (example: -ConfigName fkmvft)."
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

$command = if ($RunFull) {
    "%OptPath%\DedgePshApps\Db2-ShadowDatabase\Run-FullShadowPipeline.ps1"
} else {
    "%OptPath%\DedgePshApps\Db2-ShadowDatabase\$($Step)"
}

$arguments = $StepArguments
$waitTimeout = $TimeoutSeconds + 600

Write-LogMessage "Submitting remote command to $($serverName): $($command) $($arguments)" -Level INFO

$result = Invoke-ServerCommand -ServerName $serverName `
    -Command $command `
    -Arguments $arguments `
    -Project $Project `
    -Timeout $TimeoutSeconds `
    -WaitTimeout $waitTimeout `
    -PollInterval 30 `
    -CaptureOutput $true

if ($null -eq $result) {
    throw "Timed out waiting for remote command result on $($serverName)."
}
if ($result.exitCode -ne 0) {
    throw "Remote command failed on $($serverName): status=$($result.status), exit=$($result.exitCode)"
}

Write-LogMessage "Remote command completed on $($serverName): status=$($result.status), exit=$($result.exitCode)" -Level INFO
