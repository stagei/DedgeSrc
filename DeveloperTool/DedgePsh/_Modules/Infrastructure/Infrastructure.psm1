<#
.SYNOPSIS
    Infrastructure management module for server configuration, AD integration, and environment setup.

.DESCRIPTION
    This module provides comprehensive infrastructure management capabilities including:
    - Computer and server inventory management (ComputerInfo.json)
    - Active Directory user and group management
    - Environment variable and path configuration
    - Server initialization and setup
    - Credential and security management
    - Robocopy file deployment operations
    - Service and scheduled task management
    - Network and connectivity testing

.EXAMPLE
    Get-ComputerInfoJson
    # Retrieves the list of managed computers from the configuration file

.EXAMPLE
    Initialize-Server -AdditionalAdmins @("DOMAIN\AdminUser")
    # Initializes a server with specified additional administrators

.EXAMPLE
    Set-ComputerAvailabilityStatus
    # Updates the availability status of all managed computers
#>

$modulesToImport = @("GlobalFunctions")
foreach ($moduleName in $modulesToImport) {
    if (-not (Get-Module -Name $moduleName) -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
        Import-Module $moduleName -Force
    }
} 
  
# Import-Module -Name Microsoft.PowerShell.LocalAccounts -Force

# DEDGE\ACL_ERPUTV_Utvikling_Full;DEDGE\ACL_Dedge_Servere_Utviklere

function Install-ActiveDirectoryModule {
    try {
        Import-Module -Name ActiveDirectory -ErrorAction Stop
    }
    catch {
        Write-LogMessage "Failed to import ActiveDirectory module. Attempting to install..." -Level WARN
    
        if (Test-IsServer) {
            try {
                Install-WindowsFeature -Name RSAT-AD-PowerShell -IncludeAllSubFeature
                Import-Module -Name ActiveDirectory -Force
                Write-LogMessage "Active Directory module installed and imported successfully" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to install Active Directory module on server" -Level ERROR
                throw $_
            }
        }
        else {
            try {
                Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
                Import-Module -Name ActiveDirectory -Force
                Write-LogMessage "Active Directory module installed and imported successfully" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to install Active Directory module on client" -Level ERROR
                throw $_
            }
        }
    }
}

<#
.SYNOPSIS
    Adds a new computer to the ComputerInfo.json file.

.DESCRIPTION
    Adds a new computer object to the existing list of computers in the configuration file.
    Checks for duplicates and requires confirmation unless AutoConfirm is set to true.

.PARAMETER computer
    PSCustomObject containing the computer information to add.

.PARAMETER AutoConfirm
    If true, skips the confirmation prompt. Default is false.

.EXAMPLE
    $newComputer = [PSCustomObject]@{
        Name = "SERVER01"
        Type = "Server"
        IsActive = $true
    }
    Add-ComputerInfo -computer $newComputer
    # Adds a new computer with confirmation prompt
#>
function Add-ComputerInfo {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$computer,
        [Parameter(Mandatory = $false)]
        [bool]$AutoConfirm = $false
    )
    # Check if the computer already exists
    try {
        $existingComputers = Get-ComputerInfoJson
        if ($existingComputers | Where-Object { $_.Name -eq $computer.Name }) {
            Write-LogMessage "Computer $($computer.Name) already exists in $(Get-ComputerInfoJsonFilename)" -Level INFO
            # Display the existing computer details
            $computer | Format-List | Out-String | ForEach-Object { Write-LogMessage $_ -Level INFO }
            return $false
        }

        # Ask user for confirmation and show the computer object pretty
        $computer | Format-List | Out-String | ForEach-Object { Write-LogMessage $_ -Level INFO }

        if ($AutoConfirm -eq $false) {
            $confirmation = Read-Host "Are you sure you want to add this computer? (y/n)"
        }

        if ($confirmation.ToLower() -eq "y" -or $AutoConfirm -eq $true) {
            $jsonFilePath = $(Get-ComputerInfoJsonFilename)
            $computers = Get-ComputerInfoJson
            $computers += $computer
            Set-ComputerInfoJson -computers $computers
            Write-LogMessage "Computer $($computer.Name) added to $jsonFilePath" -Level INFO
            return $true
        }
        else {
            Write-LogMessage "Computer $($computer.Name) not added to $jsonFilePath" -Level ERROR
            return $false
        }
    }
    catch {
        Write-LogMessage "Error adding computer: $($computer.Name)" -Level ERROR -Exception $_
        return $false
    }
}

<#
.SYNOPSIS
    Removes a computer from the ComputerInfo.json file.

.DESCRIPTION
    Removes a computer from the configuration file based on its name.
    Requires user confirmation before deletion.

.PARAMETER computerName
    The name of the computer to remove.

.EXAMPLE
    Remove-ComputerInfo -computerName "SERVER01"
    # Removes SERVER01 from the configuration after confirmation
#>
function Remove-ComputerInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$computerName
    )
    # Ask user for confirmation and show the computer object pretty
    $computers = Get-ComputerInfoJson
    $computer = $computers | Where-Object { $_.Name -eq $computerName }
    $computer | Format-List | Out-String | ForEach-Object { Write-LogMessage $_ -Level INFO }
    $confirmation = Read-Host "Are you sure you want to remove this computer? (y/n)"
    if ($confirmation.ToLower() -eq "y") {
        $computers = $computers | Where-Object { $_.Name -ne $computerName }
        Set-ComputerInfoJson -computers $computers
        Write-LogMessage "Computer $computerName removed from $(Get-ComputerInfoJsonFilename)" -Level INFO
    }
    else {
        Write-LogMessage "Computer $computerName not removed from $(Get-ComputerInfoJsonFilename)" -Level ERROR
    }
}
function Rename-ArrayPropertyName {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InputObject,
        
        [Parameter(Mandatory = $true)]
        [string]$OldName,
        
        [Parameter(Mandatory = $true)] 
        [string]$NewName,
        
        [Parameter(Mandatory = $false)]
        [switch]$PartialMatch
    )
    
    foreach ($obj in $InputObject) {
        # Get all properties that need to be renamed
        $propertiesToRename = $obj | Get-Member -MemberType NoteProperty | 
        Where-Object { 
            if ($PartialMatch) {
                $_.Name -like "*$OldName*"
            }
            else {
                $_.Name -eq $OldName
            }
        }
        
        # Rename each matching property
        foreach ($property in $propertiesToRename) {
            $oldPropertyName = $property.Name
            $newPropertyName = if ($PartialMatch) {
                $oldPropertyName.Replace($OldName, $NewName)
            }
            else {
                $NewName
            }
            
            # Get the value before removing the old property
            $propertyValue = $obj.$oldPropertyName
            
            # Remove old property and add new one
            $obj.PSObject.Properties.Remove($oldPropertyName)
            $obj | Add-Member -NotePropertyName $newPropertyName -NotePropertyValue $propertyValue
        }
    }
    
    return $InputObject
}

<#
.SYNOPSIS
    Gets comprehensive information about servers by combining data from multiple configuration files.

.DESCRIPTION
    Retrieves and combines information from ComputerInfo.json, ServerTypes.json, 
    FkServerTypesPortGroup.json, and PortGroup.json to create a complete view of server configurations.
    Uses regex pattern matching to find server group matches.

.PARAMETER ComputerName
    The name of the computer to get information for. Supports regex patterns.

.EXAMPLE
    Get-ServerConfiguration -ComputerName "WEB.*"
    # Returns configuration for all web servers

.EXAMPLE
    Get-ServerConfiguration -ComputerName "APP01"
    # Returns configuration for specific server APP01

.OUTPUTS
    PSCustomObject containing combined server configuration data
#>
function Get-ServerConfiguration {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ComputerName = $($env:ComputerName.ToLower().Trim()),
        [Parameter(Mandatory = $false)]
        [bool]$ReportAllConsumerDetails = $false,
        [Parameter(Mandatory = $false)]
        [bool]$MatchActiveDatabases = $true
    )
    try {
        if ($ComputerName -is [string]) {
            $ComputerName = @($ComputerName)
        }
        # Get data from all configuration files
        $allComputerInfos = Get-ComputerInfoJson
        $filteredComputerNames = @()
        if ($ComputerName -eq "*") {
            $filteredComputerNames = $allComputerInfos
        }
        else {
            foreach ($computerName in $ComputerName) {
                $filteredComputerNames += $allComputerInfos | Where-Object { $_.Name.ToLower().Trim() -eq $computerName.ToLower().Trim() }
            }
            if ($filteredComputerNames.Count -eq 0) {
                $filteredComputerNames = [PSCustomObject]@{
                    Name     = $ComputerName
                    Type     = "Server"
                    IsActive = $true
                    Platform = Get-CurrentComputerPlatform
                }
            }
        }
        $portGroups = Get-PortGroupJson

        if ($MatchActiveDatabases -eq $true) {
            $portGroups = $portGroups | Where-Object { -not $_.Id.StartsWith("pg-db") }
            $databaseConnections = Get-DatabasesJson
            $distinctDatabaseProviders = @($($databaseConnections | 
                    Where-Object { $_.ConnectionInfo.IsActive -eq $true } | 
                    Select-Object -ExpandProperty ConnectionInfo | 
                    Select-Object -ExpandProperty Provider | 
                    Sort-Object -Unique).ToString())
            foreach ($databaseProvider in $distinctDatabaseProviders) {
                $allDatabaseServers = $databaseConnections | Where-Object { $_.ConnectionInfo.IsActive -eq $true -and $_.ConnectionInfo.Provider -eq $databaseProvider } | Select-Object -ExpandProperty ConnectionInfo | Select-Object -ExpandProperty Server | Select-Object -Unique

                foreach ($databaseServer in $allDatabaseServers) {
                    $serverName = $databaseServer.ToLower().Trim().Split(".")[0]

                    $tempPortGroup = [PSCustomObject]@{
                        Id             = $(("pg-db-$databaseProvider-$serverName").ToLower().Trim())
                        Description    = "$($databaseProvider.ToTitleCase()) ports"
                        InternetAccess = $false
                        ProviderHosts  = @([PSCustomObject]@{
                                pattern = "$($serverName.ToLower().Trim())"
                                isRegex = $false
                            })
                        ConsumerHosts  = @([PSCustomObject]@{
                                pattern = "*"
                                isRegex = $false
                            })
                        Ports          = @()
                    }                   
                    $serverDatabases = @($databaseConnections | Where-Object { $_.ConnectionInfo.Server -eq $($databaseServer.ToString()) })

                    foreach ($database in $serverDatabases) {
                        $port = $database.ConnectionInfo.Port
                        $tempPortGroup.Ports += [PSCustomObject]@{
                            Port        = $port
                            Protocols   = @("TCP")
                            Description = "$($databaseProvider.ToTitleCase()) port for $($database.ConnectionInfo.Database)"
                        }
                    }
                    if ($tempPortGroup.Ports.Count -gt 0) {
                        $portGroups += $tempPortGroup
                    }
    
    
                }
            }
        }
        #$ServerTypes = Get-ServerTypesJson
        #$ServerTypesPortGroups = Get-ServerPortGroupsMappingJson

        # Create a new array to hold the processed port groups

        $processedPortGroups = @()

        # $reportOnlyProviders = $true

        $totalComputers = $filteredComputerNames.Count
        $currentComputerCount = 0

        foreach ($currentComputer in $filteredComputerNames) {
            $currentComputerCount++
            Write-Progress -Activity "Processing computers" -Status "$($currentComputer.Name)" -PercentComplete (($currentComputerCount / $totalComputers) * 100)
            
            #$currentComputerName = $currentComputer.Name
            $isPortProvider = $false
            $isPortConsumer = $false
            # Process each port group
            foreach ($portGroup in $portGroups) {
                #Write-LogMessage "Processing port group $($portGroup.Id)" -Level INFO
                # Process each port group                
                foreach ($consumerHost in $portGroup.ConsumerHosts) {
                    $isPortConsumer = if ($consumerHost.isRegex) {
                        # For regex patterns, check if current computer matches pattern
                        $currentComputer.Name.ToLower().Trim() -match $consumerHost.pattern -or $consumerHost.pattern -eq "*"
                    }
                    else {
                        # For non-regex patterns, check exact match
                        $currentComputer.Name.ToLower().Trim() -eq $consumerHost.pattern.ToLower().Trim() -or $consumerHost.pattern -eq "*"
                    }
                    $consumerText = if ($ReportAllConsumerDetails) {
                        $currentComputer.Name
                    }
                    else {
                        $consumerHost.pattern
                    }
                    $providerHostComputernames = @()
                    foreach ($providerHost in $portGroup.ProviderHosts) {
                        $isPortProvider = if ($providerHost.isRegex) {
                            # For regex patterns, check if current computer matches pattern
                            $currentComputer.Name.ToLower().Trim() -match $providerHost.pattern
                        }
                        else {
                            # For non-regex patterns, check exact match
                            $currentComputer.Name.ToLower().Trim() -eq $providerHost.pattern.ToLower().Trim()
                        }

                        if ($providerHost.isRegex) {
                            # For regex patterns, check if current computer matches pattern
                            $providerHostComputernames += ($allComputerInfos | Where-Object { $_.Name.ToLower().Trim() -match $providerHost.pattern }).Name
                        }
                        else {
                            # For non-regex patterns, check exact match
                            $providerHostComputernames += $providerHost.pattern.ToLower().Trim()
                        }
                    }

                   
                    if (-not $isPortProvider -and -not $isPortConsumer) {
                        continue
                    }
                    foreach ($providerHostComputerName in $providerHostComputernames) {
                        if ($providerHostComputerName -eq $currentComputer.Name) {
                            continue
                        }
                        foreach ($port in $portGroup.Ports) {
                            foreach ($protocol in $port.Protocols) {
                                #Write-LogMessage "Port datatype is $($port.Port.GetType().Name)" -Level INFO
                          
                                if ($port.Port -is [int]) {
                                    $currentPortStart = $port.Port
                                    $currentPortEnd = $port.Port
                                }
                                elseif ($port.Port -is [string]) {
                                    $currentPortStart = [int]$port.Port.ToLower().Trim()
                                    $currentPortEnd = [int]$port.Port.ToLower().Trim()
                                }
                                else {
                                    # Write-LogMessage "Port.Start datatype is $($port.Port.Start.GetType().Name)" -Level INFO
                                    # Write-LogMessage "Port.End datatype is $($port.Port.End.GetType().Name)" -Level INFO

                                    if ($port.Port.Start -is [int64]) {
                                        $currentPortStart = [int]$port.Port.Start
                                    }
                                    elseif ($port.Port.Start -is [string]) {
                                        $currentPortStart = [int]$port.Port.Start.ToLower().Trim()
                                    }
                                    if ($port.Port.End -is [int64]) {
                                        $currentPortEnd = [int]$port.Port.End
                                    }
                                    elseif ($port.Port.End -is [string]) {
                                        $currentPortEnd = [int]$port.Port.End.ToLower().Trim()
                                    }
                                }
                                if ($currentPortEnd -lt $currentPortStart) {
                                    $tempPort = $currentPortStart   
                                    $currentPortStart = $currentPortEnd
                                    $currentPortEnd = $tempPort
                                }
                                if ($currentPortStart -and $currentPortEnd) {
                                    $processedPortGroup = [PSCustomObject]@{
                                        ProviderHost          = $providerHostComputerName
                                        ProviderHostIpAddress = ""
                                        ConsumerHost          = $consumerText
                                        ConsumerHostIpAddress = ""
                                        Protocol              = $protocol
                                        PortStart             = $currentPortStart
                                        PortEnd               = $currentPortEnd
                                        InternetAccess        = $portGroup.InternetAccess
                                        IsPortRange           = $currentPortStart -ne $currentPortEnd
                                        PortDescription       = $port.Description
                                        PortGroupId           = $portGroup.Id
                                        PortGroupDescription  = $portGroup.Description
                                    }
                                    # Only add unique port groups
                                    if (-not ($processedPortGroups | Where-Object { 
                                                $_.ProviderHost -eq $processedPortGroup.ProviderHost -and
                                                $_.ProviderHostIpAddress -eq $processedPortGroup.ProviderHostIpAddress -and
                                                $_.ConsumerHost -eq $processedPortGroup.ConsumerHost -and
                                                $_.ConsumerHostIpAddress -eq $processedPortGroup.ConsumerHostIpAddress -and
                                                $_.Protocol -eq $processedPortGroup.Protocol -and 
                                                $_.PortStart -eq $processedPortGroup.PortStart -and
                                                $_.PortEnd -eq $processedPortGroup.PortEnd -and
                                                $_.InternetAccess -eq $processedPortGroup.InternetAccess -and
                                                $_.IsPortRange -eq $processedPortGroup.IsPortRange -and
                                                $_.PortDescription -eq $processedPortGroup.PortDescription -and
                                                $_.PortGroupId -eq $processedPortGroup.PortGroupId -and
                                                $_.PortGroupDescription -eq $processedPortGroup.PortGroupDescription
                                            })) {
                                        $processedPortGroups += $processedPortGroup
                                    }
                         
                                }
                            }
                        }
                    }
                }
            }
        }
        $portGroups = @()
        $portGroups = $processedPortGroups
        #$portGroups = $portGroups | Select-Object -Unique
        $portGroups = $portGroups | Sort-Object -Property ProviderHost, PortGroupId
        # Remove duplicates by comparing all properties
        # $uniquePortGroups = @()
        # $seen = @{}

        # foreach ($group in $portGroups) {
        #     $key = "{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}" -f `
        #         $group.ProviderHost,
        #         $group.ConsumerHost, 
        #         $group.Protocol,
        #         $group.PortStart,
        #         $group.PortEnd,
        #         $group.InternetAccess,
        #         $group.IsPortRange,
        #         $group.PortDescription,
        #         $group.PortGroupId,
        #         $group.PortGroupDescription

        #     if (-not $seen.ContainsKey($key)) {
        #         $seen[$key] = $true
        #         $uniquePortGroups += $group
        #     }
        # }
        # $portGroups = $uniquePortGroups
        #$portGroups | Format-Table -AutoSize  | Out-String | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }

        return $portGroups
    }
    catch {
        Write-LogMessage "Error getting server configuration for $ComputerName" -Level ERROR -Exception $_
        return $null
    }
    
}

<#
.SYNOPSIS
    Gets a filtered list of computer objects.

.DESCRIPTION
    Retrieves a list of computer objects filtered by type, active status, and platform.

.PARAMETER Type
    Optional. Filter by computer type (e.g., "Server", "Developer Machine").

.PARAMETER IsActive
    Optional. Filter by active status. Default is true.

.PARAMETER Platform
    Optional. Filter by platform type.

.EXAMPLE
    Get-ComputerObjectList -Type "Server" -IsActive $true
    # Returns all active servers

.EXAMPLE
    Get-ComputerObjectList -Platform "Windows" -IsActive $true
    # Returns all active Windows computers
#>
function Get-ComputerObjectList {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Type,
        [Parameter(Mandatory = $false)]
        [bool]$IsActive = $true,
        [Parameter(Mandatory = $false)]
        [string]$Platform
    )
    $servers = @()
    if ($Type) {
        $servers = Get-ComputerInfoJson | Where-Object { $_.Type -eq $Type }
    }

    if ($IsActive -eq $true) {  
        $servers = $servers | Where-Object { $_.IsActive -eq $IsActive }
    }   

    if ($Platform) {
        $servers = $servers | Where-Object { $_.Platform -eq $Platform }
    }

    return $servers
}

<#
.SYNOPSIS
    Gets a filtered list of computer names.

.DESCRIPTION
    Retrieves a list of computer names filtered by type, active status, and platform.

.PARAMETER Type
    Optional. Filter by computer type (e.g., "Server", "Developer Machine").

.PARAMETER IsActive
    Optional. Filter by active status. Default is true.

.PARAMETER Platform
    Optional. Filter by platform type.

.EXAMPLE
    Get-ComputerList -Type "Server"
    # Returns names of all active servers
#>
function Get-ComputerList {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Type,
        [Parameter(Mandatory = $false)]
        [bool]$IsActive = $true,
        [Parameter(Mandatory = $false)]
        [string]$Platform
    )
    $servers = @()
    $servers = Get-ComputerObjectList -Type $Type -IsActive $IsActive -Platform $Platform
    return $servers.Name    
}
<#
.SYNOPSIS
    Gets a computer object by name.

.DESCRIPTION
    Retrieves a specific computer object from the configuration by matching its name.

.PARAMETER Name
    The name of the computer to retrieve.

.EXAMPLE
    $computer = Get-Computer -Name "SERVER01"
    # Returns the computer object for SERVER01
#>
function Get-ComputerMetaData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    $computers = Get-ComputerInfoJson
    return $computers | Where-Object { $_.Name.ToLower().Trim() -eq $Name.ToLower().Trim() }
}

<#
.SYNOPSIS
    Gets a list of all server objects.

.DESCRIPTION
    Retrieves a list of all active server objects from the configuration.

.EXAMPLE
    $servers = Get-ServerObjectList
    # Returns all active server objects
#>
function Get-ServerObjectList {
    return (Get-ComputerObjectList -Type "Server" -IsActive $true)
}
function Get-ServerObjectListForPlatform {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Platform = "Azure"
    )
    return (Get-ComputerObjectList -Type "Server" -IsActive $true -Platform $Platform)
}

<#
.SYNOPSIS
    Gets a list of all server names.

.DESCRIPTION
    Retrieves a list of names for all active servers.

.EXAMPLE
    $serverNames = Get-ServerList
    # Returns names of all active servers
#>
function Get-ServerList {
    return @((Get-ServerObjectList).Name)
}
function Get-ServerListForPlatform {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Platform = "Azure"
    )
    $servers = Get-ServerObjectListForPlatform -Platform $Platform
    $result = @(($servers).Name)
    return $result
}

function Get-WorkstationListForPlatform {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Platform = "Azure"
    )
    $workstations = Get-ComputerObjectList -Type "Developer Machine" -IsActive $true -Platform $Platform
    $result = @(($workstations).Name)
    return $result
}
function Get-WorkstationList {
    return @((Get-ComputerObjectList -Type "Developer Machine" -IsActive $true).Name)
}
<#
.SYNOPSIS
    Gets a list of all developer machine objects.

.DESCRIPTION
    Retrieves a list of all active developer machine objects from the configuration.

.EXAMPLE
    $devMachines = Get-WorkstationObjectList
    # Returns all active developer machine objects
#>
function Get-WorkstationObjectList {
    return (Get-ComputerObjectList -Type "Developer Machine" -IsActive $true)
}

<#
.SYNOPSIS
    Gets a list of all developer machine names.

.DESCRIPTION
    Retrieves a list of names for all active developer machines.

.EXAMPLE
    $devMachineNames = Get-WorkstationList
    # Returns names of all active developer machines
#>
function Get-WorkstationList {
    return (Get-WorkstationObjectList).Name
}

<#
.SYNOPSIS
    Tests connectivity to a remote computer using multiple methods.

.DESCRIPTION
    Tests connectivity to a remote computer using DNS resolution, WMI, and RPC.
    Each test has a timeout to prevent hanging.

.PARAMETER ComputerName
    The name of the computer to test connectivity to.

.EXAMPLE
    Test-ComputerConnection -ComputerName "SERVER01"
    # Returns $true if any connectivity test succeeds, $false otherwise
#>
function Test-ComputerConnection {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )
    
    # Test 1: DNS Resolution
    try {
        $dnsTimeout = [System.TimeSpan]::FromSeconds(10)
        $dnsTask = [System.Net.Dns]::GetHostEntryAsync($ComputerName)
        if ([System.Threading.Tasks.Task]::WaitAny(@($dnsTask), $dnsTimeout.TotalMilliseconds) -eq 0) {
            $dnsResult = $dnsTask.Result
            if ($null -ne $dnsResult) {
                Write-LogMessage "DNS check succeeded for $ComputerName" -Level INFO
                return $true
            }
        }
    }
    catch {
        Write-LogMessage "DNS resolution failed for $ComputerName" -Level DEBUG -Exception $_ -QuietMode
    }
    
    # Test 2: WMI with timeout
    try {
        $wmiTimeout = New-TimeSpan -Seconds 10
        $wmiOption = New-CimSessionOption -Protocol Wsman
        $wmiSession = New-CimSession -ComputerName $ComputerName -SessionOption $wmiOption -OperationTimeoutSec $wmiTimeout.TotalSeconds -ErrorAction Stop
        $wmiResult = Get-CimInstance -ClassName Win32_ComputerSystem -CimSession $wmiSession
        if ($null -ne $wmiResult) {
            Write-LogMessage "WMI check succeeded for $ComputerName" -Level INFO
            Remove-CimSession -CimSession $wmiSession
            return $true
        }
        Remove-CimSession -CimSession $wmiSession
    }
    catch {
        Write-LogMessage "WMI failed for $ComputerName" -Level DEBUG -Exception $_ -QuietMode
    }
    
    # Test 3: RPC with timeout
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($ComputerName, 135, $null, $null)
        $wait = $asyncResult.AsyncWaitHandle.WaitOne(10000, $false)  # 10 second timeout
        if ($wait) {
            $tcpClient.EndConnect($asyncResult)
            $tcpClient.Close()
            Write-LogMessage "RPC check succeeded for $ComputerName" -Level INFO
            return $true
        }
        $tcpClient.Close()
    }
    catch {
        Write-LogMessage "RPC check failed for $ComputerName" -Level DEBUG -Exception $_ -QuietMode
    }
    Write-LogMessage "All connectivity tests failed for $ComputerName" -Level WARN 

    # If we get here, all checks failed
    return $false
}


<#
.SYNOPSIS
    Gets the IP address of a remote computer.

.DESCRIPTION
    Attempts to retrieve the IP address of a specified computer using multiple methods:
    DNS resolution and WMI queries. Returns the first successful result with configurable
    timeouts for each method.

.PARAMETER ComputerName
    The name of the computer to get the IP address for.

.PARAMETER Quiet
    If true, suppresses informational and error messages. Default is false.

.EXAMPLE
    Get-ComputerIpAddress -ComputerName "SERVER01"
    # Returns the IP address of SERVER01

.EXAMPLE
    Get-ComputerIpAddress -ComputerName "WORKSTATION01" -Quiet $true
    # Returns the IP address without logging messages

.OUTPUTS
    String - The IP address of the computer, or empty string if not found
#>
function Get-ComputerIpAddress {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        [Parameter(Mandatory = $false)]
        [bool]$Quiet = $false
    )
    
    # Test 1: DNS Resolution
    try {
        $dnsTimeout = [System.TimeSpan]::FromSeconds(10)
        $dnsTask = [System.Net.Dns]::GetHostEntryAsync($ComputerName)
        if ([System.Threading.Tasks.Task]::WaitAny(@($dnsTask), $dnsTimeout.TotalMilliseconds) -eq 0) {
            $dnsResult = $dnsTask.Result
            if ($null -ne $dnsResult) {
                if (-not $Quiet) {
                    Write-LogMessage "DNS check succeeded for $ComputerName" -Level INFO
                }
                return $dnsResult.AddressList[0].ToString()
            }
        }
    }
    catch {
        if (-not $Quiet) {
            Write-LogMessage "DNS resolution failed for $ComputerName" -Level ERROR -Exception $_
        }
    }
    
    # Test 2: WMI with timeout
    try {
        $wmiTimeout = New-TimeSpan -Seconds 10
        $wmiOption = New-CimSessionOption -Protocol Wsman
        $wmiSession = New-CimSession -ComputerName $ComputerName -SessionOption $wmiOption -OperationTimeoutSec $wmiTimeout.TotalSeconds -ErrorAction Stop
        $wmiResult = Get-CimInstance -ClassName Win32_ComputerSystem -CimSession $wmiSession
        if ($null -ne $wmiResult) {
            if (-not $Quiet) {
                Write-LogMessage "WMI check succeeded for $ComputerName" -Level INFO
            }
            Remove-CimSession -CimSession $wmiSession
            return $wmiResult.IPv4Address
        }
        Remove-CimSession -CimSession $wmiSession
    }
    catch {
        if (-not $Quiet) {
            Write-LogMessage "WMI failed for $ComputerName" -Level ERROR -Exception $_
        }
    }
  
    # If we get here, all checks failed
    return ""
}

<#
.SYNOPSIS
    Gets the DNS hostname from an IP address.

.DESCRIPTION
    Attempts to perform reverse DNS lookup to resolve an IP address to its
    corresponding hostname using multiple methods: DNS resolution and WMI queries.
    Returns the first successful result with configurable timeouts.

.PARAMETER HostIpAddress
    The IP address to resolve to a hostname.

.PARAMETER Quiet
    If true, suppresses informational and error messages. Default is false.

.EXAMPLE
    Get-HostDnsAddress -HostIpAddress "192.168.1.100"
    # Returns the hostname for IP address 192.168.1.100

.EXAMPLE
    Get-HostDnsAddress -HostIpAddress "10.0.0.50" -Quiet $true
    # Returns the hostname without logging messages

.OUTPUTS
    String - The hostname of the IP address, or the original IP if not found
#>
function Get-HostDnsAddress {
    param (
        [Parameter(Mandatory = $true)]
        [string]$HostIpAddress,
        [Parameter(Mandatory = $false)]
        [bool]$Quiet = $false
    )
    
    # Test 1: DNS Resolution
    try {
        $dnsTimeout = [System.TimeSpan]::FromSeconds(10)
        $dnsTask = [System.Net.Dns]::GetHostEntryAsync($HostIpAddress)
        if ([System.Threading.Tasks.Task]::WaitAny(@($dnsTask), $dnsTimeout.TotalMilliseconds) -eq 0) {
            $dnsResult = $dnsTask.Result
            if ($null -ne $dnsResult) {
                if (-not $Quiet) {
                    Write-LogMessage "DNS check succeeded for $HostIpAddress" -Level INFO
                }
                return $dnsResult.HostName
            }
        }
    }
    catch {
        if (-not $Quiet) {
            Write-LogMessage "DNS resolution failed for $HostIpAddress" -Level ERROR -Exception $_
        }
    }
    
    # Test 2: WMI with timeout
    try {
        $wmiTimeout = New-TimeSpan -Seconds 10
        $wmiOption = New-CimSessionOption -Protocol Wsman
        $wmiSession = New-CimSession -ComputerName $ComputerName -SessionOption $wmiOption -OperationTimeoutSec $wmiTimeout.TotalSeconds -ErrorAction Stop
        $wmiResult = Get-CimInstance -ClassName Win32_ComputerSystem -CimSession $wmiSession
        if ($null -ne $wmiResult) {
            if (-not $Quiet) {
                Write-LogMessage "WMI check succeeded for $HostIpAddress" -Level INFO
            }
            Remove-CimSession -CimSession $wmiSession
            return $wmiResult.IPv4Address
        }
        Remove-CimSession -CimSession $wmiSession
    }
    catch {
        if (-not $Quiet) {
            Write-LogMessage "WMI failed for $HostIpAddress" -Level ERROR -Exception $_
        }
    }
  
    # If we get here, all checks failed
    return $HostIpAddress
}

<#
.SYNOPSIS
    Tests connectivity to a specific port on a remote server.

