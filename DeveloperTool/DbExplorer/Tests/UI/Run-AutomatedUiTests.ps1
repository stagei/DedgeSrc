param(
    [string]$ProfileName = "FKKTOTST",
    [string]$TestSchema = "INL",
    [switch]$BuildOnly,
    [switch]$Verbose
)

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "  DbExplorer - Automated UI Testing with FlaUI" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host ""

# Step 1: Kill any existing instances
Write-Host "🧹 Step 1: Cleaning up existing processes..." -ForegroundColor Cyan
taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
taskkill /F /IM DbExplorer.AutoTests.exe 2>$null | Out-Null
Start-Sleep -Seconds 1
Write-Host "   ✅ Cleanup complete" -ForegroundColor Green
Write-Host ""

# Step 2: Build main application
Write-Host "🔨 Step 2: Building main application..." -ForegroundColor Cyan
$buildVerbosity = if ($Verbose) { "normal" } else { "quiet" }

dotnet build DbExplorer.csproj --configuration Debug --verbosity $buildVerbosity

if ($LASTEXITCODE -ne 0) {
    Write-Host "   ❌ Main application build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "   ✅ Main application built successfully" -ForegroundColor Green
Write-Host ""

# Step 3: Build test project
Write-Host "🔨 Step 3: Building test project..." -ForegroundColor Cyan

dotnet build DbExplorer.AutoTests\DbExplorer.AutoTests.csproj --configuration Debug --verbosity $buildVerbosity

if ($LASTEXITCODE -ne 0) {
    Write-Host "   ❌ Test project build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "   ✅ Test project built successfully" -ForegroundColor Green
Write-Host ""

if ($BuildOnly) {
    Write-Host "✅ Build complete (build-only mode)" -ForegroundColor Green
    exit 0
}

# Step 4: Run automated tests
Write-Host "🧪 Step 4: Running automated UI tests..." -ForegroundColor Cyan
Write-Host "   Profile: $ProfileName" -ForegroundColor Gray
Write-Host "   Schema: $TestSchema" -ForegroundColor Gray
Write-Host ""

$testExe = ".\DbExplorer.AutoTests\bin\Debug\net10.0-windows\DbExplorer.AutoTests.exe"

if (-not (Test-Path $testExe)) {
    Write-Host "   ❌ Test executable not found: $testExe" -ForegroundColor Red
    exit 1
}

# Run the tests
& $testExe $ProfileName $TestSchema

$exitCode = $LASTEXITCODE

Write-Host ""

if ($exitCode -eq 0) {
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "✅ All automated UI tests passed!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
}
else {
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "❌ Automated UI tests failed!" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
}

Write-Host ""
Write-Host "📁 Test logs saved in: DbExplorer.AutoTests\bin\Debug\net10.0-windows\logs\" -ForegroundColor Cyan
Write-Host ""

exit $exitCode

