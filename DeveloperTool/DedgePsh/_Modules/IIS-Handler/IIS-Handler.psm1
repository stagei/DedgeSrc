# ═══════════════════════════════════════════════════════════════════════════════
# IIS-Handler
# ═══════════════════════════════════════════════════════════════════════════════

$modulesToImport = @("GlobalFunctions", "Infrastructure")
foreach ($moduleName in $modulesToImport) {
    $loadedModule = Get-Module -Name $moduleName
    if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
        Import-Module $moduleName -Force
    }
    else {
        Write-Host "Module $moduleName already loaded" -ForegroundColor Yellow
    }
} 
  
function Write-Check {
    param(
        [string]$Name,
        [ValidateSet("PASS", "WARN", "FAIL", "INFO")]
        [string]$Result,
        [string]$Detail = ""
    )
    $icon = switch ($Result) {
        "PASS" { "[PASS]"; $script:PassCount++ }
        "WARN" { "[WARN]"; $script:WarnCount++ }
        "FAIL" { "[FAIL]"; $script:FailCount++ }
        "INFO" { "[INFO]" }
    }
    $level = switch ($Result) {
        "PASS" { "INFO" }
        "WARN" { "WARN" }
        "FAIL" { "ERROR" }
        "INFO" { "INFO" }
    }
    $msg = "  $icon $Name"
    if ($Detail) { $msg += " -- $Detail" }
    Write-LogMessage $msg -Level $level
}

function Write-Suggestion {
    param([string]$Text)
    Write-LogMessage "         -> $Text" -Level WARN
}

# ═══════════════════════════════════════════════════════════════════════════════
# DIAGNOSE ONE APP
# ═══════════════════════════════════════════════════════════════════════════════
function Test-IISApp {
    param(
        [string]$AppName,
        [string]$Parent,
        [string]$VPath
    )

    Write-LogMessage "" -Level INFO
    Write-LogMessage "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
    Write-LogMessage "Diagnosing: $AppName (virtual path: $VPath)" -Level INFO
    Write-LogMessage "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO

    $appId = "$Parent$VPath"

    # ── 1. Virtual app exists? ────────────────────────────────────────────────
    $appCheck = & $appcmd list app "$appId" 2>&1 | Out-String
    if ($appCheck -notmatch 'APP "') {
        Write-Check "Virtual app exists" -Result FAIL -Detail "'$appId' not found in IIS"
        Write-Suggestion "Run: .\IIS-DeployApp.ps1 -SiteName $AppName"
        return
    }
    Write-Check "Virtual app exists" -Result PASS -Detail $appId

    # ── 2. Get app pool name ──────────────────────────────────────────────────
    $poolName = ""
    $appInfo = & $appcmd list app "$appId" /text:* 2>&1 | Out-String
    if ($appInfo -match 'APPPOOL\.NAME:"([^"]+)"') { $poolName = $matches[1] }

    if ([string]::IsNullOrWhiteSpace($poolName)) {
        Write-Check "App pool assigned" -Result FAIL -Detail "No app pool found for $appId"
        return
    }
    Write-Check "App pool assigned" -Result PASS -Detail $poolName

    # ── 3. App pool state ─────────────────────────────────────────────────────
    $poolCheck = & $appcmd list apppool "$poolName" 2>&1 | Out-String
    if ($poolCheck -notmatch 'APPPOOL "') {
        Write-Check "App pool exists" -Result FAIL -Detail "'$poolName' not found"
        Write-Suggestion "Run: .\IIS-DeployApp.ps1 -SiteName $AppName"
        return
    }

    $poolState = (& $appcmd list apppool "$poolName" /text:state 2>&1).Trim()
    if ($poolState -eq "Started") {
        Write-Check "App pool running" -Result PASS
    }
    else {
        Write-Check "App pool running" -Result FAIL -Detail "State: $poolState"
        Write-Suggestion "Run: $appcmd start apppool `"$poolName`""

        # Check for rapid-fail protection (too many crashes)
        $poolConfig = & $appcmd list apppool "$poolName" /text:* 2>&1 | Out-String
        if ($poolConfig -match 'failure\.rapidFailProtection.*true') {
            Write-Check "Rapid-fail protection" -Result WARN -Detail "App pool may have been auto-stopped after repeated crashes"
            Write-Suggestion "Check Event Log for crash details, then: $appcmd start apppool `"$poolName`""
        }
    }

    # ── 3b. Shared app pool check (500.35 prevention) ─────────────────────
    # ASP.NET Core InProcess does not allow multiple apps in the same app pool.
    $allAppsInPool = @(& $appcmd list app /apppool.name:"$poolName" 2>&1 | Out-String -Stream | Where-Object { $_ -match '^APP "' })
    if ($allAppsInPool.Count -gt 1) {
        $appNames = $allAppsInPool | ForEach-Object {
            if ($_ -match 'APP "([^"]+)"') { $matches[1] }
        }
        Write-Check "App pool exclusive" -Result FAIL -Detail "Pool '$($poolName)' is shared by $($allAppsInPool.Count) apps: $($appNames -join ', ')"
        Write-Suggestion "ASP.NET Core InProcess requires a dedicated app pool per app (HTTP 500.35)"
        Write-Suggestion "Give each app its own pool, or redeploy with: .\IIS-DeployApp.ps1 -SiteName $($AppName)"
    }
    else {
        Write-Check "App pool exclusive" -Result PASS -Detail "Pool '$($poolName)' has only this app"
    }

    # ── 4. Physical path ──────────────────────────────────────────────────────
    $physPath = ""
    $vdirCheck = & $appcmd list vdir "$appId/" 2>&1 | Out-String
    if ($vdirCheck -match 'physicalPath:([^\s\)]+)') { $physPath = $matches[1] }

    if ([string]::IsNullOrWhiteSpace($physPath)) {
        Write-Check "Physical path configured" -Result FAIL -Detail "No vdir/physical path found"
        return
    }

    if (Test-Path $physPath) {
        $fileCount = (Get-ChildItem $physPath -File -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Check "Physical path exists" -Result PASS -Detail "$physPath ($fileCount files)"
    }
    else {
        Write-Check "Physical path exists" -Result FAIL -Detail "$physPath does NOT exist"
        Write-Suggestion "Deploy the app files first, or fix PhysicalPath in the deploy profile"
        return
    }

    # ── 5. Permissions ────────────────────────────────────────────────────────
    $identity = "IIS AppPool\$poolName"
    try {
        $acl = Get-Acl $physPath
        $hasAccess = $acl.Access | Where-Object {
            $_.IdentityReference -match [regex]::Escape($poolName) -or
            $_.IdentityReference -match "IIS_IUSRS" -or
            $_.IdentityReference -match "Everyone" -or
            $_.IdentityReference -match "BUILTIN\\Users"
        }
        if ($hasAccess) {
            Write-Check "Folder permissions" -Result PASS -Detail "App pool identity has access"
        }
        else {
            Write-Check "Folder permissions" -Result WARN -Detail "No explicit rule for '$identity' found"
            Write-Suggestion "icacls `"$physPath`" /grant `"$($identity):(OI)(CI)RX`" /T"
        }
    }
    catch {
        Write-Check "Folder permissions" -Result WARN -Detail "Could not read ACL: $($_.Exception.Message)"
    }

    # ── 6. web.config ─────────────────────────────────────────────────────────
    $webConfig = Join-Path $physPath "web.config"
    if (Test-Path $webConfig) {
        Write-Check "web.config exists" -Result PASS

        # Dump the full web.config content for inspection
        Write-LogMessage "" -Level INFO
        Write-LogMessage "  ── web.config content ($webConfig) ──" -Level INFO
        $webConfigContent = Get-Content $webConfig -Raw -ErrorAction SilentlyContinue
        Write-LogMessage $webConfigContent -Level DEBUG
        Write-LogMessage "  ── end web.config ──" -Level INFO
        Write-LogMessage "" -Level INFO

        try {
            [xml]$xml = Get-Content $webConfig -Raw -ErrorAction Stop
            Write-Check "web.config valid XML" -Result PASS

            # ── Auto-analyze web.config structure ──────────────────────────────

            # Check for handlers section
            $handlers = $xml.SelectNodes("//handlers/add")
            if ($handlers -and $handlers.Count -gt 0) {
                foreach ($h in $handlers) {
                    $hName = $h.GetAttribute("name")
                    $hModules = $h.GetAttribute("modules")
                    $hPath = $h.GetAttribute("path")
                    Write-Check "Handler: $hName" -Result INFO -Detail "modules=$hModules, path=$hPath"
                }

                # Check for duplicate handler names
                $handlerNames = @($handlers | ForEach-Object { $_.GetAttribute("name") })
                $duplicates = $handlerNames | Group-Object | Where-Object { $_.Count -gt 1 }
                if ($duplicates) {
                    foreach ($dup in $duplicates) {
                        Write-Check "Duplicate handler" -Result WARN -Detail "'$($dup.Name)' appears $($dup.Count) times"
                        Write-Suggestion "Remove duplicate handler entries from web.config"
                    }
                }
            }

            # Check inheritInChildApplications
            $locationNode = $xml.SelectSingleNode("//location")
            if ($locationNode) {
                $inherit = $locationNode.GetAttribute("inheritInChildApplications")
                if ($inherit -eq "false") {
                    Write-Check "inheritInChildApplications" -Result PASS -Detail "Disabled (prevents conflicts with child apps)"
                }
                else {
                    Write-Check "inheritInChildApplications" -Result INFO -Detail "Enabled or not set"
                }
            }

            # Check for AspNetCore handler
            $aspNetCoreNode = $xml.SelectSingleNode("//aspNetCore")
            if ($aspNetCoreNode) {
                $processPath = $aspNetCoreNode.GetAttribute("processPath")
                $arguments = $aspNetCoreNode.GetAttribute("arguments")
                $hostingModel = $aspNetCoreNode.GetAttribute("hostingModel")
                $stdoutLog = $aspNetCoreNode.GetAttribute("stdoutLogEnabled")
                $stdoutLogFile = $aspNetCoreNode.GetAttribute("stdoutLogFile")

                Write-Check "ASP.NET Core handler" -Result INFO -Detail "processPath=$processPath, arguments=$arguments, hostingModel=$hostingModel"

                # Validate hostingModel
                if ($hostingModel -eq "inprocess") {
                    Write-Check "Hosting model" -Result PASS -Detail "InProcess (recommended for performance)"
                }
                elseif ($hostingModel -eq "outofprocess") {
                    Write-Check "Hosting model" -Result INFO -Detail "OutOfProcess (runs as separate Kestrel process)"
                }
                elseif ([string]::IsNullOrWhiteSpace($hostingModel)) {
                    Write-Check "Hosting model" -Result WARN -Detail "Not specified -- defaults to OutOfProcess"
                    Write-Suggestion "Add hostingModel=`"inprocess`" to <aspNetCore> for better performance"
                }

                # Determine the executable/DLL to check
                # Self-contained: processPath=.\MyApp.exe, arguments empty
                # Framework-dependent via dotnet: processPath=dotnet, arguments=.\MyApp.dll
                $appBinary = ""
                if (-not [string]::IsNullOrWhiteSpace($arguments)) {
                    $appBinary = ($arguments -replace '^\.\\', '').Split(' ')[0]
                }
                elseif ($processPath -ne "dotnet" -and $processPath -match '\\?([^\\]+\.exe)$') {
                    $appBinary = $matches[1]
                }
                elseif ($processPath -match '^\.\\.+') {
                    $appBinary = $processPath -replace '^\.\\', ''
                }

                if (-not [string]::IsNullOrWhiteSpace($appBinary)) {
                    $binaryPath = Join-Path $physPath $appBinary
                    if (Test-Path $binaryPath) {
                        $binaryInfo = Get-Item $binaryPath
                        $binarySize = "{0:N0} KB" -f ($binaryInfo.Length / 1KB)
                        $binaryDate = $binaryInfo.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                        Write-Check "Application binary" -Result PASS -Detail "$appBinary ($binarySize, $binaryDate)"
                    }
                    else {
                        Write-Check "Application binary" -Result FAIL -Detail "$appBinary not found at $binaryPath"
                        Write-Suggestion "Re-deploy the app: .\IIS-DeployApp.ps1 -SiteName $AppName"
                    }
                }

                # Check stdout logging
                if ($stdoutLog -eq "true") {
                    Write-Check "stdout logging" -Result PASS -Detail "Enabled"
                }
                else {
                    Write-Check "stdout logging" -Result WARN -Detail "Disabled -- enable to see startup errors"
                    Write-Suggestion "Set stdoutLogEnabled=`"true`" in web.config"
                }

                # Validate stdout log path
                if (-not [string]::IsNullOrWhiteSpace($stdoutLogFile)) {
                    $logFolder = Split-Path (Join-Path $physPath $stdoutLogFile) -Parent
                    if (Test-Path $logFolder) {
                        Write-Check "stdout log path" -Result PASS -Detail "$stdoutLogFile -> $logFolder"
                    }
                    else {
                        Write-Check "stdout log path" -Result FAIL -Detail "Directory '$logFolder' does not exist"
                        Write-Suggestion "Create: New-Item -ItemType Directory -Path '$logFolder' -Force"
                    }
                }

                # Check for environment variables in web.config
                $envVarNodes = $xml.SelectNodes("//aspNetCore/environmentVariables/environmentVariable")
                if ($envVarNodes -and $envVarNodes.Count -gt 0) {
                    Write-LogMessage "" -Level INFO
                    Write-LogMessage "  Environment variables in web.config:" -Level INFO
                    foreach ($envNode in $envVarNodes) {
                        $envName = $envNode.GetAttribute("name")
                        $envValue = $envNode.GetAttribute("value")
                        # Regex: mask sensitive env var values
                        # (?i)              - case-insensitive
                        # (password|...)    - match any of these sensitive keywords
                        if ($envName -match "(?i)(password|secret|key|token|connectionstring)") {
                            $envValue = "***MASKED***"
                        }
                        Write-LogMessage "         $($envName) = $($envValue)" -Level DEBUG
                    }

                    # Check ASPNETCORE_ENVIRONMENT specifically
                    $aspEnvNode = $envVarNodes | Where-Object { $_.GetAttribute("name") -eq "ASPNETCORE_ENVIRONMENT" }
                    if ($aspEnvNode) {
                        $aspEnvVal = $aspEnvNode.GetAttribute("value")
                        if ($aspEnvVal -eq "Production") {
                            Write-Check "ASPNETCORE_ENVIRONMENT (web.config)" -Result PASS -Detail $aspEnvVal
                        }
                        elseif ($aspEnvVal -eq "Development") {
                            Write-Check "ASPNETCORE_ENVIRONMENT (web.config)" -Result WARN -Detail "$aspEnvVal (not recommended for production)"
                        }
                        else {
                            Write-Check "ASPNETCORE_ENVIRONMENT (web.config)" -Result INFO -Detail $aspEnvVal
                        }
                    }
                }

                # ── 6b. runtimeconfig.json ─────────────────────────────────────
                # Find the runtimeconfig.json to determine target framework and deployment model
                $runtimeConfigs = Get-ChildItem $physPath -Filter "*.runtimeconfig.json" -File -ErrorAction SilentlyContinue
                if ($runtimeConfigs) {
                    $rcFile = $runtimeConfigs | Select-Object -First 1
                    try {
                        $rcJson = Get-Content $rcFile.FullName -Raw | ConvertFrom-Json
                        $rcFramework = $rcJson.runtimeOptions.framework
                        $rcTfm = $rcJson.runtimeOptions.tfm

                        if ($rcFramework) {
                            $fwName = $rcFramework.name
                            $fwVersion = $rcFramework.version
                            Write-Check "runtimeconfig.json" -Result INFO -Detail "$($rcFile.Name): $fwName $fwVersion (tfm: $rcTfm)"

                            # Check if this is self-contained (has coreclr.dll bundled)
                            $coreclrPath = Join-Path $physPath "coreclr.dll"
                            if (Test-Path $coreclrPath) {
                                Write-Check "Deployment model" -Result INFO -Detail "Self-contained (coreclr.dll bundled)"
                            }
                            else {
                                Write-Check "Deployment model" -Result INFO -Detail "Framework-dependent (requires shared runtime)"

                                # Verify required runtimes are installed
                                $runtimes = & dotnet --list-runtimes 2>&1 | Out-String

                                # Check base runtime (Microsoft.NETCore.App)
                                if ($fwName -eq "Microsoft.NETCore.App") {
                                    $majorMinor = ($fwVersion -split '\.')[0..1] -join '\.'
                                    # Regex: match version like 10.0.x
                                    # ^                 - start of line
                                    # Microsoft\.NETCore\.App - literal framework name
                                    # \s+               - whitespace
                                    # <majorMinor>      - e.g. 10\.0
                                    # \.\d+             - patch version
                                    if ($runtimes -match "Microsoft\.NETCore\.App\s+$majorMinor\.\d+") {
                                        $matchedLine = ($runtimes -split "`n" | Where-Object { $_ -match "Microsoft\.NETCore\.App\s+$majorMinor\.\d+" } | Select-Object -Last 1).Trim()
                                        Write-Check "Base runtime ($fwName)" -Result PASS -Detail $matchedLine
                                    }
                                    else {
                                        Write-Check "Base runtime ($fwName)" -Result FAIL -Detail "Version $fwVersion required but not installed"
                                        Write-Suggestion "Install .NET $($($fwVersion -split '\.')[0..1] -join '.') Hosting Bundle from https://dotnet.microsoft.com/download/dotnet"
                                    }
                                }

                                # Also check ASP.NET Core runtime
                                $aspMajorMinor = ($fwVersion -split '\.')[0..1] -join '\.'
                                if ($runtimes -match "Microsoft\.AspNetCore\.App\s+$aspMajorMinor\.\d+") {
                                    $matchedLine = ($runtimes -split "`n" | Where-Object { $_ -match "Microsoft\.AspNetCore\.App\s+$aspMajorMinor\.\d+" } | Select-Object -Last 1).Trim()
                                    Write-Check "ASP.NET Core runtime" -Result PASS -Detail $matchedLine
                                }
                                else {
                                    Write-Check "ASP.NET Core runtime" -Result FAIL -Detail "ASP.NET Core $aspMajorMinor.x required but not installed"
                                    Write-Suggestion "Install .NET $aspMajorMinor Hosting Bundle"
                                }
                            }

                            # Check for additional frameworks (e.g. Microsoft.AspNetCore.App)
                            $additionalFrameworks = $rcJson.runtimeOptions.frameworks
                            if ($additionalFrameworks) {
                                foreach ($addFw in $additionalFrameworks) {
                                    $addName = $addFw.name
                                    $addVer = $addFw.version
                                    $addMajorMinor = ($addVer -split '\.')[0..1] -join '\.'
                                    if ($runtimes -match "$([regex]::Escape($addName))\s+$addMajorMinor\.\d+") {
                                        $matchedLine = ($runtimes -split "`n" | Where-Object { $_ -match "$([regex]::Escape($addName))\s+$addMajorMinor\.\d+" } | Select-Object -Last 1).Trim()
                                        Write-Check "Runtime ($addName)" -Result PASS -Detail $matchedLine
                                    }
                                    else {
                                        Write-Check "Runtime ($addName)" -Result FAIL -Detail "$addName $addVer required but not installed"
                                        Write-Suggestion "Install .NET $addMajorMinor Hosting Bundle"
                                    }
                                }
                            }
                        }
                        else {
                            Write-Check "runtimeconfig.json" -Result WARN -Detail "No framework info found in $($rcFile.Name)"
                        }
                    }
                    catch {
                        Write-Check "runtimeconfig.json" -Result WARN -Detail "Could not parse: $($_.Exception.Message)"
                    }
                }
                else {
                    Write-Check "runtimeconfig.json" -Result WARN -Detail "Not found -- cannot determine target framework"
                }

                # ── 6c. appsettings.json ───────────────────────────────────────
                $appSettings = Join-Path $physPath "appsettings.json"
                if (Test-Path $appSettings) {
                    Write-Check "appsettings.json" -Result PASS
                    # Check for environment-specific config
                    $envSettings = Join-Path $physPath "appsettings.Production.json"
                    $envSettingsDev = Join-Path $physPath "appsettings.Development.json"
                    if (Test-Path $envSettings) {
                        Write-Check "appsettings.Production.json" -Result INFO -Detail "Present"
                    }
                    elseif (Test-Path $envSettingsDev) {
                        Write-Check "appsettings config" -Result WARN -Detail "Only Development config found (no Production)"
                    }
                }
                else {
                    Write-Check "appsettings.json" -Result WARN -Detail "Missing -- app may fail if it expects configuration"
                    Write-Suggestion "Deploy appsettings.json to $physPath"
                }
            }
            else {
                Write-Check "ASP.NET Core handler" -Result INFO -Detail "Not an ASP.NET Core app (static site)"
            }

            # ── 6d. Additional web.config analysis ────────────────────────────

            # Check httpErrors configuration
            $httpErrors = $xml.SelectSingleNode("//httpErrors")
            if ($httpErrors) {
                $errMode = $httpErrors.GetAttribute("errorMode")
                $existingResponse = $httpErrors.GetAttribute("existingResponse")
                Write-Check "httpErrors" -Result INFO -Detail "errorMode=$errMode, existingResponse=$existingResponse"

                $customErrors = $xml.SelectNodes("//httpErrors/error")
                if ($customErrors -and $customErrors.Count -gt 0) {
                    foreach ($ce in $customErrors) {
                        $statusCode = $ce.GetAttribute("statusCode")
                        $responseMode = $ce.GetAttribute("responseMode")
                        $cePath = $ce.GetAttribute("path")
                        Write-LogMessage "         Custom error: $statusCode -> $responseMode ($cePath)" -Level DEBUG
                    }
                }
            }

            # Check URL rewrite rules
            $rewriteRules = $xml.SelectNodes("//rewrite/rules/rule")
            if ($rewriteRules -and $rewriteRules.Count -gt 0) {
                Write-Check "URL Rewrite rules" -Result INFO -Detail "$($rewriteRules.Count) rule(s) configured"
                foreach ($rule in $rewriteRules) {
                    $ruleName = $rule.GetAttribute("name")
                    $matchUrl = $rule.SelectSingleNode("match")
                    $matchPattern = if ($matchUrl) { $matchUrl.GetAttribute("url") } else { "N/A" }
                    Write-LogMessage "         Rule: $ruleName (pattern: $matchPattern)" -Level DEBUG
                }
            }

            # Check static content / MIME types
            $staticContent = $xml.SelectNodes("//staticContent/mimeMap")
            if ($staticContent -and $staticContent.Count -gt 0) {
                Write-Check "Static content MIME types" -Result INFO -Detail "$($staticContent.Count) custom MIME mapping(s)"
                foreach ($mime in $staticContent) {
                    $ext = $mime.GetAttribute("fileExtension")
                    $mimeType = $mime.GetAttribute("mimeType")
                    Write-LogMessage "         $ext -> $mimeType" -Level DEBUG
                }
            }

            # Check CORS configuration (if present)
            $corsNode = $xml.SelectSingleNode("//cors")
            if ($corsNode) {
                Write-Check "CORS" -Result INFO -Detail "CORS configuration found in web.config"
            }

            # Check for modules section
            $modules = $xml.SelectNodes("//modules/add")
            if ($modules -and $modules.Count -gt 0) {
                Write-Check "Modules" -Result INFO -Detail "$($modules.Count) module(s) configured"
                foreach ($mod in $modules) {
                    $modName = $mod.GetAttribute("name")
                    $modType = $mod.GetAttribute("type")
                    Write-LogMessage "         Module: $modName ($modType)" -Level DEBUG
                }
            }

            # Check for security/authorization settings
            $authNode = $xml.SelectSingleNode("//security/authentication")
            if ($authNode) {
                $anonAuth = $xml.SelectSingleNode("//security/authentication/anonymousAuthentication")
                $winAuth = $xml.SelectSingleNode("//security/authentication/windowsAuthentication")
                if ($anonAuth) {
                    $anonEnabled = $anonAuth.GetAttribute("enabled")
                    Write-Check "Anonymous authentication" -Result INFO -Detail "enabled=$anonEnabled"
                }
                if ($winAuth) {
                    $winEnabled = $winAuth.GetAttribute("enabled")
                    Write-Check "Windows authentication" -Result INFO -Detail "enabled=$winEnabled"
                }
            }

            # Check for defaultDocument section
            $defaultDoc = $xml.SelectSingleNode("//defaultDocument")
            if ($defaultDoc) {
                $docFiles = $xml.SelectNodes("//defaultDocument/files/add")
                if ($docFiles -and $docFiles.Count -gt 0) {
                    $docList = @($docFiles | ForEach-Object { $_.GetAttribute("value") }) -join ", "
                    Write-Check "Default documents" -Result INFO -Detail $docList
                }
            }

        }
        catch {
            Write-Check "web.config valid XML" -Result FAIL -Detail $_.Exception.Message
            Write-Suggestion "Fix the XML syntax in $webConfig"
        }
    }
    else {
        Write-Check "web.config exists" -Result WARN -Detail "Missing -- IIS will use defaults"
    }

    # ── 7. .NET Runtime & IIS Module (for ASP.NET Core apps) ─────────────────
    if ($aspNetCoreNode) {
        $dotnetPath = Get-Command "dotnet" -ErrorAction SilentlyContinue
        if ($dotnetPath) {
            $dotnetVersion = & dotnet --version 2>&1
            Write-Check ".NET CLI" -Result PASS -Detail "dotnet v$dotnetVersion at $($dotnetPath.Source)"

            # List all installed runtimes for reference
            Write-LogMessage "" -Level INFO
            Write-LogMessage "  Installed .NET runtimes:" -Level INFO
            $allRuntimes = & dotnet --list-runtimes 2>&1
            foreach ($rt in $allRuntimes) {
                $rtTrimmed = "$rt".Trim()
                if ($rtTrimmed) {
                    Write-LogMessage "         $rtTrimmed" -Level DEBUG
                }
            }
        }
        else {
            Write-Check ".NET CLI" -Result FAIL -Detail "dotnet command not found in PATH"
            Write-Suggestion "Install .NET SDK or the ASP.NET Core Hosting Bundle"
        }

        # Check ASP.NET Core IIS Module (aspnetcorev2.dll) — installs to Program Files, not inetsrv
        $ancmCandidates = @(
            "$env:ProgramFiles\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll",
            "${env:ProgramFiles(x86)}\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll",
            "$($env:SystemRoot)\System32\inetsrv\aspnetcorev2.dll"
        )
        $modulePath = $ancmCandidates | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1
        if ($modulePath) {
            $moduleVersion = (Get-Item $modulePath).VersionInfo.FileVersion
            Write-Check "ASP.NET Core IIS Module V2" -Result PASS -Detail "v$($moduleVersion) ($($modulePath))"
        }
        else {
            Write-Check "ASP.NET Core IIS Module V2" -Result FAIL -Detail "aspnetcorev2.dll not found in any known location"
            Write-Suggestion "Install the ASP.NET Core Hosting Bundle (includes the IIS module + runtimes)"
        }

        # App pool bitness check (32-bit pool can't load 64-bit app and vice versa)
        $enable32bit = & $appcmd list apppool "$poolName" /text:enable32BitAppOnWin64 2>&1
        $enable32bit = "$enable32bit".Trim()
        if ($enable32bit -eq "true") {
            Write-Check "App pool bitness" -Result WARN -Detail "32-bit mode enabled (enable32BitAppOnWin64=true)"
            Write-Suggestion "If the app is 64-bit, disable 32-bit mode: $appcmd set apppool `"$poolName`" /enable32BitAppOnWin64:false"
        }
        else {
            Write-Check "App pool bitness" -Result PASS -Detail "64-bit mode"
        }

        # ASPNETCORE_ENVIRONMENT variable check
        $envVarCheck = & $appcmd list apppool "$poolName" /text:* 2>&1 | Out-String
        if ($envVarCheck -match 'ASPNETCORE_ENVIRONMENT') {
            Write-Check "ASPNETCORE_ENVIRONMENT" -Result INFO -Detail "Set in app pool config"
        }
        else {
            $sysEnv = [System.Environment]::GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT", "Machine")
            if ($sysEnv) {
                Write-Check "ASPNETCORE_ENVIRONMENT" -Result INFO -Detail "$sysEnv (system env var)"
            }
            else {
                Write-Check "ASPNETCORE_ENVIRONMENT" -Result INFO -Detail "Not set (defaults to Production)"
            }
        }
    }

    # ── 8. stdout logs ────────────────────────────────────────────────────────
    $logsDir = Join-Path $physPath "logs"
    if (Test-Path $logsDir) {
        $logFiles = Get-ChildItem $logsDir -Filter "stdout*" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 3
        if ($logFiles) {
            Write-Check "stdout log files" -Result INFO -Detail "$($logFiles.Count) recent file(s) in $logsDir"
            foreach ($lf in $logFiles) {
                Write-LogMessage "         $($lf.Name) ($($lf.Length) bytes, $($lf.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')))" -Level DEBUG

                # Read last 30 lines looking for errors
                $content = Get-Content $lf.FullName -Tail 30 -ErrorAction SilentlyContinue
                $errors = $content | Where-Object {
                    $_ -match "(?i)(exception|error|fail|critical|unhandled|fatal|crash)" -and
                    $_ -notmatch "(?i)(no error|error count: 0|errorpage)"
                }
                if ($errors) {
                    Write-Check "stdout errors ($($lf.Name))" -Result FAIL -Detail "Found $($errors.Count) error line(s)"
                    foreach ($err in ($errors | Select-Object -Last 5)) {
                        Write-LogMessage "         $($err.Trim())" -Level ERROR
                    }
                }
            }
        }
        else {
            Write-Check "stdout log files" -Result WARN -Detail "No stdout log files found -- app may not have started"
        }
    }
    else {
        if ($aspNetCoreNode) {
            Write-Check "stdout log directory" -Result WARN -Detail "$logsDir does not exist"
            Write-Suggestion "Create: New-Item -ItemType Directory -Path '$logsDir' -Force"
        }
    }

    # ── 9. Windows Event Log ──────────────────────────────────────────────────
    Write-LogMessage "" -Level INFO
    Write-LogMessage "  Checking Windows Event Log (last 24h)..." -Level INFO
    $cutoff = (Get-Date).AddHours(-24)

    # Event providers related to IIS and ASP.NET Core
    $iisProviders = @(
        'IIS AspNetCore Module V2'
        'ASP.NET Core Module V2'
        'IIS-W3SVC-WP'
        'W3SVC'
        'WAS'
        'Microsoft-IIS-Configuration'
        'Microsoft-IIS-W3SVC'
        'Microsoft-IIS-HttpService'
        'HttpEvent'
        'ASP.NET 4.0.30319.0'
        '.NET Runtime'
        'Application Error'
    )

    $allIISEvents = @()

    foreach ($provider in $iisProviders) {
        try {
            $provEvents = Get-WinEvent -FilterHashtable @{
                LogName      = 'Application'
                Level        = @(1, 2, 3)  # Critical, Error, Warning
                StartTime    = $cutoff
                ProviderName = $provider
            } -MaxEvents 20 -ErrorAction SilentlyContinue

            if ($provEvents) {
                $allIISEvents += $provEvents
            }
        }
        catch {
            # Provider may not exist on this system -- skip silently
        }
    }

    # Also check System log for WAS and HTTP.sys events
    foreach ($sysProvider in @('WAS', 'Microsoft-Windows-WAS', 'Microsoft-Windows-HttpService', 'HTTP')) {
        try {
            $sysEvents = Get-WinEvent -FilterHashtable @{
                LogName      = 'System'
                Level        = @(1, 2, 3)
                StartTime    = $cutoff
                ProviderName = $sysProvider
            } -MaxEvents 10 -ErrorAction SilentlyContinue

            if ($sysEvents) {
                $allIISEvents += $sysEvents
            }
        }
        catch {
            # Provider may not exist -- skip silently
        }
    }

    if ($allIISEvents.Count -gt 0) {
        # Sort all events by time descending
        $allIISEvents = $allIISEvents | Sort-Object TimeCreated -Descending

        # Filter for events related to this specific app/pool
        # Regex: match any of these identifiers in the event message
        # (?i)      - case-insensitive
        # AppName   - the virtual app name
        # poolName  - the IIS app pool name
        # Application '/ - common ASP.NET Core module prefix
        # physPath  - the physical path (escaped for regex)
        $escapedPhysPath = [regex]::Escape($physPath)
        $relevantEvents = $allIISEvents | Where-Object {
            $_.Message -match "(?i)$([regex]::Escape($AppName))" -or
            $_.Message -match "(?i)$([regex]::Escape($poolName))" -or
            $_.Message -match "Application '/" -or
            $_.Message -match $escapedPhysPath
        }

        if ($relevantEvents) {
            Write-Check "Event Log (app-specific)" -Result FAIL -Detail "$($relevantEvents.Count) error/warning event(s) for $AppName"

            foreach ($ev in ($relevantEvents | Select-Object -First 8)) {
                $evTime = $ev.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                $evLevel = switch ($ev.Level) { 1 { "CRIT" } 2 { "ERR " } 3 { "WARN" } default { "INFO" } }
                $evProvider = $ev.ProviderName
                $evLogLevel = if ($ev.Level -le 2) { "ERROR" } else { "WARN" }

                Write-LogMessage "" -Level $evLogLevel
                Write-LogMessage "         [$evTime] [$evLevel] Provider: $evProvider (EventID: $($ev.Id))" -Level $evLogLevel

                # Show full event message -- never truncate
                # Try FormatDescription() first (resolves full template),
                # fall back to .Message, then raw properties
                $fullMsg = $null
                try { $fullMsg = $ev.FormatDescription() } catch { }
                if ([string]::IsNullOrWhiteSpace($fullMsg)) { $fullMsg = $ev.Message }
                if ([string]::IsNullOrWhiteSpace($fullMsg)) {
                    $fullMsg = ($ev.Properties | ForEach-Object { $_.Value }) -join ' | '
                }
                if (-not [string]::IsNullOrWhiteSpace($fullMsg)) {
                    Write-LogMessage $fullMsg -Level $evLogLevel
                }
            }

            if ($relevantEvents.Count -gt 8) {
                Write-LogMessage "         ... and $($relevantEvents.Count - 8) more event(s) not shown" -Level WARN
            }
        }
        else {
            Write-Check "Event Log (app-specific)" -Result PASS -Detail "No IIS errors related to $AppName in last 24h"
        }

        # Also show a count of general IIS events for context
        $generalCount = $allIISEvents.Count - ($relevantEvents | Measure-Object).Count
        if ($generalCount -gt 0) {
            Write-Check "Event Log (general IIS)" -Result WARN -Detail "$generalCount other IIS-related event(s) in last 24h (not directly related to $AppName)"

            # Show up to 3 non-app-specific events as context
            $otherEvents = $allIISEvents | Where-Object {
                $relevantEvents -notcontains $_
            } | Select-Object -First 3

            foreach ($ev in $otherEvents) {
                $evTime = $ev.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                $evLevel = switch ($ev.Level) { 1 { "CRIT" } 2 { "ERR " } 3 { "WARN" } default { "INFO" } }
                $evProvider = $ev.ProviderName
                $evLogLevel = if ($ev.Level -le 2) { "ERROR" } else { "WARN" }

                Write-LogMessage "" -Level DEBUG
                Write-LogMessage "         [$evTime] [$evLevel] Provider: $evProvider (EventID: $($ev.Id))" -Level $evLogLevel

                # Full message -- never truncate
                $otherMsg = $null
                try { $otherMsg = $ev.FormatDescription() } catch { }
                if ([string]::IsNullOrWhiteSpace($otherMsg)) { $otherMsg = $ev.Message }
                if ([string]::IsNullOrWhiteSpace($otherMsg)) {
                    $otherMsg = ($ev.Properties | ForEach-Object { $_.Value }) -join ' | '
                }
                if (-not [string]::IsNullOrWhiteSpace($otherMsg)) {
                    Write-LogMessage $otherMsg -Level $evLogLevel
                }
            }
        }
    }
    else {
        Write-Check "Event Log entries" -Result PASS -Detail "No IIS/ASP.NET errors in last 24h"
    }

    # ── 10. HTTP connectivity ─────────────────────────────────────────────────
    Write-LogMessage "" -Level INFO
    Write-LogMessage "  HTTP connectivity tests..." -Level INFO

    # Get parent site port
    $parentCfg = & $appcmd list site "$Parent" 2>&1 | Out-String
    $port = 80
    if ($parentCfg -match ':(\d+):') { $port = [int]$matches[1] }
    $baseUrl = "http://localhost:$($port)$VPath"

    $testUrls = @("$baseUrl/")
    if ($aspNetCoreNode) {
        $testUrls += "$($baseUrl)/health"
        $testUrls += "$($baseUrl)/scalar/v1"
    }

    foreach ($url in $testUrls) {
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            Write-Check "HTTP $url" -Result PASS -Detail "HTTP $($response.StatusCode)"
        }
        catch {
            $statusCode = $null
            $statusDesc = ""
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                $statusDesc = $_.Exception.Response.ReasonPhrase
            }
            # Try to read the response body for sub-status details (e.g. 500.35)
            $responseBody = ""
            try {
                if ($_.Exception.Response) {
                    $stream = $_.Exception.Response.Content.ReadAsStreamAsync().Result
                    $reader = [System.IO.StreamReader]::new($stream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Dispose()
                    $stream.Dispose()
                }
            }
            catch { <# ignore - best effort #> }

            if ($statusCode) {
                $detail = "HTTP $statusCode $statusDesc"
                if ($statusCode -eq 500 -and $responseBody -match '500\.35') {
                    Write-Check "HTTP $url" -Result FAIL -Detail "$detail -- ASP.NET Core does not support multiple apps in the same app pool (500.35)"
                    Write-Suggestion "Each ASP.NET Core InProcess app needs its own dedicated app pool"
                    Write-Suggestion "Redeploy with a unique pool: .\IIS-DeployApp.ps1 -SiteName $AppName"
                }
                elseif ($statusCode -eq 500 -and $responseBody -match '500\.30') {
                    Write-Check "HTTP $url" -Result FAIL -Detail "$detail -- ANCM In-Process Start Failure (500.30)"
                    Write-Suggestion "Check stdout logs and Event Log for the startup exception"
                    Write-Suggestion "Common causes: missing appsettings.json, DB connection string, DLL dependency"
                }
                elseif ($statusCode -eq 500) {
                    Write-Check "HTTP $url" -Result FAIL -Detail "$detail -- app crashed on startup"
                    Write-Suggestion "Check stdout logs and Event Log above for the root cause"
                    Write-Suggestion "Common causes: missing appsettings.json, DB connection string, DLL dependency"
                }
                elseif ($statusCode -eq 502) {
                    Write-Check "HTTP $url" -Result FAIL -Detail "$detail -- app pool crashed or not started"
                    Write-Suggestion "Start the app pool: $appcmd start apppool `"$poolName`""
                }
                elseif ($statusCode -eq 503) {
                    Write-Check "HTTP $url" -Result FAIL -Detail "$detail -- app pool stopped (likely crashed repeatedly)"
                    Write-Suggestion "Check Event Log, fix the issue, then: $appcmd start apppool `"$poolName`""
                }
                elseif ($statusCode -eq 404) {
                    Write-Check "HTTP $url" -Result WARN -Detail "$detail -- endpoint not found (may be normal for non-root URLs)"
                }
                else {
                    Write-Check "HTTP $url" -Result WARN -Detail $detail
                }
            }
            else {
                Write-Check "HTTP $url" -Result FAIL -Detail $_.Exception.Message
                Write-Suggestion "Is the parent site '$Parent' running? Check: $appcmd list site `"$Parent`""
            }
        }
    }
}

