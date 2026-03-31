using System.Collections.Generic;
using System.Linq;
using System.Windows;
using NLog;
using DbExplorer.Services;
using DbExplorer.Services.AI;

namespace DbExplorer.Dialogs;

/// <summary>
/// Training/verification for AI SQL model with static scenarios (e.g. SYSCAT.TABLESPACES + "5 largest in GB").
/// </summary>
public partial class AiSqlTrainingDialog : Window
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly SqlEditAiService _sqlEditAiService;
    private readonly List<StaticScenario> _scenarios = new();

    public AiSqlTrainingDialog()
    {
        InitializeComponent();
        _sqlEditAiService = new SqlEditAiService(App.MetadataHandler!);
        LoadScenarios();
        ScenarioCombo.ItemsSource = _scenarios.Select(s => s.Name).ToList();
        if (_scenarios.Count > 0)
        {
            ScenarioCombo.SelectedIndex = 0;
            var s = _scenarios[0];
            OriginalSqlBox.Text = s.OriginalSql;
            InstructionBox.Text = s.Instruction;
        }
    }

    private void LoadScenarios()
    {
        _scenarios.Add(new StaticScenario
        {
            Name = "5 largest tablespaces in GB (SYSCAT.TABLESPACES)",
            OriginalSql = "SELECT TRIM(TBSPACE) AS TablespaceName, TRIM(DATATYPE) AS DataType, PAGESIZE FROM SYSCAT.TABLESPACES ORDER BY TBSPACE;",
            Instruction = "Make sql statement return the 5 largest tablespaces in GB",
            TableContext = "Table SYSCAT.TABLESPACES: TBSPACE, DATATYPE, PAGESIZE, NPAGES, TBSPACETYPE, ...",
            ExpectedContains = new[] { "FETCH FIRST 5", "SizeGB", "ORDER BY" }
        });
        _scenarios.Add(new StaticScenario
        {
            Name = "Add column list (SYSCAT.TABLES)",
            OriginalSql = "SELECT * FROM SYSCAT.TABLES WHERE TABSCHEMA = 'SYSCAT' FETCH FIRST 3 ROWS ONLY;",
            Instruction = "Return only TABNAME, TABSCHEMA, and TYPE columns",
            TableContext = "Table SYSCAT.TABLES: TABSCHEMA, TABNAME, TYPE, ...",
            ExpectedContains = new[] { "TABNAME", "TABSCHEMA", "TYPE" }
        });
    }

    private void ScenarioCombo_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (ScenarioCombo.SelectedIndex < 0 || ScenarioCombo.SelectedIndex >= _scenarios.Count) return;
        var s = _scenarios[ScenarioCombo.SelectedIndex];
        OriginalSqlBox.Text = s.OriginalSql;
        InstructionBox.Text = s.Instruction;
        OutputBox.Text = "";
        PassFailText.Text = "";
    }

    private async void Run_Click(object sender, RoutedEventArgs e)
    {
        if (ScenarioCombo.SelectedIndex < 0 || ScenarioCombo.SelectedIndex >= _scenarios.Count) return;
        var scenario = _scenarios[ScenarioCombo.SelectedIndex];
        RunButton.IsEnabled = false;
        OutputBox.Text = "Calling Ollama...";
        PassFailText.Text = "";

        try
        {
            var fullPrompt = "You are a SQL expert for DB2 12.1. Modify the following SQL according to the user's instruction. " +
                "Return only the modified SQL statement, no explanation and no markdown code fences.\n\n" +
                "Database: DB2 12.1. Schema context:\n" + scenario.TableContext + "\n\n" +
                "Original SQL:\n" + scenario.OriginalSql + "\n\n" +
                "User instruction: " + scenario.Instruction + "\n\n" +
                "Modified SQL:";

            var options = new AiGenerationOptions
            {
                Model = App.PreferencesService?.Preferences.SqlEditModel ?? "defog-llama3-sqlcoder-8b",
                Temperature = 0.2,
                MaxTokens = 4096
            };
            var ollama = new OllamaProvider();
            var response = await ollama.GenerateAsync(fullPrompt, options);
            var extracted = SqlEditAiService.ExtractSqlFromResponse(response);
            OutputBox.Text = extracted ?? response;

            var pass = scenario.ExpectedContains?.All(phrase =>
                (extracted ?? response).Contains(phrase, StringComparison.OrdinalIgnoreCase)) ?? false;
            PassFailText.Text = pass ? "Pass: output contains expected elements." : "Check: verify output manually (expected phrases may vary).";
            PassFailText.Foreground = pass ? System.Windows.Media.Brushes.Green : System.Windows.Media.Brushes.Orange;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "AI SQL training run failed");
            OutputBox.Text = "Error: " + ex.Message;
            PassFailText.Text = "Error running scenario.";
            PassFailText.Foreground = System.Windows.Media.Brushes.Red;
        }
        finally
        {
            RunButton.IsEnabled = true;
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private class StaticScenario
    {
        public string Name { get; set; } = "";
        public string OriginalSql { get; set; } = "";
        public string Instruction { get; set; } = "";
        public string TableContext { get; set; } = "";
        public string[]? ExpectedContains { get; set; }
    }
}
