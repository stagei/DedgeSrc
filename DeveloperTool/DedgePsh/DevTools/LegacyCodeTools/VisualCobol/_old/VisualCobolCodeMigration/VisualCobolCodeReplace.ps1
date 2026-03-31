
Import-Module -Name FKASendSMSDirect -Force
Import-Module -Name ConvertAnsi1252ToUtf8 -Force
Import-Module -Name ConvertUtf8ToAnsi1252 -Force
Import-Module -Name Logger -Force

function Get-FileEncoding {
    param ([Parameter(Mandatory = $true)] [string] $Path)

    [byte[]] $byte = get-content -AsByteStream -ReadCount 4 -TotalCount 4 -Path $Path
    if ($byte[0] -eq 0xef -and $byte[1] -eq 0xbb -and $byte[2] -eq 0xbf) {
        return 'UTF8'
    }
    elseif ($byte[0] -eq 0xfe -and $byte[1] -eq 0xff) {
        return 'Unicode'
    }
    elseif ($byte[0] -eq 0xff -and $byte[1] -eq 0xfe) {
        return 'Unicode'
    }
    elseif ($byte[0] -eq 0 -and $byte[1] -eq 0 -and $byte[2] -eq 0xfe -and $byte[3] -eq 0xff) {
        return 'UTF32'
    }
    else {
        return 'ASCII'
    }
}

function LogMessage {
    param(
        $message
    )
    $dtLog = get-date -Format("yyyyMMdd").ToString()
    $logfile = "\\DEDGE.fk.no\erpprog\cobnt\" + $dtLog + "_VisualCobolCodeMigration.log"
    $logfile1 = $global:logFolder + "\VisualCobolCodeMigration.log"
    $dt = get-date -Format("yyyy-MM-dd HH:mm:ss,ffff").ToString()

    $logmsg = $dt + ": VisualCobolCodeMigration :  " + $message

    Write-Host $logmsg
    Add-Content -Path $logfile -Value $logmsg
    Add-Content -Path $logfile1 -Value $logmsg
}

