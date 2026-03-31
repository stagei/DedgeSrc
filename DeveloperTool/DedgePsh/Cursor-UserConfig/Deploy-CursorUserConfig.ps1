[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("All", "Rules", "Commands", "Skills")]
    [string]$Scope = "All",

    [switch]$WhatIf,

    [switch]$Force
)

Import-Module GlobalFunctions -Force

$scriptRoot  = $PSScriptRoot
$cursorHome  = Join-Path $env:USERPROFILE ".cursor"

$categories = switch ($Scope) {
    "All"      { @("rules", "commands", "skills") }
    "Rules"    { @("rules") }
    "Commands" { @("commands") }
    "Skills"   { @("skills") }
}

$filterMap = @{
    "rules"    = "*.mdc"
    "commands" = "*.md"
}

$sourceRulesDir    = Join-Path $scriptRoot "rules"
$sourceCommandsDir = Join-Path $scriptRoot "commands"
$sourceSkillsDir   = Join-Path $scriptRoot "skills"

$ruleCount   = if (Test-Path $sourceRulesDir)    { (Get-ChildItem $sourceRulesDir -Filter "*.mdc" -File).Count }    else { 0 }
$cmdCount    = if (Test-Path $sourceCommandsDir)  { (Get-ChildItem $sourceCommandsDir -Filter "*.md" -File).Count } else { 0 }
$skillCount  = if (Test-Path $sourceSkillsDir)    { (Get-ChildItem $sourceSkillsDir -Directory).Count }             else { 0 }

Write-LogMessage "Cursor User Config Deployment" -Level INFO
Write-LogMessage "Source: $($scriptRoot)" -Level INFO
Write-LogMessage "Target: $($cursorHome)" -Level INFO
Write-LogMessage "Scope: $($Scope) | Available: $($ruleCount) rules, $($cmdCount) commands, $($skillCount) skills" -Level INFO

if (-not $Force -and -not $WhatIf) {
    Write-Host ""
    Write-Host "This will deploy Cursor user config to: $($cursorHome)" -ForegroundColor Yellow
    Write-Host "  Rules:    $($ruleCount) files -> $($cursorHome)\rules\" -ForegroundColor Cyan
    Write-Host "  Commands: $($cmdCount) files -> $($cursorHome)\commands\" -ForegroundColor Cyan
    Write-Host "  Skills:   $($skillCount) folders -> $($cursorHome)\skills\" -ForegroundColor Cyan
    Write-Host ""

    $existingRules    = if (Test-Path (Join-Path $cursorHome "rules"))    { (Get-ChildItem (Join-Path $cursorHome "rules") -Filter "*.mdc" -File -ErrorAction SilentlyContinue).Count } else { 0 }
    $existingCommands = if (Test-Path (Join-Path $cursorHome "commands")) { (Get-ChildItem (Join-Path $cursorHome "commands") -Filter "*.md" -File -ErrorAction SilentlyContinue).Count } else { 0 }
    $existingSkills   = if (Test-Path (Join-Path $cursorHome "skills"))   { (Get-ChildItem (Join-Path $cursorHome "skills") -Directory -ErrorAction SilentlyContinue).Count } else { 0 }

    if ($existingRules -gt 0 -or $existingCommands -gt 0 -or $existingSkills -gt 0) {
        Write-Host "WARNING: Existing user config detected ($($existingRules) rules, $($existingCommands) commands, $($existingSkills) skills)." -ForegroundColor Red
        Write-Host "Existing files with the same name will be OVERWRITTEN. Files not in source will be LEFT ALONE." -ForegroundColor Red
        Write-Host ""
    }

    $confirm = Read-Host "Continue? (Y/N)"
    if ($confirm -notin @("Y", "y", "Yes", "yes")) {
        Write-LogMessage "Deployment cancelled by user" -Level WARN
        return
    }
}

$totalCopied  = 0
$totalSkipped = 0

