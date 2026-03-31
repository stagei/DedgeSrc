# ImageToIcon

## Description
PowerShell module that converts common image formats (PNG, BMP, GIF, JPG, WEBP) to Windows icons (.ico) with multiple standard sizes. The module creates high-quality icons suitable for Windows applications, containing all standard sizes in a single .ico file.

## Installation
```powershell
# If the module is not in your PSModulePath
Import-Module -Path "Path\To\ImageToIcon.psm1"

# If the module is in your PSModulePath
Import-Module ImageToIcon
```

## Functions

### ConvertTo-Icon
Converts an image file to a Windows icon (.ico) with multiple standard sizes.

#### Syntax
```powershell
ConvertTo-Icon [-InputPath] <String> [[-OutputPath] <String>] [[-Sizes] <Int32[]>] [<CommonParameters>]
```

#### Parameters
- **InputPath**: The path to the source image file (PNG, BMP, GIF, JPG, or WEBP)
- **OutputPath**: The path where the resulting .ico file will be saved. If not specified, the icon will be saved in the same directory as the input file with .ico extension
- **Sizes**: Array of icon sizes to include in the output. Defaults to standard Windows sizes: 16, 32, 48, 64, 96, 128, 256 pixels

#### Examples
```powershell
# Example 1: Basic usage
ConvertTo-Icon -InputPath "C:\Images\logo.png"

# Example 2: Specify output path
ConvertTo-Icon -InputPath "C:\Images\logo.jpg" -OutputPath "C:\Icons\app.ico"

# Example 3: Custom sizes
ConvertTo-Icon -InputPath "C:\Images\logo.png" -Sizes @(16, 32, 48)
```

### ConvertTo-IconBatch
Batch converts multiple image files to icons.

#### Syntax
```powershell
ConvertTo-IconBatch [-InputDirectory] <String> [[-OutputDirectory] <String>] [[-Filter] <String>] [[-Sizes] <Int32[]>] [<CommonParameters>]
```

#### Parameters
- **InputDirectory**: Directory containing image files to convert
- **OutputDirectory**: Directory where icon files will be saved. If not specified, icons are saved in the same directory as the source images
- **Filter**: File filter pattern. Defaults to common image extensions: "*.png;*.bmp;*.gif;*.jpg;*.jpeg;*.webp"
- **Sizes**: Array of icon sizes to include in the output. Defaults to standard Windows sizes

#### Examples
```powershell
# Example 1: Convert all images in a directory
ConvertTo-IconBatch -InputDirectory "C:\Images"

# Example 2: Specify output directory
ConvertTo-IconBatch -InputDirectory "C:\Images" -OutputDirectory "C:\Icons"

# Example 3: Filter by file type
ConvertTo-IconBatch -InputDirectory "C:\Images" -Filter "*.png"
```

## Features
- **Multiple Format Support**: Converts PNG, BMP, GIF, JPG, and WEBP images
- **Standard Windows Sizes**: Creates icons with all standard Windows sizes (16x16, 32x32, 48x48, 64x64, 96x96, 128x128, 256x256)
- **High Quality**: Uses high-quality bicubic interpolation for smooth scaling
- **Transparency Support**: Preserves transparency for PNG and WEBP images
- **Batch Processing**: Convert multiple images at once
- **Flexible Output**: Specify custom output paths and sizes

## Notes
- Requires System.Drawing assembly which is available in Windows PowerShell and PowerShell Core
- The function preserves transparency for PNG and WEBP images
- All generated icons contain multiple sizes in a single .ico file
- Images are automatically scaled to square dimensions while maintaining aspect ratio
- High-quality rendering ensures smooth scaling for all sizes
- WEBP support depends on the .NET runtime version and may require additional libraries on older systems

## Technical Details
- Uses .NET System.Drawing classes for image processing
- Implements proper ICO file format with directory entries
- Supports up to 256x256 pixel icons
- Memory-efficient processing with proper resource cleanup
- Error handling for unsupported formats and file system issues

## Related Links
- [Windows Icon Format Specification](https://docs.microsoft.com/en-us/windows/win32/uxguide/vis-icons)
- [System.Drawing.Image Documentation](https://docs.microsoft.com/en-us/dotnet/api/system.drawing.image) 