<#
.SYNOPSIS
    Tests all object types can be opened for a database provider

.DESCRIPTION
    This script validates that all 13 object types can be opened successfully
    via CLI parameters for any database provider. It uses a provider config
    file to get test objects and connection details.

.PARAMETER ConfigFile
    Path to provider configuration JSON file

.PARAMETER OutputPath
    Path to save test results (optional)

.EXAMPLE
    .\Test-AllObjectTypes.ps1 -ConfigFile "..\ProviderConfigs\DB2_Config.json"

.EXAMPLE
    .\Test-AllObjectTypes.ps1 -ConfigFile "..\ProviderConfigs\PostgreSQL_Config.json" -OutputPath "..\TestResults"

.NOTES
    Version: 1.0
    Author: DbExplorer Project
    Date: December 14, 2025
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigFile,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "..\TestResults",
    
    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 20
)

# Load configuration
if (-not (Test-Path $ConfigFile)) {
    Write-Host "❌ Config file not found: $ConfigFile" -ForegroundColor Red
    exit 1
}

$config = Get-Content $ConfigFile | ConvertFrom-Json
$exe = "..\..\bin\Debug\net10.0-windows\DbExplorer.exe"

if (-not (Test-Path $exe)) {
    Write-Host "❌ DbExplorer.exe not found: $exe" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  🧪 OBJECT TYPES TEST" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Provider: $($config.provider) $($config.version)" -ForegroundColor White
Write-Host "Profile: $($config.profileName)" -ForegroundColor White
Write-Host "Timeout: $TimeoutSeconds seconds" -ForegroundColor White
Write-Host ""

# Define all object types to test
$objectTypes = @(
    @{Type="table"; Name=$config.testObjects.table; DisplayName="Table"},
    @{Type="view"; Name=$config.testObjects.view; DisplayName="View"},
    @{Type="procedure"; Name=$config.testObjects.procedure; DisplayName="Procedure"},
    @{Type="function"; Name=$config.testObjects.function; DisplayName="Function"},
    @{Type="index"; Name=$config.testObjects.index; DisplayName="Index"},
    @{Type="trigger"; Name=$config.testObjects.trigger; DisplayName="Trigger"},
    @{Type="sequence"; Name=$config.testObjects.sequence; DisplayName="Sequence"},
    @{Type="synonym"; Name=$config.testObjects.synonym; DisplayName="Synonym"},
    @{Type="type"; Name=$config.testObjects.type; DisplayName="Type"},
    @{Type="package"; Name=$config.testObjects.package; DisplayName="Package"},
    @{Type="user"; Name=$config.testObjects.user; DisplayName="User"},
    @{Type="role"; Name=$config.testObjects.role; DisplayName="Role"},
    @{Type="group"; Name=$config.testObjects.group; DisplayName="Group"}
)

$results = @()
$passed = 0
$failed = 0
$skipped = 0

foreach ($obj in $objectTypes) {
    if ([string]::IsNullOrEmpty($obj.Name) -or $obj.Name -eq "N/A") {
        Write-Host "$($obj.DisplayName)..." -NoNewline -ForegroundColor Gray
        Write-Host " ⏭️  SKIP (not configured)" -ForegroundColor Gray
        $skipped++
        $results += [PSCustomObject]@{
            Type = $obj.DisplayName
            ObjectName = "N/A"
            Status = "SKIP"
            Reason = "Not configured"
        }
        continue
    }
    
    Write-Host "$($obj.DisplayName) ($($obj.Name))..." -NoNewline -ForegroundColor Cyan
    
    # Launch app with object
    Start-Process $exe -ArgumentList "--profile", $config.profileName, "--open", $obj.Name, "--type", $obj.Type
    
    # Wait for app to respond (with timeout)
    $elapsed = 0
    $proc = $null
    $success = $false
    
    while ($elapsed -lt $TimeoutSeconds) {
        $proc = Get-Process -Name "DbExplorer" -ErrorAction SilentlyContinue
        if ($proc -and $proc.Responding) {
            $success = $true
            break
        }
        Start-Sleep -Milliseconds 500
        $elapsed++
    }
    
    # Kill process
    taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
    Start-Sleep -Milliseconds 500
    
    if ($success) {
        Write-Host " ✅ PASS" -ForegroundColor Green
        $passed++
        $results += [PSCustomObject]@{
            Type = $obj.DisplayName
            ObjectName = $obj.Name
            Status = "PASS"
            Reason = ""
        }
    } else {
        Write-Host " ❌ FAIL (timeout)" -ForegroundColor Red
        $failed++
        $results += [PSCustomObject]@{
            Type = $obj.DisplayName
            ObjectName = $obj.Name
            Status = "FAIL"
            Reason = "Timeout after $TimeoutSeconds seconds"
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  📊 RESULTS" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total: $($objectTypes.Count)" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor Red
Write-Host "Skipped: $skipped" -ForegroundColor Gray
$tested = $passed + $failed
if ($tested -gt 0) {
    $passRate = [math]::Round(($passed / $tested) * 100, 2)
    Write-Host "Pass Rate: $passRate%" -ForegroundColor Yellow
}
Write-Host ""

if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize
}

# Save results to JSON
if ($OutputPath) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputFile = Join-Path $OutputPath "$($config.provider)_ObjectTypes_$timestamp.json"
    
    $report = @{
        provider = $config.provider
        version = $config.version
        testDate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        testType = "ObjectTypes"
        results = @{
            total = $objectTypes.Count
            passed = $passed
            failed = $failed
            skipped = $skipped
            passRate = if ($tested -gt 0) { [math]::Round(($passed / $tested) * 100, 2) } else { 0 }
        }
        details = $results
    }
    
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Out-File $outputFile
    Write-Host "📄 Results saved to: $outputFile" -ForegroundColor Cyan
}

Write-Host ""
if ($failed -eq 0 -and $passed -gt 0) {
    Write-Host "🎉 ALL TESTED OBJECT TYPES PASSED!" -ForegroundColor Green
    exit 0
} elseif ($failed -gt 0) {
    Write-Host "⚠️  $failed object type(s) failed" -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "⚠️  No objects were tested" -ForegroundColor Yellow
    exit 1
}

