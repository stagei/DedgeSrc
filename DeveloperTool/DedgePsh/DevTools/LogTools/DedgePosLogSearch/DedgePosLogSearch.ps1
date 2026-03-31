# add inputparameter to script to be able to run script from commandline
param(
    $skipTerminalLogs = "0", $skipWrapperlog = "1", $skipSqllog = "1")

function InitFilter ($choice, $searchString, $logFolder) {

    $searchString = $searchString.ToString().Trim()
    $result = $null
    $trxResult = $null

    # First handle IO Exception search differently
    if ($choice -eq "9") {
        $result = @()
        $trxResult = @()

        # Get all files and process each one
        $logFiles = Get-ChildItem -Path $logFolder -Filter "*.log"

        foreach ($logFile in $logFiles) {
            # Get all lines with either pattern
            $myMatches1 = Select-String -Path $logFile.FullName -Pattern 'IOException' -SimpleMatch
            $myMatches2 = Select-String -Path $logFile.FullName -Pattern 'ConnectionClosed' -SimpleMatch
            $myMatches = $myMatches1 + $myMatches2
            $myLines = $myMatches | ForEach-Object { $_.Line }
            $myLines = $myLines | Sort-Object -Unique
            # Shrink array until a line contains IOException
            while ($myLines.Count -gt 0 -and -not ($myLines[0] -match "IOException")) {
                $myLines = $myLines[1..($myLines.Count - 1)]
            }

            $lookForConnectionClosed = $false
            $prevTerminalId = ""
            foreach ($line in $myLines) {
                if ($lookForConnectionClosed) {
                    if ($line -match "TerminalId: (BT_\w+)") {
                        $prevTerminalId = $Matches[1]
                        $result += $prevTerminalId
                        Write-Host "Found connection closed for terminal: " + $prevTerminalId
                        $lookForConnectionClosed = $false
                    }
                }
                else {
                    if ($line -match "IOException") {
                        $lookForConnectionClosed = $true
                    }
                }
            }
        }

        $result = $result | Sort-Object -Unique
        if ($result.Count -eq 0) {
            $result = $null
        }
        Write-Host "Found" $result.Count "terminals with IOExceptions"
        # Write file with results
        $result | Out-File -FilePath ($logFolder + "ioexceptions.txt")
        # open file
        Start-Process ($logFolder + "ioexceptions.txt")
    }
    # Handle transaction searches
    elseif ($choice -eq "1" -or $choice -eq "2" -or $choice -eq "3" -or $searchString -match "00\d{4}-\d{6}") {
        $result = Get-ChildItem -Path $logFolder -Filter *.log | Select-String $searchString
        $lines = $result | ForEach-Object { $_.Line }
        $trxResult = $lines | Select-string -Pattern "00\d{4}-\d{6}" -AllMatches
        $trxResult = $trxResult.Matches | ForEach-Object { $_.Value }
        $trxResult = $trxResult | Sort-Object -Unique
    }
    else {
        $result = Get-ChildItem -Path $logFolder -Filter *.log | Select-String $searchString
        $lines = $result | ForEach-Object { $_.Line }
    }

    $result2 = $result
    $result = @()
    if ($choice -eq "6") {
        foreach ($line in $result2) {
            $pos = $line.Line.IndexOf("terminalId=")
            $line.Line = $line.Line.Substring($pos)
            $pos = $line.Line.IndexOf("terminalEnvironment=")
            $line.Line = $line.Line.Substring(0, $pos).TrimEnd(",")
            $pos = $line.Line.IndexOf("timestamp=")
            $pos2 = $line.Line.IndexOf("terminalSoftwareManufacturer=")
            $line.Line = $line.Line.Substring(0, $pos) + $line.Line.Substring($pos2).TrimEnd(",")
            $result += $line
        }
        $result = $result | Sort-Object -Property Line -Unique
    }
    else {
        $result = $result2
    }

    $tempResult = $result
    $result = @()
    foreach ($temp in $tempResult) {
        if ($temp.Line.Contains("*****************************************************")) {
            Continue
        }
        if ($temp.Line.Contains("MoveNext")) {
            Continue
        }
        if ($temp.Line.Contains("SendTelemetryMessage")) {
            Continue
        }
        if ($temp.Line.Contains("SendTelemetryState")) {
            Continue
        }

        $result += $temp
    }
    return $result, $trxResult, $lines

}
function GetOrdre ($logFolder, $avdnr, $ordrenr) {
    $outputFileName = $global:tmpFolder + "ExportTableContentToFile.cmd"
    # delete cmd file

    Get-Content -Path $logFolder\runDate.txt
    $global:oldRunDate

    if (Test-Path -Path $outputFileName -PathType Leaf) {
        Remove-Item -Path $outputFileName -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $global:exportTableFilename = $global:tmpFolder + "sqlfeil_bankterm_last_30_days.csv"

    # get last write time of  Get-Item $global:exportTableFilename
    #$lastWriteTime = (Get-Item $global:exportTableFilename).LastWriteTime

    # check if file is older than 10 minutes
    # $dateDiff = (((Get-Date).AddMinutes(-10)) - $lastWriteTime).Minutes
    # if ($dateDiff -lt 10) {
    #     return
    # }

    $array = @()

    $result = "@echo off"
    $array += $result

    $result = "del " + $global:tmpFolder + "*.csv /F /Q"
    $array += $result

    $result = "db2 connect to basispro"
    $array += $result

    $result = "db2 export to " + $exportTableFilename + " of del modified by coldel;  select * from tv.sqlfeil_bankterm_last_30_days"
    $array += $result

    $result = "exit"
    $array += $result

    set-content -Path $outputFileName  -Value $array | Out-Null
    # db2cmd.exe -w $outputFileName | Out-Null
    Start-Process -FilePath "db2cmd.exe" -ArgumentList "-w $outputFileName" -NoNewWindow -Wait
    # Write-Output "Export completed: " + $exportTableName

    # Read csv file
    $csvModulArray = Import-Csv ($global:exportTableFilename) -Header TIDSPUNKT, DB , CLIENT , BRUKERID , SQLCODE , PROGRAM , PARAGRAF , MELDING , TS_NAME , SERVER , BUFFER , AVDNR , AVDNAVN , KASSENR , TEKST , MASKINNAVN , BANK_TERM_ID , IP_ADRESSE , HOVEDTERM , TERM_MODEL -Delimiter ';'

    # Export all sql errors to a file in same manner as the log files
    $result = @()
    $counter = 0
    $sqllogfilename = $logFolder + "sqlerrors.log"
    if (Test-Path -Path $sqllogfilename -PathType Leaf) {
        Remove-Item -Path $sqllogfilename -Force -ErrorAction SilentlyContinue | Out-Null
    }
    foreach ($line in $csvModulArray) {
        $timestamp = $line.TIDSPUNKT
        $timestamp = $timestamp.Substring(0, 10) + " " + $timestamp.Substring(11, 8).Replace(".", ":") + "." + $timestamp.Substring(20, 4)
        $module = $line.PROGRAM.Trim() + "." + $line.PARAGRAF.Trim()

        $sqlcode = $line.SQLCODE.Replace(".", "")
        $buffer = $line.BUFFER.ToString().Trim().Replace("`r`n", " ").Replace("`n", "").Replace("`r", "").Replace("`t", "")
        $sqlMessage = $line.MELDING.Trim().Replace("`r`n", " ").Replace("`n", "").Replace("`r", "").Replace("`t", "")
        # remove hex 00 from buffer
        $buffer = $buffer -replace '\x00', ''

        $severity = "INFO"
        if ($line.SQLCODE.Contains("100")) {
            $severity = "WARNING"
        }
        if ($line.SQLCODE.Contains("-")) {
            $severity = "ERROR"
        }

        $message = "Sqlcode: " + $sqlcode + " /Database: " + $line.DB.Trim() + " /Message: " + $sqlMessage + " /Buffer: " + $buffer.Trim() + " /UserId: " + $line.BRUKERID.Trim() + " /Server: " + $line.SERVER.Trim()

        $result = $timestamp + "|" + $severity + "|" + $module + "|" + $message

        $result | Out-File -FilePath $sqllogfilename -Append -Force

        $counter++
    }
}

function GetFile ($logFolder, $runDate, $terminalCobolLogPath, $externalLogFilename ) {
    $command = 'robocopy ' + $terminalCobolLogPath + " " + $logFolder + " " + $externalLogFilename
    $resultInvoke = Invoke-Expression $command

    if (Test-Path -Path $terminalCobolLogPathDate -PathType Container) {
        $command = 'robocopy ' + $terminalCobolLogPathDate + " " + $logFolder + " " + $externalLogFilename
        $resultInvoke = Invoke-Expression $command
    }
    return $resultInvoke
}

function GetAllCobolLogFiles ($logFolder, $runDate) {
    $terminalCobolLogPath = "\\DEDGE.fk.no\erpdata\COBDATA\LOG\"

    #$terminalCobolLogPathDate = $terminalCobolLogPath + $runDate + "\"
    Write-Host "Getting all cobol terminal log files"
    $externalLogFilename = "BT_*" + $runDate + "_BASISREG_*.log"
    Remove-Item -Path ($logFolder + $externalLogFilename) -Force -ErrorAction SilentlyContinue | Out-Null
    GetFile $logFolder $runDate $terminalCobolLogPath $externalLogFilename

    Write-Host "Getting all cobol BKFINFA log files"
    $externalLogFilename = "BKFINFA_" + $runDate + "_BASISREG_*.log"
    Remove-Item -Path ($logFolder + $externalLogFilename) -Force -ErrorAction SilentlyContinue | Out-Null
    GetFile $logFolder $runDate $terminalCobolLogPath $externalLogFilename

    Write-Host "Getting all cobol BSHBUOR log files"
    $externalLogFilename = "BSHBUOR_" + $runDate + "_BASISREG_*.log"
    Remove-Item -Path ($logFolder + $externalLogFilename) -Force -ErrorAction SilentlyContinue | Out-Null
    GetFile $logFolder $runDate $terminalCobolLogPath $externalLogFilename
}

function CheckExternalCobolLog ($logFolder, $externalLogPath, $externalLogFilename, $runDate, $orderNumber = "") {

    $feedbackArray = @()

    $command = 'robocopy ' + $externalLogPath + " " + $logFolder + " " + $externalLogFilename

    Invoke-Expression $command

    $actualExternalLogFilenames = @()
    $actualExternalLogFilenames += Get-ChildItem -Path $logFolder -Filter $externalLogFilename

    if ($actualExternalLogFilenames.Count -eq 0) {
        # $feedbackArray += " No external log files found: " + $externalLogPath + $externalLogFilename
        # foreach ($line in $resultInvoke) {
        #     $feedbackArray += $line
        #     Write-Host $line
        # }
        $feedbackArray += ""
    }
    else {
        $feedbackArray += "-------------------------------------------- External log content --------------------------------------------"
        foreach ($actualExternalLogFilename in $actualExternalLogFilenames) {
            $externalLogContent = Get-Content -Path $actualExternalLogFilename
            $feedbackArray += " External log filename: " + $externalLogPath + $actualExternalLogFilename.Name
            $feedbackArray += ""

            $counter = 0
            foreach ($line in $externalLogContent) {
                if ([string]::IsNullOrEmpty($orderNumber)) {
                    $line = $line -replace '[^\x20-\x7E\r\n]', ''
                    $feedbackArray += $line
                    $counter++
                }
                else {
                    if ($line.Contains($orderNumber.Trim())) {
                        $counter++
                        $line = $line -replace '[^\x20-\x7E\r\n]', ''
                        $feedbackArray += $line
                    }
                }
            }

            if ($counter -eq 0 -and $orderNumber -ne "") {
                $feedbackArray += "No occurences of $orderNumber in external log file"
            }

            $feedbackArray += ""
        }
    }
    return $feedbackArray
}

function CheckExternalLogsAndFiles ($logFolder, $departmentId, $terminalId, $runDate, $orderNumber = "") {
    $feedbackArray = @()

    if (-not [string]::IsNullOrEmpty($orderNumber)) {
        # Find Pos Transaction receipt
        $externalLogPath = "\\DEDGE.fk.no\erpdata\COBDATA\LOG\"
        $externalLogFilename = $departmentId + "_" + $orderNumber + "*" + $terminalId + "_*.txt"
        # $feedbackArray += " Attemting to find POS transaction receipt file: " + $externalLogPath + $externalLogFilename
        $feedbackArray += CheckExternalCobolLog $logFolder $externalLogPath $externalLogFilename $runDate

        # Find Dedge receipt file
        $externalLogFilename = "BSAUPKF_BASISREG_0" + $departmentId + "_0" + $orderNumber + ".prt"
        # $feedbackArray += " Attemting to find Dedge receipt file: " + $combinedExternalLogFilename
        $feedbackArray += CheckExternalCobolLog $logFolder $externalLogPath $externalLogFilename $runDate

    }
    return $feedbackArray
}
function GetSqlErrorMessages ($completeLog) {

    $firstRow = $true
    $allTimestamps = @()
    $terminalId = ""

    $res = $completeLog -match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}"
    foreach ($item in $res) {
        $item = $item.ToString().Trim()
        $timestampFrom = $item.Substring(0, 16)
        $pos1 = $timestampFrom.IndexOf(" ")
        $pos2 = $timestampFrom.IndexOf(":")
        if ($terminalId -eq "") {
            if ($item -match "BT_[A-Za-z]{3}\d{1}" ) {
                $terminalId = $Matches[0]
            }
        }
        $timestampFrom = $timestampFrom.Substring(0, $pos1) + "-" + $timestampFrom.Substring($pos1 + 1, $pos2 - $pos1 - 1) + "." + $timestampFrom.Substring($pos2 + 1)

        $allTimestamps += $timestampFrom
    }
    $allTimestamps = $allTimestamps | Sort-Object -Unique
    $testArray = @()
    $csvModulArray = Import-Csv ($global:exportTableFilename) -Header TIDSPUNKT, DB , CLIENT , BRUKERID , SQLCODE , PROGRAM , PARAGRAF , MELDING , TS_NAME , SERVER , BUFFER , AVDNR , AVDNAVN , KASSENR , TEKST , MASKINNAVN , BANK_TERM_ID , IP_ADRESSE , HOVEDTERM , TERM_MODEL -Delimiter ';'
    foreach ($currentTimeStamp in $allTimestamps) {
        $temp = $csvModulArray | Where-Object { $_.TIDSPUNKT.Contains($currentTimeStamp.ToString()) -and $_.BANK_TERM_ID.Contains($terminalId) }
        foreach ($line in $temp) {
            # TIDSPUNKT, DB , CLIENT , BRUKERID , SQLCODE , PROGRAM , PARAGRAF , MELDING , TS_NAME , SERVER , BUFFER , AVDNR , AVDNAVN , KASSENR , TEKST , MASKINNAVN , BANK_TERM_ID , IP_ADRESSE , HOVEDTERM , TERM_MODEL
            if ($firstRow) {
                $firstRow = $false
            }
            $testArray += $line
        }
    }
    return $testArray
}

