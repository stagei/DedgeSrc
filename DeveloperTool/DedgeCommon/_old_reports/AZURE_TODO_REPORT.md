# Azure-Dependent Code TODO Report

**Date:** 2025-12-16  
**Purpose:** Comprehensive list of all code requiring Azure access for full functionality

---

## 📋 Summary

Total Azure TODO items: **11**
- Azure Key Vault operations: **10**
- Security improvements: **1**

---

## 🔐 Azure Key Vault Manager TODOs

All items in `DedgeCommon/AzureKeyVaultManager.cs`

### TODO #1: Default Azure Credential (Line 74)
**Location:** Constructor  
**Code:**
```csharp
// TODO: Requires Azure authentication to be configured on the machine
var credential = new DefaultAzureCredential();
_secretClient = new SecretClient(new Uri(_keyVaultUri), credential);
```

**Requirements:**
- Azure authentication configured on machine
- Options: Managed Identity, Azure CLI, Visual Studio, Environment variables
- Works automatically on Azure VMs/App Services with managed identity

**Testing:** Can test locally with `az login` (Azure CLI)

---

### TODO #2: Create/Update Secret (Line 117)
**Location:** `CreateOrUpdateSecretAsync()`  
**Code:**
```csharp
// TODO: Requires Azure Key Vault access permissions
var response = await _secretClient.SetSecretAsync(secret);
```

**Requirements:**
- Key Vault permissions: `Set` on secrets
- Service Principal or Managed Identity access

---

### TODO #3: Get Secret (Line 193)
**Location:** `GetSecretAsync()`  
**Code:**
```csharp
// TODO: Requires Azure Key Vault read permissions
var response = await _secretClient.GetSecretAsync(secretName);
```

**Requirements:**
- Key Vault permissions: `Get` on secrets

---

### TODO #4: Get Credential (Line 215)
**Location:** `GetCredentialAsync()`  
**Code:**
```csharp
// TODO: Requires Azure Key Vault read permissions
var response = await _secretClient.GetSecretAsync(credentialName);
```

**Requirements:**
- Key Vault permissions: `Get` on secrets

---

### TODO #5: Search by Username (Line 255)
**Location:** `GetCredentialByUsernameAsync()`  
**Code:**
```csharp
// TODO: Requires Azure Key Vault list permissions
var allSecrets = _secretClient.GetPropertiesOfSecretsAsync();
```

**Requirements:**
- Key Vault permissions: `List` on secrets
- Iterates through all secrets to find matching username in tags

---

### TODO #6: List Secret Names (Line 293)
**Location:** `ListSecretNamesAsync()`  
**Code:**
```csharp
// TODO: Requires Azure Key Vault list permissions
var allSecrets = _secretClient.GetPropertiesOfSecretsAsync();
```

**Requirements:**
- Key Vault permissions: `List` on secrets

---

### TODO #7: List Credentials (Line 323)
**Location:** `ListCredentialsAsync()`  
**Code:**
```csharp
// TODO: Requires Azure Key Vault list and read permissions
var allSecrets = _secretClient.GetPropertiesOfSecretsAsync();
```

**Requirements:**
- Key Vault permissions: `List` and `Get` on secrets
- Lists all secrets, then reads those tagged as credentials

---

### TODO #8: Delete Secret (Line 403)
**Location:** `DeleteSecretAsync()`  
**Code:**
```csharp
// TODO: Requires Azure Key Vault delete permissions
var deleteOperation = await _secretClient.StartDeleteSecretAsync(secretName);
```

**Requirements:**
- Key Vault permissions: `Delete` on secrets
- Creates soft-delete (can be recovered unless purged)

---

### TODO #9: Purge Secret (Line 409)
**Location:** `DeleteSecretAsync()` (purge path)  
**Code:**
```csharp
// TODO: Requires Azure Key Vault purge permissions
await _secretClient.PurgeDeletedSecretAsync(secretName);
```

**Requirements:**
- Key Vault permissions: `Purge` on secrets
- **WARNING**: Permanently deletes secret, cannot be recovered
- Only works if soft-delete protection is enabled on Key Vault

---

### TODO #10: Test Connection (Line 639)
**Location:** `TestConnectionAsync()`  
**Code:**
```csharp
// TODO: Requires Azure Key Vault read permissions
var secrets = _secretClient.GetPropertiesOfSecretsAsync();
```

**Requirements:**
- Key Vault permissions: `List` on secrets (minimum)
- Used to verify connectivity before operations

---

## 🔒 Security Improvement TODOs

### TODO #11: Network Share Credentials (Line 72)
**Location:** `DedgeCommon/NetworkShareManager.cs`  
**Code:**
```csharp
// TODO: Move credentials to Azure Key Vault instead of hardcoding
public const string M_Password = "Namdal10";
public const string YZ_Password = "FiloDeig01!";
```

