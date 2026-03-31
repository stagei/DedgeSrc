<#
.SYNOPSIS
    Provides comprehensive array export functionality to multiple file formats.

.DESCRIPTION
    This module offers advanced array and data structure export capabilities to various file formats
    including CSV, JSON, XML, HTML, and text files. Features include custom formatting, encoding
    options, icon removal, and special character handling for clean data output.

.EXAMPLE
    Export-ArrayToCsvFile -Content $data -OutputPath "output.csv" -Delimiter ";"
    # Exports data to a semicolon-delimited CSV file

.EXAMPLE
    Export-ArrayToJsonFile -Content $data -OutputPath "output.json" -Pretty
    # Exports data to a formatted JSON file
#>

<#
.SYNOPSIS
    Gets property names from an array of objects.

.DESCRIPTION
    Extracts the property names from the first object in an array,
    which are used as column headers for export operations.

.PARAMETER Content
    The array of objects to extract property names from.

.EXAMPLE
    $properties = Get-PropertyNames -Content $dataArray
    # Returns the property names from the first object
#>
function Get-PropertyNames {
    param (
        [Parameter(Mandatory = $true)]
        [PSObject[]]$Content
    )
    return $Content[0].PSObject.Properties.Name
}

<#
.SYNOPSIS
    Generates formatted headers for export operations.

.DESCRIPTION
    Creates user-friendly headers by adding spaces before capital letters in property names.
    If no custom headers are provided, automatically generates them from the object properties.

.PARAMETER Content
    The array of objects to generate headers for.

.PARAMETER Headers
    Optional custom headers to use instead of auto-generated ones.

.EXAMPLE
    $headers = Get-Headers -Content $dataArray
    # Returns formatted headers like "First Name" instead of "FirstName"

.EXAMPLE
    $headers = Get-Headers -Content $dataArray -Headers @("Name", "Age")
    # Uses custom headers instead of auto-generated ones
#>
function Get-Headers {
    param (
        [Parameter(Mandatory = $true)]
        [PSObject[]]$Content,
        [Parameter(Mandatory = $false)]
        [PSObject[]]$Headers
    )
    if (-not $Headers -and $Content.Count -gt 0) {
        $Headers = $Content[0].PSObject.Properties.Name
        # Add spaces before capital letters except first letter
        $newHeaders = @()
        foreach ($name in $Headers) {
            # Only add spaces before capital letters, regardless of position
            # Convert string to char array for character-by-character processing
            $chars = $name.ToCharArray()
            $result = [System.Text.StringBuilder]::new()
            
            # Add first character without preceding space
            $result.Append($chars[0]) | Out-Null
            
            # Process remaining characters
            for ($i = 1; $i -lt $chars.Length; $i++) {
                # Add space only before uppercase letters A-Z
                if ([char]::IsUpper($chars[$i])) {
                    $result.Append(' ') | Out-Null
                }
                $result.Append($chars[$i]) | Out-Null
            }
            $name = $result.ToString()
            # Trim any leading space that was added
            $name = $name.Trim()
            $newHeaders += $name
        }
        $Headers = $newHeaders
    }
    return $Headers
}

# Add this helper function at the top of the file
<#
.SYNOPSIS
    Removes icon characters from strings.

.DESCRIPTION
    Removes special icon characters and emojis from strings to ensure clean output
    in various file formats.

.PARAMETER InputString
    The string to process and remove icons from.

.EXAMPLE
    $cleanString = Remove-Icons -InputString "Hello 👋 World 🌍"
    # Returns "Hello World"
#>
function Remove-Icons {
    param (
        [Parameter(Mandatory = $true)]
        [PSObject[]]$Content
    )

    $cleanContent = $Content | ForEach-Object {
        $obj = $_ | Select-Object *
        foreach ($prop in $obj.PSObject.Properties) {
            if ($prop.Value -is [string]) {
                # Remove emojis and other special characters
                $prop.Value = $prop.Value -replace '[✓✔️✅❌⚠️⛔️🚫]', ''
                # Clean up any double spaces that might result
                $prop.Value = $prop.Value -replace '\s+', ' '
                # Trim any resulting whitespace
                $prop.Value = $prop.Value.Trim()
            }
        }
        $obj
    }
    return $cleanContent
}

