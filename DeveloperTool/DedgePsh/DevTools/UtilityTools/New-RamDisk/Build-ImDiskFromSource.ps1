<###
.SYNOPSIS
    Clones and builds ImDisk from source for internal use.

.DESCRIPTION
    This script clones the ImDisk repository from GitHub, builds it from source,
    and installs it to a local directory. It supports building both the driver
    and command-line tools.

.PARAMETER SourcePath
    Path where ImDisk source will be cloned. Default: C:\opt\src\imdisk

.PARAMETER BuildPath
    Path where build output will be placed. Default: C:\opt\src\imdisk\build

.PARAMETER InstallPath
    Path where compiled binaries will be installed. Default: C:\opt\src\imdisk\install

.PARAMETER RepositoryUrl
    GitHub repository URL. Default: https://github.com/LTRData/ImDisk.git

.PARAMETER Branch
    Git branch or tag to checkout. Default: master

.PARAMETER Force
    Force re-clone and rebuild even if source already exists.

.PARAMETER BuildDriver
    Build the kernel driver (requires Windows Driver Kit). Default: $false

.PARAMETER BuildCli
    Build the command-line tools. Default: $true

.PARAMETER BuildGui
    Build the GUI applications (.NET). Default: $true

.PARAMETER SignBinaries
    Sign compiled binaries using DedgeSign after build. Default: $true

.EXAMPLE
    .\Build-ImDiskFromSource.ps1
    Clones and builds ImDisk from source

.EXAMPLE
    .\Build-ImDiskFromSource.ps1 -BuildDriver -Force
    Force rebuild including the kernel driver

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Requires: Git, Visual Studio Build Tools or Visual Studio, Windows Driver Kit (for driver)
    
    Security: Building from source allows code review for malicious code before compilation.
    Binaries are automatically signed using DedgeSign (Azure Trusted Signing) after build.
###>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SourcePath = "C:\opt\src\imdisk",

    [Parameter(Mandatory = $false)]
    [string]$BuildPath = "C:\opt\src\imdisk\build",

    [Parameter(Mandatory = $false)]
    [string]$InstallPath = "C:\opt\src\imdisk\install",

    [Parameter(Mandatory = $false)]
    [string]$RepositoryUrl = "https://github.com/LTRData/ImDisk.git",

    [Parameter(Mandatory = $false)]
    [string]$Branch = "master",

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$BuildDriver,

    [Parameter(Mandatory = $false)]
    [switch]$BuildCli = $true,

    [Parameter(Mandatory = $false)]
    [switch]$BuildGui = $true,

    [Parameter(Mandatory = $false)]
    [switch]$SignBinaries = $true
)

$ErrorActionPreference = 'Stop'

# Import GlobalFunctions for Write-LogMessage
Import-Module GlobalFunctions -Force

