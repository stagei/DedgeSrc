# FkKonto — `all.json`

## Purpose

`all.json` lists COBOL programs that reference **FKKONTO** (Innlan accounting database / ERP data area), for SystemAnalyzer runs with area **FkKonto**.

## How it was built

1. Recursive search under `C:\opt\data\VisualCobol\Sources\cbl` for the literal string `FKKONTO` in `*.CBL` / `*.cbl` files.
2. **Included** in the profile: programs with `FKKONTO` in active code (DB2 `CONNECT`, `DCL-DATABASE`, `CNCT-DATABASE`, `WW-UPD-DATABASE`, or file paths under `...\FKKONTO\...`).
3. **Excluded**: `ELISABET`, `ILALKTO`, `ILALKTN` (comment-only), `TPHSCANR` (documentation string only).

## Regenerate (comparison list)

Writes **`all.generated.json`** (does not overwrite curated `all.json`):

```powershell
pwsh.exe -NoProfile -File .\Build-FkKontoAllJson.ps1
```

Override source root or overwrite `all.json`:

```powershell
pwsh.exe -NoProfile -File .\Build-FkKontoAllJson.ps1 -SourceRoot 'D:\Sources\cbl'
pwsh.exe -NoProfile -File .\Build-FkKontoAllJson.ps1 -OutputFile 'all.json'
```

## Run analysis

From repo root:

```powershell
pwsh.exe -NoProfile -File .\Run-Analysis.ps1 `
  -AllJsonPath .\AnalysisProfiles\FkKonto\all.json `
  -Alias FkKonto
```

## Note on AutoDocJson

`C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDocJson` primarily indexes **Dedge** COBOL with **DBM** schema; Innlan **FKKONTO** usage often does not appear there. This seed is therefore based on **source scan**, not AutoDocJson JSON.
