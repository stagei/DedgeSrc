# CBLDuplicateStatements.ps1
# Geir Helge Starholm
#
param(
    [Parameter(Mandatory)][string]$sourceFile)

############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
# Function declarations
############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################

function RemoveDoubleSpaces {
    param (
        $text
    )
    # Loop until there are no double spaces left
    while ($text -match "  ") {
        # Replace double spaces with single space
        $text = $text -replace "  ", " "
    }

    # Return the result
    Return $text.Trim()
}

function ContainsEndVerb {
    param($sourceLine)
    $containsEndVerb = $false
    $startWithEndVerb = $false
    $sourceLine = $sourceLine.ToUpper()
    $sourceLine = " " + $sourceLine.ToLower() + " "
    $endverb = ""
    $endVerbPos = 0
    if ($null -eq $sourceLine) {
        return $false, $false, "", -1
    }

    $endverbs = @(
        "end-accept",
        "end-add",
        "end-call",
        "end-compute",
        "end-delete",
        "end-display",
        "end-divide",
        "end-evaluate",
        "end-exec",
        "end-if",
        "end-multiply",
        "end-perform",
        "end-read",
        "end-receive",
        "end-return",
        "end-rewrite",
        "end-search",
        "end-start",
        "end-string",
        "end-subtract",
        "end-write")

    foreach ($currentItemName in $endverbs) {
        if ($sourceLine.Contains($currentItemName)) {
            $containsEndVerb = $true
            $endverb = $currentItemName
            $endVerbPos = $sourceLine.IndexOf($endverb) - 1
            break
        }
    }

    return $containsEndVerb, $endverb, $endVerbPos
}

function ContainsVerb {
    param($sourceLine)
    $containsVerb = $false
    $verb = ""
    $verbPos = 0

    if ($null -eq $sourceLine) {
        return $false, $false, "", -1
    }
    $sourceLine = " " + $sourceLine.ToLower() + " "
    $verbs = @(
        "accept",
        "add",
        "alter",
        "call",
        "cancel",
        "close",
        "commit",
        "compute",
        "continue",
        "delete",
        "display",
        "divide",
        "entry",
        "evaluate",
        "exec",
        "exhibit",
        "exit",
        "generate",
        "goback",
        "go to",
        "if",
        "initialize",
        "inspect",
        "invoke",
        "merge",
        "move",
        "multiply",
        "open",
        "perform",
        "read",
        "release",
        "return",
        "rewrite",
        "rollback",
        "search",
        "set",
        "sort",
        "start",
        "stop run",
        "string",
        "subtract",
        "unstring",
        "write"
    )

    foreach ($currentItemName in $verbs) {
        if ($sourceLine.Contains(" " + $currentItemName + " ")) {
            $containsVerb = $true
            $verb = $currentItemName
            $verbPos = $sourceLine.IndexOf($verb) - 1
            break
        }
    }

    return $containsVerb, $verb, $verbPos
}

function ContainsBindVerb {
    param($sourceLine)
    $containsBindVerb = $false
    $bindVerb = ""
    $bindVerbPos = 0

    if ($null -eq $sourceLine) {
        return $false, $false, "", -1
    }
    $sourceLine = " " + $sourceLine.ToLower() + " "
    $bindVerbs = @(
        "else",
        "when"
    )

    foreach ($currentItemName in $bindVerbs) {
        if ($sourceLine.Contains(" " + $currentItemName + " ")) {
            $containsBindVerb = $true
            $bindVerb = $currentItemName
            $bindVerbPos = $sourceLine.IndexOf($bindVerb) - 1
            break
        }
    }

    return $containsBindVerb, $bindVerb, $bindVerbPos
}

function ContainsPeriod {
    param($sourceLine)
    $containsPeriod = $false
    $Period = ""
    $PeriodPos = 0

    if ($null -eq $sourceLine) {
        return $false, $false, "", -1
    }
    $sourceLine = " " + $sourceLine.ToLower() + " "
    if ($sourceLine.Contains(".")) {
        $containsPeriod = $true
        $PeriodPos = $sourceLine.IndexOf('.') - 1
    }

    return $containsPeriod, $PeriodPos
}

