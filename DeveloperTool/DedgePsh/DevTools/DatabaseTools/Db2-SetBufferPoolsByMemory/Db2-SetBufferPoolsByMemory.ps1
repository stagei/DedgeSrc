param(
    [Parameter(Mandatory = $false)]
    [string]$DatabaseName,
    [Parameter(Mandatory = $false)]
    [string]$InstanceName,
    # Use -1 for automatic OS reserve from catalog + host (FKMPRD on *fkmprd-db* vs Community-style). Any value >= 512 overrides.
    [Parameter(Mandatory = $false)]
    [int]$OsReserveMB = -1,
    [Parameter(Mandatory = $false)]
    [bool]$ForceApply = $false,
    [Parameter(Mandatory = $false)]
    [bool]$AllowIncrease = $false,
    # When $true: missing choices use recommended values (no console prompts). Callers: -NonInteractive:$true
    [Parameter(Mandatory = $false)]
    [bool]$NonInteractive = $false
)

Import-Module GlobalFunctions -Force
Import-Module Db2-Handler -Force

function Get-PrimaryDbCatalogNamesForThisServer {
    $dbConfigs = @(Get-DatabasesV2Json | Where-Object { $_.IsActive -eq $true -and $_.Provider -eq "DB2" -and $_.ServerName -eq $env:COMPUTERNAME })
    $primaryAccessPoints = @(
        $dbConfigs |
            ForEach-Object { $_.AccessPoints } |
            Where-Object { $_.IsActive -eq $true -and $_.AccessPointType -eq "PrimaryDb" }
    )
    return @($primaryAccessPoints | Select-Object -ExpandProperty CatalogName -Unique | Sort-Object)
}

function Get-HostTotalPhysicalMemoryMB {
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return [math]::Round(([double]$osInfo.TotalVisibleMemorySize / 1024), 2)
    }
    catch {
        $computerInfo = Get-ComputerInfo
        return [math]::Round(([double]$computerInfo.CsPhysicallyInstalledMemory / 1MB), 2)
    }
}

function Test-IsProductionFkMPrdDbContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CatalogName
    )
    # Regex: (?i)      = case-insensitive match
    #         fkmprd-db = hostname pattern for Dedge production Db2 servers (e.g. p-no1fkmprd-db)
    if ($CatalogName -ne 'FKMPRD') {
        return $false
    }
    return $env:COMPUTERNAME -match '(?i)fkmprd-db'
}

function Get-AutoOsReserveMBFromCatalogAndHost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CatalogName,
        [Parameter(Mandatory = $true)]
        [double]$TotalHostMemoryMB
    )

    if (Test-IsProductionFkMPrdDbContext -CatalogName $CatalogName) {
        # Standard Edition on large PRD hosts (e.g. 128 GB): reserve ~12.5% for OS, at least 8192 MB
        $reserve = [int][math]::Max(8192, [math]::Floor($TotalHostMemoryMB / 8))
        Write-LogMessage "FKMPRD on fkmprd-db host: auto OsReserveMB=$($reserve) MB (Standard-style sizing; host total $($TotalHostMemoryMB) MB, OS reserve max(8192, total/8))." -Level INFO
        return $reserve
    }

    # Not FKMPRD on PRD host: assume Db2 Community Edition (8192 MB cap for Db2) — no prompt; leave headroom for OS
    $ceDb2CapMB = 8192
    $reserve = [int][math]::Max(512, [math]::Floor($TotalHostMemoryMB - $ceDb2CapMB))
    if (($TotalHostMemoryMB - $reserve) -lt 1024) {
        $reserve = [int][math]::Max(512, [math]::Floor($TotalHostMemoryMB - 1024))
    }
    Write-LogMessage "Community-style workload (catalog '$($CatalogName)'): auto OsReserveMB=$($reserve) MB (host total $($TotalHostMemoryMB) MB; Db2 cap $($ceDb2CapMB) MB assumed)." -Level INFO
    return $reserve
}