.DESCRIPTION
    Attempts to establish a TCP connection to a specified port on a remote server
    and returns connection status and latency information.

.PARAMETER Server
    The name or IP address of the server to test.

.PARAMETER Port
    The port number to test.

.PARAMETER ServiceType
    A description of the service running on the port.

.PARAMETER Timeout
    The connection timeout in milliseconds. Default is 1000ms.

.EXAMPLE
    Test-PortConnectivity -Server "SERVER01" -Port 80 -ServiceType "HTTP" -Timeout 2000
    # Tests connection to port 80 on SERVER01 with a 2-second timeout
#>

function Test-PortConnectivity {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Server,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [Parameter(Mandatory = $false)]
        [int]$Timeout = 1000
    )
    try {
        $tcpClient = [System.Net.Sockets.TcpClient]::new()
        # $Timeout is in milliseconds (1000ms = 1 second)
        $connection = $tcpClient.ConnectAsync($Server, $Port).Wait($Timeout) 
        

        if ($connection) {
            $status = "Open"
            # Get approximate latency
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $tcpClient.Close()
            $stopwatch.Stop()
            $latency = "$($stopwatch.ElapsedMilliseconds)ms"
        }
        else {
            $status = "Closed/No Service"
            $latency = " - "
        }
    }
    catch {
        $status = "Closed"
        $latency = " - "
    }
    finally {
        if ($tcpClient) {
            $tcpClient.Dispose()
        }
    }
    
    [PSCustomObject]@{
        Server  = $Server
        Port    = $Port
        Status  = $status
        Latency = $latency
    }
}

<#
.SYNOPSIS
    Tests UDP connectivity to a specific port on a remote server.

.DESCRIPTION
    Attempts to verify UDP connectivity to a specified port on a remote server.
    Since UDP is connectionless, this function sends a test packet and attempts to
    determine if the port is open based on the response or lack of errors.

.PARAMETER Server
    The name or IP address of the server to test.

.PARAMETER Port
    The port number to test.

.PARAMETER ServiceType
    A description of the service running on the port.

.PARAMETER Timeout
    The connection timeout in milliseconds. Default is 1000ms.

.EXAMPLE
    Test-UdpConnectivity -Server "SERVER01" -Port 53 -ServiceType "DNS" -Timeout 2000
    # Tests UDP connectivity to port 53 on SERVER01 with a 2-second timeout
#>
function Test-UdpConnectivity {
    param (
        [string]$Server,
        [int]$Port,
        [string]$ServiceType,
        [int]$Timeout = 1000
    )
    
    return Test-PortConnectivity -Server $Server -Port $Port -ServiceType $ServiceType -Timeout $Timeout -Protocol "UDP"
}

<#
.SYNOPSIS
    Updates the availability status of computers in the configuration.

.DESCRIPTION
    Tests connectivity to each computer in the configuration and updates their availability status.
    The function can handle both server and developer machine types.

.EXAMPLE
    Set-ComputerAvailabilityStatus
    # Updates the availability status of all computers in the configuration
#>
function Set-ComputerAvailabilityStatus {    
    # Read the JSON file
    $computers = Get-ComputerInfoJson


    # Process each computer
    $totalComputers = $computers.Count
    $currentComputer = 0
    $hasChanges = $false

    foreach ($computer in $computers) {
        $currentComputer++
        $progressParams = @{
            Activity        = "Checking computer status"
            Status          = "Processing $($computer.Name) ($currentComputer of $totalComputers)"
            PercentComplete = ($currentComputer / $totalComputers * 100)
        }
        Write-Progress @progressParams

        if ($computer.IsActive) {
            Write-LogMessage "Checking status for computer: $($computer.Name)" -Level INFO
            $isActive = Test-ComputerConnection -ComputerName $computer.DomainName
        
            if ($isActive -ne $computer.IsActive) {
                $hasChanges = $true
                $computer.IsActive = $isActive
            }
        
            if ($isActive) {
                Write-LogMessage "`tComputer $($computer.Name) is ACTIVE" -Level INFO
            }
            else {
                Write-LogMessage "`tComputer $($computer.Name) is INACTIVE" -Level ERROR
            }
        }
    }

    Write-Progress -Activity "Checking computer status" -Completed

    # Save changes only if needed
    if ($hasChanges) {
        try {
            # Create backup first
            $backupFilePath = Join-Path $(Get-ApplicationDataPath) "FkComputerInfo_$(Get-Date -Format "yyyyMMdd_HHmmss").json"
            Write-LogMessage "Creating backup at: $backupFilePath" -Level INFO
            Copy-Item -Path $(Get-ComputerInfoJsonFilename) -Destination $backupFilePath -Force
        
            # Save updated data
            Set-ComputerInfoJson -Computers $computers
            Write-LogMessage "Successfully saved changes" -Level INFO
        }
        catch {
            Write-LogMessage "Failed to save changes" -Level ERROR -Exception $_
            exit 1
        }
    }
    else {
        Write-LogMessage "No changes detected - skipping save" -Level INFO
    } 
}

<#
.SYNOPSIS
    Detects the current computer's platform type.

.DESCRIPTION
    Determines the platform where the computer is running by analyzing system information.
    Uses WMI to check manufacturer and model information to identify Azure, Digiplex, 
    or Local environments.

.EXAMPLE
    Get-CurrentComputerPlatform
    # Returns "Azure", "Digiplex", or "Local"

.OUTPUTS
    String - The platform type where the computer is running
#>
function Get-CurrentComputerPlatform {
    $platform = ""
    # Check using WMI
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($computerSystem.Manufacturer -like "*Microsoft Corporation*" -and 
        $computerSystem.Model -like "*Virtual Machine*") {
        $platform = "Azure"
    }
    elseif ($computerSystem.Manufacturer -like "*VMware, Inc.*") {
        $platform = "Digiplex"
    }
    elseif ($computerSystem.Manufacturer -like "*Lenovo*") {
        $platform = "Local"
    }
    else {
        $platform = "Local"
    }
    return $platform
}

<#
.SYNOPSIS
    Adds the current computer to the configuration file.

.DESCRIPTION
    Adds the current computer's information to the ComputerInfo.json file.
    Automatically detects computer type and platform.

.EXAMPLE
    Add-CurrentComputer
    # Adds the current computer to the configuration
#>
function Add-CurrentComputer {
    param(
        [Parameter(Mandatory = $false)]
        [bool]$AutoConfirm = $false,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Server", "Developer Machine")]
        [string]$Type = "Server",
        [Parameter(Mandatory = $false)]
        [string]$Purpose = "",
        [Parameter(Mandatory = $false)]
        [string]$Comments = "",
        [Parameter(Mandatory = $false)]
        [string[]]$Applications = @(),
        [Parameter(Mandatory = $false)]
        [string[]]$Environments = @("DEV"),
        [Parameter(Mandatory = $false)]
        [bool]$SingleUser = $false

    )   
    try {
        # # Validate the Applications    
        # $Applications = $Applications | ForEach-Object { $_ -as [string] }
        # # Validate the Type
        # if ($Applications -eq "") {
        #     throw "Applications is required"
        # }

        $computer = [PSCustomObject]@{
            Name         = $env:COMPUTERNAME
            Type         = $Type
            Platform     = Get-CurrentComputerPlatform
            Purpose      = $Purpose
            Applications = $Applications
            Comments     = $Comments
            DomainName   = $env:COMPUTERNAME + ".DEDGE.fk.no"
            IsActive     = $true
            SingleUser   = ""
            Environments = @()
        }
        if ($SingleUser) {
            $computer.SingleUser = $env:USERNAME
        }
        if ($Applications -is [string]) {
            $computer.Applications = @($Applications)
        }
        else {
            $computer.Applications = $Applications
        }
        if ($Applications -eq @()) {
            if ($env:COMPUTERNAME.ToUpper().Contains("FKM")) {
                $computer.Applications = @("FKM")
            }     
            if ($env:COMPUTERNAME.ToUpper().Contains("INL")) {
                $computer.Applications = @("INL")
            }
        }
        # Convert Environments to array if it's a string
        if ($Environments -is [string]) {
            $computer.Environments = @($Environments)
        }
        else {
            $computer.Environments = $Environments
        }
        if ([string]::IsNullOrEmpty($Environments)) {
            if ($env:COMPUTERNAME.ToUpper().StartsWith("T-NO1") -and $env:COMPUTERNAME.ToUpper().Contains("DEV") -and $Type -eq "Server") {
                $computer.Environments = @("DEV")
            }
            elseif ($env:COMPUTERNAME.ToUpper().StartsWith("T-NO1") -and $Type -eq "Server") {
                $computer.Environments = @("TST")
            }
            elseif ($env:COMPUTERNAME.ToUpper().StartsWith("P-NO1") -and $Type -eq "Server") {
                $computer.Environments = @("PRD")
            }
        }  
        Write-Host "Adding computer: $($computer.Name)" -ForegroundColor Yellow
        $computer | ConvertTo-Json -Depth 100 | Write-Host -ForegroundColor Gray
        Add-ComputerInfo -computer $computer -AutoConfirm $false
        Write-Host "Computer added: $($computer.Name)" -ForegroundColor Green
    }
    catch {
        Write-LogMessage "Error adding computer: $($computer.Name)" -Level ERROR -Exception $_
    }
}


<#
.SYNOPSIS
    Creates and configures a folder with specified permissions.

.DESCRIPTION
    This function creates a folder on the local machine and sets up appropriate access control lists (ACLs).
    It can configure permissions for administrators, everyone, and additional specified users.

.PARAMETER Path
    The full path where the folder should be created.

.PARAMETER AdditionalAdmins
    Optional array of additional users/groups to grant full control permissions.

.PARAMETER EveryonePermission
    Permission level to grant to the Everyone group. Valid values are "ReadAndExecute", "Read", "Write", "FullControl", or empty string.

.EXAMPLE
    Add-Folder -Path "C:\SharedFolder" -EveryonePermission "ReadAndExecute"
    # Creates a folder with read and execute permissions for everyone

.EXAMPLE
    Add-Folder -Path "D:\Data" -AdditionalAdmins @("DOMAIN\GroupA", "DOMAIN\GroupB")
    # Creates a folder with full control for specified groups
#>

function Add-Folder {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [string[]]$AdditionalAdmins = @(),
        [Parameter(Mandatory = $false)]
        [ValidateSet(
            # Basic Permissions
            "Read",
            "ReadAndExecute", 
            "Write",
            "WriteAndRead",
            "ReadWriteExecute",
            "Change",
            "Modify",
            "Full",
            "FullControl",
            
            # Granular Permissions
            "ReadData",
            "WriteData",
            "AppendData",
            "CreateFiles",
            "CreateDirectories",
            "Delete",
            "DeleteSubdirectoriesAndFiles",
            "Execute",
            "Traverse",
            "ReadPermissions",
            "ChangePermissions",
            "TakeOwnership",
            
            # Common Combinations
            "ReadOnly",
            "WriteOnly",
            "ListFolder",
            "CreateFilesOnly",
            "NoAccess",
            
            # SMB-specific
            "ReadWrite",
            "WriteOnly",
            # None
            ""
        )]
        [string]$EveryonePermission = "ReadAndExecute",
        [Parameter(Mandatory = $false)]
        [bool]$IsWorkstation = $false
    )
  
    if (-not (Test-Path $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        if ( $IsWorkstation) {
            return
        }
        Write-LogMessage "Created folder $Path with default owner $($env:USERDOMAIN)\$($env:USERNAME)" -Level INFO
    }
    else {
        if ( $IsWorkstation) {
            return
        }
    }
    $acl = Get-Acl $Path
    $acl.SetOwner([System.Security.Principal.NTAccount]"$($env:USERDOMAIN)\$($env:USERNAME)")
    Set-Acl -Path $Path -AclObject $acl
    Write-LogMessage "Set owner of folder $Path to $($env:USERDOMAIN)\$($env:USERNAME)" -Level INFO
    Add-Privilege -Path $Path -AdditionalAdmins $AdditionalAdmins -EveryonePermission $EveryonePermission
}
<#
  .SYNOPSIS
      Creates and configures a folder with specified permissions.
  
  .DESCRIPTION
      This function creates a folder on the local machine and sets up appropriate access control lists (ACLs).
      It can configure permissions for administrators, everyone, and additional specified users.
  
  .PARAMETER Path
      The full path where the folder should be created.
  
  .PARAMETER AdditionalAdmins
      Optional array of additional users/groups to grant full control permissions.
  
  .PARAMETER EveryonePermission
      Permission level to grant to the Everyone group. Valid values are "ReadAndExecute", "Read", "Write", "FullControl", or empty string.
  
  .EXAMPLE
      Add-Folder -Path "C:\SharedFolder" -EveryonePermission "ReadAndExecute"
      # Creates a folder with read and execute permissions for everyone
  
  .EXAMPLE
      Add-Folder -Path "D:\Data" -AdditionalAdmins @("DOMAIN\GroupA", "DOMAIN\GroupB")
      # Creates a folder with full control for specified groups
  #>
function Add-Privilege {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [string[]]$AdditionalAdmins = @(),
        [Parameter(Mandatory = $false)]
        [ValidateSet(
            # Basic Permissions
            "Read",
            "ReadAndExecute", 
            "Write",
            "WriteAndRead",
            "ReadWriteExecute",
            "Change",
            "Modify",
            "Full",
            "FullControl",
            
            # Granular Permissions
            "ReadData",
            "WriteData",
            "AppendData",
            "CreateFiles",
            "CreateDirectories",
            "Delete",
            "DeleteSubdirectoriesAndFiles",
            "Execute",
            "Traverse",
            "ReadPermissions",
            "ChangePermissions",
            "TakeOwnership",
            
            # Common Combinations
            "ReadOnly",
            "WriteOnly",
            "ListFolder",
            "CreateFilesOnly",
            "NoAccess",
            
            # SMB-specific
            "ReadWrite",
            "WriteOnly",
            # None
            ""
        )]
        [string]$EveryonePermission = "ReadAndExecute"
    )
  
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)
    
    try {
        $adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544") # Built-in Administrators SID
        
        # Check if the path is a file or directory to set appropriate inheritance flags
        $isDirectory = Test-Path $Path -PathType Container
        Write-LogMessage "Path is directory: $isDirectory" -Level DEBUG
        
        if ($isDirectory) {
            $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        }
        else {
            $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
        }
        
        $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
        $accessType = [System.Security.AccessControl.AccessControlType]::Allow
        
        # Debug information
        Write-LogMessage "Admin SID: $($adminSID.Value)" -Level DEBUG
        Write-LogMessage "Inheritance Flags: $inheritanceFlags" -Level DEBUG
        Write-LogMessage "Propagation Flags: $propagationFlags" -Level DEBUG
        Write-LogMessage "Access Type: $accessType" -Level DEBUG
        Write-LogMessage "Rights: FullControl" -Level DEBUG
        
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule($adminSID, [System.Security.AccessControl.FileSystemRights]::FullControl, $inheritanceFlags, $propagationFlags, $accessType)
        Write-LogMessage "Admin rule created successfully" -Level DEBUG
        
        $acl.AddAccessRule($adminRule)
        Write-LogMessage "Added Administrators permission to $Path" -Level DEBUG
    }
    catch {
        Write-LogMessage "Failed to add Administrators permission" -Level ERROR -Exception $_
    }
  
    if ($EveryonePermission -and (-not [string]::IsNullOrEmpty($EveryonePermission))) {
        
        try {
            $everyoneSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-1-0") # Everyone SID
            
            # Debug information for Everyone
            Write-LogMessage "Everyone Permission requested: $EveryonePermission" -Level DEBUG
            Write-LogMessage "Everyone SID: $($everyoneSID.Value)" -Level DEBUG
            
            # Map custom permission names to valid FileSystemRights values
            $mappedPermission = switch ($EveryonePermission) {
                "Read" { [System.Security.AccessControl.FileSystemRights]::Read }
                "ReadAndExecute" { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute }
                "Write" { [System.Security.AccessControl.FileSystemRights]::Write }
                "WriteAndRead" { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Write }
                "ReadWriteExecute" { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Write }
                "Change" { [System.Security.AccessControl.FileSystemRights]::Modify }
                "Modify" { [System.Security.AccessControl.FileSystemRights]::Modify }
                "Full" { [System.Security.AccessControl.FileSystemRights]::FullControl }
                "FullControl" { [System.Security.AccessControl.FileSystemRights]::FullControl }
                
                # Granular Permissions
                "ReadData" { [System.Security.AccessControl.FileSystemRights]::ReadData }
                "WriteData" { [System.Security.AccessControl.FileSystemRights]::WriteData }
                "AppendData" { [System.Security.AccessControl.FileSystemRights]::AppendData }
                "CreateFiles" { [System.Security.AccessControl.FileSystemRights]::CreateFiles }
                "CreateDirectories" { [System.Security.AccessControl.FileSystemRights]::CreateDirectories }
                "Delete" { [System.Security.AccessControl.FileSystemRights]::Delete }
                "DeleteSubdirectoriesAndFiles" { [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles }
                "Execute" { [System.Security.AccessControl.FileSystemRights]::ExecuteFile }
                "Traverse" { [System.Security.AccessControl.FileSystemRights]::Traverse }
                "ReadPermissions" { [System.Security.AccessControl.FileSystemRights]::ReadPermissions }
                "ChangePermissions" { [System.Security.AccessControl.FileSystemRights]::ChangePermissions }
                "TakeOwnership" { [System.Security.AccessControl.FileSystemRights]::TakeOwnership }
                
                # Common Combinations
                "ReadOnly" { [System.Security.AccessControl.FileSystemRights]::Read }
                "WriteOnly" { [System.Security.AccessControl.FileSystemRights]::Write }
                "ListFolder" { [System.Security.AccessControl.FileSystemRights]::ListDirectory }
                "CreateFilesOnly" { [System.Security.AccessControl.FileSystemRights]::CreateFiles }
                "NoAccess" { $null }
                
                # SMB-specific mapped to NTFS equivalents
                "ReadWrite" { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Write }
                
                default { [System.Security.AccessControl.FileSystemRights]::Read }
            }
            
            Write-LogMessage "Mapped permission: $mappedPermission" -Level DEBUG
            
            if ([string]::IsNullOrEmpty($mappedPermission)) {
                # Use same inheritance logic as admin section
                if ($isDirectory) {
                    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
                }
                else {
                    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
                }
                
                $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
                $accessType = [System.Security.AccessControl.AccessControlType]::Allow
                
                Write-LogMessage "Everyone inheritance flags: $inheritanceFlags" -Level DEBUG
                
                $everyoneRule = New-Object System.Security.AccessControl.FileSystemAccessRule($everyoneSID, $mappedPermission, $inheritanceFlags, $propagationFlags, $accessType)
                Write-LogMessage "Everyone rule created successfully" -Level DEBUG
                
                $acl.AddAccessRule($everyoneRule)
                Write-LogMessage "Added Everyone permission ($EveryonePermission -> $mappedPermission) to $Path" -Level DEBUG
            }
            else {
                Write-LogMessage "Skipping Everyone permission (NoAccess specified)" -Level DEBUG
            }
        }
        catch {
            Write-LogMessage "Failed to add Everyone permission" -Level ERROR -Exception $_
        }
    }
  
    foreach ($admin in $AdditionalAdmins) {
        try {
            # Debug information for additional admin
            Write-LogMessage "Processing additional admin: $admin" -Level DEBUG
            
            # Use same inheritance logic as other sections
            if ($isDirectory) {
                $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
            }
            else {
                $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
            }
            
            $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
            $accessType = [System.Security.AccessControl.AccessControlType]::Allow
            
            Write-LogMessage "Additional admin inheritance flags: $inheritanceFlags" -Level DEBUG
            
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule($admin, [System.Security.AccessControl.FileSystemRights]::FullControl, $inheritanceFlags, $propagationFlags, $accessType)
            Write-LogMessage "Additional admin rule created successfully for $admin" -Level DEBUG
            
            # $filename = "c:\tempfk\AdminRule_$(Get-Date -Format "yyyyMMdd_HHmmss").json"
            # Export-WorkObjectToJsonFile -WorkObject $adminRule -FileName $filename
            $acl.AddAccessRule($adminRule)
            Write-LogMessage "Added $admin permission to $Path" -Level DEBUG
        }
        catch {
            Write-LogMessage "Failed to add permission for $admin. All Ok" -Level WARN
        }
    }
    
    try {
        Set-Acl -Path $Path -AclObject $acl
        Write-LogMessage "Set ACL for $Path" -Level DEBUG
    }
    catch {
        Write-LogMessage "Failed to set ACL" -Level WARN -Exception $_
        Write-LogMessage "Attempting alternate method..." -Level WARN
        try {
            $acl | Set-Acl -Path $Path
        }
        catch {
            Write-LogMessage "Failed to set ACL using both methods" -Level ERROR -Exception $_
        }
    }
    
    Write-LogMessage "Privilege added to $Path" -Level INFO
}
<#
.SYNOPSIS
    Gets disk space information for local drives.

.DESCRIPTION
    Retrieves disk space usage information for all local hard drives (DriveType=3).
    Returns details including total size, free space, used space, and usage percentage
    for each drive in GB format.

.EXAMPLE
    Get-DiskInfo
    # Returns disk information for all local drives

.OUTPUTS
    PSCustomObject[] - Array of objects containing disk information for each drive
    Each object contains: DeviceID, Size, FreeSpace, UsedSpace, UsedPercent, Description
#>
function Get-DiskInfo {
    # Get disk information
    $returnArray = @()
    $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3"
    foreach ($disk in $disks) {
        $size = [math]::Round($disk.Size / 1GB)
        $freeSpace = [math]::Round($disk.FreeSpace / 1GB) 
        $usedSpace = $size - $freeSpace
        $usedPercent = [math]::Round(($usedSpace / $size) * 100)    
          
        $returnObject = [PSCustomObject]@{
            DeviceID    = $disk.DeviceID
            Size        = $size 
            FreeSpace   = $freeSpace
            UsedSpace   = $usedSpace
            UsedPercent = $usedPercent
            Description = "Disk ($($disk.DeviceID))     : ${size}GB Total, ${freeSpace}GB Free (${usedPercent}% Used)"
        }
        $returnArray += $returnObject
    }
    return $returnArray
}

<#
.SYNOPSIS
    Gets detailed information about the current user.

.DESCRIPTION
    Retrieves comprehensive information about the currently logged-in user including
    username, domain, group memberships, privileges, and administrator status.
    Displays detailed group and privilege metadata in formatted tables.

.EXAMPLE
    Get-EntraAdCurrentUserMetaInfo
    # Displays current user information with detailed group and privilege tables

.OUTPUTS
    None - Function displays information directly to the console and logs
