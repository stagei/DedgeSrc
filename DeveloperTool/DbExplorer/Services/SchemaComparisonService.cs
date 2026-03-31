using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
// Alias to avoid conflict with existing DifferenceType in DatabaseComparisonService
using DiffType = DbExplorer.Models.DifferenceType;

namespace DbExplorer.Services
{
    /// <summary>
    /// Service for comparing database schemas across different connections
    /// Compares all object types: tables, views, columns, indexes, constraints, 
    /// triggers, sequences, procedures, functions, packages
    /// </summary>
    public class SchemaComparisonService
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
        private readonly MetadataHandler _metadataHandler;

        public SchemaComparisonService()
        {
            _metadataHandler = new MetadataHandler();
        }

        /// <summary>
        /// Compare two schemas across different connections
        /// </summary>
        public async Task<SchemaComparisonResult> CompareSchemas(
            IConnectionManager sourceConnection,
            string sourceSchema,
            IConnectionManager targetConnection,
            string targetSchema,
            IProgress<string>? progress = null)
        {
            Logger.Info("Starting schema comparison: {Source}.{SourceSchema} vs {Target}.{TargetSchema}",
                sourceConnection.ConnectionInfo.Name, sourceSchema,
                targetConnection.ConnectionInfo.Name, targetSchema);

            var result = new SchemaComparisonResult
            {
                SourceSchema = sourceSchema,
                TargetSchema = targetSchema,
                SourceConnectionName = sourceConnection.ConnectionInfo.Name ?? "Source",
                TargetConnectionName = targetConnection.ConnectionInfo.Name ?? "Target",
                ComparisonTime = DateTime.Now
            };

            try
            {
                // Compare all object types in parallel where possible
                progress?.Report("Loading tables...");
                await CompareTablesAsync(sourceConnection, sourceSchema, targetConnection, targetSchema, result);

                progress?.Report("Loading views...");
                await CompareViewsAsync(sourceConnection, sourceSchema, targetConnection, targetSchema, result);

                progress?.Report("Loading columns...");
                await CompareColumnsAsync(sourceConnection, sourceSchema, targetConnection, targetSchema, result);

                progress?.Report("Loading indexes...");
                await CompareIndexesAsync(sourceConnection, sourceSchema, targetConnection, targetSchema, result);

                progress?.Report("Loading constraints...");
                await CompareConstraintsAsync(sourceConnection, sourceSchema, targetConnection, targetSchema, result);

                progress?.Report("Loading triggers...");
                await CompareTriggersAsync(sourceConnection, sourceSchema, targetConnection, targetSchema, result);

                progress?.Report("Loading sequences...");
                await CompareSequencesAsync(sourceConnection, sourceSchema, targetConnection, targetSchema, result);

                progress?.Report("Loading procedures and functions...");
                await CompareRoutinesAsync(sourceConnection, sourceSchema, targetConnection, targetSchema, result);

                // Calculate summary
                CalculateSummary(result);

                Logger.Info("Schema comparison completed: {Differences} differences found", 
                    result.Summary.TotalDifferences);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error during schema comparison");
                throw;
            }

            return result;
        }

        #region Table Comparison

        private async Task CompareTablesAsync(
            IConnectionManager source, string sourceSchema,
            IConnectionManager target, string targetSchema,
            SchemaComparisonResult result)
        {
            var sourceTables = await GetTablesAsync(source, sourceSchema);
            var targetTables = await GetTablesAsync(target, targetSchema);

            var differences = CompareObjects(sourceTables, targetTables, SchemaObjectType.Table);
            result.DifferencesByType[SchemaObjectType.Table] = differences;

            Logger.Debug("Tables: {Source} source, {Target} target, {Diff} differences",
                sourceTables.Count, targetTables.Count, differences.Count(d => d.DifferenceType != DiffType.Identical));
        }

