<#
.SYNOPSIS
    Enhanced Dialog System .imp file parser with tabbed window views and layout estimation.

.DESCRIPTION
    Parses Dialog System export (.imp) files to extract:
    - Form Data: field definitions passed between COBOL and screensets
    - Window Hierarchy: WINDOW/DIALOG-BOX parent-child relationships
    - Objects: UI elements with positions for layout estimation
    - Field Bindings: Masterfield → Form Data connections with Picture formats
    - Navigation: SET-FOCUS, SHOW-WINDOW commands
    
    Generates an HTML page with:
    1. Tabbed view - one tab per window/dialog
    2. Coordinate-based layout grid showing component positions
    3. Field binding cross-reference table
    4. Navigation flow diagram

.PARAMETER ImpFile
    Path to a single .imp file to parse. Defaults to BKHOPPG.IMP.

.PARAMETER OutputFolder
    Output folder for generated HTML. Defaults to C:\opt\Work\AutoDoc\Content

.PARAMETER OpenBrowser
    If specified, opens the generated HTML in the default browser.

.PARAMETER SendSMS
    If specified, sends SMS notification when complete.

.EXAMPLE
    .\Test-DialogSystemParser.ps1 -ImpFile "C:\opt\Work\DedgeRepository\Dedge\imp\BKHOPPG.IMP" -OpenBrowser
#>

param(
    [string]$ImpFile = "C:\opt\Work\DedgeRepository\Dedge\imp\BKHOPPG.IMP",
    [string]$OutputFolder = "C:\opt\Work\AutoDoc\Content",
    [switch]$OpenBrowser,
    [switch]$SendSMS
)

Import-Module GlobalFunctions -Force

#region Helper Classes

class FormField {
    [string]$Name
    [string]$DataType
    [string]$Size
    [string]$GroupName
    [int]$GroupOccurs
    [string]$Attributes
    [bool]$IsErrorField
}

class UIObject {
    [string]$Name
    [string]$Type
    [string]$Parent
    [int]$StartX
    [int]$StartY
    [int]$Width
    [int]$Height
    [string]$Display
    [string]$Style
    [string]$Masterfield
    [string]$Picture
    [System.Collections.ArrayList]$Fields = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList]$Events = [System.Collections.ArrayList]::new()
}

class EventHandler {
    [string]$EventName
    [string]$Actions
}

class WindowInfo {
    [string]$Name
    [string]$Type
    [string]$Parent
    [string]$Display
    [int]$StartX
    [int]$StartY
    [int]$Width
    [int]$Height
    [System.Collections.ArrayList]$Children = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList]$Components = [System.Collections.ArrayList]::new()
}

class DialogSystemScreen {
    [string]$FormName
    [string]$FirstWindow
    [string]$GridStyle
    [System.Collections.ArrayList]$FormFields = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList]$UIObjects = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList]$GlobalEvents = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList]$GlobalProcedures = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList]$DataValidations = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList]$NavigationCommands = [System.Collections.ArrayList]::new()
    [hashtable]$WindowHierarchy = @{}
}

#endregion

#region Parsing Functions

function ConvertFrom-ImpFile {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        Write-LogMessage "IMP file not found: $FilePath" -Level ERROR
        return $null
    }
    
    # IMP files are Windows-1252 (ANSI) encoded
    $content = Get-Content $FilePath -Raw -Encoding 1252
    $screen = [DialogSystemScreen]::new()
    
    # Parse Form name
    if ($content -match '^Form\s+(\w+)') {
        $screen.FormName = $matches[1]
    }
    
    # Parse First-Window
    if ($content -match 'First-Window\s+([\w-]+)') {
        $screen.FirstWindow = $matches[1]
    }
    
    # Parse Grid style
    if ($content -match 'Style\s+(?:EMU-PORTABLE\s+)?GRID\((\d+),(\d+)\)') {
        $screen.GridStyle = "GRID($($matches[1]),$($matches[2]))"
    }
    
    # Parse Form Data section
    $screen.FormFields = Get-FormDataFields -Content $content
    
    # Parse Objects
    $screen.UIObjects = Get-UIObjects -Content $content
    
    # Parse Global Dialog
    $globalDialogResult = Get-GlobalDialogContent -Content $content
    $screen.GlobalEvents = $globalDialogResult.Events
    $screen.GlobalProcedures = $globalDialogResult.Procedures
    
    # Parse Data Validations
    $screen.DataValidations = Get-DataValidations -Content $content
    
    # Extract Navigation Commands
    $screen.NavigationCommands = Get-NavigationCommands -Content $content
    
    # Build Window Hierarchy
    $screen.WindowHierarchy = Build-WindowHierarchy -Screen $screen
    
    return $screen
}