**Current Issue:**
- Hardcoded passwords for network shares
- Only affects production server (p-no1fkmprd-app)
- Credentials for drives M:, Y:, Z:

**Recommendation:**
```csharp
// Retrieve from Key Vault instead
var kvManager = new AzureKeyVaultManager("Dedge-keyvault");
var cred1 = await kvManager.GetCredentialAsync("network-share-m-drive");
var cred2 = await kvManager.GetCredentialAsync("network-share-yz-drives");
```

**Impact:** Medium - Currently functional but violates security best practices

---

## 🧪 Testing Requirements

### Local Testing (Without Azure)
The following operations can be tested locally without Azure access:
- ✅ Environment settings creation
- ✅ Network share mapping (except production drives with credentials)
- ✅ COBOL program execution (if Micro Focus COBOL installed)
- ✅ Database connectivity

### Azure Testing Required
The following require actual Azure Key Vault access:
- ❌ All Azure Key Vault Manager operations
- ❌ Credential retrieval for network shares (future enhancement)

### Test Project Configuration
The `TestAzureKeyVault` project requires:
1. Valid Azure Key Vault name
2. Service Principal credentials OR Managed Identity
3. Azure Key Vault with appropriate permissions configured

**Configuration file:** `TestAzureKeyVault/appsettings.json`

---

## 📋 Azure Key Vault Setup Checklist

To use the Azure Key Vault Manager, complete these steps:

### 1. Create Azure Key Vault
```bash
az keyvault create \
  --name your-keyvault-name \
  --resource-group your-resource-group \
  --location norwayeast
```

### 2. Create Service Principal
```bash
az ad sp create-for-rbac \
  --name Dedge-keyvault-access \
  --role "Key Vault Secrets User"
```

### 3. Grant Permissions
```bash
az keyvault set-policy \
  --name your-keyvault-name \
  --spn <client-id> \
  --secret-permissions get list set delete purge
```

### 4. Configure Application
Update `appsettings.json` with:
- KeyVaultName
- TenantId
- ClientId
- ClientSecret

---

## 🎯 Priority Recommendations

### High Priority
1. **Configure Azure Key Vault for testing** (to verify all functionality)
2. **Test import/export operations** (ensure JSON/CSV formats work correctly)
3. **Verify credential search by username** (complex operation with tags)

### Medium Priority
4. **Move network share credentials to Key Vault** (security improvement)
5. **Add connection string encryption** (additional security layer)
6. **Implement secret versioning access** (for audit trails)

### Low Priority
7. **Add certificate management** (future enhancement)
8. **Add key management** (if needed for encryption)
9. **Implement soft-delete recovery** (admin operations)

---

## 🔧 Workarounds for Testing

If Azure access is not available immediately:

### Mock Testing
Create a mock Key Vault manager for unit testing:
```csharp
public class MockKeyVaultManager : IAzureKeyVaultManager
{
    private Dictionary<string, string> _mockSecrets = new();
    
    public async Task<KeyVaultSecret> CreateOrUpdateSecretAsync(string name, string value)
    {
        _mockSecrets[name] = value;
        return new KeyVaultSecret(name, value);
    }
    // ... implement other methods
}
```

### Local File Storage
For development/testing without Azure:
```csharp
// Temporary: Store secrets in encrypted local file
// Replace with Azure Key Vault in production
```

---

## ✅ Non-Azure Dependent Features

These features work without Azure access:

### FkEnvironmentSettings
- ✅ Automatic environment detection
- ✅ COBOL version detection
- ✅ Database configuration
- ✅ Executable path detection

### NetworkShareManager
- ✅ Standard drive mapping (F, K, N, R, X)
- ⚠️  Production drives require credentials (currently hardcoded)

### RunCblProgram
- ✅ COBOL program execution
- ✅ Return code checking
- ✅ Transcript file generation
- ✅ Monitor file creation

---

## 📊 Implementation Status

| Component | Status | Azure Required |
|-----------|--------|----------------|
| FkEnvironmentSettings | ✅ Complete | No |
| NetworkShareManager | ✅ Complete | No (credentials hardcoded) |
| AzureKeyVaultManager | ✅ Complete | Yes (all operations) |
| RunCblProgram | ✅ Complete | No |
| Test Project | ✅ Complete | Yes (for testing) |

---

## 📚 Additional Documentation

- See `TestAzureKeyVault/README.md` for setup instructions
- See `AzureKeyVaultManager.cs` for detailed API documentation
- All Azure operations are clearly marked with TODO comments

---

## 🚀 Next Steps

1. **Immediate**: Test non-Azure features (environment settings, COBOL execution)
2. **Short-term**: Configure Azure Key Vault for testing
3. **Long-term**: Migrate network share credentials to Key Vault

---

**Report Generated:** 2025-12-16  
**Total Items Requiring Azure Access:** 11  
**Status:** All code complete, pending Azure configuration for testing
