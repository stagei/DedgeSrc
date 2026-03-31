param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("PrimaryDb", "FederatedDb", "BothDatabases")]
    [string]$DatabaseName = "BASISVFT"
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force
Import-Module Infrastructure -Force
Import-Module NetSecurity -Force

########################################################################################################
# Main
########################################################################################################
try {
    Write-LogMessage "$(Split-Path -Path $MyInvocation.MyCommand.Path -Leaf)" -Level JOB_STARTED
    $settings = Get-GlobalEnvironmentSettings -OverrideDatabase $DatabaseName
    if ($settings.IsServer) {
        throw "This script must be run on a workstation"
    }
    $WorkObject = [PSCustomObject]@{
        DatabaseName = $DatabaseName
        Application  = $settings.Application
        InstanceName = "DB2"
    }

    $WorkObject = Get-ControlSqlStatement -WorkObject $WorkObject -RowCount 3
    if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }

    if ([string]::IsNullOrEmpty($WorkObject.ControlSqlStatement)) {
        Write-LogMessage "No control sql statement found for $($DatabaseName)" -Level WARN
        return
    }
    $numberOfHours = 0
    $numberOfHours = Get-UserConfirmationWithTimeout -PromptMessage "How many hours do you want to run the connectivity test" -TimeoutSeconds 30 -DefaultResponse "0. Infinite" -AllowedResponses @("0. Infinite", "1 Hour", "2 Hours", "3 Hours", "4 Hours", "5 Hours", "6 Hours", "7 Hours", "8 Hours", "9 Hours") -ProgressMessage "Select number of hours" -AddNumberToAllowedResponses $false
    $numberOfHours = $numberOfHours.Split(" ")[0].Trim()
    $numberOfHours = $numberOfHours -as [double]
    if ($numberOfHours -gt 0) {
        $duration = [TimeSpan]::FromHours($numberOfHours)
        Write-LogMessage "Test will run for: $($duration.ToString('hh\:mm\:ss'))" -Level INFO
    }
    else {
        Write-LogMessage "Test will run indefinitely" -Level INFO
    }

    $db2Commands = @()
    $db2Commands += "db2 connect to $($DatabaseName)"
    $db2Commands += $WorkObject.ControlSqlStatement
    $db2Commands += "db2 connect reset"
    $startTime = Get-Date
    Write-LogMessage "Db2 Commands: $($db2Commands -join "`n")" -Level INFO

    $continue = $true
    $totalIterations = 0
    $successCounter = 0
    $failedCounter = 0

    $remainingDuration = $duration
    $endTime = $startTime + $duration
    while ($continue) {
        $totalIterations++
        Write-LogMessage "Executing SQL script to verify connectivity to $($DatabaseName):`n $($db2Commands -join "`n")" -Level INFO
        try {
            $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT
            Write-LogMessage "Result: $(Get-SelectResult -SelectOutput $output)" -Level INFO -ForegroundColor White
            $successCounter++
        }
        catch {
            Write-LogMessage "Connectivity test failed to $($DatabaseName)" -Level WARN -ForegroundColor Yellow
            $failedCounter++
        }

        if ($numberOfHours -gt 0) {
            $currentTime = Get-Date
            $duration = $currentTime - $startTime
            $remainingDuration = $endTime - $currentTime
            if ($remainingDuration.TotalSeconds -le 0) {
                $continue = $false
            }
            $statusObj = [PSCustomObject]@{
                'Remaining Duration' = $remainingDuration.ToString('hh\:mm\:ss')
                'Success Count'      = $successCounter
                'Failed Count'       = $failedCounter
                'Total Repetitions'  = $totalIterations
            }
            Write-LogMessage ($statusObj | Format-List | Out-String) -Level INFO
        }
        $continue = Get-UserConfirmationWithTimeout -PromptMessage "Do you want to continue repeating the connectivity test to $($DatabaseName)?" -TimeoutSeconds 5 -DefaultResponse "Y" -AllowedResponses @("Y", "N")
        if ($continue -ne "Y") {
            $continue = $false
        }
    }
    Write-LogMessage "$(Split-Path -Path $MyInvocation.MyCommand.Path -Leaf)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_.Exception
    Write-LogMessage "$(Split-Path -Path $MyInvocation.MyCommand.Path -Leaf)" -Level JOB_FAILED
    Exit 9
}