function Resolve-NecessaryScriptParameters {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SelectedDatabaseName,
        [Parameter(Mandatory = $false)]
        [int]$OsReserveMB,
        [Parameter(Mandatory = $false)]
        [bool]$AllowIncrease,
        [Parameter(Mandatory = $false)]
        [bool]$NonInteractive,
        [Parameter(Mandatory = $true)]
        [hashtable]$BoundParameters
    )

    if ($OsReserveMB -lt 0) {
        if ($OsReserveMB -ne -1) {
            throw "OsReserveMB must be -1 (automatic from catalog and host) or an explicit MB value (>= 512)."
        }
        $totalMb = Get-HostTotalPhysicalMemoryMB
        $OsReserveMB = Get-AutoOsReserveMBFromCatalogAndHost -CatalogName $SelectedDatabaseName -TotalHostMemoryMB $totalMb
    }
    if ($OsReserveMB -lt 512) {
        throw "OsReserveMB must be at least 512 (got $($OsReserveMB))."
    }

    if (-not $BoundParameters.ContainsKey('AllowIncrease')) {
        if ($NonInteractive) {
            $AllowIncrease = $true
            Write-LogMessage "NonInteractive: AllowIncrease:`$true (recommended so buffer pools can grow toward the memory target)." -Level INFO
        }
        else {
            $r = Get-UserConfirmationWithTimeout `
                -PromptMessage "If the memory target is larger than current buffer pools, may the script increase pool sizes? (Y) Recommended: Y when the host has spare RAM." `
                -TimeoutSeconds 45 `
                -AllowedResponses @("Y", "N") `
                -ProgressMessage "Allow bufferpool growth" `
                -DefaultResponse "Y"
            $AllowIncrease = ($r -eq "Y")
            Write-LogMessage "AllowIncrease resolved to $($AllowIncrease) (from prompt)." -Level INFO
        }
    }
    else {
        Write-LogMessage "AllowIncrease taken from parameter: $($AllowIncrease)." -Level INFO
    }

    return [PSCustomObject]@{
        OsReserveMB   = $OsReserveMB
        AllowIncrease = $AllowIncrease
    }
}

function Get-DatabaseContextFromConfig {
    param(
        [Parameter(Mandatory = $false)]
        [string]$RequestedDatabaseName = "",
        [Parameter(Mandatory = $false)]
        [string]$RequestedInstanceName = ""
    )

    $dbConfigs = @(Get-DatabasesV2Json | Where-Object { $_.IsActive -eq $true -and $_.Provider -eq "DB2" -and $_.ServerName -eq $env:COMPUTERNAME })
    $primaryAccessPoints = @(
        $dbConfigs |
            ForEach-Object { $_.AccessPoints } |
            Where-Object { $_.IsActive -eq $true -and $_.AccessPointType -eq "PrimaryDb" }
    )

    if ($primaryAccessPoints.Count -eq 0) {
        throw "No active PrimaryDb access points found in DatabasesV2.json for server $($env:COMPUTERNAME)."
    }

    $allowedDatabaseNames = @($primaryAccessPoints | Select-Object -ExpandProperty CatalogName -Unique | Sort-Object)
    if ($allowedDatabaseNames.Count -eq 0) {
        throw "No database names found in active PrimaryDb access points."
    }

    $selectedDatabaseName = $RequestedDatabaseName
    if ([string]::IsNullOrWhiteSpace($selectedDatabaseName) -or ($allowedDatabaseNames -notcontains $selectedDatabaseName)) {
        if ($allowedDatabaseNames.Count -eq 1) {
            $selectedDatabaseName = $allowedDatabaseNames[0]
            Write-LogMessage "Only one database available. Selected: $($selectedDatabaseName)" -Level INFO
        }
        else {
            # Catalog names often share the same first letter (e.g. FKMFUT, FKMTST) — use numbered menu (AddNumberToAllowedResponses) per Dedge-core-modules-user-prompts.mdc
            $selectedDatabaseName = Get-UserConfirmationWithTimeout `
                -PromptMessage "Choose Database Name" `
                -TimeoutSeconds 45 `
                -AllowedResponses $allowedDatabaseNames `
                -ProgressMessage "Choose database name" `
                -AddNumberToAllowedResponses:$true `
                -ThrowOnTimeout
            Write-LogMessage "Chosen database: $($selectedDatabaseName)" -Level INFO
        }
    }
    else {
        Write-LogMessage "Using database from parameter: $($selectedDatabaseName)" -Level INFO
    }

    $selectedAccessPoint = $primaryAccessPoints | Where-Object { $_.CatalogName -eq $selectedDatabaseName } | Select-Object -First 1
    if ($null -eq $selectedAccessPoint) {
        throw "No PrimaryDb access point found for database $($selectedDatabaseName)."
    }

    $resolvedInstanceName = $selectedAccessPoint.InstanceName
    if (-not [string]::IsNullOrWhiteSpace($RequestedInstanceName) -and ($RequestedInstanceName -ne $resolvedInstanceName)) {
        Write-LogMessage "Instance name '$($RequestedInstanceName)' was supplied but the catalog '$($selectedDatabaseName)' is bound to instance '$($resolvedInstanceName)' in DatabasesV2.json; using '$($resolvedInstanceName)'." -Level INFO
    }

    return [PSCustomObject]@{
        DatabaseName = $selectedDatabaseName
        InstanceName = $resolvedInstanceName
    }
}

function Get-SystemMemorySnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ReservedMemoryMB
    )

    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalMemoryMB = [math]::Round(([double]$osInfo.TotalVisibleMemorySize / 1024), 2)
        $freeMemoryMB = [math]::Round(([double]$osInfo.FreePhysicalMemory / 1024), 2)
        $usableForDb2MB = [math]::Max(1024, [math]::Floor($totalMemoryMB - $ReservedMemoryMB))

        return [PSCustomObject]@{
            TotalMemoryMB  = $totalMemoryMB
            FreeMemoryMB   = $freeMemoryMB
            ReservedOsMB   = $ReservedMemoryMB
            UsableForDb2MB = $usableForDb2MB
        }
    }
    catch {
        Write-LogMessage "Failed to read OS memory with CIM; using Get-ComputerInfo fallback." -Level INFO -Exception $_
        $computerInfo = Get-ComputerInfo
        $totalMemoryMB = [math]::Round(([double]$computerInfo.CsPhysicallyInstalledMemory / 1MB), 2)
        $usableForDb2MB = [math]::Max(1024, [math]::Floor($totalMemoryMB - $ReservedMemoryMB))
        return [PSCustomObject]@{
            TotalMemoryMB  = $totalMemoryMB
            FreeMemoryMB   = 0
            ReservedOsMB   = $ReservedMemoryMB
            UsableForDb2MB = $usableForDb2MB
        }
    }
}

function Convert-BufferPoolsToReportRows {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$BufferPools
    )

    $reportRows = @()
    foreach ($bufferPool in $BufferPools) {
        $bpNameValue = if ($null -ne $bufferPool.BPNAME) { $bufferPool.BPNAME } else { $bufferPool.BpName }
        $bpIdValue = if ($null -ne $bufferPool.BUFFERPOOLID) { $bufferPool.BUFFERPOOLID } else { $bufferPool.BufferPoolId }
        $nPagesValue = if ($null -ne $bufferPool.NPAGES) { $bufferPool.NPAGES } else { $bufferPool.NPages }
        $pageSizeValue = if ($null -ne $bufferPool.PAGESIZE) { $bufferPool.PAGESIZE } else { $bufferPool.PageSize }

        $sizeMB = [math]::Round((([double]$nPagesValue * [double]$pageSizeValue) / 1MB), 2)
        $reportRows += [PSCustomObject]@{
            BpName       = $bpNameValue
            BufferPoolId = [int]$bpIdValue
            NPages       = [int]$nPagesValue
            PageSize     = [int]$pageSizeValue
            SizeMB       = $sizeMB
        }
    }

    return $reportRows | Sort-Object -Property BufferPoolId
}

function Invoke-Db2QueryRows {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [string]$SqlQuery
    )

    $db2Commands = @()
    $db2Commands += Get-SetInstanceNameCommand -WorkObject $WorkObject
    $db2Commands += Get-ConnectCommand -WorkObject $WorkObject
    $db2Commands += "echo __QSTART__"
    $db2Commands += "db2 -x `"$SqlQuery`""
    $db2Commands += "echo __QEND__"
    $db2Commands += "db2 connect reset"
    $db2Commands += "db2 terminate"

    $output = Invoke-Db2ContentAsScript -Content $db2Commands -ExecutionType BAT -IgnoreErrors:$false
    $rows = @()
    $inside = $false
    foreach ($line in ($output -split "`r?`n")) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -eq "__QSTART__") {
            $inside = $true
            continue
        }
        if ($trimmedLine -eq "__QEND__") {
            break
        }
        if (-not $inside -or [string]::IsNullOrWhiteSpace($trimmedLine)) {
            continue
        }
        if ($trimmedLine -like "DB20000I*") {
            continue
        }
        if ($trimmedLine -match '^[A-Za-z]:\\.*>\s*') {
            continue
        }
        $rows += $trimmedLine
    }

    return $rows
}

