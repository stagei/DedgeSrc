## Cursor usage: Git change activity report

### What this tool does
Generates a Markdown report of **your git changes** across **all repositories under a root folder** (default: `C:\opt\src`) for a time window, and can optionally generate a second **AI-style narrative summary** (offline) from JSON output.

Notes:
- Paths containing `*_old*` are **excluded** (to avoid counting archived/generated “_old” folders).
- Author matching uses `git log --author` regex. **Use email addresses** for the most reliable (and usually shortest) command, because author display names vary across repos.

The report includes:
- **Per repository**: total code lines added/removed (excluding `*.md`), and markdown lines added/removed (separate)
- **Functional overview**: grouped by folder
- **Per file/class/script**: headline detection (namespace+type for `.cs`, first function/synopsis for `.ps1`, etc.) and added/removed line statistics

### How to run in Cursor
- Open `New-GitChangeActivityReport.ps1`
- Right-click the file in Explorer (or in the editor) and choose **Run in Terminal**

Or run it manually in the integrated terminal:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\GitTools\GitChangeActivityReport\New-GitChangeActivityReport.ps1"
```

### Recommended: fully automated (report + JSON + totals verification + AI summary)

```powershell
$report = pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\GitTools\GitChangeActivityReport\New-GitChangeActivityReport.ps1" -Root "C:\opt\src" -DaysBack 21 -WriteJson -VerifyTotals
$json = [IO.Path]::ChangeExtension($report, ".json")
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\GitTools\GitChangeActivityReport\New-GitChangeActivityAiSummary.ps1" -InputJsonPath $json
```

### Recommended: compact overview report (per repo, excludes vendor/build/runtime folders)

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\GitTools\GitChangeActivityReport\New-GitChangeActivityReport.ps1" -Root "C:\opt\src" -DaysBack 21 -Authors geir.helge.starholm@Dedge.no -Compact -WriteJson -VerifyTotals
```

Notes:
- Compact mode outputs **max ~10 lines per repo** and avoids file listings.
- Excludes common downloaded/generated/build/runtime folders by default (bin/obj/node_modules/venv/etc.).
- Optional notifications:
  - Add `-SendEmail` to email the report as an attachment (uses `Send-Email` from GlobalFunctions).
  - Add `-SendSms` to send a short SMS “report ready” message (uses `Send-Sms` from GlobalFunctions).

### Common examples

#### Default: last 21 days, root `C:\opt\src`, default author list

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\GitTools\GitChangeActivityReport\New-GitChangeActivityReport.ps1"
```

#### Pick a different root folder

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\GitTools\GitChangeActivityReport\New-GitChangeActivityReport.ps1" -Root "C:\opt\src\GetPeppolDirectory"
```

#### Override authors (name/email)

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\GitTools\GitChangeActivityReport\New-GitChangeActivityReport.ps1" -Authors @('FKGEISTA','geir.helge.starholm@Dedge.no')
```

#### Recommended: email-only author filter (reliable + short)

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\GitTools\GitChangeActivityReport\New-GitChangeActivityReport.ps1" -Root "C:\opt\src" -DaysBack 21 -Authors geir.helge.starholm@Dedge.no -WriteJson -VerifyTotals
```

Notes:
- When calling from the shell, prefer `-Authors email1,email2` (comma-separated) over `@('a','b')` to avoid argument parsing/quoting surprises.

#### Last N days

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\GitTools\GitChangeActivityReport\New-GitChangeActivityReport.ps1" -DaysBack 14
```

#### Specific date range

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\opt\src\DedgePsh\DevTools\GitTools\GitChangeActivityReport\New-GitChangeActivityReport.ps1" -FromDate '2025-12-01' -ToDate '2025-12-18'
```

### Output
The script prints the output report path and writes the report to:
- `C:\opt\src\change_activity_report_YYYYMMDD_HHmm.md`

If you run it with a custom `-OutputPath`, it will write there instead.

If you use `-WriteJson`, it also writes:
- `C:\opt\src\change_activity_report_YYYYMMDD_HHmm.json`

If you run `New-GitChangeActivityAiSummary.ps1` on that JSON, it writes:
- `C:\opt\src\change_activity_report_YYYYMMDD_HHmm.AI_SUMMARY.md`
