@echo off
pwsh.exe -NoProfile -ExecutionPolicy remotesigned -Command "K:\fkavd\DedgePshApps\CursorReleaseContextGenerator.ps1 %1 %2 -FindGitReposRecursive -CurrentUserOnly"

