# Cursor Agent CLI -- Comprehensive Guide

The Cursor Agent CLI lets you use Cursor's AI models from the terminal or from scripts.
It supports all the same models as the IDE (Claude, GPT, Gemini, Grok) and can read files,
run commands, and write code -- all without opening the editor.

## Installation

```powershell
# Windows (PowerShell 7+)
irm 'https://cursor.com/install?win32=true' | iex

# Verify
agent --version
```

The agent binary is installed to `%LOCALAPPDATA%\cursor-agent\`.

## Authentication

```powershell
# Interactive login (opens browser, one-time)
agent login

# Check status
agent status

# API key (for automation / CI)
$env:CURSOR_API_KEY = "your-api-key-here"
```

Generate API keys at https://cursor.com/dashboard/cloud-agents under "User API Keys".

## Core Concepts

### Interactive vs Headless Mode

| Mode | How | Use Case |
|------|-----|----------|
| Interactive | `agent` (no flags) | Chat-style terminal session |
| Headless | `agent -p` / `--print` | Scripts, automation, CI pipelines |

In headless mode (`-p`), the prompt **must be piped through stdin** on Windows.
Passing the prompt as a positional argument will hang.

```powershell
# CORRECT -- pipe through stdin
"What is 2+2?" | agent -p --trust

# WRONG on Windows -- hangs indefinitely
agent -p --trust "What is 2+2?"
```

### Output Formats (`--output-format`)

| Format | Description | Use |
|--------|-------------|-----|
| `text` | Final answer only, plain text | Human-readable, simple scripts |
| `json` | Single JSON object after completion | Programmatic parsing |
| `stream-json` | NDJSON, one event per line | Real-time progress tracking |

---

## Parameter Reference

### Global Options

| Flag | Short | Description |
|------|-------|-------------|
| `--print` | `-p` | Headless mode, output to stdout |
| `--model <name>` | | Select a specific model |
| `--mode <mode>` | | `ask` (read-only), `plan` (planning) |
| `--output-format <fmt>` | | `text`, `json`, or `stream-json` |
| `--trust` | | Skip workspace trust prompt (headless) |
| `--workspace <path>` | | Set working directory |
| `--force` | `-f` | Allow file edits and commands without confirmation |
| `--yolo` | | Alias for `--force` |
| `--api-key <key>` | | API key for auth (or use `CURSOR_API_KEY` env var) |
| `--resume [chatId]` | | Resume a previous session |
| `--continue` | | Resume the most recent session |
| `--cloud` | `-c` | Run in Cursor Cloud (background) |
| `--sandbox <mode>` | | `enabled` or `disabled` |
| `--approve-mcps` | | Auto-approve all MCP servers |
| `--stream-partial-output` | | Character-level streaming (with `stream-json`) |
| `--list-models` | | List all available models and exit |

### Commands

| Command | Description |
|---------|-------------|
| `agent` | Start interactive agent (default) |
| `agent login` | Authenticate via browser |
| `agent logout` | Clear stored credentials |
| `agent status` | Show auth status |
| `agent models` | List available models |
| `agent about` | Version, system, and account info |
| `agent update` | Update to latest version |
| `agent ls` | List previous chat sessions |
| `agent resume` | Resume most recent session |
| `agent mcp list` | List configured MCP servers |
| `agent mcp list-tools <server>` | List tools for an MCP server |

---

## Examples

### 1. Simple Question (Text Output)

```powershell
"Explain INNER JOIN vs LEFT JOIN in SQL" | agent -p --trust --output-format text
```

Output:
```
An INNER JOIN returns only rows that have matching values in both tables...
```

### 2. Simple Question (JSON Output)

```powershell
$raw = "What is 2+2?" | agent -p --trust --output-format json
$result = $raw | ConvertFrom-Json
Write-Host "Answer: $($result.result)"
Write-Host "Took: $($result.duration_ms)ms"
```

JSON envelope:
```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 5234,
  "result": "4",
  "session_id": "c6b62c6f-...",
  "request_id": "10e11780-..."
}
```

### 3. Choose a Specific Model

```powershell
# Use Claude Sonnet
"Explain monads in simple terms" | agent -p --trust --model "claude-4.5-sonnet" --output-format text

# Use GPT-5.4
"Write a Python fibonacci function" | agent -p --trust --model "gpt-5.4-medium" --output-format text

# Use a fast model for simple tasks
"Is 'hello' a palindrome?" | agent -p --trust --model "gpt-5.4-nano-low" --output-format text
```

List all available models:
```powershell
agent models
```

### 4. Embed File Content in the Prompt

The most reliable way to give the model file context is to embed the content
directly in the prompt text:

```powershell
$code = Get-Content "C:\src\MyApp\Program.cs" -Raw
$prompt = @"
Review this C# code for potential bugs and security issues:

