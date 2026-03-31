$Private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
$Public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

foreach ($file in @($Private + $Public)) {
    try   { . $file.FullName }
    catch { Write-Error "Failed to import $($file.FullName): $_" }
}

foreach ($file in $Public) {
    Export-ModuleMember -Function $file.BaseName
}
