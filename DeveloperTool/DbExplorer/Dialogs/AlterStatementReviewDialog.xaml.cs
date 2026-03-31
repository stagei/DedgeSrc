using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using NLog;
using DbExplorer.Data;

namespace DbExplorer.Dialogs;

public partial class AlterStatementReviewDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    private readonly List<AlterStatementItem> _statements = new();
    private readonly IConnectionManager? _connectionManager;
    private readonly bool _allowExecution;
    
    public bool StatementsExecuted { get; private set; }
    public int ExecutedCount { get; private set; }
    
    /// <summary>
    /// Constructor for review-only mode (no execution capability)
    /// </summary>
    public AlterStatementReviewDialog(List<string> alterStatements)
    {
        InitializeComponent();
        _allowExecution = false;
        ExecuteButton.IsEnabled = false;
        ExecuteButton.ToolTip = "Connect to database to enable execution";
        
        LoadStatements(alterStatements);
    }
    
    /// <summary>
    /// Constructor for review and execute mode
    /// </summary>
    public AlterStatementReviewDialog(List<string> alterStatements, IConnectionManager connectionManager)
    {
        InitializeComponent();
        _connectionManager = connectionManager;
        _allowExecution = true;
        
        LoadStatements(alterStatements);
    }
    
    private void LoadStatements(List<string> statements)
    {
        Logger.Info("Loading {Count} ALTER statements for review", statements.Count);
        
        StatementListPanel.Children.Clear();
        _statements.Clear();
        
        var statementNumber = 1;
        foreach (var statement in statements)
        {
            var item = new AlterStatementItem
            {
                Number = statementNumber++,
                Statement = statement,
                IsSelected = true
            };
            
            _statements.Add(item);
            StatementListPanel.Children.Add(CreateStatementUI(item));
        }
        
        UpdateSummary();
    }
    
    private UIElement CreateStatementUI(AlterStatementItem item)
    {
        var border = new Border
        {
            Background = new SolidColorBrush(Color.FromRgb(30, 30, 30)),
            BorderBrush = new SolidColorBrush(Color.FromRgb(60, 60, 60)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(10),
            Margin = new Thickness(0, 0, 0, 10)
        };
        
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(30) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        
        // Checkbox
        var checkbox = new CheckBox
        {
            IsChecked = item.IsSelected,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 5, 0, 0)
        };
        checkbox.Checked += (s, e) => { item.IsSelected = true; UpdateSummary(); };
        checkbox.Unchecked += (s, e) => { item.IsSelected = false; UpdateSummary(); };
        Grid.SetColumn(checkbox, 0);
        
        // Statement panel
        var stackPanel = new StackPanel();
        Grid.SetColumn(stackPanel, 1);
        
        // Number and type
        var header = new TextBlock
        {
            Text = $"Statement {item.Number}",
            FontWeight = FontWeights.SemiBold,
            FontSize = 13,
            Foreground = new SolidColorBrush(Color.FromRgb(220, 220, 170)),
            Margin = new Thickness(0, 0, 0, 5)
        };
        stackPanel.Children.Add(header);
        
        // SQL Statement
        var sqlText = new TextBlock
        {
            Text = item.Statement,
            FontFamily = new FontFamily("Consolas"),
            FontSize = 12,
            Foreground = new SolidColorBrush(Color.FromRgb(206, 145, 120)),
            TextWrapping = TextWrapping.Wrap
        };
        stackPanel.Children.Add(sqlText);
        
        // Add warning for dangerous operations
        if (item.Statement.Contains("DROP", StringComparison.OrdinalIgnoreCase))
        {
            var warning = new TextBlock
            {
                Text = "⚠️  Warning: This statement drops data",
                Foreground = new SolidColorBrush(Color.FromRgb(244, 135, 113)),
                FontSize = 11,
                Margin = new Thickness(0, 5, 0, 0)
            };
            stackPanel.Children.Add(warning);
        }
        
        grid.Children.Add(checkbox);
        grid.Children.Add(stackPanel);
        border.Child = grid;
        
        return border;
    }
    
    private void UpdateSummary()
    {
        var total = _statements.Count;
        var selected = _statements.Count(s => s.IsSelected);
        
        SummaryText.Text = $"{total} ALTER statement{(total != 1 ? "s" : "")} generated";
        SelectedCountText.Text = $"{selected} selected";
        
        ExecuteButton.Content = $"▶️  Execute {selected} Statement{(selected != 1 ? "s" : "")}";
        ExecuteButton.IsEnabled = _allowExecution && selected > 0;
    }
    
    private void CopyAll_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Copying all ALTER statements to clipboard");
        
        var allStatements = string.Join("\n\n", _statements.Select(s => s.Statement));
        Clipboard.SetText(allStatements);
        
        MessageBox.Show(
            $"Copied {_statements.Count} statements to clipboard.",
            "Copied",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }
    
    private void CopySelected_Click(object sender, RoutedEventArgs e)
    {
        var selected = _statements.Where(s => s.IsSelected).ToList();
        
        if (selected.Count == 0)
        {
            MessageBox.Show(
                "No statements selected.",
                "Info",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }
        
        Logger.Info("Copying {Count} selected ALTER statements to clipboard", selected.Count);
        
        var selectedStatements = string.Join("\n\n", selected.Select(s => s.Statement));
        Clipboard.SetText(selectedStatements);
        
        MessageBox.Show(
            $"Copied {selected.Count} statement{(selected.Count != 1 ? "s" : "")} to clipboard.",
            "Copied",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }
    
    private void SaveToFile_Click(object sender, RoutedEventArgs e)
    {
        Logger.Info("Saving ALTER statements to file");
        
        var dialog = new SaveFileDialog
        {
            Filter = "SQL Script|*.sql|Text File|*.txt|All Files|*.*",
            DefaultExt = ".sql",
            FileName = $"migration_{DateTime.Now:yyyyMMdd_HHmmss}.sql"
        };
        
        if (dialog.ShowDialog() == true)
        {
            try
            {
                var header = $"-- Migration Script\n-- Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}\n-- Statements: {_statements.Count}\n\n";
                var statements = string.Join("\n\n", _statements.Select(s => s.Statement));
                
                System.IO.File.WriteAllText(dialog.FileName, header + statements);
                
                Logger.Info("Saved ALTER statements to {File}", dialog.FileName);
                
                MessageBox.Show(
                    $"Saved {_statements.Count} statements to:\n{dialog.FileName}",
                    "Saved",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to save ALTER statements to file");
                MessageBox.Show(
                    $"Failed to save file:\n\n{ex.Message}",
                    "Error",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
            }
        }
    }
    
    private async void Execute_Click(object sender, RoutedEventArgs e)
    {
        if (_connectionManager == null || !_allowExecution)
        {
            MessageBox.Show(
                "Execution is not available. Database connection required.",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            return;
        }
        
        var selected = _statements.Where(s => s.IsSelected).ToList();
        
        if (selected.Count == 0)
        {
            MessageBox.Show(
                "No statements selected for execution.",
                "Info",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }
        
        // Confirmation dialog
        var result = MessageBox.Show(
            $"Execute {selected.Count} ALTER statement{(selected.Count != 1 ? "s" : "")} in the database?\n\n" +
            $"⚠️  This will modify your database schema!\n\n" +
            $"Are you sure you want to proceed?",
            "Confirm Execution",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        
        if (result != MessageBoxResult.Yes)
        {
            Logger.Info("User cancelled ALTER statement execution");
            return;
        }
        
        Logger.Info("Executing {Count} ALTER statements", selected.Count);
        
        ExecuteButton.IsEnabled = false;
        ExecuteButton.Content = "⏳ Executing...";
        
        var executed = 0;
        var errors = new List<string>();
        
        foreach (var item in selected)
        {
            try
            {
                Logger.Debug("Executing statement {Number}: {Statement}", item.Number, item.Statement.Substring(0, Math.Min(100, item.Statement.Length)));
                
                await _connectionManager.ExecuteNonQueryAsync(item.Statement);
                executed++;
                
                Logger.Info("Statement {Number} executed successfully", item.Number);
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to execute statement {Number}", item.Number);
                errors.Add($"Statement {item.Number}: {ex.Message}");
            }
        }
        
        ExecutedCount = executed;
        StatementsExecuted = executed > 0;
        
        ExecuteButton.Content = $"▶️  Execute {selected.Count} Statement{(selected.Count != 1 ? "s" : "")}";
        ExecuteButton.IsEnabled = true;
        
        // Show results
        if (errors.Count == 0)
        {
            Logger.Info("All {Count} statements executed successfully", executed);
            
            MessageBox.Show(
                $"✅ Successfully executed {executed} statement{(executed != 1 ? "s" : "")}!\n\n" +
                $"Database schema has been updated.",
                "Success",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            
            DialogResult = true;
            Close();
        }
        else
        {
            Logger.Warn("Executed {Success}/{Total} statements, {Errors} errors", executed, selected.Count, errors.Count);
            
            var errorMessage = $"Executed {executed}/{selected.Count} statements.\n\n" +
                             $"Errors:\n" + string.Join("\n", errors.Take(5));
            
            if (errors.Count > 5)
                errorMessage += $"\n\n... and {errors.Count - 5} more errors. Check logs for details.";
            
            MessageBox.Show(
                errorMessage,
                "Partial Success",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }
    
    private class AlterStatementItem
    {
        public int Number { get; set; }
        public string Statement { get; set; } = string.Empty;
        public bool IsSelected { get; set; }
    }
}

