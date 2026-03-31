<#
.SYNOPSIS
    Extracts project markdown data into JSON files for the HTML presentation.

.DESCRIPTION
    Parses GitHistory.md and PresentationSummary.md from Projects_* folders and
    outputs one JSON file per dataset plus a datasets.json manifest for the UI picker.

.PARAMETER GitHistRoot
    Root folder containing Projects_* subfolders.

.PARAMETER ExtractFolder
    Specific Projects_* folder to process. If empty, processes all Projects_* folders.

.PARAMETER OutputDir
    Directory for the output JSON files. Defaults to the Presentation folder.

.PARAMETER AutoDocJsonPath
    UNC path to the AutoDocJson web root containing *.json documentation files.
    When accessible, key source files and top changed files are matched against
    AutoDocJson entries to enrich project data with documentation links.

.PARAMETER AutoDocJsonBaseUrl
    Base URL for the AutoDocJson web application on the IIS server.
#>

param(
    [string]$GitHistRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$ExtractFolder = '',
    [string]$OutputDir = $PSScriptRoot,
    [string]$AutoDocJsonPath = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\AutoDocJson',
    [string]$AutoDocJsonBaseUrl = 'http://dedge-server/AutoDocJson'
)

Import-Module GlobalFunctions -Force

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
Write-LogMessage "[$($scriptName)] Starting data export" -Level INFO

# ── AutoDocJson lookup ────────────────────────────────────────────────────────
$script:AutoDocLookup = @{}
$script:AutoDocAvailable = $false
if (Test-Path -LiteralPath $AutoDocJsonPath -PathType Container -ErrorAction SilentlyContinue) {
    Write-LogMessage "[$($scriptName)] Building AutoDocJson lookup from $($AutoDocJsonPath)" -Level INFO
    $adFiles = @(Get-ChildItem -LiteralPath $AutoDocJsonPath -Filter '*.json' -File -Recurse -ErrorAction SilentlyContinue)
    # Prefer shallower paths when the same BaseName exists in multiple folders (e.g. root vs _json).
    $adFiles = $adFiles | Sort-Object @{ Expression = { $_.FullName.Length }; Ascending = $true }, FullName
    foreach ($f in $adFiles) {
        $key = $f.BaseName.ToLower()
        if (-not $script:AutoDocLookup.ContainsKey($key)) {
            $script:AutoDocLookup[$key] = $f.FullName
        }
    }
    $script:AutoDocAvailable = $script:AutoDocLookup.Count -gt 0
    Write-LogMessage "[$($scriptName)] AutoDocJson: $($script:AutoDocLookup.Count) entries indexed" -Level INFO
} else {
    Write-LogMessage "[$($scriptName)] AutoDocJson path not accessible: $($AutoDocJsonPath) -- skipping enrichment" -Level WARN
}

function Get-AutoDocLinks {
    param(
        [array]$KeySourceFiles,
        [array]$TopChangedFiles
    )

    if (-not $script:AutoDocAvailable) { return @() }

    $seen = @{}
    $links = [System.Collections.Generic.List[object]]::new()

    $candidates = @()
    foreach ($ksf in $KeySourceFiles) {
        $fname = [System.IO.Path]::GetFileName($ksf.file).Trim('`', ' ')
        if ($fname -and -not $seen.ContainsKey($fname.ToLower())) {
            $candidates += $fname
            $seen[$fname.ToLower()] = $true
        }
    }
    foreach ($tcf in $TopChangedFiles) {
        $fname = [System.IO.Path]::GetFileName($tcf.file).Trim('`', ' ')
        if ($fname -and -not $seen.ContainsKey($fname.ToLower())) {
            $candidates += $fname
            $seen[$fname.ToLower()] = $true
        }
    }

    foreach ($fname in $candidates) {
        $lookupKey = $fname.ToLower()
        if (-not $script:AutoDocLookup.ContainsKey($lookupKey)) { continue }

        $adJsonPath = $script:AutoDocLookup[$lookupKey]
        $adJsonName = [System.IO.Path]::GetFileName($adJsonPath)

        $link = @{
            fileName = $fname
            webUrl   = "$($AutoDocJsonBaseUrl)/Doc/?file=$($adJsonName)"
            uncPath  = $adJsonPath
            type     = ''
            description    = ''
            system         = ''
            sqlTables      = @()
            calledSubprograms = @()
            hasDiagrams    = $false
        }

        try {
            $adContent = Get-Content -LiteralPath $adJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($adContent.type) { $link.type = $adContent.type }
            if ($adContent.description) { $link.description = $adContent.description }
            if ($adContent.metadata -and $adContent.metadata.system) { $link.system = $adContent.metadata.system }
            if ($adContent.sqlTables -and $adContent.sqlTables.Count -gt 0) {
                $link.sqlTables = @($adContent.sqlTables | ForEach-Object {
                    @{ table = $_.table; operation = $_.operation; description = $_.description }
                })
            }
            if ($adContent.calledSubprograms -and $adContent.calledSubprograms.Count -gt 0) {
                $link.calledSubprograms = @($adContent.calledSubprograms | ForEach-Object {
                    @{ module = $_.module; description = $_.description }
                })
            }
            if ($adContent.diagrams) {
                $link.hasDiagrams = (
                    (-not [string]::IsNullOrWhiteSpace($adContent.diagrams.flowMmd)) -or
                    (-not [string]::IsNullOrWhiteSpace($adContent.diagrams.sequenceMmd))
                )
            }
        }
        catch {
            Write-LogMessage "[$($scriptName)] Failed to read AutoDocJson for $($fname): $($_.Exception.Message)" -Level DEBUG
        }

        $links.Add($link)
    }

    return @($links)
}

