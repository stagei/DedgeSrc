

# RexParse.ps1
# Geir Helge Starholm
# parse and extract Object Rexx program flow for mermaid.js diagrams for visualisation
# Prerequsite: Mermaid.js.
#              Download node.js and run: npm install -g @mermaid-js/mermaid-cli
#              Instructions here https://www.npmjs.com/package/@mermaid-js/mermaid-cli/v/8.9.2
#              https://mermaid.js.org/

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
# Local Function Declarations
############################################################################################################################################################
############################################################################################################################################################



############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
# Main program
############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
# if ($sourceFile.ToLower().Contains("cobntzip.rex")) {
#     # LogMessage all input parameters in one line
#     LogMessage -message ("--> Started for :" + $sourceFile + " ¤ " + $diagramType + " ¤ " + $generateType + " ¤ " + $show.ToString() + " ¤ " + $outputFolder + " ¤ " + $cleanUp.ToString() + " ¤ " + $tmpRootFolder + " ¤ " + $srcRootFolder )
# }

$script:sequenceNumber = 0
$baseFileName = ([System.IO.Path]::GetFileName( $sourceFile))

Write-LogMessage ("Starting parsing of filename:" + $sourceFile) -Level INFO

# Check if the filename contains spaces
if ($baseFileName.Contains(" ")) {
    Write-LogMessage ("Filename is not valid. Contains spaces:" + $baseFileName) -Level ERROR
    exit
}

# Check if the filename match the purpose of the script
if (-Not $baseFileName.ToLower().Contains(".rex")) {
    Write-LogMessage ("Filetype is not valid for parsing of Object-Rexx script (.rex):" + $baseFileName) -Level ERROR
    exit
}

# ============================================================
# IN-MEMORY MMD ACCUMULATION - Thread-safe for parallel processing
# ============================================================
$StartTime = Get-Date
$script:logFolder = $outputFolder
$script:mmdFilename = $outputFolder + "\" + $baseFileName + ".flow.mmd"
$script:debugFilename = $outputFolder + "\" + $baseFileName + ".debug"
$svgFilename = $outputFolder + "\" + $baseFileName + ".flow.svg"
$htmlFilename = $outputFolder + "\" + $baseFileName + ".html"
$script:errorOccurred = $false

$script:sqlTableArray = @()

$inputDbFileFolder = $tmpRootFolder + "\cobdok"
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
} else {
    Set-Content -Path $script:mmdFilename -Value $mmdHeader
}
# mermaid.initialize({maxTextSize: 90000

#   });
# $programName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile).ToLower()
$programName = [System.IO.Path]::GetFileName($sourceFile.ToLower())
$script:baseFileNameTemp = $baseFileName

if (Test-Path -Path $sourceFile  -PathType Leaf) {
    $fileContentOriginal = Get-Content $sourceFile -Encoding ([System.Text.Encoding]::GetEncoding(1252))
    $completeFileContent = $fileContentOriginal
    $test = $fileContentOriginal -join "¤"

    # Remove content between /* and */
    $pattern = "/\*.*?\*/"
    $test = $test -replace $pattern, ""
    $fileContentOriginal = $test.Split("¤")
}
else {
    Write-LogMessage ("File not found:" + $sourceFile) -Level ERROR
    exit
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
    # Add properties to the object
    $obj | Add-Member -Type NoteProperty -Name "LineNumber" -Value 1
    $obj | Add-Member -Type NoteProperty -Name "Line" -Value "__MAIN__:"
    $obj | Add-Member -Type NoteProperty -Name "Pattern" -Value  "^.*:"
    $workContent += $obj
}
# Add all matches to $workContent
$workContent += $workContent2

# Create a list of all functions
$functions = @()
$functionsList = @()
if ($workContent.Count -gt 0) {
    $functionsList += $obj.Line.ToUpper().Replace(":", "").Trim()
}
$functionsList += $fileContentOriginal | Where-Object { $_ -match "^.*:$" } | ForEach-Object { $_.Trim().Replace(":", "").ToUpper() }
$script:functions += $functionsList

