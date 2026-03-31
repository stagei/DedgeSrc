#Requires -Version 7.0
<#
.SYNOPSIS
    Resolves uncertain CBL source files using Ollama AI analysis.
.DESCRIPTION
    Scans the cbl_uncertain folder for COBOL programs that match syscat_packages.json
    but are missing from the cbl folder. When multiple candidate versions exist, uses
    Ollama to analyze header comment dates and select the most recent/complete version.
    Single-candidate programs are copied directly without AI analysis.

    Fully dynamic: scans live on each run, adapts to new files added between runs,
    skips programs already present in the cbl folder.
.PARAMETER VcPath
    VCPATH root where sources live. Defaults to $env:VCPATH or the Step10 output folder.
.PARAMETER OllamaModel
    Ollama model to use. Defaults to qwen2.5:7b.
.PARAMETER OllamaUrl
    Ollama API URL. Defaults to http://localhost:11434.
.PARAMETER HeaderLines
    Number of lines to read from each file header. Defaults to 30.
.PARAMETER DryRun
    Log what would happen without copying files.
.EXAMPLE
    .\Step15-Resolve-VcUncertainCbl.ps1
    .\Step15-Resolve-VcUncertainCbl.ps1 -OllamaModel 'llama3:8b' -DryRun
#>
[CmdletBinding()]
param(
    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources' }),
    [string]$OllamaModel = 'qwen2.5:7b',
    [string]$OllamaUrl = 'http://localhost:11434',
    [int]$HeaderLines = 30,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force
Import-Module OllamaHandler -Force

# --- Resolve folder paths ---
$cblFolder = Join-Path $VcPath 'cbl'
$cblUncertainFolder = Join-Path $VcPath 'cbl_uncertain'
$staticDataDir = Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'StaticData'
$syscatPath = Join-Path $staticDataDir 'syscat_packages.json'
$projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$dataDir = Join-Path $projectRoot 'Data'
$protocolDir = Join-Path $PSScriptRoot '_helper\AiProtocols'
$logFile = Join-Path $dataDir 'cbl-uncertain-files-moved.json'

if (-not (Test-Path $cblUncertainFolder)) {
    Write-LogMessage "cbl_uncertain folder not found: $($cblUncertainFolder)" -Level WARN
    exit 0
}
if (-not (Test-Path $cblFolder)) {
    Write-LogMessage "cbl folder not found: $($cblFolder)" -Level ERROR
    exit 1
}
if (-not (Test-Path $syscatPath)) {
    Write-LogMessage "syscat_packages.json not found: $($syscatPath)" -Level ERROR
    exit 1
}

New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

# --- Load Ollama protocol ---
$protocolFile = Join-Path $protocolDir 'Cbl-VersionSelection.mdc'
if (-not (Test-Path $protocolFile)) {
    Write-LogMessage "AI protocol not found: $($protocolFile)" -Level ERROR
    exit 1
}
$systemPrompt = Get-Content -LiteralPath $protocolFile -Raw -Encoding utf8

# --- Blank the log file (step cleanup: re-analyze everything) ---
Write-LogMessage 'Blanking cbl-uncertain-files-moved.json for fresh analysis' -Level INFO
'[]' | Out-File -FilePath $logFile -Encoding utf8 -Force

# --- Load syscat_packages ---
Write-LogMessage "Loading syscat_packages.json from: $($syscatPath)" -Level INFO
$syscatData = Get-Content -LiteralPath $syscatPath -Raw -Encoding utf8 | ConvertFrom-Json
$packageMap = @{}
foreach ($pkg in $syscatData.packages) {
    $key = $pkg.qualifiedName.ToUpperInvariant()
    if (-not $packageMap.ContainsKey($key)) {
        $packageMap[$key] = $pkg.sourceFilename
    }
}
Write-LogMessage "Loaded $($packageMap.Count) packages from syscat" -Level INFO

# --- Scan existing cbl folder ---
$existingCbl = @{}
Get-ChildItem -Path $cblFolder -Filter '*.CBL' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $existingCbl[$_.Name.ToUpperInvariant()] = $true
}
Get-ChildItem -Path $cblFolder -Filter '*.cbl' -File -ErrorAction SilentlyContinue | ForEach-Object {
    $existingCbl[$_.Name.ToUpperInvariant()] = $true
}
Write-LogMessage "Found $($existingCbl.Count) existing CBL files in cbl folder" -Level INFO

