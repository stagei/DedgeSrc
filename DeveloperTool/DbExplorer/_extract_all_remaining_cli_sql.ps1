# DbExplorer - Extract ALL Remaining CLI SQL
# Extracts all SQL from remaining methods in CliCommandHandlerService

Write-Host "========== EXTRACTING ALL REMAINING CLI SQL ==========" -ForegroundColor Cyan
Write-Host ""

$cliFile = "Services\CliCommandHandlerService.cs"
$content = Get-Content $cliFile -Raw

# Pattern to find methods with direct SQL
$methodPattern = 'private async Task<object> (\w+Async)\([\s\S]*?(?=private async Task<object>|\z)'
$sqlPattern = 'var sql = (\$?@"[^"]*"|\$@"[\s\S]*?")'

$methods = [regex]::Matches($content, $methodPattern)

Write-Host "Found $($methods.Count) total methods" -ForegroundColor White
Write-Host ""

$extracted = @()
$skipped = @()

foreach ($method in $methods) {
    $methodName = $method.Groups[1].Value
    $methodBody = $method.Value
    
    # Check if already using MetadataHandler
    if ($methodBody -match '_metadataHandler\.GetQuery') {
        continue  # Skip already refactored
    }
    
    # Try to extract SQL
    $sqlMatch = [regex]::Match($methodBody, 'var sql = (\$?@"([^"]+)"|@"([^"]+)")', 
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    
    if ($sqlMatch.Success) {
        $sql = $sqlMatch.Groups[2].Value
        if ([string]::IsNullOrWhiteSpace($sql)) {
            $sql = $sqlMatch.Groups[3].Value
        }
        
        # Clean up SQL
        $sql = $sql -replace '\s+', ' '
        $sql = $sql.Trim()
        
        # Extract parameters (look for string interpolation or WHERE clauses)
        $params = @()
        if ($sql -match "'{[^}]+}'") {
            $params += "Uses string interpolation - needs ReplaceParameters"
        }
        
        # Generate query name (remove Async suffix, convert to noun)
        $queryName = $methodName -replace 'Async$', ''
        if ($queryName -match '^Get') {
            # Keep as is
        } elseif ($queryName -match '^List') {
            # Keep as is
        } elseif ($queryName -match '^Find') {
            # Keep as is
        } else {
            # Add Get prefix
            $queryName = "Get$queryName"
        }
        
        $extracted += [PSCustomObject]@{
            Method = $methodName
            QueryName = $queryName
            SQL = $sql.Substring(0, [Math]::Min(150, $sql.Length)) + "..."
            FullSQL = $sql
            Parameters = $params -join ", "
        }
    } else {
        $skipped += $methodName
    }
}

Write-Host "✅ Extracted: $($extracted.Count) methods with SQL" -ForegroundColor Green
Write-Host "⏭️  Skipped: $($skipped.Count) methods (already refactored or no SQL)" -ForegroundColor Yellow
Write-Host ""

# Show summary
Write-Host "Methods with SQL to extract:" -ForegroundColor Cyan
$extracted | ForEach-Object {
    Write-Host "  $($_.Method) -> $($_.QueryName)" -ForegroundColor White
}

Write-Host ""
Write-Host "Exporting to JSON format file..." -ForegroundColor Yellow

# Generate JSON entries
$jsonEntries = @()
foreach ($item in $extracted) {
    $jsonEntry = @"
    "$($item.QueryName)": {
      "sql": "$($item.FullSQL)",
      "description": "CLI command: $($item.Method -replace 'Async', ''). TODO: Add description",
      "parameters": [],
      "returns": "Query results",
      "source": "CliCommandHandlerService:$($item.Method)"
    }
"@
    $jsonEntries += $jsonEntry
}

# Save to file
$output = $jsonEntries -join ",`n"
Set-Content "_extracted_queries.txt" -Value $output

Write-Host ""
Write-Host "✅ Saved to _extracted_queries.txt" -ForegroundColor Green
Write-Host "   Review and add to db2_12.1_sql_statements.json" -ForegroundColor Yellow
Write-Host ""
Write-Host "Total to add: $($extracted.Count) queries" -ForegroundColor Cyan

