param(
    [Parameter(Mandatory = $false)]
    [string]$DatabaseName,

    [Parameter(Mandatory = $false)]
    [string]$FilePath,

    [Parameter(Mandatory = $false)]
    [bool]$UseNewConfigurations = $false,

    [Parameter(Mandatory = $false)]
    [string[]]$SmsNumbers = @()
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

try {
    Write-LogMessage "$(Split-Path -Path $MyInvocation.MyCommand.Path -Leaf)" -Level JOB_STARTED

    if ([string]::IsNullOrEmpty($DatabaseName) -and [string]::IsNullOrEmpty($FilePath)) {
        Write-LogMessage "Either -DatabaseName or -FilePath must be specified" -Level ERROR
        Write-Host "Usage:"
        Write-Host "  Import-Db2GrantsLauncher.ps1 -DatabaseName XFKMTST"
        Write-Host "  Import-Db2GrantsLauncher.ps1 -FilePath 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Commonlogging\Db2\Server\Grants\FKMTST_20260313-150000.json'"
        exit 1
    }

    $appDataPath = Get-ApplicationDataPath
    Set-OverrideAppDataFolder -Path $appDataPath

    $importParams = @{}
    if (-not [string]::IsNullOrEmpty($DatabaseName)) { $importParams.DatabaseName = $DatabaseName }
    if (-not [string]::IsNullOrEmpty($FilePath)) { $importParams.FilePath = $FilePath }

    if ($UseNewConfigurations -eq $true) {
        Write-LogMessage "UseNewConfigurations: Converting to role-based grants" -Level INFO
        $result = Import-Db2GrantsAsRoles @importParams
        $message = "Role-based grant import to $($result.DatabaseName) on $($env:COMPUTERNAME): $($result.RolesCreated) roles, $($result.GrantsToRoles) grants to roles, $($result.Memberships) memberships, $($result.RevokesIssued) revokes from $($result.SourceFile)"

        Write-LogMessage "Creating DBQA validation views in schema TV for $($result.DatabaseName)" -Level INFO
        try {
            $dbName = $result.DatabaseName
            New-DbqaPrivilegeViews -DatabaseName $dbName
            Write-LogMessage "DBQA views created: TV.V_DBQA_ALL_PRIVS, TV.V_DBQA_ROLE_MEMBERS on $($dbName)" -Level INFO

            $summary = Get-ExecuteSqlStatementServerSide -DatabaseName $dbName -SqlStatement "SELECT OBJ_TYPE, COUNT(*) AS CNT FROM TV.V_DBQA_ALL_PRIVS GROUP BY OBJ_TYPE ORDER BY OBJ_TYPE"
            $totalRows = ($summary | Measure-Object -Property CNT -Sum).Sum
            $summaryText = ($summary | ForEach-Object { "$($_.OBJ_TYPE): $($_.CNT)" }) -join ", "
            Write-LogMessage "V_DBQA_ALL_PRIVS summary ($($totalRows) rows): $($summaryText)" -Level INFO
        }
        catch {
            Write-LogMessage "DBQA view creation failed (non-fatal): $($_.Exception.Message)" -Level WARN
        }
    }
    else {
        $result = Import-Db2Grants @importParams
        $message = "Grant import to $($result.DatabaseName) on $($env:COMPUTERNAME): $($result.GrantCount) grants applied from $($result.SourceFile)"
    }
    Write-LogMessage $message -Level INFO

    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message $message
    }

    Write-LogMessage "$(Split-Path -Path $PSScriptRoot -Leaf)" -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error during grant import: $($_.Exception.Message)" -Level ERROR -Exception $_
    foreach ($smsNumber in $SmsNumbers) {
        Send-Sms -Receiver $smsNumber -Message "Grant import FAILED on $($env:COMPUTERNAME): $($_.Exception.Message)"
    }
    Write-LogMessage "$(Split-Path -Path $PSScriptRoot -Leaf)" -Level JOB_FAILED -Exception $_
    exit 1
}
finally {
    Reset-OverrideAppDataFolder
}
