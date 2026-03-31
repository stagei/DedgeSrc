<#
.SYNOPSIS
    Azure Trusted Signing module for code signing files using Dedge's certificate.

.DESCRIPTION
    This module provides functionality to digitally sign and remove signatures from 
    executable files, scripts, and other signable file types using Azure Trusted Signing.
    It supports both individual file signing and batch operations with parallel processing.
    
    Prerequisites are automatically downloaded and installed if missing:
    - Windows SDK (SignTool)
    - Microsoft Trusted Signing Client Tools

.EXAMPLE
    Invoke-DedgeSign -Path "C:\MyApp\bin" -Recursive -Action Add
    # Signs all executable files in the directory recursively

.EXAMPLE
    Invoke-DedgeSign -Path "C:\Scripts\MyScript.ps1" -Action Add
    # Signs a single PowerShell script

.EXAMPLE
    Invoke-DedgeSign -Path "C:\MyApp\bin" -Action Remove -Recursive
    # Removes signatures from all files in the directory

.NOTES
    Author: Geir Helge Starholm, www.dEdge.no
    Requires Azure Trusted Signing configuration with valid credentials.
#>

# Check if started from folder path lowercased containing text "DedgePsh"
try {
    $modulesToImport = @("GlobalFunctions")
    foreach ($moduleName in $modulesToImport) {
        if (-not (Get-Module -Name $moduleName) -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
            try {
                Import-Module $moduleName -Force
            }
            catch {
                Write-Host "Failed to load $moduleName module: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    $env:DedgeSignDedgePsh = $true
    $env:DedgeSignQuietMode = $true

}
catch {
    Write-LogMessage "DedgeSignDedgePsh is not set" -Level INFO
    $env:DedgeSignDedgePsh = $false
    $env:DedgeSignQuietMode = $false
}

function Get-DefaultSignToolPath {
    return "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"
}

function Get-DefaultDlibPath {
    return Join-Path $env:LOCALAPPDATA "Microsoft\MicrosoftTrustedSigningClientTools\Azure.CodeSigning.Dlib.dll"
}

function Get-SignDataFolder {
    $dataFolder = Join-Path $env:OptPath "data" "DedgeSign"
    if (-not (Test-Path $dataFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $dataFolder | Out-Null
    }
    return $dataFolder
}

function Get-LogFile {
    return Join-Path $(Get-SignDataFolder) "DedgeSign.log"
}

function Get-MetadataFile {
    return Join-Path $(Get-SignDataFolder) "metadata-fka.json"
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::White,
        [Parameter(Mandatory = $false)]
        [switch]$NoConfirm
    )

    # Write to console with color
    if ($env:DedgeSignDedgePsh) {

        if ($env:DedgeSignQuietMode) {
            $tempQuietMode = $true
        }
        else {
            $tempQuietMode = $false
        }
        $level = if ($ForegroundColor -eq [System.ConsoleColor]::Red) { "ERROR" } elseif ($ForegroundColor -eq [System.ConsoleColor]::Yellow) { "WARN" } else { "INFO" }
        try {
            Write-LogMessage $Message -Level $level -ForegroundColor $ForegroundColor -QuietMode:$tempQuietMode
        }
        catch {
            if (-not $NoConfirm -and -not $env:DedgeSignQuietMode) {
                Write-Host $Message -ForegroundColor $ForegroundColor
            }
    
            # Write to log file with timestamp
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "$timestamp|$env:USERNAME|$env:USERDOMAIN|$env:COMPUTERNAME|$Message" | Out-File -FilePath $(Get-LogFile) -Append -Encoding UTF8        
        }
    }
    else {
        if (-not $NoConfirm -and -not $env:DedgeSignQuietMode) {
            Write-Host $Message -ForegroundColor $ForegroundColor
        }

        # Write to log file with timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$timestamp|$env:USERNAME|$env:USERDOMAIN|$env:COMPUTERNAME|$Message" | Out-File -FilePath $(Get-LogFile) -Append -Encoding UTF8
    }
}


function Initialize-Metadata {
    $metadataPath = Join-Path $(Get-SignDataFolder) "metadata-fka.json"

    if (-not (Test-Path $metadataPath -PathType Leaf)) {
        $metadata = @{
            CertificateProfileName = "fka-publicsigning-profile"
            CodeSigningAccountName = "pwetrustedsigningfka" 
            Endpoint               = "https://weu.codesigning.azure.net/"
        }
        $metadata | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding UTF8
        Write-Log "Created metadata file at: $metadataPath"
    }
}

function Initialize-Prerequisites {

    $signToolPath = Get-DefaultSignToolPath
    $dlibPath = Get-DefaultDlibPath

    $missingPrereqs = @()

    if (-not (Test-Path $signToolPath -PathType Leaf)) {
        $missingPrereqs += "Windows SDK (SignTool)"
    }
    
    if (-not (Test-Path $dlibPath -PathType Leaf)) {
        $missingPrereqs += "Microsoft Trusted Signing Client Tools"
    }
    
    if ($missingPrereqs.Count -gt 0) {
        Write-Log "`nMissing prerequisites:" -ForegroundColor Red
        foreach ($prereq in $missingPrereqs) {
            Write-Log "- $prereq" -ForegroundColor Red
        }
        # Try to auto-download and install prerequisites with elevation
        Write-Log "`nAttempting to auto-download and install missing prerequisites..." -ForegroundColor Yellow
        
        # Check if running as admin
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            Write-Log "Requesting administrative privileges..." -ForegroundColor Yellow
            
            # Relaunch script as admin
            $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" $($MyInvocation.UnboundArguments)"
            Start-Process powershell -Verb RunAs -ArgumentList $arguments
            return $false
        }
    
        $tempDir = Join-Path $env:TEMP "DedgeSignPrereqs"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir | Out-Null
        }
    
        if ($missingPrereqs -contains "Windows SDK (SignTool)") {
            $sdkUrl = "https://go.microsoft.com/fwlink/p/?linkid=2196241"
            $sdkInstaller = Join-Path $tempDir "winsdksetup.exe"
            
            Write-Log "Downloading Windows SDK..." -ForegroundColor Yellow
            try {
                Invoke-WebRequest -Uri $sdkUrl -OutFile $sdkInstaller
                Write-Log "Installing Windows SDK (this may take a while)..." -ForegroundColor Yellow
                Start-Process -FilePath $sdkInstaller -ArgumentList "/features OptionId.SigningTools /quiet /norestart" -Wait -Verb RunAs
            }
            catch {
                Write-Log "Failed to download/install Windows SDK: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    
        if ($missingPrereqs -contains "Microsoft Trusted Signing Client Tools") {
            $tsctUrl = "https://download.microsoft.com/download/6d9cb638-4d5f-438d-9f21-23f0f4405944/TrustedSigningClientTools.msi"
            $tsctInstaller = Join-Path $tempDir "TrustedSigningClientTools.msi"
            
            Write-Log "Downloading Microsoft Trusted Signing Client Tools..." -ForegroundColor Yellow
            try {
                Invoke-WebRequest -Uri $tsctUrl -OutFile $tsctInstaller
                Write-Log "Installing Microsoft Trusted Signing Client Tools..." -ForegroundColor Yellow
                Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tsctInstaller`" /quiet" -Wait -Verb RunAs
            }
            catch {
                Write-Log "Failed to download/install Trusted Signing Client Tools: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    
        # Clean up temp directory
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    
        # Recheck prerequisites after installation attempts
        $missingPrereqs = @()
        if (-not (Test-Path $signToolPath -PathType Leaf)) { $missingPrereqs += "Windows SDK (SignTool)" }
        
        if (-not (Test-Path $dlibPath -PathType Leaf)) { $missingPrereqs += "Microsoft Trusted Signing Client Tools" }
    
        if ($missingPrereqs.Count -gt 0) {
            Write-Log "`nSome prerequisites could not be automatically installed." -ForegroundColor Red
            Write-Log "`nPlease install the following manually:" -ForegroundColor Yellow
            
            if ($missingPrereqs -contains "Windows SDK (SignTool)") {
                Write-Log "`nWindows SDK:" -ForegroundColor Yellow
                Write-Log "1. Download from: https://go.microsoft.com/fwlink/p/?linkid=2196241" 
                Write-Log "2. Run installer and select 'Windows SDK Signing Tools'"
                Write-Log "3. Verify SignTool exists at: $signToolPath"
            }
            
            if ($missingPrereqs -contains "Microsoft Trusted Signing Client Tools") {
                Write-Log "`nMicrosoft Trusted Signing Client Tools:" -ForegroundColor Yellow
                Write-Log "1. Download from: https://download.microsoft.com/download/6d9cb638-4d5f-438d-9f21-23f0f4405944/TrustedSigningClientTools.msi"
                Write-Log "2. Run installer and select 'Microsoft Trusted Signing Client Tools'"
                Write-Log "3. Verify Dlib exists at: $dlibPath"
            }
            return $false
        }
        else {
            Write-Log "`nAll prerequisites successfully installed!" -ForegroundColor Green
        }
    }
    return $true
}

function Get-ExecutableFiles {
    param (
        [string]$Path = ".",
        [switch]$Recursive
    )
    
    Write-Log "Scanning for files to sign in: $Path" -ForegroundColor White
    # check if path is a directory
    if (Test-Path $Path -PathType Container) {
        Write-Log "Path is a directory"
    }
    else {
        # Change path to the directory of the file. Used in VS2022 to sign all files in the bin folder.
        if ($Path -match '\\bin\\|[*?]') {
            Write-Log "File path contains bin, changing to parent directory"
            $Path = Split-Path $Path -Parent
        }
    }
    # Get leaf name of path for logging
    $leafName = Split-Path $Path -Leaf
    if ($leafName -eq ".") {
        $leafName = "*.*"
        $Path = Join-Path (Split-Path $Path -Parent) $leafName
    }
    
    # Check if path is a file pattern
    if ($Path -match '[*?]') {
        $directory = Split-Path $Path -Parent
        if (-not $directory) { 
            $directory = "." 
        }

        $pattern = Split-Path $Path -Leaf -ErrorAction SilentlyContinue
        if (-not $pattern) {
            $pattern = "*.*" 
        }
        Write-Log "Searching $(if ($Recursive) { 'recursively' } else { 'non-recursively' }) for files matching pattern: $pattern"
        if ($Recursive) {
            $files = Get-ChildItem -Path $directory -Filter $pattern -File -Recurse
        }
        else {
            $files = Get-ChildItem -Path $directory -Filter $pattern -File
        }
    }
    # Check if path is a file
    elseif (Test-Path $Path -PathType Leaf) {
        Write-Log "Single file mode"
        $files = Get-Item $Path
    }
    # Path is a directory
    else {
        Write-Log "Directory mode $(if ($Recursive) { '(recursive)' } else { '(non-recursive)' })"
        if ($Recursive) {
            $files = Get-ChildItem -Path $Path -File -Recurse
        }
        else {
            $files = Get-ChildItem -Path $Path -File
        }
    }
    
    # Filter for executable types
    $files = $files | Where-Object { 
        $_.Extension -match '\.(exe|dll|ps1|psm1|psd1|vbs|wsf|js|msi|sys|ocx|ax|cpl|drv|efi|mui|scr|tsp|plugin|xll|wll|pyd|pyo|pyc|jar|war|ear|class|xpi|crx|nex|xbap|application|appref-ms|gadget|widget|ipa|apk|xap|msix|msixbundle|appx|appxbundle|msp|mst|msu|tlb|com)$'
    }
    # Remove files where path like clidriver
    $files = $files | Where-Object { 
        $_.FullName -notlike "*clidriver*"
    }
    Write-Log "Found $($files.Count) executable files" -ForegroundColor Yellow
    return $files
}

function Test-FileSignature {
    param (
        [string]$FilePath
    )
    
    try {
        $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()

        # MSI/MSP/MST store signatures in an internal database stream;
        # Get-AuthenticodeSignature can be unreliable for these formats,
        # so use signtool verify as the primary check.
        if ($extension -in @('.msi', '.msp', '.mst')) {
            $signToolPath = Get-DefaultSignToolPath
            if (Test-Path $signToolPath -PathType Leaf) {
                $null = & $signToolPath verify /pa $FilePath 2>&1
                return ($LASTEXITCODE -eq 0)
            }
        }

        $signature = Get-AuthenticodeSignature -FilePath $FilePath
        if ($signature.Status -eq [System.Management.Automation.SignatureStatus]::Valid) {
            return $true
        }
        return $false
    }
    catch {
        Write-Log "Error checking signature for $($FilePath): $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Set-Signature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$FilePath
    )



        
    #Import-Module "$PSScriptRoot\DedgeSign.psm1"
        
    # if path is not provided, show a help dialog related to usage of the script
    if (-not $FilePath) {
        Write-Log "Usage: .\DedgeSign-AddFileSign.ps1 -FilePath <path>"
        return $false
    }
        
    # Check if file exists
    if (-not (Test-Path $FilePath -PathType Leaf)) {
        Write-Log "Error: File not found - $FilePath" -ForegroundColor Red
        if (Get-Module -Name GlobalFunctions) {
            Write-LogMessage "Error: File not found - $FilePath" -Level ERROR
        }
        return $false
    }
        
    # Check if file is already signed
    if (Test-FileSignature -FilePath $FilePath) {
        Write-Log "File is already signed." -ForegroundColor Yellow
        if (Get-Module -Name GlobalFunctions) {
            Write-LogMessage "File is already signed." -Level WARN
        }
        return $false
    }
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    # Parentheses required: -not binds tighter than -match without them
    if (-not ($extension -match '\.(ps1|psm1|psd1|vbs|wsf|js|exe|dll|msi|sys|ocx|ax|cpl|drv|efi|mui|scr|tsp|plugin|xll|wll|pyd|pyo|pyc|jar|war|ear|class|xpi|crx|nex|xbap|application|manifest|appref-ms|gadget|widget|ipa|apk|xap|msix|msixbundle|appx|appxbundle|msp|mst|msu|tlb|com)$')) {
        Write-Log "Unsupported file type for signing: $extension" -ForegroundColor Yellow
        if (Get-Module -Name GlobalFunctions) {
            Write-LogMessage "Unsupported file type for signing: $extension" -Level WARN
        }
        return $false
    } 
    # SignTool path
    $signToolPath = Get-DefaultSignToolPath
    $dlibPath = Get-DefaultDlibPath
    $metadataPath = Get-MetadataFile
        
    try {
        # Sign the file using internal Azure settings
        $signArgs = @(
            "sign",
            "/v",
            "/debug",
            "/fd", "SHA256",
            "/tr", "http://timestamp.acs.microsoft.com",
            "/td", "SHA256",
            "/dlib", $dlibPath,
            "/dmdf", $metadataPath,
            $FilePath
        )
            
        Write-Log "Running SignTool..."
        $result = & $signToolPath $signArgs 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            if (-not $QuietMode) {
                Write-Log "Successfully signed: $FilePath" -ForegroundColor Green
            }
            if (Get-Module -Name GlobalFunctions) {
                Write-LogMessage "Successfully signed: $FilePath" -Level INFO
            }
            return $true
        }
        else {
            Write-Log "Failed to sign file. Exit code: $LASTEXITCODE. Output: $result" -ForegroundColor Red
            if (Get-Module -Name GlobalFunctions) {
                Write-LogMessage "Failed to sign file. Exit code: $LASTEXITCODE. Output: $result" -Level ERROR
            }
            return $false
        }
    }
    catch {
        Write-Log "Error signing file: $($_.Exception.Message)" -ForegroundColor Red
        if (Get-Module -Name GlobalFunctions) {
            Write-LogMessage "Error signing file: $($_.Exception.Message)" -Level ERROR -Exception $_
        }
        return $false
    }
}
    
function Remove-Signature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$FilePath
    )
    function Get-SignDataFolder {
        $dataFolder = Join-Path $env:OptPath "data" "DedgeSign"
        if (-not (Test-Path $dataFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $dataFolder | Out-Null
        }
        return $dataFolder
    }
    # if path is not provided, show a help dialog related to usage of the script
    if (-not $FilePath) {
        Write-Log "Usage: .\DedgeSign-RemoveFileSign.ps1 -FilePath <path>"
        return $false
    }

    # Check if file exists
    if (-not (Test-Path $FilePath -PathType Leaf)) {
        Write-Log "Error: File not found - $FilePath" -ForegroundColor Red
        return $false
    }

    # Check if file has a signature to remove
    if (-not (Test-FileSignature -FilePath $FilePath)) {
        Write-Log "File is not signed." -ForegroundColor Yellow
        return $false
    }

    # SignTool path (updated to match your environment)
    $signToolPath = Get-DefaultSignToolPath

    try {
        # Remove signature from the file
        Write-Log "Running signature removal..."
    
        # Check file extension
        $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    
        # Script files use content replacement
        if ($extension -match '\.(ps1|psm1|psd1|vbs|wsf|js)$') { 
            Write-Log "Using script signature removal method..."
            $content = Get-Content -Path $FilePath -Raw
            $newContent = $content -replace '# SIG # Begin signature block[\s\S]*# SIG # End signature block', ''
            $newContent | Set-Content -Path $FilePath -NoNewline
        }
        # Binary/Executable files use SignTool
        elseif ($extension -match '\.(exe|dll|msi|sys|ocx|ax|cpl|drv|efi|mui|scr|tsp|plugin|xll|wll|pyd|pyo|pyc|jar|war|ear|class|xpi|crx|nex|xbap|application|manifest|appref-ms|gadget|widget|ipa|apk|xap|msix|msixbundle|appx|appxbundle|msp|mst|msu|tlb|com)$') {
            Write-Log "Using SignTool removal method..."
            $result = & $signToolPath remove /s $FilePath 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Log "SignTool Error: $result" -ForegroundColor Red
                return $false
            }
        }
        # Unknown file type
        else {
            Write-Log "Unsupported file type for signature removal: $extension" -ForegroundColor Yellow
            return $false
        }

        Write-Log "Successfully removed signature from: $FilePath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Log "Error removing signature: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } 
}
function Set-SingleFileSignatureParallel {
    param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$file,
        [Parameter(Mandatory = $false)]
        [string[]]$ExecutableExtensions = @()
    )
    
    $job = $null
    if ($Action -eq 'Add') {
        if (-not (Test-FileSignature -FilePath $file.FullName)) {
            $job = Start-Job -ScriptBlock {
                param($filePath, $ExecutableExtensions)
                Import-Module DedgeSign -Force
                Invoke-DedgeSign -Path $filePath -Action Add -NoConfirm -QuietMode -ExecutableExtensions $ExecutableExtensions -CalledFromPararell
            } -ArgumentList $file.FullName, $ExecutableExtensions
        }
    }
    elseif ($Action -eq 'Remove') {
        if (Test-FileSignature -FilePath $file.FullName) {
            $job = Start-Job -ScriptBlock {
                param($filePath, $ExecutableExtensions)
                Import-Module DedgeSign -Force
                Invoke-DedgeSign -Path $filePath -Action Remove -NoConfirm -QuietMode -ExecutableExtensions $ExecutableExtensions -CalledFromPararell
            } -ArgumentList $file.FullName, $ExecutableExtensions
        }
    }
    return $job
}

