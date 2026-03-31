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
/// BAT Parser - complete line-by-line translation from AutoDocFunctions.psm1
/// Functions translated:
///   Add-BatExternalProcess          (lines 1152-1172)
///   New-BatProcessExecutionDiagram  (lines 1174-1255)
///   Get-BatMmdExecutionPathDiagram  (lines 1257-1272)
///   Test-BatFunction                (lines 1274-1289)
///   Get-BatConcatValue              (lines 1291-1304)
///   Get-BatQuoteValue               (lines 1306-1319)
///   Get-BatSubstrValue              (lines 1321-1339)
///   Get-BatVariableValue            (lines 1341-1353)
///   New-BatNodes                    (lines 1355-1767)
///   Write-BatMmd                    (lines 1769-1804)
///   Get-BatFunctionCode             (lines 1806-1839)
///   Get-BatMetaData                 (lines 1841-2009)
///   Start-BatParse                  (lines 2013-2355)
/// </summary>
public static class BatParser
{
    /// <summary>
    /// External process tracking entry.
    /// Converted from Add-BatExternalProcess script-level hashtable (lines 1152-1172)
    /// </summary>
    private class ExternalProcess
    {
        public string Type { get; set; } = "";   // DB2, PowerShell, COBOL, REXX, WindowsCmd
        public string Name { get; set; } = "";
        public string Details { get; set; } = "";
    }

    /// <summary>
    /// Match result class for Select-String equivalent.
    /// </summary>
    private class MatchResult
    {
        public int LineNumber { get; set; }
        public string Line { get; set; } = "";
        public string Pattern { get; set; } = "";
    }

    #region Variable Resolution Chain (lines 1291-1353)

    /// <summary>
    /// Handles variable concatenation with || operator.
    /// Converted line-by-line from Get-BatConcatValue (lines 1291-1304)
    /// </summary>
    private static string GetBatConcatValue(string decodeString, Dictionary<string, string> assignmentsDict)
    {
        // Line 1292: Check for || operator
        if (decodeString.Contains("||"))
        {
            // Line 1293: Split on ||
            string[] temp1 = decodeString.Split("||");
            string returnString = "";
            // Line 1295-1297: Resolve each part
            foreach (string item in temp1)
            {
                string resolved = GetBatVariableValue(item, assignmentsDict);
                returnString += resolved;
            }
            return returnString;
        }
        // Line 1300-1302
        return decodeString;
    }

    /// <summary>
    /// Handles quoted values and variable substitution.
    /// Converted line-by-line from Get-BatQuoteValue (lines 1306-1319)
    /// </summary>
    private static string GetBatQuoteValue(string decodeString, Dictionary<string, string> assignmentsDict)
    {
        // Line 1307: Check for single quotes
        if (decodeString.Contains("'"))
        {
            // Line 1308: Split on '
            string[] temp1 = decodeString.Split("'");
            string returnString = "";
            // Line 1310-1312: Resolve each part
            foreach (string item in temp1)
            {
                string resolved = GetBatVariableValue(item, assignmentsDict);
                returnString += resolved;
            }
            return returnString;
        }
        return decodeString;
    }

    /// <summary>
    /// Handles SUBSTR function calls.
    /// Converted line-by-line from Get-BatSubstrValue (lines 1321-1339)
    /// </summary>
    private static string GetBatSubstrValue(string decodeString)
    {
        // Line 1322: Check for substr
        if (decodeString.ToLower().Contains("substr"))
        {
            // Line 1324: Split on "substr"
            string[] temp1 = decodeString.ToLower().Split("substr");
            string returnString = "";
            // Line 1326-1333: Process each part
            foreach (string item in temp1)
            {
                string processed = item;
                if (processed != null && processed.Contains("("))
                {
                    // Line 1328-1330: Extract first argument
                    processed = processed.Replace("(", "").Replace(")", "");
                    string temp2 = processed.Split(",")[0];
                    processed = temp2;
                }
                returnString += processed;
            }
            return returnString;
        }
        return decodeString;
    }

    /// <summary>
    /// Resolves variable values from assignments dictionary.
    /// Converted line-by-line from Get-BatVariableValue (lines 1341-1353)
    /// </summary>
    private static string GetBatVariableValue(string decodeString, Dictionary<string, string> assignmentsDict)
    {
        // Line 1342: Check length
        if (decodeString.Length > 0)
        {
            string returnString = decodeString;
            // Line 1344: Look up in assignments dict
            string key = decodeString.Trim().ToUpper();
            if (assignmentsDict.ContainsKey(key))
            {
                // Line 1345: Get value
                returnString = assignmentsDict[key];
                // Line 1346: Recursively resolve concatenation
                returnString = GetBatConcatValue(returnString, assignmentsDict);
            }
            return returnString;
        }
        return decodeString;
    }

    #endregion

    #region Test-BatFunction (lines 1274-1289)

    /// <summary>
    /// Validates if a string is a valid BAT function name.
    /// Converted line-by-line from Test-BatFunction (lines 1274-1289)
    /// </summary>
    private static bool TestBatFunction(string functionName, List<string> batFunctions)
    {
        // Line 1277: Must start with ':'
        if (!functionName.StartsWith(":"))
            return false;

        // Line 1280: Remove ':' and uppercase
        string functionTemp = functionName.Replace(":", "").ToUpper().Trim();

        // Line 1282: Check if in functions list
        return batFunctions.Contains(functionTemp);
    }

    #endregion

    #region Get-BatFunctionCode (lines 1806-1839)

    /// <summary>
    /// Extracts code lines for a specific function.
    /// Converted line-by-line from Get-BatFunctionCode (lines 1806-1839)
    /// </summary>
    private static List<string> GetBatFunctionCode(string[] array, string functionName, List<string> batFunctions)
    {
        bool foundStart = false;
        try
        {
            // Line 1811: Uppercase
            functionName = functionName.ToUpper();
        }
        catch
        {
            // Line 1813-1814
            return new List<string>();
        }

        var extractedElements = new List<string>();
        int lineNumber = 0;

        // Line 1820-1837: Loop through array
        foreach (string objectItem in array)
        {
            string item = objectItem;
            lineNumber++;

            // Line 1824: Check for function start
            if (!foundStart && (item.ToUpper().Trim().StartsWith(functionName.ToUpper()) || functionName == ":__MAIN__"))
            {
                foundStart = true;
                extractedElements = new List<string>();
            }
            else if (foundStart)
            {
                // Line 1829: Check if next function boundary
                if (TestBatFunction(item, batFunctions))
                {
                    foundStart = false;
                    break;
                }
                else
                {
                    // Line 1834: Add line
                    extractedElements.Add(item);
                }
            }
        }
        return extractedElements;
    }

    #endregion

    #region Write-BatMmd (lines 1769-1804)

