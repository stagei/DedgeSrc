<#
.SYNOPSIS
    Manages deployment of PowerShell modules and configurations across servers.

.DESCRIPTION
    This module handles the deployment of PowerShell modules, scripts, and configurations
    across multiple servers in the Dedge environment. It manages module paths,
    environment variables, and ensures consistent deployment across the infrastructure.

.EXAMPLE
    Deploy-ModulesToServerShare -serverPath "\\server\share\modules"
    # Deploys modules to a network share location

.EXAMPLE
    Deploy-ModulesToLocalOptPath
    # Deploys modules to the local OptPath directory structure
#>

$modulesToImport = @("GlobalFunctions", "Infrastructure", "ScheduledTask-Handler", "Cobol-Handler", "DedgeSign", "Db2-Handler")
foreach ($moduleName in $modulesToImport) {
  if (-not (Get-Module -Name $moduleName) -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
    Import-Module $moduleName -Force
  }
} 
 

if ($PSVersionTable.PSVersion.Major -lt 7) {
  Write-Host "This script requires PowerShell 7 or later" -ForegroundColor Red
  exit
}

function Deploy-ModulesToLocalOptPath {
  $localPath = Join-Path $env:OptPath "DedgePshApps" "CommonModules"
  Write-LogMessage "Deploying modules to local path: $localPath" -Level INFO

  # Create directory if it doesn't exist
  if (-not (Test-Path $localPath -PathType Container)) {
    New-Item -ItemType Directory -Path $localPath -Force -ErrorAction Stop | Out-Null
  }
}
function Get-SignControlFile {
 
  
  # Setup control file for hash tracking
  $controlFolder = Join-Path $env:OptPath "data" "DedgeSign"
  $controlFileJson = Join-Path $controlFolder "control.json"
  
  # Ensure control folder exists
  if (-not (Test-Path $controlFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $controlFolder -Force -ErrorAction Stop | Out-Null
  }

  # Initialize or load control file
  if (-not (Test-Path $controlFileJson -PathType Leaf)) {
    $control = @{
      lastUpdate = (Get-Date).ToString('o')
      files      = @()
    }
  }
  else {
    $control = Get-Content $controlFileJson -Raw | ConvertFrom-Json -AsHashtable
    if (-not $control.files) { $control.files = @() }
  }

  return $controlFileJson
}

function Get-LocalDifferences {
  param (
    [Parameter(Mandatory = $true)]
    [string]$deployPath,
    [Parameter(Mandatory = $false)]
    [bool]$recursive = $false
  )
  $control = Get-SignControlFile 
  $changedFiles = @()
  if ($recursive) {
    $files = Get-ChildItem -Path $deployPath -Recurse -File
  }
  else {
    $files = Get-ChildItem -Path $deployPath -File
  }
  foreach ($file in $files) {
    $relativePath = $file.FullName.Replace($deployPath, '').TrimStart('\')
    $currentHash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
    $existingFile = $control.files | Where-Object { $_.path -eq $relativePath }
    $targetExists = Test-Path $targetPath -PathType Leaf
    $needsCopy = $false
    if (-not $targetExists) {
      $needsCopy = $true
    }
    elseif (-not $existingFile) {
      $targetHash = (Get-FileHash -Path $targetPath -Algorithm SHA256).Hash
      $needsCopy = $targetHash -ne $currentHash
    }
    elseif ($existingFile.hash -ne $currentHash) {
      $needsCopy = $true
    }
    if ($needsCopy) {
      $changedFiles += $relativePath
    }
  }
  return $changedFiles
}

function Deploy-ModulesToServerShare {
  param ( 
    [Parameter(Mandatory = $true)]
    [string]$serverPath,
    [switch]$signFiles = $false
  )

  Deploy-ModulesToLocalOptPath

  Write-LogMessage "Deploying modules to: $serverPath" -Level INFO
  
  # Setup control file for hash tracking
  $controlFolder = Join-Path $env:OptPath "data" "DedgeSign"
  $controlFileJson = Join-Path $controlFolder "control.json"
  $localModulesPath = Join-Path $env:OptPath "DedgePshApps" "CommonModules"
  
  # Ensure control folder exists
  if (-not (Test-Path $controlFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $controlFolder -Force -ErrorAction Stop | Out-Null
  }

  # Initialize or load control file
  if (-not (Test-Path $controlFileJson -PathType Leaf)) {
    $control = @{
      lastUpdate = (Get-Date).ToString('o')
      files      = @()
    }
  }
  else {
    $control = Get-Content $controlFileJson -Raw | ConvertFrom-Json -AsHashtable
    if (-not $control.files) { $control.files = @() }
  }

  # Track which files have changed
  $changedFiles = @()
  
  # Compare and copy files
  Get-ChildItem -Path $PSScriptRoot -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Replace($PSScriptRoot, '').TrimStart('\')
    $targetPath = Join-Path $localModulesPath $relativePath
    $currentHash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
      
    $existingFile = $control.files | Where-Object { $_.path -eq $relativePath }
    $targetExists = Test-Path $targetPath -PathType Leaf
      
    $needsCopy = $false
    if (-not $targetExists) {
      $needsCopy = $true
    }
    elseif (-not $existingFile) {
      $targetHash = (Get-FileHash -Path $targetPath -Algorithm SHA256).Hash
      $needsCopy = $targetHash -ne $currentHash
    }
    elseif ($existingFile.hash -ne $currentHash) {
      $needsCopy = $true
    }

    if ($needsCopy) {
      # Ensure target directory exists
      Add-FolderForFileIfNotExists -FileName $targetPath
     

          
      # Copy the file
      Copy-Item -Path $_.FullName -Destination $targetPath -Force
      $changedFiles += $relativePath
          
      # Update control file
      if (-not $existingFile) {
        $control.files += @{
          path        = $relativePath
          hash        = $currentHash
          lastUpdated = (Get-Date).ToString('o')
        }
      }
      else {
        $existingFile.hash = $currentHash
        $existingFile.lastUpdated = (Get-Date).ToString('o')
      }
    }
  }

  # Remove files that no longer exist in source
  Get-ChildItem -Path $localModulesPath -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Replace($localModulesPath, '').TrimStart('\')
    $sourcePath = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path $sourcePath)) {
      Remove-Item $_.FullName -Force
      Write-Progress -Completed -ErrorAction SilentlyContinue

      $control.files = $control.files | Where-Object { $_.path -ne $relativePath }
      $changedFiles += "Removed: $relativePath"
    }
  }

  # Remove empty directories
  Get-ChildItem -Path $localModulesPath -Directory -Recurse | 
  Where-Object { -not (Get-ChildItem -Path $_.FullName -Recurse -File) } | 
  Remove-Item -Recurse -Force
  Write-Progress -Completed -ErrorAction SilentlyContinue

  # Save control file
  $control.lastUpdate = (Get-Date).ToString('o')
  $control | ConvertTo-Json -Depth 10 | Set-Content $controlFileJson

  # Sign files if requested
  if ($signFiles) {
    Write-LogMessage "Signing files" -Level INFO
    $DedgeSignScript = Join-Path $DedgeSignPath "DedgeSign.ps1"
    . $DedgeSignScript -Path $localModulesPath -Recursive -Action Add -NoConfirm -Parallel
  }

  # Deploy to server share
  if (-not (Test-Path $serverPath -PathType Container)) {
    New-Item -ItemType Directory -Path $serverPath -Force -ErrorAction Stop | Out-Null
  }

  # Only copy to server if we have changes or signing was requested
  if ($changedFiles.Count -gt 0 -or $signFiles) {
    # Copy all files from local CommonModules to server share
    Copy-Item -Path "$localModulesPath\*" -Destination $serverPath -Recurse -Force
      
    # Clean up deployment scripts from target
    Remove-Item -Path "$serverPath\deploy*.ps1" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$serverPath\deploy*.bat" -Force -ErrorAction SilentlyContinue

    Write-LogMessage "Successfully deployed to: $serverPath" -Level INFO
      
    if ($changedFiles.Count -gt 0) {
      Write-LogMessage "`nFiles updated:" -Level INFO
      $changedFiles | ForEach-Object { Write-LogMessage "  $_" -Level DEBUG }
    }
  }
  else {
    Write-LogMessage "`nNo files needed updating" -Level INFO
  }
}
function Get-ResolvedFiles {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FromFolder,
    [Parameter(Mandatory = $false)] 
    [string[]]$Files = @()
  )

  if ($Files -is [array] -and $Files.Count -gt 0) {
    $newFiles = @()
    foreach ($file in $Files) {
      if (-not $file.Contains("\")) {      
        $newFiles += "$FromFolder\$file"
      }
      else {
        $newFiles += $file
      }
    }
    $newFiles = @($newFiles | Where-Object { 
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Split('\')[-1])
        $baseName.ToLower() -ne 'deploy'
      })

    $missingFiles = @()
    foreach ($file in $newFiles) {
      if (-not (Test-Path $file -PathType Leaf)) {
        $missingFiles += $file
      }
    }
    if ($missingFiles.Count -gt 0) {
      Write-LogMessage "Files not found: $($missingFiles -join ", ")" -Level ERROR
      return $false
    }
    return $newFiles
  }
  else {
    # If no files specified, get all files in fromfolder
    $allFiles = (Get-ChildItem -Path $FromFolder -Recurse -File).FullName
    if ($allFiles.Count -eq 0) {
      Write-LogMessage "No files found in $FromFolder" -Level ERROR
      return $false
    }
    # check if any of the files are starts with "Deploy-Handler"
    $deployHandlerFiles = @($allFiles | Where-Object { $_.ToLower().Contains("deploy-handler") })
    if ($deployHandlerFiles.Count -gt 0) {
      Write-LogMessage "Deploy-Handler files found in $FromFolder" -Level INFO
    }
    return $allFiles
  }
}
function Get-StagingPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string]$FromFolder,
    [Parameter(Mandatory = $true)]
    [string]$AppName,
    [Parameter(Mandatory = $false)]
    [bool]$GetLegacyPath = $false,
    [Parameter(Mandatory = $false)]
    [PSCustomObject]$CurrentDeployFileInfo
  )
  $stagingPath = "$($env:OptPath)\$($CurrentDeployFileInfo.RelativePath)"

  # if ($CurrentDeployFileInfo.AppTechnology -eq "DedgePshApps") {
  #   if (Test-IsModuleDeployment -FromFolder $FromFolder -ApplicationTechnologyFolderName $CurrentDeployFileInfo.AppTechnology) {
  #     $stagingPath = "$($env:OptPath)\$($CurrentDeployFileInfo.RelativePath)"
  #   }
  #   else {
  #     $stagingPath = "$($env:OptPath)\$($CurrentDeployFileInfo.RelativePath)"
  #     # if ($FromFolder -match "\\VFT\\") {
  #     #   $stagingPath = $stagingPath -ireplace ("\\DedgePshApps\\", "\DedgePshApps\VFT\")
  #     # }
  #     # elseif ($FromFolder -match "\\VFK\\") {
  #     #   $stagingPath = $stagingPath -ireplace ("\\DedgePshApps\\", "\DedgePshApps\VFK\")
  #     # }
  #     # elseif ($FromFolder -match "\\MIG\\") {
  #     #   $stagingPath = $stagingPath -ireplace ("\\DedgePshApps\\", "\DedgePshApps\MIG\")
  #     # }
  #     # elseif ($FromFolder -match "\\SIT\\") {
  #     #   $stagingPath = $stagingPath -ireplace ("\\DedgePshApps\\", "\DedgePshApps\SIT\")
  #     # }
  #     # elseif ($FromFolder -match "\\KAT\\") {
  #     #   $stagingPath = $stagingPath -ireplace ("\\DedgePshApps\\", "\DedgePshApps\SIT\")
  #     # }
  #     # elseif ($FromFolder -match "\\FAT\\") {
  #     #   $stagingPath = $stagingPath -ireplace ("\\DedgePshApps\\", "\DedgePshApps\MIG\")
  #     # }
      
  #   }
  #   # if ($GetLegacyPath -and $stagingPath.Contains("\DedgePshApps")) {
  #   #   $stagingPath = $stagingPath.Replace("\DedgePshApps", "\Psh")
  #   # }
  # }
  # else {
  #   $stagingPath = "$($env:OptPath)\$($CurrentDeployFileInfo.RelativePath)\$($AppName)"
  # }
  if (-not (Test-Path $stagingPath -PathType Container)) {
    New-Item -Path $stagingPath -ItemType Directory -Force | Out-Null
  }
  return $stagingPath
}
function Test-DeployFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
  )

  $fileInfo = Get-Item $FilePath
  if ($fileInfo.Name.StartsWith("_QuickDeploy") -and ($fileInfo.Name.ToLower() -eq "_deploy.ps1" -or $fileInfo.Name.ToLower() -eq "deploy.bat" -or $fileInfo.Name.ToLower() -eq "deploy.cmd")) {
    return $true
  }
  return $false
}
function Test-IsModuleDeployment {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FromFolder,
    [Parameter(Mandatory = $false)]
    [string]$ApplicationTechnologyFolderName = ""
  )

  if (($FromFolder.ToLower().Contains("commonmodules") -or $FromFolder.ToLower().Contains("_modules")) -and $ApplicationTechnologyFolderName -eq "DedgePshApps") {
    return $true
  }
  return $false
}
function Test-IsDevTool {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FromFolder
    
  )

  if ($FromFolder.ToLower().Contains("devtools") -and $FromFolder.ToLower().Contains("DedgePsh")) {
    return $true
  }
  return $false
}

