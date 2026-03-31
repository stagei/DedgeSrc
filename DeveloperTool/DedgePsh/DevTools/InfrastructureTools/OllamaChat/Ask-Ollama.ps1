#Requires -Version 5.1

<#
.SYNOPSIS
    Ask a single question to an Ollama model using the OllamaHandler module.

.DESCRIPTION
    This script sends a single prompt to an Ollama model and returns the response.
    It's designed for use in scripts and automation with support for:
    - Role-based AI personalities (CodeAssist, Legal, Teacher, etc.)
    - Audience-level language adjustment (Expert to Beginner)
    - Context file support with intelligent large file handling
    - Structured or raw output for scripting

.PARAMETER Question
    The question or prompt to send to the model.

.PARAMETER Model
    The name of the Ollama model to use. Defaults to "llama3.1:8b".

.PARAMETER Role
    The AI role to assume. Options: General, CodeAssist, EconomicalAdvisor, Legal, 
    DataAnalyst, Writer, ITSupport, Teacher. Defaults to "General".

.PARAMETER Audience
    The audience level for response complexity. Options: Expert, Advanced, 
    Intermediate, Beginner, Child. Defaults to "Intermediate".

.PARAMETER ContextFiles
    Array of file paths to include as context for the query.

.PARAMETER ApiUrl
    The base URL for the Ollama API. Defaults to "http://localhost:11434".

.PARAMETER SystemPrompt
    Optional custom system prompt (overrides Role-based prompt).

.PARAMETER Temperature
    Controls randomness in the response (0.0 to 1.0). Defaults to 0.7.

.PARAMETER MaxTokens
    Maximum number of tokens to generate. Defaults to 2048.

.PARAMETER Raw
    If specified, returns only the response text without metadata.

.PARAMETER Quiet
    If specified, suppresses informational output (useful for scripting).

.EXAMPLE
    .\Ask-Ollama.ps1 -Question "What is PowerShell?"
    # Ask a simple question with default settings

.EXAMPLE
    .\Ask-Ollama.ps1 -Question "Review this code" -Role CodeAssist -ContextFiles @(".\script.ps1")
    # Code review with context file

.EXAMPLE
    .\Ask-Ollama.ps1 -Question "Explain recursion" -Role Teacher -Audience Child
    # Get a child-friendly explanation

.EXAMPLE
    $result = .\Ask-Ollama.ps1 -Question "Generate SQL query" -Role DataAnalyst -Raw -Quiet
    # Get raw response for use in another script

.EXAMPLE
    .\Ask-Ollama.ps1 -Question "Analyze quarterly report" -Role EconomicalAdvisor -ContextFiles @(".\report.xlsx") -Audience Expert
    # Financial analysis with context

.NOTES
    Requires Ollama to be installed and running locally.
    
.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
    [string]$Question,

    [Parameter()]
    [string]$Model = "llama3.1:8b",

    [Parameter()]
    [ValidateSet("General", "CodeAssist", "EconomicalAdvisor", "Legal", "DataAnalyst", "Writer", "ITSupport", "Teacher")]
    [string]$Role = "General",

    [Parameter()]
    [ValidateSet("Expert", "Advanced", "Intermediate", "Beginner", "Child")]
    [string]$Audience = "Intermediate",

    [Parameter()]
    [string[]]$ContextFiles = @(),

    [Parameter()]
    [string]$ApiUrl = "http://localhost:11434",

    [Parameter()]
    [string]$SystemPrompt = "",

    [Parameter()]
    [ValidateRange(0.0, 1.0)]
    [double]$Temperature = 0.7,

    [Parameter()]
    [int]$MaxTokens = 2048,

    [Parameter()]
    [switch]$Raw,

    [Parameter()]
    [switch]$Quiet
)

# Import required modules
Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
Import-Module OllamaHandler -Force -ErrorAction Stop
Import-Module SoftwareUtils -Force -ErrorAction SilentlyContinue

#region Ollama Installation Check

# Check if Ollama is installed
$ollamaPath = Get-OllamaPath
if (-not $ollamaPath) {
    if (-not $Quiet) {
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
    else {
        # Quiet mode - try auto-install
        if (Get-Command Install-WingetPackage -ErrorAction SilentlyContinue) {
            Install-WingetPackage -PackageId "Ollama.Ollama" | Out-Null
        }
        else {
            Install-Ollama | Out-Null
        }
        Start-OllamaService | Out-Null
        Start-Sleep -Seconds 3
    }
}

# Check if any models are installed
$installedModels = Get-OllamaModels -ErrorAction SilentlyContinue
if ($installedModels.Count -eq 0) {
    if (-not $Quiet) {
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
    else {
        # Quiet mode - auto-install default model
        Install-OllamaModelBatch -ModelNames @("granite4:micro-h") | Out-Null
        $installedModels = Get-OllamaModels -ErrorAction SilentlyContinue
        if ($installedModels.Count -gt 0) {
            $Model = $installedModels[0]
        }
    }
}

#endregion

try {
    # Display header unless quiet mode
    if (-not $Quiet) {
        Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                   OLLAMA QUERY                                 ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Model:    $Model" -ForegroundColor Yellow
        Write-Host "  Role:     $Role" -ForegroundColor Yellow
        Write-Host "  Audience: $Audience" -ForegroundColor Yellow
        if ($ContextFiles.Count -gt 0) {
            Write-Host "  Context:  $($ContextFiles.Count) file(s)" -ForegroundColor Yellow
        }
        Write-Host "  Question: $Question" -ForegroundColor Blue
        Write-Host ""
        Write-Host "Generating response..." -ForegroundColor Green
    }

    # Build parameters
    $invokeParams = @{
        Prompt = $Question
        Model = $Model
        Role = $Role
        Audience = $Audience
        ApiUrl = $ApiUrl
        Temperature = $Temperature
        MaxTokens = $MaxTokens
    }

    if ($ContextFiles.Count -gt 0) {
        $invokeParams.ContextFiles = $ContextFiles
    }

    if ($SystemPrompt) {
        $invokeParams.SystemPrompt = $SystemPrompt
    }

    # Invoke Ollama
    if ($Raw) {
        $response = Invoke-Ollama @invokeParams -Raw
        
        if ($Quiet) {
            # Just output the response directly
            $response
        }
        else {
            Write-Host ""
            Write-Host "Response:" -ForegroundColor Green
            Write-Host $response -ForegroundColor White
        }
        
        return $response
    }
    else {
        $result = Invoke-Ollama @invokeParams
        
        if (-not $Quiet) {
            Write-Host ""
            if ($result.Success) {
                Write-Host "Response:" -ForegroundColor Green
                Write-Host $result.Response -ForegroundColor White
                
                # Show metadata
                Write-Host ""
                Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                Write-Host "  Model: $($result.Model) | Role: $($result.Role) | Audience: $($result.Audience)" -ForegroundColor DarkGray
                if ($result.ContextFiles.Count -gt 0) {
                    Write-Host "  Context Files: $($result.ContextFiles.FileName -join ', ')" -ForegroundColor DarkGray
                }
            }
            else {
                Write-Host "Error: $($result.Error)" -ForegroundColor Red
            }
        }
        
        return $result
    }
}
catch {
    if ($Quiet) {
        return $null
    }
    Write-LogMessage "Query error" -Level ERROR -Exception $_
    exit 1
}
