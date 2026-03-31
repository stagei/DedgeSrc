param (
    [Parameter(Mandatory = $false)]
    [string]$InstanceName = "*",
    [Parameter(Mandatory = $false)]
    [ValidateSet("PrimaryDb", "FederatedDb", "BothDatabases")]
    [string]$DatabaseType = "BothDatabases",
    [Parameter(Mandatory = $false)]
    [switch] $Offline,
    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @("+4797188358"),
    [Parameter(Mandatory = $false)]
    [string]$OverrideWorkFolder = ""
)

# Import required modules
Import-Module -Name GlobalFunctions -Force
Import-Module -Name Db2-Handler -Force

Import-Module -Name Infrastructure -Force

###################################################################################
# Main
###################################################################################

try {
    Write-LogMessage "$(Get-InitScriptName)" -Level JOB_STARTED
    # Check if script is running on a server
    if (-not (Test-IsDb2Server -Quiet $true)) {
        throw "This script must be run on a server with Db2 Server installed"
    }
    $backupType = if ($Offline) { "Offline" } else { "Online" }

    # Start backup for federated database
    if ($InstanceName -eq "*") {
        # Get day of week
        $instanceNames = Get-Db2InstanceNames
        $dayOfWeek = Get-Date -Format "dddd"
        if ($dayOfWeek -eq "Friday") {
            $instanceNames = $instanceNames | Where-Object { $_ -ne "DB2HST" -and $_ -ne "DB2HFED" }
        }

        foreach ($instanceName in $instanceNames) {
            Start-Db2Backup -InstanceName $instanceName -BackupType $backupType -DatabaseType $DatabaseType -SmsNumbers $SmsNumbers -OverrideWorkFolder $OverrideWorkFolder
        }
    }
    else {
        Start-Db2Backup -InstanceName $InstanceName -BackupType $backupType -DatabaseType $DatabaseType -SmsNumbers $SmsNumbers -OverrideWorkFolder $OverrideWorkFolder
    }
    Write-LogMessage "$(Get-InitScriptName)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_.Exception
    Write-LogMessage "$(Get-InitScriptName)" -Level JOB_FAILED
    Exit 9
}

