#Requires -Version 7.0
<#
.SYNOPSIS
    Applies automated code transformations for Visual COBOL migration.
.DESCRIPTION
    Reads the FileChanges.txt and Files.txt produced by Search-VcCodeIssues.ps1 and
    applies automated transformations to migrate portability issues:
    - UNC path -> local VCPATH path conversions
    - Drive letter substitutions
    - DB2 alias name replacements (FKAVDNT -> DB2DEV)
    - COBOL code pattern rewrites for Visual COBOL compatibility
    - SQLENV COPY removal
    - Tab-to-space conversion in CPX files

    Replaces: OldScripts\VisualCobolCodeMigration\VisualCobolCodeReplace.ps1
    Changes from old version:
    - Uses GlobalFunctions Write-LogMessage and Send-Sms
    - Fixed $$ bug (now uses $PSScriptRoot)
    - Uses .NET Encoding instead of external TilUTF8/UTF8Ansi executables
    - Removed global variable pollution
    - Removed dead commented-out code blocks
    - Cleaner change application logic

    Source: Rocket Visual COBOL Documentation Version 11 - Compiling COBOL Applications
.EXAMPLE
    .\Invoke-VcCodeReplace.ps1 -SearchResultsFolder 'C:\opt\work\SearchResults'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SearchResultsFolder,

    [string]$VcPath = $(if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }),

    [switch]$SendNotification
)

$ErrorActionPreference = 'Stop'
Import-Module GlobalFunctions -Force

$filesListPath = Join-Path $SearchResultsFolder 'Files.txt'
$changesListPath = Join-Path $SearchResultsFolder 'FileChanges.txt'

if (-not (Test-Path $filesListPath) -or -not (Test-Path $changesListPath)) {
    Write-LogMessage "Required files not found in $($SearchResultsFolder). Run Search-VcCodeIssues.ps1 first." -Level ERROR
    exit 1
}

$filesContent = Get-Content -Path $filesListPath | Where-Object { $_.Trim().Length -gt 0 }
$allChanges = Get-Content -Path $changesListPath | Where-Object { $_.Trim().Length -gt 0 }

$dbaliasPattern = 'BASISPRO|BASISHST|BASISRAP|BASISTST|VISMABUS|VISMAHST|FKKONTO|FKAVDNT|BASISMIG|BASISSIT|VISMAMIG'
$vcDrive = $VcPath.Substring(0, 2)

$counter = 0
$changedCount = 0
$ansi1252 = [System.Text.Encoding]::GetEncoding(1252)