function Get-FormDataFields {
    param([string]$Content)
    
    $fields = [System.Collections.ArrayList]::new()
    
    if ($Content -match '(?s)Form Data(.+?)End Data') {
        $formDataSection = $matches[1]
        $dataLines = $formDataSection -split "`n"
        
        $currentGroup = ""
        $currentGroupOccurs = 0
        
        foreach ($line in $dataLines) {
            $trimmedLine = $line.Trim()
            
            if ($trimmedLine -match '^\*' -or $trimmedLine -eq '') { continue }
            
            if ($trimmedLine -match 'Group\s+([\w-]+)\s+Vertical\s+Occurs\s+(\d+)') {
                $currentGroup = $matches[1]
                $currentGroupOccurs = [int]$matches[2]
                continue
            }
            
            if ($trimmedLine -match 'End Group') {
                $currentGroup = ""
                $currentGroupOccurs = 0
                continue
            }
            
            if ($trimmedLine -match '^([\w-]+)\s+(Character|Integer|Decimal)\((\d+(?:\.\d+)?)\)(.*)$') {
                $field = [FormField]::new()
                $field.Name = $matches[1]
                $field.DataType = $matches[2]
                $field.Size = $matches[3]
                $field.GroupName = $currentGroup
                $field.GroupOccurs = $currentGroupOccurs
                $field.Attributes = $matches[4].Trim()
                $field.IsErrorField = $field.Attributes -match 'Error-Field'
                [void]$fields.Add($field)
            }
        }
    }
    
    return $fields
}

function Get-UIObjects {
    param([string]$Content)
    
    $objects = [System.Collections.ArrayList]::new()
    
    $objectPattern = '(?s)Object\s+(\{?[\w-]+\}?)(.+?)End Object'
    $objectMatches = [regex]::Matches($Content, $objectPattern)
    
    foreach ($match in $objectMatches) {
        $obj = [UIObject]::new()
        $obj.Name = $match.Groups[1].Value
        $objContent = $match.Groups[2].Value
        
        if ($objContent -match 'Type\s+([\w-]+)') { $obj.Type = $matches[1] }
        if ($objContent -match 'Parent\s+([\$\w-]+)') { $obj.Parent = $matches[1] }
        if ($objContent -match 'Start\s+\(\s*(\d+)\s*,\s*(\d+)\s*\)') {
            $obj.StartX = [int]$matches[1]
            $obj.StartY = [int]$matches[2]
        }
        if ($objContent -match 'Size\s+\(\s*(\d+)\s*,\s*(\d+)\s*\)') {
            $obj.Width = [int]$matches[1]
            $obj.Height = [int]$matches[2]
        }
        if ($objContent -match 'Display\s+"([^"]*)"') { $obj.Display = $matches[1] }
        if ($objContent -match 'Style\s+(.+?)(?:\r?\n|$)') { $obj.Style = $matches[1].Trim() }
        if ($objContent -match 'Masterfield\s+([\w-]+)') { $obj.Masterfield = $matches[1] }
        if ($objContent -match 'Picture\s+(\S+)') { $obj.Picture = $matches[1] }
        
        # Parse nested Field definitions (for LIST-BOX)
        $fieldMatches = [regex]::Matches($objContent, '(?s)Field(.+?)End Field')
        foreach ($fieldMatch in $fieldMatches) {
            $fieldContent = $fieldMatch.Groups[1].Value
            $fieldInfo = @{}
            if ($fieldContent -match 'Masterfield\s+([\w-]+)') { $fieldInfo['Masterfield'] = $matches[1] }
            if ($fieldContent -match 'Picture\s+(\S+)') { $fieldInfo['Picture'] = $matches[1] }
            [void]$obj.Fields.Add($fieldInfo)
        }
        
        # Parse Events
        if ($objContent -match '(?s)Dialog\s+CASE\(\w+\)(.+?)End Dialog') {
            $dialogContent = $matches[1]
            $eventMatches = [regex]::Matches($dialogContent, '(?s)Event\s+([\w-]+)(.+?)End Event')
            foreach ($eventMatch in $eventMatches) {
                $evt = [EventHandler]::new()
                $evt.EventName = $eventMatch.Groups[1].Value
                $evt.Actions = $eventMatch.Groups[2].Value.Trim() -replace '\s+', ' '
                [void]$obj.Events.Add($evt)
            }
        }
        
        [void]$objects.Add($obj)
    }
    
    return $objects
}

