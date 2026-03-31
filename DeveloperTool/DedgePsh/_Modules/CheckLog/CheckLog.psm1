# CheckLog.psm1
# Tar et programnavn (uten filnavnendelse) og sjekker rc-filen
#
# Changelog:
# ------------------------------------------------------------------------------
# 20211214 fksveeri Første versjon
# 20240115 fkgeista Laget powershell modul av scriptet
# ------------------------------------------------------------------------------

<#
.SYNOPSIS
    Provides program return code monitoring and logging functionality.

.DESCRIPTION
    This module monitors program execution by checking return code files (.rc) and logging
    the results. It integrates with the Logger system and WKMonitor for comprehensive
    program execution tracking. Designed for monitoring batch jobs and automated processes
    in the Dedge environment.

.EXAMPLE
    CheckLog -program "BatchJob01"
    # Checks the return code for BatchJob01 and logs any errors

.EXAMPLE
    CheckLog -program "DataProcessor"
    # Monitors DataProcessor execution and creates monitor files for non-zero return codes
#>

<#
.SYNOPSIS
    Checks a program's return code file and logs the results.

.DESCRIPTION
    Examines a program's .rc file in a specified network path to check its return code.
    If the return code is not "0000", or if the file is not found, logs an error message
    to both the Logger system and a monitor file. For successful executions (code "0000"),
    only logs to the Logger system.

.PARAMETER program
    The name of the program to check (without file extension).
    The function will look for a corresponding .rc file.

.EXAMPLE
    CheckLog -program "MyProgram"
    # Checks MyProgram.rc and logs any non-zero return codes

.NOTES
    - Return code files are expected to be in the format: XXXX[message]
      where XXXX is the 4-digit return code and [message] is optional text
    - Code "0000" indicates success
    - Code "0016" is used when the RC file is not found
    - Monitor files are created with timestamp and computer name
#>

function CheckLog {
    param (
        [string] $program
    )

    $rcpath = "\\DEDGE.fk.no\ERPProg\cobnt\"

    $rcfile = $rcpath + $program + ".rc"
    if (Test-Path $rcfile) {
        $rccontent = (Get-Content $rcfile)
        $kode = $rccontent.substring(0, 4)
        if ($kode -ne "0000") {
            $melding = $rccontent.substring(4, $rccontent.Length - 4)
    
            $wkmon = (Get-Date -format ("yyyyMMddHHmmss")) + " " + $program + " " + $kode + " " + $Env:Computername + ": " + $melding
            Logger -message $wkmon
        
            #$wkmonpath = ".\" 
            $wkmonpath = "\\DEDGE.fk.no\erpprog\cobnt\monitor\"
            $wkmonfilename = $wkmonpath + $Env:Computername + (get-date -format("yyyyMMddHHmmss")) + ".MON"
            Out-File -Encoding ascii -FilePath $wkmonfilename -InputObject ($wkmon).ToString()
        }
        else {
            Logger -message $rccontent
        }
    
    }
    else {
        $melding = "RC-file for " + $program + " ikke funnet!"
        $kode = "0016"
    
        $wkmon = (Get-Date -format ("yyyyMMddHHmmss")) + " " + $program + " " + $kode + " " + $Env:Computername + ": " + $melding
        Logger -message $wkmon
    
        $wkmonpath = "\\DEDGE.fk.no\erpprog\cobnt\monitor\"
        $wkmonfilename = $wkmonpath + $Env:Computername + (get-date -format("yyyyMMddHHmmss")) + ".MON"
        Out-File -Encoding ascii -FilePath $wkmonfilename -InputObject ($wkmon).ToString()
    }
}


Export-ModuleMember -Function CheckLog
