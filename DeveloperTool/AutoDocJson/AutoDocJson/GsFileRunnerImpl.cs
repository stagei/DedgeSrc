using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew;

/// <summary>
/// Implementation of IGsFileRunner that delegates to GsParser.
/// </summary>
internal sealed class GsFileRunnerImpl : IGsFileRunner
{
    public string? ParseGsFile(string gsFilePath, string impFolder, string outputFolder)
    {
        return GsParser.StartGsParse(gsFilePath, impFolder, outputFolder);
    }
}
