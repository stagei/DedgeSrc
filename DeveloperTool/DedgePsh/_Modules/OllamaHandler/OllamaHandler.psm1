#Requires -Version 5.1

<#
.SYNOPSIS
    Comprehensive PowerShell module for Ollama AI model integration.

.DESCRIPTION
    OllamaHandler provides full-featured integration with Ollama AI models for both
    interactive and programmatic use. Key capabilities include:
    
    CORE FEATURES:
    - Invoke-Ollama: Query AI with role-based prompting and audience-level adaptation
    - Start-OllamaChat: Interactive chat with commands, templates, and file context
    - Template System: Save/load reusable prompts from local and global template files
    
    CONTEXT HANDLING:
    - Add files as context with @filepath syntax or -ContextFiles parameter
    - Intelligent extraction for large files (>50KB) using AI-guided selection
    - Multi-line paste support for code blocks
    
    MODEL MANAGEMENT:
    - Browse/install models from Ollama library
    - Export/import models for airgapped servers
    - Configure port, path, and service settings
    
    OUTPUT:
    - Save chat to markdown (AI-only or full dialog)
    - Generate reports from templates with context files
    - Raw text output for script integration
    
    INFRASTRUCTURE:
    - Windows Firewall configuration for Ollama
    - Auto-installation via winget if missing
    - Service management (start, test, configure)

.AUTHOR
    Geir Helge Starholm, www.dEdge.no

.NOTES
    Requires Ollama to be installed and running locally.
    Default API endpoint: http://localhost:11434
    
    Template locations:
    - Local: $env:OptPath\data\OllamaTemplates\OllamaTemplates.json
    - Global: Configured via GlobalSettings.json
#>

#region Module Variables

# Default Ollama settings
$script:DefaultApiUrl = "http://localhost:11434"
$script:DefaultModel = "llama3.1:8b"
$script:MaxContextTokens = 100000  # Approximate max context for most models
$script:MaxFileSizeBytes = 50000   # ~50KB before triggering intelligent extraction

# AI Role definitions with system prompts
$script:AIRoles = @{
    "General" = @{
        Name = "General Assistant"
        SystemPrompt = "You are a helpful, friendly AI assistant. Provide clear, accurate, and concise responses."
        Description = "General-purpose assistant for everyday tasks"
    }
    "CodeAssist" = @{
        Name = "Code Assistant"
        SystemPrompt = @"
You are an expert programming assistant. You help with:
- Writing clean, efficient, and well-documented code
- Debugging and troubleshooting issues
- Explaining code concepts and best practices
- Code reviews and optimization suggestions
- PowerShell, Python, JavaScript, C#, and other languages

Always provide code examples when relevant. Use proper formatting with code blocks.
Explain your reasoning and suggest best practices.
"@
        Description = "Expert programmer for coding tasks, debugging, and code reviews"
    }
    "EconomicalAdvisor" = @{
        Name = "Economical Advisor"
        SystemPrompt = @"
You are a professional economic and financial advisor. You provide:
- Financial analysis and insights
- Investment guidance and risk assessment
- Budget planning and optimization
- Economic trend analysis
- Business financial strategy

Be precise with numbers. Always clarify that your advice is informational and not professional financial advice.
Recommend consulting certified professionals for major financial decisions.
"@
        Description = "Financial and economic analysis and advice"
    }
    "Legal" = @{
        Name = "Legal Assistant"
        SystemPrompt = @"
You are a knowledgeable legal assistant. You help with:
- Understanding legal concepts and terminology
- Document analysis and explanation
- Legal research guidance
- Contract review insights
- Regulatory compliance information

IMPORTANT: Always clarify that you provide legal information, not legal advice.
Recommend consulting a licensed attorney for specific legal matters.
Do not provide advice on ongoing legal cases.
"@
        Description = "Legal information and document analysis (not legal advice)"
    }
    "DataAnalyst" = @{
        Name = "Data Analyst"
        SystemPrompt = @"
You are an expert data analyst. You assist with:
- Data analysis and interpretation
- Statistical concepts and methods
- Data visualization recommendations
- SQL queries and database concepts
- Excel, Power BI, and other tools
- Pattern recognition and insights

Provide structured analysis with clear explanations. Use examples when helpful.
"@
        Description = "Data analysis, statistics, and visualization"
    }
    "Writer" = @{
        Name = "Writing Assistant"
        SystemPrompt = @"
You are a professional writing assistant. You help with:
- Content creation and editing
- Grammar and style improvements
- Document structure and flow
- Tone adjustment for different audiences
- Translation and localization guidance
- Email and business correspondence

Adapt your style to match the requested tone and purpose.
"@
        Description = "Content writing, editing, and communication"
    }
    "ITSupport" = @{
        Name = "IT Support Specialist"
        SystemPrompt = @"
You are an experienced IT support specialist. You assist with:
- Troubleshooting hardware and software issues
- Network configuration and diagnostics
- System administration tasks
- Security best practices
- Cloud services (Azure, AWS, etc.)
- Enterprise tools and infrastructure

Provide step-by-step instructions. Consider security implications.
Ask clarifying questions when needed for accurate diagnosis.
"@
        Description = "IT troubleshooting and system administration"
    }
    "Teacher" = @{
        Name = "Educational Tutor"
        SystemPrompt = @"
You are a patient and encouraging educational tutor. You:
- Explain concepts clearly at the appropriate level
- Use examples and analogies for complex topics
- Break down problems into manageable steps
- Encourage learning through questions
- Adapt teaching style to the learner

Focus on understanding, not just answers. Build foundational knowledge.
"@
        Description = "Educational tutoring and concept explanation"
    }
}

# Audience levels with language complexity adjustments
$script:AudienceLevels = @{
    "Expert" = @{
        Level = 5
        Description = "Expert/Professional - Technical jargon, advanced concepts, assumes deep knowledge"
        Modifier = "Use technical terminology and advanced concepts freely. Assume deep expertise in the field."
    }
    "Advanced" = @{
        Level = 4
        Description = "Advanced - Professional language, some technical terms, detailed explanations"
        Modifier = "Use professional language with technical terms. Provide detailed but focused explanations."
    }
    "Intermediate" = @{
        Level = 3
        Description = "Intermediate - Balanced language, explain technical terms, moderate detail"
        Modifier = "Balance technical accuracy with accessibility. Explain technical terms when first used."
    }
    "Beginner" = @{
        Level = 2
        Description = "Beginner - Simple language, minimal jargon, step-by-step explanations"
        Modifier = "Use simple, clear language. Avoid jargon. Provide step-by-step explanations with examples."
    }
    "Child" = @{
        Level = 1
        Description = "Child/Novice - Very simple language, analogies, fundamental concepts"
        Modifier = "Use very simple words and short sentences. Use fun analogies and everyday examples. Be encouraging."
    }
}

#endregion

#region Module Import

$modulesToImport = @("GlobalFunctions", "SoftwareUtils")
foreach ($moduleName in $modulesToImport) {
    $loadedModule = Get-Module -Name $moduleName
    if ($loadedModule -eq $false -or $env:USERNAME -in @("FKGEISTA", "FKSVEERI")) {
        Import-Module $moduleName -Force -ErrorAction SilentlyContinue
    }
}

#endregion

#region Service Functions

<#
.SYNOPSIS
    Tests if the Ollama service is running.

.DESCRIPTION
    Attempts to connect to the Ollama API and returns whether the service is available.

.PARAMETER ApiUrl
    The base URL for the Ollama API. Defaults to http://localhost:11434.

.PARAMETER TimeoutSec
    Connection timeout in seconds. Defaults to 5.

.EXAMPLE
    Test-OllamaService
    # Returns $true if Ollama is running

.EXAMPLE
    Test-OllamaService -ApiUrl "http://192.168.1.100:11434"
    # Tests Ollama on a remote machine
#>
function Test-OllamaService {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ApiUrl = $script:DefaultApiUrl,

        [Parameter()]
        [int]$TimeoutSec = 5
    )

    try {
        $null = Invoke-RestMethod -Uri "$ApiUrl/api/tags" -Method Get -TimeoutSec $TimeoutSec
        return $true
    }
    catch {
        Write-LogMessage "Ollama service not reachable at $($ApiUrl): $($_.Exception.Message)" -Level DEBUG
        return $false
    }
}

<#
.SYNOPSIS
    Starts the Ollama service.

.DESCRIPTION
    Attempts to start the Ollama serve process and waits for it to become available.

.PARAMETER ApiUrl
    The base URL for the Ollama API. Defaults to http://localhost:11434.

.PARAMETER MaxWaitSeconds
    Maximum time to wait for service to start. Defaults to 30.

.EXAMPLE
    Start-OllamaService
    # Starts Ollama and waits for it to be ready

.OUTPUTS
    Boolean indicating whether the service started successfully.
#>
function Start-OllamaService {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ApiUrl = $script:DefaultApiUrl,

        [Parameter()]
        [int]$MaxWaitSeconds = 30
    )

    Write-LogMessage "Starting Ollama service..." -Level INFO

    # Find ollama executable
    $ollamaCmd = $null
    
    # Try common paths
    $commonPaths = @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:ProgramFiles\Ollama\ollama.exe",
        "C:\Ollama\ollama.exe"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $ollamaCmd = $path
            break
        }
    }
    
    # Try Get-Command
    if (-not $ollamaCmd) {
        $cmd = Get-Command "ollama" -ErrorAction SilentlyContinue
        if ($cmd) {
            $ollamaCmd = $cmd.Source
        }
    }

    if (-not $ollamaCmd) {
        Write-LogMessage "Ollama executable not found. Please ensure Ollama is installed." -Level ERROR
        return $false
    }

    try {
        Start-Process -FilePath $ollamaCmd -ArgumentList "serve" -WindowStyle Minimized
        
        # Wait for service to be ready
        $waitTime = 0
        $checkInterval = 2
        while ($waitTime -lt $MaxWaitSeconds) {
            Start-Sleep -Seconds $checkInterval
            $waitTime += $checkInterval
            
            if (Test-OllamaService -ApiUrl $ApiUrl) {
                Write-LogMessage "Ollama service started successfully!" -Level INFO
                return $true
            }
        }
        
        Write-LogMessage "Ollama service did not start within $MaxWaitSeconds seconds." -Level WARN
        return $false
    }
    catch {
        Write-LogMessage "Failed to start Ollama service" -Level ERROR -Exception $_
        return $false
    }
}

#endregion

#region Model Management Functions

<#
.SYNOPSIS
    Gets a list of locally installed Ollama models.

.DESCRIPTION
    Queries the Ollama API to retrieve all models currently installed on the local system.
    Returns detailed information about each model including name, size, and modification date.

.PARAMETER ApiUrl
    The base URL for the Ollama API. Defaults to http://localhost:11434.

.PARAMETER IncludeDetails
    If specified, returns full model details. Otherwise returns just model names.

.EXAMPLE
    Get-OllamaModels
    # Returns list of model names

.EXAMPLE
    Get-OllamaModels -IncludeDetails
    # Returns detailed model information

.OUTPUTS
    Array of model names or PSCustomObjects with model details.
#>
function Get-OllamaModels {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ApiUrl = $script:DefaultApiUrl,

        [Parameter()]
        [switch]$IncludeDetails
    )

    if (-not (Test-OllamaService -ApiUrl $ApiUrl)) {
        Write-LogMessage "Ollama service is not running at $ApiUrl" -Level ERROR
        return @()
    }

    try {
        $response = Invoke-RestMethod -Uri "$ApiUrl/api/tags" -Method Get
        
        if ($IncludeDetails) {
            return $response.models | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.name
                    Model = $_.model
                    Size = [math]::Round($_.size / 1GB, 2)
                    SizeGB = "$([math]::Round($_.size / 1GB, 2)) GB"
                    ModifiedAt = $_.modified_at
                    Family = $_.details.family
                    ParameterSize = $_.details.parameter_size
                    QuantizationLevel = $_.details.quantization_level
                }
            }
        }
        else {
            return $response.models | ForEach-Object { $_.name }
        }
    }
    catch {
        Write-LogMessage "Failed to get Ollama models" -Level ERROR -Exception $_
        return @()
    }
}

<#
.SYNOPSIS
    Sets the port that Ollama uses.

.DESCRIPTION
    Configures the OLLAMA_HOST environment variable to change the port Ollama listens on.
    Requires Ollama service restart to take effect.

.PARAMETER Port
    The port number for Ollama to use. Valid range: 1024-65535.

.PARAMETER BindAddress
    The host address to bind to. Defaults to "0.0.0.0" for all interfaces.

.PARAMETER Persist
    If specified, sets the environment variable at User level (persists across sessions).

.EXAMPLE
    Set-OllamaPort -Port 8080
    # Sets Ollama to use port 8080 for current session

.EXAMPLE
    Set-OllamaPort -Port 8080 -Persist
    # Permanently sets Ollama port to 8080
