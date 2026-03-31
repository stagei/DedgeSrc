# Debug Report: Logging Issue - No Logs Being Created

**Issue**: ServerMonitor process starts and runs for 30+ seconds but creates NO log files  
**Attempts Made**: 5  
**Status**: UNRESOLVED - Requires manual debugging  
**Date**: 2025-11-27

---

## Problem Summary

The ServerMonitor application:
- ✅ Compiles successfully
- ✅ Starts and runs (process visible in Task Manager)
- ✅ Runs for 30+ seconds before timeout kill
- ❌ Creates NO log files
- ❌ Creates NO NLog internal log
- ❌ No errors in Windows Event Log

---

## What Was Tried

### Attempt 1: Fixed Configuration File Path
- **Issue**: App looking for `appsettings.json` in wrong directory
- **Fix**: Changed from `Directory.GetCurrentDirectory()` to `AppContext.BaseDirectory`
- **Result**: Fixed the FileNotFoundException, but no logs

### Attempt 2: Added Missing NLog.WindowsEventLog Package
- **Issue**: NLog.config referenced EventLog target without package
- **Fix**: Added `NLog.WindowsEventLog` version 5.3.4
- **Result**: No more NLog warnings, but still no logs

### Attempt 3: Updated NLog.config Defaults
- **Issue**: NLog.config had old default paths
- **Fix**: Changed defaults from `ServerMonitor\ServerMonitor` to `ServerMonitor\ServerMonitor`
- **Result**: Config correct, but still no logs

### Attempt 4: Enabled NLog Exceptions and Trace Logging
- **Issue**: NLog might be failing silently
- **Fix**: Set `throwExceptions="true"` and `internalLogLevel="Trace"`
- **Result**: No exceptions thrown, no internal log created

### Attempt 5: Checked Windows Event Log
- **Issue**: App might be crashing
- **Fix**: Checked Application Event Log for .NET Runtime errors
- **Result**: No crash errors found

---

## Current State

### Files Confirmed Present
- ✅ `appsettings.json` in output directory
- ✅ `NLog.config` in output directory
- ✅ `ServerMonitor.exe` executable
- ✅ All required DLLs including `NLog.dll` and `NLog.WindowsEventLog.dll`

### Directories Confirmed Created
- ✅ `C:\opt\data\ServerMonitor\` exists

### Configuration Confirmed Correct
```xml
<nlog ...
      throwExceptions="true"
      internalLogLevel="Trace"
      internalLogFile="c:\opt\data\ServerMonitor\ServerMonitor_nlog-internal.log">
  
  <variable name="logDirectory" value="${environment:LOG_DIRECTORY:whenEmpty=c:\opt\data\ServerMonitor}"/>
  <variable name="appName" value="${environment:LOG_APPNAME:whenEmpty=ServerMonitor}"/>
```

### What's Missing
- ❌ No log file: `C:\opt\data\ServerMonitor\ServerMonitor_2025-11-27.log`
- ❌ No internal log: `C:\opt\data\ServerMonitor\ServerMonitor_nlog-internal.log`
- ❌ No console output captured
- ❌ No error messages anywhere

---

## Debugging Steps for Manual Investigation

### Step 1: Run with Console Window Visible
```powershell
# Start without -WindowStyle Minimized to see console output
$exePath = "C:\opt\src\ServerMonitor\ServerMonitorAgent\src\ServerMonitor\ServerMonitorAgent\bin\Release\net10.0-windows\win-x64\ServerMonitor.exe"
& $exePath
```

**Expected**: See console output showing what's happening  
**Look for**: Errors, stack traces, initialization messages

### Step 2: Attach Debugger
```powershell
# Open in Visual Studio
# Set breakpoints in:
- Program.cs: Main() method, line where NLog is initialized
- SurveillanceWorker.cs: StartAsync() method
- GlobalSnapshotService.cs: constructor

# Run with F5 and step through
```

**Check**: Does execution reach these points? Where does it stop?

### Step 3: Check Process Details
```powershell
# While process is running:
$process = Get-Process -Name "ServerMonitor"
$process | Select-Object Id, CPU, WorkingSet64, Threads

