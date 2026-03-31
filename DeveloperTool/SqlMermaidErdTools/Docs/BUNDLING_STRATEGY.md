# Bundling External Runtimes in NuGet Package

## Overview

SqlMermaidErdTools can bundle Python and Node.js runtimes directly in the NuGet package, making it completely self-contained with zero manual setup required by users. This document outlines the strategies, tools, and implementation details.

## ✅ Yes, It's Possible and Practical!

### Available Strategies

## Strategy 1: Embeddable/Portable Runtimes (Recommended)

### Python Embeddable Distribution

Python provides official "embeddable" packages - these are minimal, portable Python distributions perfect for bundling.

#### Download Links
- **Windows**: `https://www.python.org/ftp/python/3.11.7/python-3.11.7-embed-amd64.zip` (~10 MB)
- **Size**: 10-15 MB compressed, ~25 MB extracted
- **No Installation Required**: Just extract and run

#### Structure
```
runtimes/win-x64/python/
├── python.exe              # Portable Python interpreter
├── python311.dll
├── python311.zip           # Standard library
└── Lib/
    └── site-packages/
        └── sqlglot/        # Install SQLGlot here
```

#### Install SQLGlot into Embeddable Python
```powershell
# During build/package process
$pythonDir = "runtimes/win-x64/python"
& "$pythonDir/python.exe" -m pip install --target "$pythonDir/Lib/site-packages" sqlglot

# Or download wheel and extract manually
Invoke-WebRequest -Uri "https://files.pythonproject.org/packages/.../sqlglot-*.whl" -OutFile "sqlglot.whl"
Expand-Archive "sqlglot.whl" -DestinationPath "$pythonDir/Lib/site-packages"
```

### Node.js Portable Binary

Node.js provides standalone binaries that require no installation.

#### Download Links
- **Windows**: `https://nodejs.org/dist/v18.19.0/node-v18.19.0-win-x64.zip` (~30 MB)
- **Linux**: `https://nodejs.org/dist/v18.19.0/node-v18.19.0-linux-x64.tar.gz`
- **macOS**: `https://nodejs.org/dist/v18.19.0/node-v18.19.0-darwin-x64.tar.gz`
- **Size**: 30-40 MB compressed, ~70 MB extracted

#### Structure
```
runtimes/win-x64/node/
├── node.exe                # Portable Node.js
└── node_modules/
    └── @funktechno/
        └── little-mermaid-2-the-sql/
```

#### Install little-mermaid-2-the-sql
```powershell
# During build/package process
$nodeDir = "runtimes/win-x64/node"
$env:PATH = "$nodeDir;$env:PATH"
Set-Location $nodeDir
& "$nodeDir/node.exe" "$nodeDir/npm" install @funktechno/little-mermaid-2-the-sql
```

## Strategy 2: Single-File Executables (Smaller Package Size)

### PyInstaller for Python Scripts

Convert Python scripts to standalone executables.

#### Create Standalone Python Executable
```bash
# Install PyInstaller
pip install pyinstaller

# Create standalone executable
pyinstaller --onefile --name sqlglot_converter sql_to_mmd.py

# Result: dist/sqlglot_converter.exe (~15-20 MB)
```

#### Advantages
- ✅ Single executable file (no Python runtime needed)
- ✅ Smaller total size (~15-20 MB vs ~25 MB for full runtime)
- ✅ Faster process startup
- ✅ No Python path configuration needed

#### Disadvantages
- ⚠️ Need to rebuild when updating SQLGlot
- ⚠️ Less flexible for script modifications
- ⚠️ Windows Defender may flag unknown executables

### pkg for Node.js Scripts

Convert Node.js scripts to standalone executables.

#### Create Standalone Node.js Executable
```bash
# Install pkg globally
npm install -g pkg

# Create standalone executable
pkg --targets node18-win-x64 mmd_to_sql.js

# Result: mmd_to_sql.exe (~40-50 MB)
```

#### Package Configuration
```json
// package.json
{
  "name": "mmd-sql-converter",
  "bin": "mmd_to_sql.js",
  "pkg": {
    "assets": [
      "node_modules/@funktechno/little-mermaid-2-the-sql/**/*"
    ],
    "targets": [
      "node18-win-x64",
      "node18-linux-x64",
      "node18-macos-x64"
    ]
  }
}
```

## Strategy 3: Pre-compiled Native Binaries (Best Performance)

### Use .NET Native Interop

