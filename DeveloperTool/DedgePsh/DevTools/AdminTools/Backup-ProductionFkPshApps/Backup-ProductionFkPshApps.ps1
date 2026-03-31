Import-Module -Name GlobalFunctions -Force
try {
    Write-LogMessage  $(Get-InitScriptName) -Level JOB_STARTED
    $localDedgePshAppsFolder = "$env:OptPath\DedgePshApps"
    # Zip the folder using filename computername_date_time.zip
    $appDataFolder = Get-ApplicationDataPath
    function Get-ZipFileName {

        try {
            return "$env:COMPUTERNAME_$(Get-Date -Format "yyyyMMdd-HHmmss").zip"
        }
        catch {
            Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
            return "$env:COMPUTERNAME_$(Get-Date -Format "yyyyMMdd-HHmmss").zip"
        }
    }
    $zipFileName = Get-ZipFileName
    $zipFilePath = Join-Path $appDataFolder $zipFileName
    if (-not (Test-Path $zipFilePath -PathType Leaf)) {
        New-Item -Path $zipFilePath -ItemType File -Force | Out-Null
    }

    Compress-Archive -Path $localDedgePshAppsFolder -DestinationPath $zipFilePath -Force

    Write-LogMessage "Successfully zipped $localDedgePshAppsFolder to $zipFilePath" -Level INFO

    # Remove files in the folder older than 10 days
    $filesToRemove = Get-ChildItem -Path $appDataFolder -Recurse -File -Filter "*.zip" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-10) } | Select-Object -Property Name, FullName, LastWriteTime
    foreach ($file in $filesToRemove) {
        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
        Write-LogMessage "Successfully removed old DedgePshApps backup file $($file.Name) with last write time $($file.LastWriteTime)" -Level INFO
    }
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    Exit 9
}