    /// <summary>
    /// Writes BAT-specific Mermaid content with sanitization.
    /// Converted line-by-line from Write-BatMmd (lines 1769-1804)
    /// </summary>
    private static void WriteBatMmd(MermaidWriter mmdWriter, string mmdString)
    {
        // Line 1772-1778: Null/empty check
        if (string.IsNullOrEmpty(mmdString) || mmdString.Trim().Length == 0)
            return;

        try
        {
            // Line 1782: Replace literal newlines with <br/> for Mermaid compatibility
            mmdString = mmdString.Replace("\n", "<br/>").Replace("\r", "");

            // Line 1783: Handle __MAIN__ prefix
            mmdString = mmdString.Replace(":__MAIN__", "main").Replace(":__main__", "main");

            // Line 1784-1786: Handle colon prefix
            if (mmdString.Length > 0 && mmdString[0] == ':')
                mmdString = "_" + mmdString.Substring(1);

            // Line 1787-1795: Replace colons in specific contexts
            if (mmdString.Contains(">:"))
                mmdString = mmdString.Replace(">:", ">_");
            if (mmdString.Contains("click :"))
                mmdString = mmdString.Replace("click :", "click _");
            if (mmdString.Contains("style :"))
                mmdString = mmdString.Replace("style :", "style _");
        }
        catch
        {
            // Line 1796-1798: Silently continue on error
        }

        // Line 1801: Normalize multiple spaces
        mmdString = mmdString.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");

        // Line 1803: Write via WriteMmdCommon
        mmdWriter.WriteLine(mmdString);
    }

    #endregion

    #region Add-BatExternalProcess / New-BatProcessExecutionDiagram (lines 1152-1255)

    /// <summary>
    /// Generates a Mermaid diagram showing all external process invocations.
    /// Converted line-by-line from New-BatProcessExecutionDiagram (lines 1174-1255)
    /// </summary>
    private static string NewBatProcessExecutionDiagram(string scriptName, List<ExternalProcess> externalProcesses)
    {
        // Line 1181-1182: Return placeholder if no processes
        if (externalProcesses == null || externalProcesses.Count == 0)
            return "flowchart LR\n    noprocess[No external processes detected]";

        var mmdContent = new List<string>();

        // Line 1186-1187: Header
        mmdContent.Add("%%{ init: { 'flowchart': { 'curve': 'basis' } } }%%");
        mmdContent.Add("flowchart LR");

        // Line 1190-1195: Add main script node with safe Mermaid node ID
        // Regex: [^a-zA-Z0-9_] - Replace any non-alphanumeric/underscore chars with underscore
        string scriptNode = Regex.Replace(scriptName, @"[^a-zA-Z0-9_]", "_");
        if (Regex.IsMatch(scriptNode, @"^[0-9]"))
            scriptNode = "_" + scriptNode;

        mmdContent.Add($"    {scriptNode}[[\"{scriptName}\"]]");
        mmdContent.Add($"    style {scriptNode} stroke:#7c3aed,stroke-width:3px");

        // Line 1198: Group processes by type
        var groupedProcesses = externalProcesses.GroupBy(p => p.Type);

        int nodeCounter = 0;
        foreach (var group in groupedProcesses)
        {
            // Line 1202-1208: Type label
            string typeLabel = group.Key switch
            {
                "DB2" => "DB2 Commands",
                "PowerShell" => "PowerShell Scripts",
                "COBOL" => "COBOL Programs",
                "REXX" => "REXX Scripts",
                "WindowsCmd" => "Windows Commands",
                _ => group.Key
            };

            // Line 1211-1227: Shape characters by type
            string typeShape = group.Key switch
            {
                "DB2" => "[(",
                "PowerShell" => "{{",
                "COBOL" => "[[",
                "REXX" => "([",
                "WindowsCmd" => "(",
                _ => "("
            };

            string typeShapeEnd = group.Key switch
            {
                "DB2" => ")]",
                "PowerShell" => "}}",
                "COBOL" => "]]",
                "REXX" => "])",
                "WindowsCmd" => ")",
                _ => ")"
            };

            // Line 1229-1236: Color by type
            string typeColor = group.Key switch
            {
                "DB2" => "#10b981",
                "PowerShell" => "#3b82f6",
                "COBOL" => "#f59e0b",
                "REXX" => "#8b5cf6",
                "WindowsCmd" => "#6b7280",
                _ => "#6b7280"
            };

            // Line 1239: Get unique process names
            var uniqueProcesses = group.Select(p => p.Name).Distinct();

            // Line 1241-1251: Generate nodes
            foreach (string processName in uniqueProcesses)
            {
                nodeCounter++;
                string nodeId = $"proc{nodeCounter}";
                // Line 1244-1246: Sanitize name
                string safeName = Regex.Replace(processName, @"[""\n\r]", " ");
                safeName = Regex.Replace(safeName, @"\s+", " ");
                if (safeName.Length > 50)
                    safeName = safeName.Substring(0, 47) + "...";

                // Line 1249-1250
                mmdContent.Add($"    {scriptNode} --\"{group.Key}\"--> {nodeId}{typeShape}\"{safeName}\"{typeShapeEnd}");
                mmdContent.Add($"    style {nodeId} stroke:{typeColor},stroke-width:2px");
            }
        }

        return string.Join("\n", mmdContent);
    }

    #endregion

    #region Get-BatMmdExecutionPathDiagram (lines 1257-1272)

    /// <summary>
    /// Generates execution path diagram for a BAT file.
    /// Converted line-by-line from Get-BatMmdExecutionPathDiagram (lines 1257-1272)
    /// </summary>
    private static void GetBatMmdExecutionPathDiagram(
        MermaidWriter mmdWriter,
        string srcRootFolder,
        string baseFileName)
    {
        // Line 1259-1260
        bool programInUse = false;

        // Line 1262: Find execution paths in *.ps1, *.bat, *.cs, *.psm1, *.rex, *.cbl files
        (programInUse, var returnArray) = ExecutionPathHelper.FindAutoDocExecutionPaths(
            srcRootFolder,
            new[] { "*.ps1", "*.bat", "*.cs", "*.psm1", "*.rex", "*.cbl" },
            baseFileName,
            programInUse,
            srcRootFolder);

        // Line 1265-1267: Write each path entry
        foreach (string item in returnArray)
        {
            WriteBatMmd(mmdWriter, item);
        }

        // Line 1269-1271: Log if not used
        if (!programInUse)
        {
            Logger.LogMessage($"Program is never called from any other program or script: {baseFileName}", LogLevel.INFO);
        }
    }

    #endregion

    #region New-BatNodes (lines 1355-1767)

