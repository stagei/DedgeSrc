Import-Module GlobalFunctions -Force


try {
    #########################################################################################################################
    # Prepare unsigned production files
    #########################################################################################################################
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED
    $appdataFolder = Get-ApplicationDataPath
    $folderLeft = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles"
    $folderRight = "\\p-no1fkxprd-app\DedgeCommon\Configfiles"

    # open folder dialog if the folders are not set
    if ([string]::IsNullOrEmpty($folderLeft)) {
        Add-Type -AssemblyName System.Windows.Forms
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Select left folder"
        $folderDialog.ShowNewFolderButton = $false
        
        # Create a temporary form to ensure dialog appears on top
        $topForm = New-Object System.Windows.Forms.Form
        $topForm.TopMost = $true
        $topForm.StartPosition = 'Manual'
        $topForm.Location = New-Object System.Drawing.Point(-2000, -2000)
        $topForm.Size = New-Object System.Drawing.Size(1, 1)
        $topForm.Show()
        
        if ($folderDialog.ShowDialog($topForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $folderLeft = $folderDialog.SelectedPath
        }
        else {
            $topForm.Dispose()
            throw "No folder selected. Operation cancelled."
        }
        $topForm.Dispose()
    }
    if ([string]::IsNullOrEmpty($folderRight)) {
        Add-Type -AssemblyName System.Windows.Forms
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = "Select right folder"
        $folderDialog.ShowNewFolderButton = $false
        
        # Create a temporary form to ensure dialog appears on top
        $topForm = New-Object System.Windows.Forms.Form
        $topForm.TopMost = $true
        $topForm.StartPosition = 'Manual'
        $topForm.Location = New-Object System.Drawing.Point(-2000, -2000)
        $topForm.Size = New-Object System.Drawing.Size(1, 1)
        $topForm.Show()
        
        if ($folderDialog.ShowDialog($topForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $folderRight = $folderDialog.SelectedPath
        }
        else {
            $topForm.Dispose()
            throw "No folder selected. Operation cancelled."
        }
        $topForm.Dispose()
    }


    $filesLeft = Get-ChildItem -Path $folderLeft  -File -ErrorAction SilentlyContinue
    $filesRight = Get-ChildItem -Path $folderRight -File -ErrorAction SilentlyContinue

    foreach ($fileLeft in $filesLeft) {
        $fileRight = $filesRight | Where-Object { $_.Name -eq $fileLeft.Name }
        if ($fileRight) {
            $hashLeft = Get-FileHash -Path $fileLeft.FullName -Algorithm SHA256
            $hashRight = Get-FileHash -Path $fileRight.FullName -Algorithm SHA256
            if ($hashLeft.Hash -ne $hashRight.Hash) {
                Write-LogMessage "File $($fileLeft.FullName) is different from $($fileRight.FullName)" -Level WARN
            }
            else {
                Write-LogMessage "File $($fileLeft.FullName) is the same as $($fileRight.FullName)" -Level INFO
                continue
            }
        }
        else {
            Write-LogMessage "File $($fileLeft.FullName) is not found in the right folder" -Level WARN
            continue
        }
        # OPEN IN EDITOR
        $codeCmd = Get-CommandPathWithFallback -Name "code"
        if ($codeCmd) {
            $diffArgs = @("--diff", $fileLeft.FullName, $fileRight.FullName)
            Start-Process -FilePath $codeCmd -ArgumentList $diffArgs -WindowStyle Minimized -Wait
        }
        else {
            Write-LogMessage "Code not found" -Level ERROR
        }
    }
    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}

