# Cursor Chat Reference: Commands, Rules, and Context

A reference for Cursor IDE's chat features: slash commands, @ mentions, rules, skills, MCP, and other context elements.

---

## 1. Slash Commands

Type `/` in chat to see available commands. Commands control mode, behavior, and utilities.

### Core Chat Commands

| Command | Description |
|---------|-------------|
| `/plan` | Switch to Plan mode — design your approach before coding |
| `/ask` | Switch to Ask mode — read-only exploration, no edits |
| `/model` | Set or list available AI models |
| `/new-chat` | Start a fresh chat session |

### Agent & Execution

| Command | Description |
|---------|-------------|
| `/auto-run [on\|off\|status]` | Toggle auto-run of agent steps |
| `/max-mode [on\|off]` | Toggle max mode on supported models |
| `/sandbox` | Configure sandbox mode and network access |

### Rules & Skills

| Command | Description |
|---------|-------------|
| `/rules` | Create or edit rules |
| `/commands` | Create or edit commands |
| `/create-rule` | Have Agent generate a new rule from your description |
| `/create-skill` | Have Agent generate a new skill from your description |
| `/migrate-to-skills` | Convert eligible rules/commands to skills (Cursor 2.4+) |

### MCP (Model Context Protocol)

| Command | Description |
|---------|-------------|
| `/mcp list` | Browse available MCP servers |
| `/mcp enable` | Enable an MCP server |
| `/mcp disable` | Disable an MCP server |

### Utilities

| Command | Description |
|---------|-------------|
| `/compress` | Summarize conversation to free context space |
| `/copy-request-id` | Copy current request ID to clipboard |
| `/copy-conversation-id` | Copy conversation ID to clipboard |
| `/resume [folder]` | Resume a previous chat by folder name |
| `/usage` | View Cursor streaks and usage stats |
| `/help [command]` | Show help for a command |
| `/feedback` | Share feedback with Cursor |
| `/about` | Show environment and CLI setup details |
| `/logout` | Sign out |
| `/quit` | Exit Cursor |

### Editor & UX

| Command | Description |
|---------|-------------|
| `/vim` | Toggle Vim keybindings |

---

## 1a. Command Reference (Detailed)

Each command's elements, parameters, behavior, and use cases.

### `/plan`

| Element | Details |
|---------|---------|
| **What it does** | Switches to Plan mode — Agent creates a detailed implementation plan *before* writing any code |
| **Parameters** | None |
| **Behavior** | Agent researches your codebase (reads files, docs), asks clarifying questions, then generates a markdown plan with file paths, code references, and implementation steps. Plan appears in an interactive editor; you can edit, add, or remove tasks. When ready, you build directly from the plan |
| **Shortcut** | `Shift + Tab` from the agent input |
| **When to use** | Architectural decisions, unclear requirements, tasks touching many files, complex features with multiple approaches |
| **When to skip** | Quick changes, familiar tasks — Agent mode is faster |

---

### `/ask`

| Element | Details |
|---------|---------|
| **What it does** | Switches to Ask mode — read-only exploration |
| **Parameters** | None |
| **Behavior** | Agent answers questions, explains code, suggests approaches — but does **not** edit files, run terminal commands, or make changes. Safe for "how does this work?" or "what would you suggest?" without side effects |
| **When to use** | Understanding codebase, exploring options, getting explanations, learning |

---

### `/model`

| Element | Details |
|---------|---------|
| **What it does** | Sets the AI model for the current chat or lists available models |
| **Parameters** | Optional: model name (e.g. `claude-4-opus`, `gpt-4o`) |
| **Behavior** | Without args: shows model picker. With arg: switches to that model. Models vary by provider (Anthropic, OpenAI, Google, Cursor Composer, DeepSeek, Grok) and cost |
| **Note** | Model selection is also available in the chat header dropdown |

---

### `/new-chat`

| Element | Details |
|---------|---------|
| **What it does** | Starts a fresh chat session |
| **Parameters** | None |
| **Behavior** | Clears current conversation. Previous chat remains in history but is no longer active. Useful when switching tasks or when context is cluttered |

---

### `/auto-run [on|off|status]`

| Element | Details |
|---------|---------|
| **What it does** | Controls whether Agent executes steps automatically or waits for your approval |
| **Parameters** | `on` — enable auto-run; `off` — disable; `status` — show current state |
| **Behavior** | **ON:** Agent runs terminal commands, applies file edits, and continues through multi-step tasks without pausing. **OFF:** Agent proposes each action and waits for you to approve before executing. **status:** Displays whether auto-run is on or off |
| **When ON** | Trusted tasks, refactors, multi-step workflows where you want continuous execution |
| **When OFF** | Destructive operations, unfamiliar scripts, or when you want to review each step |