try {
    # Check if running as administrator (required for driver installation)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($BuildDriver -and -not $isAdmin) {
        Write-LogMessage "Building the driver requires administrator privileges. Please run PowerShell as Administrator." -Level ERROR
        throw "Administrator privileges required for driver build"
    }

    # Check for Git
    $gitPath = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitPath) {
        Write-LogMessage "Git is not installed. Please install Git for Windows." -Level ERROR
        throw "Git not found"
    }

    # Check for MSBuild
    $msbuildPath = $null
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere) {
        $vsPath = & $vsWhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
        if ($vsPath) {
            $msbuildPath = Join-Path $vsPath "MSBuild\Current\Bin\MSBuild.exe"
            if (-not (Test-Path $msbuildPath)) {
                # Try older VS versions
                $msbuildPath = Join-Path $vsPath "MSBuild\15.0\Bin\MSBuild.exe"
            }
        }
    }

    # Fallback to standalone MSBuild
    if (-not $msbuildPath -or -not (Test-Path $msbuildPath)) {
        $msbuildPath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
        if (-not (Test-Path $msbuildPath)) {
            $msbuildPath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe"
        }
    }

    if (-not $msbuildPath -or -not (Test-Path $msbuildPath)) {
        Write-LogMessage "MSBuild not found. Please install Visual Studio or Visual Studio Build Tools." -Level ERROR
        throw "MSBuild not found"
    }

    Write-LogMessage "Using MSBuild: $msbuildPath" -Level INFO

    # Create directories
    New-Item -Path $SourcePath -ItemType Directory -Force | Out-Null
    New-Item -Path $BuildPath -ItemType Directory -Force | Out-Null
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null

    # Clone or update repository
    $repoPath = Join-Path $SourcePath "ImDisk"
    if (Test-Path (Join-Path $repoPath ".git")) {
        if ($Force) {
            Write-LogMessage "Removing existing repository..." -Level INFO
            Remove-Item -Path $repoPath -Recurse -Force
        }
        else {
            Write-LogMessage "Repository exists, updating..." -Level INFO
            Push-Location $repoPath
            try {
                & git fetch origin
                & git checkout $Branch
                & git pull origin $Branch
            }
            finally {
                Pop-Location
            }
        }
    }

    if (-not (Test-Path (Join-Path $repoPath ".git"))) {
        Write-LogMessage "Cloning ImDisk repository from $RepositoryUrl..." -Level INFO
        & git clone -b $Branch $RepositoryUrl $repoPath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone repository"
        }
    }

    Write-LogMessage "Source code available at: $repoPath" -Level INFO

    # Build CLI tools
    if ($BuildCli) {
        Write-LogMessage "Building CLI tools..." -Level INFO
        
        $cliPath = Join-Path $repoPath "cli"
        if (Test-Path $cliPath) {
            $slnFiles = Get-ChildItem -Path $cliPath -Filter "*.sln" -Recurse | Select-Object -First 1
            if ($slnFiles) {
                $slnPath = $slnFiles.FullName
                Write-LogMessage "Building solution: $slnPath" -Level INFO
                
                $buildArgs = @(
                    $slnPath
                    "/p:Configuration=Release"
                    "/p:Platform=x64"
                    "/p:OutDir=$BuildPath\cli\"
                    "/t:Build"
                    "/m"
                )
                
                & $msbuildPath @buildArgs
                if ($LASTEXITCODE -ne 0) {
                    Write-LogMessage "CLI build failed" -Level WARN
                }
                else {
                    Write-LogMessage "CLI tools built successfully" -Level INFO
                    
                    # Copy imdisk.exe to install path
                    $imdiskExe = Get-ChildItem -Path "$BuildPath\cli" -Filter "imdisk.exe" -Recurse | Select-Object -First 1
                    if ($imdiskExe) {
                        $installBinPath = Join-Path $InstallPath "bin"
                        New-Item -Path $installBinPath -ItemType Directory -Force | Out-Null
                        $targetExe = Join-Path $installBinPath "imdisk.exe"
                        Copy-Item -Path $imdiskExe.FullName -Destination $targetExe -Force
                        Write-LogMessage "Copied imdisk.exe to: $installBinPath" -Level INFO
                        
                        # Sign the binary if requested
                        if ($SignBinaries) {
                            Write-LogMessage "Signing imdisk.exe..." -Level INFO
                            try {
                                Start-DedgeSignFile -FilePath $targetExe
                                Write-LogMessage "Successfully signed imdisk.exe" -Level INFO
                            }
                            catch {
                                Write-LogMessage "Failed to sign imdisk.exe: $($_.Exception.Message)" -Level WARN
                                Write-LogMessage "Binary is unsigned. You may want to sign it manually using Start-DedgeSignFile" -Level WARN
                            }
                        }
                    }
                }
            }
            else {
                Write-LogMessage "No solution file found in CLI directory" -Level WARN
            }
        }
    }

    # Build GUI applications
    if ($BuildGui) {
        Write-LogMessage "Building GUI applications..." -Level INFO
        
        $guiPaths = @(
            Join-Path $repoPath "cpl",
            Join-Path $repoPath "ImDiskNet"
        )
        
        foreach ($guiPath in $guiPaths) {
            if (Test-Path $guiPath) {
                $slnFiles = Get-ChildItem -Path $guiPath -Filter "*.sln" -Recurse | Select-Object -First 1
                if ($slnFiles) {
                    $slnPath = $slnFiles.FullName
                    Write-LogMessage "Building solution: $slnPath" -Level INFO
                    
                    $buildArgs = @(
                        $slnPath
                        "/p:Configuration=Release"
                        "/p:Platform=x64"
                        "/p:OutDir=$BuildPath\gui\"
                        "/t:Build"
                        "/m"
                    )
                    
                    & $msbuildPath @buildArgs
                    if ($LASTEXITCODE -ne 0) {
                        Write-LogMessage "GUI build failed for: $guiPath" -Level WARN
                    }
                    else {
                        Write-LogMessage "GUI application built successfully: $guiPath" -Level INFO
                    }
                }
            }
        }
    }

    # Build driver (if requested and WDK available)
    if ($BuildDriver) {
        Write-LogMessage "Building kernel driver..." -Level INFO
        
        # Check for Windows Driver Kit
        $wdkPath = "${env:ProgramFiles(x86)}\Windows Kits\10\build"
        if (-not (Test-Path $wdkPath)) {
            Write-LogMessage "Windows Driver Kit not found. Driver build skipped." -Level WARN
            Write-LogMessage "Install WDK from: https://learn.microsoft.com/en-us/windows-hardware/drivers/download-the-wdk" -Level INFO
        }
        else {
            $sysPath = Join-Path $repoPath "sys"
            if (Test-Path $sysPath) {
                # Driver build requires WDK and is more complex
                Write-LogMessage "Driver build requires manual configuration. See ImDisk documentation." -Level INFO
                Write-LogMessage "Driver source available at: $sysPath" -Level INFO
            }
        }
    }

    # Create installation script
    $installScript = @"
