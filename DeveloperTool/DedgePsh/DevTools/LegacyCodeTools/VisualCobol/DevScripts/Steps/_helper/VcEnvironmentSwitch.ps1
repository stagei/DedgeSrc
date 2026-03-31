<#
.SYNOPSIS
    Reusable helper: switch machine environment between Visual COBOL and Micro Focus.
.DESCRIPTION
    Dot-source this file in any dev script that needs the Visual COBOL compiler.
    Call Switch-ToVisualCobol at the start and Switch-ToMicroFocus at the end.

    Uses the same environment variable pattern as CblEnvironment\switchMF.ps1
    and OneTime\Switch-CobolEnvironment.ps1, but designed for automatic
    switch-back in try/finally blocks.

    Process-level env vars are set immediately for the current session.
    Machine-level env vars are updated for persistence across processes.
#>

$script:VcBasePath = 'C:\Program Files (x86)\Rocket Software\Visual COBOL'
$script:MfBasePath = 'C:\Program Files (x86)\Micro Focus\Net Express 5.1'
$script:VcPathDir  = if ($env:VCPATH) { $env:VCPATH } else { 'C:\fkavd\Dedge2' }
$script:GitPath    = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\mingw64\bin'
$script:Db2Bin     = 'C:\Program Files\IBM\SQLLIB\BIN'

$script:_SavedEnv = @{}

function Save-CurrentEnvironment {
    $script:_SavedEnv = @{
        COBDIR  = [System.Environment]::GetEnvironmentVariable('COBDIR',  [System.EnvironmentVariableTarget]::Machine)
        COBPATH = [System.Environment]::GetEnvironmentVariable('COBPATH', [System.EnvironmentVariableTarget]::Machine)
        COBCPY  = [System.Environment]::GetEnvironmentVariable('COBCPY',  [System.EnvironmentVariableTarget]::Machine)
        COBMODE = [System.Environment]::GetEnvironmentVariable('COBMODE', [System.EnvironmentVariableTarget]::Machine)
        MFVSSW  = [System.Environment]::GetEnvironmentVariable('MFVSSW',  [System.EnvironmentVariableTarget]::Machine)
        LIB     = [System.Environment]::GetEnvironmentVariable('LIB',     [System.EnvironmentVariableTarget]::Machine)
        VCPATH  = [System.Environment]::GetEnvironmentVariable('VCPATH',  [System.EnvironmentVariableTarget]::Machine)
        PATH    = [System.Environment]::GetEnvironmentVariable('PATH',    [System.EnvironmentVariableTarget]::Machine)
    }
}

function Restore-SavedEnvironment {
    if ($script:_SavedEnv.Count -eq 0) { return }
    foreach ($entry in $script:_SavedEnv.GetEnumerator()) {
        [System.Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, [System.EnvironmentVariableTarget]::Machine)
        if ($null -eq $entry.Value) {
            [System.Environment]::SetEnvironmentVariable($entry.Key, $null, [System.EnvironmentVariableTarget]::Process)
        } else {
            [System.Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, [System.EnvironmentVariableTarget]::Process)
        }
    }
    Write-LogMessage 'Environment restored to pre-switch state' -Level INFO
}

function Switch-ToVisualCobol {
    [CmdletBinding()] param()

    Save-CurrentEnvironment

    $vcBase = if (Test-Path "$($script:VcBasePath)\bin\cobol.exe") {
        $script:VcBasePath
    } elseif (Test-Path 'C:\Program Files (x86)\Micro Focus\Visual COBOL\bin\cobol.exe') {
        'C:\Program Files (x86)\Micro Focus\Visual COBOL'
    } else {
        Write-LogMessage 'Visual COBOL compiler not found in expected paths' -Level ERROR
        return $false
    }

    $vp = $script:VcPathDir
    if (-not (Test-Path $vp)) { New-Item -ItemType Directory -Path $vp -Force | Out-Null }

    $vars = @{
        VCPATH  = $vp
        COBDIR  = "$($vcBase);$($vp)\int;$($vp)\gs;$($vp)\src\cbl"
        COBPATH = "$($vp)\int;$($vp)\gs;$($vp)\src\cbl"
        COBCPY  = "$($vp)\src\cbl\cpy;$($vp)\src\cbl\cpy\sys\cpy;$($vp)\src\cbl"
        COBMODE = '32'
        MFVSSW  = '/c /f'
        LIB     = "$($vcBase)\lib"
    }

    foreach ($entry in $vars.GetEnumerator()) {
        [System.Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, [System.EnvironmentVariableTarget]::Machine)
        [System.Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, [System.EnvironmentVariableTarget]::Process)
    }

    $removePatterns = @($script:GitPath, 'Rocket Software', 'Micro Focus', 'IBM\SQLLIB')
    $addPaths = @("$($vcBase)\bin", "$($vcBase)\lib", $script:Db2Bin, "$($vp)\cfg", $script:GitPath)

    $currentPath = [System.Environment]::GetEnvironmentVariable('PATH', [System.EnvironmentVariableTarget]::Machine)
    $entries = $currentPath.Split(';') | Where-Object { $_.Trim().Length -gt 0 }

    $filtered = @()
    foreach ($entry in $entries) {
        $shouldRemove = $false
        foreach ($pattern in ($removePatterns + @('%PATH%'))) {
            if ($entry -like "*$($pattern)*") { $shouldRemove = $true; break }
        }
        if (-not $shouldRemove) { $filtered += $entry }
    }
    $newPath = (($addPaths + $filtered) | Select-Object -Unique) -join ';'
    [System.Environment]::SetEnvironmentVariable('PATH', $newPath, [System.EnvironmentVariableTarget]::Machine)
    $env:PATH = $newPath

    Write-LogMessage "Switched to Visual COBOL ($($vcBase))" -Level INFO
    return $true
}

function Switch-ToMicroFocus {
    [CmdletBinding()] param()

    if ($script:_SavedEnv.Count -gt 0) {
        Restore-SavedEnvironment
        return
    }

    $removePatterns = @($script:GitPath, 'Rocket Software', 'Micro Focus', 'IBM\SQLLIB')
    $addPaths = @(
        "$($script:MfBasePath)\base\bin"
        "$($script:MfBasePath)\dialogsystem\bin"
        $script:Db2Bin
        $script:GitPath
    )

    foreach ($varName in @('VCPATH', 'COBDIR', 'COBPATH', 'COBCPY', 'COBMODE', 'MFVSSW', 'LIB')) {
        [System.Environment]::SetEnvironmentVariable($varName, $null, [System.EnvironmentVariableTarget]::Machine)
        [System.Environment]::SetEnvironmentVariable($varName, $null, [System.EnvironmentVariableTarget]::Process)
    }

    $currentPath = [System.Environment]::GetEnvironmentVariable('PATH', [System.EnvironmentVariableTarget]::Machine)
    $entries = $currentPath.Split(';') | Where-Object { $_.Trim().Length -gt 0 }

    $filtered = @()
    foreach ($entry in $entries) {
        $shouldRemove = $false
        foreach ($pattern in ($removePatterns + @('%PATH%'))) {
            if ($entry -like "*$($pattern)*") { $shouldRemove = $true; break }
        }
        if (-not $shouldRemove) { $filtered += $entry }
    }
    $newPath = (($addPaths + $filtered) | Select-Object -Unique) -join ';'
    [System.Environment]::SetEnvironmentVariable('PATH', $newPath, [System.EnvironmentVariableTarget]::Machine)
    $env:PATH = $newPath

    Write-LogMessage 'Switched to Micro Focus Net Express' -Level INFO
}
