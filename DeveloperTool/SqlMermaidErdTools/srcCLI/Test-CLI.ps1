#Requires -Version 7.0

<#
.SYNOPSIS
    Automated regression tests for SqlMermaidErdTools CLI
.DESCRIPTION
    Tests the CLI tool using the same test files and baselines as the main regression tests.
    Validates all commands: sql-to-mmd, mmd-to-sql, diff, license, version.
.PARAMETER ResetBaseline
    Create/reset baseline files from current CLI outputs
.PARAMETER SkipInstall
    Skip reinstalling the CLI tool (assumes it's already installed)
.EXAMPLE
    .\Test-CLI.ps1
    Run all tests (will reinstall CLI first)
.EXAMPLE
    .\Test-CLI.ps1 -ResetBaseline
    Reset baseline files
.EXAMPLE
    .\Test-CLI.ps1 -SkipInstall
    Run tests without reinstalling CLI
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$ResetBaseline = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipInstall = $false
)

$ErrorActionPreference = "Stop"

# Color output helpers
function Write-Header($message) {
    Write-Host "`n═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host $message -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
}

function Write-Success($message) {
    Write-Host "✅ $message" -ForegroundColor Green
}

function Write-Failure($message) {
    Write-Host "❌ $message" -ForegroundColor Red
}

function Write-Info($message) {
    Write-Host "ℹ️  $message" -ForegroundColor Yellow
}

# Setup paths
$cliRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent $cliRoot
$testSuiteRoot = Join-Path $projectRoot "TestSuite"
$regressionRoot = Join-Path $testSuiteRoot "RegressionTest"
$baselineRoot = Join-Path $regressionRoot "Baseline"
$cliTestRoot = Join-Path $cliRoot "TestResults"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$currentTestFolder = Join-Path $cliTestRoot $timestamp

# Test input files (same as main regression tests)
$testFilesRoot = Join-Path $projectRoot "TestFiles"
$testSqlFile = Join-Path $testFilesRoot "test.sql"
$testBeforeMmdFile = Join-Path $testFilesRoot "testBeforeChange.mmd"
$testAfterMmdFile = Join-Path $testFilesRoot "testAfterChange.mmd"

# Create directories
Write-Header "Setting Up CLI Test Environment"
Write-Info "Test folder: $currentTestFolder"
@($cliTestRoot, $currentTestFolder) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
        Write-Info "Created directory: $_"
    }
}

# Initialize report
$reportPath = Join-Path $currentTestFolder "CLI_TEST_REPORT.md"
$report = New-Object System.Text.StringBuilder