If we find or create C/C++ implementations of the parsers, we can use P/Invoke.

#### Example Structure
```
runtimes/
├── win-x64/
│   └── native/
│       ├── sqlparser.dll
│       └── mmdparser.dll
├── linux-x64/
│   └── native/
│       ├── libsqlparser.so
│       └── libmmdparser.so
└── osx-x64/
    └── native/
        ├── libsqlparser.dylib
        └── libmmdparser.dylib
```

#### Advantages
- ✅ Best performance (native code)
- ✅ Smallest package size
- ✅ No external runtime dependencies
- ✅ Fastest startup time

#### Disadvantages
- ⚠️ Requires C/C++ implementation or bindings
- ⚠️ More complex build process
- ⚠️ Platform-specific compilation needed

## 📦 Recommended Implementation: Hybrid Approach

### Package Structure

```
SqlMermaidErdTools.1.0.0.nupkg (Platform-specific)
├── lib/
│   └── net10.0/
│       └── SqlMermaidErdTools.dll
├── runtimes/
│   └── win-x64/  (or linux-x64, osx-x64)
│       ├── native/
│       │   └── SqlMermaidErdTools.dll (runtime-specific)
│       ├── python/
│       │   ├── python.exe (embeddable, ~10 MB)
│       │   └── Lib/site-packages/sqlglot/
│       ├── node/
│       │   ├── node.exe (~30 MB)
│       │   └── node_modules/@funktechno/little-mermaid-2-the-sql/
│       └── scripts/
│           ├── sql_to_mmd.py
│           └── mmd_to_sql.js
└── build/
    └── SqlMermaidErdTools.targets (auto-copy runtimes)
```

### Total Package Sizes

| Configuration | Windows | Linux | macOS |
|--------------|---------|-------|-------|
| **Full Runtimes** | ~50 MB | ~55 MB | ~55 MB |
| **Single-File Executables** | ~35 MB | ~40 MB | ~40 MB |
| **Pure .NET (Phase 2)** | ~2 MB | ~2 MB | ~2 MB |

### MSBuild Configuration

```xml
<!-- SqlMermaidErdTools.csproj -->
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <RuntimeIdentifiers>win-x64;linux-x64;osx-x64</RuntimeIdentifiers>
    <GeneratePackageOnBuild>true</GeneratePackageOnBuild>
  </PropertyGroup>

  <!-- Embed Python embeddable distribution -->
  <ItemGroup Condition="'$(RuntimeIdentifier)' == 'win-x64'">
    <Content Include="runtimes\win-x64\python\**\*">
      <PackagePath>runtimes\win-x64\python</PackagePath>
      <Pack>true</Pack>
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </Content>
  </ItemGroup>

  <!-- Embed Node.js portable binary -->
  <ItemGroup Condition="'$(RuntimeIdentifier)' == 'win-x64'">
    <Content Include="runtimes\win-x64\node\**\*">
      <PackagePath>runtimes\win-x64\node</PackagePath>
      <Pack>true</Pack>
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </Content>
  </ItemGroup>

  <!-- Scripts -->
  <ItemGroup>
    <Content Include="scripts\**\*">
      <PackagePath>scripts</PackagePath>
      <Pack>true</Pack>
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </Content>
  </ItemGroup>

  <!-- Auto-copy runtimes on package install -->
  <ItemGroup>
    <None Include="build\SqlMermaidErdTools.targets">
      <Pack>true</Pack>
      <PackagePath>build</PackagePath>
    </None>
  </ItemGroup>
</Project>
```

### Auto-Copy Targets File

```xml
<!-- build/SqlMermaidErdTools.targets -->
<Project>
  <Target Name="CopySqlMermaidErdToolsRuntimes" BeforeTargets="Build">
    <ItemGroup>
      <!-- Copy runtime files to output directory -->
      <ContentFiles Include="$(MSBuildThisFileDirectory)\..\runtimes\$(RuntimeIdentifier)\**\*" />
    </ItemGroup>
    <Copy 
      SourceFiles="@(ContentFiles)" 
      DestinationFolder="$(OutputPath)\runtimes\$(RuntimeIdentifier)\%(RecursiveDir)" 
      SkipUnchangedFiles="true" />
  </Target>
</Project>
```

## Runtime Initialization in C#

### RuntimeManager.cs

