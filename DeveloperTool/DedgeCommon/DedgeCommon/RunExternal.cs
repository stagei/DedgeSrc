using NLog;
using System.Diagnostics;

namespace DedgeCommon
{
    /// <summary>
    /// Provides functionality for executing external programs and scripts.
    /// Handles the execution of various external processes including REXX,
    /// PowerShell, and command-line applications.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - Multiple script language support (REXX, PowerShell)
    /// - Process execution management
    /// - Output capture and logging
    /// - Error handling and reporting
    /// - Configurable execution settings
    /// - Security context management
    /// </remarks>
    /// <author>Geir Helge Starholm</author>
    public static class RunExternal
    {
        // Default paths for 32-bit executables
        private static readonly string _RexxExecutablePath32 = "C:\\Program Files (x86)\\ObjREXX\\REXX.exe";
        private static readonly string _PowerShell7ExecutablePath32 = "C:\\Program Files (x86)\\PowerShell\\7\\pwsh.exe";
        private static readonly string _Db2ExecutablePath32 = "C:\\Program Files (x86)\\IBM\\SQLLIB\\BIN\\db2cw.bat";
        
        // Default paths for 64-bit executables
        private static readonly string _RexxExecutablePath64 = "C:\\Program Files\\ObjREXX\\REXX.exe";
        private static readonly string _PowerShell7ExecutablePath64 = "C:\\Program Files\\PowerShell\\7\\pwsh.exe";
        private static readonly string _Db2ExecutablePath64 = "C:\\Program Files\\IBM\\SQLLIB\\BIN\\db2cw.bat";
        
        // System executables (typically only one version)
        private static readonly string _CmdExecutablePath = "C:\\Windows\\System32\\cmd.exe";

        /// <summary>
        /// Gets the appropriate executable path based on availability of 32-bit and 64-bit versions
        /// </summary>
        private static string GetExecutablePath(string path32, string path64, string customPath = "")
        {
            if (!string.IsNullOrEmpty(customPath) && File.Exists(customPath))
            {
                return customPath;
            }

            // Prefer 64-bit version if available
            if (File.Exists(path64))
            {
                return path64;
            }
            
            if (File.Exists(path32))
            {
                return path32;
            }

            // If neither exists, return the 64-bit path as default for the error message
            return path64;
        }

        /// <summary>
        /// Runs a REXX script using the specified REXX executable.
        /// </summary>
        /// <param name="scriptPath">The file path of the REXX script to be executed.</param>
        /// <param name="rexxExecutablePath">Optional path to the REXX executable. If not provided, uses the default path.</param>
        /// <returns>The output of the REXX script execution.</returns>
        /// <exception cref="FileNotFoundException">Thrown when the script or executable is not found.</exception>
        public static string RunRexxScript(string scriptPath, string rexxExecutablePath = "")
        {
            string result = "";
            try
            {
                if (!File.Exists(scriptPath))
                {
                    throw new FileNotFoundException("The REXX script does not exist.", scriptPath);
                }

                string execPath = GetExecutablePath(_RexxExecutablePath32, _RexxExecutablePath64, rexxExecutablePath);

                if (!File.Exists(execPath))
                {
                    throw new FileNotFoundException("The REXX executable does not exist.", execPath);
                }

                // Run the rexx script
                var startInfo = new ProcessStartInfo
                {
                    FileName = execPath,
                    Arguments = scriptPath,
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };

                Process process = new() { StartInfo = startInfo };
                process.Start();

                result = process.StandardOutput.ReadToEnd();
                process.WaitForExit();

                DedgeNLog.Info("Rexx script output: \n" + result);
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "An error occurred while running the REXX script: " + scriptPath);
                throw;
            }
            return result;
        }

