######################################################################################################
# Adjust this part
######################################################################################################
$computerName = "t-no1fkmvft-db"
$recurse = $false

######################################################################################################
# Do not change this part
######################################################################################################
$currentFolder = Split-Path -Path $PSScriptRoot -Leaf
Write-Host "Current folder: $currentFolder"
$deployFolder = "\\" + $computerName + "\opt\DedgePshApps\" + $currentFolder

if ($recurse) {
    Copy-Item -Path "$PSScriptRoot\*" -Destination $deployFolder -Recurse -Force
} else {
    Copy-Item -Path "$PSScriptRoot\*" -Destination $deployFolder -Force
}
Get-ChildItem -Path "$deployFolder\*" -Recurse | Where-Object { $_.Name -like "_Q*.ps1" -or $_.Name -like "deploy*.ps1" } | Remove-Item -Force

Write-Host "Deployed to $deployFolder"

