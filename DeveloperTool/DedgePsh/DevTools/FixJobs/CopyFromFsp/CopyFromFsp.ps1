
Import-Module Deploy-Handler -Force
Import-Module GlobalFunctions -Force

$targetFolderBase = "$env:OptPath\src\DedgePsh\Forsprang"
    $exclude = @("*.log")

$sourceFolder = "\\t-no1fkmfsp-app\opt\_DedgePshApps\_VFT"
$targetFolder = Join-Path $targetFolderBase "_VFT"
Start-RoboCopy -SourceFolder $sourceFolder -DestinationFolder $targetFolder -Exclude $exclude -Recurse
$sourceFolder = "\\t-no1fkmfsp-app\opt\_DedgePshApps\_FUT"
$targetFolder = Join-Path $targetFolderBase "_FUT"
Start-RoboCopy -SourceFolder $sourceFolder -DestinationFolder $targetFolder -Exclude $exclude -Recurse
$sourceFolder = "\\t-no1fkmfsp-app\opt\_DedgePshApps\_KAT"
$targetFolder = Join-Path $targetFolderBase "_KAT"
Start-RoboCopy -SourceFolder $sourceFolder -DestinationFolder $targetFolder -Exclude $exclude -Recurse
$sourceFolder = "\\t-no1fkmfsp-app\opt\_DedgePshApps\_MIG"
$targetFolder = Join-Path $targetFolderBase "_MIG"
Start-RoboCopy -SourceFolder $sourceFolder -DestinationFolder $targetFolder -Exclude $exclude -Recurse
$sourceFolder = "\\t-no1fkmfsp-app\opt\_DedgePshApps\_PER"
$targetFolder = Join-Path $targetFolderBase "_PER"
Start-RoboCopy -SourceFolder $sourceFolder -DestinationFolder $targetFolder -Exclude $exclude -Recurse
$sourceFolder = "\\t-no1fkmfsp-app\opt\_DedgePshApps\_SIT"
$targetFolder = Join-Path $targetFolderBase "_SIT"
Start-RoboCopy -SourceFolder $sourceFolder -DestinationFolder $targetFolder -Exclude $exclude -Recurse
$sourceFolder = "\\t-no1fkmfsp-app\opt\_DedgePshApps\_VFK"
$targetFolder = Join-Path $targetFolderBase "_VFK"
Start-RoboCopy -SourceFolder $sourceFolder -DestinationFolder $targetFolder -Exclude $exclude -Recurse

