<#
.SYNOPSIS
Azure Trusted Signing Tool - Automatically adds or removes digital signatures from executable files.

.DESCRIPTION
This script is a code signing tool that uses Azure Trusted Signing to automatically add or remove digital signatures from executable files.
It can process individual files, directories, or file patterns, with support for recursive directory scanning.

.NOTES
Developer: Geir Helge Starholm (Dedge AS)
Copyright: Dedge AS
This is part of Dedge's custom signing tools that use Azure Trusted Signing.

.PARAMETER Path
The path to process. This can be:
- A specific file path
- A directory path
- A file pattern (e.g., "*.exe")
Default value is "." (current directory)

.PARAMETER Recursive
Switch to enable recursive scanning of subdirectories when Path is a directory.

.PARAMETER Action
Specifies whether to add or remove signatures.
Valid values: 'Add', 'Remove'
Default value: 'Add'

.EXAMPLE
.\DedgeSign.ps1
Adds signatures to all unsigned executable files in the current directory.

.EXAMPLE
.\DedgeSign.ps1 -Path "C:\MyApp\bin\Release" -Action Add
Adds signatures to all unsigned executable files in the specified directory.

.EXAMPLE
.\DedgeSign.ps1 -Path "C:\MyApp" -Recursive -Action Remove
Removes signatures from all signed executable files in the specified directory and its subdirectories.

.EXAMPLE
.\DedgeSign.ps1 -Path "*.exe" -Action Add
Adds signatures to all unsigned .exe files in the current directory.

.EXAMPLE
.\DedgeSign.ps1 -Path "C:\Installers\Setup.msi" -Action Add
Adds a signature to a single MSI installer file.

.NOTES
This tool uses Azure Trusted Signing to add or remove digital signatures.
Supported file extensions: .exe, .dll, .ps1, .psm1, .psd1, .vbs, .wsf, .js, .msi, .sys, .ocx, .ax, .cpl, .drv, .efi, .mui, .scr, .tsp, .plugin, .xll, .wll, .pyd, .pyo, .pyc, .jar, .war, .ear, .class, .xpi, .crx, .nex, .xbap, .application, .manifest, .appref-ms, .gadget, .widget, .ipa, .apk, .xap, .msix, .msixbundle, .appx, .appxbundle, .msp, .mst, .msu, .tlb, .com
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromPipeline = $true)]
    [string]$Path = ".",

    [Parameter()]
    [switch]$Recursive = $false,

    [Parameter()]
    [ValidateSet('Add', 'Remove')]
    [string]$Action = 'Add',

    [Parameter()]
    [switch]$NoConfirm = $true,

    [Parameter()]
    [switch]$Parallel = $false,

    [Parameter()]
    [switch]$ParallelNoWait = $false,

    [Parameter()]
    [switch]$QuietMode = $false
)
Import-Module DedgeSign -Force -ErrorAction Stop

Invoke-DedgeSign -Path $Path -Recursive:$Recursive -Action $Action -NoConfirm:$NoConfirm -Parallel:$Parallel -ParallelNoWait:$ParallelNoWait -QuietMode:$QuietMode

