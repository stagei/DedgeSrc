<#
.SYNOPSIS
    Captures headless browser screenshots for .NET web apps listed in all-projects.json scope (C# only; skips PowerShell).

.DESCRIPTION
    Starts each app with dotnet run on a dedicated localhost port, waits until the port listens,
    then uses Microsoft Edge in headless mode to save PNG screenshots under
    _BusinessDocs/screenshots/CSharp/<AppName>/.

    Skips: PowerShell-only entries, library-only projects (DedgeCommon, SqlMmdConverter), Python/PHP/static sites.

.PARAMETER OutputRoot
    Root folder for screenshots (default: .../DeveloperTool/_BusinessDocs/screenshots/CSharp)

.PARAMETER SkipBuild
    If set, does not run dotnet build before run.

.PARAMETER Apps
    Optional subset of internal app keys (e.g. AutoDocJson, FkAuth). Default: all configured web apps.
#>
[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path (Join-Path (Join-Path $PSScriptRoot '_BusinessDocs') 'screenshots') 'CSharp'),
    [switch]$SkipBuild,
    [string[]]$Apps = @()
)

$ErrorActionPreference = 'Stop'

Import-Module GlobalFunctions -Force -ErrorAction SilentlyContinue
function Write-CapLog {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    if (Get-Command Write-LogMessage -ErrorAction SilentlyContinue) {
        Write-LogMessage $Message -Level $Level
    } else {
        Write-Host "[$Level] $Message"
    }
}

$edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
if (-not (Test-Path $edge)) {
    $edge = Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'
}
if (-not (Test-Path $edge)) {
    throw "Microsoft Edge not found for headless screenshots."
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

# C# web apps from all-projects.json (exclude PowerShell, libraries, non-hosts)
$targets = @(
    @{
        Key            = 'AiDoc.WebNew'
        Project        = 'C:\opt\src\AiDoc.WebNew\AiDoc.WebNew.csproj'
        Port           = 18484
        # Omit /health here: headless Edge can hang on some health-check responses.
        UrlPaths       = @('/AiDocNew/scalar/v1', '/AiDocNew/')
    }
    @{
        Key            = 'CursorDb2McpServer'
        Project        = 'C:\opt\src\CursorDb2McpServer\CursorDb2McpServer\CursorDb2McpServer.csproj'
        Port           = 15200
        UrlPaths       = @('/')
    }
    @{
        Key            = 'AutoDocJson'
        Project        = 'C:\opt\src\AutoDocJson\AutoDocJson.Web\AutoDocJson.Web.csproj'
        Port           = 15280
        UrlPaths       = @('/health', '/', '/docs/')
    }
    @{
        Key            = 'SystemAnalyzer'
        Project        = 'C:\opt\src\SystemAnalyzer\src\SystemAnalyzer.Web\SystemAnalyzer.Web.csproj'
        Port           = 15042
        UrlPaths       = @('/scalar/v1', '/')
    }
    @{
        Key            = 'ServerMonitor'
        Project        = 'C:\opt\src\ServerMonitor\ServerMonitorDashboard\src\ServerMonitorDashboard\ServerMonitorDashboard.csproj'
        Port           = 18998
        UrlPaths       = @('/', '/health')
    }
    @{
        Key            = 'GenericLogHandler'
        Project        = 'C:\opt\src\GenericLogHandler\src\GenericLogHandler.WebApi\GenericLogHandler.WebApi.csproj'
        Port           = 18110
        UrlPaths       = @('/scalar/v1', '/health')
    }
    @{
        Key            = 'SqlMermaidErdTools-Web'
        Project        = 'C:\opt\src\SqlMermaidErdTools\srcWeb\ProductStore.csproj'
        Port           = 15288
        UrlPaths       = @('/', '/api/products')
    }
    @{
        Key            = 'SqlMermaidErdTools-REST'
        Project        = 'C:\opt\src\SqlMermaidErdTools\srcREST\SqlMermaidApi.csproj'
        Port           = 15001
        UrlPaths       = @('/swagger', '/health')
    }
    @{
        Key            = 'DedgeAuth'
        Project        = 'C:\opt\src\FkAuth\src\FkAuth.Api\FkAuth.Api.csproj'
        Port           = 18100
        UrlPaths       = @('/scalar/v1', '/health')
    }
)

if ($Apps.Count -gt 0) {
    $targets = $targets | Where-Object { $Apps -contains $_.Key }
}

function Wait-PortOpen {
    param([int]$Port, [int]$TimeoutSec = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Stop-ProcessesOnPort {
    param([int]$Port)
    $pids = @(
        Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique
    )
    foreach ($procId in $pids) {
        if ($procId -and $procId -gt 0) {
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-HeadlessScreenshot {
    param([string]$Url, [string]$OutFile, [int]$TimeoutSec = 60)
    $dir = Split-Path $OutFile -Parent
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
    # Edge may resolve screenshot path more reliably with forward slashes.
    $shotPath = ($OutFile -replace '\\', '/')
    $argList = @(
        '--headless=new',
        '--disable-gpu',
        '--window-size=1400,900',
        "--screenshot=$shotPath",
        $Url
    )
    # Run Edge in-process so -Wait covers the full headless session (parent process behavior varies by version).
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $edge
    $psi.ArgumentList.AddRange($argList)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        $p.Kill()
        return $false
    }
    Start-Sleep -Milliseconds 800
    return (Test-Path $OutFile)
}

$results = [System.Collections.Generic.List[object]]::new()

foreach ($t in $targets) {
    if (-not (Test-Path $t.Project)) {
        Write-CapLog "Skip $($t.Key): project not found: $($t.Project)" -Level WARN
        $results.Add([pscustomobject]@{ App = $t.Key; Status = 'SkipMissingProject' })
        continue
    }

    $port = $t.Port
    $base = "http://127.0.0.1:$port"
    $outDir = Join-Path $OutputRoot $t.Key
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    Stop-ProcessesOnPort -Port $port
    Start-Sleep -Milliseconds 400

    if (-not $SkipBuild) {
        Write-CapLog "dotnet build $($t.Key)..."
        dotnet build $t.Project -c Debug --nologo -v q 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-CapLog "Build failed: $($t.Key)" -Level WARN
            $results.Add([pscustomobject]@{ App = $t.Key; Status = 'BuildFailed' })
            continue
        }
    }

    $urlsArg = "http://127.0.0.1:$port"
    $logOut = Join-Path $outDir "dotnet-run.stdout.log"
    $logErr = Join-Path $outDir "dotnet-run.stderr.log"
    Write-CapLog "Starting $($t.Key) on $urlsArg ..."
    $proc = Start-Process -FilePath 'dotnet' -ArgumentList @(
        'run', '--no-launch-profile', '--project', $t.Project, '--urls', $urlsArg
    ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr `
        -Environment @{ 'ASPNETCORE_ENVIRONMENT' = 'Development' }

    try {
        if (-not (Wait-PortOpen -Port $port -TimeoutSec 120)) {
            Write-CapLog "Timeout waiting for port $port ($($t.Key))" -Level WARN
            $results.Add([pscustomobject]@{ App = $t.Key; Status = 'StartTimeout' })
            continue
        }

        Start-Sleep -Seconds 2

        $i = 0
        foreach ($path in $t.UrlPaths) {
            $i++
            $pathSafe = ($path -replace '[^\w\-]+', '_').Trim('_')
            if (-not $pathSafe) { $pathSafe = "root" }
            $fileName = "{0:D2}-{1}.png" -f $i, $pathSafe
            $fullUrl = "$base$path"
            $png = Join-Path $outDir $fileName
            $ok = Invoke-HeadlessScreenshot -Url $fullUrl -OutFile $png
            if ($ok) {
                Write-CapLog "Screenshot OK: $($t.Key) $fullUrl -> $fileName"
            } else {
                Write-CapLog "Screenshot failed: $($t.Key) $fullUrl" -Level WARN
            }
        }
        $results.Add([pscustomobject]@{ App = $t.Key; Status = 'OK' })
    }
    finally {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Stop-ProcessesOnPort -Port $port
        Start-Sleep -Milliseconds 500
    }
}

Write-CapLog "Done. Output: $OutputRoot"
$results | Format-Table -AutoSize
return $results
