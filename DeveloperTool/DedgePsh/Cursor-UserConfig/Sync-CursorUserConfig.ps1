[CmdletBinding()]
param(
    [switch]$WhatIf
)

Import-Module GlobalFunctions -Force

$scriptRoot = $PSScriptRoot
$cursorHome = Join-Path $env:USERPROFILE ".cursor"

$syncMap = @(
    @{ Source = Join-Path $cursorHome "rules";    Dest = Join-Path $scriptRoot "rules";    Filter = "*.mdc" }
    @{ Source = Join-Path $cursorHome "commands";  Dest = Join-Path $scriptRoot "commands";  Filter = "*.md"  }
)

$skillsSource = Join-Path $cursorHome "skills"
$skillsDest   = Join-Path $scriptRoot "skills"

Write-LogMessage "Syncing Cursor user config from '$($cursorHome)' to '$($scriptRoot)'" -Level INFO

$totalCopied  = 0
$totalRemoved = 0

foreach ($map in $syncMap) {
    $srcDir  = $map.Source
    $destDir = $map.Dest
    $filter  = $map.Filter
    $category = Split-Path $srcDir -Leaf

    if (-not (Test-Path $srcDir)) {
        Write-LogMessage "Source folder not found: $($srcDir) — skipping $($category)" -Level WARN
        continue
    }

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $sourceFiles = Get-ChildItem -Path $srcDir -Filter $filter -File
    $destFiles   = Get-ChildItem -Path $destDir -Filter $filter -File

    foreach ($sf in $sourceFiles) {
        $target = Join-Path $destDir $sf.Name
        $needsCopy = $true

        if (Test-Path $target) {
            $srcHash  = (Get-FileHash $sf.FullName -Algorithm SHA256).Hash
            $destHash = (Get-FileHash $target -Algorithm SHA256).Hash
            if ($srcHash -eq $destHash) {
                $needsCopy = $false
            }
        }

        if ($needsCopy) {
            if ($WhatIf) {
                Write-LogMessage "WhatIf: Would copy $($category)/$($sf.Name)" -Level INFO
            }
            else {
                Copy-Item -Path $sf.FullName -Destination $target -Force
                Write-LogMessage "Copied $($category)/$($sf.Name)" -Level INFO
            }
            $totalCopied++
        }
    }

    $sourceNames = $sourceFiles | ForEach-Object { $_.Name }
    foreach ($df in $destFiles) {
        if ($df.Name -notin $sourceNames) {
            if ($WhatIf) {
                Write-LogMessage "WhatIf: Would remove stale $($category)/$($df.Name)" -Level INFO
            }
            else {
                Remove-Item $df.FullName -Force
                Write-LogMessage "Removed stale $($category)/$($df.Name)" -Level WARN
            }
            $totalRemoved++
        }
    }
}

if (Test-Path $skillsSource) {
    $skillFolders = Get-ChildItem -Path $skillsSource -Directory

    foreach ($sf in $skillFolders) {
        $destSkillDir = Join-Path $skillsDest $sf.Name
        if (-not (Test-Path $destSkillDir)) {
            New-Item -ItemType Directory -Path $destSkillDir -Force | Out-Null
        }

        $skillFiles = Get-ChildItem -Path $sf.FullName -File -Recurse
        foreach ($file in $skillFiles) {
            $relativePath = $file.FullName.Substring($sf.FullName.Length).TrimStart('\', '/')
            $targetPath   = Join-Path $destSkillDir $relativePath
            $targetDir    = Split-Path $targetPath -Parent

            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            $needsCopy = $true
            if (Test-Path $targetPath) {
                $srcHash  = (Get-FileHash $file.FullName -Algorithm SHA256).Hash
                $destHash = (Get-FileHash $targetPath -Algorithm SHA256).Hash
                if ($srcHash -eq $destHash) {
                    $needsCopy = $false
                }
            }

            if ($needsCopy) {
                if ($WhatIf) {
                    Write-LogMessage "WhatIf: Would copy skills/$($sf.Name)/$($relativePath)" -Level INFO
                }
                else {
                    Copy-Item -Path $file.FullName -Destination $targetPath -Force
                    Write-LogMessage "Copied skills/$($sf.Name)/$($relativePath)" -Level INFO
                }
                $totalCopied++
            }
        }
    }

    $destSkillFolders = Get-ChildItem -Path $skillsDest -Directory -ErrorAction SilentlyContinue
    $sourceSkillNames = $skillFolders | ForEach-Object { $_.Name }
    foreach ($ds in $destSkillFolders) {
        if ($ds.Name -notin $sourceSkillNames) {
            if ($WhatIf) {
                Write-LogMessage "WhatIf: Would remove stale skill folder skills/$($ds.Name)" -Level INFO
            }
            else {
                Remove-Item $ds.FullName -Recurse -Force
                Write-LogMessage "Removed stale skill folder skills/$($ds.Name)" -Level WARN
            }
            $totalRemoved++
        }
    }
}

Write-LogMessage "Sync complete. Copied: $($totalCopied), Removed: $($totalRemoved)" -Level INFO