<#
.SYNOPSIS
    Removes illegal characters and regex patterns from content.

.DESCRIPTION
    Processes an array of objects to remove illegal characters and regex patterns
    that might cause issues in various export formats.

.PARAMETER Content
    The array of objects to process and clean.

.EXAMPLE
    $cleanContent = Remove-IllegalCharactersAndRegex -Content $dataArray
    # Returns cleaned content with illegal characters removed

.NOTES
    This function is currently a placeholder and returns the content unchanged.
    Implementation can be added as needed for specific character removal requirements.
#>
function Remove-IllegalCharactersAndRegex {
    param (
        [Parameter(Mandatory = $true)]
        [PSObject[]]$Content
    )
    
    # Placeholder: returns content unchanged
    # Implementation can be added for specific character removal requirements
    return $Content
}

<#
.SYNOPSIS
    Exports an array to a CSV file.

.DESCRIPTION
    Converts an array of objects to CSV format and saves it to a file.
    Supports custom formatting, headers, and file encoding options.

.PARAMETER Array
    The array of objects to export.

.PARAMETER FilePath
    The path where the CSV file should be saved.

.PARAMETER Encoding
    The encoding to use for the file. Defaults to UTF8.

.PARAMETER NoHeader
    If specified, excludes the header row from the CSV file.

.EXAMPLE
    $data = @(
        [PSCustomObject]@{ Name = "John"; Age = 30 },
        [PSCustomObject]@{ Name = "Jane"; Age = 25 }
    )
    Export-ArrayToCsvFile -Array $data -FilePath "users.csv"
    # Exports the array to a CSV file with headers
#>
function Export-ArrayToCsvFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$Content,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Headers,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$AutoOpen = $false,

        [Parameter(Mandatory = $false)]
        [string]$Delimiter = ";"
    )
    
    begin {
        # Get calling script name if OutputPath not specified
        if (-not $OutputPath) {
            $callStack = Get-PSCallStack
            $callingScript = $callStack[1].ScriptName
            if ($callingScript) {
                $OutputPath = [System.IO.Path]::ChangeExtension($callingScript, "csv")
            }
            else {
                $OutputPath = Join-Path $(Get-ScriptLogPath) "report.csv"
            }
        }

        # Initialize content collection
        $allContent = @()
    }

    process {
        # Collect all content
        $allContent += $Content
    }

    end {
        try {
            # Clean content before processing
            #$allContent = Remove-Icons $allContent
            #$allContent = Remove-IllegalCharactersAndRegex $allContent
            # $cleanContent = $allContent | ForEach-Object {
            #     $obj = $_ | Select-Object *
            #     foreach ($prop in $obj.PSObject.Properties) {
            #         $prop.Value = $prop.Value -replace '[^\w\s]', ''
            #     }
            #     $obj
            # }
            #$allContent = $cleanContent
            $propertyNames = Get-PropertyNames -Content $allContent
            # Create a custom object array with only the specified headers
            $csvContent = $allContent | ForEach-Object {
                $obj = $_
                $customObj = [ordered]@{}
                foreach ($property in $propertyNames) {
                    $value = $obj.PSObject.Properties | Where-Object { $_.Name -eq $property } | Select-Object -ExpandProperty Value
                    # Handle array values by joining with commas
                    if ($null -eq $value) {
                        $customObj[$property.ToTitleCase()] = ""
                    }
                    elseif ($value.GetType().IsArray -or $value -is [System.Collections.IList]) {
                        $customObj[$property.ToTitleCase()] = ($value | ForEach-Object { $_.ToString() }) -join ", "
                    }
                    else {
                        $customObj[$property.ToTitleCase()] = $value
                    }
                }
                [PSCustomObject]$customObj
            }

            # Export to CSV with specified delimiter
            $csvContent | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter

            Write-Verbose "CSV report generated at: $OutputPath"


            if ($AutoOpen) {
                Start-Process $OutputPath
            }
            # Return the path to the generated report
            return $OutputPath
        }
        catch {
            Write-LogMessage "Failed to generate CSV report" -Level ERROR -Exception $_
            return $null
        }
    }
}


