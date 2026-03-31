#Requires -Version 7.0
<#
.SYNOPSIS
    Resolves uncertain CPY copybook files using Ollama AI analysis.
.DESCRIPTION
    Reads the MissingCopybooks-*.json output from Step20, checks which missing
    copybook base names exist in cpy_uncertain, and uses Ollama to select the
    best candidate by verifying field usage against referencing CBL programs.

    Single-candidate copybooks are copied directly. Multi-candidate copybooks
    are analyzed by Ollama using the Cpy-VersionSelection protocol.

    Fully dynamic: scans live on each run, adapts to new files added between runs,
    skips copybooks already present in the cpy folder.
.PARAMETER VcPath
    VCPATH root where sources live. Defaults to $env:VCPATH or the Step10 output folder.
.PARAMETER MissingCopybooksFolder
    Folder containing MissingCopybooks-*.json from Step20. Defaults to Get-ApplicationDataPath.
.PARAMETER OllamaModel
    Ollama model to use. Defaults to qwen2.5:7b.
.PARAMETER OllamaUrl
    Ollama API URL. Defaults to http://localhost:11434.
.PARAMETER CopyContextLines
    Number of lines around COPY statements to extract as context. Defaults to 20.
.PARAMETER DryRun
    Log what would happen without copying files.
.EXAMPLE
    .\Step25-Resolve-VcUncertainCpy.ps1
    .\Step25-Resolve-VcUncertainCpy.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\opt\data\VisualCobol\Step1-Copy-VcSourceFiles\Sources' }),
    [string]$MissingCopybooksFolder = '',
    [string]$OllamaModel = 'qwen2.5:7b',
    [string]$OllamaUrl = 'http://localhost:11434',
    [int]$CopyContextLines = 20,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force
Import-Module OllamaHandler -Force

# --- Resolve folder paths ---
$cpyFolder = Join-Path $VcPath 'cpy'
$cblFolder = Join-Path $VcPath 'cbl'
$cpyUncertainFolder = Join-Path $VcPath 'cpy_uncertain'
$projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$dataDir = Join-Path $projectRoot 'Data'
$protocolDir = Join-Path $PSScriptRoot '_helper\AiProtocols'
$logFile = Join-Path $dataDir 'cpy-uncertain-files-moved.json'

if (-not (Test-Path $cpyUncertainFolder)) {
    Write-LogMessage "cpy_uncertain folder not found: $($cpyUncertainFolder)" -Level WARN
    exit 0
}
if (-not (Test-Path $cpyFolder)) {
    Write-LogMessage "cpy folder not found: $($cpyFolder)" -Level ERROR
    exit 1
}

if ([string]::IsNullOrEmpty($MissingCopybooksFolder)) {
    $MissingCopybooksFolder = Get-ApplicationDataPath
}

New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

# --- Load Ollama protocol ---
$protocolFile = Join-Path $protocolDir 'Cpy-VersionSelection.mdc'
if (-not (Test-Path $protocolFile)) {
    Write-LogMessage "AI protocol not found: $($protocolFile)" -Level ERROR
    exit 1
}
$systemPrompt = Get-Content -LiteralPath $protocolFile -Raw -Encoding utf8

# --- Blank the log file (step cleanup: re-analyze everything) ---
Write-LogMessage 'Blanking cpy-uncertain-files-moved.json for fresh analysis' -Level INFO
'[]' | Out-File -FilePath $logFile -Encoding utf8 -Force

# --- Find the latest MissingCopybooks JSON from Step20 ---
$missingJsonFile = Get-ChildItem -Path $MissingCopybooksFolder -Filter 'MissingCopybooks-*.json' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $missingJsonFile) {
    Write-LogMessage "No MissingCopybooks-*.json found in $($MissingCopybooksFolder) — run Step20 first" -Level ERROR
    exit 1
}

Write-LogMessage "Using missing copybooks report: $($missingJsonFile.FullName)" -Level INFO
$missingReport = Get-Content -LiteralPath $missingJsonFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json

# --- Extract unique missing copybook names ---
$missingCopybookNames = @{}
foreach ($entry in $missingReport.AllMissing) {
    $copyName = $entry.CopyElement.ToUpperInvariant()
    if (-not $missingCopybookNames.ContainsKey($copyName)) {
        $missingCopybookNames[$copyName] = [System.Collections.ArrayList]::new()
    }
    [void]$missingCopybookNames[$copyName].Add($entry.Program)
}
Write-LogMessage "Unique missing copybooks from Step20: $($missingCopybookNames.Count)" -Level INFO

# --- Scan existing cpy folder ---
$existingCpy = @{}
Get-ChildItem -Path $cpyFolder -File -ErrorAction SilentlyContinue | ForEach-Object {
    $existingCpy[$_.BaseName.ToUpperInvariant()] = $true
    $existingCpy[$_.Name.ToUpperInvariant()] = $true
}
Write-LogMessage "Found $($existingCpy.Count) existing entries in cpy folder" -Level INFO

