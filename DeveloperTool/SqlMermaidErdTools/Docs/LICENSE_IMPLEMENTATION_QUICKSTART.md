# License Implementation Quick Start

**Goal**: Add simple license validation to SqlMermaidErdTools in 1 week

---

## Quick Decision Matrix

| Your Situation | Recommended Approach | Time to Implement |
|---------------|---------------------|-------------------|
| Solo dev, just starting | **Simple License Key + Gumroad** | 2-3 days |
| Small team, want recurring revenue | **Stripe Subscriptions + Basic Validation** | 1 week |
| Enterprise customers | **Online Activation + Customer Portal** | 2-4 weeks |

---

## Simplest Implementation: **License Key File**

### Step 1: Create License Key Format (5 minutes)

```
License File: sqlmermaid.lic
Location: Same directory as .exe or user's AppData

Format: JSON
{
  "key": "SQLMMD-XXXX-XXXX-XXXX-XXXX",
  "email": "customer@email.com",
  "tier": "Pro",
  "expires": "2026-12-31"
}
```

---

### Step 2: Add License Validator Class (30 minutes)

**File**: `src/SqlMermaidErdTools/Licensing/LicenseValidator.cs`

```csharp
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace SqlMermaidErdTools.Licensing;

public enum LicenseTier
{
    Free,
    Pro,
    Enterprise
}

public record LicenseInfo(
    string Key,
    string Email,
    LicenseTier Tier,
    DateTime? ExpiryDate,
    bool IsValid
);

public static class LicenseValidator
{
    private const string LICENSE_FILE = "sqlmermaid.lic";
    private const string SECRET_KEY = "YOUR_SECRET_KEY_CHANGE_THIS"; // Change for production!
    
    public static LicenseInfo GetCurrentLicense()
    {
        // Check for license file in multiple locations
        var possiblePaths = new[]
        {
            LICENSE_FILE, // Current directory
            Path.Combine(AppContext.BaseDirectory, LICENSE_FILE), // App directory
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), 
                         "SqlMermaidErdTools", LICENSE_FILE) // AppData
        };
        
        foreach (var path in possiblePaths)
        {
            if (File.Exists(path))
            {
                try
                {
                    return ValidateLicenseFile(path);
                }
                catch
                {
                    // Invalid license file, try next location
                }
            }
        }
        
        // No license found - return free tier
        return new LicenseInfo("", "", LicenseTier.Free, null, true);
    }
    
    private static LicenseInfo ValidateLicenseFile(string path)
    {
        var json = File.ReadAllText(path);
        var data = JsonSerializer.Deserialize<Dictionary<string, string>>(json);
        
        if (data == null)
            return new LicenseInfo("", "", LicenseTier.Free, null, false);
        
        var key = data.GetValueOrDefault("key", "");
        var email = data.GetValueOrDefault("email", "");
        var tierStr = data.GetValueOrDefault("tier", "Free");
        var expiresStr = data.GetValueOrDefault("expires", "");
        
        // Validate checksum
        if (!ValidateChecksum(key, email))
            return new LicenseInfo(key, email, LicenseTier.Free, null, false);
        
        // Parse tier
        if (!Enum.TryParse<LicenseTier>(tierStr, out var tier))
            tier = LicenseTier.Free;
        
        // Parse expiry
        DateTime? expiryDate = null;
        if (DateTime.TryParse(expiresStr, out var parsed))
        {
            expiryDate = parsed;
            if (parsed < DateTime.UtcNow)
                return new LicenseInfo(key, email, tier, expiryDate, false); // Expired
        }
        
        return new LicenseInfo(key, email, tier, expiryDate, true);
    }
    
    private static bool ValidateChecksum(string key, string email)
    {
        if (string.IsNullOrWhiteSpace(key))
            return false;
        
        var parts = key.Split('-');
        if (parts.Length != 5)
            return false;
        
        // Expected: SQLMMD-XXXX-XXXX-XXXX-CHECKSUM
        var prefix = parts[0];
        var segment1 = parts[1];
        var segment2 = parts[2];
        var segment3 = parts[3];
        var checksum = parts[4];
        
        if (prefix != "SQLMMD")
            return false;
        
        // Compute expected checksum
        var data = $"{segment1}{segment2}{segment3}{email}{SECRET_KEY}";
        var expectedChecksum = ComputeChecksum(data);
        
        return checksum == expectedChecksum;
    }
    
    private static string ComputeChecksum(string data)
    {
        using var sha256 = SHA256.Create();
        var hash = sha256.ComputeHash(Encoding.UTF8.GetBytes(data));
        var base64 = Convert.ToBase64String(hash);
        
        // Take first 4 chars and make alphanumeric
        return new string(base64.Where(char.IsLetterOrDigit).Take(4).ToArray()).ToUpper();
    }
    
    // Helper to generate license keys (for your license server/admin tool)
    public static string GenerateLicenseKey(string email)
    {
        var random = new Random();
        var segment1 = GenerateRandomSegment(random);
        var segment2 = GenerateRandomSegment(random);
        var segment3 = GenerateRandomSegment(random);
        
        var data = $"{segment1}{segment2}{segment3}{email}{SECRET_KEY}";
        var checksum = ComputeChecksum(data);
        
        return $"SQLMMD-{segment1}-{segment2}-{segment3}-{checksum}";
    }
    
    private static string GenerateRandomSegment(Random random)
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // Excluding confusing chars
        return new string(Enumerable.Range(0, 4)
            .Select(_ => chars[random.Next(chars.Length)])
            .ToArray());
    }
}
```

