namespace AutoDocNew.Core;

/// <summary>
/// Log level enumeration matching PowerShell ValidateSet values
/// </summary>
public enum LogLevel
{
    TRACE,
    DEBUG,
    INFO,
    WARN,
    ERROR,
    FATAL,
    JOB_STARTED,
    JOB_COMPLETED,
    JOB_FAILED
}