function Set-SignatureParallel {
    param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo[]]$allFiles,
        [Parameter(Mandatory = $false)]
        [switch]$NoConfirm,
        [Parameter(Mandatory = $false)]
        [string[]]$ExecutableExtensions = @()
    )
    $failCount = 0
    $successCount = 0
    Write-Log "`nStarting parallel signature jobs..." -ForegroundColor Cyan
    $jobs = @()
    foreach ($file in $allFiles) {
        $job = Set-SingleFileSignatureParallel -file $file -ExecutableExtensions $ExecutableExtensions 
        if ($job) {
            $jobs += $job
        }
    }
    if ($ParallelNoWait) {
        Write-Log "Parallel mode with no waiting" -ForegroundColor Cyan
    }
    else {
        
        if ($jobs.Count -gt 0) {
            Wait-Job -Job $jobs | Receive-Job
            Remove-Job -Job $jobs
            Write-Log "All signature jobs completed" -ForegroundColor Green
            $successCount = $jobs.Count
            $failCount = 0
            foreach ($job in $jobs) {
                if ($job.State -eq 'Failed') {
                    $failCount++
                }
            }
            Write-Log "Successfully signed: $successCount files" -ForegroundColor White
            if ($failCount -gt 0) {
                Write-Log "Failed to sign: $failCount files" -ForegroundColor Red
            }
        }
        else {
            if ($Action -eq 'Add') {
                Write-Log "No files need signing" -ForegroundColor White
            }
            else {
                Write-Log "No files need signature removal" -ForegroundColor Yellow
            }
        }
    }
    return $failCount
}