#>
function Get-EntraAdCurrentUserMetaInfo {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    # $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

    # Get groups and privileges
    $groups = $currentUser.Groups | ForEach-Object {
        try {
            $_.Translate([System.Security.Principal.NTAccount]).Value
        }
        catch {
            $_.Value # Fallback to SID if translation fails
        }
    }
    $privileges = [System.Security.Principal.WindowsIdentity]::GetCurrent().Claims | 
    Where-Object { $_.Type -like '*right*' } |
    Select-Object -ExpandProperty Value

    $currentUserInfo = [PSCustomObject]@{
        UserName   = $currentUser.Name
        UserDomain = $currentUser.User
        Groups     = $groups
        Privileges = $privileges
        IsAdmin    = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    Write-LogMessage "Current User" -Level INFO
    $currentUser | Format-Table -AutoSize
    Write-LogMessage "Current User Group Info" -Level INFO
    $currentUserInfo | Format-Table -AutoSize


    Write-LogMessage "Related Group Metadata" -Level INFO
    $groupTable = @()
    foreach ($group in $groups) {
        $groupTable += [PSCustomObject]@{
            Name   = $group
            Type   = if ($group -match "^S-\d-\d+-\d+-\d+") { "SID" } else { "Group" }
            Domain = if ($group -match "\\") { $group.Split('\')[0] } else { "Local" }
        }
    }
    $groupTable | Format-Table -AutoSize

    $privTable = @()
    foreach ($privilege in $privileges) {
        $privTable += [PSCustomObject]@{
            Name     = $privilege
            Category = switch -Wildcard ($privilege) {
                "*SeBackup*" { "Backup" }
                "*SeDebug*" { "Debug" } 
                "*SeSystem*" { "System" }
                "*SeNetwork*" { "Network" }
                default { "Other" }
            }
        }
    }

    Get-CommonLogPath
    Write-LogMessage "Related Privilege Metadata" -Level INFO
    $privTable | Format-Table -AutoSize

    Write-LogMessage "Current User Privileges" -Level INFO
    $currentUser.Privileges | Format-Table -AutoSize

    $commonLogPath = $(Get-CommonLogPath) + "\Server\ServiceUsersMetadata"


    Write-LogMessage "Common Log Path: $commonLogPath" -Level INFO


    if (Test-IsServer) {
        # Create combined object with user and group info
        $combinedInfo = [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            UserInfo     = $currentUserInfo
            Groups       = $groupTable 
            Privileges   = $privTable
            Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        # Create filename with timestamp
        $fileName = "ServiceUserMetadata_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $outputPath = Join-Path $commonLogPath $fileName

        # Export to JSON file
        $combinedInfo | ConvertTo-Json -Depth 100 | Out-File $outputPath
        Write-LogMessage "Exported service user metadata to $outputPath" -Level INFO
    }

    #return $currentUserInfo
}




<#
.SYNOPSIS
    Gets all users that are members of a specified group.

.DESCRIPTION
    Takes a group name in domain\groupname format and returns a list of all usernames 
    that are members of that group. Displays user information in formatted tables.

.PARAMETER GroupName
    The name of the group to query in domain\groupname format.

.EXAMPLE
    Get-GroupMembers -GroupName "DOMAIN\Administrators"
    # Lists all members of the Administrators group

.OUTPUTS
    None - Function displays information directly to the console and logs
#>
function Get-GroupMembers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName
    )

    try {
        # Split domain and group name
        $domain, $group = $GroupName -split '\\'
        if (!$group) {
            throw "GroupName must be in domain\groupname format"
        }

        Write-LogMessage "Getting members for group: $GroupName" -Level INFO

        # Get group object
        $groupObj = [ADSI]"WinNT://$domain/$group,group"
        
        # Get members
        $members = @()
        $groupObj.Members() | ForEach-Object {
            $path = $_.GetType().InvokeMember("ADsPath", "GetProperty", $null, $_, $null)
            # Extract username from path
            $accountName = $path.Split('/')[-1]
            # Get additional properties where available
            try {
                $userObj = [ADSI]$path
                $members += [PSCustomObject]@{
                    Name        = $accountName
                    FullName    = $userObj.FullName.Value
                    Description = $userObj.Description.Value
                }
            }
            catch {
                # Fallback if can't get additional properties
                $members += [PSCustomObject]@{
                    Name        = $accountName
                    FullName    = ""
                    Description = ""
                }
            }
        }

        Write-LogMessage "Group Members" -Level INFO
        $members | Format-Table -AutoSize

        # Summary stats
        Write-LogMessage "Member Count: $($members.Count)" -Level INFO

    }
    catch {
        Write-LogMessage "Error getting group members: $_" -Level ERROR
        throw
    }
}
<#
.SYNOPSIS
    Removes all scheduled tasks for the current user.

.DESCRIPTION
    Removes all scheduled tasks that are configured to run under the current user account.
    This function uses schtasks.exe command to identify and remove tasks, making it
    compatible with PowerShell Core.

.PARAMETER Username
    The username for which to remove scheduled tasks. Defaults to current domain\username.

.EXAMPLE
    Remove-UserScheduledTasks
    # Removes all scheduled tasks for the current user

.EXAMPLE
    Remove-UserScheduledTasks -Username "DOMAIN\ServiceUser"
    # Removes all scheduled tasks for the specified user
#>
function Remove-UserScheduledTasks {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Username = "$env:USERDOMAIN\$env:USERNAME"
    )
    try {
        Write-LogMessage "Removing scheduled tasks for user: $Username" -Level INFO
        
        $counter = 0
        
        # Get all scheduled tasks using schtasks.exe
        $schtaskExePath = Get-CommandPathWithFallback -Name "schtasks"
        $taskOutput = & $schtaskExePath /query /fo csv /v | ConvertFrom-Csv
        
        # Filter tasks for the specified user
        $userTasks = $taskOutput | Where-Object { 
            $_.'Run As User' -eq $Username -or 
            $_.'Run As User' -eq $env:USERNAME -or
            $_.'Run As User' -eq "$env:USERDOMAIN\$env:USERNAME"
        }
        
        foreach ($task in $userTasks) {
            $taskName = $task.TaskName
            $taskPath = $task.'Task To Run'
            $runAsUser = $task.'Run As User'
            $status = $task.Status
            
            Write-LogMessage "Scheduled Task: $taskName" -Level INFO
            Write-LogMessage "Task To Run: $taskPath" -Level INFO
            Write-LogMessage "Run As User: $runAsUser" -Level INFO
            Write-LogMessage "Status: $status" -Level INFO
            
            try {
                # Remove the scheduled task using schtasks.exe
                $schtaskExePath = Get-CommandPathWithFallback -Name "schtasks"
                $result = & $schtaskExePath /delete /tn "$taskName" /f
                
                if ($LASTEXITCODE -eq 0) {
                    Write-LogMessage "Successfully removed scheduled task: $taskName" -Level WARN
                    $counter++
                }
                else {
                    Write-LogMessage "Failed to remove scheduled task: $taskName. Result: $result" -Level ERROR
                }
            }
            catch {
                Write-LogMessage "Failed to remove scheduled task: $taskName" -Level ERROR -Exception $_
            }
        }
        
        if ($counter -eq 0) {
            Write-LogMessage "No scheduled tasks found to remove for $Username" -Level INFO
        }
        else {
            Write-LogMessage "Successfully removed $counter scheduled tasks for $Username" -Level WARN
        }
    }
    catch {
        Write-LogMessage "Error removing scheduled tasks for $Username" -Level ERROR -Exception $_
    }
}


<#
.SYNOPSIS
    Updates service credentials with a new password.

.DESCRIPTION
    Updates the password for all services that run under the specified user account.
    Uses both sc.exe command and PowerShell fallback methods to ensure successful
    password updates, and attempts to restart services after credential changes.

.PARAMETER Password
    The new secure string password to set for the services.

.PARAMETER Username
    The username for which to update service passwords. Defaults to current domain\username.

.EXAMPLE
    $newPassword = Read-Host -AsSecureString "Enter new password"
    Update-ServiceCredentials -Password $newPassword
    # Updates all services running under current user with the new password

.EXAMPLE
    $securePass = ConvertTo-SecureString "NewPassword123" -AsPlainText -Force
    Update-ServiceCredentials -Password $securePass -Username "DOMAIN\ServiceUser"
    # Updates services for specific user account
#>
function Update-ServiceCredentials {
    param (
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$Password,
        [Parameter(Mandatory = $false)]
        [string]$Username = "$env:USERDOMAIN\$env:USERNAME",
        [Parameter(Mandatory = $false)]
        [string[]]$ChangeFromUserName = @()
    )
    try {

        $counter = 0
        # Get all services using that username
        $allservices = Get-CimInstance -ClassName Win32_Service 
        $services = @()
        foreach ($service in $allservices) {
            if ($service.SystemName.ToLower() -ne $env:COMPUTERNAME.ToLower().Trim()) {
                continue
            }
            
            # $jsonService = [PSCustomObject]@{
            #     Name        = if ($service.Name) { $service.Name } else { "" }
            #     DisplayName = if ($service.DisplayName) { $service.DisplayName } else { "" }
            #     StartName   = if ($service.StartName) { $service.StartName } else { "" }
            #     State       = if ($service.State) { $service.State } else { "" }
            #     SystemName  = if ($service.SystemName) { $service.SystemName } else { "" }
            #     ServiceType = if ($service.ServiceType) { $service.ServiceType } else { "" }
            #     StartMode   = if ($service.StartMode) { $service.StartMode } else { "" }
            #     ProcessId   = if ($service.ProcessId) { $service.ProcessId } else { 0 }
            #     PathName    = if ($service.PathName) { $service.PathName } else { "" }
            #     Description = if ($service.Description) { $service.Description } else { "" }
            # }
            # if ($global:LogLevel -eq "DEBUG" -or $global:LogLevel -eq "TRACE") {
            #     $jsonService | Format-List
            # }
            if (-not $service.StartName) {
                continue
            }
            if (-not $service.DisplayName.ToLower().Contains("db2")) {
                continue
            }
            
            if (-not [string]::IsNullOrWhiteSpace($ChangeFromUserName)) {
                
                foreach ($currentLoopUserName in $ChangeFromUserName) {
                    if ($currentLoopUserName.Contains("\")) {
                        $currentLoopUserNameOnly = $currentLoopUserName.Split('\')[1]
                    }
                    else {
                        $currentLoopUserNameOnly = $currentLoopUserName
                    }

                    if ([string]::IsNullOrWhiteSpace($currentLoopUserNameOnly)) {
                        continue
                    }
                    if ([string]::IsNullOrWhiteSpace($service.StartName)) {
                        continue
                    }

                    if (-not $service.StartName.ToLower().Contains($currentLoopUserNameOnly.ToLower())) {
                        continue
                    }
                    $services += $service
                    Write-LogMessage "Service: $($service.Name)" -Level INFO
                    Write-LogMessage "DisplayName: $($service.DisplayName)" -Level INFO
                    Write-LogMessage "StartName: $($service.StartName)" -Level INFO
                    Write-LogMessage "State: $($service.State)" -Level INFO
                    Write-LogMessage "Current ChangeFromUserName: $currentLoopUserNameOnly" -Level INFO -ForegroundColor Yellow
                    Write-LogMessage "New Username: $currentLoopUserNameOnly" -Level INFO -ForegroundColor Yellow
                }
            }
            else {
                $services += $service
                Write-LogMessage "Service: $($service.Name)" -Level INFO
                Write-LogMessage "DisplayName: $($service.DisplayName)" -Level INFO
                Write-LogMessage "StartName: $($service.StartName)" -Level INFO
                Write-LogMessage "State: $($service.State)" -Level INFO
                Write-LogMessage "Username: $Username" -Level INFO -ForegroundColor Yellow
            }
        }
        
       
        foreach ($service in $services) {
            Write-LogMessage "Service: $($service.Name)" -Level INFO
            Write-LogMessage "DisplayName: $($service.DisplayName)" -Level INFO
            Write-LogMessage "StartName: $($service.StartName)" -Level INFO
            Write-LogMessage "State: $($service.State)" -Level INFO
           
        
            try {
                # Convert SecureString to plain text for service update
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
                $plainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            
                # More reliable approach using sc.exe command
                $serviceName = $service.Name
                $serviceDisplayName = $service.DisplayName
                try {
                    # Try CIM method first (more reliable)
                    $cimService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'"
                    if ($cimService) {
                        if ($ChangeFromUserName.Count -gt 0) {
                            $found = $false
                            foreach ($loopUserName in $ChangeFromUserName) {
                                if ($service.StartName -and -not [string]::IsNullOrWhiteSpace($service.StartName)) {
                                    if ($loopUserName.Contains("\")) {
                                        $userNameOnly = $loopUserName.Split('\')[1]
                                    }
                                    else {
                                        $userNameOnly = $loopUserName
                                    }
                                    if ([string]::IsNullOrWhiteSpace($userNameOnly)) {
                                        continue
                                    }
                                    if ($service.StartName.ToLower().Contains($userNameOnly.ToLower())) {
                                        $targetUsername = $Username
                                        $found = $true
                                        break
                                    }
                                }
                            }
                            Write-LogMessage "Found: $found" -Level INFO -ForegroundColor Yellow
                            if (-not $found) {
                                continue
                            }
                        }
                        else {
                            $targetUsername = $Username
                        }
                        
                        # Use CIM Change method with proper parameters
                        try {
                            $changeResult = Invoke-CimMethod -InputObject $cimService -MethodName Change -Arguments @{
                                StartName     = $targetUsername
                                StartPassword = $plainTextPassword
                            }
                            $cimService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$serviceName'"
                            $cimService | Format-List

                            # Stop the service
                            $stopResult = Invoke-CimMethod -InputObject $cimService -MethodName "StopService"
                            if ($stopResult.ReturnValue -eq 0) {
                                Write-LogMessage "Service $serviceName stopped successfully" -Level INFO
                            }
                            else {
                                Write-LogMessage "Failed to stop service $serviceName. Return code: $($stopResult.ReturnValue)" -Level WARN
                            }
                            Start-Sleep -Seconds 4
                            
                            # Start the service
                            $startResult = Invoke-CimMethod -InputObject $cimService -MethodName "StartService"
                            if ($startResult.ReturnValue -eq 0) {
                                Write-LogMessage "Service $serviceName started successfully" -Level INFO
                            }
                            else {
                                Write-LogMessage "Failed to start service $serviceName. Return code: $($startResult.ReturnValue)" -Level WARN
                            }
                            Start-Sleep -Seconds 4
                      

                        }
                        catch { 
                            Write-LogMessage "CIM Change method failed with return code: $($_.Exception.Message)" -Level ERROR -Exception $_
                            throw
                        }
                        
                        # if ($changeResult.ReturnValue -eq 0) {
                        Write-LogMessage "Credentials updated successfully for service $serviceDisplayName using CIM" -Level WARN
                        # }
                        # else {
                        #     throw "CIM Change method failed with return code: $($changeResult.ReturnValue)"
                        # }
                    }
                    else {
                        throw "Service not found via CIM"
                    }
                }
                catch {
                    Write-LogMessage "CIM method failed, for service $serviceDisplayName" -Level ERROR -Exception $_
                    # try {
                    #     # Fallback to sc.exe with corrected syntax
                    #     if ($ChangeFromUserName -ne "" -and $service.StartName.ToLower().Contains($ChangeFromUserName.ToLower())) {
                    #         $result = & sc.exe config "$serviceName" obj= "$Username" password= "$plainTextPassword"
                    #     }
                    #     else {
                    #         $result = & sc.exe config "$serviceName" password= "$plainTextPassword"
                    #     }
                        
                    #     if ($result -like "*SUCCESS*") {
                    #         Write-LogMessage "Credentials updated successfully for service $serviceName using sc.exe" -Level WARN
                    #     }
                    #     else {
                    #         throw "sc.exe failed with result: $result"
                    #     }
                    # }
                    # catch {
                    #     Write-LogMessage "Failed to update credentials for service $serviceName with both methods" -Level ERROR -Exception $_
                    # }
                }
            
                # if ($result -like "*SUCCESS*") {
                #     Write-LogMessage "Password updated successfully for service $serviceName" -Level WARN
                #     $counter++
                #     # Restart the service using sc.exe
                #     try {
                #         $null = & sc.exe stop "$serviceName" | Out-Null
                #         Start-Sleep -Seconds 2  # Give the service time to stop
                #         $null = & sc.exe start "$serviceName" | Out-Null
                #         Start-Sleep -Seconds 2  # Give the service time to start

                #         # Check if service is actually running by querying status
                #         $status = & sc.exe query "$serviceName" | Out-String
                #         if ($status -match "RUNNING") {
                #             Write-LogMessage "Service $serviceName restarted successfully" -Level INFO
                #         }
                #         else {
                #             Write-LogMessage "Failed to restart service $serviceName. Result: $status" -Level WARN
                #             # Try one more time with longer delay
                #             Start-Sleep -Seconds 5
                #             $null = & sc.exe start "$serviceName" | Out-Null
                #             Start-Sleep -Seconds 5  # Give the service time to start

                #             $status = & sc.exe query "$serviceName" | Out-String
                #             if ($status -match "RUNNING") {
                #                 Write-LogMessage "Service $serviceName restarted successfully on second attempt" -Level INFO
                #             }
                #             else {
                #                 Write-LogMessage "Failed to restart service $serviceName after retry. Result: $status" -Level WARN
                #             }
                #         }
                #     }
                #     catch {
                #         Write-LogMessage "Failed to restart service $serviceName" -Level ERROR -Exception $_
                #     }
                # }
                # else {
                #     Write-LogMessage "Failed to update password for service $serviceName. Result: $result" -Level ERROR
                
                #     # Fallback to PowerShell cmdlet if sc.exe fails
                #     try {
                #         $securePassword = ConvertTo-SecureString -String $plainTextPassword -AsPlainText -Force
                #         [System.Management.Automation.PSCredential]$credential = New-Object System.Management.Automation.PSCredential ($service.StartName, $securePassword)
                #         $scriptBlock = {
                #             param($serviceName, [System.Management.Automation.PSCredential]$credential)
                #             Set-ServiceCredential -Name $serviceName -Credential $credential
                #         }
                #         $null = powershell.exe -Command $scriptBlock -Args $service.Name, $credential
                #         Write-LogMessage "Password updated successfully using fallback method for service $serviceName" -Level WARN
                #         $counter++
                #     }
                #     catch {
                #         Write-LogMessage "Failed to update password using fallback method for service $serviceName" -Level ERROR -Exception $_
                #     }
                # }
            }
            catch {
                Write-LogMessage "Error updating service password for service $serviceName" -Level ERROR -Exception $_
            }
        }
        if ($counter -eq 0) {
            Write-LogMessage "No services found to update password for $Username" -Level WARN
        }
        else {
            Write-LogMessage "Password updated successfully for $counter services, consider restarting services or rebooting the server" -Level WARN -ForegroundColor Green
        }

    }
    catch {
        Write-LogMessage "No services found to update password for $Username" -Level INFO -Exception $_
    }
}

function Get-PasswordFromKeyVault {
    <#
    .SYNOPSIS
        Retrieves a password from Azure Key Vault by secret name.
    .DESCRIPTION
        Loads keyvault-config.json, asserts Azure CLI login, and calls Get-AzureKeyVaultSecret.
        Returns the plain-text password string, or $null if the secret is not found or any
        step fails. Logs the specific failure reason.
    .PARAMETER SecretName
        The secret name to look up. Underscores are normalized to hyphens automatically.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SecretName
    )

    try {
        Import-Module AzureFunctions -Force -ErrorAction Stop
    }
    catch {
        Write-LogMessage "Key Vault: AzureFunctions module not available — $($_.Exception.Message)" -Level WARN
        return $null
    }

    $kvSecretName = ConvertTo-KeyVaultSecretName -Name $SecretName
    $kvConfigPath = Join-Path $env:OptPath "DedgePshApps\Azure-KeyVaultManager\keyvault-config.json"

    if (-not (Test-Path $kvConfigPath)) {
        Write-LogMessage "Key Vault: Config file not found at '$($kvConfigPath)'" -Level WARN
        return $null
    }

    try {
        $kvConfig = Get-Content $kvConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-LogMessage "Key Vault: Failed to parse config — $($_.Exception.Message)" -Level WARN
        return $null
    }

    $kvName = $kvConfig.defaultVault
    $kvSubId = $null
    $kvEntry = $kvConfig.vaults | Where-Object { $_.name -eq $kvName } | Select-Object -First 1
    if ($kvEntry) { $kvSubId = $kvEntry.subscriptionId }

    if ([string]::IsNullOrWhiteSpace($kvName)) {
        Write-LogMessage "Key Vault: No defaultVault configured in keyvault-config.json" -Level WARN
        return $null
    }

    try {
        Assert-AzureCliLogin
    }
    catch {
        Write-LogMessage "Key Vault: Azure CLI login failed — $($_.Exception.Message)" -Level WARN
        return $null
    }

    try {
        Write-LogMessage "Key Vault: Retrieving secret '$($kvSecretName)' from vault '$($kvName)'..." -Level INFO
        $raw = Get-AzureKeyVaultSecret -KeyVaultName $kvName -SecretName $kvSecretName -SubscriptionId $kvSubId
        $obj = $raw | ConvertFrom-Json
        if ($obj.value) {
            Write-LogMessage "Key Vault: Secret '$($kvSecretName)' retrieved successfully" -Level INFO
            return $obj.value
        }
        else {
            Write-LogMessage "Key Vault: Secret '$($kvSecretName)' exists but has no value" -Level WARN
            return $null
        }
    }
    catch {
        Write-LogMessage "Key Vault: Failed to retrieve secret '$($kvSecretName)' — $($_.Exception.Message)" -Level WARN
        return $null
    }
}

function Set-FkAdmPasswordsAsSecureStrings {
    <#
    .SYNOPSIS
        Prompts for and stores passwords for the 3 FK admin users (FKDEVADM, FKTSTADM, FKPRDADM).
    .DESCRIPTION
        Asks the user to enter the password for each of the 3 FK admin accounts and stores them
        as encrypted secure strings in User environment variables:
        - tempPwdFKDEVADM
        - tempPwdFKTSTADM
        - tempPwdFKPRDADM
        If -Force is not specified, existing passwords are skipped.
    .PARAMETER Force
        Overwrite existing stored passwords.
    #>
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $adminUsers = @("FKDEVADM", "FKTSTADM", "FKPRDADM")

    Write-LogMessage ("-" * 75) -Level INFO
    Write-LogMessage "Setting FK admin passwords as secure strings" -Level INFO
    Write-LogMessage ("-" * 75) -Level INFO

    $storedCount = 0
    foreach ($user in $adminUsers) {
        $envVarName = "tempPwd$($user)"

        if (-not $Force) {
            $existing = [Environment]::GetEnvironmentVariable($envVarName, "User")
            if (-not [string]::IsNullOrWhiteSpace($existing)) {
                Write-LogMessage "Password for $($user) already stored in $($envVarName), skipping (use -Force to overwrite)" -Level INFO
                $storedCount++
                continue
            }
        }

        $kvPassword = Get-PasswordFromKeyVault -SecretName $user
        if ([string]::IsNullOrWhiteSpace($kvPassword)) {
            Write-LogMessage "No password available for $($user) from Key Vault — skipping" -Level ERROR
            continue
        }

        try {
            $securePassword = ConvertTo-SecureString -String $kvPassword -AsPlainText -Force
            $encryptedString = ConvertFrom-SecureString -SecureString $securePassword
            [Environment]::SetEnvironmentVariable($envVarName, $encryptedString, "User")
            Write-LogMessage "Password stored for $($user) in env var $($envVarName) (from Key Vault)" -Level INFO
            $storedCount++
        }
        catch {
            Write-LogMessage "Error storing password for $($user)" -Level ERROR -Exception $_
        }
    }

    Write-LogMessage "FK admin password setup complete: $($storedCount)/$($adminUsers.Count) passwords stored" -Level INFO
}

function Get-FkAdmPasswordForServer {
    <#
    .SYNOPSIS
        Returns the FK admin password matching the environment of a given server name.
    .DESCRIPTION
        Inspects the server name for environment indicators (dev, tst, prd) and returns
        the corresponding stored password from the User environment variables:
        - dev -> tempPwdFKDEVADM
        - tst -> tempPwdFKTSTADM
        - prd -> tempPwdFKPRDADM
    .PARAMETER ServerName
        The server name to determine the environment from (e.g. "p-no1fkmprd-db").
    .PARAMETER AsPlainText
        Return the password as plain text string instead of SecureString.
    .OUTPUTS
        SecureString (default) or String (if -AsPlainText is specified).
    .EXAMPLE
        Get-FkAdmPasswordForServer -ServerName "p-no1fkmprd-db"
        # Returns SecureString for FKPRDADM

        Get-FkAdmPasswordForServer -ServerName "dedge-server" -AsPlainText
        # Returns plain text password for FKTSTADM
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        [Parameter(Mandatory = $false)]
        [switch]$AsPlainText
    )

    $serverLower = $ServerName.ToLower()

    # Determine environment from server name
    $envVarName = $null
    $userName = $null
    if ($serverLower -match "dev") {
        $envVarName = "tempPwdFKDEVADM"
        $userName = "FKDEVADM"
    }
    elseif ($serverLower -match "tst") {
        $envVarName = "tempPwdFKTSTADM"
        $userName = "FKTSTADM"
    }
    elseif ($serverLower -match "prd") {
        $envVarName = "tempPwdFKPRDADM"
        $userName = "FKPRDADM"
    }
    else {
        Write-LogMessage "Cannot determine environment from server name '$($ServerName)'. Expected name containing 'dev', 'tst' or 'prd'." -Level ERROR
        return $null
    }

    # Try local env var first (fast path)
    $encryptedString = [Environment]::GetEnvironmentVariable($envVarName, "User")
    if (-not [string]::IsNullOrWhiteSpace($encryptedString)) {
        try {
            $securePassword = ConvertTo-SecureString -String $encryptedString
            Write-LogMessage "Retrieved password for $($userName) from local env var" -Level DEBUG

            if ($AsPlainText) {
                $credential = New-Object System.Management.Automation.PSCredential($userName, $securePassword)
                return $credential.GetNetworkCredential().Password
            }
            return $securePassword
        }
        catch {
            Write-LogMessage "Error decrypting stored password for $($userName) from env var $($envVarName)" -Level ERROR -Exception $_
        }
    }

    # Fall back to Azure Key Vault
    Write-LogMessage "No local password for $($userName) — trying Key Vault" -Level WARN
    $kvPassword = Get-PasswordFromKeyVault -SecretName $userName
    if (-not [string]::IsNullOrWhiteSpace($kvPassword)) {
        $securePassword = ConvertTo-SecureString -String $kvPassword -AsPlainText -Force
        if ($AsPlainText) {
            return $kvPassword
        }
        return $securePassword
    }

    Write-LogMessage "No password available for $($userName) from env var or Key Vault" -Level ERROR
    return $null
}

<#
.SYNOPSIS
    Stores user password as an encrypted secure string in environment variables.

.DESCRIPTION
    Securely stores the current user's password as an encrypted string in the user's
    environment variables. The password is then used to update service credentials
    and scheduled task credentials automatically. Uses Windows Data Protection API 
    for encryption.

.PARAMETER Force
    If true, overwrites an existing stored password. Default is false.

.PARAMETER InputPw
    Optional plain text password to set. If not provided, prompts user securely.

.EXAMPLE
    Set-UserPasswordAsSecureString
    # Prompts for password and stores it securely

.EXAMPLE
    Set-UserPasswordAsSecureString -Force
    # Forces update of existing stored password

.OUTPUTS
    SecureString - Returns the secure string password that was stored
#>
# function Set-UserPasswordAsSecureString {
#     param (
#         [Parameter(Mandatory = $false)]
#         [string]$InputPw = $null,
#         [Parameter(Mandatory = $false)]
#         [switch]$Force,
#         [Parameter(Mandatory = $false)]
#         [string[]]$ChangeFromUserName = $null,
#         [Parameter(Mandatory = $false)]
#         [bool]$ForceUpdateServiceCredentials = $false
#     )
#     # Check if service user secure string already exists
#     if (-not $Force) {   
#         $existingPassword = [Environment]::GetEnvironmentVariable("UserPasswordAsSecureString", "User")
#         if (-not [string]::IsNullOrWhiteSpace($existingPassword)) {
#             Write-LogMessage "Service user secure string already exists for $env:USERNAME" -Level INFO
#             $existingPassword = Get-SecureStringUserPasswordAsPlainText 

#             [System.Environment]::SetEnvironmentVariable("tempPwd", $existingPassword, "User")
#             [System.Environment]::SetEnvironmentVariable("tempPwd", $existingPassword, "Machine")

#             return
#         }
#     }
#     Write-LogMessage ("-" * 75) -Level INFO
#     Write-LogMessage "Setting user password as secure string for $env:USERNAME" -Level INFO
#     Write-LogMessage ("-" * 75) -Level INFO
#     if (-not [string]::IsNullOrWhiteSpace($InputPw)) {
#         $password = ConvertTo-SecureString -String $InputPw -AsPlainText -Force
#     }
#     else {
#         $password = Read-Host -Prompt "Enter password" -AsSecureString
#     }
    
#     if ($null -ne $password -and $password.Length -ne 0) {
#         try {            
#             [System.Environment]::SetEnvironmentVariable("tempPwd", $InputPw, "User")
#             [System.Environment]::SetEnvironmentVariable("tempPwd", $InputPw, "Machine")
#             # Convert SecureString to encrypted standard string
#             $encryptedString = ConvertFrom-SecureString -SecureString $password
#             # Store the encrypted string in the environment variable
#             [Environment]::SetEnvironmentVariable("UserPasswordAsSecureString", $encryptedString, "User")
#             Write-LogMessage "Password stored for $env:USERNAME" -Level INFO
            
#             if ($ForceUpdateServiceCredentials) {
#                 Update-ServiceCredentials -Password $password -Username $username -ChangeFromUserName $ChangeFromUserName
#                 ScheduledTask-Handler\Update-ScheduledTaskCredentials -Password $password -Username $username -ChangeFromUserName $ChangeFromUserName
#             }

#         }
#         catch {
#             Write-LogMessage "Error storing password" -Level ERROR -Exception $_
#         }
#     }
#     else {
#         Write-LogMessage "No password provided" -Level ERROR
#     }
#     return $password
# }
function Set-UserPasswordAsSecureString {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Username = "",
        [Parameter(Mandatory = $false)]
        [string]$InputPw = $null,
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        [Parameter(Mandatory = $false)]
        [string[]]$ChangeFromUserName = $null,
        [Parameter(Mandatory = $false)]
        [bool]$ForceUpdateServiceCredentials = $false
    )
    if ([string]::IsNullOrWhiteSpace($Username) -or $Username.Trim().ToUpper() -eq "$env:USERNAME".Trim().ToUpper()) {
        $Username = ""
    }

    # When not forced, skip if env var already exists
    if (-not $Force) {
        $existingPassword = [Environment]::GetEnvironmentVariable("UserPasswordAsSecureString$($Username)", "User")
        if (-not [string]::IsNullOrWhiteSpace($existingPassword)) {
            Write-LogMessage "Service user secure string already exists for $Username" -Level INFO
            $existingPassword = Get-SecureStringUserPasswordAsPlainText $Username

            Remove-ItemProperty -Path "HKCU:\Environment" -Name "tempPwd$($Username)" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name "tempPwd$($Username)" -ErrorAction SilentlyContinue

            return
        }
    }

    Write-LogMessage ("-" * 75) -Level INFO
    Write-LogMessage "Setting user password as secure string for $Username" -Level INFO
    Write-LogMessage ("-" * 75) -Level INFO

    # Always try Azure Key Vault first
    $kvLookupName = if ([string]::IsNullOrWhiteSpace($Username)) { $env:USERNAME } else { $Username }
    $kvPassword = Get-PasswordFromKeyVault -SecretName $kvLookupName
    if (-not [string]::IsNullOrWhiteSpace($kvPassword)) {
        $InputPw = $kvPassword
    }

    if (-not [string]::IsNullOrWhiteSpace($InputPw)) {
        $password = ConvertTo-SecureString -String $InputPw -AsPlainText -Force
    }
    else {
        Write-LogMessage "No password from Key Vault or parameter — prompting for manual entry" -Level WARN
        $password = Read-Host -Prompt "Enter password" -AsSecureString
    }
    
    if ($null -ne $password -and $password.Length -ne 0) {
        try {            
            Remove-ItemProperty -Path "HKCU:\Environment" -Name "tempPwd$($Username)" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name "tempPwd$($Username)" -ErrorAction SilentlyContinue

            # Convert SecureString to encrypted standard string
            $encryptedString = ConvertFrom-SecureString -SecureString $password
            # Store the encrypted string in the environment variable
            [Environment]::SetEnvironmentVariable("UserPasswordAsSecureString$($Username)", $encryptedString, "User")
            Write-LogMessage "Password stored for $Username" -Level INFO
            
            if ($ForceUpdateServiceCredentials -and $Username.Trim().ToUpper() -eq "") {
                Update-ServiceCredentials -Password $password -Username $username -ChangeFromUserName $ChangeFromUserName
                ScheduledTask-Handler\Update-ScheduledTaskCredentials -Password $password -Username $username -ChangeFromUserName $ChangeFromUserName
            }

        }
        catch {
            Write-LogMessage "Error storing password" -Level ERROR -Exception $_
        }
    }
    else {
        Write-LogMessage "No password provided" -Level ERROR
    }

    return $password
}

<#
.SYNOPSIS
    Removes the stored user password from environment variables.

.DESCRIPTION
    Deletes the encrypted password stored in the user's environment variables
    by the Set-UserPasswordAsSecureString function. This removes the stored
    password for security purposes.

.EXAMPLE
    Remove-UserPasswordAsSecureString
    # Removes the stored password for the current user
#>
function Remove-UserPasswordAsSecureString {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Username = ""
    )
    if ([string]::IsNullOrWhiteSpace($Username) -or $Username.Trim().ToUpper() -eq "$env:USERNAME".Trim().ToUpper()) {
        $Username = ""
    }
    # reg.exe delete "HKCU\Environment" /v "UserPasswordAsSecureString" /f
    # if ($LASTEXITCODE -eq 0) {
    #     Write-LogMessage "User password as secure string removed for $env:USERNAME" -Level INFO
    # }
    # else {
    #     Write-LogMessage "Failed to remove user password as secure string for $env:USERNAME" -Level ERROR
    # }
    $result = Invoke-RegistryCommand -Operation "delete" -Key "HKCU\Environment" -ValueName "UserPasswordAsSecureString$($Username)" -Force -SuccessMessage "Successfully removed user password from environment" -ErrorMessage "Failed to remove user password from environment"
    # REG DELETE "HKCU\Environment" /V "UserPasswordAsSecureString" /F
    if ($result) {
        Write-LogMessage "User password as secure string removed for $Username" -Level INFO
    }
    else {
        Write-LogMessage "Failed to remove user password as secure string for $Username" -Level ERROR
    }
}

function Get-UserPasswordAsSecureString {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Username = ""
    )
    if ([string]::IsNullOrWhiteSpace($Username) -or $Username.Trim().ToUpper() -eq "$env:USERNAME".Trim().ToUpper()) {
        $Username = ""
    }
    # Try local env var first (fast path)
    $encryptedPassword = [Environment]::GetEnvironmentVariable("UserPasswordAsSecureString$($Username)", "User")
    if (-not [string]::IsNullOrWhiteSpace($encryptedPassword)) {
        try {
            $securePassword = ConvertTo-SecureString -String $encryptedPassword
            return $securePassword
        }
        catch {
            Write-LogMessage "Error decrypting stored password for $Username" -Level ERROR -Exception $_
        }
    }

    # Fall back to Azure Key Vault
    $kvLookupName = if ([string]::IsNullOrWhiteSpace($Username)) { $env:USERNAME } else { $Username }
    Write-LogMessage "No local password for '$($kvLookupName)' — trying Key Vault" -Level WARN
    $kvPassword = Get-PasswordFromKeyVault -SecretName $kvLookupName
    if (-not [string]::IsNullOrWhiteSpace($kvPassword)) {
        return (ConvertTo-SecureString -String $kvPassword -AsPlainText -Force)
    }

    Write-LogMessage "No password available for '$($kvLookupName)' from env var or Key Vault" -Level ERROR
    return $null
}

function Get-SecureStringUserPasswordAsPlainText { 
    param (
        [Parameter(Mandatory = $false)]
        [string]$Username = ""
    )
    if ([string]::IsNullOrWhiteSpace($Username) -or $Username.Trim().ToUpper() -eq "$env:USERNAME".Trim().ToUpper()) {
        $Username = ""
    }
    $securePassword = Get-UserPasswordAsSecureString $Username
    if ($null -eq $securePassword) {
        $currentUserPassword = Set-UserPasswordAsSecureString -Username $Username -Force 
        if ($null -ne $currentUserPassword) {
            # If we just set a new password, get it again as a SecureString
            $securePassword = Get-UserPasswordAsSecureString -Username $Username
            if ($null -eq $securePassword) {
                return $null
            }
        }
        else {
            return $null
        }
    }
    
    try {
        # Convert SecureString to plain text
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $plainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        return $plainTextPassword
    }
    catch {
        Write-LogMessage "Error converting password to plain text" -Level ERROR -Exception $_
        Write-LogMessage "Requesting new password..." -Level WARN
        Set-UserPasswordAsSecureString -Force
        return $null
    }
}

# function Grant-BatchLogonRight {
#     <#
#     .SYNOPSIS
#         Grants the "Log on as batch job" right to a specified user.
    
#     .DESCRIPTION
#         This function modifies the local security policy to grant the SeBatchLogonRight
#         to a specified user account. This right is required for scheduled tasks to run
#         under a user account without the interactive flag.
    
#     .PARAMETER Username
#         The username to grant the right to. Can be in the format "DOMAIN\Username" or just "Username".
    
#     .EXAMPLE
#         Grant-BatchLogonRight -Username "DOMAIN\Username"
#         Grants the "Log on as batch job" right to the specified domain user.
    
#     .EXAMPLE
#         Grant-BatchLogonRight -Username "LocalUser"
#         Grants the "Log on as batch job" right to the specified local user.
    
#     .NOTES
#         This function requires administrative privileges to run.
#     #>
#     [CmdletBinding()]
#     param (
#         [Parameter(Mandatory = $true)]
#         [string]$Username
#     )

#     # Check if running as administrator
#     $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
#     $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
#     if (-not $isAdmin) {
#         Write-LogMessage "This function requires administrative privileges. Please run PowerShell as Administrator." -Level ERROR
#         return
#     }

#     try {
#         # Export the current security policy
#         $tempFile = [System.IO.Path]::GetTempFileName()
#         Write-LogMessage "Exporting current security policy to $tempFile" -Level INFO
#         $null = secedit /export /cfg $tempFile /quiet

#         # Read the security policy file
#         $content = Get-Content -Path $tempFile -Raw
        
#         # Check if the SeBatchLogonRight line exists
#         if ($content -match "SeBatchLogonRight = (.*)") {
#             $currentSetting = $Matches[1]
            
#             # Check if the user is already in the list
#             if ($currentSetting -like "*$Username*") {
#                 Write-LogMessage "User $Username already has the 'Log on as batch job' right." -Level INFO
#                 Remove-Item -Path $tempFile -Force
#                 return
#             }
            
#             # Add the user to the existing list
#             $newSetting = "$currentSetting,$Username"
#             $content = $content -replace "SeBatchLogonRight = (.*)", "SeBatchLogonRight = $newSetting"
#         }
#         else {
#             # If the line doesn't exist, add it
#             $content += "`r`nSeBatchLogonRight = $Username"
#         }
        
