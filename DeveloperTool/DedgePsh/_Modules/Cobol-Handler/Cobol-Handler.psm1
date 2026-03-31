<#
.SYNOPSIS
    Manages COBOL development environments and runtime configurations across different Micro Focus platforms.

.DESCRIPTION
    This module provides comprehensive functionality for managing COBOL development and runtime environments,
    including Micro Focus Visual COBOL, Enterprise Developer, Net Express, and Enterprise Server. It handles
    path detection, version management, executable location, and environment configuration for COBOL applications.
    Supports both IDE and runtime configurations with automatic architecture detection.

.EXAMPLE
    Get-ActualPaths -Version "MF"
    # Retrieves all available Micro Focus COBOL installation paths

.EXAMPLE
    Get-CobSysPath -Version "5.1" -Subfolder "bin"
    # Gets the COBOL system path for a specific version and subfolder
#>



$modulesToImport = @("GlobalFunctions", "Infrastructure")
foreach ($moduleName in $modulesToImport) {
  $loadedModule = Get-Module -Name $moduleName
  if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
    Import-Module $moduleName -Force
  }
  else {
    Write-Host "Module $moduleName already loaded" -ForegroundColor Yellow
  }
} 
  

$skipCopy = $false
# if ($env:COMPUTERNAME -eq "FK08C4QZ") {
#     $skipCopy = $true
# }
# else {
#     $skipCopy = $false
# }

function Get-CobSysPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $false)]
        [string]$Subfolder
        
    )
    $cobSysPath = $(Join-Path $env:OptPath "Env\CobSys") + $Version
    if ($Subfolder) {
        $cobSysPath = Join-Path $cobSysPath $Subfolder
    }
    return $cobSysPath
} 



# function Get-ActualPaths {
#     param(
#         [Parameter(Mandatory = $true)]
#         [string]$Version,
#         [Parameter(Mandatory = $false)]
#         [bool]$ForceServer = $false
#     )
#     if ($ForceServer) {
#         $programFilesPaths = @(
#             @{Path = "C:\Program Files"; Architecture = "x64" }
#         )   
#         $potentialPaths = @(
#             @{
#                 Path     = "Micro Focus\Server 5.1"            # Server 5.1
#                 Version  = "MF"
#                 ToolType = "RUNTIME"
#                 ExeList  = @("runw.exe", "run.exe")
#                 Group    = "Standard Server"
#             }
#         )
#         $subPaths = @(
#             # Base paths
#             @{
#                 Path = "bin"
#                 Type = "Bin"
#             }
#         )
#     }
#     else {
#         $programFilesPaths = @(
#             @{Path = "C:\Program Files"; Architecture = "x64" },
#             @{Path = "C:\Program Files (x86)"; Architecture = "Any" }
#         )
                
#         $potentialPaths = @(
#             @{
#                 Path     = "Micro Focus\Visual COBOL\Base"           # Visual COBOL
#                 Version  = "VC"
#                 ToolType = "IDE"
#                 ExeList  = @("runw.exe", "run.exe", "cobol.exe")
#                 Group    = "Visual COBOL"
#             },
#             @{
#                 Path     = "Micro Focus\Visual COBOL\DialogSystem"           # Visual COBOL
#                 Version  = "VC"
#                 ToolType = "DSIDE"
#                 ExeList  = @("dswin.exe")
#                 Group    = "Visual COBOL"
#             },
#             @{
#                 Path     = "Micro Focus\Enterprise Developer\Base"   # Enterprise Developer
#                 Version  = "MF"
#                 ToolType = "IDE"
#                 ExeList  = @("runw.exe", "run.exe", "cobol.exe")
#                 Group    = "Enterprise Developer"
#             },
#             @{
#                 Path     = "Micro Focus\Enterprise Developer\DialogSystem"   # Enterprise Developer
#                 Version  = "MF"
#                 ToolType = "DSIDE"
#                 ExeList  = @("dswin.exe")
#                 Group    = "Enterprise Developer"
#             },
#             @{
#                 Path     = "Micro Focus\Net Express 5.1\Base"  # Development Tools
#                 Version  = "MF"
#                 ToolType = "IDE"
#                 ExeList  = @("runw.exe", "run.exe", "cobol.exe")
#                 Group    = "Net Express"
#             },
#             @{
#                 Path     = "Micro Focus\Net Express 5.1\DialogSystem"  # Development Tools
#                 Version  = "MF"
#                 ToolType = "DSIDE"
#                 ExeList  = @("dswin.exe")
#                 Group    = "Net Express"
#             },
#             @{
#                 Path     = "Micro Focus\Enterprise Server"      # Enterprise Server
#                 Version  = "MF" 
#                 ToolType = "RUNTIME"
#                 ExeList  = @("runw.exe", "run.exe")
#                 Group    = "Enterprise Server"
#             },
#             @{
#                 Path     = "Micro Focus\Server 5.1"            # Server 5.1
#                 Version  = "MF"
#                 ToolType = "RUNTIME"
#                 ExeList  = @("runw.exe", "run.exe")
#                 Group    = "Standard Server"
#             }
#         )
    
#         $subPaths = @(
#             # Base paths
#             @{
#                 Path = "bin"
#                 Type = "Bin"
#             },
#             @{
#                 Path = "bin64"
#                 Type = "Bin"
#             },
#             # @{
#             #     Path         = "bin\WIN64"
#             #     Type         = "Bin"
#             #     Architecture = "x64"
#             # },
#             @{
#                 Path         = "lib"
#                 Type         = "Lib"
#                 Architecture = "Any"
#             },
#             @{
#                 Path         = "lib64"
#                 Type         = "Lib"
#                 Architecture = "Any"
#             }
#             #,
#             # @{
#             #     Path         = "lib\WIN64"
#             #     Type         = "Lib"
#             #     Architecture = "x64"
#             # }
#         )
#     }
#     $actualPaths = @()
#     foreach ($programFilesPath in $programFilesPaths) {
#         foreach ($potentialPath in $potentialPaths) {
#             foreach ($subPath in $subPaths) {
#                 if ($potentialPath.Version -eq $Version) {
#                     $actualPath = Join-Path $programFilesPath.Path $potentialPath.Path $subPath.Path
#                     if ((Test-Path $actualPath -PathType Container) -or $ForceServer) {
#                         Write-LogMessage "Found path $actualPath" -Level INFO

#                         $allExeFound = $true
#                         $tempExeList = @()
#                         try {
#                             $tempExeList = $potentialPath.ExeList
#                         }
#                         catch {
#                             $tempExeList = @()
#                         }

#                         $fullPathExeList = @()
#                         if ($actualPath.Contains("\bin")) {
#                             foreach ($exe in $tempExeList) {
#                                 $fullPathExe = Join-Path $actualPath $exe
#                                 if ((-not (Test-Path $fullPathExe -PathType Leaf)) -and -not $ForceServer) {
#                                     Write-LogMessage "Exe $exe not found in path $fullPathExe" -Level WARN
#                                     $allExeFound = $false
#                                 }
#                                 else {
#                                     $fullPathExeList += @{
#                                         Path = $fullPathExe
#                                         Name = $exe
#                                     }
#                                     Write-LogMessage "Exe $exe found in path $actualPath" -Level INFO
#                                 }
#                             }
#                         }

                    
#                         if ($allExeFound) {
#                             if ( $subPath.Architecture -eq "x64" -or $programFilesPath.Architecture -eq "x64" -or $subPath.Architecture -eq "Any" -or $programFilesPath.Architecture -eq "Any") {
#                                 $architecture = "x64"
#                             }
#                             else {
#                                 $architecture = "x86"
#                             }

#                             $actualPaths += @{
#                                 Version      = $potentialPath.Version
#                                 Group        = $potentialPath.Group
#                                 BasePath     = (Join-Path $programFilesPath $potentialPath.Path)
#                                 Type         = $subPath.Type
#                                 Architecture = $architecture
#                                 Path         = $actualPath
#                                 ExeList      = $fullPathExeList
#                                 ToolType     = $potentialPath.ToolType
#                             }
#                         }
#                     }
#                 }
#             }
#         }
#     }
#     # Returns array of hashtables containing Version, BasePath, Type, Architecture and Path
#     return [PSCustomObject[]]$actualPaths
# }

