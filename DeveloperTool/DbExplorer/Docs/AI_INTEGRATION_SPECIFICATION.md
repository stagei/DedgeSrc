# AI Integration Specification - DbExplorer

**Date**: December 14, 2025  
**Version**: 2.0 (Updated with multi-provider + context-specific requirements)  
**Status**: 📋 **SPECIFICATION** - Ready for Implementation  
**Priority**: HIGH (User-requested feature)

---

## 🎯 Core Requirements

### 1. Multi-Provider Support (MANDATORY)

**Must support ALL major AI providers:**

#### Cloud Providers
- ✅ **OpenAI** - GPT-4o, GPT-4o-mini, GPT-3.5-turbo
- ✅ **Azure OpenAI** - GPT-4o via Azure endpoints
- ✅ **Anthropic Claude** - Claude 3.5 Sonnet, Claude 3 Opus
- ✅ **Google Gemini** - Gemini 1.5 Pro, Gemini 1.5 Flash

#### Local AI Providers (CRITICAL for Privacy)
- ✅ **Ollama** - localhost:11434 (Primary recommendation)
- ✅ **LM Studio** - localhost:1234 (OpenAI-compatible API)
- ✅ **Any OpenAI-compatible endpoint** - Jan.ai, LocalAI, etc.

**Default**: Ollama (free, private, no setup)

---

## 🏗️ Architecture

### Provider Abstraction Layer

```csharp
public interface IAiProvider
{
    string ProviderName { get; }
    string DisplayName { get; }
    bool RequiresApiKey { get; }
    bool IsLocal { get; }
    bool IsAvailable { get; }
    
    Task<bool> TestConnectionAsync();
    Task<string> GenerateAsync(string prompt, AiGenerationOptions options);
    Task<List<string>> GetAvailableModelsAsync();
}

public class AiGenerationOptions
{
    public string? Model { get; set; }
    public double Temperature { get; set; } = 0.7;
    public int MaxTokens { get; set; } = 1000;
    public bool Stream { get; set; } = false;
}
```

### Provider Implementations

#### 1. OllamaProvider (Primary - Local AI)
```csharp
public class OllamaProvider : IAiProvider
{
    private readonly string _baseUrl = "http://localhost:11434";
    
    public string ProviderName => "Ollama";
    public bool RequiresApiKey => false;
    public bool IsLocal => true;
    
    public async Task<bool> TestConnectionAsync()
    {
        // GET http://localhost:11434/api/tags
        // Returns list of installed models
    }
    
    public async Task<string> GenerateAsync(string prompt, AiGenerationOptions options)
    {
        // POST http://localhost:11434/api/generate
        // Body: { "model": "llama3.2", "prompt": "...", "stream": false }
    }
    
    public async Task<List<string>> GetAvailableModelsAsync()
    {
        // Returns: ["llama3.2", "mistral", "codellama", "deepseek-coder", ...]
    }
}
```

**Supported Models (Ollama):**
- `llama3.2:3b` - Fast, general purpose (1.7GB)
- `codellama:7b` - Code-focused (3.8GB)
- `deepseek-coder:6.7b` - Best for SQL (3.8GB)
- `mistral:7b` - Good balance (4.1GB)

#### 2. LmStudioProvider (Alternative Local AI)
```csharp
public class LmStudioProvider : IAiProvider
{
    private readonly string _baseUrl = "http://localhost:1234/v1";
    
    public string ProviderName => "LM Studio";
    public bool RequiresApiKey => false;
    public bool IsLocal => true;
    
    public async Task<string> GenerateAsync(string prompt, AiGenerationOptions options)
    {
        // OpenAI-compatible API
        // POST http://localhost:1234/v1/chat/completions
        // Same format as OpenAI
    }
}
```

#### 3. OpenAiProvider (Cloud)
```csharp
public class OpenAiProvider : IAiProvider
{
    private readonly string _apiKey;
    private readonly HttpClient _httpClient;
    
    public string ProviderName => "OpenAI";
    public bool RequiresApiKey => true;
    public bool IsLocal => false;
    
    public async Task<string> GenerateAsync(string prompt, AiGenerationOptions options)
    {
        // POST https://api.openai.com/v1/chat/completions
        // Headers: Authorization: Bearer {apiKey}
    }
}
```

#### 4. ClaudeProvider (Cloud)
```csharp
public class ClaudeProvider : IAiProvider
{
    public string ProviderName => "Anthropic Claude";
    public bool RequiresApiKey => true;
    public bool IsLocal => false;
    
    public async Task<string> GenerateAsync(string prompt, AiGenerationOptions options)
    {
        // POST https://api.anthropic.com/v1/messages
        // Headers: x-api-key: {apiKey}
    }
}
```