<#
.SYNOPSIS
    Exports an array to an HTML file.

.DESCRIPTION
    Converts an array of objects to an HTML table and saves it to a file.
    Supports custom styling, sorting, and formatting options.

.PARAMETER Array
    The array of objects to export.

.PARAMETER FilePath
    The path where the HTML file should be saved.

.PARAMETER Title
    The title for the HTML document.

.PARAMETER SortColumn
    The column to sort the data by.

.PARAMETER Descending
    If specified, sorts the data in descending order.

.EXAMPLE
    $data = @(
        [PSCustomObject]@{ Name = "John"; Age = 30 },
        [PSCustomObject]@{ Name = "Jane"; Age = 25 }
    )
    Export-ArrayToHtmlFile -Array $data -FilePath "users.html" -Title "User List" -SortColumn "Age"
    # Exports the array to a styled HTML file sorted by age
#>
function Export-ArrayToHtmlFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$Content,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Headers,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [string]$Title = "Generated Report",
        
        [Parameter(Mandatory = $false)]
        [switch]$AutoOpen = $false,
        
        [Parameter(Mandatory = $false)]
        [int]$StatusColumnIndex = -9999,
        
        [Parameter(Mandatory = $false)]
        [bool]$AddToDevToolsWebPath = $true,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoTitleAutoFormat = $false,

        [Parameter(Mandatory = $false)]
        [string]$DevToolsWebDirectory = ""
    )
    
    begin {
        # Get calling script name if OutputPath not specified
        if ($null -eq $OutputPath) {
            $callStack = Get-PSCallStack
            $callingScript = $callStack[1].ScriptName
            if ($callingScript) {
                $OutputPath = [System.IO.Path]::ChangeExtension($callingScript, "html")
            }
            else {
                $OutputPath = Join-Path $(Get-ScriptLogPath) "report.html"
            }
        }

        # Get the output folder from $OutputPath
        $outputFolder = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
        }

        # Initialize content collection
        $allContent = @()
    }

    process {
        # Collect all content
        $allContent = $Content
    }

    end {
        try {
            # Clean content before processing
            $allContent = Remove-Icons $allContent

            $Headers = Get-Headers -Headers $Headers -Content $allContent
            $propertyNames = Get-PropertyNames -Content $allContent

            $htmlRows = @()
            $htmlRows += "<table>"
            $htmlRows += "<tr>"
            $htmlRows += $(($propertyNames | ForEach-Object { "<th>$($_.ToTitleCase())</th>" }) -join "`n                ")
            $htmlRows += "</tr>"

            foreach ($obj in $allContent) {
                # Check if we need to apply a row-level class based on StatusColumnIndex
                $rowClass = ""
                if ($StatusColumnIndex -ne -9999 -and $StatusColumnIndex -ge 0 -and $StatusColumnIndex -lt $propertyNames.Count) {
                    # Get the header name at the specified index
                    $statusColumnName = $propertyNames[$StatusColumnIndex]
                    # Get the value from the object using the header name
                    $statusValue = $obj.$statusColumnName
                    
                    if ($statusValue -match '(✅|Open|Success|OK|Valid|Yes)') {
                        $rowClass = ' class="success"'
                    }
                    elseif ($statusValue -match '(❌|Closed|Failed|Error|Invalid|Not OK|NO)') {
                        $rowClass = ' class="failure"'
                    }
                }
                
                $cells = @()
                $counter = 0
             
                foreach ($property in $propertyNames) {

                    # Access the corresponding value from $obj using the header name as the property
                    $value = $obj.$property
                    $cells += "<td>$value</td>"
                    $counter++
                }

                $htmlRows += "<tr$rowClass>" + ($cells -join "") + "</tr>"
            }
            $htmlRows += "</table>"

            $htmlContent = $htmlHeader + ($htmlRows -join "`n") + $htmlFooter
            $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8

            $relativePath = $null
            if ($OutputPath.ToLower().Contains((Get-DevToolsWebPath).ToLower())) {
                $temp = $OutputPath.Split($(Get-DevToolsWebPath))[-1]
                $relativePath = $($temp.Substring(0, $temp.LastIndexOf("\"))).TrimStart("\").TrimEnd("\")
            }

            if ([string]::IsNullOrEmpty($DevToolsWebDirectory)) {
                $DevToolsWebDirectory = $relativePath
            }
            $url = Save-HtmlOutput -Title $Title -Content $($htmlContent.ToString()) -OutputFile $OutputPath -AddToDevToolsWebPath $AddToDevToolsWebPath -DevToolsWebDirectory $DevToolsWebDirectory -AutoOpen $AutoOpen -NoTitleAutoFormat:$NoTitleAutoFormat
            return $url
        }
        catch {
            Write-LogMessage "Failed to generate HTML report" -Level ERROR -Exception $_
            return $null
        }
    }
}


<#
.SYNOPSIS
    Exports an array to a JSON file.

.DESCRIPTION
    Converts an array of objects to JSON format and saves it to a file.
    Supports custom depth and formatting options.

.PARAMETER Array
    The array of objects to export.

.PARAMETER FilePath
    The path where the JSON file should be saved.

.PARAMETER Depth
    The maximum depth of nested objects to include. Defaults to 10.

.EXAMPLE
    $data = @(
        @{ Name = "John"; Details = @{ Age = 30; City = "New York" } },
        @{ Name = "Jane"; Details = @{ Age = 25; City = "London" } }
    )
    Export-ArrayToJsonFile -Array $data -FilePath "users.json" -Depth 2
    # Exports the array to a JSON file with nested objects
#>
function Export-ArrayToJsonFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$Content,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [bool]$Pretty = $true,
        
        [Parameter(Mandatory = $false)]
        [switch]$OpenInNotepad = $false

    )
    
    begin {
        # Get calling script name if OutputPath not specified
        if (-not $OutputPath) {
            $callStack = Get-PSCallStack
            $callingScript = $callStack[1].ScriptName
            if ($callingScript) {
                $OutputPath = [System.IO.Path]::ChangeExtension($callingScript, "json")
            }
            else {
                $OutputPath = Join-Path $(Get-ScriptLogPath) "report.json"
            }
        }

        # Initialize content collection
        $allContent = @()
    }

    process {
        # Collect all content
        $allContent += $Content
    }

    end {
        try {
            # Clean content before processing
            $allContent = Remove-Icons $allContent

            # Create wrapper object with metadata
            $exportObject = @{
                Metadata = @{
                    GeneratedOn = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    ItemCount   = $allContent.Count
                }
                Data     = $allContent
            }

            # Convert to JSON with optional pretty printing
            $jsonContent = if ($Pretty) {
                $exportObject | ConvertTo-Json -Depth 10
            }
            else {
                $exportObject | ConvertTo-Json -Depth 10 -Compress
            }

            # Write to file
            $jsonContent | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Verbose "JSON report generated at: $OutputPath"

            if ($OpenInNotepad) {
                Start-Process notepad.exe -ArgumentList $OutputPath
            }

            # Return the path to the generated report
            return $OutputPath
        }
        catch {
            Write-LogMessage "Failed to generate JSON report" -Level ERROR -Exception $_
            return $null
        }
    }
}