$code
"@
$prompt | agent -p --trust --model "composer-2" --output-format text
```

### 5. Embed Multiple Files

```powershell
$files = @("src\Models\User.cs", "src\Services\AuthService.cs", "src\Controllers\LoginController.cs")
$prompt = "Review these files for security issues:`n"
foreach ($f in $files) {
    $content = Get-Content $f -Raw
    $prompt += "`n--- FILE: $($f) ---`n$($content)`n--- END ---`n"
}
$prompt | agent -p --trust --mode ask --output-format text
```

### 6. Workspace Context (Agent Reads Files Itself)

Instead of embedding files, you can set a workspace and let the agent read files
using its built-in tools:

```powershell
"List all public API endpoints in this ASP.NET project" |
    agent -p --trust --workspace "C:\src\MyWebApp" --mode ask --output-format text
```

The agent will use its Read and Grep tools to explore the workspace.

### 7. Ask Mode (Read-Only)

Ask mode prevents the agent from modifying files -- ideal for analysis:

```powershell
"What does this codebase do? Summarize the architecture." |
    agent -p --trust --workspace "C:\src\MyProject" --mode ask --output-format text
```

### 8. Force Mode (Allow File Edits)

Combine `--force` with `--print` to let the agent edit files without confirmation:

```powershell
"Add XML documentation comments to all public methods in Program.cs" |
    agent -p --trust --force --workspace "C:\src\MyApp" --output-format text
```

**Warning:** `--force` allows the agent to modify files and run shell commands
without asking. Only use in trusted environments.

### 9. Batch Processing

```powershell
$scripts = Get-ChildItem "C:\src\scripts" -Filter "*.ps1"
foreach ($script in $scripts) {
    $content = Get-Content $script.FullName -Raw
    $prompt = "Add error handling to this PowerShell script:`n`n$content"
    $raw = $prompt | agent -p --trust --force --model "composer-2" --output-format json
    $result = ($raw | ConvertFrom-Json).result
    Write-Host "=== $($script.Name) ===" -ForegroundColor Cyan
    Write-Host $result
}
```

### 10. Stream JSON for Progress Tracking

```powershell
$events = "Analyze this project and create a summary" |
    agent -p --trust --workspace "C:\src\MyProject" --output-format stream-json

foreach ($line in $events) {
    $event = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $event) { continue }

    switch ($event.type) {
        'system'    { Write-Host "Model: $($event.model)" -ForegroundColor DarkGray }
        'assistant' { Write-Host $event.message.content[0].text }
        'tool_call' {
            if ($event.subtype -eq 'started') {
                Write-Host "  Tool: reading file..." -ForegroundColor Yellow
            }
        }
        'result'    { Write-Host "Done in $($event.duration_ms)ms" -ForegroundColor Green }
    }
}
```

### 11. Resume a Previous Session

```powershell
# List previous sessions
agent ls

# Resume the most recent session
agent resume

# Resume a specific session by ID
"Continue where we left off" | agent -p --trust --resume "c6b62c6f-7ead-4fd6-..."
```

### 12. Cloud Agent (Background Execution)

```powershell
# Start a task in the cloud
"Refactor the auth module and add tests" |
    agent -p --trust --cloud --workspace "C:\src\MyProject"
```

Monitor at https://cursor.com/agents.

### 13. Extract Structured Data from Source Code

```powershell
$source = Get-Content "C:\src\legacy\PROGRAM.CBL" -Raw
$prompt = @"
Extract all SQL table references from this COBOL program.
Return a JSON array of objects: [{"schema":"DBM","table":"ORDREHODE","operation":"SELECT"}]
Return ONLY the JSON array, no explanation.

$source
"@

$raw = $prompt | agent -p --trust --model "composer-2" --mode ask --output-format json
$envelope = $raw | ConvertFrom-Json
$tables = $envelope.result | ConvertFrom-Json
$tables | Format-Table -AutoSize
```

### 14. Code Review with File Diff

```powershell
$diff = git diff HEAD~1 | Out-String
$prompt = @"
Review this git diff. Focus on:
- Potential bugs
- Security issues
- Performance concerns

