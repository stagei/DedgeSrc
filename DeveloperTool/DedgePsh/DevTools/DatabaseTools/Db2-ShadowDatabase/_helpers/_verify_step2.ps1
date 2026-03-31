$errors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path (Split-Path $PSScriptRoot -Parent) 'Step-2-CopyDatabaseContent.ps1'),
    [ref]$tokens,
    [ref]$errors
)

if ($errors.Count -gt 0) {
    Write-Host "Found $($errors.Count) parse error(s):"
    foreach ($e in $errors) { Write-Host "  $($e.Extent.StartLineNumber): $($e.Message)" }
}
else {
    Write-Host "Step-2: Syntax OK, no parse errors"
}
