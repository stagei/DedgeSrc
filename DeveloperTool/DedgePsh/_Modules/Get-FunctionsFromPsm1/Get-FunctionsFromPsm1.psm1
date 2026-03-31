<#
.SYNOPSIS
    Extracts and analyzes functions from PowerShell module files.

.DESCRIPTION
    This module provides tools for analyzing PowerShell module files (.psm1),
    extracting function definitions, resolving module dependencies, and managing
    import statements. It helps in understanding module structure and dependencies.

.EXAMPLE
    Get-ImportStatementsRecursively -FilePath "C:\Modules\MyModule.psm1"
    # Returns all import statements recursively from the module

.EXAMPLE
    Get-DependencyChain -FilePath "C:\Modules\MyModule.psm1"
    # Returns the complete dependency chain for the module
#>

# Generate a copy of Deploy-Handler.psm1 to a new file called Init-ServerFunctions.ps1: $env:OptPath\src\DedgePsh\_Modules\Deploy-Handler\Deploy-Handler.psm1 and remove Export-ModuleMember statement from Init-ServerFunctions.ps1
# Modified main execution code


function Get-ImportStatementsRecursively {
    param (
        [string]$FilePath
    )
    
    $importStatements = @()
    $fileContent = Get-Content $FilePath
    
    foreach ($line in $fileContent) {
        if ($line -match "Import-Module\s+(?<module>[^\s]+)") {
            $moduleName = $matches.module
            $modulePath = "$env:OptPath\src\DedgePsh\_Modules\$moduleName\$moduleName.psm1"
            
            # Add this module's import statement
            $importStatements += "Import-Module $modulePath -Force"
            
            # Recursively get imports from this module
            if (Test-Path $modulePath) {
                $importStatements += Get-ImportStatementsRecursively -FilePath $modulePath
            }
        }
    }
    
    return $importStatements | Select-Object -Unique
}

function Get-DependencyChain {
    param (
        [string]$FilePath,
        [System.Collections.ArrayList]$Chain = [System.Collections.ArrayList]@()
    )
    
    # If we've already processed this file, skip it
    if ($Chain.Contains($FilePath)) {
        return $Chain
    }
    
    $fileContent = Get-Content $FilePath
    
    # Process dependencies first
    foreach ($line in $fileContent) {
        if ($line -match "Import-Module\s+(?:-Name\s+)?(?<module>[^\s]+)(?:\s+-|$)") {
            $moduleName = $matches.module
            # Handle both full paths and module names
            if ($moduleName.Contains("\")) {
                $modulePath = $moduleName
            }
            else {
                $modulePath = "$env:OptPath\src\DedgePsh\_Modules\$moduleName\$moduleName.psm1"
            }
            
            Write-Host "Processing dependency: $modulePath"
            
            if (Test-Path $modulePath) {
                # Recursively get dependencies first
                $subChain = Get-DependencyChain -FilePath $modulePath -Chain $Chain
                if ($subChain -is [System.Collections.ArrayList]) {
                    $Chain = $subChain
                }
            }
            else {
                Write-Warning "Could not find module at path: $modulePath"
            }
        }
    }
    
    # Add current module to chain after its dependencies
    if (-not $Chain.Contains($FilePath)) {
        Write-Host "Adding to chain: $FilePath"
        [void]$Chain.Add($FilePath)
    }
    
    return $Chain
}

function Get-ModuleContent {
    param (
        [string]$FilePath
    )
    
    $content = Get-Content $FilePath -Raw
    # Remove Export-ModuleMember and Import-Module statements
    $content = $content -replace '(?m)^\s*Export-ModuleMember.*$', ''
    $content = $content -replace '(?m)^\s*Import-Module.*$', ''
    return $content.Trim()
}

function Get-FunctionsFromPsm1 {
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$ModulePaths = @("$env:OptPath\src\DedgePsh\_Modules\Deploy-Handler\Deploy-Handler.psm1", "$env:OptPath\src\DedgePsh\_Modules\SoftwareUtils\SoftwareUtils.psm1"),
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = "$env:OptPath\src\DedgePsh\DevTools\Infrastructure\Init-ServerSetup\Init-ServerFunctions.ps1"
    )
        
    $moduleChain = [System.Collections.ArrayList]@()

    foreach ($mainModulePath in $ModulePaths) {
        Write-Host "`nStarting module dependency resolution from: $mainModulePath" -ForegroundColor Cyan
        $currentChain = Get-DependencyChain -FilePath $mainModulePath
    
        # Add any new modules to the chain that aren't already included
        foreach ($module in $currentChain) {
            if (-not $moduleChain.Contains($module)) {
                [void]$moduleChain.Add($module)
            }
        }
    }

    Write-Host "`nModule processing order (from main to most nested):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $moduleChain.Count; $i++) {
        Write-Host "[$($i + 1)] $($moduleChain[$i])" -ForegroundColor Green
    }

    Write-Host "`nGenerating combined module content..." -ForegroundColor Cyan
    # Combine all module contents in reverse order (dependencies first, main module last)
    $finalContent = ""
    for ($i = 0; $i -lt $moduleChain.Count; $i++) {
        # Adding 
        Write-Host "Processing module: $($moduleChain[$i])" -ForegroundColor Cyan
        $modulePath = $moduleChain[$i]
        $moduleContent = Get-ModuleContent -FilePath $modulePath
        $finalContent += "`n# Module content from: $modulePath`n"
        $finalContent += $moduleContent
        $finalContent += "`n`n"
    }

    # Write the final content to file
    Set-Content -Path $OutputPath -Value $finalContent.Trim()
    Write-Host "`nFile saved to $OutputPath" -ForegroundColor Green


}

Export-ModuleMember -Function Get-FunctionsFromPsm1