# Simple HTTP server for AutoDocJson output folder. Serves static files so index.html can load _json via AJAX.
# Usage: pwsh -File Serve-AutoDocJson.ps1 [-Port 8765]
param([int]$Port = 8765)

$OutputFolder = if ($env:OptPath) { Join-Path $env:OptPath 'Webs\AutoDocJson' } else { 'C:\opt\Webs\AutoDocJson' }
if (-not (Test-Path $OutputFolder)) {
    Write-Error "Output folder not found: $OutputFolder"
    exit 1
}

$MimeTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.htm'  = 'text/html; charset=utf-8'
    '.css'  = 'text/css'
    '.js'   = 'application/javascript'
    '.json' = 'application/json'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.gif'  = 'image/gif'
    '.woff' = 'font/woff'
    '.woff2'= 'font/woff2'
}
$DefaultMime = 'application/octet-stream'

$Prefix = "http://localhost:$Port/"
$Listener = New-Object System.Net.HttpListener
$Listener.Prefixes.Add($Prefix)
$Listener.Start()
Write-Host "Serving $OutputFolder at $Prefix (Ctrl+C to stop)"
try {
    while ($Listener.IsListening) {
        $Context = $Listener.GetContext()
        $Request = $Context.Request
        $Response = $Context.Response
        $LocalPath = $Request.Url.LocalPath.TrimStart('/').Replace('/', [IO.Path]::DirectorySeparatorChar)
        if ([string]::IsNullOrEmpty($LocalPath)) { $LocalPath = 'index.html' }
        $FilePath = Join-Path $OutputFolder $LocalPath
        if (-not [IO.Path]::GetFullPath($FilePath).StartsWith([IO.Path]::GetFullPath($OutputFolder), 'OrdinalIgnoreCase')) {
            $Response.StatusCode = 403
            $Response.Close()
            continue
        }
        if (-not (Test-Path $FilePath -PathType Leaf)) {
            $Response.StatusCode = 404
            $Response.Close()
            continue
        }
        $Ext = [IO.Path]::GetExtension($FilePath).ToLowerInvariant()
        $ContentType = $MimeTypes[$Ext]
        if (-not $ContentType) { $ContentType = $DefaultMime }
        $Response.ContentType = $ContentType
        $Response.AddHeader('Cache-Control', 'no-cache')
        try {
            [byte[]]$Bytes = [IO.File]::ReadAllBytes($FilePath)
            $Response.ContentLength64 = $Bytes.Length
            $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
        } catch {
            $Response.StatusCode = 500
        }
        $Response.Close()
    }
} finally {
    $Listener.Stop()
}