# Create a dictionary of all assigned variables
$assignments = $fileContentOriginal | Where-Object { $_ -match "=" -and $_ -notmatch "if" }
$script:assignmentsDict = @{}
# Parse each line and add to the dictionary
foreach ($line in $assignments) {
    $temp = $line -split "="
    $key = $temp[0].Trim().ToUpper()
    try {
        $script:assignmentsDict[$key] = $temp[1].Trim().Replace('"', "'")
    }
    catch {
    }
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
    if (VerifyIfFunction -functionName ($line)) {
        if ($functionCodeExceptLoopCode.Count -gt 0) {
            $loopCounter = 0
            # Generate nodes previous function
            GenerateNodes -functionCode $functionCodeExceptLoopCode -fileContent $fileContent -functionName $previousParticipant -fdHashtable $fdHashtable -loopCounter $loopCounter
        }

        $pos = $line.IndexOf(":")
        $currentParticipant = $line.Substring(0, $pos).Trim()
        $currentFunctionName = $currentParticipant.Trim()
        $functionCode = FindFunctionCode -array $workContent -functionName $currentParticipant

        $loopLevel = { }.Invoke()
        $loopNodeContent = { }.Invoke()
        $loopCode = { }.Invoke()
        $functionCodeExceptLoopCode = { }.Invoke()

        # Handling program name to initital function
        if ($previousParticipant.Length -eq 0 -and $currentParticipant.Length -gt 0) {
            $statement = $programName.Trim().ToLower() + "[[" + $programName.Trim().ToLower() + "]]" + " --initiated-->" + $currentParticipant.Trim().ToLower() + "(" + $currentParticipant.Trim().ToLower() + ")"
            WriteMmd -mmdString $statement
            $statement = "style " + $programName.Trim().ToLower() + " stroke:red,stroke-width:4px"
            WriteMmd -mmdString $statement

            $link = "https://Dedge.visualstudio.com/_git/Dedge?path=/rexx_prod/" + $baseFileName.ToLower()
            $statement = "click " + $programName.Trim().ToLower() + " " + '"' + $link + '"' + " " + '"' + $programName.Trim().ToLower() + '"' + " _blank"
            WriteMmd -mmdString $statement

        }
    }

    if ($functionCode.Count -eq 0) {
        Continue
    }

    $skipLine = $false
    # Perform handling
    if ($line.trim().ToLower().contains("do ") -and ($line.trim().ToLower().contains(" while") -or $line.trim().ToLower().contains(" until") )) {
        # if ($currentFunctionName.Contains("m270")) {
        #
        # }

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
        $statement = $fromNode + "--" + '"' + "call " + '"' + "-->" + $toNode

        WriteMmd -mmdString $statement
        $skipLine = $true
    }
    else {
        if ($loopCounter -gt 0 -and $line.trim().tolower().StartsWith(("end"))) {
            $workCode = $loopCode[$loopCounter - 1]
            # Generate nodes for current loop
            GenerateNodes -functionCode $loopCode[$loopCounter - 1] -fileContent $fileContent -functionName ($loopLevel[$loopCounter - 1])  -fdHashtable $fdHashtable -currentLoopCounter $loopCounter

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
            if ($loopCode[$loopCounter - 1].Length -gt 0 ) {
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
GenerateNodes -functionCode $functionCodeExceptLoopCode -fileContent $fileContent -functionName $currentFunctionName -fdHashtable $fdHashtable -loopCounter $loopCounter

# Generate links to sourcecode in Azure devOps
GenerateMmdLinks -baseFileName $baseFileName -sourceFile $workContent

# Generate
GenerateMmdExecutionPathDiagram -srcRootFolder $srcRootFolder -baseFileName $baseFileName -tmpRootFolder $tmpRootFolder

# Generate SVG file from mmd content (skip when using client-side rendering)
if (-not $ClientSideRender) {
    GenerateSvgFile -mmdFilename $script:mmdFilename
}

# Handle what to generate
if (!$script:errorOccurred) {
    # Retreive metadata from exported files from database
    GetMetaData -tmpRootFolder $tmpRootFolder  -outputFolder $outputFolder -baseFileName $baseFileName -completeFileContent $completeFileContent -inputDbFileFolder $inputDbFileFolder

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
        $flowMmdOutputPath = Join-Path $outputFolder ($baseFileName + ".mmd")
        $script:mmdFlowContent | Set-Content -Path $flowMmdOutputPath -Force
        Write-LogMessage ("Saved flow MMD file: $flowMmdOutputPath") -Level INFO
    }
}

# Log result
# Only create error file if HTML was NOT generated (fatal error)
# Non-fatal errors during parsing should not prevent successful completion if HTML was created
$dummyFile = $outputFolder + "\" + $baseFileName + ".err"
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