#### 5. GeminiProvider (Cloud)
```csharp
public class GeminiProvider : IAiProvider
{
    public string ProviderName => "Google Gemini";
    public bool RequiresApiKey => true;
    public bool IsLocal => false;
    
    public async Task<string> GenerateAsync(string prompt, AiGenerationOptions options)
    {
        // POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
    }
}
```

### Provider Manager
```csharp
public class AiProviderManager
{
    private readonly Dictionary<string, IAiProvider> _providers = new();
    private IAiProvider? _activeProvider;
    
    public void RegisterProviders()
    {
        _providers["ollama"] = new OllamaProvider();
        _providers["lmstudio"] = new LmStudioProvider();
        _providers["openai"] = new OpenAiProvider();
        _providers["claude"] = new ClaudeProvider();
        _providers["gemini"] = new GeminiProvider();
    }
    
    public async Task<IAiProvider?> DetectBestProviderAsync()
    {
        // 1. Try Ollama (localhost:11434)
        if (await _providers["ollama"].TestConnectionAsync())
            return _providers["ollama"];
        
        // 2. Try LM Studio (localhost:1234)
        if (await _providers["lmstudio"].TestConnectionAsync())
            return _providers["lmstudio"];
        
        // 3. Check for API keys in settings
        // 4. Return null if nothing available
        return null;
    }
}
```

---

## 📍 Context-Specific AI Features

### 1. Mermaid Editor - Relationship Explanation

**Location**: `MermaidDesignerWindow.xaml`

**New Button**: "🤖 Explain Relationships"

**Implementation**:
```csharp
private async void ExplainRelationships_Click(object sender, RoutedEventArgs e)
{
    // 1. Get current Mermaid diagram from WebView2
    var mermaidCode = await GetCurrentMermaidCodeAsync();
    
    // 2. Parse to extract tables and relationships
    var tables = ParseMermaidTables(mermaidCode);
    var relationships = ParseMermaidRelationships(mermaidCode);
    
    // 3. Fetch table metadata from DB2
    var tableMetadata = await FetchTableMetadataAsync(tables);
    
    // 4. Build context for AI
    var context = BuildRelationshipContext(tables, relationships, tableMetadata);
    
    // 5. Generate AI prompt
    var prompt = $@"
You are a database expert analyzing an Entity-Relationship Diagram (ERD).

Tables in the diagram:
{context.TablesInfo}

Relationships:
{context.RelationshipsInfo}

Foreign Keys:
{context.ForeignKeysInfo}

Please explain:
1. Why these tables are related (business logic)
2. What each foreign key represents
3. Common query patterns between these tables
4. Data flow direction (which direction data typically flows)
5. Business context (what real-world entities do these represent)

Be specific and practical. Use examples relevant to the domain.
";
    
    // 6. Call AI
    var explanation = await _aiService.GenerateAsync(prompt);
    
    // 7. Show in dialog
    var dialog = new AiExplanationDialog("Relationship Explanation", explanation);
    dialog.ShowDialog();
}
```

**Example Output**:
```
Relationship Analysis: INL Schema

BILAGNR (Invoice Numbers) → FASTE_TRANS (Fixed Transactions)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Business Logic:
BILAGNR is the master invoice table storing invoice numbers and dates.
FASTE_TRANS stores individual transaction lines that belong to invoices.

Why Related:
Each transaction must be associated with a specific invoice. This is a 
classic parent-child relationship where one invoice can have multiple 
transaction lines.

Foreign Key: FASTE_TRANS.BILAGNR → BILAGNR.BILAGNR
Type: One-to-Many (1:N)

Common Query Patterns:
1. Get invoice with all transactions:
   SELECT b.*, t.* 
   FROM INL.BILAGNR b 
   LEFT JOIN INL.FASTE_TRANS t ON b.BILAGNR = t.BILAGNR
   WHERE b.BILAGNR = ?

2. Get transaction totals by invoice:
   SELECT b.BILAGNR, COUNT(t.TRANS_ID) AS TransCount
   FROM INL.BILAGNR b
   LEFT JOIN INL.FASTE_TRANS t ON b.BILAGNR = t.BILAGNR
   GROUP BY b.BILAGNR

Data Flow:
Invoice created first → Transactions added → Transactions reference invoice
```

---

### 2. Table Property Window - AI Assistant Tab

**Location**: `TableDetailsDialog.xaml`

**New Tab**: "🤖 AI Assistant"

**Note**: Uses standard schema-only context by default. For deeper analysis with data samples, use "🔬 Deep Analysis" from context menu.