function Get-GlobalDialogContent {
    param([string]$Content)
    
    $result = @{
        Events = [System.Collections.ArrayList]::new()
        Procedures = [System.Collections.ArrayList]::new()
    }
    
    if ($Content -match '(?s)Global\s+Dialog\s+CASE\(\w+\)(.+?)End\s+Dialog(?=\s*\n\s*End\s+Form)') {
        $globalContent = $matches[1]
        
        $eventMatches = [regex]::Matches($globalContent, '(?s)Event\s+([\w-]+)(.+?)End Event')
        foreach ($match in $eventMatches) {
            $evt = [EventHandler]::new()
            $evt.EventName = $match.Groups[1].Value
            $evt.Actions = ($match.Groups[2].Value -replace '\*[^\n]*\n', '' -replace '\s+', ' ').Trim()
            [void]$result.Events.Add($evt)
        }
        
        $procMatches = [regex]::Matches($globalContent, '(?s)Procedure\s+([\w-@]+)(.+?)End Procedure')
        foreach ($match in $procMatches) {
            $proc = @{
                Name = $match.Groups[1].Value
                Actions = ($match.Groups[2].Value -replace '\*[^\n]*\n', '' -replace '\s+', ' ').Trim()
            }
            [void]$result.Procedures.Add($proc)
        }
    }
    
    return $result
}

function Get-DataValidations {
    param([string]$Content)
    
    $validations = [System.Collections.ArrayList]::new()
    
    # Data Validation <field> External "<program>" End Validation
    $pattern = '(?s)Data Validation\s+([\w-]+)(.+?)End Validation'
    $matches = [regex]::Matches($Content, $pattern)
    
    foreach ($match in $matches) {
        $fieldName = $match.Groups[1].Value
        $valContent = $match.Groups[2].Value
        
        $externalProgram = ""
        if ($valContent -match 'External\s+"([^"]+)"') {
            $externalProgram = $matches[1]
        }
        
        [void]$validations.Add(@{
            Field = $fieldName
            ExternalProgram = $externalProgram
        })
    }
    
    return $validations
}

function Get-NavigationCommands {
    param([string]$Content)
    
    $commands = [System.Collections.ArrayList]::new()
    
    # Extract SET-FOCUS commands to dialogs
    $focusMatches = [regex]::Matches($Content, 'SET-FOCUS\s+([\w-]+)')
    foreach ($match in $focusMatches) {
        $target = $match.Groups[1].Value
        if ($target -match '^(DBOX|WIN|DB-)') {
            [void]$commands.Add(@{ Type = "SET-FOCUS"; Target = $target })
        }
    }
    
    # Extract SHOW-WINDOW commands
    $showMatches = [regex]::Matches($Content, 'SHOW-WINDOW\s+([\w-]+)')
    foreach ($match in $showMatches) {
        [void]$commands.Add(@{ Type = "SHOW-WINDOW"; Target = $match.Groups[1].Value })
    }
    
    # Extract UNSHOW-WINDOW commands
    $unshowMatches = [regex]::Matches($Content, 'UNSHOW-WINDOW\s+([\$\w-]+)')
    foreach ($match in $unshowMatches) {
        [void]$commands.Add(@{ Type = "UNSHOW-WINDOW"; Target = $match.Groups[1].Value })
    }
    
    return $commands
}

