# CBLRun.psm1
# Kjøring av Dedge batch-modul med parametre med transcript-logging og sjekk av RC-fil
#
#
# Versjonshistorikk
# ----------------------------------------------------------------
# 20230110 fksveeri Første versjon
# 20230111 fksveeri Prodsatt
# 20231122 fkgeista Lagt til funksjon for å sjekke RC-fil og returnere true/false
# 20231123 fkgeista Lagt til override path for run.exe
# 20231124 fkgeista Lagt til funksjon for å sette pshRootPath og kjøre Set-Location og endret alle kall til powershell til å bruke pshRootPath som utgangspunkt
# 20240115 fkgeista Laget powershell modul av scriptet
# ----------------------------------------------------------------

$modulesToImport = @("GlobalFunctions", "Logger", "CheckLog")
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
    Provides COBOL program execution and monitoring functionality for Dedge batch modules.

.DESCRIPTION
    This module handles the execution of COBOL programs in the Dedge environment with comprehensive
    logging, transcript capture, and return code monitoring. It manages environment-specific paths,
    database connections, and provides utilities for checking program execution success. Designed
    for automated batch processing and program execution monitoring.

.EXAMPLE
    CBLRun -Programname "MYPROG" -Database "BASISPRO" -CBLParams @("param1", "param2")
    # Executes a COBOL program with monitoring and logging

.EXAMPLE
    $success = Test-RC -program "BATCHJOB"
    # Checks if a program executed successfully by examining its return code
#>

<#
.SYNOPSIS
    Sets the PowerShell root path based on the computer name.

.DESCRIPTION
    Determines and sets the appropriate PowerShell root path and DB2 database
    based on the current computer's name. Also changes the current directory
    to the determined path.

.EXAMPLE
    SetLocationPshRootPath
    # Sets global variables and changes directory based on computer name

.NOTES
    Sets the following global variables:
    - $global:pshRootpath: The root path for PowerShell scripts
    - $global:db2Database: The appropriate DB2 database for the environment
#>
function SetLocationPshRootPath {
    if ($env:COMPUTERNAME.ToUpper() -eq "P-NO1FKMPRD-APP") {
        $global:pshRootpath = "$env:OptPath\DedgePshApps\"
        $global:db2Database = "BASISPRO"
    }

    elseif ($env:COMPUTERNAME.ToUpper() -eq "T-NO1FKMTST-APP") {
        $global:pshRootpath = "$env:OptPath\DedgePshApps\"
        $global:db2Database = "BASISTST"
    }
    elseif (-not $(Test-IsServer)
    ) {
        $global:pshRootpath = "$env:OptPath\src\DedgePsh\"
        $global:db2Database = "FKAVDNT"
    }
    else {
        Log-Error "Unknown computername $($env:COMPUTERNAME)"
        exit
    }
    Set-Location -Path $pshRootpath
}
<#
.SYNOPSIS
    Gets the return code from a program's RC file.

.DESCRIPTION
    Reads a program's return code file and returns the first four characters,
    which represent the return code. Returns an error message if the file
    doesn't exist.

.PARAMETER program
    The name of the program to check (without file extension).

.EXAMPLE
    $rc = Get-RC -program "MyProgram"
    # Returns the return code from MyProgram.rc

.NOTES
    Returns "9999" with an error message if the RC file is not found.
#>
function Get-RC {
    param(
        $program
    )
    $prg = $rcPath + $program + ".rc"
    if (Test-Path -Path $prg) {
        $rccontent = get-content $prg
        return $rccontent.substring(0, 4)
    }
    else {
        return "9999 RC-fil for $prg finnes ikke!"
    }
}

<#
.SYNOPSIS
    Tests if a program's return code indicates success.

.DESCRIPTION
    Checks if a program's return code equals "0000", indicating successful execution.
    Returns true for success, false otherwise.

.PARAMETER program
    The name of the program to check (without file extension).

.EXAMPLE
    $success = Test-RC -program "MyProgram"
    # Returns $true if MyProgram.rc contains "0000"
#>
function Test-RC {
    param(
        $program
    )

    $rc = get-rc -program $program
    if ($rc -eq "0000") {
        return $true
    }
    else {
        return $false
    }
}

<#
.SYNOPSIS
    Runs a COBOL program with specified parameters and monitors its execution.

.DESCRIPTION
    Executes a COBOL program using the Micro Focus run.exe, with specified database
    and parameters. Logs the execution, captures output in a transcript file, and
    checks the return code for success.

.PARAMETER Programname
    The name of the COBOL program to run.

.PARAMETER Database
    The database to use. Must be one of: 'FKAVDNT', 'BASISPRO', 'BASISTST', 'BASISRAP'.

.PARAMETER CBLParams
    Additional parameters to pass to the COBOL program.

.EXAMPLE
    CBLRun -Programname "MYPROG" -Database "BASISPRO" -CBLParams @("param1", "param2")
    # Runs MYPROG with specified database and parameters

.NOTES
    - Creates a transcript file with .mfout extension
    - Checks return code after execution
    - Returns $true if execution was successful, $false otherwise
#>
function CBLRun {
    param(
        [Parameter(Mandatory)][string] $Programname,
        [Parameter(Mandatory)]
        [ValidateSet('FKAVDNT', 'BASISPRO', 'BASISTST', 'BASISRAP', 'BASISKAT', 'BASISFUT', 'BASISMIG', 'BASISVFT', 'BASISVFK', 'BASISPER', 'BASISSIT', 'FKKONTO', 'FKNTOTST', 'FKNTOTDEV')]
        [string] $Database,
        [string[]] $CBLParams
    )    

    $rcPath = "\\DEDGE.fk.no\erpprog\cobnt\"
    $programFile = $rcPath + $Programname
    $programArgs = '"RUN.exe ' + $programFile + ' ' + $Database + ' ' + $CBLParams + '"'
    $CblRunExecutionOk = $false
    
    $transcriptFile = $rcPath + $Programname + ".mfout" 
    Start-Transcript $transcriptFile -Append
    $msg = "Starter " + $programArgs
    Logger -message $msg
    
    Set-Location \\DEDGE.fk.no\erpprog\cobnt
    try {
        & run $Programname $Database $CBLParams    
    }
    catch {
        & "C:\Program Files (x86)\Micro Focus\Net Express 5.1\Base\Bin\run.exe" $Programname $Database $CBLParams
    }
    
    # Set-Location $env:OptPath\DedgePshApps\CBLRun
    Stop-Transcript
    Set-Location \\DEDGE.fk.no\erpprog\cobnt
    
    if (Test-RC -program $Programname) {
        SetLocationPshRootPath
        CheckLog -program $Programname
        $CblRunExecutionOk = $True
    }
    else {
        $msg = $Programname + ".RC <> 0000. Check RC-file."
        Logger -message $msg
        SetLocationPshRootPath
        CheckLog -program $Programname
        $CblRunExecutionOk = $False
    }
    return $CblRunExecutionOk
    
}
Export-ModuleMember -Function CBLRun
