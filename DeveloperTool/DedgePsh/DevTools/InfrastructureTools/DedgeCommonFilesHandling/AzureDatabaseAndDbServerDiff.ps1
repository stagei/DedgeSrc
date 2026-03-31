Import-Module GlobalFunctions -Force
$ConfigFilesPath = Get-ConfigFilesPath
$jsonContent = Get-Content "$ConfigFilesPath\ComputerInfo.json" | ConvertFrom-Json
$myArray = $jsonContent | Where-Object {
    $_.Name -match "t-no1([a-z]{3}|[a-z]{6})-db([0-9]{2})?" -or
    $_.Name -match "p-no1([a-z]{3}|[a-z]{6})-db([0-9]{2})?"
}

$listOfServers = $myArray | Select-Object -ExpandProperty Name

$jsonContent2 = Get-Content "$ConfigFilesPath\Databases.json" | ConvertFrom-Json
$myArray2 = $jsonContent2 | Where-Object {
    $_.ConnectionInfo.Server -match "t-no1([a-z]{3}|[a-z]{6})-db([0-9]{2})?" -or
    $_.ConnectionInfo.Server -match "p-no1([a-z]{3}|[a-z]{6})-db([0-9]{2})?"
}

$listOfDatabasesOnServers = $myArray2 | Select-Object -ExpandProperty ConnectionInfo | Select-Object -ExpandProperty Server
# Compare the two lists and find differences
$diff = Compare-Object -ReferenceObject $listOfServers -DifferenceObject $listOfDatabasesOnServers

# Output the differences
if ($diff) {
    Write-Output "Servers in ComputerInfo.json but not referenced in Databases.json:"
    $diff | Where-Object {$_.SideIndicator -eq '<='} | Select-Object -ExpandProperty InputObject

    Write-Output "`nServers referenced in Databases.json but not defined in ComputerInfo.json:"
    $diff | Where-Object {$_.SideIndicator -eq '=>'} | Select-Object -ExpandProperty InputObject
} else {
    Write-Output "No differences found - server lists match"
}

