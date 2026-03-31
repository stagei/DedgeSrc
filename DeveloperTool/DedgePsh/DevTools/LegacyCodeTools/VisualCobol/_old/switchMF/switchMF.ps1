#add parameter with valid values MF or VC
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("MF", "VC", "VCL", "VCX")]
    [string]$switch
)

function Set-MachineEnvironmentVariable ($variableName, $variableValue, $silent = $false) {
    if ($silent -eq $true) {
        if ($variableValue -eq "") {
            Write-Host "Removed Environment Variable $variableName"
        }
        else {
            Write-Host "Set Environment Variable $variableName"
        }
    }
    else {
        if ($variableValue -eq "") {
            Write-Host "Removed Environment Variable $variableName"
        }
        else {
            Write-Host "Set Environment Variable $variableName with value $variableValue"
        }

    }
    [System.Environment]::SetEnvironmentVariable($variableName, $variableValue, [System.EnvironmentVariableTarget]::Machine)
}
function Set-Path ($workPath, $removePattern, $addArray) {
    # Loop through the array and remove each folder from the path
    $splitPath = $workPath.Split(";") | Select-Object -Unique
    $newPath = ""

    $removePattern += "%PATH%"
    # Loop through the array and add each folder to the path

    foreach ($folder in $splitPath) {
        $match = $false
        foreach ($pattern in $removePattern) {
            $folderLower = $folder.ToLower()
            $patternLower = $pattern.ToLower()
            if ($folderLower.Contains($patternLower)) {
                Write-Host "Remove $folder from path using pattern $pattern"
                $match = $true
                break
            }
        }
        if (-not $match) {
            Write-Host "Added $folder to path"
            $newPath = $newPath + ";$folder"
        }
    }

    foreach ($folder in $addArray) {
        $newPath = $newPath + ";$folder"
        Write-Host "Added new  $folder to path"
    }
    Write-Host "-------------------------------------------------------------------------------------------------"

    # $newPath += ";C:\Program Files\PowerShell\7;%PATH%;C:\Program Files (x86)\Micro Focus\Visual COBOL\bin;C:\Program Files\Python311\Scripts\;C:\Program Files\Python311\;C:\Program Files\IBM\SQLLIB\BIN;C:\Program Files\IBM\SQLLIB\lib;C:\Users\fkgeista\AppData\Local\Programs\Python\Python311\Scripts\;C:\Users\fkgeista\AppData\Local\Programs\Python\Python311\;C:\Python311\Scripts\;C:\Python311\;C:\WINDOWS\system32;C:\WINDOWS;C:\WINDOWS\System32\Wbem;C:\WINDOWS\System32\WindowsPowerShell\v1.0\;C:\WINDOWS\System32\OpenSSH\;C:\Program Files (x86)\Micro Focus\Visual COBOL\lib;C:\Program Files (x86)\Micro Focus\Visual COBOL\bin64;C:\Program Files\dotnet\;C:\Program Files (x86)\Microsoft SQL Server\160\DTS\Binn\;C:\Program Files\Azure Data Studio\bin;C:\Program Files\Microsoft SQL Server\150\Tools\Binn\;C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\;C:\Program Files\nodejs\;C:\Program Files (x86)\Micro Focus\Visual COBOL\bin;C:\Program Files\Python311\Scripts\;C:\Program Files\Python311\;C:\Program Files\IBM\SQLLIB\BIN;C:\Program Files\IBM\SQLLIB\lib;C:\Users\fkgeista\AppData\Lmermaridocal\Programs\Python\Python311\Scripts\;C:\Users\fkgeista\AppData\Local\Programs\Python\Python311\;C:\Python311\Scripts\;C:\Python311\;C:\WINDOWS\system32;C:\WINDOWS;C:\WINDOWS\System32\Wbem;C:\WINDOWS\System32\WindowsPowerShell\v1.0\;C:\WINDOWS\System32\OpenSSH\;C:\Program Files (x86)\Micro Focus\Visual COBOL\lib;C:\Program Files (x86)\Micro Focus\Visual COBOL\bin64;C:\Program Files\dotnet\;C:\Program Files (x86)\Microsoft SQL Server\160\DTS\Binn\;C:\Program Files\Azure Data Studio\bin;C:\Program Files\Microsoft SQL Server\150\Tools\Binn\;C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\;C:\Program Files\nodejs\"
    $newPath = $newPath.TrimStart(";")
    $newPath = $newPath.Replace(";;", ";")
    $pathArray = $newPath.Split(";")
    $pathArray = $pathArray | Select-Object -Unique
    $newPath = $pathArray -join ";"

    # Set the new path1
    Set-MachineEnvironmentVariable -variableName "PATH" -variableValue $newPath -silent $true
    Write-Host "-------------------------------------------------------------------------------------------------"

    foreach ($folder in $pathArray) {
        Write-Host "Path: $folder"
    }
}

