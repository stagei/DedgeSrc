k:
REM @ECHO OFF
REM get two first letters from the OptPath variable
SET OptPath=%OptPath%
ECHO OptPath: %OptPath%

CD /D %OptPath%\DedgePshApps\AzureDevOpsGitCheckIn
MD %OptPath%\data\AzureDevOpsGitCheckIn > nul 2>&1
MD %OptPath%\data\AzureDevOpsGitCheckIn\log  > nul 2>&1
DEL %OptPath%\data\AzureDevOpsGitCheckIn\log\AzureDevOpsGitCheckIn.* /Q  > nul 2>&1

"C:\Program Files\PowerShell\7\pwsh.exe" -w Hidden "%OptPath%\DedgePshApps\AzureDevOpsGitCheckIn\AzureDevOpsGitCheckIn.ps1"  >> %OptPath%\data\AzureDevOpsGitCheckIn\log\AzureDevOpsGitCheckIn.bat.log 2>&1
REM "C:\Program Files\PowerShell\7\pwsh.exe" "%OptPath%\DedgePshApps\AzureDevOpsGitCheckIn\AzureDevOpsGitCheckIn.ps1"  >> %OptPath%\data\AzureDevOpsGitCheckIn\log\AzureDevOpsGitCheckIn.bat.log 2>&1

