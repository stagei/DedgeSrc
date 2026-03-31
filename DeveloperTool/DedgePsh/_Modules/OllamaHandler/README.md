# OllamaHandler PowerShell Module

A comprehensive PowerShell module for interacting with Ollama AI models locally. Provides both programmatic API access for scripts and an interactive chat interface with role-based AI personalities, prompt templates, and intelligent context handling.

## Author

Geir Helge Starholm, www.dEdge.no

## Features

- **Role-Based AI Personalities**: 8 predefined roles with optimized system prompts
- **Audience-Level Adaptation**: Adjust language complexity from Expert to Child
- **Prompt Templates**: Save and reuse prompts with local and global template support
- **Context File Support**: Include files with intelligent large file extraction
- **Multi-Line Input**: Paste multi-line text and code blocks
- **Chat Export**: Save conversations to markdown (AI-only or full dialog)
- **Model Library Browser**: Browse and install models from Ollama library
- **Model Management**: List, configure, and switch between models
- **Firewall Configuration**: Configure Windows Firewall for Ollama
- **Configuration Management**: Change Ollama port and models path programmatically
- **Export/Import**: Transfer models to airgapped servers
- **Auto-Installation**: Install Ollama via winget if missing
- **Interactive Chat**: Full-featured chat interface with commands

## Prerequisites

1. **Ollama Installation** (will auto-install if missing)
   ```powershell
   winget install Ollama.Ollama
   ```

2. **Start Ollama Service**
   ```powershell
   ollama serve
   ```

3. **Install at least one model**
   ```powershell
   ollama pull llama3.1:8b
   ```

## Installation

The module is installed via the standard deployment process:

```powershell
Import-Module OllamaHandler -Force
```

## Quick Start

### Simple Query

```powershell
Import-Module OllamaHandler

# Ask a question
Invoke-Ollama "What is PowerShell?" -Raw
```

### Using Templates

```powershell
# List available templates
Get-OllamaTemplates

# Use a template with context files and save output
$response = Invoke-Ollama -Template "CreateBankTerminalOrderReport" `
                          -ContextFiles @("C:\logs\transaction.log") `
                          -Raw
$response | Set-Content "TransactionReport.md" -Encoding UTF8
```

### With Role and Audience

```powershell
# Get coding help with expert-level response
Invoke-Ollama "Explain async/await" -Role CodeAssist -Audience Expert

# Get financial advice in simple terms
Invoke-Ollama "What is compound interest?" -Role EconomicalAdvisor -Audience Beginner
```

### With Context Files

```powershell
# Code review with file context
Invoke-Ollama "Review this script for best practices" -Role CodeAssist -ContextFiles @(".\MyScript.ps1")

# Analyze multiple files
Invoke-Ollama "Compare these files" -ContextFiles @(".\file1.ps1", ".\file2.ps1") -Raw
```

### Generate Reports

```powershell
# Generate a markdown report from log files
$report = Invoke-Ollama -Template "CreateBankTerminalOrderReport" `
                        -ContextFiles @("C:\logs\order.log", "C:\logs\payment.log") `
                        -Model "llama3.1:latest" `
                        -MaxTokens 8192 `
                        -Raw

$report | Set-Content "C:\reports\TransactionReport_$(Get-Date -Format 'yyyyMMdd').md"
```

### Interactive Chat

```powershell
# Start default chat
Start-OllamaChat

# Start with specific role
Start-OllamaChat -Role Teacher -Audience Beginner

# List templates before starting
.\OllamaChat.ps1 -ListTemplates
```

## Available Functions

### Core Functions

| Function | Description |
|----------|-------------|
| `Invoke-Ollama` | Main function for AI queries with role/audience/template support |
| `Invoke-OllamaGenerate` | Low-level API call for direct model interaction |
| `Start-OllamaChat` | Interactive chat session with commands |

### Template Functions

| Function | Description |
|----------|-------------|
| `Get-OllamaTemplates` | List templates from local and global sources |
| `Save-OllamaTemplate` | Save a prompt as a reusable template |
| `Remove-OllamaTemplate` | Remove a template from local storage |
| `Get-OllamaTemplatesJsonFilename` | Get path to global templates file |

### Installation Functions

| Function | Description |
|----------|-------------|
| `Get-OllamaPath` | Get Ollama executable path |
| `Install-Ollama` | Install Ollama via winget |

### Service Functions

| Function | Description |
|----------|-------------|
| `Test-OllamaService` | Check if Ollama is running |
| `Start-OllamaService` | Start Ollama service |

### Model Management

