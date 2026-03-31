# powershell script for running a DB2 load job
# check for signal-file to start the process, remove the signal file when done

function Test-SignalFile{
    param(
        [string]$signalFilePath
    )
    if(Test-Path -Path $signalFilePath){
        return $true
    } else {
        return $false
    }
}


function Start-DB2Load(){
    # start a db2cmd.exe session and run "db2 -tvf dbbload.sql" and check the return code
   Write-Host "Starting DB2 load job..."

   $db2cmdPath = "db2cmd.exe" # must be in PATH
   $scriptPath = "E:\opt\src\DedgePsh\WKFAKT4\dbbload.sql"
   $process = Start-Process -FilePath $db2cmdPath -ArgumentList "/c db2 -tvf $scriptPath" -PassThru
   $process.WaitForExit()
   if($process.ExitCode -eq 0){
       Write-Host "DB2 load job completed successfully."
       New-S60SignalFile
   } else {
       Write-Host "DB2 load job failed with exit code $($process.ExitCode)."
   }
}

# \\DEDGE.fk.no\erpprog\cobnt\BHKORR_LOAD_FERDIG.SIGNAL
function New-S60SignalFile{
    New-Item -Path "\\DEDGE.fk.no\erpprog\cobnt\BHKORR_LOAD_FERDIG.SIGNAL" -ItemType File -Force
}

# \\DEDGE.fk.no\erpprog\cobnt\DBBKORR_FERDIG.SIGNAL
if(Test-SignalFile -signalFilePath "\\DEDGE.fk.no\erpprog\cobnt\DBBKORR_FERDIG.SIGNAL"){
    Start-DB2Load
    Write-Host "Removing signal file..."
    Remove-Item -Path "\\DEDGE.fk.no\erpprog\cobnt\DBBKORR_FERDIG.SIGNAL" -Force
}