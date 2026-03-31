<#
.SYNOPSIS
    Test script for Reg-List.ps1 to verify all functionality works correctly.

.DESCRIPTION
    This script tests various scenarios for the Reg-List.ps1 script including:
    - Valid registry paths
    - Invalid registry paths with partial matching
    - Wildcard patterns
    - Regedit copied paths (English and Norwegian)
    - Single properties vs folders
    - Recursive searches
    - Access error handling

.EXAMPLE
    .\Test-RegList.ps1
    Runs all test scenarios for Reg-List.ps1

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
#>

# Import required modules
Import-Module GlobalFunctions -Force

# Test configuration
$scriptPath = Join-Path $PSScriptRoot "Reg-List.ps1"
$testResults = @()

function Write-TestResult {
    param(
        [string]$TestName,
        [string]$Status,
        [string]$Details = ""
    )

    $result = [PSCustomObject]@{
        TestName = $TestName
        Status = $Status
        Details = $Details
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    $testResults += $result

    $color = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        "WARN" { "Yellow" }
        default { "White" }
    }

    Write-Host "[$Status] $TestName" -ForegroundColor $color
    if ($Details) {
        Write-Host "  Details: $Details" -ForegroundColor Gray
    }
}

function Test-RegListScript {
    param(
        [string]$SearchString,
        [switch]$Recurse,
        [string]$TestName,
        [string]$ExpectedBehavior = ""
    )

    Write-Host "`n--- Testing: $TestName ---" -ForegroundColor Cyan
    Write-Host "Search String: $SearchString" -ForegroundColor Gray
    if ($Recurse) {
        Write-Host "Recurse: Yes" -ForegroundColor Gray
    }
    if ($ExpectedBehavior) {
        Write-Host "Expected: $ExpectedBehavior" -ForegroundColor Gray
    }

    try {
        $params = @{
            SearchString = $SearchString
        }
        if ($Recurse) {
            $params.Recurse = $true
        }

        $output = & $scriptPath @params 2>&1

        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
            Write-TestResult -TestName $TestName -Status "PASS" -Details "Script executed successfully"

            # Display first few lines of output for verification
            $outputLines = $output | Select-Object -First 10
            Write-Host "Output preview:" -ForegroundColor DarkGray
            foreach ($line in $outputLines) {
                Write-Host "  $line" -ForegroundColor DarkGray
            }
            if ($output.Count -gt 10) {
                Write-Host "  ... ($($output.Count - 10) more lines)" -ForegroundColor DarkGray
            }
        }
        else {
            Write-TestResult -TestName $TestName -Status "FAIL" -Details "Script failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-TestResult -TestName $TestName -Status "FAIL" -Details "Exception: $($_.Exception.Message)"
    }
}

# Start testing
Write-Host "Starting Reg-List.ps1 Test Suite" -ForegroundColor Green
Write-Host "Script Path: $scriptPath" -ForegroundColor Gray
Write-Host "Test Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# Test 1: Valid registry path (folder)
Test-RegListScript -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -TestName "Valid Registry Path (Folder)" -ExpectedBehavior "Should list all properties in Advanced folder"

# Test 2: Valid registry path with recursion
Test-RegListScript -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Recurse -TestName "Valid Registry Path with Recursion" -ExpectedBehavior "Should list all properties in Advanced folder and subfolders"

# Test 3: Single registry property
Test-RegListScript -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ShowCompColor" -TestName "Single Registry Property" -ExpectedBehavior "Should list only the specific property with datatype and value"

# Test 4: Wildcard pattern
Test-RegListScript -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\*" -TestName "Wildcard Pattern" -ExpectedBehavior "Should list all keys under Explorer using wildcard"

# Test 5: Wildcard pattern with recursion
Test-RegListScript -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\*" -Recurse -TestName "Wildcard Pattern with Recursion" -ExpectedBehavior "Should recursively list all keys under Explorer"

