using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Configuration;
using NLog;
using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Threading.Tasks;

namespace FkStack
{
    class Program
    {
        static async Task Main(string[] args)
        {
            FkStack fkStack = new FkStack();
            await fkStack.Run(args);
        }
    }

    class FkStack
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
        private List<string> errorMessages = new List<string>();
        private List<string> moduleList = new List<string>();
        private List<string> deployEnv = new List<string>();
        private bool immediateDeploy = false;
        private string inputString = "";
        private string changeDescription = "";
        private string serviceNowId = "";
        private string defaultDatabaseInCblSet;
        private string srcPath;
        private string cblCpyPath;
        private string stackPath;
        private string prodExecPath;
        private string archivePath;
        private string logPath;
        private string logFile;
        private string tempPath;

        private readonly HttpClient httpClient;
        private readonly string serviceNowInstance;
        private readonly string serviceNowUsername;
        private readonly string serviceNowPassword;

        private string changeTitle;
        private List<FileObj> fileObjList;

        public FkStack()
        {
            httpClient = new HttpClient();
            serviceNowInstance = ConfigurationManager.AppSettings["ServiceNowInstance"];
            serviceNowUsername = ConfigurationManager.AppSettings["ServiceNowUsername"];
            serviceNowPassword = ConfigurationManager.AppSettings["ServiceNowPassword"];

            var byteArray = System.Text.Encoding.ASCII.GetBytes($"{serviceNowUsername}:{serviceNowPassword}");
            httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(byteArray));
        }

        public async Task Run(string[] args)
        {
            ParseArguments(args);
            InitializeEnvironment();
            ProcessUserInput();
            HandleFiles();
            if (deployEnv.Contains("PRD"))
            {
                await HandleServiceNow();
            }
            ArchiveAndDeploy();
        }

        private void ParseArguments(string[] args)
        {
            // Implementation remains the same
        }

        private void InitializeEnvironment()
        {
            // Implementation remains the same
        }

        private void ProcessUserInput()
        {
            // Initialize changeTitle and changeDescription
            if (changeDescription.Length > 0)
            {
                int pos = changeDescription.IndexOf('.');
                if (pos > 0)
                {
                    changeTitle = changeDescription.Substring(0, pos + 1);
                    changeDescription = changeDescription.Substring(pos + 1).Trim();
                }
                else
                {
                    changeTitle = changeDescription;
                    changeDescription = "";
                }
            }
            else
            {
                // Prompt user for change title and description
                Console.WriteLine("Enter change title:");
                changeTitle = Console.ReadLine();
                Console.WriteLine("Enter change description:");
                changeDescription = Console.ReadLine();
            }
        }

        private void HandleFiles()
        {
            fileObjList = new List<FileObj>();
            foreach (string module in moduleList)
            {
                FileObj fileObj = ProcessModule(module);
                if (fileObj != null)
                {
                    fileObjList.Add(fileObj);
                }
            }
        }

        private FileObj ProcessModule(string module)
        {
            ModuleInfo moduleInfo = GetModuleInfo(module);
            if (moduleInfo != null)
            {
                ValidateModule(moduleInfo);
                ModuleInfo validationModule = null;

                if (moduleInfo.ModuleFileSuffix == "CBL")
                {
                    string thirdChar = module.Substring(2, 1);
                    if (thirdChar == "H" || thirdChar == "F")
                    {
                        string validationName = module.Substring(0, 2) + "V" + module.Substring(3);
                        string validationSource = Path.Combine(srcPath, validationName);
                        if (File.Exists(validationSource))
                        {
                            validationModule = GetModuleInfo(validationName);
                        }
                    }
                }

                return new FileObj
                {
                    Name = module,
                    MainModule = moduleInfo,
                    ValidationModule = validationModule
                };
            }
            return null;
        }

        private ModuleInfo GetModuleInfo(string module)
        {
            string moduleFileSuffix = Path.GetExtension(module).TrimStart('.').ToUpper();
            string moduleFilePrefix = Path.GetFileNameWithoutExtension(module);
            string basePath = Path.Combine(srcPath, moduleFilePrefix);

            ModuleInfo moduleInfo = new ModuleInfo
            {
                ModuleFileName = module,
                ModuleFilePrefix = moduleFilePrefix,
                ModuleFileSuffix = moduleFileSuffix,
                BasePath = basePath,
                Src = Path.Combine(basePath, module)
            };

            if (moduleFileSuffix == "CBL")
            {
                moduleInfo.SrcTime = File.GetLastWriteTime(moduleInfo.Src);
                moduleInfo.IntTime = File.Exists(basePath + ".INT") ? File.GetLastWriteTime(basePath + ".INT") : (DateTime?)null;
                moduleInfo.IdyTime = File.Exists(basePath + ".IDY") ? File.GetLastWriteTime(basePath + ".IDY") : (DateTime?)null;
                moduleInfo.BndTime = File.Exists(basePath + ".BND") ? File.GetLastWriteTime(basePath + ".BND") : (DateTime?)null;
                moduleInfo.GsTime = File.Exists(basePath + ".GS") ? File.GetLastWriteTime(basePath + ".GS") : (DateTime?)null;
                moduleInfo.UseSql = CblUseSql(moduleInfo.Src);
                moduleInfo.CopyFiles = ScanCobolProgram(moduleInfo.Src);
            }
            else
            {
                moduleInfo.SrcTime = File.GetLastWriteTime(moduleInfo.Src);
            }

            return moduleInfo;
        }

        private void ValidateModule(ModuleInfo moduleInfo)
        {
            if (moduleInfo.ModuleFileSuffix == "CBL")
            {
                if (moduleInfo.IntTime == null)
                {
                    errorMessages.Add($"{moduleInfo.ModuleFileName} is not compiled, as the INT file does not exist!");
                }

                if (moduleInfo.IntTime != null && moduleInfo.SrcTime > moduleInfo.IntTime)
                {
                    errorMessages.Add($"{moduleInfo.ModuleFileName} is newer than the .INT file!");
                }

                if (moduleInfo.UseSql && moduleInfo.BndTime == null)
                {
                    errorMessages.Add($"{moduleInfo.ModuleFileName} uses DB2 but BND file is missing!");
                }
            }
        }

        private bool CblUseSql(string modulePath)
        {
            string[] lines = File.ReadAllLines(modulePath);
            bool result = false;
            bool defaultDatabaseInCblSetCorrect = false;
            string currentDatabase = "";

            foreach (string line in lines)
            {
                string trimmedLine = line.Trim().ToUpper();
                if (trimmedLine.StartsWith("$SET") && trimmedLine.Contains("DB2"))
                {
                    result = true;
                }

                if (trimmedLine.Contains(defaultDatabaseInCblSet))
                {
                    defaultDatabaseInCblSetCorrect = true;
                }

                Match match = Regex.Match(trimmedLine, @"DB=\s*(\S+)");
                if (match.Success)
                {
                    currentDatabase = match.Groups[1].Value;
                }
            }

            if (!defaultDatabaseInCblSetCorrect)
            {
                errorMessages.Add($"{Path.GetFileName(modulePath)} SET DATABASE in CBL is set to: {currentDatabase}. Must be set to {defaultDatabaseInCblSet} to be deployed.");
            }

            return result;
        }

        private List<string> ScanCobolProgram(string sourcePath)
        {
            string[] ikkecpy = { "DS-CNTRL", "DSSYSINF", "DSRUNNER", "DS-CALL", "SQLENV", "GMAUTILS", "DEFCPY", "REQFELL", "DSUSRVAL" };
            List<string> copyFiles = new List<string>();

            string[] lines = File.ReadAllLines(sourcePath);
            int procedureDivisionLineNumber = Array.FindIndex(lines, line => line.Contains("PROCEDURE DIVISION"));

            for (int i = 0; i < procedureDivisionLineNumber; i++)
            {
                string line = lines[i].Trim().ToUpper();
                if (line.StartsWith("COPY") && !line.StartsWith("*"))
                {
                    string copyStatement = line.Substring(4).Trim().Replace("\"", "").Replace("'", "");
                    foreach (string suffix in new[] { ".CPY", ".CPB", ".CPX", ".DCL" })
                    {
                        int pos = copyStatement.IndexOf(suffix);
                        if (pos > 0)
                        {
                            copyStatement = copyStatement.Substring(0, pos + 4);
                            break;
                        }
                    }

                    string copyFilePrefix = copyStatement.Split('.')[0];
                    if (!ikkecpy.Contains(copyFilePrefix))
                    {
                        string copyFile = Path.Combine(srcPath, copyStatement);
                        if (!File.Exists(copyFile))
                        {
                            copyFile = Path.Combine(cblCpyPath, copyStatement);
                            if (!File.Exists(copyFile))
                            {
                                errorMessages.Add($"Cannot find copy element \"{copyStatement}\" in either {srcPath} or {cblCpyPath}.");
                            }
                        }
                        copyFiles.Add(copyFile.Trim().ToUpper());
                    }
                }
            }

            return copyFiles.Distinct().ToList();
        }

        private void CopyModuleFiles(ModuleInfo moduleInfo)
        {
            string archivePath = Path.Combine(tempPath, "ARC", moduleInfo.ModuleFileSuffix + "ARC", moduleInfo.ModuleFilePrefix);
            Directory.CreateDirectory(archivePath);

            CopyModuleFilesToPath(moduleInfo, archivePath);

            string releasePath = Path.Combine(tempPath, "DEP");
            Directory.CreateDirectory(releasePath);

            CopyModuleFilesToPath(moduleInfo, releasePath);
        }


        private void CopyModuleFilesToPath(ModuleInfo moduleInfo, string deployPath)
        {
            string deployPathSrc = Path.Combine(deployPath, "SRC");
            Directory.CreateDirectory(deployPathSrc);

            if (moduleInfo.ModuleFileSuffix == "CBL")
            {
                string deployPathCbl = Path.Combine(deployPathSrc, "CBL");
                Directory.CreateDirectory(deployPathCbl);

                File.Copy(moduleInfo.Src, Path.Combine(deployPathCbl, moduleInfo.ModuleFileName), true);

                string deployPathCpy = Path.Combine(deployPathCbl, "CPY");
                Directory.CreateDirectory(deployPathCpy);

                foreach (string copyFile in moduleInfo.CopyFiles)
                {
                    File.Copy(copyFile, Path.Combine(deployPathCpy, Path.GetFileName(copyFile)), true);
                }

                File.Copy(moduleInfo.BasePath + ".INT", Path.Combine(deployPath, moduleInfo.ModuleFilePrefix + ".INT"), true);
                File.Copy(moduleInfo.BasePath + ".IDY", Path.Combine(deployPath, moduleInfo.ModuleFilePrefix + ".IDY"), true);
                File.Copy(moduleInfo.BasePath + ".BND", Path.Combine(deployPath, moduleInfo.ModuleFilePrefix + ".BND"), true);

                if (moduleInfo.GsTime.HasValue)
                {
                    File.Copy(moduleInfo.BasePath + ".GS", Path.Combine(deployPath, moduleInfo.ModuleFilePrefix + ".GS"), true);
                    File.Copy(moduleInfo.BasePath + ".GS", Path.Combine(deployPathCbl, "GS", moduleInfo.ModuleFilePrefix + ".GS"), true);
                    ExportImpFileFromGsFile(moduleInfo, deployPathCbl);
                }
            }
            else
            {
                string deployPathCommon = Path.Combine(deployPathSrc, moduleInfo.ModuleFileSuffix);
                Directory.CreateDirectory(deployPathCommon);

                File.Copy(moduleInfo.Src, Path.Combine(deployPathCommon, moduleInfo.ModuleFileName), true);

                if (moduleInfo.ModuleFileSuffix != "SQL")
                {
                    File.Copy(moduleInfo.Src, Path.Combine(deployPath, moduleInfo.ModuleFileName), true);
                }
            }
        }

        private void ExportImpFileFromGsFile(ModuleInfo moduleInfo, string deployPath)
        {
            string deployPathImp = Path.Combine(deployPath, "IMP");
            Directory.CreateDirectory(deployPathImp);

            string exePath = @"C:\Program Files (x86)\Micro Focus\Net Express 5.1\DIALOGSYSTEM\Bin\dswin.exe";
            string impFile = Path.Combine(deployPathImp, moduleInfo.ModuleFilePrefix + ".IMP");
            string gsFile = moduleInfo.BasePath + ".GS";
            string args = $"/e {gsFile} {impFile}";

            ProcessStartInfo psi = new ProcessStartInfo(exePath, args)
            {
                CreateNoWindow = true,
                UseShellExecute = false
            };

            using (Process process = Process.Start(psi))
            {
                if (!process.WaitForExit(15000))
                {
                    process.Kill();
                    Logger.Warn($"DSWIN.EXE process exceeded time limit and was terminated for {moduleInfo.ModuleFileName}");
                }
            }

            if (!File.Exists(impFile))
            {
                Logger.Error($"Failed to export: {impFile}");
            }
        }

        private async Task HandleServiceNow()
        {
            if (deployEnv.Contains("PRD"))
            {
                if (string.IsNullOrEmpty(serviceNowId))
                {
                    do
                    {
                        var snRequests = await GetServiceNowOpenIssuesForUser(serviceNowId);
                        ShowServiceNowData(snRequests);
                        Console.WriteLine("--> Choose from the list or enter a ServiceNow ID to add to the list.");
                        Console.WriteLine("--> If you don't add a ServiceNow ID, a new Change Request will be created automatically.");
                        serviceNowId = Console.ReadLine().Trim().ToUpper();

                        if (int.TryParse(serviceNowId, out int choice))
                        {
                            serviceNowId = snRequests.FirstOrDefault(r => r.Sequence == choice)?.Number;
                            break;
                        }
                        else if (string.IsNullOrEmpty(serviceNowId))
                        {
                            break;
                        }
                    } while (true);
                }

                if (string.IsNullOrEmpty(serviceNowId))
                {
                    serviceNowId = await CreateServiceNowChangeRequest(changeTitle, changeDescription, moduleList);
                    Console.WriteLine($"Created new Change Request: {serviceNowId}");
                }
                else
                {
                    await UpdateServiceNowChangeRequest(changeTitle, changeDescription, moduleList, serviceNowId);
                    Console.WriteLine($"Updated Change Request: {serviceNowId}");
                }

                string servicenow_web_url = $"https://{serviceNowInstance}.service-now.com/nav_to.do?uri=change_request.do?number={serviceNowId}";
                Console.WriteLine($"ServiceNow Change Request URL: {servicenow_web_url}");
            }
        }

        private async Task<List<ServiceNowRequest>> GetServiceNowOpenIssuesForUser(string serviceNowId = null)
        {
            var requests = new List<ServiceNowRequest>();
            string username = Environment.UserName;

            // Get user's sys_id
            string userSysId = await GetUserSysId(username);

            if (string.IsNullOrEmpty(userSysId))
            {
                Logger.Error($"Failed to retrieve sys_id for user: {username}");
                return requests;
            }

            // Get incidents
            var incidents = await GetServiceNowData("incident", userSysId);
            if (incidents != null)
            {
                requests.AddRange(incidents.Select(i => new ServiceNowRequest
                {
                    Type = "Incident",
                    Number = i.number,
                    ShortDescription = i.short_description,
                    Priority = i.priority,
                    State = i.state,
                    StateText = GetStateText("incident", i.state)
                }));
            }

            // Get service requests
            var serviceRequests = await GetServiceNowData("sc_request", userSysId);
            if (serviceRequests != null)
            {
                requests.AddRange(serviceRequests.Select(sr => new ServiceNowRequest
                {
                    Type = "Service Request",
                    Number = sr.number,
                    ShortDescription = sr.short_description,
                    Priority = sr.priority,
                    State = sr.state,
                    StateText = GetStateText("sc_request", sr.state)
                }));
            }

            // Get change requests
            var changeRequests = await GetServiceNowData("change_request", userSysId);
            if (changeRequests != null)
            {
                requests.AddRange(changeRequests.Select(cr => new ServiceNowRequest
                {
                    Type = "Change Request",
                    Number = cr.number,
                    ShortDescription = cr.short_description,
                    Priority = cr.priority,
                    State = cr.state,
                    StateText = GetStateText("change_request", cr.state)
                }));
            }

            // Add sequence numbers
            for (int i = 0; i < requests.Count; i++)
            {
                requests[i].Sequence = i + 1;
            }

            return requests.OrderBy(r => r.Number).ToList();
        }

        private async Task<string> GetUserSysId(string username)
        {
            string url = $"https://{serviceNowInstance}.service-now.com/api/now/table/sys_user?sysparm_query=user_name={username}&sysparm_fields=sys_id&sysparm_limit=1";
            
            try
            {
                HttpResponseMessage response = await httpClient.GetAsync(url);
                response.EnsureSuccessStatusCode();
                string responseBody = await response.Content.ReadAsStringAsync();
                
                using (JsonDocument doc = JsonDocument.Parse(responseBody))
                {
                    JsonElement root = doc.RootElement;
                    JsonElement result = root.GetProperty("result")[0];
                    return result.GetProperty("sys_id").GetString();
                }
            }
            catch (Exception ex)
            {
                Logger.Error($"Error getting user sys_id: {ex.Message}");
                return null;
            }
        }

        private async Task<List<dynamic>> GetServiceNowData(string table, string userSysId)
        {
            string query = table == "change_request" ? $"state<3^assigned_to={userSysId}" : $"assigned_to={userSysId}";
            string url = $"https://{serviceNowInstance}.service-now.com/api/now/table/{table}?sysparm_query={query}&sysparm_fields=number,short_description,priority,state,sys_id";

            try
            {
                HttpResponseMessage response = await httpClient.GetAsync(url);
                response.EnsureSuccessStatusCode();
                string responseBody = await response.Content.ReadAsStringAsync();

                using (JsonDocument doc = JsonDocument.Parse(responseBody))
                {
                    JsonElement root = doc.RootElement;
                    JsonElement result = root.GetProperty("result");
                    return JsonSerializer.Deserialize<List<dynamic>>(result.GetRawText());
                }
            }
            catch (Exception ex)
            {
                Logger.Error($"Error getting ServiceNow data for {table}: {ex.Message}");
                return null;
            }
        }

        private string GetStateText(string table, string state)
        {
            Dictionary<string, Dictionary<string, string>> stateMap = new Dictionary<string, Dictionary<string, string>>
            {
                ["incident"] = new Dictionary<string, string>
                {
                    ["1"] = "New",
                    ["2"] = "In Progress",
                    ["3"] = "On Hold",
                    ["6"] = "Resolved",
                    ["7"] = "Closed"
                },
                ["sc_request"] = new Dictionary<string, string>
                {
                    ["1"] = "Open",
                    ["2"] = "Work in Progress",
                    ["3"] = "Closed Complete",
                    ["4"] = "Closed Incomplete",
                    ["5"] = "Closed Skipped"
                },
                ["change_request"] = new Dictionary<string, string>
                {
                    ["1"] = "Open",
                    ["2"] = "Assess",
                    ["3"] = "Authorize",
                    ["4"] = "Scheduled",
                    ["5"] = "Implement",
                    ["6"] = "Review",
                    ["7"] = "Closed"
                }
            };

            if (stateMap.TryGetValue(table, out var tableStates) && tableStates.TryGetValue(state, out var stateText))
            {
                return stateText;
            }

            return "Unknown";
        }

        private void ShowServiceNowData(List<ServiceNowRequest> requests)
        {
            Console.WriteLine("| {0,-5} | {1,-12} | {2,-15} | {3,-50} | {4,-8} | {5,-15} |", "Valg", "ServiceNowId", "Type", "Beskrivelse", "Prioritet", "Status");
            Console.WriteLine(new string('-', 120));

            foreach (var request in requests)
            {
                Console.WriteLine("| {0,-5} | {1,-12} | {2,-15} | {3,-50} | {4,-8} | {5,-15} |",
                    request.Sequence,
                    request.Number,
                    request.Type,
                    request.ShortDescription.Length > 47 ? request.ShortDescription.Substring(0, 47) + "..." : request.ShortDescription,
                    request.Priority,
                    request.StateText);
            }
        }

        private async Task<string> CreateServiceNowChangeRequest(string changeTitle, string changeDescription, List<string> moduleList)
        {
            string url = $"https://{serviceNowInstance}.service-now.com/api/now/table/change_request";

            var changeRequest = new
            {
                short_description = changeTitle,
                description = changeDescription,
                type = "standard",
                category = "Software",
                impact = "3",
                urgency = immediateDeploy ? "2" : "3",
                risk = "3",
                assignment_group = "Utvikling FK-meny",
                requested_by = Environment.UserName,
                start_date = DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"),
                end_date = immediateDeploy ? DateTime.UtcNow.AddHours(1).ToString("yyyy-MM-dd HH:mm:ss") : DateTime.UtcNow.AddDays(1).ToString("yyyy-MM-dd HH:mm:ss"),
                justification = $"Endring av følgende moduler: {string.Join(", ", moduleList)}",
                implementation_plan = "Endringen er gjennomført og testet.",
                test_plan = "Utført egentest og tester i testmiljø(er)",
                backout_plan = "Hvis noe går galt, legges tidligere versjoner av filene tilbake."
            };

            var json = JsonSerializer.Serialize(changeRequest);
            var content = new StringContent(json, System.Text.Encoding.UTF8, "application/json");

            try
            {
                HttpResponseMessage response = await httpClient.PostAsync(url, content);
                response.EnsureSuccessStatusCode();
                string responseBody = await response.Content.ReadAsStringAsync();

                using (JsonDocument doc = JsonDocument.Parse(responseBody))
                {
                    JsonElement root = doc.RootElement;
                    JsonElement result = root.GetProperty("result");
                    return result.GetProperty("number").GetString();
                }
            }
            catch (Exception ex)
            {
                Logger.Error($"Error creating ServiceNow Change Request: {ex.Message}");
                return null;
            }
        }

        private async Task UpdateServiceNowChangeRequest(string changeTitle, string changeDescription, List<string> moduleList, string serviceNowId)
        {
            string url = $"https://{serviceNowInstance}.service-now.com/api/now/table/change_request?sysparm_query=number={serviceNowId}";

            var updateData = new
            {
                short_description = changeTitle,
                description = changeDescription,
                work_notes = $"Updated modules: {string.Join(", ", moduleList)}",
                state = immediateDeploy ? "5" : "4" // 5 for Implement, 4 for Scheduled
            };

            var json = JsonSerializer.Serialize(updateData);
            var content = new StringContent(json, System.Text.Encoding.UTF8, "application/json");

            try
            {
                HttpResponseMessage response = await httpClient.PutAsync(url, content);
                response.EnsureSuccessStatusCode();
            }
            catch (Exception ex)
            {
                Logger.Error($"Error updating ServiceNow Change Request: {ex.Message}");
            }
        }

        private void ArchiveAndDeploy()
        {
            string date = DateTime.Now.ToString("yyyyMMdd");
            string time = DateTime.Now.ToString("HHmmss");

            foreach (string env in deployEnv)
            {
                string stackPathEnv = Path.Combine(stackPath, env);
                string stackPathEnvDll = Path.Combine(stackPathEnv, "DLL");
                string stackPathEnvBnd = Path.Combine(stackPathEnv, "BND");

                Directory.CreateDirectory(stackPathEnv);
                Directory.CreateDirectory(stackPathEnvDll);
                Directory.CreateDirectory(stackPathEnvBnd);

                ZipAndArchiveFiles(env, date, time);
                MoveFilesToStackFolder(env);

                if (immediateDeploy)
                {
                    DeployFiles(env);
                }
            }
        }

        private void ZipAndArchiveFiles(string deployEnvItem, string date, string time)
        {
            foreach (var fileObj in fileObjList)
            {
                string folder = Path.Combine(tempPath, "ARC", fileObj.MainModule.ModuleFileSuffix + "ARC", fileObj.MainModule.ModuleFilePrefix);
                string zipFileName = $"{fileObj.MainModule.ModuleFileName}_{date}_{time}_TO_{deployEnvItem}";
                string archivePathModule = Path.Combine(archivePath, fileObj.MainModule.ModuleFileSuffix + "ARC", fileObj.MainModule.ModuleFilePrefix);
                string zipFile = Path.Combine(archivePathModule, zipFileName + ".ZIP");

                Directory.CreateDirectory(archivePathModule);

                if (File.Exists(zipFile))
                {
                    File.Delete(zipFile);
                }

                try
                {
                    ZipFile.CreateFromDirectory(folder, zipFile);
                }
                catch (Exception ex)
                {
                    Logger.Error($"Exception occurred while zipping files: {ex.Message}");
                }
                finally
                {
                    Directory.Delete(folder, true);
                }
            }
        }

        private void MoveFilesToStackFolder(string deployEnvItem)
        {
            string tempDeployPath = Path.Combine(tempPath, "DEP");
            string stackPathEnv = Path.Combine(stackPath, deployEnvItem);

            foreach (string dirPath in Directory.GetDirectories(tempDeployPath, "*", SearchOption.AllDirectories))
            {
                Directory.CreateDirectory(dirPath.Replace(tempDeployPath, stackPathEnv));
            }

            foreach (string newPath in Directory.GetFiles(tempDeployPath, "*.*", SearchOption.AllDirectories))
            {
                File.Copy(newPath, newPath.Replace(tempDeployPath, stackPathEnv), true);
            }
        }

        private void DeployFiles(string deployEnvItem)
        {
            string sourceDir = Path.Combine(stackPath, deployEnvItem);
            string targetDir = prodExecPath;

            try
            {
                // Copy all files from sourceDir to targetDir
                foreach (string dirPath in Directory.GetDirectories(sourceDir, "*", SearchOption.AllDirectories))
                {
                    Directory.CreateDirectory(dirPath.Replace(sourceDir, targetDir));
                }

                foreach (string newPath in Directory.GetFiles(sourceDir, "*.*", SearchOption.AllDirectories))
                {
                    File.Copy(newPath, newPath.Replace(sourceDir, targetDir), true);
                }

                Logger.Info($"Immediate deployment to {deployEnvItem} completed successfully.");
            }
            catch (Exception ex)
            {
                Logger.Error($"Error during immediate deployment to {deployEnvItem}: {ex.Message}");
                // Consider implementing a rollback mechanism here
            }
        }
    }

    class ModuleInfo
    {
        public string ModuleFileName { get; set; }
        public string ModuleFilePrefix { get; set; }
        public string ModuleFileSuffix { get; set; }
        public string BasePath { get; set; }
        public string Src { get; set; }
        public DateTime SrcTime { get; set; }
        public DateTime? IntTime { get; set; }
        public DateTime? IdyTime { get; set; }
        public DateTime? BndTime { get; set; }
        public DateTime? GsTime { get; set; }
        public bool UseSql { get; set; }
        public List<string> CopyFiles { get; set; }
    }

    class ServiceNowRequest
    {
        public int Sequence { get; set; }
        public string Number { get; set; }
        public string Type { get; set; }
        public string ShortDescription { get; set; }
        public string Priority { get; set; }
        public string State { get; set; }
        public string StateText { get; set; }
    }

    class FileObj
    {
        public string Name { get; set; }
        public ModuleInfo MainModule { get; set; }
        public ModuleInfo ValidationModule { get; set; }
    }
}