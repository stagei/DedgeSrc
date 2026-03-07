#Requires -Version 7.0
<#
.SYNOPSIS
    Downloads and installs the Cursor CLI (agent) on Windows.

.DESCRIPTION
    Uses the official Cursor install endpoint for Windows (win32=true is the
    Windows platform identifier -- installs the 64-bit binary on 64-bit systems).
    After install, ensure the CLI is on your PATH (often $env:USERPROFILE\.local\bin).
    Verify with: cursor --version

.EXAMPLE
    pwsh.exe -File .\Install-CursorCli.ps1
#>

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force

$installUrl = 'https://cursor.com/install?win32=true'

Write-LogMessage "Installing Cursor CLI (Windows) from $($installUrl)" -Level INFO
Invoke-RestMethod -Uri $installUrl | Invoke-Expression
Write-LogMessage "Install finished. Add CLI to PATH if needed, then verify with: cursor --version" -Level INFO
