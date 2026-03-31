# Guide to Increasing Spacing in Cursor Explorer

## Introduction

Cursor's file explorer provides a compact view of your project files by default. However, you may want to increase the spacing between items for better readability or to accommodate touch interactions. This guide explains various methods to customize the spacing in Cursor's explorer interface.

## Method 1: Using Settings

### Adjusting Line Height

1. Open Cursor
2. Go to **File > Preferences > Settings** (or use the keyboard shortcut `Ctrl+,` on Windows/Linux, `Cmd+,` on Mac)
3. Search for "tree indent" or "explorer"
4. Look for the following settings:
   - `workbench.tree.indent`: Controls the indentation of items in the explorer (default is usually 8px)
   - `workbench.tree.renderIndentGuides`: Controls whether to show indent guides
   - `explorer.compactFolders`: When enabled, folders are shown in a more compact form

5. To increase spacing between items, you can modify these settings:
   ```json
   "workbench.tree.indent": 16,
   "explorer.compactFolders": false
   ```

### Adjusting Font Size

Increasing the font size will also increase the overall spacing:

1. In Settings, search for "explorer font"
2. Look for:
   - `editor.fontSize`: Controls the font size in pixels
   - `window.zoomLevel`: Controls the overall zoom of the UI

3. Example configuration:
   ```json
   "editor.fontSize": 14,
   "window.zoomLevel": 1
   ```

## Method 2: Custom CSS (Advanced)

For more precise control over spacing, you can use custom CSS:

1. Install the "Custom CSS and JS Loader" extension from the marketplace
2. Create a CSS file in a location of your choice (e.g., `~/.cursor/custom.css`)
3. Add CSS rules to increase spacing:

```css
/* Increase spacing in the explorer */
.monaco-list-row {
  padding-top: 4px !important;
  padding-bottom: 4px !important;
  line-height: 1.5 !important;
}

/* Increase indent for tree items */
.monaco-tl-indent {
  width: 16px !important;
}

/* Increase icon size */
.monaco-icon-label:before {
  font-size: 16px !important;
}
```

4. Configure the extension to use your CSS file:
   ```json
   "vscode_custom_css.imports": [
     "file:///absolute/path/to/your/custom.css"
   ]
   ```
5. Restart Cursor and run the "Reload Custom CSS and JS" command

## Method 3: Accessibility Features

Cursor inherits many accessibility features from VS Code:

1. Go to **View > Appearance**
2. Try options like:
   - **Zoom In** (`Ctrl++` or `Cmd++`)
   - **Zoom Out** (`Ctrl+-` or `Cmd+-`)

3. You can also try the UI Accessibility settings:
   ```json
   "editor.accessibilitySupport": "on",
   "workbench.list.automaticKeyboardNavigation": false
   ```

## Method 4: Using Themes with Larger Spacing

Some themes are designed with larger spacing by default:

1. Go to **File > Preferences > Color Theme**
2. Look for themes that mention "accessibility" or "large" in their descriptions
3. Popular options include:
   - GitHub Theme
   - Winter is Coming
   - Atom One Dark

## Troubleshooting

If your spacing changes aren't taking effect:

1. **Reload Cursor**: Sometimes changes require a full reload (`Ctrl+R` or `Cmd+R`)
2. **Check for Conflicts**: Other extensions might override your spacing settings
3. **Reset to Default**: If things go wrong, you can reset to default with:
   ```json
   "workbench.tree.indent": 8,
   "editor.fontSize": 12,
   "window.zoomLevel": 0
   ```

## Additional Tips

- **File Nesting**: Enable file nesting to reduce clutter in the explorer:
  ```json
  "explorer.fileNesting.enabled": true,
  "explorer.fileNesting.expand": false
  ```

- **Custom Explorer Sorting**: Customize how files are sorted:
  ```json
  "explorer.sortOrder": "type",
  "explorer.sortOrderLexicographicOptions": "unicode"
  ```

- **Icons**: Install an icon theme like "Material Icon Theme" for better visual distinction between files

## Conclusion

By adjusting these settings, you can customize the Cursor explorer to have the spacing that works best for your workflow and visual preferences. Start with the simple settings adjustments before moving to more advanced CSS customizations. 