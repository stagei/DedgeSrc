#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds the SqlMmdConverter NuGet package with bundled Python and Node.js runtimes.

.DESCRIPTION
    This script downloads portable Python and Node.js runtimes, installs required dependencies
    (SQLGlot and little-mermaid-2-the-sql), and packages everything into a platform-specific NuGet package.

.PARAMETER RuntimeId
    The runtime identifier to build for (win-x64, linux-x64, osx-x64)

.PARAMETER SkipDownload
    Skip downloading runtimes if they already exist

.PARAMETER Configuration
    Build configuration (Debug or Release)

.EXAMPLE
    .\build-package.ps1 -RuntimeId win-x64
    
.EXAMPLE
    .\build-package.ps1 -RuntimeId linux-x64 -Configuration Release
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('win-x64', 'linux-x64', 'osx-x64')]
    [string]$RuntimeId = 'win-x64',
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipDownload,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

# Color output functions
function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "    ✓ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "    ⚠ $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "    ✗ $Message" -ForegroundColor Red
}

# Configuration
$PythonVersion = "3.11.7"
$NodeVersion = "18.19.0"
$RuntimeDir = Join-Path $PSScriptRoot "src\SqlMmdConverter\runtimes\$($RuntimeId)"

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║           SqlMmdConverter Package Builder                    ║
║           Target: $($RuntimeId.PadRight(42))║
║           Configuration: $($Configuration.PadRight(37))║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Step 1: Create runtime directories
Write-Step "Creating runtime directories"
$pythonDir = Join-Path $RuntimeDir "python"
$nodeDir = Join-Path $RuntimeDir "node"
$scriptsDir = Join-Path $RuntimeDir "scripts"

New-Item -ItemType Directory -Force -Path $pythonDir | Out-Null
New-Item -ItemType Directory -Force -Path $nodeDir | Out-Null
New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
Write-Success "Directories created"

