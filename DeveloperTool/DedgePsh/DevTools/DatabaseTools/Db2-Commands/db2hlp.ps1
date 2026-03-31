param (
    [Parameter(Mandatory = $false)]
    [string]$Filter = ""
)
if (-not [string]::IsNullOrEmpty($Filter) -and -not $Filter.Contains("*") -and -not $Filter.Contains(".bat") -and -not $Filter.Contains(".")) {
    $Filter += ".bat"
}
else {
    $Filter += "*.bat"
}

$batFiles = Get-ChildItem -Path $PSScriptRoot -Filter $Filter -File
$helpArray = @()

foreach ($batFile in $batFiles) {
    # $content = Get-Content -Path $batFile.FullName -Raw
    $synopsis = @()

    # Extract synopsis from REM comments at the top of the file
    $lines = Get-Content -Path $batFile.FullName
    foreach ($line in $lines) {
        if ($line -match "^REM Synopsis Start$") {
            $synopsisStarted = $true
            continue
        }
        elseif ($line -match "^REM Synopsis End$") {
            break
        }
        elseif ($synopsisStarted -and $line -match "^REM\s+(.+)$") {
            $synopsis += @($matches[1].Trim())
        }
        elseif ($line.Trim() -ne "" -and -not ($line -match "^@echo off$|^@REM|^@::")) {
            break
        }
    }
    if ($synopsis.Count -gt 0) {
        $helpObj = [PSCustomObject]@{
            ScriptName   = $batFile.Name
            Synopsis     = $synopsis
            SynopsisText = ($synopsis -join "`n")
        }

        $helpArray += $helpObj
    }
}

$helpArray | Format-Table -AutoSize -Wrap -Property ScriptName, SynopsisText