    /// <summary>
    /// Main node generation function - processes function code and generates Mermaid nodes.
    /// Converted line-by-line from New-BatNodes (lines 1355-1767)
    /// </summary>
    private static void NewBatNodes(
        List<MatchResult> functionCode,
        List<string> fileContent,
        string functionName,
        MermaidWriter mmdWriter,
        string batBaseFileName,
        List<string> batFunctions,
        Dictionary<string, string> assignmentsDict,
        List<ExternalProcess> externalProcesses,
        List<string> sqlTableArray,
        List<string> htmlCallListCbl,
        List<string> htmlCallList)
    {
        // Line 1358-1360: Default function name
        if (string.IsNullOrEmpty(functionName))
            functionName = "__MAIN__";

        bool skipLine = false;
        int uniqueCounter = 0;

        // Line 1364: Iterate through function code
        foreach (var lineObject in functionCode)
        {
            // Line 1365-1371: First iteration - add source code link and style
            if (uniqueCounter == 0)
            {
                // Line 1366-1367: Azure DevOps source code search link
                string link = "https://Dedge.visualstudio.com/Dedge/_search?action=contents&text="
                    + batBaseFileName.ToLower() + "&type=code&filters=ProjectFilters%7BDedge%7D";
                string statement = "click " + functionName.ToLower() + " \"" + link + "\" \"" + functionName.ToLower() + "\" _blank";
                WriteBatMmd(mmdWriter, statement);

                // Line 1369-1370
                statement = "style " + functionName.ToLower() + " stroke:dark-blue,stroke-width:3px";
                WriteBatMmd(mmdWriter, statement);
            }
            uniqueCounter++;
            string line = lineObject.Line.Trim();

            // Line 1375-1377: Skip empty lines
            if (line.Length == 0)
                continue;

            // Line 1378-1389: Skip list (currently empty in PS, but structure preserved)
            string[] skipListItems = Array.Empty<string>();
            foreach (string item in skipListItems)
            {
                if (line.ToLower().Contains(item))
                {
                    skipLine = true;
                    break;
                }
            }
            if (skipLine) { skipLine = false; continue; }

            // Line 1390-1394: Handle drive change (single letter followed by colon, e.g., "D:")
            if (line.Trim().ToLower().EndsWith(":") && line.Trim().Length == 2)
            {
                string stmt = functionName.Trim().ToLower() + " --windows command-->"
                    + functionName.Trim().ToLower() + "_changedrive" + uniqueCounter
                    + "(\"change drive\n" + line.Trim().ToUpper() + "\")";
                WriteBatMmd(mmdWriter, stmt);
                continue;
            }

            // --- Line 1396-1464: DB2 command handling ---
            string lineLower = line.ToLower();
            if (lineLower.StartsWith("db2 ") || lineLower.StartsWith("db2cmd ") || lineLower.StartsWith("start db2cmd "))
            {
                string temp1 = GetBatQuoteValue(line, assignmentsDict);
                temp1 = GetBatConcatValue(temp1, assignmentsDict);

                string itemName = functionName.Trim().ToLower() + "_db2" + uniqueCounter;
                temp1 = temp1.Replace("\"", "").Replace("'", "").Trim();
                string[] temp3 = temp1.Split(" ");
                string temp1Display = temp3[0] + "\n" + temp1.Replace(temp3[0], "").Trim();

                // Line 1407: Try to extract SQL
                var sqlResult = SqlParseHelper.FindSqlStatementInDb2Command(line);

                if (sqlResult.SqlOperation != null && sqlResult.SqlTableNames.Count > 0)
                {
                    // Line 1410-1454: SQL detected - create SQL table nodes
                    SqlParseHelper.WriteSqlTableNodes(mmdWriter, sqlResult, functionName.Trim().ToLower(), sqlTableArray);
                    // Track for process execution diagram
                    externalProcesses.Add(new ExternalProcess { Type = "DB2", Name = temp3[0], Details = temp1Display.Replace("\n", " ") });
                    continue;
                }

                // Line 1457-1458: No SQL - regular DB2 command node
                string stmt = functionName.Trim().ToLower() + " --DB2 command-->" + itemName + "(\"" + temp1Display + "\")";
                WriteBatMmd(mmdWriter, stmt);
                // Line 1462
                externalProcesses.Add(new ExternalProcess { Type = "DB2", Name = temp3[0], Details = temp1Display.Replace("\n", " ") });
                continue;
            }

            // --- Line 1467-1479: Windows commands (COPY, PAUSE, REG, etc.) ---
            // Regex: ^(copy|pause|reg|...) followed by space - Match common Windows commands
            if (Regex.IsMatch(lineLower, @"^(copy|pause|reg|regedit|notepad|del|path|set|start|net|ren|xcopy|adfind|postiecgi|postie|robocopy) "))
            {
                string temp1 = GetBatQuoteValue(line, assignmentsDict);
                temp1 = GetBatConcatValue(temp1, assignmentsDict);

                string[] temp3 = temp1.Split(" ");
                string temp2 = temp3[0] + "\n" + temp1.Replace(temp3[0], "").Trim();
                // Line 1474: Format paths on new lines
                temp2 = temp2.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
                    .Replace("\\\\", "\n \\\\").Replace("C:\\", "\n C:\\")
                    .Replace(">>", "\n >>").Replace("N:\\", "\n N:\\");

                string stmt = functionName.Trim().ToLower() + " --windows command-->"
                    + functionName.Trim().ToLower() + "_copy" + uniqueCounter
                    + "(\"" + temp2.Replace("'", "").Replace("\"", "") + "\")";
                WriteBatMmd(mmdWriter, stmt);
                continue;
            }

            // --- Line 1480-1523: PowerShell invocation ---
            if (lineLower.StartsWith("powershell.exe ") || lineLower.StartsWith("pwsh.exe ")
                || lineLower.StartsWith("@powershell ") || lineLower.StartsWith("psexec "))
            {
                string temp1 = GetBatQuoteValue(line, assignmentsDict);
                temp1 = GetBatConcatValue(temp1, assignmentsDict);

                string[] temp3 = temp1.Split(" ");
                string temp2 = temp3[0] + "\n" + temp1.Replace(temp3[0], "").Trim();
                temp2 = temp2.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ")
                    .Replace("\\\\", "\n \\\\").Replace("C:\\", "\n C:\\")
                    .Replace(">>", "\n >>").Replace("N:\\", "\n N:\\");

                // Line 1488-1500: Extract PowerShell script name
                int pos = temp1.ToLower().IndexOf(".ps1");
                string parms = (pos >= 0 && pos + 4 < temp1.Length) ? temp1.Substring(pos + 4).Trim() : "";
                string temp4 = string.IsNullOrEmpty(parms) ? line.Trim() : line.Trim().Replace(parms, "").Trim();
                int posBack = temp4.LastIndexOf("\\");
                if (posBack == -1) posBack = temp4.LastIndexOf(" ");
                string powershellScriptName = (posBack >= 0) ? temp4.Substring(posBack + 1).Trim() : temp4;
                parms = parms.Replace("'", "").Replace("\"", "");
                powershellScriptName = powershellScriptName.Replace("'", "").Replace("\"", "");

                if (!string.IsNullOrEmpty(parms))
                    powershellScriptName += "\n" + parms;

                string psNameOrig = powershellScriptName;
                powershellScriptName = powershellScriptName.Replace("'", "").Replace("\"", "");

                // Line 1511-1518: Write nodes
                string stmt = functionName.Trim().ToLower() + " --powershell command-->" + psNameOrig + "(\"" + powershellScriptName + "\")";
                WriteBatMmd(mmdWriter, stmt);

                string psLink = "./" + powershellScriptName + ".html";
                stmt = "click " + psNameOrig + " \"" + psLink + "\" \"" + psNameOrig + "\" _blank";
                WriteBatMmd(mmdWriter, stmt);
                stmt = "style " + psNameOrig + " stroke:dark-blue,stroke-width:4px";
                WriteBatMmd(mmdWriter, stmt);

                externalProcesses.Add(new ExternalProcess { Type = "PowerShell", Name = powershellScriptName });
                continue;
            }

            // --- Line 1524-1552: RUN command (COBOL program) ---
            if (lineLower.StartsWith("run "))
            {
                string temp1 = GetBatQuoteValue(line, assignmentsDict);
                temp1 = GetBatConcatValue(temp1, assignmentsDict);
                temp1 = temp1.ToUpper().Trim().Replace("RUN", "").Trim()
                    .Replace("  ", " ").Replace("'", "").Replace("\"", "");

                string[] temp2 = temp1.Split(" ");
                string tempProgramName = temp2[0].ToLower().Trim() + ".cbl";

                string displayName;
                if (temp2.Length > 1)
                    displayName = "\"" + tempProgramName + "\nparameters: " + temp1.Replace(temp2[0], "").Trim() + "\"";
                else
                    displayName = "\"" + tempProgramName + "\"";

                htmlCallListCbl.Add(tempProgramName);
                string stmt = functionName.Trim().ToLower() + " --start cobol program-->"
                    + functionName.Trim().ToLower() + "_run" + uniqueCounter + "[[" + displayName + "]]";
                WriteBatMmd(mmdWriter, stmt);

                string runItemName = functionName.Trim().ToLower() + "_run" + uniqueCounter;
                string cblLink = "./" + tempProgramName + ".html";
                stmt = "click " + runItemName + " \"" + cblLink + "\" \"" + runItemName + "\" _blank";
                WriteBatMmd(mmdWriter, stmt);
                stmt = "style " + runItemName + " stroke:dark-blue,stroke-width:4px";
                WriteBatMmd(mmdWriter, stmt);

                externalProcesses.Add(new ExternalProcess { Type = "COBOL", Name = tempProgramName });
                continue;
            }

            // --- Line 1554-1577: REXX script invocation ---
            if (lineLower.Contains("rexx "))
            {
                string temp1 = line.ToLower().Replace("call ", "").Replace("rexx ", "").Trim();
                temp1 = GetBatQuoteValue(temp1, assignmentsDict);
                temp1 = GetBatConcatValue(temp1, assignmentsDict);

                string rexItemName = functionName.Trim().ToLower() + "_rexxrun" + uniqueCounter;
                string rexFilename = temp1.Trim().ToLower() + ".rex";
                if (rexFilename.Contains(" "))
                    rexFilename = temp1.Trim().ToLower().Split(" ")[0] + ".rex";

                htmlCallList.Add(rexFilename);
                string stmt = functionName.Trim().ToLower() + " --start rexx script-->" + rexItemName + "[[" + rexFilename + "]]";
                WriteBatMmd(mmdWriter, stmt);

                string rexLink = "./" + rexFilename + ".html";
                stmt = "click " + rexItemName + " \"" + rexLink + "\" \"" + rexItemName + "\" _blank";
                WriteBatMmd(mmdWriter, stmt);
                stmt = "style " + rexItemName + " stroke:dark-blue,stroke-width:4px";
                WriteBatMmd(mmdWriter, stmt);

                externalProcesses.Add(new ExternalProcess { Type = "REXX", Name = rexFilename });
                continue;
            }

            // --- Line 1579-1611: GOTO handling ---
            if (lineLower.Contains("goto "))
            {
                int pos = lineLower.IndexOf("goto ");
                string temp1 = lineLower.Substring(pos + 5).Trim();
                temp1 = GetBatQuoteValue(temp1, assignmentsDict);
                temp1 = GetBatConcatValue(temp1, assignmentsDict);
                string[] temp2 = temp1.Split(" ");

                string tempFunctionName;
                // Line 1586-1598: Handle %next% pattern
                if (temp2[0] == "%next%")
                {
                    int counter = 0;
                    foreach (string item in batFunctions)
                    {
                        counter++;
                        if (item.Contains(functionName.Trim().ToUpper().Replace(":", "")))
                            break;
                    }
                    tempFunctionName = (counter < batFunctions.Count) ? batFunctions[counter].ToLower().Trim() : temp2[0];
                }
                else
                {
                    tempFunctionName = temp2[0].ToLower().Trim();
                }

                string parms = "";
                if (temp2.Length > 1)
                    parms = "\"\nparameters: " + temp1.Replace(temp2[1], "").Trim() + "\"";

                string options = "goto function";
                string stmt = functionName.Trim().ToLower() + " --" + options + "-->" + tempFunctionName
                    + "[[\"" + tempFunctionName + parms + "\"]]";
                WriteBatMmd(mmdWriter, stmt);
                continue;
            }

            // --- Line 1613-1644: CALL handling ---
            if (lineLower.StartsWith("call "))
            {
                string temp1 = GetBatQuoteValue(line, assignmentsDict);
                temp1 = GetBatConcatValue(temp1, assignmentsDict);
                string[] temp2 = temp1.Split(" ");
                string tempProgramName = (temp2.Length > 1) ? temp2[1].ToLower().Trim() : temp2[0].ToLower().Trim();

                string displayName;
                if (temp2.Length > 2)
                    displayName = "\"" + tempProgramName + "\nparameters: " + temp1.Replace(temp2[2], "").Trim() + "\"";
                else
                    displayName = "\"" + tempProgramName + "\"";

                string callItemName = functionName.Trim().ToLower() + "_call" + uniqueCounter;
                htmlCallList.Add(tempProgramName);

                string stmt = functionName.Trim().ToLower() + " --call windows batch script-->" + callItemName + "[[" + displayName + "]]";
                WriteBatMmd(mmdWriter, stmt);

                // Line 1636-1642: Add click handler if .bat file
                if (temp1.Contains(".bat"))
                {
                    string batLink = "./" + tempProgramName + ".html";
                    stmt = "click " + callItemName + " \"" + batLink + "\" \"" + callItemName + "\" _blank";
                    WriteBatMmd(mmdWriter, stmt);
                    stmt = "style " + callItemName + " stroke:dark-blue,stroke-width:4px";
                    WriteBatMmd(mmdWriter, stmt);
                }
                continue;
            }

            // --- Line 1645-1659: DIR command ---
            if (lineLower.Contains("dir "))
            {
                string temp1 = GetBatQuoteValue(line, assignmentsDict);
                temp1 = GetBatConcatValue(temp1, assignmentsDict);
                string[] temp3 = temp1.Split(" ");
                string temp2 = temp3[0] + "\n" + temp1.Replace(temp3[0], "").Trim();

                string stmt = functionName.Trim().ToLower() + " --windows command-->"
                    + functionName.Trim().ToLower() + "_ren" + uniqueCounter
                    + "(\"" + temp2.Replace("'", "").Replace("\"", "") + "\")";
                WriteBatMmd(mmdWriter, stmt);
                continue;
            }

            // --- Line 1661-1675: ECHO command ---
            if (lineLower.StartsWith("echo") || lineLower.StartsWith("@echo"))
            {
                string temp1 = GetBatQuoteValue(line, assignmentsDict);
                temp1 = GetBatConcatValue(temp1, assignmentsDict);
                string[] temp3 = temp1.Split(" ");
                string temp2 = temp3[0] + "\n" + temp1.Replace(temp3[0], "").Trim();

                string stmt = functionName.Trim().ToLower() + " --windows command-->"
                    + functionName.Trim().ToLower() + "_echo" + uniqueCounter
                    + "(\"" + temp2.Replace("'", "").Replace("\"", "") + "\")";
                WriteBatMmd(mmdWriter, stmt);
                continue;
            }

            // --- Line 1677-1681: Direct function call ---
            if (batFunctions.Contains(line.ToUpper().Trim()))
            {
                string stmt = functionName.Trim().ToLower() + " --call--> " + line.ToLower().Replace(" ", "_")
                    + "(\"" + line.ToLower() + "\")";
                WriteBatMmd(mmdWriter, stmt);
                continue;
            }

            // --- Line 1683-1744: SqlExec command ---
            if (lineLower.Contains("sqlexec"))
            {
                string temp1 = GetBatQuoteValue(line, assignmentsDict);
                temp1 = GetBatConcatValue(temp1, assignmentsDict);

                string sqlItemName = functionName.Trim().ToLower() + "_sqlexec" + uniqueCounter;
                temp1 = temp1.Trim().ToLower().Replace("sqlexec", "'").Trim();

                // Line 1691: Try to extract SQL
                var sqlResult = SqlParseHelper.FindSqlStatementInDb2Command(line);

                if (sqlResult.SqlOperation != null && sqlResult.SqlTableNames.Count > 0)
                {
                    SqlParseHelper.WriteSqlTableNodes(mmdWriter, sqlResult, functionName.Trim().ToLower(), sqlTableArray);
                    continue;
                }

                // Line 1742: No SQL - regular SqlExec node
                string stmt = functionName.Trim().ToLower() + " --DB2 sqlExec command-->" + sqlItemName + "(\"" + temp1 + "\")";
                WriteBatMmd(mmdWriter, stmt);
                continue;
            }

            // --- Line 1747-1761: Batch script file path detection ---
            if ((lineLower.Contains(":\\") || lineLower.Contains("\\\\")) && lineLower.Contains(".bat"))
            {
                string batItemName = functionName.Trim().ToLower() + "runbatch_" + uniqueCounter;
                string stmt = functionName.Trim().ToLower() + " --\"start windows batch script\"-->"
                    + batItemName + "[[\"" + line.Trim() + "\"]]";
                WriteBatMmd(mmdWriter, stmt);

                string[] temp = lineLower.Split("\\");
                string temp1 = temp[temp.Length - 1];

                string batLink = "./" + temp1 + ".html";
                stmt = "click " + batItemName + " \"" + batLink + "\" \"" + batItemName + "\" _blank";
                WriteBatMmd(mmdWriter, stmt);
                stmt = "style " + batItemName + " stroke:dark-blue,stroke-width:4px";
                WriteBatMmd(mmdWriter, stmt);
                continue;
            }

            // --- Line 1763-1765: Log unhandled lines ---
            if (!(line.StartsWith(":") || lineLower.StartsWith("rem ") || lineLower.StartsWith("runc ") || lineLower.Contains("zip ")))
            {
                Logger.LogMessage($"Unhandled line in module: {batBaseFileName}, in function: {functionName}, at line: {line}", LogLevel.WARN);
            }
        }
    }

