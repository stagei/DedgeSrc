$scripts = @(
    'Run-FullShadowPipeline.ps1',
    'Step-1-CreateShadowDatabase.ps1',
    'Step-2-CopyDatabaseContent.ps1',
    'Step-3-CleanupShadowDatabase.ps1',
    'Step-4-MoveToOriginalInstance.ps1',
    'Step-5-VerifyRowCounts.ps1',
    'Invoke-ShadowDatabaseOrchestrator.ps1',
    'Invoke-RemoteShadowPipeline.ps1',
    'Stop-RemoteShadowPipeline.ps1'
)

$allOk = $true
foreach ($script in $scripts) {
    $path = Join-Path (Split-Path $PSScriptRoot -Parent) $script
    $errors = $null
    $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null

    if ($errors.Count -gt 0) {
        Write-Host "FAIL: $($script) - $($errors.Count) error(s):"
        foreach ($e in $errors) { Write-Host "  L$($e.Extent.StartLineNumber): $($e.Message)" }
        $allOk = $false
    }
    else {
        Write-Host "OK:   $($script)"
    }
}

if ($allOk) { Write-Host "`nAll scripts: Syntax OK" }
else { Write-Host "`nSome scripts have errors!"; exit 1 }
