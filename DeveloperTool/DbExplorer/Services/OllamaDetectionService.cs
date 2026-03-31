using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using NLog;

namespace DbExplorer.Services;

/// <summary>
/// Service for auto-detecting Ollama configuration and available models
/// </summary>
public class OllamaDetectionService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    
    /// <summary>
    /// Ollama configuration detected from environment and file system
    /// </summary>
    public class OllamaConfiguration
    {
        public string Host { get; set; } = "localhost";
        public int Port { get; set; } = 11434;
        public string Endpoint => $"http://{Host}:{Port}";
        public string ModelsPath { get; set; } = string.Empty;
        public bool IsRunning { get; set; }
        public List<OllamaModel> AvailableModels { get; set; } = new();
    }
    
    /// <summary>
    /// Information about an Ollama model
    /// </summary>
    public class OllamaModel
    {
        public string Name { get; set; } = string.Empty;
        public string Tag { get; set; } = "latest";
        public string FullName => string.IsNullOrEmpty(Tag) || Tag == "latest" ? Name : $"{Name}:{Tag}";
        public long SizeBytes { get; set; }
        public string SizeFormatted => FormatSize(SizeBytes);
        public string Family { get; set; } = string.Empty;
        public string ParameterSize { get; set; } = string.Empty;
        public string QuantizationLevel { get; set; } = string.Empty;
        public DateTime? ModifiedAt { get; set; }
        
        private static string FormatSize(long bytes)
        {
            if (bytes < 1024) return $"{bytes} B";
            if (bytes < 1024 * 1024) return $"{bytes / 1024.0:F1} KB";
            if (bytes < 1024 * 1024 * 1024) return $"{bytes / (1024.0 * 1024):F1} MB";
            return $"{bytes / (1024.0 * 1024 * 1024):F2} GB";
        }
    }
    
    /// <summary>
    /// Detect Ollama configuration from environment variables and default paths
    /// </summary>
    public OllamaConfiguration DetectConfiguration()
    {
        Logger.Info("Detecting Ollama configuration");
        
        var config = new OllamaConfiguration();
        
        try
        {
            // Check OLLAMA_HOST environment variable
            var ollamaHost = Environment.GetEnvironmentVariable("OLLAMA_HOST");
            if (!string.IsNullOrEmpty(ollamaHost))
            {
                Logger.Debug("Found OLLAMA_HOST environment variable: {Host}", ollamaHost);
                ParseHostString(ollamaHost, config);
            }
            else
            {
                Logger.Debug("OLLAMA_HOST not set, using defaults");
                config.Host = "localhost";
                config.Port = 11434;
            }
            
            // Check OLLAMA_MODELS environment variable
            var ollamaModels = Environment.GetEnvironmentVariable("OLLAMA_MODELS");
            if (!string.IsNullOrEmpty(ollamaModels))
            {
                Logger.Debug("Found OLLAMA_MODELS environment variable: {Path}", ollamaModels);
                config.ModelsPath = ollamaModels;
            }
            else
            {
                // Default path is %USERPROFILE%\.ollama\models
                var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                config.ModelsPath = Path.Combine(userProfile, ".ollama", "models");
                Logger.Debug("Using default models path: {Path}", config.ModelsPath);
            }
            
            // Try to discover models from manifest files
            if (Directory.Exists(config.ModelsPath))
            {
                config.AvailableModels = DiscoverModelsFromManifests(config.ModelsPath);
            }
            
            Logger.Info("Ollama configuration detected: Endpoint={Endpoint}, ModelsPath={Path}, Models={Count}",
                config.Endpoint, config.ModelsPath, config.AvailableModels.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error detecting Ollama configuration");
        }
        
        return config;
    }
    
    /// <summary>
    /// Check if Ollama service is running by calling the API
    /// </summary>
    public async Task<bool> IsOllamaRunningAsync(string endpoint)
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var response = await client.GetAsync($"{endpoint}/api/tags");
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }
    
    /// <summary>
    /// Get list of models from Ollama API (if running)
    /// </summary>
    public async Task<List<OllamaModel>> GetModelsFromApiAsync(string endpoint)
    {
        var models = new List<OllamaModel>();
        
        try
        {
            Logger.Debug("Fetching models from Ollama API: {Endpoint}", endpoint);
            
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            var response = await client.GetAsync($"{endpoint}/api/tags");
            
            if (!response.IsSuccessStatusCode)
            {
                Logger.Warn("Ollama API returned status {Status}", response.StatusCode);
                return models;
            }
            
            var json = await response.Content.ReadAsStringAsync();
            var doc = JsonDocument.Parse(json);
            
            if (doc.RootElement.TryGetProperty("models", out var modelsArray))
            {
                foreach (var modelElement in modelsArray.EnumerateArray())
                {
                    var model = new OllamaModel();
                    
                    if (modelElement.TryGetProperty("name", out var nameProp))
                    {
                        var fullName = nameProp.GetString() ?? "";
                        var parts = fullName.Split(':');
                        model.Name = parts[0];
                        model.Tag = parts.Length > 1 ? parts[1] : "latest";
                    }
                    
                    if (modelElement.TryGetProperty("size", out var sizeProp))
                    {
                        model.SizeBytes = sizeProp.GetInt64();
                    }
                    
                    if (modelElement.TryGetProperty("modified_at", out var modifiedProp))
                    {
                        if (DateTime.TryParse(modifiedProp.GetString(), out var modified))
                        {
                            model.ModifiedAt = modified;
                        }
                    }
                    
                    // Try to get details from nested "details" object
                    if (modelElement.TryGetProperty("details", out var details))
                    {
                        if (details.TryGetProperty("family", out var familyProp))
                            model.Family = familyProp.GetString() ?? "";
                        if (details.TryGetProperty("parameter_size", out var paramProp))
                            model.ParameterSize = paramProp.GetString() ?? "";
                        if (details.TryGetProperty("quantization_level", out var quantProp))
                            model.QuantizationLevel = quantProp.GetString() ?? "";
                    }
                    
                    models.Add(model);
                }
            }
            
            Logger.Info("Found {Count} models from Ollama API", models.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error fetching models from Ollama API");
        }
        
        return models;
    }
    
    /// <summary>
    /// Discover models from local manifest files (works even if Ollama is not running)
    /// </summary>
    public List<OllamaModel> DiscoverModelsFromManifests(string modelsPath)
    {
        var models = new List<OllamaModel>();
        
        try
        {
            // Manifest path: models/manifests/registry.ollama.ai/library/{model}/{tag}
            var manifestsPath = Path.Combine(modelsPath, "manifests", "registry.ollama.ai", "library");
            
            if (!Directory.Exists(manifestsPath))
            {
                Logger.Debug("Manifests directory not found: {Path}", manifestsPath);
                return models;
            }
            
            Logger.Debug("Scanning manifests directory: {Path}", manifestsPath);
            
            // Each subdirectory is a model
            foreach (var modelDir in Directory.GetDirectories(manifestsPath))
            {
                var modelName = Path.GetFileName(modelDir);
                
                // Each file in the model directory is a tag
                foreach (var tagFile in Directory.GetFiles(modelDir))
                {
                    try
                    {
                        var tagName = Path.GetFileName(tagFile);
                        var model = new OllamaModel
                        {
                            Name = modelName,
                            Tag = tagName
                        };
                        
                        // Read manifest to get more details
                        var manifestContent = File.ReadAllText(tagFile);
                        if (!string.IsNullOrEmpty(manifestContent))
                        {
                            try
                            {
                                var manifest = JsonDocument.Parse(manifestContent);
                                
                                // Calculate total size from layers
                                long totalSize = 0;
                                if (manifest.RootElement.TryGetProperty("layers", out var layers))
                                {
                                    foreach (var layer in layers.EnumerateArray())
                                    {
                                        if (layer.TryGetProperty("size", out var size))
                                        {
                                            totalSize += size.GetInt64();
                                        }
                                    }
                                }
                                model.SizeBytes = totalSize;
                                
                                // Get config digest to find config file for more details
                                if (manifest.RootElement.TryGetProperty("config", out var configProp))
                                {
                                    if (configProp.TryGetProperty("digest", out var digestProp))
                                    {
                                        var digest = digestProp.GetString() ?? "";
                                        // Could read config file for more details but keeping it simple
                                    }
                                }
                            }
                            catch (JsonException)
                            {
                                // Manifest might not be valid JSON, skip details
                            }
                        }
                        
                        // Get file modification time
                        var fileInfo = new FileInfo(tagFile);
                        model.ModifiedAt = fileInfo.LastWriteTime;
                        
                        models.Add(model);
                        Logger.Debug("Discovered model: {Name}:{Tag} ({Size})", modelName, tagName, model.SizeFormatted);
                    }
                    catch (Exception ex)
                    {
                        Logger.Warn(ex, "Error reading manifest for {Model}", modelName);
                    }
                }
            }
            
            Logger.Info("Discovered {Count} models from manifests", models.Count);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Error discovering models from manifests");
        }
        
        return models.OrderBy(m => m.Name).ThenBy(m => m.Tag).ToList();
    }
    
    /// <summary>
    /// Get comprehensive configuration including API check
    /// </summary>
    public async Task<OllamaConfiguration> GetFullConfigurationAsync()
    {
        var config = DetectConfiguration();
        
        // Check if service is running
        config.IsRunning = await IsOllamaRunningAsync(config.Endpoint);
        
        // If running, get fresh model list from API
        if (config.IsRunning)
        {
            var apiModels = await GetModelsFromApiAsync(config.Endpoint);
            if (apiModels.Count > 0)
            {
                config.AvailableModels = apiModels;
            }
        }
        
        return config;
    }
    
    private void ParseHostString(string hostString, OllamaConfiguration config)
    {
        try
        {
            // Format: [host]:port or just port
            var parts = hostString.Split(':');
            
            if (parts.Length == 1)
            {
                // Just port number or just host
                if (int.TryParse(parts[0], out var port))
                {
                    config.Port = port;
                }
                else
                {
                    config.Host = parts[0];
                }
            }
            else if (parts.Length >= 2)
            {
                config.Host = string.IsNullOrEmpty(parts[0]) ? "localhost" : parts[0];
                if (parts[0] == "0.0.0.0") config.Host = "localhost";
                
                if (int.TryParse(parts[^1], out var port))
                {
                    config.Port = port;
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Error parsing host string: {Host}", hostString);
        }
    }
}
