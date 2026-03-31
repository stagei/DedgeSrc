<#
.SYNOPSIS
    Test encoding conversion between UTF-8 and ANSI-1252 (Windows-1252)

.DESCRIPTION
    This script tests the ConvertTo-Ansi1252 function by:
    1. Reading a UTF-8 test file with Norwegian characters (ØÆÅ øæå)
    2. Converting to ANSI-1252 at byte level
    3. Simulating garbled UTF-8 (UTF-8 bytes misread as ANSI-1252)
    4. Verifying the function can recover garbled text
    5. Creating detailed byte-level analysis

.NOTES
    Test words: TRANSPORTØR, LEVERANDØR, SJÅFØRLOGG, ÆRLIG
    
    Norwegian characters:
    - Ø/ø: UTF-8 = C3 98/C3 B8, ANSI = D8/F8
    - Æ/æ: UTF-8 = C3 86/C3 A6, ANSI = C6/E6
    - Å/å: UTF-8 = C3 85/C3 A5, ANSI = C5/E5
    
    Output files:
    - Test-EncodingConversion-Output-ANSI.txt: ANSI-1252 encoded file
    - Test-EncodingConversion-Output-UTF8.txt: UTF-8 encoded file (after conversion)
    - Test-EncodingConversion-ByteDump.txt: Detailed byte analysis

.EXAMPLE
    .\Test-EncodingConversion.ps1
    
    Runs all encoding tests and generates output files
#>

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

Write-LogMessage "=== Encoding Conversion Test ===" -Level INFO

$scriptPath = $PSScriptRoot
$inputFile = Join-Path $scriptPath "Test-EncodingConversion-Data.txt"
$outputFileAnsi = Join-Path $scriptPath "Test-EncodingConversion-Output-ANSI.txt"
$outputFileUtf8 = Join-Path $scriptPath "Test-EncodingConversion-Output-UTF8.txt"
$outputFileByteDump = Join-Path $scriptPath "Test-EncodingConversion-ByteDump.txt"

# Verify input file exists
if (-not (Test-Path $inputFile)) {
    Write-LogMessage "Input file not found: $($inputFile)" -Level ERROR
    throw "Input file not found"
}

Write-LogMessage "Input file: $($inputFile)" -Level INFO
Write-LogMessage "Output ANSI file: $($outputFileAnsi)" -Level INFO
Write-LogMessage "Output UTF-8 file: $($outputFileUtf8)" -Level INFO
Write-LogMessage "Byte dump file: $($outputFileByteDump)" -Level INFO
Write-LogMessage "" -Level INFO

# ============================================================================
# TEST 1: Read UTF-8 file and examine bytes
# ============================================================================
Write-LogMessage "--- TEST 1: Read UTF-8 file and examine bytes ---" -Level INFO

$utf8Encoding = [System.Text.Encoding]::UTF8
$ansiEncoding = [System.Text.Encoding]::GetEncoding(1252)

# Read as UTF-8
$utf8Content = [System.IO.File]::ReadAllText($inputFile, $utf8Encoding)
Write-LogMessage "UTF-8 content length: $($utf8Content.Length) characters" -Level INFO

# Get UTF-8 bytes
$utf8Bytes = [System.IO.File]::ReadAllBytes($inputFile)
Write-LogMessage "File contains $($utf8Bytes.Length) bytes" -Level INFO

# ============================================================================
# TEST 2: Convert UTF-8 to ANSI-1252 at byte level
# ============================================================================
Write-LogMessage "" -Level INFO
Write-LogMessage "--- TEST 2: Convert UTF-8 → ANSI-1252 (byte level) ---" -Level INFO

# Method 1: Re-encode the string
$ansiBytes = $ansiEncoding.GetBytes($utf8Content)
$ansiContent = $ansiEncoding.GetString($ansiBytes)
Write-LogMessage "ANSI-1252 content length: $($ansiContent.Length) characters" -Level INFO

# Write ANSI file (using byte array directly)
[System.IO.File]::WriteAllBytes($outputFileAnsi, $ansiBytes)
Write-LogMessage "Wrote ANSI-1252 file: $($outputFileAnsi)" -Level INFO

# ============================================================================
# TEST 3: Test ConvertTo-Ansi1252 function
# ============================================================================
Write-LogMessage "" -Level INFO
Write-LogMessage "--- TEST 3: Test ConvertTo-Ansi1252 function ---" -Level INFO

$convertedContent = ConvertTo-Ansi1252 -ConvertString $utf8Content
Write-LogMessage "Converted content length: $($convertedContent.Length) characters" -Level INFO

