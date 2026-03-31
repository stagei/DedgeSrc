# SqlMermaidErdTools - Licensing & Monetization Guide

**Document Version**: 1.0  
**Date**: December 1, 2025  
**Current License**: MIT (Open Source)

---

## Table of Contents

1. [Overview](#overview)
2. [Licensing Models](#licensing-models)
3. [Pricing Strategies](#pricing-strategies)
4. [Technical Implementation](#technical-implementation)
5. [Distribution Channels](#distribution-channels)
6. [Payment Processing](#payment-processing)
7. [License Management](#license-management)
8. [Legal Considerations](#legal-considerations)
9. [Implementation Roadmap](#implementation-roadmap)

---

## Overview

SqlMermaidErdTools is currently released under the **MIT License** (open source). This guide explores options for monetizing the tool while maintaining a positive relationship with the developer community.

### Current Status
- ✅ Open source (MIT License)
- ✅ Published on NuGet.org (free)
- ✅ Source code on GitHub (public)

### Monetization Goals
- 💰 Generate revenue from commercial users
- 🎯 Maintain community goodwill
- 📈 Scale with usage
- 🔒 Protect intellectual property

---

## Licensing Models

### Option 1: **Dual Licensing** (Recommended)

**Best for**: Balancing open source community and commercial revenue

#### Free Tier (Open Source)
- **License**: MIT License (keep as is)
- **Features**: Core functionality
- **Limitations**: 
  - Small projects only (<10 tables)
  - Development/testing use only
  - Community support only
  - Attribution required

#### Commercial License
- **License**: Proprietary EULA
- **Features**: All features unlocked
- **Benefits**:
  - Unlimited tables/schemas
  - Production use allowed
  - Priority support
  - Commercial distribution rights
  - No attribution required

**Example Pricing**:
```
Individual Developer: $49/year or $149 perpetual
Team (5 developers): $199/year or $499 perpetual
Enterprise (unlimited): $999/year or $2,999 perpetual
```

---

### Option 2: **Freemium Model**

**Best for**: Building large user base first

#### Free Version
- Core SQL ↔ Mermaid conversion
- Limited to 10 tables per schema
- Public GitHub repositories only
- Community support

#### Pro Version ($99/year or $249 perpetual)
- Unlimited tables
- Advanced features:
  - Database reverse engineering
  - Live database connection
  - Schema comparison
  - Custom styling/themes
  - Batch processing
- Email support
- Commercial use allowed

#### Enterprise Version ($999/year)
- All Pro features
- On-premise deployment
- SSO integration
- SLA guarantee
- Dedicated support
- Training & onboarding
- Custom feature development

---

### Option 3: **Usage-Based Licensing**

**Best for**: Pay-as-you-go model

#### Tiers
- **Starter**: Free (100 conversions/month)
- **Professional**: $29/month (1,000 conversions/month)
- **Business**: $99/month (10,000 conversions/month)
- **Enterprise**: Custom pricing (unlimited)

#### Metering
- Track API calls via license server
- Monthly billing based on usage
- Automatic tier upgrades
- Grace period for overages

---

### Option 4: **Feature-Based Licensing**

**Best for**: Modular approach

#### Core (Free)
- Basic SQL → Mermaid
- Basic Mermaid → SQL
- ANSI SQL only

#### Add-ons (Pay per feature)
- **Dialect Pack** ($29/year): SQL Server, PostgreSQL, MySQL, Oracle
- **Advanced Features** ($49/year): Schema diff, migration scripts
- **Database Connectors** ($99/year): Direct DB connections
- **Enterprise Features** ($199/year): SSO, audit logs, compliance

#### Bundle Pricing
- All Add-ons: $249/year (save 25%)
- Lifetime Access: $699 (one-time)

---

### Option 5: **Open Core Model** (Hybrid)

**Best for**: Transparency and trust

#### Open Source Core (MIT)
- SQL ↔ Mermaid conversion
- All SQL dialects
- CLI tool
- Community support
- Public repository

#### Commercial Extensions (Proprietary)
- **Visual Studio Extension** ($49/year)
- **Azure DevOps Integration** ($99/year)
- **Database Import Tool** ($149/year)
- **Enterprise Security Pack** ($299/year)
  - SSO/SAML
  - Audit logging
  - Role-based access
  - Compliance reports

---

## Pricing Strategies

### 1. **Perpetual License**

**Pros**: Higher upfront revenue, customer ownership  
**Cons**: No recurring revenue, harder to support

```
Individual: $149 (lifetime)
Team (5 seats): $499 (lifetime)
Enterprise: $2,999 (lifetime)

Optional: 1st year support included, $49/year renewal
```

---

### 2. **Subscription Model**

**Pros**: Predictable recurring revenue, easier to scale  
**Cons**: Customer resistance, churn risk

```
Monthly:
  - Individual: $9/month
  - Team: $29/month
  - Enterprise: $99/month

Annual (save 20%):
  - Individual: $87/year ($7.25/month)
  - Team: $279/year ($23.25/month)
  - Enterprise: $950/year ($79.17/month)
```

---

### 3. **Volume Licensing**

**For large organizations**

```
1-10 seats:    $99/seat/year
11-50 seats:   $79/seat/year (20% discount)
51-100 seats:  $59/seat/year (40% discount)
101+ seats:    $49/seat/year (50% discount)

Site License (unlimited): $4,999/year
```

---

### 4. **Educational & Non-Profit Pricing**

**For students, academics, and non-profits**

```
Student/Teacher: Free (with .edu email)
Academic Institution: 50% off commercial pricing
Non-Profit: 50% off commercial pricing
Open Source Projects: Free (attribution required)
```

---

## Technical Implementation

### Architecture Overview

```
┌─────────────────┐
│   Your App      │
│  (NuGet Pkg)    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐      ┌──────────────────┐
│ License Manager │ ───► │  License Server  │
│   (Local)       │      │  (Cloud/API)     │
└─────────────────┘      └──────────────────┘
         │                        │
         ▼                        ▼
┌─────────────────┐      ┌──────────────────┐
│ License File    │      │   Database       │
│ (.lic)          │      │  (Customers)     │
└─────────────────┘      └──────────────────┘
```

---

### Implementation Option 1: **License Key System** (Simple)

#### How It Works
1. Customer purchases license
2. Receives license key via email
3. Adds key to app configuration
4. App validates key on startup

#### License Key Format
```
SQLMMD-XXXX-XXXX-XXXX-XXXX-XXXX

Format: PRODUCT-RANDOM-RANDOM-RANDOM-CHECKSUM-FEATURE
Example: SQLMMD-A3F5-B7C9-D1E2-4F6A-PRO
```

#### Code Implementation

**1. License Key Generator** (Server-side)
```csharp
public class LicenseKeyGenerator
{
    public static string GenerateLicenseKey(
        string customerEmail,
        LicenseType type,
        DateTime expiryDate)
    {
        var random = GenerateRandomSegments(3); // 12 chars
        var features = EncodeFeatures(type); // 4 chars
        
        var payload = $"{customerEmail}|{type}|{expiryDate:yyyy-MM-dd}";
        var checksum = ComputeChecksum(payload); // 4 chars
        
        return $"SQLMMD-{random[0]}-{random[1]}-{random[2]}-{checksum}-{features}";
    }
    
    private static string ComputeChecksum(string data)
    {
        using var sha256 = SHA256.Create();
        var hash = sha256.ComputeHash(Encoding.UTF8.GetBytes(data));
        return Convert.ToBase64String(hash).Substring(0, 4).ToUpper();
    }
}
```

**2. License Validator** (Client-side in NuGet package)
```csharp
public class LicenseValidator
{
    private const string LICENSE_FILE = "sqlmermaid.lic";
    
    public static LicenseInfo ValidateLicense()
    {
        // 1. Check for license file
        if (!File.Exists(LICENSE_FILE))
            return LicenseInfo.FreeTier;
        
        var licenseKey = File.ReadAllText(LICENSE_FILE).Trim();
        
        // 2. Validate format
        if (!IsValidFormat(licenseKey))
            throw new InvalidLicenseException("Invalid license key format");
        
        // 3. Verify checksum
        if (!VerifyChecksum(licenseKey))
            throw new InvalidLicenseException("License key checksum failed");
        
        // 4. Check expiration (if subscription)
        var license = DecodeLicense(licenseKey);
        if (license.ExpiryDate < DateTime.UtcNow)
            throw new ExpiredLicenseException("License has expired");
        
        // 5. Optional: Online activation check
        if (!VerifyOnlineActivation(licenseKey))
            throw new InvalidLicenseException("License activation failed");
        
        return license;
    }
}
```

**3. Feature Gating** (In converters)
```csharp
public class SqlToMmdConverter
{
    public string Convert(string sqlDdl)
    {
        var license = LicenseValidator.ValidateLicense();
        
        // Free tier limitations
        if (license.Type == LicenseType.Free)
        {
            var tableCount = CountTables(sqlDdl);
            if (tableCount > 10)
                throw new LicenseException(
                    "Free tier limited to 10 tables. Upgrade to Pro for unlimited tables.");
        }
        
        // Continue with conversion...
        return PerformConversion(sqlDdl, license);
    }
}
```

**4. License File Format**
```json
{
  "licenseKey": "SQLMMD-A3F5-B7C9-D1E2-4F6A-PRO",
  "licensee": "Acme Corporation",
  "email": "admin@acme.com",
  "type": "Enterprise",
  "features": ["UnlimitedTables", "AllDialects", "PrioritySupport"],
  "issueDate": "2025-01-01",
  "expiryDate": "2026-01-01",
  "maxUsers": 50,
  "signature": "BASE64_SIGNATURE_HERE"
}
```

---

### Implementation Option 2: **Online Activation** (Secure)

#### How It Works
1. Customer purchases license
2. Receives activation code
3. App contacts license server for activation
4. Server validates and issues license token
5. Token stored locally, periodic validation

#### Architecture

**License Server API**
```csharp
[ApiController]
[Route("api/licenses")]
public class LicenseController : ControllerBase
{
    [HttpPost("activate")]
    public async Task<ActionResult<ActivationResponse>> Activate(
        [FromBody] ActivationRequest request)
    {
        // 1. Validate activation code
        var license = await _db.Licenses.FindAsync(request.ActivationCode);
        if (license == null || license.IsActivated)
            return BadRequest("Invalid or already activated");
        
        // 2. Generate device fingerprint
        var deviceId = GenerateDeviceFingerprint(request.MachineInfo);
        
        // 3. Check activation limits
        if (license.ActivationCount >= license.MaxActivations)
            return BadRequest("Maximum activations reached");
        
        // 4. Create activation
        var activation = new Activation
        {
            LicenseId = license.Id,
            DeviceId = deviceId,
            ActivatedAt = DateTime.UtcNow,
            LastValidated = DateTime.UtcNow
        };
        
        await _db.Activations.AddAsync(activation);
        license.ActivationCount++;
        await _db.SaveChangesAsync();
        
        // 5. Issue JWT token
        var token = GenerateLicenseToken(license, activation);
        
        return Ok(new ActivationResponse
        {
            Token = token,
            ExpiresAt = license.ExpiryDate,
            Features = license.Features
        });
    }
    
    [HttpPost("validate")]
    public async Task<ActionResult<ValidationResponse>> Validate(
        [FromBody] ValidationRequest request)
    {
        // Verify JWT token
        var principal = ValidateToken(request.Token);
        if (principal == null)
            return Unauthorized("Invalid token");
        
        // Check if still active
        var activationId = principal.FindFirst("activation_id")?.Value;
        var activation = await _db.Activations.FindAsync(activationId);
        
        if (activation == null || activation.RevokedAt != null)
            return Unauthorized("License revoked");
        
        // Update last validation time
        activation.LastValidated = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        
        return Ok(new ValidationResponse
        {
            Valid = true,
            ExpiresAt = activation.License.ExpiryDate
        });
    }
}
```

**Client Implementation**
```csharp
public class OnlineLicenseValidator
{
    private static readonly HttpClient _httpClient = new();
    private const string LICENSE_API = "https://licenses.sqlmermaidtools.com/api/licenses";
    
    public static async Task<string> ActivateLicense(string activationCode)
    {
        var machineInfo = GetMachineInfo();
        
        var response = await _httpClient.PostAsJsonAsync($"{LICENSE_API}/activate", new
        {
            ActivationCode = activationCode,
            MachineInfo = machineInfo
        });
        
        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            throw new LicenseActivationException(error);
        }
        
        var result = await response.Content.ReadFromJsonAsync<ActivationResponse>();
        
        // Store token locally
        await File.WriteAllTextAsync("license.token", result.Token);
        
        return result.Token;
    }
    
    public static async Task<bool> ValidateLicense()
    {
        if (!File.Exists("license.token"))
            return false;
        
        var token = await File.ReadAllTextAsync("license.token");
        
        // Offline validation first (check JWT expiry)
        if (IsTokenValidOffline(token))
            return true;
        
        // Online validation (every 7 days or on startup)
        var response = await _httpClient.PostAsJsonAsync($"{LICENSE_API}/validate", new
        {
            Token = token
        });
        
        return response.IsSuccessStatusCode;
    }
    
    private static MachineInfo GetMachineInfo()
    {
        return new MachineInfo
        {
            MachineName = Environment.MachineName,
            UserName = Environment.UserName,
            ProcessorId = GetProcessorId(),
            MacAddress = GetMacAddress(),
            OSVersion = Environment.OSVersion.ToString()
        };
    }
}
```

---

### Implementation Option 3: **Hardware-Locked License** (Node-Locked)

#### How It Works
- License tied to specific machine
- Uses hardware fingerprint (CPU ID, MAC address, etc.)
- Prevents sharing of licenses
- Requires deactivation to move to new machine

```csharp
public class HardwareLicenseValidator
{
    public static string GenerateDeviceFingerprint()
    {
        var components = new[]
        {
            GetProcessorId(),
            GetMotherboardSerial(),
            GetMacAddress(),
            Environment.MachineName
        };
        
        var combined = string.Join("|", components);
        using var sha256 = SHA256.Create();
        var hash = sha256.ComputeHash(Encoding.UTF8.GetBytes(combined));
        return Convert.ToBase64String(hash);
    }
    
    public static bool ValidateHardwareLock(string licenseKey)
    {
        var currentFingerprint = GenerateDeviceFingerprint();
        var licenseFingerprint = ExtractFingerprintFromLicense(licenseKey);
        
        return currentFingerprint == licenseFingerprint;
    }
}
```

---

### Implementation Option 4: **Floating License Server** (Concurrent Users)

#### How It Works
- Central license server manages available licenses
- Users "check out" licenses when using the tool
- Licenses returned when done
- Allows more users than licenses (not all active simultaneously)

```csharp
public class FloatingLicenseServer
{
    private readonly ConcurrentDictionary<string, LicenseCheckout> _activeCheckouts = new();
    private readonly int _totalLicenses;
    
    public async Task<LicenseCheckout> CheckOutLicense(string userId)
    {
        if (_activeCheckouts.Count >= _totalLicenses)
            throw new NoLicensesAvailableException("All licenses in use");
        
        var checkout = new LicenseCheckout
        {
            UserId = userId,
            CheckedOutAt = DateTime.UtcNow,
            ExpiresAt = DateTime.UtcNow.AddHours(8)
        };
        
        _activeCheckouts[userId] = checkout;
        return checkout;
    }
    
    public void CheckInLicense(string userId)
    {
        _activeCheckouts.TryRemove(userId, out _);
    }
    
    public void StartHeartbeatMonitor()
    {
        // Remove stale checkouts
        Task.Run(async () =>
        {
            while (true)
            {
                var stale = _activeCheckouts.Where(x => x.Value.ExpiresAt < DateTime.UtcNow);
                foreach (var checkout in stale)
                    _activeCheckouts.TryRemove(checkout.Key, out _);
                
                await Task.Delay(TimeSpan.FromMinutes(5));
            }
        });
    }
}
```

---

## Distribution Channels

### 1. **NuGet.org** (Current)
- ✅ **Free tier**: Public package on NuGet.org
- ❌ **Paid tier**: Cannot distribute paid packages on public NuGet

**Solution**: Use package with license validation
```xml
<PackageReference Include="SqlMermaidErdTools" Version="0.2.8" />
<!-- License key required for Pro features -->
```

---

### 2. **Private NuGet Feed** (For Pro/Enterprise)
- Host on Azure Artifacts, MyGet, or self-hosted
- Customers get access after payment
- More control over distribution

```bash
# Customer adds private feed
dotnet nuget add source https://nuget.yourcompany.com/feed \
  --name SqlMermaidErdToolsPro \
  --username customer@email.com \
  --password ACCESS_TOKEN

# Install Pro version
dotnet add package SqlMermaidErdTools.Pro --version 1.0.0
```

---

### 3. **Direct Download** (Traditional)
- Sell DLL directly from website
- Customer downloads after payment
- Manual installation

---

### 4. **Visual Studio Marketplace**
- Distribute as VS Extension
- Built-in payment processing
- Reach Visual Studio users directly

---

### 5. **Microsoft AppSource** (For Enterprise)
- Enterprise marketplace
- Integration with Microsoft billing
- Better for large organizations

---

## Payment Processing

### Option 1: **Stripe** (Recommended)

**Pros**: Developer-friendly, global, recurring billing  
**Cons**: 2.9% + $0.30 per transaction

```csharp
// Create Stripe checkout session
var options = new SessionCreateOptions
{
    PaymentMethodTypes = new List<string> { "card" },
    LineItems = new List<SessionLineItemOptions>
    {
        new SessionLineItemOptions
        {
            PriceData = new SessionLineItemPriceDataOptions
            {
                UnitAmount = 9900, // $99.00
                Currency = "usd",
                ProductData = new SessionLineItemPriceDataProductDataOptions
                {
                    Name = "SqlMermaidErdTools Pro",
                    Description = "Annual subscription",
                },
                Recurring = new SessionLineItemPriceDataRecurringOptions
                {
                    Interval = "year",
                }
            },
            Quantity = 1,
        },
    },
    Mode = "subscription",
    SuccessUrl = "https://yoursite.com/success?session_id={CHECKOUT_SESSION_ID}",
    CancelUrl = "https://yoursite.com/cancel",
};

var service = new SessionService();
var session = service.Create(options);
```

---

### Option 2: **Gumroad**

**Pros**: Super simple, handles everything  
**Cons**: Higher fees (8.5% + $0.30)

- Perfect for solo developers
- No coding required
- Automatic license key delivery
- Handles EU VAT

---

### Option 3: **Paddle**

**Pros**: Merchant of record (handles tax), recurring billing  
**Cons**: 5% + $0.50 per transaction

- Handles all tax compliance
- Good for SaaS
- Global payment methods

---

### Option 4: **FastSpring**

**Pros**: Enterprise-focused, handles everything  
**Cons**: 5.9% + $0.95 per transaction

- Best for enterprise customers
- Handles invoicing
- Multi-currency support

---

## License Management

### Customer Portal Features

```
┌─────────────────────────────────────┐
│      Customer License Portal        │
├─────────────────────────────────────┤
│ ✓ View active licenses              │
│ ✓ Download license files            │
│ ✓ Activate/deactivate devices       │
│ ✓ View activation history           │
│ ✓ Upgrade/downgrade plan            │
│ ✓ View invoices                     │
│ ✓ Update payment method             │
│ ✓ Contact support                   │
└─────────────────────────────────────┘
```

### Admin Dashboard Features

```
┌─────────────────────────────────────┐
│       Admin Dashboard               │
├─────────────────────────────────────┤
│ ✓ Customer management               │
│ ✓ License generation                │
│ ✓ Activation monitoring             │
│ ✓ Revenue analytics                 │
│ ✓ Churn analysis                    │
│ ✓ Support ticket system             │
│ ✓ Feature usage analytics           │
└─────────────────────────────────────┘
```

---

## Legal Considerations

### 1. **EULA (End User License Agreement)**

Required sections:
- Grant of license
- Restrictions (no reverse engineering, redistribution)
- Support terms
- Warranty disclaimer
- Limitation of liability
- Termination clause
- Governing law

**Template**: https://www.termsfeed.com/eula/

---

### 2. **Privacy Policy**

If collecting customer data:
- What data is collected
- How it's used
- How it's protected
- GDPR compliance (if EU customers)
- Data retention policy

---

### 3. **Terms of Service**

- Subscription terms
- Refund policy
- Cancellation policy
- Fair use policy

---

### 4. **Export Compliance**

- Check if your software has encryption
- May require export license for certain countries
- Comply with OFAC sanctions

---

### 5. **Tax Compliance**

- **US**: Sales tax varies by state
- **EU**: VAT required (19-27% depending on country)
- **Global**: GST, VAT, sales tax in various countries

**Solution**: Use Paddle or Stripe Tax to handle automatically

---

## Implementation Roadmap

### Phase 1: **Free Tier Optimization** (Month 1)

- [ ] Add table count limitation (10 tables max for free)
- [ ] Add "Upgrade to Pro" messages
- [ ] Create landing page
- [ ] Set up analytics

### Phase 2: **Basic License System** (Month 2)

- [ ] Implement license key generator
- [ ] Add license validator to NuGet package
- [ ] Create simple checkout page (Gumroad/Stripe)
- [ ] Set up license delivery email

### Phase 3: **Customer Portal** (Month 3)

- [ ] Build license management portal
- [ ] Implement activation/deactivation
- [ ] Add invoice generation
- [ ] Create support ticket system

### Phase 4: **Enterprise Features** (Month 4+)

- [ ] Implement volume licensing
- [ ] Add SSO support
- [ ] Create admin dashboard
- [ ] Build floating license server

---

## Recommended Starting Approach

### **For Solo Developer**: 

**Model**: Dual Licensing (Free + Pro)  
**Payment**: Gumroad (simplest)  
**License**: Simple license key file  
**Pricing**: $49/year or $149 perpetual

**Minimum Viable Product**:
1. Keep current free version with 10-table limit
2. Create Pro version with unlimited tables
3. Use Gumroad to sell license keys
4. Email license key to customer
5. Customer saves key to `sqlmermaid.lic` file
6. NuGet package reads file and validates

**Time to Launch**: 1-2 weeks

---

### **For Growing Business**:

**Model**: Freemium (Free/Pro/Enterprise)  
**Payment**: Stripe (subscriptions)  
**License**: Online activation  
**Pricing**: $9/month, $99/month, Custom

**Features**:
1. Free tier with limitations
2. Pro tier with online activation
3. Enterprise tier with dedicated support
4. Customer portal for license management
5. Analytics and usage tracking

**Time to Launch**: 1-2 months

---

## Next Steps

1. **Decide on licensing model** (see recommendations above)
2. **Update LICENSE file** if going commercial
3. **Implement license validation** in code
4. **Set up payment processing** (Gumroad/Stripe)
5. **Create landing page** with pricing
6. **Test purchase flow**
7. **Soft launch** to early adopters
8. **Iterate based on feedback**

---

## Resources

### Legal
- https://www.termsfeed.com/ - EULA/ToS generators
- https://www.freeprivacypolicy.com/ - Privacy policy generator

### Payment Processing
- https://stripe.com - Payment processing
- https://gumroad.com - Simple selling platform
- https://paddle.com - Merchant of record

### License Management
- https://keygen.sh - License key API
- https://cryptlex.com - License management platform
- https://10duke.com - Enterprise license management

### Analytics
- https://www.google.com/analytics - Free analytics
- https://posthog.com - Product analytics
- https://mixpanel.com - User behavior analytics

---

## Conclusion

SqlMermaidErdTools has strong potential for monetization given its unique value proposition. Starting with a **simple dual-licensing model** (free tier + paid Pro version) is recommended, using Gumroad for payment processing and a basic license key file for validation.

As the customer base grows, you can evolve to more sophisticated online activation, subscription models, and enterprise features.

**Key Success Factors**:
1. ✅ Keep free tier valuable (builds user base)
2. ✅ Make Pro tier compelling (clear value)
3. ✅ Simple purchase process (no friction)
4. ✅ Fair pricing (aligned with value delivered)
5. ✅ Excellent support (builds loyalty)

Good luck with monetization! 🚀

---

**Questions?** Open an issue or contact support@sqlmermaidtools.com

