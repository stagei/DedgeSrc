**User command (global):** This file is `%USERPROFILE%\.cursor\commands\azstory.md` -- Cursor loads it in **every** workspace together with project `.cursor/commands`. Matching user rules: `%USERPROFILE%\.cursor\rules\azure-devops.mdc` and `%USERPROFILE%\.cursor\rules\project-structure.mdc`. These are user-level rules loaded automatically in all workspaces.

---

Azure Story Tracker — create, track, and manage Azure DevOps work items with automatic context gathering.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `/azstory` | Full workflow: gather context, pick or create a work item, execute an action |
| `/azstory help` | Show help screen |
| `/azstory status` | Show active items in this project, let user pick one |
| `/azstory <id>` | Target a specific work item by ID |
| `/azstory next-status` | Advance the most recently touched item to its next state |
| `/azstory undo` | Revert the last status change |
| `/azstory subtask` | Create or manage child items (Task/Bug) under a story |
| `/azstory unlinked` | Find AzStory-tagged items not linked to any project |

## References

- Rule (user): `%USERPROFILE%\.cursor\rules\azure-devops.mdc` (loaded automatically in all workspaces)
- Rule (user): `%USERPROFILE%\.cursor\rules\project-structure.mdc` (loaded automatically in all workspaces)
- Helper scripts: `DevTools/AzureTools/Azure-StoryTracker/` (DedgePsh) or `C:\opt\src\DedgePsh\DevTools\AzureTools\Azure-StoryTracker\`
- Work item manager: `DevTools/AzureTools/Azure-DevOpsUserStoryManager/` or `C:\opt\src\DedgePsh\DevTools\AzureTools\Azure-DevOpsUserStoryManager\`
- Bulk creator: `DevTools/AzureTools/Azure-DevOpsItemCreator/` or `C:\opt\src\DedgePsh\DevTools\AzureTools\Azure-DevOpsItemCreator\`

---

## Instructions

### Step 1: Parse the subcommand

Determine which mode to use from the user's message:

- `/azstory help` → display help screen (see below), then stop
- Bare `/azstory` → full flow (Steps 2-7)
- `/azstory status` → status mode (Step 3a)
- `/azstory <number>` → direct work item ID mode (Step 2 with pre-set ID)
- `/azstory next-status` → quick state advancement (see next-status section)
- `/azstory undo` → undo mode (see undo section)
- `/azstory subtask` or `/azstory subtask <parentId>` → subtask mode (see subtask section)
- `/azstory unlinked` → unlinked discovery mode (see unlinked section)

### Step 1a: Identify the project

Use the **project-structure** rule to determine the current project and sub-project:

1. Find the git repository root (where `.git/` lives)
2. Determine the sub-project from the currently open file or working directory
3. For multi-project repos (DedgePsh, DedgePython), identify the leaf sub-project folder
4. For standalone repos, `subProject` is `null`

The `_azstory.json` file always lives at the **git repository root**. Each entry has a `subProject` field (relative path from git root).

**When ambiguous:** Use AskQuestion to let the user pick from available sub-projects.

### Step 2: Load or create `_azstory.json`

- Read `_azstory.json` from the git repository root
- If file does not exist, create it as `[]`
- If a **work item ID was provided** (`/azstory 12345`):
  1. Look up the ID in `_azstory.json`
  2. If **not found**, fetch metadata:

```powershell
pwsh.exe -NoProfile -File "DevTools\AzureTools\Azure-StoryTracker\Get-AzStoryMetadata.ps1" -WorkItemId 12345
```

  3. Parse the returned JSON and add a new entry to `_azstory.json` with current branch and sub-project
  4. Ensure AzStory tag:

```powershell
pwsh.exe -NoProfile -File "DevTools\AzureTools\Azure-StoryTracker\Set-AzStoryTag.ps1" -WorkItemId 12345
```

  5. If **already in the JSON**, refresh `state` and `updated` from live ADO data
  6. Continue to Step 4 with the work item pre-selected

### Step 3: Gather git context (for bare `/azstory` and `/azstory status`)

Run these commands to detect context:

```powershell
$branch = git branch --show-current
git log --oneline -10
git diff --stat HEAD~1
git diff --stat
```

Auto-detect work item IDs from branch name and commit messages:

```powershell
# Regex: (\d{4,}) — match 4+ digit number
if ($branch -match '(\d{4,})') { $workItemId = $matches[1] }