[void]$report.AppendLine("# SqlMermaidErdTools CLI Test Report")
[void]$report.AppendLine("")
[void]$report.AppendLine("**Test Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$report.AppendLine("**Test Folder:** ``$currentTestFolder``")
[void]$report.AppendLine("**Mode:** $(if ($ResetBaseline) { 'BASELINE CREATION' } else { 'REGRESSION TEST' })")
[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# Test results tracking
$totalTests = 0
$passedTests = 0
$failedTests = 0
$baselineCreated = $false

# Step 1: Build and Install CLI (unless skipped)
if (-not $SkipInstall) {
    Write-Header "Building and Installing CLI Tool"
    
    # Uninstall existing version
    Write-Info "Uninstalling existing CLI tool (if any)..."
    $null = Start-Process -FilePath "dotnet" -ArgumentList "tool","uninstall","-g","SqlMermaidErdTools.CLI" -WindowStyle Hidden -Wait -PassThru
    
    # Build project
    Write-Info "Building CLI project..."
    $buildOutput = Start-Process -FilePath "dotnet" -ArgumentList "build","`"$cliRoot/SqlMermaidErdTools.CLI.csproj`"","-c","Release","--nologo","-v","quiet" -WindowStyle Hidden -Wait -PassThru
    if ($buildOutput.ExitCode -ne 0) {
        Write-Failure "Failed to build CLI project"
        exit 1
    }
    Write-Success "CLI project built"
    
    # Pack as tool
    Write-Info "Packing as .NET Global Tool..."
    $packOutput = Start-Process -FilePath "dotnet" -ArgumentList "pack","`"$cliRoot/SqlMermaidErdTools.CLI.csproj`"","-c","Release","--nologo","-v","quiet" -WindowStyle Hidden -Wait -PassThru
    if ($packOutput.ExitCode -ne 0) {
        Write-Failure "Failed to pack CLI tool"
        exit 1
    }
    Write-Success "CLI tool packed"
    
    # Install globally
    Write-Info "Installing globally..."
    $installOutput = Start-Process -FilePath "dotnet" -ArgumentList "tool","install","-g","SqlMermaidErdTools.CLI","--add-source","`"$cliRoot/bin/Release`"" -WindowStyle Hidden -Wait -PassThru
    if ($installOutput.ExitCode -ne 0) {
        Write-Failure "Failed to install CLI tool"
        exit 1
    }
    Write-Success "CLI tool installed globally"
} else {
    Write-Header "Skipping CLI Installation"
    Write-Info "Using existing CLI installation"
}

# Step 2: Verify CLI Installation
Write-Header "Verifying CLI Installation"

$versionOutput = sqlmermaid version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Failure "CLI tool not found or not working"
    [void]$report.AppendLine("## ❌ CLI Installation Failed")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("Could not execute 'sqlmermaid version'. Please install the CLI tool.")
    [void]$report.AppendLine("")
    $report.ToString() | Out-File $reportPath -Encoding UTF8
    exit 1
}

Write-Success "CLI tool is installed and working"
Write-Info "Version output:"
$versionOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

[void]$report.AppendLine("## CLI Installation")
[void]$report.AppendLine("")
[void]$report.AppendLine("**Status:** ✅ CLI tool verified")
[void]$report.AppendLine("")
[void]$report.AppendLine("``````")
[void]$report.AppendLine($versionOutput)
[void]$report.AppendLine("``````")
[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# Step 3: Activate Test License (Pro tier for unlimited tables)
Write-Header "Activating Test License"

Write-Info "Activating Pro license for testing..."
$activateOutput = sqlmermaid license activate --key SQLMMD-PRO-TEST-AUTOTEST-KEY --email autotest@sqlmermaid.tools 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Success "Test license activated"
} else {
    Write-Failure "Failed to activate test license (continuing anyway)"
}

# Verify license
$licenseOutput = sqlmermaid license show 2>&1
Write-Info "Current license:"
$licenseOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

[void]$report.AppendLine("## License Status")
[void]$report.AppendLine("")
[void]$report.AppendLine("**Test License Activated:** Pro tier (unlimited tables)")
[void]$report.AppendLine("")
[void]$report.AppendLine("``````")
[void]$report.AppendLine($licenseOutput)
[void]$report.AppendLine("``````")
[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# Step 4: Test SQL → Mermaid Conversion
Write-Header "Testing SQL → Mermaid Conversion"

[void]$report.AppendLine("## Test 1: SQL → Mermaid (test.sql)")
[void]$report.AppendLine("")

if (-not (Test-Path $testSqlFile)) {
    Write-Failure "Test SQL file not found: $testSqlFile"
    [void]$report.AppendLine("- ❌ FAIL - Test file not found")
    $failedTests++
    $totalTests++
} else {
    $totalTests++
    $outputMmdFile = Join-Path $currentTestFolder "test_output.mmd"
    $baselineMmdFile = Join-Path $baselineRoot "CLI_test_output.mmd"
    
    Write-Info "Converting SQL to Mermaid..."
    Write-Info "Command: sqlmermaid sql-to-mmd `"$testSqlFile`" -o `"$outputMmdFile`""
    
    $conversionOutput = sqlmermaid sql-to-mmd "$testSqlFile" -o "$outputMmdFile" 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Failure "Conversion failed"
        [void]$report.AppendLine("- ❌ FAIL - Conversion failed")
        [void]$report.AppendLine("``````")
        [void]$report.AppendLine($conversionOutput)
        [void]$report.AppendLine("``````")
        $failedTests++
    } elseif (-not (Test-Path $outputMmdFile)) {
        Write-Failure "Output file not created"
        [void]$report.AppendLine("- ❌ FAIL - Output file not created")
        $failedTests++
    } else {
        Write-Success "Conversion succeeded"
        
        if ($ResetBaseline) {
            # RESET MODE: Create baseline
            Copy-Item $outputMmdFile $baselineMmdFile -Force
            Write-Info "Created baseline: $baselineMmdFile"
            [void]$report.AppendLine("- ✅ Baseline created: $(([System.IO.FileInfo]$outputMmdFile).Length) bytes")
            $passedTests++
            $baselineCreated = $true
        } else {
            # TEST MODE: Compare with baseline
            if (-not (Test-Path $baselineMmdFile)) {
                Write-Failure "Baseline not found: $baselineMmdFile"
                [void]$report.AppendLine("- ❌ FAIL - Baseline not found (run with -ResetBaseline)")
                $failedTests++
            } else {
                $baselineLines = Get-Content $baselineMmdFile
                $outputLines = Get-Content $outputMmdFile
                $differences = Compare-Object -ReferenceObject $baselineLines -DifferenceObject $outputLines
                
                if ($null -eq $differences -or $differences.Count -eq 0) {
                    Write-Success "Output matches baseline"
                    [void]$report.AppendLine("- ✅ PASS - Output matches baseline")
                    $passedTests++
                } else {
                    Write-Failure "Output differs from baseline ($($differences.Count) differences)"
                    [void]$report.AppendLine("- ❌ FAIL - Output differs ($($differences.Count) line differences)")
                    $failedTests++
                    
                    # Save diff
                    $diffFile = Join-Path $currentTestFolder "DIFF_test_output.mmd.txt"
                    "=== BASELINE vs OUTPUT ===" | Out-File $diffFile
                    $differences | ForEach-Object {
                        $indicator = if ($_.SideIndicator -eq '<=') { 'BASELINE' } else { 'OUTPUT' }
                        "[$indicator] $($_.InputObject)" | Out-File $diffFile -Append
                    }
                    Write-Info "Diff saved: $diffFile"
                }
            }
        }
    }
}

[void]$report.AppendLine("")

# Step 5: Test Mermaid → SQL Conversion (All Dialects)
Write-Header "Testing Mermaid → SQL Conversion (All Dialects)"

[void]$report.AppendLine("## Test 2: Mermaid → SQL (All Dialects)")
[void]$report.AppendLine("")

$dialects = @("AnsiSql", "SqlServer", "PostgreSql", "MySql")
$testMmdFile = Join-Path $currentTestFolder "test_output.mmd"

if (-not (Test-Path $testMmdFile)) {
    Write-Info "Using test Mermaid file from baseline..."
    $testMmdFile = Join-Path $baselineRoot "CLI_test_output.mmd"
}

if (-not (Test-Path $testMmdFile)) {
    Write-Failure "No Mermaid file available for testing"
    [void]$report.AppendLine("- ❌ FAIL - No Mermaid file available")
    $failedTests += 4
    $totalTests += 4
} else {
    foreach ($dialect in $dialects) {
        $totalTests++
        $outputSqlFile = Join-Path $currentTestFolder "test_$dialect.sql"
        $baselineSqlFile = Join-Path $baselineRoot "CLI_test_$dialect.sql"
        
        Write-Info "Converting to $dialect..."
        Write-Info "Command: sqlmermaid mmd-to-sql `"$testMmdFile`" -d $dialect -o `"$outputSqlFile`""
        
        $conversionOutput = sqlmermaid mmd-to-sql "$testMmdFile" -d $dialect -o "$outputSqlFile" 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Failure "$dialect conversion failed"
            [void]$report.AppendLine("- ❌ FAIL - $dialect conversion failed")
            $failedTests++
        } elseif (-not (Test-Path $outputSqlFile)) {
            Write-Failure "$dialect output file not created"
            [void]$report.AppendLine("- ❌ FAIL - $dialect output not created")
            $failedTests++
        } else {
            Write-Success "$dialect conversion succeeded"
            
            if ($ResetBaseline) {
                # RESET MODE: Create baseline
                Copy-Item $outputSqlFile $baselineSqlFile -Force
                Write-Info "Created baseline: $baselineSqlFile"
                [void]$report.AppendLine("- ✅ $dialect baseline created: $(([System.IO.FileInfo]$outputSqlFile).Length) bytes")
                $passedTests++
                $baselineCreated = $true
            } else {
                # TEST MODE: Compare with baseline
                if (-not (Test-Path $baselineSqlFile)) {
                    Write-Failure "$dialect baseline not found"
                    [void]$report.AppendLine("- ❌ FAIL - $dialect baseline not found")
                    $failedTests++
                } else {
                    $baselineLines = Get-Content $baselineSqlFile
                    $outputLines = Get-Content $outputSqlFile
                    $differences = Compare-Object -ReferenceObject $baselineLines -DifferenceObject $outputLines
                    
                    if ($null -eq $differences -or $differences.Count -eq 0) {
                        Write-Success "$dialect output matches baseline"
                        [void]$report.AppendLine("- ✅ PASS - $dialect matches baseline")
                        $passedTests++
                    } else {
                        Write-Failure "$dialect output differs ($($differences.Count) differences)"
                        [void]$report.AppendLine("- ❌ FAIL - $dialect differs ($($differences.Count) line differences)")
                        $failedTests++
                        
                        # Save diff
                        $diffFile = Join-Path $currentTestFolder "DIFF_test_$dialect.sql.txt"
                        "=== BASELINE vs OUTPUT ($dialect) ===" | Out-File $diffFile
                        $differences | ForEach-Object {
                            $indicator = if ($_.SideIndicator -eq '<=') { 'BASELINE' } else { 'OUTPUT' }
                            "[$indicator] $($_.InputObject)" | Out-File $diffFile -Append
                        }
                    }
                }
            }
        }
    }
}

