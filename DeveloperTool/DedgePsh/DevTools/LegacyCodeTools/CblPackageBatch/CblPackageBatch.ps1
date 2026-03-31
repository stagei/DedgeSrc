

function VerifyIfParagraph {
    param(
        $paragraphName
    )
    $isValidParagraph = $false

    if ($paragraphName.StartsWith("m090") -and $paragraphName.Length -gt 4) {
        $x = 1
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

function RemoveSqlEnvLine {
    param(
        $inputFile, $outputFile
    )
    # Replace [System.Text.Encoding]::GetEncoding(1252) with your desired encoding
    $lines = ([System.IO.File]::ReadAllLines($inputFile, [System.Text.Encoding]::GetEncoding(1252))) | Select-String -Pattern 'COPY.*SQLENV\.' -NotMatch
    # Do some processing on $lines if needed
    [System.IO.File]::WriteAllLines($outputFile, $lines, [System.Text.Encoding]::GetEncoding(1252))
}
function GetSqlTableNames {
    param(
        $line
    )
    try {

        $pattern = "(dbm|hst)`.`(.*?)`(\s|\)|$)" # Use a single pattern with alternatives and escape the dot with a backtick
        $matches1 = [regex]::Matches($line, $pattern) # Get all the matches as a collection

        $sqlTableNames = @( )
        if ($matches1.Count -gt 0) {
            foreach ($currentItemName in $matches1) {
                $temp = $currentItemName.Value
                if ($temp.Contains(")")) {
                    $temp = $temp.Replace(")", "")
                }
                if ($temp.Contains(";")) {
                    $temp = $temp.Replace(";", "")
                }
                $sqlTableNames += $temp.Trim().ToLower().Replace("'", "").Replace('"', "").Replace(",", "").Replace(")", "").Replace(":", "")
            }
        }
    }
    catch {
        $x = 1
    }
    return $sqlTableNames

}
function HandleCopyElements {
    param(
        $program, $copyfileonly, $DedgeFolder, $packcopyfiles, $executionPath
    )
    $cpylist = @()

    $copypath3 = $DedgeFolder + "\cbl\"
    $copypath2 = $DedgeFolder + "\cpy\"
    $copypath1 = $DedgeFolder + "\sys\cpy\"

    $cpylist += "<None Include=" + '"' + "cpy\" + $copyfileonly + '"' + " />"

    $cpy = $copypath1 + $copyfileonly
    $result = $null
    $result = copy-item -Path $cpy -Destination ($packcopyfiles + $copyfileonly.ToLower() ) -Force 2>&1
    if ($null -ne $result) {
        if ($result.Exception.Message.Contains("does not exist")) {
            $cpy = $copypath2 + $copyfileonly
            $result = $null
            $result = copy-item -Path $cpy -Destination ($packcopyfiles ) -Force  2>&1
            if ($null -ne $result) {
                if ($result.Exception.Message.Contains("does not exist")) {
                    $cpy = $copypath3 + $copyfileonly
                    $result = $null
                    $result = copy-item -Path $cpy -Destination ($packcopyfiles ) -Force  2>&1
                    if ($null -ne $result) {
                        if ($result.Exception.Message.Contains("does not exist")) {
                            $exists = Test-Path -Path ($packcopyfiles + $copyfileonly.ToLower())
                            if (! $exists) {
                                LogMessage -message ("**> Error cannot find copy element: " + $copyfileonly + " for program: " + $program + ". Execution Path: " + $executionPath)
                                $global:errorOccurred = 2
                            }
                        }
                    }
                }
            }
        }
    }
    return $cpylist
}

function LogMessage {
    param(
        $message
    )
    $dtLog = get-date -Format("yyyyMMdd").ToString()
    $logfile = "\\DEDGE.fk.no\erpprog\cobnt\" + $dtLog + "_CblPackage.log"
    $logfile1 = $global:logFolder + "\" + $dtLog + "_CblPackage.log"
    $dt = get-date -Format("yyyy-MM-dd HH:mm:ss,ffff").ToString()
    if ($global:programName -eq "" -or $global:programName -eq $null) {
        $logmsg = $dt + ": CblPackage :  " + $message
    }
    else {
        $logmsg = $dt + ": CblPackage." + $global:programName.Trim() + " : " + $message
    }

    Write-Host $logmsg
    Add-Content -Path $logfile -Value $logmsg
    Add-Content -Path $logfile1 -Value $logmsg
    if ($null -ne $global:logFolderSystem) {
        $logfile2 = $global:logFolderSystem + "\_CblPackage.log"
        Add-Content -Path $logfile2 -Value $logmsg
    }
}

function ConvertFromAnsi1252ToUtf8 {
    param (
        $exportTableName, $folderPath
    )
    # Specify the paths for the source ANSI file and the destination UTF-8 file

    $convertFilePath = $folderPath + "\" + $exportTableName + ".csv"

    $stream = New-Object System.IO.FileStream($convertFilePath, [System.IO.FileMode]::Open)
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::GetEncoding("Windows-1252"))
    $content = $reader.ReadToEnd()
    $reader.Close()
    $stream.Close()

    # Convert the content to UTF-8 encoding and write it to the destination file
    Set-Content -Path $convertFilePath -Value $content -Encoding UTF8

}
function ExportTableContentToFile {
    param (
        $exportTableName, $folderPath
    )
    if ($exportTableName -eq "tables") {
        $command = "db2 export to " + $folderPath + "\" + $exportTableName + ".csv of del modified by coldel;  select tabschema ,tabname ,remarks from syscat.tables where tabschema in('DBM','HST','LOG','CRM','TV')"
    }
    else {
        $command = "db2 export to " + $folderPath + "\" + $exportTableName + ".csv of del modified by coldel;  select * from dbm." + $exportTableName
    }
    return $command
}

function ContainsCobolEndVerb {
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
            if ($sourceLine.Trim().StartsWith($currentItemName)) {
                $startWithEndVerb = $true
            }
            $endVerbPos = $sourceLine.IndexOf($endverb)
            break
        }
    }

    return $containsEndVerb, $startWithEndVerb, $endverb, $endVerbPos
}

