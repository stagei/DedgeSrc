param (
    [string]$AuthorFilter = "",
    [string]$AuthorEmail  = "",
    [string]$Since        = "",
    [string]$TargetPath   = "C:\opt\src",
    [switch]$SkipClone,
    [switch]$Force
)

Import-Module GlobalFunctions -Force

$scriptName = 'Pipeline'

# Reverse lookup: map author-part from folder name back to pipeline params
$authorPartLookup = @{
    'GEIR'    = @{ Filter = 'FKGEISTA'; Email = 'geir.helge.starholm@Dedge.no' }
    'SVEIN'   = @{ Filter = 'FKSVEERI'; Email = 'svein.morten.erikstad@Dedge.no' }
    'MINA'    = @{ Filter = 'FKMISTA';  Email = 'mina.marie.starholm@Dedge.no' }
    'CELINE'  = @{ Filter = 'FKCELERI'; Email = 'celine.andreassen.erikstad@Dedge.no' }
    'all'     = @{ Filter = '';          Email = '' }
}

$smsReceiver = switch ($env:USERNAME) {
    "FKGEISTA" { "+4797188358" }
    "FKSVEERI" { "+4795762742" }
    "FKMISTA"  { "+4799348397" }
    default    { "+4797188358" }
}

# ── Determine run mode ──────────────────────────────────────────────────────
# If no explicit params given, auto-detect existing Projects_* folders and refresh all
$explicitRun = $PSBoundParameters.ContainsKey('AuthorFilter') -or
               $PSBoundParameters.ContainsKey('AuthorEmail') -or
               $PSBoundParameters.ContainsKey('Since')

if (-not $explicitRun) {
    $gitHistRoot = $PSScriptRoot
    $allProjectFolders = Get-ChildItem -Path $gitHistRoot -Directory -Filter 'Projects_*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Projects_([^_]+)_(\d{8})_(\d{8})$' }

    # Deduplicate: keep only the newest folder per author+since combination
    $seenKeys = @{}
    $existingFolders = @()
    foreach ($f in ($allProjectFolders | Sort-Object Name -Descending)) {
        $null = $f.Name -match '^Projects_([^_]+)_(\d{8})_(\d{8})$'
        $key = "$($Matches[1])_$($Matches[2])"
        if (-not $seenKeys.ContainsKey($key)) {
            $seenKeys[$key] = $true
            $existingFolders += $f
        }
    }

    if ($existingFolders.Count -eq 0) {
        Write-LogMessage "[$($scriptName)] No existing Projects_* folders found. Use explicit params to create a new dataset." -Level WARN
        exit 0
    }

    $overallStart = Get-Date
    $datasetCount = $existingFolders.Count
    Write-LogMessage "[$($scriptName)] === REFRESH ALL MODE === Found $($datasetCount) dataset(s) to refresh" -Level INFO

    # Clone/pull repos once before processing all datasets
    if (-not $SkipClone) {
        Write-LogMessage "[$($scriptName)] Step 0: Cloning/pulling Azure DevOps repos to $($TargetPath)..." -Level INFO
        try {
            & "$TargetPath\DedgePsh\DevTools\CodingTools\Azure-DevOpsCloneRepositories\Azure-DevOpsCloneRepositories.ps1" -CloneAll $true -TargetPath $TargetPath
            Write-LogMessage "[$($scriptName)] Step 0: Clone/pull complete" -Level INFO
        } catch {
            Write-LogMessage "[$($scriptName)] Step 0: Clone/pull failed: $($_.Exception.Message) - continuing anyway" -Level WARN
        }
    }

    $idx = 0
    foreach ($folder in $existingFolders) {
        $idx++
        $null = $folder.Name -match '^Projects_([^_]+)_(\d{8})_(\d{8})$'
        $authorPart = $Matches[1]
        $sinceRaw   = $Matches[2]
        $oldTo      = $Matches[3]

        $sinceFormatted = "$($sinceRaw.Substring(0,4))-$($sinceRaw.Substring(4,2))-$($sinceRaw.Substring(6,2))"

        if ($authorPartLookup.ContainsKey($authorPart)) {
            $resolvedFilter = $authorPartLookup[$authorPart].Filter
            $resolvedEmail  = $authorPartLookup[$authorPart].Email
        } else {
            Write-LogMessage "[$($scriptName)] Unknown author part '$($authorPart)' in $($folder.Name) - skipping" -Level WARN
            continue
        }

        $authorDisplay = if ([string]::IsNullOrWhiteSpace($resolvedFilter)) { '(all)' } else { $resolvedFilter }
        Write-LogMessage "[$($scriptName)] --- Refreshing $($idx)/$($datasetCount): $($folder.Name) [Author=$($authorDisplay), Since=$($sinceFormatted)] ---" -Level INFO

        & $PSCommandPath -AuthorFilter $resolvedFilter -AuthorEmail $resolvedEmail -Since $sinceFormatted -SkipClone
    }

    # Re-export presentation data for all datasets
    Write-LogMessage "[$($scriptName)] Final presentation export for all datasets..." -Level INFO
    & "$PSScriptRoot\Presentation\Step4-Export-PresentationData.ps1"

    $elapsed = (Get-Date) - $overallStart
    Write-LogMessage "[$($scriptName)] === REFRESH ALL COMPLETE === $($datasetCount) dataset(s) in $($elapsed.ToString('hh\:mm\:ss'))" -Level INFO

    try {
        Send-Sms -Receiver $smsReceiver -Message "Git History refresh complete ($($datasetCount) datasets). $($elapsed.ToString('hh\:mm\:ss')) elapsed." -ErrorAction SilentlyContinue
    } catch {}

    exit 0
}

