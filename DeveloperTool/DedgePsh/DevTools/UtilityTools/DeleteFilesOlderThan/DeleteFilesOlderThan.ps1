# delete files older than n days from parameter
# kjører foreløpig på vdi fkikt958 og ligger i $env:OptPath\DedgePshApps\rydd_cobdatalog og er satt opp i en scheduled task
# Usage: DeleteFilesOlderThan.ps1 -Path "C:\Temp" -Days 30
param(
    [string]$Path,
    [int]$Days
)
Import-Module -Name FKASendSMSDirect -Force

$Now = Get-Date
$LastWrite = $Now.AddDays(-$Days)

write-host "Searching for files in $Path older than $Days days : $LastWrite"

$fd = Get-ChildItem -Path $Path | Where-Object { $_.LastWriteTime -lt $LastWrite }
$filecount = $fd.Count
if ($filecount -eq 0) {
    write-host "No files found older than $Days days"
    exit
}
else {
    write-host "Found files older than $Days days: $filecount"
    write-host "Starting deletion..."

    foreach ($f in $fd) {
        $d = Get-Date
        write-host "$d : Deleting $f"
        Remove-Item -Path $f.FullName -Force
    }

    FKASendSMSDirect -receiver "+4795762742" -message "$filecount files older than $Days days has been deleted from $Path"
    # FKASendSMSDirect -receiver "+4797188358" -message "$fd.Count files older than $Days days has been deleted from $Path"

}