function Get-CobolEnvironmentVariables {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Application,
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$Architecture,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Machine", "User")]
        [string]$EnvironmentSource = "Machine",
        [Parameter(Mandatory = $false)]
        [bool]$ForceServer = $false
    )

    $returnObject = @{}
    try {
        # Handle actual paths
        $returnObject.ActualPaths = @(Get-ActualPaths -Version $Version -ForceServer $ForceServer)
         
        $runtimeGroup = $returnObject.ActualPaths | Where-Object { 
            #            ($_.Architecture -eq $Architecture -or $_.Architecture -eq "Any") -and 
            $_.Version -eq $Version -and 
            $_.ToolType -eq "IDE" -and 
            $_.ExeList.Count -eq 3
        } | Select-Object -First 1

        $dsGroup = $returnObject.ActualPaths | Where-Object { 
            $_.Version -eq $Version -and 
            $_.ToolType -eq "DSIDE" -and 
            $_.Group -eq $runtimeGroup.Group -and
            $_.ExeList.Count -eq 1
        } | Select-Object -First 1

        # If no runtime or ds group found, try to find a runtime group
        if ([string]::IsNullOrEmpty($runtimeGroup) -or [string]::IsNullOrEmpty($dsGroup)) {
            $runtimeGroup = $returnObject.ActualPaths | Where-Object { 
                #                ($_.Architecture -eq $Architecture -or $_.Architecture -eq "Any") -and 
                $_.Version -eq $Version -and 
                $_.ToolType -eq "RUNTIME" -and 
                $_.ExeList.Count -gt 0
            } | Select-Object -First 1
        }
        $returnObject.Environment = @{}

        $runExe = $runtimeGroup | Select-Object -ExpandProperty ExeList | Where-Object { $_.Name -eq "run.exe" } | Select-Object -First 1
        if ($runExe) {
            $returnObject.Environment.RUN_EXE = $runExe.Path
        }
        else {
            Write-LogMessage "No compatible cobol runtime run.exe found in path $($runtimeGroup.Path)" -Level WARN
            Write-LogMessage "Returning empty object" -Level WARN
            return $null
        }

        $runwExe = $runtimeGroup | Select-Object -ExpandProperty ExeList | Where-Object { $_.Name -eq "runw.exe" } | Select-Object -First 1
        if ($runwExe) {
            $returnObject.Environment.RUNW_EXE = $runwExe.Path 
        }
        else {
            Write-LogMessage "No compatible cobol windows runtime runw.exe found in path $($runtimeGroup.Path)" -Level WARN
            Write-LogMessage "Returning empty object" -Level WARN
            return $null
        }

        $cobolExe = $runtimeGroup | Select-Object -ExpandProperty ExeList | Where-Object { $_.Name -eq "cobol.exe" } | Select-Object -First 1
        if ($cobolExe) {
            $returnObject.Environment.COBOL_EXE = $cobolExe.Path 
        }
        else {
            if ($runtimeGroup.ToolType -eq "IDE") {
                Write-LogMessage "No compatible cobol compiler cobol.exe found in path $($runtimeGroup.Path)" -Level WARN
            }
        }

        $dswinExe = $dsGroup | Select-Object -ExpandProperty ExeList | Where-Object { $_.Name -eq "dswin.exe" } | Select-Object -First 1
        if ($dswinExe) {
            $returnObject.Environment.DSWIN_EXE = $dswinExe.Path 
        }
        else {
            if ($dsGroup.ToolType -eq "DSIDE") {
                Write-LogMessage "No compatible cobol dialog system dswin.exe found in path $($dsGroup.Path)" -Level WARN
            }
        }

        $returnObject.ExecutablePaths = @()
        if ($runtimeGroup) {
            $returnObject.ExecutablePaths += $runtimeGroup.Path
        }
        if ($dsGroup) {
            $returnObject.ExecutablePaths += $dsGroup.Path
        }

        # Modify the path variable to only include the suitable paths that match the $BasePath
        $returnObject.Environment.PATH = ""
        $returnObject.Environment.PATH = $([System.Environment]::GetEnvironmentVariable("PATH", $EnvironmentSource))
        if ($returnObject.Environment.PATH -isnot [string]) {
            $returnObject.Environment.PATH = $returnObject.Environment.PATH.ToString()
        }

        foreach ($removeOtherPath in $returnObject.ActualPaths) {
            if ($returnObject.Environment.PATH.ToString().ToLower().Contains($removeOtherPath.Path.ToString().ToLower())) {
                # Remove path from environment variable
                $returnObject.Environment.PATH = Remove-PathFromSemicolonSeparatedVariable -Variable $returnObject.Environment.PATH -Path $removeOtherPath.Path
            }    
        }

        # Add suitable paths to environment path variable
        foreach ($suitablePath in $returnObject.ExecutablePaths) {
            $returnObject.Environment.PATH = Add-PathToSemicolonSeparatedVariable -Variable $returnObject.Environment.PATH -Path $suitablePath
        }
    
        # Handle CobSys path
        $returnObject.Environment.COBSYSPATH = Join-Path $(Get-CobSysPath -Version $Version) $Application $Environment

        # find all paths that contain "bin" or "lib" in $ExecutablePaths and join them with a semicolon, start with Bin folders first
        $cobDirPath = ($runtimeGroup | Where-Object { $_.Type -eq "Bin" }).Path + ";" + ($runtimeGroup | Where-Object { $_.Type -eq "Lib" }).Path
    
        # Set IDE environment common variables    
        if ($runtimeGroup.ToolType -eq "IDE") {
            # Handle CobCpy path
            $returnObject.Environment.COBCPY = (Join-Path $returnObject.Environment.COBSYSPATH "SRC" "CBL") + ";" + (Join-Path $returnObject.Environment.COBSYSPATH "SRC" "CBL" "CPY" ) + ";" 
        }

        # Handle Version MF and VC specific environment variables
        if ($Version -eq "MF") {
            $returnObject.Environment.COBDIR = $cobDirPath
        }
        else {
            $cobPath = (Join-Path $cobSysPath "INT") + ";" + (Join-Path $cobSysPath "SRC" "CBL") + ";"
            $returnObject.Environment.COBPATH = $cobPath

            $cobDirPath += ";" + $cobPath
            $returnObject.Environment.COBDIR = $cobDirPath

            # find all paths that contain "lib" in $actualPaths and join them with a semicolon
            $returnObject.Environment.LIB = [System.Environment]::GetEnvironmentVariable("LIB", $EnvironmentSource)    
            foreach ($libPath in ($returnObject.ActualPaths | Where-Object { $_.Type -eq "Lib" -and ($_.Architecture -eq $Architecture -or $_.Architecture -eq "Any") }).Path) {
                if ($returnObject.Environment.LIB -like "*$libPath*") {
                    $returnObject.Environment.LIB = Remove-PathFromSemicolonSeparatedVariable -Variable $returnObject.Environment.LIB -Path $libPath
                }
            }
            # find all paths that contain "lib" in $actualPaths and join them with a semicolon
            foreach ($libPath in ($returnObject.SuitableExecutablePath | Where-Object { $_.Type -eq "Lib" -and ($_.Architecture -eq $Architecture -or $_.Architecture -eq "Any") }).Path) {
                $returnObject.Environment.LIB = Add-PathToSemicolonSeparatedVariable -Variable $returnObject.Environment.LIB -Path $libPath
            }

            $returnObject.Environment.MFVSSW = "/c /f"
            if ($Architecture -eq "x64" -or $Architecture -eq "Any") { 
                $returnObject.Environment.COBMODE = "64"
            }
            else {
                $returnObject.Environment.COBMODE = "32"
            }
        }
    }
    catch {
        Write-LogMessage "Error setting Cobol environment variables" -Level ERROR -Exception $_
       
       
    }
    return [PSCustomObject]$returnObject
}

function Set-CobolEnvironmentVariables {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Application,
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )
    # Get environment variables
    $returnObject = Get-CobolEnvironmentVariables -Application $Application -Environment $Environment -Version $Version -Architecture $Architecture -EnvironmentSource "User"
    
    
    # Explanitory environment variables
    $env:FK_APPLICATION = $Application.ToUpper()
    $env:FK_ENVIRONMENT = $Environment.ToUpper()
    $env:FK_COBVERSION = $Version.ToUpper()
    $env:FK_ARCHITECTURE = $Architecture.ToUpper()

    # Cobol specific environment variables
    $env:LIB = $null
    $env:PATH = $null
    $env:COBCPY = $null
    $env:COBDIR = $null
    $env:COBPATH = $null
    $env:MFVSSW = $null
    $env:COBMODE = $null

    $env:LIB = $returnObject.Environment.LIB
    $env:PATH = $returnObject.Environment.PATH
    
    
    if ($returnObject.Environment.PSObject.Properties.Match('COBCPY').Count -gt 0) {
        $env:COBCPY = $returnObject.Environment.COBCPY
    }
    if ($returnObject.Environment.PSObject.Properties.Match('COBDIR').Count -gt 0) {
        $env:COBDIR = $returnObject.Environment.COBDIR
    }
    if ($returnObject.Environment.PSObject.Properties.Match('COBPATH').Count -gt 0) {
        $env:COBPATH = $returnObject.Environment.COBPATH
    }
    if ($returnObject.Environment.PSObject.Properties.Match('MFVSSW').Count -gt 0) {
        $env:MFVSSW = $returnObject.Environment.MFVSSW
    }
    if ($returnObject.Environment.PSObject.Properties.Match('COBMODE').Count -gt 0) {
        $env:COBMODE = $returnObject.Environment.COBMODE
    }
    
    return $returnObject
}

