## Remaining / untested functionality (GitChangeActivityReport)

This file tracks what is **not yet validated end-to-end**.

### Known issues / broken
- **`New-GitChangeActivityAiSummary.ps1` currently fails at runtime**
  - Observed error: `Cannot convert the "System.Object[]" value of type "System.Object[]" to type "System.Int32".`
  - Symptom shows up when selecting top repos using `Select-Object -First ...`.
  - Needs fixing before the AI summary step can be used reliably.

### Partially tested
- **`-VerifyTotals` inside `New-GitChangeActivityReport.ps1`**
  - Was validated once for `-DaysBack` runs after changing it to run `Test-GitChangeActivityReportTotals.ps1` in-process.
  - Not validated for the `-FromDate/-ToDate` parameter set (date range → derived days).

### Not tested yet
- **Date range mode**
  - `New-GitChangeActivityReport.ps1 -FromDate/-ToDate` output correctness (commits included/excluded, timezone edges).
  - Verification logic for date range mode.

- **Large-scale repo sets / performance**
  - Runtime and memory behavior across all `C:\opt\src` repos on slow disks.
  - Report size handling (very large markdown files).

- **Headline detection coverage**
  - `.cs`: namespaces/types across multi-type files and newer C# constructs.
  - `.ps1/.psm1`: scripts without `.SYNOPSIS`, scripts with multiple functions.
  - `.sql`: objects with bracketed identifiers and schema-qualified names.

- **Path exclusion behavior**
  - Excluding `*_old*` is implemented, but not validated for edge cases (case sensitivity, `_OLD`, paths with `_old` in filename vs folder).

### Potential enhancements (not implemented)
- **Exclude common vendor/generated folders** (optional switch), e.g. `node_modules`, `runtimes`, `site-packages`, `bin/obj`, `dist/build`.
- **Exclude file extensions** list (optional), e.g. `.dll`, `.exe`, `.png`, `.pdf`, `.zip`.
- **Net change** totals (added - deleted) per repo/folder/file.
- **CSV output** for pivoting in Excel/PowerBI.

### Quick test checklist (recommended next)
- Run `New-GitChangeActivityReport.ps1 -Root C:\opt\src -DaysBack 21 -WriteJson -VerifyTotals` and confirm verify output shows matching totals.
- Fix `New-GitChangeActivityAiSummary.ps1` so it generates `*.AI_SUMMARY.md` successfully.
- Validate date range mode and verify mode for `-FromDate/-ToDate`.
