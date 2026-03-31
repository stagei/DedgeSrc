# Import required modules
Import-Module GlobalFunctions -Force
Import-Module Infrastructure -Force
Import-Module Deploy-Handler -Force
# Main execution
try {
    Add-Db2DirectoryPermission
}
catch {
    Write-LogMessage "Fatal error occurred" -Level ERROR -Exception $_
    exit 1
}

