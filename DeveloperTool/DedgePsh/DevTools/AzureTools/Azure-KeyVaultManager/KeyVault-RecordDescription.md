# Azure Key Vault Record Description

Record/schema description of Azure Key Vault entities and their attributes.

---

## Azure Key Vault (Vault entity)

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Vault name (e.g. `p-we1int-apps-shared-kv`) |
| `location` | string | Region (e.g. `westeurope`) |
| `resourceGroup` | string | Resource group that owns the vault |
| `id` | string | Full resource ID |
| `vaultUri` | string | Base URI (e.g. `https://{name}.vault.azure.net/`) |
| `tenantId` | string | Azure AD tenant that owns the vault |
| `properties.enableSoftDelete` | bool | Soft delete enabled |
| `properties.enablePurgeProtection` | bool | Purge protection enabled |
| `properties.softDeleteRetentionInDays` | int | Days before purge (7–90) |
| `sku.name` | string | SKU: `standard` or `premium` |

---

## Key Vault Secret

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Full secret URI (includes version) |
| `name` | string | Secret name |
| `value` | string | Secret value (returned only when reading) |
| `contentType` | string | Optional MIME type |
| `attributes.enabled` | bool | Whether the secret is active |
| `attributes.created` | datetime | Creation time (UTC) |
| `attributes.updated` | datetime | Last update time (UTC) |
| `attributes.expires` | datetime | Optional expiration |
| `attributes.notBefore` | datetime | Optional activation time |
| `attributes.recoveryLevel` | string | `Recoverable`, `Recoverable+Purgeable`, etc. |
| `tags` | object | Custom key-value metadata |

---

## Soft-Deleted Secret (recoverable state)

| Field | Type | Description |
|-------|------|-------------|
| `deletedDate` | datetime | When the secret was soft-deleted (UTC) |
| `scheduledPurgeDate` | datetime | When purge will run (after retention) |
| `recoveryId` | string | Full URI used for recovery (undelete) |
