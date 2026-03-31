Import-Module GlobalFunctions -Force

# Get the folder containing the script
$scriptFolder = $PSScriptRoot
$lastExecutionInfoFileName = $scriptFolder + "\CBLDialogSystemExport.dat"

# Define the folder path you want to check and create
$PSWorkPath = $env:PSWorkPath
$srcRootFolder = $PSWorkPath
$workFolder = "$PSWorkPath\CBLDialogSystemExport"
$DedgeFolder = $env:OptPath + "\work\DedgeRepository"

$DedgeCblFolder = $DedgeFolder + "\Dedge\cbl"
$outputFolder = "$PSWorkPath\CBLDialogSystemExport\Content"
$DedgeGsFolder = $DedgeFolder + "\Dedge\gs"

Remove-Item -Path $workFolder -Recurse -Force -ErrorAction SilentlyContinue

New-Item -Path $workFolder -ItemType Directory -ErrorAction SilentlyContinue
New-Item -Path $outputFolder -ItemType Directory -ErrorAction SilentlyContinue

Push-Location
Set-Location -Path $workFolder
$workFolder = (Get-Location).Path
Pop-Location

Push-Location
Set-Location -Path $srcRootFolder
$srcRootFolder = (Get-Location).Path
Pop-Location

Push-Location
Set-Location -Path $outputFolder
$outputFolder = (Get-Location).Path
Pop-Location
$global:logFolder = $outputFolder

$maxProductionDate = $null
if (Test-Path $lastExecutionInfoFileName -PathType Leaf) {
    $maxProductionDate = Get-Content -Path $lastExecutionInfoFileName
    # convert to date
    try {
        $maxProductionDate = [datetime]::ParseExact($maxProductionDate, "dd.MM.yyyy HH:mm:ss", $null)

    }
    catch {
        try {

            $maxProductionDate = [datetime]::ParseExact($maxProductionDate, "MM/dd/yyyy h:mm:ss tt", $null)
        }
        catch {
            $maxProductionDate = (get-date).Subtract((New-TimeSpan -Days (50 * 365)))
        }
    }
}
if ($null -eq $maxProductionDate) {
    $maxProductionDate = (get-date).Subtract((New-TimeSpan -Days (50 * 365)))
}
$maxProductionDate = (get-date).Subtract((New-TimeSpan -Days (50 * 365)))

# $descArray = Get-ChildItem -Path $DedgeGsFolder -Filter "*.gs" | Where-Object { $_.LastWriteTime.Date -gt $maxProductionDate }
$descArray = Get-ChildItem -Path $DedgeGsFolder -Filter "*.gs"
$counterFailed = 0
$counterOk = 0
$machineName = $env:COMPUTERNAME.ToLower()
foreach ($currentItemName in $descArray) {
    $counterOk++
    if ($currentItemName.Name.Contains("-") -or $currentItemName.Name.Contains("_") -or $currentItemName.Name.Contains(" ")) {
        Continue
    }
    $outputFile = $outputFolder + "\" + $currentItemName.Name.ToLower().Replace(".gs", ".imp")
    Remove-Item -Path $outputFile -Recurse -Force -ErrorAction SilentlyContinue
    # $command = '"' + "C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin\dswin.exe" + '"' + " /e " + $currentItemName.FullName + " " + $outputFolder + "\" + $currentItemName.Name.ToUpper().Replace(".gs", ".imp")
    # # run command in cmd.exe
    # # cmd.exe /c $command  > $null
    # LogMessage -message ("Executing command: " + $command)
    # cmd.exe /c $command

    $exePath = "C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin\dswin.exe"
    $impFile = $outputFolder + '\' + $currentItemName.Name.ToUpper().Replace(".gs", ".imp").Replace(".GS", ".IMP")
    $timeoutSeconds = 30
    
    # Start dswin.exe directly (not via cmd.exe) so we can track the actual process
    $process = Start-Process -FilePath $exePath -ArgumentList "/e `"$($currentItemName.FullName)`" `"$impFile`"" -PassThru -NoNewWindow
    
    # Wait for process with timeout
    $completed = $false
    try {
        $completed = $process.WaitForExit($timeoutSeconds * 1000)
    }
    catch {
        $completed = $false
    }
    
    if (-not $completed) {
        # Process exceeded timeout - likely stuck on a dialog box
        Write-LogMessage "Process exceeded $($timeoutSeconds)s timeout, killing dswin.exe for: $($currentItemName.Name)" -Level WARN
        
        # Kill the main process
        if (-not $process.HasExited) {
            try {
                $process | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            catch {
                # Ignore if already exited
            }
        }
        
        # Also kill any lingering dswin.exe processes that might be stuck
        Get-Process -Name "dswin" -ErrorAction SilentlyContinue | Where-Object {
            # Kill dswin processes that started around the same time (within 5 seconds)
            $_.StartTime -and (New-TimeSpan -Start $process.StartTime -End $_.StartTime).TotalSeconds -lt 5
        } | ForEach-Object {
            Write-LogMessage "Killing lingering dswin.exe process ID: $($_.Id)" -Level WARN
            $_ | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    # Check if the file exists
    if (Test-Path $outputFile -PathType Leaf) {
        Write-LogMessage "Exported: $($currentItemName.Name)" -Level INFO
    }
    else {
        $counterFailed++
        Write-LogMessage "Failed to export: $($currentItemName.Name)" -Level ERROR
        if ($counterFailed -gt 30) {
            Write-LogMessage "Too many errors, aborting. Check the Net Express licence on this machine." -Level ERROR
            Send-Sms -Receiver "4797188358" -Message "CBLDialogSystemExport.ps1 on $($machineName): Too many errors, aborting. Check the Net Express licence."
            break
        }
    }
}
$maxProductionDate = Get-Date
Remove-Item -Path $DedgeFolder -Recurse -Force -ErrorAction SilentlyContinue
Set-Content -Path $lastExecutionInfoFileName -Value $maxProductionDate.ToString()

