[CmdletBinding()]
param(
    [Parameter()]
    [string]$SearchString
)

function Search-Registry {
    param(
        [string]$SearchString,
        [string]$Path
    )
    # Search through all values in current key
    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($key) {
            $key.Property | ForEach-Object {
                $value = $key.GetValue($_)
                if ($value -and $value.ToString() -like "*$SearchString*") {
                    return $Path
                }
            }
        }
    }
    catch { }

    # Recursively search through all subkeys
    try {
        $i = 0 # Initialize counter
        Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue | ForEach-Object {
            if ($i % 10000 -eq 0) {
                Write-Host "." -NoNewline
            }
            $i++
            Search-Registry -SearchString $SearchString -Path $_.PSPath
        }
    }
    catch { }
}

# If no search string provided, prompt user
if ( -not $SearchString) {
    $SearchString = Read-Host "Enter the text to search for in the registry"
}

# Define registry hives to search
$hives = @(
    "HKLM:\",
    "HKCU:\"
)

Write-Host "Searching registry for: $SearchString"
Write-Host "This may take a while..."

# Create temporary file to store paths
$tempFile = [System.IO.Path]::GetTempFileName()

# Search each hive and collect unique paths
$foundPaths = @()
Write-Host "Searching"

foreach ($hive in $hives) {
    $foundPaths += Search-Registry -SearchString $SearchString -Path $hive
}
$foundPaths = $foundPaths | Where-Object { $_ } | Select-Object -Unique

# If we found matches, export them
if ($foundPaths.Count -gt 0) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $exportFile = "RegistrySearch_$SearchString`_$timestamp.reg"

    Write-Host "Found $($foundPaths.Count) matching registry keys"
    Write-Host "Exporting to: $exportFile"

    # Export each found path
    foreach ($path in $foundPaths) {
        $regPath = $path -replace "Microsoft\.PowerShell\.Core\\Registry::", ""
        reg export $regPath $tempFile /y | Out-Null
        Get-Content $tempFile | Add-Content $exportFile
    }

    # Clean up temp file
    Remove-Item $tempFile -Force

    Write-Host "Export complete!"
} else {
    Write-Host "No matches found for: $SearchString"
}

