function LogMessage {
    param(
        $message
    )
    $scriptName = $MyInvocation.ScriptName.Split("\")[$MyInvocation.ScriptName.Split("\").Length - 1].Replace(".ps1", "").Replace(".PS1", "")

    $logfile = $global:logfile

    $dt = get-date -Format("yyyy-MM-dd HH:mm:ss,ffff").ToString()

    $logmsg = $dt + ": " + $scriptName.Trim() + " :  " + $message

    Write-Host $logmsg
    Add-Content -Path $logfile -Value $logmsg
}

function FindLineNumber ($errorLineNumber, $splitLstContent) {
    try {
        $vcpath = $env:VCPATH
        $checkString1 = "* " + $vcpath
        $checkString2 = "* Micro Focus COBOL "
        $errorLineNumberLocal = $errorLineNumber - 1
        $line = $splitLstContent[$errorLineNumberLocal]
        if ($splitLstContent[$errorLineNumberLocal].StartsWith($checkString1) -and $splitLstContent[$errorLineNumberLocal - 1].StartsWith($checkString2)) {
            $errorLineNumberLocal = $errorLineNumberLocal - 3
            $line = $splitLstContent[$errorLineNumberLocal]
        }

        if ($line.StartsWith(" ")) {
            $temp = $line.TrimStart().Split(" ")[0]
            # parse temp to number
            try {
                $templineNumber = [int]::Parse($temp)
                return $templineNumber
            }
            catch {
                $errorLineNumberLocal = $errorLineNumberLocal - 1
                return FindLineNumber $errorLineNumberLocal $splitLstContent
            }
        }
    }
    catch {
        return -1
    }
}

function FindLstLineNumber ($errorLineNumber, $splitLstContent) {
    try {
        $errorLineNumberLocal = $errorLineNumber - 1
        $line = $splitLstContent[$errorLineNumberLocal]
        if ($line.StartsWith(" ")) {
            $temp = $line.TrimStart().Split(" ")[0]
            # parse temp to number
            try {
                $templineNumber = [int]::Parse($temp)
                return $errorLineNumberLocal
            }
            catch {
                $errorLineNumberLocal = $errorLineNumberLocal - 1
                return FindLstLineNumber $errorLineNumberLocal $splitLstContent
            }
        }
    }
    catch {
        return -1
    }
}
function FindErrorText ($errorLineNumber, $splitLstContent) {
    $vcpath = $env:VCPATH
    $checkString1 = "* " + $vcpath
    $checkString2 = "* Micro Focus COBOL "

    $resultArray = @()
    $line = $splitLstContent[$errorLineNumber]
    $counter = 0
    $errorCode = ""
    $errorLine = $line
    $resultArray += $errorLine
    $errorLineNumber++
    $line = $splitLstContent[$errorLineNumber]
    try {
        while ($line.StartsWith("*")) {
            if (-not ($line.StartsWith($checkString1) -or $line.StartsWith($checkString2))) {
                $counter++

                if ($counter -eq 1) {
                    # $errorCode = $line.Replace("*", "").Trim() +
                    $errorCode = "Error code: ¤¤¤¤"
                    $errorLineNumber++
                    $line = $splitLstContent[$errorLineNumber]
                    continue
                }
                if ($counter -eq 2) {
                    $errorCode += " - " + $line.TrimStart("*").Trim()
                    $resultArray += $errorCode
                    $errorLineNumber++
                    $line = $splitLstContent[$errorLineNumber]
                    continue
                }

                $resultArray += "      " + $line
            }
            $errorLineNumber++
            $line = $splitLstContent[$errorLineNumber]
            if ($line.StartsWith("* Last message on page")) {
                break
            }
        }
    }
    catch {
        $x = 1
    }
    return $resultArray

}

$global:logfile = $env:OptPath + "\src\DedgePsh\DevTools\VisualCobolBatchCompile\VisualCobolBatchCompile.log"

$VCPATH = $env:VCPATH
$files = Get-ChildItem -Path "$VCPATH\src\cbl" -Filter *.cbl

$files = Get-ChildItem -Path "$VCPATH\src\cbl" -Filter "AAXFKTSX.CBL"
# Push-Location

try {
    foreach ($file in $files) {
        $allFiles = $intFolder + "\" + $file.BaseName.ToUpper() + ".*"
        $intFile = $VCPATH + "\int\" + $file.BaseName.ToUpper() + ".int"
        $lstFile = $VCPATH + "\lst\" + $file.BaseName.ToUpper() + ".lst"
        $cblFile = $VCPATH + "\src\cbl\" + $file.BaseName.ToUpper() + ".cbl"
        $compileLogFile = $VCPATH + "\log\" + $file.BaseName.ToUpper() + ".log"

        # check if int file exists
        # if (-not (Test-Path -Path $lstFile -PathType Leaf)) {
        #     Continue
        # }

        # Skip files that are not to be compiled
        if ($file.BaseName.ToUpper() -eq "DOHCBLD" -or $file.BaseName.ToUpper() -eq "DOHCHK" -or $file.BaseName.ToUpper() -eq "DOHCHK2" -or $file.BaseName.ToUpper() -eq "DOHCHK3" -or $file.BaseName.ToUpper() -eq "DOHCHK4" -or $file.BaseName.ToUpper() -eq "DOHCHK6" -or $file.BaseName.ToUpper() -eq "DOHUTGAT" -or $file.BaseName.ToUpper() -eq "DOHSCAN") {
            continue
        }

        if ($file.BaseName -match "(\d{8})|(\d{6})" -and $file.BaseName.Length -gt 6) {
            continue
        }
        if ($file.BaseName.Contains(" ")) {
            continue
        }

        LogMessage -message ("--> Compiling " + $file.FullName)

        Start-Process -FilePath ($VCPATH + "\cfg\VcComplie.bat") -ArgumentList $file.BaseName.ToUpper(), "32" -RedirectStandardOutput $compileLogFile -WindowStyle Hidden -Wait

        $output = $null
        $lstFile = $VCPATH + "\lst\" + $file.BaseName.ToUpper() + ".lst"
        if (Test-Path -Path $lstFile -PathType Leaf) {
            $lstContent = Get-Content -Path $lstFile
            $output = $lstContent | Select-String -Pattern "^\* Last message on page:"
        }
        else {
            $logContent = Get-Content -Path $compileLogFile

            $pattern = ": error COB.*"
            $output = $logContent | Select-String -Pattern $pattern
            if ($null -eq $output) {
                $output = $logContent
            }
            else {
                $output = $output.Matches[0].Value
                $output = $output.TrimStart(":").TrimStart(" ")
            }
            LogMessage -message ("******************************************************************************************")
            LogMessage -message ("******************************************************************************************")
            LogMessage -message ("**> Compilation stopped due to: " + $output)
            LogMessage -message ("******************************************************************************************")
            LogMessage -message ("******************************************************************************************")
            exit 1
    }
        # Verify if the compilation was successful
        if ($null -ne $output) {
            LogMessage -message ("-------------------------------------- START " + $file.BaseName.ToUpper().lst + "--------------------------------------")
            $lstContent | Select-Object -Skip ($output.LineNumber - 4) | ForEach-Object { LogMessage -message $_ }
            LogMessage -message ("**> Compilation failed: $file")
            LogMessage -message ("**> List file:" + $lstFile)
            LogMessage -message ("------------------------------------ ERRORLIST " + $file.BaseName.ToUpper().lst + "------------------------------------")

            $splitLstContent = $lstContent -split "\r\n"
            $errorRegex = "\*(?=\s{0,4}\d{0,4}-)(\s*\d{1,4})-([a-z])\*"
            $errorList = $splitLstContent | Select-String -Pattern $errorRegex
            foreach ($errorItem in $errorList) {

                if (  $errorItem.LineNumber -eq 248) {
                    $x = 1
                }
                # LogMessage -message ("**> Error: " + $errorItem)
                $errorMatch = $errorItem.Matches[0].Value.Replace("*", "")
                try {
                    $errorOnSrcLine = FindLineNumber  ($errorItem.LineNumber - 1) $splitLstContent
                }
                catch {
                    $errorOnSrcLine = FindLineNumber  ($errorItem.LineNumber - 1) $splitLstContent
                }
                $errorOnSrcLine = FindLineNumber  ($errorItem.LineNumber - 1) $splitLstContent
                $errorArray = FindErrorText ($errorItem.LineNumber - 2) $splitLstContent
                # LogMessage -message ("   Error found in source line: " + $errorOnSrcLine)
                $counter = 0
                foreach ($errorLine in $errorArray) {
                    $counter++
                    if ($counter -eq 1) {
                        try {
                            $pos = $errorLine.IndexOf($errorOnSrcLine.ToString())
                            $errorLine = $errorLine.Substring($pos + $errorOnSrcLine.ToString().Length)
                        }
                        catch {
                            $pos = 0
                        }

                        try {

                            $errorLineTemp = "Error on source line " + $errorOnSrcLine.ToString() + ". Line text: '" + $errorLine + "'"
                        }
                        catch {
                            LogMessage -message ("   " + $errorLine)

                        }

                        LogMessage -message ("   " + $errorLineTemp)
                        continue
                    }
                    if ($counter -eq 2) {
                        $errorLine = $errorLine.Replace("¤¤¤¤", $errorMatch)
                        LogMessage -message ("   " + $errorLine)
                        continue
                    }
                    LogMessage -message ("   Detail info:" + $errorLine)
                }
                LogMessage -message ("                                               ")

            }
            LogMessage -message ("--------------------------------------- END " + $file.BaseName.ToUpper().lst + "---------------------------------------")
        }
        else {
            LogMessage -message ("==> Compilation successful: " + $file.FullName)
            # Remove the lst file if the compilation was successful
            Remove-Item -Path $lstFile -Force
        }
        Start-Sleep -Milliseconds 500
    }
}
finally {
    # Pop-Location
    LogMessage -message "--> Done"
}

