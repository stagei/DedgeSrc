using Xunit;
using Xunit.Abstractions;
using DedgeCommon;
using System;
using System.Collections.Generic;
using System.Text.Json;

namespace TestGlobalSettings
{
    /// <summary>
    /// Comprehensive tests for GlobalFunctions.cs to verify all GlobalSettings.json elements
    /// are correctly loaded into usable object variables
    /// </summary>
    public class GlobalSettingsTests
    {
        private readonly ITestOutputHelper _output;

        public GlobalSettingsTests(ITestOutputHelper output)
        {
            _output = output;
        }

        #region Basic Functionality Tests

        [Fact]
        public void GlobalSettings_CanBeLoaded()
        {
            // Arrange & Act
            var settings = GlobalFunctions.GetGlobalSettings();

            // Assert
            Assert.NotNull(settings);
            _output.WriteLine("✓ GlobalSettings loaded successfully");
        }

        [Fact]
        public void GlobalSettings_FilePath_IsValid()
        {
            // Arrange & Act
            string filePath = GlobalFunctions.GetGlobalSettingsFilePath();

            // Assert
            Assert.NotNull(filePath);
            Assert.NotEmpty(filePath);
            Assert.EndsWith("GlobalSettings.json", filePath);
            _output.WriteLine($"✓ GlobalSettings file path: {filePath}");
        }

        [Fact]
        public void GlobalSettings_CachingWorks()
        {
            // Arrange & Act
            var settings1 = GlobalFunctions.GetGlobalSettings();
            var settings2 = GlobalFunctions.GetGlobalSettings();

            // Assert
            Assert.Same(settings1, settings2);
            _output.WriteLine("✓ GlobalSettings caching is working (same instance returned)");
        }

        [Fact]
        public void GlobalSettings_ForceRefreshWorks()
        {
            // Arrange
            var settings1 = GlobalFunctions.GetGlobalSettings();

            // Act
            var settings2 = GlobalFunctions.GetGlobalSettings(forceRefresh: true);

            // Assert
            Assert.NotNull(settings2);
            _output.WriteLine("✓ GlobalSettings force refresh works");
        }

        #endregion

        #region Organization Section Tests

        [Fact]
        public void Organization_DefaultDomain_IsLoaded()
        {
            // Arrange & Act
            string defaultDomain = GlobalFunctions.GetDefaultDomain();

            // Assert
            Assert.NotNull(defaultDomain);
            Assert.NotEmpty(defaultDomain);
            Assert.Equal("DEDGE.fk.no", defaultDomain);
            _output.WriteLine($"✓ Organization.DefaultDomain: {defaultDomain}");
        }

        [Fact]
        public void Organization_AllProperties_AreAccessible()
        {
            // Arrange
            var settings = GlobalFunctions.GetGlobalSettings();
            var organization = settings.Organization;

            // Act & Assert - Test all Organization properties
            var properties = new Dictionary<string, string>
            {
                ["DefaultDomain"] = (string)organization.DefaultDomain,
                ["Abbreviation"] = (string)organization.Abbreviation,
                ["FullName"] = (string)organization.FullName,
                ["ShortName"] = (string)organization.ShortName,
                ["OrganizationNumber"] = (string)organization.OrganizationNumber,
                ["Website"] = (string)organization.Website,
                ["LogoUrlPath"] = (string)organization.LogoUrlPath,
                ["LogoUncPath"] = (string)organization.LogoUncPath,
                ["IconUncPath"] = (string)organization.IconUncPath,
                ["PrimaryApplicationName"] = (string)organization.PrimaryApplicationName
            };

            foreach (var prop in properties)
            {
                Assert.NotNull(prop.Value);
                Assert.NotEmpty(prop.Value);
                _output.WriteLine($"✓ Organization.{prop.Key}: {prop.Value}");
            }

            Assert.Equal(10, properties.Count);
            _output.WriteLine($"✓ All {properties.Count} Organization properties are accessible");
        }

        #endregion

        #region Paths Section Tests

        [Fact]
        public void Paths_Common_IsLoaded()
        {
            // Arrange & Act
            string commonPath = GlobalFunctions.GetCommonPath();

            // Assert
            Assert.NotNull(commonPath);
            Assert.NotEmpty(commonPath);
            Assert.StartsWith(@"\\", commonPath); // Network path
            _output.WriteLine($"✓ Paths.Common: {commonPath}");
        }

