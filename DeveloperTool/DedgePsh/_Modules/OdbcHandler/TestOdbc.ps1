# Define the OdbcHandler function

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
    try {
        $bitType = Load-RequiredAssembly -odbcConnectionName $odbcConnectionName
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
        } else {
            $pathsToCheck = $registryPaths
        }

        # Check each registry path
        foreach ($bitType in $pathsToCheck.Keys) {
            $registryPath = $pathsToCheck[$bitType]

            # Check if the DSN exists in the registry
            if (Test-Path -Path "$registryPath\$Name") {
                # Get all properties for the DSN
                $properties = Get-ItemProperty -Path "$registryPath\$Name"

                # Create base connection info
                $connectionInfo = @{
                    Name = $Name
                    Type = $bitType
                    Path = "$registryPath\$Name"
                    Driver = $properties.Driver
                    LastModified = (Get-Item "$registryPath\$Name").LastWriteTime
                    Properties = @{}
                }

                # Add all registry properties to the Properties hashtable
                $properties.PSObject.Properties | ForEach-Object {
                    if ($_.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSProvider')) {
                        $connectionInfo.Properties[$_.Name] = $_.Value
                    }
                }

                # Get driver information
                $driverPath = "$registryPath\..\ODBCINST.INI\$($properties.Driver -replace '.*\\(.+)$','$1')"
                if (Test-Path $driverPath) {
                    $driverProperties = Get-ItemProperty -Path $driverPath
                    $connectionInfo.DriverInfo = @{
                        Path = $driverPath
                        Properties = @{}
                    }
                    $driverProperties.PSObject.Properties | ForEach-Object {
                        if ($_.Name -notin @('PSPath', 'PSParentPath', 'PSChildName', 'PSProvider')) {
                            $connectionInfo.DriverInfo.Properties[$_.Name] = $_.Value
                        }
                    }
                }

                return $connectionInfo
            }
        }

        # If we get here, no matching connection was found
        return $null
    }
    catch {
        Write-Error "Error checking ODBC connections: $_"
        return $null
    }
}

function New-OdbcConnection {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateSet("32-bit", "64-bit", "32/64-bit")]
        [string]$Type = "64-bit",

        [Parameter(Mandatory = $false)]
        [hashtable]$Properties = @{}
    )

    try {
        # Registry paths for ODBC connections
        $registryPaths = @{
            '32-bit' = 'HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBC.INI'
            '64-bit' = 'HKLM:\SOFTWARE\ODBC\ODBC.INI'
        }

        # For DB2 specifically
        $db2Driver = "IBM DB2 ODBC DRIVER - DB2COPY1"
        $db2DriverPath = "C:\WINDOWS\system32\DB2COPY1\bin\db2cli64.dll"

        # If mixed mode (32/64-bit), create in both locations
        if ($Type -eq "32/64-bit") {
            foreach ($regPath in $registryPaths.Values) {
                # Create the DSN registry key
                $dsnPath = "$regPath\$Name"
                if (!(Test-Path $dsnPath)) {
                    New-Item -Path $dsnPath -Force | Out-Null
                }

                # Set the driver
                Set-ItemProperty -Path $dsnPath -Name "Driver" -Value $db2DriverPath

                # Set additional properties
                foreach ($prop in $Properties.GetEnumerator()) {
                    Set-ItemProperty -Path $dsnPath -Name $prop.Key -Value $prop.Value
                }

                # Add to ODBC Data Sources list
                $sourcesPath = "$regPath\ODBC Data Sources"
                Set-ItemProperty -Path $sourcesPath -Name $Name -Value $db2Driver
            }
        }
        else {
            # Single architecture mode
            $regPath = $registryPaths[$Type]
            $dsnPath = "$regPath\$Name"

            if (!(Test-Path $dsnPath)) {
                New-Item -Path $dsnPath -Force | Out-Null
            }

            Set-ItemProperty -Path $dsnPath -Name "Driver" -Value $db2DriverPath
            foreach ($prop in $Properties.GetEnumerator()) {
                Set-ItemProperty -Path $dsnPath -Name $prop.Key -Value $prop.Value
            }

            $sourcesPath = "$regPath\ODBC Data Sources"
            Set-ItemProperty -Path $sourcesPath -Name $Name -Value $db2Driver
        }

        Write-Output "ODBC DSN '$Name' created successfully"
    }
    catch {
        Write-Error "Error creating ODBC connection: $_"
    }
}