<#
.SYNOPSIS
    Exports an array to a Markdown file.

.DESCRIPTION
    Converts an array of objects to a Markdown table format and saves it to a file.
    Supports custom formatting and table styling.

.PARAMETER Array
    The array of objects to export.

.PARAMETER FilePath
    The path where the Markdown file should be saved.

.PARAMETER Title
    The title for the Markdown document.

.EXAMPLE
    $data = @(
        [PSCustomObject]@{ Name = "John"; Age = 30 },
        [PSCustomObject]@{ Name = "Jane"; Age = 25 }
    )
    Export-ArrayToMarkdownFile -Array $data -FilePath "users.md" -Title "User List"
    # Exports the array to a Markdown file with a table
#>
function Export-ArrayToMarkdownFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$Content,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Headers,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [string]$Title = "Generated Report",

        [Parameter(Mandatory = $false)]
        [switch]$OpenInNotepad = $false
    )
    
    begin {
        # Get calling script name if OutputPath not specified
        if (-not $OutputPath) {
            $callStack = Get-PSCallStack
            $callingScript = $callStack[1].ScriptName
            if ($callingScript) {
                $OutputPath = [System.IO.Path]::ChangeExtension($callingScript, "md")
            }
            else {
                $OutputPath = Join-Path $(Get-ScriptLogPath) "report.md"
            }
        }

        # Initialize content collection
        $allContent = @()
    }

    process {
        # Collect all content
        $allContent += $Content
    }

    end {
        try {
            # Clean content before processing
            $allContent = Remove-Icons $allContent

            # If no headers specified, use property names from first object
            $Headers = Get-Headers -Headers $Headers -Content $allContent
            $propertyNames = Get-PropertyNames -Content $allContent
            # Determine column alignment
            $columnAlignment = @{}
            foreach ($property in $propertyNames) {
                # Check if the column contains only numeric values
                $hasNonNumeric = $false
                foreach ($item in $allContent) {
                    $value = $item.$property
                    if ($null -eq $value -or [string]::IsNullOrWhiteSpace($value)) {
                        continue
                    }
                    elseif ($value -is [System.Array]) {
                        $hasNonNumeric = $true
                        break
                    }
                    else {
                        $stringValue = $value.ToString().Trim()
                        if (-not [double]::TryParse($stringValue, [ref]$null)) {
                            $hasNonNumeric = $true
                            break
                        }
                    }
                }
                
                # Set alignment based on numeric check
                $columnAlignment[$property.ToTitleCase()] = if ($hasNonNumeric) { ":---" } else { "---:" }
            }

            # Create markdown content
            $lines = [System.Collections.ArrayList]::new()

            # Add title and timestamp
            $lines.Add("# $Title") | Out-Null
            $lines.Add("") | Out-Null
            $lines.Add("Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null
            $lines.Add("") | Out-Null

            # Create header line
            $headerLine = "| " + ($propertyNames | ForEach-Object { " $($_.ToTitleCase()) |" }) + " |"
            $lines.Add($headerLine) | Out-Null

            # Create separator line with alignment
            $separatorLine = "|" + ($propertyNames | ForEach-Object { " $($columnAlignment[$_]) |" })
            $lines.Add($separatorLine) | Out-Null

            # Add data rows
            foreach ($item in $allContent) {
                $cells = foreach ($property in $propertyNames) {
                    $value = $item.$property
                    if ($null -eq $value -or [string]::IsNullOrWhiteSpace($value)) {
                        ""
                    }
                    elseif ($value -is [System.Array]) {
                        ($value | ForEach-Object { $_.ToString() }) -join ", "
                    }
                    else {
                        $processedValue = $value.ToString() -replace '\|', '\|'
                        # Right-align numeric values if in a numeric column
                        if ($columnAlignment[$property.ToTitleCase()] -eq "---:") {
                            try {
                                [double]::Parse($processedValue) | Out-Null
                                $processedValue.PadLeft(($processedValue.Length))
                            }
                            catch {
                                $processedValue
                            }
                        }
                        else {
                            $processedValue
                        }
                    }
                }
                
                $rowContent = "| " + ($cells -join " | ") + " |"
                $lines.Add($rowContent) | Out-Null
            }

            # Add final newline
            $lines.Add("") | Out-Null

            # Write to file
            $lines | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Verbose "Markdown report generated at: $OutputPath"

            if ($OpenInNotepad) {
                Start-Process notepad.exe -ArgumentList $OutputPath
            }

            # Return the path to the generated report
            return $OutputPath
        }
        catch {
            Write-LogMessage "Failed to generate markdown report" -Level ERROR -Exception $_
            return $null
        }
    }
}

