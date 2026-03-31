# Run PowerShell AutoDocBatchRunner for test files
# This script runs the PowerShell batch runner for the same 10 files of each type used in C# tests

param(
    [string]$OutputFolder = "$env:OptPath\Webs\AutoDoc",
    [string]$BatchRunnerPath = "$PSScriptRoot\..\..\DevTools\LegacyCodeTools\AutoDoc\AutoDocBatchRunner.ps1"
)

Import-Module GlobalFunctions -Force

Write-LogMessage "Starting PowerShell AutoDocBatchRunner for test files" -Level INFO

# Test files matching the C# test suite
$testFiles = @{
    CBL = @(
        "BSAUTOS.CBL", "AABELMA.CBL", "AAAM005.CBL", "AAAKUN2.CBL", "AAAKUND.CBL",
        "AAAM024.CBL", "AAAM006.CBL", "AAAM046.CBL", "AAAKCSV.CBL", "AAADATO.CBL"
    )
    REX = @(
        "WKMONIT.REX", "COPYMON.REX", "DIRBIND.REX", "D3BD3FIL.REX", "FKSNAPDB.REX",
        "COBREPL.REX", "D3BD3TAB.REX", "E02REST.REX", "RESTDB_BASISTST.REX", "RESTDB_MIG_B.rex"
    )
    BAT = @(
        "RESTDB_MIG_B.BAT", "GHS_TEMP.PS2 copy 2.bat", "Db2-GeneratedGrants_srv_datavarehus_fkmprd_kerberos.bat",
        "Db2-GeneratedGrants_srv_datavarehus_fkmprd_ntlm.bat", "GHS_TEMP.PS2.bat",
        "FKATAB_BASISPRO.BAT", "FKATAB.BAT", "919_generated_db2_drop_existing_nicknames.bat",
        "restdb_vft_til_db2dev.bat", "RESTDB_VFT_TIL_DB2DEV.BAT"
    )
    PS1 = @(
        "Db2-DiagTracker.ps1", "Db2-AnalyzeMemoryConfig.ps1", "RunExportImportAD.ps1",
        "Db2-CreateInitialDatabases.ps1", "Db2-SelectHelper.ps1", "AvtalegiroImport.ps1",
        "AzureDevOpsGitCheckIn.ps1", "DeploySHR.ps1", "Deploy-NuGetPackage.ps1", "MoveInventoryToEDI.ps1"
    )
    Sql = @(
        "DBM.AH_ORDREHODE", "DBM.AH_ORDRELINJER", "CRM.A_ORDREHODE_MASKIN", "CRM.A_ORDREHODE_NY",
        "CRM.A_ORDRELINJER", "CRM.A_ORDREHODE", "CRM.A_ORDREHODE_U",
        "TV.V_DBQA_VIEWS_NOT_ACCESSED_INTERNALLY", "TV.V_DBQA_MIGRATION_TABLES_DB2_115", "DBM.DRBIDRSALG99K_SUMF"
    )
    CSharp = @(
        "GenericLogHandler.sln", "DevTools.sln", "D365InvVisService.sln", "EntraMenuManager.sln",
        "ExternalIntegrations.sln", "FKMAccessAdmin.sln", "BRREGRefresh.sln", "DB2ExportCSV.sln",
        "GetPeppolDirectory.sln", "AgriProd.sln"
    )
}

$totalFiles = ($testFiles.Values | Measure-Object -Property Count -Sum).Sum
Write-LogMessage "Processing $totalFiles test files across $(@($testFiles.Keys).Count) file types" -Level INFO

$successCount = 0
$failCount = 0
$results = @()

foreach ($fileType in $testFiles.Keys) {
    Write-LogMessage "`nProcessing $fileType files..." -Level INFO
    
    foreach ($fileName in $testFiles[$fileType]) {
        Write-LogMessage "  Processing: $fileName" -Level INFO
        
        try {
            # Run batch runner in Single mode for this specific file
            $params = @{
                Regenerate = "Single"
                SingleFile = $fileName
                FileTypes = @($fileType)
                OutputFolder = $OutputFolder
                ClientSideRender = $true
                SaveMmdFiles = $true
                Parallel = $false
                QuickRun = $true
            }
            
            & $BatchRunnerPath @params
            
            if ($LASTEXITCODE -eq 0) {
                $successCount++
                $results += [PSCustomObject]@{
                    Type = $fileType
                    File = $fileName
                    Status = "Success"
                }
                Write-LogMessage "    ✓ Success" -Level INFO
            }
            else {
                $failCount++
                $results += [PSCustomObject]@{
                    Type = $fileType
                    File = $fileName
                    Status = "Failed"
                }
                Write-LogMessage "    ✗ Failed (ExitCode: $LASTEXITCODE)" -Level ERROR
            }
        }
        catch {
            $failCount++
            $results += [PSCustomObject]@{
                Type = $fileType
                File = $fileName
                Status = "Error: $($_.Exception.Message)"
            }
            Write-LogMessage "    ✗ Error: $($_.Exception.Message)" -Level ERROR
        }
    }
}

Write-LogMessage "`n=== PowerShell Batch Runner Summary ===" -Level INFO
Write-LogMessage "Total Files: $totalFiles" -Level INFO
Write-LogMessage "Success: $successCount" -Level INFO
Write-LogMessage "Failed: $failCount" -Level INFO

# Export results
$resultsPath = Join-Path $PSScriptRoot "PowerShellBatchRunnerResults.json"
$results | ConvertTo-Json -Depth 3 | Set-Content $resultsPath
Write-LogMessage "Results saved to: $resultsPath" -Level INFO

if ($failCount -gt 0) {
    Write-LogMessage "Some files failed to process. Check logs for details." -Level WARN
    exit 1
}
else {
    Write-LogMessage "All files processed successfully!" -Level INFO
    exit 0
}
