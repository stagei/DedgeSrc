# How to Instruct Cursor to Create a Windows Desktop App with Professional Installer

This guide captures the exact approach and prompts used to create the SpotConnect Manager project -- a C# .NET 10 WPF system tray application with a WiX MSI installer, wrapping a native C/C++ executable.

Use this as a template when asking Cursor to build similar projects.

---

## Project Recipe

### What Was Built

- **C# .NET 10 WPF system tray application** wrapping a native executable (`spotraop.exe`)
- **Dark-themed Spotify-inspired UI** with settings, log viewer, about window, and first-run wizard
- **WiX Toolset v6 MSI installer** with a professional installation wizard
- **Auto-start on login**, single-instance enforcement, auto-restart on crash
- **Network auto-detection**, AirPlay device discovery, contextual help system

### Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | .NET 10, WPF |
| Tray Icon | H.NotifyIcon.Wpf |
| MVVM | CommunityToolkit.Mvvm |
| Installer | WiX Toolset v6 |
| API Docs | Scalar.AspNetCore (if API needed) |
| Target OS | Windows 11 / Windows Server 2025 |

---

## The Prompts That Built This (In Order)

### Phase 1: Initial Scaffolding

> "Can we wrap the original product with credits to a new C# app that uses the existing solution, and provides a professional installation wizard?"

**Key details to include in your prompt:**
- What native executable you're wrapping
- That it should be a **system tray application** (not a Windows Service, not a console app)
- That you want a **professional MSI installer** (WiX Toolset)
- Credit/attribution text and website

### Phase 2: Branding and Assets

> "Copy and rename this image and convert it to icon and use this as app icon. Also include the image in installation and in the Windows Forms app as sensible as possible."

**Attach the image file.** Cursor will:
- Convert PNG to ICO
- Set it as the application icon
- Embed it in the installer, about window, and header areas

### Phase 3: Logging and Diagnostics

> "Create a log file you check after installation and launch and add extensive logging throughout the installation and application."

This prompt generates:
- Bootstrap log (earliest startup diagnostics)
- Application log (full lifecycle)
- Bridge/process log (native executable output)
- Log viewer window with filtering, color-coding, and live tailing

### Phase 4: Visual Theme

> "Use dark mode in the app and use black as background color."

Cursor will create a SharedStyles.xaml resource dictionary with:
- Color palette (background, surface, text, accent colors)
- Styled controls (buttons, text boxes, checkboxes, combo boxes, tabs)
- Consistent dark theme across all windows

### Phase 5: Help System and External Links

> "Add links to all external webpages that need configurations, and add help popup in the app when link is clicked to explain step by step what to do."

This generates:
- Help button (?) icons next to each setting
- Reusable HelpWindow with step-by-step instructions
- External link buttons that open browser
- Contextual documentation per feature

### Phase 6: Auto-Detection and Ease of Use

> "Make it as easy as possible to use the app, and if a network scanner can detect local units automatically, or other settings automatically, do it."

This generates:
- Network adapter scanner with smart prioritization
- First-run welcome wizard (multi-page)
- Smart defaults applied automatically
- Auto-start bridge after setup

### Phase 7: Quality Hardening

> "Fix this app during the night until you are sure it will work and is as perfect and easy as can be."

This triggers a full audit and fix cycle:
- Automated code audit of every file
- Bug fixes (race conditions, resource leaks, crash scenarios)
- Performance optimization (frozen brushes, append-only rendering, log rotation)
- UX polish (single-instance enforcement, dark-themed controls, input validation)

---

## Project Structure to Request

When starting a new project like this, ask for this structure:

```
MyProject/
  src/
    MyApp/                    # WPF application
      Assets/                 # Icons, images
      Converters/             # XAML value converters
      Models/                 # Data models
      Services/               # Business logic
        AppLogger.cs          # File logging
        AppPaths.cs           # Centralized path resolution
        ConfigManager.cs      # XML/JSON config load/save
        ProcessManager.cs     # Native process lifecycle
        AutoStartManager.cs   # Registry-based auto-start
        NetworkScanner.cs     # Network discovery
      Views/                  # WPF windows and styles
        SharedStyles.xaml     # Global dark theme
        TrayHostWindow.xaml   # Hidden tray host
        SettingsWindow.xaml   # Main settings UI
        LogWindow.xaml        # Live log viewer
        AboutWindow.xaml      # Credits and version
        FirstRunWindow.xaml   # Welcome wizard
        HelpWindow.xaml       # Contextual help
      App.xaml                # Application resources
      App.xaml.cs             # Startup, exception handling
      Program.cs              # Entry point, single-instance mutex
      MyApp.csproj            # Project file
    MyApp.Installer/          # WiX MSI installer
      Package.wxs             # Installer definition
  native/                     # Native binaries to bundle
  publish/                    # Build output
```

---

## Key Cursor Rules to Set Up

Create `.cursor/rules/` files with these conventions:

### Build and Deploy Rule

```markdown
After any code change, run the full pipeline:
1. Kill running instances
2. dotnet publish -c Release -r win-x64 --self-contained false
3. Copy to install directory (elevated)
4. Launch the app
5. Check logs after launch
```

### Technology Rule

```markdown
- Target .NET 10, WPF, Windows 11
- Use H.NotifyIcon.Wpf for system tray
- Use CommunityToolkit.Mvvm for MVVM
- Use WiX Toolset v6 for MSI installer
- Dark theme with pure black background
- Extensive logging via custom AppLogger
```

---

## Tips for Best Results

1. **Start with the wrapper concept** -- tell Cursor what native executable you're wrapping and what it does.

2. **Provide branding assets early** -- app icon, logo image, credit text, website URL.

3. **Request logging first** -- "add extensive logging throughout" makes debugging everything else much easier.

4. **Request the dark theme before adding features** -- it's easier to style new windows if the theme exists first.

5. **Ask for the first-run wizard last** -- it depends on all other features (network detection, config management, etc.) being in place.

6. **End with "fix it until it's perfect"** -- this triggers a thorough audit that catches edge cases, race conditions, and UX issues you wouldn't think to ask about.

7. **Always include the silent reinstall rule** -- having Cursor automatically rebuild, deploy, and check logs after every change saves enormous time.

8. **Attach screenshots** -- when something looks wrong, a screenshot is worth a thousand words. Cursor can take and analyze screenshots to verify UI correctness.

---

## NuGet Packages Used

```xml
<PackageReference Include="H.NotifyIcon.Wpf" Version="2.2.1" />
<PackageReference Include="CommunityToolkit.Mvvm" Version="8.4.0" />
```

For the installer (separate project):
```xml
<!-- WiX Toolset v6 via dotnet tool -->
dotnet tool install --global wix
```

---

## One-Liner to Kick Off a New Project

> "Create a C# .NET 10 WPF system tray application at `C:\opt\src\MyProject` that wraps `[native-exe-name]`. Include: professional dark-themed UI, WiX MSI installer, extensive file logging, auto-start on login, single-instance enforcement, first-run wizard with auto-detection, contextual help, and a silent reinstall build script. Credit: Created by [Name] - [website]. Use this image as the app icon: [attach image]."

That single prompt, combined with the rules above, gets you 80% of the way there. Then iterate with the phase prompts to refine.