function Copy-SignAndBackupFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)] 
    [string]$StagingFile,
    [Parameter(Mandatory = $true)]
    [string]$UnsignedFile,
    [Parameter(Mandatory = $true)]
    [string]$FileName,
    [Parameter(Mandatory = $true)]
    [string]$FromFolder,
    [Parameter(Mandatory = $true)]
    [string]$AppName,
    [Parameter(Mandatory = $false)]
    [bool]$SkipSign = $false,
    [Parameter(Mandatory = $false)]
    [PSCustomObject]$CurrentDeployFileInfo
  )
  # Do not distribute _deploy files
  if (Test-DeployFile -FilePath $FilePath) {
    return
  }
  # Get application technology folder name

  # Make sure parent folder exists
  Add-FolderForFileIfNotExists -FileName $StagingFile
 
  # Copy file to staging location
  Copy-Item -Path $FilePath -Destination $StagingFile -Force
  if (-not $SkipSign) {
    # Sign the file using DedgeSign
    if ($StagingFile.ToLower().Contains("DedgeSign.psm1")) {
      Import-Module -Name "$($env:OptPath)\DedgePshApps\DedgeSign\DedgeSign.psm1" -Force -ErrorAction SilentlyContinue
    }
    elseif ($StagingFile.ToLower().Contains("DedgeSign")) {
      Import-Module -Name "$($env:OptPath)\src\DedgePsh\_Modules\DedgeSign\DedgeSign.psm1" -Force -ErrorAction SilentlyContinue
    }
    else {
      Import-Module -Name DedgeSign.psm1 -Force -ErrorAction SilentlyContinue
    }
    $result = Invoke-DedgeSign -Path $StagingFile -Action Add -ExecutableExtensions $CurrentDeployFileInfo.ExecutableExtensions -NoConfirm -QuietMode -Recursive
    if (-not $result) {
      Write-LogMessage "Failed to sign file: $StagingFile" -Level ERROR
      return $false
    }
    # Start-DedgeSignFile -FilePath $StagingFile
    
    # Create backup copy of unsigned file for later comparison
    Copy-Item -Path $FilePath -Destination $UnsignedFile -Force
    
    # =========================================================================================================================================
    # SPECIAL EXTRA COPY FOR POWERSHELL LEGACY PATH (Psh) - START
    # For non-DevTools files, create additional copy of signed file in PowerShell legace Psh path
    # if (-not (Test-IsDevTool -FromFolder $FromFolder) -and $applicationTechnologyFolder -eq "DedgePshApps") {
    #   # Get new path staging location and get legacy path (Psh) if PowerShell and legacy path is requested
    #   $newrelativeName = $(Get-StagingPath -FilePath $FilePath -FromFolder $FromFolder -AppName $AppName -GetLegacyPath $true) + $relativeName
      
    #   # For module deployments, update path from CommonModules to _Modules
    #   if (Test-IsModuleDeployment -FromFolder $FromFolder) {
    #     $newrelativeName = $newrelativeName.Replace("CommonModules", "_Modules")
    #   }
      
    #   # Create parent folder if it doesn't exist
    #   $newStagingFileFolder = Split-Path $newrelativeName -Parent
    #   if (-not (Test-Path $newStagingFileFolder -PathType Container)) {
    #     New-Item -Path $newStagingFileFolder -ItemType Directory -Force | Out-Null
    #   }
      
    #   # Copy signed file to PowerShell staging location
    #   Copy-Item -Path $StagingFile -Destination $newrelativeName -Force
    
    # } 
    # SPECIAL EXTRA COPY FOR POWERSHELL LEGACY PATH (Psh) - END
    # =========================================================================================================================================
  } 
}


function Copy-FilesToStaging {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string]$FromFolder,
    [Parameter(Mandatory = $false)]
    [string]$AppName,
    [Parameter(Mandatory = $false)]
    [bool]$SkipSign = $false,
    [Parameter(Mandatory = $false)]
    [PSCustomObject]$CurrentDeployFileInfo,
    [Parameter(Mandatory = $false)]
    [switch]$ForcePush
  )
  $stagingPath = Get-StagingPath -FilePath $FilePath -FromFolder $FromFolder -AppName $AppName -CurrentDeployFileInfo $CurrentDeployFileInfo
  New-Item -Path $stagingPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
  $fileName = Split-Path $FilePath -Leaf
  $relativeName = $FilePath.Substring($FromFolder.Length)
  $stagingFile = Join-Path $stagingPath $relativeName
  $unsignedFile = "$stagingFile.unsigned"

  # Create staging path if it doesn't exist
  if (-not (Test-Path $stagingPath -PathType Container)) {
    Write-LogMessage "Creating staging path $stagingPath" -Level INFO
    New-Item -Path $stagingPath -ItemType Directory -Force | Out-Null
  }
  $parentFolder = Split-Path $stagingFile -Parent
  if (-not (Test-Path $parentFolder -PathType Container)) {
    New-Item -Path $parentFolder -ItemType Directory -Force | Out-Null
  }


  # Get file extension and check if it's in executable list
  $extension = "*" + [System.IO.Path]::GetExtension($FilePath)
  $executableExtensions = $CurrentDeployFileInfo.ExecutableExtensions
  $allowedContentExtensions = $CurrentDeployFileInfo.AllowedContentExtensions


  if ($allowedContentExtensions -contains $extension) {
    if ($ForcePush) {
      Copy-Item -Path $FilePath -Destination $stagingFile -Force
      return $stagingFile
    }
    else {

      # Get hash of new file
      try {
        $newContentFileHash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction SilentlyContinue
        $newContentFileHash = $newContentFileHash.Hash
        # Get hash of unsigned file
        $oldContentFileHash = Get-FileHash -Path $stagingFile -Algorithm SHA256 -ErrorAction SilentlyContinue
        $oldContentFileHash = $oldContentFileHash.Hash
      }
      catch {
        Write-LogMessage "Error getting hash of $fileName - $($_.Exception.Message)" -Level WARN
        $oldContentFileHash = 1
        $newContentFileHash = 2
      }

      # Compare hashes
      if ($newContentFileHash -ne $oldContentFileHash) {
        if (Test-Path $stagingFile -PathType Leaf) {
          Write-LogMessage "New file      - Copying new file to staging: $fileName" -Level INFO -ForegroundColor Yellow
        }
        else {
          Write-LogMessage "Hash mismatch - Copying new version to staging: $fileName" -Level INFO -ForegroundColor Yellow
        }
        Copy-Item -Path $FilePath -Destination $stagingFile -Force
        return $stagingFile
      }
      else {
        Write-LogMessage "Content file is unchanged. Skipping..." -Level TRACE
        return $null
      }
    }
  }

  if ($executableExtensions -contains $extension) {
    # Check if unsigned file exists and compare hashes
    if ($ForcePush) {
      Copy-SignAndBackupFile  -FilePath $FilePath -StagingFile $stagingFile -UnsignedFile $unsignedFile -FileName $fileName -FromFolder $FromFolder -AppName $AppName -SkipSign $SkipSign -CurrentDeployFileInfo $CurrentDeployFileInfo
      return $stagingFile
    }
    else {
      if (-not $SkipSign) {
        if (-not (Test-Path $unsignedFile -PathType Leaf)) {
          Write-LogMessage "No .unsigned tracking file for: $($fileName) (first deploy or tracking lost)" -Level WARN
          Copy-SignAndBackupFile -FilePath $FilePath -StagingFile $stagingFile -UnsignedFile $unsignedFile -FileName $fileName -FromFolder $FromFolder -AppName $AppName -SkipSign $SkipSign -CurrentDeployFileInfo $CurrentDeployFileInfo
          return $stagingFile
        }
        # Get hash of new file
        try {
          $newFileHash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction SilentlyContinue
          $newFileHash = $newFileHash.Hash
          # Get hash of unsigned file
          $unsignedHash = Get-FileHash -Path $unsignedFile -Algorithm SHA256 -ErrorAction SilentlyContinue
          $unsignedHash = $unsignedHash.Hash
        }
        catch {
          Write-LogMessage "Error getting hash of $($stagingFile) - $($_.Exception.Message)" -Level WARN
          $newFileHash = 1
          $unsignedHash = 2
        }
        # Compare hashes
        if ($newFileHash -ne $unsignedHash) {
          Write-LogMessage "Hash mismatch - Copying new version to staging: $fileName" -Level INFO -ForegroundColor Yellow
          # Copy new file to staging and sign it
          Copy-SignAndBackupFile  -FilePath $FilePath -StagingFile $stagingFile -UnsignedFile $unsignedFile -FileName $fileName -FromFolder $FromFolder -AppName $AppName -SkipSign $SkipSign -CurrentDeployFileInfo $CurrentDeployFileInfo
          return $stagingFile
        }
        else {
          Write-LogMessage "Executable file is unchanged. Skipping: $stagingFile" -Level TRACE
          return $null
        }
      }
      else {
        try {
          $newFileHash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction SilentlyContinue
          $newFileHash = $newFileHash.Hash
          $oldFileHash = Get-FileHash -Path $stagingFile -Algorithm SHA256 -ErrorAction SilentlyContinue
          $oldFileHash = $oldFileHash.Hash
        }
        catch {
          $newFileHash = 1
          $oldFileHash = 2
        }
        if ($newFileHash -ne $oldFileHash) {
          Write-LogMessage "SkipSign - Copying file to staging without signing: $fileName" -Level INFO -ForegroundColor Yellow
          Copy-Item -Path $FilePath -Destination $stagingFile -Force
          return $stagingFile
        }
        else {
          Write-LogMessage "SkipSign - Executable file is unchanged. Skipping: $stagingFile" -Level TRACE
          return $null
        }
      }
    }
  }
  else {
    Write-LogMessage "File is not an valid file extension ($extension) for distribution of application $AppName. Removing file from staging: $stagingFile" -Level TRACE
    Remove-Item -Path $stagingFile -Force -ErrorAction SilentlyContinue
    return $null
  }


  if ($stagingFile.ToLower().Contains(".quickrun")) {
    $targetFileName = $FilePath.Split("\")[-1]
    $targetFolder = $env:OptPath + "\QuickRun"
    if (-not (Test-Path $targetFolder -PathType Container)) {
      New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
    }
    $targetPath = $targetFolder + "\" + $targetFileName.Replace(".QuickRun", "")
    Copy-Item -Path $stagingFile -Destination $targetPath -Force -ErrorAction SilentlyContinue | Out-Null
  }
  return $stagingFile
}
function Get-DeployPaths {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ComputerName,
    [Parameter(Mandatory = $true)]
    [string]$FromFolder,
    [Parameter(Mandatory = $true)]
    [PSCustomObject]$CurrentDeployFileInfo
  )

  $defaultDomain = ".DEDGE.fk.no"
  $OptPath = "\opt"
  if ($ComputerName.ToLower() -eq $env:COMPUTERNAME.ToLower()) {
    $deployPath = "$env:OptPath"
  }
  elseif ($ComputerName.Length -eq 2 -and $ComputerName.Substring(1, 1) -eq ":") {    
    $deployPath = "$env:OptPath"
  }
  else {
    $deployPath = "\\${ComputerName}${defaultDomain}${OptPath}"
  }
  
  if (-not (Test-Path $deployPath -PathType Container)) {
    Write-LogMessage " Did not find opt share for $($ComputerName). Skipping deployment to this server." -Level WARN
    throw
  }
  # Write-LogMessage "Opt share found - $ComputerName" -Level INFO

  $deployPathList = @()

  $deployPathList += "$deployPath\$($currentDeployFileInfo.RelativePath)"


  #$deployPathList += "$deployPath\$($currentDeployFileInfo.RelativePath)"

  # # Get name of current folder
  # if ($ApplicationTechnologyFolderName -eq "DedgePshApps") {
  #   if ($AppName -eq "_Modules" ) {
  #     $deployPathList += "$deployPath\DedgePshApps\CommonModules"
  #   }
  #   else {
  #     $deployPathList += "$deployPath\DedgePshApps\$AppName"   
  #   }
  #   if (-not $IsDevTools) {
  #     $deployPathList += "$deployPath\DedgePshApps\$AppName"   
  #   }
  # }
  # else {
  #   $deployPathList += "$deployPath\$ApplicationTechnologyFolderName\$AppName"
  # }

  # sort the list unique
  return $deployPathList
}
# function Get-ComputerNameList {
#   param(
#     [Parameter(Mandatory = $false)]
#     [string[]]$ComputerNameList = @() 
#   )
#   if ($ComputerNameList -is [string]) {
#     if ($ComputerNameList.Contains(',')) {
#       $ComputerNameList = @($ComputerNameList.Split(','))
#     }
#     else {
#       $ComputerNameList = @($ComputerNameList)
#     }
#   }
#   if ($ComputerNameList.Count -eq 1 -and $ComputerNameList[0] -eq '*') {
#     $ComputerNameList = Get-ServerListForPlatform -Platform "Azure"
#     $ComputerNameList = @($ComputerNameList | Where-Object { $_ -and ($_.ToLower().StartsWith("t-no1") -or $_.ToLower().StartsWith("p-no1")) })
#   }
#   elseif ($ComputerNameList.Count -eq 1 -and $ComputerNameList[0].Contains('*')) {
#     $regexPattern = $ComputerNameList[0]

#     $ComputerNameList = Get-ServerListForPlatform -Platform "Azure"
#     # Convert wildcard pattern to regex pattern
#     # Example: "*-db" becomes ".*-db$"
    
#     #check if already regex pattern
#     if (-not ($regexPattern.Contains('.*') -and -not $regexPattern.StartsWith('^') -and -not $regexPattern.EndsWith('$'))) {
#       $regexPattern = $regexPattern.Replace('*', '.*')
#       if (-not $regexPattern.EndsWith('$')) {
#         $regexPattern = "$regexPattern$"
#       }
#     }



#     $ComputerNameListNew = @()
#     Write-LogMessage "Finding computers matching regex pattern: $regexPattern" -Level INFO -ForegroundColor Yellow
#     foreach ($computerName in $ComputerNameList) {
#       if ($computerName -match $regexPattern) {
#         $ComputerNameListNew += $computerName
#         Write-LogMessage "Found computer matching regex pattern: $computerName" -Level INFO -ForegroundColor White
#       }
#     }
#     $ComputerNameList = $ComputerNameListNew
#   }
#   # Remove empty elements from ComputerNameList
#   $ComputerNameList = @($ComputerNameList | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
#   # Remove local computer from list if present
#   try {
#     $ComputerNameList = @($ComputerNameList | Where-Object { $_.ToLower() -ne $env:COMPUTERNAME.ToLower() })
#   }
#   catch {
#     $ComputerNameList = @()
#   }
#   return $ComputerNameList
# }

function Copy-FilesToSingleDeployPath2 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DeployPath,
    [Parameter(Mandatory = $true)] 
    [string]$DistributionSource,
    [Parameter(Mandatory = $true)]
    [string]$AppName,
    [Parameter(Mandatory = $true)]
    [System.Collections.ArrayList]$StagedFilesList
  )

  if ($StagedFilesList.Count -gt 0) {

    Write-LogMessage "Deploying App $AppName to $($DeployPath):" -Level INFO
    # Check file hashes between source and destination for executable files
    
    if (-not (Test-Path $DeployPath -PathType Container)) {
      # Create the folder using New-Item  
      New-Item -Path $DeployPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }
    # Use robocopy to copy files:
    # /S      - Copy subdirectories, excluding empty ones
    # /XF     - Exclude files matching these names
    # /XO     - Exclude older files (only copy newer)
    # /R:3    - Retry 3 times on fail
    # /W:5    - Wait 5 seconds between retries
    # /NP     - No progress indicator
    # /NDL    - No directory list
    # /NC     - No class summary
    # /NS     - No size summary
    # /NFL    - No file list
    robocopy "$DistributionSource" "$DeployPath" /S /XF *.unsigned deploy*.ps1 deploy*.bat deploy*.cmd /XO /R:3 /W:5 /NP /NDL /NC /NS /NFL
    Write-LogMessage "Deployed to $DeployPath" -Level INFO
  }    
}

