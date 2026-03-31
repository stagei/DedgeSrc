# AutoDoc Status Report

**Date:** 2026-01-23  
**Author:** Geir Helge Starholm, www.dEdge.no

---

## 📊 Test Results Summary

| File Type | Test File | Generation | Rendering | Notes |
|-----------|-----------|------------|-----------|-------|
| **CBL** | AABELMA.CBL | ✅ Pass | ✅ Pass | Flow + Sequence diagrams render correctly |
| **REX** | WKMONIT.REX | ✅ Pass | ✅ Pass | Flow diagram with 80+ called scripts |
| **BAT** | Catalog-All-Db2-Azure-Databases-Using-Kerberos-For-Db2Client.bat | ✅ Pass | ⚠️ Layout Error | Mermaid 11 layout engine limitation |
| **PS1** | Db2-CreateInitialDatabases.ps1 | ✅ Pass | ✅ Pass | Flow diagram with module imports |
| **SQL** | DBM.FAKTHIST99B | ✅ Pass | ✅ Pass | Table documentation with 64 columns |
| **C#** | ServerMonitor.sln | ✅ Pass | ⚠️ Partial | Some tabs work, others have pan-zoom issues |

---

## ✅ Features Working Correctly

### 1. HTML Generation
- All 6 file types generate HTML documentation successfully
- Client-side Mermaid.js rendering implemented
- Cache-busting URLs for JS/CSS files

### 2. Dark Mode Support
- Theme toggle (light/dark) functional
- Mermaid diagrams styled appropriately for both themes
- Bright blue lines (`#64b5f6`) in dark mode for visibility

### 3. External API Callers (NEW)
PowerShell scripts that call the REST API are now detected and displayed:
- 🔵 Db2-DiagTracker.ps1
- 🔵 Install-ServerMonitorService.ps1
- 🔵 ServerMonitorAgent.ps1
- 🔵 Start-ServerMonitor.ps1
- 🔵 Verify-NewEndpoints.ps1

### 4. Class Listing (FIXED)
- All 148 classes now displayed (previously limited to 50)
- No more "... and X more classes" truncation

### 5. JSON Data Files
Separate JSON files for each parser type:
- `CblParseResult.json` - COBOL programs
- `ScriptParseResult.json` - REX, BAT, PS1 scripts  
- `SqlParseResult.json` - SQL tables/views
- `CSharpParseResult.json` - C# solutions

### 6. File Filtering
- PS1 and BAT files with basename starting with `_` or `-` are skipped

---

## ⚠️ Known Issues

### 1. Mermaid 11 Large Diagram Limitations

**Affected:** Complex BAT files, some C# diagrams

**Symptom:** "Maximum text size in diagram exceeded" or `translate(undefined, NaN)` errors

**Root Cause:** Mermaid.js has built-in limits to prevent performance issues:

| Parameter | Default | Our Setting | Description |
|-----------|---------|-------------|-------------|
| `maxTextSize` | **50,000** | 5,000,000 | Maximum characters in diagram source |
| `maxEdges` | **500** | 5,000 | Maximum number of edges/connections |

