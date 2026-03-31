# Automatic File Signing Setup for Visual Studio 2022

This guide explains how to set up automatic signing for both the main application (.NET) and the installer (Setup Project) in Visual Studio 2022.

## Application Project (.csproj) Setup

1. Open your project's `.csproj` file
2. Add the following properties and post-build event to sign the output file:
   ```xml
   <PropertyGroup>
     <ShouldSign>false</ShouldSign>
     <ShouldSign Condition="'$(Configuration)' == 'Release'">true</ShouldSign>
   </PropertyGroup>

   <!-- Optional: Debug configuration to verify signing status -->
   <Target Name="EchoConfiguration" BeforeTargets="PostBuild">
     <Message Importance="high" Text="Current Configuration: $(Configuration)" />
     <Message Importance="high" Text="Should Sign: $(ShouldSign)" />
   </Target>

   <Target Name="PostBuild" AfterTargets="PostBuildEvent" Condition="'$(ShouldSign)' == 'true'">
     <Message Importance="high" Text="Signing assembly..." />
     <Exec Command="pwsh.exe -ExecutionPolicy Bypass -File &quot;\\path\to\signing\script.ps1&quot; -Path &quot;$(TargetPath)&quot; -Action Add -NoConfirm" />
   </Target>
   ```

This setup ensures that:
- Debug builds skip signing
- Release builds automatically sign
- Build output shows signing status

## Setup Project (.vdproj) Configuration

1. Open your `.vdproj` file in a text editor
2. Locate the "Product" section
3. Add or modify the "PostBuildEvent" property:
   ```
   "PostBuildEvent" = "8:pwsh.exe -ExecutionPolicy Bypass -File \"\\\\path\\to\\signing\\script.ps1\" $(TargetDir) -Action Add -NoConfirm"
   "RunPostBuildEvent" = "3:1"
   ```

## Important Notes

1. The signing script (`DedgeSign.ps1`) should be accessible from the build machine
2. PowerShell execution policy must allow running the signing script
3. Proper permissions are required to access the signing certificate and script
4. The signing process will run automatically after successful Release builds
5. Use quotes around paths that might contain spaces
6. The `-NoConfirm` parameter allows for automated signing without user intervention

## Troubleshooting

1. If signing fails, check:
   - Script path accessibility
   - PowerShell execution policy
   - Certificate availability and permissions
   - Build account permissions
   - Verify you're building in Release configuration

2. Common error messages:
   - "Access denied": Check file and network permissions
   - "Certificate not found": Verify certificate path and availability
   - "PowerShell execution policy": Use `-ExecutionPolicy Bypass`

## Security Considerations

1. Store certificates securely
2. Use environment variables for sensitive paths
3. Implement proper access controls to signing scripts
4. Use timestamp servers for long-term signature validity
5. Regular certificate renewal process

## Example Configuration

### .csproj Example
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <ShouldSign>false</ShouldSign>
    <ShouldSign Condition="'$(Configuration)' == 'Release'">true</ShouldSign>
  </PropertyGroup>

  <Target Name="PostBuild" AfterTargets="PostBuildEvent" Condition="'$(ShouldSign)' == 'true'">
    <Message Importance="high" Text="Signing assembly..." />
    <Exec Command="pwsh.exe -ExecutionPolicy Bypass -File &quot;\\server\path\DedgeSign.ps1&quot; -Path &quot;$(TargetPath)&quot; -Action Add -NoConfirm" />
  </Target>
</Project>
```

### .vdproj Example
```
"PostBuildEvent" = "8:pwsh.exe -ExecutionPolicy Bypass -File \"\\\\server\\path\\DedgeSign.ps1\" $(TargetDir) -Action Add -NoConfirm"
"RunPostBuildEvent" = "3:1"
```
