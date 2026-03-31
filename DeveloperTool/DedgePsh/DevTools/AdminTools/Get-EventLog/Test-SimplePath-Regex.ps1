<#
.SYNOPSIS
    Test script for the simple PATH regex pattern

.DESCRIPTION
    Tests the new PATH statement regex pattern to ensure it correctly captures
    simple paths like 'RAATS8' and prepends the TablespacesFolder.

.EXAMPLE
    .\Test-SimplePath-Regex.ps1
    # Tests the simple PATH regex pattern
#>

Write-Host "Testing Simple PATH Statement Regex Pattern" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

<#
REGEX PATTERN EXPLANATION: Simple PATH Statement Replacement
============================================================
Pattern: (?i)PATH\s+'(?![C-G]:)([^']+)'

BREAKDOWN:
(?i)                    - Case-insensitive flag
PATH                    - Literal text "PATH"
\s+                     - One or more whitespace characters
'                       - Literal single quote
(?![C-G]:)             - NEGATIVE LOOKAHEAD: Not followed by C:, D:, E:, F:, or G:
([^']+)                 - CAPTURE GROUP 1: One or more non-quote characters
'                       - Literal single quote

PURPOSE: Transform "PATH   'RAATS8'" to "PATH   'C:\TablespaceFolder\RAATS8'"
#>

# The regex pattern for simple PATH statements
$regexPattern = "(?i)PATH\s+'(?![C-G]:)([^']+)'"
$tablespacesFolder = "C:\TablespaceFolder"
$replacement = "PATH   '$tablespacesFolder\`$1'"

Write-Host "Regex Pattern: $regexPattern" -ForegroundColor White
Write-Host "Replacement: $replacement" -ForegroundColor White
Write-Host ""

# Test cases
$testCases = @(
    @{
        Description = "Your example - RAATS8"
        Input = "PATH   'RAATS8'"
        ShouldMatch = $true
        ExpectedResult = "PATH   'C:\TablespaceFolder\RAATS8'"
    },
    @{
        Description = "Different folder name"
        Input = "PATH 'tempspace32'"
        ShouldMatch = $true
        ExpectedResult = "PATH   'C:\TablespaceFolder\tempspace32'"
    },
    @{
        Description = "Mixed case PATH"
        Input = "path   'TESTFOLDER'"
        ShouldMatch = $true
        ExpectedResult = "PATH   'C:\TablespaceFolder\TESTFOLDER'"
    },
    @{
        Description = "With numbers and underscores"
        Input = "PATH 'SPACE_001'"
        ShouldMatch = $true
        ExpectedResult = "PATH   'C:\TablespaceFolder\SPACE_001'"
    },
    @{
        Description = "Windows C: drive - should NOT match"
        Input = "PATH   'C:\Windows\Path'"
        ShouldMatch = $false
    },
    @{
        Description = "Windows E: drive - should NOT match"
        Input = "PATH   'E:\DB\Tablespace'"
        ShouldMatch = $false
    },
    @{
        Description = "Windows D: drive - should NOT match"
        Input = "PATH   'D:\Data\Path'"
        ShouldMatch = $false
    },
    @{
        Description = "Unix path - should MATCH"
        Input = "PATH '/unix/path'"
        ShouldMatch = $true
        ExpectedResult = "PATH   'C:\TablespaceFolder\/unix/path'"
    },
    @{
        Description = "Relative path - should MATCH"
        Input = "PATH 'relative/folder'"
        ShouldMatch = $true
        ExpectedResult = "PATH   'C:\TablespaceFolder\relative/folder'"
    }
)

$passCount = 0
$failCount = 0

foreach ($testCase in $testCases) {
    Write-Host "Test: $($testCase.Description)" -ForegroundColor Yellow
    Write-Host "Input: $($testCase.Input)" -ForegroundColor Gray

    # Test if the pattern matches
    $isMatch = $testCase.Input -match $regexPattern

    if ($isMatch) {
        $result = $testCase.Input -replace $regexPattern, $replacement
        Write-Host "MATCHED - Result: $result" -ForegroundColor White

        if ($testCase.ShouldMatch) {
            # Check if expected result is specified and matches
            if ($testCase.ExpectedResult -and $result -ne $testCase.ExpectedResult) {
                Write-Host "❌ FAIL - Result doesn't match expected!" -ForegroundColor Red
                Write-Host "Expected: $($testCase.ExpectedResult)" -ForegroundColor Yellow
                $failCount++
            } else {
                Write-Host "✅ PASS - Correctly matched and transformed" -ForegroundColor Green
                $passCount++
            }
        } else {
            Write-Host "❌ FAIL - Should NOT have matched!" -ForegroundColor Red
            $failCount++
        }
    } else {
        Write-Host "NO MATCH - Input unchanged" -ForegroundColor White

        if (-not $testCase.ShouldMatch) {
            Write-Host "✅ PASS - Correctly did not match" -ForegroundColor Green
            $passCount++
        } else {
            Write-Host "❌ FAIL - Should have matched!" -ForegroundColor Red
            $failCount++
        }
    }

    Write-Host ""
}

# Summary
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Test Results Summary:" -ForegroundColor Cyan
Write-Host "✅ Passed: $passCount" -ForegroundColor Green
Write-Host "❌ Failed: $failCount" -ForegroundColor Red
Write-Host "Total Tests: $($passCount + $failCount)" -ForegroundColor White

if ($failCount -eq 0) {
    Write-Host "🎉 ALL TESTS PASSED! The simple PATH regex is working correctly." -ForegroundColor Green
} else {
    Write-Host "⚠️  Some tests failed. Please review the regex pattern." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