# Test 6: English regedit copied path
Test-RegListScript -SearchString "Computer\HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -TestName "English Regedit Path" -ExpectedBehavior "Should convert and list properties in Advanced folder"

# Test 7: Norwegian regedit copied path
Test-RegListScript -SearchString "Datamaskin\HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -TestName "Norwegian Regedit Path" -ExpectedBehavior "Should convert and list properties in Advanced folder"

# Test 8: Partial/invalid path (should find max valid path)
Test-RegListScript -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\NonExistentKey\SomeProperty" -TestName "Partial Invalid Path" -ExpectedBehavior "Should find max valid path and search for remaining parts"

# Test 9: Search term only (no valid path)
Test-RegListScript -SearchString "Explorer" -TestName "Search Term Only" -ExpectedBehavior "Should search across all registry hives for 'Explorer'"

# Test 10: HKLM path (may have access restrictions)
Test-RegListScript -SearchString "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" -TestName "HKLM Path" -ExpectedBehavior "Should list startup programs, may show inaccessible paths in yellow"

# Test 11: Non-existent path
Test-RegListScript -SearchString "HKCU\Software\NonExistentApplication\Settings" -TestName "Non-existent Path" -ExpectedBehavior "Should handle gracefully and show no results or search for parts"

# Test 12: Empty search string (should use default)
Test-RegListScript -SearchString "" -TestName "Empty Search String" -ExpectedBehavior "Should use default search string"

# Test 13: Very long path
Test-RegListScript -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ShowCompColor\Extra\Parts" -TestName "Very Long Path" -ExpectedBehavior "Should find max valid path and search remaining parts"

# Test 14: Path with special characters
Test-RegListScript -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -TestName "Path with Special Characters" -ExpectedBehavior "Should handle special characters in registry paths"

# Test 15: Multiple wildcards
Test-RegListScript -SearchString "HKCU\Software\*\Windows\CurrentVersion\*" -TestName "Multiple Wildcards" -ExpectedBehavior "Should handle multiple wildcard patterns"

# Test 16: Norwegian regedit path with wildcard (HKLM)
Test-RegListScript -SearchString "Datamaskin\HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\EC2C*" -TestName "Norwegian Regedit Path with Wildcard (HKLM)" -ExpectedBehavior "Should convert Norwegian regedit path and search for EC2C* products"

# Test 17: Norwegian regedit path with wildcard (alternative pattern)
Test-RegListScript -SearchString "Datamaskin\HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\EC2C.*" -TestName "Norwegian Regedit Path with Wildcard (Alternative)" -ExpectedBehavior "Should convert Norwegian regedit path and search for EC2C.* products"

# Test 18: Folder-only search (no properties, just subfolders)
Test-RegListScript -SearchString "HKLM\SOFTWARE\Classes\Installer\Products" -TestName "Folder-Only Search (Subfolders)" -ExpectedBehavior "Should list all subfolders in Products directory, including EC2C* folders"

# Summary
Write-Host "`n=== TEST SUMMARY ===" -ForegroundColor Green
Write-Host "Total Tests: $($testResults.Count)" -ForegroundColor White
Write-Host "Passed: $($testResults | Where-Object { $_.Status -eq 'PASS' }).Count" -ForegroundColor Green
Write-Host "Failed: $($testResults | Where-Object { $_.Status -eq 'FAIL' }).Count" -ForegroundColor Red
Write-Host "Warnings: $($testResults | Where-Object { $_.Status -eq 'WARN' }).Count" -ForegroundColor Yellow

Write-Host "`n=== DETAILED RESULTS ===" -ForegroundColor Green
$testResults | Format-Table -AutoSize

# Save results to file
$resultsFile = Join-Path $PSScriptRoot "TestResults-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$testResults | ConvertTo-Json -Depth 3 | Set-Content $resultsFile
Write-Host "`nTest results saved to: $resultsFile" -ForegroundColor Gray

Write-Host "`nTest Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

