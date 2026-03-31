# Import the module
Import-Module "$PSScriptRoot\MarkdownToHtml.psm1" -Force

# Convert the test markdown file to HTML and open it in the browser
Convert-MarkdownToHtml -MarkdownPath "$PSScriptRoot\test.md" -OpenInBrowser