foreach ($currentFile in $filesContent) {
    $counter++
    $currentFile = $currentFile.Trim()
    $fileName = [System.IO.Path]::GetFileName($currentFile)
    $fileExt = [System.IO.Path]::GetExtension($currentFile)

    $fileChanges = $allChanges | Where-Object { $_ -like "*$($currentFile)*" }
    if (-not $fileChanges) { continue }

    Write-LogMessage "File #$($counter) - $($fileName) - $($fileChanges.Count) change(s)" -Level INFO

    try {
        $contentBytes = [System.IO.File]::ReadAllBytes($currentFile)
        $contentOriginal = $ansi1252.GetString($contentBytes)
        $lines = $contentOriginal -split "`r`n"
    } catch {
        Write-LogMessage "Could not read: $($currentFile) - $($_.Exception.Message)" -Level WARN
        continue
    }

    foreach ($changeLine in $fileChanges) {
        $parts = $changeLine.Split(';')
        if ($parts.Count -lt 5) { continue }

        $change = @{
            FilePath   = $parts[0]
            Type       = $parts[1]
            LineNumber = [int]$parts[2]
            ChangeFrom = $parts[3]
            ChangeTo   = $parts[4]
        }

        $lineIdx = $change.LineNumber - 1
        if ($lineIdx -lt 0 -or $lineIdx -ge $lines.Count) { continue }
        $line = $lines[$lineIdx]

        switch ($change.Type) {
            { $_ -in 'UNC', 'DRIVE' } {
                $line = $line.Replace($change.ChangeFrom, $change.ChangeTo)
                if ($lines[$lineIdx] -eq $line) {
                    $line = $line.Replace($change.ChangeFrom.TrimEnd('\'), $change.ChangeTo.TrimEnd('\'))
                }
                $target = $change.ChangeTo
                if ($line.ToUpper() -match '\.INT') { $line = $line.Replace($target, "$($VcPath)\int\") }
                elseif ($line.ToUpper() -match '\.BND') { $line = $line.Replace($target, "$($VcPath)\bnd\") }
                elseif ($line.ToUpper() -match '\.CBL') { $line = $line.Replace($target, "$($VcPath)\src\cbl\") }
            }

            'MISC' {
                $replacement = $VcPath.Replace($vcDrive, '') + '\int'
                $line = $line.Replace("\$($change.ChangeFrom)", $replacement)
                if ($lines[$lineIdx] -eq $line) {
                    $line = $line.Replace($change.ChangeFrom, $replacement.TrimStart('\'))
                }
            }

            { $_ -in 'RUN', 'CALLRUN' } {
                if ($currentFile.ToUpper().EndsWith('.BAT')) {
                    $line = "$($vcDrive)`r`nCD $($VcPath)\int`r`n$($line.TrimEnd())"
                }
            }

            'DB2CMD' {
                if ($currentFile.ToUpper().EndsWith('.BAT')) {
                    if ($line.ToUpper() -match 'RUNW?\s') {
                        $line = "$($vcDrive)`r`nCD $($VcPath)\int`r`n$($line.TrimEnd())"
                    } elseif ($line.ToUpper() -match 'REXX') {
                        $line = "$($vcDrive)`r`nCD $($VcPath)\src\rex`r`n$($line.TrimEnd())"
                    }
                }
            }

            'REXX' {
                if (-not ($line.ToUpper() -match 'DB2CMD') -and $currentFile.ToUpper().EndsWith('.BAT')) {
                    $cdTarget = if ($line.ToUpper() -match '\.INT') { "$($VcPath)\int" }
                                elseif ($line.ToUpper() -match '\.BND|DIRBIND') { "$($VcPath)\bnd" }
                                else { "$($VcPath)\src\rex" }
                    $line = "$($vcDrive)`r`nCD $($cdTarget)`r`n$($line.TrimEnd())"
                }
            }

            'SETDB2' {
                $line = $line.Replace($change.ChangeFrom, $change.ChangeTo)
            }

            'INVALID_SETDB2' {
                $line = $line -replace $dbaliasPattern, 'DB2DEV'
            }

            'SQLENV' {
                $line = ''
            }

            'SPECIAL' {
                $line = '      *' + $line.Substring(6).TrimEnd()
            }

            'DBALIAS' {
                $line = $line.Replace($change.ChangeFrom.Trim(), 'DB2DEV')
            }

            'CPX' {
                $line = $line.Replace("`t", ' ')
                $line = '       01 ' + $line.Replace(' 01 ', '').TrimEnd()
            }
        }

        $lines[$lineIdx] = $line
    }

    $resultContent = $lines -join "`r`n"
    if ($resultContent.GetHashCode() -ne $contentOriginal.GetHashCode()) {
        $resultBytes = $ansi1252.GetBytes($resultContent)
        [System.IO.File]::WriteAllBytes($currentFile, $resultBytes)
        $changedCount++
    } else {
        Write-LogMessage "No changes made to file: $($currentFile)" -Level DEBUG
    }
}

Write-LogMessage "Code replacement complete: $($counter) files processed, $($changedCount) files modified" -Level INFO

if ($SendNotification) {
    $smsNumber = switch ($env:USERNAME) {
        'FKGEISTA' { '+4797188358' }
        'FKSVEERI' { '+4795762742' }
        'FKMISTA'  { '+4799348397' }
        'FKCELERI' { '+4745269945' }
        default    { '+4797188358' }
    }
    Send-Sms -Receiver $smsNumber -Message "Auto-Replace done. $($changedCount)/$($counter) files changed."
}