function Test-IISSite {
    param(
        [string]$SiteName = "",
        [string]$ParentSite = "Default Web Site"
    )
    
    $ErrorActionPreference = "Continue"

    Import-Module GlobalFunctions -Force

    $appcmd = "$($env:SystemRoot)\System32\inetsrv\appcmd.exe"

    # ═══════════════════════════════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════════════════════════════
    $script:PassCount = 0
    $script:WarnCount = 0
    $script:FailCount = 0

    Write-LogMessage "═══════════════════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage "IIS Site Diagnostics" -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage "Computer: $($env:COMPUTERNAME)" -Level INFO
    Write-LogMessage "Date:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level INFO

    # ── Current IIS overview ──────────────────────────────────────────────────────
    Show-IISOverview -OutputTarget LogMessage
    Write-LogMessage "" -Level INFO
    Write-LogMessage "───────────────────────────────────────────────────────────────────" -Level INFO

    # ── Check IIS service ─────────────────────────────────────────────────────────
    if (-not (Test-Path $appcmd)) {
        Write-Check "IIS installed" -Result FAIL -Detail "appcmd.exe not found"
        throw "IIS is not installed -- appcmd.exe not found"
    }
    Write-Check "IIS installed" -Result PASS

    $w3svc = Get-Service -Name W3SVC -ErrorAction SilentlyContinue
    if ($w3svc -and $w3svc.Status -eq "Running") {
        Write-Check "W3SVC service" -Result PASS -Detail "Running"
    }
    elseif ($w3svc) {
        Write-Check "W3SVC service" -Result FAIL -Detail "Status: $($w3svc.Status)"
        Write-Suggestion "Start-Service W3SVC"
    }
    else {
        Write-Check "W3SVC service" -Result FAIL -Detail "Service not found"
    }

    # ── Check parent site ─────────────────────────────────────────────────────────
    $parentCheck = & $appcmd list site "$ParentSite" 2>&1 | Out-String
    if ($parentCheck -match 'SITE "') {
        $parentState = (& $appcmd list site "$ParentSite" /text:state 2>&1).Trim()
        if ($parentState -eq "Started") {
            Write-Check "Parent site '$ParentSite'" -Result PASS -Detail "Running"
        }
        else {
            Write-Check "Parent site '$ParentSite'" -Result FAIL -Detail "State: $parentState"
            Write-Suggestion "Run the DefaultWebSite profile: .\IIS-DeployApp.ps1 (choose DefaultWebSite)"
        }
    }
    else {
        Write-Check "Parent site '$ParentSite'" -Result FAIL -Detail "Does not exist"
        Write-Suggestion "Run the DefaultWebSite profile to create it"
        throw "Parent site '$ParentSite' does not exist"
    }

    # ── Build list of apps to diagnose ────────────────────────────────────────────
    if (-not [string]::IsNullOrWhiteSpace($SiteName)) {
        # Diagnose specific app
        Test-IISApp -AppName $SiteName -Parent $ParentSite -VPath "/$SiteName"
    }
    else {
        # Discover and diagnose all virtual apps under parent site
        $appLines = & $appcmd list app /site.name:"$ParentSite" 2>&1 | Out-String
        $appList = @()
        foreach ($line in ($appLines -split "`n")) {
            if ($line -match 'APP "([^"]+)"') {
                $appPath = $matches[1]
                # Skip the root app
                if ($appPath -ne "$ParentSite/") {
                    $vPath = $appPath -replace [regex]::Escape($ParentSite), ''
                    $name = $vPath.TrimStart('/')
                    $appList += @{ Name = $name; VPath = $vPath }
                }
            }
        }

        if ($appList.Count -eq 0) {
            Write-LogMessage "" -Level INFO
            Write-LogMessage "No virtual applications found under '$ParentSite'." -Level WARN
            Write-Suggestion "Deploy an app: .\IIS-DeployApp.ps1"
        }
        else {
            Write-LogMessage "" -Level INFO
            Write-LogMessage "Found $($appList.Count) virtual application(s) to diagnose" -Level INFO
            foreach ($app in $appList) {
                Test-IISApp -AppName $app.Name -Parent $ParentSite -VPath $app.VPath
            }
        }

        # Also check the root site redirect
        Write-LogMessage "" -Level INFO
        Write-LogMessage "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
        Write-LogMessage "Checking root site redirect (http://localhost/)" -Level INFO
        Write-LogMessage "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Level INFO
        try {
            $rootResponse = Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
            if ($rootResponse.Content -match 'DedgeAuth/login') {
                Write-Check "Root redirect" -Result PASS -Detail "Redirects to /DedgeAuth/login.html"
            }
            else {
                Write-Check "Root redirect" -Result WARN -Detail "HTTP $($rootResponse.StatusCode) but no DedgeAuth redirect found"
            }
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
            if ($statusCode -ge 300 -and $statusCode -lt 400) {
                Write-Check "Root redirect" -Result PASS -Detail "HTTP $statusCode redirect"
            }
            elseif ($statusCode) {
                Write-Check "Root redirect" -Result FAIL -Detail "HTTP $statusCode"
                Write-Suggestion "Run the DefaultWebSite profile to set up the redirect index.html"
            }
            else {
                Write-Check "Root redirect" -Result FAIL -Detail $_.Exception.Message
            }
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # SUMMARY
    # ═══════════════════════════════════════════════════════════════════════════════
    Write-LogMessage "" -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════════════════" -Level INFO
    Write-LogMessage "Results: $($script:PassCount) passed, $($script:WarnCount) warnings, $($script:FailCount) failed" -Level INFO
    Write-LogMessage "═══════════════════════════════════════════════════════════════════" -Level INFO

    if ($script:FailCount -gt 0) {
        throw "Diagnostics completed with $($script:FailCount) failure(s)"
    }
}


# ═══════════════════════════════════════════════════════════════════════════════
# GATHER ALL IIS ENTRIES
# ═══════════════════════════════════════════════════════════════════════════════
function Get-IISEntries {
    $entries = @()

    # Get all sites
    $siteLines = & $appcmd list site 2>&1 | Out-String
    foreach ($line in ($siteLines -split "`n")) {
        if ($line -match 'SITE "([^"]+)"') {
            $name = $matches[1]
            $state = ""
            if ($line -match 'state:(\S+)') { $state = $matches[1] }
            $bindings = ""
            if ($line -match 'bindings:([^,]+)') { $bindings = $matches[1] }

            # Get virtual apps under this site
            $appLines = & $appcmd list app /site.name:"$name" 2>&1 | Out-String
            $vApps = @()
            foreach ($appLine in ($appLines -split "`n")) {
                if ($appLine -match 'APP "([^"]+)"') {
                    $appPath = $matches[1]
                    # Skip the root app (site itself)
                    if ($appPath -ne "$name/") {
                        $physPath = ""
                        $pool = ""
                        $vdirInfo = & $appcmd list app "$appPath" /text:* 2>&1 | Out-String
                        if ($vdirInfo -match 'APPPOOL\.NAME:"([^"]+)"') { $pool = $matches[1] }

                        # Get physical path from vdir
                        $vdirPath = & $appcmd list vdir "$appPath/" 2>&1 | Out-String
                        if ($vdirPath -match 'physicalPath:([^\s\)]+)') { $physPath = $matches[1] }

                        # Extract virtual path portion
                        $vPath = $appPath -replace [regex]::Escape($name), ''

                        $vApps += [PSCustomObject]@{
                            Type         = "VirtualApp"
                            DisplayName  = "$name$vPath"
                            SiteName     = $name
                            VirtualPath  = $vPath
                            AppPool      = $pool
                            PhysicalPath = $physPath
                            State        = $state
                            Bindings     = $bindings
                        }
                    }
                }
            }

            # Get root app physical path
            $rootPhys = ""
            $rootPool = ""
            $rootVdir = & $appcmd list vdir "$name/" 2>&1 | Out-String
            if ($rootVdir -match 'physicalPath:([^\s\)]+)') { $rootPhys = $matches[1] }
            $rootAppInfo = & $appcmd list app "$name/" /text:* 2>&1 | Out-String
            if ($rootAppInfo -match 'APPPOOL\.NAME:"([^"]+)"') { $rootPool = $matches[1] }

            $entries += [PSCustomObject]@{
                Type         = "Site"
                DisplayName  = $name
                SiteName     = $name
                VirtualPath  = "/"
                AppPool      = $rootPool
                PhysicalPath = $rootPhys
                State        = $state
                Bindings     = $bindings
                VirtualApps  = $vApps
            }

            $entries += $vApps
        }
    }
    return $entries
}
function Uninstall-IISApp {
    param(
        [string]$SiteName = "",
        [switch]$RemoveFiles,
        [switch]$Force
    )


    $ErrorActionPreference = "Stop"

    Import-Module GlobalFunctions -Force

    $appcmd = "$($env:SystemRoot)\System32\inetsrv\appcmd.exe"
    if (-not (Test-Path $appcmd)) {
        Write-LogMessage "appcmd.exe not found -- IIS is not installed" -Level ERROR
        exit 1
    }
    
    $allEntries = Get-IISEntries

    if ($allEntries.Count -eq 0) {
        Write-LogMessage "No IIS sites or virtual applications found." -Level WARN
        exit 0
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # SELECT TARGET
    # ═══════════════════════════════════════════════════════════════════════════════
    $target = $null

    if ([string]::IsNullOrWhiteSpace($SiteName)) {
        # Interactive picker
        Write-Host ""
        Write-Host "IIS Uninstall - Select item to remove" -ForegroundColor Cyan
        Write-Host "──────────────────────────────────────" -ForegroundColor DarkGray

        # Show current IIS configuration: Sites first, then Apps
        Show-IISOverview -OutputTarget Host
        Write-Host ""
        Write-Host "──────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host ""

        $i = 1
        $selectable = @()
        foreach ($entry in $allEntries) {
            $icon = if ($entry.Type -eq "Site") { "[Site]" } else { " [App]" }
            $stateTag = if ($entry.State) { " ($($entry.State))" } else { "" }
            $poolTag = if ($entry.AppPool) { " pool=$($entry.AppPool)" } else { "" }
            $pathTag = if ($entry.PhysicalPath) { " -> $($entry.PhysicalPath)" } else { "" }

            if ($entry.Type -eq "Site") {
                Write-Host ""
                Write-Host "  $($i)) $icon $($entry.DisplayName)$($stateTag)$($poolTag)$($pathTag)" -ForegroundColor White
            }
            else {
                Write-Host "  $($i)) $icon $($entry.DisplayName)$($poolTag)$($pathTag)" -ForegroundColor Gray
            }
            $selectable += $entry
            $i++
        }

        Write-Host ""
        $choice = Read-Host "Choose item to remove (or 'q' to quit)"
        if ($choice -eq 'q' -or [string]::IsNullOrWhiteSpace($choice)) {
            Write-LogMessage "Cancelled by user." -Level INFO
            exit 0
        }

        $choiceNum = 0
        if ([int]::TryParse($choice, [ref]$choiceNum) -and $choiceNum -ge 1 -and $choiceNum -le $selectable.Count) {
            $target = $selectable[$choiceNum - 1]
        }
        else {
            Write-LogMessage "Invalid choice." -Level ERROR
            exit 1
        }
    }
    else {
        # Find by name - check virtual apps first, then sites
        $target = $allEntries | Where-Object {
            ($_.Type -eq "VirtualApp" -and $_.VirtualPath -eq "/$SiteName") -or
            ($_.Type -eq "VirtualApp" -and $_.DisplayName -eq $SiteName) -or
            ($_.Type -eq "Site" -and $_.SiteName -eq $SiteName)
        } | Select-Object -First 1

        # Fallback: try normalized comparison (strip spaces, case-insensitive)
        # This handles cases like SiteName="DefaultWebSite" matching IIS "Default Web Site"
        if (-not $target) {
            $normalizedInput = $SiteName -replace '\s', ''
            $target = $allEntries | Where-Object {
                $normalizedName = $_.SiteName -replace '\s', ''
                $normalizedDisplay = $_.DisplayName -replace '\s', ''
                ($_.Type -eq "Site" -and $normalizedName -eq $normalizedInput) -or
                ($_.Type -eq "VirtualApp" -and $normalizedDisplay -eq $normalizedInput)
            } | Select-Object -First 1
            if ($target) {
                Write-LogMessage "Resolved '$SiteName' to '$($target.DisplayName)' via normalized match" -Level DEBUG
            }
        }

        if (-not $target) {
            Write-LogMessage "No site or virtual app matching '$SiteName' found." -Level ERROR
            Write-LogMessage "Available:" -Level INFO
            foreach ($e in $allEntries) {
                Write-LogMessage "  - $($e.DisplayName) ($($e.Type))" -Level INFO
            }
            exit 1
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # CONFIRM
    # ═══════════════════════════════════════════════════════════════════════════════
    Write-Host ""
    Write-Host "About to remove:" -ForegroundColor Yellow
    Write-Host "  Type:          $($target.Type)" -ForegroundColor White
    Write-Host "  Name:          $($target.DisplayName)" -ForegroundColor White
    Write-Host "  App Pool:      $($target.AppPool)" -ForegroundColor White
    Write-Host "  Physical Path: $($target.PhysicalPath)" -ForegroundColor White
    if ($RemoveFiles -and $target.PhysicalPath) {
        Write-Host "  DELETE FILES:  YES -- $($target.PhysicalPath) will be deleted!" -ForegroundColor Red
    }

    if ($target.Type -eq "Site") {
        $childApps = $allEntries | Where-Object { $_.Type -eq "VirtualApp" -and $_.SiteName -eq $target.SiteName }
        if ($childApps.Count -gt 0) {
            Write-Host ""
            Write-Host "  WARNING: This site has $($childApps.Count) virtual app(s) that will also be removed:" -ForegroundColor Red
            foreach ($child in $childApps) {
                Write-Host "    - $($child.DisplayName) (pool: $($child.AppPool), path: $($child.PhysicalPath))" -ForegroundColor Yellow
            }
        }
    }

    if (-not $Force) {
        Write-Host ""
        $confirm = Read-Host "Continue? [y/N]"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-LogMessage "Cancelled by user." -Level INFO
            exit 0
        }
    }

    Write-LogMessage "Removing: $($target.DisplayName) ($($target.Type))" -Level INFO

    # ═══════════════════════════════════════════════════════════════════════════════
    # REMOVE
    # ═══════════════════════════════════════════════════════════════════════════════
    $script:HasError = $false

    function Remove-AppPool {
        param([string]$PoolName)
        if ([string]::IsNullOrWhiteSpace($PoolName)) { return }
        # Don't remove built-in pools
        if ($PoolName -in @("DefaultAppPool", ".NET v4.5", ".NET v4.5 Classic", ".NET v2.0", ".NET v2.0 Classic", "Classic .NET AppPool")) {
            Write-LogMessage "Skipping built-in app pool: $PoolName" -Level DEBUG
            return
        }
        $poolCheck = & $appcmd list apppool "$PoolName" 2>&1 | Out-String
        if ($poolCheck -match 'APPPOOL "') {
            Write-LogMessage "Stopping app pool: $PoolName" -Level INFO
            & $appcmd stop apppool "$PoolName" 2>&1 | Out-Null
            Start-Sleep -Seconds 2
            Write-LogMessage "Deleting app pool: $PoolName" -Level INFO
            $result = & $appcmd delete apppool "$PoolName" 2>&1 | Out-String
            if ($result -match "deleted") {
                Write-LogMessage "App pool '$PoolName' deleted" -Level INFO
            }
            elseif ($result -match "Cannot find") {
                # Pool was listed but gone by delete time (race condition) -- desired state is achieved
                Write-LogMessage "App pool '$PoolName' already removed (not found during delete)" -Level INFO
            }
            else {
                Write-LogMessage "App pool delete result: $($result.Trim())" -Level WARN
            }
        }
    }

    function Remove-PhysicalFiles {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        # Safety: don't delete system paths
        $safePaths = @("C:\inetpub\wwwroot", "C:\inetpub", "C:\Windows", "$($env:SystemRoot)")
        if ($Path -in $safePaths) {
            Write-LogMessage "Skipping protected path: $Path" -Level WARN
            return
        }
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogMessage "Deleted files: $Path" -Level INFO
        }
    }

    try {
        if ($target.Type -eq "VirtualApp") {
            # Remove virtual application
            $appId = "$($target.SiteName)$($target.VirtualPath)"
            Write-LogMessage "Removing virtual application: $appId" -Level INFO

            $result = & $appcmd delete app /app.name:"$appId" 2>&1 | Out-String
            if ($result -match "deleted") {
                Write-LogMessage "Virtual app '$appId' deleted" -Level INFO
            }
            else {
                Write-LogMessage "Delete result: $($result.Trim())" -Level WARN
            }

            Remove-AppPool -PoolName $target.AppPool
            if ($RemoveFiles) { Remove-PhysicalFiles -Path $target.PhysicalPath }

        }
        elseif ($target.Type -eq "Site") {
            # Remove entire site and all its virtual apps
            Write-LogMessage "Removing site: $($target.SiteName)" -Level INFO

            # First remove child virtual apps
            $childApps = $allEntries | Where-Object { $_.Type -eq "VirtualApp" -and $_.SiteName -eq $target.SiteName }
            foreach ($child in $childApps) {
                $childId = "$($child.SiteName)$($child.VirtualPath)"
                Write-LogMessage "Removing child virtual app: $childId" -Level INFO
                & $appcmd delete app /app.name:"$childId" 2>&1 | Out-Null
                Remove-AppPool -PoolName $child.AppPool
                if ($RemoveFiles) { Remove-PhysicalFiles -Path $child.PhysicalPath }
            }

            # Stop and delete the site
            & $appcmd stop site "$($target.SiteName)" 2>&1 | Out-Null
            Start-Sleep -Seconds 1
            $result = & $appcmd delete site "$($target.SiteName)" 2>&1 | Out-String
            if ($result -match "deleted") {
                Write-LogMessage "Site '$($target.SiteName)' deleted" -Level INFO
            }
            else {
                Write-LogMessage "Delete result: $($result.Trim())" -Level WARN
            }

            Remove-AppPool -PoolName $target.AppPool
            if ($RemoveFiles) { Remove-PhysicalFiles -Path $target.PhysicalPath }
        }
    }
    catch {
        Write-LogMessage "Uninstall failed: $($_.Exception.Message)" -Level FATAL -Exception $_
        throw
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # REMOVE FIREWALL RULES
    # ═══════════════════════════════════════════════════════════════════════════════
    # Determine the app name used in firewall rule display names
    $firewallAppName = if ($target.Type -eq "VirtualApp") {
        $target.VirtualPath.TrimStart('/')
    }
    else {
        $target.SiteName
    }

    if (-not [string]::IsNullOrWhiteSpace($firewallAppName)) {
        $fwRulePrefix = "$firewallAppName - "
        Write-LogMessage "Checking for firewall rules matching '$($fwRulePrefix)*'..." -Level INFO
        $matchingRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -like "$($fwRulePrefix)*"
        }
        if ($matchingRules) {
            foreach ($rule in $matchingRules) {
                Write-LogMessage "Removing firewall rule: $($rule.DisplayName)" -Level INFO
                Remove-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
            }
            Write-LogMessage "Removed $(@($matchingRules).Count) firewall rule(s)" -Level INFO
        }
        else {
            Write-LogMessage "No firewall rules found for '$firewallAppName'" -Level DEBUG
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # REMOVE SAVED DEPLOY PROFILES
    # ═══════════════════════════════════════════════════════════════════════════════
    $profileDir = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\IIS-DeployApp"

    # Build list of profile SiteNames to remove (includes child apps when removing a site)
    $profileNamesToRemove = @()
    if ($target.Type -eq "VirtualApp") {
        $profileNamesToRemove += $target.VirtualPath.TrimStart('/')
    }
    else {
        # Site itself
        $profileNamesToRemove += $target.SiteName
        # Child virtual apps that were removed with the site
        $childAppsForProfile = $allEntries | Where-Object { $_.Type -eq "VirtualApp" -and $_.SiteName -eq $target.SiteName }
        foreach ($child in $childAppsForProfile) {
            $profileNamesToRemove += $child.VirtualPath.TrimStart('/')
        }
    }

    if ($profileNamesToRemove.Count -gt 0 -and (Test-Path $profileDir -ErrorAction SilentlyContinue)) {
        $matchingProfiles = Get-ChildItem -Path $profileDir -Filter "*.deploy.json" -File -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $json = Get-Content $_.FullName -Raw | ConvertFrom-Json
                $json.SiteName -in $profileNamesToRemove
            }
            catch { $false }
        }
        if ($matchingProfiles) {
            foreach ($pf in $matchingProfiles) {
                Remove-Item -Path $pf.FullName -Force -ErrorAction SilentlyContinue
                Write-LogMessage "Removed saved deploy profile: $($pf.Name)" -Level INFO
            }
        }
        else {
            Write-LogMessage "No saved deploy profiles found for: $($profileNamesToRemove -join ', ')" -Level DEBUG
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # SUMMARY
    # ═══════════════════════════════════════════════════════════════════════════════
    Write-LogMessage "Remaining IIS configuration:" -Level INFO

    $remaining = & $appcmd list site 2>&1 | Out-String
    foreach ($line in ($remaining -split "`n")) {
        if ($line.Trim()) { Write-LogMessage "  $($line.Trim())" -Level INFO }
    }

    $remainingApps = & $appcmd list app 2>&1 | Out-String
    foreach ($line in ($remainingApps -split "`n")) {
        if ($line.Trim()) { Write-LogMessage "  $($line.Trim())" -Level INFO }
    }
}


function Get-DeployProfiles {
    # Collects profiles from three sources (in priority order):
    #   1. Caller templates ($callerTemplatesDir) -- from $PSScriptRoot\templates of the calling script
    #   2. Bundled templates ($bundledProfileDir)  -- from the deployed app folder
    #   3. Saved profiles   ($profileDir)          -- from the shared network folder
    # Templates appear at the top of the list. Templates that have been previously
    # deployed (matching SiteName exists in $profileDir) are flagged with HasBeenDeployed.

    $templates = @()
    $savedByName = @{}

    # ── Collect saved profiles from network share (for HasBeenDeployed lookup) ──
    if (Test-Path $profileDir -ErrorAction SilentlyContinue) {
        $files = Get-ChildItem -Path $profileDir -Filter "*.deploy.json" -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
        foreach ($f in $files) {
            try {
                $json = Get-Content $f.FullName -Raw | ConvertFrom-Json
                $name = $json.SiteName
                if (-not $savedByName.ContainsKey($name)) {
                    $savedByName[$name] = [PSCustomObject]@{
                        Name              = $name
                        Source            = $json.InstallSource
                        AppType           = $json.AppType
                        File              = $f.FullName
                        LastUsed          = $json.LastDeployed
                        IsTemplate        = $false
                        HasBeenDeployed   = $true
                        IsRootSiteProfile = ($json.IsRootSiteProfile -eq $true)
                    }
                }
            }
            catch { }
        }
    }

    # ── Collect templates from caller and bundled directories ────────────────────
    $templateDirs = @($callerTemplatesDir, $bundledProfileDir) |
    Where-Object { $_ -and (Test-Path $_ -ErrorAction SilentlyContinue) } |
    Select-Object -Unique
    $seenTemplateNames = @{}

    foreach ($dir in $templateDirs) {
        $files = Get-ChildItem -Path $dir -Filter "*.deploy.json" -File -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            try {
                $json = Get-Content $f.FullName -Raw | ConvertFrom-Json
                $name = $json.SiteName
                if (-not $seenTemplateNames.ContainsKey($name)) {
                    $seenTemplateNames[$name] = $true
                    $deployed = $savedByName.ContainsKey($name)
                    $lastUsed = if ($deployed) { $savedByName[$name].LastUsed } else { $null }
                    $templates += [PSCustomObject]@{
                        Name              = $name
                        Source            = $json.InstallSource
                        AppType           = $json.AppType
                        File              = $f.FullName
                        LastUsed          = $lastUsed
                        IsTemplate        = $true
                        HasBeenDeployed   = $deployed
                        IsRootSiteProfile = ($json.IsRootSiteProfile -eq $true)
                    }
                }
            }
            catch { }
        }
    }

    # ── Build final list: templates first, then saved-only profiles ──────────────
    $sortedTemplates = $templates | Sort-Object @{Expression = { -not $_.IsRootSiteProfile } }, Name
    $savedOnly = $savedByName.Values | Where-Object { -not $seenTemplateNames.ContainsKey($_.Name) } |
    Sort-Object @{Expression = { -not $_.IsRootSiteProfile } }, Name

    return @($sortedTemplates) + @($savedOnly)
}

function Import-DeployProfile {
    param([string]$FilePath)
    $json = Get-Content $FilePath -Raw | ConvertFrom-Json
    $ht = @{}
    $json.PSObject.Properties | ForEach-Object {
        $val = $_.Value
        if ($val -is [string] -and $val -match '\$env:') {
            $val = $ExecutionContext.InvokeCommand.ExpandString($val)
        }
        $ht[$_.Name] = $val
    }
    return $ht
}

function Save-DeployProfile {
    param([hashtable]$Params)
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }
    $profileFile = Join-Path $profileDir "$($Params.SiteName)_$($Params.InstallSource)_$(Get-Date -Format 'yyyyMMdd-HHmmss').deploy.json"
    $Params | ConvertTo-Json -Depth 5 | Set-Content -Path $profileFile -Encoding UTF8 -Force
    return $profileFile
}
# ═══════════════════════════════════════════════════════════════════════════════
# Invoke-AppCmdRaw  -- low-level appcmd executor with DEBUG logging
# ═══════════════════════════════════════════════════════════════════════════════
# Centralizes all appcmd.exe calls. Every invocation logs the command and its
# output at DEBUG level so deploy/diagnostics sessions are fully traceable.
#
# OutputMode controls how the raw output is returned:
#   "String"  -> capture as single trimmed string   (replaces | Out-String)
#   "Value"   -> capture and .Trim() a single value (replaces (...).Trim())
#   "Null"    -> discard output, return $null        (replaces | Out-Null)
#   "Lines"   -> return array of non-empty lines     (for line-by-line parsing)
# ═══════════════════════════════════════════════════════════════════════════════
function Invoke-AppCmdRaw {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [ValidateSet("String", "Value", "Null", "Lines")]
        [string]$OutputMode = "String"
    )
    $argString = $Arguments -join ' '
    Write-LogMessage "APPCMD EXEC: $($appcmd) $($argString)  [OutputMode=$($OutputMode)]" -Level DEBUG

    $raw = & $appcmd @Arguments 2>&1

    switch ($OutputMode) {
        "String" {
            $output = ($raw | Out-String).Trim()
            if ($output) { Write-LogMessage "APPCMD OUT [String]: $($output)" -Level DEBUG }
            else { Write-LogMessage "APPCMD OUT [String]: (empty)" -Level DEBUG }
            return $output
        }
        "Value" {
            $output = ("$raw").Trim()
            if ($output) { Write-LogMessage "APPCMD OUT [Value]: $($output)" -Level DEBUG }
            else { Write-LogMessage "APPCMD OUT [Value]: (empty)" -Level DEBUG }
            return $output
        }
        "Null" {
            $output = ($raw | Out-String).Trim()
            if ($output) { Write-LogMessage "APPCMD OUT [Null]: $($output)" -Level DEBUG }
            else { Write-LogMessage "APPCMD OUT [Null]: (empty)" -Level DEBUG }
            return $null
        }
        "Lines" {
            $output = ($raw | Out-String).Trim()
            if ($output) { Write-LogMessage "APPCMD OUT [Lines]: $($output)" -Level DEBUG }
            else { Write-LogMessage "APPCMD OUT [Lines]: (empty)" -Level DEBUG }
            $lines = @($output -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            Write-LogMessage "APPCMD OUT [Lines]: returned $($lines.Count) line(s)" -Level DEBUG
            return $lines
        }
    }
}

function Invoke-AppCmd {
    param(
        [string[]]$Arguments,
        [string]$Description,
        [switch]$FailOnError
    )
    $output = Invoke-AppCmdRaw -Arguments $Arguments -OutputMode String

    if ($output -match "ERROR") {
        Write-LogMessage "$Description FAILED: $output" -Level ERROR
        if ($FailOnError) { throw "$Description failed: $output" }
        return $null
    }
    return $output
}

# ═══════════════════════════════════════════════════════════════════════════════
# Show-IISOverview  -- display current IIS sites and virtual applications
# ═══════════════════════════════════════════════════════════════════════════════
# Replaces the repeated "Current IIS Sites / Current IIS Virtual Applications"
# blocks used by the profile picker, uninstall picker, and diagnostics.
#
# OutputTarget controls where the output goes:
#   "Host"       -> Write-Host with colors   (interactive pickers)
#   "LogMessage" -> Write-LogMessage          (diagnostics / non-interactive)
# ═══════════════════════════════════════════════════════════════════════════════
function Show-IISOverview {
    param(
        [ValidateSet("Host", "LogMessage")]
        [string]$OutputTarget = "Host"
    )

    if (-not (Test-Path $appcmd)) { return }

    # Helper to write a line to the chosen target
    $writeLine = {
        param([string]$Text, [string]$Color = "Gray", [string]$Level = "INFO")
        if ($OutputTarget -eq "Host") {
            Write-Host $Text -ForegroundColor $Color
        }
        else {
            Write-LogMessage $Text -Level $Level
        }
    }

    # ── Pre-check: WAS and W3SVC must be running for appcmd to return data ──
    foreach ($svcName in @('WAS', 'W3SVC')) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running') {
            & $writeLine "  WARNING: Service '$svcName' is $($svc.Status) -- appcmd may return empty results" "Red" "WARN"
            try {
                Start-Service -Name $svcName -ErrorAction Stop
                Start-Sleep -Seconds 2
                & $writeLine "  Service '$svcName' started" "Green" "INFO"
            }
            catch {
                & $writeLine "  Failed to start '$($svcName)': $($_.Exception.Message)" "Red" "ERROR"
            }
        }
    }

    # ── Sites ────────────────────────────────────────────────────────────────
    & $writeLine "" "White" "INFO"
    & $writeLine "  Current IIS Sites:" "Yellow" "INFO"

    $currentSites = Invoke-AppCmdRaw -Arguments @("list", "site") -OutputMode String
    $siteCount = 0
    foreach ($line in ($currentSites -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^SITE "') {
            & $writeLine "    $trimmed" "Gray" "INFO"
            $siteCount++
        }
    }
    if ($siteCount -eq 0) {
        & $writeLine "    (none)" "DarkGray" "WARN"
        if ($currentSites) {
            & $writeLine "    (appcmd raw output: $($currentSites.Trim()))" "DarkYellow" "WARN"
        }
    }

    # ── Virtual Applications ─────────────────────────────────────────────────
    & $writeLine "" "White" "INFO"
    & $writeLine "  Current IIS Virtual Applications:" "Yellow" "INFO"

    $currentApps = Invoke-AppCmdRaw -Arguments @("list", "app") -OutputMode String
    $appCount = 0
    foreach ($line in ($currentApps -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^APP "') {
            & $writeLine "    $trimmed" "Gray" "INFO"
            $appCount++
        }
    }
    if ($appCount -eq 0) {
        & $writeLine "    (none)" "DarkGray" "WARN"
        if ($currentApps) {
            & $writeLine "    (appcmd raw output: $($currentApps.Trim()))" "DarkYellow" "WARN"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# IIS WRAPPER FUNCTIONS -- typed wrappers around Invoke-AppCmdRaw
# ═══════════════════════════════════════════════════════════════════════════════
# Each function:
#   1. Logs all input parameters at DEBUG level (caller + params)
#   2. Calls Invoke-AppCmdRaw with the correct arguments
#   3. Returns the result in the appropriate type
#
# Naming conventions:
#   Get-IIS*Check   -> returns raw appcmd output for existence checks
#   Get-IIS*State   -> returns a single state value (Started/Stopped/Unknown)
#   New-IIS*Entry   -> creates a new IIS object
#   Remove-IIS*Entry -> deletes an IIS object
#   Start-IIS*Entry -> starts an IIS object
#   Stop-IIS*Entry  -> stops an IIS object
#   Set-IIS*        -> configures an IIS object setting
#   Get-IIS*Info    -> returns detailed /text:* output
#   Get-IISAll*     -> lists all objects of a type
# ═══════════════════════════════════════════════════════════════════════════════

# ── SITE OPERATIONS ──────────────────────────────────────────────────────────

function Get-IISSiteCheck {
    # Returns raw appcmd output for a site. Use -match 'SITE "' to check existence.
    param([Parameter(Mandatory)][string]$SiteName)
    Write-LogMessage "Get-IISSiteCheck: SiteName=$($SiteName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "site", $SiteName) -OutputMode String
}

function Get-IISSiteState {
    # Returns the state of a site (e.g. "Started", "Stopped", "Unknown").
    param([Parameter(Mandatory)][string]$SiteName)
    Write-LogMessage "Get-IISSiteState: SiteName=$($SiteName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "site", $SiteName, "/text:state") -OutputMode Value
}

function Get-IISSiteInfo {
    # Returns detailed site config (/text:*).
    param([Parameter(Mandatory)][string]$SiteName)
    Write-LogMessage "Get-IISSiteInfo: SiteName=$($SiteName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "site", $SiteName, "/text:*") -OutputMode String
}

function New-IISSiteEntry {
    # Creates a new IIS site with optional bindings.
    param(
        [Parameter(Mandatory)][string]$SiteName,
        [Parameter(Mandatory)][string]$PhysicalPath,
        [string]$Bindings = "http/*:80:"
    )
    Write-LogMessage "New-IISSiteEntry: SiteName=$($SiteName) | PhysicalPath=$($PhysicalPath) | Bindings=$($Bindings)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("add", "site", "/name:$SiteName", "/physicalPath:$PhysicalPath", "/bindings:$Bindings") -OutputMode String
}

function Remove-IISSiteEntry {
    # Deletes a site by name.
    param([Parameter(Mandatory)][string]$SiteName)
    Write-LogMessage "Remove-IISSiteEntry: SiteName=$($SiteName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("delete", "site", "/site.name:$SiteName") -OutputMode String
}

function Start-IISSiteEntry {
    # Starts a site. Returns appcmd output (e.g. success or error message).
    param([Parameter(Mandatory)][string]$SiteName)
    Write-LogMessage "Start-IISSiteEntry: SiteName=$($SiteName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("start", "site", $SiteName) -OutputMode String
}

function Stop-IISSiteEntry {
    # Stops a site. Returns $null (output discarded).
    param([Parameter(Mandatory)][string]$SiteName)
    Write-LogMessage "Stop-IISSiteEntry: SiteName=$($SiteName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("stop", "site", $SiteName) -OutputMode Null
}

# ── APP POOL OPERATIONS ──────────────────────────────────────────────────────

function Get-IISAppPoolCheck {
    # Returns raw appcmd output for a pool. Use -match 'APPPOOL "' to check existence.
    param([Parameter(Mandatory)][string]$PoolName)
    Write-LogMessage "Get-IISAppPoolCheck: PoolName=$($PoolName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "apppool", $PoolName) -OutputMode String
}

function Get-IISAppPoolState {
    # Returns the state of an app pool (e.g. "Started", "Stopped").
    param([Parameter(Mandatory)][string]$PoolName)
    Write-LogMessage "Get-IISAppPoolState: PoolName=$($PoolName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "apppool", $PoolName, "/text:state") -OutputMode Value
}

function Get-IISAppPoolConfig {
    # Returns detailed app pool config (/text:*).
    param([Parameter(Mandatory)][string]$PoolName)
    Write-LogMessage "Get-IISAppPoolConfig: PoolName=$($PoolName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "apppool", $PoolName, "/text:*") -OutputMode String
}

function New-IISAppPoolEntry {
    # Creates a new app pool.
    param([Parameter(Mandatory)][string]$PoolName)
    Write-LogMessage "New-IISAppPoolEntry: PoolName=$($PoolName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("add", "apppool", "/name:$PoolName") -OutputMode Null
}

function Remove-IISAppPoolEntry {
    # Deletes an app pool by name.
    param([Parameter(Mandatory)][string]$PoolName)
    Write-LogMessage "Remove-IISAppPoolEntry: PoolName=$($PoolName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("delete", "apppool", $PoolName) -OutputMode String
}

function Start-IISAppPoolEntry {
    # Starts an app pool.
    param([Parameter(Mandatory)][string]$PoolName)
    Write-LogMessage "Start-IISAppPoolEntry: PoolName=$($PoolName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("start", "apppool", $PoolName) -OutputMode Null
}

function Stop-IISAppPoolEntry {
    # Stops an app pool.
    param([Parameter(Mandatory)][string]$PoolName)
    Write-LogMessage "Stop-IISAppPoolEntry: PoolName=$($PoolName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("stop", "apppool", $PoolName) -OutputMode Null
}

function Set-IISAppPoolSetting {
    # Applies one or more settings to an app pool (e.g. /managedRuntimeVersion:, /processModel.identityType:).
    param(
        [Parameter(Mandatory)][string]$PoolName,
        [Parameter(Mandatory)][string[]]$Settings
    )
    Write-LogMessage "Set-IISAppPoolSetting: PoolName=$($PoolName) | Settings=$($Settings -join ' ')" -Level DEBUG
    $cmdArgs = @("set", "apppool", $PoolName) + $Settings
    return Invoke-AppCmdRaw -Arguments $cmdArgs -OutputMode Null
}

# ── VIRTUAL APP OPERATIONS ───────────────────────────────────────────────────

function Get-IISAppCheck {
    # Returns raw appcmd output for a virtual app using /app.name: syntax.
    # Use -match 'APP "' to check existence.
    param([Parameter(Mandatory)][string]$AppIdentifier)
    Write-LogMessage "Get-IISAppCheck: AppIdentifier=$($AppIdentifier)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "app", "/app.name:$AppIdentifier") -OutputMode String
}

function Get-IISAppInfo {
    # Returns detailed app config (/text:*).
    param([Parameter(Mandatory)][string]$AppIdentifier)
    Write-LogMessage "Get-IISAppInfo: AppIdentifier=$($AppIdentifier)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "app", $AppIdentifier, "/text:*") -OutputMode String
}

function Get-IISAppsForSite {
    # Lists all virtual apps under a site.
    param([Parameter(Mandatory)][string]$SiteName)
    Write-LogMessage "Get-IISAppsForSite: SiteName=$($SiteName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "app", "/site.name:$SiteName") -OutputMode String
}

function Get-IISAppsForPool {
    # Lists all virtual apps using a specific app pool.
    param([Parameter(Mandatory)][string]$PoolName)
    Write-LogMessage "Get-IISAppsForPool: PoolName=$($PoolName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "app", "/apppool.name:$PoolName") -OutputMode String
}

function New-IISAppEntry {
    # Creates a new virtual application under a site.
    param(
        [Parameter(Mandatory)][string]$SiteName,
        [Parameter(Mandatory)][string]$VirtualPath,
        [Parameter(Mandatory)][string]$PhysicalPath
    )
    Write-LogMessage "New-IISAppEntry: SiteName=$($SiteName) | VirtualPath=$($VirtualPath) | PhysicalPath=$($PhysicalPath)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("add", "app", "/site.name:$SiteName", "/path:$VirtualPath", "/physicalPath:$PhysicalPath") -OutputMode String
}

function Remove-IISAppEntry {
    # Deletes a virtual app using /app.name: syntax for exact matching.
    param([Parameter(Mandatory)][string]$AppIdentifier)
    Write-LogMessage "Remove-IISAppEntry: AppIdentifier=$($AppIdentifier)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("delete", "app", "/app.name:$AppIdentifier") -OutputMode String
}

function Set-IISAppPoolAssignment {
    # Assigns an app pool to a virtual application.
    param(
        [Parameter(Mandatory)][string]$AppIdentifier,
        [Parameter(Mandatory)][string]$PoolName
    )
    Write-LogMessage "Set-IISAppPoolAssignment: AppIdentifier=$($AppIdentifier) | PoolName=$($PoolName)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("set", "app", $AppIdentifier, "/applicationPool:$PoolName") -OutputMode String
}

# ── VDIR OPERATIONS ──────────────────────────────────────────────────────────

function Get-IISVDirCheck {
    # Returns raw appcmd output for a virtual directory.
    param([Parameter(Mandatory)][string]$VDirPath)
    Write-LogMessage "Get-IISVDirCheck: VDirPath=$($VDirPath)" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "vdir", $VDirPath) -OutputMode String
}

# ── CONFIG OPERATIONS ────────────────────────────────────────────────────────

function Set-IISSiteConfigSection {
    # Applies settings to a specific IIS config section for a site/app.
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string[]]$Settings
    )
    Write-LogMessage "Set-IISSiteConfigSection: ConfigPath=$($ConfigPath) | Section=$($Section) | Settings=$($Settings -join ' ')" -Level DEBUG
    $cmdArgs = @("set", "config", $ConfigPath, "/section:$Section") + $Settings
    return Invoke-AppCmdRaw -Arguments $cmdArgs -OutputMode Null
}

function Set-IISSiteConfigRaw {
    # Applies raw config settings (no /section: prefix) to a site/app.
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string[]]$Settings
    )
    Write-LogMessage "Set-IISSiteConfigRaw: ConfigPath=$($ConfigPath) | Settings=$($Settings -join ' ')" -Level DEBUG
    $cmdArgs = @("set", "config", $ConfigPath) + $Settings
    return Invoke-AppCmdRaw -Arguments $cmdArgs -OutputMode Null
}

