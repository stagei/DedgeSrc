# Extract all SQL queries from CliCommandHandlerService.cs and generate JSON
param([int]$StartLine = 1, [int]$MaxQueries = 50)

$file = "Services\CliCommandHandlerService.cs"
$content = Get-Content $file -Raw

Write-Host "=== Extracting CLI SQL Queries ===" -ForegroundColor Cyan
Write-Host ""

# Use regex to find all SQL query blocks with their method context
$pattern = '(?ms)// Method: (\w+).*?var sql = \$@"(.*?)";\s'
$matches = [regex]::Matches($content, 'async Task<(?:object|JObject)> (\w+).*?var sql = \$@"(.*?)";', [System.Text.RegularExpressions.RegexOptions]::Singleline)

if ($matches.Count -eq 0) {
    # Try simpler pattern
    $matches = [regex]::Matches($content, 'var sql = \$@"(.*?)";', [System.Text.RegularExpressions.RegexOptions]::Singleline)
}

Write-Host "Found $($matches.Count) SQL queries" -ForegroundColor Yellow
Write-Host ""

# Extract first 10 as sample
$queryNum = 1
foreach ($match in $matches | Select-Object -First 10) {
    $sqlContent = $match.Groups[1].Value
    $firstLine = ($sqlContent -split "`n")[0].Trim()
    
    Write-Host "Query $queryNum : $firstLine..." -ForegroundColor Green
    $queryNum++
}

Write-Host ""
Write-Host "Total CLI queries to migrate: $($matches.Count)" -ForegroundColor Cyan