#>
function Set-OllamaPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1024, 65535)]
        [int]$Port,

        [Parameter()]
        [string]$BindAddress = "0.0.0.0",

        [Parameter()]
        [switch]$Persist
    )

    $ollamaHost = "$($BindAddress):$Port"

    # Set for current session
    $env:OLLAMA_HOST = $ollamaHost
    Write-LogMessage "Set OLLAMA_HOST to $ollamaHost for current session" -Level INFO

    if ($Persist) {
        try {
            [System.Environment]::SetEnvironmentVariable("OLLAMA_HOST", $ollamaHost, [System.EnvironmentVariableTarget]::User)
            Write-LogMessage "Persisted OLLAMA_HOST=$ollamaHost to User environment variables" -Level INFO
            Write-LogMessage "Restart Ollama service for changes to take effect" -Level WARN
        }
        catch {
            Write-LogMessage "Failed to persist OLLAMA_HOST environment variable" -Level ERROR -Exception $_
        }
    }

    # Update the default API URL in the module
    $script:DefaultApiUrl = "http://$($BindAddress):$Port"
    if ($BindAddress -eq "0.0.0.0") {
        $script:DefaultApiUrl = "http://localhost:$Port"
    }

    return [PSCustomObject]@{
        OllamaHost = $ollamaHost
        ApiUrl = $script:DefaultApiUrl
        Persisted = $Persist
    }
}

<#
.SYNOPSIS
    Sets the path where Ollama stores models.

.DESCRIPTION
    Configures the OLLAMA_MODELS environment variable to change where Ollama stores downloaded models.
    Useful for moving models to a larger drive or shared location.
    Requires Ollama service restart to take effect.

.PARAMETER Path
    The directory path for Ollama models. Must be a valid directory or creatable path.

.PARAMETER Persist
    If specified, sets the environment variable at User level (persists across sessions).

.PARAMETER CreateIfMissing
    If specified, creates the directory if it doesn't exist.

.EXAMPLE
    Set-OllamaModelsPath -Path "D:\AI\Models\Ollama"
    # Sets models path for current session

.EXAMPLE
    Set-OllamaModelsPath -Path "D:\AI\Models\Ollama" -Persist -CreateIfMissing
    # Permanently sets models path and creates directory if needed
#>
function Set-OllamaModelsPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [switch]$Persist,

        [Parameter()]
        [switch]$CreateIfMissing
    )

    # Validate/create path
    if (-not (Test-Path $Path -PathType Container)) {
        if ($CreateIfMissing) {
            try {
                New-Item -ItemType Directory -Path $Path -Force | Out-Null
                Write-LogMessage "Created models directory: $Path" -Level INFO
            }
            catch {
                Write-LogMessage "Failed to create models directory: $Path" -Level ERROR -Exception $_
                return $null
            }
        }
        else {
            Write-LogMessage "Path does not exist: $Path. Use -CreateIfMissing to create it." -Level ERROR
            return $null
        }
    }

    # Resolve to full path
    $fullPath = (Resolve-Path $Path).Path

    # Set for current session
    $env:OLLAMA_MODELS = $fullPath
    Write-LogMessage "Set OLLAMA_MODELS to $fullPath for current session" -Level INFO

    if ($Persist) {
        try {
            [System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $fullPath, [System.EnvironmentVariableTarget]::User)
            Write-LogMessage "Persisted OLLAMA_MODELS=$fullPath to User environment variables" -Level INFO
            Write-LogMessage "Restart Ollama service for changes to take effect" -Level WARN
        }
        catch {
            Write-LogMessage "Failed to persist OLLAMA_MODELS environment variable" -Level ERROR -Exception $_
        }
    }

    return [PSCustomObject]@{
        ModelsPath = $fullPath
        Persisted = $Persist
    }
}

<#
.SYNOPSIS
    Gets the current Ollama configuration.

.DESCRIPTION
    Returns the current Ollama configuration including host, port, and models path.

.EXAMPLE
    Get-OllamaConfiguration
    # Returns current Ollama settings
#>
function Get-OllamaConfiguration {
    [CmdletBinding()]
    param()

    $ollamaHost = $env:OLLAMA_HOST
    if (-not $ollamaHost) {
        $ollamaHost = "localhost:11434"
    }

    $modelsPath = $env:OLLAMA_MODELS
    if (-not $modelsPath) {
        $modelsPath = "$env:USERPROFILE\.ollama\models"
    }

    # Parse host and port
    $hostParts = $ollamaHost -split ':'
    $bindAddress = $hostParts[0]
    $port = if ($hostParts.Count -gt 1) { $hostParts[1] } else { "11434" }

    return [PSCustomObject]@{
        Host = $bindAddress
        Port = [int]$port
        OllamaHost = $ollamaHost
        ModelsPath = $modelsPath
        ApiUrl = "http://localhost:$port"
        ServiceRunning = (Test-OllamaService -ApiUrl "http://localhost:$port")
    }
}

#endregion

#region Role and Audience Functions

<#
.SYNOPSIS
    Gets available AI roles.

.DESCRIPTION
    Returns the list of predefined AI roles with their descriptions and system prompts.

.PARAMETER RoleName
    Optional specific role name to retrieve.

.EXAMPLE
    Get-OllamaRoles
    # Lists all available roles

.EXAMPLE
    Get-OllamaRoles -RoleName "CodeAssist"
    # Gets details for the CodeAssist role
#>
function Get-OllamaRoles {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet("General", "CodeAssist", "EconomicalAdvisor", "Legal", "DataAnalyst", "Writer", "ITSupport", "Teacher")]
        [string]$RoleName
    )

    if ($RoleName) {
        $role = $script:AIRoles[$RoleName]
        return [PSCustomObject]@{
            RoleKey = $RoleName
            Name = $role.Name
            Description = $role.Description
            SystemPrompt = $role.SystemPrompt
        }
    }
    else {
        return $script:AIRoles.GetEnumerator() | ForEach-Object {
            [PSCustomObject]@{
                RoleKey = $_.Key
                Name = $_.Value.Name
                Description = $_.Value.Description
            }
        } | Sort-Object RoleKey
    }
}

<#
.SYNOPSIS
    Gets available audience levels.

.DESCRIPTION
    Returns the list of audience levels for adjusting AI response complexity.

.PARAMETER Level
    Optional specific level to retrieve.

.EXAMPLE
    Get-OllamaAudienceLevels
    # Lists all audience levels

.EXAMPLE
    Get-OllamaAudienceLevels -Level "Beginner"
    # Gets details for the Beginner audience level
#>
function Get-OllamaAudienceLevels {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet("Expert", "Advanced", "Intermediate", "Beginner", "Child")]
        [string]$Level
    )

    if ($Level) {
        $audience = $script:AudienceLevels[$Level]
        return [PSCustomObject]@{
            LevelKey = $Level
            Level = $audience.Level
            Description = $audience.Description
            Modifier = $audience.Modifier
        }
    }
    else {
        return $script:AudienceLevels.GetEnumerator() | ForEach-Object {
            [PSCustomObject]@{
                LevelKey = $_.Key
                Level = $_.Value.Level
                Description = $_.Value.Description
            }
        } | Sort-Object Level -Descending
    }
}

#endregion

#region Context File Handling

<#
.SYNOPSIS
    Processes a context file for AI consumption.

.DESCRIPTION
    Reads a file and prepares it for use as context in an AI prompt.
    Handles large files by extracting relevant portions using AI-guided extraction.

.PARAMETER FilePath
    Path to the file to process.

.PARAMETER ApiUrl
    The base URL for the Ollama API.

.PARAMETER Model
    The model to use for intelligent extraction decisions.

.PARAMETER Query
    The user's query to help determine what parts of a large file to extract.

.OUTPUTS
    PSCustomObject with Content, FileName, and Truncated properties.
#>
function Get-ContextFileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter()]
        [string]$ApiUrl = $script:DefaultApiUrl,

        [Parameter()]
        [string]$Model = $script:DefaultModel,

        [Parameter()]
        [string]$Query = ""
    )

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        Write-LogMessage "Context file not found: $FilePath" -Level ERROR
        return $null
    }

    $fileName = Split-Path $FilePath -Leaf
    $fileInfo = Get-Item $FilePath
    $fileSize = $fileInfo.Length

    Write-LogMessage "Processing context file: $fileName ($([math]::Round($fileSize/1KB, 1)) KB)" -Level DEBUG

    # Read the file content
    try {
        $content = Get-Content $FilePath -Raw -Encoding UTF8
    }
    catch {
        try {
            $content = Get-Content $FilePath -Raw
        }
        catch {
            Write-LogMessage "Failed to read file: $FilePath" -Level ERROR -Exception $_
            return $null
        }
    }

    $result = [PSCustomObject]@{
        FileName = $fileName
        FilePath = $FilePath
        OriginalSize = $fileSize
        Content = $content
        Truncated = $false
        ExtractionMethod = "Full"
    }

    # Check if file is too large
    if ($fileSize -gt $script:MaxFileSizeBytes) {
        Write-LogMessage "File $fileName is large ($([math]::Round($fileSize/1KB, 1)) KB). Performing intelligent extraction..." -Level INFO
        
        $extractedContent = Invoke-IntelligentExtraction -Content $content -FileName $fileName -Query $Query -ApiUrl $ApiUrl -Model $Model
        
        if ($extractedContent) {
            $result.Content = $extractedContent.Content
            $result.Truncated = $true
            $result.ExtractionMethod = $extractedContent.Method
        }
    }

    return $result
}

<#
.SYNOPSIS
    Performs intelligent extraction from large file content.

.DESCRIPTION
    Uses AI to determine what parts of a large file are relevant to the user's query,
    then extracts those portions to create a manageable context.
#>
function Invoke-IntelligentExtraction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter()]
        [string]$Query,

        [Parameter()]
        [string]$ApiUrl = $script:DefaultApiUrl,

        [Parameter()]
        [string]$Model = $script:DefaultModel
    )

    # First, get a preview of the file structure
    $lines = $Content -split "`n"
    $lineCount = $lines.Count
    
    # Create a structural preview (first 50 lines, summary, last 20 lines)
    $preview = ""
    if ($lineCount -le 100) {
        $preview = $Content
    }
    else {
        $firstLines = ($lines | Select-Object -First 50) -join "`n"
        $lastLines = ($lines | Select-Object -Last 20) -join "`n"
        $preview = @"
=== FILE: $FileName (Total: $lineCount lines) ===

=== FIRST 50 LINES ===
$firstLines

=== LINES 51-$($lineCount - 20) OMITTED ===

=== LAST 20 LINES ===
$lastLines
"@
    }

    # Ask AI what to extract
    $extractionPrompt = @"
I have a large file ($FileName, $lineCount lines) that I need to use as context for the following query:

USER QUERY: $Query

Here's a preview of the file structure:

$preview

Please analyze this file and tell me what parts would be most relevant. Respond with ONE of these options:

1. REGEX: <pattern> - If I should extract lines matching a regex pattern
2. LINES: <start>-<end> - If I should extract specific line ranges (can be comma-separated: 1-50,100-150)
3. FUNCTIONS: <list> - If this is code and I should extract specific functions/classes
4. FIRST: <n> - If I should just use the first n lines
5. FULL - If the whole file is needed (only if absolutely necessary)

Respond with ONLY the extraction instruction, nothing else.
"@

    try {
        $extractionResponse = Invoke-OllamaGenerate -Prompt $extractionPrompt -Model $Model -ApiUrl $ApiUrl -MaxTokens 200 -SystemPrompt "You are a file analysis assistant. Respond only with the extraction instruction."
        
        if (-not $extractionResponse) {
            # Fallback: return first 100 lines
            Write-LogMessage "AI extraction failed, using fallback (first 100 lines)" -Level WARN
            return @{
                Content = ($lines | Select-Object -First 100) -join "`n"
                Method = "Fallback-First100"
            }
        }

        $instruction = $extractionResponse.Trim()
        Write-LogMessage "AI extraction instruction: $instruction" -Level DEBUG

        # Parse and execute extraction
        if ($instruction -match '^REGEX:\s*(.+)$') {
            $pattern = $Matches[1].Trim()
            Write-LogMessage "Extracting lines matching regex: $pattern" -Level DEBUG
            $extracted = $lines | Where-Object { $_ -match $pattern }
            return @{
                Content = $extracted -join "`n"
                Method = "Regex: $pattern"
            }
        }
        elseif ($instruction -match '^LINES:\s*(.+)$') {
            $ranges = $Matches[1].Trim()
            Write-LogMessage "Extracting line ranges: $ranges" -Level DEBUG
            $extractedLines = @()
            foreach ($range in ($ranges -split ',')) {
                if ($range -match '^(\d+)-(\d+)$') {
                    $start = [int]$Matches[1] - 1
                    $end = [int]$Matches[2] - 1
                    $extractedLines += $lines[$start..$end]
                }
                elseif ($range -match '^(\d+)$') {
                    $extractedLines += $lines[[int]$Matches[1] - 1]
                }
            }
            return @{
                Content = $extractedLines -join "`n"
                Method = "Lines: $ranges"
            }
        }
        elseif ($instruction -match '^FIRST:\s*(\d+)$') {
            $n = [int]$Matches[1]
            Write-LogMessage "Extracting first $n lines" -Level DEBUG
            return @{
                Content = ($lines | Select-Object -First $n) -join "`n"
                Method = "First $n lines"
            }
        }
        elseif ($instruction -match '^FULL$') {
            Write-LogMessage "AI requested full file" -Level DEBUG
            return @{
                Content = $Content
                Method = "Full (AI requested)"
            }
        }
        else {
            # Default fallback
            Write-LogMessage "Could not parse AI instruction, using first 100 lines" -Level WARN
            return @{
                Content = ($lines | Select-Object -First 100) -join "`n"
                Method = "Fallback-First100"
            }
        }
    }
    catch {
        Write-LogMessage "Intelligent extraction error" -Level ERROR -Exception $_
        return @{
            Content = ($lines | Select-Object -First 100) -join "`n"
            Method = "Error-Fallback"
        }
    }
}

#endregion

#region Core API Functions

