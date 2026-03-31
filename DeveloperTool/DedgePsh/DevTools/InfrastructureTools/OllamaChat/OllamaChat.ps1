#Requires -Version 5.1

<#
.SYNOPSIS
    Interactive chat with Ollama local models using the OllamaHandler module.

.DESCRIPTION
    This script provides an interactive interface to chat with Ollama models running locally.
    It uses the OllamaHandler module for all AI interactions with support for:
    - Role-based AI personalities (CodeAssist, Legal, Teacher, etc.)
    - Audience-level language adjustment (Expert to Beginner)
    - Context file support with intelligent large file handling

.PARAMETER Model
    The name of the Ollama model to use. Defaults to "llama3.1:8b" if not specified.

.PARAMETER Role
    The AI role to assume. Options: General, CodeAssist, EconomicalAdvisor, Legal, 
    DataAnalyst, Writer, ITSupport, Teacher. Defaults to "General".

.PARAMETER Audience
    The audience level for response complexity. Options: Expert, Advanced, 
    Intermediate, Beginner, Child. Defaults to "Intermediate".

.PARAMETER ApiUrl
    The base URL for the Ollama API. Defaults to "http://localhost:11434".

.PARAMETER Temperature
    Controls randomness in the response (0.0 to 1.0). Defaults to 0.7.

.PARAMETER MaxTokens
    Maximum number of tokens to generate. Defaults to 2048.

.PARAMETER ListTemplates
    If specified, lists all available templates (local and global) and exits.

.EXAMPLE
    .\OllamaChat.ps1
    # Starts interactive chat with default model and settings

.EXAMPLE
    .\OllamaChat.ps1 -Model "gemma3:2b" -Role CodeAssist -Audience Expert
    # Starts chat configured for expert-level coding assistance

.EXAMPLE
    .\OllamaChat.ps1 -Role Teacher -Audience Beginner
    # Starts chat in educational mode with beginner-friendly language

.EXAMPLE
    .\OllamaChat.ps1 -Role EconomicalAdvisor -Temperature 0.3
    # Starts chat for financial guidance with more deterministic responses

.NOTES
    Requires Ollama to be installed and running locally.
    The script will attempt to start Ollama if it's not running.

.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Model = "llama3.1:8b",

    [Parameter()]
    [ValidateSet("General", "CodeAssist", "EconomicalAdvisor", "Legal", "DataAnalyst", "Writer", "ITSupport", "Teacher")]
    [string]$Role = "General",

    [Parameter()]
    [ValidateSet("Expert", "Advanced", "Intermediate", "Beginner", "Child")]
    [string]$Audience = "Intermediate",

    [Parameter()]
    [string]$ApiUrl = "http://localhost:11434",

    [Parameter()]
    [ValidateRange(0.0, 1.0)]
    [double]$Temperature = 0.7,

    [Parameter()]
    [int]$MaxTokens = 2048,

    [Parameter()]
    [switch]$ListTemplates
)

# Import required modules
Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
Import-Module OllamaHandler -Force -ErrorAction Stop
Import-Module SoftwareUtils -Force -ErrorAction SilentlyContinue

#region Ollama Installation Check