# Check if it's actually doing anything:
$process.Threads | ForEach-Object { $_.WaitReason }
```

**Look for**: Is CPU usage > 0? Are threads blocked? What are they waiting for?

### Step 4: Use Process Monitor (Procmon)
1. Download Sysinternals Process Monitor
2. Filter for "ServerMonitor.exe"
3. Run the application
4. Look for:
   - File access attempts to `appsettings.json`
   - File creation attempts to log directory
   - Registry access
   - DLL loads
   - Any "ACCESS DENIED" or "PATH NOT FOUND" errors

### Step 5: Check for Deadlocks
```csharp
// Add to Program.cs at the very start of Main():
Console.WriteLine("=== STARTING ===");
logger.Info("=== NLOG STARTED ===");

// Add after each major initialization:
Console.WriteLine("Config loaded");
Console.WriteLine("Host built");
Console.WriteLine("Host running");
```

**Check**: Which message is the last one printed?

### Step 6: Simplify to Minimal Reproduction
Create a minimal test:
```csharp
class Program
{
    static void Main()
    {
        var logger = LogManager.GetCurrentClassLogger();
        logger.Info("TEST MESSAGE");
        Console.WriteLine("If you see this, app started");
        Thread.Sleep(10000);
        Console.WriteLine("Still running");
        LogManager.Shutdown();
    }
}
```

**Expected**: If this works, problem is in app logic. If not, problem is in NLog setup.

### Step 7: Check Environment Variables
```powershell
# When app is running, check its environment:
$process = Get-Process -Name "ServerMonitor"
# (Can't easily get env vars from running process without debugger)

# Instead, check if Program.cs is setting them:
```

**Add logging to Program.cs**:
```csharp
Environment.SetEnvironmentVariable("LOG_DIRECTORY", logDirectory);
Environment.SetEnvironmentVariable("LOG_APPNAME", appName);

// Add this:
Console.WriteLine($"LOG_DIRECTORY={Environment.GetEnvironmentVariable("LOG_DIRECTORY")}");
Console.WriteLine($"LOG_APPNAME={Environment.GetEnvironmentVariable("LOG_APPNAME")}");
```

### Step 8: Check Permissions
```powershell
# Check if app can write to log directory:
$logDir = "C:\opt\data\ServerMonitor"
$acl = Get-Acl $logDir
$acl.Access | Where-Object { $_.IdentityReference -match $env:USERNAME }
```

**Check**: Does current user have Write permissions?

### Step 9: Try Different Log Target
Temporarily change NLog.config to write to a simple location:
```xml
<target xsi:type="File"
        name="fileTarget"
        fileName="C:\Temp\test.log"
        layout="${message}" />
```

**Check**: Does this simple config work?

### Step 10: Check if Host is Actually Running
The app uses `Host.CreateDefaultBuilder()` which runs as a background service. Check if:
```csharp
// In SurveillanceWorker.cs, add to StartAsync():
_logger.LogInformation("=== WORKER STARTED ===");
File.WriteAllText(@"C:\Temp\worker-started.txt", DateTime.Now.ToString());
```

**Check**: Does the file get created? If not, background service isn't starting.

---

## Most Likely Root Causes

Based on the symptoms:

### Theory 1: Background Service Not Starting (70% likely)
- App starts but `SurveillanceWorker` never calls `StartAsync()`
- Host configuration issue
- Service registration problem

**How to verify**: Add file write in `StartAsync()` (see Step 10)

### Theory 2: Synchronous Deadlock (20% likely)
- App starts but hangs immediately
- Async/await deadlock in initialization
- Thread blocking on startup

**How to verify**: Attach debugger and check thread states (Step 3)

### Theory 3: Silent Exception (10% likely)
- Exception thrown before logging initializes
- Try-catch swallowing errors
- Configuration validation failing

**How to verify**: Add console writes everywhere (Step 5)

---

## Recommended Next Steps

1. **IMMEDIATE**: Run Step 1 (console window visible) - 2 minutes
2. **QUICK**: Run Step 10 (file write in Worker) - 5 minutes
3. **THOROUGH**: Run Step 4 (Process Monitor) - 15 minutes
4. **IF STUCK**: Run Step 2 (attach debugger) - 30 minutes

---

## Workaround to Continue Testing

Since we need to test other features (JSON/HTML export, REST API), we can:

1. Add `Console.WriteLine()` statements throughout the code
2. Capture console output to a file:
   ```powershell
   & $exePath > C:\Temp\console-output.txt 2>&1
   ```
3. Read that file instead of NLog logs
4. Once we get console output, we can see what's failing

---

## Status: SKIPPED (Moving to Next Task)

Per user instructions: After 5 attempts, skip and move to next task.

**Next Task**: Test and fix JSON/HTML export functionality