function Test-Property {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Property,
        [Parameter(Mandatory = $true)]
        [PSObject]$Object
    )
    
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($Property)) {
            Write-LogMessage "Property: $Property = $($Object[$Property])" -Level INFO
            return $true
        }
        return $false
    }
    else {
        if ($Object.PSObject.Properties.Match($Property).Count -gt 0) {
            Write-LogMessage "Property: $Property = $($Object.$Property)" -Level INFO
            return $true
        }
        return $false
    }
}
function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Property,
        [Parameter(Mandatory = $true)]
        [PSObject]$Object
    )
    
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($Property)) {
            Write-LogMessage "Property: $Property = $($Object[$Property])" -Level INFO
            return $Object[$Property]
        }
        return $false
    }
    else {
        if ($Object.PSObject.Properties.Match($Property).Count -gt 0) {
            Write-LogMessage "Property: $Property = $($Object.$Property)" -Level INFO
            return $Object.$Property
        }
        return $false
    }
}

function Set-CommonCobolEnvironmentVariablesAsConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Application,
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$Architecture,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Machine", "User")]
        [string]$EnvironmentSource = "Machine",
        [Parameter(Mandatory = $false)]
        [PSObject]$EnvironmentVariables,
        [Parameter(Mandatory = $false)]
        [string]$OverridePath = ""
    )
    # Get environment variables
    $returnObject = $EnvironmentVariables
    $temp = "$($EnvironmentSource)_Environment_Config_for_$($Application.ToUpper())_$($Environment.ToUpper())_CobolVersion_$($Version.ToUpper())_$($Architecture).cmd"
    if ($OverridePath -ne "") {
        $configFileName = Join-Path $OverridePath $temp
    }
    else {
        $configFileName = Join-Path $returnObject.Environment.COBSYSPATH "CFG" $temp
    }


    # Create config file
    $cobolVersionText = "Cobol Version"
    if ($Version -eq "MF") {
        $cobolVersionText = "Micro Focus"
    }
    else {
        $cobolVersionText = "Visual Cobol"
    }
    Remove-Item -Path $configFileName -Force -ErrorAction SilentlyContinue
    Add-Content -Path $configFileName -Value "@echo off"
    Add-Content -Path $configFileName -Value "---------------------------------------------------------------------"
    Add-Content -Path $configFileName -Value "echo FK Cobol environment setup of $($EnvironmentSource) Environment Variables:"
    Add-Content -Path $configFileName -Value "echo    Application         $($Application.ToUpper())"
    Add-Content -Path $configFileName -Value "echo    Environment         $($Environment.ToUpper())"
    Add-Content -Path $configFileName -Value "echo    Cobol Version       $($cobolVersionText) ($($Version.ToUpper()))"
    Add-Content -Path $configFileName -Value "echo    Architecture        $($Architecture.ToUpper())"
    Add-Content -Path $configFileName -Value "echo    Generated by        $($env:USERNAME) on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Add-Content -Path $configFileName -Value "---------------------------------------------------------------------"
    Add-Content -Path $configFileName -Value ""

    if (Test-Property -Property "PATH" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "PATH" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx PATH `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set PATH `"$temp`""
        }
    }
    if (Test-Property -Property "LIB" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "LIB" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx LIB `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set LIB `"$temp`""
        }
    }
    if (Test-Property -Property "COBCPY" -Object $returnObject.Environment) {    
        $temp = Get-PropertyValue -Property "COBCPY" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx COBCPY $temp /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set COBCPY `"$temp`""
        }
    }
    if (Test-Property -Property "COBDIR" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "COBDIR" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx COBDIR `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set COBDIR `"$temp`""
        }
    }
    if (Test-Property -Property "COBPATH" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "COBPATH" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx COBPATH `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set COBPATH `"$temp`""
        }
    }
    if (Test-Property -Property "MFVSSW" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "MFVSSW" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx MFVSSW `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set MFVSSW `"$temp`""
        }
    }
    if (Test-Property -Property "COBMODE" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "COBMODE" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx COBMODE `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set COBMODE `"$temp`""
        }
    }
    Add-Content -Path $configFileName -Value ""

    Write-LogMessage "Created $($EnvironmentSource) environment config file: $configFileName" -Level INFO
    return $configFileName
}
function Save-CobolEnvironmentVariablesAsConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Application,
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$Architecture,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Machine", "User")]
        [string]$EnvironmentSource = "Machine"
    )
    # Get environment variables
    $returnObject = Get-CobolEnvironmentVariables -Application $Application -Environment $Environment -Version $Version -Architecture $Architecture -EnvironmentSource $EnvironmentSource
    $temp = "$($EnvironmentSource)_Environment_Config_for_$($Application.ToUpper())_$($Environment.ToUpper())_CobolVersion_$($Version.ToUpper())_$($Architecture).cmd"
    $configFileName = Join-Path $returnObject.Environment.COBSYSPATH "CFG" $temp

    # Create config file
    $cobolVersionText = "Cobol Version"
    if ($Version -eq "MF") {
        $cobolVersionText = "Micro Focus"
    }
    else {
        $cobolVersionText = "Visual Cobol"
    }
    Remove-Item -Path $configFileName -Force -ErrorAction SilentlyContinue
    Add-Content -Path $configFileName -Value "@echo off"
    Add-Content -Path $configFileName -Value "---------------------------------------------------------------------"
    Add-Content -Path $configFileName -Value "echo FK Cobol environment setup of $($EnvironmentSource) Environment Variables:"
    Add-Content -Path $configFileName -Value "echo    Application         $($Application.ToUpper())"
    Add-Content -Path $configFileName -Value "echo    Environment         $($Environment.ToUpper())"
    Add-Content -Path $configFileName -Value "echo    Cobol Version       $($cobolVersionText) ($($Version.ToUpper()))"
    Add-Content -Path $configFileName -Value "echo    Architecture        $($Architecture.ToUpper())"
    Add-Content -Path $configFileName -Value "echo    Generated by        $($env:USERNAME) on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Add-Content -Path $configFileName -Value "---------------------------------------------------------------------"
    Add-Content -Path $configFileName -Value ""

    if (Test-Property -Property "PATH" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "PATH" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx PATH `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set PATH `"$temp`""
        }
    }
    if (Test-Property -Property "LIB" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "LIB" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx LIB `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set LIB `"$temp`""
        }
    }
    if (Test-Property -Property "COBCPY" -Object $returnObject.Environment) {    
        $temp = Get-PropertyValue -Property "COBCPY" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx COBCPY $temp /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set COBCPY `"$temp`""
        }
    }
    if (Test-Property -Property "COBDIR" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "COBDIR" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx COBDIR `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set COBDIR `"$temp`""
        }
    }
    if (Test-Property -Property "COBPATH" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "COBPATH" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx COBPATH `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set COBPATH `"$temp`""
        }
    }
    if (Test-Property -Property "MFVSSW" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "MFVSSW" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx MFVSSW `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set MFVSSW `"$temp`""
        }
    }
    if (Test-Property -Property "COBMODE" -Object $returnObject.Environment) {
        $temp = Get-PropertyValue -Property "COBMODE" -Object $returnObject.Environment
        if ($EnvironmentSource -eq "Machine") {
            Add-Content -Path $configFileName -Value "setx COBMODE `"$temp`" /M"
        }
        else {
            Add-Content -Path $configFileName -Value "set COBMODE `"$temp`""
        }
    }
    Add-Content -Path $configFileName -Value ""

    Write-LogMessage "Created $($EnvironmentSource) environment config file: $configFileName" -Level INFO
    return $configFileName
}
function Get-ApplicationInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Application
    )
    $iconPath = Join-Path (Get-CobSysPath -Version $version -Subfolder "GLB") "dedge.ico"
    $applicationMetadataList = @(
        [PSCustomObject]@{
            Application  = "FKM"
            Title        = "Fk-Meny"
            ShortCutList = @(
                [PSCustomObject]@{
                    ProgramName           = "RUNW_EXE"
                    Argument              = "GMSTART"
                    AdditionalArgs        = ""
                    AdditionalDescription = ""
                    Icon                  = $iconPath
                },
                [PSCustomObject]@{
                    ProgramName           = "RUNW_EXE"
                    Argument              = "GMSTART"
                    AdditionalArgs        = ""
                    AdditionalDescription = "Pos"
                    Icon                  = $iconPath
                },
                [PSCustomObject]@{
                    ProgramName           = "RUNW_EXE"
                    Argument              = "KTHOKOR"
                    AdditionalArgs        = ""
                    AdditionalDescription = "Kt-Ordre"
                    Icon                  = $iconPath
                },
                [PSCustomObject]@{
                    ProgramName           = "RUNW_EXE"
                    Argument              = "GMSUSER"
                    AdditionalArgs        = ""
                    AdditionalDescription = "Brukerregister"
                    Icon                  = $iconPath
                },
                [PSCustomObject]@{
                    ProgramName           = "RUNW_EXE"
                    Argument              = "BRSPARK"
                    AdditionalArgs        = "BRHDEBE X"
                    AdditionalDescription = "Sbtr - Delebestilling"
                    Icon                  = $iconPath
                }
            )
        },
        [PSCustomObject]@{
            Application  = "INL"
            Description  = "Fk-Konto"
            ShortCutList = @(
                [PSCustomObject]@{
                    ProgramName           = "RUNW_EXE"
                    Argument              = "GMSTART"
                    AdditionalDescription = ""
                    AdditionalArgs        = ""
                    Icon                  = $iconPath
                }
            )
        }
    )
    $result = [PSCustomObject]($applicationMetadataList | Where-Object { $_.Application -eq $Application })
    return $result
}