[void]$report.AppendLine("")

# Step 6: Test Diff Command
Write-Header "Testing Mermaid Diff → SQL Migration"

[void]$report.AppendLine("## Test 3: Mermaid Diff (Migration Generation)")
[void]$report.AppendLine("")

if (-not (Test-Path $testBeforeMmdFile) -or -not (Test-Path $testAfterMmdFile)) {
    Write-Failure "Test Mermaid diff files not found"
    [void]$report.AppendLine("- ❌ FAIL - Test files not found")
    $failedTests += 4
    $totalTests += 4
} else {
    foreach ($dialect in $dialects) {
        $totalTests++
        $outputMigrationFile = Join-Path $currentTestFolder "migration_$dialect.sql"
        $baselineMigrationFile = Join-Path $baselineRoot "CLI_migration_$dialect.sql"
        
        Write-Info "Generating migration for $dialect..."
        Write-Info "Command: sqlmermaid diff `"$testBeforeMmdFile`" `"$testAfterMmdFile`" -d $dialect -o `"$outputMigrationFile`""
        
        $diffOutput = sqlmermaid diff "$testBeforeMmdFile" "$testAfterMmdFile" -d $dialect -o "$outputMigrationFile" 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Failure "$dialect migration failed"
            [void]$report.AppendLine("- ❌ FAIL - $dialect migration failed")
            $failedTests++
        } elseif (-not (Test-Path $outputMigrationFile)) {
            Write-Failure "$dialect migration output not created"
            [void]$report.AppendLine("- ❌ FAIL - $dialect migration output not created")
            $failedTests++
        } else {
            Write-Success "$dialect migration succeeded"
            
            if ($ResetBaseline) {
                # RESET MODE: Create baseline
                Copy-Item $outputMigrationFile $baselineMigrationFile -Force
                Write-Info "Created baseline: $baselineMigrationFile"
                [void]$report.AppendLine("- ✅ $dialect migration baseline created: $(([System.IO.FileInfo]$outputMigrationFile).Length) bytes")
                $passedTests++
                $baselineCreated = $true
            } else {
                # TEST MODE: Compare with baseline
                if (-not (Test-Path $baselineMigrationFile)) {
                    Write-Failure "$dialect migration baseline not found"
                    [void]$report.AppendLine("- ❌ FAIL - $dialect migration baseline not found")
                    $failedTests++
                } else {
                    $baselineLines = Get-Content $baselineMigrationFile
                    $outputLines = Get-Content $outputMigrationFile
                    $differences = Compare-Object -ReferenceObject $baselineLines -DifferenceObject $outputLines
                    
                    if ($null -eq $differences -or $differences.Count -eq 0) {
                        Write-Success "$dialect migration matches baseline"
                        [void]$report.AppendLine("- ✅ PASS - $dialect migration matches baseline")
                        $passedTests++
                    } else {
                        Write-Failure "$dialect migration differs ($($differences.Count) differences)"
                        [void]$report.AppendLine("- ❌ FAIL - $dialect migration differs ($($differences.Count) line differences)")
                        $failedTests++
                        
                        # Save diff
                        $diffFile = Join-Path $currentTestFolder "DIFF_migration_$dialect.sql.txt"
                        "=== BASELINE vs OUTPUT ($dialect) ===" | Out-File $diffFile
                        $differences | ForEach-Object {
                            $indicator = if ($_.SideIndicator -eq '<=') { 'BASELINE' } else { 'OUTPUT' }
                            "[$indicator] $($_.InputObject)" | Out-File $diffFile -Append
                        }
                    }
                }
            }
        }
    }
}

