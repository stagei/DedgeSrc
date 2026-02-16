#Requires -Version 7.0
<#
.SYNOPSIS
    Downloads and installs the Cursor CLI (agent) on Windows.

.DESCRIPTION
    Uses the official Cursor install endpoint for Windows (win32).
    After install, ensure the CLI is on your PATH (often $env:USERPROFILE\.local\bin).
    Verify with: agent --version

.EXAMPLE
    pwsh.exe -File .\Install-CursorCli.ps1
#>

$ErrorActionPreference = 'Stop'
$installUrl = 'https://cursor.com/install?win32=true'

Write-Host "CursorDocIndexQuery: Installing Cursor CLI (Windows) from $($installUrl)"
Invoke-RestMethod -Uri $installUrl -Method Get | Invoke-Expression
Write-Host "Install finished. Add CLI to PATH if needed, then run: agent --version"
