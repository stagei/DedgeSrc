@echo off
REM Synopsis Start
REM This script exports DB2 server configuration by running the Db2-ExportServerConfig PowerShell application.
REM It first checks if the application exists, and if not, attempts to install it before running.
REM Synopsis End
set pshApp=Db2-ExportServerConfig
run-psh %pshApp%

