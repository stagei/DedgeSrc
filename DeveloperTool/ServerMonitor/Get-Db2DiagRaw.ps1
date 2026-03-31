<#
.SYNOPSIS
    Extracts all DB2 diagnostic raw blocks from a ServerMonitor agent API.
.DESCRIPTION
    Calls the snapshot API with includeAllDb2Entries=true and extracts all rawBlock
    fields from the DB2 diagnostics entries, saving them to a text file.
.PARAMETER Server
    The server hostname running the ServerMonitor agent. Default: p-no1fkmprd-db
.PARAMETER Port
    The API port. Default: 8999
.PARAMETER OutputFile
    The output file path. Default: test.txt in script directory
.EXAMPLE
    .\Get-Db2DiagRaw.ps1 -Server "p-no1fkmprd-db" -OutputFile "db2diag_raw.txt"
#>
param(
    [string]$Server = "p-no1fkmprd-db",
    [int]$Port = 8999,
    [string]$OutputFile = "test.txt"
)

$startTime = Get-Date
Write-Host "⏱️  START: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "Action: Fetching all DB2 diagnostic entries from $($Server):$($Port)`n" -ForegroundColor Cyan

try {
    # Build API URL
    $apiUrl = "http://$($Server):$($Port)/api/snapshot?includeAllDb2Entries=true"
    Write-Host "Calling API: $apiUrl" -ForegroundColor Gray
    
    # Call the API
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 120
    
    # Check if DB2 diagnostics data exists
    if (-not $response.db2Diagnostics) {
        Write-Host "❌ No db2Diagnostics section in response" -ForegroundColor Red
        exit 1
    }
    
    $allEntries = $response.db2Diagnostics.allEntries
    if (-not $allEntries -or $allEntries.Count -eq 0) {
        Write-Host "❌ No allEntries found in db2Diagnostics" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Found $($allEntries.Count) DB2 diagnostic entries" -ForegroundColor Green
    
    # Extract rawBlock from each entry
    $rawBlocks = @()
    $entriesWithRaw = 0
    foreach ($entry in $allEntries) {
        if ($entry.rawBlock) {
            $rawBlocks += $entry.rawBlock
            $entriesWithRaw++
        }
    }
    
    Write-Host "Entries with rawBlock: $entriesWithRaw" -ForegroundColor Cyan
    
    if ($rawBlocks.Count -eq 0) {
        Write-Host "❌ No rawBlock fields found in entries" -ForegroundColor Red
        exit 1
    }
    
    # Resolve output path
    if (-not [System.IO.Path]::IsPathRooted($OutputFile)) {
        $OutputFile = Join-Path $PSScriptRoot $OutputFile
    }
    
    # Join with separator and save to file
    $separator = "`n`n========================================`n`n"
    $content = $rawBlocks -join $separator
    
    $content | Out-File -FilePath $OutputFile -Encoding UTF8
    
    $fileSizeKB = [math]::Round((Get-Item $OutputFile).Length / 1KB, 2)
    Write-Host "`n✅ Saved $($rawBlocks.Count) raw blocks to: $OutputFile" -ForegroundColor Green
    Write-Host "   File size: $fileSizeKB KB" -ForegroundColor Gray
    
} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n⏱️  END: $(Get-Date -Format 'HH:mm:ss') | Duration: $([math]::Round(((Get-Date) - $startTime).TotalSeconds, 1))s" -ForegroundColor Yellow
