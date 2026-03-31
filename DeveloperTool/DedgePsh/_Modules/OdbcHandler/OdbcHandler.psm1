<#
.SYNOPSIS
    Provides ODBC connection management and database query execution functionality.

.DESCRIPTION
    This module provides utilities for working with ODBC connections, including retrieving
    connection information from the registry, executing SQL queries and non-query commands,
    and dynamically loading required assemblies based on the ODBC connection type.

.EXAMPLE
    $result = ExecuteQuery -sqlStatement "SELECT * FROM Users" -odbcConnectionName "BASISPRO"
    # Executes a SELECT query and returns results as PSObjects

.EXAMPLE
    $connection = Get-OdbcConnection -Name "MyDSN" -Type "64-bit"
    # Retrieves ODBC connection details from the registry
#>

<#
.SYNOPSIS
    Generates a create script for an ODBC connection.

.DESCRIPTION
    Creates a PowerShell command string that can recreate the specified ODBC connection.

.PARAMETER odbcConnectionName
    The name of the ODBC connection to generate a create script for.

.EXAMPLE
    $script = GetOdbcConnectionCreateScript -odbcConnectionName "BASISPRO"
    # Returns a New-OdbcConnection command string
#>
function GetOdbcConnectionCreateScript {
    param (
        [Parameter(Mandatory = $true)]
        [string]$odbcConnectionName
    )

    $odbcConnection = Get-OdbcConnection -Name $odbcConnectionName

    $createScript = "New-OdbcConnection -Name $($odbcConnection['Name']) -Type $($odbcConnection['Type']) -Path $($odbcConnection['Path'])"

    return $createScript
}
# We'll load assemblies dynamically based on the ODBC connection type
function Load-RequiredAssembly {
    param (
        [Parameter(Mandatory = $true)]
        [string]$odbcConnectionName
    )
    
    # Check if the ODBC connection is present
    $odbcConnection = Get-OdbcConnection -Name $odbcConnectionName
    if ($null -eq $odbcConnection) {
        
        throw "ODBC connection '$odbcConnectionName' not found"
    }
    
    
    # Determine bit type and load appropriate assembly 
    switch ($odbcConnection['Type']) {
        "64-bit" {
            Add-Type -AssemblyName System.Data
            Add-Type -AssemblyName "System.Data, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089"
        }
        "32-bit" {
            Add-Type -AssemblyName System.Data
            Add-Type -AssemblyName "System.Data, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089"
        }
        default {
            throw "Unable to determine ODBC connection type"
        }
    }
}

function ExecuteNonQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$sqlStatement,
        [Parameter(Mandatory = $false)]
        [string]$odbcConnectionName = "BASISPRO",
        [Parameter(Mandatory = $false)]
        [string]$uid = "",
        [Parameter(Mandatory = $false)]
        [string]$pwd = ""
    )
    $rowsAffected = 0

    # Load appropriate assembly based on ODBC connection type
    try {
        Load-RequiredAssembly -odbcConnectionName $odbcConnectionName
    }
    catch {
        throw $_
    }

    # Create a new ODBC connection object
    $connectionString = "DSN=$odbcConnectionName;Uid=$uid;Pwd=$pwd;"
    $connection = New-Object System.Data.Odbc.OdbcConnection($connectionString)

    try {
        # Open the connection
        $connection.Open()

        # Begin a transaction
        $transaction = $connection.BeginTransaction()

        # Create an ODBC command and associate it with the transaction
        $command = $connection.CreateCommand()
        $command.Transaction = $transaction
        $command.CommandText = $sqlStatement

        # Execute the query
        $rowsAffected = $command.ExecuteNonQuery()

        # Commit the transaction
        $transaction.Commit()
        Write-Output "Transaction committed and rows inserted successfully."
    }
    catch {
        Write-Error "Error occurred: $_"
        # Rollback the transaction if there is an error
        if ($null -ne $transaction) {
            $transaction.Rollback()
            Write-Output "Transaction rolled back due to an error."
        }
    }
    finally {
        # Always close the connection
        $connection.Close()
    }

    # Dispose of the ODBC connection object
    if ($null -ne $connection) {
        $connection.Dispose()
    }
    return $rowsAffected
}

function ExecuteQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$sqlStatement,
        [Parameter(Mandatory = $false)]
        [string]$odbcConnectionName = "BASISPRO",
        [Parameter(Mandatory = $false)]
        [string]$uid = "",
        [Parameter(Mandatory = $false)]
        [string]$pwd = ""
    )
    # Initialize the list to store PSObjects
    $returnPsObjectList = New-Object System.Collections.ArrayList
    # Load appropriate assembly based on ODBC connection type
    # $bitType = Load-RequiredAssembly -odbcConnectionName $odbcConnectionName

    # try {
    #     $bitType = Load-RequiredAssembly -odbcConnectionName $odbcConnectionName
    # }
    # catch {
    #     try {
    #         $modulesToImport = @("GlobalFunctions", "Db2-Handler")
    # foreach ($moduleName in $modulesToImport) {
    #     $loadedModule = Get-Module -Name $moduleName
    #     if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
    #       Write-LogMessage "Importing module: $moduleName" -Level INFO
    #       Import-Module $moduleName -Force
    #     }
    #     else {
    #       Write-LogMessage "Module $moduleName already loaded" -Level INFO
    #     }
    #   } 
    #         $autoCatalogPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientConfig\Kerberos\Catalog-Script-For-Azure-Db2-Database-$($odbcConnectionName)-Using-Kerberos-For-Odbc.bat"           
    #         Invoke-DB2ScriptCommand -Command $autoCatalogPath -IgnoreErrors $true
    #         $bitType = Load-RequiredAssembly -odbcConnectionName $odbcConnectionName
    #     }
    #     catch {
    #         throw $_
    #     }
    # }

    # Create a new ODBC connection object
    $connectionString = "DSN=$odbcConnectionName;Uid=$uid;Pwd=$pwd;"
    $connection = New-Object System.Data.Odbc.OdbcConnection($connectionString)

    try {
        # Open the connection
        $connection.Open()

        # Create an ODBC command and associate it with the transaction
        $command = $connection.CreateCommand()
        $command.CommandText = $sqlStatement

        # Execute the query and extract result into object
        $adapter = New-Object System.Data.Odbc.OdbcDataAdapter($command)
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataset) 

        # Process each row in the DataTable
        foreach ($row in $dataset.Tables[0].Rows) {
            $psObj = New-Object PSObject
            # Process each column in the DataTable
            foreach ($col in $dataset.Tables[0].Columns) {
                $psObj | Add-Member -NotePropertyName $col.ColumnName -NotePropertyValue $row[$col]
            }
            # Add the fully built PSObject to the list
            $returnPsObjectList.Add($psObj) | Out-Null
        } 
    }
    catch {
        Write-Error "Error occurred: $_"
        throw $_
    }
    finally {
        # Always close the connection
        $connection.Close()
    }

    # Dispose of the ODBC connection object
    if ($null -ne $connection) {
        $connection.Dispose()
    }
    # Return the list of PSObjects
    return $returnPsObjectList		
}

function Get-OdbcConnection {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("32-bit", "64-bit")]
        [string]$Type
    )

    try {
        # Registry paths for ODBC connections
        $registryPaths = @{
            '32-bit' = 'HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBC.INI'
            '64-bit' = 'HKLM:\SOFTWARE\ODBC\ODBC.INI'
        }

        # If Type is specified, only check that specific registry path
        if ($Type) {
            $pathsToCheck = @{ $Type = $registryPaths[$Type] }
        }
        else {
            $pathsToCheck = $registryPaths
        }

        # Check each registry path
        foreach ($bitType in $pathsToCheck.Keys) {
            $registryPath = $pathsToCheck[$bitType]
            
            # Check if the DSN exists in the registry
            if (Test-Path -Path "$registryPath\$Name") {
                $result = [PSCustomObject]@{
                    Name = $Name
                    Type = $bitType
                    Path = "$registryPath\$Name"
                }
            }
            # Get all properties from result.Path in registry as hashtable
            $result.Path | Get-ItemProperty | ForEach-Object {
                $result | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force
            }
            return $result
        }

        # If we get here, no matching connection was found
        return $null
    }
    catch {
        Write-Error "Error checking ODBC connections: $_"
        return $null
    }
}

# Export the function so it's available when the module is imported
Export-ModuleMember -Function Get-OdbcConnection
Export-ModuleMember -Function GetOdbcConnectionCreateScript
Export-ModuleMember -Function ExecuteNonQuery
Export-ModuleMember -Function ExecuteQuery