function Build-WindowHierarchy {
    param([DialogSystemScreen]$Screen)
    
    $hierarchy = @{}
    
    # Find all windows and dialogs
    $windows = $Screen.UIObjects | Where-Object { $_.Type -in @('WINDOW', 'DIALOG-BOX') }
    
    foreach ($win in $windows) {
        $winInfo = [WindowInfo]::new()
        $winInfo.Name = $win.Name
        $winInfo.Type = $win.Type
        $winInfo.Parent = $win.Parent
        $winInfo.Display = $win.Display
        $winInfo.StartX = $win.StartX
        $winInfo.StartY = $win.StartY
        $winInfo.Width = $win.Width
        $winInfo.Height = $win.Height
        
        # Find child windows
        $childWindows = $windows | Where-Object { $_.Parent -eq $win.Name }
        foreach ($child in $childWindows) {
            [void]$winInfo.Children.Add($child.Name)
        }
        
        # Find components (non-window objects with this as parent)
        $components = $Screen.UIObjects | Where-Object { 
            $_.Parent -eq $win.Name -and $_.Type -notin @('WINDOW', 'DIALOG-BOX')
        }
        foreach ($comp in $components) {
            [void]$winInfo.Components.Add($comp)
        }
        
        $hierarchy[$win.Name] = $winInfo
    }
    
    return $hierarchy
}

#endregion

#region HTML Generation

