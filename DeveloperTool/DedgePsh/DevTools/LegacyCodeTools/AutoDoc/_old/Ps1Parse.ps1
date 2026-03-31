# Ps1Parse.ps1
# Geir Helge Starholm
# parse and extract Powershell flow for mermaid.js diagrams for visualisation
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
$script:sequenceNumber = 0
$baseFileName = ([System.IO.Path]::GetFileName( $sourceFile))
$fullFileName = $sourceFile
$htmlPath = $fullFileName.Replace($srcRootFolder, "").Replace("\DedgePsh", "").Replace($baseFileName, "").Replace("\", "%2F") + $baseFileName

Write-LogMessage ("Starting parsing of filename:" + $sourceFile) -Level INFO

# Check if the filename contains spaces
if ($baseFileName.Contains(" ")) {
    Write-LogMessage ("Filename is not valid. Contains spaces:" + $baseFileName) -Level ERROR
    exit
}

# Check if the filename match the purpose of the script
if (-Not $baseFileName.ToLower().Contains(".ps1")) {
    Write-LogMessage ("Filetype is not valid for parsing of Powershell script (.ps1):" + $baseFileName) -Level ERROR
    exit
}

# Check if the file exist in certain folders
if ($sourceFile.ToLower().Contains("\fat\") -or $sourceFile.ToLower().Contains("\kat\") -or $sourceFile.ToLower().Contains("\vft\")) {
    Write-LogMessage ("Skipping file due to location in KAT/FAT/VFT:" + $sourceFile) -Level INFO
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

if ($baseFileName.ToLower().Contains("parse.ps1")) {
    Write-LogMessage ("Cannot create diagram on parser programs: " + $baseFileName) -Level INFO
    exit
}
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

$programName = [System.IO.Path]::GetFileName($sourceFile.ToLower())
$script:baseFileNameTemp = $baseFileName

$script:functionList = @()
$script:assignmentsDict = @{}
$script:functionList2 = @()

if (Test-Path -Path $sourceFile -PathType Leaf) {
    $fileContentOriginalWithComments = Get-Content -Path $sourceFile
    $fileContentOriginal = Get-Content -Path $sourceFile | Select-String "^*"
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
            $pos = $item.Line.IndexOf("#>")
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
            catch {
            }
        }
    }
    $fileContent = $testArray
}
else {
    Write-LogMessage ("File not found:" + $sourceFile) -Level ERROR
    exit
}

$script:functionList += "__MAIN__"
$script:functionList2 += "__MAIN__"
$functionsList = $script:functionList
$assignmentsDict = $script:assignmentsDict

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
$mainCodeExceptLoopCode = { }.Invoke()
$counter = 0
$startBracketCount = 0
$endBracketCount = 0

# Initialize loop tracking arrays (needed before the main foreach loop)
$loopLevel = { }.Invoke()
$loopNodeContent = { }.Invoke()
$loopCode = { }.Invoke()
$loopCodeStartBracketCount = { }.Invoke()
$loopCodeEndBracketCount = { }.Invoke()

# Set-Content -Path ".\debugfile.txt" -Value $fileContent
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

    $isFunction, $currentParticipantTemp = VerifyIfFunction -functionName $line
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
            catch {
            }

        }
        if ($line.Contains("}")) {
            try {
                $work = $loopCodeEndBracketCount[$loopCounter - 1]
                $work += [System.Convert]::ToInt16(($line -split "}").Count - 1)
                $loopCodeEndBracketCount[$loopCounter - 1] = $work
            }
            catch {
            }
        }
    }

    if ($loopCounter -gt 0 ) {
        if ($loopCodeStartBracketCount[$loopCounter - 1] -gt 0 -and $loopCodeStartBracketCount[$loopCounter - 1] -eq $loopCodeEndBracketCount[$loopCounter - 1]) {
            $workCode = $loopCode[$loopCounter - 1]
            # Generate nodes for current loop
            GenerateNodes -functionCode $loopCode[$loopCounter - 1] -fileContent $fileContent -functionName ($loopLevel[$loopCounter - 1])  -fdHashtable $fdHashtable -currentLoopCounter $loopCounter -htmlPath $htmlPath

            try {
                $loopLevel.RemoveAt($loopCounter - 1)
            }
            catch {
            }
            try {
                $loopNodeContent.RemoveAt($loopCounter - 1)
            }
            catch {
            }
            try {
                $loopCode.RemoveAt($loopCounter - 1)
            }
            catch {
            }
            try {
                $loopCodeStartBracketCount.RemoveAt($loopCounter - 1)
            }
            catch {
            }
            try {
                $loopCodeEndBracketCount.RemoveAt($loopCounter - 1)
            }
            catch {
            }

            $loopCounter -= 1
            $skipLine = $true
            $currentParticipant = ""
        }
    }

    # Check if line is a function
    if ($isFunction -or ($isEndOfFunction -and $currentParticipant -ne "__MAIN__")) {
        if ($functionCodeExceptLoopCode.Count -gt 0) {
            $loopCounter = 0
            # Generate nodes previous function
            # loop down $loopCounter and call GenerateNodes for each until 0
            GenerateNodes -functionCode $functionCodeExceptLoopCode -fileContent $fileContent -functionName $previousParticipant -fdHashtable $fdHashtable -loopCounter $loopCounter -htmlPath $htmlPath

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
        catch {
        }

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
    if ($line.ToUpper().Contains("GENERATENODES")) {
    }

    # Perform handling
    if ($line.trim().ToLower().StartsWith("for ") -or $line.trim().ToLower().StartsWith("for(") `
            -or $line.trim().ToLower().StartsWith("foreach ") -or $line.trim().ToLower().StartsWith("foreach(") `
            -or $line.trim().ToLower().StartsWith("do ") -or $line.trim().ToLower().StartsWith("do{") -or $line.trim().ToLower().StartsWith("do {") `
            -or $line.trim().ToLower().StartsWith("while ") -or $line.trim().ToLower().StartsWith("while(")) {
        $loopCounter += 1

        $tmpCurrentParticipant = $currentParticipant
        if ($currentParticipant.ToLower().Contains("handlediagramgeneration")) {
            if ($line.Contains("GENERATENODES")) {
            }

        }
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

            $loopLevel.Add($currentParticipant + "-loop" + $loopCounter )
        }
        else {

            $fromNode = $tmpCurrentParticipant
            $toNode = $tmpCurrentParticipant + "-loop" + "((" + $tmpCurrentParticipant + "-loop))"
            $toNode = $toNode.Replace("$", "")
            $loopLevel.Add($tmpCurrentParticipant.Replace("$", "") + "-loop")
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
            $statement = $fromNode.ToLower().Replace("$", "") + "--" + '"' + "call " + '"' + "-->" + $toNode.ToLower()
        }
        catch {
        }

        WriteMmd -mmdString $statement
        $skipLine = $true
    }
    else {
        if ($loopCounter -gt 0) {
            # Accumulate brackets
            # if ($line.Contains("{")) {
            #     $work = $loopCodeStartBracketCount[$loopCounter - 1]
            #     $work += [System.Convert]::ToInt16(($line -split "{").Count - 1)
            #     try {
            #         $loopCodeStartBracketCount[$loopCounter - 1] = $work
            #     }
            #     catch {
            #
            #     }

            # }
            # if ($line.Contains("}")) {
            #     try {
            #         $work = $loopCodeEndBracketCount[$loopCounter - 1]
            #         $work += [System.Convert]::ToInt16(($line -split "}").Count - 1)
            #         $loopCodeEndBracketCount[$loopCounter - 1] = $work
            #     }
            #     catch {
            #
            #     }
            # }
            if ($lineObject.LineNumber -eq 348) {
            }

            # if ($loopCodeStartBracketCount[$loopCounter - 1] -gt 0 -and $loopCodeStartBracketCount[$loopCounter - 1] -eq $loopCodeEndBracketCount[$loopCounter - 1]) {
            #     $workCode = $loopCode[$loopCounter - 1]
            #     # Generate nodes for current loop
            #     GenerateNodes -functionCode $loopCode[$loopCounter - 1] -fileContent $fileContent -functionName ($loopLevel[$loopCounter - 1])  -fdHashtable $fdHashtable -currentLoopCounter $loopCounter -htmlPath $htmlPath

            #     try {
            #         $loopLevel.RemoveAt($loopCounter - 1)
            #     }
            #     catch {
            #
            #     }
            #     try {
            #         $loopNodeContent.RemoveAt($loopCounter - 1)
            #     }
            #     catch {
            #
            #     }
            #     try {
            #         $loopCode.RemoveAt($loopCounter - 1)
            #     }
            #     catch {
            #
            #     }
            #     try {
            #         $loopCodeStartBracketCount.RemoveAt($loopCounter - 1)
            #     }
            #     catch {
            #
            #     }
            #     try {
            #         $loopCodeEndBracketCount.RemoveAt($loopCounter - 1)
            #     }
            #     catch {
            #
            #     }

            #     $loopCounter -= 1
            #     $skipLine = $true
            #     $currentParticipant = ""
            # }
        }
    }
    # Accumulate lines
    if ($skipLine -eq $false) {
        if ($lineObject.LineNumber -eq 337) {
        }
        if ($loopCounter -gt 0) {
            $workCode = { }.Invoke()
            if ($loopCode[$loopCounter - 1].Length -gt 0 ) {
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
WriteMmd  $statement
$statement = "style " + $programName.Trim().ToLower() + " stroke:red,stroke-width:4px"
WriteMmd  $statement

$link = "https://Dedge.visualstudio.com/Dedge/_git/DedgePsh?path=" + $htmlPath
$statement = "click " + $programName.Trim().ToLower() + " " + '"' + $link + '"' + " " + '"' + $programName.Trim().ToLower() + '"' + " _blank"
WriteMmd  $statement

# Generate nodes for last function
GenerateNodes -functionCode $mainCodeExceptLoopCode -fileContent $fileContent -functionName "__MAIN__" -fdHashtable $fdHashtable -loopCounter 0 -htmlPath $htmlPath

# Generate links to sourcecode in Azure devOps
GenerateMmdLinks -baseFileName $baseFileName -htmlPath $htmlPath -sourceFile $workContent

# Generate execution path diagram
GenerateMmdExecutionPathDiagram -srcRootFolder $srcRootFolder -baseFileName $baseFileName -tmpRootFolder $tmpRootFolder

# Generate SVG file from mmd content (skip when using client-side rendering)
if (-not $ClientSideRender) {
    GenerateSvgFile -mmdFilename $script:mmdFilename
}

# Handle what to generate
if (!$script:errorOccurred) {
    # Retreive metadata from exported files from database
    GetMetaData -tmpRootFolder $tmpRootFolder  -outputFolder $outputFolder -baseFileName $baseFileName -completeFileContent $fileContentOriginalWithComments -inputDbFileFolder $inputDbFileFolder
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
        Write-LogMessage ("Completed with warnings:" + $fullFileName) -Level WARN
    }
    else {
        Write-LogMessage ("Time elapsed: " + $timeDiff.Seconds.ToString()) -Level INFO
        Write-LogMessage ("Completed successfully:" + $fullFileName) -Level INFO
    }
}
else {
    # HTML was NOT generated - this is a true failure
    Write-LogMessage ("*******************************************************************************") -Level ERROR
    Write-LogMessage ("Failed - HTML not generated:" + $sourceFile) -Level ERROR
    Write-LogMessage ("*******************************************************************************") -Level ERROR
    "Error: HTML file was not generated for $baseFileName" | Set-Content -Path $dummyFile -Force
}