---

### Step 3: Add Feature Gating (15 minutes)

**Update**: `src/SqlMermaidErdTools/Converters/SqlToMmdConverter.cs`

```csharp
using SqlMermaidErdTools.Licensing;

public class SqlToMmdConverter : BaseConverter, ISqlToMmdConverter
{
    public string Convert(string sqlDdl)
    {
        // Validate license
        var license = LicenseValidator.GetCurrentLicense();
        
        ValidateInput(sqlDdl, nameof(sqlDdl));
        
        // Apply limitations for free tier
        if (license.Tier == LicenseTier.Free)
        {
            var tableCount = CountTables(sqlDdl);
            if (tableCount > 10)
            {
                throw new LicenseException(
                    $"Free tier is limited to 10 tables (found {tableCount}). " +
                    "Upgrade to Pro for unlimited tables: https://sqlmermaidtools.com/pricing");
            }
        }
        
        // Continue with conversion...
        try
        {
            var cleanedSql = CleanSqlBrackets(sqlDdl);
            return ExecutePythonWithTempFile("sql_to_mmd.py", cleanedSql);
        }
        catch (ConversionException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new SqlParseException(
                $"Failed to convert SQL to Mermaid ERD: {ex.Message}",
                ex);
        }
    }
    
    private int CountTables(string sql)
    {
        // Simple regex to count CREATE TABLE statements
        var pattern = @"CREATE\s+TABLE\s+";
        return System.Text.RegularExpressions.Regex.Matches(
            sql, 
            pattern, 
            System.Text.RegularExpressions.RegexOptions.IgnoreCase
        ).Count;
    }
}
```

---

### Step 4: Create License Exception (5 minutes)

**File**: `src/SqlMermaidErdTools/Exceptions/LicenseException.cs`

```csharp
namespace SqlMermaidErdTools.Exceptions;

/// <summary>
/// Exception thrown when license validation fails or feature is not available in current tier.
/// </summary>
public class LicenseException : Exception
{
    public LicenseException(string message) : base(message)
    {
    }
    
    public LicenseException(string message, Exception innerException) 
        : base(message, innerException)
    {
    }
}
```

---

### Step 5: Set Up Gumroad for Sales (10 minutes)

1. **Create account**: https://gumroad.com
2. **Create product**:
   - Name: "SqlMermaidErdTools Pro"
   - Price: $99/year or $249 lifetime
   - Description: Your feature list
3. **Add license key delivery**:
   - Enable "Generate license keys"
   - Use pattern: `SQLMMD-{random}-{random}-{random}-{random}`
4. **Set up webhook** (optional):
   - Endpoint: `https://yoursite.com/api/gumroad-webhook`
   - Automatically generate proper license file

---

### Step 6: Create Simple Landing Page (2 hours)

**File**: `website/index.html`

