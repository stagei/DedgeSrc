# Configuring Trusted Signing Certificate Profile Signer Role in Azure

This guide explains how to create and assign the "Trusted Signing Certificate Profile Signer" role in Azure Active Directory.

## Prerequisites

- Azure subscription with administrative access
- Azure CLI installed (optional)
- Access to Azure Portal

## Steps to Create the Custom Role

### Method 1: Using Azure Portal

1. Sign in to the [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Active Directory**
3. Select **Roles and administrators**
4. Click **+ New custom role**
5. Configure the role with these settings:
   - Name: "Trusted Signing Certificate Profile Signer"
   - Description: "Can sign and manage trusted certificate profiles"
   - Baseline permissions: Start from scratch
   - Permissions:
     - Microsoft.Authorization/*/read
     - Microsoft.Certificates/trustedSigningCertificates/*

### Method 2: Using Azure PowerShell

```powershell
# Connect to Azure
Connect-AzAccount

# Create the role definition
$role = @{
    Name = "Trusted Signing Certificate Profile Signer"
    Description = "Can sign and manage trusted certificate profiles"
    Actions = @(
        "Microsoft.Authorization/*/read",
        "Microsoft.Certificates/trustedSigningCertificates/*"
    )
    AssignableScopes = @("/subscriptions/<your-subscription-id>")
}

New-AzRoleDefinition -Role $role
```

## Assigning the Role to a User

### Using Azure Portal

1. Navigate to **Azure Active Directory**
2. Select **Roles and administrators**
3. Find and click on the "Trusted Signing Certificate Profile Signer" role
4. Click **+ Add assignments**
5. Search for and select the user
6. Click **Add**

### Using Azure PowerShell

```powershell
# Variables
$userPrincipalName = "user@domain.com"
$subscriptionId = "<your-subscription-id>"
$roleName = "Trusted Signing Certificate Profile Signer"

# Get user object ID
$user = Get-AzADUser -UserPrincipalName $userPrincipalName

# Assign role
New-AzRoleAssignment -ObjectId $user.Id `
                     -RoleDefinitionName $roleName `
                     -Scope "/subscriptions/$subscriptionId"
```

## Verification

To verify the role assignment:

1. Have the user sign in to Azure Portal
2. Navigate to Azure Active Directory
3. Click on **My permissions**
4. Confirm the "Trusted Signing Certificate Profile Signer" role is listed

## Notes

- The role assignment may take a few minutes to propagate
- Ensure the user has appropriate base permissions in Azure AD
- Regular auditing of role assignments is recommended for security

## Troubleshooting

If you encounter issues:

1. Verify the user exists in Azure AD
2. Check if you have sufficient permissions to assign roles
3. Ensure the subscription ID is correct
4. Wait a few minutes for role propagation
5. Check Azure Activity Logs for any error messages

For additional support, contact Azure Support or consult the [Azure documentation](https://docs.microsoft.com/en-us/azure/role-based-access-control/). 