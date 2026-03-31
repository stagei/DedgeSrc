using System.Runtime.InteropServices;
using System.ComponentModel;

namespace DedgeCommon
{
    /// <summary>
    /// Manages automatic mapping of network shares for Dedge applications.
    /// Replaces the PowerShell Set-NetworkDrives function with C# implementation.
    /// </summary>
    /// <remarks>
    /// Features:
    /// - Automatic mapping of standard Dedge network drives
    /// - Server-specific drive mappings
    /// - Credential handling for secured shares
    /// - Drive persistence configuration
    /// - Error handling and logging
    /// </remarks>
    public static class NetworkShareManager
    {
        // Network drive mapping via Win32 API
        [DllImport("mpr.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int WNetAddConnection2(
            ref NETRESOURCE netResource,
            string? password,
            string? username,
            int flags);

        [DllImport("mpr.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int WNetCancelConnection2(
            string name,
            int flags,
            bool force);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct NETRESOURCE
        {
            public int dwScope;
            public int dwType;
            public int dwDisplayType;
            public int dwUsage;
            public string? lpLocalName;
            public string? lpRemoteName;
            public string? lpComment;
            public string? lpProvider;
        }

        private const int RESOURCETYPE_DISK = 0x00000001;
        private const int CONNECT_UPDATE_PROFILE = 0x00000001;  // Make persistent
        private const int CONNECT_TEMPORARY = 0x00000004;        // Temporary (not persistent)

        /// <summary>
        /// Standard network drives for all Dedge environments.
        /// </summary>
        public static class StandardDrives
        {
            public const string F_Felles = @"\\DEDGE.fk.no\Felles";
            public const string K_Utvikling = @"\\DEDGE.fk.no\erputv\Utvikling";
            public const string N_ErrProg = @"\\DEDGE.fk.no\erpprog";
            public const string R_ErpData = @"\\DEDGE.fk.no\erpdata";
            public const string X_DedgeCommon = @"C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon";
        }

        /// <summary>
        /// Production server specific drives with credentials.
        /// </summary>
        private static class ProductionDrives
        {
            public const string M_NKM = @"\\sfknam01.DEDGE.fk.no\Felles_NKM\NKM_Utlast";
            public const string Y_Fabrikk = @"\\10.60.0.4\fabrikkdata";
            public const string Z_Fabrikk2 = @"\\10.60.0.4\fabrikkdata2";
            
            // TODO: Move credentials to Azure Key Vault instead of hardcoding
            public const string M_Username = "Administrator";
            public const string M_Password = "Namdal10";
            public const string YZ_Username = "SKAERP13";
            public const string YZ_Password = "FiloDeig01!";
        }

        /// <summary>
        /// Maps all standard network drives.
        /// </summary>
        /// <param name="persist">Whether to make the mappings persistent across reboots</param>
        /// <returns>True if all mappings succeeded, false if any failed</returns>
        public static bool MapAllDrives(bool persist = true)
        {
            DedgeNLog.Info("Starting network drive mapping");
            bool allSucceeded = true;

            // Map standard drives for all computers
            allSucceeded &= MapDrive("F", StandardDrives.F_Felles, persist);
            allSucceeded &= MapDrive("K", StandardDrives.K_Utvikling, persist);
            allSucceeded &= MapDrive("N", StandardDrives.N_ErrProg, persist);
            allSucceeded &= MapDrive("R", StandardDrives.R_ErpData, persist);
            allSucceeded &= MapDrive("X", StandardDrives.X_DedgeCommon, persist);

            // Map production-specific drives if on production server
            string computerName = Environment.MachineName.ToUpper();
            if (computerName == "P-NO1FKMPRD-APP")
            {
                DedgeNLog.Info("Detected production server, mapping additional drives with credentials");
                
                allSucceeded &= MapDriveWithCredentials("M", ProductionDrives.M_NKM, 
                    ProductionDrives.M_Username, ProductionDrives.M_Password, persist);
                
                allSucceeded &= MapDriveWithCredentials("Y", ProductionDrives.Y_Fabrikk, 
                    ProductionDrives.YZ_Username, ProductionDrives.YZ_Password, persist);
                
                allSucceeded &= MapDriveWithCredentials("Z", ProductionDrives.Z_Fabrikk2, 
                    ProductionDrives.YZ_Username, ProductionDrives.YZ_Password, persist);
            }

            if (allSucceeded)
            {
                DedgeNLog.Info("All network drives mapped successfully");
            }
            else
            {
                DedgeNLog.Warn("Some network drive mappings failed (see logs above)");
            }

            return allSucceeded;
        }

        /// <summary>
        /// Maps a single network drive without credentials.
        /// </summary>
        /// <param name="driveLetter">Drive letter (without colon)</param>
        /// <param name="uncPath">UNC path to map</param>
        /// <param name="persist">Whether to persist across reboots</param>
        /// <returns>True if successful</returns>
        public static bool MapDrive(string driveLetter, string uncPath, bool persist = true)
        {
            return MapDriveWithCredentials(driveLetter, uncPath, null, null, persist);
        }

        /// <summary>
        /// Maps a single network drive with optional credentials.
        /// </summary>
        /// <param name="driveLetter">Drive letter (without colon)</param>
        /// <param name="uncPath">UNC path to map</param>
        /// <param name="username">Username for authenticated shares (null for current user)</param>
        /// <param name="password">Password for authenticated shares (null for current user)</param>
        /// <param name="persist">Whether to persist across reboots</param>
        /// <returns>True if successful or already mapped</returns>
        public static bool MapDriveWithCredentials(
            string driveLetter, 
            string uncPath, 
            string? username, 
            string? password, 
            bool persist = true)
        {
            try
            {
                string driveWithColon = $"{driveLetter}:";

                // Check if already mapped
                if (Directory.Exists(driveWithColon))
                {
                    DedgeNLog.Debug($"Drive {driveWithColon} already mapped");
                    return true;
                }

                DedgeNLog.Debug($"Mapping drive {driveWithColon} to {uncPath}" + 
                            (string.IsNullOrEmpty(username) ? "" : $" with credentials for user {username}"));

                var netResource = new NETRESOURCE
                {
                    dwType = RESOURCETYPE_DISK,
                    lpLocalName = driveWithColon,
                    lpRemoteName = uncPath,
                    lpProvider = null
                };

                int flags = persist ? CONNECT_UPDATE_PROFILE : CONNECT_TEMPORARY;
                int result = WNetAddConnection2(ref netResource, password, username, flags);

                if (result == 0)
                {
                    DedgeNLog.Info($"Successfully mapped drive {driveWithColon} to {uncPath}");
                    return true;
                }
                else
                {
                    // Get error message
                    string errorMessage = new Win32Exception(result).Message;
                    DedgeNLog.Warn($"Failed to map drive {driveWithColon} to {uncPath}: {errorMessage} (Error code: {result})");
                    return false;
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Exception mapping drive {driveLetter}: to {uncPath}");
                return false;
            }
        }

        /// <summary>
        /// Unmaps a network drive.
        /// </summary>
        /// <param name="driveLetter">Drive letter to unmap (without colon)</param>
        /// <param name="force">Force disconnect even if files are open</param>
        /// <returns>True if successful</returns>
        public static bool UnmapDrive(string driveLetter, bool force = false)
        {
            try
            {
                string driveWithColon = $"{driveLetter}:";

                // Check if mapped
                if (!Directory.Exists(driveWithColon))
                {
                    DedgeNLog.Debug($"Drive {driveWithColon} is not mapped");
                    return true;
                }

                DedgeNLog.Debug($"Unmapping drive {driveWithColon}");

                int result = WNetCancelConnection2(driveWithColon, CONNECT_UPDATE_PROFILE, force);

                if (result == 0)
                {
                    DedgeNLog.Info($"Successfully unmapped drive {driveWithColon}");
                    return true;
                }
                else
                {
                    string errorMessage = new Win32Exception(result).Message;
                    DedgeNLog.Warn($"Failed to unmap drive {driveWithColon}: {errorMessage} (Error code: {result})");
                    return false;
                }
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, $"Exception unmapping drive {driveLetter}:");
                return false;
            }
        }

        /// <summary>
        /// Gets a list of currently mapped network drives.
        /// </summary>
        /// <returns>Dictionary of drive letter to UNC path</returns>
        public static Dictionary<string, string> GetMappedDrives()
        {
            var mappedDrives = new Dictionary<string, string>();

            try
            {
                var drives = DriveInfo.GetDrives().Where(d => d.DriveType == DriveType.Network);
                
                foreach (var drive in drives)
                {
                    string driveLetter = drive.Name.TrimEnd(':', '\\');
                    mappedDrives[driveLetter] = drive.Name;
                }

                DedgeNLog.Debug($"Found {mappedDrives.Count} mapped network drives");
            }
            catch (Exception ex)
            {
                DedgeNLog.Error(ex, "Failed to enumerate mapped drives");
            }

            return mappedDrives;
        }

        /// <summary>
        /// Ensures a specific drive is mapped, mapping it if not already present.
        /// </summary>
        /// <param name="driveLetter">Drive letter (without colon)</param>
        /// <param name="uncPath">UNC path to map</param>
        /// <param name="persist">Whether to persist across reboots</param>
        /// <returns>True if drive is mapped (either already or newly mapped)</returns>
        public static bool EnsureDriveMapped(string driveLetter, string uncPath, bool persist = true)
        {
            string driveWithColon = $"{driveLetter}:";

            if (Directory.Exists(driveWithColon))
            {
                DedgeNLog.Debug($"Drive {driveWithColon} already mapped");
                return true;
            }

            return MapDrive(driveLetter, uncPath, persist);
        }
    }
}