$diff
"@
$prompt | agent -p --trust --model "claude-4.5-sonnet" --mode ask --output-format text
```

### 15. Using in a PowerShell Function

```powershell
function Ask-Cursor {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Question,
        [string]$Model = 'composer-2'
    )
    $agentDir = Join-Path $env:LOCALAPPDATA 'cursor-agent'
    $ver = Get-ChildItem "$agentDir\versions" -Directory |
        Where-Object { $_.Name -match '^\d{4}\.' } |
        Sort-Object Name -Descending | Select-Object -First 1
    $env:CURSOR_INVOKED_AS = 'agent.cmd'
    $raw = $Question | & "$($ver.FullName)\node.exe" "$($ver.FullName)\index.js" `
        -p --trust --model $Model --output-format json 2>&1
    ($raw | Out-String | ConvertFrom-Json).result
}

# Usage
Ask-Cursor "What is the capital of Norway?"
Ask-Cursor "Explain async/await" -Model "claude-4.5-sonnet"
```

---

## JSON Response Structure

### `json` format (single object after completion)

```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 5234,
  "duration_api_ms": 5234,
  "result": "<full assistant text>",
  "session_id": "<uuid>",
  "request_id": "<uuid>"
}
```

| Field | Description |
|-------|-------------|
| `type` | Always `"result"` |
| `subtype` | `"success"` or error subtype |
| `is_error` | `true` if the request failed |
| `duration_ms` | Total execution time in ms |
| `result` | The model's complete response text |
| `session_id` | UUID for resuming this session |

### `stream-json` format (NDJSON events)

Events in order:
1. `system` (init) -- model name, permissions
2. `user` -- your prompt
3. `assistant` -- model response segments (between tool calls)
4. `tool_call` (started/completed) -- file reads, writes, grep, etc.
5. `result` -- final summary (same structure as `json` format)

---

## Windows-Specific Notes

### Piping is Required

On Windows, the Cursor Agent CLI blocks when the prompt is passed as a
positional argument in headless mode. **Always pipe the prompt through stdin:**

```powershell
# CORRECT
"your prompt" | agent -p --trust

# WRONG (hangs on Windows)
agent -p --trust "your prompt"
```

### Direct Node.js Invocation

The `agent` command is a `.cmd` batch file that calls PowerShell 5.1, which
calls Node.js. For maximum reliability in scripts, call Node.js directly:

```powershell
$agentDir = "$env:LOCALAPPDATA\cursor-agent\versions"
$latest   = (Get-ChildItem $agentDir -Directory | Sort-Object Name -Descending)[0]
$nodeExe  = "$($latest.FullName)\node.exe"
$indexJs  = "$($latest.FullName)\index.js"
$env:CURSOR_INVOKED_AS = 'agent.cmd'

"Your prompt" | & $nodeExe $indexJs -p --trust --model "composer-2" --output-format json
```

### Character Encoding

For files with Norwegian characters (Æ Ø Å), use `-Encoding Default` when
reading and `-Encoding utf8` when writing results:

```powershell
$source = Get-Content "C:\src\legacy\PROGRAM.CBL" -Raw -Encoding Default
# ... process with agent ...
$result | Set-Content "output.json" -Encoding utf8
```

---

## Common Model Choices

| Model ID | Name | Best For |
|----------|------|----------|
| `composer-2` | Composer 2 | General coding tasks (default) |
| `claude-4.5-sonnet` | Sonnet 4.5 1M | Large context, detailed analysis |
| `claude-4.6-sonnet-medium` | Sonnet 4.6 1M | Latest Claude, balanced |
| `claude-4.6-opus-high` | Opus 4.6 1M | Complex reasoning, best quality |
| `gpt-5.4-medium` | GPT-5.4 1M | OpenAI flagship |
| `gpt-5.4-nano-low` | GPT-5.4 Nano Low | Fastest, cheapest, simple tasks |
| `gemini-3.1-pro` | Gemini 3.1 Pro | Google's latest |
| `grok-4-20` | Grok 4.20 | xAI model |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `agent: command not found` | Run install: `irm 'https://cursor.com/install?win32=true' \| iex` |
| `Not authenticated` | Run `agent login` or set `CURSOR_API_KEY` |
| Command hangs (no output) | Pipe through stdin: `"prompt" \| agent -p` |
| `%1 is not a valid Win32 application` | Don't use `Start-Process -FilePath agent`; call node.exe directly |
| Empty output | Ensure `--output-format` is set and prompt is piped |
| `No models available` | Login first: `agent login` |
| Update fails | Login first, then `agent update` |

---

## Further Reading

- [Cursor CLI Overview](https://cursor.com/docs/cli/overview)
- [Headless Mode](https://cursor.com/docs/cli/headless)
- [Parameters Reference](https://cursor.com/docs/cli/reference/parameters)
- [Output Format](https://cursor.com/docs/cli/reference/output-format)
- [Authentication](https://cursor.com/docs/cli/reference/authentication)