foreach ($category in $categories) {
    if ($category -eq "skills") { continue }

    $srcDir  = Join-Path $scriptRoot $category
    $destDir = Join-Path $cursorHome $category
    $filter  = $filterMap[$category]

    if (-not (Test-Path $srcDir)) {
        Write-LogMessage "No source folder for $($category) — skipping" -Level WARN
        continue
    }

    if (-not (Test-Path $destDir)) {
        if ($WhatIf) {
            Write-LogMessage "WhatIf: Would create $($destDir)" -Level INFO
        }
        else {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            Write-LogMessage "Created $($destDir)" -Level INFO
        }
    }

    $sourceFiles = Get-ChildItem -Path $srcDir -Filter $filter -File
    foreach ($sf in $sourceFiles) {
        $target = Join-Path $destDir $sf.Name
        $needsCopy = $true

        if (Test-Path $target) {
            $srcHash  = (Get-FileHash $sf.FullName -Algorithm SHA256).Hash
            $destHash = (Get-FileHash $target -Algorithm SHA256).Hash
            if ($srcHash -eq $destHash) {
                $needsCopy = $false
                $totalSkipped++
            }
        }

        if ($needsCopy) {
            if ($WhatIf) {
                Write-LogMessage "WhatIf: Would deploy $($category)/$($sf.Name)" -Level INFO
            }
            else {
                Copy-Item -Path $sf.FullName -Destination $target -Force
                Write-LogMessage "Deployed $($category)/$($sf.Name)" -Level INFO
            }
            $totalCopied++
        }
    }
}

if ("skills" -in $categories) {
    $srcDir  = Join-Path $scriptRoot "skills"
    $destDir = Join-Path $cursorHome "skills"

    if (Test-Path $srcDir) {
        if (-not (Test-Path $destDir)) {
            if (-not $WhatIf) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
        }

        $skillFolders = Get-ChildItem -Path $srcDir -Directory
        foreach ($sf in $skillFolders) {
            $destSkillDir = Join-Path $destDir $sf.Name
            if (-not (Test-Path $destSkillDir)) {
                if (-not $WhatIf) {
                    New-Item -ItemType Directory -Path $destSkillDir -Force | Out-Null
                }
            }

            $skillFiles = Get-ChildItem -Path $sf.FullName -File -Recurse
            foreach ($file in $skillFiles) {
                $relativePath = $file.FullName.Substring($sf.FullName.Length).TrimStart('\', '/')
                $targetPath   = Join-Path $destSkillDir $relativePath
                $targetDir    = Split-Path $targetPath -Parent

                if (-not (Test-Path $targetDir)) {
                    if (-not $WhatIf) {
                        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                    }
                }

                $needsCopy = $true
                if (Test-Path $targetPath) {
                    $srcHash  = (Get-FileHash $file.FullName -Algorithm SHA256).Hash
                    $destHash = (Get-FileHash $targetPath -Algorithm SHA256).Hash
                    if ($srcHash -eq $destHash) {
                        $needsCopy = $false
                        $totalSkipped++
                    }
                }

                if ($needsCopy) {
                    if ($WhatIf) {
                        Write-LogMessage "WhatIf: Would deploy skills/$($sf.Name)/$($relativePath)" -Level INFO
                    }
                    else {
                        Copy-Item -Path $file.FullName -Destination $targetPath -Force
                        Write-LogMessage "Deployed skills/$($sf.Name)/$($relativePath)" -Level INFO
                    }
                    $totalCopied++
                }
            }
        }
    }
}

Write-LogMessage "Deployment complete. Deployed: $($totalCopied), Unchanged: $($totalSkipped)" -Level INFO

if ($totalCopied -gt 0 -and -not $WhatIf) {
    Write-Host ""
    Write-Host "Restart Cursor to load the new user rules, commands, and skills." -ForegroundColor Yellow
}
