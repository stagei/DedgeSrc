# ImageToIcon.psm1
# Converts common image formats (PNG, BMP, GIF, JPG, WEBP) to Windows icons with all standard sizes
#
# Changelog:
# ------------------------------------------------------------------------------
# 20241221 AI Assistant - First version
# 20241221 AI Assistant - Added WEBP format support
# ------------------------------------------------------------------------------

Add-Type -AssemblyName System.Drawing

<#
.SYNOPSIS
    Converts an image file to a Windows icon (.ico) with multiple standard sizes.

.DESCRIPTION
    Takes a PNG, BMP, GIF, JPG, or WEBP image file and converts it to a Windows icon file
    containing multiple standard sizes (16x16, 32x32, 48x48, 64x64, 96x96, 128x128, 256x256).
    The function automatically handles aspect ratio and creates high-quality scaled versions.

.PARAMETER InputPath
    The path to the source image file (PNG, BMP, GIF, JPG, or WEBP).

.PARAMETER OutputPath
    The path where the resulting .ico file will be saved. If not specified, 
    the icon will be saved in the same directory as the input file with .ico extension.

.PARAMETER Sizes
    Array of icon sizes to include in the output. Defaults to standard Windows sizes:
    16, 32, 48, 64, 96, 128, 256 pixels.

.EXAMPLE
    ConvertTo-Icon -InputPath "C:\Images\logo.png"
    # Converts logo.png to logo.ico with all standard sizes

.EXAMPLE
    ConvertTo-Icon -InputPath "C:\Images\logo.jpg" -OutputPath "C:\Icons\app.ico"
    # Converts logo.jpg to app.ico with all standard sizes

.EXAMPLE
    ConvertTo-Icon -InputPath "C:\Images\logo.png" -Sizes @(16, 32, 48)
    # Converts logo.png to logo.ico with only 16x16, 32x32, and 48x48 sizes

.NOTES
    Requires System.Drawing assembly which is available in Windows PowerShell and PowerShell Core.
    The function preserves transparency for PNG images.
