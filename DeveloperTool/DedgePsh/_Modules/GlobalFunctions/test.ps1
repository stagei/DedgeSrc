Import-Module Infrastructure -Force
Import-Module GlobalFunctions -Force
Import-Module Export-Array

# Test Send-FkAlert
Send-FkAlert -Program "Test" -Code "9999" -Message "Test of GlobalFunctions $(Get-Date)"

# Test Get-DefaultDomain
Write-Host "`nTesting Get-DefaultDomain:" -ForegroundColor Yellow
$defaultDomain = Get-DefaultDomain
Write-Host "Default Domain: $defaultDomain"

# Test Get-ComputerInfoJsonFilename and related functions
Write-Host "`nTesting FkComputerInfo functions:" -ForegroundColor Yellow
$computerInfoPath = Get-ComputerInfoJsonFilename
Write-Host "Computer Info JSON path: $computerInfoPath"

$computers = Get-ComputerInfoJson
Write-Host "Retrieved $(($computers | Measure-Object).Count) computers from JSON"

# Test server types functions
Write-Host "`nTesting Server Types functions:" -ForegroundColor Yellow
$serverTypesPath = Get-ServerTypesJsonFilename
Write-Host "Server Types JSON path: $serverTypesPath"

$serverTypes = Get-ServerTypesJson
Write-Host "Retrieved $(($serverTypes | Measure-Object).Count) server types"

# Test port group functions
Write-Host "`nTesting Port Group functions:" -ForegroundColor Yellow
$portGroupPath = Get-PortGroupJsonFilename
Write-Host "Port Group JSON path: $portGroupPath"

$portGroups = Get-PortGroupJson
Write-Host "Retrieved $(($portGroups | Measure-Object).Count) port groups"

# Test server port groups mapping
Write-Host "`nTesting Server Port Groups Mapping:" -ForegroundColor Yellow
$mappingPath = Get-ServerPortGroupsMappingJsonFilename
Write-Host "Mapping JSON path: $mappingPath"

$mappings = Get-ServerPortGroupsMappingJson
Write-Host "Retrieved $(($mappings | Measure-Object).Count) port group mappings"

# Test path functions
Write-Host "`nTesting Path functions:" -ForegroundColor Yellow

$devToolsWebPath = Get-DevToolsWebPath
Write-Host "DevTools Web Path: $devToolsWebPath"

$devToolsWebUrl = Get-DevToolsWebPathUrl
Write-Host "DevTools Web URL: $devToolsWebUrl"

$commonPath = Get-CommonPath
Write-Host "Common Path: $commonPath"

$configPath = Get-ConfigFilesPath
Write-Host "Config Files Path: $configPath"

$configResourcesPath = Get-ConfigFilesResourcesPath
Write-Host "Config Resources Path: $configResourcesPath"

$softwarePath = Get-SoftwarePath
Write-Host "Software Path: $softwarePath"

$psDefaultAppsPath = Get-PowershellDefaultAppsPath
Write-Host "PowerShell Default Apps Path: $psDefaultAppsPath"

$winDefaultAppsPath = Get-WindowsDefaultAppsPath
Write-Host "Windows Default Apps Path: $winDefaultAppsPath"

$logFilesPath = Get-CommonLogFilesPath
Write-Host "Log Files Path: $logFilesPath"

$scriptLogPath = Get-ScriptLogPath
Write-Host "Script Log Path: $scriptLogPath"

$tempPath = Get-TempFkPath
Write-Host "Temp FK Path: $tempPath"

$wingetAppsPath = Get-WingetAppsPath
Write-Host "Winget Apps Path: $wingetAppsPath"

$windowsAppsPath = Get-WindowsAppsPath
Write-Host "Windows Apps Path: $windowsAppsPath"

Write-Host "`nConfig Files Content:" -ForegroundColor Yellow
$configFiles = @(
    "ComputerInfo.json",
    "PortGroup.json",
    "ServerTypes.json",
    "ServerPortGroupsMapping.json"
)

