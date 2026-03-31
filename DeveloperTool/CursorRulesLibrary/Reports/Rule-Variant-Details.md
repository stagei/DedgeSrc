# Rule Variant Details — Action Required

Generated: 2026-03-07

This report covers all content variants that need a decision. Identical duplicates and project-specific rules (expected to differ) are excluded.

---

## Already Fixed (No Action Needed)

| Issue | Fix Applied |
|-------|------------|
| 7 files missing `description:` frontmatter | Added YAML frontmatter to all 7 files |
| `git-no-attribution.mdc` — 2 copies (AutoDocJson, CursorDb2McpServer) were less comprehensive | Updated to match the 5-copy version (adds `Co-authored-by:` ban, mentions Cursor by name) |
| `doc-sources-and-attribution.mdc` — AiDoc said "in AiDoc" instead of generic | Changed to "in this workspace" to match DedgePsh |

## Expected Variants (No Action Needed)

These files **should** differ because they contain project-specific content:

| Rule | Why It Differs |
|------|---------------|
| `agent-mistakes.mdc` (2) | Only project name substituted (AutoDocNew ↔ AutoDocJson) |
| `agent-notifications.mdc` (3) | Only the example SMS text differs per project |
| `architecture-and-technology.mdc` (2) | Entirely different architectures (DedgeAuth vs GenericLogHandler) |
| `coding-conventions.mdc` (2) | Entirely different patterns (web API vs WinForms tray app) |
| `csharp-standards.mdc` (2) | Only project name substituted (AutoDocNew ↔ AutoDocJson) |
| `development-guidelines.mdc` (3) | Project-specific coding/testing guidelines |
| `project-overview.mdc` (6) | All unique — project descriptions |
| `commands.mdc` (4) | Project-specific command lists |
| `deploy-publish.mdc` (3) | Project-specific deploy/publish commands |
| `rag-rebuild-and-scripts.mdc` (2) | DedgePsh uses absolute paths to AiDoc; AiDoc uses relative paths. Expected for cross-project reference. |
| `use-rag-for-docs.mdc` (2) | Minor wording + project-specific fallback doc paths |

---

## Decisions Needed

### 1. `documentation-placement.mdc` — Folder Casing: `Docs` vs `docs`

**Projects:** GenericLogHandler, DedgeAuth

| Area | GenericLogHandler | DedgeAuth |
|------|------------------|--------|
| Folder name | `.\Docs` (capital D) | `.\docs` (lowercase d) |
| Examples | `.\Docs\API-Evaluation.md` | `.\docs\API.md` |
| Exceptions | Mentions `DatabaseSchemas\` specifically | Says "a schema folder" generically |

**Recommendation:** Standardize to **lowercase `docs`** — it's the more common convention (GitHub, npm, most open source). Update GenericLogHandler to match DedgeAuth's version with its own project-specific examples.

---

### 2. `documentation-standards.mdc` — Specific vs Generic Class Examples

**Projects:** DedgeCommon, CursorDb2McpServer

| Area | DedgeCommon | CursorDb2McpServer |
|------|---------|-------------------|
| Required class types | Lists specific classes: `Db2Handler`, `DedgeConnection`, `WorkObject` | Generic: "Public API classes", "Core utility classes" |
| NuGet heading | `Update DedgeCommon.csproj:` | `(if applicable)` |

**Recommendation:** Both are fine. DedgeCommon's version is project-specific (mentions its own classes), CursorDb2McpServer's is generic. Since this rule should be generic when promoted to Library, the **CursorDb2McpServer version is the better template** for the Library copy.

---

### 3. `web-testing-methodology.mdc` — Outdated vs Current

**Projects:** GenericLogHandler, DedgeAuth

| Area | GenericLogHandler (OUTDATED) | DedgeAuth (CURRENT) |
|------|-----|------|
| MCP server | `cursor-browser-extension` (old name) | `cursor-ide-browser` (current name) |
| Had frontmatter | No (just added description) | Yes (`alwaysApply: true`) |
| Title | "Web Page Testing Methodology" | "MANDATORY Browser Testing Protocol" |
| Tone | Informational | Mandatory/non-negotiable |
| Tool path | Hardcoded project-specific MCP path | References tools generically |

**Recommendation:** **Replace GenericLogHandler's version with DedgeAuth's version.** The GenericLogHandler copy references the old `cursor-browser-extension` MCP name and project-specific paths. DedgeAuth's version is the authoritative, current standard.

---

### 4. `command-commit.mdc` — Verbose vs Streamlined

**Projects:** CursorDb2McpServer (outlier) vs 7 others (majority)

| Area | CursorDb2McpServer (older) | Majority (newer) |
|------|---------------------------|-------------------|
| Description | `run git add, commit, and push` | `always git add, commit, and push/sync` |
| Trigger words | `"commit and push"` | `"commit", "commit and push"` |
| git add | `git add -A or git add . as appropriate` | `git add -A` (simpler) |
| Structure | Rules inline after steps | Separate `## Rules` section |

**Recommendation:** **Update CursorDb2McpServer to match the majority version.** The majority version is cleaner and more structured.

---

### 5. `command-autocur.mdc` — DedgePsh Outlier

**Projects:** DedgePsh (167 lines) vs 15 others (165 lines)

The first 30 lines are identical. The difference is likely in the deploy section or module references later in the file (DedgePsh is the source project for `_deploy.ps1` and CommonModules, so it may have slightly more specific instructions).

**Recommendation:** Minor difference, likely DedgePsh-specific wording. **Low priority** — investigate only if command behavior differs between projects.

---

### 6. `command-rag-status.mdc` — AiDoc Outlier

**Projects:** AiDoc (outlier) vs 15 others (majority)