    #endregion

    #region Get-BatMetaData (lines 1841-2009)

    /// <summary>
    /// Generates metadata and HTML output for the BAT file.
    /// Converted line-by-line from Get-BatMetaData (lines 1841-2009)
    /// </summary>
    private static void GetBatMetaData(
        string tmpRootFolder,
        string baseFileName,
        string outputFolder,
        string[] completeFileContent,
        string inputDbFileFolder,
        bool clientSideRender,
        MermaidWriter mmdWriter,
        List<ExternalProcess> externalProcesses,
        List<string> htmlCallListCbl,
        List<string> htmlCallList,
        ref bool errorOccurred,
        bool generateHtml = false,
        string sourceFile = "")
    {
        string title = "No description found";
        string htmlCreatedDateTime = "";
        var commentArray = new List<string>();
        var cblArray = new List<string>();
        var scriptArray = new List<string>();
        string htmlUseSql = "";
        string htmlUseRex = "";

        try
        {
            // Line 1846-1851: Extract title from first comment line
            foreach (string line in completeFileContent)
            {
                if (Regex.IsMatch(line, "[A-Za-z]") && line.StartsWith("#"))
                {
                    title = line.Replace("#", "").Trim();
                    break;
                }
            }

            // Line 1852-1902: Parse changelog comments (lines starting with #, containing dates)
            bool startCommentFound = false;
            var rawComments = new List<string>();
            foreach (string line in completeFileContent)
            {
                // Regex for date patterns:
                //   (19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])  - yyyyMMdd
                //   (0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}  - dd.MM.yyyy
                //   (19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])    - yyyy-MM-dd
                if ((Regex.IsMatch(line, @"(19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])") ||
                     Regex.IsMatch(line, @"(0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}") ||
                     Regex.IsMatch(line, @"(19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])"))
                    && line.Contains("#"))
                {
                    startCommentFound = true;
                }
                if (startCommentFound && line.Contains("*/"))
                {
                    rawComments.Add(line.Replace("#", "").Trim());
                }
                if (startCommentFound && !line.Contains("#"))
                    break;
            }

            // Line 1867-1902: Process comments into HTML table rows
            string newComment = "";
            foreach (string item in rawComments)
            {
                if (item.Trim().Contains("-----------") || item.Trim().Contains("**********") || item.Trim().Contains("=========="))
                    break;

                if (Regex.IsMatch(item, @"(19|20)\d{2}(0[1-9]|1[012])(0[1-9]|[12]\d|3[01])") ||
                    Regex.IsMatch(item, @"(0[1-9]|[12]\d|3[01])\.(0[1-9]|1[012])\.(19|20)\d{2}") ||
                    Regex.IsMatch(item, @"(19|20)\d{2}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01])"))
                {
                    if (newComment.Length > 0)
                    {
                        newComment = newComment.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");
                        string[] temp = newComment.Split(" ");
                        if (string.IsNullOrEmpty(htmlCreatedDateTime))
                            htmlCreatedDateTime = temp[0];
                        string tempComment = "<tr><td>" + temp[0] + "</td><td>" + (temp.Length > 1 ? temp[1] : "") + "</td><td>";
                        string temp2 = newComment.Replace(temp[0] + " " + (temp.Length > 1 ? temp[1] : ""), "").Trim();
                        commentArray.Add((tempComment + temp2 + "</td></tr>").Trim());
                    }
                    newComment = item;
                }
                else
                {
                    newComment += " " + item.Trim();
                }
            }
            // Flush last comment
            if (newComment.Length > 0)
            {
                newComment = newComment.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");
                string[] temp = newComment.Split(" ");
                string tempComment = "<tr><td>" + temp[0] + "</td><td>" + (temp.Length > 1 ? temp[1] : "") + "</td><td>";
                string temp2 = newComment.Replace(temp[0] + " " + (temp.Length > 1 ? temp[1] : ""), "").Trim();
                commentArray.Add((tempComment + temp2 + "</td></tr>").Trim());
            }

            // Line 1904-1931: Load modul.csv for COBOL program metadata
            string modulCsvPath = Path.Combine(inputDbFileFolder, "modul.csv");
            if (File.Exists(modulCsvPath))
            {
                string[] csvLines = SourceFileCache.GetLines(modulCsvPath) ?? File.ReadAllLines(modulCsvPath, Encoding.UTF8);
                foreach (string cblItem in htmlCallListCbl)
                {
                    string cblUpper = cblItem.Replace(".cbl", "").ToUpper();
                    string cblSystem = "N/A";
                    string cblDesc = "N/A";
                    string cblType = "N/A";

                    // Search CSV for matching module
                    foreach (string csvLine in csvLines)
                    {
                        string[] fields = csvLine.Split(';');
                        if (fields.Length > 5 && fields[2].Contains(cblUpper))
                        {
                            cblSystem = fields[1].Trim();
                            cblDesc = fields[3].Trim();
                            string typeCode = fields[4].Trim();
                            cblType = typeCode switch
                            {
                                "B" => "B - Batchprogram",
                                "H" => "H - Main user interface",
                                "S" => "S - Webservice",
                                "V" => "V - Validation module for user interface",
                                "A" => "A - Common module",
                                "F" => "F - Search module for user interface",
                                _ => typeCode
                            };
                            break;
                        }
                    }

                    string link = "<a href=\"./" + cblItem.Trim() + ".html\">" + cblItem.Trim() + "</a>";
                    cblArray.Add("<tr><td>" + link + "</td><td>" + cblDesc + "</td><td>" + cblType + "</td><td>" + cblSystem + "</td></tr>");
                }
            }

            // Line 1933-1939: Build script call list
            var uniqueCallList = htmlCallList.Distinct().OrderBy(x => x).ToList();
            foreach (string item in uniqueCallList)
            {
                string link = "<a href=\"./" + item.Trim() + ".html\">" + item.Trim() + "</a>";
                scriptArray.Add("<tr><td>" + link + "</td></tr>");
            }

            // Line 1943-1952: Check for DB2 and REXX usage
            if (completeFileContent.Any(l => l.ToLower().Contains("db2 ")))
                htmlUseSql = "checked";
            if (completeFileContent.Any(l => l.ToLower().Contains("rexx")))
                htmlUseRex = "checked";
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in GetBatMetaData: {ex.Message}", LogLevel.ERROR, ex);
            errorOccurred = true;
        }

        // Line 1962-2008: Generate HTML file (in finally block)
        string htmlFilename = Path.Combine(outputFolder, baseFileName + ".html");
        string templatePath = Path.Combine(outputFolder, "_templates");
        string mmdTemplateFilename = Path.Combine(templatePath, "batmmdtemplate.html");
        string myDescription = "AutoDoc Flowchart - Windows Batch Script - " + baseFileName.ToLower();

        // Try to load template
        string templateContent = "";
        if (File.Exists(mmdTemplateFilename))
        {
            templateContent = File.ReadAllText(mmdTemplateFilename, Encoding.UTF8);
        }
        else
        {
            string sharedTemplatesFolder = ParserBase.GetAutodocTemplatesFolder();
            string sharedTemplatePath = Path.Combine(sharedTemplatesFolder, "batmmdtemplate.html");
            if (File.Exists(sharedTemplatePath))
                templateContent = File.ReadAllText(sharedTemplatePath, Encoding.UTF8);
            else
            {
                Logger.LogMessage($"Template not found: {mmdTemplateFilename}", LogLevel.ERROR);
                return;
            }
        }

        try
        {
            // Line 1973: Apply shared CSS and common URL replacements
            string doc = ParserBase.SetAutodocTemplate(templateContent, outputFolder);

            // Line 1976-1987: Page-specific replacements
            doc = doc.Replace("[title]", myDescription);
            doc = doc.Replace("[desc]", title);
            doc = doc.Replace("[generated]", DateTime.Now.ToString());
            doc = doc.Replace("[type]", "Windows Batch Script");
            doc = doc.Replace("[usesql]", htmlUseSql);
            doc = doc.Replace("[userex]", htmlUseRex);
            doc = doc.Replace("[created]", htmlCreatedDateTime);
            doc = doc.Replace("[changelog]", string.Join("\n", commentArray));
            doc = doc.Replace("[calllist]", string.Join("\n", scriptArray));
            doc = doc.Replace("[calllistcbl]", string.Join("\n", cblArray));
            doc = doc.Replace("[diagram]", "./" + baseFileName + ".flow.svg");
            doc = doc.Replace("[sourcefile]", baseFileName.ToLower());
            doc = doc.Replace("[githistory]", GitStatsService.RenderHtmlRows(GitStatsService.GetStats(sourceFile, Path.GetDirectoryName(sourceFile) ?? "")));

            // Line 1990-2005: Client-side rendering - embed MMD content
            if (clientSideRender)
            {
                string flowMmdContent = "";
                if (mmdWriter.MmdFilename != null && File.Exists(mmdWriter.MmdFilename))
                    flowMmdContent = File.ReadAllText(mmdWriter.MmdFilename);
                else
                    flowMmdContent = mmdWriter.GetContent();

                doc = doc.Replace("[flowmmd_content]", flowMmdContent);
                doc = doc.Replace("[sequencemmd_content]", "");

                // Line 1999: Generate process execution diagram
                string processMmdContent = NewBatProcessExecutionDiagram(baseFileName, externalProcesses);
                doc = doc.Replace("[processmmd_content]", processMmdContent);
            }
            else
            {
                doc = doc.Replace("[processmmd_content]", "flowchart LR\n    noprocess[Process diagram requires client-side rendering]");
            }

            // Line 2007: Write HTML file
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
                // Extract name from HTML: <tr><td><a href="./item.html">item</a></td></tr>
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

            string flowMmdContent = "";
            if (mmdWriter.MmdFilename != null && File.Exists(mmdWriter.MmdFilename))
                flowMmdContent = File.ReadAllText(mmdWriter.MmdFilename);
            else
                flowMmdContent = mmdWriter.GetContent();

            var batResult = new BatResult
            {
                Type = "BAT",
                FileName = baseFileName,
                Title = "AutoDoc Flowchart - Windows Batch Script - " + baseFileName.ToLower(),
                Description = title,
                GeneratedAt = DateTime.Now.ToString("o"),
                SourceFile = baseFileName.ToLower(),
                Metadata = new BatMetadata
                {
                    UsesSql = htmlUseSql == "checked",
                    UsesRexx = htmlUseRex == "checked",
                    Created = htmlCreatedDateTime
                },
                Diagrams = new DiagramData
                {
                    FlowMmd = flowMmdContent,
                    ProcessMmd = NewBatProcessExecutionDiagram(baseFileName, externalProcesses)
                },
                CalledScripts = jsonScripts,
                CalledPrograms = jsonPrograms,
                ChangeLog = jsonChangelog
            };
            batResult.GitHistory = GitStatsService.GetStats(sourceFile, Path.GetDirectoryName(sourceFile) ?? "");
            JsonResultWriter.WriteResult(batResult, outputFolder, baseFileName);
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error writing JSON result for {baseFileName}: {ex.Message}", LogLevel.WARN);
        }
    }