# ImDisk Local Installation
# Generated by Build-ImDiskFromSource.ps1

`$installPath = "$InstallPath"
`$binPath = Join-Path `$installPath "bin"

# Add to PATH for current session
`$env:Path += ";`$binPath"

# Add to user PATH permanently
`$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (`$userPath -notlike "*`$binPath*") {
    [Environment]::SetEnvironmentVariable("Path", "`$userPath;`$binPath", "User")
    Write-Host "Added `$binPath to user PATH"
}

Write-Host "ImDisk binaries available at: `$binPath"
Write-Host "Run: imdisk -l  (to verify installation)"
"@

    $installScriptPath = Join-Path $InstallPath "Install-LocalImDisk.ps1"
    Set-Content -Path $installScriptPath -Value $installScript -Force
    Write-LogMessage "Installation script created: $installScriptPath" -Level INFO

    # Sign any additional binaries if requested
    if ($SignBinaries) {
        Write-LogMessage "Signing additional binaries..." -Level INFO
        $binariesToSign = Get-ChildItem -Path $InstallPath -Filter "*.exe" -Recurse -File
        $binariesToSign += Get-ChildItem -Path $InstallPath -Filter "*.dll" -Recurse -File
        
        foreach ($binary in $binariesToSign) {
            try {
                Start-DedgeSignFile -FilePath $binary.FullName
                Write-LogMessage "Signed: $($binary.Name)" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to sign $($binary.Name): $($_.Exception.Message)" -Level WARN
            }
        }
    }

    Write-LogMessage "Build complete!" -Level INFO
    Write-LogMessage "  Source: $repoPath" -Level INFO
    Write-LogMessage "  Build: $BuildPath" -Level INFO
    Write-LogMessage "  Install: $InstallPath" -Level INFO
    if ($SignBinaries) {
        Write-LogMessage "  Binaries signed with DedgeSign" -Level INFO
    }
    Write-LogMessage "  Run: .\Install-LocalImDisk.ps1 (in install directory)" -Level INFO
}
catch {
    Write-LogMessage "Error building ImDisk from source: $($_.Exception.Message)" -Level ERROR -Exception $_
    throw
}