```html
<!DOCTYPE html>
<html>
<head>
    <title>SqlMermaidErdTools - Pricing</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 1200px; margin: 0 auto; padding: 20px; }
        .pricing-table { display: flex; gap: 20px; justify-content: center; }
        .pricing-card { border: 2px solid #ddd; border-radius: 10px; padding: 30px; 
                       text-align: center; flex: 1; max-width: 300px; }
        .pricing-card.featured { border-color: #0066cc; transform: scale(1.05); }
        .price { font-size: 48px; font-weight: bold; color: #0066cc; }
        .features { text-align: left; margin: 20px 0; }
        .feature { margin: 10px 0; }
        .feature::before { content: "✓ "; color: green; font-weight: bold; }
        .buy-button { background: #0066cc; color: white; padding: 15px 30px; 
                     border: none; border-radius: 5px; font-size: 18px; cursor: pointer; }
        .buy-button:hover { background: #0052a3; }
    </style>
</head>
<body>
    <h1>SqlMermaidErdTools - Pricing</h1>
    
    <div class="pricing-table">
        <!-- Free Tier -->
        <div class="pricing-card">
            <h2>Free</h2>
            <div class="price">$0</div>
            <p>Forever</p>
            
            <div class="features">
                <div class="feature">Up to 10 tables</div>
                <div class="feature">All SQL dialects</div>
                <div class="feature">Community support</div>
                <div class="feature">Open source</div>
            </div>
            
            <button class="buy-button" onclick="location.href='https://www.nuget.org/packages/SqlMermaidErdTools'">
                Get Started
            </button>
        </div>
        
        <!-- Pro Tier -->
        <div class="pricing-card featured">
            <h2>Pro</h2>
            <div class="price">$99</div>
            <p>per year</p>
            
            <div class="features">
                <div class="feature">Unlimited tables</div>
                <div class="feature">All SQL dialects</div>
                <div class="feature">Priority support</div>
                <div class="feature">Commercial use</div>
                <div class="feature">Regular updates</div>
            </div>
            
            <button class="buy-button" onclick="location.href='https://gumroad.com/l/sqlmermaid-pro'">
                Buy Now
            </button>
            
            <p style="font-size: 12px; color: #666;">
                or $249 lifetime license
            </p>
        </div>
        
        <!-- Enterprise Tier -->
        <div class="pricing-card">
            <h2>Enterprise</h2>
            <div class="price">Custom</div>
            <p>Contact us</p>
            
            <div class="features">
                <div class="feature">Everything in Pro</div>
                <div class="feature">Volume licensing</div>
                <div class="feature">SLA guarantee</div>
                <div class="feature">Dedicated support</div>
                <div class="feature">Custom features</div>
            </div>
            
            <button class="buy-button" onclick="location.href='mailto:sales@sqlmermaidtools.com'">
                Contact Sales
            </button>
        </div>
    </div>
    
    <h2>FAQ</h2>
    <details>
        <summary>How do I activate my Pro license?</summary>
        <p>After purchase, you'll receive a license file. Save it as <code>sqlmermaid.lic</code> 
           in your project directory or in <code>%APPDATA%\SqlMermaidErdTools\</code></p>
    </details>
    
    <details>
        <summary>Can I try Pro before buying?</summary>
        <p>Yes! Contact us for a 14-day trial license.</p>
    </details>
    
    <details>
        <summary>What's your refund policy?</summary>
        <p>30-day money-back guarantee, no questions asked.</p>
    </details>
</body>
</html>
```

---

## Complete Implementation Example

### Project Structure

```
src/SqlMermaidErdTools/
├── Licensing/
│   ├── LicenseValidator.cs      ← Validates license files
│   ├── LicenseInfo.cs           ← License data model
│   └── LicenseTier.cs           ← Enum: Free/Pro/Enterprise
├── Exceptions/
│   └── LicenseException.cs      ← Thrown when license invalid
└── Converters/
    └── SqlToMmdConverter.cs     ← Updated with license checks
```

---

### Full Working Example

**1. LicenseInfo.cs**
```csharp
namespace SqlMermaidErdTools.Licensing;

public record LicenseInfo
{
    public string Key { get; init; } = "";
    public string Email { get; init; } = "";
    public LicenseTier Tier { get; init; } = LicenseTier.Free;
    public DateTime? ExpiryDate { get; init; }
    public bool IsValid { get; init; }
    public bool IsExpired => ExpiryDate.HasValue && ExpiryDate.Value < DateTime.UtcNow;
    
    public static LicenseInfo FreeTier => new()
    {
        Tier = LicenseTier.Free,
        IsValid = true
    };
}

public enum LicenseTier
{
    Free = 0,
    Pro = 1,
    Enterprise = 2
}
```