**Recommendation:** AiDoc probably has a slightly different RAG configuration. **Low priority** — AiDoc is the RAG source project so a minor variant is expected.

---

### 7. `browser-test-verification-report.mdc` — GenericLogHandler Has Per-App Deploy Sections

**Projects:** GenericLogHandler (outlier, 172 lines) vs 10 others (majority, 166 lines)

Lines 1–138 are identical. The difference is in the "Mandatory Ordering After Deploy" section:

- **Majority:** One combined deploy flow (`Build-And-Publish-ALL.ps1` → `IIS-RedeployAll.ps1` → GrabScreenShot)
- **GenericLogHandler:** Two separate flows — `/deploy` (single app) and `/deployAll` (all apps) — with project-specific `IIS-DeployApp.ps1 -SiteName GenericLogHandler`

**Recommendation:** GenericLogHandler's version is **more detailed and correct** for a per-app workflow. Consider whether all projects should have the dual-flow pattern, or if this is GenericLogHandler-specific. **Medium priority.**

---

### 8. `powershell-standards.mdc` — Project-Specific Server Names

**Projects:** DedgePsh (outlier) vs AiDoc + CursorDb2McpServer (identical pair)

| Area | DedgePsh | AiDoc / CursorDb2McpServer |
|------|----------|---------------------------|
| Intro before code | None (jumps to code) | Explanatory sentence |
| ComputerNameList | `@("p-no1fkmprd-db", "p-no1inlprd-db", "*-app")` — specific servers | `@("*-db", "*-app")` — generic wildcards |
| Modules reference | `` `_Modules/` `` (formatted) | `modules` (plain text) |
| After "handles automatically" | Example workflow section | "Do NOT deploy when" section |

**Recommendation:** DedgePsh's `ComputerNameList` is project-specific. The **AiDoc/CursorDb2McpServer version is more generic** and suitable as a template. DedgePsh should keep its version since it has the correct server names for that project.

---

### 9. `team-and-sms.mdc` — 4 Variants of Increasing Detail

**Projects:** 7 majority (99 lines), GetPeppolDirectory (55 lines), DedgeCommon (65 lines), AiDoc (99 lines, identical to majority)

| Feature | Majority (99 lines) | GetPeppolDirectory (55) | DedgeCommon (65) |
|---------|---------------------|------------------------|---------------|
| SecondaryEmail | Yes | No | No |
| AzurePatFile paths | Yes | No | No |
| ServiceAccounts | Yes | No | No |
| Email lookup function | Yes | No | No |
| PAT file auto-detection | Yes | No | No |
| SMS "Do NOT send" items | 2 items | 2 items | 4 items |
| SMS example | Generic | None | Project-specific |

**Recommendation:** **Update GetPeppolDirectory and DedgeCommon to match the majority version** (99 lines). The majority version has the most complete team data (email, PAT files, service accounts). DedgeCommon's expanded "Do NOT send" list is good — could be merged into the majority.

---

### 10. `app-publish-and-iis-deploy.mdc` — 3 Variants

**Projects:** 4 majority (AutoDocJson, DocView, GenericLogHandler, ServerMonitor), DedgeAuth (outlier), AgriNxt.GrainDryingDeduction (outlier)

DedgeAuth is likely the source of truth for the publish/deploy infrastructure. AgriNxt.GrainDryingDeduction may have been added later with slightly different content.

**Recommendation:** **Investigate DedgeAuth's version** — it's the canonical source for IIS deploy. If the other 2 outliers are just drift, update them. **Medium priority.**

---

### 11. `ecosystem-architecture.mdc` — 3 Variants

**Projects:** 4 majority (AutoDocJson, DocView, GenericLogHandler, ServerMonitor), DedgeAuth (outlier), AgriNxt.GrainDryingDeduction (outlier)

DedgeAuth is the canonical source for ecosystem architecture.

**Recommendation:** DedgeAuth's version is the authoritative source. The majority version may be an older copy. **Compare and update majority to match DedgeAuth if DedgeAuth's is newer.** AgriNxt may have been added with yet another snapshot.

---

### 12. `DedgeAuth-integration.mdc` — 2 Variants

**Projects:** 4 majority (AutoDocJson, DocView, GenericLogHandler, ServerMonitor), AgriNxt.GrainDryingDeduction (outlier)

**Recommendation:** AgriNxt.GrainDryingDeduction likely has a slightly newer or older copy. **Compare and standardize.** Low priority — the integration pattern is the same.

---

### 13. `publish-and-deploy.mdc` — 2 Variants

**Projects:** 4 majority (AutoDocJson, DocView, GenericLogHandler, ServerMonitor), AgriNxt.GrainDryingDeduction (outlier)

**Recommendation:** Same as above — standardize to the majority version. Low priority.

---

## Priority Summary

| Priority | Action | Items |
|----------|--------|-------|
| **High** | Replace outdated file | `web-testing-methodology.mdc` in GenericLogHandler |
| **High** | Standardize | `documentation-placement.mdc` — pick `docs` or `Docs` |
| **Medium** | Update outlier to majority | `command-commit.mdc` in CursorDb2McpServer |
| **Medium** | Update to latest | `team-and-sms.mdc` in GetPeppolDirectory and DedgeCommon |
| **Medium** | Compare and standardize | `browser-test-verification-report.mdc` dual-flow vs single-flow |
| **Medium** | Compare DedgeAuth source | `app-publish-and-iis-deploy.mdc`, `ecosystem-architecture.mdc` |
| **Low** | Minor outlier investigation | `command-autocur.mdc`, `command-rag-status.mdc` |
| **Low** | Standardize to majority | `DedgeAuth-integration.mdc`, `publish-and-deploy.mdc` in AgriNxt |
| **None** | Already correct | `documentation-standards.mdc`, `powershell-standards.mdc` |
