# Temporary script to remove HTML files for fixed errors
# This will allow AutoDocBatchRunner to regenerate them

$ServerWebsPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDoc"

# Get all error files
$errorFiles = Get-ChildItem -Path $ServerWebsPath -Filter "*.err" -ErrorAction SilentlyContinue

if ($null -eq $errorFiles -or $errorFiles.Count -eq 0) {
    Write-Host "No error files found." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($errorFiles.Count) error file(s)" -ForegroundColor Cyan
Write-Host "Checking for corresponding HTML files...`n" -ForegroundColor Cyan

# Get all HTML files (excluding index.html and web.config)
$allHtmlFiles = Get-ChildItem -Path $ServerWebsPath -Filter "*.html" -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -ne "index.html" -and $_.Name -ne "web.config" }

Write-Host "Found $($allHtmlFiles.Count) HTML files in folder`n" -ForegroundColor Cyan

$removedCount = 0
$notFoundCount = 0
$errorBaseNames = @{}
$htmlBaseNames = @{}

# Build lookup for error file base names
foreach ($errFile in $errorFiles) {
    $baseName = $errFile.BaseName
    $errorBaseNames[$baseName] = $true
    
    # For SQL files, also check without .sql suffix
    if ($baseName -match '\.sql$') {
        $baseWithoutSql = $baseName -replace '\.sql$', ''
        $errorBaseNames[$baseWithoutSql] = $true
    }
}

# Build lookup for HTML file base names
foreach ($htmlFile in $allHtmlFiles) {
    $baseName = $htmlFile.BaseName
    $htmlBaseNames[$baseName] = $htmlFile
    
    # For .sql.html files, also check without .sql suffix
    if ($baseName -match '\.sql$') {
        $baseWithoutSql = $baseName -replace '\.sql$', ''
        if (-not $htmlBaseNames.ContainsKey($baseWithoutSql)) {
            $htmlBaseNames[$baseWithoutSql] = $htmlFile
        }
    }
}

# Match and remove HTML files
foreach ($errFile in $errorFiles) {
    $baseName = $errFile.BaseName
    $htmlFileToRemove = $null
    
    # Try exact match first
    if ($htmlBaseNames.ContainsKey($baseName)) {
        $htmlFileToRemove = $htmlBaseNames[$baseName]
    }
    else {
        # Try with .html extension removed
        $baseWithoutHtml = $baseName -replace '\.html$', ''
        if ($htmlBaseNames.ContainsKey($baseWithoutHtml)) {
            $htmlFileToRemove = $htmlBaseNames[$baseWithoutHtml]
        }
    }
    
    if ($null -ne $htmlFileToRemove -and (Test-Path $htmlFileToRemove.FullName)) {
        try {
            Remove-Item $htmlFileToRemove.FullName -Force -ErrorAction Stop
            Write-Host "✓ Removed: $($htmlFileToRemove.Name)" -ForegroundColor Green
            $removedCount++
        }
        catch {
            Write-Host "✗ Failed to remove $($htmlFileToRemove.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "- Not found: $baseName.html (may have been removed already)" -ForegroundColor Yellow
        $notFoundCount++
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Removed: $removedCount" -ForegroundColor Green
Write-Host "  Not found: $notFoundCount" -ForegroundColor Yellow
Write-Host "  Total errors: $($errorFiles.Count)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