# Write using function result
[System.IO.File]::WriteAllText($outputFileUtf8, $convertedContent, $utf8Encoding)
Write-LogMessage "Wrote converted UTF-8 file: $($outputFileUtf8)" -Level INFO

# ============================================================================
# TEST 4: Byte-level comparison
# ============================================================================
Write-LogMessage "" -Level INFO
Write-LogMessage "--- TEST 4: Byte-level analysis ---" -Level INFO

$byteDump = @()
$byteDump += "=" * 80
$byteDump += "BYTE-LEVEL COMPARISON OF NORWEGIAN CHARACTERS"
$byteDump += "=" * 80
$byteDump += ""

# Test specific words
$testWords = @("TRANSPORTØR", "LEVERANDØR", "SJÅFØRLOGG", "ÆRLIG", "transportør", "ærlig")

foreach ($word in $testWords) {
    $byteDump += "Word: $($word)"
    $byteDump += "-" * 40
    
    # UTF-8 bytes
    $utf8WordBytes = $utf8Encoding.GetBytes($word)
    $utf8Hex = ($utf8WordBytes | ForEach-Object { $_.ToString("X2") }) -join " "
    $byteDump += "UTF-8  bytes: $($utf8Hex)"
    
    # ANSI-1252 bytes
    $ansiWordBytes = $ansiEncoding.GetBytes($word)
    $ansiHex = ($ansiWordBytes | ForEach-Object { $_.ToString("X2") }) -join " "
    $byteDump += "ANSI   bytes: $($ansiHex)"
    
    # Character breakdown
    $byteDump += "Characters:"
    for ($i = 0; $i -lt $word.Length; $i++) {
        $char = $word[$i]
        $charUtf8Bytes = $utf8Encoding.GetBytes($char)
        $charAnsiBytes = $ansiEncoding.GetBytes($char)
        
        $charUtf8Hex = ($charUtf8Bytes | ForEach-Object { $_.ToString("X2") }) -join " "
        $charAnsiHex = ($charAnsiBytes | ForEach-Object { $_.ToString("X2") }) -join " "
        
        $byteDump += "  [$($i)] '$($char)' → UTF-8: $($charUtf8Hex), ANSI: $($charAnsiHex)"
    }
    $byteDump += ""
}

# Special Norwegian characters
$byteDump += "=" * 80
$byteDump += "NORWEGIAN CHARACTER MAPPINGS"
$byteDump += "=" * 80
$byteDump += ""

$norwegianChars = @(
    [PSCustomObject]@{ Char = [char]0x00D8; Description = 'Capital O with stroke (Ø)' }
    [PSCustomObject]@{ Char = [char]0x00C6; Description = 'Capital AE ligature (Æ)' }
    [PSCustomObject]@{ Char = [char]0x00C5; Description = 'Capital A with ring (Å)' }
    [PSCustomObject]@{ Char = [char]0x00F8; Description = 'Small o with stroke (ø)' }
    [PSCustomObject]@{ Char = [char]0x00E6; Description = 'Small ae ligature (æ)' }
    [PSCustomObject]@{ Char = [char]0x00E5; Description = 'Small a with ring (å)' }
)

foreach ($charObj in $norwegianChars) {
    $char = $charObj.Char.ToString()
    $description = $charObj.Description
    $charUtf8Bytes = $utf8Encoding.GetBytes($char)
    $charAnsiBytes = $ansiEncoding.GetBytes($char)
    
    $utf8Hex = ($charUtf8Bytes | ForEach-Object { $_.ToString("X2") }) -join " "
    $ansiHex = ($charAnsiBytes | ForEach-Object { $_.ToString("X2") }) -join " "
    
    $utf8Dec = ($charUtf8Bytes | ForEach-Object { $_.ToString().PadLeft(3) }) -join " "
    $ansiDec = ($charAnsiBytes | ForEach-Object { $_.ToString().PadLeft(3) }) -join " "
    
    $byteDump += "Character: '$($char)' ($($description))"
    $byteDump += "  UTF-8:      Hex: $($utf8Hex.PadRight(12)) Dec: $($utf8Dec)"
    $byteDump += "  ANSI-1252:  Hex: $($ansiHex.PadRight(12)) Dec: $($ansiDec)"
    $byteDump += ""
}

# Write byte dump
[System.IO.File]::WriteAllLines($outputFileByteDump, $byteDump, $utf8Encoding)
Write-LogMessage "Wrote byte dump file: $($outputFileByteDump)" -Level INFO

