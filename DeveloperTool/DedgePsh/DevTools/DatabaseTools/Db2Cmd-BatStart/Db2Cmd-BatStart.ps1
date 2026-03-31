param (
    [Parameter(Mandatory = $true)]
    [string]$BatchFilePath,
    [Parameter(Mandatory = $false)]
    [string]$Db2CmdPath = "C:\Program Files (x86)\IBM\SQLLIB\BIN"
)

# Verify that the batch file exists
if (-not (Test-Path $BatchFilePath)) {
    Write-Error "Batch file not found: $BatchFilePath"
    exit 1
}

# Verify that DB2 command line processor exists
$db2CmdExe = Join-Path $Db2CmdPath "db2cmd.exe"
if (-not (Test-Path $db2CmdExe)) {
    Write-Error "DB2 command line processor not found: $db2CmdExe"
    exit 1
}

# Start the batch file using DB2 command line processor
Write-Host "Starting batch file: $BatchFilePath"
Write-Host "Using DB2 command processor: $db2CmdExe"

try {
    & $db2CmdExe /c $BatchFilePath
    Write-Host "Batch file execution completed"
}
catch {
    Write-Error "Failed to execute batch file: $($_.Exception.Message)"
    exit 1
}

