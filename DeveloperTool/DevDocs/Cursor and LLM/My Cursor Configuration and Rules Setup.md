# My Cursor Configuration and Rules Setup

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-01-30  
**Technology:** Cursor IDE / AI Development

---

## Overview

This document describes my personal Cursor IDE configuration, including custom settings, cursor rules files, and preferences that enhance AI-assisted development workflows.

---

## Custom Settings (settings.json)

Location: `%APPDATA%\Cursor\User\settings.json`

### Window Title Configuration

Shows project name first in the window title for easy identification when multiple Cursor instances are open:

```json
{
  "window.title": "${rootName}${separator}${activeEditorShort}${dirty}${separator}${appName}"
}
```

**Result:** `ServerMonitor - Program.cs - Cursor` instead of `Program.cs - ServerMonitor - Cursor`

**Available variables:**

| Variable | Description |
|----------|-------------|
| `${rootName}` | Workspace/project folder name |
| `${activeEditorShort}` | Just the file name |
| `${activeEditorMedium}` | File path relative to workspace |
| `${activeEditorLong}` | Full file path |
| `${dirty}` | Shows `●` if file has unsaved changes |
| `${separator}` | Shows ` - ` only when surrounded by values |
| `${appName}` | "Cursor" |

### UI Customizations

```json
{
  "explorer.openEditors.visible": 0,
  "workbench.view.alwaysShowHeaderActions": false,
  "window.commandCenter": true,
  "workbench.tree.indent": 20,
  "workbench.colorTheme": "Visual Studio Dark",
  "workbench.colorCustomizations": {
    "tab.activeBackground": "#c7850c"
  }
}
```