<#
.SYNOPSIS
    Sends a prompt to an Ollama model and returns the response.

.DESCRIPTION
    Core function for generating responses from Ollama models. Used internally by other functions.

.PARAMETER Prompt
    The text prompt to send to the model.

.PARAMETER Model
    The name of the model to use.

.PARAMETER ApiUrl
    The base URL for the Ollama API.

.PARAMETER SystemPrompt
    Optional system prompt for context.

.PARAMETER Temperature
    Controls randomness (0.0-1.0).

.PARAMETER MaxTokens
    Maximum tokens to generate.

.OUTPUTS
    The generated response text, or $null on error.
#>
function Invoke-OllamaGenerate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter()]
        [string]$Model = $script:DefaultModel,

        [Parameter()]
        [string]$ApiUrl = $script:DefaultApiUrl,

        [Parameter()]
        [string]$SystemPrompt = "",

        [Parameter()]
        [ValidateRange(0.0, 1.0)]
        [double]$Temperature = 0.7,

        [Parameter()]
        [int]$MaxTokens = 2048
    )

    # Check model availability and fall back if needed
    $availableModels = Get-OllamaModels -ApiUrl $ApiUrl
    if ($Model -notin $availableModels) {
        Write-LogMessage "Model '$Model' not available. Available: $($availableModels -join ', ')" -Level WARN
        if ($availableModels.Count -gt 0) {
            $Model = $availableModels[0]
            Write-LogMessage "Using fallback model: $Model" -Level INFO
        }
        else {
            Write-LogMessage "No models available for Invoke-OllamaGenerate" -Level ERROR
            return $null
        }
    }

    $requestBody = @{
        model = $Model
        prompt = $Prompt
        stream = $false
        options = @{
            temperature = $Temperature
            num_predict = $MaxTokens
        }
    }

    if ($SystemPrompt) {
        $requestBody.system = $SystemPrompt
    }

    try {
        $response = Invoke-RestMethod -Uri "$ApiUrl/api/generate" -Method Post -Body ($requestBody | ConvertTo-Json -Depth 10) -ContentType "application/json"
        return $response.response
    }
    catch {
        Write-LogMessage "Ollama generate request failed" -Level ERROR -Exception $_
        return $null
    }
}

<#
.SYNOPSIS
    Query Ollama AI models with role-based prompting, templates, and context file support.

.DESCRIPTION
    The main function for interacting with Ollama models. Provides comprehensive AI querying with:
    
    - TEMPLATES: Use saved prompts from local or global template files
    - ROLES: 8 AI personas (CodeAssist, Teacher, Legal, etc.) with optimized system prompts
    - AUDIENCE: Adjust language complexity from Expert to Child
    - CONTEXT: Include files with intelligent large file extraction (>50KB)
    - OUTPUT: Raw text for scripts or structured object with metadata
    
    Use -Raw switch for script integration to get plain text responses.
    Combine -Template with -ContextFiles to generate reports from log files.

.PARAMETER Prompt
    The question or instruction to send to the model. Can be combined with -Template.

.PARAMETER Template
    Name of a saved template from local or global template files.
    Templates are loaded from $env:OptPath\data\OllamaTemplates\OllamaTemplates.json (local)
    or the path configured in GlobalSettings.json (global).

.PARAMETER Model
    The Ollama model to use. Auto-selects first available if not specified.

.PARAMETER Role
    AI persona: General, CodeAssist, EconomicalAdvisor, Legal, DataAnalyst, Writer, ITSupport, Teacher.

.PARAMETER Audience
    Language complexity: Expert, Advanced, Intermediate, Beginner, Child.

.PARAMETER ContextFiles
    Array of file paths to include as context. Large files (>50KB) trigger intelligent extraction.

.PARAMETER SystemPrompt
    Custom system prompt (overrides Role-based prompt if specified).

.PARAMETER ApiUrl
    The Ollama API URL. Defaults to http://localhost:11434.

.PARAMETER Temperature
    Response creativity (0.0-1.0). Lower = more deterministic. Default: 0.7.

.PARAMETER MaxTokens
    Maximum tokens to generate. Default: 4096.

.PARAMETER Raw
    Returns plain text instead of PSCustomObject. Use for script output and file saving.

Qm6_pL4-cN8+fH3.xV    
.EXAMPLE
    Invoke-Ollama -Prompt "What is PowerShell?" -Raw
    # Simple query returning text

.EXAMPLE
    $response = Invoke-Ollama -Template "CreateBankTerminalOrderReport" -ContextFiles @("log.txt") -Raw
    $response | Set-Content "report.md" -Encoding UTF8
    # Generate markdown report from template and save to file

.EXAMPLE
    Invoke-Ollama -Prompt "Review this code" -Role CodeAssist -ContextFiles @(".\script.ps1")
    # Code review with context file

.EXAMPLE
    Invoke-Ollama -Prompt "Explain recursion" -Role Teacher -Audience Beginner
    # Teaching with beginner-friendly language

.EXAMPLE
    $response = Invoke-Ollama -Prompt "Analyze this data" -Role DataAnalyst -Audience Expert -Raw
    # Get raw response text for scripting

.OUTPUTS
    PSCustomObject with Response, Model, Role, Audience, and other metadata.
    Or just the response text if -Raw is specified.
#>
function Invoke-Ollama {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = "",

        [Parameter()]
        [string]$Template = "",

        [Parameter()]
        [string]$Model = $script:DefaultModel,

        [Parameter()]
        [ValidateSet("General", "CodeAssist", "EconomicalAdvisor", "Legal", "DataAnalyst", "Writer", "ITSupport", "Teacher")]
        [string]$Role = "General",

        [Parameter()]
        [ValidateSet("Expert", "Advanced", "Intermediate", "Beginner", "Child")]
        [string]$Audience = "Intermediate",

        [Parameter()]
        [string[]]$ContextFiles = @(),

        [Parameter()]
        [string]$SystemPrompt = "",

        [Parameter()]
        [string]$ApiUrl = $script:DefaultApiUrl,

        [Parameter()]
        [ValidateRange(0.0, 1.0)]
        [double]$Temperature = 0.7,

        [Parameter()]
        [int]$MaxTokens = 4096,

        [Parameter()]
        [switch]$Raw
    )

    # Handle template if specified
    if ($Template) {
        $templateObj = Get-OllamaTemplates -TemplateName $Template
        if ($templateObj) {
            Write-LogMessage "Using template: $Template (Source: $($templateObj.Source))" -Level INFO
            # Template prompt is appended to any user prompt
            if ($Prompt) {
                $Prompt = "$Prompt`n`n$($templateObj.Prompt)"
            }
            else {
                $Prompt = $templateObj.Prompt
            }
        }
        else {
            Write-LogMessage "Template '$Template' not found in local or global templates" -Level WARN
        }
    }

    # Validate that we have a prompt
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        Write-LogMessage "No prompt provided and no valid template specified" -Level ERROR
        if ($Raw) { return $null }
        return [PSCustomObject]@{
            Success = $false
            Error = "No prompt provided"
            Response = $null
        }
    }

    # Ensure Ollama is running
    if (-not (Test-OllamaService -ApiUrl $ApiUrl)) {
        Write-LogMessage "Ollama service not running. Attempting to start..." -Level WARN
        if (-not (Start-OllamaService -ApiUrl $ApiUrl)) {
            Write-LogMessage "Cannot connect to Ollama service at $ApiUrl" -Level ERROR
            if ($Raw) { return $null }
            return [PSCustomObject]@{
                Success = $false
                Error = "Ollama service not available"
                Response = $null
            }
        }
    }

    # Check model availability
    $availableModels = Get-OllamaModels -ApiUrl $ApiUrl
    if ($Model -notin $availableModels) {
        Write-LogMessage "Model '$Model' not available. Available: $($availableModels -join ', ')" -Level WARN
        if ($availableModels.Count -gt 0) {
            $Model = $availableModels[0]
            Write-LogMessage "Using fallback model: $Model" -Level INFO
        }
        else {
            if ($Raw) { return $null }
            return [PSCustomObject]@{
                Success = $false
                Error = "No models available"
                Response = $null
            }
        }
    }

    # Build system prompt
    $effectiveSystemPrompt = $SystemPrompt
    if (-not $effectiveSystemPrompt) {
        $roleInfo = $script:AIRoles[$Role]
        $audienceInfo = $script:AudienceLevels[$Audience]
        
        $effectiveSystemPrompt = @"
$($roleInfo.SystemPrompt)

AUDIENCE ADAPTATION:
$($audienceInfo.Modifier)
"@
    }

    # Process context files
    $contextContent = ""
    $processedFiles = @()
    
    foreach ($contextFile in $ContextFiles) {
        $fileContent = Get-ContextFileContent -FilePath $contextFile -ApiUrl $ApiUrl -Model $Model -Query $Prompt
        if ($fileContent) {
            $contextContent += @"

=== CONTEXT FILE: $($fileContent.FileName) ===
$($fileContent.Content)
=== END: $($fileContent.FileName) ===

"@
            $processedFiles += [PSCustomObject]@{
                FileName = $fileContent.FileName
                OriginalSize = $fileContent.OriginalSize
                Truncated = $fileContent.Truncated
                ExtractionMethod = $fileContent.ExtractionMethod
            }
        }
    }

    # Build final prompt with context
    $finalPrompt = $Prompt
    if ($contextContent) {
        $finalPrompt = @"
The following context files have been provided for reference:

$contextContent

USER REQUEST:
$Prompt
"@
    }

    # Make the request
    Write-LogMessage "Sending request to Ollama (Model: $Model, Role: $Role, Audience: $Audience)" -Level DEBUG
    
    $response = Invoke-OllamaGenerate -Prompt $finalPrompt -Model $Model -ApiUrl $ApiUrl -SystemPrompt $effectiveSystemPrompt -Temperature $Temperature -MaxTokens $MaxTokens

    if ($Raw) {
        return $response
    }

    return [PSCustomObject]@{
        Success = ($null -ne $response)
        Response = $response
        Model = $Model
        Role = $Role
        Audience = $Audience
        ContextFiles = $processedFiles
        Timestamp = Get-Date
        Error = if ($null -eq $response) { "Failed to generate response" } else { $null }
    }
}

#endregion

#region Interactive Chat Function

<#
.SYNOPSIS
    Interactive chat interface for Ollama AI with templates, context files, and export.

.DESCRIPTION
    Full-featured interactive chat session with comprehensive capabilities:
    
    CHAT FEATURES:
    - Conversation history with context
    - Multi-line paste mode (/paste)
    - Add files with @filepath syntax
    - Save chat to markdown (/save)
    
    CONFIGURATION:
    - Switch models, roles, audience on-the-fly
    - Adjust temperature and token limits
    - View current settings (/status)
    
    TEMPLATES:
    - List templates (/templates) with [LOCAL]/[GLOBAL] tags
    - Apply templates (/use <name>)
    - Save prompts as templates (/savetemp <name>)
    
    COMMANDS: /help, /models, /switch, /roles, /role, /audience, /temp, /tokens,
              @filepath, /paste, /templates, /use, /savetemp, /save, /status, /clear, /quit

.PARAMETER Model
    The initial model to use. Auto-selects if not available.

.PARAMETER Role
    AI persona: General, CodeAssist, EconomicalAdvisor, Legal, DataAnalyst, Writer, ITSupport, Teacher.

.PARAMETER Audience
    Language complexity: Expert, Advanced, Intermediate, Beginner, Child.

.PARAMETER ApiUrl
    The Ollama API URL.

.EXAMPLE
    Start-OllamaChat
    # Starts interactive chat with defaults

.EXAMPLE
    Start-OllamaChat -Model "gemma3:2b" -Role CodeAssist -Audience Expert
    # Starts chat configured for expert coding assistance