function Get-EnvironmentInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Application,
        [Parameter(Mandatory = $true)]
        [string]$Environment

    )

    $jsonMetadata = @(Get-ApplicationsJson)
    if ($Application -eq "*" -and $Environment -eq "*") {
        return $jsonMetadata
    }
    
    
    $environmentMetadataList = @()
    
    foreach ($appItem in $jsonMetadata) {
        if ($appItem.ApplicationCode -ne $Application -and $Application -ne "*") {
            continue
        }
        Write-LogMessage "Processing application: $($appItem.ApplicationCode)" -Level INFO
        
        if (-not $appItem.Environments) {
            Write-LogMessage "No environments found for application: $($appItem.ApplicationCode)" -Level WARNING
            continue
        }

        foreach ($envItem in $appItem.Environments) {
            if ($envItem.EnvironmentCode -ne $Environment -and $Environment -ne "*") {
                continue
            }
            $paths = @()
            $pathObj = [PSCustomObject]@{
                PathType                 = "MF"
                FromRunPath              = ""
                FromBndPath              = ""
                FromCblSrcPath           = ""
                FromCblCpyPath           = ""
                FromSqlPath              = ""
                FromDb2CatPath           = ""
                FromEnvMachineConfigPath = ""
                FromEnvUserConfigPath    = ""
            }
            if (-not $envItem.Paths) {
                $envItem.Paths = @()
            }
                    
            foreach ($path in $envItem.Paths) {
                if ($path.Type -eq "MfRunPath") { 
                    $pathObj.FromRunPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "MfBndPath") { 
                    $pathObj.FromBndPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "MfCblSrcPath") { 
                    $pathObj.FromCblSrcPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "MfCblCpyPath") { 
                    $pathObj.FromCblCpyPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "SqlSourcePath") { 
                    $pathObj.FromSqlPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "Db2CatalogFile") { 
                    $pathObj.FromDb2CatPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "EnvironmentMachineConfig") { 
                    $pathObj.FromEnvMachineConfigPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "EnvironmentUserConfig") { 
                    $pathObj.FromEnvUserConfigPath = $path.Path 
                    continue
                }
            }
            $paths += $pathObj

            $pathObj = [PSCustomObject]@{
                PathType                 = "VC"
                FromRunPath              = ""
                FromBndPath              = ""
                FromCblSrcPath           = ""
                FromCblCpyPath           = ""
                FromSqlPath              = ""
                FromDb2CatPath           = ""
                FromEnvMachineConfigPath = ""
                FromEnvUserConfigPath    = ""
            }
            if (-not $envItem.Paths) {
                $envItem.Paths = @()
            }
                    
            foreach ($path in $envItem.Paths) {
                if ($path.Type -eq "VcRunPath") { 
                    $pathObj.FromRunPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "VcBndPath") { 
                    $pathObj.FromBndPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "VcCblSrcPath") { 
                    $pathObj.FromCblSrcPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "VcCblCpyPath") { 
                    $pathObj.FromCblCpyPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "VcSqlSourcePath") { 
                    $pathObj.FromSqlPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "VcDb2CatalogFile") { 
                    $pathObj.FromDb2CatPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "VcEnvironmentMachineConfig") { 
                    $pathObj.FromEnvMachineConfigPath = $path.Path 
                    continue
                }
                if ($path.Type -eq "VcEnvironmentUserConfig") { 
                    $pathObj.FromEnvUserConfigPath = $path.Path 
                    continue
                }
            }
            $paths += $pathObj
        }

        $environmentMetadataList += [PSCustomObject]@{
            Application = if ($appItem.ApplicationCode) { $appItem.ApplicationCode } else { "" }    
            Environment = if ($envItem.EnvironmentCode) { $envItem.EnvironmentCode } else { "" }
            Description = if ($envItem.Description) { $envItem.Description } else { "" }
            Title       = if ($envItem.Description) { $appItem.Name + " " + $envItem.Description } else { $appItem.Name + " " + $envItem.EnvironmentCode }
            Paths       = if ($paths) { $paths } else { @() }
        }
    }

    return $environmentMetadataList 

    # $environmentMetadataList = @(
    #     [PSCustomObject]@{
    #         Application = "FKM"
    #         Environment = "DEV"
    #         Description = "Utvikling"
    #         Paths       = @(
    #             [PSCustomObject]@{
    #                 PathType       = "MF"
    #                 FromRunPath    = "K:\fkavd\nt"
    #                 FromBndPath    = "K:\fkavd\nt\bnd"
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\DEV"
    #             },
    #             [PSCustomObject]@{
    #                 PathType       = "VC"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\DEV"
    #             }
    #         )
    #     },
    #     [PSCustomObject]@{
    #         Application = "FKM" 
    #         Environment = "TST"
    #         Description = "Test"
    #         Paths       = @(
    #             [PSCustomObject]@{
    #                 PathType       = "MF"
    #                 FromRunPath    = "N:\COBTST"
    #                 FromBndPath    = "N:\COBTST\bnd"
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\TST"
    #             },
    #             [PSCustomObject]@{
    #                 PathType       = "VC"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\TST"
    #             }
    #         )
    #     },
    #     [PSCustomObject]@{
    #         Application = "FKM"
    #         Environment = "MIG"
    #         Description = "Forsprang MIG"
    #         Paths       = @(
    #             [PSCustomObject]@{
    #                 PathType       = "MF"
    #                 FromRunPath    = "N:\COBTST\COBMIG"
    #                 FromBndPath    = "N:\COBTST\COBMIG\bnd"
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\MIG"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basismig_kerberos_2.0.bat"
    #             },
    #             [PSCustomObject]@{
    #                 PathType       = "VC"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\MIG"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basismig_kerberos_2.0.bat"
    #             }
    #         )
    #     },
    #     [PSCustomObject]@{
    #         Application = "FKM"
    #         Environment = "SIT"
    #         Description = "Forsprang SIT"
    #         Paths       = @(
    #             [PSCustomObject]@{
    #                 PathType       = "MF"
    #                 FromRunPath    = "N:\COBTST\COBSIT"
    #                 FromBndPath    = "N:\COBTST\COBSIT\bnd"
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\SIT"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basissit_kerberos_2.0.bat"
    #             },
    #             [PSCustomObject]@{
    #                 PathType       = "VC"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\SIT"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basissit_kerberos_2.0.bat"
    #             }
    #         )
    #     },
    #     [PSCustomObject]@{
    #         Application = "FKM"
    #         Environment = "VFK"
    #         Description = "Forsprang VFK"
    #         Paths       = @(
    #             [PSCustomObject]@{
    #                 PathType       = "MF"
    #                 FromRunPath    = "N:\COBTST\COBVFK"
    #                 FromBndPath    = "N:\COBTST\COBVFK\bnd"
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\VFK"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basissit_kerberos_2.0.bat"
    #             },
    #             [PSCustomObject]@{
    #                 PathType       = "VC"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\VFK"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basissit_kerberos_2.0.bat"
    #             }
    #         )
    #     },
    #     [PSCustomObject]@{
    #         Application = "FKM"
    #         Environment = "VFT"
    #         Description = "Forsprang VFT"
    #         Paths       = @(
    #             [PSCustomObject]@{
    #                 PathType       = "MF"
    #                 FromRunPath    = "N:\COBTST\COBVFT"
    #                 FromBndPath    = "N:\COBTST\COBVFT\bnd"
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\VFT"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basisvft_kerberos_2.0.bat"
    #             },
    #             [PSCustomObject]@{
    #                 PathType       = "VC"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\VFT"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basisvft_kerberos_2.0.bat"
    #             }
    #         )
    #     },
    #     [PSCustomObject]@{
    #         Application = "FKM"
    #         Environment = "RAP"
    #         Description = "Rapportering"
    #         Paths       = @(
    #             [PSCustomObject]@{
    #                 PathType       = "MF"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\RAP"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basisrap_kerberos_2.0.bat"
    #             },
    #             [PSCustomObject]@{
    #                 PathType       = "VC"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\RAP"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basisrap_kerberos_2.0.bat"
    #             }
    #         )
    #     },
    #     [PSCustomObject]@{
    #         Application = "FKM"
    #         Environment = "PRD"
    #         Description = "Produksjon"
    #         Paths       = @(
    #             [PSCustomObject]@{
    #                 PathType       = "MF"
    #                 FromRunPath    = "N:\COBNT"
    #                 FromBndPath    = "N:\COBNT\bnd"
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\PRD"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basispro_kerberos_2.0.bat"
    #             },
    #             [PSCustomObject]@{
    #                 PathType       = "VC"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\PRD"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basispro_kerberos_2.0.bat"
    #             }
    #         )
    #     },
    #     [PSCustomObject]@{
    #         Application = "INL"
    #         Environment = "TST"
    #         Description = "Test"
    #         Paths       = @(
    #             [PSCustomObject]@{
    #                 PathType       = "MF"
    #                 FromRunPath    = "N:\COBTST"
    #                 FromBndPath    = "N:\COBTST\bnd"
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\INL\TST"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basistst_kerberos_2.0.bat"
    #             },
    #             [PSCustomObject]@{
    #                 PathType       = "VC"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\INL\TST"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_basistst_kerberos_2.0.bat"
    #             }
    #         )
    #     },
    #     [PSCustomObject]@{
    #         Application = "INL"
    #         Environment = "PRD"
    #         Description = "Produksjon"
    #         Paths       = @(
    #             [PSCustomObject]@{
    #                 PathType       = "MF"
    #                 FromRunPath    = "N:\COBNT"
    #                 FromBndPath    = "N:\COBNT\bnd"
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\INL\PRD"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_fkkonto_kerberos_2.0.bat"
    #             },
    #             [PSCustomObject]@{
    #                 PathType       = "VC"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\INL\PRD"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_fkkonto_kerberos_2.0.bat"
    #             }
    #         )
    #     }
    #     ,
    #     [PSCustomObject]@{
    #         Application = "INL"
    #         Environment = "DEV"
    #         Description = "Utvikling"
    #         Paths       = @(
    #             [PSCustomObject]@{
    #                 PathType       = "MF"
    #                 FromRunPath    = "K:\fkavd\nt"
    #                 FromBndPath    = "K:\fkavd\nt\bnd"
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\DEV"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_fkontodev_kerberos_2.0.bat"
    #             },
    #             [PSCustomObject]@{
    #                 PathType       = "VC"
    #                 FromRunPath    = ""
    #                 FromBndPath    = ""
    #                 FromCblSrcPath = "K:\fkavd\nt"
    #                 FromCblCpyPath = "K:\fkavd\sys\cpy"
    #                 FromSqlPath    = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\DevToolsCodeUtility\SQLEXPORT\FKM\DEV"
    #                 RunCatalogFile = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\Db2\ClientCatalogScripts\Kerberos\cat_db2_fkontodev_kerberos_2.0.bat"
    #             }
    #         )
    #     }
    # )



    
}