<#
.SYNOPSIS
    Exports an array to a text file.

.DESCRIPTION
    Converts an array of objects to a formatted text representation and saves it to a file.
    Supports custom formatting and layout options.

.PARAMETER Array
    The array of objects to export.

.PARAMETER FilePath
    The path where the text file should be saved.

.PARAMETER Title
    The title for the text document.

.EXAMPLE
    $data = @(
        [PSCustomObject]@{ Name = "John"; Age = 30 },
        [PSCustomObject]@{ Name = "Jane"; Age = 25 }
    )
    Export-ArrayToTxtFile -Array $data -FilePath "users.txt" -Title "User List"
    # Exports the array to a formatted text file
#>
function Export-ArrayToTxtFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$Content,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Headers,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [string]$Title = "Generated Report",

        [Parameter(Mandatory = $false)]
        [switch]$OpenInNotepad = $false
    )
    
    begin {
        # Get calling script name if OutputPath not specified
        if (-not $OutputPath) {
            $callStack = Get-PSCallStack
            $callingScript = $callStack[1].ScriptName
            if ($callingScript) {
                $OutputPath = [System.IO.Path]::ChangeExtension($callingScript, "txt")
            }
            else {
                $OutputPath = Join-Path $(Get-ScriptLogPath) "report.txt"
            }
        }

        # Initialize content collection
        $allContent = @()
    }

    process {
        # Collect all content
        $allContent += $Content
    }

    end {
        $allContent = Remove-Icons $allContent

        try {
            # If no headers specified, use property names from first object
            $propertyNames = Get-PropertyNames -Content $allContent
            # Calculate maximum width for each column
            $columnWidths = @{}
            foreach ($property in $propertyNames) {
                $maxWidth = $property.Length
                foreach ($item in $allContent) {
                    $value = $item.$property
                    if ($null -ne $value) {
                        $maxWidth = [Math]::Max($maxWidth, $value.ToString().Length)
                    }
                }
                $columnWidths[$property.ToTitleCase()] = $maxWidth
            }

            # Calculate total width for title centering
            $totalWidth = ($columnWidths.Values | Measure-Object -Sum).Sum + (3 * $propertyNames.Count) + 1

            # Create title line
            $titlePadding = [Math]::Max(0, [Math]::Floor(($totalWidth - $Title.Length) / 2))
            $titleLine = " " * $titlePadding + $Title

            # Create header line
            $headerLine = $propertyNames | ForEach-Object {
                $_.PadRight($columnWidths[$_])
            }
            $headerText = " | " + ($headerLine -join " | ") + " | "
            
            # Create separator line
            $separatorLine = $propertyNames | ForEach-Object {
                "-" * $columnWidths[$_]
            }
            $separatorText = "-|-" + ($separatorLine -join "-|-") + "-|"

            # Create content lines
            $contentLines = $allContent | ForEach-Object {
                $obj = $_
                $line = $propertyNames | ForEach-Object {
                    $value = $obj.$_
                    # Fixed: was incorrectly checking $null -ne $value
                    if ($null -eq $value) { $value = "" }
                    $value.ToString().PadRight($columnWidths[$_])
                }
                " | " + ($line -join " | ") + " | "
            }

            # Combine all parts
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $output = @(
                $titleLine
                "Generated on $timestamp"
                ""
                $headerText
                $separatorText
                $contentLines
            )

            # Write to file
            $output | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Verbose "Text report generated at: $OutputPath"

            if ($OpenInNotepad) {
                Start-Process notepad.exe -ArgumentList $OutputPath
            }

            # Return the path to the generated report
            return $OutputPath
        }
        catch {
            Write-LogMessage "Failed to generate text report" -Level ERROR -Exception $_
            return $null
        }
    }
}