# ── WORKER PROCESS ───────────────────────────────────────────────────────────

function Get-IISWorkerProcesses {
    # Lists all running IIS worker processes.
    Write-LogMessage "Get-IISWorkerProcesses" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "wp") -OutputMode String
}

# ── LIST ALL (discovery/overview) ────────────────────────────────────────────

function Get-IISAllSites {
    # Lists all IIS sites.
    Write-LogMessage "Get-IISAllSites" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "site") -OutputMode String
}

function Get-IISAllApps {
    # Lists all IIS virtual applications.
    Write-LogMessage "Get-IISAllApps" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "app") -OutputMode String
}

function Get-IISAllAppPools {
    # Lists all IIS application pools.
    Write-LogMessage "Get-IISAllAppPools" -Level DEBUG
    return Invoke-AppCmdRaw -Arguments @("list", "apppool") -OutputMode String
}

function Find-TestPage {
    param([string]$Path)
    $defaultNames = @("index.html", "index.htm", "default.html", "default.htm", "home.html")
    foreach ($name in $defaultNames) {
        $candidate = Join-Path $Path $name
        if (Test-Path $candidate) { return $name }
    }
    # Fall back to any .html or .htm file in root
    $htmlFiles = Get-ChildItem -Path $Path -Filter "*.htm*" -File -ErrorAction SilentlyContinue |
    Select-Object -First 1
    if ($htmlFiles) { return $htmlFiles.Name }
    return $null
}