function Get-DatabaseCatalogName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Application,
        [Parameter(Mandatory = $true)]
        [string]$Environment    
    )
    $jsonDatabases = Get-DatabasesJson 
    $jsonDatabase = $jsonDatabases | Where-Object { $_.ConnectionKey.Application -eq $Application -and $_.ConnectionKey.Environment -eq $Environment -and $_.ConnectionKey.Version -ne "1.0" }
    if ($jsonDatabase.ConnectionInfo.Aliases.Count -gt 0) {
        $alias = $jsonDatabase.ConnectionInfo.Aliases[0].DatabaseAlias
    }
    else {
        $alias = $jsonDatabase.ConnectionInfo.Database
    }
    return $alias
}

function New-MenuItemsAndShortcuts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Application,
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [Parameter(Mandatory = $false)]
        [string]$Version,
        [Parameter(Mandatory = $false)]
        [string]$Architecture,
        [Parameter(Mandatory = $false)]
        [string]$EnvironmentPath,
        [Parameter(Mandatory = $false)]
        [string]$DestRunPath,
        [Parameter(Mandatory = $false)]
        [string]$FromRunPath,
        [Parameter(Mandatory = $false)]
        [string]$PathType = "MfRunPath",
        [Parameter(Mandatory = $false)]
        [bool]$OnlyReturnMetadata = $false,
        [Parameter(Mandatory = $false)]
        [string]$OverrideRunPath = $null,
        [Parameter(Mandatory = $false)]
        [string]$OverrideIntPath = $null
    )
    try {
        $destRunPathUnc = $FromRunPath
        $results = @()

        

        $serverInfo = Get-ComputerMetaData -Name $env:COMPUTERNAME
        $applicationEnvironment = $(Get-ApplicationsJson | Where-Object { $_.ApplicationCode -eq $Application })
        $environmentObj = $applicationEnvironment.Environments | Where-Object { $_.EnvironmentCode -eq $Environment }
        $environmentMetadataList = Get-EnvironmentInfo -Application $applicationEnvironment.ApplicationCode -Environment $environmentObj.EnvironmentCode

        $applicationMetadataList = Get-ApplicationInfo -Application $applicationEnvironment.ApplicationCode
        

        foreach ($path in $environmentObj.Paths ) {
            $applicationMetadataList = Get-ApplicationInfo -Application $applicationEnvironment.ApplicationCode       
            # Use override path if provided, otherwise use the default path from configuration
            $destRunPath = $OverrideRunPath ? $OverrideRunPath : $path.Path
            if ($null -ne $environmentMetadataList) {
                $cobolEnvironmentVariables = Get-CobolEnvironmentVariables -Application $applicationEnvironment.ApplicationCode -Environment $environmentObj.EnvironmentCode -Version $Version -Architecture $Architecture -ForceServer $true

                if ( $OnlyReturnMetadata) {
                    $lnkPath = Join-Path $(Get-SoftwarePath) "\Config\Cobol\ShortcutInfo"
                    $overridePath = Join-Path $(Get-SoftwarePath) "\Config\Cobol\EnvironmentScripts"
                    $catalogPath = Join-Path $(Get-SoftwarePath) "\Config\Db2\ClientConfig"
                    if (-not (Test-Path $overridePath -PathType Container)) {
                        New-Item -Path $overridePath -ItemType Directory | Out-Null
                    }
                    if (-not (Test-Path $catalogPath -PathType Container)) {
                        New-Item -Path $catalogPath -ItemType Directory | Out-Null
                    }
    
                    $machineEnvironmentFile = Set-CommonCobolEnvironmentVariablesAsConfigFile -Application $applicationEnvironment.ApplicationCode -Environment $environmentObj.EnvironmentCode -Version $Version -Architecture $Architecture -EnvironmentSource "Machine" -EnvironmentVariables $cobolEnvironmentVariables -OverridePath $overridePath
                    $userEnvironmentFile = Set-CommonCobolEnvironmentVariablesAsConfigFile -Application $applicationEnvironment.ApplicationCode -Environment $environmentObj.EnvironmentCode -Version $Version -Architecture $Architecture -EnvironmentSource "User" -EnvironmentVariables $cobolEnvironmentVariables -OverridePath $overridePath
    
                }
                else {
                    $lnkPath = Join-Path $EnvironmentPath "LNK"
                    Remove-Item -Path $lnkPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            
                if (-not (Test-Path $lnkPath -PathType Container)) {
                    New-Item -Path $lnkPath -ItemType Directory
                }
                $shortCutList = $applicationMetadataList.ShortCutList
                if ($null -ne $shortCutList -and $null -ne $cobolEnvironmentVariables) {
                    foreach ($shortcut in $shortCutList) {
                        $programName = $shortcut.ProgramName
                        switch ($programName) {
                            "RUN_EXE" {
                                $programPath = $cobolEnvironmentVariables.Environment.RUN_EXE
                            }
                            "RUNW_EXE" {
                                $programPath = $cobolEnvironmentVariables.Environment.RUNW_EXE
                            }
                            "COBOL_EXE" {
                                $programPath = $cobolEnvironmentVariables.Environment.COBOL_EXE
                            }
                            "DS_EXE" {
                                $programPath = $cobolEnvironmentVariables.Environment.DSWIN_EXE
                            }
                            Default {
                                $programPath = $programName
                                # $programPath = $programPath.Replace("?", $argument)
                            }
                        }
                    
                        $icon = $shortcut.Icon
                        if (-not (Test-Path $icon)) {
                            $tempIcon = Join-Path $(Get-ConfigFilesResourcesPath) "dedge.ico"
                            if (Test-Path $tempIcon) {
                                Add-FolderForFileIfNotExists -FileName $icon
                                Copy-Item -Path $tempIcon -Destination $icon -Force -ErrorAction SilentlyContinue | Out-Null
                            }
                        }

                        $cobsysPath = $cobolEnvironmentVariables.Environment.COBSYSPATH
                        $databaseCatalogName = Get-DatabaseCatalogName -Application $Application -Environment $Environment
                        $argument = $shortcut.Argument + " " + $databaseCatalogName + " " + $shortcut.AdditionalArgs
                        $argument = $argument.Trim()

                    
                        $shortCutName = $($($applicationMetadataList.Title + " " + $shortcut.AdditionalDescription + " " + "($($environmentMetadataList.Description))").Trim()).Replace("  ", " ")
                        # save shortcut to $cobsysPath using icon program and argument
                        if ($OnlyReturnMetadata) {
                            $folderName = $($applicationMetadataList.Title + " " + $environmentMetadataList.Description)
                            $shortCutFolderPath = Join-Path $lnkPath $folderName
                        }
                        else {
                            $shortCutFolderPath = Join-Path $cobsysPath "LNK"
                        }
                        if (-not (Test-Path $shortCutFolderPath)) {
                            New-Item -Path $shortCutFolderPath -ItemType Directory
                        }

                        $shortcutPath = Join-Path $shortCutFolderPath ($shortCutName + ".lnk")
                    
                        # Create WScript.Shell COM object to handle shortcut creation
                        if ($OnlyReturnMetadata) {
                            $results += [PSCustomObject]@{
                                Foldername             = $folderName
                                Application            = $application
                                Environment            = $environment
                                ShortCutName           = $shortCutName
                                DatabaseCatalogName    = $databaseCatalogName
                                Arguments              = $argument
                                ShortcutPath           = $shortcutPath
                                CatalogFile            = Join-Path $catalogPath ("cat_db2_" + $($databaseCatalogName.ToLower()) + "_kerberos_2.0.bat")
                                MachineEnvironmentFile = $machineEnvironmentFile
                                UserEnvironmentFile    = $userEnvironmentFile
                                OverrideRunPath        = $OverrideRunPath
                                OverrideIntPath        = $OverrideIntPath
                            }
                        }
                        $shell = New-Object -ComObject WScript.Shell
                        $shortcut = $shell.CreateShortcut($shortcutPath)
                        $shortcut.TargetPath = $programPath
                        $shortcut.Arguments = $argument
                        $shortcut.WorkingDirectory = $FromRunPath

                        if ($icon -and (Test-Path $icon)) {
                            # Set the icon for the shortcut
                            # The format is "path_to_icon_file,icon_index"
                            # Using index 0 to get the first icon from the file
                            $shortcut.IconLocation = "$icon,0"
                            Write-LogMessage "Setting icon to $icon" -Level INFO
                        }
                        else {
                            # If icon path is invalid or not provided, use the target executable's icon
                            Write-LogMessage "Icon path '$icon' not found or not specified. Using default icon." -Level INFO
                        }
                        $shortcut.Save()
                        # Release COM object to prevent memory leaks
                        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
                    
                        Write-LogMessage "Shortcut saved to $shortcutPath with icon $(if($icon -and (Test-Path $icon)){"'$icon'"} else {"(default)"})" -Level INFO                                       
                    }
                }
            }
       
    
        }
        if ($OnlyReturnMetadata) {
            $results = $results | Sort-Object -Property ShortCutName -Unique | ForEach-Object { [PSCustomObject]$_ }
            return $results
        }
    }
    catch {
        Write-LogMessage "Error creating menu items and shortcuts" -Level ERROR -Exception $_
        throw
    }
}

