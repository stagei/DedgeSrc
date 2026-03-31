@echo off
REM Kill in-flight regen workers and re-run every analysis listed in analyses.json (see Regenerate-All-Analyses.ps1).
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Regenerate-All-Analyses.ps1" %*
exit /b %ERRORLEVEL%
