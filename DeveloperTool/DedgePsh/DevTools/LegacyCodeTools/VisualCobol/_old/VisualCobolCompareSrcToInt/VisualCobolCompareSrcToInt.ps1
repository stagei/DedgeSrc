# Import-Module -Name FKASendSMSDirect -Force
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
function CheckCblArchiveFolder ($intFile, $localSrcFolder , $localTmpFolder) {
    try {

        $cblArchiveFolder = "\\DEDGE.fk.no\erputv\Utvikling\CBLARKIV" + "\" + $intFile + "\"
        $extractFolder = $localTmpFolder + "\" + $intFile
        # check if $cblArchiveFolder exists
        if (Test-Path -Path $cblArchiveFolder -PathType Container) {
            if (-not (Test-Path -Path $extractFolder -PathType Container)) {
                $latestZip = Get-ChildItem -Path $cblArchiveFolder -Filter "*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($latestZip) {
                    $zipFile = $cblArchiveFolder + $latestZip.Name
                    LogMessage -message ("Extracting: " + $zipFile + " to: " + $extractFolder)
                    New-Item -Path $extractFolder -ItemType Directory | Out-Null
                    Expand-Archive -Path $zipFile -DestinationPath $extractFolder -Force
                    Get-ChildItem -Path $extractFolder -Filter *.cbl | Copy-Item -Destination $localSrcFolder -Force
                }
            }
        }
    }
    catch {
        LogMessage -message ("CheckCblArchiveFolder failed with error: " + $_.Exception.Message)
    }
}

