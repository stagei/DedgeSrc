# DbExplorer - Batch CLI Refactoring Script
# Automates extraction and refactoring of CLI methods

param(
    [int]$BatchSize = 10,
    [switch]$ExtractOnly,
    [switch]$RefactorOnly
)

$ErrorActionPreference = "Stop"

Write-Host "========== BATCH CLI REFACTORING ==========" -ForegroundColor Cyan
Write-Host "Batch Size: $BatchSize methods" -ForegroundColor White
Write-Host ""

# Read files
$cliFile = "Services\CliCommandHandlerService.cs"
$jsonFile = "ConfigFiles\db2_12.1_sql_statements.json"

if (-not (Test-Path $cliFile)) {
    Write-Host "ERROR: $cliFile not found" -ForegroundColor Red
    exit 1
}

# Step 1: Extract all methods and their SQL
Write-Host "Step 1: Analyzing CLI methods..." -ForegroundColor Cyan

$content = Get-Content $cliFile -Raw

# Find all method signatures
$methodPattern = 'private async Task<object> (\w+Async)\(DB2ConnectionManager'
$methods = [regex]::Matches($content, $methodPattern)

Write-Host "Found $($methods.Count) CLI methods" -ForegroundColor Green

# Step 2: For each method, check if it uses MetadataHandler or direct SQL
$needsRefactoring = @()
$alreadyRefactored = @()

foreach ($match in $methods) {
    $methodName = $match.Groups[1].Value
    
    # Extract method body (simplified - just check for SQL patterns)
    if ($content -match "(?s)$methodName.*?\.GetQuery\(") {
        $alreadyRefactored += $methodName
    } else {
        $needsRefactoring += $methodName
    }
}

Write-Host ""
Write-Host "Already refactored: $($alreadyRefactored.Count)" -ForegroundColor Green
Write-Host "Need refactoring: $($needsRefactoring.Count)" -ForegroundColor Yellow

# Show first batch to refactor
Write-Host ""
Write-Host "Next batch (first $BatchSize methods needing refactoring):" -ForegroundColor Cyan
$nextBatch = $needsRefactoring | Select-Object -First $BatchSize
foreach ($method in $nextBatch) {
    Write-Host "  - $method" -ForegroundColor White
}

Write-Host ""
Write-Host "========== RECOMMENDATIONS ==========" -ForegroundColor Cyan
Write-Host "Methods already using MetadataHandler: $($alreadyRefactored.Count)" -ForegroundColor Green
Write-Host "Methods to refactor: $($needsRefactoring.Count)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Manually review next $BatchSize methods" -ForegroundColor White
Write-Host "  2. Add missing queries to JSON" -ForegroundColor White
Write-Host "  3. Refactor methods to use MetadataHandler" -ForegroundColor White
Write-Host "  4. Build and test" -ForegroundColor White
Write-Host "  5. Commit" -ForegroundColor White