function Get-CobolProgramDetails {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProgramName
    )

    # Clean program name
    if ($ProgramName.Contains(".")) {
        $cleanProgramName = $ProgramName.Split(".")[0].ToUpper()
    }
    else {
        $cleanProgramName = $ProgramName.ToUpper()
    }

    # Determine architecture
    $architecture = if ($cleanProgramName.Substring(2, 1).ToLower() -eq "b") {
        "x64"
    }
    else {
        "x86" 
    }

    return @{
        ProgramName  = $cleanProgramName
        Architecture = $architecture
    }
}

function Start-CobolApplication {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Application,
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$CobolProgramName,
        [Parameter(Mandatory = $false)]
        [string]$DatabaseCatalogName
    )
    # Handle Cobol program details
    
    $cobolProgramDetails = Get-CobolProgramDetails -ProgramName $CobolProgramName
    $CobolProgramName = $cobolProgramDetails.ProgramName
    Set-CobolEnvironmentVariables -Application $Application -Environment $Environment -Version $Version -Architecture $cobolProgramDetails.Architecture
    $databaseCatalogName = Get-DatabaseCatalogName -Application $Application -Environment $Environment
       
    # build cmd to start Cobol program
    $cmd = $suitableExecutablePath.Path + " " + $CobolProgramName + " " + $databaseCatalogName

    Write-LogMessage "Starting Cobol program using command: $cmd" -Level INFO

    # Start Cobol program
    Start-Process $cmd

}



