# Cursor Rules, Skills, and Commands - How They Work Together

**Author:** Geir Helge Starholm, www.dEdge.no  
**Created:** 2026-03-26  
**Technology:** Cursor IDE / AI Development

---

## Overview

Cursor's AI agent system has three extensibility mechanisms that control how the agent behaves, what workflows it can trigger, and what knowledge it has access to. This document explains how **rules**, **commands**, and **skills** work individually and how they interact during a session.

---

## The Three Mechanisms

| Mechanism | Location | Trigger | Purpose |
|---|---|---|---|
| **Rules** (`.mdc`) | `.cursor/rules/*.mdc` | Automatic or glob-matched | Persistent behavioral instructions the agent always follows |
| **Commands** (`.md`) | `.cursor/commands/*.md` | User types `/commandname` | On-demand workflows the user explicitly invokes |
| **Skills** (`SKILL.md`) | `.cursor/skills/*/SKILL.md` | Automatic pattern matching | Complex multi-step procedures the agent reads and follows |

```
┌─────────────────────────────────────────────────┐
│                  Agent Session                   │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
│  │  Rules   │  │ Commands │  │    Skills    │   │
│  │ (always  │  │ (on user │  │ (auto-read   │   │
│  │  loaded) │  │  /slash) │  │  when needed)│   │
│  └────┬─────┘  └────┬─────┘  └──────┬───────┘   │
│       │              │               │           │
│       └──────────────┼───────────────┘           │
│                      ▼                           │
│              Agent Behavior                      │
└─────────────────────────────────────────────────┘
```

---

## Rules (`.cursor/rules/*.mdc`)

Rules are the foundation. They define persistent behavioral instructions that the agent follows throughout a session.

### File Format

Rules use Markdown with YAML frontmatter in `.mdc` files (Markdown for Cursor):

```yaml
---
description: Short description shown in rule picker
alwaysApply: true
---
```

The YAML frontmatter has two key fields:

| Field | Type | Effect |
|---|---|---|
| `description` | string | Human-readable label shown when browsing rules |
| `alwaysApply` | boolean | When `true`, the rule is injected into every agent session automatically |

If `alwaysApply` is `false` (or omitted), the rule is only loaded when files matching a glob pattern are involved. The glob pattern is specified in the `description` field or via Cursor's rule configuration UI.

### Rule Scopes

Rules exist at three levels, from broadest to narrowest:

1. **User rules** -- stored in Cursor Settings, apply to all workspaces globally
2. **Workspace rules** -- stored in `.cursor/rules/*.mdc`, apply to one project
3. **Folder rules** -- stored in subfolder `.cursor/rules/*.mdc`, apply to that subtree

When rules conflict, narrower scopes override broader ones.

### What Rules Contain

Rules are plain instructions the agent must follow. Common patterns:

- **Coding standards**: "All PowerShell scripts must use `pwsh.exe`"
- **Behavioral constraints**: "Never use `Invoke-Command -ComputerName`"
- **Workflow automation**: "After deploying, always run health checks"
- **Domain knowledge**: database names, server mappings, API endpoints
- **Templates**: report formats, commit message structures

### The `@` Reference Syntax

Users can reference specific lines of any file using `@` in chat:

```
@.cursor/rules/cross-project-inbox.mdc:2-4
```

This tells Cursor to attach lines 2-4 of that file to the conversation context. The agent sees the file contents inline. This works with any file, not just rules:

| Syntax | What it does |
|---|---|
| `@filename` | Attaches the entire file |
| `@filename:10-20` | Attaches lines 10 through 20 |
| `@foldername/` | Attaches the folder structure |

This is how users provide precise context without copy-pasting code.

### Real Example: `cross-project-inbox.mdc`

```yaml
---
description: Cross-project error/change reporting via _inbox folders
alwaysApply: true
---
```

Line 2 is the `description` -- this appears in the Cursor rules list.  
Line 3 is `alwaysApply: true` -- this rule is active in every session.  
Line 4 closes the frontmatter block.

The body after `---` contains the actual instructions the agent follows.

---

## Commands (`.cursor/commands/*.md`)

Commands are on-demand workflows triggered by typing `/commandname` in the chat input.

### File Format

Plain markdown files in `.cursor/commands/`. The filename (minus `.md`) becomes the slash command:

| File | Command |
|---|---|
| `.cursor/commands/help.md` | `/help` |
| `.cursor/commands/report.md` | `/report` |
| `.cursor/commands/inbox.md` | `/inbox` |
| `.cursor/commands/devdocs.md` | `/devdocs` |

### How Commands Work

1. User types `/commandname` in the chat input
2. Cursor injects the markdown file content as the prompt
3. The agent reads the instructions and executes them
4. The user can add additional context after the command name

Commands are essentially pre-written prompts. They combine well with rules because the agent still follows all active rules while executing a command.

### Command vs Rule

| Aspect | Rule | Command |
|---|---|---|
| Trigger | Automatic (always or glob-matched) | Manual (`/slash` in chat) |
| Scope | Behavioral constraint or knowledge | Specific workflow or task |
| Persistence | Active for entire session | Active only when invoked |
| User action | None required | User must type the command |

### When to Use Commands

