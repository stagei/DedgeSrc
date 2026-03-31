<#
.SYNOPSIS
    Common functions for AutoDoc parsers - Optimized version.

.DESCRIPTION
    Provides shared functionality for all AutoDoc parsers including:
    - File usage tracking (FindUsages)
    - Scheduled task detection
    - Logging utilities
    - SVG generation
    - Mermaid diagram output

.AUTHOR
    Geir Helge Starholm, www.dEdge.no

.NOTES
    Performance optimized version - 2025-12-15
    Migrated to _Modules/AutodocFunctions - 2026-01-19
    
    Key optimizations:
    - Regex-based year pattern matching (vs 28 separate Contains calls)
    - ArrayList for O(1) additions (vs array += O(n²))
    - Buffered file writes
    - Cached string operations
    - HashSet for duplicate checking
#>

# Import required modules
$modulesToImport = @("GlobalFunctions")
foreach ($moduleName in $modulesToImport) {
    $loadedModule = Get-Module -Name $moduleName
    if (-not $loadedModule) {
        Import-Module $moduleName -Force
    }
}

# Global log buffer for batched writes
$script:logBuffer = [System.Collections.ArrayList]::new()
$script:mmdBuffer = [System.Collections.ArrayList]::new()

# Cached shared CSS content
$script:sharedFolder = $null
$script:outputFolder = $null
$script:webFolderRoot = $null

function Get-AutodocSharedFolder {
    <#
    .SYNOPSIS
        Returns the AutoDoc shared folder containing _css, _js, _images, _templates subfolders.
    .DESCRIPTION
        Looks for the AutoDoc folder in multiple locations:
        1. Development: $env:OptPath\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc
        2. Server deployment: $env:OptPath\DedgePshApps\AutoDoc
        3. Fallback: $PSScriptRoot (module folder)
    .OUTPUTS
        String containing the path to the shared folder.
    #>
    
    if ($null -eq $script:sharedFolder) {
        # Try multiple locations for the AutoDoc folder
        $sharedLocations = @(
            "$env:OptPath\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc",  # Development
            "$env:OptPath\DedgePshApps\AutoDoc",                                # Server deployment
            $PSScriptRoot                                                     # Fallback
        )
        
        foreach ($sharedPath in $sharedLocations) {
            # Verify by checking for _css subfolder (key indicator of correct folder)
            $cssFolder = Join-Path $sharedPath "_css"
            if (Test-Path $cssFolder -PathType Container) {
                $script:sharedFolder = $sharedPath
                Write-LogMessage "Set shared folder to: $sharedPath" -Level DEBUG
                break
            }
        }
        
        # If still not found, use first existing path
        if ($null -eq $script:sharedFolder) {
            foreach ($sharedPath in $sharedLocations) {
                if (Test-Path $sharedPath -PathType Container) {
                    $script:sharedFolder = $sharedPath
                    Write-LogMessage "Set shared folder to (fallback): $sharedPath" -Level DEBUG
                    break
                }
            }
        }
    }
    
    return $script:sharedFolder
}

function Get-AutodocTemplatesFolder {
    <#
    .SYNOPSIS
        Returns the AutoDoc templates folder path.
    .DESCRIPTION
        Resolves the _templates subfolder under the AutoDoc shared folder.
        Works for both development and server deployment environments.
    .OUTPUTS
        String containing the full path to the _templates folder.
    #>
    
    $sharedFolder = Get-AutodocSharedFolder
    $templatesFolder = Join-Path $sharedFolder "_templates"
    
    if (-not (Test-Path $templatesFolder -PathType Container)) {
        Write-LogMessage "Templates folder not found: $templatesFolder" -Level WARN
    }
    
    return $templatesFolder
}

function Set-AutodocTemplate {
    <#
    .SYNOPSIS
        Applies common replacements to an AutoDoc HTML template.
    .DESCRIPTION
        Replaces common placeholders including [css], [iconurl], [imageurl], [autodochomepageurl].
        Uses CSS files from OutputFolder\_css subfolder (copied at startup by AutoDocBatchRunner).
    .PARAMETER Template
        The HTML template content.
    .PARAMETER OutputFolder
        The output folder containing .css, .js, .images subfolders.
    .OUTPUTS
        String with common placeholders replaced.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Template,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFolder
    )
  
    # Load and inject shared CSS from OutputFolder\_css subfolder
    $cssFolder = Join-Path $OutputFolder "_css"
    $sharedCssPath = Join-Path $cssFolder "autodoc-shared.css"
    $sharedCss = Get-Content -Path $sharedCssPath -Raw -Encoding UTF8
    $Template = $Template.Replace("[css]", $sharedCss)
    
    # Use relative paths for images and scripts (copied to output folder by AutoDocBatchRunner)
    # Images are in _images/ subfolder
    $Template = $Template.Replace("[iconurl]", "./_images/dedge.ico")
    $Template = $Template.Replace("[imageurl]", "./_images/dedge.svg")
    # Add cache-busting timestamp to JS files to prevent browser caching issues
    $cacheBust = (Get-Date).ToString("yyyyMMddHHmm")
    
    # OLD: Relative paths (commented out)
    # JS files are in _js/ subfolder
    # $Template = $Template.Replace("[mermaidconfigurl]", "./_js/autodoc-mermaid-config.js?v=$cacheBust")
    # $Template = $Template.Replace("[controlsscripturl]", "./_js/autodoc-diagram-controls.js?v=$cacheBust")
    
    # NEW: Central URL for JS files (test server)
    $jsBaseUrl = "http://dedge-server/AutoDoc/_js"
    $Template = $Template.Replace("[mermaidconfigurl]", "$jsBaseUrl/autodoc-mermaid-config.js?v=$cacheBust")
    $Template = $Template.Replace("[controlsscripturl]", "$jsBaseUrl/autodoc-diagram-controls.js?v=$cacheBust")
    $Template = $Template.Replace("[functionscripturl]", "$jsBaseUrl/autodoc-function-navigation.js?v=$cacheBust")
    $Template = $Template.Replace("[autodochomepageurl]", "index.html")
    
    return $Template
}

# Precompiled regex patterns for performance
$script:yearPattern = [regex]::new('20[0-2][0-9]', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$script:skipSuffixPattern = [regex]::new('-(ferdig|gml|old)$', [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$script:skipFilesPattern = [regex]::new('(deploy\.(bat|ps1)|dirt\.bat|dell\.bat|ttt\.bat|tfselect\.bat|launch\.json|tr_rx)', [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

# Helper function to safely add items to ArrayList from various collection types
function Add-SafeRange {
    param([System.Collections.ArrayList]$TargetList, $SourceCollection)
    if ($null -eq $SourceCollection) { return }
    if ($SourceCollection -is [System.Collections.ArrayList]) {
        [void]$TargetList.AddRange($SourceCollection)
    }
    elseif ($SourceCollection -is [array]) {
        [void]$TargetList.AddRange($SourceCollection)
    }
    elseif ($SourceCollection -is [System.Collections.IEnumerable] -and $SourceCollection -isnot [string]) {
        foreach ($item in $SourceCollection) {
            [void]$TargetList.Add($item)
        }
    }
}

function Find-AutodocUsages {
    <#
    .SYNOPSIS
        Finds usages of a pattern across source files.
    
    .DESCRIPTION
        Searches for references to a program/script name across the codebase.
        Optimized with regex patterns and ArrayList for better performance.
    
    .PARAMETER Pattern
        The pattern to search for (e.g., program name).
    
    .PARAMETER FindPath
        The path to search in.
    
    .PARAMETER IncludeFilter
        File filter (e.g., "*.cbl", "*.xml").
    
    .PARAMETER ResultArray
        Existing results array to append to.
    
    .PARAMETER ResultArrayFull
        Existing full results array to append to.
    
    .OUTPUTS
        Two arrays: simplified results and full results.
    
    .EXAMPLE
        $results, $fullResults = Find-AutodocUsages -Pattern "MYPROG" -FindPath "C:\src" -IncludeFilter "*.cbl"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern, 
        [Parameter(Mandatory = $true)]
        [string]$FindPath, 
        [Parameter(Mandatory = $true)]
        $IncludeFilter, 
        $ResultArray, 
        $ResultArrayFull
    )

    # Early exit for invalid patterns
    $pos = $Pattern.IndexOf(".")
    $length = if ($pos -ne -1) { $pos } else { $Pattern.Length }
    
    if ([string]::IsNullOrEmpty($Pattern) -or $length -lt 4) {
        return $ResultArray, $ResultArrayFull
    }
    
    # Extract base pattern without extension
    if ($Pattern.Contains(".cbl") -or $Pattern.Contains(".rex")) {
        $Pattern = $Pattern.Split(".")[0]
    }
    
    # Use ArrayList for O(1) additions
    $resultList = [System.Collections.ArrayList]::new()
    $resultFullList = [System.Collections.ArrayList]::new()
    if ($ResultArray) { [void]$resultList.AddRange($ResultArray) }
    if ($ResultArrayFull) { [void]$resultFullList.AddRange($ResultArrayFull) }
    
    $patternLower = $Pattern.Trim().ToLower()
    
    if ($IncludeFilter -eq "*.xml") {
        # XML file search for scheduled tasks
        if (Test-Path $FindPath) {
            $resultFiles = Get-ChildItem -Path $FindPath -Filter $IncludeFilter -Recurse -ErrorAction SilentlyContinue | 
            Select-String "(<Command>.*</Command>|<Arguments>.*</Arguments>)" | 
            Select-String $Pattern 
            
            foreach ($item in $resultFiles) {
                $filenameLower = $item.Filename.Trim().ToLower()
                if ($filenameLower -eq $patternLower) { continue }
                if ($script:baseFileNameTemp -ne $filenameLower) {
                    [void]$resultList.Add($filenameLower)
                    [void]$resultFullList.Add($item)
                }
            }
        }
    }
    else {
        # Source file search
        if (Test-Path $FindPath) {
            $resultFiles = Get-ChildItem -Path $FindPath -Include $IncludeFilter -Recurse -ErrorAction SilentlyContinue | 
            Select-String $Pattern -ErrorAction SilentlyContinue | 
            Select-Object Path, Line, Filename, Extension, BaseName
            
            foreach ($item in $resultFiles) {
                # Cache lowercase values
                $filename = $item.Filename.ToLower().Trim()
                $pos = $filename.LastIndexOf(".")
                $extension = if ($pos -eq -1) { "" } else { $filename.Substring($pos) }
                $baseName = if ($pos -eq -1) { $filename } else { $filename.Substring(0, $pos) }
                $lineLower = $item.Line.ToLower().Trim()
                
                # Skip comments based on file type
                switch ($extension) {
                    ".bat" { if ($lineLower.StartsWith("rem")) { continue } }
                    ".ps1" { if ($lineLower.StartsWith("#")) { continue } }
                    ".rex" { if ($lineLower.StartsWith("#")) { continue } }
                    ".cbl" { if ($lineLower.Length -gt 6 -and $lineLower.Substring(6, 1) -eq "*") { continue } }
                    ".xml" { if ($lineLower.StartsWith("<!--")) { continue } }
                }
                
                # Verify exact pattern match
                $pos = $lineLower.IndexOf($patternLower)
                if ($pos -eq -1) { continue }
                
                $temp = ($lineLower.Substring($pos).Trim() -replace "['""]", "") + " "
                $temp = $temp.Split(" ")[0]
                if ($temp -ne $patternLower) { continue }
                
                # Skip self-references
                if ($baseName -eq $patternLower -and ($extension -eq ".cbl" -or $extension -eq ".rex")) { continue }
                if ($filename -eq $patternLower) { continue }
                
                # Skip utility files using precompiled regex
                if ($script:skipFilesPattern.IsMatch($filename)) { continue }
                
                # Skip year-based and old files using precompiled regex (MAJOR OPTIMIZATION)
                if ($script:yearPattern.IsMatch($baseName) -or $script:skipSuffixPattern.IsMatch($baseName)) {
                    continue
                }
                
                if ($script:baseFileNameTemp -ne $filename) {
                    try {
                        [void]$resultList.Add($filename)
                        [void]$resultFullList.Add($item)
                    }
                    catch {
                        Write-LogMessage ("Error in Find-AutodocUsages: " + $_.Exception.Message) -Level ERROR -Exception $_
                    }
                }
            }
        }
    }
    
    # Return unique sorted results
    $uniqueResults = $resultList | Sort-Object -Unique | Where-Object { $_ -match '^[\x00-\x7F]+$' }
    $uniqueResultsFull = $resultFullList | Sort-Object -Unique
    
    return @($uniqueResults), @($uniqueResultsFull)
}

function Test-ExecutedFromScheduledTask {
    <#
    .SYNOPSIS
        Checks if a script is executed from Windows Task Scheduler.
    
    .DESCRIPTION
        Searches scheduled task XML exports to find if the given script/program
        is called from any scheduled task.
    
    .PARAMETER ProgramInUse
        Current usage status.
    
    .PARAMETER ReturnMmdArray
        Array of Mermaid diagram lines.
    
    .PARAMETER SearchFiles
        Set of already searched files.
    
    .PARAMETER SrcRootFolder
        Root folder for source files.
    
    .PARAMETER Filename
        The filename to search for.
    
    .OUTPUTS
        Updated ProgramInUse status, Mermaid array, and search files set.
    #>
    [CmdletBinding()]
    param(
        $ProgramInUse, 
        $ReturnMmdArray, 
        $SearchFiles, 
        [Parameter(Mandatory = $true)]
        [string]$SrcRootFolder, 
        [Parameter(Mandatory = $true)]
        [string]$Filename
    )
    
    $findpath = Join-Path $SrcRootFolder "Dedge\ExportScheduledTasks\"
    
    if (-not (Test-Path $findpath)) {
        return $ProgramInUse, $ReturnMmdArray, $SearchFiles
    }
    
    $resultArray1 = @()
    $resultArrayFull = @()
    $null, $resultArray1 = Find-AutodocUsages -Pattern $Filename.ToString() -FindPath $findpath -IncludeFilter "*.xml" -ResultArrayFull $resultArrayFull
    
    # Use HashSet for O(1) contains check
    $searchSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $SearchFiles) {
        foreach ($s in $SearchFiles) { 
            if ($null -ne $s) { [void]$searchSet.Add([string]$s) }
        }
    }
    
    $mmdList = [System.Collections.ArrayList]::new()
    Add-SafeRange -TargetList $mmdList -SourceCollection $ReturnMmdArray
    
    $filenameLower = $Filename.ToString().Trim().ToLower()
    
    foreach ($item in $resultArray1) {
        if (-not $item.Path) { continue }
        
        $temp1 = $item.Path.Trim().ToLower().Split("exportscheduledtasks")
        if ($temp1.Count -lt 2) { continue }
        
        $temp2 = $temp1[1].Split("\")
        if ($temp2.Count -lt 2) { continue }
        
        $server = $temp2[1].ToUpper().Trim()
        $itemFilenameLower = $item.Filename.ToString().Trim().ToLower()
        $searchKey = "$itemFilenameLower¤$filenameLower"
        
        if ($searchSet.Contains($searchKey)) { continue }
        
        [void]$searchSet.Add($searchKey)
        $ProgramInUse = $true
        
        $scheduledTask = "ScheduledTask on server $server`n" + $item.Filename.Trim().Replace(".xml", "")
        [void]$mmdList.Add($item.Filename.Trim().Replace(".xml", "") + ">`"$scheduledTask`"]-.->$filenameLower")
    }
    
    # Return the actual collections, not array-casted versions, to preserve HashSet and ArrayList types
    return $ProgramInUse, $mmdList, $searchSet
}

function Get-AutodocExecutionPath {
    <#
    .SYNOPSIS
        Common handling for execution path analysis.
    
    .DESCRIPTION
        Processes execution paths for generating Mermaid diagrams showing
        program call hierarchies.
    #>
    [CmdletBinding()]
    param(
        $SearchFiles, 
        $Item, 
        $PrevItem, 
        $ReturnMmdArray, 
        $ProgramInUse,
        [string]$SrcRootFolder
    )

    try {
        $skipLine = $false
        
        # Handle null or empty Item - return early with skip flag
        # Use [string] cast to safely handle null without calling .ToString()
        if ($null -eq $Item -or [string]::IsNullOrWhiteSpace([string]$Item)) {
            $mmdList = [System.Collections.ArrayList]::new()
            Add-SafeRange -TargetList $mmdList -SourceCollection $ReturnMmdArray
            # Return actual collections to preserve types
            return "", "", $SearchFiles, $true, $mmdList, $ProgramInUse
        }
        
        $itemLower = ([string]$Item).ToLower().Trim()
        $searchItem = $itemLower -replace '\.(cbl|rex)$', ''
        
        # Skip utility files using precompiled regex (with null check for safety)
        if (($null -ne $script:skipFilesPattern -and $script:skipFilesPattern.IsMatch($itemLower)) -or $itemLower.Contains(" ")) {
            $skipLine = $true
        }
        
        # Use HashSet for efficient duplicate checking - ensure we always have a valid HashSet
        $searchSet = $null
        if ($SearchFiles -is [System.Collections.Generic.HashSet[string]]) {
            $searchSet = $SearchFiles
        }
        else {
            $searchSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            if ($null -ne $SearchFiles) {
                foreach ($s in $SearchFiles) { 
                    if ($null -ne $s) { [void]$searchSet.Add([string]$s) }
                }
            }
        }
        
        $mmdList = [System.Collections.ArrayList]::new()
        Add-SafeRange -TargetList $mmdList -SourceCollection $ReturnMmdArray
        
        if ($null -ne $PrevItem -and -not [string]::IsNullOrWhiteSpace([string]$PrevItem)) {
            $prevItemLower = ([string]$PrevItem).Trim().ToLower()
            $searchKey = "$itemLower¤$prevItemLower"
            
            if ($searchSet.Contains($searchKey)) {
                $skipLine = $true
            }
            else {
                [void]$searchSet.Add($searchKey)
            }
            
            if (-not $skipLine) {
                [void]$mmdList.Add("$itemLower[[$itemLower]]-.->$prevItemLower")
                $link = "./$($itemLower.Trim()).html"
                [void]$mmdList.Add("click $itemLower `"$link`" `"$itemLower`" _blank")
                [void]$mmdList.Add("style $itemLower stroke:dark-blue,stroke-width:4px")
            }
        }
        
        if (-not $skipLine) {
            $ProgramInUse, $mmdList, $searchSet = Test-ExecutedFromScheduledTask -ProgramInUse $ProgramInUse -ReturnMmdArray $mmdList -SearchFiles $searchSet -SrcRootFolder $SrcRootFolder -Filename $itemLower
        }
        
        # Return actual collections to preserve HashSet and ArrayList types for subsequent calls
        return $itemLower, $searchItem, $searchSet, $skipLine, $mmdList, $ProgramInUse
    }
    catch {
        # On any error, return skip=true to continue processing other items
        $mmdList = [System.Collections.ArrayList]::new()
        Add-SafeRange -TargetList $mmdList -SourceCollection $ReturnMmdArray
        return "", "", $SearchFiles, $true, $mmdList, $ProgramInUse
    }
}

function Find-AutodocExecutionPaths {
    <#
    .SYNOPSIS
        Finds all execution paths for a script/program.
    
    .DESCRIPTION
        Searches the codebase to find all ways a program can be executed,
        including from scheduled tasks, other scripts, and batch files.
    
    .PARAMETER FindPath
        The path to search in.
    
    .PARAMETER IncludeFilter
        File filter for the search.
    
    .PARAMETER Filename
        The filename to find execution paths for.
    
    .PARAMETER ProgramInUse
        Current usage status.
    
    .PARAMETER SrcRootFolder
        Root folder for source files.
    
    .OUTPUTS
        Updated ProgramInUse status and Mermaid diagram array.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FindPath, 
        [Parameter(Mandatory = $true)]
        $IncludeFilter, 
        [Parameter(Mandatory = $true)]
        [string]$Filename, 
        $ProgramInUse, 
        [Parameter(Mandatory = $true)]
        [string]$SrcRootFolder
    )
    
    $resultArray = @()
    $resultArrayFull = @()
    $searchFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $returnMmdArray = [System.Collections.ArrayList]::new()
    
    $Filename, $searchItem, $searchFiles, $skipLine, $returnMmdArray, $ProgramInUse = Get-AutodocExecutionPath -SearchFiles $searchFiles -ReturnMmdArray $returnMmdArray -ProgramInUse $ProgramInUse -PrevItem $null -Item $Filename -SrcRootFolder $SrcRootFolder
    
    # Find primary usages
    $resultArray1, $null = Find-AutodocUsages -Pattern $searchItem -FindPath $FindPath -IncludeFilter $IncludeFilter -ResultArray $resultArray -ResultArrayFull $resultArrayFull
    
    if ($null -eq $resultArray1 -or $resultArray1.Count -eq 0) {
        # Convert to array for final return to caller
        return $ProgramInUse, @($returnMmdArray)
    }
    
    # Filter out null/empty values and get unique sorted results
    # Use separate null check to avoid calling .ToString() on null
    $filteredArray1 = @()
    foreach ($r in $resultArray1) {
        if ($null -ne $r -and -not [string]::IsNullOrWhiteSpace([string]$r)) {
            $filteredArray1 += $r
        }
    }
    $resultArray1 = $filteredArray1 | Sort-Object -Unique
    
    foreach ($item in $resultArray1) {
        if ($null -eq $item -or [string]::IsNullOrWhiteSpace([string]$item)) { continue }
        
        $item, $searchItem1, $searchFiles, $skipLine, $returnMmdArray, $ProgramInUse = Get-AutodocExecutionPath -SearchFiles $searchFiles -ReturnMmdArray $returnMmdArray -ProgramInUse $ProgramInUse -PrevItem $Filename -Item $item -SrcRootFolder $SrcRootFolder
        
        if ($skipLine) { continue }
        $ProgramInUse = $true
        
        # Find secondary usages
        $resultArray2, $null = Find-AutodocUsages -Pattern $searchItem1 -FindPath $FindPath -IncludeFilter $IncludeFilter -ResultArray $resultArray -ResultArrayFull $resultArrayFull
        
        # Filter out null/empty values and get unique sorted results
        $filteredArray2 = @()
        foreach ($r in $resultArray2) {
            if ($null -ne $r -and -not [string]::IsNullOrWhiteSpace([string]$r)) {
                $filteredArray2 += $r
            }
        }
        $resultArray2 = $filteredArray2 | Sort-Object -Unique
        
        foreach ($item2 in $resultArray2) {
            if ($null -eq $item2 -or [string]::IsNullOrWhiteSpace([string]$item2)) { continue }
            
            $item2, $searchItem2, $searchFiles, $skipLine, $returnMmdArray, $ProgramInUse = Get-AutodocExecutionPath -SearchFiles $searchFiles -ReturnMmdArray $returnMmdArray -ProgramInUse $ProgramInUse -PrevItem $item -Item $item2 -SrcRootFolder $SrcRootFolder
            
            if ($skipLine) { continue }
            $ProgramInUse = $true
            # Tertiary usages skipped for performance
        }
    }
    
    return $ProgramInUse, @($returnMmdArray)
}

function New-AutodocSvgFile {
    <#
    .SYNOPSIS
        Generates SVG file from Mermaid diagram.
    
    .DESCRIPTION
        Calls mmdc.cmd to convert .mmd to .svg with link target fixes.
    
    .PARAMETER MmdFilename
        Path to the .mmd file to convert.
    
    .PARAMETER ConfigPath
        Optional path to config.json for mmdc.
    
    .OUTPUTS
        Boolean indicating success or failure.
    
    .EXAMPLE
        $success = New-AutodocSvgFile -MmdFilename "C:\output\MYPROG.CBL.mmd"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MmdFilename,
        [string]$ConfigPath
    )
    
    try {
        $svgFilename = $MmdFilename.Replace(".mmd", ".svg")
        
        if (Test-Path $svgFilename) {
            Remove-Item $svgFilename -Force
        }
        
        # Use provided config path or try to find it
        if (-not $ConfigPath) {
            $ConfigPath = Join-Path $PSScriptRoot "..\..\DevTools\LegacyCodeTools\AutoDoc\config.json"
            if (-not (Test-Path $ConfigPath)) {
                $ConfigPath = ".\config.json"  # Fallback to relative
            }
        }
        
        $processOutput = mmdc.cmd -i $MmdFilename -o $svgFilename --configFile $ConfigPath 2>&1
        
        if ($processOutput -match "Error:") {
            if ($processOutput.Count -ge 6) {
                Write-LogMessage "Error in mmdc.cmd. SVG not generated. See: $MmdFilename" -Level ERROR
                Write-LogMessage ($processOutput -join "`n") -Level ERROR
            }
            throw [System.IO.FileNotFoundException] "$svgFilename not found."
        }
        
        # Read content and apply all replacements at once
        $content = [System.IO.File]::ReadAllText($svgFilename)
        
        # Define replacement pairs
        $replacements = @(
            @('.cbl.html">', '.cbl.html" target="_blank">')
            @('.sql.html">', '.sql.html" target="_blank">')
            @('.rex.html">', '.rex.html" target="_blank">')
            @('.bat.html">', '.bat.html" target="_blank">')
            @('.ps1.html">', '.ps1.html" target="_blank">')
            @('.cbl">', '.cbl" target="_blank">')
            @('.sql">', '.sql" target="_blank">')
            @('.rex">', '.rex" target="_blank">')
            @('.bat">', '.bat" target="_blank">')
            @('.ps1">', '.ps1" target="_blank">')
            @('ProjectFilters%7BDedge%7D">', 'ProjectFilters%7BDedge%7D" target="_blank">')
            @('lineStartColumn=1&amp;lineEndColumn=1&amp;lineStyle=plain&amp;_a=contents">', 'lineStartColumn=1&amp;lineEndColumn=1&amp;lineStyle=plain&amp;_a=contents" target="_blank">')
            @('Dedgeopath=', 'Dedge?path=')
        )
        
        foreach ($pair in $replacements) {
            $content = $content.Replace($pair[0], $pair[1])
        }
        
        [System.IO.File]::WriteAllText($svgFilename, $content)
        return $true
    }
    catch {
        Write-LogMessage "Error in New-AutodocSvgFile: $($_.Exception.Message)" -Level ERROR -Exception $_
        return $false
    }
}

function Write-AutodocMermaidLine {
    <#
    .SYNOPSIS
        Writes a line to the Mermaid diagram - supports both file and in-memory modes.
    
    .DESCRIPTION
        Optimized with HashSet for duplicate checking. Supports two modes:
        1. File mode: Writes to $script:mmdFilename (for server-side SVG generation)
        2. Memory mode: Appends to $script:mmdFlowContent ArrayList (for client-side rendering)
        
        Mode is determined by $script:useClientSideRender in the caller's scope.
    
    .PARAMETER MmdString
        The Mermaid diagram line to write.
    
    .PARAMETER ContentArray
        Optional: An ArrayList to append to instead of using global/script variables.
        When provided, this function operates in a completely thread-safe manner.
    
    .PARAMETER DuplicateSet
        Optional: A HashSet for duplicate checking. When provided with ContentArray,
        enables fully thread-safe operation without any global state.
    
    .EXAMPLE
        Write-AutodocMermaidLine -MmdString "A-->B"
        
    .EXAMPLE
        # Thread-safe usage with explicit ArrayList
        $mmdContent = [System.Collections.ArrayList]::new()
        $dupCheck = [System.Collections.Generic.HashSet[string]]::new()
        Write-AutodocMermaidLine -MmdString "A-->B" -ContentArray $mmdContent -DuplicateSet $dupCheck
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MmdString,
        
        [System.Collections.ArrayList]$ContentArray = $null,
        
        [System.Collections.Generic.HashSet[string]]$DuplicateSet = $null
    )
    
    # Thread-safe mode: Use provided ArrayList and HashSet
    if ($null -ne $ContentArray -and $null -ne $DuplicateSet) {
        if (-not $DuplicateSet.Contains($MmdString)) {
            # Add sequence numbers to arrows
            if ($MmdString.Contains("-->") -and -not $MmdString.ToLower().Contains("initiated-->")) {
                $pos1 = $MmdString.IndexOf("-->")
                $pos2 = $MmdString.LastIndexOf("-->")
                if ($pos1 -eq $pos2) {
                    # Use counter in the set as sequence number
                    $seqNum = $DuplicateSet.Count + 1
                    $MmdString = $MmdString.Substring(0, $pos1) + "(#$seqNum)" + $MmdString.Substring($pos1)
                }
            }
            [void]$ContentArray.Add($MmdString)
            [void]$DuplicateSet.Add($MmdString)
        }
        return
    }
    
    # Legacy mode: Use script/global variables (for backwards compatibility)
    # Note: This mode is NOT thread-safe and should not be used in parallel processing
    
    # Initialize duplicate check HashSet if needed
    if ($null -eq $script:duplicateLineCheckSet) {
        $script:duplicateLineCheckSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        if ($script:duplicateLineCheck) {
            foreach ($line in $script:duplicateLineCheck) {
                [void]$script:duplicateLineCheckSet.Add($line)
            }
        }
    }
    
    if (-not $script:duplicateLineCheckSet.Contains($MmdString)) {
        # Add sequence numbers to arrows
        if ($MmdString.Contains("-->") -and -not $MmdString.ToLower().Contains("initiated-->")) {
            $pos1 = $MmdString.IndexOf("-->")
            $pos2 = $MmdString.LastIndexOf("-->")
            if ($pos1 -eq $pos2) {
                $script:sequenceNumber++
                $MmdString = $MmdString.Substring(0, $pos1) + "(#$($script:sequenceNumber))" + $MmdString.Substring($pos1)
            }
        }
        
        # Check if we're using client-side rendering (in-memory mode)
        if ($script:useClientSideRender -and $null -ne $script:mmdFlowContent) {
            [void]$script:mmdFlowContent.Add($MmdString)
        }
        elseif ($global:mmdFilename) {
            # Use global variable set by the calling parser module
            Add-Content -Path $global:mmdFilename -Value $MmdString -Force
        }
        elseif ($script:mmdFilename) {
            Add-Content -Path $script:mmdFilename -Value $MmdString -Force
        }
        
        [void]$script:duplicateLineCheckSet.Add($MmdString)
    }
}

#region Backward Compatibility Aliases
# These aliases maintain backward compatibility with the old function names
# from CommonFunctions.psm1. They should be considered deprecated.

function FindUsages {
    <#
    .SYNOPSIS
        DEPRECATED: Use Find-AutodocUsages instead.
    #>
    [CmdletBinding()]
    param($pattern, $findpath, $includeFilter, $resultArray, $resultArrayFull)
    Find-AutodocUsages -Pattern $pattern -FindPath $findpath -IncludeFilter $includeFilter -ResultArray $resultArray -ResultArrayFull $resultArrayFull
}

function IsExecutedFromSceduledTask {
    <#
    .SYNOPSIS
        DEPRECATED: Use Test-ExecutedFromScheduledTask instead.
    #>
    [CmdletBinding()]
    param($programInUse, $returnMmdArray, $searchFiles, $srcRootFolder, $filename)
    Test-ExecutedFromScheduledTask -ProgramInUse $programInUse -ReturnMmdArray $returnMmdArray -SearchFiles $searchFiles -SrcRootFolder $srcRootFolder -Filename $filename
}

function CommonHandlingExecutionPath {
    <#
    .SYNOPSIS
        DEPRECATED: Use Get-AutodocExecutionPath instead.
    #>
    [CmdletBinding()]
    param($searchFiles, $item, $prevItem, $returnMmdArray, $programInUse)
    # Note: SrcRootFolder needs to be passed from the calling context
    Get-AutodocExecutionPath -SearchFiles $searchFiles -Item $item -PrevItem $prevItem -ReturnMmdArray $returnMmdArray -ProgramInUse $programInUse -SrcRootFolder $script:srcRootFolder
}

function IsExecutedFromAny {
    <#
    .SYNOPSIS
        DEPRECATED: Use Find-AutodocExecutionPaths instead.
    #>
    [CmdletBinding()]
    param($findpath, $includeFilter, $filename, $programInUse, $srcRootFolder)
    Find-AutodocExecutionPaths -FindPath $findpath -IncludeFilter $includeFilter -Filename $filename -ProgramInUse $programInUse -SrcRootFolder $srcRootFolder
}

function GenerateSvgFile {
    <#
    .SYNOPSIS
        DEPRECATED: Use New-AutodocSvgFile instead.
    #>
    [CmdletBinding()]
    param([string]$mmdFilename)
    New-AutodocSvgFile -MmdFilename $mmdFilename
}

function WriteMmdCommon {
    <#
    .SYNOPSIS
        DEPRECATED: Use Write-AutodocMermaidLine instead.
    #>
    [CmdletBinding()]
    param([string]$mmdString)
    Write-AutodocMermaidLine -MmdString $mmdString
}

function LogMessage {
    <#
    .SYNOPSIS
        DEPRECATED: Use Write-LogMessage from GlobalFunctions instead.
    #>
    [CmdletBinding()]
    param([string]$message, [switch]$Flush)
    Write-LogMessage $message -Level INFO
}
#endregion

#region Common Parser Helper Functions

function Find-AutodocParserScript {
    <#
    .SYNOPSIS
        Finds the path to an AutoDoc parser script.
    
    .DESCRIPTION
        Searches for the specified parser script in multiple locations:
        1. Relative to the module folder
        2. In $env:OptPath\src\DedgePsh
        3. In the current directory
    
    .PARAMETER ParserName
        Name of the parser (e.g., "Cbl", "Ps1", "Rex", "Bat", "Sql").
    
    .OUTPUTS
        Full path to the parser script, or $null if not found.
    
    .EXAMPLE
        $scriptPath = Find-AutodocParserScript -ParserName "Cbl"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Cbl", "Ps1", "Rex", "Bat", "Sql")]
        [string]$ParserName
    )
    
    $scriptFileName = "${ParserName}Parse.ps1"
    
    # Try module-relative path first
    $scriptPath = Join-Path $PSScriptRoot "..\..\DevTools\LegacyCodeTools\AutoDoc\$scriptFileName"
    if (Test-Path $scriptPath) {
        return (Resolve-Path $scriptPath).Path
    }
    
    # Try OptPath\src\DedgePsh
    $scriptPath = "$env:OptPath\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\$scriptFileName"
    if (Test-Path $scriptPath) {
        return $scriptPath
    }
    
    # Try current directory
    $scriptPath = ".\$scriptFileName"
    if (Test-Path $scriptPath) {
        return (Resolve-Path $scriptPath).Path
    }
    
    return $null
}

function Invoke-AutodocParserScript {
    <#
    .SYNOPSIS
        Invokes an AutoDoc parser script with common parameter handling.
    
    .DESCRIPTION
        Common wrapper for executing AutoDoc parser scripts. Handles:
        - Script path finding
        - Parameter building
        - Execution with error handling
        - HTML filename return
    
    .PARAMETER ParserName
        Name of the parser (e.g., "Cbl", "Ps1", "Rex", "Bat").
    
    .PARAMETER SourceFile
        Path to the source file to parse.
    
    .PARAMETER Show
        If true, opens the generated HTML file after creation.
    
    .PARAMETER OutputFolder
        Output folder for generated files.
    
    .PARAMETER CleanUp
        If true, cleans up temporary files after processing.
    
    .PARAMETER TmpRootFolder
        Root folder for temporary files.
    
    .PARAMETER SrcRootFolder
        Root folder for source files.
    
    .PARAMETER ClientSideRender
        Skip SVG generation and use client-side Mermaid.js rendering.
    
    .PARAMETER SaveMmdFiles
        Save Mermaid diagram source files (.mmd) alongside the HTML output.
    
    .OUTPUTS
        Path to the generated HTML file, or $null on error.
    
    .EXAMPLE
        $htmlFile = Invoke-AutodocParserScript -ParserName "Cbl" -SourceFile "C:\src\MYPROG.CBL"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Cbl", "Ps1", "Rex", "Bat")]
        [string]$ParserName,
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [bool]$Show = $false,
        [string]$OutputFolder = "$env:OptPath\Webs\AutoDoc",
        [bool]$CleanUp = $true,
        [string]$TmpRootFolder = "$env:OptPath\data\AutoDoc\tmp",
        [string]$SrcRootFolder = "$env:OptPath\data\AutoDoc\src",
        [switch]$ClientSideRender,
        [switch]$SaveMmdFiles
    )
    
    # Find the parser script
    $scriptPath = Find-AutodocParserScript -ParserName $ParserName
    
    if (-not $scriptPath) {
        Write-LogMessage "${ParserName}Parse.ps1 not found. Cannot parse file." -Level ERROR
        return $null
    }
    
    # Build parameters
    $params = @{
        sourceFile    = $SourceFile
        show          = $Show
        outputFolder  = $OutputFolder
        cleanUp       = $CleanUp
        tmpRootFolder = $TmpRootFolder
        srcRootFolder = $SrcRootFolder
    }
    
    if ($ClientSideRender) {
        $params.Add("clientSideRender", $true)
    }
    
    if ($SaveMmdFiles) {
        $params.Add("saveMmdFiles", $true)
    }
    
    try {
        # Execute the parser script
        & $scriptPath @params
        
        # Return the HTML filename
        $baseFileName = [System.IO.Path]::GetFileName($SourceFile)
        $htmlFilename = Join-Path $OutputFolder "$baseFileName.html"
        
        if (Test-Path $htmlFilename) {
            return $htmlFilename
        }
        return $null
    }
    catch {
        Write-LogMessage "Error executing ${ParserName}Parse.ps1: $($_.Exception.Message)" -Level ERROR -Exception $_
        return $null
    }
}

function Set-AutodocTemplateUrls {
    <#
    .SYNOPSIS
        Replaces URL placeholders in AutoDoc HTML template content.
    
    .DESCRIPTION
        Common function to replace standard AutoDoc URL placeholders:
        - [autodochomepageurl] - AutoDoc home page URL
        - [imageurl] - FK logo SVG URL
        - [iconurl] - FK favicon URL
    
    .PARAMETER Content
        The template content (string or array) to process.
    
    .OUTPUTS
        The content with URL placeholders replaced.
    
    .EXAMPLE
        $doc = Get-Content -Path $templateFile
        $doc = Set-AutodocTemplateUrls -Content $doc
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Content
    )
    
    $baseUrl = Get-DevToolsWebPathUrl
    
    # Handle both string and array input
    if ($Content -is [array]) {
        $Content = $Content -join "`n"
    }
    
    # Use relative paths for images and scripts (copied to output folder by AutoDocBatchRunner)
    # Images are in _images/ subfolder
    $Content = $Content.Replace("[autodochomepageurl]", "$baseUrl/AutoDoc")
    $Content = $Content.Replace("[imageurl]", "./_images/dedge.svg")
    $Content = $Content.Replace("[iconurl]", "./_images/dedge.ico")
    # Add cache-busting timestamp to JS files to prevent browser caching issues
    $cacheBust = (Get-Date).ToString("yyyyMMddHHmm")
    
    # OLD: Relative paths (commented out)
    # JS files are in _js/ subfolder
    # $Content = $Content.Replace("[mermaidconfigurl]", "./_js/autodoc-mermaid-config.js?v=$cacheBust")
    # $Content = $Content.Replace("[controlsscripturl]", "./_js/autodoc-diagram-controls.js?v=$cacheBust")
    
    # NEW: Central URLs for JS files (test server)
    $jsBaseUrl = "http://dedge-server/AutoDoc/_js"
    $Content = $Content.Replace("[mermaidconfigurl]", "$jsBaseUrl/autodoc-mermaid-config.js?v=$cacheBust")
    $Content = $Content.Replace("[controlsscripturl]", "$jsBaseUrl/autodoc-diagram-controls.js?v=$cacheBust")
    
    return $Content
}

function Get-AutodocTemplateFile {
    <#
    .SYNOPSIS
        Finds an AutoDoc HTML template file.
    
    .DESCRIPTION
        Searches for the specified template file in multiple locations:
        1. Relative to the module folder (DevTools\LegacyCodeTools\AutoDoc)
        2. In the current directory
    
    .PARAMETER TemplateName
        Name of the template file (e.g., "cblmmdtemplate.html").
    
    .OUTPUTS
        Full path to the template file, or $null if not found.
    
    .EXAMPLE
        $templatePath = Get-AutodocTemplateFile -TemplateName "cblmmdtemplate.html"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateName
    )
    
    $basePath = Join-Path $PSScriptRoot "..\..\DevTools\LegacyCodeTools\AutoDoc"
    $templatesFolder = Join-Path $basePath "_templates"
    
    # Try _templates subfolder first (new structure)
    $templatePath = Join-Path $templatesFolder $TemplateName
    if (Test-Path $templatePath) {
        return (Resolve-Path $templatePath).Path
    }
    
    # Fallback to base folder (legacy)
    $templatePath = Join-Path $basePath $TemplateName
    if (Test-Path $templatePath) {
        return (Resolve-Path $templatePath).Path
    }
    
    # Try current directory
    if (Test-Path ".\$TemplateName") {
        return (Resolve-Path ".\$TemplateName").Path
    }
    
    return $null
}

#endregion

# Note: Parser modules (SqlParseFunctions, BatParseFunctions, etc.) have been consolidated
# directly into this module. All Start-* functions are defined below in their respective regions.

#region Bat Parse Functions
<#
.SYNOPSIS
    Windows Batch Parser Functions for AutoDoc.

.DESCRIPTION
    Contains all functions needed to parse Windows Batch files (.bat) and generate
    AutoDoc HTML pages with Mermaid flowchart diagrams.
    Entry point: Start-BatParse

.AUTHOR
    Geir Helge Starholm, www.dEdge.no

.NOTES
    Migrated from BatParse.ps1 to AutodocFunctions module - 2026-01-19
#>

#region Batch Parser Local Functions

function Add-BatExternalProcess {
    <#
    .SYNOPSIS
        Tracks an external process invocation for the process execution diagram.
    #>
    param(
        [string]$Type,        # DB2, PowerShell, COBOL, REXX, WindowsCmd
        [string]$Name,        # Process/script name
        [string]$Details = "" # Additional details
    )
    
    if (-not $script:externalProcesses) {
        $script:externalProcesses = @()
    }
    
    $script:externalProcesses += @{
        Type    = $Type
        Name    = $Name
        Details = $Details
    }
}

function New-BatProcessExecutionDiagram {
    <#
    .SYNOPSIS
        Generates a Mermaid diagram showing all external process invocations.
    #>
    param([string]$ScriptName)
    
    if (-not $script:externalProcesses -or $script:externalProcesses.Count -eq 0) {
        return "flowchart LR`n    noprocess[No external processes detected]"
    }
    
    $mmdContent = @()
    $mmdContent += "%%{ init: { 'flowchart': { 'curve': 'basis' } } }%%"
    $mmdContent += "flowchart LR"
    
    # Add main script node with safe Mermaid node ID
    $scriptNode = $ScriptName -replace '[^a-zA-Z0-9_]', '_'
    if ($scriptNode -match '^[0-9]') {
        $scriptNode = "_" + $scriptNode
    }
    $mmdContent += "    $($scriptNode)[[`"$ScriptName`"]]"
    $mmdContent += "    style $scriptNode stroke:#7c3aed,stroke-width:3px"
    
    # Group processes by type
    $groupedProcesses = $script:externalProcesses | Group-Object -Property Type
    
    $nodeCounter = 0
    foreach ($group in $groupedProcesses) {
        $typeLabel = switch ($group.Name) {
            "DB2" { "DB2 Commands"; break }
            "PowerShell" { "PowerShell Scripts"; break }
            "COBOL" { "COBOL Programs"; break }
            "REXX" { "REXX Scripts"; break }
            "WindowsCmd" { "Windows Commands"; break }
            default { $group.Name }
        }
        
        $typeShape = switch ($group.Name) {
            "DB2" { "[("; break }       # Cylinder
            "PowerShell" { "{{"; break } # Hexagon  
            "COBOL" { "[["; break }     # Subroutine
            "REXX" { "(["; break }      # Stadium
            "WindowsCmd" { "("; break } # Rounded
            default { "(" }
        }
        
        $typeShapeEnd = switch ($group.Name) {
            "DB2" { ")]"; break }
            "PowerShell" { "}}"; break }
            "COBOL" { "]]"; break }
            "REXX" { "])"; break }
            "WindowsCmd" { ")"; break }
            default { ")" }
        }
        
        $typeColor = switch ($group.Name) {
            "DB2" { "#10b981"; break }      # Green
            "PowerShell" { "#3b82f6"; break } # Blue
            "COBOL" { "#f59e0b"; break }    # Amber
            "REXX" { "#8b5cf6"; break }     # Purple
            "WindowsCmd" { "#6b7280"; break } # Gray
            default { "#6b7280" }
        }
        
        # Get unique process names
        $uniqueProcesses = $group.Group | Select-Object -ExpandProperty Name -Unique
        
        foreach ($processName in $uniqueProcesses) {
            $nodeCounter++
            $nodeId = "proc$nodeCounter"
            $safeName = $processName -replace '["\n\r]', ' ' -replace '\s+', ' '
            if ($safeName.Length -gt 50) {
                $safeName = $safeName.Substring(0, 47) + "..."
            }
            
            $mmdContent += "    $scriptNode --`"$($group.Name)`"--> $nodeId$typeShape`"$safeName`"$typeShapeEnd"
            $mmdContent += "    style $nodeId stroke:$typeColor,stroke-width:2px"
        }
    }
    
    return ($mmdContent -join "`n")
}

function Get-BatMmdExecutionPathDiagram {
    param($SrcRootFolder, $BaseFileName, $TmpRootFolder)
    $programInUse = $false
    $returnArray = @()
    $returnArray2 = @()
    $programInUse, $returnArray2 = IsExecutedFromAny -findpath $SrcRootFolder -includeFilter "*.ps1", "*.bat" -filename $BaseFileName -programInUse $programInUse -srcRootFolder $SrcRootFolder
    $returnArray += $returnArray2

    foreach ($item in $returnArray) {
        Write-BatMmd -MmdString $item
    }

    If (!$programInUse) {
        Write-LogMessage ("Program is never called from any other program or script: " + $BaseFileName) -Level INFO
    }
}

function Test-BatFunction {
    param($FunctionName)
    $isValidFunction = $false
    if (-not $FunctionName.StartsWith(":")) {
        return $isValidFunction
    }
    $functionTemp = $FunctionName.Replace(":", "").ToUpper().Trim()

    if ($script:batFunctions.Contains($functionTemp)) {
        $isValidFunction = $true
    }
    else {
        $isValidFunction = $false
    }
    return $isValidFunction
}

function Get-BatConcatValue($DecodeString) {
    if ($DecodeString.Contains("||")) {
        $temp1 = $DecodeString.Split("||")
        $returnString = ""
        foreach ($item in $temp1) {
            $item = Get-BatVariableValue($item)
            $returnString += $item
        }
    }
    else {
        $returnString = $DecodeString
    }
    return $returnString
}

function Get-BatQuoteValue($DecodeString) {
    if ($DecodeString.Contains("'")) {
        $temp1 = $DecodeString.Split("'")
        $returnString = ""
        foreach ($item in $temp1) {
            $item = Get-BatVariableValue($item)
            $returnString += $item
        }
    }
    else {
        $returnString = $DecodeString
    }
    return $returnString
}

function Get-BatSubstrValue($DecodeString) {
    if ($DecodeString.ToLower().Contains("substr")) {
        $returnString = $DecodeString
        $temp1 = $DecodeString.ToLower().Split("substr")
        $returnString = ""
        foreach ($item in $temp1) {
            if ($null -ne $item -and $item.Contains("(")) {
                $item = $item.Replace("(", "").Replace(")", "")
                $temp2 = $item.Split(",")[0]
                $item = $temp2
            }
            $returnString += $item
        }
    }
    else {
        $returnString = $DecodeString
    }
    return $returnString
}

function Get-BatVariableValue($DecodeString) {
    if ($DecodeString.length -gt 0) {
        $returnString = $DecodeString
        if ($script:batAssignmentsDict.ContainsKey($DecodeString.Trim())) {
            $returnString = $script:batAssignmentsDict[$DecodeString.Trim()].ToString()
            $returnString = Get-BatConcatValue($returnString)
        }
    }
    else {
        $returnString = $DecodeString
    }
    return $returnString
}

function New-BatNodes {
    param ($FunctionCode, $FileContent, $FunctionName, $FdHashtable, $CurrentLoopCounter)

    if ($FunctionName -eq "") {
        $FunctionName = "__MAIN__"
    }
    $skipLine = $false

    $uniqueCounter = 0
    foreach ($lineObject in $FunctionCode) {
        if ($uniqueCounter -eq 0) {
            $link = "https://Dedge.visualstudio.com/Dedge/_search?action=contents&text=" + $script:batBaseFileName.ToLower() + "&type=code&filters=ProjectFilters%7BDedge%7D"
            $statement = "click " + $FunctionName.ToLower() + " " + '"' + $link + '"' + " " + '"' + $FunctionName.ToLower() + '"' + " _blank"
            Write-BatMmd -MmdString $statement
            $statement = "style " + $FunctionName.ToLower() + " stroke:dark-blue,stroke-width:3px"
            Write-BatMmd -MmdString $statement
        }
        $uniqueCounter += 1
        $line = $lineObject.Line.Trim()

        if ($line.Length -eq 0) {
            continue
        }
        $skipList = @()
        foreach ($item in $skipList) {
            if ($line.ToLower().Contains($item)) {
                $skipLine = $true
                break
            }
        }

        if ($skipLine) {
            $skipLine = $false
            continue
        }
        if ($line.Trim().ToLower().EndsWith(":") -and $line.Trim().Length -eq 2) {
            $statement = $FunctionName.Trim().ToLower() + " --windows command-->" + $FunctionName.Trim().ToLower() + "_changedrive" + $uniqueCounter.ToString() + "(" + '"' + "change drive`n" + $line.Trim().ToUpper() + '"' + ")"
            Write-BatMmd -MmdString $statement
            Continue
        }

        if ($line.ToLower().StartsWith("db2 ") -or $line.ToLower().StartsWith("db2cmd ") -or $line.ToLower().StartsWith("start db2cmd ")) {
            $temp1 = $line.ToLower().Replace("call ", "").Replace("start ", "").Trim()
            $temp1 = Get-BatQuoteValue($line)
            $temp1 = Get-BatConcatValue($temp1)

            $itemName = $FunctionName.Trim().ToLower() + "_db2" + $uniqueCounter.ToString()
            $temp1 = $temp1.Replace('"', "").Replace("'", "").Trim()
            $temp3 = $temp1.Split(" ")
            $temp1 = $temp3[0] + "`n" + $temp1.Replace($temp3[0], "").Trim()

            # Try to extract SQL statement from db2 command
            $sqlOperation, $sqlTableNames, $cursorName, $cursorForUpdate, $updateFields = FindSqlStatementInDb2Command -CommandLine $line
            
            if ($sqlOperation -and $sqlTableNames.Count -gt 0) {
                # SQL statement detected - create SQL table nodes (like COBOL does)
                $supportedSqlExpressions = @("SELECT", "UPDATE", "INSERT", "DELETE", "FETCH", "CALL")
                if ($supportedSqlExpressions -contains $sqlOperation) {
                    $tableCounter = 0
                    foreach ($sqlTable in $sqlTableNames) {
                        $script:sqlTableArray += $sqlTable
                        $tableCounter += 1
                        $statementText = $sqlOperation.ToLower()
                        
                        # Handle cursor logic (similar to COBOL)
                        if ($cursorName -and $cursorName.Length -gt 0) {
                            if ($tableCounter -eq 1) {
                                $statementText = "Cursor " + $cursorName.ToUpper() + " select"
                                if ($cursorForUpdate) {
                                    $statementText = "Primary table for cursor " + $cursorName.ToUpper() + " select for update"
                                }
                            }
                            else {
                                $statementText = "Sub-select in cursor " + $cursorName.ToUpper()
                            }
                        }
                        else {
                            # Handle multiple tables in non-cursor statements
                            if ($tableCounter -gt 1) {
                                if ($sqlOperation -eq "UPDATE" -or $sqlOperation -eq "INSERT" -or $sqlOperation -eq "DELETE") {
                                    $statementText = "Sub-select related to " + $sqlTableNames[0].Trim()
                                }
                                if ($sqlOperation -eq "SELECT") {
                                    $statementText = "Join or Sub-select related to " + $sqlTableNames[0].Trim()
                                }
                            }
                            # Add field names for UPDATE statements (primary table only)
                            elseif ($sqlOperation -eq "UPDATE" -and $updateFields -and $updateFields.Count -gt 0) {
                                $fieldList = $updateFields -join ", "
                                $statementText = "update [$($fieldList)]"
                            }
                        }
                        
                        # Create SQL table node connection (same format as COBOL)
                        $statement = $FunctionName.Trim().ToLower() + '--"' + $statementText + '"-->sql_' + $sqlTable.Replace(".", "_").Trim() + "[(" + $sqlTable.Trim() + ")]"
                        Write-BatMmd -MmdString $statement
                    }
                    # Skip process node creation when SQL is detected
                    Continue
                }
            }
            
            # No SQL detected - treat as regular DB2 command (process node)
            $statement = $FunctionName.Trim().ToLower() + " --DB2 command-->" + $itemName + "(" + '"' + $temp1 + '"' + ")"
            Write-BatMmd -MmdString $statement
            
            # Track for process execution diagram
            Add-BatExternalProcess -Type "DB2" -Name $temp3[0] -Details ($temp1 -replace "`n", " ")
            Continue
        }

        # OPTIMIZED: Cache lowercased line and use regex for command detection
        $lineLower = $line.ToLower()
        if ($lineLower -match '^(copy|pause|reg|regedit|notepad|del|path|set|start|net|ren|xcopy|adfind|postiecgi|postie|robocopy) ') {
            $temp1 = Get-BatQuoteValue($line)
            $temp1 = Get-BatConcatValue($temp1)

            $temp3 = $temp1.Split(" ")
            $temp2 = $temp3[0] + "`n" + $temp1.Replace($temp3[0], "").Trim()
            $temp2 = $temp2.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("\\", "`n \\").Replace("C:\", "`n C:\").Replace(">>", "`n >>").Replace("N:\", "`n N:\")

            $statement = $FunctionName.Trim().ToLower() + " --windows command-->" + $FunctionName.Trim().ToLower() + "_copy" + $uniqueCounter.ToString() + "(" + '"' + $temp2.replace("'", "").replace('"', "") + '"' + ")"
            Write-BatMmd -MmdString $statement
            Continue
        }
        if ($line.ToLower().StartsWith("powershell.exe ") -or $line.ToLower().StartsWith("pwsh.exe ") -or $line.ToLower().StartsWith("@powershell ") -or $line.ToLower().StartsWith("psexec ")) {
            $temp1 = Get-BatQuoteValue($line)
            $temp1 = Get-BatConcatValue($temp1)

            $temp3 = $temp1.Split(" ")
            $temp2 = $temp3[0] + "`n" + $temp1.Replace($temp3[0], "").Trim()
            $temp2 = $temp2.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("\\", "`n \\").Replace("C:\", "`n C:\").Replace(">>", "`n >>").Replace("N:\", "`n N:\")

            $pos = $temp1.ToLower().IndexOf(".ps1")
            $params = $temp1.Substring($pos + 4).Trim()
            if ($params) {
                $temp4 = $line.Trim().Replace($params, "").Trim()
            }
            else {
                $temp4 = $line.Trim()
            }
            $pos = $temp4.LastIndexOf("\")
            if ($pos -eq -1) {
                $pos = $temp4.LastIndexOf(" ")
            }
            $powershellScriptName = $temp4.Substring($pos + 1).Trim()
            $params = $params.Replace("'", "").Replace('"', "")

            $powershellScriptName = $powershellScriptName.replace("'", "").replace('"', "")

            if ($params) {
                $powershellScriptName += "`n" + $params
            }
            $powershellScriptNameOrig = $powershellScriptName
            $powershellScriptName = $powershellScriptName.replace("'", "").replace('"', "")

            $statement = $FunctionName.Trim().ToLower() + " --powershell command-->" + $powershellScriptNameOrig + "(" + '"' + $powershellScriptName + '"' + ")"
            Write-BatMmd -MmdString $statement

            $link = "./" + $powershellScriptName + ".html"
            $statement = "click " + $powershellScriptNameOrig + " " + '"' + $link + '"' + " " + '"' + $powershellScriptNameOrig + '"' + " _blank"
            Write-BatMmd -MmdString $statement
            $statement = "style " + $powershellScriptNameOrig + " stroke:dark-blue,stroke-width:4px"
            Write-BatMmd -MmdString $statement

            # Track for process execution diagram
            Add-BatExternalProcess -Type "PowerShell" -Name $powershellScriptName -Details ""
            Continue
        }
        if ($line.ToLower().StartsWith("run ")) {
            $temp1 = Get-BatQuoteValue($line)
            $temp1 = Get-BatConcatValue($temp1)
            $temp1 = $temp1.ToUpper().Trim().Replace("RUN", "").Trim().Replace("  ", " ").Replace("'", "").Replace('"', "")

            $temp2 = $temp1.Split(" ")
            $tempProgramName = $temp2[0].ToLower().Trim() + ".cbl"

            if ($temp2.Length -gt 1) {
                $temp1 = '"' + $tempProgramName + "`n" + "parameters: " + $temp1.Replace($temp2[0], "").Trim() + '"'
            }
            else {
                $temp1 = '"' + $tempProgramName + '"'
            }
            $script:htmlCallListCbl += $tempProgramName
            $statement = $FunctionName.Trim().ToLower() + " --start cobol program-->" + $FunctionName.Trim().ToLower() + "_run" + $uniqueCounter.ToString() + "[[" + $temp1 + "]]"
            Write-BatMmd -MmdString $statement
            $itemName = $FunctionName.Trim().ToLower() + "_run" + $uniqueCounter.ToString()

            $link = "./" + $tempProgramName + ".html"
            $statement = "click " + $itemName + " " + '"' + $link + '"' + " " + '"' + $itemName + '"' + " _blank"
            Write-BatMmd -MmdString $statement
            $statement = "style " + $itemName + " stroke:dark-blue,stroke-width:4px"
            Write-BatMmd -MmdString $statement
            
            # Track for process execution diagram
            Add-BatExternalProcess -Type "COBOL" -Name $tempProgramName -Details ""
            Continue
        }

        if ($line.ToLower().Contains("rexx ")) {
            $temp1 = $line.ToLower().Replace("call ", "").Replace("rexx ", "").Trim()
            $temp1 = Get-BatQuoteValue($temp1)
            $temp1 = Get-BatConcatValue($temp1)

            $itemName = $FunctionName.Trim().ToLower() + "_rexxrun" + $uniqueCounter.ToString()
            $rexFilename = $temp1.Trim().ToLower() + ".rex"
            if ($rexFilename.Contains(" ")) {
                $rexFilename = $temp1.Trim().ToLower().Split(" ")[0] + ".rex"
            }
            $script:htmlCallList += $rexFilename
            $statement = $FunctionName.Trim().ToLower() + " --start rexx script-->" + $itemName + "[[" + $rexFilename + "]]"
            Write-BatMmd -MmdString $statement

            $link = "./" + $rexFilename + ".html"
            $statement = "click " + $itemName + " " + '"' + $link + '"' + " " + '"' + $itemName + '"' + " _blank"
            Write-BatMmd -MmdString $statement
            $statement = "style " + $itemName + " stroke:dark-blue,stroke-width:4px"
            Write-BatMmd -MmdString $statement
            
            # Track for process execution diagram
            Add-BatExternalProcess -Type "REXX" -Name $rexFilename -Details ""
            Continue
        }

        if ($line.ToLower().contains("goto ")) {
            $pos = $line.ToLower().IndexOf("goto ")
            $temp1 = $line.ToLower().Substring($pos + 5).Trim()
            $temp1 = Get-BatQuoteValue($temp1)
            $temp1 = Get-BatConcatValue($temp1)
            $temp2 = $temp1.Split(" ")

            if ($temp2[0] -eq "%next%") {
                $counter = 0
                foreach ($item in $script:batFunctions) {
                    $counter += 1
                    if ($item.Contains($FunctionName.Trim().ToUpper().Replace(":", ""))) {
                        break
                    }
                }
                $tempFunctionName = $script:batFunctions[$counter].ToLower().Trim()
            }
            else {
                $tempFunctionName = $temp2[0].ToLower().Trim()
            }

            $params = ""
            if ($temp2.Length -gt 1) {
                $params = '"' + "`nparameters: " + $temp1.Replace($temp2[1], "").Trim() + '"'
            }

            $options = "goto function"

            $statement = $FunctionName.Trim().ToLower() + " --" + $options + "-->" + $tempFunctionName + "[[" + '"' + $tempFunctionName + $params + '"' + "]]"
            Write-BatMmd -MmdString $statement

            Continue
        }

        if ($line.ToLower().StartsWith("call ")) {
            $temp1 = Get-BatQuoteValue($line)
            $temp1 = Get-BatConcatValue($temp1)
            $temp2 = $temp1.Split(" ")
            $tempProgramName = $temp2[1].ToLower().Trim()

            $functionTemp = $script:batFunctions | Select-String -Pattern $tempProgramName -Quiet

            if ($temp2.Length -gt 2) {
                $temp1 = '"' + $tempProgramName + "`n" + "parameters: " + $temp1.Replace($temp2[2], "").Trim() + '"'
            }
            else {
                $temp1 = '"' + $tempProgramName + '"'
            }

            $options = "call windows batch script"
            $itemName = $FunctionName.Trim().ToLower() + "_call" + $uniqueCounter.ToString()

            $script:htmlCallList += $tempProgramName

            $statement = $FunctionName.Trim().ToLower() + " --" + $options + "-->" + $itemName + "[[" + $temp1 + "]]"
            Write-BatMmd -MmdString $statement

            if ($temp1.Contains(".bat")) {
                $link = "./" + $tempProgramName + ".html"
                $statement = "click " + $itemName + " " + '"' + $link + '"' + " " + '"' + $itemName + '"' + " _blank"
                Write-BatMmd -MmdString $statement
                $statement = "style " + $itemName + " stroke:dark-blue,stroke-width:4px"
                Write-BatMmd -MmdString $statement
            }
            Continue
        }
        if ($line.ToLower().contains("dir ")) {
            $temp1 = Get-BatQuoteValue($line)
            $temp1 = Get-BatConcatValue($temp1)

            $temp3 = $temp1.Split(" ")
            $temp2 = $temp3[0] + "`n" + $temp1.Replace($temp3[0], "").Trim()

            if ($null -eq $temp2) {
                $temp2 = $temp1
            }

            $statement = $FunctionName.Trim().ToLower() + " --windows command-->" + $FunctionName.Trim().ToLower() + "_ren" + $uniqueCounter.ToString() + "(" + '"' + $temp2.replace("'", "").replace('"', "") + '"' + ")"
            Write-BatMmd -MmdString $statement
            Continue
        }

        if ($line.ToLower().StartsWith("echo") -or $line.ToLower().StartsWith("@echo")) {
            $temp1 = Get-BatQuoteValue($line)
            $temp1 = Get-BatConcatValue($temp1)

            $temp3 = $temp1.Split(" ")
            $temp2 = $temp3[0] + "`n" + $temp1.Replace($temp3[0], "").Trim()

            if ($null -eq $temp2) {
                $temp2 = $temp1
            }

            $statement = $FunctionName.Trim().ToLower() + " --windows command-->" + $FunctionName.Trim().ToLower() + "_echo" + $uniqueCounter.ToString() + "(" + '"' + $temp2.Replace("'", "").Replace('"', "") + '"' + ")"
            Write-BatMmd -MmdString $statement
            Continue
        }

        if ($script:batFunctions.Contains($line)) {
            $statement = $FunctionName.Trim().ToLower() + " --call--> " + $line.ToLower().Replace(" ", "_") + "(" + '"' + $line.ToLower() + + '"' + ")"
            Write-BatMmd -MmdString $statement
            Continue
        }

        if ($line.ToLower().contains("sqlexec")) {
            $temp1 = Get-BatQuoteValue($line)
            $temp1 = Get-BatConcatValue($temp1)

            $itemName = $FunctionName.Trim().ToLower() + "_sqlexec" + $uniqueCounter.ToString()
            $temp1 = $temp1.Trim().ToLower().Replace("sqlexec", "'").Trim()
            
            # Try to extract SQL statement from sqlexec command
            $sqlOperation, $sqlTableNames, $cursorName, $cursorForUpdate, $updateFields = FindSqlStatementInDb2Command -CommandLine $line
            
            if ($sqlOperation -and $sqlTableNames.Count -gt 0) {
                # SQL statement detected - create SQL table nodes (like COBOL does)
                $supportedSqlExpressions = @("SELECT", "UPDATE", "INSERT", "DELETE", "FETCH", "CALL")
                if ($supportedSqlExpressions -contains $sqlOperation) {
                    $tableCounter = 0
                    foreach ($sqlTable in $sqlTableNames) {
                        $script:sqlTableArray += $sqlTable
                        $tableCounter += 1
                        $statementText = $sqlOperation.ToLower()
                        
                        # Handle cursor logic (similar to COBOL)
                        if ($cursorName -and $cursorName.Length -gt 0) {
                            if ($tableCounter -eq 1) {
                                $statementText = "Cursor " + $cursorName.ToUpper() + " select"
                                if ($cursorForUpdate) {
                                    $statementText = "Primary table for cursor " + $cursorName.ToUpper() + " select for update"
                                }
                            }
                            else {
                                $statementText = "Sub-select in cursor " + $cursorName.ToUpper()
                            }
                        }
                        else {
                            # Handle multiple tables in non-cursor statements
                            if ($tableCounter -gt 1) {
                                if ($sqlOperation -eq "UPDATE" -or $sqlOperation -eq "INSERT" -or $sqlOperation -eq "DELETE") {
                                    $statementText = "Sub-select related to " + $sqlTableNames[0].Trim()
                                }
                                if ($sqlOperation -eq "SELECT") {
                                    $statementText = "Join or Sub-select related to " + $sqlTableNames[0].Trim()
                                }
                            }
                            # Add field names for UPDATE statements (primary table only)
                            elseif ($sqlOperation -eq "UPDATE" -and $updateFields -and $updateFields.Count -gt 0) {
                                $fieldList = $updateFields -join ", "
                                $statementText = "update [$($fieldList)]"
                            }
                        }
                        
                        # Create SQL table node connection (same format as COBOL)
                        $statement = $FunctionName.Trim().ToLower() + '--"' + $statementText + '"-->sql_' + $sqlTable.Replace(".", "_").Trim() + "[(" + $sqlTable.Trim() + ")]"
                        Write-BatMmd -MmdString $statement
                    }
                    # Skip process node creation when SQL is detected
                    Continue
                }
            }
            
            # No SQL detected - treat as regular SqlExec command (process node)
            $statement = $FunctionName.Trim().ToLower() + " --DB2 sqlExec command-->" + $itemName + "(" + '"' + $temp1 + '"' + ")"
            Write-BatMmd -MmdString $statement
            Continue
        }

        if (($line.ToLower().Contains(":\") -or $line.ToLower().Contains("\\")) -and $line.ToLower().Contains(".bat")) {
            $itemName = $FunctionName.Trim().ToLower() + "runbatch_" + $uniqueCounter.ToString()
            $statement = $FunctionName.Trim().ToLower() + " --" + '"' + "start windows batch script" + '"' + "-->" + $itemName + "[[" + '"' + $line.Trim() + '"' + "]]"
            Write-BatMmd -MmdString $statement

            $temp = $line.ToLower().Split("\")
            $temp1 = $temp[$temp.Length - 1]

            $link = "./" + $temp1 + ".html"
            $statement = "click " + $itemName + " " + '"' + $link + '"' + " " + '"' + $itemName + '"' + " _blank"
            Write-BatMmd -MmdString $statement
            $statement = "style " + $itemName + " stroke:dark-blue,stroke-width:4px"
            Write-BatMmd -MmdString $statement
            Continue
        }
        
        if (-not ($line.StartsWith(":") -or $line.ToLower().StartsWith("rem ") -or $line.ToLower().StartsWith("runc ") -or $line.ToLower().Contains("zip "))) {
            Write-LogMessage ("Unhandled line in module: " + $script:batBaseFileName + ", in function: " + $FunctionName + ", at line: " + $line) -Level WARN
        }
    }
}

function Write-BatMmd {
    param ($MmdString)

    if ($null -eq $MmdString) {
        return
    }

    if ($MmdString.Trim().Length -eq 0) {
        return
    }

    try {
        # OPTIMIZED: Replace literal newlines with <br/> for Mermaid compatibility
        $MmdString = $MmdString -replace "`n", "<br/>" -replace "`r", ""
        $MmdString = $MmdString.Replace(":__MAIN__", "main").Replace(":__main__", "main")
        if ($MmdString.Substring(0, 1) -eq ":") {
            $MmdString = "_" + $MmdString.Substring(1)
        }
        if ($MmdString.Contains(">:")) {
            $MmdString = $MmdString.Replace(">:", ">_")
        }
        if ($MmdString.Contains("click :")) {
            $MmdString = $MmdString.Replace("click :", "click _")
        }
        if ($MmdString.Contains("style :")) {
            $MmdString = $MmdString.Replace("style :", "style _")
        }
    }
    catch {
        # Silently continue on error
    }

    $MmdString = $MmdString.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")

    WriteMmdCommon -mmdString $MmdString
}

function Get-BatFunctionCode {
    param ($Array, [string]$FunctionName)

    $foundStart = $false
    try {
        $FunctionName = $FunctionName.ToUpper()
    }
    catch {
        return $null
    }

    $extractedElements = @()

    $lineNumber = 0
    foreach ($objectItem in $Array) {
        $item = $objectItem
        $lineNumber += 1

        if (-not $foundStart -and ($item.ToUpper().Trim().StartsWith($FunctionName.ToUpper()) -or $FunctionName -eq ":__MAIN__")) {
            $foundStart = $true
            $extractedElements = @()
        }
        elseif ($foundStart) {
            if (Test-BatFunction -FunctionName $item) {
                $foundStart = $false
                break
            }
            else {
                $extractedElements += $item
            }
        }
    }
    return $extractedElements
}

function Get-BatMetaData {
    param ($TmpRootFolder, $BaseFileName, $OutputFolder, $CompleteFileContent, $InputDbFileFolder, $ClientSideRender)
    
    try {
        $title = "No description found"
        foreach ($line in $CompleteFileContent) {
            if ($line -match "[A-Za-z]" -and $line.StartsWith("#")) {
                $title = $line.Replace("#", "").Trim()
                break
            }
        }
        $startCommentFound = $false
        $commentArray = @()
        foreach ($line in $CompleteFileContent) {
            if (($line -match "(19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])" -or $line -match "(0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}" -or $line -match "(19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])") `
                    -and $line.Contains("#")) {
                $startCommentFound = $true
            }
            if ($startCommentFound -and $line.Contains("*/")) {
                $commentArray += $line.Replace("#", "").Trim()
            }

            if ($startCommentFound -and -not $line.Contains("#")) {
                break
            }
        }
        $commentArray2 = @()
        $newComment = ""
        $htmlCreatedDateTime = ""
        foreach ($item in $commentArray) {
            if ($item.Trim().Contains("-----------") -or $item.Trim().Contains("**********") -or $item.Trim().Contains("==========")) {
                break
            }

            if ($item -match "(19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])" -or $item -match "(0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}" -or $item -match "(19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])") {
                if ($newComment.Length -gt 0) {
                    $newComment = $newComment.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
                    $temp = $newComment.Split(" ")
                    if ($htmlCreatedDateTime.Length -eq 0) {
                        $htmlCreatedDateTime = $temp[0]
                    }
                    $tempComment = "<tr><td>" + $temp[0] + "</td><td>" + $temp[1] + "</td><td>"
                    $temp2 = $newComment.Replace($temp[0] + " " + $temp[1], "").Trim()
                    $newComment = $tempComment + $temp2 + "</td></tr>"
                    $commentArray2 += $newComment.Trim()
                }
                $newComment = $item
            }
            else {
                $newComment += " " + $item.Trim()
            }
        }

        if ($newComment.Length -gt 0) {
            $newComment = $newComment.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
            $temp = $newComment.Split(" ")
            $tempComment = "<tr><td>" + $temp[0] + "</td><td>" + $temp[1] + "</td><td>"
            $temp2 = $newComment.Replace($temp[0] + " " + $temp[1], "").Trim()
            $newComment = $tempComment + $temp2 + "</td></tr>"
            $commentArray2 += $newComment.Trim()
        }
        $commentArray = $commentArray2

        $csvModulArray = Import-Csv ($InputDbFileFolder + "\modul.csv") -Header system, delsystem, modul, tekst, modultype, benytter_sql, benytter_ds, fra_dato, fra_kl, antall_linjer, lengde, filenavn -Delimiter ';'
        $cblArray = @()
        foreach ($item in $script:htmlCallListCbl) {
            $descArray = $csvModulArray | Where-Object { $_.modul.Contains($item.Replace(".cbl", "").ToUpper()) }
            if ($descArray.Length -eq 0) {
                $cblSystem = "N/A"
                $cblDesc = "N/A"
                $cblType = "N/A"
            }
            else {
                $temp = $descArray[0]
                $cblSystem = $temp.delsystem.Trim()
                $cblDesc = $temp.tekst.Trim()
                $cblType = $temp.modultype.Trim()

                if ($cblType -eq "B") { $cblType = "B - Batchprogram" }
                elseif ($cblType -eq "H") { $cblType = "H - Main user interface" }
                elseif ($cblType -eq "S") { $cblType = "S - Webservice" }
                elseif ($cblType -eq "V") { $cblType = "V - Validation module for user interface" }
                elseif ($cblType -eq "A") { $cblType = "A - Common module" }
                elseif ($cblType -eq "F") { $cblType = "F - Search module for user interface" }
            }

            $link = "<a href=" + '"' + "./" + $item.Trim() + ".html" + '"' + ">" + $item.Trim() + "</a>"
            $tempComment = "<tr><td>" + $link + "</td><td>" + $cblDesc + "</td><td>" + $cblType + "</td><td>" + $cblSystem + "</td></tr>"

            $cblArray += $tempComment
        }

        $scriptArray = @()
        $script:htmlCallList = $script:htmlCallList | Sort-Object -Unique
        foreach ($item in $script:htmlCallList) {
            $link = "<a href=" + '"' + "./" + $item.Trim() + ".html" + '"' + ">" + $item.Trim() + "</a>"
            $tempComment = "<tr><td>" + $link + "</td></tr>"
            $scriptArray += $tempComment
        }

        $htmlDesc = $title.Trim()
        $htmlType = "Windows Batch Script"
        $temp = $CompleteFileContent | Select-String -Pattern @("db2 ")
        $htmlUseSql = ""
        if ($temp.Length -gt 0) {
            $htmlUseSql = "checked"
        }
        $temp = $CompleteFileContent | Select-String -Pattern @("rexx")
        $htmlUseRex = ""
        if ($temp.Length -gt 0) {
            $htmlUseRex = "checked"
        }
    }
    catch {
        $errorMessage = $_.Exception
        Write-Host "En feil oppstod: $errorMessage"
        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
        Write-LogMessage $errorMessage -Level ERROR
        $script:errorOccurred = $true
    }
    finally {
        $htmlFilename = $OutputFolder + "\" + $BaseFileName + ".html"
        
        # Use template from OutputFolder\_templates (copied at startup by AutoDocBatchRunner)
        $templatePath = Join-Path $OutputFolder "_templates"
        $mmdTemplateFilename = Join-Path $templatePath "batmmdtemplate.html"

        $myDescription = "AutoDoc Flowchart - Windows Batch Script - " + $BaseFileName.ToLower()

        $templateContent = Get-Content -Path $mmdTemplateFilename -Raw
        
        # Apply shared CSS and common URL replacements
        $doc = Set-AutodocTemplate -Template $templateContent -OutputFolder $OutputFolder
        
        # Page-specific replacements
        $doc = $doc.Replace("[title]", $myDescription)
        $doc = $doc.Replace("[desc]", $title)
        $doc = $doc.Replace("[generated]", (Get-Date).ToString())
        $doc = $doc.Replace("[type]", $htmlType)
        $doc = $doc.Replace("[usesql]", $htmlUseSql)
        $doc = $doc.Replace("[userex]", $htmlUseRex)
        $doc = $doc.Replace("[created]", $htmlCreatedDateTime)
        $doc = $doc.Replace("[changelog]", $commentArray)
        $doc = $doc.Replace("[calllist]", $scriptArray)
        $doc = $doc.Replace("[calllistcbl]", $cblArray)
        $doc = $doc.Replace("[diagram]", "./" + $BaseFileName + ".flow.svg")
        $doc = $doc.Replace("[sourcefile]", $BaseFileName.ToLower())
        
        # For client-side rendering, embed MMD content directly
        if ($ClientSideRender) {
            $flowMmdContent = ""
            if (Test-Path -Path $script:mmdFilename -PathType Leaf) {
                $flowMmdContent = Get-Content -Path $script:mmdFilename -Raw -ErrorAction SilentlyContinue
            }
            $doc = $doc.Replace("[flowmmd_content]", $flowMmdContent)
            $doc = $doc.Replace("[sequencemmd_content]", "")
            
            # Generate process execution diagram
            $processMmdContent = New-BatProcessExecutionDiagram -ScriptName $BaseFileName
            $doc = $doc.Replace("[processmmd_content]", $processMmdContent)
        }
        else {
            # Non-client-side rendering - still need placeholder replacement
            $doc = $doc.Replace("[processmmd_content]", "flowchart LR`n    noprocess[Process diagram requires client-side rendering]")
        }
        
        Set-Content -Path $htmlFilename -Value $doc
    }
}

#endregion

function Start-BatParse {
    <#
    .SYNOPSIS
        Main entry point for Windows Batch file parsing.
    
    .DESCRIPTION
        Parses Windows Batch files and generates AutoDoc HTML documentation
        with Mermaid flowchart diagrams.
    
    .PARAMETER SourceFile
        Path to the .bat file to parse.
    
    .PARAMETER Show
        If true, opens the generated HTML file after creation.
    
    .PARAMETER OutputFolder
        Output folder for generated files.
    
    .PARAMETER CleanUp
        If true, cleans up temporary files after processing.
    
    .PARAMETER TmpRootFolder
        Root folder for temporary files.
    
    .PARAMETER SrcRootFolder
        Root folder for source files.
    
    .PARAMETER ClientSideRender
        Skip SVG generation and use client-side Mermaid.js rendering.
    
    .PARAMETER SaveMmdFiles
        Save Mermaid diagram source files (.mmd) alongside the HTML output.
    
    .OUTPUTS
        Path to the generated HTML file, or $null on error.
    
    .EXAMPLE
        Start-BatParse -SourceFile "C:\scripts\myscript.bat" -OutputFolder "C:\output"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [bool]$Show = $false,
        [string]$OutputFolder = "$env:OptPath\Webs\AutoDoc",
        [bool]$CleanUp = $true,
        [string]$TmpRootFolder = "$env:OptPath\data\AutoDoc\tmp",
        [string]$SrcRootFolder = "$env:OptPath\data\AutoDoc\src",
        [switch]$ClientSideRender,
        [switch]$SaveMmdFiles
    )
    
    $script:sequenceNumber = 0
    $script:batBaseFileName = [System.IO.Path]::GetFileName($SourceFile)
    $global:baseFileNameTemp = $script:batBaseFileName
    
    # Sanitize filename for Mermaid node IDs (must start with letter or underscore)
    $script:batSafeFileName = $script:batBaseFileName
    if ($script:batSafeFileName -match '^[^a-zA-Z_]') {
        $script:batSafeFileName = "_" + $script:batSafeFileName
    }
    $script:batSafeFileName = $script:batSafeFileName -replace '[^a-zA-Z0-9_]', '_'
    
    # Initialize external process tracking
    $script:externalProcesses = @()
    
    Write-LogMessage ("Starting parsing of filename:" + $SourceFile) -Level INFO
    
    # Validate filename
    if ($script:batBaseFileName.Contains(" ")) {
        Write-LogMessage ("Filename is not valid. Contains spaces:" + $script:batBaseFileName) -Level ERROR
        return $null
    }
    
    if (-not $script:batBaseFileName.ToLower().Contains(".bat")) {
        Write-LogMessage ("Filetype is not valid for parsing of Windows Batch script (.bat):" + $script:batBaseFileName) -Level ERROR
        return $null
    }
    
    $startTime = Get-Date
    $script:logFolder = $OutputFolder
    $script:mmdFilename = $OutputFolder + "\" + $script:batBaseFileName + ".flow.mmd"
    $global:mmdFilename = $script:mmdFilename
    $script:debugFilename = $OutputFolder + "\" + $script:batBaseFileName + ".debug"
    $htmlFilename = $OutputFolder + "\" + $script:batBaseFileName + ".html"
    $script:errorOccurred = $false
    
    $script:sqlTableArray = @()
    
    $inputDbFileFolder = $TmpRootFolder + "\cobdok"
    $global:duplicateLineCheck = ""
    
    Write-LogMessage ("Started for :" + $script:batBaseFileName) -Level INFO
    
    # Initialize MMD file
    $mmdHeader = @"
%%{ init: { 'flowchart': { 'curve': 'basis' } } }%%
flowchart LR
"@
    Set-Content -Path $script:mmdFilename -Value $mmdHeader -Force
    
    $programName = [System.IO.Path]::GetFileName($SourceFile.ToLower())
    # Create a safe version for Mermaid node IDs (must start with letter or underscore)
    $safeNodeId = $programName -replace '[^a-zA-Z0-9_]', '_'
    if ($safeNodeId -match '^[0-9]') {
        $safeNodeId = "_" + $safeNodeId
    }
    
    if (Test-Path -Path $SourceFile -PathType Leaf) {
        $fileContentOriginal = Get-Content $SourceFile -Encoding ([System.Text.Encoding]::GetEncoding(1252))
        $completeFileContent = $fileContentOriginal
        $test = $fileContentOriginal -join "¤"
        
        # Remove content between /* and */
        $pattern = "/\*.*?\*/"
        $test = $test -replace $pattern, ""
        $fileContentOriginal = $test.Split("¤")
    }
    else {
        Write-LogMessage ("File not found:" + $SourceFile) -Level ERROR
        return $null
    }
    
    $fileContent = @()
    $fileContent = $fileContentOriginal
    
    # Extract all relevant code content
    $workContent2 = @()
    $workContent = @()
    $workContent2 = $fileContentOriginal | Select-String -Pattern @("^:.*", "CALL ", "DEL ", "RUN ", "DIR ", "REXX ", "DB2 ", "COPY ", "XCOPY ", "REN ", "ADFIND ", "SET ", "GOTO ", "ECHO ", ".PS1", "PWSH", "PSEXEC")
    
    # Extract the first match (if any)
    $obj = New-Object PSObject
    if ($workContent2.Count -gt 0) {
        $obj | Add-Member -Type NoteProperty -Name "LineNumber" -Value 1
        $obj | Add-Member -Type NoteProperty -Name "Line" -Value (":__MAIN__")
        $obj | Add-Member -Type NoteProperty -Name "Pattern" -Value "^.*:"
        $workContent += $obj
    }
    $workContent += $workContent2
    
    # Create a list of all functions
    $script:batFunctions = @()
    $functionsList = @()
    if ($workContent.Count -gt 0) {
        $functionsList += $obj.Line.ToUpper().Replace(":", "").Trim()
    }
    $functionsList += $fileContentOriginal | Where-Object { $_ -match "^.*:" } | ForEach-Object { $_.Trim().Replace(":", "").ToUpper() }
    $script:batFunctions += $functionsList
    
    # Create a dictionary of all assigned variables
    $assignments = $fileContentOriginal | Where-Object { $_ -match "=" -and $_ -notmatch "if" }
    $script:batAssignmentsDict = @{}
    foreach ($line in $assignments) {
        $temp = $line -split "="
        $key = $temp[0].Trim().ToUpper()
        try {
            $script:batAssignmentsDict[$key] = $temp[1].Trim().Replace('"', "'")
        }
        catch { }
    }
    
    $fdHashtable = @{}
    $script:htmlCallListCbl = @()
    $script:htmlCallList = @()
    
    # Initialization
    $currentParticipant = ""
    $currentFunctionName = ""
    
    $loopCounter = 0
    $previousParticipant = ""
    $counter = 0
    $functionCodeExceptLoopCode = { }.Invoke()
    $counter = 0
    
    # Loop through all workContent
    foreach ($lineObject in $workContent) {
        $counter += 1
        $line = $lineObject.Line
        $lineNumber = $lineObject.LineNumber
        $counter += 1
        
        # Function handling
        $previousParticipant = $currentFunctionName
        
        # Check if line is a function
        if (Test-BatFunction -FunctionName $line) {
            if ($functionCodeExceptLoopCode.Count -gt 0) {
                $loopCounter = 0
                New-BatNodes -FunctionCode $functionCodeExceptLoopCode -FileContent $fileContent -FunctionName $previousParticipant -FdHashtable $fdHashtable -CurrentLoopCounter $loopCounter
            }
            
            $currentParticipant = $line.Trim()
            $currentFunctionName = $currentParticipant.Trim()
            $functionCode = Get-BatFunctionCode -Array $fileContentOriginal -FunctionName $currentParticipant
            
            $loopNodeContent = { }.Invoke()
            $loopCode = { }.Invoke()
            $functionCodeExceptLoopCode = { }.Invoke()
            
            # Handling program name to initial function
            if ($previousParticipant.Length -eq 0 -and $currentParticipant.Length -gt 0) {
                $statement = $safeNodeId + "[[" + $programName.Trim().ToLower() + "]]" + " --initiated-->" + $currentParticipant.Trim().ToLower() + "(" + $currentParticipant.Trim().ToLower() + ")"
                Write-BatMmd -MmdString $statement
                $statement = "style " + $safeNodeId + " stroke:red,stroke-width:4px"
                Write-BatMmd -MmdString $statement
                
                $link = "https://Dedge.visualstudio.com/Dedge/_search?action=contents&text=" + $script:batBaseFileName.ToLower() + "&type=code&filters=ProjectFilters%7BDedge%7D"
                $statement = "click " + $safeNodeId + " " + '"' + $link + '"' + " " + '"' + $programName.Trim().ToLower() + '"' + " _blank"
                Write-BatMmd -MmdString $statement
            }
        }
        
        if ($functionCode.Count -eq 0) {
            Continue
        }
        
        $skipLine = $false
        # Perform handling
        if ($line.trim().ToLower().contains("do ") -and ($line.trim().ToLower().contains(" while") -or $line.trim().ToLower().contains(" until"))) {
            $loopCounter += 1
            if ($loopCounter -gt 1) {
                $fromNode = $loopLevel[($loopCounter - 2)]
                $toNode = $loopLevel[($loopCounter - 2)] + $loopCounter + "((" + $loopLevel[($loopCounter - 2)] + $loopCounter + "))"
                $loopLevel.Add($currentParticipant + "-loop" + $loopCounter)
            }
            else {
                $fromNode = $currentParticipant
                $toNode = $currentParticipant + "-loop" + "((" + $currentParticipant + "-loop))"
                $loopLevel.Add($currentParticipant + "-loop")
            }
            $loopNodeContent.Add($toNode)
            $loopCode.Add("")
            $statement = $fromNode + "--" + '"' + "perform " + '"' + "-->" + $toNode
            
            Write-BatMmd -MmdString $statement
            $skipLine = $true
        }
        else {
            if ($line.trim().tolower().StartsWith(("end"))) {
                $workCode = $loopCode[$loopCounter - 1]
                New-BatNodes -FunctionCode $loopCode[$loopCounter - 1] -FileContent $fileContent -FunctionName ($loopLevel[$loopCounter - 1]) -FdHashtable $fdHashtable -CurrentLoopCounter $loopCounter
                
                $loopLevel.RemoveAt($loopCounter - 1)
                $loopNodeContent.RemoveAt($loopCounter - 1)
                $loopCode.RemoveAt($loopCounter - 1)
                $loopCounter -= 1
                $skipLine = $true
            }
        }
        # Accumulate lines
        if ($skipLine -eq $false) {
            if ($loopCounter -gt 0) {
                $workCode = { }.Invoke()
                if ($loopCode[$loopCounter - 1].Length -gt 0) {
                    $workCode = $loopCode[$loopCounter - 1]
                }
                $workCode.Add($lineObject)
                $loopCode[$loopCounter - 1] = $workCode
            }
            else {
                $functionCodeExceptLoopCode.Add($lineObject)
            }
        }
    }
    
    $loopCounter = 0
    
    # Handling program name to initial function
    if ($previousParticipant.Length -eq 0 -and $currentParticipant.Length -eq 0) {
        $currentParticipant = "__MAIN__"
        $statement = $safeNodeId + "[[" + $programName.Trim().ToLower() + "]]" + " --initiated-->" + $currentParticipant.Trim().ToLower() + "(" + $currentParticipant.Trim().ToLower() + ")"
        Write-BatMmd -MmdString $statement
        $statement = "style " + $safeNodeId + " stroke:red,stroke-width:4px"
        Write-BatMmd -MmdString $statement
        $link = "https://Dedge.visualstudio.com/Dedge/_search?action=contents&text=" + $script:batBaseFileName.ToLower() + "&type=code&filters=ProjectFilters%7BDedge%7D"
        
        $statement = "click " + $safeNodeId + " " + '"' + $link + '"' + " " + '"' + $programName.Trim().ToLower() + '"' + " _blank"
        Write-BatMmd -MmdString $statement
    }
    
    # Generate nodes for last function
    New-BatNodes -FunctionCode $functionCodeExceptLoopCode -FileContent $fileContent -FunctionName $currentFunctionName -FdHashtable $fdHashtable -CurrentLoopCounter $loopCounter
    
    # Generate execution path diagram
    Get-BatMmdExecutionPathDiagram -SrcRootFolder $SrcRootFolder -BaseFileName $script:batBaseFileName -TmpRootFolder $TmpRootFolder
    
    # Generate SVG file (skip when using client-side rendering)
    if ($script:batBaseFileName -ne "cobreplxen.bat" -and -not $ClientSideRender) {
        GenerateSvgFile -mmdFilename $script:mmdFilename
    }
    
    # Handle what to generate
    if (-not $script:errorOccurred) {
        Get-BatMetaData -TmpRootFolder $TmpRootFolder -OutputFolder $OutputFolder -BaseFileName $script:batBaseFileName -CompleteFileContent $completeFileContent -InputDbFileFolder $inputDbFileFolder -ClientSideRender:$ClientSideRender
        
        if ($Show) {
            & $htmlFilename
        }
    }
    
    $endTime = Get-Date
    $timeDiff = $endTime - $startTime
    
    # Save MMD files if requested
    if ($SaveMmdFiles -and (Test-Path -Path $script:mmdFilename -PathType Leaf)) {
        $mmdOutputPath = Join-Path $OutputFolder ($script:batBaseFileName + ".mmd")
        Copy-Item -Path $script:mmdFilename -Destination $mmdOutputPath -Force
        Write-LogMessage ("Saved MMD file: $mmdOutputPath") -Level INFO
    }
    
    # Log result
    # Only create error file if HTML was NOT generated (fatal error)
    # Non-fatal errors during parsing should not prevent successful completion if HTML was created
    $dummyFile = $OutputFolder + "\" + $script:batBaseFileName + ".err"
    $htmlFilename = $OutputFolder + "\" + $script:batBaseFileName + ".html"
    $htmlWasGenerated = Test-Path -Path $htmlFilename -PathType Leaf
    
    if ($htmlWasGenerated) {
        # HTML was generated - remove any error file and mark as success
        if (Test-Path -Path $dummyFile -PathType Leaf) {
            Remove-Item -Path $dummyFile -Force -ErrorAction SilentlyContinue
        }
        if ($script:errorOccurred) {
            Write-LogMessage ("Time elapsed: " + $timeDiff.Seconds.ToString()) -Level INFO
            Write-LogMessage ("Completed with warnings:" + $script:batBaseFileName) -Level WARN
        }
        else {
            Write-LogMessage ("Time elapsed: " + $timeDiff.Seconds.ToString()) -Level INFO
            Write-LogMessage ("Completed successfully:" + $script:batBaseFileName) -Level INFO
        }
        return $htmlFilename
    }
    else {
        # HTML was NOT generated - this is a true failure
        Write-LogMessage ("*******************************************************************************") -Level ERROR
        Write-LogMessage ("Failed - HTML not generated:" + $SourceFile) -Level ERROR
        Write-LogMessage ("*******************************************************************************") -Level ERROR
        "Error: HTML file was not generated for $($script:batBaseFileName)" | Set-Content -Path $dummyFile -Force
        return $null
    }
}
#endregion

#region ps1 Parse Functions

function Get-Ps1ExecutionPathDiagram {
    param($srcRootFolder, $baseFileName, $tmpRootFolder)
    $programInUse = $false

    $returnArray = @()
    $returnArray2 = @()
    $programInUse, $returnArray2 = IsExecutedFromAny -findpath ($srcRootFolder + "\DedgePsh\") -includeFilter "*.ps1", "*.bat" -filename $baseFileName -programInUse $programInUse -srcRootFolder $srcRootFolder
    $returnArray += $returnArray2

    foreach ($item in $returnArray) {
        Write-Ps1Mmd -mmdString $item
    }

    If (!$programInUse) {
        Write-LogMessage ("Program is never called from any other program or script: " + $baseFileName) -Level INFO
    }
}

function Test-Ps1Function {
    param(
        $functionName
    )
    $isValidFunction = $false
    if (-not $functionName.ToUpper().Contains("FUNCTION ")) {
        return $isValidFunction
    }
    $functionTemp = $functionName.ToUpper().Replace("{", " ").Replace("(", " (").ToUpper().Trim()
    $temp1 = $functionTemp.Split(" ")[1]

    if ($script:functionList.Contains($temp1)) {
        $isValidFunction = $true
        return $isValidFunction, $temp1
    }
    else {
        $isValidFunction = $false
        return $isValidFunction, $null
    }
}

function Get-ModuleFunctions {
    <#
    .SYNOPSIS
        Extracts function names from a PowerShell module file (.psm1).
    .DESCRIPTION
        Parses a .psm1 file to extract all function declarations.
        Handles both explicit exports (Export-ModuleMember) and implicit (all functions).
    .PARAMETER ModuleFilePath
        Path to the .psm1 file to parse.
    .OUTPUTS
        Array of function names (uppercase).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleFilePath
    )
    
    $functions = @()
    
    if (-not (Test-Path -Path $ModuleFilePath -PathType Leaf)) {
        Write-LogMessage "Module file not found: $ModuleFilePath" -Level WARN
        return $functions
    }
    
    try {
        $fileContent = Get-Content -Path $ModuleFilePath -ErrorAction Stop
        
        # Extract exported functions from Export-ModuleMember
        $exportedFunctions = @()
        foreach ($line in $fileContent) {
            if ($line -match 'Export-ModuleMember\s+-Function\s+(.+)$') {
                $exportList = $Matches[1]
                # Handle multiple functions separated by commas
                $exportedFunctions += $exportList -split ',' | ForEach-Object { $_.Trim().Trim("'").Trim('"') }
            }
            elseif ($line -match 'Export-ModuleMember\s+-Function\s+@\((.+)\)') {
                $exportList = $Matches[1]
                $exportedFunctions += $exportList -split ',' | ForEach-Object { $_.Trim().Trim("'").Trim('"') }
            }
        }
        
        # Extract all function declarations
        foreach ($line in $fileContent) {
            if ($line -match '^\s*function\s+([a-zA-Z0-9_-]+)') {
                $funcName = $Matches[1].ToUpper()
                if ($funcName.Length -gt 0) {
                    $functions += $funcName
                }
            }
        }
        
        # If Export-ModuleMember was found, filter to only exported functions
        if ($exportedFunctions.Count -gt 0) {
            $exportedFunctionsUpper = $exportedFunctions | ForEach-Object { $_.ToUpper() }
            $functions = $functions | Where-Object { $exportedFunctionsUpper -contains $_ }
        }
        
        # Remove duplicates
        $functions = $functions | Sort-Object -Unique
    }
    catch {
        Write-LogMessage "Error parsing module file $ModuleFilePath : $($_.Exception.Message)" -Level WARN
    }
    
    return $functions
}

function Resolve-ModuleName {
    <#
    .SYNOPSIS
        Extracts and normalizes module name from Import-Module statement.
    .DESCRIPTION
        Handles various Import-Module statement formats:
        - Import-Module GlobalFunctions
        - Import-Module -Name "GlobalFunctions"
        - Import-Module GlobalFunctions -Force
        - Import-Module "C:\path\Module.psm1"
    .PARAMETER ImportLine
        The Import-Module statement line to parse.
    .OUTPUTS
        Normalized module name (basename without extension).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImportLine
    )
    
    $moduleName = $null
    
    try {
        # Remove Import-Module prefix
        $line = $ImportLine.Trim().ToLower()
        $line = $line -replace '^import-module\s+', ''
        
        # Handle -Name parameter
        if ($line -match '-name\s+["'']?([^"'']+)["'']?') {
            $moduleName = $Matches[1].Trim()
        }
        # Handle path-based import (extract basename)
        elseif ($line -match '["'']?([^"'']+\\)?([^"'']+\.psm1)["'']?') {
            $moduleName = $Matches[2] -replace '\.psm1$', ''
        }
        # Handle simple module name (first word before any switches)
        elseif ($line -match '^([a-zA-Z0-9_-]+)') {
            $moduleName = $Matches[1].Trim()
        }
        
        # Clean up module name
        if ($moduleName) {
            $moduleName = $moduleName.Trim().Trim("'").Trim('"')
            # Remove .psm1 extension if present
            $moduleName = $moduleName -replace '\.psm1$', ''
        }
    }
    catch {
        Write-LogMessage "Error resolving module name from line: $ImportLine - $($_.Exception.Message)" -Level WARN
    }
    
    return $moduleName
}

function Build-ModuleIndex {
    <#
    .SYNOPSIS
        Builds an index of all PowerShell modules (.psm1) in the repository.
    .DESCRIPTION
        Scans all .psm1 files in the specified folder and extracts:
        - Module name (from file basename)
        - File path
        - List of exported functions
    .PARAMETER ModulesFolder
        Root folder to search for .psm1 files (default: _Modules folder in DedgePsh).
    .OUTPUTS
        Hashtable: ModuleName -> @{FilePath, Functions[]}
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$ModulesFolder = ""
    )
    
    $moduleIndex = @{}
    
    try {
        # Determine modules folder path
        if ([string]::IsNullOrWhiteSpace($ModulesFolder)) {
            # Try to find _Modules folder relative to common locations
            $possiblePaths = @(
                "$PSScriptRoot\..\..\_Modules",
                "$env:OptPath\src\DedgePsh\_Modules",
                "C:\opt\src\DedgePsh\_Modules"
            )
            
            foreach ($path in $possiblePaths) {
                if (Test-Path -Path $path -PathType Container) {
                    $ModulesFolder = $path
                    break
                }
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($ModulesFolder) -or -not (Test-Path -Path $ModulesFolder -PathType Container)) {
            Write-LogMessage "Modules folder not found. Skipping module index building." -Level WARN
            return $moduleIndex
        }
        
        Write-LogMessage "Building module index from: $ModulesFolder" -Level INFO
        
        # Find all .psm1 files
        $psm1Files = Get-ChildItem -Path $ModulesFolder -Recurse -Filter "*.psm1" -ErrorAction SilentlyContinue
        
        Write-LogMessage "Found $($psm1Files.Count) module file(s)" -Level INFO
        
        foreach ($psm1File in $psm1Files) {
            try {
                $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($psm1File.Name)
                $functions = Get-ModuleFunctions -ModuleFilePath $psm1File.FullName
                
                $moduleIndex[$moduleName] = @{
                    FilePath  = $psm1File.FullName
                    Functions = $functions
                }
                
                Write-LogMessage "Indexed module: $moduleName ($($functions.Count) functions)" -Level DEBUG
            }
            catch {
                Write-LogMessage "Error indexing module $($psm1File.Name): $($_.Exception.Message)" -Level WARN
            }
        }
        
        Write-LogMessage "Module index built: $($moduleIndex.Count) modules" -Level INFO
    }
    catch {
        Write-LogMessage "Error building module index: $($_.Exception.Message)" -Level WARN
    }
    
    return $moduleIndex
}

function Get-Ps1DecodedConcat($decodeString) {
    if ($decodeString.Contains("||")) {
        $temp1 = $decodeString.Split("||")
        $returnString = ""
        foreach ($item in $temp1) {
            $item = Get-Ps1VariableValue($item)
            $returnString += $item
        }
    }
    else {
        $returnString = $decodeString
    }
    return $returnString
}
function Decode($decodeString, $localAssignmentsDict) {
    if ($decodeString.Contains(" ")) {
        $decodeString = $decodeString.Replace("(", "( ").Replace(")", " )")
        $temp1 = $decodeString.Split(" ")
        $returnString = ""
        foreach ($item in $temp1) {
            $returnString = $returnString.Trim()
            $item = GetLocalVariableValue -decodeString $item -localAssignmentsDict $localAssignmentsDict
            $returnString += " " + $item.Trim()
        }
    }
    else {
        $returnString = $decodeString
    }
    return $returnString.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("( ", "(").Replace(" )", ")")
}

function Get-Ps1DecodedSubstr($decodeString) {
    if ($decodeString.ToLower().Contains("substr")) {
        $returnString = $decodeString

        $temp1 = $decodeString.ToLower().Split("substr")
        $returnString = ""
        foreach ($item in $temp1) {
            if ($item.Contains("(")) {
                $item = $item.Replace("(", "").Replace(")", "")
                $temp2 = $item.Split(",")[0]
                $item = $temp2
            }
            $returnString += $item
        }
    }
    else {
        $returnString = $decodeString
    }
    return $returnString
}

function Get-Ps1VariableValue($decodeString) {
    if ($decodeString.length -gt 0) {
        $returnString = $decodeString
        if ($script:assignmentsDict.ContainsKey($decodeString.Trim())) {
            $returnString = $script:assignmentsDict[$decodeString.Trim()].ToString()
            $returnString = Get-Ps1DecodedConcat($returnString)
        }
    }
    else {
        $returnString = $decodeString
    }
    return $returnString
}

function GetLocalVariableValue($decodeString, $localAssignmentsDict) {
    if ($decodeString.length -gt 0 -and $decodeString.Contains("$")) {
        $returnString = $decodeString
        if ($localAssignmentsDict.ContainsKey($decodeString.Trim().ToUpper())) {
            $returnString = "(" + $localAssignmentsDict[$decodeString.Trim()].ToString() + ")"
            $returnString = Get-Ps1DecodedConcat($returnString)
        }
    }
    else {
        $returnString = $decodeString
    }
    return $returnString
}

function New-Ps1Nodes {
    param (
        $functionCode, $fileContent , $functionName, $fdHashtable, $currentLoopCounter, $htmlPath
    )

    $localAssignmentsDict = @{}
    $functionListLocal = $script:functionList2
    $currentSetLocation = ""
    $uniqueCounter = 0
    foreach ($lineObject in $functionCode) {
        # Skip null objects or objects with null Line property
        if ($null -eq $lineObject -or $null -eq $lineObject.Line) {
            $uniqueCounter += 1
            continue
        }
        
        if ($uniqueCounter -eq 0) {
            $lineNum = if ($lineObject.LineNumber) { $lineObject.LineNumber } else { 1 }
            $link = "https://Dedge.visualstudio.com/Dedge/_git/DedgePsh?path=" + $htmlPath + "&version=GBmain&line=" + $lineNum.ToString() + "&lineEnd=" + ($lineNum + 1).ToString() + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents#function-" + $functionName.ToLower()
            $statement = "click " + $functionName.ToLower() + " " + '"' + $link + '"' + " " + '"' + $functionName.ToLower() + '"' + " _blank"
            Write-Ps1Mmd -mmdString $statement
            $statement = "style " + $functionName.ToLower() + " stroke:dark-blue,stroke-width:3px"
            Write-Ps1Mmd -mmdString $statement
        }
        if ($lineObject.Line.Trim().Contains("=")) {
            $temp = $lineObject.Line -split "="
            $key = $temp[0].Trim().ToUpper()
            try {
                $localAssignmentsDict[$key] = $temp[1].Trim().Replace('"', "'")
            }
            catch {
            }
        }

        $uniqueCounter += 1
        $line = $lineObject.Line.Trim()

        if ($line.Length -eq 0) {
            continue
        }
        ############################################################################################################################################
        ############################################################################################################################################
        ############################################################################################################################################
        ############################################################################################################################################

        $line = $line.Replace("(", " ( ").Replace(")", " ) ").Replace("  ", " ")
        if ($line.ToLower().StartsWith("set-location")) {
            $currentSetLocation = $line.ToLower().Replace("set-location", "").Trim()
            Continue
        }

        if ($line.ToLower().StartsWith(".")) {
            $line = $currentSetLocation.Trim() + $line.ToLower().Substring(1).Trim()
        }

        $anyhits = $false
        if (-not $line.ToUpper().Trim().StartsWith("FUNCTION ")) {

            foreach ($item1 in $line.Trim().Split(" ")) {
                try {
                    $funcNameUpper = $item1.ToUpper().Trim()
                    if ($funcNameUpper.Length -eq 0) {
                        continue
                    }
                    
                    # Check if function exists in current file
                    if ($functionListLocal.Contains($funcNameUpper)) {
                        $toNode = $item1.ToLower()
                        if ($functionName.ToUpper().Trim() -eq $funcNameUpper) {
                            Continue
                        }
                        $statement = $functionName.Trim().ToLower() + " --call function--> " + $toNode.ToLower().Replace(" ", "_") + "(" + '"' + $toNode + '"' + ")"
                        Write-Ps1Mmd -mmdString $statement
                        $anyhits = $true
                    }
                    # Check if function is from an imported module
                    elseif ($script:importedModules -and $script:importedModules.Count -gt 0 -and $script:moduleIndex) {
                        $foundInModule = $false
                        foreach ($moduleName in $script:importedModules.Keys) {
                            if ($script:moduleIndex.ContainsKey($moduleName)) {
                                $moduleInfo = $script:moduleIndex[$moduleName]
                                if ($moduleInfo.Functions -contains $funcNameUpper) {
                                    # Function is from imported module
                                    $moduleFilePath = $script:importedModules[$moduleName]
                                    $moduleFileName = [System.IO.Path]::GetFileName($moduleFilePath)
                                    $toNode = $functionName.Trim().ToLower() + "_call_" + $funcNameUpper.ToLower().Replace("-", "_") + $uniqueCounter.ToString()
                                    
                                    # Create link with function anchor
                                    $link = "./" + $moduleFileName + ".html#function-" + $item1.ToLower()
                                    $statement = $functionName.Trim().ToLower() + " --call module function--> " + $toNode + "(" + '"' + $item1.ToLower() + "`nfrom " + $moduleName + '"' + ")"
                                    Write-Ps1Mmd -mmdString $statement
                                    
                                    # Add click event with function anchor
                                    $statement = "click " + $toNode + " " + '"' + $link + '"' + " " + '"' + $item1.ToLower() + '"' + " _blank"
                                    Write-Ps1Mmd -mmdString $statement
                                    $statement = "style " + $toNode + " stroke:dark-green,stroke-width:3px"
                                    Write-Ps1Mmd -mmdString $statement
                                    
                                    $anyhits = $true
                                    $foundInModule = $true
                                    break
                                }
                            }
                        }
                    }

                }
                catch {
                }
            }
        }
        if ($anyhits) {
            Continue
        }

        if ($line.trim().tolower().startswith("& run ") `
                -or $line.trim().tolower().contains("c:\program files (x86)\micro focus\server 5.1\bin\run.exe")) {
            $temp0 = $line.ToLower().Replace("& run ", "").Replace("c:\program files (x86)\micro focus\server 5.1\bin\run.exe", "").Replace("&", "").Trim()
            $temp1 = Decode -decodeString $temp0 -localAssignmentsDict $localAssignmentsDict
            $temp1 = Decode -decodeString $temp1 -localAssignmentsDict $localAssignmentsDict
            $temp1 = Decode -decodeString $temp1 -localAssignmentsDict $localAssignmentsDict

            $temp1 = Decode -decodeString $temp1 -localAssignmentsDict $script:assignmentsDict
            $temp1 = Decode -decodeString $temp1 -localAssignmentsDict $script:assignmentsDict
            $temp1 = Decode -decodeString $temp1 -localAssignmentsDict $script:assignmentsDict

            $temp1 = $temp1.Replace("'", "").Replace('"', "").Replace("((", "(").Replace("))", ")").Replace("  ", " ").Replace("  ", " ")

            $pos1 = $temp1.ToLower().IndexOf(" ")
            $pos2 = $temp1.ToLower().IndexOf("(")
            if ($pos1 -gt 0 -and $pos2 -gt 0 -and $pos1 -gt $pos2) {
                $pos = $pos2
            }
            else {
                $pos = $pos1
            }

            try {
                $temp3 = $temp1.Split("\")
                $temp4 = $temp3[$temp3.Length - 1]
                $temp5 = $temp4.Split(" ")
                $params = "parameters: " + $temp4.Replace($temp5[0], "").Trim()
                $module = $temp5[0] + ".cbl"
                $script:htmlCallListCbl += $module
            }
            catch {
                $module = $temp0.Trim().ToLower()
                $params = ""
            }

            $optionsText = ""
            $toNode = $functionName.Trim().ToLower() + $module + $uniqueCounter.ToString()
            $module = "run cobol program`n" + $module
            $optionsText = "run cobol program"
            $toNode = $functionName.Trim().ToLower() + "runcbl" + $uniqueCounter.ToString()
            $statement = $functionName.Trim().ToLower() + " --" + $optionsText + "-->" + $toNode + "(" + '"' + $module + "`n" + $params + '"' + ")"
            Write-Ps1Mmd -mmdString $statement
            Continue
        }

        if ($line.ToLower().Contains("db2exportcsv.exe") `
                -or $line.Trim().ToLower().Contains("db2cmd.exe") `
                -or $line.Trim().ToLower().Contains("db2cmd.exe")
        ) {
            $temp1 = Decode -decodeString $line -localAssignmentsDict $localAssignmentsDict
            $temp1 = Decode -decodeString $temp1 -localAssignmentsDict $localAssignmentsDict
            $temp1 = Decode -decodeString $temp1 -localAssignmentsDict $localAssignmentsDict

            $temp1 = Decode -decodeString $temp1 -localAssignmentsDict $script:assignmentsDict
            $temp1 = Decode -decodeString $temp1 -localAssignmentsDict $script:assignmentsDict
            $temp1 = Decode -decodeString $temp1 -localAssignmentsDict $script:assignmentsDict

            $temp1 = $temp1.Replace("'", "").Replace('"', "").Replace("((", "(").Replace("))", ")").Replace("  ", " ").Replace("  ", " ")

            # Try to extract SQL statement from db2 command
            $sqlOperation, $sqlTableNames, $cursorName, $cursorForUpdate, $updateFields = FindSqlStatementInDb2Command -CommandLine $line
            
            if ($sqlOperation -and $sqlTableNames.Count -gt 0) {
                # SQL statement detected - create SQL table nodes (like COBOL does)
                $supportedSqlExpressions = @("SELECT", "UPDATE", "INSERT", "DELETE", "FETCH", "CALL")
                if ($supportedSqlExpressions -contains $sqlOperation) {
                    $tableCounter = 0
                    foreach ($sqlTable in $sqlTableNames) {
                        $script:sqlTableArray += $sqlTable
                        $tableCounter += 1
                        $statementText = $sqlOperation.ToLower()
                        
                        # Handle cursor logic (similar to COBOL)
                        if ($cursorName -and $cursorName.Length -gt 0) {
                            if ($tableCounter -eq 1) {
                                $statementText = "Cursor " + $cursorName.ToUpper() + " select"
                                if ($cursorForUpdate) {
                                    $statementText = "Primary table for cursor " + $cursorName.ToUpper() + " select for update"
                                }
                            }
                            else {
                                $statementText = "Sub-select in cursor " + $cursorName.ToUpper()
                            }
                        }
                        else {
                            # Handle multiple tables in non-cursor statements
                            if ($tableCounter -gt 1) {
                                if ($sqlOperation -eq "UPDATE" -or $sqlOperation -eq "INSERT" -or $sqlOperation -eq "DELETE") {
                                    $statementText = "Sub-select related to " + $sqlTableNames[0].Trim()
                                }
                                if ($sqlOperation -eq "SELECT") {
                                    $statementText = "Join or Sub-select related to " + $sqlTableNames[0].Trim()
                                }
                            }
                            # Add field names for UPDATE statements (primary table only)
                            elseif ($sqlOperation -eq "UPDATE" -and $updateFields -and $updateFields.Count -gt 0) {
                                $fieldList = $updateFields -join ", "
                                $statementText = "update [$($fieldList)]"
                            }
                        }
                        
                        # Create SQL table node connection (same format as COBOL)
                        $statement = $functionName.Trim().ToLower() + '--"' + $statementText + '"-->sql_' + $sqlTable.Replace(".", "_").Trim() + "[(" + $sqlTable.Trim() + ")]"
                        Write-Ps1Mmd -mmdString $statement
                    }
                    # Skip process node creation when SQL is detected
                    Continue
                }
            }
            
            # No SQL detected - treat as regular DB2 command (process node)
            $temp4 = $temp1.Split(" ")

            $pos1 = $temp4[0].ToLower().LastIndexOf("\")
            $pos = $pos1
            if ($pos -gt 0) {
                $temp2 = $temp1.Substring($pos + 1).Trim()
                $params = "parameters: " + $temp1.Replace($temp4[0], "").Trim()
            }
            else {
                $temp2 = $temp1.Trim()
                $params = ""
            }
            $temp3 = $temp2.Split(" ")
            $module = $temp3[0].Trim()
            $optionsText = ""
            $toNode = $functionName.Trim().ToLower() + $module + $uniqueCounter.ToString()
            $module = "db2 command`n" + $module
            $optionsText = "call db2 command"

            $statement = $functionName.Trim().ToLower() + " --" + $optionsText + "-->" + $toNode + "(" + '"' + $module + "`n" + $params + '"' + ")"
            Write-Ps1Mmd -mmdString $statement
            Continue
        }

        # OPTIMIZED: Cache lowercased/trimmed line and use regex for multiple pattern matching
        $lineLowerTrimmed = $line.Trim().ToLower()
        if ($lineLowerTrimmed -match '^(python |py |copy-item |move-item |remove-item |rename-item |\[system\.io\.file\]|set-content |(\( )?get-content |add-content |logtowkmon|log-start|log-write|log-finish|log-error|write-debug|write-logmessage|logmessage|logwrite|start-sleep|start-process|(\( )?get-childitem|out-file|git|cmd\.exe|push-location|pop-location|db2cmd\.exe |copy |new-item |write-output |invoke-webrequest |send-mailmessage|start-transcript|stop-transcript|import-module|install-windowsfeature|send-fkalert|invoke-expression)' `
                -or $lineLowerTrimmed -match '(mmdc\.exe|utf8ansi|tilutf8\.exe)'
        ) {
            # OPTIMIZED: Reduce decode iterations - 2 passes is usually sufficient
            $temp1 = Decode -decodeString $line -localAssignmentsDict $localAssignmentsDict
            $temp1 = Decode -decodeString $temp1 -localAssignmentsDict $script:assignmentsDict
            $temp1 = ($temp1 -replace "['""]", "") -replace '\(\(|\)\)', '(' -replace '\s{2,}', ' '
            
            $temp1Lower = $temp1.ToLower()
            $pos1 = $temp1Lower.IndexOf(" ")
            $pos2 = $temp1Lower.IndexOf("(")
            if ($pos1 -gt 0 -and $pos2 -gt 0 -and $pos1 -gt $pos2) {
                $pos = $pos2
            }
            else {
                $pos = $pos1
            }

            try {
                $module = $line.Substring(0, $pos).Trim().ToLower()
                $params = "parameters: " + $temp1.Substring($pos).Trim()
            }
            catch {
                $module = $line.Trim().ToLower()
                $params = ""
            }

            $optionsText = ""
            # Sanitize node ID - remove/replace characters that break Mermaid syntax
            $sanitizedModule = $module -replace '[\s\(\)\[\]\{\}\|]', '_' -replace '__+', '_' -replace '^_|_$', ''
            $toNode = $functionName.Trim().ToLower() + $sanitizedModule + $uniqueCounter.ToString()
            
            # Handle Import-Module statements - link to module files
            if ($module.ToLower().StartsWith("import-module") -or $lineLowerTrimmed -match '^import-module') {
                $resolvedModuleName = Resolve-ModuleName -ImportLine $line
                if ($resolvedModuleName -and $script:moduleIndex -and $script:moduleIndex.ContainsKey($resolvedModuleName)) {
                    $moduleInfo = $script:moduleIndex[$resolvedModuleName]
                    $moduleFilePath = $moduleInfo.FilePath
                    $moduleFileName = [System.IO.Path]::GetFileName($moduleFilePath)
                    
                    # Store module-to-file mapping for function call resolution
                    $script:importedModules[$resolvedModuleName] = $moduleFilePath
                    
                    # Add to htmlCallList for "Called Scripts" section
                    if (-not $script:htmlCallList.Contains($moduleFileName)) {
                        $script:htmlCallList += $moduleFileName
                    }
                    
                    # Create Mermaid node linking to module file
                    $moduleDisplayName = $resolvedModuleName + ".psm1"
                    $toNode = $functionName.Trim().ToLower() + "_import_" + $resolvedModuleName.ToLower().Replace("-", "_") + $uniqueCounter.ToString()
                    $optionsText = "import module"
                    $module = "PowerShell Module`n" + $moduleDisplayName
                    
                    $statement = $functionName.Trim().ToLower() + " --" + $optionsText + "-->" + $toNode + "[[" + $moduleDisplayName + "]]"
                    Write-Ps1Mmd -mmdString $statement
                    
                    # Add click event to navigate to module file
                    $link = "./" + $moduleFileName + ".html"
                    $statement = "click " + $toNode + " " + '"' + $link + '"' + " " + '"' + $moduleDisplayName + '"' + " _blank"
                    Write-Ps1Mmd -mmdString $statement
                    $statement = "style " + $toNode + " stroke:dark-blue,stroke-width:4px"
                    Write-Ps1Mmd -mmdString $statement
                    
                    Continue
                }
                else {
                    # Module not found in index - treat as generic import-module command
                    $module = "import-module`n" + ($resolvedModuleName ?? "module")
                    $optionsText = "import module"
                }
            }
            elseif ($module.ToLower().StartsWith("py")) {
                $temp2 = $temp1.Split(" ")
                $module = "python " + $temp2[1].Trim()
                $params = $params.Replace($temp2[1].Trim(), "").Replace("  ", " ").Trim()
                $optionsText = "call python script"
                if ($currentSetLocation.Length -gt 0 -and $line.Trim().StartsWith(".")) {

                    $params = "parameters: " + $currentSetLocation.Trim() + $line.Substring($pos + 1).Trim()
                }
            }
            elseif ($module.ToLower().Contains("git ")) {
                $module = "git.exe`n" + $module
                $optionsText = "call git command"
                $toNode = $functionName.Trim().ToLower() + "git" + $uniqueCounter.ToString()
            }
            elseif ($module.ToLower().Contains("tilutf8")) {
                $module = "tilutf8`n" + $module
                $optionsText = "call custom exe"
                $toNode = $functionName.Trim().ToLower() + "tilutf8" + $uniqueCounter.ToString()
            }
            elseif ($module.ToLower().Contains("utf8ansi")) {
                $module = "utf8ansi`n" + $module
                $optionsText = "call custom exe"
                $toNode = $functionName.Trim().ToLower() + "utf8ansi" + $uniqueCounter.ToString()
            }
            elseif ($module.ToLower().contains("mmdc.exe")) {
                $module = "mermaid executable`n" + $module
                $optionsText = "call mermaid exe"
                $toNode = $functionName.Trim().ToLower() + "utf8ansi" + $uniqueCounter.ToString()
            }
            elseif ($line.contains("|")) {
                $temp4 = $line.Trim()
                $temp5 = $temp4.Split("|")
                $temp6 = $temp5[$temp5.Length - 1].Trim()
                $module = $temp6
                $optionsText = "call built-in function"
                $params = ""
                $toNode = $functionName.Trim().ToLower() + "callfuc" + $uniqueCounter.ToString()
            }
            elseif ($line.StartsWith("copy ")) {
                $optionsText = "call windows command"
            }
            else {
                $optionsText = "call built-in function"

            }

            $statement = $functionName.Trim().ToLower() + " --" + $optionsText + "-->" + $toNode + "(" + '"' + $module + "`n" + $params + '"' + ")"
            Write-Ps1Mmd -mmdString $statement
            Continue
        }

        if ($line.Length -gt 3 ) {
            if (($line.ToLower().StartsWith(".") -or $line.ToLower().Contains(".ps1") -or $line.ToLower().Substring(1, 2) -eq ":\") -and -not  $line.ToLower().Contains("*.ps1")) {
                $temp1 = Decode -decodeString $line -localAssignmentsDict $localAssignmentsDict

                $temp1 = $temp1.Replace("'", "").Replace('"', "").Replace("((", "(").Replace("))", ")").Replace("  ", " ").Replace("  ", " ")

                $temp4 = $temp1.Split(" ")

                $pos1 = $temp4[0].ToLower().LastIndexOf("\")
                $pos = $pos1
                if ($pos -gt 0) {
                    $temp2 = $temp1.Substring($pos + 1).Trim()
                    $params = "parameters: " + $temp1.Replace($temp4[0], "").Trim()
                }
                else {
                    $temp2 = $temp1.Trim()
                    $params = ""
                }

                $temp3 = $temp2.Split(" ")
                $params = $temp1.Trim().Replace($temp3[0], "").Trim()
                $module = $temp3[0].Trim().Replace("\", "")

                if ( -not $module.ToLower().Contains(".ps1")) {
                    $module += ".ps1"
                }
                $script:htmlCallList += $module
                if ( -not $temp1.ToLower().Contains(".ps1")) {
                    $temp1 += ".ps1"
                }
                # $module += "`n" + $temp1

                $toNode = $functionName.Trim().ToLower() + "pshcall" + $uniqueCounter.ToString()

                if ($params.Length -gt 0) {
                    $params = "`n" + "parameters: " + $params
                }
                $module = $module.Replace("'", "").Replace('"', "")
                $params = $params.Replace("'", "").Replace('"', "")
                $optionsText = "call powershell script"

                $statement = $functionName.Trim().ToLower() + " --" + $optionsText + "-->" + $toNode + "(" + '"' + $module + $params + '"' + ")"
                Write-Ps1Mmd -mmdString $statement
                Continue
            }
        }

        if (-not ($line.Contains("=") `
                    -or $line.Trim() -eq "{" `
                    -or $line.Trim() -eq "}" `
                    -or $line.Trim().ToLower().Contains("catch ")  `
                    -or $line.Trim().ToLower().Contains("continue")  `
                    -or $line.Trim().ToLower().Contains("break")  `
                    -or $line.Trim().ToLower().StartsWith("exit")  `
                    -or $line.Trim().ToLower().Contains("try ")  `
                    -or $line.Trim().ToLower().Contains("else")  `
                    -or $line.Trim().ToLower().StartsWith("throw")  `
                    -or $line.Trim().ToLower().StartsWith("default")  `
                    -or $line.Trim().ToLower().Contains("write-host") `
                    -or $line.Trim().ToLower().Contains("write-logmessage") `
                    -or $line.Trim().ToLower().Contains("import-module") `
                    -or $line.Trim().ToLower().Contains("send-fkalert") `
                    -or $line.Trim().ToLower().Contains("install-windowsfeature") `
                    -or $line.Trim().ToLower().Contains("param (") `
                    -or $line.Trim().ToLower().StartsWith("function ") `
                    -or $line.Trim().ToLower().StartsWith("$") `
                    -or $line.Trim().ToLower().StartsWith(")") `
                    -or $line.Trim().ToLower().StartsWith("if ") `
                    -or $line.Trim().ToLower().StartsWith("if(") `
                    -or $line.Trim().ToLower().StartsWith("[") `
                    -or $line.Trim().ToLower().StartsWith("<") `
                    -or $line.Trim().ToLower().StartsWith(',"') `
                    -or $line.Trim().ToLower().StartsWith('"') `
                    -or $line.Trim().ToLower().StartsWith("'") `
                    -or $line.Trim().ToLower().StartsWith("$") `
                    -or $line.Trim().ToLower().StartsWith("switch") `
                    -or $line.Trim().ToLower().StartsWith("try") `
                    -or $line.Trim().ToLower().StartsWith("finally") `
                    -or $line.Trim().ToLower().StartsWith("catch") `
                    -or $line.Trim().ToLower().StartsWith("try{") `
                    -or $line.Trim().ToLower().StartsWith("param (") `
                    -or $line.Trim().ToLower().StartsWith("return")
            )) {
            Write-LogMessage ("Unhandled line in module: " + $baseFileName + ", in function: " + $functionName + ", at line:" + $line.Trim()) -Level WARN
        }

    }
}

function New-Ps1MmdLinks {
    param (
        $baseFileName, $sourceFile, $htmlPath
    )
    try {
        $link = "https://Dedge.visualstudio.com/Dedge/_git/DedgePsh?path=" + $htmlPath
        $statement = "click " + $baseFileName.ToLower().Split(".")[0] + " " + '"' + $link + '"' + " " + '"' + $baseFileName.ToLower().Split(".")[0] + '"' + " _blank"
        Write-Ps1Mmd -mmdString $statement
        $counter = 0

        foreach ($item in $sourceFile) {
            $line = $item.line
            $counter += 1
            if ($line.Trim().Length -eq 0) {
                # Skip to next element if null
                continue
            }
            # Debug code removed
            # if ($counter -gt 39) {
            #
            # }

            if (Test-Ps1Function -functionName ($line.Trim())) {
                $line = $line.Replace("--", "-").Replace(":", "").ToLower()
                $link = "https://Dedge.visualstudio.com/Dedge/_git/DedgePsh?path=" + $htmlPath + "&version=GBmain&line=" + ($item.LineNumber).ToString() + "&lineEnd=" + ($item.LineNumber + 1).ToString() + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents"
                $statement = "click " + $line + " " + '"' + $link + '"' + " " + '"' + $line + '"' + " _blank"
                Write-Ps1Mmd -mmdString $statement
            }
        }
    }
    catch {
        $errorMessage = $_.Exception
        write-host En feil oppstod: $errorMessage
        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
        Write-LogMessage $errorMessage -Level ERROR
        $script:errorOccurred = $true
    }

}

function Get-Ps1MetaData {
    param (
        $tmpRootFolder, $baseFileName, $outputFolder, $completeFileContent, $inputDbFileFolder
    )
    try {
        $title = ""
        foreach ($line in $completeFileContent) {
            if ($line -match "[A-Za-z]" -and $line.Trim().StartsWith("#") -and -not $line.ToLower().Trim().Contains(".ps1") -and -not $line.ToLower().Trim().Contains("geir") -and -not $line.ToLower().Trim().Contains("svein")) {
                $title = $line.Replace("#", "").Replace("*/", "").Trim()
                break
            }
        }
        $startCommentFound = $false
        $commentArray = @()
        $counter = 0

        foreach ($line in $completeFileContent) {
            $counter += 1
            if ($counter -gt 100) {
                break
            }
            if (($line -match "(19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])" -or $line -match "(0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}" -or $line -match "(19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])") `
                    -and $line.Trim().StartsWith("#")) {
                $startCommentFound = $true
            }
            # if ($startCommentFound -and $line.Trim().StartsWith("#")) {
            if (($line -match "(19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])" -or $line -match "(0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}" -or $line -match "(19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])") `
                    -and $line.Trim().StartsWith("#") -and $startCommentFound) {
                $commentArray += $line.Replace("#", "").Trim()
            }

            if ($startCommentFound -and -not $line.Trim().StartsWith("#")) {
                break
            }
        }
        $commentArray2 = @()
        $newComment = ""
        $htmlCreatedDateTime = ""
        foreach ($item in $commentArray) {

            $newComment = $item.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
            $temp = $newComment.Split(" ")
            if ($htmlCreatedDateTime.Length -eq 0) {
                $htmlCreatedDateTime = $temp[0]
            }
            $tempComment = "<tr><td>" + $temp[0] + "</td><td>" + $temp[1] + "</td><td>"
            $temp2 = $newComment.Replace($temp[0] + " " + $temp[1], "").Trim()
            $newComment = $tempComment + $temp2 + "</td></tr>"
            $commentArray2 += $newComment.Trim()
        }

        $commentArray = $commentArray2

        $csvModulArray = Import-Csv ($inputDbFileFolder + "\modul.csv") -Header system, delsystem, modul, tekst, modultype, benytter_sql, benytter_ds, fra_dato, fra_kl, antall_linjer, lengde, filenavn -Delimiter ';'
        $cblArray = @()
        foreach ($item in $script:htmlCallListCbl) {
            $descArray = $csvModulArray | Where-Object { $_.modul.Contains($item.Replace(".cbl", "").ToUpper()) }
            if ($descArray.Length -eq 0) {
                $cblSystem = "N/A"
                $cblDesc = "N/A"
                $cblType = "N/A"
            }
            else {
                $temp = $descArray[0]
                $cblSystem = $temp.delsystem.Trim()
                $cblDesc = $temp.tekst.Trim()
                $cblType = $temp.modultype.Trim()

                if ($cblType -eq "B") {
                    $cblType = "B - Batchprogram"
                }
                elseif ($cblType -eq "H") {
                    $cblType = "H - Main user interface"
                }
                elseif ($cblType -eq "S") {
                    $cblType = "S - Webservice"
                }
                elseif ($cblType -eq "V") {
                    $cblType = "V - Validation module for user interface"
                }
                elseif ($cblType -eq "A") {
                    $cblType = "A - Common module"
                }
                elseif ($cblType -eq "F") {
                    $cblType = "F - Search module for user interface"
                }
            }

            $link = "<a href=" + '"' + "./" + $item.Trim() + ".html" + '"' + ">" + $item.Trim() + "</a>"
            $tempComment = "<tr><td>" + $link + "</td><td>" + $cblDesc + "</td><td>" + $cblType + "</td><td>" + $cblSystem + "</td></tr>"

            $cblArray += $tempComment
        }

        $scriptArray = @()
        foreach ($item in $script:htmlCallList) {
            $link = "<a href=" + '"' + "./" + $item.Trim() + ".html" + '"' + ">" + $item.Trim() + "</a>"
            $tempComment = "<tr><td>" + $link + "</td></tr>"
            $scriptArray += $tempComment
        }

        # Generate function list HTML with anchors
        $functionsHtml = ""
        $functionsStyle = "display: none;"
        if ($script:functionList -and $script:functionList.Count -gt 0) {
            $functionsStyle = ""
            foreach ($func in $script:functionList) {
                if ($func -ne "__MAIN__" -and $func.Length -gt 0) {
                    $anchorId = "function-" + $func.ToLower()
                    $functionsHtml += "<a href='#$anchorId' id='$anchorId' class='function-anchor' style='display: inline-block; margin-right: 0.5rem; margin-bottom: 0.25rem; padding: 0.25rem 0.5rem; background: var(--bg-secondary); border-radius: 3px; text-decoration: none; color: var(--text-primary);'>$func</a> "
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($functionsHtml)) {
            $functionsHtml = "<span style='color: var(--text-secondary); font-style: italic;'>No functions found</span>"
        }

        $htmlDesc = $title.Trim()
        $htmlType = "Powershell Script"

        $temp = $completeFileContent | Select-String -Pattern @("sqlexec")
        $htmlUseSql = ""
        if ($temp.Length -gt 0) {
            $htmlUseSql = "checked"
        }
        $temp = $completeFileContent | Select-String -Pattern @("ftpsetuser")
        $htmlUseFtp = ""
        if ($temp.Length -gt 0) {
            $htmlUseFtp = "checked"
        }
        $temp = $completeFileContent | Select-String -Pattern @("invoke-webrequest")
        $htmlUseWs = ""
        if ($temp.Length -gt 0) {
            $htmlUseWs = "checked"
        }

    }
    catch {
        $errorMessage = $_.Exception
        write-host En feil oppstod: $errorMessage
        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
        Write-LogMessage $errorMessage -Level ERROR
        $script:errorOccurred = $true
    }
    finally {
        $htmlFilename = $outputFolder + "\" + $baseFileName + ".html"
        
        # Use template from OutputFolder\_templates (copied at startup by AutoDocBatchRunner)
        $templatePath = Join-Path $outputFolder "_templates"
        $mmdTemplateFilename = Join-Path $templatePath "ps1mmdtemplate.html"

        $myDescription = "AutoDoc Flowchart - Powershell Script - " + $baseFileName.ToLower()

        $tmpl = Get-Content -Path $mmdTemplateFilename -Raw -Encoding UTF8
        # Apply shared CSS and common URL replacements
        $doc = Set-AutodocTemplate -Template $tmpl -OutputFolder $outputFolder
        $doc = $doc.Replace("[title]", $myDescription)
        $doc = $doc.Replace("[desc]", $title)
        $doc = $doc.Replace("[generated]", (Get-Date).ToString())
        $doc = $doc.Replace("[type]", $htmlType)
        $doc = $doc.Replace("[usesql]", $htmlUseSql)
        $doc = $doc.Replace("[useftp]", $htmlUseFtp)
        $doc = $doc.Replace("[usews]", $htmlUseWs)
        $doc = $doc.Replace("[created]", $htmlCreatedDateTime)
        $doc = $doc.Replace("[changelog]", $commentArray)
        $doc = $doc.Replace("[calllist]", $scriptArray)
        $doc = $doc.Replace("[calllistcbl]", $cblArray)
        $doc = $doc.Replace("[diagram]", "./" + $baseFileName + ".flow.svg" )
        $doc = $doc.Replace("[sourcefile]", $baseFileName.ToLower())
        
        # For client-side rendering, embed MMD content directly
        if ($ClientSideRender) {
            $flowMmdContent = ""
            # IN-MEMORY: Get content from ArrayList instead of file
            if ($script:useClientSideRender) {
                $flowMmdContent = $script:mmdFlowContent -join "`n"
            }
            elseif (Test-Path -Path $script:mmdFilename -PathType Leaf) {
                $flowMmdContent = Get-Content -Path $script:mmdFilename -Raw -ErrorAction SilentlyContinue
            }
            $doc = $doc.Replace("[flowmmd_content]", $flowMmdContent)
            $doc = $doc.Replace("[sequencemmd_content]", "")  # PS1 doesn't have sequence diagrams
        }
        
        set-content -Path $htmlFilename -Value $doc
    }

}

function Write-Ps1Mmd {
    param (
        $mmdString
    )

    # OPTIMIZED: Replace literal newlines with <br/> for Mermaid compatibility
    $mmdString = $mmdString -replace "`n", "<br/>" -replace "`r", ""
    $mmdString = $mmdString.Replace("__MAIN__", "main").Replace("__main__", "main")
    $mmdString = $mmdString -replace '\s{2,}', ' '  # OPTIMIZED: Single regex for multiple spaces
    $mmdString = $mmdString.Replace("[system.io.file]:", "")
    
    # FIX: Escape special characters that break Mermaid syntax
    # Handle backslashes in paths (common in Windows paths)
    $mmdString = $mmdString.Replace('\', '/')
    # Handle dollar signs in PowerShell variables 
    $mmdString = $mmdString.Replace('$', '#')
    # Handle parentheses that could break node definitions
    $mmdString = $mmdString -replace '\)\s*\)', ')'
    $mmdString = $mmdString -replace '\(\s*\(', '('
    # Handle ampersand - but NOT in URLs (keep %amp)
    if (-not $mmdString.Contains('http')) {
        $mmdString = $mmdString.Replace('&', ' and ')
    }
    # Handle pipes
    $mmdString = $mmdString.Replace('|', ' pipe ')
    
    # FIX: Handle nested quotes inside node labels - simplified approach
    # Remove any embedded quotes that appear after = inside node labels
    $mmdString = $mmdString -replace '= "#', '= #'
    $mmdString = $mmdString -replace '=  "#', '= #'
    
    # Truncate very long parameter strings to prevent parsing issues
    if ($mmdString.Contains('parameters:') -and $mmdString.Length -gt 250) {
        $pos = $mmdString.IndexOf('parameters:')
        $truncated = $mmdString.Substring(0, [Math]::Min($pos + 60, $mmdString.Length)) + '...'
        # Close any open parentheses/brackets
        if ($mmdString.Contains('("')) {
            $truncated += '")'
        }
        elseif ($mmdString.Contains('[(')) {
            $truncated += ')]'
        }
        $mmdString = $truncated
    }

    # Add to flow content (in-memory or file)
    if (-not $script:duplicateLineCheck.Contains($mmdString)) {
        if ($script:useClientSideRender) {
            [void]$script:mmdFlowContent.Add($mmdString)
        }
        else {
            Add-Content -Path $script:mmdFilename -Value $mmdString -Force
        }
        [void]$script:duplicateLineCheck.Add($mmdString)
    }
}

function Find-Ps1FunctionCode {
    param ($array, [string] $functionName)
    # Regular expression patterns

    # Initialize variables
    $foundStart = $false

    $functionName = $functionName.ToLower()

    $extractedElements = @()

    $lineNumber = 0
    $startBracketCount = 0
    $endBracketCount = 0
    # Loop through the array
    foreach ($item in $array) {
        $lineNumber += 1

        if ($item.Line.Trim().StartsWith("function ") -and $item.Line.ToUpper().Trim().Contains($functionName.ToUpper())) {
            $foundStart = $true
            $extractedElements = @()
        }
        #count brackets to find end of function
        if ($foundStart) {
            $startBracketCount += ($item.Line -split "{").Count - 1
            $endBracketCount += ($item.Line -split "}").Count - 1
            $extractedElements += $item
            if ($startBracketCount -gt 0 -and $startBracketCount -eq $endBracketCount) {
                $foundStart = $false
                break
            }
        }
    }
    return $extractedElements
}


<#
.SYNOPSIS
    PowerShell Parser Functions Module for AutoDoc.

.DESCRIPTION
    Contains the Start-Ps1Parse entry point function that orchestrates
    PowerShell file parsing and AutoDoc HTML generation.

.AUTHOR
    Geir Helge Starholm, www.dEdge.no

.NOTES
    Migrated to AutodocFunctions module - 2026-01-19
#>

function Start-Ps1Parse {
    <#
    .SYNOPSIS
        Main entry point for PowerShell file parsing.
    
    .DESCRIPTION
        Parses PowerShell script files and generates AutoDoc HTML documentation
        with Mermaid flowchart diagrams.
    
    .PARAMETER SourceFile
        Path to the .ps1 file to parse.
    
    .PARAMETER Show
        If true, opens the generated HTML file after creation.
    
    .PARAMETER OutputFolder
        Output folder for generated files.
    
    .PARAMETER CleanUp
        If true, cleans up temporary files after processing.
    
    .PARAMETER TmpRootFolder
        Root folder for temporary files.
    
    .PARAMETER SrcRootFolder
        Root folder for source files.
    
    .PARAMETER ClientSideRender
        Skip SVG generation and use client-side Mermaid.js rendering.
    
    .PARAMETER SaveMmdFiles
        Save Mermaid diagram source files (.mmd) alongside the HTML output.
    
    .OUTPUTS
        Path to the generated HTML file, or $null on error.
    
    .EXAMPLE
        Start-Ps1Parse -SourceFile "C:\scripts\myscript.ps1" -OutputFolder "C:\output"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [bool]$Show = $false,
        [string]$OutputFolder = "$env:OptPath\Webs\AutoDoc",
        [bool]$CleanUp = $true,
        [string]$TmpRootFolder = "$env:OptPath\data\AutoDoc\tmp",
        [string]$SrcRootFolder = "$env:OptPath\data\AutoDoc\src",
        [switch]$ClientSideRender,
        [switch]$SaveMmdFiles,
        [hashtable]$ModuleIndex = $null
    )
    
    # Initialize script-level variables
    $script:sequenceNumber = 0
    $baseFileName = [System.IO.Path]::GetFileName($SourceFile)
    $fullFileName = $SourceFile
    $htmlPath = $fullFileName.Replace($SrcRootFolder, "").Replace("\DedgePsh", "").Replace($baseFileName, "").Replace("\", "%2F") + $baseFileName
    
    # Initialize module tracking variables
    if ($null -ne $ModuleIndex) {
        $script:moduleIndex = $ModuleIndex
    }
    if ($null -eq $script:importedModules) {
        $script:importedModules = @{}  # ModuleName -> FilePath mapping
    }
    
    Write-LogMessage ("Starting parsing of filename:" + $SourceFile) -Level INFO
    
    # Check if the filename contains spaces
    if ($baseFileName.Contains(" ")) {
        Write-LogMessage ("Filename is not valid. Contains spaces:" + $baseFileName) -Level ERROR
        return $null
    }
    
    # Check if the filename match the purpose of the script
    if (-Not ($baseFileName.ToLower().Contains(".ps1") -or $baseFileName.ToLower().Contains(".psm1"))) {
        Write-LogMessage ("Filetype is not valid for parsing of Powershell script (.ps1 or .psm1):" + $baseFileName) -Level ERROR
        return $null
    }
    
    # Check if the file exist in certain folders
    if ($SourceFile.ToLower().Contains("\fat\") -or $SourceFile.ToLower().Contains("\kat\") -or $SourceFile.ToLower().Contains("\vft\")) {
        Write-LogMessage ("Skipping file due to location in KAT/FAT/VFT:" + $SourceFile) -Level INFO
        return $null
    }
    
    # IN-MEMORY MMD ACCUMULATION
    $StartTime = Get-Date
    $script:logFolder = $OutputFolder
    $script:mmdFilename = $OutputFolder + "\" + $baseFileName + ".flow.mmd"
    $script:debugFilename = $OutputFolder + "\" + $baseFileName + ".debug"
    $svgFilename = $OutputFolder + "\" + $baseFileName + ".flow.svg"
    $htmlFilename = $OutputFolder + "\" + $baseFileName + ".html"
    $script:errorOccurred = $false
    $script:sqlTableArray = @()
    $inputDbFileFolder = $TmpRootFolder + "\cobdok"
    $script:duplicateLineCheck = [System.Collections.Generic.HashSet[string]]::new()
    
    # IN-MEMORY: Use ArrayList for thread-safe accumulation
    $script:mmdFlowContent = [System.Collections.ArrayList]::new()
    $script:useClientSideRender = $ClientSideRender
    
    Write-LogMessage ("Started for :" + $baseFileName) -Level INFO
    
    if ($baseFileName.ToLower().Contains("parse.ps1")) {
        Write-LogMessage ("Cannot create diagram on parser programs: " + $baseFileName) -Level INFO
        return $null
    }
    
    # Initialize MMD with flowchart header
    $mmdHeader = @"
%%{ init: { 'flowchart': { 'curve': 'basis' } } }%%
flowchart LR
"@
    
    if ($script:useClientSideRender) {
        [void]$script:mmdFlowContent.Add($mmdHeader)
    }
    else {
        Set-Content -Path $script:mmdFilename -Value $mmdHeader -Force
    }
    
    $programName = [System.IO.Path]::GetFileName($SourceFile.ToLower())
    $script:baseFileNameTemp = $baseFileName
    
    $script:functionList = @()
    $script:assignmentsDict = @{}
    $script:functionList2 = @()
    
    if (Test-Path -Path $SourceFile -PathType Leaf) {
        $fileContentOriginalWithComments = Get-Content -Path $SourceFile
        $fileContentOriginal = Get-Content -Path $SourceFile | Select-String "^*"
        $testArray = { }.Invoke()
        $counter = -1
        $counter2 = -1
        $accumulate = $false
        $accumulateText = ""
        $fileContent = $fileContentOriginal
        
        # Find content between <# and #> and add # to the start of each line
        $isInbetween = $false
        foreach ($item in $fileContent) {
            $counter += 1
            if ($item.Line.Trim().StartsWith("<#")) {
                $item.Line = $item.Line.Replace("<#", "")
                $isInbetween = $true
            }
            if ($item.Line.Trim().EndsWith("#>")) {
                $item.Line = $item.Line.Replace("#>", "")
                $fileContent[$counter] = $item
                $isInbetween = $false
            }
            if ($isInbetween) {
                $item.Line = "# " + $item.Line
                $fileContent[$counter] = $item
            }
        }
        
        foreach ($item in $fileContent) {
            $counter += 1
            if ($item.Line.Contains("#")) {
                $pos = $item.Line.IndexOf("#")
                $item.Line = $item.Line.Substring(0, $pos)
            }
            
            if ($item.Line.Trim() -eq "{") {
                $testArray[$counter2].Line += " {"
                $item.Line = ""
            }
            
            if ($item.Line.Contains("``")) {
                if ($accumulate -eq $false) {
                    $accumulateText = ""
                    $accumulate = $true
                }
                $pos = $item.Line.IndexOf("``")
                $accumulateText += $item.Line.Substring(0, $pos).TrimEnd() + " "
                $item.Line = ""
            }
            elseif ($accumulate -eq $true) {
                $accumulateText += $item.Line.Trim()
                $item.Line = $accumulateText
                $accumulate = $false
            }
            
            if ($item.Line.Trim() -ne "") {
                $counter2 += 1
                $testArray += $item
            }
            
            if ($item.Line.ToLower().Trim().StartsWith("function")) {
                $tempItem = $item.Line.ToUpper().Replace("FUNCTION ", "").Replace("{", "").Replace("(", " (").Split(" ")[0].Trim()
                $script:functionList += $tempItem
                $script:functionList2 += $tempItem
            }
            
            if ($item.Line.Trim().Contains("=")) {
                $temp = $item.Line -split "="
                $key = $temp[0].Trim().ToUpper()
                try {
                    $script:assignmentsDict[$key] = $temp[1].Trim().Replace('"', "'")
                }
                catch { }
            }
        }
        $fileContent = $testArray
    }
    else {
        Write-LogMessage ("File not found:" + $SourceFile) -Level ERROR
        return $null
    }
    
    $script:functionList += "__MAIN__"
    $script:functionList2 += "__MAIN__"
    $functionsList = $script:functionList
    $assignmentsDict = $script:assignmentsDict
    
    $fdHashtable = @{}
    $script:htmlCallListCbl = @()
    $script:htmlCallList = @()
    $currentParticipant = ""
    $currentFunctionName = ""
    
    $loopCounter = 0
    $previousParticipant = ""
    $counter = 0
    $functionCodeExceptLoopCode = { }.Invoke()
    $mainCodeExceptLoopCode = { }.Invoke()
    $counter = 0
    $startBracketCount = 0
    $endBracketCount = 0
    
    # Initialize loop tracking arrays
    $loopLevel = { }.Invoke()
    $loopNodeContent = { }.Invoke()
    $loopCode = { }.Invoke()
    $loopCodeStartBracketCount = { }.Invoke()
    $loopCodeEndBracketCount = { }.Invoke()
    
    # Loop through all workContent
    foreach ($lineObject in $fileContent) {
        $counter += 1
        $line = $lineObject.Line
        $lineNumber = $lineObject.LineNumber
        
        if ($line.Trim().Length -eq 0 -or $null -eq $line) {
            Continue
        }
        
        # Accumulate brackets
        if ($line.Contains("{")) {
            $startBracketCount += ($line -split "{").Count - 1
        }
        if ($line.Contains("}")) {
            $endBracketCount += ($line -split "}").Count - 1
        }
        
        # Function handling
        $isFunction, $currentParticipantTemp = Test-Ps1Function -functionName $line
        $isEndOfFunction = ($startBracketCount -gt 0 -and $startBracketCount -eq $endBracketCount -and $line.trim().StartsWith("}"))
        
        $previousParticipant = $currentFunctionName
        $currentParticipant = $currentFunctionName
        
        if ($loopCounter -gt 0) {
            if ($line.Contains("{")) {
                $work = $loopCodeStartBracketCount[$loopCounter - 1]
                $work += [System.Convert]::ToInt16(($line -split "{").Count - 1)
                try {
                    $loopCodeStartBracketCount[$loopCounter - 1] = $work
                }
                catch { }
            }
            if ($line.Contains("}")) {
                try {
                    $work = $loopCodeEndBracketCount[$loopCounter - 1]
                    $work += [System.Convert]::ToInt16(($line -split "}").Count - 1)
                    $loopCodeEndBracketCount[$loopCounter - 1] = $work
                }
                catch { }
            }
        }
        
        if ($loopCounter -gt 0) {
            if ($loopCodeStartBracketCount[$loopCounter - 1] -gt 0 -and $loopCodeStartBracketCount[$loopCounter - 1] -eq $loopCodeEndBracketCount[$loopCounter - 1]) {
                $workCode = $loopCode[$loopCounter - 1]
                New-Ps1Nodes -functionCode $loopCode[$loopCounter - 1] -fileContent $fileContent -functionName ($loopLevel[$loopCounter - 1]) -fdHashtable $fdHashtable -currentLoopCounter $loopCounter -htmlPath $htmlPath
                
                try { $loopLevel.RemoveAt($loopCounter - 1) } catch { }
                try { $loopNodeContent.RemoveAt($loopCounter - 1) } catch { }
                try { $loopCode.RemoveAt($loopCounter - 1) } catch { }
                try { $loopCodeStartBracketCount.RemoveAt($loopCounter - 1) } catch { }
                try { $loopCodeEndBracketCount.RemoveAt($loopCounter - 1) } catch { }
                
                $loopCounter -= 1
                $skipLine = $true
                $currentParticipant = ""
            }
        }
        
        # Check if line is a function
        if ($isFunction -or ($isEndOfFunction -and $currentParticipant -ne "__MAIN__")) {
            if ($functionCodeExceptLoopCode.Count -gt 0) {
                $loopCounter = 0
                New-Ps1Nodes -functionCode $functionCodeExceptLoopCode -fileContent $fileContent -functionName $previousParticipant -fdHashtable $fdHashtable -loopCounter $loopCounter -htmlPath $htmlPath
                
                $counter = -1
                foreach ($item in $functionsList) {
                    $counter += 1
                    if ($item.Contains($previousParticipant)) {
                        $functionsList[$counter] = ""
                        if ($functionsList[$counter + 1] -eq "__MAIN__") {
                            $currentParticipantTemp = "__MAIN__"
                        }
                        break
                    }
                }
            }
            
            try {
                $currentParticipant = $currentParticipantTemp.Trim()
                $currentFunctionName = $currentParticipant
            }
            catch { }
            
            $loopLevel = { }.Invoke()
            $loopNodeContent = { }.Invoke()
            $loopCode = { }.Invoke()
            $loopCodeStartBracketCount = { }.Invoke()
            $loopCodeEndBracketCount = { }.Invoke()
            $loopCounter = 0
            
            $startBracketCount = ($line -split "{").Count - 1
            $endBracketCount = 0
            
            $functionCodeExceptLoopCode = { }.Invoke()
        }
        
        $skipLine = $false
        
        # Perform handling
        if ($line.trim().ToLower().StartsWith("for ") -or $line.trim().ToLower().StartsWith("for(") `
                -or $line.trim().ToLower().StartsWith("foreach ") -or $line.trim().ToLower().StartsWith("foreach(") `
                -or $line.trim().ToLower().StartsWith("do ") -or $line.trim().ToLower().StartsWith("do{") -or $line.trim().ToLower().StartsWith("do {") `
                -or $line.trim().ToLower().StartsWith("while ") -or $line.trim().ToLower().StartsWith("while(")) {
            $loopCounter += 1
            
            $tmpCurrentParticipant = $currentParticipant
            if ($tmpCurrentParticipant -eq $null -or $tmpCurrentParticipant -eq "") {
                $tmpCurrentParticipant = "__MAIN__"
            }
            if ($loopCounter -gt 1) {
                $fromNode = $loopLevel[($loopCounter - 2)]
                try {
                    $toNode = $loopLevel[($loopCounter - 2)] + $loopCounter + "((" + $loopLevel[($loopCounter - 2)] + $loopCounter + "))"
                }
                catch {
                    Write-Host "Error in line: " + $lineObject.LineNumber.ToString()
                }
                $loopLevel.Add($currentParticipant + "-loop" + $loopCounter)
            }
            else {
                $fromNode = $tmpCurrentParticipant
                $toNode = $tmpCurrentParticipant + "-loop" + "((" + $tmpCurrentParticipant + "-loop))"
                $toNode = $toNode.Replace("`$", "")
                $loopLevel.Add($tmpCurrentParticipant.Replace("`$", "") + "-loop")
            }
            
            if ($line.Contains("{")) {
                $work = [System.Convert]::ToInt16(($line -split "{").Count - 1)
                $loopCodeStartBracketCount.Add($work)
            }
            else {
                $loopCodeStartBracketCount.Add(0)
            }
            if ($line.Contains("}")) {
                $work = [System.Convert]::ToInt16(($line -split "}").Count - 1)
                $loopCodeEndBracketCount.Add($work)
            }
            else {
                $loopCodeEndBracketCount.Add(0)
            }
            
            $loopNodeContent.Add($toNode)
            $loopCode.Add("")
            try {
                $statement = $fromNode.ToLower().Replace("`$", "") + "--" + '"' + "call " + '"' + "-->" + $toNode.ToLower()
            }
            catch { }
            
            Write-Ps1Mmd -mmdString $statement
            $skipLine = $true
        }
        else {
            if ($loopCounter -gt 0) {
                # Bracket handling for loops is done above
            }
        }
        
        # Accumulate lines
        if ($skipLine -eq $false) {
            if ($loopCounter -gt 0) {
                $workCode = { }.Invoke()
                if ($loopCode[$loopCounter - 1].Length -gt 0) {
                    $workCode = $loopCode[$loopCounter - 1]
                }
                $workCode.Add($lineObject)
                try {
                    $loopCode[$loopCounter - 1] = $workCode
                }
                catch {
                    $loopCode.Add($workCode)
                }
            }
            else {
                if ($currentFunctionName -eq "" -or $currentFunctionName -eq $null -or $currentFunctionName -eq "__MAIN__") {
                    $mainCodeExceptLoopCode.Add($lineObject)
                }
                else {
                    $functionCodeExceptLoopCode.Add($lineObject)
                }
            }
        }
    }
    
    $loopCounter = 0
    
    $statement = $programName.Trim().ToLower() + "[[" + $programName.Trim().ToLower() + "]]" + " --initiated-->__main__(__main__)"
    Write-Ps1Mmd $statement
    $statement = "style " + $programName.Trim().ToLower() + " stroke:red,stroke-width:4px"
    Write-Ps1Mmd $statement
    
    $link = "https://Dedge.visualstudio.com/Dedge/_git/DedgePsh?path=" + $htmlPath
    $statement = "click " + $programName.Trim().ToLower() + " " + '"' + $link + '"' + " " + '"' + $programName.Trim().ToLower() + '"' + " _blank"
    Write-Ps1Mmd $statement
    
    # Generate nodes for last function
    New-Ps1Nodes -functionCode $mainCodeExceptLoopCode -fileContent $fileContent -functionName "__MAIN__" -fdHashtable $fdHashtable -loopCounter 0 -htmlPath $htmlPath
    
    # Generate links to sourcecode in Azure DevOps
    New-Ps1MmdLinks -baseFileName $baseFileName -htmlPath $htmlPath -sourceFile $workContent
    
    # Generate execution path diagram
    Get-Ps1ExecutionPathDiagram -srcRootFolder $SrcRootFolder -baseFileName $baseFileName -tmpRootFolder $TmpRootFolder
    
    # Generate SVG file from mmd content (skip when using client-side rendering)
    if (-not $ClientSideRender) {
        GenerateSvgFile -mmdFilename $script:mmdFilename
    }
    
    # Handle what to generate
    if (-not $script:errorOccurred) {
        Get-Ps1MetaData -tmpRootFolder $TmpRootFolder -outputFolder $OutputFolder -baseFileName $baseFileName -completeFileContent $fileContentOriginalWithComments -inputDbFileFolder $inputDbFileFolder
        if ($Show) {
            & $htmlFilename
        }
    }
    
    $endTime = Get-Date
    $timeDiff = $endTime - $StartTime
    
    # Save MMD files if requested
    if ($SaveMmdFiles) {
        if ($script:mmdFlowContent -and $script:mmdFlowContent.Count -gt 0) {
            $flowMmdOutputPath = Join-Path $OutputFolder ($baseFileName + ".mmd")
            $script:mmdFlowContent | Set-Content -Path $flowMmdOutputPath -Force
            Write-LogMessage ("Saved flow MMD file: $flowMmdOutputPath") -Level INFO
        }
    }
    
    # Log result
    $dummyFile = $OutputFolder + "\" + $baseFileName + ".err"
    $htmlFilename = $OutputFolder + "\" + $baseFileName + ".html"
    $htmlWasGenerated = Test-Path -Path $htmlFilename -PathType Leaf
    
    if ($htmlWasGenerated) {
        if (Test-Path -Path $dummyFile -PathType Leaf) {
            Remove-Item -Path $dummyFile -Force -ErrorAction SilentlyContinue
        }
        if ($script:errorOccurred) {
            Write-LogMessage ("Time elapsed: " + $timeDiff.Seconds.ToString()) -Level INFO
            Write-LogMessage ("Completed with warnings:" + $fullFileName) -Level WARN
        }
        else {
            Write-LogMessage ("Time elapsed: " + $timeDiff.Seconds.ToString()) -Level INFO
            Write-LogMessage ("Completed successfully:" + $fullFileName) -Level INFO
        }
        return $htmlFilename
    }
    else {
        Write-LogMessage ("*******************************************************************************") -Level ERROR
        Write-LogMessage ("Failed - HTML not generated:" + $SourceFile) -Level ERROR
        Write-LogMessage ("*******************************************************************************") -Level ERROR
        "Error: HTML file was not generated for $baseFileName" | Set-Content -Path $dummyFile -Force
        return $null
    }
}


#endregion

#region Rex Parse Functions
function Get-RexExecutionPathDiagram {
    param($srcRootFolder, $baseFileName, $tmpRootFolder)
    $programInUse = $false

    $returnArray = @()
    $returnArray2 = @()
    $programInUse, $returnArray2 = IsExecutedFromAny -findpath $srcRootFolder -includeFilter "*.ps1", "*.bat", "*.rex" -filename $baseFileName -programInUse $programInUse -srcRootFolder $srcRootFolder
    $returnArray += $returnArray2

    foreach ($item in $returnArray) {
        Write-RexMmd -mmdString $item
    }

    If (!$programInUse) {
        Write-LogMessage ("Program is never called from any other program or script: " + $baseFileName) -Level INFO
    }
}

function Test-RexFunction {
    param(
        $functionName
    )
    $isValidFunction = $false
    if (-not $functionName.Contains(":")) {
        return $isValidFunction
    }
    $functionTemp = $functionName.Replace(":", "").ToUpper().Trim()

    if ($script:functions.Contains($functionTemp)) {
        $isValidFunction = $true
    }
    else {
        $isValidFunction = $false
    }
    return $isValidFunction
}

function Get-RexDecodedConcat($decodeString) {
    if ($decodeString.Contains("||")) {
        $temp1 = $decodeString.Split("||")
        $returnString = ""
        foreach ($item in $temp1) {
            $item = Get-RexVariableValue($item)
            $returnString += $item
        }
    }
    else {
        $returnString = $decodeString
    }
    return $returnString
}
function DecodeQuote($decodeString) {
    if ($decodeString.Contains("'")) {
        $temp1 = $decodeString.Split("'")
        $returnString = ""
        foreach ($item in $temp1) {
            $returnString = $returnString.Trim()
            $item = Get-RexVariableValue($item)
            $returnString += " " + $item.Trim()
        }
    }
    else {
        $returnString = $decodeString
    }
    return $returnString.Trim().Replace("'", "").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
}

function Get-RexDecodedSubstr($decodeString) {
    if ($decodeString.ToLower().Contains("substr")) {
        $returnString = $decodeString

        $temp1 = $decodeString.ToLower().Split("substr")
        $returnString = ""
        foreach ($item in $temp1) {
            if ($item.Contains("(")) {
                $item = $item.Replace("(", "").Replace(")", "")
                $temp2 = $item.Split(",")[0]
                $item = $temp2
            }
            $returnString += $item
        }
    }
    else {
        $returnString = $decodeString
    }
    return $returnString
}

function Get-RexVariableValue($decodeString) {
    if ($decodeString.length -gt 0) {
        $returnString = $decodeString
        if ($script:assignmentsDict.ContainsKey($decodeString.Trim())) {
            $returnString = $script:assignmentsDict[$decodeString.Trim()].ToString()
            $returnString = Get-RexDecodedConcat($returnString)
        }
    }
    else {
        $returnString = $decodeString
    }
    return $returnString
}

function New-RexNodes {
    param (
        $functionCode, $fileContent , $functionName, $fdHashtable, $currentLoopCounter
    )

    $skipLine = $false

    if ($functionName -eq $null) {
    }
    if ($functionName.ToLower().Contains("slutt")) {
    }

    $uniqueCounter = 0
    foreach ($lineObject in $functionCode) {
        if ($uniqueCounter -eq 0) {
            $link = "https://Dedge.visualstudio.com/_git/Dedge?path=/rexx_prod/" + $baseFileName.ToLower() + "&version=GBmaster&line=" + ($lineObject.LineNumber).ToString() + "&lineEnd=" + ($lineObject.LineNumber + 1).ToString() + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents"
            $statement = "click " + $functionName.ToLower() + " " + '"' + $link + '"' + " " + '"' + $functionName.ToLower() + '"' + " _blank"
            Write-RexMmd -mmdString $statement
            $statement = "style " + $functionName.ToLower() + " stroke:dark-blue,stroke-width:3px"
            Write-RexMmd -mmdString $statement

        }
        $uniqueCounter += 1
        $line = $lineObject.Line.Trim()

        if ($line.Length -eq 0) {
            continue
        }

        if ($line.ToUpper().Contains("RXFUNCADD") ) {
            Continue
        }
        $testCallfunction = $line.ToUpper().Replace(":", "")
        if ($testCallfunction.Contains("CALL ") -and $testCallfunction.Contains(" ")) {
            $testCallfunction = $testCallfunction.Split("CALL ")[1].Trim()
        }

        if ($testCallfunction.ToUpper().Contains("CALL_COBOL")) {
        }

        if ($script:functions.Contains($line.ToUpper().Replace(":", "")) -or $script:functions.Contains($testCallfunction)) {
            if ($script:functions.Contains($testCallfunction)) {
                $toNode = $testCallfunction
            }
            else {
                $toNode = $line.ToUpper().Replace(":", "")
            }

            if ($toNode -eq $functionName.Trim().ToLower()) {
                Continue
            }
            $statement = $functionName.Trim().ToLower() + " --call--> " + $toNode.ToLower().Replace(" ", "_") + "(" + '"' + $toNode + '"' + ")"
            Write-RexMmd -mmdString $statement
            Continue
        }

        if (($line.ToLower().StartsWith("'start") -or $line.ToLower().Contains("rexx")) -and -not $line.ToLower().contains("system32")) {
            $temp1 = DecodeQuote($line)
            $temp1 = Get-RexDecodedConcat($temp1)
            $temp1 = $temp1.ToLower().Replace("'", "").Replace('"', "").Replace("start", "").Replace("rexx", "").Replace("call ", "").Replace("  ", " ").Trim()
            $rexFilename = $temp1.Trim().ToLower()
            $params = ""
            if ($rexFilename.Contains(" ")) {
                $rexFilename = $temp1.Trim().ToLower().Split(" ")[0]
                $params = $temp1.Replace($rexFilename, "").Trim()
                $temp2 = $rexFilename + "`n" + "parameters: " + $params
            }
            if (-not $rexFilename.Contains(".rex")) {
                $rexFilename += ".rex"
            }
            $itemName = $functionName.Trim().ToLower() + "_rexxrun" + $uniqueCounter.ToString()
            $script:htmlCallList += $rexFilename
            $statement = $functionName.Trim().ToLower() + " --start rexx script-->" + $itemName + "[[" + $rexFilename + "]]"
            Write-RexMmd -mmdString $statement

            $link = "./" + $rexFilename + ".html"
            $statement = "click " + $itemName + " " + '"' + $link + '"' + " " + '"' + $itemName + '"' + " _blank"
            Write-RexMmd -mmdString $statement
            $statement = "style " + $itemName + " stroke:dark-blue,stroke-width:4px"
            Write-RexMmd -mmdString $statement
            Continue
        }

        # "call\s*", "SysFileDelete", "'RUN " , "'REXX ", "'DB2", "'COPY", "'REN", "FtpLogoff", "ftpput", "ftpget", "ftpdel")

        if ($line.ToLower().contains("'@copy") `
                -or $line.ToLower().StartsWith("'pause") `
                -or $line.ToLower().StartsWith("'reg") `
                -or $line.ToLower().StartsWith("'regedit") `
                -or $line.ToLower().StartsWith("'notepad") `
                -or $line.ToLower().StartsWith("'del") `
                -or $line.ToLower().StartsWith("'icacls") `
                -or $line.ToLower().StartsWith("'@del") `
                -or $line.ToLower().StartsWith("'path") `
                -or $line.ToLower().StartsWith("'set") `
                -or $line.ToLower().StartsWith("'start") `
                -or $line.ToLower().StartsWith("'net") `
                -or $line.ToLower().StartsWith("'ren") `
                -or $line.ToLower().StartsWith("'xcopy") `
                -or $line.ToLower().StartsWith("'adfind") `
                -or $line.ToLower().contains("'copy") `
                -or $line.ToLower().contains("system32") `
                -or $line.ToLower().StartsWith("'postiecgi")`
                -or $line.ToLower().StartsWith("'postie") `
                -or $line.ToLower().contains("'xcopy") `
                -or $line.ToLower().contains("psexec") `
                -or $line.ToLower().contains("robocopy") ) {
            $temp1 = DecodeQuote($line)
            $temp1 = Get-RexDecodedConcat($temp1)
            $temp1 = $temp1.Replace('"', "").Replace("\\", "`n \\").Replace("C:\", "`n C:\").Replace("N:\", "`n N:\")
            $temp3 = $temp1.Split(" ")
            $temp2 = '"' + $temp3[0] + "`n" + $temp1.Replace($temp3[0], "").Trim() + '"'
            if ($temp2 -eq $null) {
                $temp2 = $temp1
            }

            $statement = $functionName.Trim().ToLower() + " --windows command-->" + $functionName.Trim().ToLower() + "_ren" + $uniqueCounter.ToString() + "(" + $temp2 + ")"
            Write-RexMmd -mmdString $statement
            Continue
        }
        if ($line.ToLower().contains(".bat")  ) {
            $temp1 = DecodeQuote($line)
            $temp1 = Get-RexDecodedConcat($temp1)
            $temp1 = $temp1.Replace('"', "").Replace("\\", "`n \\").Replace("C:\", "`n C:\").Replace("N:\", "`n N:\")
            $temp3 = $temp1.Split(" ")
            $temp2 = '"' + $temp3[0] + "`n parameters: " + $temp1.Replace($temp3[0], "").Trim() + '"'
            if ($temp2 -eq $null) {
                $temp2 = $temp1
            }

            $statement = $functionName.Trim().ToLower() + " --windows batch script-->" + $functionName.Trim().ToLower() + "_ren" + $uniqueCounter.ToString() + "(" + $temp2 + ")"
            Write-RexMmd -mmdString $statement
            Continue
        }

        if ($line.ToLower().contains("'run")) {
            $temp1 = DecodeQuote($line)
            $temp1 = Get-RexDecodedConcat($temp1)
            $temp1 = $temp1.ToUpper().Trim().Replace("RUN", "").Trim().Replace("  ", " ")

            $temp2 = $temp1.Split(" ")
            $cblProgram = $temp2[0].ToLower().Trim() + ".cbl"

            if ($temp2.Length -gt 1) {
                $temp1 = '"' + $cblProgram + "`n" + "parameters: " + $temp2[1].Trim().Replace(" ", ", ") + '"'
            }
            else {
                $temp1 = '"' + $cblProgram + '"'
            }
            if ($cblProgram.Length -eq 0) {
            }
            $script:htmlCallListCbl += $cblProgram
            $statement = $functionName.Trim().ToLower() + " --start cobol program-->" + $functionName.Trim().ToLower() + "_run" + $uniqueCounter.ToString() + "[[" + $temp1 + "]]"
            Write-RexMmd -mmdString $statement
            $itemName = $functionName.Trim().ToLower() + "_run" + $uniqueCounter.ToString()

            $link = "./" + $cblProgram + ".html"
            $statement = "click " + $itemName + " " + '"' + $link + '"' + " " + '"' + $itemName + '"' + " _blank"
            Write-RexMmd -mmdString $statement
            $statement = "style " + $itemName + " stroke:dark-blue,stroke-width:4px"
            Write-RexMmd -mmdString $statement
            Continue
        }

        if ($line.ToLower().contains("'db2") ) {
            $temp1 = $line.ToLower().Replace("call", "").Trim()
            $temp1 = DecodeQuote($line)
            $temp1 = Get-RexDecodedConcat($temp1)

            $itemName = $functionName.Trim().ToLower() + "_db2" + $uniqueCounter.ToString()
            $temp1 = $temp1.Replace('"', "").Replace("'", "").Trim()
            $temp3 = $temp1.Split(" ")
            $temp1 = $temp3[0] + "`n" + $temp1.ToLower().Replace($temp3[0], "").Trim()
            
            # Try to extract SQL statement from db2 command
            $sqlOperation, $sqlTableNames, $cursorName, $cursorForUpdate, $updateFields = FindSqlStatementInDb2Command -CommandLine $line
            
            if ($sqlOperation -and $sqlTableNames.Count -gt 0) {
                # SQL statement detected - create SQL table nodes (like COBOL does)
                $supportedSqlExpressions = @("SELECT", "UPDATE", "INSERT", "DELETE", "FETCH", "CALL")
                if ($supportedSqlExpressions -contains $sqlOperation) {
                    $tableCounter = 0
                    foreach ($sqlTable in $sqlTableNames) {
                        $script:sqlTableArray += $sqlTable
                        $tableCounter += 1
                        $statementText = $sqlOperation.ToLower()
                        
                        # Handle cursor logic (similar to COBOL)
                        if ($cursorName -and $cursorName.Length -gt 0) {
                            if ($tableCounter -eq 1) {
                                $statementText = "Cursor " + $cursorName.ToUpper() + " select"
                                if ($cursorForUpdate) {
                                    $statementText = "Primary table for cursor " + $cursorName.ToUpper() + " select for update"
                                }
                            }
                            else {
                                $statementText = "Sub-select in cursor " + $cursorName.ToUpper()
                            }
                        }
                        else {
                            # Handle multiple tables in non-cursor statements
                            if ($tableCounter -gt 1) {
                                if ($sqlOperation -eq "UPDATE" -or $sqlOperation -eq "INSERT" -or $sqlOperation -eq "DELETE") {
                                    $statementText = "Sub-select related to " + $sqlTableNames[0].Trim()
                                }
                                if ($sqlOperation -eq "SELECT") {
                                    $statementText = "Join or Sub-select related to " + $sqlTableNames[0].Trim()
                                }
                            }
                            # Add field names for UPDATE statements (primary table only)
                            elseif ($sqlOperation -eq "UPDATE" -and $updateFields -and $updateFields.Count -gt 0) {
                                $fieldList = $updateFields -join ", "
                                $statementText = "update [$($fieldList)]"
                            }
                        }
                        
                        # Create SQL table node connection (same format as COBOL)
                        $statement = $functionName.Trim().ToLower() + '--"' + $statementText + '"-->sql_' + $sqlTable.Replace(".", "_").Trim() + "[(" + $sqlTable.Trim() + ")]"
                        Write-RexMmd -mmdString $statement
                    }
                    # Skip process node creation when SQL is detected
                    Continue
                }
            }
            
            # No SQL detected - treat as regular DB2 command (process node)
            $statement = $functionName.Trim().ToLower() + " --DB2 command-->" + $itemName + "(" + '"' + $temp1 + '"' + ")"
            Write-RexMmd -mmdString $statement
            Continue
        }

        if ($line.ToLower().contains("ftplogoff")) {
            $statement = $functionName.Trim().ToLower() + " ---->" + $functionName.Trim().ToLower() + "_FtpLogoff" + $uniqueCounter.ToString() + "[[FtpLogoff]]"
            Write-RexMmd -mmdString $statement
            Continue
        }

        if ($line.ToLower().contains("ftpput")) {
            if ($functionName.ToLower().contains("ftp_send_borgskip")) {
            }

            $optionsText = ""
            $pos = $line.ToLower().IndexOf("ftpput")
            $temp = $line.Substring($pos + 6).Replace("(", "").Replace(")", "")
            $temp = $temp.Split(",")
            $counter = 0
            $ok = $false
            foreach ($item in $temp) {
                $item = $item.Trim()
                $counter += 1
                if ($script:assignmentsDict.ContainsKey($item)) {
                    $temp2 = $script:assignmentsDict[$item].ToString()
                    if ($temp2.Contains("||")) {
                        $temp3 = $temp2.Split("||")
                        $temp4 = ""
                        foreach ($item2 in $temp3) {
                            $temp5 = ""
                            $item2 = Get-RexVariableValue($item2)
                            $item2 = Get-RexVariableValue($item2)

                            if ($item2.ToLower().Contains("filespec")) {
                                $item2 = $item2.Replace("filespec", "").Replace("(", "").Replace(")", "").Split(",")[1].Trim()
                                $item2 = Get-RexVariableValue($item2)
                            }

                            $temp4 += $item2.Replace("'", "")
                        }
                        $temp2 = $temp4
                    }
                    $item = $temp2.trim()
                }

                if ($counter -eq 1) {
                    $optionsText += "source file: " + $item.Trim() + "`n"
                }

                if ($counter -eq 2) {
                    $optionsText += "destination file: " + $item.Trim() + "`n"
                    $ok = $true
                }
                if ($counter -eq 3) {
                    $item = $item.Replace("'", "").Replace('"', "").Trim()
                    $optionsText += "encoding: " + $item.Trim() + "`n"
                }
            }
            if ($ok) {
                $statement = $functionName.Trim().ToLower() + " --" + $optionsText + "-->" + $functionName.Trim().ToLower() + $uniqueCounter.ToString() + "_FtpPut" + "[[FtpPut]]"
                Write-RexMmd -mmdString $statement
                Continue
            }
        }

        # Call handling
        if ($line.Trim().ToLower().StartsWith("call")) {
            $skipCallList = @("rxfuncadd", "sysloadfuncs")
            foreach ($item in $skipCallList) {
                if ($line.ToLower().Contains($item)) {
                    $skipLine = $true
                    break
                }
            }

            if ($skipLine) {
                $skipLine = $false
                continue
            }

            $line = $line.Trim().ToLower().Replace("call ", "")

            if ($line.ToLower().contains("lineout")) {
                $optionsText = ""
                $tempText = ""

                $filename = ($line.ToLower().Replace("lineout", "").Trim() + '"').Split(",")[0]
                $filename = Get-RexVariableValue($filename)
                $filename = DecodeQuote($filename)
                if ($null -eq $filename) {
                    $filename = ($line.ToLower().Replace("lineout", "").Trim() + '"').Split("'")[0]

                    if ($null -eq $filename -or $filename.Contains(" ") -or $filename.Contains("-----------------")) {
                        $filename = ($line.ToLower().Replace("lineout", "").Trim() + '"').Split(",")[1]
                    }
                }
                if ($filename -eq "aplfn,") {
                }
                $tempText = $line.ToLower().Replace("lineout", "").Replace($filename, "").Trim()
                $filename = Get-RexVariableValue($filename)
                $filename = DecodeQuote($filename)

                try {
                    $write_variable = ($line.ToLower().Replace("lineout", "").Trim() + '"').Split(",")[1].Replace('"', "").Replace("'", "")
                }
                catch {
                    $write_variable = ""
                }

                $write_content = Get-RexVariableValue($write_variable)

                if ($write_content -ne "" -and -not $write_content.Contains("---------------") -and -not $write_content.Contains("substr")) {
                    $optionsText = '"write file' + "`n" + "content: " + $write_content + '"'
                }
                else {
                    $optionsText = '"write file' + '"'
                }

                $filename = $filename.Replace("'", "").Replace('"', "")
                if (-not ($filename.Contains("\") -or $filename.Contains("/"))) {
                    $filename = $filename.ToLower()
                }

                $itemName = "file" + $filename.Trim().ToLower().Replace("(", "").Replace(")", "").Replace(",", "").Replace(".", "").Replace(" ", "_").Replace("\", "_").Replace("/", "_").Replace(":", "_").TrimEnd("_").Replace("__", "_")
                # $script:assignmentsDict[$functionName] += $line.ToLower().Replace("sysfiletree", "").Trim() + "`n"
                $statement = $functionName.Trim().ToLower() + " --" + $optionsText + "-->" + $itemName + "[/" + '"' + $filename + '"' + "/]"
                Write-RexMmd -mmdString $statement
                Continue
            }

            if ($line.ToLower().contains("stream")) {
                $optionsText = ""
                $filename = ($line.ToLower().Replace("stream", "").Trim() + '"').Split(",")[0]
                if ($null -eq $filename) {
                    $filename = ($line.ToLower().Replace("stream", "").Trim() + '"').Split("'")[1]
                }

                $filename = Get-RexVariableValue($filename)

                if ($filename.Contains("'")) {
                    $temp = $filename.Split("'")
                    $temp2 = $filename.Split("'")[0]
                    $temp3 = Get-RexVariableValue($temp2)
                    $filename = $temp3 + $temp[1]
                    $filename = $filename.Replace("'", "").Replace('"', "")
                }

                try {
                    $file_operation = ($line.ToLower().Replace("stream", "").Trim() + '"').Split(",")[2].Replace('"', "").Replace("'", "").Trim()
                    $file_operation = $file_operation + " file"
                }
                catch {
                    $file_operation = ""
                }
                $filename = $filename.Replace("'", "").Replace('"', "")

                if (-not ($filename.Contains("\") -or $filename.Contains("/"))) {
                    $filename = $filename.ToLower()
                }

                $itemName = "file" + $filename.Trim().ToLower().Replace("(", "").Replace(")", "").Replace(",", "").Replace(".", "").Replace(" ", "_").Replace("\", "_").Replace("/", "_").Replace(":", "_").TrimEnd("_").Replace("__", "_")
                $statement = $functionName.Trim().ToLower() + " --" + $file_operation + "-->" + $itemName + "[/" + '"' + $filename + '"' + "/]"
                Write-RexMmd -mmdString $statement
                Continue
            }

            if ($line.ToLower().contains("ftpsetuser")) {
                $optionsText = ""
                $temp = ($line.ToLower().Replace("FtpSetUser", "").Trim() + '"').Split(",")
                $temp1 = $temp[0].Split(" ")[1]

                $temp2 = Get-RexVariableValue($temp1)
                $temp2 = $temp2.Replace("'", "").Replace('"', "")
                $operation = '"' + "host: " + $temp2 + '"'

                $statement = $functionName.Trim().ToLower() + " --" + $operation + "-->" + $functionName.Trim().ToLower() + "_FtpSetUser" + "[[FtpSetUser]]"
                Write-RexMmd -mmdString $statement
                Continue
            }

            if ($line.ToLower().contains("sysfiletree")) {
                $optionsText = ""
                $toNode = "SysFileTree"
                $temp1 = ($line.ToLower().Replace("sysfiletree", "").Trim() + '"').Split("'")[0]
                $temp2 = $script:assignmentsDict[$temp1]
                if (-not $null -eq $temp1 -and -not $null -eq $temp2) {
                    $optionsText = '"call' + "`n" + $temp2 + "`n" + $line.ToLower().Replace("sysfiletree", "").Replace($temp1, "").Trim() + '"'
                }

                # $script:assignmentsDict[$functionName] += $line.ToLower().Replace("sysfiletree", "").Trim() + "`n"
                $statement = $functionName.Trim().ToLower() + " --" + $optionsText + "-->" + $toNode.Trim().ToLower().Replace(" ", "_").Replace(",", "_").Replace("(", "_").Replace(")", "_").TrimEnd("_").Replace("__", "_") + "(" + '"' + $toNode.Trim().ToLower() + '"' + ")"
                Write-RexMmd -mmdString $statement
                Continue
            }

            if ($line.ToLower().contains("sqlexec")) {
                $temp1 = DecodeQuote($line)
                $temp1 = Get-RexDecodedConcat($temp1)

                $itemName = $functionName.Trim().ToLower() + "_sqlexec" + $uniqueCounter.ToString()
                $temp1 = $temp1.Trim().ToLower().Replace("sqlexec", "'").Trim()
                
                # Try to extract SQL statement from sqlexec command
                $sqlOperation, $sqlTableNames, $cursorName, $cursorForUpdate, $updateFields = FindSqlStatementInDb2Command -CommandLine $line
                
                if ($sqlOperation -and $sqlTableNames.Count -gt 0) {
                    # SQL statement detected - create SQL table nodes (like COBOL does)
                    $supportedSqlExpressions = @("SELECT", "UPDATE", "INSERT", "DELETE", "FETCH", "CALL")
                    if ($supportedSqlExpressions -contains $sqlOperation) {
                        $tableCounter = 0
                        foreach ($sqlTable in $sqlTableNames) {
                            $script:sqlTableArray += $sqlTable
                            $tableCounter += 1
                            $statementText = $sqlOperation.ToLower()
                            
                            # Handle cursor logic (similar to COBOL)
                            if ($cursorName -and $cursorName.Length -gt 0) {
                                if ($tableCounter -eq 1) {
                                    $statementText = "Cursor " + $cursorName.ToUpper() + " select"
                                    if ($cursorForUpdate) {
                                        $statementText = "Primary table for cursor " + $cursorName.ToUpper() + " select for update"
                                    }
                                }
                                else {
                                    $statementText = "Sub-select in cursor " + $cursorName.ToUpper()
                                }
                            }
                            else {
                                # Handle multiple tables in non-cursor statements
                                if ($tableCounter -gt 1) {
                                    if ($sqlOperation -eq "UPDATE" -or $sqlOperation -eq "INSERT" -or $sqlOperation -eq "DELETE") {
                                        $statementText = "Sub-select related to " + $sqlTableNames[0].Trim()
                                    }
                                    if ($sqlOperation -eq "SELECT") {
                                        $statementText = "Join or Sub-select related to " + $sqlTableNames[0].Trim()
                                    }
                                }
                                # Add field names for UPDATE statements (primary table only)
                                elseif ($sqlOperation -eq "UPDATE" -and $updateFields -and $updateFields.Count -gt 0) {
                                    $fieldList = $updateFields -join ", "
                                    $statementText = "update [$($fieldList)]"
                                }
                            }
                            
                            # Create SQL table node connection (same format as COBOL)
                            $statement = $functionName.Trim().ToLower() + '--"' + $statementText + '"-->sql_' + $sqlTable.Replace(".", "_").Trim() + "[(" + $sqlTable.Trim() + ")]"
                            Write-RexMmd -mmdString $statement
                        }
                        # Skip process node creation when SQL is detected
                        Continue
                    }
                }
                
                # No SQL detected - treat as regular SqlExec command (process node)
                $statement = $functionName.Trim().ToLower() + " --database command-->" + $itemName + "(" + '"' + "DB2 SqlExec Command`n" + $temp1 + '"' + ")"
                Write-RexMmd -mmdString $statement
                Continue
            }
            if ($line.ToLower().contains("'")  ) {
                $temp1 = DecodeQuote($line)
                $temp1 = Get-RexDecodedConcat($temp1)

                $itemName = $functionName.Trim().ToLower() + "_rexx2run" + $uniqueCounter.ToString()
                $rexFilename = $temp1.Trim().ToLower() + ".rex"
                if ($rexFilename.Contains(" ")) {
                    $rexFilename = $temp1.Trim().ToLower().Split(" ")[0] + ".rex"
                }
                $script:htmlCallList += $rexFilename
                $statement = $functionName.Trim().ToLower() + " --start rexx script-->" + $itemName + "[[" + $rexFilename + "]]"
                Write-RexMmd -mmdString $statement

                $link = "./" + $rexFilename + ".html"
                $statement = "click " + $itemName + " " + '"' + $link + '"' + " " + '"' + $itemName + '"' + " _blank"
                Write-RexMmd -mmdString $statement
                $statement = "style " + $itemName + " stroke:dark-blue,stroke-width:4px"
                Write-RexMmd -mmdString $statement
                Continue
            }

            $toNode = $line.Replace('"', "").Replace("'", "").Trim()
            $itemName = $toNode.Trim().ToLower().Replace(" ", "_").Replace(",", "_").Replace("(", "_").Replace(")", "_").TrimEnd("_").Replace("__", "_")
            $statement = $functionName.Trim().ToLower() + " --call-->" + $itemName + "(" + '"' + $toNode.Trim().ToLower() + '"' + ")"
            Write-RexMmd -mmdString $statement
            Continue
        }

        if ($line.ToLower().contains("sysfiledelete")) {
            $pos = $line.ToLower().IndexOf("sysfiledelete")
            $temp = $line.Substring($pos + 13).Replace("(", "").Replace(")", "").Replace('"', "").Replace("'", "").Trim()
            $temp = Get-RexVariableValue($temp)
            $temp = $temp.Replace("(", "").Replace(")", "").Replace('"', "").Replace("'", "").Trim()
            $optionsText = ""
            $toNode = $functionName.Trim().ToLower() + "SysFileDelete" + $uniqueCounter.ToString()
            $optionsText = "rexx command"
            $statement = $functionName.Trim().ToLower() + " --" + $optionsText + "-->" + $toNode + "(" + '"' + "SysFileDelete`n" + $temp.Trim() + '"' + ")"
            Write-RexMmd -mmdString $statement
            Continue
        }
        if (-not ($line.Trim().EndsWith(":") `
                    -or $line.Contains("=") `
                    -or $line.Trim().ToLower().StartsWith("say") `
                    -or $line.Trim().ToLower().StartsWith('":') `
                    -or $line.Trim().ToLower().StartsWith('if ')  `
                    -or $line.Trim().ToLower().StartsWith('parse '))) {
            Write-LogMessage ("Unhandled line in module: " + $baseFileName + ", in function: " + $functionName + ", at line: " + $line.Trim()) -Level WARN
        }

    }
}

function New-RexMmdLinks {
    param (
        $baseFileName, $sourceFile
    )
    try {
        $link = "https://Dedge.visualstudio.com/_git/Dedge?path=/rexx_prod/" + $baseFileName.ToLower()
        $statement = "click " + $baseFileName.ToLower().Split(".")[0] + " " + '"' + $link + '"' + " " + '"' + $baseFileName.ToLower().Split(".")[0] + '"' + " _blank"
        Write-RexMmd -mmdString $statement
        $counter = 0

        foreach ($item in $sourceFile) {
            $line = $item.line
            $counter += 1
            if ($line.Trim().Length -eq 0) {
                # Skip to next element if null
                continue
            }
            if ($line.ToLower().Contains("sjekkfile:")) {
            }
            # if ($counter -gt 39) {
            #
            # }

            if (Test-RexFunction -functionName ($line.Trim())) {
                $line = $line.Replace("--", "-").Replace(":", "").ToLower()
                $link = "https://Dedge.visualstudio.com/_git/Dedge?path=/rexx_prod/" + $baseFileName.ToLower() + "&version=GBmaster&line=" + ($item.LineNumber).ToString() + "&lineEnd=" + ($item.LineNumber + 1).ToString() + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents"
                $statement = "click " + $line + " " + '"' + $link + '"' + " " + '"' + $line + '"' + " _blank"
                Write-RexMmd -mmdString $statement
            }
        }
    }
    catch {
        $errorMessage = $_.Exception
        write-host En feil oppstod: $errorMessage
        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
        Write-LogMessage $errorMessage -Level ERROR
        $script:errorOccurred = $true
    }

}

function Get-RexMetaData {
    param (
        $tmpRootFolder, $baseFileName, $outputFolder, $completeFileContent, $inputDbFileFolder
    )
    try {
        $title = ""
        foreach ($line in $completeFileContent) {
            if ($line -match "[A-Za-z]") {
                $title = $line.Replace("/*", "").Replace("*/", "").Trim()
                break
            }
        }
        $startCommentFound = $false
        $commentArray = @()
        foreach ($line in $completeFileContent) {
            if (($line -match "(19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])" -or $line -match "(0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}" -or $line -match "(19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])") `
                    -and $line.Contains("/*")) {
                $startCommentFound = $true
            }
            if ($startCommentFound -and $line.Contains("*/")) {
                $commentArray += $line.Replace("*/", "").Replace("/*", "").Trim()
            }

            if ($startCommentFound -and -not $line.Contains("/*")) {
                break
            }
        }
        $commentArray2 = @()
        $newComment = ""
        $htmlCreatedDateTime = ""
        foreach ($item in $commentArray) {
            if ($item.Trim().Contains("-----------") -or $item.Trim().Contains("**********") -or $item.Trim().Contains("==========")) {
                break
            }

            if ($item -match "(19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])" -or $item -match "(0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}" -or $item -match "(19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])") {
                if ($newComment.Length -gt 0) {
                    $newComment = $newComment.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
                    $temp = $newComment.Split(" ")
                    if ($htmlCreatedDateTime.Length -eq 0) {
                        $htmlCreatedDateTime = $temp[0]
                    }
                    $tempComment = "<tr><td>" + $temp[0] + "</td><td>" + $temp[1] + "</td><td>"
                    $temp2 = $newComment.Replace($temp[0] + " " + $temp[1], "").Trim()
                    $newComment = $tempComment + $temp2 + "</td></tr>"
                    $commentArray2 += $newComment.Trim()
                }
                $newComment = $item
            }
            else {
                $newComment += " " + $item.Trim()
            }
        }

        if ($newComment.Length -gt 0) {
            $newComment = $newComment.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
            $temp = $newComment.Split(" ")
            $tempComment = "<tr><td>" + $temp[0] + "</td><td>" + $temp[1] + "</td><td>"
            $temp2 = $newComment.Replace($temp[0] + " " + $temp[1], "").Trim()
            $newComment = $tempComment + $temp2 + "</td></tr>"
            $commentArray2 += $newComment.Trim()
        }
        $commentArray = $commentArray2

        $csvModulArray = Import-Csv ($inputDbFileFolder + "\modul.csv") -Header system, delsystem, modul, tekst, modultype, benytter_sql, benytter_ds, fra_dato, fra_kl, antall_linjer, lengde, filenavn -Delimiter ';'
        $cblArray = @()
        foreach ($item in $script:htmlCallListCbl) {
            $descArray = $csvModulArray | Where-Object { $_.modul.Contains($item.Replace(".cbl", "").ToUpper()) }
            if ($descArray.Length -eq 0) {
                $cblSystem = "N/A"
                $cblDesc = "N/A"
                $cblType = "N/A"
            }
            else {
                $temp = $descArray[0]
                $cblSystem = $temp.delsystem.Trim()
                $cblDesc = $temp.tekst.Trim()
                $cblType = $temp.modultype.Trim()

                if ($cblType -eq "B") {
                    $cblType = "B - Batchprogram"
                }
                elseif ($cblType -eq "H") {
                    $cblType = "H - Main user interface"
                }
                elseif ($cblType -eq "S") {
                    $cblType = "S - Webservice"
                }
                elseif ($cblType -eq "V") {
                    $cblType = "V - Validation module for user interface"
                }
                elseif ($cblType -eq "A") {
                    $cblType = "A - Common module"
                }
                elseif ($cblType -eq "F") {
                    $cblType = "F - Search module for user interface"
                }
            }

            $link = "<a href=" + '"' + "./" + $item.Trim() + ".html" + '"' + ">" + $item.Trim() + "</a>"
            $tempComment = "<tr><td>" + $link + "</td><td>" + $cblDesc + "</td><td>" + $cblType + "</td><td>" + $cblSystem + "</td></tr>"

            $cblArray += $tempComment
        }

        $scriptArray = @()
        foreach ($item in $script:htmlCallList) {
            $link = "<a href=" + '"' + "./" + $item.Trim() + ".html" + '"' + ">" + $item.Trim() + "</a>"
            $tempComment = "<tr><td>" + $link + "</td></tr>"
            $scriptArray += $tempComment
        }

        $htmlDesc = $title.Trim()
        $htmlType = "Object Rexx Script"
        $temp = $completeFileContent | Select-String -Pattern @("sqlexec")
        $htmlUseSql = ""
        if ($temp.Length -gt 0) {
            $htmlUseSql = "checked"
        }
        $temp = $completeFileContent | Select-String -Pattern @("ftpsetuser")
        $htmlUseFtp = ""
        if ($temp.Length -gt 0) {
            $htmlUseFtp = "checked"
        }

    }
    catch {
        $errorMessage = $_.Exception
        write-host En feil oppstod: $errorMessage
        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
        Write-LogMessage $errorMessage -Level ERROR
        $script:errorOccurred = $true
    }
    finally {
        $htmlFilename = $outputFolder + "\" + $baseFileName + ".html"
        
        # Use template from OutputFolder\_templates (copied at startup by AutoDocBatchRunner)
        $templatePath = Join-Path $outputFolder "_templates"
        $mmdTemplateFilename = Join-Path $templatePath "rexmmdtemplate.html"

        $myDescription = "AutoDoc Flowchart - Object Rexx Script - " + $baseFileName.ToLower()

        $tmpl = Get-Content -Path $mmdTemplateFilename -Raw -Encoding UTF8
        # Apply shared CSS and common URL replacements
        $doc = Set-AutodocTemplate -Template $tmpl -OutputFolder $outputFolder
        $doc = $doc.Replace("[title]", $myDescription)
        $doc = $doc.Replace("[desc]", $title)
        $doc = $doc.Replace("[generated]", (Get-Date).ToString())
        $doc = $doc.Replace("[type]", $htmlType)
        $doc = $doc.Replace("[usesql]", $htmlUseSql)
        $doc = $doc.Replace("[useftp]", $htmlUseFtp)
        $doc = $doc.Replace("[created]", $htmlCreatedDateTime)
        $doc = $doc.Replace("[changelog]", $commentArray)
        $doc = $doc.Replace("[calllist]", $scriptArray)
        $doc = $doc.Replace("[calllistcbl]", $cblArray)
        $doc = $doc.Replace("[diagram]", "./" + $baseFileName + ".flow.svg" )
        $doc = $doc.Replace("[sourcefile]", $baseFileName.ToLower())
        
        # For client-side rendering, embed MMD content directly
        if ($ClientSideRender) {
            $flowMmdContent = ""
            # IN-MEMORY: Get content from ArrayList instead of file
            if ($script:useClientSideRender) {
                $flowMmdContent = $script:mmdFlowContent -join "`n"
            }
            elseif (Test-Path -Path $script:mmdFilename -PathType Leaf) {
                $flowMmdContent = Get-Content -Path $script:mmdFilename -Raw -ErrorAction SilentlyContinue
            }
            $doc = $doc.Replace("[flowmmd_content]", $flowMmdContent)
            $doc = $doc.Replace("[sequencemmd_content]", "")  # REX doesn't have sequence diagrams
        }
        
        set-content -Path $htmlFilename -Value $doc
    }

}

function Write-RexMmd ($mmdString) {
    # OPTIMIZED: Replace literal newlines with <br/> for Mermaid compatibility
    $mmdString = $mmdString -replace "`n", "<br/>" -replace "`r", ""
    $mmdString = $mmdString.Replace("__MAIN__", "main").Replace("__main__", "main")
    $mmdString = $mmdString -replace '\s{2,}', ' '  # OPTIMIZED: Single regex for multiple spaces
    
    # Add to flow content (in-memory or file)
    if (-not $script:duplicateLineCheck.Contains($mmdString)) {
        if ($script:useClientSideRender) {
            [void]$script:mmdFlowContent.Add($mmdString)
        }
        else {
            Add-Content -Path $script:mmdFilename -Value $mmdString -Force
        }
        [void]$script:duplicateLineCheck.Add($mmdString)
    }
}

function Find-RexFunctionCode {
    param ($array, [string] $functionName)
    # Regular expression patterns

    # Initialize variables
    $foundStart = $false
    try {
        $functionName = $functionName.ToLower()
    }
    catch {
    }

    $extractedElements = @()

    $lineNumber = 0
    # Loop through the array
    foreach ($objectItem in $array) {
        $item = $objectItem.Line
        $lineNumber += 1

        if ($item.Trim().StartsWith($functionName.ToUpper() + ":")) {
            $foundStart = $true
            $extractedElements = @()
        }
        elseif ($foundStart) {
            if (Test-RexFunction -functionName $item) {
                # if ($item -match $endPattern) {
                $foundStart = $false
                break
            }
            else {
                $extractedElements += $item
            }
        }
    }
    return $extractedElements
}


<#
.SYNOPSIS
    Object Rexx Parser Functions Module for AutoDoc.

.DESCRIPTION
    Contains the Start-RexParse entry point function that orchestrates
    Object Rexx file parsing and AutoDoc HTML generation.

.AUTHOR
    Geir Helge Starholm, www.dEdge.no

.NOTES
    Migrated to AutodocFunctions module - 2026-01-19
#>

function Start-RexParse {
    <#
    .SYNOPSIS
        Main entry point for Object Rexx file parsing.
    
    .DESCRIPTION
        Parses Object Rexx script files and generates AutoDoc HTML documentation
        with Mermaid flowchart diagrams.
    
    .PARAMETER SourceFile
        Path to the .rex file to parse.
    
    .PARAMETER Show
        If true, opens the generated HTML file after creation.
    
    .PARAMETER OutputFolder
        Output folder for generated files.
    
    .PARAMETER CleanUp
        If true, cleans up temporary files after processing.
    
    .PARAMETER TmpRootFolder
        Root folder for temporary files.
    
    .PARAMETER SrcRootFolder
        Root folder for source files.
    
    .PARAMETER ClientSideRender
        Skip SVG generation and use client-side Mermaid.js rendering.
    
    .PARAMETER SaveMmdFiles
        Save Mermaid diagram source files (.mmd) alongside the HTML output.
    
    .OUTPUTS
        Path to the generated HTML file, or $null on error.
    
    .EXAMPLE
        Start-RexParse -SourceFile "C:\scripts\myscript.rex" -OutputFolder "C:\output"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [bool]$Show = $false,
        [string]$OutputFolder = "$env:OptPath\Webs\AutoDoc",
        [bool]$CleanUp = $true,
        [string]$TmpRootFolder = "$env:OptPath\data\AutoDoc\tmp",
        [string]$SrcRootFolder = "$env:OptPath\data\AutoDoc\src",
        [switch]$ClientSideRender,
        [switch]$SaveMmdFiles
    )
    
    # Initialize script-level variables
    $script:sequenceNumber = 0
    $baseFileName = [System.IO.Path]::GetFileName($SourceFile)
    
    Write-LogMessage ("Starting parsing of filename:" + $SourceFile) -Level INFO
    
    # Check if the filename contains spaces
    if ($baseFileName.Contains(" ")) {
        Write-LogMessage ("Filename is not valid. Contains spaces:" + $baseFileName) -Level ERROR
        return $null
    }
    
    # Check if the filename match the purpose of the script
    if (-Not $baseFileName.ToLower().Contains(".rex")) {
        Write-LogMessage ("Filetype is not valid for parsing of Object-Rexx script (.rex):" + $baseFileName) -Level ERROR
        return $null
    }
    
    # IN-MEMORY MMD ACCUMULATION
    $StartTime = Get-Date
    $script:logFolder = $OutputFolder
    $script:mmdFilename = $OutputFolder + "\" + $baseFileName + ".flow.mmd"
    $script:debugFilename = $OutputFolder + "\" + $baseFileName + ".debug"
    $svgFilename = $OutputFolder + "\" + $baseFileName + ".flow.svg"
    $htmlFilename = $OutputFolder + "\" + $baseFileName + ".html"
    $script:errorOccurred = $false
    $script:sqlTableArray = @()
    $inputDbFileFolder = $TmpRootFolder + "\cobdok"
    $script:duplicateLineCheck = [System.Collections.Generic.HashSet[string]]::new()
    
    # IN-MEMORY: Use ArrayList for thread-safe accumulation
    $script:mmdFlowContent = [System.Collections.ArrayList]::new()
    $script:useClientSideRender = $ClientSideRender
    
    Write-LogMessage ("Started for :" + $baseFileName) -Level INFO
    
    # Initialize MMD with flowchart header
    $mmdHeader = @"
%%{ init: { 'flowchart': { 'curve': 'basis' } } }%%
flowchart LR
"@
    
    if ($script:useClientSideRender) {
        [void]$script:mmdFlowContent.Add($mmdHeader)
    }
    else {
        Set-Content -Path $script:mmdFilename -Value $mmdHeader -Force
    }
    
    $programName = [System.IO.Path]::GetFileName($SourceFile.ToLower())
    $script:baseFileNameTemp = $baseFileName
    
    if (Test-Path -Path $SourceFile -PathType Leaf) {
        $fileContentOriginal = Get-Content $SourceFile -Encoding ([System.Text.Encoding]::GetEncoding(1252))
        $completeFileContent = $fileContentOriginal
        $test = $fileContentOriginal -join "¤"
        
        # Remove content between /* and */
        $pattern = "/\*.*?\*/"
        $test = $test -replace $pattern, ""
        $fileContentOriginal = $test.Split("¤")
    }
    else {
        Write-LogMessage ("File not found:" + $SourceFile) -Level ERROR
        return $null
    }
    
    $fileContent = @()
    $fileContent = $fileContentOriginal
    
    # Extract all relevant code content
    $workContent2 = @()
    $workContent = @()
    $workContent2 = $fileContentOriginal | Select-String -Pattern @("^.*:", "call\s*", "SysFileDelete", "'RUN" , "'REXX", "'START ", "'DB2", "'COPY", "'REN", "FtpLogoff", "ftpput", "ftpget", "ftpdel" , "if ")
    
    # Extract the first match (if any)
    $obj = New-Object PSObject
    if ($workContent2.Count -gt 0) {
        $obj | Add-Member -Type NoteProperty -Name "LineNumber" -Value 1
        $obj | Add-Member -Type NoteProperty -Name "Line" -Value "__MAIN__:"
        $obj | Add-Member -Type NoteProperty -Name "Pattern" -Value "^.*:"
        $workContent += $obj
    }
    $workContent += $workContent2
    
    # Create a list of all functions
    $functions = @()
    $functionsList = @()
    if ($workContent.Count -gt 0) {
        $functionsList += $obj.Line.ToUpper().Replace(":", "").Trim()
    }
    $functionsList += $fileContentOriginal | Where-Object { $_ -match "^.*:$" } | ForEach-Object { $_.Trim().Replace(":", "").ToUpper() }
    $script:functions = $functionsList
    
    # Create a dictionary of all assigned variables
    $assignments = $fileContentOriginal | Where-Object { $_ -match "=" -and $_ -notmatch "if" }
    $script:assignmentsDict = @{}
    foreach ($line in $assignments) {
        $temp = $line -split "="
        $key = $temp[0].Trim().ToUpper()
        try {
            $script:assignmentsDict[$key] = $temp[1].Trim().Replace('"', "'")
        }
        catch { }
    }
    
    $fdHashtable = @{}
    $script:htmlCallListCbl = @()
    $script:htmlCallList = @()
    $currentParticipant = ""
    $currentFunctionName = ""
    
    $loopCounter = 0
    $previousParticipant = ""
    $counter = 0
    $functionCodeExceptLoopCode = { }.Invoke()
    $counter = 0
    
    # Loop through all workContent
    foreach ($lineObject in $workContent) {
        $counter += 1
        $line = $lineObject.Line
        $lineNumber = $lineObject.LineNumber
        $counter += 1
        
        # Function handling
        $previousParticipant = $currentFunctionName
        
        # Check if line is a function
        if (Test-RexFunction -functionName ($line)) {
            if ($functionCodeExceptLoopCode.Count -gt 0) {
                $loopCounter = 0
                New-RexNodes -functionCode $functionCodeExceptLoopCode -fileContent $fileContent -functionName $previousParticipant -fdHashtable $fdHashtable -loopCounter $loopCounter
            }
            
            $pos = $line.IndexOf(":")
            $currentParticipant = $line.Substring(0, $pos).Trim()
            $currentFunctionName = $currentParticipant.Trim()
            $functionCode = Find-RexFunctionCode -array $workContent -functionName $currentParticipant
            
            $loopLevel = { }.Invoke()
            $loopNodeContent = { }.Invoke()
            $loopCode = { }.Invoke()
            $functionCodeExceptLoopCode = { }.Invoke()
            
            # Handling program name to initial function
            if ($previousParticipant.Length -eq 0 -and $currentParticipant.Length -gt 0) {
                $statement = $programName.Trim().ToLower() + "[[" + $programName.Trim().ToLower() + "]]" + " --initiated-->" + $currentParticipant.Trim().ToLower() + "(" + $currentParticipant.Trim().ToLower() + ")"
                Write-RexMmd -mmdString $statement
                $statement = "style " + $programName.Trim().ToLower() + " stroke:red,stroke-width:4px"
                Write-RexMmd -mmdString $statement
                
                $link = "https://Dedge.visualstudio.com/_git/Dedge?path=/rexx_prod/" + $baseFileName.ToLower()
                $statement = "click " + $programName.Trim().ToLower() + " " + '"' + $link + '"' + " " + '"' + $programName.Trim().ToLower() + '"' + " _blank"
                Write-RexMmd -mmdString $statement
            }
        }
        
        if ($functionCode.Count -eq 0) {
            Continue
        }
        
        $skipLine = $false
        # Perform handling
        if ($line.trim().ToLower().contains("do ") -and ($line.trim().ToLower().contains(" while") -or $line.trim().ToLower().contains(" until"))) {
            $loopCounter += 1
            if ($loopCounter -gt 1) {
                $fromNode = $loopLevel[($loopCounter - 2)]
                $toNode = $loopLevel[($loopCounter - 2)] + $loopCounter + "((" + $loopLevel[($loopCounter - 2)] + $loopCounter + "))"
                $loopLevel.Add($currentParticipant + "-loop" + $loopCounter)
            }
            else {
                $fromNode = $currentParticipant
                $toNode = $currentParticipant + "-loop" + "((" + $currentParticipant + "-loop))"
                $loopLevel.Add($currentParticipant + "-loop")
            }
            $loopNodeContent.Add($toNode)
            $loopCode.Add("")
            $statement = $fromNode + "--" + '"' + "call " + '"' + "-->" + $toNode
            
            Write-RexMmd -mmdString $statement
            $skipLine = $true
        }
        else {
            if ($loopCounter -gt 0 -and $line.trim().tolower().StartsWith(("end"))) {
                $workCode = $loopCode[$loopCounter - 1]
                New-RexNodes -functionCode $loopCode[$loopCounter - 1] -fileContent $fileContent -functionName ($loopLevel[$loopCounter - 1]) -fdHashtable $fdHashtable -currentLoopCounter $loopCounter
                
                $loopLevel.RemoveAt($loopCounter - 1)
                $loopNodeContent.RemoveAt($loopCounter - 1)
                $loopCode.RemoveAt($loopCounter - 1)
                $loopCounter -= 1
                $skipLine = $true
            }
        }
        
        # Accumulate lines
        if ($skipLine -eq $false) {
            if ($loopCounter -gt 0) {
                $workCode = { }.Invoke()
                if ($loopCode[$loopCounter - 1].Length -gt 0) {
                    $workCode = $loopCode[$loopCounter - 1]
                }
                $workCode.Add($lineObject)
                $loopCode[$loopCounter - 1] = $workCode
            }
            else {
                $functionCodeExceptLoopCode.Add($lineObject)
            }
        }
    }
    
    $loopCounter = 0
    
    # Generate nodes for last function
    New-RexNodes -functionCode $functionCodeExceptLoopCode -fileContent $fileContent -functionName $currentFunctionName -fdHashtable $fdHashtable -loopCounter $loopCounter
    
    # Generate links to sourcecode in Azure DevOps
    New-RexMmdLinks -baseFileName $baseFileName -sourceFile $workContent
    
    # Generate execution path diagram
    Get-RexExecutionPathDiagram -srcRootFolder $SrcRootFolder -baseFileName $baseFileName -tmpRootFolder $TmpRootFolder
    
    # Generate SVG file from mmd content (skip when using client-side rendering)
    if (-not $ClientSideRender) {
        GenerateSvgFile -mmdFilename $script:mmdFilename
    }
    
    # Handle what to generate
    if (-not $script:errorOccurred) {
        Get-RexMetaData -tmpRootFolder $TmpRootFolder -outputFolder $OutputFolder -baseFileName $baseFileName -completeFileContent $completeFileContent -inputDbFileFolder $inputDbFileFolder
        
        if ($Show) {
            & $htmlFilename
        }
    }
    
    $endTime = Get-Date
    $timeDiff = $endTime - $StartTime
    
    # Save MMD files if requested
    if ($SaveMmdFiles) {
        if ($script:mmdFlowContent -and $script:mmdFlowContent.Count -gt 0) {
            $flowMmdOutputPath = Join-Path $OutputFolder ($baseFileName + ".mmd")
            $script:mmdFlowContent | Set-Content -Path $flowMmdOutputPath -Force
            Write-LogMessage ("Saved flow MMD file: $flowMmdOutputPath") -Level INFO
        }
    }
    
    # Log result
    $dummyFile = $OutputFolder + "\" + $baseFileName + ".err"
    $htmlFilename = $OutputFolder + "\" + $baseFileName + ".html"
    $htmlWasGenerated = Test-Path -Path $htmlFilename -PathType Leaf
    
    if ($htmlWasGenerated) {
        if (Test-Path -Path $dummyFile -PathType Leaf) {
            Remove-Item -Path $dummyFile -Force -ErrorAction SilentlyContinue
        }
        if ($script:errorOccurred) {
            Write-LogMessage ("Time elapsed: " + $timeDiff.Seconds.ToString()) -Level INFO
            Write-LogMessage ("Completed with warnings:" + $baseFileName) -Level WARN
        }
        else {
            Write-LogMessage ("Time elapsed: " + $timeDiff.Seconds.ToString()) -Level INFO
            Write-LogMessage ("Completed successfully:" + $baseFileName) -Level INFO
        }
        return $htmlFilename
    }
    else {
        Write-LogMessage ("*******************************************************************************") -Level ERROR
        Write-LogMessage ("Failed - HTML not generated:" + $SourceFile) -Level ERROR
        Write-LogMessage ("*******************************************************************************") -Level ERROR
        "Error: HTML file was not generated for $baseFileName" | Set-Content -Path $dummyFile -Force
        return $null
    }
}

#endregion

#region Cbl Parse Functions
# OPTIMIZED: Precompiled regex for COBOL end verbs
$script:endVerbPattern = [regex]::new('\b(end-accept|end-add|end-call|end-compute|end-delete|end-display|end-divide|end-evaluate|end-exec|end-if|end-multiply|end-perform|end-read|end-receive|end-return|end-rewrite|end-search|end-start|end-string|end-subtract|end-write)\b', [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

function ContainsCobolEndVerb {
    param($sourceLine)
    
    if ($null -eq $sourceLine) {
        return $false, $false, "", -1
    }
    
    $match = $script:endVerbPattern.Match($sourceLine)
    if ($match.Success) {
        $endverb = $match.Value.ToLower()
        $startWithEndVerb = $sourceLine.Trim().ToLower().StartsWith($endverb)
        return $true, $startWithEndVerb, $endverb, $match.Index
    }
    
    return $false, $false, "", -1
}

# OPTIMIZED: Precompiled regex for COBOL verbs
$script:verbPattern = [regex]::new('\b(accept|add|alter|call|cancel|close|commit|compute|continue|delete|display|divide|entry|evaluate|exec|exhibit|exit|generate|goback|go to|if|initialize|inspect|invoke|merge|move|multiply|open|perform|read|release|return|rewrite|rollback|search|set|sort|start|stop run|string|subtract|unstring|write)\b', [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

function ContainsCobolVerb {
    param($sourceLine)
    
    if ($null -eq $sourceLine) {
        return $false, $false, "", -1
    }
    
    $match = $script:verbPattern.Match($sourceLine)
    if ($match.Success) {
        $verb = $match.Value.ToLower()
        $startWithVerb = $sourceLine.Trim().ToLower().StartsWith($verb)
        return $true, $startWithVerb, $verb, $match.Index
    }
    
    return $false, $false, "", -1
}

function PreProcessFileContent {
    param($fileContentOriginal)

    $declarativesContent = @()
    $procedureContent = @()
    $procedureCodeContent = @()
    $fileSectionContent = @()

    $fileSectionLineNumber = 0
    $workingStorageLineNumber = 0
    $procedureDivisionLineNumber = 0
    $firstParagraphLinenumber = 0

    $workArray = @()
    $counter = 0

    foreach ($line in $fileContentOriginal) {
        $ustart = $line.IndexOf("*>")
        if ($ustart -gt 0) {
            # Removes comment at end of line
            $line = $line.Substring(0, $ustart)
        }

        if ($line.Trim().Length -eq 0) {
            # Skip to next element if null
            continue
        }
        if ($line.Length -le 6) {
            # Skip to next element only room for linenumbers from 0..6
            continue
        }

        if ($line.Trim().Substring(0, 1) -eq "*") {
            # Skip to next element
            continue
        }

        $line = $line.ToString().ToLower().Substring(6)
        if ($line.Trim().Length -eq 0) {
            # Skip to next element if null aftger removing first 6 characthers
            continue
        }

        # we are not skipping line, so increase counter
        $counter += 1

        $line = $line.ToString().ToLower().Trim()

        if ($line -match "procedure.*division" -or $line -match "procedure.division" ) {
            $procedureDivisionLinenumber = $counter
        }

        if ($line -match ".*M[0-9]+\-.*\." -and $firstParagraphLinenumber -eq 0) {
            $firstParagraphLinenumber = $counter
        }

        if ($procedureDivisionLinenumber -eq 0) {
            $declarativesContent += $line
        }
        else {
            $procedureContent += $line
        }

        if ($procedureDivisionLinenumber -gt 0 -and $firstParagraphLinenumber -eq 0 ) {
            $procedureCodeContent += $line
        }

        if ($line -match ".*M[0-9]+\-.*\." -and $firstParagraphLinenumber -eq 0) {
            $firstParagraphLinenumber = $counter
        }

        if ($line -match "file section" ) {
            $fileSectionLineNumber = $counter
        }

        if ($line -match "working-storage" ) {
            $workingStorageLineNumber = $counter
        }

        if ($fileSectionLineNumber -gt 0 -and $workingStorageLineNumber -eq 0) {
            $fileSectionContent += $line
        }

        $workArray += $line

    }

    $workArray1 = @()
    $counter = -1
    $isInlinePerform = $false
    $inlinePerformParagraph = ""
    $accumulatedExpression = ""
    $procedureDivisionLinenumber = 0
    $procedureDivisionPeriodLinenumber = 0
    $firstParagraphLinenumber = 0

    while ($workArray.Count -gt $counter) {
        $counter += 1
        $line = $workArray[$counter]
        if ($null -eq $line) {
            continue
        }

        if ($line -match "procedure.*division" -or $line -match "procedure.division" ) {
            $procedureDivisionLinenumber = $counter
        }

        # if ( $line.Contains("fetch c_fknr")) {
        # if ( $counter -gt 263 ) {
        #     Write-Host "A:" $accumulatedExpression " L:"  $line
        #
        # }
        if ($counter -gt $procedureDivisionLinenumber -and $procedureDivisionLinenumber -gt 0 -and $procedureDivisionPeriodLinenumber -gt 0) {
            $containsCobolVerb, $verbAtStartOfLine, $verb, $verbPos = ContainsCobolVerb -sourceLine $line
            $containsEndVerb, $startWithEndVerb, $endverb, $endVerbPos = ContainsCobolEndVerb -sourceLine $line

            $verifiedParagraph = $false
            $verifiedParagraph = VerifyIfParagraph -paragraphName ($line.Trim())
            if ($verifiedParagraph -and $firstParagraphLinenumber -eq 0 -and $procedureDivisionLinenumber -gt 0) {
                $firstParagraphLinenumber = $counter
            }

            if ($line.trim() -eq "." -or $containsCobolVerb -or $containsEndVerb -or $accumulatedExpression.Trim() -eq ".") {
                if ($line.trim() -eq "perform") {
                }

                if ($accumulatedExpression.Length -gt 0) {
                    if (($accumulatedExpression.Contains("perform") -and $accumulatedExpression.Contains("until")) -or ($accumulatedExpression.Contains("perform") -and $line.StartsWith("exec"))) {
                        if ($accumulatedExpression.Contains("perform") -and $line.StartsWith("exec") -and -not $accumulatedExpression.Contains("end-perform")) {
                            # LogMessage -message ("  > Substituted :" + $accumulatedExpression + " with perform until")
                            $accumulatedExpression = "perform until"
                        }
                        else {
                            $tempStr = $accumulatedExpression.Replace("perform", "").Trim()
                            $pos = $tempStr.IndexOf(" ")
                            if ($pos -gt 0) {
                                $inlinePerformParagraph = ($tempStr.Split(" "))[0]
                                $bool = VerifyIfParagraph -paragraphName ($inlinePerformParagraph.Trim())
                                if ($bool) {
                                    $isInlinePerform = $true
                                }
                                else {
                                    $inlinePerformParagraph = ""
                                    $isInlinePerform = $false
                                }
                            }
                        }

                    }
                    if ($isInlinePerform) {
                        $accumulatedExpression = $accumulatedExpression.Replace($inlinePerformParagraph, "")
                        $accumulatedExpression = $accumulatedExpression.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
                        $tempArray = @()

                        $tempArray += $accumulatedExpression.Trim()
                        $tempArray += "perform " + $inlinePerformParagraph
                        $tempArray += "end-perform "
                        $workArray1 += $tempArray

                        $procedureCodeContent += $tempArray

                        if ($counter -gt $procedureDivisionLinenumber -and $firstParagraphLinenumber -eq 0 ) {
                            $procedureContent += $tempArray
                            # add-Content -Path $global:debugFilename -Value $tempArray

                        }
                    }
                    else {
                        # if ($procedureContent.Count -gt 67) {
                        #
                        #     Write-Host "A:" $accumulatedExpression " L:"  $line
                        # }
                        # if ($accumulatedExpression.Contains("fetch c_fknr")) {
                        #
                        # }
                        $containsEndVerb, $startWithEndVerb, $endverb, $endVerbPos = ContainsCobolEndVerb -sourceLine $accumulatedExpression.Trim()
                        $tempArray = @()
                        if ($containsEndVerb -and !$startWithEndVerb) {
                            $tempArray += $accumulatedExpression.Substring(0, $endVerbPos - 1).Trim()
                            $tempArray += $accumulatedExpression.Substring(($endVerbPos - 1))
                        }
                        else {
                            $tempArray += $accumulatedExpression.Trim()
                        }
                        $workArray1 += $tempArray

                        $procedureCodeContent += $tempArray
                        if ($counter -gt $procedureDivisionLinenumber -and $firstParagraphLinenumber -eq 0 ) {
                            $procedureContent += $tempArray
                            # add-Content -Path $global:debugFilename -Value $tempArray
                        }

                    } #if ($isInlinePerform)
                } #if ($accumulatedExpression.Length -gt 0)
                $isInlinePerform = $false
                $inlinePerformParagraph = ""
                $accumulatedExpression = ""
            } #if ($line.trim() -eq "." -or $containsCobolVerb -or $containsEndVerb -or $accumulatedExpression.Trim() -eq ".")

            $accumulatedExpression += " " + $line.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
            $accumulatedExpression = $accumulatedExpression.trim()

        }
        else {
            if ($procedureDivisionLinenumber -gt 0 -and $procedureDivisionPeriodLinenumber -eq 0 -and $line.Contains(".")) {
                $procedureDivisionPeriodLinenumber = $counter
            }

            $workArray1 += $line.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
        }#if ($counter -gt $procedureDivisionLinenumber -and $procedureDivisionLinenumber -gt 0 )
    } #while ($workArray.Count -gt $counter)

    if ($accumulatedExpression.Length -gt 0) {
        $workArray1 += $accumulatedExpression
    }

    $workArray = $workArray1
    # Set-Content -Path ".\workArraydebug.txt" -Value $workArray
    # Set-Content -Path ".\procedureCodeContentArraydebug.txt" -Value $procedureCodeContent

    if ($procedureDivisionLinenumber -gt 0 -and $firstParagraphLinenumber -eq 0 ) {
        $procedureCodeContent = $procedureContent
    }
    return $workArray, $procedureCodeContent, $fileSectionLineNumber, $workingStorageLineNumber, $fileSectionContent

}

function Get-CblExecutionPathDiagram {
    param($srcRootFolder, $baseFileName, $tmpRootFolder)

    if ($baseFileName.ToLower().Contains("gmacoco") `
            -or $baseFileName.ToLower().Contains("gmacnct") `
            -or $baseFileName.ToLower().Contains("gmalike") `
            -or $baseFileName.ToLower().Contains("gmacurt") `
            -or $baseFileName.ToLower().Contains("gmftrap") `
            -or $baseFileName.ToLower().Contains("gmffell") `
            -or $baseFileName.ToLower().Contains("gmadato") `
            -or $baseFileName.ToLower().Contains("gmfsql" )) {
        return
    }

    $pos = $baseFileName.IndexOf(".")
    $baseFileName = $baseFileName.Substring(0, $pos).ToLower()
    $inputDbFileFolder = $tmpRootFolder + "\cobdok"

    $programInUse = $false
    $resultArrayMmd = @()

    # Get data from cobdok_meny.csv - Start
    if ($baseFileName.ToUpper().Substring(2, 1) -eq "H") {
        $descArray = $null
        $csvCopyArray = $null
        $csvCopyArray = Import-Csv ($inputDbFileFolder + "\cobdok_meny.csv") -Header funksjon, tekst, system, beskrivelse, ansvarlig, organisasjon, url_brukerdok, url_brukerdok_meny -Delimiter ';'

        try {
            $descArray = $csvCopyArray | Where-Object { $_.funksjon.Contains(($baseFileName.ToUpper().ToUpper().trim()) ) }
        }
        catch {
            $descArray = $null
        }

        if ($descArray.Count -gt 0) {
            $descArray = $descArray | Sort-Object

            $counter = 0
            foreach ($item in $descArray) {
                $counter += 1
                $menuSystem = $item.system.Trim()
                $menuText = $item.tekst.Trim()
                $menuText = "System:" + $menuSystem + "`n" + "Choice:" + $menuText
                $menuDesc = $item.beskrivelse.Trim()
                if ($menuDesc.length -gt 0) {
                    $menuText += "`n" + "Description:" + $menuDesc.Replace('"', "").Replace("'", "")
                }
                $programInUse = $true

                $resultArrayMmd += ("menuitem" + $counter.ToString() + "(" + '"' + $menuText + '"' + ")" + "-.->" + $baseFileName)
                $resultArrayMmd += ("style menuitem" + $counter.ToString() + " stroke-dasharray: 5 5")
            }
        }
    }
    # Get data from cobdok_meny.csv - End
    $returnMmdArray = @()
    if ($baseFileName.ToUpper().Substring(2, 1) -eq "B") {
        $returnMmdArray2 = @()
        $includeFilter = "*.ps1", "*.bat", "*.rex"
        $programInUse, $returnMmdArray2 = IsExecutedFromAny -findpath $srcRootFolder -includeFilter $includeFilter -filename $baseFileName -programInUse $programInUse -srcRootFolder $srcRootFolder
        $returnMmdArray += $returnMmdArray2
    }

    if ($baseFileName.ToUpper().Substring(2, 1) -eq "V" -or $baseFileName.ToUpper().Substring(2, 1) -eq "A" -or $baseFileName.ToUpper().Substring(2, 1) -eq "F") {
        $returnMmdArray2 = @()
        $programInUse, $returnMmdArray2 = IsExecutedFromAny -findpath ($srcRootFolder + "\Dedge\cbl\") -includeFilter "*.cbl" -filename $baseFileName -programInUse $programInUse -srcRootFolder $srcRootFolder
        $returnMmdArray += $returnMmdArray2
    }

    if ($baseFileName.ToUpper().Substring(2, 1) -eq "H") {
        $returnMmdArray2 = @()
        $programInUse, $returnMmdArray2 = IsExecutedFromAny -findpath ($srcRootFolder + "\Dedge\bat_prod\") -includeFilter "*.bat" -filename $baseFileName -programInUse $programInUse -srcRootFolder $srcRootFolder
        $returnMmdArray += $returnMmdArray2
    }

    foreach ($item in $returnMmdArray) {
        WriteMmdFlow -mmdString $item
    }

    If (!$programInUse) {
        Write-LogMessage ("Program is never called from any other program or script: " + $baseFileName) -Level INFO
    }

    foreach ($item in $resultArrayMmd) {
        WriteMmdFlow -mmdString $item
    }

}

function VerifyIfParagraph {
    param(
        $paragraphName
    )
    $isValidParagraph = $false

    if ($paragraphName.StartsWith("m090") -and $paragraphName.Length -gt 4) {
    }
    $paragraphName = $paragraphName.ToString().ToLower().Trim().Replace(" .", ".").Trim().Replace(" .", ".").Trim().Replace(" .", ".").Trim().Replace(" .", ".").Trim().Replace(" .", ".").Trim().Replace(" .", ".").Trim().Replace(" .", ".").Trim().Replace(" .", ".").Trim().Replace(" .", ".")
    if (-Not $paragraphName.Contains(" ") -and ($paragraphName.Length - 1) -eq $paragraphName.indexOf(".") -and $paragraphName.Length -gt 1) {
        $isValidParagraph = $true
    }

    # if ($paragraphName.IndexOf(" ") -gt 0) {
    #     $paragraphName = $paragraphName.Substring(0, ($paragraphName.IndexOf(" ") - 1))
    # }

    # try {
    #     if ($paragraphName.Length -gt 4) {
    #         $testInt = [int]$paragraphName.Substring(1, 3)
    #         $isValidParagraph = $true
    #     }
    # }
    # catch {
    #     $isValidParagraph = $false
    # }
    return $isValidParagraph
}

function New-CblNodes {
    param (
        $paragraphCode, $procedureContent, $fileContent , $paragraphName, $fdHashtable, $currentLoopCounter
    )
    $isSqlCodeInParagraphHandled = $false

    $accumulatedParagraphCode = @()
    $skipLine = $false
    $contentFromLineNumber = 0

    foreach ($lineObject in $paragraphCode) {
        $line = $lineObject.Line
        # LogMessage -message ("paragraphName " + $paragraphName + ": " + $lineObject.LineNumber )

        if ($line.Length -eq 0) {
            continue
        }
        if ($line.trim().contains("perform until") -or $line.trim().contains("perform varying") -or $line.trim().contains("until") -or ($line.trim().contains("perform") -and $line.trim().contains(" times") ) -or $line.ToLower().trim().contains("perform with test before")) {
            $skipLine = $true
            Write-LogMessage ("Skipped perform until. Should not be here. Linenumber: " + $lineObject.LineNumber) -Level WARN
            continue
        }

        if ($line.contains("end-perform")) {
            $skipLine = $false
            Write-LogMessage ("Skipped end-perform. Should not be here. Linenumber: " + $lineObject.LineNumber) -Level WARN
            continue
        }

        if ($skipLine) {
            continue
        }

        if ($contentFromLineNumber -eq 0) {
            $contentFromLineNumber = $lineObject.LineNumber
        }

        if ($lineObject.LineNumber -gt $contentFromLineNumber) {
            $accumulatedParagraphCode += $procedureContent[($contentFromLineNumber - 1)..($lineObject.LineNumber - 1)]
            $contentFromLineNumber = $lineObject.LineNumber + 1
        }

        # Handle perform statements
        $lastLineNumber = $lineObject.LineNumber
        if ($line.trim().contains("perform") -and !$line.trim().contains("exit") -and !$line.trim().contains("-perform") ) {
            $pos = $line.IndexOf("perform")
            $toNode = $line.Substring($pos + "perform".Length).Trim().Replace(".", "")

            if ($toNode.Contains(" ")) {
                $pos = $toNode.IndexOf(" ")
                $toNode = $toNode.Substring(0, $pos)
            }
            if ($toNode.Contains("=")) {
            }

            if ($loopCounter -gt 0) {
                $fromNode = $loopNodeContent[$loopNodeContent.Count - 1]
            }
            else {
                $fromNode = $paragraphName + "(" + $paragraphName + ")"
            }

            if ($toNode -eq $fromNode -or $toNode.Length -eq 0 -or $fromNode.Length -eq 0) {
                # Skip if self reference
                continue
            }
            $statement = $fromNode + "--" + '"' + "perform" + '"' + "-->" + $toNode + "(" + $toNode + ")"
            WriteMmdFlow -mmdString $statement
            $statement = $paragraphName + "->>" + $toNode + ": perform"
            WriteMmdSequence -mmdString $statement

        }

        # Call handling

        if ($line.trim().StartsWith("call")) {
            $toNode = $line.trim().Replace("call", "").replace("'", "").Replace('"', "").replace("end-call", "").replace("end", "")
            $pos1 = $line.IndexOf("call ")
            $pos2 = $line.IndexOf("'")
            $pos3 = $line.IndexOf('"')
            if ($pos3 -gt $pos2) {
                $pos2 = $pos3
            }
            if ($pos1 -gt $pos2) {
                Write-LogMessage ("Skipped call statement:" + $line) -Level INFO
                continue
            }
            $ustart = $toNode.IndexOf("using")
            if ($ustart -gt 0) {
                $toNode = $toNode.Substring(0, $ustart).Trim()
            }
            $toNode = $toNode.TrimEnd("-").TrimStart("-").Trim()

            $statement = $paragraphName + " --call-->" + $toNode.trim().Replace(" ", "_") + "[[" + $toNode.trim() + "]]"
            WriteMmdFlow -mmdString $statement

            $statement = $paragraphName + "-->>" + $toNode.trim() + ": call"
            WriteMmdSequence -mmdString $statement

        }

        # Stop Run handling
        if ($line.trim().Contains("stop run")) {
            $statement = $paragraphName + " ---->stop_run(STOP RUN)"
            WriteMmdFlow -mmdString $statement
            $statement = $paragraphName + "-->>stop_run: stop run"
            WriteMmdSequence -mmdString $statement
            $statement = "participant stop_run"
            WriteMmdSequence -mmdString $statement
        }

        # GoBack handling
        if ($line.trim().Contains("goback")) {
            $statement = $paragraphName + " ---->goback(goback)"
            WriteMmdFlow -mmdString $statement
            $statement = $paragraphName + "-->>goback: goback"
            WriteMmdSequence -mmdString $statement
            $statement = "participant goback"
            WriteMmdSequence -mmdString $statement
        }

        # Read and write file handling
        if ($line.StartsWith("read ") -or $line.StartsWith("write ")) {
            $temp = $line
            $x = $temp.Split(' ')
            if ($x.Count -gt 1) {
                $readOrWriteOperation = $x[0]
                $fileName = $x[1]

                if ($fileName.Contains("-rec")) {
                    $searchString = "�" + $fileName + "�"
                    $fileNameRes = FindStringInHashtable -hashTable $fdHashtable -searchString  $searchString
                }

                try {
                    $fileNameTemp = $fileNameRes.Replace("-", "_").Replace(" ", "_")
                }
                catch {
                    $fileNameTemp = $fileName
                    $fileNameRes = $fileName
                }
                $statement = $paragraphName + " --" + $readOrWriteOperation + " file-->" + $fileNameTemp + "file[/" + $fileNameRes + "/]"
                if ($fileNameRes.Length -eq 0 ) {
                    Write-LogMessage ("Error parsing file node (fix later): " + $line) -Level WARN
                }
                else {
                    WriteMmdFlow -mmdString $statement
                }
            }
        }
    }
    # Add the last lines to accumulated paragraph code
    if ($lastLineNumber -gt $contentFromLineNumber) {
        $accumulatedParagraphCode += $procedureContent[($contentFromLineNumber - 1)..($lastLineNumber - 1)]
    }

    # SQL Select handling
    if (!$isSqlCodeInParagraphHandled) {
        try {
            if ($paragraphName.contains("m180")) {
            }

        }
        catch {
        }
        if ($paragraphName.contains("m180")) {
        }
        GenerateSqlNodes -paragraphCode $accumulatedParagraphCode -fileContent $fileContent -procedureContent $procedureContent -paragraphName $paragraphName
        $isSqlCodeInParagraphHandled = $true
    }
}

function GenerateSqlNodes {
    param (
        $paragraphCode, $fileContent , $procedureContent, $paragraphName
    )
    try {
        $sqlOperation = $null
        $sqlTableNames = $null
        $cursorName = $null
        $cursorForUpdate = $null

        $sqlOperation, $sqlTableNames, $cursorName, $cursorForUpdate, $updateFields = $null

        $supportedSqlExpressions = @("SELECT", "UPDATE", "INSERT", "DELETE" , "FETCH", "CALL")

        $pattern = "exec sql([^\n]*?)end-exec" # Use a non-greedy quantifier *? to match the shortest possible string
        $matches1 = [regex]::Matches($paragraphCode, $pattern) # Get all the matches as a collection

        foreach ($currentItemName in $matches1) {
            $sqlOperation, $sqlTableNames, $cursorName, $cursorForUpdate, $updateFields = FindSqlStatementInExecSql -inCode $currentItemName.Value -fileContent $fileContent -procedureContent $procedureContent
            $sqlTableNames = $sqlTableNames | Sort-Object -Unique

            if ($sqlOperation -eq "CALL") {
                $tempStr = $currentItemName.Value.Replace("exec sql", "").Replace("end-exec", "").Replace("call", "").Replace("'", "").Replace('"', "").Replace(";", "").Trim()
                $pos = $tempStr.IndexOf("(")
                if ($pos -gt 0) {
                    $tempStr = $tempStr.Substring(0, $pos).Trim()
                }
                else {
                    Continue
                }
                $statement = $paragraphName + "-->" + $tempStr + "(" + $tempStr + ")"
                WriteMmdFlow -mmdString $statement
                $statement = $paragraphName + "-->>" + $tempStr + ": call sql procedure"
                WriteMmdSequence -mmdString $statement
                Continue
            }

            if ($supportedSqlExpressions.Contains($sqlOperation) -and $sqlTableNames.Count -gt 0 ) {

                $tableCounter = 0
                foreach ($sqlTable in $sqlTableNames) {
                    $sqlTable = $sqlTable.Replace(")", "").Replace("(", "").Replace("'", "").Replace('"', "")
                    $script:sqlTableArray += $sqlTable
                    $tableCounter += 1
                    $statementText = $sqlOperation.ToLower()
                    if ($cursorName.Length -gt 0) {
                        if ($tableCounter -eq 1) {

                            $statementText = "Cursor " + $cursorName.ToUpper() + " select"
                            if ($cursorForUpdate) {
                                $statementText = "Primary table for cursor " + $cursorName.ToUpper() + " select for update"
                            }
                        }
                        else {
                            $statementText = "Sub-select in cursor " + $cursorName.ToUpper()
                        }
                    }
                    else {
                        if ($tableCounter -gt 1) {
                            if ($sqlOperation.ToUpper() -eq "UPDATE" -or $sqlOperation.ToUpper() -eq "INSERT" -or $sqlOperation.ToUpper() -eq "DELETE") {
                                $statementText = "Sub-select related to " + $sqlTableNames[0].Trim()
                            }
                            if ($sqlOperation.ToUpper() -eq "SELECT") {
                                $statementText = "Join or Sub-select related to " + $sqlTableNames[0].Trim()
                            }
                        }
                        # Add field names for UPDATE statements (primary table only)
                        elseif ($sqlOperation.ToUpper() -eq "UPDATE" -and $updateFields -and $updateFields.Count -gt 0) {
                            $fieldList = $updateFields -join ", "
                            $statementText = "update [$($fieldList)]"
                        }
                    }
                    try {

                        $statement = $paragraphName + '--"' + $statementText + '"-->sql_' + $sqlTable.Replace(".", "_").Trim() + "[(" + $sqlTable.Trim() + ")]"
                        WriteMmdFlow -mmdString $statement

                        $statement = $paragraphName + "-->>" + $sqlTable.Trim() + ": sql " + $statementText
                        WriteMmdSequence -mmdString $statement

                    }
                    catch {
                        $errorMessage = $_.Exception
                        write-host En feil oppstod: $errorMessage
                        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
                        Write-LogMessage $errorMessage -Level ERROR
                        $script:errorOccurred = $true
                    }
                }
            }
        }
    }
    catch {
        $errorMessage = $_.Exception
        write-host En feil oppstod: $errorMessage
        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
        Write-LogMessage $errorMessage -Level ERROR
        $script:errorOccurred = $true
    }
}

function New-CblMmdLinks {
    param (
        $baseFileName, $sourceFile, $proxyFilename, $proxyClass, $proxyFileContent
    )
    try {

        $link = "https://Dedge.visualstudio.com/_git/Dedge?path=/cbl/" + $baseFileName.ToLower()
        $statement = "click " + $baseFileName.ToLower().Split(".")[0] + " " + '"' + $link + '"' + " " + '"' + $baseFileName.ToLower().Split(".")[0] + '"' + " _blank"
        WriteMmdFlow -mmdString $statement

        $paragraphListItems = Get-Content -Path $sourceFile | Select-String -Pattern "(^.*M[0-9]+\-.*\.)|(^.*CALL.*)|(^.*PROCEDURE.DIVISION.*)|(^.*PROCEDURE.*DIVISION.*)" -AllMatches

        $counter = 0
        $procedureDivisionPassed = $false

        #$script:sqlTableArray
        foreach ($Item in $script:sqlTableArray) {
            $workstring = $Item.Replace("?�?", "a").Replace("?�", "o").Replace("??", "o").Replace("?", "o")

            $linkname = "sql_" + $workstring.Replace(".", "_").Trim()
            $link = ("./" + $workstring.Replace(".", "_").Trim() + ".sql.html").Trim().ToUpper().Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower()
            $statement = "click " + $linkname + " " + '"' + $link + '"' + " " + '"' + $workstring + '"' + " _blank"
            WriteMmdFlow -mmdString $statement
            $statement = "style " + $linkname + " stroke:dark-blue,stroke-width:4px"
            WriteMmdFlow -mmdString $statement
        }

        foreach ($item in $paragraphListItems) {

            $counter += 1
            $ustart = $item.line.IndexOf("*>")
            if ($ustart -gt 0) {
                # Removes comment at end of line
                $item.line = $item.line.Substring(0, $ustart)
            }

            if ($item.line.Trim().Length -eq 0) {
                # Skip to next element if null
                continue
            }
            if ($item.line.Trim().Length -le 6) {
                # Skip to next element only room for linenumbers from 0..6
                continue
            }

            if ($item.line.Trim().Substring(0, 1) -eq "*") {
                # Skip to next element
                continue
            }

            $item.line = $item.line.ToString().ToLower().Substring(6).Trim()

            if ($item.Line.Trim().StartsWith("*")  ) {
                continue
            }

            if ($item.line.Contains("entry ") -or $item.line.Contains("perform ")) {
                continue
            }

            if ($item.line -match "^.*PROCEDURE.DIVISION.*" -or $item.line -match "^.*PROCEDURE.*DIVISION.*") {
                $procedureDivisionPassed = $true
                $link = "https://Dedge.visualstudio.com/_git/Dedge?path=/cbl/" + $baseFileName.ToLower() + "&version=GBmaster&line=" + ($item.LineNumber).ToString() + "&lineEnd=" + ($item.LineNumber + 1).ToString() + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents"
                $statement = "click procedure_division " + '"' + $link + '"' + " " + '"' + "procedure_division" + '"' + " _blank"
                WriteMmdFlow -mmdString $statement
            }

            if ($procedureDivisionPassed) {
                if ($item.line.Contains("call ")) {
                    #This code is created to handle the following code: inspect ww-linje tallying w-tally for all ' call '
                    $pos1 = $item.line.IndexOf("call ")
                    $pos2 = $item.line.IndexOf("'")
                    $pos3 = $item.line.IndexOf('"')
                    if ($pos3 -gt $pos2) {
                        $pos2 = $pos3
                    }
                    if ($pos1 -gt $pos2) {
                        continue
                    }

                    if ($item.line.Contains("perform ")) {
                        continue
                    }

                    try {
                        if ($item.line.contains("'")) {
                            $temp1 = $item.line.Split("'")
                        }
                        else {
                            $temp1 = $item.line.Split(" ")
                        }
                        $callModule = $temp1[1].Trim().ToLower()
                    }
                    catch {
                        try {
                            $temp1 = $item.line.Split('"')
                            $callModule = $temp1[1].Trim().ToLower()
                        }
                        catch {
                            continue
                        }
                    }

                    $callModule = $callModule.Replace("'", "").Replace('"', "")

                    if ($null -ne $proxyFilename -and $proxyFilename.Length -gt 0) {
                        $resultArray1 = @()
                        $resultArray1 = $fileContentOriginal | select-string $callModule

                        if ($resultArray1.Count -gt 0) {
                            $linkRequest = $proxyClass + "%20AND%20" + $callModule
                            $link = "https://Dedge.visualstudio.com/Dedge/_search?action=contents&text=" + $linkRequest + "&type=code&lp=code-Project&filters=ProjectFilters%7BDedge%7DRepositoryFilters%7BDedge%7D&pageSize=25"
                            $statement = "click " + $callModule + " " + '"' + $link + '"' + " " + '"' + $callModule + '"' + " _blank"
                            WriteMmdFlow -mmdString $statement
                            $statement = "style " + $callModule + " stroke:dark-blue,stroke-width:4px"
                            WriteMmdFlow -mmdString $statement
                            continue
                        }
                    }

                    if ($callModule.ToUpper().startsWith("CBL_") `
                            -or $callModule.ToUpper().startsWith("UTL_") `
                            -or $callModule.ToUpper().contains(" ") `
                            -or $callModule.ToUpper().startsWith("DB2") `
                            -or $callModule.ToUpper().startsWith("SLEEP") `
                            -or $callModule.ToUpper().Contains("SET-BUTTON-STATE") `
                            -or $callModule.ToUpper().Contains("COB32API") `
                            -or $callModule.ToUpper().Contains("DISABLE-OBJECT") `
                            -or $callModule.ToUpper().Contains("ENABLE-OBJECT") `
                            -or $callModule.ToUpper().Contains("REFRESH-OBJECT")`
                            -or $callModule.ToUpper().Contains("HIDE-OBJECT")  `
                            -or $callModule.ToUpper().Contains("SQLGINTP")  `
                            -or $callModule.ToUpper().Contains("HIDE-OBJECT") `
                            -or $callModule.ToUpper().Contains("SET-FOCUS") `
                            -or $callModule.ToUpper().Contains("SET-MOUSE-SHAPE") `
                            -or $callModule.ToUpper().Contains("SHOW-OBJECT") `
                            -or $callModule.ToUpper().Contains("VENT_SEK") `
                            -or $callModule.ToUpper().Contains("CLEAR-OBJECT") `
                            -or $callModule.ToUpper().Contains("CC1") `
                            -or $callModule.ToUpper().Contains("DSRUN") `
                            -or $callModule.ToUpper().Contains("SET-FIRST-WINDOW") `
                            -or $callModule.ToUpper().Contains("INVOKE-MESSAGE-BOX") `
                            -or $callModule.ToUpper().Contains("SET-LIST-ITEM-STATE") `
                            -or $callModule.ToUpper().Contains("SET-OBJECT-LABEL") `
                            -or $callModule.ToUpper().Contains("SET-TOP-LIST-ITEM") `
                            -or $callModule.ToUpper().Contains("VENT_KVARTSEK") `
                            -or $callModule.ToUpper().Contains("SQLGINTR")) {
                        continue
                    }

                    if ($callModule.Length -gt 0) {
                        $link = "./" + $callModule + ".cbl.html"
                        $statement = "click " + $callModule + " " + '"' + $link + '"' + " " + '"' + $callModule + '"' + " _blank"
                        WriteMmdFlow -mmdString $statement
                        $statement = "style " + $callModule + " stroke:dark-blue,stroke-width:4px"
                        WriteMmdFlow -mmdString $statement
                    }
                }
                elseif ($item.line -match ".*M[0-9]+\-.*\.") {
                    $pos = $item.line.IndexOf(".")
                    $item.line = $item.line.Substring(0, $pos)
                    $item.line = $item.line.Replace("--", "-")
                    if (VerifyIfParagraph -paragraphName $item.line) {
                        $link = "https://Dedge.visualstudio.com/_git/Dedge?path=/cbl/" + $baseFileName.ToLower() + "&version=GBmaster&line=" + ($item.LineNumber).ToString() + "&lineEnd=" + ($item.LineNumber + 1).ToString() + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents"
                        $statement = "click " + $item.line + " " + '"' + $link + '"' + " " + '"' + $item.line + '"' + " _blank"
                        WriteMmdFlow -mmdString $statement
                    }
                }
            }
        }
    }
    catch {
        $errorMessage = $_.Exception
        write-host En feil oppstod: $errorMessage
        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
        Write-LogMessage $errorMessage -Level ERROR
        $script:errorOccurred = $true
    }
}

function Get-CblMetaData {
    param (
        $tmpRootFolder, $baseFileName, $outputFolder
    )
    try {
        $inputDbFileFolder = $tmpRootFolder + "\cobdok"
        $searchProgramName = $baseFileName.ToLower().Split(".")[0]

        # Get data from modul.csv - start
        $csvModulArray = Import-Csv ($inputDbFileFolder + "\modul.csv") -Header system, delsystem, modul, tekst, modultype, benytter_sql, benytter_ds, fra_dato, fra_kl, antall_linjer, lengde, filenavn -Delimiter ';'
        $descArray = $csvModulArray | Where-Object { $_.modul.Contains($searchProgramName.ToUpper()) }

        if ($descArray.Count -gt 0) {
            $item = $descArray[0]

            $htmlSystem = $item.delsystem.Trim()
            $htmlDesc = $item.tekst.Trim()
            $htmlType = $item.modultype.Trim()

            if ($htmlType -eq "B") {
                $htmlType = "B - Batchprogram"
            }
            elseif ($htmlType -eq "H") {
                $htmlType = "H - Main user interface"
            }
            elseif ($htmlType -eq "S") {
                $htmlType = "S - Webservice"
            }
            elseif ($htmlType -eq "V") {
                $htmlType = "V - Validation module for user interface"
            }
            elseif ($htmlType -eq "A") {
                $htmlType = "A - Common module"
            }
            elseif ($htmlType -eq "F") {
                $htmlType = "F - Search module for user interface"
            }

            $htmlUseSql = $item.benytter_ds.Replace("N", "false").Replace("J", "true")
            $htmlUseDs = $item.benytter_sql.Replace("N", "false").Replace("J", "true")
        }
        # Get data from modul.csv - End

        # Get data from delsystem.csv - Start
        $csvDelsystemArray = Import-Csv ($inputDbFileFolder + "\delsystem.csv") -Header system, delsystem, tekst -Delimiter ';'
        $descArray = $csvDelsystemArray | Where-Object { $_.system.Contains("FKAVDNT") -and $_.delsystem.Contains($htmlSystem) }

        if ($descArray.Count -gt 0) {
            $item = $descArray[0]
            $htmlSystem = $htmlSystem + " - " + $item.tekst.Trim()
        }
        # Get data from delsystem.csv - End

        # Get data from tiltp_log.csv - Start
        $csvTiltp_logArray = Import-Csv ($inputDbFileFolder + "\tiltp_log.csv") -Header pgm, dato, brukerid, tidspunkt -Delimiter ';'
        $descArray = $csvTiltp_logArray | Where-Object { $_.pgm.Contains($searchProgramName.ToUpper()) }

        if ($descArray.Count -gt 0) {
            $descArray = $descArray | Sort-Object -Descending

            $item = $descArray[($descArray.Count - 1)]
            $tempWork = $item.tidspunkt.trim()

            $htmlCreatedDateTime = $tempWork.Substring(8, 2) + "/" + $tempWork.Substring(5, 2) + "/" + $tempWork.Substring(0, 4) + " - " + $tempWork.Substring(11, 2) + ":" + $tempWork.Substring(14, 2) + " (" + $item.brukerid.Trim() + ")"

            $item = $descArray[0]
            $tempWork = $item.tidspunkt.Trim()
            $htmlLastProdDateTime = $tempWork.Substring(8, 2) + "/" + $tempWork.Substring(5, 2) + "/" + $tempWork.Substring(0, 4) + " - " + $tempWork.Substring(11, 2) + ":" + $tempWork.Substring(14, 2) + " (" + $item.brukerid.Trim() + ")"

            $descArray = $descArray | Sort-Object
            $workArray = @()

            foreach ($item in $descArray) {
                $tempWork = $item.tidspunkt.Trim()
                $tempWorkUser = $item.brukerid.Trim()
                $workString = "<tr><td>" + $tempWork.Substring(8, 2) + "/" + $tempWork.Substring(5, 2) + "/" + $tempWork.Substring(0, 4) + " - " + $tempWork.Substring(11, 2) + ":" + $tempWork.Substring(14, 2) + "</td><td>" + $tempWorkUser + "</td></tr>"
                $workArray += $workString
            }
            $htmlProdLog = "" + $workArray -join ""
        }
        # Get data from tiltp_log.csv - End

        # Get data from modkom.csv - Start
        $csvModkomArray = Import-Csv ($inputDbFileFolder + "\modkom.csv") -Header system, modul, seqnr, tekst -Delimiter ';'
        $descArray = $csvModkomArray | Where-Object { $_.system.Contains("FKAVDNT") -and $_.modul.Contains($searchProgramName.ToUpper()) }

        if ($descArray.Count -gt 0) {
            $descArray = $descArray | Sort-Object
            $workArray = @()

            $workString = ""
            foreach ($item in $descArray) {
                $tempWork = $item.tekst.Trim()
                if ($tempWork.Length -gt 0 ) {
                    if ($workString -ne "" -and ($tempWork.Substring(0, 1) -eq "1" -or $tempWork.Substring(0, 1) -eq "2" -or $tempWork.Substring(0, 1) -eq "3" -or $tempWork.Substring(0, 1) -eq "4" -or $tempWork.Substring(0, 1) -eq "5" -or $tempWork.Substring(0, 1) -eq "6" -or $tempWork.Substring(0, 1) -eq "7" -or $tempWork.Substring(0, 1) -eq "8" -or $tempWork.Substring(0, 1) -eq "9" -or $tempWork.Substring(0, 1) -eq "0")) {
                        $workArray += $workString + " "
                        $workString = ""
                    }
                }
                $workString += " " + $tempWork.Trim()
            }
            $workArray += $workString

            $descArray = $workArray
            $workArray = @()

            foreach ($item in $descArray) {
                $item = $item.Trim()
                $pos = $item.IndexOf(" ")
                if ($item.Length -le 0 -or $pos -le 0) {
                    continue
                }
                try {
                    $string = $item.Substring(0, $pos)
                }
                catch {
                }

                try {
                    $date = [Convert]::ToDateTime($string)
                    $commentDate = $date.ToString()
                }
                catch {
                    $commentDate = [Convert]::ToDateTime("01.01.1970")
                }
                finally {
                    try {

                        $workString = $item.Substring($pos).Trim()
                        $pos = $workString.IndexOf(" ")
                        $commentInitials = $workString.Substring(0, $pos)
                        if ($commentInitials.Trim().Length -gt 3) {
                            $commentInitials = "N/A"
                            $comment = $item.Trim()
                        }
                        else {
                            $commentInitials = $workString.Substring(0, $pos).Trim()
                            $comment = $workString.Substring($pos).Trim()
                        }
                    }
                    catch {
                    }

                }
                try {
                    $commentDateStr = $commentDate.ToString()
                    # 01.01.1970
                    $commentDateStr = $commentDateStr.Substring(6, 4) + $commentDateStr.Substring(3, 2) + $commentDateStr.Substring(0, 2)
                }
                catch {
                    <#Do this if a terminating exception happens#>
                    $errorMessage = $_.Exception
                }
                $str = $commentDateStr + "�" + $commentInitials + "�" + $comment
                $workArray += $str.ToString()

            }

            $descArray = $workArray | Sort-Object
            $workArray = @()

            foreach ($item in $descArray) {
                $split = $item.Split("�")
                $year = $split[0].Substring(0, 4)
                $month = $split[0].Substring(4, 2)
                $day = $split[0].Substring(6, 2)
                $initials = $split[1].Trim()
                $comment = $split[2].Trim()
                $workString = "<tr><td>" + $day + "/" + $month + "/" + $year + "</td><td>" + $initials + "</td><td>" + $comment + "</td></tr>"
                $workArray += $workString
            }
            $htmlComments = "" + $workArray -join ""
        }
        # Get data from modkom.csv - End

        # Get data from sqlxtab.csv and tables.csv - Start
        $csvTablesArray = Import-Csv ($inputDbFileFolder + "\tables.csv") -Header tabschema , tabname , remarks -Delimiter ';'

        $csvSqlxtabArray = Import-Csv ($inputDbFileFolder + "\sqlxtab.csv") -Header system, modul, id, type, tabell -Delimiter ';'
        $descArray = $csvSqlxtabArray | Where-Object { $_.system.Contains("FKAVDNT") -and $_.modul.Contains($searchProgramName.ToUpper()) }

        if ($descArray.Count -gt 0) {
            # Use the Sort-Object cmdlet with the -Unique parameter to remove duplicates
            $descArray = $descArray | Sort-Object
            $workArray = @()

            foreach ($item in $descArray) {
                $tableName = $item.tabell.Trim()
                if ($item.type.Trim() -eq "S") {
                    $tableOperationDesc = "Select"
                }
                elseif ($item.type.Trim() -eq "I") {
                    $tableOperationDesc = "Insert"
                }
                elseif ($item.type.Trim() -eq "U") {
                    $tableOperationDesc = "Update"
                }
                elseif ($item.type.Trim() -eq "D") {
                    $tableOperationDesc = "Delete"
                }

                $pos = $tableName.IndexOf(".")
                $tableNameWithoutSchema = $tableName.Substring($pos + 1).ToUpper().Trim()

                $tableArray = $csvTablesArray | Where-Object { $_.tabname.Contains($tableNameWithoutSchema) }
                $tableRemarks = ""
                if ($tableArray.Count -gt 0) {
                    $item = $tableArray[0]
                    $tableRemarks = $item.remarks
                    if ($tableRemarks.Length -gt 0) {
                        $tableRemarks = $tableRemarks.Substring(0, 1).ToUpper() + $tableRemarks.Substring(1).ToLower()
                    }
                }
                $filelink = ("./" + $tableName.Replace(".", "_").Trim() + ".sql.html").Trim().ToUpper().Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower()
                $tablenamelink = "<a href=" + '"' + $filelink + '" ' + "target=" + '"' + "_blank" + '"' + ">" + $tableName + "</a>"

                $workString = "<tr><td>" + $tablenamelink + "</td><td>" + $tableOperationDesc + "</td><td>" + $tableRemarks + "</td></tr>"
                $workArray += $workString
            }
            $workArray = $workArray | Sort-Object -Unique

            $htmlSqlTables = "" + $workArray -join ""
        }
        # Get data from sqlxtab.csv and tables.csv - End

        # Get data from call.csv - Start
        $csvCallArray = Import-Csv ($inputDbFileFolder + "\call.csv") -Header system, modul, call -Delimiter ';'
        $descArray = $csvCallArray | Where-Object { $_.system.Contains("FKAVDNT") -and $_.modul.Contains($searchProgramName.ToUpper()) }

        if ($descArray.Count -gt 0) {
            $descArray = $descArray | Sort-Object
            $workArray = @()

            foreach ($item in $descArray) {
                $call = $item.call.Trim()
                $modulArray = $csvModulArray | Where-Object { $_.system.Contains("FKAVDNT") -and $_.modul.Contains($call.ToUpper()) }

                if ($modulArray.Length -gt 0) {
                    $item = $modulArray[0]
                    $callDesc = $item.tekst
                    if ($callDesc.Length -gt 0) {
                        $callDesc = ($callDesc.Substring(0, 1).ToUpper() + $callDesc.Substring(1).ToLower()).Trim()
                    }
                }
                else {
                    $callDesc = "N/A"
                }

                $link = "<a href=" + '"' + "./" + $call + ".cbl.html" + '" ' + "target=" + '"' + "_blank" + '"' + ">" + $call + "</a>"
                # $link = "<a href=" + '"' + "https://dev.azure.com/Dedge/Dedge/_git/Dedge?path=%2Fcbl%2F" + $call + ".cbl&_a=contents&version=GBmaster" + '"' + ">" + $call + "</a>"
                $workString = "<tr><td>" + $link + "</td><td>" + $callDesc + "</td></tr>"
                $workArray += $workString
            }

            $htmlCallList = "" + $workArray -join ""
        }
        # Get data from call.csv - End

        # Get data from copy.csv - Start

        $csvCodoMenyArray = Import-Csv ($inputDbFileFolder + "\copy.csv") -Header system, modul, copy -Delimiter ';'
        $descArray = $csvCodoMenyArray | Where-Object { $_.system.Contains("FKAVDNT") -and $_.modul.Contains($searchProgramName.ToUpper()) }

        if ($descArray.Count -gt 0) {
            $descArray = $descArray | Sort-Object
            $workArray = @()

            foreach ($item in $descArray) {
                $copyElementFile = $item.copy

                $fileSuffix = $copyElementFile.Substring(($copyElementFile.IndexOf(".") + 1)).ToLower().Trim()
                $link = "<a href=" + '"' + "https://Dedge.visualstudio.com/Dedge/_search?action=contents&text=" + $copyElementFile + "%20ext%3A" + $fileSuffix.trim() + "&type=code&lp=code-Project&filters=ProjectFilters%7BDedge%7DRepositoryFilters%7BDedge%7D&pageSize=25" + '"' + ">" + $copyElementFile.ToLower() + "</a>"
                $workString = "<tr><td>" + $link + "</td></tr>"
                $workArray += $workString
            }

            $htmlCopyList = "" + $workArray -join ""
        }
        # Get data from copy.csv - End

    }
    catch {
        $errorMessage = $_.Exception
        write-host En feil oppstod: $errorMessage
        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
        Write-LogMessage $errorMessage -Level ERROR
        $script:errorOccurred = $true
    }
    finally {
        $htmlFilename = $outputFolder + "\" + $baseFileName + ".html"
        
        # Use template from OutputFolder\_templates (copied at startup by AutoDocBatchRunner)
        $templatePath = Join-Path $outputFolder "_templates"
        $mmdTemplateFilename = Join-Path $templatePath "cblmmdtemplate.html"

        $myDescription = "AutoDoc Diagrams - Cobol Source File - " + $baseFileName.ToLower()

        $tmpl = Get-Content -Path $mmdTemplateFilename -Raw -Encoding UTF8
        # Apply shared CSS and common URL replacements
        $doc = Set-AutodocTemplate -Template $tmpl -OutputFolder $outputFolder
        $doc = $doc.Replace("[title]", $myDescription)

        $doc = $doc.Replace("[desc]", $htmlDesc)
        $doc = $doc.Replace("[generated]", (Get-Date).ToString())
        $doc = $doc.Replace("[type]", $htmlType)
        $doc = $doc.Replace("[system]", $htmlSystem)
        $doc = $doc.Replace("[usesql]", $htmlUseSql)
        $doc = $doc.Replace("[useds]", $htmlUseDs)
        
        # Check for related Dialog System screen HTML file and add link
        $screenHtmlFile = Join-Path $outputFolder "$($baseFileName.ToUpper() -replace '\.CBL$', '').screen.html"
        if (Test-Path $screenHtmlFile) {
            $screenBaseName = $baseFileName.ToUpper() -replace '\.CBL$', ''
            $doc = $doc.Replace("[screenlinkstyle]", "")
            $doc = $doc.Replace("[screenlink]", "./$screenBaseName.screen.html")
            $doc = $doc.Replace("[screenlinktext]", "$screenBaseName Screen")
        } else {
            # Hide the row if no screen file exists
            $doc = $doc.Replace("[screenlinkstyle]", "display: none;")
            $doc = $doc.Replace("[screenlink]", "#")
            $doc = $doc.Replace("[screenlinktext]", "")
        }
        
        $doc = $doc.Replace("[created]", $htmlCreatedDateTime)
        $doc = $doc.Replace("[prodinfo]", $htmlLastProdDateTime)
        $doc = $doc.Replace("[prodlog]", $htmlProdLog)
        $doc = $doc.Replace("[changelog]", $htmlComments)
        $doc = $doc.Replace("[sqltables]", $htmlSqlTables)
        $doc = $doc.Replace("[calllist]", $htmlCallList)
        $doc = $doc.Replace("[copylist]", $htmlCopyList)
        if ($htmlExecutionPoints.Length -gt 0) {
            $doc = $doc.Replace("[execlist]", $htmlExecutionPoints)
        }
        else {
            $doc = $doc.Replace("[execlist]", "")
        }

        # For client-side rendering, embed MMD content directly from memory
        if ($ClientSideRender) {
            # IN-MEMORY: Get content from ArrayLists instead of files
            $flowMmdContent = $script:mmdFlowContent -join "`n"
            $sequenceMmdContent = $script:mmdSequenceContent -join "`n"
            
            $doc = $doc.Replace("[flowmmd_content]", $flowMmdContent)
            $doc = $doc.Replace("[sequencemmd_content]", $sequenceMmdContent)
        }
        
        $doc = $doc.Replace("[flowdiagram]", "./" + $baseFileName + ".flow.svg" )
        $doc = $doc.Replace("[sequencediagram]", "./" + $baseFileName + ".sequence.svg" )
        $doc = $doc.Replace("[sourcefile]", $baseFileName.ToLower())
        set-content -Path $htmlFilename -Value $doc
    }

}

function WriteMmdFlow {
    param (
        $mmdString
    )

    # OPTIMIZED: Replace literal newlines with <br/> for Mermaid compatibility
    $mmdString = $mmdString -replace "`n", "<br/>" -replace "`r", ""
    
    # OPTIMIZED: Use single regex for Norwegian character cleanup
    $mmdString = $mmdString -replace '[Ø]', 'O' -replace '[ø]', 'o' -replace '[Å]', 'A' -replace '[å]', 'a' -replace '[Æ]', 'AE' -replace '[æ]', 'ae'
    $mmdString = $mmdString.Replace("LEVERANDOR", "LEVERANDOR").Replace("TRANSPORTOR", "TRANSPORTOR")
    
    # Use baseFileName from script scope
    $baseFileName = $script:baseFileNameTemp.Trim().ToLower()
    $mmdString = $mmdString -replace '\s{2,}', ' '  # OPTIMIZED: Single regex for multiple spaces

    # if (($mmdString.Contains("-->p") -and $mmdString.Contains("perform")) `

    # OPTIMIZED: Use regex for module/pattern filtering
    $mmdLower = $mmdString.ToLower()
    
    # Check for common utility modules (skip if not the same as current file)
    $utilityModules = @('gmacoco', 'gmasql', 'gmacnct', 'gmalike', 'gmacurt', 'gmftrap', 'gmffell', 'gmadato', 'gmfsql')
    foreach ($mod in $utilityModules) {
        if ($mmdLower.Contains($mod) -and $baseFileName -ne $mod) { return }
    }
    
    # Skip common patterns using regex
    if ($mmdLower -match '(-sql-trap|-error|refresh-?object|cbl_(exit_proc|copy_file|rename_file|toupper|tolower)|sqlg(star|intr)|db2api|-exit-proc|procdiv)') {
        return
    }
    
    # Use HashSet for O(1) duplicate checking (thread-safe within same runspace)
    if (-not $script:duplicateLineCheck.Contains($mmdString)) {

        if ($mmdString.Contains("-->") -and -Not $mmdString.ToLower().Contains("initiated-->") ) {
            $pos1 = $mmdString.IndexOf("-->")
            $pos2 = $mmdString.LastIndexOf("-->")
            if ($pos1 -eq $pos2) {
                $script:sequenceNumber += 1
                $mmdString = $mmdString.Substring(0, $pos1) + "(#" + $script:sequenceNumber + ")" + $mmdString.Substring($pos1)
            }
        }
        $script:mmdSequenceElementsWritten += 1
        
        # IN-MEMORY: Add to ArrayList instead of file I/O
        if ($script:useClientSideRender) {
            [void]$script:mmdFlowContent.Add($mmdString)
        }
        else {
            Add-Content -Path $script:mmdFilenameFlow -Value $mmdString -Force
        }
        [void]$script:duplicateLineCheck.Add($mmdString)
    }
}
function Get-CblStringBetween {
    param ($firstString, $secondString, $data, $overrideStartPos = 0)
    try {

        if ($overrideStartPos -gt 0) {
            $pos1 = $overrideStartPos
        }
        else {
            if ($firstString -eq "<line_start>") {
                $pos1 = -1
            }
            else {
                $pos1 = $data.IndexOf($firstString)
                if ($pos1 -lt 0) {
                    return $null, $data
                }
            }
        }
        $pos2 = $data.Substring($pos1 + 1).IndexOf($secondString)
        if ($pos2 -lt 0) {
            return $null, $data
        }
        if ($pos1 -lt 0) {
            $pos1 = 0
        }
        $retData = $data.Substring($pos1, $pos2 + 1).Trim()
        return $retData, $data.Substring($pos1 + $pos2 + 1)
    }
    catch {
        return $null, $data
    }

}

function WriteMmdSequence {
    param (
        $mmdString
    )

    if ($mmdString.contains("cob32api.dll")) {
    }

    # Escape/remove characters that break Mermaid sequence diagram syntax
    # Double quotes within message text cause parse errors
    $mmdString = $mmdString.Replace('"', "'")
    
    # Remove backslashes that cause escape issues
    $mmdString = $mmdString.Replace('\', '/')
    
    # Handle Norwegian characters - comprehensive replacement using regex
    $mmdString = $mmdString -replace '[Ø]', 'O' -replace '[ø]', 'o' -replace '[Å]', 'A' -replace '[å]', 'a' -replace '[Æ]', 'AE' -replace '[æ]', 'ae'
    
    # Handle legacy encoding issues with Norwegian characters
    $mmdString = $mmdString.Replace("?�?", "a")
    $mmdString = $mmdString.Replace("?�", "o")
    $mmdString = $mmdString.Replace("??", "o")
    $mmdString = $mmdString.Replace("�", "o")  # Common encoding for ø
    $mmdString = $mmdString.Replace("�", "o")  # Another encoding variant

    $mmdString = $mmdString.Replace("LEVERANDOR", "LEVERANDOR")
    $mmdString = $mmdString.Replace("TRANSPORTOR", "TRANSPORTOR")
    $mmdString = $mmdString.Replace("leverandor", "leverandor")
    $mmdString = $mmdString.Replace("transportor", "transportor")
    
    # Remove characters that can break Mermaid parsing
    $mmdString = $mmdString.Replace(';', ',')
    $mmdString = $mmdString.Replace('&', 'and')
    
    # Normalize whitespace
    $mmdString = $mmdString.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
    if (($mmdString.Contains("-->p") -and $mmdString.Contains("perform")) `
            -or $mmdString.Contains("-sql-trap") `
            -or $mmdString.Contains("-error") `
            -or $mmdString.Contains("gmacoco") `
            -or $mmdString.Contains("refresh-object") `
            -or $mmdString.Contains("refreshobject") `
            -or $mmdString.Contains("gmfsql") `
            -or $mmdString.Contains("gmasql") `
            -or $mmdString.Contains("gmacnct") `
            -or $mmdString.Contains("gmalike") `
            -or $mmdString.Contains("gmacurt") `
            -or $mmdString.Contains("gmftrap") `
            -or $mmdString.Contains("gmffell") `
            -or $mmdString.Contains("gmadato") `
            -or $mmdString.Contains("cbl_exit_proc") `
            -or $mmdString.Contains("cbl_copy_file") `
            -or $mmdString.Contains("cbl_rename_file") `
            -or $mmdString.Contains("cbl_toupper") `
            -or $mmdString.Contains("cbl_tolower") `
            -or $mmdString.Contains("sqlgstar") `
            -or $mmdString.Contains("sqlgintr") `
            -or $mmdString.Contains("db2api") `
            -or $mmdString.Contains("-exit-proc") `
            -or $mmdString.ToLower().Contains("procdiv")) {
        return
    }

    # Use HashSet for O(1) duplicate checking
    if (-not $script:duplicateLineCheck.Contains($mmdString)) {
        # IN-MEMORY: Add to ArrayList instead of file I/O
        if ($script:useClientSideRender) {
            [void]$script:mmdSequenceContent.Add($mmdString)
        }
        else {
            Add-Content -Path $script:mmdFilenameSequence -Value $mmdString -Force
        }
        [void]$script:duplicateLineCheck.Add($mmdString)
    }
}
function Get-CblStringBetween {
    param ($firstString, $secondString, $data, $overrideStartPos = 0)
    try {

        if ($overrideStartPos -gt 0) {
            $pos1 = $overrideStartPos
        }
        else {
            if ($firstString -eq "<line_start>") {
                $pos1 = -1
            }
            else {
                $pos1 = $data.IndexOf($firstString)
                if ($pos1 -lt 0) {
                    return $null, $data
                }
            }
        }
        $pos2 = $data.Substring($pos1 + 1).IndexOf($secondString)
        if ($pos2 -lt 0) {
            return $null, $data
        }
        if ($pos1 -lt 0) {
            $pos1 = 0
        }
        $retData = $data.Substring($pos1, $pos2 + 1).Trim()
        return $retData, $data.Substring($pos1 + $pos2 + 1)
    }
    catch {
        return $null, $data
    }

}

function FindParagraphCode {
    param ($array, [string] $paragraphName)
    # Regular expression patterns

    # Initialize variables
    $foundStart = $false
    try {
        $paragraphName = $paragraphName.ToLower()
    }
    catch {
    }

    $extractedElements = @()

    $lineNumber = 0
    # Loop through the array
    foreach ($item in $array) {
        $lineNumber += 1

        if ($item.Trim().StartsWith($paragraphName) -or $item -match $paragraphName) {
            $foundStart = $true
            $extractedElements = @()
        }
        elseif ($foundStart) {
            if (VerifyIfParagraph -paragraphName $item) {
                # if ($item -match $endPattern) {
                $foundStart = $false
                break
            }
            else {
                $extractedElements += $item
            }
        }
    }
    return $extractedElements

}

function GetSqlDeclareCursorPart {
    param ($fileContent, [string] $cursorName)

    $pattern = $cursorName + "(.*?)end-exec" # Use a non-greedy quantifier *? to match the shortest possible string
    $matches = [regex]::Matches($fileContent, $pattern) # Get all the matches as a collection
    foreach ($match in $matches) {
        $match.Groups[1].Value # This will output the text between the two strings for each match
    }

    $extractedElements = @()
    if ($matches.Count -gt 0) {
        $extractedElements = $matches[0].Groups[0].Value
    }

    if ($extractedElements.Count -gt 0) {
        return $extractedElements.ToLower()
    }
    else {
        return $null
    }
}

function FindAllFileDefenitionsAndRelatedRecords {
    param ($fileSectionContent, $srcRootFolder)

    try {
        $fdDataResArrayWithCpy = @()
        foreach ($line in $fileSectionContent) {
            if ($line.StartsWith('copy')) {
                $cpyFile = $line.trim().Split('"')[1]

                $filePath = $srcRootFolder + "\Dedge\cpy\" + $cpyFile
                if (Test-Path -Path $filePath -PathType Leaf) {
                    $cpyData = Get-Content $filePath
                }

                $filePath = $srcRootFolder + "\Dedge\sys\cpy\" + $cpyFile
                if (Test-Path -Path $filePath -PathType Leaf) {
                    $cpyData = Get-Content $filePath
                }

                foreach ($line in $cpyData) {
                    $ustart = $line.IndexOf(" redefines ")
                    if ($ustart -gt 0) {
                        # Removes comment at end of line
                        $line = $line.Substring(0, $ustart).Trim() + "."
                    }

                    $ustart = $line.IndexOf(" pic ")
                    if ($ustart -gt 0) {
                        # Removes comment at end of line
                        $line = $line.Substring(0, $ustart).Trim() + "."
                    }

                    if ($line.Trim().StartsWith("01 ") ) {
                        $fdDataResArrayWithCpy += $line
                    }
                }
            }
            else {
                $ustart = $line.IndexOf(" pic ")
                if ($ustart -gt 0) {
                    # Removes comment at end of line
                    $line = $line.Substring(0, $ustart).Trim() + "."
                }

                if ($line.Trim().StartsWith("01 ") -or $line.Trim().StartsWith("fd ")) {
                    $fdDataResArrayWithCpy += $line
                }
            }
        }

        $fdDataRes = " " + $fdDataResArrayWithCpy -join " "
        $fdDataRes = $fdDataRes.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
        $y = $fdDataRes.Split(" fd ")
        $fileEntries = @{}

        foreach ($temp1 in $y) {
            $temp1 = $temp1.Trim()
            if ($temp1.Replace(".", "") -eq "") {
                continue
            }
            if ($temp1.Replace(".", "") -eq "") {
                continue
            }
            $pos1 = $temp1.IndexOf(".")
            $pos2 = $temp1.IndexOf(" ")
            if ($pos1 -gt $pos2 -and $pos2 -gt 0) {
                $fileName, $restData = Get-CblStringBetween -firstString "<line_start>" -secondString " " -data $temp1 -overrideStartPos 0
            }
            else {
                $fileName, $restData = Get-CblStringBetween -firstString "<line_start>" -secondString "." -data $temp1 -overrideStartPos 0
            }
            if ($fileName.Length -le 0) {
                $filename = $temp1
            }
            $fileName = $fileName.Replace(".", "")
            $fileRecString = ""
            $prevRestData = ""
            $restData = " " + $restData
            while ($prevRestData -cne $restData) {
                $prevRestData = $restData
                $resultString, $restData = Get-CblStringBetween " 01 " "." $restData
                if ($resultString.Length -ne 0) {
                    $resultString = " " + $resultString
                    if ($resultString.Contains(" 01 ")) {
                        $resultString = $resultString.Replace(" 01 ", "")
                    }
                    $fileRecString += "�" + $resultString.Trim()
                }
            }
            $fileRecString += "�"
            $fileEntries.Add($fileName, $fileRecString)

        }
        return $fileEntries
    }
    catch {
        $errorMessage = $_.Exception
        write-host En feil oppstod: $errorMessage
        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
        Write-LogMessage $errorMessage -Level ERROR
        $script:errorOccurred = $true
    }
}

function FindSqlStatementInDb2Command {
    <#
    .SYNOPSIS
        Extracts SQL statements from db2/db2cmd command lines in BAT, REXX, and PS1 files.
    .DESCRIPTION
        Parses db2 command lines to extract SQL operations (SELECT, INSERT, UPDATE, DELETE)
        and table names, similar to FindSqlStatementInExecSql for COBOL files.
    .PARAMETER CommandLine
        The db2 command line to parse (e.g., "db2 select * from dbm.kunde")
    .OUTPUTS
        Returns: sqlOperation, sqlTableNames, cursorName, cursorForUpdate, updateFields
    #>
    param (
        [string]$CommandLine
    )
    
    try {
        if ([string]::IsNullOrWhiteSpace($CommandLine)) {
            return $null, @(), $null, $false, @()
        }
        
        $cursorForUpdate = $false
        $cursorName = $null
        $updateFields = @()
        
        # Normalize the command line - remove db2/db2cmd prefixes and clean up
        $sqlRes = $CommandLine.ToLower().Trim()
        
        # Remove db2 command prefixes
        $sqlRes = $sqlRes -replace '^(db2|db2cmd|start\s+db2cmd)\s+', ''
        $sqlRes = $sqlRes -replace '^call\s+', ''
        $sqlRes = $sqlRes -replace '^start\s+', ''
        
        # Remove quotes and clean up whitespace
        $sqlRes = $sqlRes.Replace('"', '').Replace("'", '').Trim()
        $sqlRes = $sqlRes -replace '\s+', ' '
        
        if ($sqlRes.Length -eq 0) {
            return $null, @(), $null, $false, @()
        }
        
        # Check if line contains SQL keywords
        $sqlKeywords = @('select', 'insert', 'update', 'delete', 'fetch', 'call', 'declare', 'cursor')
        $hasSqlKeyword = $false
        foreach ($keyword in $sqlKeywords) {
            if ($sqlRes -match "\b$keyword\b") {
                $hasSqlKeyword = $true
                break
            }
        }
        
        if (-not $hasSqlKeyword) {
            return $null, @(), $null, $false, @()
        }
        
        # Extract SQL operation - look for SELECT, INSERT, UPDATE, DELETE, FETCH, CALL
        $sqlOperation = $null
        $restData = $sqlRes
        
        if ($sqlRes -match '\b(select|insert|update|delete|fetch|call)\b') {
            $sqlOperation = $Matches[1].ToUpper()
            # Get everything after the operation keyword
            $pos = $sqlRes.IndexOf($Matches[1]) + $Matches[1].Length
            $restData = $sqlRes.Substring($pos).Trim()
        }
        elseif ($sqlRes -match '\bdeclare\s+cursor\b') {
            # DECLARE CURSOR - extract cursor name and SELECT statement
            $sqlOperation = "SELECT"
            if ($sqlRes -match '\bdeclare\s+cursor\s+(\w+)') {
                $cursorName = $Matches[1]
            }
            # Extract SELECT part after CURSOR ... FOR
            if ($sqlRes -match '\bfor\s+(.+)$') {
                $restData = $Matches[1].Trim()
            }
        }
        
        if (-not $sqlOperation) {
            return $null, @(), $null, $false, @()
        }
        
        # Check for FOR UPDATE in cursor declarations
        if ($restData -match '\bfor\s+update\b') {
            $cursorForUpdate = $true
            $restData = $restData -replace '\bfor\s+update\b', ''
        }
        
        # Extract table names using schema.table pattern
        # Pattern matches: dbm.table, hst.table, log.table, crm.table, tv.table
        # Regex breakdown:
        #   (dbm\.|hst\.|log\.|crm\.|tv\.)  - Match schema prefix (capture group 1)
        #   (.*?)                            - Match table name (non-greedy, capture group 2)
        #   (?=\s|;|\)|,|$)                  - Lookahead: stop at whitespace, semicolon, closing paren, comma, or end
        $pattern = "(dbm\.|hst\.|log\.|crm\.|tv\.)([a-z0-9_]+)(?=\s|;|\)|,|$)"
        $tableMatches = [regex]::Matches($restData, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        $sqlTableNames = @()
        if ($tableMatches.Count -gt 0) {
            foreach ($match in $tableMatches) {
                $schema = $match.Groups[1].Value.ToLower()
                $table = $match.Groups[2].Value.ToLower()
                $fullTableName = $schema + $table
                
                # Clean up table name
                $fullTableName = $fullTableName -replace '[\)\]\};,]', ''
                $fullTableName = $fullTableName -replace ';', ''
                
                if ($fullTableName.Length -gt 0) {
                    $sqlTableNames += $fullTableName
                }
            }
        }
        
        # Extract field names for UPDATE statements
        if ($sqlOperation -eq "UPDATE" -and $sqlTableNames.Count -gt 0) {
            # Pattern: Extract text between SET and WHERE (or end of statement)
            # Regex breakdown:
            #   \bset\b     - Match word "set" with word boundaries
            #   \s+         - One or more whitespace
            #   (.+?)       - Capture group: match any chars (non-greedy)
            #   (?=\bwhere\b|$) - Lookahead: stop at "where" or end of string
            $setPattern = "\bset\b\s+(.+?)(?=\bwhere\b|$)"
            $setMatch = [regex]::Match($restData, $setPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($setMatch.Success) {
                $setClause = $setMatch.Groups[1].Value
                # Regex breakdown:
                #   (\w+)     - Capture group: one or more word characters (field name)
                #   \s*=      - Optional whitespace followed by equals sign
                $fieldPattern = "(\w+)\s*="
                $fieldMatches = [regex]::Matches($setClause, $fieldPattern)
                foreach ($fieldMatch in $fieldMatches) {
                    $fieldName = $fieldMatch.Groups[1].Value.Trim()
                    if ($fieldName.Length -gt 0) {
                        $updateFields += $fieldName
                    }
                }
            }
        }
        
        # Remove duplicates and return
        $sqlTableNames = $sqlTableNames | Sort-Object -Unique
        
        return $sqlOperation, $sqlTableNames, $cursorName, $cursorForUpdate, $updateFields
    }
    catch {
        Write-LogMessage "Error in FindSqlStatementInDb2Command: $($_.Exception.Message)" -Level WARN
        return $null, @(), $null, $false, @()
    }
}

function FindSqlStatementInExecSql {
    param ($inCode, $fileContent, $procedureContent)
    try {
        if ($inCode.length -le 0 ) {
            return
        }
        if ($inCode.length -le 0) {
            return
        }

        $cursorForUpdate = $false

        $sqlRes = " " + $inCode -join " "
        $sqlRes = " " + $sqlRes.ToLower().Trim() + " "

        $sqlRes = $sqlRes.Replace("  ", " ")
        $sqlRes = $sqlRes.Replace("  ", " ")
        $sqlRes = $sqlRes.Replace("  ", " ")
        $sqlRes = $sqlRes.Replace("exec sql", "")
        $sqlRes = $sqlRes.Replace("end-exec", "")
        $sqlRes = $sqlRes.Trim()
        if ($sqlRes.Length -le 0) {
            return
        }

        $pos = $sqlRes.IndexOf(" ")
        if ($pos -le 0) {
            return
        }

        $sqlOperation = $sqlRes.Substring(0, $pos).ToUpper()
        $restData = $sqlRes.Substring($pos + 1)

        $restData = $restData.ToLower()
        if ($sqlOperation -eq "FETCH") {
            $pos = $restData.IndexOf(" ")
            $cursorName = $restData.Substring(0, $pos)
            $cursorContent = GetSqlDeclareCursorPart -fileContent $fileContent -cursorName $cursorName
            $cursorContentJoin = " " + $cursorContent -join " "
            $restData = $cursorContentJoin.ToLower().Trim()
            if ($restData.Contains("for update")) {
                $cursorForUpdate = $true
            }
        }

        # $pattern = "dbm\.(.*?)\s" # Use a non-greedy quantifier *? to match the shortest possible string
        $pattern = "(dbm\.|hst\.|log\.|crm\.|tv\.)(.*?)\s" # Use a non-greedy quantifier *? to match the shortest possible string
        $matches1 = [regex]::Matches($restData, $pattern) # Get all the matches as a collection

        $sqlTableNames = @( )
        if ($matches1.Count -gt 0) {
            foreach ($currentItemName in $matches1) {
                $temp = $currentItemName.Captures[0].ToString()
                if ($temp.Contains(")")) {
                    $temp = $temp.Replace(")", "")
                }
                if ($temp.Contains(";")) {
                    $temp = $temp.Replace(";", "")
                }
                $sqlTableNames += $temp.Trim()
            }
        }

        # Extract field names for UPDATE statements
        # Pattern: Extract text between SET and WHERE (or end of statement)
        # Then parse field names from "field = value" pairs
        $updateFields = @()
        if ($sqlOperation -eq "UPDATE") {
            # Regex breakdown:
            #   \bset\b     - Match word "set" with word boundaries
            #   \s+         - One or more whitespace
            #   (.+?)       - Capture group: match any chars (non-greedy)
            #   (?=\bwhere\b|$) - Lookahead: stop at "where" or end of string
            $setPattern = "\bset\b\s+(.+?)(?=\bwhere\b|$)"
            $setMatch = [regex]::Match($restData, $setPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($setMatch.Success) {
                $setClause = $setMatch.Groups[1].Value
                # Regex breakdown:
                #   (\w+)     - Capture group: one or more word characters (field name)
                #   \s*=      - Optional whitespace followed by equals sign
                $fieldPattern = "(\w+)\s*="
                $fieldMatches = [regex]::Matches($setClause, $fieldPattern)
                foreach ($fieldMatch in $fieldMatches) {
                    $fieldName = $fieldMatch.Groups[1].Value.Trim()
                    if ($fieldName.Length -gt 0) {
                        $updateFields += $fieldName
                    }
                }
            }
        }

        return $sqlOperation, $sqlTableNames, $cursorName, $cursorForUpdate, $updateFields
    }
    catch {
        $errorMessage = $_.Exception
        write-host En feil oppstod: $errorMessage
        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
        Write-LogMessage $errorMessage -Level ERROR
        $script:errorOccurred = $true
    }
}

function FindSqlStatementInCSharp {
    <#
    .SYNOPSIS
        Extracts SQL statements from C# code patterns.
    .DESCRIPTION
        Parses C# code to extract SQL operations (SELECT, INSERT, UPDATE, DELETE)
        and table names from various patterns:
        - Raw SQL strings: "SELECT * FROM dbm.kunde"
        - CommandText assignments: command.CommandText = "SELECT ..."
        - String variables: string sql = "SELECT ..."
        - Dapper queries: connection.Query("SELECT ...")
        - Multi-line strings: @"SELECT ... FROM ..."
    .PARAMETER CodeLine
        The C# code line or string containing potential SQL.
    .OUTPUTS
        Returns: sqlOperation, sqlTableNames, updateFields
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$CodeLine
    )
    
    try {
        if ([string]::IsNullOrWhiteSpace($CodeLine)) {
            return $null, @(), @()
        }
        
        $updateFields = @()
        
        # Normalize the code line - extract SQL string content
        $sqlRes = $CodeLine.Trim()
        
        # Handle C# string patterns
        # Remove string delimiters and escape sequences
        # Pattern 1: Regular strings: "SELECT ..."
        if ($sqlRes -match '"([^"]+)"') {
            $sqlRes = $Matches[1]
        }
        # Pattern 2: Verbatim strings: @"SELECT ..."
        elseif ($sqlRes -match '@"([^"]+)"') {
            $sqlRes = $Matches[1]
        }
        # Pattern 3: Single-quoted strings: 'SELECT ...'
        elseif ($sqlRes -match "'([^']+)'") {
            $sqlRes = $Matches[1]
        }
        # Pattern 4: CommandText assignments: command.CommandText = "SELECT ..."
        elseif ($sqlRes -match '\.CommandText\s*=\s*["'']([^"'']+)["'']') {
            $sqlRes = $Matches[1]
        }
        # Pattern 5: Dapper Query: connection.Query("SELECT ...")
        elseif ($sqlRes -match '\.Query(?:<[^>]+>)?\s*\(["'']([^"'']+)["'']') {
            $sqlRes = $Matches[1]
        }
        # Pattern 6: String variables: string sql = "SELECT ..."
        elseif ($sqlRes -match '(?:string|var)\s+\w+\s*=\s*["'']([^"'']+)["'']') {
            $sqlRes = $Matches[1]
        }
        
        # Handle C# escape sequences
        $sqlRes = $sqlRes -replace '\\"', '"'
        $sqlRes = $sqlRes -replace "\\'", "'"
        $sqlRes = $sqlRes -replace '\\n', ' '
        $sqlRes = $sqlRes -replace '\\r', ' '
        $sqlRes = $sqlRes -replace '\\t', ' '
        
        # Normalize whitespace
        $sqlRes = $sqlRes.ToLower().Trim()
        $sqlRes = $sqlRes -replace '\s+', ' '
        
        if ($sqlRes.Length -eq 0) {
            return $null, @(), @()
        }
        
        # Check if line contains SQL keywords
        $sqlKeywords = @('select', 'insert', 'update', 'delete', 'call', 'declare', 'cursor')
        $hasSqlKeyword = $false
        foreach ($keyword in $sqlKeywords) {
            if ($sqlRes -match "\b$keyword\b") {
                $hasSqlKeyword = $true
                break
            }
        }
        
        if (-not $hasSqlKeyword) {
            return $null, @(), @()
        }
        
        # Extract SQL operation - look for SELECT, INSERT, UPDATE, DELETE, CALL
        $sqlOperation = $null
        $restData = $sqlRes
        
        if ($sqlRes -match '\b(select|insert|update|delete|call)\b') {
            $sqlOperation = $Matches[1].ToUpper()
            # Get everything after the operation keyword
            $pos = $sqlRes.IndexOf($Matches[1]) + $Matches[1].Length
            $restData = $sqlRes.Substring($pos).Trim()
        }
        elseif ($sqlRes -match '\bdeclare\s+cursor\b') {
            # DECLARE CURSOR - extract cursor name and SELECT statement
            $sqlOperation = "SELECT"
            # Extract SELECT part after CURSOR ... FOR
            if ($sqlRes -match '\bfor\s+(.+)$') {
                $restData = $Matches[1].Trim()
            }
        }
        
        if (-not $sqlOperation) {
            return $null, @(), @()
        }
        
        # Extract table names using schema.table pattern
        # Pattern matches: dbm.table, hst.table, log.table, crm.table, tv.table
        # Regex breakdown:
        #   (dbm\.|hst\.|log\.|crm\.|tv\.)  - Match schema prefix (capture group 1)
        #   ([a-z0-9_]+)                    - Match table name (alphanumeric and underscores, capture group 2)
        #   (?=\s|;|\|\)|,|$)                  - Lookahead: stop at whitespace, semicolon, closing paren, comma, or end
        $pattern = "(dbm\.|hst\.|log\.|crm\.|tv\.)([a-z0-9_]+)(?=\s|;|\|\)|,|$)"
        $tableMatches = [regex]::Matches($restData, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        $sqlTableNames = @()
        if ($tableMatches.Count -gt 0) {
            foreach ($match in $tableMatches) {
                $schema = $match.Groups[1].Value.ToLower()
                $table = $match.Groups[2].Value.ToLower()
                $fullTableName = $schema + $table
                
                # Clean up table name
                $fullTableName = $fullTableName -replace '[)\]};,]', ''
                $fullTableName = $fullTableName -replace ';', ''
                
                if ($fullTableName.Length -gt 0) {
                    $sqlTableNames += $fullTableName
                }
            }
        }
        
        # Extract field names for UPDATE statements
        if ($sqlOperation -eq "UPDATE" -and $sqlTableNames.Count -gt 0) {
            # Pattern: Extract text between SET and WHERE (or end of statement)
            # Regex breakdown:
            #   \bset\b     - Match word "set" with word boundaries
            #   \s+         - One or more whitespace
            #   (.+?)       - Capture group: match any chars (non-greedy)
            #   (?=\bwhere\b|$) - Lookahead: stop at "where" or end of string
            $setPattern = "\bset\b\s+(.+?)(?=\bwhere\b|$)"
            $setMatch = [regex]::Match($restData, $setPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($setMatch.Success) {
                $setClause = $setMatch.Groups[1].Value
                # Regex breakdown:
                #   (\w+)     - Capture group: one or more word characters (field name)
                #   \s*=      - Optional whitespace followed by equals sign
                $fieldPattern = "(\w+)\s*="
                $fieldMatches = [regex]::Matches($setClause, $fieldPattern)
                foreach ($fieldMatch in $fieldMatches) {
                    $fieldName = $fieldMatch.Groups[1].Value.Trim()
                    if ($fieldName.Length -gt 0) {
                        $updateFields += $fieldName
                    }
                }
            }
        }
        
        # Remove duplicates and return
        $sqlTableNames = $sqlTableNames | Sort-Object -Unique
        
        return $sqlOperation, $sqlTableNames, $updateFields
    }
    catch {
        Write-LogMessage "Error in FindSqlStatementInCSharp: $($_.Exception.Message)" -Level WARN
        return $null, @(), @()
    }
}

function ExtractEntityFrameworkTables {
    <#
    .SYNOPSIS
        Extracts table names from Entity Framework patterns in C# code.
    .DESCRIPTION
        Detects Entity Framework patterns like:
        - context.TableName.Where(...)
        - dbSet.Select(...)
        - _context.Kunde.FirstOrDefault(...)
        Maps DbSet names to database tables (assumes dbm schema by default).
    .PARAMETER CodeLine
        The C# code line containing Entity Framework patterns.
    .OUTPUTS
        Returns: sqlOperation, sqlTableNames
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$CodeLine
    )
    
    try {
        $sqlTableNames = @()
        $sqlOperation = $null
        
        # Pattern 1: context.TableName or _context.TableName
        # Matches: context.Kunde.Where, _context.Order.Select, etc.
        if ($CodeLine -match '(?:context|_context|dbContext|_dbContext)\.(\w+)\.(Where|Select|FirstOrDefault|First|Single|SingleOrDefault|ToList|Count|Any|All|OrderBy|GroupBy)') {
            $tableName = $Matches[1].ToLower()
            $method = $Matches[2].ToLower()
            
            # Map method to SQL operation
            if ($method -in @('where', 'select', 'firstordefault', 'first', 'single', 'singleordefault', 'tolist', 'count', 'any', 'all', 'orderby', 'groupby')) {
                $sqlOperation = "SELECT"
            }
            
            # Assume dbm schema (can be enhanced with configuration)
            $fullTableName = "dbm." + $tableName
            $sqlTableNames += $fullTableName
        }
        # Pattern 2: dbSet variable usage
        # Matches: _kundeDbSet.Where, orders.Select, etc.
        elseif ($CodeLine -match '(\w+DbSet|\w+Set)\.(Where|Select|FirstOrDefault|Add|Update|Remove|RemoveRange)') {
            $dbSetName = $Matches[1].ToLower()
            $method = $Matches[2].ToLower()
            
            # Remove DbSet suffix and pluralization hints
            $tableName = $dbSetName -replace 'dbset$', '' -replace 'set$', ''
            # Handle pluralization: Kunder -> kunde, Orders -> order
            if ($tableName.EndsWith('er')) {
                $tableName = $tableName.Substring(0, $tableName.Length - 2)
            }
            elseif ($tableName.EndsWith('s') -and $tableName.Length -gt 1) {
                $tableName = $tableName.Substring(0, $tableName.Length - 1)
            }
            
            # Map method to SQL operation
            if ($method -in @('where', 'select', 'firstordefault')) {
                $sqlOperation = "SELECT"
            }
            elseif ($method -in @('add', 'update')) {
                $sqlOperation = "INSERT"
            }
            elseif ($method -in @('remove', 'removerange')) {
                $sqlOperation = "DELETE"
            }
            
            if ($tableName.Length -gt 0) {
                $fullTableName = "dbm." + $tableName
                $sqlTableNames += $fullTableName
            }
        }
        
        return $sqlOperation, $sqlTableNames
    }
    catch {
        Write-LogMessage "Error in ExtractEntityFrameworkTables: $($_.Exception.Message)" -Level WARN
        return $null, @()
    }
}

function ScanCSharpMethodForSql {
    <#
    .SYNOPSIS
        Scans a C# method body for SQL statements.
    .DESCRIPTION
        Scans method body for various SQL patterns:
        - String literals containing SQL keywords
        - CommandText assignments
        - Dapper Query/QueryAsync calls
        - Entity Framework patterns
    .PARAMETER MethodBody
        The method body code as a string.
    .PARAMETER MethodName
        Name of the method (for logging).
    .PARAMETER ClassName
        Name of the class (for logging).
    .OUTPUTS
        Returns array of hashtables: @{Operation, Tables[], Fields[], LineNumber}
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MethodBody,
        [Parameter(Mandatory = $false)]
        [string]$MethodName = "",
        [Parameter(Mandatory = $false)]
        [string]$ClassName = ""
    )
    
    $sqlStatements = @()
    
    try {
        if ([string]::IsNullOrWhiteSpace($MethodBody)) {
            return $sqlStatements
        }
        
        # Split method body into lines for line number tracking
        $lines = $MethodBody -split "`n"
        $lineNumber = 0
        
        foreach ($line in $lines) {
            $lineNumber++
            $lineTrimmed = $line.Trim()
            
            if ([string]::IsNullOrWhiteSpace($lineTrimmed)) {
                continue
            }
            
            # Skip comments
            if ($lineTrimmed.StartsWith("//") -or $lineTrimmed.StartsWith("/*") -or $lineTrimmed.StartsWith("*")) {
                continue
            }
            
            # Pattern 1: Raw SQL strings (regular and verbatim)
            # Matches: "SELECT * FROM dbm.kunde", @"SELECT ... FROM ..."
            if ($lineTrimmed -match '["'']\s*(?:select|insert|update|delete|call)\s+.*?from\s+.*?(?:dbm|hst|log|crm|tv)\.', 'IgnoreCase') {
                $sqlOperation, $sqlTableNames, $updateFields = FindSqlStatementInCSharp -CodeLine $lineTrimmed
                if ($sqlOperation -and $sqlTableNames.Count -gt 0) {
                    $sqlStatements += @{
                        Operation   = $sqlOperation
                        Tables      = $sqlTableNames
                        Fields      = $updateFields
                        LineNumber  = $lineNumber
                        Source      = "Raw SQL String"
                    }
                }
            }
            
            # Pattern 2: CommandText assignments
            # Matches: command.CommandText = "SELECT ...", cmd.CommandText = @"SELECT ..."
            if ($lineTrimmed -match '\.CommandText\s*=\s*["'']') {
                $sqlOperation, $sqlTableNames, $updateFields = FindSqlStatementInCSharp -CodeLine $lineTrimmed
                if ($sqlOperation -and $sqlTableNames.Count -gt 0) {
                    $sqlStatements += @{
                        Operation   = $sqlOperation
                        Tables      = $sqlTableNames
                        Fields      = $updateFields
                        LineNumber  = $lineNumber
                        Source      = "CommandText"
                    }
                }
            }
            
            # Pattern 3: Dapper Query calls
            # Matches: connection.Query("SELECT ..."), connection.QueryAsync<string>("SELECT ...")
            if ($lineTrimmed -match '\.Query(?:<[^>]+>)?\s*\(["'']') {
                $sqlOperation, $sqlTableNames, $updateFields = FindSqlStatementInCSharp -CodeLine $lineTrimmed
                if ($sqlOperation -and $sqlTableNames.Count -gt 0) {
                    $sqlStatements += @{
                        Operation   = $sqlOperation
                        Tables      = $sqlTableNames
                        Fields      = $updateFields
                        LineNumber  = $lineNumber
                        Source      = "Dapper"
                    }
                }
            }
            
            # Pattern 4: Entity Framework patterns
            # Matches: context.Kunde.Where(...), _context.Order.Select(...)
            $efOperation, $efTables = ExtractEntityFrameworkTables -CodeLine $lineTrimmed
            if ($efOperation -and $efTables.Count -gt 0) {
                $sqlStatements += @{
                    Operation   = $efOperation
                    Tables      = $efTables
                    Fields      = @()
                    LineNumber  = $lineNumber
                    Source      = "Entity Framework"
                }
            }
        }
        
        # Handle multi-line SQL strings (verbatim strings spanning multiple lines)
        # Pattern: @"SELECT ... FROM ... WHERE ..."
        $verbatimPattern = '@"([^"]*(?:select|insert|update|delete|call)[^"]*)"'
        $verbatimMatches = [regex]::Matches($MethodBody, $verbatimPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        foreach ($match in $verbatimMatches) {
            $sqlOperation, $sqlTableNames, $updateFields = FindSqlStatementInCSharp -CodeLine $match.Value
            if ($sqlOperation -and $sqlTableNames.Count -gt 0) {
                # Check if already added (avoid duplicates)
                $isDuplicate = $false
                foreach ($existing in $sqlStatements) {
                    if ($existing.Operation -eq $sqlOperation -and 
                        ($existing.Tables | Compare-Object $sqlTableNames -PassThru).Count -eq 0) {
                        $isDuplicate = $true
                        break
                    }
                }
                if (-not $isDuplicate) {
                    $sqlStatements += @{
                        Operation   = $sqlOperation
                        Tables      = $sqlTableNames
                        Fields      = $updateFields
                        LineNumber  = 0  # Multi-line, can't determine exact line
                        Source      = "Multi-line Verbatim String"
                    }
                }
            }
        }
        
        # Handle string concatenation patterns
        # Pattern: "SELECT " + field + " FROM dbm.kunde"
        $concatPattern = '["'']\s*(?:select|insert|update|delete)\s+.*?\+.*?from\s+.*?(?:dbm|hst|log|crm|tv)\.'
        if ($MethodBody -match $concatPattern -and $MethodBody -notmatch '@"') {
            # Try to extract SQL from concatenated strings
            $sqlOperation, $sqlTableNames, $updateFields = FindSqlStatementInCSharp -CodeLine $MethodBody
            if ($sqlOperation -and $sqlTableNames.Count -gt 0) {
                $sqlStatements += @{
                    Operation   = $sqlOperation
                    Tables      = $sqlTableNames
                    Fields      = $updateFields
                    LineNumber  = 0
                    Source      = "String Concatenation"
                }
            }
        }
    }
    catch {
        Write-LogMessage "Error in ScanCSharpMethodForSql for method $MethodName in class $ClassName : $($_.Exception.Message)" -Level WARN
    }
    
    return $sqlStatements
}

function FindStringInHashtable {
    param ($hashTable, $searchString)

    foreach ($entry in $hashTable.GetEnumerator()) {
        $key = $entry.Key
        $value = $entry.Value

        if ($value.Contains($searchString)) {
            return $key
        }
    }
}

function HandleDiagramGeneration ($workArray, $procedureContent, $fileSectionLineNumber, $workingStorageLineNumber, $fileSectionContent) {

    # Flowchart diagram
    WriteMmdFlow -mmdString "%%{ init: { 'flowchart': { 'curve': 'basis' } } }%%"
    WriteMmdFlow -mmdString "flowchart TD"
    $programName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile).ToLower()

    $resultArrayProxy = @()

    $testString = $fileContentOriginal | select-string "-proxy"
    $pattern = '(?<=")[^"]*(?=")'
    try {

        $resultArrayProxy = [regex]::Matches($testString, $pattern) # Get all the matches as a collection
        if ($resultArrayProxy.Count -eq 0) {
            $pattern = "(?<=\')[^\']*(?=\')"
            $resultArrayProxy = [regex]::Matches($testString, $pattern) # Get all the matches as a collection
        }
    }
    catch {
    }

    $proxyFilename = ""
    if ($resultArrayProxy.Count -gt 0) {
        $proxyClass = $resultArrayProxy[0].Value
        $proxyFilename = $srcRootFolder + "\Dedge\cbl\" + $proxyClass + ".cbl"
        $proxyClass = $proxyClass.Replace("-proxy", "")
        $proxyFileContent = Get-Content $proxyFilename -Encoding ([System.Text.Encoding]::GetEncoding(1252))
    }

    $fileContent = @()
    $fileContent = $workArray

    $workContent = $procedureContent | Select-String -Pattern @(".*\-.*\.", "perform.*until", "perform\s*varying", ".*perform", "not at end perform", "end\-perform", "call\s*", "read\s*", "write\s*", "stop\s*run", "exec\s*sql", "end\-exec", "procedure\s*division")

    #Find all files and related records
    $fdHashtable = FindAllFileDefenitionsAndRelatedRecords -fileSectionContent $fileSectionContent -srcRootFolder $srcRootFolder

    # Initialization
    $currentParticipant = ""
    $currentParagraphName = ""

    $loopCounter = 0
    $previousParticipant = ""
    $counter = 0
    $isSqlCodeInParagraphHandled = $false
    $paragraphCodeExceptLoopCode = { }.Invoke()
    $counter = 0
    if ($workContent.Count -eq 0) {
        Write-LogMessage "No work content found" -Level ERROR
        exit
    }
    # Loop through all workContent
    foreach ($lineObject in $workContent) {
        $counter += 1
        if ($lineObject.LineNumber -eq 147) {
        }
        $line = $procedureContent[$lineObject.LineNumber - 1]
        $lineNumber = $lineObject.LineNumber
        $counter += 1
        if ($line.StartsWith("*")) {
            Continue
        }
        # LogMessage -message ("Line " + $lineNumber + ": " + $line)
        # Paragraph handling
        $previousParticipant = $currentParagraphName

        if ($line -match "^.*M[0-9]+\-.*\." -or $line -match "procedure.division" -or $line -match "procedure.*division" ) {
            if ($line.contains("entry")) {
                continue
            }

            $verifiedParagraph = $false
            if ($line -match "procedure.division" -or $line -match "procedure.*division") {
                $currentParticipant = "procedure_division"
                $paragraphCode = FindParagraphCode  -array $procedureContent -paragraphName "procedure.*division"

                $currentParagraphName = $currentParticipant.Trim()
                $verifiedParagraph = $true
            }
            else {
                $verifiedParagraph = VerifyIfParagraph -paragraphName ($line.Trim())
                if ($verifiedParagraph) {
                    if ($previousParticipant -eq "procedure_division" -and $line.replace(".", "").Trim() -ne "procedure_division") {
                        $statement = "procedure_division->>" + $line.replace(".", "").Trim() + ": start"
                        WriteMmdSequence -mmdString $statement
                        $statement = "participant procedure_division"
                        WriteMmdSequence -mmdString $statement
                    }
                    $pos = $line.IndexOf(".")
                    $participant = $line.Substring(0, $pos).Trim().Replace("--", "-")

                    $statement = "participant " + $participant.replace(".", "").Trim()
                    WriteMmdSequence -mmdString $statement

                    if ($paragraphCodeExceptLoopCode.Count -gt 0) {
                        if ($previousParticipant.Contains("m250")) {
                        }
                        $loopCounter = 0
                        # Generate nodes previous paragraph
                        New-CblNodes -paragraphCode $paragraphCodeExceptLoopCode -procedureContent $procedureContent -fileContent $fileContent -paragraphName $previousParticipant -fdHashtable $fdHashtable -loopCounter $loopCounter
                    }

                    $pos = $line.IndexOf(".")
                    $currentParticipant = $line.Substring(0, $pos).Trim().Replace("--", "-")
                    $currentParagraphName = $currentParticipant.Trim()
                    $paragraphCode = FindParagraphCode  -array $procedureContent -paragraphName $currentParticipant
                }
            }

            if ($verifiedParagraph) {
                $loopLevel = { }.Invoke()
                $loopNodeContent = { }.Invoke()
                $loopCode = { }.Invoke()
                $paragraphCodeExceptLoopCode = { }.Invoke()

                $isSqlCodeInParagraphHandled = $false

                # Handling program name to initital paragraph
                if ($previousParticipant.Length -eq 0 -and ($currentParticipant.Length -gt 0 -or $currentParticipant -eq "procedure_division")) {
                    $statement = $programName + "[[" + $programName + "]]" + " --initiated-->" + $currentParticipant + "((" + $currentParticipant + "))"
                    WriteMmdFlow -mmdString $statement
                    $statement = "style " + $programName + " stroke:red,stroke-width:4px"
                    WriteMmdFlow -mmdString $statement

                }
                if ($previousParticipant -eq "procedure_division") {
                    $statement = $previousParticipant + "(" + $previousParticipant + ")" + " --start-->" + $currentParticipant + "(" + $currentParticipant + ")"
                    WriteMmdFlow -mmdString $statement
                }
            }
        }

        if ($paragraphCode.Length -eq 0) {
            Continue
        }

        $skipLine = $false
        # Perform handling
        if ($currentParagraphName.Contains("m100-program-uke")) {
        }
        if ($line.Contains("perform m050-write-record")) {
        }

        if ($line.trim().contains("perform until") -or $line.trim().contains("perform varying") -or $line.trim().contains("until") -or ($line.trim().contains("perform") -and $line.trim().contains(" times") ) -or $line.trim().contains("perform exit") -or $line.ToLower().trim().contains("perform with test before") ) {
            if ($currentParagraphName.Contains("m100-program-uke")) {
                Write-LogMessage ("Line " + $lineNumber + ": " + $line) -Level DEBUG
            }
            $loopCounter += 1
            if ($loopCounter -gt 1) {
                $fromNode = $loopLevel[($loopCounter - 2)]
                $toNode = $loopLevel[($loopCounter - 2)] + $loopCounter + "((" + $loopLevel[($loopCounter - 2)] + $loopCounter + "))"
                $loopLevel.Add($currentParticipant + "-loop" + $loopCounter )
            }
            else {
                $fromNode = $currentParticipant
                $toNode = $currentParticipant + "-loop" + "((" + $currentParticipant + "-loop))"
                $loopLevel.Add($currentParticipant + "-loop")
            }
            $loopNodeContent.Add($toNode)
            $loopCode.Add("")
            $statement = $fromNode + "--" + '"' + "perform " + '"' + "-->" + $toNode

            WriteMmdFlow -mmdString $statement

            $skipLine = $true
        }
        else {
            if ($line.contains("end-perform")) {
                $workCode = $loopCode[$loopCounter - 1]
                # Generate nodes for current loop
                $statement = "participant " + ($loopLevel[$loopCounter - 1]).Trim()
                WriteMmdSequence -mmdString $statement

                $statement = $fromNode + "->>" + ($loopLevel[$loopCounter - 1]) + ":loop"
                WriteMmdSequence -mmdString $statement

                New-CblNodes -paragraphCode $loopCode[$loopCounter - 1] -procedureContent $procedureContent -fileContent $fileContent -paragraphName ($loopLevel[$loopCounter - 1])  -fdHashtable $fdHashtable -currentLoopCounter $loopCounter

                $loopLevel.RemoveAt($loopCounter - 1)
                $loopNodeContent.RemoveAt($loopCounter - 1)
                $loopCode.RemoveAt($loopCounter - 1)
                $loopCounter -= 1
                $skipLine = $true
            }

        }
        # Accumulate lines
        if ($skipLine -eq $false) {
            if ($currentParagraphName.Contains("m250")) {
            }

            if ($counter -eq 91) {
            }
            if ($loopCounter -gt 0) {
                $workCode = { }.Invoke()
                if ($loopCode[$loopCounter - 1].Length -gt 0 ) {
                    $workCode = $loopCode[$loopCounter - 1]
                }
                $workCode.Add($lineObject)
                $loopCode[$loopCounter - 1] = $workCode
            }
            else {
                $paragraphCodeExceptLoopCode.Add($lineObject)
            }
        }
    }
    $loopCounter = 0
    # Generate nodes for last paragraph
    New-CblNodes -paragraphCode $paragraphCodeExceptLoopCode -procedureContent $procedureContent -fileContent $fileContent -paragraphName $currentParagraphName -fdHashtable $fdHashtable -loopCounter $loopCounter

    # Generate links to sourcecode in Azure devOps
    New-CblMmdLinks -baseFileName $baseFileName -sourceFile $sourceFile -proxyFilename $proxyFilename -proxyClass $proxyClass -proxyFileContent $proxyFileContent

    # Generate
    Get-CblExecutionPathDiagram -srcRootFolder $srcRootFolder -baseFileName $baseFileName -tmpRootFolder $tmpRootFolder

    # Sort participants in sequence diagram
    # IN-MEMORY: Check ArrayList instead of file when using ClientSideRender
    if ($script:useClientSideRender) {
        # Check if we have any sequence content
        if ($script:mmdSequenceContent.Count -eq 0) {
            $statement = "procedure_division->>logic: logic"
            WriteMmdSequence -mmdString $statement
            $statement = "participant procedure_division"
            WriteMmdSequence -mmdString $statement
        }
        
        # Sort participants in the in-memory ArrayList
        $participantArray = @()
        $remainingArray = @()
        $uniqueContent = $script:mmdSequenceContent | Select-Object -Unique
        foreach ($line in $uniqueContent) {
            if ($null -eq $line) { continue }
            $lineStr = $line.ToString()
            if ($lineStr.Contains("-x")) {
                $lineStr = $lineStr.Replace("-x", "_x")
            }
            if ($lineStr.Contains("create-")) {
                $lineStr = $lineStr.Replace("create-", "create_")
            }

            if ($lineStr.Contains("participant")) {
                $participantArray += $lineStr
            }
            else {
                $remainingArray += $lineStr
            }
        }
        
        # Rebuild the sequence content with proper header
        $script:mmdSequenceContent.Clear()
        [void]$script:mmdSequenceContent.Add("sequenceDiagram")
        [void]$script:mmdSequenceContent.Add("autonumber")
        foreach ($p in $participantArray) { [void]$script:mmdSequenceContent.Add($p) }
        foreach ($r in $remainingArray) { [void]$script:mmdSequenceContent.Add($r) }
    }
    else {
        # Original file-based logic
        $tempFileName = $script:mmdFilenameSequence
        if (-Not (Test-Path -Path $tempFileName)) {
            $statement = "procedure_division->>logic: logic"
            WriteMmdSequence -mmdString $statement
            $statement = "participant procedure_division"
            WriteMmdSequence -mmdString $statement
        }

        # read file and sort all participants at start
        $participantArray = @()
        $remainingArray = @()
        $fileContent = Get-Content $script:mmdFilenameSequence
        $fileContent = $fileContent | Select-Object -Unique
        foreach ($line in $fileContent) {
            if ($line.Contains("-x")) {
                $line = $line.Replace("-x", "_x")
            }
            if ($line.Contains("create-")) {
                $line = $line.Replace("create-", "create_")
            }

            if ($line.Contains("participant")) {
                $participantArray += $line.ToString()
            }
            else {
                $remainingArray += $line.ToString()
            }
        }
        $startSequence = @()
        $startSequence += "sequenceDiagram"
        $startSequence += "autonumber"

        $array = @()
        $array = $startSequence + $participantArray + $remainingArray
        Set-Content -Path $script:mmdFilenameSequence -Value $array -Force
    }

}

<#
.SYNOPSIS
    COBOL Parser Functions Module for AutoDoc.

.DESCRIPTION
    Contains the Start-CblParse entry point function that orchestrates
    COBOL file parsing and AutoDoc HTML generation.

.AUTHOR
    Geir Helge Starholm, www.dEdge.no

.NOTES
    Migrated to AutodocFunctions module - 2026-01-19
#>

function Start-CblParse {
    <#
    .SYNOPSIS
        Main entry point for COBOL file parsing.
    
    .DESCRIPTION
        Parses COBOL source files and generates AutoDoc HTML documentation
        with Mermaid flowchart and sequence diagrams.
    
    .PARAMETER SourceFile
        Path to the .cbl file to parse.
    
    .PARAMETER Show
        If true, opens the generated HTML file after creation.
    
    .PARAMETER OutputFolder
        Output folder for generated files.
    
    .PARAMETER CleanUp
        If true, cleans up temporary files after processing.
    
    .PARAMETER TmpRootFolder
        Root folder for temporary files.
    
    .PARAMETER SrcRootFolder
        Root folder for source files.
    
    .PARAMETER ClientSideRender
        Skip SVG generation and use client-side Mermaid.js rendering.
    
    .PARAMETER SaveMmdFiles
        Save Mermaid diagram source files (.mmd) alongside the HTML output.
    
    .OUTPUTS
        Path to the generated HTML file, or $null on error.
    
    .EXAMPLE
        Start-CblParse -SourceFile "C:\src\MYPROG.CBL" -OutputFolder "C:\output"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,
        [bool]$Show = $false,
        [string]$OutputFolder = "$env:OptPath\Webs\AutoDoc",
        [bool]$CleanUp = $true,
        [string]$TmpRootFolder = "$env:OptPath\data\AutoDoc\tmp",
        [string]$SrcRootFolder = "$env:OptPath\data\AutoDoc\src",
        [switch]$ClientSideRender,
        [switch]$SaveMmdFiles
    )
    
    # Initialize script-level variables for CBL parsing
    $script:sequenceNumber = 0
    $baseFileName = [System.IO.Path]::GetFileName($SourceFile)
    $script:baseFileNameTemp = $baseFileName.Replace(".cbl", "")
    
    # Remove dummy file if it exists
    $dummyFile = $OutputFolder + "\" + $baseFileName + ".err"
    if (Test-Path -Path $dummyFile -PathType Leaf) {
        Remove-Item -Path $dummyFile -Force
    }
    
    Write-LogMessage ("Starting parsing of filename:" + $SourceFile) -Level INFO
    
    # Check if the filename contains spaces
    if ($baseFileName.Contains(" ")) {
        Write-LogMessage ("Filename is not valid. Contains spaces:" + $baseFileName) -Level ERROR
        return $null
    }
    
    $script:mmdSequenceElementsWritten = 0
    $StartTime = Get-Date
    $script:logFolder = $OutputFolder
    
    # IN-MEMORY MMD CONTENT - Use ArrayLists for thread-safe accumulation
    $script:mmdFlowContent = [System.Collections.ArrayList]::new()
    $script:mmdSequenceContent = [System.Collections.ArrayList]::new()
    
    # File paths for backwards compatibility (only used when NOT using ClientSideRender)
    $script:mmdFilenameFlow = $OutputFolder + "\" + $baseFileName + ".flow.mmd"
    $script:mmdFilenameSequence = $OutputFolder + "\" + $baseFileName + ".sequence.mmd"
    
    # Clean up old mmd files if they exist (only needed for non-ClientSideRender mode)
    if (-not $ClientSideRender) {
        if (Test-Path -Path $script:mmdFilenameFlow -PathType Leaf) {
            Remove-Item $script:mmdFilenameFlow
        }
        if (Test-Path -Path $script:mmdFilenameSequence -PathType Leaf) {
            Remove-Item $script:mmdFilenameSequence
        }
    }
    
    $script:debugFilename = $OutputFolder + "\" + $baseFileName + ".debug"
    $htmlFilename = $OutputFolder + "\" + $baseFileName + ".html"
    $script:errorOccurred = $false
    $script:sqlTableArray = @()
    $inputDbFileFolder = $TmpRootFolder + "\cobdok"
    $script:duplicateLineCheck = [System.Collections.Generic.HashSet[string]]::new()
    
    # Store ClientSideRender flag for use in functions
    $script:useClientSideRender = $ClientSideRender
    
    Write-LogMessage ("Started for :" + $baseFileName) -Level INFO
    
    # Initialize mmd flow content with empty header (only for file mode)
    if (-not $ClientSideRender) {
        Set-Content -Path $script:mmdFilenameFlow -Value "" -Force
    }
    
    if (Test-Path -Path $SourceFile -PathType Leaf) {
        $fileContentOriginal = Get-Content $SourceFile -Encoding ([System.Text.Encoding]::GetEncoding(1252))
    }
    else {
        Write-LogMessage ("File not found:" + $SourceFile) -Level ERROR
        return $null
    }
    
    # Pre-process file content to remove unwanted lines
    $workArray, $procedureContent, $fileSectionLineNumber, $workingStorageLineNumber, $fileSectionContent = PreProcessFileContent -fileContentOriginal $fileContentOriginal
    
    HandleDiagramGeneration -workArray $workArray -procedureContent $procedureContent -fileSectionLineNumber $fileSectionLineNumber -workingStorageLineNumber $workingStorageLineNumber -fileSectionContent $fileSectionContent
    
    if (-not $baseFileName.ToUpper().Contains("D4BMAL")) {
        # Skip SVG generation when using client-side rendering
        if (-not $ClientSideRender) {
            if (Test-Path -Path $script:mmdFilenameFlow -PathType Leaf) {
                $result = GenerateSvgFile -mmdFilename $script:mmdFilenameFlow
                if ($result -eq $false) {
                    New-Item -Path $dummyFile -ItemType File -Force | Out-Null
                }
            }
            if (Test-Path -Path $script:mmdFilenameSequence -PathType Leaf) {
                $result = GenerateSvgFile -mmdFilename $script:mmdFilenameSequence
                if ($result -eq $false) {
                    New-Item -Path $dummyFile -ItemType File -Force | Out-Null
                }
            }
        }
    }
    
    # Handle what to generate
    if (-not $script:errorOccurred) {
        # Retrieve metadata from exported files from database
        $searchProgramName = $baseFileName.ToLower().Split(".")[0]
        Get-CblMetaData -tmpRootFolder $TmpRootFolder -outputFolder $OutputFolder -baseFileName $baseFileName
        
        if ($Show) {
            & $htmlFilename
        }
    }
    
    $endTime = Get-Date
    $timeDiff = $endTime - $StartTime
    
    # Save MMD files if requested
    if ($SaveMmdFiles) {
        if ($script:mmdFlowContent -and $script:mmdFlowContent.Count -gt 0) {
            $flowMmdOutputPath = Join-Path $OutputFolder ($baseFileName + ".flow.mmd")
            $script:mmdFlowContent | Set-Content -Path $flowMmdOutputPath -Force
            Write-LogMessage ("Saved flow MMD file: $flowMmdOutputPath") -Level INFO
        }
        if ($script:mmdSequenceContent -and $script:mmdSequenceContent.Count -gt 0) {
            $seqMmdOutputPath = Join-Path $OutputFolder ($baseFileName + ".sequence.mmd")
            $script:mmdSequenceContent | Set-Content -Path $seqMmdOutputPath -Force
            Write-LogMessage ("Saved sequence MMD file: $seqMmdOutputPath") -Level INFO
        }
    }
    
    # Log result
    $htmlFilename = $OutputFolder + "\" + $baseFileName + ".html"
    $htmlWasGenerated = Test-Path -Path $htmlFilename -PathType Leaf
    
    if ($htmlWasGenerated) {
        if (Test-Path -Path $dummyFile -PathType Leaf) {
            Remove-Item -Path $dummyFile -Force -ErrorAction SilentlyContinue
        }
        if ($script:errorOccurred) {
            Write-LogMessage ("Time elapsed: " + $timeDiff.Seconds.ToString()) -Level INFO
            Write-LogMessage ("Completed with warnings:" + $baseFileName) -Level WARN
        }
        else {
            Write-LogMessage ("Time elapsed: " + $timeDiff.Seconds.ToString()) -Level INFO
            Write-LogMessage ("Completed successfully:" + $baseFileName) -Level INFO
        }
        return $htmlFilename
    }
    else {
        Write-LogMessage ("*******************************************************************************") -Level ERROR
        Write-LogMessage ("Failed - HTML not generated:" + $SourceFile) -Level ERROR
        Write-LogMessage ("*******************************************************************************") -Level ERROR
        "Error: HTML file was not generated for $baseFileName" | Set-Content -Path $dummyFile -Force
        return $null
    }
}


#endregion

#region Sql Parse Functions
<#
.SYNOPSIS
    SQL Table Parser Functions for AutoDoc.

.DESCRIPTION
    Contains all functions needed to parse SQL tables and generate AutoDoc HTML pages.
    Entry point: Start-SqlParse

.AUTHOR
    Geir Helge Starholm, www.dEdge.no

.NOTES
    Migrated from SqlParse.ps1 to AutodocFunctions module - 2026-01-19
#>

#region SQL Table Enhanced Metadata Functions

function Get-SqlIndexMetadata {
    <#
    .SYNOPSIS
        Retrieves index metadata for a table from indexes.csv.
    #>
    param (
        [string]$InputDbFileFolder,
        [string]$SchemaName,
        [string]$TableName
    )
    
    $indexFile = Join-Path $InputDbFileFolder "indexes.csv"
    if (-not (Test-Path $indexFile)) { return @() }
    
    try {
        $csvData = Import-Csv $indexFile -Header indschema, indname, tabschema, tabname, colnames, uniquerule, colcount, indextype, nleaf, nlevels, fullkeycard, create_time, remarks -Delimiter ';' -ErrorAction SilentlyContinue
        return @($csvData | Where-Object { $_.tabschema -and $_.tabname -and $_.tabschema.Trim() -eq $SchemaName -and $_.tabname.Trim() -eq $TableName })
    }
    catch {
        return @()
    }
}

function Get-SqlConstraintMetadata {
    <#
    .SYNOPSIS
        Retrieves constraint metadata for a table from tabconst.csv.
    #>
    param (
        [string]$InputDbFileFolder,
        [string]$SchemaName,
        [string]$TableName
    )
    
    $constFile = Join-Path $InputDbFileFolder "tabconst.csv"
    if (-not (Test-Path $constFile)) { return @() }
    
    try {
        $csvData = Import-Csv $constFile -Header constname, tabschema, tabname, type, enforced, remarks -Delimiter ';' -ErrorAction SilentlyContinue
        return @($csvData | Where-Object { $_.tabschema -and $_.tabname -and $_.tabschema.Trim() -eq $SchemaName -and $_.tabname.Trim() -eq $TableName })
    }
    catch {
        return @()
    }
}

function Get-SqlKeyColumnMetadata {
    <#
    .SYNOPSIS
        Retrieves key column usage for a table from keycoluse.csv.
    #>
    param (
        [string]$InputDbFileFolder,
        [string]$SchemaName,
        [string]$TableName
    )
    
    $keycolFile = Join-Path $InputDbFileFolder "keycoluse.csv"
    if (-not (Test-Path $keycolFile)) { return @() }
    
    try {
        $csvData = Import-Csv $keycolFile -Header constname, tabschema, tabname, colname, colseq -Delimiter ';' -ErrorAction SilentlyContinue
        return @($csvData | Where-Object { $_.tabschema -and $_.tabname -and $_.tabschema.Trim() -eq $SchemaName -and $_.tabname.Trim() -eq $TableName })
    }
    catch {
        return @()
    }
}

function Get-SqlForeignKeyMetadata {
    <#
    .SYNOPSIS
        Retrieves foreign key relationships for a table from references.csv.
        Returns both outgoing (this table references others) and incoming (others reference this table).
    #>
    param (
        [string]$InputDbFileFolder,
        [string]$SchemaName,
        [string]$TableName
    )
    
    $refFile = Join-Path $InputDbFileFolder "references.csv"
    if (-not (Test-Path $refFile)) { return @{ Outgoing = @(); Incoming = @() } }
    
    try {
        $csvData = Import-Csv $refFile -Header constname, tabschema, tabname, reftabschema, reftabname, refkeyname, fk_colnames, pk_colnames, deleterule, updaterule, colcount, create_time -Delimiter ';' -ErrorAction SilentlyContinue
        
        # Outgoing FKs: this table references other tables
        $outgoing = @($csvData | Where-Object { $_.tabschema -and $_.tabname -and $_.tabschema.Trim() -eq $SchemaName -and $_.tabname.Trim() -eq $TableName })
        
        # Incoming FKs: other tables reference this table
        $incoming = @($csvData | Where-Object { $_.reftabschema -and $_.reftabname -and $_.reftabschema.Trim() -eq $SchemaName -and $_.reftabname.Trim() -eq $TableName })
        
        return @{ Outgoing = $outgoing; Incoming = $incoming }
    }
    catch {
        return @{ Outgoing = @(); Incoming = @() }
    }
}

function Get-SqlTriggerMetadata {
    <#
    .SYNOPSIS
        Retrieves trigger metadata for a table from triggers.csv.
    #>
    param (
        [string]$InputDbFileFolder,
        [string]$SchemaName,
        [string]$TableName
    )
    
    $trigFile = Join-Path $InputDbFileFolder "triggers.csv"
    if (-not (Test-Path $trigFile)) { return @() }
    
    try {
        $csvData = Import-Csv $trigFile -Header trigschema, trigname, tabschema, tabname, trigtime, trigevent, granularity, valid, create_time, remarks -Delimiter ';' -ErrorAction SilentlyContinue
        return @($csvData | Where-Object { $_.tabschema -and $_.tabname -and $_.tabschema.Trim() -eq $SchemaName -and $_.tabname.Trim() -eq $TableName })
    }
    catch {
        return @()
    }
}

function Get-SqlCheckConstraintMetadata {
    <#
    .SYNOPSIS
        Retrieves check constraint metadata from checks.csv.
    #>
    param (
        [string]$InputDbFileFolder,
        [string]$SchemaName,
        [string]$TableName
    )
    
    $checkFile = Join-Path $InputDbFileFolder "checks.csv"
    if (-not (Test-Path $checkFile)) { return @() }
    
    try {
        $csvData = Import-Csv $checkFile -Header constname, tabschema, tabname, create_time, text -Delimiter ';' -ErrorAction SilentlyContinue
        return @($csvData | Where-Object { $_.tabschema -and $_.tabname -and $_.tabschema.Trim() -eq $SchemaName -and $_.tabname.Trim() -eq $TableName })
    }
    catch {
        return @()
    }
}

function New-SqlErDiagram {
    <#
    .SYNOPSIS
        Generates a Mermaid ER diagram showing table relationships.
    .DESCRIPTION
        Creates an Entity-Relationship diagram showing the table columns,
        primary keys, and foreign key relationships to other tables.
    #>
    param (
        [string]$SchemaName,
        [string]$TableName,
        [array]$Columns,
        [array]$PkColumns,
        [hashtable]$ForeignKeys
    )
    
    $mmd = @()
    $mmd += "erDiagram"
    
    $safeTableName = "$($SchemaName)_$TableName" -replace '[^a-zA-Z0-9_]', ''
    
    # Main table entity
    $mmd += "    $safeTableName {"
    
    foreach ($col in $Columns) {
        $colName = $col.colname.Trim()
        $typeName = $col.typename.Trim()
        $length = $col.length
        $isPk = $PkColumns -contains $colName
        
        # Format data type for Mermaid ER diagram
        # Mermaid requires single-word types - no spaces or parentheses
        # Replace multi-word types (e.g., "LONG VARCHAR" -> "LONGVARCHAR")
        # Remove length specifiers as they contain parentheses which break parsing
        $dataType = $typeName -replace '\s+', ''  # Remove spaces from multi-word types
        
        # Mark primary keys
        $pkMarker = if ($isPk) { "PK" } else { "" }
        
        # Check if this is an FK column
        $fkMarker = ""
        foreach ($fk in $ForeignKeys.Outgoing) {
            if ($fk.fk_colnames.Trim() -match "\b$colName\b") {
                $fkMarker = "FK"
                break
            }
        }
        
        $markers = @($pkMarker, $fkMarker) | Where-Object { $_ }
        $markerStr = if ($markers) { " `"$($markers -join ',')`"" } else { "" }
        
        $mmd += "        $dataType $colName$markerStr"
    }
    $mmd += "    }"
    
    # Add related tables and relationships
    foreach ($fk in $ForeignKeys.Outgoing) {
        $refSchema = $fk.reftabschema.Trim()
        $refTable = $fk.reftabname.Trim()
        $safeRefName = "$($refSchema)_$refTable" -replace '[^a-zA-Z0-9_]', ''
        
        # Add reference table (minimal - just show it exists)
        $mmd += "    $safeRefName {"
        $mmd += "        string PK_COLUMN"
        $mmd += "    }"
        
        # Add relationship line
        $fkCols = $fk.fk_colnames.Trim() -replace '\+', '' -replace '-', ''
        $mmd += "    $safeTableName }o--|| $($safeRefName) : `"$fkCols`""
    }
    
    # Add incoming relationships (tables that reference this one)
    foreach ($fk in $ForeignKeys.Incoming) {
        $childSchema = $fk.tabschema.Trim()
        $childTable = $fk.tabname.Trim()
        $safeChildName = "$($childSchema)_$childTable" -replace '[^a-zA-Z0-9_]', ''
        
        # Add child table
        $mmd += "    $safeChildName {"
        $mmd += "        string FK_COLUMN"
        $mmd += "    }"
        
        $fkCols = $fk.fk_colnames.Trim() -replace '\+', '' -replace '-', ''
        $mmd += "    $safeChildName }o--|| $safeTableName : `"$fkCols`""
    }
    
    return $mmd -join "`n"
}

function New-SqlTableHtmlSections {
    <#
    .SYNOPSIS
        Generates HTML sections for indexes, constraints, triggers, and FKs.
        Returns a hashtable with individual sections for tabbed layout.
    #>
    param (
        [array]$Indexes,
        [array]$Constraints,
        [array]$KeyColumns,
        [hashtable]$ForeignKeys,
        [array]$Triggers,
        [array]$CheckConstraints
    )
    
    $sections = @{
        IndexInfo = ""
        PkInfo = ""
        UkInfo = ""
        FkOutgoing = ""
        FkIncoming = ""
        TriggerInfo = ""
        IndexCount = $Indexes.Count
        UkCount = 0
        FkCount = 0
        TriggerCount = $Triggers.Count
    }
    
    # ===== INDEXES SECTION =====
    if ($Indexes.Count -gt 0) {
        $sections.IndexInfo = "<table><tr><th>Index Name</th><th>Type</th><th>Unique</th><th>Columns</th><th>Levels</th></tr>"
        foreach ($idx in $Indexes) {
            $uniqueType = switch ($idx.uniquerule.Trim()) {
                "P" { "Primary Key" }
                "U" { "Unique" }
                "D" { "Non-Unique" }
                default { $idx.uniquerule }
            }
            $idxType = switch ($idx.indextype.Trim()) {
                "REG" { "Regular" }
                "CLUS" { "Clustering" }
                default { $idx.indextype }
            }
            # Parse column names with ASC/DESC indicators
            # DB2 format: +COL1+COL2-COL3 means COL1 ASC, COL2 ASC, COL3 DESC
            # + = ASC, - = DESC, columns separated by these characters
            $rawColnames = $idx.colnames.Trim()
            $formattedCols = @()
            
            # Split by + or - but keep the delimiter to know ASC/DESC
            # Use regex to split while keeping delimiters
            # Pattern explanation: (?=[+-]) = lookahead for + or -, splits before the character
            $colParts = $rawColnames -split '(?=[+-])' | Where-Object { $_ -ne '' }
            
            foreach ($colPart in $colParts) {
                $colPart = $colPart.Trim()
                if ($colPart.StartsWith('+')) {
                    $colName = $colPart.Substring(1).Trim()
                    if ($colName) { $formattedCols += "$colName ASC" }
                }
                elseif ($colPart.StartsWith('-')) {
                    $colName = $colPart.Substring(1).Trim()
                    if ($colName) { $formattedCols += "$colName DESC" }
                }
                elseif ($colPart) {
                    # No prefix means ASC by default
                    $formattedCols += "$colPart ASC"
                }
            }
            $colnames = $formattedCols -join ", "
            $sections.IndexInfo += "<tr><td>$($idx.indname.Trim())</td><td>$idxType</td><td>$uniqueType</td><td><code>$colnames</code></td><td>$($idx.nlevels)</td></tr>"
        }
        $sections.IndexInfo += "</table>"
    }
    else {
        $sections.IndexInfo = "<div class='empty-state'><i class='bi bi-list-ol'></i><p>No indexes defined</p></div>"
    }
    
    # ===== PRIMARY KEY SECTION =====
    $pkConstraints = @($Constraints | Where-Object { $_.type -and $_.type.Trim() -eq "P" })
    if ($pkConstraints.Count -gt 0) {
        $sections.PkInfo = "<table><tr><th>Constraint Name</th><th>Columns</th></tr>"
        foreach ($pk in $pkConstraints) {
            $pkCols = @($KeyColumns | Where-Object { $_.constname -and $_.constname.Trim() -eq $pk.constname.Trim() } | Sort-Object { [int]$_.colseq } | ForEach-Object { $_.colname.Trim() })
            $sections.PkInfo += "<tr><td>$($pk.constname.Trim())</td><td><code>$($pkCols -join ', ')</code></td></tr>"
        }
        $sections.PkInfo += "</table>"
    }
    else {
        $sections.PkInfo = "<div class='empty-state'><i class='bi bi-key'></i><p>No primary key defined</p></div>"
    }
    
    # ===== UNIQUE CONSTRAINTS SECTION =====
    $ukConstraints = @($Constraints | Where-Object { $_.type -and $_.type.Trim() -eq "U" })
    $sections.UkCount = $ukConstraints.Count
    if ($ukConstraints.Count -gt 0) {
        $sections.UkInfo = "<table><tr><th>Constraint Name</th><th>Columns</th></tr>"
        foreach ($uk in $ukConstraints) {
            $ukCols = @($KeyColumns | Where-Object { $_.constname -and $_.constname.Trim() -eq $uk.constname.Trim() } | Sort-Object { [int]$_.colseq } | ForEach-Object { $_.colname.Trim() })
            $sections.UkInfo += "<tr><td>$($uk.constname.Trim())</td><td><code>$($ukCols -join ', ')</code></td></tr>"
        }
        $sections.UkInfo += "</table>"
    }
    else {
        $sections.UkInfo = "<div class='empty-state'><i class='bi bi-asterisk'></i><p>No unique constraints defined</p></div>"
    }
    
    # Calculate FK count
    $sections.FkCount = $ForeignKeys.Outgoing.Count + $ForeignKeys.Incoming.Count
    
    # ===== FOREIGN KEYS (OUTGOING) SECTION =====
    if ($ForeignKeys.Outgoing.Count -gt 0) {
        $sections.FkOutgoing = "<div class='data-section'><h5><i class='bi bi-arrow-right-circle'></i> References ($($ForeignKeys.Outgoing.Count) parent tables)</h5>"
        $sections.FkOutgoing += "<table><tr><th>FK Name</th><th>FK Columns</th><th>References Table</th><th>PK Columns</th><th>On Delete</th></tr>"
        foreach ($fk in $ForeignKeys.Outgoing) {
            $refTable = "$($fk.reftabschema.Trim()).$($fk.reftabname.Trim())"
            $refFileName = $refTable.Replace(".", "_").ToLower() + ".sql.html"
            $fkCols = $fk.fk_colnames.Trim() -replace '\+', '' -replace '-', ''
            $pkCols = $fk.pk_colnames.Trim() -replace '\+', '' -replace '-', ''
            $deleteRule = switch ($fk.deleterule.Trim()) {
                "A" { "No Action" }
                "C" { "Cascade" }
                "N" { "Set Null" }
                "R" { "Restrict" }
                default { $fk.deleterule }
            }
            $sections.FkOutgoing += "<tr><td>$($fk.constname.Trim())</td><td><code>$fkCols</code></td><td><a href='$refFileName'><strong>$refTable</strong></a></td><td><code>$pkCols</code></td><td>$deleteRule</td></tr>"
        }
        $sections.FkOutgoing += "</table></div>"
    }
    
    # ===== FOREIGN KEYS (INCOMING) SECTION =====
    if ($ForeignKeys.Incoming.Count -gt 0) {
        $sections.FkIncoming = "<div class='data-section'><h5><i class='bi bi-arrow-left-circle'></i> Referenced By ($($ForeignKeys.Incoming.Count) child tables)</h5>"
        $sections.FkIncoming += "<table><tr><th>Child Table</th><th>FK Name</th><th>FK Columns</th><th>On Delete</th></tr>"
        foreach ($fk in $ForeignKeys.Incoming) {
            $childTable = "$($fk.tabschema.Trim()).$($fk.tabname.Trim())"
            $childFileName = $childTable.Replace(".", "_").ToLower() + ".sql.html"
            $fkCols = $fk.fk_colnames.Trim() -replace '\+', '' -replace '-', ''
            $deleteRule = switch ($fk.deleterule.Trim()) {
                "A" { "No Action" }
                "C" { "Cascade" }
                "N" { "Set Null" }
                "R" { "Restrict" }
                default { $fk.deleterule }
            }
            $sections.FkIncoming += "<tr><td><a href='$childFileName'><strong>$childTable</strong></a></td><td>$($fk.constname.Trim())</td><td><code>$fkCols</code></td><td>$deleteRule</td></tr>"
        }
        $sections.FkIncoming += "</table></div>"
    }
    
    # If no FKs at all, show empty state
    if ($ForeignKeys.Outgoing.Count -eq 0 -and $ForeignKeys.Incoming.Count -eq 0) {
        $sections.FkOutgoing = "<div class='data-section'><div class='empty-state'><i class='bi bi-link-45deg'></i><p>No foreign key relationships</p></div></div>"
    }
    
    # ===== TRIGGERS SECTION =====
    if ($Triggers.Count -gt 0) {
        $sections.TriggerInfo = "<table><tr><th>Trigger Name</th><th>Timing</th><th>Event</th><th>Granularity</th><th>Valid</th></tr>"
        foreach ($trig in $Triggers) {
            $timing = switch ($trig.trigtime.Trim()) {
                "A" { "AFTER" }
                "B" { "BEFORE" }
                "I" { "INSTEAD OF" }
                default { $trig.trigtime }
            }
            $trigEvent = switch ($trig.trigevent.Trim()) {
                "I" { "INSERT" }
                "D" { "DELETE" }
                "U" { "UPDATE" }
                default { $trig.trigevent }
            }
            $granularity = if ($trig.granularity.Trim() -eq "R") { "Row" } else { "Statement" }
            $valid = if ($trig.valid.Trim() -eq "Y") { "Yes" } else { "No" }
            $sections.TriggerInfo += "<tr><td>$($trig.trigname.Trim())</td><td>$timing</td><td>$trigEvent</td><td>$granularity</td><td>$valid</td></tr>"
        }
        $sections.TriggerInfo += "</table>"
    }
    else {
        $sections.TriggerInfo = "<div class='empty-state'><i class='bi bi-lightning'></i><p>No triggers defined</p></div>"
    }
    
    return $sections
}

#endregion

function Get-SqlTableMetaData {
    <#
    .SYNOPSIS
        Retrieves and formats comprehensive SQL table metadata for HTML output.
    
    .DESCRIPTION
        Reads table and column information from CSV exports and generates
        the HTML page for the SQL table documentation. Enhanced to include
        indexes, constraints, foreign keys, triggers, and ER diagrams.
    
    .PARAMETER TmpRootFolder
        Root folder for temporary files (cobdok CSV files).
    
    .PARAMETER OutputFolder
        Output folder for generated HTML files.
    
    .PARAMETER InputDbFileFolder
        Folder containing the database export CSV files.
    
    .PARAMETER SqlTable
        The SQL table name (schema.tablename).
    
    .PARAMETER TableInfo
        Table metadata from tables.csv.
    
    .PARAMETER ColumnsArray
        Column metadata from columns.csv.
    
    .OUTPUTS
        Path to the generated HTML file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TmpRootFolder,
        [Parameter(Mandatory = $true)]
        [string]$OutputFolder,
        [Parameter(Mandatory = $true)]
        [string]$InputDbFileFolder,
        [Parameter(Mandatory = $true)]
        [string]$SqlTable,
        [Parameter(Mandatory = $true)]
        $TableInfo,
        [Parameter(Mandatory = $true)]
        $ColumnsArray
    )
    
    $schemaName = $TableInfo.schemaName.Trim().ToUpper()
    $tableName = $TableInfo.tableName.Trim().ToUpper()
    
    try {
        $title = "AutoDoc Info - " + $TableInfo.comment

        # ===== Load enhanced metadata =====
        $indexes = Get-SqlIndexMetadata -InputDbFileFolder $InputDbFileFolder -SchemaName $schemaName -TableName $tableName
        $constraints = Get-SqlConstraintMetadata -InputDbFileFolder $InputDbFileFolder -SchemaName $schemaName -TableName $tableName
        $keyColumns = Get-SqlKeyColumnMetadata -InputDbFileFolder $InputDbFileFolder -SchemaName $schemaName -TableName $tableName
        $foreignKeys = Get-SqlForeignKeyMetadata -InputDbFileFolder $InputDbFileFolder -SchemaName $schemaName -TableName $tableName
        $triggers = Get-SqlTriggerMetadata -InputDbFileFolder $InputDbFileFolder -SchemaName $schemaName -TableName $tableName
        $checkConstraints = Get-SqlCheckConstraintMetadata -InputDbFileFolder $InputDbFileFolder -SchemaName $schemaName -TableName $tableName

        # Get primary key columns for marking in column table
        $pkConstraint = $constraints | Where-Object { $_.type -and $_.type.Trim() -eq "P" } | Select-Object -First 1
        $pkColumnNames = @()
        if ($pkConstraint) {
            $pkColumnNames = @($keyColumns | Where-Object { $_.constname -and $_.constname.Trim() -eq $pkConstraint.constname.Trim() } | ForEach-Object { $_.colname.Trim() })
        }

        # Create enhanced HTML table with PK/FK indicators and nullable info
        $htmlTable = "<table><tr><th>Column</th><th>#</th><th>Data Type</th><th>Length</th><th>Scale</th><th>Null</th><th>Key</th><th>Remarks</th></tr>"
        foreach ($item in $ColumnsArray) {
            $colName = $item.colname.Trim()
            $nullable = if ($item.nulls -and $item.nulls.Trim() -eq "Y") { "Yes" } else { "No" }
            
            # Determine key type
            $keyType = ""
            if ($pkColumnNames -contains $colName) {
                $keyType = "<span class='badge bg-primary'>PK</span>"
            }
            foreach ($fk in $foreignKeys.Outgoing) {
                if ($fk.fk_colnames.Trim() -match "\b$colName\b") {
                    $keyType += " <span class='badge bg-warning text-dark'>FK</span>"
                    break
                }
            }
            
            $htmlTable += "<tr><td class='column-name'>$colName</td><td>$($item.colno)</td><td class='column-type'>$($item.typename.Trim())</td><td>$($item.length)</td><td>$($item.scale)</td><td>$nullable</td><td>$keyType</td><td>$($item.remarks)</td></tr>"
        }
        $htmlTable += "</table>"

        # Generate additional HTML sections (returns hashtable with individual sections)
        $sections = New-SqlTableHtmlSections -Indexes $indexes -Constraints $constraints -KeyColumns $keyColumns -ForeignKeys $foreignKeys -Triggers $triggers -CheckConstraints $checkConstraints

        # Generate ER diagram if there are relationships
        $erDiagram = ""
        if ($foreignKeys.Outgoing.Count -gt 0 -or $foreignKeys.Incoming.Count -gt 0) {
            $erDiagram = New-SqlErDiagram -SchemaName $schemaName -TableName $tableName -Columns $ColumnsArray -PkColumns $pkColumnNames -ForeignKeys $foreignKeys
        }
        
        # Get counts for tab badges
        $columnCount = $ColumnsArray.Count
        $indexCount = $sections.IndexCount
        $ukCount = $sections.UkCount
        $fkCount = $sections.FkCount
        $triggerCount = $sections.TriggerCount

        # Determine table type
        if ($TableInfo.type -eq "T") {
            $htmlType = "Sql Table"
        }
        elseif ($TableInfo.type -eq "V") {
            $htmlType = "Sql View"
        }
        else {
            $htmlType = "Sql Unknown"
        }

        # Build statistics info
        $statsHtml = ""
        if ($TableInfo.card -and [int]$TableInfo.card -ge 0) {
            $rowCount = [int]$TableInfo.card
            $pageCount = if ($TableInfo.npages) { [int]$TableInfo.npages } else { 0 }
            $colCount = if ($TableInfo.colcount) { [int]$TableInfo.colcount } else { $ColumnsArray.Count }
            $statsHtml = "<div class='info-card stats-card'><table class='info-table'>"
            $statsHtml += "<tr><td><i class='bi bi-bar-chart'></i> Statistics</td><td></td></tr>"
            $statsHtml += "<tr><td>Row Count</td><td><strong>$($rowCount.ToString('N0'))</strong></td></tr>"
            $statsHtml += "<tr><td>Data Pages</td><td>$($pageCount.ToString('N0'))</td></tr>"
            $statsHtml += "<tr><td>Column Count</td><td>$colCount</td></tr>"
            $statsHtml += "<tr><td>Indexes</td><td>$($indexes.Count)</td></tr>"
            $statsHtml += "<tr><td>Triggers</td><td>$($triggers.Count)</td></tr>"
            $statsHtml += "<tr><td>Parent Tables</td><td>$($foreignKeys.Outgoing.Count)</td></tr>"
            $statsHtml += "<tr><td>Child Tables</td><td>$($foreignKeys.Incoming.Count)</td></tr>"
            $statsHtml += "</table></div>"
        }
    }
    catch {
        $errorMessage = $_.Exception
        Write-Host "En feil oppstod: $errorMessage"
        Write-LogMessage ("Error in line " + $_.InvocationInfo.ScriptLineNumber.ToString() + "/offset " + $_.InvocationInfo.OffsetInLine.ToString()) -Level ERROR -Exception $_
        Write-LogMessage $errorMessage -Level ERROR
        $script:errorOccurred = $true
    }
    finally {
        $htmlFilename = $OutputFolder + "\" + $SqlTable.Replace(".", "_") + ".sql.html"
        $htmlFilename = $htmlFilename.Trim().ToUpper().Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower()
        
        # Use template from OutputFolder\_templates (copied at startup by AutoDocBatchRunner)
        $templatePath = Join-Path $OutputFolder "_templates"
        $mmdTemplateFilename = Join-Path $templatePath "sqlmmdtemplate.html"
        
        $tableFullName = $TableInfo.schemaName.Trim().ToUpper() + "." + $TableInfo.tableName.Trim().ToUpper()
        $myDescription = "AutoDoc Sql Info - " + $SqlTable.ToLower()
        $templateContent = Get-Content -Path $mmdTemplateFilename -Raw
        
        # Apply shared CSS and common URL replacements
        $doc = Set-AutodocTemplate -Template $templateContent -OutputFolder $OutputFolder
        
        # Page-specific replacements
        $doc = $doc.Replace("[title]", $myDescription)
        $doc = $doc.Replace("[tablename]", $tableFullName.ToUpper())
        $doc = $doc.Replace("[comment]", $TableInfo.comment.ToUpper())
        $doc = $doc.Replace("[type]", $htmlType)
        $doc = $doc.Replace("[ddltime]", $TableInfo.alter_time)
        $doc = $doc.Replace("[generated]", (Get-Date).ToString())
        
        # Column and section content
        $doc = $doc.Replace("[columninfo]", $htmlTable)
        $doc = $doc.Replace("[statsinfo]", $statsHtml)
        $doc = $doc.Replace("[erdiagram]", $erDiagram)
        $doc = $doc.Replace("[haserdiagram]", $(if ($erDiagram) { "true" } else { "false" }))
        
        # Individual sections for tabbed layout
        $doc = $doc.Replace("[indexinfo]", $sections.IndexInfo)
        $doc = $doc.Replace("[pkinfo]", $sections.PkInfo)
        $doc = $doc.Replace("[ukinfo]", $sections.UkInfo)
        $doc = $doc.Replace("[fkoutgoing]", $sections.FkOutgoing)
        $doc = $doc.Replace("[fkincoming]", $sections.FkIncoming)
        $doc = $doc.Replace("[triggerinfo]", $sections.TriggerInfo)
        
        # Get SQL table interactions
        $interactionDiagram = ""
        $interactionCount = 0
        $hasInteractionDiagram = "false"
        $interactionTabStyle = "display: none;"
        
        try {
            $tableNameLower = $SqlTable.ToLower()
            $jsonCachePath = Join-Path $OutputFolder "_sql_interactions.json"
            
            # Try to load interactions from JSON cache
            $interactions = Get-SqlTableInteractions -TableName $tableNameLower -OutputFolder $OutputFolder -JsonCachePath $jsonCachePath
            
            if ($interactions -and $interactions.Count -gt 0) {
                # Count total interactions
                foreach ($operation in $interactions.Keys) {
                    if ($interactions[$operation] -is [System.Array]) {
                        $interactionCount += $interactions[$operation].Count
                    }
                }
                
                if ($interactionCount -gt 0) {
                    # Generate interaction diagram
                    $interactionDiagram = New-SqlInteractionDiagram -TableName $tableNameLower -Interactions $interactions
                    $hasInteractionDiagram = "true"
                    $interactionTabStyle = ""
                }
            }
        }
        catch {
            Write-LogMessage "Error generating interaction diagram: $($_.Exception.Message)" -Level WARN
        }
        
        # Counts for tab badges
        $doc = $doc.Replace("[columncount]", $columnCount.ToString())
        $doc = $doc.Replace("[indexcount]", $indexCount.ToString())
        $doc = $doc.Replace("[ukcount]", $ukCount.ToString())
        $doc = $doc.Replace("[fkcount]", $fkCount.ToString())
        $doc = $doc.Replace("[triggercount]", $triggerCount.ToString())
        $doc = $doc.Replace("[interactioncount]", $interactionCount.ToString())
        
        # Interaction diagram placeholders
        $doc = $doc.Replace("[interactiondiagram]", $interactionDiagram)
        $doc = $doc.Replace("[hasinteractiondiagram]", $hasInteractionDiagram)
        $doc = $doc.Replace("[interactionstabstyle]", $interactionTabStyle)
        
        # Legacy placeholder (keep for compatibility)
        $doc = $doc.Replace("[additionalsections]", "")
        $doc = $doc.Replace("[usedbylist]", $cblArray)
        Set-Content -Path $htmlFilename -Value $doc
    }
    return $htmlFilename
}

function Search-HtmlFilesForSqlInteractions {
    <#
    .SYNOPSIS
        Scans all generated HTML files to extract SQL table interactions.
    .DESCRIPTION
        After all other file types (PS1, CBL, BAT, REXX, C#) are generated,
        this function scans the webs output folder to find all SQL table interactions.
        Groups interactions by table, operation, and program/module.
        Stores results in JSON for reuse.
    .PARAMETER OutputFolder
        The webs output folder containing generated HTML files.
    .PARAMETER JsonOutputPath
        Path to save the interaction JSON file.
    .OUTPUTS
        Hashtable with table interactions grouped by table, operation, and program.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputFolder,
        [Parameter(Mandatory = $false)]
        [string]$JsonOutputPath = ""
    )
    
    Write-LogMessage "Scanning HTML files for SQL table interactions..." -Level INFO
    
    if (-not (Test-Path $OutputFolder)) {
        Write-LogMessage "Output folder not found: $OutputFolder" -Level ERROR
        return @{}
    }
    
    # Initialize interaction dictionary: Table -> Operation -> Programs[]
    $interactions = @{}
    
    # File type patterns to scan (exclude SQL files themselves)
    $filePatterns = @("*.ps1.html", "*.cbl.html", "*.bat.html", "*.rex.html", "*.csharp.html")
    
    foreach ($pattern in $filePatterns) {
        $htmlFiles = Get-ChildItem -Path $OutputFolder -Filter $pattern -File -ErrorAction SilentlyContinue
        
        foreach ($htmlFile in $htmlFiles) {
            try {
                $content = Get-Content $htmlFile.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if (-not $content) { continue }
                
                # Extract program/module name from filename
                $programName = [System.IO.Path]::GetFileNameWithoutExtension($htmlFile.Name)
                $programName = [System.IO.Path]::GetFileNameWithoutExtension($programName)  # Remove .ps1, .cbl, etc.
                
                # Extract file type
                $fileType = ""
                if ($htmlFile.Name -match '\.ps1\.html$') { $fileType = "PowerShell" }
                elseif ($htmlFile.Name -match '\.cbl\.html$') { $fileType = "COBOL" }
                elseif ($htmlFile.Name -match '\.bat\.html$') { $fileType = "Batch" }
                elseif ($htmlFile.Name -match '\.rex\.html$') { $fileType = "REXX" }
                elseif ($htmlFile.Name -match '\.csharp\.html$') { $fileType = "CSharp" }
                
                # Find MMD content in HTML
                # Pattern: <pre class="mermaid">...</pre> or <div class="mermaid">...</div>
                $mmdPattern = '(?:<pre[^>]*class=["'']mermaid["'']|<div[^>]*class=["'']mermaid["''])[^>]*>([\s\S]*?)(?:</pre>|</div>)'
                $mmdMatches = [regex]::Matches($content, $mmdPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                
                foreach ($mmdMatch in $mmdMatches) {
                    $mmdContent = $mmdMatch.Groups[1].Value
                    
                    # Parse MMD content for SQL table interactions
                    # Pattern: programNode--"operation"-->sql_schema_table[(tableName)]
                    # Or: programNode--"operation"-->sql_dbm_table[(dbm.table)]
                    $sqlNodePattern = '(\w+)\s*--["'']([^"'']+)["'']-->\s*sql_([\w_]+)\[\(([^)]+)\)\]'
                    $sqlMatches = [regex]::Matches($mmdContent, $sqlNodePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                    
                    foreach ($sqlMatch in $sqlMatches) {
                        $programNode = $sqlMatch.Groups[1].Value
                        $operation = $sqlMatch.Groups[2].Value.Trim()
                        $sqlNodeId = $sqlMatch.Groups[3].Value
                        $tableName = $sqlMatch.Groups[4].Value.Trim()
                        
                        # Normalize table name (handle case variations)
                        $tableName = $tableName.ToLower()
                        
                        # Normalize operation (extract SQL operation from edge label)
                        $sqlOperation = "SELECT"  # Default
                        if ($operation -match '\b(select|insert|update|delete|fetch|call)\b') {
                            $sqlOperation = $Matches[1].ToUpper()
                        }
                        elseif ($operation -match 'update\s*\[([^\]]+)\]') {
                            $sqlOperation = "UPDATE"
                        }
                        
                        # Initialize table entry if not exists
                        if (-not $interactions.ContainsKey($tableName)) {
                            $interactions[$tableName] = @{}
                        }
                        
                        # Initialize operation entry if not exists
                        if (-not $interactions[$tableName].ContainsKey($sqlOperation)) {
                            $interactions[$tableName][$sqlOperation] = @()
                        }
                        
                        # Add program if not already present
                        $programInfo = @{
                            Name     = $programName
                            Node     = $programNode
                            FileType = $fileType
                            FilePath = $htmlFile.Name
                        }
                        
                        $exists = $false
                        foreach ($existing in $interactions[$tableName][$sqlOperation]) {
                            if ($existing.Name -eq $programName -and $existing.FileType -eq $fileType) {
                                $exists = $true
                                break
                            }
                        }
                        
                        if (-not $exists) {
                            $interactions[$tableName][$sqlOperation] += $programInfo
                        }
                    }
                }
            }
            catch {
                Write-LogMessage "Error scanning file $($htmlFile.Name): $($_.Exception.Message)" -Level WARN
            }
        }
    }
    
    Write-LogMessage "Found interactions for $($interactions.Keys.Count) tables" -Level INFO
    
    # Save to JSON if path provided
    if ($JsonOutputPath) {
        try {
            $jsonContent = $interactions | ConvertTo-Json -Depth 10
            Set-Content -Path $JsonOutputPath -Value $jsonContent -Encoding UTF8 -Force
            Write-LogMessage "Saved interactions to JSON: $JsonOutputPath" -Level INFO
        }
        catch {
            Write-LogMessage "Error saving JSON: $($_.Exception.Message)" -Level WARN
        }
    }
    
    return $interactions
}

function Get-SqlTableInteractions {
    <#
    .SYNOPSIS
        Gets SQL table interactions from JSON cache or scans HTML files.
    .DESCRIPTION
        Loads interactions from JSON file if it exists and is recent,
        otherwise scans HTML files and updates the JSON cache.
    .PARAMETER TableName
        The SQL table name (schema.tablename format).
    .PARAMETER OutputFolder
        The webs output folder.
    .PARAMETER JsonCachePath
        Path to the JSON cache file.
    .OUTPUTS
        Hashtable with interactions for the specified table.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $true)]
        [string]$OutputFolder,
        [Parameter(Mandatory = $false)]
        [string]$JsonCachePath = ""
    )
    
    if (-not $JsonCachePath) {
        $JsonCachePath = Join-Path $OutputFolder "_sql_interactions.json"
    }
    
    $tableNameLower = $TableName.ToLower()
    $interactions = @{}
    
    # Try to load from JSON cache
    if (Test-Path $JsonCachePath) {
        try {
            $jsonContent = Get-Content $JsonCachePath -Raw -Encoding UTF8
            $allInteractions = $jsonContent | ConvertFrom-Json -AsHashtable
            
            if ($allInteractions.ContainsKey($tableNameLower)) {
                $interactions = $allInteractions[$tableNameLower]
            }
        }
        catch {
            Write-LogMessage "Error loading JSON cache: $($_.Exception.Message)" -Level WARN
        }
    }
    
    return $interactions
}

function New-SqlInteractionDiagram {
    <#
    .SYNOPSIS
        Generates Mermaid diagram showing all modules that interact with a SQL table.
    .DESCRIPTION
        Creates a flowchart diagram showing programs/modules grouped by operation type
        (SELECT, INSERT, UPDATE, DELETE) that interact with a given SQL table.
    .PARAMETER TableName
        The SQL table name (schema.tablename format).
    .PARAMETER Interactions
        Hashtable with interactions grouped by operation.
    .OUTPUTS
        Mermaid diagram code as string.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        [Parameter(Mandatory = $true)]
        [hashtable]$Interactions
    )
    
    if ($Interactions.Count -eq 0) {
        return ""
    }
    
    $diagram = @()
    $diagram += "flowchart TD"
    
    # Create table node (center)
    $safeTableName = $TableName.Replace(".", "_").ToLower()
    $tableNodeId = "sql_$safeTableName"
    $tableDisplayName = $TableName.ToUpper()
    $diagram += "    $tableNodeId[($tableDisplayName)]"
    
    # Group by operation type
    $operations = @("SELECT", "INSERT", "UPDATE", "DELETE", "FETCH", "CALL")
    
    foreach ($operation in $operations) {
        if (-not $Interactions.ContainsKey($operation)) { continue }
        
        $programs = $Interactions[$operation]
        if ($programs.Count -eq 0) { continue }
        
        # Create subgraph for operation
        $safeOpName = $operation.ToLower()
        $diagram += "    subgraph $safeOpName[`"📊 $operation`"]"
        
        # Add program nodes
        foreach ($program in $programs) {
            $safeProgramName = $program.Name -replace '[^a-zA-Z0-9]', '_'
            $programNodeId = "${safeOpName}_${safeProgramName}"
            
            # Determine node shape based on file type
            $nodeShape = "[`"$($program.Name)`"]"
            if ($program.FileType -eq "COBOL") {
                $nodeShape = "([`"$($program.Name)`"])"
            }
            elseif ($program.FileType -eq "CSharp") {
                $nodeShape = "([`"⚡ $($program.Name)`"])"
            }
            
            $diagram += "        $programNodeId$nodeShape"
            
            # Create link from program to table with click event to open program file
            $programLink = "./$($program.FilePath)"
            $diagram += "        $programNodeId -->|`"$operation`"| $tableNodeId"
            $diagram += "        click $programNodeId `"$programLink`""
        }
        
        $diagram += "    end"
    }
    
    return $diagram -join "`n"
}

function Start-SqlParse {
    <#
    .SYNOPSIS
        Main entry point for SQL table parsing.
    
    .DESCRIPTION
        Parses SQL table metadata and generates AutoDoc HTML documentation.
        This is the entry point function that orchestrates the SQL parsing process.
    
    .PARAMETER SqlTable
        The SQL table name (schema.tablename format, e.g., "DBM.KUNDE").
    
    .PARAMETER Show
        If true, opens the generated HTML file after creation.
    
    .PARAMETER OutputFolder
        Output folder for generated files.
    
    .PARAMETER CleanUp
        If true, cleans up temporary files after processing.
    
    .PARAMETER TmpRootFolder
        Root folder for temporary files.
    
    .PARAMETER SrcRootFolder
        Root folder for source files.
    
    .OUTPUTS
        Path to the generated HTML file, or $null on error.
    
    .EXAMPLE
        Start-SqlParse -SqlTable "DBM.KUNDE" -OutputFolder "C:\output"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SqlTable,
        [bool]$Show = $false,
        [string]$OutputFolder = "$env:OptPath\Webs\AutoDoc",
        [bool]$CleanUp = $true,
        [string]$TmpRootFolder = "$env:OptPath\data\AutoDoc\tmp",
        [string]$SrcRootFolder = "$env:OptPath\data\AutoDoc\src"
    )
    
    $script:errorOccurred = $false
    
    Write-LogMessage ("Starting parsing of table:" + $SqlTable) -Level INFO
    
    # Validate table name
    if (-not $SqlTable.Contains(".")) {
        Write-LogMessage ("Filename is not valid. Do not contain period in tablename:" + $SqlTable) -Level ERROR
        return $null
    }
    
    $startTime = Get-Date
    $htmlFilename = $OutputFolder + "\" + $SqlTable + ".sql.html"
    
    $inputDbFileFolder = $TmpRootFolder + "\cobdok"
    
    Write-LogMessage ("Started for :" + $SqlTable) -Level INFO
    
    # Parse table name
    $temp1 = $SqlTable.ToUpper().Split(".")
    $schemaName = $temp1[0]
    $tableName = $temp1[1]
    
    # Load table metadata from CSV
    $csvTableArray = Import-Csv ($inputDbFileFolder + "\tables.csv") -Header schemaName, tableName, comment, type, alter_time -Delimiter ';' -ErrorAction SilentlyContinue
    if ($null -eq $csvTableArray) {
        $csvTableArray = @()
    }
    $tableArray = $csvTableArray | Where-Object { $_.schemaName.Trim() -eq $schemaName -and $_.tableName.Trim() -eq $tableName }
    
    # Load column metadata from CSV
    $columnsArray = @()  # Initialize as empty array
    $columnsCsvPath = Join-Path $inputDbFileFolder "columns.csv"
    if (Test-Path $columnsCsvPath) {
        try {
            $csvTableArray1 = Import-Csv $columnsCsvPath -Header tabschema, tabname, colname, colno, typeschema, typename, length, scale, remarks -Delimiter ';' -ErrorAction Stop
            if ($null -ne $csvTableArray1) {
                $columnsArray = $csvTableArray1 | Where-Object { $_.tabschema.Trim().Contains($schemaName) -and $_.tabname.Trim() -eq $tableName }
            }
        }
        catch {
            Write-LogMessage "Failed to load columns.csv: $($_.Exception.Message)" -Level WARN
            $columnsArray = @()  # Ensure it's an array, not null
        }
    }
    else {
        Write-LogMessage "Columns CSV file not found: $columnsCsvPath" -Level WARN
    }
    
    # Generate HTML
    if (-not $script:errorOccurred -and $tableArray.Count -gt 0) {
        # Ensure columnsArray is not null before passing to function
        if ($null -eq $columnsArray) {
            $columnsArray = @()
        }
        $htmlFilename = Get-SqlTableMetaData -TmpRootFolder $TmpRootFolder -OutputFolder $OutputFolder -InputDbFileFolder $inputDbFileFolder -SqlTable $SqlTable -TableInfo $tableArray[0] -ColumnsArray $columnsArray
        
        if ($Show) {
            & $htmlFilename
        }
    }
    
    $endTime = Get-Date
    $timeDiff = $endTime - $startTime
    
    # Log result
    # Only create error file if HTML was NOT generated (fatal error)
    # Non-fatal errors during parsing should not prevent successful completion if HTML was created
    $dummyFile = $htmlFilename.Replace(".html", ".err")
    $htmlWasGenerated = Test-Path -Path $htmlFilename -PathType Leaf
    
    if ($htmlWasGenerated) {
        # HTML was generated - remove any error file and mark as success
        if (Test-Path -Path $dummyFile -PathType Leaf) {
            Remove-Item -Path $dummyFile -Force -ErrorAction SilentlyContinue
        }
        if ($script:errorOccurred) {
            Write-LogMessage ("Time elapsed: " + $timeDiff.Seconds.ToString()) -Level INFO
            Write-LogMessage ("Completed with warnings:" + $SqlTable) -Level WARN
        }
        else {
            Write-LogMessage ("Time elapsed: " + $timeDiff.Seconds.ToString()) -Level INFO
            Write-LogMessage ("Completed successfully:" + $SqlTable) -Level INFO
        }
        return $htmlFilename
    }
    else {
        # HTML was NOT generated - this is a true failure
        Write-LogMessage ("*******************************************************************************") -Level ERROR
        Write-LogMessage ("Failed - HTML not generated:" + $SqlTable) -Level ERROR
        Write-LogMessage ("*******************************************************************************") -Level ERROR
        "Error: HTML file was not generated for $SqlTable" | Set-Content -Path $dummyFile -Force
        return $null
    }
}
#endregion

#region CSharp Parse Functions
# Author: Geir Helge Starholm, www.dEdge.no
# Title: C# Parser Functions Module for AutoDoc
# Description: Contains the main Start-CSharpParse function and supporting functions
#              for parsing C# solutions and projects.

#region Required Modules

# Note: GlobalFunctions and AutodocFunctions are loaded by the parent module
# Only import GlobalFunctions if not already loaded (avoid module nesting issues)
if (-not (Get-Module -Name GlobalFunctions)) {
    Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
}

#endregion

#region Script-Level Variables

$script:sequenceNumber = 0
$script:mmdClassContent = $null
$script:mmdFlowContent = $null
$script:mmdInteractionContent = $null
$script:mmdExecutionFlowContent = $null
$script:mmdEcosystemContent = $null
$script:duplicateLineCheck = $null

#endregion

#region Helper Functions

function Initialize-CSharpParseVariables {
    <#
    .SYNOPSIS
        Initializes thread-safe variables for C# parsing.
    #>
    $script:sequenceNumber = 0
    $script:mmdClassContent = [System.Collections.ArrayList]::new()
    $script:mmdFlowContent = [System.Collections.ArrayList]::new()
    $script:mmdInteractionContent = [System.Collections.ArrayList]::new()
    $script:mmdExecutionFlowContent = [System.Collections.ArrayList]::new()
    $script:mmdEcosystemContent = ""
    $script:duplicateLineCheck = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $script:sqlTableArray = @()  # Track SQL tables for "Uses SQL" checkbox
}

function Get-CSharpFiles {
    <#
    .SYNOPSIS
        Gets all C# files in a folder, excluding common non-source folders.
    #>
    param([string]$FolderPath)
    
    $excludeFolders = @('bin', 'obj', 'node_modules', '.git', '.vs', 'packages', 'TestResults')
    
    $csFiles = Get-ChildItem -Path $FolderPath -Filter "*.cs" -Recurse -File | Where-Object {
        $path = $_.DirectoryName.ToLower()
        $exclude = $false
        foreach ($folder in $excludeFolders) {
            if ($path -match "\\$folder(\\|$)") {
                $exclude = $true
                break
            }
        }
        -not $exclude
    }
    
    return $csFiles
}

function Get-SolutionProjects {
    <#
    .SYNOPSIS
        Parses a .sln file to extract project information.
    #>
    param([string]$SolutionPath)
    
    $projects = @()
    
    if (-not (Test-Path $SolutionPath)) {
        Write-LogMessage "Solution file not found: $SolutionPath" -Level WARN
        return $projects
    }
    
    $content = Get-Content $SolutionPath -Raw
    
    # Regex pattern to match Project lines in .sln file
    # Pattern: Project("{GUID}") = "ProjectName", "RelativePath\Project.csproj", "{ProjectGUID}"
    $projectPattern = 'Project\("\{[A-F0-9-]+\}"\)\s*=\s*"([^"]+)",\s*"([^"]+)",\s*"\{([A-F0-9-]+)\}"'
    
    $matches = [regex]::Matches($content, $projectPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    
    foreach ($match in $matches) {
        $projectName = $match.Groups[1].Value
        $relativePath = $match.Groups[2].Value
        $projectGuid = $match.Groups[3].Value
        
        # Skip solution folders
        if ($relativePath -notmatch '\.csproj$') { continue }
        
        $solutionDir = Split-Path $SolutionPath -Parent
        $projectPath = Join-Path $solutionDir $relativePath
        
        if (Test-Path $projectPath) {
            $projects += [PSCustomObject]@{
                Name         = $projectName
                Path         = $projectPath
                Guid         = $projectGuid
                RelativePath = $relativePath
            }
        }
    }
    
    return $projects
}

function Get-ProjectReferences {
    <#
    .SYNOPSIS
        Parses a .csproj file to extract project references and package references.
    #>
    param([string]$ProjectPath)
    
    $references = @{
        ProjectReferences = @()
        PackageReferences = @()
        TargetFramework   = ""
        RootNamespace     = ""
        AssemblyName      = ""
        Description       = ""
        Product           = ""
        Company           = ""
    }
    
    if (-not (Test-Path $ProjectPath)) {
        return $references
    }
    
    try {
        [xml]$csproj = Get-Content $ProjectPath
        
        # Get target framework
        $tfNode = $csproj.SelectSingleNode("//TargetFramework")
        if ($tfNode) { $references.TargetFramework = $tfNode.InnerText }
        
        # Get root namespace
        $nsNode = $csproj.SelectSingleNode("//RootNamespace")
        if ($nsNode) { $references.RootNamespace = $nsNode.InnerText }
        
        # Get assembly name
        $anNode = $csproj.SelectSingleNode("//AssemblyName")
        if ($anNode) { $references.AssemblyName = $anNode.InnerText }
        
        # Get description (from .csproj PropertyGroup)
        $descNode = $csproj.SelectSingleNode("//Description")
        if ($descNode) { $references.Description = $descNode.InnerText }
        
        # Get product name
        $prodNode = $csproj.SelectSingleNode("//Product")
        if ($prodNode) { $references.Product = $prodNode.InnerText }
        
        # Get company name
        $compNode = $csproj.SelectSingleNode("//Company")
        if ($compNode) { $references.Company = $compNode.InnerText }
        
        # Get project references
        $projRefs = $csproj.SelectNodes("//ProjectReference")
        foreach ($ref in $projRefs) {
            $include = $ref.GetAttribute("Include")
            if ($include) {
                $projName = [System.IO.Path]::GetFileNameWithoutExtension($include)
                $references.ProjectReferences += $projName
            }
        }
        
        # Get package references
        $pkgRefs = $csproj.SelectNodes("//PackageReference")
        foreach ($ref in $pkgRefs) {
            $include = $ref.GetAttribute("Include")
            $version = $ref.GetAttribute("Version")
            if ($include) {
                $references.PackageReferences += [PSCustomObject]@{
                    Name    = $include
                    Version = $version
                }
            }
        }
    }
    catch {
        Write-LogMessage "Error parsing project file $ProjectPath`: $($_.Exception.Message)" -Level WARN
    }
    
    return $references
}

function Read-CSharpFile {
    <#
    .SYNOPSIS
        Parses a C# file to extract classes, interfaces, methods, and properties.
    #>
    param(
        [string]$FilePath,
        [string]$ProjectName
    )
    
    $result = @{
        Namespace  = ""
        Classes    = @()
        Interfaces = @()
        Enums      = @()
        Usings     = @()
    }
    
    if (-not (Test-Path $FilePath)) {
        return $result
    }
    
    try {
        $content = Get-Content $FilePath -Raw -Encoding UTF8
        
        # Extract using statements
        $usingPattern = '^\s*using\s+([^;]+);'
        $usingMatches = [regex]::Matches($content, $usingPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($match in $usingMatches) {
            $result.Usings += $match.Groups[1].Value.Trim()
        }
        
        # Extract namespace (file-scoped or block-scoped)
        $namespacePattern = '(?:namespace\s+([^\s{;]+)\s*;)|(?:namespace\s+([^\s{]+)\s*\{)'
        $nsMatch = [regex]::Match($content, $namespacePattern)
        if ($nsMatch.Success) {
            $result.Namespace = if ($nsMatch.Groups[1].Value) { $nsMatch.Groups[1].Value } else { $nsMatch.Groups[2].Value }
        }
        
        # Extract interfaces
        $interfacePattern = '(?:public|internal|private|protected)?\s*interface\s+(\w+)(?:<[^>]+>)?(?:\s*:\s*([^\{]+))?\s*\{'
        $ifaceMatches = [regex]::Matches($content, $interfacePattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($match in $ifaceMatches) {
            $interfaceInfo = @{
                Name        = $match.Groups[1].Value
                FullName    = "$($result.Namespace).$($match.Groups[1].Value)"
                Extends     = @()
                Methods     = @()
                Properties  = @()
                ProjectName = $ProjectName
                FilePath    = $FilePath
            }
            
            if ($match.Groups[2].Success) {
                $bases = $match.Groups[2].Value -split ',' | ForEach-Object { $_.Trim() }
                $interfaceInfo.Extends = $bases
            }
            
            $result.Interfaces += $interfaceInfo
        }
        
        # Extract classes
        $classPattern = '(?:\[([^\]]+)\]\s*)*(?:public|internal|private|protected)?\s*(?:abstract|sealed|static|partial)?\s*class\s+(\w+)(?:<[^>]+>)?(?:\s*:\s*([^\{]+))?\s*\{'
        $classMatches = [regex]::Matches($content, $classPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        
        foreach ($match in $classMatches) {
            $className = $match.Groups[2].Value
            $fullName = if ($result.Namespace) { "$($result.Namespace).$className" } else { $className }
            
            $classInfo = @{
                Name            = $className
                FullName        = $fullName
                Namespace       = $result.Namespace
                Attributes      = @()
                BaseClass       = ""
                Interfaces      = @()
                Methods         = @()
                Properties      = @()
                Fields          = @()
                Dependencies    = @()
                RestEndpoints   = @()      # REST API endpoint detection
                ControllerRoute = ""     # Base route for controller
                ProjectName     = $ProjectName
                FilePath        = $FilePath
            }
            
            if ($match.Groups[1].Success) {
                $classInfo.Attributes += $match.Groups[1].Value
            }
            
            if ($match.Groups[3].Success) {
                $bases = $match.Groups[3].Value -split ',' | ForEach-Object { $_.Trim() }
                foreach ($base in $bases) {
                    $baseName = ($base -split '<')[0].Trim()
                    if ($baseName -match '^I[A-Z]') {
                        $classInfo.Interfaces += $baseName
                    }
                    elseif (-not $classInfo.BaseClass -and $baseName -ne 'object') {
                        $classInfo.BaseClass = $baseName
                    }
                }
            }
            
            $result.Classes += $classInfo
        }
        
        # Extract methods
        $methodPattern = '(?:public|protected|internal|private)\s+(?:virtual|override|abstract|static|async)?\s*(?:Task<?\w*>?|void|[\w<>,\s\[\]]+)\s+(\w+)\s*\(([^)]*)\)'
        $methodMatches = [regex]::Matches($content, $methodPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        
        $methods = @()
        foreach ($match in $methodMatches) {
            $methodName = $match.Groups[1].Value
            $parameters = $match.Groups[2].Value.Trim()
            
            $isConstructor = $false
            foreach ($class in $result.Classes) {
                if ($class.Name -eq $methodName) {
                    $isConstructor = $true
                    break
                }
            }
            
            if (-not $isConstructor) {
                $methodInfo = @{
                Name          = $methodName
                Parameters    = $parameters
                FullSignature = "$methodName($parameters)"
                SqlStatements = @()
            }
            $methods += $methodInfo
            }
        }
        
        if ($result.Classes.Count -gt 0) {
            $result.Classes[-1].Methods = $methods
        }
        
        # Detect REST API endpoints from controller classes
        # Pattern matches: [HttpGet], [HttpPost("route")], [HttpDelete("{id}")], etc.
        # Regex explanation:
        # \[(Http(Get|Post|Put|Delete|Patch))  - Match HTTP verb attribute - Group 1=full, Group 2=verb
        # (?:\("([^"]*)"\))?                    - Optional route template in quotes - Group 3
        # \]\s*                                 - Closing bracket and whitespace
        # (?:\[[^\]]+\]\s*)*                   - Skip other attributes
        # (?:public|private|protected|internal)\s+  - Access modifier
        # (?:async\s+)?                        - Optional async
        # (?:Task<?\w*>?|IActionResult|ActionResult<?\w*>?|\w+)\s+  - Return type
        # (\w+)\s*\(                           - Method name - Group 4
        $restPattern = '\[(Http(Get|Post|Put|Delete|Patch))(?:\("([^"]*)"\))?\]\s*(?:\[[^\]]+\]\s*)*(?:public|private|protected|internal)\s+(?:async\s+)?(?:Task<?\w*>?|IActionResult|ActionResult<?\w*>?|\w+)\s+(\w+)\s*\('
        $restMatches = [regex]::Matches($content, $restPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        if ($restMatches.Count -gt 0) {
            # Find controller route from class attribute
            $routePattern = '\[Route\("([^"]*)"\)\]'
            $routeMatch = [regex]::Match($content, $routePattern)
            $baseRoute = if ($routeMatch.Success) { $routeMatch.Groups[1].Value } else { "" }
            
            foreach ($class in $result.Classes) {
                if ($class.BaseClass -match 'Controller|ControllerBase' -or $class.Attributes -match 'ApiController') {
                    $class.ControllerRoute = $baseRoute
                }
            }
            
            foreach ($restMatch in $restMatches) {
                $httpVerb = $restMatch.Groups[2].Value.ToUpper()
                $routeTemplate = if ($restMatch.Groups[3].Success) { $restMatch.Groups[3].Value } else { "" }
                $methodName = $restMatch.Groups[4].Value
                
                # Add to the controller class
                foreach ($class in $result.Classes) {
                    if ($class.BaseClass -match 'Controller|ControllerBase' -or $class.Attributes -match 'ApiController') {
                        $fullRoute = if ($class.ControllerRoute -and $routeTemplate) {
                            "$($class.ControllerRoute)/$routeTemplate"
                        }
                        elseif ($class.ControllerRoute) {
                            $class.ControllerRoute
                        }
                        else {
                            $routeTemplate
                        }
                        
                        $class.RestEndpoints += @{
                            HttpVerb   = $httpVerb
                            Route      = $routeTemplate
                            FullRoute  = $fullRoute
                            MethodName = $methodName
                        }
                        break
                    }
                }
            }
        }
        
        # Extract constructor dependencies
        $ctorPattern = 'public\s+(\w+)\s*\(([^)]+)\)'
        $ctorMatches = [regex]::Matches($content, $ctorPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        
        foreach ($match in $ctorMatches) {
            $ctorName = $match.Groups[1].Value
            $params = $match.Groups[2].Value
            
            foreach ($class in $result.Classes) {
                if ($class.Name -eq $ctorName) {
                    $paramList = $params -split ','
                    foreach ($param in $paramList) {
                        $param = $param.Trim()
                        if ($param -match '^([\w<>]+)\s+\w+$') {
                            $typeName = $matches[1]
                            if ($typeName -notmatch '^(string|int|bool|double|float|decimal|long|short|byte|char|object|CancellationToken)$') {
                                $class.Dependencies += $typeName
                            }
                        }
                    }
                    break
                }
            }
        }
    }
    catch {
        Write-LogMessage "Error parsing C# file $FilePath`: $($_.Exception.Message)" -Level WARN
    }
    
    return $result
}

#endregion

#region Mermaid Generation

function Write-CSharpMmdClass {
    param([string]$mmdString)
    # No duplicate check - structural elements like } appear multiple times
    [void]$script:mmdClassContent.Add($mmdString)
}

function Write-CSharpMmdFlow {
    param([string]$mmdString)
    # No duplicate check - structural elements like end appear multiple times
    $script:sequenceNumber++
    [void]$script:mmdFlowContent.Add($mmdString)
}

function Write-CSharpMmdInteraction {
    param([string]$mmdString)
    # No duplicate check - structural elements appear multiple times
    [void]$script:mmdInteractionContent.Add($mmdString)
}

function Write-CSharpMmdExecFlow {
    param([string]$mmdString)
    [void]$script:mmdExecutionFlowContent.Add($mmdString)
}

function Get-CSharpProcessInvocations {
    <#
    .SYNOPSIS
        Detects external process invocations in C# source code.
    .DESCRIPTION
        Scans C# source files for patterns like Process.Start(), ProcessStartInfo,
        SqlConnection, SqlCommand, and other external process/database invocations.
    .PARAMETER CsFiles
        Array of C# file paths to scan.
    .RETURNS
        Array of hashtables with process invocation details.
    #>
    param(
        [string[]]$CsFiles
    )
    
    $invocations = @()
    
    foreach ($filePath in $CsFiles) {
        if (-not (Test-Path $filePath)) { continue }
        
        try {
            $content = Get-Content -Path $filePath -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrEmpty($content)) { continue }
            
            $fileName = Split-Path $filePath -Leaf
            
            # Detect Process.Start() calls
            $processStartMatches = [regex]::Matches($content, 'Process\.Start\s*\(\s*(?:"([^"]+)"|([^,\)]+))')
            foreach ($match in $processStartMatches) {
                $processName = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value.Trim() }
                $invocations += @{
                    Type       = "Process"
                    Name       = $processName
                    Details    = "Process.Start"
                    SourceFile = $fileName
                }
            }
            
            # Detect ProcessStartInfo with FileName
            $psiMatches = [regex]::Matches($content, 'ProcessStartInfo[^{]*\{[^}]*FileName\s*=\s*"([^"]+)"')
            foreach ($match in $psiMatches) {
                $invocations += @{
                    Type       = "Process"
                    Name       = $match.Groups[1].Value
                    Details    = "ProcessStartInfo"
                    SourceFile = $fileName
                }
            }
            
            # Detect SqlConnection usage
            $sqlConnMatches = [regex]::Matches($content, 'new\s+SqlConnection\s*\(')
            foreach ($match in $sqlConnMatches) {
                $invocations += @{
                    Type       = "Database"
                    Name       = "SQL Server"
                    Details    = "SqlConnection"
                    SourceFile = $fileName
                }
            }
            
            # Detect DB2 connections
            $db2Matches = [regex]::Matches($content, '(DB2Connection|OdbcConnection|Db2Command)', 'IgnoreCase')
            foreach ($match in $db2Matches) {
                $invocations += @{
                    Type       = "Database"
                    Name       = "DB2/ODBC"
                    Details    = $match.Value
                    SourceFile = $fileName
                }
            }
            
            # Detect PowerShell invocations
            $psMatches = [regex]::Matches($content, '("powershell\.exe"|"pwsh\.exe"|PowerShell\.Create|Runspace)', 'IgnoreCase')
            foreach ($match in $psMatches) {
                $invocations += @{
                    Type       = "PowerShell"
                    Name       = "PowerShell"
                    Details    = $match.Value -replace '"', ''
                    SourceFile = $fileName
                }
            }
            
            # Detect CMD/batch script invocations
            $cmdMatches = [regex]::Matches($content, '("cmd\.exe"|"\.bat"|"\.cmd")', 'IgnoreCase')
            foreach ($match in $cmdMatches) {
                $invocations += @{
                    Type       = "Script"
                    Name       = "CMD/Batch"
                    Details    = $match.Value -replace '"', ''
                    SourceFile = $fileName
                }
            }
            
            # Detect HTTP client usage (external API calls)
            $httpMatches = [regex]::Matches($content, '(HttpClient|WebClient|WebRequest|RestClient)')
            foreach ($match in $httpMatches) {
                $invocations += @{
                    Type       = "HTTP"
                    Name       = "External API"
                    Details    = $match.Value
                    SourceFile = $fileName
                }
            }
        }
        catch {
            Write-LogMessage "Error scanning file for process invocations: $filePath - $_" -Level WARN
        }
    }
    
    return $invocations
}

function New-CSharpProcessDiagram {
    <#
    .SYNOPSIS
        Generates a Mermaid diagram showing external process invocations.
    #>
    param(
        [string]$SolutionName,
        [array]$ProcessInvocations
    )
    
    if (-not $ProcessInvocations -or $ProcessInvocations.Count -eq 0) {
        return "flowchart LR`n    noprocess[No external process invocations detected]"
    }
    
    $mmdContent = @()
    $mmdContent += "flowchart LR"
    
    # Add main solution node
    $solutionNode = $SolutionName -replace '[^a-zA-Z0-9]', '_'
    $mmdContent += "    $($solutionNode)[[`"$SolutionName`"]]"
    $mmdContent += "    style $solutionNode stroke:#10b981,stroke-width:3px"
    
    # Group by type
    $groupedProcesses = $ProcessInvocations | Group-Object -Property Type
    
    $nodeCounter = 0
    foreach ($group in $groupedProcesses) {
        $typeLabel = switch ($group.Name) {
            "Process" { "External Processes" }
            "Database" { "Databases" }
            "PowerShell" { "PowerShell Scripts" }
            "Script" { "Batch/CMD Scripts" }
            "HTTP" { "HTTP/API Calls" }
            default { $group.Name }
        }
        
        $typeShape = switch ($group.Name) {
            "Process" { "{{" }      # Hexagon
            "Database" { "[(" }     # Cylinder
            "PowerShell" { "([" }   # Stadium
            "Script" { "(" }        # Rounded
            "HTTP" { "((" }         # Circle
            default { "(" }
        }
        
        $typeShapeEnd = switch ($group.Name) {
            "Process" { "}}" }
            "Database" { ")]" }
            "PowerShell" { "])" }
            "Script" { ")" }
            "HTTP" { "))" }
            default { ")" }
        }
        
        $typeColor = switch ($group.Name) {
            "Process" { "#f59e0b" }    # Amber
            "Database" { "#10b981" }   # Green
            "PowerShell" { "#3b82f6" } # Blue
            "Script" { "#8b5cf6" }     # Purple
            "HTTP" { "#ef4444" }       # Red
            default { "#6b7280" }
        }
        
        # Get unique process names with their source files
        $uniqueProcesses = $group.Group | Select-Object -Property Name, Details, SourceFile -Unique
        
        foreach ($proc in $uniqueProcesses) {
            $nodeCounter++
            $nodeId = "proc$nodeCounter"
            $safeName = $proc.Name -replace '["\n\r]', '' -replace '\s+', ' '
            if ($safeName.Length -gt 40) {
                $safeName = $safeName.Substring(0, 37) + "..."
            }
            
            $mmdContent += "    $solutionNode --`"$($group.Name)`"--> $nodeId$typeShape`"$safeName`"$typeShapeEnd"
            $mmdContent += "    style $nodeId stroke:$typeColor,stroke-width:2px"
        }
    }
    
    return ($mmdContent -join "`n")
}

function Get-CSharpApiConfiguration {
    <#
    .SYNOPSIS
        Extracts REST API configuration (URLs, ports) from C# project config files.
    .DESCRIPTION
        Parses appsettings.json and launchSettings.json to find REST API base URLs
        and port configurations for cross-referencing with external callers.
    .PARAMETER ProjectFolder
        Path to the C# project folder.
    .RETURNS
        Hashtable containing ApiUrl, Port, and Endpoints information.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectFolder
    )
    
    $apiConfig = @{
        BaseUrls         = @()
        Ports            = @()
        EndpointPatterns = @()
    }
    
    # Find and parse appsettings.json files
    $appsettingsFiles = Get-ChildItem -Path $ProjectFolder -Filter "appsettings*.json" -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -notmatch '\\(bin|obj|node_modules)\\' }
    
    foreach ($file in $appsettingsFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrEmpty($content)) { continue }
            
            $json = $content | ConvertFrom-Json -ErrorAction SilentlyContinue
            if (-not $json) { continue }
            
            # Extract Kestrel endpoints
            if ($json.Kestrel.Endpoints) {
                foreach ($endpoint in $json.Kestrel.Endpoints.PSObject.Properties) {
                    if ($endpoint.Value.Url) {
                        $url = $endpoint.Value.Url
                        $apiConfig.BaseUrls += $url
                        
                        # Extract port from URL
                        if ($url -match ':(\d+)') {
                            $port = $Matches[1]
                            if ($port -notin $apiConfig.Ports) {
                                $apiConfig.Ports += $port
                            }
                        }
                    }
                }
            }
            
            # Extract RestApi configuration
            if ($json.RestApi.Port) {
                $port = $json.RestApi.Port.ToString()
                if ($port -notin $apiConfig.Ports) {
                    $apiConfig.Ports += $port
                }
            }
            
            # Extract Dashboard.ServerMonitorPort (for interconnected services)
            if ($json.Dashboard.ServerMonitorPort) {
                $port = $json.Dashboard.ServerMonitorPort.ToString()
                if ($port -notin $apiConfig.Ports) {
                    $apiConfig.Ports += $port
                }
            }
        }
        catch {
            Write-LogMessage "Error parsing appsettings file: $($file.FullName) - $_" -Level WARN
        }
    }
    
    # Find and parse launchSettings.json files
    $launchSettingsFiles = Get-ChildItem -Path $ProjectFolder -Filter "launchSettings.json" -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -notmatch '\\(bin|obj|node_modules)\\' }
    
    foreach ($file in $launchSettingsFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrEmpty($content)) { continue }
            
            $json = $content | ConvertFrom-Json -ErrorAction SilentlyContinue
            if (-not $json) { continue }
            
            # Extract URLs from profiles
            if ($json.profiles) {
                foreach ($profile in $json.profiles.PSObject.Properties) {
                    $profileValue = $profile.Value
                    
                    # Check applicationUrl
                    if ($profileValue.applicationUrl) {
                        $urls = $profileValue.applicationUrl -split ';'
                        foreach ($url in $urls) {
                            $url = $url.Trim()
                            if ($url -and $url -notin $apiConfig.BaseUrls) {
                                $apiConfig.BaseUrls += $url
                            }
                            if ($url -match ':(\d+)') {
                                $port = $Matches[1]
                                if ($port -notin $apiConfig.Ports) {
                                    $apiConfig.Ports += $port
                                }
                            }
                        }
                    }
                }
            }
        }
        catch {
            Write-LogMessage "Error parsing launchSettings file: $($file.FullName) - $_" -Level WARN
        }
    }
    
    return $apiConfig
}

function Find-ExternalApiCallers {
    <#
    .SYNOPSIS
        Finds external callers (PS1, BAT, CBL) that reference C# REST API endpoints.
    .DESCRIPTION
        Searches PowerShell, Batch, and COBOL files for HTTP calls matching
        the C# project's API ports and endpoints.
    .PARAMETER SrcRootFolder
        Root folder to search for caller files.
    .PARAMETER ApiPorts
        Array of port numbers to search for.
    .PARAMETER RestEndpoints
        Array of REST endpoint configurations to match against.
    .PARAMETER OutputFolder
        Folder where generated HTML files are stored (for linking).
    .RETURNS
        Array of caller information including file path, type, and matched endpoint.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SrcRootFolder,
        
        [string[]]$ApiPorts = @(),
        [array]$RestEndpoints = @(),
        [string]$OutputFolder = ""
    )
    
    $callers = @()
    
    if (-not (Test-Path $SrcRootFolder)) {
        return $callers
    }
    
    # Define file types to search (PS1, BAT, CMD, REX, CBL)
    $fileTypes = @("*.ps1", "*.bat", "*.cmd", "*.rex", "*.cbl")
    
    # Build search patterns from ports
    $portPatterns = @()
    foreach ($port in $ApiPorts) {
        $portPatterns += ":$port"
        $portPatterns += "localhost:$port"
        $portPatterns += "127\.0\.0\.1:$port"
    }
    
    # Build search patterns from REST endpoints
    $endpointPatterns = @()
    foreach ($endpoint in $RestEndpoints) {
        if ($endpoint.Route) {
            # Extract meaningful route parts (skip {id} and similar placeholders)
            $routeParts = $endpoint.Route -replace '\{[^}]+\}', '' -replace '^\/', '' -replace '\/$', ''
            if ($routeParts) {
                $endpointPatterns += "api/$routeParts"
                $endpointPatterns += "/api/$routeParts"
            }
        }
    }
    
    # Search for files containing API references
    foreach ($fileType in $fileTypes) {
        $files = Get-ChildItem -Path $SrcRootFolder -Filter $fileType -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -notmatch '\\(bin|obj|node_modules|\.git|_old)\\' }
        
        foreach ($file in $files) {
            try {
                $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
                if ([string]::IsNullOrEmpty($content)) { continue }
                
                $contentLower = $content.ToLower()
                $isApiCaller = $false
                $matchedPattern = ""
                $matchedEndpoints = @()
                
                # Check for port patterns
                foreach ($pattern in $portPatterns) {
                    if ($content -match [regex]::Escape($pattern)) {
                        $isApiCaller = $true
                        $matchedPattern = $pattern
                        
                        # Also check which specific endpoint is being called
                        foreach ($endpoint in $RestEndpoints) {
                            $routeLower = $endpoint.Route.ToLower()
                            if ($contentLower -match [regex]::Escape($routeLower) -or 
                                $contentLower -match "api/$($endpoint.MethodName.ToLower())") {
                                $matchedEndpoints += $endpoint
                            }
                        }
                        break
                    }
                }
                
                # Check for endpoint patterns (e.g., /api/Alerts, /api/snapshot)
                if (-not $isApiCaller) {
                    foreach ($pattern in $endpointPatterns) {
                        if ($contentLower -match [regex]::Escape($pattern.ToLower())) {
                            $isApiCaller = $true
                            $matchedPattern = $pattern
                            
                            # Find matching endpoint details
                            foreach ($endpoint in $RestEndpoints) {
                                $routeLower = $endpoint.Route.ToLower()
                                if ($pattern.ToLower() -match [regex]::Escape($routeLower)) {
                                    $matchedEndpoints += $endpoint
                                }
                            }
                            break
                        }
                    }
                }
                
                if ($isApiCaller) {
                    $fileExt = [System.IO.Path]::GetExtension($file.Name).ToLower()
                    $callerType = switch ($fileExt) {
                        ".ps1" { "PowerShell" }
                        ".bat" { "Batch" }
                        ".cmd" { "Batch" }
                        ".cbl" { "COBOL" }
                        default { "Script" }
                    }
                    
                    # Generate expected HTML filename for linking
                    $htmlFileName = $file.Name + ".html"
                    
                    $callers += @{
                        FileName         = $file.Name
                        FilePath         = $file.FullName
                        FileType         = $callerType
                        MatchedPattern   = $matchedPattern
                        MatchedEndpoints = $matchedEndpoints
                        HtmlLink         = $htmlFileName
                        RelativePath     = $file.FullName.Replace($SrcRootFolder, "").TrimStart('\', '/')
                    }
                }
            }
            catch {
                # Silently skip files that can't be read
            }
        }
    }
    
    return $callers
}

function Get-MethodBody {
    <#
    .SYNOPSIS
        Extracts the body of a method from C# source code.
    #>
    param(
        [string]$Content,
        [string]$MethodName
    )
    
    # Find method signature and extract body between { }
    $pattern = "(?:public|protected|private|internal)\s+(?:static\s+)?(?:async\s+)?(?:virtual\s+)?(?:override\s+)?[\w<>\[\],\s]+\s+$MethodName\s*\([^)]*\)\s*\{"
    $match = [regex]::Match($Content, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    
    if (-not $match.Success) { return "" }
    
    $startIndex = $match.Index + $match.Length - 1
    $braceCount = 1
    $endIndex = $startIndex + 1
    
    while ($braceCount -gt 0 -and $endIndex -lt $Content.Length) {
        $char = $Content[$endIndex]
        if ($char -eq '{') { $braceCount++ }
        elseif ($char -eq '}') { $braceCount-- }
        $endIndex++
    }
    
    if ($braceCount -eq 0) {
        return $Content.Substring($startIndex + 1, $endIndex - $startIndex - 2)
    }
    return ""
}

function Get-MethodControlFlow {
    <#
    .SYNOPSIS
        Parses method body for control flow statements (if, while, for, foreach, switch, try/catch).
    #>
    param(
        [string]$MethodBody,
        [string]$MethodName,
        [string]$ClassName
    )
    
    $flowNodes = @()
    $nodeId = 0
    $safeMethod = ($MethodName -replace '[^a-zA-Z0-9]', '_')
    $safeClass = ($ClassName -replace '[^a-zA-Z0-9]', '_')
    $prefix = "${safeClass}_${safeMethod}"
    
    # Start node
    $flowNodes += @{ Id = "${prefix}_start"; Label = "Start: $MethodName"; Type = "start" }
    
    # Find control flow statements
    $patterns = @{
        'if'      = 'if\s*\(([^)]+)\)'
        'else'    = 'else\s*\{'
        'for'     = 'for\s*\(([^)]+)\)'
        'foreach' = 'foreach\s*\(([^)]+)\)'
        'while'   = 'while\s*\(([^)]+)\)'
        'switch'  = 'switch\s*\(([^)]+)\)'
        'try'     = 'try\s*\{'
        'catch'   = 'catch\s*(?:\([^)]*\))?\s*\{'
        'return'  = 'return\s+([^;]+);'
        'await'   = 'await\s+([^;]+);'
        'throw'   = 'throw\s+([^;]+);'
    }
    
    # Extract method calls
    $callPattern = '(?:await\s+)?(\w+)\s*\.\s*(\w+)\s*\('
    $callMatches = [regex]::Matches($MethodBody, $callPattern)
    
    foreach ($call in $callMatches) {
        $obj = $call.Groups[1].Value
        $method = $call.Groups[2].Value
        
        # Skip common non-interesting calls
        if ($obj -in @('Console', 'Debug', 'Trace', 'string', 'int', 'Math', 'Convert')) { continue }
        
        $nodeId++
        $flowNodes += @{ 
            Id     = "${prefix}_call_$nodeId"
            Label  = "$obj.$method()"
            Type   = "call"
            Target = $method
        }
    }
    
    # Find control structures
    foreach ($type in $patterns.Keys) {
        $matches = [regex]::Matches($MethodBody, $patterns[$type])
        foreach ($m in $matches) {
            $nodeId++
            $condition = if ($m.Groups.Count -gt 1) { $m.Groups[1].Value } else { "" }
            $shortCondition = if ($condition.Length -gt 30) { $condition.Substring(0, 30) + "..." } else { $condition }
            
            $flowNodes += @{
                Id        = "${prefix}_${type}_$nodeId"
                Label     = "$type $shortCondition"
                Type      = $type
                Condition = $condition
            }
        }
    }
    
    # End node
    $flowNodes += @{ Id = "${prefix}_end"; Label = "End"; Type = "end" }
    
    return $flowNodes
}

function Get-AllProjectsInFolder {
    <#
    .SYNOPSIS
        Discovers all .csproj files in a folder tree to find the complete project ecosystem.
    #>
    param(
        [string]$RootFolder
    )
    
    $projects = @{}
    $projectRefs = @{}
    
    # Find all .csproj files (excluding bin/obj/packages)
    $csprojFiles = Get-ChildItem -Path $RootFolder -Filter "*.csproj" -Recurse -File | Where-Object {
        $_.DirectoryName -notmatch '\\(bin|obj|packages|node_modules|\.git)[\\/]?'
    }
    
    Write-LogMessage "Found $($csprojFiles.Count) .csproj files in ecosystem" -Level INFO
    
    foreach ($csproj in $csprojFiles) {
        $projName = [System.IO.Path]::GetFileNameWithoutExtension($csproj.Name)
        
        # Skip test projects for the main diagram
        if ($projName -match '\.Tests$|\.Test$|Tests$') { continue }
        
        $projRefs = Get-ProjectReferences -ProjectPath $csproj.FullName
        
        $projects[$projName] = @{
            Name              = $projName
            Path              = $csproj.FullName
            Directory         = $csproj.DirectoryName
            TargetFramework   = $projRefs.TargetFramework
            RootNamespace     = $projRefs.RootNamespace
            AssemblyName      = $projRefs.AssemblyName
            PackageReferences = $projRefs.PackageReferences
            ParentFolder      = (Split-Path (Split-Path $csproj.FullName -Parent) -Leaf)
        }
        
        $projectRefs[$projName] = $projRefs.ProjectReferences
    }
    
    return @{
        Projects          = $projects
        ProjectReferences = $projectRefs
    }
}

function New-FullEcosystemDiagram {
    <#
    .SYNOPSIS
        Generates a comprehensive ecosystem diagram showing all projects in a folder and their relationships.
    #>
    param(
        [hashtable]$Projects,
        [hashtable]$ProjectReferences,
        [array]$Communications,
        [string]$EcosystemName
    )
    
    $diagram = [System.Collections.ArrayList]::new()
    [void]$diagram.Add("flowchart TB")
    [void]$diagram.Add("")
    [void]$diagram.Add("    %% $EcosystemName - Full Ecosystem Diagram")
    [void]$diagram.Add("")
    
    # Categorize projects by their purpose (detected from name and references)
    $categories = @{
        Agents        = @()
        Dashboards    = @()
        TrayApps      = @()
        CoreLibraries = @()
        WebApis       = @()
        Services      = @()
    }
    
    foreach ($projName in $Projects.Keys) {
        $proj = $Projects[$projName]
        $safeName = $projName -replace '[^a-zA-Z0-9]', '_'
        $item = @{ Name = $projName; SafeName = $safeName; Project = $proj }
        
        # Categorize based on name patterns
        if ($projName -match 'Agent') { $categories.Agents += $item }
        elseif ($projName -match 'Dashboard|Web') { $categories.Dashboards += $item }
        elseif ($projName -match 'Tray|Icon|Desktop') { $categories.TrayApps += $item }
        elseif ($projName -match '\.Core$|\.Common$|\.Shared$') { $categories.CoreLibraries += $item }
        elseif ($projName -match 'Api$|\.Api$') { $categories.WebApis += $item }
        else { $categories.Services += $item }
    }
    
    # Create visual groupings
    $categoryConfig = @{
        Agents        = @{ Icon = "🖥️"; Title = "Server Agents"; Style = "agent"; Color = "#2d5016" }
        Dashboards    = @{ Icon = "📊"; Title = "Web Dashboards"; Style = "dashboard"; Color = "#1e3a5f" }
        TrayApps      = @{ Icon = "🔔"; Title = "Desktop/Tray Apps"; Style = "tray"; Color = "#5c2d91" }
        CoreLibraries = @{ Icon = "📦"; Title = "Core Libraries"; Style = "core"; Color = "#7b3f00" }
        WebApis       = @{ Icon = "🌐"; Title = "Web APIs"; Style = "api"; Color = "#0d6efd" }
        Services      = @{ Icon = "⚙️"; Title = "Services"; Style = "service"; Color = "#198754" }
    }
    
    # Generate subgraphs for each category with projects
    foreach ($catName in $categoryConfig.Keys) {
        $items = $categories[$catName]
        if ($items.Count -eq 0) { continue }
        
        $config = $categoryConfig[$catName]
        $subgraphId = $catName -replace '[^a-zA-Z0-9]', '_'
        
        [void]$diagram.Add("    subgraph $subgraphId[`"$($config.Icon) $($config.Title)`"]")
        
        foreach ($item in $items) {
            $framework = if ($item.Project.TargetFramework) { $item.Project.TargetFramework } else { "" }
            $label = "$($item.Name)"
            if ($framework) { $label += "<br/><small>$framework</small>" }
            
            # Use different shapes based on project type
            $shape = switch ($catName) {
                "Agents" { "([`"$label`"])" }
                "Dashboards" { "[(`"$label`")]" }
                "TrayApps" { "{{`"$label`"}}" }
                "CoreLibraries" { "[[$label]]" }
                "WebApis" { "[/`"$label`"/]" }
                default { "[`"$label`"]" }
            }
            
            [void]$diagram.Add("        $($item.SafeName)$shape")
        }
        
        [void]$diagram.Add("    end")
        [void]$diagram.Add("")
    }
    
    # Add project reference connections (compile-time dependencies)
    [void]$diagram.Add("    %% Project References (compile-time)")
    $addedConnections = @{}
    
    foreach ($projName in $ProjectReferences.Keys) {
        $safeName = $projName -replace '[^a-zA-Z0-9]', '_'
        $refs = $ProjectReferences[$projName]
        
        foreach ($ref in $refs) {
            $safeRef = $ref -replace '[^a-zA-Z0-9]', '_'
            $connKey = "$safeName-->$safeRef"
            
            if (-not $addedConnections.ContainsKey($connKey) -and $Projects.ContainsKey($ref)) {
                [void]$diagram.Add("    $safeName -->|uses| $safeRef")
                $addedConnections[$connKey] = $true
            }
        }
    }
    
    [void]$diagram.Add("")
    
    # Add runtime/API communication patterns
    [void]$diagram.Add("    %% Runtime Communication (HTTP/API)")
    $apiConnections = @{}
    
    foreach ($comm in $Communications) {
        if ($comm.Type -eq "HTTP" -and $comm.Endpoint -match '/api/') {
            $fromProj = $comm.FromProject -replace '[^a-zA-Z0-9]', '_'
            
            # Determine target based on endpoint pattern
            $targetProj = $null
            $endpointLabel = ($comm.Endpoint -replace '\$\{[^}]+\}', '*' -replace '\{[^}]+\}', '*')
            if ($endpointLabel.Length -gt 25) { $endpointLabel = $endpointLabel.Substring(0, 22) + "..." }
            
            if ($comm.Endpoint -match 'snapshot|health|metrics|status') {
                # Likely calling an agent
                $targetProj = ($categories.Agents | Select-Object -First 1).SafeName
            }
            elseif ($comm.Endpoint -match 'agent|restart|stop|start') {
                # Agent control API
                $targetProj = ($categories.Agents | Select-Object -First 1).SafeName
            }
            elseif ($comm.Endpoint -match 'dashboard|ui|web') {
                $targetProj = ($categories.Dashboards | Select-Object -First 1).SafeName
            }
            
            if ($targetProj -and $fromProj -ne $targetProj) {
                $connKey = "$fromProj-.->$targetProj"
                if (-not $apiConnections.ContainsKey($connKey)) {
                    [void]$diagram.Add("    $fromProj -.->|`"$endpointLabel`"| $targetProj")
                    $apiConnections[$connKey] = $true
                }
            }
        }
    }
    
    [void]$diagram.Add("")
    
    # Add styling
    [void]$diagram.Add("    %% Styling")
    [void]$diagram.Add("    classDef agent fill:#2d5016,stroke:#4a8522,color:#fff")
    [void]$diagram.Add("    classDef dashboard fill:#1e3a5f,stroke:#3a7bd5,color:#fff")
    [void]$diagram.Add("    classDef tray fill:#5c2d91,stroke:#8661c5,color:#fff")
    [void]$diagram.Add("    classDef core fill:#7b3f00,stroke:#c9711a,color:#fff")
    [void]$diagram.Add("    classDef api fill:#0d6efd,stroke:#3d8bfd,color:#fff")
    [void]$diagram.Add("    classDef service fill:#198754,stroke:#25a56a,color:#fff")
    
    foreach ($catName in $categoryConfig.Keys) {
        $items = $categories[$catName]
        $style = $categoryConfig[$catName].Style
        foreach ($item in $items) {
            [void]$diagram.Add("    class $($item.SafeName) $style")
        }
    }
    
    return ($diagram -join "`n")
}

function Get-ProjectCommunication {
    <#
    .SYNOPSIS
        Analyzes C# source files for inter-project communication patterns (HTTP, API calls, shared interfaces).
    #>
    param(
        [hashtable]$Projects,
        [string]$SourceFolder
    )
    
    $communications = @()
    
    foreach ($projName in $Projects.Keys) {
        $proj = $Projects[$projName]
        $projDir = Split-Path $proj.Path -Parent
        
        # Get all C# files in this project
        $csFiles = Get-CSharpFiles -FolderPath $projDir
        
        foreach ($csFile in $csFiles) {
            $content = Get-Content $csFile.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            
            # Detect HTTP client usage with base URLs
            $httpPatterns = @(
                '(?:BaseAddress|_baseUrl|baseUrl)\s*=\s*["`]([^"`]+)["`]',
                'new\s+HttpClient[^}]+BaseAddress\s*=\s*new\s+Uri\(["`]([^"`]+)["`]\)',
                'GetAsync\(["`\$]([^"`]+)["`]?\)',
                'PostAsync\(["`\$]([^"`]+)["`]?',
                '/api/(\w+)(?:/\w+)*'
            )
            
            foreach ($pattern in $httpPatterns) {
                $matches = [regex]::Matches($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                foreach ($m in $matches) {
                    $endpoint = $m.Groups[1].Value
                    if ($endpoint -and $endpoint.Length -gt 2) {
                        $communications += @{
                            FromProject = $projName
                            Type        = "HTTP"
                            Endpoint    = $endpoint
                            File        = $csFile.Name
                        }
                    }
                }
            }
            
            # Detect service/interface dependencies
            if ($content -match 'class\s+(\w+Service)\s*:') {
                $serviceName = $matches[1]
                $communications += @{
                    FromProject = $projName
                    Type        = "Service"
                    ServiceName = $serviceName
                    File        = $csFile.Name
                }
            }
            
            # Detect API controllers
            if ($content -match '\[ApiController\]|\[Route\(["`]api/') {
                $controllerMatch = [regex]::Match($content, 'class\s+(\w+Controller)')
                if ($controllerMatch.Success) {
                    $communications += @{
                        FromProject    = $projName
                        Type           = "ApiController"
                        ControllerName = $controllerMatch.Groups[1].Value
                        File           = $csFile.Name
                    }
                }
            }
            
            # Detect SignalR hubs
            if ($content -match 'class\s+(\w+)\s*:\s*Hub') {
                $communications += @{
                    FromProject = $projName
                    Type        = "SignalRHub"
                    HubName     = $matches[1]
                    File        = $csFile.Name
                }
            }
        }
    }
    
    return $communications
}

function New-EcosystemDiagram {
    <#
    .SYNOPSIS
        Generates a Mermaid diagram showing how multiple projects in a solution interact.
    #>
    param(
        [hashtable]$Projects,
        [hashtable]$ProjectReferences,
        [array]$Communications,
        [string]$SolutionName
    )
    
    $diagram = [System.Collections.ArrayList]::new()
    [void]$diagram.Add("flowchart TB")
    [void]$diagram.Add("")
    [void]$diagram.Add("    %% $SolutionName Ecosystem")
    [void]$diagram.Add("")
    
    # Categorize projects by type
    $agents = @()
    $dashboards = @()
    $trayApps = @()
    $apis = @()
    $libraries = @()
    
    foreach ($projName in $Projects.Keys) {
        $safeName = $projName -replace '[^a-zA-Z0-9]', '_'
        
        if ($projName -match 'Agent') { $agents += @{ Name = $projName; SafeName = $safeName } }
        elseif ($projName -match 'Dashboard|Web|UI') { $dashboards += @{ Name = $projName; SafeName = $safeName } }
        elseif ($projName -match 'Tray|Icon|Desktop') { $trayApps += @{ Name = $projName; SafeName = $safeName } }
        elseif ($projName -match 'Api|Service') { $apis += @{ Name = $projName; SafeName = $safeName } }
        else { $libraries += @{ Name = $projName; SafeName = $safeName } }
    }
    
    # Create subgraphs for each category
    if ($agents.Count -gt 0) {
        [void]$diagram.Add("    subgraph Agents[`"🖥️ Server Agents`"]")
        foreach ($a in $agents) {
            [void]$diagram.Add("        $($a.SafeName)([`"$($a.Name)`"])")
        }
        [void]$diagram.Add("    end")
        [void]$diagram.Add("")
    }
    
    if ($dashboards.Count -gt 0) {
        [void]$diagram.Add("    subgraph Dashboards[`"📊 Dashboards`"]")
        foreach ($d in $dashboards) {
            [void]$diagram.Add("        $($d.SafeName)([`"$($d.Name)`"])")
        }
        [void]$diagram.Add("    end")
        [void]$diagram.Add("")
    }
    
    if ($trayApps.Count -gt 0) {
        [void]$diagram.Add("    subgraph TrayApps[`"🔔 Tray Applications`"]")
        foreach ($t in $trayApps) {
            [void]$diagram.Add("        $($t.SafeName)([`"$($t.Name)`"])")
        }
        [void]$diagram.Add("    end")
        [void]$diagram.Add("")
    }
    
    if ($libraries.Count -gt 0) {
        [void]$diagram.Add("    subgraph Libraries[`"📦 Shared Libraries`"]")
        foreach ($l in $libraries) {
            [void]$diagram.Add("        $($l.SafeName)[`"$($l.Name)`"]")
        }
        [void]$diagram.Add("    end")
        [void]$diagram.Add("")
    }
    
    # Add project references as connections
    $addedConnections = @{}
    foreach ($projName in $ProjectReferences.Keys) {
        $safeName = $projName -replace '[^a-zA-Z0-9]', '_'
        $refs = $ProjectReferences[$projName]
        
        foreach ($ref in $refs) {
            $safeRef = $ref -replace '[^a-zA-Z0-9]', '_'
            $connKey = "$safeName->$safeRef"
            if (-not $addedConnections.ContainsKey($connKey)) {
                [void]$diagram.Add("    $safeName -->|references| $safeRef")
                $addedConnections[$connKey] = $true
            }
        }
    }
    
    [void]$diagram.Add("")
    
    # Add API communication patterns
    $apiEndpoints = $Communications | Where-Object { $_.Type -eq "HTTP" -and $_.Endpoint -match '/api/' }
    $groupedByProject = $apiEndpoints | Group-Object -Property FromProject
    
    foreach ($group in $groupedByProject) {
        $fromProj = $group.Name -replace '[^a-zA-Z0-9]', '_'
        
        # Infer target based on endpoint patterns
        foreach ($comm in ($group.Group | Select-Object -First 5)) {
            $endpoint = $comm.Endpoint
            
            # Try to infer which project this connects to
            if ($endpoint -match 'snapshot|health|status') {
                foreach ($a in $agents) {
                    $connKey = "$fromProj->$($a.SafeName)_api"
                    if (-not $addedConnections.ContainsKey($connKey)) {
                        [void]$diagram.Add("    $fromProj -.->|`"API: $endpoint`"| $($a.SafeName)")
                        $addedConnections[$connKey] = $true
                        break
                    }
                }
            }
            elseif ($endpoint -match 'agent|script|restart') {
                foreach ($a in $agents) {
                    $connKey = "$fromProj->$($a.SafeName)_ctrl"
                    if (-not $addedConnections.ContainsKey($connKey)) {
                        [void]$diagram.Add("    $fromProj -.->|`"Control: $endpoint`"| $($a.SafeName)")
                        $addedConnections[$connKey] = $true
                        break
                    }
                }
            }
        }
    }
    
    # Add styling
    [void]$diagram.Add("")
    [void]$diagram.Add("    %% Styling")
    [void]$diagram.Add("    classDef agent fill:#2d5016,stroke:#4a8522,color:#fff")
    [void]$diagram.Add("    classDef dashboard fill:#1e3a5f,stroke:#3a7bd5,color:#fff")
    [void]$diagram.Add("    classDef tray fill:#5c2d91,stroke:#8661c5,color:#fff")
    [void]$diagram.Add("    classDef library fill:#4a4a4a,stroke:#888,color:#fff")
    
    foreach ($a in $agents) { [void]$diagram.Add("    class $($a.SafeName) agent") }
    foreach ($d in $dashboards) { [void]$diagram.Add("    class $($d.SafeName) dashboard") }
    foreach ($t in $trayApps) { [void]$diagram.Add("    class $($t.SafeName) tray") }
    foreach ($l in $libraries) { [void]$diagram.Add("    class $($l.SafeName) library") }
    
    return ($diagram -join "`n")
}

function New-ExecutionFlowDiagram {
    <#
    .SYNOPSIS
        Generates a Mermaid flowchart showing method execution flows.
    #>
    param(
        [hashtable]$Classes,
        [hashtable]$MethodBodies,
        [int]$MaxMethods = 20
    )
    
    Write-CSharpMmdExecFlow "flowchart TD"
    
    # Group classes by project/entry points
    $entryPoints = @()
    $serviceClasses = @()
    
    foreach ($classKey in $Classes.Keys) {
        $class = $Classes[$classKey]
        $className = $class.Name
        
        # Identify entry points and important classes
        if ($className -match 'Program|Startup|Main|App|Service|Controller|Handler') {
            $entryPoints += $class
        }
        elseif ($class.Methods.Count -gt 0) {
            $serviceClasses += $class
        }
    }
    
    # Start with a main entry point
    Write-CSharpMmdExecFlow "    Start([🚀 Application Start])"
    
    $processedMethods = 0
    $nodeConnections = @()
    $lastNodeId = "Start"
    
    # Process entry point classes first
    foreach ($class in ($entryPoints | Select-Object -First 5)) {
        $safeClassName = $class.Name -replace '[^a-zA-Z0-9]', '_'
        
        Write-CSharpMmdExecFlow "    subgraph ${safeClassName}[`"📦 $($class.Name)`"]"
        
        foreach ($method in ($class.Methods | Select-Object -First 5)) {
            if ($processedMethods -ge $MaxMethods) { break }
            
            $safeMethodName = $method.Name -replace '[^a-zA-Z0-9]', '_'
            $nodeId = "${safeClassName}_${safeMethodName}"
            
            # Check for async methods
            $methodShape = if ($method.Name -match 'Async$') { "([`"⚡ $($method.Name)`"])" } else { "[`"$($method.Name)`"]" }
            
            Write-CSharpMmdExecFlow "        $nodeId$methodShape"
            
            # Check method body for calls
            $bodyKey = "$($class.FullName).$($method.Name)"
            if ($MethodBodies.ContainsKey($bodyKey)) {
                $body = $MethodBodies[$bodyKey]
                
                # Find if/else
                if ($body -match 'if\s*\(') {
                    $condNodeId = "${nodeId}_cond"
                    Write-CSharpMmdExecFlow "        $condNodeId{`"❓ Condition`"}"
                    $nodeConnections += "$nodeId --> $condNodeId"
                }
                
                # Find try/catch
                if ($body -match 'try\s*\{') {
                    $tryNodeId = "${nodeId}_try"
                    Write-CSharpMmdExecFlow "        $tryNodeId[/`"🛡️ Try-Catch`"/]"
                    $nodeConnections += "$nodeId --> $tryNodeId"
                }
            }
            
            # Check for SQL statements in method
            if ($method.SqlStatements -and $method.SqlStatements.Count -gt 0) {
                $supportedSqlExpressions = @("SELECT", "UPDATE", "INSERT", "DELETE", "FETCH", "CALL")
                foreach ($sqlStmt in $method.SqlStatements) {
                    if ($supportedSqlExpressions -contains $sqlStmt.Operation -and $sqlStmt.Tables.Count -gt 0) {
                        $tableCounter = 0
                        foreach ($sqlTable in $sqlStmt.Tables) {
                            $tableCounter++
                            $statementText = $sqlStmt.Operation.ToLower()
                            
                            # Handle multiple tables (JOINs, subqueries)
                            if ($tableCounter -gt 1) {
                                if ($sqlStmt.Operation -eq "UPDATE" -or $sqlStmt.Operation -eq "INSERT" -or $sqlStmt.Operation -eq "DELETE") {
                                    $statementText = "Sub-select related to " + $sqlStmt.Tables[0].Trim()
                                }
                                if ($sqlStmt.Operation -eq "SELECT") {
                                    $statementText = "Join or Sub-select related to " + $sqlStmt.Tables[0].Trim()
                                }
                            }
                            # Add field names for UPDATE statements (primary table only)
                            elseif ($sqlStmt.Operation -eq "UPDATE" -and $sqlStmt.Fields -and $sqlStmt.Fields.Count -gt 0) {
                                $fieldList = $sqlStmt.Fields -join ", "
                                $statementText = "update [$($fieldList)]"
                            }
                            
                            # Create SQL table node connection (same format as COBOL)
                            $sqlNodeId = "sql_" + $sqlTable.Replace(".", "_").Trim()
                            $statement = "        $nodeId--`"$statementText`"-->$sqlNodeId[(" + $sqlTable.Trim() + ")]"
                            Write-CSharpMmdExecFlow $statement
                        }
                    }
                }
            }
            
            $nodeConnections += "$lastNodeId --> $nodeId"
            $lastNodeId = $nodeId
            $processedMethods++
        }
        
        Write-CSharpMmdExecFlow "    end"
    }
    
    # Process some service classes
    foreach ($class in ($serviceClasses | Select-Object -First 3)) {
        if ($processedMethods -ge $MaxMethods) { break }
        
        $safeClassName = $class.Name -replace '[^a-zA-Z0-9]', '_'
        
        Write-CSharpMmdExecFlow "    subgraph ${safeClassName}[`"🔧 $($class.Name)`"]"
        
        foreach ($method in ($class.Methods | Select-Object -First 3)) {
            if ($processedMethods -ge $MaxMethods) { break }
            
            $safeMethodName = $method.Name -replace '[^a-zA-Z0-9]', '_'
            $nodeId = "${safeClassName}_${safeMethodName}"
            
            Write-CSharpMmdExecFlow "        $nodeId[`"$($method.Name)`"]"
            
            # Check for SQL statements in method
            if ($method.SqlStatements -and $method.SqlStatements.Count -gt 0) {
                $supportedSqlExpressions = @("SELECT", "UPDATE", "INSERT", "DELETE", "FETCH", "CALL")
                foreach ($sqlStmt in $method.SqlStatements) {
                    if ($supportedSqlExpressions -contains $sqlStmt.Operation -and $sqlStmt.Tables.Count -gt 0) {
                        $tableCounter = 0
                        foreach ($sqlTable in $sqlStmt.Tables) {
                            $tableCounter++
                            $statementText = $sqlStmt.Operation.ToLower()
                            
                            # Handle multiple tables
                            if ($tableCounter -gt 1) {
                                if ($sqlStmt.Operation -eq "UPDATE" -or $sqlStmt.Operation -eq "INSERT" -or $sqlStmt.Operation -eq "DELETE") {
                                    $statementText = "Sub-select related to " + $sqlStmt.Tables[0].Trim()
                                }
                                if ($sqlStmt.Operation -eq "SELECT") {
                                    $statementText = "Join or Sub-select related to " + $sqlStmt.Tables[0].Trim()
                                }
                            }
                            # Add field names for UPDATE statements
                            elseif ($sqlStmt.Operation -eq "UPDATE" -and $sqlStmt.Fields -and $sqlStmt.Fields.Count -gt 0) {
                                $fieldList = $sqlStmt.Fields -join ", "
                                $statementText = "update [$($fieldList)]"
                            }
                            
                            # Create SQL table node connection
                            $sqlNodeId = "sql_" + $sqlTable.Replace(".", "_").Trim()
                            $statement = "        $nodeId--`"$statementText`"-->$sqlNodeId[(" + $sqlTable.Trim() + ")]"
                            Write-CSharpMmdExecFlow $statement
                        }
                    }
                }
            }
            
            $processedMethods++
        }
        
        Write-CSharpMmdExecFlow "    end"
    }
    
    # Add connections
    foreach ($conn in ($nodeConnections | Select-Object -First 30)) {
        Write-CSharpMmdExecFlow "    $conn"
    }
    
    # End node
    Write-CSharpMmdExecFlow "    End([🏁 End])"
    Write-CSharpMmdExecFlow "    $lastNodeId --> End"
}

function New-ClassDiagram {
    param(
        [hashtable]$Classes,
        [hashtable]$Interfaces,
        [string]$ProjectName = "",
        [int]$MaxClasses = 8  # Keep it small for readable diagrams
    )
    
    Write-CSharpMmdClass "classDiagram"
    
    # Get classes for this project, prioritize controllers and services
    $projectClasses = $Classes.Values | Where-Object {
        -not $ProjectName -or $_.ProjectName -eq $ProjectName
    }
    
    # Categorize classes by importance
    $controllers = $projectClasses | Where-Object { $_.Name -match 'Controller$' }
    $services = $projectClasses | Where-Object { $_.Name -match 'Service$|Manager$' -and $_.Name -notmatch 'Controller$' }
    $others = $projectClasses | Where-Object { $_.Name -notmatch 'Controller$|Service$|Manager$' }
    
    # Select top classes from each category
    $selectedClasses = @()
    $selectedClasses += $controllers | Sort-Object { $_.Methods.Count } -Descending | Select-Object -First 3
    $selectedClasses += $services | Sort-Object { $_.Methods.Count } -Descending | Select-Object -First 3
    $selectedClasses += $others | Sort-Object { $_.Methods.Count } -Descending | Select-Object -First 2
    $selectedClasses = $selectedClasses | Select-Object -First $MaxClasses
    
    $totalClasses = $projectClasses.Count
    
    # Only show interfaces that selected classes implement
    $usedInterfaces = @{}
    foreach ($class in $selectedClasses) {
        foreach ($iface in $class.Interfaces) {
            $usedInterfaces[$iface] = $true
        }
    }
    
    # Define interfaces (simple, no methods)
    foreach ($ifaceKey in $Interfaces.Keys) {
        $iface = $Interfaces[$ifaceKey]
        if ($ProjectName -and $iface.ProjectName -ne $ProjectName) { continue }
        if (-not $usedInterfaces.ContainsKey($iface.Name)) { continue }
        
        $safeName = $iface.Name -replace '[^a-zA-Z0-9]', '_'
        Write-CSharpMmdClass "    class $safeName"
    }
    
    # Define classes with limited methods (max 5 for readability)
    foreach ($class in $selectedClasses) {
        $safeName = $class.Name -replace '[^a-zA-Z0-9]', '_'
        Write-CSharpMmdClass "    class $safeName {"
        
        $methodCount = 0
        $maxMethodsToShow = 5
        foreach ($method in $class.Methods) {
            if ($methodCount -ge $maxMethodsToShow) {
                $remainingMethods = $class.Methods.Count - $maxMethodsToShow
                if ($remainingMethods -gt 0) {
                    Write-CSharpMmdClass "        +_more_$($remainingMethods)_methods()"
                }
                break
            }
            $methodSig = $method.Name -replace '[<>]', ''
            Write-CSharpMmdClass "        +$methodSig()"
            $methodCount++
        }
        
        Write-CSharpMmdClass "    }"
    }
    
    # Show only inheritance and interface implementation (skip "uses" dependencies for cleaner diagram)
    foreach ($class in $selectedClasses) {
        $safeName = $class.Name -replace '[^a-zA-Z0-9]', '_'
        
        if ($class.BaseClass -and $class.BaseClass -notin @('object', 'Object')) {
            $safeBase = $class.BaseClass -replace '[^a-zA-Z0-9]', '_'
            Write-CSharpMmdClass "    $safeBase <|-- $safeName : extends"
        }
        
        foreach ($iface in $class.Interfaces) {
            $safeIface = $iface -replace '[^a-zA-Z0-9]', '_'
            Write-CSharpMmdClass "    $safeIface <|.. $safeName : implements"
        }
    }
    
    # Add note showing total count
    if ($totalClasses -gt $MaxClasses) {
        $remainingClasses = $totalClasses - $selectedClasses.Count
        Write-CSharpMmdClass "    note `"$remainingClasses more classes not shown`""
    }
}

function New-ProjectInteractionDiagram {
    param(
        [hashtable]$Projects,
        [hashtable]$ProjectReferences
    )
    
    Write-CSharpMmdInteraction "flowchart TB"
    Write-CSharpMmdInteraction "    subgraph Solution"
    
    foreach ($projName in $Projects.Keys) {
        $safeName = $projName -replace '[^a-zA-Z0-9]', '_'
        Write-CSharpMmdInteraction "        ${safeName}[$projName]"
    }
    
    Write-CSharpMmdInteraction "    end"
    
    foreach ($projName in $ProjectReferences.Keys) {
        $safeName = $projName -replace '[^a-zA-Z0-9]', '_'
        $refs = $ProjectReferences[$projName]
        
        foreach ($ref in $refs) {
            $safeRef = $ref -replace '[^a-zA-Z0-9]', '_'
            Write-CSharpMmdInteraction "    $safeName --> $safeRef"
        }
    }
}

function New-NamespaceFlowDiagram {
    param(
        [hashtable]$Classes,
        [string]$ProjectName = ""
    )
    
    # Use TB layout for cleaner namespace visualization
    Write-CSharpMmdFlow "flowchart TB"
    
    $namespaces = @{}
    
    # Collect classes by namespace
    foreach ($classKey in $Classes.Keys) {
        $classItem = $Classes[$classKey]
        if ($ProjectName -and $classItem.ProjectName -ne $ProjectName) { continue }
        
        $ns = if ($classItem.Namespace) { $classItem.Namespace } else { "(global)" }
        
        if (-not $namespaces.ContainsKey($ns)) {
            $namespaces[$ns] = @{
                Classes = [System.Collections.ArrayList]::new()
                Controllers = 0
                Services = 0
                Other = 0
            }
        }
        [void]$namespaces[$ns].Classes.Add($classItem)
        
        # Categorize for summary
        if ($classItem.Name -match 'Controller$') {
            $namespaces[$ns].Controllers++
        } elseif ($classItem.Name -match 'Service$|Manager$') {
            $namespaces[$ns].Services++
        } else {
            $namespaces[$ns].Other++
        }
    }
    
    # Create a simple node for each namespace showing counts
    # Limit to top namespaces by class count for readability
    $sortedNamespaces = $namespaces.Keys | Sort-Object { $namespaces[$_].Classes.Count } -Descending | Select-Object -First 8
    
    foreach ($ns in $sortedNamespaces) {
        $safeNs = $ns -replace '[^a-zA-Z0-9]', '_'
        $nsData = $namespaces[$ns]
        $classCount = $nsData.Classes.Count
        
        # Create a readable label with class count breakdown
        $label = "$ns"
        $details = @()
        if ($nsData.Controllers -gt 0) { $details += "$($nsData.Controllers) Controllers" }
        if ($nsData.Services -gt 0) { $details += "$($nsData.Services) Services" }
        if ($nsData.Other -gt 0) { $details += "$($nsData.Other) Other" }
        $detailStr = $details -join ", "
        
        Write-CSharpMmdFlow "    $safeNs[`"📦 $label<br/>$detailStr`"]"
    }
    
    # Show remaining count if namespaces were truncated
    if ($namespaces.Count -gt 8) {
        $remaining = $namespaces.Count - 8
        Write-CSharpMmdFlow "    more[`"... and $remaining more namespaces`"]"
    }
}

#endregion

#region Main Function

function Start-CSharpParse {
    <#
    .SYNOPSIS
        Main entry point for C# solution/project parsing.
    .DESCRIPTION
        Parses C# solutions and projects to generate class diagrams, 
        project interaction diagrams, and namespace flow diagrams.
    .PARAMETER SourceFolder
        Path to the solution or project folder.
    .PARAMETER SolutionFile
        Optional: specific .sln file to parse.
    .PARAMETER OutputFolder
        Folder to write generated HTML files.
    .PARAMETER ClientSideRender
        Always uses client-side Mermaid.js rendering (default).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFolder,
        
        [string]$SolutionFile = "",
        [string]$OutputFolder = "",
        [string]$TmpRootFolder = "",
        [string]$SrcRootFolder = "",
        [switch]$ClientSideRender,
        [switch]$CleanUp,
        [int]$ThreadId = 0
    )
    
    Initialize-CSharpParseVariables
    
    if (-not (Test-Path $SourceFolder)) {
        Write-LogMessage "Source folder not found: $SourceFolder" -Level ERROR
        return $null
    }
    
    if (-not $OutputFolder) { $OutputFolder = "$env:OptPath\Webs\AutoDoc" }
    if (-not $TmpRootFolder) { $TmpRootFolder = "$env:OptPath\data\AutoDoc\tmp" }
    
    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }
    
    Write-LogMessage "Starting C# parser for: $SourceFolder" -Level INFO
    
    $StartTime = Get-Date
    
    # Find solution files
    $solutionFiles = @()
    if ($SolutionFile -and (Test-Path $SolutionFile)) {
        $solutionFiles += Get-Item $SolutionFile
    }
    else {
        $solutionFiles = Get-ChildItem -Path $SourceFolder -Filter "*.sln" -Recurse | Select-Object -First 5
    }
    
    $solutionName = if ($solutionFiles.Count -gt 0) { 
        [System.IO.Path]::GetFileNameWithoutExtension($solutionFiles[0].Name) 
    }
    else { 
        Split-Path $SourceFolder -Leaf 
    }
    
    Write-LogMessage "Found $($solutionFiles.Count) solution file(s)" -Level INFO
    
    # Parse all projects
    $allProjects = @{}
    $allProjectRefs = @{}
    
    foreach ($slnFile in $solutionFiles) {
        Write-LogMessage "Parsing solution: $($slnFile.Name)" -Level INFO
        $projects = Get-SolutionProjects -SolutionPath $slnFile.FullName
        
        foreach ($proj in $projects) {
            $projRefs = Get-ProjectReferences -ProjectPath $proj.Path
            
            $allProjects[$proj.Name] = @{
                Name              = $proj.Name
                Path              = $proj.Path
                TargetFramework   = $projRefs.TargetFramework
                RootNamespace     = $projRefs.RootNamespace
                PackageReferences = $projRefs.PackageReferences
            }
            
            $allProjectRefs[$proj.Name] = $projRefs.ProjectReferences
        }
    }
    
    # Fallback to .csproj files if no solution found
    if ($allProjects.Count -eq 0) {
        $csprojFiles = Get-ChildItem -Path $SourceFolder -Filter "*.csproj" -Recurse | Where-Object {
            $_.DirectoryName -notmatch '\\(bin|obj|packages)[\\/]'
        }
        
        foreach ($csproj in $csprojFiles) {
            $projName = [System.IO.Path]::GetFileNameWithoutExtension($csproj.Name)
            $projRefs = Get-ProjectReferences -ProjectPath $csproj.FullName
            
            $allProjects[$projName] = @{
                Name              = $projName
                Path              = $csproj.FullName
                TargetFramework   = $projRefs.TargetFramework
                RootNamespace     = $projRefs.RootNamespace
                PackageReferences = $projRefs.PackageReferences
            }
            
            $allProjectRefs[$projName] = $projRefs.ProjectReferences
        }
    }
    
    Write-LogMessage "Total projects found: $($allProjects.Count)" -Level INFO
    
    # Parse all C# files
    $allClasses = @{}
    $allInterfaces = @{}
    $totalMethods = 0
    
    foreach ($projName in $allProjects.Keys) {
        $proj = $allProjects[$projName]
        $projDir = Split-Path $proj.Path -Parent
        
        $csFiles = Get-CSharpFiles -FolderPath $projDir
        
        foreach ($csFile in $csFiles) {
            $parsed = Read-CSharpFile -FilePath $csFile.FullName -ProjectName $projName
            
            foreach ($class in $parsed.Classes) {
                $key = $class.FullName
                if (-not $allClasses.ContainsKey($key)) {
                    $allClasses[$key] = $class
                    $totalMethods += $class.Methods.Count
                }
            }
            
            foreach ($iface in $parsed.Interfaces) {
                $key = $iface.FullName
                if (-not $allInterfaces.ContainsKey($key)) {
                    $allInterfaces[$key] = $iface
                }
            }
        }
    }
    
    Write-LogMessage "Total classes: $($allClasses.Count), interfaces: $($allInterfaces.Count), methods: $totalMethods" -Level INFO
    
    # Extract method bodies for flow analysis
    $methodBodies = @{}
    foreach ($projName in $allProjects.Keys) {
        $proj = $allProjects[$projName]
        $projDir = Split-Path $proj.Path -Parent
        $csFiles = Get-CSharpFiles -FolderPath $projDir
        
        foreach ($csFile in $csFiles) {
            $content = Get-Content $csFile.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            
            foreach ($classKey in $allClasses.Keys) {
                $class = $allClasses[$classKey]
                if ($class.FilePath -ne $csFile.FullName) { continue }
                
                foreach ($method in $class.Methods) {
                    $body = Get-MethodBody -Content $content -MethodName $method.Name
                    if ($body) {
                        $key = "$($class.FullName).$($method.Name)"
                        $methodBodies[$key] = $body
                        
                        # Scan method body for SQL statements
                        $sqlStatements = ScanCSharpMethodForSql -MethodBody $body -MethodName $method.Name -ClassName $class.Name
                        if ($sqlStatements -and $sqlStatements.Count -gt 0) {
                            # Ensure SqlStatements property exists
                            if (-not $method.SqlStatements) {
                                $method.SqlStatements = @()
                            }
                            $method.SqlStatements = $sqlStatements
                            
                            # Track SQL tables for "Uses SQL" checkbox
                            if (-not $script:sqlTableArray) {
                                $script:sqlTableArray = @()
                            }
                            foreach ($sqlStmt in $sqlStatements) {
                                foreach ($table in $sqlStmt.Tables) {
                                    if (-not $script:sqlTableArray.Contains($table)) {
                                        $script:sqlTableArray += $table
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    Write-LogMessage "Extracted $($methodBodies.Count) method bodies for flow analysis" -Level INFO
    
    # Generate diagrams
    New-ClassDiagram -Classes $allClasses -Interfaces $allInterfaces
    
    if ($allProjects.Count -gt 1) {
        New-ProjectInteractionDiagram -Projects $allProjects -ProjectReferences $allProjectRefs
    }
    else {
        Write-CSharpMmdInteraction "flowchart LR"
        Write-CSharpMmdInteraction "    A[Single Project]"
    }
    
    New-NamespaceFlowDiagram -Classes $allClasses
    New-ExecutionFlowDiagram -Classes $allClasses -MethodBodies $methodBodies
    
    # Generate ecosystem diagram for multi-project solutions
    if ($allProjects.Count -gt 1) {
        Write-LogMessage "Analyzing inter-project communication patterns..." -Level INFO
        $communications = Get-ProjectCommunication -Projects $allProjects -SourceFolder $SourceFolder
        Write-LogMessage "Found $($communications.Count) communication patterns" -Level INFO
        
        $script:mmdEcosystemContent = New-EcosystemDiagram -Projects $allProjects -ProjectReferences $allProjectRefs `
            -Communications $communications -SolutionName $solutionName
    }
    else {
        $script:mmdEcosystemContent = @"
flowchart LR
    Single[📦 Single Project Solution]
    Note[This solution contains only one project]
    Single --- Note
"@
    }
    
    # Use template from OutputFolder\_templates (copied at startup by AutoDocBatchRunner)
    $templatesFolder = Join-Path $OutputFolder "_templates"
    $templatePath = Join-Path $templatesFolder "csharpmmdtemplate.html"
    if (-not (Test-Path $templatePath)) {
        # Fallback to embedded template
        Write-LogMessage "Template file not found at $templatePath, using embedded template" -Level WARN
        $template = Get-CSharpHtmlTemplate
    }
    else {
        $template = Get-Content $templatePath -Raw -Encoding UTF8
    }
    
    # Keep standard Mermaid <<stereotype>> syntax - Mermaid 11 handles it correctly
    $classDiagramContent = $script:mmdClassContent -join "`n"
    
    $projectDiagramContent = $script:mmdInteractionContent -join "`n"
    $namespaceDiagramContent = $script:mmdFlowContent -join "`n"
    $flowDiagramContent = $script:mmdExecutionFlowContent -join "`n"
    $ecosystemDiagramContent = $script:mmdEcosystemContent
    
    $classListHtml = New-ClassListHtml -Classes $allClasses
    $projectListHtml = New-ProjectListHtml -Projects $allProjects
    $namespaceListHtml = New-NamespaceListHtml -Classes $allClasses
    
    $targetFramework = ($allProjects.Values | Select-Object -First 1).TargetFramework
    if (-not $targetFramework) { $targetFramework = "Unknown" }
    
    # Apply shared CSS and common URL replacements
    $html = Set-AutodocTemplate -Template $template -OutputFolder $OutputFolder
    
    # Generate SQL information
    $htmlUseSql = ""
    $sqlTablesHtml = ""
    $sqlTablesStyle = "display: none;"
    if ($script:sqlTableArray -and $script:sqlTableArray.Count -gt 0) {
        $htmlUseSql = "checked"
        $sqlTablesStyle = ""
        $sqlTablesHtml = "<ul style='list-style-type: none; padding-left: 0;'>"
        foreach ($table in ($script:sqlTableArray | Sort-Object -Unique)) {
            $tableLink = $table.Replace(".", "_").ToLower() + ".sql.html"
            $sqlTablesHtml += "<li style='margin-bottom: 0.25rem;'><a href='./$tableLink' target='_blank' style='text-decoration: none; color: var(--text-primary);'>$table</a></li>"
        }
        $sqlTablesHtml += "</ul>"
    }
    else {
        $sqlTablesHtml = "<span style='color: var(--text-secondary); font-style: italic;'>No SQL tables detected</span>"
    }
    
    # Page-specific replacements
    $html = $html.Replace("[title]", $solutionName)
    $html = $html.Replace("[solutionname]", $solutionName)
    $html = $html.Replace("[targetframework]", $targetFramework)
    $html = $html.Replace("[generationdate]", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
    $html = $html.Replace("[projectcount]", $allProjects.Count.ToString())
    $html = $html.Replace("[classcount]", $allClasses.Count.ToString())
    $html = $html.Replace("[interfacecount]", $allInterfaces.Count.ToString())
    $html = $html.Replace("[methodcount]", $totalMethods.ToString())
    $html = $html.Replace("[usesql]", $htmlUseSql)
    $html = $html.Replace("[sqltables]", $sqlTablesHtml)
    $html = $html.Replace("[sqltablesstyle]", $sqlTablesStyle)
    $html = $html.Replace("[flowdiagram]", $flowDiagramContent)
    $html = $html.Replace("[classdiagram]", $classDiagramContent)
    $html = $html.Replace("[projectdiagram]", $projectDiagramContent)
    $html = $html.Replace("[namespacediagram]", $namespaceDiagramContent)
    $html = $html.Replace("[ecosystemdiagram]", $ecosystemDiagramContent)
    $html = $html.Replace("[classlist]", $classListHtml)
    $html = $html.Replace("[projectlist]", $projectListHtml)
    $html = $html.Replace("[namespacelist]", $namespaceListHtml)
    
    # Collect REST endpoints from controller classes
    $restEndpoints = @()
    foreach ($classKey in $allClasses.Keys) {
        $class = $allClasses[$classKey]
        # Detect controller classes by base class or attribute
        if ($class.BaseClass -match 'Controller|ControllerBase' -or $class.Attributes -match 'ApiController') {
            if ($class.RestEndpoints -and $class.RestEndpoints.Count -gt 0) {
                foreach ($endpoint in $class.RestEndpoints) {
                    $restEndpoints += @{
                        Controller = $class.Name
                        HttpVerb   = $endpoint.HttpVerb
                        Route      = $endpoint.FullRoute
                        MethodName = $endpoint.MethodName
                    }
                }
            }
        }
    }
    
    # Get API configuration from appsettings.json and launchSettings.json
    $apiConfig = Get-CSharpApiConfiguration -ProjectFolder $SourceFolder
    Write-LogMessage "Found API configuration: $($apiConfig.Ports.Count) ports, $($apiConfig.BaseUrls.Count) base URLs" -Level INFO
    
    # Find external callers (PS1, BAT, CBL files) that call this API
    $externalCallers = @()
    if ($SrcRootFolder -and (Test-Path $SrcRootFolder) -and $apiConfig.Ports.Count -gt 0) {
        $externalCallers = Find-ExternalApiCallers -SrcRootFolder $SrcRootFolder -ApiPorts $apiConfig.Ports -RestEndpoints $restEndpoints -OutputFolder $OutputFolder
        Write-LogMessage "Found $($externalCallers.Count) external API callers" -Level INFO
    }
    
    # Generate REST API diagram (with external callers)
    # Use TB (top-to-bottom) layout for better horizontal text space with long endpoint names
    $restDiagramContent = ""
    if ($restEndpoints.Count -gt 0 -or $externalCallers.Count -gt 0) {
        $restDiagramContent = "flowchart TB`n"
        
        # Add external callers on the left side
        if ($externalCallers.Count -gt 0) {
            $restDiagramContent += "    subgraph CALLERS[`"📞 External API Callers`"]`n"
            $callerCounter = 0
            $uniqueCallers = $externalCallers | Sort-Object -Property FileName -Unique
            foreach ($caller in $uniqueCallers) {
                $callerCounter++
                $callerNodeId = "caller$callerCounter"
                $callerIcon = switch ($caller.FileType) {
                    "PowerShell" { "🔵" }
                    "Batch" { "🟤" }
                    "COBOL" { "🟣" }
                    default { "⚪" }
                }
                $safeFileName = $caller.FileName -replace '[^a-zA-Z0-9\.]', '_'
                $restDiagramContent += "        $callerNodeId[`"$callerIcon $($caller.FileName)`"]`n"
                $restDiagramContent += "        click $callerNodeId `"$($caller.HtmlLink)`" `"Open $($caller.FileName) documentation`"`n"
            }
            $restDiagramContent += "    end`n"
        }
        
        # Add API endpoints
        if ($restEndpoints.Count -gt 0) {
            $restDiagramContent += "    subgraph API[`"🌐 REST API Endpoints`"]`n"
            $controllerGroups = $restEndpoints | Group-Object -Property Controller
            foreach ($group in $controllerGroups) {
                $controllerName = $group.Name
                $safeName = $controllerName -replace '[^a-zA-Z0-9]', '_'
                $restDiagramContent += "        subgraph $safeName[`"📦 $controllerName`"]`n"
                foreach ($endpoint in $group.Group) {
                    $endpointId = "$($safeName)_$($endpoint.MethodName)"
                    $verbIcon = switch ($endpoint.HttpVerb) {
                        "GET" { "🟢" }
                        "POST" { "🟡" }
                        "PUT" { "🟠" }
                        "DELETE" { "🔴" }
                        default { "⚪" }
                    }
                    $route = if ($endpoint.Route) { $endpoint.Route } else { "/$($endpoint.MethodName.ToLower())" }
                    $restDiagramContent += "            $endpointId[`"$verbIcon $($endpoint.HttpVerb) $route`"]`n"
                }
                $restDiagramContent += "        end`n"
            }
            $restDiagramContent += "    end`n"
        }
        
        # Add edges from callers to endpoints they use
        if ($externalCallers.Count -gt 0 -and $restEndpoints.Count -gt 0) {
            $callerCounter = 0
            $uniqueCallers = $externalCallers | Sort-Object -Property FileName -Unique
            foreach ($caller in $uniqueCallers) {
                $callerCounter++
                $callerNodeId = "caller$callerCounter"
                
                if ($caller.MatchedEndpoints -and $caller.MatchedEndpoints.Count -gt 0) {
                    # Link to specific matched endpoints
                    foreach ($matchedEndpoint in $caller.MatchedEndpoints) {
                        $controllerSafe = $matchedEndpoint.Controller -replace '[^a-zA-Z0-9]', '_'
                        $endpointId = "$($controllerSafe)_$($matchedEndpoint.MethodName)"
                        $restDiagramContent += "    $callerNodeId --`"$($matchedEndpoint.HttpVerb)`"--> $endpointId`n"
                    }
                }
                else {
                    # Generic link to first controller if no specific match
                    $firstController = $controllerGroups | Select-Object -First 1
                    if ($firstController) {
                        $firstControllerSafe = $firstController.Name -replace '[^a-zA-Z0-9]', '_'
                        $restDiagramContent += "    $callerNodeId -.-> $firstControllerSafe`n"
                    }
                }
            }
        }
    }
    else {
        $restDiagramContent = "flowchart LR`n    NoAPI[`"No REST API endpoints detected`"]"
    }
    
    # Generate REST endpoint list HTML (with caller information)
    $restEndpointListHtml = ""
    if ($restEndpoints.Count -gt 0) {
        $restEndpointListHtml = "<table class='detail-table'><tr><th>Verb</th><th>Route</th><th>Controller</th><th>Method</th><th>Callers</th></tr>"
        foreach ($endpoint in $restEndpoints) {
            # Find callers that match this specific endpoint
            $matchingCallers = $externalCallers | Where-Object { 
                $_.MatchedEndpoints | Where-Object { $_.MethodName -eq $endpoint.MethodName -and $_.Controller -eq $endpoint.Controller }
            }
            $callerLinks = ""
            if ($matchingCallers) {
                $callerLinks = ($matchingCallers | ForEach-Object { 
                        "<a href='$($_.HtmlLink)' title='$($_.FilePath)'>$($_.FileName)</a>" 
                    }) -join ", "
            }
            else {
                $callerLinks = "<span class='text-muted'>-</span>"
            }
            $restEndpointListHtml += "<tr><td><strong>$($endpoint.HttpVerb)</strong></td><td><code>$($endpoint.Route)</code></td><td>$($endpoint.Controller)</td><td>$($endpoint.MethodName)</td><td>$callerLinks</td></tr>"
        }
        $restEndpointListHtml += "</table>"
    }
    else {
        $restEndpointListHtml = "<p>No REST API endpoints detected</p>"
    }
    
    # Generate port list HTML (from appsettings.json and launchSettings.json)
    if ($apiConfig.Ports.Count -gt 0 -or $apiConfig.BaseUrls.Count -gt 0) {
        $portListHtml = "<table class='detail-table'><tr><th>Type</th><th>Value</th></tr>"
        foreach ($port in $apiConfig.Ports) {
            $portListHtml += "<tr><td><strong>Port</strong></td><td><code>$port</code></td></tr>"
        }
        foreach ($url in $apiConfig.BaseUrls) {
            $portListHtml += "<tr><td><strong>URL</strong></td><td><code>$url</code></td></tr>"
        }
        $portListHtml += "</table>"
    }
    else {
        $portListHtml = "<p>No ports configured in launchSettings.json or appsettings.json</p>"
    }
    
    # Detect external process invocations
    $csFiles = Get-ChildItem -Path $SourceFolder -Filter "*.cs" -Recurse -File | 
    Where-Object { $_.DirectoryName -notmatch '\\(bin|obj|node_modules|\.git)\\' } |
    Select-Object -ExpandProperty FullName
    $processInvocations = Get-CSharpProcessInvocations -CsFiles $csFiles
    $processDiagramContent = New-CSharpProcessDiagram -SolutionName $solutionName -ProcessInvocations $processInvocations
    Write-LogMessage "Detected $($processInvocations.Count) external process invocations" -Level INFO
    
    # Hide process tab if no process invocations detected
    $hasProcessInvocations = $processInvocations -and $processInvocations.Count -gt 0
    $processTabStyle = if ($hasProcessInvocations) { "" } else { "display: none;" }
    $processContentStyle = if ($hasProcessInvocations) { "" } else { "display: none;" }
    
    $html = $html.Replace("[processdiagram]", $processDiagramContent)
    $html = $html.Replace("[processtabstyle]", $processTabStyle)
    $html = $html.Replace("[processcontentstyle]", $processContentStyle)
    $html = $html.Replace("[restdiagram]", $restDiagramContent)
    $html = $html.Replace("[restendpointcount]", $restEndpoints.Count.ToString())
    $html = $html.Replace("[restendpointlist]", $restEndpointListHtml)
    $html = $html.Replace("[portlist]", $portListHtml)
    
    $outputFileName = "$solutionName.csharp.html"
    $outputPath = Join-Path $OutputFolder $outputFileName
    $html | Set-Content -Path $outputPath -Encoding UTF8
    
    $EndTime = Get-Date
    $Duration = [math]::Round(($EndTime - $StartTime).TotalSeconds)
    
    Write-LogMessage "Generated: $outputPath" -Level INFO
    Write-LogMessage "C# parser completed: $solutionName ($Duration seconds)" -Level INFO
    
    return $outputPath
}

function Start-CSharpEcosystemParse {
    <#
    .SYNOPSIS
        Parses an entire folder containing multiple C# projects/solutions as a unified ecosystem.
    .DESCRIPTION
        Scans all .csproj files in the folder tree, analyzes their relationships,
        and generates a comprehensive ecosystem diagram showing all projects and their interactions.
    .PARAMETER RootFolder
        The root folder containing multiple C# projects (e.g., $env:OptPath\src\ServerMonitor)
    .PARAMETER OutputFolder
        Where to write the generated HTML file.
    .PARAMETER EcosystemName
        Name of the ecosystem (defaults to folder name)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootFolder,
        
        [string]$OutputFolder = "",
        [string]$TmpRootFolder = "",
        [string]$SrcRootFolder = "",
        [string]$EcosystemName = ""
    )
    
    Initialize-CSharpParseVariables
    
    if (-not (Test-Path $RootFolder)) {
        Write-LogMessage "Root folder not found: $RootFolder" -Level ERROR
        return $null
    }
    
    if (-not $OutputFolder) { $OutputFolder = "$env:OptPath\Webs\AutoDoc" }
    if (-not $TmpRootFolder) { $TmpRootFolder = "$env:OptPath\data\AutoDoc\tmp" }
    if (-not $EcosystemName) { $EcosystemName = Split-Path $RootFolder -Leaf }
    
    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }
    
    Write-LogMessage "Starting C# ecosystem parse for: $RootFolder" -Level INFO
    $StartTime = Get-Date
    
    # Discover ALL projects in the folder tree
    $discovery = Get-AllProjectsInFolder -RootFolder $RootFolder
    $allProjects = $discovery.Projects
    $allProjectRefs = $discovery.ProjectReferences
    
    if ($allProjects.Count -eq 0) {
        Write-LogMessage "No C# projects found in $RootFolder" -Level WARN
        return $null
    }
    
    Write-LogMessage "Discovered $($allProjects.Count) projects in ecosystem" -Level INFO
    
    # Parse all C# files from all projects
    $allClasses = @{}
    $allInterfaces = @{}
    $totalMethods = 0
    
    foreach ($projName in $allProjects.Keys) {
        $proj = $allProjects[$projName]
        $projDir = Split-Path $proj.Path -Parent
        
        $csFiles = Get-CSharpFiles -FolderPath $projDir
        
        foreach ($csFile in $csFiles) {
            $parsed = Read-CSharpFile -FilePath $csFile.FullName -ProjectName $projName
            
            foreach ($class in $parsed.Classes) {
                $key = $class.FullName
                if (-not $allClasses.ContainsKey($key)) {
                    $allClasses[$key] = $class
                    $totalMethods += $class.Methods.Count
                }
            }
            
            foreach ($iface in $parsed.Interfaces) {
                $key = $iface.FullName
                if (-not $allInterfaces.ContainsKey($key)) {
                    $allInterfaces[$key] = $iface
                }
            }
        }
    }
    
    Write-LogMessage "Parsed $($allClasses.Count) classes, $($allInterfaces.Count) interfaces, $totalMethods methods" -Level INFO
    
    # Extract method bodies for flow analysis
    $methodBodies = @{}
    foreach ($projName in $allProjects.Keys) {
        $proj = $allProjects[$projName]
        $projDir = Split-Path $proj.Path -Parent
        $csFiles = Get-CSharpFiles -FolderPath $projDir
        
        foreach ($csFile in $csFiles) {
            $content = Get-Content $csFile.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            
            foreach ($classKey in $allClasses.Keys) {
                $class = $allClasses[$classKey]
                if ($class.FilePath -ne $csFile.FullName) { continue }
                
                foreach ($method in $class.Methods) {
                    $body = Get-MethodBody -Content $content -MethodName $method.Name
                    if ($body) {
                        $key = "$($class.FullName).$($method.Name)"
                        $methodBodies[$key] = $body
                        
                        # Scan method body for SQL statements
                        $sqlStatements = ScanCSharpMethodForSql -MethodBody $body -MethodName $method.Name -ClassName $class.Name
                        if ($sqlStatements -and $sqlStatements.Count -gt 0) {
                            # Ensure SqlStatements property exists
                            if (-not $method.SqlStatements) {
                                $method.SqlStatements = @()
                            }
                            $method.SqlStatements = $sqlStatements
                            
                            # Track SQL tables for "Uses SQL" checkbox
                            if (-not $script:sqlTableArray) {
                                $script:sqlTableArray = @()
                            }
                            foreach ($sqlStmt in $sqlStatements) {
                                foreach ($table in $sqlStmt.Tables) {
                                    if (-not $script:sqlTableArray.Contains($table)) {
                                        $script:sqlTableArray += $table
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    Write-LogMessage "Extracted $($methodBodies.Count) method bodies" -Level INFO
    
    # Analyze communication patterns across all projects
    Write-LogMessage "Analyzing cross-project communication patterns..." -Level INFO
    $communications = Get-ProjectCommunication -Projects $allProjects -SourceFolder $RootFolder
    Write-LogMessage "Found $($communications.Count) communication patterns" -Level INFO
    
    # Generate all diagrams
    New-ClassDiagram -Classes $allClasses -Interfaces $allInterfaces
    New-ProjectInteractionDiagram -Projects $allProjects -ProjectReferences $allProjectRefs
    New-NamespaceFlowDiagram -Classes $allClasses
    New-ExecutionFlowDiagram -Classes $allClasses -MethodBodies $methodBodies
    
    # Generate the comprehensive ecosystem diagram
    $script:mmdEcosystemContent = New-FullEcosystemDiagram -Projects $allProjects -ProjectReferences $allProjectRefs `
        -Communications $communications -EcosystemName $EcosystemName
    
    # Use template from OutputFolder\_templates (copied at startup by AutoDocBatchRunner)
    $templatesFolder = Join-Path $OutputFolder "_templates"
    $templatePath = Join-Path $templatesFolder "csharpmmdtemplate.html"
    if (-not (Test-Path $templatePath)) {
        Write-LogMessage "Template file not found at $templatePath, using embedded template" -Level WARN
        $template = Get-CSharpHtmlTemplate
    }
    else {
        $template = Get-Content $templatePath -Raw -Encoding UTF8
    }
    
    # Keep standard Mermaid <<stereotype>> syntax - Mermaid 11 handles it correctly
    $classDiagramContent = $script:mmdClassContent -join "`n"
    
    $projectDiagramContent = $script:mmdInteractionContent -join "`n"
    $namespaceDiagramContent = $script:mmdFlowContent -join "`n"
    $flowDiagramContent = $script:mmdExecutionFlowContent -join "`n"
    $ecosystemDiagramContent = $script:mmdEcosystemContent
    
    $classListHtml = New-ClassListHtml -Classes $allClasses
    $projectListHtml = New-ProjectListHtml -Projects $allProjects
    $namespaceListHtml = New-NamespaceListHtml -Classes $allClasses
    
    # Get most common framework
    $frameworks = $allProjects.Values | ForEach-Object { $_.TargetFramework } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending
    $primaryFramework = if ($frameworks.Count -gt 0) { $frameworks[0].Name } else { "Various" }
    
    # Apply shared CSS and common URL replacements
    $html = Set-AutodocTemplate -Template $template -OutputFolder $OutputFolder
    
    # Page-specific replacements
    # Generate SQL information for ecosystem
    $htmlUseSqlEco = ""
    $sqlTablesHtmlEco = ""
    $sqlTablesStyleEco = "display: none;"
    if ($script:sqlTableArray -and $script:sqlTableArray.Count -gt 0) {
        $htmlUseSqlEco = "checked"
        $sqlTablesStyleEco = ""
        $sqlTablesHtmlEco = "<ul style='list-style-type: none; padding-left: 0;'>"
        foreach ($table in ($script:sqlTableArray | Sort-Object -Unique)) {
            $tableLink = $table.Replace(".", "_").ToLower() + ".sql.html"
            $sqlTablesHtmlEco += "<li style='margin-bottom: 0.25rem;'><a href='./$tableLink' target='_blank' style='text-decoration: none; color: var(--text-primary);'>$table</a></li>"
        }
        $sqlTablesHtmlEco += "</ul>"
    }
    else {
        $sqlTablesHtmlEco = "<span style='color: var(--text-secondary); font-style: italic;'>No SQL tables detected</span>"
    }
    
    $html = $html.Replace("[title]", "$EcosystemName Ecosystem")
    $html = $html.Replace("[solutionname]", "$EcosystemName (Ecosystem)")
    $html = $html.Replace("[targetframework]", $primaryFramework)
    $html = $html.Replace("[generationdate]", (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
    $html = $html.Replace("[projectcount]", $allProjects.Count.ToString())
    $html = $html.Replace("[classcount]", $allClasses.Count.ToString())
    $html = $html.Replace("[interfacecount]", $allInterfaces.Count.ToString())
    $html = $html.Replace("[methodcount]", $totalMethods.ToString())
    $html = $html.Replace("[usesql]", $htmlUseSqlEco)
    $html = $html.Replace("[sqltables]", $sqlTablesHtmlEco)
    $html = $html.Replace("[sqltablesstyle]", $sqlTablesStyleEco)
    $html = $html.Replace("[flowdiagram]", $flowDiagramContent)
    $html = $html.Replace("[classdiagram]", $classDiagramContent)
    $html = $html.Replace("[projectdiagram]", $projectDiagramContent)
    $html = $html.Replace("[namespacediagram]", $namespaceDiagramContent)
    $html = $html.Replace("[ecosystemdiagram]", $ecosystemDiagramContent)
    $html = $html.Replace("[classlist]", $classListHtml)
    $html = $html.Replace("[projectlist]", $projectListHtml)
    $html = $html.Replace("[namespacelist]", $namespaceListHtml)
    
    # Collect REST endpoints from controller classes across all projects
    $restEndpoints = @()
    foreach ($classKey in $allClasses.Keys) {
        $class = $allClasses[$classKey]
        if ($class.BaseClass -match 'Controller|ControllerBase' -or $class.Attributes -match 'ApiController') {
            if ($class.RestEndpoints -and $class.RestEndpoints.Count -gt 0) {
                foreach ($endpoint in $class.RestEndpoints) {
                    $restEndpoints += @{
                        Controller = $class.Name
                        HttpVerb   = $endpoint.HttpVerb
                        Route      = $endpoint.FullRoute
                        MethodName = $endpoint.MethodName
                    }
                }
            }
        }
    }
    
    # Get API configuration from appsettings.json across all projects
    $apiConfig = Get-CSharpApiConfiguration -ProjectFolder $RootFolder
    Write-LogMessage "Ecosystem API config: $($apiConfig.Ports.Count) ports, $($apiConfig.BaseUrls.Count) base URLs" -Level INFO
    
    # Find external callers
    $externalCallers = @()
    if ($SrcRootFolder -and (Test-Path $SrcRootFolder) -and $apiConfig.Ports.Count -gt 0) {
        $externalCallers = Find-ExternalApiCallers -SrcRootFolder $SrcRootFolder -ApiPorts $apiConfig.Ports -RestEndpoints $restEndpoints -OutputFolder $OutputFolder
        Write-LogMessage "Found $($externalCallers.Count) external API callers" -Level INFO
    }
    
    # Generate REST API diagram (with external callers)
    # Use TB (top-to-bottom) layout for better horizontal text space with long endpoint names
    $restDiagramContent = ""
    if ($restEndpoints.Count -gt 0 -or $externalCallers.Count -gt 0) {
        $restDiagramContent = "flowchart TB`n"
        
        if ($externalCallers.Count -gt 0) {
            $restDiagramContent += "    subgraph CALLERS[`"📞 External API Callers`"]`n"
            $callerCounter = 0
            $uniqueCallers = $externalCallers | Sort-Object -Property FileName -Unique
            foreach ($caller in $uniqueCallers) {
                $callerCounter++
                $callerNodeId = "caller$callerCounter"
                $callerIcon = switch ($caller.FileType) {
                    "PowerShell" { "🔵" }
                    "Batch" { "🟤" }
                    "COBOL" { "🟣" }
                    default { "⚪" }
                }
                $restDiagramContent += "        $callerNodeId[`"$callerIcon $($caller.FileName)`"]`n"
                $restDiagramContent += "        click $callerNodeId `"$($caller.HtmlLink)`" `"Open documentation`"`n"
            }
            $restDiagramContent += "    end`n"
        }
        
        if ($restEndpoints.Count -gt 0) {
            $restDiagramContent += "    subgraph API[`"🌐 REST API Endpoints`"]`n"
            $controllerGroups = $restEndpoints | Group-Object -Property Controller
            foreach ($group in $controllerGroups) {
                $controllerName = $group.Name
                $safeName = $controllerName -replace '[^a-zA-Z0-9]', '_'
                $restDiagramContent += "        subgraph $safeName[`"📦 $controllerName`"]`n"
                foreach ($endpoint in $group.Group) {
                    $endpointId = "$($safeName)_$($endpoint.MethodName)"
                    $verbIcon = switch ($endpoint.HttpVerb) {
                        "GET" { "🟢" }
                        "POST" { "🟡" }
                        "PUT" { "🟠" }
                        "DELETE" { "🔴" }
                        default { "⚪" }
                    }
                    $route = if ($endpoint.Route) { $endpoint.Route } else { "/$($endpoint.MethodName.ToLower())" }
                    $restDiagramContent += "            $endpointId[`"$verbIcon $($endpoint.HttpVerb) $route`"]`n"
                }
                $restDiagramContent += "        end`n"
            }
            $restDiagramContent += "    end`n"
        }
        
        # Add edges from callers to endpoints
        if ($externalCallers.Count -gt 0 -and $restEndpoints.Count -gt 0) {
            $callerCounter = 0
            $uniqueCallers = $externalCallers | Sort-Object -Property FileName -Unique
            foreach ($caller in $uniqueCallers) {
                $callerCounter++
                $callerNodeId = "caller$callerCounter"
                if ($caller.MatchedEndpoints -and $caller.MatchedEndpoints.Count -gt 0) {
                    foreach ($matchedEndpoint in $caller.MatchedEndpoints) {
                        $controllerSafe = $matchedEndpoint.Controller -replace '[^a-zA-Z0-9]', '_'
                        $endpointId = "$($controllerSafe)_$($matchedEndpoint.MethodName)"
                        $restDiagramContent += "    $callerNodeId --`"HTTP`"--> $endpointId`n"
                    }
                }
                else {
                    $firstGroup = $restEndpoints | Group-Object -Property Controller | Select-Object -First 1
                    if ($firstGroup) {
                        $firstControllerSafe = $firstGroup.Name -replace '[^a-zA-Z0-9]', '_'
                        $restDiagramContent += "    $callerNodeId -.-> $firstControllerSafe`n"
                    }
                }
            }
        }
    }
    else {
        $restDiagramContent = "flowchart LR`n    NoAPI[`"No REST API endpoints detected`"]"
    }
    
    # Generate REST endpoint list HTML
    $restEndpointListHtml = ""
    if ($restEndpoints.Count -gt 0) {
        $restEndpointListHtml = "<table class='detail-table'><tr><th>Verb</th><th>Route</th><th>Controller</th><th>Method</th></tr>"
        foreach ($endpoint in $restEndpoints) {
            $restEndpointListHtml += "<tr><td><strong>$($endpoint.HttpVerb)</strong></td><td><code>$($endpoint.Route)</code></td><td>$($endpoint.Controller)</td><td>$($endpoint.MethodName)</td></tr>"
        }
        $restEndpointListHtml += "</table>"
    }
    else {
        $restEndpointListHtml = "<p>No REST API endpoints detected</p>"
    }
    
    # Generate port list HTML
    if ($apiConfig.Ports.Count -gt 0 -or $apiConfig.BaseUrls.Count -gt 0) {
        $portListHtml = "<table class='detail-table'><tr><th>Type</th><th>Value</th></tr>"
        foreach ($port in $apiConfig.Ports) {
            $portListHtml += "<tr><td><strong>Port</strong></td><td><code>$port</code></td></tr>"
        }
        foreach ($url in $apiConfig.BaseUrls) {
            $portListHtml += "<tr><td><strong>URL</strong></td><td><code>$url</code></td></tr>"
        }
        $portListHtml += "</table>"
    }
    else {
        $portListHtml = "<p>No ports configured in launchSettings.json or appsettings.json</p>"
    }
    
    # Generate Process Execution diagram
    $csFiles = Get-ChildItem -Path $RootFolder -Filter "*.cs" -Recurse -File |
    Where-Object { $_.DirectoryName -notmatch '\\(bin|obj|node_modules|\.git)\\' } |
    Select-Object -ExpandProperty FullName
    $processInvocations = Get-CSharpProcessInvocations -CsFiles $csFiles
    $processDiagramContent = New-CSharpProcessDiagram -SolutionName $EcosystemName -ProcessInvocations $processInvocations
    Write-LogMessage "Detected $($processInvocations.Count) external process invocations" -Level INFO
    
    # Hide process tab if no process invocations detected
    $hasProcessInvocations = $processInvocations -and $processInvocations.Count -gt 0
    $processTabStyle = if ($hasProcessInvocations) { "" } else { "display: none;" }
    $processContentStyle = if ($hasProcessInvocations) { "" } else { "display: none;" }
    
    $html = $html.Replace("[processdiagram]", $processDiagramContent)
    $html = $html.Replace("[processtabstyle]", $processTabStyle)
    $html = $html.Replace("[processcontentstyle]", $processContentStyle)
    $html = $html.Replace("[restdiagram]", $restDiagramContent)
    $html = $html.Replace("[restendpointcount]", $restEndpoints.Count.ToString())
    $html = $html.Replace("[restendpointlist]", $restEndpointListHtml)
    $html = $html.Replace("[portlist]", $portListHtml)
    
    $outputFileName = "$EcosystemName.ecosystem.csharp.html"
    $outputPath = Join-Path $OutputFolder $outputFileName
    $html | Set-Content -Path $outputPath -Encoding UTF8
    
    $EndTime = Get-Date
    $Duration = [math]::Round(($EndTime - $StartTime).TotalSeconds)
    
    Write-LogMessage "Generated ecosystem diagram: $outputPath" -Level INFO
    Write-LogMessage "C# ecosystem parse completed: $EcosystemName ($Duration seconds)" -Level INFO
    
    return $outputPath
}

function Get-CSharpHtmlTemplate {
    return @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>[projectname] - C# Documentation</title>
    <link rel="icon" href="[iconurl]" type="image/x-icon">
    <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
    <style>
        :root { --bg: #1a1a2e; --card: #16213e; --text: #e4e4e4; --accent: #0f3460; --highlight: #e94560; }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: 'Segoe UI', sans-serif; background: var(--bg); color: var(--text); padding: 20px; }
        .container { max-width: 1800px; margin: 0 auto; }
        header { background: linear-gradient(135deg, var(--accent), var(--card)); padding: 30px; border-radius: 12px; margin-bottom: 30px; }
        h1 { color: var(--highlight); font-size: 2rem; margin-bottom: 10px; }
        .meta-info { display: flex; gap: 30px; flex-wrap: wrap; font-size: 0.9rem; }
        .meta-label { color: var(--highlight); font-weight: 600; }
        .section { background: var(--card); border-radius: 12px; padding: 25px; margin-bottom: 25px; }
        .section h2 { color: var(--highlight); margin-bottom: 20px; }
        .diagram-container { background: #0d1117; border-radius: 8px; padding: 20px; overflow: auto; max-height: 800px; }
        .mermaid { display: flex; justify-content: center; }
        .controls { display: flex; gap: 10px; margin-bottom: 15px; }
        button { background: var(--accent); color: var(--text); border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; }
        button:hover { background: var(--highlight); }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
        .stat-card { background: var(--accent); padding: 20px; border-radius: 8px; text-align: center; }
        .stat-value { font-size: 2rem; color: var(--highlight); font-weight: bold; }
        .class-list { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 15px; }
        .class-card { background: var(--accent); padding: 15px; border-radius: 8px; border-left: 4px solid var(--highlight); }
        .class-name { font-weight: 600; color: var(--highlight); }
        .class-namespace { font-size: 0.8rem; opacity: 0.7; }
        .tabs { display: flex; gap: 5px; margin-bottom: 20px; }
        .tab { padding: 10px 20px; background: var(--accent); border: none; border-radius: 8px 8px 0 0; cursor: pointer; color: var(--text); }
        .tab.active { background: var(--highlight); }
        .tab-content { display: none; }
        .tab-content.active { display: block; }
        a { color: var(--highlight); text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="container">
        <a href="[autodochomepageurl]">← Back to AutoDoc</a>
        <header>
            <h1>📦 [projectname]</h1>
            <div class="meta-info">
                <div><span class="meta-label">Solution:</span> [solutionname]</div>
                <div><span class="meta-label">Framework:</span> [targetframework]</div>
                <div><span class="meta-label">Generated:</span> [generationdate]</div>
            </div>
        </header>
        <section class="section">
            <h2>📊 Statistics</h2>
            <div class="stats-grid">
                <div class="stat-card"><div class="stat-value">[projectcount]</div><div>Projects</div></div>
                <div class="stat-card"><div class="stat-value">[classcount]</div><div>Classes</div></div>
                <div class="stat-card"><div class="stat-value">[interfacecount]</div><div>Interfaces</div></div>
                <div class="stat-card"><div class="stat-value">[methodcount]</div><div>Methods</div></div>
            </div>
        </section>
        <section class="section">
            <h2>📈 Diagrams</h2>
            <div class="tabs">
                <button class="tab active" onclick="showTab('class-diagram')">Class Diagram</button>
                <button class="tab" onclick="showTab('project-diagram')">Projects</button>
                <button class="tab" onclick="showTab('namespace-diagram')">Namespaces</button>
            </div>
            <div id="class-diagram" class="tab-content active">
                <div class="controls">
                    <button onclick="zoom('classDiagram', 1.2)">🔍+</button>
                    <button onclick="zoom('classDiagram', 0.8)">🔍-</button>
                    <button onclick="zoom('classDiagram', 'reset')">📐</button>
                </div>
                <div class="diagram-container"><div class="mermaid" id="classDiagram">[classdiagram_content]</div></div>
            </div>
            <div id="project-diagram" class="tab-content">
                <div class="controls">
                    <button onclick="zoom('projectDiagram', 1.2)">🔍+</button>
                    <button onclick="zoom('projectDiagram', 0.8)">🔍-</button>
                </div>
                <div class="diagram-container"><div class="mermaid" id="projectDiagram">[projectdiagram_content]</div></div>
            </div>
            <div id="namespace-diagram" class="tab-content">
                <div class="controls">
                    <button onclick="zoom('namespaceDiagram', 1.2)">🔍+</button>
                    <button onclick="zoom('namespaceDiagram', 0.8)">🔍-</button>
                </div>
                <div class="diagram-container"><div class="mermaid" id="namespaceDiagram">[namespacediagram_content]</div></div>
            </div>
        </section>
        <section class="section">
            <h2>📚 Classes</h2>
            <div class="class-list">[classlist_content]</div>
        </section>
        <section class="section">
            <h2>🔗 Projects</h2>
            <div class="class-list">[relatedprojects_content]</div>
        </section>
    </div>
    <script>
        mermaid.initialize({ startOnLoad: true, theme: 'dark', securityLevel: 'loose', maxEdges: 2000 });
        const zoomLevels = {};
        function zoom(id, factor) {
            if (factor === 'reset') { zoomLevels[id] = 1; }
            else { zoomLevels[id] = (zoomLevels[id] || 1) * factor; }
            document.getElementById(id).style.transform = `scale(${zoomLevels[id]})`;
        }
        function showTab(id) {
            document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.getElementById(id).classList.add('active');
            event.target.classList.add('active');
        }
    </script>
</body>
</html>
'@
}

function New-ClassListHtml {
    param([hashtable]$Classes)
    
    $html = ""
    # Show ALL classes - sorted alphabetically by name
    foreach ($classKey in ($Classes.Keys | Sort-Object)) {
        $class = $Classes[$classKey]
        $methodCount = if ($class.Methods) { $class.Methods.Count } else { 0 }
        $html += @"
<div class="class-item">
    <div class="class-name">$($class.Name)</div>
    <div class="class-namespace">$($class.Namespace)</div>
    <div class="class-methods">$methodCount methods</div>
</div>
"@
    }
    return $html
}

function New-ProjectListHtml {
    param([hashtable]$Projects)
    
    $html = ""
    foreach ($projName in $Projects.Keys | Sort-Object) {
        $proj = $Projects[$projName]
        $framework = if ($proj.TargetFramework) { $proj.TargetFramework } else { "Unknown" }
        $html += @"
<div class="class-item">
    <div class="class-name">📦 $projName</div>
    <div class="class-namespace">$framework</div>
</div>
"@
    }
    return $html
}

function New-NamespaceListHtml {
    param([hashtable]$Classes)
    
    $namespaces = @{}
    foreach ($classKey in $Classes.Keys) {
        $class = $Classes[$classKey]
        $ns = if ($class.Namespace) { $class.Namespace } else { "(default)" }
        if (-not $namespaces.ContainsKey($ns)) {
            $namespaces[$ns] = 0
        }
        $namespaces[$ns]++
    }
    
    $html = ""
    foreach ($ns in ($namespaces.Keys | Sort-Object)) {
        $count = $namespaces[$ns]
        $html += @"
<div class="class-item">
    <div class="class-name">📁 $ns</div>
    <div class="class-methods">$count classes</div>
</div>
"@
    }
    return $html
}

function New-RelatedProjectsHtml {
    param([hashtable]$Projects)
    
    $html = ""
    foreach ($projName in $Projects.Keys | Sort-Object) {
        $proj = $Projects[$projName]
        $html += "<div class='class-card'><div class='class-name'>$projName</div><div class='class-namespace'>$($proj.TargetFramework)</div></div>`n"
    }
    return $html
}
#endregion

#region Dialog System (GS/IMP) Parser

function Start-GsParse {
    <#
    .SYNOPSIS
        Parses a MicroFocus Dialog System .imp file and generates HTML documentation.
    .DESCRIPTION
        Parses the exported .imp file (from .gs screenset) to extract:
        - Form Data fields (data passed between COBOL and screenset)
        - Window hierarchy (DIALOG-BOX, WINDOW)
        - UI components with positions
        - Field bindings (Masterfield -> Form Data)
        
        Generates a tabbed HTML page showing each window's layout using the shared AutoDoc theme.
    .PARAMETER ImpFile
        Path to the .imp file to parse.
    .PARAMETER OutputFolder
        Folder where the .screen.html file will be created.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImpFile,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFolder
    )
    
    if (-not (Test-Path $ImpFile)) {
        Write-LogMessage "IMP file not found: $ImpFile" -Level ERROR
        return $null
    }
    
    # Get template
    $sharedFolder = Get-AutodocSharedFolder
    $templatePath = Join-Path $sharedFolder "_templates\gsmmdtemplate.html"
    if (-not (Test-Path $templatePath)) {
        Write-LogMessage "GS template not found: $templatePath" -Level ERROR
        return $null
    }
    $template = Get-Content $templatePath -Raw -Encoding UTF8
    
    # IMP files are Windows-1252 (ANSI) encoded
    $content = Get-Content $ImpFile -Raw -Encoding 1252
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($ImpFile)
    
    # Parse form metadata
    $formName = if ($content -match '^Form\s+(\w+)') { $matches[1] } else { $baseName }
    $firstWindow = if ($content -match 'First-Window\s+([\w-]+)') { $matches[1] } else { "" }
    $gridStyle = if ($content -match 'Style\s+(?:EMU-PORTABLE\s+)?GRID\((\d+),(\d+)\)') { "GRID($($matches[1]),$($matches[2]))" } else { "" }
    
    # Parse Form Data fields
    $formFields = [System.Collections.ArrayList]::new()
    if ($content -match '(?s)Form Data(.+?)End Data') {
        $dataSection = $matches[1]
        $currentGroup = ""
        $currentGroupOccurs = 0
        
        foreach ($line in ($dataSection -split "`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\*' -or $trimmed -eq '') { continue }
            if ($trimmed -match 'Group\s+([\w-]+)\s+Vertical\s+Occurs\s+(\d+)') {
                $currentGroup = $matches[1]
                $currentGroupOccurs = [int]$matches[2]
                continue
            }
            if ($trimmed -match 'End Group') {
                $currentGroup = ""
                $currentGroupOccurs = 0
                continue
            }
            if ($trimmed -match '^([\w-]+)\s+(Character|Integer|Decimal)\((\d+(?:\.\d+)?)\)(.*)$') {
                [void]$formFields.Add(@{
                    Name = $matches[1]
                    DataType = $matches[2]
                    Size = $matches[3]
                    GroupName = $currentGroup
                    GroupOccurs = $currentGroupOccurs
                    Attributes = $matches[4].Trim()
                })
            }
        }
    }
    
    # Parse UI Objects
    $uiObjects = [System.Collections.ArrayList]::new()
    $objectMatches = [regex]::Matches($content, '(?s)Object\s+(\{?[\w-]+\}?)(.+?)End Object')
    foreach ($match in $objectMatches) {
        $objName = $match.Groups[1].Value
        $objContent = $match.Groups[2].Value
        
        $obj = @{
            Name = $objName
            Type = if ($objContent -match 'Type\s+([\w-]+)') { $matches[1] } else { "" }
            Parent = if ($objContent -match 'Parent\s+([\$\w-]+)') { $matches[1] } else { "" }
            StartX = if ($objContent -match 'Start\s+\(\s*(\d+)\s*,\s*(\d+)\s*\)') { [int]$matches[1] } else { 0 }
            StartY = if ($objContent -match 'Start\s+\(\s*(\d+)\s*,\s*(\d+)\s*\)') { [int]$matches[2] } else { 0 }
            Width = if ($objContent -match 'Size\s+\(\s*(\d+)\s*,\s*(\d+)\s*\)') { [int]$matches[1] } else { 0 }
            Height = if ($objContent -match 'Size\s+\(\s*(\d+)\s*,\s*(\d+)\s*\)') { [int]$matches[2] } else { 0 }
            Display = if ($objContent -match 'Display\s+"([^"]*)"') { $matches[1] } else { "" }
            Masterfield = if ($objContent -match 'Masterfield\s+([\w-]+)') { $matches[1] } else { "" }
            Picture = if ($objContent -match 'Picture\s+(\S+)') { $matches[1] } else { "" }
        }
        [void]$uiObjects.Add($obj)
    }
    
    # Parse Data Validations
    $dataValidations = [System.Collections.ArrayList]::new()
    $valMatches = [regex]::Matches($content, '(?s)Data Validation\s+([\w-]+)(.+?)End Validation')
    foreach ($match in $valMatches) {
        $fieldName = $match.Groups[1].Value
        $valContent = $match.Groups[2].Value
        $externalProgram = if ($valContent -match 'External\s+"([^"]+)"') { $matches[1] } else { "" }
        [void]$dataValidations.Add(@{ Field = $fieldName; ExternalProgram = $externalProgram })
    }
    
    # Build window hierarchy
    $windows = $uiObjects | Where-Object { $_.Type -in @('WINDOW', 'DIALOG-BOX') }
    $windowHierarchy = @{}
    foreach ($win in $windows) {
        $components = $uiObjects | Where-Object { $_.Parent -eq $win.Name -and $_.Type -notin @('WINDOW', 'DIALOG-BOX') }
        $windowHierarchy[$win.Name] = @{ Window = $win; Components = $components }
    }
    
    # Generate meta grid HTML
    $metaGridHtml = @"
      <div class="meta-item"><label>Form Name</label><span>$formName</span></div>
      <div class="meta-item"><label>First Window</label><span>$firstWindow</span></div>
      <div class="meta-item"><label>Grid Style</label><span>$gridStyle</span></div>
      <div class="meta-item"><label>Windows/Dialogs</label><span>$($windows.Count)</span></div>
      <div class="meta-item"><label>Total Objects</label><span>$($uiObjects.Count)</span></div>
      <div class="meta-item"><label>Form Fields</label><span>$($formFields.Count)</span></div>
"@
    
    # Generate tabs HTML
    $tabsHtml = [System.Text.StringBuilder]::new()
    $tabContentHtml = [System.Text.StringBuilder]::new()
    
    $orderedWindows = @($firstWindow) + ($windows | Where-Object { $_.Name -ne $firstWindow } | ForEach-Object { $_.Name })
    $orderedWindows = $orderedWindows | Where-Object { $_ -and $windowHierarchy.ContainsKey($_) }
    
    $isFirst = $true
    foreach ($winName in $orderedWindows) {
        $winData = $windowHierarchy[$winName]
        $win = $winData.Window
        $components = $winData.Components
        
        $activeClass = if ($isFirst) { 'active' } else { '' }
        $tabId = $winName -replace '[^a-zA-Z0-9]', '_'
        $tabLabel = if ($win.Display) { "$winName - $($win.Display)" } else { $winName }
        
        $encodedTabLabel = $tabLabel -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
        [void]$tabsHtml.AppendLine("<button class='gs-tab-btn $activeClass' data-tab='$tabId'>$encodedTabLabel</button>")
        
        [void]$tabContentHtml.AppendLine("<div class='gs-tab-content $activeClass' id='$tabId'>")
        $encodedWinDisplay = ($win.Display) -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
        [void]$tabContentHtml.AppendLine("<div class='window-info'><h3><i class='bi bi-window'></i> $encodedWinDisplay</h3>")
        [void]$tabContentHtml.AppendLine("<p><strong>Type:</strong> $($win.Type) | <strong>Parent:</strong> $($win.Parent) | <strong>Size:</strong> $($win.Width) x $($win.Height) | <strong>Components:</strong> $($components.Count)</p></div>")
        
        # Components table
        [void]$tabContentHtml.AppendLine("<div class='window-info'><h3><i class='bi bi-list-ul'></i> Components ($($components.Count))</h3>")
        [void]$tabContentHtml.AppendLine("<table class='component-table'><thead><tr><th>Name</th><th>Type</th><th>Position</th><th>Display</th><th>Masterfield</th></tr></thead><tbody>")
        foreach ($comp in ($components | Sort-Object { $_.StartY }, { $_.StartX })) {
            $display = if ($comp.Display) { ($comp.Display -replace '~', '' -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;') } else { '-' }
            $master = if ($comp.Masterfield) { "<code>$($comp.Masterfield)</code>" } else { '-' }
            [void]$tabContentHtml.AppendLine("<tr><td>$($comp.Name)</td><td>$($comp.Type)</td><td>($($comp.StartX), $($comp.StartY))</td><td>$display</td><td>$master</td></tr>")
        }
        [void]$tabContentHtml.AppendLine("</tbody></table></div>")
        [void]$tabContentHtml.AppendLine("</div>")
        
        $isFirst = $false
    }
    
    # Generate field bindings HTML
    $fieldBindingsHtml = [System.Text.StringBuilder]::new()
    $bindings = $uiObjects | Where-Object { $_.Masterfield }
    if ($bindings.Count -eq 0) {
        [void]$fieldBindingsHtml.AppendLine("<p style='color: var(--text-muted);'>No field bindings found.</p>")
    } else {
        [void]$fieldBindingsHtml.AppendLine("<table class='component-table'><thead><tr><th>UI Element</th><th>Type</th><th>Masterfield</th><th>Picture</th></tr></thead><tbody>")
        foreach ($b in $bindings) {
            $picture = if ($b.Picture) { "<code>$($b.Picture)</code>" } else { '-' }
            [void]$fieldBindingsHtml.AppendLine("<tr><td>$($b.Name)</td><td>$($b.Type)</td><td><code>$($b.Masterfield)</code></td><td>$picture</td></tr>")
        }
        [void]$fieldBindingsHtml.AppendLine("</tbody></table>")
    }
    
    # Generate validations HTML
    $validationsHtml = [System.Text.StringBuilder]::new()
    if ($dataValidations.Count -eq 0) {
        [void]$validationsHtml.AppendLine("<p style='color: var(--text-muted);'>No external validations defined.</p>")
    } else {
        [void]$validationsHtml.AppendLine("<table class='component-table'><thead><tr><th>Field</th><th>External Program</th></tr></thead><tbody>")
        foreach ($v in $dataValidations) {
            [void]$validationsHtml.AppendLine("<tr><td><code>$($v.Field)</code></td><td><code>$($v.ExternalProgram)</code></td></tr>")
        }
        [void]$validationsHtml.AppendLine("</tbody></table>")
    }
    
    # Replace placeholders in template using Set-AutodocTemplate
    $html = Set-AutodocTemplate -Template $template -OutputFolder $OutputFolder
    $html = $html.Replace("[title]", $formName)
    $html = $html.Replace("[metagrid]", $metaGridHtml)
    $html = $html.Replace("[tabs]", $tabsHtml.ToString())
    $html = $html.Replace("[tabcontent]", $tabContentHtml.ToString())
    $html = $html.Replace("[fieldbindings]", $fieldBindingsHtml.ToString())
    $html = $html.Replace("[validations]", $validationsHtml.ToString())
    $html = $html.Replace("[timestamp]", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
    
    # Check for related CBL HTML file and add link
    $cblHtmlFile = Join-Path $OutputFolder "$($formName.ToLower()).cbl.html"
    if (Test-Path $cblHtmlFile) {
        $html = $html.Replace("[cbllinkstyle]", "")
        $html = $html.Replace("[cbllink]", "./$($formName.ToLower()).cbl.html")
        $html = $html.Replace("[cbllinktext]", "$formName.CBL")
    } else {
        # Hide the section if no CBL file exists
        $html = $html.Replace("[cbllinkstyle]", "display: none;")
        $html = $html.Replace("[cbllink]", "#")
        $html = $html.Replace("[cbllinktext]", "")
    }
    
    # Write output file
    $outputFile = Join-Path $OutputFolder "$formName.screen.html"
    $html | Set-Content -Path $outputFile -Encoding UTF8 -Force
    
    Write-LogMessage "Generated Dialog System HTML: $outputFile" -Level DEBUG
    
    return $outputFile
}

#endregion

Export-ModuleMember -Function *