function Get-Db2BufferPoolsInfoByDb2Script {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject
    )

    $sql = "SELECT RTRIM(BPNAME) || CHR(9) || CHAR(NPAGES) || CHR(9) || CHAR(PAGESIZE) || CHR(9) || CHAR(BUFFERPOOLID) FROM SYSCAT.BUFFERPOOLS ORDER BY BUFFERPOOLID"
    $rows = @(Invoke-Db2QueryRows -WorkObject $WorkObject -SqlQuery $sql)

    $bufferPools = @()
    foreach ($row in $rows) {
        $parts = $row.Split("`t")
        if ($parts.Count -lt 4) {
            continue
        }
        $bufferPools += [PSCustomObject]@{
            BPNAME       = $parts[0].Trim()
            NPAGES       = [int]$parts[1].Trim()
            PAGESIZE     = [int]$parts[2].Trim()
            BUFFERPOOLID = [int]$parts[3].Trim()
        }
    }

    if ($bufferPools.Count -eq 0) {
        throw "No buffer pools were returned from SYSCAT.BUFFERPOOLS for database $($WorkObject.DatabaseName)."
    }

    Add-Member -InputObject $WorkObject -NotePropertyName BufferPools -NotePropertyValue $bufferPools -Force
    return $WorkObject
}

