Import-Module -Name Db2-Handler -Force

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Get-SystemInfoAsObject COMPREHENSIVE TEST" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$systemInfo = Get-SystemInfoAsObject

# Test counters
$passCount = 0
$failCount = 0
$tests = @()

function Test-Property {
    param(
        [string]$PropertyName,
        [object]$Value,
        [string]$ExpectedType,
        [scriptblock]$ValidationRule = $null,
        [string]$ValidationMessage = ""
    )

    $result = [PSCustomObject]@{
        Property = $PropertyName
        Value = $Value
        Type = $Value.GetType().Name
        ExpectedType = $ExpectedType
        Status = "PENDING"
        Message = ""
    }

    # Type check
    if ($Value.GetType().Name -ne $ExpectedType) {
        $result.Status = "FAIL"
        $result.Message = "Type mismatch: Expected $ExpectedType, got $($Value.GetType().Name)"
        return $result
    }

    # Custom validation
    if ($ValidationRule) {
        try {
            $validationResult = & $ValidationRule
            if ($validationResult) {
                $result.Status = "PASS"
                $result.Message = $ValidationMessage
            } else {
                $result.Status = "FAIL"
                $result.Message = "Validation failed: $ValidationMessage"
            }
        } catch {
            $result.Status = "FAIL"
            $result.Message = "Validation error: $_"
        }
    } else {
        $result.Status = "PASS"
        $result.Message = "Type check passed"
    }

    return $result
}

# Test String Properties
Write-Host "[STRING PROPERTIES]" -ForegroundColor Yellow
$stringProps = @('ComputerName', 'OSName', 'OSVersion', 'OSManufacturer', 'OSConfiguration',
                 'OSBuildType', 'SystemManufacturer', 'SystemModel', 'SystemType', 'Processor',
                 'BIOSVersion', 'PageFileLocation', 'Domain', 'LogonServer')

foreach ($prop in $stringProps) {
    $value = $systemInfo.$prop
    $test = Test-Property -PropertyName $prop -Value $value -ExpectedType "String" `
        -ValidationRule { -not [string]::IsNullOrWhiteSpace($value) } `
        -ValidationMessage "Non-empty string"

    $tests += $test

    if ($test.Status -eq "PASS") {
        Write-Host "  [PASS] $prop = '$value'" -ForegroundColor Green
        $passCount++
    } else {
        Write-Host "  [FAIL] $prop - $($test.Message)" -ForegroundColor Red
        $failCount++
    }
}

# Test Integer Properties
Write-Host "`n[INTEGER PROPERTIES]" -ForegroundColor Yellow
$intProps = @('TotalPhysicalMemoryMB', 'AvailablePhysicalMemoryMB', 'VirtualMemoryMaxSizeMB',
              'VirtualMemoryAvailableMB', 'VirtualMemoryInUseMB')

foreach ($prop in $intProps) {
    $value = $systemInfo.$prop
    $test = Test-Property -PropertyName $prop -Value $value -ExpectedType "Int32" `
        -ValidationRule { $value -gt 0 } `
        -ValidationMessage "Positive integer"

    $tests += $test

    if ($test.Status -eq "PASS") {
        Write-Host "  [PASS] $prop = $value MB" -ForegroundColor Green
        $passCount++
    } else {
        Write-Host "  [FAIL] $prop - $($test.Message)" -ForegroundColor Red
        $failCount++
    }
}

# Test Hotfixes Array
Write-Host "`n[HOTFIXES ARRAY]" -ForegroundColor Yellow
$hotfixes = $systemInfo.Hotfixes

Write-Host "  Type: $($hotfixes.GetType().Name)" -ForegroundColor Gray
Write-Host "  Count: $($hotfixes.Count)" -ForegroundColor Gray

if ($hotfixes.GetType().Name -eq "Object[]") {
    Write-Host "  [PASS] Hotfixes is array type" -ForegroundColor Green
    $passCount++

    $allKB = $true
    $invalidItems = @()

    for ($i = 0; $i -lt $hotfixes.Count; $i++) {
        $item = $hotfixes[$i]
        Write-Host "    [$i] = '$item' (Type: $($item.GetType().Name))" -ForegroundColor Gray

        # Each item should be a string starting with KB
        if ($item -notmatch '^KB\d+$') {
            $allKB = $false
            $invalidItems += "[$i] = '$item'"
        }
    }

    if ($allKB -and $hotfixes.Count -gt 0) {
        Write-Host "  [PASS] All hotfixes are valid KB numbers" -ForegroundColor Green
        $passCount++
    } else {
        Write-Host "  [FAIL] Some hotfixes are invalid:" -ForegroundColor Red
        $invalidItems | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        $failCount++
    }
} else {
    Write-Host "  [FAIL] Hotfixes is not an array" -ForegroundColor Red
    $failCount++
}

# Test NetworkAdapters Array
Write-Host "`n[NETWORK ADAPTERS ARRAY]" -ForegroundColor Yellow
$adapters = $systemInfo.NetworkAdapters

Write-Host "  Type: $($adapters.GetType().Name)" -ForegroundColor Gray
Write-Host "  Count: $($adapters.Count)" -ForegroundColor Gray

if ($adapters.GetType().Name -eq "Object[]") {
    Write-Host "  [PASS] NetworkAdapters is array type" -ForegroundColor Green
    $passCount++

    $allValid = $true
    $invalidItems = @()

    for ($i = 0; $i -lt $adapters.Count; $i++) {
        $item = $adapters[$i]
        Write-Host "    [$i] = '$item' (Type: $($item.GetType().Name))" -ForegroundColor Gray

        # Each item should be a string
        if ($item.GetType().Name -ne "String") {
            $allValid = $false
            $invalidItems += "[$i] has wrong type: $($item.GetType().Name)"
        }

        # Should not contain KB numbers (those are hotfixes)
        if ($item -match '^KB\d+') {
            $allValid = $false
            $invalidItems += "[$i] = '$item' (This is a hotfix, not a network adapter!)"
        }

        # Should not contain processor info
        if ($item -match 'Intel64 Family|GenuineIntel|~\d+ Mhz') {
            $allValid = $false
            $invalidItems += "[$i] = '$item' (This is processor info, not a network adapter!)"
        }

        # Should not be an IP address
        if ($item -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            $allValid = $false
            $invalidItems += "[$i] = '$item' (This is an IP address, not a network adapter!)"
        }
    }

    if ($allValid -and $adapters.Count -gt 0) {
        Write-Host "  [PASS] All network adapters are valid" -ForegroundColor Green
        $passCount++
    } else {
        Write-Host "  [FAIL] Some network adapters are invalid:" -ForegroundColor Red
        $invalidItems | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        $failCount++
    }
} else {
    Write-Host "  [FAIL] NetworkAdapters is not an array" -ForegroundColor Red
    $failCount++
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Tests: $($passCount + $failCount)" -ForegroundColor White
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red

if ($failCount -eq 0) {
    Write-Host "`nSTATUS: ALL TESTS PASSED" -ForegroundColor Green -BackgroundColor DarkGreen
} else {
    Write-Host "`nSTATUS: TESTS FAILED" -ForegroundColor Red -BackgroundColor DarkRed
}

Write-Host ""

# Return test results for further analysis
return $tests

