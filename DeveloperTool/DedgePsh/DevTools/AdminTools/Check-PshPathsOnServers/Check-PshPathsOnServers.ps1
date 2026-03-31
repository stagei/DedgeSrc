Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force
Import-Module Infrastructure -Force
Import-Module Deploy-Handler -Force
$computerNameList = Get-ComputerNameList -ComputerNameList @("*")

foreach ($computerName in $computerNameList) {
    $testPath = "\\$computerName\opt\DedgePshApps\CommonModules"
    Write-Host "Checking path $testPath"
    if (-not (Test-Path $testPath)) {
        Write-Host "Path $testPath not found" -ForegroundColor Green
    }
    else {
        Write-Host "Path $testPath found" -ForegroundColor Red
        Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

