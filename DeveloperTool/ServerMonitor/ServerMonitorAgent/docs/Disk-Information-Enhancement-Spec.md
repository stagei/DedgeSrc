# Disk Information Enhancement Specification

## Overview

This specification describes the enhancement to add complete disk information including drive labels and used space to the global snapshot object, ensuring it's available in JSON exports, HTML exports, and REST API responses.

---

## Current State

### Existing DiskSpaceData Model

```csharp
public class DiskSpaceData
{
    public string Drive { get; init; } = string.Empty;        // "C:", "D:", etc.
    public double TotalGB { get; init; }                        // Total size in GB
    public double AvailableGB { get; init; }                   // Available free space in GB
    public double UsedPercent { get; init; }                    // Percentage used
    public string FileSystem { get; init; } = string.Empty;    // "NTFS", "FAT32", etc.
}
```

### Current Data Collection

The `DiskMonitor.CollectDiskSpaceData()` method already collects:
- ✅ Drive letter (e.g., "C:")
- ✅ Total size in GB
- ✅ Available free space in GB
- ✅ Used percentage
- ✅ File system type

### Current Issues

1. **❌ Not All Drives Detected**: The auto-detection filter excludes drives without volume labels:
   ```csharp
   !string.IsNullOrEmpty(d.VolumeLabel) && // Exclude uninitialized drives
   ```
   This is too restrictive - some valid drives may have empty volume labels.