# Check if Ollama is installed
$ollamaPath = Get-OllamaPath
if (-not $ollamaPath) {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║              OLLAMA NOT INSTALLED                              ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Ollama is required but not installed on this system." -ForegroundColor White
    Write-Host ""
    Write-Host "  Install Ollama now? (Y/n): " -ForegroundColor Cyan -NoNewline
    $installChoice = Read-Host
    
    if ($installChoice -eq '' -or $installChoice -match '^[Yy]') {
        Write-Host ""
        Write-Host "Installing Ollama via winget..." -ForegroundColor Green
        
        # Try using Install-WingetPackage if available, otherwise use Install-Ollama
        $installed = $false
        if (Get-Command Install-WingetPackage -ErrorAction SilentlyContinue) {
            $installed = Install-WingetPackage -PackageId "Ollama.Ollama"
        }
        else {
            $installed = Install-Ollama
        }
        
        if ($installed) {
            Write-Host "  ✓ Ollama installed successfully!" -ForegroundColor Green
            
            # Refresh path
            $ollamaPath = Get-OllamaPath
            
            # Start service
            Write-Host "  Starting Ollama service..." -ForegroundColor Yellow
            Start-OllamaService | Out-Null
            Start-Sleep -Seconds 3
        }
        else {
            Write-Host "  ✗ Failed to install Ollama." -ForegroundColor Red
            Write-Host "  Please install manually: winget install Ollama.Ollama" -ForegroundColor Yellow
            exit 1
        }
    }
    else {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Check if any models are installed
$installedModels = Get-OllamaModels -ErrorAction SilentlyContinue
if ($installedModels.Count -eq 0) {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║              NO MODELS INSTALLED                               ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Ollama requires at least one model to function." -ForegroundColor White
    Write-Host ""
    Write-Host "  Recommended models:" -ForegroundColor Green
    Write-Host "    1. granite4:micro-h  (2.0 GB) - IBM Granite, optimized for CPU [DEFAULT]" -ForegroundColor White
    Write-Host "    2. llama3.2:3b       (2.0 GB) - Meta Llama 3.2, compact" -ForegroundColor White
    Write-Host "    3. phi3:mini         (2.3 GB) - Microsoft Phi-3, efficient" -ForegroundColor White
    Write-Host "    4. mistral:7b        (4.1 GB) - Mistral 7B, fast" -ForegroundColor White
    Write-Host "    5. llama3.1:8b       (4.7 GB) - Meta Llama 3.1, general purpose" -ForegroundColor White
    Write-Host "    6. codellama:7b      (3.8 GB) - Code specialized" -ForegroundColor White
    Write-Host "    0. Skip              - Don't install any model now" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Select model(s) to install (comma-separated, e.g., '1,2' or press Enter for default): " -ForegroundColor Cyan -NoNewline
    $modelChoice = Read-Host
    
    # Map choices to model names
    $modelMap = @{
        "1" = "granite4:micro-h"
        "2" = "llama3.2:3b"
        "3" = "phi3:mini"
        "4" = "mistral:7b"
        "5" = "llama3.1:8b"
        "6" = "codellama:7b"
    }
    
    $modelsToInstall = @()
    
    if ($modelChoice -eq '' -or $modelChoice -eq '1') {
        # Default: granite4:micro-h
        $modelsToInstall = @("granite4:micro-h")
    }
    elseif ($modelChoice -ne '0') {
        $selections = $modelChoice -split ',' | ForEach-Object { $_.Trim() }
        foreach ($sel in $selections) {
            if ($modelMap.ContainsKey($sel)) {
                $modelsToInstall += $modelMap[$sel]
            }
        }
    }
    
    if ($modelsToInstall.Count -gt 0) {
        Write-Host ""
        Write-Host "Installing selected model(s)..." -ForegroundColor Green
        Install-OllamaModelBatch -ModelNames $modelsToInstall
        
        # Update the Model parameter to use an installed model
        $installedModels = Get-OllamaModels -ErrorAction SilentlyContinue
        if ($installedModels.Count -gt 0 -and $Model -notin $installedModels) {
            $Model = $installedModels[0]
        }
    }
    elseif ($modelChoice -eq '0') {
        Write-Host ""
        Write-Host "Skipping model installation. You can install models later with:" -ForegroundColor Yellow
        Write-Host "  ollama pull <model-name>" -ForegroundColor White
        exit 0
    }
}

#endregion

# List templates if requested
if ($ListTemplates) {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              OLLAMA PROMPT TEMPLATES                           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    $allTemplates = Get-OllamaTemplates
    
    if ($allTemplates.Count -eq 0) {
        Write-Host "  No templates found." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Template locations:" -ForegroundColor Yellow
        Write-Host "    Local:  $env:OptPath\data\OllamaTemplates\OllamaTemplates.json" -ForegroundColor White
        $globalPath = Get-OllamaTemplatesJsonFilename
        if ($globalPath) {
            Write-Host "    Global: $globalPath" -ForegroundColor White
        }
    }
    else {
        Write-Host "  Found $($allTemplates.Count) template(s):" -ForegroundColor Green
        Write-Host ""
        
        # Group by source
        $localTemplates = $allTemplates | Where-Object { $_.Source -eq "Local" }
        $globalTemplates = $allTemplates | Where-Object { $_.Source -eq "Global" }
        
        if ($localTemplates.Count -gt 0) {
            Write-Host "  ─── LOCAL TEMPLATES ───" -ForegroundColor Cyan
            foreach ($tmpl in $localTemplates) {
                Write-Host "    • $($tmpl.Name)" -ForegroundColor Yellow
                if ($tmpl.Description) {
                    Write-Host "      $($tmpl.Description)" -ForegroundColor DarkGray
                }
            }
            Write-Host ""
        }
        
        if ($globalTemplates.Count -gt 0) {
            Write-Host "  ─── GLOBAL TEMPLATES ───" -ForegroundColor Magenta
            foreach ($tmpl in $globalTemplates) {
                Write-Host "    • $($tmpl.Name)" -ForegroundColor Yellow
                if ($tmpl.Description) {
                    Write-Host "      $($tmpl.Description)" -ForegroundColor DarkGray
                }
            }
            Write-Host ""
        }
        
        Write-Host "  Usage in chat: /use <TemplateName>" -ForegroundColor DarkGray
        Write-Host "  Usage in script: Invoke-Ollama -Template <TemplateName> -ContextFiles @('file.txt')" -ForegroundColor DarkGray
    }
    Write-Host ""
    exit 0
}

# Start interactive chat using the module function
try {
    Start-OllamaChat -Model $Model -Role $Role -Audience $Audience -ApiUrl $ApiUrl -Temperature $Temperature -MaxTokens $MaxTokens
}
catch {
    Write-LogMessage "Chat session error" -Level ERROR -Exception $_
    exit 1
}