# Helper: test a URL and report result
function Test-HealthUrl {
    param(
        [string]$Url,
        [string]$Label
    )
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        Write-LogMessage "[OK] $($Label): $Url -> HTTP $($response.StatusCode)" -Level INFO
        return $true
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
        if ($statusCode) {
            if ($statusCode -ge 500) {
                Write-LogMessage "[FAIL] $($Label): $Url -> HTTP $($statusCode) (server error)" -Level ERROR
                return $false
            }
            elseif ($statusCode -eq 404) {
                Write-LogMessage "[WARN] $($Label): $Url -> HTTP 404 (not found)" -Level WARN
                return $false
            }
            elseif ($statusCode -ge 400) {
                # 4xx (except 404) means the server IS running but rejected the request
                # (401 Unauthorized, 403 Forbidden, 406 Not Acceptable, etc.)
                Write-LogMessage "[OK] $($Label): $Url -> HTTP $($statusCode) (server alive, request rejected)" -Level WARN
                return $true
            }
            else {
                Write-LogMessage "[OK] $($Label): $Url -> HTTP $($statusCode)" -Level WARN
                return $true
            }
        }
        else {
            Write-LogMessage "[FAIL] $($Label): $Url -> $($_.Exception.Message)" -Level ERROR
            return $false
        }
    }
}
# ═══════════════════════════════════════════════════════════════════════════════
# APPLY PERMISSIONS FROM TEMPLATE
# ═══════════════════════════════════════════════════════════════════════════════
function Set-FolderPermissionsFromTemplate {
    <#
    .SYNOPSIS
        Applies an array of filesystem ACE entries (from a permissions template JSON) to a path.
    .DESCRIPTION
        Parses each entry's FileSystemRights (named enum string or raw integer), InheritanceFlags,
        PropagationFlags, and AccessControlType, then adds all rules to the existing ACL and writes
        it back.

        Windows stores some ACEs using "generic access mask" integers that are not valid named members
        of the .NET FileSystemRights enum (e.g. GENERIC_ALL = 0x10000000, GENERIC_READ|GENERIC_EXECUTE
        = 0xA0000000). The FileSystemAccessRule constructor rejects these values even after enum-casting.
        They are mapped to the equivalent named FileSystemRights before the rule is created.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [array]$Entries
    )

    if (-not $Entries -or $Entries.Count -eq 0) {
        Write-LogMessage "Set-FolderPermissionsFromTemplate: no entries provided, skipping." -Level DEBUG
        return
    }

    # Map of Windows generic access mask integers (as signed Int32) to the nearest named
    # FileSystemRights value the .NET FileSystemAccessRule constructor accepts.
    #
    # These appear in Windows-generated ACEs for inheritance-only rules. At runtime Windows
    # translates them to full rights on each child object, so mapping to the equivalent named
    # right here is semantically correct and avoids the constructor's validation exception.
    #
    # Value breakdown:
    #   268435456  = 0x10000000 = GENERIC_ALL                   -> FullControl
    #   536870912  = 0x20000000 = GENERIC_EXECUTE                -> ReadAndExecute
    #   1073741824 = 0x40000000 = GENERIC_WRITE                  -> Modify
    #  -2147483648 = 0x80000000 = GENERIC_READ                   -> ReadAndExecute
    #  -1610612736 = 0xA0000000 = GENERIC_READ | GENERIC_EXECUTE -> ReadAndExecute
    $genericRightsMap = @{
        268435456   = [System.Security.AccessControl.FileSystemRights]::FullControl
        536870912   = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
        1073741824  = [System.Security.AccessControl.FileSystemRights]::Modify
        -2147483648 = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
        -1610612736 = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
    }

    Write-LogMessage "Applying $($Entries.Count) permission entries to: $($Path)" -Level INFO
    try {
        $acl = Get-Acl -Path $Path -ErrorAction Stop

        foreach ($entry in $Entries) {
            try {
                $identity = $entry.Identity

                # ── FileSystemRights: numeric (e.g. -1610612736) or named (e.g. "ReadAndExecute, Synchronize")
                $rawRights = "$($entry.FileSystemRights)".Trim()

                # Regex explanation:
                # ^     start of string
                # -?    optional leading minus (handles negative signed-int values like -1610612736)
                # \d+   one or more digits
                # $     end of string
                # Matches any pure integer string so we can route it through the generic-rights map
                # instead of trying to parse it as a named enum member.
                if ($rawRights -match '^-?\d+$') {
                    $intVal = [int]$rawRights
                    if ($genericRightsMap.ContainsKey($intVal)) {
                        $rights = $genericRightsMap[$intVal]
                        Write-LogMessage "  Mapped generic rights $($intVal) -> $($rights) for '$($identity)'" -Level DEBUG
                    }
                    else {
                        # Unknown numeric value: try direct enum cast as last resort
                        $rights = [Enum]::ToObject([System.Security.AccessControl.FileSystemRights], $intVal)
                    }
                }
                else {
                    # Named value, possibly comma-separated ("ReadAndExecute, Synchronize")
                    $rights = [System.Security.AccessControl.FileSystemRights]0
                    foreach ($part in ($rawRights -split ',')) {
                        $trimmed = $part.Trim()
                        if ($trimmed) {
                            $rights = $rights -bor [System.Security.AccessControl.FileSystemRights]$trimmed
                        }
                    }
                }

                # ── InheritanceFlags: possibly comma-separated ("ContainerInherit, ObjectInherit")
                $inherit = [System.Security.AccessControl.InheritanceFlags]::None
                foreach ($part in ("$($entry.InheritanceFlags)" -split ',')) {
                    $trimmed = $part.Trim()
                    if ($trimmed -and $trimmed -ne 'None') {
                        $inherit = $inherit -bor [System.Security.AccessControl.InheritanceFlags]$trimmed
                    }
                }

                # ── PropagationFlags: possibly comma-separated
                $propagate = [System.Security.AccessControl.PropagationFlags]::None
                foreach ($part in ("$($entry.PropagationFlags)" -split ',')) {
                    $trimmed = $part.Trim()
                    if ($trimmed -and $trimmed -ne 'None') {
                        $propagate = $propagate -bor [System.Security.AccessControl.PropagationFlags]$trimmed
                    }
                }

                # ── AccessControlType
                $aclType = if ($entry.AccessControlType -eq 'Deny') {
                    [System.Security.AccessControl.AccessControlType]::Deny
                }
                else {
                    [System.Security.AccessControl.AccessControlType]::Allow
                }

                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $identity, $rights, $inherit, $propagate, $aclType
                )
                $acl.AddAccessRule($rule)
                Write-LogMessage "  Queued: $($identity) / $($rights) / $($aclType)" -Level DEBUG
            }
            catch {
                Write-LogMessage "  Skipped rule for '$($entry.Identity)': $($_.Exception.Message)" -Level WARN
            }
        }

        Set-Acl -Path $Path -AclObject $acl -ErrorAction Stop
        Write-LogMessage "All permission entries applied to: $($Path)" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to apply permissions to '$($Path)': $($_.Exception.Message)" -Level WARN
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# DedgeAuth DATABASE HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

