# Azure Key Vault Manager Test Project

This project tests the comprehensive Azure Key Vault management functionality in DedgeCommon.

## Setup

### 1. Configure appsettings.json

Edit `appsettings.json` with your Azure Key Vault details:

```json
{
  "AzureKeyVault": {
    "KeyVaultName": "your-keyvault-name",
    "TenantId": "your-tenant-id",
    "ClientId": "your-client-id",
    "ClientSecret": "your-client-secret-or-pat",
    "UseManagedIdentity": false
  }
}
```

### 2. Authentication Options

#### Option A: Service Principal (Recommended for local testing)
1. Create a service principal in Azure AD
2. Grant it access to your Key Vault (Get, List, Set, Delete secrets)
3. Set `UseManagedIdentity` to `false`
4. Provide `TenantId`, `ClientId`, and `ClientSecret`

#### Option B: Managed Identity (For Azure VMs/App Services)
1. Enable managed identity on your Azure resource
2. Grant the managed identity access to Key Vault
3. Set `UseManagedIdentity` to `true`
4. Leave other fields empty

#### Option C: Azure CLI (For local development)
1. Install Azure CLI
2. Run `az login`
3. Set `UseManagedIdentity` to `true`
4. The DefaultAzureCredential will use your Azure CLI credentials

## Required Azure Permissions

The service principal or managed identity needs these permissions on the Key Vault:

**Secret Permissions:**
- Get
- List
- Set
- Delete
- Purge (optional, for permanent deletion)

## Running Tests

```powershell
cd C:\opt\src\DedgeCommon\TestAzureKeyVault
dotnet run
```

## Test Suite

The program runs 15 comprehensive tests:

1. ✓ Create Secret
2. ✓ Read Secret
3. ✓ Create Credential (username:password pair)
4. ✓ Read Credential
5. ✓ Search Credential by Username
6. ✓ List All Secrets
7. ✓ List All Credentials
8. ✓ Export to JSON (passwords redacted)
9. ✓ Export to CSV (passwords redacted)
10. ✓ Import from JSON
11. ✓ Import from CSV
12. ✓ Update Secret
13. ✓ Update Credential Password
14. ✓ Batch Create Secrets
15. ✓ Delete Secrets (soft-delete, can be recovered)

## Features Tested

### CRUD Operations
- Create/Update secrets and credentials
- Read secrets and credentials
- Delete secrets (with optional purge)

### Search & List
- List all secrets
- List all credentials
- Search credentials by username

### Import/Export
- Import from JSON file
- Import from CSV file
- Export to JSON (with password redaction option)
- Export to CSV (with password redaction option)

### Batch Operations
- Batch create/update multiple secrets
- Batch create/update multiple credentials

### Credential Management
- Store username/password pairs as single secret
- Tag credentials for easy filtering
- Update passwords independently

## Output Files

After running tests, you'll find:
- `test-export.json` - Exported credentials in JSON format
- `test-export.csv` - Exported credentials in CSV format
- `test-import.json` - Test import data (auto-generated)
- `test-import.csv` - Test import data (auto-generated)

## Security Note

⚠️ **WARNING**: 
- Never commit `appsettings.json` with real credentials to source control
- The export functionality can export passwords in plain text - use with caution
- Always use the `includePasswords: false` option in production exports
- Credentials in files are temporary test data only

## Troubleshooting

### "Failed to connect to Key Vault"
- Verify your Key Vault name is correct
- Check that your service principal has access
- Ensure firewall rules allow your IP address

### "Access denied"
- Check that your service principal has the required permissions
- Verify the permissions include Get, List, Set, Delete for secrets

### "Authentication failed"
- Verify TenantId, ClientId, and ClientSecret are correct
- Check that the service principal is not expired
- Try using Azure CLI authentication as fallback

## TODO Items

Some operations require actual Azure access and are marked with TODO comments:
- See `AZURE_TODO_REPORT.md` for a complete list of Azure-dependent operations