# --- Scan cpy_uncertain and group by base name ---
$uncertainFiles = @(Get-ChildItem -Path $cpyUncertainFolder -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -imatch '^\.(cpy|cpb|dcl|cpx)$' })

Write-LogMessage "Found $($uncertainFiles.Count) files in cpy_uncertain" -Level INFO

# Group candidates by base copybook name (strip date/version suffixes)
# Regex: match base name before optional _digits suffix
#   ^(.+?)(?:_\d+)?$  - same pattern as Step15
$cpyGroups = @{}
foreach ($file in $uncertainFiles) {
    $baseName = $file.BaseName
    if ($baseName -match '^(.+?)(?:_\d+)?$') {
        $groupKey = $Matches[1].ToUpperInvariant()
    } else {
        $groupKey = $baseName.ToUpperInvariant()
    }
    if (-not $cpyGroups.ContainsKey($groupKey)) {
        $cpyGroups[$groupKey] = [System.Collections.ArrayList]::new()
    }
    [void]$cpyGroups[$groupKey].Add($file)
}

# --- Filter: only copybooks that are missing AND have candidates in cpy_uncertain ---
$toProcess = [System.Collections.ArrayList]::new()
foreach ($copyName in $missingCopybookNames.Keys) {
    $lookupKey = $copyName -replace '\.[^.]+$', ''
    $lookupKeyUpper = $lookupKey.ToUpperInvariant()

    if ($existingCpy.ContainsKey($copyName) -or $existingCpy.ContainsKey($lookupKeyUpper)) { continue }

    if ($cpyGroups.ContainsKey($lookupKeyUpper)) {
        [void]$toProcess.Add(@{
            CopybookName    = $copyName
            BaseName        = $lookupKeyUpper
            ReferencedBy    = @($missingCopybookNames[$copyName])
            Candidates      = @($cpyGroups[$lookupKeyUpper])
        })
    } elseif ($cpyGroups.ContainsKey($copyName)) {
        [void]$toProcess.Add(@{
            CopybookName    = $copyName
            BaseName        = $copyName
            ReferencedBy    = @($missingCopybookNames[$copyName])
            Candidates      = @($cpyGroups[$copyName])
        })
    }
}

Write-LogMessage "$($toProcess.Count) missing copybooks have candidates in cpy_uncertain" -Level INFO

if ($toProcess.Count -eq 0) {
    Write-LogMessage 'No uncertain CPY files to resolve — step complete' -Level INFO
    exit 0
}

# --- Helper: find COPY context in CBL files ---
function Get-CopyContext {
    param(
        [string]$CblFolder,
        [string]$ProgramName,
        [string]$CopybookName,
        [int]$ContextLines = 20
    )

    $cblFile = Get-ChildItem -Path $CblFolder -Filter "$($ProgramName)*" -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $cblFile) { return $null }

    $lines = @(Get-Content -LiteralPath $cblFile.FullName -Encoding windows-1252 -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0) { return $null }

    $baseCopy = ($CopybookName -replace '\.[^.]+$', '')

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -imatch "COPY\s+[`"']?$([regex]::Escape($baseCopy))") {
            $start = [Math]::Max(0, $i - [int]($ContextLines / 2))
            $end = [Math]::Min($lines.Count - 1, $i + [int]($ContextLines / 2))
            return ($lines[$start..$end] -join "`n")
        }
    }
    return $null
}

# --- Helper: parse Ollama JSON response ---
function ConvertFrom-OllamaJson {
    param([string]$RawResponse)

    if ([string]::IsNullOrWhiteSpace($RawResponse)) { return $null }

    $cleaned = $RawResponse.Trim()
    $cleaned = $cleaned -replace '```json\s*', '' -replace '```\s*', ''
    $cleaned = $cleaned.Trim()

    if ($cleaned -match '(\{[\s\S]*?\})') {
        try {
            return $Matches[1] | ConvertFrom-Json -ErrorAction Stop
        } catch { }
    }

    try {
        return $cleaned | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }
}

# --- Process each missing copybook ---
$results = [System.Collections.ArrayList]::new()
$copiedCount = 0
$ollamaCount = 0
$singleCount = 0
$failedCount = 0