$configPath = Get-ConfigFilesPath
foreach ($file in $configFiles) {
    $filePath = Join-Path $configPath $file
    if (Test-Path $filePath) {
        $content = Get-Content $filePath | ConvertFrom-Json
        $count = 0
        if ($content -is [System.Array]) {
            $count = $content.Count
        } else {
            $count = 1
        }
        Write-Host "$file : $count rows"
    } else {
        Write-Host "$file : File not found" -ForegroundColor Red
    }
}

try {
    $innerException = New-Object System.Exception("Inner exception details")
    $exception = New-Object System.Exception("Test errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest error `n Test errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest errorTest error", $innerException)
$errorRecord = New-Object System.Management.Automation.ErrorRecord(
    $exception,
    "CobolHandlerError",
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $null
    )
    throw $errorRecord
}
catch {
    Write-LogMessage "Error testing, Error testing, Error testing, Error testing, Error testing, Error testing, Error testing, Error testing, Error testing, Error testing, Error testing, Error testing, Error testing, Error testing, Error testing, Error testing `n Error testing Error testing" -Level "ERROR" -Exception $_.Exception
}

# Chain conversion test script
# This script tests whether our string conversion functions handle chained conversions properly

# Simplified test script focusing only on string conversion functionality
Write-Host "Lo5ading GlobalFunctions module..." -ForegroundColor Yellow
Import-Module GlobalFunctions -Force -ErrorAction Stop5

# Define test cases
$testStrings = @(
    "this is a test string",
    "THIS_IS_ALL_CAPS",
    "already-kebab-case",5
    "already_snake_case",
    "AlreadyPascalCase",
    "alreadyCamelCase",
    "Mixed-Format_with spaces",
    "special!@#characters&^%in$string",
    "test123With456Numbers",
    "XML HTTP API Request"
)

# Define conversion methods
$conversionMethods = @(
    "ToSnakeCase",
    "ToKebabCase",
    "ToPascalCase",
    "ToCamelCase",
    "ToTitleCase",
    "ToCapitalize"
)

# Test all possible chains of two conversions
Write-Host "==== Testing Chained Conversions ====" -ForegroundColor Yellow
Write-Host "Testing all possible combinations of two conversions"
Write-Host "------------------------------------------"

$failCount = 0
$passCount = 0

foreach ($inputString in $testStrings) {
    Write-Host "`nInput: '$inputString'" -ForegroundColor Cyan

    # First, make sure each initial conversion works
    Write-Host "Direct conversions:" -ForegroundColor Gray
    $results = @{}
    foreach ($method in $conversionMethods) {
        try {
            # Use string extension method syntax instead of function call
            $result = $inputString.$method()
            $results[$method] = $result
            Write-Host "  $method -> '$result'" -ForegroundColor DarkGray
        } catch {
            Write-Host "  $method -> FAILED with error: $($_.Exception.Message)" -ForegroundColor Red
            $failCount++
        }
    }

    # Then test all possible chains
    Write-Host "Chained conversions:" -ForegroundColor Gray
    foreach ($firstMethod in $conversionMethods) {
        if ($results.ContainsKey($firstMethod)) {
            $firstResult = $results[$firstMethod]

            foreach ($secondMethod in $conversionMethods) {
                try {
                    # Use string extension method syntax for the second conversion
                    $chainResult = $firstResult.$secondMethod()
                    # Make sure the result is a non-empty string
                    if ([string]::IsNullOrWhiteSpace($chainResult)) {
                        Write-Host "  $firstMethod -> $secondMethod -> FAILED (Empty result)" -ForegroundColor Red
                        $failCount++
                    } else {
                        Write-Host "  $firstMethod -> $secondMethod -> '$chainResult'" -ForegroundColor Green
                        $passCount++
                    }
                } catch {
                    Write-Host "  $firstMethod -> $secondMethod -> FAILED with error: $($_.Exception.Message)" -ForegroundColor Red
                    $failCount++
                }
            }
        }
    }
}

Write-Host "`n==== Test Summary ====" -ForegroundColor Yellow
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red
if ($failCount -eq 0) {
    Write-Host "✅ ALL CHAINED CONVERSIONS PASSED!" -ForegroundColor Green
} else {
    Write-Host "❌ SOME CHAINED CONVERSIONS FAILED!" -ForegroundColor Red
}
Send-SMS -Receiver @("+4797188358", "+4797188358") -Message "Test of GlobalFunctions $(Get-Date)"

