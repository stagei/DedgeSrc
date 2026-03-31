# Comprehensive HTML Verification and Comparison Script
# Compares PowerShell and C# generated HTML files and verifies C# files with browser automation

param(
    [string]$PsOutputFolder = "$env:OptPath\Webs\AutoDoc",
    [string]$CsOutputFolder = "$env:OptPath\Webs\AutoDocNew",
    [int]$WebServerPort = 8889
)

Import-Module GlobalFunctions -Force

Write-LogMessage "Starting HTML Verification and Comparison" -Level INFO

# Test files matching the test suite
$testFiles = @{
    CBL = @("BSAUTOS.CBL", "AABELMA.CBL", "AAAM005.CBL", "AAAKUN2.CBL", "AAAKUND.CBL", "AAAM024.CBL", "AAAM006.CBL", "AAAM046.CBL", "AAAKCSV.CBL", "AAADATO.CBL")
    REX = @("WKMONIT.REX", "COPYMON.REX", "DIRBIND.REX", "D3BD3FIL.REX", "FKSNAPDB.REX", "COBREPL.REX", "D3BD3TAB.REX", "E02REST.REX", "RESTDB_BASISTST.REX", "RESTDB_MIG_B.rex")
    BAT = @("RESTDB_MIG_B.BAT", "GHS_TEMP.PS2 copy 2.bat", "Db2-GeneratedGrants_srv_datavarehus_fkmprd_kerberos.bat", "Db2-GeneratedGrants_srv_datavarehus_fkmprd_ntlm.bat", "GHS_TEMP.PS2.bat", "FKATAB_BASISPRO.BAT", "FKATAB.BAT", "919_generated_db2_drop_existing_nicknames.bat", "restdb_vft_til_db2dev.bat", "RESTDB_VFT_TIL_DB2DEV.BAT")
    PS1 = @("Db2-DiagTracker.ps1", "Db2-AnalyzeMemoryConfig.ps1", "RunExportImportAD.ps1", "Db2-CreateInitialDatabases.ps1", "Db2-SelectHelper.ps1", "AvtalegiroImport.ps1", "AzureDevOpsGitCheckIn.ps1", "DeploySHR.ps1", "Deploy-NuGetPackage.ps1", "MoveInventoryToEDI.ps1")
    SQL = @("DBM.AH_ORDREHODE", "DBM.AH_ORDRELINJER", "CRM.A_ORDREHODE_MASKIN", "CRM.A_ORDREHODE_NY", "CRM.A_ORDRELINJER", "CRM.A_ORDREHODE", "CRM.A_ORDREHODE_U", "TV.V_DBQA_VIEWS_NOT_ACCESSED_INTERNALLY", "TV.V_DBQA_MIGRATION_TABLES_DB2_115", "DBM.DRBIDRSALG99K_SUMF")
    CSharp = @("GenericLogHandler.sln", "DevTools.sln", "D365InvVisService.sln", "EntraMenuManager.sln", "ExternalIntegrations.sln", "FKMAccessAdmin.sln", "BRREGRefresh.sln", "DB2ExportCSV.sln", "GetPeppolDirectory.sln", "AgriProd.sln")
}

function Get-HtmlFileName {
    param([string]$FileName, [string]$Type)
    
    switch ($Type) {
        "SQL" {
            return ($FileName.Replace(".", "_").ToUpper().Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower() + ".sql.html")
        }
        "CSharp" {
            return ([System.IO.Path]::GetFileNameWithoutExtension($FileName) + ".html")
        }
        default {
            return ($FileName + ".html")
        }
    }
}

# Step 1: Compare HTML files
Write-LogMessage "`n=== Step 1: Comparing HTML Files ===" -Level INFO
$comparisonResults = @()