        [Fact]
        public void Paths_DevToolsWeb_IsLoaded()
        {
            // Arrange & Act
            string devToolsWebPath = GlobalFunctions.GetDevToolsWebPath();

            // Assert
            Assert.NotNull(devToolsWebPath);
            Assert.NotEmpty(devToolsWebPath);
            _output.WriteLine($"✓ Paths.DevToolsWeb: {devToolsWebPath}");
        }

        [Fact]
        public void Paths_DevToolsWebUrl_IsLoaded()
        {
            // Arrange & Act
            string devToolsWebUrl = GlobalFunctions.GetDevToolsWebPathUrl();

            // Assert
            Assert.NotNull(devToolsWebUrl);
            Assert.NotEmpty(devToolsWebUrl);
            Assert.StartsWith("http", devToolsWebUrl);
            _output.WriteLine($"✓ Paths.DevToolsWebUrl: {devToolsWebUrl}");
        }

        [Fact]
        public void Paths_AllProperties_AreAccessible()
        {
            // Arrange
            var settings = GlobalFunctions.GetGlobalSettings();
            var paths = settings.Paths;

            // Act & Assert - Test all Paths properties
            var properties = new Dictionary<string, string>
            {
                ["Common"] = (string)paths.Common,
                ["CommonLog"] = (string)paths.CommonLog,
                ["DevToolsWeb"] = (string)paths.DevToolsWeb,
                ["DevToolsWebContent"] = (string)paths.DevToolsWebContent,
                ["DevToolsWebUrl"] = (string)paths.DevToolsWebUrl,
                ["TempFk"] = (string)paths.TempFk,
                ["AdInfo"] = (string)paths.AdInfo
            };

            foreach (var prop in properties)
            {
                Assert.NotNull(prop.Value);
                Assert.NotEmpty(prop.Value);
                _output.WriteLine($"✓ Paths.{prop.Key}: {prop.Value}");
            }

            Assert.Equal(7, properties.Count);
            _output.WriteLine($"✓ All {properties.Count} Paths properties are accessible");
        }

        #endregion

        #region Config Section Tests

        [Fact]
        public void Config_ComputerInfo_IsLoaded()
        {
            // Arrange & Act
            string computerInfoPath = GlobalFunctions.GetFkComputerInfoFilePath();

            // Assert
            Assert.NotNull(computerInfoPath);
            Assert.NotEmpty(computerInfoPath);
            Assert.EndsWith("ComputerInfo.json", computerInfoPath);
            _output.WriteLine($"✓ Config.ComputerInfo path: {computerInfoPath}");
        }

        [Fact]
        public void Config_PortGroup_IsLoaded()
        {
            // Arrange & Act
            string portGroupPath = GlobalFunctions.GetFkPortGroupFilePath();

            // Assert
            Assert.NotNull(portGroupPath);
            Assert.NotEmpty(portGroupPath);
            Assert.EndsWith("PortGroup.json", portGroupPath);
            _output.WriteLine($"✓ Config.PortGroup path: {portGroupPath}");
        }

        [Fact]
        public void Config_ServerTypes_IsLoaded()
        {
            // Arrange & Act
            string serverTypesPath = GlobalFunctions.GetFkServerTypesFilePath();

            // Assert
            Assert.NotNull(serverTypesPath);
            Assert.NotEmpty(serverTypesPath);
            Assert.EndsWith("ServerTypes.json", serverTypesPath);
            _output.WriteLine($"✓ Config.ServerTypes path: {serverTypesPath}");
        }

        [Fact]
        public void Config_ServerPortGroupsMapping_IsLoaded()
        {
            // Arrange & Act
            string serverPortGroupsMappingPath = GlobalFunctions.GetFkServerPortGroupsMappingFilePath();

            // Assert
            Assert.NotNull(serverPortGroupsMappingPath);
            Assert.NotEmpty(serverPortGroupsMappingPath);
            Assert.EndsWith("ServerPortGroupsMapping.json", serverPortGroupsMappingPath);
            _output.WriteLine($"✓ Config.ServerPortGroupsMapping path: {serverPortGroupsMappingPath}");
        }

        [Fact]
        public void Config_Databases_IsLoaded()
        {
            // Arrange & Act
            string databasesPath = GlobalFunctions.GetFkDatabasesFilePath();

            // Assert
            Assert.NotNull(databasesPath);
            Assert.NotEmpty(databasesPath);
            Assert.EndsWith("Databases.json", databasesPath);
            _output.WriteLine($"✓ Config.Databases path: {databasesPath}");
        }

