@echo off
title AutoDocJson Distributed Worker
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-DistributedWorker.ps1"
if errorlevel 1 pause