function ContainsCobolVerb {
    param($sourceLine)
    $containsVerb = $false
    $startWithVerb = $false
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
            if ($sourceLine.Trim().StartsWith($currentItemName)) {
                $startWithVerb = $true
            }
            $verbPos = $sourceLine.IndexOf($verb)
            break
        }
    }

    return $containsVerb, $StartWithVerb, $verb, $verbPos
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

        # if ( $line.Toupper().Contains("MOVE 'BSHBUOR'")) {
        #     $x = 1
        # }
        if ($counter -gt $procedureDivisionLinenumber -and $procedureDivisionLinenumber -gt 0 -and $procedureDivisionPeriodLinenumber -gt 0) {
            $containsCobolVerb, $verbAtStartOfLine, $verb, $verbPos = ContainsCobolVerb -sourceLine $line
            $containsEndVerb, $startWithEndVerb, $endverb, $endVerbPos = ContainsCobolEndVerb -sourceLine $line

            $verifiedParagraph = $false
            $verifiedParagraph = VerifyIfParagraph -paragraphName ($line.replace(".", "").Trim())
            if ($verifiedParagraph -and $firstParagraphLinenumber -eq 0) {
                $firstParagraphLinenumber = $counter
            }

            if ($line.trim() -eq "." -or $containsCobolVerb -or $containsEndVerb -or $accumulatedExpression.Trim() -eq ".") {
                if ($line.trim() -eq "perform") {
                    $x = 1
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
                        #     $x = 1
                        #     Write-Host "A:" $accumulatedExpression " L:"  $line
                        # }
                        # if ($accumulatedExpression.Contains("fetch c_fknr")) {
                        #     $x = 1
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
            # if ($accumulatedExpression.StartsWith("move ") -and $containsCobolVerb -eq $false -and $containsEndVerb -eq $false) {

            # }
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

function HandleProgram {
    param(
        $program, $DedgeFolder, $packprogram, $packcopyfiles, $packdepfiles, $executionPath
    )
    if ($program -eq "gmapayd") {
        $x = 1
    }
    $executionPath += " --> " + $program + ".cbl"
    $global:programName = $program + ".cbl"
    $localErrorOccurred = 0
    if ($program.ToLower().Trim() -eq "gmvmal1") {
        $x = 1
    }

    # Check if the program has already been handled
    if (Test-Path -Path ($packprogram + "\" + $program + ".cbl" )) {
        return
    }

    # LogMessage -message ("--> Handling program: " + $program)

    $sourcelist = @()
    $cpylist = @()

    # copy the program
    $lbrfilename = $DedgeFolder + "\cbl\" + $program + ".lbr"
    $gsfilename = $DedgeFolder + "\cbl\" + $program + ".gs"
    $progfilename = $DedgeFolder + "\cbl\" + $program + ".cbl"
    $gsImporFileName = $DedgeFolder + "\imp\" + $program + ".imp"

    $proxyfilename = $DedgeFolder + "\cbl\" + $program + "-proxy.cbl"
    $appfilename = $DedgeFolder + "\cbl\" + $program + "-app.cbl"

    if (-not (Test-Path -Path $progfilename -PathType Any)) {
        LogMessage -message ("**> Error during retrieving source code for: " + $program + ". File cannot be found: " + $progfilename + " . Execution Path: " + $executionPath)
        $machineName = $env:COMPUTERNAME.ToLower()
        if ($env:COMPUTERNAME.ToUpper() -eq "FK08C4QZ" `
                -or $env:COMPUTERNAME.ToUpper() -eq "FKIKT251" `
                -or $env:COMPUTERNAME.ToUpper() -eq "FKIKT958" `
                -or $env:COMPUTERNAME.ToUpper() -eq "FKIKT962") {
            # check if file exist in either of the folders K:\fkavd\utgatt or K:\fkavd\NT\HISTORIKK and log a message of the result
            $utgatt = "\\DEDGE.fk.no\fkavd\utgatt\cbl\" + $program + ".cbl"
            $historikk = "\\DEDGE.fk.no\fkavd\nt\historikk\cbl\" + $program + ".cbl"
            if (Test-Path -Path $utgatt -PathType Any) {
                LogMessage -message ("**> File exist in utgatt folder: " + $utgatt)
            }
            if (Test-Path -Path $historikk -PathType Any) {
                LogMessage -message ("**> File exist in historikk folder: " + $historikk)
            }
            # Log if file does not exist in either of the folders K:\fkavd\utgatt or K:\fkavd\NT\HISTORIKK
            if (-not (Test-Path -Path $utgatt -PathType Any) -and -not (Test-Path -Path $historikk -PathType Any)) {
                LogMessage -message ("**> File does not exist in either of the folders K:\fkavd\utgatt or K:\fkavd\NT\HISTORIKK")
            }
            # Check if int file exist in either of the folders N:\COBNT
            $intfile = "\\DEDGE.fk.no\erpprog\cobnt\" + $program + ".int"
            if (Test-Path -Path $intfile -PathType Any) {
                LogMessage -message ("**> Warning - Object file exist in cobnt folder: " + $intfile)
            }
            else {
                LogMessage -message ("**> Error - Object file does NOT exist in cobnt folder: " + $intfile)
            }
        }

        $global:errorOccurred = 2
        $localErrorOccurred = 2
        return $null, $null, $null, $null, $localErrorOccurred
    }
    else {
        RemoveSqlEnvLine -inputFile $progfilename -outputFile ($packprogram + "\" + $program + ".cbl")
        # copy-item $progfilename $packprogram -Force 2>&1
        $sourcelist += "<Compile Include=" + '"' + $program.ToLower() + ".cbl" + '"' + " />"
    }

    if (Test-Path -Path $lbrfilename -PathType Any) {
        copy-item $lbrfilename  $packcopyfiles -Force 2>&1
        $cpylist += "<None Include=" + '"' + "cpy\" + $program.ToLower() + ".lbr" + '"' + " />"
    }

    if (Test-Path -Path $gsfilename -PathType Any) {
        copy-item $gsfilename   $packprogram -Force 2>&1
        $cpylist += "<Content Include=" + '"' + $program.ToLower() + ".gs" + '"' + " />"
    }

    if (Test-Path -Path $proxyfilename -PathType Any) {
        copy-item $proxyfilename   $packprogram -Force 2>&1
        $sourcelist += "<Compile Include=" + '"' + $program.ToLower() + "-proxy.cbl" + '"' + " />"
    }

    if (Test-Path -Path $appfilename -PathType Any) {
        copy-item $appfilename   $packprogram -Force 2>&1
        $sourcelist += "<Compile Include=" + '"' + $program.ToLower() + "-app.cbl" + '"' + " />"
    }

    # copy the copy files
    $srcOriginal = Get-Content $progfilename

    $gsImporFileSrc = @()
    if (Test-Path -Path $gsImporFileName -PathType Any) {
        $gsImporFileSrc = Get-Content $gsImporFileName
    }

    $workArray, $procedureContent, $fileSectionLineNumber, $workingStorageLineNumber, $fileSectionContent = PreProcessFileContent -fileContentOriginal  $srcOriginal
    $src = $workArray

    # Handle sql tables
    $sqlTables = @()
    $sqlTableSrc = @()
    $sqlTableSrc1 = @()
    $sqlTableSrc2 = @()
    # find all matches of dbm. and hst. and add each to a seperate itme into array

    $sqlTableSrc1 = $src | Select-String -Pattern "(dbm\.|hst\.|log\.|crm\.|tv\.)(.*?)\s" -AllMatches

    foreach ($item in $sqlTableSrc1.Matches) {
        $workString = $item.Value
        $workString = $workString.Trim().Replace("'", "").Replace('"', "").Replace(",", "").Replace(")", "").Replace(":", "").TrimEnd(".")
        $pos = $workString.IndexOf("(")
        if ($pos -gt 0) {
            $workString = $workString.Substring(0, $pos).Trim()
        }
        $sqlTables += $workString.ToUpper()
    }

    # try {
    #     $sqlTableSrc2 += $src | Select-String -Pattern "hst\.(.*?)\s" -AllMatches
    # }
    # catch {
    #     $sqlTableSrc2 = $null
    # }
    # try {
    #     $sqlTableSrc = $sqlTableSrc1.Matches + $sqlTableSrc2.Matches
    # }
    # catch {
    #     $x = 1
    # }
    # $sqlTableSrc = $sqlTableSrc | Sort-Object -Unique
    # foreach ($item in $sqlTableSrc) {
    #     $item = $item.Value.Trim().Replace("'", "").Replace('"', "").Replace(",", "").Replace(")", "").Replace(":", "").TrimEnd(".")
    #     $pos = $item.IndexOf("(")
    #     if ($pos -gt 0) {
    #         $item = $item.Substring(0, $pos).Trim()
    #     }
    #     $sqlTables += $item.ToUpper()
    # }
    # $sqlTables = $sqlTables | Sort-Object -Unique

    # Handle copy files
    $copyfiles = $src | select-string "^.*copy\s"
    $counter = 0
    foreach ($c in $copyfiles) {
        $pos = $c.Line.ToUpper().IndexOf("COPY ")
        if ($pos -lt 0) {
            continue
        }

        $pos2 = $c.Line.IndexOf("*")
        if ($pos2 -lt $pos -and $pos2 -ge 0 ) {
            continue
        }
        $c.Line = $c.Line.Substring($pos)
        $copyfileonly = $c.Line

        # I want to find the last \ in string
        $pos = $copyfileonly.LastIndexOf("\")
        $copyfileonly = $copyfileonly.Substring($pos + 1)

        if ($copyfileonly.ToLower().Contains(".cpy") -or $copyfileonly.ToLower().Contains(".cpb") -or $copyfileonly.ToLower().Contains(".dcl") -or $copyfileonly.ToLower().Contains(".gs")) {

            $pos = 0
            $pos = $copyfileonly.IndexOf(".")
            if ($pos -le 0) {
                continue
            }

            if ($copyfileonly.ToLower().Contains(".gs")) {
                $pos += 3
            }
            else {
                $pos += 4
            }

            $copyfileonly = $copyfileonly.Substring(0, $pos)

            # Check Quote occurs before Call
            $pos1 = $copyfileonly.IndexOf("'")
            $pos2 = $copyfileonly.IndexOf('"')
            if ($pos2 -gt $pos1) {
                $pos1 = $pos2
            }

            $copyfileonly = $copyfileonly.Substring($pos1 + 1)
            if ($copyfileonly.ToUpper().StartsWith("COPY ")) {
                $copyfileonly = $copyfileonly.Substring(5).Trim()
            }
            $copyfileonly = $copyfileonly.Trim()
            if ($copyfileonly.ToUpper() -eq ".DCL" -or $copyfileonly.ToUpper() -eq ".CPY" -or $copyfileonly.ToUpper() -eq ".GS" -or $copyfileonly.ToUpper() -eq ".CPB") {
                Continue
            }

            $cpylist += HandleCopyElements -program $program -copyfileonly $copyfileonly -DedgeFolder $DedgeFolder -packcopyfiles $packcopyfiles -executionPath $executionPath

            if ($copyfileonly.ToLower() -eq "dbafakt.cpy") {
                $copyfileonly = "sah.dcl"
                $cpylist += HandleCopyElements -program $program -copyfileonly $copyfileonly -DedgeFolder $DedgeFolder -packcopyfiles $packcopyfiles -executionPath $executionPath
                $copyfileonly = "sal.dcl"
                $cpylist += HandleCopyElements -program $program -copyfileonly $copyfileonly -DedgeFolder $DedgeFolder -packcopyfiles $packcopyfiles -executionPath $executionPath
            }
            elseif ($copyfileonly.ToLower() -eq "drarrap.cpy") {
                $copyfileonly = "drbrrap.cpy"
                $cpylist += HandleCopyElements -program $program -copyfileonly $copyfileonly -DedgeFolder $DedgeFolder -packcopyfiles $packcopyfiles -executionPath $executionPath
            }
            elseif ($copyfileonly.ToLower() -eq "Dedgetfp.cpy") {
                $copyfileonly = "gmautils.cpy"
                $cpylist += HandleCopyElements -program $program -copyfileonly $copyfileonly -DedgeFolder $DedgeFolder -packcopyfiles $packcopyfiles -executionPath $executionPath
            }
            elseif ($copyfileonly.ToLower() -eq "tm001.cpy") {
                $copyfileonly = "gmautils.cpy"
                $cpylist += HandleCopyElements -program $program -copyfileonly $copyfileonly -DedgeFolder $DedgeFolder -packcopyfiles $packcopyfiles -executionPath $executionPath
            }
            elseif ($copyfileonly.ToLower() -eq "tm007.cpy") {
                $copyfileonly = "gmautils.cpy"
                $cpylist += HandleCopyElements -program $program -copyfileonly $copyfileonly -DedgeFolder $DedgeFolder -packcopyfiles $packcopyfiles -executionPath $executionPath
            }
        }
    }

    # copy the dependencies
    $callArray = @()
    # $dependencies = $src | Select-String -Pattern "(.\ *call\ )|( using )" -AllMatches
    $dependencies = $src | Select-String -Pattern "^.*call" -AllMatches

    $counter = 0
    $dependencies = $dependencies  | Sort-Object -Unique

    foreach ($c in $dependencies) {

        if ($c.Line.ToUpper().Contains(" DIVISION") `
                -or $c.Line.ToUpper().Contains("CALL X") `
                -or $c.Line.ToUpper().Contains(" ENTRY ") `
                -or $c.Line.ToUpper().Contains(" DBM.") `
                -or $c.Line.ToUpper().Contains(" HST.") `
                -or $c.Line.ToUpper().Contains("(DBM.") `
                -or $c.Line.ToUpper().Contains("(HST.") `
                -or $c.Line.ToUpper().Contains("TIMELOCALTOGM") `
                -or $c.Line.ToUpper().Contains("DSGRUN") `
                -or $c.Line.ToUpper().Contains("SQLGSTAR") `
                -or $c.Line.ToUpper().Contains("DYNAMICSTDCALL") `
                -or $c.Line.ToUpper().Contains("SHELLEXECUTE") `
                -or $c.Line.ToUpper().Contains("WINAPI") `
                -or $c.Line.ToUpper().Contains("SQLGISIG") `
                -or $c.Line.ToUpper().Contains("GET-SRVC-") `
                -or $c.Line.ToUpper().Contains("DT_UKE_") `
                -or $c.Line.ToUpper().Contains("DT_DATO_") `
                -or $c.Line.ToUpper().Contains("GENERATEEXCEL") `
                -or $c.Line.ToUpper().Contains("HELLOWORLD") `
                -or $c.Line.ToUpper().Contains(" FLX ") `
                -or $c.Line.ToUpper().Contains("PANELS2") `
                -or $c.Line.ToUpper().Contains("PC_PRINTER_") `
                -or $c.Line.ToUpper().Contains("LNPUBLIC") `
                -or $c.Line.ToUpper().Contains("VALIDATE") `
                -or $c.Line.ToUpper().Contains("-LIST-ITEM") `
                -or $c.Line.ToUpper().Contains("SENDSMS") `
                -or $c.Line.ToUpper().Contains("APIGUI") `
                -or $c.Line.ToUpper().Contains("LN_NSFITEMSETTEXT")`
                -or $c.Line.ToUpper().Contains("LN_NSFITEMTEXTEQUAL")`
                -or $c.Line.ToUpper().Contains("LN_NSFNOTECLOSE")`
                -or $c.Line.ToUpper().Contains("LN_NSFNOTECOMPUTEWITHFORM")`
                -or $c.Line.ToUpper().Contains("LN_NSFNOTECREATE")`
                -or $c.Line.ToUpper().Contains("LN_NSFNOTEOPEN")`
                -or $c.Line.ToUpper().Contains("LN_NSFNOTEUPDATE")`
                -or $c.Line.ToUpper().Contains("LN_OSLOADSTRING")`
                -or $c.Line.ToUpper().Contains("LN_CONVERTFLOATTOTEXT")`
                -or $c.Line.ToUpper().Contains("LN_CONVERTTIMEDATETOTEXT")`
                -or $c.Line.ToUpper().Contains("LN_ERRORGETINFO")`
                -or $c.Line.ToUpper().Contains("LN_NIFCLOSECOLLECTION")`
                -or $c.Line.ToUpper().Contains("LN_NIFFINDDESIGNNOTE")`
                -or $c.Line.ToUpper().Contains("LN_NIFOPENCOLLECTION")`
                -or $c.Line.ToUpper().Contains("LN_NIFREADENTRIES")`
                -or $c.Line.ToUpper().Contains("LN_NIFUPDATECOLLECTION")`
                -or $c.Line.ToUpper().Contains("LN_NSFDBCLOSE")`
                -or $c.Line.ToUpper().Contains("LN_NSFDBOPEN")`
                -or $c.Line.ToUpper().Contains("LN_NSFITEMINFO")`
                -or $c.Line.ToUpper().Contains("LN_OSLOCKBLOCK")`
                -or $c.Line.ToUpper().Contains("LN_OSLOCKOBJECT")`
                -or $c.Line.ToUpper().Contains("LN_OSMEMFREE")`
                -or $c.Line.ToUpper().Contains("LN_OSUNLOCKOBJECT")`
                -or $c.Line.ToUpper().Contains("LN_NOTESINIT")`
                -or $c.Line.ToUpper().Contains("LN_ASCII_Z")`
                -or $c.Line.ToUpper().Contains("LN_OSPATHNETCONSTRUCT")`
                -or $c.Line.ToUpper().Contains("LN_SETDEFAULTFONTID")`
                -or $c.Line.ToUpper().Contains("LN_NOTESTERM")`
                -or $c.Line.ToUpper().Contains("LN_ITEMSETDECIMAL")`
                -or $c.Line.ToUpper().Contains("LN_NSFITEMLONGCOMPARE")`
                -or $c.Line.ToUpper().Contains("DICRHASH")`
                -or $c.Line.ToUpper().Contains("LN_NSFITEMLONGCOMPARE")`
                -or $c.Line.ToUpper().Contains("=")`
                -or $c.Line.ToUpper().Contains("MD5_FILEHEXHASH")) {
            continue
        }

        # if ($c.Line.Length -gt 6) {
        #     $line = $c.Line.Substring(6)
        # }
        # else {
            $line = $c.Line
        # }
        $counter += 1
        if ($counter -eq 40) {
            $x = 1
        }

        $pos = $line.IndexOf("*>")
        if ($pos -gt 0) {
            # Removes comment at end of line
            $line = $line.Substring(0, $pos)
        }

        if ($line.Length -le 6) {
            # Skip to next element only room for linenumbers from 0..6
            continue
        }

        if ($null -eq $line -or $line.Length -eq 0) {
            continue
        }

        # if ($line.ToUpper().Contains("DYNAMICSTD") -or `
        #         $line.ToUpper().Contains("DYNAMICSTD") -or `
        #         $line.ToUpper().Contains("XF5")) {
        #     continue
        # }

        if ($line.Trim().Substring(0, 1) -eq "*") {
            # Skip to next element
            continue
        }

        if ($line.Trim().Length -eq 0) {
            # Skip to next element if null aftger removing first 6 characthers
            continue
        }

        # $pos1 = $line.IndexOf("USING ")
        # $pos2 = $line.IndexOf("'")
        # $pos3 = $line.IndexOf('"')
        # if ($pos3 -gt $pos2) {
        #     $pos2 = $pos3
        # }
        # if ($pos1 -lt $pos2) {
        #     continue
        # }

        # Check Quote occurs before Call
        $workLine = $line.ToUpper().Trim()
        if (-Not $workLine.StartsWith("CALL ")) {
            Continue
        }
        $workLine = $workLine.Substring(5).Trim().Replace("'", " ").Replace('"', " ").Replace(",", "").Replace(")", "").Replace(":", "").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Trim()
        $workLine = $workLine.Split(" ")[0]

        $depfileonly = $workLine.Trim()

        if ($depfileonly.Trim().Length -eq 0) {
            Continue
        }

        if ($depfileonly.startsWith("CBL_") `
                -or $depfileonly.startsWith("FKPROC") `
                -or $depfileonly.startsWith("WIN32") `
                -or $depfileonly.Contains("DSUSRVAL") `
                -or $depfileonly.Contains("PROGRAMID") `
                -or $depfileonly.startsWith("DB2") `
                -or $depfileonly.startsWith("SLEEP") `
                -or $depfileonly.Contains("SET-BUTTON-STATE") `
                -or $depfileonly.Contains("COB32API") `
                -or $depfileonly.Contains("DISABLE-OBJECT") `
                -or $depfileonly.Contains("ENABLE-OBJECT") `
                -or $depfileonly.Contains("REFRESH-OBJECT")`
                -or $depfileonly.Contains("HIDE-OBJECT")  `
                -or $depfileonly.Contains("SQLGINTP")  `
                -or $depfileonly.Contains("HIDE-OBJECT") `
                -or $depfileonly.Contains("SET-FOCUS") `
                -or $depfileonly.Contains("SET-MOUSE-SHAPE") `
                -or $depfileonly.Contains("SHOW-OBJECT") `
                -or $depfileonly.Contains("VENT_SEK") `
                -or $depfileonly.Contains("CLEAR-OBJECT") `
                -or $depfileonly.Contains("CC1") `
                -or $depfileonly.Contains("DSRUN") `
                -or $depfileonly.Contains("SET-FIRST-WINDOW") `
                -or $depfileonly.Contains("INVOKE-MESSAGE-BOX") `
                -or $depfileonly.Contains("SET-LIST-ITEM-STATE") `
                -or $depfileonly.Contains("SET-OBJECT-LABEL") `
                -or $depfileonly.Contains("SET-TOP-LIST-ITEM") `
                -or $depfileonly.Contains("VENT_KVARTSEK") `
                -or $depfileonly.Contains("SQLGINTR")) {
            continue
        }
        if ($depfileonly.ToLower().Trim() -eq "gmvmal1") {
            $x = 1
        }
        $callArray += $depfileonly
    }

    $dependencies2 = $src | Select-String -Pattern "^.*move.*to.*scrn" -AllMatches
    foreach ($item in $dependencies2) {
        $tempStr = $item.Line
        if ($tempStr.ToLower().Trim() -eq "gmvmal1") {
            $x = 1
        }
        $pos1 = $tempStr.IndexOf('"')
        $pos2 = $tempStr.IndexOf("'")
        $useQuote = "None"
        if ($pos1 -gt 0 -and $pos2 -gt 0 -and $pos1 -lt $pos2) {
            $useQuote = "Double"
        }
        elseif ($pos2 -gt 0 -and $pos1 -gt 0 -and $pos2 -lt $pos1) {
            $useQuote = "Single"
        }
        elseif ($pos1 -gt 0 -and $pos2 -eq -1) {
            $useQuote = "Double"
        }
        elseif ($pos2 -gt 0 -and $pos1 -eq -1) {
            $useQuote = "Single"
        }

        $tempSplit = $null
        if ($useQuote -eq "Double") {
            $tempSplit = $tempStr.Split('"')
            $depfileonly = $tempSplit[1].Trim()
            if ($program -ne $depfileonly) {
                $callArray += $depfileonly
            }
        }
        elseif ($useQuote -eq "Single") {
            $tempSplit = $tempStr.Split("'")
            $depfileonly = $tempSplit[1].Trim()
            if ($program -ne $depfileonly) {
                $callArray += $depfileonly
            }
        }
        else {
            $x = 1
        }
    }

    if ($gsImporFileSrc.Count -gt 0) {
        $dependencies3 = $gsImporFileSrc | Select-String -Pattern "^.* external.*" -AllMatches
        foreach ($item in $dependencies3) {
            $tempStr = $item.Line
            if ($tempStr.ToLower().Trim() -eq "gmvmal1") {
                $x = 1
            }

            $pos1 = $tempStr.IndexOf('"')
            $pos2 = $tempStr.IndexOf("'")
            $useQuote = "None"
            if ($pos1 -gt 0 -and $pos2 -gt 0 -and $pos1 -lt $pos2) {
                $useQuote = "Double"
            }
            elseif ($pos2 -gt 0 -and $pos1 -gt 0 -and $pos2 -lt $pos1) {
                $useQuote = "Single"
            }
            elseif ($pos1 -gt 0 -and $pos2 -eq -1) {
                $useQuote = "Double"
            }
            elseif ($pos2 -gt 0 -and $pos1 -eq -1) {
                $useQuote = "Single"
            }

            $tempSplit = $null
            if ($useQuote -eq "Double") {
                $tempSplit = $tempStr.Split('"')
                $depfileonly = $tempSplit[1].ToLower().Trim()
                if ($program -ne $depfileonly) {
                    $callArray += $depfileonly
                }
            }
            elseif ($useQuote -eq "Single") {
                $tempSplit = $tempStr.Split("'")
                $depfileonly = $tempSplit[1].ToLower().Trim()
                if ($program -ne $depfileonly) {
                    $callArray += $depfileonly
                }
            }
            else {
                $x = 1
            }

        }
    }

    $callArray = $callArray | Sort-Object -Unique
    foreach ($item in $callArray) {
        $handleErrorOccurred = 0
        $callArray2, $sourcelist2, $cpylist2, $sqlTables2, $handleErrorOccurred = HandleProgram -program $item -DedgeFolder $DedgeFolder -packprogram $packprogram -packcopyfiles $packcopyfiles -packdepfiles $packdepfiles -executionPath $executionPath
        # if ($handleErrorOccurred -eq 2) {
        #     # $localErrorOccurred = 2
        #     # return $null, $null, $null, $null, $localErrorOccurred
        #     LogMessage -message ("**> Packing error occurred during handling of program: " + $item + ". Previous program: " + $executionPath)
        # }

        if ($null -ne $callArray2) {
            $callArray += $callArray2
        }
        if ($null -ne $cpylist2) {
            $cpylist += $cpylist2
        }
        if ($null -ne $sourcelist2) {
            $sourcelist += $sourcelist2
        }
        if ($null -ne $sqlTables2) {
            $sqlTables += $sqlTables2
        }
    }
    if ($null -ne $callArray) {
        return $callArray, $sourcelist, $cpylist, $sqlTables, $localErrorOccurred
    }
    else {
        return $null, $sourcelist, $cpylist, $sqlTables, $localErrorOccurred
    }

}

function CblPackage {
    param(
        [Parameter(Mandatory = $true)][string]$program,
        [Parameter(Mandatory = $true)][string]$outputFolder,
        [Parameter(Mandatory = $true)][string]$tmpFolder,
        [Parameter(Mandatory = $true)][string]$DedgeFolder,
        [Parameter(Mandatory = $true)][string]$logFolder,
        [Parameter(Mandatory = $true)][string]$delsystem
    )

    $global:programName = ""
    LogMessage -message ("--> Subsystem " + $delsystem + " - Packing program: " + $program)

    $global:logFolder = $logFolder
    $global:errorOccurred = 0

    $packcopyfiles = $outputFolder + "\cpy\"
    $packdepfiles = $outputFolder
    $packprogram = $outputFolder
    $exists = Test-Path -Path $packprogram
    if (! $exists) {
        new-item -ItemType Directory -Path $packprogram | Out-Null
    }

    $exists = Test-Path -Path $packcopyfiles
    if (! $exists) {
        new-item -ItemType Directory -Path $packcopyfiles | Out-Null
    }

    $handleErrorOccurred = 0
    $callArray, $sourcelist, $cpylist, $sqlTables, $handleErrorOccurred = HandleProgram -program $program -DedgeFolder $DedgeFolder -packprogram $packprogram -packcopyfiles $packcopyfiles -packdepfiles $packdepfiles -executionPath $delsystem
    $global:programName = ""
    if ($handleErrorOccurred -eq 2) {
        LogMessage -message ("**> Main packing error occurred during handling of program: " + $program)
    }

    # if ($null -ne $callArray) {
    #     LogMessage -message ("**> Array not empty when finished: " + $program)
    #     $global:errorOccurred = 1
    # }

    if ($global:errorOccurred -eq 1) {
        LogMessage -message ("**> Error occurred during packaging for program: " + $program)
    }
    else {
        LogMessage -message ("==> Completed packaging for program: " + $program)
    }

    if ($errorOccurred -eq 1) {
        Start-Sleep -Milliseconds 250
        LogMessage -message ("**> Error occurred in CblPackage.ps1 for program: $program")
    }
    elseif ($errorOccurred -eq 2) {
        Start-Sleep -Milliseconds 250
        LogMessage -message ("==> Elements related to program have been retired or deleted: " + $program + ".cbl")
    }

    return $sourcelist, $cpylist, $sqlTables

}

function HandleSubSystem ($workArraySystem, $delsystem, $workFolder, $DedgeFolder, $tmpFolder, $outputFolder, $allArray) {
    $totalSourcelist, $totalCpylist, $totalSqlTables = @()
    $workFolder = $outputFolder + "\" + $delsystem
    $global:logFolderSystem = $workFolder
    # if ($delsystem -ne "BS") {
    #     return $totalSqlTables, $allArray
    # }

    if (-not (Test-Path -Path $workFolder -PathType Container)) {
        New-Item -Path $workFolder -ItemType Directory  | Out-Null
    }

    foreach ($currentItemName in $workArraySystem) {
        if ($currentItemName.Contains("-") -or $currentItemName.Contains("_") -or $currentItemName.Contains("FELLES")) {
            Continue
        }
        # if (!$currentItemName.ToUpper().Contains("BSBANGO")) {
        #     Continue
        # }

        $pos = $currentItemName.IndexOf(".")
        $program = $currentItemName.Substring(0, $pos).ToLower().Trim()

        $sourcelist, $cpylist, $sqlTables = @()

        if ($delsystem -eq "_Other") {
            if ($allArray | select-string -pattern $program -quiet) {
                Continue
            }
        }

        if (-not (Test-Path -Path $workFolder -PathType Container)) {
            New-Item -Path $workFolder -ItemType Directory  | Out-Null
        }

        $sourcelist, $cpylist, $sqlTables = @()
        $sourcelist, $cpylist, $sqlTables = CblPackage -program $program -outputFolder $workFolder -tmpFolder $tmpFolder -DedgeFolder $DedgeFolder -logFolder $global:logFolder -delsystem $delsystem

        $totalSourcelist += $sourcelist
        $totalCpylist += $cpylist
        $totalSqlTables += $sqlTables

        $allArray += $currentItemName
    }

    # $sourcelist1, $cpylist1, $sqlTables1 = @()
    # $sourcelist1, $cpylist1, $sqlTables1 = CblPackage -program "gmstart" -outputFolder $workFolder -tmpFolder $tmpFolder -DedgeFolder $DedgeFolder -logFolder $global:logFolder -delsystem $delsystem

    # $totalSourcelist += $sourcelist1
    # $totalCpylist += $cpylist1
    # $totalSqlTables += $sqlTables1
    # $allArray += "gmstart"

    $totalCpylist = $totalCpylist | Sort-Object -Unique
    $totalSourcelist = $totalSourcelist | Sort-Object -Unique

    $tempList = @()
    foreach ($item in $totalSourcelist) {
        # add new line to each item
        $tempList += $item + "`n"
    }
    $totalSourcelist = $tempList

    $tempList = @()

    foreach ($item in $totalCpylist) {
        # add new line to each item
        $tempList += $item + "`n"
    }
    $totalCpylist = $tempList

    $totalSourcelist += "<None Include=" + '"' + "_" + $delsystem.Trim() + ".sqltables" + '"' + " />"
    $totalSourcelist += "<None Include=" + '"_CblPackage.log"' + " />"

    $doc = get-content -Path ".\Template.cblproj"
    $doc = $doc.Replace("[guid]", [guid]::NewGuid())
    $doc = $doc.Replace("[sourcelist]", $totalSourcelist)
    $doc = $doc.Replace("[cpylist]", $totalCpylist)

    $projectFileName = $workFolder + "\_" + $delsystem.ToUpper() + ".cblproj"
    set-content -Path $projectFileName -Value $doc

    $totalSqlTables = $totalSqlTables | Sort-Object -Unique
    $systemSqltablesFilename = $workFolder + "\_" + $delsystem.Trim() + ".sqltables"
    Set-Content -Path $systemSqltablesFilename -Value $totalSqlTables -Force
    return $totalSqlTables, $allArray
}

# Get the folder containing the script
$scriptFolder = $PSScriptRoot
$PSWorkPath = $env:PSWorkPath

# Define the folder path you want to check and create
$srcRootFolder = "$PSWorkPath\CblPackage"
$DedgeFolder = "$PSWorkPath\CblPackage\Dedge"
$DedgePshFolder = "$PSWorkPath\CblPackage\DedgePsh"

$db2devFolder = "K:\fkavd\Dedge2\src"

$DedgeCblFolder = $DedgeFolder + "\cbl"
$outputFolder = "$PSWorkPath\CblPackage\Content"
$tmpFolder = "$PSWorkPath\CblPackage\tmp"
$cobdokFolder = "$PSWorkPath\CblPackage\tmp\cobdok"

if (-not (Test-Path -Path $DedgeFolder -PathType Container)) {
    # Folder doesn't exist, so create it
    New-Item -Path $DedgeFolder -ItemType Directory
}

# Remove folders
Remove-Item -Path $outputFolder -Recurse -Force -ErrorAction SilentlyContinue

# Check if the folder exists
if (-not (Test-Path -Path $cobdokFolder -PathType Container)) {
    # Folder doesn't exist, so create it
    New-Item -Path $cobdokFolder -ItemType Directory
}

# Check if the folder exists
if (-not (Test-Path -Path $outputFolder -PathType Container)) {
    # Folder doesn't exist, so create it
    New-Item -Path $outputFolder -ItemType Directory
}

Push-Location
Set-Location -Path $DedgeFolder
$DedgeFolder = (Get-Location).Path
Pop-Location

Push-Location
Set-Location -Path $tmpFolder
$tmpFolder = (Get-Location).Path
Pop-Location

Push-Location
Set-Location -Path $outputFolder
$outputFolder = (Get-Location).Path
Pop-Location
$global:logFolder = $outputFolder
$global:logFolderSystem = $null

LogMessage -message "Start CblPackage.ps1"
LogMessage -message "--> Copying changed files from $db2devFolder to $DedgeFolder"
xcopy.exe $db2devFolder $DedgeFolder /Y /D /Q /S

Push-Location
Set-Location -Path $DedgeCblFolder
$DedgeCblFolder = (Get-Location).Path
Pop-Location

Push-Location
Set-Location -Path $cobdokFolder
$cobdokFolder = (Get-Location).Path
Pop-Location

Push-Location
Set-Location -Path $srcRootFolder
$srcRootFolder = (Get-Location).Path
Pop-Location

$array = @()

$result = "del " + $cobdokFolder + "\" + "*.csv /F /Q"
$array += $result

$result = "db2 connect to cobdok"
$array += $result

$result = ExportTableContentToFile -exportTableName "delsystem" -folderPath $cobdokFolder
$array += $result

$result = "db2 connect to basistst"
$array += $result

$result = ExportTableContentToFile -exportTableName "tables" -folderPath $cobdokFolder
$array += $result

$result = "exit"
$array += $result

$outPutFile = $cobdokFolder + "\ExportTableContentToFile.cmd"
set-content -Path $outPutFile  -Value $array
db2cmd.exe -w $outPutFile
Write-Output "--> CobDok Export Completed"

ConvertFromAnsi1252ToUtf8 -exportTableName  "delsystem" -folderPath $cobdokFolder

ConvertFromAnsi1252ToUtf8 -exportTableName "tables" -folderPath $cobdokFolder

$workArrayAll = @()
$descArray = Get-ChildItem -Path $DedgeCblFolder -Filter "*.cbl" -Name
foreach ($currentItemName in $descArray) {
    if (!$currentItemName.Contains("-")) {
        $pos = $currentItemName.IndexOf(".")
        $addString = $currentItemName.Substring(0, $pos).ToLower().Trim()
        $workArrayAll += $addString
    }
}

$csvDelsystemArray = Import-Csv ($cobdokFolder + "\delsystem.csv") -Header system, delsystem, tekst -Delimiter ';'
$systemArray = $csvDelsystemArray | Where-Object { $_.system.Contains("FKAVDNT") }
$allArray = @()
$allSqlTables = @()

foreach ($system in $systemArray) {

    $workArraySystem = @()
    $delsystem = $system.delsystem
    $filter = $delsystem + "*.cbl"
    $workArraySystem = Get-ChildItem -Path $DedgeCblFolder -Filter $filter -Name

    $totalSqlTables, $allArray = HandleSubSystem -workArraySystem $workArraySystem -delsystem $delsystem -workFolder $workFolder -DedgeFolder $DedgeFolder -tmpFolder $tmpFolder -outputFolder $outputFolder -allArray $allArray
    $allSqlTables += $totalSqlTables
}

$workArraySystem = @()
$delsystem = "_Other"
$workArraySystem = Get-ChildItem -Path $DedgeCblFolder -Filter "*.cbl" -Name

$totalSqlTables, $allArray = HandleSubSystem -workArraySystem $workArraySystem -delsystem $delsystem -workFolder $workFolder -DedgeFolder $DedgeFolder -tmpFolder $tmpFolder -outputFolder $outputFolder -allArray $allArray
$allSqlTables += $totalSqlTables

$global:logFolderSystem = $null
# merge all sqltables files into one large
$allSqlFileNames = Get-ChildItem -Path $outputFolder -Filter "*.sqltables" -Name
$systemSqltablesFilename = $outputFolder + "\_All.sqltables"
Set-Content -Path $systemSqltablesFilename -Value "" -Force
foreach ($currentItemName in $allSqlFileNames) {
    $workSqlTablesFilename = $outputFolder + "\" + $currentItemName
    $workSqlTablesContent = Get-Content -Path $workSqlTablesFilename
    $systemSqlTablesContent = Get-Content -Path $systemSqltablesFilename
    if ($systemSqlTablesContent -eq "") {
        $systemSqlTablesContent = @()
    }
    $systemSqlTablesContent += $workSqlTablesContent
    $systemSqlTablesContent = $systemSqlTablesContent | Sort-Object -Unique
    Set-Content -Path $systemSqltablesFilename -Value $systemSqlTablesContent -Force
}

$unusedTables = @()
$allSqlTablesContent = Get-Content -Path $systemSqltablesFilename
$csvTablesArray = Import-Csv ($cobdokFolder + "\tables.csv") -Header tabschema , tabname , remarks -Delimiter ';'

foreach ($Item in $csvTablesArray) {
    $tableName = $Item.tabschema.Trim().ToUpper() + "." + $Item.tabname.Trim().ToUpper()

    $result = $allSqlTablesContent | select-string -pattern $tableName -quiet
    if (!$result) {
        $unusedTables += $tableName
    }
}

$systemUnusedSqltablesFilename = $outputFolder + "\_Unused.sqltables"
Set-Content -Path $systemUnusedSqltablesFilename -Value $unusedTables -Force

