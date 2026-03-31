#Requires -Version 7.0

<#
.SYNOPSIS
    Comprehensive test suite for SqlMermaidErdTools (Unit Tests + Regression Tests + Optional NuGet Deployment)
.DESCRIPTION
    Runs unit tests first, then regression tests with standard input files, captures outputs,
    and compares against baseline files to detect regressions.
    
    Optionally increments version and deploys to NuGet.org if all tests pass.
    
    First run: Creates baseline files
    Subsequent runs: Compares against baseline and reports differences
.PARAMETER ResetBaseline
    Create/reset baseline files from current test outputs
.PARAMETER Configuration
    Build configuration (Debug or Release). Default: Release
.PARAMETER PublishOnSuccess
    If all tests pass, increment version and publish to NuGet.org
.PARAMETER NewVersion
    Override auto-increment with specific version (e.g., "1.0.0")
.EXAMPLE
    .\Run-RegressionTests.ps1
    Run unit tests and regression tests (no deployment)
.EXAMPLE
    .\Run-RegressionTests.ps1 -ResetBaseline
    Reset baseline files
.EXAMPLE
    .\Run-RegressionTests.ps1 -PublishOnSuccess
    Run all tests, and if they pass, auto-increment version and deploy to NuGet
.EXAMPLE
    .\Run-RegressionTests.ps1 -PublishOnSuccess -NewVersion "1.0.0"
    Run all tests, and if they pass, set version to 1.0.0 and deploy to NuGet
.EXAMPLE
    .\Run-RegressionTests.ps1 -PublishOnSuccess -NugetApiKey "your-api-key"
    Run all tests, and if they pass, deploy to NuGet using the provided API key
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$ResetBaseline = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$Configuration = "Release",
    
    [Parameter(Mandatory=$false)]
    [switch]$PublishOnSuccess = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$NewVersion = "",
    
    [Parameter(Mandatory=$false)]
    [string]$NugetApiKey = ""
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
$testSuiteRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Split-Path -Parent $testSuiteRoot
$regressionRoot = Join-Path $testSuiteRoot "RegressionTest"
$baselineRoot = Join-Path $regressionRoot "Baseline"
$baselineInputRoot = Join-Path $regressionRoot "BaselineInput"
$auditRoot = Join-Path $regressionRoot "Audit"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$currentAuditFolder = Join-Path $auditRoot $timestamp

# Test input files
$testSqlFile = Join-Path $scriptRoot "TestFiles" "test.sql"
$testBeforeMmdFile = Join-Path $scriptRoot "TestFiles" "testBeforeChange.mmd"
$testAfterMmdFile = Join-Path $scriptRoot "TestFiles" "testAfterChange.mmd"

# Test executables (using correct project names)
$fullCircleTestExe = Join-Path $testSuiteRoot "ComprehensiveTest" "bin" $Configuration "net10.0" "ComprehensiveTest.exe"
$mermaidDiffTestExe = Join-Path $testSuiteRoot "TestMmdDiff" "bin" $Configuration "net10.0" "TestMmdDiff.exe"

# Create directories
Write-Header "Setting Up Regression Test Environment"
Write-Info "Audit folder: $currentAuditFolder"
@($regressionRoot, $baselineRoot, $baselineInputRoot, $auditRoot, $currentAuditFolder) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
        Write-Info "Created directory: $_"
    }
}

# Initialize report BEFORE running tests
$reportPath = Join-Path $currentAuditFolder "REGRESSION_TEST_REPORT.md"
$report = New-Object System.Text.StringBuilder

