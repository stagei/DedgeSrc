# SqlMermaid ERD Tools - REST API

RESTful API service for converting between SQL DDL and Mermaid ERD diagrams with license-based access control.

## 🚀 Quick Start

### 1. Start the API

```bash
cd srcREST
dotnet run
```

API will be available at: **http://localhost:5001**

### 2. Get Your API Key

Visit the API Portal: **http://localhost:5000/api-portal.html**

Or create one programmatically:

```bash
curl -X POST "http://localhost:5001/api/v1/auth/create-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "your@email.com",
    "licenseKey": "SQLMMD-PRO-XXXX"
  }'
```

### 3. Make Your First Request

```bash
curl -X POST "http://localhost:5001/api/v1/conversion/sql-to-mermaid" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_API_KEY_HERE" \
  -d '{
    "sql": "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100));"
  }'
```

---

## 📡 API Endpoints

### Authentication

#### Create API Key
```
POST /api/v1/auth/create-api-key
```
**Body:**
```json
{
  "email": "your@email.com",
  "licenseKey": "SQLMMD-PRO-XXXX-XXXX-XXXX"
}
```

**Response:**
```json
{
  "apiKey": "sk_sqlmmd_...",
  "tier": "Pro",
  "email": "your@email.com",
  "expiresAt": "2035-12-01T00:00:00Z",
  "message": "API key created successfully"
}
```

#### Get Key Info
```
GET /api/v1/auth/key-info
Headers: X-API-Key: YOUR_KEY
```

**Response:**
```json
{
  "tier": "Pro",
  "email": "your@email.com",
  "tableLimit": 2147483647,
  "requestsToday": 42,
  "dailyLimit": 10000,
  "expiresAt": "2035-12-01T00:00:00Z",
  "isActive": true
}
```

---

### Conversion Endpoints

All conversion endpoints require the `X-API-Key` header.

#### SQL to Mermaid
```
POST /api/v1/conversion/sql-to-mermaid
```
**Body:**
```json
{
  "sql": "CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100));",
  "includeAst": false
}
```

**Response:**
```json
{
  "success": true,
  "result": "erDiagram\n  users {\n    int id PK\n    varchar name\n  }",
  "ast": null,
  "metadata": {
    "tableCount": 1,
    "columnCount": 2,
    "relationshipCount": 0,
    "dialect": "Input SQL"
  }
}
```

#### Mermaid to SQL
```
POST /api/v1/conversion/mermaid-to-sql
```
**Body:**
```json
{
  "mermaid": "erDiagram\n  users {\n    int id PK\n    varchar name\n  }",
  "dialect": "SqlServer",
  "includeAst": false
}
```

**Dialects:** `AnsiSql`, `SqlServer`, `PostgreSql`, `MySql`

**Response:**
```json
{
  "success": true,
  "result": "CREATE TABLE users (\n  id INT PRIMARY KEY,\n  name VARCHAR(100)\n);",
  "metadata": {
    "tableCount": 1,
    "dialect": "SqlServer"
  }
}
```

#### Generate Migration
```
POST /api/v1/conversion/generate-migration
```
**Body:**
```json
{
  "beforeMermaid": "...",
  "afterMermaid": "...",
  "dialect": "PostgreSql"
}
```

**Response:**
```json
{
  "success": true,
  "result": "ALTER TABLE users ADD COLUMN email VARCHAR(100);",
  "metadata": {
    "tableCount": 1,
    "dialect": "PostgreSql"
  }
}
```

---

## 🔑 License Tiers

### Free Tier
- **Table Limit:** 10 tables per schema
- **Daily Requests:** 100
- **Rate Limit:** 10 requests/minute
- **License Key:** `SQLMMD-FREE-TRIAL`

### Pro Tier
- **Table Limit:** Unlimited
- **Daily Requests:** 10,000
- **Rate Limit:** 100 requests/minute
- **Price:** $49/product (one-time)

### Enterprise Tier
- **Table Limit:** Unlimited
- **Daily Requests:** 100,000
- **Rate Limit:** 1,000 requests/minute
- **Price:** Starting at $299/year
- **Features:** Unlimited API keys, priority support

---

## 🔐 Authentication

All API requests (except auth endpoints) require an API key in the header:

```
X-API-Key: sk_sqlmmd_your_key_here
```

### Error Responses

**401 Unauthorized:**
```json
{
  "error": "Invalid or expired API key",
  "detail": "Your API key is invalid, expired, or has exceeded rate limits"
}
```

**400 Bad Request:**
```json
{
  "error": "Conversion failed",
  "statusCode": 400
}
```

**Table Limit Exceeded:**
```json
{
  "success": false,
  "error": "Table limit exceeded. Your Free license allows 10 tables, but this schema has 25 tables. Upgrade to Pro or Enterprise for unlimited tables."
}
```