#>
function Start-OllamaChat {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Model = $script:DefaultModel,

        [Parameter()]
        [ValidateSet("General", "CodeAssist", "EconomicalAdvisor", "Legal", "DataAnalyst", "Writer", "ITSupport", "Teacher")]
        [string]$Role = "General",

        [Parameter()]
        [ValidateSet("Expert", "Advanced", "Intermediate", "Beginner", "Child")]
        [string]$Audience = "Intermediate",

        [Parameter()]
        [string]$ApiUrl = $script:DefaultApiUrl,

        [Parameter()]
        [double]$Temperature = 0.7,

        [Parameter()]
        [int]$MaxTokens = 2048
    )

    # Check service
    if (-not (Test-OllamaService -ApiUrl $ApiUrl)) {
        Write-Host "Ollama service not running. Starting..." -ForegroundColor Yellow
        if (-not (Start-OllamaService -ApiUrl $ApiUrl)) {
            Write-Host "Failed to start Ollama. Please start it manually." -ForegroundColor Red
            return
        }
    }

    # Check model
    $availableModels = Get-OllamaModels -ApiUrl $ApiUrl
    if ($Model -notin $availableModels) {
        if ($availableModels.Count -gt 0) {
            Write-Host "Model '$Model' not available. Using: $($availableModels[0])" -ForegroundColor Yellow
            $Model = $availableModels[0]
        }
        else {
            Write-Host "No models available. Install a model with: ollama pull <model-name>" -ForegroundColor Red
            return
        }
    }

    # Display header
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              OLLAMA INTERACTIVE CHAT                           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Model:    $Model" -ForegroundColor Yellow
    Write-Host "  Role:     $Role ($($script:AIRoles[$Role].Name))" -ForegroundColor Yellow
    Write-Host "  Audience: $Audience" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Commands:" -ForegroundColor Green
    Write-Host "    /help           - Show all commands" -ForegroundColor White
    Write-Host "    /models         - List available models" -ForegroundColor White
    Write-Host "    /switch         - Switch to different model" -ForegroundColor White
    Write-Host "    /roles          - List available roles" -ForegroundColor White
    Write-Host "    /role <name>    - Change current role" -ForegroundColor White
    Write-Host "    /audience       - Change audience level" -ForegroundColor White
    Write-Host "    /temp <0.0-1.0> - Set temperature (creativity)" -ForegroundColor White
    Write-Host "    /tokens <num>   - Set max tokens (response length)" -ForegroundColor White
    Write-Host "    @filepath       - Add file as context" -ForegroundColor White
    Write-Host "    /paste          - Multi-line input mode" -ForegroundColor White
    Write-Host "    /templates      - List and use prompt templates" -ForegroundColor White
    Write-Host "    /save [file]    - Save AI responses to markdown" -ForegroundColor White
    Write-Host "    /status         - Show current settings" -ForegroundColor White
    Write-Host "    /clear          - Clear chat history" -ForegroundColor White
    Write-Host "    /quit           - Exit chat" -ForegroundColor White
    Write-Host ""

    $chatHistory = @()
    $contextFiles = @()

    :chatLoop while ($true) {
        Write-Host "`nYou: " -ForegroundColor Blue -NoNewline
        $userInput = Read-Host

        if ([string]::IsNullOrWhiteSpace($userInput)) {
            continue chatLoop
        }

        # Handle @filepath syntax for adding context files
        # Regex: @           - literal @ symbol at start of reference
        #        "([^"]+)"   - quoted path (capture group 1) - handles paths with spaces
        #        |           - OR
        #        (\S+)       - unquoted path (capture group 2) - no spaces allowed
        #        (.*)        - optional remainder of input (capture group 3) - the actual question
        while ($userInput -match '@"([^"]+)"|@(\S+)') {
            $filePath = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
            
            # Resolve relative paths
            if (-not [System.IO.Path]::IsPathRooted($filePath)) {
                $filePath = Join-Path (Get-Location) $filePath
            }
            
            if (Test-Path $filePath -PathType Leaf) {
                if ($filePath -notin $contextFiles) {
                    $contextFiles += $filePath
                    Write-Host "  + Added context: $(Split-Path $filePath -Leaf)" -ForegroundColor DarkGreen
                }
            }
            else {
                Write-Host "  ! File not found: $filePath" -ForegroundColor DarkYellow
            }
            
            # Remove the @reference from input (both quoted and unquoted forms)
            $userInput = $userInput -replace '@"[^"]+"', '' -replace '@\S+', ''
            $userInput = $userInput.Trim()
        }
        
        # If only @files were provided with no question, show status and continue
        if ([string]::IsNullOrWhiteSpace($userInput)) {
            Write-Host "  Context files: $($contextFiles.Count)" -ForegroundColor DarkGray
            continue chatLoop
        }

        # Handle commands
        switch -Regex ($userInput.ToLower().Trim()) {
            "^/help$" {
                Write-Host "`nCommands:" -ForegroundColor Green
                Write-Host "  /help           - Show this help" -ForegroundColor White
                Write-Host "  /models         - List available models" -ForegroundColor White
                Write-Host "  /roles          - List available roles" -ForegroundColor White
                Write-Host "  /switch         - Switch to different model" -ForegroundColor White
                Write-Host "  /role <name>    - Change current role" -ForegroundColor White
                Write-Host "  /audience       - List and change audience levels" -ForegroundColor White
                Write-Host "  /temp <0.0-1.0> - Set temperature (creativity)" -ForegroundColor White
                Write-Host "  /tokens <num>   - Set max tokens (response length)" -ForegroundColor White
                Write-Host "  /context        - Add context file" -ForegroundColor White
                Write-Host "  @filepath       - Add file as context (or @`"path with spaces`")" -ForegroundColor White
                Write-Host "  /paste          - Enter multi-line text (end with blank line)" -ForegroundColor White
                Write-Host "  /templates      - List available templates (local/global)" -ForegroundColor White
                Write-Host "  /use <name>     - Use a template as prompt" -ForegroundColor White
                Write-Host "  /savetemp <n>   - Save last prompt as template" -ForegroundColor White
                Write-Host "  /save [file]    - Save AI responses to markdown" -ForegroundColor White
                Write-Host "  /save full [f]  - Save full dialog to markdown" -ForegroundColor White
                Write-Host "  /status         - Show current settings" -ForegroundColor White
                Write-Host "  /clear          - Clear chat history" -ForegroundColor White
                Write-Host "  /quit           - Exit chat" -ForegroundColor White
                continue chatLoop
            }
            "^/models$" {
                Write-Host "`nAvailable models:" -ForegroundColor Green
                $models = Get-OllamaModels -ApiUrl $ApiUrl -IncludeDetails
                $models | ForEach-Object {
                    $marker = if ($_.Name -eq $Model) { " [ACTIVE]" } else { "" }
                    Write-Host "  $($_.Name)$marker - $($_.SizeGB)" -ForegroundColor White
                }
                continue chatLoop
            }
            "^/roles$" {
                Write-Host "`nAvailable roles:" -ForegroundColor Green
                Get-OllamaRoles | ForEach-Object {
                    $marker = if ($_.RoleKey -eq $Role) { " [ACTIVE]" } else { "" }
                    Write-Host "  $($_.RoleKey)$marker - $($_.Description)" -ForegroundColor White
                }
                continue chatLoop
            }
            "^/audience$" {
                Write-Host "`nAudience levels:" -ForegroundColor Green
                Get-OllamaAudienceLevels | ForEach-Object {
                    $marker = if ($_.LevelKey -eq $Audience) { " [ACTIVE]" } else { "" }
                    Write-Host "  $($_.LevelKey)$marker - $($_.Description)" -ForegroundColor White
                }
                Write-Host "`nSelect level (Expert/Advanced/Intermediate/Beginner/Child): " -ForegroundColor Yellow -NoNewline
                $selection = Read-Host
                if ($selection -in @("Expert", "Advanced", "Intermediate", "Beginner", "Child")) {
                    $Audience = $selection
                    Write-Host "Audience set to: $Audience" -ForegroundColor Green
                }
                else {
                    Write-Host "Invalid selection." -ForegroundColor Red
                }
                continue chatLoop
            }
            "^/switch$" {
                $models = Get-OllamaModels -ApiUrl $ApiUrl
                for ($i = 0; $i -lt $models.Count; $i++) {
                    Write-Host "  $($i + 1). $($models[$i])" -ForegroundColor White
                }
                Write-Host "`nSelect model number: " -ForegroundColor Yellow -NoNewline
                $selection = Read-Host
                if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $models.Count) {
                    $Model = $models[[int]$selection - 1]
                    Write-Host "Switched to: $Model" -ForegroundColor Green
                    $chatHistory = @()
                }
                else {
                    Write-Host "Invalid selection." -ForegroundColor Red
                }
                continue chatLoop
            }
            "^/role\s+(\w+)$" {
                $newRole = $Matches[1]
                if ($newRole -in $script:AIRoles.Keys) {
                    $Role = $newRole
                    Write-Host "Role changed to: $Role" -ForegroundColor Green
                }
                else {
                    Write-Host "Invalid role. Use /roles to see available roles." -ForegroundColor Red
                }
                continue chatLoop
            }
            # Regex: ^/temp\s+  - starts with /temp followed by whitespace
            #        ([\d.]+)   - capture group for decimal number (digits and dots)
            #        $          - end of string
            "^/temp\s+([\d.]+)$" {
                $newTemp = $Matches[1]
                try {
                    $tempValue = [double]$newTemp
                    if ($tempValue -ge 0.0 -and $tempValue -le 1.0) {
                        $Temperature = $tempValue
                        Write-Host "Temperature set to: $Temperature" -ForegroundColor Green
                    }
                    else {
                        Write-Host "Temperature must be between 0.0 and 1.0" -ForegroundColor Red
                    }
                }
                catch {
                    Write-Host "Invalid temperature value. Use a number between 0.0 and 1.0" -ForegroundColor Red
                }
                continue chatLoop
            }
            "^/temp$" {
                Write-Host "`nTemperature controls response creativity:" -ForegroundColor Green
                Write-Host "  0.0-0.3 - More focused, deterministic responses" -ForegroundColor White
                Write-Host "  0.4-0.6 - Balanced creativity and consistency" -ForegroundColor White
                Write-Host "  0.7-1.0 - More creative, varied responses" -ForegroundColor White
                Write-Host "`nCurrent: $Temperature" -ForegroundColor Yellow
                Write-Host "Usage: /temp 0.5" -ForegroundColor DarkGray
                continue chatLoop
            }
            # Regex: ^/tokens\s+  - starts with /tokens followed by whitespace
            #        (\d+)        - capture group for integer (digits only)
            #        $            - end of string
            "^/tokens\s+(\d+)$" {
                $newTokens = [int]$Matches[1]
                if ($newTokens -ge 100 -and $newTokens -le 32768) {
                    $MaxTokens = $newTokens
                    Write-Host "Max tokens set to: $MaxTokens" -ForegroundColor Green
                }
                else {
                    Write-Host "Max tokens must be between 100 and 32768" -ForegroundColor Red
                }
                continue chatLoop
            }
            "^/tokens$" {
                Write-Host "`nMax tokens controls response length:" -ForegroundColor Green
                Write-Host "  512-1024   - Short responses" -ForegroundColor White
                Write-Host "  2048-4096  - Medium responses (default)" -ForegroundColor White
                Write-Host "  8192-32768 - Long, detailed responses" -ForegroundColor White
                Write-Host "`nCurrent: $MaxTokens" -ForegroundColor Yellow
                Write-Host "Usage: /tokens 4096" -ForegroundColor DarkGray
                continue chatLoop
            }
            "^/context$" {
                Write-Host "Enter file path: " -ForegroundColor Yellow -NoNewline
                $filePath = Read-Host
                if (Test-Path $filePath -PathType Leaf) {
                    $contextFiles += $filePath
                    Write-Host "Added context: $filePath" -ForegroundColor Green
                }
                else {
                    Write-Host "File not found: $filePath" -ForegroundColor Red
                }
                continue chatLoop
            }
            "^/paste$" {
                Write-Host "`nMulti-line input mode. Paste your text and press Enter twice (blank line) to send:" -ForegroundColor Yellow
                Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                
                $multiLineInput = @()
                $consecutiveEmpty = 0
                
                while ($true) {
                    $line = Read-Host
                    
                    if ([string]::IsNullOrEmpty($line)) {
                        $consecutiveEmpty++
                        if ($consecutiveEmpty -ge 1) {
                            # One blank line ends input
                            break
                        }
                        $multiLineInput += ""
                    }
                    else {
                        $consecutiveEmpty = 0
                        $multiLineInput += $line
                    }
                }
                
                Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                
                if ($multiLineInput.Count -eq 0) {
                    Write-Host "No input received." -ForegroundColor Yellow
                    continue chatLoop
                }
                
                # Join the lines and use as input
                $userInput = $multiLineInput -join "`n"
                Write-Host "Received $($multiLineInput.Count) line(s)" -ForegroundColor DarkGray
                
                # Don't continue - fall through to process the input
            }
            "^/templates$" {
                Write-Host "`nAvailable Templates:" -ForegroundColor Green
                Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                
                $allTemplates = Get-OllamaTemplates
                
                if ($allTemplates.Count -eq 0) {
                    Write-Host "  No templates found." -ForegroundColor DarkGray
                    Write-Host "  Use /savetemp <name> to save the current prompt as a template." -ForegroundColor DarkGray
                }
                else {
                    $index = 1
                    foreach ($tmpl in $allTemplates) {
                        $sourceTag = if ($tmpl.Source -eq "Local") { "[LOCAL]" } else { "[GLOBAL]" }
                        $sourceColor = if ($tmpl.Source -eq "Local") { "Cyan" } else { "Magenta" }
                        
                        Write-Host "  $index. " -ForegroundColor White -NoNewline
                        Write-Host "$sourceTag " -ForegroundColor $sourceColor -NoNewline
                        Write-Host "$($tmpl.Name)" -ForegroundColor Yellow
                        if ($tmpl.Description) {
                            Write-Host "     $($tmpl.Description)" -ForegroundColor DarkGray
                        }
                        $index++
                    }
                }
                
                Write-Host ""
                Write-Host "Use: /use <name> to apply a template" -ForegroundColor DarkGray
                continue chatLoop
            }
            # Regex: ^/use\s+   - starts with /use followed by whitespace
            #        (.+)       - capture group for template name
            #        $          - end of string
            "^/use\s+(.+)$" {
                $templateName = $Matches[1].Trim()
                $templateObj = Get-OllamaTemplates -TemplateName $templateName
                
                if ($templateObj) {
                    Write-Host "`nUsing template: $templateName" -ForegroundColor Green
                    Write-Host "Source: $($templateObj.Source)" -ForegroundColor DarkGray
                    Write-Host ""
                    
                    # Set the user input to the template prompt
                    $userInput = $templateObj.Prompt
                    Write-Host "Template applied. Processing..." -ForegroundColor DarkGray
                    
                    # Don't continue - fall through to process the input
                }
                else {
                    Write-Host "Template not found: $templateName" -ForegroundColor Red
                    Write-Host "Use /templates to see available templates." -ForegroundColor DarkGray
                    continue chatLoop
                }
            }
            # Regex: ^/savetemp\s+   - starts with /savetemp followed by whitespace
            #        (.+)            - capture group for template name
            #        $               - end of string
            "^/savetemp\s+(.+)$" {
                $templateName = $Matches[1].Trim()
                
                # Get last user prompt from history
                $lastUserMessage = $chatHistory | Where-Object { $_.role -eq "user" } | Select-Object -Last 1
                
                if (-not $lastUserMessage) {
                    Write-Host "No previous prompt to save as template." -ForegroundColor Red
                    continue chatLoop
                }
                
                Write-Host "`nSaving template: $templateName" -ForegroundColor Yellow
                Write-Host "Enter description (optional): " -ForegroundColor Yellow -NoNewline
                $description = Read-Host
                
                $saved = Save-OllamaTemplate -Name $templateName -Prompt $lastUserMessage.content -Description $description
                
                if ($saved) {
                    Write-Host "Template saved successfully!" -ForegroundColor Green
                }
                else {
                    Write-Host "Failed to save template." -ForegroundColor Red
                }
                continue chatLoop
            }
            "^/status$" {
                Write-Host "`nCurrent Settings:" -ForegroundColor Green
                Write-Host "  Model:       $Model" -ForegroundColor White
                Write-Host "  Role:        $Role" -ForegroundColor White
                Write-Host "  Audience:    $Audience" -ForegroundColor White
                Write-Host "  Temperature: $Temperature" -ForegroundColor White
                Write-Host "  Max Tokens:  $MaxTokens" -ForegroundColor White
                Write-Host "  Context:     $($contextFiles.Count) file(s)" -ForegroundColor White
                Write-Host "  History:     $($chatHistory.Count) messages" -ForegroundColor White
                continue chatLoop
            }
            # Regex: ^/save      - starts with /save
            #        (?:\s+(.+))? - optional: whitespace followed by capture group for arguments
            #        $           - end of string
            "^/save(?:\s+(.+))?$" {
                $saveArgs = if ($Matches[1]) { $Matches[1].Trim() } else { "" }
                
                # Parse arguments: [full] [filename]
                $includeDialog = $false
                $outputFile = ""
                
                if ($saveArgs -match "^full\s*(.*)$") {
                    $includeDialog = $true
                    $outputFile = $Matches[1].Trim()
                }
                elseif ($saveArgs) {
                    $outputFile = $saveArgs
                }
                
                # Generate default filename if not specified
                if (-not $outputFile) {
                    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                    $outputFile = "ollama-chat-$timestamp.md"
                }
                
                # Ensure .md extension
                if (-not $outputFile.EndsWith(".md")) {
                    $outputFile += ".md"
                }
                
                # Build markdown content
                $mdContent = @()
                $mdContent += "# Ollama Chat Export"
                $mdContent += ""
                $mdContent += "**Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $mdContent += "**Model:** $Model"
                $mdContent += "**Role:** $Role"
                $mdContent += "**Audience:** $Audience"
                $mdContent += ""
                $mdContent += "---"
                $mdContent += ""
                
                if ($chatHistory.Count -eq 0) {
                    Write-Host "No chat history to save." -ForegroundColor Yellow
                    continue chatLoop
                }
                
                if ($includeDialog) {
                    # Full dialog mode
                    $mdContent += "## Conversation"
                    $mdContent += ""
                    foreach ($msg in $chatHistory) {
                        if ($msg.role -eq "user") {
                            $mdContent += "### User"
                            $mdContent += ""
                            $mdContent += $msg.content
                            $mdContent += ""
                        }
                        else {
                            $mdContent += "### Assistant"
                            $mdContent += ""
                            $mdContent += $msg.content
                            $mdContent += ""
                        }
                    }
                }
                else {
                    # AI responses only (default)
                    $mdContent += "## AI Responses"
                    $mdContent += ""
                    $responseNum = 1
                    foreach ($msg in $chatHistory) {
                        if ($msg.role -eq "assistant") {
                            if ($responseNum -gt 1) {
                                $mdContent += "---"
                                $mdContent += ""
                            }
                            $mdContent += $msg.content
                            $mdContent += ""
                            $responseNum++
                        }
                    }
                }
                
                # Write to file
                try {
                    $mdContent -join "`n" | Set-Content -Path $outputFile -Encoding UTF8
                    $fullPath = (Resolve-Path $outputFile).Path
                    Write-Host "Saved to: $fullPath" -ForegroundColor Green
                    if ($includeDialog) {
                        Write-Host "  Mode: Full dialog" -ForegroundColor DarkGray
                    }
                    else {
                        Write-Host "  Mode: AI responses only" -ForegroundColor DarkGray
                    }
                }
                catch {
                    Write-Host "Failed to save: $($_.Exception.Message)" -ForegroundColor Red
                }
                continue chatLoop
            }
            "^/clear$" {
                $chatHistory = @()
                $contextFiles = @()
                Write-Host "Chat history and context cleared." -ForegroundColor Green
                continue chatLoop
            }
            "^/quit$" {
                Write-Host "Goodbye!" -ForegroundColor Green
                return
            }
        }

        # Generate response
        Write-Host "`nAssistant: " -ForegroundColor Green -NoNewline
        Write-Host "(thinking...)" -ForegroundColor DarkGray -NoNewline

        # Add to history
        $chatHistory += @{ role = "user"; content = $userInput }

        # Build context from history
        $contextPrompt = ""
        if ($chatHistory.Count -gt 1) {
            $recentHistory = $chatHistory | Select-Object -Last 10
            $contextPrompt = ($recentHistory | ForEach-Object { "$($_.role): $($_.content)" }) -join "`n"
        }
        else {
            $contextPrompt = $userInput
        }

        $response = Invoke-Ollama -Prompt $contextPrompt -Model $Model -Role $Role -Audience $Audience -ContextFiles $contextFiles -Temperature $Temperature -MaxTokens $MaxTokens -Raw

        # Clear the "thinking..." message
        Write-Host "`r                          `r" -NoNewline
        Write-Host "Assistant: " -ForegroundColor Green -NoNewline

        if ($response) {
            Write-Host $response -ForegroundColor White
            $chatHistory += @{ role = "assistant"; content = $response }
        }
        else {
            Write-Host "Failed to generate response." -ForegroundColor Red
        }
    }
}

