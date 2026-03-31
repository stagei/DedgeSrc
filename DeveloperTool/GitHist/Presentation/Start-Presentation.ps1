<#
.SYNOPSIS
    Starts a local HTTP server to host the Git History Presentation.

.DESCRIPTION
    Uses System.Net.HttpListener to serve static files from the Presentation folder.
    Opens the default browser automatically.

.PARAMETER Port
    TCP port to listen on. Default: 8099.

.PARAMETER NoBrowser
    Suppress automatic browser launch.
#>

param(
    [int]$Port = 8099,
    [switch]$NoBrowser
)

Import-Module GlobalFunctions -Force

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$rootPath = $PSScriptRoot
$prefix = "http://localhost:$($Port)/"

Write-LogMessage "[$($scriptName)] Starting HTTP server at $($prefix)" -Level INFO

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-LogMessage "[$($scriptName)] Failed to start listener: $($_.Exception.Message)" -Level ERROR
    exit 1
}

Write-LogMessage "[$($scriptName)] Serving files from $($rootPath)" -Level INFO

if (-not $NoBrowser) {
    Start-Process $prefix
}

$mimeTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.htm'  = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.gif'  = 'image/gif'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
    '.woff' = 'font/woff'
    '.woff2'= 'font/woff2'
}

Write-Host "`nPress Ctrl+C to stop the server.`n" -ForegroundColor Yellow

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $localPath = $request.Url.LocalPath.TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($localPath) -or $localPath -eq '/') {
            $localPath = 'index.html'
        }

        $filePath = Join-Path $rootPath $localPath.Replace('/', '\')

        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            $response.StatusCode = 404
            $errorBytes = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
            $response.ContentType = 'text/plain'
            $response.ContentLength64 = $errorBytes.Length
            $response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
            $response.Close()
            Write-LogMessage "[$($scriptName)] 404 $($request.Url.LocalPath)" -Level WARN
            continue
        }

        $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
        $contentType = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { 'application/octet-stream' }

        $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
        $response.StatusCode = 200
        $response.ContentType = $contentType
        $response.ContentLength64 = $fileBytes.Length
        $response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
        $response.Close()

        Write-LogMessage "[$($scriptName)] 200 $($request.Url.LocalPath)" -Level DEBUG
    }
} finally {
    $listener.Stop()
    $listener.Close()
    Write-LogMessage "[$($scriptName)] Server stopped" -Level INFO
}
