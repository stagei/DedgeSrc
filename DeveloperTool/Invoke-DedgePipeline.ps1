<#
.SYNOPSIS
    Orchestrates the full Dedge conversion, rebranding, and AI documentation pipeline.

.DESCRIPTION
    Runs up to 5 phases in sequence:
      Phase 1 (Convert)      — Convert-AppsToDedge.ps1 (copy + rebrand)
      Phase 2 (Competitors)  — AI competitor research per product
      Phase 3 (Docs)         — AI per-product business documentation
      Phase 4 (Portfolio)    — AI master portfolio regeneration
      Phase 5 (Screenshots)  — Browser/WPF screenshot capture per product

    Each AI phase uses Invoke-DedgeProtocol.ps1 with protocol definitions
    from the AiProtocols/ folder.

.PARAMETER Phases
    Which phases to run.  Default: All.
    Values: All, Convert, Competitors, Docs, Portfolio, Screenshots

.PARAMETER Products
    Optional list of product names to process (from all-projects.json).
    If omitted, all products are processed.

.PARAMETER OverwriteExisting
    Ignore skipIfExists flags in protocol definitions and regenerate outputs.

.PARAMETER DryRun
    Show what would happen without executing anything.

.EXAMPLE
    pwsh.exe -File .\Invoke-DedgePipeline.ps1

.EXAMPLE
    pwsh.exe -File .\Invoke-DedgePipeline.ps1 -Phases Competitors,Docs -Products DbExplorer,DedgeAuth

.EXAMPLE
    pwsh.exe -File .\Invoke-DedgePipeline.ps1 -Phases Screenshots -OverwriteExisting
#>
[CmdletBinding()]
param(
    [ValidateSet('All', 'Convert', 'Competitors', 'Docs', 'Portfolio', 'Screenshots')]
    [string[]]$Phases = @('All'),

    [string[]]$Products = @(),

    [switch]$OverwriteExisting,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module GlobalFunctions -Force

$Script:Root = $PSScriptRoot
$Script:AllProjectsPath = Join-Path $Script:Root 'all-projects.json'
$Script:ConvertAppsPath = Join-Path $Script:Root 'convertapps.json'
$Script:ProtocolRunner  = Join-Path $Script:Root 'Invoke-DedgeProtocol.ps1'
$Script:ConvertScript   = Join-Path $Script:Root 'Convert-AppsToDedge.ps1'
$Script:BusinessDocs    = Join-Path $Script:Root '_BusinessDocs'
$Script:ScreenshotsRoot = Join-Path $Script:BusinessDocs 'screenshots'

$Script:LogFile = Join-Path $Script:Root "Invoke-DedgePipeline_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-PipeLog {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','OK')][string]$Level = 'INFO')
    Write-LogMessage $Message -Level $Level
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$($Level)] $($Message)"
    [System.IO.File]::AppendAllText($Script:LogFile, "$($line)`r`n")
}

# ═════════════════════════════════════════════════════════════════════════════
#  Load project catalogs
# ═════════════════════════════════════════════════════════════════════════════

if (-not (Test-Path $Script:AllProjectsPath)) {
    throw "all-projects.json not found: $($Script:AllProjectsPath)"
}
if (-not (Test-Path $Script:ConvertAppsPath)) {
    throw "convertapps.json not found: $($Script:ConvertAppsPath)"
}

$allProjects = (Get-Content $Script:AllProjectsPath -Raw -Encoding UTF8 | ConvertFrom-Json).projects
$convertApps = (Get-Content $Script:ConvertAppsPath -Raw -Encoding UTF8 | ConvertFrom-Json).projects

if ($Products.Count -gt 0) {
    $allProjects = $allProjects | Where-Object { $Products -contains $_.name }
    $convertApps = $convertApps | Where-Object { $Products -contains $_.name }
}

