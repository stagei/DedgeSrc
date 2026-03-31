@echo off
pwsh.exe -NoProfile -ExecutionPolicy remotesigned -Command "%OptPath%\DedgePshApps\DedgePosLogSearch\DedgePosLogSearch.ps1 %1 %2"