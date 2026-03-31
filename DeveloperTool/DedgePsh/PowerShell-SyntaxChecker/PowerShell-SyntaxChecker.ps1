<#
.SYNOPSIS
    Validates PowerShell script syntax using the official PowerShell parser.

.DESCRIPTION
    Uses [System.Management.Automation.Language.Parser]::ParseFile to check for syntax errors
    in PowerShell scripts. This is more reliable than IDE linters which can produce false
    positives on large or complex files.

.PARAMETER Path
    Path to the PowerShell script file to check. Can be a single file or array of files.

.PARAMETER Recurse
    If Path is a directory, recursively check all .ps1 and .psm1 files.

.EXAMPLE
    .\PowerShell-SyntaxChecker.ps1 -Path "C:\scripts\MyScript.ps1"
    Check a single file.

.EXAMPLE
    .\PowerShell-SyntaxChecker.ps1 -Path "C:\scripts" -Recurse
    Check all PowerShell files in a directory recursively.

.EXAMPLE
    Get-ChildItem *.ps1 | .\PowerShell-SyntaxChecker.ps1
    Check files from pipeline.

.NOTES
    Author: AutoDoc Team
    Use this script when IDE linters show syntax errors on large PowerShell files.
    IDE linters can struggle with complex constructs and produce false positives.
#>

param(
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias("FullName")]
    [string[]]$Path,

    [switch]$Recurse
)

begin {
    $totalFiles = 0
    $filesWithErrors = 0
    $totalErrors = 0
    $allFiles = @()
}

process {
    foreach ($p in $Path) {
        if (Test-Path $p -PathType Container) {
            # It's a directory - use wildcard path for -Include to work without -Recurse
            $searchPath = Join-Path $p "*"
            if ($Recurse) {
                $allFiles += Get-ChildItem -Path $p -Include "*.ps1", "*.psm1" -Recurse -File
            } else {
                $allFiles += Get-ChildItem -Path $searchPath -Include "*.ps1", "*.psm1" -File
            }
        } elseif (Test-Path $p -PathType Leaf) {
            # It's a file
            $allFiles += Get-Item $p
        } else {
            Write-Warning "Path not found: $p"
        }
    }
}

end {
    if ($allFiles.Count -eq 0) {
        Write-Host "No PowerShell files found to check." -ForegroundColor Yellow
        return
    }

    Write-Host "`nPowerShell Syntax Checker" -ForegroundColor Cyan
    Write-Host "=========================" -ForegroundColor Cyan
    Write-Host "Checking $($allFiles.Count) file(s)...`n" -ForegroundColor Gray

    foreach ($file in $allFiles) {
        $totalFiles++
        $tokens = $null
        $errors = $null
        
        try {
            [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            
            if ($errors.Count -gt 0) {
                $filesWithErrors++
                $totalErrors += $errors.Count
                
                Write-Host "ERRORS: $($file.FullName)" -ForegroundColor Red
                foreach ($parseError in $errors) {
                    Write-Host "  Line $($parseError.Extent.StartLineNumber): $($parseError.Message)" -ForegroundColor Yellow
                }
                Write-Host ""
            } else {
                Write-Host "OK: $($file.Name)" -ForegroundColor Green
            }
        }
        catch {
            $filesWithErrors++
            Write-Host "ERROR: $($file.FullName) - $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # Summary
    Write-Host "`n-------------------------" -ForegroundColor Cyan
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  Files checked:    $totalFiles" -ForegroundColor White
    Write-Host "  Files with errors: $filesWithErrors" -ForegroundColor $(if ($filesWithErrors -gt 0) { "Red" } else { "Green" })
    Write-Host "  Total errors:     $totalErrors" -ForegroundColor $(if ($totalErrors -gt 0) { "Red" } else { "Green" })
    
    if ($filesWithErrors -eq 0) {
        Write-Host "`nAll files passed syntax check!" -ForegroundColor Green
    } else {
        Write-Host "`nSome files have syntax errors." -ForegroundColor Red
    }
}
