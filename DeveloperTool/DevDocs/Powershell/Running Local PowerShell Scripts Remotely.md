# Running Local PowerShell Scripts Remotely

This guide explains how to execute PowerShell scripts that are stored locally on your machine on a remote computer using PowerShell 7.

## Prerequisites

- PowerShell 7 installed on both local and remote machines
- Remote PowerShell enabled on the target computer (`Enable-PSRemoting`)
- Appropriate credentials and permissions
- Network connectivity between machines

## Setup Remote Session

First, establish a PowerShell 7 remote session:

```powershell
$session = New-PSSession -ComputerName $ComputerName -Credential $credentials -ConfigurationName "PowerShell.7"
```

## Methods to Run Local Scripts Remotely

### Method 1: Using Script Content

```powershell
$scriptPath = "C:\LocalPath\YourScript.ps1"
$scriptContent = Get-Content -Path $scriptPath -Raw
Invoke-Command -Session $session -ScriptBlock ([ScriptBlock]::Create($scriptContent))
```

### Method 2: Using FilePath (Recommended)

```powershell
Invoke-Command -Session $session -FilePath "C:\LocalPath\YourScript.ps1"
```

### Passing Parameters to Your Script

If your script accepts parameters, you can pass them using `-ArgumentList`:

```powershell
Invoke-Command -Session $session -FilePath "C:\LocalPath\YourScript.ps1" -ArgumentList $param1, $param2
```

## Important Considerations

1. **Dependencies**: Any modules used in your script must be available on the remote computer
2. **File Paths**: Local file paths in your script need to be modified for the remote context
3. **Variables**: Local variables aren't automatically available in the remote session
4. **Permissions**: The remote computer needs appropriate permissions to access any network resources used in the script

## Cleanup

Always close your remote session when finished:

```powershell
Remove-PSSession $session
```

## Troubleshooting

- Ensure PowerShell remoting is enabled: `Enable-PSRemoting`
- Check network connectivity between machines
- Verify PowerShell 7 is installed on the remote machine
- Confirm you have the necessary permissions
- Check for any module dependencies
```
