#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive test for WorkObject JSON and HTML export functionality
    
.DESCRIPTION
    Tests Export-WorkObjectToJsonFile and Export-WorkObjectToHtmlFile functions
    Verifies JSON structure and HTML content with tabs and Monaco editor
    
.EXAMPLE
    .\Test-WorkObjectExport.ps1
#>

Import-Module GlobalFunctions -Force

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "   PowerShell WorkObject Export Test" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$testFolder = Join-Path $env:TEMP "PowerShell_WorkObject_Test"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonFile = Join-Path $testFolder "TestWorkObject_$timestamp.json"
$htmlFile = Join-Path $testFolder "TestWorkObject_$timestamp.html"

try {
    # Create output folder
    if (-not (Test-Path $testFolder)) {
        New-Item -ItemType Directory -Path $testFolder -Force | Out-Null
    }

    # ═══════════════════════════════════════════════════════════
    # STEP 1: Create and populate WorkObject
    # ═══════════════════════════════════════════════════════════
    Write-Host "STEP 1: Creating PowerShell WorkObject..." -ForegroundColor Yellow
    
    $workObject = [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        UserName = "$env:USERDOMAIN\$env:USERNAME"
        OperatingSystem = [System.Environment]::OSVersion.ToString()
        ProcessorCount = [System.Environment]::ProcessorCount
        IsServer = $env:COMPUTERNAME -match "-APP$|-DB$"
        TestTimestamp = Get-Date
        TestArray = @("Item1", "Item2", "Item3")
        TestBool = $true
        TestNumber = 42
        TestDouble = 3.14159
        ScriptArray = @()
    }
    
    Write-Host "  ✓ Created WorkObject with 10 properties" -ForegroundColor Green

    # Add script executions using Add-ScriptAndOutputToWorkObject
    $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject `
        -Name "Database Check" `
        -Script "SELECT * FROM SYSCAT.TABLES FETCH FIRST 5 ROWS ONLY" `
        -Output @"
TABSCHEMA  TABNAME    TYPE
SYSCAT     TABLES     T
SYSCAT     COLUMNS    T
"@

    $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject `
        -Name "Server Info" `
        -Script "Get-ComputerInfo | Select-Object CsName, OsName, OsVersion" `
        -Output "CsName: $env:COMPUTERNAME`nOsName: Win32NT`nOsVersion: 10.0.26100.0"

    # Add another execution to same script (should append)
    $workObject = Add-ScriptAndOutputToWorkObject -WorkObject $workObject `
        -Name "Database Check" `
        -Script "SELECT COUNT(*) FROM SYSCAT.TABLES" `
        -Output "COUNT(*)`n547"

    Write-Host "  ✓ Added 3 script executions (2 unique scripts)" -ForegroundColor Green
    Write-Host "  ✓ WorkObject populated successfully" -ForegroundColor Green
    Write-Host ""

    # ═══════════════════════════════════════════════════════════
    # STEP 2: Export to JSON
    # ═══════════════════════════════════════════════════════════
    Write-Host "STEP 2: Exporting to JSON..." -ForegroundColor Yellow
    
    Export-WorkObjectToJsonFile -WorkObject $workObject -FileName $jsonFile
    
    if (-not (Test-Path $jsonFile)) {
        throw "JSON file was not created!"
    }
    
    $jsonFileSize = (Get-Item $jsonFile).Length
    Write-Host "  ✓ JSON exported to: $jsonFile" -ForegroundColor Green
    Write-Host "  ✓ JSON file size: $jsonFileSize bytes" -ForegroundColor Green

    # ═══════════════════════════════════════════════════════════
    # STEP 3: Verify JSON Content
    # ═══════════════════════════════════════════════════════════
    Write-Host ""
    Write-Host "STEP 3: Verifying JSON content..." -ForegroundColor Yellow
    
    $jsonContent = Get-Content $jsonFile -Raw | ConvertFrom-Json
    
    # Verify properties
    if ($jsonContent.ComputerName -ne $env:COMPUTERNAME) { throw "ComputerName mismatch in JSON" }
    Write-Host "  ✓ ComputerName in JSON" -ForegroundColor Green
    
    if ([string]::IsNullOrEmpty($jsonContent.UserName)) { throw "UserName missing in JSON" }
    Write-Host "  ✓ UserName in JSON" -ForegroundColor Green
    
    if ($jsonContent.ProcessorCount -ne [System.Environment]::ProcessorCount) { throw "ProcessorCount mismatch" }
    Write-Host "  ✓ ProcessorCount in JSON" -ForegroundColor Green
    
    if ($jsonContent.TestBool -ne $true) { throw "TestBool mismatch" }
    Write-Host "  ✓ TestBool in JSON" -ForegroundColor Green
    
    if ($jsonContent.TestNumber -ne 42) { throw "TestNumber mismatch" }
    Write-Host "  ✓ TestNumber in JSON" -ForegroundColor Green
    
    if ($jsonContent.TestArray.Count -ne 3) { throw "TestArray incorrect" }
    Write-Host "  ✓ TestArray in JSON" -ForegroundColor Green
    
    # Verify ScriptArray
    if ($null -eq $jsonContent.ScriptArray) { throw "ScriptArray missing" }
    Write-Host "  ✓ ScriptArray exists" -ForegroundColor Green
    
    if ($jsonContent.ScriptArray.Count -ne 2) { throw "ScriptArray should have 2 entries, has $($jsonContent.ScriptArray.Count)" }
    Write-Host "  ✓ ScriptArray has 2 entries" -ForegroundColor Green
    
    if ([string]::IsNullOrEmpty($jsonContent.ScriptArray[0].Name)) { throw "First script missing Name" }
    Write-Host "  ✓ First script has Name" -ForegroundColor Green
    
    if ([string]::IsNullOrEmpty($jsonContent.ScriptArray[0].Script)) { throw "First script missing Script" }
    Write-Host "  ✓ First script has Script" -ForegroundColor Green
    
    if ([string]::IsNullOrEmpty($jsonContent.ScriptArray[0].Output)) { throw "First script missing Output" }
    Write-Host "  ✓ First script has Output" -ForegroundColor Green
    
    if ([string]::IsNullOrEmpty($jsonContent.ScriptArray[0].FirstTimestamp)) { throw "First script missing timestamps" }
    Write-Host "  ✓ First script has timestamps" -ForegroundColor Green
    
    Write-Host "  ✓ All JSON validations passed!" -ForegroundColor Green
    Write-Host ""

    # ═══════════════════════════════════════════════════════════
    # STEP 4: Export to HTML
    # ═══════════════════════════════════════════════════════════
    Write-Host "STEP 4: Exporting to HTML..." -ForegroundColor Yellow
    
    Export-WorkObjectToHtmlFile `
        -WorkObject $workObject `
        -FileName $htmlFile `
        -Title "WorkObject PowerShell Test Report" `
        -AddToDevToolsWebPath $false `
        -AutoOpen $false

    if (-not (Test-Path $htmlFile)) {
        throw "HTML file was not created!"
    }
    
    $htmlFileSize = (Get-Item $htmlFile).Length
    Write-Host "  ✓ HTML exported to: $htmlFile" -ForegroundColor Green
    Write-Host "  ✓ HTML file size: $htmlFileSize bytes" -ForegroundColor Green

    # ═══════════════════════════════════════════════════════════
    # STEP 5: Verify HTML Content
    # ═══════════════════════════════════════════════════════════
    Write-Host ""
    Write-Host "STEP 5: Verifying HTML content..." -ForegroundColor Yellow
    
    $htmlContent = Get-Content $htmlFile -Raw
    
    # Verify HTML structure
    if ($htmlContent -notmatch "<!DOCTYPE html>") { throw "HTML missing DOCTYPE" }
    Write-Host "  ✓ HTML has DOCTYPE" -ForegroundColor Green
    
    if ($htmlContent -notmatch "<title>WorkObject PowerShell Test Report</title>") { throw "HTML missing title" }
    Write-Host "  ✓ HTML has title" -ForegroundColor Green
    
    # Check if using shared template (has theme toggle) or built-in (has FK logo)
    if ($htmlContent -match "Toggle Theme") {
        Write-Host "  ✓ HTML using shared template (has theme toggle)" -ForegroundColor Green
    }
    elseif ($htmlContent -match "FKA_logo") {
        Write-Host "  ✓ HTML using built-in template (has FK logo)" -ForegroundColor Green
    }
    else {
        throw "HTML has neither theme toggle nor FK logo - template issue"
    }
    
    if ($htmlContent -notmatch "<h2>Properties</h2>") { throw "HTML missing Properties section" }
    Write-Host "  ✓ HTML has Properties section" -ForegroundColor Green
    
    if ($htmlContent -notmatch "class='tab-container'") { throw "HTML missing tab system" }
    Write-Host "  ✓ HTML has tab system" -ForegroundColor Green
    
    if ($htmlContent -notmatch "class='tab-headers'") { throw "HTML missing tab headers" }
    Write-Host "  ✓ HTML has tab headers" -ForegroundColor Green
    
    if ($htmlContent -notmatch "class='tab-button'") { throw "HTML missing tab buttons" }
    Write-Host "  ✓ HTML has tab buttons" -ForegroundColor Green
    
    if ($htmlContent -notmatch "monaco-editor-container") { throw "HTML missing Monaco editor" }
    Write-Host "  ✓ HTML has Monaco editor" -ForegroundColor Green
    
    if ($htmlContent -notmatch "function showTab") { throw "HTML missing showTab function" }
    Write-Host "  ✓ HTML has showTab function" -ForegroundColor Green
    
    # Verify properties are in HTML
    if ($htmlContent -notmatch $env:COMPUTERNAME) { throw "HTML missing ComputerName" }
    Write-Host "  ✓ HTML contains ComputerName" -ForegroundColor Green
    
    if ($htmlContent -notmatch [System.Environment]::ProcessorCount) { throw "HTML missing ProcessorCount" }
    Write-Host "  ✓ HTML contains ProcessorCount" -ForegroundColor Green
    
    # Verify scripts are in HTML (as tabs)
    if ($htmlContent -notmatch "Database Check") { throw "HTML missing Database Check" }
    Write-Host "  ✓ HTML contains Database Check" -ForegroundColor Green
    
    if ($htmlContent -notmatch "Server Info") { throw "HTML missing Server Info" }
    Write-Host "  ✓ HTML contains Server Info" -ForegroundColor Green
    
    if ($htmlContent -notmatch "SELECT") { throw "HTML missing SQL" }
    Write-Host "  ✓ HTML contains SQL" -ForegroundColor Green
    
    if ($htmlContent -notmatch "data-script-") { throw "HTML missing Monaco script tags" }
    Write-Host "  ✓ HTML contains Monaco script tags" -ForegroundColor Green
    
    Write-Host "  ✓ All HTML validations passed!" -ForegroundColor Green
    Write-Host ""

    # ═══════════════════════════════════════════════════════════
    # STEP 6: Summary
    # ═══════════════════════════════════════════════════════════
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "                  TEST RESULTS" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "✅ WorkObject Creation:        PASS" -ForegroundColor Green
    Write-Host "✅ Script Array Functions:     PASS" -ForegroundColor Green
    Write-Host "✅ JSON Export:                PASS" -ForegroundColor Green
    Write-Host "✅ JSON Validation:            PASS" -ForegroundColor Green
    Write-Host "✅ HTML Export:                PASS" -ForegroundColor Green
    Write-Host "✅ HTML Validation:            PASS" -ForegroundColor Green
    Write-Host "✅ Tab System:                 PASS" -ForegroundColor Green
    Write-Host "✅ Monaco Editor:              PASS" -ForegroundColor Green
    Write-Host ""
    Write-Host "📄 JSON Output: $jsonFile" -ForegroundColor White
    Write-Host "📄 HTML Output: $htmlFile" -ForegroundColor White
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "✅ ALL TESTS PASSED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    # Open HTML in browser
    Write-Host "Opening HTML report in browser..." -ForegroundColor Yellow
    Start-Process $htmlFile
    Write-Host "✓ Browser opened" -ForegroundColor Green
    Write-Host ""

    # Return success
    return 0
}
catch {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "❌ TEST FAILED" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Write-Host ""
    
    return 1
}
