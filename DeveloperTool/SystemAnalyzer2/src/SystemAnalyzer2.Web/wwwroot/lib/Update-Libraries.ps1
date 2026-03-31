#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Downloads bundled JavaScript libraries for SystemAnalyzer.
.DESCRIPTION
    Fetches GoJS, svg-pan-zoom, and Mermaid from jsdelivr CDN and saves
    them locally under wwwroot/lib/. Run this script when you need to
    update library versions. Self-hosting avoids Edge Tracking Prevention
    blocking cdn.jsdelivr.net.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$libDir = $PSScriptRoot

$libs = @(
    @{ Name = "go.js";               Url = "https://cdn.jsdelivr.net/npm/gojs@3/release/go.js" }
    @{ Name = "svg-pan-zoom.min.js"; Url = "https://cdn.jsdelivr.net/npm/svg-pan-zoom@3.6.1/dist/svg-pan-zoom.min.js" }
    @{ Name = "mermaid.min.js";      Url = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js" }
)

foreach ($lib in $libs) {
    $dest = Join-Path $libDir $lib.Name
    Write-Host "Downloading $($lib.Name)..."
    Invoke-WebRequest -Uri $lib.Url -OutFile $dest -UseBasicParsing
    $sizeKb = [math]::Round((Get-Item $dest).Length / 1KB, 1)
    Write-Host "  Saved: $($lib.Name) ($($sizeKb) KB)"
}

Write-Host "All libraries updated."
