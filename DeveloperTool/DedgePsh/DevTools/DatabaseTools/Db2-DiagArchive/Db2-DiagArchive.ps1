Import-Module -Name GlobalFunctions -Force
Import-Module -Name Db2-Handler -Force

###################################################################################
# Main
###################################################################################
try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    Test-Db2ServerAndAdmin
    $smsNumbers = @("+4797188358")
    $workFolder = Get-ApplicationDataPath
    $diagFilesFound = Get-ChildItem -Path "C:\ProgramData\IBM\DB2\DB2COPY1" -Filter "db2diag.log" -Recurse -ErrorAction SilentlyContinue
    foreach ($diagFile in $diagFilesFound) {
        try {
        $splitPath = $diagFile.FullName.ToUpper().Replace("DB2DIAG.LOG", "").Split("\")
        # find the last element in the array that contains "DB2", and fall back to the first element if no "DB2" is found
        $instanceFolder = $splitPath | Where-Object { $_ -like "DB2*" } | Select-Object -Last 1
        if ($null -eq $instanceFolder) {
            $instanceFolder = "DB2"
        }
        $destinationFileName = "$($instanceFolder)_Diag_$(Get-Date -Format 'yyyyMMddHHmmssfff').log"
        $destinationFilePath = Join-Path $workFolder $destinationFileName
        # Move the diag file to the work folder
        Move-Item -Path $diagFile.FullName -Destination $destinationFilePath -Force
        Write-LogMessage "Moved diag file $($diagFile.FullName) to $($workFolder) and renamed to $($destinationFileName)" -Level INFO
        }
        catch {
            Write-LogMessage "Db2 Server: $($env:COMPUTERNAME)`nFailed to move diag file $($diagFile.FullName) to $($workFolder) and rename it to $($destinationFileName)`nError: $($_.Exception.Message)" -Level ERROR -Exception $_
            foreach ($smsNumber in $smsNumbers) {
                Send-Sms -Receiver $smsNumber -Message "Db2 Server: $($env:COMPUTERNAME)`nFailed to move diag file $($diagFile.FullName) to $($workFolder) and rename it to $($destinationFileName)`nError: $($_.Exception.Message)"
            }
        }
    }
    # Remove the old diag files in WorkFolder older than 30 days
    $oldDiagFiles = Get-ChildItem -Path $workFolder -Filter "*.log" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
    foreach ($oldDiagFile in $oldDiagFiles) {
        Remove-Item -Path $oldDiagFile.FullName -Force
        Write-LogMessage "Removed old diag file $($oldDiagFile.FullName)" -Level INFO
    }
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    throw $_
}

