# Quick Start Guide - VS Code Extension Development

## 🚀 Get Started in 5 Minutes

### Step 1: Install Dependencies

```bash
cd srcVSC
npm install
```

### Step 2: Compile TypeScript

```bash
npm run compile
```

### Step 3: Run the Extension

1. Open `srcVSC` folder in VS Code
2. Press `F5`
3. A new "Extension Development Host" window will open

### Step 4: Test It!

In the Extension Development Host window:

1. **Create a test SQL file** (`test.sql`):
```sql
CREATE TABLE users (
    id INT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE
);

CREATE TABLE orders (
    id INT PRIMARY KEY,
    user_id INT,
    order_date DATE,
    FOREIGN KEY (user_id) REFERENCES users(id)
);
```

2. **Right-click in the editor** → Select **"Convert SQL to Mermaid ERD"**

3. **A new `test.mmd` file** will be created automatically!

4. **Click the preview icon** (👁️) in the title bar to see the diagram

### Step 5: Test Mermaid → SQL

1. **Open the `test.mmd` file** that was just created
2. **Right-click** → Select **"Convert Mermaid ERD to SQL (Choose Dialect)"**
3. **Choose "PostgreSql"** from the dropdown
4. **A new `test_PostgreSql.sql` file** will be created!

---

## 🔧 Development Workflow

### Watch Mode (Auto-Compile)

```bash
npm run watch
```

Then press `F5` to run. Changes will auto-compile!

### Build Package

```bash
npm run package
```

This creates a `.vsix` file you can install in VS Code:

```bash
code --install-extension sqlmermaid-erd-tools-0.1.0.vsix
```

---

## ⚙️ Configuration

The extension needs either:

### Option A: Local CLI (Recommended for Development)

Install the .NET CLI tool:

```bash
cd ..
dotnet pack src/SqlMermaidErdTools.CLI/SqlMermaidErdTools.CLI.csproj
dotnet tool install -g --add-source ./nupkg SqlMermaidErdTools.CLI
```

The extension will auto-detect it!

### Option B: API Endpoint

Configure in VS Code settings (File → Preferences → Settings → Search "sqlmermaid"):

```json
{
  "sqlmermaid.apiEndpoint": "https://api.sqlmermaid.tools",
  "sqlmermaid.apiKey": "your-api-key"
}
```

### Option C: Custom CLI Path

```json
{
  "sqlmermaid.cliPath": "C:\\path\\to\\SqlMermaidErdTools.CLI.exe"
}
```

---

## 🎨 Available Commands

Open Command Palette (`Ctrl+Shift+P` or `Cmd+Shift+P`):

- `SqlMermaid: Convert SQL to Mermaid ERD`
- `SqlMermaid: Convert Mermaid ERD to SQL`
- `SqlMermaid: Convert Mermaid ERD to SQL (Choose Dialect)`
- `SqlMermaid: Preview Mermaid Diagram`

---

## 🐛 Debugging

1. Set breakpoints in TypeScript files
2. Press `F5`
3. Extension will pause at breakpoints
4. Use Debug Console to inspect variables

---

## 📦 Project Structure

```
srcVSC/
├── src/
│   ├── extension.ts              # Main entry point
│   └── services/
│       ├── conversionService.ts  # SQL ↔ Mermaid conversion
│       ├── previewService.ts     # Diagram preview
│       └── fileService.ts        # File operations
├── package.json                  # Extension manifest
├── tsconfig.json                 # TypeScript config
└── README.md                     # User docs
```

---

## ✅ What to Test

- [ ] SQL → Mermaid conversion creates `.mmd` file
- [ ] Mermaid → SQL conversion creates `.sql` file
- [ ] Dialect selection works (AnsiSql, SqlServer, PostgreSql, MySql)
- [ ] Preview shows diagram correctly
- [ ] Preview auto-updates when `.mmd` file changes
- [ ] Right-click context menu appears on `.sql` and `.mmd` files
- [ ] Output format options work (new file, clipboard, both)
- [ ] CLI auto-detection works
- [ ] Custom CLI path works
- [ ] API endpoint mode works (if configured)

---

## 🚢 Publishing

### To VS Code Marketplace

1. Create publisher: https://marketplace.visualstudio.com/manage
2. Get Personal Access Token from Azure DevOps
3. Login:
```bash
npx vsce login your-publisher-id
```
4. Publish:
```bash
npm run publish
```

### To Open VSX (for VS Code alternatives)

```bash
npx ovsx publish -p YOUR_ACCESS_TOKEN
```

---

## 📚 Next Steps

- Read [DEVELOPMENT.md](DEVELOPMENT.md) for detailed docs
- Check [VS Code Extension API](https://code.visualstudio.com/api)
- Join [VS Code Dev Community](https://aka.ms/vscode-dev-community)

---

**Happy Coding!** 🎉

