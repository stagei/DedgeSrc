**User command (global):** %USERPROFILE%\.cursor\commands\convert2UserRule.md — same behavior as DedgePsh; when generalizing, prefer writing outputs under %USERPROFILE%\.cursor\ and use placeholders for C:\opt\src\DedgePsh unless the user keeps a canonical example.

---

Convert project rule or project slash command into a **generalized (non–project-specific)** version and install it as a **user rule** and/or **user command**.

## When this command runs

The user message is **`/convert2UserRule`** only, or with optional context:

| User input | Behavior |
|------------|----------|
| `/convert2UserRule` | Use the **currently focused file** if it is under `.cursor/rules/*.mdc` or `.cursor/commands/*.md`; otherwise use **AskQuestion** to pick a source file path (or paste path). |
| `/convert2UserRule` with @file or path in message | Treat that path as the **source** to convert. |

---

## Goal

Produce artifacts that work **across repos**, not only DedgePsh:

1. **Generalized content** — remove or abstract org/repo/server-specific literals.
2. **User rule** (optional but default when source is `.mdc`) — write to `%USERPROFILE%\.cursor\rules\<name>.mdc`.
3. **User command** (optional but default when source is `.md` in commands) — write to `%USERPROFILE%\.cursor\commands\<name>.md`.

If the user only wants one artifact (rule *or* command), follow their instruction; otherwise produce both when the source is a rule that references command patterns (or vice versa), only when it makes sense — **default: one output file matching the source type**.

---

## Generalization rules (apply in order)

1. **Paths**
   - Replace fixed workspace roots such as `C:\opt\src\DedgePsh` with placeholders: `<git-root>` or "repository root" and document that user rules apply globally.
   - Replace `C:\opt\src\` with `<opt-src>` or describe as "local source root" where a concrete example helps.
   - Keep **`%USERPROFILE%\.cursor\...`** for targets of user rules/commands (Windows).
   - For scripts that must stay discoverable, add a **canonical example path** line: e.g. `Example (Dedge): C:\opt\src\DedgePsh\...` in a short table — do not require that path at runtime.

2. **Relative paths → full paths (CRITICAL for user rules)**
   - Project rules (`.cursor/rules/*.mdc`) resolve relative paths from the workspace root. User rules have **no fixed workspace root** — relative paths become meaningless.
   - **Every relative path** in the source rule (e.g., `DevTools/CodingTools/Foo/_deploy.ps1`, `_Modules/Bar/Bar.psm1`) MUST be converted to one of:
     - **`<git-root>\` prefix**: `<git-root>\DevTools\CodingTools\Foo\_deploy.ps1` — for paths the agent should resolve at runtime from the open workspace
     - **Canonical full path with label**: `C:\opt\src\DedgePsh\DevTools\CodingTools\Foo\_deploy.ps1` inside a clearly marked "Canonical path (Dedge):" line — for paths that reference a specific known repo
   - For code blocks with relative dot-source paths (`. ".\subfolder\script.ps1"`), rewrite to use the `<git-root>` placeholder or a canonical full path.
   - For frontmatter `globs:` fields, prefix with `**/` to match across any workspace (e.g., `DevTools/Foo/**` → `**/Foo/**` or `**/DevTools/Foo/**`).
   - **Scan the entire rule** for bare relative paths before finalizing — missed relative paths silently break in user rules.

3. **Hosts, databases, ADO**
   - Replace real server hostnames with patterns already used in generic rules (e.g. `dedge-server`) only if the doc is meant to stay internal; for a **portable** user rule, prefer **`\\<server>\opt\`** or "app server per your `project-structure` rule".
   - Azure DevOps org/project: use placeholders `Dedge` / `Dedge` only as **examples**, labeled as such.

4. **Secrets and accounts**
   - Never copy PAT file paths with real secrets; use `C:\opt\data\UserConfig\$env:USERNAME\AzureDevOpsPat.json` style or "configure PAT per your org".

5. **Frontmatter (`.mdc`)**
   - Preserve `description`, `alwaysApply`, `globs` where still valid.
   - For user-wide rules, prefer **`alwaysApply: true`** unless the rule must be file-scoped; then set **`globs`** to broad patterns (e.g. `**/*`) only if appropriate.
   - Add or bump **`description`** to state it is a **user/global** rule.

6. **Commands (`.md`)**
   - Add a short **User command (global)** note at the top (same pattern as `azstory` user copy): where the file lives, that Cursor merges with project commands, and **fallback paths** to canonical repo files if the open project has no copy.

7. **Duplication**
   - Do not leave two conflicting truths: if the project rule says "only DedgePsh", replace with "multi-repo layouts (see project-structure)" or link to a **generic** layout section inside the same file.

---

## Output steps (agent checklist)

1. **Resolve source path** — from focus, @mention, or question.
2. **Read** the full source file.
3. **Draft** generalized markdown (and frontmatter for `.mdc`).
4. **Choose target filename** — kebab-case, stable (e.g. `azure-devops.mdc`); avoid `Dedge`-specific prefixes unless the content is still Dedge-only (then prefer generalizing further or ask user).
5. **Write** to:
   - `%USERPROFILE%\.cursor\rules\<name>.mdc` for rules
   - `%USERPROFILE%\.cursor\commands\<name>.md` for commands  
   Create directories if missing.
6. **Report** to user: absolute paths written, one-line summary of what was abstracted, and whether they should **restart Cursor** to pick up new user commands/rules.

---

## Optional: dual install

If the source is a **rule** that tightly couples to a **command** file (same topic), ask once:

- "Also generate a matching user **command** stub that points to this rule?" — if yes, emit a minimal `*.md` in `%USERPROFILE%\.cursor\commands\` that only references the generalized rule and the high-level workflow.

---

## Do not

- Overwrite user files without showing a **diff summary** or explicit user confirmation if the target already exists (if overwrite, ask **AskQuestion**: Replace / Merge / Cancel).
- Remove license, attribution, or required sections the user mandated in the original rule.
- Commit git changes inside DedgePsh unless the user asks; this command primarily writes under **`%USERPROFILE%\.cursor\`**.

---

## References

- Project rules layout: `.cursor/rules/*.mdc`
- Project commands: `.cursor/commands/*.md`
- User rules: `%USERPROFILE%\.cursor\rules\`
- User commands: `%USERPROFILE%\.cursor\commands\`
- Example user command with fallbacks: `%USERPROFILE%\.cursor\commands\azstory.md` (if present)
