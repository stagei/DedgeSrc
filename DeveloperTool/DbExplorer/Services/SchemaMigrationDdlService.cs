using System;
using System.Collections.Generic;
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
    /// Service for generating DDL scripts from schema comparison differences
    /// </summary>
    public class SchemaMigrationDdlService
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

        /// <summary>
        /// Generate migration scripts from selected differences
        /// </summary>
        public List<MigrationScript> GenerateMigrationScripts(
            SchemaComparisonResult comparisonResult,
            IEnumerable<SchemaDifference> selectedDifferences)
        {
            var scripts = new List<MigrationScript>();

            // Group by direction and target
            var toTarget = selectedDifferences
                .Where(d => d.MergeDirection == MergeDirection.SourceToTarget || d.MergeDirection == MergeDirection.Both)
                .ToList();

            var toSource = selectedDifferences
                .Where(d => d.MergeDirection == MergeDirection.TargetToSource || d.MergeDirection == MergeDirection.Both)
                .ToList();

            if (toTarget.Count > 0)
            {
                var script = new MigrationScript
                {
                    ConnectionName = comparisonResult.TargetConnectionName,
                    TargetSchema = comparisonResult.TargetSchema,
                    Direction = MergeDirection.SourceToTarget,
                    SourceDifferences = toTarget
                };

                foreach (var diff in OrderDifferencesForDdl(toTarget, true))
                {
                    var ddl = GenerateDdlForDifference(diff, comparisonResult.SourceSchema, comparisonResult.TargetSchema, true);
                    if (!string.IsNullOrEmpty(ddl))
                    {
                        script.DdlStatements.Add(ddl);
                    }
                }

                scripts.Add(script);
            }

            if (toSource.Count > 0)
            {
                var script = new MigrationScript
                {
                    ConnectionName = comparisonResult.SourceConnectionName,
                    TargetSchema = comparisonResult.SourceSchema,
                    Direction = MergeDirection.TargetToSource,
                    SourceDifferences = toSource
                };

                foreach (var diff in OrderDifferencesForDdl(toSource, false))
                {
                    var ddl = GenerateDdlForDifference(diff, comparisonResult.TargetSchema, comparisonResult.SourceSchema, false);
                    if (!string.IsNullOrEmpty(ddl))
                    {
                        script.DdlStatements.Add(ddl);
                    }
                }

                scripts.Add(script);
            }

            return scripts;
        }

        /// <summary>
        /// Order differences for DDL execution (respecting dependencies)
        /// </summary>
        private IEnumerable<SchemaDifference> OrderDifferencesForDdl(
            List<SchemaDifference> differences, 
            bool sourceToTarget)
        {
            // Order: 1. Sequences, 2. Tables, 3. Columns, 4. Indexes, 5. Constraints, 6. Views, 7. Routines, 8. Triggers
            var typeOrder = new[]
            {
                SchemaObjectType.Sequence,
                SchemaObjectType.Table,
                SchemaObjectType.Column,
                SchemaObjectType.Index,
                SchemaObjectType.PrimaryKey,
                SchemaObjectType.UniqueConstraint,
                SchemaObjectType.ForeignKey,
                SchemaObjectType.CheckConstraint,
                SchemaObjectType.View,
                SchemaObjectType.Function,
                SchemaObjectType.Procedure,
                SchemaObjectType.Trigger
            };

            return differences.OrderBy(d => Array.IndexOf(typeOrder, d.ObjectType))
                             .ThenBy(d => d.DisplayName);
        }

        /// <summary>
        /// Generate DDL for a single difference
        /// </summary>
        private string GenerateDdlForDifference(
            SchemaDifference diff, 
            string fromSchema, 
            string toSchema,
            bool sourceToTarget)
        {
            var sb = new StringBuilder();
            var sourceObj = sourceToTarget ? diff.SourceObject : diff.TargetObject;
            var targetObj = sourceToTarget ? diff.TargetObject : diff.SourceObject;

            // Add comment
            sb.AppendLine($"-- {diff.ObjectType}: {diff.DisplayName}");
            sb.AppendLine($"-- Difference: {diff.DifferenceType}");

            switch (diff.DifferenceType)
            {
                case DiffType.OnlyInSource when sourceToTarget:
                case DiffType.OnlyInTarget when !sourceToTarget:
                    // Create in target
                    sb.Append(GenerateCreateDdl(sourceObj!, toSchema));
                    break;

                case DiffType.OnlyInTarget when sourceToTarget:
                case DiffType.OnlyInSource when !sourceToTarget:
                    // Object exists only in target - may need to drop or skip
                    sb.AppendLine($"-- Object exists only in target, consider DROP if needed:");
                    sb.Append(GenerateDropDdl(targetObj!, toSchema));
                    break;

                case DiffType.Modified:
                    // Generate ALTER or DROP/CREATE
                    sb.Append(GenerateModifyDdl(diff, sourceObj!, targetObj!, toSchema));
                    break;

                default:
                    return string.Empty;
            }

            return sb.ToString();
        }

        #region DDL Generation

        private string GenerateCreateDdl(SchemaObject obj, string targetSchema)
        {
            return obj.ObjectType switch
            {
                SchemaObjectType.Table => GenerateCreateTableDdl(obj, targetSchema),
                SchemaObjectType.View => GenerateCreateViewDdl(obj, targetSchema),
                SchemaObjectType.Column => GenerateAddColumnDdl(obj, targetSchema),
                SchemaObjectType.Index => GenerateCreateIndexDdl(obj, targetSchema),
                SchemaObjectType.PrimaryKey => GenerateAddPrimaryKeyDdl(obj, targetSchema),
                SchemaObjectType.UniqueConstraint => GenerateAddUniqueConstraintDdl(obj, targetSchema),
                SchemaObjectType.ForeignKey => GenerateAddForeignKeyDdl(obj, targetSchema),
                SchemaObjectType.CheckConstraint => GenerateAddCheckConstraintDdl(obj, targetSchema),
                SchemaObjectType.Trigger => GenerateCreateTriggerDdl(obj, targetSchema),
                SchemaObjectType.Sequence => GenerateCreateSequenceDdl(obj, targetSchema),
                SchemaObjectType.Procedure => GenerateCreateProcedureDdl(obj, targetSchema),
                SchemaObjectType.Function => GenerateCreateFunctionDdl(obj, targetSchema),
                _ => $"-- TODO: Implement CREATE for {obj.ObjectType}\n"
            };
        }

        private string GenerateDropDdl(SchemaObject obj, string targetSchema)
        {
            var qualifiedName = $"{targetSchema}.{obj.Name}";
            var parentQualified = obj.ParentName != null ? $"{targetSchema}.{obj.ParentName}" : null;

            return obj.ObjectType switch
            {
                SchemaObjectType.Table => $"-- DROP TABLE {qualifiedName};\n",
                SchemaObjectType.View => $"DROP VIEW {qualifiedName};\n",
                SchemaObjectType.Column => $"ALTER TABLE {parentQualified} DROP COLUMN {obj.Name};\n",
                SchemaObjectType.Index => $"DROP INDEX {qualifiedName};\n",
                SchemaObjectType.PrimaryKey => $"ALTER TABLE {parentQualified} DROP PRIMARY KEY;\n",
                SchemaObjectType.UniqueConstraint => $"ALTER TABLE {parentQualified} DROP CONSTRAINT {obj.Name};\n",
                SchemaObjectType.ForeignKey => $"ALTER TABLE {parentQualified} DROP FOREIGN KEY {obj.Name};\n",
                SchemaObjectType.CheckConstraint => $"ALTER TABLE {parentQualified} DROP CHECK {obj.Name};\n",
                SchemaObjectType.Trigger => $"DROP TRIGGER {qualifiedName};\n",
                SchemaObjectType.Sequence => $"DROP SEQUENCE {qualifiedName};\n",
                SchemaObjectType.Procedure => $"DROP PROCEDURE {qualifiedName};\n",
                SchemaObjectType.Function => $"DROP FUNCTION {qualifiedName};\n",
                _ => $"-- TODO: Implement DROP for {obj.ObjectType}\n"
            };
        }

        private string GenerateModifyDdl(SchemaDifference diff, SchemaObject source, SchemaObject target, string targetSchema)
        {
            var sb = new StringBuilder();
            var qualifiedName = $"{targetSchema}.{source.Name}";

            switch (diff.ObjectType)
            {
                case SchemaObjectType.Column:
                    sb.AppendLine($"-- Column {source.Name} in table {source.ParentName} has differences:");
                    foreach (var propDiff in diff.PropertyDifferences)
                    {
                        sb.AppendLine($"--   {propDiff}");
                    }
                    sb.AppendLine(GenerateAlterColumnDdl(source, targetSchema, diff.PropertyDifferences));
                    break;

                case SchemaObjectType.View:
                case SchemaObjectType.Trigger:
                case SchemaObjectType.Procedure:
                case SchemaObjectType.Function:
                    // For objects with source code, use CREATE OR REPLACE if available, else DROP/CREATE
                    sb.AppendLine("-- Source code differs - recreating object");
                    sb.AppendLine(GenerateDropDdl(target, targetSchema));
                    sb.AppendLine(GenerateCreateDdl(source, targetSchema));
                    break;

                case SchemaObjectType.Index:
                    sb.AppendLine("-- Index structure differs - recreating");
                    sb.AppendLine(GenerateDropDdl(target, targetSchema));
                    sb.AppendLine(GenerateCreateDdl(source, targetSchema));
                    break;

                case SchemaObjectType.Sequence:
                    sb.AppendLine(GenerateAlterSequenceDdl(source, targetSchema, diff.PropertyDifferences));
                    break;

                default:
                    sb.AppendLine($"-- Modified {diff.ObjectType} - differences:");
                    foreach (var propDiff in diff.PropertyDifferences)
                    {
                        sb.AppendLine($"--   {propDiff}");
                    }
                    sb.AppendLine($"-- TODO: Generate ALTER statement for {diff.ObjectType}");
                    break;
            }

            return sb.ToString();
        }

        #region Specific DDL Generators

        private string GenerateCreateTableDdl(SchemaObject table, string targetSchema)
        {
            // Note: Full table DDL would require column information
            // This is a placeholder - in real implementation, we'd fetch column details
            var sb = new StringBuilder();
            sb.AppendLine($"CREATE TABLE {targetSchema}.{table.Name} (");
            sb.AppendLine("    -- TODO: Column definitions would be generated here");
            sb.AppendLine("    -- Run 'DESCRIBE TABLE' on source to get full structure");
            sb.AppendLine(");");
            return sb.ToString();
        }

        private string GenerateCreateViewDdl(SchemaObject view, string targetSchema)
        {
            if (!string.IsNullOrEmpty(view.SourceCode))
            {
                // Replace schema in source code
                return view.SourceCode.Replace($"{view.Schema}.", $"{targetSchema}.") + ";\n";
            }
            return $"-- CREATE VIEW {targetSchema}.{view.Name} AS ... (source not available)\n";
        }

        private string GenerateAddColumnDdl(SchemaObject column, string targetSchema)
        {
            var dataType = column.Properties.TryGetValue("DataType", out var dt) ? dt?.ToString() : "VARCHAR(100)";
            var length = column.Properties.TryGetValue("Length", out var len) ? len : null;
            var scale = column.Properties.TryGetValue("Scale", out var sc) ? sc : null;
            var nullable = column.Properties.TryGetValue("Nullable", out var nl) && nl?.ToString() == "Y" ? "" : " NOT NULL";
            var defaultVal = column.Properties.TryGetValue("Default", out var dv) && !string.IsNullOrEmpty(dv?.ToString()) 
                ? $" DEFAULT {dv}" : "";

            var typeSpec = dataType;
            if (length != null && (dataType?.Contains("CHAR") == true || dataType?.Contains("DECIMAL") == true))
            {
                if (scale != null && Convert.ToInt32(scale) > 0)
                    typeSpec = $"{dataType}({length}, {scale})";
                else
                    typeSpec = $"{dataType}({length})";
            }

            return $"ALTER TABLE {targetSchema}.{column.ParentName} ADD COLUMN {column.Name} {typeSpec}{nullable}{defaultVal};\n";
        }

        private string GenerateAlterColumnDdl(SchemaObject column, string targetSchema, List<PropertyDifference> diffs)
        {
            var sb = new StringBuilder();
            var table = $"{targetSchema}.{column.ParentName}";

            foreach (var diff in diffs)
            {
                switch (diff.PropertyName)
                {
                    case "DataType":
                    case "Length":
                    case "Scale":
                        // For data type changes, need to use SET DATA TYPE
                        var dataType = column.Properties.TryGetValue("DataType", out var dt) ? dt?.ToString() : "VARCHAR";
                        var length = column.Properties.TryGetValue("Length", out var len) ? len : 100;
                        var scale = column.Properties.TryGetValue("Scale", out var sc) ? sc : 0;
                        
                        var typeSpec = dataType;
                        if (dataType?.Contains("CHAR") == true || dataType?.Contains("DECIMAL") == true)
                        {
                            if (Convert.ToInt32(scale) > 0)
                                typeSpec = $"{dataType}({length}, {scale})";
                            else
                                typeSpec = $"{dataType}({length})";
                        }
                        sb.AppendLine($"ALTER TABLE {table} ALTER COLUMN {column.Name} SET DATA TYPE {typeSpec};");
                        break;

                    case "Nullable":
                        if (diff.SourceValue == "Y")
                            sb.AppendLine($"ALTER TABLE {table} ALTER COLUMN {column.Name} DROP NOT NULL;");
                        else
                            sb.AppendLine($"ALTER TABLE {table} ALTER COLUMN {column.Name} SET NOT NULL;");
                        break;

                    case "Default":
                        if (string.IsNullOrEmpty(diff.SourceValue))
                            sb.AppendLine($"ALTER TABLE {table} ALTER COLUMN {column.Name} DROP DEFAULT;");
                        else
                            sb.AppendLine($"ALTER TABLE {table} ALTER COLUMN {column.Name} SET DEFAULT {diff.SourceValue};");
                        break;
                }
            }

            return sb.ToString();
        }

        private string GenerateCreateIndexDdl(SchemaObject index, string targetSchema)
        {
            var unique = index.Properties.TryGetValue("UniqueRule", out var ur) && ur?.ToString() == "U" ? "UNIQUE " : "";
            var columns = index.Properties.TryGetValue("Columns", out var cols) ? cols?.ToString() : "";
            
            // Parse column names from COLNAMES format (+COL1+COL2-COL3)
            var columnList = ParseColumnNames(columns ?? "");

            return $"CREATE {unique}INDEX {targetSchema}.{index.Name} ON {targetSchema}.{index.ParentName} ({columnList});\n";
        }

        private string ParseColumnNames(string colnames)
        {
            if (string.IsNullOrEmpty(colnames))
                return "";

            var parts = new List<string>();
            var current = "";
            var isDesc = false;

            foreach (var c in colnames)
            {
                if (c == '+')
                {
                    if (!string.IsNullOrEmpty(current))
                        parts.Add(current + (isDesc ? " DESC" : ""));
                    current = "";
                    isDesc = false;
                }
                else if (c == '-')
                {
                    if (!string.IsNullOrEmpty(current))
                        parts.Add(current + (isDesc ? " DESC" : ""));
                    current = "";
                    isDesc = true;
                }
                else
                {
                    current += c;
                }
            }
            if (!string.IsNullOrEmpty(current))
                parts.Add(current + (isDesc ? " DESC" : ""));

            return string.Join(", ", parts);
        }

        private string GenerateAddPrimaryKeyDdl(SchemaObject pk, string targetSchema)
        {
            var columns = pk.Properties.TryGetValue("Columns", out var cols) ? cols?.ToString() : "";
            return $"ALTER TABLE {targetSchema}.{pk.ParentName} ADD CONSTRAINT {pk.Name} PRIMARY KEY ({columns});\n";
        }

        private string GenerateAddUniqueConstraintDdl(SchemaObject uc, string targetSchema)
        {
            var columns = uc.Properties.TryGetValue("Columns", out var cols) ? cols?.ToString() : "";
            return $"ALTER TABLE {targetSchema}.{uc.ParentName} ADD CONSTRAINT {uc.Name} UNIQUE ({columns});\n";
        }

        private string GenerateAddForeignKeyDdl(SchemaObject fk, string targetSchema)
        {
            var fkCols = fk.Properties.TryGetValue("FKColumns", out var fc) ? fc?.ToString() : "";
            var refSchema = fk.Properties.TryGetValue("ReferencedSchema", out var rs) ? rs?.ToString() : targetSchema;
            var refTable = fk.Properties.TryGetValue("ReferencedTable", out var rt) ? rt?.ToString() : "";
            var pkCols = fk.Properties.TryGetValue("PKColumns", out var pc) ? pc?.ToString() : "";
            var deleteRule = fk.Properties.TryGetValue("DeleteRule", out var dr) ? GetDeleteRuleClause(dr?.ToString()) : "";
            var updateRule = fk.Properties.TryGetValue("UpdateRule", out var ur) ? GetUpdateRuleClause(ur?.ToString()) : "";

            return $"ALTER TABLE {targetSchema}.{fk.ParentName} ADD CONSTRAINT {fk.Name} " +
                   $"FOREIGN KEY ({fkCols}) REFERENCES {refSchema}.{refTable} ({pkCols}){deleteRule}{updateRule};\n";
        }

        private string GetDeleteRuleClause(string? rule)
        {
            return rule switch
            {
                "C" => " ON DELETE CASCADE",
                "N" => " ON DELETE SET NULL",
                "R" => " ON DELETE RESTRICT",
                _ => ""
            };
        }

        private string GetUpdateRuleClause(string? rule)
        {
            return rule switch
            {
                "R" => " ON UPDATE RESTRICT",
                _ => ""
            };
        }

        private string GenerateAddCheckConstraintDdl(SchemaObject check, string targetSchema)
        {
            var expression = check.SourceCode ?? "1=1";
            return $"ALTER TABLE {targetSchema}.{check.ParentName} ADD CONSTRAINT {check.Name} CHECK ({expression});\n";
        }

        private string GenerateCreateTriggerDdl(SchemaObject trigger, string targetSchema)
        {
            if (!string.IsNullOrEmpty(trigger.SourceCode))
            {
                return trigger.SourceCode.Replace($"{trigger.Schema}.", $"{targetSchema}.") + ";\n";
            }
            return $"-- CREATE TRIGGER {targetSchema}.{trigger.Name} ... (source not available)\n";
        }

        private string GenerateCreateSequenceDdl(SchemaObject seq, string targetSchema)
        {
            var sb = new StringBuilder();
            sb.Append($"CREATE SEQUENCE {targetSchema}.{seq.Name}");

            if (seq.Properties.TryGetValue("Start", out var start) && start != null)
                sb.Append($" START WITH {start}");
            if (seq.Properties.TryGetValue("Increment", out var inc) && inc != null)
                sb.Append($" INCREMENT BY {inc}");
            if (seq.Properties.TryGetValue("MinValue", out var min) && min != null)
                sb.Append($" MINVALUE {min}");
            if (seq.Properties.TryGetValue("MaxValue", out var max) && max != null)
                sb.Append($" MAXVALUE {max}");
            if (seq.Properties.TryGetValue("Cycle", out var cycle))
                sb.Append(cycle?.ToString() == "Y" ? " CYCLE" : " NO CYCLE");
            if (seq.Properties.TryGetValue("Cache", out var cache) && cache != null)
                sb.Append($" CACHE {cache}");

            sb.AppendLine(";");
            return sb.ToString();
        }

        private string GenerateAlterSequenceDdl(SchemaObject seq, string targetSchema, List<PropertyDifference> diffs)
        {
            var sb = new StringBuilder();
            sb.Append($"ALTER SEQUENCE {targetSchema}.{seq.Name}");

            foreach (var diff in diffs)
            {
                switch (diff.PropertyName)
                {
                    case "Increment":
                        sb.Append($" INCREMENT BY {diff.SourceValue}");
                        break;
                    case "MinValue":
                        sb.Append($" MINVALUE {diff.SourceValue}");
                        break;
                    case "MaxValue":
                        sb.Append($" MAXVALUE {diff.SourceValue}");
                        break;
                    case "Cycle":
                        sb.Append(diff.SourceValue == "Y" ? " CYCLE" : " NO CYCLE");
                        break;
                    case "Cache":
                        sb.Append($" CACHE {diff.SourceValue}");
                        break;
                }
            }

            sb.AppendLine(";");
            return sb.ToString();
        }

        private string GenerateCreateProcedureDdl(SchemaObject proc, string targetSchema)
        {
            if (!string.IsNullOrEmpty(proc.SourceCode))
            {
                return proc.SourceCode.Replace($"{proc.Schema}.", $"{targetSchema}.") + "\n";
            }
            return $"-- CREATE PROCEDURE {targetSchema}.{proc.Name} ... (source not available)\n";
        }

        private string GenerateCreateFunctionDdl(SchemaObject func, string targetSchema)
        {
            if (!string.IsNullOrEmpty(func.SourceCode))
            {
                return func.SourceCode.Replace($"{func.Schema}.", $"{targetSchema}.") + "\n";
            }
            return $"-- CREATE FUNCTION {targetSchema}.{func.Name} ... (source not available)\n";
        }

        #endregion

        #endregion
    }
}