---

### `/max-mode [on|off]`

| Element | Details |
|---------|---------|
| **What it does** | Toggles Max mode — extends context window and read limits on supported models |
| **Parameters** | `on` — enable; `off` — disable |
| **Behavior** | **Context:** Unlocks full context window (e.g. Gemini 2.5 Pro: ~200k → ~1M tokens). **Read cap:** Increases per-call read from ~250 to ~750 lines. **Cost:** 1.2× normal API rate; charged per token used |
| **When to use** | Multi-file refactors, large codebase exploration, complex projects. Regular mode is fine for simple tasks |

---

### `/sandbox`

| Element | Details |
|---------|---------|
| **What it does** | Configures sandbox mode and network access for Agent terminal/execution |
| **Parameters** | Opens configuration UI or references `sandbox.json` |
| **Config file** | `~/.cursor/sandbox.json` (global) or `/.cursor/sandbox.json` (workspace). Workspace overrides global |
| **Network policy** | `default` (allow/deny), `allow` (domains/IPs to permit), `deny` (domains/IPs to block). Deny always wins. Private IPs (10.x, 172.16.x, 192.168.x, 127.x) and cloud metadata (169.254.169.254) are blocked by default |
| **When to use** | Restricting Agent's network access for security, or allowing specific APIs/registries |

---

### `/compress`

| Element | Details |
|---------|---------|
| **What it does** | Summarizes the conversation to free context space |
| **Parameters** | None |
| **Behavior** | Replaces older messages with a condensed summary. Preserves semantics and key decisions. Frees tokens for new turns. Cursor also auto-summarizes when approaching context limits |
| **When to use** | Long conversations, "context full" warnings, or when you want to continue a chat without losing the thread |

---

### `/resume [folder]`

| Element | Details |
|---------|---------|
| **What it does** | Resumes a previous chat associated with a folder/workspace |
| **Parameters** | Optional: folder or workspace name |
| **Behavior** | Opens a prior conversation linked to that workspace. Chat history is stored per-workspace in SQLite (`state.vscdb`). Moving or renaming a project can break the link |
| **When to use** | Returning to an earlier session in the same project |

---

### `/rules` and `/commands`

| Element | Details |
|---------|---------|
| **What it does** | Opens the Rules/Commands management UI |
| **Parameters** | None |
| **Behavior** | Launches Cursor Settings → Rules, Commands (or equivalent). Create, edit, enable/disable project rules and custom slash commands |
| **Related** | `/create-rule` and `/create-skill` create new items from chat |

---

### `/create-rule` and `/create-skill`

| Element | Details |
|---------|---------|
| **What it does** | Agent generates a new rule or skill from your description |
| **Parameters** | Your description (typed after the command or in follow-up) |
| **Behavior** | Agent asks clarifying questions if needed, then creates the file in `.cursor/rules/` (rule) or `.cursor/skills/<name>/SKILL.md` (skill) with appropriate frontmatter and content |
| **Rule vs skill** | Rule = short guideline; Skill = multi-step workflow |

---

### `/migrate-to-skills`

| Element | Details |
|---------|---------|
| **What it does** | Converts eligible rules and commands to skills (Cursor 2.4+) |
| **Parameters** | None |
| **Converts** | Slash commands (user + workspace); dynamic rules (`alwaysApply: false`, no globs) |
| **Does not convert** | Rules with `alwaysApply: true`; rules with specific globs; User Rules |

---

### `/mcp list` | `/mcp enable` | `/mcp disable`

| Element | Details |
|---------|---------|
| **What it does** | Manages MCP (Model Context Protocol) servers |
| **Parameters** | `list` — browse; `enable` / `disable` — toggle a server |
| **Behavior** | MCP servers expose tools, resources, and prompts. Cursor discovers them from `mcp.json`. Enable/disable controls which servers are active in chat |
| **Config** | `%USERPROFILE%\.cursor\mcp.json` (or `~/.cursor/mcp.json`) |

---

### `/copy-request-id` and `/copy-conversation-id`

| Element | Details |
|---------|---------|
| **What it does** | Copies an ID to the clipboard |
| **Parameters** | None |
| **Behavior** | **Request ID:** Identifies a single message/request (for support or debugging). **Conversation ID:** Identifies the entire chat thread |
| **When to use** | Bug reports, support tickets, debugging |

