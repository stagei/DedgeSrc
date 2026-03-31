<#
.SYNOPSIS
    Generates an HTML report from pre-move and post-move verification inventories.

.DESCRIPTION
    Step 7 of the shadow database workflow. Reads the JSON inventory files produced
    by Step-6 (pre-move and post-move phases) and generates a self-contained HTML report
    with a dashboard, object count matrix, row count details, and difference highlights.

    Defaults are loaded from config.json.

.PARAMETER PreMoveJsonPath
    Path to the pre-move JSON inventory file.

.PARAMETER PostMoveJsonPath
    Path to the post-move JSON inventory file. Optional; if not provided, report
    shows only pre-move data.

.PARAMETER OutputPath
    Path for the generated HTML report.

.EXAMPLE
    .\Step-7-GenerateReport.ps1 -PreMoveJsonPath "ExecLogs\server_PreMove_20260322.json" -PostMoveJsonPath "ExecLogs\server_PostMove_20260322.json"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$PreMoveJsonPath,

    [Parameter(Mandatory = $false)]
    [string]$PostMoveJsonPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

Import-Module GlobalFunctions -Force

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Write-LogMessage "Step 7: Generating HTML report" -Level INFO

    if (-not (Test-Path $PreMoveJsonPath)) { throw "PreMove JSON not found: $($PreMoveJsonPath)" }
    $preMoveData = Get-Content $PreMoveJsonPath -Raw | ConvertFrom-Json

    $hasPostMove = $false
    $postMoveData = $null
    if (-not [string]::IsNullOrEmpty($PostMoveJsonPath) -and (Test-Path $PostMoveJsonPath)) {
        $postMoveData = Get-Content $PostMoveJsonPath -Raw | ConvertFrom-Json
        $hasPostMove = $true
    }

    if ([string]::IsNullOrEmpty($OutputPath)) {
        $execLogsDir = Join-Path $PSScriptRoot "ExecLogs"
        if (-not (Test-Path $execLogsDir -PathType Container)) {
            New-Item -Path $execLogsDir -ItemType Directory -Force | Out-Null
        }
        $OutputPath = Join-Path $execLogsDir "$($env:COMPUTERNAME)_Report_$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    }

    function Get-StatusBadge {
        param([bool]$IsMatch, [string]$TrueText = "MATCH", [string]$FalseText = "MISMATCH")
        if ($IsMatch) {
            return "<span class='badge badge-pass'>$($TrueText)</span>"
        } else {
            return "<span class='badge badge-fail'>$($FalseText)</span>"
        }
    }

    $objectTypesHtml = ""
    $objectTypes = @()
    if ($null -ne $preMoveData.ObjectCounts.PSObject) {
        $objectTypes = $preMoveData.ObjectCounts.PSObject.Properties | ForEach-Object { $_.Name }
    }

    foreach ($objType in $objectTypes) {
        $pre = $preMoveData.ObjectCounts.$objType
        $srcCount = $pre.SourceCount
        $tgtCount = if ($null -ne $pre.TargetCount) { $pre.TargetCount } else { "-" }
        $preMatch = if ($null -ne $pre.Match) { Get-StatusBadge -IsMatch $pre.Match } else { "-" }
        $preMissing = if ($null -ne $pre.Missing) { @($pre.Missing).Count } else { 0 }
        $preExtra = if ($null -ne $pre.Extra) { @($pre.Extra).Count } else { 0 }

        $postSrc = "-"; $postTgt = "-"; $postMatch = "-"
        if ($hasPostMove -and $null -ne $postMoveData.ObjectCounts.$objType) {
            $post = $postMoveData.ObjectCounts.$objType
            $postSrc = $post.SourceCount
            $postTgt = if ($null -ne $post.TargetCount) { $post.TargetCount } else { "-" }
            $postMatch = if ($null -ne $post.Match) { Get-StatusBadge -IsMatch $post.Match } else { "-" }
        }

        $objectTypesHtml += @"
        <tr>
            <td><strong>$($objType)</strong></td>
            <td>$($srcCount)</td>
            <td>$($tgtCount)</td>
            <td>$($preMatch)</td>
            <td>$($preMissing)</td>
            <td>$($preExtra)</td>
            <td>$($postSrc)</td>
            <td>$($postMatch)</td>
        </tr>
"@
    }

    $rowCountHtml = ""
    $rowMismatchDetails = ""
    $totalRowTables = 0
    $totalRowMatches = 0
    $totalRowMismatches = 0
    $rowCountEntries = @()

    if ($null -ne $preMoveData.RowCounts.PSObject) {
        $rowCountEntries = $preMoveData.RowCounts.PSObject.Properties | ForEach-Object { $_.Name }
    }

    foreach ($tbl in $rowCountEntries) {
        $pre = $preMoveData.RowCounts.$tbl
        $totalRowTables++
        $srcCount = $pre.Source
        $tgtCount = if ($null -ne $pre.Target) { $pre.Target } else { "-" }
        $isMatch = if ($null -ne $pre.Match) { $pre.Match } else { $true }

        if ($isMatch) {
            $totalRowMatches++
        } else {
            $totalRowMismatches++
            $diff = if ($null -ne $pre.Target) { $pre.Source - $pre.Target } else { 0 }
            $rowMismatchDetails += @"
            <tr class='mismatch-row'>
                <td>$($tbl)</td>
                <td>$($srcCount)</td>
                <td>$($tgtCount)</td>
                <td>$($diff)</td>
            </tr>
"@
        }
    }

    $postMoveRowSummary = ""
    if ($hasPostMove) {
        $postRowEntries = @()
        if ($null -ne $postMoveData.RowCounts.PSObject) {
            $postRowEntries = $postMoveData.RowCounts.PSObject.Properties | ForEach-Object { $_.Name }
        }
        $postRowCount = $postRowEntries.Count
        $postMoveRowSummary = "<p>Post-move row count entries: <strong>$($postRowCount)</strong></p>"
    }

    $missingObjectsHtml = ""
    foreach ($objType in $objectTypes) {
        $pre = $preMoveData.ObjectCounts.$objType
        $missing = @()
        $extra = @()
        if ($null -ne $pre.Missing) { $missing = @($pre.Missing) }
        if ($null -ne $pre.Extra) { $extra = @($pre.Extra) }

        if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
            $missingObjectsHtml += "<div class='diff-section'><h4>$($objType)</h4>"
            if ($missing.Count -gt 0) {
                $missingObjectsHtml += "<p class='diff-label'>Missing in Target ($($missing.Count)):</p><ul>"
                foreach ($m in $missing) {
                    $missingObjectsHtml += "<li>$($m)</li>"
                }
                $missingObjectsHtml += "</ul>"
            }
            if ($extra.Count -gt 0) {
                $missingObjectsHtml += "<p class='diff-label'>Extra in Target ($($extra.Count)):</p><ul>"
                foreach ($e in $extra) {
                    $missingObjectsHtml += "<li>$($e)</li>"
                }
                $missingObjectsHtml += "</ul>"
            }
            $missingObjectsHtml += "</div>"
        }
    }

    $preAllMatch = $preMoveData.Summary.AllMatch
    $overallStatus = if ($preAllMatch) { "PASS" } else { "ISSUES FOUND" }
    $overallClass = if ($preAllMatch) { "status-pass" } else { "status-fail" }

    $reportTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Shadow Pipeline Verification Report</title>