function Get-TargetBufferPoolRows {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$CurrentRows,
        [Parameter(Mandatory = $true)]
        [double]$TargetTotalBufferPoolMB,
        [Parameter(Mandatory = $false)]
        [bool]$AllowIncrease = $false
    )

    $resizableRows = @($CurrentRows | Where-Object { $_.NPages -gt 0 })
    $currentTotalMB = [double](($resizableRows | Measure-Object -Property SizeMB -Sum).Sum)
    if ($currentTotalMB -le 0) {
        return @($CurrentRows)
    }

    $effectiveTargetTotalBufferPoolMB = [double]$TargetTotalBufferPoolMB
    if (-not $AllowIncrease) {
        $effectiveTargetTotalBufferPoolMB = [math]::Min($effectiveTargetTotalBufferPoolMB, $currentTotalMB)
    }

    $scaleFactor = $effectiveTargetTotalBufferPoolMB / $currentTotalMB
    $targetRows = @()
    foreach ($row in $CurrentRows) {
        if ($row.NPages -le 0) {
            # Keep AUTOMATIC/SPECIAL bufferpool sizing untouched.
            $targetRows += [PSCustomObject]@{
                BpName         = $row.BpName
                BufferPoolId   = $row.BufferPoolId
                PageSize       = $row.PageSize
                CurrentPages   = $row.NPages
                ProposedPages  = $row.NPages
                CurrentSizeMB  = $row.SizeMB
                ProposedSizeMB = $row.SizeMB
                DeltaMB        = 0
            }
            continue
        }

        $newPages = [math]::Floor([double]$row.NPages * $scaleFactor)
        $newPages = [math]::Max(1000, $newPages)
        $newSizeMB = [math]::Round((([double]$newPages * [double]$row.PageSize) / 1MB), 2)
        $targetRows += [PSCustomObject]@{
            BpName         = $row.BpName
            BufferPoolId   = $row.BufferPoolId
            PageSize       = $row.PageSize
            CurrentPages   = $row.NPages
            ProposedPages  = [int]$newPages
            CurrentSizeMB  = $row.SizeMB
            ProposedSizeMB = $newSizeMB
            DeltaMB        = [math]::Round(($newSizeMB - $row.SizeMB), 2)
        }
    }

    return $targetRows | Sort-Object -Property BufferPoolId
}

