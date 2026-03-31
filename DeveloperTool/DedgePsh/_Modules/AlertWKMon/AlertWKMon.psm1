<#
.SYNOPSIS
    Provides alert messaging functionality for the WKMonitor system.

.DESCRIPTION
    This module offers alert messaging capabilities for the WKMonitor system, allowing programs
    to send conditional alerts based on return codes. It integrates with the Logger system and
    creates monitor files for non-successful operations. Designed for automated monitoring and
    alerting in the Dedge environment.

.EXAMPLE
    AlertWKMon -program "BatchJob" -kode "ERR1" -melding "Database connection failed"
    # Sends an alert message to WKMonitor for a failed operation

.EXAMPLE
    AlertWKMon -program "DataSync" -kode "0000" -melding "Synchronization completed"
    # Logs success message without creating an alert file
#>

# AlertWKMon.psm1
# Hjelperutine for å sende meldinger til WKMonitor
#
# Changelog:
# ------------------------------------------------------------------------------
# 20211202 fksveeri Første versjon
# 20240115 fkgeista Laget powershell modul av scriptet
# ------------------------------------------------------------------------------
$modulesToImport = @("GlobalFunctions", "Logger")
foreach ($moduleName in $modulesToImport) {
  $loadedModule = Get-Module -Name $moduleName
  if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
    Import-Module $moduleName -Force
  }
  else {
    Write-Host "Module $moduleName already loaded" -ForegroundColor Yellow
  }
} 
 

<#
.SYNOPSIS
    Sends alert messages to WKMonitor based on return codes.

.DESCRIPTION
    Creates and writes monitoring alert messages to a file for the WKMonitor system.
    If the code is not "0000" (success), writes a detailed alert message including
    timestamp, program name, code, computer name, and custom message to both the
    Logger system and a monitor file. For successful codes, only logs to the Logger system.

.PARAMETER program
    The name of the program or application generating the alert.

.PARAMETER kode
    The return code. If not "0000", triggers an alert message.

.PARAMETER melding
    The actual message content to be logged.

.EXAMPLE
    AlertWKMon -program "MyApp" -kode "ERR1" -melding "Process failed"
    # Creates an alert monitor file with the error message

.EXAMPLE
    AlertWKMon -program "Backup" -kode "0000" -melding "Backup completed successfully"
    # Only logs to Logger system, no monitor file created

.NOTES
    Monitor files are created with format: [ComputerName][Timestamp].MON
    The path for monitor files varies based on the computer name:
    - For p-no1fkmprd-app: Network path
    - For others: Local path
#>
function AlertWKMon {
    param (
        [string] $program,
        [string] $kode,
        [string] $melding
    )
    
    if ($kode -ne "0000") {
    
        $wkmon = (Get-Date -format ("yyyyMMddHHmmss")) + " " + $program + " " + $kode + " " + $Env:Computername + ": " + $melding
        Logger -message ($wkmon)

        $wkmonpath = ".\" 
        if ($Env:Computername.ToUpper().StartsWith("P-NO1")) {
            $wkmonpath = "\\DEDGE.fk.no\erpprog\cobnt\monitor\"
        }
        
        $wkmonfilename = $wkmonpath + $Env:Computername + (get-date -format("yyyyMMddHHmmss")) + ".MON"
        Out-File -Encoding ascii -FilePath $wkmonfilename -InputObject ($wkmon).ToString()
    }
    else {
        Logger -message ($Env:Computername + " " + $melding)
    }
}


Export-ModuleMember -Function AlertWKMon