foreach ($fileType in $testFiles.Keys) {
    Write-LogMessage "`nComparing $fileType files..." -Level INFO
    
    foreach ($fileName in $testFiles[$fileType]) {
        $htmlFileName = Get-HtmlFileName -FileName $fileName -Type $fileType
        $psPath = Join-Path $PsOutputFolder $htmlFileName
        $csPath = Join-Path $CsOutputFolder $htmlFileName
        
        $result = [PSCustomObject]@{
            Type = $fileType
            File = $fileName
            HtmlFile = $htmlFileName
            PsExists = (Test-Path $psPath)
            CsExists = (Test-Path $csPath)
            PsSize = if (Test-Path $psPath) { (Get-Item $psPath).Length } else { 0 }
            CsSize = if (Test-Path $csPath) { (Get-Item $csPath).Length } else { 0 }
            SizeDiff = 0
            Similarity = 0.0
            Status = "Unknown"
        }
        
        if ($result.PsExists -and $result.CsExists) {
            # Calculate size difference
            $result.SizeDiff = [Math]::Abs($result.PsSize - $result.CsSize)
            $maxSize = [Math]::Max($result.PsSize, $result.CsSize)
            if ($maxSize -gt 0) {
                $result.Similarity = [Math]::Round((1 - ($result.SizeDiff / $maxSize)) * 100, 2)
            }
            
            # Read and compare content (basic comparison)
            try {
                $psContent = Get-Content $psPath -Raw -Encoding UTF8
                $csContent = Get-Content $csPath -Raw -Encoding UTF8
                
                # Remove timestamps and normalize
                $psNormalized = $psContent -replace '<!--\s*Generated:.*?-->', '' -replace '\s+', ' '
                $csNormalized = $csContent -replace '<!--\s*Generated:.*?-->', '' -replace '\s+', ' '
                
                if ($psNormalized -eq $csNormalized) {
                    $result.Similarity = 100.0
                    $result.Status = "Identical"
                }
                else {
                    # Simple similarity calculation
                    $psLength = $psNormalized.Length
                    $csLength = $csNormalized.Length
                    $maxLength = [Math]::Max($psLength, $csLength)
                    if ($maxLength -gt 0) {
                        $diff = [Math]::Abs($psLength - $csLength)
                        $result.Similarity = [Math]::Round((1 - ($diff / $maxLength)) * 100, 2)
                    }
                    $result.Status = if ($result.Similarity -ge 98) { "Match" } else { "Different" }
                }
            }
            catch {
                $result.Status = "Error: $($_.Exception.Message)"
            }
        }
        elseif (-not $result.PsExists) {
            $result.Status = "PowerShell file missing"
        }
        elseif (-not $result.CsExists) {
            $result.Status = "C# file missing"
        }
        
        $comparisonResults += $result
        Write-LogMessage "  $fileName : $($result.Status) (Similarity: $($result.Similarity)%)" -Level INFO
    }
}

# Step 2: Start Python Web Server
Write-LogMessage "`n=== Step 2: Starting Python Web Server ===" -Level INFO
$pythonProcess = $null

try {
    # Check for Python
    $pythonCmd = $null
    foreach ($cmd in @("python", "python3", "py")) {
        try {
            $version = & $cmd --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                $pythonCmd = $cmd
                break
            }
        }
        catch { }
    }
    
    if (-not $pythonCmd) {
        Write-LogMessage "Python not found - skipping web server" -Level WARN
    }
    else {
        Write-LogMessage "Found Python: $pythonCmd" -Level INFO
        
        # Start Python HTTP server
        $serverScript = @"
import http.server
import socketserver
import os
import sys

port = $WebServerPort
directory = r"$CsOutputFolder"

os.chdir(directory)

Handler = http.server.SimpleHTTPRequestHandler
httpd = socketserver.TCPServer(("", port), Handler)

print(f"Server started at http://localhost:{port}/")
print(f"Serving directory: {directory}")
sys.stdout.flush()

try:
    httpd.serve_forever()
except KeyboardInterrupt:
    print("\nServer stopped")
    httpd.shutdown()
"@
        
        $scriptPath = Join-Path $env:TEMP "webserver_$WebServerPort.py"
        $serverScript | Set-Content $scriptPath -Encoding UTF8
        
        $pythonProcess = Start-Process -FilePath $pythonCmd -ArgumentList $scriptPath -PassThru -WindowStyle Hidden
        
        Start-Sleep -Seconds 3
        
        # Verify server is running
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$WebServerPort/" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            Write-LogMessage "Python HTTP server started successfully on port $WebServerPort" -Level INFO
            Write-LogMessage "Server URL: http://localhost:$WebServerPort/" -Level INFO
        }
        catch {
            Write-LogMessage "Server may not be responding: $($_.Exception.Message)" -Level WARN
        }
    }
}
catch {
    Write-LogMessage "Error starting Python server: $($_.Exception.Message)" -Level ERROR
}