function New-DialogSystemHtml {
    param(
        [DialogSystemScreen]$Screen,
        [string]$ImpFilePath
    )
    
    $baseName = $Screen.FormName
    
    # Build field bindings lookup (FormField Name -> attributes)
    $fieldBindings = @{}
    foreach ($field in $Screen.FormFields) {
        $fieldBindings[$field.Name] = $field
    }
    
    # Get ordered list of windows (first window first, then by parent hierarchy)
    $orderedWindows = Get-OrderedWindows -Screen $Screen
    
    # Generate tabs HTML
    $tabsHtml = [System.Text.StringBuilder]::new()
    $tabContentHtml = [System.Text.StringBuilder]::new()
    
    $isFirst = $true
    foreach ($winName in $orderedWindows) {
        $window = $Screen.WindowHierarchy[$winName]
        if (-not $window) { continue }
        
        $activeClass = if ($isFirst) { 'active' } else { '' }
        $tabId = $winName -replace '[^a-zA-Z0-9]', '_'
        
        # Tab button
        $tabLabel = if ($window.Display) { "$winName - $($window.Display)" } else { $winName }
        [void]$tabsHtml.AppendLine("<button class='tab-btn $activeClass' data-tab='$tabId'>$tabLabel</button>")
        
        # Tab content
        [void]$tabContentHtml.AppendLine("<div class='tab-content $activeClass' id='$tabId'>")
        [void]$tabContentHtml.AppendLine((New-WindowTabContent -Window $window -Screen $Screen -FieldBindings $fieldBindings))
        [void]$tabContentHtml.AppendLine("</div>")
        
        $isFirst = $false
    }
    
    # Generate field bindings table
    $fieldBindingsHtml = New-FieldBindingsTable -Screen $Screen
    
    # Generate navigation flow
    $navigationHtml = New-NavigationFlowHtml -Screen $Screen
    
    # Generate data validations table
    $validationsHtml = New-DataValidationsTable -Screen $Screen
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dialog System: $baseName</title>
    <link rel="icon" href="./_images/dedge.ico" type="image/x-icon" />
    <style>
        :root {
            --bg-primary: #ffffff;
            --bg-secondary: #f8f9fa;
            --bg-tertiary: #e9ecef;
            --text-primary: #212529;
            --text-secondary: #6c757d;
            --border-color: #dee2e6;
            --accent-primary: #006838;
            --accent-secondary: #0d6efd;
            --tab-active: #006838;
            --type-text: #6c757d;
            --type-entry: #0d6efd;
            --type-button: #198754;
            --type-list: #6f42c1;
            --type-check: #fd7e14;
        }
        
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #1a1a1a;
                --bg-secondary: #2d2d2d;
                --bg-tertiary: #3d3d3d;
                --text-primary: #e0e0e0;
                --text-secondary: #a0a0a0;
                --border-color: #444;
                --accent-primary: #4caf50;
                --tab-active: #4caf50;
                --type-text: #888;
                --type-entry: #64b5f6;
                --type-button: #81c784;
                --type-list: #b39ddb;
                --type-check: #ffb74d;
            }
        }
        
        * { box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', system-ui, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            margin: 0;
            padding: 20px;
            line-height: 1.5;
        }
        .container { max-width: 1600px; margin: 0 auto; }
        
        header {
            display: flex;
            align-items: center;
            gap: 1rem;
            padding-bottom: 1rem;
            border-bottom: 2px solid var(--accent-primary);
            margin-bottom: 1.5rem;
        }
        header a { display: flex; }
        header img { height: 40px; }
        header h1 { margin: 0; color: var(--accent-primary); flex: 1; }
        .badge {
            background: var(--accent-primary);
            color: white;
            padding: 0.3rem 0.8rem;
            border-radius: 4px;
            font-size: 0.85rem;
            font-weight: 600;
        }
        .back-link {
            display: inline-block;
            margin-bottom: 1rem;
            color: var(--accent-primary);
            text-decoration: none;
        }
        .back-link:hover { text-decoration: underline; }
        
        /* Meta info */
        .meta-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            gap: 0.75rem;
            margin-bottom: 1.5rem;
        }
        .meta-item {
            background: var(--bg-secondary);
            padding: 0.75rem;
            border-radius: 6px;
            border-left: 3px solid var(--accent-primary);
        }
        .meta-item label { font-size: 0.75rem; color: var(--text-secondary); display: block; }
        .meta-item span { font-weight: 600; }
        
        /* Tabs */
        .tabs-container { margin-bottom: 1.5rem; }
        .tabs {
            display: flex;
            flex-wrap: wrap;
            gap: 0.25rem;
            border-bottom: 2px solid var(--border-color);
            padding-bottom: 0;
        }
        .tab-btn {
            background: var(--bg-secondary);
            border: 1px solid var(--border-color);
            border-bottom: none;
            padding: 0.6rem 1rem;
            cursor: pointer;
            border-radius: 6px 6px 0 0;
            font-size: 0.9rem;
            color: var(--text-secondary);
            transition: all 0.2s;
        }
        .tab-btn:hover { background: var(--bg-tertiary); }
        .tab-btn.active {
            background: var(--tab-active);
            color: white;
            border-color: var(--tab-active);
        }
        .tab-content { display: none; padding: 1rem 0; }
        .tab-content.active { display: block; }
        
        /* Sections */
        .section {
            background: var(--bg-secondary);
            border-radius: 8px;
            padding: 1.25rem;
            margin-bottom: 1.25rem;
        }
        .section h3 {
            margin: 0 0 1rem 0;
            color: var(--accent-primary);
            font-size: 1.1rem;
            border-bottom: 1px solid var(--border-color);
            padding-bottom: 0.5rem;
        }
        .section h4 { margin: 1rem 0 0.5rem 0; font-size: 0.95rem; }
        
        /* Tables */
        table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
        th, td { text-align: left; padding: 0.5rem; border-bottom: 1px solid var(--border-color); }
        th { background: var(--accent-primary); color: white; font-weight: 600; }
        tr:hover { background: var(--bg-tertiary); }
        
        /* Columns */
        .columns { display: grid; grid-template-columns: 1fr 1fr; gap: 1.25rem; }
        @media (max-width: 1000px) { .columns { grid-template-columns: 1fr; } }
        
        code { 
            background: var(--bg-tertiary); 
            padding: 0.15rem 0.4rem; 
            border-radius: 3px;
            font-family: 'Consolas', monospace;
            font-size: 0.85em;
        }
        .text-muted { color: var(--text-secondary); }
        
        footer {
            text-align: center;
            padding: 2rem 0;
            color: var(--text-secondary);
            font-size: 0.85rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <a href="index.html" class="back-link">← Back to AutoDoc</a>
        
        <header>
            <a href="index.html"><img src="./_images/dedge.svg" alt="FK" /></a>
            <h1>$baseName</h1>
            <span class="badge">Dialog System Screen</span>
        </header>
        
        <div class="meta-grid">
            <div class="meta-item"><label>Form Name</label><span>$($Screen.FormName)</span></div>
            <div class="meta-item"><label>First Window</label><span>$($Screen.FirstWindow)</span></div>
            <div class="meta-item"><label>Grid Style</label><span>$($Screen.GridStyle)</span></div>
            <div class="meta-item"><label>Windows/Dialogs</label><span>$($Screen.WindowHierarchy.Count)</span></div>
            <div class="meta-item"><label>Total Objects</label><span>$($Screen.UIObjects.Count)</span></div>
            <div class="meta-item"><label>Form Fields</label><span>$($Screen.FormFields.Count)</span></div>
        </div>
        
        <div class="tabs-container">
            <div class="tabs">
                $($tabsHtml.ToString())
            </div>
            $($tabContentHtml.ToString())
        </div>
        
        <div class="columns">
            <div class="section">
                <h3>Field Bindings</h3>
                <p class="text-muted">UI elements linked to Form Data fields via Masterfield.</p>
                $fieldBindingsHtml
            </div>
            <div class="section">
                <h3>External Validations</h3>
                <p class="text-muted">Fields validated by external COBOL programs.</p>
                $validationsHtml
            </div>
        </div>
        
        <div class="section">
            <h3>Navigation Flow</h3>
            <p class="text-muted">Dialog navigation commands (SET-FOCUS, SHOW-WINDOW).</p>
            $navigationHtml
        </div>
        
        <footer>
            Generated by AutoDoc Dialog System Parser | $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        </footer>
    </div>
    
    <script>
        document.querySelectorAll('.tab-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
                document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
                btn.classList.add('active');
                document.getElementById(btn.dataset.tab).classList.add('active');
            });
        });
    </script>
