<#
.SYNOPSIS
    Lists all ports used by IIS deploy templates.
.DESCRIPTION
    Reads all *.deploy.json templates and displays ApiPort and AdditionalPorts in a table.
#>

$templatesPath = Join-Path $PSScriptRoot "templates"
$templates = Get-ChildItem -Path $templatesPath -Filter "*.deploy.json" | Sort-Object Name

$rows = foreach ($file in $templates) {
    $json = Get-Content $file.FullName -Raw | ConvertFrom-Json

    if ($json.ApiPort -and $json.ApiPort -gt 0) {
        [PSCustomObject]@{
            SiteName = $json.SiteName
            Port     = $json.ApiPort
            Type     = "ApiPort"
        }
    }

    if ($json.AdditionalPorts) {
        foreach ($ap in $json.AdditionalPorts) {
            [PSCustomObject]@{
                SiteName = $json.SiteName
                Port     = $ap.Port
                Type     = "Additional ($($ap.Description))"
            }
        }
    }
}

Write-Host "`nIIS Deploy Template Port Allocation" -ForegroundColor Cyan
Write-Host ("=" * 70)
$rows | Sort-Object Port | Format-Table -AutoSize
Write-Host "Total ports: $($rows.Count)" -ForegroundColor Yellow