---

### `/usage`

| Element | Details |
|---------|---------|
| **What it does** | Shows Cursor usage stats |
| **Parameters** | None |
| **Behavior** | Displays streaks, request counts, and usage relative to your plan limits |

---

### `/help [command]`

| Element | Details |
|---------|---------|
| **What it does** | Shows help for a command |
| **Parameters** | Optional: command name (e.g. `/help compress`) |
| **Behavior** | Without arg: general help. With arg: help for that specific command |

---

### `/vim`

| Element | Details |
|---------|---------|
| **What it does** | Toggles Vim keybindings in the editor |
| **Parameters** | None |
| **Behavior** | Enables/disables Vim-style navigation and editing (h/j/k/l, modes, etc.) in Cursor's text areas |

---

### `/feedback`, `/about`, `/logout`, `/quit`

| Command | Purpose |
|---------|---------|
| `/feedback` | Opens feedback form to send input to Cursor |
| `/about` | Shows environment info, CLI setup, Cursor version |
| `/logout` | Signs out of your Cursor account |
| `/quit` | Exits Cursor (CLI/terminal context) |

---

## 2. @ Mentions (Context Attachment)

Use `@` to attach specific context to your message. Agent uses this to focus on relevant files, docs, or past chats.

### Files & Code

| Mention | Description |
|---------|-------------|
| `@filename.ext` | Attach a specific file |
| `@folder/` | Attach an entire folder |
| `@Code` | Reference specific code (snippets, functions, classes) |
| `#filename.ext` | Focus on a specific file (often combined with @) |

### Search & Indexing

| Mention | Description |
|---------|-------------|
| `@Codebase` | Semantic search across the entire project — Agent gathers, reranks, and reasons over relevant chunks |
| `@Docs` | Search indexed documentation (including custom docs you add) |

### History & Recommendations

| Mention | Description |
|---------|-------------|
| `@Past Chats` | Reference previous conversations for project history |
| `@Recommended` | (Agent mode) Automatically pulls the most relevant context from your codebase |

### Rules & Skills

| Mention | Description |
|---------|-------------|
| `@rule-name` | Manually apply a project rule (e.g. `@git-standards`) |
| `@skill-name` | Attach a skill as context |

### How @Codebase Works

1. **Gathering** — Scans codebase for relevant files and chunks  
2. **Reranking** — Orders context by relevance to your query  
3. **Reasoning** — Plans how to use the context  
4. **Generating** — Produces the response  

Indexing runs automatically (every ~5 min). Use `.cursorignore` to exclude large/generated folders. Configure from **Cursor Settings → Indexing**.

---

## 3. Rules

Rules are persistent instructions included in Agent context. They apply automatically or when @-mentioned.

### Rule Types

| Type | Location | Scope |
|------|----------|-------|
| **Project Rules** | `.cursor/rules/` | Per-repo, version-controlled |
| **User Rules** | Cursor Settings → Rules | Global, all projects |
| **Team Rules** | Cursor Dashboard | Organization-wide (Team/Enterprise) |
| **AGENTS.md** | Project root or subdirs | Simple markdown alternative |

### Precedence (when rules conflict)

1. Team Rules  
2. Project Rules  
3. User Rules  

### Project Rule File Format

**File extensions:** `.md` or `.mdc` (use `.mdc` for frontmatter)

**Frontmatter fields:**

```yaml
---
description: "What the rule does (used for relevance matching)"
globs:
  - "**/*.ts"
  - "src/**/*.tsx"
alwaysApply: false
---
```

| Field | Purpose |
|-------|---------|
| `description` | Shown to Agent for relevance; used when `alwaysApply: false` |
| `globs` | Minimatch patterns — rule applies when matching files are in context |
| `alwaysApply` | `true` = every chat; `false` = intelligently or when @-mentioned |

### Rule Application Modes

| Mode | `alwaysApply` | `globs` | Behavior |
|------|---------------|---------|----------|
| Always Apply | `true` | — | Every chat session |
| Apply Intelligently | `false` | — | When Agent decides it's relevant (uses description) |
| Apply to Specific Files | `false` | patterns | When matching files are in context |
| Apply Manually | `false` | — | When @-mentioned in chat |

### Glob Pattern Notes

- Use **minimatch** syntax
- Must be a YAML list (hyphens, not comma-separated)
- `*.js` does not match `.jsx` — extensions are exact
- `src/*` vs `src/**` behave differently (single vs recursive)

### Creating Rules

