# DbExplorer - Complete ALL Remaining CLI Refactoring
# Refactors all 26 remaining methods with SQL at once using comprehensive regex patterns

Write-Host "=========== COMPLETING CLI REFACTORING ==========" -ForegroundColor Cyan
Write-Host ""

$file = "Services\CliCommandHandlerService.cs"
$content = Get-Content $file -Raw

# Backup
Copy-Item $file "$file.backup"

# Define all 26 remaining refactorings with precise patterns
$refactorings = @(
    @{ Method = "SearchSourceCodeAsync"; Query = "GetSearchSourceCode"; Params = "schema, searchText" }
    @{ Method = "AnalyzePackageAsync"; Query = "GetAnalyzePackage"; Params = "schema, packageName" }
    @{ Method = "GetPackageDetailsAsync"; Query = "GetPackageDetails"; Params = "schema, packageName" }
    @{ Method = "GetStatisticsOverviewAsync"; Query = "GetStatisticsOverview"; Params = "schema" }
    @{ Method = "GetStatisticsRecommendationsAsync"; Query = "GetStatisticsRecommendations"; Params = "schema" }
    @{ Method = "GetIndexStatisticsAsync"; Query = "GetIndexStatistics"; Params = "schema, tableName" }
    @{ Method = "FindUnusedIndexesAsync"; Query = "FindUnusedIndexes"; Params = "schema" }
    @{ Method = "FindUnusedViewsAsync"; Query = "FindUnusedViews"; Params = "schema" }
    @{ Method = "FindUnusedRoutinesAsync"; Query = "FindUnusedRoutines"; Params = "schema" }
    @{ Method = "GetSchemaMetadataAsync"; Query = "GetSchemaMetadata"; Params = "schema, schema, schema, schema, schema, schema" }
    @{ Method = "GetDatabaseLoadFullAsync"; Query = "GetDatabaseLoadFull"; Params = "schema" }
    @{ Method = "GetTableActivityAsync"; Query = "GetTableActivity"; Params = "schema, tableName" }
    @{ Method = "GetTopActiveTablesAsync"; Query = "GetTopActiveTables"; Params = "schema, limit" }
    @{ Method = "GetLockMonitorFullAsync"; Query = "GetLockMonitorFull"; Params = "" }
    @{ Method = "GetSessionDetailsAsync"; Query = "GetSessionDetails"; Params = "" }
    @{ Method = "GetLongRunningSessionsAsync"; Query = "GetLongRunningSessions"; Params = "" }
    @{ Method = "GetDependencyGraphAsync"; Query = "GetDependencyGraph"; Params = "schema, objectName, schema, objectName" }
    @{ Method = "GetDependencyImpactAsync"; Query = "GetDependencyImpact"; Params = "schema, objectName, schema, objectName" }
    @{ Method = "GenerateMigrationPlanAsync"; Query = "GetGenerateMigrationPlan"; Params = "sourceSchema" }
    @{ Method = "ExportTableDataAsync"; Query = "GetExportTableData"; Params = "schema, tableName, limit" }
    @{ Method = "ListTablespacesAsync"; Query = "ListTablespaces"; Params = "" }
    @{ Method = "ListAllIndexesAsync"; Query = "ListAllIndexes"; Params = "schema" }
    @{ Method = "ListConstraintsAsync"; Query = "ListConstraints"; Params = "schema" }
    @{ Method = "ListSequencesAsync"; Query = "ListSequences"; Params = "schema" }
    @{ Method = "GetDbConfigAsync"; Query = "GetDbConfig"; Params = "" }
    @{ Method = "GetFunctionInfoAsync"; Query = "GetFunctionInfo"; Params = "schema, functionName" }  # Already in JSON from earlier
)

$refactored = 0
$failed = @()

foreach ($r in $refactorings) {
    Write-Host "Refactoring: $($r.Method) -> $($r.Query)..." -ForegroundColor Yellow
    
    # Pattern to match the SQL assignment in this method
    # Matches: var sql = $@"..." or var sql = @"..."
    $sqlPattern = "var sql = (\`$)?@`"[^`"]*`""
    
    # Find the method and its SQL
    if ($content -match "($($r.Method)\([^\)]+\)[\s\S]*?)$sqlPattern") {
        $methodSection = $matches[0]
        $oldSqlAssignment = $matches[2]  # The full "var sql = ..." line
        
        # Create new assignment
        if ($r.Params -eq "") {
            # No parameters
            $newSql = "var sql = _metadataHandler.GetQuery(`"DB2`", `"12.1`", `"$($r.Query)`")"
        } else {
            # Has parameters
            $newSql = "var sql = ReplaceParameters(_metadataHandler.GetQuery(`"DB2`", `"12.1`", `"$($r.Query)`"), $($r.Params))"
        }
        
        # Replace in content
        $content = $content.Replace($oldSqlAssignment, $newSql)
        $refactored++
        Write-Host "  ✅ Refactored" -ForegroundColor Green
    } else {
        $failed += $r.Method
        Write-Host "  ❌ Pattern not found" -ForegroundColor Red
    }
}

# Save refactored content
Set-Content $file -Value $content

Write-Host ""
Write-Host "========== REFACTORING COMPLETE ==========" -ForegroundColor Cyan
Write-Host "✅ Refactored: $refactored/$($refactorings.Count) methods" -ForegroundColor Green

if ($failed.Count -gt 0) {
    Write-Host "⚠️  Failed: $($failed.Count) methods" -ForegroundColor Yellow
    $failed | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
}

Write-Host ""
Write-Host "Backup saved: $file.backup" -ForegroundColor White
Write-Host ""
Write-Host "Next: Build and test" -ForegroundColor Cyan

