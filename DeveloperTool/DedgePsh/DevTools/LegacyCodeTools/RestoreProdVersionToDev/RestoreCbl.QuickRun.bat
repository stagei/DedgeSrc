@echo off
pwsh.exe -NoProfile -ExecutionPolicy remotesigned -Command "K:\fkavd\DedgePshApps\RestoreProdVersionToDev.ps1 -filename %1"

