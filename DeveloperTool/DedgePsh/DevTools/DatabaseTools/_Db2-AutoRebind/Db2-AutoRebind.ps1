# --------------------------------------------------------------------------------
# Db2-AutoRebind.ps1 - Automatically rebind invalid DB2 packages
# --------------------------------------------------------------------------------
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$DatabaseName = "BASISTST"
)
Import-Module -Name GlobalFunctions -Force
Import-Module -Name Db2-Handler -Force

Write-Host "Starting DB2 Auto Rebind for database: $DatabaseName" -ForegroundColor Green

try {
    # Find db2cmd.exe
    $db2cmdPath = Get-CommandPathWithFallback "db2cmd"
    Write-Host "Found DB2 Command Path: $db2cmdPath" -ForegroundColor Yellow

    # Create temporary batch file for DB2 commands
    # $tempBatchFile = [System.IO.Path]::GetTempFileName() + ".cmd"
    # $tempResultFile = [System.IO.Path]::GetTempFileName() + ".txt"
    $tempBatchFile = $PSScriptRoot + "\temp_rebind.bat"
    $tempSqlFile = $PSScriptRoot + "\temp_rebind.sql"
    $tempResultFile = $PSScriptRoot + "\temp_rebind.txt"
    Remove-Item $tempBatchFile -ErrorAction SilentlyContinue
    Remove-Item $tempSqlFile -ErrorAction SilentlyContinue
    Remove-Item $tempResultFile -ErrorAction SilentlyContinue

    Write-Host "Getting list of invalid packages..." -ForegroundColor Yellow
    $temp = @"
select rtrim(pkgschema) || '.' || rtrim(pkgname) from syscat.packages where valid = 'N'
"@
    $temp | Out-File -FilePath $tempSqlFile -Encoding ASCII
    # Create batch file to get invalid packages
    $getBatchContent = @"
@echo off
db2 connect to $DatabaseName
db2 -x -v -f $tempSqlFile > $tempResultFile
db2 connect reset
exit /b
"@
    $getBatchContent | Out-File -FilePath $tempBatchFile -Encoding ASCII

    # Execute and capture output
    $command = "$db2cmdPath `"$tempBatchFile`""
    Write-Host "Executing command: $command" -ForegroundColor Yellow
    & cmd.exe /c $command
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c $command" -Wait

    $result = Get-Content $tempResultFile
    # Parse invalid packages from output
    $invalidPackages = @()
    # $connectSuccess = $false
    $result = Test-OutputForErrors -Output $getBatchContent
    # foreach ($line in $result) {
    #     $line = $line.ToString().Trim()
    #     if ($line -match "Database Connection Information") {
    #         $connectSuccess = $true
    #     }
    #     elseif ($connectSuccess -and $line -match "^[A-Z0-9_]+\.[A-Z0-9_]+$") {
    #         $invalidPackages += $line
    #     }
    # }

    if (-not $result) {
        Write-Error "Failed to connect to database $DatabaseName"
        Write-Host "DB2 Output:" -ForegroundColor Red
        $result | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        return
    }

    if ($invalidPackages.Count -eq 0) {
        Write-Host "No invalid packages found. All packages are valid!" -ForegroundColor Green
        return
    }

    Write-Host "Found $($invalidPackages.Count) invalid packages:" -ForegroundColor Yellow
    $invalidPackages | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }

    # Create rebind batch file
    Write-Host "`nCreating rebind commands..." -ForegroundColor Yellow

    $rebindBatchContent = @"
@echo off
echo Connecting to database $DatabaseName...
db2 connect to $DatabaseName
if %errorlevel% neq 0 (
    echo Failed to connect to database
    exit /b 1
)

"@

    foreach ($package in $invalidPackages) {
        $rebindBatchContent += @"
echo Rebinding package: $package
db2 rebind package $package
if %errorlevel% neq 0 (
    echo Warning: Failed to rebind package $package
) else (
    echo Successfully rebound package $package
)

"@
    }

    $rebindBatchContent += @"
echo Disconnecting from database...
db2 connect reset
echo Rebind process completed.
"@

    $rebindBatchContent | Out-File -FilePath $tempBatchFile -Encoding ASCII

    # Execute rebind commands
    Write-Host "Executing rebind commands..." -ForegroundColor Yellow
    Write-Host "----------------------------------------" -ForegroundColor Cyan

    $rebindResult = & cmd.exe /c "`"$tempBatchFile`""
    $rebindResult | ForEach-Object { Write-Host $_ }

    Write-Host "----------------------------------------" -ForegroundColor Cyan

    # Verify results
    Write-Host "`nVerifying rebind results..." -ForegroundColor Yellow

    $verifyBatchContent = @"
@echo off
db2 connect to $DatabaseName
db2 -x "select count(*) from syscat.packages where invalid = 'Y'"
db2 connect reset
"@

    $verifyBatchContent | Out-File -FilePath $tempBatchFile -Encoding ASCII
    $verifyResult = & cmd.exe /c "`"$tempBatchFile`""

    $remainingInvalid = 0
    foreach ($line in $verifyResult) {
        if ($line -match "^\s*(\d+)\s*$") {
            $remainingInvalid = [int]$matches[1]
            break
        }
    }

    if ($remainingInvalid -eq 0) {
        Write-Host "SUCCESS: All packages have been successfully rebound!" -ForegroundColor Green
    }
    else {
        Write-Host "WARNING: $remainingInvalid invalid packages still remain." -ForegroundColor Yellow
        Write-Host "You may need to investigate these packages manually." -ForegroundColor Yellow
    }

}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
}
finally {
    # Clean up temporary files
    if (Test-Path $tempBatchFile) {
        Remove-Item $tempBatchFile -ErrorAction SilentlyContinue
    }
    if (Test-Path $tempResultFile) {
        Remove-Item $tempResultFile -ErrorAction SilentlyContinue
    }
}

Write-Host "`nDB2 Auto Rebind completed!" -ForegroundColor Green