function GetSourceFiles ($localSrcFolder, $localTmpFolder, $intPath, $prodArray, $intArray, $prodSrcFolder, $intFiles) {
    xcopy /y /d /f \\DEDGE.fk.no\erputv\Utvikling\fkavd\NT\HISTORIKK\*.cbl $localSrcFolder | Out-Null

    xcopy /y /d /f \\DEDGE.fk.no\erputv\Utvikling\fkavd\utgatt\*.cbl $localSrcFolder #| Out-Null

    foreach ($file in $intFiles) {
        CheckCblArchiveFolder -intFile $file.BaseName.ToUpper() -localSrcFolder $localSrcFolder -localTmpFolder $localTmpFolder
    }

    $srcPath = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT"
    $fileList = Get-ChildItem -Path $srcPath -Filter *.cbl_del
    # Create folder $localSrcFolder + "\DISCARDED\" if it does not exist
    $cblDelFolder = $localSrcFolder + "\DISCARDED"
    if (-not (Test-Path -Path $cblDelFolder -PathType Container)) {
        New-Item -Path $cblDelFolder -ItemType Directory
    }
    foreach ($file in $fileList) {
        $srcFile = $file.FullName
        $destFile = $localSrcFolder + "\" + $file.Name.ToUpper().Replace("_DEL", "")
        $destFile2 = $localSrcFolder + "\DISCARDED\" + $file.Name.ToUpper().Replace("_DEL", "")
        if (-not (Test-Path -Path $destFile -PathType Leaf)) {
            Copy-Item -Path $srcFile -Destination $destFile -Force
            Copy-Item -Path $srcFile -Destination $destFile2 -Force
        }
    }

    $srcPath = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\utgatt"
    $fileList = Get-ChildItem -Path $srcPath -Filter *.cbl_del
    foreach ($file in $fileList) {
        $srcFile = $file.FullName
        $destFile = $localSrcFolder + "\" + $file.Name.ToUpper().Replace("_DEL", "")
        $destFile2 = $localSrcFolder + "\DISCARDED\" + $file.Name.ToUpper().Replace("_DEL", "")
        if (-not (Test-Path -Path $destFile -PathType Leaf)) {
            Copy-Item -Path $srcFile -Destination $destFile -Force
            Copy-Item -Path $srcFile -Destination $destFile2 -Force
        }
    }

    $srcPath = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT"
    # copy all *.cbl files to local folder
    xcopy /y $srcPath\*.cbl $localSrcFolder | Out-Null
    xcopy /y \\DEDGE.fk.no\erpprog\COBNT\*.bat $localSrcFolder | Out-Null
    xcopy /y \\DEDGE.fk.no\erpprog\COBNT\*.rex $localSrcFolder | Out-Null

    # \\p-no1fkmprd-app.DEDGE.fk.no\opt\DedgePshApps\
    # \\p-no1fkmprd-app\opt\DedgePshApps\
    $sourceLocations = "\\p-no1fkmprd-app.DEDGE.fk.no\opt\DedgePshApps\", "\\p-no1fkmprd-app\opt\DedgePshApps\"

    foreach ($location in $sourceLocations) {
        Get-ChildItem -Path $location -File -Filter "*.ps*" -Recurse | Copy-Item -Destination $prodSrcFolder -Force
        Get-ChildItem -Path $location -File -Filter "*.bat" -Recurse | Copy-Item -Destination $prodSrcFolder -Force
    }

    Get-ChildItem -Path "\\DEDGE.fk.no\erpprog\COBNT\ExportScheduledTasks\" -File -Filter "*.*" -Recurse | Copy-Item -Destination $prodSrcFolder -Force

    $skiplist = @("HIST.BAT", "RYDD2.BAT", "RYDD2.BAT", "MAYLISS.CBL", "VEGARD.CBL", "TFN1.BAT", "2810.BAT", "1310.BAT", "FIX.BAT", "BPROT2.BAT")
    foreach ($skipfile in $skiplist) {
        Remove-Item -Path $localSrcFolder\$skipfile -Force -ErrorAction SilentlyContinue
    }

    Get-ChildItem -Path $localSrcFolder -Filter "*-GML*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*-NY*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*_GML*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*_NY*" | Move-Item -Destination $cblDelFolder -Force
    # find files with space in filename and remove them
    Get-ChildItem -Path $localSrcFolder -Filter "* *" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2001*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2002*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2003*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2004*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2005*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2006*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2007*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2008*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2009*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2010*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2011*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2012*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2013*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2014*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2015*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2016*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2017*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2018*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2019*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2020*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2021*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2022*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2023*" | Move-Item -Destination $cblDelFolder -Force
    Get-ChildItem -Path $localSrcFolder -Filter "*2024*" | Move-Item -Destination $cblDelFolder -Force

    # Remove files in $localSrcFolder that contain either 6 or 8 digits in the filename
    $cleanFiles = Get-ChildItem -Path $localSrcFolder -Filter *.*
    foreach ($file in $cleanFiles) {
        if ($file.BaseName -match "\d{6,8}") {
            Move-Item -Path $file.FullName -Destination $cblDelFolder -Force
        }
        if ($file.BaseName -match "^\d{6,8}$") {
            Move-Item -Path $file.FullName -Destination $cblDelFolder -Force
        }
        if ($file.BaseName.Contains(" ")) {
            Move-Item -Path $file.FullName -Destination $cblDelFolder -Force
        }
    }

    foreach ($src in $prodArray) {
        $src = $src.ToUpper()
        if (-not $src.Contains(".CBL")) {
            continue
        }
        $srcFile = $localSrcFolder + "\" + $src
        $destFile = $prodSrcFolder + "\" + $src
        if (Test-Path -Path $srcFile -PathType Leaf) {
            if (-not (Test-Path -Path $destFile -PathType Leaf)) {
                Copy-Item -Path $srcFile -Destination $destFile -Force
            }
        }
        else {
            LogMessage -message ("Source file: " + $src + " not found in local folder")
        }
    }

}

