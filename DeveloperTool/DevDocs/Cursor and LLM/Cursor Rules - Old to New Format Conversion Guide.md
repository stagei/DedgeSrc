# Cursor Rules - Old to New Format Conversion Guide

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-01-30  
**For:** Mina (and anyone learning Cursor rules)

---

## Overview

Cursor IDE uses "rules" to give the AI assistant context about your project. There are two formats:

1. **Old format**: Single `.cursorrules` file in project root
2. **New format**: Multiple `.mdc` files in `.cursor/rules/` folder

This guide explains the difference and why we converted.

---

## The Old Format: `.cursorrules`

### How It Works

A single file named `.cursorrules` placed in your project root:

```
MyProject/
├── .cursorrules          ← Single file with ALL rules
├── src/
└── package.json
```

### Example Content

```markdown
# My Project Rules

## Agent Permissions
- The AI can edit files freely
- Always commit after changes

## Code Style
- Use TypeScript
- Format with Prettier

## Commands
When user types "--deploy":
1. Build the project
2. Push to server
```

### Problems with Old Format

1. **Gets too long** - Rules for a complex project can be 500-2000+ lines
2. **Hard to navigate** - Everything in one file
3. **No conditional loading** - ALL rules load for ALL files, even if not relevant
4. **Hard to maintain** - Finding and updating specific rules is tedious

---

## The New Format: `.mdc` Files

### How It Works

Multiple files in a `.cursor/rules/` folder, each focused on one topic:

```
MyProject/
├── .cursor/
│   └── rules/
│       ├── agent-permissions.mdc    ← Permissions only
│       ├── commands.mdc             ← Commands only
│       ├── code-style.mdc           ← Code style only
│       └── typescript-patterns.mdc  ← Only for .ts files
├── src/
└── package.json
```

### File Structure

Each `.mdc` file has two parts:

1. **Frontmatter** (metadata between `---` markers)
2. **Content** (the actual rules in markdown)

### Example `.mdc` File

```markdown
---
description: Code style and formatting rules
alwaysApply: true
---

# Code Style

- Use TypeScript for all new code
- Format with Prettier on save
- Use 2-space indentation
```

---

## The Frontmatter Options

The frontmatter controls WHEN the rules apply:

### `description`

A short description shown in Cursor's UI:

```yaml
description: Database query patterns for PostgreSQL
```

### `alwaysApply`

If `true`, rules are ALWAYS included for this project:

```yaml
alwaysApply: true   # Always load these rules
alwaysApply: false  # Only load when conditions match
```

### `globs`

Only load rules when working on files matching these patterns:

```yaml
globs: ["*.ts", "*.tsx"]           # Only for TypeScript files
globs: ["*.cs"]                     # Only for C# files
globs: ["*.xaml", "*.xaml.cs"]      # Only for WPF files
```

---

## Conversion Example

### Before (Old Format)

One big `.cursorrules` file with 300 lines:

```markdown
# Project Rules

## Agent Permissions
- Full edit access
- Commit means full push

## Commands
--deploy triggers build and publish

## PowerShell Standards
- Use Write-LogMessage for logging
- Never use Write-Host

## C# Patterns
- Use async/await
- Log all exceptions

## Database Rules
- Use parameterized queries
- Never concatenate SQL strings
```

### After (New Format)

Split into focused files:

**`.cursor/rules/agent-permissions.mdc`**
```markdown
---
description: Agent permissions and git workflow
alwaysApply: true
---

# Agent Permissions

- Full edit access
- Commit means full push
```

**`.cursor/rules/commands.mdc`**
```markdown
---
description: Custom commands like --deploy
alwaysApply: true
---

# Commands

--deploy triggers build and publish
```

**`.cursor/rules/powershell-standards.mdc`**
```markdown
---
description: PowerShell coding standards
globs: ["*.ps1", "*.psm1"]
---

# PowerShell Standards

- Use Write-LogMessage for logging
- Never use Write-Host
```

**`.cursor/rules/csharp-patterns.mdc`**
```markdown
---
description: C# coding patterns
globs: ["*.cs"]
---

# C# Patterns

- Use async/await
- Log all exceptions
```

**`.cursor/rules/database-rules.mdc`**
```markdown
---
description: Database security rules
globs: ["*.cs", "*.sql"]
---

# Database Rules

- Use parameterized queries
- Never concatenate SQL strings
```

---

## Benefits of the New Format

| Benefit | Explanation |
|---------|-------------|
| **Organized** | Each file has one clear purpose |
| **Conditional** | Load rules only when relevant (e.g., C# rules only for .cs files) |
| **Maintainable** | Easy to find and update specific rules |
| **Smaller context** | AI only sees relevant rules, not everything |
| **Reusable** | Can copy specific rule files to other projects |

---

## Quick Reference

### File Locations

| Format | Location |
|--------|----------|
| Old | `project/.cursorrules` |
| New | `project/.cursor/rules/*.mdc` |

### Frontmatter Template

```markdown
---
description: Brief description of what these rules cover
alwaysApply: true
globs: ["*.ext"]
---

# Rule Title

Your rules here...
```

### Common `globs` Patterns

| Pattern | Matches |
|---------|---------|
| `*.cs` | C# files |
| `*.ts` | TypeScript files |
| `*.ps1` | PowerShell scripts |
| `*.xaml` | WPF XAML files |
| `*.sql` | SQL files |
| `*.md` | Markdown files |
| `**/*.cs` | C# files in any subfolder |

---

## Migration Checklist

When converting an old `.cursorrules` file:

1. [ ] Read through the entire file
2. [ ] Identify distinct sections/topics
3. [ ] Create `.cursor/rules/` folder
4. [ ] Create one `.mdc` file per topic
5. [ ] Add appropriate frontmatter to each file
6. [ ] Use `globs` for technology-specific rules
7. [ ] Rename old file to `.cursorrules.old` (keep as backup)
8. [ ] Test that Cursor still loads the rules

---

## Tips

1. **Start simple** - Use `alwaysApply: true` for most rules initially
2. **Use globs sparingly** - Only for clearly technology-specific rules
3. **Keep files focused** - If a file has multiple unrelated topics, split it
4. **Descriptive names** - File names should indicate content (`db2-patterns.mdc` not `rules2.mdc`)
5. **Keep the old file** - Rename to `.cursorrules.old` as backup until you're confident

---

*Last updated: 2026-01-30*
