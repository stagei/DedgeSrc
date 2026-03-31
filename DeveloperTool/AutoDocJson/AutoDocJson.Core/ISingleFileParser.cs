namespace AutoDocNew.Core;

/// <summary>
/// Abstraction for parsing a single file (used when -SingleFile is set).
/// Implemented by the main application so Core does not reference Parsers.
/// Converted from AutoDocBatchRunner.ps1 single-file block (lines 2526-2635).
/// </summary>
public interface ISingleFileParser
{
    /// <summary>
    /// Parse a single file or SQL table.
    /// </summary>
    /// <param name="singleFileArg">File name (e.g. aabelma.cbl), full path, or SQL table (SCHEMA.TABLE).</param>
    /// <param name="outputFolder">Output folder for generated HTML.</param>
    /// <param name="tmpFolder">Temp root folder.</param>
    /// <param name="workFolder">Work folder containing Dedge, DedgePsh subfolders.</param>
    /// <param name="clientSideRender">Use client-side Mermaid rendering.</param>
    /// <param name="saveMmdFiles">Save .mmd diagram source files.</param>
    /// <param name="generateHtml">When true, generate static HTML files alongside JSON.</param>
    /// <returns>0 on success, non-zero on failure.</returns>
    int Parse(string singleFileArg, string outputFolder, string tmpFolder, string workFolder, bool clientSideRender, bool saveMmdFiles, bool generateHtml);
}
