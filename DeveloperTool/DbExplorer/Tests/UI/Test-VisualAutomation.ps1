param(
    [string]$ProfileName = "FKKTOTST"
)

# Add required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class MouseHelper {
        [DllImport("user32.dll")]
        public static extern bool SetCursorPos(int X, int Y);
        
        [DllImport("user32.dll")]
        public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
        
        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();
        
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
        
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        
        public const int MOUSEEVENTF_LEFTDOWN = 0x02;
        public const int MOUSEEVENTF_LEFTUP = 0x04;
        public const int SW_RESTORE = 9;
        
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }
        
        public static void LeftClick() {
            mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
            mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
        }
        
        public static void DoubleClick() {
            LeftClick();
            System.Threading.Thread.Sleep(50);
            LeftClick();
        }
    }
"@

function Take-Screenshot {
    param([string]$Name, [string]$Description)
    
    $dir = ".\Screenshots"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $path = Join-Path $dir "${timestamp}_${Name}.png"
    
    Write-Host "📸 $Description" -ForegroundColor Cyan
    
    try {
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
        Write-Host "   ✅ Saved: $path" -ForegroundColor Green
        return $path
    }
    catch {
        Write-Host "   ❌ Failed: $_" -ForegroundColor Red
        return $null
    }
}

function Analyze-Screenshot {
    param([string]$ImagePath)
    
    Write-Host "🔍 Analyzing screenshot: $ImagePath" -ForegroundColor Cyan
    
    try {
        $bitmap = [System.Drawing.Bitmap]::FromFile($ImagePath)
        
        # Sample some pixels to understand the screen state
        # This is a simple heuristic - in a real scenario, you'd use OCR or image recognition
        
        $width = $bitmap.Width
        $height = $bitmap.Height
        
        Write-Host "   📐 Screen size: ${width}x${height}" -ForegroundColor Gray
        
        # Check center of screen for dark background (welcome screen)
        $centerPixel = $bitmap.GetPixel($width / 2, $height / 2)
        $isDark = ($centerPixel.R -lt 50 -and $centerPixel.G -lt 50 -and $centerPixel.B -lt 50)
        
        $bitmap.Dispose()
        
        $state = @{
            Width = $width
            Height = $height
            IsDarkTheme = $isDark
            CenterColor = "$($centerPixel.R),$($centerPixel.G),$($centerPixel.B)"
        }
        
        Write-Host "   🎨 Dark theme: $isDark | Center color: $($state.CenterColor)" -ForegroundColor Gray
        
        return $state
    }
    catch {
        Write-Host "   ❌ Analysis failed: $_" -ForegroundColor Red
        return $null
    }
}

function Click-AtPosition {
    param(
        [int]$X,
        [int]$Y,
        [bool]$DoubleClick = $false
    )
    
    Write-Host "🖱️  Clicking at position ($X, $Y)..." -ForegroundColor Cyan
    
    try {
        # Move cursor to position
        [MouseHelper]::SetCursorPos($X, $Y)
        Start-Sleep -Milliseconds 200
        
        # Click
        if ($DoubleClick) {
            Write-Host "   🖱️  Double-clicking..." -ForegroundColor Gray
            [MouseHelper]::DoubleClick()
        }
        else {
            [MouseHelper]::LeftClick()
        }
        
        Start-Sleep -Milliseconds 500
        Write-Host "   ✅ Click completed" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "   ❌ Click failed: $_" -ForegroundColor Red
        return $false
    }
}

function Get-AppWindow {
    $process = Get-Process -Name "DbExplorer" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($process) {
        return $process.MainWindowHandle
    }
    return [IntPtr]::Zero
}

function Bring-AppToFront {
    $hwnd = Get-AppWindow
    if ($hwnd -ne [IntPtr]::Zero) {
        [MouseHelper]::ShowWindow($hwnd, [MouseHelper]::SW_RESTORE) | Out-Null
        Start-Sleep -Milliseconds 200
        [MouseHelper]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 500
        
        # Get window position
        $rect = New-Object MouseHelper+RECT
        if ([MouseHelper]::GetWindowRect($hwnd, [ref]$rect)) {
            Write-Host "   📏 Window position: ($($rect.Left), $($rect.Top)) to ($($rect.Right), $($rect.Bottom))" -ForegroundColor Gray
            Write-Host "   📏 Window size: $($rect.Right - $rect.Left) x $($rect.Bottom - $rect.Top)" -ForegroundColor Gray
            
            return @{
                Left = $rect.Left
                Top = $rect.Top
                Right = $rect.Right
                Bottom = $rect.Bottom
                Width = $rect.Right - $rect.Left
                Height = $rect.Bottom - $rect.Top
            }
        }
    }
    return $null
}

Write-Host "🚀 Visual Automation - FKKTOTST Connection Test" -ForegroundColor Yellow
Write-Host "=" * 70 -ForegroundColor Yellow
Write-Host ""

# Clean up
Write-Host "🧹 Cleaning up..." -ForegroundColor Cyan
taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
Start-Sleep -Seconds 1

