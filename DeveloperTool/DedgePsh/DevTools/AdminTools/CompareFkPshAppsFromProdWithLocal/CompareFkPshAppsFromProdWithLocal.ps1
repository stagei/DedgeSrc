Import-Module GlobalFunctions -Force

#########################################################################################################################
# Helper Functions
#########################################################################################################################

function Remove-DuplicateNewlines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$content
    )
    # Normalize all line endings to Windows standard (CRLF, "`r`n")
    # Windows standard for newlines is CRLF (`r`n); normalize all variations to this format
    $newContent = $($($($($content.Replace("`r`n", "`n").Replace("`n`r", "`n").Replace("`n", "`r`n")).Split("`n") | ForEach-Object { $_.TrimEnd() }) -join "`r`n") + "`r`n")
    while ($newContent.Contains("`r`n`r`n`r`n")) {
        $newContent = $newContent.Replace("`r`n`r`n`r`n", "`r`n`r`n")
    }
    return $newContent
}

function Repair-PowerShellCasing {
    param([string]$Content)
    
    # PowerShell approved verbs (common ones)
    $verbs = @('Get', 'Set', 'New', 'Remove', 'Add', 'Clear', 'Close', 'Copy', 'Enter', 'Exit', 
               'Find', 'Format', 'Hide', 'Join', 'Lock', 'Move', 'Open', 'Optimize', 'Pop', 
               'Push', 'Redo', 'Rename', 'Reset', 'Resize', 'Search', 'Select', 'Show', 'Skip',
               'Split', 'Step', 'Switch', 'Undo', 'Unlock', 'Watch', 'Backup', 'Checkpoint',
               'Compare', 'Compress', 'Convert', 'ConvertFrom', 'ConvertTo', 'Dismount', 'Edit',
               'Expand', 'Export', 'Group', 'Import', 'Initialize', 'Limit', 'Merge', 'Mount',
               'Out', 'Publish', 'Restore', 'Save', 'Sync', 'Unpublish', 'Update', 'Approve',
               'Assert', 'Complete', 'Confirm', 'Deny', 'Disable', 'Enable', 'Install', 'Invoke',
               'Register', 'Request', 'Restart', 'Resume', 'Start', 'Stop', 'Submit', 'Suspend',
               'Uninstall', 'Unregister', 'Wait', 'Debug', 'Measure', 'Ping', 'Repair', 'Resolve',
               'Test', 'Trace', 'Connect', 'Disconnect', 'Read', 'Receive', 'Send', 'Write',
               'Block', 'Grant', 'Protect', 'Revoke', 'Unblock', 'Unprotect', 'Use')
    
    # Common PowerShell keywords
    $keywords = @('foreach', 'if', 'else', 'elseif', 'switch', 'while', 'do', 'until', 'for',
                  'break', 'continue', 'return', 'param', 'begin', 'process', 'end', 'try',
                  'catch', 'finally', 'throw', 'function', 'filter', 'class', 'enum')
    
    # Fix verbs in cmdlet names (e.g., get-content -> Get-Content)
    foreach ($verb in $verbs) {
        $Content = $Content -replace "(?i)\b$verb-", "$verb-"
    }
    
    # Fix keywords (should be lowercase)
    foreach ($keyword in $keywords) {
        $Content = $Content -replace "(?i)\b$keyword\b", $keyword.ToLower()
    }
    
    # Fix boolean and null values
    $Content = $Content -replace '\$true\b', '$true'
    $Content = $Content -replace '\$false\b', '$false'
    $Content = $Content -replace '\$null\b', '$null'
    
    # Fix common cmdlet patterns
    $Content = $Content -replace '(?i)\bWrite-Host\b', 'Write-Host'
    $Content = $Content -replace '(?i)\bWrite-Output\b', 'Write-Output'
    $Content = $Content -replace '(?i)\bWrite-Verbose\b', 'Write-Verbose'
    $Content = $Content -replace '(?i)\bWrite-Warning\b', 'Write-Warning'
    $Content = $Content -replace '(?i)\bWrite-Error\b', 'Write-Error'
    $Content = $Content -replace '(?i)\bWrite-Debug\b', 'Write-Debug'
    
    return $Content
}

