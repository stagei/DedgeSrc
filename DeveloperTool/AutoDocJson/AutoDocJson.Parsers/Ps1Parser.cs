using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using AutoDocNew.Core;
using AutoDocNew.Models;

namespace AutoDocNew.Parsers;

/// <summary>
/// PS1 Parser - complete line-by-line translation from AutoDocFunctions.psm1
/// Functions translated:
///   Get-Ps1ExecutionPathDiagram  (lines 2360-2376)
///   Test-Ps1Function             (lines 2378-2397)
///   Get-ModuleFunctions          (lines 2399-2464)
///   Resolve-ModuleName           (lines 2466-2518)
///   Build-ModuleIndex            (lines 2520-2595)
///   Get-Ps1DecodedConcat         (lines 2597-2610)
///   Decode                       (lines 2611-2626)
///   Get-Ps1DecodedSubstr         (lines 2628-2647)
///   Get-Ps1VariableValue         (lines 2649-2661)
///   GetLocalVariableValue        (lines 2663-2675)
///   New-Ps1Nodes                 (lines 2677-3140)
///   New-Ps1MmdLinks              (lines 3142-3180)
///   Get-Ps1MetaData              (lines 3182-3369)
///   Write-Ps1Mmd                 (lines 3371-3426)
///   Find-Ps1FunctionCode         (lines 3428-3462)
///   Start-Ps1Parse               (lines 3480-3977)
/// </summary>
public static class Ps1Parser
{
    /// <summary>
    /// Global module index built once at startup by BatchRunner.
    /// Used as fallback when moduleIndex parameter is null in StartPs1Parse.
    /// </summary>
    public static Dictionary<string, (string FilePath, List<string> Functions)>? GlobalModuleIndex { get; set; }

    private class MatchResult
    {
        public int LineNumber { get; set; }
        public string Line { get; set; } = "";
        public string Pattern { get; set; } = "";
    }

    #region Module Index (lines 2399-2595)

    /// <summary>
    /// Extracts function names from a .psm1 file.
    /// Converted line-by-line from Get-ModuleFunctions (lines 2399-2464)
    /// </summary>
    public static List<string> GetModuleFunctions(string moduleFilePath)
    {
        var functions = new List<string>();
        if (!File.Exists(moduleFilePath)) return functions;

        try
        {
            string[] fileContent = SourceFileCache.GetLines(moduleFilePath) ?? File.ReadAllLines(moduleFilePath);
            var exportedFunctions = new List<string>();

            // Line 2428-2438: Extract Export-ModuleMember
            foreach (string line in fileContent)
            {
                // Regex: Export-ModuleMember\s+-Function\s+(.+)$ - Match Export-ModuleMember with function list
                var m = Regex.Match(line, @"Export-ModuleMember\s+-Function\s+(.+)$", RegexOptions.IgnoreCase);
                if (m.Success)
                {
                    exportedFunctions.AddRange(m.Groups[1].Value.Split(',')
                        .Select(s => s.Trim().Trim('\'', '"')));
                }
            }

            // Line 2441-2448: Extract function declarations
            foreach (string line in fileContent)
            {
                // Regex: ^\s*function\s+([a-zA-Z0-9_-]+) - Match function keyword at start of line
                var m = Regex.Match(line, @"^\s*function\s+([a-zA-Z0-9_-]+)", RegexOptions.IgnoreCase);
                if (m.Success)
                {
                    string funcName = m.Groups[1].Value.ToUpper();
                    if (funcName.Length > 0)
                        functions.Add(funcName);
                }
            }

            // Line 2451-2453: Filter to exported only if Export-ModuleMember found
            if (exportedFunctions.Count > 0)
            {
                var exportedUpper = exportedFunctions.Select(f => f.ToUpper()).ToHashSet();
                functions = functions.Where(f => exportedUpper.Contains(f)).ToList();
            }

            functions = functions.Distinct().OrderBy(x => x).ToList();
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error parsing module file {moduleFilePath}: {ex.Message}", LogLevel.WARN);
        }
        return functions;
    }

    /// <summary>
    /// Extracts module name from Import-Module statement.
    /// Converted line-by-line from Resolve-ModuleName (lines 2466-2518)
    /// </summary>
    public static string? ResolveModuleName(string importLine)
    {
        string? moduleName = null;
        try
        {
            string line = importLine.Trim().ToLower();
            // Regex: ^import-module\s+ - Remove Import-Module prefix
            line = Regex.Replace(line, @"^import-module\s+", "", RegexOptions.IgnoreCase);

            // Regex: -name\s+["']?([^"']+)["']? - Handle -Name parameter
            var m = Regex.Match(line, @"-name\s+[""']?([^""']+)[""']?");
            if (m.Success)
                moduleName = m.Groups[1].Value.Trim();
            // Regex: ["']?([^"']+\\)?([^"']+\.psm1)["']? - Handle path-based import
            else if ((m = Regex.Match(line, @"[""']?([^""']+\\)?([^""']+\.psm1)[""']?")).Success)
                moduleName = Regex.Replace(m.Groups[2].Value, @"\.psm1$", "");
            // Regex: ^([a-zA-Z0-9_-]+) - Simple module name
            else if ((m = Regex.Match(line, @"^([a-zA-Z0-9_-]+)")).Success)
                moduleName = m.Groups[1].Value.Trim();

            if (moduleName != null)
            {
                moduleName = moduleName.Trim().Trim('\'', '"');
                moduleName = Regex.Replace(moduleName, @"\.psm1$", "");
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error resolving module name from: {importLine} - {ex.Message}", LogLevel.WARN);
        }
        return moduleName;
    }

    /// <summary>
    /// Builds index of all .psm1 modules in the repository.
    /// Converted line-by-line from Build-ModuleIndex (lines 2520-2595)
    /// </summary>
    public static Dictionary<string, (string FilePath, List<string> Functions)> BuildModuleIndex(string modulesFolder = "")
    {
        var moduleIndex = new Dictionary<string, (string FilePath, List<string> Functions)>(StringComparer.OrdinalIgnoreCase);

        try
        {
            if (string.IsNullOrWhiteSpace(modulesFolder))
            {
                string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
                string[] possiblePaths = {
                    Path.Combine(optPath, "src", "DedgePsh", "_Modules"),
                    Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository", "DedgePsh", "_Modules")
                };
                foreach (string path in possiblePaths)
                {
                    if (Directory.Exists(path)) { modulesFolder = path; break; }
                }
            }

            if (string.IsNullOrWhiteSpace(modulesFolder) || !Directory.Exists(modulesFolder))
            {
                Logger.LogMessage("Modules folder not found. Skipping module index.", LogLevel.WARN);
                return moduleIndex;
            }

            Logger.LogMessage($"Building module index from: {modulesFolder}", LogLevel.INFO);
            var psm1Files = Directory.GetFiles(modulesFolder, "*.psm1", SearchOption.AllDirectories);
            Logger.LogMessage($"Found {psm1Files.Length} module file(s)", LogLevel.INFO);

            foreach (string psm1File in psm1Files)
            {
                try
                {
                    string moduleName = Path.GetFileNameWithoutExtension(psm1File);
                    var functions = GetModuleFunctions(psm1File);
                    moduleIndex[moduleName] = (psm1File, functions);
                    Logger.LogMessage($"Indexed module: {moduleName} ({functions.Count} functions)", LogLevel.DEBUG);
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"Error indexing module {Path.GetFileName(psm1File)}: {ex.Message}", LogLevel.WARN);
                }
            }
            Logger.LogMessage($"Module index built: {moduleIndex.Count} modules", LogLevel.INFO);
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error building module index: {ex.Message}", LogLevel.WARN);
        }
        return moduleIndex;
    }