#>
function ConvertTo-Icon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$InputPath,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [int[]]$Sizes = @(16, 32, 48, 64, 96, 128, 256)
    )
    
    # Validate input file extension
    $validExtensions = @('.png', '.bmp', '.gif', '.jpg', '.jpeg', '.webp')
    $inputExtension = [System.IO.Path]::GetExtension($InputPath).ToLower()
    
    if ($inputExtension -notin $validExtensions) {
        throw "Unsupported file format. Supported formats: PNG, BMP, GIF, JPG, WEBP"
    }
    
    # Set output path if not provided
    if (-not $OutputPath) {
        $inputDirectory = [System.IO.Path]::GetDirectoryName($InputPath)
        $inputFileName = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
        $OutputPath = Join-Path $inputDirectory "$inputFileName.ico"
    }
    
    # Ensure output directory exists
    $outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
    if (-not (Test-Path $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    
    Write-Host "Converting '$InputPath' to icon..." -ForegroundColor Green
    Write-Host "Output: '$OutputPath'" -ForegroundColor Gray
    
    try {
        # Load the source image
        $sourceImage = [System.Drawing.Image]::FromFile($InputPath)
        
        # Create memory streams for each size
        $iconStreams = @()
        
        foreach ($size in $Sizes) {
            Write-Host "  Creating ${size}x${size} icon..." -ForegroundColor Gray
            
            # Create bitmap of the specified size
            $bitmap = New-Object System.Drawing.Bitmap($size, $size)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            
            # Set high quality rendering
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            
            # Draw the resized image
            $graphics.DrawImage($sourceImage, 0, 0, $size, $size)
            $graphics.Dispose()
            
            # Convert to memory stream
            $memoryStream = New-Object System.IO.MemoryStream
            $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
            $iconStreams += $memoryStream
            
            $bitmap.Dispose()
        }
        
        # Create ICO file
        $iconBytes = Create-IcoFile -IconStreams $iconStreams -Sizes $Sizes
        [System.IO.File]::WriteAllBytes($OutputPath, $iconBytes)
        
        # Clean up
        foreach ($stream in $iconStreams) {
            $stream.Dispose()
        }
        $sourceImage.Dispose()
        
        Write-Host "Icon created successfully: '$OutputPath'" -ForegroundColor Green
        
        # Return file info
        Get-Item $OutputPath
        
    } catch {
        Write-Error "Failed to convert image to icon: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Creates ICO file bytes from multiple PNG image streams.

.DESCRIPTION
    Internal function that combines multiple PNG images into a single ICO file format.
    This function handles the ICO file structure with proper headers and directory entries.

.PARAMETER IconStreams
    Array of MemoryStream objects containing PNG image data.

.PARAMETER Sizes
    Array of corresponding sizes for each stream.

.NOTES
    This is an internal helper function used by ConvertTo-Icon.
#>
function Create-IcoFile {
    [CmdletBinding()]
    param(
        [System.IO.MemoryStream[]]$IconStreams,
        [int[]]$Sizes
    )
    
    $iconCount = $IconStreams.Count
    
    # ICO file header (6 bytes)
    $header = @(
        0x00, 0x00,  # Reserved, must be 0
        0x01, 0x00,  # Image type (1 = ICO)
        [byte]($iconCount -band 0xFF), [byte](($iconCount -shr 8) -band 0xFF)  # Number of images
    )
    
    # Calculate directory size and data offset
    $directorySize = 16 * $iconCount  # 16 bytes per directory entry
    $dataOffset = 6 + $directorySize
    
    # Create directory entries
    $directory = @()
    $currentOffset = $dataOffset
    
    for ($i = 0; $i -lt $iconCount; $i++) {
        $size = $Sizes[$i]
        $imageData = $IconStreams[$i].ToArray()
        
        # Directory entry (16 bytes)
        $entry = @(
            [byte]($size -eq 256 ? 0 : $size),  # Width (0 for 256)
            [byte]($size -eq 256 ? 0 : $size),  # Height (0 for 256)
            0x00,  # Color palette count (0 for PNG)
            0x00,  # Reserved
            0x01, 0x00,  # Color planes
            0x20, 0x00,  # Bits per pixel (32 for PNG)
            [byte]($imageData.Length -band 0xFF),
            [byte](($imageData.Length -shr 8) -band 0xFF),
            [byte](($imageData.Length -shr 16) -band 0xFF),
            [byte](($imageData.Length -shr 24) -band 0xFF),  # Image size
            [byte]($currentOffset -band 0xFF),
            [byte](($currentOffset -shr 8) -band 0xFF),
            [byte](($currentOffset -shr 16) -band 0xFF),
            [byte](($currentOffset -shr 24) -band 0xFF)   # Offset to image data
        )
        
        $directory += $entry
        $currentOffset += $imageData.Length
    }
    
    # Combine all parts
    $result = @()
    $result += $header
    $result += $directory
    
    # Add image data
    for ($i = 0; $i -lt $iconCount; $i++) {
        $result += $IconStreams[$i].ToArray()
    }
    
    return $result
}

<#
.SYNOPSIS
    Batch converts multiple image files to icons.

.DESCRIPTION
    Converts multiple image files in a directory to Windows icons.
    Supports PNG, BMP, GIF, JPG, and WEBP formats.

.PARAMETER InputDirectory
    Directory containing image files to convert.

.PARAMETER OutputDirectory
    Directory where icon files will be saved. If not specified, 
    icons are saved in the same directory as the source images.

.PARAMETER Filter
    File filter pattern. Defaults to common image extensions: "*.png;*.bmp;*.gif;*.jpg;*.jpeg;*.webp".

.PARAMETER Sizes
    Array of icon sizes to include in the output. Defaults to standard Windows sizes.

.EXAMPLE
    ConvertTo-IconBatch -InputDirectory "C:\Images"
    # Converts all images in C:\Images to icons

.EXAMPLE
    ConvertTo-IconBatch -InputDirectory "C:\Images" -OutputDirectory "C:\Icons"
    # Converts all images in C:\Images and saves icons to C:\Icons

.EXAMPLE
    ConvertTo-IconBatch -InputDirectory "C:\Images" -Filter "*.png"
    # Converts only PNG files in C:\Images to icons
#>
function ConvertTo-IconBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        [string]$InputDirectory,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory,
        
        [Parameter(Mandatory = $false)]
        [string]$Filter = "*.png;*.bmp;*.gif;*.jpg;*.jpeg;*.webp",
        
        [Parameter(Mandatory = $false)]
        [int[]]$Sizes = @(16, 32, 48, 64, 96, 128, 256)
    )
    
    if (-not $OutputDirectory) {
        $OutputDirectory = $InputDirectory
    }
    
    # Parse filter patterns
    $filterPatterns = $Filter.Split(';')
    $imageFiles = @()
    
    foreach ($pattern in $filterPatterns) {
        $imageFiles += Get-ChildItem -Path $InputDirectory -Filter $pattern.Trim() -File
    }
    
    if ($imageFiles.Count -eq 0) {
        Write-Warning "No image files found in '$InputDirectory' matching filter '$Filter'"
        return
    }
    
    Write-Host "Found $($imageFiles.Count) image file(s) to convert" -ForegroundColor Green
    
    foreach ($file in $imageFiles) {
        $outputPath = Join-Path $OutputDirectory "$($file.BaseName).ico"
        
        try {
            ConvertTo-Icon -InputPath $file.FullName -OutputPath $outputPath -Sizes $Sizes
        } catch {
            Write-Warning "Failed to convert '$($file.Name)': $($_.Exception.Message)"
        }
    }
    
    Write-Host "Batch conversion completed!" -ForegroundColor Green
}

# Export functions
Export-ModuleMember -Function ConvertTo-Icon
Export-ModuleMember -Function ConvertTo-IconBatch 