
Import-Module -Name FKASendSMSDirect -Force
Import-Module -Name ConvertFileFromAnsi1252ToUtf8 -Force

function LogMessage {
    param(
        $message
    )
    $dtLog = get-date -Format("yyyyMMdd").ToString()
    $logfile = "\\DEDGE.fk.no\erpprog\cobnt\" + $dtLog + "_VisualCobolCodeMigration.log"
    $logfile1 = $global:logFolder + "\" + $dtLog + "_VisualCobolCodeMigration.log"
    $dt = get-date -Format("yyyy-MM-dd HH:mm:ss,ffff").ToString()

    $logmsg = $dt + ": VisualCobolCodeMigration :  " + $message

    Write-Host $logmsg
    Add-Content -Path $logfile -Value $logmsg
    Add-Content -Path $logfile1 -Value $logmsg
}

function removeFilenameFromCleanPath {
    param(
        $cleanPath
    )

    $backupCleanPath = $cleanPath
    $invalidChar = $cleanPath | Select-String -Pattern '[^\x20-\x7E\xC6\xE6\xD8\xF8\xC5\xE5\x2E\x24\x5C\x3A]' -AllMatches
    if ($invalidChar) {
        $index = $invalidChar.Matches[0].Index
        $cleanPath = $cleanPath.Substring(0, $index)
        $posx = $cleanPath.LastIndexOf("\")
        $cleanPath = $cleanPath.Substring(0, $posx + 1)
    }
    if ($invalidChar) {
        $invalidChar.Matches | ForEach-Object {
            $hexValue = [System.Text.Encoding]::UTF8.GetBytes($_.Value) | ForEach-Object { '0x{0:X}' -f $_ }
            LogMessage "Invalid character found in path: $backupCleanPath. Hex value: $hexValue. Path reduced to: $cleanPath"
        }
    }

    if ($cleanPath.Contains(" ")) {
        $cleanPath = $cleanPath.Split(" ")[0]
    }
    if ($cleanPath.Contains("'")) {
        $cleanPath = $cleanPath.Split("'")[0]
    }
    if ($cleanPath.EndsWith(".")) {
        $cleanPath = $cleanPath.Split(".")[0]
    }
    if ($cleanPath.Contains('"')) {
        $cleanPath = $cleanPath.Split('"')[0]
    }
    if ($cleanPath.Contains(')')) {
        $cleanPath = $cleanPath.Split(')')[0]
    }
    if ($cleanPath.Contains('*')) {
        $cleanPath = $cleanPath.Split('*')[0]
    }
    if ($cleanPath.Contains('%')) {
        $cleanPath = $cleanPath.Split('%')[0]
    }
    if ($cleanPath.Contains('BRUKERID')) {
        $cleanPath = $cleanPath.Split('BRUKERID')[0]
    }

    if ($cleanPath.Length -gt 3) {
        if ($cleanPath.Substring(2).Contains(':')) {
            $cleanPath = $cleanPath.Split(':')[0]
        }
    }

    if ($cleanPath.Contains(".")) {
        $extenstionArray = @(".TXT", ".LOG", ".BAT", ".%COMPUTERNAME%", ".TEST", ".AKT", ".CSV", ".ERR", ".BND")

        foreach ($ext in $extenstionArray) {
            if ($cleanPath.Contains($ext)) {
                $cleanPath = $cleanPath.Split($ext)[0]
                # Find previous "\" and remove string after that
                $lastSlash = $cleanPath.LastIndexOf("\")
                $cleanPath = $cleanPath.Substring(0, $lastSlash + 1)
                break
            }
        }
    }

    if (-not $cleanPath.EndsWith("\")) {
        $lastSlash = $cleanPath.LastIndexOf("\")
        $cleanPath = $cleanPath.Substring(0, $lastSlash + 1)
    }

    #if cleanPath contains non valid characters lower than ascii 32, remove them
    # $cleanPath = $cleanPath -replace "[^\x20-\x7E]", ""

    return $cleanPath
}

function HandleSelectedLines ($searchObject) {

    if ($searchObject.FileBaseName.ToUpper() -eq "DOHCBLD" -or $searchObject.FileBaseName.ToUpper() -eq "DOHCHK" -or $searchObject.FileBaseName.ToUpper() -eq "DOHCHK2" -or $searchObject.FileBaseName.ToUpper() -eq "DOHCHK3" -or $searchObject.FileBaseName.ToUpper() -eq "DOHCHK4" -or $searchObject.FileBaseName.ToUpper() -eq "DOHCHK6" -or $searchObject.FileBaseName.ToUpper() -eq "DOHUTGAT" -or $searchObject.FileBaseName.ToUpper() -eq "DOHSCAN") {
        continue
    }

    if ($searchObject.FileExtension -eq ".BAT" -and ($line.Line.ToUpper().StartsWith("REM") -or $line.Line.ToUpper().StartsWith("@REM")) ) {
        continue
    }

    if ($searchObject.FileExtension -eq ".CMD" -and ($line.Line.ToUpper().StartsWith("REM") -or $line.Line.ToUpper().StartsWith("@REM")) ) {
        continue
    }

    if ($searchObject.FileExtension -eq ".PSM1" -and ($line.Line.ToUpper().StartsWith("#")) ) {
        continue
    }

    if ($searchObject.FileExtension -eq ".PS1" -and ($line.Line.ToUpper().StartsWith("#")) ) {
        continue
    }

    if ($searchObject.FileExtension -eq ".CBL" -and ($line.Line.Trim().ToUpper().StartsWith("*")) ) {
        continue
    }

    if ($searchObject.FileExtension -eq ".DCL" -and ($line.Line.Trim().ToUpper().StartsWith("*")) ) {
        continue
    }

    if ($searchObject.FileExtension -eq ".CPY" -and ($line.Line.Trim().ToUpper().StartsWith("*")) ) {
        continue
    }

    if ($searchObject.FileExtension -eq ".CPB" -and ($line.Line.Trim().ToUpper().StartsWith("*")) ) {
        continue
    }

    if ($searchObject.FileExtension -eq ".REX" -and ($line.Line.Trim().ToUpper().StartsWith("/*")) ) {
        continue
    }

    $cleanPath = $searchObject.MatchText
    $cleanPath = $cleanPath -replace '\x0A', '' -replace '\x00', '' -replace '\x0D', '' -replace '\x1A', ''

    if ($searchObject.Type -eq "UNC" -or $searchObject.Type -eq "DRIVE") {
        if (-not $cleanPath.EndsWith("\") -and -not $cleanPath.Contains(".") -and -not $cleanPath.Contains("*") -and -not $cleanPath.Contains("%") -and -not $cleanPath.Contains("?") -and -not $cleanPath.EndsWith("_")) {
            $cleanPath = $cleanPath.Trim() + "\"
        }
        $cleanPath = removeFilenameFromCleanPath -cleanPath $cleanPath
    }

    if ($searchObject.Type -eq "DRIVE") {
        if ($cleanPath.Length -gt 1) {
            if ($cleanPath.StartsWith("C:") -or $cleanPath.StartsWith("U:")) {
                $cleanPath = $cleanPath.TrimStart("\")
            }
        }
    }

    $invalidChar = ""

    # Character | Hexadecimal
    # ----------|------------
    # Æ         | C6
    # æ         | E6
    # Ø         | D8
    # ø         | F8
    # Å         | C5
    # å         | E5

    # $invalidChar = $cleanPath | Select-String -Pattern '[^\x20-\x7E]' -AllMatches
    # $invalidChar = $cleanPath | Select-String -Pattern '[^\x20-\x7E\xC6\xE6\xD8\xF8\xC5\xE5\x2E\x24\x5C\x3A]' -AllMatches
    # if ($invalidChar) {
    #     LogMessage "Invalid character found in path: $cleanPath."
    #     continue
    # }

    # Find position of last "."
    $lastDot = $cleanPath.LastIndexOf(".")
    $lastSlash = $cleanPath.LastIndexOf("\")
    if ($lastDot -gt $lastSlash -and $lastDot -gt 0) {
        $temp = $cleanPath.Substring($lastDot)
        if (-not $temp.Contains(' ')) {
            $global:ResultExtensions += $temp
        }
    }

    if ($cleanPath -eq "\\") {
        Continue
    }
    # if ($cleanPath.StartsWith(("C:\"))) {
    #     Continue
    # }
    # if ($cleanPath.StartsWith(("U:\"))) {
    #     Continue
    # }

    if ($cleanPath.StartsWith(("\\"))) {
        $temp2 = $cleanPath.TrimStart("\\")
        $temp2 = $temp2.Replace("\\", "\")
        $temp2 = $temp2.Replace("\\", "\")
        $temp2 = $temp2.Replace("\\", "\")
        $temp2 = $temp2.Replace("\\", "\")
        $temp2 = $temp2.Replace("\\", "\")
        $cleanPath = '\\' + $temp2.Replace("\\", "\")
    }

    if ($cleanPath.Length -gt 3) {
        if ($cleanPath.Substring(1, 1) -eq ":") {
            $temp2 = $cleanPath.Substring(0, 2)
            $temp3 = $cleanPath.Substring(2)
            $temp3 = $temp3.Replace("\\", "\")
            $temp3 = $temp3.Replace("\\", "\")
            $temp3 = $temp3.Replace("\\", "\")
            $temp3 = $temp3.Replace("\\", "\")
            $temp3 = $temp3.Replace("\\", "\")

            $cleanPath = $temp2 + $temp3
        }
    }

    if ($cleanPath.Length -le 2) {
        Continue
    }

    if ($cleanPath.StartsWith(("\\"))) {
        $temp2 = $cleanPath.TrimStart("\\")
        $temp2 = $temp2.Split("\")[0]
        $global:ResultMachines += $temp2
    }

    # $invalidChar = $cleanPath | Select-String -Pattern '[^\x20-\x7E\xC6\xE6\xD8\xF8\xC5\xE5\x2E\x24\x5C\x3A]' -AllMatches
    # if ($invalidChar) {
    #     $invalidChar.Matches | ForEach-Object {
    #         $hexValue = [System.Text.Encoding]::UTF8.GetBytes($_.Value) | ForEach-Object { '0x{0:X}' -f $_ }
    #         LogMessage "Invalid character found in path: $cleanPath. Hex value: $hexValue"
    #     }
    #     continue
    # }

    # $global:Results += [PSCustomObject]@{
    #     FilePath   = $searchObject.FilePath.Replace(($workFolder + "\"), "")
    #     Type       = $searchObject.Type
    #     Match      = $cleanPath
    #     MatchIndex = $searchObject.LineNumber
    #     Line       = $line.Line.Trim()
    # }

    $global:ResultTexts += $searchObject.FilePath.Replace(($workFolder + "\"), "") + ";" + $searchObject.Type + ";" + $cleanPath + ";" + $searchObject.LineNumber + ";" + $searchObject.Line.Trim()

    if ($cleanPath.Trim().Length -gt 0) {
        $global:ResultPaths += $cleanPath
    }
    $pathOrig = $cleanPath
    $path = $cleanPath

    if ($searchObject.Type -eq "SETDB2") {
        $pathOrig = $searchObject.Line
        $path = $searchObject.Line.Replace("DB=FKAVDNT", "DB=DB2DEV")
    }

    if ($searchObject.Type -eq "UNC" ) {
        if ($path -eq "\\") {
            Continue
        }

        if ($path.Length -le 2) {
            Continue
        }

        if ($path.StartsWith("\\")) {
            $path = $path.TrimStart("\")
            $path = $env:VCPATH + "\net\srv\" + $path
        }
    }

    if ($searchObject.Type -eq "DRIVE" ) {
        if ($path.Length -gt 2) {
            if ($path.Substring(1, 1) -eq ":") {
                $path = $env:VCPATH + "\net\drv\" + $path.Substring(0, 1) + "\" + $path.Substring(2).TrimEnd("\") + "\"
            }
        }
    }

    if ($searchObject.Type -eq "DRIVE" -or $searchObject.Type -eq "UNC") {
        if ($path.Length -gt 2) {
            $path = $path.TrimEnd("\") + "\"
            $path = $path.Replace("\\", "\")
            $global:NewPaths += $path
        }
    }
    $global:Files += $searchObject.FilePath
    # Logger -message "File: $($searchObject.FilePath) Type: $($searchObject.Type) Line: $($searchObject.LineNumber) Match: $cleanPath"
    $Global:counter++
    if ($Global:counter % 1000 -eq 0) {
        Logger -message "Counter: $Global:counter. FileCounter $Global:filecounter."
    }

    $global:FileChanges += $searchObject.FilePath + ";" + $searchObject.Type + ";" + $searchObject.LineNumber + ";" + $pathOrig + ";" + $path
}
# Define the folder path you want to check and create
$StartPath = $$
$pos = $StartPath.LastIndexOf("\")
$StartPath = $StartPath.Substring(0, $pos + 1)

$Global:counter = 0
$Global:filecounter = 0
$PSWorkPath = $env:PSWorkPath
$srcRootFolder = $PSWorkPath
$workFolder = "$PSWorkPath\VisualCobolCodeMigration"
$DedgeFolder = "$PSWorkPath\VisualCobolCodeMigration\Dedge"

$DedgeCblFolder = $DedgeFolder + "\cbl"
$outputFolder = "$PSWorkPath\VisualCobolCodeMigration\Content"

$env:VCPATH

$ChangeLeadingPath = $env:VCPATH + "\net"
# Remove and recreate folder
Remove-Item -Path $ChangeLeadingPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path $ChangeLeadingPath -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

# Check if the folder exists
$repository = "https://Dedge.visualstudio.com/DefaultCollection/Dedge/_git/Dedge"

Remove-Item -Path $workFolder -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $DedgeFolder -Recurse -Force -ErrorAction SilentlyContinue

New-Item -Path $workFolder -ItemType Directory -ErrorAction SilentlyContinue
New-Item -Path $DedgeFolder -ItemType Directory -ErrorAction SilentlyContinue
New-Item -Path $outputFolder -ItemType Directory -ErrorAction SilentlyContinue

Write-Output "Retreiving repository: $DedgeFolder"
# check if directory is empty
Set-Location -Path $DedgeFolder
if ((Get-ChildItem -Path $DedgeFolder).Count -eq 0) {
    git.exe clone $repository $DedgeFolder
}
else {
    git.exe pull

}

function GetSearchObject ($fileFullName, $fileBaseName, $fileExtension, $type, $lineText, $lineNumber, $matchText, $matchPosition ) {
    $result = [PSCustomObject]@{
        FilePath      = $fileFullName.ToString().ToUpper()
        FileBasename  = $fileBaseName.ToString().ToUpper()
        FileExtention = $fileExtension.ToString().ToUpper()
        Type          = $type
        Line          = $lineText
        LineNumber    = $lineNumber
        MatchText     = $matchText
        MatchPosition = $matchPosition
    }
    return $result
}
# $selectedLinesTemp = GetSelectedLines -file $file -content $content -type "PATH" -pattern '(\\\\[^\s\\]+\\[^\\s ]+)|([a-zA-Z]:\\[^\\s ]+)'
#     if ($null -ne $selectedLinesTemp) {
#         $selectedLines = $selectedLinesTemp
#     }
#     $selectedLinesTemp = GetSelectedLines -file $file -content $content -type "MISC" -pattern '(?<!N:\\)COBNT|(?<!N:\\)COBTST|(?<!K:\\)FKAVD\\NT\\'
#     if ($null -ne $selectedLinesTemp) {
#         $selectedLines = $selectedLinesTemp
#     }
#     $selectedLinesTemp = GetSelectedLines -file $file -content $content -type "RUN" -pattern '^\s*RUNW\s+|^\s*RUN\s+'
#     if ($null -ne $selectedLinesTemp) {
#         $selectedLines = $selectedLinesTemp
#     }
#     $selectedLinesTemp = GetSelectedLines -file $file -content $content -type "CALLRUN" -pattern 'CALL\s+RUNW\s+|CALL\s+RUN\s+'
#     if ($null -ne $selectedLinesTemp) {
#         $selectedLines = $selectedLinesTemp
#     }
#     $selectedLinesTemp = GetSelectedLines -file $file -content $content -type "SETDB2" -pattern 'SET DB2.*DB=FKAVDNT'
#     if ($null -ne $selectedLinesTemp) {
#         $selectedLines = $selectedLinesTemp
#     }
#     $selectedLinesTemp = GetSelectedLines -file $file -content $content -type "INVALID_SETDB2" -pattern 'SET DB2.*DB=(?!FKAVDNT)\w+'
#     if ($null -ne $selectedLinesTemp) {
#         $selectedLines = $selectedLinesTemp
#     }
#     $selectedLinesTemp = GetSelectedLines -file $file -content $content -type "SQLENV" -pattern 'COPY.*SQLENV.*.'
#     if ($null -ne $selectedLinesTemp) {
#         $selectedLines = $selectedLinesTemp
#     }
#     $selectedLinesTemp = GetSelectedLines -file $file -content $content -type "REXX" -pattern 'REXX\s+'
#     if ($null -ne $selectedLinesTemp) {
#         $selectedLines = $selectedLinesTemp
#     }
function GetSelectedLines ($file, $content, $objectArray) {

    $results = @()
    $allPatterns = ($objectArray | Select-Object -ExpandProperty Pattern) -join "|"

    $validate = $content | Select-String -Pattern $allPatterns -AllMatches
    if ($null -eq $validate) {
        return $results
    }

    foreach ($line in $content) {
        foreach ($object in $objectArray) {
            if ($file.Extension.ToUpper() -ne ".CPX" -and $object.Type -eq "CPX") {
                continue
            }

            if ($line.Contains("SET DB2") -and $object.Type -eq "DBALIAS") {
                continue
            }
            $pattern = $object.Pattern
            $type = $object.Type
            [regex]$Regex = $pattern
            $mymatches = $Regex.Matches($line)
            foreach ($item in $mymatches) {
                $lineNumber = $content.IndexOf($line) + 1
                $match = $item
                $matchText = $item.Value
                $matchPosition = $item.Index
                if ($type -eq "UNC" -or $type -eq "DRIVE") {
                    $pos = $matchText.IndexOf(" ")
                    if ($pos -gt 0) {
                        $matchText = $matchText.Substring(0, $pos)
                    }

                    $pos = $matchText.IndexOf("'")
                    if ($pos -gt 0) {
                        $matchText = $matchText.Substring(0, $pos)
                    }

                    $pos = $matchText.IndexOf(")")
                    if ($pos -gt 0) {
                        $matchText = $matchText.Substring(0, $pos)
                    }

                    $pos = $matchText.IndexOf('"')
                    if ($pos -gt 0) {
                        $matchText = $matchText.Substring(0, $pos)
                    }
                    $pos = $matchText.IndexOf(',')
                    if ($pos -gt 0) {
                        $matchText = $matchText.Substring(0, $pos)
                    }
                    $pos1 = $matchText.LastIndexOf('.')
                    $pos2 = $matchText.LastIndexOf('\')
                    if ($pos1 -gt $pos2) {
                        $matchText = $matchText.Substring(0, $pos2 + 1)
                    }

                    $matchText = $matchText.Trim() + "\"

                }

                $results += GetSearchObject -fileFullName $file.FullName -fileBaseName $file.BaseName -fileExtension $file.Extension -type $type -lineText $line -lineNumber $lineNumber -matchText $matchText -matchPosition $matchPosition
            }
        }
    }

    return $results
}

FKASendSMSDirect -receiver "+4797188358" -message "CodeSearch started. Approximately 10 minutes to complete if ran on local files."

$global:logFolder = $outputFolder

# Initialize a list to store global:Results
$global:Results = @()

$global:Resultglobal:Files = @()
$global:ResultPaths = @()
$global:ResultMachines = @()
$global:ResultExtensions = @()
$global:NewPaths = @()
$global:Files = @()
$global:FileChanges = @()
$global:ResultTexts = @()

$objectArray = @(
    [PSCustomObject]@{
        Pattern = '\\\\[^\s\\]+.*?(?=[''"\),\s>]|$)'
        Type    = "UNC"
    },
    [PSCustomObject]@{
        Pattern = '[a-zA-Z]:\\+.*?(?=[''"\),\s>]|$)'
        Type    = "DRIVE"

    },
    [PSCustomObject]@{
        Pattern = '(?<!N:\\)COBNT|(?<!N:\\)COBTST|(?<!K:\\)FKAVD\\NT\\'
        Type    = "MISC"
    },
    [PSCustomObject]@{
        Pattern = '^\s*DB2CMD\s+'
        Type    = "DB2CMD"
    }, [PSCustomObject]@{
        Pattern = '^\s*RUNW\s+|^\s*RUN\s+'
        Type    = "RUN"
    },
    [PSCustomObject]@{
        Pattern = 'CALL\s+RUNW\s+|CALL\s+RUN\s+'
        Type    = "CALLRUN"
    },
    [PSCustomObject]@{
        Pattern = 'SET DB2.*DB=FKAVDNT'
        Type    = "SETDB2"
    },
    [PSCustomObject]@{
        Pattern = 'SET DB2.*DB=(?!FKAVDNT)\w+'
        Type    = "INVALID_SETDB2"
    },
    [PSCustomObject]@{
        Pattern = 'COPY.*SQLENV.*.'
        Type    = "SQLENV"
    },
    [PSCustomObject]@{
        Pattern = 'REXX\s+'
        Type    = "REXX"
    },
    # "BASISPRO","BASISHST","BASISRAP","BASISTST","VISMABUS","VISMAHST","FKKONTO","FKAVDNT","BASISMIG","BASISSIT","VISMAMIG"
    [PSCustomObject]@{
        Pattern = 'BASISPRO|BASISHST|BASISRAP|BASISTST|VISMABUS|VISMAHST|FKKONTO|FKAVDNT|BASISMIG|BASISSIT|VISMAMIG'
        Type    = "DBALIAS"
    }
    [PSCustomObject]@{
        Pattern = ' 01 '
        Type    = "CPX"
    }
    [PSCustomObject]@{
        Pattern = '\\t'
        Type    = "TAB"
    }
)

# Recursively search for global:Files in subdirectories
$fileArray = Get-ChildItem $DedgeFolder -Recurse  -Include "*.cbl", "*.cpy", "*.cpb", "*.cpx", "*.imp", "*.dcl", "*.ps1", "*.psm1", "*.bat", "*.rex", "*.cmd" -File

# $fileArray = Get-ChildItem "$env:OptPath\WORK\VISUALCOBOLCODEMIGRATION\Dedge\BAT\RESTDB_VFT_TIL_DB2DEV.BAT" -Recurse  -Include "*.cbl", "*.cpy", "*.cpb", "*.cpx", "*.imp", "*.dcl", "*.ps1", "*.psm1", "*.bat", "*.rex", "*.cmd" -File

$counter = 0
# Loop through each file
foreach ($file in $fileArray) {
    $Global:filecounter++

    # Read content
    $contentOriginal = ConvertFileFromAnsi1252ToUtf8String -fileName $file.FullName
    $content = $contentOriginal -split "`r`n"  # Split content into individual lines

    $selectedLines = $null
    $selectedLines = GetSelectedLines -file $file -content $content -objectArray $objectArray

    if ($file.BaseName.ToUpper() -eq "GMAOPVA" -and $file.Extension.ToUpper() -eq ".CBL") {
        $type = "SPECIAL"
        $selectedLinesTemp = GetSearchObject -fileFullName $file.FullName -fileBaseName $file.BaseName -fileExtension $file.Extension -type $type -lineText "           EXEC SQL WHENEVER SQLWARNING GO TO M990-SQL-TRAP END-EXEC" -lineNumber 757 -matchText "      *    EXEC SQL WHENEVER SQLWARNING GO TO M990-SQL-TRAP END-EXEC" -matchPosition 0
        if ($null -ne $selectedLinesTemp) {
            $selectedLines = $selectedLinesTemp
        }
    }

    if ($null -eq $selectedLines) {
        continue
    }

    foreach ($searchObject in $selectedLines) {
        HandleSelectedLines -searchObject $searchObject
    }
}

foreach ($path in $global:NewPaths) {
    try {
        New-Item -Path $path -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Host "Error: $_ on path $path"
    }
}

# # Remove duplicates from the global:Results
# Remove-Item -Path "$outputFolder\Results.txt" -Force -ErrorAction SilentlyContinue
# $global:Results = $global:Results | Sort-Object -Property FilePath, Type, Match, Line -Unique
# $global:Results | Out-File -FilePath "$outputFolder\Results.txt" -Encoding utf8

Remove-Item -Path "$outputFolder\ResultMachines.txt" -Force -ErrorAction SilentlyContinue
$global:ResultMachines = $global:ResultMachines | Sort-Object -Unique
$global:ResultMachines | Out-File -FilePath "$outputFolder\ResultMachines.txt" -Encoding utf8

Remove-Item -Path "$outputFolder\ResultMachines.txt" -Force -ErrorAction SilentlyContinue
$global:ResultExtensions = $global:ResultExtensions | Sort-Object -Unique
$global:ResultMachines | Out-File -FilePath "$outputFolder\ResultMachines.txt" -Encoding utf8

Remove-Item -Path "$outputFolder\ResultPaths.txt" -Force -ErrorAction SilentlyContinue
$global:ResultPaths = $global:ResultPaths | Sort-Object -Unique
$global:ResultPaths | Out-File -FilePath "$outputFolder\ResultPaths.txt" -Encoding utf8

Remove-Item -Path "$outputFolder\NewPaths.txt" -Force -ErrorAction SilentlyContinue
$global:NewPaths = $global:NewPaths | Sort-Object -Unique
$global:NewPaths | Out-File -FilePath "$outputFolder\NewPaths.txt" -Encoding utf8

Remove-Item -Path "$outputFolder\Files.txt" -Force -ErrorAction SilentlyContinue
$global:Files = $global:Files | Sort-Object -Unique
$global:Files | Out-File -FilePath "$outputFolder\Files.txt" -Encoding utf8

Remove-Item -Path "$outputFolder\FileChanges.txt" -Force -ErrorAction SilentlyContinue
$global:FileChanges = $global:FileChanges | Sort-Object -Unique
$global:FileChanges | Out-File -FilePath "$outputFolder\FileChanges.txt" -Encoding utf8

Remove-Item -Path "$outputFolder\ResultTexts.txt" -Force -ErrorAction SilentlyContinue
$global:ResultTexts = $global:ResultTexts | Sort-Object -Unique
$global:ResultTexts | Out-File -FilePath "$outputFolder\ResultTexts.txt" -Encoding utf8

Set-Location -Path $StartPath

# Send SMS
FKASendSMSDirect -receiver "+4797188358" -message "CodeSearch completed. Results are available in $outputFolder"
LogMessage -message "CodeSearch completed. Results are available in $outputFolder"

