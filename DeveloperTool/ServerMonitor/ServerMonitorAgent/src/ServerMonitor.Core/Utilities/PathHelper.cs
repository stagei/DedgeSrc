using System.Text.RegularExpressions;

namespace ServerMonitor.Core.Utilities;

/// <summary>
/// Converts between local OptPath-based paths and UNC paths for remote Dashboard access.
/// Local:  E:\opt\data\ServerMonitor\...
/// UNC:    \\SERVERNAME.DEDGE.fk.no\opt\data\ServerMonitor\...
/// </summary>
public static class PathHelper
{
    private const string DnsSuffix = "DEDGE.fk.no";

    // Regex: match drive letter + :\opt at start, followed by \ or end-of-string
    // ^           - Start of string
    // [A-Za-z]    - Any drive letter
    // :           - Literal colon
    // \\          - Literal backslash (escaped for regex)
    // opt         - Literal "opt"
    // (?=\\|$)    - Positive lookahead: must be followed by backslash or end-of-string
    private static readonly Regex DriveOptPattern = new(
        @"^[A-Za-z]:\\opt(?=\\|$)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    // Regex: match \\hostname.DEDGE.fk.no\opt at start
    // ^                           - Start of string
    // \\\\                        - Two literal backslashes (UNC prefix)
    // [^\\]+                      - One or more non-backslash chars (hostname.fqdn)
    // \\                          - Literal backslash
    // opt                         - Literal "opt"
    // (?=\\|$)                    - Lookahead: followed by backslash or end-of-string
    private static readonly Regex UncOptPattern = new(
        @"^\\\\[^\\]+\\opt(?=\\|$)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    /// <summary>
    /// Converts a local OptPath-based path to a UNC path for remote access.
    /// E:\opt\data\... → \\SERVERNAME.DEDGE.fk.no\opt\data\...
    /// Uses the current machine name when machineName is not provided.
    /// </summary>
    public static string ToUncPath(string localPath, string? machineName = null)
    {
        if (string.IsNullOrEmpty(localPath))
            return localPath;

        var host = machineName ?? Environment.MachineName;
        var fqdn = host.Contains('.') ? host : $"{host}.{DnsSuffix}";

        return DriveOptPattern.Replace(localPath, $@"\\{fqdn}\opt");
    }

    /// <summary>
    /// Converts a UNC path back to a local OptPath-based path.
    /// \\SERVERNAME.DEDGE.fk.no\opt\data\... → {OptPath}\data\...
    /// Falls back to C:\opt when OptPath env var is not set.
    /// </summary>
    public static string ToLocalPath(string uncPath)
    {
        if (string.IsNullOrEmpty(uncPath))
            return uncPath;

        var optPath = Environment.GetEnvironmentVariable("OptPath") ?? @"C:\opt";

        return UncOptPattern.Replace(uncPath, optPath.TrimEnd('\\'));
    }
}