# Build
Write-Host "🔨 Building..." -ForegroundColor Cyan
dotnet build --verbosity quiet 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Build successful" -ForegroundColor Green
Write-Host ""

# Start app
Write-Host "🎯 Starting application..." -ForegroundColor Cyan
$exePath = ".\bin\Debug\net10.0-windows\DbExplorer.exe"
Start-Process $exePath
Start-Sleep -Seconds 3

# Take initial screenshot
$screenshot1 = Take-Screenshot "01_startup" "Application started"
Start-Sleep -Seconds 1

# Analyze the screenshot
$state1 = Analyze-Screenshot $screenshot1

# Bring app to front and get window position
$windowInfo = Bring-AppToFront

if ($windowInfo) {
    Write-Host "   ✅ Window brought to front" -ForegroundColor Green
    
    Take-Screenshot "02_window_focused" "Window focused and ready"
    Start-Sleep -Seconds 1
    
    # Based on the screenshots we saw earlier, FKKTOTST appears at approximately:
    # - Centered horizontally in the "Recent Connections" panel
    # - In the middle/upper part of the screen (around 50-60% from top)
    
    # Calculate approximate position of FKKTOTST in the Recent Connections list
    # The window is maximized, so we use screen center as reference
    $screenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
    $screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
    
    Write-Host "🎯 Screen resolution: ${screenWidth}x${screenHeight}" -ForegroundColor Cyan
    
    # Recent Connections panel is centered at approximately:
    # - X: 50% of screen width
    # - Y: 55% of screen height (first item)
    $fkktotst_X = [int]($screenWidth * 0.50)
    $fkktotst_Y = [int]($screenHeight * 0.50)  # Adjusted based on the screenshots
    
    Write-Host "🎯 Calculated FKKTOTST position: ($fkktotst_X, $fkktotst_Y)" -ForegroundColor Cyan
    Write-Host "   💡 This is based on the screenshots showing FKKTOTST centered in the panel" -ForegroundColor Gray
    Write-Host ""
    
    # Move mouse to position (so we can see it in screenshot)
    Write-Host "🖱️  Moving cursor to FKKTOTST position..." -ForegroundColor Cyan
    [MouseHelper]::SetCursorPos($fkktotst_X, $fkktotst_Y)
    Start-Sleep -Milliseconds 500
    
    Take-Screenshot "03_cursor_positioned" "Cursor positioned over FKKTOTST"
    Start-Sleep -Seconds 1
    
    # Double-click on FKKTOTST
    Write-Host "🖱️  Double-clicking on FKKTOTST..." -ForegroundColor Cyan
    Click-AtPosition -X $fkktotst_X -Y $fkktotst_Y -DoubleClick $true
    
    Write-Host "⏳ Waiting for connection dialog or result..." -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    
    Take-Screenshot "04_after_doubleclick" "After double-clicking FKKTOTST"
    Start-Sleep -Seconds 2
    
    Take-Screenshot "05_connection_result" "Connection result"
    Start-Sleep -Seconds 1
    
    # Try different Y positions if first attempt didn't work
    Write-Host "🔄 Trying alternative positions..." -ForegroundColor Yellow
    
    $alternativePositions = @(
        @{ X = [int]($screenWidth * 0.50); Y = [int]($screenHeight * 0.45) }
        @{ X = [int]($screenWidth * 0.50); Y = [int]($screenHeight * 0.55) }
        @{ X = [int]($screenWidth * 0.45); Y = [int]($screenHeight * 0.50) }
        @{ X = [int]($screenWidth * 0.55); Y = [int]($screenHeight * 0.50) }
    )
    
    $attemptNum = 6
    foreach ($pos in $alternativePositions) {
        Write-Host "🖱️  Trying position ($($pos.X), $($pos.Y))..." -ForegroundColor Cyan
        
        [MouseHelper]::SetCursorPos($pos.X, $pos.Y)
        Start-Sleep -Milliseconds 500
        
        Take-Screenshot "${attemptNum}_cursor_alt_position" "Cursor at alternative position"
        $attemptNum++
        
        [MouseHelper]::DoubleClick()
        Start-Sleep -Seconds 2
        
        Take-Screenshot "${attemptNum}_after_alt_click" "After clicking alternative position"
        $attemptNum++
    }
    
    Take-Screenshot "99_final_state" "Final application state"
}
else {
    Write-Host "   ❌ Could not find window" -ForegroundColor Red
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Yellow
Write-Host "✅ Visual automation complete!" -ForegroundColor Green
Write-Host "📁 Screenshots saved in: .\Screenshots\" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 Review the screenshots to see where the cursor was positioned" -ForegroundColor Yellow
Write-Host "💡 The application is still running for manual verification" -ForegroundColor Yellow
Write-Host ""
Write-Host "📋 Latest screenshots:" -ForegroundColor Cyan
Get-ChildItem ".\Screenshots\*.png" | Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object {
    Write-Host "   - $($_.Name)" -ForegroundColor Gray
}