function CheckCblFileUsage ($srcFile, $prodSrcFolder, $usedByArray) {
    $pos = $srcFile.IndexOf(".")
    $srcFileBase = $srcFile.Substring(0, $pos)
    $srcFileExt = $srcFile.Substring($pos + 1).ToUpper()
    $srcFileBaseUpper = $srcFileBase.ToUpper()
    $srcFileUpper = $srcFile.ToUpper()

    if ($usedByArray.Count -gt 1) {
        $x = 1
    }

    # if ($srcFileBaseUpper.Length -le 3) {
    #     return $usedByArray
    # }

    $includeFilter = $null
    $pattern = $null
    $result = @()
    if ($srcFileExt -eq "BAT") {
        $includeFilter = "*.ps1", "*.bat", "*.rex", "*.xml"
        $pattern = $srcFileUpper

    }
    elseif ($srcFileExt -eq "PS1") {
        $includeFilter = "*.ps1", "*.bat", "*.rex", "*.xml"
        $pattern = $srcFileUpper
    }
    elseif ($srcFileExt -eq "PSM1") {
        $includeFilter = "*.ps1", "*.psm1"
        $pattern = $srcFileUpper
    }
    elseif ($srcFileExt -eq "XML") {
        $result = @()
    }
    elseif ($srcFileExt -eq "REX") {
        $includeFilter = "*.ps1", "*.bat", "*.rex", "*.xml"
        $pattern = $srcFileBaseUpper, $srcFileUpper
    }
    elseif ($srcFileExt -eq "CBL") {
        $includeFilter = "*.ps1", "*.bat", "*.rex", "*.cbl"
        $pattern = $srcFileBaseUpper
    }

    if ($includeFilter.Length -gt 0 -and $pattern.Length -gt 0) {
        $result = Get-ChildItem -Path $prodSrcFolder -Include $includeFilter -Recurse | Select-String $pattern | Select-Object Path -Unique
    }

    if ($result.Count -gt 0) {
        foreach ($file in $result) {
            $fileInfo = Get-Item -Path $file.Path
            if ($fileInfo.Name.ToUpper() -eq $srcFileUpper) {
                continue
            }
            if ($usedByArray -notcontains $fileInfo.Name.ToUpper()) {
                $usedByArray += $fileInfo.Name.ToUpper()
                $usedByArray = CheckCblFileUsage -srcFile $fileInfo.Name.ToUpper() -prodSrcFolder $prodSrcFolder -usedByArray $usedByArray
            }
        }
    }
    return $usedByArray
}

#########################################################################################################################################
#########################################################################################################################################
# Main script
#########################################################################################################################################
#########################################################################################################################################