**UI Layout**:
```xml
<TabItem Header="🤖 AI Assistant">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Quick Actions -->
        <WrapPanel Grid.Row="0" Margin="0,0,0,10">
            <Button Content="💡 Explain Table" Click="AiExplainTable_Click"/>
            <Button Content="📊 Common Queries" Click="AiCommonQueries_Click"/>
            <Button Content="⚡ Optimization Tips" Click="AiOptimize_Click"/>
            <Button Content="📚 Generate Docs" Click="AiGenerateDocs_Click"/>
        </WrapPanel>
        
        <!-- AI Response Area -->
        <Border Grid.Row="1" BorderThickness="1" BorderBrush="Gray" Padding="10"
                Background="{DynamicResource SystemControlBackgroundAltHighBrush}">
            <ScrollViewer>
                <TextBlock x:Name="AiResponseText" TextWrapping="Wrap"
                           Text="Click a button above to get AI assistance..."/>
            </ScrollViewer>
        </Border>
        
        <!-- Custom Question -->
        <Grid Grid.Row="2" Margin="0,10,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            
            <TextBox x:Name="CustomQuestionBox" 
                     PlaceholderText="Ask AI anything about this table..."/>
            <Button Grid.Column="1" Content="Ask" Width="80" Margin="5,0,0,0"
                    Click="AskCustomQuestion_Click"/>
        </Grid>
    </Grid>
</TabItem>
```

**Implementation**:
```csharp
private async void AiExplainTable_Click(object sender, RoutedEventArgs e)
{
    AiResponseText.Text = "⏳ Analyzing table...";
    
    var context = BuildTableContext();
    var prompt = $@"
Explain this database table:

Table: {_table.Schema}.{_table.Name}
Columns: {context.ColumnsInfo}
Primary Key: {context.PrimaryKey}
Foreign Keys: {context.ForeignKeys}
Indexes: {context.Indexes}
Row Count: {context.RowCount:N0}

Explain:
1. What this table stores (business purpose)
2. What each column represents
3. How it relates to other tables
4. When to use this table
5. Common use cases
";
    
    var response = await _aiService.GenerateAsync(prompt);
    AiResponseText.Text = response;
}

private async void AiCommonQueries_Click(object sender, RoutedEventArgs e)
{
    AiResponseText.Text = "⏳ Generating query examples...";
    
    var context = BuildTableContext();
    var prompt = $@"
Generate common SQL query patterns for this table:

Table: {_table.Schema}.{_table.Name}
Columns: {context.ColumnsInfo}
Primary Key: {context.PrimaryKey}
Foreign Keys: {context.ForeignKeys}

Generate 5-7 typical queries with explanations:
1. Simple SELECT
2. Filtered query (with WHERE)
3. JOIN with related tables
4. Aggregation (COUNT, SUM, etc.)
5. INSERT example
6. UPDATE example
7. DELETE example (with safety)

Use DB2 syntax. Include comments.
";
    
    var response = await _aiService.GenerateAsync(prompt);
    AiResponseText.Text = response;
}
```

---

### 3. View Property Window - AI Assistant Tab

**Similar to Table Property Window, but context includes:**
- View SQL definition (CREATE VIEW statement)
- Underlying tables referenced
- Columns returned
- Complexity metrics

**Prompts**:
```
- "Explain this view" → What data it provides, business purpose
- "Show underlying logic" → Explain the SELECT statement step-by-step
- "Suggest improvements" → Performance optimization tips
- "Find dependencies" → What queries/procedures use this view
```

---

### 4. Procedure Property Window - AI Assistant Tab

**Context includes:**
- Full procedure source code
- Parameters (IN/OUT/INOUT)
- Tables accessed
- Logic flow

**Prompts**:
```
- "Explain this procedure" → What it does, when to use
- "Explain parameters" → What each parameter means
- "Show example usage" → Generate CALL statements
- "Document logic" → Step-by-step breakdown
```

---

### 5. Function Property Window - AI Assistant Tab

**Context includes:**
- Full function source code
- Parameters and return type
- Used in queries/views

**Prompts**:
```
- "Explain this function" → What it calculates
- "Show usage examples" → How to call in SELECT
- "Explain logic" → Algorithm breakdown
- "Suggest alternatives" → Better implementations
```

---

### 6. Package Property Window - AI Assistant Tab

**Context includes:**
- Package metadata
- All SQL statements (from SYSCAT.STATEMENTS)
- Dependencies (from Dependencies tab)

