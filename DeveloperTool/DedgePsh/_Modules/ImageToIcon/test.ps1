# Test script for ImageToIcon module
# This script demonstrates how to use the ImageToIcon module

# Import the module
Import-Module ImageToIcon.psm1 -Force

Write-Host "ImageToIcon Module Test Script" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

# Test 1: Check if we have any image files to work with
Write-Host "`nTest 1: Looking for test images..." -ForegroundColor Yellow

# Check if we have any image files in the current directory or common locations
$global:OverrideRootPath = "$env:OptPath"
Set-location $($global:OverrideRootPath ? $global:OverrideRootPath : $PSScriptRoot)
Write-Host "Current directory: $($global:OverrideRootPath ? $global:OverrideRootPath : $PSScriptRoot)" -ForegroundColor Gray
$currentDirectory = Get-Location
$testPaths = @(
    "$currentDirectory\*.png",
    "$currentDirectory\*.jpg",
    "$currentDirectory\*.bmp",
    "$currentDirectory\*.gif",
    "$currentDirectory\*.webp"
)

$testImages = @()
foreach ($path in $testPaths) {
    $testImages += Get-ChildItem -Path $path -ErrorAction SilentlyContinue
}

if ($testImages.Count -eq 0) {
    Write-Host "No test images found. Creating a simple test image..." -ForegroundColor Gray

    # Create a simple test image programmatically
    Add-Type -AssemblyName System.Drawing

    $testImagePath = "$currentDirectory\test-image.png"

    # Create a 100x100 bitmap with a colorful design
    $bitmap = New-Object System.Drawing.Bitmap(100, 100)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    # Fill background with blue
    $blueBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Blue)
    $graphics.FillRectangle($blueBrush, 0, 0, 100, 100)

    # Draw a yellow circle
    $yellowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Yellow)
    $graphics.FillEllipse($yellowBrush, 20, 20, 60, 60)

    # Draw "TEST" text
    $font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $graphics.DrawString("TEST", $font, $whiteBrush, 30, 40)

    # Save the image
    $bitmap.Save($testImagePath, [System.Drawing.Imaging.ImageFormat]::Png)

    # Clean up
    $graphics.Dispose()
    $bitmap.Dispose()
    $blueBrush.Dispose()
    $yellowBrush.Dispose()
    $whiteBrush.Dispose()
    $font.Dispose()

    Write-Host "Created test image: $testImagePath" -ForegroundColor Green
    $testImages = @(Get-Item $testImagePath)
}

# Test 2: Convert a single image
Write-Host "`nTest 2: Converting single image to icon..." -ForegroundColor Yellow

$firstImage = $testImages[0]
Write-Host "Converting: $($firstImage.Name)" -ForegroundColor Gray

try {
    $iconFile = ConvertTo-Icon -InputPath $firstImage.FullName
    Write-Host "Success! Created icon: $($iconFile.Name)" -ForegroundColor Green
    Write-Host "Icon file size: $([math]::Round($iconFile.Length / 1KB, 2)) KB" -ForegroundColor Gray
} catch {
    Write-Host "Error converting image: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Convert with custom sizes
Write-Host "`nTest 3: Converting with custom sizes..." -ForegroundColor Yellow

$customSizes = @(16, 32, 64)
$customOutput = "$currentDirectory\custom-sizes.ico"

try {
    $iconFile = ConvertTo-Icon -InputPath $firstImage.FullName -OutputPath $customOutput -Sizes $customSizes
    Write-Host "Success! Created custom icon: $($iconFile.Name)" -ForegroundColor Green
    Write-Host "Custom icon file size: $([math]::Round($iconFile.Length / 1KB, 2)) KB" -ForegroundColor Gray
} catch {
    Write-Host "Error converting with custom sizes: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Batch conversion (if we have multiple images)
if ($testImages.Count -gt 1) {
    Write-Host "`nTest 4: Batch conversion..." -ForegroundColor Yellow

    $batchOutputDir = "$currentDirectory\batch-output"

    try {
        ConvertTo-IconBatch -InputDirectory $currentDirectory -OutputDirectory $batchOutputDir -Filter "*.png;*.jpg;*.bmp;*.gif;*.webp"
        Write-Host "Success! Batch conversion completed." -ForegroundColor Green

        $batchIcons = Get-ChildItem -Path $batchOutputDir -Filter "*.ico" -ErrorAction SilentlyContinue
        if ($batchIcons) {
            Write-Host "Created $($batchIcons.Count) icon(s) in batch output directory:" -ForegroundColor Gray
            foreach ($icon in $batchIcons) {
                Write-Host "  - $($icon.Name)" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "Error in batch conversion: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "`nTest 4: Skipped (only one test image available)" -ForegroundColor Yellow
}

# Test 5: Display help
Write-Host "`nTest 5: Module help..." -ForegroundColor Yellow
Write-Host "Getting help for ConvertTo-Icon:" -ForegroundColor Gray
Get-Help ConvertTo-Icon -Examples

Write-Host "`nTest Summary:" -ForegroundColor Cyan
Write-Host "=============" -ForegroundColor Cyan
Write-Host "- Module loaded successfully" -ForegroundColor Green
Write-Host "- Functions available: ConvertTo-Icon, ConvertTo-IconBatch" -ForegroundColor Green
Write-Host "- Check the created .ico files in your file explorer" -ForegroundColor Green
Write-Host "- The icons contain multiple sizes suitable for Windows applications" -ForegroundColor Green

Write-Host "`nUsage Examples:" -ForegroundColor Cyan
Write-Host "===============" -ForegroundColor Cyan
Write-Host "ConvertTo-Icon -InputPath 'C:\Images\logo.png'" -ForegroundColor White
Write-Host "ConvertTo-Icon -InputPath 'image.jpg' -OutputPath 'app.ico'" -ForegroundColor White
Write-Host "ConvertTo-IconBatch -InputDirectory 'C:\Images' -OutputDirectory 'C:\Icons'" -ForegroundColor White

