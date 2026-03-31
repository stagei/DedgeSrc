
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

function HandleSelectedLines ($type, $file, $line) {
    if ($file.BaseName.ToUpper() -eq "DOHCBLD" -or $file.BaseName.ToUpper() -eq "DOHCHK" -or $file.BaseName.ToUpper() -eq "DOHCHK2" -or $file.BaseName.ToUpper() -eq "DOHCHK3" -or $file.BaseName.ToUpper() -eq "DOHCHK4" -or $file.BaseName.ToUpper() -eq "DOHCHK6" -or $file.BaseName.ToUpper() -eq "DOHUTGAT" -or $file.BaseName.ToUpper() -eq "DOHSCAN") {
        continue
    }
 
    if ($file.Extension -eq ".BAT" -and ($line.Line.ToUpper().StartsWith("REM") -or $line.Line.ToUpper().StartsWith("@REM")) ) {
        continue
    }

    if ($file.Extension -eq ".CMD" -and ($line.Line.ToUpper().StartsWith("REM") -or $line.Line.ToUpper().StartsWith("@REM")) ) {
        continue
    }

    if ($file.Extension -eq ".PSM1" -and ($line.Line.ToUpper().StartsWith("#")) ) {
        continue
    }

    if ($file.Extension -eq ".PS1" -and ($line.Line.ToUpper().StartsWith("#")) ) {
        continue
    }

    if ($file.Extension -eq ".CBL" -and ($line.Line.Trim().ToUpper().StartsWith("*")) ) {
        continue
    }

    if ($file.Extension -eq ".DCL" -and ($line.Line.Trim().ToUpper().StartsWith("*")) ) {
        continue
    }

    if ($file.Extension -eq ".CPY" -and ($line.Line.Trim().ToUpper().StartsWith("*")) ) {
        continue
    }

    if ($file.Extension -eq ".CPB" -and ($line.Line.Trim().ToUpper().StartsWith("*")) ) {
        continue
    }

    if ($file.Extension -eq ".REX" -and ($line.Line.Trim().ToUpper().StartsWith("/*")) ) {
        continue
    }


    # $pattern = '(\\\\[^\s\\]+\\[^\\s ]+)|([a-zA-Z]:\\[^\\s ]+)'
    # $mymatches = [regex]::Matches($line.Line.Trim().ToUpper(), $pattern)
    
    foreach ($lineMatch in $line.Matches) {
        $tempPath = $lineMatch.Value.Trim().ToUpper()
        # Check if $tempPath contains a space and if it does, split the string and take the first part

        if ($tempPath.Contains("BRUKERID")) {
            $tempPath = $tempPath
        }
        $pathList = @()
        if ($tempPath.Contains(",")) {
            $pathList = $tempPath.Split(",")
        }
        else {
            $pathList = $tempPath.Trim()
        }
        foreach ($cleanPath in $pathList) {
            if (-not $cleanPath.EndsWith("\") -and -not $cleanPath.Contains(".") -and -not $cleanPath.Contains("*") -and -not $cleanPath.Contains("%") -and -not $cleanPath.Contains("?") -and -not $cleanPath.EndsWith("_")) {
                $cleanPath = $cleanPath.Trim() + "\"
            }

            if ($cleanPath.Length -gt 1) {
                if ($cleanPath.StartsWith("C:") -or $cleanPath.StartsWith("U:")) {
                    $cleanPath = $cleanPath.TrimStart("\")
                }
                
            }

            $cleanPath = $cleanPath -replace '\x0A', '' -replace '\x00', '' -replace '\x0D', '' -replace '\x1A', ''

            if ($type -eq "PATH") {
                $cleanPath = removeFilenameFromCleanPath -cleanPath $cleanPath
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

            $invalidChar = $cleanPath | Select-String -Pattern '[^\x20-\x7E\xC6\xE6\xD8\xF8\xC5\xE5\x2E\x24\x5C\x3A]' -AllMatches
            if ($invalidChar) {
                $invalidChar.Matches | ForEach-Object {
                    $hexValue = [System.Text.Encoding]::UTF8.GetBytes($_.Value) | ForEach-Object { '0x{0:X}' -f $_ }
                    LogMessage "Invalid character found in path: $cleanPath. Hex value: $hexValue"
                }
                continue
            }
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


            $global:Results += [PSCustomObject]@{
                FilePath   = $file.FullName.Replace(($workFolder + "\"), "")
                Type       = $type
                Match      = $cleanPath
                MatchIndex = $lineMatch.Index
                Line       = $line.Line.Trim()
            }

            $global:ResultTexts += $file.FullName.Replace(($workFolder + "\"), "") + ";" + $type + ";" + $cleanPath + ";" + $lineMatch.Index + ";" + $line.Line.Trim() 

            if ($cleanPath.Trim().Length -gt 0) {
                $global:ResultPaths += $cleanPath
            }

            $path = $cleanPath
            $pathOrig = $cleanPath
            if ($type -eq "SETDB2") {
                $path = $pathOrig.Replace("DB=FKAVDNT", "DB=DB2DEV")
            }

            if ($type -eq "PATH") {
                if ($path -eq "\\" -and $path.Length -le 2) {
                    Continue
                }
    
                if ($path.StartsWith("\\")) {
                    $path = $path.TrimStart("\")
                    $path = $ChangeLeadingPath + "\srv\" + $path
                }
                else {
                    if ($path.Substring(1, 1) -eq ":") {
                        $path = $ChangeLeadingPath + "\drv\" + $path.Substring(0, 1) + "\" + $path.Substring(2)
                    }                
                }                
  
                $path = $path.TrimEnd("\") + "\"
                $path = $path.Replace("\\", "\")
   
                $global:NewPaths += $path
            }
            $global:Files += $file.FullName

            $global:FileChanges += $file.FullName + ";" + $type + ";" + $lineMatch.Index + ";" + $pathOrig + ";" + $path
        }            
    }
}
# Define the folder path you want to check and create
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

# Remove-Item -Path $workFolder -Recurse -Force -ErrorAction SilentlyContinue


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

function GetSelectedLines ($file, $content, $pattern, $type) {

    [regex]$Regex = $pattern     # Your regex pattern

    $contentArray = $content -split "`r?`n" | ForEach-Object -Begin { $lineNumber = 0 } -Process { [PSCustomObject]@{ LineNumber = $lineNumber++; Line = $_ } }

    $results = @()
    $mymatches = $Regex.Matches($content)

    foreach ($match in $mymatches) {
        $lineNumber = ($content.Substring(0, $match.Index) | Measure-Object -Line).Lines
        $lineText = $content[$lineNumber - 1]
        $matchText = $match.Value
        $matchPosition = $match.Index

        $results += [PSCustomObject]@{
            FilePath      = $file.FullName
            FileBasename  = $file.BaseName
            FileExtention = $file.Extension
            Type          = $type
            Line          = $lineText
            LineNumber    = $lineNumber
            MatchText     = $matchText
            MatchPosition = $matchPosition            
        }
    
    }
    return $results    
}

$global:logFolder = $outputFolder


# # Define regex patterns for UNC paths and Windows drive letters
# $UNCPattern = '\\\\[^\\]+\\[^\\]+'    
# $DriveLetterPattern = '[A-Z]:\\[^\\]+'

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

# Recursively search for global:Files in subdirectories
$fileArray = Get-ChildItem $DedgeFolder -Recurse  -Include "*.cbl", "*.cpy", "*.cpb", "*.cpx", "*.imp", "*.dcl", "*.ps1", "*.psm1", "*.bat", "*.rex", "*.cmd" -File
#$global:Files = Get-ChildItem $DedgeFolder"\bat\RESTORE_BASISREG.BAT" -Recurse  -Include "*.cbl", "*.cpy", "*.cpb", "*.imp", "*.dcl", "*.ps1", "*.psm1", "*.bat", "*.rex", "*.cmd" -File



$counter = 0
# Loop through each file
foreach ($file in $fileArray) {

    # Read content 
    $content = ConvertFileFromAnsi1252ToUtf8String -fileName $file.FullName
    $selectedLines1 = $null
    $selectedLines2 = $null
    $selectedLines3 = $null
    $selectedLines4 = $null
    $selectedLines5 = $null
    $selectedLines6 = $null
    $selectedLines7 = $null

    $selectedLines1 = $content | Select-String -Pattern '(\\\\[^\s\\]+\\[^\\s ]+)|([a-zA-Z]:\\[^\\s ]+)' -AllMatches
    $selectedLines2 = $content | Select-String -Pattern '(?<!N:\\)COBNT|(?<!N:\\)COBTST|(?<!K:\\)FKAVD\\NT\\' -AllMatches
    $selectedLines3 = $content | Select-String -Pattern 'RUNW\s+|RUN\s+' -AllMatches

    # $selectedLines3 = $content | Select-String -Pattern 'RUNW\s+|RUN\s+' -AllMatches| ForEach-Object {
    #     $lineNumber = $_.LineNumber
    #     $line = $_.Line
    #     # Process the line or store it in a variable
    #     # ...
    #     # Return an object with line number and line
    #     [PSCustomObject]@{
    #         LineNumber = $lineNumber
    #         Line = $line
    #     }}

    $test = GetSelectedLines -file $file -content $content -type "RUN" -pattern 'RUNW\s+|RUN\s+'
    # [regex]$Regex = "RUNW\s+|RUN\s+"     # Your regex pattern

    # $mymatches = $Regex.Matches($content)

    # foreach ($match in $mymatches) {
    #     $lineNumber = ($content.Substring(0, $match.Index) | Measure-Object -Line).Lines + 1
    #     $lineText = $content[$lineNumber - 1]
    #     $matchText = $match.Value
    #     $matchPosition = $match.Index
    # }
    

    $selectedLines4 = $content | Select-String -Pattern 'SET DB2.*DB=FKAVDNT' -AllMatches
    $selectedLines5 = $content | Select-String -Pattern 'SET DB2.*DB=(?!FKAVDNT)\w+' -AllMatches
    $selectedLines6 = $content | Select-String -Pattern 'COPY.*SQLENV.*.' -AllMatches
    $selectedLines7 = $content | Select-String -Pattern 'REXX\s+' -AllMatches 

    if ($file.BaseName.ToUpper() -eq "GMAOPVA" -and $file.Extension.ToUpper() -eq ".CBL") {
        $type = "SPECIAL"
        $global:Files += $file.FullName
        $global:FileChanges += $file.FullName + ";" + $type + ";" + 755 + "           EXEC SQL WHENEVER SQLWARNING GO TO M990-SQL-TRAP END-EXEC" + ";" + ";" + "      *    EXEC SQL WHENEVER SQLWARNING GO TO M990-SQL-TRAP END-EXEC"
    } 

    if ($null -eq $selectedLines1 -and 
        $null -eq $selectedLines2 -and 
        $null -eq $selectedLines3 -and 
        $null -eq $selectedLines4 -and 
        $null -eq $selectedLines5 -and 
        $null -eq $selectedLines6 -and 
        $null -eq $selectedLines7 -and 
        $null -eq $selectedLines8
    ) {
        continue
    }
    

    foreach ($line in $selectedLines1) {
        $type = "PATH"
        HandleSelectedLines -type $type -file $file -line $line
    }

    foreach ($line in $selectedLines2) {
        $type = "MISC"
        HandleSelectedLines -type $type -file $file -line $line
    }

    foreach ($line in $selectedLines3) {
        $type = "RUN"
        HandleSelectedLines -type $type -file $file -line $line
    }

    foreach ($line in $selectedLines4) {
        $type = "SETDB2"
        HandleSelectedLines -type $type -file $file -line $line
    }

    foreach ($line in $selectedLines5) {
        $type = "INVALID_SETDB2"
        HandleSelectedLines -type $type -file $file -line $line
    }

    foreach ($line in $selectedLines6) {
        $type = "SQLENV"
        HandleSelectedLines -type $type -file $file -line $line
    }

    foreach ($line in $selectedLines7) {
        $type = "REXX"
        HandleSelectedLines -type $type -file $file -line $line
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


# Remove duplicates from the global:Results
Remove-Item -Path "$outputFolder\Results.txt" -Force -ErrorAction SilentlyContinue
$global:Results = $global:Results | Sort-Object -Property FilePath, Type, Match, Line -Unique
$global:Results | Out-File -FilePath "$outputFolder\Results.txt" -Encoding utf8

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



# Remove-Item -Path "$outputFolder\ResultDetails.xlsx" -Force -ErrorAction SilentlyContinue


# $excel = New-Object -ComObject Excel.Application
# $workbook = $excel.Workbooks.Add()
# $worksheet = $workbook.Worksheets.Item(1)

# $row = 1
# $column = 1

# # Add headings from property names
# $propertyIndex = 1
# $global:Results[0].PSObject.Properties | ForEach-Object {
#     $worksheet.Cells.Item($row, $column).Value2 = $_.Name
#     $column++
#     $propertyIndex++
# }

# $row++
# $column = 1

# $global:Results | ForEach-Object {
#     $propertyIndex = 1
#     $_.PSObject.Properties | ForEach-Object {
#         $worksheet.Cells.Item($row, $column).Value2 = $_.Value.ToString()
#         $column++
#         $propertyIndex++
#     }
#     $row++
#     $column = 1
# }

# $workbook.SaveAs("$outputFolder\ResultDetails.xlsx")
# $workbook.Close()
# $excel.Quit()





FKASendSMSDirect -receiver "+4797188358" -message "VisualCobolPathSearch completed. Results are available in $outputFolder"
# Remove-Item -Path $DedgeFolder -Recurse -Force -ErrorAction SilentlyContinue