**Prompts**:
```
- "Explain this package" → Application purpose
- "Summarize SQL statements" → What queries do
- "Analyze dependencies" → Why it uses certain tables
- "Document package" → Complete documentation
```

---

## ⚙️ Settings Dialog - AI Configuration

**Location**: Settings → AI Tab

```xml
<TabItem Header="🤖 AI Configuration">
    <StackPanel Margin="20">
        <TextBlock Text="AI Provider" FontSize="16" FontWeight="Bold"/>
        
        <!-- Provider Selection -->
        <ComboBox x:Name="ProviderCombo" Margin="0,10,0,0">
            <ComboBoxItem Content="🏠 Ollama (Local - Recommended)" Tag="ollama"/>
            <ComboBoxItem Content="🖥️ LM Studio (Local)" Tag="lmstudio"/>
            <ComboBoxItem Content="☁️ OpenAI (GPT-4o)" Tag="openai"/>
            <ComboBoxItem Content="☁️ Anthropic Claude" Tag="claude"/>
            <ComboBoxItem Content="☁️ Google Gemini" Tag="gemini"/>
        </ComboBox>
        
        <!-- Provider Status -->
        <Border Margin="0,10,0,0" Padding="10" Background="LightGreen">
            <TextBlock x:Name="ProviderStatus" Text="✅ Ollama detected - 3 models available"/>
        </Border>
        
        <!-- Model Selection (for Ollama/LM Studio) -->
        <TextBlock Text="Model" FontWeight="SemiBold" Margin="0,15,0,5"/>
        <ComboBox x:Name="ModelCombo">
            <!-- Populated based on selected provider -->
        </ComboBox>
        
        <!-- API Key (for cloud providers) -->
        <TextBlock Text="API Key" FontWeight="SemiBold" Margin="0,15,0,5"/>
        <PasswordBox x:Name="ApiKeyBox"/>
        <TextBlock Text="Only required for cloud providers (OpenAI, Claude, Gemini)"
                   FontSize="10" Foreground="Gray"/>
        
        <!-- Advanced Settings -->
        <Expander Header="Advanced Settings" Margin="0,15,0,0">
            <StackPanel>
                <TextBlock Text="Temperature (0-1)"/>
                <Slider x:Name="TemperatureSlider" Minimum="0" Maximum="1" Value="0.7"/>
                
                <TextBlock Text="Max Tokens" Margin="0,10,0,0"/>
                <TextBox x:Name="MaxTokensBox" Text="1000"/>
                
                <CheckBox Content="Enable streaming responses" Margin="0,10,0,0"/>
            </StackPanel>
        </Expander>
        
        <!-- Privacy Settings -->
        <Expander Header="Privacy Settings" Margin="0,10,0,0">
            <StackPanel>
                <CheckBox Content="Send table names to AI" IsChecked="True"/>
                <CheckBox Content="Send column names to AI" IsChecked="True"/>
                <CheckBox Content="Send SQL queries to AI" IsChecked="True"/>
                <CheckBox Content="Send row counts to AI" IsChecked="False"/>
                <TextBlock Text="⚠️ Cloud providers: Data sent to external servers"
                           Foreground="Orange" Margin="0,10,0,0"/>
                <TextBlock Text="✅ Local providers (Ollama/LM Studio): Data never leaves your PC"
                           Foreground="Green"/>
            </StackPanel>
        </Expander>
        
        <!-- Test Connection -->
        <Button Content="Test Connection" Margin="0,15,0,0" Click="TestAi_Click"/>
    </StackPanel>
</TabItem>
```

---

## 🔧 Implementation Steps

### Phase 1: Core Infrastructure (6-8 hours)
1. Create `IAiProvider` interface
2. Implement `OllamaProvider` (primary)
3. Implement `LmStudioProvider`
4. Implement `OpenAiProvider`
5. Implement `AiProviderManager`
6. Create Settings UI for AI configuration
7. Test provider switching

### Phase 1.5: Deep Analysis Engine (6-8 hours) ⭐ NEW
1. Create `DeepAnalysisContext` model
2. Implement `DeepAnalysisService`:
   - Extract table/column comments from SYSCAT
   - Sample data extraction (configurable row count)
   - Column profiling (distinct, nulls, min/max, top values)
   - Sensitive data detection and masking
