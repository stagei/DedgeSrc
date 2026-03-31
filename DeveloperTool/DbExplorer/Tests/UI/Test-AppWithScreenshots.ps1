param(
    [string]$Profile = "FKKTOTST",
    [int]$DelaySeconds = 2
)

# Add .NET types for screenshots and window manipulation
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class WindowHelper {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
        
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();
        
        [DllImport("user32.dll")]
        public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
        
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        
        public const int SW_RESTORE = 9;
        public const int SW_SHOW = 5;
    }
"@

function Take-Screenshot {
    param(
        [string]$FileName,
        [string]$Description
    )
    
    $screenshotDir = ".\Screenshots"
    if (-not (Test-Path $screenshotDir)) {
        New-Item -ItemType Directory -Path $screenshotDir | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $fullPath = Join-Path $screenshotDir "${timestamp}_${FileName}.png"
    
    Write-Host "📸 Taking screenshot: $Description" -ForegroundColor Cyan
    
    try {
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $bitmap.Save($fullPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
        
        Write-Host "   ✅ Saved: $fullPath" -ForegroundColor Green
        return $fullPath
    }
    catch {
        Write-Host "   ❌ Failed to take screenshot: $_" -ForegroundColor Red
        return $null
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
        [WindowHelper]::ShowWindow($hwnd, [WindowHelper]::SW_RESTORE) | Out-Null
        [WindowHelper]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 500
        return $true
    }
    return $false
}

function Send-KeysToApp {
    param([string]$Keys)
    
    if (Bring-AppToFront) {
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait($Keys)
        Start-Sleep -Milliseconds 500
        return $true
    }
    return $false
}

# Main script
Write-Host "🚀 DbExplorer Screenshot Testing Tool" -ForegroundColor Yellow
Write-Host "=" * 60 -ForegroundColor Yellow
Write-Host ""

# Step 1: Clean up
Write-Host "🧹 Step 1: Cleaning up existing processes..." -ForegroundColor Cyan
taskkill /F /IM DbExplorer.exe 2>$null | Out-Null
Start-Sleep -Seconds 1

# Step 2: Build
Write-Host "🔨 Step 2: Building the project..." -ForegroundColor Cyan
$buildOutput = dotnet build --verbosity quiet 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    Write-Host $buildOutput
    exit 1
}
Write-Host "   ✅ Build successful" -ForegroundColor Green
Write-Host ""

# Step 3: Start the application
Write-Host "🎯 Step 3: Starting the application..." -ForegroundColor Cyan
$exePath = ".\bin\Debug\net10.0-windows\DbExplorer.exe"

if (-not (Test-Path $exePath)) {
    Write-Host "❌ Executable not found: $exePath" -ForegroundColor Red
    exit 1
}

Start-Process $exePath
Write-Host "   ✅ Application started" -ForegroundColor Green
Write-Host ""

# Wait for app to start
Write-Host "⏳ Waiting for application to initialize..." -ForegroundColor Cyan
Start-Sleep -Seconds 3

# Step 4: Take initial screenshot
Write-Host "📸 Step 4: Taking screenshots..." -ForegroundColor Yellow
Write-Host ""

Take-Screenshot "01_initial_startup" "Application startup - initial state"
Start-Sleep -Seconds $DelaySeconds

# Bring app to front
if (Bring-AppToFront) {
    Write-Host "   ✅ Application window found and brought to front" -ForegroundColor Green
    Start-Sleep -Seconds 1
    
    # Take screenshot of main window
    Take-Screenshot "02_main_window" "Main application window"
    Start-Sleep -Seconds $DelaySeconds
    
    # Try to open connection dialog (Ctrl+N for new connection)
    Write-Host "🔧 Step 5: Attempting to open New Connection dialog (Ctrl+N)..." -ForegroundColor Cyan
    if (Send-KeysToApp "^n") {
        Start-Sleep -Seconds 1
        Take-Screenshot "03_new_connection_dialog" "New Connection dialog"
        Start-Sleep -Seconds $DelaySeconds
        
        # Try to interact with the dialog
        if ($Profile) {
            Write-Host "🔧 Step 6: Selecting profile: $Profile..." -ForegroundColor Cyan
            
            # Tab to profile dropdown and open it
            Send-KeysToApp "{TAB}" | Out-Null
            Start-Sleep -Milliseconds 300
            Take-Screenshot "04_after_tab" "After TAB navigation"
            Start-Sleep -Seconds $DelaySeconds
            
            # Open dropdown
            Send-KeysToApp "{DOWN}" | Out-Null
            Start-Sleep -Milliseconds 500
            Take-Screenshot "05_dropdown_opened" "Profile dropdown opened"
            Start-Sleep -Seconds $DelaySeconds
            
            # Type profile name
            Send-KeysToApp $Profile | Out-Null
            Start-Sleep -Milliseconds 500
            Take-Screenshot "06_profile_typed" "Profile name typed: $Profile"
            Start-Sleep -Seconds $DelaySeconds
            
            # Press Enter to select
            Send-KeysToApp "{ENTER}" | Out-Null
            Start-Sleep -Milliseconds 500
            Take-Screenshot "07_profile_selected" "Profile selected"
            Start-Sleep -Seconds $DelaySeconds
            
            # Press Enter again to connect
            Send-KeysToApp "{ENTER}" | Out-Null
            Start-Sleep -Seconds 2
            Take-Screenshot "08_after_connect_attempt" "After connection attempt"
            Start-Sleep -Seconds $DelaySeconds
        }
        
        # Close dialog with Escape
        Write-Host "🔧 Step 7: Closing dialog (ESC)..." -ForegroundColor Cyan
        Send-KeysToApp "{ESC}" | Out-Null
        Start-Sleep -Seconds 1
        Take-Screenshot "09_dialog_closed" "Dialog closed"
    }
    
    # Try menu navigation
    Write-Host "🔧 Step 8: Navigating menu (Alt+F)..." -ForegroundColor Cyan
    if (Send-KeysToApp "%f") {
        Start-Sleep -Milliseconds 500
        Take-Screenshot "10_file_menu" "File menu opened"
        Start-Sleep -Seconds $DelaySeconds
        
        Send-KeysToApp "{ESC}" | Out-Null
        Start-Sleep -Milliseconds 500
    }
    
    # Final screenshot
    Take-Screenshot "11_final_state" "Final application state"
    
} else {
    Write-Host "   ⚠️ Could not find application window" -ForegroundColor Yellow
    Take-Screenshot "02_no_window_found" "Application started but window not found"
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Yellow
Write-Host "✅ Screenshot testing complete!" -ForegroundColor Green
Write-Host "📁 Screenshots saved in: .\Screenshots\" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 The application is still running. Review the screenshots and then close it manually." -ForegroundColor Yellow
Write-Host ""

# List all screenshots taken
Write-Host "📋 Screenshots taken:" -ForegroundColor Cyan
Get-ChildItem ".\Screenshots\*.png" | Sort-Object LastWriteTime -Descending | Select-Object -First 15 | ForEach-Object {
    Write-Host "   - $($_.Name)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Press any key to close this window..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

