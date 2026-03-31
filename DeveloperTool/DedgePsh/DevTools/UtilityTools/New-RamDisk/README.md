# New-RamDisk & Remove-RamDisk

PowerShell scripts for managing RAM disks using ImDisk.

- **New-RamDisk.ps1**: Creates a RAM disk, automatically downloading and installing ImDisk if missing.
- **Remove-RamDisk.ps1**: Removes one or all RAM disks created by ImDisk.
- **Build-ImDiskFromSource.ps1**: Builds ImDisk from source for internal use.
- **Initialize-ImDiskSubprojects.ps1**: Sets up subprojects directory structure.

## Description

This PowerShell script creates a RAM disk with the specified size in GB. If ImDisk is not installed on the system, the script will automatically download and install it silently. The RAM disk is created as an NTFS formatted drive with the specified drive letter.

## Requirements

- **Windows 11** (or Windows 10)
- **Administrator privileges** (required for installing ImDisk and creating RAM disks)
- **Internet connection** (for downloading ImDisk if not installed)

## Usage

### Basic Usage

```powershell
# Create a 1 GB RAM disk on drive R: (default)
.\New-RamDisk.ps1

# Create a 2 GB RAM disk
.\New-RamDisk.ps1 -SizeGB 2

# Create a 4 GB RAM disk on drive T:
.\New-RamDisk.ps1 -SizeGB 4 -DriveLetter "T:"
```

### Advanced Usage

```powershell
# Remove existing RAM disk and create a new one
.\New-RamDisk.ps1 -SizeGB 2 -Force

# Create a large RAM disk (up to 128 GB)
.\New-RamDisk.ps1 -SizeGB 16 -DriveLetter "S:"
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SizeGB` | `int` | `1` | Size of the RAM disk in gigabytes (1-128 GB) |
| `-DriveLetter` | `string` | `"R:"` | Drive letter to assign to the RAM disk (format: "X:") |
| `-Force` | `switch` | `false` | Remove any existing RAM disk on the specified drive letter before creating a new one |

## Examples

### Example 1: Default RAM Disk
```powershell
.\New-RamDisk.ps1
```
Creates a 1 GB RAM disk on drive R:

### Example 2: Custom Size and Drive
```powershell
.\New-RamDisk.ps1 -SizeGB 4 -DriveLetter "T:"
```
Creates a 4 GB RAM disk on drive T:

### Example 3: Replace Existing RAM Disk
```powershell
.\New-RamDisk.ps1 -SizeGB 2 -DriveLetter "R:" -Force
```
Removes any existing RAM disk on R: and creates a new 2 GB RAM disk

## How It Works

1. **Administrator Check**: Verifies the script is running with administrator privileges
2. **Drive Letter Validation**: Checks if the specified drive letter is available
3. **ImDisk Installation**: If ImDisk is not installed:
   - **First**: Attempts to install via winget (if available) - *Note: ImDisk is currently not available in winget, but the script checks for future availability*
   - **Fallback**: Downloads the latest version from GitHub releases (preferred) or SourceForge
   - Installs it silently
   - Updates PATH environment variable
4. **RAM Disk Creation**: Creates an NTFS formatted RAM disk with the specified size
5. **Verification**: Confirms the RAM disk was created successfully

## Remove-RamDisk.ps1

The companion script `Remove-RamDisk.ps1` provides an easy way to remove RAM disks.

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-DriveLetter` | `string` | Drive letter of specific RAM disk to remove (format: "R:"). If not specified, removes all RAM disks. |
| `-Force` | `switch` | Remove RAM disks without prompting for confirmation |
| `-ListOnly` | `switch` | List all RAM disks without removing them |

### Usage Examples

```powershell
# List all RAM disks without removing
.\Remove-RamDisk.ps1 -ListOnly

# Remove a specific RAM disk (with confirmation)
.\Remove-RamDisk.ps1 -DriveLetter "R:"

# Remove all RAM disks (with confirmation)
.\Remove-RamDisk.ps1

# Remove all RAM disks without prompting
.\Remove-RamDisk.ps1 -Force
```

### Manual Removal

To remove a RAM disk manually using ImDisk command line:

```powershell
# Remove specific drive
imdisk -d -m R:

# List all ImDisk drives
imdisk -l
```

## Important Notes

- **Volatile Storage**: RAM disks are volatile - all data is lost when the computer is rebooted or the RAM disk is removed
- **Memory Usage**: The RAM disk uses physical RAM, so ensure you have enough available memory
- **Performance**: RAM disks provide extremely fast read/write speeds, ideal for temporary files, cache, or high-speed I/O operations
- **Size Limits**: Maximum size is 128 GB (limited by available RAM and script validation)

## Troubleshooting

### "Administrator privileges required"
Run PowerShell as Administrator:
1. Right-click PowerShell
2. Select "Run as Administrator"

### "Drive X: is already in use"
Use the `-Force` parameter to remove the existing drive:
```powershell
.\New-RamDisk.ps1 -SizeGB 2 -Force
```

### "ImDisk installation failed"
- Check internet connection
- Verify administrator privileges
- Check Windows Event Viewer for installation errors

### "Failed to create RAM disk"
- Ensure sufficient RAM is available
- Check if another process is using the drive letter
- Verify ImDisk is properly installed

## Building from Source

For internal use, you can build ImDisk from source instead of using pre-compiled binaries:

```powershell
# Build from source
.\Build-ImDiskFromSource.ps1

# Initialize subprojects structure
.\Initialize-ImDiskSubprojects.ps1
```

See **README-BuildFromSource.md** for detailed instructions.

## Author

Geir Helge Starholm, www.dEdge.no

## License

Part of the DedgePsh DevTools collection.
