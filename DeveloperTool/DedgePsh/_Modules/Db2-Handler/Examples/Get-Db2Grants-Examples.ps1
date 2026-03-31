# Examples of using the new DB2 Grant functions
# Import the module first
Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

# Example 1: Get all table/view grants for a specific database
Write-LogMessage "Example 1: Getting all table/view grants" -Level INFO
$tableGrants = Get-Db2TableGrants -DatabaseName "SAMPLE"
$tableGrants | Format-Table -AutoSize

# Example 2: Get table grants for a specific schema and user
Write-LogMessage "Example 2: Getting table grants for DBM schema and SRV_KPDB user" -Level INFO
$specificTableGrants = Get-Db2TableGrants -DatabaseName "SAMPLE" -SchemaName "DBM" -Grantee "SRV_KPDB"
$specificTableGrants | Format-Table -AutoSize

# Example 3: Get all routine grants (functions/procedures)
Write-LogMessage "Example 3: Getting all routine grants" -Level INFO
$routineGrants = Get-Db2RoutineGrants -DatabaseName "SAMPLE"
$routineGrants | Format-Table -AutoSize

# Example 4: Get schema grants
Write-LogMessage "Example 4: Getting all schema grants" -Level INFO
$schemaGrants = Get-Db2SchemaGrants -DatabaseName "SAMPLE"
$schemaGrants | Format-Table -AutoSize

# Example 5: Get package grants
Write-LogMessage "Example 5: Getting all package grants" -Level INFO
$packageGrants = Get-Db2PackageGrants -DatabaseName "SAMPLE"
$packageGrants | Format-Table -AutoSize

# Example 6: Get index grants
Write-LogMessage "Example 6: Getting all index grants" -Level INFO
$indexGrants = Get-Db2IndexGrants -DatabaseName "SAMPLE"
$indexGrants | Format-Table -AutoSize

# Example 7: Get comprehensive grant report (all types)
Write-LogMessage "Example 7: Getting comprehensive grant report" -Level INFO
$allGrants = Get-Db2AllGrants -DatabaseName "SAMPLE"
Write-LogMessage "Total Table Grants: $($allGrants.TableGrants.Count)" -Level INFO
Write-LogMessage "Total Routine Grants: $($allGrants.RoutineGrants.Count)" -Level INFO
Write-LogMessage "Total Schema Grants: $($allGrants.SchemaGrants.Count)" -Level INFO
Write-LogMessage "Total Package Grants: $($allGrants.PackageGrants.Count)" -Level INFO
Write-LogMessage "Total Index Grants: $($allGrants.IndexGrants.Count)" -Level INFO

# Example 8: Export grants to CSV files
Write-LogMessage "Example 8: Exporting grants to CSV files" -Level INFO
$tableGrants | Export-Csv -Path "TableGrants.csv" -NoTypeInformation
$routineGrants | Export-Csv -Path "RoutineGrants.csv" -NoTypeInformation
$schemaGrants | Export-Csv -Path "SchemaGrants.csv" -NoTypeInformation
$packageGrants | Export-Csv -Path "PackageGrants.csv" -NoTypeInformation
$indexGrants | Export-Csv -Path "IndexGrants.csv" -NoTypeInformation

Write-LogMessage "Grant analysis complete. CSV files created in current directory." -Level INFO