    #endregion

    #region Variable Resolution (lines 2597-2675)

    private static string GetPs1DecodedConcat(string decodeString, Dictionary<string, string> assignmentsDict)
    {
        if (decodeString.Contains("||"))
        {
            string[] temp1 = decodeString.Split("||");
            string returnString = "";
            foreach (string item in temp1)
            {
                string resolved = GetPs1VariableValue(item, assignmentsDict);
                returnString += resolved;
            }
            return returnString;
        }
        return decodeString;
    }

    /// <summary>
    /// Multi-pass variable decoding with local assignments.
    /// Converted line-by-line from Decode (lines 2611-2626)
    /// </summary>
    private static string Decode(string decodeString, Dictionary<string, string> localAssignmentsDict, Dictionary<string, string> assignmentsDict)
    {
        if (decodeString.Contains(" "))
        {
            decodeString = decodeString.Replace("(", "( ").Replace(")", " )");
            string[] temp1 = decodeString.Split(" ");
            string returnString = "";
            foreach (string item in temp1)
            {
                returnString = returnString.Trim();
                string resolved = GetLocalVariableValue(item, localAssignmentsDict, assignmentsDict);
                returnString += " " + resolved.Trim();
            }
            return returnString.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
                .Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
                .Replace("( ", "(").Replace(" )", ")");
        }
        return decodeString;
    }

    private static string GetPs1VariableValue(string decodeString, Dictionary<string, string> assignmentsDict)
    {
        if (decodeString.Length > 0)
        {
            string key = decodeString.Trim().ToUpper();
            if (assignmentsDict.ContainsKey(key))
            {
                string returnString = assignmentsDict[key];
                return GetPs1DecodedConcat(returnString, assignmentsDict);
            }
            return decodeString;
        }
        return decodeString;
    }

    private static string GetLocalVariableValue(string decodeString, Dictionary<string, string> localAssignmentsDict, Dictionary<string, string> assignmentsDict)
    {
        if (decodeString.Length > 0 && decodeString.Contains("$"))
        {
            string key = decodeString.Trim().ToUpper();
            if (localAssignmentsDict.ContainsKey(key))
            {
                string returnString = "(" + localAssignmentsDict[key] + ")";
                return GetPs1DecodedConcat(returnString, assignmentsDict);
            }
            return decodeString;
        }
        return decodeString;
    }

    #endregion

    #region Test-Ps1Function / Find-Ps1FunctionCode (lines 2378-2397, 3428-3462)

    /// <summary>
    /// Validates if a line declares a PowerShell function.
    /// Converted line-by-line from Test-Ps1Function (lines 2378-2397)
    /// Returns (isValid, functionName)
    /// </summary>
    private static (bool IsValid, string? FunctionName) TestPs1Function(string functionName, List<string> functionList)
    {
        if (!functionName.ToUpper().Contains("FUNCTION "))
            return (false, null);

        string functionTemp = functionName.ToUpper().Replace("{", " ").Replace("(", " (").Trim();
        string[] parts = functionTemp.Split(" ");
        if (parts.Length < 2)
            return (false, null);

        string temp1 = parts[1];
        if (functionList.Contains(temp1))
            return (true, temp1);

        return (false, null);
    }

    /// <summary>
    /// Extracts function code using bracket counting.
    /// Converted line-by-line from Find-Ps1FunctionCode (lines 3428-3462)
    /// </summary>
    private static List<MatchResult> FindPs1FunctionCode(List<MatchResult> array, string functionName)
    {
        bool foundStart = false;
        functionName = functionName.ToLower();
        var extractedElements = new List<MatchResult>();
        int startBracketCount = 0, endBracketCount = 0;

        foreach (var item in array)
        {
            if (item.Line.Trim().StartsWith("function ", StringComparison.OrdinalIgnoreCase) &&
                item.Line.ToUpper().Trim().Contains(functionName.ToUpper()))
            {
                foundStart = true;
                extractedElements = new List<MatchResult>();
            }
            if (foundStart)
            {
                startBracketCount += item.Line.Split('{').Length - 1;
                endBracketCount += item.Line.Split('}').Length - 1;
                extractedElements.Add(item);
                if (startBracketCount > 0 && startBracketCount == endBracketCount)
                {
                    foundStart = false;
                    break;
                }
            }
        }
        return extractedElements;
    }

    #endregion

    #region Write-Ps1Mmd (lines 3371-3426)

    /// <summary>
    /// Writes PS1-specific Mermaid content with extensive sanitization.
    /// Converted line-by-line from Write-Ps1Mmd (lines 3371-3426)
    /// </summary>
    private static void WritePs1Mmd(MermaidWriter mmdWriter, string mmdString)
    {
        if (string.IsNullOrEmpty(mmdString)) return;

        // Line 3377-3379
        mmdString = mmdString.Replace("\n", "<br/>").Replace("\r", "");
        mmdString = mmdString.Replace("__MAIN__", "main").Replace("__main__", "main");
        mmdString = Regex.Replace(mmdString, @"\s{2,}", " ");

        // Line 3380
        mmdString = mmdString.Replace("[system.io.file]:", "");

        // Line 3384-3396: Escape special characters
        mmdString = mmdString.Replace("\\", "/");
        mmdString = mmdString.Replace("$", "#");
        // Regex: \)\s*\) - Collapse nested closing parens
        mmdString = Regex.Replace(mmdString, @"\)\s*\)", ")");
        // Regex: \(\s*\( - Collapse nested opening parens
        mmdString = Regex.Replace(mmdString, @"\(\s*\(", "(");

        if (!mmdString.Contains("http"))
            mmdString = mmdString.Replace("&", " and ");

        mmdString = mmdString.Replace("|", " pipe ");

        // Line 3399-3400: Handle nested quotes
        mmdString = mmdString.Replace("= \"#", "= #").Replace("=  \"#", "= #");

        // Line 3403-3413: Truncate long parameters
        if (mmdString.Contains("parameters:") && mmdString.Length > 250)
        {
            int pos = mmdString.IndexOf("parameters:");
            string truncated = mmdString.Substring(0, Math.Min(pos + 60, mmdString.Length)) + "...";
            if (mmdString.Contains("(\""))
                truncated += "\")";
            else if (mmdString.Contains("[("))
                truncated += ")]";
            mmdString = truncated;
        }

        mmdWriter.WriteLine(mmdString);
    }

    #endregion

    #region New-Ps1Nodes (lines 2677-3140)

