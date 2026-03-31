using System;
using System.Diagnostics;
using System.Linq;
using System.Management;
using AutoDocNew.Core;

namespace AutoDocNew.Core;

/// <summary>
/// Kill Process Handler - converted line-by-line from AutoDocBatchRunner.ps1 (lines 73-130)
/// Kills other PowerShell processes running AutoDocBatchRunner.ps1 to prevent conflicts
/// </summary>
public static class KillProcessHandler
{
    /// <summary>
    /// Kill other AutoDoc processes
    /// Converted line-by-line from lines 73-130
    /// </summary>
    public static void KillOtherAutoDocProcesses()
    {
        // Line 75: Get current process ID
        int currentProcessId = Process.GetCurrentProcess().Id;

        // Line 79: Initialize list
        var otherAutoDocProcesses = new List<Process>();

        // Line 82-84: Get PowerShell processes
        var pwshProcesses = Process.GetProcessesByName("pwsh")
            .Where(p => p.Id != currentProcessId)
            .ToList();
        var psProcesses = Process.GetProcessesByName("powershell")
            .Where(p => p.Id != currentProcessId)
            .ToList();

        // Line 86-110: Check each process for AutoDocBatchRunner in command line
        foreach (var proc in pwshProcesses.Concat(psProcesses))
        {
            try
            {
                // Line 89-99: Get command line using WMI/CIM
                string? commandLine = null;
                try
                {
                    using (ManagementObjectSearcher searcher = new ManagementObjectSearcher(
                        $"SELECT CommandLine FROM Win32_Process WHERE ProcessId = {proc.Id}"))
                    {
                        foreach (ManagementObject obj in searcher.Get())
                        {
                            commandLine = obj["CommandLine"]?.ToString();
                            break;
                        }
                    }
                }
                catch
                {
                    // Skip if we can't get command line
                    continue;
                }

                // Line 102: Check if command line contains AutoDocBatchRunner
                if (!string.IsNullOrEmpty(commandLine) && commandLine.Contains("AutoDocBatchRunner.ps1"))
                {
                    otherAutoDocProcesses.Add(proc);
                }
            }
            catch
            {
                // If we can't check command line, skip this process
                continue;
            }
        }

        // Line 112-126: Kill found processes
        if (otherAutoDocProcesses.Count > 0)
        {
            Logger.LogMessage($"Found {otherAutoDocProcesses.Count} other AutoDoc process(es) running. Terminating to prevent conflicts...", LogLevel.WARN);
            foreach (var proc in otherAutoDocProcesses)
            {
                try
                {
                    Logger.LogMessage($"Terminating process: PID {proc.Id}, Name: {proc.ProcessName}", LogLevel.INFO);
                    proc.Kill();
                    Logger.LogMessage($"Successfully terminated process PID {proc.Id}", LogLevel.INFO);
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"Failed to terminate process PID {proc.Id}: {ex.Message}", LogLevel.WARN);
                }
            }
            // Line 125: Give processes a moment to terminate
            System.Threading.Thread.Sleep(2000);
        }
        else
        {
            // Line 128: No other processes found
            Logger.LogMessage("No other AutoDoc processes detected. Proceeding...", LogLevel.INFO);
        }
    }
}
