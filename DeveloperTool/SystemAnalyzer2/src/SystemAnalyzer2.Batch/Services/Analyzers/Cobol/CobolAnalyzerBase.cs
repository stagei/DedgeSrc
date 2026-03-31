using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace SystemAnalyzer2.Batch.Services.Analyzers.Cobol;

/// <summary>Generic COBOL dependency patterns (COBOL-85/2002). Used by <see cref="DependencyExtractor"/> and vendor analyzers.</summary>
public abstract class CobolAnalyzerBase : AnalyzerBase
{
    public override string TechnologyId => "cobol";

    public static readonly Regex CopyPattern = new(
        @"\bCOPY\s+['""]?([A-Z0-9_\-\\.]+)['""]?\s*\.?", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly Regex CallPattern = new(
        @"(?<![A-Za-z0-9\-])CALL\s+['""]?([A-Z0-9_\-]+)['""]?(?:\s|$)", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly Regex CallExtensionStrip = new(
        @"\.(cbl|CBL|obj|OBJ)$", RegexOptions.Compiled);

    public static readonly Regex SqlBlockPattern = new(
        @"EXEC\s+SQL\s+(.+?)END-EXEC", RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.Compiled);

    public static readonly Regex SqlTablePattern = new(
        @"\b(SELECT|INSERT\s+INTO|UPDATE|DELETE\s+FROM|MERGE\s+INTO|FROM|JOIN|INTO|TABLE|INCLUDE)\s+(?:(\w+)\.)?(\w+)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly Regex SelectAssignPattern = new(
        @"\bSELECT\s+(?:OPTIONAL\s+)?(\w[\w-]*)\s+ASSIGN\s+(?:TO\s+)?(?:""([^""]+)""|'([^']+)'|(\w[\w-]*))",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly Regex OpenPattern = new(
        @"\bOPEN\s+(INPUT|OUTPUT|I-O|EXTEND)\s+([\w][\w-]*(?:[ \t]+[\w][\w-]*)*)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly Regex RagSourcePattern = new(
        @"\(source:\s*([A-Z0-9_]+)\.CBL", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly Regex CallExcludePrefix = new(
        @"^(IEF|DFS|DFH|CEE|CEEDAY|ILBO|IGZ|__|WIN32|WINAPI|COB32API|CBL_)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static readonly HashSet<string> CallExcludeSet = new(StringComparer.OrdinalIgnoreCase)
    {
        "IF","MOVE","ADD","SUBTRACT","MULTIPLY","DIVIDE","COMPUTE","PERFORM","EXIT",
        "EVALUATE","WHEN","OTHER","END","GO","TO","GOBACK","STOP","RUN",
        "ACCEPT","DISPL","DISPL1","DISPL2","INSPECT","EXEC","END-IF","ERROR",
        "STREAM","LINEOUT","PREP_SQL","CALL","DISPLAY","PIC","PAYD","OG","TIL",
        "INS","IS","---","AVSLUTT","SLUTT","SYSFILETREE","SYSLOADFUNCS","SYSSLEEP",
        "RXFUNCADD","START_REXX","DIALOG-SYSTEM","INVOKE-MESSAGE-BOX",
        "ENABLE-OBJECT","DISABLE-OBJECT","REFRESH-OBJECT",
        "REPLACING","COPY","USING","RETURNING","GIVING","ALSO","THRU","THROUGH",
        "VARYING","UNTIL","THE","FROM","UPON","VALUE","SIZE","LENGTH","STRING",
        "UNSTRING","INITIALIZE","RELEASE","RETURN","OPEN","CLOSE","READ","WRITE",
        "REWRITE","DELETE","START","SORT","MERGE","GENERATE","SECTION","PARAGRAPH",
        "CONTINUE",
        "INTO","VALUES","LEFT","RIGHT","INNER","OUTER","CROSS","ORDER","GROUP",
        "HAVING","DISTINCT","WHERE","SELECT","INSERT","UPDATE","DELETE","TABLE",
        "BETWEEN","LIKE","EXISTS","CASE","THEN","ELSE","UNION","EXCEPT",
        "INTERSECT","FETCH","FIRST","ONLY","ROWS","NEXT","PRIOR","CURSOR",
        "DECLARE","END-EXEC","COMMIT","ROLLBACK","CONNECT","DISCONNECT",
        "SET","NULL","NOT","AND","ALL","ANY","ASC","DESC",
        "DB2API","COBAPI","NETAPI","CBLJAPI","CBLAPI","CICS","CICSAPI"
    };

    public static readonly HashSet<string> SqlNotTables = new(StringComparer.OrdinalIgnoreCase)
    {
        "SQLCA","SQLDA","SECTION","SQL","EXEC","END","WHERE","SET","VALUES","INTO","AND",
        "OR","NOT","NULL","IS","AS","ON","BY","ORDER","GROUP","HAVING","DISTINCT",
        "ALL","ANY","BETWEEN","LIKE","IN","EXISTS","CASE","WHEN","THEN","ELSE",
        "BEGIN","COMMIT","ROLLBACK","DECLARE","CURSOR","OPEN","CLOSE","FETCH","NEXT",
        "FOR","READONLY","READ","ONLY","WITH","HOLD","LOCK","ROW","ROWS","FIRST","LAST",
        "CURRENT","OF","TIMESTAMP","DATE","TIME","INTEGER","SMALLINT","CHAR","VARCHAR",
        "DECIMAL","NUMERIC","FLOAT","DOUBLE","BLOB","CLOB","DBCLOB","GRAPHIC",
        "VARGRAPHIC","BIGINT","REAL","BINARY","VARBINARY","BOOLEAN","XML",
        "GLOBAL","TEMPORARY","SEQUENCE","INDEX","VIEW","PROCEDURE","FUNCTION","TRIGGER",
        "INNER","OUTER","LEFT","RIGHT","FULL","CROSS","NATURAL","UNION","EXCEPT","INTERSECT",
        "ASC","DESC","LIMIT","OFFSET","TOP","COUNT","SUM","AVG","MIN","MAX","COALESCE",
        "CAST","TRIM","UPPER","LOWER","SUBSTRING","LENGTH","REPLACE","POSITION",
        "EXTRACT","YEAR","MONTH","DAY","HOUR","MINUTE","SECOND","MICROSECOND",
        "ISOLATION","LEVEL","REPEATABLE","SERIALIZABLE","UNCOMMITTED","COMMITTED",
        "WORK","SAVEPOINT","RELEASE","TO","DATA","EXTERNAL","INPUT","OUTPUT"
    };

    public static readonly HashSet<string> SkipLogicalFiles = new(StringComparer.OrdinalIgnoreCase)
    {
        "PRINTER","PRINT-FILE","SYSOUT","SYSIN","CONSOLE","DISPLAY","KEYBOARD",
        "LINE-SEQUENTIAL","BINARY-SEQUENTIAL","RECORD-SEQUENTIAL",
        "ORGANIZATION","RECORDING","MODE","STATUS","FILE-STATUS",
        "LINAGE","FOOTING","TOP","BOTTOM","LINE-COUNTER","PAGE-COUNTER",
        "SORT-FILE","MERGE-FILE","REPORT-FILE","USE","GIVING","USING"
    };

    /*
     * VSAM-oriented SELECT: ORGANIZATION IS INDEXED => KSDS-style; RELATIVE => RRDS; SEQUENTIAL => ESDS-style.
     * Elements: SELECT name, ASSIGN, ORGANIZATION, ACCESS MODE, RECORD KEY, ALTERNATE RECORD KEY, FILE STATUS.
     */
    private static readonly Regex VsamSelectBlock = new(
        @"SELECT\s+([^\.]+?)\.",
        RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.Compiled);

    private static readonly Regex OrgIndexed = new(@"ORGANIZATION\s+IS\s+INDEXED", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex OrgRelative = new(@"ORGANIZATION\s+IS\s+RELATIVE", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex OrgSequential = new(@"ORGANIZATION\s+IS\s+SEQUENTIAL", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex AccessModeRx = new(@"ACCESS\s+MODE\s+IS\s+(\w+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex RecordKeyRx = new(@"RECORD\s+KEY\s+IS\s+([\w\-]+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex AltKeyRx = new(@"ALTERNATE\s+RECORD\s+KEY\s+IS\s+([\w\-]+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex FileStatusRx = new(@"FILE\s+STATUS\s+IS\s+([\w\-]+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex AssignDdRx = new(@"ASSIGN\s+TO\s+(?:\?|'([^']+)'|""([^""]+)""|(\w+))", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    /// <summary>Extract VSAM-like file definitions from FILE-CONTROL / SELECT clauses.</summary>
    public static List<JsonObject> ExtractVsamFiles(string sourceContent)
    {
        var list = new List<JsonObject>();
        if (string.IsNullOrWhiteSpace(sourceContent)) return list;

        foreach (Match m in VsamSelectBlock.Matches(sourceContent))
        {
            var block = m.Groups[1].Value;
            if (!OrgIndexed.IsMatch(block) && !OrgRelative.IsMatch(block) && !OrgSequential.IsMatch(block))
                continue;

            string org;
            if (OrgIndexed.IsMatch(block)) org = "KSDS";
            else if (OrgRelative.IsMatch(block)) org = "RRDS";
            else org = "ESDS";

            var selName = Regex.Match(block, @"^\s*(\w[\w\-]*)", RegexOptions.IgnoreCase);
            var logical = selName.Success ? selName.Groups[1].Value : "";

            var am = AccessModeRx.Match(block);
            var rk = RecordKeyRx.Match(block);
            var fs = FileStatusRx.Match(block);
            var dd = AssignDdRx.Match(block);
            var ddName = dd.Groups[1].Success ? dd.Groups[1].Value
                : dd.Groups[2].Success ? dd.Groups[2].Value
                : dd.Groups[3].Success ? dd.Groups[3].Value : "";

            var alts = new JsonArray();
            foreach (Match ak in AltKeyRx.Matches(block))
                alts.Add(ak.Groups[1].Value);

            var jo = new JsonObject
            {
                ["logicalName"] = logical,
                ["ddName"] = ddName,
                ["organization"] = org,
                ["accessMode"] = am.Success ? am.Groups[1].Value : "",
                ["recordKey"] = rk.Success ? rk.Groups[1].Value : "",
                ["alternateKeys"] = alts,
                ["fileStatus"] = fs.Success ? fs.Groups[1].Value : ""
            };
            list.Add(jo);
        }

        return list;
    }
}