```csharp
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace SqlMermaidErdTools.Runtime
{
    public static class RuntimeManager
    {
        private static string _runtimePath;
        private static string _pythonPath;
        private static string _nodePath;

        static RuntimeManager()
        {
            InitializeRuntimes();
        }

        private static void InitializeRuntimes()
        {
            // Get the assembly location
            var assemblyPath = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            
            // Determine runtime identifier
            var rid = GetRuntimeIdentifier();
            
            // Set runtime paths
            _runtimePath = Path.Combine(assemblyPath, "runtimes", rid);
            _pythonPath = Path.Combine(_runtimePath, "python", GetPythonExecutable());
            _nodePath = Path.Combine(_runtimePath, "node", GetNodeExecutable());
            
            // Verify runtimes exist
            if (!File.Exists(_pythonPath))
                throw new FileNotFoundException($"Python runtime not found at {_pythonPath}");
            
            if (!File.Exists(_nodePath))
                throw new FileNotFoundException($"Node.js runtime not found at {_nodePath}");
        }

        private static string GetRuntimeIdentifier()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                return RuntimeInformation.ProcessArchitecture == Architecture.X64 ? "win-x64" : "win-x86";
            
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
                return "linux-x64";
            
            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                return "osx-x64";
            
            throw new PlatformNotSupportedException("Unsupported platform");
        }

        private static string GetPythonExecutable()
        {
            return RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "python.exe" : "bin/python3";
        }

        private static string GetNodeExecutable()
        {
            return RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "node.exe" : "bin/node";
        }

        public static string ExecutePythonScript(string scriptName, string arguments)
        {
            var scriptPath = Path.Combine(_runtimePath, "scripts", scriptName);
            
            var psi = new ProcessStartInfo
            {
                FileName = _pythonPath,
                Arguments = $"\"{scriptPath}\" {arguments}",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };

            using var process = Process.Start(psi);
            var output = process.StandardOutput.ReadToEnd();
            var error = process.StandardError.ReadToEnd();
            
            process.WaitForExit();

            if (process.ExitCode != 0)
                throw new Exception($"Python script failed: {error}");

            return output;
        }

        public static string ExecuteNodeScript(string scriptName, string arguments)
        {
            var scriptPath = Path.Combine(_runtimePath, "scripts", scriptName);
            
            var psi = new ProcessStartInfo
            {
                FileName = _nodePath,
                Arguments = $"\"{scriptPath}\" {arguments}",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = Path.Combine(_runtimePath, "node")
            };

            using var process = Process.Start(psi);
            var output = process.StandardOutput.ReadToEnd();
            var error = process.StandardError.ReadToEnd();
            
            process.WaitForExit();

            if (process.ExitCode != 0)
                throw new Exception($"Node.js script failed: {error}");

            return output;
        }

        public static string PythonPath => _pythonPath;
        public static string NodePath => _nodePath;
        public static string RuntimePath => _runtimePath;
    }
}
```

### Usage Example

```csharp
public class SqlToMmdConverter : ISqlToMmdConverter
{
    public string Convert(string sqlDdl)
    {
        // Write SQL to temp file
        var tempSqlFile = Path.GetTempFileName();
        File.WriteAllText(tempSqlFile, sqlDdl);

        try
        {
            // Execute Python script with bundled runtime
            var result = RuntimeManager.ExecutePythonScript(
                "sql_to_mmd.py", 
                $"\"{tempSqlFile}\""
            );

            return result;
        }
        finally
        {
            File.Delete(tempSqlFile);
        }
    }
}
```

## Build Automation Script

### build-package.ps1