    #endregion

    #region Start-BatParse (lines 2013-2355)

    /// <summary>
    /// Main entry point for Windows Batch file parsing.
    /// Converted line-by-line from Start-BatParse (lines 2013-2355)
    /// </summary>
    public static string? StartBatParse(
        string sourceFile,
        bool show = false,
        string outputFolder = "",
        bool cleanUp = true,
        string tmpRootFolder = "",
        string srcRootFolder = "",
        bool clientSideRender = false,
        bool saveMmdFiles = false,
        bool generateHtml = false)
    {
        // Line 2057-2063: Default folders
        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        if (string.IsNullOrEmpty(outputFolder))
            outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
        if (string.IsNullOrEmpty(tmpRootFolder))
            tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");
        if (string.IsNullOrEmpty(srcRootFolder))
            srcRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");

        // Line 2065-2067: Initialize base filename
        string batBaseFileName = Path.GetFileName(sourceFile);

        // Line 2070-2074: Sanitize filename for Mermaid node IDs
        // Regex: ^[^a-zA-Z_] - Check if first char is not letter/underscore
        string batSafeFileName = batBaseFileName;
        if (Regex.IsMatch(batSafeFileName, @"^[^a-zA-Z_]"))
            batSafeFileName = "_" + batSafeFileName;
        // Regex: [^a-zA-Z0-9_] - Replace all non-alphanumeric/underscore
        batSafeFileName = Regex.Replace(batSafeFileName, @"[^a-zA-Z0-9_]", "_");

        // Line 2077: Initialize external process tracking
        var externalProcesses = new List<ExternalProcess>();

        Logger.LogMessage($"Starting parsing of filename: {sourceFile}", LogLevel.INFO);

        // Line 2082-2090: Validate filename
        if (batBaseFileName.Contains(" "))
        {
            Logger.LogMessage($"Filename is not valid. Contains spaces: {batBaseFileName}", LogLevel.ERROR);
            return null;
        }
        if (!batBaseFileName.ToLower().Contains(".bat"))
        {
            Logger.LogMessage($"Filetype is not valid for parsing of Windows Batch script (.bat): {batBaseFileName}", LogLevel.ERROR);
            return null;
        }

        // Line 2092-2103: Initialize variables
        DateTime startTime = DateTime.Now;
        string mmdFilename = Path.Combine(outputFolder, batBaseFileName + ".flow.mmd");
        string htmlFilename = Path.Combine(outputFolder, batBaseFileName + ".html");
        bool errorOccurred = false;
        var sqlTableArray = new List<string>();
        string inputDbFileFolder = Path.Combine(tmpRootFolder, "cobdok");

        Logger.LogMessage($"Started for: {batBaseFileName}", LogLevel.INFO);

        // Line 2108-2112: Initialize MMD header
        string mmdHeader = "%%{ init: { 'flowchart': { 'curve': 'basis' } } }%%\nflowchart LR";
        var mmdWriter = new MermaidWriter(clientSideRender, mmdFilename, mmdHeader);

        // Line 2114-2119: Set program name and safe node ID
        string programName = Path.GetFileName(sourceFile).ToLower();
        // Regex: [^a-zA-Z0-9_] - Replace non-alphanumeric for safe node ID
        string safeNodeId = Regex.Replace(programName, @"[^a-zA-Z0-9_]", "_");
        if (Regex.IsMatch(safeNodeId, @"^[0-9]"))
            safeNodeId = "_" + safeNodeId;

        // Line 2121-2134: Read source file
        string[] fileContentOriginal;
        string[] completeFileContent;

        System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);

