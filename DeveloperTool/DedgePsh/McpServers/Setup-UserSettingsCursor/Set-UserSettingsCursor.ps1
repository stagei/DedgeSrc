<#
.SYNOPSIS
    Configures standardized Cursor IDE user settings for any team member.
.DESCRIPTION
    Reads (or creates) the user's Cursor settings.json and merges the
    team-standard settings into it.  Existing user settings that are NOT
    in the standard set are preserved.
.EXAMPLE
    pwsh.exe -NoProfile -File Set-UserSettingsCursor.ps1
    pwsh.exe -NoProfile -File Set-UserSettingsCursor.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param()

Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force


# Install Extensions
$extensions = Get-ExtentionArray

foreach ($extension in $extensions) {
    Install-CursorExtension -ExtensionId $extension.Id
}

$settingsDir = Join-Path $env:APPDATA 'Cursor\User'
$settingsPath = Join-Path $settingsDir 'settings.json'

Write-LogMessage "Set-UserSettingsCursor starting for user $($env:USERNAME)" -Level INFO
Write-LogMessage "Target: $($settingsPath)" -Level INFO

# ── Read existing settings or start fresh ────────────────────────────
if (Test-Path $settingsPath) {
    $raw = Get-Content -Path $settingsPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $settings = [PSCustomObject]@{}
    }
    else {
        $settings = $raw | ConvertFrom-Json
    }
    Write-LogMessage "Loaded existing settings.json" -Level INFO
}
else {
    if (-not (Test-Path $settingsDir)) {
        New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null
    }
    $settings = [PSCustomObject]@{}
    Write-LogMessage "No existing settings.json found — will create new" -Level INFO
}

