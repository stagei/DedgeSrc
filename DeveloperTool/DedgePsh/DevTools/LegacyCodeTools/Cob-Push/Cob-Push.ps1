# --------------------------------------------------------------------------------
# Cob-Push.ps1
# --------------------------------------------------------------------------------
[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $ProdFolderPath = "N:\COBNT",

    [Parameter()]
    [string]
    $bndFolderPath = "N:\COBNT\BND",

    [Parameter()]
    [int]
    $includeFilesChangedLastXHours = 300,

    [Parameter()]
    [string]
    $TemplateServerName = "p-no1avd-wrk",

    [Parameter()]
    [int]
    $digits = 3,

    [Parameter()]
    [int]
    $StartNumber = 001,

    [Parameter()]
    [int]
    $EndNumber = 100,

    [Parameter()]
    [string]
    $IsTestMode = "true"
)
$scriptBlockFunctionCode = @"
function Copy-FilesToServer {
    param(
        [string]`$ServerName,
        [string]`$ProdFolderPath,
        [string]`$BndFolderPath,
        [int]`$IncludeFilesChangedLastXHours
    )
    `$includeFilesExtensionCbl = '`"*.int`" `"*.gs`"'
    `$includeFilesExtensionBnd = '`"*.bnd`"'

    # Copy from prod folder
    `$serverSharePath = "\\" + `$ServerName + "\COBNT"
    if (-not (Test-Path `$serverSharePath)) {
        Write-Output "Server share path does not exist: `$serverSharePath"
        return
    }
    `$robocopyCommandCbl = "robocopy " + `$ProdFolderPath + " " + `$serverSharePath + " /E /XO /MAXAGE:" + `$IncludeFilesChangedLastXHours.ToString() + "H " + `$includeFilesExtensionCbl
    Write-Output `$robocopyCommandCbl

    # Copy from prodbnd folder to BND subfolder on server
    `$serverBndPath = `$serverSharePath + "\BND"
    `$robocopyCommandBnd = "robocopy " + `$BndFolderPath + " " + `$serverBndPath + " /E /XO /MAXAGE:" + `$IncludeFilesChangedLastXHours.ToString() + "H " + `$includeFilesExtensionBnd
    Write-Output `$robocopyCommandBnd
    # Start-Process -FilePath "cmd.exe" -ArgumentList "/c `$robocopyCommandCbl" -Wait
    # Start-Process -FilePath "cmd.exe" -ArgumentList "/c `$robocopyCommandBnd" -Wait
}
"@

function Copy-FilesToServerMultiThread {
    param(
        [string]$ScriptBlockFunctionCode,
        [string]$ProdFolderPath,
        [string]$BndFolderPath,
        [int]$IncludeFilesChangedLastXHours,
        [string]$TemplateServerName,
        [int]$Digits,
        [int]$StartNumber,
        [int]$EndNumber
    )

    # Create script block for parallel execution
    $scriptBlock = {
        param($ServerName, $ProdFolderPath, $BndFolderPath, $IncludeFilesChangedLastXHours, $ScriptBlockFunctionCode)

        # Import the function into the job context
        Invoke-Command -ScriptBlock ([ScriptBlock]::Create($ScriptBlockFunctionCode))

        $startTime = Get-Date
        $serverSharePath = "\\" + $ServerName + "\COBNT"
        try {
            Copy-FilesToServer -ServerName $ServerName -ProdFolderPath $ProdFolderPath -BndFolderPath $BndFolderPath -IncludeFilesChangedLastXHours $IncludeFilesChangedLastXHours
            $success = $true
        }
        catch {
            $success = $false
        }
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds

        return [PSCustomObject]@{
            ServerName      = $ServerName
            ServerSharePath = $serverSharePath
            Success         = $success
            DurationMs      = $duration
        }
    }

    # Start jobs for each server
    $jobs = foreach ($number in $StartNumber..$EndNumber) {
        $number = $number.ToString("D" + $Digits)
        $serverName = $TemplateServerName + $number
        Write-Output "Starting job for $serverName"

        Start-Job -ScriptBlock $scriptBlock -ArgumentList $serverName, $ProdFolderPath, $BndFolderPath, $IncludeFilesChangedLastXHours, $ScriptBlockFunctionCode
    }

    # Wait for all jobs and get results
    $results = $jobs | Wait-Job | Receive-Job

    # Display results table
    $results | Format-Table -Property ServerName, ServerSharePath, Success, @{
        Label      = "Duration";
        Expression = { "{0:N0}ms" -f $_.DurationMs }
    }

    # Cleanup jobs
    $jobs | Remove-Job
}

function Copy-FilesToServerLocalTest {
    param(
        [string]$ScriptBlockFunctionCode,
        [string]$ProdFolderPath,
        [string]$BndFolderPath,
        [int]$IncludeFilesChangedLastXHours,
        [string]$TemplateServerName,
        [int]$Digits,
        [int]$StartNumber,
        [int]$EndNumber
    )

    Invoke-Command -ScriptBlock ([ScriptBlock]::Create($ScriptBlockFunctionCode))
    foreach ($number in $StartNumber..$EndNumber) {
        $number = $number.ToString("D" + $Digits)
        $serverName = $TemplateServerName + $number
        Write-Output "Starting job for $serverName"
        Copy-FilesToServer -ServerName $serverName -ProdFolderPath $ProdFolderPath -BndFolderPath $BndFolderPath -IncludeFilesChangedLastXHours $IncludeFilesChangedLastXHours
    }
}

if ($IsTestMode) {
    Copy-FilesToServerLocalTest -ScriptBlockFunctionCode $scriptBlockFunctionCode -ProdFolderPath $ProdFolderPath -BndFolderPath $bndFolderPath -IncludeFilesChangedLastXHours $includeFilesChangedLastXHours -TemplateServerName $TemplateServerName -Digits $digits -StartNumber $StartNumber -EndNumber $EndNumber
} else {
    Copy-FilesToServerMultiThread -ScriptBlockFunctionCode $scriptBlockFunctionCode -ProdFolderPath $ProdFolderPath -BndFolderPath $bndFolderPath -IncludeFilesChangedLastXHours $includeFilesChangedLastXHours -TemplateServerName $TemplateServerName -Digits $digits -StartNumber $StartNumber -EndNumber $EndNumber
}

