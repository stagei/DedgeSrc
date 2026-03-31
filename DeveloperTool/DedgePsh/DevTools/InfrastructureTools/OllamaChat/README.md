# Ollama Chat Interface

This directory contains PowerShell scripts for interacting with Ollama models using the OllamaHandler module.

## Author

Geir Helge Starholm, www.dEdge.no

## Prerequisites

1. **Ollama Installation**: Make sure Ollama is installed on your system
   ```powershell
   winget install Ollama.Ollama
   ```

2. **Ollama Service**: Start the Ollama service
   ```powershell
   ollama serve
   ```

3. **Models**: Install at least one model
   ```powershell
   ollama pull llama3.1:8b
   # or
   ollama pull gemma3:2b
   ```

## Scripts

### 1. OllamaChat.ps1 - Interactive Chat Interface

A full-featured interactive chat interface with:

- **Role-based AI personalities** (CodeAssist, Legal, Teacher, etc.)
- **Audience-level language adjustment** (Expert to Child)
- **Model switching** during the session
- **Context file support** with intelligent large file handling
- **Built-in commands** for session management

#### Usage Examples:

```powershell
# Start interactive chat with default settings
.\OllamaChat.ps1

# Start chat with specific model
.\OllamaChat.ps1 -Model "gemma3:2b"

# Start as coding assistant with expert-level responses
.\OllamaChat.ps1 -Role CodeAssist -Audience Expert

# Start as teacher with beginner-friendly language
.\OllamaChat.ps1 -Role Teacher -Audience Beginner

# Financial advisor mode
.\OllamaChat.ps1 -Role EconomicalAdvisor -Temperature 0.3
```

#### Interactive Commands:

- `/help` - Show available commands
- `/models` - List available models
- `/roles` - List available AI roles
- `/audience` - List and change audience levels
- `/switch` - Switch to a different model
- `/role <name>` - Change current role (e.g., `/role CodeAssist`)
- `/context` - Add a context file
- `/status` - Show current settings
- `/clear` - Clear chat history
- `/quit` - Exit the chat

### 2. Ask-Ollama.ps1 - Single Question Interface

A script for asking single questions without starting an interactive session. Perfect for scripting and automation.

#### Usage Examples:

```powershell
# Ask a simple question
.\Ask-Ollama.ps1 -Question "What is PowerShell?"

# Ask with specific model and role
.\Ask-Ollama.ps1 -Question "Write a PowerShell function to list files" -Role CodeAssist

# Get beginner-friendly explanation
.\Ask-Ollama.ps1 -Question "Explain recursion" -Role Teacher -Audience Child

# Include context files
.\Ask-Ollama.ps1 -Question "Review this code" -Role CodeAssist -ContextFiles @(".\script.ps1")

# Get raw response for scripting (no formatting)
$result = .\Ask-Ollama.ps1 -Question "Generate a function name" -Raw -Quiet
```

## Available AI Roles

| Role | Best For |
|------|----------|
| `General` | Everyday tasks and questions |
| `CodeAssist` | Programming, debugging, code reviews |
| `EconomicalAdvisor` | Financial analysis, budgeting |
| `Legal` | Legal concepts (not legal advice) |
| `DataAnalyst` | Data analysis, SQL, statistics |
| `Writer` | Content creation, editing |
| `ITSupport` | Troubleshooting, system admin |
| `Teacher` | Educational explanations |

## Audience Levels

| Level | Description |
|-------|-------------|
| `Expert` | Technical jargon, advanced concepts |
| `Advanced` | Professional, detailed explanations |
| `Intermediate` | Balanced, explains terms when used |
| `Beginner` | Simple language, step-by-step |
| `Child` | Very simple, fun analogies |

## Context Files

Include files as context for your queries:

```powershell
# Single file
.\Ask-Ollama.ps1 -Question "What does this do?" -ContextFiles @(".\MyScript.ps1")

# Multiple files
.\Ask-Ollama.ps1 -Question "Find issues" -ContextFiles @(".\config.json", ".\main.ps1")
```

### Large File Handling

When files exceed ~50KB, the module automatically:
1. Analyzes the file structure
2. Asks the AI what parts are relevant
3. Extracts only necessary portions

## OllamaHandler Module

These scripts use the `OllamaHandler` module located in `_Modules\OllamaHandler`. You can also use the module directly in your scripts:

```powershell
Import-Module OllamaHandler

# Quick query
$answer = Invoke-Ollama "Explain this error" -Role CodeAssist -Raw

# With full response object
$result = Invoke-Ollama "Analyze this data" -Role DataAnalyst -ContextFiles @(".\data.csv")
if ($result.Success) {
    Write-Host $result.Response
}

# Model management
Get-OllamaModels -IncludeDetails
Set-OllamaPort -Port 8080 -Persist
Set-OllamaModelsPath -Path "D:\Models" -Persist -CreateIfMissing
```

## Batch Processing Example

```powershell
$questions = @(
    "What is PowerShell?",
    "How do I install modules?",
    "Explain error handling"
)

foreach ($q in $questions) {
    $result = .\Ask-Ollama.ps1 -Question $q -Role Teacher -Audience Beginner -Raw -Quiet
    "Q: $q`nA: $result`n" | Out-File -Append .\qa-output.txt
}
```

## Automated Code Review Example

```powershell
Get-ChildItem .\*.ps1 | ForEach-Object {
    $review = .\Ask-Ollama.ps1 -Question "Review for bugs and best practices" `
        -Role CodeAssist `
        -ContextFiles @($_.FullName) `
        -Raw -Quiet
    
    "# $($_.Name)`n$review`n---`n" | Out-File -Append .\code-review.md
}
```

## Troubleshooting

### Common Issues:

1. **"Ollama service is not running"**
   - Start Ollama: `ollama serve`
   - Or use: `Start-OllamaService` from the module

2. **"Model not found"**
   - Install the model: `ollama pull <model-name>`
   - List available: `Get-OllamaModels`

3. **"Connection refused"**
   - Ensure Ollama is running
   - Check firewall settings
   - Verify the API URL: `Get-OllamaConfiguration`

4. **Slow responses with large files**
   - The module automatically extracts relevant portions
   - Consider using more specific queries
   - Use smaller models for faster responses

## API Reference

The scripts use the Ollama REST API on `http://localhost:11434` by default.

See the main module documentation in `_Modules\OllamaHandler\README.md` for complete API details.

## Integration

These scripts integrate with the DedgePsh infrastructure:

- Uses `GlobalFunctions` module for logging (`Write-LogMessage`)
- Uses `OllamaHandler` module for all AI interactions
- Follows standard deployment patterns
