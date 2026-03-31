# Export-Array Module

Exports arrays to various file formats with advanced formatting options.

## Exported Functions

### Export-ArrayToXmlFile
Exports an array to an XML file with custom formatting.

```powershell
Export-ArrayToXmlFile -Content <PSObject[]> [-OutputPath <string>] [-OpenInNotepad] [-RootElementName <string>] [-ItemElementName <string>]
```

### Export-ArrayToJsonFile
Exports an array to a JSON file with optional pretty printing.

```powershell
Export-ArrayToJsonFile -Content <PSObject[]> [-OutputPath <string>] [-Pretty <bool>] [-OpenInNotepad]
```

### Export-ArrayToMarkdownFile
Exports an array to a Markdown file with table formatting.

```powershell
Export-ArrayToMarkdownFile -Content <PSObject[]> [-Headers <string[]>] [-OutputPath <string>] [-Title <string>] [-OpenInNotepad]
```

### Export-ArrayToTxtFile
Exports an array to a formatted text file.

```powershell
Export-ArrayToTxtFile -Content <PSObject[]> [-Headers <string[]>] [-OutputPath <string>] [-Title <string>] [-OpenInNotepad]
```

### Export-ArrayToHtmlFile
Exports an array to a styled HTML file.

```powershell
Export-ArrayToHtmlFile -Content <PSObject[]> [-Headers <string[]>] [-OutputPath <string>] [-Title <string>] [-AutoOpen]
```

### Export-ArrayToCsvFile
Exports an array to a CSV file with custom delimiter.

```powershell
Export-ArrayToCsvFile -Content <PSObject[]> [-Headers <string[]>] [-OutputPath <string>] [-AutoOpen] [-Delimiter <string>]
```

Each function supports:
- Custom output paths (defaults to script location if not specified)
- Optional headers
- Opening in associated application
- Custom formatting options
- Special character handling

## Dependencies
- GlobalFunctions module
```powershell
# Export data to CSV
$data = @(
    [PSCustomObject]@{ Name = "John"; Age = 30 },
    [PSCustomObject]@{ Name = "Jane"; Age = 25 }
)
Export-ArrayToCsvFile -Content $data -OutputPath "users.csv" -AutoOpen

# Export data to HTML with a title and open in browser
Export-ArrayToHtmlFile -Content $data -Title "User List" -OutputPath "users.html" -AutoOpen

# Export data to JSON
Export-ArrayToJsonFile -Content $data -OutputPath "users.json" -Pretty -OpenInNotepad

# Export data to XML
Export-ArrayToXmlFile -Content $data -OutputPath "users.xml" -RootElementName "Users" -ItemElementName "User"

# Export data to plain text
Export-ArrayToTxtFile -Content $data -OutputPath "users.txt" -Title "User List" -OpenInNotepad
``` 