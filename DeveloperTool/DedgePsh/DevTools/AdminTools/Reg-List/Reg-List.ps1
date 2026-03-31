<#
.SYNOPSIS
    Searches for registry properties based on input parameters.

.DESCRIPTION
    This script searches for registry properties related to the input parameter.
    Supports wildcard patterns (*) in registry paths. Automatically converts registry path formats:
    - HKCU\ to HKCU: format
    - Computer\HKEY_CURRENT_USER\ to HKCU: format (English regedit)
    - Datamaskin\HKEY_CURRENT_USER\ to HKCU: format (Norwegian regedit)

    Behavior:
    - If path points to a specific property: lists only that property with datatype and value
    - If path points to a folder: lists all properties in that folder
    - If -Recurse is set: includes all properties in subfolders
    - Always includes datatype and value information for each property

    Output format depends on the number of folders found:
    - Multiple folders: ConvertTo-Json
    - Single folder: Format-List

.PARAMETER SearchString
    The registry path or search term to look for. Can be a full registry path, wildcard pattern, regedit copied path, or search term.

.PARAMETER Recurse
    If specified, searches recursively through all subfolders.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Searches for properties in the specified registry path.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Recurse
    Searches recursively through the specified registry path and all subfolders.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\*" -Recurse
    Searches for all registry keys under Explorer using wildcard pattern.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKLM\Software\Microsoft\Windows\CurrentVersion\*" -Recurse
    Searches for all registry keys under CurrentVersion using wildcard pattern.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "Computer\HKEY_CURRENT_USER\Software\Micro Focus\NetExpress\5.1\IDE\Edit Clipboard"
    Searches using a path copied from regedit (English version).

.EXAMPLE
    .\Reg-List.ps1 -SearchString "Datamaskin\HKEY_CURRENT_USER\Software\Micro Focus\NetExpress\5.1\IDE\Edit Clipboard"
    Searches using a path copied from regedit (Norwegian version).

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\ShowEncryptCompressedColor"
    Lists only the specific property with its datatype and value.

.EXAMPLE
    .\Reg-List.ps1 -SearchString "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Recurse
    Lists all properties in the Advanced folder and all subfolders with datatype and value information.

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
#>
param(
    [Parameter(Mandatory = $false)]
    #[string]$SearchString = "Datamaskin\HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\6EC9DDDF052905D4687BAC8742FB7E8E",
    [string]$SearchString = "Datamaskin\HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\EC2C*",
    [Parameter(Mandatory = $false)]
    [switch]$Recurse,
    [Parameter(Mandatory = $false)]
    [switch]$OutputJson

)

# Handle empty search string
if ([string]::IsNullOrEmpty($SearchString)) {
    $SearchString = "Datamaskin\HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer\Products\EC2C*"
}

# Import required modules
Import-Module GlobalFunctions -Force

$result = Get-RegListSearchResults -SearchString $SearchString -Recurse:$Recurse -OutputJson:$OutputJson
Show-RegListResults -result $result.result -inaccessiblePaths $result.inaccessiblePaths -OutputJson:$OutputJson