function Set-SignatureStandard {
    param (
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo[]]$allFiles,
        [Parameter(Mandatory = $false)]
        [switch]$NoConfirm
    )
    $failCount = 0
    $successCount = 0
    $filesToSign = @()
    Write-Log "`nChecking file signatures..." -ForegroundColor White -NoConfirm
    foreach ($file in $allFiles) {
        if ($Action -eq 'Add') {
            if (-not (Test-FileSignature -FilePath $file.FullName)) {
                $filesToSign += $file
            }
        }
        elseif ($Action -eq 'Remove') {
            if (Test-FileSignature -FilePath $file.FullName) {
                $filesToSign += $file
            }
        }
    }
    
    if ($filesToSign.Count -eq 0) {
        if ($Action -eq 'Add') {
            Write-Log "`nAll files are already signed." -ForegroundColor Green -NoConfirm
        }
        else {
            Write-Log "`nNo signed files found to remove signatures from." -ForegroundColor Green -NoConfirm
        }
        return $true
    }
    
    Write-Log "`nFound $($filesToSign.Count) following files:" -ForegroundColor Yellow -NoConfirm
    $filesToSign | ForEach-Object { Write-Log "  $($_.FullName)" }
    if (-not $NoConfirm) {
        if ($Action -eq 'Add') {
            $confirm = Read-Host "`nDo you want to sign these files? (Y/N)"
        }
        else {
            $confirm = Read-Host "`nDo you want to remove signatures from these files? (Y/N)"
        }
    }
    else {
        $confirm = "Y"
        Write-Log "`nAuto-confirming, signing all files..." -ForegroundColor Cyan -NoConfirm
    }
        
    if ($confirm -eq "Y") {
        $successCount = 0
        $failCount = 0
        
        foreach ($file in $filesToSign) {
            if ($Action -eq 'Add') {    
                if (Set-Signature -FilePath $file.FullName) {
                    $successCount++
                }
                Write-Log "`nSigning complete!" -ForegroundColor Cyan -NoConfirm
                Write-Log "Successfully signed: $successCount files" -ForegroundColor White
                if ($failCount -gt 0) {
                    Write-Log "Failed to sign: $failCount files" -ForegroundColor Red
                    return $false
                }
                return $true
            }
            elseif ($Action -eq 'Remove') {
                if (Remove-Signature -FilePath $file.FullName) {
                    $successCount++
                }
                Write-Log "`nRemoving signatures complete!" -ForegroundColor Cyan -NoConfirm
                Write-Log "Successfully removed signatures from: $successCount files" -ForegroundColor White
                if ($failCount -gt 0) {
                    Write-Log "Failed to remove signatures from: $failCount files" -ForegroundColor Red
                    return $false
                }
                return $true
            }
        }
        
    }
    else {
        Write-Log "Operation cancelled." -ForegroundColor Yellow
        return $false
    }
    return $true
}


