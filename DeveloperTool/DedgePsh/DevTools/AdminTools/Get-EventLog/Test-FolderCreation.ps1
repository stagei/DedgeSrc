<#
.SYNOPSIS
    Test script for Add-FolderForFileIfNotExists function

.DESCRIPTION
    Tests the improved Add-FolderForFileIfNotExists function with various scenarios
    to ensure it properly creates folders and handles edge cases.

.EXAMPLE
    .\Test-FolderCreation.ps1
    # Tests the folder creation function
#>

Import-Module GlobalFunctions -Force

Write-Host "Testing Add-FolderForFileIfNotExists Function" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Test cases
$testCases = @(
    @{
        Description = "Standard nested path"
        FileName = "C:\Temp\TestFolder\SubFolder\testfile.txt"
        ExpectedFolder = "C:\Temp\TestFolder\SubFolder"
    },
    @{
        Description = "Path with spaces"
        FileName = "C:\Temp\Test Folder\My Sub Folder\test file.log"
        ExpectedFolder = "C:\Temp\Test Folder\My Sub Folder"
    },
    @{
        Description = "Deep nested path"
        FileName = "C:\Temp\Level1\Level2\Level3\Level4\deepfile.dat"
        ExpectedFolder = "C:\Temp\Level1\Level2\Level3\Level4"
    },
    @{
        Description = "Path with special characters"
        FileName = "C:\Temp\Test-Folder_2025\Sub.Folder\file@test.xml"
        ExpectedFolder = "C:\Temp\Test-Folder_2025\Sub.Folder"
    }
)

$passCount = 0
$failCount = 0

foreach ($testCase in $testCases) {
    Write-Host "Test: $($testCase.Description)" -ForegroundColor Yellow
    Write-Host "File: $($testCase.FileName)" -ForegroundColor Gray
    Write-Host "Expected Folder: $($testCase.ExpectedFolder)" -ForegroundColor Gray

    try {
        # Clean up before test (remove folder if it exists)
        if (Test-Path -Path $testCase.ExpectedFolder) {
            Remove-Item -Path $testCase.ExpectedFolder -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  Cleaned up existing test folder" -ForegroundColor DarkGray
        }

        # Test without return folder
        Write-Host "  Testing without ReturnFolder..." -ForegroundColor Gray
        Add-FolderForFileIfNotExists -FileName $testCase.FileName

        if (Test-Path -Path $testCase.ExpectedFolder -PathType Container) {
            Write-Host "  ✅ SUCCESS - Folder created successfully" -ForegroundColor Green

            # Test with return folder
            Write-Host "  Testing with ReturnFolder..." -ForegroundColor Gray
            $returnedFolder = Add-FolderForFileIfNotExists -FileName $testCase.FileName -ReturnFolder

            if ($returnedFolder -eq $testCase.ExpectedFolder) {
                Write-Host "  ✅ SUCCESS - Correct folder path returned: $returnedFolder" -ForegroundColor Green
                $passCount++
            } else {
                Write-Host "  ❌ FAIL - Wrong folder path returned" -ForegroundColor Red
                Write-Host "    Expected: $($testCase.ExpectedFolder)" -ForegroundColor Red
                Write-Host "    Returned: $returnedFolder" -ForegroundColor Red
                $failCount++
            }
        } else {
            Write-Host "  ❌ FAIL - Folder was not created" -ForegroundColor Red
            $failCount++
        }
    }
    catch {
        Write-Host "  ❌ FAIL - Exception occurred: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }

    Write-Host ""
}

# Test edge cases
Write-Host "Testing Edge Cases:" -ForegroundColor Cyan
Write-Host "==================" -ForegroundColor Cyan
Write-Host ""

# Test with invalid input
Write-Host "Test: Empty string input" -ForegroundColor Yellow
try {
    Add-FolderForFileIfNotExists -FileName ""
    Write-Host "❌ FAIL - Should have thrown exception for empty string" -ForegroundColor Red
    $failCount++
}
catch {
    Write-Host "✅ SUCCESS - Correctly rejected empty string: $($_.Exception.Message)" -ForegroundColor Green
    $passCount++
}
Write-Host ""

# Test with root path
Write-Host "Test: Root path file" -ForegroundColor Yellow
try {
    $rootFolder = Add-FolderForFileIfNotExists -FileName "C:\rootfile.txt" -ReturnFolder
    if ($rootFolder -eq "C:") {
        Write-Host "✅ SUCCESS - Root path handled correctly: $rootFolder" -ForegroundColor Green
        $passCount++
    } else {
        Write-Host "❌ FAIL - Root path not handled correctly: $rootFolder" -ForegroundColor Red
        $failCount++
    }
}
catch {
    Write-Host "❌ FAIL - Exception with root path: $($_.Exception.Message)" -ForegroundColor Red
    $failCount++
}
Write-Host ""

# Summary
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "Test Results Summary:" -ForegroundColor Cyan
Write-Host "✅ Passed: $passCount" -ForegroundColor Green
Write-Host "❌ Failed: $failCount" -ForegroundColor Red
Write-Host "Total Tests: $($passCount + $failCount)" -ForegroundColor White

if ($failCount -eq 0) {
    Write-Host "🎉 ALL TESTS PASSED! The function is working correctly." -ForegroundColor Green
} else {
    Write-Host "⚠️  Some tests failed. Please review the function implementation." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Cleaning up test folders..." -ForegroundColor Gray
foreach ($testCase in $testCases) {
    if (Test-Path -Path $testCase.ExpectedFolder) {
        Remove-Item -Path $testCase.ExpectedFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "Cleanup completed." -ForegroundColor Green

