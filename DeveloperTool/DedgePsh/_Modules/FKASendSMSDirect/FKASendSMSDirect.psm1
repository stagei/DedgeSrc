<#
.SYNOPSIS
    Sends SMS messages directly using the GlobalFunctions Send-Sms functionality.

.DESCRIPTION
    [DEPRECATED] This module is a wrapper around GlobalFunctions\Send-Sms for backward compatibility.
    It provides direct SMS sending capabilities. Please use GlobalFunctions\Send-Sms directly instead.

.PARAMETER receiver
    The phone number of the SMS recipient.

.PARAMETER message
    The text message to be sent.

.EXAMPLE
    FKASendSMSDirect -receiver "+4712345678" -message "Hello World"
    # Sends an SMS to the specified number
#>

# FKASendSMSDirect.ps1
#
# [DEPRECATED] This module is deprecated. Please use GlobalFunctions\Send-Sms instead.
# 
# Changelog:
# ------------------------------------------------------------------------------
# 20240119         Marked as deprecated - use GlobalFunctions\Send-Sms instead
# 20211202 fksveeri Første versjon
# ------------------------------------------------------------------------------
$modulesToImport = @("GlobalFunctions", "Logger")
foreach ($moduleName in $modulesToImport) {
  $loadedModule = Get-Module -Name $moduleName
  if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
    Import-Module $moduleName -Force
  }
  else {
    Write-Host "Module $moduleName already loaded" -ForegroundColor Yellow
  }
} 



function FKASendSMSDirect {
    param(
        [string] $receiver,
        [string] $message
    )
    Write-Warning "FKASendSMSDirect is deprecated. Please use GlobalFunctions\Send-Sms instead."
    Send-Sms -To $Receiver -Message $Message
}
Export-ModuleMember -Function FKASendSMSDirect