**2. Feature Limits**
```csharp
public static class LicenseLimits
{
    public static int GetMaxTables(LicenseTier tier) => tier switch
    {
        LicenseTier.Free => 10,
        LicenseTier.Pro => int.MaxValue,
        LicenseTier.Enterprise => int.MaxValue,
        _ => 10
    };
    
    public static bool CanUseCommercially(LicenseTier tier) => tier switch
    {
        LicenseTier.Free => false,
        LicenseTier.Pro => true,
        LicenseTier.Enterprise => true,
        _ => false
    };
    
    public static bool HasPrioritySupport(LicenseTier tier) => tier switch
    {
        LicenseTier.Free => false,
        LicenseTier.Pro => true,
        LicenseTier.Enterprise => true,
        _ => false
    };
}
```

---

## Gumroad Integration

### Automatic License File Generation

When customer purchases on Gumroad, you can automatically email them a license file:

**Gumroad Webhook Handler** (optional - for automation)
```csharp
[ApiController]
[Route("api/gumroad")]
public class GumroadWebhookController : ControllerBase
{
    [HttpPost("webhook")]
    public async Task<IActionResult> HandlePurchase([FromForm] GumroadPurchase purchase)
    {
        // Verify Gumroad signature
        if (!VerifyGumroadSignature(purchase))
            return Unauthorized();
        
        // Generate license
        var licenseKey = LicenseValidator.GenerateLicenseKey(purchase.Email);
        
        var licenseFile = new
        {
            key = licenseKey,
            email = purchase.Email,
            tier = "Pro",
            expires = DateTime.UtcNow.AddYears(1).ToString("yyyy-MM-dd")
        };
        
        var json = JsonSerializer.Serialize(licenseFile, new JsonSerializerOptions 
        { 
            WriteIndented = true 
        });
        
        // Email license file to customer
        await SendEmailWithAttachment(
            purchase.Email,
            "Your SqlMermaidErdTools License",
            "Thank you for your purchase! Attached is your license file.",
            "sqlmermaid.lic",
            json
        );
        
        // Log purchase
        await _db.Purchases.AddAsync(new Purchase
        {
            Email = purchase.Email,
            LicenseKey = licenseKey,
            PurchaseDate = DateTime.UtcNow,
            GumroadOrderId = purchase.OrderId
        });
        await _db.SaveChangesAsync();
        
        return Ok();
    }
}
```

---

## User Experience Flow

### For Free Users

```
1. Install NuGet package
   dotnet add package SqlMermaidErdTools

2. Use normally (up to 10 tables)
   var converter = new SqlToMmdConverter();
   var mermaid = converter.Convert(sql);

3. Hit limitation
   ❌ LicenseException: "Free tier is limited to 10 tables (found 25).
      Upgrade to Pro: https://sqlmermaidtools.com/pricing"
```

---

### For Pro Customers

```
1. Purchase license from Gumroad
   → Receives email with sqlmermaid.lic file

2. Save license file
   Option A: In project directory
   Option B: In %APPDATA%\SqlMermaidErdTools\

3. Use with unlimited tables
   var converter = new SqlToMmdConverter();
   var mermaid = converter.Convert(largeSql); // ✅ Works!
```

---

## Alternative: Environment Variable License

Simpler for CI/CD environments:

```csharp
public static LicenseInfo GetCurrentLicense()
{
    // Check environment variable first (for CI/CD)
    var licenseKey = Environment.GetEnvironmentVariable("SQLMERMAID_LICENSE_KEY");
    if (!string.IsNullOrWhiteSpace(licenseKey))
    {
        return ValidateLicenseKey(licenseKey);
    }
    
    // Fall back to license file
    return GetLicenseFromFile();
}
```

**Usage in CI/CD**:
```yaml
# GitHub Actions
env:
  SQLMERMAID_LICENSE_KEY: ${{ secrets.SQLMERMAID_LICENSE }}

# Azure DevOps
variables:
  SQLMERMAID_LICENSE_KEY: $(SqlMermaidLicenseKey)
```

---

## Testing Your Implementation

### Test Free Tier
```csharp
[Fact]
public void FreeTier_WithLargeSql_ShouldThrowLicenseException()
{
    // Remove license file if exists
    if (File.Exists("sqlmermaid.lic"))
        File.Delete("sqlmermaid.lic");
    
    var largeSql = GenerateSqlWith(15); // 15 tables
    
    var converter = new SqlToMmdConverter();
    
    Assert.Throws<LicenseException>(() => converter.Convert(largeSql));
}
```