function Update-CobolEnvironments {

    $serverInfo = Get-ComputerMetaData -Name $env:COMPUTERNAME

    $command = "$env:OptPath\DedgePshApps\Add-NetworkDrives\Add-NetworkDrives.bat"
    cmd.exe /c $command

    foreach ($version in @("Mf", "Vc")) {
        $applications = @($serverInfo.Applications)
        if ($serverInfo.Applications -is [string]) {
            $applications = @($serverInfo.Applications)
        }

        foreach ($application in $applications) {

            $environments = @($serverInfo.Environments)
            if ($serverInfo.Environments -is [string]) {
                $environments = @($serverInfo.Environments)
            }
            $applicationInfo = Get-ApplicationInfo -Application $application
            
            foreach ($environment in $environments) {

                $environmentInfo = Get-EnvironmentInfo -Application $application -Environment $environment
                
                $cobolEnvironmentVariables = Get-CobolEnvironmentVariables -Application $application -Environment $environment -Version $version -Architecture "Any"
                Write-LogMessage "Checking if we are able to update environment $environment for application $application with version $version" -Level INFO -ForegroundColor Green
                if ($null -eq $environmentInfo) {
                    Write-LogMessage "Environment $environment not found for application $application is not configured to be updated. Skipping..." -Level WARN
                    continue
                }
                if ($null -eq $cobolEnvironmentVariables) {
                    Write-LogMessage "Cobol environment not possible to be set due to missing runtime environment" -Level WARN
                    continue
                }
                $paths = $environmentInfo.Paths | Where-Object { $_.PathType -eq $version }
    


                $fromRunPath = $paths.FromRunPath
                $fromBndPath = Join-Path $fromRunPath "bnd"
                $fromCblSrcPath = $fromRunPath 
                $fromCblCpyPath = $paths.FromCblCpyPath
                $fromSqlPath = $paths.FromSqlPath

                if ($fromRunPath -ne "") {
                    $versionPath = Get-CobSysPath -Version $version
                    if (-not (Test-Path $versionPath -PathType Container)) {
                        Add-Folder -Path $versionPath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                    }

                    $versionGlbPath = Get-CobSysPath -Version $version -Subfolder "GLB"
                    if (-not (Test-Path $versionGlbPath -PathType Container)) {
                        Add-Folder -Path $versionGlbPath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                    }
                    $versionGlbPath = Get-CobSysPath -Version $version -Subfolder "GLB"
                    Copy-Item -Path "$(Get-ConfigFilesResourcesPath)\*" -Destination $versionGlbPath -Force

                    $applicationPath = Get-CobSysPath -Version $version -Subfolder $application
                    if (-not (Test-Path $applicationPath -PathType Container)) {
                        Add-Folder -Path $applicationPath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                    }
        
                    $environmentPath = Join-Path $applicationPath $environment
                    if (-not (Test-Path $environmentPath -PathType Container)) {
                        Add-Folder -Path $environmentPath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                    }

                    $destRunPath = Join-Path $environmentPath "INT"
                    if (-not (Test-Path $destRunPath -PathType Container)) {
                        Add-Folder -Path $destRunPath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                    }

                    $destSrcPath = Join-Path $environmentPath "SRC" "CBL"
                    if (-not (Test-Path $destSrcPath -PathType Container)) {
                        Add-Folder -Path $destSrcPath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                    }
            
                    $destCpyPath = Join-Path $environmentPath "SRC" "CBL" "CPY"
                    if (-not (Test-Path $destCpyPath -PathType Container)) {
                        Add-Folder -Path $destCpyPath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                    }
                
                    $destLnkPath = Join-Path $environmentPath "LNK"
                    if (-not (Test-Path $destLnkPath -PathType Container)) {
                        Add-Folder -Path $destLnkPath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                    }
                
                    $destSqlPath = Join-Path $environmentPath "SRC" "SQL"
                    if (-not (Test-Path $destSqlPath -PathType Container)) {
                        Add-Folder -Path $destSqlPath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                    }

                    $destCfgPath = Join-Path $environmentPath "CFG"
                    if (-not (Test-Path $destCfgPath -PathType Container)) {
                        Add-Folder -Path $destCfgPath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                    }
              
                    $destBndPath = Join-Path $destRunPath "BND"
                    if (-not (Test-Path $destBndPath -PathType Container)) {
                        Add-Folder -Path $destBndPath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                    }

                    # Robocopy parameters (see https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy):
                    # /XO    : eXclude Older - skip files that exist in dest and are the same date or newer
                    # /NJH   : No Job Header
                    # /NJS   : No Job Summary
                    # /NDL   : No Directory List
                    # /NC    : No Class - don't log file classes
                    # /NS    : No Size - don't log file sizes
                    $skipCopy = $true
                    if (-not $skipCopy) {
                        robocopy $fromRunPath $destRunPath "*.INT" "*.GS" "*.EXE" "*.DLL" "*.REX" "*.BAT" "*.CMD" "*.BMP" "*.ICO" /XO /NJH /NJS /NDL /NC /NS
                        robocopy $fromBndPath $destBndPath "*.BND" /XO /NJH /NJS /NDL /NC /NS 

                        robocopy $fromCblSrcPath $destCpyPath "*.CPY" "*.CPX" "*.CPB" "*.DCL" "*.ICO" /XO /NJH /NJS /NDL /NC /NS

                        robocopy $fromCblCpyPath $destCpyPath "*.CPY" "*.CPX" "*.CPB" "*.DCL" "*.ICO" /XO /NJH /NJS /NDL /NC /NS

                        robocopy $fromCblSrcPath $destSrcPath "*.CBL" "*.GS" "*.IMP" /XO /NJH /NJS /NDL /NC /NS

                        if (Test-Path $fromSqlPath -PathType Container) {   
                            robocopy $fromSqlPath $destSqlPath "*.SQL" /XO /NJH /NJS /NDL /NC /NS
                        }
                    }

                    Save-CobolEnvironmentVariablesAsConfigFile -Application $application -Environment $environment -Version $version -Architecture "Any" -EnvironmentSource "Machine"
                    Save-CobolEnvironmentVariablesAsConfigFile -Application $application -Environment $environment -Version $version -Architecture "Any" -EnvironmentSource "User"

                    New-MenuItemsAndShortcuts -Application $application -Environment $environment -Version $version -Architecture "Any" -EnvironmentPath $environmentPath -DestRunPath $destRunPath
               
                    if ($serverInfo.Type.Contains("Server") -or $env:USERNAME -eq "FKGEISTA") {
                        $additionalAdmins = @($("$env:USERDOMAIN\$env:USERNAME"), "DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere")    

                        If ($application -eq "FKM") {
                            $shareName = $("COB" + $environment).ToUpper()
                            Remove-SharedFolder -ShareName $shareName
                            $cobSharePath = "$env:OptPath\Env\$shareName"
                            Add-Folder -Path $cobSharePath  -AdditionalAdmins @("DEDGE\ACL_ERPUTV_Utvikling_Full", "DEDGE\ACL_Dedge_Servere_Utviklere") -EveryonePermission "ReadAndExecute"
                            Add-SharedFolder -Path $cobSharePath -ShareName $shareName -EveryonePermission "ReadAndExecute" -Description "$($applicationInfo.Title) $($environmentInfo.Description ) applikasjon rot katalog" -AdditionalAdmins $additionalAdmins
                        }


                        $shareName = $("$application" + $environment).ToLower()
                        Remove-SharedFolder -ShareName $shareName
                        Add-SharedFolder -Path $destCfgPath -ShareName $shareName -EveryonePermission "ReadAndExecute" -Description "$($applicationInfo.Title) $($environmentInfo.Description ) applikasjon rot katalog" -AdditionalAdmins $additionalAdmins
                        
                        $shareName = $("$application" + $environment + "_config").ToLower()
                        Remove-SharedFolder -ShareName $shareName
                        # Add-SharedFolder -Path $destCfgPath -ShareName $shareName -EveryonePermission "ReadAndExecute" -Description "$($applicationInfo.Title) $($environmentInfo.Description) konfigurasjonsfiler" -AdditionalAdmins $additionalAdmins

                        $shareName = $("$application" + $environment + "_shortcuts").ToLower()
                        Remove-SharedFolder -ShareName $shareName
                        # Add-SharedFolder -Path $destLnkPath -ShareName $shareName -EveryonePermission "ReadAndExecute" -Description "$($applicationInfo.Title) $($environmentInfo.Description) applikasjons-snarveier " -AdditionalAdmins $additionalAdmins         

                        $shareName = $("$application" + $environment + "_COBRUN").ToLower()
                        Remove-SharedFolder -ShareName $shareName
                        # Add-SharedFolder -Path $destRunPath -ShareName $shareName -EveryonePermission "ReadAndExecute" -Description "$($applicationInfo.Title) $($environmentInfo.Description) Cobol objekter,Rexx programer og batchfiler" -AdditionalAdmins $additionalAdmins

                        $shareName = $("$application" + $environment + "_COBSRC").ToLower()
                        Remove-SharedFolder -ShareName $shareName
                        # Add-SharedFolder -Path $destSrcPath -ShareName $shareName -EveryonePermission "ReadAndExecute" -Description "$($applicationInfo.Title) $($environmentInfo.Description) Cobol kildekodefiler, Rexx programer og batchfiler" -AdditionalAdmins $additionalAdmins

                        $shareName = $("$application" + $environment + "_SQLSRC").ToLower()
                        Remove-SharedFolder -ShareName $shareName
                        # Add-SharedFolder -Path $destSqlPath -ShareName $shareName -EveryonePermission "ReadAndExecute" -Description "$($applicationInfo.Title) $($environmentInfo.Description) SQL kildekodefiler" -AdditionalAdmins $additionalAdmins                        


                        # Bind the program to the environment
                        # rexx dirbind n:\cobtst\bnd\<programnavn>.bnd BASISTST
                        & DB2CMD.EXE -c "$($environmentInfo.RunCatalogFile)"
                        if ($LASTEXITCODE -ne 0) {
                            Write-LogMessage "Error running catalog file $($environmentInfo.RunCatalogFile)" -Level ERROR
                            continue
                        }
                        Write-LogMessage "Run catalog file $($environmentInfo.RunCatalogFile)" -Level INFO
                        
                        $databaseCatalogName = Get-DatabaseCatalogName -Application $application -Environment $environment
                        Set-Location $destRunPath
                        $command = "dirbind $destBndPath\*.bnd $databaseCatalogName"

                        #rexx dirbind n:\cobtst\bnd\bkhbaid.bnd basistst
                        #K:\fkavd\NT>rexx dirbind n:\cobtst\bnd\bkhbaid.bnd basistst


                        & DB2CMD.EXE -c "DIRBIND $destBndPath $($bndFile.Name) $databaseCatalogName"
                        Write-LogMessage "Bound $($bndFile.Name) to $databaseCatalogName" -Level INFO

                        # foreach ($bndFile in Get-ChildItem -Path $destBndPath -Filter "*.bnd") {
                        #     & DB2CMD.EXE -c "DIRBIND $destBndPath $($bndFile.Name) $databaseCatalogName"
                        #     Write-LogMessage "Bound $($bndFile.Name) to $databaseCatalogName" -Level INFO
                        # }

                    }

                }
            }
        }
    }
}

function Get-AllShortcutInfo {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Version = "Mf",
        [Parameter(Mandatory = $false)]
        [string]$OverrideIntPath = $null
    )

    $environmentMetadataList = Get-EnvironmentInfo -Application "*" -Environment "*"
    $environmentMetadataList = $environmentMetadataList | Where-Object { $_.ApplicationCode -eq "INL" -or $_.ApplicationCode -eq "FKM" }

    $outputFolder = Join-Path $(Get-SoftwarePath) "\Config\Cobol\ShortcutInfo"
    Remove-Item -Path $outputFolder -Recurse -Force | Out-Null
    New-Item -Path $outputFolder -ItemType Directory | Out-Null

    $jsonfile = Join-Path $outputFolder "CobolShortcutInfo.json"

    $jsonContent = @()
    #xXXXXXX
    foreach ($applicationMetadata in $environmentMetadataList) {
        foreach ($environmentMetadata in $applicationMetadata.Environments) {
            Write-Host "Processing $($applicationMetadata.ApplicationCode) " -ForegroundColor Green -NoNewline
            Write-Host " - $($environmentMetadata.EnvironmentCode)" -ForegroundColor Yellow
            $environmentPath = Join-Path $(Get-CobSysPath -Version $Version) $($applicationMetadata.ApplicationCode) $($environmentMetadata.EnvironmentCode)    
            try {
                $results = New-MenuItemsAndShortcuts -Application $applicationMetadata.ApplicationCode -Environment $environmentMetadata.EnvironmentCode -Version $Version -Architecture "Any" -EnvironmentPath $environmentPath -OnlyReturnMetadata $true -OverrideIntPath $OverrideIntPath

                $jsonContent += $results
            }
            catch {
                Write-LogMessage "Error getting shortcut info for $($applicationMetadata.ApplicationCode) $($environmentMetadata.EnvironmentCode) $Version" -Level ERROR -Exception $_
            }
        }
    }
    $jsonContent = $jsonContent | Sort-Object -Property Application, ShortCutName, Environment -Unique | ForEach-Object { [PSCustomObject]$_ }
    Set-Content -Path $jsonfile -Value ($jsonContent | ConvertTo-Json -Depth 10)
    Write-LogMessage "Shortcut info saved to $jsonfile" -Level INFO
}
function Copy-CobolFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $sourcePath = Join-Path $(Get-SoftwarePath) "\Config\Cobol\ShortcutInfo"
    $destinationPath = Join-Path $(Get-SoftwarePath) "\Config\Cobol\ShortcutInfo"

    Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse
}


