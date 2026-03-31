# AutoDoc.ps1
# Svein Morten Erikstad / Geir Helge Starholm
# Parse and extract COBOL program flow for mermaid.js diagrams for visualisation
# Prerequsite: Mermaid.js.
#              Download node.js and run: npm install -g @mermaid-js/mermaid-cli
#              Instructions here https://www.npmjs.com/package/@mermaid-js/mermaid-cli/v/8.9.2
#              https://mermaid.js.org/
# Example usage (when all source have been downloaded):

param(
    [Parameter(Mandatory)][string]$sourceFile,
    [bool]$show = $false,
    [string]$outputFolder = "$env:OptPath\Webs\AutoDoc",
    [bool]$cleanUp = $true,
    [string]$tmpRootFolder = "$env:OptPath\data\AutoDoc\tmp",
    [string]$srcRootFolder = "$env:OptPath\data\AutoDoc\src",
    [switch]$ClientSideRender,  # Skip SVG generation, embed MMD and use client-side Mermaid.js
    [switch]$saveMmdFiles  # Save Mermaid diagram source files (.mmd) alongside the HTML output
)

Import-Module -Name GlobalFunctions -Force
Import-Module -Name AutodocFunctions -Force

############################################################################################################################################################
############################################################################################################################################################
# Common Function Declarations
############################################################################################################################################################
############################################################################################################################################################

