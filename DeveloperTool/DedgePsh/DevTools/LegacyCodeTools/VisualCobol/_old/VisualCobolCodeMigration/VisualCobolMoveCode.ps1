function LogMessage {
    param(
        $message
    )
    $dtLog = get-date -Format("yyyyMMdd").ToString()
    $logfile = "\\DEDGE.fk.no\erpprog\cobnt\" + $dtLog + "_VisualCobolCodeMigration.log"
    $logfile1 = $global:logFolder + "\VisualCobolCodeMigration.log"
    $dt = get-date -Format("yyyy-MM-dd HH:mm:ss,ffff").ToString()

    $logmsg = $dt + ": VisualCobolCodeMigration :  " + $message

    Write-Host $logmsg
    Add-Content -Path $logfile -Value $logmsg
    Add-Content -Path $logfile1 -Value $logmsg
}

$PSWorkPath = $env:PSWorkPath
$StartPath = $$
$pos = $StartPath.LastIndexOf("\")
$StartPath = $StartPath.Substring(0, $pos + 1)
$DedgeFolder = "$PSWorkPath\VisualCobolCodeMigration\Dedge"
$global:logFolder = $StartPath

FKASendSMSDirect -receiver "+4797188358" -message "Move Code is starting. Moving all files to $VCPath"
LogMessage -message "Move Code is starting. Moving all files to $VCPath"

$folders = @("$VCPath\src", "$VCPath\src\cbl", "$VCPath\src\cbl\cpy", "$VCPath\src\cbl\cpy\sys\cpy", "$VCPath\src\cbl\imp", "$VCPath\src\rex", "$VCPath\src\bat")

foreach ($folder in $folders) {
    if (-not (Test-Path -Path $folder)) {
        New-Item -ItemType Directory -Path $folder | Out-Null
    }
}

Get-ChildItem -Path "$VCPath\src\cbl" -File | Remove-Item -Force
Get-ChildItem -Path "$VCPath\src\cbl\cpy" -File | Remove-Item -Force
Get-ChildItem -Path "$VCPath\src\cbl\cpy\sys\cpy" -File | Remove-Item -Force
Get-ChildItem -Path "$VCPath\src\cbl\imp" -File | Remove-Item -Force
Get-ChildItem -Path "$VCPath\src\rex" -File | Remove-Item -Force
Get-ChildItem -Path "$VCPath\src\bat" -File | Remove-Item -Force

Copy-Item -Path "$DedgeFolder\cbl\*.cbl" -Destination "$VCPath\src\cbl" -Force

Copy-Item -Path "$DedgeFolder\cpy\*.cpy" -Destination "$VCPath\src\cbl\cpy" -Force
Copy-Item -Path "$DedgeFolder\cpy\*.cpx" -Destination "$VCPath\src\cbl\cpy" -Force
Copy-Item -Path "$DedgeFolder\cpy\*.cpb" -Destination "$VCPath\src\cbl\cpy" -Force
Copy-Item -Path "$DedgeFolder\cpy\*.dcl" -Destination "$VCPath\src\cbl\cpy" -Force

Copy-Item -Path "$DedgeFolder\sys\cpy\*.cpy" -Destination "$VCPath\src\cbl\cpy\sys\cpy" -Force
Copy-Item -Path "$DedgeFolder\sys\cpy\*.cpx" -Destination "$VCPath\src\cbl\cpy\sys\cpy" -Force
Copy-Item -Path "$DedgeFolder\sys\cpy\*.cpb" -Destination "$VCPath\src\cbl\cpy\sys\cpy" -Force
Copy-Item -Path "$DedgeFolder\sys\cpy\*.dcl" -Destination "$VCPath\src\cbl\cpy\sys\cpy" -Force

Copy-Item -Path "$DedgeFolder\imp\*.*" -Destination "$VCPath\src\cbl\imp" -Force
Copy-Item -Path "$DedgeFolder\rexx\*.*" -Destination "$VCPath\src\rex" -Force
Copy-Item -Path "$DedgeFolder\rexx_prod\*.*" -Destination "$VCPath\src\rex" -Force
Copy-Item -Path "$DedgeFolder\bat\*.*" -Destination "$VCPath\src\bat" -Force
Copy-Item -Path "$DedgeFolder\bat_prod\*.*" -Destination "$VCPath\src\bat" -Force

FKASendSMSDirect -receiver "+4797188358" -message "Move Code is completed."
Set-Location -Path $StartPath
LogMessage -message "Move Code is completed."