function New-OdbcUserConnection {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [ValidateSet("32-bit", "64-bit", "32/64-bit")]
        [string]$Type = "32/64-bit"
    )

    try {
        # Registry paths for User ODBC connections (notice HKCU instead of HKLM)
        $registryPaths = @{
            '32-bit' = 'HKCU:\SOFTWARE\WOW6432Node\ODBC\ODBC.INI'
            '64-bit' = 'HKCU:\SOFTWARE\ODBC\ODBC.INI'
        }

        # For DB2 specifically
        $db2Driver = "IBM DB2 ODBC DRIVER - DB2COPY1"
        $db2Properties = @{
            "Driver" = "IBM DB2 ODBC DRIVER - DB2COPY1"
            "Database" = "COBDOK"
            "Protocol" = "TCPIP"
            "Hostname" = "t-no1fkmtst-db.DEDGE.fk.no"
            "Port" = "3710"
            "Description" = "DB2 COBDOK Connection"
        }

        # If mixed mode (32/64-bit), create in both locations
        if ($Type -eq "32/64-bit") {
            foreach ($regPath in $registryPaths.Values) {
                # Create the DSN registry key
                $dsnPath = "$regPath\$Name"
                if (!(Test-Path $dsnPath)) {
                    New-Item -Path $dsnPath -Force | Out-Null
                }

                # Set all DB2 properties
                foreach ($prop in $db2Properties.GetEnumerator()) {
                    Set-ItemProperty -Path $dsnPath -Name $prop.Key -Value $prop.Value
                }

                # Add to ODBC Data Sources list
                $sourcesPath = "$regPath\ODBC Data Sources"
                if (!(Test-Path $sourcesPath)) {
                    New-Item -Path $sourcesPath -Force | Out-Null
                }
                Set-ItemProperty -Path $sourcesPath -Name $Name -Value $db2Driver
            }
        }
        else {
            # Single architecture mode
            $regPath = $registryPaths[$Type]
            $dsnPath = "$regPath\$Name"

            if (!(Test-Path $dsnPath)) {
                New-Item -Path $dsnPath -Force | Out-Null
            }

            foreach ($prop in $db2Properties.GetEnumerator()) {
                Set-ItemProperty -Path $dsnPath -Name $prop.Key -Value $prop.Value
            }

            $sourcesPath = "$regPath\ODBC Data Sources"
            if (!(Test-Path $sourcesPath)) {
                New-Item -Path $sourcesPath -Force | Out-Null
            }
            Set-ItemProperty -Path $sourcesPath -Name $Name -Value $db2Driver
        }

        Write-Output "User ODBC DSN '$Name' created successfully"
    }
    catch {
        Write-Error "Error creating ODBC connection: $_"
        throw $_
    }
}

try {

   $createScript = GetOdbcConnectionCreateScript -odbcConnectionName "COBDOK"
   Write-Output $createScript

    # Load the ADO.NET assembly for ODBC
    Add-Type -AssemblyName System.Data

    # Create a new ODBC connection object
    $connectionString = "DSN=$dbName;Uid=;Pwd=;"
    $connection = New-Object System.Data.Odbc.OdbcConnection($connectionString)

    # Load the ADO.NET assembly for ODBC
    Add-Type -AssemblyName "System.Data, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089"

    # Define connection parameters
    $dbName = "COBDOK"  # Specify your database name
    $uid = ""  # Specify your username
    $pwd = ""  # Specify your password

    # Create a new ODBC connection object
    $connectionString = "DSN=$dbName;Uid=$uid;Pwd=$pwd;"
    $connection = New-Object System.Data.Odbc.OdbcConnection($connectionString)

    # Open the connection
    $connection.Open()

    # Begin a transaction
    $transaction = $connection.BeginTransaction()

    # Define the SQL command to insert static values
    $sql = "SELECT * FROM DBM.MODUL"

    # Create an ODBC command and associate it with the transaction
    $command = $connection.CreateCommand()
    $command.Transaction = $transaction
    $command.CommandText = $sql

    $result = $command.ExecuteReaderAsync()

    # Commit the transaction
    $transaction.Commit()
    Write-Output "Transaction committed and rows inserted successfully."
}
catch {
    Write-Error "Error occurred: $_"
    # Rollback the transaction if there is an error
    if ($transaction -ne $null) {
        $transaction.Rollback()
        Write-Output "Transaction rolled back due to an error."
    }
}
finally {
    # Always close the connection
    $connection.Close()
    # Dispose of the ODBC connection object
    if ($connection -ne $null) {
        $connection.Dispose()
    }
}