# Regex: #(\d{4,}) — literal '#' then 4+ digit capture group
$commitMsg = git log -1 --pretty=%B
if ($commitMsg -match '#(\d{4,})') { $workItemId = $matches[1] }
```

### Step 3a: `/azstory status` — show status and let user pick

1. Read `_azstory.json`, filter for entries where `state` is `New`, `Active`, or `Resolved`
2. If no active entries, report "No active work items tracked for this project" and offer to scan other projects
3. If active entries exist, present them using AskQuestion with selectable options:
   - Group display: parent stories first, children indented underneath:

```
WI-12345: Implementer ny funksjon (Active) [User Story]
  ├─ WI-12350: Opprett hjelpeskript (Active) [Task]
  ├─ WI-12351: Skriv enhetstester (New) [Task]
  └─ WI-12352: Feil i upsert-logikk (New) [Bug]
WI-12346: Fikset login-feil (Resolved) [Bug]
```

   - Each story, task, and bug is individually selectable
   - Plus: "Create new work item"
   - Plus: "Enter work item ID manually"
4. If user picks an existing item, refresh its state from ADO then continue to Step 4
5. If user enters a new ID manually, go through Step 2's fetch-and-register flow

### Step 4: Present action options

Once a work item is identified, use AskQuestion to offer actions:

- If existing item: Update description, Add comment, Link files/URLs, Add attachment, Change status, Add tags, Create subtask
- If new: Create new work item (Norwegian title/description)
- Bulk creation from JSON template (always available)

The same action set applies to both stories and child items.

If no work item is identified (bare `/azstory`, nothing in branch/commit/JSON):
- **Auto-create a story** from conversation context (Step 4a)
- Or offer: Enter ID manually / Bulk create

### Step 4a: Auto-create story from conversation context

When no existing story is found and the user ran bare `/azstory`:

1. **Gather conversation context:**
   - Summarize the current chat session: what was discussed, what problem was solved, what was built
   - List key decisions made
   - Identify the type: feat (new feature), fix (bug fix), refactor, chore, docs

2. **Gather code context:**
   - `git diff --stat` and `git log --oneline -5`
   - Identify the primary module/script/component affected
   - Count lines added/removed for scope estimate

3. **Generate Norwegian title and rich description:**
   - Title: follow the Norwegian templates from `azure-devops.mdc`
   - Description: **MUST follow the Description Standard in `azure-devops.mdc`**. Generate a full HTML description with ALL required sections:

     a. **Oversikt** — one paragraph summary of what was built/changed and why
     b. **Hva prosjektet gjør** — detailed explanation of purpose, how it works, what it solves. Write for someone unfamiliar with the code.
     c. **Arkitektur** — Mermaid diagram rendered to PNG via `mmdc` and embedded as base64 `<img>` tag (see rendering steps below)
     d. **Arbeidsflyt** — Mermaid diagram rendered the same way
     e. **Filer endret** — bulleted list of key files with brief explanation of each change

   - Add optional sections when relevant: Underkommandoer/API table, Konfigurasjon, Kjente begrensninger

   **Mermaid diagram rendering (mandatory — do NOT use raw code blocks):**

   ADO does not render Mermaid natively. The **only working approach** is: render to SVG via `mmdc`, base64-encode, embed as `<img src="data:image/svg+xml;base64,...">`.

   Use `Cursor-Handler` module functions:

   ```powershell
   Import-Module Cursor-Handler -Force

   # Render each diagram to base64 (white background, 900px width)
   $archB64 = Convert-CursorMermaid -MermaidCode $archMermaid -Name "arch"
   $wfB64 = Convert-CursorMermaid -MermaidCode $wfMermaid -Name "workflow"

   # Embed in HTML
   $archImg = "<img src=`"data:image/svg+xml;base64,$archB64`" alt=`"Arkitekturdiagram`" />"
   $wfImg = "<img src=`"data:image/svg+xml;base64,$wfB64`" alt=`"Arbeidsflytdiagram`" />"
   ```

4. **Discover the Azure DevOps repo and build a link:**

```powershell
Import-Module Cursor-Handler -Force
$org  = Get-AzureDevOpsOrganization
$proj = Get-AzureDevOpsProject
$repo = Get-AzureDevOpsRepository
$branch = git branch --show-current
```

   Build repo link: `https://dev.azure.com/$org/$proj/_git/$repo?version=GB$branch`

5. **Create the work item and set description:**

   Use `Cursor-Handler` module functions. Auth, UTF-8 encoding, and AzStory tagging are handled automatically.

```powershell
Import-Module Cursor-Handler -Force

# Step 1: Create work item (auto-assigns current user, auto-tags AzStory)
$wi = New-CursorWorkItem -Title $title -Type "User Story" -Tags "AzStory;Feature"

# Step 2: Set rich HTML description (handles large content with base64 images)
Set-CursorWorkItemDescription -WorkItemId $wi.id -HtmlDescription $htmlDescription
```

