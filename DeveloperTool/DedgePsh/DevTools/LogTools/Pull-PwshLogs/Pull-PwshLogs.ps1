Import-Module GlobalFunctions -Force
# FkLog_20251030.log
$dateArray = @()
$dateArray += (Get-Date).ToString('yyyyMMdd')
$dateArray += (Get-Date).AddDays(-1).ToString('yyyyMMdd')
$dateArray += (Get-Date).AddDays(-2).ToString('yyyyMMdd')
$dateArray += (Get-Date).AddDays(-3).ToString('yyyyMMdd')
$dateArray += (Get-Date).AddDays(-4).ToString('yyyyMMdd')
$dateArray += (Get-Date).AddDays(-5).ToString('yyyyMMdd')
$dateArray += (Get-Date).AddDays(-6).ToString('yyyyMMdd')
$dateArray += (Get-Date).AddDays(-7).ToString('yyyyMMdd')
$promptMessage = "Choose Pwsh Log File     Date: "
$progressMessage = "Choose Pwsh log file date"
$date = Get-UserConfirmationWithTimeout -PromptMessage $promptMessage -TimeoutSeconds 30 -AllowedResponses $dateArray -ProgressMessage $progressMessage -ThrowOnTimeout
Write-LogMessage "Chosen Pwsh log file date: $date" -Level INFO

$appdataFolder = Get-ApplicationDataPath
# Remove all files in $appdataFolder
Remove-Item -Path $appdataFolder\* -Force
$computerNameList = Get-ValidServerNameList

$computerCount = $computerNameList.Count
$index = 0
foreach ($computerName in $computerNameList) {
    $index++
    Write-Progress -Activity "Pulling Pwsh Logs" -Status "Processing $computerName ($index/$computerCount)" -PercentComplete (($index / $computerCount) * 100)
    $uncPath = "\\$computerName\opt\data\AllPwshLog"
    $dateFile = "FkLog_$($date).log"
    $file = Join-Path $uncPath $dateFile
    if (Test-Path $file -PathType Leaf) {
        $destinationFile = Join-Path $appdataFolder $dateFile.Replace("FkLog_", "FkLog_$($computerName)_")
        Copy-Item -Path $file -Destination $destinationFile -Force
    }
}
Write-Progress -Activity "Pulling Pwsh Logs" -Completed -Status "Done"
# start code in search on folder $appdataFolder
$codeCmd = Get-CommandPathWithFallback -Name "Code"
Start-Process -FilePath $codeCmd -ArgumentList $appdataFolder

