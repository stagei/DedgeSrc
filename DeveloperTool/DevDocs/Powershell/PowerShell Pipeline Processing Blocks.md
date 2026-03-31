# PowerShell Pipeline Processing Blocks

Understanding PowerShell's standard pipeline processing blocks: `begin`, `process`, and `end`.

## Basic Structure

```powershell
function Verb-Noun {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string]$Input
    )
    
    begin   { # Runs once at start }
    process { # Runs for each item }
    end     { # Runs once at end }
}
```

## How It Works

PowerShell functions with pipeline support use three distinct processing blocks:

1. **begin**: Runs ONCE before processing any items
   - Perfect for initialization
   - Setting up variables
   - Preparing resources

2. **process**: Runs ONCE FOR EACH pipeline item
   - Handles individual items
   - Core processing logic
   - Accumulates data

3. **end**: Runs ONCE after all items processed
   - Final calculations
   - Resource cleanup
   - Output generation

## Practical Example

```powershell
function Count-Items {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string]$Item
    )
    
    begin {
        $count = 0
        Write-Host "Starting count..."
    }
    
    process {
        $count++
        Write-Host "Processing item: $Item"
    }
    
    end {
        Write-Host "Final count: $count"
    }
}

# Usage:
"apple", "banana", "orange" | Count-Items

# Output:
# Starting count...
# Processing item: apple
# Processing item: banana
# Processing item: orange
# Final count: 3
```

## Common Use Cases

- Data collection and aggregation
- File processing
- Batch operations
- Report generation
- Resource management

## Important Notes

- All blocks are optional
- `begin` is perfect for one-time initialization
- `process` is essential for pipeline input
- `end` is ideal for final processing of collected data

## Pipeline Parameter Requirements

To enable pipeline input, add the ValueFromPipeline parameter attribute:

```powershell
param(
    [Parameter(ValueFromPipeline = $true)]
    $InputObject
)