# ── Explicit single-dataset run ──────────────────────────────────────────────
$startTime = Get-Date
Write-LogMessage "[$($scriptName)] === FULL PIPELINE START === Author=$($AuthorFilter) Since=$($Since)" -Level INFO

# Step 0: Clone/pull all Azure DevOps repos to ensure full coverage
if (-not $SkipClone) {
    Write-LogMessage "[$($scriptName)] Step 0: Cloning/pulling Azure DevOps repos to $($TargetPath)..." -Level INFO
    try {
        & "$TargetPath\DedgePsh\DevTools\CodingTools\Azure-DevOpsCloneRepositories\Azure-DevOpsCloneRepositories.ps1" -CloneAll $true -TargetPath $TargetPath
        Write-LogMessage "[$($scriptName)] Step 0: Clone/pull complete" -Level INFO
    } catch {
        Write-LogMessage "[$($scriptName)] Step 0: Clone/pull failed: $($_.Exception.Message) - continuing anyway" -Level WARN
    }
} else {
    Write-LogMessage "[$($scriptName)] Step 0: Skipped (SkipClone)" -Level INFO
}

# Step 1: Generate worklist
Write-LogMessage "[$($scriptName)] Step 1/4: Generating worklist..." -Level INFO
& "$PSScriptRoot\Step1-Get-ProjectWorkList.ps1" -AuthorFilter $AuthorFilter -Since $Since
if ($LASTEXITCODE -ne 0 -and -not (Test-Path "$PSScriptRoot\ProjectWorkList.txt")) {
    Write-LogMessage "[$($scriptName)] Worklist generation failed" -Level ERROR
    exit 1
}
Write-LogMessage "[$($scriptName)] Step 1/4: Worklist complete" -Level INFO

# Step 2: Export git history
Write-LogMessage "[$($scriptName)] Step 2/4: Exporting git history..." -Level INFO
$exportArgs = @{
    Since        = $Since
    AuthorFilter = $AuthorEmail
}
if ($Force) { $exportArgs['Force'] = $true }
& "$PSScriptRoot\Step2-Export-GitHistoryTree.ps1" @exportArgs
Write-LogMessage "[$($scriptName)] Step 2/4: Git history export complete" -Level INFO

# Compute the output folder name (mirrors Export-GitHistoryTree logic)
$authorPart = if ([string]::IsNullOrWhiteSpace($AuthorEmail)) { 'all' }
              else { ($AuthorEmail -split '[.@ ]')[0].ToUpper() }
$extractFolderName = "Projects_$($authorPart)_$($Since -replace '-','')_$((Get-Date).ToString('yyyyMMdd'))"
$extractFolderPath = Join-Path $PSScriptRoot $extractFolderName

# Step 3: Ollama analysis
Write-LogMessage "[$($scriptName)] Step 3/4: Running Ollama analysis on $($extractFolderName)..." -Level INFO
$analyzeArgs = @{ ExtractFolder = $extractFolderPath }
if ($Force) { $analyzeArgs['Force'] = $true }
& "$PSScriptRoot\Step3-Analyze-GitExtractWithOllama.ps1" @analyzeArgs
Write-LogMessage "[$($scriptName)] Step 3/4: Ollama analysis complete" -Level INFO

# Step 4: Export presentation data
Write-LogMessage "[$($scriptName)] Step 4/4: Exporting presentation data..." -Level INFO
& "$PSScriptRoot\Presentation\Step4-Export-PresentationData.ps1"
Write-LogMessage "[$($scriptName)] Step 4/4: Presentation data export complete" -Level INFO

$elapsed = (Get-Date) - $startTime
Write-LogMessage "[$($scriptName)] === FULL PIPELINE COMPLETE === (elapsed: $($elapsed.ToString('hh\:mm\:ss')))" -Level INFO

try {
    Send-Sms -Receiver $smsReceiver -Message "Git History pipeline complete ($($AuthorFilter) since $($Since)). $($elapsed.ToString('hh\:mm\:ss')) elapsed." -ErrorAction SilentlyContinue
    Write-LogMessage "[$($scriptName)] SMS notification sent" -Level INFO
} catch {
    Write-LogMessage "[$($scriptName)] SMS send failed: $($_.Exception.Message)" -Level WARN
}
