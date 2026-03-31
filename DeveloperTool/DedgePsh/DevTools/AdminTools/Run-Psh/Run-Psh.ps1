param (
    [Parameter(Mandatory = $false)]
    [string]$AppName = "",
    [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

# Add debugging output
Write-Host "Run-Psh.ps1 started" -ForegroundColor Cyan
Write-Host "AppName: $AppName" -ForegroundColor Cyan
# Write-Host "Arguments received:" -ForegroundColor Cyan
# foreach ($arg in $Arguments) {
#     Write-Host "  $arg" -ForegroundColor Cyan
# }

Import-Module SoftwareUtils -Force

if ([string]::IsNullOrEmpty($AppName)) {
    Install-SelectedApps -AppType "--OurPsh"
}
elseif ($AppName -eq "--updateAll") {
    Install-SelectedApps -AppType "--OurPsh" -Options "--updateAll"
}
elseif ($AppName -eq "--help" -or $AppName -eq "-h" -or [string]::IsNullOrEmpty($AppName)) {
    Write-Host "Usage: Run-Psh [AppName] [Args] [--help] [--list] [--updateAll]"
    Write-Host "Options:"
    Write-Host "  Run-Psh                 # Start the Get-App dialog (Get-App --FkPsh)"
    Write-Host "  Run-Psh --help          # Shows this help message"
    Write-Host "  Run-Psh --list          # Lists available PowerShell apps"
    Write-Host "  Run-Psh --updateAll     # Calls Get-App --FkPsh --updateAll"
    Write-Host "Usage:"
    Write-Host "  Run-Psh AppName         # Runs specific PowerShell app"
    Write-Host "  Run-Psh AppName arg1    # Runs app with arguments"
    Write-Host ""
    Write-Host "Note: CommonModules will automatically be updated whenever an app is installed"
    exit
}
else {
    Write-Host "Calling Start-OurPshApp with AppName: $AppName" -ForegroundColor Cyan
    Write-Host "Passing these arguments to the target script:" -ForegroundColor Cyan
    foreach ($arg in $Arguments) {
        Write-Host "  $arg" -ForegroundColor Cyan
    }

    # # Make sure boolean parameters are handled properly
    # $processedArgs = @()
    # for ($i = 0; $i -lt $Arguments.Count; $i++) {
    #     $arg = $Arguments[$i]
    #     $processedArgs += $arg

    #     # If this is a potential boolean parameter (ending with ":$true" or ":$false"), handle it
    #     if ($i + 1 -lt $Arguments.Count) {
    #         if ($Arguments[$i + 1] -eq "true" -or $Arguments[$i + 1] -eq "false") {
    #             # Write-Host "  (Converting '$($Arguments[$i + 1])' to boolean for parameter '$arg')" -ForegroundColor Yellow
    #         }
    #     }
    # }

    try {
        Start-OurPshApp -AppName $AppName -Arguments $Arguments
    }
    catch {
        Write-LogMessage "Error calling Start-OurPshApp: $_" -Level ERROR -Exception $_
        exit 1
    }
}