function Invoke-DedgeSign {
    
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
        [switch]$NoConfirm,

        [Parameter()]
        [switch]$Parallel = $false,
    
        [Parameter()]
        [switch]$ParallelNoWait = $false,

        [Parameter()]
        [switch]$QuietMode = $false,

        [Parameter()]
        [string[]]$ExecutableExtensions = @(),
        [Parameter()]
        [switch]$CalledFromPararell = $false
    )

    if (Get-Module -Name GlobalFunctions) {
        if ($Action -eq 'Add') {
            $jobText = "Signature operation for $Path"
        }
        else {
            $jobText = "Signature removal operation for $Path"
        }
        Write-LogMessage $jobText -Level JOB_STARTED -QuietMode
    }
    try {
        # Main script
        $heading = "Dedge's Azure Trusted Signing Tool - Function: $(if ($Action -eq 'Add') { 'Add Digital Signatures' } else { 'Remove Digital Signatures' })"
        Initialize-Metadata
        $result = Initialize-Prerequisites
        if (-not $result) {
            return $false
        }
        if ($Action -eq 'Add'  ) {
            #$completetionText = 'sign'
            $completetionTextPlural = 'signed'
        }
        else {
            #$completetionText = 'unsign'
            $completetionTextPlural = 'unsigned'
        }

        # Write-Log "Parameters: $($PSBoundParameters | Out-String)"

        # if path is not provided, show a help dialog related to usage of the script
        if (-not $Path) {
            Write-Log "Usage: .\DedgeSign.ps1 -Path <path> -Action <Add|Remove> -Recursive <true|false>" -ForegroundColor Yellow
            return $false
        }
        Write-Log (("=" * (($heading.Length / 2) - 7)) + " DedgeSign Start " + ("=" * (($heading.Length / 2) - 7))) -ForegroundColor White

        Write-Log $heading -ForegroundColor Cyan
        Write-Log ("-" * $heading.Length) -ForegroundColor White

        $allFiles = Get-ExecutableFiles -Path $Path -Recursive:$Recursive 
        if ($ExecutableExtensions.Count -gt 0) {
            $allFiles = $allFiles | Where-Object { "*$($_.Extension)" -in $ExecutableExtensions }
        }
        # Get all executable files
        if ($allFiles.Count -eq 0) {
            Write-Log "--> No files found to sign." -ForegroundColor Yellow
            Write-Log (("=" * (($heading.Length / 2) - 6)) + " DedgeSign End " + ("=" * (($heading.Length / 2) - 6))) -ForegroundColor White
            return $true
        }
    
        $failCount = 0
        if ($Parallel) {
            $failCount = Set-SignatureParallel -allFiles $allFiles -NoConfirm:$NoConfirm -ExecutableExtensions $ExecutableExtensions
            if (-not $QuietMode) {
                if ($failCount -gt 0) {
                    Write-Host "Failed to $completetionTextPlural $failCount of $($allFiles.Count) files for $Path " -ForegroundColor Red
                }
                else {
                    Write-Host "Successfully $completetionTextPlural $($allFiles.Count) files for $Path" -ForegroundColor Green
                }
                Write-Host (("=" * (($heading.Length / 2) - 6)) + " DedgeSign End " + ("=" * (($heading.Length / 2) - 6))) -ForegroundColor White
            }
        }
        else {
            $result = Set-SignatureStandard -allFiles $allFiles -NoConfirm:$NoConfirm
            if ($CalledFromPararell) {
                return $result
            }
            if (-not $QuietMode) {
                if (-not $result) {
                    Write-Host "Failed to $completetionTextPlural $failCount of $($allFiles.Count) files for $Path" -ForegroundColor Red
                }
                else {
                    Write-Host "Successfully $completetionTextPlural $($allFiles.Count) files for $Path" -ForegroundColor Green
                }
                #Write-Host (("=" * (($heading.Length / 2) - 6)) + " DedgeSign End " + ("=" * (($heading.Length / 2) - 6))) -ForegroundColor White
            }
        }
        if (Get-Module -Name GlobalFunctions) {
            Write-LogMessage $jobText -Level JOB_COMPLETED -QuietMode
        }


        return $result
    }
    catch {
        if (Get-Module -Name GlobalFunctions) {
            Write-LogMessage $jobText -Level JOB_FAILED -Exception $_
        }
    }
}