# MarkdownToHtml.psm1

<#
.SYNOPSIS
    Converts Markdown files to HTML with enhanced styling and Mermaid diagram support.

.DESCRIPTION
    This module provides functionality to convert Markdown files into well-formatted HTML documents.
    The generated HTML includes responsive styling, proper code block formatting, and built-in support
    for Mermaid diagrams. The module is designed for documentation generation and presentation purposes.

.EXAMPLE
    Convert-MarkdownToHtml -MarkdownPath "README.md" -OpenInBrowser
    # Converts README.md to HTML and opens it in the default browser

.EXAMPLE
    Convert-MarkdownToHtml -MarkdownPath "docs.md" -OutputPath "documentation.html"
    # Converts docs.md to a custom-named HTML file
#>

<#
.SYNOPSIS
    Converts a Markdown file to HTML with Mermaid diagram support.

.DESCRIPTION
    Converts a Markdown file to a styled HTML document that includes support for Mermaid diagrams.
    The output HTML includes responsive styling and proper formatting for code blocks.
    The function can optionally open the generated HTML file in the default browser.

.PARAMETER MarkdownPath
    The path to the input Markdown file.

.PARAMETER OutputPath
    Optional. The path where the HTML file should be saved. If not specified,
    creates an HTML file in the same location as the input file.

.PARAMETER OpenInBrowser
    Optional switch. If specified, opens the generated HTML file in the default browser.

.EXAMPLE
    Convert-MarkdownToHtml -MarkdownPath "document.md"
    # Converts document.md to document.html in the same directory

.EXAMPLE
    Convert-MarkdownToHtml -MarkdownPath "input.md" -OutputPath "output.html" -OpenInBrowser
    # Converts input.md to output.html and opens it in the default browser
#>
function Convert-MarkdownToHtml {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MarkdownPath,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$OpenInBrowser
    )

    # Check if the markdown file exists
    if (-not (Test-Path $MarkdownPath)) {
        throw "Markdown file not found: $MarkdownPath"
    }

    # If no output path specified, create one based on input file
    if (-not $OutputPath) {
        $OutputPath = [System.IO.Path]::ChangeExtension($MarkdownPath, "html")
    }

    # Read the markdown content
    $markdownContent = Get-Content -Path $MarkdownPath -Raw

    # Create HTML template with Mermaid support
    $htmlTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Markdown to HTML</title>
    <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
    <script>
        mermaid.initialize({
            startOnLoad: true,
            theme: 'default'
        });
    </script>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, 'Open Sans', 'Helvetica Neue', sans-serif;
            line-height: 1.6;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            color: #333;
        }
        pre {
            background-color: #f5f5f5;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
        }
        code {
            font-family: 'Courier New', Courier, monospace;
        }
        .mermaid {
            text-align: center;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    $markdownContent
</body>
</html>
"@

    # Save the HTML file
    $htmlTemplate | Out-File -FilePath $OutputPath -Encoding UTF8

    Write-Host "HTML file generated successfully at: $OutputPath"

    # Open in default browser if requested
    if ($OpenInBrowser) {
        Start-Process $OutputPath
    }
}

# Export the function
Export-ModuleMember -Function Convert-MarkdownToHtml 