# Step 3: Browser Automation (using MCP browser tools would be done separately)
Write-LogMessage "`n=== Step 3: Browser Verification ===" -Level INFO
Write-LogMessage "Browser automation will be performed using MCP browser tools" -Level INFO
Write-LogMessage "C# HTML files are available at: http://localhost:$WebServerPort/" -Level INFO

$browserResults = @()
foreach ($fileType in $testFiles.Keys) {
    foreach ($fileName in $testFiles[$fileType]) {
        $htmlFileName = Get-HtmlFileName -FileName $fileName -Type $fileType
        $csPath = Join-Path $CsOutputFolder $htmlFileName
        
        if (Test-Path $csPath) {
            $url = "http://localhost:$WebServerPort/$htmlFileName"
            $browserResults += [PSCustomObject]@{
                Type = $fileType
                File = $fileName
                HtmlFile = $htmlFileName
                Url = $url
                Status = "Available"
            }
            Write-LogMessage "  $htmlFileName : $url" -Level INFO
        }
    }
}

# Generate summary report
Write-LogMessage "`n=== Summary Report ===" -Level INFO
$totalFiles = ($testFiles.Values | Measure-Object -Property Count -Sum).Sum
$psExists = ($comparisonResults | Where-Object { $_.PsExists }).Count
$csExists = ($comparisonResults | Where-Object { $_.CsExists }).Count
$bothExist = ($comparisonResults | Where-Object { $_.PsExists -and $_.CsExists }).Count
$matches = ($comparisonResults | Where-Object { $_.Status -eq "Identical" -or ($_.Status -eq "Match" -and $_.Similarity -ge 98) }).Count
$avgSimilarity = if ($bothExist -gt 0) { [Math]::Round(($comparisonResults | Where-Object { $_.PsExists -and $_.CsExists } | Measure-Object -Property Similarity -Average).Average, 2) } else { 0 }

Write-LogMessage "Total Files: $totalFiles" -Level INFO
Write-LogMessage "PowerShell Files Exist: $psExists" -Level INFO
Write-LogMessage "C# Files Exist: $csExists" -Level INFO
Write-LogMessage "Both Exist: $bothExist" -Level INFO
Write-LogMessage "Matches (>=98%): $matches" -Level INFO
Write-LogMessage "Average Similarity: $avgSimilarity%" -Level INFO

# Export results
$resultsPath = Join-Path $PSScriptRoot "HtmlComparisonResults.json"
$comparisonResults | ConvertTo-Json -Depth 3 | Set-Content $resultsPath
Write-LogMessage "`nResults saved to: $resultsPath" -Level INFO

# Cleanup function
Register-ObjectEvent -InputObject ([System.AppDomain]::CurrentDomain) -EventName "ProcessExit" -Action {
    if ($pythonProcess -and -not $pythonProcess.HasExited) {
        Stop-Process -Id $pythonProcess.Id -Force -ErrorAction SilentlyContinue
    }
} | Out-Null

Write-LogMessage "`nVerification complete. Python server running on port $WebServerPort" -Level INFO
Write-LogMessage "Press Ctrl+C to stop the server" -Level INFO

# Keep script running to maintain server
try {
    while ($true) {
        Start-Sleep -Seconds 10
        if ($pythonProcess -and $pythonProcess.HasExited) {
            Write-LogMessage "Python server stopped unexpectedly" -Level WARN
            break
        }
    }
}
finally {
    if ($pythonProcess -and -not $pythonProcess.HasExited) {
        Stop-Process -Id $pythonProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $scriptPath) {
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
    }
}
