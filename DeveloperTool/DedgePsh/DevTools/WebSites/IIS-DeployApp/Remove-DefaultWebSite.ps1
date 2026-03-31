<#
.SYNOPSIS
    Removes the Default Web Site (and its applications) using appcmd so it works when IIS Manager GUI fails.

.DESCRIPTION
    The IIS Manager client can fail with "The application '/' does not exist" when removing
    Default Web Site due to config inconsistency. This script uses appcmd.exe to:

    1. List all applications under the site
    2. Delete each application by exact identifier (including the root app "Default Web Site/")
    3. Stop the site
    4. Delete the site

    Run on the target server (e.g. dedge-server) with elevated privileges.

.PARAMETER SiteName
    IIS site name to remove. Default: "Default Web Site"

.PARAMETER Force
    Skip confirmation prompt.

.PARAMETER RemoveAppPool
    Also remove the site's application pool (DefaultAppPool) if no other app uses it. Default: false.

.EXAMPLE
    .\Remove-DefaultWebSite.ps1 -Force
    Remove Default Web Site without prompting.

.EXAMPLE
    .\Remove-DefaultWebSite.ps1 -SiteName "Default Web Site" -Force -RemoveAppPool
    Remove site and its app pool.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SiteName = "Default Web Site",
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    [Parameter(Mandatory = $false)]
    [switch]$RemoveAppPool
)

$ErrorActionPreference = "Stop"
Import-Module GlobalFunctions -Force
$logDir = "C:\opt\data\AllPwshLog"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_STARTED

$appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
if (-not (Test-Path $appcmd)) {
    Write-LogMessage "appcmd.exe not found. IIS may not be installed." -Level ERROR
    exit 1
}

# Require -Force to avoid accidental removal
if (-not $Force) {
    Write-LogMessage "Refusing to remove site without -Force. Run: .\Remove-DefaultWebSite.ps1 -Force" -Level WARN
    exit 0
}

# Check site exists
$siteList = & $appcmd list site "$SiteName" 2>&1 | Out-String
if ($siteList -notmatch 'SITE "') {
    Write-LogMessage "Site '$SiteName' does not exist. Nothing to remove." -Level INFO
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
    exit 0
}

Write-LogMessage "Removing site: $SiteName" -Level INFO

# 1) List all apps under this site (exact identifiers from appcmd)
$appList = & $appcmd list app /site.name:"$SiteName" 2>&1 | Out-String
$appIds = [System.Collections.ArrayList]@()
foreach ($line in ($appList -split "`n")) {
    $line = $line.Trim()
    # Format: APP "Default Web Site/" (applicationPool:DefaultAppPool) or APP "Default Web Site/DedgeAuth" (...)
    if ($line -match '^APP "([^"]+)"') {
        $id = $matches[1]
        $null = $appIds.Add($id)
    }
}

# 2) Delete each app by exact identifier. Delete child apps first (longest path), then root "Default Web Site/"
$sortedIds = @($appIds | Sort-Object { -$_.Length }, { $_ })
foreach ($appId in $sortedIds) {
    $check = & $appcmd list app /app.name:"$appId" 2>&1 | Out-String
    if ($check -match 'APP "') {
        Write-LogMessage "  Deleting app: $appId" -Level INFO
        try {
            $result = & $appcmd delete app /app.name:"$appId" 2>&1 | Out-String
            if ($result -match "deleted") {
                Write-LogMessage "    Deleted." -Level INFO
            } else {
                Write-LogMessage "    Result: $($result.Trim())" -Level WARN
            }
        } catch {
            Write-LogMessage "    Failed (continuing): $_" -Level WARN
        }
    }
}

# 3) Stop site
Write-LogMessage "Stopping site: $SiteName" -Level INFO
& $appcmd stop site "$SiteName" 2>&1 | Out-Null
Start-Sleep -Seconds 2

# 4) Delete site (use /site.name: for exact match)
Write-LogMessage "Deleting site: $SiteName" -Level INFO
$delResult = & $appcmd delete site /site.name:"$SiteName" 2>&1 | Out-String
if ($delResult -match "deleted") {
    Write-LogMessage "Site '$SiteName' removed successfully." -Level INFO
} else {
    Write-LogMessage "Delete site result: $($delResult.Trim())" -Level ERROR
    Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_FAILED
    exit 1
}

# 5) Optionally remove the app pool used by the root app (DefaultAppPool)
if ($RemoveAppPool) {
    $poolName = "DefaultAppPool"
    $poolCheck = & $appcmd list apppool "$poolName" 2>&1 | Out-String
    if ($poolCheck -match 'APPPOOL "') {
        $appsInPool = & $appcmd list app /apppool.name:"$poolName" 2>&1 | Out-String
        $count = ([regex]::Matches($appsInPool, 'APP "')).Count
        if ($count -eq 0) {
            Write-LogMessage "Removing app pool: $poolName" -Level INFO
            & $appcmd delete apppool "$poolName" 2>&1 | Out-Null
        } else {
            Write-LogMessage "App pool '$poolName' still in use ($count app(s)); not removed." -Level WARN
        }
    }
}

Write-LogMessage "$($MyInvocation.MyCommand.Name)" -Level JOB_COMPLETED
exit 0
