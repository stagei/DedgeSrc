using NLog;
using DbExplorer.Services.AI;
using Xunit;

namespace DbExplorer.AutoTests;

/// <summary>
/// Tests for AI Provider integration (Ollama, OpenAI, Claude, etc.)
/// </summary>
public class AiProviderTests
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    [Fact]
    public void AiProviderManager_CanInitialize()
    {
        // Arrange & Act
        var manager = new AiProviderManager();

        // Assert
        Assert.NotNull(manager);
        Logger.Info("✅ AiProviderManager initialized successfully");
    }

    [Fact]
    public void OllamaProvider_CanBeCreated()
    {
        // Arrange & Act
        var provider = new OllamaProvider("http://localhost:11434");

        // Assert
        Assert.NotNull(provider);
        Logger.Info("✅ OllamaProvider created successfully");
    }

    [Fact]
    public void LmStudioProvider_CanBeCreated()
    {
        // Arrange & Act
        var provider = new LmStudioProvider("http://localhost:1234");

        // Assert
        Assert.NotNull(provider);
        Logger.Info("✅ LmStudioProvider created successfully");
    }

    [Fact]
    public void OpenAiProvider_CanBeCreated()
    {
        // Arrange & Act
        var provider = new OpenAiProvider("test-api-key");

        // Assert
        Assert.NotNull(provider);
        Logger.Info("✅ OpenAiProvider created successfully");
    }

    // Add more tests for actual AI calls when providers are configured
}

