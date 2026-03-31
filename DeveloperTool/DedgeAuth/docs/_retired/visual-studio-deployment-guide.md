# Visual Studio 2026 Deployment Guide for DedgeAuth

This guide explains how to deploy the DedgeAuth application to `t-no1fkxtst.app` directly from Visual Studio 2026 without using the `Build-And-Publish.ps1` script.

## Prerequisites

- Visual Studio 2026 installed
- Access to the network share `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth`
- Appropriate permissions to write to the deployment target
- .NET 10.0 SDK installed

## Deployment Methods

### Method 1: Using Existing FileSystem Publish Profile (Recommended)

The project already includes a `Prod.pubxml` profile configured to publish to the network share. This is the simplest method.

#### Steps:

1. **Open the Solution**
   - Open `DedgeAuth.sln` in Visual Studio 2026

2. **Select the API Project**
   - In Solution Explorer, right-click on `DedgeAuth.Api` project
   - Select **Publish...**

3. **Choose Publish Profile**
   - If you see the publish dialog, click **New** or select **Prod** profile if it exists
   - If the Prod profile is already configured, select it and click **Publish**

4. **Verify Publish Settings**
   - **Target**: Folder
   - **Target location**: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth`
   - **Configuration**: Release
   - **Target Framework**: net10.0
   - **Runtime**: win-x64
   - **Deployment Mode**: Framework-dependent (SelfContained: false)

5. **Publish**
   - Click **Publish** button
   - Visual Studio will build and publish the application to the network share

6. **Verify Deployment**
   - Check that files were copied to `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth`
   - The published application should include:
     - `DedgeAuth.Api.dll`
     - `appsettings.json`
     - `wwwroot/` folder with static files
     - All required dependencies

---

### Method 2: Manual File System Deployment

If you prefer more control over the deployment process:

1. **Build the Solution**
   - In Visual Studio, select **Build** → **Build Solution** (or press `Ctrl+Shift+B`)
   - Ensure build succeeds with **Release** configuration

2. **Publish Using Command Line**
   - Open a terminal in Visual Studio (View → Terminal)
   - Navigate to the API project directory:
     ```powershell
     cd src\DedgeAuth.Api
     ```
   - Run publish command:
     ```powershell
     dotnet publish -c Release -p:PublishProfile=Prod
     ```

3. **Copy Files Manually**
   - Navigate to the publish output folder
   - Copy all files to `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth`

---

## Important Configuration Notes

### Port Configuration

The application is configured to run on port **8100** (see `Program.cs`):
```csharp
builder.WebHost.UseUrls("http://*:8100");
```

Ensure:
- Port 8100 is open on the target server
- Firewall rules allow traffic on port 8100
- No other application is using port 8100

### Database Connection

The application requires a PostgreSQL database. Update `appsettings.json` on the target server:
```json
"ConnectionStrings": {
  "AuthDb": "Host=t-no1fkxtst-db;Database=DedgeAuth;Username=<user>;Password=<password>"
}
```

### Windows Service Support

The application supports running as a Windows Service. To install:

```powershell
sc.exe create DedgeAuth binPath="C:\path\to\DedgeAuth.Api.exe"
sc.exe start DedgeAuth
```

---

## Troubleshooting

### Common Issues

1. **Network Share Access Denied**
   - Verify you have write permissions to `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\DedgeCommon\Software\DedgeWinApps\DedgeAuth`
   - Check network connectivity to the server

2. **Build Errors**
   - Ensure all NuGet packages are restored: **Tools** → **NuGet Package Manager** → **Restore NuGet Packages**
   - Clean solution: **Build** → **Clean Solution**, then rebuild

3. **Runtime Errors**
   - Verify .NET 10.0 runtime is installed on the target server
   - Check application logs for detailed error messages
   - Verify database connection string is correct

4. **Port Already in Use**
   - Stop any existing DedgeAuth processes
   - Change the port in `Program.cs` if needed

---

## Comparison: Visual Studio vs. Build-And-Publish.ps1

| Feature | Visual Studio | Build-And-Publish.ps1 |
|---------|--------------|----------------------|
| Version bumping | Manual (edit .csproj) | Automatic |
| Process stopping | Manual | Automatic |
| Health check | Manual | Automatic |
| Browser opening | Manual | Automatic |
| UI-based configuration | Yes | No |
| Integration with VS | Native | External |

---

## Next Steps After Deployment

1. **Verify Application is Running**
   - Navigate to `http://t-no1fkxtst.app:8100/health` in a browser
   - Should return: `{"Status":"Healthy","Timestamp":"..."}`

2. **Test Login Page**
   - Navigate to `http://t-no1fkxtst.app:8100/login.html`
   - Verify the UI loads correctly

3. **Check Logs**
   - Monitor application logs for any errors
   - Check Windows Event Viewer if running as a service

4. **Configure as Windows Service (Optional)**
   - Install the application as a Windows Service for automatic startup
   - Use the `sc.exe` commands mentioned above

---

## Additional Resources

- [ASP.NET Core Deployment Documentation](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/)
- [Visual Studio Publish Profiles](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/visual-studio-publish-profiles)
- [IIS Deployment Guide](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/iis/)
