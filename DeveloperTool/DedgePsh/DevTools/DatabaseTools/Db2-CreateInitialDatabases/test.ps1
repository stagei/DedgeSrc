Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force
Import-Module Infrastructure -Force
Import-Module NetSecurity -Force

$object = [PSCustomObject]@{
    ControlDataAgeSqlStatement  = $(Get-ControlDataAgeSqlStatement -Application "FKM")
    ControlSqlStatement  = $(Get-ControlSqlStatement -Application "FKM")

}
$db2Commands = @()
$db2Commands += "db2 connect to basisrap"
$db2Commands += "$($object.ControlDataAgeSqlStatement)"
$db2Commands += "db2 connect reset"
$db2Commands += ""
$output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors
Write-Output $output
# Extract date using regex pattern matching
$datePattern = '\d{2}\.\d{2}\.\d{4}'
$dateMatch = [regex]::Match($output, $datePattern)

if ($dateMatch.Success) {
    $extractedDate = $dateMatch.Value
    Write-LogMessage "Found date in output: $extractedDate" -Level INFO
} else {
    Write-LogMessage "No date found in output" -Level WARN
}

$db2Commands = @()
$db2Commands += "db2 connect to basisrap"
$db2Commands += "$($object.ControlSqlStatement)"
$db2Commands += "db2 connect reset"
$db2Commands += ""
$output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors
Write-Output $output
# Extract rowcount eg. "  10 post(er) er valgt." using regex pattern matching
$rowCountPattern = '(\d{2})\s+post\((\w+)\)\s+er\s+valgt\.' #  10 post(er) er valgt.
$rowCountMatch = [regex]::Match($output, $rowCountPattern)

if ($rowCountMatch.Success) {
    $extractedRowCount = [int] $rowCountMatch.Groups[1].Value
    Write-LogMessage "Found rowcount in output: $extractedRowCount" -Level INFO
} else {
    Write-LogMessage "No rowcount found in output" -Level WARN
}

