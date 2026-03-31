#Requires -Version 7
<#
.SYNOPSIS
    Generates proper multi-resolution ICO files for ServerMonitor tray apps.

.DESCRIPTION
    The original dedge.ico had a single 256x240 (non-square) BMP image.
    Windows Shell cannot scale a non-square image and has no 16/32/48px fallbacks,
    so shortcuts and the taskbar show a blank generic icon.

    This script creates a standards-compliant ICO containing:
        16x16   PNG  (taskbar, small icon view)
        32x32   PNG  (normal desktop/Start Menu)
        48x48   PNG  (large icon view)
       256x256  PNG  (high-DPI / jumbo view, PNG-in-ICO, Vista+)

    Each frame: FK green (#006241) square, white "FK" sans-serif text centred.

    Output targets (same icon for both tray apps):
      ServerMonitorTrayIcon\src\ServerMonitorTrayIcon\dedge.ico
      ServerMonitorDashboard\src\ServerMonitorDashboard.Tray\dedge.ico

    Reference: C:\opt\src\DedgeRemoteConnect\docs\WiX-Icon-Pitfalls.md

.EXAMPLE
    pwsh.exe -NoProfile -File Generate-Icon.ps1
#>

Add-Type -AssemblyName System.Drawing

$fkGreen = [System.Drawing.Color]::FromArgb(0, 98, 65)
$white   = [System.Drawing.Color]::White

function New-IconFrame([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $g.Clear($fkGreen)

    $fontSize  = [Math]::Max(5, [int]($size * 0.42))
    $font      = New-Object System.Drawing.Font("Arial", $fontSize, [System.Drawing.FontStyle]::Bold)
    $brush     = New-Object System.Drawing.SolidBrush($white)
    $sf        = New-Object System.Drawing.StringFormat
    $sf.Alignment     = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect      = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
    $g.DrawString("FK", $font, $brush, $rect, $sf)

    $font.Dispose(); $brush.Dispose(); $sf.Dispose(); $g.Dispose()
    return $bmp
}

function Get-PngBytes([System.Drawing.Bitmap]$bmp) {
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $ms.Dispose()
    return $bytes
}

function Write-U16([System.IO.MemoryStream]$s, [int]$v) {
    $b = [BitConverter]::GetBytes([uint16]$v); $s.Write($b, 0, 2)
}
function Write-U32([System.IO.MemoryStream]$s, [int]$v) {
    $b = [BitConverter]::GetBytes([uint32]$v); $s.Write($b, 0, 4)
}

# ── Build ICO binary ──────────────────────────────────────────────────────────
# ICO format:
#   ICONDIR   (6 bytes):  reserved(2) + type=1(2) + imageCount(2)
#   ICONDIRENTRY (16 bytes each): w(1) h(1) colorCount(1) reserved(1)
#                                  planes(2) bitCount(2) bytesInRes(4) imageOffset(4)
#   Image data (PNG bytes for each frame)

$sizes      = @(16, 32, 48, 256)
$frameBytes = @()
foreach ($s in $sizes) {
    $bmp = New-IconFrame $s
    $frameBytes += ,( Get-PngBytes $bmp )
    $bmp.Dispose()
}

$count      = $sizes.Count
$headerSize = 6
$dirSize    = 16 * $count
$dataOffset = $headerSize + $dirSize

$ms = New-Object System.IO.MemoryStream

# ICONDIR header
Write-U16 $ms 0
Write-U16 $ms 1
Write-U16 $ms $count

# ICONDIRENTRY for each frame
$offset = $dataOffset
for ($i = 0; $i -lt $count; $i++) {
    $s   = $sizes[$i]
    $len = $frameBytes[$i].Length
    $ms.WriteByte($(if ($s -eq 256) { 0 } else { $s }))
    $ms.WriteByte($(if ($s -eq 256) { 0 } else { $s }))
    $ms.WriteByte(0)
    $ms.WriteByte(0)
    Write-U16 $ms 1
    Write-U16 $ms 32
    Write-U32 $ms $len
    Write-U32 $ms $offset
    $offset += $len
}

# Image data
foreach ($fb in $frameBytes) {
    $ms.Write($fb, 0, $fb.Length)
}

$icoBytes = $ms.ToArray()
$ms.Dispose()

# ── Write to both tray app locations ──────────────────────────────────────────
$targets = @(
    (Join-Path $PSScriptRoot "ServerMonitorTrayIcon\src\ServerMonitorTrayIcon\dedge.ico")
    (Join-Path $PSScriptRoot "ServerMonitorDashboard\src\ServerMonitorDashboard.Tray\dedge.ico")
)

foreach ($target in $targets) {
    $dir = Split-Path $target
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllBytes($target, $icoBytes)
    Write-Output "Written: $target  ($($icoBytes.Length) bytes)"
}

# ── Verify ────────────────────────────────────────────────────────────────────
Write-Output ""
Write-Output "Verification:"
foreach ($target in $targets) {
    $verify   = [System.IO.File]::ReadAllBytes($target)
    $imgCount = [BitConverter]::ToUInt16($verify, 4)
    Write-Output "  $([System.IO.Path]::GetFileName((Split-Path $target)))  ($imgCount images)"
    for ($i = 0; $i -lt $imgCount; $i++) {
        $off = 6 + ($i * 16)
        $ww  = $verify[$off];     if ($ww -eq 0) { $ww = 256 }
        $hh  = $verify[$off + 1]; if ($hh -eq 0) { $hh = 256 }
        $sz  = [BitConverter]::ToUInt32($verify, $off + 8)
        Write-Output "    [$($i)]: $($ww)x$($hh)  $($sz) bytes  PNG"
    }
}

Write-Output ""
Write-Output "Done. Both dedge.ico files are now standards-compliant."