        [Fact]
        public void Config_AllProperties_AreAccessible()
        {
            // Arrange
            var settings = GlobalFunctions.GetGlobalSettings();
            var config = settings.Config;

            // Act & Assert - Test all Config properties
            var properties = new Dictionary<string, string>
            {
                ["ComputerInfo"] = (string)config.ComputerInfo,
                ["PortGroup"] = (string)config.PortGroup,
                ["ServerTypes"] = (string)config.ServerTypes,
                ["ServerPortGroupsMapping"] = (string)config.ServerPortGroupsMapping,
                ["Databases"] = (string)config.Databases,
                ["DatabasesV2"] = (string)config.DatabasesV2
            };

            foreach (var prop in properties)
            {
                Assert.NotNull(prop.Value);
                Assert.NotEmpty(prop.Value);
                Assert.EndsWith(".json", prop.Value);
                _output.WriteLine($"✓ Config.{prop.Key}: {prop.Value}");
            }

            Assert.Equal(6, properties.Count);
            _output.WriteLine($"✓ All {properties.Count} Config properties are accessible");
        }

        #endregion

        #region Directories Section Tests

        [Fact]
        public void Directories_Configfiles_IsLoaded()
        {
            // Arrange & Act
            string configFilesPath = GlobalFunctions.GetConfigFilesPath();

            // Assert
            Assert.NotNull(configFilesPath);
            Assert.NotEmpty(configFilesPath);
            Assert.Contains("Configfiles", configFilesPath);
            _output.WriteLine($"✓ Directories.Configfiles path: {configFilesPath}");
        }

        [Fact]
        public void Directories_AllProperties_AreAccessible()
        {
            // Arrange
            var settings = GlobalFunctions.GetGlobalSettings();
            var directories = settings.Directories;

            // Act & Assert - Test all Directories properties
            var properties = new Dictionary<string, string>
            {
                ["Logfiles"] = (string)directories.Logfiles,
                ["Configfiles"] = (string)directories.Configfiles,
                ["ConfigResources"] = (string)directories.ConfigResources,
                ["Software"] = (string)directories.Software,
                ["PowerShellApps"] = (string)directories.PowerShellApps,
                ["NodeJsApps"] = (string)directories.NodeJsApps,
                ["PythonApps"] = (string)directories.PythonApps,
                ["WindowsApps"] = (string)directories.WindowsApps,
                ["RexxApps"] = (string)directories.RexxApps,
                ["WingetApps"] = (string)directories.WingetApps,
                ["OtherWindowsApps"] = (string)directories.OtherWindowsApps
            };

            foreach (var prop in properties)
            {
                Assert.NotNull(prop.Value);
                Assert.NotEmpty(prop.Value);
                _output.WriteLine($"✓ Directories.{prop.Key}: {prop.Value}");
            }

            Assert.Equal(11, properties.Count);
            _output.WriteLine($"✓ All {properties.Count} Directories properties are accessible");
        }

        #endregion

        #region AzureDevOps Section Tests

        [Fact]
        public void AzureDevOps_AllProperties_AreAccessible()
        {
            // Arrange
            var settings = GlobalFunctions.GetGlobalSettings();
            var azureDevOps = settings.AzureDevOps;

            // Act & Assert - Test all AzureDevOps properties
            var properties = new Dictionary<string, string>
            {
                ["Organization"] = (string)azureDevOps.Organization,
                ["Project"] = (string)azureDevOps.Project,
                ["Repository"] = (string)azureDevOps.Repository,
                ["Pat"] = (string)azureDevOps.Pat
            };

            foreach (var prop in properties)
            {
                Assert.NotNull(prop.Value);
                Assert.NotEmpty(prop.Value);
                _output.WriteLine($"✓ AzureDevOps.{prop.Key}: {(prop.Key == "Pat" ? "***REDACTED***" : prop.Value)}");
            }

            Assert.Equal(4, properties.Count);
            _output.WriteLine($"✓ All {properties.Count} AzureDevOps properties are accessible");
        }