Write-PipeLog "Pipeline starting — $($allProjects.Count) products, Phases: $($Phases -join ', ')"
if ($DryRun) { Write-PipeLog '*** DRY RUN ***' -Level WARN }

$runAll = $Phases -contains 'All'
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$pipelineSw = [System.Diagnostics.Stopwatch]::StartNew()

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 1: Convert (copy + rebrand)
# ═════════════════════════════════════════════════════════════════════════════

if ($runAll -or $Phases -contains 'Convert') {
    Write-PipeLog ''
    Write-PipeLog '═══════════════════════════════════════════════════════'
    Write-PipeLog 'PHASE 1: Convert (copy + rebrand)'
    Write-PipeLog '═══════════════════════════════════════════════════════'

    if ($DryRun) {
        Write-PipeLog '[DryRun] Would run Convert-AppsToDedge.ps1' -Level WARN
    } else {
        $convertArgs = @()
        if ($DryRun) { $convertArgs += '-DryRun' }
        & pwsh.exe -NoProfile -File $Script:ConvertScript @convertArgs
        if ($LASTEXITCODE -ne 0) {
            Write-PipeLog 'Convert-AppsToDedge.ps1 failed' -Level ERROR
        } else {
            Write-PipeLog 'Phase 1 complete' -Level OK
        }
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 2: Competitor Research
# ═════════════════════════════════════════════════════════════════════════════

if ($runAll -or $Phases -contains 'Competitors') {
    Write-PipeLog ''
    Write-PipeLog '═══════════════════════════════════════════════════════'
    Write-PipeLog 'PHASE 2: Competitor Research'
    Write-PipeLog '═══════════════════════════════════════════════════════'

    foreach ($proj in $allProjects) {
        Write-PipeLog "  Competitors: $($proj.name)"
        $placeholders = @{
            ProductName        = $proj.name
            ProductDescription = $proj.description
            ProductCategory    = $proj.category
            ProductStack       = $proj.stack
        }

        $protoArgs = @{
            ProtocolName     = 'competitor-research'
            Placeholders     = $placeholders
            ProtocolsRoot    = (Join-Path $Script:Root 'AiProtocols')
            OutputRoot       = $Script:Root
        }
        if ($OverwriteExisting) { $protoArgs.OverwriteExisting = $true }
        if ($DryRun) { $protoArgs.DryRun = $true }

        $r = & $Script:ProtocolRunner @protoArgs
        $results.Add($r)
        Write-PipeLog "    -> $($r.Status) ($($r.DurationMs)ms)" -Level $(if ($r.IsError) { 'ERROR' } else { 'INFO' })
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 3: Per-Product Business Docs
# ═════════════════════════════════════════════════════════════════════════════

if ($runAll -or $Phases -contains 'Docs') {
    Write-PipeLog ''
    Write-PipeLog '═══════════════════════════════════════════════════════'
    Write-PipeLog 'PHASE 3: Per-Product Business Documentation'
    Write-PipeLog '═══════════════════════════════════════════════════════'

    foreach ($proj in $allProjects) {
        Write-PipeLog "  BusinessDoc: $($proj.name)"

        $copyToPath = ($convertApps | Where-Object { $_.name -eq $proj.name }).copyToPath
        if (-not $copyToPath) { $copyToPath = '' }

        $competitorJson = Join-Path $Script:BusinessDocs "competitors\$($proj.name)-competitors.json"
        if (-not (Test-Path -LiteralPath $competitorJson)) { $competitorJson = '' }

        $placeholders = @{
            ProductName        = $proj.name
            ProductDescription = $proj.description
            ProductCategory    = $proj.category
            ProductStack       = $proj.stack
            CopyToPath         = $copyToPath
            CompetitorJson     = $competitorJson
        }

        $protoArgs = @{
            ProtocolName     = 'product-business-doc'
            Placeholders     = $placeholders
            ProtocolsRoot    = (Join-Path $Script:Root 'AiProtocols')
            OutputRoot       = $Script:Root
        }
        if ($OverwriteExisting) { $protoArgs.OverwriteExisting = $true }
        if ($DryRun) { $protoArgs.DryRun = $true }

        $r = & $Script:ProtocolRunner @protoArgs
        $results.Add($r)
        Write-PipeLog "    -> $($r.Status) ($($r.DurationMs)ms)" -Level $(if ($r.IsError) { 'ERROR' } else { 'INFO' })
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 4: Portfolio Update
# ═════════════════════════════════════════════════════════════════════════════

if ($runAll -or $Phases -contains 'Portfolio') {
    Write-PipeLog ''
    Write-PipeLog '═══════════════════════════════════════════════════════'
    Write-PipeLog 'PHASE 4: Master Portfolio Update'
    Write-PipeLog '═══════════════════════════════════════════════════════'

    $portfolioPath = Join-Path $Script:BusinessDocs 'Dedge-Business-Portfolio.md'
    $productListJson = ($allProjects | Select-Object name, category, description | ConvertTo-Json -Depth 5 -Compress)

    $placeholders = @{
        TotalProducts         = $allProjects.Count.ToString()
        ProductListJson       = $productListJson
        ExistingPortfolioPath = $portfolioPath
    }

    $protoArgs = @{
        ProtocolName     = 'portfolio-update'
        Placeholders     = $placeholders
        ProtocolsRoot    = (Join-Path $Script:Root 'AiProtocols')
        OutputRoot       = $Script:Root
    }
    if ($OverwriteExisting) { $protoArgs.OverwriteExisting = $true }
    if ($DryRun) { $protoArgs.DryRun = $true }

    $r = & $Script:ProtocolRunner @protoArgs
    $results.Add($r)
    Write-PipeLog "  -> $($r.Status) ($($r.DurationMs)ms)" -Level $(if ($r.IsError) { 'ERROR' } else { 'INFO' })
}

# ═════════════════════════════════════════════════════════════════════════════
#  Phase 5: Screenshots
# ═════════════════════════════════════════════════════════════════════════════

if ($runAll -or $Phases -contains 'Screenshots') {
    Write-PipeLog ''
    Write-PipeLog '═══════════════════════════════════════════════════════'
    Write-PipeLog 'PHASE 5: Screenshot Capture'
    Write-PipeLog '═══════════════════════════════════════════════════════'

    # .NET web apps — use web-screenshot protocol
    $webTargets = @(
        @{ Key = 'AiDoc.WebNew';           Project = 'C:\opt\src\AiDoc.WebNew\AiDoc.WebNew.csproj';                                                          Port = '18484'; UrlPaths = '/AiDocNew/scalar/v1,/AiDocNew/' }
        @{ Key = 'CursorDb2McpServer';     Project = 'C:\opt\src\CursorDb2McpServer\CursorDb2McpServer\CursorDb2McpServer.csproj';                            Port = '15200'; UrlPaths = '/' }
        @{ Key = 'AutoDocJson';            Project = 'C:\opt\src\AutoDocJson\AutoDocJson.Web\AutoDocJson.Web.csproj';                                         Port = '15280'; UrlPaths = '/health,/,/docs/' }
        @{ Key = 'SystemAnalyzer';         Project = 'C:\opt\src\SystemAnalyzer\src\SystemAnalyzer.Web\SystemAnalyzer.Web.csproj';                            Port = '15042'; UrlPaths = '/scalar/v1,/' }
        @{ Key = 'ServerMonitor';          Project = 'C:\opt\src\ServerMonitor\ServerMonitorDashboard\src\ServerMonitorDashboard\ServerMonitorDashboard.csproj'; Port = '18998'; UrlPaths = '/,/health' }
        @{ Key = 'GenericLogHandler';      Project = 'C:\opt\src\GenericLogHandler\src\GenericLogHandler.WebApi\GenericLogHandler.WebApi.csproj';              Port = '18110'; UrlPaths = '/scalar/v1,/health' }
        @{ Key = 'SqlMermaidErdTools-Web'; Project = 'C:\opt\src\SqlMermaidErdTools\srcWeb\ProductStore.csproj';                                              Port = '15288'; UrlPaths = '/,/api/products' }
        @{ Key = 'SqlMermaidErdTools-REST'; Project = 'C:\opt\src\SqlMermaidErdTools\srcREST\SqlMermaidApi.csproj';                                            Port = '15001'; UrlPaths = '/swagger,/health' }
        @{ Key = 'DedgeAuth';             Project = 'C:\opt\src\FkAuth\src\FkAuth.Api\FkAuth.Api.csproj';                                                    Port = '18100'; UrlPaths = '/scalar/v1,/health' }
    )

    # WPF/WinForms desktop apps — use wpf-screenshot protocol
    $wpfTargets = @(
        @{ Key = 'DbExplorer';    ProjectPath = 'C:\opt\src\DedgeSrc\DbExplorer\DbExplorer\DbExplorer.csproj';         ExePath = ''; WindowTitle = 'DbExplorer' }
        @{ Key = 'MouseJiggler';  ProjectPath = 'C:\opt\src\DedgeSrc\MouseJiggler\MouseJiggler\MouseJiggler.csproj';   ExePath = ''; WindowTitle = 'MouseJiggler' }
        @{ Key = 'RemoteConnect'; ProjectPath = 'C:\opt\src\DedgeSrc\RemoteConnect\DedgeRemoteConnect\DedgeRemoteConnect.csproj'; ExePath = ''; WindowTitle = 'RemoteConnect' }
    )

    # Static sites
    $staticTargets = @(
        @{ Key = 'OnePager';                   StaticPath = 'C:\opt\src\DedgeSrc\Misc\WordPress\onepager\index.html'; UrlPaths = '/' }
        @{ Key = 'LillestromOsteopati-Static'; StaticPath = 'C:\opt\src\DedgeSrc\Misc\LillestromOsteopati\index.html'; UrlPaths = '/' }
    )

    if ($Products.Count -gt 0) {
        $webTargets    = $webTargets    | Where-Object { $Products -contains $_.Key }
        $wpfTargets    = $wpfTargets    | Where-Object { $Products -contains $_.Key }
        $staticTargets = $staticTargets | Where-Object { $Products -contains $_.Key }
    }

    # --- Web screenshots ---
    foreach ($t in $webTargets) {
        Write-PipeLog "  WebScreenshot: $($t.Key)"
        $screenshotDir = Join-Path $Script:ScreenshotsRoot $t.Key

        $placeholders = @{
            AppKey        = $t.Key
            AppType       = 'dotnet'
            Project       = $t.Project
            Port          = $t.Port
            UrlPaths      = $t.UrlPaths
            StaticPath    = ''
            ScreenshotDir = $screenshotDir
        }

        $protoArgs = @{
            ProtocolName     = 'web-screenshot'
            Placeholders     = $placeholders
            ProtocolsRoot    = (Join-Path $Script:Root 'AiProtocols')
            OutputRoot       = $Script:Root
        }
        if ($OverwriteExisting) { $protoArgs.OverwriteExisting = $true }
        if ($DryRun) { $protoArgs.DryRun = $true }

        $r = & $Script:ProtocolRunner @protoArgs
        $results.Add($r)
        Write-PipeLog "    -> $($r.Status) ($($r.DurationMs)ms)" -Level $(if ($r.IsError) { 'ERROR' } else { 'INFO' })
    }

    # --- WPF/WinForms screenshots ---
    foreach ($t in $wpfTargets) {
        Write-PipeLog "  WpfScreenshot: $($t.Key)"
        $screenshotDir = Join-Path $Script:ScreenshotsRoot $t.Key

        $exePath = $t.ExePath
        if (-not $exePath -and $t.ProjectPath) {
            $projDir = Split-Path $t.ProjectPath -Parent
            $projName = [System.IO.Path]::GetFileNameWithoutExtension($t.ProjectPath)
            $exePath = Join-Path $projDir "bin\Debug\net10.0-windows\$($projName).exe"
        }

        $placeholders = @{
            AppKey         = $t.Key
            ExePath        = $exePath
            ProjectPath    = ($t.ProjectPath ?? '')
            WindowTitle    = $t.WindowTitle
            ScreenshotDir  = $screenshotDir
            StartupWaitSec = '15'
        }

        $protoArgs = @{
            ProtocolName     = 'wpf-screenshot'
            Placeholders     = $placeholders
            ProtocolsRoot    = (Join-Path $Script:Root 'AiProtocols')
            OutputRoot       = $Script:Root
        }
        if ($OverwriteExisting) { $protoArgs.OverwriteExisting = $true }
        if ($DryRun) { $protoArgs.DryRun = $true }

        $r = & $Script:ProtocolRunner @protoArgs
        $results.Add($r)
        Write-PipeLog "    -> $($r.Status) ($($r.DurationMs)ms)" -Level $(if ($r.IsError) { 'ERROR' } else { 'INFO' })
    }

    # --- Static site screenshots ---
    foreach ($t in $staticTargets) {
        Write-PipeLog "  StaticScreenshot: $($t.Key)"
        $screenshotDir = Join-Path $Script:ScreenshotsRoot $t.Key

        $placeholders = @{
            AppKey        = $t.Key
            AppType       = 'static'
            Project       = ''
            Port          = ''
            UrlPaths      = $t.UrlPaths
            StaticPath    = $t.StaticPath
            ScreenshotDir = $screenshotDir
        }

        $protoArgs = @{
            ProtocolName     = 'web-screenshot'
            Placeholders     = $placeholders
            ProtocolsRoot    = (Join-Path $Script:Root 'AiProtocols')
            OutputRoot       = $Script:Root
        }
        if ($OverwriteExisting) { $protoArgs.OverwriteExisting = $true }
        if ($DryRun) { $protoArgs.DryRun = $true }

        $r = & $Script:ProtocolRunner @protoArgs
        $results.Add($r)
        Write-PipeLog "    -> $($r.Status) ($($r.DurationMs)ms)" -Level $(if ($r.IsError) { 'ERROR' } else { 'INFO' })
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  Summary
# ═════════════════════════════════════════════════════════════════════════════

$pipelineSw.Stop()
$okCount    = ($results | Where-Object { $_.Status -eq 'OK' }).Count
$skipCount  = ($results | Where-Object { $_.Status -eq 'Skipped' }).Count
$errCount   = ($results | Where-Object { $_.IsError -eq $true }).Count
$dryCount   = ($results | Where-Object { $_.Status -eq 'DryRun' }).Count

Write-PipeLog ''
Write-PipeLog '═══════════════════════════════════════════════════════'
Write-PipeLog "PIPELINE COMPLETE  OK=$($okCount)  Skipped=$($skipCount)  Errors=$($errCount)  DryRun=$($dryCount)  Time=$($pipelineSw.Elapsed.ToString('hh\:mm\:ss'))"
Write-PipeLog "Log: $($Script:LogFile)"
Write-PipeLog '═══════════════════════════════════════════════════════'

if ($errCount -gt 0) {
    Write-PipeLog '' -Level WARN
    Write-PipeLog 'Errors:' -Level WARN
    $results | Where-Object { $_.IsError -eq $true } | ForEach-Object {
        Write-PipeLog "  $($_.Protocol) / $($_.ProductName): $($_.Message)" -Level ERROR
    }
}

$results | Format-Table Protocol, ProductName, Status, DurationMs, IsError -AutoSize
return $results
