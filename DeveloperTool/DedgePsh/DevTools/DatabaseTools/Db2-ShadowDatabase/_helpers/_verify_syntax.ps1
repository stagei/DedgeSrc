$parentDir = Split-Path $PSScriptRoot -Parent
$files = @(Get-ChildItem -Path $parentDir -Filter '*.ps1') + @(Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' | Where-Object { $_.Name -ne '_verify_syntax.ps1' })
$allOk = $true
foreach ($f in $files) {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        $allOk = $false
        Write-Host "ERRORS in $($f.Name):"
        foreach ($e in $errors) { Write-Host "  Line $($e.Extent.StartLineNumber): $($e.Message)" }
    } else {
        Write-Host "OK: $($f.Name)"
    }
}
if ($allOk) { Write-Host "`nALL FILES SYNTAX OK" }