| Function | Description |
|----------|-------------|
| `Get-OllamaModels` | List installed models with details |
| `Get-OllamaConfiguration` | Get current Ollama settings |
| `Set-OllamaPort` | Change Ollama API port |
| `Set-OllamaModelsPath` | Change models storage location |

### Model Library & Installation

| Function | Description |
|----------|-------------|
| `Get-OllamaModelLibrary` | Fetch models from ollama.com |
| `Get-OllamaRecommendedModels` | Get curated model list |
| `Select-OllamaModelsToInstall` | Interactive model browser |
| `Install-OllamaModelBatch` | Install multiple models |

### Export/Import (Airgapped Servers)

| Function | Description |
|----------|-------------|
| `Export-OllamaModel` | Export model to ZIP for transfer |
| `Import-OllamaModel` | Import model from ZIP file |

### Firewall Configuration

| Function | Description |
|----------|-------------|
| `Set-OllamaFirewallRules` | Configure Windows Firewall for Ollama |
| `Get-OllamaFirewallRules` | List current Ollama firewall rules |
| `Remove-OllamaFirewallRules` | Remove all Ollama firewall rules |

### Role & Audience

| Function | Description |
|----------|-------------|
| `Get-OllamaRoles` | List available AI roles |
| `Get-OllamaAudienceLevels` | List audience levels |

## Invoke-Ollama Parameters

| Parameter | Description |
|-----------|-------------|
| `-Prompt` | The question or instruction to send |
| `-Template` | Named template to use (from local/global templates) |
| `-Model` | Ollama model to use (auto-selects if not specified) |
| `-Role` | AI persona: General, CodeAssist, EconomicalAdvisor, Legal, DataAnalyst, Writer, ITSupport, Teacher |
| `-Audience` | Language level: Expert, Advanced, Intermediate, Beginner, Child |
| `-ContextFiles` | Array of file paths to include as context |
| `-SystemPrompt` | Custom system prompt (overrides Role) |
| `-Temperature` | Response creativity 0.0-1.0 (default: 0.7) |
| `-MaxTokens` | Maximum response length (default: 4096) |
| `-Raw` | Return plain text instead of PSCustomObject |

## Template System

### Template Locations

- **Local**: `$env:OptPath\data\OllamaTemplates\OllamaTemplates.json`
- **Global**: `\\<server>\DedgeCommon\Configfiles\OllamaTemplates.json`

### Using Templates in Scripts

```powershell
# List all templates
Get-OllamaTemplates

# Get specific template
Get-OllamaTemplates -TemplateName "CreateBankTerminalOrderReport"

# Use template with context files
$response = Invoke-Ollama -Template "MyTemplate" -ContextFiles @("data.txt") -Raw
$response | Set-Content "output.md" -Encoding UTF8
```

### Creating Templates

```powershell
# Save a new template
Save-OllamaTemplate -Name "CodeReview" `
                    -Prompt "Review this code for bugs, security issues, and best practices. Provide specific line numbers and suggestions." `
                    -Description "Comprehensive code review template" `
                    -Category "Development"

# Remove a template
Remove-OllamaTemplate -Name "OldTemplate"
```

### Using Templates in Chat

```
You: /templates              # List all templates
You: /use MyTemplate         # Apply a template
You: /savetemp NewTemplate   # Save last prompt as template
```

## AI Roles

| Role | Description |
|------|-------------|
| `General` | General-purpose helpful assistant |
| `CodeAssist` | Expert programming assistant |
| `EconomicalAdvisor` | Financial and economic guidance |
| `Legal` | Legal information (not legal advice) |
| `DataAnalyst` | Data analysis and statistics |
| `Writer` | Writing and editing assistance |
| `ITSupport` | IT troubleshooting and sysadmin |
| `Teacher` | Educational tutoring |

## Audience Levels

| Level | Description |
|-------|-------------|
| `Expert` | Technical jargon, advanced concepts |
| `Advanced` | Professional language, detailed |
| `Intermediate` | Balanced, explains technical terms |
| `Beginner` | Simple language, step-by-step |
| `Child` | Very simple, fun analogies |

## Interactive Chat Commands

| Command | Description |
|---------|-------------|
| `/help` | Show all commands |
| `/models` | List available models |
| `/switch` | Switch to different model |
| `/roles` | List available roles |
| `/role <name>` | Change current role |
| `/audience` | Change audience level |
| `/temp <0.0-1.0>` | Set temperature (creativity) |
| `/tokens <num>` | Set max tokens (response length) |
| `@filepath` | Add file as context |
| `/paste` | Enter multi-line text mode |
| `/templates` | List available templates |
| `/use <name>` | Apply a template as prompt |
| `/savetemp <name>` | Save last prompt as template |
| `/save [file]` | Save AI responses to markdown |
| `/save full [file]` | Save full dialog to markdown |
| `/status` | Show current settings |
| `/clear` | Clear chat history |
| `/quit` | Exit chat |

### Adding Context Files

```
You: @readme.md
  + Added context: readme.md

