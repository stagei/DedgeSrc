Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force

function Save-LatestPwshDownload {
    try {
        $appId = "Microsoft.PowerShell"
        $wingetPath = Get-CommandPathWithFallback -Name "winget"
        if ($wingetPath -eq "winget") {
            Write-LogMessage "winget not found, cannot download latest $($appId)" -Level WARN
            return
        }

        $downloadRoot = Get-WingetAppsPath
        if (-not (Test-Path $downloadRoot -PathType Container)) {
            New-Item -Path $downloadRoot -ItemType Directory -Force | Out-Null
        }

        $subfolder = Join-Path $downloadRoot $appId
        $versionFile = Join-Path $subfolder "version.txt"

        $showOutput = & $wingetPath show --id $appId --exact 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "Failed to query latest version for $($appId): $($showOutput -join "`n")" -Level WARN
            return
        }

        $latestVersion = ($showOutput | Select-String -Pattern "^\s*Version:\s*(.+)$").Matches.Groups[1].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($latestVersion)) {
            Write-LogMessage "Could not read latest version for $($appId), skipping dedicated download step" -Level WARN
            return
        }

        $currentVersion = ""
        if (Test-Path $versionFile -PathType Leaf) {
            $currentVersion = (Get-Content -Path $versionFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        }

        if ((Test-Path $subfolder -PathType Container) -and ($currentVersion -eq $latestVersion)) {
            Write-LogMessage "Latest $($appId) already downloaded (version $($latestVersion))" -Level INFO
            return
        }

        if (Test-Path $subfolder -PathType Container) {
            Remove-Item -Path $subfolder -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
        New-Item -Path $subfolder -ItemType Directory -Force | Out-Null

        Write-LogMessage "Downloading latest $($appId) version $($latestVersion) to $($subfolder)" -Level INFO
        $downloadOutput = & $wingetPath download --id $appId --exact --download-directory $subfolder 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-LogMessage "Failed downloading $($appId): $($downloadOutput -join "`n")" -Level ERROR
            return
        }

        Set-Content -Path $versionFile -Value $latestVersion -Force
        Write-LogMessage "Downloaded latest $($appId) version $($latestVersion)" -Level INFO
    }
    catch {
        Write-LogMessage "Save-LatestPwshDownload failed: $($_.Exception.Message)" -Level ERROR -Exception $_
    }
}

Save-LatestPwshDownload
Start-WingetDownload
Start-VsixDownload
Get-CursorInstaller
Get-VSCodeInstaller
Get-OllamaModels

# Generate comprehensive software inventory report
Get-SoftwareInventory
    