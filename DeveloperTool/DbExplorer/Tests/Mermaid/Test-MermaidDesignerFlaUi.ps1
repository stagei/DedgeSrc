param(
    [string]$ProfileName = "FKKTOTST",
    [string]$TestSchema = "INL",
    [switch]$SkipConnection
)

Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "  🎨 Mermaid Designer - FlaUI Automated Testing" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host ""

# Step 1: Clean up
Write-Host "🧹 Step 1: Cleaning up..." -ForegroundColor Cyan
taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
taskkill /F /IM DbExplorer.AutoTests.exe 2>$null | Out-Null
Start-Sleep -Seconds 1
Write-Host "   ✅ Cleanup complete" -ForegroundColor Green
Write-Host ""

# Step 2: Build main app
Write-Host "🔨 Step 2: Building main application..." -ForegroundColor Cyan
dotnet build DbExplorer.csproj --configuration Debug --verbosity quiet

if ($LASTEXITCODE -ne 0) {
    Write-Host "   ❌ Main application build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Main application built" -ForegroundColor Green
Write-Host ""

# Step 3: Build test project
Write-Host "🔨 Step 3: Building test project..." -ForegroundColor Cyan
dotnet build DbExplorer.AutoTests\DbExplorer.AutoTests.csproj --configuration Debug --verbosity quiet

if ($LASTEXITCODE -ne 0) {
    Write-Host "   ❌ Test project build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Test project built" -ForegroundColor Green
Write-Host ""

# Step 4: Run tests
Write-Host "🧪 Step 4: Running Mermaid Designer automated tests..." -ForegroundColor Cyan
Write-Host "   Profile: $ProfileName" -ForegroundColor Gray
Write-Host "   Schema: $TestSchema" -ForegroundColor Gray
Write-Host ""

$testExe = ".\DbExplorer.AutoTests\bin\Debug\net10.0-windows\DbExplorer.AutoTests.exe"

& $testExe $ProfileName $TestSchema

$exitCode = $LASTEXITCODE

Write-Host ""

if ($exitCode -eq 0) {
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "✅ All Mermaid Designer tests passed!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 Test Summary:" -ForegroundColor Cyan
    Write-Host "   ✅ Application startup" -ForegroundColor Green
    Write-Host "   ✅ Main window verification" -ForegroundColor Green
    Write-Host "   ✅ Recent connections panel" -ForegroundColor Green
    Write-Host "   ✅ Profile connection (FKKTOTST)" -ForegroundColor Green
    Write-Host "   ✅ Connection tab opened" -ForegroundColor Green
    Write-Host "   ✅ New Connection dialog" -ForegroundColor Green
    Write-Host "   ✅ Mermaid Designer - Open from menu" -ForegroundColor Green
    Write-Host "   ✅ Mermaid Designer - Window verification" -ForegroundColor Green
    Write-Host "   ✅ Mermaid Designer - Diagram generation" -ForegroundColor Green
    Write-Host "   ✅ Mermaid Designer - Preview" -ForegroundColor Green
    Write-Host "   ✅ Mermaid Designer - Export" -ForegroundColor Green
    Write-Host "   ✅ Mermaid Designer - DDL generation" -ForegroundColor Green
    Write-Host "   ✅ Mermaid Designer - Keyboard shortcuts" -ForegroundColor Green
    Write-Host "   ✅ Mermaid Designer - Close window" -ForegroundColor Green
}
else {
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "❌ Some tests failed!" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
}

Write-Host ""
Write-Host "📁 Logs:" -ForegroundColor Cyan
Write-Host "   Test logs: DbExplorer.AutoTests\bin\Debug\net10.0-windows\logs\" -ForegroundColor Gray
Write-Host "   App logs: bin\Debug\net10.0-windows\logs\" -ForegroundColor Gray
Write-Host ""

exit $exitCode