function Copy-FilesToSingleDeployPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DeployPath,
    [Parameter(Mandatory = $true)] 
    [string]$DistributionSource,
    [Parameter(Mandatory = $true)]
    [string]$AppName,
    [Parameter(Mandatory = $true)]
    [System.Collections.ArrayList]$StagedFilesList,
    [Parameter(Mandatory = $false)]
    [bool]$ForcePush = $true,
    [Parameter(Mandatory = $false)]
    [string]$ApplicationTechnologyFolderName = ""
  )

  if ($StagedFilesList.Count -gt 0) {

    Write-LogMessage "Deploying App $AppName to $($DeployPath):" -Level INFO
    if ($ForcePush -eq $false) {
      # Check file hashes between source and destination for executable files
      $allHashesMatch = $true
      if (Test-Path $DeployPath -PathType Container) {
        if ($ApplicationTechnologyFolderName -eq "DedgePshApps" -or $ApplicationTechnologyFolderName -eq "DedgeWinApps") {
          $allowedContentExtensions = Get-ExecutableExtensions
        }
        else {
          $allowedContentExtensions = @(".*")
        }
  
        foreach ($extension in $allowedContentExtensions) {
          $sourceFiles = Get-ChildItem -Path $DistributionSource -Filter "*$extension" -Recurse
          foreach ($sourceFile in $sourceFiles) {
            $relativePath = $sourceFile.FullName.Substring($DistributionSource.Length)
 
            $destFile = Join-Path $DeployPath $relativePath
            if (Test-Path $destFile -PathType Leaf) {
              $sourceHash = Get-FileHash -Path $sourceFile.FullName -Algorithm SHA256
              $destHash = Get-FileHash -Path $destFile -Algorithm SHA256
              if ($sourceHash.Hash -ne $destHash.Hash) {
                #Write-Log "Different version of $($sourceFile.Name) detected in $DeployPath. Deploying..." -ForegroundColor Yellow
                $allHashesMatch = $false
                break
              }
            }
            else {
              $allHashesMatch = $false
              break
            }
          }
          if (-not $allHashesMatch) {
            break
          }
        }
      }
      else {
        $allHashesMatch = $false
      }
      if ($allHashesMatch) {
        Write-LogMessage "No changes detected for $DeployPath" -Level INFO
        return
      }

      if (Test-Path $DeployPath -PathType Container) {
        if ($DeployPath.ToLower().Contains("\psh")) { 
          Write-LogMessage "Skipping removal of files in $DeployPath because it is a PSH folder." -Level INFO
        }
        else {
          Write-LogMessage "Removing all files in $DeployPath" -Level INFO
          Get-ChildItem -Path $DeployPath -Include (Get-ExecutableExtensions) -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue | Out-Null
        }
      }
      else {  
        # Create the folder using New-Item  
        New-Item -Path $DeployPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
      }
    }
    Copy-Item -Path "$DistributionSource\*" -Destination $DeployPath -Recurse -Force -Exclude "*.unsigned", "_deployAll.ps1", "_deploy.ps1" , "_deploy.bat" , "_deploy.cmd" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Item (Join-Path $DeployPath $_.Name) -ErrorAction SilentlyContinue).LastWriteTime }
    Write-LogMessage "Deployed to $DeployPath" -Level INFO
  }    
  
}