function PreProcessFileContent {
    param($fileContentOriginal)

    $declarativesContent = @()
    $procedureContent = @()
    $procedureCodeContent = @()
    $fileSectionContent = @()

    $fileSectionLineNumber = 0
    $WorkingStorageLineNumber = 0
    $procedureDivisionLineNumber = 0
    $procedureDivisionPeriodLinenumber = 0
    $firstParagraphLinenumber = 0

    $workArray = @()
    $counter = 0

    foreach ($line in $fileContentOriginal) {

        if ($counter -eq 985 ) {
            $x = 1
        }

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

        if ($procedureDivisionLinenumber -gt 0 -and $procedureDivisionPeriodLinenumber -eq 0 -and $line.Contains(".")) {
            $procedureDivisionPeriodLinenumber = $counter
            $counter = 0
            continue
        }

        if (-not ($procedureDivisionPeriodLinenumber -gt 0)) {
            continue
        }

        # $verifiedParagraph = $false
        # $verifiedParagraph = VerifyIfParagraph -paragraphName ($line.replace(".", "").Trim())

        if (VerifyIfParagraph -paragraphName ($line.replace(".", "").Trim()) -and $firstParagraphLinenumber -eq 0) {
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
            $WorkingStorageLineNumber = $counter
        }

        if ($fileSectionLineNumber -gt 0 -and $WorkingStorageLineNumber -eq 0) {
            $fileSectionContent += $line
        }

        $workArray += $line

    }

    $workArray1 = @()
    $counter = -1
    $writeCounter = -1
    $accumulatedExpression = ""
    $procedureDivisionLinenumber = 0
    $procedureDivisionPeriodLinenumber = 0
    $firstParagraphLinenumber = 0
    $currentlyInExec = $false

    while ($workArray.Count -gt $counter) {
        $counter += 1
        $line = $workArray[$counter]
        if ($null -eq $line) {
            continue
        }

        if ($line -match "procedure.*division" -or $line -match "procedure.division" ) {
            $procedureDivisionLinenumber = $counter
        }

        # Check if line contains a paragraph
        $verifiedParagraph = VerifyIfParagraph -paragraphName ($line.replace(".", "").Trim())
        if ($verifiedParagraph ) {
            $firstParagraphLinenumber = $counter
            if ($firstParagraphLinenumber -eq 0) {
                $firstParagraphLinenumber = $counter
            }

            if ($accumulatedExpression.Length -gt 0) {
                $workArray1 += RemoveDoubleSpaces -text $accumulatedExpression
                $accumulatedExpression = ""
            }
            $workArray1 += $line
            continue
        }

        # Replace all strings with VAR1, VAR2, VAR3 etc
        $i = 0
        $pattern = '\".*?\"' + "|" + "\'.*?\'"
        $line = $line -replace $pattern , { $i++; "¤VAR¤" }

        $line = RemoveDoubleSpaces -text $line

        # Get information about the line
        $line = $line.Trim()

        $containsVerb = $false
        $verb = ""
        $verbPos = 0
        $containsBindVerb = $false
        $bindVerb = ""
        $bindVerbPos = 0
        $containsPeriod = $false
        $PeriodPos = 0
        if ($currentlyInExec -eq $false) {
            $containsVerb, $verb, $verbPos = ContainsVerb -sourceLine $line
            $containsBindVerb, $bindVerb, $bindVerbPos = ContainsBindVerb -sourceLine $line
            $containsPeriod, $PeriodPos = ContainsPeriod -sourceLine $line
        }
        $containsEndVerb, $endverb, $endVerbPos = ContainsEndVerb -sourceLine $line

        # if ($containsVerb -and $verbAtStartOfLine) {
        #     $workArray1 += RemoveDoubleSpaces -text $line
        #     continue
        # }
        if ($verb -eq ("exec")) {
            $currentlyInExec = $true
        }

        if ($endverb -eq ("end-exec")) {
            $currentlyInExec = $false
        }

        # if ($accumulatedExpression.Length -gt 0 -and $containsVerb -and $containsEndVerb ) {
        #     $workArray1 += RemoveDoubleSpaces -text $line
        #     continue
        # }
        if ($writeCounter -eq 34 ) {
            $x = 1
        }
        $line = $line.Trim()
        if ($accumulatedExpression.Length -gt 0 -and ($containsVerb -or $containsEndVerb -or $containsBindVerb -or $containsPeriod)) {
            $addString = ""
            $addLineContentFromPos = 0

            if ($containsPeriod) {
                $addString = $line.Substring(0, $periodPos)
                $addLineContentFromPos = $verbPos
            }
            elseif ($containsBindVerb) {
                $addString = $line.Substring(0, $bindVerbPos)
                $addLineContentFromPos = $bindVerbPos
            }
            elseif ($containsVerb) {
                $addString = $line.Substring(0, $verbPos)

            }
            elseif ($containsEndVerb) {
                $addString = $line.Substring(0, $endVerbPos)
                $addLineContentFromPos = $endVerbPos
                $endVerbList = @("end-accept", "end-add", "end-call", "end-compute", "end-delete", "end-display", "end-divide", "end-exec", "end-multiply", "end-read", "end-receive", "end-return", "end-rewrite", "end-search", "end-start", "end-string", "end-subtract", "end-write")

                if ($endVerbList.Contains($endverb) ) {
                    $addString = " " + $endverb
                    $addLineContentFromPos = $endVerbPos + 1 + $endverb.Length
                    $accumulatedExpression += " " + $addString.Trim()
                    continue
                }

            }
            #  elseif ($containsBindVerb -and $containsVerb) {
            #     if ($bindVerbPos -lt $verbPos) {
            #         $addString = $line.Substring(0, $bindVerbPos)
            #         $workArray1 += RemoveDoubleSpaces -text ($accumulatedExpress5ion + " " + $addString.Trim())
            #         $accumulatedExpression = ""
            #         $addString = $line.Substring($bindVerbPos, $verbPos - $bindVerbPos)
            #         $workArray1 += RemoveDoubleSpaces -text ($accumulatedExpression + " " + $addString.Trim())
            #         $accumulatedExpression = $line.Substring($verbPos)
            #         $addString = ""
            #     }
            #     else {
            #         $addString = $line.Substring(0, $verbPos)
            #         $addLineContentFromPos = $verbPos
            #         $workArray1 += RemoveDoubleSpaces -text ($accumulatedExpression + " " + $addString.Trim())

            #         $addString = $line.Substring($verbPos, $bindVerbPos - $verbPos)
            #         $workArray1 += RemoveDoubleSpaces -text ($accumulatedExpression + " " + $addString.Trim())
            #         $accumulatedExpression = $line.Substring($bindVerbPos)
            #         $addString = ""
            #     }
            # }
            # elseif ($containsEndVerb) {
            #     $addString = $line.Substring(0, $endVerbPos)
            #     $line.Substring(0, $endVerbPos) = ""
            #     $addLineContentFromPos = $endVerbPos
            #     $endVerbList = @("end-accept", "end-add", "end-call", "end-compute", "end-delete", "end-display", "end-divide", "end-exec", "end-multiply", "end-read", "end-receive", "end-return", "end-rewrite", "end-search", "end-start", "end-string", "end-subtract", "end-write")
            #     if ($endVerbList.Contains($endverb) ) {
            #         $addString += " " + $endverb
            #         $addLineContentFromPos = $endVerbPos + 1 + $endverb.Length
            #     }
            # }
            $line = $line.Substring($addLineContentFromPos)
            $workArray1 += RemoveDoubleSpaces -text ($accumulatedExpression + " " + $addString.Trim())
            $writeCounter += 1
            $accumulatedExpression = $line
            # if ($addLineContentFromPos -lt $line.Length) {
            #     $accumulatedExpression = $line.Substring($addLineContentFromPos)
            # }
            continue
        }
        else {
            if ($accumulatedExpression.Length -eq 0 ) {
                $accumulatedExpression = $line
            }
            else {
                $accumulatedExpression += " " + $line.Trim()
            }

            continue
        }

    } #while ($workArray.Count -gt $counter)

    if ($accumulatedExpression.Length -gt 0) {
        $workArray1 += RemoveDoubleSpaces -text $accumulatedExpression
    }

    $workArray = $workArray1
    return $workArray

}