---

## 📚 Interactive Documentation

**Swagger UI:** http://localhost:5001/swagger

Try out all endpoints with interactive documentation.

---

## 🏗️ Architecture

### Components

- **Program.cs** - API configuration, middleware pipeline
- **Controllers/**
  - `ConversionController.cs` - SQL/Mermaid conversion endpoints
  - `AuthController.cs` - API key management
- **Services/**
  - `ConversionService.cs` - Core conversion logic
  - `ApiKeyService.cs` - API key validation, rate limiting
- **Middleware/**
  - `ApiKeyAuthenticationMiddleware.cs` - API key validation
- **Models/**
  - `ApiModels.cs` - Request/response models

### Storage

API keys are stored in `apikeys.json` (gitignored). In production, use a database.

---

## 🧪 Testing

### Unit Tests
```bash
dotnet test
```

### Manual Testing

1. **Generate API Key:**
```bash
curl -X POST "http://localhost:5001/api/v1/auth/create-api-key" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","licenseKey":"SQLMMD-PRO-TEST"}'
```

2. **Test Conversion:**
```bash
curl -X POST "http://localhost:5001/api/v1/conversion/sql-to-mermaid" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_KEY" \
  -d '{"sql":"CREATE TABLE users (id INT);"}'
```

3. **Check Key Info:**
```bash
curl -X GET "http://localhost:5001/api/v1/auth/key-info" \
  -H "X-API-Key: YOUR_KEY"
```

---

## 🚀 Deployment

### Azure App Service

```bash
# Publish
dotnet publish -c Release

# Deploy to Azure
az webapp up --name sqlmermaid-api --resource-group my-rg
```

### Docker

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY bin/Release/net10.0/publish .
EXPOSE 80
ENTRYPOINT ["dotnet", "SqlMermaidApi.dll"]
```

---

## ⚙️ Configuration

### appsettings.json

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    }
  },
  "ApiKeysFilePath": "apikeys.json",
  "AllowedHosts": "*"
}
```

### Environment Variables

- `ASPNETCORE_URLS` - Listening URLs (default: http://localhost:5001)
- `ASPNETCORE_ENVIRONMENT` - Environment (Development/Production)

---

## 🔒 Security Best Practices

1. **HTTPS Only** - Use HTTPS in production
2. **Rate Limiting** - Built-in per-tier rate limits
3. **API Key Rotation** - Regenerate keys periodically
4. **CORS** - Configure allowed origins in production
5. **API Key Storage** - Use secure storage (Azure Key Vault, AWS Secrets Manager)

---

## 📊 Monitoring

### Health Check

```bash
curl http://localhost:5001/health
```

### Metrics to Monitor

- Request count per endpoint
- Average response time
- Error rate
- Rate limit violations
- API key usage by tier

---

## 🤝 Integration Examples

### JavaScript/TypeScript

```typescript
const client = {
  baseUrl: 'http://localhost:5001/api/v1',
  apiKey: 'YOUR_API_KEY',
  
  async sqlToMermaid(sql: string) {
    const response = await fetch(`${this.baseUrl}/conversion/sql-to-mermaid`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': this.apiKey
      },
      body: JSON.stringify({ sql })
    });
    return response.json();
  }
};
```

### Python

```python
import requests

class SqlMermaidClient:
    def __init__(self, api_key):
        self.base_url = 'http://localhost:5001/api/v1'
        self.api_key = api_key
    
    def sql_to_mermaid(self, sql):
        response = requests.post(
            f'{self.base_url}/conversion/sql-to-mermaid',
            headers={'X-API-Key': self.api_key},
            json={'sql': sql}
        )
        return response.json()
```

### C#

```csharp
public class SqlMermaidClient
{
    private readonly HttpClient _client;
    private readonly string _apiKey;
    
    public SqlMermaidClient(string apiKey)
    {
        _apiKey = apiKey;
        _client = new HttpClient
        {
            BaseAddress = new Uri("http://localhost:5001/api/v1")
        };
        _client.DefaultRequestHeaders.Add("X-API-Key", apiKey);
    }
    
    public async Task<ConversionResponse> SqlToMermaidAsync(string sql)
    {
        var response = await _client.PostAsJsonAsync(
            "/conversion/sql-to-mermaid",
            new { sql });
        return await response.Content.ReadFromJsonAsync<ConversionResponse>();
    }
}
```

---

## 📞 Support

- **Email:** support@codemonkey.dedge.no
- **Sales:** sales@codemonkey.dedge.no
- **GitHub:** https://github.com/yourusername/SqlMermaidErdTools

---

**Built with .NET 10 and ❤️ by CodeMonkey by Dedge**