6. **Register in `_azstory.json`** with the returned ID and all metadata

7. **Link repository branch** (see Step 6b below) — immediately after creation, link the current branch to the work item's Development section

### Step 5: Execute action

- Create/update via `Azure-DevOpsUserStoryManager.ps1`
- Bulk create via `Azure-DevOpsItemCreator.ps1`
- Auto-create via Step 4a flow
- Use Norwegian for titles/descriptions, English for tags
- After creating a **new** work item, immediately register it in `_azstory.json`
- **Tag enforcement:** On every action, check if the `AzStory` tag exists. If not, add it via `-Action AddTags -Tags "AzStory"`. This ensures items are discoverable by `/azstory unlinked`.
- **Repo link enforcement:** After every action, check if the work item has a repository branch link (see Step 6b). If not, add one.

### Step 6: Update `_azstory.json`

- Upsert entry by `id` (update if exists, append if new)
- Always refresh: `state`, `updated` timestamp, `context`, `linkedFiles`
- After status change actions, update `state` to the new value
- Use the helper script:

```powershell
pwsh.exe -NoProfile -File "DevTools\AzureTools\Azure-StoryTracker\Update-AzStoryJson.ps1" `
    -Path "<git-root>" -WorkItemId $id -EntryJson $metadataJson
```

### Step 6a: Auto-publish docs on completion

When a story transitions to **Resolved** or **Closed** (via any path — `/azstory next-status`, manual status change, or Step 5):

1. Determine the target folder:
   - If `subProject` is set, use that path relative to the git root
   - If `subProject` is `null`, use the git root itself
2. Execute the `/sysdocs` flow for that folder:
   - Find or generate `README.md`
   - Auto-detect technology
   - Copy to DocView share
   - Refresh DocView cache
   - Generate DocView URL
3. **Link the DocView URL back to the ADO work item** as a hyperlink:

```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $workItemId -Action Link `
    -Url "$docViewUrl" -Title "DocView: $projectName documentation"
```

4. Include the DocView URL in the report to the user
5. If `/sysdocs` fails, warn but don't block — the status update already succeeded

### Step 6b: Auto-link repository branch

On **every `/azstory` interaction** (create, status change, link, comment, subtask — any action), check if the work item has a Git branch link in the Development section. If not, add one.

**When to run:**
- After Step 4a (auto-create story) — link immediately
- After Step 5 (any action on existing story) — check and link if missing
- After `/azstory next-status` — check and link if missing
- After `/azstory <id>` (registering an existing WI) — check and link if missing

**How it works:**

1. Detect if the current workspace is in an Azure DevOps Git repo:

```powershell
Import-Module Cursor-Handler -Force
$repoName = Get-AzureDevOpsRepository
$branch   = git branch --show-current
```

2. If `$repoName` is valid (non-empty, repo exists in ADO), add the branch link:

```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $workItemId -Action RepoLink
```

This uses the new `RepoLink` action which:
- Looks up the repository ID and project ID from the ADO API
- Constructs a `vstfs:///Git/Ref/{projectId}/{repoId}/GB{branch}` artifact URL
- Adds it as an `ArtifactLink` relation (populates the "Development" section)
- Silently skips if the link already exists (no duplicate error)

3. **Optional: specify branch or repo explicitly:**

```powershell
# Link a specific branch (default: current branch)
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $workItemId -Action RepoLink -Url "feature/my-branch"

# Link to a different repo (default: current workspace repo)
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $workItemId -Action RepoLink -Title "DedgeAuth"
```

4. **Update `_azstory.json`:** Set `"repoLinked": true` on the entry after a successful link. Skip the lookup on future interactions if already `true`.

**Failure handling:** If the repo link fails (repo not found, not in ADO, etc.), log a warning but do not block. The work item action already succeeded.

### Step 7: Report to user

- Summary of what was done
- Work item ID and Azure DevOps URL: `https://dev.azure.com/<org>/<proj>/_workitems/edit/<id>`
- Current state of the `_azstory.json` entry
- If docs were published: DocView URL as `[Open in DocView](<url>)`

---

## `/azstory help` — Display help screen

When user types `/azstory help`, display this text and stop:

```
===============================================================
   Azure Story Tracker (/azstory) - Help
===============================================================

SUBCOMMANDS:

  /azstory              Full workflow: gather context, pick or
                        create a work item, execute an action.
                        Auto-creates a story from conversation
                        context if none exists.

  /azstory help         Show this help screen.

  /azstory status       Show all active/open work items tracked
                        in this project's _azstory.json. Pick one
                        to work with.

  /azstory <id>         Target a specific work item by ID. If not
                        in _azstory.json, fetches metadata from
                        Azure DevOps and registers it locally.

  /azstory next-status  Advance the most recently touched item to
                        its next state (New->Active->Resolved->Closed).
                        Auto-proceeds for unambiguous transitions.

  /azstory undo         Revert the last status change on the most
                        recently touched item (single-level undo).

  /azstory subtask      Create a child item (Task or Bug) under the
                        current story, or manage existing children.
                        Children support the same actions as stories:
                        link files/URLs, add attachments, comments,
                        change status, and add tags.

  /azstory unlinked     List all open Azure DevOps items tagged
                        'AzStory' that are not linked to any project.
                        Assign each to a project path or skip.

TRACKING:

  Each project gets a _azstory.json file in its root that tracks
  all work items associated with that project. Git-tracked.

  All items created or touched by /azstory are tagged 'AzStory'
  in Azure DevOps for cross-project discovery.

TOOLS:

  Scripts:  DevTools/AzureTools/Azure-StoryTracker/
  Manager:  DevTools/AzureTools/Azure-DevOpsUserStoryManager/
  Bulk:     DevTools/AzureTools/Azure-DevOpsItemCreator/

STATE TRANSITIONS:

  New -> Active -> Resolved -> Closed
  (Active -> Closed for cancellation, ask user)

EXAMPLES:

  /azstory              After coding, create or update a story
  /azstory 54321        Register and work with WI-54321
  /azstory status       See what's active in this project
  /azstory next-status  Quick bump: Active -> Resolved
  /azstory undo         Oops, revert that status change
  /azstory subtask      Add a subtask to the current story
  /azstory unlinked     Find orphan stories, link to projects
===============================================================
```

---

## `/azstory next-status` — Quick state advancement

1. Read `_azstory.json`, find the entry with the most recent `updated` timestamp
2. Refresh its current `state` from ADO (in case it changed externally)
3. Determine the next state:

| Current State | Next State | Auto? |
|---------------|-----------|-------|
| New | Active | Yes |
| Active | Resolved | Yes |
| Resolved | Closed | Yes |
| Closed | (none) | Terminal — inform user |
| Removed | (none) | Terminal — inform user |

4. **Unambiguous** (New→Active, Active→Resolved, Resolved→Closed): execute immediately via `Azure-DevOpsUserStoryManager.ps1 -Action Status -State <next>`, update `_azstory.json`
5. **Ambiguous or terminal**: use AskQuestion:
   - Active when cancellation suspected: offer Resolved vs Closed
   - Closed/Removed: inform "already terminal", offer to pick a different item
   - Multiple items with same `updated` timestamp: present as options to pick from
6. Update `_azstory.json` with new state, set `previousState` to old state
7. **If new state is Resolved or Closed**: trigger Step 6a (auto-publish docs + link DocView URL to ADO story)
8. **Check repo link**: trigger Step 6b (auto-link repository branch if not already linked)
9. Report: `"WI-12345: Active → Resolved"`

---

## `/azstory undo` — Revert last status change

1. Read `_azstory.json`, find entry with most recent `updated` timestamp
2. Check if entry has a `previousState` field
3. If **no `previousState`**: report "No status change to undo for WI-{id}" and exit
4. If `previousState` exists:
   - Revert ADO state: `Azure-DevOpsUserStoryManager.ps1 -Action Status -State $previousState -WorkItemId $id`
   - Update `_azstory.json`: set `state` back to `previousState`, clear `previousState`, update `updated`
   - Report: `"WI-12345: Resolved → Active (undone)"`
5. Single-level undo only (not a full history stack)

---

## `/azstory subtask` — Create or manage child items (Tasks and Bugs)

Child items are **Task** or **Bug** work items under a parent story/bug. They support the **same full set of actions** as stories.

### Create a new child item

1. Determine the parent story:
   - If user specifies a parent ID (`/azstory subtask 12345`), use that
   - Otherwise use the most recently touched top-level story (latest `updated` where `parentId` is `null`)
   - If no stories tracked: report "No parent story found. Create one first with `/azstory`" and exit
2. **Ask which child type** using AskQuestion:
   - "Task (oppgave)" — a unit of work
   - "Bug (feil)" — a defect discovered during the story
3. Gather context from conversation and `git diff --stat`
4. Generate Norwegian title and description:
   - Task: `"Opprett [komponent]"` or `"Implementer [deloppgave]"`
   - Bug: `"Fikset feil: [problem]"` or `"Feil i [komponent]: [symptom]"`