</body>
</html>
"@
    
    return $html
}

function Get-OrderedWindows {
    param([DialogSystemScreen]$Screen)
    
    $ordered = [System.Collections.ArrayList]::new()
    $visited = @{}
    
    # Start with first window
    if ($Screen.FirstWindow -and $Screen.WindowHierarchy.ContainsKey($Screen.FirstWindow)) {
        Add-WindowAndChildren -WindowName $Screen.FirstWindow -Hierarchy $Screen.WindowHierarchy -Ordered $ordered -Visited $visited
    }
    
    # Add any remaining windows
    foreach ($winName in $Screen.WindowHierarchy.Keys) {
        if (-not $visited.ContainsKey($winName)) {
            Add-WindowAndChildren -WindowName $winName -Hierarchy $Screen.WindowHierarchy -Ordered $ordered -Visited $visited
        }
    }
    
    return $ordered
}

function Add-WindowAndChildren {
    param(
        [string]$WindowName,
        [hashtable]$Hierarchy,
        [System.Collections.ArrayList]$Ordered,
        [hashtable]$Visited
    )
    
    if ($Visited.ContainsKey($WindowName)) { return }
    $Visited[$WindowName] = $true
    [void]$Ordered.Add($WindowName)
    
    $window = $Hierarchy[$WindowName]
    if ($window -and $window.Children) {
        foreach ($childName in $window.Children) {
            Add-WindowAndChildren -WindowName $childName -Hierarchy $Hierarchy -Ordered $Ordered -Visited $Visited
        }
    }
}

