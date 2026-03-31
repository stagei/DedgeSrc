# Switch Cursor / VS Code from PowerShell 5.1 to pwsh 7+

## Automated (recommended)

```powershell
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\AdminTools\Set-VsCodePwshDefault\Set-VsCodePwshDefault.ps1"
```

Preview without writing: add `-WhatIf`.

## Manual steps in Cursor UI

### 1. Set default terminal to pwsh

1. Open **Settings** (`Ctrl+,`)
2. Search for `terminal.integrated.defaultProfile.windows`
3. Change the dropdown from **Windows PowerShell** to **PowerShell**

### 2. Set the PowerShell extension default version

1. Search for `powershell.powerShellDefaultVersion`
2. Enter: `PowerShell 7` (must match the name registered below)

### 3. Register the pwsh path (if not auto-detected)

1. Search for `powershell.powerShellAdditionalExePaths`
2. Click **Edit in settings.json**
3. Add:

```json
"powershell.powerShellAdditionalExePaths": {
    "PowerShell 7": "C:\\Program Files\\PowerShell\\7\\pwsh.exe"
}
```

### 4. Restart Cursor

`Ctrl+Shift+P` > **Developer: Reload Window** (or close and reopen).

After restart, new terminals and the PowerShell extension language server will use pwsh 7+ by default.
