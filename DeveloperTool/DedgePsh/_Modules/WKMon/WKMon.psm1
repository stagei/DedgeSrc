# WKMon.psm1
# Hjelperutine for å sende meldinger til WKMonitor
#
# Changelog:
# ------------------------------------------------------------------------------
# 20211202 fksveeri Første versjon
# 20240115 fkgeista Laget powershell modul av scriptet
# ------------------------------------------------------------------------------
Import-Module -Name Logger

<#
.SYNOPSIS
    Sends messages to WKMonitor.

.DESCRIPTION
    Creates and writes monitoring messages to a file for WKMonitor system.
    The messages include timestamp, program name, code, computer name, and custom message.
    Files are written with specific naming convention and location based on the computer.

.PARAMETER program
    The name of the program or application generating the message.

.PARAMETER kode
    A code identifier for the message type or category.

.PARAMETER melding
    The actual message content to be logged.

.EXAMPLE
    WKMon -program "MyApp" -kode "ERR001" -melding "Process failed"
    # Creates a monitoring file with the error message

.EXAMPLE
    WKMon -program "Backup" -kode "INFO" -melding "Backup completed successfully"
    # Logs a success message to WKMonitor
#>
function WKMon {
    param (
        [string] $program,
        [string] $kode,
        [string] $melding
    )

    $wkmonpath = ".\" 
    # Fixed: Use case-insensitive comparison for computer name
    if ($Env:Computername.ToUpper().Contains("P-NO1FKMPRD-APP")) {
        $wkmonpath = "\\DEDGE.fk.no\erpprog\cobnt\monitor\"
    }

    $wkmon = (Get-Date -format ("yyyyMMddHHmmss")) + " " + $program + " " + $kode + " " + $Env:Computername + ": " + $melding
    Logger -message $wkmon
    $wkmonfilename = $wkmonpath + $Env:Computername + (get-date -format("yyyyMMddHHmmss")) + ".MON"
    Out-File -Encoding ascii -FilePath $wkmonfilename -InputObject ($wkmon).ToString()
}


Export-ModuleMember -Function WKMon