#endregion

#region Installation and Model Library Functions

<#
.SYNOPSIS
    Gets the path to the Ollama executable, installing if missing.

.DESCRIPTION
    Finds the Ollama executable path. If Ollama is not installed and -InstallIfMissing
    is specified, attempts to install it using winget.

.PARAMETER InstallIfMissing
    If specified and Ollama is not found, attempts to install via winget.

.EXAMPLE
    Get-OllamaPath
    # Returns path to ollama.exe or $null if not found

.EXAMPLE
    Get-OllamaPath -InstallIfMissing
    # Installs Ollama if not found, then returns path
#>
function Get-OllamaPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$InstallIfMissing
    )

    # Common installation paths
    $commonPaths = @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:ProgramFiles\Ollama\ollama.exe",
        "C:\Ollama\ollama.exe",
        "C:\Program Files\Ollama\ollama.exe"
    )
    
    # Check common paths first
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    # Try Get-Command
    $cmd = Get-Command "ollama" -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    # Not found - attempt install if requested
    if ($InstallIfMissing) {
        Write-LogMessage "Ollama not found. Attempting installation via winget..." -Level INFO
        $installed = Install-Ollama
        if ($installed) {
            # Re-check paths after installation
            foreach ($path in $commonPaths) {
                if (Test-Path $path) {
                    return $path
                }
            }
        }
    }

    return $null
}

<#
.SYNOPSIS
    Installs Ollama using winget.

.DESCRIPTION
    Installs the Ollama application using Windows Package Manager (winget).
    Returns $true on success, $false on failure.

.PARAMETER Force
    If specified, reinstalls even if Ollama is already installed.

.EXAMPLE
    Install-Ollama
    # Installs Ollama if not already present

.EXAMPLE
    Install-Ollama -Force
    # Forces reinstallation of Ollama
#>
function Install-Ollama {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force
    )

    # Check if already installed
    if (-not $Force) {
        $existingPath = Get-OllamaPath
        if ($existingPath) {
            Write-LogMessage "Ollama is already installed at: $existingPath" -Level INFO
            return $true
        }
    }

    # Check if winget is available
    $wingetCmd = Get-Command "winget" -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        Write-LogMessage "Winget is not available. Please install Ollama manually from https://ollama.com" -Level ERROR
        return $false
    }

    Write-LogMessage "Installing Ollama via winget..." -Level INFO
    
    try {
        $installArgs = @("install", "--id", "Ollama.Ollama", "--accept-source-agreements", "--accept-package-agreements")
        if ($Force) {
            $installArgs += "--force"
        }
        
        $process = Start-Process -FilePath "winget" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-LogMessage "Ollama installed successfully!" -Level INFO
            
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            
            return $true
        }
        else {
            Write-LogMessage "Winget installation returned exit code: $($process.ExitCode)" -Level WARN
            # Exit code 0x8A150011 (-1978335215) means already installed
            if ($process.ExitCode -eq -1978335215) {
                Write-LogMessage "Ollama is already installed" -Level INFO
                return $true
            }
            return $false
        }
    }
    catch {
        Write-LogMessage "Failed to install Ollama" -Level ERROR -Exception $_
        return $false
    }
}

<#
.SYNOPSIS
    Fetches the list of available models from the Ollama library.

.DESCRIPTION
    Scrapes the Ollama library website to get a list of available models
    with their metadata including name, description, and download counts.

.PARAMETER IncludeInstalled
    If specified, marks models that are already installed locally.

.PARAMETER Search
    Optional search term to filter models by name or description.

.EXAMPLE
    Get-OllamaModelLibrary
    # Returns all available models from Ollama library

.EXAMPLE
    Get-OllamaModelLibrary -Search "llama" -IncludeInstalled
    # Searches for llama models and marks installed ones
#>
function Get-OllamaModelLibrary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeInstalled,

        [Parameter()]
        [string]$Search = ""
    )

    $url = "https://ollama.com/library"
    
    try {
        Write-LogMessage "Fetching Ollama model library from $url" -Level DEBUG
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
    }
    catch {
        Write-LogMessage "Failed to fetch Ollama library" -Level ERROR -Exception $_
        return @()
    }

    $html = $response.Content
    $models = @()
    
    # Regex pattern explanation:
    # <a[^>]*href="/library/   - Match anchor tag with href starting with /library/
    # ([^/?#"]+)               - Capture group 1: model name (no slashes, query strings, or hashes)
    # "[^>]*>                  - Rest of anchor tag opening
    # ([\s\S]*?)               - Capture group 2: anchor content (lazy match, including newlines)
    # </a>                     - Closing anchor tag
    $modelLinkPattern = '<a[^>]*href="/library/([^/?#"]+)"[^>]*>([\s\S]*?)</a>'
    $modelMatches = [regex]::Matches($html, $modelLinkPattern)
    
    $processedNames = @{}
    
    foreach ($match in $modelMatches) {
        $modelName = $match.Groups[1].Value
        $anchorContent = $match.Groups[2].Value
        
        # Skip if already processed (avoid duplicates)
        if ($processedNames.ContainsKey($modelName)) {
            continue
        }
        $processedNames[$modelName] = $true
        
        # Skip non-model links (like "featured", etc.)
        if ($modelName -in @("featured", "search", "models", "")) {
            continue
        }

        $modelObj = [PSCustomObject]@{
            Name        = $modelName
            Title       = $modelName
            Description = ""
            Downloads   = ""
            Tags        = @()
            Installed   = $false
        }

        # Try to extract title from heading or span
        if ($anchorContent -match '<h[1-6][^>]*>([^<]+)</h[1-6]>') {
            $modelObj.Title = $matches[1].Trim()
        }
        elseif ($anchorContent -match '<span[^>]*class="[^"]*truncate[^"]*"[^>]*>([^<]+)</span>') {
            $modelObj.Title = $matches[1].Trim()
        }

        # Try to extract description
        if ($anchorContent -match '<p[^>]*class="[^"]*text-neutral[^"]*"[^>]*>([^<]+)</p>') {
            $modelObj.Description = $matches[1].Trim()
        }
        elseif ($anchorContent -match '<span[^>]*>([^<]{20,})</span>') {
            # Longer text is likely a description
            $modelObj.Description = $matches[1].Trim()
        }

        # Try to extract download count
        if ($anchorContent -match '([\d\.]+[KMB]?)\s*(?:Pulls|Downloads)') {
            $modelObj.Downloads = $matches[1]
        }

        # Try to extract tags
        $tagPattern = '<span[^>]*class="[^"]*(?:tag|badge|chip)[^"]*"[^>]*>([^<]+)</span>'
        $tagMatches = [regex]::Matches($anchorContent, $tagPattern)
        if ($tagMatches.Count -gt 0) {
            $modelObj.Tags = $tagMatches | ForEach-Object { $_.Groups[1].Value.Trim() }
        }

        $models += $modelObj
    }
    
    # Mark installed models if requested
    if ($IncludeInstalled) {
        $installedModels = Get-OllamaModels -ErrorAction SilentlyContinue
        foreach ($model in $models) {
            # Check both exact name and base name (without tag)
            $baseName = $model.Name.Split(':')[0]
            $isInstalled = $installedModels | Where-Object { 
                $_ -eq $model.Name -or 
                $_.Split(':')[0] -eq $baseName 
            }
            if ($isInstalled) {
                $model.Installed = $true
            }
        }
    }
    
    # Apply search filter if specified
    if ($Search) {
        $models = $models | Where-Object {
            $_.Name -match $Search -or 
            $_.Title -match $Search -or 
            $_.Description -match $Search
        }
    }
    
    return $models
}