# ── Helper: set a property (add or overwrite) ────────────────────────
function Set-SettingsProperty {
    param(
        [PSCustomObject]$Object,
        [string]$Name,
        $Value
    )
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

# ═══════════════════════════════════════════════════════════════════════
# Standard settings — sourced from the team reference settings.json
# ═══════════════════════════════════════════════════════════════════════

# ── Window / UI ───────────────────────────────────────────────────────
Set-SettingsProperty $settings 'window.title'                          '${rootName}${separator}${activeEditorShort}${dirty}${separator}${appName}'
Set-SettingsProperty $settings 'explorer.openEditors.visible'          0
Set-SettingsProperty $settings 'workbench.view.alwaysShowHeaderActions' $false
Set-SettingsProperty $settings 'window.commandCenter'                  $true
Set-SettingsProperty $settings 'workbench.tree.indent'                 20

# ── PowerShell ────────────────────────────────────────────────────────
Set-SettingsProperty $settings 'powershell.promptToUpdatePowerShell'   $false
Set-SettingsProperty $settings 'terminal.integrated.defaultProfile.windows' 'PowerShell'
Set-SettingsProperty $settings 'powershell.powerShellDefaultVersion'   'PowerShell 7'
Set-SettingsProperty $settings 'powershell.powerShellAdditionalExePaths' ([PSCustomObject]@{
        'PowerShell 7' = 'C:\Program Files\PowerShell\7\pwsh.exe'
        'PowerShell '  = 'C:\Program Files\PowerShell\7\pwsh.exe'
    })

# ── Git ───────────────────────────────────────────────────────────────
Set-SettingsProperty $settings 'git.confirmSync'                       $false
Set-SettingsProperty $settings 'git.autofetch'                         $true
Set-SettingsProperty $settings 'git.enableSmartCommit'                 $true
Set-SettingsProperty $settings 'git.blame.editorDecoration.enabled'    $false
Set-SettingsProperty $settings 'git.blame.statusBarItem.enabled'       $false
Set-SettingsProperty $settings 'git.openRepositoryInParentFolders'     'always'

# ── Editor / files ────────────────────────────────────────────────────
Set-SettingsProperty $settings 'editor.largeFileOptimizations'         $false
Set-SettingsProperty $settings 'files.dialog.defaultPath'              'C:\opt\src'

# ── Cursor-specific ───────────────────────────────────────────────────
Set-SettingsProperty $settings 'cursor.composer.shouldChimeAfterChatFinishes' $true

# ── Language formatters ───────────────────────────────────────────────
Set-SettingsProperty $settings '[json]'  ([PSCustomObject]@{ 'editor.defaultFormatter' = 'esbenp.prettier-vscode' })
Set-SettingsProperty $settings '[jsonc]' ([PSCustomObject]@{ 'editor.defaultFormatter' = 'esbenp.prettier-vscode' })

# ── Log Viewer watch paths ────────────────────────────────────────────
$logViewerWatch = @(
    @{ pattern = 'C:\opt\data\AllPwshLog\*.log'; title = 'Local AllPwshLog' }
    @{ pattern = '\\t-no1fkmdev-db\opt\data\AllPwshLog\*.log'; title = 'DEV t-no1fkmdev-db' }
    @{ pattern = '\\sfk-erp-03\opt\data\AllPwshLog\*.log'; title = 'TST sfk-erp-03' }
    @{ pattern = '\\t-no1fkmtst-app\opt\data\AllPwshLog\*.log'; title = 'TST t-no1fkmtst-app' }
    @{ pattern = '\\t-no1fkmtst-db\opt\data\AllPwshLog\*.log'; title = 'TST t-no1fkmtst-db' }
    @{ pattern = '\\t-no1fkmtst-soa\opt\data\AllPwshLog\*.log'; title = 'TST t-no1fkmtst-soa' }
    @{ pattern = '\\t-no1fkmtst-web\opt\data\AllPwshLog\*.log'; title = 'TST t-no1fkmtst-web' }
    @{ pattern = 'C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\AllPwshLog\*.log'; title = 'TST dedge-server' }
    @{ pattern = '\\t-no1fkxtst-db\opt\data\AllPwshLog\*.log'; title = 'TST t-no1fkxtst-db' }
    @{ pattern = '\\t-no1inltst-app\opt\data\AllPwshLog\*.log'; title = 'TST t-no1inltst-app' }
    @{ pattern = '\\t-no1inltst-db\opt\data\AllPwshLog\*.log'; title = 'TST t-no1inltst-db' }
    @{ pattern = '\\t-no1qvp-rep01\opt\data\AllPwshLog\*.log'; title = 'TST t-no1qvp-rep01' }
    @{ pattern = '\\t-no1fkmfsp-app\opt\data\AllPwshLog\*.log'; title = 'FSP t-no1fkmfsp-app' }
    @{ pattern = '\\t-no1fkmvft-db\opt\data\AllPwshLog\*.log'; title = 'VFT t-no1fkmvft-db' }
    @{ pattern = '\\t-no1fkmvfk-db\opt\data\AllPwshLog\*.log'; title = 'VFK t-no1fkmvfk-db' }
    @{ pattern = '\\t-no1fkmsit-db\opt\data\AllPwshLog\*.log'; title = 'SIT t-no1fkmsit-db' }
    @{ pattern = '\\t-no1fkmmig-db\opt\data\AllPwshLog\*.log'; title = 'MIG t-no1fkmmig-db' }
    @{ pattern = '\\t-no1fkmper-db\opt\data\AllPwshLog\*.log'; title = 'PER t-no1fkmper-db' }
    @{ pattern = '\\t-no1fkmfut-db\opt\data\AllPwshLog\*.log'; title = 'FUT t-no1fkmfut-db' }
    @{ pattern = '\\t-no1fkmkat-db\opt\data\AllPwshLog\*.log'; title = 'KAT t-no1fkmkat-db' }
    @{ pattern = '\\p-no1batch-vm01\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1batch-vm01' }
    @{ pattern = '\\p-no1docprd-db\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1docprd-db' }
    @{ pattern = '\\p-no1erp-sms01\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1erp-sms01' }
    @{ pattern = '\\p-no1fkmprd-app\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1fkmprd-app' }
    @{ pattern = '\\p-no1fkmprd-db\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1fkmprd-db' }
    @{ pattern = '\\p-no1fkmprd-pos\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1fkmprd-pos' }
    @{ pattern = '\\p-no1fkmprd-soa\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1fkmprd-soa' }
    @{ pattern = '\\p-no1fkmprd-web\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1fkmprd-web' }
    @{ pattern = '\\p-no1fkmrap-db\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1fkmrap-db' }
    @{ pattern = '\\p-no1fkxprd-app\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1fkxprd-app' }
    @{ pattern = '\\p-no1fkxprd-db\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1fkxprd-db' }
    @{ pattern = '\\p-no1hstprd-db\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1hstprd-db' }
    @{ pattern = '\\p-no1inlprd-app\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1inlprd-app' }
    @{ pattern = '\\p-no1inlprd-db\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1inlprd-db' }
    @{ pattern = '\\p-no1qvp-rep01\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1qvp-rep01' }
    @{ pattern = '\\p-no1visprd-db\opt\data\AllPwshLog\*.log'; title = 'PRD p-no1visprd-db' }
    @{ pattern = '\\sfk-batch-vm01\opt\data\AllPwshLog\*.log'; title = 'PRD sfk-batch-vm01' }
    @{ pattern = '\\sfkerp12\opt\data\AllPwshLog\*.log'; title = 'PRD sfkerp12' }
)

Set-SettingsProperty $settings 'logViewer.watch' $logViewerWatch

# ── Allowed UNC hosts ─────────────────────────────────────────────────
$allowedUncHosts = @(
    'p-no1batch-vm01'
    'p-no1docprd-db'
    'p-no1erp-sms01'
    'p-no1fkmprd-app'
    'p-no1fkmprd-db'
    'p-no1fkmprd-pos'
    'p-no1fkmprd-soa'
    'p-no1fkmprd-web'
    'p-no1fkmrap-db'
    'p-no1fkxprd-app'
    'p-no1fkxprd-db'
    'p-no1hstprd-db'
    'p-no1inlprd-app'
    'p-no1inlprd-db'
    'p-no1qvp-rep01'
    'p-no1visprd-db'
    'sfk-batch-vm01'
    'sfk-erp-03'
    'sfkerp12'
    't-no1fkmdev-db'
    't-no1fkmfsp-app'
    't-no1fkmfut-db'
    't-no1fkmkat-db'
    't-no1fkmmig-db'
    't-no1fkmper-db'
    't-no1fkmsit-db'
    't-no1fkmtst-app'
    't-no1fkmtst-db'
    't-no1fkmtst-soa'
    't-no1fkmtst-web'
    't-no1fkmvfk-db'
    't-no1fkmvft-db'
    'dedge-server'
    't-no1fkxtst-db'
    't-no1inltst-app'
    't-no1inltst-db'
    't-no1qvp-rep01'
)

# Merge with any existing hosts the user may already have
if ($settings.PSObject.Properties.Name -contains 'security.allowedUNCHosts') {
    $existing = @($settings.'security.allowedUNCHosts')
    $merged = @($existing) + @($allowedUncHosts) | Select-Object -Unique | Sort-Object
    Set-SettingsProperty $settings 'security.allowedUNCHosts' $merged
}
else {
    Set-SettingsProperty $settings 'security.allowedUNCHosts' $allowedUncHosts
}

# ═══════════════════════════════════════════════════════════════════════
# Write back
# ═══════════════════════════════════════════════════════════════════════
if ($PSCmdlet.ShouldProcess($settingsPath, 'Write standardized Cursor settings')) {
    $json = $settings | ConvertTo-Json -Depth 100
    Set-Content -Path $settingsPath -Value $json -Encoding utf8
    Write-LogMessage "Settings written to $($settingsPath)" -Level INFO
}

Write-LogMessage "Set-UserSettingsCursor completed for user $($env:USERNAME)" -Level INFO