$teamLookup = @{
    'geir.helge.starholm'        = 'Geir Helge Starholm'
    'geir helge starholm'        = 'Geir Helge Starholm'
    'svein.morten.erikstad'      = 'Svein Morten Erikstad'
    'svein morten erikstad'      = 'Svein Morten Erikstad'
    'mina.marie.starholm'        = 'Mina Marie Starholm'
    'mina marie starholm'        = 'Mina Marie Starholm'
    'celine.andreassen.erikstad' = 'Celine Andreassen Erikstad'
    'celine andreassen erikstad' = 'Celine Andreassen Erikstad'
}

function Resolve-AuthorName {
    param([string]$RawAuthor)
    $key = $RawAuthor.Trim().ToLower()
    if ($teamLookup.ContainsKey($key)) { return $teamLookup[$key] }
    return (Get-Culture).TextInfo.ToTitleCase($key.Replace('.', ' '))
}

function Hide-Credentials {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    # Regex: mask values after common credential keys in connection strings and config
    # Matches patterns like PWD=secret; Password=secret; UID=user; User Id=user
    $masked = $Text -replace '(?i)(PWD|Password|Pwd|password)\s*=\s*[^;}\s"'']+', '$1=***'
    $masked = $masked -replace '(?i)(UID|User\s*Id|Username|username|User)\s*=\s*[^;}\s"'']+', '$1=***'
    $masked = $masked -replace '(?i)(Secret|ApiKey|Token|Bearer)\s*[:=]\s*\S+', '$1=***'
    return $masked
}

