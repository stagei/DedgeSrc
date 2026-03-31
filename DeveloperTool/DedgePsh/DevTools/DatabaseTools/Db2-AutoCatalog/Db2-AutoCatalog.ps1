Import-Module Db2-Handler -Force
Import-Module GlobalFunctions -Force
try {
    Write-LogMessage "Starting Db2 auto catalog" -Level JOB_STARTED
    $catalogScript = Join-Path $(Get-SoftwarePath) "\Config\Db2\ClientConfig\Catalog-Script-For-All-Cobol-Applications-For-All-Environments.bat"
    $null = Invoke-DB2ScriptCommand -ScriptFile $catalogScript -IgnoreErrors -OutputToConsole
    Add-Content -Path "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Client\$($env:COMPUTERNAME)-Client-Config-$(Get-Date -Format 'yyyy-MM-dd').log" -Value "$env:COMPUTERNAME, $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), Success" -ErrorAction SilentlyContinue
    Write-LogMessage "Db2 auto catalog completed" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error starting Db2 auto catalog: $($_.Exception.Message)" -Level ERROR
    Write-LogMessage "Db2 auto catalog failed" -Level JOB_FAILED
}

