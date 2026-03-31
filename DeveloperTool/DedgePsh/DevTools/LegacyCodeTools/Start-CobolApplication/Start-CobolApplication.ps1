Import-Module Cobol-Handler -Force
param (
    [Parameter(Mandatory = $true)]
    [string]$Application,
    [Parameter(Mandatory = $true)]
    [string]$Environment,
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [string]$CobolProgramName,
    [Parameter(Mandatory = $true)]
    [string]$DatabaseCatalogName
)

Start-CobolApplication -Application $Application -Environment $Environment -Version $Version -CobolProgramName $CobolProgramName -DatabaseCatalogName $DatabaseCatalogName

