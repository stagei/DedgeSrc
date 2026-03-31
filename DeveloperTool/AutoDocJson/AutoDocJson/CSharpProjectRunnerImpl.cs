using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew;

/// <summary>
/// Implementation of ICSharpProjectRunner that delegates to CSharpParser.
/// </summary>
internal sealed class CSharpProjectRunnerImpl : ICSharpProjectRunner
{
    public void ParseSolution(string solutionFolder, string solutionFile, string outputFolder,
        string tmpRootFolder, string srcRootFolder, bool clientSideRender, bool cleanUp)
    {
        CSharpParser.StartCSharpParse(
            sourceFolder: solutionFolder,
            solutionFile: solutionFile,
            outputFolder: outputFolder,
            tmpRootFolder: tmpRootFolder,
            srcRootFolder: srcRootFolder,
            clientSideRender: clientSideRender,
            cleanUp: cleanUp);
    }

    public void ParseEcosystem(string repoFolder, string outputFolder, string tmpFolder, string ecosystemName)
    {
        CSharpParser.StartCSharpEcosystemParse(repoFolder, outputFolder, tmpFolder, ecosystemName);
    }
}