# --- Scan cbl_uncertain and group by base program name ---
$uncertainFiles = @(Get-ChildItem -Path $cblUncertainFolder -Filter '*.cbl' -File -Recurse -ErrorAction SilentlyContinue)
$uncertainFiles += @(Get-ChildItem -Path $cblUncertainFolder -Filter '*.CBL' -File -Recurse -ErrorAction SilentlyContinue)
$uncertainFiles = $uncertainFiles | Sort-Object FullName -Unique

Write-LogMessage "Found $($uncertainFiles.Count) files in cbl_uncertain" -Level INFO

# Group candidates by deriving the base program name:
#   Match: <basename>_<digits>.cbl, <basename>_<date>.cbl, <basename>.cbl
# Regex explanation:
#   ^           - start of string
#   (.+?)       - group 1: base name (non-greedy, captures program name)
#   (?:_\d+)?   - optional non-capturing group: underscore followed by digits (date/version suffix)
#   \.cbl$      - literal .cbl extension at end
#   (?i)        - case-insensitive
$groups = @{}
foreach ($file in $uncertainFiles) {
    $baseName = $file.BaseName
    if ($baseName -match '^(.+?)(?:_\d+)?$') {
        $programKey = $Matches[1].ToUpperInvariant()
    } else {
        $programKey = $baseName.ToUpperInvariant()
    }
    if (-not $groups.ContainsKey($programKey)) {
        $groups[$programKey] = [System.Collections.ArrayList]::new()
    }
    [void]$groups[$programKey].Add($file)
}

Write-LogMessage "Grouped into $($groups.Count) unique program names" -Level INFO

# --- Filter: only programs that match syscat AND are not already in cbl ---
$toProcess = [System.Collections.ArrayList]::new()
foreach ($programKey in $groups.Keys) {
    if (-not $packageMap.ContainsKey($programKey)) { continue }

    $targetFilename = $packageMap[$programKey]
    if ($existingCbl.ContainsKey($targetFilename.ToUpperInvariant())) { continue }

    [void]$toProcess.Add(@{
        ProgramName    = $programKey
        TargetFilename = $targetFilename
        Candidates     = @($groups[$programKey])
    })
}

Write-LogMessage "$($toProcess.Count) programs need resolution (match syscat, missing from cbl)" -Level INFO

if ($toProcess.Count -eq 0) {
    Write-LogMessage 'No uncertain CBL files to resolve — step complete' -Level INFO
    exit 0
}