    /// <summary>
    /// Main node generation for PS1 - processes function code and generates Mermaid nodes.
    /// Converted line-by-line from New-Ps1Nodes (lines 2677-3140)
    /// </summary>
    private static void NewPs1Nodes(
        List<MatchResult> functionCode,
        List<MatchResult> fileContent,
        string functionName,
        MermaidWriter mmdWriter,
        string baseFileName,
        string htmlPath,
        List<string> functionList,
        List<string> functionList2,
        Dictionary<string, string> assignmentsDict,
        Dictionary<string, (string FilePath, List<string> Functions)>? moduleIndex,
        Dictionary<string, string> importedModules,
        List<string> sqlTableArray,
        List<string> htmlCallListCbl,
        List<string> htmlCallList)
    {
        var localAssignmentsDict = new Dictionary<string, string>();
        string currentSetLocation = "";
        int uniqueCounter = 0;

        foreach (var lineObject in functionCode)
        {
            if (lineObject == null || lineObject.Line == null) { uniqueCounter++; continue; }

            // Line 2693-2700: First iteration - source link
            if (uniqueCounter == 0)
            {
                int lineNum = lineObject.LineNumber > 0 ? lineObject.LineNumber : 1;
                string link = "https://Dedge.visualstudio.com/Dedge/_git/DedgePsh?path=" + htmlPath
                    + "&version=GBmain&line=" + lineNum + "&lineEnd=" + (lineNum + 1)
                    + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents#function-" + functionName.ToLower();
                string stmt = "click " + functionName.ToLower() + " \"" + link + "\" \"" + functionName.ToLower() + "\" _blank";
                WritePs1Mmd(mmdWriter, stmt);
                stmt = "style " + functionName.ToLower() + " stroke:dark-blue,stroke-width:3px";
                WritePs1Mmd(mmdWriter, stmt);
            }

            // Line 2701-2709: Track local assignments
            if (lineObject.Line.Trim().Contains("="))
            {
                string[] temp = lineObject.Line.Split('=');
                if (temp.Length >= 2)
                {
                    string key = temp[0].Trim().ToUpper();
                    try { localAssignmentsDict[key] = temp[1].Trim().Replace("\"", "'"); } catch { }
                }
            }

            uniqueCounter++;
            string line = lineObject.Line.Trim();
            if (line.Length == 0) continue;

            // Line 2722-2730: Handle Set-Location
            line = line.Replace("(", " ( ").Replace(")", " ) ").Replace("  ", " ");
            if (line.ToLower().StartsWith("set-location"))
            {
                currentSetLocation = line.ToLower().Replace("set-location", "").Trim();
                continue;
            }
            if (line.ToLower().StartsWith("."))
            {
                line = currentSetLocation.Trim() + line.ToLower().Substring(1).Trim();
            }

            // Line 2732-2790: Check function calls (local and module)
            bool anyHits = false;
            if (!line.ToUpper().Trim().StartsWith("FUNCTION "))
            {
                foreach (string item1 in line.Trim().Split(" "))
                {
                    try
                    {
                        string funcNameUpper = item1.ToUpper().Trim();
                        if (funcNameUpper.Length == 0) continue;

                        // Check local functions
                        if (functionList2.Contains(funcNameUpper))
                        {
                            string toNode = item1.ToLower();
                            if (functionName.ToUpper().Trim() == funcNameUpper) continue;
                            string stmt = functionName.Trim().ToLower() + " --call function--> " + toNode.Replace(" ", "_") + "(\"" + toNode + "\")";
                            WritePs1Mmd(mmdWriter, stmt);
                            anyHits = true;
                        }
                        // Check imported module functions
                        else if (importedModules.Count > 0 && moduleIndex != null)
                        {
                            foreach (var moduleName in importedModules.Keys)
                            {
                                if (moduleIndex.ContainsKey(moduleName))
                                {
                                    var moduleInfo = moduleIndex[moduleName];
                                    if (moduleInfo.Functions.Contains(funcNameUpper))
                                    {
                                        string moduleFilePath = importedModules[moduleName];
                                        string moduleFileName = Path.GetFileName(moduleFilePath);
                                        string toNode = functionName.Trim().ToLower() + "_call_" + funcNameUpper.ToLower().Replace("-", "_") + uniqueCounter;
                                        string mLink = "./" + moduleFileName + ".html#function-" + item1.ToLower();
                                        string stmt = functionName.Trim().ToLower() + " --call module function--> " + toNode + "{{\"" + item1.ToLower() + "\nfrom " + moduleName + "\"}}";
                                        WritePs1Mmd(mmdWriter, stmt);
                                        stmt = "click " + toNode + " \"" + mLink + "\" \"" + item1.ToLower() + "\" _blank";
                                        WritePs1Mmd(mmdWriter, stmt);
                                        stmt = "style " + toNode + " stroke:dark-green,stroke-width:3px";
                                        WritePs1Mmd(mmdWriter, stmt);
                                        anyHits = true;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                    catch { }
                }
            }
            if (anyHits) continue;

            string lineLowerTrimmed = line.Trim().ToLower();

            // Line 2792-2835: COBOL program invocation ('& run')
            if (lineLowerTrimmed.StartsWith("& run ") || lineLowerTrimmed.Contains("micro focus"))
            {
                string temp0 = line.ToLower().Replace("& run ", "").Replace("c:\\program files (x86)\\micro focus\\server 5.1\\bin\\run.exe", "").Replace("&", "").Trim();
                string temp1 = Decode(temp0, localAssignmentsDict, assignmentsDict);
                temp1 = Decode(temp1, localAssignmentsDict, assignmentsDict);
                temp1 = Decode(temp1, assignmentsDict, assignmentsDict);
                temp1 = Decode(temp1, assignmentsDict, assignmentsDict);
                temp1 = temp1.Replace("'", "").Replace("\"", "").Replace("((", "(").Replace("))", ")").Replace("  ", " ");

                string module, parms;
                try
                {
                    string[] temp3 = temp1.Split("\\");
                    string temp4 = temp3[temp3.Length - 1];
                    string[] temp5 = temp4.Split(" ");
                    parms = "parameters: " + temp4.Replace(temp5[0], "").Trim();
                    module = temp5[0] + ".cbl";
                    htmlCallListCbl.Add(module);
                }
                catch
                {
                    module = temp0.Trim().ToLower();
                    parms = "";
                }

                string toNode = functionName.Trim().ToLower() + "runcbl" + uniqueCounter;
                string stmt = functionName.Trim().ToLower() + " --run cobol program-->" + toNode + "(\"run cobol program\n" + module + "\n" + parms + "\")";
                WritePs1Mmd(mmdWriter, stmt);
                continue;
            }

            // Line 2837-2925: DB2 command handling
            if (lineLowerTrimmed.Contains("db2exportcsv.exe") || lineLowerTrimmed.Contains("db2cmd.exe"))
            {
                string temp1 = Decode(line, localAssignmentsDict, assignmentsDict);
                temp1 = Decode(temp1, assignmentsDict, assignmentsDict);
                temp1 = temp1.Replace("'", "").Replace("\"", "").Replace("((", "(").Replace("))", ")").Replace("  ", " ");

                // Try SQL extraction
                var sqlResult = SqlParseHelper.FindSqlStatementInDb2Command(line);
                if (sqlResult.SqlOperation != null && sqlResult.SqlTableNames.Count > 0)
                {
                    SqlParseHelper.WriteSqlTableNodes(mmdWriter, sqlResult, functionName.Trim().ToLower(), sqlTableArray);
                    continue;
                }

                // Regular DB2 command node
                string[] temp4 = temp1.Split(" ");
                int pos1 = temp4[0].ToLower().LastIndexOf("\\");
                string module, parms;
                if (pos1 > 0)
                {
                    module = temp1.Substring(pos1 + 1).Trim().Split(" ")[0];
                    parms = "parameters: " + temp1.Replace(temp4[0], "").Trim();
                }
                else
                {
                    module = temp1.Trim().Split(" ")[0];
                    parms = "";
                }

                string toNode = functionName.Trim().ToLower() + module + uniqueCounter;
                string stmt = functionName.Trim().ToLower() + " --call db2 command-->" + toNode + "(\"db2 command\n" + module + "\n" + parms + "\")";
                WritePs1Mmd(mmdWriter, stmt);
                continue;
            }

            // Line 2928-3051: Built-in functions and commands
            // Regex: ^(python|py|copy-item|move-item|...) - Match built-in PS commands
            if (Regex.IsMatch(lineLowerTrimmed, @"^(python |py |copy-item |move-item |remove-item |rename-item |\[system\.io\.file\]|set-content |(\( )?get-content |add-content |logtowkmon|log-start|log-write|log-finish|log-error|write-debug|write-logmessage|logmessage|logwrite|start-sleep|start-process|(\( )?get-childitem|out-file|git|cmd\.exe|push-location|pop-location|db2cmd\.exe |copy |new-item |write-output |invoke-webrequest |send-mailmessage|start-transcript|stop-transcript|import-module|install-windowsfeature|send-fkalert|invoke-expression)")
                || Regex.IsMatch(lineLowerTrimmed, @"(mmdc\.exe|utf8ansi|tilutf8\.exe)"))
            {
                string temp1 = Decode(line, localAssignmentsDict, assignmentsDict);
                temp1 = Decode(temp1, assignmentsDict, assignmentsDict);
                temp1 = Regex.Replace(temp1.Replace("'", "").Replace("\"", ""), @"\(\(|\)\)", "(");
                temp1 = Regex.Replace(temp1, @"\s{2,}", " ");

                string temp1Lower = temp1.ToLower();
                int pos1 = temp1Lower.IndexOf(" ");
                int pos2 = temp1Lower.IndexOf("(");
                int pos = (pos1 > 0 && pos2 > 0 && pos1 > pos2) ? pos2 : pos1;

                string module, parms;
                try
                {
                    module = line.Substring(0, Math.Max(pos, 1)).Trim().ToLower();
                    parms = "parameters: " + temp1.Substring(Math.Max(pos, 1)).Trim();
                }
                catch
                {
                    module = line.Trim().ToLower();
                    parms = "";
                }

                string sanitizedModule = Regex.Replace(module, @"[\s\(\)\[\]\{\}\|]", "_");
                sanitizedModule = Regex.Replace(sanitizedModule, @"__+", "_").Trim('_');
                string toNode = functionName.Trim().ToLower() + sanitizedModule + uniqueCounter;

                string optionsText;

                // Handle Import-Module
                if (module.ToLower().StartsWith("import-module") || lineLowerTrimmed.StartsWith("import-module"))
                {
                    string? resolvedModuleName = ResolveModuleName(line);
                    if (resolvedModuleName != null && moduleIndex != null && moduleIndex.ContainsKey(resolvedModuleName))
                    {
                        var moduleInfo = moduleIndex[resolvedModuleName];
                        string moduleFileName = Path.GetFileName(moduleInfo.FilePath);
                        importedModules[resolvedModuleName] = moduleInfo.FilePath;
                        if (!htmlCallList.Contains(moduleFileName))
                            htmlCallList.Add(moduleFileName);

                        string moduleDisplayName = resolvedModuleName + ".psm1";
                        toNode = functionName.Trim().ToLower() + "_import_" + resolvedModuleName.ToLower().Replace("-", "_") + uniqueCounter;
                        string stmt = functionName.Trim().ToLower() + " --import module-->" + toNode + "[[" + moduleDisplayName + "]]";
                        WritePs1Mmd(mmdWriter, stmt);
                        string mLink = "./" + moduleFileName + ".html";
                        stmt = "click " + toNode + " \"" + mLink + "\" \"" + moduleDisplayName + "\" _blank";
                        WritePs1Mmd(mmdWriter, stmt);
                        stmt = "style " + toNode + " stroke:dark-blue,stroke-width:4px";
                        WritePs1Mmd(mmdWriter, stmt);
                        continue;
                    }
                    module = "import-module\n" + (resolvedModuleName ?? "module");
                    optionsText = "import module";
                }
                else if (module.StartsWith("py"))
                {
                    string[] temp2 = temp1.Split(" ");
                    module = "python " + (temp2.Length > 1 ? temp2[1].Trim() : "");
                    parms = parms.Replace(temp2.Length > 1 ? temp2[1].Trim() : "", "").Replace("  ", " ").Trim();
                    optionsText = "call python script";
                }
                else if (module.Contains("git"))
                {
                    module = "git.exe\n" + module;
                    optionsText = "call git command";
                    toNode = functionName.Trim().ToLower() + "git" + uniqueCounter;
                }
                else if (module.Contains("tilutf8")) { module = "tilutf8\n" + module; optionsText = "call custom exe"; toNode = functionName.Trim().ToLower() + "tilutf8" + uniqueCounter; }
                else if (module.Contains("utf8ansi")) { module = "utf8ansi\n" + module; optionsText = "call custom exe"; toNode = functionName.Trim().ToLower() + "utf8ansi" + uniqueCounter; }
                else if (module.Contains("mmdc.exe")) { module = "mermaid executable\n" + module; optionsText = "call mermaid exe"; toNode = functionName.Trim().ToLower() + "mmdc" + uniqueCounter; }
                else if (line.Contains("|"))
                {
                    string[] temp5 = line.Trim().Split("|");
                    module = temp5[temp5.Length - 1].Trim();
                    optionsText = "call built-in function";
                    parms = "";
                    toNode = functionName.Trim().ToLower() + "callfuc" + uniqueCounter;
                }
                else if (line.StartsWith("copy ")) { optionsText = "call windows command"; }
                else { optionsText = "call built-in function"; }

                string stmtBuiltin = functionName.Trim().ToLower() + " --" + optionsText + "-->" + toNode + "(\"" + module + "\n" + parms + "\")";
                WritePs1Mmd(mmdWriter, stmtBuiltin);
                continue;
            }

            // Line 3053-3098: PowerShell script invocation (.ps1 files)
            if (line.Length > 3)
            {
                if ((lineLowerTrimmed.StartsWith(".") || lineLowerTrimmed.Contains(".ps1") || (line.Length > 3 && line.Substring(1, 2) == ":\\"))
                    && !lineLowerTrimmed.Contains("*.ps1"))
                {
                    string temp1 = Decode(line, localAssignmentsDict, assignmentsDict);
                    temp1 = temp1.Replace("'", "").Replace("\"", "").Replace("((", "(").Replace("))", ")").Replace("  ", " ");

                    string[] temp4 = temp1.Split(" ");
                    int pos1 = temp4[0].ToLower().LastIndexOf("\\");
                    string parms;

                    string temp2 = pos1 > 0 ? temp1.Substring(pos1 + 1).Trim() : temp1.Trim();
                    string[] temp3 = temp2.Split(" ");
                    parms = temp1.Trim().Replace(temp3[0], "").Trim();
                    string module = temp3[0].Trim().Replace("\\", "");

                    if (!module.ToLower().Contains(".ps1"))
                        module += ".ps1";
                    htmlCallList.Add(module);

                    string toNode = functionName.Trim().ToLower() + "pshcall" + uniqueCounter;
                    if (parms.Length > 0)
                        parms = "\nparameters: " + parms;
                    module = module.Replace("'", "").Replace("\"", "");
                    parms = parms.Replace("'", "").Replace("\"", "");

                    string stmt = functionName.Trim().ToLower() + " --call powershell script-->" + toNode + "(\"" + module + parms + "\")";
                    WritePs1Mmd(mmdWriter, stmt);
                    continue;
                }
            }

            // Line 3100-3137: Log unhandled lines (skip known patterns)
            if (!(line.Contains("=") || line.Trim() == "{" || line.Trim() == "}"
                || lineLowerTrimmed.Contains("catch ") || lineLowerTrimmed.Contains("continue")
                || lineLowerTrimmed.Contains("break") || lineLowerTrimmed.StartsWith("exit")
                || lineLowerTrimmed.Contains("try ") || lineLowerTrimmed.Contains("else")
                || lineLowerTrimmed.StartsWith("throw") || lineLowerTrimmed.StartsWith("default")
                || lineLowerTrimmed.Contains("write-host") || lineLowerTrimmed.Contains("write-logmessage")
                || lineLowerTrimmed.Contains("import-module") || lineLowerTrimmed.Contains("send-fkalert")
                || lineLowerTrimmed.Contains("install-windowsfeature") || lineLowerTrimmed.Contains("param (")
                || lineLowerTrimmed.StartsWith("function ") || lineLowerTrimmed.StartsWith("$")
                || lineLowerTrimmed.StartsWith(")") || lineLowerTrimmed.StartsWith("if ")
                || lineLowerTrimmed.StartsWith("if(") || lineLowerTrimmed.StartsWith("[")
                || lineLowerTrimmed.StartsWith("<") || lineLowerTrimmed.StartsWith(",\"")
                || lineLowerTrimmed.StartsWith("\"") || lineLowerTrimmed.StartsWith("'")
                || lineLowerTrimmed.StartsWith("switch") || lineLowerTrimmed.StartsWith("try")
                || lineLowerTrimmed.StartsWith("finally") || lineLowerTrimmed.StartsWith("catch")
                || lineLowerTrimmed.StartsWith("try{") || lineLowerTrimmed.StartsWith("return")))
            {
                Logger.LogMessage($"Unhandled line in module: {baseFileName}, in function: {functionName}, at line: {line.Trim()}", LogLevel.WARN);
            }
        }
    }

    #endregion

    #region Metadata and HTML Generation (lines 3142-3369)

    private static void NewPs1MmdLinks(MermaidWriter mmdWriter, string baseFileName, string htmlPath, List<MatchResult> sourceFile, List<string> functionList)
    {
        try
        {
            string link = "https://Dedge.visualstudio.com/Dedge/_git/DedgePsh?path=" + htmlPath;
            string baseName = baseFileName.ToLower().Split(".")[0];
            string stmt = "click " + baseName + " \"" + link + "\" \"" + baseName + "\" _blank";
            WritePs1Mmd(mmdWriter, stmt);

            foreach (var item in sourceFile)
            {
                if (item.Line.Trim().Length == 0) continue;
                var (isFunc, _) = TestPs1Function(item.Line.Trim(), functionList);
                if (isFunc)
                {
                    string funcLine = item.Line.Replace("--", "-").Replace(":", "").ToLower();
                    link = "https://Dedge.visualstudio.com/Dedge/_git/DedgePsh?path=" + htmlPath
                        + "&version=GBmain&line=" + item.LineNumber + "&lineEnd=" + (item.LineNumber + 1)
                        + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents";
                    stmt = "click " + funcLine + " \"" + link + "\" \"" + funcLine + "\" _blank";
                    WritePs1Mmd(mmdWriter, stmt);
                }
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in NewPs1MmdLinks: {ex.Message}", LogLevel.ERROR, ex);
        }
    }

    private static void GetPs1MetaData(
        string tmpRootFolder, string baseFileName, string outputFolder, string[] completeFileContent,
        string inputDbFileFolder, bool clientSideRender, MermaidWriter mmdWriter,
        List<string> functionList, List<string> htmlCallListCbl, List<string> htmlCallList, ref bool errorOccurred,
        bool generateHtml = false, string fullFileName = "")
    {
        string title = "";
        string htmlCreatedDateTime = "";
        var commentArray = new List<string>();
        var cblArray = new List<string>();
        var scriptArray = new List<string>();
        string htmlUseSql = "", htmlUseFtp = "", htmlUseWs = "";
        string functionsHtml = "";

        try
        {
            // Line 3188-3193: Extract title
            foreach (string line in completeFileContent)
            {
                if (Regex.IsMatch(line, "[A-Za-z]") && line.Trim().StartsWith("#")
                    && !line.ToLower().Trim().Contains(".ps1")
                    && !line.ToLower().Trim().Contains("geir")
                    && !line.ToLower().Trim().Contains("svein"))
                {
                    title = line.Replace("#", "").Replace("*/", "").Trim();
                    break;
                }
            }

            // Line 3196-3233: Parse changelog
            bool startCommentFound = false;
            int counter = 0;
            var rawComments = new List<string>();
            foreach (string line in completeFileContent)
            {
                counter++;
                if (counter > 100) break;
                if ((Regex.IsMatch(line, @"(19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])") ||
                     Regex.IsMatch(line, @"(0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}") ||
                     Regex.IsMatch(line, @"(19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])"))
                    && line.Trim().StartsWith("#"))
                {
                    startCommentFound = true;
                    rawComments.Add(line.Replace("#", "").Trim());
                }
                if (startCommentFound && !line.Trim().StartsWith("#"))
                    break;
            }

            foreach (string item in rawComments)
            {
                string newComment = item.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");
                string[] temp = newComment.Split(" ");
                if (string.IsNullOrEmpty(htmlCreatedDateTime))
                    htmlCreatedDateTime = temp[0];
                string tempComment = "<tr><td>" + temp[0] + "</td><td>" + (temp.Length > 1 ? temp[1] : "") + "</td><td>";
                string temp2 = newComment.Replace(temp[0] + " " + (temp.Length > 1 ? temp[1] : ""), "").Trim();
                commentArray.Add((tempComment + temp2 + "</td></tr>").Trim());
            }

            // Line 3235-3274: Load modul.csv
            string modulCsvPath = Path.Combine(inputDbFileFolder, "modul.csv");
            System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);
            if (File.Exists(modulCsvPath))
            {
                string[] csvLines = SourceFileCache.GetLines(modulCsvPath) ?? File.ReadAllLines(modulCsvPath, Encoding.UTF8);
                foreach (string cblItem in htmlCallListCbl)
                {
                    string cblUpper = cblItem.Replace(".cbl", "").ToUpper();
                    string cblSystem = "N/A", cblDesc = "N/A", cblType = "N/A";
                    foreach (string csvLine in csvLines)
                    {
                        string[] fields = csvLine.Split(';');
                        if (fields.Length > 5 && fields[2].Contains(cblUpper))
                        {
                            cblSystem = fields[1].Trim(); cblDesc = fields[3].Trim();
                            string typeCode = fields[4].Trim();
                            cblType = typeCode switch { "B" => "B - Batchprogram", "H" => "H - Main user interface", "S" => "S - Webservice", "V" => "V - Validation module for user interface", "A" => "A - Common module", "F" => "F - Search module for user interface", _ => typeCode };
                            break;
                        }
                    }
                    string link = "<a href=\"./" + cblItem.Trim() + ".html\">" + cblItem.Trim() + "</a>";
                    cblArray.Add("<tr><td>" + link + "</td><td>" + cblDesc + "</td><td>" + cblType + "</td><td>" + cblSystem + "</td></tr>");
                }
            }

            // Line 3276-3281: Script call list
            foreach (string item in htmlCallList)
            {
                string link = "<a href=\"./" + item.Trim() + ".html\">" + item.Trim() + "</a>";
                scriptArray.Add("<tr><td>" + link + "</td></tr>");
            }

            // Line 3283-3297: Function list HTML with anchors
            if (functionList.Count > 0)
            {
                foreach (string func in functionList)
                {
                    if (func != "__MAIN__" && func.Length > 0)
                    {
                        string anchorId = "function-" + func.ToLower();
                        functionsHtml += $"<a href='#{anchorId}' id='{anchorId}' class='function-anchor' style='display: inline-block; margin-right: 0.5rem; margin-bottom: 0.25rem; padding: 0.25rem 0.5rem; background: var(--bg-secondary); border-radius: 3px; text-decoration: none; color: var(--text-primary);'>{func}</a> ";
                    }
                }
            }
            if (string.IsNullOrWhiteSpace(functionsHtml))
                functionsHtml = "<span style='color: var(--text-secondary); font-style: italic;'>No functions found</span>";

            // Line 3302-3316: Usage flags
            if (completeFileContent.Any(l => l.ToLower().Contains("sqlexec"))) htmlUseSql = "checked";
            if (completeFileContent.Any(l => l.ToLower().Contains("ftpsetuser"))) htmlUseFtp = "checked";
            if (completeFileContent.Any(l => l.ToLower().Contains("invoke-webrequest"))) htmlUseWs = "checked";
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in GetPs1MetaData: {ex.Message}", LogLevel.ERROR, ex);
            errorOccurred = true;
        }

        // Line 3327-3367: Generate HTML
        string htmlFilename = Path.Combine(outputFolder, baseFileName + ".html");
        string templatePath = Path.Combine(outputFolder, "_templates");
        string mmdTemplateFilename = Path.Combine(templatePath, "ps1mmdtemplate.html");

        string templateContent = "";
        if (File.Exists(mmdTemplateFilename))
            templateContent = File.ReadAllText(mmdTemplateFilename, Encoding.UTF8);
        else
        {
            string sharedTemplatesFolder = ParserBase.GetAutodocTemplatesFolder();
            string sharedTemplatePath = Path.Combine(sharedTemplatesFolder, "ps1mmdtemplate.html");
            if (File.Exists(sharedTemplatePath))
                templateContent = File.ReadAllText(sharedTemplatePath, Encoding.UTF8);
            else { Logger.LogMessage($"Template not found: {mmdTemplateFilename}", LogLevel.ERROR); return; }
        }

        try
        {
            string doc = ParserBase.SetAutodocTemplate(templateContent, outputFolder);
            doc = doc.Replace("[title]", "AutoDoc Flowchart - Powershell Script - " + baseFileName.ToLower());
            doc = doc.Replace("[desc]", title);
            doc = doc.Replace("[generated]", DateTime.Now.ToString());
            doc = doc.Replace("[type]", "Powershell Script");
            doc = doc.Replace("[usesql]", htmlUseSql);
            doc = doc.Replace("[useftp]", htmlUseFtp);
            doc = doc.Replace("[usews]", htmlUseWs);
            doc = doc.Replace("[created]", htmlCreatedDateTime);
            doc = doc.Replace("[changelog]", string.Join("\n", commentArray));
            doc = doc.Replace("[calllist]", string.Join("\n", scriptArray));
            doc = doc.Replace("[calllistcbl]", string.Join("\n", cblArray));
            doc = doc.Replace("[diagram]", "./" + baseFileName + ".flow.svg");
            doc = doc.Replace("[sourcefile]", baseFileName.ToLower());
            doc = doc.Replace("[functionlist]", functionsHtml);
            doc = doc.Replace("[githistory]", GitStatsService.RenderHtmlRows(GitStatsService.GetStats(fullFileName, Path.GetDirectoryName(fullFileName) ?? "")));

            if (clientSideRender)
            {
                doc = doc.Replace("[flowmmd_content]", mmdWriter.GetContent());
                doc = doc.Replace("[sequencemmd_content]", "");
            }

            if (generateHtml)
            {
                File.WriteAllText(htmlFilename, doc, Encoding.UTF8);
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error generating HTML: {ex.Message}", LogLevel.ERROR, ex);
            errorOccurred = true;
        }

        // Write JSON result alongside HTML
        try
        {
            var jsonScripts = new List<ScriptRef>();
            foreach (string s in scriptArray)
            {
                var m = Regex.Match(s, @"href=""([^""]+)"">([^<]+)</a>");
                if (m.Success) jsonScripts.Add(new ScriptRef { Name = m.Groups[2].Value, Link = m.Groups[1].Value });
            }
            var jsonPrograms = new List<SubprogramRef>();
            foreach (string s in cblArray)
            {
                var m = Regex.Match(s, @"href=""([^""]+)"">([^<]+)</a></td><td>([^<]*)</td><td>([^<]*)</td><td>([^<]*)");
                if (m.Success) jsonPrograms.Add(new SubprogramRef { Module = m.Groups[2].Value, Description = m.Groups[3].Value, Type = m.Groups[4].Value, System = m.Groups[5].Value, Link = m.Groups[1].Value });
            }
            var jsonChangelog = new List<ChangeLogEntry>();
            foreach (string s in commentArray)
            {
                var m = Regex.Match(s, @"<td>([^<]*)</td><td>([^<]*)</td><td>([^<]*)");
                if (m.Success) jsonChangelog.Add(new ChangeLogEntry { Date = m.Groups[1].Value, User = m.Groups[2].Value, Comment = m.Groups[3].Value });
            }

            var jsonFunctions = functionList.Where(f => f != "__MAIN__" && f.Length > 0).ToList();

            var ps1Result = new Ps1Result
            {
                Type = "PS1",
                FileName = baseFileName,
                Title = "AutoDoc Flowchart - Powershell Script - " + baseFileName.ToLower(),
                Description = title,
                GeneratedAt = DateTime.Now.ToString("o"),
                SourceFile = baseFileName.ToLower(),
                Metadata = new Ps1Metadata
                {
                    UsesSql = htmlUseSql == "checked",
                    UsesFtp = htmlUseFtp == "checked",
                    UsesWebservice = htmlUseWs == "checked",
                    Created = htmlCreatedDateTime
                },
                Diagrams = new DiagramData
                {
                    FlowMmd = mmdWriter.GetContent()
                },
                CalledScripts = jsonScripts,
                CalledPrograms = jsonPrograms,
                ChangeLog = jsonChangelog,
                Functions = jsonFunctions
            };
            ps1Result.GitHistory = GitStatsService.GetStats(fullFileName, Path.GetDirectoryName(fullFileName) ?? "");
            JsonResultWriter.WriteResult(ps1Result, outputFolder, baseFileName);
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error writing JSON result for {baseFileName}: {ex.Message}", LogLevel.WARN);
        }
    }

    #endregion

    #region Start-Ps1Parse (lines 3480-3977)

    /// <summary>
    /// Main entry point for PowerShell file parsing.
    /// Converted line-by-line from Start-Ps1Parse (lines 3480-3977)
    /// </summary>
    public static string? StartPs1Parse(
        string sourceFile,
        bool show = false,
        string outputFolder = "",
        bool cleanUp = true,
        string tmpRootFolder = "",
        string srcRootFolder = "",
        bool clientSideRender = false,
        bool saveMmdFiles = false,
        bool generateHtml = false,
        Dictionary<string, (string FilePath, List<string> Functions)>? moduleIndex = null)
    {
        // Fall back to the global module index built by BatchRunner at startup
        moduleIndex ??= GlobalModuleIndex;

        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        if (string.IsNullOrEmpty(outputFolder)) outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
        if (string.IsNullOrEmpty(tmpRootFolder)) tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");
        if (string.IsNullOrEmpty(srcRootFolder)) srcRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");

        string baseFileName = Path.GetFileName(sourceFile);
        string fullFileName = sourceFile;
        string htmlPath = fullFileName.Replace(srcRootFolder, "").Replace("\\DedgePsh", "").Replace(baseFileName, "").Replace("\\", "%2F") + baseFileName;

        var importedModules = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        Logger.LogMessage($"Starting parsing of filename: {sourceFile}", LogLevel.INFO);

        // Validations
        if (baseFileName.Contains(" ")) { Logger.LogMessage($"Filename contains spaces: {baseFileName}", LogLevel.ERROR); return null; }
        if (!(baseFileName.ToLower().Contains(".ps1") || baseFileName.ToLower().Contains(".psm1"))) { Logger.LogMessage($"Invalid file type: {baseFileName}", LogLevel.ERROR); return null; }
        if (sourceFile.ToLower().Contains("\\fat\\") || sourceFile.ToLower().Contains("\\kat\\") || sourceFile.ToLower().Contains("\\vft\\"))
        { Logger.LogMessage($"Skipping file in KAT/FAT/VFT: {sourceFile}", LogLevel.INFO); return null; }

        DateTime startTime = DateTime.Now;
        string mmdFilename = Path.Combine(outputFolder, baseFileName + ".flow.mmd");
        string htmlFilename = Path.Combine(outputFolder, baseFileName + ".html");
        bool errorOccurred = false;
        var sqlTableArray = new List<string>();
        string inputDbFileFolder = Path.Combine(tmpRootFolder, "cobdok");

        Logger.LogMessage($"Started for: {baseFileName}", LogLevel.INFO);

        if (baseFileName.ToLower().Contains("parse.ps1"))
        { Logger.LogMessage($"Cannot create diagram on parser programs: {baseFileName}", LogLevel.INFO); return null; }

        string mmdHeader = "%%{ init: { 'flowchart': { 'curve': 'basis' } } }%%\nflowchart LR";
        var mmdWriter = new MermaidWriter(clientSideRender, mmdFilename, mmdHeader);
        string programName = Path.GetFileName(sourceFile).ToLower();

        var functionList = new List<string>();
        var functionList2 = new List<string>();
        var assignmentsDict = new Dictionary<string, string>();

        // Line 3610-3687: Read and preprocess source file
        string[] completeFileContent;
        var fileContent = new List<MatchResult>();

        if (!File.Exists(sourceFile)) { Logger.LogMessage($"File not found: {sourceFile}", LogLevel.ERROR); return null; }

        completeFileContent = SourceFileCache.GetLines(sourceFile) ?? File.ReadAllLines(sourceFile);
        string[] rawLines = SourceFileCache.GetLines(sourceFile) ?? File.ReadAllLines(sourceFile);

        // Preprocess: handle block comments, line continuations
        var testArray = new List<MatchResult>();
        bool isInBlock = false;
        bool accumulate = false;
        string accumulateText = "";
        int lineNum = 0;

        foreach (string rawLine in rawLines)
        {
            lineNum++;
            string processedLine = rawLine;

            // Handle block comments <# ... #>
            if (processedLine.Trim().StartsWith("<#")) { processedLine = processedLine.Replace("<#", ""); isInBlock = true; }
            if (processedLine.Trim().EndsWith("#>")) { processedLine = processedLine.Replace("#>", ""); isInBlock = false; }
            if (isInBlock) { processedLine = "# " + processedLine; }

            // Remove inline comments
            if (processedLine.Contains("#"))
            {
                int pos = processedLine.IndexOf("#");
                processedLine = processedLine.Substring(0, pos);
            }

            // Handle lone opening brace
            if (processedLine.Trim() == "{" && testArray.Count > 0)
            {
                testArray[testArray.Count - 1].Line += " {";
                processedLine = "";
            }

            // Handle line continuations (backtick)
            if (processedLine.Contains("`"))
            {
                if (!accumulate) { accumulateText = ""; accumulate = true; }
                int pos = processedLine.IndexOf("`");
                accumulateText += processedLine.Substring(0, pos).TrimEnd() + " ";
                processedLine = "";
            }
            else if (accumulate)
            {
                accumulateText += processedLine.Trim();
                processedLine = accumulateText;
                accumulate = false;
            }

            if (processedLine.Trim().Length > 0)
            {
                testArray.Add(new MatchResult { LineNumber = lineNum, Line = processedLine, Pattern = "" });
            }

            // Extract function names
            if (processedLine.ToLower().Trim().StartsWith("function"))
            {
                string tempItem = processedLine.ToUpper().Replace("FUNCTION ", "").Replace("{", "").Replace("(", " (").Split(" ")[0].Trim();
                if (!functionList.Contains(tempItem)) functionList.Add(tempItem);
                if (!functionList2.Contains(tempItem)) functionList2.Add(tempItem);
            }

            // Extract assignments
            if (processedLine.Trim().Contains("="))
            {
                string[] temp = processedLine.Split('=');
                if (temp.Length >= 2)
                {
                    string key = temp[0].Trim().ToUpper();
                    try { assignmentsDict[key] = temp[1].Trim().Replace("\"", "'"); } catch { }
                }
            }
        }
        fileContent = testArray;

        functionList.Add("__MAIN__");
        functionList2.Add("__MAIN__");

        // Initialize tracking lists
        var htmlCallListCbl = new List<string>();
        var htmlCallList = new List<string>();
        string currentParticipant = "";
        string currentFunctionName = "";
        int loopCounter = 0;
        string previousParticipant = "";
        var functionCodeExceptLoopCode = new List<MatchResult>();
        var mainCodeExceptLoopCode = new List<MatchResult>();
        int startBracketCount = 0, endBracketCount = 0;
        var loopLevel = new List<string>();
        var loopNodeContent = new List<string>();
        var loopCode = new List<List<MatchResult>>();
        var loopCodeStartBracketCount = new List<int>();
        var loopCodeEndBracketCount = new List<int>();

        // Line 3720-3904: Main processing loop
        foreach (var lineObject in fileContent)
        {
            string line = lineObject.Line;
            if (string.IsNullOrEmpty(line)) continue;

            // Track brackets
            if (line.Contains("{")) startBracketCount += line.Split('{').Length - 1;
            if (line.Contains("}")) endBracketCount += line.Split('}').Length - 1;

            // Check function/end-of-function
            var (isFunction, currentParticipantTemp) = TestPs1Function(line, functionList);
            bool isEndOfFunction = startBracketCount > 0 && startBracketCount == endBracketCount && line.Trim().StartsWith("}");
            previousParticipant = currentFunctionName;

            // Track loop brackets
            if (loopCounter > 0)
            {
                if (line.Contains("{") && loopCodeStartBracketCount.Count >= loopCounter)
                    loopCodeStartBracketCount[loopCounter - 1] += line.Split('{').Length - 1;
                if (line.Contains("}") && loopCodeEndBracketCount.Count >= loopCounter)
                    loopCodeEndBracketCount[loopCounter - 1] += line.Split('}').Length - 1;
            }

            // Check if loop ended (by bracket count)
            if (loopCounter > 0 && loopCodeStartBracketCount.Count >= loopCounter && loopCodeEndBracketCount.Count >= loopCounter)
            {
                if (loopCodeStartBracketCount[loopCounter - 1] > 0 && loopCodeStartBracketCount[loopCounter - 1] == loopCodeEndBracketCount[loopCounter - 1])
                {
                    NewPs1Nodes(loopCode[loopCounter - 1], fileContent, loopLevel[loopCounter - 1],
                        mmdWriter, baseFileName, htmlPath, functionList, functionList2, assignmentsDict,
                        moduleIndex, importedModules, sqlTableArray, htmlCallListCbl, htmlCallList);

                    try { loopLevel.RemoveAt(loopCounter - 1); } catch { }
                    try { loopNodeContent.RemoveAt(loopCounter - 1); } catch { }
                    try { loopCode.RemoveAt(loopCounter - 1); } catch { }
                    try { loopCodeStartBracketCount.RemoveAt(loopCounter - 1); } catch { }
                    try { loopCodeEndBracketCount.RemoveAt(loopCounter - 1); } catch { }
                    loopCounter--;
                }
            }

            // Function detection
            if (isFunction || (isEndOfFunction && currentParticipant != "__MAIN__"))
            {
                if (functionCodeExceptLoopCode.Count > 0)
                {
                    NewPs1Nodes(functionCodeExceptLoopCode, fileContent, previousParticipant,
                        mmdWriter, baseFileName, htmlPath, functionList, functionList2, assignmentsDict,
                        moduleIndex, importedModules, sqlTableArray, htmlCallListCbl, htmlCallList);
                }

                try
                {
                    currentParticipant = currentParticipantTemp?.Trim() ?? "__MAIN__";
                    currentFunctionName = currentParticipant;
                }
                catch { }

                loopLevel = new List<string>();
                loopNodeContent = new List<string>();
                loopCode = new List<List<MatchResult>>();
                loopCodeStartBracketCount = new List<int>();
                loopCodeEndBracketCount = new List<int>();
                loopCounter = 0;

                startBracketCount = line.Split('{').Length - 1;
                endBracketCount = 0;
                functionCodeExceptLoopCode = new List<MatchResult>();
            }

            bool skipLine = false;
            string lineTrimLower = line.Trim().ToLower();

            // Loop detection (for/foreach/do/while)
            if (lineTrimLower.StartsWith("for ") || lineTrimLower.StartsWith("for(")
                || lineTrimLower.StartsWith("foreach ") || lineTrimLower.StartsWith("foreach(")
                || lineTrimLower.StartsWith("do ") || lineTrimLower.StartsWith("do{") || lineTrimLower.StartsWith("do {")
                || lineTrimLower.StartsWith("while ") || lineTrimLower.StartsWith("while("))
            {
                loopCounter++;
                string tmpCurrent = string.IsNullOrEmpty(currentParticipant) ? "__MAIN__" : currentParticipant;
                string fromNode, toNode;

                if (loopCounter > 1 && loopLevel.Count >= loopCounter - 1)
                {
                    fromNode = loopLevel[loopCounter - 2];
                    toNode = loopLevel[loopCounter - 2] + loopCounter + "((" + loopLevel[loopCounter - 2] + loopCounter + "))";
                    loopLevel.Add(currentParticipant + "-loop" + loopCounter);
                }
                else
                {
                    fromNode = tmpCurrent;
                    toNode = tmpCurrent + "-loop((" + tmpCurrent + "-loop))";
                    toNode = toNode.Replace("$", "");
                    loopLevel.Add(tmpCurrent.Replace("$", "") + "-loop");
                }

                int bracketInLine = line.Split('{').Length - 1;
                loopCodeStartBracketCount.Add(bracketInLine);
                int endBracketInLine = line.Split('}').Length - 1;
                loopCodeEndBracketCount.Add(endBracketInLine);

                loopNodeContent.Add(toNode);
                loopCode.Add(new List<MatchResult>());

                try
                {
                    string stmt = fromNode.ToLower().Replace("$", "") + "--\"call\"-->" + toNode.ToLower();
                    WritePs1Mmd(mmdWriter, stmt);
                }
                catch { }
                skipLine = true;
            }

            // Accumulate lines
            if (!skipLine)
            {
                if (loopCounter > 0 && loopCode.Count >= loopCounter)
                {
                    loopCode[loopCounter - 1].Add(lineObject);
                }
                else
                {
                    if (string.IsNullOrEmpty(currentFunctionName) || currentFunctionName == "__MAIN__")
                        mainCodeExceptLoopCode.Add(lineObject);
                    else
                        functionCodeExceptLoopCode.Add(lineObject);
                }
            }
        }

        // Line 3908-3915: Program initiated node
        string initStmt = programName.Trim().ToLower() + "[[" + programName.Trim().ToLower() + "]] --initiated-->__main__(__main__)";
        WritePs1Mmd(mmdWriter, initStmt);
        initStmt = "style " + programName.Trim().ToLower() + " stroke:red,stroke-width:4px";
        WritePs1Mmd(mmdWriter, initStmt);
        string initLink = "https://Dedge.visualstudio.com/Dedge/_git/DedgePsh?path=" + htmlPath;
        initStmt = "click " + programName.Trim().ToLower() + " \"" + initLink + "\" \"" + programName.Trim().ToLower() + "\" _blank";
        WritePs1Mmd(mmdWriter, initStmt);

        // Line 3918: Process main code
        NewPs1Nodes(mainCodeExceptLoopCode, fileContent, "__MAIN__",
            mmdWriter, baseFileName, htmlPath, functionList, functionList2, assignmentsDict,
            moduleIndex, importedModules, sqlTableArray, htmlCallListCbl, htmlCallList);

        // Line 3921: Source code links
        NewPs1MmdLinks(mmdWriter, baseFileName, htmlPath, fileContent, functionList);

        // Line 3924: Execution path diagram
        bool programInUse = false;
        string findPath = Path.Combine(srcRootFolder, "DedgePsh");
        (programInUse, var returnArray) = ExecutionPathHelper.FindAutoDocExecutionPaths(
            findPath, new[] { "*.ps1", "*.bat", "*.cs", "*.psm1", "*.rex" }, baseFileName, programInUse, srcRootFolder);
        foreach (string item in returnArray) WritePs1Mmd(mmdWriter, item);
        if (!programInUse) Logger.LogMessage($"Program is never called from any other program or script: {baseFileName}", LogLevel.INFO);

        // Line 3927-3929: SVG generation
        if (!clientSideRender)
            ExecutionPathHelper.GenerateSvgFile(mmdFilename);

        // Line 3932-3933: Metadata
        if (!errorOccurred)
        {
            GetPs1MetaData(tmpRootFolder, baseFileName, outputFolder, completeFileContent,
                inputDbFileFolder, clientSideRender, mmdWriter, functionList, htmlCallListCbl, htmlCallList, ref errorOccurred,
                generateHtml, fullFileName);
        }

        // Save MMD
        if (saveMmdFiles)
        {
            string flowMmdOutputPath = Path.Combine(outputFolder, baseFileName + ".mmd");
            File.WriteAllLines(flowMmdOutputPath, mmdWriter.GetContentList(), Encoding.UTF8);
            Logger.LogMessage($"Saved flow MMD file: {flowMmdOutputPath}", LogLevel.INFO);
        }

        // Log result
        DateTime endTime = DateTime.Now;
        TimeSpan timeDiff = endTime - startTime;
        string dummyFile = Path.Combine(outputFolder, baseFileName + ".err");
        string jsonFilePath = Path.Combine(outputFolder, baseFileName + ".json");
        bool htmlWasGenerated = File.Exists(htmlFilename) || File.Exists(jsonFilePath);

        if (htmlWasGenerated)
        {
            if (File.Exists(dummyFile)) try { File.Delete(dummyFile); } catch { }
            Logger.LogMessage($"Time elapsed: {timeDiff.Seconds}", LogLevel.INFO);
            Logger.LogMessage(errorOccurred ? $"Completed with warnings: {fullFileName}" : $"Completed successfully: {fullFileName}",
                errorOccurred ? LogLevel.WARN : LogLevel.INFO);
            return htmlFilename;
        }
        else
        {
            Logger.LogMessage("*******************************************************************************", LogLevel.ERROR);
            Logger.LogMessage($"Failed - HTML not generated: {sourceFile}", LogLevel.ERROR);
            Logger.LogMessage("*******************************************************************************", LogLevel.ERROR);
            File.WriteAllText(dummyFile, $"Error: HTML file was not generated for {baseFileName}");
            return null;
        }
    }

    #endregion
}