<#
.SYNOPSIS
    Returns a static list of recommended Ollama models.

.DESCRIPTION
    Returns a predefined list of popular Ollama models with metadata including
    size classifications for different hardware capabilities.

.PARAMETER ModelGroup
    Filter by model group: All, LessThan6GB, LessThan10GB, Non-GPU.

.EXAMPLE
    Get-OllamaRecommendedModels
    # Returns all recommended models

.EXAMPLE
    Get-OllamaRecommendedModels -ModelGroup "LessThan6GB"
    # Returns models suitable for systems with less than 6GB VRAM
#>
function Get-OllamaRecommendedModels {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet("All", "LessThan6GB", "LessThan10GB", "Non-GPU")]
        [string]$ModelGroup = "All"
    )
    
    $recommendedModels = @(
        [PSCustomObject]@{ Name = "llama3.1:8b"; Title = "Llama 3.1 8B"; Description = "Meta's flagship 8B parameter model. Excellent general-purpose performance."; SizeGB = 4.7; Tags = @("tools", "general"); ModelGroup = @("LessThan6GB", "LessThan10GB", "Non-GPU") }
        [PSCustomObject]@{ Name = "llama3.2:3b"; Title = "Llama 3.2 3B"; Description = "Compact but capable model from Meta. Good for resource-constrained systems."; SizeGB = 2.0; Tags = @("tools", "compact"); ModelGroup = @("LessThan6GB", "LessThan10GB", "Non-GPU") }
        [PSCustomObject]@{ Name = "gemma3:4b"; Title = "Gemma 3 4B"; Description = "Google's efficient model optimized for everyday devices."; SizeGB = 3.3; Tags = @("efficient"); ModelGroup = @("LessThan6GB", "LessThan10GB", "Non-GPU") }
        [PSCustomObject]@{ Name = "qwen3:8b"; Title = "Qwen 3 8B"; Description = "Alibaba's latest with strong multilingual and reasoning capabilities."; SizeGB = 4.9; Tags = @("tools", "thinking", "multilingual"); ModelGroup = @("LessThan6GB", "LessThan10GB", "Non-GPU") }
        [PSCustomObject]@{ Name = "deepseek-r1:7b"; Title = "DeepSeek R1 7B"; Description = "Advanced reasoning model with performance approaching larger models."; SizeGB = 4.7; Tags = @("reasoning", "thinking"); ModelGroup = @("LessThan6GB", "LessThan10GB", "Non-GPU") }
        [PSCustomObject]@{ Name = "mistral:7b"; Title = "Mistral 7B"; Description = "Fast and efficient 7B model with good instruction following."; SizeGB = 4.1; Tags = @("fast"); ModelGroup = @("LessThan6GB", "LessThan10GB", "Non-GPU") }
        [PSCustomObject]@{ Name = "codellama:7b"; Title = "Code Llama 7B"; Description = "Specialized for code generation and understanding."; SizeGB = 3.8; Tags = @("code"); ModelGroup = @("LessThan6GB", "LessThan10GB", "Non-GPU") }
        [PSCustomObject]@{ Name = "phi3:mini"; Title = "Phi-3 Mini"; Description = "Microsoft's compact model with surprising capabilities."; SizeGB = 2.3; Tags = @("compact", "efficient"); ModelGroup = @("LessThan6GB", "LessThan10GB", "Non-GPU") }
        [PSCustomObject]@{ Name = "granite4:micro-h"; Title = "Granite 4 Micro-H"; Description = "IBM Granite 4 optimized for CPU/non-GPU workloads."; SizeGB = 2.0; Tags = @("tools", "enterprise"); ModelGroup = @("LessThan6GB", "LessThan10GB", "Non-GPU") }
        [PSCustomObject]@{ Name = "llama3.1:70b"; Title = "Llama 3.1 70B"; Description = "Meta's large 70B model for maximum capability."; SizeGB = 40; Tags = @("tools", "premium"); ModelGroup = @() }
        [PSCustomObject]@{ Name = "gemma3:27b"; Title = "Gemma 3 27B"; Description = "Google's larger Gemma model for demanding tasks."; SizeGB = 17; Tags = @("premium"); ModelGroup = @() }
    )
    
    if ($ModelGroup -ne "All") {
        $recommendedModels = $recommendedModels | Where-Object { $_.ModelGroup -contains $ModelGroup }
    }
    
    return $recommendedModels
}

<#
.SYNOPSIS
    Interactive model browser and installer for Ollama.

.DESCRIPTION
    Displays an interactive list of available Ollama models with search and
    selection capabilities. Allows installing multiple models at once.

.PARAMETER Source
    Source for model list: Library (from ollama.com) or Recommended (curated list).

.PARAMETER Search
    Optional search term to filter models.

.PARAMETER ModelGroup
    Filter recommended models by hardware capability.

.EXAMPLE
    Select-OllamaModelsToInstall
    # Opens interactive model browser

.EXAMPLE
    Select-OllamaModelsToInstall -Source Recommended -ModelGroup "Non-GPU"
    # Shows recommended models for non-GPU systems
#>
function Select-OllamaModelsToInstall {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet("Library", "Recommended")]
        [string]$Source = "Recommended",

        [Parameter()]
        [string]$Search = "",

        [Parameter()]
        [ValidateSet("All", "LessThan6GB", "LessThan10GB", "Non-GPU")]
        [string]$ModelGroup = "All"
    )

    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              OLLAMA MODEL BROWSER                              ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Get models based on source
    Write-Host "Loading models..." -ForegroundColor Yellow
    
    if ($Source -eq "Library") {
        $models = Get-OllamaModelLibrary -IncludeInstalled -Search $Search
    }
    else {
        $models = Get-OllamaRecommendedModels -ModelGroup $ModelGroup
        # Mark installed
        $installedModels = Get-OllamaModels -ErrorAction SilentlyContinue
        foreach ($model in $models) {
            $baseName = $model.Name.Split(':')[0]
            $isInstalled = $installedModels | Where-Object { 
                $_ -eq $model.Name -or $_.Split(':')[0] -eq $baseName 
            }
            $model | Add-Member -NotePropertyName "Installed" -NotePropertyValue ($null -ne $isInstalled) -Force
        }
        
        # Apply search filter
        if ($Search) {
            $models = $models | Where-Object {
                $_.Name -match $Search -or $_.Title -match $Search -or $_.Description -match $Search
            }
        }
    }

    if ($models.Count -eq 0) {
        Write-Host "No models found matching your criteria." -ForegroundColor Red
        return
    }

    # Display models
    Write-Host ""
    Write-Host "Available Models (Source: $Source):" -ForegroundColor Green
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    
    for ($i = 0; $i -lt $models.Count; $i++) {
        $model = $models[$i]
        $num = ($i + 1).ToString().PadLeft(2)
        $installedMarker = if ($model.Installed) { " [INSTALLED]" } else { "" }
        $sizeInfo = if ($model.SizeGB) { " (~$($model.SizeGB) GB)" } else { "" }
        
        Write-Host "  $num. " -ForegroundColor White -NoNewline
        Write-Host "$($model.Name)" -ForegroundColor Cyan -NoNewline
        Write-Host "$sizeInfo" -ForegroundColor DarkGray -NoNewline
        Write-Host "$installedMarker" -ForegroundColor Green
        
        if ($model.Description) {
            Write-Host "      $($model.Description)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Enter model numbers to install (comma-separated, e.g., '1,3,5')" -ForegroundColor Yellow
    Write-Host "Or enter 'q' to quit, 's' to search, 'r' to refresh" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Selection: " -ForegroundColor White -NoNewline
    $selection = Read-Host

    if ($selection -eq 'q') {
        return
    }
    
    if ($selection -eq 's') {
        Write-Host "Enter search term: " -ForegroundColor Yellow -NoNewline
        $searchTerm = Read-Host
        Select-OllamaModelsToInstall -Source $Source -Search $searchTerm -ModelGroup $ModelGroup
        return
    }
    
    if ($selection -eq 'r') {
        Select-OllamaModelsToInstall -Source $Source -Search $Search -ModelGroup $ModelGroup
        return
    }

    # Parse selection
    $selectedNumbers = $selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
    
    if ($selectedNumbers.Count -eq 0) {
        Write-Host "No valid selections. Exiting." -ForegroundColor Red
        return
    }

    $modelsToInstall = @()
    foreach ($num in $selectedNumbers) {
        $index = [int]$num - 1
        if ($index -ge 0 -and $index -lt $models.Count) {
            $modelsToInstall += $models[$index]
        }
    }

    if ($modelsToInstall.Count -eq 0) {
        Write-Host "No valid models selected. Exiting." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Selected models to install:" -ForegroundColor Green
    $modelsToInstall | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Cyan }
    Write-Host ""
    Write-Host "Proceed with installation? (y/n): " -ForegroundColor Yellow -NoNewline
    $confirm = Read-Host

    if ($confirm -ne 'y') {
        Write-Host "Installation cancelled." -ForegroundColor Red
        return
    }

    # Install selected models
    Install-OllamaModelBatch -ModelNames ($modelsToInstall | ForEach-Object { $_.Name })
}

<#
.SYNOPSIS
    Installs one or more Ollama models.

.DESCRIPTION
    Downloads and installs the specified Ollama models using 'ollama pull'.

.PARAMETER ModelNames
    Array of model names to install.

.EXAMPLE
    Install-OllamaModelBatch -ModelNames @("llama3.1:8b", "gemma3:4b")
    # Installs multiple models
#>
function Install-OllamaModelBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ModelNames
    )

    # Ensure Ollama is installed
    $ollamaPath = Get-OllamaPath -InstallIfMissing
    if (-not $ollamaPath) {
        Write-LogMessage "Ollama is not installed and could not be installed automatically." -Level ERROR
        return $false
    }

    Write-Host ""
    Write-Host "Installing $($ModelNames.Count) model(s)..." -ForegroundColor Green
    Write-Host ""

    $results = @()
    
    foreach ($modelName in $ModelNames) {
        Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
        Write-Host "Installing: $modelName" -ForegroundColor Cyan
        Write-Host ""

        try {
            # Use ollama pull to download the model
            $process = Start-Process -FilePath $ollamaPath -ArgumentList "pull $modelName" -Wait -PassThru -NoNewWindow
            
            if ($process.ExitCode -eq 0) {
                Write-Host "✓ Successfully installed: $modelName" -ForegroundColor Green
                $results += [PSCustomObject]@{ Model = $modelName; Success = $true; Error = $null }
            }
            else {
                Write-Host "✗ Failed to install: $modelName (Exit code: $($process.ExitCode))" -ForegroundColor Red
                $results += [PSCustomObject]@{ Model = $modelName; Success = $false; Error = "Exit code: $($process.ExitCode)" }
            }
        }
        catch {
            Write-Host "✗ Error installing: $modelName" -ForegroundColor Red
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
            $results += [PSCustomObject]@{ Model = $modelName; Success = $false; Error = $_.Exception.Message }
        }
        
        Write-Host ""
    }

    # Summary
    Write-Host "─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    $successCount = ($results | Where-Object { $_.Success }).Count
    $failCount = ($results | Where-Object { -not $_.Success }).Count
    
    Write-Host "Installation Summary:" -ForegroundColor Green
    Write-Host "  Successful: $successCount" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "  Failed: $failCount" -ForegroundColor Red
    }
    Write-Host ""

    return $results
}

<#
.SYNOPSIS
    Exports an Ollama model for transfer to airgapped servers.

.DESCRIPTION
    Exports a specified Ollama model by copying model files from Ollama's storage
    directory to a ZIP archive. The archive can be transferred to an airgapped
    server and imported using Import-OllamaModel.

.PARAMETER ModelName
    The name of the model to export (e.g., "llama3.1:8b", "deepseek-r1").

.PARAMETER OutputPath
    Optional path for the output ZIP file. Defaults to OllamaExport folder.

.EXAMPLE
    Export-OllamaModel -ModelName "llama3.1:8b"
    # Exports to default location

.EXAMPLE
    Export-OllamaModel -ModelName "deepseek-r1" -OutputPath "D:\Models\deepseek-r1.zip"
    # Exports to specified path
