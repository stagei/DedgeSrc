
Import-Module -Name FKASendSMSDirect -Force
Import-Module -Name ConvertAnsi1252ToUtf8 -Force
Import-Module -Name ConvertUtf8ToAnsi1252 -Force
Import-Module -Name Logger -Force

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




# Define the folder path you want to check and create
$PSWorkPath = $env:PSWorkPath
$srcRootFolder = $PSWorkPath
$workFolder = "$PSWorkPath\VisualCobolCodeMigration"
$DedgeFolder = "$PSWorkPath\VisualCobolCodeMigration\Dedge"

$DedgeCblFolder = $DedgeFolder + "\cbl"
$outputFolder = "$PSWorkPath\VisualCobolCodeMigration\Content"

$filesContent = Get-Content -Path "$outputFolder\Files.txt"

foreach ($currentFile in $filesContent) {
    $currentFile = $currentFile.ToString().Trim()
    $content = ConvertFileToStringAnsi1252ToUtf8 -fileName $currentFile
    $content
    $filePathsContent =  $null
    $filePathsContent = Get-Content -Path "$outputFolder\FilePaths.txt" | Where-Object {$_ -like "*$currentFile*"}

    $content = $content.Replace('n:', 'k:')
    $content
    $content = $content.Replace('N:', 'K:')
    $content
    if ($content.Contains("FKAVD\NT")) {
        if ($content.ToUpper().Contains(".BND") -or $content.ToUpper().Contains("DIRBIND")) {
            $content = $content.Replace('FKAVD\NT', 'fkavd\Dedge2\bnd')
            $content
        }
        if ($content.ToUpper().Contains(".INT")) {
            $content = $content.Replace('FKAVD\NT', 'fkavd\Dedge2\int')
            $content
        }
        if ($content.ToUpper().Contains(".CBL")) {
            $content = $content.Replace('FKAVD\NT', 'fkavd\Dedge2\src\cbl')
            $content
        }
    }

    # if ($content.Contains("COBNT")) {
    #     if ($content.ToUpper().Contains(".BND") -or $content.ToUpper().Contains("DIRBIND")) {
    #         $content = $content.Replace('COBNT', 'fkavd\Dedge2\bnd')
    #         $content
    #     }
    #     if ($content.ToUpper().Contains(".INT")) {
    #         $content = $content.Replace('COBNT', 'fkavd\Dedge2\int')
    #         $content
    #     }
    #     if ($content.ToUpper().Contains(".CBL")) {
    #         $content = $content.Replace('COBNT', 'fkavd\Dedge2\src\cbl')
    #         $content
    #     }
    # }

    # if ($content.Contains("COBNT")) {
    #     if ($content.ToUpper().Contains(".BND") -or $content.ToUpper().Contains("DIRBIND")) {
    #         $content = $content.Replace('COBNT', 'fkavd\Dedge2\bnd')
    #         $content
    #     }
    #     if ($content.ToUpper().Contains(".INT")) {
    #         $content = $content.Replace('COBNT', 'fkavd\Dedge2\int')
    #         $content
    #     }
    #     if ($content.ToUpper().Contains(".CBL")) {
    #         $content = $content.Replace('COBNT', 'fkavd\Dedge2\src\cbl')
    #         $content
    #     }
    # }

    # if ($content.ToUpper().Contains("RUN ") -and $currentFile.ToUpper().Contains(".BAT")) {
    #     $content = $content.Replace('RUN ', 'RUN k:\fkavd\Dedge2\int\')
    #     $content
    # }

    # if ($content.ToUpper().Contains("RUNW ") -and $currentFile.ToUpper().Contains(".BAT")) {
    #     $content = $content.Replace('RUNW ', 'RUN k:\fkavd\Dedge2\int\')
    #     $content
    # }

    # if ($content.ToUpper().Contains("RUN.EXE ") -and $currentFile.ToUpper().Contains(".BAT")) {
    #     $content = $content.Replace('RUN.EXE ', 'RUN.EXE k:\fkavd\Dedge2\int\')
    #     $content
    # }

    # if ($content.ToUpper().Contains("RUNW.EXE ") -and $currentFile.ToUpper().Contains(".BAT")) {
    #     $content = $content.Replace('RUNW.EXE ', 'RUN.EXE k:\fkavd\Dedge2\int\')
    #     $content
    # }
    
    foreach ($currentChange in $filePathsContent) {
        $splitList = $currentChange.Split(";")
        $content = $content.Replace($splitList[1], $splitList[2])
        $content
    }

    # ConvertStringUtf8ToAnsi1252 -string $content | Set-Content -Path $currentFile -Encoding Default
    break
}


FKASendSMSDirect -receiver "+4797188358" -message "VisualCobolCodeMigration completed. Results are available in $outputFolder"
