function Deploy-FilesInternal {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$FromFolder,

    [Parameter(Mandatory = $true)]
    [PSCustomObject]$CurrentDeployFileInfo,

    [Parameter(Mandatory = $false)]
    [string[]]$Files = @(),

    [Parameter(Mandatory = $false)]
    [string[]]$ComputerNameList = "",

    [Parameter(Mandatory = $false)]
    [bool]$SkipSign = $false,

    [Parameter(Mandatory = $false)]
    [switch]$ForcePush

  )

  try {
    if ($Files -is [string]) {
      $Files = @($Files)
    }

    $addPathElement = ""

    if ($currentDeployFileInfo.SourceFolder.ToLower().Contains("\forsprang\")) {
      if ($currentDeployFileInfo.SourceFolder.ToLower().Contains("\_prd\")) {
        $addPathElement = ""
      }
      elseif ($currentDeployFileInfo.SourceFolder.ToLower().Contains("\_per\")) {
        $addPathElement = "_PER"
      }
      elseif ($currentDeployFileInfo.SourceFolder.ToLower().Contains("\_kat\")) {
        $addPathElement = "_KAT"
      } 
      elseif ($currentDeployFileInfo.SourceFolder.ToLower().Contains("\_vfk\")) {
        $addPathElement = "_VFK"
      }
      elseif ($currentDeployFileInfo.SourceFolder.ToLower().Contains("\_vft\")) {
        $addPathElement = "_VFT"
      }
      elseif ($currentDeployFileInfo.SourceFolder.ToLower().Contains("\_fut\")) {
        $addPathElement = "_FUT"
      }
      elseif ($currentDeployFileInfo.SourceFolder.ToLower().Contains("\_sit\")) {
        $addPathElement = "_SIT"
      }
      elseif ($currentDeployFileInfo.SourceFolder.ToLower().Contains("\_mig\")) {
        $addPathElement = "_MIG"
      }
  
    }
  
  
    if ($addPathElement -ne "") {
      $substring1 = $currentDeployFileInfo.RelativePath.Substring(0, $currentDeployFileInfo.RelativePath.IndexOf("\"))
      $substring2 = $currentDeployFileInfo.RelativePath.Substring($currentDeployFileInfo.RelativePath.IndexOf("\") + 1)
      $currentDeployFileInfo.RelativePath = "$substring1\$addPathElement\$substring2"
    }
    Add-Member -InputObject $currentDeployFileInfo -MemberType NoteProperty -Name "DistributionSource" -Value "$($env:OptPath)\$($currentDeployFileInfo.RelativePath)"

    $ComputerNameList = Get-ComputerNameList -ComputerNameList $ComputerNameList

    # Get resolved files based on the files and fromfolder
    $Files = Get-ResolvedFiles -FromFolder $FromFolder -Files $Files

    
    $stagedFilesList = @()
  
    # Get the apps module path
    $deploymentAppPath = $currentDeployFileInfo.DistributionSource

    if (Test-Path $deploymentAppPath) {
      # Get all files recursively in apps module folder
      $appsFiles = Get-ChildItem -Path $deploymentAppPath -Recurse -File

      foreach ($appsFile in $appsFiles) {
        # Skip .unsigned files
        if ($appsFile.Name.EndsWith('.unsigned') -or $appsFile.Name.Contains('_old') -or $appsFile.Name.Contains('_deploy.ps1')) {
          continue
        }

        # Get relative path from apps module root
        $relativePath = $appsFile.FullName.Substring($deploymentAppPath.Length + 1)
      
        # Check if file exists in FromFolder
        $sourceFile = Join-Path $FromFolder $relativePath
        $sourceFileUnsigned = $sourceFile + '.unsigned'

        if (-not (Test-Path $sourceFile) -and -not (Test-Path $sourceFileUnsigned) -and -not ($appsFile.Name -like "*.version")) {
          Write-LogMessage "Removing obsolete file: $($appsFile.FullName)" -Level INFO
          Remove-Item $appsFile.FullName -Force -ErrorAction SilentlyContinue
          Write-Progress -Completed -ErrorAction SilentlyContinue
        }
      }

      if ($ForcePush) {
        # Clean up empty directories
        $removeFiles = Get-ChildItem -Path $deploymentAppPath -Recurse -File
        
        $removeFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Progress -Completed -ErrorAction SilentlyContinue

      }
      # Clean up empty directories
      Get-ChildItem -Path $deploymentAppPath -Recurse -Directory | 
      Where-Object { $null -eq (Get-ChildItem -Path $_.FullName -Recurse -File) } |
      Sort-Object -Property FullName -Descending |
      Remove-Item -Force -ErrorAction SilentlyContinue
      Write-Progress -Completed -ErrorAction SilentlyContinue

    }

    $executableExtensions = $CurrentDeployFileInfo.ExecutableExtensions
    $allowedContentExtensions = $CurrentDeployFileInfo.AllowedContentExtensions
  
  
    foreach ($file in $Files) {
      try {
        $extension = [System.IO.Path]::GetExtension($file).ToLower()
        $extension = "*" + $extension
        if ($executableExtensions -notcontains $extension -and $allowedContentExtensions -notcontains $extension) {
          Write-LogMessage "Skipping file: $file" -Level TRACE
          continue
        }
        if ($file -like "*_old*") {
          Write-LogMessage "Skipping old file: $file" -Level TRACE
          continue
        }
        if ($file -like "*_deploy.ps1*") {
          Write-LogMessage "Skipping deploy script: $file" -Level TRACE
          continue
        }
       
        # Process file to staging path(s), sign them if needed and copy them to the staging paths
        $stagedFileResult = Copy-FilesToStaging -FilePath $file -FromFolder $FromFolder -AppName $appName -SkipSign $SkipSign -CurrentDeployFileInfo $CurrentDeployFileInfo -ForcePush:$ForcePush
        if ($null -ne $stagedFileResult) {
          $stagedFilesList += $stagedFileResult
        }      
      }
      catch {
        Write-LogMessage "Failed to copy file $($file)" -Level ERROR -Exception $_
      }
    }
    # create a timestamp file in the staging path
    $localStagingPath = Join-Path $env:OptPath $CurrentDeployFileInfo.RelativePath
    # check if the version file exists in the staging path
    
    $versionFile = Get-ChildItem -Path $localStagingPath -Filter "*.version" -Force -ErrorAction Stop | Select-Object -First 1
    if ($stagedFilesList.Count -gt 0 -or -not (Test-Path $versionFile)) {
      Get-ChildItem -Path $localStagingPath -Filter "*.version" -Force -ErrorAction Stop | Remove-Item -Force -ErrorAction Stop
      Write-Progress -Completed -ErrorAction SilentlyContinue

      $timestamp = Get-Date -Format "yyyyMMddHHmmssfff"
      $localStagingPath = Join-Path $env:OptPath $CurrentDeployFileInfo.RelativePath
      $versionFile = Join-Path $localStagingPath "$($CurrentDeployFileInfo.AppName)-$timestamp.version"
      New-Item -Path $versionFile -ItemType File -Force -ErrorAction Stop | Out-Null
      Write-LogMessage "New version detected and signed. Created version file $versionFile" -Level INFO -ForegroundColor Green
    }
    else {
      Write-LogMessage "No new files to deploy" -Level INFO
    }
  
    Write-LogMessage "All local files signed and deployed locally and are ready for distribution" -Level INFO

    # Get deploy paths for the remote computer
    $deployPathList = @()
    if ($ComputerNameList.Count -ne 0) {
      Write-LogMessage "Checking if opt share exists " -Level INFO
      foreach ($computer in $ComputerNameList) {
        try {
          $deployPathList += Get-DeployPaths -ComputerName $computer -FromFolder $FromFolder -CurrentDeployFileInfo $CurrentDeployFileInfo
        }
        catch {
          Write-LogMessage "Failed to get deploy paths for $($computer). Skipping..." -Level WARN
        }
      }
    }

    $tempList = @()
    $tempList += "$(Get-SoftwarePath)\$($currentDeployFileInfo.RelativePath)"

    $deployPathList = @($deployPathList | Sort-Object -Unique)
    $tempList += $($deployPathList | ForEach-Object { $_.ToString() })
    $deployPathList = $tempList

    if ($deployPathList.Count -eq 0) {
      Write-LogMessage "No valid deploy paths found" -Level ERROR
      throw
    }
     
    #$distributionSource = "$($env:OptPath)\$($currentDeployFileInfo.RelativePath)"
    $distributionSource = $currentDeployFileInfo.DistributionSource
    $resultObjects = @()

    try {
      # $Debug = $true
      $resultObjects += Copy-FilesToDeployPaths -DeployPathList $deployPathList -DistributionSource $distributionSource -AppName $appName -ForcePush $ForcePush -CurrentDeployFileInfo $CurrentDeployFileInfo
    }
    catch {
      Write-LogMessage "Deployment failed for $($appName)" -Level ERROR -Exception $_
      throw  
    }
    return $resultObjects
  }
  catch {
    Write-LogMessage "Deployment failed for $($FromFolder)" -Level ERROR -Exception $_
    throw
  }
}


function Deploy-Files {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$FromFolder,

    [Parameter(Mandatory = $false)]
    [string[]]$Files = @(),

    [Parameter(Mandatory = $false)]
    [string[]]$ComputerNameList = "",

    [Parameter(Mandatory = $false)]
    [bool]$SkipSign = $false,

    [Parameter(Mandatory = $false)]
    [bool]$DeployModules = $true,

    [Parameter(Mandatory = $false)]
    [switch]$ForcePush,

    [Parameter(Mandatory = $false)]
    [switch]$PlaySound,

    [Parameter(Mandatory = $false)]
    [switch]$OutputList,

    [Parameter(Mandatory = $false)]
    [switch]$ShowTransferReport
  )
  # Override parameters
  $PlaySound = $true
  $ShowTransferReport = $true

  $env:DedgeSignDedgePsh = $true
  $env:DedgeSignQuietMode = $true

  
  Write-LogMessage "Deploying files from $FromFolder. Parameters: SkipSign: $SkipSign, DeployModules: $DeployModules, ForcePush: $ForcePush, ComputerNameList: $($ComputerNameList -join ', ')" -Level TRACE
  $startTime = Get-Date
  # Get last directory in FromFolder
  $currentDeployFileInfo = Get-SourceFolderFileInfo -SourceFolder $FromFolder

  if ($null -eq $DeployModules) {
    if ($currentDeployFileInfo.SkipModuleDeployment) {
      $DeployModules = $false
    }
    else {
      $DeployModules = $true
    }
  }

  
  if ($null -eq $SkipSign) {
    if ($currentDeployFileInfo.SkipSign) {
      $SkipSign = $false
    }
    else {
      $SkipSign = $true
    }
  }

  
  $lineLength = 70
  $appName = $CurrentDeployFileInfo.AppName
  $titleLine = "Deploying $($CurrentDeployFileInfo.AppTechnology) - $($appName)"
  $paddingLength = ($lineLength - $titleLine.Length) / 2

  Write-Host ("=" * $lineLength) -ForegroundColor Cyan
  Write-Host (" " * $paddingLength) $titleLine -ForegroundColor White
  Write-Host ("=" * $lineLength) -ForegroundColor Cyan



  $resultObjects = @()
  if ($DeployModules -eq $true -and $currentDeployFileInfo.AppName -ne "CommonModules" -and $currentDeployFileInfo.AppTechnology -eq "PowerShell") {
    $currentDeployFileInfoModules = Get-SourceFolderFileInfo -SourceFolder "$($env:OptPath)\src\DedgePsh\_Modules"
    $resultObjects += Deploy-FilesInternal -FromFolder "$($env:OptPath)\src\DedgePsh\_Modules" -ComputerNameList $ComputerNameList -SkipSign $SkipSign -ForcePush:$ForcePush -CurrentDeployFileInfo $currentDeployFileInfoModules
  }


  $resultObjects += Deploy-FilesInternal -FromFolder $FromFolder -Files $Files -ComputerNameList $ComputerNameList -SkipSign $SkipSign -ForcePush:$ForcePush -CurrentDeployFileInfo $currentDeployFileInfo
  $duration = (Get-Date) - $startTime
  if ($OutputList) {
    $resultObjects | Format-List -Property AppName, DeployFolder, ResultMessage, ElapsedTime, RobocopyExitCode, TotalFiles, QuickRunDeployed
  }
  else {
    $resultObjects | Format-Table -Property AppName, DeployFolder, ResultMessage, ElapsedTime, RobocopyExitCode, TotalFiles, QuickRunDeployed -AutoSize
  }
  Write-Progress -Completed -ErrorAction SilentlyContinue

  if ($ShowTransferReport -or $ForcePush) {
    $mergedResultObjects = @()
    foreach ($resultObject in $resultObjects) {
      $mergedResultObjects += $resultObject.ChangedFiles
    }
    $mergedResultObjects = $mergedResultObjects | Sort-Object -Property DestinationFolder, DestinationFileName
    $output = $mergedResultObjects | Format-Table -Property SourceFolder, SourceFileName, DestinationFolder, DestinationFileName, Transferred -AutoSize | Out-String
    $outputTotal = "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------`n"
    $outputTotal += "                                                               Transferred status report`n"
    $outputTotal += $output
    $outputTotal += "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------`n"

    
    $outputArray = $outputTotal.Split("`n")
    # Set line green or red depending on Transferred while printing to console
    foreach ($row in $outputArray) {
      if ($row.Trim().EndsWith("True")) {
        $color = "Green"
      }
      elseif ($row.Trim().EndsWith("False")) {
        $color = "Red"
      }
      elseif ($row.Trim().StartsWith("-----")) {
        $color = "Cyan"
      }
      elseif ($row.Trim().StartsWith("SourceFolder")) {
        $color = "White"
      }
      elseif ($row.Trim().StartsWith("Transferred")) {
        $color = "White"
      }
      else {
        $color = "Cyan"
      }
      Write-Host $row -ForegroundColor $color
    }

  }
  Write-LogMessage "Deployed $($currentDeployFileInfo.AppName) in $($duration.TotalSeconds) seconds" -Level INFO

  if ($PlaySound) {
    $null = Start-PlaySound -SoundName "Notify"
  }
}


<#
.SYNOPSIS
    Executes a ScriptBlock either locally or in a remote PowerShell session.

.DESCRIPTION
    This function provides a unified way to execute PowerShell ScriptBlocks either locally or in a remote session.
    It handles argument passing and session management automatically.

.PARAMETER ScriptBlock
    The ScriptBlock to execute.

.PARAMETER Session
    Optional PSSession object for remote execution.

.PARAMETER ArgumentList
    Optional array of arguments to pass to the ScriptBlock.

.EXAMPLE
    $scriptBlock = { param($name) Write-LogMessage "Hello $name" -Level INFO }
    Invoke-ScriptBlockWithSession -ScriptBlock $scriptBlock -ArgumentList "World"
    # Executes the script block locally with arguments

.EXAMPLE
    $session = New-PSSession -ComputerName "server01"
    Invoke-ScriptBlockWithSession -ScriptBlock { Get-Process } -Session $session
    # Executes the script block in a remote session
#>
function Invoke-ScriptBlockWithSession {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [scriptblock]$ScriptBlock,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.Runspaces.PSSession]$Session,

    [Parameter(Mandatory = $false)]
    [object[]]$ArgumentList
  )

  if ($Session) {
    if ($ArgumentList) {
      return Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
    else {
      return Invoke-Command -Session $Session -ScriptBlock $ScriptBlock
    }
  }
  else {
    if ($ArgumentList) {
      return & $ScriptBlock @ArgumentList
    }
    else {
      return & $ScriptBlock
    }
  }
}

  
function Get-TestFolderExistance {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Path
  )
  Write-LogMessage "Checking if $Path exists" -Level INFO
  return Test-Path $Path -PathType Container
}

function Get-PotentialOptDrive {
  Write-LogMessage "Attempting to get potential opt drive" -Level INFO
  $optDriveList = @("E:\", "D:\", "C:\")

  foreach ($currentItem in $optDriveList) {  
    $exists = Get-TestFolderExistance -Path $currentItem
    if ($exists) {
      return $currentItem
    }
  }
  return $null
}

function Set-UICustomization {
  # Set server info wallpaper
  Set-ServerInfoWallpaper
  # Modify Windows Schema to be dark mode
  Write-LogMessage "Setting Windows Schema to dark mode..." -Level INFO
  Set-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name AppsUseLightTheme -Value 0
  Set-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name SystemUsesLightTheme -Value 0
}

function Set-WindowsSystemSettings {
  param (
    [Parameter(Mandatory = $false)]
    [bool]$IsWorkstation = $false
  )
  Write-LogMessage "Setting Windows system settings..." -Level INFO
  
  # Query 8.3 filename generation status
  # Write-Host "Checking 8.3 filename generation status..." -ForegroundColor White
  # $result = & fsutil 8dot3name query
  # Write-Host $result -ForegroundColor Gray
  # Write-Host "Setting 8.3 filename generation to off..." -ForegroundColor White
  # 0: Enables 8dot3 name creation for all volumes on the system.
  # 1: Disables 8dot3 name creation for all volumes on the system.
  # 2: Sets 8dot3 name creation on a per volume basis.
  # 3: Disables 8dot3 name creation for all volumes except the system volume.
  #& fsutil 8dot3name set 0
  
  # Expand Explorer context menu to show all developer options
  Write-LogMessage "Expanding Explorer context menu..." -Level INFO
  Write-LogMessage "Configuring Explorer context menu for developer options..." -Level INFO

  # Show file extensions
  Write-LogMessage "Showing file extensions in Explorer..." -Level INFO
  Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0

  # Show hidden files
  Write-LogMessage "Showing hidden files in Explorer..." -Level INFO
  Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1

  # Show full path in title bar
  Write-LogMessage "Showing full path in title bar..." -Level INFO
  New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Force -ErrorAction SilentlyContinue | Out-Null
  Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -Name "FullPath" -Value 1 -ErrorAction SilentlyContinue | Out-Null

  # Expand context menu completely
  Write-LogMessage "Expanding context menu completely..." -Level INFO

  # Method 1: Try registry modification for Windows 11 style
  $registryPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
  if (-not (Test-Path $registryPath)) {
    try {
      New-Item -Path $registryPath -Force | Out-Null
      Set-ItemProperty -Path $registryPath -Name "(Default)" -Value "" -Force
      Write-LogMessage "Successfully configured expanded context menu (Windows 11 method)" -Level INFO
    }
    catch {
      Write-LogMessage "Failed to set expanded context menu using Windows 11 method" -Level ERROR
    }
  }

  # Method 2: Alternative registry key for older Windows versions
  $legacyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
  if (Test-Path $legacyPath) {
    try {
      Set-ItemProperty -Path $legacyPath -Name "EnableFullContextMenu" -Value 1 -ErrorAction Stop
      Write-LogMessage "Successfully configured expanded context menu (Legacy method)" -Level INFO
    }   
    catch {
      Write-LogMessage "Failed to set expanded context menu using legacy method" -Level ERROR
    }
  }
  Write-LogMessage "Note: Changes will take effect after Explorer restart or system reboot" -Level INFO

}

function Restart-Machine {
  param (
    [Parameter(Mandatory = $false)]
    [bool]$Force = $false
  )
  # Prompt user for restart
  if (-not $Force) {
    Write-LogMessage "Done! Please restart your computer to apply all changes. Would you like to restart now? (y/n)" -Level INFO
    $response = Read-Host
  }


  if ($response -eq 'y' -or $Force) {
    # Wait 15 seconds to allow user to abort
    Write-LogMessage "Waiting 15 seconds before restart. Press Ctrl+C to abort..." -Level WARN
    for ($i = 15; $i -gt 0; $i--) {
      Write-Host "Restarting in $i seconds..." -NoNewline
      Start-Sleep -Seconds 1
      Write-Host "`r" -NoNewline
    }
    Write-Host ""
    Restart-Computer -Force
  }
  else {
    Write-LogMessage "Please remember to restart your computer later." -Level INFO
  }  
}

function Set-CommonSettings {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $false)]
    [string[]]$AdditionalAdmins = @(),
    [Parameter(Mandatory = $false)]
    [string]$EveryonePermission = "Read",
    [Parameter(Mandatory = $false)]
    [bool]$IsWorkstation = $false
  )
  
  $originalAdditionalAdmins = $AdditionalAdmins
  $AdditionalAdmins = Get-AdditionalAdmins -AdditionalAdmins $AdditionalAdmins
  Add-Folder -Path $env:OptPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission $EveryonePermission -IsWorkstation $IsWorkstation
  #Add-SharedFolder -Path $env:OptPath -ShareName "Opt" -Description "Shared folder for Opt" -AdditionalAdmins $AdditionalAdmins -EveryonePermission $EveryonePermission
  Add-SmbSharedFolder -Path $env:OptPath -ShareName "Opt" -Description "Shared folder for Opt"  -AdditionalAdmins $AdditionalAdmins 
  
  $dataPath = "$env:OptPath\Data"
  Write-LogMessage "Adding folder $dataPath" -Level INFO
  Add-Folder -Path $dataPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission $EveryonePermission -IsWorkstation $IsWorkstation
  try {
    $quickRunPath = "$env:OptPath\QuickRun"
    Write-LogMessage "Adding folder $quickRunPath" -Level INFO
    Add-Folder -Path $quickRunPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission $EveryonePermission -IsWorkstation $IsWorkstation
    Remove-PathFromEnvironmentPathVariable -Path $quickRunPath -Target "Machine"
    Remove-PathFromEnvironmentPathVariable -Path $quickRunPath -Target "User"
    Add-PathToEnvironmentPathVariable -Path $quickRunPath -Target "Machine"
    Add-PathToEnvironmentPathVariable -Path $quickRunPath -Target "User"
  }
  catch {
    Write-LogMessage "Failed to add $quickRunPath to environment path" -Level ERROR 
  }
  
  $agentPath = "$env:OptPath\Agent"
  Write-LogMessage "Adding folder $agentPath" -Level INFO
  Add-Folder -Path $agentPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission "" -IsWorkstation $IsWorkstation

  $pshPath = "$env:OptPath\Psh"
  Write-LogMessage "Adding folder $pshPath" -Level INFO
  Add-Folder -Path $pshPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission "" -IsWorkstation $IsWorkstation

  $appsPath = "$env:OptPath\DedgePshApps"
  Write-LogMessage "Adding folder $appsPath" -Level INFO
  Add-Folder -Path $appsPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission "" -IsWorkstation $IsWorkstation

  $appsPath = "$env:OptPath\DedgeWinApps"
  Write-LogMessage "Adding folder $appsPath" -Level INFO
  Add-Folder -Path $appsPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission "" -IsWorkstation $IsWorkstation

  $appsPath = "$env:OptPath\Programs"
  Write-LogMessage "Adding folder $appsPath" -Level INFO
  Add-Folder -Path $appsPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission "" -IsWorkstation $IsWorkstation

  $workPath = "$env:OptPath\Work"
  Write-LogMessage "Adding folder $workPath" -Level INFO
  Add-Folder -Path $workPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission "" -IsWorkstation $IsWorkstation
  
  $websPath = "$env:OptPath\Webs"
  Write-LogMessage "Adding folder $websPath" -Level INFO
  Add-Folder -Path $websPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission "ReadAndExecute" -IsWorkstation $IsWorkstation
  
  $tempFkPath = "C:\TEMPFK"
  Write-LogMessage "Adding folder $tempFkPath" -Level INFO
  Add-Folder -Path $tempFkPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission $EveryonePermission -IsWorkstation $IsWorkstation

  $quickRunPath = "$env:OptPath\QuickRun"
  Write-LogMessage "Adding folder QuickRun that will be added to PATH" -Level INFO
  Add-Folder -Path $quickRunPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission "ReadAndExecute" -IsWorkstation $IsWorkstation
  
  
  # Add privileges for all local drives
  foreach ($disk in $(Get-DiskInfo)) {
    if ($disk.DeviceID -eq "C:") {
      continue
    }
    $driveLetter = $disk.DeviceID + "\"
    Write-LogMessage "Adding privileges for drive $driveLetter" -Level INFO
    Add-Privilege -Path $driveLetter -AdditionalAdmins $originalAdditionalAdmins -EveryonePermission ""
  }

  $optUncPath = "\\" + $env:COMPUTERNAME.Trim().ToLower() + "\opt"
  [System.Environment]::SetEnvironmentVariable("OptUncPath", $optUncPath, [System.EnvironmentVariableTarget]::Machine)
  Set-WindowsSystemSettings -IsWorkstation $IsWorkstation

}
function Get-AdditionalAdmins {
  param (
    [Parameter(Mandatory = $false)]
    [string[]]$AdditionalAdmins = @()
  )
  if (-not $AdditionalAdmins) {
    $AdditionalAdmins = @()
  }
  
  $AdditionalAdmins += $env:USERDOMAIN + "\" + $env:USERNAME
  if (Test-IsServer) {
    $generatedAdmin = Get-OldServiceUsernameFromServerName
    if ($generatedAdmin) {
      Write-LogMessage "Generated admin: $generatedAdmin" -Level INFO
      $AdditionalAdmins += "$env:USERDOMAIN\$generatedAdmin"
    }
    
    if ($env:COMPUTERNAME.ToLower().Contains("prd")) {
      $AdditionalAdmins += "$env:USERDOMAIN\srverp13"
      $AdditionalAdmins += "$env:USERDOMAIN\FKPRDADM"
    }
    elseif ($env:COMPUTERNAME.ToLower().Contains("dev")) {
      $AdditionalAdmins += "$env:USERDOMAIN\srverp13"
      $AdditionalAdmins += "$env:USERDOMAIN\FKDEVADM"
    } 
    else {
      $AdditionalAdmins += "$env:USERDOMAIN\srverp13"
      $AdditionalAdmins += "$env:USERDOMAIN\FKPRDADM"
      $AdditionalAdmins += "$env:USERDOMAIN\FKDEVADM"
      $AdditionalAdmins += "$env:USERDOMAIN\FKTSTADM"
    }
    # $AdditionalAdmins += "$env:COMPUTERNAME\Administrators"
    $AdditionalAdmins += "$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full"
    $AdditionalAdmins += "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere"
  }
  else {
    $AdditionalAdmins += "$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full"
    $AdditionalAdmins += "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere"
  }
  
  $AdditionalAdmins = $AdditionalAdmins | Select-Object -Unique
  Write-LogMessage "Additional admins: $($AdditionalAdmins -join "`n")" -Level DEBUG
  return $AdditionalAdmins
}
function Initialize-Server {
  param (
    [Parameter(Mandatory = $false)]
    [string[]]$AdditionalAdmins = @(),
    [Parameter(Mandatory = $false)]
    [bool]$SkipWinInstall = $false
  )

  $appdataPath = Get-ApplicationDataPath
  Set-OverrideAppDataFolder -Path $appdataPath


  Write-Progress -Completed -ErrorAction SilentlyContinue
  
  Remove-Item -Path "$env:OptPath\DedgePshApps\Agent-HandlerAutoDeploy" -Recurse -Force -ErrorAction SilentlyContinue
  Write-Progress -Completed -ErrorAction SilentlyContinue

  Write-LogMessage "Starting server initialization" -Level INFO
  Write-LogMessage "Log files: $($global:LogFiles -join "`n")" -Level INFO


  try {
    #######################################################################################################
    # Initial configuration
    #######################################################################################################
    $AdditionalAdmins = Get-AdditionalAdmins -AdditionalAdmins $AdditionalAdmins

    Write-LogMessage "Initializing local server setup" -Level INFO
    Add-CurrentComputer -AutoConfirm $true -Type "Server" -Environments $environments -Purpose "FK server undecided" -Comments "" -Applications $applications
    
    $everyonePermission = "Read"
    Write-LogMessage "Adding folders, shares, environment variables and privileges" -Level INFO

    try {
      Set-CommonSettings -AdditionalAdmins $AdditionalAdmins -EveryonePermission $everyonePermission -IsWorkstation $false
    }
    catch {
      Write-LogMessage "Failed to set common settings" -Level ERROR -Exception $_
    }
    
    try {
      Add-CommonNetworkDrives
    }
    catch {
      Write-LogMessage "Failed to add common network drives" -Level ERROR -Exception $_
    }
    
    #######################################################################################################
    # Applications and configuration for all servers
    #######################################################################################################
    $installWindowsApps = @()
    $installWingetApps = @("Microsoft.DotNet.SDK.8", "Notepad++.Notepad++", "Git.Git")      
    $installWindowsApps += @("VSCode System-Installer")
    $installDedgePshApps = @(
      "Db2-Commands",
      "Get-App",
      "Add-Task",
      "Refresh-ServerSettings", 
      "Init-Machine",
      #"Map-CommonNetworkDrives",
      "Run-Psh",
      "Inst-Psh",
      "Chg-Pass",
      "Send-Sms",
      "Db2-CreateDb2CliShortCuts",
      "AddFkUserAsLocalAdmin"    )
    if (-not $env:COMPUTERNAME.ToUpper().Contains("-DB")) {
      $installDedgePshApps += @("Db2-AutoCatalog")
    }
    # Add the Map-Drv.bat script to run at user logon
    
    #######################################################################################################
    # Distribution of MicroFocus Server Pack licences
    #######################################################################################################
    if (($env:COMPUTERNAME.ToUpper().Contains("FKM") -and $env:COMPUTERNAME.ToUpper().Contains("TST") -and $env:COMPUTERNAME.ToUpper().Contains("APP")) -or # 1 Core
      ($env:COMPUTERNAME.ToUpper().Contains("FKM") -and $env:COMPUTERNAME.ToUpper().Contains("TST") -and $env:COMPUTERNAME.ToUpper().Contains("SOA")) -or # 1 Core   
      ($env:COMPUTERNAME.ToUpper().Contains("FKM") -and $env:COMPUTERNAME.ToUpper().Contains("VCT") -and $env:COMPUTERNAME.ToUpper().Contains("APP")) -or # 1 Core
      ($env:COMPUTERNAME.ToUpper().Contains("FKM") -and $env:COMPUTERNAME.ToUpper().Contains("VCT") -and $env:COMPUTERNAME.ToUpper().Contains("SOA")) -or # 1 Core
      ($env:COMPUTERNAME.ToUpper().Contains("FKM") -and $env:COMPUTERNAME.ToUpper().Contains("FSP") -and $env:COMPUTERNAME.ToUpper().Contains("APP")) -or # 1 Core
      ($env:COMPUTERNAME.ToUpper().Contains("INL") -and $env:COMPUTERNAME.ToUpper().Contains("PRD") -and $env:COMPUTERNAME.ToUpper().Contains("APP")) -or # 1 Core
      ($env:COMPUTERNAME.ToUpper().Contains("FKM") -and $env:COMPUTERNAME.ToUpper().Contains("PRD") -and $env:COMPUTERNAME.ToUpper().Contains("APP")) -or # 3 Core
      ($env:COMPUTERNAME.ToUpper().Contains("FKM") -and $env:COMPUTERNAME.ToUpper().Contains("PRD") -and $env:COMPUTERNAME.ToUpper().Contains("SOA"))     # 1 Core
    ) {
      $installWindowsApps += @("MicroFocus Server Pack")
    }

    #######################################################################################################
    # Applications and configuration for database servers
    #######################################################################################################
    if ($env:COMPUTERNAME.ToUpper().EndsWith("DB")) {
      # For FKM production DB servers, install both Community and Standard editions
      if ($env:COMPUTERNAME.ToUpper().Contains("FKM") -and $env:COMPUTERNAME.ToUpper().Contains("PRD") ) {
        $installWindowsApps += "Db2 Server 12.1 Standard Edition"
      }
      # For all other DB servers, only install Community edition
      else {
        $installWindowsApps += "Db2 Server 12.1 Community Edition"
      }

      # Add DB2-specific PowerShell apps to install
      $installDedgePshApps += @(
        "Db2-Commands",
        "Db2-CreateDb2CliShortCuts",
        "Db2-CreateInitialDatabases",
        "Db2-DiagArchive",
        "Db2-DiagnoseConnect",
        "Db2-DiagInstanceFolderShare",
        "Db2-ErrorDiagnosisReport",
        "Db2-ExportServerConfig",
        "Db2-FederationHandler",
        "Db2-GrantHandler",
        "Db2-GrantsImport",
        "Db2-GrantsExport",
        "Db2-LargeTableYearSplit",
        "Db2-Restore",
        "Db2-StandardConfiguration",
        "Db2Server-InstallHandler"        
      )

      # Set up DB restore folder path - prefer F: drive if available, otherwise use E:
      if (Test-Path "F:" -PathType Container) {
        $path = Join-Path "F:" "Db2Restore"
      }
      else {
        $path = Join-Path "E:" "Db2Restore"
      }

      # Create folder and share for DB restores with appropriate permissions
      Add-Folder -Path $path -AdditionalAdmins $AdditionalAdmins
      # Add-SharedFolder -Path $path -ShareName "Db2Restore" -Description "Db2Restore is a shared folder for Db2 restore files" -AdditionalAdmins @(
      #   "$env:USERDOMAIN\$env:USERNAME",
      #   "$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full",
      #   "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere"
      # )
      Add-SmbSharedFolder -Path $path -ShareName "Db2Restore" -Description "Db2Restore is a shared folder for Db2 restore files"  -AdditionalAdmins $AdditionalAdmins 


      # For INL DB servers, add the Fkkonto local group
      if ($env:COMPUTERNAME.ToUpper().Contains('INL')) {
        $WorkObject = [PSCustomObject]@{AdminUsers = $AdditionalAdmins }
        $WorkObject = Remove-FkkontoLocalGroup -WorkObject $WorkObject  
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
        $WorkObject = Add-FkkontoLocalGroup -WorkObject $WorkObject
        if ($WorkObject -is [array]) { Write-LogMessage "Multiple database objects returned" -Level WARN; $WorkObject = $WorkObject[-1] }
      }
    }

    #######################################################################################################
    # Applications and configuration for App servers
    #######################################################################################################
    # Check if computer name ends with 'APP'
    if ($env:COMPUTERNAME.ToUpper().EndsWith('APP')) {  
      # Add required Windows applications
      $installWindowsApps += @(
        "Microsoft .Net Framwork 3.5",
        "Db2 Client 12.1 x86", 
        "IBM ObjectRexx"
        
      )

      # Add required FKPsh applications 
      $installDedgePshApps += @(
        "Db2-AddCat",
        "Refresh-CobolEnvironments"
      )

      # Handle non-FKX servers
      if (-not $env:COMPUTERNAME.ToUpper().Contains('FKX')) {
        # Create and share COBNT folder
        Add-Folder -Path "C:\COBNT" -AdditionalAdmins $AdditionalAdmins
        # Add-SharedFolder -Path "C:\COBNT" -ShareName "COBNT" -Description "Kopi av cobol, bat og rexx filer fra N:\COBNT" -AdditionalAdmins @(
        #   "$env:USERDOMAIN\$env:USERNAME",
        #   "$env:USERDOMAIN\ACL_ERPUTV_Utvikling_Full",
        #   "$env:USERDOMAIN\ACL_Dedge_Servere_Utviklere"
        # ) 
        Add-SmbSharedFolder -Path "C:\COBNT" -ShareName "COBNT" -Description "Kopi av cobol, bat og rexx filer fra N:\COBNT"  -AdditionalAdmins $AdditionalAdmins 

        # Create and share WKAKT folder
        Add-Folder -Path "C:\WKAKT" -AdditionalAdmins $AdditionalAdmins
        Add-SmbSharedFolder -Path "C:\WKAKT" -ShareName "WKAKT" -Description "Brukes til å lagre triggerfiler for Rexx"  -AdditionalAdmins $AdditionalAdmins 
      }
      # Handle FKX servers
      if ($env:COMPUTERNAME.ToUpper().Contains('FKX')) {
        try {
          # Remove shared folders and directories if they exist
          Remove-SharedFolder -Path "C:\WKAKT" -ShareName "WKAKT" -ErrorAction SilentlyContinue
          Remove-SharedFolder -Path "C:\COBNT" -ShareName "COBNT" -ErrorAction SilentlyContinue
          Remove-Folder -Path "C:\COBNT" -ErrorAction SilentlyContinue
          Remove-Folder -Path "C:\WKAKT" -ErrorAction SilentlyContinue
        }
        catch {            
        }
      }

      # Remove CLIENTNAME from registry if it exists
      $null = Invoke-RegistryCommand -Operation "delete" -Key "HKEY_LOCAL_MACHINE\Environment" -ValueName "CLIENTNAME" -Force -SuccessMessage "Successfully removed CLIENTNAME from machine environment" -ErrorMessage "Failed to remove CLIENTNAME from machine environment" -IgnoreError
      $null = Invoke-RegistryCommand -Operation "delete" -Key "HKEY_CURRENT_USER\Environment" -ValueName "CLIENTNAME" -Force -SuccessMessage "Successfully removed CLIENTNAME from user environment" -ErrorMessage "Failed to remove CLIENTNAME from user environment" -IgnoreError
    }

    #######################################################################################################
    # Applications and configuration for FSP application server
    #######################################################################################################
    # Check if this is a FKM FSP APP server (e.g. P-NO1FKMFSP-APP)
    if ($env:COMPUTERNAME.ToUpper().Contains("FKMFSP-APP") -or $env:COMPUTERNAME.ToUpper().Contains("INLPRD-APP")) {
      
      # Define folder paths and permissions to create
      $pathArray = @([PSCustomObject]@{
          Path               = "$env:OptPath\data\ReplicationData" # Path for replication data
          ShareName          = "ReplicationData"
          AdditionalAdmins   = $AdditionalAdmins # Pass through additional admins
          EveryonePermission = "Write" # Allow write access for everyone
          Description        = "Replication data for to be updated in Forsprang Performance FKMMIG database"
          AddSmbSharedFolder = $false
        })
      $pathArray += @([PSCustomObject]@{
          Path               = "E:\COBPER"
          ShareName          = "COBPER"
          AdditionalAdmins   = $AdditionalAdmins # Pass through additional admins
          EveryonePermission = "ReadWriteExecute" # Allow write access for everyone
          Description        = "Folder for COBPER cobol INT and BND files"
          AddSmbSharedFolder = $true
        })
      $pathArray += @([PSCustomObject]@{
          Path               = "E:\COBFUT"
          ShareName          = "COBFUT"
          AdditionalAdmins   = $AdditionalAdmins # Pass through additional admins
          EveryonePermission = "ReadWriteExecute" # Allow write access for everyone
          Description        = "Folder for COBFUT cobol INT and BND files"
          AddSmbSharedFolder = $true
        })
      $pathArray += @([PSCustomObject]@{
          Path               = "E:\COBSIT"
          ShareName          = "COBSIT"
          AdditionalAdmins   = $AdditionalAdmins # Pass through additional admins
          EveryonePermission = "ReadWriteExecute" # Allow write access for everyone
          Description        = "Folder for COBSIT cobol INT and BND files"
          AddSmbSharedFolder = $true
        })
      $pathArray += @([PSCustomObject]@{
          Path               = "E:\COBMIG"
          ShareName          = "COBMIG"
          AdditionalAdmins   = $AdditionalAdmins # Pass through additional admins
          EveryonePermission = "ReadWriteExecute" # Allow write access for everyone
          Description        = "Folder for COBMIG cobol INT and BND files"
          AddSmbSharedFolder = $true
        })
      $pathArray += @([PSCustomObject]@{
          Path               = "E:\COBVFK"
          ShareName          = "COBVFK"
          AdditionalAdmins   = $AdditionalAdmins # Pass through additional admins
          EveryonePermission = "ReadWriteExecute" # Allow write access for everyone
          Description        = "Folder for COBVFK cobol INT and BND files"
          AddSmbSharedFolder = $true
        })
      $pathArray += @([PSCustomObject]@{
          Path               = "E:\COBVFT"
          ShareName          = "COBVFT"
          AdditionalAdmins   = $AdditionalAdmins # Pass through additional admins
          EveryonePermission = "ReadWriteExecute" # Allow write access for everyone
          Description        = "Folder for COBVFT cobol INT and BND files"
          AddSmbSharedFolder = $true
        })
      $pathArray += @([PSCustomObject]@{
          Path               = "E:\COBKAT"
          ShareName          = "COBKAT"
          AdditionalAdmins   = $AdditionalAdmins # Pass through additional admins
          EveryonePermission = "ReadWriteExecute" # Allow write access for everyone
          Description        = "Folder for COBKAT cobol INT and BND files"
          AddSmbSharedFolder = $true
        })
      # Create each folder with specified permissions
      foreach ($pathItem in $pathArray) {
        Add-Folder -Path $pathItem.Path -AdditionalAdmins $pathItem.AdditionalAdmins -EveryonePermission $pathItem.EveryonePermission
        if ($pathItem.AddSmbSharedFolder) {
          Add-SmbSharedFolder -Path $pathItem.Path -ShareName $pathItem.ShareName -Description $pathItem.Description -AdditionalAdmins $pathItem.AdditionalAdmins
        }
      }
    }

    #######################################################################################################
    # Applications and configuration for POS servers
    #######################################################################################################
    if ($env:COMPUTERNAME.ToUpper().EndsWith('POS')) {  

      $command = "netsh http remove urlacl url=http://+:18000/DedgePosAPI.svc"
      Invoke-Expression $command
      $command = "netsh http remove urlacl url=http://+:8700/DedgePosAPI.svc"
      Invoke-Expression $command

      $username = "$env:USERDOMAIN\$env:USERNAME"
      $command = "netsh http add urlacl url=http://+:8700/DedgePosAPI.svc user=$username"
      Invoke-Expression $command

      netsh http show urlacl | findstr "DedgePosAPI.svc"

      # $command = "netsh http remove urlacl url=http://+:18000/DedgePosAPI.svc"
      # Invoke-Expression $command

      # $command = "netsh http show urlacl"
      # Invoke-Expression $command


      Set-NetIPInterface -InterfaceAlias "Ethernet" -NlMtu 1378
      Get-NetIPInterface 
    }
    

    #######################################################################################################
    # Applications and configuration for SOA servers
    #######################################################################################################
    # Configure SOA (Service Oriented Architecture) servers
    if ($env:COMPUTERNAME.ToUpper().EndsWith('SOA')) {
      # Stack 1: Core Windows Applications
      # - .NET Framework for runtime environment
      # - MicroFocus for COBOL support
      # - DB2 Client for database connectivity
      # - IBM ObjectRexx for scripting
      # - QMF for database querying
      $installWindowsApps += @("Microsoft .Net Framwork 3.5", 
        "MicroFocus Server SOA", 
        "Db2 Client 12.1 x86", 
        "IBM ObjectRexx"
      )
      
      # Stack 2: FK PowerShell Applications
      # - Db2-AddCat for database catalog management
      $installDedgePshApps += @("Db2-AddCat")

      # Stack 3: File System Setup
      # Create COBOL folder and share with appropriate permissions
      Add-Folder -Path "C:\COBNT" -AdditionalAdmins $AdditionalAdmins
      Add-SmbSharedFolder -Path "C:\COBNT" -ShareName "COBNT" -Description "Kopi av cobol, bat og rexx filer fra N:\COBNT"  -AdditionalAdmins $AdditionalAdmins 
      
      # Stack 4: Environment Variables
      # Set COBOL directory path
      [System.Environment]::SetEnvironmentVariable('COBDIR', 'C:\COBNT', [System.EnvironmentVariableTarget]::Machine)
      # Set DB2 instance name
      [System.Environment]::SetEnvironmentVariable('InstanceName', 'DB2', [System.EnvironmentVariableTarget]::Machine)

      # Set DB basis environment variable based on environment type
      if ($env:COMPUTERNAME.ToUpper().Contains('FKMPRD')) {
        # Production environment uses BASISPRO
        [System.Environment]::SetEnvironmentVariable('DBBASIS', 'BASISPRO', [System.EnvironmentVariableTarget]::Machine)
      }
      else {
        # Non-production environments use BASISTST
        [System.Environment]::SetEnvironmentVariable('DBBASIS', 'BASISTST', [System.EnvironmentVariableTarget]::Machine)
      }
    }

    if ($env:COMPUTERNAME.ToUpper().Contains('FKX') -and $env:COMPUTERNAME.ToUpper().EndsWith('APP')) {
      $installWingetApps += @("OpenJS.NodeJS.LTS", "Microsoft.AzureDataStudio", "Microsoft.DotNet.HostingBundle.9", "Microsoft.DotNet.SDK.9", "DBeaver.DBeaver.Community")
      $installDedgePshApps += @("Db2-AddCat", "Backup-CommonConfigFiles")
      try {
        $AdditionalAdmins = Get-AdditionalAdmins -AdditionalAdmins $AdditionalAdmins
        # $AdditionalAdmins | Format-Table -AutoSize

        # $pathArray = @([PSCustomObject]@{
        #     Path               = "E:\CommonLogging"
        #     AdditionalAdmins   = $AdditionalAdmins
        #     EveryonePermission = "Write"
        #   },
        #   [PSCustomObject]@{
        #     Path               = "E:\CommonLogging\Psh"
        #     AdditionalAdmins   = $AdditionalAdmins
        #     EveryonePermission = "Write"
        #   },
        #   [PSCustomObject]@{
        #     Path               = "E:\CommonLogging\DedgePos"
        #     AdditionalAdmins   = $AdditionalAdmins
        #     EveryonePermission = "Write"
        #   },
        #   [PSCustomObject]@{
        #     Path               = "E:\CommonLogging"
        #     AdditionalAdmins   = $AdditionalAdmins
        #     EveryonePermission = "Write"
        #   },
        #   [PSCustomObject]@{
        #     Path               = "E:\CommonLogging\Server"
        #     AdditionalAdmins   = $AdditionalAdmins
        #     EveryonePermission = "Write"
        #   },
        #   [PSCustomObject]@{
        #     Path               = "E:\CommonLogging\Server\ServiceUsersMetadata"
        #     AdditionalAdmins   = $AdditionalAdmins
        #     EveryonePermission = "Write"
        #   },
        #   [PSCustomObject]@{
        #     Path               = "E:\CommonLogging\Db2\Server"
        #     AdditionalAdmins   = $AdditionalAdmins
        #     EveryonePermission = "Write"
        #   },
        #   [PSCustomObject]@{
        #     Path               = "E:\CommonLogging\Db2\Client"
        #     AdditionalAdmins   = $AdditionalAdmins
        #     EveryonePermission = "Write"
        #   },
        #   [PSCustomObject]@{
        #     Path               = "E:\CommonLogging\Db2\Client\SslCertificateUsers"
        #     AdditionalAdmins   = $AdditionalAdmins
        #     EveryonePermission = "Write"
        #   }
        # )
        # foreach ($pathItem in $pathArray) {
        #   Add-Folder -Path $pathItem.Path -AdditionalAdmins $pathItem.AdditionalAdmins -EveryonePermission $pathItem.EveryonePermission
        # }
        
        Add-Folder -Path "E:\CommonLogging" -AdditionalAdmins $AdditionalAdmins -EveryonePermission "WriteAndRead"
        Add-Folder -Path "E:\CommonLogging\Psh" -AdditionalAdmins $AdditionalAdmins -EveryonePermission "WriteOnly"
        Add-Folder -Path "E:\CommonLogging\DedgePos" -AdditionalAdmins $AdditionalAdmins  -EveryonePermission "WriteOnly"
        Add-Folder -Path "E:\CommonLogging\Server" -AdditionalAdmins $AdditionalAdmins -EveryonePermission "WriteOnly"
        Add-Folder -Path "E:\CommonLogging\Server\ServiceUsersMetadata" -AdditionalAdmins $AdditionalAdmins -EveryonePermission "WriteOnly"
        Add-Folder -Path "E:\CommonLogging\Db2\Server" -AdditionalAdmins $AdditionalAdmins -EveryonePermission "WriteOnly"
        Add-Folder -Path "E:\CommonLogging\Db2\Client" -AdditionalAdmins $AdditionalAdmins -EveryonePermission "WriteOnly"
        Add-Folder -Path "E:\CommonLogging\Db2\Client\SslCertificateUsers" -AdditionalAdmins $AdditionalAdmins -EveryonePermission "WriteOnly"
        Add-SmbSharedFolder -Path "E:\CommonLogging" -ShareName "CommonLogging" -Description "Common log input for all FK logging"  -AdditionalAdmins $AdditionalAdmins 

        Add-Folder -Path "$($env:OptPath)\Webs\FkAdminWeb\Content" -AdditionalAdmins $(Get-AdditionalAdmins -AdditionalAdmins $AdditionalAdmins) -EveryonePermission "WriteAndRead"
        Add-SmbSharedFolder -Path "$($env:OptPath)\Webs\FkAdminWeb\Content" -ShareName "FkAdminWebContent" -Description "FkAdminWebContent" -AdditionalAdmins $(Get-AdditionalAdmins -AdditionalAdmins $AdditionalAdmins) 

        Add-Folder -Path "F:\DedgeCommon" -AdditionalAdmins $AdditionalAdmins -EveryonePermission "ReadAndExecute"
        Add-Folder -Path "F:\DedgeCommon\Software" -AdditionalAdmins $AdditionalAdmins  -EveryonePermission "ReadAndExecute"         
        Add-Folder -Path "F:\DedgeCommon\Software" -AdditionalAdmins $AdditionalAdmins  -EveryonePermission "ReadAndExecute"         
        Add-SmbSharedFolder -Path "F:\DedgeCommon" -ShareName "DedgeCommon" -Description "Common FK folder containing configuration files for the applications and services for all servers and workstations. Also contains the entire software repository for both servers and workstations related to Fk development."  -AdditionalAdmins $AdditionalAdmins 
      }
      catch {
        Write-LogMessage "Failed to add common logging folders" -Level ERROR -Exception $_
      }
    }

    #######################################################################################################
    # Applications and configuration for FKX DB servers
    #######################################################################################################
    if ($env:COMPUTERNAME.ToUpper().Contains('FKX') -and $env:COMPUTERNAME.ToUpper().EndsWith('DB')) {
      #$installWindowsApps += @("Microsoft.SQLServer.2022.Developer", "Microsoft.SQLServerManagementStudio")
      $installWindowsApps += "Microsoft.SQLServerManagementStudio"
    }

    #######################################################################################################
    # Applications and configuration for WEB servers
    #######################################################################################################
    if ( $env:COMPUTERNAME.ToUpper().Contains('WEB')) {
      $installWindowsApps += @("Internet Information Services", "Internet Information Services Management Console")
    }

    #######################################################################################################
    # Other common configuration
    #######################################################################################################
    $username = "$env:USERDOMAIN\$env:USERNAME"
    Write-LogMessage "Ensuring user $username has 'Log on as batch job' rights..." -Level INFO
    Grant-BatchLogonRight -Username $username


    
    # Set the default terminal to Windows Console Host
    Set-DefaultTerminalToConsoleHost
    #$null = Invoke-RegistryCommand -Operation "add" -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" -ValueName "Map-Drv" -ValueType "REG_SZ" -ValueData "$env:OptPath\DedgePshApps\Map-CommonNetworkDrives\Map-Drv.bat" -Force -SuccessMessage "Successfully added Map-Drv.bat to user startup registry" -ErrorMessage "Failed to add Map-Drv.bat to user startup registry"

    try {
      Save-ScheduledTaskFiles
    }
    catch {
      Write-LogMessage "Failed to save scheduled task files" -Level ERROR -Exception $_
    }
    # try {
    #   Remove-UserScheduledTasks
    # }
    # catch {
    #   Write-LogMessage "Failed to remove user scheduled tasks" -Level ERROR -Exception $_
    # }
    # try {
    #   Add-DefaultScheduledTasksServer 
    # }
    # catch {
    #   Write-LogMessage "Failed to add default scheduled tasks" -Level ERROR -Exception $_
    # }
 

    if (-not $SkipWinInstall) {

      #######################################################################################################
      # VCT environment: exclude MicroFocus products (not licensed for VCT)
      #######################################################################################################
      if ($env:COMPUTERNAME.ToUpper().Contains('VCT')) {
        $microFocusApps = $installWindowsApps | Where-Object { $_ -like "MicroFocus*" }
        if ($microFocusApps) {
          Write-LogMessage "VCT environment — removing MicroFocus apps from install list: $($microFocusApps -join ', ')" -Level INFO
          $installWindowsApps = $installWindowsApps | Where-Object { $_ -notlike "MicroFocus*" }
        }
      }

      #######################################################################################################
      # Install WindowsApps
      #######################################################################################################
      $installWindowsApps = $installWindowsApps | Sort-Object -Unique
      foreach ($app in $installWindowsApps) {
        try {
          Install-WindowsApps -AppName $app
        }
        catch {
          Write-LogMessage "Failed to install $app" -Level ERROR -Exception $_
        }
      }

      #######################################################################################################
      # Install WingetApps
      #######################################################################################################
      $installWingetApps = $installWingetApps | Sort-Object -Unique
      foreach ($app in $installWingetApps) {
        try {
          Install-WingetPackage -AppName $app
        }
        catch {
          Write-LogMessage "Failed to install $app" -Level ERROR -Exception $_
        }
      }
    }

    ################################################################################
    # Install DedgeWinApps
    ################################################################################

     
    ################################################################################
    # Install DedgeWinApps
    ################################################################################
    $installDedgeWinApps = @(
      "IBM-QMF-Version-81-For-Windows-With-HomeMade-32bit-Installer"
    )

    $failedDedgeWinApps = @()
    foreach ($app in $installDedgeWinApps) {
      try {
        Install-OurWinApp -AppName $app
      }
      catch {
        try { Write-LogMessage "Failed to install FkWinApp $($app)" -Level ERROR -Exception $_ }
        catch { Write-Host "ERROR: Failed to install FkWinApp $($app): $($_.Exception.Message)" -ForegroundColor Red }
        $failedDedgeWinApps += $app
      }
    }


    $usernameArray = @("$env:USERDOMAIN\srverp13", "$env:USERDOMAIN\$env:USERNAME")
    if ($env:COMPUTERNAME.ToUpper().Contains('PRD')) {
      $usernameArray += @("$env:USERDOMAIN\FKPRDADM")
    }
    elseif ($env:COMPUTERNAME.ToUpper().Contains('TST') -or $env:COMPUTERNAME.ToUpper().Contains('VCT')) {
      $usernameArray += @("$env:USERDOMAIN\FKTSTADM")
    }
    elseif ($env:COMPUTERNAME.ToUpper().Contains('DEV')) {
      $usernameArray += @("$env:USERDOMAIN\FKDEVADM")
    }

    foreach ($username in $usernameArray) {
      # Check if Infrastructure module is available and has the Grant-BatchLogonRight function
      if (Get-Command -Name Grant-BatchLogonRight -ErrorAction SilentlyContinue) {
        Write-LogMessage "Ensuring user $username has 'Log on as batch job' rights..." -Level INFO
        Grant-BatchLogonRight -Username $username
      }
      else {
        Write-LogMessage "Warning: Grant-BatchLogonRight function not available. User $username may need 'Log on as batch job' rights." -Level ERROR
      }
    }
    
    
    #######################################################################################################
    # Install DedgePshApps
    #######################################################################################################
    $installDedgePshApps = $installDedgePshApps | Sort-Object -Unique
    $failedDedgePshApps = @()
    foreach ($app in $installDedgePshApps) {
      try {
        Install-OurPshApp -AppName $app -CalledByInitMachine
      }
      catch {
        try { Write-LogMessage "Failed to install FkPshApp $($app)" -Level ERROR -Exception $_ }
        catch { Write-Host "ERROR: Failed to install FkPshApp $($app): $($_.Exception.Message)" -ForegroundColor Red }
        $failedDedgePshApps += $app
      }
    }

    if ($failedDedgePshApps.Count -gt 0) {
      try { Write-LogMessage "Failed DedgePshApps: $($failedDedgePshApps -join ', ')" -Level WARNING }
      catch { Write-Host "WARNING: Failed DedgePshApps: $($failedDedgePshApps -join ', ')" -ForegroundColor Yellow }
    }
    
    #######################################################################################################
    # Final configuration
    #######################################################################################################
    try {
      Set-UICustomization
    }
    catch {
      Write-LogMessage "Failed to set UI customization" -Level ERROR -Exception $_
    }

    if (-not $env:COMPUTERNAME.ToLower().EndsWith('-db')) {
      Start-Db2AutoCatalog
    }   
    if (-not $SkipWinInstall) {
      Restart-Machine     
    }
    
  }
  catch {
    Write-LogMessage "Failed to initialize server" -Level ERROR -Exception $_
  }
  finally {
    $logfilePath = $global:CurrentLogFilePath
    $webServerPath = Join-Path $(Get-DevToolsWebPath) "Server\$($env:COMPUTERNAME.ToLower())"
    if (-not (Test-Path $webServerPath -PathType Container)) {
      New-Item -ItemType Directory -Path $webServerPath -Force -ErrorAction SilentlyContinue | Out-Null
    }
    $destinationFilePath = Join-Path $webServerPath "Initialize-Server.log"
    Copy-Item -Path $logfilePath -Destination $destinationFilePath -Force -ErrorAction SilentlyContinue
    Reset-OverrideAppDataFolder
  }
}

function Initialize-Workstation {
  param (
    [Parameter(Mandatory = $false)]
    [string[]]$AdditionalAdmins = @(),
    [Parameter(Mandatory = $false)]
    [bool]$SkipWinInstall = $false
  )
  try {
    Write-Progress -Completed -ErrorAction SilentlyContinue

    # Test if the system32 path is correct
    Test-System32Path
    $currentUser = "$env:USERDOMAIN\$env:USERNAME"
    if ($currentUser -notin $AdditionalAdmins) {
      $AdditionalAdmins += $currentUser
    }
    Set-CommonSettings -AdditionalAdmins $AdditionalAdmins -EveryonePermission "" -IsWorkstation $true
    
    Connect-NetworkDrives -Drives  @(
      @{ Letter = "K"; Path = "\\DEDGE.fk.no\erputv\Utvikling" },
      @{ Letter = "N"; Path = "\\DEDGE.fk.no\erpprog" },
      @{ Letter = "R"; Path = "\\DEDGE.fk.no\erpdata" },
      @{ Letter = "Z"; Path = Get-CommonPath }
    )

    $dataPath = "$env:OptPath\src"
    Write-LogMessage "Adding folder $dataPath" -Level INFO
    Add-Folder -Path $dataPath -AdditionalAdmins $AdditionalAdmins -EveryonePermission "" -IsWorkstation $true
    $installDedgePshApps = @(
      "Add-BatchLogonCurrentUser",
      "Add-Task",
      "AddFkUserAsLocalAdmin", 
      "Agent-DeployTask",
      "Azure-DevOpsCloneRepositories",
      "Chg-Pass",
      "Configure-DefaultTerminalToConsoleHost",
      "Db2-AddCat",
      "Db2-AutoCatalog",
      "Db2-Commands",
      "Db2-CreateDb2CliShortCuts",
      "Get-App",
      "Init-Machine",
      "Inst-Psh",
      "Inst-WinApp",
      "Map-NetworkDrives",
      "PortCheckTool",
      "Pwsh-CreateAdminShortcut",
      "Refresh-WorkstationSettings",
      "RestoreProdVersionToDev"
      "Run-Psh",
      "Send-Sms"
      "Set-WinRegionTimeAndLanguage"
    )

    $installWindowsApps = @(
      "Microsoft .Net Framwork 3.5",
      "Db2 Client 12.1 x86", 
      "IBM ObjectRexx",
      "MicroFocus NetExpress Pack",
      #"Rocket Visual Cobol For 3 Studio 2022",
      "SPF Editor"
    )
    if ($env:USERNAME.ToUpper() -eq "FKGEISTA" -or $env:USERNAME.ToUpper() -eq "FKSVEERI" -or $env:USERNAME.ToUpper() -eq "FKMINSTA" -or $env:USERNAME.ToUpper() -eq "FKCELERI" -or $env:USERNAME.ToUpper() -eq "FKHANBOR" -or $env:USERNAME.ToUpper() -eq "FKMARERI") {
      #remove "MicroFocus NetExpress Pack",
      $installWindowsApps = $installWindowsApps | Where-Object { $_ -ne "MicroFocus NetExpress Pack" }
      $installDedgePshApps += @(
        "Azure-DevOpsCloneRepositories"
        "Setup-CursorRagNew"
        "Setup-CursorDb2Mcp"
        "Setup-CursorUserSettings"
        "Setup-OllamaDb2"
        "Setup-OllamaDb2New"
        "DedgePosLogSearch"
        "Enable-KerberosForBrowser"
        "Azure-NugetVersionPush"
        "Config-CursorAndVsCode"
        "DedgeSign"
        "Push-AllRepos"
        "CompareAllFilesInTwoFolders"
      )
    }


    $installWingetApps = @(
      "DBeaver.DBeaver.Community",
      "Git.Git",
      "Microsoft.DotNet.SDK.8",
      "Microsoft.DotNet.SDK.9",
      "Microsoft.DotNet.SDK.10",
      "Microsoft.DotNet.Runtime.8",
      "Microsoft.DotNet.Runtime.9",
      "Microsoft.DotNet.Runtime.10",
      "Microsoft.VisualStudio.Community",
      "Notepad++.Notepad++", 
      "Microsoft.Azure.TrustedSigningClientTools",
      "VSCode System-Installer"
    )

    if ($env:USERNAME.ToUpper() -eq "FKGEISTA" -or $env:USERNAME.ToUpper() -eq "FKSVEERI" -or $env:USERNAME.ToUpper() -eq "FKMINSTA" -or $env:USERNAME.ToUpper() -eq "FKCELERI") {
      $installWingetApps += @(
        "OpenJS.NodeJS.LTS",
        "Google.Chrome",
        "Microsoft.DotNet.HostingBundle.9",
        "Microsoft.DotNet.HostingBundle.10",
        "Microsoft.SQLServerManagementStudio",
        "Ollama.Ollama"
      )
      $installWindowsApps += @("Cursor System-Installer", "Python")
    }


     
    ################################################################################
    # Install DedgeWinApps
    ################################################################################
    $installDedgeWinApps = @(
      "DedgeRemoteConnect",
      "IBM-QMF-Version-81-For-Windows-With-HomeMade-32bit-Installer"
    )

    $failedDedgeWinApps = @()
    foreach ($app in $installDedgeWinApps) {
      try {
        Install-OurWinApp -AppName $app
      }
      catch {
        try { Write-LogMessage "Failed to install FkWinApp $($app)" -Level ERROR -Exception $_ }
        catch { Write-Host "ERROR: Failed to install FkWinApp $($app): $($_.Exception.Message)" -ForegroundColor Red }
        $failedDedgeWinApps += $app
      }
    }
 
    ################################################################################
    # Install DedgePshApps
    ################################################################################
    $failedDedgePshApps = @()
    foreach ($app in $installDedgePshApps) {
      try {
        Install-OurPshApp -AppName $app -CalledByInitMachine
      }
      catch {
        try { Write-LogMessage "Failed to install FkPshApp $($app)" -Level ERROR -Exception $_ }
        catch { Write-Host "ERROR: Failed to install FkPshApp $($app): $($_.Exception.Message)" -ForegroundColor Red }
        $failedDedgePshApps += $app
      }
    }

    ################################################################################
    # Install WindowsApps
    ################################################################################
    $failedWindowsApps = @()
    if (-not $SkipWinInstall) {
      foreach ($app in $installWindowsApps) {
        try {
          Install-WindowsApps -AppName $app
        }
        catch {
          try { Write-LogMessage "Failed to install WindowsApp $($app)" -Level ERROR -Exception $_ }
          catch { Write-Host "ERROR: Failed to install WindowsApp $($app): $($_.Exception.Message)" -ForegroundColor Red }
          $failedWindowsApps += $app
        }
      }
    }
    else {
      try { Write-LogMessage "Skipping WindowsApps installation (SkipWinInstall=$($SkipWinInstall))" -Level INFO }
      catch { Write-Host "Skipping WindowsApps installation" -ForegroundColor Yellow }
    }
    
    
    ################################################################################
    # Install WingetApps
    ################################################################################
    $failedWingetApps = @()
    if (-not $SkipWinInstall) {
      foreach ($app in $installWingetApps) {
        try {
          Install-WingetPackage -AppName $app 
          #-QueryWinget
        }
        catch {
          try { Write-LogMessage "Failed to install WingetApp $($app)" -Level ERROR -Exception $_ }
          catch { Write-Host "ERROR: Failed to install WingetApp $($app): $($_.Exception.Message)" -ForegroundColor Red }
          $failedWingetApps += $app
        }
      }
    }
    else {
      try { Write-LogMessage "Skipping WingetApps installation (SkipWinInstall=$($SkipWinInstall))" -Level INFO }
      catch { Write-Host "Skipping WingetApps installation" -ForegroundColor Yellow }
    }

    if ($failedDedgePshApps.Count -gt 0 -or $failedWindowsApps.Count -gt 0 -or $failedWingetApps.Count -gt 0 -or $failedDedgeWinApps.Count -gt 0) {
      try { Write-LogMessage "Some applications failed to install:" -Level WARNING }
      catch { Write-Host "WARNING: Some applications failed to install:" -ForegroundColor Yellow }
      if ($failedDedgePshApps.Count -gt 0) {
        try { Write-LogMessage "Failed DedgePshApps: $($failedDedgePshApps -join ', ')" -Level WARNING }
        catch { Write-Host "WARNING: Failed DedgePshApps: $($failedDedgePshApps -join ', ')" -ForegroundColor Yellow }
      }
      if ($failedWindowsApps.Count -gt 0) {
        try { Write-LogMessage "Failed WindowsApps: $($failedWindowsApps -join ', ')" -Level WARNING }
        catch { Write-Host "WARNING: Failed WindowsApps: $($failedWindowsApps -join ', ')" -ForegroundColor Yellow }
      }
      if ($failedWingetApps.Count -gt 0) {
        try { Write-LogMessage "Failed WingetApps: $($failedWingetApps -join ', ')" -Level WARNING }
        catch { Write-Host "WARNING: Failed WingetApps: $($failedWingetApps -join ', ')" -ForegroundColor Yellow }
      }
      if ($failedDedgeWinApps.Count -gt 0) {
        try { Write-LogMessage "Failed DedgeWinApps: $($failedDedgeWinApps -join ', ')" -Level WARNING }
        catch { Write-Host "WARNING: Failed DedgeWinApps: $($failedDedgeWinApps -join ', ')" -ForegroundColor Yellow }
      }
    }



    #######################################################################################################
    # Final configuration
    #######################################################################################################
    try {
      Set-UICustomization
    }
    catch {
      try { Write-LogMessage "Failed to set UI customization" -Level ERROR -Exception $_ }
      catch { Write-Host "ERROR: Failed to set UI customization: $($_.Exception.Message)" -ForegroundColor Red }
    }

    if (-not $env:COMPUTERNAME.ToLower().EndsWith('-db')) {
      Start-Db2AutoCatalog
    }
    
    Restart-Machine     
  }
  catch {
    try { Write-LogMessage "Failed to initialize workstation" -Level ERROR -Exception $_ }
    catch { Write-Host "ERROR: Failed to initialize workstation: $($_.Exception.Message)" -ForegroundColor Red }
    Write-Host "--- Diagnostics ---" -ForegroundColor Yellow
    Write-Host "PSModulePath: $($env:PSModulePath)" -ForegroundColor Yellow
    Write-Host "Loaded modules from opt:" -ForegroundColor Yellow
    Get-Module | Where-Object { $_.Path -like "*\opt\*" } | ForEach-Object {
      Write-Host "  $($_.Name) -> $($_.Path)" -ForegroundColor Yellow
    }
    Write-Host "GlobalFunctions available: $(($null -ne (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)))" -ForegroundColor Yellow
    Write-Host "-------------------" -ForegroundColor Yellow
  }
}

function Initialize-WorkstationOther {
  param (
    [Parameter(Mandatory = $false)]
    [string[]]$AdditionalAdmins = @(),
    [Parameter(Mandatory = $false)]
    [bool]$SkipWinInstall = $false
  )
  try {
    Write-Progress -Completed -ErrorAction SilentlyContinue

    # Test if the system32 path is correct
    Test-System32Path
    $AdditionalAdmins = @($("$env:USERDOMAIN\$env:USERNAME"))
    Set-CommonSettings -AdditionalAdmins $AdditionalAdmins -EveryonePermission "" -IsWorkstation $true
    
    try {
      Install-OurWinApp -AppName "DedgeRemoteConnect"
    }
    catch {
      try { Write-LogMessage "Failed to install DedgeRemoteConnect" -Level ERROR -Exception $_ }
      catch { Write-Host "ERROR: Failed to install DedgeRemoteConnect: $($_.Exception.Message)" -ForegroundColor Red }
    }

    try {
      Install-OurPshApp -AppName "Get-App" -CalledByInitMachine
    }
    catch {
      try { Write-LogMessage "Failed to install Get-App" -Level ERROR -Exception $_ }
      catch { Write-Host "ERROR: Failed to install Get-App: $($_.Exception.Message)" -ForegroundColor Red }
    }

    try {
      Install-OurPshApp -AppName "Send-Sms" -CalledByInitMachine
    }
    catch {
      try { Write-LogMessage "Failed to install Send-Sms" -Level ERROR -Exception $_ }
      catch { Write-Host "ERROR: Failed to install Send-Sms: $($_.Exception.Message)" -ForegroundColor Red }
    }

    try {
      Install-OurPshApp -AppName "Add-Task" -CalledByInitMachine
    }
    catch {
      try { Write-LogMessage "Failed to install Add-Task" -Level ERROR -Exception $_ }
      catch { Write-Host "ERROR: Failed to install Add-Task: $($_.Exception.Message)" -ForegroundColor Red }
    }

    try {
      Install-OurPshApp -AppName "Inst-Psh" -CalledByInitMachine
    }
    catch {
      try { Write-LogMessage "Failed to install Inst-Psh" -Level ERROR -Exception $_ }
      catch { Write-Host "ERROR: Failed to install Inst-Psh: $($_.Exception.Message)" -ForegroundColor Red }
    }

    try {
      Install-OurPshApp -AppName "Run-Psh" -CalledByInitMachine
    }
    catch {
      try { Write-LogMessage "Failed to install Run-Psh" -Level ERROR -Exception $_ }
      catch { Write-Host "ERROR: Failed to install Run-Psh: $($_.Exception.Message)" -ForegroundColor Red }
    }
    

    ################################################################################
    # Install WindowsApps
    ################################################################################
    try { Write-LogMessage "Installing standard software..." -Level INFO }
    catch { Write-Host "Installing standard software..." -ForegroundColor White }
    $installWindowsApps = @()
    foreach ($app in $installWindowsApps) {
      try {
        Install-WindowsApps -AppName $app 
      }
      catch {
        try { Write-LogMessage "Failed to install WindowsApp $($app)" -Level ERROR -Exception $_ }
        catch { Write-Host "ERROR: Failed to install WindowsApp $($app): $($_.Exception.Message)" -ForegroundColor Red }
      }
    }
    ################################################################################
    # Install WingetApps
    ################################################################################
    $installWingetApps = @()
    foreach ($app in $installWingetApps) {
      try {
        Install-WingetPackage -AppName $app -Force $false
      }
      catch {
        try { Write-LogMessage "Failed to install WingetApp $($app)" -Level ERROR -Exception $_ }
        catch { Write-Host "ERROR: Failed to install WingetApp $($app): $($_.Exception.Message)" -ForegroundColor Red }
      }
    }

    Restart-Machine
  }
  catch {
    try { Write-LogMessage "Failed to initialize workstation (Other)" -Level ERROR -Exception $_ }
    catch { Write-Host "ERROR: Failed to initialize workstation (Other): $($_.Exception.Message)" -ForegroundColor Red }
    Write-Host "--- Diagnostics ---" -ForegroundColor Yellow
    Write-Host "PSModulePath: $($env:PSModulePath)" -ForegroundColor Yellow
    Write-Host "Loaded modules from opt:" -ForegroundColor Yellow
    Get-Module | Where-Object { $_.Path -like "*\opt\*" } | ForEach-Object {
      Write-Host "  $($_.Name) -> $($_.Path)" -ForegroundColor Yellow
    }
    Write-Host "GlobalFunctions available: $(($null -ne (Get-Command Write-LogMessage -ErrorAction SilentlyContinue)))" -ForegroundColor Yellow
    Write-Host "-------------------" -ForegroundColor Yellow
  }
}


function Copy-FilesToDeployPaths {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$DeployPathList,
    [Parameter(Mandatory = $true)] 
    [string]$DistributionSource,
    [Parameter(Mandatory = $true)]
    [string]$AppName,
    [Parameter(Mandatory = $false)]
    [bool]$ForcePush = $true,
    [Parameter(Mandatory = $false)]
    [PSCustomObject]$CurrentDeployFileInfo
  )


  Write-LogMessage "Deploying App $AppName to $($DeployPathList.Count) paths:" -Level INFO
  $newDeployPathList = @()
  foreach ($DeployPath in $DeployPathList) {
    if ($ForcePush) {
      Get-ChildItem -Path $DeployPath -Filter "*.version" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
      Write-Progress -Completed -ErrorAction SilentlyContinue
    }
    New-Item -Path $DeployPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null


    $localVersionFile = Get-ChildItem -Path $DistributionSource -Filter "*.version" -ErrorAction SilentlyContinue  
    if ($localVersionFile) {
      $remoteVersionFile = Get-ChildItem -Path $DeployPath -Filter "*.version" -ErrorAction SilentlyContinue
      if ($remoteVersionFile.Count -gt 1) {
        Get-ChildItem -Path $DeployPath -Filter "*.version" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Progress -Completed -ErrorAction SilentlyContinue
        $remoteVersionFile = $null
      }
      if ($remoteVersionFile) {
        if ($localVersionFile.Name -eq $remoteVersionFile.Name) {
          Write-LogMessage "Local version and remote version are the same. Skipping deployment to $DeployPath" -Level INFO -ForegroundColor Yellow
          continue
        }
        else {
          Write-LogMessage "Local version is newer than remote version. Deploying to $DeployPath" -Level INFO -ForegroundColor Green
          Get-ChildItem -Path $DeployPath -Filter "*.version" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
          Write-Progress -Completed -ErrorAction SilentlyContinue
          Copy-Item -Path $localVersionFile.FullName -Destination $DeployPath -Force -ErrorAction SilentlyContinue
          $newDeployPathList += $DeployPath
        }
      }
      else {
        Write-LogMessage "No version file found in $DeployPath. Copying version file $($localVersionFile.Name) to $DeployPath" -Level INFO
        Copy-Item -Path $localVersionFile.FullName -Destination $DeployPath -Force
        $newDeployPathList += $DeployPath
      }
    }
    else {
      Write-LogMessage "No version file found in $DistributionSource. Deploying to $DeployPath" -Level INFO
      $newDeployPathList += $DeployPath
    }
  }

  $DeployPathList = $newDeployPathList
  if ($DeployPathList.Count -eq 0) {
    Write-LogMessage "No paths to deploy to after checking timestamp files. Skipping deployment." -Level INFO
    return
  }


  $resultObjects = @()
  $deployQuickRun = $false
  $quickRunFilenames = @()
  if (Get-ChildItem "$DistributionSource\*.QuickRun.bat" -ErrorAction SilentlyContinue) {
    $quickRunFilenames = @(Get-ChildItem "$DistributionSource\*.QuickRun.bat" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $deployQuickRun = $true
  }
  $deployIndex = 0
  $DeployPathList = $DeployPathList | Sort-Object { $_.DeployFolder.Length } -Descending
  foreach ($DeployPath in $DeployPathList) {
    $deployIndex++
    $pos = $DeployPath.ToLower().IndexOf("\" , 5)
    $servername = $DeployPath.Substring(0, $pos)
    Write-Progress -Activity "Deploying $AppName" -Status "Deploying to $servername" -PercentComplete (($deployIndex / $DeployPathList.Count) * 100)
    if ($ForcePush -and $DeployPath.ToLower().Contains("\DedgeCommon\")) {
      Remove-Item -Path $DeployPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $DeployPath -PathType Container)) {
      New-Item -Path $DeployPath -ItemType Directory -Force -ErrorAction SilentlyContinue
    }
      
    if ($DeployPath.ToLower().Contains("\DedgeCommon\")) {
      $tempObj = Start-RoboCopy -SourceFolder $DistributionSource -DestinationFolder $DeployPath -Recurse:$true -QuietMode -Exclude @("*.unsigned", "_deployAll.ps1", "_deploy.ps1" , "_deploy.bat" , "_deploy.cmd") -ApplicationTechnologyFolderName $ApplicationTechnologyFolderName -ForcePush:$ForcePush
    }
    else {
      $tempObj = Start-RoboCopy -SourceFolder $DistributionSource -DestinationFolder $DeployPath -Recurse:$true -QuietMode -Exclude @("*.unsigned", "_deployAll.ps1", "_deploy.ps1" , "_deploy.bat" , "_deploy.cmd") -ApplicationTechnologyFolderName $ApplicationTechnologyFolderName -ForcePush:$ForcePush
    }


    # $sshTest = $false
    # if ($sshTest) {
    #   # Extract server name for SSH connection
    #   $serverName = "dedge-server"
      
    #   # Build remote PowerShell command
    #   $remoteCommand = "Start-RoboCopy -SourceFolder '$DistributionSource' -DestinationFolder '$DeployPath' -Recurse:`$true -QuietMode -Exclude @('*.unsigned', '_deployAll.ps1', '_deploy.ps1', '_deploy.bat', '_deploy.cmd') -ApplicationTechnologyFolderName '$ApplicationTechnologyFolderName'"
    #   try {
    #     # Execute command via SSH and get object back
    #     $securePassword = Get-UserPasswordAsSecureString
    #     if ($null -eq $securePassword) {
    #       $securePassword = Read-Host -Prompt "Enter password for SSH connection to $serverName" -AsSecureString
    #     }
        
    #     # For SSH remoting, we have a few options:
    #     # Option 1: Use SSH key authentication (recommended)
    #     # Option 2: Use credential with SSH transport
        
    #     # Try SSH key authentication first (if keys are configured)
    #     try {
    #       $tempObj = Invoke-Command -HostName $serverName -UserName $env:USERNAME -ScriptBlock { 
    #         param($cmd)
    #         Invoke-Expression $cmd
    #       } -ArgumentList $remoteCommand -ErrorAction Stop
    #     }
    #     catch {
    #       # Fall back to password authentication
    #       Write-LogMessage "SSH key authentication failed, trying password authentication..." -Level WARN
    #       $credential = New-Object System.Management.Automation.PSCredential($env:USERNAME, $securePassword)
          
    #       # Use SSH with credential (PowerShell 7+ feature)
    #       if ($PSVersionTable.PSVersion.Major -ge 7) {
    #         $tempObj = Invoke-Command -HostName $serverName -UserName $env:USERNAME -SSHTransport -Credential $credential -ScriptBlock { 
    #           param($cmd)
    #           Invoke-Expression $cmd
    #         } -ArgumentList $remoteCommand
    #       }
    #       else {
    #         # For PowerShell 5.x, use alternative approach
    #         throw "SSH with password requires PowerShell 7+. Please use SSH keys or upgrade to PowerShell 7."
    #       }
    #     }
    #   }
    #   catch {
    #     Write-LogMessage "Failed to execute remote command. Falling back to local robocopy execution." -Level WARN -Exception $_
    #     $tempObj = Start-RoboCopy -SourceFolder $DistributionSource -DestinationFolder $DeployPath -Recurse:$true -QuietMode -Exclude @("*.unsigned", "_deployAll.ps1", "_deploy.ps1" , "_deploy.bat" , "_deploy.cmd") -ApplicationTechnologyFolderName $ApplicationTechnologyFolderName
    #   }

    #   # TODO: Configure PowerShell Remoting on fkxprd server to fix "Access is denied" error
    #   # 
    #   # On the target server (dedge-server), run the following commands as Administrator:
    #   # 1. Enable-PSRemoting -Force
    #   # 2. Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
    #   # 3. Restart-Service WinRM
    #   # 4. Test-WSMan dedge-server (from source machine)
    #   # 
    #   # Alternative: Use SSH remoting if available:
    #   # 1. Install OpenSSH Server on target machine
    #   # 2. Configure SSH keys or use credential authentication
    #   # 3. Replace Invoke-Command with Invoke-Command -HostName instead of -ComputerName
    #   #
    #   # For now, falling back to local robocopy execution
    # }
    # else {
    # $tempObj = Start-RoboCopy -SourceFolder $DistributionSource -DestinationFolder $DeployPath -Recurse:$true -QuietMode -Exclude @("*.unsigned", "_deployAll.ps1", "_deploy.ps1" , "_deploy.bat" , "_deploy.cmd") -ApplicationTechnologyFolderName $ApplicationTechnologyFolderName
    # }
    #}


    $tempObj | Add-Member -MemberType NoteProperty -Name "QuickRunDeployed" -Value $false
    $tempObj | Add-Member -MemberType NoteProperty -Name "AppName" -Value $AppName

    # # Copy version file
    Get-ChildItem -Path $DeployPath -Filter "version-*.txt" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    


    if ($tempObj.RobocopyExitCode -eq 16) {
      New-Item -Path $DeployPath -ItemType Directory -Force -ErrorAction SilentlyContinue

      Write-LogMessage "Robocopy exit code 16. Attempting Powershell copy instead." -Level INFO
      Copy-Item -Path $DistributionSource -Destination $DeployPath -Recurse -Force -ErrorAction SilentlyContinue
      $tempObj.RobocopyExitCode = 0
      $tempObj.ResultMessage = "Powershell copy successful"
    }


    # Copy QuickRun files
    if ($deployQuickRun -and $DeployPath.ToLower().Contains("\opt\")) {
      $splitOptPath = $DeployPath.ToLower().Split("\opt\")[0] + "\opt" + "\QuickRun" 
      $QuickRunPath = $splitOptPath
      if (-not (Test-Path $QuickRunPath -PathType Container)) {
        New-Item -Path $QuickRunPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
      }
      try {
        $localQuickRunFolder = $env:OptPath + "\QuickRun" 
        if (-not (Test-Path ($localQuickRunFolder.TrimEnd("\")) -PathType Container)) {
          New-Item -Path $localQuickRunFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $remoteQuickRunFolder = $DeployPath.ToLower().Split("\opt\")[0] + "\opt" + "\QuickRun" 
        foreach ($file in $quickRunFilenames) {  
          $targetFile = $($file.Replace(".QuickRun.bat", ".bat"))
          $localQuickRunFile = $($localQuickRunFolder + "\" + $targetFile)
          $remoteQuickRunFile = $($remoteQuickRunFolder + "\" + $targetFile)
          Copy-Item -Path $($DistributionSource + "\" + $file) -Destination $localQuickRunFile -Force | Out-Null
          Copy-Item -Path $($DistributionSource + "\" + $file) -Destination $remoteQuickRunFile -Force | Out-Null
          $tempObj.QuickRunDeployed = $true
          # Write-LogMessage "Copied $targetFile to $remoteQuickRunFolder" -Level INFO
        }
      }
      catch {
        Write-LogMessage "Error copying $file to $QuickRunPath" -Level ERROR
      }
    }
    $resultObjects += $tempObj
  }
    
  $resultObjects = $resultObjects | Sort-Object { $_.DeployFolder.Length } -Descending 
  foreach ($resultObject in $resultObjects) {
    if ($resultObject.ErrorLevel -eq "ERROR") {
      $resultObject.RobocopyOutput.Split("`n") | ForEach-Object {
        Write-Host $_ -ForegroundColor Yellow
      }
    }
  }
  Write-Progress -Activity "Deploying $AppName" -Completed
  return $resultObjects
}
function Start-Deploy {
  param (
    [Parameter(Mandatory = $false)]
    [string]$FkPshPath = "$env:OptPath\src\DedgePsh",
    [Parameter(Mandatory = $true)]
    [string]$PushMethod,
    [Parameter(Mandatory = $false)]
    [switch]$ForcePush
  )
  try {
    Set-Location $FkPshPath
    $deployScript = Get-ChildItem -Path $FkPshPath -Filter "_deploy.ps1" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $deployScript -or $deployScript.FullName.ToLower().Contains("\_old") -or $deployScript.FullName.ToLower().Contains("\_retiredfkcode")) {
      return
    }

    $deployScriptContent = Get-Content -Path $deployScript.FullName
    if (-not $deployScriptContent.ToLower() -contains "deploy-handler") {
      Write-LogMessage "Deploy script not valid to be ran by this automated script: $($deployScript.FullName)" -Level WARN
      return
    }

    if ($PushMethod -eq "DedgeCommon") {
      Deploy-Files -FromFolder $FkPshPath -DeployModules $false -ForcePush:$ForcePush
    }
    elseif ($PushMethod -eq "All") {
      Deploy-Files -FromFolder $FkPshPath -DeployModules $false -ComputerNameList "*" -ForcePush:$ForcePush
    }
    elseif ($PushMethod -eq "Standard") {
      & $deployScript.FullName
    }
  }
  catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
  }
}

function Deploy-AllModules {
  param (
    [Parameter(Mandatory = $false)]
    [string]$FkPshPath = "$env:OptPath\src\DedgePsh",
    [Parameter(Mandatory = $false)]
    [ValidateSet("DedgeCommon", "Standard", "All")]
    [string]$PushMethod = "DedgeCommon",
    [Parameter(Mandatory = $false)]
    [string]$SmsReceiver = $null,
    [switch]$ForcePush
  )
  try {
    Write-LogMessage "Deploying all modules from folder $FkPshPath" -Level INFO

  

    # Deploy all modules from folder

    Write-LogMessage "Deploying all CommonModules first: $FkPshPath" -Level INFO
    if ($FkPshPath.EndsWith("DedgePsh")) {
      if (-not (Test-Path "$FkPshPath\_Modules" -PathType Container)) {
        Write-LogMessage "Folder _Modules not found in $FkPshPath. Skipping deployment." -Level WARN
        return
      }
      Start-Deploy -FkPshPath "$FkPshPath\_Modules" -PushMethod $PushMethod -ForcePush:$ForcePush
    }
    else {
      $splitPath = $FkPshPath.Split("DedgePsh")[0] + "DedgePsh"
      if (-not (Test-Path "$splitPath\_Modules" -PathType Container)) {
        Write-LogMessage "Folder _Modules not found in $splitPath. Skipping deployment." -Level WARN
        return
      }
      Start-Deploy -FkPshPath "$splitPath\_Modules" -PushMethod $PushMethod -ForcePush:$ForcePush
    }


    # Find all the deploy.ps1 files and run them
    Set-Location $FkPshPath
    $deployScriptList = @(Get-ChildItem -Path $FkPshPath -Recurse -Include _deploy.ps1)
    foreach ($deployScript in $deployScriptList) {
      Write-LogMessage "Running deploy script $($deployScript.FullName.Split("\src")[-1]) with parameters (PushMethod: $PushMethod, ForcePush: $ForcePush)" -Level INFO
      $currentDirectory = $deployScript.Directory.ToString()
      Push-Location -Path "$currentDirectory"      
      Start-Deploy -FkPshPath $currentDirectory -PushMethod $PushMethod -ForcePush:$ForcePush
      Pop-Location
    }

    if ($SmsReceiver) {
      Send-Sms -Receiver $SmsReceiver -Message $($PSCommandPath.Split("\")[-1] + " completed")
    }
    Write-LogMessage "$($PSCommandPath.Split("\")[-1] + " completed")" -Level INFO
  }
  catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    if ($SmsReceiver) {
      Send-Sms -Receiver $SmsReceiver -Message $($PSCommandPath.Split("\")[-1] + " failed")
    }
  }
}

Export-ModuleMember -Function *
