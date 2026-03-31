Import-Module GlobalFunctions -Force
$OldArray = @(
    "psh\_Modules"
)
# $NewArray = @(
#     "_Modules"
#     "CommonModules\Db2Cli-Handler"
#     "HentSLF"
#     "Setup-FkAdmUsersOnOldServiceAccount"
#     "Add-BatchLogonRigthsOnComputer"
#     "Add-BatchLogonRigthsOnComputer copy"
#     "Db2-CreateDb2CwAdminShortcut"
#     "DisableNtlmPolicyRestriction"
#     "Fix-Path copy"
#     "HentSLF"
#     "MicroFocus-ExtFh"
#     "Reapply-DefaultServerSettings"
#     "Run-Gxbfloi"
#     "Setup-FkAdmUsers"
#     "Setup-FkAdmUsersOnFkAdmRdp"
#     "Db2-BackupRestore"
#     "Db2-PermissionFix",
#     "Set-Db2SetOwnerOnProgramDataIbmDirectory"
#     "Db2-AutoGrant"
# )
$NewArray = @(
    "_Modules"
    "CommonModules\Db2Cli-Handler"
    "HentSLF"
    "Setup-FkAdmUsersOnOldServiceAccount"
    "Add-BatchLogonRigthsOnComputer"
    "Add-BatchLogonRigthsOnComputer copy"
    "Db2-CreateDb2CwAdminShortcut"
    "DisableNtlmPolicyRestriction"
    "Fix-Path copy"
    "HentSLF"
    "MicroFocus-ExtFh"
    "Reapply-DefaultServerSettings"
    "Run-Gxbfloi"
    "Setup-FkAdmUsers"
    "Setup-FkAdmUsersOnFkAdmRdp"
    "Db2-BackupRestore"
    "Db2-PermissionFix"
    "Set-Db2SetOwnerOnProgramDataIbmDirectory"
    "Db2-AutoGrant"
    "_PowerShell-Handler"
    "Db2-AddAdminGrants"
    "Db2-AddEnvGroupAdmin"
    "Db2-AddLogging"
    "Db2-AddUserDb2Admin"
    "Db2-AddUsersToFederatedDb"
    "Db2-Administration"
    "Db2-AutoCatalog-AVD"
    "Db2-AutoRefresh"
    "Db2-BackupRestoreOld"
    "Db2-ClientConfigDefault"
    "Db2-CreateFakeServerFed"
    "Db2-FixDb2AdminUser"
    "Db2-GrantExplicitForIntegrations"
    "Db2-Granting"
    "Db2-KerberosServerConfig"
    "Db2-LogFileDecoder"
    "Db2-ManualOnlineBackup"
    "Db2-Migration"
    "Db2-ServerAdminFix"
    "Db2-ShadowInstanceNTLM"
    "Db2-SqlGenerator"
    "Db2-TemplateEngine"
    "Defender-VerifySpecificExclusions"
    "Install-SshServer"
    "Map-CommonNetworkDrives"
    "ooRexx"
    "PushIntToCitrix"
    "RunAsAdminLaps",
    "Pwsh-CreateAdminShortcut",
    "AdEntra-CompareUserSettings",
    "Auto-ServerPshInstall",
    "Add-BatchLogonCurrentUser",
    "Install-ServerMonitorAgent",
    "Install-ServerMonitor",
    "Install-ServerMonitorDashboard",
    "Install-ServerMonitorService",
    "ServerMonitorDashboard",
    "Db2-AnalyzeMemoryConfig"
)

$completeArray = $OldArray
foreach ($item in $NewArray) {
    $completeArray += "DedgePshApps\$item"
}
$array = $completeArray

$objList = Get-ComputerNameList -ComputerNameList $(Get-ValidServerNameList)
$objList | Format-Table -Property ComputerName
foreach ($obj in $objList) {

    foreach ($item in $array) {
        $tempPath = "\\" + $obj + "\opt\" + $item
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Recurse -Force -ErrorAction Continue
            Write-LogMessage -Message "$($obj): Removing $tempPath" -Level INFO
        }
    }
}

$objList = @("dedge-server")
foreach ($obj in $objList) {

    foreach ($item in $array) {
        $tempPath = "\\" + $obj + "\DedgeCommon\Software\" + $item
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Recurse -Force -ErrorAction Continue
            Write-LogMessage -Message "$($obj): Removing $tempPath" -Level INFO
        }
    }
}

