using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.UIA3;
using NLog;

namespace DbExplorer.AutoTests;

/// <summary>
/// Functional tests for Mermaid Designer - verify actual end-to-end workflows
/// Tests what ACTUALLY works, not just what code exists
/// </summary>
public class MermaidDesignerFunctionalTests
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly Application _app;
    private readonly AutomationBase _automation;
    private Window? _mainWindow;
    
    public MermaidDesignerFunctionalTests(Application app, AutomationBase automation)
    {
        _app = app;
        _automation = automation;
    }
    
    /// <summary>
    /// TEST 1: Verify "Load from DB" button actually works
    /// </summary>
    public bool Test_LoadFromDB_ActuallyWorks()
    {
        Logger.Info("═══════════════════════════════════════════════");
        Logger.Info("TEST 1: Load from DB - End-to-End Verification");
        Logger.Info("═══════════════════════════════════════════════");
        
        try
        {
            // Step 1: Open Mermaid Designer from menu
            Logger.Info("Step 1: Opening Mermaid Designer via View menu");
            
            _mainWindow = _app.GetMainWindow(_automation);
            if (_mainWindow == null)
            {
                Logger.Error("Main window not found");
                return false;
            }
            
            // Find View menu
            var menuBar = _mainWindow.FindFirstDescendant(cf => cf.ByControlType(ControlType.MenuBar));
            if (menuBar == null)
            {
                Logger.Error("Menu bar not found");
                return false;
            }
            
            var viewMenu = menuBar.FindFirstDescendant(cf => cf.ByName("View"));
            if (viewMenu == null)
            {
                Logger.Error("View menu not found");
                return false;
            }
            
            viewMenu.Click();
            Thread.Sleep(500);
            
            var mermaidMenuItem = viewMenu.FindFirstDescendant(cf => cf.ByName("Mermaid Visual Designer").Or(cf.ByName("Mermaid Designer")));
            if (mermaidMenuItem == null)
            {
                Logger.Error("Mermaid Designer menu item not found");
                return false;
            }
            
            Logger.Info("Clicking 'Mermaid Visual Designer' menu item");
            mermaidMenuItem.Click();
            Thread.Sleep(5000); // Wait for Mermaid Designer window + WebView2
            
            // Step 2: Find Mermaid Designer window
            Logger.Info("Step 2: Looking for Mermaid Designer window");
            
            var mermaidWindow = _app.GetAllTopLevelWindows(_automation)
                .FirstOrDefault(w => w.Name.Contains("Mermaid", StringComparison.OrdinalIgnoreCase));
            
            if (mermaidWindow == null)
            {
                Logger.Error("Mermaid Designer window not found");
                return false;
            }
            
            Logger.Info("✅ Mermaid Designer window opened: {Title}", mermaidWindow.Name);
            
            // Step 3: Find "Load from DB" button
            Logger.Info("Step 3: Looking for 'Load from DB' button");
            
            // WebView2 controls are tricky - buttons are inside the WebView
            // We need to look for the WebView2 control first
            var webView = mermaidWindow.FindFirstDescendant(cf => cf.ByClassName("Chrome_RenderWidgetHostHWND")
                .Or(cf.ByControlType(ControlType.Pane)));
            
            if (webView == null)
            {
                Logger.Warn("WebView2 control not found directly - Mermaid Designer uses embedded web content");
                Logger.Info("✅ TEST PARTIAL: Mermaid window opened, but cannot interact with WebView2 buttons via FlaUI");
                Logger.Info("   Reason: WebView2 content is HTML/JavaScript, not native WPF controls");
                Logger.Info("   Alternative: Use JavaScript injection or Selenium for WebView2 testing");
                mermaidWindow.Close();
                return false; // Partial success
            }
            
            // If we found WebView, try to find button (unlikely to work)
            var loadButton = webView.FindFirstDescendant(cf => cf.ByName("Load from DB").Or(cf.ByName("🔽 Load from DB")));
            
            if (loadButton == null)
            {
                Logger.Warn("Load from DB button not accessible via FlaUI (expected with WebView2)");
                Logger.Info("✅ TEST PARTIAL: Mermaid Designer opened successfully");
                Logger.Info("   ⚠️  Cannot test WebView2 button interactions with FlaUI");
                Logger.Info("   ℹ️  WebView2 content requires JavaScript execution testing");
                mermaidWindow.Close();
                return false; // Partial success - window opens but can't test buttons
            }
            
            Logger.Info("Found 'Load from DB' button, clicking...");
            loadButton.Click();
            Thread.Sleep(2000);
            
            // Step 4: Look for SchemaTableSelectionDialog
            Logger.Info("Step 4: Looking for Schema Table Selection Dialog");
            
            var selectionDialog = _app.GetAllTopLevelWindows(_automation)
                .FirstOrDefault(w => w.Name.Contains("Select Tables", StringComparison.OrdinalIgnoreCase)
                                  || w.Name.Contains("Schema", StringComparison.OrdinalIgnoreCase));
            
            if (selectionDialog == null)
            {
                Logger.Error("Schema Table Selection Dialog did NOT open");
                Logger.Error("❌ 'Load from DB' button click did not trigger dialog");
                mermaidWindow.Close();
                return false;
            }
            
            Logger.Info("✅ Schema Table Selection Dialog opened!");
            
            // Step 5: Try to select tables and generate
            // (Would continue with more detailed testing...)
            
            selectionDialog.Close();
            mermaidWindow.Close();
            
            Logger.Info("✅ TEST PASSED: Load from DB workflow verified to open selection dialog");
            return true;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Test failed with exception");
            return false;
        }
    }
    
    /// <summary>
    /// TEST 2: Simplified test - just check if Mermaid Designer can be opened
    /// </summary>
    public bool Test_MermaidDesigner_CanOpen()
    {
        Logger.Info("═══════════════════════════════════════════════");
        Logger.Info("TEST 2: Mermaid Designer - Can Open");
        Logger.Info("═══════════════════════════════════════════════");
        
        try
        {
            _mainWindow = _app.GetMainWindow(_automation);
            if (_mainWindow == null)
            {
                Logger.Error("Main window not found");
                return false;
            }
            
            // Try to find View menu and open Mermaid Designer
            var menuBar = _mainWindow.FindFirstDescendant(cf => cf.ByControlType(ControlType.MenuBar));
            var viewMenu = menuBar?.FindFirstDescendant(cf => cf.ByName("View"));
            
            if (viewMenu == null)
            {
                Logger.Error("View menu not found");
                return false;
            }
            
            viewMenu.Click();
            Thread.Sleep(500);
            
            var mermaidItem = viewMenu.FindFirstDescendant(cf => 
                cf.ByName("Mermaid Visual Designer").Or(cf.ByName("Mermaid Designer")));
            
            if (mermaidItem == null)
            {
                Logger.Warn("Mermaid Designer menu item not found - checking alternatives...");
                
                // List all menu items under View
                var allItems = viewMenu.FindAllDescendants();
                Logger.Debug("Found {Count} items in View menu", allItems.Length);
                foreach (var item in allItems.Take(10))
                {
                    Logger.Debug("  - {Name} ({Type})", item.Name, item.ControlType);
                }
                
                return false;
            }
            
            Logger.Info("Clicking Mermaid Designer menu item");
            mermaidItem.Click();
            Thread.Sleep(5000);
            
            // Check if window appeared
            var allWindows = _app.GetAllTopLevelWindows(_automation);
            Logger.Info("Found {Count} top-level windows after click", allWindows.Length);
            
            foreach (var window in allWindows)
            {
                Logger.Debug("  Window: {Title}", window.Name);
                
                if (window.Name.Contains("Mermaid", StringComparison.OrdinalIgnoreCase))
                {
                    Logger.Info("✅ TEST PASSED: Mermaid Designer window opened");
                    Logger.Info("   Window Title: {Title}", window.Name);
                    window.Close();
                    return true;
                }
            }
            
            Logger.Error("❌ TEST FAILED: Mermaid Designer window did not appear");
            return false;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Test failed with exception");
            return false;
        }
    }
    
    /// <summary>
    /// SUMMARY: Run all Mermaid Designer functional tests
    /// </summary>
    public void RunAllTests()
    {
        Logger.Info("\n");
        Logger.Info("╔═══════════════════════════════════════════════════════╗");
        Logger.Info("║  MERMAID DESIGNER FUNCTIONAL TESTS                    ║");
        Logger.Info("╚═══════════════════════════════════════════════════════╝");
        Logger.Info("");
        
        var results = new List<(string TestName, bool Passed, string Note)>();
        
        // Test 1: Can window open?
        var test1 = Test_MermaidDesigner_CanOpen();
        results.Add(("Mermaid Designer Can Open", test1, test1 ? "Window opens successfully" : "Window failed to open"));
        
        // Test 2: Load from DB workflow (complex, may fail due to WebView2)
        if (test1)
        {
            var test2 = Test_LoadFromDB_ActuallyWorks();
            results.Add(("Load from DB Workflow", test2, test2 ? "Complete workflow works" : "WebView2 buttons not accessible via FlaUI"));
        }
        else
        {
            results.Add(("Load from DB Workflow", false, "Skipped - window didn't open"));
        }
        
        // Summary
        Logger.Info("\n");
        Logger.Info("═══════════════════════════════════════════════════════");
        Logger.Info("  TEST RESULTS");
        Logger.Info("═══════════════════════════════════════════════════════");
        Logger.Info("");
        
        var passCount = results.Count(r => r.Passed);
        var failCount = results.Count(r => !r.Passed);
        
        foreach (var (testName, passed, note) in results)
        {
            var status = passed ? "✅ PASS" : "❌ FAIL";
            Logger.Info("{Status} - {Test}", status, testName);
            Logger.Info("        {Note}", note);
        }
        
        Logger.Info("");
        Logger.Info("Total: {Total} tests, {Pass} passed, {Fail} failed", 
            results.Count, passCount, failCount);
        Logger.Info("");
        
        if (failCount > 0)
        {
            Logger.Warn("⚠️  IMPORTANT FINDING:");
            Logger.Warn("   WebView2 content (HTML/JavaScript) cannot be tested with FlaUI");
            Logger.Warn("   Button clicks inside WebView2 require:");
            Logger.Warn("     - JavaScript execution via CoreWebView2.ExecuteScriptAsync()");
            Logger.Warn("     - OR Selenium WebDriver for browser automation");
            Logger.Warn("     - OR Manual testing");
        }
    }
}