#>
function Export-OllamaModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelName,
        
        [Parameter()]
        [string]$OutputPath = ""
    )

    # Verify Ollama is installed
    $ollamaPath = Get-OllamaPath
    if (-not $ollamaPath) {
        Write-LogMessage "Ollama is not installed." -Level ERROR
        return $null
    }

    # Get Ollama models directory
    $ollamaModelsDir = $env:OLLAMA_MODELS
    if ([string]::IsNullOrEmpty($ollamaModelsDir)) {
        $ollamaModelsDir = "$env:USERPROFILE\.ollama\models"
    }
    
    if (-not (Test-Path $ollamaModelsDir)) {
        Write-LogMessage "Ollama models directory not found: $ollamaModelsDir" -Level ERROR
        return $null
    }

    Write-LogMessage "Using Ollama models directory: $ollamaModelsDir" -Level INFO
    
    # Generate output path if not provided
    $safeModelName = $ModelName -replace '[:\/]', '-'
    if (-not $OutputPath) {
        $exportFolder = Join-Path $env:USERPROFILE "OllamaExport"
        if (-not (Test-Path $exportFolder)) {
            New-Item -ItemType Directory -Path $exportFolder -Force | Out-Null
        }
        $OutputPath = Join-Path $exportFolder "$safeModelName.zip"
    }
    
    # Create work directory
    $workDir = Join-Path $env:TEMP "OllamaExport_$safeModelName"
    if (Test-Path $workDir) {
        Remove-Item -Path $workDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    Write-LogMessage "Exporting model '$ModelName' to '$OutputPath'" -Level INFO
    
    # Construct manifest path
    if ($ModelName -match '^([^:]+):(.+)$') {
        $modelBaseName = $matches[1]
        $modelTag = $matches[2]
        $manifestPath = Join-Path $ollamaModelsDir "manifests\registry.ollama.ai\library\$modelBaseName\$modelTag"
    }
    else {
        $manifestPath = Join-Path $ollamaModelsDir "manifests\registry.ollama.ai\library\$ModelName\latest"
    }
    
    if (-not (Test-Path $manifestPath)) {
        Write-LogMessage "Model manifest not found at: $manifestPath" -Level ERROR
        Write-LogMessage "Model may not be downloaded. Try running: ollama pull $ModelName" -Level WARN
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
        return $null
    }

    # Read manifest to find blob files
    try {
        $manifestContent = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-LogMessage "Failed to parse manifest file" -Level ERROR -Exception $_
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
        return $null
    }

    # Extract blob hashes
    $blobHashes = @()
    if ($manifestContent.config.digest) {
        $blobHashes += $manifestContent.config.digest -replace '^sha256:', 'sha256-'
    }
    if ($manifestContent.layers) {
        foreach ($layer in $manifestContent.layers) {
            if ($layer.digest) {
                $blobHashes += $layer.digest -replace '^sha256:', 'sha256-'
            }
        }
    }

    Write-LogMessage "Found $($blobHashes.Count) blob file(s) to copy" -Level INFO
    
    # Copy manifest file
    $relativeManifestPath = $manifestPath.Substring($ollamaModelsDir.Length + 1)
    $destManifestPath = Join-Path $workDir $relativeManifestPath
    $destManifestDir = Split-Path -Path $destManifestPath -Parent
    if (-not (Test-Path $destManifestDir)) {
        New-Item -ItemType Directory -Path $destManifestDir -Force | Out-Null
    }
    Copy-Item -Path $manifestPath -Destination $destManifestPath -Force
    Write-LogMessage "Copied manifest: $relativeManifestPath" -Level DEBUG
    
    # Copy blob files
    $blobsDir = Join-Path $ollamaModelsDir "blobs"
    $destBlobsDir = Join-Path $workDir "blobs"
    if (-not (Test-Path $destBlobsDir)) {
        New-Item -ItemType Directory -Path $destBlobsDir -Force | Out-Null
    }
    
    $copiedBlobs = 0
    foreach ($blobHash in $blobHashes) {
        $blobPath = Join-Path $blobsDir $blobHash
        if (Test-Path $blobPath) {
            Copy-Item -Path $blobPath -Destination $destBlobsDir -Force
            $copiedBlobs++
            Write-LogMessage "Copied blob: $blobHash" -Level DEBUG
        }
        else {
            Write-LogMessage "Blob not found: $blobHash" -Level WARN
        }
    }

    Write-LogMessage "Copied $copiedBlobs of $($blobHashes.Count) blob files" -Level INFO

    # Create ZIP archive
    if (Test-Path $OutputPath) {
        Remove-Item -Path $OutputPath -Force
    }
    
    try {
        Compress-Archive -Path "$workDir\*" -DestinationPath $OutputPath -CompressionLevel Optimal
        Write-LogMessage "Created export archive: $OutputPath" -Level INFO
    }
    catch {
        Write-LogMessage "Failed to create ZIP archive" -Level ERROR -Exception $_
        Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
        return $null
    }

    # Cleanup
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue

    return $OutputPath
}

<#
.SYNOPSIS
    Imports an Ollama model from an exported archive.

.DESCRIPTION
    Imports a model from a ZIP archive created by Export-OllamaModel.
    Used on airgapped servers where direct download is not possible.

.PARAMETER ModelPath
    Path to the exported model ZIP file or folder.

.EXAMPLE
    Import-OllamaModel -ModelPath "C:\Models\llama3.1-8b.zip"
    # Imports the model from the ZIP file
#>
function Import-OllamaModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ModelPath
    )
    
    # Verify Ollama is installed
    $ollamaPath = Get-OllamaPath -InstallIfMissing
    if (-not $ollamaPath) {
        Write-LogMessage "Ollama is not installed." -Level ERROR
        return $false
    }
    
    Write-LogMessage "Importing model from '$ModelPath'" -Level INFO
    
    # Get Ollama models directory
    $ollamaModelsDir = $env:OLLAMA_MODELS
    if ([string]::IsNullOrEmpty($ollamaModelsDir) -or -not (Test-Path $ollamaModelsDir)) {
        $ollamaModelsDir = "$env:USERPROFILE\.ollama\models"
    }
    
    if (-not (Test-Path $ollamaModelsDir)) {
        New-Item -ItemType Directory -Path $ollamaModelsDir -Force | Out-Null
        Write-LogMessage "Created Ollama models directory: $ollamaModelsDir" -Level INFO
    }
    
    Write-LogMessage "Using Ollama models directory: $ollamaModelsDir" -Level INFO
    
    $blobsDir = Join-Path $ollamaModelsDir "blobs"
    $manifestsDir = Join-Path $ollamaModelsDir "manifests"
    
    if (-not (Test-Path $blobsDir)) {
        New-Item -ItemType Directory -Path $blobsDir -Force | Out-Null
    }
    if (-not (Test-Path $manifestsDir)) {
        New-Item -ItemType Directory -Path $manifestsDir -Force | Out-Null
    }
    
    # Determine if input is ZIP or folder
    $sourceDir = $ModelPath
    $tempExtractDir = $null
    
    if ($ModelPath -match '\.zip$') {
        $tempExtractDir = Join-Path $env:TEMP "OllamaImport_$(Get-Random)"
        Write-LogMessage "Extracting ZIP to: $tempExtractDir" -Level DEBUG
        Expand-Archive -Path $ModelPath -DestinationPath $tempExtractDir -Force
        $sourceDir = $tempExtractDir
    }
    
    $copiedFiles = 0
    
    # Copy manifests
    $sourceManifestsDir = Join-Path $sourceDir "manifests"
    if (Test-Path $sourceManifestsDir) {
        $manifestFiles = Get-ChildItem -Path $sourceManifestsDir -Recurse -File
        foreach ($file in $manifestFiles) {
            $relativePath = $file.FullName.Substring($sourceManifestsDir.Length + 1)
            $destPath = Join-Path $manifestsDir $relativePath
            $destDir = Split-Path -Path $destPath -Parent
            
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            
            Copy-Item -Path $file.FullName -Destination $destPath -Force
            $copiedFiles++
            Write-LogMessage "Copied manifest: $relativePath" -Level DEBUG
        }
    }
    
    # Copy blobs
    $sourceBlobsDir = Join-Path $sourceDir "blobs"
    if (Test-Path $sourceBlobsDir) {
        $blobFiles = Get-ChildItem -Path $sourceBlobsDir -File
        foreach ($file in $blobFiles) {
            $destPath = Join-Path $blobsDir $file.Name
            Copy-Item -Path $file.FullName -Destination $destPath -Force
            $copiedFiles++
            Write-LogMessage "Copied blob: $($file.Name)" -Level DEBUG
        }
    }
    
    # Cleanup temp directory
    if ($tempExtractDir -and (Test-Path $tempExtractDir)) {
        Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    if ($copiedFiles -gt 0) {
        Write-LogMessage "Successfully imported model ($copiedFiles files copied)" -Level INFO
        Write-LogMessage "Run 'ollama list' to verify model availability" -Level INFO
        return $true
    }
    else {
        Write-LogMessage "No files were copied. The archive may be empty or invalid." -Level WARN
        return $false
    }
}

#endregion

#region Template Management

# Template file paths
$script:LocalTemplatesPath = "$env:OptPath\data\OllamaTemplates\OllamaTemplates.json"

<#
.SYNOPSIS
    Gets the path to the global Ollama templates file.

.DESCRIPTION
    Reads GlobalSettings.json to find the common path and constructs the templates file path.

.OUTPUTS
    String path to the global templates file, or $null if not available.
#>
function Get-OllamaTemplatesJsonFilename {
    [CmdletBinding()]
    param()

    try {
        # Try to find GlobalSettings.json
        $globalSettingsPath = "$env:OptPath\data\GlobalSettings.json"
        
        # Fallback to common network path
        if (-not (Test-Path $globalSettingsPath)) {
            $globalSettingsPath = "C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Configfiles\GlobalSettings.json"
        }
        
        if (Test-Path $globalSettingsPath) {
            $settings = Get-Content $globalSettingsPath -Raw | ConvertFrom-Json
            $commonPath = $settings.Paths.Common
            if ($commonPath) {
                return Join-Path $commonPath "Configfiles\OllamaTemplates.json"
            }
        }
    }
    catch {
        Write-LogMessage "Failed to get global templates path" -Level DEBUG -Exception $_
    }

    return $null
}

<#
.SYNOPSIS
    Gets available Ollama prompt templates.

.DESCRIPTION
    Retrieves prompt templates from local and/or global template files.
    Templates are returned with a Source property indicating their origin.

.PARAMETER Source
    Filter by source: All, Local, or Global. Defaults to All.

.PARAMETER TemplateName
    Optional specific template name to retrieve.

.EXAMPLE
    Get-OllamaTemplates
    # Returns all templates from both local and global sources

.EXAMPLE
    Get-OllamaTemplates -Source Local
    # Returns only local templates

.EXAMPLE
    Get-OllamaTemplates -TemplateName "CreateBankTerminalOrderReport"
    # Returns specific template

.OUTPUTS
    Array of template objects with Name, Description, Prompt, and Source properties.
#>
function Get-OllamaTemplates {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet("All", "Local", "Global")]
        [string]$Source = "All",

        [Parameter()]
        [string]$TemplateName = ""
    )

    $templates = @()

    # Load local templates
    if ($Source -in @("All", "Local")) {
        if (Test-Path $script:LocalTemplatesPath) {
            try {
                $localData = Get-Content $script:LocalTemplatesPath -Raw | ConvertFrom-Json
                if ($localData.Templates) {
                    foreach ($template in $localData.Templates) {
                        $templates += [PSCustomObject]@{
                            Name = $template.Name
                            Description = $template.Description
                            Prompt = $template.Prompt
                            Category = if ($template.Category) { $template.Category } else { "General" }
                            Source = "Local"
                            CreatedAt = $template.CreatedAt
                        }
                    }
                }
            }
            catch {
                Write-LogMessage "Failed to load local templates" -Level WARN -Exception $_
            }
        }
    }

    # Load global templates
    if ($Source -in @("All", "Global")) {
        $globalPath = Get-OllamaTemplatesJsonFilename
        if ($globalPath -and (Test-Path $globalPath)) {
            try {
                $globalData = Get-Content $globalPath -Raw | ConvertFrom-Json
                if ($globalData.Templates) {
                    foreach ($template in $globalData.Templates) {
                        $templates += [PSCustomObject]@{
                            Name = $template.Name
                            Description = $template.Description
                            Prompt = $template.Prompt
                            Category = if ($template.Category) { $template.Category } else { "General" }
                            Source = "Global"
                            CreatedAt = $template.CreatedAt
                        }
                    }
                }
            }
            catch {
                Write-LogMessage "Failed to load global templates" -Level WARN -Exception $_
            }
        }
    }

    # Filter by name if specified
    if ($TemplateName) {
        $templates = $templates | Where-Object { $_.Name -eq $TemplateName }
    }

    return $templates
}

<#
.SYNOPSIS
    Saves a prompt template to the local templates file.

.DESCRIPTION
    Saves a new template or updates an existing one in the local templates file.

.PARAMETER Name
    The unique name for the template.

.PARAMETER Prompt
    The prompt text to save as a template.

.PARAMETER Description
    Optional description of what the template does.

.PARAMETER Category
    Optional category for organizing templates.

.EXAMPLE
    Save-OllamaTemplate -Name "CodeReview" -Prompt "Review this code..." -Description "Code review template"

.OUTPUTS
    Boolean indicating success.
#>
function Save-OllamaTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter()]
        [string]$Description = "",

        [Parameter()]
        [string]$Category = "General"
    )

    # Ensure directory exists
    $templateDir = Split-Path $script:LocalTemplatesPath -Parent
    if (-not (Test-Path $templateDir)) {
        New-Item -ItemType Directory -Path $templateDir -Force | Out-Null
        Write-LogMessage "Created templates directory: $templateDir" -Level INFO
    }

    # Load existing templates or create new structure
    $templateData = @{
        Version = "1.0"
        LastModified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Templates = @()
    }

    if (Test-Path $script:LocalTemplatesPath) {
        try {
            $existingData = Get-Content $script:LocalTemplatesPath -Raw | ConvertFrom-Json
            if ($existingData.Templates) {
                $templateData.Templates = @($existingData.Templates)
            }
        }
        catch {
            Write-LogMessage "Could not read existing templates, creating new file" -Level WARN
        }
    }

    # Check if template already exists
    $existingIndex = -1
    for ($i = 0; $i -lt $templateData.Templates.Count; $i++) {
        if ($templateData.Templates[$i].Name -eq $Name) {
            $existingIndex = $i
            break
        }
    }

    $newTemplate = @{
        Name = $Name
        Description = $Description
        Prompt = $Prompt
        Category = $Category
        CreatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    if ($existingIndex -ge 0) {
        # Update existing
        $templateData.Templates[$existingIndex] = $newTemplate
        Write-LogMessage "Updated template: $Name" -Level INFO
    }
    else {
        # Add new
        $templateData.Templates += $newTemplate
        Write-LogMessage "Created template: $Name" -Level INFO
    }

    # Save to file
    try {
        $templateData | ConvertTo-Json -Depth 10 | Set-Content $script:LocalTemplatesPath -Encoding UTF8
        Write-LogMessage "Saved templates to: $($script:LocalTemplatesPath)" -Level INFO
        return $true
    }
    catch {
        Write-LogMessage "Failed to save templates" -Level ERROR -Exception $_
        return $false
    }
}

