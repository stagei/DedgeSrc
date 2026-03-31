function LogMessage {
    param(
        $message
    )
    $scriptName = $MyInvocation.ScriptName.Split("\")[$MyInvocation.ScriptName.Split("\").Length - 1].Replace(".ps1", "").Replace(".PS1", "")

    $dtLog = get-date -Format("yyyyMMdd").ToString()
    $logfile = ".\CBLCompileDB2DEV.log"
    # $logfile = "C:\TEMPFK\CBLCompileDB2DEV.log"

    $dt = get-date -Format("yyyy-MM-dd HH:mm:ss,ffff").ToString()

    $logmsg = $dt + ": " + $scriptName.Trim() + " :  " + $message

    Write-Host $logmsg
    Add-Content -Path $logfile -Value $logmsg
}
$cobolExe = "C:\Program Files (x86)\Micro Focus\Visual COBOL\bin\cobol.exe"

$lstFolder = "c:\fkavd\Dedge2\lst"
$intFolder = "c:\fkavd\Dedge2\int"
$cblFolder = "c:\fkavd\Dedge2\src\cbl"
# create folders if they don't exist
if (!(Test-Path -Path $lstFolder)) {
    New-Item -Path $lstFolder -ItemType Directory
}
if (!(Test-Path -Path $intFolder)) {
    New-Item -Path $intFolder -ItemType Directory
}
if (!(Test-Path -Path $cblFolder)) {
    New-Item -Path $cblFolder -ItemType Directory
}

# $files = Get-ChildItem -Path $cblFolder -Filter bkfinfa.cbl
$files = Get-ChildItem -Path $cblFolder -Filter GMAFELL.cbl
Push-Location
Set-Location -Path $intFolder
try {
    foreach ($file in $files) {

        $command = $cobolExe
        $allFiles = $intFolder + "\" + $file.BaseName + ".*"
        $intFile = $intFolder + "\" + $file.BaseName + ".int"
        $lstFile = $lstFolder + "\" + $file.BaseName + ".lst"

        # # check if int file exists
        # if (Test-Path -Path $lstFile -PathType Leaf) {
        #     Continue
        # }
        # if (Test-Path -Path $intFile -PathType Leaf) {
        #     Continue
        # }

        Remove-Item -Path $allFiles -Force
        $fileNameOnly = [System.IO.Path]::GetFileName($file)

        if ($fileNameOnly -match "(\d{8})|(\d{6})" -and $fileNameOnly.Length -gt 6) {
            continue
        }
        if ($fileNameOnly.Contains(" ")) {
            continue
        }

        LogMessage -message "--> Compiling $file"

        $args = $file.FullName + ", " + $intFile + ", " + $lstFile + ", nul INT() anim cobidy""$intFolder\"" sourcetabstop""4"" sourceformat""Variable"" noquery warnings""1"" max-error""100"""

        LogMessage -message ("--> Compile Command: " + $command + " " + $args)

        Start-Process -FilePath $command -ArgumentList $args -Wait -WindowStyle Hidden
        $output = $null
        $lstContent = Get-Content -Path $lstFile
        $output = $lstContent | Select-String -Pattern "^\* Last message on page:"
        if ($output -ne $null) {
            LogMessage -message ("-------------------------------------- START " + $file.BaseName.lst + "--------------------------------------")
            $lstContent | Select-Object -Skip ($output.LineNumber - 4) | ForEach-Object { LogMessage -message $_ }
            LogMessage -message ("--------------------------------------- END " + $file.BaseName.lst + "---------------------------------------")
            LogMessage -message ("**> Compilation failed: $file")
            LogMessage -message ("**> List file:" + $lstFile)
        }
        else {
            LogMessage -message "==> Compilation successful: $file"
            Remove-Item -Path $lstFile -Force
        }
        Start-Sleep -Milliseconds 500
    }
}
finally {
    LogMessage -message "--> Copying files to int folder and lst folder"

    # $lstFolderCommon = "K:\fkavd\Dedge2\lst"
    # $intFolderCommon = "K:\fkavd\Dedge2\int"

    # Copy-Item -Path ($lstFolder + "\*.lst")  -Destination $lstFolderCommon -Force
    # Copy-Item -Path ($intFolder + "\*.*")  -Destination $intFolderCommon -Force
    # Pop-Location
    LogMessage -message "--> Done"
}

