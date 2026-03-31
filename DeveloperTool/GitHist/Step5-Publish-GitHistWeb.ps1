<#
.SYNOPSIS
    Deploys the GitHist Presentation to a remote IIS server.

.DESCRIPTION
    Copies the static web content (index.html, datasets.json, Projects_*.json)
    from the local Presentation folder to the target server via UNC path.
    Optionally runs IIS-DeployApp on the remote server to create the IIS virtual app
    (only needed on first deployment).

.PARAMETER ComputerName
    Target server hostname. Default: dedge-server

.PARAMETER SetupIIS
    When specified, invokes IIS-DeployApp.ps1 on the remote server to create/update
    the IIS virtual app and app pool. Only needed on first deployment or after
    template changes.

.EXAMPLE
    .\Deploy-ToIIS.ps1
    Copies presentation files to dedge-server.

.EXAMPLE
    .\Deploy-ToIIS.ps1 -ComputerName dedge-server -SetupIIS
    Copies files and runs IIS site setup on the server.
#>

param(
    [string]$ComputerName = "dedge-server",
    [switch]$SetupIIS
)

Import-Module GlobalFunctions -Force

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$sourceDir  = Join-Path $PSScriptRoot 'Presentation'
$targetDir  = "\\$($ComputerName)\opt\Webs\GitHist"

$includePatterns = @('index.html', 'autodoc-viewer.html', 'datasets.json', 'Projects_*.json')

Write-LogMessage "[$($scriptName)] Deploying GitHist to $($ComputerName)" -Level INFO
Write-LogMessage "[$($scriptName)] Source: $($sourceDir)" -Level INFO
Write-LogMessage "[$($scriptName)] Target: $($targetDir)" -Level INFO

if (-not (Test-Path $sourceDir)) {
    Write-LogMessage "[$($scriptName)] Source folder not found: $($sourceDir)" -Level ERROR
    exit 1
}

if (-not (Test-Path $targetDir)) {
    Write-LogMessage "[$($scriptName)] Creating target folder: $($targetDir)" -Level INFO
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
}

$filesToCopy = foreach ($pattern in $includePatterns) {
    Get-ChildItem -Path $sourceDir -Filter $pattern -File
}

if ($filesToCopy.Count -eq 0) {
    Write-LogMessage "[$($scriptName)] No files matched include patterns -- nothing to deploy" -Level WARN
    exit 1
}

$totalSize = ($filesToCopy | Measure-Object -Property Length -Sum).Sum
Write-LogMessage "[$($scriptName)] Copying $($filesToCopy.Count) files ($([math]::Round($totalSize / 1MB, 2)) MB)" -Level INFO

foreach ($file in $filesToCopy) {
    $dest = Join-Path $targetDir $file.Name
    Copy-Item -Path $file.FullName -Destination $dest -Force
    Write-LogMessage "[$($scriptName)]   $($file.Name) ($([math]::Round($file.Length / 1MB, 2)) MB)" -Level INFO
}

Write-LogMessage "[$($scriptName)] File copy complete" -Level INFO

if ($SetupIIS) {
    Write-LogMessage "[$($scriptName)] Running IIS-DeployApp on $($ComputerName) for SiteName 'GitHist'" -Level INFO
    $remoteScript = "C:\opt\DedgePshApps\IIS-DeployApp\IIS-DeployApp.ps1"

    try {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($scriptPath)
            & $scriptPath -SiteName "GitHist"
        } -ArgumentList $remoteScript -ErrorAction Stop

        Write-LogMessage "[$($scriptName)] IIS site setup complete" -Level INFO
    }
    catch {
        Write-LogMessage "[$($scriptName)] Remote IIS setup failed: $($_.Exception.Message)" -Level WARN
        Write-LogMessage "[$($scriptName)] Run this on the server manually (as admin):" -Level WARN
        Write-LogMessage "[$($scriptName)]   $($remoteScript) -SiteName 'GitHist'" -Level WARN
    }
}

Write-LogMessage "[$($scriptName)] Deployment finished. URL: http://$($ComputerName)/GitHist/" -Level INFO