[void]$report.AppendLine("")

# Summary
Write-Header "CLI Test Summary"

$passRate = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 2) } else { 0 }

Write-Host "Total Tests:  $totalTests" -ForegroundColor Cyan
Write-Host "Passed:       $passedTests" -ForegroundColor Green
Write-Host "Failed:       $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { "Green" } else { "Red" })
Write-Host "Pass Rate:    $passRate%" -ForegroundColor $(if ($passRate -eq 100) { "Green" } else { "Yellow" })

[void]$report.AppendLine("---")
[void]$report.AppendLine("")
[void]$report.AppendLine("## Summary")
[void]$report.AppendLine("")
[void]$report.AppendLine("| Metric | Value |")
[void]$report.AppendLine("|--------|-------|")
[void]$report.AppendLine("| **Total Tests** | $totalTests |")
[void]$report.AppendLine("| **Passed** | $passedTests ✅ |")
[void]$report.AppendLine("| **Failed** | $failedTests $(if ($failedTests -eq 0) { '✅' } else { '❌' }) |")
[void]$report.AppendLine("| **Pass Rate** | $passRate% |")
[void]$report.AppendLine("")

if ($baselineCreated) {
    [void]$report.AppendLine("### ⚠️ Baseline Files Created")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("Baseline files have been created/updated in:")
    [void]$report.AppendLine("``````")
    [void]$report.AppendLine($baselineRoot)
    [void]$report.AppendLine("``````")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("**Run the test again to perform actual regression testing.**")
    [void]$report.AppendLine("")
}