3. Create `DeepAnalysisDialog` UI
4. Add context menu items: "Deep Analysis", "Group Analysis"
5. Implement caching (don't re-profile on every question)
6. Performance optimization for large tables

### Phase 2: Context Builders (4-6 hours - Updated)
1. Create `IAiProvider` interface
2. Implement `OllamaProvider` (primary)
3. Implement `LmStudioProvider`
4. Implement `OpenAiProvider`
5. Implement `AiProviderManager`
6. Create Settings UI for AI configuration
7. Test provider switching

### Phase 2: Context Builders (4-6 hours)
1. `TableContextBuilder` - Gather table metadata
2. `ViewContextBuilder` - Gather view metadata
3. `ProcedureContextBuilder` - Gather procedure metadata
4. `PackageContextBuilder` - Gather package metadata
5. `MermaidContextBuilder` - Parse Mermaid diagrams

### Phase 3: UI Integration (8-10 hours)
1. Add AI Assistant tab to `TableDetailsDialog`
2. Add AI Assistant tab to `ViewDetailsDialog` (create if needed)
3. Add AI Assistant tab to `ProcedureDetailsDialog` (create if needed)
4. Add AI Assistant tab to `FunctionDetailsDialog` (create if needed)
5. Add AI Assistant tab to `PackageDetailsDialog`
6. Add "Explain Relationships" to `MermaidDesignerWindow`

### Phase 4: Additional Providers (2-4 hours each)
1. Implement `ClaudeProvider`
2. Implement `GeminiProvider`
3. Implement `AzureOpenAiProvider`

**Phase 5: Export & Preferences (NEW)** (10-15 hours)
1. Create AiExportService (markdown export)
2. Implement ExternalEditorService (Cursor/VS Code integration)
3. Create FontSizeManager (dynamic font preferences)
4. Add export buttons to all AI dialogs
5. Enhance Mermaid export with .mmd embedding
6. Add Settings UI for editor and font preferences

**Total Estimated**: 42-61 hours (including Deep Analysis, Export, Preferences)

---

## 📦 Dependencies

```xml
<!-- AI Provider HTTP clients -->
<PackageReference Include="System.Net.Http.Json" Version="10.0.0" />

<!-- Optional: Official SDKs -->
<PackageReference Include="Azure.AI.OpenAI" Version="2.1.0" />
<PackageReference Include="Anthropic.SDK" Version="0.1.0" />

<!-- JSON handling -->
<PackageReference Include="System.Text.Json" Version="10.0.0" />
```

**No model files needed!** All AI providers (Ollama, LM Studio, cloud APIs) manage models externally.

---

## 🎯 Success Criteria

### Provider Support
- ✅ All 5+ providers working
- ✅ Auto-detection of Ollama/LM Studio
- ✅ Easy provider switching in settings
- ✅ Fallback if primary unavailable

### Context-Specific AI
- ✅ Mermaid relationship explanation working
- ✅ Table AI assistant tab functional
- ✅ View AI assistant tab functional
- ✅ Procedure AI assistant tab functional
- ✅ Function AI assistant tab functional
- ✅ Package AI assistant tab functional

### User Experience
- ✅ Fast responses (<5 seconds)
- ✅ Clear, actionable explanations
- ✅ Copy/paste AI responses
- ✅ Save AI responses to file

### Privacy & Security
- ✅ Local AI (Ollama) works offline
- ✅ User controls what data is sent
- ✅ Clear privacy warnings for cloud providers
- ✅ API keys encrypted in settings

---

## 🚀 Recommended Approach

**Start with Ollama** (easiest, most private):
1. User installs Ollama: `https://ollama.com/download`
2. User runs: `ollama pull llama3.2`
3. App auto-detects Ollama at localhost:11434
4. Works immediately, no API keys needed

**Benefits of Ollama-first approach**:
- ✅ Free
- ✅ Private (data never leaves PC)
- ✅ Fast (local inference)
- ✅ No setup in app (just detect)
- ✅ Multiple models available (llama3.2, codellama, mistral)

---

**Status**: Complete specification with Deep Analysis feature  
**Priority**: HIGH (user-requested feature with clear requirements)  
**Complexity**: Medium-High (26-38 hours estimated)

---

## 🎯 Key Features Summary

### Multi-Provider AI ✅
- Ollama (local, free, private)
- LM Studio (local alternative)
- OpenAI, Claude, Gemini (cloud)

### Context-Specific AI ✅
- Mermaid relationship explanation
- Table/View/Procedure/Function/Package AI assistants

### Deep Analysis ✅ (NEW)
- **Data sampling** - Analyze actual data patterns
- **Column comments** - Extract REMARKS from SYSCAT.COLUMNS
- **Table comments** - Extract REMARKS from SYSCAT.TABLES
- **Data profiling** - Distinct counts, nulls, min/max, top values
- **Group analysis** - Analyze multiple tables together
- **Privacy controls** - Mask sensitive data, configurable sampling

**This gives AI the FULL context to truly understand your database!** 🚀

