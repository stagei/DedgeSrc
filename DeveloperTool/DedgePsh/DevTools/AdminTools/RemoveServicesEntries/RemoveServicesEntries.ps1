# Remove DB2 Service Entries from Windows Services File
# This script removes lines starting with "db2c_" from the services file
# while preserving all other entries and creating a backup

Import-Module -Name GlobalFunctions -Force
Import-Module -Name Infrastructure -Force

Remove-ServicesFromServiceFile -ServicesPattern "(DB2C_*|DB.*25000/tcp|DB.*37[0-2][0-9]/tcp|DB.*50(0[0-9][0-9]|100/tcp))" -ServicesPatternIsRegex -Force