foreach ($item in $toProcess) {
    $copybookName = $item.CopybookName
    $baseName = $item.BaseName
    $referencedBy = $item.ReferencedBy
    $candidates = $item.Candidates

    # Determine target filename: use the missing copybook name as-is (it includes extension)
    $targetFilename = $copybookName
    if ($targetFilename -notmatch '\.\w+$') {
        $targetFilename = "$($targetFilename).CPY"
    }

    if ($candidates.Count -eq 1) {
        $sourceFile = $candidates[0]
        $destPath = Join-Path $cpyFolder $targetFilename

        if (-not $DryRun) {
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destPath -Force
        }
        $singleCount++
        $copiedCount++

        $entry = [ordered]@{
            copybookName   = $copybookName
            targetFilename = $targetFilename
            selectedFrom   = $sourceFile.Name
            candidateCount = 1
            confidence     = 'only-candidate'
            matchingFields = 0
            reasoning      = 'Single candidate — copied directly'
            referencedBy   = @($referencedBy | Select-Object -First 5)
            ollamaModel    = $null
            analyzedAt     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        }
        [void]$results.Add($entry)
        continue
    }

    # Multiple candidates — read content and gather referencing program context
    $candidateData = [System.Collections.ArrayList]::new()
    foreach ($c in $candidates) {
        $content = Get-Content -LiteralPath $c.FullName -Raw -Encoding windows-1252 -ErrorAction SilentlyContinue
        [void]$candidateData.Add(@{
            filename = $c.Name
            fileDate = $c.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss')
            content  = if ($content.Length -gt 8000) { $content.Substring(0, 8000) } else { $content }
        })
    }

    $refProgData = [System.Collections.ArrayList]::new()
    $uniqueRefs = @($referencedBy | Select-Object -Unique | Select-Object -First 3)
    foreach ($progName in $uniqueRefs) {
        $ctx = Get-CopyContext -CblFolder $cblFolder -ProgramName $progName -CopybookName $copybookName -ContextLines $CopyContextLines
        if ($ctx) {
            [void]$refProgData.Add(@{
                programName = $progName
                copyContext = $ctx
            })
        }
    }

    $inputPayload = @{
        copybookName        = $copybookName
        candidates          = @($candidateData)
        referencingPrograms = @($refProgData)
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-OllamaGenerate -Prompt $inputPayload -SystemPrompt $systemPrompt `
            -Model $OllamaModel -ApiUrl $OllamaUrl -Temperature 0.2 -MaxTokens 512

        $parsed = ConvertFrom-OllamaJson -RawResponse $response

        if (-not $parsed -or -not $parsed.selectedFile) {
            Write-LogMessage "  $($copybookName): Ollama returned invalid JSON — skipping" -Level WARN
            $failedCount++
            continue
        }

        $selectedCandidate = $candidates | Where-Object { $_.Name -eq $parsed.selectedFile } | Select-Object -First 1
        if (-not $selectedCandidate) {
            $selectedCandidate = $candidates | Where-Object { $_.Name -ieq $parsed.selectedFile } | Select-Object -First 1
        }
        if (-not $selectedCandidate) {
            Write-LogMessage "  $($copybookName): Ollama selected '$($parsed.selectedFile)' but file not found in candidates" -Level WARN
            $failedCount++
            continue
        }

        $destPath = Join-Path $cpyFolder $targetFilename
        if (-not $DryRun) {
            Copy-Item -LiteralPath $selectedCandidate.FullName -Destination $destPath -Force
        }
        $ollamaCount++
        $copiedCount++

        $entry = [ordered]@{
            copybookName   = $copybookName
            targetFilename = $targetFilename
            selectedFrom   = $parsed.selectedFile
            candidateCount = $candidates.Count
            confidence     = if ($parsed.confidence) { $parsed.confidence } else { 'unknown' }
            matchingFields = if ($parsed.matchingFields) { $parsed.matchingFields } else { 0 }
            reasoning      = if ($parsed.reasoning) { $parsed.reasoning } else { '' }
            referencedBy   = @($referencedBy | Select-Object -First 5)
            ollamaModel    = $OllamaModel
            analyzedAt     = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        }
        [void]$results.Add($entry)

    } catch {
        Write-LogMessage "  $($copybookName): Ollama call failed — $($_.Exception.Message)" -Level WARN
        $failedCount++
    }

    if (($copiedCount % 25) -eq 0 -and $copiedCount -gt 0) {
        Write-LogMessage "Progress: $($copiedCount)/$($toProcess.Count) processed ($($singleCount) single, $($ollamaCount) Ollama, $($failedCount) failed)" -Level INFO
        $results | ConvertTo-Json -Depth 5 | Out-File -FilePath $logFile -Encoding utf8 -Force
    }
}

# --- Save final log ---
$results | ConvertTo-Json -Depth 5 | Out-File -FilePath $logFile -Encoding utf8 -Force

# --- Summary ---
Write-LogMessage '=== Step25 Summary ===' -Level INFO
Write-LogMessage "  Missing copybooks with uncertain candidates: $($toProcess.Count)" -Level INFO
Write-LogMessage "  Single-candidate (direct copy):              $($singleCount)" -Level INFO
Write-LogMessage "  Multi-candidate (Ollama analyzed):           $($ollamaCount)" -Level INFO
Write-LogMessage "  Failed / skipped:                            $($failedCount)" -Level INFO
Write-LogMessage "  Total copied to cpy:                         $($copiedCount)" -Level INFO
Write-LogMessage "  Log file: $($logFile)" -Level INFO

if ($DryRun) {
    Write-LogMessage '  [DRY RUN] No files were actually copied' -Level WARN
}

exit 0