- **Repeatable workflows**: deploy, test, report generation
- **Complex multi-step tasks**: that need the same sequence every time
- **Team standardization**: everyone uses the same workflow via `/command`

---

## Skills (`.cursor/skills/*/SKILL.md`)

Skills are the most powerful mechanism. They are detailed procedure documents that the agent reads and follows step-by-step.

### File Format

Each skill lives in its own folder with a `SKILL.md` file:

```
.cursor/skills/
├── git-smart-commit/
│   └── SKILL.md
├── shadow-pipeline-autocur/
│   └── SKILL.md
└── new-repo/
    └── SKILL.md
```

Skills can also exist at the user level (`~/.cursor/skills/`) for cross-workspace availability.

### How Skills Work

1. The agent sees a task that matches a skill's trigger pattern
2. It reads the `SKILL.md` file to get detailed instructions
3. It follows the procedure step-by-step, using the tools available
4. Skills can include error handling, retry logic, and validation steps

### Skill Trigger Patterns

Skills are matched by keywords or phrases in the user's request. The skill description in the agent's context defines when it activates:

- "Use when the user types `/commit`" -- keyword trigger
- "Use when the user asks to run the shadow pipeline" -- intent trigger
- "Use when building UI with @wix/design-system" -- technology trigger

### Skill vs Command

| Aspect | Command | Skill |
|---|---|---|
| Location | `.cursor/commands/` | `.cursor/skills/*/SKILL.md` |
| Trigger | Explicit `/slash` | Automatic pattern match or explicit |
| Complexity | Simple prompt injection | Full procedure with steps, error handling |
| Scope | Single task | Multi-step autonomous workflow |

### When to Use Skills

- **Complex autonomous workflows**: deploy pipelines, database operations
- **Error recovery**: skills can include "if X fails, do Y" logic
- **Multi-tool orchestration**: skills that coordinate git, deploy, test, notify

---

## How They Interact

During a typical session, all three mechanisms work together:

```
User types: /inbox

1. Cursor loads the /inbox COMMAND
   → Agent reads .cursor/commands/inbox.md

2. Agent also has all alwaysApply RULES loaded
   → cross-project-inbox.mdc (report format)
   → git-standards.mdc (commit conventions)
   → server-logging.mdc (log patterns)
   → execute-all-orders.mdc (no refusals)
   → ... all other alwaysApply rules

3. While processing, agent recognizes a SKILL pattern
   → Reads .cursor/skills/git-smart-commit/SKILL.md
   → Uses it to commit changes properly

Result: Command drives the workflow, rules constrain behavior,
        skills provide detailed procedures when needed.
```

### Precedence and Composition

- **Rules** are always active -- they constrain everything the agent does
- **Commands** inject a specific task -- the agent follows both the command and all active rules
- **Skills** provide detailed procedures -- the agent follows the skill steps while still respecting rules
- If a rule says "never do X" and a command says "do X", the rule wins (rules are non-negotiable)

### Practical Example: Cross-Project Workflow

This workspace demonstrates the interaction pattern with the inbox system:

1. **Rule** (`cross-project-inbox.mdc`): Always active. When the agent discovers an issue in another project, it automatically creates a report in `_inbox/`.

2. **Command** (`/report`): User explicitly asks to file a report. The command prompt tells the agent what to do, and the rule provides the report template.

3. **Command** (`/inbox`): User asks to process all pending reports. The agent scans repos, reads reports, implements fixes, and uses git-standards rules for commits.

4. **Command** (`/devdocs`): User asks to create documentation. The command drives the workflow (create file, commit, deploy), while rules ensure proper conventions.

---

## Creating Your Own

### New Rule

Create `.cursor/rules/my-rule.mdc`:

```yaml
---
description: What this rule does
alwaysApply: true
---

# Rule Title

Instructions the agent must follow...
```

### New Command

Create `.cursor/commands/my-command.md`:

```markdown
Description of what this command does.

## Instructions

1. Step one...
2. Step two...
3. Step three...
```

Then type `/my-command` in chat to use it.

### New Skill

Create `.cursor/skills/my-skill/SKILL.md`:

```markdown
# My Skill

## When to Use
Trigger conditions...

## Procedure
1. Detailed step...
2. Detailed step with error handling...
3. Validation...
```

---

## File Locations Summary

| Type | Workspace Level | User Level |
|---|---|---|
| Rules | `.cursor/rules/*.mdc` | Cursor Settings > User Rules |
| Commands | `.cursor/commands/*.md` | `~/.cursor/commands/*.md` |
| Skills | `.cursor/skills/*/SKILL.md` | `~/.cursor/skills/*/SKILL.md` |

Workspace-level files are version-controlled and shared with the team. User-level files are personal and apply across all workspaces.

---

## Tips

- **Start with rules** for standards that should always apply (coding conventions, deploy patterns)
- **Add commands** for workflows your team repeats (deploy, test, report)
- **Create skills** for complex autonomous tasks that need error handling and multi-step logic
- **Use `alwaysApply: true`** sparingly -- every always-on rule consumes context tokens
- **Keep commands concise** -- they're prompts, not documentation
- **Make skills detailed** -- they're procedures, include error paths and validation
- **Reference rules from commands** -- "use the template from the cross-project-inbox rule" avoids duplication
