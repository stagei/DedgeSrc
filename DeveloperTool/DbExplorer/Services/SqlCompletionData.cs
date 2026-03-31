using NLog;
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ICSharpCode.AvalonEdit.CodeCompletion;
using ICSharpCode.AvalonEdit.Document;
using ICSharpCode.AvalonEdit.Editing;

namespace DbExplorer.Services;

/// <summary>
/// Base class for SQL completion data.
/// Database-agnostic - works with any SQL provider.
/// </summary>
public abstract class SqlCompletionDataBase : ICompletionData
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    public virtual string Text { get; set; } = string.Empty;
    public virtual object Description { get; set; } = string.Empty;
    public double Priority { get; set; } = 1.0;
    public ImageSource? Image { get; set; }
    
    public virtual object Content => Text;
    
    public virtual void Complete(TextArea textArea, ISegment completionSegment, EventArgs insertionRequestEventArgs)
    {
        Logger.Debug("Completing: {Text}", Text);
        textArea.Document.Replace(completionSegment, Text);
    }
}

/// <summary>
/// Completion data for SQL keywords.
/// </summary>
public class SqlKeywordCompletionData : SqlCompletionDataBase
{
    public SqlKeywordCompletionData()
    {
        // Keywords have highest priority
        Priority = 1.0;
    }
}

/// <summary>
/// Completion data for SELECT * - adds trailing space after insertion.
/// </summary>
public class SqlStarCompletionData : SqlCompletionDataBase
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    public SqlStarCompletionData()
    {
        Text = "*";
        Description = "Select all columns";
        Priority = 10.0;
    }
    
    public override void Complete(TextArea textArea, ISegment completionSegment, EventArgs insertionRequestEventArgs)
    {
        Logger.Debug("Completing * with trailing space");
        // Insert "* " (with trailing space)
        textArea.Document.Replace(completionSegment, "* ");
    }
    
    public override object Content
    {
        get
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(new TextBlock
            {
                Text = "⭐ ",
                FontSize = 12,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = "*",
                FontWeight = FontWeights.Bold,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = " (all columns)",
                FontSize = 10,
                Foreground = Brushes.Gray,
                Margin = new System.Windows.Thickness(5, 0, 0, 0),
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            return panel;
        }
    }
}

/// <summary>
/// Completion data for table names.
/// </summary>
public class SqlTableCompletionData : SqlCompletionDataBase
{
    public int RowCount { get; set; }
    
    public SqlTableCompletionData()
    {
        Priority = 2.0;
    }
    
    public new object Content
    {
        get
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(new TextBlock
            {
                Text = "📋 ",
                FontSize = 12,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = Text,
                FontWeight = FontWeights.Bold,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            
            if (RowCount > 0)
            {
                panel.Children.Add(new TextBlock
                {
                    Text = $" ({RowCount:N0} rows)",
                    FontSize = 10,
                    Foreground = Brushes.Gray,
                    Margin = new System.Windows.Thickness(5, 0, 0, 0),
                    VerticalAlignment = System.Windows.VerticalAlignment.Center
                });
            }
            
            return panel;
        }
    }
}

/// <summary>
/// Completion data for view names.
/// </summary>
public class SqlViewCompletionData : SqlCompletionDataBase
{
    public SqlViewCompletionData()
    {
        Priority = 2.0;
    }
    
    public new object Content
    {
        get
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(new TextBlock
            {
                Text = "👁️ ",
                FontSize = 12,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = Text,
                FontWeight = FontWeights.Bold,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            
            return panel;
        }
    }
}

/// <summary>
/// Completion data for column names.
/// </summary>
public class SqlColumnCompletionData : SqlCompletionDataBase
{
    public string ColumnName { get; set; } = string.Empty;
    public string DataType { get; set; } = string.Empty;
    public bool IsNullable { get; set; }
    public bool IsPrimaryKey { get; set; }
    public string TableName { get; set; } = string.Empty;
    
    public SqlColumnCompletionData()
    {
        Priority = 3.0;
    }
    
    public new string Text => ColumnName;
    
    public new object Description => 
        $"{DataType}{(IsNullable ? "" : " NOT NULL")}{(IsPrimaryKey ? " PK" : "")} (from {TableName})";
    
