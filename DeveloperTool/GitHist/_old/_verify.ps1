$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile('c:\opt\src\GitHist\Export-GitHistoryTree.ps1', [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host "ERROR: $($_.Message) at line $($_.Extent.StartLineNumber)" } }
else { Write-Host 'Parse OK' }

[System.Management.Automation.Language.Parser]::ParseFile('c:\opt\src\GitHist\_run_full_pipeline.ps1', [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Host "ERROR: $($_.Message) at line $($_.Extent.StartLineNumber)" } }
else { Write-Host 'Parse OK' }
