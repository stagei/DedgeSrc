#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configures Windows Firewall rules for Ollama AI.

.DESCRIPTION
    This script configures Windows Firewall to allow Ollama to function properly:
    
    - Opens the Ollama API port for inbound connections (current configured port)
    - Allows Ollama process to download models from ollama.com/org
    - Optionally allows Edge browser to access Ollama websites
    
    The script detects the current Ollama port configuration and creates
    appropriate rules. If Ollama is using a non-standard port, both the
    custom port and the default port (11434) are opened.

.PARAMETER ShowCurrentRules
    Shows current Ollama firewall rules without making changes.

.PARAMETER RemoveExisting
    Removes existing Ollama firewall rules before creating new ones.

.PARAMETER RemoveOnly
    Only removes existing Ollama firewall rules (does not create new ones).

.PARAMETER SkipBrowserRules
    Skips creating rules for Edge browser access to Ollama websites.

.PARAMETER WhatIf
    Shows what rules would be created without actually creating them.

.EXAMPLE
    .\Ollama-ConfigureFirewall.ps1
    # Creates all necessary firewall rules for Ollama

.EXAMPLE
    .\Ollama-ConfigureFirewall.ps1 -ShowCurrentRules
    # Shows existing Ollama firewall rules

.EXAMPLE
    .\Ollama-ConfigureFirewall.ps1 -RemoveExisting
    # Removes old rules and creates fresh ones

.EXAMPLE
    .\Ollama-ConfigureFirewall.ps1 -RemoveOnly
    # Only removes existing Ollama firewall rules

.EXAMPLE
    .\Ollama-ConfigureFirewall.ps1 -SkipBrowserRules
    # Creates rules without Edge browser rules

.NOTES
    Must be run as Administrator.
    Uses the OllamaHandler module for configuration.

.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [switch]$ShowCurrentRules,

    [Parameter()]
    [switch]$RemoveExisting,

    [Parameter()]
    [switch]$RemoveOnly,

    [Parameter()]
    [switch]$SkipBrowserRules
)

# Import required modules
Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
Import-Module OllamaHandler -Force -ErrorAction Stop

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         OLLAMA FIREWALL CONFIGURATION                          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Show current Ollama configuration
$config = Get-OllamaConfiguration
Write-Host "Current Ollama Configuration:" -ForegroundColor Yellow
Write-Host "  Host:          $($config.Host)" -ForegroundColor White
Write-Host "  Port:          $($config.Port)" -ForegroundColor White
Write-Host "  API URL:       $($config.ApiUrl)" -ForegroundColor White
Write-Host "  Service:       $(if ($config.ServiceRunning) { 'Running' } else { 'Stopped' })" -ForegroundColor $(if ($config.ServiceRunning) { 'Green' } else { 'Red' })
Write-Host ""

# Show current rules if requested
if ($ShowCurrentRules) {
    Write-Host "Current Ollama Firewall Rules:" -ForegroundColor Yellow
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    
    $rules = Get-OllamaFirewallRules
    
    if ($rules.Count -eq 0) {
        Write-Host "  No Ollama firewall rules found." -ForegroundColor DarkGray
    }
    else {
        foreach ($rule in $rules) {
            $status = if ($rule.Enabled -eq 'True') { "✓" } else { "✗" }
            $ports = @()
            if ($rule.LocalPort) { $ports += "Local:$($rule.LocalPort)" }
            if ($rule.RemotePort) { $ports += "Remote:$($rule.RemotePort)" }
            $portStr = if ($ports.Count -gt 0) { " ($($ports -join ', '))" } else { "" }
            
            Write-Host "  $status " -ForegroundColor $(if ($rule.Enabled -eq 'True') { 'Green' } else { 'Red' }) -NoNewline
            Write-Host "$($rule.DisplayName)" -ForegroundColor White -NoNewline
            Write-Host "$portStr" -ForegroundColor DarkGray
            Write-Host "      Direction: $($rule.Direction), Action: $($rule.Action)" -ForegroundColor DarkGray
            if ($rule.Program) {
                Write-Host "      Program: $(Split-Path $rule.Program -Leaf)" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ""
    exit 0
}

# Remove only if requested
if ($RemoveOnly) {
    Write-Host "Removing all Ollama firewall rules..." -ForegroundColor Yellow
    $removed = Remove-OllamaFirewallRules
    Write-Host ""
    Write-Host "Removed $removed rule(s)." -ForegroundColor Green
    exit 0
}

# Configure firewall
Write-Host "Configuring Windows Firewall for Ollama..." -ForegroundColor Yellow
Write-Host ""

$params = @{}

if ($SkipBrowserRules) {
    $params.SkipBrowserRules = $true
}

if ($RemoveExisting) {
    $params.RemoveExisting = $true
}

$result = Set-OllamaFirewallRules @params

Write-Host ""
Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if ($result.Success) {
    Write-Host "╔═══════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   FIREWALL CONFIGURED SUCCESSFULLY!   ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════╝" -ForegroundColor Green
}
else {
    Write-Host "╔═══════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║   CONFIGURATION COMPLETED WITH ERRORS ║" -ForegroundColor Red
    Write-Host "╚═══════════════════════════════════════╝" -ForegroundColor Red
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  Rules Created: $($result.RulesCreated.Count)" -ForegroundColor $(if ($result.RulesCreated.Count -gt 0) { 'Green' } else { 'White' })
Write-Host "  Rules Removed: $($result.RulesRemoved.Count)" -ForegroundColor $(if ($result.RulesRemoved.Count -gt 0) { 'Yellow' } else { 'White' })

if ($result.Errors.Count -gt 0) {
    Write-Host "  Errors:        $($result.Errors.Count)" -ForegroundColor Red
    foreach ($error in $result.Errors) {
        Write-Host "    - $error" -ForegroundColor Red
    }
}

Write-Host ""

if ($result.RulesCreated.Count -gt 0) {
    Write-Host "Created Rules:" -ForegroundColor Green
    foreach ($ruleName in $result.RulesCreated) {
        Write-Host "  ✓ $ruleName" -ForegroundColor Green
    }
    Write-Host ""
}

Write-Host "To view current rules, run:" -ForegroundColor DarkGray
Write-Host "  .\Ollama-ConfigureFirewall.ps1 -ShowCurrentRules" -ForegroundColor White
Write-Host ""