    public new object Content
    {
        get
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            
            // Column name
            panel.Children.Add(new TextBlock
            {
                Text = ColumnName,
                FontWeight = IsPrimaryKey ? FontWeights.Bold : FontWeights.Normal,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            
            // Data type
            panel.Children.Add(new TextBlock
            {
                Text = $" : {DataType}",
                FontSize = 10,
                Foreground = Brushes.DarkBlue,
                Margin = new System.Windows.Thickness(5, 0, 0, 0),
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            
            // PK indicator
            if (IsPrimaryKey)
            {
                panel.Children.Add(new TextBlock
                {
                    Text = " 🔑",
                    FontSize = 10,
                    Margin = new System.Windows.Thickness(3, 0, 0, 0),
                    VerticalAlignment = System.Windows.VerticalAlignment.Center
                });
            }
            
            return panel;
        }
    }
}

/// <summary>
/// Completion data for function names.
/// </summary>
public class SqlFunctionCompletionData : SqlCompletionDataBase
{
    public string? ParameterHint { get; set; }
    public string? Category { get; set; }
    
    public SqlFunctionCompletionData()
    {
        Priority = 2.0;
    }
    
    public new object Content
    {
        get
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(new TextBlock
            {
                Text = "🔧 ",
                FontSize = 12,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = Text,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            
            if (!string.IsNullOrEmpty(ParameterHint))
            {
                panel.Children.Add(new TextBlock
                {
                    Text = $" ({ParameterHint})",
                    FontSize = 10,
                    Foreground = Brushes.Gray,
                    Margin = new System.Windows.Thickness(3, 0, 0, 0),
                    VerticalAlignment = System.Windows.VerticalAlignment.Center
                });
            }
            
            return panel;
        }
    }
}

/// <summary>
/// Completion data for SQL snippets.
/// </summary>
public class SqlSnippetCompletionData : SqlCompletionDataBase
{
    public string Template { get; set; } = string.Empty;
    public string Trigger { get; set; } = string.Empty;
    
    public SqlSnippetCompletionData()
    {
        Priority = 1.5;
    }
    
    public override void Complete(TextArea textArea, ISegment completionSegment, EventArgs insertionRequestEventArgs)
    {
        // Replace trigger with template
        textArea.Document.Replace(completionSegment, Template);
        
        // Future: Add placeholder navigation with TAB
    }
    
    public override object Content
    {
        get
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(new TextBlock
            {
                Text = "📝 ",
                FontSize = 12,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = Trigger,
                FontWeight = FontWeights.Bold,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = $" ({Description})",
                FontSize = 10,
                Foreground = Brushes.DarkGreen,
                Margin = new System.Windows.Thickness(5, 0, 0, 0),
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            
            return panel;
        }
    }
}

/// <summary>
/// Completion data for data types.
/// </summary>
public class SqlDataTypeCompletionData : SqlCompletionDataBase
{
    public string? Category { get; set; }
    
    public SqlDataTypeCompletionData()
    {
        Priority = 1.5;
    }
    
    public new object Content
    {
        get
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(new TextBlock
            {
                Text = "📦 ",
                FontSize = 12,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = Text,
                FontWeight = FontWeights.SemiBold,
                Foreground = Brushes.DarkMagenta,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            
            return panel;
        }
    }
}

/// <summary>
/// Completion data for system catalog tables.
/// </summary>
public class SqlSystemTableCompletionData : SqlCompletionDataBase
{
    public string? Schema { get; set; }
    
    public SqlSystemTableCompletionData()
    {
        Priority = 2.0;
    }
    
    public new object Content
    {
        get
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(new TextBlock
            {
                Text = "🗃️ ",
                FontSize = 12,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = Text,
                FontWeight = FontWeights.Bold,
                Foreground = Brushes.DarkOrange,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            
            return panel;
        }
    }
}

/// <summary>
/// Completion data for schema names.
/// Auto-adds period after selection and triggers table completion.
/// </summary>
public class SqlSchemaCompletionData : SqlCompletionDataBase
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Action to trigger after completion (e.g., show tables)
    /// </summary>
    public Action? OnCompleted { get; set; }
    
    public SqlSchemaCompletionData()
    {
        Priority = 3.0; // High priority - schemas shown at top
    }
    
    public override void Complete(TextArea textArea, ISegment completionSegment, EventArgs insertionRequestEventArgs)
    {
        Logger.Debug("Schema completion: inserting '{Text}.' with auto-period", Text);
        
        // Insert schema name WITH period (so user can immediately type table name)
        textArea.Document.Replace(completionSegment, Text + ".");
        
        // Trigger the callback to show table completions
        OnCompleted?.Invoke();
    }
    
    public override object Content
    {
        get
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(new TextBlock
            {
                Text = "📁 ",
                FontSize = 12,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = Text,
                FontWeight = FontWeights.Bold,
                Foreground = Brushes.DarkBlue,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            
            return panel;
        }
    }
}

/// <summary>
/// Completion data for table/view alias names.
/// Used in WHERE clause to show aliases, then columns after period.
/// </summary>
public class SqlAliasCompletionData : SqlCompletionDataBase
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    public string AliasName { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public string SchemaName { get; set; } = string.Empty;
    public bool IsSubselectAlias { get; set; }
    
    /// <summary>
    /// Action to trigger after completion (e.g., show columns)
    /// </summary>
    public Action? OnCompleted { get; set; }
    
    public SqlAliasCompletionData()
    {
        Priority = 4.0; // Higher priority than columns
    }
    
    public override string Text => AliasName;
    
    public override object Description => IsSubselectAlias 
        ? $"Subquery alias" 
        : $"Alias for {SchemaName}.{TableName}";
    
    public override void Complete(TextArea textArea, ISegment completionSegment, EventArgs insertionRequestEventArgs)
    {
        Logger.Debug("Alias completion: inserting '{Alias}.' with auto-period", AliasName);
        
        // Insert alias name WITH period
        textArea.Document.Replace(completionSegment, AliasName + ".");
        
        // Trigger the callback to show column completions
        OnCompleted?.Invoke();
    }
    
    public override object Content
    {
        get
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(new TextBlock
            {
                Text = IsSubselectAlias ? "🔗 " : "🏷️ ",
                FontSize = 12,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = AliasName,
                FontWeight = FontWeights.Bold,
                Foreground = Brushes.DarkGreen,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            
            if (!IsSubselectAlias && !string.IsNullOrEmpty(TableName))
            {
                panel.Children.Add(new TextBlock
                {
                    Text = $" → {TableName}",
                    FontSize = 10,
                    Foreground = Brushes.Gray,
                    Margin = new System.Windows.Thickness(5, 0, 0, 0),
                    VerticalAlignment = System.Windows.VerticalAlignment.Center
                });
            }
            
            return panel;
        }
    }
}

/// <summary>
/// Completion data for stored procedure names.
/// </summary>
public class SqlProcedureCompletionData : SqlCompletionDataBase
{
    public SqlProcedureCompletionData()
    {
        Priority = 2.0;
    }
    
    public new object Content
    {
        get
        {
            var panel = new StackPanel { Orientation = Orientation.Horizontal };
            panel.Children.Add(new TextBlock
            {
                Text = "⚙️ ",
                FontSize = 12,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            panel.Children.Add(new TextBlock
            {
                Text = Text,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = System.Windows.VerticalAlignment.Center
            });
            
            return panel;
        }
    }
}

#region Backward Compatibility Aliases

// These aliases maintain backward compatibility with existing code
// that uses the old Db2* class names

/// <summary>Alias for SqlCompletionDataBase (backward compatibility)</summary>
public abstract class Db2CompletionDataBase : SqlCompletionDataBase { }

/// <summary>Alias for SqlKeywordCompletionData (backward compatibility)</summary>
public class Db2KeywordCompletionData : SqlKeywordCompletionData { }

/// <summary>Alias for SqlTableCompletionData (backward compatibility)</summary>
public class Db2TableCompletionData : SqlTableCompletionData { }

/// <summary>Alias for SqlViewCompletionData (backward compatibility)</summary>
public class Db2ViewCompletionData : SqlViewCompletionData { }

/// <summary>Alias for SqlColumnCompletionData (backward compatibility)</summary>
public class Db2ColumnCompletionData : SqlColumnCompletionData { }

/// <summary>Alias for SqlFunctionCompletionData (backward compatibility)</summary>
public class Db2FunctionCompletionData : SqlFunctionCompletionData { }

/// <summary>Alias for SqlSnippetCompletionData (backward compatibility)</summary>
public class Db2SnippetCompletionData : SqlSnippetCompletionData { }

#endregion