#         # Write the modified content back to the file
#         Set-Content -Path $tempFile -Value $content
        
#         # Apply the updated security policy
#         Write-LogMessage "Applying updated security policy" -Level INFO
#         $null = secedit /configure /db C:\Windows\security\local.sdb /cfg $tempFile /areas USER_RIGHTS /quiet
        
#         # Clean up
#         Remove-Item -Path $tempFile -Force
        
#         Write-LogMessage "Successfully granted 'Log on as batch job' right to $Username." -Level INFO
#     }
#     catch {
#         Write-LogMessage "Failed to grant 'Log on as batch job' right" -Level ERROR -Exception $_
#         if (Test-Path -Path $tempFile) {
#             Remove-Item -Path $tempFile -Force
#         }
#     }
# }

function Grant-BatchLogonRight {
    <#
    .SYNOPSIS
        Grants the "Log on as batch job" right to a specified user.
    
    .DESCRIPTION
        This function modifies the local security policy to grant the SeBatchLogonRight
        to a specified user account. This right is required for scheduled tasks to run
        under a user account without the interactive flag.
    
    .PARAMETER Username
        The username to grant the right to. Can be in the format "DOMAIN\Username" or just "Username".
    
    .EXAMPLE
        Grant-BatchLogonRight -Username "DOMAIN\Username"
        Grants the "Log on as batch job" right to the specified domain user.
    
    .EXAMPLE
        Grant-BatchLogonRight -Username "LocalUser"
        Grants the "Log on as batch job" right to the specified local user.
    
    .NOTES
        This function requires administrative privileges to run.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Username = "$env:USERDOMAIN\$env:USERNAME"
    )
    try {
        Write-LogMessage "Starting Grant-BatchLogonRight for user: $Username" -Level DEBUG

        # Check if running as administrator
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        Write-LogMessage "Is administrator: $isAdmin" -Level DEBUG
    
        if (-not $isAdmin) {
            Write-LogMessage "This function requires administrative privileges. Please run PowerShell as Administrator." -Level ERROR
            return
        }

        # Resolve the username to SID
        Write-LogMessage "Resolving username '$Username' to SID" -Level DEBUG
        try {
            $ntAccount = New-Object System.Security.Principal.NTAccount($Username)
            $userSid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
            $userSidString = $userSid.Value
            Write-LogMessage "Resolved SID: $userSidString" -Level DEBUG
        }
        catch {
            Write-LogMessage "Failed to resolve username '$Username' to SID: $($_.Exception.Message)" -Level ERROR
            throw "Failed to resolve username '$Username' to SID. Ensure the username is in format 'DOMAIN\Username' or 'Username' for local accounts."
        }

        # Define the full path to secedit.exe
        $seceditPath = Get-CommandPathWithFallback "secedit"
        Write-LogMessage "secedit path resolved to: $seceditPath" -Level DEBUG
    
        # Check if secedit.exe exists
        if (-not (Test-Path $seceditPath)) {
            Write-LogMessage "secedit.exe not found at $seceditPath. Cannot modify security policy." -Level ERROR
            return
        }
        
        Write-LogMessage "secedit.exe found, proceeding with security policy modification" -Level DEBUG
        
        try {
            # Export the current security policy
            $tempFile = [System.IO.Path]::GetTempFileName()
            Write-LogMessage "Exporting current security policy to $tempFile" -Level INFO
        
            $exportArgs = @("/export", "/cfg", $tempFile, "/quiet")
            Write-LogMessage "Executing secedit with args: $($exportArgs -join ' ')" -Level DEBUG
            $exportResult = & $seceditPath $exportArgs
        
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "secedit export failed with exit code: $LASTEXITCODE" -Level ERROR
                throw "secedit export failed with exit code $LASTEXITCODE. Output: $exportResult"
            }
            
            Write-LogMessage "Security policy exported successfully" -Level DEBUG

            # Read the security policy file
            $content = Get-Content -Path $tempFile -Raw
            Write-LogMessage "Security policy file read, content length: $($content.Length) characters" -Level DEBUG
            
            # Check if the SeBatchLogonRight line exists
            # SeBatchLogonRight is the Windows security privilege constant that grants the "Log on as batch job" user right
            # This privilege allows a user account to log on using a batch-queue facility (like Task Scheduler)
            # It's required for running scheduled tasks, services, and other batch operations under a specific user context
            if ($content.Contains("SeBatchLogonRight")) {
                Write-LogMessage "SeBatchLogonRight section found in security policy" -Level DEBUG
                #Get line number of SeBatchLogonRight
                $splitContent = $content.Split("`r`n")
                $foundLine = ""
                foreach ($line in $splitContent) {
                    if ($line.Contains("SeBatchLogonRight")) {
                        $foundLine = $line
                        Write-LogMessage "Found SeBatchLogonRight line: $foundLine" -Level DEBUG
                        # Check if the user is already in the list
                        if ($line.Contains($userSidString)) {
                            Write-LogMessage "User $Username (SID: $userSidString) already has the 'Log on as batch job' right." -Level WARN
                            Remove-Item -Path $tempFile -Force
                            Write-LogMessage "Temporary file cleaned up" -Level DEBUG
                            return
                        }
                        break
                    }
                }
            
                Write-LogMessage "User not found in existing SeBatchLogonRight, adding to list" -Level DEBUG
                # Add the user to the existing list (comma-separated SID format with leading asterisk)
                $newLine = $foundLine + ",*$userSidString"
                $content = $content -replace [regex]::Escape($foundLine), $newLine
                Write-LogMessage "User $Username (SID: $userSidString) appended to 'Log on as batch job' right." -Level INFO -ForegroundColor Green
            }
            else {
                Write-LogMessage "SeBatchLogonRight section not found, creating new entry" -Level DEBUG
                # If the SeBatchLogonRight line doesn't exist, add it to the [Privilege Rights] section
                if ($content -match "\[Privilege Rights\]") {
                    Write-LogMessage "Found existing [Privilege Rights] section, adding SeBatchLogonRight" -Level DEBUG
                    # Insert the privilege right under the existing [Privilege Rights] section
                    $content = $content -replace "(\[Privilege Rights\])", "`$1`r`nSeBatchLogonRight = *$userSidString"
                }
                else {
                    Write-LogMessage "No [Privilege Rights] section found, creating new section" -Level DEBUG
                    # Create the [Privilege Rights] section if it doesn't exist
                    $content += "`r`n[Privilege Rights]`r`nSeBatchLogonRight = *$userSidString"
                }
                Write-LogMessage "User $Username (SID: $userSidString) added to 'Log on as batch job' right." -Level INFO -ForegroundColor Green
            }

            Write-LogMessage "Security policy content modified, writing back to file" -Level DEBUG
            # Write the modified content back to the file
            Set-Content -Path $tempFile -Value $content
        
            # Apply the updated security policy
            Write-LogMessage "Applying updated security policy" -Level INFO
            $configureArgs = @("/configure", "/db", "C:\Windows\security\local.sdb", "/cfg", $tempFile, "/areas", "USER_RIGHTS", "/quiet")
            Write-LogMessage "Executing secedit configure with args: $($configureArgs -join ' ')" -Level DEBUG
            $configureResult = & $seceditPath $configureArgs
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "Secedit configure failed with exit code $LASTEXITCODE. Output: $configureResult" -Level ERROR
                throw "secedit configure failed with exit code $LASTEXITCODE. Output: $configureResult"
            }
            
            Write-LogMessage "Security policy applied successfully" -Level DEBUG
        
            # Clean up
            Remove-Item -Path $tempFile -Force
            Write-LogMessage "Temporary file cleaned up successfully" -Level DEBUG
        }
        catch {
            Write-LogMessage "Exception occurred during security policy modification: $($_.Exception.Message)" -Level DEBUG
            Write-LogMessage "Failed to grant 'Log on as batch job' right" -Level WARN
            if (-not [string]::IsNullOrEmpty($tempFile) -and (Test-Path -Path $tempFile)) {
                Remove-Item -Path $tempFile -Force
                Write-LogMessage "Temporary file cleaned up after error" -Level DEBUG
            }
            throw $_
        }
    }
    catch {
        Write-LogMessage "Failed to grant 'Log on as batch job' right" -Level WARN -Exception $_
        throw $_
    }
}

function Grant-ServiceLogonRight {
    <#
    .SYNOPSIS
        Grants the "Log on as a service" right to a specified user.
    
    .DESCRIPTION
        This function modifies the local security policy to grant the SeServiceLogonRight
        to a specified user account. This right is required for Windows services to run
        under a specific user account context.
    
    .PARAMETER Username
        The username to grant the right to. Can be in the format "DOMAIN\Username" or just "Username".
        If not specified, defaults to the current user.
    
    .EXAMPLE
        Grant-ServiceLogonRight -Username "DOMAIN\Username"
        Grants the "Log on as a service" right to the specified domain user.
    
    .EXAMPLE
        Grant-ServiceLogonRight -Username "LocalUser"
        Grants the "Log on as a service" right to the specified local user.
    
    .EXAMPLE
        Grant-ServiceLogonRight
        Grants the "Log on as a service" right to the current user.
    
    .NOTES
        Author: Geir Helge Starholm, www.dEdge.no
        This function requires administrative privileges to run.
        Changes may require a logout/login for the user to take effect.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Username = "$env:USERDOMAIN\$env:USERNAME"
    )
    try {
        Write-LogMessage "Starting Grant-ServiceLogonRight for user: $Username" -Level DEBUG

        # Check if running as administrator
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        Write-LogMessage "Is administrator: $isAdmin" -Level DEBUG
    
        if (-not $isAdmin) {
            Write-LogMessage "This function requires administrative privileges. Please run PowerShell as Administrator." -Level ERROR
            return
        }

        # Resolve the username to SID
        Write-LogMessage "Resolving username '$Username' to SID" -Level DEBUG
        try {
            $ntAccount = New-Object System.Security.Principal.NTAccount($Username)
            $userSid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
            $userSidString = $userSid.Value
            Write-LogMessage "Resolved SID: $userSidString" -Level DEBUG
        }
        catch {
            Write-LogMessage "Failed to resolve username '$Username' to SID: $($_.Exception.Message)" -Level ERROR
            throw "Failed to resolve username '$Username' to SID. Ensure the username is in format 'DOMAIN\Username' or 'Username' for local accounts."
        }

        # Define the full path to secedit.exe
        $seceditPath = Get-CommandPathWithFallback "secedit"
        Write-LogMessage "secedit path resolved to: $seceditPath" -Level DEBUG
    
        # Check if secedit.exe exists
        if (-not (Test-Path $seceditPath)) {
            Write-LogMessage "secedit.exe not found at $seceditPath. Cannot modify security policy." -Level ERROR
            return
        }
        
        Write-LogMessage "secedit.exe found, proceeding with security policy modification" -Level DEBUG
        
        try {
            # Export the current security policy
            $tempFile = [System.IO.Path]::GetTempFileName()
            Write-LogMessage "Exporting current security policy to $tempFile" -Level INFO
        
            $exportArgs = @("/export", "/cfg", $tempFile, "/quiet")
            Write-LogMessage "Executing secedit with args: $($exportArgs -join ' ')" -Level DEBUG
            $exportResult = & $seceditPath $exportArgs
        
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "secedit export failed with exit code: $LASTEXITCODE" -Level ERROR
                throw "secedit export failed with exit code $LASTEXITCODE. Output: $exportResult"
            }
            
            Write-LogMessage "Security policy exported successfully" -Level DEBUG

            # Read the security policy file
            $content = Get-Content -Path $tempFile -Raw
            Write-LogMessage "Security policy file read, content length: $($content.Length) characters" -Level DEBUG
            
            # Check if the SeServiceLogonRight line exists
            # SeServiceLogonRight is the Windows security privilege constant that grants the "Log on as a service" user right
            # This privilege allows a user account to log on as a service (required for Windows services)
            # It's required for running Windows services, SQL Server, IIS Application Pools, and other service-based operations under a specific user context
            if ($content.Contains("SeServiceLogonRight")) {
                Write-LogMessage "SeServiceLogonRight section found in security policy" -Level DEBUG
                #Get line number of SeServiceLogonRight
                $splitContent = $content.Split("`r`n")
                $foundLine = ""
                foreach ($line in $splitContent) {
                    if ($line.Contains("SeServiceLogonRight")) {
                        $foundLine = $line
                        Write-LogMessage "Found SeServiceLogonRight line: $foundLine" -Level DEBUG
                        # Check if the user is already in the list
                        if ($line.Contains($userSidString)) {
                            Write-LogMessage "User $Username (SID: $userSidString) already has the 'Log on as a service' right." -Level WARN
                            Remove-Item -Path $tempFile -Force
                            Write-LogMessage "Temporary file cleaned up" -Level DEBUG
                            return
                        }
                        break
                    }
                }
            
                Write-LogMessage "User not found in existing SeServiceLogonRight, adding to list" -Level DEBUG
                # Add the user to the existing list (comma-separated SID format with leading asterisk)
                $newLine = $foundLine + ",*$userSidString"
                $content = $content -replace [regex]::Escape($foundLine), $newLine
                Write-LogMessage "User $Username (SID: $userSidString) appended to 'Log on as a service' right." -Level INFO -ForegroundColor Green
            }
            else {
                Write-LogMessage "SeServiceLogonRight section not found, creating new entry" -Level DEBUG
                # If the SeServiceLogonRight line doesn't exist, add it to the [Privilege Rights] section
                if ($content -match "\[Privilege Rights\]") {
                    Write-LogMessage "Found existing [Privilege Rights] section, adding SeServiceLogonRight" -Level DEBUG
                    # Insert the privilege right under the existing [Privilege Rights] section
                    $content = $content -replace "(\[Privilege Rights\])", "`$1`r`nSeServiceLogonRight = *$userSidString"
                }
                else {
                    Write-LogMessage "No [Privilege Rights] section found, creating new section" -Level DEBUG
                    # Create the [Privilege Rights] section if it doesn't exist
                    $content += "`r`n[Privilege Rights]`r`nSeServiceLogonRight = *$userSidString"
                }
                Write-LogMessage "User $Username (SID: $userSidString) added to 'Log on as a service' right." -Level INFO -ForegroundColor Green
            }

            Write-LogMessage "Security policy content modified, writing back to file" -Level DEBUG
            # Write the modified content back to the file
            Set-Content -Path $tempFile -Value $content
        
            # Apply the updated security policy
            Write-LogMessage "Applying updated security policy" -Level INFO
            $configureArgs = @("/configure", "/db", "C:\Windows\security\local.sdb", "/cfg", $tempFile, "/areas", "USER_RIGHTS", "/quiet")
            Write-LogMessage "Executing secedit configure with args: $($configureArgs -join ' ')" -Level DEBUG
            $configureResult = & $seceditPath $configureArgs
            if ($LASTEXITCODE -ne 0) {
                Write-LogMessage "Secedit configure failed with exit code $LASTEXITCODE. Output: $configureResult" -Level ERROR
                throw "secedit configure failed with exit code $LASTEXITCODE. Output: $configureResult"
            }
            
            Write-LogMessage "Security policy applied successfully" -Level DEBUG
        
            # Clean up
            Remove-Item -Path $tempFile -Force
            Write-LogMessage "Temporary file cleaned up successfully" -Level DEBUG
        }
        catch {
            Write-LogMessage "Exception occurred during security policy modification: $($_.Exception.Message)" -Level DEBUG
            Write-LogMessage "Failed to grant 'Log on as a service' right" -Level WARN
            if (-not [string]::IsNullOrEmpty($tempFile) -and (Test-Path -Path $tempFile)) {
                Remove-Item -Path $tempFile -Force
                Write-LogMessage "Temporary file cleaned up after error" -Level DEBUG
            }
            throw $_
        }
    }
    catch {
        Write-LogMessage "Failed to grant 'Log on as a service' right" -Level WARN -Exception $_
        throw $_
    }
}

<#
.SYNOPSIS
    Sets a custom desktop wallpaper with server information.

.DESCRIPTION
    Creates and sets a custom desktop wallpaper that displays comprehensive server
    information including computer name, environment, applications, hardware specs,
    disk usage, and system details. Uses a background image and overlays text
    with environment-specific colors.

.EXAMPLE
    Set-ServerInfoWallpaper
    # Sets the desktop wallpaper with current server information
#>
function Set-ServerInfoWallpaper {
    Write-LogMessage "Setting custom background with server information..." -Level INFO

    # Get system information

    $computerInfo = Get-ComputerInfo
    $computerName = $env:COMPUTERNAME
    $osName = $computerInfo.OsName
    try {
        $osCodeSet = $computerInfo.OsCodeSet.ToString()
    }
    catch {
        $osCodeSet = "N/A"
    }
    $osVersion = $computerInfo.WindowsVersion
    $totalRam = [math]::Round($computerInfo.CsTotalPhysicalMemory / 1GB)
    # Get disk information
    $diskInfo = Get-DiskInfo
    $diskText = $diskInfo.Description -join "`n"

    if ($computerInfo.CsProcessors) {
        $processorInfo = $computerInfo.CsProcessors[0].Name
    }
    else {
        $processorInfo = "N/A"
    }
    # $processorCount = $computerInfo.CsProcessors.NumberOfCores | Measure-Object -Sum
    # $threadCount = ($computerInfo.CsProcessors | Measure-Object -Property ThreadCount -Sum).Sum
    $metaData = Get-ComputerMetaData -Name $env:COMPUTERNAME
    $purpose = $metaData.Purpose
    $comments = $metaData.Comments
    $fkApplications = $metaData.Applications -join ", "
    $platform = $metaData.Platform
    $environments = @()
    try {
        $environments = $metaData.Environments -join ", "
    }
    catch {
        $environments = @("PRD")
    }
    


    # Create background text
    $bgText = ""
    $bgText += "Status date   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
    $bgText += "Computer Name : $computerName`n"
    $bgText += "Environments  : $environments`n" 
    $bgText += "Applications  : $fkApplications`n"
    $bgText += "Purpose       : $purpose`n"
    $bgText += "Platform      : $platform`n"
    if ($comments) {
        $bgText += "Comments      : $comments`n"
    }
    $bgText += "`n"

    $bgText += "OS Code Set   : $osCodeSet`n"
    $bgText += "OS Name       : $osName`n"
    $bgText += "OS Version    : $osVersion`n"
    $bgText += "RAM           : ${totalRam}GB`n"
    $bgText += "Architecture  : $($computerInfo.CsSystemType)`n"
    $bgText += "CPU           : $processorInfo `n"
    $bgText += "Physical CPUs : $($computerInfo.CsNumberOfProcessors)`n"
    $bgText += "Logical CPUs  : $($computerInfo.CsNumberOfLogicalProcessors)`n"
    $bgText += "$diskText`n"
    $bgText += "`n"
    $bgText += "Region        : $([System.Globalization.RegionInfo]::CurrentRegion.DisplayName)`n"
    $bgText += "Culture       : $([System.Globalization.CultureInfo]::CurrentCulture.DisplayName)`n"
    $bgText += "Language      : $([System.Globalization.CultureInfo]::CurrentCulture.Name)`n"
    $bgText += "Timezone      : $(Get-TimeZone).DisplayName)`n"
    $bgText += "OptPath       : $env:OptPath`n"
    $bgText += "Current User  : $($env:USERDOMAIN.ToUpper())\$($env:USERNAME.ToUpper())`n"

    # Create a bitmap with the text
    Add-Type -AssemblyName System.Drawing
    
    # Load the background image
    $backgroundPath = Join-Path $(Get-CommonPath) "Configfiles\Resources\FkBackground.png"
    try {
        $backgroundImage = [System.Drawing.Image]::FromFile($backgroundPath)
        $bitmap = New-Object System.Drawing.Bitmap($backgroundImage.Width, $backgroundImage.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        
        # Draw the background image
        $graphics.DrawImage($backgroundImage, 0, 0, $backgroundImage.Width, $backgroundImage.Height)
        
        # Configure text settings
        $font = New-Object System.Drawing.Font("Courier New", 20, [System.Drawing.FontStyle]::Bold)
        # Set brush color based on environment
        try {
            $brush = if ($env:COMPUTERNAME.ToUpper().Contains("PRD") -or $env:COMPUTERNAME.ToUpper().StartsWith("P-NO1AVD")) {
                [System.Drawing.Brushes]::White
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains("PRD") -or $env:COMPUTERNAME.ToUpper().StartsWith("P-NO1")) {
                [System.Drawing.Brushes]::Red
            }
            elseif ($env:COMPUTERNAME.ToUpper().Contains("DEV")) {
                [System.Drawing.Brushes]::White
            }
            else {
                [System.Drawing.Brushes]::Yellow
            }
        }
        catch {
            $brush = [System.Drawing.Brushes]::Yellow
        }
        
        $format = [System.Drawing.StringFormat]::new()
        $format.Alignment = [System.Drawing.StringAlignment]::Near
        $format.LineAlignment = [System.Drawing.StringAlignment]::Near
        $rect = New-Object System.Drawing.RectangleF(0, 0, $bitmap.Width, $bitmap.Height)

        # Draw text on bitmap
        $graphics.DrawString($bgText, $font, $brush, $rect, $format)

        # Save and set as wallpaper
        $wallpaperPath = "C:\TEMPFK\$($env:USERNAME)_ServerInfo.png"
        $bitmap.Save($wallpaperPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        # Cleanup resources
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        if ($backgroundImage) { $backgroundImage.Dispose() }
    }

    # Set wallpaper
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value 0
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value 1
    try {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    }
    catch {
    }
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
    [Wallpaper]::SystemParametersInfo(20, 0, $wallpaperPath, 3)



    Write-LogMessage "Background set successfully!" -Level INFO
}


function Add-NetworkDrive {
    param (
        [Parameter(Mandatory = $false)]
        [string]$DriveLetter = "Z",
        [Parameter(Mandatory = $false)]
        [string]$Path = $(Get-CommonPath),
        [Parameter(Mandatory = $false)]
        [bool]$Persistant = $true
    )
   
    if ($DriveLetter -eq "") { 
        Write-LogMessage "DriveLetter is empty" -Level WARN
        return  
    }
    if ($Path -eq "") {
        Write-LogMessage "Path is empty" -Level WARN
        return  
    }
    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-LogMessage "Path is not a valid container: $Path" -Level WARN
        return  
    }

    try {
        $command = "$env:SystemRoot\System32\net use $($DriveLetter): $Path /PERSISTENT:$Persistant"
        Write-LogMessage "Mapping drive ${DriveLetter} to $Path with command: $command" -Level INFO
        $netUseResult = Invoke-Expression $command 2>&1
        $netUseResult = $netUseResult -join "`n"

        Write-LogMessage "`nDrive $DriveLetter added successfully to $Path" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to add drive $DriveLetter to $Path" -Level WARN
    }
}



function Add-PathToEnvironmentPathVariable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
    
        [Parameter(Mandatory = $false)]
        [ValidateSet("User", "Machine")] 
        [string]$Target = "User"
    )
    $currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
    $currentMachinePath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

    # Get current path based on target
    if ($Target -eq "User") {
        $currentUserPath = Add-PathToSemicolonSeparatedVariable -Variable $currentUserPath -Path $Path
        [System.Environment]::SetEnvironmentVariable("Path", $currentUserPath, [System.EnvironmentVariableTarget]::User)
        Write-LogMessage "NewUserPath: $currentUserPath" -Level DEBUG
    }
    else {
        $currentMachinePath = Add-PathToSemicolonSeparatedVariable -Variable $currentMachinePath -Path $Path
        [System.Environment]::SetEnvironmentVariable("Path", $currentMachinePath, [System.EnvironmentVariableTarget]::Machine)
        Write-LogMessage "NewMachinePath: $currentMachinePath" -Level DEBUG
    }

    $env:Path = $currentMachinePath + ";" + $currentUserPath
    Write-LogMessage "Env:Path: $env:Path" -Level DEBUG

}

<#
.SYNOPSIS
    Removes a path from the environment PATH variable.

.DESCRIPTION
    Removes a specified path from either the user or machine environment PATH variable.
    Uses helper functions to handle semicolon-separated path management and
    updates both the environment variable and current session PATH.

.PARAMETER Path
    The path to remove from the environment PATH variable.

.PARAMETER Target
    The target scope for the environment variable. Valid values are "User" or "Machine". Default is "User".

.EXAMPLE
    Remove-PathFromEnvironmentPathVariable -Path "C:\MyApp\bin"
    # Removes C:\MyApp\bin from the user PATH variable

.EXAMPLE
    Remove-PathFromEnvironmentPathVariable -Path "C:\Tools" -Target "Machine"
    # Removes C:\Tools from the machine PATH variable
#>
function Remove-PathFromEnvironmentPathVariable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
    
        [Parameter(Mandatory = $false)]
        [ValidateSet("User", "Machine")] 
        [string]$Target = "User"
    )
    $currentUserPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
    $currentMachinePath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

    # Get current path based on target
    if ($Target -eq "User") {
        $currentUserPath = Remove-PathFromSemicolonSeparatedVariable -Variable $currentUserPath -Path $Path
        [System.Environment]::SetEnvironmentVariable("Path", $currentUserPath, [System.EnvironmentVariableTarget]::User)
        Write-LogMessage "NewUserPath: $currentUserPath" -Level DEBUG
    }
    else {
        $currentMachinePath = Remove-PathFromSemicolonSeparatedVariable -Variable $currentMachinePath -Path $Path
        [System.Environment]::SetEnvironmentVariable("Path", $currentMachinePath, [System.EnvironmentVariableTarget]::Machine)
        Write-LogMessage "NewMachinePath: $currentMachinePath" -Level DEBUG
    }
    $env:Path = $currentMachinePath + ";" + $currentUserPath
    Write-LogMessage "Env:Path: $env:Path" -Level DEBUG
}
 




function Add-PathToAllEnvironmentPathVariables {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    Write-LogMessage "Adding folder $Path to both user and machine environment path variables" -Level INFO
    if (Test-IsServer) {
        $AdditionalAdmins = @($("$env:USERDOMAIN\$env:USERNAME"), "DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere")
        Add-Folder -Path $Path -AdditionalAdmins $AdditionalAdmins -EveryonePermission "ReadAndExecute" -IsWorkstation $false
    }
    else {
        $AdditionalAdmins = @($("$env:USERDOMAIN\$env:USERNAME"))
        Add-Folder -Path $Path -AdditionalAdmins $AdditionalAdmins -EveryonePermission "ReadAndExecute" -IsWorkstation $true
    }

    Remove-PathFromEnvironmentPathVariable -Path $Path -Target "Machine"
    Write-LogMessage "Env:Path: $env:Path" -Level DEBUG
    Remove-PathFromEnvironmentPathVariable -Path $Path -Target "User"
    Write-LogMessage "Env:Path: $env:Path" -Level DEBUG
    Add-PathToEnvironmentPathVariable -Path $Path -Target "Machine"
    Write-LogMessage "Env:Path: $env:Path" -Level DEBUG
    Add-PathToEnvironmentPathVariable -Path $Path -Target "User"   
    Write-LogMessage "Env:Path: $env:Path" -Level DEBUG
}


# Add helper function for the fallback method

<#
.SYNOPSIS
    Updates service credentials using WMI.

.DESCRIPTION
    Helper function that updates service credentials using WMI Win32_Service class.
    This is used as a fallback method when the primary sc.exe command fails.
    Provides detailed error handling and return codes.

.PARAMETER Name
    The name of the service to update credentials for.

.PARAMETER Credential
    PSCredential object containing the new username and password.

.EXAMPLE
    $cred = Get-Credential
    Set-ServiceCredential -Name "MyService" -Credential $cred
    # Updates MyService with new credentials

.OUTPUTS
    Boolean - Returns $true if successful, throws exception if failed
#>
function Set-ServiceCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    try {
        $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'"
        if ($null -eq $service) {
            throw "Service '$Name' not found"
        }
        
        $username = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password
        
        $result = $service.Change($null, $null, $null, $null, $null, $null, $username, $password, $null, $null, $null)
        
        if ($result.ReturnValue -eq 0) {
            return $true
        }
        else {
            throw "Failed to update service credentials. Return code: $($result.ReturnValue)"
        }
    }
    catch {
        throw $_
    }
}

