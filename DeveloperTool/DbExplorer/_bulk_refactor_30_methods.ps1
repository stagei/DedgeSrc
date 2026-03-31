# Bulk refactor 30 CLI methods to use MetadataHandler

$file = "Services\CliCommandHandlerService.cs"
$content = Get-Content $file -Raw

Write-Host "Refactoring 30 methods..." -ForegroundColor Cyan

# Method -> Query name mapping
$refactorings = @(
    @{ Method = "ListTablesAsync"; Query = "ListTables"; HasParams = $true }
    @{ Method = "GetTriggerUsageAsync"; Query = "GetTriggerUsage"; HasParams = $true }
    @{ Method = "SearchSourceCodeAsync"; Query = "GetSearchSourceCode"; HasParams = $true }
    @{ Method = "AnalyzePackageAsync"; Query = "GetAnalyzePackage"; HasParams = $true }
    @{ Method = "GetPackageDetailsAsync"; Query = "GetPackageDetails"; HasParams = $true }
    @{ Method = "GetStatisticsOverviewAsync"; Query = "GetStatisticsOverview"; HasParams = $true }
    @{ Method = "GetStatisticsRecommendationsAsync"; Query = "GetStatisticsRecommendations"; HasParams = $true }
    @{ Method = "GetIndexStatisticsAsync"; Query = "GetIndexStatistics"; HasParams = $true }
    @{ Method = "FindUnusedIndexesAsync"; Query = "FindUnusedIndexes"; HasParams = $true }
    @{ Method = "FindUnusedViewsAsync"; Query = "FindUnusedViews"; HasParams = $true }
    @{ Method = "FindUnusedRoutinesAsync"; Query = "FindUnusedRoutines"; HasParams = $true }
    @{ Method = "GetSchemaMetadataAsync"; Query = "GetSchemaMetadata"; HasParams = $true }
    @{ Method = "GetDatabaseLoadFullAsync"; Query = "GetDatabaseLoadFull"; HasParams = $true }
    @{ Method = "GetTableActivityAsync"; Query = "GetTableActivity"; HasParams = $true }
    @{ Method = "GetTopActiveTablesAsync"; Query = "GetTopActiveTables"; HasParams = $true }
    @{ Method = "GetLockMonitorFullAsync"; Query = "GetLockMonitorFull"; HasParams = $false }
    @{ Method = "GetSessionDetailsAsync"; Query = "GetSessionDetails"; HasParams = $false }
    @{ Method = "GetLongRunningSessionsAsync"; Query = "GetLongRunningSessions"; HasParams = $false }
    @{ Method = "GetDependencyGraphAsync"; Query = "GetDependencyGraph"; HasParams = $true }
    @{ Method = "GetDependencyImpactAsync"; Query = "GetDependencyImpact"; HasParams = $true }
    @{ Method = "GenerateMigrationPlanAsync"; Query = "GetGenerateMigrationPlan"; HasParams = $true }
    @{ Method = "ExportTableDataAsync"; Query = "GetExportTableData"; HasParams = $true }
    @{ Method = "ListTablespacesAsync"; Query = "ListTablespaces"; HasParams = $false }
    @{ Method = "ListAllIndexesAsync"; Query = "ListAllIndexes"; HasParams = $true }
    @{ Method = "ListConstraintsAsync"; Query = "ListConstraints"; HasParams = $true }
    @{ Method = "ListSequencesAsync"; Query = "ListSequences"; HasParams = $true }
    @{ Method = "GetTableSizeAsync"; Query = "GetTableSize"; HasParams = $true }
    @{ Method = "GetSchemaSizeAsync"; Query = "GetSchemaSize"; HasParams = $true }
    @{ Method = "GetDbConfigAsync"; Query = "GetDbConfig"; HasParams = $false }
)

$count = 0
foreach ($r in $refactorings) {
    $methodName = $r.Method
    
    # Pattern to find the SQL assignment in this method
    # Look for: var sql = $@"..." or var sql = @"..." in this method
    $pattern = "($methodName\([^\)]+\)[^{]*\{[^}]*?)var sql = (\`$)?@`"[^`"]*`""
    
    if ($r.HasParams) {
        $replacement = "`$1var sql = ReplaceParameters(_metadataHandler.GetQuery(`"DB2`", `"12.1`", `"$($r.Query)`")"
    } else {
        $replacement = "`$1var sql = _metadataHandler.GetQuery(`"DB2`", `"12.1`", `"$($r.Query)`")"
    }
    
    if ($content -match $pattern) {
        Write-Host "  ✅ $methodName -> $($r.Query)" -ForegroundColor Green
        $count++
    } else {
        Write-Host "  ⚠️  $methodName - pattern not found" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Found $count/$($refactorings.Count) methods to refactor" -ForegroundColor Cyan
Write-Host ""
Write-Host "NOTE: This is a preview. Actual refactoring requires careful" -ForegroundColor Yellow
Write-Host "search-replace for each method due to complex patterns." -ForegroundColor Yellow

