# Cursor CLI — Comprehensive Reference

> **Beta notice:** The Cursor CLI is currently in beta. Security safeguards are still evolving.
> It can read, modify, and delete files, and execute shell commands. Use only in trusted environments.

---

## Table of Contents

1. [Installation](#installation)
2. [Authentication](#authentication)
3. [Commands](#commands)
4. [Global Options / Flags](#global-options--flags)
5. [Models](#models)
6. [Output Formats](#output-formats)
7. [Permissions System](#permissions-system)
8. [Shell Mode](#shell-mode)
9. [Headless / Script Mode](#headless--script-mode)
10. [MCP Server Management](#mcp-server-management)
11. [Session Management](#session-management)
12. [GitHub Actions / CI-CD Integration](#github-actions--ci-cd-integration)
13. [Configuration Files](#configuration-files)
14. [PowerShell Examples (Windows)](#powershell-examples-windows)

---

## Installation

### Windows (PowerShell 7+)

```powershell
irm 'https://cursor.com/install?win32=true' | iex
```

> `win32=true` is the **Windows platform identifier** — it installs the 64-bit binary on 64-bit systems.
> `irm` is an alias for `Invoke-RestMethod`.

### macOS / Linux / WSL

```bash
curl https://cursor.com/install -fsSL | bash
```

### Verify installation

```powershell
agent --version
agent about
```

### Update to latest version

```powershell
agent update
```

---

## Authentication

### Interactive login (browser-based)

```powershell
agent login
```

### Check current auth status

```powershell
agent status
agent whoami   # alias for status
```

### Logout

```powershell
agent logout
```

### API key authentication (for scripts / CI)

Set an environment variable — no browser login needed:

```powershell
# PowerShell
$env:CURSOR_API_KEY = "your_api_key_here"
agent -p "Analyze this codebase"

# Bash / WSL
export CURSOR_API_KEY=your_api_key_here
agent -p "Analyze this codebase"
```

Or pass it inline per command:

```powershell
agent --api-key "your_api_key_here" -p "Fix the bug in app.ts"
```

Generate an API key from your Cursor dashboard at [cursor.com](https://cursor.com).

---

## Commands

All commands are invoked as `agent <command>`. When no command is specified, the CLI starts in interactive agent mode.

| Command | Aliases | Description |
|---|---|---|
| `agent` | — | Start in interactive agent mode (default) |
| `agent login` | — | Authenticate with Cursor (browser-based) |
| `agent logout` | — | Sign out and clear stored authentication |
| `agent status` | `whoami` | Check authentication status |
| `agent about` | — | Display version, system, and account info |
| `agent models` | — | List all available models |
| `agent update` | — | Update Cursor Agent to the latest version |
| `agent ls` | — | List previous chat sessions |
| `agent resume` | — | Resume the latest chat session |
| `agent create-chat` | — | Create a new empty chat, returns its ID |
| `agent generate-rule` | `rule` | Generate a new Cursor rule interactively |
| `agent mcp` | — | Manage MCP servers (see subcommands below) |
| `agent install-shell-integration` | — | Install shell integration to `~/.zshrc` |
| `agent uninstall-shell-integration` | — | Remove shell integration from `~/.zshrc` |
| `agent help [command]` | — | Display help for a specific command |

### Examples

```powershell
# Start interactive agent session with an initial prompt
agent "find one bug and fix it"

# List all previous sessions
agent ls

# Resume most recent session
agent resume

# Show version and system info
agent about

# List available models
agent models

# Generate a Cursor rule interactively
agent generate-rule
```

---

## Global Options / Flags

These flags can be combined with any command.

| Flag | Short | Description |
|---|---|---|
| `--version` | `-v` | Output the version number |
| `--api-key <key>` | — | API key for authentication |
| `--header <Name: Value>` | `-H` | Add custom HTTP header (repeatable) |
| `--print` | `-p` | Non-interactive/headless mode — print response to stdout |
| `--output-format <fmt>` | — | `text` (default), `json`, or `stream-json` — only with `--print` |
| `--stream-partial-output` | — | Stream character-level deltas (only with `stream-json`) |
| `--cloud` | `-c` | Start in cloud mode |
| `--resume [chatId]` | — | Resume a specific chat session by ID |
| `--continue` | — | Continue the previous session (alias for `--resume=-1`) |
| `--model <name>` | — | Specify which model to use |
| `--mode <mode>` | — | Set agent mode: `plan` or `ask` (default: `agent`) |
| `--plan` | — | Start in plan mode (shorthand for `--mode=plan`) |
| `--list-models` | — | List all available models |
| `--force` | `-f` | Allow file writes without confirmation in print mode |
| `--yolo` | — | Alias for `--force` |
| `--sandbox <mode>` | — | Sandbox mode: `enabled` or `disabled` |
| `--approve-mcps` | — | Auto-approve all MCP servers |
| `--trust` | — | Trust the workspace without prompting (headless only) |
| `--workspace <dir>` | — | Set the working directory for the agent |
| `--help` | `-h` | Display help |

### Examples

```powershell
# Run in plan mode (agent explains plan, doesn't execute)
agent --plan "Refactor the authentication module"

# Run in ask mode (read-only, no file changes)
agent --mode ask "What does the UserService class do?"

# Use a specific model
agent --model claude-4-sonnet "Review this pull request"

# Use a different workspace directory
agent --workspace "C:\opt\src\MyProject" "Summarize the codebase"

# Run with a custom request header
agent -H "X-Team-ID: myteam" -p "List all TODO comments"

# List all models
agent --list-models
```

---

## Models

List all available models:

```powershell
agent models
# or
agent --list-models
```

### Specify a model per command

```powershell
agent --model auto "Fix the failing tests"
agent --model claude-4-sonnet "Review my PR"
agent --model gpt-5.2 "Analyze security vulnerabilities"
agent --model gemini-3-pro "Generate unit tests for UserService"
```

Available model families (exact names shown by `agent models`):

- `auto` — Cursor selects the best model (default)
- Claude models (Anthropic) — e.g. `claude-4-sonnet`, `claude-4-opus`
- GPT / Codex models (OpenAI)
- Gemini models (Google)
- Composer / Cursor native models
- Grok (xAI)

---

## Output Formats

Only available when using `--print` (`-p`).

### `text` (default) — clean final answer only

```powershell
agent -p "What does this codebase do?"
# Outputs: plain text answer, no metadata
```

### `json` — single JSON object on completion

```powershell
agent -p --output-format json "Find all TODO comments" | ConvertFrom-Json
```

Response structure:

```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 1234,
  "duration_api_ms": 1234,
  "result": "<full assistant text>",
  "session_id": "<uuid>",
  "request_id": "<optional request id>"
}
```

Extracting just the result in PowerShell:

```powershell
$result = agent -p --output-format json "Summarize the project" | ConvertFrom-Json
Write-Output $result.result
```

### `stream-json` — newline-delimited JSON events (NDJSON)

```powershell
agent -p --output-format stream-json "Analyze and document this module"
```

Emits one JSON object per line as events occur:

| Event type | When emitted |
|---|---|
| `system` / `init` | Once at session start — includes model, cwd, session_id |
| `user` | Your prompt |
| `assistant` | Each assistant message segment |
| `tool_call` / `started` | When a tool (read/write/shell) begins |
| `tool_call` / `completed` | When a tool finishes, includes result |
| `result` / `success` | Final event on successful completion |

### `stream-json` + `--stream-partial-output` — character-level streaming

```powershell
agent -p --output-format stream-json --stream-partial-output "Generate API docs"
# Streams text delta by delta in real time
```

---

## Permissions System

Control what the agent is allowed to do via configuration files.

### Config file locations

| Scope | File |
|---|---|
| Global (all projects) | `~/.cursor/cli-config.json` |
| Project-specific | `<project>/.cursor/cli.json` |

### Permission types

| Type | Format | Description |
|---|---|---|
| Shell | `Shell(command)` | Allow/deny shell commands |
| Read | `Read(pathOrGlob)` | Allow/deny file reads |
| Write | `Write(pathOrGlob)` | Allow/deny file writes |
| WebFetch | `WebFetch(domain)` | Allow/deny web fetches |
| MCP | `Mcp(server:tool)` | Allow/deny MCP tool calls |

### Deny rules always override allow rules.

### Example config

```json
{
  "permissions": {
    "allow": [
      "Shell(git)",
      "Shell(npm)",
      "Shell(ls)",
      "Shell(grep)",
      "Shell(dotnet)",
      "Read(src/**/*.ts)",
      "Read(**/*.md)",
      "Write(src/**)",
      "Write(docs/**)",
      "WebFetch(docs.github.com)",
      "WebFetch(*.microsoft.com)",
      "Mcp(datadog:*)"
    ],
    "deny": [
      "Shell(rm)",
      "Shell(rmdir)",
      "Read(.env*)",
      "Write(**/*.key)",
      "Write(**/.env*)",
      "Write(package-lock.json)"
    ]
  }
}
```

### Pattern examples

```json
"Shell(curl:*)"           // curl with any arguments
"Shell(git:push*)"        // only git push subcommands
"Read(src/**/*.ts)"       // all .ts files under src
"Read(**/*.md)"           // markdown files anywhere
"Write(docs/**/*)"        // anything under docs
"WebFetch(*.example.com)" // any subdomain of example.com
"WebFetch(*)"             // all domains (use with caution)
"Mcp(*:search)"           // search tool on any MCP server
"Mcp(*:*)"                // all MCP tools (use with caution)
```

---

## Shell Mode

Shell Mode lets the agent run shell commands directly during a conversation, with safety checks before execution.

### Behavior

- Commands run in your login shell with the CLI's working directory
- Output is displayed inline in the conversation
- Commands that exceed 30 seconds time out automatically
- Large outputs are truncated

### Limitations

- No long-running processes (servers, watchers)
- No interactive prompts or applications
- Each command runs independently — `cd` does not persist

### Run a command in a subdirectory

```bash
cd subdir && npm test
```

### Usage in interactive mode

Just type shell commands when the agent suggests or you request them. The agent will prompt you to approve or allowlist the command.

### Approve once vs. allowlist

- **Approve once**: runs this time only
- **Allowlist (Tab)**: adds the command to your permissions config permanently

### Troubleshooting

```powershell
# If output is truncated — use Ctrl+O to expand
# If a command hangs — Ctrl+C to cancel

# Shell integration for zsh (not applicable on Windows)
agent install-shell-integration
agent uninstall-shell-integration
```

---

## Headless / Script Mode

Use `--print` (`-p`) to run the agent non-interactively. Essential for automation, CI, and PowerShell scripts.

### Basic headless usage

```powershell
# Ask a question — output to stdout
agent -p "What does this project do?"

# Make file changes (requires --force)
agent -p --force "Add JSDoc comments to all functions in src/utils.ts"

# Propose changes without applying them
agent -p "Suggest refactors for UserService.cs"
# Without --force, files are NOT modified
```

### Batch file processing

```powershell
# PowerShell: add comments to every .cs file
Get-ChildItem -Path src -Filter *.cs -Recurse | ForEach-Object {
    Write-Output "Processing $($_.FullName)"
    agent -p --force "Add XML doc comments to all public members in $($_.FullName)"
}
```

### Capture output in PowerShell

```powershell
$answer = agent -p "List all public API endpoints in this project"
Write-Output $answer
```

### Parse JSON output

```powershell
$result = agent -p --output-format json "Find all TODO comments" | ConvertFrom-Json
Write-Output "Duration: $($result.duration_ms)ms"
Write-Output $result.result
```

### Automated code review

```powershell
agent -p --force --output-format text `
    "Review recent code changes and write feedback to review.txt covering:
     - Code quality and readability
     - Potential bugs
     - Security issues
     - Best practices compliance"
```

### Image / file analysis

```powershell
# Analyze a screenshot
agent -p "Analyze this UI screenshot and suggest improvements: ./screenshots/dashboard.png"

# Compare before/after images
agent -p "Compare these two images and describe differences: ./before.png ./after.png"

# Combine image and code review
agent -p "Review src/app.ts and the design in designs/homepage.png. Does the code match?"
```

### Real-time progress tracking (stream-json)

```powershell
agent -p --force --output-format stream-json --stream-partial-output `
    "Analyze this project and write a summary to analysis.txt" |
    ForEach-Object {
        $event = $_ | ConvertFrom-Json
        switch ($event.type) {
            "system" { Write-Host "Model: $($event.model)" }
            "assistant" { Write-Host "Agent: $($event.message.content[0].text)" }
            "tool_call" {
                if ($event.subtype -eq "started") {
                    Write-Host "Tool: $($event.tool_call | ConvertTo-Json -Compress)"
                }
            }
            "result" { Write-Host "Done in $($event.duration_ms)ms" }
        }
    }
```

### Trust workspace without prompting

```powershell
agent -p --trust --force "Refactor all service classes to use dependency injection"
```

---

## MCP Server Management

MCP (Model Context Protocol) servers extend the agent with additional tools.

### Subcommands

| Subcommand | Description |
|---|---|
| `agent mcp list` | List configured MCP servers and their status |
| `agent mcp list-tools <server>` | List all tools available on a server |
| `agent mcp enable <server>` | Enable an MCP server |
| `agent mcp disable <server>` | Disable an MCP server |
| `agent mcp login <server>` | Authenticate with an MCP server |

### Examples

```powershell
# List all configured MCP servers
agent mcp list

# Show tools available on a specific server
agent mcp list-tools datadog

# Enable a server
agent mcp enable github

# Disable a server
agent mcp disable github

# Login to an MCP server (reads config from .cursor/mcp.json)
agent mcp login myserver
```

### Auto-approve all MCP tools

```powershell
agent --approve-mcps "Use GitHub MCP to list open PRs"
```

### MCP config file

Defined in `.cursor/mcp.json` in your project or `~/.cursor/mcp.json` globally.

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "your_token"
      }
    },
    "datadog": {
      "command": "npx",
      "args": ["-y", "datadog-mcp-server"]
    }
  }
}
```

---

## Session Management

The agent tracks conversation history in sessions so you can resume previous chats.

### List all past sessions

```powershell
agent ls
```

### Resume the most recent session

```powershell
agent resume
# or
agent --continue "Now also fix the related test"
```

### Resume a specific session by ID

```powershell
agent --resume c6b62c6f-7ead-4fd6-9922-e952131177ff "Continue from where we left off"
```

### Create a new empty session (returns its ID)

```powershell
$chatId = agent create-chat
Write-Output "New session: $($chatId)"
```

### Use session ID in scripts

```powershell
# Start a session, capture ID, resume later
$sessionOutput = agent -p --output-format json "Start analyzing the codebase" | ConvertFrom-Json
$sessionId = $sessionOutput.session_id

# Resume the same session
agent --resume $sessionId -p "Now generate the documentation"
```

---

## GitHub Actions / CI-CD Integration

### Basic workflow step (Linux runner)

```yaml
- name: Install Cursor CLI
  run: |
    curl https://cursor.com/install -fsS | bash
    echo "$HOME/.cursor/bin" >> $GITHUB_PATH

- name: Run Cursor Agent
  env:
    CURSOR_API_KEY: ${{ secrets.CURSOR_API_KEY }}
  run: |
    agent -p "Review the changes in this PR and write feedback to review.txt"
```

### Windows runner

```yaml
- name: Install Cursor CLI (Windows)
  shell: pwsh
  run: irm 'https://cursor.com/install?win32=true' | iex

- name: Run Cursor Agent (Windows)
  shell: pwsh
  env:
    CURSOR_API_KEY: ${{ secrets.CURSOR_API_KEY }}
  run: agent -p --force "Update documentation based on the latest code changes"
```

### Store API key as repository secret

```bash
# Via GitHub CLI
gh secret set CURSOR_API_KEY --repo OWNER/REPO --body "$CURSOR_API_KEY"

# Organisation-wide
gh secret set CURSOR_API_KEY --org ORG --visibility all --body "$CURSOR_API_KEY"
```

Or: GitHub repo → Settings → Secrets and variables → Actions → New repository secret.

### Full autonomy approach — agent handles git + PR

```yaml
- name: Update docs (full autonomy)
  env:
    CURSOR_API_KEY: ${{ secrets.CURSOR_API_KEY }}
  run: |
    agent -p "You have full access to git and GitHub CLI.
    Analyze the PR changes, update the documentation, commit, push,
    and post a summary comment on the PR."
```

### Restricted autonomy approach — agent modifies files only, CI handles git

```yaml
- name: Generate docs updates (restricted)
  env:
    CURSOR_API_KEY: ${{ secrets.CURSOR_API_KEY }}
  run: |
    agent -p "IMPORTANT: Do NOT create branches, commit, push, or post PR comments.
    Only modify files in the working directory. Update docs/ to match recent code changes."

- name: Commit and push (deterministic CI step)
  run: |
    git checkout -B "docs/${{ github.head_ref }}"
    git add -A
    git commit -m "docs: update for PR ${{ github.event.pull_request.number }}"
    git push origin "docs/${{ github.head_ref }}"

- name: Post PR comment (deterministic CI step)
  run: |
    gh pr comment ${{ github.event.pull_request.number }} \
      --body "Documentation updated automatically."
```

### Permission-restricted CI config

```json
{
  "permissions": {
    "allow": [
      "Read(**/*.md)",
      "Read(src/**/*)",
      "Write(docs/**/*)",
      "Shell(grep)",
      "Shell(find)"
    ],
    "deny": [
      "Shell(git)",
      "Shell(gh)",
      "Write(.env*)",
      "Write(package.json)",
      "Write(package-lock.json)"
    ]
  }
}
```

---

## Configuration Files

| File | Scope | Purpose |
|---|---|---|
| `~/.cursor/cli-config.json` | Global | Default permissions, model, preferences |
| `<project>/.cursor/cli.json` | Project | Project-specific permissions and settings |
| `<project>/.cursor/mcp.json` | Project | MCP server definitions |
| `~/.cursor/mcp.json` | Global | Global MCP server definitions |

### Example global config (`~/.cursor/cli-config.json`)

```json
{
  "model": "auto",
  "permissions": {
    "allow": [
      "Shell(git)",
      "Shell(npm)",
      "Shell(dotnet)",
      "Shell(pwsh)",
      "Shell(ls)",
      "Shell(grep)",
      "Read(**/*)",
      "Write(src/**)",
      "Write(docs/**)",
      "WebFetch(*)"
    ],
    "deny": [
      "Shell(rm)",
      "Shell(rmdir)",
      "Write(.env*)",
      "Write(**/*.key)",
      "Write(**/*.pem)"
    ]
  }
}
```

---

## PowerShell Examples (Windows)

A collection of practical PowerShell patterns for using Cursor CLI on Windows.

### Run agent on a specific project folder

```powershell
agent --workspace "C:\opt\src\MyProject" -p "What is the architecture of this solution?"
```

### Fix all linter errors in a project

```powershell
agent --workspace "C:\opt\src\MyProject" -p --force `
    "Find and fix all linter errors in the src/ folder"
```

### Generate documentation for all public APIs

```powershell
agent -p --force --model claude-4-sonnet `
    "Generate XML documentation comments for all public methods and classes in the project"
```

### Write a code review to a file

```powershell
agent -p --force "Review all recent changes and write a detailed code review to code-review.md"
```

### Parse result and send via email (integration example)

```powershell
Import-Module GlobalFunctions -Force

$result = agent -p --output-format json "Summarize what changed in the last commit" |
          ConvertFrom-Json

Write-LogMessage "Agent completed in $($result.duration_ms)ms" -Level INFO
Send-Email -To "geir.helge.starholm@felleskjopet.no" `
           -Subject "Daily Code Summary" `
           -Body $result.result
```

### Batch: analyze multiple projects

```powershell
$projects = @(
    "C:\opt\src\FkAuth",
    "C:\opt\src\DocView",
    "C:\opt\src\ServerMonitor"
)

foreach ($project in $projects) {
    Write-Output "Analyzing $($project)..."
    $result = agent --workspace $project -p --output-format json `
                    "Summarize this project in 3 bullet points" | ConvertFrom-Json
    Write-Output "$($project): $($result.result)"
    Write-Output ""
}
```

### Headless with API key (no browser login required)

```powershell
$env:CURSOR_API_KEY = "your_api_key_here"
agent -p "Generate unit tests for the UserService class"
```

### Resume last session and continue work

```powershell
agent --continue "Now also update the README with the changes you just made"
```

### Generate a Cursor rule from the CLI

```powershell
agent generate-rule
# Follows interactive prompts to create a .cursor/rules/*.mdc file
```

---

## Quick Reference Card

```
agent                                    # Interactive mode
agent "do something"                     # Interactive with initial prompt
agent -p "question"                      # Headless, text output
agent -p --force "modify files"          # Headless, allow file writes
agent -p --output-format json "..."      # JSON output
agent -p --output-format stream-json "." # Streaming NDJSON output
agent --model claude-4-sonnet "..."      # Specific model
agent --plan "..."                       # Plan mode (no execution)
agent --mode ask "..."                   # Ask mode (read-only)
agent --continue "..."                   # Resume last session
agent --resume <id> "..."               # Resume specific session
agent --workspace <dir> "..."           # Different working directory
agent --trust --force "..."             # Trust workspace, allow writes
agent login                             # Browser login
agent logout                            # Sign out
agent status                            # Check auth
agent models                            # List models
agent ls                                # List sessions
agent resume                            # Resume latest session
agent mcp list                          # List MCP servers
agent mcp list-tools <server>           # List MCP tools
agent update                            # Update CLI
agent about                             # Version + system info
agent help [command]                    # Help
```

---

*Last updated: February 2026 — based on official Cursor CLI documentation at [cursor.com/docs/cli](https://cursor.com/docs/cli/overview)*