        if (File.Exists(sourceFile))
        {
            fileContentOriginal = SourceFileCache.GetLines(sourceFile) ?? File.ReadAllLines(sourceFile, Encoding.GetEncoding(1252));
            completeFileContent = (string[])fileContentOriginal.Clone();

            // Line 2126-2129: Remove content between /* and */
            string test = string.Join("¤", fileContentOriginal);
            // Regex: /\*.*?\*/ with Singleline - Remove block comments (non-greedy)
            test = Regex.Replace(test, @"/\*.*?\*/", "", RegexOptions.Singleline);
            fileContentOriginal = test.Split("¤");
        }
        else
        {
            Logger.LogMessage($"File not found: {sourceFile}", LogLevel.ERROR);
            return null;
        }

        // Line 2139-2152: Extract relevant code content using Select-String equivalent
        var workContent = new List<MatchResult>();

        // Line 2142: Patterns to match
        // Regex patterns: ^:.*    - Lines starting with colon (function labels)
        //                 CALL    - Call commands
        //                 DEL     - Delete commands
        //                 RUN     - COBOL run commands
        //                 etc.
        string[] patterns = { @"^:.*", "CALL ", "DEL ", "RUN ", "DIR ", "REXX ", "DB2 ", "COPY ", "XCOPY ",
                              "REN ", "ADFIND ", "SET ", "GOTO ", "ECHO ", @"\.PS1", "PWSH", "PSEXEC" };

