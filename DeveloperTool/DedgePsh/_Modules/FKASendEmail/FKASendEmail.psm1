<#
.SYNOPSIS
    Sends emails using the GlobalFunctions Send-Email functionality.

.DESCRIPTION
    [DEPRECATED] This module is a wrapper around GlobalFunctions\Send-Email for backward compatibility.
    It provides email sending capabilities with support for HTML body and attachments.
    Please use GlobalFunctions\Send-Email directly instead.

.PARAMETER To
    The email address of the recipient.

.PARAMETER From
    The email address of the sender.

.PARAMETER Subject
    The subject line of the email.

.PARAMETER Body
    The plain text body of the email.

.PARAMETER HtmlBody
    The HTML formatted body of the email.

.PARAMETER Attachments
    An array of file paths to attach to the email.

.EXAMPLE
    FKASendEmail -To "recipient@example.com" -From "sender@example.com" -Subject "Test" -Body "Hello World"
    # Sends a simple email

.EXAMPLE
    FKASendEmail -To "recipient@example.com" -From "sender@example.com" -Subject "Test" -HtmlBody "<h1>Hello</h1>" -Attachments @("file1.pdf", "file2.txt")
    # Sends an HTML email with attachments
#>

# FKASendEmail.ps1
#
# [DEPRECATED] This module is deprecated. Please use GlobalFunctions\Send-Email instead.
# 
# Changelog:
# ------------------------------------------------------------------------------
# 20240119         Marked as deprecated - use GlobalFunctions\Send-Email instead
# ------------------------------------------------------------------------------

$modulesToImport = @("GlobalFunctions")
foreach ($moduleName in $modulesToImport) {
  $loadedModule = Get-Module -Name $moduleName
  if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
    Import-Module $moduleName -Force
  }
  else {
    Write-Host "Module $moduleName already loaded" -ForegroundColor Yellow
  }
} 


function FKASendEmail {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$To,
        [Parameter(Mandatory = $true)]
        [string]$From,
        [Parameter(Mandatory = $true)]
        [string]$Subject,
        [Parameter(Mandatory = $false)]
        [string]$Body,
        [Parameter(Mandatory = $false)]
        [string]$HtmlBody,
        [Parameter(Mandatory = $false)]
        [string[]]$Attachments
    )

    Write-Warning "FKASendEmail is deprecated. Please use GlobalFunctions\Send-Email instead."
    Send-Email -To $To -From $From -Subject $Subject -Body $Body -Attachments $Attachments
}

Export-ModuleMember -Function FKASendEmail
