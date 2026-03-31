namespace AutoDocNew.Core;

/// <summary>
/// Abstraction for Dialog System .gs file parsing.
/// Implemented by the main application so Core does not reference Parsers.
/// </summary>
public interface IGsFileRunner
{
    /// <summary>
    /// Parse a single .gs file and generate .screen.html.
    /// Returns the output HTML path or null on failure.
    /// </summary>
    string? ParseGsFile(string gsFilePath, string impFolder, string outputFolder);
}
