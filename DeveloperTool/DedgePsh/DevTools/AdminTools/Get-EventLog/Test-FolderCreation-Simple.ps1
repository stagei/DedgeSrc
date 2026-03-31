<#
.SYNOPSIS
    Simple test for folder creation logic without module dependencies

.DESCRIPTION
    Tests the core folder creation logic using native PowerShell commands
    to verify the improved logic works correctly.

.EXAMPLE
    .\Test-FolderCreation-Simple.ps1
    # Tests folder creation with various scenarios
#>

Write-Host "Testing Folder Creation Logic (Standalone)" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

# Simulate the improved Add-FolderForFileIfNotExists function logic
function Test-FolderCreationLogic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,
        [Parameter(Mandatory = $false)]
        [switch]$ReturnFolder = $false
    )

    $fileFolder = ""

    try {
        # Validation
        if ([string]::IsNullOrWhiteSpace($FileName)) {
            throw "FileName parameter cannot be null, empty, or whitespace: '$FileName'"
        }

        Write-Host "  Processing file: $FileName" -ForegroundColor Gray

        # Extract parent directory
        $fileFolder = Split-Path -Path $FileName -Parent

        # Handle edge cases
        if ([string]::IsNullOrWhiteSpace($fileFolder)) {
            Write-Host "  No parent folder found (possibly root or relative path)" -ForegroundColor Yellow
            if ($ReturnFolder) {
                return ""
            }
            return
        }

        Write-Host "  Target folder: $fileFolder" -ForegroundColor Gray

        # Check if folder exists
        if (Test-Path -Path $fileFolder -PathType Container) {
            Write-Host "  Folder already exists" -ForegroundColor Green
        }
        else {
            Write-Host "  Creating folder..." -ForegroundColor Yellow

            # Create directory
            $createdFolder = New-Item -ItemType Directory -Path $fileFolder -Force -ErrorAction Stop

            if ($null -eq $createdFolder) {
                throw "New-Item returned null when creating folder: $fileFolder"
            }

            Write-Host "  Successfully created folder" -ForegroundColor Green
        }

        # Final verification
        if (-not (Test-Path -Path $fileFolder -PathType Container)) {
            throw "Folder verification failed after creation: $fileFolder"
        }

        Write-Host "  Folder verified to exist" -ForegroundColor Green

        if ($ReturnFolder) {
            return $fileFolder
        }
    }
    catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

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
    }
)

$passCount = 0
$failCount = 0

foreach ($testCase in $testCases) {
    Write-Host "Test: $($testCase.Description)" -ForegroundColor Yellow

    try {
        # Clean up before test
        if (Test-Path -Path $testCase.ExpectedFolder) {
            Remove-Item -Path $testCase.ExpectedFolder -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  Cleaned up existing test folder" -ForegroundColor DarkGray
        }

        # Test function
        Test-FolderCreationLogic -FileName $testCase.FileName

        # Verify result
        if (Test-Path -Path $testCase.ExpectedFolder -PathType Container) {
            Write-Host "  ✅ SUCCESS - Folder created and verified" -ForegroundColor Green

            # Test return folder feature
            $returnedFolder = Test-FolderCreationLogic -FileName $testCase.FileName -ReturnFolder
            if ($returnedFolder -eq $testCase.ExpectedFolder) {
                Write-Host "  ✅ SUCCESS - Correct folder path returned" -ForegroundColor Green
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
        Write-Host "  ❌ FAIL - Exception: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }

    Write-Host ""
}

# Test edge cases
Write-Host "Edge Case Tests:" -ForegroundColor Cyan
Write-Host "================" -ForegroundColor Cyan
Write-Host ""

# Test empty string
Write-Host "Test: Empty string input" -ForegroundColor Yellow
try {
    Test-FolderCreationLogic -FileName ""
    Write-Host "❌ FAIL - Should have thrown exception" -ForegroundColor Red
    $failCount++
}
catch {
    Write-Host "✅ SUCCESS - Correctly rejected empty string" -ForegroundColor Green
    $passCount++
}
Write-Host ""

# Test root path
Write-Host "Test: Root path file" -ForegroundColor Yellow
try {
    $rootFolder = Test-FolderCreationLogic -FileName "C:\rootfile.txt" -ReturnFolder
    Write-Host "✅ SUCCESS - Root path handled: '$rootFolder'" -ForegroundColor Green
    $passCount++
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
    Write-Host "🎉 ALL TESTS PASSED! The folder creation logic is working correctly." -ForegroundColor Green
} else {
    Write-Host "⚠️  Some tests failed." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Cleaning up test folders..." -ForegroundColor Gray
foreach ($testCase in $testCases) {
    if (Test-Path -Path $testCase.ExpectedFolder) {
        Remove-Item -Path $testCase.ExpectedFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "Cleanup completed." -ForegroundColor Green