############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
# Function declarations
############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
# OPTIMIZED: Precompiled regex for COBOL end verbs
$script:endVerbPattern = [regex]::new('\b(end-accept|end-add|end-call|end-compute|end-delete|end-display|end-divide|end-evaluate|end-exec|end-if|end-multiply|end-perform|end-read|end-receive|end-return|end-rewrite|end-search|end-start|end-string|end-subtract|end-write)\b', [System.Text.RegularExpressions.RegexOptions]::Compiled -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
# Main program
############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
# ============================================================
# IN-MEMORY MMD ACCUMULATION - Thread-safe for parallel processing
# All script-level variables are isolated per runspace
# ============================================================
$script:sequenceNumber = 0
$baseFileName = ([System.IO.Path]::GetFileName( $sourceFile))
$script:baseFileNameTemp = $baseFileName.Replace(".cbl", "")

# Remove dummy file if it exists
$dummyFile = $outputFolder + "\" + $baseFileName + ".err"
if (Test-Path -Path $dummyFile  -PathType Leaf) {
    Remove-Item -Path $dummyFile -Force
}

Write-LogMessage ("Starting parsing of filename:" + $sourceFile) -Level INFO

# Check if the filename contains spaces
if ($baseFileName.Contains(" ")) {
    Write-LogMessage ("Filename is not valid. Contains spaces:" + $baseFileName) -Level ERROR
    exit
}
$script:mmdSequenceElementsWritten = 0

$StartTime = Get-Date
$script:logFolder = $outputFolder

# IN-MEMORY MMD CONTENT - Use ArrayLists for thread-safe accumulation
# When using ClientSideRender, we accumulate in memory and skip file I/O
$script:mmdFlowContent = [System.Collections.ArrayList]::new()
$script:mmdSequenceContent = [System.Collections.ArrayList]::new()

# File paths for backwards compatibility (only used when NOT using ClientSideRender)
$script:mmdFilenameFlow = $outputFolder + "\" + $baseFileName + ".flow.mmd"
$script:mmdFilenameSequence = $outputFolder + "\" + $baseFileName + ".sequence.mmd"

# Clean up old mmd files if they exist (only needed for non-ClientSideRender mode)
if (-not $ClientSideRender) {
    if (Test-Path -Path $script:mmdFilenameFlow -PathType Leaf) {
        Remove-Item $script:mmdFilenameFlow
    }
    if (Test-Path -Path $script:mmdFilenameSequence -PathType Leaf) {
        Remove-Item $script:mmdFilenameSequence
    }
}

$script:debugFilename = $outputFolder + "\" + $baseFileName + ".debug"
$htmlFilename = $outputFolder + "\" + $baseFileName + ".html"
$script:errorOccurred = $false

$script:sqlTableArray = @()

$inputDbFileFolder = $tmpRootFolder + "\cobdok"
$script:duplicateLineCheck = [System.Collections.Generic.HashSet[string]]::new()

# Store ClientSideRender flag for use in functions
$script:useClientSideRender = $ClientSideRender

Write-LogMessage ("Started for :" + $baseFileName) -Level INFO

# Initialize mmd flow content with empty header (only for file mode)
if (-not $ClientSideRender) {
    Set-Content -Path $script:mmdFilenameFlow -Value ""
}

if (Test-Path -Path $sourceFile  -PathType Leaf) {
    $fileContentOriginal = Get-Content $sourceFile -Encoding ([System.Text.Encoding]::GetEncoding(1252))
}
else {
    Write-LogMessage ("File not found:" + $sourceFile) -Level ERROR
    exit
}
# Pre-process filecontent to remove unwanted lines
$workArray, $procedureContent, $fileSectionLineNumber, $workingStorageLineNumber, $fileSectionContent = PreProcessFileContent -fileContentOriginal  $fileContentOriginal

HandleDiagramGeneration -workArray $workArray -procedureContent $procedureContent -fileSectionLineNumber $fileSectionLineNumber -workingStorageLineNumber $workingStorageLineNumber -fileSectionContent $fileSectionContent

if (-not $baseFileName.ToUpper().Contains("D4BMAL")) {
    # Skip SVG generation when using client-side rendering
    if (-not $ClientSideRender) {
        if (Test-Path -Path $script:mmdFilenameFlow  -PathType Leaf) {
            $result = GenerateSvgFile -mmdFilename $script:mmdFilenameFlow
            if ($result -eq $false) {
                New-Item -Path $dummyFile -ItemType File -Force
            }
        }

        if (Test-Path -Path $script:mmdFilenameSequence  -PathType Leaf) {
            $result = GenerateSvgFile -mmdFilename $script:mmdFilenameSequence
            if ($result -eq $false) {
                New-Item -Path $dummyFile -ItemType File -Force
            }
        }
    }
}

# Handle what to generate
if (!$script:errorOccurred) {
    # Retreive metadata from exported files from database
    $searchProgramName = $baseFileName.ToLower().Split(".")[0]
    GetMetaData -tmpRootFolder $tmpRootFolder  -outputFolder $outputFolder -baseFileName $baseFileName

    if ($show) {
        & $htmlFilename
    }
}

$endTime = Get-Date
$timeDiff = $endTime - $startTime

# Save MMD files if requested
if ($saveMmdFiles) {
    # Save flow diagram MMD
    if ($script:mmdFlowContent -and $script:mmdFlowContent.Count -gt 0) {
        $flowMmdOutputPath = Join-Path $outputFolder ($baseFileName + ".flow.mmd")
        $script:mmdFlowContent | Set-Content -Path $flowMmdOutputPath -Force
        Write-LogMessage ("Saved flow MMD file: $flowMmdOutputPath") -Level INFO
    }
    # Save sequence diagram MMD
    if ($script:mmdSequenceContent -and $script:mmdSequenceContent.Count -gt 0) {
        $seqMmdOutputPath = Join-Path $outputFolder ($baseFileName + ".sequence.mmd")
        $script:mmdSequenceContent | Set-Content -Path $seqMmdOutputPath -Force
        Write-LogMessage ("Saved sequence MMD file: $seqMmdOutputPath") -Level INFO
    }
}

# Log result
# Only create error file if HTML was NOT generated (fatal error)
# Non-fatal errors during parsing should not prevent successful completion if HTML was created

$htmlFilename = $outputFolder + "\" + $baseFileName + ".html"
$htmlWasGenerated = Test-Path -Path $htmlFilename -PathType Leaf

if ($htmlWasGenerated) {
    # HTML was generated - remove any error file and mark as success
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
}
else {
    # HTML was NOT generated - this is a true failure
    Write-LogMessage ("*******************************************************************************") -Level ERROR
    Write-LogMessage ("Failed - HTML not generated:" + $sourceFile) -Level ERROR
    Write-LogMessage ("*******************************************************************************") -Level ERROR
    "Error: HTML file was not generated for $baseFileName" | Set-Content -Path $dummyFile -Force
}


