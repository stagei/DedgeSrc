using System.Security.Cryptography;
using System.Text;

namespace DedgeRemoteConnect.Models;

public class SecureCredentialManager
{
    private readonly string _documentsFolder;
    private readonly string _rdpBaseFolder;
    private readonly string _currentComputerFolder;

    public SecureCredentialManager()
    {
        _documentsFolder = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        _rdpBaseFolder = Path.Combine(_documentsFolder, "RDP");
        _currentComputerFolder = Path.Combine(_rdpBaseFolder, Environment.MachineName);

        if (!Directory.Exists(_currentComputerFolder))
        {
            Directory.CreateDirectory(_currentComputerFolder);
        }
    }

    private string GetRdpFilePath(string machineName)
    {
        // Remove .DEDGE.fk.no domain suffix and convert to lowercase
        string cleanName = machineName.ToLower().Replace(".DEDGE.fk.no", "");

        return Path.Combine(_currentComputerFolder, $"{cleanName}.rdp");
    }

    private string GetOldRdpFilePath(string machineName)
    {
        // Old path directly in Documents folder
        string cleanName = machineName.ToLower().Replace(".DEDGE.fk.no", "");
        return Path.Combine(_documentsFolder, $"{cleanName}.rdp");
    }

    private void MigrateOldRdpFile(string machineName)
    {
        string oldPath = GetOldRdpFilePath(machineName);
        string newPath = GetRdpFilePath(machineName);

        if (File.Exists(oldPath) && !File.Exists(newPath))
        {
            try
            {
                File.Move(oldPath, newPath);
            }
            catch
            {
                // If move fails, try copy and delete
                try
                {
                    File.Copy(oldPath, newPath);
                    File.Delete(oldPath);
                }
                catch
                {
                    // If all fails, ignore - user will have to recreate
                }
            }
        }
    }

    private string EncryptPassword(string password)
    {
        // Use Unicode encoding like in PowerShell
        Encoding encoding = Encoding.Unicode;
        byte[] passwordAsBytes = encoding.GetBytes(password);
        byte[] encryptedBytes = ProtectedData.Protect(
            passwordAsBytes,
            null,
            DataProtectionScope.CurrentUser
        );

        // Convert to hex string like in PowerShell
        return BitConverter.ToString(encryptedBytes).Replace("-", "");
    }

    private string? DecryptPassword(string encryptedHex)
    {
        try
        {
            // Convert hex string to bytes
            byte[] encryptedBytes = new byte[encryptedHex.Length / 2];
            for (int i = 0; i < encryptedBytes.Length; i++)
            {
                encryptedBytes[i] = Convert.ToByte(encryptedHex.Substring(i * 2, 2), 16);
            }

            // Decrypt using DPAPI
            byte[] decryptedBytes = ProtectedData.Unprotect(
                encryptedBytes,
                null,
                DataProtectionScope.CurrentUser
            );

            // Use Unicode encoding like in PowerShell
            return Encoding.Unicode.GetString(decryptedBytes);
        }
        catch
        {
            return null;
        }
    }

