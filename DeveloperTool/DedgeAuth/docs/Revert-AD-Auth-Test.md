# Revert AD/Entra Auth Test Changes

All AD/Entra authentication test changes are tagged with:
- C#: `// 20260317 GHS Test Ad/Entra Start -->` / `// <--20260317 GHS Test Ad/Entra End`
- HTML: `<!-- 20260317 GHS Test Ad/Entra Start -->` / `<!-- 20260317 GHS Test Ad/Entra End -->`

## Revert via git (recommended)

```bash
git revert --no-commit 4e0083b..HEAD
git commit -m "Revert AD/Entra auth test changes"
```

## Hard reset (destructive)

```bash
git reset --hard 4e0083b
```

## IIS cleanup

After reverting code, remove the Windows Authentication override on the server:

```powershell
& $env:windir\system32\inetsrv\appcmd.exe set config "Default Web Site/DedgeAuth" `
    /section:system.webServer/security/authentication/windowsAuthentication `
    /enabled:false /commit:apphost
```

Or simply run `IIS-RedeployAll.ps1` which resets all IIS auth config from templates.

## Files affected

| File | Change |
|------|--------|
| `src/DedgeAuth.Api/DedgeAuth.Api.csproj` | Added `Microsoft.AspNetCore.Authentication.Negotiate` |
| `src/DedgeAuth.Api/Program.cs` | Added `.AddNegotiate()` secondary scheme |
| `src/DedgeAuth.Api/Controllers/AuthController.cs` | Added `WindowsLogin` endpoint |
| `src/DedgeAuth.Services/AuthService.cs` | Added `LoginWithWindowsAsync` method |
| `src/DedgeAuth.Api/wwwroot/login.html` | Added Windows Login button + JS |
