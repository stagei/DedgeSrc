# Update-ModuleDocumentation.ps1
# Script to help update documentation for PowerShell modules
# This script extracts exported functions from .psm1 files and helps update documentation

# Import required modules
Import-Module Get-FunctionsFromPsm1 -ErrorAction SilentlyContinue

# Function to extract exported functions from a .psm1 file
function Get-ExportedFunctions {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModulePath
    )

    if (-not (Test-Path $ModulePath)) {
        Write-Error "Module file not found: $ModulePath"
        return $null
    }

    # Try to use Get-FunctionsFromPsm1 module if available
    if (Get-Command Get-FunctionsFromPsm1 -ErrorAction SilentlyContinue) {
        return Get-FunctionsFromPsm1 -ModulePath $ModulePath
    }

    # Fallback method: Parse the file manually
    $moduleContent = Get-Content -Path $ModulePath -Raw
    $exportStatements = [regex]::Matches($moduleContent, 'Export-ModuleMember\s+-Function\s+([^#\r\n]+)')

    $exportedFunctions = @()
    foreach ($statement in $exportStatements) {
        $functionNames = $statement.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() }
        $exportedFunctions += $functionNames
    }

    return $exportedFunctions
}

# Function to extract SYNOPSIS comments for a function
function Get-SynopsisComment {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModulePath,
        [Parameter(Mandatory = $true)]
        [string]$FunctionName
    )

    if (-not (Test-Path $ModulePath)) {
        Write-Error "Module file not found: $ModulePath"
        return $null
    }

    $moduleContent = Get-Content -Path $ModulePath -Raw
    $functionPattern = "function\s+$FunctionName\s*\{"
    $commentPattern = "<#(.*?)#>"

    # Find the function in the file
    $functionMatch = [regex]::Match($moduleContent, $functionPattern)
    if (-not $functionMatch.Success) {
        Write-Warning "Function $FunctionName not found in $ModulePath"
        return $null
    }

    # Look for the comment block before the function
    $contentBeforeFunction = $moduleContent.Substring(0, $functionMatch.Index)
    $lastCommentMatch = [regex]::Match($contentBeforeFunction, $commentPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    if ($lastCommentMatch.Success) {
        $commentBlock = $lastCommentMatch.Groups[1].Value
        $synopsisMatch = [regex]::Match($commentBlock, "\.SYNOPSIS\s*(.*?)(\r?\n\.|\r?\n\s*\r?\n|$)", [System.Text.RegularExpressions.RegexOptions]::Singleline)

        if ($synopsisMatch.Success) {
            return $synopsisMatch.Groups[1].Value.Trim()
        }
    }

    return "No SYNOPSIS found"
}

# Main function to process all modules
function Update-ModuleDocumentation {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModulesPath
    )

    $moduleFolders = Get-ChildItem -Path $ModulesPath -Directory
    $results = @()

    foreach ($folder in $moduleFolders) {
        $moduleName = $folder.Name
        $psm1File = Join-Path -Path $folder.FullName -ChildPath "$moduleName.psm1"

        if (Test-Path $psm1File) {
            Write-Host "Processing module: $moduleName" -ForegroundColor Green

            $exportedFunctions = Get-ExportedFunctions -ModulePath $psm1File

            if ($exportedFunctions) {
                foreach ($function in $exportedFunctions) {
                    $synopsis = Get-SynopsisComment -ModulePath $psm1File -FunctionName $function

                    $results += [PSCustomObject]@{
                        Module = $moduleName
                        Function = $function
                        Synopsis = $synopsis
                    }
                }
            } else {
                Write-Host "  No exported functions found in $moduleName" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  No .psm1 file found for $moduleName" -ForegroundColor Yellow
        }
    }

    return $results
}

# Execute the script if run directly
if ($MyInvocation.InvocationName -ne '.') {
    $modulesPath = $PSScriptRoot
    $results = Update-ModuleDocumentation -ModulesPath $modulesPath

    # Display results
    $results | Format-Table -AutoSize

    # Export results to CSV for reference
    $csvPath = Join-Path -Path $modulesPath -ChildPath "ModuleFunctions.csv"
    $results | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Results exported to: $csvPath" -ForegroundColor Green

    # Generate markdown report
    $markdownPath = Join-Path -Path $modulesPath -ChildPath "ModuleFunctions.md"
    $markdown = "# PowerShell Module Functions Report`n`n"

    $currentModule = ""
    foreach ($item in $results) {
        if ($item.Module -ne $currentModule) {
            $markdown += "`n## $($item.Module)`n`n"
            $currentModule = $item.Module
        }

        $markdown += "### $($item.Function)`n`n"
        $markdown += "$($item.Synopsis)`n`n"
    }

    $markdown | Out-File -FilePath $markdownPath -Encoding utf8
    Write-Host "Markdown report generated: $markdownPath" -ForegroundColor Green
}