function LogMessage {
    param(
        $message
    )
    $scriptName = $MyInvocation.ScriptName.Split("\")[$MyInvocation.ScriptName.Split("\").Length - 1].Replace(".ps1", "").Replace(".PS1", "")

    $global:logfile = $env:OptPath + "\work\DedgePosLogSearch\DedgePosLogSearch.log"

    $dt = get-date -Format("yyyy-MM-dd HH:mm:ss,ffff").ToString()

    $logmsg = $dt + ": " + $scriptName.Trim() + " :  " + $message

    Write-Host $logmsg
    Add-Content -Path $global:logfile -Value $logmsg
}

function GetSqlErrors ($logFolder, $runDate, $terminalId) {
    $outputFileName = $global:tmpFolder + "ExportTableContentToFile.cmd"

    if (Test-Path -Path $outputFileName -PathType Leaf) {
        Remove-Item -Path $outputFileName -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $global:exportTableFilename = $global:tmpFolder + "sqlfeil_bankterm_last_30_days.csv"

    # get last write time of  Get-Item $global:exportTableFilename
    if (Test-Path -Path $global:exportTableFilename -PathType Leaf) {
        $lastWriteTime = (Get-Item $global:exportTableFilename).LastWriteTime

        # check if file is older than 5 minutes
        $dateDiff = (((Get-Date).AddMinutes(-5)) - $lastWriteTime).Minutes
        if ($dateDiff -lt 10) {
            return
        }
    }

    # 2024-08-19-14.01.20.270000

    $reformatRunDate = $runDate.Substring(0, 4) + "-" + $runDate.Substring(4, 2) + "-" + $runDate.Substring(6, 2)
    $timestampFrom = $reformatRunDate + "-00.00.00.000000"
    $timestampTo = $reformatRunDate + "-23.59.59.999999"

    $array = @()

    $result = "@echo off"
    $array += $result

    $result = "del " + $global:tmpFolder + "*.csv /F /Q"
    $array += $result

    $result = "db2 connect to basispro"
    $array += $result

    $result = "db2 export to " + $exportTableFilename + " of del modified by coldel;  select * from tv.sqlfeil_bankterm_last_30_days where tidspunkt between '" + $timestampFrom + "' and '" + $timestampTo + "'"
    if ($terminalId -ne "") {
        $result += " and bank_term_id = '" + $terminalId + "'"
    }

    $array += $result

    $result = "exit"
    $array += $result

    set-content -Path $outputFileName  -Value $array | Out-Null
    # db2cmd.exe -w $outputFileName | Out-Null
    Start-Process -FilePath "db2cmd.exe" -ArgumentList "-w $outputFileName" -NoNewWindow -Wait

    # Write-Output "Export completed: " + $exportTableName

    if (-not (Test-Path -Path $global:exportTableFilename -PathType Leaf)) {
        Write-Host "No sql errors csv file found"
        return
    }
    # Read csv file
    $csvModulArray = Import-Csv ($global:exportTableFilename) -Header TIDSPUNKT, DB , CLIENT , BRUKERID , SQLCODE , PROGRAM , PARAGRAF , MELDING , TS_NAME , SERVER , BUFFER , AVDNR , AVDNAVN , KASSENR , TEKST , MASKINNAVN , BANK_TERM_ID , IP_ADRESSE , HOVEDTERM , TERM_MODEL -Delimiter ';'

    # Export all sql errors to a file in same manner as the log files
    $result = @()
    $counter = 0
    $sqllogfilename = $logFolder + "sqlerrors.log"
    if (Test-Path -Path $sqllogfilename -PathType Leaf) {
        Remove-Item -Path $sqllogfilename -Force -ErrorAction SilentlyContinue | Out-Null
    }
    foreach ($line in $csvModulArray) {
        $timestamp = $line.TIDSPUNKT
        $timestamp = $timestamp.Substring(0, 10) + " " + $timestamp.Substring(11, 8).Replace(".", ":") + "." + $timestamp.Substring(20, 4)
        $module = $line.PROGRAM.Trim() + "." + $line.PARAGRAF.Trim()

        $sqlcode = $line.SQLCODE.Replace(".", "")
        $buffer = $line.BUFFER.ToString().Trim().Replace("`r`n", " ").Replace("`n", "").Replace("`r", "").Replace("`t", "")
        $sqlMessage = $line.MELDING.Trim().Replace("`r`n", " ").Replace("`n", "").Replace("`r", "").Replace("`t", "")
        # remove hex 00 from buffer
        $buffer = $buffer -replace '\x00', ''

        $severity = "INFO"
        if ($line.SQLCODE.Contains("100")) {
            $severity = "WARNING"
        }
        if ($line.SQLCODE.Contains("-")) {
            $severity = "ERROR"
        }

        # Remove all invalid characters from buffer, only keep printable characters
        # $buffer = ($line.BUFFER.ToString().Trim()) -replace '[^\x20-\x7E\r\n]', ''

        $message = "Sqlcode: " + $sqlcode + " /Message: " + $sqlMessage + " /Buffer: " + $buffer.Trim() + " /UserId: " + $line.BRUKERID.Trim() + " /Database: " + $line.DB.Trim() + " /Server: " + $line.SERVER.Trim()

        $result = $timestamp + "|" + $severity + "|" + $module + "|" + $line.BANK_TERM_ID.Trim() + '|' + $message

        $result | Out-File -FilePath $sqllogfilename -Append -Force

        $counter++
    }
}

function GetFkLog ($logFolder, $runDate, $terminalId = "", $avdnr = "", $ordrenr = "") {
    $outputFileName = $global:tmpFolder + "ExportTableContentToFile.cmd"

    if (Test-Path -Path $outputFileName -PathType Leaf) {
        Remove-Item -Path $outputFileName -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $exportTableFilename = $global:tmpFolder + "fk_log.csv"

    $array = @()

    $result = "@echo off"
    $array += $result

    $result = "del " + $global:tmpFolder + "*.csv /F /Q"
    $array += $result

    $result = "db2 connect to basispro"
    $array += $result

    $reformatRunDate = $runDate.Substring(0, 4) + "-" + $runDate.Substring(4, 2) + "-" + $runDate.Substring(6, 2)

    # $tidspunktStart = $reformatRunDate + "-00.00.01.000000"
    # $tidspunktEnd = $reformatRunDate + "-23.59.59.000000"

    $result = "db2 export to " + $exportTableFilename + " of del modified by coldel;  select * from dbm.fk_log where dato = '" + $reformatRunDate + "'"
    # $result = "db2 export to " + $exportTableFilename + " of del modified by coldel;  select * from dbm.fk_log where tidspunkt between '" + $tidspunktStart + "' and '" + $tidspunktEnd + "'"
    if ($terminalId -ne "") {
        $result += " and bank_term_id = '" + $terminalId + "'"
    }

    if ($avdnr -ne "") {
        $result += " and avdnr = " + $avdnr
    }

    if ($ordrenr -ne "") {
        $result += " and ordrenr = " + $ordrenr
    }

    $array += $result

    $result = "exit"
    $array += $result

    set-content -Path $outputFileName  -Value $array | Out-Null
    # db2cmd.exe -w $outputFileName | Out-Null
    Start-Process -FilePath "db2cmd.exe" -ArgumentList "-w $outputFileName" -NoNewWindow -Wait
    # Wait for db2cmd to finish sleep 2 seconds

    # Write-Output "Export completed: " + $exportTableName
    # TIDSPUNKT
    # SEVERITY
    # DATO
    # DB
    # MASKINNAVN
    # BANK_TERM_ID
    # BRUKERID
    # PROGRAM
    # PARAGRAF
    # CONTEXT
    # AVDNR
    # ORDRENR
    # MELDING

    # Read csv file
    $csvModulArray = Import-Csv ($exportTableFilename) -Header TIDSPUNKT, SEVERITY, DATO, DB, MASKINNAVN, BANK_TERM_ID, BRUKERID, PROGRAM, PARAGRAF, CONTEXT, AVDNR, ORDRENR, MELDING -Delimiter ';'

    # Export all sql errors to a file in same manner as the log files
    $result = @()
    $counter = 0
    $fklogfilename = $logFolder + "fk_log.log"
    if (Test-Path -Path $fklogfilename -PathType Leaf) {
        Remove-Item -Path $fklogfilename -Force -ErrorAction SilentlyContinue | Out-Null
    }

    foreach ($line in $csvModulArray) {
        $timestamp = $line.TIDSPUNKT
        $timestamp = $timestamp.Substring(0, 10) + " " + $timestamp.Substring(11, 8).Replace(".", ":") + "." + $timestamp.Substring(20, 4)
        $module = $line.PROGRAM.Trim() + "." + $line.PARAGRAF.Trim()

        $tmpMessage = $line.MELDING.Trim().Replace("`r`n", " ").Replace("`n", "").Replace("`r", "").Replace("`t", "")

        $severity = $line.SEVERITY.Trim().ToUpper()

        $message = "Message: " + $tmpMessage + " /Context: " + $line.CONTEXT.Trim() + " /UserId: " + $line.BRUKERID.Trim() + " /Server: " + $line.MASKINNAVN.Trim() + " /DepartmentId: " + $line.AVDNR.Trim() + " /OrderNumber: " + $line.ORDRENR.Trim()
        # + " /TerminalId: " + $line.BANK_TERM_ID.Trim()

        $resultx = $timestamp + "|" + $severity + "|" + $module + "|" + $line.BANK_TERM_ID.Trim() + "|" + $message

        $resultx | Out-File -FilePath $fklogfilename -Append -Force

        $counter++
    }
}

function HandleTransactionFeedback ($trx, $transactionFeedbackLine, $trxFeedbackString , $resultCounter , $departmentId, $orderNumber, $terminalId, $runDate) {

    $transactionTimeStampAndSeverity = $transactionFeedbackLine.Split($trxFeedbackString)[0].Trim()
    $transactionTimeStamp = $transactionTimeStampAndSeverity.Split(" ")[0].Trim() + " " + $transactionTimeStampAndSeverity.Split(" ")[1].Trim()
    $transactionSeverity = $transactionTimeStampAndSeverity.Split(" ")[2].Trim()
    $transactionFeedbackLine = $transactionFeedbackLine.Split($trxFeedbackString)[1].Replace(", content=ReceiptContent{format=Text, text=", "").Trim().TrimStart("-").Trim().Replace("{", ",").Replace("}", ",").Replace(",,", ",")
    $feedbackArray = @()
    $amountLine = ""
    $extraIndentLineCount = 0
    $level1Indent = "     - "
    $level2Indent = "        - "
    $level3Indent = "           - "
    $standardIndent = $level1Indent
    $feedbackArray += "-------------------------------------------- Summary $resultCounter for $trx --------------------------------------------"
    $feedbackArray += $standardIndent + "Timestamp: " + $transactionTimeStamp
    $feedbackArray += $standardIndent + "Severity: " + $transactionSeverity

    foreach ($currentItemName in $transactionFeedbackLine.Split(",")) {

        if ($currentItemName.Length -eq 0) {
            Continue
        }

        if ($amountLine -ne "" -and $currentItemName -match "\d{2}" ) {
            $amountLine += "," + $currentItemName
            # uppercase first letter in amountLine
            $amountLine = $amountLine.Substring(0, 1).ToUpper() + $amountLine.Substring(1)
            $feedbackArray += $standardIndent + $amountLine.Trim()
            $amountLine = ""
            Continue
        }
        elseif ($amountLine -ne "") {
            $amountLine = $amountLine.Trim()
            $amountLine = $amountLine.Substring(0, 1).ToUpper() + $amountLine.Substring(1)
            $feedbackArray += $standardIndent + $amountLine.Trim()
            $amountLine = ""
        }

        if ($currentItemName.Contains("Amount=")) {
            $amountLine = $currentItemName
        }
        elseif ($currentItemName.Contains(" receipts=[Receipt")) {
            Continue
        }
        elseif ($currentItemName.Contains("=TransactionId") -or $currentItemName.Contains("=PaymentInstrumentData")) {
            $temp = $currentItemName.Split("=")[0]
            $temp = $temp.Trim()
            $temp = $temp.Substring(0, 1).ToUpper() + $temp.Substring(1)
            $feedbackArray += $standardIndent + $temp.Trim()
            $temp = $currentItemName.Split("=")[1]
            $temp = $temp.Trim()
            $temp = $temp.Substring(0, 1).ToUpper() + $temp.Substring(1)
            $feedbackArray += "        - " + $temp.Trim()
            if ($currentItemName.Contains("=PaymentInstrumentData")) {
                $extraIndentLineCount = 8
            }
            else {
                $extraIndentLineCount = 2
            }
        }
        elseif ($currentItemName.Contains(": TransactionResult")) {

            $feedbackArray += ($standardIndent + "DepartmentId: " + $departmentId)
            $feedbackArray += ($standardIndent + "OrderNumber: " + $orderNumber)
            $feedbackArray += ($standardIndent + "TransactionId: " + $trx)
            $feedbackArray += ($standardIndent + "TerminalId: " + $terminalId)
            $pos = $currentItemName.IndexOf(":")
            $temp = $currentItemName.Substring(0, $pos)

            $temp = $temp.Trim()
            $temp = $temp.Substring(0, 1).ToUpper() + $temp.Substring(1)
            $feedbackArray += $standardIndent + $temp.Trim()
            $temp = $currentItemName.Substring($pos)
            $temp = $temp.Trim().TrimStart(":").Trim()
            $temp = $temp.Substring(0, 1).ToUpper() + $temp.Substring(1)
            $feedbackArray += ($standardIndent + $temp.Trim())
            $standardIndent = $level2Indent
        }
        elseif ($extraIndentLineCount -gt 0) {
            $currentItemName = $currentItemName.Trim()
            $currentItemName = $currentItemName.Substring(0, 1).ToUpper() + $currentItemName.Substring(1)
            $feedbackArray += $level3Indent + $currentItemName.Trim()
            $extraIndentLineCount--
        }
        else {
            $currentItemName = $currentItemName.Trim()
            try {

                $currentItemName = $currentItemName.Substring(0, 1).ToUpper() + $currentItemName.Substring(1)
            }
            catch {
            }
            $feedbackArray += $standardIndent + $currentItemName.Trim()
        }
    }

    $feedbackArray += ""

    return $feedbackArray
}
function FixWorkLine ($filename, $workLine) {
    if ($workLine.Contains(" TRACE ") -or $workLine.Contains(" DEBUG ") -or $workLine.Contains(" INFO ") -or $workLine.Contains(" WARN ") -or $workLine.Contains(" ERROR ") -or $workLine.Contains(" FATAL ")) {
        $source = "VimLog"
        $workLine = $workLine.Replace(" TRACE   ", "|TRACE|")
        $workLine = $workLine.Replace(" DEBUG   ", "|DEBUG|")
        $workLine = $workLine.Replace(" INFO   ", "|INFO|")
        $workLine = $workLine.Replace(" WARN   ", "|WARN|")
        $workLine = $workLine.Replace(" ERROR   ", "|ERROR|")
        $workLine = $workLine.Replace(" FATAL   ", "|FATAL|")
        $workLine = $workLine.Replace(" TRACE  ", "|TRACE|")
        $workLine = $workLine.Replace(" DEBUG  ", "|DEBUG|")
        $workLine = $workLine.Replace(" INFO  ", "|INFO|")
        $workLine = $workLine.Replace(" WARN  ", "|WARN|")
        $workLine = $workLine.Replace(" ERROR  ", "|ERROR|")
        $workLine = $workLine.Replace(" FATAL  ", "|FATAL|")
        $workLine = $workLine.Replace(" TRACE ", "|TRACE|")
        $workLine = $workLine.Replace(" DEBUG ", "|DEBUG|")
        $workLine = $workLine.Replace(" INFO ", "|INFO|")
        $workLine = $workLine.Replace(" WARN ", "|WARN|")
        $workLine = $workLine.Replace(" ERROR ", "|ERROR|")
        $workLine = $workLine.Replace(" FATAL ", "|FATAL|")
        $pos = $workLine.IndexOf(" - ")
        $workLine = $workLine.Substring(0, $pos) + "|" + $workLine.Substring($pos + 3)
    }
    elseif ($lineResult.Filename.Contains("AllLogging")) {
        $source = "PosLog"
    }
    elseif ($lineResult.Filename.Contains("sqlerrors")) {
        $source = "SqlLog"
    }
    elseif ($lineResult.Filename.Contains("wrapper")) {
        $source = "WrpLog"
    }
    elseif ($lineResult.Filename.Contains("fk_log")) {
        $source = "FkLog "
    }
    else {
        $source = "CblLog"
        # 2024-07-07 12:03:23.3000|CblLog|INFO|BSHBUOR|BUTFBU01|AVDNR: 008412 /ORDRENR: 202407 /MESSAGE: LOGTAG:M1410-CHK-UTLEVERT/AVDNR: 008412 /ORDRENR: 202407 /WW-CNT-FULLEVERT: 0000000000000 /H-TILBUD-SW: 0000000000000 /H-ORDRESTATUS: 0000000003100
        $splitCblLine = $workLine.Split("|")
        $counter = 0
        $tempWorkLine = ""
        foreach ($item in $splitCblLine) {
            if ($counter -eq 2 ) {
                $tempWorkLine += "Dedge.Cbl." + $item.Trim() + "|"
            }
            elseif ($counter -ne 3 ) {
                $tempWorkLine += $item + "|"
            }
            $counter++
        }
        $workLine = $tempWorkLine

    }
    #Count number of | in line
    $count = 0
    for ($i = 0; $i -lt $workLine.Length; $i++) {
        if ($workLine[$i] -eq "|") {
            $count++
        }
    }
    $pos = $workLine.IndexOf("|")

    $newLine = $workLine.Substring(0, $pos) + "|" + $source + "|" + $workLine.Substring($pos + 1)
    return $newLine
}
function TransactionHandling ($logFolder, $searchResultFolder , $lines, $runDate) {
    $allResultContent = @()
    $trxFeedbackString = "Verifone.Vim.Internal.Protocol.Epas.Handlers.Response.EpasPaymentResponseHandler"
    $trxResult = @()
    $trxResult = $lines | Select-string -Pattern "00\d{4}-\d{6}" -AllMatches
    # $trxResult = $lines | Select-string -Pattern "00\d{4}-\d{6}-\d{1}-" -AllMatches
    $trxResult = $trxResult.Matches | ForEach-Object { $_.Value }
    $trxResult = $trxResult | Sort-Object -Unique
    $trxCount = $trxResult.Count
    $eachTrxPercent = 100 / $trxCount
    $trxPercent = 0
    $lastTrx = ""
    $lastTerminalId = ""

    foreach ($trx in $trxResult) {
        $trx = $trx.ToString().Trim()
        $splitTrx = $trx.Split("-")
        $departmentId = $splitTrx[0]
        $orderNumber = $splitTrx[1]

        $trxDeptOrder = $departmentId + "-" + $orderNumber

        $trxPercent += $eachTrxPercent
        Write-Progress -Activity "Processing transactions" -Status "Processing transaction $trx" -PercentComplete $trxPercent
        $result = Get-ChildItem -Path $logFolder -Filter "*.log" | Select-String $trx | Sort-Object -Unique

        # Find all terminals in $result
        $terminals = @()
        foreach ($line in $result) {
            if ($line.Line -match "BT_[A-Za-z]{3}\d{1}" ) {
                $terminalIdResult = $line.Line | Select-String -Pattern "BT_[A-Za-z]{3}\d{1}"
                $terminalId = $terminalIdResult.Matches.Value
                $terminals += $terminalId
                break
            }
        }
        $terminalId = $terminals | Sort-Object -Unique | Select-Object -First 1
        $terminalId = $terminalId.ToString().Trim()

        if ($lastTerminalId -ne $terminalId -or $lastTerminalId -eq "") {
            GetSqlErrors $logFolder -runDate $runDate -terminalId $terminalId.ToUpper().Trim()
        }
        $lastTerminalId = $terminalId

        if ($lastTrx -ne $trxDeptOrder -or $lastTrx -eq "") {
            GetFkLog -logFolder $logFolder -runDate $runDate -terminalId $terminalId.ToUpper().Trim() -avdnr $departmentId -ordrenr $orderNumber
        }
        $lastTrx = $trxDeptOrder
        # GetCobolLogFiles $logFolder $runDate $terminalId

        $result = Get-ChildItem -Path $logFolder -Filter "*.log" | Select-String $orderNumber
        $result += Get-ChildItem -Path $logFolder -Filter "sqlerrors.log" | Select-String $terminalId

        # # Find highest and lowest timestamp in $result using regex "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}"
        # $minTimestamp = ""
        # $maxTimestamp = ""
        # foreach ($line in $result) {
        #     if ($line.Line -match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}") {
        #         $timestamp = $line.Line.Split("|")[0].Trim()
        #         # "2024-07-01 17:46:58.8900"
        #         # Convert to timestamp

        #         if ($minTimestamp -eq "" -or $timestamp -lt $minTimestamp) {
        #             $minTimestamp = $timestamp
        #         }
        #         if ($maxTimestamp -eq "" -or $timestamp -gt $maxTimestamp) {
        #             $maxTimestamp = $timestamp
        #         }
        #     }
        # }
        # # Calculate difference in minutes between min and max timestamp
        # $minTimestamp = [DateTime]::ParseExact($minTimestamp.Substring(0, 16), "yyyy-MM-dd HH:mm", $null)
        # $maxTimestamp = [DateTime]::ParseExact($maxTimestamp.Substring(0, 16), "yyyy-MM-dd HH:mm", $null)
        # $maxTimestamp = $maxTimestamp.AddMinutes(1)
        # $dateDiff = $maxTimestamp - $minTimestamp
        # $dateDiff = $dateDiff.TotalMinutes
        # if ($dateDiff -lt 1) {
        #     $dateDiff = 1
        # }
        # $dateDiff = [math]::Ceiling($dateDiff)

        # # for each minute between min and max timestamp
        # $result = @()
        # $counter = 0
        # $currentTimestamp = $minTimestamp
        # while ($currentTimestamp -lt $maxTimestamp) {
        #     $currentTimestampStr = $currentTimestamp.ToString("yyyy-MM-dd HH:mm")

        #     $resultTemp = @()
        #     $resultTemp = Get-ChildItem -Path $logFolder -Filter "*.log" | Select-String $currentTimestampStr

        #     foreach ($line in $resultTemp) {
        #         if ($line.Line.Contains($trx) -or ($line.Line.Contains($orderNumber)) -or $line.Line.Contains($terminalId)) {
        #             $result += $line
        #         }
        #     }

        #     $counter++

        #     $currentTimestamp = $currentTimestamp.AddMinutes($counter)
        # }

        $result = $result | Sort-Object -Unique

        $transactionFeedbackLine = ""

        $feedResultArray = @()
        $resultCounter = 0

        $splitTrx = $trx.Split("-")
        $departmentId = $splitTrx[0]
        $orderNumber = $splitTrx[1]

        $tempArray = @()
        $lastFkLogLine = ""
        $firstFkLogLine = ""

        foreach ($lineResult in $result) {
            # Find all lines in $lineResult.Line that contains $trxFeedbackString
            # $lineResult = $lineResult.ToString().Trim()
            $tempLine = ""

            if ($lineResult.Line.Contains($trxFeedbackString)) {
                $resultCounter++
                $transactionFeedbackLine = $lineResult.Line
                $tempLine = FixWorkLine -filename $lineResult.Filename -workLine $lineResult.Line

                $feedResultArray += HandleTransactionFeedback $trx $transactionFeedbackLine $trxFeedbackString $resultCounter $departmentId $orderNumber $terminalId $runDate
            }
            else {
                $tempLine = FixWorkLine -filename $lineResult.Filename -workLine $lineResult.Line
            }

            if ($lineResult.Filename.Contains("fk_log")) {
                if ($firstFkLogLine -eq "") {
                    $firstFkLogLine = $tempLine
                }
                $lastFkLogLine = $tempLine
            }
            if (-not $lineResult.Filename.Contains("sqlerrors")) {
                $lastFkLogLine = $tempLine
            }
            # write-host $tempLine
            $tempArray += $tempLine
        }
        $newArray = @()
        $newArray = $tempArray | Sort-Object -Unique

        $completeLog = @()
        $completeLog += "********************************************** Start $trx **********************************************"

        $firstFkLogLineFound = $false

        foreach ($lineResult in $newArray) {

            $lineResult = $lineResult.ToString().Trim()

            if ($lineResult -eq $firstFkLogLine -or $firstFkLogLine -eq "") {
                $firstFkLogLineFound = $true
            }
            if ($firstFkLogLineFound -eq $true) {
                $completeLog += $lineResult
            }
            if ($lineResult -eq $lastFkLogLine) {
                break
            }
        }

        $completeLog = $completeLog | Sort-Object -Unique

        foreach ($item in $feedResultArray) {
            $completeLog += $item
        }

        $completeLog += CheckExternalLogsAndFiles $logFolder $departmentId $terminalId $runDate $orderNumber

        # $testArray = @()
        # if ($skipSqllog -eq "0") {
        #     $testArray = GetSqlErrorMessages $completeLog
        #     if ($testArray.Count -gt 0) {
        #         $completeLog += "******************************************* SQL ERRORS START *******************************************"
        #         $completeLog += $testArray
        #         $completeLog += "******************************************** SQL ERRORS END ********************************************"
        #     }
        # }

        $completeLog += "=============================================== End $trx ================================================"
        $resultFileName = $searchResultFolder + "\" + $trx + ".log"
        $completeLog | Out-File -FilePath $resultFileName -Force
        $completeLog += "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        $completeLog += ""
        $completeLog += ""
        $allResultContent += $completeLog
    }
    Write-Progress -Activity "Processing transactions" -Completed

    return $allResultContent

}

function HandleCobdokExport ($cobdokFolder) {
    Write-Host "--> Exporting tables from cobdok"

    $array = @()

    $result = "del " + $cobdokFolder + "\" + "*.csv /F /Q"
    $array += $result

    $result = "db2 connect to cobdok"
    $array += $result

    $result = ExportTableContentToFile -exportTableName "modul" -folderPath $cobdokFolder
    $array += $result

    $result = "exit"
    $array += $result

    $outputFileName = $cobdokFolder + "\ExportTableContentToFile.cmd"
    set-content -Path $outputFileName  -Value $array
    # db2cmd.exe -w $outputFileName
    Start-Process -FilePath "db2cmd.exe" -ArgumentList "-w $outputFileName" -NoNewWindow -Wait
    # Write-Output "Export completed"

    ConvertFromAnsi1252ToUtf8 -exportTableName  "modul" -folderPath $cobdokFolder
}

function FindRunDateFromLogfiles ($logFolder, $addDays = -1) {
    $firstFile = Get-ChildItem -Path $logFolder -Filter "*vim*.log" | Select-Object -Last 1
    $runDate = $firstFile.LastWriteTime.AddDays($addDays).ToString("yyyyMMdd")
    $runDateDmy = $firstFile.LastWriteTime.AddDays($addDays).ToString("dd-MM-yyyy")
    Set-Content -Path $logFolder\runDate.txt -Value $runDate
    return $runDate, $runDateDmy
}
# --------------------------------------------------------------------------------
# Main script
# --------------------------------------------------------------------------------
Clear-Host
Write-Host "================================== DedgePos log search =================================="

if ($null -eq $env:OptPath) {
    Write-Host "Environment variable OptPath is not set. Exiting script."
    return
}
if (Test-Path -Path $logFolder\runDate.txt -PathType Leaf) {
    $global:oldRunDate = Get-Content -Path $logFolder\runDate.txt
}

$StartPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location -Path $StartPath
$global:logfile = $env:OptPath + "\work\DedgePosLogSearch\DedgePosLogSearch.log"

$workFolder = $env:OptPath + "\work\DedgePosLogSearch\"
if (-not (Test-Path -Path $workFolder -PathType Container)) {
    New-Item -Path $workFolder -ItemType Directory
}
$logFolder = $env:OptPath + "\work\DedgePosLogSearch\log\"
if (-not (Test-Path -Path $logFolder -PathType Container)) {
    New-Item -Path $logFolder -ItemType Directory
}
$tmpFolder = $env:OptPath + "\work\DedgePosLogSearch\tmp\"
if (-not (Test-Path -Path $tmpFolder -PathType Container)) {
    New-Item -Path $tmpFolder -ItemType Directory
}
$resultFolder = $env:OptPath + "\work\DedgePosLogSearch\result\"
if (-not (Test-Path -Path $resultFolder -PathType Container)) {
    New-Item -Path $resultFolder -ItemType Directory
}

$global:tmpFolder = $tmpFolder

try {

    $ProdServer1 = "sfk-batch-vm01"
    $ProdServer2 = "p-no1batch-vm01"

    $ProdLogPath1 = "\\" + $ProdServer1 + ".DEDGE.fk.no\opt\Apps\DedgePosServiceHostRunner\log"
    $ProdLogBackupPath1 = "\\" + $ProdServer1 + ".DEDGE.fk.no\opt\Apps\DedgePosServiceHostRunner\log\LogBackup"
    $ProdLogPath2 = "\\" + $ProdServer2 + ".DEDGE.fk.no\opt\Apps\DedgePosServiceHostRunner\log"
    $ProdLogBackupPath2 = "\\" + $ProdServer2 + ".DEDGE.fk.no\opt\Apps\DedgePosServiceHostRunner\log\LogBackup"

    if (Test-Path -Path $ProdLogPath1 -PathType Container) {
        $logfiles = Get-ChildItem -Path $ProdLogPath1 -Filter "*.log"
    }
    if (Test-Path -Path $ProdLogPath2 -PathType Container) {
        $logfiles += Get-ChildItem -Path $ProdLogPath2 -Filter "*.log"
    }

    $files = Get-ChildItem -Path $logFolder -Filter "*.log"

}
catch {
    Write-Host "Error: $($_.Exception.Message). Exiting script."
    return
}

if ($logfiles.Count -eq 0) {
    Write-Host "You dont have access to the log folder. Exiting script."
    exit
}

$getLogfiles = $false
# if number of log files in $logFolder is greater than 0 ask user if he wants to delete all log files in $logFolder and copy all *.log files from $ProdLogPath1 to $logFolder
Write-Host "Search for transaction types, reconciliation messages or any other string in log files."
Write-Host "------------------------------------------------------------------------------------------"
Write-Host ""
if ($files.Count -gt 0) {

    $runDate, $runDateDmy = FindRunDateFromLogfiles $logFolder -1

    $msg = "Logfiles are for $runDateDmy. Do you want to refresh log files? (y/n)"
    $result = Read-Host -Prompt $msg
    $result = $result.ToLower()
    if ($result -eq "y") {
        $getLogfiles = $true
    }
}
else {
    $getLogfiles = $true
}

if ($getLogfiles) {
    # delete all log files in $logFolder
    Get-ChildItem -Path $logFolder -Filter "*.*" | Remove-Item -Force
    $files = @()

    $msg = "Do you want to retrieve log files from another day? (y/n)"
    $result = Read-Host -Prompt $msg
    $result = $result.ToLower()
    if ($result -eq "y") {
        $histLogFiles = @()
        $histLogFiles += Get-ChildItem -Path $ProdLogBackupPath2 -Filter "*.zip"
        $histLogFiles += Get-ChildItem -Path $ProdLogBackupPath1 -Filter "*.zip"
        # Show file choices in a numbered list
        $counter = 1
        $addedDates = @()
        foreach ($file in $histLogFiles) {
            $text = $file.Name.Substring(0, 8)
            # convert text to date
            $dateText = [DateTime]::ParseExact($text, "yyyyMMdd", $null)

            # $text now contains the date of the log file in the format YYYYMMDD. Format it to YYYY-MM-DD
            $addedDates += ($dateText.ToString("yyyyMMdd") + "_" + $dateText.AddDays(-1).ToString("yyyyMMdd") + "_" + $dateText.AddDays(-1).ToString("dd-MM-yyyy") )
        }
        $addedDates = $addedDates | Sort-Object -Unique -Descending
        foreach ($text in $addedDates) {
            $splitText = $text.Split("_")

            Write-Host "    <$counter>: " $splitText[2]
            $counter++
        }
        $msg = "Choose date to copy log files from. Enter file number"
        $choice = Read-Host -Prompt $msg
        $choice = $choice - 1
        $splitText = $addedDates[$choice].Split("_")
        $filePattern = "*" + $splitText[0] + "*.zip"
        $filesToCopy = @()
        $filesToCopy += Get-ChildItem -Path $ProdLogBackupPath1 -Filter $filePattern
        $filesToCopy += Get-ChildItem -Path $ProdLogBackupPath2 -Filter $filePattern

        foreach ($fileToCopy in $filesToCopy) {

            if ($fileToCopy.FullName.Contains($ProdServer1)) {
                $destFile = $tmpFolder + $ProdServer1 + "_" + $fileToCopy.Name
            }
            else {
                $destFile = $tmpFolder + $ProdServer2 + "_" + $fileToCopy.Name
            }

            if (-not(Test-Path -Path $destFile -PathType Leaf)) {
                Copy-Item -Path $fileToCopy.FullName -Destination $destFile -Force
            }
            # unzipped $destFile
            $unzipDestFile = $destFile.Replace(".zip", "")
            # remove files in folder first unzipDestFile
            Get-ChildItem -Path $unzipDestFile -Filter "*.log" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

            try {
                Expand-Archive -Path $destFile -DestinationPath $unzipDestFile
            }
            catch {
                Copy-Item -Path $fileToCopy.FullName -Destination $destFile -Force
                Expand-Archive -Path $destFile -DestinationPath $unzipDestFile
            }
            $files = Get-ChildItem -Path $unzipDestFile -Filter "*.log"
            foreach ($logfile in $files) {
                if ($logfile.Name.Contains("AllLoggingInfo.log") -or $logfile.Name.Contains("VIMWrapper.log") -or $logfile.Name -match "vim_.*.log") {
                    if ($skipWrapperlog -eq "1" -and $logfile.Name.Contains("VIMWrapper.log")) {
                        continue
                    }

                    $pos = $logfile.Name.IndexOf("_")
                    $temp = $logfile.Name.Substring($pos + 1)
                    # $destFile = $logFolder + $temp
                    if ($fileToCopy.FullName.Contains($ProdServer1)) {
                        $destFile = $logFolder + $ProdServer1 + "_" + $temp
                    }
                    else {
                        $destFile = $logFolder + $ProdServer2 + "_" + $temp
                    }
                    Copy-Item -Path $logfile.FullName -Destination $destFile -Force
                    Write-Host "Copied " $logfile.FullName " to " $destFile
                }
            }
        }
        $text = $fileToCopy.Name.Substring(0, 8)
        $runDate, $runDateDmy = FindRunDateFromLogfiles $logFolder
    }
    else {
        $files = @()
        $files += Get-ChildItem -Path $ProdLogPath1 -Filter "*.log"
        $files += Get-ChildItem -Path $ProdLogPath2 -Filter "*.log"
        $runDate = (Get-Date).ToString("yyyyMMdd")
        $runDateDmy = (Get-Date).ToString("dd-MM-yyyy")
        Set-Content -Path $logFolder\runDate.txt -Value $runDate

        foreach ($logfile in $files) {
            if ($logfile.Name -eq "AllLoggingInfo.log" -or $logfile.Name.Contains("VIMWrapper.log") -or $logfile.Name -match "vim_.*.log") {
                if ($skipWrapperlog -eq "1" -and $logfile.Name.Contains("VIMWrapper.log")) {
                    continue
                }

                # $files += $logfile
                if ($logfile.FullName.Contains($ProdServer1)) {
                    $destFile = $logFolder + $ProdServer1 + "_" + $logfile.Name
                }
                else {
                    $destFile = $logFolder + $ProdServer2 + "_" + $logfile.Name
                }
                Copy-Item -Path $logfile.FullName -Destination $destFile -Force
                Write-Host "Copied " $logfile.FullName " to " $destFile
            }
        }
        $runDate, $runDateDmy = FindRunDateFromLogfiles $logFolder 0
    }
}

$trxRefundString = "ReqRefund"
$trxPaymentString = "ReqPayment"
$trxReversalString = "ReqReversal"
$recReconciliationString = 'AVSTEMMING\"'
$terminalConnection = "GetTerminalReadyStatus"
# $terminalLoginInfo = "Verifone.Vim.Internal.Protocol.Epas.Handlers.Response.EpasLoginResponseHandler"
$terminalLoginInfo = "Response.EpasLoginResponseHandler"
$queryFilterArray = @()
# # Get Sql error messages from database
# GetSqlErrors $logFolder
# GetFkLog $logFolder $runDate

$trxResult = @()
# ask user for search string
while ($true) {

    Clear-Host
    Write-Host "================================== DedgePos log search =================================="
    Write-Host "Search for transaction types, reconciliation messages or any other string in log files."
    Write-Host "------------------------------------------------------------------------------------------"
    Write-Host "Files searchable for date: $runDateDmy"
    Write-Host "------------------------------------------------------------------------------------------"
    Write-Host ""
    Write-Host "Predefined search:"
    Write-Host "    <1>: Payment transactions"
    Write-Host "    <2>: Refund transactions"
    Write-Host "    <3>: Reversal transactions"
    Write-Host "    <4>: Reconciliation messages"
    Write-Host "    <5>: Terminal connection changes"
    Write-Host "    <6>: Terminal login info"
    Write-Host "    <7>: Open VIM log"
    Write-Host "    <8>: Open AllLoggingInfo log"
    Write-Host "    <9>: Find IO Exceptions"
    Write-Host "    <20>: Open log folder"
    Write-Host "    <30>: Get Cobol export files"
    Write-Host "    <99>: Exit script"
    Write-Host ""
    Write-Host "Otherwise enter a search string. Regex is supported"
    Write-Host ""
    $choice = Read-Host -Prompt "Enter search string"
    if ($choice -eq "99") {
        Write-Host "Exiting script."
        break
    }

    if ($choice -eq "7") {
        $logFiles = Get-ChildItem -Path $logFolder -Filter "*vim_*.log"
        if ($logFiles.Count -eq 0) {
            Write-Host "No vim log file found"
            Read-Host -Prompt "Press any key to continue..."
            continue
        }
        foreach ($logFile in $logFiles) {
            Invoke-Item -Path $logFile.FullName
        }
        continue
    }

    if ($choice -eq "8") {
        $logFiles = Get-ChildItem -Path $logFolder -Filter "*AllLoggingInfo.log"
        if ($logFiles.Count -eq 0) {
            Write-Host "No AllLoggingInfo log file found"
            Read-Host -Prompt "Press any key to continue..."
            continue
        }
        foreach ($logFile in $logFiles) {
            Invoke-Item -Path $logFile.FullName
        }
        continue
    }

    if ($choice -eq "9") {
        $searchString = "IOException.*?TerminalId: (\w+), Handle event: Type: ConnectionClosed"
    }

    if ($choice -eq "20") {
        Invoke-Item -Path $logFolder
        continue
    }
    if ($choice -eq "30") {
        GetAllCobolLogFiles $logFolder $runDate
        continue
    }

    break
}

if ($choice -eq "1") {
    $searchString = $trxPaymentString
}
elseif ($choice -eq "2") {
    $searchString = $trxRefundString
}
elseif ($choice -eq "3") {
    $searchString = $trxReversalString
}
elseif ($choice -eq "4") {
    $searchString = $recReconciliationString
}
elseif ($choice -eq "5") {
    $searchString = $terminalConnection
}
elseif ($choice -eq "6") {
    $searchString = $terminalLoginInfo
}
elseif ($choice -eq "9") {
    $searchString = "IOException.*?TerminalId: (\w+), Handle event: Type: ConnectionClosed"
}
else {
    $searchString = $choice
    $choice = ""
}

if ($searchString -eq "") {
    Write-Host "No search string entered. Exiting script."
    return
}
$result, $trxResult, $lines = InitFilter $choice $searchString $logFolder

$queryFilterArray += $searchString

$resultCount = $result.Count
if ($resultCount -eq 0) {
    Write-Host "No occurences of $searchString in log files"
    return
}

# Limit search

# Limit results until user input is empty
$backupResults = $result
$resultCount = $result.Count
$limitSearch = "-"
$trxResultTemp = @()
$lines = @()
$tdBackupResults = @()
$trxResultUniqueList = @()
while ($limitSearch -ne "") {
    Write-Host ""
    Write-Host ""
    Write-Host "================================== DedgePos log search =================================="
    Write-Host "Filter search results by time, terminal, transactionId or a combination of these"
    Write-Host ""
    Write-Host "Free search examples:"
    Write-Host "    Limit search example options  "
    Write-Host "    Limit by time:'11:32'"
    Write-Host "    Limit by hour 11:'11:**'"
    Write-Host "    Limit by terminal:'BT_KLO1'"
    Write-Host "    Limit by transactionId:'00xxxx-xxxxxx-x-DEB/CRED'"
    Write-Host "    Limit by time and terminal:'11:32 BT_KLO1'"
    Write-Host ""
    Write-Host "Number of search results: $resultCount"
    Write-Host "    <l> to list all search results"
    Write-Host "    <r> to reset search results"
    Write-Host "    <td> to fetch all transaction data for further filtering"
    Write-Host "    <rtd> to reset to last td result"
    Write-Host "    <tl> to fetch list of active terminals"
    Write-Host ""
    Write-Host "Current search count: $resultCount"
    Write-Host ""
    $limitSearch = Read-Host -Prompt "Enter limit search"
    if ($limitSearch -eq "") {
        break
    }
    elseif ($limitSearch -eq "tl") {
        $termList = @()
        $termResultList = @()
        $termList = Get-ChildItem -Path $logFolder -Filter *.log | Select-String "ReqReconciliation"
        foreach ($line in $termList) {
            $splitLine = $line.Line.Split("ReqReconciliation")
            $line = $splitLine[1].Replace("|", "").Trim()
            $termResultList += $line
        }
        $termResultList = $termResultList | Sort-Object -Unique
        Clear-Host
        $header = "TerminalId"
        $termResultList | Format-Table -AutoSize -Property $header
        # Read-Host -Prompt "Press any key to continue..."
        continue
    }
    elseif ($limitSearch -eq "td") {
        $trxResultTemp = @()
        $tdBackupResults = @()
        Write-Host "    Fetching all transaction data for further filtering"
        $trxPercent = 0

        # Get transaction IDs from current results
        $lines = $result | ForEach-Object { $_.Line }
        $lines = $lines | Sort-Object -Unique

        $trxMatches = $lines | Select-string -Pattern "00\d{4}-\d{6}" -AllMatches
        $trxResultTemp = $trxMatches.Matches | ForEach-Object { $_.Value }
        $trxResultUniqueList = $trxResultTemp | Sort-Object -Unique

        $trxCount = $trxResultUniqueList.Count
        if ($trxCount -eq 0) {
            Write-Host "    No transactions found in current results"
            continue
        }

        $eachTrxPercent = 100 / $trxCount
        $tdBackupResults = $result
        $result = @()

        Write-Host "    Found $trxCount unique transactions"

        foreach ($trxTemp in $trxResultUniqueList) {
            $trxPercent += $eachTrxPercent
            if ($trxPercent -gt 100) {
                $trxPercent = 100
            }
            Write-Progress -Activity "Gathering log data for transactions" -Status "Processing transaction $trxTemp" -PercentComplete $trxPercent
            $result += Get-ChildItem -Path $logFolder -Filter *.log | Select-String $trxTemp
        }
        Write-Progress -Activity "Gathering log data for transactions" -Completed

        $resultCount = $result.Count
        if ($resultCount -eq 0) {
            Write-Host "    No log entries found for transactions"
            Write-Host "    Resetting search results"
            $result = $tdBackupResults
        }
        else {
            Write-Host "    Found $resultCount log entries for $trxCount transactions"
        }
        continue
    }
    elseif ($limitSearch -eq "rtd") {
        Write-Host "    Resetting search results to last transaction data search results"
        $result = $tdBackupResults
        $resultCount = $result.Count
        if ($resultCount -eq 0) {
            Write-Host "    No occurences of $searchString after filtering in log files"
            Write-Host "    Resetting search results"
            $result = $backupResults
            $resultCount = $result.Count
        }
        continue
    }
    elseif ($limitSearch -eq "r") {
        $trxResultTemp = @()
        $tdBackupResults = @()
        Write-Host "    Resetting search results"
        $result = $backupResults
        $resultCount = $result.Count
        continue
    }
    elseif ($limitSearch -eq "l") {
        Clear-Host
        Write-Host "    Listing all search results"
        $result | ForEach-Object { $_.Line }
        # Read-Host -Prompt "Press any key to continue..."
        $limitSearch = "-"
        continue
    }
    elseif ($limitSearch.Substring(0, 2) -match "\d{2}" -and $limitSearch.Length -le 5 -and $limitSearch.Contains(":")) {
        #Get current date as YYYY-MM-DD
        $currentDate = Get-Date -Format "yyyy-MM-dd"
        $limitSearch = $currentDate + " " + $limitSearch.Replace("*", "")
        $queryFilterArray += $limitSearch
    }
    $result = $result | Select-String $limitSearch
    $resultCount = $result.Count
    if ($resultCount -eq 0 ) {
        Write-Host "    No occurences of string '$limitSearch' found after filtering in log files"
        Write-Host "    Resetting search results"
        if ($tdBackupResults.Count -gt 0) {
            $result = $tdBackupResults
        }
        else {
            $result = $backupResults
        }
        $resultCount = $result.Count
    }
}

if ($trxResultTemp.Count -gt 0 -or $trxResult.Count -gt 0 -or $trxResultUniqueList.Count -gt 0) {
    if ($trxResultUniqueList.Count -eq $result.Count) {
        $trxResult = $trxResultUniqueList
    }
    else {
        $lines = $result | ForEach-Object { $_.Line }
        $lines = $result | Sort-Object -Unique
        $trxResult = $lines | Select-string -Pattern "00\d{4}-\d{6}" -AllMatches
        # $trxResult = $lines | Select-string -Pattern "00\d{4}-\d{6}-\d{1}-" -AllMatches
        $trxResult = $trxResult.Matches | ForEach-Object { $_.Value }
        $trxResult = $trxResult | Sort-Object -Unique

    }
}
# else {
#     $trxResult = @($searchString)
# }

$resultCount = $result.Count
if ($resultCount -eq 0) {
    Write-Host "No occurences of after filtering in log files"
    return
}

$searchStringFileFolder = $searchString -replace '[^\x20-\x7E]', ''
$searchStringFileFolder = $searchStringFileFolder -replace '[^\x20-\x7E\r\n\\/()]', ''
$searchStringFileFolder = $searchStringFileFolder.Replace(" ", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace(":", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace("/", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace("\\", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace("\", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace("(", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace(")", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace("?", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace("!", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace("=", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace(">", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace("<", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace("|", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace("*", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace(";", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace(":", "_")
$searchStringFileFolder = $searchStringFileFolder.Replace('"', "")
$searchStringFileFolder = $searchStringFileFolder.Replace("'", "")

$searchStringFileFolder = $searchStringFileFolder.TrimEnd("_")

# create a subfolder in $resultFolder with the name of the search string
$searchResultFolder = $resultFolder + $searchStringFileFolder
if (-not (Test-Path -Path $searchResultFolder -PathType Container)) {
    New-Item -Path $searchResultFolder -ItemType Directory
}
else {
    Get-ChildItem -Path $searchResultFolder -Filter "*.log" | Remove-Item -Force
}

$allResultContent = @()
# find all lines in allloggininfo.log that contains each $trxResultstrand log all lines to screen per trxResultstr
if ($trxResult.Count -gt 0) {
    $allResultContent = TransactionHandling $logFolder $searchResultFolder $lines $runDate
}
else {

    if ($searchString.ToUpper().Contains('BT_')) {
        GetSqlErrors $logFolder -runDate $runDate -terminalId $searchString.ToUpper().Trim()
        GetFkLog -logFolder $logFolder -runDate $runDate -terminalId $searchString.ToUpper().Trim()
    }
    else {
        GetSqlErrors $logFolder -runDate $runDate
        # GetFkLog -logFolder $logFolder -runDate $runDate
    }
    # $queryFilterArray
    $result = @()
    $resultTmp, $trxResult, $lines = InitFilter $choice $queryFilterArray[0] $logFolder
    $counter = 0
    foreach ($queryFilter in $queryFilterArray) {
        $counter++
        if ($counter -eq 1) {
            continue
        }
        $resultTmp = $resultTmp | Select-String $queryFilter
    }
    $result = $resultTmp

    $completeLog = @()
    $result = $result | Sort-Object
    foreach ($lineResult in $result) {
        $line = $lineResult.Line
        $line = $line -replace '[^\x20-\x7E]', ''
        $line = $line -replace '[^\x20-\x7E\r\n\\/()]', ''
        $completeLog = @()
        $completeLog += FixWorkLine -filename $lineResult.Filename -workLine $line
        $allResultContent += $completeLog
    }

    # if ($searchString.ToUpper().Contains('BT_')) {
    #     $completeLog += CheckExternalLogsAndFiles $logFolder $departmentId $searchString.ToUpper() $runDate $orderNumber
    # }

    $allResultContent += $completeLog
    $allResultContent = $allResultContent | Sort-Object -Unique
}

$resultFileName = $searchResultFolder + "\AllResults.log"
$allResultContent | Out-File -FilePath $resultFileName -Force

# Invoke-Item $searchResultFolder
Invoke-Item $resultFileName

