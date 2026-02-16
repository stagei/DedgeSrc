# CursorDocIndexQuery

Small project to **auto-download the Cursor CLI** and **test codebase queries** from the command line, with Markdown output.

## Requirements

- **PowerShell 7+** (`pwsh.exe`)
- **Cursor** installed (or at least the CLI; the install script can install the CLI on Windows)
- For codebase context: open the folder you want to query (e.g. `DedgeSrc` or `c:\opt\src`) as your **Cursor workspace** so it is indexed.

## 1. Install Cursor CLI (once)

From this folder:

```powershell
pwsh.exe -File .\Install-CursorCli.ps1
```

This uses the official Windows install: `irm 'https://cursor.com/install?win32=true' | iex`.

After install, ensure the CLI is on your **PATH** (e.g. `$env:USERPROFILE\.local\bin`). Verify:

```powershell
agent --version
```

## 2. Run a test query (Markdown output)

From this folder, run the test app (default: short project summary, output under `.\output\result_<timestamp>.md`):

```powershell
pwsh.exe -File .\Test-CursorDocIndexQuery.ps1
```

Custom query and workspace:

```powershell
pwsh.exe -File .\Test-CursorDocIndexQuery.ps1 -Query "List all PowerShell scripts in this repo. Answer in Markdown with paths."
pwsh.exe -File .\Test-CursorDocIndexQuery.ps1 -WorkspacePath "C:\opt\src" -Query "Which projects contain COBOL or SQL? Answer in Markdown."
```

Parameters:

| Parameter | Description |
|-----------|--------------|
| `Query` | Natural-language question (default: short project summary). Ask for "Markdown" in the prompt to get formatted output. |
| `WorkspacePath` | Folder to run the query from; should be your Cursor workspace so the index is available. Default: parent of this project (DedgeSrc root). |
| `OutputPath` | Full path for the output `.md` file. Default: `.\output\result_yyyyMMdd_HHmmss.md`. |
| `SkipInstallCheck` | Do not check for `agent`/`cursor` in PATH before running. |

## 3. One-shot: install then test

```powershell
pwsh.exe -File .\Install-CursorCli.ps1
# If PATH is updated in this session (or restart terminal), then:
pwsh.exe -File .\Test-CursorDocIndexQuery.ps1
```

## 4. Add folders to be indexed (optional)

The Cursor CLI does not have an “add folder to index” command. Indexing happens when you **open a workspace** in the Cursor IDE. This script creates a **multi-root workspace file** (`.code-workspace`) that lists the folders you want indexed; when you open that file in Cursor, all listed roots are indexed.

From this folder:

```powershell
# Create workspace that includes CursorDocIndexQuery + parent DedgeSrc (default)
pwsh.exe -File .\Add-FoldersToCursorWorkspace.ps1

# Create workspace and open it in Cursor so indexing starts
pwsh.exe -File .\Add-FoldersToCursorWorkspace.ps1 -OpenInCursor

# Custom folders (e.g. this project and c:\opt\src)
pwsh.exe -File .\Add-FoldersToCursorWorkspace.ps1 -FoldersToIndex "C:\opt\src\DedgeSrc\CursorDocIndexQuery","C:\opt\src" -OpenInCursor

# List folders currently in the workspace file
pwsh.exe -File .\Add-FoldersToCursorWorkspace.ps1 -List

# Remove one or more folders from the workspace file
pwsh.exe -File .\Add-FoldersToCursorWorkspace.ps1 -RemovePaths "C:\opt\src\DedgeSrc\CursorDocIndexQuery"
pwsh.exe -File .\Add-FoldersToCursorWorkspace.ps1 -RemovePaths "C:\opt\src\DedgeSrc\CursorDocIndexQuery","C:\opt\src" -OpenInCursor
```

Then in Cursor: **File → Open Workspace from File** and choose `DedgeSrc-Indexed.code-workspace` (or the path you set with `-WorkspaceFilePath`). With `-OpenInCursor`, Cursor opens that workspace for you. The “cursor” shell command must be installed (Cursor: Command Palette → **Shell Command: Install 'cursor' command**).

## Files

| File | Purpose |
|------|---------|
| `Install-CursorCli.ps1` | Downloads and installs Cursor CLI (Windows) via official endpoint. |
| `Test-CursorDocIndexQuery.ps1` | Runs `agent -p "<query>"` from the given workspace and writes the result to a Markdown file. |
| `Run-Test.ps1` | Runs install (if needed) then runs the test query. |
| `Add-FoldersToCursorWorkspace.ps1` | Creates/updates a multi-root `.code-workspace`; use `-List` to list indexed folders, `-RemovePaths` to remove them, or default to add/set folders; optional `-OpenInCursor`. |
| `DedgeSrc-Indexed.code-workspace` | Generated workspace file (after running Add-FoldersToCursorWorkspace.ps1). |
| `output\` | Default directory for result `.md` files (created on first run). |

## Notes

- The **workspace** you open in Cursor is what gets indexed. Run the test from the same folder (or pass `-WorkspacePath`) so the CLI has access to that index.
- CLI command is typically **`agent`** (not `cursor`). The test script looks for `agent` first, then `cursor`.
- For more options (e.g. `--output-format json`), run `agent` directly from the workspace directory.
