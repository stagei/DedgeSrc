# DbExplorer - Bulk CLI SQL Extraction
# Extracts all remaining SQL from CliCommandHandlerService and adds to JSON

Write-Host "=========== BULK CLI SQL EXTRACTION ===========" -ForegroundColor Cyan
Write-Host ""

$cliFile = "Services\CliCommandHandlerService.cs"
$jsonFile = "ConfigFiles\db2_12.1_sql_statements.json"

# Load files
$cliContent = Get-Content $cliFile -Raw
$json = Get-Content $jsonFile | ConvertFrom-Json

$extractedCount = 0
$newQueries = @{}

# Define SQL patterns to extract with their query names
$methodsToExtract = @(
    @{
        Method = "GetActiveSessionsAsync"
        QueryName = "GetActiveSessions"
        Pattern = 'GetActiveSessionsAsync.*?var sql = @"([^"]+)"'
    },
    @{
        Method = "GetDatabaseLoadAsync"
        QueryName = "GetDatabaseLoad"
        Pattern = 'GetDatabaseLoadAsync.*?\$@"([^"]+)"'
    },
    @{
        Method = "GetTableStatsAsync"
        QueryName = "GetTableStatistics"
        Pattern = 'GetTableStatsAsync.*?\$@"([^"]+)"'
    },
    @{
        Method = "GetDependenciesAsync"
        QueryName = "GetTableDependencies"
        Pattern = 'GetDependenciesAsync.*?var sql = \$@"([^"]+)"'
    },
    @{
        Method = "GetCdcInfoAsync"
        QueryName = "GetCdcInfo"
        Pattern = 'GetCdcInfoAsync.*?\$@"([^"]+)"'
    }
)

foreach ($extract in $methodsToExtract) {
    Write-Host "Extracting: $($extract.QueryName) from $($extract.Method)..." -ForegroundColor Yellow
    
    try {
        $regex = [regex]::new($extract.Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $match = $regex.Match($cliContent)
        
        if ($match.Success) {
            $sql = $match.Groups[1].Value.Trim()
            
            # Clean up SQL
            $sql = $sql -replace '\s+', ' '
            $sql = $sql.Trim()
            
            $newQueries[$extract.QueryName] = @{
                sql = $sql
                description = "CLI command: $($extract.Method -replace 'Async', '')"
                parameters = @()
                returns = "Query results"
                source = "CliCommandHandlerService:$($extract.Method)"
            }
            
            Write-Host "  ✅ Extracted $($sql.Length) chars" -ForegroundColor Green
            $extractedCount++
        } else {
            Write-Host "  ❌ Pattern not found" -ForegroundColor Red
        }
    } catch {
        Write-Host "  ❌ Error: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Extracted: $extractedCount queries" -ForegroundColor Green
Write-Host ""
Write-Host "Sample extracted queries:" -ForegroundColor Cyan
$newQueries.Keys | ForEach-Object {
    Write-Host "  $_" -ForegroundColor White
}