[void]$report.AppendLine("# SqlMermaidErdTools Regression Test Report")
[void]$report.AppendLine("")
[void]$report.AppendLine("**Test Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$report.AppendLine("**Audit Folder:** ``$currentAuditFolder``")
[void]$report.AppendLine("**Configuration:** $Configuration")
[void]$report.AppendLine("**Mode:** $(if ($ResetBaseline) { 'BASELINE CREATION' } else { 'REGRESSION TEST' })")
[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# STEP 0: Run Unit Tests FIRST (with static input files)
Write-Header "Running Unit Tests"
Write-Info "Executing unit tests from SqlMermaidErdTools.Tests..."
$unitTestProject = Join-Path $scriptRoot "tests\SqlMermaidErdTools.Tests\SqlMermaidErdTools.Tests.csproj"
$testUnit = Start-Process -FilePath "dotnet" -ArgumentList "test","`"$unitTestProject`"","-c",$Configuration,"--nologo","--verbosity","minimal" -WindowStyle Hidden -Wait -PassThru
if ($testUnit.ExitCode -ne 0) {
    Write-Failure "Unit tests failed! Fix unit tests before continuing."
    [void]$report.AppendLine("## ❌ Unit Tests Failed")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("Unit tests must pass before regression tests can run.")
    [void]$report.AppendLine("")
    
    # Save report and exit
    $report.ToString() | Out-File $reportPath -Encoding UTF8
    
    Write-Info "Report saved: $reportPath"
    exit 1
}
Write-Success "All unit tests passed"
Write-Host ""

[void]$report.AppendLine("## Unit Tests")
[void]$report.AppendLine("")
[void]$report.AppendLine("**Status:** ✅ All unit tests passed")
[void]$report.AppendLine("")
[void]$report.AppendLine("---")
[void]$report.AppendLine("")

# STEP 1: Build main project first (required for RuntimeManager to work)
Write-Header "Building Main Project"
Write-Info "Building SqlMermaidErdTools..."
$mainProjectPath = Join-Path $scriptRoot "src\SqlMermaidErdTools\SqlMermaidErdTools.csproj"
$buildMain = Start-Process -FilePath "dotnet" -ArgumentList "build","`"$mainProjectPath`"","-c",$Configuration,"--nologo","-v","quiet" -WindowStyle Hidden -Wait -PassThru
if ($buildMain.ExitCode -ne 0) {
    Write-Failure "Failed to build main project"
    exit 1
}
Write-Success "Main project built successfully"

# STEP 2: Build all test projects
Write-Header "Building Test Projects"
Write-Info "Building ComprehensiveTest..."
$buildComp = Start-Process -FilePath "dotnet" -ArgumentList "build","`"$testSuiteRoot\ComprehensiveTest\ComprehensiveTest.csproj`"","-c",$Configuration,"--nologo","-v","quiet" -WindowStyle Hidden -Wait -PassThru
if ($buildComp.ExitCode -ne 0) {
    Write-Failure "Failed to build ComprehensiveTest"
    exit 1
}

Write-Info "Building TestMmdDiff..."
$buildDiff = Start-Process -FilePath "dotnet" -ArgumentList "build","`"$testSuiteRoot\TestMmdDiff\TestMmdDiff.csproj`"","-c",$Configuration,"--nologo","-v","quiet" -WindowStyle Hidden -Wait -PassThru
if ($buildDiff.ExitCode -ne 0) {
    Write-Failure "Failed to build TestMmdDiff"
    exit 1
}

Write-Success "All test projects built successfully"

# Test results tracking (report already initialized above)
$totalTests = 0
$passedTests = 0
$failedTests = 0
$baselineCreated = $false

# Baseline input file mapping
$baselineMapping = @{
    "FullCircle_roundtrip.mmd" = @("test.sql")
    "FullCircle_AnsiSql_roundtrip_AnsiSql.sql" = @("test.sql")
    "FullCircle_SqlServer_roundtrip_SqlServer.sql" = @("test.sql")
    "FullCircle_PostgreSql_roundtrip_PostgreSql.sql" = @("test.sql")
    "FullCircle_MySql_roundtrip_MySql.sql" = @("test.sql")
    "MermaidDiff_Direction1_AnsiSql.sql" = @("testBeforeChange.mmd", "testAfterChange.mmd")
    "MermaidDiff_Direction1_SqlServer.sql" = @("testBeforeChange.mmd", "testAfterChange.mmd")
    "MermaidDiff_Direction1_PostgreSql.sql" = @("testBeforeChange.mmd", "testAfterChange.mmd")
    "MermaidDiff_Direction1_MySql.sql" = @("testBeforeChange.mmd", "testAfterChange.mmd")
    "MermaidDiff_Direction2_AnsiSql.sql" = @("testBeforeChange.mmd", "testAfterChange.mmd")
    "MermaidDiff_Direction2_SqlServer.sql" = @("testBeforeChange.mmd", "testAfterChange.mmd")
    "MermaidDiff_Direction2_PostgreSql.sql" = @("testBeforeChange.mmd", "testAfterChange.mmd")
    "MermaidDiff_Direction2_MySql.sql" = @("testBeforeChange.mmd", "testAfterChange.mmd")
}

# Verify and store input files
Write-Header "Verifying Input Files"
$inputFiles = @{
    "test.sql" = $testSqlFile
    "testBeforeChange.mmd" = $testBeforeMmdFile
    "testAfterChange.mmd" = $testAfterMmdFile
}

foreach ($inputName in $inputFiles.Keys) {
    $inputPath = $inputFiles[$inputName]
    if (-not (Test-Path $inputPath)) {
        Write-Failure "Input file not found: $inputPath"
        exit 1
    }
    Write-Info "Found input file: $inputName"
    
    # Store input file in BaselineInput if creating baseline
    if ($ResetBaseline) {
        $baselineInputFile = Join-Path $baselineInputRoot $inputName
        Copy-Item $inputPath $baselineInputFile -Force
        Write-Info "Stored input file in baseline: $inputName"
    } else {
        # Verify input file hasn't changed
        $baselineInputFile = Join-Path $baselineInputRoot $inputName
        if (Test-Path $baselineInputFile) {
            $currentContent = Get-FileHash $inputPath -Algorithm SHA256
            $baselineContent = Get-FileHash $baselineInputFile -Algorithm SHA256
            if ($currentContent.Hash -ne $baselineContent.Hash) {
                Write-Failure "Input file has changed: $inputName"
                Write-Info "Current hash: $($currentContent.Hash)"
                Write-Info "Baseline hash: $($baselineContent.Hash)"
                [void]$report.AppendLine("### ⚠️ Input File Changed")
                [void]$report.AppendLine("")
                [void]$report.AppendLine("**$inputName** has been modified since baseline was created.")
                [void]$report.AppendLine("This may cause test failures. Consider resetting baseline with `-ResetBaseline`.")
                [void]$report.AppendLine("")
            } else {
                Write-Success "Input file matches baseline: $inputName"
            }
        }
    }
}

# Create baseline mapping file
$mappingFile = Join-Path $baselineRoot "baseline-mapping.json"
if ($ResetBaseline -or -not (Test-Path $mappingFile)) {
    $mappingJson = $baselineMapping | ConvertTo-Json -Depth 10
    $mappingJson | Out-File $mappingFile -Encoding UTF8
    Write-Info "Created baseline mapping file: baseline-mapping.json"
}

Write-Host ""

# Test 1: Full Circle Test
Write-Header "Running Full Circle Test"

[void]$report.AppendLine("## Test 1: Full Circle Conversion (test.sql)")
[void]$report.AppendLine("")
[void]$report.AppendLine("**Test:** SQL → Mermaid → SQL (4 dialects)")
[void]$report.AppendLine("")

Write-Info "Executing ComprehensiveTest..."

# Determine export folder based on mode
if ($ResetBaseline) {
    # Reset mode: Use temporary folder, will copy outputs to Baseline
    Write-Info "Mode: Creating baseline - using temporary export folder"
    Push-Location $scriptRoot
    try {
        $fullCircleOutput = & $fullCircleTestExe 2>&1
        $fullCircleExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
} else {
    # Regression test mode: Export directly to audit folder
    $auditFullCircleExport = Join-Path $currentAuditFolder "FullCircle_Export"
    Write-Info "Mode: Regression test - exporting to audit folder"
    Write-Info "Export path: $auditFullCircleExport"
    Push-Location $scriptRoot
    try {
        $fullCircleOutput = & $fullCircleTestExe $auditFullCircleExport 2>&1
        $fullCircleExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

if ($fullCircleExitCode -eq 0) {
    Write-Success "ComprehensiveTest completed successfully"
    
    # Determine source folder based on mode
    if ($ResetBaseline) {
        # Find the most recent FullCircle_Export folder in the workspace root
        $exportFolders = Get-ChildItem -Path $scriptRoot -Directory -Filter "FullCircle_Export_*" | Sort-Object LastWriteTime -Descending
        if ($exportFolders.Count -eq 0) {
            Write-Failure "Export folder not found"
            [void]$report.AppendLine("- ❌ FAIL - Export folder not created")
            $failedTests += 5
            $totalTests += 5
        } else {
            $latestExportFolder = $exportFolders[0].FullName
            Write-Info "Found export folder: $($exportFolders[0].Name)"
        }
    } else {
        # Use audit folder
        $latestExportFolder = $auditFullCircleExport
        if (-not (Test-Path $latestExportFolder)) {
            Write-Failure "Audit export folder not created"
            [void]$report.AppendLine("- ❌ FAIL - Audit export folder not created")
            $failedTests += 5
            $totalTests += 5
        }
    }
    
    # Process files if export folder exists
    if (Test-Path $latestExportFolder) {
        # Key files to check (matching actual ComprehensiveTest output)
        $keyFiles = @(
            "roundtrip.mmd",
            "AnsiSql\roundtrip_AnsiSql.sql",
            "SqlServer\roundtrip_SqlServer.sql",
            "PostgreSql\roundtrip_PostgreSql.sql",
            "MySql\roundtrip_MySql.sql"
        )
        
        foreach ($file in $keyFiles) {
            $totalTests++
            $sourceFile = Join-Path $latestExportFolder $file
            # Sanitize file path for baseline name (replace backslashes with underscores)
            $baselineFileName = "FullCircle_" + ($file -replace '\\', '_')
            $baselineFile = Join-Path $baselineRoot $baselineFileName
            
            if (Test-Path $sourceFile) {
                if ($ResetBaseline) {
                    # RESET MODE: Create/update baseline files
                    Copy-Item $sourceFile $baselineFile -Force
                    Write-Info "Created baseline: $baselineFileName"
                    $inputFilesForThis = $baselineMapping[$baselineFileName]
                    $inputInfo = if ($inputFilesForThis) { " (from: $($inputFilesForThis -join ', '))" } else { "" }
                    [void]$report.AppendLine("- **$file**: ✅ Baseline created ($(([System.IO.FileInfo]$sourceFile).Length) bytes)$inputInfo")
                    $passedTests++
                    $baselineCreated = $true
                } else {
                    # REGRESSION MODE: Compare with baseline
                    if (-not (Test-Path $baselineFile)) {
                        Write-Failure "Baseline file not found: $baselineFileName"
                        [void]$report.AppendLine("- **$file**: ❌ FAIL - Baseline file not found (run with -ResetBaseline first)")
                        $failedTests++
                    } else {
                        # Read as arrays for line-by-line comparison
                        $baselineLines = Get-Content $baselineFile
                        $sourceLines = Get-Content $sourceFile
                        
                        # Compare arrays
                        $differences = Compare-Object -ReferenceObject $baselineLines -DifferenceObject $sourceLines
                        
                        if ($null -eq $differences -or $differences.Count -eq 0) {
                            Write-Success "$file matches baseline"
                            [void]$report.AppendLine("- **$file**: ✅ PASS - Exact match with baseline")
                            $passedTests++
                        } else {
                            Write-Failure "$file differs from baseline ($($differences.Count) differences)"
                            [void]$report.AppendLine("- **$file**: ❌ FAIL - Content differs from baseline ($($differences.Count) line differences)")
                            $failedTests++
                            
                            # Save detailed diff for inspection in audit folder
                            $diffFileName = "DIFF_$baselineFileName.txt"
                            $diffFile = Join-Path $currentAuditFolder $diffFileName
                            
                            "=== COMPARISON SUMMARY ===" | Out-File $diffFile
                            "Baseline lines: $($baselineLines.Count)" | Out-File $diffFile -Append
                            "Current lines: $($sourceLines.Count)" | Out-File $diffFile -Append
                            "Differences: $($differences.Count)" | Out-File $diffFile -Append
                            "" | Out-File $diffFile -Append
                            
                            "=== LINE-BY-LINE DIFFERENCES ===" | Out-File $diffFile -Append
                            foreach ($diff in $differences) {
                                $indicator = if ($diff.SideIndicator -eq '<=') { 'BASELINE ONLY' } else { 'CURRENT ONLY' }
                                "[$indicator] $($diff.InputObject)" | Out-File $diffFile -Append
                            }
                            
                            "" | Out-File $diffFile -Append
                            "=== BASELINE CONTENT ===" | Out-File $diffFile -Append
                            $baselineLines | Out-File $diffFile -Append
                            
                            "" | Out-File $diffFile -Append
                            "=== CURRENT CONTENT ===" | Out-File $diffFile -Append
                            $sourceLines | Out-File $diffFile -Append
                            
                            Write-Info "Saved diff: $diffFileName"
                        }
                    }
                }
            } else {
                Write-Failure "$file not found in export folder"
                [void]$report.AppendLine("- **$file**: ❌ FAIL - Output file not generated")
                $failedTests++
            }
        }
        
        # Clean up temporary export folder only in reset mode
        if ($ResetBaseline) {
            Remove-Item $latestExportFolder -Recurse -Force
            Write-Info "Cleaned up temporary export folder"
        }
    }
} else {
    Write-Failure "ComprehensiveTest failed with exit code $fullCircleExitCode"
    [void]$report.AppendLine("- ❌ FAIL - Test execution failed (exit code: $fullCircleExitCode)")
    [void]$report.AppendLine("``````")
    [void]$report.AppendLine($fullCircleOutput)
    [void]$report.AppendLine("``````")
    $failedTests += 5
    $totalTests += 5
}

[void]$report.AppendLine("")

# Test 2: Mermaid Diff Test (Both Directions)
Write-Header "Running Mermaid Diff Test"

[void]$report.AppendLine("## Test 2: Mermaid DIFF Bidirectional")
[void]$report.AppendLine("")
[void]$report.AppendLine("**Test:** testBeforeChange.mmd ↔ testAfterChange.mmd (4 dialects × 2 directions)")
[void]$report.AppendLine("")

Write-Info "Executing TestMmdDiff..."

# Determine export folder based on mode
if ($ResetBaseline) {
    # Reset mode: Use temporary folder, will copy outputs to Baseline
    Write-Info "Mode: Creating baseline - using temporary export folder"
    Push-Location $scriptRoot
    try {
        $mermaidDiffOutput = & $mermaidDiffTestExe 2>&1
        $mermaidDiffExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
} else {
    # Regression test mode: Export directly to audit folder
    $auditMmdDiffExport = Join-Path $currentAuditFolder "MmdDiffTest_Export"
    Write-Info "Mode: Regression test - exporting to audit folder"
    Write-Info "Export path: $auditMmdDiffExport"
    Push-Location $scriptRoot
    try {
        $mermaidDiffOutput = & $mermaidDiffTestExe $auditMmdDiffExport 2>&1
        $mermaidDiffExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

if ($mermaidDiffExitCode -eq 0) {
    Write-Success "TestMmdDiff completed successfully"
    
    # Determine source folder based on mode
    if ($ResetBaseline) {
        # Find the most recent MmdDiffTest_Export folder in the workspace root
        $exportFolders = Get-ChildItem -Path $scriptRoot -Directory -Filter "MmdDiffTest_Export_*" | Sort-Object LastWriteTime -Descending
        if ($exportFolders.Count -eq 0) {
            Write-Failure "Export folder not found"
            [void]$report.AppendLine("- ❌ FAIL - Export folder not created")
            $failedTests += 8
            $totalTests += 8
        } else {
            $latestExportFolder = $exportFolders[0].FullName
            Write-Info "Found export folder: $($exportFolders[0].Name)"
        }
    } else {
        # Use audit folder
        $latestExportFolder = $auditMmdDiffExport
        if (-not (Test-Path $latestExportFolder)) {
            Write-Failure "Audit export folder not created"
            [void]$report.AppendLine("- ❌ FAIL - Audit export folder not created")
            $failedTests += 8
            $totalTests += 8
        }
    }
    
    # Process files if export folder exists
    if (Test-Path $latestExportFolder) {
        
        # Key files to check (matching actual TestMmdDiff output structure)
        $dialects = @("AnsiSql", "SqlServer", "PostgreSql", "MySql")
        foreach ($dialect in $dialects) {
            # Direction 1: Before → After (Forward)
            $totalTests++
            $file = "Forward_Before-To-After\$dialect\forward_alter_$dialect.sql"
            $sourceFile = Join-Path $latestExportFolder $file
            $baselineFileName = "MermaidDiff_Direction1_$dialect.sql"
            $baselineFile = Join-Path $baselineRoot $baselineFileName
            
            if (Test-Path $sourceFile) {
                if ($ResetBaseline) {
                    # RESET MODE: Create/update baseline files
                    Copy-Item $sourceFile $baselineFile -Force
                    Write-Info "Created baseline: $baselineFileName"
                    $inputFilesForThis = $baselineMapping[$baselineFileName]
                    $inputInfo = if ($inputFilesForThis) { " (from: $($inputFilesForThis -join ', '))" } else { "" }
                    [void]$report.AppendLine("- **Direction1 ($dialect)**: ✅ Baseline created ($(([System.IO.FileInfo]$sourceFile).Length) bytes)$inputInfo")
                    $passedTests++
                    $baselineCreated = $true
                } else {
                    # REGRESSION MODE: Compare with baseline
                    if (-not (Test-Path $baselineFile)) {
                        Write-Failure "Baseline file not found: $baselineFileName"
                        [void]$report.AppendLine("- **Direction1 ($dialect)**: ❌ FAIL - Baseline file not found (run with -ResetBaseline first)")
                        $failedTests++
                    } else {
                        # Read as arrays for line-by-line comparison
                        $baselineLines = Get-Content $baselineFile
                        $sourceLines = Get-Content $sourceFile
                        
                        # Compare arrays
                        $differences = Compare-Object -ReferenceObject $baselineLines -DifferenceObject $sourceLines
                        
                        if ($null -eq $differences -or $differences.Count -eq 0) {
                            Write-Success "$file matches baseline"
                            [void]$report.AppendLine("- **Direction1 ($dialect)**: ✅ PASS - Exact match with baseline")
                            $passedTests++
                        } else {
                            Write-Failure "$file differs from baseline ($($differences.Count) differences)"
                            [void]$report.AppendLine("- **Direction1 ($dialect)**: ❌ FAIL - Content differs from baseline ($($differences.Count) line differences)")
                            $failedTests++
                            
                            # Save detailed diff for inspection in audit folder
                            $diffFileName = "DIFF_$baselineFileName.txt"
                            $diffFile = Join-Path $currentAuditFolder $diffFileName
                            
                            "=== COMPARISON SUMMARY ===" | Out-File $diffFile
                            "Baseline lines: $($baselineLines.Count)" | Out-File $diffFile -Append
                            "Current lines: $($sourceLines.Count)" | Out-File $diffFile -Append
                            "Differences: $($differences.Count)" | Out-File $diffFile -Append
                            "" | Out-File $diffFile -Append
                            
                            "=== LINE-BY-LINE DIFFERENCES ===" | Out-File $diffFile -Append
                            foreach ($diff in $differences) {
                                $indicator = if ($diff.SideIndicator -eq '<=') { 'BASELINE ONLY' } else { 'CURRENT ONLY' }
                                "[$indicator] $($diff.InputObject)" | Out-File $diffFile -Append
                            }
                            
                            "" | Out-File $diffFile -Append
                            "=== BASELINE CONTENT ===" | Out-File $diffFile -Append
                            $baselineLines | Out-File $diffFile -Append
                            
                            "" | Out-File $diffFile -Append
                            "=== CURRENT CONTENT ===" | Out-File $diffFile -Append
                            $sourceLines | Out-File $diffFile -Append
                            
                            Write-Info "Saved diff: $diffFileName"
                        }
                    }
                }
            } else {
                Write-Failure "$file not found"
                [void]$report.AppendLine("- **Direction1 ($dialect)**: ❌ FAIL - Output file not generated")
                $failedTests++
            }
            
            # Direction 2: After → Before (Reverse)
            $totalTests++
            $file = "Reverse_After-To-Before\$dialect\reverse_alter_$dialect.sql"
            $sourceFile = Join-Path $latestExportFolder $file
            $baselineFileName = "MermaidDiff_Direction2_$dialect.sql"
            $baselineFile = Join-Path $baselineRoot $baselineFileName
            
            if (Test-Path $sourceFile) {
                if ($ResetBaseline) {
                    # RESET MODE: Create/update baseline files
                    Copy-Item $sourceFile $baselineFile -Force
                    Write-Info "Created baseline: $baselineFileName"
                    $inputFilesForThis = $baselineMapping[$baselineFileName]
                    $inputInfo = if ($inputFilesForThis) { " (from: $($inputFilesForThis -join ', '))" } else { "" }
                    [void]$report.AppendLine("- **Direction2 ($dialect)**: ✅ Baseline created ($(([System.IO.FileInfo]$sourceFile).Length) bytes)$inputInfo")
                    $passedTests++
                    $baselineCreated = $true
                } else {
                    # REGRESSION MODE: Compare with baseline
                    if (-not (Test-Path $baselineFile)) {
                        Write-Failure "Baseline file not found: $baselineFileName"
                        [void]$report.AppendLine("- **Direction2 ($dialect)**: ❌ FAIL - Baseline file not found (run with -ResetBaseline first)")
                        $failedTests++
                    } else {
                        # Read as arrays for line-by-line comparison
                        $baselineLines = Get-Content $baselineFile
                        $sourceLines = Get-Content $sourceFile
                        
                        # Compare arrays
                        $differences = Compare-Object -ReferenceObject $baselineLines -DifferenceObject $sourceLines
                        
                        if ($null -eq $differences -or $differences.Count -eq 0) {
                            Write-Success "$file matches baseline"
                            [void]$report.AppendLine("- **Direction2 ($dialect)**: ✅ PASS - Exact match with baseline")
                            $passedTests++
                        } else {
                            Write-Failure "$file differs from baseline ($($differences.Count) differences)"
                            [void]$report.AppendLine("- **Direction2 ($dialect)**: ❌ FAIL - Content differs from baseline ($($differences.Count) line differences)")
                            $failedTests++
                            
                            # Save detailed diff for inspection in audit folder
                            $diffFileName = "DIFF_$baselineFileName.txt"
                            $diffFile = Join-Path $currentAuditFolder $diffFileName
                            
                            "=== COMPARISON SUMMARY ===" | Out-File $diffFile
                            "Baseline lines: $($baselineLines.Count)" | Out-File $diffFile -Append
                            "Current lines: $($sourceLines.Count)" | Out-File $diffFile -Append
                            "Differences: $($differences.Count)" | Out-File $diffFile -Append
                            "" | Out-File $diffFile -Append
                            
                            "=== LINE-BY-LINE DIFFERENCES ===" | Out-File $diffFile -Append
                            foreach ($diff in $differences) {
                                $indicator = if ($diff.SideIndicator -eq '<=') { 'BASELINE ONLY' } else { 'CURRENT ONLY' }
                                "[$indicator] $($diff.InputObject)" | Out-File $diffFile -Append
                            }
                            
                            "" | Out-File $diffFile -Append
                            "=== BASELINE CONTENT ===" | Out-File $diffFile -Append
                            $baselineLines | Out-File $diffFile -Append
                            
                            "" | Out-File $diffFile -Append
                            "=== CURRENT CONTENT ===" | Out-File $diffFile -Append
                            $sourceLines | Out-File $diffFile -Append
                            
                            Write-Info "Saved diff: $diffFileName"
                        }
                    }
                }
            } else {
                Write-Failure "$file not found"
                [void]$report.AppendLine("- **Direction2 ($dialect)**: ❌ FAIL - Output file not generated")
                $failedTests++
            }
        }
        
        # Clean up temporary export folder only in reset mode
        if ($ResetBaseline) {
            Remove-Item $latestExportFolder -Recurse -Force
            Write-Info "Cleaned up temporary export folder"
        }
    }
} else {
    Write-Failure "TestMmdDiff failed with exit code $mermaidDiffExitCode"
    [void]$report.AppendLine("- ❌ FAIL - Test execution failed (exit code: $mermaidDiffExitCode)")
    [void]$report.AppendLine("``````")
    [void]$report.AppendLine($mermaidDiffOutput)
    [void]$report.AppendLine("``````")
    $failedTests += 8
    $totalTests += 8
}

[void]$report.AppendLine("")

# Summary
Write-Header "Regression Test Summary"

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
    [void]$report.AppendLine("This was the first run or baseline was reset. Baseline files have been created in:")
    [void]$report.AppendLine("``````")
    [void]$report.AppendLine($baselineRoot)
    [void]$report.AppendLine("``````")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("**Run the regression test again to perform actual regression testing.**")
    [void]$report.AppendLine("")
}

if ($failedTests -eq 0 -and -not $baselineCreated) {
    [void]$report.AppendLine("### ✅ All Tests Passed!")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("No regressions detected. All outputs match the baseline files exactly.")
    [void]$report.AppendLine("")
} elseif ($failedTests -gt 0) {
    [void]$report.AppendLine("### ⚠️ Regressions Detected!")
    [void]$report.AppendLine("")
    [void]$report.AppendLine("One or more tests failed. Review the differences above to identify regressions.")
    [void]$report.AppendLine("")
[void]$report.AppendLine("**All test artifacts** (export files, diffs, intermediate files) have been saved to:")
[void]$report.AppendLine("``````")
[void]$report.AppendLine($currentAuditFolder)
[void]$report.AppendLine("``````")
[void]$report.AppendLine("")
[void]$report.AppendLine("**Audit folder contains:**")
[void]$report.AppendLine("- ``FullCircle_Export/`` - All intermediate files from ComprehensiveTest (AST, SQLGlot I/O, etc.)")
[void]$report.AppendLine("- ``MmdDiffTest_Export/`` - All intermediate files from TestMmdDiff")
[void]$report.AppendLine("- ``DIFF_*.txt`` - Detailed diffs for failed comparisons")
[void]$report.AppendLine("- ``REGRESSION_TEST_REPORT.md`` - This report")
    [void]$report.AppendLine("")
}

[void]$report.AppendLine("---")
[void]$report.AppendLine("")
[void]$report.AppendLine("### Baseline Files Location")
[void]$report.AppendLine("")
[void]$report.AppendLine("``````")
[void]$report.AppendLine($baselineRoot)
[void]$report.AppendLine("``````")
[void]$report.AppendLine("")
[void]$report.AppendLine("### Input Files Used")
[void]$report.AppendLine("")
[void]$report.AppendLine("- **SQL:** ``$testSqlFile``")
[void]$report.AppendLine("- **Mermaid Before:** ``$testBeforeMmdFile``")
[void]$report.AppendLine("- **Mermaid After:** ``$testAfterMmdFile``")
[void]$report.AppendLine("")
[void]$report.AppendLine("### Baseline Input Files")
[void]$report.AppendLine("")
[void]$report.AppendLine("Baseline input files are stored in:")
[void]$report.AppendLine("``````")
[void]$report.AppendLine($baselineInputRoot)
[void]$report.AppendLine("``````")
[void]$report.AppendLine("")
[void]$report.AppendLine("### Baseline Mapping")
[void]$report.AppendLine("")
[void]$report.AppendLine("The following mapping shows which input files produce which baseline outputs:")
[void]$report.AppendLine("")
foreach ($outputFile in $baselineMapping.Keys | Sort-Object) {
    $inputs = $baselineMapping[$outputFile]
    [void]$report.AppendLine("- **$outputFile** ← $($inputs -join ', ')")
}
[void]$report.AppendLine("")
[void]$report.AppendLine("See ``baseline-mapping.json`` in the Baseline folder for machine-readable mapping.")
[void]$report.AppendLine("")

# Save report to audit folder only
$report.ToString() | Out-File $reportPath -Encoding UTF8

Write-Success "Report saved: $reportPath"
Write-Host ""

# Open report in Cursor
Write-Info "Opening report in Cursor..."
Start-Process "cursor" -ArgumentList "`"$reportPath`""

Write-Host ""
Write-Success "Regression test complete!"
Write-Info "All test artifacts saved to: $currentAuditFolder"

# Check if we should publish
$allTestsPassed = ($failedTests -eq 0 -and -not $baselineCreated)

if ($allTestsPassed -and $PublishOnSuccess) {
    Write-Header "All Tests Passed - Preparing NuGet Package"
    
    # Step 1: Increment version
    Write-Info "Reading current version from project file..."
    $projectFilePath = Join-Path $scriptRoot "src\SqlMermaidErdTools\SqlMermaidErdTools.csproj"
    [xml]$projectXml = Get-Content $projectFilePath
    $currentVersion = $projectXml.Project.PropertyGroup.Version
    
    Write-Info "Current version: $currentVersion"
    
    if ($NewVersion) {
        $targetVersion = $NewVersion
        Write-Info "Using override version: $targetVersion"
    } else {
        # Auto-increment patch version
        if ($currentVersion -match '^(\d+)\.(\d+)\.(\d+)$') {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            $patch = [int]$matches[3]
            $newPatch = $patch + 1
            $targetVersion = "$major.$minor.$newPatch"
            Write-Info "Auto-incremented to: $targetVersion"
        } else {
            Write-Failure "Could not parse version number: $currentVersion"
            exit 1
        }
    }
    
    # Update version in project file
    Write-Info "Updating version in project file..."
    $projectXml.Project.PropertyGroup.Version = $targetVersion
    
    # Update PackageReleaseNotes with timestamp
    $releaseDate = Get-Date -Format "yyyy-MM-dd"
    $releaseNotes = "Version $targetVersion released on $releaseDate. All regression tests passed."
    $projectXml.Project.PropertyGroup.PackageReleaseNotes = $releaseNotes
    
    $projectXml.Save($projectFilePath)
    Write-Success "Version updated to: $targetVersion"
    
    # Step 2: Rebuild solution with new version
    Write-Header "Rebuilding Solution"
    Write-Info "Building with version $targetVersion..."
    $rebuildSln = Start-Process -FilePath "dotnet" -ArgumentList "build","`"$scriptRoot\SqlMermaidErdTools.sln`"","-c","Release","--nologo" -WindowStyle Hidden -Wait -PassThru
    if ($rebuildSln.ExitCode -ne 0) {
        Write-Failure "Solution build failed!"
        exit 1
    }
    Write-Success "Solution built successfully"
    
    # Step 3: Build NuGet Package (using dotnet pack directly)
    Write-Header "Building NuGet Package"
    Write-Info "Creating NuGet package with dotnet pack..."
    
    # Create output directory
    $packageOutputPath = Join-Path $scriptRoot "nupkg"
    if (Test-Path $packageOutputPath) {
        Remove-Item $packageOutputPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $packageOutputPath -Force | Out-Null
    
    # Pack the project
    $packProj = Start-Process -FilePath "dotnet" -ArgumentList "pack","`"$mainProjectPath`"","-c","Release","-o","`"$packageOutputPath`"","--no-build","--nologo" -WindowStyle Hidden -Wait -PassThru
    if ($packProj.ExitCode -ne 0) {
        Write-Failure "NuGet package build failed!"
        exit 1
    }
    
    # Verify package was created
    $packageFiles = Get-ChildItem -Path $packageOutputPath -Filter "*.nupkg" | Where-Object { $_.Name -notlike "*.symbols.nupkg" }
    if ($packageFiles.Count -eq 0) {
        Write-Failure "No NuGet package file found!"
        exit 1
    }
    
    $packageFile = $packageFiles[0].FullName
    $packageSize = [math]::Round(($packageFiles[0].Length / 1MB), 2)
    Write-Success "NuGet package built successfully"
    Write-Info "Package: $($packageFiles[0].Name)"
    Write-Info "Size: $packageSize MB"
    
    # Step 4: Publish to NuGet.org (only if API key is provided)
    if ($NugetApiKey) {
        Write-Header "Publishing to NuGet.org"
        
        Write-Info "Publishing package to NuGet.org..."
        $pushPkg = Start-Process -FilePath "dotnet" -ArgumentList "nuget","push","`"$packageFile`"","--api-key",$NugetApiKey,"--source","https://api.nuget.org/v3/index.json","--skip-duplicate" -WindowStyle Hidden -Wait -PassThru
        if ($pushPkg.ExitCode -ne 0) {
            Write-Failure "NuGet package publish failed!"
            exit 1
        }
        Write-Success "Package published successfully!"
    } else {
        Write-Info "Skipping NuGet publish (no API key provided)"
        Write-Info "To publish, provide -NugetApiKey parameter or set NUGET_API_KEY_SQL2MMD environment variable"
    }
    
    if ($NugetApiKey) {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║                                                                ║" -ForegroundColor Green
        Write-Host "║           ✅ DEPLOYMENT SUCCESSFUL! ✅                          ║" -ForegroundColor Green
        Write-Host "║                                                                ║" -ForegroundColor Green
        Write-Host "║  Package: SqlMermaidErdTools v$($targetVersion.PadRight(34))║" -ForegroundColor Green
        Write-Host "║  Published to: NuGet.org                                       ║" -ForegroundColor Green
        Write-Host "║                                                                ║" -ForegroundColor Green
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        
        [void]$report.AppendLine("")
        [void]$report.AppendLine("---")
        [void]$report.AppendLine("")
        [void]$report.AppendLine("## 🚀 NuGet Package Deployment")
        [void]$report.AppendLine("")
        [void]$report.AppendLine("**Status:** ✅ Successfully deployed to NuGet.org")
        [void]$report.AppendLine("")
        [void]$report.AppendLine("- **Previous Version:** $currentVersion")
        [void]$report.AppendLine("- **New Version:** $targetVersion")
        [void]$report.AppendLine("- **Release Date:** $releaseDate")
        [void]$report.AppendLine("- **Package URL:** https://www.nuget.org/packages/SqlMermaidErdTools/$targetVersion")
        [void]$report.AppendLine("")
        [void]$report.AppendLine("Users can install with:")
        [void]$report.AppendLine("``````powershell")
        [void]$report.AppendLine("dotnet add package SqlMermaidErdTools --version $targetVersion")
        [void]$report.AppendLine("``````")
        [void]$report.AppendLine("")
    } else {
        Write-Host ""
        Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║                                                                ║" -ForegroundColor Yellow
        Write-Host "║           📦 PACKAGE BUILT SUCCESSFULLY! 📦                    ║" -ForegroundColor Yellow
        Write-Host "║                                                                ║" -ForegroundColor Yellow
        Write-Host "║  Package: SqlMermaidErdTools v$($targetVersion.PadRight(34))║" -ForegroundColor Yellow
        Write-Host "║  Status: Built but NOT published (no API key)                  ║" -ForegroundColor Yellow
        Write-Host "║                                                                ║" -ForegroundColor Yellow
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        
        [void]$report.AppendLine("")
        [void]$report.AppendLine("---")
        [void]$report.AppendLine("")
        [void]$report.AppendLine("## 📦 NuGet Package Built")
        [void]$report.AppendLine("")
        [void]$report.AppendLine("**Status:** ✅ Package built successfully (NOT published)")
        [void]$report.AppendLine("")
        [void]$report.AppendLine("- **Previous Version:** $currentVersion")
        [void]$report.AppendLine("- **New Version:** $targetVersion")
        [void]$report.AppendLine("- **Release Date:** $releaseDate")
        [void]$report.AppendLine("- **Package Location:** ``$packageFile``")
        [void]$report.AppendLine("")
        [void]$report.AppendLine("To publish manually:")
        [void]$report.AppendLine("``````powershell")
        [void]$report.AppendLine("dotnet nuget push `"$packageFile`" --api-key YOUR_KEY --source https://api.nuget.org/v3/index.json")
        [void]$report.AppendLine("``````")
        [void]$report.AppendLine("")
    }
    
    # Re-save report with deployment info
    $report.ToString() | Out-File $reportPath -Encoding UTF8
}

# Exit with appropriate code
exit $(if ($failedTests -eq 0 -and -not $baselineCreated) { 0 } else { 1 })