> 📚 **Source:** [Mermaid Configuration Options](https://mermaid.js.org/config/schema-docs/config.html#maxtextsize)

**Why It Still Fails:**
Even with increased limits, some diagrams fail because:
1. The diagram has **many nodes/edges** causing `translate(undefined, NaN)` layout errors
2. The dagre-d3 layout engine cannot calculate positions for complex graphs
3. This is a **layout calculation issue**, not just a text size issue

**Missing Text in Diagrams:**
Mermaid 11 has two bugs that cause text to be invisible:
1. **foreignObject dimensions**: Text containers rendered with 0x0 size → text clipped
2. **Invalid transforms**: Parent `<g>` elements have `translate(undefined, NaN)` → text positioned offscreen

**Fix applied in `autodoc-diagram-controls.js`:**
```javascript
// Fix 1: foreignObject dimensions
fo.setAttribute('width', '300');
fo.setAttribute('height', '50');

// Fix 2: Invalid transforms
if (transform.includes('undefined') || transform.includes('NaN')) {
  g.setAttribute('transform', 'translate(0, 0)');
}
```

**Workarounds:**

1. **Increase `maxEdges`** - Set `maxEdges: 5000` or higher in mermaid.initialize()
2. **Simplify diagrams** - Break complex flows into multiple smaller diagrams
3. **Use subgraphs** - Group related nodes to reduce layout complexity
4. **Use mmdc CLI** - Render offline with more resources: `mmdc -i file.mmd -o file.svg`
5. **Consider ELK layout** - Mermaid 11 supports ELK layout engine for complex diagrams:
   ```javascript
   mermaid.initialize({
     layout: 'elk'  // Alternative layout engine
   });
   ```

**Configuration Example:**
```javascript
mermaid.initialize({
  startOnLoad: true,
  maxTextSize: 5000000,  // 5 million characters
  maxEdges: 5000,        // 5000 edges (10x default)
  securityLevel: 'loose',
  layout: 'dagre'        // or 'elk' for complex graphs
});
```

### 2. Pan-Zoom Initialization

**Affected:** C# Project Dependencies, Namespaces, REST API, Process Execution tabs

**Symptom:** Diagram appears as thin line at bottom of viewport

**Cause:** svg-pan-zoom library miscalculates initial viewBox when Mermaid sets unusual dimensions

**Status:** Partial fix implemented - manual viewBox calculation added

### 3. Logo/Icon Not Loading

**Affected:** All pages served via local web server

**Symptom:** Logo and favicon not displayed

**Cause:** Templates reference `file://` URLs which browsers block for security

**Fix Required:** Copy `dedge.svg` and `dedge.ico` to output folder, update templates to use relative paths

---

## 📁 File Locations

### Source Files
```
C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc\
├── AutoDocBatchRunner.ps1      # Main generation script
├── Test-AutoDocGeneration.ps1  # Test wrapper script
├── autodoc-diagram-controls.js # Diagram controls (external)
├── autodoc-mermaid-config.js   # Mermaid configuration (external)
├── autodoc-shared.css          # Shared styles
├── cblmmdtemplate.html         # COBOL template
├── rexmmdtemplate.html         # REX template
├── batmmdtemplate.html         # BAT template
├── ps1mmdtemplate.html         # PS1 template
├── csharpmmdtemplate.html      # C# template
└── index.html                  # DataTables index page
```

### Output Files
```
C:\opt\Webs\AutoDoc\
├── *.html                      # Generated documentation
├── *.mmd                       # Mermaid source files
├── CblParseResult.json         # COBOL data
├── ScriptParseResult.json      # Scripts data
├── SqlParseResult.json         # SQL data
├── CSharpParseResult.json      # C# data
├── autodoc-diagram-controls.js # Copied JS
├── autodoc-mermaid-config.js   # Copied JS
└── autodoc-shared.css          # Copied CSS
```

### Server Location
```
http://dedge-server:8080/AutoDoc/
```

---

## 📈 Configuration

### Mermaid Settings
```javascript
{
  startOnLoad: true,
  theme: 'dark',              // or 'default'
  securityLevel: 'loose',
  maxTextSize: 5000000,       // 5M chars (default: 50,000)
  maxEdges: 5000,             // 5K edges (default: 500)
  themeVariables: {
    fontFamily: '"Courier New", Courier, monospace',
    fontSize: '14px',
    lineColor: '#64b5f6',
    primaryTextColor: '#f5f5f5',
    primaryColor: '#3a3a5c',
    primaryBorderColor: '#64b5f6'
  }
}
```

### C# Parser Settings
- `MaxClasses: 40` - Limits class diagram to prevent layout errors

---

## 🔧 Recent Changes

### 2026-01-23

1. **External API Callers Feature**
   - Added `SrcRootFolder` parameter to `Start-CSharpParse`
   - Added `*.rex` to file types scanned for API calls
   - Displays PS1/REX/CBL files that call REST API

2. **Class Listing Fixed**
   - Removed 50-class limit in `New-ClassListHtml`
   - All classes now displayed alphabetically

3. **JSON Append Mode**
   - `CreateJsonFileCbl`, `CreateJsonFileScript`, `CreateJsonFileSql`, `CreateJsonFileCSharp` 
   - Now append to existing files instead of overwriting
   - Duplicate detection by unique key (programName, scriptNameLink, tableNameLink, projectName)

4. **Mermaid Limits Increased**
   - `maxTextSize`: 50,000 → 5,000,000 (100x increase)
   - `maxEdges`: 500 → 5,000 (10x increase)
   - Allows larger, more complex diagrams to render

5. **Mermaid 11 Rendering Fixes**
   - Added `fixForeignObjectDimensions` - fixes 0x0 foreignObject dimensions
   - Added `fixInvalidTransforms` - fixes `translate(undefined, NaN)` errors
   - Added `fixAllForeignObjects` - applies fixes on page load and tab switch
   - Both fixes run on DOMContentLoaded with multiple retry attempts (500ms, 1s, 2s, 3s)
   - MutationObserver watches for new SVGs and applies fixes automatically

---

## 📋 Deployment

To deploy changes:
```powershell
cd C:\opt\src\DedgePsh\DevTools\LegacyCodeTools\AutoDoc
.\_deploy.ps1
```

---

## 🧪 Testing

Run full test suite:
```powershell
.\Test-AutoDocGeneration.ps1 -StartFromIndex 0
```

Test specific file type (index 0-5):
```powershell
.\Test-AutoDocGeneration.ps1 -StartFromIndex 5  # C# only
```

Test files:
| Index | Type | File |
|-------|------|------|
| 0 | CBL | AABELMA.CBL |
| 1 | REX | WKMONIT.REX |
| 2 | BAT | Catalog-All-Db2-Azure-Databases-Using-Kerberos-For-Db2Client.bat |
| 3 | PS1 | Db2-CreateInitialDatabases.ps1 |
| 4 | SQL | DBM.FAKTHIST99B |
| 5 | C# | ServerMonitor.sln |

---

## 📌 Next Steps

1. [ ] Fix logo/icon paths to use relative URLs instead of file://
2. [ ] Test ELK layout engine for complex diagrams (`layout: 'elk'`)
3. [ ] Improve pan-zoom initialization for C# pages
4. [ ] Consider splitting very large BAT diagrams into sub-diagrams
5. [ ] Add error recovery for Mermaid layout failures

---

## 📚 References

### Mermaid.js Documentation
- [Configuration Options](https://mermaid.js.org/config/schema-docs/config.html) - Full schema documentation
- [maxTextSize](https://mermaid.js.org/config/schema-docs/config.html#maxtextsize) - Default: 50,000 characters
- [maxEdges](https://mermaid.js.org/config/schema-docs/config.html#maxedges) - Default: 500 edges
- [Layout Options](https://mermaid.js.org/config/layouts.html) - dagre (default) vs ELK layout

### Key Parameters for Large Diagrams
| Parameter | Default | Recommended | Purpose |
|-----------|---------|-------------|---------|
| `maxTextSize` | 50,000 | 5,000,000 | Max diagram source characters |
| `maxEdges` | 500 | 5,000 | Max connections between nodes |
| `layout` | dagre | elk (complex) | Layout engine selection |
| `securityLevel` | strict | loose | Allow HTML in labels |