You: @"C:\path with spaces\file.txt" Summarize this
  + Added context: file.txt
  
You: @file1.ps1 @file2.ps1 Compare these files
  + Added context: file1.ps1
  + Added context: file2.ps1
```

### Multi-Line Input

```
You: /paste
Paste your text and press Enter twice to send:
─────────────────────────────────────────
function Get-Example {
    param($Name)
    return "Hello $Name"
}

─────────────────────────────────────────
Received 4 line(s)
```

### Saving Chat to Markdown

```
You: /save                    # Save AI responses only
You: /save myreport           # Save to myreport.md
You: /save full               # Save full dialog
You: /save full transcript    # Save dialog to transcript.md
```

## Firewall Configuration

Configure Windows Firewall for Ollama (requires Administrator):

```powershell
# Create all necessary firewall rules
Set-OllamaFirewallRules

# View current rules
Get-OllamaFirewallRules

# Remove all Ollama rules
Remove-OllamaFirewallRules

# Skip browser rules
Set-OllamaFirewallRules -SkipBrowserRules
```

Rules created:
- Inbound: Ollama API port (configured port)
- Outbound: Ollama process for model downloads
- Outbound: Edge browser for ollama.com/org access

## Intelligent Context Extraction

When context files are larger than ~50KB, the module:

1. Creates a structural preview of the file
2. Asks the AI what parts are relevant to your query
3. Extracts only the relevant portions automatically

Extraction methods include:
- **Regex patterns** - Extract lines matching a pattern
- **Line ranges** - Extract specific line numbers
- **First N lines** - Use beginning of file
- **Full file** - If AI determines full context needed

## Usage Examples

### Generate Report from Log Files

```powershell
Import-Module OllamaHandler

# Use template with context file
$response = Invoke-Ollama -Template "CreateBankTerminalOrderReport" `
                          -ContextFiles @("C:\logs\transaction.log") `
                          -MaxTokens 8192 `
                          -Raw

# Save to markdown
$response | Set-Content "TransactionReport.md" -Encoding UTF8
```

### Automated Code Review

```powershell
$scripts = Get-ChildItem .\*.ps1
foreach ($script in $scripts) {
    $review = Invoke-Ollama "Review for bugs and improvements" `
        -Role CodeAssist `
        -ContextFiles @($script.FullName) `
        -Raw
    
    "$($script.Name):`n$review`n" | Out-File -Append .\code-review.md
}
```

### Document Summarization

```powershell
$doc = ".\annual-report.txt"

$expertSummary = Invoke-Ollama "Summarize key financial points" `
    -Role EconomicalAdvisor -Audience Expert -ContextFiles @($doc) -Raw

$publicSummary = Invoke-Ollama "Summarize for public stakeholders" `
    -Role EconomicalAdvisor -Audience Beginner -ContextFiles @($doc) -Raw
```

### Airgapped Server Transfer

```powershell
# On connected machine: Export model
$exportPath = Export-OllamaModel -ModelName "llama3.1:8b"

# On airgapped server: Import model
Import-OllamaModel -ModelPath "C:\Transfer\llama3.1-8b.zip"
```

## Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `OLLAMA_HOST` | Host and port (default: `localhost:11434`) |
| `OLLAMA_MODELS` | Models storage path |

### Setting Persistent Configuration

```powershell
# Change port permanently
Set-OllamaPort -Port 8080 -Persist

# Change models path permanently  
Set-OllamaModelsPath -Path "E:\Models\Ollama" -Persist -CreateIfMissing
```

## Troubleshooting

### "Ollama service not running"

```powershell
Test-OllamaService
Start-OllamaService
# Or manually: ollama serve
```

### "Ollama not installed"

```powershell
Install-Ollama
# Or: Get-OllamaPath -InstallIfMissing
```

### "Template not found"

```powershell
# Check template locations
Get-OllamaTemplates

# Verify local template file exists
Test-Path "$env:OptPath\data\OllamaTemplates\OllamaTemplates.json"
```

## Related Files

- `DevTools\InfrastructureTools\OllamaChat\OllamaChat.ps1` - Interactive chat launcher
- `DevTools\InfrastructureTools\OllamaChat\Ask-Ollama.ps1` - Single-question CLI tool
- `DevTools\AI\Ollama-ConfigureFirewall\Ollama-ConfigureFirewall.ps1` - Firewall configuration
- `DevTools\AI\Ollama-TemplateTest\Test-BankTerminalReport.ps1` - Template test script
