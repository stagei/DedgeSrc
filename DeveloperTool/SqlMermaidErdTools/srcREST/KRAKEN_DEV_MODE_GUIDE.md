# KRAKEN Development Mode - Complete Guide

## 🚀 Overview

KRAKEN Development Mode is a special testing mode that automatically disables API key authentication when running on a computer named "KRAKEN". This allows for faster development and testing without managing API keys.

---

## 🔧 How It Works

### 1. Automatic Detection

The system automatically detects if you're on the KRAKEN computer:

**PowerShell Test Script:**
```powershell
$computerName = $env:COMPUTERNAME
if ($computerName -eq "KRAKEN") {
    # Auto-enable dev mode
    $SkipTokenCheck = $true
}
```

**C# Middleware:**
```csharp
var computerName = Environment.MachineName;
if (computerName.Equals("KRAKEN", StringComparison.OrdinalIgnoreCase))
{
    context.Items["ApiKey"] = "KRAKEN-DEV-MODE";
    await _next(context);
    return;
}
```

### 2. Special API Key

When KRAKEN mode is detected, a special API key is set:
- **Key:** `KRAKEN-DEV-MODE`
- **Access:** Unlimited
- **Rate Limit:** None
- **Table Limit:** `int.MaxValue` (2,147,483,647 tables)

### 3. Controller Handling

Controllers check for the KRAKEN dev mode key:

```csharp
var tableLimit = int.MaxValue;
if (apiKey != "KRAKEN-DEV-MODE")
{
    var keyInfo = await _apiKeyService.GetApiKeyInfoAsync(apiKey);
    tableLimit = keyInfo.TableLimit;
}
```

---

## ✅ Benefits

### Development
- ✅ No need to generate API keys
- ✅ No license key management
- ✅ Unlimited API access
- ✅ No rate limiting
- ✅ Faster iteration

### Testing
- ✅ Automated test execution
- ✅ No token expiration issues
- ✅ Consistent test results
- ✅ Faster test runs
- ✅ Simpler CI/CD setup

### Debugging
- ✅ Easy API exploration
- ✅ No auth headers needed
- ✅ Focus on functionality
- ✅ Instant access

---

## 🎯 Use Cases

### 1. Automated Testing
```powershell
# On KRAKEN computer
PS> .\Tests\Run-RestApiTests.ps1
# Token check automatically disabled
✅ All tests run without API keys
```

### 2. Manual API Testing
```powershell
# On KRAKEN computer
PS> curl http://localhost:5001/api/v1/conversion/sql-to-mermaid `
    -H "Content-Type: application/json" `
    -d '{"sql":"CREATE TABLE test (id INT);"}'

# No X-API-Key header needed!
```

### 3. Development Workflow
```powershell
# Start API
cd srcREST
dotnet run

# Make requests without auth
# Test changes immediately
# No key management overhead
```

---

## 🔒 Security

### Safety Measures
- ✅ Only enabled on KRAKEN computer
- ✅ Computer name check (case-insensitive)
- ✅ No configuration file changes
- ✅ No environment variables needed
- ✅ Automatic detection

### Production Safety
- ✅ KRAKEN mode never active in production
- ✅ Normal auth flow unaffected
- ✅ No security vulnerabilities
- ✅ Computer-specific activation

### Override
Can manually disable even on KRAKEN:
```powershell
.\Tests\Run-RestApiTests.ps1 -SkipTokenCheck:$false
```

---

## 📊 What Gets Bypassed

| Feature | Normal Mode | KRAKEN Mode |
|---------|-------------|-------------|
| **API Key Required** | ✅ Yes | ❌ No |
| **Key Validation** | ✅ Yes | ❌ No |
| **Table Limits** | ✅ Per tier | ❌ Unlimited |
| **Rate Limiting** | ✅ Yes | ❌ No |
| **Daily Quotas** | ✅ Yes | ❌ No |
| **License Check** | ✅ Yes | ❌ No |

---

## 🛠️ Implementation Locations

### 1. Middleware
**File:** `srcREST/Middleware/ApiKeyAuthenticationMiddleware.cs`

```csharp
public async Task InvokeAsync(HttpContext context, IApiKeyService apiKeyService)
{
    // Skip authentication for health check and docs
    if (context.Request.Path.StartsWithSegments("/health") ||
        context.Request.Path.StartsWithSegments("/swagger") ||
        context.Request.Path.StartsWithSegments("/api/auth"))
    {
        await _next(context);
        return;
    }

    // Skip token validation on KRAKEN computer (for testing)
    var computerName = Environment.MachineName;
    if (computerName.Equals("KRAKEN", StringComparison.OrdinalIgnoreCase))
    {
        context.Items["ApiKey"] = "KRAKEN-DEV-MODE";
        await _next(context);
        return;
    }

    // ... normal authentication flow
}
```

### 2. Controllers
**File:** `srcREST/Controllers/ConversionController.cs`

All three endpoints (SqlToMermaid, MermaidToSql, GenerateMigration):

```csharp
var apiKey = HttpContext.Items["ApiKey"]?.ToString();
if (apiKey == null)
{
    return Unauthorized(...);
}

// KRAKEN dev mode - unlimited access
var tableLimit = int.MaxValue;
if (apiKey != "KRAKEN-DEV-MODE")
{
    var keyInfo = await _apiKeyService.GetApiKeyInfoAsync(apiKey);
    tableLimit = keyInfo.TableLimit;
}

var result = await _conversionService.ConvertAsync(..., tableLimit);
```