```powershell
#!/usr/bin/env pwsh
param(
    [ValidateSet('win-x64', 'linux-x64', 'osx-x64')]
    [string]$RuntimeId = 'win-x64'
)

$ErrorActionPreference = 'Stop'

Write-Host "Building SqlMermaidErdTools for $RuntimeId" -ForegroundColor Green

# Create runtime directories
$runtimeDir = "src/SqlMermaidErdTools/runtimes/$RuntimeId"
New-Item -ItemType Directory -Force -Path "$runtimeDir/python" | Out-Null
New-Item -ItemType Directory -Force -Path "$runtimeDir/node" | Out-Null
New-Item -ItemType Directory -Force -Path "$runtimeDir/scripts" | Out-Null

# Download and extract Python embeddable
if ($RuntimeId -eq 'win-x64') {
    $pythonUrl = "https://www.python.org/ftp/python/3.11.7/python-3.11.7-embed-amd64.zip"
    $pythonZip = "python-embed.zip"
    
    Write-Host "Downloading Python embeddable..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonZip
    Expand-Archive -Path $pythonZip -DestinationPath "$runtimeDir/python" -Force
    Remove-Item $pythonZip
    
    # Install SQLGlot
    Write-Host "Installing SQLGlot..." -ForegroundColor Cyan
    & "$runtimeDir/python/python.exe" -m pip install --target "$runtimeDir/python/Lib/site-packages" sqlglot
}

# Download and extract Node.js portable
if ($RuntimeId -eq 'win-x64') {
    $nodeUrl = "https://nodejs.org/dist/v18.19.0/node-v18.19.0-win-x64.zip"
    $nodeZip = "node-portable.zip"
    
    Write-Host "Downloading Node.js portable..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $nodeUrl -OutFile $nodeZip
    Expand-Archive -Path $nodeZip -DestinationPath "$runtimeDir/node-temp" -Force
    
    # Move files to correct location
    Move-Item -Path "$runtimeDir/node-temp/node-v18.19.0-win-x64/*" -Destination "$runtimeDir/node" -Force
    Remove-Item -Recurse -Force "$runtimeDir/node-temp"
    Remove-Item $nodeZip
    
    # Install little-mermaid-2-the-sql
    Write-Host "Installing little-mermaid-2-the-sql..." -ForegroundColor Cyan
    Push-Location "$runtimeDir/node"
    & "$runtimeDir/node/node.exe" "$runtimeDir/node/npm" install @funktechno/little-mermaid-2-the-sql
    Pop-Location
}

# Copy scripts
Copy-Item -Path "scripts/*" -Destination "$runtimeDir/scripts" -Recurse -Force

# Build and pack
Write-Host "Building package..." -ForegroundColor Cyan
dotnet pack src/SqlMermaidErdTools/SqlMermaidErdTools.csproj `
    -c Release `
    -p:RuntimeIdentifier=$RuntimeId `
    -o packages

Write-Host "Package created successfully!" -ForegroundColor Green
```

## Distribution Strategy

### Option 1: Platform-Specific Packages
```bash
SqlMermaidErdTools.win-x64.1.0.0.nupkg      (~50 MB)
SqlMermaidErdTools.linux-x64.1.0.0.nupkg    (~55 MB)
SqlMermaidErdTools.osx-x64.1.0.0.nupkg      (~55 MB)
```

### Option 2: Meta-Package with Dependencies
```xml
<!-- SqlMermaidErdTools.nuspec -->
<package>
  <metadata>
    <id>SqlMermaidErdTools</id>
    <version>1.0.0</version>
    <dependencies>
      <group targetFramework="net10.0">
        <dependency id="SqlMermaidErdTools.win-x64" version="1.0.0" 
                    condition="$([MSBuild]::IsOSPlatform('Windows'))" />
        <dependency id="SqlMermaidErdTools.linux-x64" version="1.0.0" 
                    condition="$([MSBuild]::IsOSPlatform('Linux'))" />
        <dependency id="SqlMermaidErdTools.osx-x64" version="1.0.0" 
                    condition="$([MSBuild]::IsOSPlatform('OSX'))" />
      </group>
    </dependencies>
  </metadata>
</package>
```

## Summary

### ✅ Recommended Approach

1. **Use Python Embeddable** (~10 MB) + **Node.js Portable** (~30 MB)
2. **Bundle in platform-specific NuGet packages** (win-x64, linux-x64, osx-x64)
3. **Auto-copy runtimes** to output directory via MSBuild targets
4. **Runtime detection** in C# to find and use bundled executables
5. **Total package size**: ~50 MB per platform (acceptable for most scenarios)

### Benefits

- ✅ **Zero manual setup** - users just `dotnet add package SqlMermaidErdTools`
- ✅ **No system requirements** - everything bundled
- ✅ **Version locked** - guaranteed compatibility
- ✅ **Offline capable** - no internet needed after install
- ✅ **Cross-platform** - same experience on Windows/Linux/macOS
- ✅ **Future migration path** - can replace with pure .NET in Phase 2

### Trade-offs

- ⚠️ Larger package size (~50 MB vs ~2 MB for pure .NET)
- ⚠️ Platform-specific packages required
- ⚠️ Need to update bundled runtimes periodically
- ⚠️ Initial package build is more complex

This is a proven approach used by many commercial tools and is the best balance between ease of use and functionality!

