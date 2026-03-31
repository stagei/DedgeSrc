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
/// CBL Parser - complete line-by-line translation from AutoDocFunctions.psm1
/// Functions translated:
///   ContainsCobolEndVerb          (lines 5247-5262)
///   ContainsCobolVerb             (lines 5267-5282)
///   PreProcessFileContent         (lines 5284-5509)
///   Get-CblExecutionPathDiagram   (lines 5511-5598)
///   VerifyIfParagraph             (lines 5600-5626)
///   New-CblNodes                  (lines 5629-5799)
///   GenerateSqlNodes              (lines 5801-5900)
///   New-CblMmdLinks               (lines 5902-6080)
///   Get-CblMetaData               (lines 6082-6435)
///   WriteMmdFlow                  (lines 6437-6491)
///   Get-CblStringBetween          (lines 6492-6523)
///   WriteMmdSequence              (lines 6526-6600)
///   FindParagraphCode             (lines 6635-6671)
///   FindAllFileDefenitionsAndRelatedRecords (lines 6695-6797)
///   HandleDiagramGeneration       (lines 7481-7777)
///   Start-CblParse                (lines 7794-7988)
/// </summary>
public static class CblParser
{
    static CblParser()
    {
        System.Text.Encoding.RegisterProvider(System.Text.CodePagesEncodingProvider.Instance);
    }

    /// <summary>Strip surrounding double-quotes and trim whitespace from CSV fields.</summary>
    private static string CsvClean(string field) => field.Trim().Trim('"').Trim();

    // Script-level variables (equivalent to $script: variables in PowerShell)
    private static int _sequenceNumber = 0;
    private static string? _baseFileNameTemp = null;
    private static int _mmdSequenceElementsWritten = 0;
    private static List<string> _mmdFlowContent = new();
    private static List<string> _mmdSequenceContent = new();
    private static string? _mmdFilenameFlow = null;
    private static string? _mmdFilenameSequence = null;
    private static bool _errorOccurred = false;
    private static List<string> _sqlTableArray = new();
    private static HashSet<string> _duplicateLineCheck = new();
    private static bool _useClientSideRender = false;