<style>
    :root {
        --bg: #0f1419;
        --surface: #1a1f2e;
        --surface2: #232838;
        --border: #2d3548;
        --text: #e6edf3;
        --text-dim: #8b949e;
        --pass: #3fb950;
        --fail: #f85149;
        --warn: #d29922;
        --accent: #58a6ff;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
        background: var(--bg);
        color: var(--text);
        line-height: 1.6;
        padding: 2rem;
    }
    .container { max-width: 1200px; margin: 0 auto; }
    h1 { font-size: 1.8rem; margin-bottom: 0.5rem; color: var(--accent); }
    h2 { font-size: 1.3rem; margin: 2rem 0 1rem; color: var(--text); border-bottom: 1px solid var(--border); padding-bottom: 0.5rem; }
    h3 { font-size: 1.1rem; margin: 1.5rem 0 0.5rem; color: var(--text-dim); }
    h4 { font-size: 1rem; margin: 0.5rem 0; }
    .meta { color: var(--text-dim); font-size: 0.9rem; margin-bottom: 2rem; }
    .dashboard {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
        gap: 1rem;
        margin-bottom: 2rem;
    }
    .card {
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 8px;
        padding: 1.2rem;
        text-align: center;
    }
    .card .value { font-size: 2rem; font-weight: 700; }
    .card .label { font-size: 0.85rem; color: var(--text-dim); margin-top: 0.3rem; }
    .status-pass .value { color: var(--pass); }
    .status-fail .value { color: var(--fail); }
    table {
        width: 100%;
        border-collapse: collapse;
        background: var(--surface);
        border-radius: 8px;
        overflow: hidden;
        margin-bottom: 1.5rem;
    }
    th, td { padding: 0.6rem 1rem; text-align: left; border-bottom: 1px solid var(--border); }
    th { background: var(--surface2); font-weight: 600; font-size: 0.85rem; text-transform: uppercase; color: var(--text-dim); }
    tr:last-child td { border-bottom: none; }
    .badge { padding: 2px 8px; border-radius: 4px; font-size: 0.8rem; font-weight: 600; }
    .badge-pass { background: rgba(63,185,80,0.15); color: var(--pass); }
    .badge-fail { background: rgba(248,81,73,0.15); color: var(--fail); }
    .mismatch-row td { color: var(--fail); }
    .diff-section { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; margin-bottom: 1rem; }
    .diff-label { font-weight: 600; margin: 0.5rem 0 0.3rem; }
    .diff-section ul { padding-left: 1.5rem; }
    .diff-section li { font-size: 0.9rem; color: var(--text-dim); }
    p { margin: 0.5rem 0; }
