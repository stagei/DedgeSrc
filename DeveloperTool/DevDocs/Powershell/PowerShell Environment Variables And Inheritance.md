# PowerShell Environment Variables Guide

This document explains how environment variables work in PowerShell, including their scope, inheritance, and best practices.

## Environment Variable Basics

Environment variables in Windows are name-value pairs that can affect the behavior of processes running on the system. PowerShell provides several ways to work with these variables.

### Types of Environment Variables

In Windows, environment variables exist at three levels:

1. **System (Machine)**: Apply to all users on the computer
2. **User**: Apply to the current user only
3. **Process**: Apply only to the current process (temporary)

## Working with Environment Variables in PowerShell

### Accessing Environment Variables

PowerShell provides the `env:` drive to access environment variables:

```powershell
# List all environment variables
Get-ChildItem env:

# Access a specific variable
$env:PATH
$env:COMPUTERNAME
```

### Modifying Environment Variables

#### Temporary Changes (Process Level)

```powershell
# Create or modify a variable for the current session only
$env:MY_VARIABLE = "Hello World"

# Append to PATH
$env:PATH = "C:\MyApp;$env:PATH"

# Remove a variable
$env:MY_VARIABLE = $null
# Or
Remove-Item Env:\MY_VARIABLE
```

#### Persistent Changes

```powershell
# Set a User environment variable (persists across sessions)
[System.Environment]::SetEnvironmentVariable("MY_VARIABLE", "Hello World", [System.EnvironmentVariableTarget]::User)

# Set a System environment variable (requires admin privileges)
[System.Environment]::SetEnvironmentVariable("MY_VARIABLE", "Hello World", [System.EnvironmentVariableTarget]::Machine)

# Remove a persistent variable
[System.Environment]::SetEnvironmentVariable("MY_VARIABLE", $null, [System.EnvironmentVariableTarget]::User)
```

## Environment Variable Inheritance

### Process Hierarchy and Inheritance

Environment variables follow a parent-child inheritance model:

1. When a process starts, it inherits a copy of its parent's environment variables
2. Changes made by a process affect only that process and its children
3. Changes don't propagate back to parent processes

### PowerShell and CMD Interaction

#### PowerShell → CMD

When PowerShell launches CMD:

```powershell
# Set a variable in PowerShell
$env:TEST_VAR = "From PowerShell"

# Launch CMD and echo the variable
Start-Process cmd -ArgumentList "/c echo %TEST_VAR% && pause"
```

CMD will see the variable because it inherits from its PowerShell parent.

#### CMD → PowerShell

When CMD launches PowerShell:

```batch
@REM In CMD
SET TEST_VAR=From CMD

@REM Launch PowerShell
pwsh -Command "Write-Host $env:TEST_VAR"
```

PowerShell will see the variable because it inherits from its CMD parent.

## Important Considerations

### Synchronization Issues

When using `SetEnvironmentVariable`, be aware:

1. Changes to persistent variables don't automatically update the current session
2. You need to update both for immediate effect:

```powershell
# Update both session and persistent variable
$env:PATH = "C:\MyApp;$env:PATH"
[System.Environment]::SetEnvironmentVariable("PATH", $env:PATH, [System.EnvironmentVariableTarget]::User)
```

### Variable Precedence

When resolving environment variables, Windows uses this precedence:
1. Process-level variables
2. User-level variables
3. System-level variables

This means your session's temporary variables override persistent ones.

## Best Practices

1. **Use temporary variables** for session-specific settings
2. **Use persistent variables** only when necessary
3. **Be cautious with PATH modifications** to avoid breaking system functionality
4. **Document environment dependencies** in your scripts
5. **Consider using PowerShell profiles** for session setup instead of persistent variables
6. **Use descriptive variable names** with appropriate prefixes to avoid conflicts

## Common Scenarios

### Setting Up Development Environments

```powershell
# Create a function in your profile to set up a dev environment
function Set-JavaEnvironment {
    $env:JAVA_HOME = "C:\Program Files\Java\jdk-17"
    $env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
    Write-Host "Java environment configured" -ForegroundColor Green
}
```

### Running Applications with Custom Environments

```powershell
# Run an application with a custom environment
$env:LOG_LEVEL = "DEBUG"
try {
    .\myapplication.exe
}
finally {
    # Clean up when done
    $env:LOG_LEVEL = $null
}
```

## Troubleshooting

1. **Variable not visible in new PowerShell window**: Persistent change may not have been made
2. **Variable not visible to application**: Check if it's running as a different user or with elevation
3. **Changes not persisting**: Verify you're using `SetEnvironmentVariable` correctly
4. **PATH changes not taking effect**: Some applications cache the PATH at startup