# --- Helper: extract dates from COBOL header comments ---
function Get-CobolCommentDates {
    param([string[]]$Lines)

    $dates = [System.Collections.ArrayList]::new()

    foreach ($line in $Lines) {
        # Regex: Extract dates in DD.MM.YY, DD.MM.YYYY, or YYYY.MM.DD format
        #   (\d{2})\.(\d{2})\.(\d{2,4})  - DD.MM.YY or DD.MM.YYYY
        #   (\d{4})\.(\d{2})\.(\d{2})    - YYYY.MM.DD
        $shortMatches = [regex]::Matches($line, '(\d{2})\.(\d{2})\.(\d{2,4})')
        foreach ($m in $shortMatches) {
            $part1 = [int]$m.Groups[1].Value
            $part2 = [int]$m.Groups[2].Value
            $part3 = $m.Groups[3].Value

            if ($part3.Length -eq 4 -and $part1 -gt 31) {
                # YYYY.MM.DD
                $year = [int]$part3; $month = $part2; $day = [int]$m.Groups[1].Value
                # Actually: part1=YYYY first two, need full 4-digit from group
                $year = [int]$part1 * 100 + [int]$part2
                continue
            }

            if ($part3.Length -eq 4) {
                $day = $part1; $month = $part2; $year = [int]$part3
            } elseif ($part3.Length -eq 2) {
                $day = $part1; $month = $part2
                $yr = [int]$part3
                $year = if ($yr -le 49) { 2000 + $yr } else { 1900 + $yr }
            } else {
                continue
            }

            if ($month -ge 1 -and $month -le 12 -and $day -ge 1 -and $day -le 31) {
                try {
                    $dt = [datetime]::new($year, $month, $day)
                    [void]$dates.Add($dt)
                } catch { }
            }
        }

        # YYYY.MM.DD pattern (4.2.2)
        $isoMatches = [regex]::Matches($line, '(\d{4})\.(\d{2})\.(\d{2})')
        foreach ($m in $isoMatches) {
            $year = [int]$m.Groups[1].Value
            $month = [int]$m.Groups[2].Value
            $day = [int]$m.Groups[3].Value
            if ($year -ge 1980 -and $year -le 2030 -and $month -ge 1 -and $month -le 12 -and $day -ge 1 -and $day -le 31) {
                try {
                    $dt = [datetime]::new($year, $month, $day)
                    [void]$dates.Add($dt)
                } catch { }
            }
        }
    }

    return @($dates | Sort-Object -Unique)
}

# --- Helper: extract date from filename ---
function Get-DateFromFilename {
    param([string]$Filename)

    # Regex: match 8-digit date suffix in filename
    #   _(\d{8})   - underscore followed by exactly 8 digits (YYYYMMDD)
    if ($Filename -match '_(\d{8})') {
        $ds = $Matches[1]
        try {
            return [datetime]::ParseExact($ds, 'yyyyMMdd', $null)
        } catch { return $null }
    }
    return $null
}

