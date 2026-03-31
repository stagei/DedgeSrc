using System;
using System.Data;
using System.Windows;
using System.Windows.Controls;
using NLog;
using DbExplorer.Data;
using DbExplorer.Models;
using DbExplorer.Services;

namespace DbExplorer.Controls;

/// <summary>
/// UserControl for displaying package details - can be embedded in dialogs or tabs
/// </summary>
public partial class PackageDetailsPanel : UserControl
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly IConnectionManager _connectionManager;
    private readonly MetadataHandler? _metadataHandler;
    private readonly PackageInfo _package;

    public PackageDetailsPanel(IConnectionManager connectionManager, PackageInfo package)
    {
        InitializeComponent();
        _connectionManager = connectionManager ?? throw new ArgumentNullException(nameof(connectionManager));
        _metadataHandler = App.MetadataHandler;
        _package = package ?? throw new ArgumentNullException(nameof(package));

        PackageNameText.Text = $"{_package.PackageName?.Trim()}";
        PackageInfoText.Text = $"Schema: {_package.PackageSchema?.Trim()} • Full Name: {_package.PackageSchema?.Trim()}.{_package.PackageName?.Trim()}";

        this.Loaded += async (s, e) =>
        {
            UIStyleService.ApplyStyles(this);
            await LoadPackageDetailsAsync();
        };
    }

    private async Task LoadPackageDetailsAsync()
    {
        try
        {
            if (_metadataHandler == null)
            {
                throw new InvalidOperationException("MetadataHandler not initialized");
            }
            
            var pkgSchema = _package.PackageSchema?.Trim() ?? "";
            var pkgName = _package.PackageName?.Trim() ?? "";
            
            // Load properties
            Dispatcher.Invoke(() =>
            {
                PkgNameValue.Text = pkgName;
                PkgSchemaValue.Text = pkgSchema;
                BoundByValue.Text = _package.BoundBy?.Trim() ?? "-";
                OwnerValue.Text = _package.Owner?.Trim() ?? "-";
                IsolationValue.Text = _package.Isolation?.Trim() ?? "-";
                CreatedValue.Text = _package.CreateTime?.ToString("yyyy-MM-dd HH:mm:ss") ?? "-";
            });

            // Check if package is valid - use required statement from JSON config
            var validSqlTemplate = _metadataHandler.GetRequiredStatement("GetPackageValid");
            var validSql = ReplacePlaceholders(validSqlTemplate, pkgSchema, pkgName);
            var validResult = await _connectionManager.ExecuteQueryAsync(validSql);
            if (validResult.Rows.Count > 0)
            {
                var valid = validResult.Rows[0]["VALID"]?.ToString();
                Dispatcher.Invoke(() => ValidValue.Text = valid == "Y" ? "Yes" : "No");
            }

            // Load statements - use required statement from JSON config
            var stmtSqlTemplate = _metadataHandler.GetRequiredStatement("GetPackageStatements_Preview");
            var stmtSql = ReplacePlaceholders(stmtSqlTemplate, pkgSchema, pkgName);
            var stmtResult = await _connectionManager.ExecuteQueryAsync(stmtSql);
            Dispatcher.Invoke(() =>
            {
                StatementsGrid.ItemsSource = stmtResult.DefaultView;
                StatementCountText.Text = $"Statements: {stmtResult.Rows.Count}";
            });

            // Load dependencies - use required statement from JSON config
            var depSqlTemplate = _metadataHandler.GetRequiredStatement("GetPackageDependencies");
            var depSql = ReplacePlaceholders(depSqlTemplate, pkgSchema, pkgName);
            var depResult = await _connectionManager.ExecuteQueryAsync(depSql);
            Dispatcher.Invoke(() =>
            {
                DependenciesGrid.ItemsSource = depResult.DefaultView;
                DependencyCountText.Text = $"Dependencies: {depResult.Rows.Count}";
            });

            Logger.Info("Package details loaded: {Schema}.{Package}", _package.PackageSchema, _package.PackageName);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error loading package details");
            MessageBox.Show($"Error loading package details: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void Statement_DoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (StatementsGrid.SelectedItem is DataRowView row)
        {
            var stmtNo = row["STMTNO"]?.ToString();
            var pkgSchema = _package.PackageSchema?.Trim() ?? "";
            var pkgName = _package.PackageName?.Trim() ?? "";
            
            if (_metadataHandler == null) return;
            
            try
            {
                // Get the full statement text - use required statement from JSON config
                var fullSqlTemplate = _metadataHandler.GetRequiredStatement("GetPackageStatementFull");
                var fullSql = ReplacePlaceholders(fullSqlTemplate, pkgSchema, pkgName, stmtNo ?? "0");
                var result = await _connectionManager.ExecuteQueryAsync(fullSql);
                if (result.Rows.Count > 0)
                {
                    var text = result.Rows[0][0]?.ToString() ?? "";
                    var window = ThemedWindowHelper.CreateScriptWindow($"Statement {stmtNo}", text, 700, 400, Window.GetWindow(this));
                    window.Show();
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to load full statement");
                MessageBox.Show($"Failed to load statement: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    private async void CopyStatement_Click(object sender, RoutedEventArgs e)
    {
        if (StatementsGrid.SelectedItem is DataRowView row)
        {
            var stmtNo = row["STMTNO"]?.ToString();
            var pkgSchema = _package.PackageSchema?.Trim() ?? "";
            var pkgName = _package.PackageName?.Trim() ?? "";
            
            if (_metadataHandler == null) return;
            
            try
            {
                // Get the full statement text - use required statement from JSON config
                var fullSqlTemplate = _metadataHandler.GetRequiredStatement("GetPackageStatementFull");
                var fullSql = ReplacePlaceholders(fullSqlTemplate, pkgSchema, pkgName, stmtNo ?? "0");
                var result = await _connectionManager.ExecuteQueryAsync(fullSql);
                if (result.Rows.Count > 0)
                {
                    Clipboard.SetText(result.Rows[0][0]?.ToString() ?? "");
                    MessageBox.Show("Statement copied to clipboard!", "Success", MessageBoxButton.OK, MessageBoxImage.Information);
                }
            }
            catch (Exception ex)
            {
                Logger.Error(ex, "Failed to copy statement");
                MessageBox.Show($"Failed to copy: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
        else
        {
            MessageBox.Show("Please select a statement first.", "No Selection", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }
    
    /// <summary>
    /// Replace ? placeholders in SQL with quoted values
    /// </summary>
    private static string ReplacePlaceholders(string sql, params string[] values)
    {
        var result = sql;
        foreach (var value in values)
        {
            var idx = result.IndexOf('?');
            if (idx >= 0)
            {
                result = result.Remove(idx, 1).Insert(idx, $"'{value}'");
            }
        }
        return result;
    }
}
