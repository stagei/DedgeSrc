using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace AutoDocNew.Tests;

/// <summary>
/// Configuration for Test-AutoDocGeneration (C#). Load from TestFileList.json so file list can be changed without recompile.
/// </summary>
public class TestGenerationConfig
{
    /// <summary>Repository root (DedgeRepository). Defaults to OptPath/data/AutoDocJson/tmp/DedgeRepository if empty.</summary>
    [JsonPropertyName("repoRoot")]
    public string RepoRoot { get; set; } = "";

    /// <summary>Output folder for generated HTML. Defaults to OptPath/Webs/AutoDocJson if empty.</summary>
    [JsonPropertyName("outputFolder")]
    public string OutputFolder { get; set; } = "";

    /// <summary>Temporary/working folder. Defaults to OptPath/data/AutoDocJson/tmp if empty.</summary>
    [JsonPropertyName("tmpRootFolder")]
    public string TmpRootFolder { get; set; } = "";

    /// <summary>List of files to generate. Edit this file to add/remove test files without recompiling.</summary>
    [JsonPropertyName("files")]
    public List<TestGenerationFileEntry> Files { get; set; } = new List<TestGenerationFileEntry>();
}

/// <summary>
/// One entry in the test file list.
/// For SQL: set isTable true and fileName (e.g. DBM.AH_ORDREHODE). Path is ignored.
/// For others: path is relative to repoRoot (e.g. Dedge/cbl/BSAUTOS.CBL). fileName should match the file name.
/// </summary>
public class TestGenerationFileEntry
{
    /// <summary>Type: CBL, REX, BAT, PS1, SQL, CSharp.</summary>
    [JsonPropertyName("type")]
    public string Type { get; set; } = "";

    /// <summary>File or table name (e.g. BSAUTOS.CBL, DBM.AH_ORDREHODE).</summary>
    [JsonPropertyName("fileName")]
    public string FileName { get; set; } = "";

    /// <summary>Path relative to repoRoot (e.g. Dedge/cbl/BSAUTOS.CBL). Not used for SQL when isTable is true.</summary>
    [JsonPropertyName("path")]
    public string Path { get; set; } = "";

    /// <summary>True for SQL table entries. Path is ignored.</summary>
    [JsonPropertyName("isTable")]
    public bool IsTable { get; set; }
}
