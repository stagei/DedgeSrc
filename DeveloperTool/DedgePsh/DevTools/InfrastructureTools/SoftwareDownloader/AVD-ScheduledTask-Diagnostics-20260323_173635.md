# AVD Scheduled Task Diagnostics Report

- Computer: p-no1avd-vdi024
- User: DEDGE\FKGEISTA
- AVD detected: True
- Planned start time used: 17:41
- Passed cases: 1
- Failed cases: 4

## Attempted cases
- NoCreds_HIGHEST: Success=False, ExitCode=1, DurationMs=78
  - Output: ERROR: Access is denied.
- NoCreds_LIMITED: Success=True, ExitCode=0, DurationMs=51
  - Output: SUCCESS: The scheduled task "\DevTools\AVDProbe_NoCreds_Limited_bd73b5d6" has successfully been created.
- WithCreds_HIGHEST: Success=False, ExitCode=1, DurationMs=55
  - Output: ERROR: Access is denied.
- WithCreds_LIMITED: Success=False, ExitCode=1, DurationMs=936
  - Output: ERROR: The user name or password is incorrect.
- Module_New-ScheduledTask_RunAsUserTrue: Success=False, ExitCode=1, DurationMs=19866
  - Output: schtasks.exe failed with exit code 1

## Official references
- https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create
- https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks
- https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/troubleshooting-task-scheduler-access-denied-error
- https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-desktop/troubleshoot-agent

## Interpretation
- The environment allows task creation without stored credentials but rejects one or more credential-backed registrations (/RU + /RP).
- This matches AVD policy/elevation constraints; use interactive logged-on tasks on AVD.