### Test Pro Tier
```csharp
[Fact]
public void ProTier_WithLargeSql_ShouldSucceed()
{
    // Create Pro license file
    var license = new
    {
        key = LicenseValidator.GenerateLicenseKey("test@example.com"),
        email = "test@example.com",
        tier = "Pro",
        expires = "2099-12-31"
    };
    
    File.WriteAllText("sqlmermaid.lic", 
        JsonSerializer.Serialize(license, new JsonSerializerOptions { WriteIndented = true }));
    
    var largeSql = GenerateSqlWith(100); // 100 tables
    
    var converter = new SqlToMmdConverter();
    
    var result = converter.Convert(largeSql); // Should work!
    Assert.NotNull(result);
}
```

---

## 7-Day Implementation Plan

### Day 1: Foundation
- [ ] Create `Licensing` folder and classes
- [ ] Implement `LicenseValidator`
- [ ] Add `LicenseException`
- [ ] Write unit tests for license validation

### Day 2: Integration
- [ ] Update all converters with license checks
- [ ] Add table counting logic
- [ ] Test free tier limitations
- [ ] Update documentation

### Day 3: Gumroad Setup
- [ ] Create Gumroad account and product
- [ ] Set up pricing ($99/year, $249 lifetime)
- [ ] Configure license key generation
- [ ] Test purchase flow

### Day 4: Customer Experience
- [ ] Create simple landing page
- [ ] Write getting started guide
- [ ] Create email templates
- [ ] Set up support email

### Day 5: Testing
- [ ] Test end-to-end purchase → activation
- [ ] Verify license validation works
- [ ] Test expiry handling
- [ ] Test invalid license scenarios

### Day 6: Documentation
- [ ] Update README with licensing info
- [ ] Create activation guide
- [ ] Document upgrade process
- [ ] Create FAQ

### Day 7: Launch
- [ ] Publish Pro version to NuGet
- [ ] Announce on social media
- [ ] Email existing users about Pro tier
- [ ] Monitor for issues

---

## Example: Complete License File for Customer

**Generated after purchase via Gumroad**:

```json
{
  "key": "SQLMMD-AB3F-7C9D-E1F2-4G6H",
  "email": "customer@company.com",
  "tier": "Pro",
  "expires": "2026-12-31",
  "issuedDate": "2025-12-01",
  "features": {
    "unlimitedTables": true,
    "commercialUse": true,
    "prioritySupport": true
  },
  "metadata": {
    "purchaseId": "gumroad_12345",
    "version": "1.0"
  }
}
```

**Installation Instructions for Customer**:
```
1. Download the attached sqlmermaid.lic file
2. Save it to one of these locations:
   • Your project folder
   • C:\Users\YourName\AppData\Roaming\SqlMermaidErdTools\
   • Your solution root directory
3. That's it! The Pro features are now unlocked.
```

---

## Revenue Projections

### Conservative Estimate (Year 1)
```
Month 1-3: 10 Pro licenses × $99 = $990
Month 4-6: 25 Pro licenses × $99 = $2,475
Month 7-9: 50 Pro licenses × $99 = $4,950
Month 10-12: 75 Pro licenses × $99 = $7,425

Year 1 Total: ~$15,840
```

### Optimistic Estimate (Year 1)
```
Monthly Pro Sales: 100 × $99 = $9,900/month
Lifetime Sales: 10 × $249 = $2,490
Enterprise Deals: 2 × $999 = $1,998

Year 1 Total: ~$123,678
```

### Costs
```
Gumroad fees (8.5%): -$1,346 (conservative) to -$10,512 (optimistic)
Hosting (license server): -$20/month = -$240/year
Email service (SendGrid): -$15/month = -$180/year
Domain & SSL: -$50/year

Net profit: $14,064 (conservative) to $112,696 (optimistic)
```

---

## Immediate Action Items

If you want to start monetizing **this week**:

### Minimum Viable Product (MVP)
1. ✅ Add license validator class (already provided above)
2. ✅ Add 10-table limit to free tier
3. ✅ Create Gumroad product
4. ✅ Create simple landing page
5. ✅ Publish dual-licensed NuGet package

**Time**: 1-2 days  
**Cost**: $0 (Gumroad handles everything)  
**Revenue Potential**: $1,000-$5,000/month

---

## Questions?

**Technical Questions**: Check `LicenseValidator.cs` example above  
**Business Questions**: See "Licensing Models" section  
**Implementation Help**: See "7-Day Implementation Plan"

**Ready to monetize?** Start with the simple Gumroad + license file approach! 🚀

