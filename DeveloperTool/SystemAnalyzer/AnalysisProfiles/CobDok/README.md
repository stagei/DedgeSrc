# CobDok — `all.json`

## Table name: `DBM.MODUL` (not `MODULES`)

In the **COBDOK** database (collection **DBM**), the central **module** table is **`DBM.MODUL`**. There is no `DBM.MODULES` in the scanned COBOL; English “modules” maps to this table.

## Programs in this profile

| Program   | Role |
|-----------|------|
| **DOHSCAN** | Main **loader**: analyses COBOL source and updates COBDOK, including **`INSERT` / `UPDATE` / `DELETE` on `DBM.MODUL`**. |
| **DOHCHK**  | **Check** logic with SQL joining **`DBM.MODUL`**. |
| **DOHCBLD** | **Build** / reporting queries with many **`FROM DBM.MODUL`** / joins. |

## How it was verified

Search under `C:\opt\data\VisualCobol\Sources\cbl` for SQL containing `DBM.MODUL` as the **MODUL** table (pattern excludes `DBM.MODUL_LINJER`).

## Regenerate list

```powershell
pwsh.exe -NoProfile -File .\Build-CobDokAllJson.ps1
```

Writes `all.generated.json` next to this script.

## Run analysis

From repo root:

```powershell
pwsh.exe -NoProfile -File .\Run-Analysis.ps1 `
  -AllJsonPath .\AnalysisProfiles\CobDok\all.json `
  -Alias CobDok
```

## Related data

- Pipeline **COBDOK metadata** often uses **`modul.csv`** (export from COBDOK) — see `CobdokCsvPath` in `src\SystemAnalyzer.Batch\Scripts\Invoke-FullAnalysis.ps1`.