function Invoke-BufferPoolAdjustments {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$WorkObject,
        [Parameter(Mandatory = $true)]
        [object[]]$TargetRows
    )

    $commands = @()
    $commands += Get-SetInstanceNameCommand -WorkObject $WorkObject
    $commands += Get-ConnectCommand -WorkObject $WorkObject

    foreach ($targetRow in $TargetRows) {
        if ($targetRow.CurrentPages -ne $targetRow.ProposedPages) {
            $commands += "db2 `"ALTER BUFFERPOOL $($targetRow.BpName) SIZE $($targetRow.ProposedPages)`""
        }
    }

    $commands += "db2 terminate"
    if ($commands.Count -le 3) {
        Write-LogMessage "No bufferpool page changes were required." -Level INFO
        return
    }

    $output = Invoke-Db2ContentAsScript -Content $commands -ExecutionType BAT -IgnoreErrors:$false
    Write-LogMessage "Apply output:" -Level INFO
    Write-LogMessage $output -Level INFO
}

try {
    Write-LogMessage $(Get-InitScriptName) -Level JOB_STARTED

    Test-Db2ServerAndAdmin

    $allowedDbNamesEarly = @(Get-PrimaryDbCatalogNamesForThisServer)
    if ($allowedDbNamesEarly.Count -eq 0) {
        throw "No active PrimaryDb catalog names found in DatabasesV2.json for $($env:COMPUTERNAME)."
    }
    if ($NonInteractive -and $allowedDbNamesEarly.Count -gt 1 -and [string]::IsNullOrWhiteSpace($DatabaseName)) {
        throw "NonInteractive: specify -DatabaseName. Options: $($allowedDbNamesEarly -join ', ')."
    }

    $dbContext = Get-DatabaseContextFromConfig -RequestedDatabaseName $DatabaseName -RequestedInstanceName $InstanceName
    $selectedDatabaseName = $dbContext.DatabaseName
    $selectedInstanceName = $dbContext.InstanceName

    $resolvedParams = Resolve-NecessaryScriptParameters `
        -SelectedDatabaseName $selectedDatabaseName `
        -OsReserveMB $OsReserveMB `
        -AllowIncrease $AllowIncrease `
        -NonInteractive $NonInteractive `
        -BoundParameters $PSBoundParameters

    $OsReserveMB = $resolvedParams.OsReserveMB
    $AllowIncrease = $resolvedParams.AllowIncrease

    $workObject = Get-DefaultWorkObjectsCommon -DatabaseName $selectedDatabaseName -DatabaseType PrimaryDb -InstanceName $selectedInstanceName -QuickMode
    if ($workObject -is [array]) {
        $workObject = $workObject[-1]
    }

    $workObject = Get-ExistingInstances -WorkObject $workObject
    if ($workObject -is [array]) {
        $workObject = $workObject[-1]
    }

    $workObject = Get-Db2Version -WorkObject $workObject
    if ($workObject -is [array]) {
        $workObject = $workObject[-1]
    }

    $workObject = Get-Db2BufferPoolsInfoByDb2Script -WorkObject $workObject
    if ($workObject -is [array]) {
        $workObject = $workObject[-1]
    }

    $workObject = Get-Db2MemoryConfiguration -WorkObject $workObject
    if ($workObject -is [array]) {
        $workObject = $workObject[-1]
    }

    $memorySnapshot = Get-SystemMemorySnapshot -ReservedMemoryMB $OsReserveMB
    $currentRows = Convert-BufferPoolsToReportRows -BufferPools $workObject.BufferPools
    $currentTotalBufferPoolMB = [double](($currentRows | Measure-Object -Property SizeMB -Sum).Sum)

    $instanceMemoryMB = [double]$workObject.MemoryConfiguration.InstanceMemoryMB
    $effectiveMemoryCapMB = if ($instanceMemoryMB -gt 0) {
        [math]::Min($instanceMemoryMB, [double]$memorySnapshot.UsableForDb2MB)
    }
    else {
        [double]$memorySnapshot.UsableForDb2MB
    }

    $isProductionFkMPrd = Test-IsProductionFkMPrdDbContext -CatalogName $selectedDatabaseName
    if (-not $isProductionFkMPrd) {
        $ceCapMb = 8192
        $beforeCap = $effectiveMemoryCapMB
        $effectiveMemoryCapMB = [math]::Min($ceCapMb, $effectiveMemoryCapMB)
        if ($beforeCap -gt $ceCapMb) {
            Write-LogMessage "Db2 Community Edition limit applied for buffer-pool sizing: effective cap reduced from $([math]::Round($beforeCap, 2)) MB to $($ceCapMb) MB (not FKMPRD on fkmprd-db host)." -Level INFO
        }
    }

    $targetRatio = if ($workObject.Db2Version -eq "StandardEdition") { 0.45 } else { 0.35 }
    $targetTotalBufferPoolMB = [math]::Max(512, [math]::Floor($effectiveMemoryCapMB * $targetRatio))
    $targetRows = Get-TargetBufferPoolRows -CurrentRows $currentRows -TargetTotalBufferPoolMB $targetTotalBufferPoolMB -AllowIncrease $AllowIncrease

    Write-LogMessage "========================================" -Level INFO
    Write-LogMessage "DB2 BUFFERPOOL AUTO-TUNE REPORT" -Level INFO
    Write-LogMessage "========================================" -Level INFO
    Write-LogMessage "Server: $($env:COMPUTERNAME)" -Level INFO
    Write-LogMessage "Instance: $($selectedInstanceName)" -Level INFO
    Write-LogMessage "Database: $($selectedDatabaseName)" -Level INFO
    Write-LogMessage "Db2 Edition: $($workObject.Db2Version)" -Level INFO
    Write-LogMessage "INSTANCE_MEMORY: $($workObject.MemoryConfiguration.InstanceMemory) ($($workObject.MemoryConfiguration.InstanceMemoryMB) MB)" -Level INFO
    Write-LogMessage "DATABASE_MEMORY: $($workObject.MemoryConfiguration.DatabaseMemory) ($($workObject.MemoryConfiguration.DatabaseMemoryMB) MB)" -Level INFO
    Write-LogMessage "SELF_TUNING_MEM: $($workObject.MemoryConfiguration.SelfTuningMem)" -Level INFO
    Write-LogMessage "Total System Memory MB: $($memorySnapshot.TotalMemoryMB)" -Level INFO
    Write-LogMessage "Free System Memory MB: $($memorySnapshot.FreeMemoryMB)" -Level INFO
    Write-LogMessage "OS Reserve MB: $($memorySnapshot.ReservedOsMB)" -Level INFO
    Write-LogMessage "Usable For Db2 MB: $($memorySnapshot.UsableForDb2MB)" -Level INFO
    Write-LogMessage "Effective Memory Cap MB: $([math]::Round($effectiveMemoryCapMB, 2))" -Level INFO
    Write-LogMessage "Target Ratio: $([math]::Round($targetRatio * 100, 0))%" -Level INFO
    Write-LogMessage "Current Total Bufferpool MB: $([math]::Round($currentTotalBufferPoolMB, 2))" -Level INFO
    Write-LogMessage "Target Total Bufferpool MB: $([math]::Round($targetTotalBufferPoolMB, 2))" -Level INFO
    Write-LogMessage "AllowIncrease: $($AllowIncrease)" -Level INFO
    Write-LogMessage "========================================" -Level INFO

    $currentTable = $currentRows | Select-Object BpName, BufferPoolId, NPages, PageSize, SizeMB | Format-Table -AutoSize | Out-String
    Write-LogMessage "Current bufferpools:" -Level INFO
    Write-LogMessage $currentTable -Level INFO

    $proposalTable = $targetRows | Select-Object BpName, BufferPoolId, CurrentPages, ProposedPages, CurrentSizeMB, ProposedSizeMB, DeltaMB | Format-Table -AutoSize | Out-String
    Write-LogMessage "Proposed bufferpool adjustments:" -Level INFO
    Write-LogMessage $proposalTable -Level INFO

    $doApply = $false
    if ($PSBoundParameters.ContainsKey('ForceApply')) {
        $doApply = $ForceApply
        Write-LogMessage "Apply step driven by -ForceApply parameter: $($doApply)." -Level INFO
    }
    elseif ($NonInteractive) {
        $doApply = $false
        Write-LogMessage "NonInteractive: not applying changes (report-only). Pass -ForceApply:`$true to apply without a prompt." -Level INFO
    }
    else {
        $applyChoice = Get-UserConfirmationWithTimeout `
            -PromptMessage "Apply these bufferpool adjustments on the server now? (Y) or keep report-only (N). Recommended: Y only after you have reviewed the table above." `
            -TimeoutSeconds 45 `
            -AllowedResponses @("Y", "N") `
            -ProgressMessage "Apply bufferpool adjustments" `
            -DefaultResponse "N"
        $doApply = ($applyChoice -eq "Y")
        Write-LogMessage "Apply choice after preview: $($doApply)." -Level INFO
    }

    if ($doApply) {
        Write-LogMessage "Applying bufferpool adjustments..." -Level INFO
        Invoke-BufferPoolAdjustments -WorkObject $workObject -TargetRows $targetRows

        Write-LogMessage "Reloading bufferpool information after changes..." -Level INFO
        $workObject = Get-Db2BufferPoolsInfoByDb2Script -WorkObject $workObject
        if ($workObject -is [array]) {
            $workObject = $workObject[-1]
        }

        $postRows = Convert-BufferPoolsToReportRows -BufferPools $workObject.BufferPools
        $postTable = $postRows | Select-Object BpName, BufferPoolId, NPages, PageSize, SizeMB | Format-Table -AutoSize | Out-String
        Write-LogMessage "Post-change bufferpools:" -Level INFO
        Write-LogMessage $postTable -Level INFO
    }
    else {
        Write-LogMessage "No changes applied. Report-only run completed." -Level INFO
    }


    Write-LogMessage $(Get-InitScriptName) -Level JOB_COMPLETED
}
catch {
    Write-LogMessage "Error in Db2 bufferpool auto-tune script: $($_.Exception.Message)" -Level ERROR -Exception $_
    Write-LogMessage $(Get-InitScriptName) -Level JOB_FAILED
    exit 1
}
