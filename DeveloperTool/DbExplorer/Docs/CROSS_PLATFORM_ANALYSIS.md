# Cross-Platform Analysis - DbExplorer

**Date:** November 20, 2025  
**Question:** Can this app be compiled to run on macOS and Linux?  
**Short Answer:** ❌ **Not currently** - but ✅ **possible with significant refactoring**

---

## 🚫 CURRENT STATE: Windows-Only

### Why It's Windows-Only:

**1. WPF (Windows Presentation Foundation)**
- ❌ **WPF is Windows-only** - Does NOT run on macOS or Linux
- `<UseWPF>true</UseWPF>` in project file
- WPF is a Windows-native UI framework from Microsoft
- All XAML files (MainWindow.xaml, dialogs, controls) use WPF

**2. Target Framework**
- `<TargetFramework>net10.0-windows</TargetFramework>`
- The `-windows` suffix means Windows-specific APIs are available
- Cannot run on other operating systems

**3. Windows-Only Dependencies:**

| Package | Status | Platform Support |
|---------|--------|------------------|
| **ModernWpfUI** | ❌ Windows-only | WPF-based, no cross-platform |
| **Microsoft.Web.WebView2** | ❌ Windows-only | Microsoft Edge WebView2 (Windows) |
| **AvalonEdit** | ⚠️ WPF-dependent | Has WPF dependencies, limited cross-platform |
| **System.Windows.Forms** | ❌ Windows-only | Windows Forms (legacy Windows UI) |
| **Net.IBM.Data.Db2** | ✅ Cross-platform | **Works on Windows, Linux, macOS!** |
| **NLog** | ✅ Cross-platform | **Works everywhere** |
| **PoorMansTSQLFormatter** | ✅ Cross-platform | Pure .NET, platform-agnostic |
| **Microsoft.Extensions.*** | ✅ Cross-platform | Standard .NET libraries |

**4. Windows-Specific Features:**
- DPI awareness manifest (`app.manifest`)
- Windows Data Protection API (DPAPI) for password encryption
- Windows-specific file paths and conventions

---

## ✅ GOOD NEWS: Database Layer is Cross-Platform!

### What Already Works Cross-Platform:

**1. DB2 Connectivity** ✅
- `Net.IBM.Data.Db2 9.0.0.400` **fully supports Linux and macOS**
- No external IBM DB2 Client installation required
- Native connectivity on all platforms
- All SYSCAT queries will work unchanged

**2. Business Logic** ✅
- All service classes (ObjectBrowserService, MetadataLoaderService, etc.)
- All model classes
- SQL query execution
- Data export functionality
- NLog logging

**3. .NET 10** ✅
- .NET 10 is fully cross-platform
- Works on Windows, macOS, and Linux (x64, ARM64)
- Same runtime everywhere

---

## 🔄 CROSS-PLATFORM OPTIONS

### Option 1: Avalonia UI (RECOMMENDED) ⭐

**What is Avalonia?**
- Open-source, cross-platform XAML-based UI framework
- Very similar to WPF (uses XAML)
- Runs on Windows, macOS, Linux, iOS, Android, WebAssembly
- Excellent WPF migration path

**Pros:**
- ✅ XAML syntax nearly identical to WPF
- ✅ Can reuse ~70% of XAML code with modifications
- ✅ Can reuse 100% of business logic (services, models)
- ✅ Active development, good community
- ✅ Modern styling (Fluent, Material Design)
- ✅ Good performance on all platforms

**Cons:**
- ⚠️ Not 100% WPF-compatible (some differences)
- ⚠️ No direct ModernWpfUI equivalent (would use Avalonia.Themes.Fluent)
- ⚠️ WebView2 replacement needed (use Avalonia.Browser or native WebView)
- ⚠️ AvalonEdit replacement needed (AvaloniaEdit exists!)

**Effort Estimate:**
- **High:** 200-300 hours (3-4 weeks full-time)
- Rewrite all XAML files for Avalonia
- Replace ModernWpfUI with Avalonia.Themes.Fluent
- Replace WebView2 with cross-platform WebView
- Replace System.Windows.Forms dependencies
- Test on all three platforms

**Package Replacements:**
```xml
<!-- Remove -->
<UseWPF>true</UseWPF>
<PackageReference Include="ModernWpfUI" Version="0.9.6" />
<PackageReference Include="AvalonEdit" Version="6.3.1.120" />
<PackageReference Include="Microsoft.Web.WebView2" Version="1.0.2535.41" />

<!-- Add -->
<PackageReference Include="Avalonia" Version="11.1.0" />
<PackageReference Include="Avalonia.Desktop" Version="11.1.0" />
<PackageReference Include="Avalonia.Themes.Fluent" Version="11.1.0" />
<PackageReference Include="AvaloniaEdit" Version="11.1.0" />
<PackageReference Include="Avalonia.HtmlRenderer" Version="11.1.0" />
```