<#
.SYNOPSIS
    Removes a template from the local templates file.

.PARAMETER Name
    The name of the template to remove.

.EXAMPLE
    Remove-OllamaTemplate -Name "MyTemplate"
#>
function Remove-OllamaTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Test-Path $script:LocalTemplatesPath)) {
        Write-LogMessage "No local templates file found" -Level WARN
        return $false
    }

    try {
        $templateData = Get-Content $script:LocalTemplatesPath -Raw | ConvertFrom-Json
        $originalCount = $templateData.Templates.Count
        $templateData.Templates = @($templateData.Templates | Where-Object { $_.Name -ne $Name })
        
        if ($templateData.Templates.Count -eq $originalCount) {
            Write-LogMessage "Template not found: $Name" -Level WARN
            return $false
        }

        $templateData.LastModified = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $templateData | ConvertTo-Json -Depth 10 | Set-Content $script:LocalTemplatesPath -Encoding UTF8
        Write-LogMessage "Removed template: $Name" -Level INFO
        return $true
    }
    catch {
        Write-LogMessage "Failed to remove template" -Level ERROR -Exception $_
        return $false
    }
}

#endregion

#region Firewall Configuration

<#
.SYNOPSIS
    Configures Windows Firewall rules for Ollama.

.DESCRIPTION
    Creates Windows Firewall rules to allow Ollama to function properly:
    - Inbound rule for Ollama API (current configured port)
    - Outbound rules for Ollama process (model downloads)
    - Outbound rules for Edge browser to access ollama.com/org (HTTP/HTTPS)
    
    Requires administrative privileges to modify firewall rules.

.PARAMETER RemoveExisting
    If specified, removes existing Ollama firewall rules before creating new ones.

.PARAMETER WhatIf
    Shows what rules would be created without actually creating them.

.PARAMETER SkipBrowserRules
    If specified, skips creating rules for Edge browser access to Ollama websites.
    By default, browser rules are created.

.EXAMPLE
    Set-OllamaFirewallRules
    # Creates all necessary firewall rules for current Ollama configuration

.EXAMPLE
    Set-OllamaFirewallRules -RemoveExisting
    # Removes old rules and creates fresh ones

.EXAMPLE
    Set-OllamaFirewallRules -WhatIf
    # Shows what rules would be created without creating them

.OUTPUTS
    PSCustomObject with RulesCreated, RulesRemoved, and Errors properties.

.NOTES
    Requires running PowerShell as Administrator.

.AUTHOR
    Geir Helge Starholm, www.dEdge.no
#>
function Set-OllamaFirewallRules {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [switch]$RemoveExisting,

        [Parameter()]
        [switch]$SkipBrowserRules
    )

    # Check for admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage "This function requires administrative privileges. Please run PowerShell as Administrator." -Level ERROR
        return [PSCustomObject]@{
            Success = $false
            RulesCreated = @()
            RulesRemoved = @()
            Errors = @("Insufficient privileges - requires Administrator")
        }
    }

    $results = [PSCustomObject]@{
        Success = $true
        RulesCreated = @()
        RulesRemoved = @()
        Errors = @()
    }

    # Get current Ollama configuration
    $config = Get-OllamaConfiguration
    $ollamaPort = $config.Port
    $ollamaPath = Get-OllamaPath

    Write-LogMessage "Configuring firewall for Ollama (Port: $ollamaPort)" -Level INFO

    # Define rule prefix for easy identification
    $rulePrefix = "Ollama"

    # Remove existing rules if requested
    if ($RemoveExisting) {
        Write-LogMessage "Removing existing Ollama firewall rules..." -Level INFO
        try {
            $existingRules = Get-NetFirewallRule -DisplayName "$rulePrefix*" -ErrorAction SilentlyContinue
            foreach ($rule in $existingRules) {
                if ($PSCmdlet.ShouldProcess($rule.DisplayName, "Remove firewall rule")) {
                    Remove-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue
                    $results.RulesRemoved += $rule.DisplayName
                    Write-LogMessage "Removed rule: $($rule.DisplayName)" -Level DEBUG
                }
            }
        }
        catch {
            Write-LogMessage "Error removing existing rules" -Level WARN -Exception $_
        }
    }

    # Define rules to create
    $rulesToCreate = @()

    # 1. Inbound - Ollama API access (current configured port)
    $rulesToCreate += @{
        DisplayName = "$rulePrefix - API Inbound (TCP $ollamaPort)"
        Direction = "Inbound"
        Action = "Allow"
        Protocol = "TCP"
        LocalPort = $ollamaPort
        Description = "Allow inbound connections to Ollama API on port $ollamaPort"
        Program = $null
    }

    # 2. Inbound - Ollama default port 11434 (if different from current)
    if ($ollamaPort -ne 11434) {
        $rulesToCreate += @{
            DisplayName = "$rulePrefix - API Inbound (TCP 11434 - Default)"
            Direction = "Inbound"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = 11434
            Description = "Allow inbound connections to Ollama API on default port 11434"
            Program = $null
        }
    }

    # 3. Outbound - Ollama process for model downloads (HTTPS)
    if ($ollamaPath -and (Test-Path $ollamaPath)) {
        $rulesToCreate += @{
            DisplayName = "$rulePrefix - Process Outbound (HTTPS)"
            Direction = "Outbound"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = $null
            RemotePort = 443
            Description = "Allow Ollama to download models via HTTPS"
            Program = $ollamaPath
        }

        # 4. Outbound - Ollama process for HTTP (port 80)
        $rulesToCreate += @{
            DisplayName = "$rulePrefix - Process Outbound (HTTP)"
            Direction = "Outbound"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = $null
            RemotePort = 80
            Description = "Allow Ollama to access HTTP resources"
            Program = $ollamaPath
        }
    }

    # 5. Browser rules for Edge to access Ollama websites
    if (-not $SkipBrowserRules) {
        # Find Edge executable
        $edgePaths = @(
            "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
            "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
            "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
        )
        
        $edgePath = $null
        foreach ($path in $edgePaths) {
            if (Test-Path $path) {
                $edgePath = $path
                break
            }
        }

        if ($edgePath) {
            # Edge HTTPS outbound (port 443)
            $rulesToCreate += @{
                DisplayName = "$rulePrefix - Edge HTTPS Outbound (443)"
                Direction = "Outbound"
                Action = "Allow"
                Protocol = "TCP"
                LocalPort = $null
                RemotePort = 443
                Description = "Allow Edge to access Ollama websites via HTTPS"
                Program = $edgePath
            }

            # Edge HTTP outbound (port 80)
            $rulesToCreate += @{
                DisplayName = "$rulePrefix - Edge HTTP Outbound (80)"
                Direction = "Outbound"
                Action = "Allow"
                Protocol = "TCP"
                LocalPort = $null
                RemotePort = 80
                Description = "Allow Edge to access Ollama websites via HTTP"
                Program = $edgePath
            }

            # Edge alternate HTTP outbound (port 8080)
            $rulesToCreate += @{
                DisplayName = "$rulePrefix - Edge Alt HTTP Outbound (8080)"
                Direction = "Outbound"
                Action = "Allow"
                Protocol = "TCP"
                LocalPort = $null
                RemotePort = 8080
                Description = "Allow Edge to access Ollama websites via alternate HTTP port"
                Program = $edgePath
            }
        }
        else {
            Write-LogMessage "Microsoft Edge not found - skipping browser rules" -Level WARN
        }
    }

    # Create the rules
    foreach ($rule in $rulesToCreate) {
        try {
            # Check if rule already exists
            $existingRule = Get-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue
            
            if ($existingRule) {
                Write-LogMessage "Rule already exists: $($rule.DisplayName)" -Level DEBUG
                continue
            }

            if ($PSCmdlet.ShouldProcess($rule.DisplayName, "Create firewall rule")) {
                $params = @{
                    DisplayName = $rule.DisplayName
                    Direction = $rule.Direction
                    Action = $rule.Action
                    Protocol = $rule.Protocol
                    Description = $rule.Description
                    Enabled = "True"
                    ErrorAction = "Stop"
                }

                if ($rule.LocalPort) {
                    $params.LocalPort = $rule.LocalPort
                }
                if ($rule.RemotePort) {
                    $params.RemotePort = $rule.RemotePort
                }
                if ($rule.Program) {
                    $params.Program = $rule.Program
                }

                New-NetFirewallRule @params | Out-Null
                $results.RulesCreated += $rule.DisplayName
                Write-LogMessage "Created rule: $($rule.DisplayName)" -Level INFO
            }
        }
        catch {
            $errorMsg = "Failed to create rule '$($rule.DisplayName)': $($_.Exception.Message)"
            $results.Errors += $errorMsg
            Write-LogMessage $errorMsg -Level ERROR
            $results.Success = $false
        }
    }

    # Summary
    Write-LogMessage "Firewall configuration complete. Created: $($results.RulesCreated.Count), Removed: $($results.RulesRemoved.Count), Errors: $($results.Errors.Count)" -Level INFO

    return $results
}

<#
.SYNOPSIS
    Gets current Ollama-related firewall rules.

.DESCRIPTION
    Lists all Windows Firewall rules related to Ollama.

.EXAMPLE
    Get-OllamaFirewallRules
    # Lists all Ollama firewall rules

.OUTPUTS
    Array of firewall rule objects.
#>
function Get-OllamaFirewallRules {
    [CmdletBinding()]
    param()

    try {
        $rules = Get-NetFirewallRule -DisplayName "Ollama*" -ErrorAction SilentlyContinue
        
        if (-not $rules) {
            Write-LogMessage "No Ollama firewall rules found" -Level INFO
            return @()
        }

        return $rules | ForEach-Object {
            $portFilter = $_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            $appFilter = $_ | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
            
            [PSCustomObject]@{
                DisplayName = $_.DisplayName
                Direction = $_.Direction
                Action = $_.Action
                Enabled = $_.Enabled
                Protocol = $portFilter.Protocol
                LocalPort = $portFilter.LocalPort
                RemotePort = $portFilter.RemotePort
                Program = $appFilter.Program
                Description = $_.Description
            }
        }
    }
    catch {
        Write-LogMessage "Failed to get firewall rules" -Level ERROR -Exception $_
        return @()
    }
}

<#
.SYNOPSIS
    Removes all Ollama-related firewall rules.

.DESCRIPTION
    Removes all Windows Firewall rules that were created for Ollama.
    Requires administrative privileges.

.EXAMPLE
    Remove-OllamaFirewallRules
    # Removes all Ollama firewall rules

.OUTPUTS
    Number of rules removed.
#>
function Remove-OllamaFirewallRules {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    # Check for admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-LogMessage "This function requires administrative privileges." -Level ERROR
        return 0
    }

    $removedCount = 0

    try {
        $rules = Get-NetFirewallRule -DisplayName "Ollama*" -ErrorAction SilentlyContinue
        
        foreach ($rule in $rules) {
            if ($PSCmdlet.ShouldProcess($rule.DisplayName, "Remove firewall rule")) {
                Remove-NetFirewallRule -Name $rule.Name -ErrorAction Stop
                $removedCount++
                Write-LogMessage "Removed rule: $($rule.DisplayName)" -Level INFO
            }
        }
    }
    catch {
        Write-LogMessage "Failed to remove firewall rules" -Level ERROR -Exception $_
    }

    Write-LogMessage "Removed $removedCount Ollama firewall rule(s)" -Level INFO
    return $removedCount
}

#endregion

#region Module Exports

Export-ModuleMember -Function @(
    # Service functions
    'Test-OllamaService',
    'Start-OllamaService',
    
    # Installation
    'Get-OllamaPath',
    'Install-Ollama',
    
    # Model management
    'Get-OllamaModels',
    'Set-OllamaPort',
    'Set-OllamaModelsPath',
    'Get-OllamaConfiguration',
    
    # Model library and installation
    'Get-OllamaModelLibrary',
    'Get-OllamaRecommendedModels',
    'Select-OllamaModelsToInstall',
    'Install-OllamaModelBatch',
    
    # Export/Import
    'Export-OllamaModel',
    'Import-OllamaModel',
    
    # Template management
    'Get-OllamaTemplatesJsonFilename',
    'Get-OllamaTemplates',
    'Save-OllamaTemplate',
    'Remove-OllamaTemplate',
    
    # Firewall configuration
    'Set-OllamaFirewallRules',
    'Get-OllamaFirewallRules',
    'Remove-OllamaFirewallRules',
    
    # Role and audience
    'Get-OllamaRoles',
    'Get-OllamaAudienceLevels',
    
    # Core functions
    'Invoke-OllamaGenerate',
    'Invoke-Ollama',
    
    # Interactive
    'Start-OllamaChat'
)

#endregion

