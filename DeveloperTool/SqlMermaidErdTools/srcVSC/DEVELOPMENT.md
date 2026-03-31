# Development Guide - SQL ↔ Mermaid ERD Tools Extension

## Prerequisites

- Node.js 20.x or later
- npm 10.x or later
- Visual Studio Code 1.85.0 or later
- .NET 10 SDK (for testing with local CLI)

## Setup

1. **Clone the repository**
```bash
cd srcVSC
npm install
```

2. **Compile TypeScript**
```bash
npm run compile
```

Or watch for changes:
```bash
npm run watch
```

## Development Workflow

### Running the Extension

1. Open `srcVSC` folder in VS Code
2. Press `F5` to launch Extension Development Host
3. A new VS Code window will open with the extension loaded
4. Test the extension in this new window

### Testing

1. Create a test `.sql` file:
```sql
CREATE TABLE users (
    id INT PRIMARY KEY,
    name VARCHAR(100)
);
```

2. Right-click in the editor
3. Select "Convert SQL to Mermaid ERD"
4. Verify the `.mmd` file is created correctly

### Debugging

- Set breakpoints in TypeScript files
- Use `F5` to start debugging
- Extension Development Host will pause at breakpoints
- Use Debug Console to inspect variables

### Project Structure

```
srcVSC/
├── src/
│   ├── extension.ts           # Main extension entry point
│   └── services/
│       ├── conversionService.ts  # Handles SQL ↔ Mermaid conversion
│       ├── previewService.ts     # Mermaid preview webview
│       └── fileService.ts        # File operations
├── out/                       # Compiled JavaScript (git ignored)
├── images/
│   └── icon.png              # Extension icon
├── package.json              # Extension manifest
├── tsconfig.json             # TypeScript configuration
├── .eslintrc.json            # ESLint configuration
├── .vscodeignore             # Files to exclude from package
└── README.md                 # User documentation
```

### Key Files

#### `src/extension.ts`
Main extension activation and command registration.

**Key functions:**
- `activate()`: Called when extension is activated
- `handleSqlToMermaid()`: SQL → Mermaid conversion handler
- `handleMermaidToSql()`: Mermaid → SQL conversion handler
- `handlePreviewMermaid()`: Preview handler

#### `src/services/conversionService.ts`
Handles the actual conversion logic.

**Conversion methods:**
- CLI-based (local execution)
- API-based (remote service)

**Key methods:**
- `sqlToMermaid()`: Main SQL → Mermaid entry point
- `mermaidToSql()`: Main Mermaid → SQL entry point
- `detectCli()`: Auto-detect CLI installation

#### `src/services/previewService.ts`
Manages the Mermaid preview webview panel.

**Features:**
- Live preview using Mermaid.js CDN
- Auto-refresh on file changes
- Side-by-side view

#### `src/services/fileService.ts`
File system operations.

**Methods:**
- `createMermaidFile()`: Create `.mmd` output
- `createSqlFile()`: Create `.sql` output with dialect suffix

## Building for Production

### Package the Extension

```bash
npm run package
```

This creates a `.vsix` file in the root directory.

### Install Locally

```bash
code --install-extension sqlmermaid-erd-tools-0.1.0.vsix
```

### Publish to Marketplace

1. **Create a publisher account**
   - Go to [Visual Studio Marketplace](https://marketplace.visualstudio.com/)
   - Create a publisher ID

2. **Get a Personal Access Token**
   - Go to [Azure DevOps](https://dev.azure.com/)
   - Create a PAT with `Marketplace (Publish)` scope

3. **Login to vsce**
```bash
npx vsce login your-publisher-id
```

4. **Publish**
```bash
npm run publish
```

## Configuration

### Extension Settings

Defined in `package.json` under `contributes.configuration`:

```json
"sqlmermaid.defaultDialect": {
  "type": "string",
  "enum": ["AnsiSql", "SqlServer", "PostgreSql", "MySql"],
  "default": "AnsiSql"
}
```

Users can modify in VS Code settings:
- UI: `File > Preferences > Settings` → Search "sqlmermaid"
- JSON: Add to `settings.json`

### Commands

Defined in `package.json` under `contributes.commands`:

```json
{
  "command": "sqlmermaid.sqlToMermaid",
  "title": "Convert SQL to Mermaid ERD",
  "category": "SqlMermaid"
}
```

Activated in `extension.ts`:
```typescript
vscode.commands.registerCommand('sqlmermaid.sqlToMermaid', async () => {
  await handleSqlToMermaid();
});
```

## Testing Scenarios

### 1. Local CLI Mode
- Install CLI: `dotnet tool install -g SqlMermaidErdTools.CLI`
- Extension should auto-detect and use it
- Test: Convert SQL → Mermaid → SQL

### 2. API Mode
- Configure `sqlmermaid.apiEndpoint` in settings
- Configure `sqlmermaid.apiKey`
- Extension should use API instead of CLI
- Test: Verify API calls work

### 3. Output Modes
- **New File**: Should create `.mmd` or `.sql` file
- **Clipboard**: Should copy to clipboard
- **Both**: Should do both

### 4. Multi-Dialect
- Test conversion to AnsiSql, SqlServer, PostgreSql, MySql
- Verify dialect-specific syntax

### 5. Preview
- Open `.mmd` file
- Click preview icon
- Edit file → Preview should auto-update

## Common Issues

### Issue: CLI not found
**Solution**: 
- Check CLI is installed: `dotnet tool list -g`
- Install if missing: `dotnet tool install -g SqlMermaidErdTools.CLI`
- Or configure custom path in settings

### Issue: Preview not rendering
**Solution**:
- Check browser console in webview (Developer Tools)
- Verify Mermaid syntax is valid
- Check CDN is accessible

### Issue: Conversion fails
**Solution**:
- Check extension output panel: `View > Output` → Select "SqlMermaid"
- Verify SQL/Mermaid syntax
- Check CLI/API is working

## Adding New Features

### Example: Add new command

1. **Define command in `package.json`**
```json
{
  "command": "sqlmermaid.newFeature",
  "title": "New Feature",
  "category": "SqlMermaid"
}
```

2. **Register in `extension.ts`**
```typescript
context.subscriptions.push(
  vscode.commands.registerCommand('sqlmermaid.newFeature', async () => {
    await handleNewFeature();
  })
);
```

3. **Implement handler**
```typescript
async function handleNewFeature() {
  // Implementation
}
```

## Release Process

1. Update version in `package.json`
2. Update `CHANGELOG.md`
3. Commit changes
4. Create git tag: `git tag v0.1.0`
5. Push: `git push --tags`
6. Build: `npm run package`
7. Publish: `npm run publish`

## Resources

- [VS Code Extension API](https://code.visualstudio.com/api)
- [Extension Guidelines](https://code.visualstudio.com/api/references/extension-guidelines)
- [Publishing Extensions](https://code.visualstudio.com/api/working-with-extensions/publishing-extension)
- [Webview API](https://code.visualstudio.com/api/extension-guides/webview)
- [Mermaid.js Documentation](https://mermaid.js.org/)

## Support

For questions or issues during development:
- Check the [VS Code Extension Samples](https://github.com/microsoft/vscode-extension-samples)
- Ask on [Stack Overflow](https://stackoverflow.com/questions/tagged/vscode-extensions)
- Join [VS Code Dev Slack](https://aka.ms/vscode-dev-community)

