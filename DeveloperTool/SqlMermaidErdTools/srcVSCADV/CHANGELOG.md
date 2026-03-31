# Change Log

All notable changes to the "SQL ↔ Mermaid ERD Tools (Advanced)" extension will be documented in this file.

## [1.0.0] - 2025-12-01

### 🎉 Initial Release - Advanced Split-View Editor

#### Major Features

**Split-View Editor**
- Custom editor with professional split-view layout
- Left panel: Edit SQL or Mermaid code
- Right panel: Real-time converted output
- Integrated live Mermaid diagram preview
- Resizable splitter between panels

**Real-Time Conversion**
- Auto-convert as you type with configurable debounce (default: 500ms)
- Manual conversion with Convert button (`Ctrl+Enter`)
- Conversion timing display in status bar
- Comprehensive error messages with stack traces

**Mode Switching**
- Toggle between SQL → Mermaid and Mermaid → SQL
- Keyboard shortcut: `Ctrl+M`
- Mode indicator in toolbar
- Smart UI adaptation based on current mode

**Multi-Dialect Support**
- ANSI SQL (Standard)
- Microsoft SQL Server (T-SQL)
- PostgreSQL
- MySQL
- Dropdown selector in toolbar

**Live Preview**
- Real-time Mermaid diagram rendering using Mermaid.js v10
- Toggle preview panel visibility
- Beautiful diagram rendering in white background
- Error display for invalid diagrams

**Professional UI**
- VS Code-integrated dark theme
- Custom toolbar with icon buttons
- Status bar with conversion metrics
- Line counter
- Smooth animations and transitions
- Responsive layout

#### Additional Features

**Editor Features**
- Syntax-aware code editing
- Auto-save support (`Ctrl+S`)
- Copy to clipboard functionality
- Line counting and metrics
- Placeholder text

**Configuration**
- `sqlmermaid.defaultDialect`: Default SQL dialect
- `sqlmermaid.autoConvert`: Enable/disable auto-conversion
- `sqlmermaid.showPreview`: Show/hide preview panel
- `sqlmermaid.conversionDelay`: Debounce delay (ms)
- `sqlmermaid.cliPath`: Custom CLI path
- `sqlmermaid.apiEndpoint`: Custom API endpoint
- `sqlmermaid.apiKey`: API key for cloud service

**Keyboard Shortcuts**
- `Ctrl+S`: Save file
- `Ctrl+Enter`: Convert now
- `Ctrl+M`: Toggle SQL ↔ Mermaid mode

**Context Menu Integration**
- "Open in SQL ↔ Mermaid Split Editor" in file explorer
- "Open in SQL ↔ Mermaid Split Editor" in editor title
- Set as default editor for `.sql` and `.mmd` files

#### Technical Highlights

- Custom TextEditor provider with webview
- State management between extension and webview
- CSP-compliant HTML with nonce
- Message passing between extension and webview
- Auto-detection of file type (SQL vs. Mermaid)
- Mermaid.js CDN integration
- Professional CSS with VS Code theming

#### Supported File Types

- `.sql` - SQL DDL files
- `.mmd` - Mermaid diagram files
- `.mermaid` - Mermaid diagram files (alternate extension)

### Known Issues

- Very large schemas (>100 tables) may render slowly in preview
- Some complex SQL features may not convert perfectly
- Preview requires internet connection for Mermaid.js CDN

---

## [Unreleased]

### Planned Features

- **Offline mode**: Bundle Mermaid.js for offline use
- **Export diagrams**: Save as PNG, SVG, PDF
- **Database connection**: Import schema directly from live database
- **Schema comparison**: Visual diff between two schemas
- **Batch conversion**: Convert multiple files at once
- **Custom themes**: User-defined color schemes for diagrams
- **Syntax highlighting**: Code highlighting in editors
- **Code snippets**: Quick templates for common patterns
- **Schema validation**: Lint and validate SQL/Mermaid
- **Version history**: Track schema changes over time
- **Collaboration**: Share schemas with team members
- **AI assistant**: Suggest schema improvements

---

## Version History

- **1.0.0**: Initial release with advanced split-view editor
- **0.1.0** (Basic Edition): Command-based conversions only

---

## Comparison: Advanced vs. Basic Edition

| Feature | Basic (0.1.0) | Advanced (1.0.0) |
|---------|---------------|-------------------|
| SQL ↔ Mermaid conversion | ✅ | ✅ |
| Command-based | ✅ | ✅ |
| Split-view editor | ❌ | ✅ |
| Live preview | Separate panel | Integrated |
| Auto-convert | ❌ | ✅ |
| Mode toggle | ❌ | ✅ |
| Professional UI | Basic | Advanced |
| Real-time sync | ❌ | ✅ |

---

Made with ❤️ for database developers and technical writers
