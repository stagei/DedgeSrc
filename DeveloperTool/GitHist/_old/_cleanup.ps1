Get-ChildItem -Path 'C:\opt\src\GitHist' -Directory -Filter 'Projects_*' | ForEach-Object {
    Write-Host "Removing: $($_.Name)"
    Remove-Item -LiteralPath $_.FullName -Recurse -Force
}
Write-Host 'Cleanup done'