function Resolve-DedgeAuthDbHost {
    <#
    .SYNOPSIS
        Auto-discovers the DedgeAuth PostgreSQL database host at deploy time.
    .DESCRIPTION
        Tries hosts in order:
          1. localhost:8432
          2. $env:COMPUTERNAME with -app suffix replaced by -db (e.g. t-no1fkxtst-db)
        Returns the first host where a TCP connection succeeds AND the DedgeAuth database exists.
        Returns $null if no host is reachable (caller should skip DB registration).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'DbPassword', Justification = 'psql PGPASSWORD requires plain string')]
    param(
        [int]$Port = 8432,
        [string]$DbName = "DedgeAuth",
        [string]$DbUser = "postgres",
        [string]$DbPassword = "postgres"
    )

    $candidates = @("localhost")

    # Derive -db hostname from current machine name
    # Pattern: replace trailing -app (case-insensitive) with -db
    $derived = $env:COMPUTERNAME -replace '(?i)-app$', '-db'
    if ($derived -ne $env:COMPUTERNAME -and $derived -ne "localhost") {
        $candidates += $derived
    }

    foreach ($candidateHost in $candidates) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $connected = $tcp.ConnectAsync($candidateHost, $Port).Wait(2000)
            $tcp.Close()
            if (-not $connected) { continue }
        }
        catch {
            continue
        }

        # TCP reachable — verify DedgeAuth DB exists via quick SQL
        try {
            Import-Module PostgreSql-Handler -Force -ErrorAction SilentlyContinue
            $result = Invoke-PostgreSqlQuery -Host $candidateHost -Port $Port -User $DbUser -Password $DbPassword `
                -Database $DbName -Query "SELECT 1;" -Unattended -ErrorAction Stop
            if ($null -ne $result) {
                Write-LogMessage "DedgeAuth DB resolved: $($candidateHost):$($Port)/$($DbName)" -Level INFO
                return $candidateHost
            }
        }
        catch {
            Write-LogMessage "DedgeAuth DB not available on $($candidateHost):$($Port) — $($_.Exception.Message)" -Level DEBUG
        }
    }

    Write-LogMessage "DedgeAuth DB not found on any candidate host (localhost, $($derived)) — skipping DB registration" -Level WARN
    return $null
}

function Sync-DedgeAuthAdminEmails {
    <#
    .SYNOPSIS
        Ensures all AdminEmails from DedgeAuth appsettings.json have the highest privileges
        in the DedgeAuth database: global_access_level=3 (Admin) and the highest available
        role on the specified app.
    .DESCRIPTION
        Reads AdminEmails from the installed DedgeAuth appsettings.json. For each email:
        - Sets global_access_level = 3 in the users table (if user exists)
        - Grants the highest available role in the app's available_roles_json
        This runs non-fatally — errors are logged as warnings.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'DbPassword', Justification = 'psql PGPASSWORD requires plain string')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        [Parameter(Mandatory = $true)]
        [string]$DbHost,
        [int]$DbPort = 8432,
        [string]$DbName = "DedgeAuth",
        [string]$DbUser = "postgres",
        [string]$DbPassword = "postgres",
        [string]$HighestRole = "Admin"
    )

    # Read AdminEmails from installed DedgeAuth appsettings.json
    $DedgeAuthSettings = Join-Path $env:OptPath "DedgeWinApps\DedgeAuth\appsettings.json"
    if (-not (Test-Path $DedgeAuthSettings)) {
        Write-LogMessage "DedgeAuth appsettings.json not found at '$($DedgeAuthSettings)' — skipping admin sync" -Level DEBUG
        return
    }

    $adminEmails = @()
    try {
        $json = Get-Content $DedgeAuthSettings -Raw -Encoding UTF8 | ConvertFrom-Json
        $adminEmails = @($json.AuthConfiguration.AdminEmails | Where-Object { $_ })
    }
    catch {
        Write-LogMessage "Could not read AdminEmails from DedgeAuth appsettings: $($_.Exception.Message)" -Level WARN
        return
    }

    if ($adminEmails.Count -eq 0) {
        Write-LogMessage "No AdminEmails configured in DedgeAuth appsettings — skipping admin sync" -Level DEBUG
        return
    }

    $syncApp = if ([string]::IsNullOrWhiteSpace($AppId)) { "(global only)" } else { $AppId }
    Write-LogMessage "Syncing $($adminEmails.Count) admin email(s) for app '$($syncApp)'..." -Level INFO

    try {
        Import-Module PostgreSql-Handler -Force -ErrorAction SilentlyContinue

        foreach ($email in $adminEmails) {
            $emailEscaped = $email -replace "'", "''"

            # Ensure global_access_level = 3 (Admin)
            $levelSql = "UPDATE users SET global_access_level = 3 WHERE LOWER(email) = LOWER('$($emailEscaped)');"
            Invoke-PostgreSqlQuery -Host $DbHost -Port $DbPort -User $DbUser -Password $DbPassword `
                -Database $DbName -Query $levelSql -Unattended -ErrorAction SilentlyContinue | Out-Null

            # Grant highest role on this specific app (upsert) — skip if AppId is empty
            if (-not [string]::IsNullOrWhiteSpace($AppId) -and -not [string]::IsNullOrWhiteSpace($HighestRole)) {
                $permSql = @"
INSERT INTO app_permissions (id, user_id, app_id, role, granted_at, granted_by)
SELECT gen_random_uuid(), u.id, a.id, '$($HighestRole -replace "'","''")', NOW(), 'Sync-DedgeAuthAdminEmails'
FROM users u, apps a
WHERE LOWER(u.email) = LOWER('$($emailEscaped)') AND a.app_id = '$($AppId -replace "'","''")'
ON CONFLICT (user_id, app_id) DO UPDATE SET role = EXCLUDED.role, granted_at = EXCLUDED.granted_at, granted_by = EXCLUDED.granted_by;
"@
                Invoke-PostgreSqlQuery -Host $DbHost -Port $DbPort -User $DbUser -Password $DbPassword `
                    -Database $DbName -Query $permSql -Unattended -ErrorAction SilentlyContinue | Out-Null
                Write-LogMessage "  Admin synced: $($email) -> $($AppId)/$($HighestRole), global_access_level=3" -Level INFO
            }
            else {
                Write-LogMessage "  Admin global_access_level synced: $($email)" -Level INFO
            }
        }
    }
    catch {
        Write-LogMessage "Admin sync failed: $($_.Exception.Message)" -Level WARN
    }
}

function Register-AppInDedgeAuthDb {
    <#
    .SYNOPSIS
        Registers or updates an app in the DedgeAuth database using data from a deploy profile's DedgeAuth block.
        Called from Deploy-IISSite as Step 3.5.
    .DESCRIPTION
        - Calls Register-DedgeAuthApp.ps1 (UPSERT always runs, idempotent)
        - Then calls Sync-DedgeAuthAdminEmails to ensure admin emails have top privileges
        Non-fatal: logs warnings on failure and returns $false; caller continues.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'DbPassword', Justification = 'psql PGPASSWORD requires plain string')]
    param(
        [hashtable]$DedgeAuthBlock,
        [string]$RegisterScriptPath,
        [string]$DbHost,
        [int]$DbPort = 8432,
        [string]$DbName = "DedgeAuth",
        [string]$DbUser = "postgres",
        [string]$DbPassword = "postgres"
    )

    if (-not $DedgeAuthBlock -or -not $DedgeAuthBlock.AppId) {
        Write-LogMessage "No DedgeAuth.AppId in profile — skipping DedgeAuth registration" -Level DEBUG
        return $false
    }

    if (-not (Test-Path $RegisterScriptPath)) {
        Write-LogMessage "Register-DedgeAuthApp.ps1 not found at '$($RegisterScriptPath)' — skipping DedgeAuth registration" -Level WARN
        return $false
    }

    $appId = $DedgeAuthBlock.AppId
    $displayName = if ($DedgeAuthBlock.DisplayName) { $DedgeAuthBlock.DisplayName } else { $appId }
    $description = if ($DedgeAuthBlock.Description) { $DedgeAuthBlock.Description } else { "" }
    $roles = if ($DedgeAuthBlock.Roles) { @($DedgeAuthBlock.Roles) }     else { @("User", "Admin") }
    $tenants = if ($DedgeAuthBlock.TenantDomains) { @($DedgeAuthBlock.TenantDomains) } else { @() }

    # Expand $env:COMPUTERNAME in BaseUrl if present
    $baseUrl = if ($DedgeAuthBlock.BaseUrl) { $DedgeAuthBlock.BaseUrl } else { "http://$($env:COMPUTERNAME)/$($appId)" }
    $baseUrl = $ExecutionContext.InvokeCommand.ExpandString($baseUrl)

    # Highest role = last in array (convention: escalating privileges order)
    $highestRole = if ($roles.Count -gt 0) { $roles[-1] } else { "Admin" }

    # Extract Groups field for app group placement (optional)
    $groups = if ($DedgeAuthBlock.Groups) { $DedgeAuthBlock.Groups } else { $null }

    Write-LogMessage "--- Step 3.5: DedgeAuth DB registration for '$($appId)' ---" -Level INFO
    Write-LogMessage "  BaseUrl: $($baseUrl) | Roles: $($roles -join ', ') | Tenants: $($tenants -join ', ')" -Level INFO

    try {
        $registerArgs = @{
            DbHost         = $DbHost
            DbPort         = $DbPort
            DbName         = $DbName
            DbUser         = $DbUser
            DbPassword     = $DbPassword
            AppId          = $appId
            DisplayName    = $displayName
            Description    = $description
            BaseUrl        = $baseUrl
            Roles          = $roles
            TenantDomains  = $tenants
            PermissionMode = "admins"
            PermissionRole = $highestRole
            Unattended     = $true
        }
        if ($groups) {
            $registerArgs['GroupsJson'] = ($groups | ConvertTo-Json -Compress)
        }
        & $RegisterScriptPath @registerArgs

        Write-LogMessage "DedgeAuth app '$($appId)' registered/updated in database" -Level INFO
    }
    catch {
        Write-LogMessage "DedgeAuth app registration failed: $($_.Exception.Message)" -Level WARN
        return $false
    }

    # Sync admin email privileges
    Sync-DedgeAuthAdminEmails -AppId $appId -DbHost $DbHost -DbPort $DbPort -DbName $DbName `
        -DbUser $DbUser -DbPassword $DbPassword -HighestRole $highestRole

    return $true
}

function Deploy-IISSite {

  
    param(
        [Parameter(Mandatory = $false)]
        [string]$SiteName = "",

        [Parameter(Mandatory = $false)]
        [string]$PhysicalPath = $null,

        [Parameter(Mandatory = $false)]
        [ValidateSet("AspNetCore", "Static", "Undetermined")]
        [string]$AppType = "Undetermined",

        [Parameter(Mandatory = $false)]
        [string]$DotNetDll = $null,

        [Parameter(Mandatory = $false)]
        [string]$AppPoolName = $null,

        [Parameter(Mandatory = $false)]
        [ValidateSet("WinApp", "PshApp", "None", "Undetermined")]
        [string]$InstallSource = "Undetermined",

        [Parameter(Mandatory = $false)]
        [string]$InstallAppName = $null,

        [Parameter(Mandatory = $false)]
        [string]$VirtualPath = $null,

        [Parameter(Mandatory = $false)]
        [string]$ParentSite = $null,

        [Parameter(Mandatory = $false)]
        [string]$HealthEndpoint = $null,

        [Parameter(Mandatory = $false)]
        [bool]$EnableDirectoryBrowsing = $true,

        [Parameter(Mandatory = $false)]
        [int]$ApiPort = 0,

        # Optional array of additional ports that need firewall rules.
        # Each entry: @{ Port = [int]; Description = [string]; Direction = [string] }
        # Direction: "Inbound", "Outbound", or "Both" (default: "Both").
        [Parameter(Mandatory = $false)]
        [array]$AdditionalPorts = @(),

        # Optional array of additional WinApp names to install alongside the main app.
        # Each entry is a string app name passed to Install-OurWinApp (e.g. "GenericLogHandler-Agent").
        [Parameter(Mandatory = $false)]
        [string[]]$AdditionalWinApps = @(),

        [Parameter(Mandatory = $false)]
        [string]$TemplatesPath = $null,

        # Optional path to a permissions JSON template (absolute, or relative to the deploy template directory).
        # When set, permissions in that file are applied to PhysicalPath during Step 6 instead of the default rule.
        # Format: same as Export-FolderPermissions.ps1 output -- JSON with an "Entries" array.
        [Parameter(Mandatory = $false)]
        [string]$PermissionsTemplatePath = $null,

        # Optional path to Register-DedgeAuthApp.ps1. When set (or auto-resolved), used in Step 3.5
        # to register/update the app in the DedgeAuth database after file installation.
        # Defaults to the sibling DedgeAuth-AddAppSupport folder relative to IIS-DeployApp scripts.
        [Parameter(Mandatory = $false)]
        [string]$DedgeAuthRegisterScriptPath = "",

        # When true, enables Anonymous Authentication and disables Windows Authentication
        # on the virtual app path so the site is publicly accessible without credentials.
        # Default is $false (inherits parent site auth settings, typically Windows Auth).
        [Parameter(Mandatory = $false)]
        [bool]$AllowAnonymousAccess = $false,

        # When $true, enables Windows Authentication on the virtual app (required for
        # ASP.NET Core Negotiate handler). Use for apps that need SSO via Negotiate.
        # When combined with AllowAnonymousAccess=$false, both Anonymous and Windows Auth
        # are enabled so the app can serve public pages AND handle Negotiate SSO.
        [Parameter(Mandatory = $false)]
        [bool]$WindowsAuthentication = $false,

        # When $true, skips Step 10 (health check). Use for MCP/SSE servers and apps
        # that don't expose standard HTTP endpoints for health verification.
        [Parameter(Mandatory = $false)]
        [bool]$SkipHealthCheck = $false
    )
    
    $ErrorActionPreference = "Stop"
    $script:IsRootSiteProfile = $false
    $script:HasError = $false
    $script:ProfileDedgeAuthBlock = $null

    $appcmd = "$($env:SystemRoot)\System32\inetsrv\appcmd.exe"

    # ═══════════════════════════════════════════════════════════════════════════════
    # PROFILE SUPPORT
    # ═══════════════════════════════════════════════════════════════════════════════
    # Profiles are saved as JSON in a shared network folder.
    # Bundled profiles and assets (DefaultWebSite-index.html) are in the deployed app templates folder.
    # Caller can pass -TemplatesPath to load templates from the source/script folder.
    # A special "DefaultWebSite" profile (IsRootSiteProfile=true) bootstraps the root site.

    $profileDir = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\Config\IIS-DeployApp"
    $bundledProfileDir = "$($env:OptPath)\DedgePshApps\IIS-DeployApp\templates"
    $callerTemplatesDir = if ($TemplatesPath -and (Test-Path $TemplatesPath)) { $TemplatesPath } else { $null }

    # Helper: run appcmd, log output, return output string, optionally fail on ERROR


    # ═══════════════════════════════════════════════════════════════════════════════
    # PROFILE PICKER (when SiteName is not explicitly provided)
    # ═══════════════════════════════════════════════════════════════════════════════
    if (-not $PSBoundParameters.ContainsKey('SiteName') -or [string]::IsNullOrWhiteSpace($SiteName)) {
        $availableProfiles = Get-DeployProfiles

        if ($availableProfiles.Count -gt 0) {
            Write-Host ""
            Write-Host "IIS Site Deployment" -ForegroundColor Cyan
            Write-Host "───────────────────────────────────────" -ForegroundColor DarkGray

            # Show current IIS configuration: Sites first, then Apps
            Show-IISOverview -OutputTarget Host

            Write-Host ""
            Write-Host "───────────────────────────────────────" -ForegroundColor DarkGray
            # Split profiles into two separate lists
            $templateProfiles = @($availableProfiles | Where-Object { $_.IsTemplate })
            $savedProfiles = @($availableProfiles | Where-Object { -not $_.IsTemplate })

            $i = 1

            # ── List 1: Bundled Templates ───────────────────────────────────────
            Write-Host ""
            Write-Host "  Bundled Templates:" -ForegroundColor Yellow
            if ($templateProfiles.Count -eq 0) {
                Write-Host "    (none)" -ForegroundColor DarkGray
            }
            else {
                $lastWasSite = $null
                foreach ($p in $templateProfiles) {
                    $isSite = $p.IsRootSiteProfile
                    if ($null -ne $lastWasSite -and $lastWasSite -and -not $isSite) { Write-Host "" }
                    $lastWasSite = $isSite

                    $typeLabel = if ($isSite) { "[Site]" } else { "[App] " }
                    $lastUsed = if ($p.LastUsed) { " (last: $($p.LastUsed))" } else { "" }

                    # Color: Green if previously deployed, Yellow if never deployed
                    if ($p.HasBeenDeployed) {
                        $color = "Green"
                        $tag = " [deployed]"
                    }
                    else {
                        $color = "Yellow"
                        $tag = " [new]"
                    }

                    Write-Host "  $($i)) $typeLabel $($p.Name) ($($p.AppType), $($p.Source))$($tag)$($lastUsed)" -ForegroundColor $color
                    $i++
                }
            }

            # ── List 2: Deployed Profiles (saved on network share) ──────────────
            Write-Host ""
            Write-Host "  Deployed Profiles:" -ForegroundColor Yellow
            if ($savedProfiles.Count -eq 0) {
                Write-Host "    (none -- no saved profiles outside of templates)" -ForegroundColor DarkGray
            }
            else {
                $lastWasSite = $null
                foreach ($p in $savedProfiles) {
                    $isSite = $p.IsRootSiteProfile
                    if ($null -ne $lastWasSite -and $lastWasSite -and -not $isSite) { Write-Host "" }
                    $lastWasSite = $isSite

                    $typeLabel = if ($isSite) { "[Site]" } else { "[App] " }
                    $color = if ($isSite) { "Cyan" } else { "White" }
                    $lastUsed = if ($p.LastUsed) { " (last: $($p.LastUsed))" } else { "" }

                    Write-Host "  $($i)) $typeLabel $($p.Name) ($($p.AppType), $($p.Source))$($lastUsed)" -ForegroundColor $color
                    $i++
                }
            }
            Write-Host "  $($i)) Enter new site name manually" -ForegroundColor Gray
            Write-Host ""
            $profileChoice = Read-Host "Choose profile [1]"
            if ([string]::IsNullOrWhiteSpace($profileChoice)) { $profileChoice = "1" }

            $choiceNum = 0
            if ([int]::TryParse($profileChoice, [ref]$choiceNum) -and $choiceNum -ge 1 -and $choiceNum -le $availableProfiles.Count) {
                $selectedProfile = $availableProfiles[$choiceNum - 1]
                Write-LogMessage "Loading profile: $($selectedProfile.Name) from $($selectedProfile.File)" -Level INFO
                $profileData = Import-DeployProfile -FilePath $selectedProfile.File

                if (-not $PSBoundParameters.ContainsKey('SiteName')) { $SiteName = $profileData.SiteName }
                if (-not $PSBoundParameters.ContainsKey('PhysicalPath')) { $PhysicalPath = $profileData.PhysicalPath }
                if (-not $PSBoundParameters.ContainsKey('AppType')) { $AppType = $profileData.AppType }
                if (-not $PSBoundParameters.ContainsKey('DotNetDll')) { $DotNetDll = $profileData.DotNetDll }
                if (-not $PSBoundParameters.ContainsKey('AppPoolName')) { $AppPoolName = $profileData.AppPoolName }
                if (-not $PSBoundParameters.ContainsKey('InstallSource')) { $InstallSource = $profileData.InstallSource }
                if (-not $PSBoundParameters.ContainsKey('InstallAppName')) { $InstallAppName = $profileData.InstallAppName }
                if (-not $PSBoundParameters.ContainsKey('VirtualPath')) { $VirtualPath = if ($profileData.VirtualPath) { $profileData.VirtualPath } else { "" } }
                if (-not $PSBoundParameters.ContainsKey('ParentSite')) { $ParentSite = $profileData.ParentSite }
                if (-not $PSBoundParameters.ContainsKey('HealthEndpoint')) { $HealthEndpoint = if ($profileData.HealthEndpoint) { $profileData.HealthEndpoint } else { "" } }
                if (-not $PSBoundParameters.ContainsKey('EnableDirectoryBrowsing') -and $profileData.EnableDirectoryBrowsing -eq $true) { $EnableDirectoryBrowsing = [switch]$true }
                if (-not $PSBoundParameters.ContainsKey('ApiPort') -and $profileData.ApiPort) { $ApiPort = [int]$profileData.ApiPort }
                if (-not $PSBoundParameters.ContainsKey('AdditionalPorts') -and $profileData.AdditionalPorts) { $AdditionalPorts = @($profileData.AdditionalPorts) }
                if (-not $PSBoundParameters.ContainsKey('AdditionalWinApps') -and $profileData.AdditionalWinApps) { $AdditionalWinApps = @($profileData.AdditionalWinApps) }
                if ($profileData.IsRootSiteProfile -eq $true) { $script:IsRootSiteProfile = $true }
                if (-not $PSBoundParameters.ContainsKey('AllowAnonymousAccess') -and $profileData.AllowAnonymousAccess -eq $true) { $AllowAnonymousAccess = $true }
                if (-not $PSBoundParameters.ContainsKey('WindowsAuthentication') -and $profileData.WindowsAuthentication -eq $true) { $WindowsAuthentication = $true }
                if (-not $PSBoundParameters.ContainsKey('SkipHealthCheck') -and $profileData.SkipHealthCheck -eq $true) { $SkipHealthCheck = $true }
                if (-not $PermissionsTemplatePath -and $profileData.PermissionsTemplatePath) {
                    $ptRaw = $profileData.PermissionsTemplatePath
                    if ([System.IO.Path]::IsPathRooted($ptRaw)) {
                        $PermissionsTemplatePath = $ptRaw
                    }
                    else {
                        $PermissionsTemplatePath = Join-Path (Split-Path $selectedProfile.File -Parent) $ptRaw
                    }
                }

                if ($profileData.DedgeAuth) { $script:ProfileDedgeAuthBlock = $profileData.DedgeAuth }
                $script:LoadedFromProfile = $true
            }
            else {
                $SiteName = Read-Host "Site name"
                if ([string]::IsNullOrWhiteSpace($SiteName)) {
                    Write-LogMessage "Site name is required. Exiting." -Level ERROR
                    exit 1
                }
            }
        }
        else {
            Write-Host ""
            Write-Host "IIS Site Deployment - Interactive Setup" -ForegroundColor Cyan
            Write-Host "───────────────────────────────────────" -ForegroundColor DarkGray
            Write-Host ""
            $inputSite = Read-Host "Site name"
            if ([string]::IsNullOrWhiteSpace($inputSite)) {
                Write-LogMessage "Site name is required. Exiting." -Level ERROR
                exit 1
            }
            $SiteName = $inputSite
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # AUTO-LOAD TEMPLATE (when SiteName is provided but no profile was loaded yet)
    # ═══════════════════════════════════════════════════════════════════════════════
    if (-not $script:LoadedFromProfile -and -not [string]::IsNullOrWhiteSpace($SiteName)) {
        # Search for a matching template by SiteName in caller templates, bundled templates, then saved profiles
        $templateFile = $null
        $searchDirs = @()
        if ($callerTemplatesDir) { $searchDirs += $callerTemplatesDir }
        if (Test-Path $bundledProfileDir -ErrorAction SilentlyContinue) { $searchDirs += $bundledProfileDir }
        if (Test-Path $profileDir -ErrorAction SilentlyContinue) { $searchDirs += $profileDir }

        foreach ($dir in $searchDirs) {
            $candidates = Get-ChildItem -Path $dir -Filter "*.deploy.json" -File -ErrorAction SilentlyContinue
            foreach ($f in $candidates) {
                try {
                    $json = Get-Content $f.FullName -Raw | ConvertFrom-Json
                    if ($json.SiteName -eq $SiteName) {
                        $templateFile = $f.FullName
                        break
                    }
                }
                catch { }
            }
            if ($templateFile) { break }
        }

        if ($templateFile) {
            Write-LogMessage "Auto-loaded template for '$($SiteName)': $($templateFile)" -Level INFO
            $profileData = Import-DeployProfile -FilePath $templateFile

            if (-not $PSBoundParameters.ContainsKey('PhysicalPath')) { $PhysicalPath = $profileData.PhysicalPath }
            if (-not $PSBoundParameters.ContainsKey('AppType')) { $AppType = $profileData.AppType }
            if (-not $PSBoundParameters.ContainsKey('DotNetDll')) { $DotNetDll = $profileData.DotNetDll }
            if (-not $PSBoundParameters.ContainsKey('AppPoolName')) { $AppPoolName = $profileData.AppPoolName }
            if (-not $PSBoundParameters.ContainsKey('InstallSource')) { $InstallSource = $profileData.InstallSource }
            if (-not $PSBoundParameters.ContainsKey('InstallAppName')) { $InstallAppName = $profileData.InstallAppName }
            if (-not $PSBoundParameters.ContainsKey('VirtualPath')) { $VirtualPath = if ($profileData.VirtualPath) { $profileData.VirtualPath } else { "" } }
            if (-not $PSBoundParameters.ContainsKey('ParentSite')) { $ParentSite = $profileData.ParentSite }
            if (-not $PSBoundParameters.ContainsKey('HealthEndpoint')) { $HealthEndpoint = if ($profileData.HealthEndpoint) { $profileData.HealthEndpoint } else { "" } }
            if (-not $PSBoundParameters.ContainsKey('EnableDirectoryBrowsing') -and $profileData.EnableDirectoryBrowsing -eq $true) { $EnableDirectoryBrowsing = [switch]$true }
            if (-not $PSBoundParameters.ContainsKey('ApiPort') -and $profileData.ApiPort) { $ApiPort = [int]$profileData.ApiPort }
            if (-not $PSBoundParameters.ContainsKey('AdditionalPorts') -and $profileData.AdditionalPorts) { $AdditionalPorts = @($profileData.AdditionalPorts) }
            if (-not $PSBoundParameters.ContainsKey('AdditionalWinApps') -and $profileData.AdditionalWinApps) { $AdditionalWinApps = @($profileData.AdditionalWinApps) }
            if ($profileData.IsRootSiteProfile -eq $true) { $script:IsRootSiteProfile = $true }
            if (-not $PSBoundParameters.ContainsKey('AllowAnonymousAccess') -and $profileData.AllowAnonymousAccess -eq $true) { $AllowAnonymousAccess = $true }
            if (-not $PSBoundParameters.ContainsKey('WindowsAuthentication') -and $profileData.WindowsAuthentication -eq $true) { $WindowsAuthentication = $true }
            if (-not $PSBoundParameters.ContainsKey('SkipHealthCheck') -and $profileData.SkipHealthCheck -eq $true) { $SkipHealthCheck = $true }
            if (-not $PermissionsTemplatePath -and $profileData.PermissionsTemplatePath) {
                $ptRaw = $profileData.PermissionsTemplatePath
                if ([System.IO.Path]::IsPathRooted($ptRaw)) {
                    $PermissionsTemplatePath = $ptRaw
                }
                else {
                    $PermissionsTemplatePath = Join-Path (Split-Path $templateFile -Parent) $ptRaw
                }
            }

            if ($profileData.DedgeAuth) { $script:ProfileDedgeAuthBlock = $profileData.DedgeAuth }
            $script:LoadedFromProfile = $true
        }
        else {
            # Require a matching template when -SiteName is passed; list available templates
            $availableSiteNames = [System.Collections.Generic.List[string]]::new()
            foreach ($dir in $searchDirs) {
                $candidates = Get-ChildItem -Path $dir -Filter "*.deploy.json" -File -ErrorAction SilentlyContinue
                foreach ($f in $candidates) {
                    try {
                        $json = Get-Content $f.FullName -Raw | ConvertFrom-Json
                        if ($json.SiteName -and -not $availableSiteNames.Contains($json.SiteName)) {
                            $availableSiteNames.Add($json.SiteName)
                        }
                    }
                    catch { }
                }
            }
            $availableSiteNames.Sort()
            $templateList = if ($availableSiteNames.Count -gt 0) { $availableSiteNames -join ", " } else { "(none found)" }
            $templatesPathDesc = if ($callerTemplatesDir) { $callerTemplatesDir } else { $bundledProfileDir }
            Write-LogMessage "No deploy template found for SiteName '$($SiteName)'. Templates path: $templatesPathDesc. Available SiteNames: $templateList" -Level ERROR
            throw "No deploy template found for SiteName '$SiteName'. Use one of: $templateList (or run without -SiteName to pick interactively)."
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # RESOLVE DEFAULTS
    # ═══════════════════════════════════════════════════════════════════════════════

    # Resolve %OPTPATH% token in PhysicalPath (used by DefaultWebSite template)
    if ($PhysicalPath -match '%OPTPATH%') {
        $PhysicalPath = $PhysicalPath -replace '%OPTPATH%', $env:OptPath
        Write-LogMessage "Resolved PhysicalPath token: $PhysicalPath" -Level DEBUG
    }

    if ([string]::IsNullOrWhiteSpace($AppPoolName)) {
        $AppPoolName = $SiteName
    }

    # Default VirtualPath to /$SiteName if not set
    if ([string]::IsNullOrWhiteSpace($VirtualPath)) {
        $VirtualPath = "/$SiteName"
    }

    # Normalize virtual path
    $VirtualPath = $VirtualPath.TrimEnd('/')
    if (-not $VirtualPath.StartsWith('/')) { $VirtualPath = "/$VirtualPath" }

    # ── LOAD PERMISSION ENTRIES ───────────────────────────────────────────────────
    # If PermissionsTemplatePath is set (from profile or parameter), resolve and load entries now.
    # The loaded entries are applied in Step 6 (and for the root site permissions block).
    $permissionEntries = $null
    if ($PermissionsTemplatePath) {
        if (Test-Path $PermissionsTemplatePath) {
            try {
                $permJson = Get-Content $PermissionsTemplatePath -Raw | ConvertFrom-Json
                $permissionEntries = @($permJson.Entries)
                Write-LogMessage "Loaded $($permissionEntries.Count) permission entries from: $(Split-Path $PermissionsTemplatePath -Leaf)" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to parse permissions template '$($PermissionsTemplatePath)': $($_.Exception.Message)" -Level WARN
            }
        }
        else {
            Write-LogMessage "Permissions template not found: $($PermissionsTemplatePath)" -Level WARN
        }
    }

    # ── ROOT PROTECTION ──────────────────────────────────────────────────────────
    # Only the DefaultWebSite profile (IsRootSiteProfile=true) can deploy to /
    if ($VirtualPath -eq "/" -and -not $script:IsRootSiteProfile) {
        Write-LogMessage "Cannot deploy to root (/) of '$ParentSite'. The root is reserved for the DefaultWebSite profile. Use a virtual path like /$SiteName instead." -Level ERROR
        exit 1
    }

    # Interactive prompts (skip if loaded from profile)
    if (-not $script:LoadedFromProfile) {

        if (-not $PSBoundParameters.ContainsKey('AppType') -and $SiteName -ne "DedgeAuth") {
            Write-Host ""
            Write-Host "App type:" -ForegroundColor Yellow
            Write-Host "  1) AspNetCore  - .NET app with in-process hosting (e.g. DedgeAuth)" -ForegroundColor White
            Write-Host "  2) Static      - HTML/CSS/JS files served by IIS (e.g. AutoDoc)" -ForegroundColor White
            $typeChoice = Read-Host "Choose [1]"
            if ($typeChoice -eq "2") { $AppType = "Static" }
        }

        if (-not $PSBoundParameters.ContainsKey('InstallSource') -and $SiteName -ne "DedgeAuth") {
            Write-Host ""
            Write-Host "Install source:" -ForegroundColor Yellow
            Write-Host "  1) WinApp  - Deploy via Install-OurWinApp (from DedgeWinApps staging)" -ForegroundColor White
            Write-Host "  2) PshApp  - Deploy via Install-OurPshApp (from DedgePshApps staging)" -ForegroundColor White
            Write-Host "  3) None    - Skip install, use existing files at PhysicalPath" -ForegroundColor White
            $srcChoice = Read-Host "Choose [1]"
            switch ($srcChoice) {
                "2" { $InstallSource = "PshApp" }
                "3" { $InstallSource = "None" }
            }
        }

        if ([string]::IsNullOrWhiteSpace($InstallAppName)) {
            $InstallAppName = $SiteName
        }

        if (-not $PSBoundParameters.ContainsKey('PhysicalPath') -or [string]::IsNullOrWhiteSpace($PhysicalPath)) {
            switch ($InstallSource) {
                "WinApp" { $PhysicalPath = "$($env:OptPath)\DedgeWinApps\$InstallAppName" }
                "PshApp" { $PhysicalPath = "$($env:OptPath)\DedgePshApps\$InstallAppName" }
                "None" {
                    $inputPath = Read-Host "Physical path (required for InstallSource=None)"
                    if ([string]::IsNullOrWhiteSpace($inputPath)) {
                        Write-LogMessage "Physical path is required when InstallSource is None. Exiting." -Level ERROR
                        exit 1
                    }
                    $PhysicalPath = $inputPath
                }
            }
        }
    }

    # For AspNetCore, auto-detect or prompt for DLL
    if ($AppType -eq "AspNetCore" -and [string]::IsNullOrWhiteSpace($DotNetDll)) {
        if (Test-Path $PhysicalPath) {
            $dlls = Get-ChildItem -Path $PhysicalPath -Filter "*.dll" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '\.(Api|Web|Server|App)\.dll$' } |
            Select-Object -First 1
            if ($dlls) {
                $DotNetDll = $dlls.Name
                Write-LogMessage "Auto-detected DLL: $DotNetDll" -Level INFO
            }
        }
        if ([string]::IsNullOrWhiteSpace($DotNetDll)) {
            $DotNetDll = Read-Host "ASP.NET Core DLL name (e.g. MyApp.Api.dll)"
            if ([string]::IsNullOrWhiteSpace($DotNetDll)) {
                Write-LogMessage "DLL name is required for AspNetCore apps. Exiting." -Level ERROR
                exit 1
            }
        }
    }

    # ═══════════════════════════════════════════════════════════════════════════════
    # PREFLIGHT
    # ═══════════════════════════════════════════════════════════════════════════════
    if (-not (Test-Path $appcmd)) {
        Write-LogMessage "appcmd.exe not found at $appcmd -- IIS is not installed" -Level ERROR
        exit 1
    }

    # ── Ensure W3SVC and WAS services are running BEFORE any appcmd calls ─────
    foreach ($svcName in @('WAS', 'W3SVC')) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-LogMessage "Service '$svcName' not found -- IIS may not be installed" -Level ERROR
            exit 1
        }
        if ($svc.Status -ne 'Running') {
            Write-LogMessage "Service '$svcName' is $($svc.Status) -- starting..." -Level WARN
            try {
                Start-Service -Name $svcName -ErrorAction Stop
                Start-Sleep -Seconds 2
                Write-LogMessage "Service '$svcName' started successfully" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to start '$svcName': $($_.Exception.Message). IIS may be non-functional." -Level ERROR
            }
        }
    }

    # Check if parent site exists -- root profile always tears down and recreates
    $parentCheck = & $appcmd list site "$ParentSite" 2>&1 | Out-String
    Write-LogMessage "appcmd list site '$($ParentSite)' returned: $($parentCheck.Trim())" -Level DEBUG
    if ($script:IsRootSiteProfile) {
        # ── TEARDOWN existing site completely before recreating ──────────────────
        if ($parentCheck -match 'SITE "') {
            Write-LogMessage "Tearing down existing '$ParentSite' for clean recreate..." -Level INFO

            # List and delete all applications (children first by longest path, then root)
            $appList = & $appcmd list app /site.name:"$ParentSite" 2>&1 | Out-String
            $appIds = [System.Collections.ArrayList]@()
            foreach ($line in ($appList -split "`n")) {
                if ($line.Trim() -match '^APP "([^"]+)"') { $null = $appIds.Add($matches[1]) }
            }
            $sortedIds = @($appIds | Sort-Object { - $_.Length })
            foreach ($appId in $sortedIds) {
                Write-LogMessage "  Deleting app: $appId" -Level INFO
                try {
                    & $appcmd delete app /app.name:"$appId" 2>&1 | Out-Null
                }
                catch {
                    Write-LogMessage "  Could not delete app '$($appId)' (continuing): $_" -Level WARN
                }
            }

            # Stop and delete the site
            & $appcmd stop site "$ParentSite" 2>&1 | Out-Null
            Start-Sleep -Seconds 1
            $delResult = & $appcmd delete site /site.name:"$ParentSite" 2>&1 | Out-String
            if ($delResult -match "deleted") {
                Write-LogMessage "'$ParentSite' removed" -Level INFO
            }
            else {
                Write-LogMessage "Site delete result: $($delResult.Trim())" -Level WARN
            }
        }

        # ── CREATE app pool FIRST so the site never references a missing pool ──
        $poolCheck = & $appcmd list apppool "$AppPoolName" 2>&1 | Out-String
        if ($poolCheck -notmatch 'APPPOOL "') {
            Write-LogMessage "Creating app pool '$AppPoolName' (before site creation)..." -Level INFO
            & $appcmd add apppool "/name:$AppPoolName" 2>&1 | Out-Null
        }
        & $appcmd set apppool "$AppPoolName" /managedRuntimeVersion: /managedPipelineMode:Integrated 2>&1 | Out-Null
        Write-LogMessage "App pool '$AppPoolName' ready (no managed runtime, Integrated)" -Level INFO

        # ── CREATE fresh site pointing to $PhysicalPath ─────────────────────────
        Write-LogMessage "Creating '$ParentSite' at $PhysicalPath with binding *:80" -Level INFO
        if (-not (Test-Path $PhysicalPath)) {
            New-Item -ItemType Directory -Path $PhysicalPath -Force | Out-Null
            Write-LogMessage "Created directory: $PhysicalPath" -Level INFO
        }
        $createResult = & $appcmd add site "/name:$ParentSite" "/physicalPath:$PhysicalPath" "/bindings:http/*:80:" 2>&1 | Out-String
        if ($createResult -match "ERROR") {
            Write-LogMessage "Failed to create '$($ParentSite)': $($createResult.Trim())" -Level ERROR
            exit 1
        }
        Write-LogMessage "'$ParentSite' created fresh with binding *:80" -Level INFO

        # ── Immediately assign the app pool to the root application ─────────────
        # This prevents the site from going to 'Unknown' state if DefaultAppPool is missing
        $assignResult = & $appcmd set app "$ParentSite/" "/applicationPool:$AppPoolName" 2>&1 | Out-String
        if ($assignResult -match "ERROR") {
            Write-LogMessage "Warning: Could not assign pool to root app: $($assignResult.Trim())" -Level WARN
        }
        else {
            Write-LogMessage "Root app '/' immediately assigned to pool '$AppPoolName'" -Level INFO
        }

        # ── Verify site state right after creation ──────────────────────────────
        $postCreateState = (& $appcmd list site "$ParentSite" /text:state 2>&1).Trim()
        if ($postCreateState -eq "Unknown") {
            Write-LogMessage "Site '$ParentSite' is in Unknown state after creation! Attempting recovery..." -Level WARN
            # Re-check root app pool assignment
            $rootAppInfo = & $appcmd list app "$ParentSite/" 2>&1 | Out-String
            Write-LogMessage "Root app info: $($rootAppInfo.Trim())" -Level DEBUG
            & $appcmd set app "$ParentSite/" "/applicationPool:$AppPoolName" 2>&1 | Out-Null
            Start-Sleep -Seconds 1
            $retryState = (& $appcmd list site "$ParentSite" /text:state 2>&1).Trim()
            Write-LogMessage "Site state after recovery attempt: $retryState" -Level INFO
        }
        else {
            Write-LogMessage "Site '$ParentSite' post-creation state: $postCreateState" -Level INFO
        }
    }
    elseif ($parentCheck -notmatch 'SITE "') {
        Write-LogMessage "Parent site '$ParentSite' does not exist (appcmd returned: '$($parentCheck.Trim())'). Run the DefaultWebSite profile first to create it." -Level ERROR
        exit 1
    }

    # ── AUTO-RECOVER: Parent site in 'Unknown' state ─────────────────────────
    # The 'Unknown' state occurs when the root application '/' is missing or
    # references a non-existent app pool. This blocks all virtual apps from
    # serving traffic (hresult:800710d8). Attempt a targeted fix before proceeding.
    $parentPreflightState = (& $appcmd list site "$ParentSite" /text:state 2>&1).Trim()
    if ($parentPreflightState -eq "Unknown") {
        Write-LogMessage "Parent site '$ParentSite' is in 'Unknown' state -- attempting auto-recovery..." -Level WARN

        # 1. Ensure a usable app pool exists for the root site
        $rootPoolName = "DefaultWebSite"
        $rootPoolCheck = & $appcmd list apppool "$rootPoolName" 2>&1 | Out-String
        if ($rootPoolCheck -notmatch 'APPPOOL "') {
            Write-LogMessage "Creating app pool '$rootPoolName' for root site" -Level INFO
            & $appcmd add apppool "/name:$rootPoolName" 2>&1 | Out-Null
            & $appcmd set apppool "$rootPoolName" /managedRuntimeVersion: /managedPipelineMode:Integrated 2>&1 | Out-Null
        }

        # 2. Ensure root application '/' exists with a valid physical path
        $rootAppCheck = & $appcmd list app "$ParentSite/" 2>&1 | Out-String
        if ($rootAppCheck -notmatch 'APP "') {
            $rootPhysPath = Join-Path $env:OptPath "Webs\DefaultWebSite"
            if (-not (Test-Path $rootPhysPath)) {
                New-Item -ItemType Directory -Path $rootPhysPath -Force | Out-Null
            }
            Write-LogMessage "Re-creating root application '/' at $rootPhysPath" -Level INFO
            & $appcmd add app "/site.name:$ParentSite" /path:/ "/physicalPath:$rootPhysPath" 2>&1 | Out-Null
        }

        # 3. Assign the app pool to the root application
        & $appcmd set app "$ParentSite/" "/applicationPool:$rootPoolName" 2>&1 | Out-Null
        Write-LogMessage "Root app '/' assigned to pool '$rootPoolName'" -Level INFO

        # 4. Copy redirect index.html if available (from caller or bundled templates)
        $rootPhysFromVdir = ""
        $rootVdirInfo = & $appcmd list vdir "$ParentSite/" 2>&1 | Out-String
        if ($rootVdirInfo -match 'physicalPath:([^\s\)]+)') { $rootPhysFromVdir = $matches[1] }
        if (-not [string]::IsNullOrWhiteSpace($rootPhysFromVdir) -and (Test-Path $rootPhysFromVdir)) {
            $indexTarget = Join-Path $rootPhysFromVdir "index.html"
            if (-not (Test-Path $indexTarget)) {
                $indexSource = $null
                if ($callerTemplatesDir) {
                    $candidate = Join-Path $callerTemplatesDir "DefaultWebSite-index.html"
                    if (Test-Path $candidate) { $indexSource = $candidate }
                }
                if (-not $indexSource -and (Test-Path $bundledProfileDir -ErrorAction SilentlyContinue)) {
                    $candidate = Join-Path $bundledProfileDir "DefaultWebSite-index.html"
                    if (Test-Path $candidate) { $indexSource = $candidate }
                }
                if ($indexSource) {
                    Copy-Item -Path $indexSource -Destination $indexTarget -Force
                    Write-LogMessage "Copied redirect index.html to $indexTarget" -Level INFO
                }
            }
        }

        # 5. Start pool and site
        & $appcmd start apppool "$rootPoolName" 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        & $appcmd start site "$ParentSite" 2>&1 | Out-Null
        Start-Sleep -Seconds 1

        # 6. Verify recovery succeeded
        $recoveredState = (& $appcmd list site "$ParentSite" /text:state 2>&1).Trim()
        if ($recoveredState -eq "Started") {
            Write-LogMessage "Auto-recovery successful -- '$ParentSite' is now in '$recoveredState' state" -Level INFO
        }
        else {
            Write-LogMessage "Auto-recovery failed -- '$ParentSite' still in state: $recoveredState" -Level ERROR
            Write-LogMessage "Run the full DefaultWebSite profile: .\IIS-DeployApp.ps1 -SiteName DefaultWebSite" -Level ERROR
            throw "Parent site '$ParentSite' is in '$recoveredState' state and auto-recovery failed"
        }
    }

    # Get parent site config and port for URL building
    $parentConfig = & $appcmd list site "$ParentSite" 2>&1 | Out-String
    $parentPort = 80
    if ($parentConfig -match ':(\d+):') { $parentPort = [int]$matches[1] }

    if (-not (Test-Path $PhysicalPath)) {
        Write-LogMessage "Physical path does not exist: $($PhysicalPath) -- creating it" -Level WARN
        New-Item -ItemType Directory -Path $PhysicalPath -Force | Out-Null
    }

    # Build base URL -- skip port for default HTTP (80)
    if ($parentPort -eq 80) {
        $baseUrl = "http://localhost$VirtualPath"
    }
    else {
        $baseUrl = "http://localhost:$($parentPort)$VirtualPath"
    }

    Write-LogMessage "===============================================================================" -Level INFO
    Write-LogMessage "IIS Deployment (appcmd.exe) -- virtual app under '$ParentSite'" -Level INFO
    Write-LogMessage "===============================================================================" -Level INFO
    Write-LogMessage "SiteName:     $SiteName" -Level INFO
    Write-LogMessage "AppPoolName:  $AppPoolName" -Level INFO
    Write-LogMessage "AppType:      $AppType" -Level INFO
    Write-LogMessage "InstallSrc:   $InstallSource$(if ($InstallSource -ne 'None') { " ($InstallAppName)" } else { '' })" -Level INFO
    Write-LogMessage "VirtualPath:  $VirtualPath" -Level INFO
    Write-LogMessage "PhysicalPath: $PhysicalPath" -Level INFO
    Write-LogMessage "ParentSite:   $ParentSite" -Level INFO
    if ($AllowAnonymousAccess) {
        Write-LogMessage "AnonAccess:   Enabled (public)" -Level INFO
    }
    if ($AppType -eq "AspNetCore") {
        Write-LogMessage "DotNetDll:    $DotNetDll" -Level INFO
        if (-not [string]::IsNullOrWhiteSpace($HealthEndpoint)) {
            Write-LogMessage "HealthCheck:  $HealthEndpoint" -Level INFO
        }
    }
    if ($ApiPort -gt 0) {
        Write-LogMessage "ApiPort:      $ApiPort" -Level INFO
    }
    if ($AdditionalPorts.Count -gt 0) {
        Write-LogMessage "AdditionalPorts:" -Level INFO
        foreach ($ap in $AdditionalPorts) {
            $apPort = if ($ap.Port) { $ap.Port } else { $ap }
            $apDesc = if ($ap.Description) { " - $($ap.Description)" } else { "" }
            $apDir = if ($ap.Direction) { " [$($ap.Direction)]" } else { " [Both]" }
            Write-LogMessage "  TCP $($apPort)$($apDesc)$($apDir)" -Level INFO
        }
    }
    if ($AdditionalWinApps.Count -gt 0) {
        Write-LogMessage "AdditionalWinApps:" -Level INFO
        foreach ($extraApp in $AdditionalWinApps) {
            Write-LogMessage "  $($extraApp)" -Level INFO
        }
    }
    if ($script:IsRootSiteProfile) {
        Write-LogMessage "Mode:         ROOT SITE BOOTSTRAP" -Level INFO
    }
    Write-LogMessage "===============================================================================" -Level INFO
    Write-LogMessage "" -Level INFO

    try {

        # ═══════════════════════════════════════════════════════════════════════════════
        # ROOT SITE BOOTSTRAP (special path for DefaultWebSite profile)
        # Site was already torn down and recreated fresh in the parent-check section.
        # This section: app pool, index.html, default documents, permissions, start, verify.
        # ═══════════════════════════════════════════════════════════════════════════════
        if ($script:IsRootSiteProfile) {
            Write-LogMessage "--- Root site bootstrap ---" -Level INFO

            # App pool was already created and assigned before site creation (see above).
            # Verify the pool exists and the root app assignment is correct.
            $poolVerify = & $appcmd list apppool "$AppPoolName" 2>&1 | Out-String
            if ($poolVerify -notmatch 'APPPOOL "') {
                Write-LogMessage "App pool '$AppPoolName' missing -- recreating..." -Level WARN
                & $appcmd add apppool "/name:$AppPoolName" 2>&1 | Out-Null
                & $appcmd set apppool "$AppPoolName" /managedRuntimeVersion: /managedPipelineMode:Integrated 2>&1 | Out-Null
            }
            Write-LogMessage "App pool '$AppPoolName' confirmed" -Level INFO

            # Ensure root app is on correct pool (idempotent)
            $assignResult = & $appcmd set app "$ParentSite/" "/applicationPool:$AppPoolName" 2>&1 | Out-String
            if ($assignResult -match "ERROR") {
                Write-LogMessage "Could not assign root app to pool: $($assignResult.Trim())" -Level WARN
            }
            else {
                Write-LogMessage "Root app '/' confirmed on pool '$AppPoolName'" -Level INFO
            }

            # ── Copy redirect index.html from caller templates or bundled ───────
            $bundledIndex = $null
            if ($callerTemplatesDir) {
                $candidate = Join-Path $callerTemplatesDir "DefaultWebSite-index.html"
                if (Test-Path $candidate) { $bundledIndex = $candidate }
            }
            if (-not $bundledIndex -and (Test-Path $bundledProfileDir)) {
                $candidate = Join-Path $bundledProfileDir "DefaultWebSite-index.html"
                if (Test-Path $candidate) { $bundledIndex = $candidate }
            }

            $targetIndex = Join-Path $PhysicalPath "index.html"
            if ($bundledIndex) {
                Copy-Item -Path $bundledIndex -Destination $targetIndex -Force
                Write-LogMessage "Copied redirect index.html to $targetIndex" -Level INFO
            }
            else {
                Write-LogMessage "DefaultWebSite-index.html not found in templates folders" -Level ERROR
                $script:HasError = $true
            }

            # ── Enable Anonymous Authentication (required for static redirect) ──
            Write-LogMessage "Enabling Anonymous Authentication for '$ParentSite'..." -Level INFO
            & $appcmd set config "$ParentSite" /section:anonymousAuthentication /enabled:true 2>&1 | Out-Null
            & $appcmd set config "$ParentSite" /section:anonymousAuthentication /userName:"" 2>&1 | Out-Null
            Write-LogMessage "Anonymous Authentication enabled (pass-through to app pool identity)" -Level INFO

            # ── Configure default document so IIS serves index.html at / ────────
            Write-LogMessage "Configuring default documents for '$ParentSite'..." -Level INFO
            & $appcmd set config "$ParentSite" /section:defaultDocument /enabled:true 2>&1 | Out-Null
            & $appcmd set config "$ParentSite" /section:defaultDocument "/-files.[value='index.html']" 2>&1 | Out-Null
            & $appcmd set config "$ParentSite" /section:defaultDocument "/+files.[value='index.html']" 2>&1 | Out-Null
            Write-LogMessage "Default document set to index.html" -Level INFO

            # ── Enable static content serving ───────────────────────────────────
            & $appcmd set config "$ParentSite" /section:staticContent /enabled:true 2>&1 | Out-Null

            # ── Set filesystem permissions ──────────────────────────────────────
            if ($permissionEntries -and $permissionEntries.Count -gt 0) {
                Set-FolderPermissionsFromTemplate -Path $PhysicalPath -Entries $permissionEntries
            }
            else {
                try {
                    $acl = Get-Acl $PhysicalPath
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        "IIS_IUSRS", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
                    )
                    $acl.AddAccessRule($rule)
                    Set-Acl -Path $PhysicalPath -AclObject $acl
                    Write-LogMessage "Permissions set on $PhysicalPath" -Level INFO
                }
                catch {
                    Write-LogMessage "Could not set permissions: $($_.Exception.Message)" -Level WARN
                }
            }

            # ── Start app pool and site ─────────────────────────────────────────
            $rootPoolState = (& $appcmd list apppool "$AppPoolName" /text:state 2>&1).Trim()
            if ($rootPoolState -ne "Started") {
                Write-LogMessage "Starting app pool '$AppPoolName'..." -Level INFO
                & $appcmd start apppool "$AppPoolName" 2>&1 | Out-Null
                Write-LogMessage "App pool '$AppPoolName' started" -Level INFO
            }
            else {
                Write-LogMessage "App pool '$AppPoolName' already running" -Level DEBUG
            }

            Write-LogMessage "Starting site '$ParentSite'..." -Level INFO
            $startResult = & $appcmd start site "$ParentSite" 2>&1 | Out-String
            if ($startResult -match "ERROR") {
                Write-LogMessage "Could not start '$($ParentSite)': $($startResult.Trim())" -Level WARN
            }
            else {
                Write-LogMessage "'$ParentSite' started" -Level INFO
            }

            # ── Verify redirect works ───────────────────────────────────────────
            # IIS responding at all (even 401/403) means the site is up.
            # Only a connection failure (no response) is fatal for the root site.
            Start-Sleep -Seconds 2
            try {
                $response = Invoke-WebRequest -Uri "http://localhost/" -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop
                $body = $response.Content
                if ($body -match 'DedgeAuth/login') {
                    Write-LogMessage "[OK] Root site: http://localhost/ -> HTTP $($response.StatusCode) (redirect to DedgeAuth)" -Level INFO
                }
                else {
                    Write-LogMessage "[WARN] Root site: http://localhost/ -> HTTP $($response.StatusCode) but redirect content not found" -Level WARN
                }
            }
            catch {
                $statusCode = $null
                if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
                if ($statusCode -and $statusCode -ge 300 -and $statusCode -lt 400) {
                    Write-LogMessage "[OK] Root site: http://localhost/ -> HTTP $($statusCode) (redirect)" -Level INFO
                }
                elseif ($statusCode -eq 401) {
                    # 401 = IIS is responding but anonymous auth may not be enabled.
                    # Site is up -- warn but don't block app deployment.
                    Write-LogMessage "[WARN] Root site: http://localhost/ -> HTTP 401 (Unauthorized). Anonymous Authentication may need manual enabling on this server." -Level WARN
                }
                elseif ($statusCode -and $statusCode -ge 400) {
                    # Other HTTP errors (403, 404, 500 etc) -- site is responding but not correctly
                    Write-LogMessage "[WARN] Root site: http://localhost/ -> HTTP $($statusCode). Site is responding but returned an error." -Level WARN
                }
                else {
                    # No response at all -- connection refused, timeout etc. This IS fatal.
                    Write-LogMessage "[FAIL] Root site: http://localhost/ -> $($_.Exception.Message)" -Level ERROR
                    $script:HasError = $true
                }
            }

            Write-LogMessage "===============================================================================" -Level INFO
            Write-LogMessage "Root site bootstrap complete. http://localhost/ -> /DedgeAuth/login.html" -Level INFO
            Write-LogMessage "PhysicalPath: $PhysicalPath" -Level INFO
            Write-LogMessage "AppPool:      $AppPoolName" -Level INFO
            Write-LogMessage "===============================================================================" -Level INFO

            # Save profile
            try {
                $profileParams = @{
                    SiteName                = $SiteName
                    PhysicalPath            = $PhysicalPath
                    AppType                 = $AppType
                    DotNetDll               = ""
                    AppPoolName             = $AppPoolName
                    InstallSource           = $InstallSource
                    InstallAppName          = $InstallAppName
                    VirtualPath             = $VirtualPath
                    ParentSite              = $ParentSite
                    HealthEndpoint          = ""
                    EnableDirectoryBrowsing = $false
                    IsRootSiteProfile       = $true
                    ApiPort                 = 0
                    AdditionalPorts         = @()
                    AdditionalWinApps       = @()
                    LastDeployed            = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    DeployedBy              = "$($env:USERDOMAIN)\$($env:USERNAME)"
                    ComputerName            = $env:COMPUTERNAME
                }
                $savedProfile = Save-DeployProfile -Params $profileParams
                Write-LogMessage "Profile saved: $savedProfile" -Level DEBUG
            }
            catch {
                Write-LogMessage "Could not save profile: $($_.Exception.Message)" -Level DEBUG
            }

            if ($script:HasError) {
                throw "Root site deployment completed with errors"
            }
            return [PSCustomObject]@{
                Success      = $true
                SiteName     = $SiteName
                ParentSite   = $ParentSite
                VirtualPath  = $VirtualPath
                PhysicalPath = $PhysicalPath
                AppType      = $AppType
                HasError     = [bool]$script:HasError
            }
        }

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 1: TEARDOWN VIRTUAL APPLICATION
        # ═══════════════════════════════════════════════════════════════════════════════
        Write-LogMessage "--- Step 1: Teardown existing configuration ---" -Level INFO

        # --- 1a: Remove orphan standalone site with the same name (if any) ---
        # A previous failed deployment or manual config may have left a standalone
        # SITE with the same SiteName. This conflicts with the virtual-app deployment
        # because both reference the same app pool. Clean it up first.
        $orphanSiteCheck = & $appcmd list site "$SiteName" 2>&1 | Out-String
        if ($orphanSiteCheck -match 'SITE "') {
            # Only remove if it's NOT the parent site (prevent accidentally deleting Default Web Site)
            if ($SiteName -ne $ParentSite) {
                Write-LogMessage "Found orphan standalone site '$SiteName' -- removing to avoid conflicts" -Level WARN
                # First remove all apps under the orphan site (root app included)
                $orphanApps = & $appcmd list app /site.name:"$SiteName" 2>&1 | Out-String
                foreach ($line in ($orphanApps -split "`n")) {
                    if ($line.Trim() -match '^APP "([^"]+)"') {
                        $orphanAppId = $matches[1]
                        Write-LogMessage "  Removing orphan app: $orphanAppId" -Level DEBUG
                        & $appcmd delete app /app.name:"$orphanAppId" 2>&1 | Out-Null
                    }
                }
                # Stop and delete the orphan site
                & $appcmd stop site "$SiteName" 2>&1 | Out-Null
                $delOrphan = & $appcmd delete site /site.name:"$SiteName" 2>&1 | Out-String
                if ($delOrphan -match "deleted") {
                    Write-LogMessage "Orphan site '$SiteName' deleted" -Level INFO
                }
                else {
                    Write-LogMessage "Could not delete orphan site '$($SiteName)': $($delOrphan.Trim())" -Level WARN
                }
            }
        }

        # --- 1b: Remove the virtual application under the parent site ---
        # Use /app.name: syntax for reliable exact matching (avoids ambiguous identifier errors)
        # Then extract the exact identifier from appcmd list output to guarantee the delete
        # uses the same string IIS recognizes (handles trailing slash, spacing, etc.)
        #
        # IMPORTANT: appcmd does PREFIX matching, so searching for "Default Web Site/DocView"
        # will return "Default Web Site/" (the root app) if /DocView doesn't exist.
        # We must verify the returned ID matches what we intended to delete.
        $appIdentifier = ("$ParentSite$VirtualPath").Trim()
        $appCheck = & $appcmd list app /app.name:"$appIdentifier" 2>&1 | Out-String
        if ($appCheck -match 'APP "([^"]+)"') {
            $exactAppId = $matches[1]
            # Guard: appcmd prefix-matches, so verify the result is our actual target
            # and not the root "/" app or a different app entirely
            $normalizedExact = $exactAppId.TrimEnd('/')
            $normalizedTarget = $appIdentifier.TrimEnd('/')
            if ($normalizedExact -eq $normalizedTarget) {
                Write-LogMessage "Removing virtual application: $exactAppId" -Level INFO
                $delApp = & $appcmd delete app /app.name:"$exactAppId" 2>&1 | Out-String
                if ($delApp -match "deleted") {
                    Write-LogMessage "Virtual application '$exactAppId' deleted" -Level INFO
                }
                elseif ($delApp -match "ERROR") {
                    Write-LogMessage "Delete virtual app failed: $($delApp.Trim())" -Level WARN
                }
            }
            else {
                Write-LogMessage "appcmd prefix-matched '$exactAppId' instead of '$($appIdentifier)' -- skipping delete to protect root app" -Level WARN
            }
        }
        else {
            Write-LogMessage "Virtual application '$appIdentifier' does not exist (nothing to tear down)" -Level DEBUG
        }

        # Stop and delete the app pool if it exists
        $poolCheck = & $appcmd list apppool "$AppPoolName" 2>&1 | Out-String
        if ($poolCheck -match 'APPPOOL "') {
            Write-LogMessage "Stopping app pool: $AppPoolName" -Level INFO
            & $appcmd stop apppool "$AppPoolName" 2>&1 | Out-Null

            $wpTimeout = 15
            $wpDeadline = (Get-Date).AddSeconds($wpTimeout)
            $wpRunning = $true
            while ((Get-Date) -lt $wpDeadline -and $wpRunning) {
                $workers = & $appcmd list wp 2>&1 | Out-String
                if ($workers -match $AppPoolName) {
                    Write-LogMessage "Waiting for w3wp.exe ($AppPoolName) to terminate..." -Level DEBUG
                    Start-Sleep -Seconds 2
                }
                else {
                    $wpRunning = $false
                }
            }
            if ($wpRunning) {
                Write-LogMessage "w3wp.exe did not terminate within $($wpTimeout)s -- killing" -Level WARN
                Get-CimInstance Win32_Process -Filter "Name = 'w3wp.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
                    $cmd = $_.CommandLine ?? ""
                    if ($cmd -match $AppPoolName) {
                        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                    }
                }
                Start-Sleep -Seconds 2
            }
            else {
                Write-LogMessage "Worker process terminated" -Level DEBUG
            }

            Write-LogMessage "Deleting app pool: $AppPoolName" -Level INFO
            $delPool = & $appcmd delete apppool "$AppPoolName" 2>&1 | Out-String
            if ($delPool -match "deleted") {
                Write-LogMessage "App pool '$AppPoolName' deleted" -Level INFO
            }
        }
        else {
            Write-LogMessage "App pool '$AppPoolName' does not exist (nothing to tear down)" -Level DEBUG
        }

        Write-LogMessage "Teardown complete" -Level INFO

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 2: INSTALL APP FILES
        # ═══════════════════════════════════════════════════════════════════════════════
        Write-LogMessage "--- Step 2: Install app files (source: $InstallSource) ---" -Level INFO

        # Kill stray processes whose command line references the deploy folder.
        # After app pool teardown, background services (ImportService, AlertAgent, etc.)
        # may still be running from the install path, locking DLLs and blocking file cleanup.
        if ($InstallSource -ne "None") {
            $killTargets = @($SiteName)
            if ($AdditionalWinApps.Count -gt 0) { $killTargets += $AdditionalWinApps }

            $strayCount = 0
            $escapedTargets = $killTargets | ForEach-Object { [regex]::Escape($_) }
            # regex: match any of the target names in process name or command line
            # e.g. GenericLogHandler|GenericLogHandler-AlertAgent|GenericLogHandler-ImportService
            $pattern = ($escapedTargets -join '|')

            try {
                # Use CIM to get CommandLine — avoids access-denied errors from MainModule
                $cimProcs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    ($_.Name -match $pattern) -or
                    ($_.CommandLine -and $_.CommandLine -match $pattern)
                }

                foreach ($cim in $cimProcs) {
                    $procId = $cim.ProcessId
                    if ($procId -eq $PID) { continue }
                    Write-LogMessage "Killing stray process: $($cim.Name) (PID $($procId)) — $($cim.CommandLine)" -Level WARN
                    Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                    $strayCount++
                }
            }
            catch {
                Write-LogMessage "Error searching for stray processes: $($_.Exception.Message)" -Level WARN
            }
            if ($strayCount -gt 0) {
                Write-LogMessage "Killed $($strayCount) stray process(es) for $($SiteName)" -Level INFO
                Start-Sleep -Seconds 2
            }
            else {
                Write-LogMessage "No stray processes found for $($SiteName)" -Level INFO
            }
        }

        # Clean install folder before copying new files to remove stale files from previous versions
        # This prevents old DLLs, configs, or assets from interfering with the new deployment
        $resolvedInstallPath = [System.Environment]::ExpandEnvironmentVariables($PhysicalPath)
        if ($InstallSource -ne "None" -and (Test-Path $resolvedInstallPath)) {
            Write-LogMessage "Cleaning install folder before deployment: $resolvedInstallPath" -Level INFO
            try {
                Get-ChildItem -Path $resolvedInstallPath -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                Write-LogMessage "Install folder cleaned" -Level INFO
            }
            catch {
                Write-LogMessage "Could not fully clean install folder: $($_.Exception.Message)" -Level WARN
            }
        }

        switch ($InstallSource) {
            "WinApp" {
                try {
                    Install-OurWinApp -AppName $InstallAppName -SkipShortcuts
                    Write-LogMessage "Install-OurWinApp '$InstallAppName' completed" -Level INFO
                }
                catch {
                    Write-LogMessage "Install-OurWinApp failed: $($_.Exception.Message)" -Level WARN
                    Write-LogMessage "Files in $PhysicalPath may need manual deployment" -Level WARN
                }
            }
            "PshApp" {
                try {
                    Install-OurPshApp -AppName $InstallAppName
                    Write-LogMessage "Install-OurPshApp '$InstallAppName' completed" -Level INFO
                }
                catch {
                    Write-LogMessage "Install-OurPshApp failed: $($_.Exception.Message)" -Level WARN
                    Write-LogMessage "Files in $PhysicalPath may need manual deployment" -Level WARN
                }
            }
            "None" {
                Write-LogMessage "No install -- using existing files at $PhysicalPath" -Level INFO
            }
        }

        # ── Install additional WinApps (companion services / agents) ─────────────
        # These are separate WinApp packages listed in the profile's AdditionalWinApps
        # array. Each is installed via Install-OurWinApp independently of the main app.
        if ($AdditionalWinApps.Count -gt 0) {
            Write-LogMessage "Installing $($AdditionalWinApps.Count) additional WinApp(s)..." -Level INFO
            foreach ($extraApp in $AdditionalWinApps) {
                try {
                    Write-LogMessage "Installing additional WinApp: $($extraApp)" -Level INFO
                    Install-OurWinApp -AppName $extraApp -SkipShortcuts
                    Write-LogMessage "Install-OurWinApp '$($extraApp)' completed" -Level INFO
                }
                catch {
                    Write-LogMessage "Install-OurWinApp '$($extraApp)' failed: $($_.Exception.Message)" -Level WARN
                    $script:HasError = $true
                }
            }
        }

        # ── Normalize DedgeAuth:AuthServerUrl to localhost (server-agnostic) ──────────
        # After file copy, the appsettings.json may contain a server-specific hostname
        # (e.g. http://dedge-server/DedgeAuth). Normalize it to http://localhost/{path}
        # so configs are portable across servers. Browser-facing URLs are derived
        # dynamically from the HTTP request by DedgeAuth.Client.
        if ($AppType -eq "AspNetCore") {
            $appSettingsPath = Join-Path $PhysicalPath "appsettings.json"
            if (Test-Path $appSettingsPath) {
                try {
                    $appSettingsJson = Get-Content $appSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    $DedgeAuthSection = $appSettingsJson.DedgeAuth
                    if ($DedgeAuthSection -and $DedgeAuthSection.AuthServerUrl) {
                        $currentUrl = $DedgeAuthSection.AuthServerUrl
                        try {
                            $parsed = [System.Uri]::new($currentUrl)
                            if ($parsed.Host -ne "localhost" -and $parsed.Host -ne "127.0.0.1") {
                                $normalizedUrl = "http://localhost$($parsed.AbsolutePath.TrimEnd('/'))"
                                $DedgeAuthSection.AuthServerUrl = $normalizedUrl
                                $appSettingsJson | ConvertTo-Json -Depth 20 | Set-Content $appSettingsPath -Encoding UTF8 -Force
                                Write-LogMessage "Normalized DedgeAuth:AuthServerUrl: $($currentUrl) -> $($normalizedUrl)" -Level INFO
                            }
                            else {
                                Write-LogMessage "DedgeAuth:AuthServerUrl already server-agnostic: $($currentUrl)" -Level DEBUG
                            }
                        }
                        catch {
                            Write-LogMessage "Could not parse DedgeAuth:AuthServerUrl '$($currentUrl)': $($_.Exception.Message)" -Level WARN
                        }
                    }
                }
                catch {
                    Write-LogMessage "Could not read/parse appsettings.json for DedgeAuth normalization: $($_.Exception.Message)" -Level WARN
                }
            }
        }

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 3: CREATE APPLICATION POOL
        # ═══════════════════════════════════════════════════════════════════════════════
        Write-LogMessage "--- Step 3: Create application pool ---" -Level INFO

        # ── 3a. Guard: prevent shared app pool (HTTP 500.35) ─────────────────
        # ASP.NET Core InProcess cannot share an app pool with other apps.
        # If the pool already exists and has other apps assigned, block deployment.
        if ($AppType -eq "AspNetCore") {
            $existingPool = & $appcmd list apppool "$AppPoolName" 2>&1 | Out-String
            if ($existingPool -match 'APPPOOL "') {
                $otherApps = @(& $appcmd list app /apppool.name:"$AppPoolName" 2>&1 | Out-String -Stream | Where-Object { $_ -match '^APP "' })
                if ($otherApps.Count -gt 0) {
                    $otherAppNames = $otherApps | ForEach-Object {
                        if ($_ -match 'APP "([^"]+)"') { $matches[1] }
                    }
                    Write-LogMessage "App pool '$($AppPoolName)' is already used by: $($otherAppNames -join ', ')" -Level ERROR
                    Write-LogMessage "ASP.NET Core InProcess requires a dedicated app pool per app (HTTP 500.35)" -Level ERROR
                    Write-LogMessage "Use a unique AppPoolName, or uninstall the conflicting app first" -Level ERROR
                    throw "Cannot deploy '$($SiteName)' to shared app pool '$($AppPoolName)'"
                }
            }
        }

        Invoke-AppCmd @("add", "apppool", "/name:$AppPoolName", '/managedRuntimeVersion:', '/managedPipelineMode:Integrated') `
            -Description "Create app pool" -FailOnError

        if ($AppType -eq "AspNetCore") {
            Invoke-AppCmd @("set", "apppool", "$AppPoolName", '/startMode:AlwaysRunning') -Description "Set startMode"
            Invoke-AppCmd @("set", "apppool", "$AppPoolName", '/processModel.idleTimeout:00:00:00') -Description "Set idleTimeout"
            Write-LogMessage "App pool configured: AlwaysRunning, no idle timeout" -Level DEBUG
        }
        else {
            Write-LogMessage "App pool configured: default settings (static site)" -Level DEBUG
        }

        # Determine service account: on servers use Get-OldServiceUsernameFromServerName,
        # on dev machines fall back to current user
        # $serviceUser = Get-OldServiceUsernameFromServerName
        $serviceUser = $env:USERNAME

        if (-not [string]::IsNullOrWhiteSpace($serviceUser)) {
            $runAsUser = "$($env:USERDOMAIN)\$($serviceUser)"
            Write-LogMessage "Server detected — using service account: $($runAsUser)" -Level INFO
        }
        else {
            $runAsUser = "$($env:USERDOMAIN)\$($env:USERNAME)"
            Write-LogMessage "Dev machine — using current user: $($runAsUser)" -Level INFO
        }

        Write-LogMessage "Configuring app pool identity to run as: $($runAsUser)" -Level INFO
        $plainPassword = Get-SecureStringUserPasswordAsPlainText -Username $serviceUser
        if ([string]::IsNullOrWhiteSpace($plainPassword)) {
            Write-LogMessage "Could not retrieve password for $($runAsUser) -- app pool will use default identity (ApplicationPoolIdentity)" -Level WARN
            Write-LogMessage "Run Set-UserPasswordAsSecureString -Username '$($serviceUser)' first, then re-run this script" -Level WARN
        }
        else {
            Invoke-AppCmd @("set", "apppool", "$AppPoolName", "/processModel.identityType:SpecificUser",
                "/processModel.userName:$runAsUser", "/processModel.password:$plainPassword") `
                -Description "Set app pool identity to $($runAsUser)"
            Write-LogMessage "App pool identity set to $($runAsUser)" -Level INFO
        }

        Write-LogMessage "App pool '$AppPoolName' created and configured" -Level INFO

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 3.5: DedgeAuth DATABASE REGISTRATION
        # ═══════════════════════════════════════════════════════════════════════════════
        # Runs only when the deploy template contains a "DedgeAuth" block with an AppId.
        # Non-fatal: failures are logged as warnings; IIS setup continues regardless.
        $DedgeAuthBlock = $script:ProfileDedgeAuthBlock
        if ($DedgeAuthBlock -and ($DedgeAuthBlock.AppId -or $DedgeAuthBlock.SyncAdminsOnly)) {
            # Resolve Register-DedgeAuthApp.ps1 path
            $registerScript = $DedgeAuthRegisterScriptPath
            if ([string]::IsNullOrWhiteSpace($registerScript)) {
                # Default: sibling DedgeAuth-AddAppSupport folder relative to IIS-DeployApp scripts
                $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
                $registerScript = Join-Path $scriptDir "..\DedgeAuth\DedgeAuth-AddAppSupport\Register-DedgeAuthApp.ps1"
            }
            $registerScript = [System.IO.Path]::GetFullPath($registerScript)

            try {
                $dbHost = Resolve-DedgeAuthDbHost
                if ($dbHost) {
                    # Convert PSCustomObject from JSON to hashtable for easier use
                    $DedgeAuthHashtable = @{}
                    $DedgeAuthBlock.PSObject.Properties | ForEach-Object { $DedgeAuthHashtable[$_.Name] = $_.Value }

                    if ($DedgeAuthHashtable.SyncAdminsOnly -eq $true) {
                        # Special case for DedgeAuth itself: only sync admin global_access_level (no app registration)
                        Write-LogMessage "Step 3.5: DedgeAuth server deploy — syncing admin global_access_level only" -Level INFO
                        Sync-DedgeAuthAdminEmails -AppId "" -DbHost $dbHost -HighestRole ""
                    }
                    else {
                        Register-AppInDedgeAuthDb `
                            -DedgeAuthBlock        $DedgeAuthHashtable `
                            -RegisterScriptPath  $registerScript `
                            -DbHost             $dbHost
                    }
                }
                else {
                    Write-LogMessage "Step 3.5 skipped: DedgeAuth DB not reachable" -Level WARN
                }
            }
            catch {
                Write-LogMessage "Step 3.5 (DedgeAuth registration) failed: $($_.Exception.Message)" -Level WARN
            }
        }
        else {
            Write-LogMessage "Step 3.5 skipped: no DedgeAuth block in deploy template" -Level DEBUG
        }

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 4: CREATE VIRTUAL APPLICATION
        # ═══════════════════════════════════════════════════════════════════════════════
        Write-LogMessage "--- Step 4: Create virtual application ---" -Level INFO

        Invoke-AppCmd @("add", "app", "/site.name:$ParentSite", "/path:$VirtualPath", "/physicalPath:$PhysicalPath") `
            -Description "Create virtual application" -FailOnError

        Invoke-AppCmd @("set", "app", "$ParentSite$VirtualPath", "/applicationPool:$AppPoolName") `
            -Description "Assign app pool" -FailOnError

        Write-LogMessage "Virtual application '$($ParentSite)$($VirtualPath)' created -> $PhysicalPath" -Level INFO

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 5: WEB.CONFIG
        # ═══════════════════════════════════════════════════════════════════════════════
        Write-LogMessage "--- Step 5: Verify web.config ---" -Level INFO

        $webConfigPath = Join-Path $PhysicalPath "web.config"
        if (-not (Test-Path $webConfigPath)) {
            Write-LogMessage "web.config not found -- creating for $AppType" -Level WARN

            if ($AppType -eq "AspNetCore") {
                # Build environment variables block for ApiPort
                $envVarsBlock = ""
                if ($ApiPort -gt 0) {
                    $envVarsBlock = @"

      <environmentVariables>
        <environmentVariable name="ASPNETCORE_URLS" value="http://localhost:$($ApiPort)" />
      </environmentVariables>
"@
                }
                @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <location path="." inheritInChildApplications="false">
    <system.webServer>
      <handlers>
        <add name="aspNetCore" path="*" verb="*" modules="AspNetCoreModuleV2" resourceType="Unspecified" />
      </handlers>
      <aspNetCore processPath="dotnet"
                  arguments=".\$DotNetDll"
                  stdoutLogEnabled="true"
                  stdoutLogFile=".\logs\stdout"
                  hostingModel="inprocess">$envVarsBlock
      </aspNetCore>
    </system.webServer>
  </location>
</configuration>
"@ | Out-File -FilePath $webConfigPath -Encoding UTF8 -Force
            }
            else {
                $dirBrowse = if ($EnableDirectoryBrowsing) { "true" } else { "false" }
                @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <directoryBrowse enabled="$dirBrowse" />
        <staticContent>
            <remove fileExtension=".json" />
            <mimeMap fileExtension=".json" mimeType="application/json" />
            <remove fileExtension=".mmd" />
            <mimeMap fileExtension=".mmd" mimeType="text/plain" />
            <remove fileExtension=".md" />
            <mimeMap fileExtension=".md" mimeType="text/plain" />
            <remove fileExtension=".woff2" />
            <mimeMap fileExtension=".woff2" mimeType="font/woff2" />
        </staticContent>
        <defaultDocument>
            <files>
                <clear />
                <add value="index.html" />
                <add value="default.html" />
            </files>
        </defaultDocument>
    </system.webServer>
</configuration>
"@ | Out-File -FilePath $webConfigPath -Encoding UTF8 -Force
            }
            Write-LogMessage "web.config created ($AppType)" -Level INFO
        }
        else {
            Write-LogMessage "web.config exists" -Level INFO
        }

        # ── Patch ASPNETCORE_URLS in existing web.config when ApiPort is configured ─
        if ($AppType -eq "AspNetCore" -and $ApiPort -gt 0 -and (Test-Path $webConfigPath)) {
            try {
                [xml]$webXml = Get-Content $webConfigPath -Raw
                $aspNetCoreNode = $webXml.SelectSingleNode("//aspNetCore")
                if ($aspNetCoreNode) {
                    $expectedUrl = "http://localhost:$($ApiPort)"

                    # Find or create the environmentVariables element
                    $envVarsNode = $aspNetCoreNode.SelectSingleNode("environmentVariables")
                    if (-not $envVarsNode) {
                        $envVarsNode = $webXml.CreateElement("environmentVariables")
                        $aspNetCoreNode.AppendChild($envVarsNode) | Out-Null
                    }

                    # Find or create the ASPNETCORE_URLS variable
                    $urlVar = $envVarsNode.SelectSingleNode("environmentVariable[@name='ASPNETCORE_URLS']")
                    if (-not $urlVar) {
                        $urlVar = $webXml.CreateElement("environmentVariable")
                        $urlVar.SetAttribute("name", "ASPNETCORE_URLS")
                        $envVarsNode.AppendChild($urlVar) | Out-Null
                    }

                    $currentUrl = $urlVar.GetAttribute("value")
                    if ($currentUrl -ne $expectedUrl) {
                        $urlVar.SetAttribute("value", $expectedUrl)
                        $webXml.Save($webConfigPath)
                        if ($currentUrl) {
                            Write-LogMessage "Updated ASPNETCORE_URLS in web.config: $($currentUrl) -> $($expectedUrl)" -Level INFO
                        }
                        else {
                            Write-LogMessage "Set ASPNETCORE_URLS in web.config: $($expectedUrl)" -Level INFO
                        }
                    }
                    else {
                        Write-LogMessage "ASPNETCORE_URLS already correct: $($expectedUrl)" -Level DEBUG
                    }
                }
            }
            catch {
                Write-LogMessage "Failed to patch ASPNETCORE_URLS in web.config: $($_.Exception.Message)" -Level WARN
            }
        }

        # ── Patch maxQueryString in web.config for JWT token redirects ─────────
        # DedgeAuth passes JWT tokens via ?token=<jwt> query string on login redirect.
        # JWT tokens typically exceed IIS's default maxQueryString of 2048 bytes,
        # causing HTTP 404.15 rejections. Set to 8192 for all AspNetCore apps.
        if ($AppType -eq "AspNetCore" -and (Test-Path $webConfigPath)) {
            try {
                [xml]$webXml = Get-Content $webConfigPath -Raw
                $expectedMaxQs = "8192"

                # Navigate to the <system.webServer> node inside <location>
                $sysWebServer = $webXml.SelectSingleNode("//location/system.webServer")
                if (-not $sysWebServer) {
                    $sysWebServer = $webXml.SelectSingleNode("//system.webServer")
                }

                if ($sysWebServer) {
                    # Find or create <security>
                    $securityNode = $sysWebServer.SelectSingleNode("security")
                    if (-not $securityNode) {
                        $securityNode = $webXml.CreateElement("security")
                        $sysWebServer.AppendChild($securityNode) | Out-Null
                    }

                    # Find or create <requestFiltering>
                    $reqFilterNode = $securityNode.SelectSingleNode("requestFiltering")
                    if (-not $reqFilterNode) {
                        $reqFilterNode = $webXml.CreateElement("requestFiltering")
                        $securityNode.AppendChild($reqFilterNode) | Out-Null
                    }

                    # Find or create <requestLimits>
                    $reqLimitsNode = $reqFilterNode.SelectSingleNode("requestLimits")
                    if (-not $reqLimitsNode) {
                        $reqLimitsNode = $webXml.CreateElement("requestLimits")
                        $reqFilterNode.AppendChild($reqLimitsNode) | Out-Null
                    }

                    $currentMaxQs = $reqLimitsNode.GetAttribute("maxQueryString")
                    if ($currentMaxQs -ne $expectedMaxQs) {
                        $reqLimitsNode.SetAttribute("maxQueryString", $expectedMaxQs)
                        $webXml.Save($webConfigPath)
                        if ($currentMaxQs) {
                            Write-LogMessage "Updated maxQueryString in web.config: $($currentMaxQs) -> $($expectedMaxQs)" -Level INFO
                        }
                        else {
                            Write-LogMessage "Set maxQueryString in web.config: $($expectedMaxQs)" -Level INFO
                        }
                    }
                    else {
                        Write-LogMessage "maxQueryString already correct: $($expectedMaxQs)" -Level DEBUG
                    }
                }
            }
            catch {
                Write-LogMessage "Failed to patch maxQueryString in web.config: $($_.Exception.Message)" -Level WARN
            }
        }

        # Ensure logs directory exists (for AspNetCore stdout logs)
        $logsDir = Join-Path $PhysicalPath "logs"
        if ($AppType -eq "AspNetCore") {
            if (-not (Test-Path $logsDir)) {
                New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
                Write-LogMessage "Created logs directory" -Level DEBUG
            }
        }

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 6: SET FOLDER PERMISSIONS
        # ═══════════════════════════════════════════════════════════════════════════════
        Write-LogMessage "--- Step 6: Set folder permissions ---" -Level INFO

        try {
            $identity = "IIS AppPool\$AppPoolName"

            $acl = Get-Acl $PhysicalPath
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $identity, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.AddAccessRule($rule)
            Set-Acl -Path $PhysicalPath -AclObject $acl
            Write-LogMessage "Granted ReadAndExecute to $identity on $PhysicalPath" -Level INFO

            if ($AppType -eq "AspNetCore" -and (Test-Path $logsDir)) {
                $acl = Get-Acl $logsDir
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $identity, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
                )
                $acl.AddAccessRule($rule)
                Set-Acl -Path $logsDir -AclObject $acl
                Write-LogMessage "Granted Modify to $identity on $logsDir" -Level INFO
            }
        }
        catch {
            Write-LogMessage "Failed to set permissions: $($_.Exception.Message)" -Level WARN
            Write-LogMessage "Set manually: icacls `"$PhysicalPath`" /grant `"IIS AppPool\$($AppPoolName):(OI)(CI)RX`" /T" -Level WARN
        }

        if ($permissionEntries -and $permissionEntries.Count -gt 0) {
            Set-FolderPermissionsFromTemplate -Path $PhysicalPath -Entries $permissionEntries
        }

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 6b: ANONYMOUS ACCESS (opt-in)
        # ═══════════════════════════════════════════════════════════════════════════════
        if ($AllowAnonymousAccess) {
            $iisConfigPath = "$ParentSite$VirtualPath"
            Write-LogMessage "--- Step 6b: Enabling Anonymous Access for '$($iisConfigPath)' ---" -Level INFO
            try {
                # /commit:apphost is required because anonymousAuthentication and
                # windowsAuthentication sections are locked (overrideModeDefault="Deny")
                # in applicationHost.config. Without it, appcmd silently fails.
                Invoke-AppCmd @("set", "config", "$iisConfigPath",
                    "/section:system.webServer/security/authentication/anonymousAuthentication",
                    "/enabled:true", "/commit:apphost") `
                    -Description "Enable Anonymous Authentication" -FailOnError

                Invoke-AppCmd @("set", "config", "$iisConfigPath",
                    "/section:system.webServer/security/authentication/anonymousAuthentication",
                    "/userName:", "/commit:apphost") `
                    -Description "Set Anonymous Auth to use App Pool Identity" -FailOnError

                Invoke-AppCmd @("set", "config", "$iisConfigPath",
                    "/section:system.webServer/security/authentication/windowsAuthentication",
                    "/enabled:false", "/commit:apphost") `
                    -Description "Disable Windows Authentication" -FailOnError

                Write-LogMessage "Anonymous Authentication enabled, Windows Authentication disabled for '$($iisConfigPath)'" -Level INFO

                # Grant IUSR read access as a fallback for anonymous requests
                $iusrIdentity = "IUSR"
                $acl = Get-Acl $PhysicalPath
                $iusrRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $iusrIdentity, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
                )
                $acl.AddAccessRule($iusrRule)
                Set-Acl -Path $PhysicalPath -AclObject $acl
                Write-LogMessage "Granted ReadAndExecute to $($iusrIdentity) on $($PhysicalPath)" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to configure anonymous access: $($_.Exception.Message)" -Level WARN
                $script:HasError = $true
            }
        }

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 6c: WINDOWS AUTHENTICATION (opt-in, for apps using Negotiate SSO)
        # ═══════════════════════════════════════════════════════════════════════════════
        if ($WindowsAuthentication) {
            $iisConfigPath = "$ParentSite$VirtualPath"
            Write-LogMessage "--- Step 6c: Enabling Windows Authentication for '$($iisConfigPath)' ---" -Level INFO
            try {
                Invoke-AppCmd @("set", "config", "$iisConfigPath",
                    "/section:system.webServer/security/authentication/windowsAuthentication",
                    "/enabled:true", "/commit:apphost") `
                    -Description "Enable Windows Authentication" -FailOnError

                # When the app pool runs as a domain account (not machine account),
                # Kerberos tickets are encrypted for the SPN principal which may not
                # match the machine account. useAppPoolCredentials=true tells HTTP.sys
                # to pass tickets to the app pool process for decryption, fixing
                # SEC_E_WRONG_PRINCIPAL errors.
                Invoke-AppCmd @("set", "config", "$iisConfigPath",
                    "/section:system.webServer/security/authentication/windowsAuthentication",
                    "/useAppPoolCredentials:true", "/commit:apphost") `
                    -Description "Set useAppPoolCredentials for Kerberos with domain app pool" -FailOnError

                Invoke-AppCmd @("set", "config", "$iisConfigPath",
                    "/section:system.webServer/security/authentication/anonymousAuthentication",
                    "/enabled:true", "/commit:apphost") `
                    -Description "Enable Anonymous Authentication (alongside Windows Auth)" -FailOnError

                Write-LogMessage "Windows Authentication (useAppPoolCredentials) and Anonymous Authentication both enabled for '$($iisConfigPath)'" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to configure Windows Authentication: $($_.Exception.Message)" -Level WARN
                $script:HasError = $true
            }
        }

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 7: FIREWALL RULES
        # ═══════════════════════════════════════════════════════════════════════════════
        Write-LogMessage "--- Step 7: Firewall rules ---" -Level INFO

        if ($ApiPort -gt 0) {
            # Inbound rule for the app's Kestrel/API port
            $inboundName = "$SiteName - API Inbound (TCP $ApiPort)"
            $existingInbound = Get-NetFirewallRule -DisplayName $inboundName -ErrorAction SilentlyContinue
            if (-not $existingInbound) {
                New-NetFirewallRule -DisplayName $inboundName -Direction Inbound -Protocol TCP -LocalPort $ApiPort -Action Allow | Out-Null
                Write-LogMessage "Created firewall rule: $inboundName" -Level INFO
            }
            else {
                Write-LogMessage "Firewall rule already exists: $inboundName" -Level DEBUG
            }

            # Outbound rule for the app's Kestrel/API port
            $outboundName = "$SiteName - API Outbound (TCP $ApiPort)"
            $existingOutbound = Get-NetFirewallRule -DisplayName $outboundName -ErrorAction SilentlyContinue
            if (-not $existingOutbound) {
                New-NetFirewallRule -DisplayName $outboundName -Direction Outbound -Protocol TCP -RemotePort $ApiPort -Action Allow | Out-Null
                Write-LogMessage "Created firewall rule: $outboundName" -Level INFO
            }
            else {
                Write-LogMessage "Firewall rule already exists: $outboundName" -Level DEBUG
            }
        }
        else {
            Write-LogMessage "No ApiPort configured -- skipping app firewall rules" -Level DEBUG
        }

        # Additional ports -- direction-aware firewall rules.
        # Each entry supports: Port, Description, Direction (Inbound | Outbound | Both).
        # Default direction is "Both" for backward compatibility.
        if ($AdditionalPorts.Count -gt 0) {
            Write-LogMessage "Creating firewall rules for $($AdditionalPorts.Count) additional port(s)..." -Level INFO
            foreach ($ap in $AdditionalPorts) {
                $apPort = if ($ap.Port) { [int]$ap.Port } else { [int]$ap }
                $apDesc = if ($ap.Description) { $ap.Description } else { "Additional" }
                $apDir = if ($ap.Direction) { $ap.Direction } else { "Both" }

                # Inbound rule (if Direction is Inbound or Both)
                if ($apDir -in @("Inbound", "Both")) {
                    $apInName = "$SiteName - $($apDesc) Inbound (TCP $($apPort))"
                    $existingApIn = Get-NetFirewallRule -DisplayName $apInName -ErrorAction SilentlyContinue
                    if (-not $existingApIn) {
                        New-NetFirewallRule -DisplayName $apInName -Direction Inbound -Protocol TCP -LocalPort $apPort -Action Allow | Out-Null
                        Write-LogMessage "Created firewall rule: $apInName" -Level INFO
                    }
                    else {
                        Write-LogMessage "Firewall rule already exists: $apInName" -Level DEBUG
                    }
                }

                # Outbound rule (if Direction is Outbound or Both)
                if ($apDir -in @("Outbound", "Both")) {
                    $apOutName = "$SiteName - $($apDesc) Outbound (TCP $($apPort))"
                    $existingApOut = Get-NetFirewallRule -DisplayName $apOutName -ErrorAction SilentlyContinue
                    if (-not $existingApOut) {
                        New-NetFirewallRule -DisplayName $apOutName -Direction Outbound -Protocol TCP -RemotePort $apPort -Action Allow | Out-Null
                        Write-LogMessage "Created firewall rule: $apOutName" -Level INFO
                    }
                    else {
                        Write-LogMessage "Firewall rule already exists: $apOutName" -Level DEBUG
                    }
                }
            }
        }

        # Always ensure SMTP outbound (port 25) is open
        $smtpRuleName = "SMTP Outbound (TCP 25)"
        $existingSmtp = Get-NetFirewallRule -DisplayName $smtpRuleName -ErrorAction SilentlyContinue
        if (-not $existingSmtp) {
            New-NetFirewallRule -DisplayName $smtpRuleName -Direction Outbound -Protocol TCP -RemotePort 25 -Action Allow | Out-Null
            Write-LogMessage "Created firewall rule: $smtpRuleName" -Level INFO
        }
        else {
            Write-LogMessage "Firewall rule already exists: $smtpRuleName" -Level DEBUG
        }

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 8: START SERVICES
        # ═══════════════════════════════════════════════════════════════════════════════
        Write-LogMessage "--- Step 8: Start services ---" -Level INFO

        Invoke-AppCmd @("start", "apppool", "$AppPoolName") -Description "Start app pool"
        Start-Sleep -Seconds 2

        # Ensure parent site is running
        $parentState = (& $appcmd list site "$ParentSite" /text:state 2>&1).Trim()
        if ($parentState -ne "Started") {
            Write-LogMessage "Parent site '$ParentSite' is $parentState -- attempting to start..." -Level INFO
            $startResult = & $appcmd start site "$ParentSite" 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0 -or $startResult -match "ERROR") {
                Write-LogMessage "Could not start '$($ParentSite)': $($startResult.Trim())" -Level WARN
                Write-LogMessage "Run the DefaultWebSite profile first to bootstrap the parent site." -Level WARN
            }
            else {
                Write-LogMessage "'$ParentSite' started" -Level INFO
            }
            Start-Sleep -Seconds 2
        }
        else {
            Write-LogMessage "'$ParentSite' already running" -Level DEBUG
        }

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 9: VERIFY
        # ═══════════════════════════════════════════════════════════════════════════════
        Write-LogMessage "--- Step 9: Verify ---" -Level INFO

        $poolState = (& $appcmd list apppool "$AppPoolName" /text:state 2>&1).Trim()
        if ($poolState -eq "Started") {
            Write-LogMessage "[OK] App pool: $poolState" -Level INFO
        }
        else {
            Write-LogMessage "[FAIL] App pool: $poolState" -Level ERROR
            $script:HasError = $true
        }

        $parentState = (& $appcmd list site "$ParentSite" /text:state 2>&1).Trim()
        if ($parentState -eq "Started") {
            Write-LogMessage "[OK] Parent site '$($ParentSite)': $parentState" -Level INFO
        }
        else {
            Write-LogMessage "[WARN] Parent site '$($ParentSite)': $parentState -- run DefaultWebSite profile first" -Level WARN
        }

        $appCheck = & $appcmd list app "$ParentSite$VirtualPath" 2>&1 | Out-String
        if ($appCheck -match 'APP "') {
            Write-LogMessage "[OK] Virtual app: $($ParentSite)$($VirtualPath)" -Level INFO
        }
        else {
            Write-LogMessage "[FAIL] Virtual app not found: $($ParentSite)$($VirtualPath)" -Level ERROR
            $script:HasError = $true
        }

        if (Test-Path $webConfigPath) {
            Write-LogMessage "[OK] web.config exists" -Level INFO
        }
        else {
            Write-LogMessage "[FAIL] web.config missing" -Level ERROR
            $script:HasError = $true
        }

        # ═══════════════════════════════════════════════════════════════════════════════
        # STEP 10: HEALTH CHECK
        # ═══════════════════════════════════════════════════════════════════════════════
        Write-LogMessage "--- Step 10: Health check ---" -Level INFO

        if ($SkipHealthCheck) {
            Write-LogMessage "SkipHealthCheck=true — skipping health check (MCP/SSE server or non-HTTP app)" -Level INFO
        }
        else {

            # Verify the IIS virtual path from appcmd so the test URL matches what IIS actually serves
            $iisAppPath = & $appcmd list app "$ParentSite$VirtualPath" 2>&1 | Out-String
            if ($iisAppPath -match 'APP "([^"]+)"') {
                $actualAppPath = $matches[1] -replace [regex]::Escape($ParentSite), ''
                if ($actualAppPath -ne $VirtualPath) {
                    Write-LogMessage "IIS virtual path differs from profile: IIS='$actualAppPath' vs profile='$VirtualPath'" -Level WARN
                }
                # Rebuild baseUrl from the actual IIS path
                if ($parentPort -eq 80) {
                    $baseUrl = "http://localhost$actualAppPath"
                }
                else {
                    $baseUrl = "http://localhost:$($parentPort)$actualAppPath"
                }
            }

            Write-LogMessage "Health check URL base: $baseUrl" -Level DEBUG

            if ($AppType -eq "AspNetCore") {
                # AspNetCore apps may take several seconds to start up (JIT, EF migrations, etc.)
                # Retry health checks up to 3 times with a 10-second delay between attempts
                $maxHealthRetries = 3
                $healthRetryDelay = 10
                $apiResponded = $false

                for ($healthAttempt = 1; $healthAttempt -le $maxHealthRetries; $healthAttempt++) {
                    if ($healthAttempt -gt 1) {
                        Write-LogMessage "App not responding yet -- waiting $($healthRetryDelay)s before retry $($healthAttempt)/$($maxHealthRetries)..." -Level INFO
                        Start-Sleep -Seconds $healthRetryDelay
                    }

                    # Test health endpoint if configured
                    if (-not [string]::IsNullOrWhiteSpace($HealthEndpoint)) {
                        $healthUrl = "$($baseUrl)$($HealthEndpoint)"
                        if (Test-HealthUrl -Url $healthUrl -Label "Health") { $apiResponded = $true }
                    }

                    # Test app root only when we have a default document or any HTML (avoids 404 for API-only apps)
                    if (-not $apiResponded) {
                        $resolvedPath = [System.Environment]::ExpandEnvironmentVariables($PhysicalPath)
                        $testPage = Find-TestPage -Path $resolvedPath
                        $rootResult = $false
                        if ($testPage) {
                            $rootUrlToTest = "$($baseUrl)/$testPage"
                            $rootResult = Test-HealthUrl -Url $rootUrlToTest -Label "Root"
                        }
                        else {
                            # No index/default/first HTML — skip Root URL test to avoid 404; rely on Health/Scalar/API below
                            Write-LogMessage "No default document in path — skipping Root URL check (will try Health/Scalar/API)" -Level DEBUG
                        }
                        if ($rootResult) {
                            $apiResponded = $true
                        }
                    }

                    # Try Scalar API documentation endpoint
                    if (-not $apiResponded) {
                        $scalarUrl = "$($baseUrl)/scalar/v1"
                        if (Test-HealthUrl -Url $scalarUrl -Label "Scalar") { $apiResponded = $true }
                    }

                    # Try common API endpoints (includes /health for apps using ASP.NET Core health checks)
                    if (-not $apiResponded) {
                        foreach ($apiPath in @("/health", "/api", "/api/health", "/api/v1")) {
                            $apiUrl = "$($baseUrl)$apiPath"
                            if (Test-HealthUrl -Url $apiUrl -Label "API ($apiPath)") {
                                $apiResponded = $true
                                break
                            }
                        }
                    }

                    # Last resort: try the app root URL directly (catches MCP/SSE servers that respond with non-404)
                    if (-not $apiResponded) {
                        $rootUrl = "$($baseUrl)/"
                        if (Test-HealthUrl -Url $rootUrl -Label "App root") { $apiResponded = $true }
                    }

                    if ($apiResponded) { break }
                }

                if (-not $apiResponded) {
                    Write-LogMessage "API did not respond on any endpoint after $($maxHealthRetries) attempt(s). Check logs at: $(Join-Path $PhysicalPath 'logs')" -Level ERROR
                    $script:HasError = $true
                }
            }
            else {
                # Static site -- find a page to test
                $testPage = Find-TestPage -Path $PhysicalPath
                if ($testPage) {
                    # Try the discovered page directly
                    $url = "$($baseUrl)/$testPage"
                    $result = Test-HealthUrl -Url $url -Label "Static ($testPage)"
                    if (-not $result) {
                        $script:HasError = $true
                    }
                }
                else {
                    Write-LogMessage "No HTML files found in $PhysicalPath -- cannot test HTTP" -Level WARN
                    if ($EnableDirectoryBrowsing) {
                        # Try root anyway since directory browsing is on
                        Test-HealthUrl -Url "$($baseUrl)/" -Label "Directory listing" | Out-Null
                    }
                }
            }

        } # end of SkipHealthCheck else block

        # ═══════════════════════════════════════════════════════════════════════════════
        # SUMMARY
        # ═══════════════════════════════════════════════════════════════════════════════
        Write-LogMessage "===============================================================================" -Level INFO
        Write-LogMessage "Summary" -Level INFO
        Write-LogMessage "===============================================================================" -Level INFO
        Write-LogMessage "Site:          $SiteName" -Level INFO
        Write-LogMessage "App Pool:      $AppPoolName" -Level INFO
        Write-LogMessage "App Type:      $AppType" -Level INFO
        Write-LogMessage "Install:       $InstallSource$(if ($InstallSource -ne 'None') { " ($InstallAppName)" } else { '' })" -Level INFO
        Write-LogMessage "Virtual Path:  $VirtualPath" -Level INFO
        Write-LogMessage "Physical Path: $PhysicalPath" -Level INFO
        Write-LogMessage "URL:           $baseUrl" -Level INFO

        if ($script:HasError) {
            Write-LogMessage "Result: SOME CHECKS FAILED -- review errors above" -Level ERROR
        }
        else {
            Write-LogMessage "Result: ALL CHECKS PASSED" -Level INFO
        }

        Write-LogMessage "===============================================================================" -Level INFO

        # ═══════════════════════════════════════════════════════════════════════════════
        # SAVE DEPLOYMENT PROFILE
        # ═══════════════════════════════════════════════════════════════════════════════
        try {
            $profileParams = @{
                SiteName                = $SiteName
                PhysicalPath            = $PhysicalPath
                AppType                 = $AppType
                DotNetDll               = $DotNetDll
                AppPoolName             = $AppPoolName
                InstallSource           = $InstallSource
                InstallAppName          = $InstallAppName
                VirtualPath             = $VirtualPath
                ParentSite              = $ParentSite
                HealthEndpoint          = $HealthEndpoint
                EnableDirectoryBrowsing = [bool]$EnableDirectoryBrowsing
                AllowAnonymousAccess    = [bool]$AllowAnonymousAccess
                WindowsAuthentication   = [bool]$WindowsAuthentication
                SkipHealthCheck         = [bool]$SkipHealthCheck
                IsRootSiteProfile       = $false
                ApiPort                 = $ApiPort
                AdditionalPorts         = $AdditionalPorts
                AdditionalWinApps       = $AdditionalWinApps
                LastDeployed            = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                DeployedBy              = "$($env:USERDOMAIN)\$($env:USERNAME)"
                ComputerName            = $env:COMPUTERNAME
            }
            $savedProfile = Save-DeployProfile -Params $profileParams
            Write-LogMessage "Profile saved: $savedProfile" -Level DEBUG
        }
        catch {
            Write-LogMessage "Could not save profile: $($_.Exception.Message)" -Level DEBUG
        }

        if ($script:HasError) {
            throw "Deployment completed with errors -- review log above"
        }

        return [PSCustomObject]@{
            Success      = $true
            SiteName     = $SiteName
            ParentSite   = $ParentSite
            VirtualPath  = $VirtualPath
            PhysicalPath = $PhysicalPath
            AppType      = $AppType
            HasError     = [bool]$script:HasError
        }

    }
    catch {
        Write-LogMessage "DEPLOY FAILED: $($_.Exception.Message)" -Level FATAL -Exception $_
        throw
    }

}
Export-ModuleMember -Function *