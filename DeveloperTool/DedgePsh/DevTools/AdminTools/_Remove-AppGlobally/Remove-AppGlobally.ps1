param(
    [Parameter(Mandatory = $false)]
    [string]$AppName = "Entra-GetCurrentUserMetaInfo",
    [Parameter(Mandatory = $false)]
    [ValidateSet("DedgePshApps", "DedgeWinApps","FkPythonApps", "FkNodeJsApps")]
    [string]$AppType = "DedgePshApps",
    [Parameter(Mandatory = $false)]
    [array]$ComputerList = @()
)

Import-Module -Name GlobalFunctions -Force

if ($ComputerList -eq @()) {
    $computerList = Get-ComputerNameList -ComputerNameList "*"
}

foreach ($computer in $computerList) {
    Write-Host "Removing $AppName from $computer"
    $checkPath = "\\$computer\opt\$AppType\$AppName"
    if (Test-Path $checkPath) {
        Write-Host "Removing $checkPath"
        # Remove-Item -Path $checkPath -Recurse -Force
    }
}