if (-not $SkipDownload) {
    # Step 2: Download and extract Python embeddable
    if ($RuntimeId -eq 'win-x64') {
        Write-Step "Downloading Python $($PythonVersion) embeddable for Windows"
        $pythonUrl = "https://www.python.org/ftp/python/$($PythonVersion)/python-$($PythonVersion)-embed-amd64.zip"
        $pythonZip = Join-Path $env:TEMP "python-embed.zip"
        
        Write-Info "URL: $($pythonUrl)"
        try {
            Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonZip -UseBasicParsing
            Write-Success "Python downloaded ($([math]::Round((Get-Item $pythonZip).Length / 1MB, 2)) MB)"
            
            Write-Info "Extracting Python runtime..."
            Expand-Archive -Path $pythonZip -DestinationPath $pythonDir -Force
            Remove-Item $pythonZip -Force
            Write-Success "Python extracted to $($pythonDir)"
        }
        catch {
            Write-Error "Failed to download/extract Python: $($_.Exception.Message)"
            throw
        }
        
        # Enable pip in embeddable Python
        Write-Info "Configuring Python for pip support..."
        $pthFile = Join-Path $pythonDir "python311._pth"
        if (Test-Path $pthFile) {
            $content = Get-Content $pthFile
            $content = $content -replace '#import site', 'import site'
            Set-Content -Path $pthFile -Value $content
            Write-Success "Python configured for pip"
        }
        
        # Download get-pip.py
        Write-Info "Installing pip..."
        $getPipUrl = "https://bootstrap.pypa.io/get-pip.py"
        $getPipPath = Join-Path $pythonDir "get-pip.py"
        Invoke-WebRequest -Uri $getPipUrl -OutFile $getPipPath -UseBasicParsing
        & "$pythonDir\python.exe" $getPipPath
        Write-Success "pip installed"
        
        # Install SQLGlot
        Write-Info "Installing SQLGlot..."
        & "$pythonDir\python.exe" -m pip install sqlglot --target "$pythonDir\Lib\site-packages"
        Write-Success "SQLGlot installed"
    }
    else {
        Write-Warning "Python bundling for $($RuntimeId) not yet implemented. Please install manually."
    }

    # Step 3: Download and extract Node.js portable
    if ($RuntimeId -eq 'win-x64') {
        Write-Step "Downloading Node.js $($NodeVersion) for Windows"
        $nodeUrl = "https://nodejs.org/dist/v$($NodeVersion)/node-v$($NodeVersion)-win-x64.zip"
        $nodeZip = Join-Path $env:TEMP "node-portable.zip"
        
        Write-Info "URL: $($nodeUrl)"
        try {
            Invoke-WebRequest -Uri $nodeUrl -OutFile $nodeZip -UseBasicParsing
            Write-Success "Node.js downloaded ($([math]::Round((Get-Item $nodeZip).Length / 1MB, 2)) MB)"
            
            Write-Info "Extracting Node.js runtime..."
            $nodeTempDir = Join-Path $env:TEMP "node-temp"
            Expand-Archive -Path $nodeZip -DestinationPath $nodeTempDir -Force
            
            # Move files from extracted folder to target
            $extractedDir = Join-Path $nodeTempDir "node-v$($NodeVersion)-win-x64"
            Copy-Item -Path "$($extractedDir)\*" -Destination $nodeDir -Recurse -Force
            
            Remove-Item $nodeZip -Force
            Remove-Item $nodeTempDir -Recurse -Force
            Write-Success "Node.js extracted to $($nodeDir)"
        }
        catch {
            Write-Error "Failed to download/extract Node.js: $($_.Exception.Message)"
            throw
        }
        
        # Install little-mermaid-2-the-sql
        Write-Info "Installing little-mermaid-2-the-sql..."
        Push-Location $nodeDir
        try {
            & "$nodeDir\npm.cmd" install @funktechno/little-mermaid-2-the-sql
            Write-Success "little-mermaid-2-the-sql installed"
        }
        catch {
            Write-Error "Failed to install little-mermaid-2-the-sql: $($_.Exception.Message)"
            throw
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Warning "Node.js bundling for $($RuntimeId) not yet implemented. Please install manually."
    }
}
else {
    Write-Warning "Skipping runtime downloads (using existing)"
}

# Step 4: Copy scripts
Write-Step "Copying conversion scripts"
$sourceScriptsDir = Join-Path $PSScriptRoot "src\SqlMmdConverter\scripts"
if (Test-Path $sourceScriptsDir) {
    Copy-Item -Path "$($sourceScriptsDir)\*" -Destination $scriptsDir -Recurse -Force
    Write-Success "Scripts copied to $($scriptsDir)"
}

# Step 5: Build and pack
Write-Step "Building NuGet package"
Write-Info "Configuration: $($Configuration)"
Write-Info "Runtime: $($RuntimeId)"

try {
    # Create packages directory
    New-Item -ItemType Directory -Force -Path "packages" | Out-Null
    
    # First build
    dotnet build src\SqlMmdConverter\SqlMmdConverter.csproj -c $Configuration
    
    # Then pack
    dotnet pack src\SqlMmdConverter\SqlMmdConverter.csproj `
        -c $Configuration `
        -p:RuntimeIdentifier=$RuntimeId `
        -o packages `
        --no-build
    
    Write-Success "Package created successfully!"
    
    # Show package info
    $packageFiles = Get-ChildItem -Path "packages" -Filter "*.nupkg" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($packageFiles) {
        Write-Host "`n" -NoNewline
        Write-Host "📦 Package created:" -ForegroundColor Green
        Write-Host "    Name: $($packageFiles.Name)" -ForegroundColor White
        Write-Host "    Size: $([math]::Round($packageFiles.Length / 1MB, 2)) MB" -ForegroundColor White
        Write-Host "    Path: $($packageFiles.FullName)" -ForegroundColor White
    }
}
catch {
    Write-Error "Build/pack failed: $($_.Exception.Message)"
    throw
}

Write-Host "`n✨ Build complete!`n" -ForegroundColor Green