### 3. Test Script
**File:** `srcREST/Tests/Run-RestApiTests.ps1`

```powershell
# Detect if running on KRAKEN
$computerName = $env:COMPUTERNAME
$isKraken = $computerName -eq "KRAKEN"

# Auto-skip token check on KRAKEN
if ($isKraken -and -not $SkipTokenCheck) {
    Write-Info "Running on KRAKEN - automatically skipping token validation"
    $SkipTokenCheck = $true
}
```

---

## 📋 Test Output Examples

### On KRAKEN Computer
```
ℹ️  Running on KRAKEN - automatically skipping token validation

═══════════════════════════════════════════════════════════════════
Setting Up REST API Test Environment
═══════════════════════════════════════════════════════════════════

ℹ️  Computer: KRAKEN
ℹ️  API Base URL: http://localhost:5001/api/v1
ℹ️  Token Check: DISABLED
```

### On Other Computers
```
═══════════════════════════════════════════════════════════════════
Setting Up REST API Test Environment
═══════════════════════════════════════════════════════════════════

ℹ️  Computer: MY-LAPTOP
ℹ️  API Base URL: http://localhost:5001/api/v1
ℹ️  Token Check: ENABLED
```

---

## 🔄 How to Rename Your Computer to KRAKEN

### Windows
```powershell
# PowerShell (Admin)
Rename-Computer -NewName "KRAKEN" -Restart
```

### Verify
```powershell
PS> $env:COMPUTERNAME
KRAKEN
```

### Alternative: Don't Rename
Use the `-SkipTokenCheck` parameter instead:
```powershell
.\Tests\Run-RestApiTests.ps1 -SkipTokenCheck
```

---

## 🧪 Testing KRAKEN Mode

### Test 1: Verify Computer Name Detection
```powershell
PS> $env:COMPUTERNAME
KRAKEN
```

### Test 2: Run API Tests
```powershell
PS> .\Tests\Run-RestApiTests.ps1
# Should see: "Running on KRAKEN - automatically skipping token validation"
```

### Test 3: Make Direct API Call
```powershell
PS> curl http://localhost:5001/api/v1/conversion/sql-to-mermaid `
    -H "Content-Type: application/json" `
    -d '{"sql":"CREATE TABLE users (id INT);"}'

# Should succeed without X-API-Key header
```

### Test 4: Check Middleware
```powershell
# In logs, should see:
# context.Items["ApiKey"] = "KRAKEN-DEV-MODE"
```

---

## ⚠️ Important Notes

### Do NOT Use in Production
- KRAKEN mode is for development/testing only
- Never deploy to production with KRAKEN settings
- Never name production servers "KRAKEN"

### Override When Needed
```powershell
# Force authentication even on KRAKEN
.\Tests\Run-RestApiTests.ps1 -SkipTokenCheck:$false
```

### Fallback
If KRAKEN detection fails:
- Use `-SkipTokenCheck` parameter
- Generate a test API key
- Check computer name spelling

---

## 📊 Comparison with Manual Skip

| Method | Detection | Setup | Flexibility |
|--------|-----------|-------|-------------|
| **KRAKEN Mode** | Automatic | One-time | Best for dedicated dev machine |
| **-SkipTokenCheck** | Manual | Per-run | Best for occasional testing |
| **Test API Key** | None | Per-session | Best for CI/CD |

---

## 🎯 Recommended Setup

### Development Machine
1. Rename computer to "KRAKEN"
2. Run tests normally (auto-detection)
3. Never worry about API keys

### CI/CD Pipeline
1. Don't rename build agent
2. Use `-SkipTokenCheck` parameter
3. Or generate temporary API key

### Team Environment
1. Each developer has own setup
2. KRAKEN name optional
3. Use parameters for flexibility

---

## ✅ Checklist

- [x] Computer named "KRAKEN" (optional)
- [x] Middleware detects computer name
- [x] Controllers handle KRAKEN dev mode
- [x] Test script auto-detects KRAKEN
- [x] All limits bypassed on KRAKEN
- [x] Can manually override with parameters
- [x] Production safety maintained

---

## 🔍 Troubleshooting

### KRAKEN Mode Not Working

**Check Computer Name:**
```powershell
PS> $env:COMPUTERNAME
# Should be: KRAKEN
```

**Check Case Sensitivity:**
- "KRAKEN" ✅
- "kraken" ✅
- "Kraken" ✅
- All work (case-insensitive)

**Force Dev Mode:**
```powershell
.\Tests\Run-RestApiTests.ps1 -SkipTokenCheck
```

### Still Getting Auth Errors

**Verify Middleware:**
- Check `ApiKeyAuthenticationMiddleware.cs`
- Ensure computer name check is present
- Confirm `KRAKEN-DEV-MODE` is set

**Verify Controller:**
- Check `ConversionController.cs`
- Ensure KRAKEN dev mode check exists
- Confirm unlimited `tableLimit` is set

---

## 📚 Related Documentation

- [REST API Tests README](Tests/README.md) - Test suite documentation
- [REST API README](README.md) - API documentation
- [REST_API_TESTS_COMPLETE.md](Tests/REST_API_TESTS_COMPLETE.md) - Implementation details

---

**KRAKEN Development Mode - Making development and testing easier!**

*Part of the SqlMermaidErdTools automated testing ecosystem*