function New-WindowTabContent {
    param(
        [WindowInfo]$Window,
        [DialogSystemScreen]$Screen,
        [hashtable]$FieldBindings
    )
    
    $html = [System.Text.StringBuilder]::new()
    
    # Window info
    [void]$html.AppendLine("<div class='section'>")
    [void]$html.AppendLine("<h3>$($Window.Display)</h3>")
    [void]$html.AppendLine("<p><strong>Type:</strong> $($Window.Type) | <strong>Parent:</strong> $($Window.Parent) | <strong>Size:</strong> $($Window.Width) x $($Window.Height) | <strong>Components:</strong> $($Window.Components.Count)</p>")
    
    if ($Window.Children.Count -gt 0) {
        $childLinks = ($Window.Children | ForEach-Object { "<code>$_</code>" }) -join ", "
        [void]$html.AppendLine("<p><strong>Child Windows:</strong> $childLinks</p>")
    }
    [void]$html.AppendLine("</div>")
    
    # Components table
    [void]$html.AppendLine("<div class='section'>")
    [void]$html.AppendLine("<h3>Components ($($Window.Components.Count))</h3>")
    [void]$html.AppendLine("<div style='overflow-x:auto;'>")
    [void]$html.AppendLine("<table><thead><tr><th>Name</th><th>Type</th><th>Position</th><th>Display</th><th>Masterfield</th><th>Picture</th></tr></thead><tbody>")
    
    foreach ($comp in ($Window.Components | Sort-Object StartY, StartX)) {
        $pos = "($($comp.StartX), $($comp.StartY))"
        $display = if ($comp.Display) { $comp.Display -replace '~', '' } else { '-' }
        $master = if ($comp.Masterfield) { "<code>$($comp.Masterfield)</code>" } else { '-' }
        $picture = if ($comp.Picture) { "<code>$($comp.Picture)</code>" } else { '-' }
        [void]$html.AppendLine("<tr><td>$($comp.Name)</td><td>$($comp.Type)</td><td>$pos</td><td>$display</td><td>$master</td><td>$picture</td></tr>")
    }
    
    [void]$html.AppendLine("</tbody></table></div></div>")
    
    return $html.ToString()
}

function New-FieldBindingsTable {
    param([DialogSystemScreen]$Screen)
    
    $html = [System.Text.StringBuilder]::new()
    
    # Find all objects with Masterfield bindings
    $bindings = $Screen.UIObjects | Where-Object { $_.Masterfield } | ForEach-Object {
        $formField = $Screen.FormFields | Where-Object { $_.Name -eq $_.Masterfield } | Select-Object -First 1
        @{
            UIElement = $_.Name
            UIType = $_.Type
            Parent = $_.Parent
            Masterfield = $_.Masterfield
            Picture = $_.Picture
            FormFieldType = if ($formField) { "$($formField.DataType)($($formField.Size))" } else { '-' }
            Group = if ($formField -and $formField.GroupName) { "$($formField.GroupName)[$($formField.GroupOccurs)]" } else { '-' }
        }
    }
    
    if ($bindings.Count -eq 0) {
        return "<p class='text-muted'>No field bindings found.</p>"
    }
    
    [void]$html.AppendLine("<table><thead><tr><th>UI Element</th><th>Type</th><th>Masterfield</th><th>Picture</th><th>Form Data Type</th><th>Group</th></tr></thead><tbody>")
    
    foreach ($b in $bindings) {
        $picture = if ($b.Picture) { "<code>$($b.Picture)</code>" } else { '-' }
        [void]$html.AppendLine("<tr><td>$($b.UIElement)</td><td>$($b.UIType)</td><td><code>$($b.Masterfield)</code></td><td>$picture</td><td>$($b.FormFieldType)</td><td>$($b.Group)</td></tr>")
    }
    
    [void]$html.AppendLine("</tbody></table>")
    
    return $html.ToString()
}