        /// <summary>
        /// Runs a PowerShell 7 script using the specified PowerShell executable.
        /// </summary>
        /// <param name="scriptPath">The file path of the PowerShell script to be executed.</param>
        /// <param name="powershellExecutablePath">Optional path to the PowerShell executable.</param>
        /// <returns>The output of the PowerShell script execution.</returns>
        /// <exception cref="FileNotFoundException">Thrown when the script or executable is not found.</exception>
        public static string RunPowerShell7Script(string scriptPath, string powershellExecutablePath = "")
        {
            string result = "";
            try
            {
                if (!File.Exists(scriptPath))
                {
                    throw new FileNotFoundException("The PowerShell script does not exist.", scriptPath);
                }

                string execPath = GetExecutablePath(_PowerShell7ExecutablePath32, _PowerShell7ExecutablePath64, powershellExecutablePath);

                if (!File.Exists(execPath))
                {
                    throw new FileNotFoundException("The PowerShell executable does not exist.", execPath);
                }

                // Run the PowerShell script
                var startInfo = new ProcessStartInfo
                {
                    FileName = execPath,
                    Arguments = scriptPath,
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };

                Process process = new() { StartInfo = startInfo };
                process.Start();

                result = process.StandardOutput.ReadToEnd();
                process.WaitForExit();

                DedgeNLog.Info("PowerShell script output: \n" + result);
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "An error occurred while running the PowerShell script: " + scriptPath);
                throw;
            }
            return result;
        }

        /// <summary>
        /// Runs a DB2CMD script using the specified DB2CMD executable.
        /// </summary>
        /// <param name="scriptPath">The file path of the DB2CMD script to be executed.</param>
        /// <param name="db2cmdExecutablePath">Optional path to the DB2CMD executable.</param>
        /// <returns>The output of the DB2CMD script execution.</returns>
        /// <exception cref="FileNotFoundException">Thrown when the script or executable is not found.</exception>
        public static string RunDb2CmdScript(string scriptPath, string db2cmdExecutablePath = "")
        {
            string result = "";
            try
            {
                if (!File.Exists(scriptPath))
                {
                    throw new FileNotFoundException("The DB2CMD script does not exist.", scriptPath);
                }

                string execPath = GetExecutablePath(_Db2ExecutablePath32, _Db2ExecutablePath64, db2cmdExecutablePath);

                if (!File.Exists(execPath))
                {
                    throw new FileNotFoundException("The DB2CMD executable does not exist.", execPath);
                }

                // Run the DB2CMD script
                var startInfo = new ProcessStartInfo
                {
                    FileName = execPath,
                    Arguments = scriptPath,
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };

                Process process = new() { StartInfo = startInfo };
                process.Start();

                result = process.StandardOutput.ReadToEnd();
                process.WaitForExit();

                DedgeNLog.Info("DB2CMD script output: \n" + result);
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "An error occurred while running the DB2CMD script: " + scriptPath);
                throw;
            }
            return result;
        }

        /// <summary>
        /// Runs an external program with the specified arguments.
        /// </summary>
        /// <param name="executablePath">The path to the executable to run.</param>
        /// <param name="arguments">The command-line arguments to pass to the executable.</param>
        /// <param name="waitForExit">If true, waits for the program to exit before returning.</param>
        /// <returns>The output of the program execution.</returns>
        /// <exception cref="FileNotFoundException">Thrown when the executable is not found.</exception>
        public static string RunProgram(string executablePath, string arguments, bool waitForExit = true)
        {
            string result = "";
            string error = "";
            try
            {
                if (string.IsNullOrEmpty(executablePath) || !File.Exists(executablePath))
                {
                    throw new FileNotFoundException("The executable does not exist.", executablePath);
                }

                // Run the script
                var startInfo = new ProcessStartInfo
                {
                    FileName = executablePath,
                    Arguments = arguments,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };

                Process process = new() { StartInfo = startInfo };
                process.Start();

                // check if the process has exited
                if (waitForExit)
                {
                    process.WaitForExit();

                    result = process.StandardOutput.ReadToEnd();
                    error = process.StandardError.ReadToEnd();

                    DedgeNLog.Info("Program output: \n" + result);
                    if (!string.IsNullOrEmpty(error))
                    {
                        DedgeNLog.Error("Program error: \n" + error);
                    }
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "An error occurred while running the program: " + executablePath);
                throw;
            }
            return result;
        }

        /// <summary>
        /// Runs a command using the Windows Command Prompt (cmd.exe).
        /// </summary>
        /// <param name="command">The command to execute.</param>
        /// <param name="cmdExecutablePath">Optional path to cmd.exe. If not provided, uses the default path.</param>
        /// <returns>The output of the command execution.</returns>
        /// <exception cref="FileNotFoundException">Thrown when cmd.exe is not found at the specified path.</exception>
        public static string RunCmdCommand(string command, string cmdExecutablePath = "")
        {
            string result = "";
            try
            {
                string execPath = string.IsNullOrEmpty(cmdExecutablePath) ? _CmdExecutablePath : cmdExecutablePath;

                if (!File.Exists(execPath))
                {
                    throw new FileNotFoundException("The CMD executable does not exist.", execPath);
                }

                // Run the CMD command
                var startInfo = new ProcessStartInfo
                {
                    FileName = execPath,
                    Arguments = $"/C {command}",  // /C carries out the command and terminates
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };

                Process process = new() { StartInfo = startInfo };
                process.Start();

                result = process.StandardOutput.ReadToEnd();
                string error = process.StandardError.ReadToEnd();
                process.WaitForExit();

                if (!string.IsNullOrEmpty(error))
                {
                    DedgeNLog.Error($"CMD error output: {error}");
                }
                else
                {
                    DedgeNLog.Info($"CMD command output: {result}");
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"An error occurred while running the CMD command: {command}");
                throw;
            }
            return result;
        }
    }
}

