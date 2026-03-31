# Ad-CompareUserSettings.ps1
# Compare user settings between Active Directory and Entra
# Author: Geir Helge Starholm, www.dEdge.no
#
# Forutsetninger:
# - Powershell Versjon >= 7.1
# - Infrastructure og GlobalFunctions modules
#
# Bruk:
# pwsh.exe -file Ad-CompareUserSettings.ps1
# pwsh.exe -file Ad-CompareUserSettings.ps1 -ReferenceUserName "FKGEISTA" -DifferenceUserName "FKMINSTA"
# pwsh.exe -file Ad-CompareUserSettings.ps1 -ReferenceUserName "FKGEISTA" -DifferenceUserName "FKMINSTA" -ExcludeMatches
#
# Note: Markdown report with categorized differences is automatically generated when differences are found
#       Default template: AdGroupTemplate.md in script folder
#
# Historikk:
# --------------------------------------------------------------------
# 20251125 fkgeista Første versjon
# 20251125 fkgeista Add categorized markdown report generation
# --------------------------------------------------------------------
param(
    [Parameter(Mandatory = $false)]
    [string]$ReferenceUserName = "FKGEISTA",
    [Parameter(Mandatory = $false)]
    [string]$DifferenceUserName = "FKMINSTA",
    [switch]$IncludeRawData = $false,
    [switch]$ExcludeMatches = $false,
    [Parameter(Mandatory = $false)]
    [string]$TemplateFilePath = (Join-Path $PSScriptRoot "AdGroupTemplate.md")
)


Import-Module Infrastructure -Force
Import-Module GlobalFunctions -Force
# must be ran at server to have access to Active Directory and Entra
if (-not (Test-IsServer)) {
    Write-LogMessage "This script must be run on a server" -Level ERROR
    exit 1
}
Write-LogMessage "Comparing user settings between Active Directory and Entra for $ReferenceUserName and $DifferenceUserName" -Level INFO
$result = Compare-AdUserSettings -ReferenceUserName $ReferenceUserName -DifferenceUserName $DifferenceUserName -IncludeRawData:$IncludeRawData -ExcludeMatches:$ExcludeMatches

Write-LogMessage "Comparison complete with $($result.TotalDifferences) differences found" -Level INFO

# Generate categorized markdown report if differences found and template exists
if ($result.TotalDifferences -gt 0) {
    if (Test-Path $TemplateFilePath) {
        $outputFolder = Join-Path $(Get-ApplicationDataPath) "Ad-CompareUserSettings"
        if (-not (Test-Path $outputFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $outputFolder -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $markdownOutputFile = Join-Path $outputFolder "$($ReferenceUserName)-$($DifferenceUserName)-Categorized.md"
        
        Export-AdComparisonMarkdown -ComparisonResult $result -TemplateFilePath $TemplateFilePath -OutputFilePath $markdownOutputFile
        Write-LogMessage "Categorized markdown report saved to: $($markdownOutputFile)" -Level INFO
        
        # Open the markdown file
        Start-Process $markdownOutputFile
    }
    else {
        Write-LogMessage "Template file not found: $($TemplateFilePath) - Skipping categorized report" -Level WARN
    }
}
else {
    Write-LogMessage "No differences found - Skipping markdown report generation" -Level INFO
}