- **Open Editors panel hidden** - Uses tabs instead
- **Tree indent increased to 20** - Better visibility for nested folders
- **Active tab highlighted in orange** (#c7850c) - Easy identification of current file
- **Command Center enabled** - Quick access to commands via the top bar

### Git Settings

```json
{
  "git.confirmSync": false,
  "git.autofetch": true,
  "git.enableSmartCommit": true,
  "git.blame.editorDecoration.enabled": false,
  "git.blame.statusBarItem.enabled": false
}
```

- **Auto-fetch enabled** - Keeps remote refs up to date
- **Smart commit enabled** - Stages all changes when there are no staged changes
- **Git blame disabled** - Removes visual clutter from editor and status bar

### Log Viewer Configuration

```json
{
  "logViewer.watch": [
    { "pattern": "C:\\opt\\data\\AllPwshLog\\**.log", "title": "Local AllPwshLog" },
    { "pattern": "\\\\p-no1fkmrap\\opt\\data\\AllPwshLog\\**.log", "title": "FKMRAP AllPwshLog" },
    { "pattern": "\\\\p-no1fkmprd\\opt\\data\\AllPwshLog\\**.log", "title": "FKMPRD AllPwshLog" },
    { "pattern": "\\\\p-no1inlprd\\opt\\data\\AllPwshLog\\**.log", "title": "INLPRD AllPwshLog" }
  ]
}
```

Watches PowerShell log files from local machine and production servers for real-time monitoring.

### Security Settings

```json
{
  "security.allowedUNCHosts": ["*.DEDGE.fk.no", "p-no1*", "t-no1*"],
  "security.promptForLocalFileProtocolHandling": false
}
```

Pre-approves network shares for seamless access to server files.

### Editor and Formatter Settings

```json
{
  "[json]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[jsonc]": { "editor.defaultFormatter": "esbenp.prettier-vscode" },
  "[html]": { "editor.defaultFormatter": "vscode.html-language-features" },
  "editor.largeFileOptimizations": false,
  "markdown-preview-enhanced.previewTheme": "atom-dark.css"
}
```

### Cursor AI Settings

```json
{
  "cursor.general.gitGraphIndexing": "enabled",
  "cursor.composer.shouldChimeAfterChatFinishes": true
}
```

- **Git graph indexing** - Enables AI to understand git history
- **Chime on completion** - Audio notification when AI finishes long operations

---

## Cursor Rules Files

Cursor rules provide context and instructions to the AI agent for each project. There are two formats:

### 1. Legacy Format: `.cursorrules` Files

Location: Project root directory (e.g., `C:\opt\src\DedgePsh\.cursorrules`)

**My current projects with `.cursorrules`:**

| Project | Purpose |
|---------|---------|
| `DedgePsh` | Main PowerShell tools repository - comprehensive rules |
| `ServerMonitor\ServerMonitorAgent` | .NET monitoring agent |
| `WindowsDb2Editor` | DB2 database editor |
| `DedgeCommon` | Shared utilities |
| `GetPeppolDirectory` | Peppol integration |
| `SqlMermaidErdTools` | SQL to Mermaid diagram tools |

### 2. New Format: `.mdc` Files (Cursor Rules v2)

Location: `.cursor/rules/` folder in project root

**Structure:**
```
project/
├── .cursor/
│   └── rules/
│       ├── architecture-and-technology.mdc
│       └── agent-notifications.mdc
```

**Format with frontmatter:**
```markdown
---
description: Architecture, design choices, and technology stack
alwaysApply: true
---

# Rule Title

Content here...
```

**Frontmatter options:**

| Option | Type | Description |
|--------|------|-------------|
| `description` | string | Brief description shown in rule picker |
| `alwaysApply` | boolean | If true, rule is always included in context |
| `globs` | array | File patterns when rule should apply (e.g., `["*.cs", "*.csproj"]`) |

---

## Key Rule Patterns I Use

### 1. Agent Permissions Section

Allow AI to autonomously update rules when discovering patterns:

```markdown
## Agent Permissions

The AI agent is **authorized to edit this `.cursorrules` file** when:
- Adding new standards discovered during code analysis
- Improving existing rules based on observed patterns
- Fixing inconsistencies or ambiguities
- Adding examples to clarify rules
```

### 2. Custom Commands

Define shortcuts the AI recognizes:

```markdown
## Cursor Commands

| Command | Description |
|---------|-------------|
| `--help` | Show command list |
| `--ado` | Azure DevOps workflow |
| `--deploy` | Build and deploy |
| `--gitreport` | Generate Git activity report |
```

### 3. Team Configuration

Store team member info for automation:

```yaml
Users:
  - Username: FKGEISTA
    FullName: Geir Helge Starholm
    Email: geir.helge.starholm@Dedge.no
    SmsNumber: +4797188358
```

### 4. Technology-Specific Standards

Document coding patterns for the project:

```markdown
## PowerShell Coding Standards

### Module Import
Import-Module GlobalFunctions -Force

### Logging
Write-LogMessage "Test" -Level INFO

### Parameter Types
- Switch: Use `-Name` or `-Name:$false`
- Boolean: Use `-Name:$true` or `-Name:$false`
```

### 5. Deployment Workflows

Define build and deployment procedures:

```markdown
## Publishing

When user says "publish":
1. Run `.\Build-And-Publish.ps1` from repo root
2. Do NOT manually bump versions
3. Do NOT use Quick-Build.ps1 unless explicitly requested
```

---

## Cursor Preferences Configuration

Access via: `Ctrl+Shift+P` → "Preferences: Open Settings (UI)"

### User Rules (Cursor Settings → Rules)

These global rules apply across all projects and are stored in Cursor's preferences:

1. **DevTools _deploy.ps1 Standard** - Deployment script patterns
2. **PowerShell interpolation rule** - Variable wrapping in strings
3. **Switch vs Boolean parameter rules** - Parameter type handling
4. **Regex explanation requirement** - Document regex patterns
5. **Linter error correction** - Auto-fix after agent execution
6. **Module import standard** - GlobalFunctions import pattern
7. **Logging standard** - Write-LogMessage usage
8. **Log file location** - Default log paths

### How to Add User Rules

1. Open Cursor Settings (`Ctrl+,`)
2. Search for "cursor.rules" or navigate to Features → Rules
3. Click "Add Rule" or edit `rules` in settings.json:

```json
{
  "cursor.rules": [
    "Always use Write-LogMessage for logging",
    "Prefer switch parameters with -Name syntax"
  ]
}
```

---

## Best Practices

### 1. Layered Rules Strategy

- **Global User Rules**: Universal standards (logging, formatting)
- **Project `.cursorrules`**: Project-specific workflows and commands
- **Folder `.mdc` files**: Component-specific patterns (e.g., API vs UI)

### 2. Keep Rules Focused

Each rules file should focus on one domain:
- `architecture-and-technology.mdc` - Tech stack and patterns
- `agent-notifications.mdc` - When/how AI should notify
- `.cursorrules` - Commands, workflows, team config

### 3. Include Examples

Always provide code examples in rules - AI learns better from examples than descriptions:

```markdown
## Good Example
```powershell
Write-LogMessage "Processing file: $($filePath)" -Level INFO
```

## Bad Example
```powershell
Write-Host "Processing file: $filePath"
```
```

### 4. Document "Why" Not Just "What"

```markdown
**Why:** The pre-build script automatically copies FROM network share TO local.
Any local changes will be overwritten.
```

---

## File Locations Summary

| Item | Location |
|------|----------|
| User Settings | `%APPDATA%\Cursor\User\settings.json` |
| Global User Rules | Cursor Settings → Features → Rules |
| Project Rules (Legacy) | `<project>/.cursorrules` |
| Project Rules (v2) | `<project>/.cursor/rules/*.mdc` |
| Cursor Skills | `%USERPROFILE%\.cursor\skills-cursor\` |
| Cursor Plans | `%USERPROFILE%\.cursor\plans\` |

---

## Related Documentation

- [Cursor Rules Guide](./Cursor%20Rules%20Guide.md) - General overview of cursor rules
- [Changes to Command Execution in Cursor AI](./Changes%20to%20Command%20Execution%20in%20Cursor%20AI.md)
- [Claude 3.7 - New Functionality Overview](./Claude%203.7%20-%20New%20Functionality%20Overview.md)

---

*Last updated: 2026-01-30*
