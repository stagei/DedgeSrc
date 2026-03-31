Import-Module -Name GlobalFunctions -Force
try {
    Write-LogMessage  $(Get-InitScriptName) -Level JOB_STARTED
    $localDedgeCommonFolder = Find-ExistingFolder -Name "DedgeCommon"
    # Zip the folder using filename computername_date_time.zip
    $appDataFolder = Get-ApplicationDataPath
    $zipFileName = "$env:COMPUTERNAME_$(Get-Date -Format "yyyyMMdd-HHmmss").zip"
    $zipFilePath = Join-Path $appDataFolder $zipFileName
    if (-not (Test-Path $zipFilePath -PathType Leaf)) {
        New-Item -Path $zipFilePath -ItemType File -Force | Out-Null
    }

    $configfilesFolder = Join-Path $localDedgeCommonFolder "Configfiles"
    Compress-Archive -Path $configfilesFolder -DestinationPath $zipFilePath -Force

    Write-LogMessage "Successfully zipped $configfilesFolder to $zipFilePath" -Level INFO

    # Remove files in the folder older than 10 days
    $filesToRemove = Get-ChildItem -Path $appDataFolder -Recurse -File -Filter "*.zip" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-10) } | Select-Object -Property Name, FullName, LastWriteTime
    foreach ($file in $filesToRemove) {
        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Successfully removed old DedgeCommon ConfigFiles backup file $($file.Name) with last write time $($file.LastWriteTime)" -Level INFO
    }
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    Exit 9
}