<#
.SYNOPSIS
    Exports an array to an XML file.

.DESCRIPTION
    Converts an array of objects to XML format and saves it to a file.
    Supports custom root element names and formatting options.

.PARAMETER Array
    The array of objects to export.

.PARAMETER FilePath
    The path where the XML file should be saved.

.PARAMETER RootElementName
    The name of the root XML element. Defaults to "Objects".

.EXAMPLE
    $data = @(
        [PSCustomObject]@{ Name = "John"; Age = 30 },
        [PSCustomObject]@{ Name = "Jane"; Age = 25 }
    )
    Export-ArrayToXmlFile -Array $data -FilePath "users.xml" -RootElementName "Users"
    # Exports the array to an XML file with custom root element
#>
function Export-ArrayToXmlFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$Content,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$OpenInNotepad = $false,

        [Parameter(Mandatory = $false)]
        [string]$RootElementName = "Report",

        [Parameter(Mandatory = $false)]
        [string]$ItemElementName = "Item"
    )
    
    begin {
        # Get calling script name if OutputPath not specified
        if (-not $OutputPath) {
            $callStack = Get-PSCallStack
            $callingScript = $callStack[1].ScriptName
            if ($callingScript) {
                $OutputPath = [System.IO.Path]::ChangeExtension($callingScript, "xml")
            }
            else {
                $OutputPath = Join-Path $(Get-ScriptLogPath) "report.xml"
            }
        }

        # Initialize content collection
        $allContent = @()
    }

    process {
        # Collect all content
        $allContent += $Content
    }

    end {
        try {
            # Clean content before processing
            $allContent = Remove-Icons $allContent

            # Create XML document
            $xmlDoc = New-Object System.Xml.XmlDocument
            
            # Add declaration
            $declaration = $xmlDoc.CreateXmlDeclaration("1.0", "UTF-8", $null)
            $xmlDoc.AppendChild($declaration) | Out-Null

            # Create root element
            $root = $xmlDoc.CreateElement($RootElementName)
            $xmlDoc.AppendChild($root) | Out-Null

            # Add metadata
            $metadata = $xmlDoc.CreateElement("Metadata")
            $generatedOn = $xmlDoc.CreateElement("GeneratedOn")
            $generatedOn.InnerText = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $itemCount = $xmlDoc.CreateElement("ItemCount")
            $itemCount.InnerText = $allContent.Count
            $metadata.AppendChild($generatedOn) | Out-Null
            $metadata.AppendChild($itemCount) | Out-Null
            $root.AppendChild($metadata) | Out-Null

            # Create data section
            $dataSection = $xmlDoc.CreateElement("Data")
            $root.AppendChild($dataSection) | Out-Null

            # Add items
            foreach ($item in $allContent) {
                $itemElement = $xmlDoc.CreateElement($ItemElementName)
                
                foreach ($prop in $item.PSObject.Properties) {
                    $element = $xmlDoc.CreateElement($prop.Name)
                    
                    # Handle different value types
                    if ($null -eq $prop.Value) {
                        $element.InnerText = ""
                    }
                    elseif ($prop.Value -is [System.Array]) {
                        # For arrays, create child elements
                        foreach ($arrayItem in $prop.Value) {
                            $arrayElement = $xmlDoc.CreateElement("Item")
                            $arrayElement.InnerText = $arrayItem.ToString()
                            $element.AppendChild($arrayElement) | Out-Null
                        }
                    }
                    else {
                        $element.InnerText = $prop.Value.ToString()
                    }
                    
                    $itemElement.AppendChild($element) | Out-Null
                }
                
                $dataSection.AppendChild($itemElement) | Out-Null
            }

            # Save to file
            $xmlDoc.Save($OutputPath)
            Write-Verbose "XML report generated at: $OutputPath"

            if ($OpenInNotepad) {
                Start-Process notepad.exe -ArgumentList $OutputPath
            }

            # Return the path to the generated report
            return $OutputPath
        }
        catch {
            Write-LogMessage "Failed to generate XML report" -Level ERROR -Exception $_
            return $null
        }
    }
}
Export-ModuleMember -Function Export-ArrayToXmlFile, Export-ArrayToJsonFile, Export-ArrayToMarkdownFile, Export-ArrayToTxtFile, Export-ArrayToHtmlFile, Export-ArrayToCsvFile, Get-PropertyNames