if ($failedTests -eq 0 -and -not $baselineCreated) {
    [void]$report.AppendLine("### ✅ All Tests Passed!")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("No regressions detected. All CLI outputs match the baseline files exactly.")
    [void]$report.AppendLine("")
} elseif ($failedTests -gt 0) {
    [void]$report.AppendLine("### ⚠️ Regressions Detected!")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("One or more CLI tests failed. Review the differences to identify regressions.")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("**Test artifacts saved to:**")
    [void]$report.AppendLine("``````")
    [void]$report.AppendLine($currentTestFolder)
    [void]$report.AppendLine("``````")
    [void]$report.AppendLine("")
}

[void]$report.AppendLine("---")
[void]$report.AppendLine("")
[void]$report.AppendLine("### Test Input Files")
[void]$report.AppendLine("")
[void]$report.AppendLine("- **SQL:** ``$testSqlFile``")
[void]$report.AppendLine("- **Mermaid Before:** ``$testBeforeMmdFile``")
[void]$report.AppendLine("- **Mermaid After:** ``$testAfterMmdFile``")
[void]$report.AppendLine("")

# Save report
$report.ToString() | Out-File $reportPath -Encoding UTF8

Write-Success "Report saved: $reportPath"
Write-Host ""

# Cleanup: Deactivate test license
Write-Header "Cleanup"
Write-Info "Deactivating test license..."
sqlmermaid license deactivate 2>&1 | Out-Null
Write-Success "Test license deactivated"

# Open report
Write-Info "Opening report..."
Start-Process "cursor" -ArgumentList "`"$reportPath`"" -ErrorAction SilentlyContinue

Write-Host ""
if ($failedTests -eq 0 -and -not $baselineCreated) {
    Write-Success "All CLI tests passed! ✅"
    exit 0
} elseif ($baselineCreated) {
    Write-Info "Baseline created. Run again without -ResetBaseline to test."
    exit 0
} else {
    Write-Failure "Some tests failed. Check the report for details."
    exit 1
}