5. Create the child item:

```powershell
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $parentId -Action Subtask `
    -Title "$title" -Description "$description" -Type "Task"
# Or for Bug:
.\Azure-DevOpsUserStoryManager.ps1 -WorkItemId $parentId -Action Subtask `
    -Title "$title" -Description "$description" -Type "Bug"
```

6. Tag with AzStory: `Set-AzStoryTag.ps1 -WorkItemId $newChildId`
7. Register in `_azstory.json` with `"type": "Task"` or `"type": "Bug"` and `"parentId"` linking to parent
8. Report: `"Created [Task/Bug] WI-{newId} under WI-{parentId}: {title}"`

### Manage an existing child item

Present the **same action menu** as for stories using AskQuestion:
- Update description, Add comment, Link files/URLs, Add attachment, Change status, Add tags

All actions use the **child item's own work item ID**.

### List children under a story

When `/azstory subtask` is invoked and existing children exist in `_azstory.json`:

1. List children grouped by type (Tasks, then Bugs) with state
2. AskQuestion to pick:
   - An existing child to manage
   - "Create new Task (oppgave)"
   - "Create new Bug (feil)"
3. If no children exist, go directly to the type selection + create flow

---

## `/azstory unlinked` — Find and assign orphan stories

1. **Query ADO** for all open tagged items:

```powershell
pwsh.exe -NoProfile -File "DevTools\AzureTools\Azure-StoryTracker\Get-AzStoryUnlinked.ps1"
```

2. **Scan all `_azstory.json` files**:

```powershell
pwsh.exe -NoProfile -File "DevTools\AzureTools\Azure-StoryTracker\Get-AzStoryLinked.ps1"
```

3. **Compute unlinked set**: ADO results minus linked IDs = orphan stories
4. If **no orphans**: report "All AzStory-tagged items are linked to projects" and exit
5. **Present orphans** as a numbered list:

```
Unlinked AzStory work items:

1. WI-12345: "Implementer ny eksportfunksjon" (User Story, Active)
2. WI-12346: "Fikset feil i batch-import" (Bug, Active)
3. WI-12347: "Refaktorert Db2-Handler modul" (User Story, New)

Enter paths as: 1=C:\opt\src\DedgePsh 2=C:\opt\src\DedgeAuth
Leave blank to skip.
```

6. Wait for user to reply with path assignments
7. For each assigned path:
   - Find the nearest git root
   - Fetch full metadata from ADO
   - Upsert into that project's `_azstory.json`
   - Confirm: `"WI-12345 linked to C:\opt\src\DedgePsh\_azstory.json"`
8. Unassigned items remain unlinked (appear again next time)

---

## Mandatory Tag: `AzStory`

Every story created or touched by `/azstory` MUST have the tag `AzStory` in Azure DevOps:

- On **create**: include `AzStory` in initial tags
- On **any action**: if tag is missing, add it via `Set-AzStoryTag.ps1`
- Used by `/azstory unlinked` to find orphan stories

---

## `_azstory.json` Schema

```json
[
  {
    "id": 12345,
    "type": "User Story",
    "parentId": null,
    "title": "Implementer ny eksportfunksjon i Db2-Handler",
    "state": "Active",
    "previousState": null,
    "subProject": "DevTools/DatabaseTools/Db2-Export",
    "assignedTo": "Geir Helge Starholm",
    "areaPath": "Dedge\\DevTools",
    "iterationPath": "Dedge\\Sprint 42",
    "tags": "Feature;InProgress;AzStory",
    "created": "2026-03-26T14:30:00",
    "updated": "2026-03-26T16:00:00",
    "registered": "2026-03-26T14:30:00",
    "branch": "feature/12345-ny-funksjon",
    "context": "Added new data export feature to Db2-Handler module",
    "linkedFiles": [
      "_Modules/Db2-Handler/Db2-Handler.psm1",
      "DevTools/DatabaseTools/Db2-Export/Export-Data.ps1"
    ]
  }
]
```

**Field rules:**

- `id` — Azure DevOps work item ID (integer, primary key for upsert)
- `type` — Work item type (User Story, Task, Bug, Epic)
- `parentId` — Parent work item ID for child items; `null` for top-level
- `state` — Current state, refreshed on every interaction
- `previousState` — Used by `/azstory undo`, cleared after undo
- `subProject` — Relative path from git root; `null` for standalone repos
- `updated` — Refreshed on every interaction
- `registered` — Set once when first added
- `linkedFiles` — Accumulates over time