<#
.SYNOPSIS
    Provides program return code monitoring and logging functionality.

.DESCRIPTION
    This module monitors program execution by checking return code files (.rc) and logging
    the results. It integrates with the Logger system and WKMonitor for comprehensive
    program execution tracking. Designed for monitoring batch jobs and automated processes
    in the Dedge environment.

.EXAMPLE
    CheckLog -program "BatchJob01"
    # Checks the return code for BatchJob01 and logs any errors

.EXAMPLE
    CheckLog -program "DataProcessor"
    # Monitors DataProcessor execution and creates monitor files for non-zero return codes
#>

<#
.SYNOPSIS
    Checks a program's return code file and logs the results.

.DESCRIPTION
    Examines a program's .rc file in a specified network path to check its return code.
    If the return code is not "0000", or if the file is not found, logs an error message
    to both the Logger system and a monitor file. For successful executions (code "0000"),
    only logs to the Logger system.

.PARAMETER program
    The name of the program to check (without file extension).
    The function will look for a corresponding .rc file.

.EXAMPLE
    CheckLog -program "MyProgram"
    # Checks MyProgram.rc and logs any non-zero return codes

.NOTES
    - Return code files are expected to be in the format: XXXX[message]
      where XXXX is the 4-digit return code and [message] is optional text
    - Code "0000" indicates success
    - Code "0016" is used when the RC file is not found
    - Monitor files are created with timestamp and computer name
#>

function CheckLog {
    param (
        [Parameter(Mandatory = $true)]
        [string] $Program
    )

    $returnCodePath = $global:FkEnvironmentSettings.CobolObjectPath
    $rcfile = $returnCodePath + $Program + ".rc"
    if (Test-Path $rcfile) {
        $rccontent = Get-Content -Path $rcfile
        $kode = $rccontent.Substring(0, 4)
        if ($kode -ne "0000") {
            $melding = $rccontent.Substring(4, $rccontent.Length - 4)                
            Write-LogMessage "Program $Program finished with return code $kode and message: $melding" -Level ERROR
            Send-FkAlert -Program $Program -Code $kode -Message $melding
        }
        else {
            Write-LogMessage "Program $Program completed successfully: $rccontent" -Level INFO
        }   
    }
    else {
        $melding = "RC-file for $Program ikke funnet!"
        $kode = "0016"
    
        Write-LogMessage "RC-file for program $Program not found in path $returnCodePath" -Level ERROR 
        Send-FkAlert -Program $Program -Code $kode -Message $melding
    }
}


function SetLocationPshRootPath {
    Set-Location -Path $global:FkEnvironmentSettings.DedgePshAppsPath
}

<#
.SYNOPSIS
    Gets the return code from a program's RC file.

.DESCRIPTION
    Reads a program's return code file and returns the first four characters,
    which represent the return code. Returns an error message if the file
    doesn't exist.

.PARAMETER program
    The name of the program to check (without file extension).

.EXAMPLE
    $rc = Get-RC -program "MyProgram"
    # Returns the return code from MyProgram.rc

.NOTES
    Returns "9999" with an error message if the RC file is not found.
#>
function Get-CobolProgramReturnCode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Program
    )
    $returnCodePath = $global:FkEnvironmentSettings.CobolObjectPath
    $prg = $returnCodePath + $Program + ".rc"
    if (Test-Path -Path $prg) {
        $rccontent = Get-Content $prg
        Write-LogMessage "Retrieved return code for program $Program from file $prg" -Level DEBUG
        return $rccontent.substring(0, 4)
    }
    else {
        Write-LogMessage "RC-file for program $Program not found at path: $prg" -Level ERROR
        return "9999 RC-fil for $prg finnes ikke!"
    }
}
function Get-RC {
    param(
        $Program
    )
    return Get-CobolProgramReturnCode -Program $Program
}
<#
.SYNOPSIS
    Tests if a program's return code indicates success.

.DESCRIPTION
    Checks if a program's return code equals "0000", indicating successful execution.
    Returns true for success, false otherwise.

.PARAMETER program
    The name of the program to check (without file extension).

.EXAMPLE
    $success = Test-RC -Program "MyProgram"
    # Returns $true if MyProgram.rc contains "0000"
#>
function Test-CobolProgramReturnCode {
    param(
        $Program
    )

    $rc = Get-CobolProgramReturnCode -Program $Program
    if ($rc -eq "0000") {
        return $true
    }
    else {
        return $false
    }
}
function Test-RC {
    param(
        $Program
    )
    return Test-CobolProgramReturnCode -Program $Program
}
<#
.SYNOPSIS
    Runs a COBOL program with specified parameters and monitors its execution.

.DESCRIPTION
    Executes a COBOL program using the Micro Focus run.exe, with specified database
    and parameters. Logs the execution, captures output in a transcript file, and
    checks the return code for success.

.PARAMETER Programname
    The name of the COBOL program to run.

.PARAMETER Database
    The database to use. Must be one of: 'FKAVDNT', 'BASISPRO', 'BASISTST', 'BASISRAP'.

.PARAMETER CBLParams
    Additional parameters to pass to the COBOL program.

.EXAMPLE
    CBLRun -Programname "MYPROG" -Database "BASISPRO" -CBLParams @("param1", "param2")
    # Runs MYPROG with specified database and parameters

.NOTES
    - Creates a transcript file with .mfout extension
    - Checks return code after execution
    - Returns $true if execution was successful, $false otherwise
#>
function Start-CobolProgram {
    param(
        [Parameter(Mandatory)][string] $ProgramName,
        [Parameter(Mandatory)]
        [ValidateSet('FKAVDNT', 'BASISPRO', 'BASISTST', 'BASISRAP', 'BASISKAT', 'BASISFUT', 'BASISMIG', 'BASISVFT', 'BASISVFK', 'BASISPER', 'BASISSIT', 'FKKONTO', 'FKNTOTST', 'FKNTOTDEV')]
        [string] $Database,
        [string[]] $CblParams
    )    
    if ($Database -ne $global:FkEnvironmentSettings.Database) {
        Get-GlobalEnvironmentSettings -OverrideDatabase $Database
    }
    $rcPath = $global:FkEnvironmentSettings.CobolObjectPath
    $programFile = $rcPath + $ProgramName
    $programArgs = $global:FkEnvironmentSettings.CobolRuntimeExecutable + ' ' + $programFile + ' ' + $Database + ' ' + $CblParams + '"'
    $CblRunExecutionOk = $false
    
    $transcriptFile = $rcPath + $ProgramName + ".mfout" 
    Start-Transcript $transcriptFile -Append
    $msg = "Starting COBOL program: " + $programArgs
    # Updated to use Write-LogMessage instead of Logger
    Write-LogMessage $msg -Level INFO
    # Old code: Logger -message $msg
    
    Set-Location $global:FkEnvironmentSettings.CobolObjectPath
    try {
        & run $ProgramName $Database $CblParams    
    }
    catch {
        & $global:FkEnvironmentSettings.CobolRuntimeExecutable $ProgramName $Database $CblParams
    }
    
    # Set-Location $env:OptPath\DedgePshApps\CBLRun
    Stop-Transcript
    Set-Location $global:FkEnvironmentSettings.CobolObjectPath
    
    if (Test-RC -program $ProgramName) {
        SetLocationPshRootPath
        CheckLog -program $ProgramName
        $CblRunExecutionOk = $True
    }
    else {
        $msg = $ProgramName + ".RC <> 0000. Check RC-file."
        # Updated to use Write-LogMessage instead of Logger
        Write-LogMessage $msg -Level ERROR
        # Old code: Logger -message $msg
        if (-not [string]::IsNullOrEmpty($global:FkEnvironmentSettings.Database) -and $global:FkEnvironmentSettings.Database -ne $Database) {
            Get-GlobalEnvironmentSettings -OverrideDatabase $Database
        }

        SetLocationPshRootPath
        CheckLog -program $ProgramName
        $CblRunExecutionOk = $False
    }
    return $CblRunExecutionOk
    
}

function CBLRun {
    param(
        [Parameter(Mandatory)][string] $ProgramName,
        [Parameter(Mandatory)]
        [string] $Database,
        [string[]] $CblParams
    )
    return Start-CobolProgram -ProgramName $ProgramName -Database $Database -CblParams $CblParams
}

Export-ModuleMember -Function *