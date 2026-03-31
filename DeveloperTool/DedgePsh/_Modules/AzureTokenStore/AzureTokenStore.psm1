function Get-AzureAccessTokensFileCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$FileName = 'AzureAccessTokens.json'
    )

    $searchRoots = @()

    if ($env:OneDriveCommercial) { $searchRoots += $env:OneDriveCommercial }
    if ($env:OneDrive) { $searchRoots += $env:OneDrive }

    if ($env:USERPROFILE) {
        $searchRoots += Join-Path $env:USERPROFILE 'Documents'
        $searchRoots += Join-Path $env:USERPROFILE 'AppData\Roaming'
        $searchRoots += Join-Path $env:USERPROFILE 'AppData\Local'
    }

    $seen = @{}
    $results = @()

    foreach ($root in $searchRoots) {
        if (-not $root) { continue }
        if (-not (Test-Path $root -PathType Container)) { continue }

        $candidate = Join-Path $root $FileName
        if (-not (Test-Path $candidate -PathType Leaf)) { continue }

        $fi = Get-Item -LiteralPath $candidate
        if (-not $seen.ContainsKey($fi.FullName)) {
            $seen[$fi.FullName] = $true
            $results += [PSCustomObject]@{
                FullName      = $fi.FullName
                LastWriteTime = $fi.LastWriteTime
            }
        }
    }

    return $results
}

function Get-AzureAccessTokensFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$FileName = 'AzureAccessTokens.json'
    )

    $candidates = Get-AzureAccessTokensFileCandidates -FileName $FileName

    if (-not $candidates -or $candidates.Count -eq 0) {
        return [PSCustomObject]@{
            SelectedPath = $null
            Candidates   = @()
        }
    }

    $selected = $candidates | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1

    return [PSCustomObject]@{
        SelectedPath = $selected.FullName
        Candidates   = $candidates
    }
}

function Get-AzureAccessTokens {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$FileName = 'AzureAccessTokens.json'
    )

    $fileInfo = Get-AzureAccessTokensFile -FileName $FileName
    if (-not $fileInfo.SelectedPath) {
        return @()
    }

    $data = Get-Content -LiteralPath $fileInfo.SelectedPath -Raw | ConvertFrom-Json

    if ($data -is [System.Array]) { return $data }
    if ($null -ne $data) { return @($data) }

    return @()
}

function Get-AzureAccessTokenById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IdLike,

        [Parameter(Mandatory = $false)]
        [string]$FileName = 'AzureAccessTokens.json'
    )

    $tokens = Get-AzureAccessTokens -FileName $FileName
    if (-not $tokens) { return $null }

    return ($tokens | Where-Object { $_.Id -like $IdLike } | Select-Object -First 1)
}

Export-ModuleMember -Function Get-AzureAccessTokensFileCandidates, Get-AzureAccessTokensFile, Get-AzureAccessTokens, Get-AzureAccessTokenById
