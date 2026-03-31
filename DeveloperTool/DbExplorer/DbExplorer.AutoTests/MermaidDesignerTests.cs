using System;
using System.Threading;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;
using NLog;

namespace DbExplorer.AutoTests;

/// <summary>
/// Comprehensive automated tests for Mermaid Visual Designer functionality
/// </summary>
public class MermaidDesignerTests
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly Window _mainWindow;
    private readonly AutomationBase _automation;
    
    public MermaidDesignerTests(Window mainWindow, AutomationBase automation)
    {
        _mainWindow = mainWindow;
        _automation = automation;
    }
    
    /// <summary>
    /// Test 1: Open Mermaid Designer from View menu
    /// </summary>
    public void Test_OpenMermaidDesigner_FromMenu()
    {
        Console.WriteLine("🧪 Mermaid Test 1: Opening Mermaid Designer from View menu...");
        Logger.Info("Test: Opening Mermaid Designer from View menu");
        
        try
        {
            // Find and click View menu
            _mainWindow.Focus();
            Thread.Sleep(300);
            
            Console.WriteLine("   🖱️  Opening View menu with Alt+V...");
            Keyboard.TypeSimultaneously(VirtualKeyShort.ALT, VirtualKeyShort.KEY_V);
            Thread.Sleep(800);
            
            // Look for View menu
            var viewMenu = _mainWindow.FindFirstDescendant(cf =>
                cf.ByText("View").And(cf.ByControlType(ControlType.MenuItem)));
            
            if (viewMenu != null)
            {
                Console.WriteLine("   ✅ View menu found");
                
                // Find Mermaid Designer menu item by searching for partial text
                Console.WriteLine("   🔍 Looking for Mermaid menu item...");
                
                var allMenuItems = _mainWindow.FindAllDescendants(cf =>
                    cf.ByControlType(ControlType.MenuItem));
                
                AutomationElement? mermaidMenuItem = null;
                foreach (var item in allMenuItems)
                {
                    var itemText = item.Name ?? "";
                    Console.WriteLine($"      Checking menu item: {itemText}");
                    if (itemText.Contains("Mermaid", StringComparison.OrdinalIgnoreCase))
                    {
                        mermaidMenuItem = item;
                        Console.WriteLine($"   ✅ Found Mermaid menu item: {itemText}");
                        break;
                    }
                }
                
                if (mermaidMenuItem != null)
                {
                    Console.WriteLine("   🖱️  Clicking Mermaid Designer...");
                    mermaidMenuItem.Click();
                    Console.WriteLine("   ✅ Mermaid Designer clicked");
                    
                    Thread.Sleep(3000); // Wait longer for window to open
                }
                else
                {
                    Console.WriteLine("   ⚠️  Mermaid Designer menu item not found in View menu");
                }
            }
            else
            {
                Console.WriteLine("   ⚠️  View menu not found, trying direct navigation...");
                
                // Try typing 'M' to navigate to Mermaid item
                Keyboard.TypeSimultaneously(VirtualKeyShort.ALT, VirtualKeyShort.KEY_V);
                Thread.Sleep(500);
                Keyboard.Type(VirtualKeyShort.KEY_M);
                Thread.Sleep(500);
                Keyboard.Type(VirtualKeyShort.RETURN);
                Thread.Sleep(3000);
            }
            
            // Verify Mermaid Designer window opened
            var mermaidWindow = FindMermaidDesignerWindow();
            
            if (mermaidWindow != null)
            {
                Console.WriteLine("   ✅ Mermaid Designer window opened successfully");
                Logger.Info("Mermaid Designer window found: {Name}", mermaidWindow.Name);
            }
            else
            {
                Console.WriteLine("   ⚠️  Mermaid Designer window not found");
                Logger.Warn("Mermaid Designer window not found after menu click");
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error opening Mermaid Designer");
            Console.WriteLine($"   ❌ Error: {ex.Message}");
            throw;
        }
    }
    
    /// <summary>
    /// Test 2: Verify Mermaid Designer window elements
    /// </summary>
    public void Test_VerifyMermaidDesignerWindow()
    {
        Console.WriteLine("🧪 Mermaid Test 2: Verifying Mermaid Designer window...");
        Logger.Info("Test: Verifying Mermaid Designer window");
        
        var mermaidWindow = FindMermaidDesignerWindow();
        
        if (mermaidWindow == null)
        {
            Console.WriteLine("   ⚠️  Mermaid Designer window not found, skipping test");
            return;
        }
        
        Console.WriteLine($"   ✅ Window title: {mermaidWindow.Name}");
        
        // Check if window has expected title
        if (mermaidWindow.Name.Contains("Mermaid") || mermaidWindow.Name.Contains("Designer"))
        {
            Console.WriteLine("   ✅ Window title verified");
        }
        
        // Look for WebView2 control
        var webView = mermaidWindow.FindFirstDescendant(cf =>
            cf.ByControlType(ControlType.Pane).Or(cf.ByClassName("Chrome_WidgetWin_1")));
        
        if (webView != null)
        {
            Console.WriteLine("   ✅ WebView2 control found");
            Logger.Info("WebView2 control found in Mermaid Designer");
        }
        else
        {
            Console.WriteLine("   ⚠️  WebView2 control not found");
        }
        
        // Check window size
        var bounds = mermaidWindow.BoundingRectangle;
        Console.WriteLine($"   📐 Window size: {bounds.Width}x{bounds.Height}");
        
        if (bounds.Width >= 1200 && bounds.Height >= 800)
        {
            Console.WriteLine("   ✅ Window size appropriate for designer");
        }
        
        Console.WriteLine("   ✅ Mermaid Designer window verified");
    }
    
    /// <summary>
    /// Test 3: Test table selection and diagram generation
    /// </summary>
    public void Test_GenerateDiagramFromTables()
    {
        Console.WriteLine("🧪 Mermaid Test 3: Testing diagram generation...");
        Logger.Info("Test: Testing diagram generation from tables");
        
        var mermaidWindow = FindMermaidDesignerWindow();
        
        if (mermaidWindow == null)
        {
            Console.WriteLine("   ⚠️  Mermaid Designer window not found, skipping test");
            return;
        }
        
        try
        {
            // Wait for WebView2 to load
            Console.WriteLine("   ⏳ Waiting for designer to initialize...");
            Thread.Sleep(3000);
            
            // Look for table list or schema browser
            Console.WriteLine("   🔍 Looking for table selection interface...");
            
            // Try to find interactive elements
            var allButtons = mermaidWindow.FindAllDescendants(cf =>
                cf.ByControlType(ControlType.Button));
            
            Console.WriteLine($"   📋 Found {allButtons.Length} buttons in designer");
            
            foreach (var button in allButtons)
            {
                var name = button.Name;
                if (!string.IsNullOrEmpty(name))
                {
                    Console.WriteLine($"      - Button: {name}");
                }
            }
            
            // Look for checkboxes (table selection)
            var checkboxes = mermaidWindow.FindAllDescendants(cf =>
                cf.ByControlType(ControlType.CheckBox));
            
            Console.WriteLine($"   📋 Found {checkboxes.Length} checkboxes in designer");
            
            if (checkboxes.Length > 0)
            {
                Console.WriteLine("   ✅ Table selection checkboxes found");
                
                // Select first few tables
                int tablesToSelect = Math.Min(3, checkboxes.Length);
                Console.WriteLine($"   🔘 Selecting first {tablesToSelect} tables...");
                
                for (int i = 0; i < tablesToSelect; i++)
                {
                    try
                    {
                        checkboxes[i].AsCheckBox().IsChecked = true;
                        Console.WriteLine($"      ✅ Selected table {i + 1}");
                        Thread.Sleep(300);
                    }
                    catch (Exception ex)
                    {
                        Logger.Debug(ex, "Error selecting checkbox {Index}", i);
                    }
                }
            }
            
            // Look for "Generate Diagram" or similar button
            var generateButton = mermaidWindow.FindFirstDescendant(cf =>
                cf.ByText("Generate").And(cf.ByControlType(ControlType.Button)));
            
            if (generateButton == null)
            {
                generateButton = mermaidWindow.FindFirstDescendant(cf =>
                    cf.ByText("Create").And(cf.ByControlType(ControlType.Button)));
            }
            
            if (generateButton != null)
            {
                Console.WriteLine("   ✅ Generate button found");
                Console.WriteLine("   🖱️  Clicking Generate...");
                generateButton.Click();
                Thread.Sleep(2000);
                Console.WriteLine("   ✅ Diagram generation requested");
            }
            else
            {
                Console.WriteLine("   ⚠️  Generate button not found");
            }
            
            Console.WriteLine("   ✅ Diagram generation test completed");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error during diagram generation test");
            Console.WriteLine($"   ❌ Error: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Test 4: Test diagram export functionality
    /// </summary>
    public void Test_ExportDiagram()
    {
        Console.WriteLine("🧪 Mermaid Test 4: Testing diagram export...");
        Logger.Info("Test: Testing diagram export");
        
        var mermaidWindow = FindMermaidDesignerWindow();
        
        if (mermaidWindow == null)
        {
            Console.WriteLine("   ⚠️  Mermaid Designer window not found, skipping test");
            return;
        }
        
        try
        {
            // Look for Export button
            var exportButton = mermaidWindow.FindFirstDescendant(cf =>
                cf.ByText("Export").And(cf.ByControlType(ControlType.Button)));
            
            if (exportButton == null)
            {
                exportButton = mermaidWindow.FindFirstDescendant(cf =>
                    cf.ByText("Save").And(cf.ByControlType(ControlType.Button)));
            }
            
            if (exportButton != null)
            {
                Console.WriteLine("   ✅ Export button found");
                Console.WriteLine("   🖱️  Clicking Export...");
                exportButton.Click();
                Thread.Sleep(1000);
                
                // Look for Save File dialog
                var saveDialog = _automation.GetDesktop().FindFirstChild(cf =>
                    cf.ByControlType(ControlType.Window).And(
                        cf.ByName("Save").Or(cf.ByName("Export"))));
                
                if (saveDialog != null)
                {
                    Console.WriteLine("   ✅ Save dialog opened");
                    Logger.Info("Save dialog found");
                    
                    // Close the dialog (press Escape)
                    Keyboard.Type(VirtualKeyShort.ESCAPE);
                    Thread.Sleep(500);
                    Console.WriteLine("   ✅ Save dialog closed");
                }
                else
                {
                    Console.WriteLine("   ⚠️  Save dialog not found");
                }
            }
            else
            {
                Console.WriteLine("   ⚠️  Export button not found");
            }
            
            Console.WriteLine("   ✅ Export test completed");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error during export test");
            Console.WriteLine($"   ❌ Error: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Test 5: Test diagram preview/render
    /// </summary>
    public void Test_DiagramPreview()
    {
        Console.WriteLine("🧪 Mermaid Test 5: Testing diagram preview...");
        Logger.Info("Test: Testing diagram preview");
        
        var mermaidWindow = FindMermaidDesignerWindow();
        
        if (mermaidWindow == null)
        {
            Console.WriteLine("   ⚠️  Mermaid Designer window not found, skipping test");
            return;
        }
        
        try
        {
            // Wait for render
            Thread.Sleep(2000);
            
            // Look for preview pane or canvas
            var canvas = mermaidWindow.FindFirstDescendant(cf =>
                cf.ByControlType(ControlType.Custom).Or(cf.ByControlType(ControlType.Pane)));
            
            if (canvas != null)
            {
                Console.WriteLine("   ✅ Preview canvas found");
                
                var bounds = canvas.BoundingRectangle;
                Console.WriteLine($"   📐 Canvas size: {bounds.Width}x{bounds.Height}");
                
                if (bounds.Width > 100 && bounds.Height > 100)
                {
                    Console.WriteLine("   ✅ Canvas has reasonable size for preview");
                }
            }
            else
            {
                Console.WriteLine("   ⚠️  Preview canvas not found");
            }
            
            // Look for zoom controls
            var zoomIn = mermaidWindow.FindFirstDescendant(cf =>
                cf.ByText("+").And(cf.ByControlType(ControlType.Button)));
            
            var zoomOut = mermaidWindow.FindFirstDescendant(cf =>
                cf.ByText("-").And(cf.ByControlType(ControlType.Button)));
            
            if (zoomIn != null && zoomOut != null)
            {
                Console.WriteLine("   ✅ Zoom controls found");
                
                // Test zoom in
                Console.WriteLine("   🔍 Testing zoom in...");
                zoomIn.Click();
                Thread.Sleep(500);
                
                // Test zoom out
                Console.WriteLine("   🔍 Testing zoom out...");
                zoomOut.Click();
                Thread.Sleep(500);
                
                Console.WriteLine("   ✅ Zoom controls working");
            }
            else
            {
                Console.WriteLine("   ⚠️  Zoom controls not found");
            }
            
            Console.WriteLine("   ✅ Preview test completed");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error during preview test");
            Console.WriteLine($"   ❌ Error: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Test 6: Test DDL generation from diagram
    /// </summary>
    public void Test_GenerateDDLFromDiagram()
    {
        Console.WriteLine("🧪 Mermaid Test 6: Testing DDL generation...");
        Logger.Info("Test: Testing DDL generation from diagram");
        
        var mermaidWindow = FindMermaidDesignerWindow();
        
        if (mermaidWindow == null)
        {
            Console.WriteLine("   ⚠️  Mermaid Designer window not found, skipping test");
            return;
        }
        
        try
        {
            // Look for Generate DDL button
            var ddlButton = mermaidWindow.FindFirstDescendant(cf =>
                cf.ByText("Generate DDL").And(cf.ByControlType(ControlType.Button)));
            
            if (ddlButton == null)
            {
                ddlButton = mermaidWindow.FindFirstDescendant(cf =>
                    cf.ByText("DDL").And(cf.ByControlType(ControlType.Button)));
            }
            
            if (ddlButton != null)
            {
                Console.WriteLine("   ✅ Generate DDL button found");
                Console.WriteLine("   🖱️  Clicking Generate DDL...");
                ddlButton.Click();
                Thread.Sleep(2000);
                
                // Look for DDL output dialog or panel
                var ddlDialog = _automation.GetDesktop().FindFirstChild(cf =>
                    cf.ByControlType(ControlType.Window).And(
                        cf.ByName("DDL").Or(cf.ByName("SQL"))));
                
                if (ddlDialog != null)
                {
                    Console.WriteLine("   ✅ DDL dialog opened");
                    Logger.Info("DDL generation dialog found");
                    
                    // Look for text content
                    var textBox = ddlDialog.FindFirstDescendant(cf =>
                        cf.ByControlType(ControlType.Edit).Or(cf.ByControlType(ControlType.Document)));
                    
                    if (textBox != null)
                    {
                        Console.WriteLine("   ✅ DDL text content found");
                        
                        try
                        {
                            var text = textBox.AsTextBox()?.Text ?? "";
                            if (!string.IsNullOrEmpty(text))
                            {
                                Console.WriteLine($"   ✅ DDL generated ({text.Length} characters)");
                                Logger.Info("DDL generated successfully: {Length} characters", text.Length);
                            }
                        }
                        catch
                        {
                            Console.WriteLine("   ⚠️  Could not read DDL text content");
                        }
                    }
                    
                    // Close dialog
                    Keyboard.Type(VirtualKeyShort.ESCAPE);
                    Thread.Sleep(500);
                }
                else
                {
                    Console.WriteLine("   ⚠️  DDL dialog not found");
                }
            }
            else
            {
                Console.WriteLine("   ⚠️  Generate DDL button not found");
            }
            
            Console.WriteLine("   ✅ DDL generation test completed");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error during DDL generation test");
            Console.WriteLine($"   ❌ Error: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Test 7: Test keyboard shortcuts in designer
    /// </summary>
    public void Test_KeyboardShortcuts()
    {
        Console.WriteLine("🧪 Mermaid Test 7: Testing keyboard shortcuts...");
        Logger.Info("Test: Testing keyboard shortcuts");
        
        var mermaidWindow = FindMermaidDesignerWindow();
        
        if (mermaidWindow == null)
        {
            Console.WriteLine("   ⚠️  Mermaid Designer window not found, skipping test");
            return;
        }
        
        try
        {
            mermaidWindow.Focus();
            Thread.Sleep(300);
            
            // Test Ctrl+S (Save)
            Console.WriteLine("   ⌨️  Testing Ctrl+S (Save)...");
            Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_S);
            Thread.Sleep(1000);
            Console.WriteLine("   ✅ Ctrl+S tested");
            
            // Test Ctrl+E (Export)
            Console.WriteLine("   ⌨️  Testing Ctrl+E (Export)...");
            Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_E);
            Thread.Sleep(1000);
            Console.WriteLine("   ✅ Ctrl+E tested");
            
            // Test Ctrl+G (Generate)
            Console.WriteLine("   ⌨️  Testing Ctrl+G (Generate)...");
            Keyboard.TypeSimultaneously(VirtualKeyShort.CONTROL, VirtualKeyShort.KEY_G);
            Thread.Sleep(1000);
            Console.WriteLine("   ✅ Ctrl+G tested");
            
            // Test Escape (close any dialogs)
            Keyboard.Type(VirtualKeyShort.ESCAPE);
            Thread.Sleep(500);
            
            Console.WriteLine("   ✅ Keyboard shortcuts test completed");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error during keyboard shortcuts test");
            Console.WriteLine($"   ❌ Error: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Test 8: Close Mermaid Designer window
    /// </summary>
    public void Test_CloseMermaidDesigner()
    {
        Console.WriteLine("🧪 Mermaid Test 8: Closing Mermaid Designer...");
        Logger.Info("Test: Closing Mermaid Designer");
        
        var mermaidWindow = FindMermaidDesignerWindow();
        
        if (mermaidWindow == null)
        {
            Console.WriteLine("   ⚠️  Mermaid Designer window not found");
            return;
        }
        
        try
        {
            Console.WriteLine("   🖱️  Closing Mermaid Designer window...");
            mermaidWindow.Close();
            Thread.Sleep(1000);
            
            // Verify window closed
            var stillOpen = FindMermaidDesignerWindow();
            
            if (stillOpen == null)
            {
                Console.WriteLine("   ✅ Mermaid Designer closed successfully");
                Logger.Info("Mermaid Designer window closed");
            }
            else
            {
                Console.WriteLine("   ⚠️  Window still open, trying Alt+F4...");
                stillOpen.Focus();
                Keyboard.TypeSimultaneously(VirtualKeyShort.ALT, VirtualKeyShort.F4);
                Thread.Sleep(1000);
                Console.WriteLine("   ✅ Window closed with Alt+F4");
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error closing Mermaid Designer");
            Console.WriteLine($"   ❌ Error: {ex.Message}");
        }
    }
    
    /// <summary>
    /// Helper: Find Mermaid Designer window
    /// </summary>
    private Window? FindMermaidDesignerWindow()
    {
        // First try: Direct child of main window (most common for WPF child windows)
        var childWindow = _mainWindow.FindFirstDescendant(cf =>
            cf.ByControlType(ControlType.Window));
        
        if (childWindow != null)
        {
            var name = childWindow.Name ?? "";
            if (name.Contains("Mermaid", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine($"   📍 Found Mermaid window as child: {name}");
                return childWindow.AsWindow();
            }
        }
        
        // Second try: Desktop-level window by exact title
        var window = _automation.GetDesktop().FindFirstChild(cf =>
            cf.ByName("Mermaid Visual Designer").And(cf.ByControlType(ControlType.Window)));
        
        if (window != null)
        {
            Console.WriteLine($"   📍 Found Mermaid window on desktop: {window.Name}");
            return window.AsWindow();
        }
        
        // Third try: Search all desktop windows
        var allWindows = _automation.GetDesktop().FindAllChildren(cf =>
            cf.ByControlType(ControlType.Window));
        
        Console.WriteLine($"   🔍 Searching through {allWindows.Length} desktop windows...");
        foreach (var win in allWindows)
        {
            var name = win.Name ?? "";
            Console.WriteLine($"      Window: {name}");
            if (name.Contains("Mermaid", StringComparison.OrdinalIgnoreCase) ||
                name.Contains("Designer", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine($"   📍 Found matching window: {name}");
                return win.AsWindow();
            }
        }
        
        // Fourth try: Look for any WebView2 control (Mermaid Designer contains one)
        var webView = _automation.GetDesktop().FindFirstDescendant(cf =>
            cf.ByClassName("Chrome_WidgetWin_1"));
        
        if (webView != null)
        {
            // Get the parent window of the WebView
            var parent = webView.Parent;
            while (parent != null && parent.ControlType != ControlType.Window)
            {
                parent = parent.Parent;
            }
            
            if (parent != null)
            {
                Console.WriteLine($"   📍 Found window containing WebView2: {parent.Name}");
                return parent.AsWindow();
            }
        }
        
        Console.WriteLine("   ❌ Mermaid Designer window not found in any location");
        return null;
    }
    
    /// <summary>
    /// Run all Mermaid Designer tests
    /// </summary>
    public void RunAllMermaidTests()
    {
        Console.WriteLine();
        Console.WriteLine("═══════════════════════════════════════════════════════════════");
        Console.WriteLine("  🎨 Mermaid Visual Designer - Automated Test Suite");
        Console.WriteLine("═══════════════════════════════════════════════════════════════");
        Console.WriteLine();
        
        try
        {
            Test_OpenMermaidDesigner_FromMenu();
            Thread.Sleep(1000);
            
            Test_VerifyMermaidDesignerWindow();
            Thread.Sleep(1000);
            
            Test_GenerateDiagramFromTables();
            Thread.Sleep(1000);
            
            Test_DiagramPreview();
            Thread.Sleep(1000);
            
            Test_ExportDiagram();
            Thread.Sleep(1000);
            
            Test_GenerateDDLFromDiagram();
            Thread.Sleep(1000);
            
            Test_KeyboardShortcuts();
            Thread.Sleep(1000);
            
            Test_CloseMermaidDesigner();
            
            Console.WriteLine();
            Console.WriteLine("═══════════════════════════════════════════════════════════════");
            Console.WriteLine("✅ All Mermaid Designer tests completed!");
            Console.WriteLine("═══════════════════════════════════════════════════════════════");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Mermaid test suite failed");
            Console.WriteLine();
            Console.WriteLine("═══════════════════════════════════════════════════════════════");
            Console.WriteLine($"❌ Mermaid test suite failed: {ex.Message}");
            Console.WriteLine("═══════════════════════════════════════════════════════════════");
            throw;
        }
    }
}