</style>
</head>
<body>
<div class="container">
    <h1>Shadow Pipeline Verification Report</h1>
    <div class="meta">
        Generated: $($reportTimestamp) | Server: $($env:COMPUTERNAME)<br>
        Source: $($preMoveData.SourceDb) ($($preMoveData.SourceInst)) | Target: $($preMoveData.TargetDb) ($($preMoveData.TargetInst))
    </div>

    <div class="dashboard">
        <div class="card $($overallClass)">
            <div class="value">$($overallStatus)</div>
            <div class="label">Overall Status</div>
        </div>
        <div class="card">
            <div class="value">$($preMoveData.Summary.TotalObjectTypes)</div>
            <div class="label">Object Types Checked</div>
        </div>
        <div class="card">
            <div class="value">$($totalRowTables)</div>
            <div class="label">Tables Verified</div>
        </div>
        <div class="card $(if ($preMoveData.Summary.ObjectMismatches -gt 0) { 'status-fail' } else { 'status-pass' })">
            <div class="value">$($preMoveData.Summary.ObjectMismatches)</div>
            <div class="label">Object Mismatches</div>
        </div>
        <div class="card $(if ($totalRowMismatches -gt 0) { 'status-fail' } else { 'status-pass' })">
            <div class="value">$($totalRowMismatches)</div>
            <div class="label">Row Count Mismatches</div>
        </div>
    </div>

    <h2>Object Count Matrix</h2>
    <table>
        <thead>
            <tr>
                <th>Object Type</th>
                <th>Source (Pre)</th>
                <th>Target (Pre)</th>
                <th>Pre-Move</th>
                <th>Missing</th>
                <th>Extra</th>
                <th>Post-Move Count</th>
                <th>Post-Move</th>
            </tr>
        </thead>
        <tbody>
            $($objectTypesHtml)
        </tbody>
    </table>

    <h2>Row Count Summary</h2>
    <p>Total tables: <strong>$($totalRowTables)</strong> |
       Matches: <strong>$($totalRowMatches)</strong> |
       Mismatches: <strong>$($totalRowMismatches)</strong></p>
    $($postMoveRowSummary)

    $(if ($totalRowMismatches -gt 0) {
@"
    <h3>Row Count Mismatches</h3>
    <table>
        <thead>
            <tr><th>Table</th><th>Source</th><th>Target</th><th>Difference</th></tr>
        </thead>
        <tbody>
            $($rowMismatchDetails)
        </tbody>
    </table>
"@
    })

    $(if (-not [string]::IsNullOrEmpty($missingObjectsHtml)) {
@"
    <h2>Object Differences Detail</h2>
    $($missingObjectsHtml)
"@
    })

    <h2>Report Metadata</h2>
    <table>
        <tr><td><strong>Pre-Move Inventory</strong></td><td>$($PreMoveJsonPath)</td></tr>
        $(if ($hasPostMove) { "<tr><td><strong>Post-Move Inventory</strong></td><td>$($PostMoveJsonPath)</td></tr>" })
        <tr><td><strong>Pre-Move Timestamp</strong></td><td>$($preMoveData.Timestamp)</td></tr>
        $(if ($hasPostMove) { "<tr><td><strong>Post-Move Timestamp</strong></td><td>$($postMoveData.Timestamp)</td></tr>" })
    </table>
</div>
</body>
</html>
"@

    Set-Content -Path $OutputPath -Value $html -Encoding UTF8 -Force
    Write-LogMessage "HTML report written to: $($OutputPath)" -Level INFO

    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Step 7 FAILED: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