function VerifyIfParagraph {
    param(
        $paragraphName
    )
    $isValidParagraph = $false

    if ($paragraphName.IndexOf(" ") -gt 0) {
        $paragraphName = $paragraphName.Substring(0, ($paragraphName.IndexOf(" ") - 1))
    }

    try {
        if ($paragraphName.Length -gt 4) {
            $testInt = [int]$paragraphName.Substring(1, 3)
            $isValidParagraph = $true
        }
    }
    catch {
        $isValidParagraph = $false
    }
    return $isValidParagraph
}

function LogMessage {
    param(
        $message
    )
    $dtLog = get-date -Format("yyyyMMdd").ToString()
    $logfile = "\\DEDGE.fk.no\erpprog\cobnt\" + $dtLog + "_CblParse.log"
    $logfile1 = $global:logFolder + "\" + $dtLog + "_CblParse.log"
    $dt = get-date -Format("yyyy-MM-dd HH:mm:ss,ffff").ToString()

    $logmsg = $dt + ": CblParse :  " + $message

    Write-Host $logmsg
    Add-Content -Path $logfile -Value $logmsg
    Add-Content -Path $logfile1 -Value $logmsg
}

############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
# Main program
############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
############################################################################################################################################################
# Start-Transcript \\DEDGE.fk.no\erpprog\COBNT\CblParse.MFOUT -Append

