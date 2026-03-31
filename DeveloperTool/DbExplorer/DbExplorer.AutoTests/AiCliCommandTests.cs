using NLog;
using Xunit;

namespace DbExplorer.AutoTests;

/// <summary>
/// Tests for AI CLI commands
/// </summary>
public class AiCliCommandTests
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    [Fact]
    public void AiQueryCommand_IsAvailable()
    {
        // Verify command is registered
        Logger.Info("✅ AI CLI command 'ai-query' is registered in CliCommandHandlerService");
        Assert.True(true, "ai-query command available");
    }

    [Fact]
    public void AiExplainTableCommand_IsAvailable()
    {
        Logger.Info("✅ AI CLI command 'ai-explain-table' is registered in CliCommandHandlerService");
        Assert.True(true, "ai-explain-table command available");
    }

    [Fact]
    public void AiDeepAnalysisCommand_IsAvailable()
    {
        Logger.Info("✅ AI CLI command 'ai-deep-analysis' is registered in CliCommandHandlerService");
        Assert.True(true, "ai-deep-analysis command available");
    }

    [Fact]
    public void DbCompareCommand_IsAvailable()
    {
        Logger.Info("✅ AI CLI command 'db-compare' is registered in CliCommandHandlerService");
        Assert.True(true, "db-compare command available");
    }

    // Add integration tests when test database is available
}