        var workContent2 = new List<MatchResult>();
        for (int i = 0; i < fileContentOriginal.Length; i++)
        {
            string line = fileContentOriginal[i];
            foreach (string pattern in patterns)
            {
                if (Regex.IsMatch(line, pattern, RegexOptions.IgnoreCase))
                {
                    workContent2.Add(new MatchResult { LineNumber = i + 1, Line = line, Pattern = pattern });
                    break;
                }
            }
        }

        // Line 2145-2151: Add __MAIN__ if workContent2 has items
        if (workContent2.Count > 0)
        {
            workContent.Add(new MatchResult { LineNumber = 1, Line = ":__MAIN__", Pattern = @"^.*:" });
        }
        workContent.AddRange(workContent2);

        // Line 2154-2161: Create list of all functions
        var batFunctions = new List<string>();
        if (workContent.Count > 0)
            batFunctions.Add("__MAIN__");

        foreach (string line in fileContentOriginal)
        {
            // Regex: ^.*:$ - Lines that are labels (start with anything, end with colon)
            if (Regex.IsMatch(line.Trim(), @"^:"))
            {
                string funcName = line.Trim().TrimStart(':').ToUpper();
                if (!string.IsNullOrEmpty(funcName) && !batFunctions.Contains(funcName))
                    batFunctions.Add(funcName);
            }
        }

        // Line 2163-2173: Create dictionary of all assigned variables
        var assignmentsDict = new Dictionary<string, string>();
        foreach (string line in fileContentOriginal)
        {
            if (line.Contains("=") && !Regex.IsMatch(line, @"\bif\b", RegexOptions.IgnoreCase))
            {
                string[] temp = line.Split('=');
                if (temp.Length >= 2)
                {
                    string key = temp[0].Trim().ToUpper();
                    // Remove "SET " prefix if present
                    if (key.StartsWith("SET "))
                        key = key.Substring(4).Trim();
                    try
                    {
                        assignmentsDict[key] = temp[1].Trim().Replace("\"", "'");
                    }
                    catch { }
                }
            }
        }

        // Line 2175-2178: Initialize lists
        var htmlCallListCbl = new List<string>();
        var htmlCallList = new List<string>();

        // Line 2180-2187: Loop state variables
        string currentParticipant = "";
        string currentFunctionName = "";
        int loopCounter = 0;
        string previousParticipant = "";
        var functionCodeExceptLoopCode = new List<MatchResult>();
        var loopLevel = new List<string>();
        var loopNodeContent = new List<string>();
        var loopCode = new List<List<MatchResult>>();
        List<string>? functionCode = null;