$workPath = $env:Path
$gitstring = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\mingw64\bin\"

if ($switch -eq "MF") {
    # Set-MachineEnvironmentVariable -variableName "COBCPY" -variableValue "K:\fkavd\Sys\cpy;K:\fkavd\NT;"
    # Set-MachineEnvironmentVariable -variableName "COBDIR" -variableValue "c:\Program Files (x86)\Micro Focus\Net Express 5.1\base\Bin;C:\Program Files (x86)\Micro Focus\Net Express 5.1\DialogSystem\Bin;"
    # Set-MachineEnvironmentVariable -variableName "COBPATH" -variableValue ""
    # Set-MachineEnvironmentVariable -variableName "INCLUDE" -variableValue ""
    # Set-MachineEnvironmentVariable -variableName "LIB" -variableValue ""
    # Set-MachineEnvironmentVariable -variableName "COBDATA" -variableValue ""
    # Set-MachineEnvironmentVariable -variableName "COBMODE" -variableValue ""

    $removePattern = @("$gitstring", "micro focus", "IBM\SQLLIB")
    $addarray = @("c:\program files (x86)\micro focus\net express 5.1\base\bin", "c:\program files (x86)\micro focus\net express 5.1\dialogsystem\bin;", "C:\Program Files\IBM\SQLLIB\BIN", "$gitstring")

    Set-Path $workPath $removePattern $addarray
}
elseif ($switch -eq "VC") {
    $VCPATH = "C:\fkavd\Dedge2"

    if (-not (Test-Path $VCPATH -PathType Container )) {
        New-Item -ItemType Directory -Path $VCPATH
    }

    Set-MachineEnvironmentVariable -variableName "VCPATH" -variableValue "$VCPATH"
    Set-MachineEnvironmentVariable -variableName "COBCPY" -variableValue "$VCPATH\src\cbl\cpy;$VCPATH\src\cbl\cpy\sys\cpy;$VCPATH\src\cbl;"
    Set-MachineEnvironmentVariable -variableName "COBPATH" -variableValue "$VCPATH\int;$VCPATH\gs;$VCPATH\src\cbl;"
    Set-MachineEnvironmentVariable -variableName "COBDIR" -variableValue "C:\Program Files (x86)\Micro Focus\Visual COBOL;$VCPATH\int;$VCPATH\gs;$VCPATH\src\cbl;"
    Set-MachineEnvironmentVariable -variableName "MFVSSW" -variableValue "/c /f"
    Set-MachineEnvironmentVariable -variableName "COBMODE" -variableValue "32"
    Set-MachineEnvironmentVariable -variableName "LIB" -variableValue "C:\Program Files (x86)\Micro Focus\Visual COBOL\lib"

    $removePattern = @("micro focus", "SQLLIB")

    $removePattern = @("$gitstring", "c:\program files (x86)\micro focus", "IBM\SQLLIB", ("$VCPATH\cfg".Substring(3)))
    $addarray = @("C:\Program Files (x86)\Micro Focus\Visual COBOL\bin", "C:\Program Files (x86)\Micro Focus\Visual COBOL\lib", "C:\Program Files (x86)\IBM\SQLLIB\BI2N", "$VCPATH\cfg", "$gitstring")

    #     ath: C:\PROGRA~2\IBM\SQLLIB\BIN
    # Path: C:\PROGRA~2\IBM\SQLLIB\FUNCTION
    # Path: C:\PROGRA~2\IBM\SQLLIB\SAMPLES\REPL
    # Path: C:\PROGRA~2\IBM\SQLLIB\lib

    Set-Path $workPath $removePattern $addarray

}