$baseFileName = ([System.IO.Path]::GetFileName( $sourceFile))
$startTime = Get-Date
$outputFolder = ".\"
$global:logFolder = ".\"
$global:debugFilename = $outputFolder + "\" + $baseFileName + ".debug"
$global:errorOccurred = $false

LogMessage -message ("--> Started for :" + $baseFileName)

$programName = [System.IO.Path]::GetFileNameWithoutExtension($sourceFile).ToLower()

if (Test-Path -Path $sourceFile  -PathType Leaf) {
    $fileContentOriginal = Get-Content $sourceFile -Encoding ([System.Text.Encoding]::GetEncoding(1252))
}
else {
    LogMessage -message ("**> File not found:" + $sourceFile)
    exit
}

# Pre-process filecontent to remove unwanted lines
$workArray = PreProcessFileContent -fileContentOriginal  $fileContentOriginal

$workContent = $workArray | Select-String -Pattern @(".*M[0-9]+\-.*\.", "perform.*until", "perform\s*varying", ".*perform", "not at end perform", "end\-perform", "call\s*", "read\s*", "write\s*", "stop\s*run", "exec\s*sql", "end\-exec", "procedure\s*division")

$endTime = Get-Date
$timeDiff = $endTime - $startTime

# Log result
if (!$global:errorOccurred) {
    LogMessage -message ("--> Time eleapsed: " + $timeDiff.Seconds.ToString())
    LogMessage -message ("==> Completed successfully:" + $baseFileName )
}
else {
    LogMessage -message ("**> Failed with error:" + $baseFileName)
}
# stop-transcript

#"(?:ACCEPT|ADD|ALTER|CALL|CANCEL|CLOSE|COMMIT|COMPUTE|CONTINUE|DELETE|DISPLAY|DIVIDE|ENTRY|EVALUATE|EXHIBIT|EXIT|GENERATE|GOBACK|GO TO|IF|INITIALIZE|INSPECT|INVOKE|MERGE|MOVE|MULTIPLY|OPEN|PERFORM|READ|RELEASE|RETURN|REWRITE|ROLLBACK|SEARCH|SET|SORT|START|STOP RUN|STRING|SUBTRACT|TERMINATE THREADS|UNSTRING|WRITE)(.*?)(|?=END-EVALUATE|?=END-INVOKE|?=END-MULTIPLY|?=END-PERFORM|?=END-SUBTRACT|?=END-WRITE|?=ACCEPT|?=ADD|?=ALTER|?=CALL|?=CANCEL|?=CLOSE|?=COMMIT|?=COMPUTE|?=CONTINUE|?=DELETE|?=DISPLAY|?=DIVIDE|?=ENTRY|?=EVALUATE|?=EXHIBIT|?=EXIT|?=GENERATE|?=GOBACK|?=GO TO|?=IF|?=INITIALIZE|?=INSPECT|?=INVOKE|?=MERGE|?=MOVE|?=MULTIPLY|?=OPEN|?=PERFORM|?=READ|?=RELEASE|?=RETURN|?=REWRITE|?=ROLLBACK|?=SEARCH|?=SET|?=SORT|?=START|?=STOP RUN|?=STRING|?=SUBTRACT|?=TERMINATE THREADS|?=UNSTRING|?=WRITE|\\.)"

$workContent = $fileContentOriginal | Select-String -Pattern "\sexec\s(.*?)end-exec"
$workContent = $fileContentOriginal | Select-String -Pattern "\sIF\s(.*?)END-IF"
Write-Host  $workContent
$x = 1

