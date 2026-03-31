param(
    [Parameter(Mandatory = $false)]
    [string[]]$ComputerNameList = @("localhost"),
    
    [Parameter(Mandatory = $false)]
    [string]$OverrideDatabase,
    
    [Parameter(Mandatory = $false)]
    [switch]$SendEmail,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   DedgeCommon Environment Test Deployment Script" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Build and publish
if (-not $SkipBuild) {
    Write-Host "Building TestEnvironmentReport..." -ForegroundColor Yellow
    
    $buildResult = dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed!" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✓ Build successful`n" -ForegroundColor Green
}

$exePath = "bin\Release\net8.0\win-x64\publish\TestEnvironmentReport.exe"

if (-not (Test-Path $exePath)) {
    Write-Host "ERROR: Executable not found at $($exePath)" -ForegroundColor Red
    Write-Host "Run without -SkipBuild to build first" -ForegroundColor Yellow
    exit 1
}

# Create Reports folder
$reportsFolder = "Reports"
if (-not (Test-Path $reportsFolder)) {
    New-Item -ItemType Directory -Path $reportsFolder -Force | Out-Null
}

$successCount = 0
$failCount = 0

foreach ($computerName in $ComputerNameList) {
    Write-Host "───────────────────────────────────────────────────────────" -ForegroundColor Gray
    Write-Host "Processing: $($computerName.ToUpper())" -ForegroundColor Cyan
    Write-Host "───────────────────────────────────────────────────────────" -ForegroundColor Gray
    
    try {
        # Handle localhost specially
        if ($computerName -eq "localhost" -or $computerName -eq $env:COMPUTERNAME) {
            Write-Host "  Running locally..." -ForegroundColor Yellow
            
            $args = @()
            if ($OverrideDatabase) { $args += $OverrideDatabase }
            if ($SendEmail) { $args += "--email" }
            
            & $exePath $args
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Execution successful" -ForegroundColor Green
                $successCount++
            }
            else {
                Write-Host "  ✗ Execution failed (exit code: $($LASTEXITCODE))" -ForegroundColor Red
                $failCount++
            }
        }
        else {
            # Remote execution
            Write-Host "  Deploying to $($computerName)..." -ForegroundColor Yellow
            
            # Copy to server
            $destPath = "\\$($computerName)\c$\Temp\TestEnvironmentReport.exe"
            Copy-Item $exePath $destPath -Force -ErrorAction Stop
            Write-Host "  ✓ Deployed to C:\Temp\" -ForegroundColor Green
            
            # Execute remotely
            Write-Host "  Executing on $($computerName)..." -ForegroundColor Yellow
            
            $scriptArgs = ""
            if ($OverrideDatabase) { $scriptArgs += " $OverrideDatabase" }
            if ($SendEmail) { $scriptArgs += " --email" }
            
            $result = Invoke-Command -ComputerName $computerName -ScriptBlock {
                param($scriptArgs)
                Set-Location C:\Temp
                
                $argList = $scriptArgs.Trim().Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
                
                if ($argList.Count -gt 0) {
                    & .\TestEnvironmentReport.exe $argList
                }
                else {
                    & .\TestEnvironmentReport.exe
                }
                
                return $LASTEXITCODE
            } -ArgumentList $scriptArgs -ErrorAction Stop
            
            if ($result -eq 0) {
                Write-Host "  ✓ Execution successful" -ForegroundColor Green
                $successCount++
            }
            else {
                Write-Host "  ✗ Execution failed (exit code: $($result))" -ForegroundColor Red
                $failCount++
            }
            
            # Retrieve reports
            Write-Host "  Retrieving reports..." -ForegroundColor Yellow
            $reportFiles = Get-ChildItem "\\$($computerName)\c$\Temp\EnvironmentReport_*.txt" -ErrorAction SilentlyContinue
            
            if ($reportFiles) {
                foreach ($file in $reportFiles) {
                    $localPath = Join-Path $reportsFolder $file.Name
                    Copy-Item $file.FullName $localPath -Force
                    Write-Host "  ✓ Report saved to: $($localPath)" -ForegroundColor Green
                }
                
                # Also get JSON files
                $jsonFiles = Get-ChildItem "\\$($computerName)\c$\Temp\EnvironmentReport_*.json" -ErrorAction SilentlyContinue
                foreach ($file in $jsonFiles) {
                    $localPath = Join-Path $reportsFolder $file.Name
                    Copy-Item $file.FullName $localPath -Force
                    Write-Host "  ✓ JSON report saved to: $($localPath)" -ForegroundColor Green
                }
            }
            else {
                Write-Host "  ⚠️  No report files found" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "  ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
    
    Write-Host ""
}

# Summary
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   Deployment Summary" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Servers:     $($ComputerNameList.Count)" -ForegroundColor White
Write-Host "Successful:        $($successCount)" -ForegroundColor Green
Write-Host "Failed:            $($failCount)" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

if (Test-Path $reportsFolder) {
    $reportCount = (Get-ChildItem $reportsFolder -Filter "*.txt").Count
    if ($reportCount -gt 0) {
        Write-Host "Reports Location:  $((Get-Item $reportsFolder).FullName)" -ForegroundColor Cyan
        Write-Host "Report Files:      $($reportCount)" -ForegroundColor White
    }
}

Write-Host ""

if ($failCount -eq 0) {
    Write-Host "✅ All deployments completed successfully!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "⚠️  Some deployments failed. Check errors above." -ForegroundColor Yellow
    exit 1
}