function Format-PowerShellFile {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File
    )
    
    try {
        # Only format .ps1 files
        if ($File.Extension -ne ".ps1") {
            return $false
        }
        
        # Read file content
        $content = Get-Content -Path $File.FullName -Raw
        $originalContent = $content
        
        # Check if PSScriptAnalyzer is available for full formatting
        $formatterAvailable = $null -ne (Get-Command Invoke-Formatter -ErrorAction SilentlyContinue)
        
        if ($formatterAvailable) {
            # Apply full formatting using PSScriptAnalyzer
            $content = Invoke-Formatter -ScriptDefinition $content
        }
        
        # Always apply casing corrections
        $content = Repair-PowerShellCasing -Content $content
        
        # Apply newline cleanup
        $content = Remove-DuplicateNewlines -content $content
        
        # Save if content changed
        if ($content -ne $originalContent) {
            Set-Content -Path $File.FullName -Value $content -NoNewline
            return $true
        }
        
        return $false
    }
    catch {
        Write-LogMessage "Error formatting file $($File.FullName): $($_.Exception.Message)" -Level WARN
        return $false
    }
}
try {
    #########################################################################################################################
    # Prepare unsigned production files
    #########################################################################################################################
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    $appdataFolder = Get-ApplicationDataPath
    $ProductionFolder = "$env:OptPath\src\_FROMPRD\DedgePshApps"
    # Create unsigned versions of production files by removing signatures
    $unsignedProductionFolder = Join-Path $appdataFolder "DedgePshApps_Unsigned"

    Get-ChildItem -Path $unsignedProductionFolder -Recurse -File -ErrorAction SilentlyContinue | Remove-Item -Force

    New-Item -Path $unsignedProductionFolder -ItemType Directory -Force | Out-Null

    # Get all PowerShell and batch files from production
    $productionSignedFiles = Get-ChildItem -Path $ProductionFolder -Recurse -File -Include @("*.ps1", "*.bat")
    $totalProdFiles = $productionSignedFiles.Count
    $currentProdFile = 0
    foreach ($file in $productionSignedFiles) {
        $currentProdFile++
        $progressPercent = if ($totalProdFiles -eq 0) { 100 } else { [math]::Round(($currentProdFile / $totalProdFiles) * 100, 1) }
        Write-Progress -Activity "Preparing unsigned production files" `
            -Status "Processing $currentProdFile of $totalProdFiles ($progressPercent%)" `
            -PercentComplete $progressPercent
        # Get relative path from production folder
        $relativePath = $file.FullName -replace [regex]::Escape($ProductionFolder), ""
        $relativePath = $relativePath.TrimStart('\')
        # Create destination path in appdata folder
        $destinationPath = Join-Path $unsignedProductionFolder $relativePath
        $destinationDir = Split-Path $destinationPath -Parent
        # Ensure destination directory exists
        if (-not (Test-Path $destinationDir)) {
            New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
        }
        # Read file content
        $content = Get-Content -Path $file.FullName -Raw
        # If content contains signature, remove it
        if ($content -match "# SIG # Begin signature block") {
            $content = ($content -split "# SIG # Begin signature block")[0]
        }
        # Check if content is empty
        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-LogMessage "File $($file.FullName) is empty" -Level WARN
        }
        else {
            # Remove trailing whitespace and newlines
            $content = Remove-DuplicateNewlines -content $content
        }
        # Save unsigned content to destination
        try {
            Set-Content -Path $destinationPath -Value $content -NoNewline
        }
        catch {
            Write-LogMessage "Error saving unsigned content to $($destinationPath): $($_.Exception.Message)" -Level ERROR
            Write-LogMessage "Content: $content" -Level ERROR
        }
    }
    Write-Progress -Activity "Preparing unsigned production files" -Completed -Status "Done"
    Write-LogMessage "Unsigned production files saved to: $($unsignedProductionFolder)" -Level INFO

    #########################################################################################################################
    # Format all production files
    #########################################################################################################################
    Write-LogMessage "Formatting production PowerShell files" -Level INFO
    $ProductionFiles = Get-ChildItem -Path $unsignedProductionFolder -Recurse -File -Exclude @("*.version", "*.unsigned") -Include @("*.ps1", "*.bat")
    $totalFormatProd = $ProductionFiles.Count
    $currentFormatProd = 0
    $formattedCount = 0

    foreach ($file in $ProductionFiles) {
        $currentFormatProd++
        $progressPercent = if ($totalFormatProd -eq 0) { 100 } else { [math]::Round(($currentFormatProd / $totalFormatProd) * 100, 1) }
        Write-Progress -Activity "Formatting production files" `
            -Status "Processing $currentFormatProd of $totalFormatProd ($progressPercent%)" `
            -PercentComplete $progressPercent
        
        if (Format-PowerShellFile -File $file) {
            $formattedCount++
        }
    }
    Write-Progress -Activity "Formatting production files" -Completed -Status "Done"
    Write-LogMessage "Formatted $formattedCount of $totalFormatProd production files" -Level INFO

    #########################################################################################################################
    # Get DedgePsh files for comparison
    #########################################################################################################################
    $DedgePshPath = Join-Path $env:OptPath "src\DedgePsh"
    # Get DedgePsh files with filters:
    # - Skip paths containing "_old"
    # - Skip paths containing "Forsprang" EXCEPT "Forsprang\_PRD" or "Forsprang_PRD"
    $allDedgePshFiles = Get-ChildItem -Path $DedgePshPath -Recurse -File -Exclude @("*.version", "*.unsigned") -Include @("*.ps1", "*.psm1", "*.bat")
    $DedgePshFiles = $allDedgePshFiles | Where-Object {
        $path = $_.FullName
        # Skip if contains _old
        if ($path -like "*_old*") { return $false }
        if ($path -like "*_FROMPRD*") { return $false }
        if ($path -like "*_deploy.ps1*") { return $false }
        if ($path -like "*.psm1*") { return $false }
        # Skip if contains Forsprang but not Forsprang\_PRD or Forsprang_PRD
        if ($path -match "Forsprang" -and $path -notmatch "Forsprang[_\\]PRD") { return $false }
        return $true
    }

    #########################################################################################################################
    # Matching files
    #########################################################################################################################
    $matchingFiles = @()
    $totalFiles = $ProductionFiles.Count
    $currentFile = 0
    # Matching logic:
    # - Match by filename AND parent folder name (parent folder = App name)
    # - Parent folder is the immediate directory containing the file
    foreach ($file in $ProductionFiles) {
        $currentFile++
        $progressPercent = if ($totalFiles -eq 0) { 100 } else { [math]::Round(($currentFile / $totalFiles) * 100, 1) }
        Write-Progress -Activity "Matching files" `
            -Status "Processing $currentFile of $totalFiles ($progressPercent%)" `
            -PercentComplete $progressPercent

        # Get the filename and parent folder (app name)
        $fileName = $file.Name
        $parentFolderName = $file.Directory.Name

        # Find matching file in DedgePsh with same filename AND parent folder name
        $DedgePshMatch = $DedgePshFiles | Where-Object {
            $_.Name.ToLower() -eq $fileName.ToLower() -and $_.Directory.Name.ToLower() -eq $parentFolderName.ToLower()
        }
        # Extra check
        if (-not $DedgePshMatch) {
            $objectFound = $false
            $testArray = @()
            $testArray += Join-Path $env:OptPath "src\DedgePsh" $parentFolderName $fileName
            $testArray += Join-Path $env:OptPath "src\DedgePsh\DevTools" $parentFolderName $fileName
            $testArray += Join-Path $env:OptPath "src\DedgePsh\DevTools\LogTools" $parentFolderName $fileName
            $testArray += Join-Path $env:OptPath "src\DedgePsh\DevTools\UtilityTools" $parentFolderName $fileName
            $testArray += Join-Path $env:OptPath "src\DedgePsh\DevTools\AdminTools" $parentFolderName $fileName
            $testArray += Join-Path $env:OptPath "src\DedgePsh\DevTools\DatabaseTools" $parentFolderName $fileName
            $testArray += Join-Path $env:OptPath "src\DedgePsh\DevTools\Documentation" $parentFolderName $fileName
            $testArray += Join-Path $env:OptPath "src\DedgePsh\DevTools\Experiments" $parentFolderName $fileName
            $testArray += Join-Path $env:OptPath "src\DedgePsh\DevTools\FixJobs" $parentFolderName $fileName
            $testArray += Join-Path $env:OptPath "src\DedgePsh\DevTools\GitTools" $parentFolderName $fileName
            $testArray += Join-Path $env:OptPath "src\DedgePsh\DevTools\InfrastructureTools" $parentFolderName $fileName
            $testArray += Join-Path $env:OptPath "src\DedgePsh\DevTools\LegacyCodeTools" $parentFolderName $fileName
            foreach ($testPath in $testArray) {
                Write-LogMessage "Looking for file in $($testPath)" -Level INFO
                if (Test-Path $testPath -PathType Leaf) {
                    Write-LogMessage "File found in $($testPath)" -Level INFO

                    $fileInfo = Get-Item -Path $testPath
                    $fileObject = [PSCustomObject]@{
                        ProductionFileName      = $file.FullName
                        DedgePshFileName       = $testPath
                        ProductionFileNameHash  = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
                        DedgePshFileNameHash   = (Get-FileHash -Path $fileInfo.FullName -Algorithm SHA256).Hash
                        ProductionLastWriteTime = $file.LastWriteTime
                        DedgePshLastWriteTime  = $fileInfo.LastWriteTime
                    }
                    Add-Member -InputObject $fileObject -MemberType NoteProperty -Name "HashMatch" -Value ($fileObject.ProductionFileNameHash -eq $fileObject.DedgePshFileNameHash)
                    $matchingFiles += $fileObject
                    $objectFound = $true
                    break
                }
            }
            if ($objectFound) {
                continue
            }
        }

        if ($DedgePshMatch) {
            if ($DedgePshMatch.FullName.ToLower().Contains("devtools")) {
                Write-LogMessage "Skipping DevTools file: $($DedgePshMatch.FullName)" -Level WARN
                continue
            }
            $fileObject = [PSCustomObject]@{
                ProductionFileName      = $file.FullName
                DedgePshFileName       = $DedgePshMatch.FullName
                ProductionFileNameHash  = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
                DedgePshFileNameHash   = (Get-FileHash -Path $DedgePshMatch.FullName -Algorithm SHA256).Hash
                ProductionLastWriteTime = $file.LastWriteTime
                DedgePshLastWriteTime  = $DedgePshMatch.LastWriteTime
            }
            Add-Member -InputObject $fileObject -MemberType NoteProperty -Name "HashMatch" -Value ($fileObject.ProductionFileNameHash -eq $fileObject.DedgePshFileNameHash)
            $matchingFiles += $fileObject
        }
        else {
            Write-LogMessage "No matching file found in DedgePsh: $($file.FullName)" -Level WARN
        }
    }
    Write-Progress -Activity "Matching files" -Completed -Status "Done"

    #########################################################################################################################
    # Format matched DedgePsh files before comparison
    #########################################################################################################################
    Write-LogMessage "Formatting matched DedgePsh files before comparison" -Level INFO
    $uniqueDedgePshFiles = $matchingFiles | Select-Object -ExpandProperty DedgePshFileName -Unique
    $totalFormatMatched = $uniqueDedgePshFiles.Count
    $currentFormatMatched = 0
    $formattedMatchedCount = 0

    foreach ($filePath in $uniqueDedgePshFiles) {
        $currentFormatMatched++
        $progressPercent = if ($totalFormatMatched -eq 0) { 100 } else { [math]::Round(($currentFormatMatched / $totalFormatMatched) * 100, 1) }
        Write-Progress -Activity "Formatting matched DedgePsh files" `
            -Status "Processing $currentFormatMatched of $totalFormatMatched ($progressPercent%)" `
            -PercentComplete $progressPercent
        
        $fileInfo = Get-Item $filePath
        if (Format-PowerShellFile -File $fileInfo) {
            $formattedMatchedCount++
        }
    }
    Write-Progress -Activity "Formatting matched DedgePsh files" -Completed -Status "Done"
    Write-LogMessage "Formatted $formattedMatchedCount of $totalFormatMatched matched DedgePsh files" -Level INFO

    #########################################################################################################################
    # Re-calculate hashes after formatting
    #########################################################################################################################
    Write-LogMessage "Recalculating hashes after formatting" -Level INFO
    foreach ($fileObject in $matchingFiles) {
        $fileObject.ProductionFileNameHash = (Get-FileHash -Path $fileObject.ProductionFileName -Algorithm SHA256).Hash
        $fileObject.DedgePshFileNameHash = (Get-FileHash -Path $fileObject.DedgePshFileName -Algorithm SHA256).Hash
        $fileObject.HashMatch = ($fileObject.ProductionFileNameHash -eq $fileObject.DedgePshFileNameHash)
    }

    $differentFiles = $matchingFiles | Where-Object { -not $_.HashMatch }
    Write-LogMessage "All Different files:" -Level INFO
    $differentFiles | Format-Table -Property ProductionFileName, DedgePshFileName, HashMatch, ProductionLastWriteTime, DedgePshLastWriteTime
    # Open each file and compare the content and add bool to differentFiles object
    Write-LogMessage "Comparing content of different files: $($differentFiles.Count)" -Level INFO
    foreach ($file in $differentFiles) {
        $productionContent = Get-Content -Path $file.ProductionFileName -Raw
        $DedgePshContent = Get-Content -Path $file.DedgePshFileName -Raw
        if ($productionContent -ne $DedgePshContent) {
            Add-Member -InputObject $file -MemberType NoteProperty -Name "ContentMatch" -Value $false
        }
        else {
            Add-Member -InputObject $file -MemberType NoteProperty -Name "ContentMatch" -Value $true
        }
    }
    $differentFiles = $differentFiles | Where-Object { -not $_.ContentMatch }
    $counter = 0
    $totalDifferentFiles = $differentFiles.Count
foreach ($file in $differentFiles) {
        $counter++
        $progressPercent = if ($totalDifferentFiles -eq 0) { 100 } else { [math]::Round(($counter / $totalDifferentFiles) * 100, 1) }
        Write-Progress -Activity "Comparing content of different files" `
            -Status "Processing $counter of $totalDifferentFiles ($progressPercent%)" `
            -PercentComplete $progressPercent
        Write-LogMessage "File $($file.ProductionFileName) is different from $($file.DedgePshFileName)" -Level WARN

        if (1 -eq 2) {
            # OPEN IN EDITOR
            $codeCmd = Get-CommandPathWithFallback -Name "code"
            if ($codeCmd) {
                $diffArgs = @("--diff", $file.ProductionFileName, $file.DedgePshFileName)
                Start-Process -FilePath $codeCmd -ArgumentList $diffArgs -WindowStyle Minimized -Wait
            }
            else {
                Write-LogMessage "Code not found" -Level ERROR
            }
        }
        else {
            Copy-Item -Path $file.ProductionFileName -Destination $file.DedgePshFileName -Force
        }
        Write-Progress -Activity "Comparing content of different files" -Completed -Status "Done"
        # Table
        $matchingFiles | Format-Table -Property ProductionFileName, LocalDedgePshAppsFileName, HashMatch
        Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
    }
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}

