function Get-SystemInfo {
    param(
        [string]$InfoType = "time"
    )

    switch ($InfoType) {
        "time" { return Get-Date -Format "HH:mm:ss" }
        "date" { return Get-Date -Format "yyyy-MM-dd" }
        "datetime" { return Get-Date -Format "yyyy-MM-dd HH:mm:ss" }
        "computer" { return $env:COMPUTERNAME }
        "user" { return $env:USERNAME }
        default { return "Unknown info type" }
    }
}

# Call the function and return the result
Get-SystemInfo -InfoType $args[0]