function Test-EnsureSmb2Or3Enabled {
    if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
        # Likely Windows Server

        # Disable SMB 1.0 if present
        $smb1Feature = Get-WindowsFeature -Name FS-SMB1
        if ($smb1Feature -and $smb1Feature.InstallState -eq 'Installed') {
            Write-LogMessage "Disabling insecure SMB 1.0 support..." -Level INFO
            Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction SilentlyContinue
            # For server, also remove the feature via DISM as fallback
            dism /online /disable-feature /featurename:SMB1Protocol /norestart | Out-Null
        }

        $smb2Feature = Get-WindowsFeature -Name FS-SMB2
        if ($smb2Feature -and $smb2Feature.InstallState -ne 'Installed') {
            Write-LogMessage "Enabling SMB 2.0/3.0 support (Windows Server)..." -Level INFO
            Install-WindowsFeature -Name FS-SMB2 -IncludeAllSubFeature -IncludeManagementTools -ErrorAction SilentlyContinue
        }
    }
    elseif (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
        # Likely Windows 10/11

        # Disable SMB 1.0 if present
        $smb1Feature = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -ErrorAction SilentlyContinue
        if ($smb1Feature -and $smb1Feature.State -eq 'Enabled') {
            Write-LogMessage "Disabling insecure SMB 1.0 support..." -Level INFO
            Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction SilentlyContinue
            # For server, also remove the feature via DISM as fallback
            dism /online /disable-feature /featurename:SMB1Protocol /norestart | Out-Null
        }

        $smb2Feature = Get-WindowsOptionalFeature -Online -FeatureName "SMB2Protocol" -ErrorAction SilentlyContinue
        if ($smb2Feature -and $smb2Feature.State -ne 'Enabled') {
            Write-LogMessage "Enabling SMB 2.0/3.0 support (Windows 10/11)..." -Level INFO
            Enable-WindowsOptionalFeature -Online -FeatureName "SMB2Protocol" -NoRestart -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-LogMessage "Could not determine how to enable SMB 2.0/3.0 support on this system." -Level WARN
    }
}
function Add-SmbSharedFolder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$ShareName,
        [Parameter(Mandatory = $false)]
        [string]$Description = "Shared folder created by Add-SharedFolder script",
        [Parameter(Mandatory = $false)]
        [string[]]$AdditionalAdmins = @($("$env:USERDOMAIN\$env:USERNAME"), "DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere"),
        [Parameter(Mandatory = $false)]
        [ValidateSet("Manual", "Documents", "Programs", "BranchCache", "None")]
        [string]$CachingMode = "Manual"
    )
    Test-EnsureSmb2Or3Enabled

    Import-Module SmbShare -ErrorAction Stop
    $existingShare = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
    if ($existingShare) {
        
        # Check if path, description, caching mode, and SMB access are identical
        $pathMatches = $existingShare.Path -eq $Path
        $descriptionMatches = $existingShare.Description -eq $Description
        $cachingMatches = $existingShare.CachingMode -eq $CachingMode
        
        # Get current SMB access permissions
        $currentAccess = Get-SmbShareAccess -Name $ShareName -ErrorAction SilentlyContinue
        # Example of current access object structure:
        # $currentAccess = [
        #   {
        #     AccessControlType = "Allow"
        #     AccessRight = "Full" 
        #     AccountName = "DEDGE\FKTSTADM"
        #     Name = "Db2Restore"
        #     ScopeName = "*"
        #     PSComputerName = $null
        #     CimClass = "ROOT/Microsoft/Windows/Smb:MSFT_SmbShareAccessControlEntry"
        #     CimInstanceProperties = [CimPropertiesCollection]
        #     CimSystemProperties = [CimSystemProperties]
        #   }
        # ]

        # Build expected full access users list (including current user)
        $expectedFullAccessUsers = @("DEDGE\$env:USERNAME")
        foreach ($admin in $AdditionalAdmins) {
            if (-not $admin.ToLower().Contains($env:USERNAME.ToLower())) {
                $expectedFullAccessUsers += $admin
            }
        }
        
        # Compare access permissions
        $accessMatches = $false
        if ($currentAccess) {
            # Filter for allowed full access users only (exclude denied permissions)
            $fullAccessUsers = $currentAccess | Where-Object { 
                $_.AccessControlType -eq "Allow" -and $_.AccessRight -eq "Full" 
            } | ForEach-Object { $_.AccountName }
            
            # Sort both arrays for consistent comparison
            $sortedFullAccessUsers = $fullAccessUsers | Sort-Object
            $sortedExpectedUsers = $expectedFullAccessUsers | Sort-Object
            
            $accessMatches = ($sortedFullAccessUsers.Count -eq $sortedExpectedUsers.Count) -and 
            (Compare-Object $sortedFullAccessUsers $sortedExpectedUsers -SyncWindow 0 | Measure-Object).Count -eq 0
        }
        
        if ($pathMatches -and $descriptionMatches -and $cachingMatches -and $accessMatches) {
            Write-LogMessage "SmbShare $ShareName already exists with identical path, description, caching mode, and access permissions" -Level INFO
            return $existingShare
        }
        else {
            Write-LogMessage "SmbShare $ShareName exists but configuration differs. Removing and recreating..." -Level INFO
            Write-LogMessage "Path match: $($pathMatches), Description match: $($descriptionMatches), Caching match: $($cachingMatches), Access match: $($accessMatches)" -Level TRACE
        }

    }
    else {
        Write-LogMessage "SmbShare $ShareName does not exist. Creating new share..." -Level INFO
    }

    Remove-SmbShare -Name $ShareName -Force -ErrorAction SilentlyContinue | Out-Null
    New-SmbShare -Name $ShareName -Path $Path -Description $Description -CachingMode $CachingMode -FullAccess "DEDGE\$env:USERNAME" -ErrorAction SilentlyContinue | Out-Null
    foreach ($account in $AdditionalAdmins) {
        if (-not $account.ToLower().Contains($env:USERNAME.ToLower())) {
            Grant-SmbShareAccess -Name $ShareName -AccountName $account -AccessRight Full -Force -ErrorAction SilentlyContinue
        }
    }
    $existingShare = Get-SmbShare -Name $ShareName
    Write-LogMessage "SmbSharedFolder $ShareName created successfully" -Level INFO
    return $existingShare
}

<#
.SYNOPSIS
    Creates and configures a shared folder with specified permissions.

.DESCRIPTION
    Creates a Windows SMB share with configurable permissions for specified users and groups.
    Handles both CIM and Windows API methods for share creation, sets up NTFS permissions,
    and provides comprehensive error handling and fallback mechanisms.

.PARAMETER Path
    The local path to share. Must be an existing directory.

.PARAMETER AdditionalAdmins
    Array of additional users/groups to grant full control permissions. 
    Default includes current user and FK development groups.

.PARAMETER ShareName
    The name of the share. Default is "opt".

.PARAMETER Description
    Description for the share. Default is "Shared folder created by Add-SharedFolder script".

.PARAMETER EveryonePermission
    Permission level for Everyone group. Valid values: "Read", "Change", "Full". Default is "Read".

.EXAMPLE
    Add-SharedFolder -Path "C:\Data" -ShareName "DataShare"
    # Creates a share named "DataShare" for C:\Data with default permissions

.EXAMPLE
    Add-SharedFolder -Path "C:\Apps" -AdditionalAdmins @("DOMAIN\DevTeam") -EveryonePermission "Change"
    # Creates share with custom admin group and change permissions for everyone
#>
function Add-SharedFolder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [string[]]$AdditionalAdmins = @($("$env:USERDOMAIN\$env:USERNAME"), "DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere"),
        [Parameter(Mandatory = $false)]
        [string]$ShareName = "opt",
        [Parameter(Mandatory = $false)]
        [string]$Description = "Shared folder created by Add-SharedFolder script",
        [Parameter(Mandatory = $false)]
        [ValidateSet(
            # Basic Permissions
            "Read",
            "ReadAndExecute", 
            "Write",
            "WriteAndRead",
            "ReadWriteExecute",
            "Change",
            "Modify",
            "Full",
            "FullControl",
            
            # Granular Permissions
            "ReadData",
            "WriteData",
            "AppendData",
            "CreateFiles",
            "CreateDirectories",
            "Delete",
            "DeleteSubdirectoriesAndFiles",
            "Execute",
            "Traverse",
            "ReadPermissions",
            "ChangePermissions",
            "TakeOwnership",
            
            # Common Combinations
            "ReadOnly",
            "WriteOnly",
            "ListFolder",
            "CreateFilesOnly",
            "NoAccess",
            
            # SMB-specific
            "ReadWrite",
            "WriteOnly",
            # None
            ""
        )]
        [string]$EveryonePermission = "Read"
    )

    # Check if running on Windows
    if (-not $IsWindows -and -not $env:OS -like "*Windows*") {
        Write-Error "This script requires Windows to manage SMB shares."
        exit 1
    }

    if ($ShareName -eq "") { 
        throw "ShareName is empty"
    }

    # Write-Host "Parameters:" -ForegroundColor Green
    # Write-Host "Path: $Path" -ForegroundColor Yellow
    # Write-Host "ShareName: $ShareName" -ForegroundColor Yellow 
    # Write-Host "EveryonePermission: $EveryonePermission" -ForegroundColor Yellow

    # Write-Host "`nAdditional Admins:" -ForegroundColor Green
    # foreach ($admin in $AdditionalAdmins) {
    #     Write-Host $admin -ForegroundColor Yellow
    # }
    # Write-Host ""

    # Add C# code for share management
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class ShareManagement {
    [DllImport("netapi32.dll", SetLastError = true)]
    public static extern int NetShareAdd(
        [MarshalAs(UnmanagedType.LPWStr)] string servername,
        int level,
        IntPtr buf,
        out int parm_err);

    [DllImport("netapi32.dll", SetLastError = true)]
    public static extern int NetShareDel(
        [MarshalAs(UnmanagedType.LPWStr)] string servername,
        [MarshalAs(UnmanagedType.LPWStr)] string netname,
        int reserved);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SHARE_INFO_2 {
        [MarshalAs(UnmanagedType.LPWStr)]
        public string shi2_netname;
        public uint shi2_type;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string shi2_remark;
        public uint shi2_permissions;
        public uint shi2_max_uses;
        public uint shi2_current_uses;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string shi2_path;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string shi2_passwd;
    }

    public const uint STYPE_DISKTREE = 0;
    public const uint ACCESS_ALL = 0;
}
"@

    try {
        # Check if the path exists
        $DrivePath = $Path
        if (-not (Test-Path -Path $DrivePath -PathType Container)) {
            throw "The specified path does not exist: $DrivePath"
        }

        # Check for existing share using CIM
        $existingShare = Get-CimInstance -ClassName Win32_Share -Filter "Name='$ShareName'" -ErrorAction SilentlyContinue

        if ($existingShare) {
            Write-Warning "Share '$ShareName' already exists. Removing existing share..."
        
            # Try using CIM first
            try {
                $existingShare | Remove-CimInstance -ErrorAction Stop
            }
            catch {
                # Fall back to C# implementation
                $result = [ShareManagement]::NetShareDel($null, $ShareName, 0)
                if ($result -ne 0) {
                    throw "Failed to remove existing share. Error code: $result"
                }
            }
        }

        # Create the share
        Write-Host "Creating share '$ShareName' for path '$DrivePath'..."
    
        # Try using CIM first
        try {
            $cimMethodParams = @{
                Name        = $ShareName
                Path        = $DrivePath
                Description = $Description
                Type        = [uint32]0  # Disk Drive - explicitly cast to uint32
            }
        
            Invoke-CimMethod -ClassName Win32_Share -MethodName Create -Arguments $cimMethodParams | Out-Null
        }
        catch {
            # Fall back to C# implementation
            $shareInfo = New-Object ShareManagement+SHARE_INFO_2
            $shareInfo.shi2_netname = $ShareName
            $shareInfo.shi2_type = [ShareManagement]::STYPE_DISKTREE
            $shareInfo.shi2_remark = $Description
            $shareInfo.shi2_permissions = [ShareManagement]::ACCESS_ALL
            $shareInfo.shi2_max_uses = [uint32]::MaxValue
            $shareInfo.shi2_path = $DrivePath
            $shareInfo.shi2_passwd = $null

            $bufferSize = [System.Runtime.InteropServices.Marshal]::SizeOf($shareInfo)
            $buffer = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($bufferSize)
            [System.Runtime.InteropServices.Marshal]::StructureToPtr($shareInfo, $buffer, $false)

            $paramErr = 0
            $result = [ShareManagement]::NetShareAdd($null, 2, $buffer, [ref]$paramErr)
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)

            if ($result -ne 0) {
                throw "Failed to create share. Error code: $result, Parameter Error: $paramErr"
            }
        }

        # Remove inheritance and preserve inherited permissions
        $acl = Get-Acl -Path $DrivePath
        $acl.SetAccessRuleProtection($true, $true)
        Set-Acl -Path $DrivePath -AclObject $acl

        # Convert AdditionalAdmins to array of PSObjects and add default users
        $userPermissions = @()

        # Add default users
        if ($EveryonePermission -and (-not [string]::IsNullOrEmpty($EveryonePermission))) {
            $userPermissions += [PSCustomObject]@{
                User        = "Everyone"
                Permissions = $EveryonePermission
            }
        }

        # Add additional admins
        foreach ($admin in $AdditionalAdmins) {
            $userPermissions += [PSCustomObject]@{
                User        = $admin
                Permissions = "Full"
            }
        }
    
        # Add permissions for each domain user
        foreach ($singleUserPermission in $userPermissions) {
            Write-Host "Adding $($singleUserPermission.Permissions) permissions for user: $($singleUserPermission.User)"
            
            # Use only the direct Windows API method that works reliably
            try {
                # Define the required P/Invoke signatures (requires admin rights)
                Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;

public class SharePermissions
{
    // Constants
    private const int NERR_Success = 0;
    
    [DllImport("netapi32.dll", CharSet = CharSet.Unicode)]
    private static extern int NetShareSetInfo(
        [MarshalAs(UnmanagedType.LPWStr)] string servername,
        [MarshalAs(UnmanagedType.LPWStr)] string netname,
        int level,
        IntPtr buf,
        out int parm_err);
        
    [DllImport("netapi32.dll")]
    private static extern int NetApiBufferFree(IntPtr Buffer);
    
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHARE_INFO_502
    {
        [MarshalAs(UnmanagedType.LPWStr)]
        public string shi502_netname;
        public int shi502_type;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string shi502_remark;
        public int shi502_permissions;
        public int shi502_max_uses;
        public int shi502_current_uses;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string shi502_path;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string shi502_passwd;
        public int shi502_reserved;
        public IntPtr shi502_security_descriptor;
    }
    
    public static int SetShareInfo(string shareName, string remark, int permissions)
    {
        IntPtr buffer = IntPtr.Zero;
        int parm_err = 0;
        
        try
        {
            // Create a SHARE_INFO_502 struct
            SHARE_INFO_502 shi502 = new SHARE_INFO_502();
            
            // Fill in the share info fields
            shi502.shi502_netname = shareName;
            shi502.shi502_type = 0; // STYPE_DISKTREE
            shi502.shi502_remark = remark;
            shi502.shi502_permissions = permissions;
            shi502.shi502_max_uses = -1;
            shi502.shi502_current_uses = 0;
            shi502.shi502_path = null;
            shi502.shi502_passwd = null;
            shi502.shi502_reserved = 0;
            shi502.shi502_security_descriptor = IntPtr.Zero;
            
            // Allocate memory and marshal the struct
            buffer = Marshal.AllocHGlobal(Marshal.SizeOf(shi502));
            Marshal.StructureToPtr(shi502, buffer, false);
            
            // Call NetShareSetInfo
            return NetShareSetInfo(null, shareName, 502, buffer, out parm_err);
        }
        finally
        {
            // Free the allocated memory
            if (buffer != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
    }
}
"@
                # Set permissions using the Windows API
                $permissions = switch ($singleUserPermission.Permissions) {
                    # Basic Permissions
                    "Read" { 1 }   # Read access only
                    "ReadAndExecute" { 1 }   # Read access (SMB doesn't distinguish execute)
                    "Write" { 2 }   # Write access only (rare, usually combined)
                    "WriteAndRead" { 3 }   # Read + Write access (same as Change)
                    "ReadWriteExecute" { 3 }   # Read + Write access (same as Change)
                    "Change" { 3 }   # Read + Write access
                    "Modify" { 3 }   # Read + Write access (same as Change)
                    "Full" { 7 }   # Full control (Read + Write + Change permissions)
                    "FullControl" { 7 }   # Full control (same as Full)
                    
                    # Granular Permissions (map to closest SMB equivalent)
                    "ReadData" { 1 }   # Read access
                    "WriteData" { 2 }   # Write access
                    "AppendData" { 2 }   # Write access
                    "CreateFiles" { 2 }   # Write access
                    "CreateDirectories" { 2 }   # Write access
                    "Delete" { 3 }   # Change access (includes delete)
                    "DeleteSubdirectoriesAndFiles" { 3 }   # Change access
                    "Execute" { 1 }   # Read access (SMB doesn't have separate execute)
                    "Traverse" { 1 }   # Read access
                    "ReadPermissions" { 1 }   # Read access
                    "ChangePermissions" { 7 }   # Full control
                    "TakeOwnership" { 7 }   # Full control
                    
                    # Common Combinations
                    "ReadOnly" { 1 }   # Read access
                    "WriteOnly" { 2 }   # Write access
                    "ListFolder" { 1 }   # Read access
                    "CreateFilesOnly" { 2 }   # Write access
                    "NoAccess" { 0 }   # No access
                    
                    # SMB-specific
                    "ReadWrite" { 3 }   # Same as Change - Read + Write
                    
                    default { 1 }   # Default to Read
                }
                
                $result = [SharePermissions]::SetShareInfo($ShareName, $Description, $permissions)
                
                if ($result -eq 0) {
                    Write-Host "  Share permissions set successfully using Windows API" -ForegroundColor Green
                }
                else {
                    throw "Failed to set share permissions. Error code: $result"
                }
            }
            catch {
                Write-Warning "  Failed to set share permissions: $_"
                Write-Host "  You may need to set permissions manually using Computer Management" -ForegroundColor Yellow
                Write-Host "  Open Computer Management > System Tools > Shared Folders > Shares" -ForegroundColor Yellow
                Write-Host "  Right-click on $ShareName > Properties > Share Permissions" -ForegroundColor Yellow
            }
        
            # Add NTFS permission (this is separate from share permissions)
            $acl = Get-Acl -Path $DrivePath
            $rights = switch ($singleUserPermission.Permissions) {
                # Basic Permissions
                "Read" { [System.Security.AccessControl.FileSystemRights]::Read }
                "ReadAndExecute" { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute }
                "Write" { [System.Security.AccessControl.FileSystemRights]::Write }
                "WriteAndRead" { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Write }
                "ReadWriteExecute" { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Write }
                "Change" { [System.Security.AccessControl.FileSystemRights]::Modify }
                "Modify" { [System.Security.AccessControl.FileSystemRights]::Modify }
                "Full" { [System.Security.AccessControl.FileSystemRights]::FullControl }
                "FullControl" { [System.Security.AccessControl.FileSystemRights]::FullControl }
                
                # Granular NTFS Permissions
                "ReadData" { [System.Security.AccessControl.FileSystemRights]::ReadData }
                "WriteData" { [System.Security.AccessControl.FileSystemRights]::WriteData }
                "AppendData" { [System.Security.AccessControl.FileSystemRights]::AppendData }
                "CreateFiles" { [System.Security.AccessControl.FileSystemRights]::CreateFiles }
                "CreateDirectories" { [System.Security.AccessControl.FileSystemRights]::CreateDirectories }
                "Delete" { [System.Security.AccessControl.FileSystemRights]::Delete }
                "DeleteSubdirectoriesAndFiles" { [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles }
                "Execute" { [System.Security.AccessControl.FileSystemRights]::ExecuteFile }
                "Traverse" { [System.Security.AccessControl.FileSystemRights]::Traverse }
                "ReadPermissions" { [System.Security.AccessControl.FileSystemRights]::ReadPermissions }
                "ChangePermissions" { [System.Security.AccessControl.FileSystemRights]::ChangePermissions }
                "TakeOwnership" { [System.Security.AccessControl.FileSystemRights]::TakeOwnership }
                
                # Common Combinations
                "ReadOnly" { [System.Security.AccessControl.FileSystemRights]::Read }
                "WriteOnly" { [System.Security.AccessControl.FileSystemRights]::Write }
                "ListFolder" { [System.Security.AccessControl.FileSystemRights]::ListDirectory }
                "CreateFilesOnly" { [System.Security.AccessControl.FileSystemRights]::CreateFiles -bor [System.Security.AccessControl.FileSystemRights]::WriteData }
                "NoAccess" { $null }   # Will be handled specially below
                
                # SMB-specific mapped to NTFS equivalents
                "ReadWrite" { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Write }
                
                default { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute }
            }
            
            # Handle special case for NoAccess
            if ($singleUserPermission.Permissions -eq "NoAccess") {
                # Skip adding any permissions for NoAccess
                Write-Host "  Skipping NTFS permissions for NoAccess setting" -ForegroundColor Yellow
            }
            else {
                $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
                $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
                $type = [System.Security.AccessControl.AccessControlType]::Allow

                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($singleUserPermission.User, $rights, $inheritanceFlags, $propagationFlags, $type)
                $acl.AddAccessRule($accessRule)
                Set-Acl -Path $DrivePath -AclObject $acl
            }
        }

        Write-Host "`nShare created successfully!" -ForegroundColor Green
        Write-Host "Share Name: \\$($env:COMPUTERNAME)\$ShareName"
    }
    catch {
        Write-Error "Failed to create share: $_"
    }
}
function Remove-SharedFolder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ShareName
    )
    try {
        # Check if the share exists
        $existingShare = Get-CimInstance -ClassName Win32_Share -Filter "Name='$ShareName'" -ErrorAction SilentlyContinue
        
        if ($existingShare) {
            Write-Host "Removing share '$ShareName'..."
        
            # Try using CIM first
            try {
                $existingShare | Remove-CimInstance -ErrorAction Stop
            }
            catch {
                # Fall back to C# implementation    
                $result = [ShareManagement]::NetShareDel($null, $ShareName, 0)
                if ($result -ne 0) {
                    throw "Failed to remove share. Error code: $result"
                }
            }
        }   
        Write-Host "Share '$ShareName' removed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to remove share: $_"
    }   
}

function Test-NetworkRoute {
    param (
        [Parameter(Mandatory = $true)]
        [string]$HostName,
        [Parameter(Mandatory = $false)]
        [int]$MaxHops = 30,
        [Parameter(Mandatory = $false)]
        [int]$Timeout = 1000
    )

    Write-LogMessage "Testing network route to $HostName" -Level INFO
    Write-LogMessage "Using tracert command for detailed hop information..." -Level INFO

    # First try tracert command
    try {
        $tracertOutput = tracert -d -h $MaxHops -w $Timeout $HostName
        Write-LogMessage "Tracert Results:" -Level INFO
        $tracertOutput | ForEach-Object { Write-LogMessage $_ -Level INFO }
    }
    catch {
        Write-LogMessage "Tracert failed: $_" -Level ERROR
    }

    Write-LogMessage "`nUsing Test-NetConnection for additional details..." -Level INFO

    # Then use Test-NetConnection for additional details
    try {
        $testResult = Test-NetConnection -ComputerName $HostName -TraceRoute
        Write-LogMessage "Test-NetConnection Results:" -Level INFO
        Write-LogMessage "Remote Address: $($testResult.RemoteAddress)" -Level INFO
        Write-LogMessage "Interface Alias: $($testResult.InterfaceAlias)" -Level INFO
        Write-LogMessage "Source Address: $($testResult.SourceAddress)" -Level INFO
        Write-LogMessage "Ping Succeeded: $($testResult.PingSucceeded)" -Level INFO
        Write-LogMessage "Ping Reply Details:" -Level INFO
        Write-LogMessage "Round Trip Time: $($testResult.PingReplyDetails.RoundTripTime) ms" -Level INFO
        Write-LogMessage "Status: $($testResult.PingReplyDetails.Status)" -Level INFO
    }
    catch {
        Write-LogMessage "Test-NetConnection failed: $_" -Level ERROR
    }
}

<#
.SYNOPSIS
    Finds DNS names associated with an IP address.

.DESCRIPTION
    Performs reverse DNS lookups using multiple methods to find hostnames
    associated with an IP address. Checks standard DNS, PTR records,
    local hosts file, and DNS cache for comprehensive results.

.PARAMETER IpAddress
    The IP address to resolve to DNS names.

.PARAMETER IncludeLocal
    Whether to include local hosts file in the search. Default is true.

.EXAMPLE
    Get-DnsNamesForIp -IpAddress "8.8.8.8"
    # Finds DNS names for Google's public DNS server

.EXAMPLE
    Get-DnsNamesForIp -IpAddress "192.168.1.1" -IncludeLocal $false
    # Finds DNS names without checking local hosts file

.OUTPUTS
    String[] - Array of DNS names found, or $null if none found
#>
function Get-DnsNamesForIp {
    param (
        [Parameter(Mandatory = $true)]
        [string]$IpAddress,
        [Parameter(Mandatory = $false)]
        [bool]$IncludeLocal = $true
    )

    Write-LogMessage "Finding DNS names for IP address: $IpAddress" -Level INFO
    
    $results = @()
    
    try {
        # Method 1: Standard reverse DNS lookup
        Write-LogMessage "Performing standard reverse DNS lookup..." -Level INFO
        $hostEntry = [System.Net.Dns]::GetHostEntry($IpAddress)
        if ($hostEntry) {
            $results += $hostEntry.HostName
            $results += $hostEntry.Aliases
        }
    }
    catch {
        Write-LogMessage "Standard reverse DNS lookup failed: $_" -Level WARN
    }

    # Method 2: Using nslookup for PTR record
    try {
        Write-LogMessage "Checking PTR record using nslookup..." -Level INFO
        $nslookupOutput = nslookup -type=PTR $IpAddress 2>&1
        $ptrRecord = $nslookupOutput | Where-Object { $_ -match "name\s*=\s*(.+)" } | ForEach-Object { $matches[1] }
        if ($ptrRecord) {
            $results += $ptrRecord
        }
    }
    catch {
        Write-LogMessage "PTR record lookup failed: $_" -Level WARN
    }

    # Method 3: Check local hosts file if IncludeLocal is true
    if ($IncludeLocal) {
        Write-LogMessage "Checking local hosts file..." -Level INFO
        $hostsFile = "$env:windir\System32\drivers\etc\hosts"
        if (Test-Path $hostsFile) {
            $hostsContent = Get-Content $hostsFile
            $hostsContent | Where-Object { $_ -match "^[^#].*\s+$IpAddress\s+(.+)$" } | ForEach-Object {
                $hostName = $matches[1].Trim()
                $results += $hostName
            }
        }
    }

    # Method 4: Check DNS cache
    try {
        Write-LogMessage "Checking DNS cache..." -Level INFO
        $dnsCache = Get-DnsClientCache | Where-Object { $_.Data -eq $IpAddress }
        if ($dnsCache) {
            $results += $dnsCache.HostName
        }
    }
    catch {
        Write-LogMessage "DNS cache check failed: $_" -Level WARN
    }

    # Remove duplicates and empty entries
    $uniqueResults = $results | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique

    if ($uniqueResults) {
        Write-LogMessage "Found the following DNS names:" -Level INFO
        $uniqueResults | ForEach-Object { Write-LogMessage "$_" -Level INFO }
        return $uniqueResults
    }
    else {
        Write-LogMessage "No DNS names found for IP address $IpAddress" -Level WARN
        return $null
    }
}

<#
.SYNOPSIS
    Renames properties in an array of objects.

.DESCRIPTION
    Modifies the property names of objects in an array by replacing old property names 
    with new ones. Supports both exact matching and partial matching with wildcards.

.PARAMETER InputObject
    The array of objects whose properties need to be renamed.

.PARAMETER OldName
    The current name of the property to rename.

.PARAMETER NewName
    The new name for the property.

.PARAMETER PartialMatch
    If specified, performs partial matching using wildcards on the property name.

.EXAMPLE
    $objects | Rename-ArrayPropertyName -OldName "OldProp" -NewName "NewProp"
    # Renames "OldProp" to "NewProp" in all objects

.EXAMPLE
    $objects | Rename-ArrayPropertyName -OldName "Temp" -NewName "Final" -PartialMatch
    # Renames any property containing "Temp" to replace "Temp" with "Final"

.OUTPUTS
    Object[] - Returns the modified array of objects with renamed properties
#>
function Rename-ArrayPropertyName {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$InputObject,
        
        [Parameter(Mandatory = $true)]
        [string]$OldName,
        
        [Parameter(Mandatory = $true)] 
        [string]$NewName,
        
        [Parameter(Mandatory = $false)]
        [switch]$PartialMatch
    )
    
    foreach ($obj in $InputObject) {
        # Get all properties that need to be renamed
        $propertiesToRename = $obj | Get-Member -MemberType NoteProperty | 
        Where-Object { 
            if ($PartialMatch) {
                $_.Name -like "*$OldName*"
            }
            else {
                $_.Name -eq $OldName
            }
        }
        
        # Rename each matching property
        foreach ($property in $propertiesToRename) {
            $oldPropertyName = $property.Name
            $newPropertyName = if ($PartialMatch) {
                $oldPropertyName.Replace($OldName, $NewName)
            }
            else {
                $NewName
            }
            
            # Get the value before removing the old property
            $propertyValue = $obj.$oldPropertyName
            
            # Remove old property and add new one
            $obj.PSObject.Properties.Remove($oldPropertyName)
            $obj | Add-Member -NotePropertyName $newPropertyName -NotePropertyValue $propertyValue
        }
    }
    
    return $InputObject
}

# <#
# .SYNOPSIS
#     Converts the stored secure string password to plain text.

# .DESCRIPTION
#     Retrieves the stored user password and converts it from SecureString to plain text.
#     If no password is stored, prompts the user to set one. This function is used
#     internally by other functions that need the password in plain text format.

# .EXAMPLE
#     $plainPassword = Get-SecureStringUserPasswordAsPlainText
#     # Gets the stored password as plain text

# .OUTPUTS
#     String - The password in plain text, or $null if unavailable
# #>
# function Get-SecureStringUserPasswordAsPlainText {
#     $securePassword = Get-UserPasswordAsSecureString
#     if ($null -eq $securePassword) {
#         $currentUserPassword = Set-UserPasswordAsSecureString -Force 
#         if ($null -ne $currentUserPassword) {
#             # If we just set a new password, get it again as a SecureString
#             $securePassword = Get-UserPasswordAsSecureString
#             if ($null -eq $securePassword) {
#                 return $null
#             }
#         }
#         else {
#             return $null
#         }
#     }
    
#     try {
#         # Convert SecureString to plain text
#         $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
#         $plainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
#         [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
#         return $plainTextPassword
#     }
#     catch {
#         Write-LogMessage "Error converting password to plain text" -Level ERROR -Exception $_
#         Write-LogMessage "Requesting new password..." -Level WARN
#         Set-UserPasswordAsSecureString -Force
#         return $null
#     }
# }

# <#
# .SYNOPSIS
#     Retrieves the stored user password as a secure string.

# .DESCRIPTION
#     Gets the encrypted password stored in the user's environment variables
#     and converts it back to a SecureString object. The password must have been
#     previously stored using Set-UserPasswordAsSecureString.

# .EXAMPLE
#     $securePassword = Get-UserPasswordAsSecureString
#     # Retrieves the stored password as a SecureString

# .OUTPUTS
#     SecureString - The decrypted password, or $null if no password is stored
# #>
# function Get-UserPasswordAsSecureString {
#     $encryptedPassword = [Environment]::GetEnvironmentVariable("UserPasswordAsSecureString", "User")
#     if (-not [string]::IsNullOrWhiteSpace($encryptedPassword)) {
#         try {
#             # Convert the encrypted string back to a SecureString
#             $securePassword = ConvertTo-SecureString -String $encryptedPassword
#             return $securePassword
#         }
#         catch {
#             Write-LogMessage "Error retrieving stored password" -Level ERROR -Exception $_
#             return $null
#         }
#     }
#     else {
#         Write-LogMessage "No password stored for $env:USERNAME" -Level ERROR  
#         return $null
#     }
# }

<#
.SYNOPSIS
    Creates Windows shortcuts for server shared folders.

.DESCRIPTION
    Generates Windows Explorer shortcuts for shared folders on active servers based on
    server configuration data. Creates organized shortcuts by environment, platform,
    and application, checking for actual folder existence before creating shortcuts.

.EXAMPLE
    Update-ServerShorcuts
    # Creates shortcuts for all active server shared folders
