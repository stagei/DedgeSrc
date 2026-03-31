# OdbcHandler Module

## Overview
The OdbcHandler module provides functionality for working with ODBC connections in PowerShell. It simplifies database operations by providing functions to execute SQL queries, manage ODBC connections, and handle database transactions.

## Exported Functions

### Get-OdbcConnection
Retrieves information about an ODBC connection from the Windows registry.

#### Parameters
- **Name**: The name of the ODBC connection (DSN) to retrieve.
- **Type**: Optional. The bit architecture of the ODBC driver. Valid values are "32-bit" or "64-bit".

#### Behavior
- Searches the Windows registry for the specified ODBC connection
- Checks both 32-bit and 64-bit registry paths unless a specific Type is specified
- Returns a hashtable with Name, Type, and Path properties if found
- Returns $null if the connection is not found

#### Examples
```powershell
# Get information about an ODBC connection
$connection = Get-OdbcConnection -Name "BASISPRO"

# Get information about a specific 32-bit ODBC connection
$connection = Get-OdbcConnection -Name "BASISPRO" -Type "32-bit"
```

### GetOdbcConnectionCreateScript
Generates a PowerShell script that can recreate an ODBC connection.

#### Parameters
- **odbcConnectionName**: The name of the ODBC connection to generate a script for.

#### Behavior
- Retrieves the ODBC connection information using Get-OdbcConnection
- Generates a PowerShell command string that can be used to recreate the connection
- Returns the script as a string

#### Examples
```powershell
# Generate a script to recreate an ODBC connection
$script = GetOdbcConnectionCreateScript -odbcConnectionName "BASISPRO"
# Returns: "New-OdbcConnection -Name BASISPRO -Type 64-bit -Path HKLM:\SOFTWARE\ODBC\ODBC.INI\BASISPRO"
```

### ExecuteNonQuery
Executes a SQL statement that doesn't return a result set (INSERT, UPDATE, DELETE, etc.).

#### Parameters
- **sqlStatement**: The SQL statement to execute.
- **odbcConnectionName**: Optional. The name of the ODBC connection to use. Default is "BASISPRO".
- **uid**: Optional. The username for the database connection.
- **pwd**: Optional. The password for the database connection.

#### Behavior
- Loads the appropriate assembly based on the ODBC connection type
- Creates an ODBC connection and executes the SQL statement within a transaction
- Automatically commits the transaction if successful or rolls back if an error occurs
- Returns the number of rows affected by the statement
- Always closes the connection, even if an error occurs

#### Examples
```powershell
# Execute an INSERT statement
$rowsAffected = ExecuteNonQuery -sqlStatement "INSERT INTO Users (Name, Email) VALUES ('John Doe', 'john@example.com')"

# Execute an UPDATE statement with a specific connection
$rowsAffected = ExecuteNonQuery -sqlStatement "UPDATE Products SET Price = 19.99 WHERE ID = 123" -odbcConnectionName "Inventory"

# Execute a DELETE statement with authentication
$rowsAffected = ExecuteNonQuery -sqlStatement "DELETE FROM Orders WHERE Status = 'Cancelled'" -odbcConnectionName "OrderSystem" -uid "admin" -pwd "password"
```

### ExecuteQuery
Executes a SQL query that returns a result set (SELECT).

#### Parameters
- **sqlStatement**: The SQL query to execute.
- **odbcConnectionName**: Optional. The name of the ODBC connection to use. Default is "BASISPRO".
- **uid**: Optional. The username for the database connection.
- **pwd**: Optional. The password for the database connection.

#### Behavior
- Loads the appropriate assembly based on the ODBC connection type
- Creates an ODBC connection and executes the SQL query
- Converts the result set into a collection of PowerShell objects
- Each row becomes a PSObject with properties named after the columns
- Always closes the connection, even if an error occurs
- Returns an ArrayList of PSObjects representing the query results

#### Examples
```powershell
# Execute a simple SELECT query
$results = ExecuteQuery -sqlStatement "SELECT * FROM Customers"

# Execute a query with a specific connection
$results = ExecuteQuery -sqlStatement "SELECT ProductID, Name, Price FROM Products WHERE Category = 'Electronics'" -odbcConnectionName "Inventory"

# Execute a query with authentication
$results = ExecuteQuery -sqlStatement "SELECT OrderID, CustomerID, OrderDate FROM Orders WHERE Status = 'Pending'" -odbcConnectionName "OrderSystem" -uid "admin" -pwd "password"

# Process the results
foreach ($row in $results) {
    Write-Host "Customer: $($row.CustomerName), Email: $($row.Email)"
}
```

## Usage Notes
- The module automatically handles database transactions for non-query operations
- Connections are properly disposed of even when errors occur
- The module supports both 32-bit and 64-bit ODBC drivers
- Default connection is "BASISPRO" if not specified 