# ============================================================================
# TEST 5: Verify file contents
# ============================================================================
Write-LogMessage "" -Level INFO
Write-LogMessage "--- TEST 5: Verify output files ---" -Level INFO

# Read ANSI file back
$ansiReadBack = [System.IO.File]::ReadAllText($outputFileAnsi, $ansiEncoding)
Write-LogMessage "ANSI file read back length: $($ansiReadBack.Length) characters" -Level INFO

# Check for specific words in ANSI file
$wordsFound = 0
$wordsNotFound = @()
foreach ($word in $testWords) {
    if ($ansiReadBack.Contains($word)) {
        $wordsFound++
        Write-LogMessage "  ✓ Found: $($word)" -Level INFO
    }
    else {
        $wordsNotFound += $word
        Write-LogMessage "  ✗ Missing: $($word)" -Level WARN
    }
}

Write-LogMessage "" -Level INFO
Write-LogMessage "=== SUMMARY ===" -Level INFO
Write-LogMessage "Words found: $($wordsFound)/$($testWords.Count)" -Level INFO
if ($wordsNotFound.Count -gt 0) {
    Write-LogMessage "Words not found: $($wordsNotFound -join ', ')" -Level WARN
}
else {
    Write-LogMessage "All test words found successfully! ✓" -Level INFO
}

# ============================================================================
# TEST 6: Simulate garbled UTF-8 (UTF-8 bytes misread as ANSI-1252)
# ============================================================================
Write-LogMessage "" -Level INFO
Write-LogMessage "--- TEST 6: Simulate garbled UTF-8 scenario ---" -Level INFO

# This simulates what happens when UTF-8 file is read as ANSI-1252
$garbledContent = $ansiEncoding.GetString($utf8Bytes)
Write-LogMessage "Garbled content length: $($garbledContent.Length) characters" -Level INFO
Write-LogMessage "Garbled content sample: $($garbledContent.Substring(0, [Math]::Min(200, $garbledContent.Length)))" -Level INFO

# Check if test words appear garbled
Write-LogMessage "" -Level INFO
Write-LogMessage "Checking for garbled versions of test words:" -Level INFO
$garbledWords = @{
    'TRANSPORTØR' = 'TRANSPORTÃ˜R'
    'LEVERANDØR' = 'LEVERANDÃ˜R'
    'SJÅFØRLOGG' = 'SJÃ…FÃ˜RLOGG'
    'ÆRLIG' = 'Ã†RLIG'
}
foreach ($word in $garbledWords.Keys) {
    $garbledVersion = $garbledWords[$word]
    if ($garbledContent.Contains($garbledVersion)) {
        Write-LogMessage "  ✓ Found garbled '$($word)' as '$($garbledVersion)'" -Level INFO
    }
    else {
        # Try to find what it actually looks like
        $startIndex = $utf8Content.IndexOf($word)
        if ($startIndex -ge 0 -and $startIndex + $word.Length + 5 -le $garbledContent.Length) {
            $actualGarbled = $garbledContent.Substring($startIndex, [Math]::Min($word.Length + 5, $garbledContent.Length - $startIndex))
            Write-LogMessage "  ? Word '$($word)' appears as: '$($actualGarbled)'" -Level WARN
        }
    }
}

# Now use ConvertTo-Ansi1252 to fix it
Write-LogMessage "" -Level INFO
Write-LogMessage "Converting garbled content back to proper UTF-8..." -Level INFO
$fixedContent = ConvertTo-Ansi1252 -ConvertString $garbledContent
Write-LogMessage "Fixed content length: $($fixedContent.Length) characters" -Level INFO
Write-LogMessage "Fixed content sample: $($fixedContent.Substring(0, [Math]::Min(200, $fixedContent.Length)))" -Level INFO

# Verify the fix worked
$fixWorked = $true
foreach ($word in $testWords) {
    if (-not $fixedContent.Contains($word)) {
        Write-LogMessage "  ✗ Failed to fix: $($word)" -Level ERROR
        $fixWorked = $false
    }
}

if ($fixWorked) {
    Write-LogMessage "ConvertTo-Ansi1252 successfully recovered all garbled text! ✓" -Level INFO
}
else {
    Write-LogMessage "ConvertTo-Ansi1252 failed to recover some text ✗" -Level ERROR
}

Write-LogMessage "" -Level INFO
Write-LogMessage "=== TEST COMPLETE ===" -Level INFO
Write-LogMessage "Check the output files for results" -Level INFO

