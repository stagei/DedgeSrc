# AVD Scheduled Task Diagnostics Report

- Computer: p-no1avd-vdi024
- User: DEDGE\FKGEISTA
- AVD detected: True
- Planned start time used: 17:42
- Passed cases: 2
- Failed cases: 3

## Attempted cases
- NoCreds_HIGHEST: Success=False, ExitCode=1, DurationMs=66
  - Output: ERROR: Access is denied.
- NoCreds_LIMITED: Success=True, ExitCode=0, DurationMs=58
  - Output: SUCCESS: The scheduled task "\DevTools\AVDProbe_NoCreds_Limited_204403f1" has successfully been created.
- WithCreds_HIGHEST: Success=False, ExitCode=1, DurationMs=64
  - Output: ERROR: Access is denied.
- WithCreds_LIMITED: Success=False, ExitCode=1, DurationMs=997
  - Output: ERROR: The user name or password is incorrect.
- Module_New-ScheduledTask_RunAsUserTrue: Success=True, ExitCode=0, DurationMs=19072
  - Output: New-ScheduledTask call completed.

## Official references
- https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create
- https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks
- https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/troubleshooting-task-scheduler-access-denied-error
- https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-desktop/troubleshoot-agent

## Interpretation
- The environment allows task creation without stored credentials but rejects one or more credential-backed registrations (/RU + /RP).
- This matches AVD policy/elevation constraints; use interactive logged-on tasks on AVD.

## Validation using SoftwareDownloader _install.ps1
- Ran `DevTools/InfrastructureTools/SoftwareDownloader/_install.ps1` on `p-no1avd-vdi024`.
- Observed module logs:
  - `AVD session host detected - skipping /RL HIGHEST and using default LIMITED run level`
  - `AVD session host detected - skipping /RU and /RP for scheduled task creation (interactive logged-on context)`
  - `Scheduled task DevTools\SoftwareDownloader created successfully`
- Result: Real install path now works on AVD with the AVD-isolated module behavior.
