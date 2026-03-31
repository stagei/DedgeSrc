
Import-Module -Name FKASendSMSDirect -Force





function LogMessage {
    param(
        $message
    )
    $dtLog = get-date -Format("yyyyMMdd").ToString()
    $logfile = "\\DEDGE.fk.no\erpprog\cobnt\" + $dtLog + "_VisualCobolPathSearch.log"
    $logfile1 = $global:logFolder + "\" + $dtLog + "_VisualCobolPathSearch.log"
    $dt = get-date -Format("yyyy-MM-dd HH:mm:ss,ffff").ToString()

    $logmsg = $dt + ": VisualCobolPathSearch :  " + $message

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
    if ($cleanPath.Contains('\*.')) {
        $cleanPath = $cleanPath.Split('"')[0]
    }
    if ($cleanPath.Contains('"')) {
        $cleanPath = $cleanPath.Split('"')[0]
    }
    if ($cleanPath.Contains('"')) {
        $cleanPath = $cleanPath.Split('"')[0]
    }
    if ($cleanPath.Contains('"')) {
        $cleanPath = $cleanPath.Split('"')[0]
    }


    $extenstionArray = @(".TXT", ".LOG", ".BAT", ".%COMPUTERNAME%", ".TEST", ".AKT", ".CSV", ".ERR", ".BND")
    $extenstionArray += @(".CPY", ".DEL", ".DFT", ".EXE", ".FNK", ".GS", ".ICN", ".INT", ".JPG", ".PRN", ".REX", ".SQL")

    foreach ($ext in $extenstionArray) {
        if ($cleanPath.Contains($ext)) {
            $cleanPath = $cleanPath.Split($ext)[0]
            # Find previous "\" and remove string after that
            $lastSlash = $cleanPath.LastIndexOf("\")
            $cleanPath = $cleanPath.Substring(0, $lastSlash + 1)
            break
        }
    }



    #if cleanPath contains non valid characters lower than ascii 32, remove them
    $cleanPath = $cleanPath -replace "[^\x20-\x7E]", ""

    return $cleanPath
}

# Define the folder path you want to check and create
$PSWorkPath = $env:PSWorkPath
$srcRootFolder = $PSWorkPath
$workFolder = "$PSWorkPath\VisualCobolPathSearch"
$DedgeFolder = "$PSWorkPath\VisualCobolPathSearch\Dedge"

$DedgeCblFolder = $DedgeFolder + "\cbl"
$outputFolder = "$PSWorkPath\VisualCobolPathSearch\Content"




# Check if the folder exists
$repository = "https://Dedge.visualstudio.com/DefaultCollection/Dedge/_git/Dedge"

# Remove-Item -Path $workFolder -Recurse -Force -ErrorAction SilentlyContinue


New-Item -Path $workFolder -ItemType Directory -ErrorAction SilentlyContinue
New-Item -Path $DedgeFolder -ItemType Directory -ErrorAction SilentlyContinue
New-Item -Path $outputFolder -ItemType Directory -ErrorAction SilentlyContinue


Push-Location
Set-Location -Path $workFolder
$workFolder = (Get-Location).Path
Pop-Location

Push-Location
Set-Location -Path $DedgeFolder
$DedgeFolder = (Get-Location).Path
Pop-Location

# Write-Output "Retreiving repository: $DedgeFolder"
# git.exe clone $repository $DedgeFolder

Push-Location
Set-Location -Path $DedgeFolder
$DedgeFolder = (Get-Location).Path
Pop-Location

Push-Location
Set-Location -Path $DedgeCblFolder
$DedgeCblFolder = (Get-Location).Path
Pop-Location

Push-Location
Set-Location -Path $srcRootFolder
$srcRootFolder = (Get-Location).Path
Pop-Location

Push-Location
Set-Location -Path $outputFolder
$outputFolder = (Get-Location).Path
Pop-Location
$global:logFolder = $outputFolder


# # Define regex patterns for UNC paths and Windows drive letters
# $UNCPattern = '\\\\[^\\]+\\[^\\]+'
# $DriveLetterPattern = '[A-Z]:\\[^\\]+'

# Initialize a list to store results
$Results = @()
$ResultFiles = @()
$ResultPaths = @()
$ResultMachines = @()
$ResultExtensions = @()


# Recursively search for files in subdirectories
$files = Get-ChildItem $DedgeFolder -Recurse  -Include "*.cbl", "*.cpy", "*.cpb", "*.imp", "*.dcl", "*.ps1", "*.psm1", "*.bat", "*.rex", "*.cmd" -File
# $files = Get-ChildItem $DedgeFolder"\bat_prod\MEHPRD.BAT" -Recurse  -Include "*.cbl", "*.cpy", "*.cpb", "*.imp", "*.dcl", "*.ps1", "*.psm1", "*.bat", "*.rex", "*.cmd" -File

# Loop through each file
foreach ($file in $files) {

    # Read content as ansi-1252
    $content = Get-Content $file.FullName -Encoding Default

    # $selectedLines = $content | Select-String -Pattern '(\\\\[^\s\\]+\\[^\\s ]+)|([a-zA-Z]:\\[^\\s ]+)' -AllMatches
    $selectedLines = $content | Select-String -Pattern '(\\\\[^\s\\]+\\[^\s ]+)|([a-zA-Z]:\\[^\s ]+)' -AllMatches

    if ($null -eq $selectedLines) {
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

    foreach ($line in $selectedLines) {

        # $pattern = '(\\\\[^\s\\]+\\[^\\s ]+)|([a-zA-Z]:\\[^\\s ]+)'
        # $mymatches = [regex]::Matches($line.Line.Trim().ToUpper(), $pattern)
        
        foreach ($lineMatch in $line.Matches) {
            $cleanPath = $lineMatch.Value.Trim().ToUpper()
            # Check if $cleanPath contains a space and if it does, split the string and take the first part


            $cleanPath = removeFilenameFromCleanPath -cleanPath $cleanPath

            # Find position of last "." 
            $lastDot = $cleanPath.LastIndexOf(".")
            if ($lastDot -gt 0) {
                $temp = $cleanPath.Substring($lastDot)
                if (-not $temp.Contains(' ')) {
                    $ResultExtensions += "EndString(.): " + $temp
                }
            }
            # Find position of last "\" 
            $lastDot = $cleanPath.LastIndexOf("\")
            if ($lastDot -gt 0) {
                $temp = $cleanPath.Substring($lastDot)
                if (-not $temp.Contains(' ')) {
                    $ResultExtensions += "EndString(\): " + $temp
                }
            }

            $cleanPath = $cleanPath.TrimEnd("\")
                      
            $Results += [PSCustomObject]@{
                FilePath   = $file.FullName.Replace(($workFolder + "\"), "")
                LineNumber = $line.LineNumber
                Match      = $cleanPath
                Line       = $line.Line.Trim()
            }
            $ResultPaths += $cleanPath
            if ($cleanPath.StartsWith(("\\\\"))) {
                $temp2 = $cleanPath.Substring(2)
                $temp2 = $temp2.Split("\")[0]
                $ResultMachines += $temp2
            }
        }
    }
}

# Remove duplicates from the results
$Results = $Results | Sort-Object -Property FilePath, LineNumber, Match, Line -Unique


$excel = New-Object -ComObject Excel.Application
$workbook = $excel.Workbooks.Add()
$worksheet = $workbook.Worksheets.Item(1)

$row = 1
$column = 1

# Add headings from property names
$propertyIndex = 1
$Results[0].PSObject.Properties | ForEach-Object {
    $worksheet.Cells.Item($row, $column).Value2 = $_.Name
    $column++
    $propertyIndex++
}

$row++
$column = 1

$Results | ForEach-Object {
    $propertyIndex = 1
    $_.PSObject.Properties | ForEach-Object {
        $worksheet.Cells.Item($row, $column).Value2 = $_.Value.ToString()
        $column++
        $propertyIndex++
    }
    $row++
    $column = 1
}

$workbook.SaveAs("$outputFolder\ResultDetails.xlsx")
$workbook.Close()
$excel.Quit()



$ResultPaths = $ResultPaths | Sort-Object -Unique
$ResultPaths | Out-File -FilePath "$outputFolder\ResultPaths.txt" -Encoding utf8

$ResultMachines = $ResultMachines | Sort-Object -Unique
$ResultMachines | Out-File -FilePath "$outputFolder\ResultMachines.txt" -Encoding utf8

$ResultExtensions = $ResultExtensions | Sort-Object -Unique
$ResultExtensions | Out-File -FilePath "$outputFolder\ResultExtensions.txt" -Encoding utf8




# Remove-Item -Path $DedgeFolder -Recurse -Force -ErrorAction SilentlyContinue
