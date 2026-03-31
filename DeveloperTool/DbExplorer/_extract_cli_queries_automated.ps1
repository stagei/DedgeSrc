# DbExplorer - Automated CLI SQL Query Extraction
# Phase 1b: Extract 91 SQL queries from CliCommandHandlerService

$ErrorActionPreference = "Stop"

Write-Host "========== CLI SQL QUERY EXTRACTION ==========" -ForegroundColor Cyan
Write-Host ""

# Read the CLI service file
$cliFile = "Services\CliCommandHandlerService.cs"
$content = Get-Content $cliFile -Raw

# Extract all method names from switch statement
$methodPattern = '"([^"]+)"\s*=>\s*await\s+(\w+)'
$methods = [regex]::Matches($content, $methodPattern)

Write-Host "Found $($methods.Count) CLI commands" -ForegroundColor Green
Write-Host ""

# Create output file for query catalog
$outputFile = "cli_queries_catalog.json"
$queries = @()

foreach ($match in $methods) {
    $command = $match.Groups[1].Value
    $methodName = $match.Groups[2].Value
    
    # Find the method implementation
    $methodPattern = "private\s+(?:async\s+)?Task<\w+>\s+$methodName\s*\([^)]+\)\s*\{([^}]+(?:\{[^}]*\}[^}]+)*)\}"
    $methodMatch = [regex]::Match($content, $methodPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    
    if ($methodMatch.Success) {
        $methodBody = $methodMatch.Groups[1].Value
        
        # Extract SQL queries (looking for var sql = @" or string sql = @" or $@")
        # Pattern matches: var sql = @"...", var sql = $@"...", string sql = @"...", etc.
        $sqlPattern = '(?:var|string)\s+\w+Sql\s*=\s*\$?@"([^"]+)"|FROM\s+SYSCAT\.'
        $sqlMatches = [regex]::Matches($methodBody, $sqlPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        
        # Also look for direct SQL in interpolated strings
        if ($sqlMatches.Count -eq 0) {
            $sqlPattern2 = '\$@"\s*(SELECT|INSERT|UPDATE|DELETE|WITH|CALL)[^"]+?"'
            $sqlMatches = [regex]::Matches($methodBody, $sqlPattern2, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
        }
        
        if ($sqlMatches.Count -gt 0) {
            foreach ($sqlMatch in $sqlMatches) {
                $sqlQuery = $sqlMatch.Groups[1].Value.Trim()
                
                # Create query entry
                $queryEntry = @{
                    command = $command
                    method = $methodName
                    query_name = "cli_$($command.Replace('-', '_'))"
                    sql = $sqlQuery
                    extracted = $true
                    requires_params = ($sqlQuery -match '@\w+')
                }
                
                $queries += $queryEntry
                Write-Host "✓ $command ($methodName)" -ForegroundColor Green
            }
        } else {
            # Check if method uses other services (not direct SQL)
            $usesService = $methodBody -match '_\w+Service\.' -or $methodBody -match 'connectionManager\.'
            
            $queryEntry = @{
                command = $command
                method = $methodName
                query_name = "cli_$($command.Replace('-', '_'))"
                sql = $null
                extracted = $false
                uses_service = $usesService
                note = if ($usesService) { "Uses external service - check method body" } else { "No SQL found - review manually" }
            }
            
            $queries += $queryEntry
            Write-Host "⚠ $command ($methodName) - No direct SQL" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✗ $command ($methodName) - Method not found" -ForegroundColor Red
    }
}

# Save to JSON
$output = @{
    total_commands = $queries.Count
    extracted = ($queries | Where-Object { $_.extracted }).Count
    needs_review = ($queries | Where-Object { -not $_.extracted }).Count
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    queries = $queries
} | ConvertTo-Json -Depth 10

Set-Content -Path $outputFile -Value $output

Write-Host ""
Write-Host "========== EXTRACTION COMPLETE ==========" -ForegroundColor Cyan
Write-Host "Total commands: $($queries.Count)" -ForegroundColor White
Write-Host "Direct SQL extracted: $(($queries | Where-Object { $_.extracted }).Count)" -ForegroundColor Green
Write-Host "Needs review: $(($queries | Where-Object { -not $_.extracted }).Count)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Output saved to: $outputFile" -ForegroundColor Cyan
Write-Host "Next: Review queries and update db2_12.1_queries.json" -ForegroundColor Yellow

