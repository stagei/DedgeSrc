Import-Module GlobalFunctions -Force

$ErrorActionPreference = "Stop"

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED

    $excludedPathPatterns = @(
        "*_old*",
        "*_UNSORTED MISC FILES*",
        "*_UNSORTED MISC F9ILES*",
        "*DEPRECATED*"
    )

    $deployScripts = Get-ChildItem -Path $PSScriptRoot -Recurse -Filter "_deploy.ps1" -File |
        Where-Object { $_.FullName -ne $PSCommandPath } |
        Where-Object {
            $include = $true
            foreach ($pattern in $excludedPathPatterns) {
                if ($_.FullName -like $pattern) {
                    $include = $false
                    break
                }
            }
            $include
        } |
        Sort-Object FullName

    if ($deployScripts.Count -eq 0) {
        Write-LogMessage "No _deploy.ps1 scripts found under $($PSScriptRoot)." -Level WARN
        Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
        return
    }

    Write-LogMessage "Found $($deployScripts.Count) _deploy.ps1 scripts. Running each script directly." -Level INFO

    $failedScripts = @()
    foreach ($scriptFile in $deployScripts) {
        try {
            Write-LogMessage "Running $($scriptFile.FullName)" -Level INFO
            & $scriptFile.FullName
            Write-LogMessage "Completed $($scriptFile.FullName)" -Level INFO
        }
        catch {
            Write-LogMessage "Failed $($scriptFile.FullName): $($_.Exception.Message)" -Level ERROR -Exception $_
            $failedScripts += $scriptFile.FullName
        }
    }

    if ($failedScripts.Count -gt 0) {
        Write-LogMessage "One or more _deploy.ps1 scripts failed:" -Level ERROR
        Write-LogMessage ($failedScripts | ForEach-Object { " - $($_)" } | Out-String) -Level ERROR
        throw "Deploy script execution failed for $($failedScripts.Count) script(s)."
    }

    Write-LogMessage "All _deploy.ps1 scripts completed successfully." -Level INFO
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error in run-deploy-scripts-only script: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
