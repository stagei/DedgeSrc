using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using NLog;
using DbExplorer.Models;

namespace DbExplorer.Services;

/// <summary>
/// Service for managing connection profiles
/// </summary>
public class ConnectionProfileService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private readonly string _profilesFile;
    
    public ConnectionProfileService()
    {
        _profilesFile = UserDataFolderHelper.GetFilePath("connection_profiles.json");
        var directory = Path.GetDirectoryName(_profilesFile);
        if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
        {
            Directory.CreateDirectory(directory);
        }
        MigrateFromAppDataIfNeeded();
        Logger.Debug("Connection profiles file: {File}", _profilesFile);
    }

    private void MigrateFromAppDataIfNeeded()
    {
        if (File.Exists(_profilesFile)) return;
        var oldPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DbExplorer", "connection_profiles.json");
        if (!File.Exists(oldPath)) return;
        try
        {
            File.Copy(oldPath, _profilesFile);
            Logger.Info("Migrated connection_profiles.json from AppData to user data folder");
        }
        catch (Exception ex)
        {
            Logger.Warn(ex, "Could not migrate connection_profiles.json from AppData");
        }
    }
    
    /// <summary>
    /// Get connection profile by name
    /// </summary>
    public DatabaseConnection? GetProfile(string profileName)
    {
        Logger.Debug("Loading profile: {ProfileName}", profileName);
        
        if (!File.Exists(_profilesFile))
        {
            Logger.Warn("Profiles file not found: {File}", _profilesFile);
            return null;
        }
        
        try
        {
            var json = File.ReadAllText(_profilesFile);
            var profiles = JsonSerializer.Deserialize<List<DatabaseConnection>>(json);
            
            var profile = profiles?.FirstOrDefault(p => 
                p.Name.Equals(profileName, StringComparison.OrdinalIgnoreCase));
                
            if (profile == null)
            {
                Logger.Warn("Profile not found: {ProfileName}", profileName);
            }
            else
            {
                Logger.Info("Profile loaded: {ProfileName}", profileName);
            }
            
            return profile;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load profile: {ProfileName}", profileName);
            return null;
        }
    }
    
    /// <summary>
    /// Save connection profile
    /// </summary>
    public void SaveProfile(DatabaseConnection profile)
    {
        Logger.Info("Saving profile: {ProfileName}", profile.Name);
        
        try
        {
            var profiles = LoadAllProfiles();
            
            // Remove existing profile with same name
            profiles.RemoveAll(p => p.Name.Equals(profile.Name, StringComparison.OrdinalIgnoreCase));
            
            // Add new/updated profile
            profiles.Add(profile);
            
            // Save to file
            var options = new JsonSerializerOptions 
            { 
                WriteIndented = true 
            };
            var json = JsonSerializer.Serialize(profiles, options);
            
            File.WriteAllText(_profilesFile, json);
            Logger.Info("Profile saved successfully: {ProfileName}", profile.Name);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to save profile: {ProfileName}", profile.Name);
            throw;
        }
    }
    
    /// <summary>
    /// Load all connection profiles
    /// </summary>
    public List<DatabaseConnection> LoadAllProfiles()
    {
        if (!File.Exists(_profilesFile))
        {
            Logger.Debug("No profiles file found, returning empty list");
            return new List<DatabaseConnection>();
        }
            
        try
        {
            var json = File.ReadAllText(_profilesFile);
            var profiles = JsonSerializer.Deserialize<List<DatabaseConnection>>(json) ?? new List<DatabaseConnection>();
            
            Logger.Debug("Loaded {Count} profiles", profiles.Count);
            return profiles;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to load profiles");
            return new List<DatabaseConnection>();
        }
    }
    
    /// <summary>
    /// Delete connection profile
    /// </summary>
    public bool DeleteProfile(string profileName)
    {
        Logger.Info("Deleting profile: {ProfileName}", profileName);
        
        try
        {
            var profiles = LoadAllProfiles();
            var removed = profiles.RemoveAll(p => p.Name.Equals(profileName, StringComparison.OrdinalIgnoreCase));
            
            if (removed > 0)
            {
                var options = new JsonSerializerOptions { WriteIndented = true };
                var json = JsonSerializer.Serialize(profiles, options);
                File.WriteAllText(_profilesFile, json);
                
                Logger.Info("Profile deleted: {ProfileName}", profileName);
                return true;
            }
            
            Logger.Warn("Profile not found for deletion: {ProfileName}", profileName);
            return false;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to delete profile: {ProfileName}", profileName);
            return false;
        }
    }
}

