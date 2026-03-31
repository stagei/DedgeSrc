# MarkdownToHtml Module

## Overview
The MarkdownToHtml module provides functionality to convert Markdown files to HTML with built-in support for Mermaid diagrams. It generates responsive, well-styled HTML documents that maintain the formatting of the original Markdown content while adding support for interactive diagrams.

## Exported Functions

### Convert-MarkdownToHtml
Converts a Markdown file to HTML with Mermaid diagram support.

#### Parameters
- **MarkdownPath**: The path to the input Markdown file.
- **OutputPath**: Optional. The path where the HTML file should be saved. If not specified, creates an HTML file in the same location as the input file with the same name but .html extension.
- **OpenInBrowser**: Optional switch. If specified, opens the generated HTML file in the default browser.

#### Behavior
- Reads the content of the specified Markdown file
- Embeds the Markdown content in an HTML template with CSS styling
- Includes Mermaid.js for diagram rendering
- Saves the resulting HTML file to the specified location
- Optionally opens the generated HTML file in the default browser

#### Examples
```powershell
# Convert a Markdown file to HTML in the same directory
Convert-MarkdownToHtml -MarkdownPath "document.md"

# Convert a Markdown file to HTML with a specific output path
Convert-MarkdownToHtml -MarkdownPath "input.md" -OutputPath "C:\output\document.html"

# Convert a Markdown file and immediately open it in the browser
Convert-MarkdownToHtml -MarkdownPath "documentation.md" -OpenInBrowser
```

## HTML Template Features
- Responsive design with clean typography
- Syntax highlighting for code blocks
- Centered Mermaid diagrams with proper spacing
- Mobile-friendly layout

## Dependencies
- Mermaid.js (loaded from CDN in the generated HTML)

## Features

- Converts Markdown files to HTML
- Built-in support for Mermaid diagrams
- Clean, responsive design
- Option to automatically open the generated HTML in your default browser

## Installation

1. Copy the `MarkdownToHtml` folder to your PowerShell modules directory
2. Import the module:
```powershell
Import-Module MarkdownToHtml
```

## Usage

Basic usage:
```powershell
Convert-MarkdownToHtml -MarkdownPath "path/to/your/file.md"
```

Convert and specify output path:
```powershell
Convert-MarkdownToHtml -MarkdownPath "path/to/your/file.md" -OutputPath "path/to/output.html"
```

Convert and open in browser:
```powershell
Convert-MarkdownToHtml -MarkdownPath "path/to/your/file.md" -OpenInBrowser
```

## Mermaid Support

The module automatically supports Mermaid diagrams. In your markdown, create a Mermaid diagram using the following syntax:

\```mermaid
graph TD
    A[Start] --> B{Is it working?}
    B -- Yes --> C[Great!]
    B -- No --> D[Debug]
\```

## Requirements

- PowerShell 5.1 or later
- Internet connection (for loading the Mermaid library) 