using System;
using System.IO;
using AutoDocNew.Core;
using AutoDocNew.Parsers;

namespace AutoDocNew;

/// <summary>
/// Implements single-file parsing by delegating to the appropriate parser.
/// Converted from AutoDocBatchRunner.ps1 single-file block (lines 2526-2635).
/// </summary>
internal sealed class SingleFileParserImpl : ISingleFileParser
{
    public int Parse(string singleFileArg, string outputFolder, string tmpFolder, string workFolder, bool clientSideRender, bool saveMmdFiles, bool generateHtml)
    {
        string srcRootFolder = workFolder;

        if (IsSqlTable(singleFileArg))
        {
            Logger.LogMessage($"Detected SQL table: {singleFileArg}", LogLevel.INFO);
            string? result = SqlParser.StartSqlParse(
                sqlTable: singleFileArg,
                show: false,
                outputFolder: outputFolder,
                cleanUp: true,
                tmpRootFolder: tmpFolder,
                srcRootFolder: srcRootFolder,
                generateHtml: generateHtml);
            return string.IsNullOrEmpty(result) ? 1 : 0;
        }

        string? sourceFilePath = ResolveSourceFilePath(singleFileArg, workFolder);
        if (sourceFilePath == null)
        {
            Logger.LogMessage($"Could not find source file: {singleFileArg}", LogLevel.ERROR);
            return 1;
        }

        Logger.LogMessage($"Found source file: {sourceFilePath}", LogLevel.INFO);
        string fileExt = Path.GetExtension(sourceFilePath).ToLowerInvariant();

        switch (fileExt)
        {
            case ".cbl":
                return ParseResultToExitCode(CblParser.StartCblParse(
                    sourceFile: sourceFilePath,
                    show: false,
                    outputFolder: outputFolder,
                    cleanUp: true,
                    tmpRootFolder: tmpFolder,
                    srcRootFolder: srcRootFolder,
                    clientSideRender: clientSideRender,
                    saveMmdFiles: saveMmdFiles,
                    generateHtml: generateHtml));
            case ".ps1":
                return ParseResultToExitCode(Ps1Parser.StartPs1Parse(
                    sourceFile: sourceFilePath,
                    show: false,
                    outputFolder: outputFolder,
                    cleanUp: true,
                    tmpRootFolder: tmpFolder,
                    srcRootFolder: srcRootFolder,
                    clientSideRender: clientSideRender,
                    saveMmdFiles: saveMmdFiles,
                    generateHtml: generateHtml));
            case ".rex":
                return ParseResultToExitCode(RexParser.StartRexParse(
                    sourceFile: sourceFilePath,
                    show: false,
                    outputFolder: outputFolder,
                    cleanUp: true,
                    tmpRootFolder: tmpFolder,
                    srcRootFolder: srcRootFolder,
                    clientSideRender: clientSideRender,
                    saveMmdFiles: saveMmdFiles,
                    generateHtml: generateHtml));
            case ".bat":
                return ParseResultToExitCode(BatParser.StartBatParse(
                    sourceFile: sourceFilePath,
                    show: false,
                    outputFolder: outputFolder,
                    cleanUp: true,
                    tmpRootFolder: tmpFolder,
                    srcRootFolder: srcRootFolder,
                    clientSideRender: clientSideRender,
                    saveMmdFiles: saveMmdFiles,
                    generateHtml: generateHtml));
            case ".sln":
            {
                string? solutionFolder = Path.GetDirectoryName(sourceFilePath);
                if (string.IsNullOrEmpty(solutionFolder))
                    return 1;
                Logger.LogMessage($"Processing C# solution from folder: {solutionFolder}", LogLevel.INFO);
                return ParseResultToExitCode(CSharpParser.StartCSharpParse(
                    sourceFolder: solutionFolder,
                    solutionFile: sourceFilePath,
                    outputFolder: outputFolder,
                    tmpRootFolder: tmpFolder,
                    srcRootFolder: srcRootFolder,
                    clientSideRender: clientSideRender,
                    cleanUp: true,
                    generateHtml: generateHtml));
            }
            default:
                Logger.LogMessage($"Unsupported file type: {fileExt}", LogLevel.ERROR);
                return 1;
        }
    }

    private static bool IsSqlTable(string arg)
    {
        if (string.IsNullOrWhiteSpace(arg)) return false;

        // Strip surrounding quotes from table names like "CRM"."A_ORDREHODE"
        string cleaned = arg.Replace("\"", "");

        // Regex: ^[A-Z]+\.[A-Z0-9_]+$
        // ^          - start of string
        // [A-Z]+     - one or more uppercase letters (schema name)
        // \.         - literal dot separator
        // [A-Z0-9_]+ - one or more alphanumeric or underscore (table name)
        // $          - end of string
        if (cleaned.Contains(".") && cleaned.IndexOf(".", StringComparison.Ordinal) == cleaned.LastIndexOf(".", StringComparison.Ordinal))
        {
            if (System.Text.RegularExpressions.Regex.IsMatch(cleaned, @"^[A-Z]+\.[A-Z0-9_]+$", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                return true;
        }
        if (!cleaned.Contains(".") && cleaned.Length > 0 && char.IsLetter(cleaned[0]))
            return true;
        return false;
    }

    private static string? ResolveSourceFilePath(string singleFileArg, string workFolder)
    {
        if (File.Exists(singleFileArg))
            return Path.GetFullPath(singleFileArg);

        string DedgeCblFolder = Path.Combine(workFolder, "Dedge", "cbl");
        string candidate = Path.Combine(DedgeCblFolder, singleFileArg);
        if (File.Exists(candidate))
            return candidate;

        string DedgePshFolder = Path.Combine(workFolder, "DedgePsh");
        candidate = Path.Combine(DedgePshFolder, singleFileArg);
        if (File.Exists(candidate))
            return candidate;

        return null;
    }

    private static int ParseResultToExitCode(string? result) => string.IsNullOrEmpty(result) ? 1 : 0;
}
