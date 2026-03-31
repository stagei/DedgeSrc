using System.Diagnostics;

namespace SqlMmdConverter.Tests.Utilities;

/// <summary>
/// Utility for opening files for visual comparison when tests fail.
/// </summary>
public static class FileComparisonUtility
{
    /// <summary>
    /// Opens two files for comparison using the system default or a diff tool if available.
    /// </summary>
    /// <param name="expectedPath">Path to the expected/reference file</param>
    /// <param name="actualPath">Path to the actual/generated file</param>
    public static void OpenFilesForComparison(string expectedPath, string actualPath)
    {
        if (!File.Exists(expectedPath))
        {
            Console.WriteLine($"Expected file not found: {expectedPath}");
            return;
        }

        if (!File.Exists(actualPath))
        {
            Console.WriteLine($"Actual file not found: {actualPath}");
            return;
        }

        // Try to launch diff tool
        if (TryLaunchDiffTool(expectedPath, actualPath))
        {
            return;
        }

        // Fallback: open both files individually
        OpenFile(expectedPath);
        OpenFile(actualPath);
    }

    private static bool TryLaunchDiffTool(string expectedPath, string actualPath)
    {
        // Try common diff tools in order of preference
        var diffTools = new[]
        {
            // VS Code
            new DiffTool
            {
                Name = "VS Code",
                ExecutablePaths = new[] {
                    @"C:\Program Files\Microsoft VS Code\Code.exe",
                    @"C:\Program Files\Microsoft VS Code\bin\code.cmd"
                },
                Arguments = (exp, act) => $"--diff \"{exp}\" \"{act}\""
            },
            // WinMerge
            new DiffTool
            {
                Name = "WinMerge",
                ExecutablePaths = new[] {
                    @"C:\Program Files\WinMerge\WinMergeU.exe",
                    @"C:\Program Files (x86)\WinMerge\WinMergeU.exe"
                },
                Arguments = (exp, act) => $"\"{exp}\" \"{act}\""
            },
            // Beyond Compare
            new DiffTool
            {
                Name = "Beyond Compare",
                ExecutablePaths = new[] {
                    @"C:\Program Files\Beyond Compare 4\BComp.exe",
                    @"C:\Program Files\Beyond Compare 5\BComp.exe",
                    @"C:\Program Files (x86)\Beyond Compare 4\BComp.exe"
                },
                Arguments = (exp, act) => $"\"{exp}\" \"{act}\""
            },
            // KDiff3
            new DiffTool
            {
                Name = "KDiff3",
                ExecutablePaths = new[] {
                    @"C:\Program Files\KDiff3\kdiff3.exe",
                    @"C:\Program Files (x86)\KDiff3\kdiff3.exe"
                },
                Arguments = (exp, act) => $"\"{exp}\" \"{act}\""
            }
        };

        foreach (var tool in diffTools)
        {
            foreach (var path in tool.ExecutablePaths)
            {
                if (File.Exists(path))
                {
                    try
                    {
                        var args = tool.Arguments(expectedPath, actualPath);
                        var psi = new ProcessStartInfo
                        {
                            FileName = path,
                            Arguments = args,
                            UseShellExecute = true
                        };

                        Process.Start(psi);
                        Console.WriteLine($"Opened files in {tool.Name} for comparison");
                        return true;
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Failed to launch {tool.Name}: {ex.Message}");
                    }
                }
            }
        }

        return false;
    }

    private static void OpenFile(string filePath)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = filePath,
                UseShellExecute = true
            };

            Process.Start(psi);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Failed to open file {filePath}: {ex.Message}");
        }
    }

    private class DiffTool
    {
        public required string Name { get; init; }
        public required string[] ExecutablePaths { get; init; }
        public required Func<string, string, string> Arguments { get; init; }
    }
}