function New-DataValidationsTable {
    param([DialogSystemScreen]$Screen)
    
    if ($Screen.DataValidations.Count -eq 0) {
        return "<p class='text-muted'>No external validations defined.</p>"
    }
    
    $html = [System.Text.StringBuilder]::new()
    [void]$html.AppendLine("<table><thead><tr><th>Field</th><th>External Program</th></tr></thead><tbody>")
    
    foreach ($v in $Screen.DataValidations) {
        [void]$html.AppendLine("<tr><td><code>$($v.Field)</code></td><td><code>$($v.ExternalProgram)</code></td></tr>")
    }
    
    [void]$html.AppendLine("</tbody></table>")
    
    return $html.ToString()
}

function New-NavigationFlowHtml {
    param([DialogSystemScreen]$Screen)
    
    if ($Screen.NavigationCommands.Count -eq 0) {
        return "<p class='text-muted'>No navigation commands found.</p>"
    }
    
    $html = [System.Text.StringBuilder]::new()
    
    # Group by command type
    $grouped = $Screen.NavigationCommands | Group-Object { $_.Type }
    
    [void]$html.AppendLine("<table><thead><tr><th>Command</th><th>Target</th></tr></thead><tbody>")
    
    foreach ($cmd in $Screen.NavigationCommands | Select-Object -Unique -Property Type, Target) {
        [void]$html.AppendLine("<tr><td><code>$($cmd.Type)</code></td><td><code>$($cmd.Target)</code></td></tr>")
    }
    
    [void]$html.AppendLine("</tbody></table>")
    
    return $html.ToString()
}

#endregion

#region Main Execution

Write-LogMessage "========================================" -Level INFO
Write-LogMessage "Enhanced Dialog System Parser" -Level INFO
Write-LogMessage "========================================" -Level INFO

if (-not (Test-Path $ImpFile)) {
    Write-LogMessage "IMP file not found: $ImpFile" -Level ERROR
    exit 1
}

Write-LogMessage "Parsing IMP file: $ImpFile" -Level INFO

$screen = ConvertFrom-ImpFile -FilePath $ImpFile

if (-not $screen) {
    Write-LogMessage "Failed to parse IMP file" -Level ERROR
    exit 1
}

Write-LogMessage "Successfully parsed screenset: $($screen.FormName)" -Level INFO
Write-LogMessage "  - Windows/Dialogs: $($screen.WindowHierarchy.Count)" -Level INFO
Write-LogMessage "  - Form Fields: $($screen.FormFields.Count)" -Level INFO
Write-LogMessage "  - UI Objects: $($screen.UIObjects.Count)" -Level INFO
Write-LogMessage "  - Global Events: $($screen.GlobalEvents.Count)" -Level INFO
Write-LogMessage "  - Data Validations: $($screen.DataValidations.Count)" -Level INFO

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    Write-LogMessage "Created output folder: $OutputFolder" -Level INFO
}

Write-LogMessage "Generating HTML output..." -Level INFO
$html = New-DialogSystemHtml -Screen $screen -ImpFilePath $ImpFile

$outputFile = Join-Path $OutputFolder "$($screen.FormName).screen.html"
$html | Set-Content -Path $outputFile -Encoding UTF8 -Force

Write-LogMessage "HTML generated: $outputFile" -Level INFO

if ($OpenBrowser) {
    Write-LogMessage "Opening in browser..." -Level INFO
    Start-Process $outputFile
}

if ($SendSMS) {
    try {
        $smsMessage = "Dialog System Parser: $($screen.FormName) - $($screen.WindowHierarchy.Count) windows, $($screen.UIObjects.Count) objects"
        Send-Sms -Receiver "4797188358" -Message $smsMessage
        Write-LogMessage "SMS notification sent" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to send SMS: $($_.Exception.Message)" -Level WARN
    }
}

Write-LogMessage "========================================" -Level INFO
Write-LogMessage "Processing complete!" -Level INFO
Write-LogMessage "========================================" -Level INFO

return $outputFile

#endregion
