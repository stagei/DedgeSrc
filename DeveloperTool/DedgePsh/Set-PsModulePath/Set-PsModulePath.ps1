Import-Module GlobalFunctions -Force

# Update PSModulePath
$RemovePSModulePaths = @("$env:OptPath\src\DedgePsh\_Modules", "$env:OptPath\Apps\CommonModules", "$env:OptPath\DedgePshApps\CommonModules", "$env:OptPath\DedgePshApps\_Modules", "$env:OptPath\psh\_Modules")
if (Test-Path "$env:OptPath\src\DedgePsh\_Modules") {
    $AddPSModulePaths = @("$env:OptPath\src\DedgePsh\_Modules")
}
else {
    $AddPSModulePaths = @("$env:OptPath\DedgePshApps\CommonModules")
}
$PSModulePathWork = [Environment]::GetEnvironmentVariable("PSModulePath", [EnvironmentVariableTarget]::Machine)

# First remove paths we don't want
$validPaths = @()
foreach ($path in ($PSModulePathWork -split ";")) {
    $skipPath = $false
    foreach ($removePath in $RemovePSModulePaths) {
        if ($path -like "*$removePath*") {
            Write-LogMessage "Removing path: $path" -Level INFO
            $skipPath = $true
            break
        }
    }
    if (-not $skipPath -and (Test-Path $path -PathType Container)) {
        Write-LogMessage "Adding path: $path" -Level INFO
        $validPaths += $path
    }
}

foreach ($path in $AddPSModulePaths) {
    if (Test-Path $path -PathType Container) {
        $validPaths += $path
    }
}

# Join back into single string
$PSModulePathWork = $validPaths -join ";"

if ($PSModulePathWork) {
    [System.Environment]::SetEnvironmentVariable('PsModulePath', $PSModulePathWork, [System.EnvironmentVariableTarget]::Machine)
    Write-LogMessage "Updated PSModulePath environment variable for Machine" -Level INFO

    $env:PSModulePath = $PSModulePathWork
    [System.Environment]::SetEnvironmentVariable('PsModulePath', $PSModulePathWork, [System.EnvironmentVariableTarget]::Process)
    Write-LogMessage "Updated PSModulePath environment variable for Session" -Level INFO

    Remove-ItemProperty -Path "HKCU:\Environment" -Name "PSModulePath" -ErrorAction SilentlyContinue
    Write-LogMessage "Deleted PSModulePath environment variable for User" -Level INFO
}

Start-ModuleRefresh

Write-LogMessage "PSModulePath search order:" -Level INFO
$paths = [System.Environment]::GetEnvironmentVariable("PSModulePath", [System.EnvironmentVariableTarget]::Machine) -split ";"
for ($i = 0; $i -lt $paths.Count; $i++) {
    Write-LogMessage "  $($i + 1). $($paths[$i])" -Level INFO
}
Write-LogMessage "Refresh PowerShell modules" -Level INFO
Write-LogMessage "PSModulePath: $env:PSModulePath" -Level INFO

