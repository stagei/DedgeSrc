# Visual COBOL Help Export

Exports Rocket Visual COBOL for VS 2022 (v11) help content to **Markdown** (primary output)
and **HTML** (intermediate).

## Source

- **Manifest**: `helpcontentsetup.msha` (references `RocketVisualCOBOL.cab` and `MicroFocus_COBOL_RuntimeServices.cab`)
- **Content**: The `.cab` files from the product install, or extracted from Help Viewer's catalog store
  (e.g. `C:\ProgramData\Microsoft\HelpLibrary2\Catalogs\...`).

## Script

**`Build-VcHelpMarkdown.ps1`** — single script, four steps:

| Step | What it does |
|------|-------------|
| 1 | Extract `.cab` + `.mshc` → raw HTML in `OutputDirectory\html` |
| 2 | Normalize HTML: fix asset paths (`styles/`, `scripts/`, `icons/`), rename each file to `<title>.html`, translate `ms-xhelp://` links to filename-based hrefs |
| 3 | Convert title-based HTML → Markdown via **Doc2Markdown** (`C:\opt\src\DedgeSrc\Doc2Markdown\Doc2Markdown.ps1`) |
| 4 | Rewrite all cross-links in `.md` files to local, editor-safe relative paths (`./Title%20Name.md`) |

## Output location

```
$env:OptPath\src\AiDoc\Rocket Visual Cobol For Visual Studio 2022 Version 11\
    html\   ← intermediate HTML (can be discarded after conversion)
    md\     ← PRIMARY OUTPUT — one .md file per help topic
```

## Usage

```powershell
# Full run from scratch (extract + normalize + convert + fix links)
pwsh.exe -File .\Build-VcHelpMarkdown.ps1 -SourcePath "C:\path\to\vcdocsvs2022_110"

# HTML already extracted; skip extraction
pwsh.exe -File .\Build-VcHelpMarkdown.ps1 -SkipExtract

# .md files already exist; only re-run link fixing
pwsh.exe -File .\Build-VcHelpMarkdown.ps1 -SkipExtract -SkipConvert

# Override output location
pwsh.exe -File .\Build-VcHelpMarkdown.ps1 -SourcePath "C:\..." -OutputDirectory "D:\MyOutput"
```

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-SourcePath` | Folder with `helpcontentsetup.msha` and `.cab` files. Required unless `-SkipExtract`. |
| `-OutputDirectory` | Root output folder. Defaults to `$env:OptPath\src\AiDoc\Rocket Visual Cobol For Visual Studio 2022 Version 11`. |
| `-SkipExtract` | Skip Step 1 (CAB extraction). |
| `-SkipConvert` | Skip Step 3 (Doc2Markdown conversion). |

## Dependencies

- **GlobalFunctions** module (`Import-Module GlobalFunctions -Force`) for `Write-LogMessage`.
- **Doc2Markdown** at `C:\opt\src\DedgeSrc\Doc2Markdown\Doc2Markdown.ps1` (Python-based; see its own README).
- **Windows `expand.exe`** for CAB extraction (built-in on all Windows versions).

## Link format

All generated `.md` cross-links use `./Filename%20With%20Spaces.md` format so that editors
like Cursor treat them as local file paths rather than external URLs.

## Folder layout

```
VcHelpExport\
    Build-VcHelpMarkdown.ps1    ← main script (run this)
    README.md                   ← this file
    _old\                       ← retired individual scripts
        Export-VcHelpToHtmlOrMarkdown.ps1
        Normalize-VcHelpOutput.ps1
        Fix-VcHelpMarkdownLinks.ps1
```
