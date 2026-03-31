<#
.SYNOPSIS
    Automatically creates network shares for DB2 diagnostic log folders on DB2 servers.

.DESCRIPTION
    This script discovers DB2 instance folders in the ProgramData\IBM\DB2 directory,
    sets up folder permissions using Infrastructure module, and creates SMB shares
    with the naming convention DiagFiles<InstanceName>.
    
    Shares are configured with full access for the following domain groups:
    - DEDGE\ACL_ERPUTV_Utvikling_Full
    - DEDGE\ACL_Dedge_Servere_Utviklere
    
    The script must be run on a DB2 server with administrator privileges.

.PARAMETER Force
    When specified, recreates shares even if they already exist with the same configuration.

.EXAMPLE
    .\Db2-DiagInstanceFolderShare.ps1
    # Discovers DB2 instances and creates shares for each diag folder

.EXAMPLE
    .\Db2-DiagInstanceFolderShare.ps1 -Force
    # Recreates all shares even if they exist

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Requires: Administrator privileges, DB2 server environment
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force

<#
    Function: Get-Db2ProgramDataPath
    Gets the DB2 installation path from db2set DB2INSTPROF command and extracts
    the path up to and including the first "DB2" folder.
    
    Example:
    - Command output: C:\PROGRAMDATA\IBM\DB2\DB2COPY1
    - Extracted path: C:\PROGRAMDATA\IBM\DB2
    
    Returns: String path to DB2 folder, or $null if command fails or path not found
#>
function Get-Db2ProgramDataPath {
    try {
        # Call db2set DB2INSTPROF and capture output
        $db2Output = & db2set DB2INSTPROF 2>&1 | Out-String
        
        if ([string]::IsNullOrWhiteSpace($db2Output)) {
            Write-LogMessage "db2set DB2INSTPROF returned no output" -Level WARN
            return $null
        }
        
        # Trim whitespace and newlines
        $db2ProgramDataPath = $db2Output.Trim()
        
        # Find the first occurrence of "DB2" folder in the path
        # Regex pattern explanation:
        # ^          - Start of string
        # (.+?)      - Capture group: match any characters (non-greedy) - captures everything up to DB2
        # \\DB2      - Literal backslash followed by "DB2" (included in capture group)
        # (?:\\|$)   - Non-capturing group: match either a backslash or end of string (not captured)
        # Example: C:\PROGRAMDATA\IBM\DB2\DB2COPY1 → captures "C:\PROGRAMDATA\IBM\DB2"
        if ($db2ProgramDataPath -match '^(.+?\\DB2)(?:\\|$)') {
            $extractedPath = $matches[1]
            Write-LogMessage "DB2 installation path extracted: $($extractedPath)" -Level INFO
            return $extractedPath
        }
        else {
            Write-LogMessage "Could not find DB2 folder in path: $($db2ProgramDataPath)" -Level WARN
            return $null
        }
    }
    catch {
        Write-LogMessage "Failed to execute db2set command: $($_.Exception.Message)" -Level WARN
        return $null
    }
}

<#
    Function: Get-Db2InstanceFromPath
    Determines the DB2 instance name from the file path.
    Known instances: DB2FED, DB2HFED, DB2HST, DB2DBQA, DB2DOC, DB2 (default)
#>
function Get-Db2InstanceFromPath {
    param([string]$FilePath)
    
    $upperPath = $FilePath.ToUpper()
    
    if ($upperPath.Contains("DB2HFED")) { return "DB2HFED" }
    elseif ($upperPath.Contains("DB2FED")) { return "DB2FED" }
    elseif ($upperPath.Contains("DB2HST")) { return "DB2HST" }
    elseif ($upperPath.Contains("DB2DBQA")) { return "DB2DBQA" }
    elseif ($upperPath.Contains("DB2DOC")) { return "DB2DOC" }
    else { return "DB2" }
}

<#
    Function: Get-DiagFolderFromLogPath
    Extracts the diag folder path from a db2diag.log file path.
    The diag folder is the parent directory containing the db2diag.log file.
    
    Example:
    - Input: C:\ProgramData\IBM\DB2\DB2COPY1\DB2FED\db2diag.log
    - Output: C:\ProgramData\IBM\DB2\DB2COPY1\DB2FED
#>
function Get-DiagFolderFromLogPath {
    param([string]$LogFilePath)
    
    return Split-Path -Path $LogFilePath -Parent
}