---

### Option 2: .NET MAUI (Multi-platform App UI)

**What is MAUI?**
- Microsoft's official cross-platform framework
- Successor to Xamarin
- Runs on Windows, macOS, iOS, Android
- Linux support limited (community projects)

**Pros:**
- ✅ Official Microsoft support
- ✅ Good documentation
- ✅ Can reuse business logic 100%
- ✅ Modern UI controls
- ✅ Blazor Hybrid option (HTML/CSS for UI)

**Cons:**
- ❌ **Limited Linux support** (major drawback for this use case)
- ❌ Very different from WPF (different XAML dialect)
- ❌ Would require complete UI rewrite
- ❌ Desktop support is secondary focus (mobile-first)

**Effort Estimate:**
- **Very High:** 300-400 hours (4-5 weeks full-time)
- Complete UI rewrite in MAUI XAML
- Different control paradigms
- Test on Windows and macOS only (Linux problematic)

**Recommendation:** ❌ **Not ideal** for desktop-focused DB2 tool

---

### Option 3: Electron + Web Tech (Blazor or React)

**What is Electron?**
- Cross-platform desktop framework using web technologies
- Used by VS Code, Slack, Discord
- Would require complete rewrite

**Pros:**
- ✅ Perfect cross-platform support
- ✅ Modern web UI (HTML/CSS/JavaScript)
- ✅ Can use Monaco Editor (VS Code's editor)
- ✅ Good tooling and debugging

**Cons:**
- ❌ **Complete rewrite** - no code reuse from WPF
- ❌ Large application size
- ❌ Performance overhead
- ❌ Different programming paradigm

**Effort Estimate:**
- **Extremely High:** 500+ hours (6-8 weeks full-time)
- Rewrite everything from scratch
- Would be a new application, not a port

**Recommendation:** ❌ **Not worth it** - too much effort

---

### Option 4: Keep Windows, Create Separate Linux/Mac CLI Tool

**Hybrid Approach:**
- Keep WPF app for Windows users
- Create separate cross-platform CLI tool for Linux/macOS
- Share all business logic (services, models)

**Pros:**
- ✅ Minimal changes to existing Windows app
- ✅ Quick to implement CLI tool
- ✅ Business logic reuse 100%
- ✅ Linux/macOS users get DB2 access

**Cons:**
- ⚠️ Two separate codebases to maintain
- ⚠️ No GUI for Linux/macOS users
- ⚠️ Feature parity challenges

**Effort Estimate:**
- **Low:** 40-60 hours (1 week)
- Create new Console project
- Wire up CLI commands to existing services
- Package for Linux/macOS

---

## 📊 COMPARISON MATRIX

| Option | Effort | Code Reuse | Windows | macOS | Linux | Recommended |
|--------|--------|------------|---------|-------|-------|-------------|
| **Keep WPF** | None | 100% | ✅ | ❌ | ❌ | Current state |
| **Avalonia UI** | High | ~70% | ✅ | ✅ | ✅ | ⭐ **Best** |
| **.NET MAUI** | Very High | ~30% | ✅ | ✅ | ⚠️ Limited | Not ideal |
| **Electron** | Extreme | ~10% | ✅ | ✅ | ✅ | Overkill |
| **Hybrid (GUI+CLI)** | Low | 100% | ✅ (GUI) | ✅ (CLI) | ✅ (CLI) | Quick option |

---

## 🎯 RECOMMENDATION

### If Cross-Platform is Required: **Avalonia UI** ⭐

**Why:**
1. Most similar to WPF - easiest migration path
2. Good XAML reuse (~70% with modifications)
3. 100% business logic reuse
4. True cross-platform (Windows, macOS, Linux)
5. Active community and good documentation
6. Modern UI capabilities

**Migration Strategy:**
1. **Phase 1:** Create new Avalonia project structure
2. **Phase 2:** Move all business logic (Services, Models, Data) - **no changes needed**
3. **Phase 3:** Convert XAML files one-by-one
   - MainWindow
   - Dialogs
   - Controls
4. **Phase 4:** Replace platform-specific components
   - ModernWpfUI → Avalonia.Themes.Fluent
   - WebView2 → Avalonia.Browser
   - AvalonEdit → AvaloniaEdit
   - DPAPI → Cross-platform encryption (System.Security.Cryptography)
5. **Phase 5:** Test on all three platforms
6. **Phase 6:** Package for distribution

**Estimated Timeline:**
- 3-4 weeks full-time development
- 1 week testing and polish
- **Total: 4-5 weeks**

---

### If Cross-Platform is NOT Required: **Keep WPF** ✅

**Why:**
1. Already works perfectly on Windows
2. No migration effort
3. Best Windows-native experience
4. All features implemented and tested
5. DPI awareness and modern Windows features

**When to Keep WPF:**
- Organization is Windows-only
- DB2 databases are on Windows servers
- Users are on Windows workstations
- No immediate need for macOS/Linux support

---

## 🛠️ TECHNICAL DETAILS: Avalonia Migration

### Project File Changes:
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <!-- Change this: -->
    <TargetFramework>net10.0</TargetFramework>  <!-- Remove -windows -->
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <!-- Remove: <UseWPF>true</UseWPF> -->
  </PropertyGroup>

  <ItemGroup>
    <!-- Avalonia packages -->
    <PackageReference Include="Avalonia" Version="11.1.0" />
    <PackageReference Include="Avalonia.Desktop" Version="11.1.0" />
    <PackageReference Include="Avalonia.Themes.Fluent" Version="11.1.0" />
    <PackageReference Include="AvaloniaEdit" Version="11.1.0" />
    
    <!-- Keep these - they're cross-platform -->
    <PackageReference Include="Net.IBM.Data.Db2" Version="9.0.0.400" />
    <PackageReference Include="NLog" Version="6.0.6" />
    <PackageReference Include="PoorMansTSQLFormatter" Version="1.4.3.1" />
    <PackageReference Include="Microsoft.Extensions.*" />
  </ItemGroup>
</Project>
```

### XAML Differences (Example):

**WPF XAML:**
```xml
<Window x:Class="DbExplorer.MainWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:ui="http://schemas.modernwpf.com/2019"
        Title="DbExplorer">
    <ui:ModernWindow>
        <Grid>
            <Button Content="Click Me" />
        </Grid>
    </ui:ModernWindow>
</Window>
```

**Avalonia XAML:**
```xml
<Window x:Class="DbExplorer.MainWindow"
        xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DbExplorer">
    <Grid>
        <Button Content="Click Me" />
    </Grid>
</Window>
```

**Changes:**
- Different XML namespace
- No ModernWpfUI (use Fluent theme)
- Most controls same names
- Some property differences

---

## 💰 COST-BENEFIT ANALYSIS

### Cost of Staying Windows-Only:
- ✅ No development cost
- ❌ Cannot support macOS/Linux users
- ❌ Limited to Windows infrastructure

### Cost of Going Cross-Platform (Avalonia):
- ❌ 4-5 weeks development time
- ❌ Testing on multiple platforms
- ❌ Additional support complexity
- ✅ Can support all users regardless of OS
- ✅ Future-proof
- ✅ Larger potential user base

---

## 📋 DECISION CHECKLIST

**Consider Cross-Platform If:**
- [ ] You have users on macOS or Linux
- [ ] DB2 databases run on Linux servers
- [ ] Organization uses mixed OS environments
- [ ] Want to future-proof the application
- [ ] Can dedicate 4-5 weeks for migration

**Stay Windows-Only If:**
- [x] All users are on Windows (current assumption)
- [x] DB2 is on Windows servers
- [x] Organization is Windows-standardized
- [x] Need to deliver features now, not port
- [x] Have Windows-specific requirements (DPAPI, etc.)

---

## 🚀 NEXT STEPS

### If You Want Cross-Platform:
1. **Evaluate:** Test Avalonia with a small prototype
2. **Plan:** Create detailed migration plan
3. **Prototype:** Convert one dialog to Avalonia as proof-of-concept
4. **Migrate:** Follow phased migration strategy
5. **Test:** Comprehensive testing on Windows, macOS, Linux
6. **Deploy:** Package for all platforms

### If Staying Windows-Only:
1. **Continue:** Keep building features in WPF
2. **Document:** Note architecture decision (Windows-only)
3. **Consider:** Optional CLI tool for Linux/macOS users
4. **Review:** Revisit decision in 6-12 months

---

## 📝 SUMMARY

**Current State:**
- ❌ **Cannot run on macOS or Linux** - WPF is Windows-only
- ✅ Database layer (Net.IBM.Data.Db2) is already cross-platform
- ✅ Business logic is platform-agnostic

**Best Cross-Platform Option:**
- ⭐ **Avalonia UI** - 4-5 weeks effort, true cross-platform
- ~70% XAML reuse, 100% business logic reuse
- Works on Windows, macOS, Linux

**Recommendation:**
- **If cross-platform is needed:** Migrate to Avalonia UI
- **If Windows-only is acceptable:** Keep current WPF implementation
- **Quick hybrid option:** Add CLI tool for Linux/macOS (1 week)

---

**Status:** Analysis complete - decision needed based on requirements  
**Key Takeaway:** Technically feasible with Avalonia UI, but requires significant effort (4-5 weeks)

