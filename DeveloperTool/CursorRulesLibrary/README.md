# CursorRulesLibrary

Shared Cursor content library and sync tooling for projects under `C:\opt\src`.

## Target Cursor Layout

Each receiving project should use:

- `.cursor/rules/` for persistent rules (`*.mdc`)
- `.cursor/commands/` for slash commands (`*.mdc`)
- `.cursor/skills/<skill-name>/SKILL.md` for project skills

## Library Structure

Source content in this repository:

- `Library/<Theme>/*.mdc` -> rule sources
- `Library/Commands/*.mdc` -> command sources
- `Library/Skills/*.mdc` -> skill sources (converted to `SKILL.md` on export)

## Scripts

All scripts are in `Scripts/` and intended to be run with `pwsh.exe`.

- `Update-LibraryRulesToUsers.ps1`
  - Pattern-based sync of typed content to projects.
  - Rules are selected by detected project themes plus baseline themes.
  - Commands and skills are synced from dedicated Library folders.
  - Skills are written to `.cursor/skills/<name>/SKILL.md`.

- `Restructure-CursorRulesAndCommands.ps1`
  - Migrates legacy project layouts into:
    - `.cursor/rules`
    - `.cursor/commands`
    - `.cursor/skills`
  - Supports git add/commit/push per modified repository.

- `Organize-CursorRules.ps1`
  - Lightweight organizer for classifying `.cursor/rules` content into rules/commands/skills.
  - Useful for local cleanup or preview mode.

- `Analyze-CursorRuleConflicts.ps1`
  - Cross-project analysis for duplicate/variant files in rules, commands, and skills.
  - Outputs markdown report under `Reports/`.

- `Find-MdcProjects.ps1`
  - Finds projects with Cursor content and reports counts for rules/commands/skills.

- `Collect-RulesToAllFoundRules.ps1`
  - Collects project Cursor content snapshots into `_AllFoundRules`.

## Quick Usage

```powershell
# Sync typed content from Library to all projects
pwsh.exe -NoProfile -File "C:\opt\src\CursorRulesLibrary\Scripts\Update-LibraryRulesToUsers.ps1"

# Preview sync only
pwsh.exe -NoProfile -File "C:\opt\src\CursorRulesLibrary\Scripts\Update-LibraryRulesToUsers.ps1" -WhatIf

# Restructure legacy folders in all projects
pwsh.exe -NoProfile -File "C:\opt\src\CursorRulesLibrary\Scripts\Restructure-CursorRulesAndCommands.ps1"

# Analyze conflicts/variants
pwsh.exe -NoProfile -File "C:\opt\src\CursorRulesLibrary\Scripts\Analyze-CursorRuleConflicts.ps1"
```