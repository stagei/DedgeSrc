# Aggressive CLI Completion - Refactor ALL remaining methods NOW

Write-Host "========== AGGRESSIVE CLI COMPLETION ==========" -ForegroundColor Cyan

$file = "Services\CliCommandHandlerService.cs"
$content = Get-Content $file -Raw

# Backup
Copy-Item $file "$file.backup2"

# Find all methods with direct SQL that need refactoring
$methodPattern = 'private async Task<object> (\w+)Async\([^\)]+\).*?var sql = (\$)?@"'
$matches = [regex]::Matches($content, $methodPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

Write-Host "Found $($matches.Count) methods with direct SQL to refactor" -ForegroundColor Yellow
Write-Host ""

$refactored = 0

foreach ($match in $matches) {
    $methodName = $match.Groups[1].Value
    $hasDollar = $match.Groups[2].Success
    
    # Skip if already using MetadataHandler
    $methodStart = $match.Index
    $methodSection = $content.Substring($methodStart, [Math]::Min(500, $content.Length - $methodStart))
    if ($methodSection -match '_metadataHandler') {
        continue
    }
    
    Write-Host "Processing: $methodName..." -ForegroundColor Yellow
    
    # Try to find corresponding query in JSON
    # Convert method name pattern to query name
    $queryName = $methodName
    
    # Common transformations
    if ($queryName -match '^Get(.+)') {
        $queryName = "Get$($matches[0].Groups[1].Value)"
    } elseif ($queryName -match '^List(.+)') {
        $queryName = "List$($matches[0].Groups[1].Value)"
    } elseif ($queryName -match '^Find(.+)') {
        $queryName = "Find$($matches[0].Groups[1].Value)"
    } elseif ($queryName -match '^Analyze(.+)') {
        $queryName = "GetAnalyze$($matches[0].Groups[1].Value)"
    } elseif ($queryName -match '^Generate(.+)') {
        $queryName = "GetGenerate$($matches[0].Groups[1].Value)"
    } elseif ($queryName -match '^Export(.+)') {
        $queryName = "GetExport$($matches[0].Groups[1].Value)"
    }
    
    # Pattern: Find the SQL assignment and replace it
    # Look for: var sql = $@"..." or var sql = @"..."
    $sqlPattern = "($methodName.*?)(var sql = (\`$)?@`"[^`"]+`")"
    
    if ($content -match $sqlPattern) {
        $before = $matches[0].Groups[1].Value
        $oldSql = $matches[0].Groups[2].Value
        
        # Generate replacement - assume parameters needed
        $newSql = "var sql = ReplaceParameters(_metadataHandler.GetQuery(`"DB2`", `"12.1`", `"$queryName`")"
        
        Write-Host "  $methodName -> $queryName" -ForegroundColor Green
        $refactored++
    } else {
        Write-Host "  ⚠️  Pattern not found for $methodName" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Analyzed: $refactored methods" -ForegroundColor Cyan
Write-Host ""
Write-Host "NOTE: Manual verification recommended" -ForegroundColor Yellow
Write-Host "      Script identifies candidates but doesn't modify" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next: Manual batch refactoring of remaining methods" -ForegroundColor Cyan

