namespace AutoDocNew.Core;

/// <summary>
/// Abstraction for C# project/solution parsing.
/// Implemented by the main application so Core does not reference Parsers.
/// </summary>
public interface ICSharpProjectRunner
{
    /// <summary>Parse a C# solution into HTML documentation.</summary>
    void ParseSolution(string solutionFolder, string solutionFile, string outputFolder,
        string tmpRootFolder, string srcRootFolder, bool clientSideRender, bool cleanUp);

    /// <summary>Generate ecosystem diagram for all projects in a repo folder.</summary>
    void ParseEcosystem(string repoFolder, string outputFolder, string tmpFolder, string ecosystemName);
}
