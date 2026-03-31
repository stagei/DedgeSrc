namespace GenericLogHandler.Core.Models;

/// <summary>
/// Cached metadata from AutoDocJson for a COBOL/REXX program that writes to WKMONIT.LOG.
/// Loaded from {ProgramName}.CBL.json or {ProgramName}.REX.json files.
/// </summary>
public class WkmonitProgramInfo
{
    public string ProgramName { get; set; } = string.Empty;
    public string TypeLabel { get; set; } = string.Empty;
    public string System { get; set; } = string.Empty;
    public bool UsesSql { get; set; }
    public string SourceType { get; set; } = string.Empty;
    public string AutoDocUrl { get; set; } = string.Empty;
}