        private async Task<List<SchemaObject>> GetTablesAsync(IConnectionManager connection, string schema)
        {
            var tables = new List<SchemaObject>();
            var provider = connection.ConnectionInfo.ProviderType?.ToUpperInvariant() ?? "DB2";
            var version = "12.1";

            var sql = $@"
                SELECT TRIM(TABNAME) AS TABNAME, TRIM(TYPE) AS TYPE, 
                       COLCOUNT, CARD, REMARKS,
                       TRIM(TBSPACE) AS TBSPACE, COMPRESSION, TABLEORG
                FROM SYSCAT.TABLES 
                WHERE TRIM(TABSCHEMA) = '{schema}' 
                AND TYPE IN ('T', 'S', 'G')
                ORDER BY TABNAME";

            try
            {
                var data = await connection.ExecuteQueryAsync(sql);
                foreach (DataRow row in data.Rows)
                {
                    var obj = new SchemaObject
                    {
                        Schema = schema,
                        Name = row["TABNAME"]?.ToString()?.Trim() ?? "",
                        ObjectType = SchemaObjectType.Table
                    };
                    obj.Properties["Type"] = row["TYPE"]?.ToString()?.Trim();
                    obj.Properties["ColumnCount"] = row["COLCOUNT"];
                    obj.Properties["RowCount"] = row["CARD"];
                    obj.Properties["Tablespace"] = row["TBSPACE"]?.ToString()?.Trim();
                    obj.Properties["Compression"] = row["COMPRESSION"]?.ToString()?.Trim();
                    obj.Properties["TableOrg"] = row["TABLEORG"]?.ToString()?.Trim();
                    obj.Properties["Remarks"] = row["REMARKS"]?.ToString()?.Trim();
                    tables.Add(obj);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting tables for schema {Schema}", schema);
            }

            return tables;
        }

        #endregion

        #region View Comparison

        private async Task CompareViewsAsync(
            IConnectionManager source, string sourceSchema,
            IConnectionManager target, string targetSchema,
            SchemaComparisonResult result)
        {
            var sourceViews = await GetViewsAsync(source, sourceSchema);
            var targetViews = await GetViewsAsync(target, targetSchema);

            var differences = CompareObjectsWithSource(sourceViews, targetViews, SchemaObjectType.View);
            result.DifferencesByType[SchemaObjectType.View] = differences;

            Logger.Debug("Views: {Source} source, {Target} target", sourceViews.Count, targetViews.Count);
        }

        private async Task<List<SchemaObject>> GetViewsAsync(IConnectionManager connection, string schema)
        {
            var views = new List<SchemaObject>();

            var sql = $@"
                SELECT TRIM(V.VIEWNAME) AS VIEWNAME, V.TEXT, V.READONLY, V.VALID,
                       T.REMARKS, T.COLCOUNT
                FROM SYSCAT.VIEWS V
                JOIN SYSCAT.TABLES T ON V.VIEWSCHEMA = T.TABSCHEMA AND V.VIEWNAME = T.TABNAME
                WHERE TRIM(V.VIEWSCHEMA) = '{schema}'
                ORDER BY V.VIEWNAME";

            try
            {
                var data = await connection.ExecuteQueryAsync(sql);
                foreach (DataRow row in data.Rows)
                {
                    var obj = new SchemaObject
                    {
                        Schema = schema,
                        Name = row["VIEWNAME"]?.ToString()?.Trim() ?? "",
                        ObjectType = SchemaObjectType.View,
                        SourceCode = row["TEXT"]?.ToString()
                    };
                    obj.Properties["ReadOnly"] = row["READONLY"]?.ToString()?.Trim();
                    obj.Properties["Valid"] = row["VALID"]?.ToString()?.Trim();
                    obj.Properties["ColumnCount"] = row["COLCOUNT"];
                    obj.Properties["Remarks"] = row["REMARKS"]?.ToString()?.Trim();
                    views.Add(obj);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting views for schema {Schema}", schema);
            }

            return views;
        }

        #endregion

        #region Column Comparison

        private async Task CompareColumnsAsync(
            IConnectionManager source, string sourceSchema,
            IConnectionManager target, string targetSchema,
            SchemaComparisonResult result)
        {
            var sourceColumns = await GetColumnsAsync(source, sourceSchema);
            var targetColumns = await GetColumnsAsync(target, targetSchema);

            var differences = CompareObjects(sourceColumns, targetColumns, SchemaObjectType.Column);
            result.DifferencesByType[SchemaObjectType.Column] = differences;

            Logger.Debug("Columns: {Source} source, {Target} target", sourceColumns.Count, targetColumns.Count);
        }

        private async Task<List<SchemaObject>> GetColumnsAsync(IConnectionManager connection, string schema)
        {
            var columns = new List<SchemaObject>();

            var sql = $@"
                SELECT TRIM(TABNAME) AS TABNAME, TRIM(COLNAME) AS COLNAME, 
                       COLNO, TRIM(TYPENAME) AS TYPENAME, LENGTH, SCALE, 
                       NULLS, TRIM(DEFAULT) AS DEFAULT_VAL, IDENTITY, GENERATED,
                       REMARKS
                FROM SYSCAT.COLUMNS 
                WHERE TRIM(TABSCHEMA) = '{schema}'
                ORDER BY TABNAME, COLNO";

            try
            {
                var data = await connection.ExecuteQueryAsync(sql);
                foreach (DataRow row in data.Rows)
                {
                    var tableName = row["TABNAME"]?.ToString()?.Trim() ?? "";
                    var obj = new SchemaObject
                    {
                        Schema = schema,
                        Name = row["COLNAME"]?.ToString()?.Trim() ?? "",
                        ParentName = tableName,
                        ObjectType = SchemaObjectType.Column
                    };
                    obj.Properties["Position"] = row["COLNO"];
                    obj.Properties["DataType"] = row["TYPENAME"]?.ToString()?.Trim();
                    obj.Properties["Length"] = row["LENGTH"];
                    obj.Properties["Scale"] = row["SCALE"];
                    obj.Properties["Nullable"] = row["NULLS"]?.ToString()?.Trim();
                    obj.Properties["Default"] = row["DEFAULT_VAL"]?.ToString()?.Trim();
                    obj.Properties["Identity"] = row["IDENTITY"]?.ToString()?.Trim();
                    obj.Properties["Generated"] = row["GENERATED"]?.ToString()?.Trim();
                    obj.Properties["Remarks"] = row["REMARKS"]?.ToString()?.Trim();
                    columns.Add(obj);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting columns for schema {Schema}", schema);
            }

            return columns;
        }

        #endregion

        #region Index Comparison

        private async Task CompareIndexesAsync(
            IConnectionManager source, string sourceSchema,
            IConnectionManager target, string targetSchema,
            SchemaComparisonResult result)
        {
            var sourceIndexes = await GetIndexesAsync(source, sourceSchema);
            var targetIndexes = await GetIndexesAsync(target, targetSchema);

            var differences = CompareObjects(sourceIndexes, targetIndexes, SchemaObjectType.Index);
            result.DifferencesByType[SchemaObjectType.Index] = differences;

            Logger.Debug("Indexes: {Source} source, {Target} target", sourceIndexes.Count, targetIndexes.Count);
        }

        private async Task<List<SchemaObject>> GetIndexesAsync(IConnectionManager connection, string schema)
        {
            var indexes = new List<SchemaObject>();

            var sql = $@"
                SELECT TRIM(INDNAME) AS INDNAME, TRIM(TABNAME) AS TABNAME,
                       TRIM(COLNAMES) AS COLNAMES, UNIQUERULE, INDEXTYPE,
                       COLCOUNT, PCTFREE, COMPRESSION, REMARKS
                FROM SYSCAT.INDEXES 
                WHERE TRIM(INDSCHEMA) = '{schema}'
                  AND UNIQUERULE <> 'P'  -- Exclude primary key indexes (handled separately)
                ORDER BY TABNAME, INDNAME";

            try
            {
                var data = await connection.ExecuteQueryAsync(sql);
                foreach (DataRow row in data.Rows)
                {
                    var obj = new SchemaObject
                    {
                        Schema = schema,
                        Name = row["INDNAME"]?.ToString()?.Trim() ?? "",
                        ParentName = row["TABNAME"]?.ToString()?.Trim(),
                        ObjectType = SchemaObjectType.Index
                    };
                    obj.Properties["Columns"] = row["COLNAMES"]?.ToString()?.Trim();
                    obj.Properties["UniqueRule"] = row["UNIQUERULE"]?.ToString()?.Trim();
                    obj.Properties["IndexType"] = row["INDEXTYPE"]?.ToString()?.Trim();
                    obj.Properties["ColumnCount"] = row["COLCOUNT"];
                    obj.Properties["PctFree"] = row["PCTFREE"];
                    obj.Properties["Compression"] = row["COMPRESSION"]?.ToString()?.Trim();
                    obj.Properties["Remarks"] = row["REMARKS"]?.ToString()?.Trim();
                    indexes.Add(obj);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting indexes for schema {Schema}", schema);
            }

            return indexes;
        }

        #endregion

        #region Constraint Comparison

        private async Task CompareConstraintsAsync(
            IConnectionManager source, string sourceSchema,
            IConnectionManager target, string targetSchema,
            SchemaComparisonResult result)
        {
            // Primary Keys
            var sourcePKs = await GetPrimaryKeysAsync(source, sourceSchema);
            var targetPKs = await GetPrimaryKeysAsync(target, targetSchema);
            result.DifferencesByType[SchemaObjectType.PrimaryKey] = CompareObjects(sourcePKs, targetPKs, SchemaObjectType.PrimaryKey);

            // Foreign Keys
            var sourceFKs = await GetForeignKeysAsync(source, sourceSchema);
            var targetFKs = await GetForeignKeysAsync(target, targetSchema);
            result.DifferencesByType[SchemaObjectType.ForeignKey] = CompareObjects(sourceFKs, targetFKs, SchemaObjectType.ForeignKey);

            // Check Constraints
            var sourceChecks = await GetCheckConstraintsAsync(source, sourceSchema);
            var targetChecks = await GetCheckConstraintsAsync(target, targetSchema);
            result.DifferencesByType[SchemaObjectType.CheckConstraint] = CompareObjects(sourceChecks, targetChecks, SchemaObjectType.CheckConstraint);

            // Unique Constraints
            var sourceUniques = await GetUniqueConstraintsAsync(source, sourceSchema);
            var targetUniques = await GetUniqueConstraintsAsync(target, targetSchema);
            result.DifferencesByType[SchemaObjectType.UniqueConstraint] = CompareObjects(sourceUniques, targetUniques, SchemaObjectType.UniqueConstraint);

            Logger.Debug("Constraints: PK={PK}, FK={FK}, Check={Check}, Unique={Unique}",
                sourcePKs.Count, sourceFKs.Count, sourceChecks.Count, sourceUniques.Count);
        }

        private async Task<List<SchemaObject>> GetPrimaryKeysAsync(IConnectionManager connection, string schema)
        {
            var pks = new List<SchemaObject>();

            var sql = $@"
                SELECT TRIM(C.CONSTNAME) AS CONSTNAME, TRIM(C.TABNAME) AS TABNAME,
                       (SELECT LISTAGG(TRIM(K.COLNAME), ', ') WITHIN GROUP (ORDER BY K.COLSEQ)
                        FROM SYSCAT.KEYCOLUSE K 
                        WHERE K.CONSTNAME = C.CONSTNAME AND K.TABSCHEMA = C.TABSCHEMA AND K.TABNAME = C.TABNAME) AS COLUMNS
                FROM SYSCAT.TABCONST C
                WHERE TRIM(C.TABSCHEMA) = '{schema}' AND C.TYPE = 'P'
                ORDER BY C.TABNAME";

            try
            {
                var data = await connection.ExecuteQueryAsync(sql);
                foreach (DataRow row in data.Rows)
                {
                    var obj = new SchemaObject
                    {
                        Schema = schema,
                        Name = row["CONSTNAME"]?.ToString()?.Trim() ?? "",
                        ParentName = row["TABNAME"]?.ToString()?.Trim(),
                        ObjectType = SchemaObjectType.PrimaryKey
                    };
                    obj.Properties["Columns"] = row["COLUMNS"]?.ToString()?.Trim();
                    pks.Add(obj);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting primary keys for schema {Schema}", schema);
            }

            return pks;
        }

        private async Task<List<SchemaObject>> GetForeignKeysAsync(IConnectionManager connection, string schema)
        {
            var fks = new List<SchemaObject>();

            var sql = $@"
                SELECT TRIM(R.CONSTNAME) AS CONSTNAME, TRIM(R.TABNAME) AS TABNAME,
                       TRIM(R.REFTABSCHEMA) AS REFTABSCHEMA, TRIM(R.REFTABNAME) AS REFTABNAME,
                       TRIM(R.FK_COLNAMES) AS FK_COLUMNS, TRIM(R.PK_COLNAMES) AS PK_COLUMNS,
                       R.DELETERULE, R.UPDATERULE
                FROM SYSCAT.REFERENCES R
                WHERE TRIM(R.TABSCHEMA) = '{schema}'
                ORDER BY R.TABNAME, R.CONSTNAME";

            try
            {
                var data = await connection.ExecuteQueryAsync(sql);
                foreach (DataRow row in data.Rows)
                {
                    var obj = new SchemaObject
                    {
                        Schema = schema,
                        Name = row["CONSTNAME"]?.ToString()?.Trim() ?? "",
                        ParentName = row["TABNAME"]?.ToString()?.Trim(),
                        ObjectType = SchemaObjectType.ForeignKey
                    };
                    obj.Properties["ReferencedSchema"] = row["REFTABSCHEMA"]?.ToString()?.Trim();
                    obj.Properties["ReferencedTable"] = row["REFTABNAME"]?.ToString()?.Trim();
                    obj.Properties["FKColumns"] = row["FK_COLUMNS"]?.ToString()?.Trim();
                    obj.Properties["PKColumns"] = row["PK_COLUMNS"]?.ToString()?.Trim();
                    obj.Properties["DeleteRule"] = row["DELETERULE"]?.ToString()?.Trim();
                    obj.Properties["UpdateRule"] = row["UPDATERULE"]?.ToString()?.Trim();
                    fks.Add(obj);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting foreign keys for schema {Schema}", schema);
            }

            return fks;
        }

        private async Task<List<SchemaObject>> GetCheckConstraintsAsync(IConnectionManager connection, string schema)
        {
            var checks = new List<SchemaObject>();

            var sql = $@"
                SELECT TRIM(CONSTNAME) AS CONSTNAME, TRIM(TABNAME) AS TABNAME, TEXT
                FROM SYSCAT.CHECKS 
                WHERE TRIM(TABSCHEMA) = '{schema}'
                ORDER BY TABNAME, CONSTNAME";

            try
            {
                var data = await connection.ExecuteQueryAsync(sql);
                foreach (DataRow row in data.Rows)
                {
                    var obj = new SchemaObject
                    {
                        Schema = schema,
                        Name = row["CONSTNAME"]?.ToString()?.Trim() ?? "",
                        ParentName = row["TABNAME"]?.ToString()?.Trim(),
                        ObjectType = SchemaObjectType.CheckConstraint,
                        SourceCode = row["TEXT"]?.ToString()
                    };
                    checks.Add(obj);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting check constraints for schema {Schema}", schema);
            }

            return checks;
        }

        private async Task<List<SchemaObject>> GetUniqueConstraintsAsync(IConnectionManager connection, string schema)
        {
            var uniques = new List<SchemaObject>();

            var sql = $@"
                SELECT TRIM(C.CONSTNAME) AS CONSTNAME, TRIM(C.TABNAME) AS TABNAME,
                       (SELECT LISTAGG(TRIM(K.COLNAME), ', ') WITHIN GROUP (ORDER BY K.COLSEQ)
                        FROM SYSCAT.KEYCOLUSE K 
                        WHERE K.CONSTNAME = C.CONSTNAME AND K.TABSCHEMA = C.TABSCHEMA AND K.TABNAME = C.TABNAME) AS COLUMNS
                FROM SYSCAT.TABCONST C
                WHERE TRIM(C.TABSCHEMA) = '{schema}' AND C.TYPE = 'U'
                ORDER BY C.TABNAME";

            try
            {
                var data = await connection.ExecuteQueryAsync(sql);
                foreach (DataRow row in data.Rows)
                {
                    var obj = new SchemaObject
                    {
                        Schema = schema,
                        Name = row["CONSTNAME"]?.ToString()?.Trim() ?? "",
                        ParentName = row["TABNAME"]?.ToString()?.Trim(),
                        ObjectType = SchemaObjectType.UniqueConstraint
                    };
                    obj.Properties["Columns"] = row["COLUMNS"]?.ToString()?.Trim();
                    uniques.Add(obj);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting unique constraints for schema {Schema}", schema);
            }

            return uniques;
        }

        #endregion

        #region Trigger Comparison

        private async Task CompareTriggersAsync(
            IConnectionManager source, string sourceSchema,
            IConnectionManager target, string targetSchema,
            SchemaComparisonResult result)
        {
            var sourceTriggers = await GetTriggersAsync(source, sourceSchema);
            var targetTriggers = await GetTriggersAsync(target, targetSchema);

            var differences = CompareObjectsWithSource(sourceTriggers, targetTriggers, SchemaObjectType.Trigger);
            result.DifferencesByType[SchemaObjectType.Trigger] = differences;

            Logger.Debug("Triggers: {Source} source, {Target} target", sourceTriggers.Count, targetTriggers.Count);
        }

        private async Task<List<SchemaObject>> GetTriggersAsync(IConnectionManager connection, string schema)
        {
            var triggers = new List<SchemaObject>();

            var sql = $@"
                SELECT TRIM(TRIGNAME) AS TRIGNAME, TRIM(TABNAME) AS TABNAME,
                       TRIGTIME, TRIGEVENT, GRANULARITY, VALID, TEXT, REMARKS
                FROM SYSCAT.TRIGGERS 
                WHERE TRIM(TRIGSCHEMA) = '{schema}'
                ORDER BY TABNAME, TRIGNAME";

            try
            {
                var data = await connection.ExecuteQueryAsync(sql);
                foreach (DataRow row in data.Rows)
                {
                    var obj = new SchemaObject
                    {
                        Schema = schema,
                        Name = row["TRIGNAME"]?.ToString()?.Trim() ?? "",
                        ParentName = row["TABNAME"]?.ToString()?.Trim(),
                        ObjectType = SchemaObjectType.Trigger,
                        SourceCode = row["TEXT"]?.ToString()
                    };
                    obj.Properties["TrigTime"] = row["TRIGTIME"]?.ToString()?.Trim();
                    obj.Properties["TrigEvent"] = row["TRIGEVENT"]?.ToString()?.Trim();
                    obj.Properties["Granularity"] = row["GRANULARITY"]?.ToString()?.Trim();
                    obj.Properties["Valid"] = row["VALID"]?.ToString()?.Trim();
                    obj.Properties["Remarks"] = row["REMARKS"]?.ToString()?.Trim();
                    triggers.Add(obj);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting triggers for schema {Schema}", schema);
            }

            return triggers;
        }

        #endregion

        #region Sequence Comparison

        private async Task CompareSequencesAsync(
            IConnectionManager source, string sourceSchema,
            IConnectionManager target, string targetSchema,
            SchemaComparisonResult result)
        {
            var sourceSeqs = await GetSequencesAsync(source, sourceSchema);
            var targetSeqs = await GetSequencesAsync(target, targetSchema);

            var differences = CompareObjects(sourceSeqs, targetSeqs, SchemaObjectType.Sequence);
            result.DifferencesByType[SchemaObjectType.Sequence] = differences;

            Logger.Debug("Sequences: {Source} source, {Target} target", sourceSeqs.Count, targetSeqs.Count);
        }

        private async Task<List<SchemaObject>> GetSequencesAsync(IConnectionManager connection, string schema)
        {
            var sequences = new List<SchemaObject>();

            var sql = $@"
                SELECT TRIM(SEQNAME) AS SEQNAME, SEQTYPE, INCREMENT, START,
                       MAXVALUE, MINVALUE, CYCLE, CACHE, REMARKS
                FROM SYSCAT.SEQUENCES 
                WHERE TRIM(SEQSCHEMA) = '{schema}' AND SEQTYPE = 'S'
                ORDER BY SEQNAME";

            try
            {
                var data = await connection.ExecuteQueryAsync(sql);
                foreach (DataRow row in data.Rows)
                {
                    var obj = new SchemaObject
                    {
                        Schema = schema,
                        Name = row["SEQNAME"]?.ToString()?.Trim() ?? "",
                        ObjectType = SchemaObjectType.Sequence
                    };
                    obj.Properties["Increment"] = row["INCREMENT"];
                    obj.Properties["Start"] = row["START"];
                    obj.Properties["MaxValue"] = row["MAXVALUE"];
                    obj.Properties["MinValue"] = row["MINVALUE"];
                    obj.Properties["Cycle"] = row["CYCLE"]?.ToString()?.Trim();
                    obj.Properties["Cache"] = row["CACHE"];
                    obj.Properties["Remarks"] = row["REMARKS"]?.ToString()?.Trim();
                    sequences.Add(obj);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting sequences for schema {Schema}", schema);
            }

            return sequences;
        }

        #endregion

        #region Routine Comparison (Procedures and Functions)

        private async Task CompareRoutinesAsync(
            IConnectionManager source, string sourceSchema,
            IConnectionManager target, string targetSchema,
            SchemaComparisonResult result)
        {
            // Procedures
            var sourceProcs = await GetRoutinesAsync(source, sourceSchema, "P");
            var targetProcs = await GetRoutinesAsync(target, targetSchema, "P");
            result.DifferencesByType[SchemaObjectType.Procedure] = CompareObjectsWithSource(sourceProcs, targetProcs, SchemaObjectType.Procedure);

            // Functions
            var sourceFuncs = await GetRoutinesAsync(source, sourceSchema, "F");
            var targetFuncs = await GetRoutinesAsync(target, targetSchema, "F");
            result.DifferencesByType[SchemaObjectType.Function] = CompareObjectsWithSource(sourceFuncs, targetFuncs, SchemaObjectType.Function);

            Logger.Debug("Routines: {Procs} procedures, {Funcs} functions", sourceProcs.Count, sourceFuncs.Count);
        }

        private async Task<List<SchemaObject>> GetRoutinesAsync(IConnectionManager connection, string schema, string routineType)
        {
            var routines = new List<SchemaObject>();
            var objectType = routineType == "P" ? SchemaObjectType.Procedure : SchemaObjectType.Function;

            var sql = $@"
                SELECT TRIM(ROUTINENAME) AS ROUTINENAME, TRIM(SPECIFICNAME) AS SPECIFICNAME,
                       LANGUAGE, PARM_COUNT, DETERMINISTIC, EXTERNAL_ACTION, 
                       SQL_DATA_ACCESS, VALID, TEXT, REMARKS
                FROM SYSCAT.ROUTINES 
                WHERE TRIM(ROUTINESCHEMA) = '{schema}' AND ROUTINETYPE = '{routineType}'
                  AND ORIGIN IN ('S', 'U')  -- SQL or User-defined
                ORDER BY ROUTINENAME";

            try
            {
                var data = await connection.ExecuteQueryAsync(sql);
                foreach (DataRow row in data.Rows)
                {
                    var obj = new SchemaObject
                    {
                        Schema = schema,
                        Name = row["ROUTINENAME"]?.ToString()?.Trim() ?? "",
                        ObjectType = objectType,
                        SourceCode = row["TEXT"]?.ToString()
                    };
                    obj.Properties["SpecificName"] = row["SPECIFICNAME"]?.ToString()?.Trim();
                    obj.Properties["Language"] = row["LANGUAGE"]?.ToString()?.Trim();
                    obj.Properties["ParamCount"] = row["PARM_COUNT"];
                    obj.Properties["Deterministic"] = row["DETERMINISTIC"]?.ToString()?.Trim();
                    obj.Properties["ExternalAction"] = row["EXTERNAL_ACTION"]?.ToString()?.Trim();
                    obj.Properties["SqlDataAccess"] = row["SQL_DATA_ACCESS"]?.ToString()?.Trim();
                    obj.Properties["Valid"] = row["VALID"]?.ToString()?.Trim();
                    obj.Properties["Remarks"] = row["REMARKS"]?.ToString()?.Trim();
                    routines.Add(obj);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Error getting routines for schema {Schema}", schema);
            }

            return routines;
        }

        #endregion

        #region Comparison Logic

        private List<SchemaDifference> CompareObjects(
            List<SchemaObject> sourceObjects,
            List<SchemaObject> targetObjects,
            SchemaObjectType objectType)
        {
            var differences = new List<SchemaDifference>();

            // Create lookup dictionaries by name (case-insensitive)
            var sourceByName = sourceObjects.ToDictionary(
                o => o.FullName, 
                o => o, 
                StringComparer.OrdinalIgnoreCase);
            var targetByName = targetObjects.ToDictionary(
                o => o.FullName, 
                o => o, 
                StringComparer.OrdinalIgnoreCase);

            // Find objects only in source
            foreach (var source in sourceObjects)
            {
                if (!targetByName.ContainsKey(source.FullName))
                {
                    differences.Add(new SchemaDifference
                    {
                        ObjectType = objectType,
                        DifferenceType = DiffType.OnlyInSource,
                        SourceObject = source
                    });
                }
            }

            // Find objects only in target
            foreach (var target in targetObjects)
            {
                if (!sourceByName.ContainsKey(target.FullName))
                {
                    differences.Add(new SchemaDifference
                    {
                        ObjectType = objectType,
                        DifferenceType = DiffType.OnlyInTarget,
                        TargetObject = target
                    });
                }
            }

            // Compare objects that exist in both
            foreach (var source in sourceObjects)
            {
                if (targetByName.TryGetValue(source.FullName, out var target))
                {
                    var propDiffs = CompareProperties(source.Properties, target.Properties);
                    
                    if (propDiffs.Count > 0)
                    {
                        differences.Add(new SchemaDifference
                        {
                            ObjectType = objectType,
                            DifferenceType = DiffType.Modified,
                            SourceObject = source,
                            TargetObject = target,
                            PropertyDifferences = propDiffs
                        });
                    }
                    else
                    {
                        differences.Add(new SchemaDifference
                        {
                            ObjectType = objectType,
                            DifferenceType = DiffType.Identical,
                            SourceObject = source,
                            TargetObject = target
                        });
                    }
                }
            }

            return differences;
        }

        private List<SchemaDifference> CompareObjectsWithSource(
            List<SchemaObject> sourceObjects,
            List<SchemaObject> targetObjects,
            SchemaObjectType objectType)
        {
            var differences = new List<SchemaDifference>();

            var sourceByName = sourceObjects.ToDictionary(
                o => o.FullName, 
                o => o, 
                StringComparer.OrdinalIgnoreCase);
            var targetByName = targetObjects.ToDictionary(
                o => o.FullName, 
                o => o, 
                StringComparer.OrdinalIgnoreCase);

            // Find objects only in source
            foreach (var source in sourceObjects)
            {
                if (!targetByName.ContainsKey(source.FullName))
                {
                    differences.Add(new SchemaDifference
                    {
                        ObjectType = objectType,
                        DifferenceType = DiffType.OnlyInSource,
                        SourceObject = source
                    });
                }
            }

            // Find objects only in target
            foreach (var target in targetObjects)
            {
                if (!sourceByName.ContainsKey(target.FullName))
                {
                    differences.Add(new SchemaDifference
                    {
                        ObjectType = objectType,
                        DifferenceType = DiffType.OnlyInTarget,
                        TargetObject = target
                    });
                }
            }

            // Compare objects that exist in both - including source code comparison
            foreach (var source in sourceObjects)
            {
                if (targetByName.TryGetValue(source.FullName, out var target))
                {
                    var propDiffs = CompareProperties(source.Properties, target.Properties);
                    var lineDiffs = CompareSourceCode(source.SourceCode, target.SourceCode);
                    
                    if (propDiffs.Count > 0 || lineDiffs.Count > 0)
                    {
                        differences.Add(new SchemaDifference
                        {
                            ObjectType = objectType,
                            DifferenceType = DiffType.Modified,
                            SourceObject = source,
                            TargetObject = target,
                            PropertyDifferences = propDiffs,
                            LineDifferences = lineDiffs
                        });
                    }
                    else
                    {
                        differences.Add(new SchemaDifference
                        {
                            ObjectType = objectType,
                            DifferenceType = DiffType.Identical,
                            SourceObject = source,
                            TargetObject = target
                        });
                    }
                }
            }

            return differences;
        }

        private List<PropertyDifference> CompareProperties(
            Dictionary<string, object?> sourceProps,
            Dictionary<string, object?> targetProps)
        {
            var differences = new List<PropertyDifference>();

            // Skip these properties when comparing
            var skipProperties = new HashSet<string>(StringComparer.OrdinalIgnoreCase) 
            { 
                "Remarks", "RowCount", "Position" // Position may differ, remarks are not structural
            };

            var allKeys = sourceProps.Keys.Union(targetProps.Keys).Distinct();

            foreach (var key in allKeys)
            {
                if (skipProperties.Contains(key))
                    continue;

                sourceProps.TryGetValue(key, out var sourceVal);
                targetProps.TryGetValue(key, out var targetVal);

                var sourceStr = sourceVal?.ToString()?.Trim() ?? "";
                var targetStr = targetVal?.ToString()?.Trim() ?? "";

                if (!sourceStr.Equals(targetStr, StringComparison.OrdinalIgnoreCase))
                {
                    differences.Add(new PropertyDifference
                    {
                        PropertyName = key,
                        SourceValue = string.IsNullOrEmpty(sourceStr) ? null : sourceStr,
                        TargetValue = string.IsNullOrEmpty(targetStr) ? null : targetStr
                    });
                }
            }

            return differences;
        }

        private List<LineDifference> CompareSourceCode(string? sourceCode, string? targetCode)
        {
            var differences = new List<LineDifference>();

            if (string.IsNullOrWhiteSpace(sourceCode) && string.IsNullOrWhiteSpace(targetCode))
                return differences;

            var sourceLines = (sourceCode ?? "").Split('\n').Select(l => l.TrimEnd('\r')).ToArray();
            var targetLines = (targetCode ?? "").Split('\n').Select(l => l.TrimEnd('\r')).ToArray();

            // Simple line-by-line diff (LCS-based diff could be added for better results)
            var maxLines = Math.Max(sourceLines.Length, targetLines.Length);

            for (int i = 0; i < maxLines; i++)
            {
                var sourceLine = i < sourceLines.Length ? sourceLines[i] : null;
                var targetLine = i < targetLines.Length ? targetLines[i] : null;

                if (sourceLine == null && targetLine != null)
                {
                    differences.Add(new LineDifference
                    {
                        LineNumber = i + 1,
                        Type = LineDifferenceType.Added,
                        TargetLine = targetLine
                    });
                }
                else if (sourceLine != null && targetLine == null)
                {
                    differences.Add(new LineDifference
                    {
                        LineNumber = i + 1,
                        Type = LineDifferenceType.Removed,
                        SourceLine = sourceLine
                    });
                }
                else if (sourceLine != targetLine)
                {
                    differences.Add(new LineDifference
                    {
                        LineNumber = i + 1,
                        Type = LineDifferenceType.Modified,
                        SourceLine = sourceLine,
                        TargetLine = targetLine
                    });
                }
            }

            return differences;
        }

        #endregion

        #region Summary Calculation

        private void CalculateSummary(SchemaComparisonResult result)
        {
            var summary = new ComparisonSummary();

            foreach (var kvp in result.DifferencesByType)
            {
                var objectType = kvp.Key;
                var differences = kvp.Value;

                var typeSummary = new ObjectTypeSummary
                {
                    ObjectType = objectType,
                    OnlyInSource = differences.Count(d => d.DifferenceType == DiffType.OnlyInSource),
                    OnlyInTarget = differences.Count(d => d.DifferenceType == DiffType.OnlyInTarget),
                    Modified = differences.Count(d => d.DifferenceType == DiffType.Modified),
                    Identical = differences.Count(d => d.DifferenceType == DiffType.Identical)
                };
                typeSummary.SourceCount = typeSummary.OnlyInSource + typeSummary.Modified + typeSummary.Identical;
                typeSummary.TargetCount = typeSummary.OnlyInTarget + typeSummary.Modified + typeSummary.Identical;

                summary.ByObjectType[objectType] = typeSummary;

                summary.TotalObjectsInSource += typeSummary.SourceCount;
                summary.TotalObjectsInTarget += typeSummary.TargetCount;
                summary.OnlyInSourceCount += typeSummary.OnlyInSource;
                summary.OnlyInTargetCount += typeSummary.OnlyInTarget;
                summary.ModifiedCount += typeSummary.Modified;
                summary.IdenticalCount += typeSummary.Identical;
            }

            result.Summary = summary;
        }

        #endregion
    }
}