    public string SaveCredentials(string machineName, string username, string password,
        bool useMultiMonitor = false, bool redirectPrinters = true, bool redirectClipboard = true, int audioMode = 0)
    {
        // First try to migrate any old RDP file
        MigrateOldRdpFile(machineName);

        string rdpPath = GetRdpFilePath(machineName);

        // Create RDP file content with exact settings and order from user's file
        StringBuilder rdpContent = new();
        // Screen and display settings
        rdpContent.AppendLine("screen mode id:i:2");
        rdpContent.AppendLine($"use multimon:i:{(useMultiMonitor ? 1 : 0)}");
        rdpContent.AppendLine("desktopwidth:i:3840");
        rdpContent.AppendLine("desktopheight:i:1080");
        rdpContent.AppendLine("session bpp:i:32");
        rdpContent.AppendLine("winposstr:s:0,1,0,0,1425,1040");
        rdpContent.AppendLine("compression:i:1");
        rdpContent.AppendLine("keyboardhook:i:2");
        rdpContent.AppendLine("audiocapturemode:i:0");
        rdpContent.AppendLine("videoplaybackmode:i:1");
        rdpContent.AppendLine("connection type:i:7");
        rdpContent.AppendLine("networkautodetect:i:1");
        rdpContent.AppendLine("bandwidthautodetect:i:1");
        rdpContent.AppendLine("displayconnectionbar:i:1");
        rdpContent.AppendLine("enableworkspacereconnect:i:0");
        rdpContent.AppendLine("disable wallpaper:i:0");
        rdpContent.AppendLine("allow font smoothing:i:0");
        rdpContent.AppendLine("allow desktop composition:i:0");
        rdpContent.AppendLine("disable full window drag:i:1");
        rdpContent.AppendLine("disable menu anims:i:1");
        rdpContent.AppendLine("disable themes:i:0");
        rdpContent.AppendLine("disable cursor setting:i:0");
        rdpContent.AppendLine("bitmapcachepersistenable:i:1");
        rdpContent.AppendLine($"full address:s:{machineName}");
        rdpContent.AppendLine($"audiomode:i:{audioMode}");
        rdpContent.AppendLine($"redirectprinters:i:{(redirectPrinters ? 1 : 0)}");
        rdpContent.AppendLine("redirectcomports:i:0");
        rdpContent.AppendLine("redirectsmartcards:i:1");
        rdpContent.AppendLine("redirectwebauthn:i:1");
        rdpContent.AppendLine($"redirectclipboard:i:{(redirectClipboard ? 1 : 0)}");
        rdpContent.AppendLine("redirectposdevices:i:0");
        rdpContent.AppendLine("autoreconnection enabled:i:1");
        rdpContent.AppendLine("authentication level:i:2");
        rdpContent.AppendLine("prompt for credentials:i:0");
        rdpContent.AppendLine("negotiate security layer:i:1");
        rdpContent.AppendLine("remoteapplicationmode:i:0");
        rdpContent.AppendLine("alternate shell:s:");
        rdpContent.AppendLine("shell working directory:s:");
        rdpContent.AppendLine("gatewayhostname:s:");
        rdpContent.AppendLine("gatewayusagemethod:i:4");
        rdpContent.AppendLine("gatewaycredentialssource:i:4");
        rdpContent.AppendLine("gatewayprofileusagemethod:i:0");
        rdpContent.AppendLine("promptcredentialonce:i:0");
        rdpContent.AppendLine("gatewaybrokeringtype:i:0");
        rdpContent.AppendLine("use redirection server name:i:0");
        rdpContent.AppendLine("rdgiskdcproxy:i:0");
        rdpContent.AppendLine("kdcproxyname:s:");
        rdpContent.AppendLine("enablerdsaadauth:i:0");
        rdpContent.AppendLine("drivestoredirect:s:");
        rdpContent.AppendLine($"username:s:{username}");

        // Only add password if it exists
        if (!string.IsNullOrEmpty(password))
        {
            string encryptedHex = EncryptPassword(password);
            rdpContent.AppendLine($"password 51:b:{encryptedHex}");
        }

        // Ensure directory exists
        Directory.CreateDirectory(_currentComputerFolder);

        // Write the RDP file
        File.WriteAllText(rdpPath, rdpContent.ToString());
        return rdpPath;
    }

    public string? LoadCredentials(string machineName)
    {
        try
        {
            // First try to migrate any old RDP file
            MigrateOldRdpFile(machineName);

            string rdpPath = GetRdpFilePath(machineName);
            if (!File.Exists(rdpPath))
                return null;
            return rdpPath;
        }
        catch
        {
            return null;
        }
    }

    public void ClearCredentials(string machineName)
    {
        string rdpPath = GetRdpFilePath(machineName);
        if (File.Exists(rdpPath))
        {
            File.Delete(rdpPath);
        }
    }

    public void ClearAllCredentials()
    {
        if (Directory.Exists(_currentComputerFolder))
        {
            Directory.Delete(_currentComputerFolder, true);
            Directory.CreateDirectory(_currentComputerFolder);
        }
    }

    public List<string> GetSavedMachines()
    {
        var machines = new List<string>();

        // Get machines from current computer folder
        if (Directory.Exists(_currentComputerFolder))
        {
            machines.AddRange(Directory.GetFiles(_currentComputerFolder, "*.rdp")
                .Select(path => Path.GetFileNameWithoutExtension(path)));
        }

        return machines;
    }

    public List<string> GetAllRdpFiles()
    {
        var rdpFiles = new List<string>();

        // Get all RDP files from current computer folder
        if (Directory.Exists(_currentComputerFolder))
        {
            rdpFiles.AddRange(Directory.GetFiles(_currentComputerFolder, "*.rdp"));
        }

        // Also check for old files directly in Documents and migrate them
        var oldFiles = Directory.GetFiles(_documentsFolder, "*.rdp");
        foreach (var oldFile in oldFiles)
        {
            string machineName = Path.GetFileNameWithoutExtension(oldFile);
            MigrateOldRdpFile(machineName);
        }

        // Re-scan after migration
        if (Directory.Exists(_currentComputerFolder))
        {
            rdpFiles.Clear();
            rdpFiles.AddRange(Directory.GetFiles(_currentComputerFolder, "*.rdp"));
        }

        return rdpFiles;
    }
}