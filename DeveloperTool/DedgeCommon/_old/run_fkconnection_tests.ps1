# PowerShell script to run DedgeConnection tests after rewrite
# This script runs all available test programs to verify DedgeConnection functionality

param(
    [switch]$Verbose,
    [switch]$SkipUnitTests,
    [switch]$SkipIntegrationTests,
    [switch]$SkipCustomTests
)

$ErrorActionPreference = "Stop"

Write-Host "=== DedgeConnection Test Verification Script ===" -ForegroundColor Green
Write-Host "Started at: $(Get-Date)" -ForegroundColor Yellow
Write-Host ""

# Function to run a test and capture results
function Run-Test {
    param(
        [string]$TestName,
        [string]$Command,
        [string]$WorkingDirectory = "."
    )
    
    Write-Host "Running: $TestName" -ForegroundColor Cyan
    Write-Host "Command: $Command" -ForegroundColor Gray
    Write-Host "Working Directory: $WorkingDirectory" -ForegroundColor Gray
    
    try {
        $startTime = Get-Date
        $result = Invoke-Expression $Command
        $endTime = Get-Date
        $duration = $endTime - $startTime
        
        Write-Host "✓ $TestName completed successfully in $($duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Green
        
        if ($Verbose -and $result) {
            Write-Host "Output:" -ForegroundColor Gray
            Write-Host $result -ForegroundColor White
        }
        
        return $true
    }
    catch {
        Write-Host "✗ $TestName failed: $($_.Exception.Message)" -ForegroundColor Red
        if ($Verbose) {
            Write-Host "Error details:" -ForegroundColor Gray
            Write-Host $_.Exception.ToString() -ForegroundColor White
        }
        return $false
    }
    finally {
        Write-Host ""
    }
}

# Test results tracking
$testResults = @{
    Total = 0
    Passed = 0
    Failed = 0
    Tests = @()
}

# Function to record test result
function Record-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed
    )
    
    $testResults.Total++
    if ($Passed) {
        $testResults.Passed++
    } else {
        $testResults.Failed++
    }
    
    $testResults.Tests += @{
        Name = $TestName
        Passed = $Passed
        Timestamp = Get-Date
    }
}

# Check if we're in the right directory
if (-not (Test-Path "DedgeCommon.sln")) {
    Write-Host "Error: DedgeCommon.sln not found. Please run this script from the DedgeCommon project root directory." -ForegroundColor Red
    exit 1
}

Write-Host "Project structure verified. Starting tests..." -ForegroundColor Green
Write-Host ""

# Test 1: Unit Tests (if not skipped)
if (-not $SkipUnitTests) {
    Write-Host "=== Phase 1: Unit Tests ===" -ForegroundColor Yellow
    
    $unitTestPassed = Run-Test -TestName "FkDatabaseHandler Unit Tests" -Command "dotnet test DedgeCommonTest/DedgeCommonTest.csproj --verbosity normal --no-build" -WorkingDirectory "."
    Record-TestResult -TestName "Unit Tests" -Passed $unitTestPassed
    
    if (-not $unitTestPassed) {
        Write-Host "Unit tests failed. Attempting to build first..." -ForegroundColor Yellow
        $buildPassed = Run-Test -TestName "Build Project" -Command "dotnet build DedgeCommonTest/DedgeCommonTest.csproj" -WorkingDirectory "."
        if ($buildPassed) {
            $unitTestPassed = Run-Test -TestName "FkDatabaseHandler Unit Tests (Retry)" -Command "dotnet test DedgeCommonTest/DedgeCommonTest.csproj --verbosity normal" -WorkingDirectory "."
            Record-TestResult -TestName "Unit Tests (Retry)" -Passed $unitTestPassed
        }
    }
} else {
    Write-Host "Skipping unit tests as requested." -ForegroundColor Yellow
}

# Test 2: Integration Tests (if not skipped)
if (-not $SkipIntegrationTests) {
    Write-Host "=== Phase 2: Integration Tests ===" -ForegroundColor Yellow
    
    $integrationTestPassed = Run-Test -TestName "FkDatabaseHandler Integration Test" -Command "dotnet run --project DedgeCommonVerifyFkDatabaseHandler/VerifyFunctionality.csproj" -WorkingDirectory "."
    Record-TestResult -TestName "Integration Tests" -Passed $integrationTestPassed
} else {
    Write-Host "Skipping integration tests as requested." -ForegroundColor Yellow
}

# Test 3: Custom DedgeConnection Tests (if not skipped)
if (-not $SkipCustomTests) {
    Write-Host "=== Phase 3: Custom DedgeConnection Tests ===" -ForegroundColor Yellow
    
    # First, we need to create a test project for our custom test
    $testProjectPath = "DedgeConnectionTest"
    if (-not (Test-Path $testProjectPath)) {
        Write-Host "Creating test project for DedgeConnection tests..." -ForegroundColor Yellow
        
        # Create test project directory
        New-Item -ItemType Directory -Path $testProjectPath -Force | Out-Null
        
        # Create project file
        $projectContent = @"
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\DedgeCommon\DedgeCommon.csproj" />
  </ItemGroup>

</Project>
"@
        $projectContent | Out-File -FilePath "$testProjectPath/DedgeConnectionTest.csproj" -Encoding UTF8
        
        # Copy test program
        Copy-Item "DedgeConnectionTestProgram.cs" "$testProjectPath/Program.cs"
        
        Write-Host "Test project created successfully." -ForegroundColor Green
    }
    
    $customTestPassed = Run-Test -TestName "Custom DedgeConnection Tests" -Command "dotnet run --project $testProjectPath/DedgeConnectionTest.csproj" -WorkingDirectory "."
    Record-TestResult -TestName "Custom DedgeConnection Tests" -Passed $customTestPassed
} else {
    Write-Host "Skipping custom DedgeConnection tests as requested." -ForegroundColor Yellow
}

# Test 4: Simple Test Program
Write-Host "=== Phase 4: Simple Test Program ===" -ForegroundColor Yellow

$simpleTestPassed = Run-Test -TestName "Simple Test Program" -Command "dotnet run --project TestNoNameSpace/TestNoNameSpace.csproj" -WorkingDirectory "."
Record-TestResult -TestName "Simple Test Program" -Passed $simpleTestPassed

# Print final summary
Write-Host "=== Test Summary ===" -ForegroundColor Green
Write-Host "Total tests run: $($testResults.Total)" -ForegroundColor White
Write-Host "Passed: $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($testResults.Failed)" -ForegroundColor Red

if ($testResults.Total -gt 0) {
    $successRate = ($testResults.Passed * 100.0 / $testResults.Total)
    Write-Host "Success rate: $($successRate.ToString('F1'))%" -ForegroundColor $(if ($successRate -eq 100) { "Green" } elseif ($successRate -ge 80) { "Yellow" } else { "Red" })
}

Write-Host ""
Write-Host "Detailed Results:" -ForegroundColor Yellow
foreach ($test in $testResults.Tests) {
    $status = if ($test.Passed) { "✓" } else { "✗" }
    $color = if ($test.Passed) { "Green" } else { "Red" }
    Write-Host "  $status $($test.Name)" -ForegroundColor $color
}

Write-Host ""
Write-Host "Completed at: $(Get-Date)" -ForegroundColor Yellow

# Exit with appropriate code
if ($testResults.Failed -eq 0) {
    Write-Host "🎉 All tests passed! DedgeConnection rewrite is working correctly." -ForegroundColor Green
    exit 0
} else {
    Write-Host "⚠️  Some tests failed. Please review the issues above." -ForegroundColor Red
    exit 1
}