- **From Settings:** Cursor Settings → Rules, Commands → + Add Rule  
- **From Chat:** `/create-rule` and describe what you want  

### AGENTS.md

Plain markdown in project root or subdirs. No frontmatter. Nested `AGENTS.md` in subdirs applies when working in that area; more specific overrides parent.

---

## 4. Skills

Skills are multi-step workflows — more detailed than rules, invoked on demand.

### Rules vs Skills

| | Rules | Skills |
|--|-------|--------|
| Purpose | Short guidelines, constraints | Multi-step workflows |
| Length | Few lines to a few hundred | Often longer, step-by-step |
| Application | Auto or by glob | On demand with `/skill-name` or `@skill-name` |
| Example | "Use TypeScript for new files" | "Deploy: run tests, build, deploy, verify" |

### Skill Locations

- `.cursor/skills/your-skill-name/SKILL.md`
- `.agents/skills/`
- `~/.cursor/skills/` (global)

Also loaded from: `.claude/skills/`, `.codex/skills/`, `~/.claude/skills/`, `~/.codex/skills/`

### Creating Skills

- **From Chat:** `/create-skill` and describe the workflow  
- **Manually:** Add `SKILL.md` in `.cursor/skills/your-skill-name/`  

### Using Skills

- Type `/skill-name` in chat (e.g. `/write-tests`)  
- Or `@skill-name` to attach as context  

### Migrating to Skills

`/migrate-to-skills` converts:

- Slash commands (user and workspace)
- Dynamic rules (`alwaysApply: false`, no globs)

Does **not** migrate: rules with `alwaysApply: true` or specific globs, or User Rules.

---

## 5. Custom Commands

Custom commands are slash-triggered workflows stored in `.cursor/rules/` (often in a `Commands/` subfolder). They behave like rules but are invoked explicitly.

### Structure

- Filename pattern: `command-*.mdc` or `commands.mdc`
- Same frontmatter as rules
- Content describes what happens when the user types `/command-name`

### Example

```markdown
---
description: When user says /commit, run git add, commit, and push
alwaysApply: true
---

# Command /commit

When the user types `/commit`:
1. git add -A
2. git commit -m "<message from user or generated>"
3. git push
```

### Creating Commands

- **From Chat:** Ask Agent to create a command rule  
- **From Settings:** Cursor Settings → Rules, Commands → + Add Rule (then structure as command)  

---

## 6. MCP (Model Context Protocol)

MCP lets Cursor connect to external tools and data via a standard protocol.

### What MCP Provides

- **Tools** — Executable functions (e.g. run tests, call APIs)
- **Resources** — Contextual data (e.g. DB schemas, configs)
- **Prompts** — Reusable prompt templates

### Managing MCP

- `/mcp list` — Browse servers
- `/mcp enable` — Enable a server
- `/mcp disable` — Disable a server

### Configuration

MCP servers are configured in `%USERPROFILE%\.cursor\mcp.json` (or equivalent). Cursor supports stdio, SSE, and HTTP transports.

### Popular MCP Servers

GitHub, Slack, Figma, Linear, Playwright, Vercel, and many community servers.

---

## 7. Chat Modes

| Mode | Shortcut | Behavior |
|------|----------|----------|
| **Agent** | `⌘.` (Cmd/Ctrl + .) | Full autonomy: file edits, terminal, search |
| **Plan** | `/plan` | Design approach before implementation |
| **Ask** | `/ask` | Read-only; no edits or execution |

---

## 8. Best Practices

### Rules

- Keep rules focused and under ~500 lines
- Reference files with `@filename` instead of copying content
- Use globs to scope rules to relevant files
- Check rules into git for team sharing

### Context

- Use `@Codebase` for broad questions; `@file` for specific edits
- Add `.cursorignore` to exclude `node_modules`, build output, etc.
- Use `/compress` when context is full

### Skills vs Rules

- Use **rules** for "always do X" or "when in Y, do Z"
- Use **skills** for "when I say /deploy, run these steps"

---

## 9. Quick Reference

| Need | Use |
|------|-----|
| Attach a file | `@filename.ext` |
| Search codebase | `@Codebase` |
| Apply a rule manually | `@rule-name` |
| Run a workflow | `/skill-name` |
| New chat | `/new-chat` |
| Free context | `/compress` |
| Create rule | `/create-rule` |
| Create skill | `/create-skill` |
| Manage MCP | `/mcp list` |

---

*Last updated: February 2026. Cursor features change frequently; check [Cursor Docs](https://cursor.com/docs) for the latest.*
