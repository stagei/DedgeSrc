Import-Module GlobalFunctions -Force
Import-Module SoftwareUtils -Force

function Get-Db2ExePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExeName
    )
    $db2SearchPaths = @(
        "C:\DbInst\BIN",
        "C:\Program Files\IBM\SQLLIB\BIN",
        "C:\Program Files (x86)\IBM\SQLLIB\BIN"
    )
    foreach ($path in $db2SearchPaths) {
        $db2Exe = Get-ChildItem -Path $path -Filter "$ExeName.exe" -ErrorAction SilentlyContinue
        if ($db2Exe) {
            return $db2Exe.FullName
        }
    }
}

if ($PSScriptRoot.Contains("DevTools")) {
    $pngPath = "$PSScriptRoot\IBM-DB2Admin.png"
    $iconPath = ConvertTo-Icon -InputPath $pngPath -Sizes @(16, 32, 48, 64, 128, 256)
}
else {
    $iconPath = $env:OptPath + "\DedgePshApps\Db2-CreateDb2CliShortCuts\IBM-DB2Admin.ico"
}

# Create shortcuts
$targetPath = Get-Db2ExePath -ExeName "db2cmdAdmin"
Add-DesktopShortcut -ShortcutName "Db2 Admin CLI" -TargetPath $targetPath -IconPath $iconPath -WorkingDirectory "$env:OptPath\DedgePshApps" -RunAsAdmin

if ($PSScriptRoot.Contains("DevTools")) {
    $pngPath = "$PSScriptRoot\IBM-DB2.png"
    $iconPath = ConvertTo-Icon -InputPath $pngPath -Sizes @(16, 32, 48, 64, 128, 256)
}
else {
    $iconPath = $env:OptPath + "\DedgePshApps\Db2-CreateDb2CliShortCuts\IBM-DB2.ico"
}

$targetPath = Get-Db2ExePath -ExeName "db2cmd"
Add-DesktopShortcut -ShortcutName "Db2 CLI" -TargetPath $targetPath -IconPath $iconPath -WorkingDirectory "$env:OptPath\DedgePshApps"

Write-LogMessage "Shortcut created at Desktop"