try {
    $quickDebugRun = $true
    $global:logfile = $env:OptPath + "\src\DedgePsh\DevTools\VisualCobolCompareSrcToInt\VisualCobolCompareSrcToInt.log"
    Remove-Item -Path $global:logfile -Force -ErrorAction SilentlyContinue

    LogMessage -message ("VisualCobolCompareSrcToInt started")
    # Get current script path and set location to it
    $StartPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
    Set-Location -Path $StartPath

    $srcPath = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\NT"
    $srcUtgattPath = "\\DEDGE.fk.no\erputv\Utvikling\fkavd\utgatt"
    $intPath = "\\DEDGE.fk.no\erpprog\COBNT"

    $localSrcFolder = $env:OptPath + "\work\VisualCobolCompareSrcToInt\src"
    if (-not (Test-Path -Path $localSrcFolder -PathType Container)) {
        New-Item -Path $localSrcFolder -ItemType Directory
    }

    $localTmpFolder = $env:OptPath + "\work\VisualCobolCompareSrcToInt\tmp"
    if (-not (Test-Path -Path $localTmpFolder -PathType Container)) {
        New-Item -Path $localTmpFolder -ItemType Directory
    }

    $prodSrcFolder = $env:OptPath + "\work\VisualCobolCompareSrcToInt\prd"
    if (-not (Test-Path -Path $prodSrcFolder -PathType Container)) {
        New-Item -Path $prodSrcFolder -ItemType Directory
    }
    $cblDelFolder = $localSrcFolder + "\DISCARDED"
    if (-not (Test-Path -Path $cblDelFolder -PathType Container)) {
        New-Item -Path $cblDelFolder -ItemType Directory
    }

    $intArray = @()
    $intFiles = Get-ChildItem -Path $intPath -Filter *.int
    foreach ($file in $intFiles) {
        $intArray += $file.BaseName.ToUpper()
    }

    $prodArray = @()
    $prodFiles = Get-ChildItem -Path "\\DEDGE.fk.no\erpprog\COBNT" -Filter *.bat
    $prodFiles += Get-ChildItem -Path "\\DEDGE.fk.no\erpprog\COBNT" -Filter *.cmd
    $prodFiles += Get-ChildItem -Path "\\DEDGE.fk.no\erpprog\COBNT" -Filter *.rex
    $prodFiles += Get-ChildItem -Path "\\DEDGE.fk.no\erpprog\COBNT" -Filter *.int
    foreach ($file in $prodFiles) {
        if ($file.Extension.ToUpper() -eq ".INT") {
            $prodArray += $file.BaseName.ToUpper() + ".CBL"
        }
        else {
            $prodArray += $file.Name.ToUpper()
        }
    }

    # check if there are files in the localSrcFolder
    # $allFiles = Get-ChildItem -Path $localSrcFolder -Filter *.*
    # if (-not $allFiles) {
    if (-not $quickDebugRun) {
        GetSourceFiles -localSrcFolder $localSrcFolder -localTmpFolder $localTmpFolder -intPath $intPath -prodArray $prodArray -intArray $intArray -prodSrcFolder $prodSrcFolder -intFiles $intFiles
    }
    # }

    $srcArray = @()
    $cblFiles = Get-ChildItem -Path $prodSrcFolder -Filter *.cbl
    foreach ($file in $cblFiles) {
        $srcArray += $file.BaseName.ToUpper()
    }

    $objarrayMissing = @()
    $objarrayAll = @()
    foreach ($intFile in $intArray) {
        try {
            $tempSrcFile = $intFile + ".CBL"
            $usedByArray = @()
            if ($srcArray -notcontains $intFile) {
                if (-not $quickDebugRun) {
                    $usedByArray = CheckCblFileUsage -srcFile $tempSrcFile -prodSrcFolder $prodSrcFolder -usedByArray $usedByArray
                }
            }
            else {
                $usedByArray += 'Not checked since file exists in source folder'
            }

            if ($usedByArray) {
                $listUsedBy = $usedByArray -join ","
                $proqramInUse = "Y"
                # LogMessage -message ("Missing source file: " + $intFile + ". Used by: " + $listUsedBy)
            }
            else {
                $listUsedBy = ""
                $proqramInUse = "N"
                # LogMessage -message ("Missing source file: " + $intFile + ". Not used by any program")
            }

            # check if file exists in $prodSrcFolder
            $existSrcFile = "Y"
            $srcFilePath = $prodSrcFolder + "\" + $intFile + ".CBL"
            if (-not (Test-Path -Path $srcFilePath -PathType Leaf)) {
                $existSrcFile = "N"
            }
            $comment = ""
            if ($existSrcFile -eq "N") {
                # Check if any version exists in $cblDelFolder
                $count = (Get-ChildItem -Path $cblDelFolder -Filter "$intFile*.*").Count
                if ($count.Count -gt 0) {
                    $existSrcFileCblDel = "Y"
                    $comment = "Some version or versions of File exists in DISCARDED folder"
                }
            }
            else {
                $existSrcFileCblDel = "N/A"
            }

            $missingSrc = [PSCustomObject]@{
                PackageSchemaName   = "DBM"
                PackageName         = $intFile.Trim().ToUpper()
                IntFile             = $intFile + ".INT"
                SrcFile             = $srcFilePath
                ExistSrcFile        = $existSrcFile
                $existSrcFileCblDel = $existSrcFileCblDel
                ProgramInUse        = $proqramInUse
                Comment             = $comment
                User                = ""
                UsedBy              = $listUsedBy
            }
            $objarrayAll += $missingSrc
            if ($existSrcFile -eq "N") {
                $objarrayMissing += $missingSrc
            }
        }
        catch {
            LogMessage -message ("Error: " + $_.Exception.Message + " on line: " + $_.InvocationInfo.ScriptLineNumber.ToString() + " in script: " + $_.InvocationInfo.ScriptName + " at position: " + $_.InvocationInfo.OffsetInLine)
        }

    }

    $sqlInsertFile = $StartPath + "\InsertSourceReport.sql"
    if (Test-Path -Path $sqlInsertFile -PathType Leaf) {
        Remove-Item -Path $sqlInsertFile -Force -ErrorAction SilentlyContinue
    }

    foreach ($obj in $objarrayAll) {
        $sqlInsert = @"
    INSERT INTO DBM.DB_STAT_SOURCE_REPORT (
        PACKAGE_SCHEMA_NAME,
        PACKAGE_NAME,
        INT_FILE,
        SRC_FILE,
        EXIST_SRC_FILE,
        EXIST_SRC_FILE_IN_DISCARDED_FOLDER,
        PROGRAM_IN_USE,
        COMMENT,
        USER,
        USED_BY
    )
    VALUES (
        '$($obj.PackageSchemaName)',
        '$($obj.PackageName)',
        '$($obj.IntFile)',
        '$($obj.SrcFile)',
        '$($obj.ExistSrcFile)',
        '$($obj.ExistSrcFileInDiscardedFolder)',
        '$($obj.ProgramInUse)',
        '$($obj.Comment)',
        '$($obj.User)',
        '$($obj.UsedBy)'
    );
"@

        Add-Content -Path $sqlInsertFile -Value $sqlInsert
    }

    # Write $objarray as text file
    $csvFile = $StartPath + "\MissingSourceReport.csv"
    if (Test-Path -Path $csvFile -PathType Leaf) {
        Remove-Item -Path $csvFile -Force -ErrorAction SilentlyContinue
    }
    # export to csv
    $objarrayMissing | Export-Csv -Path $csvFile -NoTypeInformation -Delimiter ';' -Encoding UTF8

    # Write $objarray as text file
    $csvFile = $StartPath + "\AllSourceReport.csv"
    if (Test-Path -Path $csvFile -PathType Leaf) {
        Remove-Item -Path $csvFile -Force -ErrorAction SilentlyContinue
    }
    # export to csv
    $objarrayAll | Export-Csv -Path $csvFile -NoTypeInformation -Delimiter ';' -Encoding UTF8

    $dbName = "BASISPRO"
    # $userID = "db2nt"
    # $PW = "ntdb2"
    $server = "p-no1fkmprd-db.DEDGE.fk.no"
    $port = 3700

    # # Source File with connection variables set
    # $Path = $PSScriptRoot

    # #Define connection string for the database
    # $cn = new-object system.data.OleDb.OleDbConnection("Provider=IBMDADB2;DSN=$dbName;User Id=;Password=;");
    # #Define data set for first query
    # $ds = new-object "System.Data.DataSet" "ds"
    # #Define query to run
    # $q = "select * from DBM.BANKTERM_INFO"
    # # Define data object given the specific query and connection string
    # $da = new-object "System.Data.OleDb.OleDbDataAdapter" ($q, $cn)
    # # Fill the data set - essentially run the query.
    # $da.Fill($ds) | Out-Null
    # # Print the result
    # foreach ($Row in $ds.Tables[0].Rows) {
    #     $columnIndex = 0
    #     # Create a PsObject for each row
    #     $obj = New-Object PSObject
    #     foreach ($column in $ds.Tables[0].Columns) {
    #         $obj | Add-Member -MemberType NoteProperty -Name $column.ColumnName -Value $Row.ItemArray[$columnIndex]
    #         $columnIndex++
    #     }
    #     # Output the PsObject
    #     $obj
    # }
    # # Close the Connection
    # $cn.close()

    # Source File with connection variables set
    $Path = $PSScriptRoot

    # Set your database name or other variable data

    # # Define connection string for the database
    # $cn = new-object system.data.OleDb.OleDbConnection("Provider=IBMDADB2;DSN=$dbName;User Id=;Password=;")
    # $cn.Open()

    # try {
    #     # Begin transaction
    #     $transaction = $cn.BeginTransaction()

    #     # Define query to run
    #     $q = "INSERT INTO DBM.DB_STAT_SOURCE_REPORT (PACKAGE_SCHEMA_NAME, PACKAGE_NAME, INT_FILE, SRC_FILE, EXIST_SRC_FILE, EXIST_SRC_FILE_IN_DISCARDED_FOLDER, PROGRAM_IN_USE, COMMENT, USER, USED_BY) VALUES ('DBM', 'GHSGHS', 'GHSGHS.INT', 'c:\\opt\\work\\VisualCobolCompareSrcToInt\\prd\\GHSGHS.CBL', 'Y', '', 'Y', '', '', 'Not checked since file exists in source folder');"

    #     # Create and execute the command
    #     $cmd = new-object system.data.OleDb.OleDbCommand
    #     # check result of the command
    #     $cmd.Connection = $cn

    #     $cmd.CommandText = $q

    #     $cmd.Transaction = $transaction
    #     $cmd.ExecuteNonQuery() | Out-Null

    #     # Check the result of the command
    #     # $cmd.CommandText = "SELECT * FROM DBM.DB_STAT_SOURCE_REPORT"

    #     # $cmd.Transaction = $transaction
    #     # $rdr = $cmd.ExecuteReader()
    #     # while ($rdr.Read()) {
    #     #     $rdr.GetString(0)
    #     # }
    #     # $rdr.Close()

    #     $transaction.Commit()
    # }
    # catch {
    #     # Rollback transaction if an exception occurs
    #     if ($transaction) {
    #         $transaction.Rollback()
    #     }
    #     Write-Error "An error occurred: $_"
    # }
    # finally {
    #     # Close the Connection
    #     $cn.Close()
    # }

# Load the ADO.NET assembly for ODBC
Add-Type -AssemblyName System.Data

# Create a new ODBC connection object
$connectionString = "DSN=$dbName;Uid=;Pwd=;"
$connection = New-Object System.Data.Odbc.OdbcConnection($connectionString)

# try {
#     # Open the connection
#     $connection.Open()

#     # SQL command to insert a row
#     $sql = "INSERT INTO DBM.DB_STAT_SOURCE_REPORT (PACKAGE_SCHEMA_NAME, PACKAGE_NAME, INT_FILE, SRC_FILE, EXIST_SRC_FILE, EXIST_SRC_FILE_IN_DISCARDED_FOLDER, PROGRAM_IN_USE, COMMENT, USER, USED_BY) VALUES ('DBM', 'GHSGHS', 'GHSGHS.INT', 'c:\\opt\\work\\VisualCobolCompareSrcToInt\\prd\\GHSGHS.CBL', 'Y', '', 'Y', '', '', 'Not checked since file exists in source folder')"

#     # Create an ODBC command
#     $command = $connection.CreateCommand()
#     $command.CommandText = $sql

#     # Add parameters to avoid SQL injection
#     # $param1 = $command.CreateParameter()
#     # $param1.Value = 'Value1'
#     # $command.Parameters.Add($param1)

#     # $param2 = $command.CreateParameter()
#     # $param2.Value = 'Value2'
#     # $command.Parameters.Add($param2)

#     # Execute the query
#     $rowsAffected = $command.ExecuteNonQuery()
#     Write-Output "Rows inserted: $rowsAffected"
# }
# catch {
#     Write-Error "Error occurred: $_"
# }
# finally {
#     # Always close the connection
#     $connection.Close()
# }

# # Load the ADO.NET assembly for ODBC
# Add-Type -AssemblyName System.Data

# # Create a new ODBC connection object
# $connectionString = "DSN=$dbName;Uid=;Pwd=;"
# $connection = New-Object System.Data.Odbc.OdbcConnection($connectionString)

# try {
#     # Open the connection
#     $connection.Open()

#     # Begin a transaction
#     $transaction = $connection.BeginTransaction()

#     # SQL command to insert a row

#     # Create an ODBC command and associate it with the transaction
#     $command = $connection.CreateCommand()
#     $command.Transaction = $transaction
#     $command.CommandText = $sql

#     # # Add parameters to avoid SQL injection
#     # $param1 = $command.CreateParameter()
#     # $param1.Value = 'Value1'
#     # $command.Parameters.Add($param1)

#     # $param2 = $command.CreateParameter()
#     # $param2.Value = 'Value2'
#     # $command.Parameters.Add($param2)

#     # Execute the query
#     $command.ExecuteNonQuery()

#     # Commit the transaction
#     $transaction.Commit()
#     Write-Output "Transaction committed and rows inserted successfully."
# }
# catch {
#     Write-Error "Error occurred: $_"
#     # Rollback the transaction if there is an error
#     if ($transaction -ne $null) {
#         $transaction.Rollback()
#         Write-Output "Transaction rolled back due to an error."
#     }
# }
# finally {
#     # Always close the connection
#     $connection.Close()
# }

# Load the ADO.NET assembly for ODBC
Add-Type -AssemblyName "System.Data, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089"

# Define connection parameters
$dbName = "BASISPRO"  # Specify your database name
$uid = ""  # Specify your username
$pwd = ""  # Specify your password

# Create a new ODBC connection object
$connectionString = "DSN=$dbName;Uid=$uid;Pwd=$pwd;"
$connection = New-Object System.Data.Odbc.OdbcConnection($connectionString)

try {
    # Open the connection
    $connection.Open()

    # Begin a transaction
    $transaction = $connection.BeginTransaction()

    # Define the SQL command to insert static values
    $sql = "INSERT INTO DBM.DB_STAT_SOURCE_REPORT (PACKAGE_SCHEMA_NAME, PACKAGE_NAME, INT_FILE, SRC_FILE, EXIST_SRC_FILE, EXIST_SRC_FILE_IN_DISCARDED_FOLDER, PROGRAM_IN_USE, COMMENT, USER, USED_BY) VALUES ('DBM', 'GHSGHS', 'GHSGHS.INT', 'c:\\opt\\work\\VisualCobolCompareSrcToInt\\prd\\GHSGHS.CBL', 'Y', '', 'Y', '', '', 'Not checked since file exists in source folder')"

    # Create an ODBC command and associate it with the transaction
    $command = $connection.CreateCommand()
    $command.Transaction = $transaction
    $command.CommandText = $sql

    # Execute the query
    $command.ExecuteNonQuery()

    # Commit the transaction
    $transaction.Commit()
    Write-Output "Transaction committed and rows inserted successfully."
}
catch {
    Write-Error "Error occurred: $_"
    # Rollback the transaction if there is an error
    if ($transaction -ne $null) {
        $transaction.Rollback()
        Write-Output "Transaction rolled back due to an error."
    }
}
finally {
    # Always close the connection
    $connection.Close()
}

# Dispose of the ODBC connection object
if ($connection -ne $null) {
    $connection.Dispose()
}

    # save arrays to file

    # # Connect to DB2 database
    # $username = $env:USERNAME
    # $connectionString = "DSN=BASISPRO;UID=$username;PWD=!;"
    # #$connectionString = "DSN=BASISPRO;"

    # Add-Type -AssemblyName "IBM.Data.DB2"
    # $connection = [IBM.Data.DB2.DB2Connection]::new($connectionString)
    # try {
    #     $connection.Open()

    #     # Delete existing rows in the table
    #     $deleteCommand = $connection.CreateCommand()
    #     $deleteCommand.CommandText = "DELETE FROM DBM.DB_STAT_SOURCE_REPORT"
    #     $deleteCommand.ExecuteNonQuery()

    #     # Execute the .sql script
    #     $sqlScript = Get-Content -Path $sqlInsertFile -Raw
    #     $sqlCommands = $sqlScript -split ";"

    #     foreach ($command in $sqlCommands) {
    #         if ($command.Trim()) {
    #             $sqlCommand = $connection.CreateCommand()
    #             $sqlCommand.CommandText = $command
    #             $sqlCommand.ExecuteNonQuery()
    #         }
    #     }
    # }
    # catch {
    #     LogMessage -message ("Database operation failed with error: " + $_.Exception.Message)
    #     if ($_.Exception.InnerException) {
    #         LogMessage -message ("Inner exception message: " + $_.Exception.InnerException.Message)
    #     }
    # }
    # finally {
    #     # Close the connection
    #     $connection.Close()
    # }

    Set-Location -Path $StartPath

}
catch {
}