    // Precompiled regex patterns (lines 5244, 5264)
    // Regex: \b(end-evaluate|end-if|end-perform|end-exec|end-read|end-search|end-write|end-compute|end-delete|end-invoke|end-multiply|end-return|end-start|end-string|end-unstring|end-call|end-add|end-subtract|end-divide)\b
    // Matches COBOL end-verbs with word boundaries
    private static readonly Regex EndVerbPattern = new(
        @"\b(end-evaluate|end-if|end-perform|end-exec|end-read|end-search|end-write|end-compute|end-delete|end-invoke|end-multiply|end-return|end-start|end-string|end-unstring|end-call|end-add|end-subtract|end-divide)\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    // Regex: \b(accept|add|alter|call|cancel|close|commit|compute|continue|delete|display|divide|entry|evaluate|exec|exhibit|exit|generate|goback|go to|if|initialize|inspect|invoke|merge|move|multiply|open|perform|read|release|return|rewrite|rollback|search|set|sort|start|stop run|string|subtract|unstring|write)\b
    // Matches COBOL verbs with word boundaries
    private static readonly Regex VerbPattern = new(
        @"\b(accept|add|alter|call|cancel|close|commit|compute|continue|delete|display|divide|entry|evaluate|exec|exhibit|exit|generate|goback|go to|if|initialize|inspect|invoke|merge|move|multiply|open|perform|read|release|return|rewrite|rollback|search|set|sort|start|stop run|string|subtract|unstring|write)\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private class MatchResult
    {
        public int LineNumber { get; set; }
        public string Line { get; set; } = "";
    }

    private class PreProcessResult
    {
        public List<string> WorkArray { get; set; } = new();
        public List<string> ProcedureContent { get; set; } = new();
        public int FileSectionLineNumber { get; set; }
        public int WorkingStorageLineNumber { get; set; }
        public List<string> FileSectionContent { get; set; } = new();
    }

    #region Verb Detection (lines 5247-5282)

    /// <summary>
    /// Checks if line contains a COBOL end-verb.
    /// Converted from ContainsCobolEndVerb (lines 5247-5262)
    /// Returns (containsEndVerb, startWithEndVerb, endverb, position)
    /// </summary>
    private static (bool Contains, bool StartsWithEndVerb, string Endverb, int Position) ContainsCobolEndVerb(string? sourceLine)
    {
        if (sourceLine == null)
            return (false, false, "", -1);

        var match = EndVerbPattern.Match(sourceLine);
        if (match.Success)
        {
            string endverb = match.Value.ToLower();
            bool startWithEndVerb = sourceLine.Trim().ToLower().StartsWith(endverb);
            return (true, startWithEndVerb, endverb, match.Index);
        }
        return (false, false, "", -1);
    }

    /// <summary>
    /// Checks if line contains a COBOL verb.
    /// Converted from ContainsCobolVerb (lines 5267-5282)
    /// Returns (containsVerb, startWithVerb, verb, position)
    /// </summary>
    private static (bool Contains, bool StartsWithVerb, string Verb, int Position) ContainsCobolVerb(string? sourceLine)
    {
        if (sourceLine == null)
            return (false, false, "", -1);

        var match = VerbPattern.Match(sourceLine);
        if (match.Success)
        {
            string verb = match.Value.ToLower();
            bool startWithVerb = sourceLine.Trim().ToLower().StartsWith(verb);
            return (true, startWithVerb, verb, match.Index);
        }
        return (false, false, "", -1);
    }

    #endregion

    #region VerifyIfParagraph (lines 5600-5626)

    /// <summary>
    /// Validates if a line is a COBOL paragraph name.
    /// Converted from VerifyIfParagraph (lines 5600-5626)
    /// </summary>
    private static bool VerifyIfParagraph(string paragraphName)
    {
        bool isValidParagraph = false;
        paragraphName = paragraphName.ToLower().Trim()
            .Replace(" .", ".").Trim().Replace(" .", ".").Trim().Replace(" .", ".").Trim()
            .Replace(" .", ".").Trim().Replace(" .", ".").Trim().Replace(" .", ".").Trim()
            .Replace(" .", ".").Trim().Replace(" .", ".").Trim().Replace(" .", ".");

        if (!paragraphName.Contains(" ") && (paragraphName.Length - 1) == paragraphName.IndexOf('.') && paragraphName.Length > 1)
        {
            isValidParagraph = true;
        }
        return isValidParagraph;
    }

    #endregion

    #region PreProcessFileContent (lines 5284-5509)

    /// <summary>
    /// Pre-processes COBOL file content: removes comments, extracts sections,
    /// accumulates multi-line expressions.
    /// Converted line-by-line from PreProcessFileContent (lines 5284-5509)
    /// </summary>
    private static PreProcessResult PreProcessFileContent(string[] fileContentOriginal)
    {
        var declarativesContent = new List<string>();
        var procedureContent = new List<string>();
        var procedureCodeContent = new List<string>();
        var fileSectionContent = new List<string>();

        int fileSectionLineNumber = 0;
        int workingStorageLineNumber = 0;
        int procedureDivisionLineNumber = 0;
        int firstParagraphLinenumber = 0;

        var workArray = new List<string>();
        int counter = 0;

        // First pass (lines 5300-5369)
        foreach (string rawLine in fileContentOriginal)
        {
            string line = rawLine;
            int ustart = line.IndexOf("*>");
            if (ustart > 0) line = line.Substring(0, ustart);

            if (string.IsNullOrWhiteSpace(line)) continue;
            if (line.Length <= 6) continue;
            if (line.Trim().StartsWith("*")) continue;

            line = line.Substring(6).ToLower();
            if (string.IsNullOrWhiteSpace(line)) continue;

            counter++;
            line = line.Trim();

            if (Regex.IsMatch(line, @"procedure.*division", RegexOptions.IgnoreCase) ||
                Regex.IsMatch(line, @"procedure\.division", RegexOptions.IgnoreCase))
                procedureDivisionLineNumber = counter;

            if (Regex.IsMatch(line, @".*M[0-9]+\-.*\.") && firstParagraphLinenumber == 0)
                firstParagraphLinenumber = counter;

            if (procedureDivisionLineNumber == 0)
                declarativesContent.Add(line);
            else
                procedureContent.Add(line);

            if (procedureDivisionLineNumber > 0 && firstParagraphLinenumber == 0)
                procedureCodeContent.Add(line);

            if (Regex.IsMatch(line, @".*M[0-9]+\-.*\.") && firstParagraphLinenumber == 0)
                firstParagraphLinenumber = counter;

            if (Regex.IsMatch(line, @"file section", RegexOptions.IgnoreCase))
                fileSectionLineNumber = counter;

            if (Regex.IsMatch(line, @"working-storage", RegexOptions.IgnoreCase))
                workingStorageLineNumber = counter;

            if (fileSectionLineNumber > 0 && workingStorageLineNumber == 0)
                fileSectionContent.Add(line);

            workArray.Add(line);
        }

        // Second pass - process accumulated expressions (lines 5371-5498)
        var workArray1 = new List<string>();
        counter = -1;
        bool isInlinePerform = false;
        string inlinePerformParagraph = "";
        string accumulatedExpression = "";
        procedureDivisionLineNumber = 0;
        int procedureDivisionPeriodLinenumber = 0;
        firstParagraphLinenumber = 0;

        while (workArray.Count > counter)
        {
            counter++;
            if (counter >= workArray.Count) break;

            string line = workArray[counter];
            if (string.IsNullOrEmpty(line)) continue;

            if (Regex.IsMatch(line, @"procedure.*division", RegexOptions.IgnoreCase) ||
                Regex.IsMatch(line, @"procedure\.division", RegexOptions.IgnoreCase))
                procedureDivisionLineNumber = counter;

            if (counter > procedureDivisionLineNumber && procedureDivisionLineNumber > 0 && procedureDivisionPeriodLinenumber > 0)
            {
                var (containsCobolVerb, verbAtStartOfLine, verb, verbPos) = ContainsCobolVerb(line);
                var (containsEndVerb, startWithEndVerb, endverb, endVerbPos) = ContainsCobolEndVerb(line);

                bool verifiedParagraph = VerifyIfParagraph(line.Trim());
                if (verifiedParagraph && firstParagraphLinenumber == 0 && procedureDivisionLineNumber > 0)
                    firstParagraphLinenumber = counter;

                if (line.Trim() == "." || containsCobolVerb || containsEndVerb || accumulatedExpression.Trim() == ".")
                {
                    if (accumulatedExpression.Length > 0)
                    {
                        // Handle inline perform (lines 5411-5476)
                        if ((accumulatedExpression.Contains("perform") && accumulatedExpression.Contains("until")) ||
                            (accumulatedExpression.Contains("perform") && line.StartsWith("exec")))
                        {
                            if (accumulatedExpression.Contains("perform") && line.StartsWith("exec") && !accumulatedExpression.Contains("end-perform"))
                            {
                                accumulatedExpression = "perform until";
                            }
                            else
                            {
                                string tempStr = accumulatedExpression.Replace("perform", "").Trim();
                                int pos = tempStr.IndexOf(' ');
                                if (pos > 0)
                                {
                                    inlinePerformParagraph = tempStr.Split(' ')[0];
                                    bool boolResult = VerifyIfParagraph(inlinePerformParagraph.Trim());
                                    if (boolResult)
                                        isInlinePerform = true;
                                    else
                                    {
                                        inlinePerformParagraph = "";
                                        isInlinePerform = false;
                                    }
                                }
                            }
                        }

                        if (isInlinePerform)
                        {
                            accumulatedExpression = accumulatedExpression.Replace(inlinePerformParagraph, "");
                            accumulatedExpression = accumulatedExpression.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");
                            var tempArray = new List<string>
                            {
                                accumulatedExpression.Trim(),
                                "perform " + inlinePerformParagraph,
                                "end-perform "
                            };
                            workArray1.AddRange(tempArray);
                            procedureCodeContent.AddRange(tempArray);

                            if (counter > procedureDivisionLineNumber && firstParagraphLinenumber == 0)
                                procedureContent.AddRange(tempArray);
                        }
                        else
                        {
                            var (containsEndVerb2, startWithEndVerb2, endverb2, endVerbPos2) = ContainsCobolEndVerb(accumulatedExpression.Trim());
                            var tempArray = new List<string>();
                            if (containsEndVerb2 && !startWithEndVerb2 && endVerbPos2 > 0)
                            {
                                tempArray.Add(accumulatedExpression.Substring(0, endVerbPos2 - 1).Trim());
                                tempArray.Add(accumulatedExpression.Substring(endVerbPos2 - 1));
                            }
                            else
                            {
                                tempArray.Add(accumulatedExpression.Trim());
                            }
                            workArray1.AddRange(tempArray);
                            procedureCodeContent.AddRange(tempArray);
                            if (counter > procedureDivisionLineNumber && firstParagraphLinenumber == 0)
                                procedureContent.AddRange(tempArray);
                        }
                    }
                    isInlinePerform = false;
                    inlinePerformParagraph = "";
                    accumulatedExpression = "";
                }

                accumulatedExpression += " " + line.Trim().Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");
                accumulatedExpression = accumulatedExpression.Trim();
            }
            else
            {
                if (procedureDivisionLineNumber > 0 && procedureDivisionPeriodLinenumber == 0 && line.Contains('.'))
                    procedureDivisionPeriodLinenumber = counter;

                workArray1.Add(line.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " "));
            }
        }

        if (accumulatedExpression.Length > 0)
            workArray1.Add(accumulatedExpression);

        workArray = workArray1;

        if (procedureDivisionLineNumber > 0 && firstParagraphLinenumber == 0)
            procedureCodeContent = new List<string>(procedureContent);

        return new PreProcessResult
        {
            WorkArray = workArray,
            ProcedureContent = procedureCodeContent,
            FileSectionLineNumber = fileSectionLineNumber,
            WorkingStorageLineNumber = workingStorageLineNumber,
            FileSectionContent = fileSectionContent
        };
    }

    #endregion

    #region WriteMmdFlow / WriteMmdSequence (lines 6437-6600)

    /// <summary>
    /// Write Mermaid Flow diagram content with filtering and deduplication.
    /// Converted line-by-line from WriteMmdFlow (lines 6437-6491)
    /// </summary>
    private static void WriteMmdFlow(string mmdString)
    {
        // Line 6443-6446: Replace newlines and Norwegian characters
        mmdString = mmdString.Replace("\n", "<br/>").Replace("\r", "");
        mmdString = Regex.Replace(mmdString, "[Ø]", "O").Replace("ø", "o").Replace("Å", "A").Replace("å", "a").Replace("Æ", "AE").Replace("æ", "ae");

        string baseFileName = (_baseFileNameTemp ?? "").Trim().ToLower();
        mmdString = Regex.Replace(mmdString, @"\s{2,}", " ");

        // Line 6459-6467: Skip utility modules
        string mmdLower = mmdString.ToLower();
        string[] utilityModules = { "gmacoco", "gmasql", "gmacnct", "gmalike", "gmacurt", "gmftrap", "gmffell", "gmadato", "gmfsql" };
        foreach (string mod in utilityModules)
        {
            if (mmdLower.Contains(mod) && baseFileName != mod)
                return;
        }

        // Regex: (-sql-trap|-error|refresh-?object|cbl_(exit_proc|copy_file|rename_file|toupper|tolower)|sqlg(star|intr)|db2api|-exit-proc|procdiv)
        // Skip common utility patterns
        if (Regex.IsMatch(mmdLower, @"(-sql-trap|-error|refresh-?object|cbl_(exit_proc|copy_file|rename_file|toupper|tolower)|sqlg(star|intr)|db2api|-exit-proc|procdiv)"))
            return;

        // Line 6470-6490: Check for duplicates and add to content
        if (!_duplicateLineCheck.Contains(mmdString))
        {
            if (mmdString.Contains("-->") && !mmdLower.Contains("initiated-->"))
            {
                int pos1 = mmdString.IndexOf("-->");
                int pos2 = mmdString.LastIndexOf("-->");
                if (pos1 == pos2)
                {
                    _sequenceNumber++;
                    mmdString = mmdString.Substring(0, pos1) + "(#" + _sequenceNumber + ")" + mmdString.Substring(pos1);
                }
            }
            _mmdSequenceElementsWritten++;

            if (_useClientSideRender)
                _mmdFlowContent.Add(mmdString);
            else if (_mmdFilenameFlow != null)
                File.AppendAllText(_mmdFilenameFlow, mmdString + Environment.NewLine, Encoding.UTF8);

            _duplicateLineCheck.Add(mmdString);
        }
    }

    /// <summary>
    /// Write Mermaid Sequence diagram content.
    /// Converted line-by-line from WriteMmdSequence (lines 6526-6600)
    /// </summary>
    private static void WriteMmdSequence(string mmdString)
    {
        mmdString = mmdString.Replace("\"", "'").Replace("\\", "/");
        mmdString = Regex.Replace(mmdString, "[Ø]", "O").Replace("ø", "o").Replace("Å", "A").Replace("å", "a").Replace("Æ", "AE").Replace("æ", "ae");
        mmdString = mmdString.Replace("?å?", "a").Replace("?ø", "o").Replace("??", "o").Replace("ø", "o");
        mmdString = mmdString.Replace(";", ",").Replace("&", "and");
        mmdString = mmdString.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");

        // Line 6562-6586: Skip common patterns
        string mmdLower = mmdString.ToLower();
        if (mmdLower.Contains("-sql-trap") || mmdLower.Contains("-error") || mmdLower.Contains("gmacoco")
            || mmdLower.Contains("refresh-object") || mmdLower.Contains("refreshobject") || mmdLower.Contains("gmfsql")
            || mmdLower.Contains("gmasql") || mmdLower.Contains("gmacnct") || mmdLower.Contains("gmalike")
            || mmdLower.Contains("gmacurt") || mmdLower.Contains("gmftrap") || mmdLower.Contains("gmffell")
            || mmdLower.Contains("gmadato") || mmdLower.Contains("cbl_exit_proc") || mmdLower.Contains("cbl_copy_file")
            || mmdLower.Contains("cbl_rename_file") || mmdLower.Contains("cbl_toupper") || mmdLower.Contains("cbl_tolower")
            || mmdLower.Contains("sqlgstar") || mmdLower.Contains("sqlgintr") || mmdLower.Contains("db2api")
            || mmdLower.Contains("-exit-proc") || mmdLower.Contains("procdiv")
            || (mmdLower.Contains("-->p") && mmdLower.Contains("perform")))
            return;

        if (!_duplicateLineCheck.Contains(mmdString))
        {
            if (_useClientSideRender)
                _mmdSequenceContent.Add(mmdString);
            else if (_mmdFilenameSequence != null)
                File.AppendAllText(_mmdFilenameSequence, mmdString + Environment.NewLine, Encoding.UTF8);

            _duplicateLineCheck.Add(mmdString);
        }
    }

    #endregion

    #region String Utilities (lines 6492-6523)

    /// <summary>
    /// Extracts substring between two delimiter strings.
    /// Converted from Get-CblStringBetween (lines 6492-6523)
    /// Returns (extracted, remaining)
    /// </summary>
    private static (string? Extracted, string Remaining) GetCblStringBetween(string firstString, string secondString, string data, int overrideStartPos = 0)
    {
        try
        {
            int pos1;
            if (overrideStartPos > 0)
                pos1 = overrideStartPos;
            else if (firstString == "<line_start>")
                pos1 = -1;
            else
            {
                pos1 = data.IndexOf(firstString);
                if (pos1 < 0) return (null, data);
            }

            int pos2 = data.Substring(pos1 + 1).IndexOf(secondString);
            if (pos2 < 0) return (null, data);
            if (pos1 < 0) pos1 = 0;

            string retData = data.Substring(pos1, pos2 + 1).Trim();
            return (retData, data.Substring(pos1 + pos2 + 1));
        }
        catch
        {
            return (null, data);
        }
    }

    #endregion

    #region FindParagraphCode (lines 6635-6671)

    /// <summary>
    /// Extracts code for a specific COBOL paragraph.
    /// Converted from FindParagraphCode (lines 6635-6671)
    /// </summary>
    private static List<MatchResult> FindParagraphCode(List<string> array, string paragraphName)
    {
        bool foundStart = false;
        try { paragraphName = paragraphName.ToLower(); } catch { }

        var extractedElements = new List<MatchResult>();
        int lineNumber = 0;

        foreach (string item in array)
        {
            lineNumber++;
            if (item.Trim().StartsWith(paragraphName) || Regex.IsMatch(item, paragraphName))
            {
                foundStart = true;
                extractedElements = new List<MatchResult>();
            }
            else if (foundStart)
            {
                if (VerifyIfParagraph(item))
                {
                    foundStart = false;
                    break;
                }
                else
                {
                    extractedElements.Add(new MatchResult { LineNumber = lineNumber, Line = item });
                }
            }
        }
        return extractedElements;
    }

    #endregion

    #region FindAllFileDefinitionsAndRelatedRecords (lines 6695-6797)

    /// <summary>
    /// Finds FD entries and their related record definitions.
    /// Converted from FindAllFileDefenitionsAndRelatedRecords (lines 6695-6797)
    /// </summary>
    private static Dictionary<string, string> FindAllFileDefinitionsAndRelatedRecords(List<string> fileSectionContent, string srcRootFolder)
    {
        var fileEntries = new Dictionary<string, string>();
        try
        {
            var fdDataResArrayWithCpy = new List<string>();
            foreach (string rawLine in fileSectionContent)
            {
                string line = rawLine;
                if (line.StartsWith("copy"))
                {
                    try
                    {
                        string cpyFile = line.Trim().Split('"')[1];
                        string[] cpyData = Array.Empty<string>();

                        string filePath = Path.Combine(srcRootFolder, "Dedge", "cpy", cpyFile);
                        if (File.Exists(filePath))
                            cpyData = SourceFileCache.GetLines(filePath) ?? File.ReadAllLines(filePath);

                        filePath = Path.Combine(srcRootFolder, "Dedge", "sys", "cpy", cpyFile);
                        if (File.Exists(filePath))
                            cpyData = SourceFileCache.GetLines(filePath) ?? File.ReadAllLines(filePath);

                        foreach (string cpyLine in cpyData)
                        {
                            string processedLine = cpyLine;
                            int ustart = processedLine.IndexOf(" redefines ");
                            if (ustart > 0) processedLine = processedLine.Substring(0, ustart).Trim() + ".";

                            ustart = processedLine.IndexOf(" pic ");
                            if (ustart > 0) processedLine = processedLine.Substring(0, ustart).Trim() + ".";

                            if (processedLine.Trim().StartsWith("01 "))
                                fdDataResArrayWithCpy.Add(processedLine);
                        }
                    }
                    catch { }
                }
                else
                {
                    int ustart = line.IndexOf(" pic ");
                    if (ustart > 0) line = line.Substring(0, ustart).Trim() + ".";

                    if (line.Trim().StartsWith("01 ") || line.Trim().StartsWith("fd "))
                        fdDataResArrayWithCpy.Add(line);
                }
            }

            string fdDataRes = " " + string.Join(" ", fdDataResArrayWithCpy);
            fdDataRes = fdDataRes.Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ").Replace("  ", " ");
            string[] y = fdDataRes.Split(" fd ");

            foreach (string temp1Raw in y)
            {
                string temp1 = temp1Raw.Trim();
                if (temp1.Replace(".", "") == "") continue;

                int pos1 = temp1.IndexOf('.');
                int pos2 = temp1.IndexOf(' ');
                string? fileName;
                string restData;

                if (pos1 > pos2 && pos2 > 0)
                    (fileName, restData) = GetCblStringBetween("<line_start>", " ", temp1, 0);
                else
                    (fileName, restData) = GetCblStringBetween("<line_start>", ".", temp1, 0);

                if (string.IsNullOrEmpty(fileName)) fileName = temp1;
                fileName = fileName.Replace(".", "");

                string fileRecString = "";
                string prevRestData = "";
                restData = " " + restData;
                while (prevRestData != restData)
                {
                    prevRestData = restData;
                    var (resultString, newRestData) = GetCblStringBetween(" 01 ", ".", restData);
                    restData = newRestData;
                    if (!string.IsNullOrEmpty(resultString))
                    {
                        string rs = " " + resultString;
                        if (rs.Contains(" 01 ")) rs = rs.Replace(" 01 ", "");
                        fileRecString += "\u00B6" + rs.Trim();
                    }
                }
                fileRecString += "\u00B6";
                if (!fileEntries.ContainsKey(fileName))
                    fileEntries.Add(fileName, fileRecString);
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in FindAllFileDefinitionsAndRelatedRecords: {ex.Message}", LogLevel.ERROR, ex);
            _errorOccurred = true;
        }
        return fileEntries;
    }

    /// <summary>
    /// Finds a string in the hashtable matching the search string.
    /// Utility for FD record lookups.
    /// </summary>
    private static string? FindStringInHashtable(Dictionary<string, string> hashTable, string searchString)
    {
        foreach (var kvp in hashTable)
        {
            if (kvp.Value.Contains(searchString))
                return kvp.Key;
        }
        return null;
    }

    #endregion

    #region New-CblNodes (lines 5629-5799)

    /// <summary>
    /// Generates Mermaid nodes for a COBOL paragraph.
    /// Converted line-by-line from New-CblNodes (lines 5629-5799)
    /// </summary>
    private static void NewCblNodes(
        List<MatchResult> paragraphCode,
        List<string> procedureContent,
        List<string> fileContent,
        string paragraphName,
        Dictionary<string, string> fdHashtable,
        int currentLoopCounter)
    {
        bool isSqlCodeInParagraphHandled = false;
        var accumulatedParagraphCode = new List<string>();
        bool skipLine = false;
        int contentFromLineNumber = 0;
        int lastLineNumber = 0;

        foreach (var lineObject in paragraphCode)
        {
            string line = lineObject.Line;
            if (line.Length == 0) continue;

            // Line 5646-5650: Skip inline perform/varying
            if (line.Trim().Contains("perform until") || line.Trim().Contains("perform varying")
                || line.Trim().Contains("until") || (line.Trim().Contains("perform") && line.Trim().Contains(" times"))
                || line.ToLower().Trim().Contains("perform with test before"))
            {
                skipLine = true;
                Logger.LogMessage($"Skipped perform until. Should not be here. Linenumber: {lineObject.LineNumber}", LogLevel.WARN);
                continue;
            }

            if (line.Contains("end-perform"))
            {
                skipLine = false;
                Logger.LogMessage($"Skipped end-perform. Should not be here. Linenumber: {lineObject.LineNumber}", LogLevel.WARN);
                continue;
            }

            if (skipLine) continue;

            if (contentFromLineNumber == 0)
                contentFromLineNumber = lineObject.LineNumber;

            // Accumulate procedure content for SQL parsing
            if (lineObject.LineNumber > contentFromLineNumber)
            {
                int startIdx = Math.Max(0, contentFromLineNumber - 1);
                int endIdx = Math.Min(procedureContent.Count, lineObject.LineNumber) - 1;
                for (int i = startIdx; i <= endIdx && i < procedureContent.Count; i++)
                    accumulatedParagraphCode.Add(procedureContent[i]);
                contentFromLineNumber = lineObject.LineNumber + 1;
            }

            lastLineNumber = lineObject.LineNumber;

            // Line 5673-5699: Perform handling
            if (line.Trim().Contains("perform") && !line.Trim().Contains("exit") && !line.Trim().Contains("-perform"))
            {
                int pos = line.IndexOf("perform");
                string toNode = line.Substring(pos + "perform".Length).Trim().Replace(".", "");

                if (toNode.Contains(' '))
                {
                    int spacePos = toNode.IndexOf(' ');
                    toNode = toNode.Substring(0, spacePos);
                }

                string fromNode = paragraphName + "(" + paragraphName + ")";
                if (toNode == fromNode || toNode.Length == 0 || fromNode.Length == 0) continue;

                string statement = fromNode + "--\"perform\"-->" + toNode + "(" + toNode + ")";
                WriteMmdFlow(statement);
                statement = paragraphName + "->>" + toNode + ": perform";
                WriteMmdSequence(statement);
            }

            // Line 5704-5728: Call handling
            if (line.Trim().StartsWith("call"))
            {
                string toNode = line.Trim().Replace("call", "").Replace("'", "").Replace("\"", "")
                    .Replace("end-call", "").Replace("end", "");
                int pos1 = line.IndexOf("call ");
                int pos2 = line.IndexOf("'");
                int pos3 = line.IndexOf("\"");
                if (pos3 > pos2) pos2 = pos3;
                if (pos1 > pos2)
                {
                    Logger.LogMessage($"Skipped call statement: {line}", LogLevel.INFO);
                    continue;
                }

                int ustart = toNode.IndexOf("using");
                if (ustart > 0) toNode = toNode.Substring(0, ustart).Trim();
                toNode = toNode.TrimEnd('-').TrimStart('-').Trim();

                string statement = paragraphName + " --call-->" + toNode.Trim().Replace(" ", "_") + "[[" + toNode.Trim() + "]]";
                WriteMmdFlow(statement);
                statement = paragraphName + "-->>" + toNode.Trim() + ": call";
                WriteMmdSequence(statement);
            }

            // Line 5731-5738: Stop Run handling
            if (line.Trim().Contains("stop run"))
            {
                WriteMmdFlow(paragraphName + " ---->stop_run(STOP RUN)");
                WriteMmdSequence(paragraphName + "-->>stop_run: stop run");
                WriteMmdSequence("participant stop_run");
            }

            // Line 5741-5748: GoBack handling
            if (line.Trim().Contains("goback"))
            {
                WriteMmdFlow(paragraphName + " ---->goback(goback)");
                WriteMmdSequence(paragraphName + "-->>goback: goback");
                WriteMmdSequence("participant goback");
            }

            // Line 5751-5778: Read and write file handling
            if (line.StartsWith("read ") || line.StartsWith("write "))
            {
                string[] x = line.Split(' ');
                if (x.Length > 1)
                {
                    string readOrWriteOperation = x[0];
                    string fileName = x[1];
                    string? fileNameRes = null;

                    if (fileName.Contains("-rec"))
                    {
                        string searchString = "\u00B6" + fileName + "\u00B6";
                        fileNameRes = FindStringInHashtable(fdHashtable, searchString);
                    }

                    string fileNameTemp;
                    try
                    {
                        fileNameTemp = (fileNameRes ?? fileName).Replace("-", "_").Replace(" ", "_");
                    }
                    catch
                    {
                        fileNameTemp = fileName;
                        fileNameRes = fileName;
                    }

                    string statement = paragraphName + " --" + readOrWriteOperation + " file-->" + fileNameTemp + "file[/" + (fileNameRes ?? fileName) + "/]";
                    if ((fileNameRes ?? fileName).Length == 0)
                        Logger.LogMessage($"Error parsing file node (fix later): {line}", LogLevel.WARN);
                    else
                        WriteMmdFlow(statement);
                }
            }
        }

        // Line 5780-5798: Add remaining lines and handle SQL
        if (lastLineNumber > contentFromLineNumber)
        {
            int startIdx = Math.Max(0, contentFromLineNumber - 1);
            int endIdx = Math.Min(procedureContent.Count, lastLineNumber) - 1;
            for (int i = startIdx; i <= endIdx && i < procedureContent.Count; i++)
                accumulatedParagraphCode.Add(procedureContent[i]);
        }

        if (!isSqlCodeInParagraphHandled)
        {
            GenerateSqlNodes(accumulatedParagraphCode, fileContent, procedureContent, paragraphName);
            isSqlCodeInParagraphHandled = true;
        }
    }

    #endregion

    #region GenerateSqlNodes (lines 5801-5900)

    /// <summary>
    /// Generates Mermaid nodes for SQL statements found in COBOL code.
    /// Converted line-by-line from GenerateSqlNodes (lines 5801-5900)
    /// </summary>
    private static void GenerateSqlNodes(
        List<string> paragraphCode,
        List<string> fileContent,
        List<string> procedureContent,
        string paragraphName)
    {
        try
        {
            string[] supportedSqlExpressions = { "SELECT", "UPDATE", "INSERT", "DELETE", "FETCH", "CALL" };

            string paragraphCodeJoined = string.Join(" ", paragraphCode);
            // Regex: exec sql([^\n]*?)end-exec - Match SQL statements between exec sql and end-exec
            var matches1 = Regex.Matches(paragraphCodeJoined, @"exec sql(.*?)end-exec", RegexOptions.Singleline);

            string fileContentJoined = string.Join(" ", fileContent);

            foreach (Match currentItemName in matches1)
            {
                var sqlResult = SqlParseHelper.FindSqlStatementInExecSql(
                    new[] { currentItemName.Value },
                    fileContentJoined,
                    string.Join(" ", procedureContent));

                string? sqlOperation = sqlResult.SqlOperation;
                var sqlTableNames = sqlResult.SqlTableNames?.Distinct().OrderBy(x => x).ToList() ?? new List<string>();
                string? cursorName = sqlResult.CursorName;
                bool cursorForUpdate = sqlResult.CursorForUpdate;
                var updateFields = sqlResult.UpdateFields ?? new List<string>();

                // Line 5822-5836: CALL handling
                if (sqlOperation == "CALL")
                {
                    string tempStr = currentItemName.Value.Replace("exec sql", "").Replace("end-exec", "")
                        .Replace("call", "").Replace("'", "").Replace("\"", "").Replace(";", "").Trim();
                    int pos = tempStr.IndexOf('(');
                    if (pos > 0)
                        tempStr = tempStr.Substring(0, pos).Trim();
                    else
                        continue;

                    WriteMmdFlow(paragraphName + "-->" + tempStr + "(" + tempStr + ")");
                    WriteMmdSequence(paragraphName + "-->>" + tempStr + ": call sql procedure");
                    continue;
                }

                // Line 5838-5890: Table nodes
                if (supportedSqlExpressions.Contains(sqlOperation) && sqlTableNames.Count > 0)
                {
                    int tableCounter = 0;
                    foreach (string sqlTableRaw in sqlTableNames)
                    {
                        string sqlTable = sqlTableRaw.Replace(")", "").Replace("(", "").Replace("'", "").Replace("\"", "");
                        _sqlTableArray.Add(sqlTable);
                        tableCounter++;
                        string statementText = (sqlOperation ?? "").ToLower();

                        if (!string.IsNullOrEmpty(cursorName) && cursorName.Length > 0)
                        {
                            if (tableCounter == 1)
                            {
                                statementText = "Cursor " + cursorName.ToUpper() + " select";
                                if (cursorForUpdate)
                                    statementText = "Primary table for cursor " + cursorName.ToUpper() + " select for update";
                            }
                            else
                                statementText = "Sub-select in cursor " + cursorName.ToUpper();
                        }
                        else
                        {
                            if (tableCounter > 1)
                            {
                                if (sqlOperation == "UPDATE" || sqlOperation == "INSERT" || sqlOperation == "DELETE")
                                    statementText = "Sub-select related to " + sqlTableNames[0].Trim();
                                if (sqlOperation == "SELECT")
                                    statementText = "Join or Sub-select related to " + sqlTableNames[0].Trim();
                            }
                            else if (sqlOperation == "UPDATE" && updateFields.Count > 0)
                            {
                                string fieldList = string.Join(", ", updateFields);
                                statementText = $"update [{fieldList}]";
                            }
                        }

                        try
                        {
                            string statement = paragraphName + "--\"" + statementText + "\"-->sql_" + sqlTable.Replace(".", "_").Trim() + "[(" + sqlTable.Trim() + ")]";
                            WriteMmdFlow(statement);
                            statement = paragraphName + "-->>" + sqlTable.Trim() + ": sql " + statementText;
                            WriteMmdSequence(statement);
                        }
                        catch (Exception ex)
                        {
                            Logger.LogMessage($"Error generating SQL node: {ex.Message}", LogLevel.ERROR, ex);
                            _errorOccurred = true;
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in GenerateSqlNodes: {ex.Message}", LogLevel.ERROR, ex);
            _errorOccurred = true;
        }
    }

    #endregion

    #region New-CblMmdLinks (lines 5902-6080)

    /// <summary>
    /// Generates clickable links in Mermaid diagram to Azure DevOps source.
    /// Converted line-by-line from New-CblMmdLinks (lines 5902-6080)
    /// </summary>
    private static void NewCblMmdLinks(
        string baseFileName,
        string sourceFile,
        string? proxyFilename,
        string? proxyClass,
        string[]? proxyFileContent,
        string[]? fileContentOriginal)
    {
        try
        {
            // Line 5908-5909: Main source link
            string link = "https://Dedge.visualstudio.com/_git/Dedge?path=/cbl/" + baseFileName.ToLower();
            string statement = "click " + baseFileName.ToLower().Split('.')[0] + " \"" + link + "\" \"" + baseFileName.ToLower().Split('.')[0] + "\" _blank";
            WriteMmdFlow(statement);

            // Line 5912: Find paragraphs and calls in source
            var paragraphListItems = new List<MatchResult>();
            if (File.Exists(sourceFile))
            {
                string[] lines = SourceFileCache.GetLines(sourceFile) ?? File.ReadAllLines(sourceFile);
                // Regex: (^.*M[0-9]+\-.*\.)|(^.*CALL.*)|(^.*PROCEDURE.DIVISION.*)|(^.*PROCEDURE.*DIVISION.*)
                // Match paragraph headers, CALL statements, and PROCEDURE DIVISION
                var pattern = new Regex(@"(^.*M[0-9]+\-.*\.)|(^.*CALL.*)|(^.*PROCEDURE.DIVISION.*)|(^.*PROCEDURE.*DIVISION.*)", RegexOptions.IgnoreCase);
                for (int i = 0; i < lines.Length; i++)
                {
                    if (pattern.IsMatch(lines[i]))
                        paragraphListItems.Add(new MatchResult { LineNumber = i + 1, Line = lines[i] });
                }
            }

            // Line 5917-5927: SQL table links
            foreach (string item in _sqlTableArray)
            {
                string workstring = item.Replace("?å?", "a").Replace("?ø", "o").Replace("??", "o").Replace("?", "o");
                string linkname = "sql_" + workstring.Replace(".", "_").Trim();
                link = ("./" + workstring.Replace(".", "_").Trim() + ".sql.html").Trim().ToUpper()
                    .Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower();
                statement = "click " + linkname + " \"" + link + "\" \"" + workstring + "\" _blank";
                WriteMmdFlow(statement);
                statement = "style " + linkname + " stroke:dark-blue,stroke-width:4px";
                WriteMmdFlow(statement);
            }

            // Line 5929-6071: Process paragraph list items
            bool procedureDivisionPassed = false;
            foreach (var item in paragraphListItems)
            {
                string itemLine = item.Line;
                int ustart = itemLine.IndexOf("*>");
                if (ustart > 0) itemLine = itemLine.Substring(0, ustart);
                if (string.IsNullOrWhiteSpace(itemLine)) continue;
                if (itemLine.Trim().Length <= 6) continue;
                if (itemLine.Trim().StartsWith("*")) continue;

                itemLine = itemLine.Substring(6).ToLower().Trim();
                if (itemLine.Trim().StartsWith("*")) continue;
                if (itemLine.Contains("entry ") || itemLine.Contains("perform ")) continue;

                if (Regex.IsMatch(itemLine, @"^.*PROCEDURE.DIVISION.*", RegexOptions.IgnoreCase) ||
                    Regex.IsMatch(itemLine, @"^.*PROCEDURE.*DIVISION.*", RegexOptions.IgnoreCase))
                {
                    procedureDivisionPassed = true;
                    link = "https://Dedge.visualstudio.com/_git/Dedge?path=/cbl/" + baseFileName.ToLower()
                        + "&version=GBmaster&line=" + item.LineNumber + "&lineEnd=" + (item.LineNumber + 1)
                        + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents";
                    WriteMmdFlow("click procedure_division \"" + link + "\" \"procedure_division\" _blank");
                }

                if (procedureDivisionPassed)
                {
                    if (itemLine.Contains("call "))
                    {
                        int pos1 = itemLine.IndexOf("call ");
                        int pos2 = itemLine.IndexOf("'");
                        int pos3 = itemLine.IndexOf("\"");
                        if (pos3 > pos2) pos2 = pos3;
                        if (pos1 > pos2) continue;
                        if (itemLine.Contains("perform ")) continue;

                        string callModule;
                        try
                        {
                            string[] temp1 = itemLine.Contains("'") ? itemLine.Split('\'') : itemLine.Split(' ');
                            callModule = temp1[1].Trim().ToLower();
                        }
                        catch
                        {
                            try
                            {
                                string[] temp1 = itemLine.Split('"');
                                callModule = temp1[1].Trim().ToLower();
                            }
                            catch { continue; }
                        }

                        callModule = callModule.Replace("'", "").Replace("\"", "");

                        // Check proxy
                        if (!string.IsNullOrEmpty(proxyFilename) && proxyFilename.Length > 0 && fileContentOriginal != null)
                        {
                            bool found = fileContentOriginal.Any(l => l.ToLower().Contains(callModule));
                            if (found)
                            {
                                string linkRequest = (proxyClass ?? "") + "%20AND%20" + callModule;
                                link = "https://Dedge.visualstudio.com/Dedge/_search?action=contents&text=" + linkRequest
                                    + "&type=code&lp=code-Project&filters=ProjectFilters%7BDedge%7DRepositoryFilters%7BDedge%7D&pageSize=25";
                                WriteMmdFlow("click " + callModule + " \"" + link + "\" \"" + callModule + "\" _blank");
                                WriteMmdFlow("style " + callModule + " stroke:dark-blue,stroke-width:4px");
                                continue;
                            }
                        }

                        // Skip utility modules
                        string callModuleUpper = callModule.ToUpper();
                        if (callModuleUpper.StartsWith("CBL_") || callModuleUpper.StartsWith("UTL_") || callModuleUpper.Contains(" ")
                            || callModuleUpper.StartsWith("DB2") || callModuleUpper.StartsWith("SLEEP")
                            || callModuleUpper.Contains("SET-BUTTON-STATE") || callModuleUpper.Contains("COB32API")
                            || callModuleUpper.Contains("DISABLE-OBJECT") || callModuleUpper.Contains("ENABLE-OBJECT")
                            || callModuleUpper.Contains("REFRESH-OBJECT") || callModuleUpper.Contains("HIDE-OBJECT")
                            || callModuleUpper.Contains("SQLGINTP") || callModuleUpper.Contains("SET-FOCUS")
                            || callModuleUpper.Contains("SET-MOUSE-SHAPE") || callModuleUpper.Contains("SHOW-OBJECT")
                            || callModuleUpper.Contains("VENT_SEK") || callModuleUpper.Contains("CLEAR-OBJECT")
                            || callModuleUpper.Contains("CC1") || callModuleUpper.Contains("DSRUN")
                            || callModuleUpper.Contains("SET-FIRST-WINDOW") || callModuleUpper.Contains("INVOKE-MESSAGE-BOX")
                            || callModuleUpper.Contains("SET-LIST-ITEM-STATE") || callModuleUpper.Contains("SET-OBJECT-LABEL")
                            || callModuleUpper.Contains("SET-TOP-LIST-ITEM") || callModuleUpper.Contains("VENT_KVARTSEK")
                            || callModuleUpper.Contains("SQLGINTR"))
                            continue;

                        if (callModule.Length > 0)
                        {
                            link = "./" + callModule + ".cbl.html";
                            WriteMmdFlow("click " + callModule + " \"" + link + "\" \"" + callModule + "\" _blank");
                            WriteMmdFlow("style " + callModule + " stroke:dark-blue,stroke-width:4px");
                        }
                    }
                    else if (Regex.IsMatch(itemLine, @".*M[0-9]+\-.*\."))
                    {
                        int pos = itemLine.IndexOf('.');
                        itemLine = itemLine.Substring(0, pos).Replace("--", "-");
                        if (VerifyIfParagraph(itemLine + "."))
                        {
                            link = "https://Dedge.visualstudio.com/_git/Dedge?path=/cbl/" + baseFileName.ToLower()
                                + "&version=GBmaster&line=" + item.LineNumber + "&lineEnd=" + (item.LineNumber + 1)
                                + "&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents";
                            WriteMmdFlow("click " + itemLine + " \"" + link + "\" \"" + itemLine + "\" _blank");
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in NewCblMmdLinks: {ex.Message}", LogLevel.ERROR, ex);
            _errorOccurred = true;
        }
    }

    #endregion

    #region Get-CblExecutionPathDiagram (lines 5511-5598)

    /// <summary>
    /// Generates execution path diagram for CBL programs.
    /// Converted line-by-line from Get-CblExecutionPathDiagram (lines 5511-5598)
    /// </summary>
    private static void GetCblExecutionPathDiagram(string srcRootFolder, string baseFileName, string tmpRootFolder)
    {
        // Line 5514-5523: Skip utility modules
        string baseNameLower = baseFileName.ToLower();
        string[] skipModules = { "gmacoco", "gmacnct", "gmalike", "gmacurt", "gmftrap", "gmffell", "gmadato", "gmfsql" };
        if (skipModules.Any(m => baseNameLower.Contains(m)))
            return;

        int pos = baseFileName.IndexOf('.');
        baseFileName = baseFileName.Substring(0, pos).ToLower();
        string inputDbFileFolder = Path.Combine(tmpRootFolder, "cobdok");

        bool programInUse = false;
        var resultArrayMmd = new List<string>();

        // Line 5533-5564: Get menu data for H (screen) modules
        if (baseFileName.Length > 2 && baseFileName.ToUpper()[2] == 'H')
        {
            string menuCsvPath = Path.Combine(inputDbFileFolder, "cobdok_meny.csv");
            if (File.Exists(menuCsvPath))
            {
                try
                {
                    string[] csvLines = SourceFileCache.GetLines(menuCsvPath) ?? File.ReadAllLines(menuCsvPath, Encoding.UTF8);
                    int counter = 0;
                    foreach (string csvLine in csvLines)
                    {
                        string[] fields = csvLine.Split(';');
                        if (fields.Length > 1 && CsvClean(fields[0]).ToUpper().Contains(baseFileName.ToUpper()))
                        {
                            counter++;
                            string menuSystem = fields.Length > 2 ? CsvClean(fields[2]) : "";
                            string menuText = fields.Length > 1 ? CsvClean(fields[1]) : "";
                            string menuDesc = fields.Length > 3 ? CsvClean(fields[3]) : "";
                            string menuTextFull = "System:" + menuSystem + "\nChoice:" + menuText;
                            if (menuDesc.Length > 0)
                                menuTextFull += "\nDescription:" + menuDesc.Replace("\"", "").Replace("'", "");
                            programInUse = true;
                            resultArrayMmd.Add("menuitem" + counter + "(\"" + menuTextFull + "\")-.->" + baseFileName);
                            resultArrayMmd.Add("style menuitem" + counter + " stroke-dasharray: 5 5");
                        }
                    }
                }
                catch (Exception ex)
                {
                    Logger.LogMessage($"Error reading cobdok_meny.csv: {ex.Message}", LogLevel.WARN);
                }
            }
        }

        // Line 5567-5572: B (batch) modules - check scripts
        if (baseFileName.Length > 2 && baseFileName.ToUpper()[2] == 'B')
        {
            string[] includeFilter = { "*.ps1", "*.bat", "*.rex", "*.cs", "*.psm1" };
            var (pInUse, returnMmdArray2) = ExecutionPathHelper.FindAutoDocExecutionPaths(
                srcRootFolder, includeFilter, baseFileName, programInUse, srcRootFolder);
            programInUse = pInUse;
            foreach (string item in returnMmdArray2) WriteMmdFlow(item);
        }

        // Line 5574-5578: V/A/F modules - check CBL
        if (baseFileName.Length > 2 && "VAF".Contains(baseFileName.ToUpper()[2]))
        {
            string cblPath = Path.Combine(srcRootFolder, "Dedge", "cbl");
            var (pInUse, returnMmdArray2) = ExecutionPathHelper.FindAutoDocExecutionPaths(
                cblPath, new[] { "*.cbl" }, baseFileName, programInUse, srcRootFolder);
            programInUse = pInUse;
            foreach (string item in returnMmdArray2) WriteMmdFlow(item);
        }

        // Line 5580-5583: H modules - check BAT
        if (baseFileName.Length > 2 && baseFileName.ToUpper()[2] == 'H')
        {
            string batPath = Path.Combine(srcRootFolder, "Dedge", "bat_prod");
            var (pInUse, returnMmdArray2) = ExecutionPathHelper.FindAutoDocExecutionPaths(
                batPath, new[] { "*.bat", "*.ps1", "*.cs", "*.psm1" }, baseFileName, programInUse, srcRootFolder);
            programInUse = pInUse;
            foreach (string item in returnMmdArray2) WriteMmdFlow(item);
        }

        if (!programInUse)
            Logger.LogMessage($"Program is never called from any other program or script: {baseFileName}", LogLevel.INFO);

        foreach (string item in resultArrayMmd)
            WriteMmdFlow(item);
    }

    #endregion

    #region HandleDiagramGeneration (lines 7481-7777)

    /// <summary>
    /// Main diagram generation orchestrator for COBOL files.
    /// Converted line-by-line from HandleDiagramGeneration (lines 7481-7777)
    /// </summary>
    private static void HandleDiagramGeneration(
        List<string> workArray,
        List<string> procedureContent,
        int fileSectionLineNumber,
        int workingStorageLineNumber,
        List<string> fileSectionContent,
        string baseFileName,
        string outputFolder,
        string tmpRootFolder,
        string srcRootFolder,
        string sourceFile,
        string[] fileContentOriginal,
        bool generateHtml = false)
    {
        // Line 7484-7485: Initialize flowchart diagram
        WriteMmdFlow("%%{ init: { 'flowchart': { 'curve': 'basis' } } }%%");
        WriteMmdFlow("flowchart TD");
        string programName = Path.GetFileNameWithoutExtension(sourceFile).ToLower();

        // Line 7488-7509: Proxy file detection
        string? proxyFilename = null;
        string? proxyClass = null;
        string[]? proxyFileContent = null;

        try
        {
            string testString = string.Join(" ", fileContentOriginal.Where(l => l.ToLower().Contains("-proxy")));
            if (!string.IsNullOrEmpty(testString))
            {
                // Regex: (?<=")[^"]*(?=") - Match text between double quotes
                var resultArrayProxy = Regex.Matches(testString, "(?<=\")[^\"]*(?=\")");
                if (resultArrayProxy.Count == 0)
                    resultArrayProxy = Regex.Matches(testString, "(?<=')[^']*(?=')");

                if (resultArrayProxy.Count > 0)
                {
                    proxyClass = resultArrayProxy[0].Value;
                    proxyFilename = Path.Combine(srcRootFolder, "Dedge", "cbl", proxyClass + ".cbl");
                    proxyClass = proxyClass.Replace("-proxy", "");
                    if (File.Exists(proxyFilename))
                        proxyFileContent = SourceFileCache.GetLines(proxyFilename) ?? File.ReadAllLines(proxyFilename, Encoding.GetEncoding(1252));
                }
            }
        }
        catch { }

        List<string> fileContent = workArray;

        // Line 7514: Find work content using pattern matching
        // Regex: (.*\-.*\.|perform.*until|perform\s*varying|.*perform|not at end perform|end\-perform|call\s*|read\s*|write\s*|stop\s*run|exec\s*sql|end\-exec|procedure\s*division)
        // Match COBOL paragraph names, PERFORM statements, CALL, READ, WRITE, STOP RUN, EXEC SQL, and PROCEDURE DIVISION
        var workContentPattern = new Regex(
            @"(.*\-.*\.|perform.*until|perform\s*varying|.*perform|not at end perform|end\-perform|call\s*|read\s*|write\s*|stop\s*run|exec\s*sql|end\-exec|procedure\s*division)",
            RegexOptions.IgnoreCase);

        var workContent = new List<MatchResult>();
        for (int i = 0; i < procedureContent.Count; i++)
        {
            if (workContentPattern.IsMatch(procedureContent[i]))
                workContent.Add(new MatchResult { LineNumber = i + 1, Line = procedureContent[i] });
        }

        // Line 7517: Find all files and related records
        var fdHashtable = FindAllFileDefinitionsAndRelatedRecords(fileSectionContent, srcRootFolder);

        // Line 7520-7532: Initialization
        string currentParticipant = "";
        string currentParagraphName = "";
        int loopCounter = 0;
        string previousParticipant = "";
        int counter = 0;
        var paragraphCodeExceptLoopCode = new List<MatchResult>();
        List<MatchResult> paragraphCode = new();

        if (workContent.Count == 0)
        {
            Logger.LogMessage("No work content found", LogLevel.ERROR);
            return;
        }

        // Line 7534-7687: Main processing loop
        var loopLevel = new List<string>();
        var loopNodeContent = new List<string>();
        var loopCode = new List<List<MatchResult>>();
        string fromNode = "";

        foreach (var lineObject in workContent)
        {
            counter++;
            if (lineObject.LineNumber - 1 >= procedureContent.Count) continue;
            string line = procedureContent[lineObject.LineNumber - 1];
            int lineNumber = lineObject.LineNumber;

            if (line.StartsWith("*")) continue;

            previousParticipant = currentParagraphName;

            // Line 7548-7611: Paragraph handling
            if (Regex.IsMatch(line, @"^.*M[0-9]+\-.*\.", RegexOptions.IgnoreCase) || Regex.IsMatch(line, @"procedure\.division", RegexOptions.IgnoreCase) || Regex.IsMatch(line, @"procedure.*division", RegexOptions.IgnoreCase))
            {
                if (line.Contains("entry")) continue;

                bool verifiedParagraph = false;
                if (Regex.IsMatch(line, @"procedure\.division", RegexOptions.IgnoreCase) || Regex.IsMatch(line, @"procedure.*division", RegexOptions.IgnoreCase))
                {
                    currentParticipant = "procedure_division";
                    paragraphCode = FindParagraphCode(procedureContent, @"procedure.*division");
                    currentParagraphName = currentParticipant.Trim();
                    verifiedParagraph = true;
                }
                else
                {
                    verifiedParagraph = VerifyIfParagraph(line.Trim());
                    if (verifiedParagraph)
                    {
                        if (previousParticipant == "procedure_division" && line.Replace(".", "").Trim() != "procedure_division")
                        {
                            WriteMmdSequence(previousParticipant + "->>" + line.Replace(".", "").Trim() + ": start");
                            WriteMmdSequence("participant procedure_division");
                        }
                        int dotPos = line.IndexOf('.');
                        string participant = line.Substring(0, dotPos).Trim().Replace("--", "-");
                        WriteMmdSequence("participant " + participant.Replace(".", "").Trim());

                        if (paragraphCodeExceptLoopCode.Count > 0)
                        {
                            loopCounter = 0;
                            NewCblNodes(paragraphCodeExceptLoopCode, procedureContent, fileContent, previousParticipant, fdHashtable, loopCounter);
                        }

                        dotPos = line.IndexOf('.');
                        currentParticipant = line.Substring(0, dotPos).Trim().Replace("--", "-");
                        currentParagraphName = currentParticipant.Trim();
                        paragraphCode = FindParagraphCode(procedureContent, currentParticipant);
                    }
                }

                if (verifiedParagraph)
                {
                    loopLevel = new List<string>();
                    loopNodeContent = new List<string>();
                    loopCode = new List<List<MatchResult>>();
                    paragraphCodeExceptLoopCode = new List<MatchResult>();

                    // Line 7600-7610: Program name to initial paragraph
                    if (previousParticipant.Length == 0 && (currentParticipant.Length > 0 || currentParticipant == "procedure_division"))
                    {
                        string statement = programName + "[[" + programName + "]]" + " --initiated-->" + currentParticipant + "((" + currentParticipant + "))";
                        WriteMmdFlow(statement);
                        WriteMmdFlow("style " + programName + " stroke:red,stroke-width:4px");
                    }
                    if (previousParticipant == "procedure_division")
                    {
                        string statement = previousParticipant + "(" + previousParticipant + ")" + " --start-->" + currentParticipant + "(" + currentParticipant + ")";
                        WriteMmdFlow(statement);
                    }
                }
            }

            if (paragraphCode.Count == 0) continue;

            bool skipLine = false;

            // Line 7625-7667: Perform handling (loops)
            if (line.Trim().Contains("perform until") || line.Trim().Contains("perform varying")
                || line.Trim().Contains("until") || (line.Trim().Contains("perform") && line.Trim().Contains(" times"))
                || line.Trim().Contains("perform exit") || line.ToLower().Trim().Contains("perform with test before"))
            {
                loopCounter++;
                string toNode;
                if (loopCounter > 1 && loopLevel.Count >= loopCounter - 1)
                {
                    fromNode = loopLevel[loopCounter - 2];
                    toNode = loopLevel[loopCounter - 2] + loopCounter + "((" + loopLevel[loopCounter - 2] + loopCounter + "))";
                    loopLevel.Add(currentParticipant + "-loop" + loopCounter);
                }
                else
                {
                    fromNode = currentParticipant;
                    toNode = currentParticipant + "-loop" + "((" + currentParticipant + "-loop))";
                    loopLevel.Add(currentParticipant + "-loop");
                }
                loopNodeContent.Add(toNode);
                loopCode.Add(new List<MatchResult>());
                WriteMmdFlow(fromNode + "--\"perform \"-->" + toNode);
                skipLine = true;
            }

            if (skipLine && line.Contains("end-perform"))
            {
                if (loopCounter > 0 && loopCode.Count >= loopCounter)
                {
                    WriteMmdSequence("participant " + loopLevel[loopCounter - 1].Trim());
                    WriteMmdSequence(fromNode + "->>" + loopLevel[loopCounter - 1] + ":loop");
                    NewCblNodes(loopCode[loopCounter - 1], procedureContent, fileContent, loopLevel[loopCounter - 1], fdHashtable, loopCounter);

                    loopLevel.RemoveAt(loopCounter - 1);
                    loopNodeContent.RemoveAt(loopCounter - 1);
                    loopCode.RemoveAt(loopCounter - 1);
                    loopCounter--;
                }
            }
            else if (line.Contains("end-perform"))
            {
                if (loopCounter > 0 && loopCode.Count >= loopCounter)
                {
                    WriteMmdSequence("participant " + loopLevel[loopCounter - 1].Trim());
                    WriteMmdSequence(fromNode + "->>" + loopLevel[loopCounter - 1] + ":loop");
                    NewCblNodes(loopCode[loopCounter - 1], procedureContent, fileContent, loopLevel[loopCounter - 1], fdHashtable, loopCounter);

                    loopLevel.RemoveAt(loopCounter - 1);
                    loopNodeContent.RemoveAt(loopCounter - 1);
                    loopCode.RemoveAt(loopCounter - 1);
                    loopCounter--;
                }
                skipLine = true;
            }

            // Line 7669-7686: Accumulate lines
            if (!skipLine)
            {
                if (loopCounter > 0 && loopCode.Count >= loopCounter)
                {
                    loopCode[loopCounter - 1].Add(lineObject);
                }
                else
                {
                    paragraphCodeExceptLoopCode.Add(lineObject);
                }
            }
        }

        // Line 7688-7690: Generate nodes for last paragraph
        loopCounter = 0;
        NewCblNodes(paragraphCodeExceptLoopCode, procedureContent, fileContent, currentParagraphName, fdHashtable, loopCounter);

        // Line 7693: Generate links
        NewCblMmdLinks(baseFileName, sourceFile, proxyFilename, proxyClass, proxyFileContent, fileContentOriginal);

        // Line 7696: Execution path diagram
        GetCblExecutionPathDiagram(srcRootFolder, baseFileName, tmpRootFolder);

        // Line 7698-7776: Sort participants in sequence diagram
        if (_useClientSideRender)
        {
            if (_mmdSequenceContent.Count == 0)
            {
                WriteMmdSequence("procedure_division->>logic: logic");
                WriteMmdSequence("participant procedure_division");
            }

            var participantArray = new List<string>();
            var remainingArray = new List<string>();
            var uniqueContent = _mmdSequenceContent.Distinct().ToList();
            foreach (string? line2 in uniqueContent)
            {
                if (line2 == null) continue;
                string lineStr = line2.Replace("-x", "_x").Replace("create-", "create_");
                if (lineStr.Contains("participant"))
                    participantArray.Add(lineStr);
                else
                    remainingArray.Add(lineStr);
            }

            _mmdSequenceContent.Clear();
            _mmdSequenceContent.Add("sequenceDiagram");
            _mmdSequenceContent.Add("autonumber");
            _mmdSequenceContent.AddRange(participantArray);
            _mmdSequenceContent.AddRange(remainingArray);
        }
        else
        {
            string? tempFileName = _mmdFilenameSequence;
            if (tempFileName != null && !File.Exists(tempFileName))
            {
                WriteMmdSequence("procedure_division->>logic: logic");
                WriteMmdSequence("participant procedure_division");
            }

            if (tempFileName != null && File.Exists(tempFileName))
            {
                var participantArray = new List<string>();
                var remainingArray = new List<string>();
                string[] seqFileContent = File.ReadAllLines(tempFileName);
                var uniqueContent = seqFileContent.Distinct().ToList();
                foreach (string line2 in uniqueContent)
                {
                    string lineStr = line2.Replace("-x", "_x").Replace("create-", "create_");
                    if (lineStr.Contains("participant"))
                        participantArray.Add(lineStr);
                    else
                        remainingArray.Add(lineStr);
                }
                var array = new List<string> { "sequenceDiagram", "autonumber" };
                array.AddRange(participantArray);
                array.AddRange(remainingArray);
                File.WriteAllLines(tempFileName, array, Encoding.UTF8);
            }
        }
    }

    #endregion

    #region Get-CblMetaData (lines 6082-6435)

    /// <summary>
    /// Retrieves metadata from cobdok CSV files and generates HTML output.
    /// Converted line-by-line from Get-CblMetaData (lines 6082-6435)
    /// </summary>
    private static void GetCblMetaData(string tmpRootFolder, string outputFolder, string baseFileName, string sourceFile = "", bool generateHtml = false)
    {
        string htmlDesc = "";
        string htmlType = "";
        string htmlSystem = "";
        string htmlUseSql = "false";
        string htmlUseDs = "false";
        string htmlCreatedDateTime = "";
        string htmlLastProdDateTime = "";
        string htmlProdLog = "";
        string htmlComments = "";
        string htmlSqlTables = "";
        string htmlCallList = "";
        string htmlCopyList = "";
        string htmlExecutionPoints = "";

        // Structured data for JSON output
        string jsonTypeCode = "";
        var jsonSqlTables = new List<SqlTableRef>();
        var jsonSubprograms = new List<SubprogramRef>();
        var jsonCopyElements = new List<CopyElementRef>();
        var jsonChangeLog = new List<ChangeLogEntry>();
        var jsonProductionLog = new List<ProductionLogEntry>();

        try
        {
            string inputDbFileFolder = Path.Combine(tmpRootFolder, "cobdok");
            string searchProgramName = baseFileName.ToLower().Split('.')[0];

            // Line 6090-6123: modul.csv
            string modulCsvPath = Path.Combine(inputDbFileFolder, "modul.csv");
            string[]? csvModulLines = null;
            if (File.Exists(modulCsvPath))
            {
                csvModulLines = SourceFileCache.GetLines(modulCsvPath) ?? File.ReadAllLines(modulCsvPath, Encoding.UTF8);
                foreach (string csvLine in csvModulLines)
                {
                    string[] fields = csvLine.Split(';');
                    if (fields.Length > 5 && CsvClean(fields[2]).Contains(searchProgramName.ToUpper()))
                    {
                        htmlSystem = CsvClean(fields[1]);
                        htmlDesc = CsvClean(fields[3]);
                        jsonTypeCode = CsvClean(fields[4]);
                        htmlType = jsonTypeCode;
                        htmlType = htmlType switch
                        {
                            "B" => "B - Batchprogram",
                            "H" => "H - Main user interface",
                            "S" => "S - Webservice",
                            "V" => "V - Validation module for user interface",
                            "A" => "A - Common module",
                            "F" => "F - Search module for user interface",
                            _ => htmlType
                        };
                        htmlUseSql = fields.Length > 6 ? CsvClean(fields[6]).Replace("N", "false").Replace("J", "true") : "false";
                        htmlUseDs = fields.Length > 5 ? CsvClean(fields[5]).Replace("N", "false").Replace("J", "true") : "false";
                        break;
                    }
                }
            }

            // Line 6125-6133: delsystem.csv
            string delsystemCsvPath = Path.Combine(inputDbFileFolder, "delsystem.csv");
            if (File.Exists(delsystemCsvPath))
            {
                string[] csvDelsystemLines = SourceFileCache.GetLines(delsystemCsvPath) ?? File.ReadAllLines(delsystemCsvPath, Encoding.UTF8);
                foreach (string csvLine in csvDelsystemLines)
                {
                    string[] fields = csvLine.Split(';');
                    if (fields.Length > 2 && CsvClean(fields[0]).Contains("FKAVDNT") && CsvClean(fields[1]).Contains(htmlSystem))
                    {
                        htmlSystem = htmlSystem + " - " + CsvClean(fields[2]);
                        break;
                    }
                }
            }

            // Line 6135-6161: tiltp_log.csv
            string tiltpLogCsvPath = Path.Combine(inputDbFileFolder, "tiltp_log.csv");
            if (File.Exists(tiltpLogCsvPath))
            {
                string[] csvTiltpLines = SourceFileCache.GetLines(tiltpLogCsvPath) ?? File.ReadAllLines(tiltpLogCsvPath, Encoding.UTF8);
                var matchingLines = csvTiltpLines.Where(l => l.Split(';').Length > 0 && CsvClean(l.Split(';')[0]).Contains(searchProgramName.ToUpper())).ToList();

                if (matchingLines.Count > 0)
                {
                    // First entry (oldest after sort)
                    var sortedAsc = matchingLines.OrderBy(x => x).ToList();
                    try
                    {
                        var firstItem = sortedAsc.Last();
                        string[] firstFields = firstItem.Split(';');
                        if (firstFields.Length > 3)
                        {
                            string tempWork = CsvClean(firstFields[3]);
                            if (tempWork.Length >= 16)
                                htmlCreatedDateTime = tempWork.Substring(8, 2) + "/" + tempWork.Substring(5, 2) + "/" + tempWork.Substring(0, 4) + " - " + tempWork.Substring(11, 2) + ":" + tempWork.Substring(14, 2) + " (" + CsvClean(firstFields[2]) + ")";
                        }
                    }
                    catch { }

                    // Last entry (newest)
                    try
                    {
                        var lastItem = sortedAsc.First();
                        string[] lastFields = lastItem.Split(';');
                        if (lastFields.Length > 3)
                        {
                            string tempWork = CsvClean(lastFields[3]);
                            if (tempWork.Length >= 16)
                                htmlLastProdDateTime = tempWork.Substring(8, 2) + "/" + tempWork.Substring(5, 2) + "/" + tempWork.Substring(0, 4) + " - " + tempWork.Substring(11, 2) + ":" + tempWork.Substring(14, 2) + " (" + CsvClean(lastFields[2]) + ")";
                        }
                    }
                    catch { }

                    // Production log entries
                    var workArray = new List<string>();
                    foreach (string item in sortedAsc)
                    {
                        string[] fields = item.Split(';');
                        if (fields.Length > 3)
                        {
                            string tempWork = CsvClean(fields[3]);
                            string tempWorkUser = CsvClean(fields[2]);
                            if (tempWork.Length >= 16)
                            {
                                string formattedDate = tempWork.Substring(8, 2) + "/" + tempWork.Substring(5, 2) + "/" + tempWork.Substring(0, 4) + " - " + tempWork.Substring(11, 2) + ":" + tempWork.Substring(14, 2);
                                string workString = "<tr><td>" + formattedDate + "</td><td>" + tempWorkUser + "</td></tr>";
                                workArray.Add(workString);
                                jsonProductionLog.Add(new ProductionLogEntry { Date = formattedDate, User = tempWorkUser });
                            }
                        }
                    }
                    htmlProdLog = string.Join("", workArray);
                }
            }

            // Line 6164-6254: modkom.csv (comments/changelog)
            string modkomCsvPath = Path.Combine(inputDbFileFolder, "modkom.csv");
            if (File.Exists(modkomCsvPath))
            {
                string[] csvModkomLines = SourceFileCache.GetLines(modkomCsvPath) ?? File.ReadAllLines(modkomCsvPath, Encoding.UTF8);
                var matchingLines = csvModkomLines.Where(l =>
                {
                    string[] f = l.Split(';');
                    return f.Length > 1 && CsvClean(f[0]).Contains("FKAVDNT") && CsvClean(f[1]).Contains(searchProgramName.ToUpper());
                }).OrderBy(x => x).ToList();

                if (matchingLines.Count > 0)
                {
                    var rawComments = new List<string>();
                    string workString = "";
                    foreach (string item in matchingLines)
                    {
                        string[] fields = item.Split(';');
                        if (fields.Length > 3)
                        {
                            string tempWork = CsvClean(fields[3]);
                            if (tempWork.Length > 0)
                            {
                                if (workString != "" && char.IsDigit(tempWork[0]))
                                {
                                    rawComments.Add(workString + " ");
                                    workString = "";
                                }
                            }
                            workString += " " + tempWork.Trim();
                        }
                    }
                    rawComments.Add(workString);

                    var sortedComments = new List<string>();
                    foreach (string item in rawComments)
                    {
                        string trimmed = item.Trim();
                        int spacePos = trimmed.IndexOf(' ');
                        if (trimmed.Length <= 0 || spacePos <= 0) continue;

                        string dateStr, commentInitials, comment;
                        try
                        {
                            string dateCandidate = trimmed.Substring(0, spacePos);
                            DateTime date;
                            try { date = DateTime.Parse(dateCandidate); }
                            catch { date = new DateTime(1970, 1, 1); }

                            string rest = trimmed.Substring(spacePos).Trim();
                            int restSpacePos = rest.IndexOf(' ');
                            if (restSpacePos > 0)
                            {
                                commentInitials = rest.Substring(0, restSpacePos);
                                if (commentInitials.Trim().Length > 3)
                                {
                                    commentInitials = "N/A";
                                    comment = trimmed.Trim();
                                }
                                else
                                    comment = rest.Substring(restSpacePos).Trim();
                            }
                            else
                            {
                                commentInitials = "N/A";
                                comment = rest;
                            }

                            dateStr = date.ToString("yyyyMMdd");
                        }
                        catch { dateStr = "19700101"; commentInitials = "N/A"; comment = trimmed; }

                        sortedComments.Add(dateStr + "\u00B6" + commentInitials + "\u00B6" + comment);
                    }

                    sortedComments.Sort();
                    var commentHtmlList = new List<string>();
                    foreach (string item in sortedComments)
                    {
                        string[] split = item.Split('\u00B6');
                        if (split.Length < 3) continue;
                        string year = split[0].Substring(0, 4);
                        string month = split[0].Substring(4, 2);
                        string day = split[0].Substring(6, 2);
                        string formattedDate = day + "/" + month + "/" + year;
                        commentHtmlList.Add("<tr><td>" + formattedDate + "</td><td>" + split[1].Trim() + "</td><td>" + split[2].Trim() + "</td></tr>");
                        jsonChangeLog.Add(new ChangeLogEntry { Date = formattedDate, User = split[1].Trim(), Comment = split[2].Trim() });
                    }
                    htmlComments = string.Join("", commentHtmlList);
                }
            }

            // Line 6257-6305: sqlxtab.csv and tables.csv
            string sqlxtabCsvPath = Path.Combine(inputDbFileFolder, "sqlxtab.csv");
            string tablesCsvPath = Path.Combine(inputDbFileFolder, "tables.csv");
            if (File.Exists(sqlxtabCsvPath) && File.Exists(tablesCsvPath))
            {
                string[] csvTablesLines = SourceFileCache.GetLines(tablesCsvPath) ?? File.ReadAllLines(tablesCsvPath, Encoding.UTF8);
                string[] csvSqlxtabLines = SourceFileCache.GetLines(sqlxtabCsvPath) ?? File.ReadAllLines(sqlxtabCsvPath, Encoding.UTF8);
                var matchingSqlxtab = csvSqlxtabLines.Where(l =>
                {
                    string[] f = l.Split(';');
                    return f.Length > 4 && CsvClean(f[0]).Contains("FKAVDNT") && CsvClean(f[1]).Contains(searchProgramName.ToUpper());
                }).OrderBy(x => x).Distinct().ToList();

                if (matchingSqlxtab.Count > 0)
                {
                    var workArray = new List<string>();
                    foreach (string item in matchingSqlxtab)
                    {
                        string[] fields = item.Split(';');
                        string tableName = CsvClean(fields[4]);
                        string tableOperationDesc = CsvClean(fields[3]) switch
                        {
                            "S" => "Select", "I" => "Insert", "U" => "Update", "D" => "Delete", _ => CsvClean(fields[3])
                        };

                        int dotPos = tableName.IndexOf('.');
                        string tableNameWithoutSchema = dotPos >= 0 ? tableName.Substring(dotPos + 1).ToUpper().Trim() : tableName.ToUpper().Trim();

                        string tableRemarks = "";
                        foreach (string tableLine in csvTablesLines)
                        {
                            string[] tableFields = tableLine.Split(';');
                            if (tableFields.Length > 2 && CsvClean(tableFields[1]).Contains(tableNameWithoutSchema))
                            {
                                tableRemarks = CsvClean(tableFields[2]);
                                if (tableRemarks.Length > 0)
                                    tableRemarks = tableRemarks.Substring(0, 1).ToUpper() + tableRemarks.Substring(1).ToLower();
                                break;
                            }
                        }

                        string filelink = ("./" + tableName.Replace(".", "_").Trim() + ".sql.html").Trim().ToUpper()
                            .Replace("Æ", "AE").Replace("Ø", "OE").Replace("Å", "AA").ToLower();
                        string tablenamelink = "<a href=\"" + filelink + "\" target=\"_blank\">" + tableName + "</a>";
                        workArray.Add("<tr><td>" + tablenamelink + "</td><td>" + tableOperationDesc + "</td><td>" + tableRemarks + "</td></tr>");
                        jsonSqlTables.Add(new SqlTableRef { Table = tableName, Operation = tableOperationDesc, Description = tableRemarks, Link = filelink });
                    }
                    htmlSqlTables = string.Join("", workArray.Distinct().OrderBy(x => x));
                }
            }

            // Line 6307-6337: call.csv
            string callCsvPath = Path.Combine(inputDbFileFolder, "call.csv");
            if (File.Exists(callCsvPath) && csvModulLines != null)
            {
                string[] csvCallLines = SourceFileCache.GetLines(callCsvPath) ?? File.ReadAllLines(callCsvPath, Encoding.UTF8);
                var matchingCalls = csvCallLines.Where(l =>
                {
                    string[] f = l.Split(';');
                    return f.Length > 2 && CsvClean(f[0]).Contains("FKAVDNT") && CsvClean(f[1]).Contains(searchProgramName.ToUpper());
                }).OrderBy(x => x).ToList();

                if (matchingCalls.Count > 0)
                {
                    var workArray = new List<string>();
                    foreach (string item in matchingCalls)
                    {
                        string[] fields = item.Split(';');
                        string call = CsvClean(fields[2]);
                        string callDesc = "N/A";

                        foreach (string modulLine in csvModulLines)
                        {
                            string[] modulFields = modulLine.Split(';');
                            if (modulFields.Length > 3 && CsvClean(modulFields[0]).Contains("FKAVDNT") && CsvClean(modulFields[2]).Contains(call.ToUpper()))
                            {
                                callDesc = CsvClean(modulFields[3]);
                                if (callDesc.Length > 0)
                                    callDesc = callDesc.Substring(0, 1).ToUpper() + callDesc.Substring(1).ToLower();
                                break;
                            }
                        }

                        string callLink = "./" + call + ".cbl.html";
                        string link = "<a href=\"" + callLink + "\" target=\"_blank\">" + call + "</a>";
                        workArray.Add("<tr><td>" + link + "</td><td>" + callDesc + "</td></tr>");
                        jsonSubprograms.Add(new SubprogramRef { Module = call, Description = callDesc, Link = callLink });
                    }
                    htmlCallList = string.Join("", workArray);
                }
            }

            // Line 6340-6360: copy.csv
            string copyCsvPath = Path.Combine(inputDbFileFolder, "copy.csv");
            if (File.Exists(copyCsvPath))
            {
                string[] csvCopyLines = SourceFileCache.GetLines(copyCsvPath) ?? File.ReadAllLines(copyCsvPath, Encoding.UTF8);
                var matchingCopies = csvCopyLines.Where(l =>
                {
                    string[] f = l.Split(';');
                    return f.Length > 2 && CsvClean(f[0]).Contains("FKAVDNT") && CsvClean(f[1]).Contains(searchProgramName.ToUpper());
                }).OrderBy(x => x).ToList();

                if (matchingCopies.Count > 0)
                {
                    var workArray = new List<string>();
                    foreach (string item in matchingCopies)
                    {
                        string[] fields = item.Split(';');
                        string copyElementFile = CsvClean(fields[2]);
                        int dotPos = copyElementFile.IndexOf('.');
                        string fileSuffix = dotPos >= 0 ? copyElementFile.Substring(dotPos + 1).ToLower().Trim() : "";
                        string copyLink = "https://Dedge.visualstudio.com/Dedge/_search?action=contents&text=" + copyElementFile + "%20ext%3A" + fileSuffix.Trim() + "&type=code&lp=code-Project&filters=ProjectFilters%7BDedge%7DRepositoryFilters%7BDedge%7D&pageSize=25";
                        string link = "<a href=\"" + copyLink + "\">" + copyElementFile.ToLower() + "</a>";
                        workArray.Add("<tr><td>" + link + "</td></tr>");
                        jsonCopyElements.Add(new CopyElementRef { Name = copyElementFile.ToLower(), Link = copyLink });
                    }
                    htmlCopyList = string.Join("", workArray);
                }
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error in GetCblMetaData: {ex.Message}", LogLevel.ERROR, ex);
            _errorOccurred = true;
        }

        // Line 6371-6432: Generate HTML file
        string htmlFilename = Path.Combine(outputFolder, baseFileName + ".html");
        string templatePath = Path.Combine(outputFolder, "_templates");
        string mmdTemplateFilename = Path.Combine(templatePath, "cblmmdtemplate.html");

        string tmpl = "";
        if (File.Exists(mmdTemplateFilename))
            tmpl = File.ReadAllText(mmdTemplateFilename, Encoding.UTF8);
        else
        {
            string sharedTemplatesFolder = ParserBase.GetAutodocTemplatesFolder();
            string sharedTemplatePath = Path.Combine(sharedTemplatesFolder, "cblmmdtemplate.html");
            if (File.Exists(sharedTemplatePath))
                tmpl = File.ReadAllText(sharedTemplatePath, Encoding.UTF8);
            else { Logger.LogMessage($"Template not found: {mmdTemplateFilename}", LogLevel.ERROR); return; }
        }

        try
        {
            string doc = ParserBase.SetAutodocTemplate(tmpl, outputFolder);
            doc = doc.Replace("[title]", "AutoDoc Diagrams - Cobol Source File - " + baseFileName.ToLower());
            doc = doc.Replace("[desc]", htmlDesc);
            doc = doc.Replace("[generated]", DateTime.Now.ToString());
            doc = doc.Replace("[type]", htmlType);
            doc = doc.Replace("[system]", htmlSystem);
            doc = doc.Replace("[usesql]", htmlUseSql);
            doc = doc.Replace("[useds]", htmlUseDs);

            string screenBaseName = baseFileName.ToUpper().Replace(".CBL", "");
            string screenHtmlFile = Path.Combine(outputFolder, screenBaseName + ".screen.html");
            if (File.Exists(screenHtmlFile))
            {
                doc = doc.Replace("[screenlinkstyle]", "");
                doc = doc.Replace("[screenlink]", "./" + screenBaseName + ".screen.html");
                doc = doc.Replace("[screenlinktext]", screenBaseName + " Screen");
            }
            else
            {
                doc = doc.Replace("[screenlinkstyle]", "display: none;");
                doc = doc.Replace("[screenlink]", "#");
                doc = doc.Replace("[screenlinktext]", "");
            }

            doc = doc.Replace("[created]", htmlCreatedDateTime);
            doc = doc.Replace("[prodinfo]", htmlLastProdDateTime);
            doc = doc.Replace("[prodlog]", htmlProdLog);
            doc = doc.Replace("[changelog]", htmlComments);
            doc = doc.Replace("[sqltables]", htmlSqlTables);
            doc = doc.Replace("[calllist]", htmlCallList);
            doc = doc.Replace("[copylist]", htmlCopyList);
            doc = doc.Replace("[execlist]", htmlExecutionPoints.Length > 0 ? htmlExecutionPoints : "");
            doc = doc.Replace("[githistory]", GitStatsService.RenderHtmlRows(GitStatsService.GetStats(sourceFile, Path.GetDirectoryName(sourceFile) ?? "")));

            if (_useClientSideRender)
            {
                doc = doc.Replace("[flowmmd_content]", string.Join("\n", _mmdFlowContent));
                doc = doc.Replace("[sequencemmd_content]", string.Join("\n", _mmdSequenceContent));
            }

            doc = doc.Replace("[flowdiagram]", "./" + baseFileName + ".flow.svg");
            doc = doc.Replace("[sequencediagram]", "./" + baseFileName + ".sequence.svg");
            doc = doc.Replace("[sourcefile]", baseFileName.ToLower());
            if (generateHtml)
            {
                File.WriteAllText(htmlFilename, doc, Encoding.UTF8);
                Logger.LogMessage($"Generated HTML file: {htmlFilename}", LogLevel.INFO);
            }
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error generating HTML file: {ex.Message}", LogLevel.ERROR, ex);
            _errorOccurred = true;
        }

        // Write JSON result alongside HTML
        try
        {
            string screenBaseName = baseFileName.ToUpper().Replace(".CBL", "");
            string screenHtmlFile = Path.Combine(outputFolder, screenBaseName + ".screen.html");
            var cblResult = new CblResult
            {
                Type = "CBL",
                FileName = baseFileName,
                Title = "AutoDoc Diagrams - Cobol Source File - " + baseFileName.ToLower(),
                Description = htmlDesc,
                GeneratedAt = DateTime.Now.ToString("o"),
                SourceFile = baseFileName.ToLower(),
                Metadata = new CblMetadata
                {
                    TypeCode = jsonTypeCode,
                    TypeLabel = htmlType,
                    System = htmlSystem,
                    UsesSql = htmlUseSql == "true",
                    UsesDialogSystem = htmlUseDs == "true",
                    ScreenLink = File.Exists(screenHtmlFile) ? "./" + screenBaseName + ".screen.html" : "",
                    ScreenLinkText = File.Exists(screenHtmlFile) ? screenBaseName + " Screen" : "",
                    Created = htmlCreatedDateTime,
                    LastProduction = htmlLastProdDateTime
                },
                Diagrams = new DiagramData
                {
                    FlowMmd = string.Join("\n", _mmdFlowContent),
                    SequenceMmd = string.Join("\n", _mmdSequenceContent)
                },
                SqlTables = jsonSqlTables,
                CalledSubprograms = jsonSubprograms,
                CopyElements = jsonCopyElements,
                ChangeLog = jsonChangeLog,
                ProductionLog = jsonProductionLog
            };
            cblResult.GitHistory = GitStatsService.GetStats(sourceFile, Path.GetDirectoryName(sourceFile) ?? "");
            JsonResultWriter.WriteResult(cblResult, outputFolder, baseFileName);
        }
        catch (Exception ex)
        {
            Logger.LogMessage($"Error writing JSON result for {baseFileName}: {ex.Message}", LogLevel.WARN);
        }
    }

    #endregion

    #region Start-CblParse (lines 7794-7988)

    /// <summary>
    /// Main entry point for COBOL file parsing.
    /// Converted line-by-line from Start-CblParse (lines 7794-7988)
    /// </summary>
    public static string? StartCblParse(
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
        string optPath = Environment.GetEnvironmentVariable("OptPath") ?? "C:\\opt";
        if (string.IsNullOrEmpty(outputFolder)) outputFolder = Path.Combine(optPath, "Webs", "AutoDocJson");
        if (string.IsNullOrEmpty(tmpRootFolder)) tmpRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp");
        if (string.IsNullOrEmpty(srcRootFolder)) srcRootFolder = Path.Combine(optPath, "data", "AutoDocJson", "tmp", "DedgeRepository");

        // Line 7846-7849: Initialize script-level variables
        _sequenceNumber = 0;
        string baseFileName = Path.GetFileName(sourceFile);
        _baseFileNameTemp = baseFileName.Replace(".cbl", "");

        // Line 7852-7855: Remove dummy file
        string dummyFile = Path.Combine(outputFolder, baseFileName + ".err");
        if (File.Exists(dummyFile)) File.Delete(dummyFile);

        Logger.LogMessage($"Starting parsing of filename: {sourceFile}", LogLevel.INFO);

        // Line 7860-7863: Validate filename
        if (baseFileName.Contains(" "))
        { Logger.LogMessage($"Filename is not valid. Contains spaces: {baseFileName}", LogLevel.ERROR); return null; }

        // Line 7865-7867: Initialize
        _mmdSequenceElementsWritten = 0;
        DateTime startTime = DateTime.Now;
        _mmdFlowContent = new List<string>();
        _mmdSequenceContent = new List<string>();
        _mmdFilenameFlow = Path.Combine(outputFolder, baseFileName + ".flow.mmd");
        _mmdFilenameSequence = Path.Combine(outputFolder, baseFileName + ".sequence.mmd");

        if (!clientSideRender)
        {
            if (File.Exists(_mmdFilenameFlow)) File.Delete(_mmdFilenameFlow);
            if (File.Exists(_mmdFilenameSequence)) File.Delete(_mmdFilenameSequence);
        }

        string htmlFilename = Path.Combine(outputFolder, baseFileName + ".html");
        _errorOccurred = false;
        _sqlTableArray = new List<string>();
        string inputDbFileFolder = Path.Combine(tmpRootFolder, "cobdok");
        _duplicateLineCheck = new HashSet<string>();
        _useClientSideRender = clientSideRender;

        Logger.LogMessage($"Started for: {baseFileName}", LogLevel.INFO);

        if (!clientSideRender)
            File.WriteAllText(_mmdFilenameFlow, "", Encoding.UTF8);

        // Line 7904-7910: Read source file
        string[] fileContentOriginal;
        if (File.Exists(sourceFile))
            fileContentOriginal = SourceFileCache.GetLines(sourceFile) ?? File.ReadAllLines(sourceFile, Encoding.GetEncoding(1252));
        else
        { Logger.LogMessage($"File not found: {sourceFile}", LogLevel.ERROR); return null; }

        // Line 7913: Pre-process
        var preprocessResult = PreProcessFileContent(fileContentOriginal);

        // Line 7915: Handle diagram generation
        HandleDiagramGeneration(
            preprocessResult.WorkArray, preprocessResult.ProcedureContent,
            preprocessResult.FileSectionLineNumber, preprocessResult.WorkingStorageLineNumber,
            preprocessResult.FileSectionContent, baseFileName, outputFolder, tmpRootFolder, srcRootFolder,
            sourceFile, fileContentOriginal, generateHtml);

        // Line 7917-7933: Generate SVG files
        if (!baseFileName.ToUpper().Contains("D4BMAL"))
        {
            if (!clientSideRender)
            {
                if (File.Exists(_mmdFilenameFlow))
                {
                    bool result = ExecutionPathHelper.GenerateSvgFile(_mmdFilenameFlow);
                    if (!result) File.Create(dummyFile).Close();
                }
                if (File.Exists(_mmdFilenameSequence))
                {
                    bool result = ExecutionPathHelper.GenerateSvgFile(_mmdFilenameSequence);
                    if (!result) File.Create(dummyFile).Close();
                }
            }
        }

        // Line 7936-7944: Handle metadata
        if (!_errorOccurred)
        {
            GetCblMetaData(tmpRootFolder, outputFolder, baseFileName, sourceFile, generateHtml);

            if (show)
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                {
                    FileName = htmlFilename,
                    UseShellExecute = true
                });
            }
        }

        // Line 7946-7961: Save MMD files
        DateTime endTime = DateTime.Now;
        TimeSpan timeDiff = endTime - startTime;

        if (saveMmdFiles)
        {
            if (_mmdFlowContent.Count > 0)
            {
                string flowMmdOutputPath = Path.Combine(outputFolder, baseFileName + ".flow.mmd");
                File.WriteAllLines(flowMmdOutputPath, _mmdFlowContent, Encoding.UTF8);
                Logger.LogMessage($"Saved flow MMD file: {flowMmdOutputPath}", LogLevel.INFO);
            }
            if (_mmdSequenceContent.Count > 0)
            {
                string seqMmdOutputPath = Path.Combine(outputFolder, baseFileName + ".sequence.mmd");
                File.WriteAllLines(seqMmdOutputPath, _mmdSequenceContent, Encoding.UTF8);
                Logger.LogMessage($"Saved sequence MMD file: {seqMmdOutputPath}", LogLevel.INFO);
            }
        }

        // Line 7964-7987: Return result
        htmlFilename = Path.Combine(outputFolder, baseFileName + ".html");
        string jsonFilePath = Path.Combine(outputFolder, baseFileName + ".json");
        bool htmlWasGenerated = File.Exists(htmlFilename) || File.Exists(jsonFilePath);

        if (htmlWasGenerated)
        {
            if (File.Exists(dummyFile)) File.Delete(dummyFile);
            Logger.LogMessage($"Time elapsed: {timeDiff.Seconds}", LogLevel.INFO);
            Logger.LogMessage(_errorOccurred ? $"Completed with warnings: {baseFileName}" : $"Completed successfully: {baseFileName}",
                _errorOccurred ? LogLevel.WARN : LogLevel.INFO);
            return htmlFilename;
        }
        else
        {
            Logger.LogMessage("*******************************************************************************", LogLevel.ERROR);
            Logger.LogMessage($"Failed - HTML not generated: {sourceFile}", LogLevel.ERROR);
            Logger.LogMessage("*******************************************************************************", LogLevel.ERROR);
            File.WriteAllText(dummyFile, $"Error: HTML file was not generated for {baseFileName}", Encoding.UTF8);
            return null;
        }
    }

    #endregion
}
