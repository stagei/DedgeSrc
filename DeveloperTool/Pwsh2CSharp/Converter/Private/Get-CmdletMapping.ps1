$script:CmdletMappingCache = $null

function Get-CmdletMapping {
    <#
    .SYNOPSIS
        Loads and caches the CmdletMappings.json table.
    #>
    param(
        [string]$MappingsPath
    )

    if ($null -eq $script:CmdletMappingCache) {
        if (-not $MappingsPath) {
            $MappingsPath = Join-Path $PSScriptRoot '..\CmdletMappings.json'
        }
        if (Test-Path -LiteralPath $MappingsPath) {
            $raw = Get-Content -LiteralPath $MappingsPath -Raw -Encoding UTF8
            $script:CmdletMappingCache = $raw | ConvertFrom-Json -AsHashtable
        }
        else {
            $script:CmdletMappingCache = @{}
        }
    }
    return $script:CmdletMappingCache
}
