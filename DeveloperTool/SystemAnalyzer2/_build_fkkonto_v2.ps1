$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'AnalysisProfiles2\FkKonto\all.json'
$text = Get-Content -LiteralPath $src -Raw
$doc = $text | ConvertFrom-Json -AsHashtable
$entries = $doc['entries']
$doc.Remove('entries')
$doc['version'] = 2
$doc['technologies'] = @{
    cobol = @{
        vendor   = 'rocket'
        product  = 'visual-cobol'
        version  = '11.0'
        platform = 'windows-x64'
        database = $doc['database']
        entries  = $entries
    }
    powershell = @{ entries = @() }
    csharp     = @{ entries = @() }
    python     = @{ entries = @() }
    node       = @{ entries = @() }
    go         = @{ entries = @() }
}
$out = $doc | ConvertTo-Json -Depth 100
Set-Content -LiteralPath $src -Value $out -Encoding utf8