########################################################################################################
# Main
########################################################################################################
try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    
    # Check if script is running on a DB2 server
    if (-not (Test-IsDb2Server)) {
        Write-LogMessage "This script must be run on a DB2 server (C:\DbInst folder not found)" -Level ERROR
        throw "Not a DB2 server - C:\DbInst folder does not exist"
    }
    
    # Check if running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-LogMessage "This script must be run as Administrator" -Level ERROR
        throw "Administrator privileges required"
    }
    
    Write-LogMessage "Running on DB2 server: $($env:COMPUTERNAME)" -Level INFO
    
    # Get DB2 ProgramData path
    $db2ProgramDataPath = Get-Db2ProgramDataPath
    
    if ([string]::IsNullOrWhiteSpace($db2ProgramDataPath) -or -not (Test-Path $db2ProgramDataPath)) {
        Write-LogMessage "Could not determine DB2 ProgramData path" -Level ERROR
        throw "DB2 ProgramData path not found"
    }
    
    Write-LogMessage "Searching for db2diag.log files in: $($db2ProgramDataPath)" -Level INFO
    
    # Find all db2diag.log files to discover instance folders
    $diagLogFiles = Get-ChildItem -Path $db2ProgramDataPath -Filter "db2diag.log" -Recurse -ErrorAction SilentlyContinue
    
    if ($null -eq $diagLogFiles -or @($diagLogFiles).Count -eq 0) {
        Write-LogMessage "No db2diag.log files found in: $($db2ProgramDataPath)" -Level WARN
        Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
        return [PSCustomObject]@{
            SearchDirectory = $db2ProgramDataPath
            InstancesFound  = 0
            SharesCreated   = 0
            Message         = "No db2diag.log files found"
        }
    }
    
    Write-LogMessage "Found $(@($diagLogFiles).Count) db2diag.log file(s)" -Level INFO
    
    # Define the groups to share with
    $shareGroups = @(
        "DEDGE\ACL_ERPUTV_Utvikling_Full",
        "DEDGE\ACL_Dedge_Servere_Utviklere"
    )
    
    # Track processed instances to avoid duplicates
    $processedInstances = @{}
    $results = @()
    
    foreach ($diagFile in $diagLogFiles) {
        $instanceName = Get-Db2InstanceFromPath -FilePath $diagFile.DirectoryName
        $diagFolder = Get-DiagFolderFromLogPath -LogFilePath $diagFile.FullName
        
        # Skip if we've already processed this instance
        if ($processedInstances.ContainsKey($instanceName)) {
            Write-LogMessage "Instance $($instanceName) already processed, skipping duplicate at: $($diagFolder)" -Level DEBUG
            continue
        }
        
        $processedInstances[$instanceName] = $diagFolder
        $shareName = "DiagFiles$($instanceName)"
        
        Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
        Write-LogMessage "Processing instance: $($instanceName)" -Level INFO
        Write-LogMessage "Diag folder: $($diagFolder)" -Level INFO
        Write-LogMessage "Share name: $($shareName)" -Level INFO
        Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
        
        try {
            # Step 1: Set up folder permissions using Add-Folder
            Write-LogMessage "Setting up folder permissions for: $($diagFolder)" -Level INFO
            Add-Folder -Path $diagFolder -AdditionalAdmins $shareGroups -EveryonePermission "ReadAndExecute"
            Write-LogMessage "✅ Folder permissions configured successfully" -Level INFO
            
            # Step 2: Create SMB share using Add-SmbSharedFolder
            Write-LogMessage "Creating SMB share: $($shareName)" -Level INFO
            $shareResult = Add-SmbSharedFolder -Path $diagFolder `
                -ShareName $shareName `
                -Description "DB2 Diagnostic Log folder for instance $($instanceName) on $($env:COMPUTERNAME)" `
                -AdditionalAdmins $shareGroups
            
            Write-LogMessage "✅ SMB share '$($shareName)' created successfully" -Level INFO
            Write-LogMessage "   UNC Path: \\$($env:COMPUTERNAME)\$($shareName)" -Level INFO
            
            $results += [PSCustomObject]@{
                InstanceName = $instanceName
                DiagFolder   = $diagFolder
                ShareName    = $shareName
                UncPath      = "\\$($env:COMPUTERNAME)\$($shareName)"
                Status       = "Success"
                Error        = $null
            }
        }
        catch {
            Write-LogMessage "❌ Failed to create share for instance $($instanceName): $($_.Exception.Message)" -Level ERROR -Exception $_
            
            $results += [PSCustomObject]@{
                InstanceName = $instanceName
                DiagFolder   = $diagFolder
                ShareName    = $shareName
                UncPath      = $null
                Status       = "Failed"
                Error        = $_.Exception.Message
            }
        }
    }
    
    # Summary
    Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage "  Processing Complete - Summary" -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
    
    $successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
    $failedCount = ($results | Where-Object { $_.Status -eq "Failed" }).Count
    
    Write-LogMessage "Instances processed: $($processedInstances.Count)" -Level INFO
    Write-LogMessage "Shares created successfully: $($successCount)" -Level INFO
    if ($failedCount -gt 0) {
        Write-LogMessage "Shares failed: $($failedCount)" -Level WARN
    }
    
    Write-LogMessage "" -Level INFO
    Write-LogMessage "Created shares:" -Level INFO
    foreach ($result in ($results | Where-Object { $_.Status -eq "Success" })) {
        Write-LogMessage "  $($result.UncPath)" -Level INFO
    }
    
    Write-LogMessage "═══════════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
    
    # Return results
    return [PSCustomObject]@{
        ServerName      = $env:COMPUTERNAME
        SearchDirectory = $db2ProgramDataPath
        InstancesFound  = $processedInstances.Count
        SharesCreated   = $successCount
        SharesFailed    = $failedCount
        Details         = $results
        ShareGroups     = $shareGroups
    }
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    throw
}