# FKASendSMSDirect -receiver "+4797188358" -message "Auto-Replace started."
# Define the folder path you want to check and create
$PSWorkPath = $env:PSWorkPath
$StartPath = $$
$pos = $StartPath.LastIndexOf("\")
$StartPath = $StartPath.Substring(0, $pos + 1)
$global:logFolder
$srcRootFolder = $PSWorkPath
$workFolder = "$PSWorkPath\VisualCobolCodeMigration"
$DedgeFolder = "$PSWorkPath\VisualCobolCodeMigration\Dedge"
$global:logFolder = $StartPath

$repository = "https://Dedge.visualstudio.com/DefaultCollection/Dedge/_git/Dedge"
# Remove-Item -Path $DedgeFolder -Recurse -Force -ErrorAction SilentlyContinue
New-Item -Path $DedgeFolder -ItemType Directory -ErrorAction SilentlyContinue
Write-Output "Retreiving repository: $DedgeFolder"
# check if directory is empty
Set-Location -Path $DedgeFolder
if ((Get-ChildItem -Path $DedgeFolder).Count -eq 0) {
    git.exe clone $repository $DedgeFolder
}
else {
    git.exe reset --hard HEAD^
}

$dbaliasPattern = 'BASISPRO|BASISHST|BASISRAP|BASISTST|VISMABUS|VISMAHST|FKKONTO|FKAVDNT|BASISMIG|BASISSIT|VISMAMIG'

$DedgeCblFolder = $DedgeFolder + "\cbl"
$outputFolder = "$PSWorkPath\VisualCobolCodeMigration\Content"

# $filesContent = Get-Content -Path "$outputFolder\Files.txt" | Where-Object { $_ -like "*.bat" -or $_ -like "*.rex" }

$filesContent = Get-Content -Path "$outputFolder\Files.txt"

$counter = 0

foreach ($currentFile in $filesContent) {
    $counter++
    $currentFile = $currentFile.ToString().Trim()
    $newFile = $currentFile.ToString().Trim() + ".new"

    $filePathsContent = $null
    $filePathsContent = Get-Content -Path "$outputFolder\FileChanges.txt" | Where-Object { $_ -like "*$currentFile*" }
    $fileName = [System.IO.Path]::GetFileName($currentFile)
    $fileExtention = [System.IO.Path]::GetExtension($currentFile)
    $fileBasename = [System.IO.Path]::GetFileNameWithoutExtension($currentFile)

    LogMessage  ("File #$counter - " + $fileName + " - Change count: " + $filePathsContent.Length)

    if ($filePathsContent -eq $null) {
        continue
    }

    $VCPath = $env:VCPATH
    $vcDrive = $env:VCPATH.Substring(0, 2)

    $content = $null

    $utf8InputFile = $currentFile.Replace($fileExtention, ".inutf8$fileExtention")
    $command = "$env:OptPath\Tools\TilUTF8\TilUTF8.exe $currentFile $utf8InputFile"
    Invoke-Expression -Command $command | Out-Null
    $contentOriginal = Get-Content -Path $utf8InputFile -Encoding utf8
    # $contentOriginal = $contentOriginal + "`r`n" + "      *ÆØÅæøå`r`n"
    $content = $contentOriginal -split "`r`n"  # Split content into individual lines

    foreach ($currentChange in $filePathsContent) {

        $splitList = $currentChange.Split(";")
        $change = [PSCustomObject]@{
            FilePath    = $splitList[0]
            Type        = $splitList[1]
            LineNumber  = [int]$splitList[2]
            ChangeFrom  = $splitList[3]
            ChangeTo    = $splitList[4]
            CurrentLine = $content[([int]$splitList[2] - 1)]
        }

        # if (
        #     $change.Type -eq "UNC" -or
        #     $change.Type -eq "DRIVE" -or
        #     $change.Type -eq "MISC" -or
        #     $change.Type -eq "RUN" -or
        #     $change.Type -eq "DB2CMD" -or
        #     $change.Type -eq "CALLRUN" -or
        #     $change.Type -eq "REXX" -or
        #     $change.Type -eq "SETDB2" -or
        #     $change.Type -eq "INVALID_SETDB2" -or
        #     $change.Type -eq "SQLENV" -or
        #     $change.Type -eq "SPECIAL" -or
        #     $change.Type -eq "DBALIAS" -or
        #     $change.Type -eq "CPX" -or
        #     $change.Type -eq "SPECIAL"
        # ) {
        #     # output as table
        #     Write-Host "Change:"
        #     $change | Format-Table
        # }

        $line = $content[$change.LineNumber - 1]

        if ($change.Type -eq "UNC" -or $change.Type -eq "DRIVE") {
            $line = $line.Replace($change.ChangeFrom, $change.ChangeTo)
            if ($content[$change.LineNumber - 1] -eq $line) {
                $line = $line.Replace($change.ChangeFrom.TrimEnd("\"), $change.ChangeTo.TrimEnd("\"))
                $change.ChangeFrom = $change.ChangeTo.TrimEnd("\")
            }
            else {
                $change.ChangeFrom = $change.ChangeTo
            }
            if ($line.ToUpper().Contains(".INT")) {
                $line = $line.Replace($change.ChangeFrom, ($VCPath + "\int\"))
            }
            elseif ($line.ToUpper().Contains(".BND")) {
                $line = $line.Replace($change.ChangeFrom, ($VCPath + "\bnd\"))
            }
            elseif ($line.ToUpper().Contains(".CBL")) {
                $line = $line.Replace($change.ChangeFrom, ($VCPath + "\src\cbl\"))
            }
        }
        elseif ($change.Type -eq "MISC") {
            $temp = $VCPath.Replace($vcDrive, "") + "\int"
            $line = $line.Replace(("\" + $change.ChangeFrom), $temp)
            if ($content[$change.LineNumber - 1] -eq $line) {
                $line = $line.Replace($change.ChangeFrom, $temp.TrimStart("\"))
            }
        }
        elseif ($change.Type -eq "RUN" -or $change.Type -eq "CALLRUN") {
            if ($change.ChangeFrom.EndsWith("\")) {
                $change.ChangeFrom = $change.ChangeFrom.Replace("\", " ")
            }
            $addString = $null
            if ($currentFile.ToUpper().EndsWith(".BAT")) {
                $addString = $vcDrive + "`r`n" + "CD " + $VCPath + "\int" + "`r`n" + $line.TrimEnd()
            }
            if ($addString -ne $null) {
                $line = $line.Replace($line, $addString)
            }
        }
        elseif ($change.Type -eq "DB2CMD") {
            if ($change.ChangeFrom.EndsWith("\")) {
                $change.ChangeFrom = $change.ChangeFrom.Replace("\", " ")
            }
            $addString = $null
            if ($currentFile.ToUpper().EndsWith(".BAT") -and ($line.ToUpper().Contains("RUN") -or $line.ToUpper().Contains("RUNW"))) {
                $addString = $vcDrive + "`r`n" + "CD " + $VCPath + "\int" + "`r`n" + $line.TrimEnd()
            }
            elseif ($currentFile.ToUpper().EndsWith(".BAT") -and $line.ToUpper().Contains("REXX")) {
                $addString = $vcDrive + "`r`n" + "CD " + $VCPath + "\src\rex" + "`r`n" + $line.TrimEnd()
            }

            if ($addString -ne $null) {
                $line = $line.Replace($line, $addString)
            }
        }

        elseif ($change.Type -eq "REXX" -and -not $line.ToUpper().Contains("DB2CMD")) {
            if ($change.ChangeFrom.EndsWith("\")) {
                $change.ChangeFrom = $change.ChangeFrom.Replace("\", " ")
            }
            $addString = $null
            if ($currentFile.ToUpper().EndsWith(".BAT")) {
                if ($line.ToUpper().Contains(".INT")) {
                    $addString = $vcDrive + "`r`n" + "CD " + $VCPath + "\int" + "`r`n" + $line.TrimEnd()
                }
                elseif ($line.ToUpper().Contains(".BND") -or $line.ToUpper().Contains("DIRBIND")) {
                    $addString = $vcDrive + "`r`n" + "CD " + $VCPath + "\bnd" + "`r`n" + $line.TrimEnd()
                }
                else {
                    $addString = $vcDrive + "`r`n" + "CD " + $VCPath + "\src\rex" + "`r`n" + $line.TrimEnd()
                }
            }
            else {
                $x = 1
            }
            if ($addString -ne $null) {
                $line = $line.Replace($line, $addString)
            }
        }
        elseif ($change.Type -eq "SETDB2") {
            $line = $line.Replace($change.ChangeFrom, $change.ChangeTo)
        }
        elseif ($change.Type -eq "INVALID_SETDB2") {
            $replacement = 'DB2DEV'
            $line = $line -replace $dbaliasPattern, $replacement
        }
        elseif ($change.Type -eq "SQLENV") {
            $line = ""
        }
        elseif ($change.Type -eq "SPECIAL") {
            $line = "      *" + $line.Substring(6).TrimEnd()
        }
        elseif ($change.Type -eq "DBALIAS") {
            $line = $line.Replace($change.ChangeFrom.Trim(), "DB2DEV")
        }
        elseif ($change.Type -eq "CPX") {
            # replace tab in line with 1 spaces
            $line = $line.Replace("`t", " ")
            $line = "       01 " + $line.Replace(" 01 ", "").TrimEnd()
            if ($line.TrimEnd() -eq $change.CurrentLine.TrimEnd()) {
                $line = $change.CurrentLine
            }
        }

        # if (
        #     $change.Type -eq "UNC" -or
        #     $change.Type -eq "DRIVE" -or
        #     $change.Type -eq "MISC" -or
        #     $change.Type -eq "RUN" -or
        #     $change.Type -eq "DB2CMD" -or
        #     $change.Type -eq "CALLRUN" -or
        #     $change.Type -eq "REXX" -or
        #     $change.Type -eq "SETDB2" -or
        #     $change.Type -eq "INVALID_SETDB2" -or
        #     $change.Type -eq "SQLENV" -or
        #     $change.Type -eq "DBALIAS" -or
        #     $change.Type -eq "CPX" -or
        #     $change.Type -eq "SPECIAL"
        # ) {
        #     Write-Host -ForegroundColor Green "Results"
        #     Write-Host -ForegroundColor Green "------------------------------------------------------------------------------------------------------------------------"
        #     Write-Host -ForegroundColor Green "OldLine: "  $content[$change.LineNumber - 1]
        #     Write-Host -ForegroundColor Green "NewLine: "  $line
        #     $x = 1
        # }

        $content[$change.LineNumber - 1] = $line

    }
    $resultContent = $content -join "`r`n"

    foreach ($driveLetter in [regex]::Matches($resultContent, '[A-Za-z]:')) {
        $content = $resultContent.Replace($driveLetter.Value, $vcDrive)
    }

    if ($resultContent.GetHashCode() -ne $contentOriginal.GetHashCode()) {

        $utf8OutputFile = $currentFile.Replace($fileExtention, ".oututf8$fileExtention")
        Set-Content -Value $resultContent -Path $utf8OutputFile  -Encoding UTF-8

        $command = "$env:OptPath\Tools\UTF8Ansi\UTF8Ansi.exe $utf8OutputFile $currentFile"
        Invoke-Expression -Command $command  | Out-Null

    }
    else {
        LogMessage -message "No changes made to file: $currentFile"
    }
    Remove-Item -Path $utf8OutputFile -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $utf8InputFile  -Force -ErrorAction SilentlyContinue
    # $encoding = Get-FileEncoding -Path $currentFile
    # LogMessage "File: $currentFile has been converted to $encoding"
}

Set-Location -Path $StartPath
LogMessage -message "Auto-Replace completed."
FKASendSMSDirect -receiver "+4797188358" -message "Auto-Replace completed."