2. **❌ Missing Volume Label**: Volume label is not collected (even though it's available)

3. **❌ Missing Used Space**: Used space in GB is not calculated (only percentage)

### What Needs to be Fixed

- ❌ **Remove VolumeLabel filter** - Include all ready fixed drives, regardless of volume label
- ❌ **Add Volume Label** to data model (e.g., "OS", "Data", "Backup", "New Volume")
- ❌ **Add Used Space in GB** - Calculate and include used space

---

## Requirements

### 1. Enhanced DiskSpaceData Model

**Add the following properties:**

```csharp
public class DiskSpaceData
{
    public string Drive { get; init; } = string.Empty;        // "C:", "D:", etc. (existing)
    public string? VolumeLabel { get; init; }                  // "OS", "Data", "Backup", etc. (NEW)
    public double TotalGB { get; init; }                      // Total size in GB (existing)
    public double UsedGB { get; init; }                        // Used space in GB (NEW)
    public double AvailableGB { get; init; }                   // Available free space in GB (existing)
    public double UsedPercent { get; init; }                   // Percentage used (existing)
    public string FileSystem { get; init; } = string.Empty;    // "NTFS", "FAT32", etc. (existing)
}
```

### 2. Data Collection Enhancement

**Update `DiskMonitor.CollectDiskSpaceData()` to include:**

1. **Volume Label**: Extract from `DriveInfo.VolumeLabel`
   - Handle null/empty labels gracefully
   - Use empty string or null if label is not available

2. **Used Space**: Calculate as `TotalGB - AvailableGB`
   - Ensure calculation is accurate
   - Handle edge cases (e.g., when TotalGB is 0)

### 3. Availability Requirements

The enhanced disk information must be available in:

- ✅ **Global Snapshot Object** (`SystemSnapshot.Disks.Space`)
- ✅ **JSON Export** (snapshot files)
- ✅ **HTML Export** (snapshot HTML files)
- ✅ **REST API** (`/api/Snapshot` endpoint)

---

## Implementation Details

### 1. Model Update

**File**: `src/ServerMonitor.Core/Models/SystemSnapshot.cs`

```csharp
public class DiskSpaceData
{
    /// <summary>
    /// Drive letter (e.g., "C:", "D:")
    /// </summary>
    public string Drive { get; init; } = string.Empty;
    
    /// <summary>
    /// Volume label/name (e.g., "OS", "Data", "Backup")
    /// May be null or empty if no label is set
    /// </summary>
    public string? VolumeLabel { get; init; }
    
    /// <summary>
    /// Total disk size in GB
    /// </summary>
    public double TotalGB { get; init; }
    
    /// <summary>
    /// Used disk space in GB
    /// </summary>
    public double UsedGB { get; init; }
    
    /// <summary>
    /// Available free space in GB
    /// </summary>
    public double AvailableGB { get; init; }
    
    /// <summary>
    /// Percentage of disk space used (0-100)
    /// </summary>
    public double UsedPercent { get; init; }
    
    /// <summary>
    /// File system type (e.g., "NTFS", "FAT32", "exFAT")
    /// </summary>
    public string FileSystem { get; init; } = string.Empty;
}
```

### 2. DiskMonitor Update

**File**: `src/ServerMonitor.Core/Monitors/DiskMonitor.cs`

**Update `CollectDiskSpaceData()` method:**

```csharp
private (List<DiskSpaceData> data, List<Alert> alerts) CollectDiskSpaceData(DiskSpaceMonitoringSettings settings)
{
    var data = new List<DiskSpaceData>();
    var alerts = new List<Alert>();

    try
    {
        // Get drives to monitor (existing logic)
        List<DriveInfo> drives;
        
        if (settings.DisksToMonitor == null || settings.DisksToMonitor.Count == 0)
        {
            // Auto-detect all local fixed drives
            // Remove VolumeLabel filter - it's too restrictive and excludes valid drives
            drives = DriveInfo.GetDrives()
                .Where(d => d.IsReady && 
                           d.DriveType == DriveType.Fixed && // Only fixed drives (hard drives)
                           d.TotalSize > 0) // Ensure drive has space (excludes uninitialized drives)
                .ToList();
        }
        else
        {
            drives = DriveInfo.GetDrives()
                .Where(d => d.IsReady && 
                           settings.DisksToMonitor.Contains(d.Name.TrimEnd('\\')))
                .ToList();
        }

        foreach (var drive in drives)
        {
            var totalGB = (double)drive.TotalSize / 1024 / 1024 / 1024;
            var availableGB = (double)drive.AvailableFreeSpace / 1024 / 1024 / 1024;
            var usedGB = totalGB - availableGB; // NEW: Calculate used space
            var usedPercent = (usedGB / totalGB) * 100;
            
            // Get volume label (NEW)
            var volumeLabel = string.IsNullOrWhiteSpace(drive.VolumeLabel) 
                ? null 
                : drive.VolumeLabel.Trim();

            data.Add(new DiskSpaceData
            {
                Drive = drive.Name.TrimEnd('\\'),
                VolumeLabel = volumeLabel,  // NEW
                TotalGB = totalGB,
                UsedGB = usedGB,            // NEW
                AvailableGB = availableGB,
                UsedPercent = usedPercent,
                FileSystem = drive.DriveFormat
            });

            // Alert logic remains the same...
        }
    }
    catch (Exception ex)
    {
        _logger.LogWarning(ex, "Failed to collect disk space data");
    }

    return (data, alerts);
}
```

### 3. JSON Serialization

**No changes required** - JSON serialization will automatically include new properties:
- `volumeLabel` (camelCase)
- `usedGB` (camelCase)

**Example JSON output:**
```json
{
  "disks": {
    "space": [
      {
        "drive": "C:",
        "volumeLabel": "OS",
        "totalGB": 126.51,
        "usedGB": 42.45,
        "availableGB": 84.06,
        "usedPercent": 33.56,
        "fileSystem": "NTFS"
      },
      {
        "drive": "D:",
        "volumeLabel": "Data",
        "totalGB": 500.0,
        "usedGB": 250.0,
        "availableGB": 250.0,
        "usedPercent": 50.0,
        "fileSystem": "NTFS"
      }
    ]
  }
}
```

### 4. HTML Export Update

**File**: `src/ServerMonitor.Core/Services/SnapshotHtmlExporter.cs`

**Update disk rendering to include new fields:**

```csharp
private void RenderDiskContent(StringBuilder sb, DiskData disk)
{
    if (disk?.Space == null || disk.Space.Count == 0)
    {
        sb.AppendLine("<p>No disk space data available.</p>");
        return;
    }

    sb.AppendLine("<h2>Disk Space</h2>");
    sb.AppendLine("<table class='properties-table'>");
    sb.AppendLine("<thead>");
    sb.AppendLine("<tr>");
    sb.AppendLine("<th>Drive</th>");
    sb.AppendLine("<th>Label</th>");
    sb.AppendLine("<th>File System</th>");
    sb.AppendLine("<th>Total Size</th>");
    sb.AppendLine("<th>Used</th>");
    sb.AppendLine("<th>Available</th>");
    sb.AppendLine("<th>Used %</th>");
    sb.AppendLine("</tr>");
    sb.AppendLine("</thead>");
    sb.AppendLine("<tbody>");

    foreach (var diskSpace in disk.Space)
    {
        var usedColor = diskSpace.UsedPercent >= 90 ? "red" : 
                        diskSpace.UsedPercent >= 75 ? "orange" : "green";
        
        sb.AppendLine("<tr>");
        sb.AppendLine($"<td><strong>{HtmlEncode(diskSpace.Drive)}</strong></td>");
        sb.AppendLine($"<td>{HtmlEncode(diskSpace.VolumeLabel ?? "—")}</td>");
        sb.AppendLine($"<td>{HtmlEncode(diskSpace.FileSystem)}</td>");
        sb.AppendLine($"<td>{diskSpace.TotalGB:F2} GB</td>");
        sb.AppendLine($"<td>{diskSpace.UsedGB:F2} GB</td>");
        sb.AppendLine($"<td>{diskSpace.AvailableGB:F2} GB</td>");
        sb.AppendLine($"<td style='color: {usedColor};'><strong>{diskSpace.UsedPercent:F1}%</strong></td>");
        sb.AppendLine("</tr>");
    }

    sb.AppendLine("</tbody>");
    sb.AppendLine("</table>");
}
```

### 5. REST API

**No changes required** - The REST API (`/api/Snapshot`) automatically returns the complete snapshot object, which includes the enhanced `DiskSpaceData`.

**Example REST API response:**
```json
{
  "disks": {
    "space": [
      {
        "drive": "C:",
        "volumeLabel": "OS",
        "totalGB": 126.51,
        "usedGB": 42.45,
        "availableGB": 84.06,
        "usedPercent": 33.56,
        "fileSystem": "NTFS"
      }
    ]
  }
}
```

---

## Data Flow

### Collection Flow

```
DiskMonitor.CollectAsync()
  ↓
CollectDiskSpaceData()
  ↓
DriveInfo.GetDrives() → Extract:
  - Drive letter (Name)
  - Volume label (VolumeLabel) ← NEW
  - Total size (TotalSize)
  - Available space (AvailableFreeSpace)
  - Used space (calculated) ← NEW
  - File system (DriveFormat)
  ↓
Create DiskSpaceData objects
  ↓
Return in DiskData.Space list
  ↓
UpdateGlobalSnapshot() → GlobalSnapshotService.UpdateDisk()
  ↓
Stored in SystemSnapshot.Disks.Space
```

### Export Flow

```
SystemSnapshot.Disks.Space
  ↓
JSON Export → SnapshotExporter.ExportAsync()
  ↓
JsonSerializer.Serialize() → Includes all properties
  ↓
Written to JSON file

SystemSnapshot.Disks.Space
  ↓
HTML Export → SnapshotHtmlExporter.ExportAsync()
  ↓
RenderDiskContent() → Renders table with all fields
  ↓
Written to HTML file

SystemSnapshot.Disks.Space
  ↓
REST API → SnapshotController.GetCurrentSnapshot()
  ↓
GlobalSnapshotService.GetCurrentSnapshot()
  ↓
Returns SystemSnapshot with all properties
  ↓
ASP.NET Core JSON serialization → Includes all properties
```

---

## Edge Cases and Error Handling

### 1. Volume Label Handling

**Scenario**: Drive has no volume label set
- **Behavior**: Set `VolumeLabel` to `null` or empty string
- **Display**: Show "—" or "No Label" in HTML/UI

**Code:**
```csharp
var volumeLabel = string.IsNullOrWhiteSpace(drive.VolumeLabel) 
    ? null 
    : drive.VolumeLabel.Trim();
```

### 2. Uninitialized Drives

**Scenario**: Drive exists but is not ready (e.g., uninitialized)
- **Current Behavior**: Filtered out by `d.IsReady` and `d.TotalSize > 0` checks
- **Fix**: Removed `!string.IsNullOrEmpty(d.VolumeLabel)` filter - this was excluding valid drives
- **New Behavior**: All ready fixed drives with `TotalSize > 0` are included, regardless of volume label

### 3. Calculation Edge Cases

**Scenario**: TotalGB is 0 (shouldn't happen, but handle gracefully)
- **Behavior**: 
  - UsedGB = 0
  - UsedPercent = 0
  - Log warning if TotalGB is 0

**Code:**
```csharp
var totalGB = (double)drive.TotalSize / 1024 / 1024 / 1024;
var availableGB = (double)drive.AvailableFreeSpace / 1024 / 1024 / 1024;
var usedGB = totalGB > 0 ? (totalGB - availableGB) : 0;
var usedPercent = totalGB > 0 ? (usedGB / totalGB) * 100 : 0;

if (totalGB == 0)
{
    _logger.LogWarning("Drive {Drive} has zero total size", drive.Name);
}
```

### 4. Access Denied

**Scenario**: Cannot access drive properties
- **Current Behavior**: Caught by try-catch, drive is skipped
- **No Change Required**: Already handled

---

## Testing Checklist

### Unit Tests

- [ ] Test `DiskSpaceData` model with all properties
- [ ] Test volume label extraction (with label, without label, empty string)
- [ ] Test used space calculation (TotalGB - AvailableGB)
- [ ] Test edge case: TotalGB = 0
- [ ] Test edge case: AvailableGB > TotalGB (shouldn't happen, but handle)

### Integration Tests

- [ ] Verify disk data appears in global snapshot
- [ ] Verify JSON export includes all fields
- [ ] Verify HTML export displays all fields correctly
- [ ] Verify REST API returns all fields
- [ ] Test with drives that have labels
- [ ] Test with drives that don't have labels
- [ ] Test with multiple drives (C:, D:, etc.)

### Manual Testing

- [ ] Check JSON snapshot file contains `volumeLabel` and `usedGB`
- [ ] Check HTML snapshot file displays label and used space
- [ ] Check REST API response includes new fields
- [ ] Verify calculations are correct (usedGB + availableGB = totalGB)
- [ ] Verify usedPercent matches (usedGB / totalGB * 100)

---

## Performance Impact

### Minimal Impact

- **Additional Data**: 2 properties per drive (VolumeLabel, UsedGB)
- **Collection Time**: +0-1ms per drive (VolumeLabel is already read, UsedGB is simple calculation)
- **Memory**: Negligible (+~50 bytes per drive)
- **Serialization**: No impact (JSON/HTML serialization already includes all properties)

### No Breaking Changes

- **Backward Compatibility**: Existing code that reads `DiskSpaceData` will continue to work
- **New Properties**: Optional/nullable, won't break existing consumers
- **JSON Schema**: New fields are additive, existing parsers will ignore unknown fields

---

## Example Output

### Before Enhancement

```json
{
  "disks": {
    "space": [
      {
        "drive": "C:",
        "totalGB": 126.51,
        "availableGB": 84.06,
        "usedPercent": 33.56,
        "fileSystem": "NTFS"
      }
    ]
  }
}
```

### After Enhancement

```json
{
  "disks": {
    "space": [
      {
        "drive": "C:",
        "volumeLabel": "OS",
        "totalGB": 126.51,
        "usedGB": 42.45,
        "availableGB": 84.06,
        "usedPercent": 33.56,
        "fileSystem": "NTFS"
      },
      {
        "drive": "D:",
        "volumeLabel": "Data",
        "totalGB": 500.0,
        "usedGB": 250.0,
        "availableGB": 250.0,
        "usedPercent": 50.0,
        "fileSystem": "NTFS"
      }
    ]
  }
}
```

### HTML Table Example

| Drive | Label | File System | Total Size | Used | Available | Used % |
|-------|-------|-------------|------------|------|-----------|--------|
| **C:** | OS | NTFS | 126.51 GB | 42.45 GB | 84.06 GB | **33.6%** |
| **D:** | Data | NTFS | 500.00 GB | 250.00 GB | 250.00 GB | **50.0%** |

---

## Implementation Steps

### Step 1: Update Model
1. Add `VolumeLabel` property to `DiskSpaceData`
2. Add `UsedGB` property to `DiskSpaceData`
3. Update XML documentation comments

### Step 2: Update DiskMonitor
1. Extract `VolumeLabel` from `DriveInfo.VolumeLabel`
2. Calculate `UsedGB` as `TotalGB - AvailableGB`
3. Update `DiskSpaceData` object creation
4. Add error handling for edge cases

### Step 3: Update HTML Exporter
1. Add "Label" column to disk space table
2. Add "Used" column to disk space table
3. Update table rendering logic
4. Handle null/empty volume labels gracefully

### Step 4: Testing
1. Unit tests for model and calculations
2. Integration tests for exports and API
3. Manual testing with real drives

### Step 5: Documentation
1. Update API documentation
2. Update configuration documentation (if needed)
3. Update example outputs in documentation

---

## Summary

This enhancement:
1. **Fixes Drive Detection** - Removes overly restrictive VolumeLabel filter to include ALL local fixed drives
2. **Adds Volume Label** - Human-readable drive name (e.g., "Windows", "Temporary Storage", "New Volume")
3. **Adds Used Space in GB** - Absolute used space (not just percentage)

All disk information will be:
- ✅ Available in the global snapshot object
- ✅ Included in JSON exports
- ✅ Displayed in HTML exports
- ✅ Returned by REST API

**Impact**: 
- **Fixes bug**: Now detects all local fixed drives (C:, D:, E:, F:, etc.)
- **Minimal performance impact**: No breaking changes, improves data completeness and usability