        // Line 2189-2277: Main processing loop
        foreach (var lineObject in workContent)
        {
            string line = lineObject.Line;

            // Line 2197: Track previous function
            previousParticipant = currentFunctionName;

            // Line 2200: Check if line is a function label
            if (TestBatFunction(line, batFunctions))
            {
                // Line 2201-2204: Process accumulated function code
                if (functionCodeExceptLoopCode.Count > 0)
                {
                    loopCounter = 0;
                    NewBatNodes(functionCodeExceptLoopCode, new List<string>(fileContentOriginal), previousParticipant,
                        mmdWriter, batBaseFileName, batFunctions, assignmentsDict, externalProcesses,
                        sqlTableArray, htmlCallListCbl, htmlCallList);
                }

                // Line 2206-2208: Update current function
                currentParticipant = line.Trim();
                currentFunctionName = currentParticipant.Trim();
                var functionCodeRaw = GetBatFunctionCode(fileContentOriginal, currentParticipant, batFunctions);

                // Wrap in MatchResult
                functionCode = functionCodeRaw;

                // Line 2210-2212: Reset loop tracking
                loopNodeContent = new List<string>();
                loopCode = new List<List<MatchResult>>();
                loopLevel = new List<string>();
                functionCodeExceptLoopCode = new List<MatchResult>();

                // Line 2215-2224: Handle program name to initial function connection
                if (previousParticipant.Length == 0 && currentParticipant.Length > 0)
                {
                    string stmt = safeNodeId + "[[" + programName.Trim().ToLower() + "]]"
                        + " --initiated-->" + currentParticipant.Trim().ToLower()
                        + "(" + currentParticipant.Trim().ToLower() + ")";
                    WriteBatMmd(mmdWriter, stmt);

                    stmt = "style " + safeNodeId + " stroke:red,stroke-width:4px";
                    WriteBatMmd(mmdWriter, stmt);

                    string link = "https://Dedge.visualstudio.com/Dedge/_search?action=contents&text="
                        + batBaseFileName.ToLower() + "&type=code&filters=ProjectFilters%7BDedge%7D";
                    stmt = "click " + safeNodeId + " \"" + link + "\" \"" + programName.Trim().ToLower() + "\" _blank";
                    WriteBatMmd(mmdWriter, stmt);
                }
            }

            // Line 2227-2229: Skip if no function code
            if (functionCode == null || functionCode.Count == 0)
                continue;

            bool skipLine = false;

            // Line 2233-2263: Loop handling (DO/WHILE/UNTIL/END)
            string lineTrimLower = line.Trim().ToLower();
            if (lineTrimLower.Contains("do ") && (lineTrimLower.Contains(" while") || lineTrimLower.Contains(" until")))
            {
                loopCounter++;
                string fromNode, toNode;

                if (loopCounter > 1 && loopLevel.Count >= loopCounter - 1)
                {
                    fromNode = loopLevel[loopCounter - 2];
                    toNode = loopLevel[loopCounter - 2] + loopCounter + "((" + loopLevel[loopCounter - 2] + loopCounter + "))";
                    loopLevel.Add(currentParticipant + "-loop" + loopCounter);
                }
                else
                {
                    fromNode = currentParticipant;
                    toNode = currentParticipant + "-loop((" + currentParticipant + "-loop))";
                    loopLevel.Add(currentParticipant + "-loop");
                }

                loopNodeContent.Add(toNode);
                loopCode.Add(new List<MatchResult>());
                string stmt = fromNode + "--\"perform\"-->" + toNode;
                WriteBatMmd(mmdWriter, stmt);
                skipLine = true;
            }
            else if (lineTrimLower.StartsWith("end"))
            {
                // Line 2254-2261: End of loop - process loop code
                if (loopCounter > 0 && loopCode.Count >= loopCounter)
                {
                    var workCode = loopCode[loopCounter - 1];
                    NewBatNodes(workCode, new List<string>(fileContentOriginal),
                        loopLevel[loopCounter - 1], mmdWriter, batBaseFileName, batFunctions,
                        assignmentsDict, externalProcesses, sqlTableArray, htmlCallListCbl, htmlCallList);

                    loopLevel.RemoveAt(loopCounter - 1);
                    loopNodeContent.RemoveAt(loopCounter - 1);
                    loopCode.RemoveAt(loopCounter - 1);
                    loopCounter--;
                }
                skipLine = true;
            }

            // Line 2265-2277: Accumulate lines
            if (!skipLine)
            {
                if (loopCounter > 0 && loopCode.Count >= loopCounter)
                {
                    // Add to current loop
                    loopCode[loopCounter - 1].Add(lineObject);
                }
                else
                {
                    // Add to function code (outside loops)
                    functionCodeExceptLoopCode.Add(lineObject);
                }
            }
        }

        // Line 2280-2293: Handle case where no functions were found
        if (previousParticipant.Length == 0 && currentParticipant.Length == 0)
        {
            currentParticipant = "__MAIN__";
            string stmt = safeNodeId + "[[" + programName.Trim().ToLower() + "]]"
                + " --initiated-->" + currentParticipant.Trim().ToLower()
                + "(" + currentParticipant.Trim().ToLower() + ")";
            WriteBatMmd(mmdWriter, stmt);

            stmt = "style " + safeNodeId + " stroke:red,stroke-width:4px";
            WriteBatMmd(mmdWriter, stmt);

            string link = "https://Dedge.visualstudio.com/Dedge/_search?action=contents&text="
                + batBaseFileName.ToLower() + "&type=code&filters=ProjectFilters%7BDedge%7D";
            stmt = "click " + safeNodeId + " \"" + link + "\" \"" + programName.Trim().ToLower() + "\" _blank";
            WriteBatMmd(mmdWriter, stmt);
        }

        // Line 2296: Generate nodes for last function
        if (functionCodeExceptLoopCode.Count > 0)
        {
            NewBatNodes(functionCodeExceptLoopCode, new List<string>(fileContentOriginal), currentFunctionName,
                mmdWriter, batBaseFileName, batFunctions, assignmentsDict, externalProcesses,
                sqlTableArray, htmlCallListCbl, htmlCallList);
        }

        // Line 2299: Generate execution path diagram
        GetBatMmdExecutionPathDiagram(mmdWriter, srcRootFolder, batBaseFileName);

        // Line 2302-2304: Generate SVG file (skip when using client-side rendering)
        if (batBaseFileName != "cobreplxen.bat" && !clientSideRender)
        {
            ExecutionPathHelper.GenerateSvgFile(mmdFilename);
        }

        // Line 2307-2309: Generate metadata and HTML
        if (!errorOccurred)
        {
            GetBatMetaData(tmpRootFolder, batBaseFileName, outputFolder, completeFileContent,
                inputDbFileFolder, clientSideRender, mmdWriter, externalProcesses,
                htmlCallListCbl, htmlCallList, ref errorOccurred, generateHtml, sourceFile);
        }

        // Line 2318-2323: Save MMD files if requested
        if (saveMmdFiles && mmdWriter.MmdFilename != null && File.Exists(mmdWriter.MmdFilename))
        {
            string mmdOutputPath = Path.Combine(outputFolder, batBaseFileName + ".mmd");
            File.Copy(mmdWriter.MmdFilename, mmdOutputPath, true);
            Logger.LogMessage($"Saved MMD file: {mmdOutputPath}", LogLevel.INFO);
        }

        // Line 2326-2354: Log result and return
        DateTime endTime = DateTime.Now;
        TimeSpan timeDiff = endTime - startTime;
        string dummyFile = Path.Combine(outputFolder, batBaseFileName + ".err");
        string jsonFilePath = Path.Combine(outputFolder, batBaseFileName + ".json");
        bool htmlWasGenerated = File.Exists(htmlFilename) || File.Exists(jsonFilePath);

        if (htmlWasGenerated)
        {
            // Line 2334-2336: Remove error file on success
            if (File.Exists(dummyFile))
            {
                try { File.Delete(dummyFile); } catch { }
            }

            if (errorOccurred)
            {
                Logger.LogMessage($"Time elapsed: {timeDiff.Seconds}", LogLevel.INFO);
                Logger.LogMessage($"Completed with warnings: {batBaseFileName}", LogLevel.WARN);
            }
            else
            {
                Logger.LogMessage($"Time elapsed: {timeDiff.Seconds}", LogLevel.INFO);
                Logger.LogMessage($"Completed successfully: {batBaseFileName}", LogLevel.INFO);
            }
            return htmlFilename;
        }
        else
        {
            // Line 2349-2353: Log failure
            Logger.LogMessage("*******************************************************************************", LogLevel.ERROR);
            Logger.LogMessage($"Failed - HTML not generated: {sourceFile}", LogLevel.ERROR);
            Logger.LogMessage("*******************************************************************************", LogLevel.ERROR);
            File.WriteAllText(dummyFile, $"Error: HTML file was not generated for {batBaseFileName}");
            return null;
        }
    }

    #endregion
}