#>
function Update-ServerShorcuts {
    param(
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = "$env:OptPath\ServerShortcuts"
    )
    $result = Get-ComputerInfoJson 
    #$serverInfos = $result | Where-Object { $_.Platform -eq "Azure" -and $_.IsActive -eq $true -and $_.Type.ToLower().Contains("server") }
    $serverInfos = $result | Where-Object { $_.IsActive -eq $true -and $_.Type.ToLower().Contains("server") -and $_.PSObject.Properties.Name -contains "ServiceUserName" }

    $applications = Get-ApplicationsJson
    $potentialSharedFolders = @("opt", "Db2Restore", "TEMPFK", "COBMIG", "COBSIT", "COBVFT", "COBVFK", "WKAKT", "COBNT", "COBTST", "COBDEV", "COBPRD")
    foreach ($appItem in $applications) {
        foreach ($envItem in $appItem.Environments) {
            $potentialSharedFolders += @("$($appItem.ApplicationCode)$($envItem.EnvironmentCode)")
        }
    }

    $copyToFolderAfterCompletion = ""
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $shortcutFolder = Join-Path $(Get-CommonPath) "ServerShortcuts" 
    }
    else {
        $shortcutFolder = $OutputPath
        $copyToFolderAfterCompletion = Join-Path $(Get-CommonPath) "ServerShortcuts" 
    }


    # Remove existing shortcuts
    if (Test-Path $shortcutFolder -PathType Container) {
        Get-ChildItem -Path $shortcutFolder -Recurse | Remove-Item -Force -Recurse
        Write-LogMessage "Removed existing shortcuts from $shortcutFolder" -Level INFO
    }
    else {
        New-Item -ItemType Directory -Path $shortcutFolder -Force | Out-Null
        Write-LogMessage "Created new shortcut folder $shortcutFolder" -Level INFO
    }
    $allShortcuts = @()

    foreach ($serverInfo in $serverInfos) {
        $basefolder = "\\" + $serverInfo.Name + "\"
        $actualFolders = @()
        foreach ($potentialSharedFolder in $potentialSharedFolders) {
            $testFolder = $basefolder + $potentialSharedFolder
            if (Test-Path $testFolder -PathType Container) {
                $actualFolders += $testFolder
                Write-LogMessage "Folder $testFolder exists" -Level INFO
            }
            else {
                Write-LogMessage "Folder $testFolder does not exist" -Level WARN
            }
        }

        $newShortcutAllFolder = $shortcutFolder + "\All"
        if ( -not (Test-Path $newShortcutAllFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $newShortcutAllFolder -Force | Out-Null
        }
        foreach ($actualFolder in $actualFolders) {
            $shortcutName = $($serverInfo.Name.ToLower() + " - " + $actualFolder.Split("\")[-1].ToUpper() + ".lnk")
            $shortcutPath = $newShortcutAllFolder + "\" + $shortcutName
            $programPath = "explorer.exe"
            $argument = $actualFolder
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $programPath
            $shortcut.Arguments = $argument
            $shortcut.WorkingDirectory = $($shortcutFolder)
            $shortcut.IconLocation = "explorer.exe,0"
            $shortcut.Save()
            $allShortcuts += [PSCustomObject]@{
                Name             = $shortcutName
                Path             = $shortcutPath
                ProgramPath      = $programPath
                Arguments        = $argument
                WorkingDirectory = $($shortcutFolder)
                IconLocation     = "explorer.exe,0"
                Server           = $serverInfo.Name
                Environment      = $actualFolder.Split("\")[-1].ToUpper()
                Folder           = $actualFolder.Split("\")[-1].ToUpper()
            }   
            # Release COM object to prevent memory leaks
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
            # Handle environments
            foreach ($envItem in $appItem.Environments) {
                $newShortcutEnvFolder = $shortcutFolder + "\Environments\" + $envItem.EnvironmentCode
                if (-not (Test-Path $newShortcutEnvFolder -PathType Container)) {
                    New-Item -ItemType Directory -Path $newShortcutEnvFolder -Force | Out-Null
                }
                $shortcutName = $($serverInfo.Name.ToLower() + " - " + $actualFolder.Split("\")[-1].ToUpper() + ".lnk")
                $newShortcutPath = $newShortcutEnvFolder + "\" + $shortcutName
                if ( -not (Test-Path $newShortcutPath -PathType Leaf)) {
                    Copy-Item -Path $shortcutPath -Destination $newShortcutPath 
                    $allShortcuts += [PSCustomObject]@{
                        Name             = $shortcutName
                        Path             = $shortcutPath
                        ProgramPath      = $programPath
                        Arguments        = $argument
                        WorkingDirectory = $($shortcutFolder)
                        IconLocation     = "explorer.exe,0"
                        Server           = $serverInfo.Name
                        Environment      = $actualFolder.Split("\")[-1].ToUpper()
                        Folder           = $actualFolder.Split("\")[-1].ToUpper()
                    }   
                }
            }
            # Handling Platforms
            $newShortcutPlatformFolder = $shortcutFolder + "\Platforms\" + $serverInfo.Platform
            if (-not (Test-Path $newShortcutPlatformFolder -PathType Container)) {
                New-Item -ItemType Directory -Path $newShortcutPlatformFolder -Force | Out-Null
            }
            $shortcutName = $($serverInfo.Name.ToLower() + " - " + $actualFolder.Split("\")[-1].ToUpper() + ".lnk")
            $newShortcutPath = $newShortcutPlatformFolder + "\" + $shortcutName
            if ( -not (Test-Path $newShortcutPath -PathType Leaf)) {
                Copy-Item -Path $shortcutPath -Destination $newShortcutPath 
                $allShortcuts += [PSCustomObject]@{
                    Name             = $shortcutName
                    Path             = $shortcutPath
                    ProgramPath      = $programPath
                    Arguments        = $argument
                    WorkingDirectory = $($shortcutFolder)
                    IconLocation     = "explorer.exe,0"
                    Server           = $serverInfo.Name
                    Environment      = $actualFolder.Split("\")[-1].ToUpper()
                    Folder           = $actualFolder.Split("\")[-1].ToUpper()
                }   
            }
        
            Write-LogMessage "Shortcut saved to $shortcutPath)" -Level INFO         

            # Handling Application Environment
            foreach ($appItem in $serverInfo.Applications) {
                $newShortcutApplicationFolder = $shortcutFolder + "\Application\" + $appItem
                if (-not (Test-Path $newShortcutApplicationFolder -PathType Container)) {
                    New-Item -ItemType Directory -Path $newShortcutApplicationFolder -Force | Out-Null
                }
                # Handle environments
                foreach ($envItem in $serverInfo.Environments) {
                    $newShortcutEnvFolder = $newShortcutApplicationFolder + "\" + $envItem
                    if (-not (Test-Path $newShortcutEnvFolder -PathType Container)) {
                        New-Item -ItemType Directory -Path $newShortcutEnvFolder -Force | Out-Null
                    }
                    $shortcutName = $($serverInfo.Name.ToLower() + " - " + $actualFolder.Split("\")[-1].ToUpper() + ".lnk")
                    $newShortcutPath = $newShortcutEnvFolder + "\" + $shortcutName
                    if ( -not (Test-Path $newShortcutPath -PathType Leaf)) {
                        Copy-Item -Path $shortcutPath -Destination $newShortcutPath 
                        $allShortcuts += [PSCustomObject]@{
                            Name             = $shortcutName
                            Path             = $shortcutPath
                            ProgramPath      = $programPath
                            Arguments        = $argument
                            WorkingDirectory = $($shortcutFolder)
                            IconLocation     = "explorer.exe,0"
                            Server           = $serverInfo.Name
                            Environment      = $actualFolder.Split("\")[-1].ToUpper()
                            Folder           = $actualFolder.Split("\")[-1].ToUpper()
                        }   
                    }
                }
          
            }
            Write-LogMessage "Shortcut saved to $shortcutPath)" -Level INFO         
        }

        # $jsonOutputPath = Join-Path $(Get-ApplicationDataPath) "ShortcutInfo.json"
        # if (-not (Test-Path $jsonOutputPath -PathType Leaf)) {
        #     # Get previous shortcuts
        #     $previousShortcuts = Get-Content -Path $jsonOutputPath -Raw | ConvertFrom-Json
        #     if ($null -ne $previousShortcuts) {
        #         if ($previousShortcuts -eq $allShortcuts) {
        #             Write-LogMessage "No changes to shortcuts for $($serverInfo.Name)" -Level INFO
        #         }
        #         else {
        #             Write-LogMessage "Changes to shortcuts for $($serverInfo.Name)" -Level INFO
        #         }
        #     }
        # }

     
    }
    if (-not [string]::IsNullOrWhiteSpace($copyToFolderAfterCompletion)) {
        robocopy $shortcutFolder $copyToFolderAfterCompletion /MIR /R:3 /W:1
        Write-LogMessage "Copied shortcuts to $copyToFolderAfterCompletion" -Level INFO
    }
    Write-LogMessage "Finished creating shortcuts for $($serverInfo.Name)" -Level INFO
    return $allShortcuts
}

function Connect-NetworkDrives {
    param(
        [Parameter(Mandatory = $false)]
        [PsCustomObject[]]$Drives = @(@{ Letter = "A"; Path = $(Get-CommonPath) })
    )
    Write-Host "Kobler til nettverksstasjoner..." -NoNewline
    try {
       
        foreach ($drive in $drives) {
            if (-not (Test-Path -Path "$($drive.Letter):")) {
                Add-NetworkDrive -DriveLetter $drive.Letter -Path $drive.Path -Persistant $true
            }
        }
        Write-Host " Vellykket!" -ForegroundColor Green
        Write-ApplicationLog -AppName "Network Setup" -Status "Success" -Message "Network drives mapped successfully"
    }
    catch {
        Write-Host " Mislyktes: $($_.Exception.Message)$(if($_.Exception.InnerException){" $($_.Exception.InnerException.Message)"})" -ForegroundColor Red
        Write-ApplicationLog -AppName "Network Setup" -Status "Failed" -Message "Failed to map network drives: $_"
    }
}

function Add-CommonNetworkDrives {   
    Connect-NetworkDrives -Drives @(
        @{ Letter = "A"; Path = $(Get-CommonPath) },
        @{ Letter = "F"; Path = "\\DEDGE.fk.no\Felles" },
        @{ Letter = "K"; Path = "\\DEDGE.fk.no\erputv\Utvikling" },
        @{ Letter = "N"; Path = "\\DEDGE.fk.no\erpprog" },
        @{ Letter = "R"; Path = "\\DEDGE.fk.no\erpdata" }
    )
    Write-LogMessage "Common drives mapped for $env:COMPUTERNAME" -Level INFO
}

function Invoke-RegistryCommand {
    <#
    .SYNOPSIS
        Executes registry operations using native PowerShell methods with proper error handling and logging.
    
    .DESCRIPTION
        This function provides a wrapper around PowerShell registry cmdlets with standardized
        error handling and logging capabilities. Uses native PowerShell methods instead of reg.exe.
    
    .PARAMETER Operation
        The registry operation to perform (add, delete, query, get)
    
    .PARAMETER Key
        The registry key path (e.g., "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run")
    
    .PARAMETER ValueName
        The name of the registry value (optional for some operations)
    
    .PARAMETER ValueType
        The type of registry value (String, DWord, QWord, Binary, MultiString, ExpandString)
    
    .PARAMETER ValueData
        The data to store in the registry value
    
    .PARAMETER Force
        Force the operation (overwrites existing values)
    
    .PARAMETER SuccessMessage
        Custom success message for logging
    
    .PARAMETER ErrorMessage
        Custom error message for logging
    
    .EXAMPLE
        Invoke-RegistryCommand -Operation "add" -Key "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ValueName "Map-Drv" -ValueType "String" -ValueData "$env:OptPath\DedgePshApps\Map-CommonNetworkDrives\Map-Drv.bat" -Force -SuccessMessage "Successfully added Map-Drv.bat to user startup registry" -ErrorMessage "Failed to add Map-Drv.bat to user startup registry"
    
    .EXAMPLE
        Invoke-RegistryCommand -Operation "delete" -Key "HKCU:\Environment" -ValueName "UserPasswordAsSecureString" -Force -SuccessMessage "Successfully removed user password from environment" -ErrorMessage "Failed to remove user password from environment"
    
    .NOTES
        This function requires appropriate permissions for the registry operations being performed.
        Uses native PowerShell registry cmdlets for better integration and error handling.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("add", "delete", "query", "get")]
        [string]$Operation,
        
        [Parameter(Mandatory = $true)]
        [string]$Key,
        
        [Parameter(Mandatory = $false)]
        [string]$ValueName,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("String", "DWord", "QWord", "Binary", "MultiString", "ExpandString", "REG_SZ", "REG_EXPAND_SZ", "REG_DWORD", "REG_QWORD", "REG_BINARY", "REG_MULTI_SZ", "REG_NONE", "REG_LINK", "REG_RESOURCE_LIST", "REG_FULL_RESOURCE_DESCRIPTOR", "REG_RESOURCE_REQUIREMENTS_LIST", "REG_QWORD_LITTLE_ENDIAN", "REG_DWORD_LITTLE_ENDIAN", "REG_DWORD_BIG_ENDIAN", "REG_LINK_LITTLE_ENDIAN", "REG_FULL_RESOURCE_DESCRIPTOR_LITTLE_ENDIAN", "REG_RESOURCE_REQUIREMENTS_LIST_LITTLE_ENDIAN", "REG_QWORD_LITTLE_ENDIAN", "REG_DWORD_LITTLE_ENDIAN", "REG_DWORD_BIG_ENDIAN", "REG_LINK_LITTLE_ENDIAN", "REG_FULL_RESOURCE_DESCRIPTOR_LITTLE_ENDIAN", "REG_RESOURCE_REQUIREMENTS_LIST_LITTLE_ENDIAN")]
        [string]$ValueType = "String",
        
        [Parameter(Mandatory = $false)]
        [string]$ValueData,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        
        [Parameter(Mandatory = $false)]
        [string]$SuccessMessage = "Registry operation completed successfully",
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = "Registry operation failed"
        ,
        [Parameter(Mandatory = $false)]
        [switch]$IgnoreError
    )

    try {
        Write-LogMessage "Starting registry operation: $Operation" -Level DEBUG
        
        # Convert reg.exe style key paths to PowerShell registry paths
        $psKey = $Key
        Write-LogMessage "Original key: $Key" -Level DEBUG
        
        if ($Key.StartsWith("HKCU\")) {
            $psKey = $Key.Replace("HKCU\", "HKCU:\")
        }
        elseif ($Key.StartsWith("HKLM\")) {
            $psKey = $Key.Replace("HKLM\", "HKLM:\")
        }
        elseif ($Key.StartsWith("HKCR\")) {
            $psKey = $Key.Replace("HKCR\", "HKCR:\")
        }
        elseif ($Key.StartsWith("HKU\")) {
            $psKey = $Key.Replace("HKU\", "HKU:\")
        }
        elseif ($Key.StartsWith("HKCC\")) {
            $psKey = $Key.Replace("HKCC\", "HKCC:\")
        }
        else {
            Write-LogMessage "Key does not match expected registry hive patterns" -Level DEBUG
            if (-not $IgnoreError) {
                Write-LogMessage "Invalid registry key: $Key" -Level ERROR
            }
            return $false
        }
        
        Write-LogMessage "Converted PowerShell key: $psKey" -Level DEBUG
        
        # Convert the ValueType to a PowerShell registry type
        $originalValueType = $ValueType
        $ValueType = switch ($ValueType) {
            "String" { "String" }
            "DWord" { "DWord" }
            "QWord" { "QWord" }
            "Binary" { "Binary" }
            "MultiString" { "MultiString" }
            "ExpandString" { "ExpandString" }
            "REG_SZ" { "String" }
            "REG_DWORD" { "DWord" }
            "REG_QWORD" { "QWord" }
            "REG_BINARY" { "Binary" }
            "REG_MULTI_SZ" { "MultiString" }
            "REG_EXPAND_SZ" { "ExpandString" }
            default { $ValueType }
        }
        
        Write-LogMessage "ValueType conversion: $originalValueType -> $ValueType" -Level DEBUG

        Write-LogMessage "Registry operation: $Operation on $psKey$(if($ValueName){" value $ValueName"})" -Level INFO

        switch ($Operation.ToLower()) {
            "add" {
                Write-LogMessage "Executing ADD operation" -Level DEBUG
                
                # Ensure the registry key exists
                if (-not (Test-Path -Path $psKey)) {
                    Write-LogMessage "Registry key does not exist, creating: $psKey" -Level DEBUG
                    New-Item -Path $psKey -Force | Out-Null
                    Write-LogMessage "Created registry key: $psKey" -Level INFO
                }
                else {
                    Write-LogMessage "Registry key already exists: $psKey" -Level DEBUG
                }

                if ($ValueName) {
                    Write-LogMessage "Setting registry value: $ValueName = $ValueData (Type: $ValueType)" -Level DEBUG
                    
                    # Add or update a registry value
                    $setItemParams = @{
                        Path  = $psKey
                        Name  = $ValueName
                        Value = $ValueData
                        Type  = $ValueType
                    }
                    Write-LogMessage "SetItemParams: $($setItemParams | ConvertTo-Json -Compress)" -Level TRACE
                    if ($Force) {
                        $setItemParams.Force = $true
                        Write-LogMessage "Force parameter enabled for registry operation" -Level DEBUG
                    }

                    Set-ItemProperty @setItemParams
                    Write-LogMessage "Set registry value: ${psKey}\$ValueName = $ValueData" -Level INFO
                }
                else {
                    Write-LogMessage "No ValueName specified, only ensuring key exists" -Level DEBUG
                    # Just create the key if no value name specified
                    if (-not (Test-Path -Path $psKey)) {
                        New-Item -Path $psKey -Force | Out-Null
                    }
                }
            }

            "delete" {
                Write-LogMessage "Executing DELETE operation" -Level DEBUG
                
                if ($ValueName) {
                    Write-LogMessage "Attempting to delete registry value: ${psKey}\$ValueName" -Level DEBUG
                    
                    # Delete a specific registry value
                    if (Get-ItemProperty -Path $psKey -Name $ValueName -ErrorAction SilentlyContinue) {
                        Write-LogMessage "Registry value exists, proceeding with deletion" -Level DEBUG
                        Remove-ItemProperty -Path $psKey -Name $ValueName -Force:$Force
                        Write-LogMessage "Deleted registry value: ${psKey}\$ValueName" -Level INFO
                    }
                    else {
                        Write-LogMessage "Registry value not found for deletion: ${psKey}\$ValueName" -Level DEBUG
                        Write-LogMessage "Registry value not found: ${psKey}\$ValueName" -Level WARN
                        return $false
                    }
                }
                else {
                    Write-LogMessage "Attempting to delete entire registry key: $psKey" -Level DEBUG
                    
                    # Delete the entire registry key
                    if (Test-Path -Path $psKey) {
                        Write-LogMessage "Registry key exists, proceeding with deletion" -Level DEBUG
                        Remove-Item -Path $psKey -Recurse -Force:$Force
                        Write-LogMessage "Deleted registry key: $psKey" -Level INFO
                    }
                    else {
                        Write-LogMessage "Registry key not found for deletion: $psKey" -Level DEBUG
                        if (-not $IgnoreError) {
                            Write-LogMessage "Registry key not found: $psKey" -Level WARN
                            return $false
                        }
                    }
                }
            }

            { $_ -in @("query", "get") } {
                Write-LogMessage "Executing QUERY/GET operation" -Level DEBUG
                
                if ($ValueName) {
                    Write-LogMessage "Querying specific registry value: ${psKey}\$ValueName" -Level DEBUG
                    
                    # Query a specific registry value
                    $value = Get-ItemProperty -Path $psKey -Name $ValueName -ErrorAction SilentlyContinue
                    if ($value) {
                        Write-LogMessage "Registry value found and retrieved successfully" -Level DEBUG
                        Write-LogMessage "Registry value ${psKey}\$ValueName = $($value.$ValueName)" -Level INFO
                        return $value.$ValueName
                    }
                    else {
                        Write-LogMessage "Registry value not found during query: ${psKey}\$ValueName" -Level DEBUG
                        Write-LogMessage "Registry value not found: ${psKey}\$ValueName" -Level WARN
                        return $null
                    }
                }
                else {
                    Write-LogMessage "Querying all values in registry key: $psKey" -Level DEBUG
                    
                    # Query all values in the registry key
                    if (Test-Path -Path $psKey) {
                        Write-LogMessage "Registry key exists, retrieving all properties" -Level DEBUG
                        $properties = Get-ItemProperty -Path $psKey
                        Write-LogMessage "Registry key contents for ${psKey}:" -Level INFO
                        $properties | Format-List | Out-String | ForEach-Object { Write-LogMessage $_ -Level INFO }
                        return $properties
                    }
                    else {
                        Write-LogMessage "Registry key not found during query: $psKey" -Level DEBUG
                        Write-LogMessage "Registry key not found: $psKey" -Level WARN
                        return $null
                    }
                }
            }
        }

        Write-LogMessage "Registry operation completed successfully" -Level DEBUG
        Write-LogMessage $SuccessMessage -Level INFO
        return $true
    }
    catch {
        if (-not $IgnoreError) {
            Write-LogMessage "$ErrorMessage. Exception: $_" -Level ERROR -Exception $_
        }
        return $false
    }
}


function Add-BatchLogonRights {
    
    $usernameArray = @("$env:USERDOMAIN\srverp13", "$env:USERDOMAIN\$env:USERNAME")
    if ($env:COMPUTERNAME.ToUpper().Contains('PRD')) {
        $usernameArray += @("$env:USERDOMAIN\FKPRDADM")
    }
    elseif ($env:COMPUTERNAME.ToUpper().Contains('TST')) {
        $usernameArray += @("$env:USERDOMAIN\FKTSTADM")
    }
    elseif ($env:COMPUTERNAME.ToUpper().Contains('DEV')) {
        $usernameArray += @("$env:USERDOMAIN\FKDEVADM")
    }


    foreach ($username in $usernameArray) {
        # Check if Infrastructure module is available and has the Grant-BatchLogonRight function
        if (Get-Command -Name Grant-BatchLogonRight -ErrorAction SilentlyContinue) {
            Write-LogMessage "Ensuring user $username has 'Log on as batch job' rights..." -Level INFO
            Grant-BatchLogonRight -Username $username
        }
        else {
            Write-LogMessage "Warning: Grant-BatchLogonRight function not available. User $username may need 'Log on as batch job' rights." -Level ERROR
        }
    }
}

function Get-AllPowerShellVariablesAsMarkdownFile {
    # Export all PowerShell global variables to JSON file
    $globalVars = [PSCustomObject]@{}
    foreach ($var in Get-Variable -Scope Global) {
        try {
            # Skip automatic variables and complex objects that can't be serialized
            #  if ($var.Name -notmatch '^(Error|Host|Home|PID|PWD|ShellId|ExecutionContext|PSVersionTable|PROFILE|PSCommandPath|PSScriptRoot|MyInvocation|StackTrace|PSBoundParameters|args|input|LastExitCode|Matches|NestedPromptLevel|OutputEncoding|PSCulture|PSUICulture|PSDefaultParameterValues|PSEmailServer|PSModuleAutoLoadingPreference|PSSessionApplicationName|PSSessionConfigurationName|PSSessionOption|VerbosePreference|WarningPreference|ErrorActionPreference|ProgressPreference|DebugPreference|InformationPreference|WhatIfPreference|ConfirmPreference)$') {
            $globalVars | Add-Member -MemberType NoteProperty -Name $var.Name -Value $var.Value
            # }
        }
        catch {
            # Skip variables that can't be serialized
            $globalVars | Add-Member -MemberType NoteProperty -Name $var.Name -Value "[Cannot serialize: $($_.Exception.Message)]"
        }
    }
    $globalVars | Add-Member -MemberType NoteProperty -Name 'Timestamp' -Value (Get-Date).ToString('o')
 
    #search for all variables that contain the word "SoftwareDownloader"
    $softwareDownloaderVars = $globalVars | Where-Object { $_.Name -like "*SoftwareDownloader*" }
    $softwareDownloaderVars | Out-String | Set-Content -Path (Join-Path $PSScriptRoot "PowerShell-GlobalVars-SoftwareDownloader.raw") -Force
    Write-LogMessage "SoftwareDownloader variables exported to: $(Join-Path $PSScriptRoot "PowerShell-GlobalVars-SoftwareDownloader.raw")" -Level DEBUG



















    # Export as markdown file with breadcrumbs and line breaks
    $markdownPath = Join-Path $PSScriptRoot "PowerShell-GlobalVars.md"
    $markdownContent = @()

    # Add header
    $markdownContent += "# PowerShell Global Variables Export"
    $markdownContent += "**Timestamp:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $markdownContent += ""

    # Function to recursively process objects and create breadcrumbs
    function Add-ObjectToMarkdown {
        param(
            [Parameter(Mandatory = $true)]
            $Object,
            [Parameter(Mandatory = $false)]
            [string]$Breadcrumb = "",
            [Parameter(Mandatory = $false)]
            [int]$Level = 1
        )
    
        $content = @()
    
        if ($Object -is [PSCustomObject] -or $Object -is [hashtable]) {
            # Handle PSCustomObject or hashtable
            $properties = if ($Object -is [PSCustomObject]) { $Object.PSObject.Properties } else { $Object.GetEnumerator() }
        
            foreach ($property in $properties) {
                $propName = if ($Object -is [PSCustomObject]) { $property.Name } else { $property.Key }
                $propValue = if ($Object -is [PSCustomObject]) { $property.Value } else { $property.Value }
            
                # Skip null values
                if ($null -eq $propValue) { continue }
            
                $currentBreadcrumb = if ($Breadcrumb) { "$Breadcrumb > $propName" } else { $propName }
                $headingLevel = "#" * ($Level + 1)
            
                if ($propValue -is [PSCustomObject] -or $propValue -is [hashtable] -or $propValue -is [array]) {
                    # Add heading for complex objects
                    $content += "$headingLevel $propName"
                    $content += ""
                
                    # Recursively process complex objects
                    $content += Add-ObjectToMarkdown -Object $propValue -Breadcrumb $currentBreadcrumb -Level ($Level + 1)
                }
                else {
                    # Add simple property
                    $content += "$headingLevel $propName"
                    $content += '```'
                    $content += $propValue
                    $content += '```'
                    $content += ""
                }
            }
        }
        elseif ($Object -is [array]) {
            # Handle arrays
            for ($i = 0; $i -lt $Object.Count; $i++) {
                $item = $Object[$i]
            
                # Skip null values
                if ($null -eq $item) { continue }
            
                $currentBreadcrumb = if ($Breadcrumb) { "$Breadcrumb > [$i]" } else { "[$i]" }
                $headingLevel = "#" * ($Level + 1)
            
                if ($item -is [PSCustomObject] -or $item -is [hashtable] -or $item -is [array]) {
                    # Add heading for complex array items
                    $content += "$headingLevel Item [$i]"
                    $content += ""
                
                    # Recursively process complex array items
                    # Check recursion depth to prevent call depth overflow
                    if ($Level -lt 100) {
                        $content += Add-ObjectToMarkdown -Object $item -Breadcrumb $currentBreadcrumb -Level ($Level + 1)
                    }
                    else {
                        $content += "... (max recursion depth reached)"
                    }
                }
                else {
                    # Add simple array item
                    $content += "$headingLevel Item [$i]"
                    $content += '```'
                    $content += $item
                    $content += '```'
                    $content += ""
                }
            }
        }
        else {
            # Handle simple values
            $content += '```'
            $content += $Object
            $content += '```'
            $content += ""
        }
    
        return $content
    }

    # Group variables by type/category for breadcrumbs
    $variableGroups = @{
        "System Variables" = @()
        "Path Variables"   = @()
        "User Variables"   = @()
        "Module Variables" = @()
        "Other Variables"  = @()
    }

    # Track already exported variable names to avoid duplicates
    $exportedVariableNames = @{}

    # Iterate through each property in $globalVars PSObject
    foreach ($property in $globalVars.PSObject.Properties) {
        if ($property.Name -eq 'Timestamp') { continue }
    
        $varName = $property.Name
        $varValue = $property.Value
    
        # Skip null values
        if ($null -eq $varValue) { continue }


        # For simple types (string, int, etc.), write directly to markdown
        if ($varValue -is [string] -or $varValue -is [int] -or $varValue -is [double] -or $varValue -is [bool] -or $varValue -is [datetime]) {
            $markdownContent += "### $varName"
            $markdownContent += '```'
            $markdownContent += "[$($varValue.GetType().Name)]$varName=$varValue"
            $markdownContent += '```'
            $markdownContent += ""
        }
        else {
            # For complex types, use the detailed object processing
            $markdownContent += Add-ObjectToMarkdown -Object $varValue -Breadcrumb $varName -Level 2
        }
    

        # Skip if variable name has already been exported
        if ($exportedVariableNames.ContainsKey($varName)) { continue }
    
        # Mark this variable name as exported
        $exportedVariableNames[$varName] = $true
    }

    # Generate markdown content with breadcrumbs for each group
    foreach ($groupName in $variableGroups.Keys) {
        if ($variableGroups[$groupName].Count -gt 0) {
            $markdownContent += "## $groupName"
            $markdownContent += ""
        
            # Iterate through each variable in the group
            foreach ($var in $variableGroups[$groupName]) {
                $markdownContent += Add-ObjectToMarkdown -Object $var.Value -Breadcrumb $var.Name -Level 2
            }
        }
    }

    # Write markdown file
    $markdownContent | Set-Content -Path $markdownPath -Force
    Write-LogMessage "Global variables exported to markdown: $markdownPath" -Level DEBUG
}

function Add-Db2UserToDb2admns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )
    try {
        Add-LocalGroupMember -Group DB2ADMNS -member "$env:USERDOMAIN\$UserName" -ErrorAction SilentlyContinue
    }
    catch {
        Write-LogMessage "$($_.Exception.Message)" -Level WARN
    }
}
function Remove-Db2UserFromDb2admns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )
    try {
        Remove-LocalGroupMember -Group DB2ADMNS -member "$env:USERDOMAIN\$UserName" -ErrorAction SilentlyContinue
    }
    catch {
        Write-LogMessage "$($_.Exception.Message)" -Level WARN
    }
}
function Add-Db2UserToDb2users {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )
    try {
        Add-LocalGroupMember -Group DB2USERS -member "$env:USERDOMAIN\$UserName" -ErrorAction SilentlyContinue
    }
    catch {
        Write-LogMessage "$($_.Exception.Message)" -Level WARN
    }
}
function Remove-Db2UserFromDb2users {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )
    try {
        Remove-LocalGroupMember -Group DB2USERS -member "$env:USERDOMAIN\$UserName" -ErrorAction SilentlyContinue
    }
    catch {
        Write-LogMessage "$($_.Exception.Message)" -Level WARN
    }
}


function Set-NoIndexingForRcFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [bool]$IgnoreError = $true
    )
    # Other services that can lock files besides Windows Defender:
    # - Antivirus software (Norton, McAfee, Avast, etc.)
    # - File sync services (Dropbox, OneDrive, Google Drive)
    # - Search indexing services (Windows Search)
    # - Backup software (Windows Backup, Veeam, etc.)
    # - Source control systems (Git, SVN)
    # - IDE file watchers (Visual Studio, VS Code)
    # - Database services that memory map files
    # - System file monitoring tools
    # - File compression services
    # - Document management systems
    # - File sharing services (SMB, FTP, etc.)
    # - Cloud storage services (Amazon S3, Azure Blob Storage)
    # - Virtual machine file systems
    # - Docker container file systems
    # - Network file systems (NFS, CIFS)
    # - Virtual file systems (WSL, Docker)
    # - File system virtualization tools
  
  
    try {
        $paths = @(
            "\\DEDGE.fk.no\erpprog\cobnt",
            "\\DEDGE.fk.no\erpprog\cobtst", 
            "\\DEDGE.fk.no\erpprog\cobnt",
            "\\DEDGE.fk.no\erputv\Utvikling\fkavd\nt",
            "\\DEDGE.fk.no\erpprog\cobtst\COBMIG",
            "\\DEDGE.fk.no\erpprog\cobtst\COBSIT",
            "\\DEDGE.fk.no\erpprog\cobtst\COBVFT",
            "\\DEDGE.fk.no\erpprog\cobtst\COBVFK"
        )
        foreach ($path in $paths) {
            $attribCommand = "attrib +I +S `"$path\*.rc`""
            $result = Start-Process "cmd.exe" -ArgumentList "/c", $attribCommand -NoNewWindow -Wait -PassThru
            if ($result.ExitCode -ne 0) {
                Write-LogMessage "Failed to set no-indexing attribute. Exit code: $($result.ExitCode)" -Level ERROR
                if (-not $IgnoreError) {
                    throw "Failed to set no-indexing attribute"
                }
            }
            else {
                Write-LogMessage "Successfully set no-indexing attribute for *.rc files in $path" -Level INFO
            }
        }
    }
    catch {
        if (-not $IgnoreError) {
            Write-LogMessage "Error setting no-indexing attribute: $_" -Level ERROR -Exception $_
            throw
        }
    }
}

function Start-EscapeStringForCmd {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputString
    )
    #return $InputString.Replace("^", "^^").Replace("&", "^&").Replace("|", "^|").Replace("<", "^<").Replace(">", "^>").Replace("%", "^%").Replace("`"", "^""").Replace("(", "^(").Replace(")", "^)").Replace(",", "^,").Replace(";", "^;").Replace("=", "^=").Replace("[", "^[").Replace("]", "^]").Replace("{", "^{").Replace("}", "^}")
    $replacements = @(
        #@{Old="^"; New="^^"},
        @{Old = "&"; New = "^&" },
        @{Old = "|"; New = "^|" },
        @{Old = "<"; New = "^<" },
        @{Old = ">"; New = "^>" },
        #@{Old="%"; New="^%"},
        @{Old = "`""; New = "^""" },
        @{Old = "("; New = "^(" },
        @{Old = ")"; New = "^)" },
        @{Old = ","; New = "^," },
        @{Old = ";"; New = "^;" },
        @{Old = "="; New = "^=" },
        @{Old = "["; New = "^[" },
        @{Old = "]"; New = "^]" },
        @{Old = "{"; New = "^{" },
        @{Old = "}"; New = "^}" }
    )
    $escapedString = $InputString
    foreach ($pair in $replacements) {
        $escapedString = $escapedString.Replace($pair.Old, $pair.New)
    }
    return $escapedString
}
  
<#
.SYNOPSIS
    Configures FK administrative user credentials and sets up server environment.

.DESCRIPTION
    This script configures FK administrative users based on the server environment (PRD, TST, DEV).
    It performs the following operations:
    - Validates the script is running on a server
    - Determines the appropriate admin user and password based on environment
    - Sets the user password securely
    - Adds batch logon rights for the user
    - Creates default scheduled tasks for the server

.NOTES
    - Only supported on servers (not workstations)
    - Environment is determined by computer name containing 'prd', 'tst', or 'dev'
    - Database servers get additional scheduled tasks
    - Requires Infrastructure and ScheduledTask-Handler modules

.EXAMPLE
    .\Setup-FkAdmUsersOnFkAdmRdp.ps1
    # Sets up FK admin users on the current server based on environment detection
#>
function Update-FkAdmUser2 {
    if (-not (Test-IsServer)) {
        Write-LogMessage "This script is only supported on servers" -Level ERROR
        return
    }


    if ($env:USERNAME -in @("FKPRDADM", "FKTSTADM", "FKDEVADM")) {
        Write-LogMessage "This script is only supported for other users than FKPRDADM, FKTSTADM, or FKDEVADM" -Level ERROR
        return
    }



    # Get current computer information and determine old username
    $oldUserName = $env:USERNAME

    # Determine new admin username and password based on environment
    $newUserName = ""
    if ($env:COMPUTERNAME.ToLower().Contains("prd")) {
        $newUserName = "FKPRDADM"
        # Password with special chars replaced: UF78FQFeFKx2ApSgZoF7zMDQFFPcy9MU8Xm
        $password = "UF78FQ^e$Kx2ApSgZo*7zMDQ!#Pcy9MU8Xm"
    }
    elseif ($env:COMPUTERNAME.ToLower().Contains("tst")) {
        $newUserName = "FKTSTADM"
        $password = "tk!bn7DEG^w5eR6xTo2^%3QRNSgc!&!jz93"
    }
    elseif ($env:COMPUTERNAME.ToLower().Contains("dev")) {
        $newUserName = "FKDEVADM"
        $password = "^mNtaP#nzKBuoTPas8%BNrXovJ68Y9B^*sa"
    }
    else {
        Write-LogMessage "Unknown environment: $env:COMPUTERNAME" -Level ERROR
        return
    }

    if ($env:COMPUTERNAME.ToLower().EndsWith("-db")) {
        Add-Db2UserToDb2admns -UserName $newUserName
    }
    Grant-BatchLogonRight -UserName $($env:USERDOMAIN + "\" + $newUserName)



    if ($env:COMPUTERNAME.ToLower().EndsWith("-db")) {
        # $applicationName = Get-ApplicationFromServerName
        # if ($applicationName -eq "DOC") {
        #     $instanceDb2Username = "SRV_SFKSS07"
        #     $instanceDb2Password = "Mandag123"
        # }
        # elseif ($applicationName -eq "INL") {
        #     $instanceDb2Username = "SRV_DB2"
        #     $instanceDb2Password = "Database1"
        # }
        # else {
        #     $instanceDb2Username = "SRV_DB2"
        #     $instanceDb2Password = "Database1"
        # }  

        $instanceDb2DatabaseName = Get-DatabaseNameFromServerName
        $instanceDb2FedDatabaseName = "X" + $instanceDb2DatabaseName
        $db2Script = @"
    set DB2INSTANCE=DB2
    db2stop force
    db2start
    db2 activate db $instanceDb2DatabaseName
    if %ERRORLEVEL% NEQ 0 (
        echo Failed to activate db $instanceDb2DatabaseName
        timeout /t 10
        exit /b 1
    )
    db2 connect to $instanceDb2DatabaseName 
    if %ERRORLEVEL% NEQ 0 (
        echo Failed to connect to $instanceDb2DatabaseName
        timeout /t 10
        exit /b 1
    )
    db2 update dbm cfg using SYSADM_GROUP DB2ADMNS

    db2 grant sysadm_group on SYSTEM to 'DB2ADMNS'
    db2 grant secadm on SYSTEM to $newUserName
    db2 grant dbadm with accessctrl with dataaccess on SYSTEM to $newUserName
    db2 grant bindadd on database to user $newUserName
    db2 grant connect on database to user $newUserName
    db2 grant createtab on database to user $newUserName
    db2 grant dbadm on database to user $newUserName
    db2 grant implicit_schema on database to user $newUserName
    db2 grant load on database to user $newUserName
    db2 grant quiesce_connect on database to user $newUserName
    db2 grant secadm on database to user $newUserName
    db2 grant sqladm on database to user $newUserName
    db2 grant wlmadm on database to user $newUserName
    db2 grant explain on database to user $newUserName
    db2 grant dataaccess on database to user $newUserName
    db2 grant accessctrl on database to user $newUserName
    db2 grant create_secure_object on database to user $newUserName
    db2 grant create_external_routine on database to user $newUserName
    db2 grant create_not_fenced_routine on database to user $newUserName
    db2 grant connect on database to user $newUserName
    db2 grant load on database to user $newUserName

    set DB2INSTANCE=DB2FED
    db2stop force
    db2start
    db2 activate db $instanceDb2FedDatabaseName
    if %ERRORLEVEL% NEQ 0 (
        echo Failed to activate db $instanceDb2FedDatabaseName
        timeout /t 10
        exit /b 1
    )
    db2 connect to $instanceDb2FedDatabaseName 
    if %ERRORLEVEL% NEQ 0 ( 
        echo Failed to connect to $instanceDb2FedDatabaseName
        timeout /t 10
        exit /b 1
    )

    db2 update dbm cfg using SYSADM_GROUP DB2ADMNS
    db2 grant sysadm_group on SYSTEM to 'DB2ADMNS'
    db2 grant secadm on SYSTEM to $newUserName
    db2 grant dbadm with accessctrl with dataaccess on SYSTEM to $newUserName
    db2 grant bindadd on database to user $newUserName
    db2 grant connect on database to user $newUserName
    db2 grant createtab on database to user $newUserName
    db2 grant dbadm on database to user $newUserName
    db2 grant implicit_schema on database to user $newUserName
    db2 grant load on database to user $newUserName
    db2 grant quiesce_connect on database to user $newUserName
    db2 grant secadm on database to user $newUserName
    db2 grant sqladm on database to user $newUserName
    db2 grant wlmadm on database to user $newUserName
    db2 grant explain on database to user $newUserName
    db2 grant dataaccess on database to user $newUserName
    db2 grant accessctrl on database to user $newUserName
    db2 grant create_secure_object on database to user $newUserName
    db2 grant create_external_routine on database to user $newUserName
    db2 grant create_not_fenced_routine on database to user $newUserName
    db2 grant connect on database to user $newUserName
    db2 grant load on database to user $newUserName
    timeout /t 10
"@
        Set-Content -Path "C:\temp\db2script.bat" -Value $db2Script
        $argumentList = "-w -c " + "C:\temp\db2script.bat"
        Write-LogMessage "Running $argumentList" -Level INFO 
        $command = "db2cmdadmin.exe -w -c C:\temp\db2script.bat"
        Write-LogMessage "Running $command" -Level INFO 

        $result = Start-Process "db2cmdadmin.exe" -ArgumentList $argumentList -Wait -PassThru -Verb RunAs
        if ($result.ExitCode -ne 0) {
            Write-LogMessage "Failed to run $command" -Level ERROR
        }

        #Remove-Item -Path "C:\temp\db2script.bat" -Force
    }    
    Set-UserPasswordAsSecureString -InputPw $password -Force -ChangeFromUserName $($oldUserName, "DEDGE\SRVERP13") -ForceUpdateServiceCredentials $true

}

<#
.SYNOPSIS
    Configures FK administrative user credentials and sets up server environment.

.DESCRIPTION
    This script configures FK administrative users based on the server environment (PRD, TST, DEV).
    It performs the following operations:
    - Validates the script is running on a server
    - Determines the appropriate admin user and password based on environment
    - Sets the user password securely
    - Adds batch logon rights for the user
    - Creates default scheduled tasks for the server

.NOTES
    - Only supported on servers (not workstations)
    - Environment is determined by computer name containing 'prd', 'tst', or 'dev'
    - Database servers get additional scheduled tasks
    - Requires Infrastructure and ScheduledTask-Handler modules

.EXAMPLE
    .\Setup-FkAdmUsersOnFkAdmRdp.ps1
    # Sets up FK admin users on the current server based on environment detection
#>
function Update-FkAdmUser {
    if (-not (Test-IsServer)) {
        Write-LogMessage "This script is only supported on servers" -Level ERROR
        return
    }


    if ($env:USERNAME -notin @("FKPRDADM", "FKTSTADM", "FKDEVADM", "FKGEISTA")) {
        Write-LogMessage "This script is only supported for FKPRDADM, FKTSTADM, or FKDEVADM" -Level ERROR
        return
    }



    # Get current computer information and determine old username
    $oldUserName = Get-OldServiceUsernameFromServerName

    # Determine new admin username and password based on environment
    $newUserName = ""
    if ($env:COMPUTERNAME.ToLower().Contains("prd") -or $env:COMPUTERNAME.ToLower().Contains("rap")) {
        $newUserName = "FKPRDADM"
        # Password with special chars replaced: UF78FQFeFKx2ApSgZoF7zMDQFFPcy9MU8Xm
        $password = "UF78FQ^e$Kx2ApSgZo*7zMDQ!#Pcy9MU8Xm"
    }
    elseif ($env:COMPUTERNAME.ToLower().Contains("tst") -or $env:COMPUTERNAME.ToLower().Contains("vfk") -or $env:COMPUTERNAME.ToLower().Contains("vft") -or $env:COMPUTERNAME.ToLower().Contains("mig") -or $env:COMPUTERNAME.ToLower().Contains("sit") -or $env:COMPUTERNAME.ToLower().Contains("per") -or $env:COMPUTERNAME.ToLower().Contains("fut") -or $env:COMPUTERNAME.ToLower().Contains("kat")) {
        $newUserName = "FKTSTADM"
        $password = "tk!bn7DEG^w5eR6xTo2^%3QRNSgc!&!jz93"
    }
    elseif ($env:COMPUTERNAME.ToLower().Contains("dev")) {
        $newUserName = "FKDEVADM"
        $password = "^mNtaP#nzKBuoTPas8%BNrXovJ68Y9B^*sa"
    }
    else {
        Write-LogMessage "Unknown environment: $env:COMPUTERNAME" -Level ERROR
        return
    }

    if ($env:COMPUTERNAME.ToLower().EndsWith("-db")) {
        Add-Db2UserToDb2admns -UserName $newUserName
    }
    Grant-BatchLogonRight



    if ($env:COMPUTERNAME.ToLower().EndsWith("-db")) {
        $applicationName = Get-ApplicationFromServerName
        if ($applicationName -eq "DOC") {
            $instanceDb2Username = "SRV_SFKSS07"
        }
        else {
            $instanceDb2Username = "SRV_DB2"
        }

        $instanceDb2DatabaseName = Get-DatabaseNameFromServerName
        $instanceDb2FedUserName = Get-OldServiceUsernameFromServerName

        # Retrieve passwords from Azure Key Vault instead of hardcoded values
        $instanceDb2Password = $null
        $instanceDb2FedPassword = $null
        try {
            Import-Module AzureFunctions -Force -ErrorAction Stop
            $kvConfigPath = Join-Path $env:OptPath "DedgePshApps\Azure-KeyVaultManager\keyvault-config.json"
            $kvName = $null
            $kvSubId = $null
            if (Test-Path $kvConfigPath) {
                $kvConfig = Get-Content $kvConfigPath -Raw | ConvertFrom-Json
                $kvName = $kvConfig.defaultVault
                $kvEntry = $kvConfig.vaults | Where-Object { $_.name -eq $kvName } | Select-Object -First 1
                if ($kvEntry) { $kvSubId = $kvEntry.subscriptionId }
            }
            if ($kvName) {
                Assert-AzureCliLogin

                $kvDbAdminName = ConvertTo-KeyVaultSecretName -Name $instanceDb2Username
                Write-LogMessage "Retrieving DB2 instance admin password from Key Vault: '$($kvDbAdminName)'" -Level INFO
                $rawAdmin = Get-AzureKeyVaultSecret -KeyVaultName $kvName -SecretName $kvDbAdminName -SubscriptionId $kvSubId
                $objAdmin = $rawAdmin | ConvertFrom-Json
                if ($objAdmin.value) { $instanceDb2Password = $objAdmin.value }

                $kvFedName = ConvertTo-KeyVaultSecretName -Name $instanceDb2FedUserName
                Write-LogMessage "Retrieving federated service account password from Key Vault: '$($kvFedName)'" -Level INFO
                $rawFed = Get-AzureKeyVaultSecret -KeyVaultName $kvName -SecretName $kvFedName -SubscriptionId $kvSubId
                $objFed = $rawFed | ConvertFrom-Json
                if ($objFed.value) { $instanceDb2FedPassword = $objFed.value }
            }
        }
        catch {
            Write-LogMessage "Key Vault lookup failed: $($_.Exception.Message). Falling back to defaults." -Level WARN
        }
        if (-not $instanceDb2Password) {
            Write-LogMessage "No Key Vault secret for DB2 admin '$($instanceDb2Username)' — using default password" -Level WARN
            $instanceDb2Password = "Database1"
        }
        if (-not $instanceDb2FedPassword) {
            Write-LogMessage "No Key Vault secret for fed user '$($instanceDb2FedUserName)' — using default password" -Level WARN
            $instanceDb2FedPassword = "Database1"
        }
        $instanceDb2FedPassword = Start-EscapeStringForCmd -InputString $instanceDb2FedPassword
        $instanceDb2Password = Start-EscapeStringForCmd -InputString $instanceDb2Password

        #         $instanceDb2FedDatabaseName = "X" + $instanceDb2DatabaseName
        #         $db2Script = @"
        #     set DB2INSTANCE=DB2
        #     db2 update dbm cfg using sysadm_group "DB2ADMNS"
        #     db2 update dbm cfg using sysctrl_group "DB2ADMNS"
        #     db2 update dbm cfg using sysmaint_group "DB2ADMNS"
        #     db2 update dbm cfg using sysmon_group "DB2ADMNS"
        #     db2stop force
        #     db2start
        #     db2 activate db $instanceDb2DatabaseName user $instanceDb2Username Using $instanceDb2Password
        #     if %ERRORLEVEL% NEQ 0 (
        #         db2 connect to $instanceDb2DatabaseName user $instanceDb2Username
        #     )
        #     db2 connect to $instanceDb2DatabaseName user $instanceDb2Username Using $instanceDb2Password
        #     if %ERRORLEVEL% NEQ 0 (
        #         db2 connect to $instanceDb2DatabaseName user $instanceDb2Username
        #     )
        #     db2 update dbm cfg using SYSADM_GROUP DB2ADMNS

        #     db2 grant sysadm_group on SYSTEM to 'DB2ADMNS'
        #     db2 grant secadm on SYSTEM to $newUserName
        #     db2 grant dbadm with accessctrl with dataaccess on SYSTEM to $newUserName
        #     db2 grant bindadd on database to user $newUserName
        #     db2 grant connect on database to user $newUserName
        #     db2 grant createtab on database to user $newUserName
        #     db2 grant dbadm on database to user $newUserName
        #     db2 grant implicit_schema on database to user $newUserName
        #     db2 grant load on database to user $newUserName
        #     db2 grant quiesce_connect on database to user $newUserName
        #     db2 grant secadm on database to user $newUserName
        #     db2 grant sqladm on database to user $newUserName
        #     db2 grant wlmadm on database to user $newUserName
        #     db2 grant explain on database to user $newUserName
        #     db2 grant dataaccess on database to user $newUserName
        #     db2 grant accessctrl on database to user $newUserName
        #     db2 grant create_secure_object on database to user $newUserName
        #     db2 grant create_external_routine on database to user $newUserName
        #     db2 grant create_not_fenced_routine on database to user $newUserName
        #     db2 grant connect on database to user $newUserName
        #     db2 grant load on database to user $newUserName

        #     set DB2INSTANCE=DB2FED       
        #     db2 update dbm cfg using sysadm_group "DB2ADMNS"
        #     db2 update dbm cfg using sysctrl_group "DB2ADMNS"
        #     db2 update dbm cfg using sysmaint_group "DB2ADMNS"
        #     db2 update dbm cfg using sysmon_group "DB2ADMNS"
        #     db2stop force
        #     db2start
        #     db2 activate db $instanceDb2FedDatabaseName user $instanceDb2FedUsername Using $instanceDb2FedPassword
        #     if %ERRORLEVEL% NEQ 0 (
        #         db2 connect to $instanceDb2FedDatabaseName user $instanceDb2FedUsername
        #     )
        #     db2 connect to $instanceDb2FedDatabaseName USER $instanceDb2FedUsername Using $instanceDb2FedPassword
        #     if %ERRORLEVEL% NEQ 0 (
        #         db2 connect to $instanceDb2FedDatabaseName USER $instanceDb2FedUsername
        #     )
        #     db2 update dbm cfg using SYSADM_GROUP DB2ADMNS
        #     db2 grant sysadm_group on SYSTEM to 'DB2ADMNS'
        #     db2 grant secadm on SYSTEM to $newUserName
        #     db2 grant dbadm with accessctrl with dataaccess on SYSTEM to $newUserName
        #     db2 grant bindadd on database to user $newUserName
        #     db2 grant connect on database to user $newUserName
        #     db2 grant createtab on database to user $newUserName
        #     db2 grant dbadm on database to user $newUserName
        #     db2 grant implicit_schema on database to user $newUserName
        #     db2 grant load on database to user $newUserName
        #     db2 grant quiesce_connect on database to user $newUserName
        #     db2 grant secadm on database to user $newUserName
        #     db2 grant sqladm on database to user $newUserName
        #     db2 grant wlmadm on database to user $newUserName
        #     db2 grant explain on database to user $newUserName
        #     db2 grant dataaccess on database to user $newUserName
        #     db2 grant accessctrl on database to user $newUserName
        #     db2 grant create_secure_object on database to user $newUserName
        #     db2 grant create_external_routine on database to user $newUserName
        #     db2 grant create_not_fenced_routine on database to user $newUserName
        #     db2 grant connect on database to user $newUserName
        #     db2 grant load on database to user $newUserName
        #     timeout /t 10
        # "@
        #         Set-Content -Path "C:\temp\db2script.bat" -Value $db2Script
        #         $argumentList = "-w -c " + "C:\temp\db2script.bat"
        #         Write-LogMessage "Running $argumentList" -Level INFO 
        #         $command = "db2cmdadmin.exe -w -c C:\temp\db2script.bat"
        #         Write-LogMessage "Running $command" -Level INFO 

        #         $result = Start-Process "db2cmdadmin.exe" -ArgumentList $argumentList -Wait -PassThru -Verb RunAs
        #         if ($result.ExitCode -ne 0) {
        #             Write-LogMessage "Failed to run $command" -Level ERROR
        #         }

        #         #Remove-Item -Path "C:\temp\db2script.bat" -Force
    }    
    Set-UserPasswordAsSecureString -InputPw $password -Force -ChangeFromUserName @($oldUserName, "DEDGE\SRVERP13") -ForceUpdateServiceCredentials $true

}

function Add-CurrentUserAsLocalAdmin {
    try {
        $adminGroupNames = @(
            [PSCustomObject]@{ Name = "Administrators"; Description = "English" },
            [PSCustomObject]@{ Name = "Administratorer"; Description = "Norwegian" }
        )
        $localAdminGroup = $null
        
        foreach ($groupInfo in $adminGroupNames) {
            if (Get-LocalGroup -Name $groupInfo.Name -ErrorAction SilentlyContinue) {
                $localAdminGroup = $groupInfo.Name
                break
            }
        }
        
        if (-not $localAdminGroup) {
            Write-LogMessage "Could not find administrators group with English or Norwegian name" -Level ERROR
            return
        }

        # Get the SID for the user
        $userSID = (New-Object System.Security.Principal.NTAccount($UserName)).Translate([System.Security.Principal.SecurityIdentifier]).Value

        # Check if the current user is already a local admin
        $currentUserIsAdmin = (Get-LocalGroupMember -Group $localAdminGroup | Where-Object { $_.Name -eq "$($env:USERDOMAIN)\$($env:USERNAME)" }).Count -gt 0
        
        if ($currentUserIsAdmin) {
            Write-LogMessage "Current user $currentUser is already a local admin" -Level INFO
            return
        }   
        
        # Add user by SID to ensure proper permissions
        powershell.exe -Command "Add-LocalGroupMember -Group $localAdminGroup -Member $userSID -ErrorAction SilentlyContinue"
        Write-LogMessage "Successfully added $UserName to the local admin group" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to add $UserName to the local admin group: $_" -Level ERROR
    }
    
}

function Remove-DuplicateServicesFromServiceFile {    
    try {
        # Requires Administrator privileges
        if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
            Write-Error "This script requires Administrator privileges. Please run as Administrator."
            exit 1
        }

        $servicesFile = Join-Path $env:windir "system32\drivers\etc\services"
        $content = Get-Content $servicesFile -Encoding ASCII
        $content = $content | Sort-Object
        $content = $content | Select-Object -Unique
        $content | Set-Content $servicesFile -Encoding ASCII -Force
        Write-LogMessage "Successfully removed duplicate services from services file" -Level INFO
        return $true
    }
    catch {
        Write-LogMessage "Failed to remove duplicate services from services file: $($_.Exception.Message)" -Level ERROR -Exception $_
        return $false
    }
}
function Remove-ServicesFromServiceFile {    
    param(
        [string]$ServicesPattern = "(DB2C_*|DB.*25000/tcp|DB.*37[0-2][0-9]/tcp|DB.*50(0[0-9][0-9]|100/tcp))",
        [switch]$ServicesPatternIsRegex,
        [switch]$WhatIf,
        [switch]$Diff,
        [switch]$Force
    )
    $modulesToImport = @("GlobalFunctions")
    foreach ($moduleName in $modulesToImport) {
        $loadedModule = Get-Module -Name $moduleName
        if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
            Write-LogMessage "Importing module: $moduleName" -Level INFO
            Import-Module $moduleName -Force
        }
        else {
            Write-LogMessage "Module $moduleName already loaded" -Level INFO
        }
    } 
      
    # Requires Administrator privileges
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "This script requires Administrator privileges. Please run as Administrator."
        exit 1
    }

    $servicesFile = Join-Path $env:windir "system32\drivers\etc\services"
    $backupFolder = Join-Path $env:OptPath "data\WindowsBackupFiles"
    if (-not (Test-Path $backupFolder)) {
        New-Item -ItemType Directory -Path $backupFolder | Out-Null
    }
    $backupFile = Join-Path $backupFolder "services_$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

    Write-LogMessage "=================================" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "DB2 Services File Cleanup Script" -Level INFO 
    Write-LogMessage "=================================" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "Services file: $servicesFile" -Level INFO
    Write-LogMessage "Backup file: $backupFile" -Level INFO
    Write-LogMessage "Removing lines starting with: $ServicesPattern" -Level INFO

    # Check if services file exists
    if (-not (Test-Path $servicesFile -PathType Leaf)) {
        Write-LogMessage "Services file not found: $servicesFile" -Level ERROR
        exit 1
    }

    try {
        # Read all lines from the services file
        Write-LogMessage "Reading services file..." -Level INFO
        $allLines = Get-Content $servicesFile -Encoding ASCII
    
        # Find lines to remove
        if ($ServicesPatternIsRegex) {
            $linesToRemove = $allLines | Where-Object { $_.ToLower() -match "$ServicesPattern".ToLower() }
            $linesToKeep = $allLines | Where-Object { $_.ToLower() -notmatch "$ServicesPattern".ToLower() }
        }
        else {
            $linesToRemove = $allLines | Where-Object { $_.ToLower() -match "^$ServicesPattern".ToLower() }
            $linesToKeep = $allLines | Where-Object { $_.ToLower() -notmatch "^$ServicesPattern".ToLower() }
        }
    
        Write-LogMessage "Total lines in services file: $($allLines.Count)"
        Write-LogMessage "Lines to remove: $($linesToRemove.Count)" -Level INFO
        Write-LogMessage "Lines to keep: $($linesToKeep.Count)" -Level INFO
    
    
        if ($linesToRemove.Count -gt 0) {
            Write-LogMessage "Lines that will be removed:" -Level INFO
            $linesToRemove | ForEach-Object { Write-LogMessage "  $_" -Level INFO }
        
            if ($WhatIf) {
                Write-LogMessage "WhatIf mode: No changes will be made." -Level WARN
                & notepad.exe $servicesFile
                return
            }
        
            if (-not $Force) {
                $confirm = Read-Host "Do you want to proceed with removing these lines? (y/N)"
                if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                    Write-LogMessage "Operation cancelled by user." -Level WARN
                    return
                }
            }
        
            # Create backup
            Write-LogMessage "Creating backup..." -Level INFO
            Copy-Item $servicesFile $backupFile -Force
            Write-LogMessage "Backup created: $backupFile" -Level INFO
        
            # Write the filtered content back to the services file
            Write-LogMessage "Updating services file..." -Level INFO
            $linesToKeep | Set-Content $servicesFile -Encoding ASCII -Force
        
        
            Write-LogMessage "Successfully removed $($linesToRemove.Count) DB2 service entries!" -Level INFO
            Write-LogMessage "Backup saved to: $backupFile" -Level INFO
        
            # Verify the changes
            $newLines = Get-Content $servicesFile
            Write-LogMessage "Verification: Services file now contains $($newLines.Count) lines" -Level INFO

            if ($Diff) {
                Write-LogMessage "Diffing $servicesFile and $backupFile" -Level INFO
                code --diff $servicesFile $backupFile        
            }
        }
        else {
            Write-LogMessage "No lines found starting with '$ServicesPattern' - nothing to remove." -Level WARN
        }
        Write-LogMessage "Script completed successfully!" -Level INFO 
    
    }
    catch {
        Write-LogMessage "An error occurred: $($_.Exception.Message)" -Level ERROR -Exception $_
    
        # Restore from backup if it exists and the original file was modified
        if (Test-Path $backupFile) {
            Write-LogMessage "Attempting to restore from backup..." -Level WARN 
            try {
                Copy-Item $backupFile $servicesFile -Force
                Write-LogMessage "Services file restored from backup." -Level INFO
            }
            catch {
                Write-LogMessage "Failed to restore from backup: $($_.Exception.Message)" -Level ERROR -Exception $_
            }
        }
        exit 1
    }
}
function Get-ServicesFromServiceFile {
    param(
        [string]$ServicesPattern = "(DB2C_*|DB.*25000/tcp|DB.*37[0-2][0-9]/tcp|DB.*50(0[0-9][0-9]|100/tcp))",
        [switch]$ServicesPatternIsRegex
    )
 
    # Requires Administrator privileges
    if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Error "This script requires Administrator privileges. Please run as Administrator."
        exit 1
    }

    $servicesFile = Join-Path $env:windir "system32\drivers\etc\services"
    $backupFolder = Join-Path $env:OptPath "data\WindowsBackupFiles"
    if (-not (Test-Path $backupFolder)) {
        New-Item -ItemType Directory -Path $backupFolder | Out-Null
    }
    $backupFile = Join-Path $backupFolder "services_$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

    Write-LogMessage "=================================" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "DB2 Services File Cleanup Script" -Level INFO 
    Write-LogMessage "=================================" -Level INFO -ForegroundColor Cyan
    Write-LogMessage "Services file: $servicesFile" -Level INFO
    Write-LogMessage "Backup file: $backupFile" -Level INFO
    Write-LogMessage "Removing lines starting with: $ServicesPattern" -Level INFO

    # Check if services file exists
    if (-not (Test-Path $servicesFile -PathType Leaf)) {
        Write-LogMessage "Services file not found: $servicesFile" -Level ERROR
        exit 1
    }

    try {
        # Read all lines from the services file
        Write-LogMessage "Reading services file..." -Level INFO
        $allLines = Get-Content $servicesFile -Encoding ASCII
    
        # Find lines to remove
        if ($ServicesPatternIsRegex) {
            $linesToGet = $allLines | Where-Object { $_.ToLower() -match "$ServicesPattern".ToLower() }
        }
        else {
            $linesToGet = $allLines | Where-Object { $_.ToLower() -match "^$ServicesPattern".ToLower() }
        }
    
        Write-LogMessage "Total lines in services file: $($allLines.Count)"
        Write-LogMessage "Lines to get: $($linesToGet.Count)" -Level INFO
    
    
        if ($linesToGet.Count -gt 0) {
            Write-LogMessage "Lines that will be get:" -Level INFO
            $linesToGet | ForEach-Object { Write-LogMessage "  $_" -Level INFO }
        }
        else {
            Write-LogMessage "No lines found starting with '$ServicesPattern' - nothing to get." -Level WARN
        }
        Write-LogMessage "Script completed successfully!" -Level INFO 
        return @($linesToGet)
    
    }
    catch {
        Write-LogMessage "An error occurred: $($_.Exception.Message)" -Level ERROR -Exception $_
        return @()
    }
}

function Add-ServicesToServiceFile {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$Services
    )
    try {
        
        Write-LogMessage "Adding services to services file..." -Level INFO
        $servicesFile = Join-Path $env:windir "system32\drivers\etc\services"
        $existingServices = Get-Content $servicesFile

        foreach ($service in $Services) {
            $matchingServices = $existingServices | Where-Object { $_.Trim().Contains($($service.Port.ToString() + "/$($service.Protocol)")) }
            if ($matchingServices) {
                Write-LogMessage "Service $($service.ServiceName) already exists on port $($service.Port)" -Level WARN
                continue             
            }
            Write-LogMessage "Adding service $($service.ServiceName) on port $($service.Port)" -Level INFO
            Add-Content -Path $servicesFile -Value "$($service.ServiceName.PadRight(15)) $($($service.Port.ToString() + "/$($service.Protocol)").PadRight(35)) #$($service.Description)"
        }

        Write-LogMessage "Successfully added $($Services.Count) service entries" -Level INFO
        return $true
    }
    catch {
        Write-LogMessage "Error adding services to services file" -Level ERROR -Exception $_
        return $false
    }
}

<#
.SYNOPSIS
    Verifies Active Directory user existence and properties
    
.DESCRIPTION
    This script verifies if a specified user exists in Active Directory and displays
    relevant information including SPNs, group memberships, and account status.
    
.PARAMETER Username
    The username to verify (e.g., T1_srv_inldev-db)
    
.PARAMETER Domain
    The domain to search in (default: DEDGE.fk.no)
    
.EXAMPLE
    .\Verify-ADUser.ps1 -Username "T1_srv_inldev-db"
    
.EXAMPLE
    .\Verify-ADUser.ps1 -Username "T1_srv_fkmper-db" -Domain "DEDGE.fk.no"
    
.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Requires: Active Directory PowerShell module
#>
function Test-ADUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,
    
        [Parameter(Mandatory = $false)]
        [string]$Domain = "DEDGE.fk.no",
        [switch]$Quiet
    )

    Install-ActiveDirectoryModule

    try {
        # Search for the user in Active Directory
        $user = Get-ADUser -Filter "SamAccountName -eq '$Username'" -Properties * -Server $Domain
    
        if ($user) {
            # Display basic user information
            $userInfoObject = [PSCustomObject]@{
                Username          = $user.SamAccountName
                DisplayName       = $user.DisplayName
                UserPrincipalName = $user.UserPrincipalName
                DistinguishedName = $user.DistinguishedName
                AccountStatus     = $user.Enabled
                LastLogon         = $user.LastLogonDate
                PasswordLastSet   = $user.PasswordLastSet
                AccountLockout    = $user.LockedOut
            }

            if (-not $Quiet) {
                "User Information`n" + ($userInfoObject | Format-List | Out-String) | ForEach-Object { Write-LogMessage $_ -Level INFO }

        
                # Display SPNs if any
                if ($user.ServicePrincipalNames) {
                    $spnObjectArray = @()
                    foreach ($spn in $user.ServicePrincipalNames) {
                        $spnObjectArray += [PSCustomObject]@{
                            SPN = $spn
                        }
                    }
                    if (-not $Quiet) {
                        "Service Principal Names`n" + ($spnObjectArray | Format-List | Out-String) | ForEach-Object { Write-LogMessage $_ -Level INFO }
                    }
                }
           
        
                # Display group memberships
                try {
                    $groups = Get-ADPrincipalGroupMembership -Identity $user.SamAccountName -Server $Domain
                    $groupsObjectArray = @()
                
                    foreach ($group in $groups) {
                        $properties = $group | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                        $groupProperties = [PSCustomObject]@{}
                        foreach ($property in $properties) {
                            Add-Member -InputObject $groupProperties -NotePropertyName $property -NotePropertyValue $group.$property -Force
                        }
                        $groupsObjectArray += $groupProperties
                    }
                
                    if (-not $Quiet) {
                        "Group Memberships`n" + ($groupsObjectArray | Format-List | Out-String) | ForEach-Object { Write-LogMessage $_ -Level INFO }
                    }

                }
                catch {
                    if (-not $Quiet) {
                        Write-LogMessage "Unable to retrieve group memberships: $($_.Exception.Message)" -Level WARN
                    }
                }
        
                # Display additional properties
                $additionalPropertiesObject = [PSCustomObject]@{
                    Description = $user.Description
                    Office      = $user.Office
                    Department  = $user.Department
                    Title       = $user.Title
                    Company     = $user.Company
                }
            
                if (-not $Quiet) {
                    "Additional Properties`n" + ($additionalPropertiesObject | Format-List | Out-String) | ForEach-Object { Write-LogMessage $_ -Level INFO }
                }
            }
        }
        else {
            if (-not $Quiet) {
                Write-LogMessage "User $Username not found in Active Directory" -Level WARN
        
                # Try to search with partial match
                Write-LogMessage "Searching for similar usernames..." -Level INFO
                $similarUsers = Get-ADUser -Filter "SamAccountName -like '*$Username*'" -Properties SamAccountName, DisplayName -Server $Domain
        
                if ($similarUsers) {
                    Write-LogMessage "Similar usernames found:" -Level INFO
                    $similarUsersObject = [PSCustomObject]@{
                        SimilarUsers = $similarUsers
                    }
                
                    if (-not $Quiet) {
                        "Similar users`n" + ($similarUsersObject | Format-List | Out-String) | ForEach-Object { Write-LogMessage $_ -Level INFO }
                    }
                }
                else {
                    if (-not $Quiet) {
                        Write-LogMessage "No similar usernames found" -Level WARN
                    }
                }
            }
        }
        if ($user) {
            if (-not $Quiet) {
                Write-LogMessage "User $Username verified successfully in Active Directory" -Level INFO
            }
            return $true
        }
        else {
            if (-not $Quiet) {
                Write-LogMessage "User $Username not found in Active Directory" -Level WARN
            }
            return $false
        }
    }
    catch {
        Write-LogMessage "Error during user verification for $Username" -Level ERROR -Exception $_  
    }

}

<#
.SYNOPSIS
    Detects whether this machine is an Azure Virtual Desktop (AVD) session host using the AVD agent and related registry paths.

.DESCRIPTION
    Checks for signals used by the Azure Virtual Desktop session host stack:
    - The RDAgent service (Remote Desktop Agent / AVD agent component).
    - HKLM\SOFTWARE\Microsoft\RDInfraAgent (registration and agent state; used in Microsoft deployment guidance).
    - HKLM\SOFTWARE\Microsoft\RDAgentBootLoader (bootloader locates the agent).

    Returns $true if RDInfraAgent registry exists, or if both RDAgent service and RDAgentBootLoader registry exist.

.OUTPUTS
    System.Boolean

.EXAMPLE
    if (Test-AzureVirtualDesktopSessionHost) { ... }

.NOTES
    RDInfraAgent is documented for AVD session host registration (see Microsoft Learn: Azure Virtual Desktop agent troubleshooting).
#>
function Test-AzureVirtualDesktopSessionHost {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # AVD detection: match computer name prefix for Azure Virtual Desktop session hosts
    $isAvd = $env:COMPUTERNAME.ToUpper().StartsWith("P-NO1AVD")

    # --- Original detection logic (commented out - was slow due to Get-Service / registry queries) ---
    # $rdInfraAgentPath = 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent'
    # $rdAgentBootLoaderPath = 'HKLM:\SOFTWARE\Microsoft\RDAgentBootLoader'
    # $hasRdInfraAgent = Test-Path -LiteralPath $rdInfraAgentPath
    # $hasRdAgentBootLoader = Test-Path -LiteralPath $rdAgentBootLoaderPath
    # $rdAgentService = $null
    # try {
    #     $rdAgentService = Get-Service -Name 'RDAgent' -ErrorAction SilentlyContinue
    # }
    # catch {
    #     # Service not present or access denied; treat as not found
    # }
    # $hasRdAgentService = $null -ne $rdAgentService
    # return ($hasRdInfraAgent -or ($hasRdAgentService -and $hasRdAgentBootLoader))
    # --- End original detection logic ---

    return $isAvd
}


<#
.SYNOPSIS
    Compares all available Active Directory settings for two user accounts.

.DESCRIPTION
    Retrieves the full property sets returned by Get-ADUser for each provided username. The function normalizes the
    property values, compares them property-by-property, and returns structured comparison
    data along with metadata and optional raw objects for troubleshooting.

.PARAMETER ReferenceUserName
    The primary username (SAM account name, UPN, or object identifier) to use as the reference.

.PARAMETER DifferenceUserName
    The secondary username to compare against the reference user.

.PARAMETER IncludeRawData
    When specified, the raw AD user objects are included in the output for further inspection.

.OUTPUTS
    PSCustomObject containing comparison arrays (AD) plus metadata and optional raw data.

.EXAMPLE
    Compare-AdUserSettings -ReferenceUserName "user1" -DifferenceUserName "user2"
#>
function Compare-AdUserSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReferenceUserName,
        [Parameter(Mandatory = $true)]
        [string]$DifferenceUserName,
        [switch]$IncludeRawData,
        [switch]$ExcludeMatches
    )

    Write-LogMessage "Comparing AD settings for $($ReferenceUserName) and $($DifferenceUserName)" -Level INFO

    $metadata = [PSCustomObject]@{
        Timestamp                   = (Get-Date).ToUniversalTime().ToString("o")
        AdReferenceLookupSucceeded  = $false
        AdDifferenceLookupSucceeded = $false
        AdPropertiesCompared        = 0
        AdDifferences               = 0
        
    }

    $normalizeValue = {
        param($Value)

        if ($null -eq $Value) {
            return $null
        }

        if ($Value -is [datetime]) {
            return $Value.ToUniversalTime().ToString("o")
        }

        if ($Value -is [System.Collections.IDictionary]) {
            $pairs = @()
            foreach ($key in ($Value.Keys | Sort-Object)) {
                $pairs += "$key=$($Value[$key])"
            }
            return $pairs -join "; "
        }

        if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
            $items = @()
            foreach ($item in $Value) {
                if ($item -is [pscustomobject] -or $item -is [System.Collections.IDictionary]) {
                    $items += ($item | ConvertTo-Json -Depth 6 -Compress)
                }
                else {
                    $items += "$item"
                }
            }
            return ($items | Sort-Object) -join ", "
        }

        return "$Value"
    }

    $convertToPropertyMap = {
        param($InputObject)

        $map = [ordered]@{}
        if ($null -eq $InputObject) {
            return $map
        }

        foreach ($property in $InputObject.PSObject.Properties) {
            if ($property.MemberType -notin @('NoteProperty', 'Property', 'AliasProperty', 'ScriptProperty')) {
                continue
            }

            try {
                $map[$property.Name] = & $normalizeValue $property.Value
            }
            catch {
                $map[$property.Name] = "<conversion failed>"
            }
        }

        return $map
    }

    $compareMaps = {
        param(
            [System.Collections.IDictionary]$ReferenceMap,
            [System.Collections.IDictionary]$DifferenceMap,
            [string]$SourceName
        )

        $rows = @()
        $referenceKeys = @($ReferenceMap.Keys)
        $differenceKeys = @($DifferenceMap.Keys)
        $allPropertyNames = @($referenceKeys + $differenceKeys | Sort-Object -Unique)

        foreach ($propertyName in $allPropertyNames) {
            $referenceExists = $referenceKeys -contains $propertyName
            $differenceExists = $differenceKeys -contains $propertyName
            $referenceValue = if ($referenceExists) { $ReferenceMap[$propertyName] } else { $null }
            $differenceValue = if ($differenceExists) { $DifferenceMap[$propertyName] } else { $null }

            $status = if ($referenceExists -and $differenceExists) {
                if ($referenceValue -eq $differenceValue) { "Match" } else { "Different" }
            }
            elseif ($referenceExists) {
                "ReferenceOnly"
            }
            else {
                "DifferenceOnly"
            }

            $rows += [PSCustomObject]@{
                Source          = $SourceName
                Property        = $propertyName
                ReferenceValue  = $referenceValue
                DifferenceValue = $differenceValue
                Status          = $status
            }
        }

        return $rows
    }

    $adReferenceUser = $null
    $adDifferenceUser = $null

    try {
        if (-not (Get-Module -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
            Import-Module ActiveDirectory -ErrorAction Stop
        }
        Write-LogMessage "ActiveDirectory module loaded for comparison" -Level DEBUG
    }
    catch {
        Write-LogMessage "ActiveDirectory module unavailable. AD comparison will be skipped." -Level WARN -Exception $_
    }

    if (Get-Command -Name Get-ADUser -ErrorAction SilentlyContinue) {
        try {
            $adReferenceUser = Get-ADUser -Identity $ReferenceUserName -Properties * -ErrorAction Stop
            $metadata.AdReferenceLookupSucceeded = $true
        }
        catch {
            Write-LogMessage "Unable to retrieve AD user $($ReferenceUserName)" -Level WARN -Exception $_
        }

        try {
            $adDifferenceUser = Get-ADUser -Identity $DifferenceUserName -Properties * -ErrorAction Stop
            $metadata.AdDifferenceLookupSucceeded = $true
        }
        catch {
            Write-LogMessage "Unable to retrieve AD user $($DifferenceUserName)" -Level WARN -Exception $_
        }
    }
    else {
        Write-LogMessage "Get-ADUser cmdlet not found. AD comparison skipped." -Level WARN
    }

    $adComparison = @()
    if ($metadata.AdReferenceLookupSucceeded -or $metadata.AdDifferenceLookupSucceeded) {
        $adComparison = & $compareMaps (& $convertToPropertyMap $adReferenceUser) (& $convertToPropertyMap $adDifferenceUser) "ActiveDirectory"
        $metadata.AdPropertiesCompared = $adComparison.Count
        $metadata.AdDifferences = ($adComparison | Where-Object { $_.Status -ne "Match" }).Count
    }

    $entraCommand = Get-Command -Name Get-EntraUser -ErrorAction SilentlyContinue
    if (-not $entraCommand) {
        $entraCommand = Get-Command -Name Get-MgUser -ErrorAction SilentlyContinue
    }

    if (-not $entraCommand) {
        try {
            if (Get-Module -ListAvailable -Name Entra -ErrorAction SilentlyContinue) {
                Import-Module Entra -ErrorAction Stop
                $entraCommand = Get-Command -Name Get-EntraUser -ErrorAction SilentlyContinue
            }
            elseif (Get-Module -ListAvailable -Name Microsoft.Graph.Users -ErrorAction SilentlyContinue) {
                Import-Module Microsoft.Graph.Users -ErrorAction Stop
                $entraCommand = Get-Command -Name Get-MgUser -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-LogMessage "Unable to import Entra/Microsoft Graph cmdlets" -Level WARN -Exception $_
        }
    }

    # Filter out matching elements if ExcludeMatches switch is enabled
    $filteredAdComparison = $adComparison
    if ($ExcludeMatches) {
        $filteredAdComparison = $adComparison | Where-Object { $_.Status -ne "Match" }
        Write-LogMessage "Filtered comparison to show only differences. Displaying $($filteredAdComparison.Count) of $($adComparison.Count) properties." -Level INFO
    }

    # Organize comparison data for better HTML side-by-side display
    $result = [PSCustomObject]@{
        ReferenceUserName       = $ReferenceUserName
        DifferenceUserName      = $DifferenceUserName
        TotalPropertiesCompared = $metadata.AdPropertiesCompared
        TotalDifferences        = $metadata.AdDifferences
        ComparisonResults       = $filteredAdComparison
        Metadata                = $metadata
        RawData                 = $null
    }

    if ($IncludeRawData) {
        $result.RawData = [PSCustomObject]@{
            ActiveDirectory = [PSCustomObject]@{
                Reference  = $adReferenceUser
                Difference = $adDifferenceUser
            }
        }
    }

    Write-LogMessage "Comparison complete. AD differences: $($metadata.AdDifferences)." -Level INFO
    $outputFolder = Join-Path $(Get-ApplicationDataPath) "Ad-CompareUserSettings"
    if (-not (Test-Path $outputFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $outputFolder -Force -ErrorAction SilentlyContinue | Out-Null
    }
    $filenameSuffix = if ($ExcludeMatches) { "-DifferencesOnly" } else { "" }
    $outputFileName = Join-Path $outputFolder "$($ReferenceUserName)-$($DifferenceUserName)$($filenameSuffix).html"
    $titleSuffix = if ($ExcludeMatches) { " (Differences Only)" } else { "" }
    Export-WorkObjectToHtmlFile -WorkObject $result -FileName $outputFileName -Title "AdEntra-CompareUserSettings for $($ReferenceUserName) and $($DifferenceUserName)$($titleSuffix)" -AutoOpen $true
    Export-WorkObjectToJsonFile -WorkObject $result -FileName $($outputFileName -replace ".html", ".json")

    return $result
}

<#
.SYNOPSIS
    Generates a categorized markdown report of AD group membership differences based on a template file.

.DESCRIPTION
    Parses a markdown template file containing categorized AD groups, compares against the comparison
    result object from Compare-AdUserSettings, and generates a report showing which groups are missing
    or different, organized by category.

.PARAMETER ComparisonResult
    The result object from Compare-AdUserSettings containing the comparison data.

.PARAMETER TemplateFilePath
    Path to the markdown file containing the expected categories and groups.

.PARAMETER OutputFilePath
    Optional path to save the generated markdown report. If not specified, returns the markdown content.

.OUTPUTS
    String containing the markdown report, or file path if OutputFilePath is specified.

.EXAMPLE
    $comparison = Compare-AdUserSettings -ReferenceUserName "user1" -DifferenceUserName "user2"
    Export-AdComparisonMarkdown -ComparisonResult $comparison -TemplateFilePath "C:\template.md"
#>
function Export-AdComparisonMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ComparisonResult,
        [Parameter(Mandatory = $true)]
        [string]$TemplateFilePath,
        [Parameter(Mandatory = $false)]
        [string]$OutputFilePath
    )

    Write-LogMessage "Generating categorized markdown report from template: $($TemplateFilePath)" -Level INFO

    if (-not (Test-Path $TemplateFilePath)) {
        Write-LogMessage "Template file not found: $($TemplateFilePath)" -Level ERROR
        throw "Template file not found: $TemplateFilePath"
    }

    # Read template file and parse categories
    $templateContent = Get-Content -Path $TemplateFilePath -Raw -Encoding UTF8
    $categories = @()
    $currentCategory = $null
    $currentSubCategory = $null

    foreach ($line in ($templateContent -split "`r?`n")) {
        # Match level 2 heading (## Category Name)
        if ($line -match '^##\s+(.+)$') {
            if ($currentCategory) {
                $categories += $currentCategory
            }
            $currentCategory = [PSCustomObject]@{
                Name          = $Matches[1].Trim()
                SubCategories = @()
                Items         = @()
            }
            $currentSubCategory = $null
        }
        # Match level 3 heading (### SubCategory Name)
        elseif ($line -match '^###\s+(.+)$') {
            if ($currentCategory) {
                $currentSubCategory = [PSCustomObject]@{
                    Name  = $Matches[1].Trim()
                    Items = @()
                }
                $currentCategory.SubCategories += $currentSubCategory
            }
        }
        # Match level 4 heading (#### SubCategory Name)
        elseif ($line -match '^####\s+(.+)$') {
            if ($currentCategory) {
                $currentSubCategory = [PSCustomObject]@{
                    Name  = $Matches[1].Trim()
                    Items = @()
                }
                $currentCategory.SubCategories += $currentSubCategory
            }
        }
        # Match items (lines that are not empty and don't start with #)
        elseif ($line -match '^\s*([A-Za-z0-9_\-\*\\]+)\s*$' -and $line.Trim() -ne '') {
            $itemName = $Matches[1].Trim()
            if ($currentSubCategory) {
                $currentSubCategory.Items += $itemName
            }
            elseif ($currentCategory) {
                $currentCategory.Items += $itemName
            }
        }
    }

    # Add last category
    if ($currentCategory) {
        $categories += $currentCategory
    }

    Write-LogMessage "Parsed $($categories.Count) categories from template" -Level DEBUG

    # Get MemberOf property from comparison results
    $memberOfProperty = $ComparisonResult.ComparisonResults | Where-Object { $_.Property -eq 'MemberOf' }
    
    if (-not $memberOfProperty) {
        Write-LogMessage "MemberOf property not found in comparison results" -Level WARN
        $referenceGroups = @()
        $differenceGroups = @()
    }
    else {
        # Parse group memberships from the comparison result
        $referenceGroupsRaw = if ($memberOfProperty.ReferenceValue) { $memberOfProperty.ReferenceValue -split ',\s*' } else { @() }
        $differenceGroupsRaw = if ($memberOfProperty.DifferenceValue) { $memberOfProperty.DifferenceValue -split ',\s*' } else { @() }

        # Extract just the CN (Common Name) from each DN
        $referenceGroups = $referenceGroupsRaw | ForEach-Object {
            if ($_ -match 'CN=([^,]+)') {
                $Matches[1]
            }
        }
        $differenceGroups = $differenceGroupsRaw | ForEach-Object {
            if ($_ -match 'CN=([^,]+)') {
                $Matches[1]
            }
        }
    }

    Write-LogMessage "Reference user groups: $($referenceGroups.Count), Difference user groups: $($differenceGroups.Count)" -Level DEBUG

    # Generate markdown report
    $markdownLines = @()
    $markdownLines += "# AD Group Membership Comparison Report"
    $markdownLines += ""
    $markdownLines += "**Reference User:** $($ComparisonResult.ReferenceUserName)"
    $markdownLines += "**Difference User:** $($ComparisonResult.DifferenceUserName)"
    $markdownLines += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $markdownLines += ""

    $totalDifferences = 0

    foreach ($category in $categories) {
        $categoryDifferences = @()
        
        # Check items directly under category
        foreach ($item in $category.Items) {
            $refHas = $referenceGroups -contains $item
            $diffHas = $differenceGroups -contains $item
            
            if ($refHas -ne $diffHas) {
                $status = if ($refHas -and -not $diffHas) { "❌ Missing in $($ComparisonResult.DifferenceUserName)" }
                elseif (-not $refHas -and $diffHas) { "✓ Only in $($ComparisonResult.DifferenceUserName)" }
                else { "?" }
                
                $categoryDifferences += [PSCustomObject]@{
                    SubCategory = $null
                    Item        = $item
                    Status      = $status
                    RefHas      = $refHas
                    DiffHas     = $diffHas
                }
            }
        }

        # Check items in subcategories
        foreach ($subCat in $category.SubCategories) {
            foreach ($item in $subCat.Items) {
                $refHas = $referenceGroups -contains $item
                $diffHas = $differenceGroups -contains $item
                
                if ($refHas -ne $diffHas) {
                    $status = if ($refHas -and -not $diffHas) { "❌ Missing in $($ComparisonResult.DifferenceUserName)" }
                    elseif (-not $refHas -and $diffHas) { "✓ Only in $($ComparisonResult.DifferenceUserName)" }
                    else { "?" }
                    
                    $categoryDifferences += [PSCustomObject]@{
                        SubCategory = $subCat.Name
                        Item        = $item
                        Status      = $status
                        RefHas      = $refHas
                        DiffHas     = $diffHas
                    }
                }
            }
        }

        # Only add category to report if there are differences
        if ($categoryDifferences.Count -gt 0) {
            $markdownLines += "## $($category.Name)"
            $markdownLines += ""
            $totalDifferences += $categoryDifferences.Count
            
            # Group by subcategory
            $bySubCategory = $categoryDifferences | Group-Object -Property SubCategory
            
            foreach ($group in $bySubCategory) {
                if ($group.Name) {
                    $markdownLines += "### $($group.Name)"
                    $markdownLines += ""
                }
                
                foreach ($diff in $group.Group) {
                    $markdownLines += "- **$($diff.Item)**: $($diff.Status)"
                }
                $markdownLines += ""
            }
        }
    }

    # Add summary
    $markdownLines = @(
        $markdownLines[0..3]
        ""
        "**Total Differences Found:** $totalDifferences"
        ""
    ) + $markdownLines[4..($markdownLines.Count - 1)]

    $markdownContent = $markdownLines -join "`r`n"

    # Save to file if specified
    if ($OutputFilePath) {
        $markdownContent | Out-File -FilePath $OutputFilePath -Encoding UTF8 -Force
        Write-LogMessage "Markdown report saved to: $($OutputFilePath)" -Level INFO
        return $OutputFilePath
    }
    else {
        return $markdownContent
    }
}

function Stop-ProcessTree {
    <#
    .SYNOPSIS
        Kills all processes matching a given name, including their entire process trees.

    .DESCRIPTION
        Applications like VS Code, Cursor, and browsers spawn many child processes
        (renderer, extension host, GPU helper, file watcher, etc.).
        This function identifies root parent processes and uses taskkill /T /F to
        terminate the full tree. If any stragglers survive, they are killed individually.
        As a last resort, taskkill /IM is used to catch anything remaining.

        Returns a PSCustomObject with the result.

    .PARAMETER ProcessName
        The process name to kill (without .exe). Examples: "Code", "Cursor", "chrome".

    .EXAMPLE
        Stop-ProcessTree -ProcessName "Code"
        # Kills all VS Code processes and their child trees.

    .EXAMPLE
        $result = Stop-ProcessTree -ProcessName "chrome"
        if (-not $result.Success) { Write-Host "Some processes survived!" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName
    )

    $imageName = "$($ProcessName).exe"

    # ── Enumerate ────────────────────────────────────────────────────────────
    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if (-not $processes) {
        Write-LogMessage "No '$($ProcessName)' processes running" -Level INFO
        return [PSCustomObject]@{
            ProcessName   = $ProcessName
            InitialCount  = 0
            RootCount     = 0
            KilledCount   = 0
            SurvivorCount = 0
            Success       = $true
        }
    }

    $totalCount = @($processes).Count
    Write-LogMessage "Found $($totalCount) '$($ProcessName)' process(es) -- identifying root parent(s)" -Level INFO

    # ── Step 1: Identify root processes (parent is NOT also a same-name process) ─
    $processIds = @($processes | ForEach-Object { $_.Id })
    $rootProcesses = @()
    foreach ($proc in $processes) {
        try {
            $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).ParentProcessId
            if ($parentId -notin $processIds) {
                $rootProcesses += $proc
            }
        }
        catch {
            # Cannot determine parent -- treat as root to be safe
            $rootProcesses += $proc
        }
    }

    if ($rootProcesses.Count -eq 0) {
        Write-LogMessage "No root '$($ProcessName)' process identified -- killing all $($totalCount) individually" -Level WARN
        $rootProcesses = $processes
    }
    else {
        Write-LogMessage "Identified $($rootProcesses.Count) root process(es) out of $($totalCount) total" -Level INFO
    }

    # ── Step 2: Kill each root tree ──────────────────────────────────────────
    foreach ($root in $rootProcesses) {
        if (-not (Get-Process -Id $root.Id -ErrorAction SilentlyContinue)) {
            Write-LogMessage "PID $($root.Id) already terminated by earlier tree kill" -Level DEBUG
            continue
        }
        $title = if ($root.MainWindowTitle) { $root.MainWindowTitle } else { "(no window)" }
        Write-LogMessage "Killing '$($ProcessName)' tree: PID $($root.Id) ($($title))" -Level INFO
        # /T = terminate child processes, /F = force
        & taskkill /T /F /PID $root.Id 2>&1 | Out-Null
    }

    # ── Step 3: Straggler sweep ──────────────────────────────────────────────
    Start-Sleep -Seconds 2
    $remaining = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($remaining) {
        $remCount = @($remaining).Count
        Write-LogMessage "$($remCount) '$($ProcessName)' process(es) survived tree kill -- force killing individually" -Level WARN
        foreach ($straggler in $remaining) {
            if (Get-Process -Id $straggler.Id -ErrorAction SilentlyContinue) {
                Write-LogMessage "  Killing straggler PID $($straggler.Id)" -Level DEBUG
                Stop-Process -Id $straggler.Id -Force -ErrorAction SilentlyContinue
            }
        }
        Start-Sleep -Seconds 1
    }

    # ── Step 4: Final verification (last resort: kill by image name) ─────────
    $final = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($final) {
        $finalCount = @($final).Count
        Write-LogMessage "$($finalCount) '$($ProcessName)' process(es) could not be killed -- trying image name kill" -Level ERROR
        & taskkill /F /IM $imageName 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        $final = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    }

    $survivorCount = if ($final) { @($final).Count } else { 0 }
    $killedCount = $totalCount - $survivorCount

    if ($survivorCount -gt 0) {
        Write-LogMessage "$($survivorCount) '$($ProcessName)' process(es) STILL running after all kill attempts" -Level ERROR
    }
    else {
        Write-LogMessage "All $($totalCount) '$($ProcessName)' process(es) terminated successfully" -Level INFO
    }

    return [PSCustomObject]@{
        ProcessName   = $ProcessName
        InitialCount  = $totalCount
        RootCount     = $rootProcesses.Count
        KilledCount   = $killedCount
        SurvivorCount = $survivorCount
        Success       = ($survivorCount -eq 0)
    }
}

function Close-ExplorerWindows {
    <#
    .SYNOPSIS
        Closes all open File Explorer windows without killing the shell process.

    .DESCRIPTION
        Uses the COM Shell.Application object to enumerate and close only File Explorer
        folder windows. The main explorer.exe shell process (taskbar, desktop, Start menu)
        is left untouched.

        Returns a PSCustomObject with the result.

    .EXAMPLE
        Close-ExplorerWindows
        # Closes all open File Explorer folder windows.

    .EXAMPLE
        $result = Close-ExplorerWindows
        if ($result.ClosedCount -gt 0) { Write-Host "Closed $($result.ClosedCount) windows" }
    #>
    [CmdletBinding()]
    param()

    try {
        $shell = New-Object -ComObject Shell.Application
        $explorerWindows = @($shell.Windows())

        if ($explorerWindows.Count -eq 0) {
            Write-LogMessage "No File Explorer windows open" -Level INFO
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
            return [PSCustomObject]@{
                ClosedCount = 0
                Success     = $true
            }
        }

        $windowCount = $explorerWindows.Count
        Write-LogMessage "Closing $($windowCount) File Explorer window(s)" -Level INFO

        $closedCount = 0
        foreach ($win in $explorerWindows) {
            try {
                $win.Quit()
                $closedCount++
            } catch {
                Write-LogMessage "Failed to close Explorer window: $($_.Exception.Message)" -Level DEBUG
            }
        }

        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        Write-LogMessage "Closed $($closedCount) of $($windowCount) File Explorer window(s)" -Level INFO

        return [PSCustomObject]@{
            ClosedCount = $closedCount
            Success     = ($closedCount -eq $windowCount)
        }
    }
    catch {
        Write-LogMessage "Failed to close File Explorer windows: $($_.Exception.Message)" -Level WARN
        return [PSCustomObject]@{
            ClosedCount = 0
            Success     = $false
        }
    }
}

Export-ModuleMember -Function *

