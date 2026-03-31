---
name: new-repo
description: >-
  Create a new Azure DevOps repo and push an existing local project.
  Use when the user types /newrepo, wants to create a new repo, or needs
  to publish a local project to Azure DevOps.
---

# New Azure DevOps Repo

Create an Azure DevOps repo initialized with README.md, then push an existing local project.

## Workflow

When triggered with `/newrepo` or `/newrepo <RepoName>`:

1. **Determine RepoName**: use provided name, or derive from current workspace folder name.

2. **Create empty repo** on Azure DevOps:
   ```powershell
   pwsh.exe -NoProfile -File "$env:OptPath\DedgePshApps\New-EmptyAzDevOpsRepo\New-EmptyAzDevOpsRepo.ps1" -RepoName "<RepoName>" -SkipClone
   ```

3. **Push the current project** (the user's workspace folder):
   ```powershell
   git init
   git remote add origin "https://dev.azure.com/Dedge/Dedge/_git/<RepoName>"
   git pull origin main --allow-unrelated-histories
   git add -A
   git commit -m "Initial commit - <RepoName>"
   git push -u origin main
   ```

4. **Confirm** with the repo URL.

## Parameters

The underlying script accepts:

| Parameter | Default | Description |
|---|---|---|
| `-RepoName` | (mandatory) | Repository name |
| `-Organization` | `Dedge` | Azure DevOps org |
| `-Project` | `Dedge` | Azure DevOps project |
| `-CloneTo` | `$env:OptPath\Src\<RepoName>` | Clone path (not used when pushing existing project) |
| `-SkipClone` | — | Skip local clone (use when pushing existing project) |
| `-SkipPush` | — | Create repo only, no commit/push |

## If user specifies a different project path

Use that path instead of the current workspace:
```powershell
pwsh.exe -NoProfile -File "$env:OptPath\DedgePshApps\New-EmptyAzDevOpsRepo\New-EmptyAzDevOpsRepo.ps1" -RepoName "<RepoName>" -SkipClone
cd "<ProjectPath>"
git init
git remote add origin "https://dev.azure.com/Dedge/Dedge/_git/<RepoName>"
git pull origin main --allow-unrelated-histories
git add -A
git commit -m "Initial commit - <RepoName>"
git push -u origin main
```

## Prerequisites

- Azure CLI (`az`) with DevOps extension
- Git in PATH
- Valid Azure DevOps PAT (run `Setup-AzureDevOpsPAT.ps1` if missing)

## Script location

- Source: `C:\opt\src\DedgePsh\DevTools\CodingTools\New-EmptyAzDevOpsRepo\`
- Deployed: `$env:OptPath\DedgePshApps\New-EmptyAzDevOpsRepo\`
