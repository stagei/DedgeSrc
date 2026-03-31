

param(
    [Parameter(Mandatory)][string]$sqlFile)
$result = node.exe C:\Users\fkgeista\AppData\Roaming\npm\node_modules\sql-formatter\bin\sql-formatter-cli.cjs -l db2 $sqlFile
return $result