function ConvertTo-ProjectId {
    param([string]$Name)
    return ($Name.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
}

function Parse-GitHistory {
    param([string]$Content)

    $result = @{
        sourcePath = ''; repoRoot = ''; remoteUrl = ''; subPath = $null
        stats = @{ commits = 0; firstEverDate = ''; firstDate = ''; lastDate = ''; filesChanged = 0; insertions = 0; deletions = 0 }
        topFiles = @(); commits = @()
    }

    if ($Content -match 'Source path:\s*`([^`]+)`') { $result.sourcePath = $Matches[1] }
    if ($Content -match 'Repository root:\s*`([^`]+)`') { $result.repoRoot = $Matches[1] }
    if ($Content -match 'Remote URL:\s*`([^`]+)`') { $result.remoteUrl = $Matches[1] }
    if ($Content -match 'Repository subpath filter:\s*`([^`]+)`') { $result.subPath = $Matches[1] }
    if ($Content -match 'Commits:\s*(\d+)') { $result.stats.commits = [int]$Matches[1] }
    if ($Content -match 'First ever commit:\s*(\S+)') { $result.stats.firstEverDate = $Matches[1] }
    if ($Content -match 'First commit date in range:\s*(\S+)') { $result.stats.firstDate = $Matches[1] }
    if ($Content -match 'Last commit date in range:\s*(\S+)') { $result.stats.lastDate = $Matches[1] }
    if ($Content -match 'Aggregated files changed:\s*(\d+)') { $result.stats.filesChanged = [int]$Matches[1] }
    if ($Content -match 'Aggregated insertions:\s*(\d+)') { $result.stats.insertions = [int]$Matches[1] }
    if ($Content -match 'Aggregated deletions:\s*(\d+)') { $result.stats.deletions = [int]$Matches[1] }
    if ($Content -match 'Source file count:\s*(\d+)') { $result.stats.sourceFileCount = [int]$Matches[1] }
    if ($Content -match 'Total code lines:\s*(\d+)') { $result.stats.totalCodeLines = [int]$Matches[1] }

    $topFilesSection = $false
    $commitSection = $false

    foreach ($line in ($Content -split "`n")) {
        $line = $line.Trim()
        if ($line -match '^## Top Changed Files') { $topFilesSection = $true; $commitSection = $false; continue }
        if ($line -match '^## Commit List') { $commitSection = $true; $topFilesSection = $false; continue }
        if ($line -match '^## ' -and $line -notmatch '^## (Top Changed|Commit)') { $topFilesSection = $false; $commitSection = $false }

        if ($topFilesSection -and $line -match '^\|\s*`([^`]+)`\s*\|\s*(\d+)\s*\|') {
            $result.topFiles += @{ file = $Matches[1]; count = [int]$Matches[2] }
        }
        if ($commitSection -and $line -match '^\|\s*(\d{4}-\d{2}-\d{2})\s*\|\s*`([^`]+)`\s*\|\s*([^|]+)\|\s*(.+)\s*\|$') {
            $result.commits += @{
                date = $Matches[1]; hash = $Matches[2]
                author = $Matches[3].Trim(); message = $Matches[4].Trim().Replace('\|', '|')
            }
        }
    }
    return $result
}

function Parse-PresentationSummary {
    param([string]$Content)

    $result = @{
        businessPurpose = ''; tags = @(); executables = @(); periodSummary = ''
        parameters = @(); inputOutput = @()
        dbTechnology = ''; dbConnection = ''; dbTables = ''
    }

    $cleaned = $Content -replace '<think>[\s\S]*?</think>', ''
    $cleaned = $cleaned -replace '</think>', ''
    $cleaned = $cleaned -replace '<think>', ''

    $sections = @{}
    $currentSection = ''
    foreach ($line in ($cleaned -split "`n")) {
        if ($line -match '^##\s+(.+)') {
            $currentSection = $Matches[1].Trim()
            $sections[$currentSection] = [System.Collections.Generic.List[string]]::new()
            continue
        }
        if ($currentSection -and $sections.ContainsKey($currentSection)) {
            $sections[$currentSection].Add($line)
        }
    }

    if ($sections.ContainsKey('Business Purpose')) {
        $result.businessPurpose = (($sections['Business Purpose'] | Where-Object { $_.Trim() -ne '' }) -join ' ').Trim()
    }
    if ($sections.ContainsKey('Tags')) {
        $tagLine = ($sections['Tags'] | Where-Object { $_.Trim() -ne '' -and $_.Trim() -notmatch '^\(' }) | Select-Object -First 1
        if ($tagLine) {
            $normalized = $tagLine -replace '#', ''
            # Split on comma, space, or mixed separators
            $result.tags = @($normalized -split '[,\s]+' |
                ForEach-Object { $_.Trim().ToLower() } |
                Where-Object { $_ -ne '' -and $_ -ne '-' })
        }
    }
    $execKey = if ($sections.ContainsKey('Key Source Files')) { 'Key Source Files' } else { 'Executables' }
    if ($sections.ContainsKey($execKey)) {
        foreach ($line in $sections[$execKey]) {
            if ($line -match '^\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|$') {
                $fname = $Matches[1].Trim()
                $fdesc = $Matches[2].Trim()
                if ($fname -ne 'File' -and $fname -ne '---') {
                    $result.executables += @{ file = $fname; description = $fdesc }
                }
            }
        }
    }
    if ($sections.ContainsKey('Period Summary')) {
        $result.periodSummary = (($sections['Period Summary'] | Where-Object { $_.Trim() -ne '' }) -join ' ').Trim()
    }

    if ($sections.ContainsKey('Technical Details')) {
        $tdLines = $sections['Technical Details']
        $subSection = ''
        foreach ($tdLine in $tdLines) {
            if ($tdLine -match '^###\s+Parameters') { $subSection = 'params'; continue }
            if ($tdLine -match '^###\s+Input\s*/\s*Output') { $subSection = 'io'; continue }
            if ($tdLine -match '^###\s+Database') { $subSection = 'db'; continue }
            if ($tdLine -match '^###\s+') { $subSection = ''; continue }

            if ($subSection -eq 'params' -and $tdLine -match '^\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|$') {
                $pName = $Matches[1].Trim()
                $pType = $Matches[2].Trim()
                $pDesc = $Matches[3].Trim()
                if ($pName -ne 'Parameter' -and $pName -ne '---' -and $pName -notmatch '^-+$') {
                    $result.parameters += @{ name = $pName; type = $pType; description = $pDesc }
                }
            }
            if ($subSection -eq 'io' -and $tdLine -match '^\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|$') {
                $dir = $Matches[1].Trim()
                $res = $Matches[2].Trim()
                $desc = $Matches[3].Trim()
                if ($dir -ne 'Direction' -and $dir -ne '---' -and $dir -notmatch '^-+$') {
                    $result.inputOutput += @{ direction = $dir; resource = (Hide-Credentials -Text $res); description = (Hide-Credentials -Text $desc) }
                }
            }
            if ($subSection -eq 'db') {
                if ($tdLine -match '\*\*Technology\*\*:\s*(.+)') { $result.dbTechnology = $Matches[1].Trim() }
                if ($tdLine -match '\*\*Connection\*\*:\s*(.+)') { $result.dbConnection = Hide-Credentials -Text $Matches[1].Trim() }
                if ($tdLine -match '\*\*Tables/Views\*\*:\s*(.+)') { $result.dbTables = $Matches[1].Trim() }
            }
        }
    }

    return $result
}

function Export-SingleDataset {
    param(
        [string]$FolderPath,
        [string]$OutputJsonPath
    )

    $folderName = Split-Path $FolderPath -Leaf
    $historyFiles = Get-ChildItem -Path $FolderPath -Recurse -Filter 'GitHistory.md' -File | Sort-Object FullName
    Write-LogMessage "[$($scriptName)] [$($folderName)] Found $($historyFiles.Count) projects" -Level INFO

    $projects = [System.Collections.Generic.List[object]]::new()

    foreach ($histFile in $historyFiles) {
        $projectFolder = $histFile.DirectoryName
        $relativePath = $projectFolder.Substring($FolderPath.Length).TrimStart('\', '/')

        $gitContent = Get-Content -LiteralPath $histFile.FullName -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($gitContent)) { continue }

        $gitData = Parse-GitHistory -Content $gitContent

        $summaryPath = Join-Path $projectFolder 'PresentationSummary.md'
        $summaryData = @{ businessPurpose = ''; tags = @(); executables = @(); periodSummary = '' }
        if (Test-Path -LiteralPath $summaryPath -PathType Leaf) {
            $summaryContent = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction SilentlyContinue
            if ($summaryContent) { $summaryData = Parse-PresentationSummary -Content $summaryContent }
        }

        $projectName = Split-Path $projectFolder -Leaf
        $section = 'standalone'
        $theme = $null
        if ($relativePath -match '^DedgePsh[\\/]DevTools[\\/]([^\\/]+)[\\/]') {
            $section = 'devtools'; $theme = $Matches[1]
        } elseif ($relativePath -match '^DedgePsh[\\/]_Modules[\\/]') {
            $section = 'module'
        }

        $devMap = @{}
        foreach ($c in $gitData.commits) {
            $displayName = Resolve-AuthorName -RawAuthor $c.author
            if ($devMap.ContainsKey($displayName)) { $devMap[$displayName]++ } else { $devMap[$displayName] = 1 }
        }
        $developers = @($devMap.GetEnumerator() | Sort-Object Value -Descending |
            ForEach-Object { @{ name = $_.Key; commits = $_.Value } })

        $preExisting = $false
        $fed = $gitData.stats.firstEverDate
        $rangeFirst = $gitData.stats.firstDate
        if ($fed -and $fed -ne 'unknown' -and $rangeFirst -and $fed -lt $rangeFirst) {
            $preExisting = $true
        }

        $autoDocLinks = Get-AutoDocLinks -KeySourceFiles $summaryData.executables -TopChangedFiles $gitData.topFiles

        $projects.Add(@{
            id = ConvertTo-ProjectId -Name $relativePath
            name = $projectName
            relativePath = $relativePath.Replace('\', '/')
            sourcePath = $gitData.sourcePath
            repoRoot = $gitData.repoRoot
            remoteUrl = $gitData.remoteUrl
            subPath = $gitData.subPath
            section = $section; theme = $theme
            preExisting = $preExisting; firstEverDate = $fed
            businessPurpose = $summaryData.businessPurpose
            tags = @($summaryData.tags) + @($developers | ForEach-Object { ($_.name -split '\s+')[0].ToLower() }) | Select-Object -Unique
            periodSummary = $summaryData.periodSummary
            executables = $summaryData.executables
            parameters = $summaryData.parameters
            inputOutput = $summaryData.inputOutput
            database = @{
                technology = $summaryData.dbTechnology
                connection = $summaryData.dbConnection
                tables = $summaryData.dbTables
            }
            developers = $developers
            stats = $gitData.stats
            topFiles = @($gitData.topFiles | Select-Object -First 15)
            commits = $gitData.commits
            autoDocLinks = $autoDocLinks
        })
    }

    $allDates = @($projects | ForEach-Object { $_.stats.firstDate } | Where-Object { $_ }) | Sort-Object
    $periodFrom = if ($allDates.Count -gt 0) { $allDates[0] } else { (Get-Date -Format 'yyyy-MM-dd') }
    $periodTo = if ($allDates.Count -gt 0) { $allDates[-1] } else { (Get-Date -Format 'yyyy-MM-dd') }

    # Parse author from folder name (Projects_AUTHOR_from_to)
    $authorFromName = 'unknown'
    if ($folderName -match '^Projects_([^_]+)_') { $authorFromName = $Matches[1] }

    $output = @{
        generated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        datasetName = $folderName
        author = $authorFromName
        period = @{ from = $periodFrom; to = $periodTo }
        projects = @($projects)
    }

    $json = $output | ConvertTo-Json -Depth 10 -Compress:$false
    [System.IO.File]::WriteAllText($OutputJsonPath, $json, [System.Text.Encoding]::UTF8)

    Write-LogMessage "[$($scriptName)] Exported $($projects.Count) projects to $($OutputJsonPath)" -Level INFO

    return @{
        file = Split-Path $OutputJsonPath -Leaf
        name = $folderName
        author = $authorFromName
        periodFrom = $periodFrom
        periodTo = $periodTo
        projectCount = $projects.Count
    }
}

# ── Main logic ───────────────────────────────────────────────────────────────

$foldersToProcess = [System.Collections.Generic.List[string]]::new()

if (-not [string]::IsNullOrWhiteSpace($ExtractFolder)) {
    if (-not (Test-Path -LiteralPath $ExtractFolder -PathType Container)) {
        Write-LogMessage "[$($scriptName)] Folder not found: $($ExtractFolder)" -Level ERROR
        exit 1
    }
    $foldersToProcess.Add($ExtractFolder)
} else {
    $projectDirs = Get-ChildItem -Path $GitHistRoot -Directory -Filter 'Projects_*' | Sort-Object Name
    if ($projectDirs.Count -eq 0) {
        Write-LogMessage "[$($scriptName)] No Projects_* folders found in $($GitHistRoot)" -Level ERROR
        exit 1
    }
    foreach ($d in $projectDirs) { $foldersToProcess.Add($d.FullName) }
}

Write-LogMessage "[$($scriptName)] Processing $($foldersToProcess.Count) dataset(s)" -Level INFO

$datasetEntries = [System.Collections.Generic.List[object]]::new()

foreach ($folder in $foldersToProcess) {
    $folderName = Split-Path $folder -Leaf
    $jsonFileName = "$($folderName).json"
    $jsonPath = Join-Path $OutputDir $jsonFileName
    $meta = Export-SingleDataset -FolderPath $folder -OutputJsonPath $jsonPath
    $datasetEntries.Add($meta)
}

$manifest = @{
    generated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    datasets = @($datasetEntries)
}

$manifestPath = Join-Path $OutputDir 'datasets.json'
$manifestJson = $manifest | ConvertTo-Json -Depth 5 -Compress:$false
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, [System.Text.Encoding]::UTF8)

Write-LogMessage "[$($scriptName)] Manifest written: $($manifestPath) ($($datasetEntries.Count) datasets)" -Level INFO
Write-LogMessage "[$($scriptName)] Done" -Level INFO