# --- Helper: parse Ollama JSON response ---
function ConvertFrom-OllamaJson {
    param([string]$RawResponse)

    if ([string]::IsNullOrWhiteSpace($RawResponse)) { return $null }

    $cleaned = $RawResponse.Trim()
    # Strip markdown code fences if present
    $cleaned = $cleaned -replace '```json\s*', '' -replace '```\s*', ''
    $cleaned = $cleaned.Trim()

    # Extract first JSON object
    if ($cleaned -match '(\{[\s\S]*?\})') {
        try {
            return $Matches[1] | ConvertFrom-Json -ErrorAction Stop
        } catch { }
    }

    # Fallback: try entire cleaned string
    try {
        return $cleaned | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

# --- Process each program ---
$results = [System.Collections.ArrayList]::new()
$copiedCount = 0
$ollamaCount = 0
$singleCount = 0
$failedCount = 0

foreach ($item in $toProcess) {
    $programName = $item.ProgramName
    $targetFilename = $item.TargetFilename
    $candidates = $item.Candidates

    if ($candidates.Count -eq 1) {
        # Single candidate — copy directly
        $sourceFile = $candidates[0]
        $destPath = Join-Path $cblFolder $targetFilename

        if (-not $DryRun) {
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destPath -Force
        }
        $singleCount++
        $copiedCount++

        $entry = [ordered]@{
            programName      = $programName
            sourceFilename   = $targetFilename
            selectedFrom     = $sourceFile.Name
            candidateCount   = 1
            confidence       = 'only-candidate'
            latestCommentDate = $null
            reasoning        = 'Single candidate — copied directly'
            ollamaModel      = $null
            analyzedAt       = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        }
        [void]$results.Add($entry)

        if (($copiedCount % 50) -eq 0) {
            Write-LogMessage "Progress: $($copiedCount)/$($toProcess.Count) processed ($($singleCount) single, $($ollamaCount) Ollama)" -Level INFO
        }
        continue
    }

    # Multiple candidates — gather data and call Ollama
    $candidateData = [System.Collections.ArrayList]::new()
    foreach ($c in $candidates) {
        $header = @(Get-Content -LiteralPath $c.FullName -TotalCount $HeaderLines -Encoding windows-1252 -ErrorAction SilentlyContinue)
        $dateFromName = Get-DateFromFilename -Filename $c.Name
        $dateFromNameStr = if ($dateFromName) { $dateFromName.ToString('yyyy-MM-dd') } else { $null }

        [void]$candidateData.Add(@{
            filename    = $c.Name
            fileDate    = $c.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            dateFromName = $dateFromNameStr
            headerLines = ($header -join "`n")
        })
    }

    $inputPayload = @{
        programName = $programName
        candidates  = @($candidateData)
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-OllamaGenerate -Prompt $inputPayload -SystemPrompt $systemPrompt `
            -Model $OllamaModel -ApiUrl $OllamaUrl -Temperature 0.2 -MaxTokens 512

        $parsed = ConvertFrom-OllamaJson -RawResponse $response

        if (-not $parsed -or -not $parsed.selectedFile) {
            Write-LogMessage "  $($programName): Ollama returned invalid JSON — skipping" -Level WARN
            $failedCount++
            continue
        }

        $selectedCandidate = $candidates | Where-Object { $_.Name -eq $parsed.selectedFile } | Select-Object -First 1
        if (-not $selectedCandidate) {
            $selectedCandidate = $candidates | Where-Object { $_.Name -ieq $parsed.selectedFile } | Select-Object -First 1
        }
        if (-not $selectedCandidate) {
            Write-LogMessage "  $($programName): Ollama selected '$($parsed.selectedFile)' but file not found in candidates" -Level WARN
            $failedCount++
            continue
        }

        $destPath = Join-Path $cblFolder $targetFilename
        if (-not $DryRun) {
            Copy-Item -LiteralPath $selectedCandidate.FullName -Destination $destPath -Force
        }
        $ollamaCount++
        $copiedCount++

        $entry = [ordered]@{
            programName       = $programName
            sourceFilename    = $targetFilename
            selectedFrom      = $parsed.selectedFile
            candidateCount    = $candidates.Count
            confidence        = if ($parsed.confidence) { $parsed.confidence } else { 'unknown' }
            latestCommentDate = if ($parsed.latestCommentDate) { $parsed.latestCommentDate } else { $null }
            reasoning         = if ($parsed.reasoning) { $parsed.reasoning } else { '' }
            ollamaModel       = $OllamaModel
            analyzedAt        = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        }
        [void]$results.Add($entry)

    } catch {
        Write-LogMessage "  $($programName): Ollama call failed — $($_.Exception.Message)" -Level WARN
        $failedCount++
    }

    if (($copiedCount % 25) -eq 0 -and $copiedCount -gt 0) {
        Write-LogMessage "Progress: $($copiedCount)/$($toProcess.Count) processed ($($singleCount) single, $($ollamaCount) Ollama, $($failedCount) failed)" -Level INFO
        # Periodic save
        $results | ConvertTo-Json -Depth 5 | Out-File -FilePath $logFile -Encoding utf8 -Force
    }
}

# --- Save final log ---
$results | ConvertTo-Json -Depth 5 | Out-File -FilePath $logFile -Encoding utf8 -Force

# --- Summary ---
Write-LogMessage '=== Step15 Summary ===' -Level INFO
Write-LogMessage "  Total programs needing resolution: $($toProcess.Count)" -Level INFO
Write-LogMessage "  Single-candidate (direct copy):    $($singleCount)" -Level INFO
Write-LogMessage "  Multi-candidate (Ollama analyzed): $($ollamaCount)" -Level INFO
Write-LogMessage "  Failed / skipped:                  $($failedCount)" -Level INFO
Write-LogMessage "  Total copied to cbl:               $($copiedCount)" -Level INFO
Write-LogMessage "  Log file: $($logFile)" -Level INFO

if ($DryRun) {
    Write-LogMessage '  [DRY RUN] No files were actually copied' -Level WARN
}

exit 0
