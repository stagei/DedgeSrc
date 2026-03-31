param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Console", "Web", "Csv", "Json")]
    [string]$OutputMethod = "Console",
    [Parameter(Mandatory = $false)]
    [string]$CombinedString = "select * from inl.KONTOTYPE",
    [Parameter(Mandatory = $false)]
    [string]$OutputFileName = ""
)

$CombinedString = $CombinedString.Trim()
$posSelect = $CombinedString.ToLower().IndexOf("select")

$SelectStatement = $CombinedString.Substring($posSelect).Trim()
$DatabaseName = $CombinedString.Substring(0, $posSelect).Trim()

Import-Module OdbcHandler -Force
Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force
Import-Module Export-Array -Force
Import-Module Db2-Handler -Force
$DatabaseName = $env:CURRENT_DATABASE
if ([string]::IsNullOrEmpty($DatabaseName)) {
    $DatabaseName = Read-Host "Enter the database name"
}

Write-LogMessage "Current database name: $currentDatabaseName" -Level INFO
$instanceName = $env:DB2INSTANCE
$databaseType = $(Get-DatabaseTypeFromInstanceName -InstanceName $instanceName)
if (-not [string]::IsNullOrEmpty($DatabaseName)) {
    $workObject = Get-DefaultWorkObjectsCommon -DatabaseName $DatabaseName -DatabaseType $DatabaseType -QuickMode
    if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }
}
else {
    $workObject = Get-DefaultWorkObjectsCommon -DatabaseType $databaseType -InstanceName $instanceName -QuickMode
    if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }
}

$workObject = Add-OdbcCatalogEntry -WorkObject $workObject -Quiet
if ($workObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $workObject = $workObject[-1] }

# $WorkObject = [PSCustomObject]@{
#     DatabaseName       = $DatabaseName
#     ComputerName       = $ComputerName
#     OdbcConnectionName = $odbcConnectionName
#     SelectStatement    = $SelectStatement
#     Result             = $result
# }

$odbcConnectionName = $workObject.RemoteAccessPoint.CatalogName

try {
    $result = ExecuteQuery -sqlStatement $SelectStatement -odbcConnectionName $odbcConnectionName
}
catch {
    Write-LogMessage "Error executing query: $SelectStatement" -Level Error -Exception $_
    return
}
$result = $result | Select-Object -Skip 1
$currentDateTime = Get-Date -Format "yyyyMMddHHmmss"

if ($OutputFileName -ne "" -and (-not ($OutputFileName -match "^[c-zC-Z]:\\" -or $OutputFileName.StartsWith("\\")))) {
    $OutputFileName = "C:\TEMPFK\$OutputFileName"
}
elseif ($OutputFileName -eq "") {
    if ($OutputMethod -eq "Json") {
        $OutputFileName = "C:\TEMPFK\db2sel_$currentDateTime.json"
    }
    elseif ($OutputMethod -eq "Csv") {
        $OutputFileName = "C:\TEMPFK\db2sel_$currentDateTime.csv"
    }
    elseif ($OutputMethod -eq "Console") {
        $OutputFileName = "C:\TEMPFK\db2sel_$currentDateTime.txt"
    }
    elseif ($OutputMethod -eq "Web") {
        $OutputFileName = "C:\TEMPFK\db2sel_$currentDateTime.html"
    }
}
else {
    if ($OutputFileName.EndsWith(".csv") -or $OutputFileName.EndsWith(".json") -or $OutputFileName.EndsWith(".html") -or $OutputFileName.EndsWith(".txt")) {
        $OutputFileName = "C:\TEMPFK\$OutputFileName"
    }
    else {
        if ($OutputMethod -eq "Web") {
            $OutputFileName = "C:\TEMPFK\$OutputFileName.$currentDateTime.html"
        }
        elseif ($OutputMethod -eq "Csv") {
            $OutputFileName = "C:\TEMPFK\$OutputFileName.$currentDateTime.csv"
        }
        elseif ($OutputMethod -eq "Json") {
            $OutputFileName = "C:\TEMPFK\$OutputFileName.$currentDateTime.json"
        }
        else {
            $OutputFileName = "C:\TEMPFK\$OutputFileName.$currentDateTime.txt"
        }
    }
}

if (Test-Path $OutputFileName) {
    Remove-Item $OutputFileName -Force | Out-Null
}
if ($result.Count -eq 0) {
    Write-LogMessage "No results found" -Level WARN
    return
}

if ($OutputMethod -eq "Web") {
    Export-ArrayToHtmlFile -Content $result -Title "DB2 Query Results - $($odbcConnectionName.ToUpper() + " - " + $SelectStatement)" -OutputPath $OutputFileName -AutoOpen $true -AddToDevToolsWebPath $false
}
elseif ($OutputMethod -eq "Csv") {
    Export-ArrayToCsvFile -Content $result -OutputPath $OutputFileName
}
elseif ($OutputMethod -eq "Json") {
    Export-ArrayToJsonFile -Content $result -OutputPath $OutputFileName
}
else {
    if ($result.Count -gt 1) {
        $result | Format-Table -Property * -AutoSize
    }
    else {
        $result | Format-List -Property *
    }
}

Write-LogMessage "DB2 Query executed towards $DatabaseName on $ComputerName successfully: `n$SelectStatement" -Level Info
Write-LogMessage "Selected $($result.Count) rows" -Level INFO -ForegroundColor Green
Write-LogMessage "Output file: $OutputFileName" -Level INFO -ForegroundColor Green