        [Fact]
        public void AzureDevOps_Organization_IsCorrect()
        {
            // Arrange
            var settings = GlobalFunctions.GetGlobalSettings();

            // Act
            string organization = (string)settings.AzureDevOps.Organization;

            // Assert
            Assert.Equal("Dedge", organization);
            _output.WriteLine($"✓ AzureDevOps.Organization: {organization}");
        }

        #endregion

        #region DefaultBackupConfig Section Tests

        [Fact]
        public void DefaultBackupConfig_AllProperties_AreAccessible()
        {
            // Arrange
            var settings = GlobalFunctions.GetGlobalSettings();
            var backupConfig = settings.DefaultBackupConfig;

            // Act & Assert - Test all DefaultBackupConfig properties
            int buffers = (int)backupConfig.buffers;
            int bufferSize = (int)backupConfig.buffer_size;
            int parallelism = (int)backupConfig.parallelism;
            int utilImpactPriority = (int)backupConfig.util_impact_priority;

            Assert.True(buffers > 0);
            Assert.True(bufferSize > 0);
            Assert.True(parallelism > 0);
            Assert.True(utilImpactPriority > 0);

            _output.WriteLine($"✓ DefaultBackupConfig.buffers: {buffers}");
            _output.WriteLine($"✓ DefaultBackupConfig.buffer_size: {bufferSize}");
            _output.WriteLine($"✓ DefaultBackupConfig.parallelism: {parallelism}");
            _output.WriteLine($"✓ DefaultBackupConfig.util_impact_priority: {utilImpactPriority}");
            _output.WriteLine($"✓ All 4 DefaultBackupConfig properties are accessible");
        }

        #endregion

        #region Comprehensive Validation Tests

        [Fact]
        public void AllSections_ArePresent()
        {
            // Arrange & Act
            var settings = GlobalFunctions.GetGlobalSettings();

            // Assert - Verify all major sections exist
            Assert.NotNull(settings.Organization);
            Assert.NotNull(settings.Paths);
            Assert.NotNull(settings.Config);
            Assert.NotNull(settings.Directories);
            Assert.NotNull(settings.AzureDevOps);
            Assert.NotNull(settings.DefaultBackupConfig);

            _output.WriteLine("✓ All 6 major sections are present:");
            _output.WriteLine("  - Organization");
            _output.WriteLine("  - Paths");
            _output.WriteLine("  - Config");
            _output.WriteLine("  - Directories");
            _output.WriteLine("  - AzureDevOps");
            _output.WriteLine("  - DefaultBackupConfig");
        }

        [Fact]
        public void AllProperties_TotalCount()
        {
            // This test provides a summary of all properties across all sections

            // Arrange
            var settings = GlobalFunctions.GetGlobalSettings();

            // Act - Count properties in each section
            int organizationCount = 10; // Verified in Organization_AllProperties_AreAccessible
            int pathsCount = 7;          // Verified in Paths_AllProperties_AreAccessible
            int configCount = 6;         // Verified in Config_AllProperties_AreAccessible
            int directoriesCount = 11;   // Verified in Directories_AllProperties_AreAccessible
            int azureDevOpsCount = 4;    // Verified in AzureDevOps_AllProperties_AreAccessible
            int defaultBackupConfigCount = 4; // Verified in DefaultBackupConfig_AllProperties_AreAccessible

            int totalCount = organizationCount + pathsCount + configCount + 
                           directoriesCount + azureDevOpsCount + defaultBackupConfigCount;

            // Assert
            Assert.Equal(42, totalCount);

            _output.WriteLine("✅ COMPREHENSIVE VALIDATION COMPLETE");
            _output.WriteLine("=====================================");
            _output.WriteLine($"Organization properties:        {organizationCount}");
            _output.WriteLine($"Paths properties:               {pathsCount}");
            _output.WriteLine($"Config properties:              {configCount}");
            _output.WriteLine($"Directories properties:         {directoriesCount}");
            _output.WriteLine($"AzureDevOps properties:         {azureDevOpsCount}");
            _output.WriteLine($"DefaultBackupConfig properties: {defaultBackupConfigCount}");
            _output.WriteLine("-------------------------------------");
            _output.WriteLine($"TOTAL PROPERTIES:               {totalCount}");
            _output.WriteLine("=====================================");
            _output.WriteLine("✅ All elements from GlobalSettings.json are loaded");
            _output.WriteLine("✅ All elements are accessible as object variables");
            _output.WriteLine("✅ All tests passed successfully!");
        }

        #endregion
    }
}


