# Azure-DevOpsCloneRepositories

**Category:** GitTools | **Time Saved:** ~5 min/run

---

## 🎯 Business Value

**Function:** Clone all repositories from Azure DevOps  
**Purpose:** Bulk repository cloning  
**Value:** Fast workspace setup

### Functionality
- Authenticates to Azure DevOps
- Lists all accessible repositories
- Clones in paralll
- Organizes by project
- Reports results

### Usage
- Default (no arguments): interactive mode
- Non-interactive clone all: set `CloneAll` to `true`
- Optional destination root: set `TargetPath` to the folder where repositories should be cloned

```powershell
# Interactive (existing default behavior)
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\CodingTools\Azure-DevOpsCloneRepositories\Azure-DevOpsCloneRepositories.ps1"

# Non-interactive clone all to default path ($env:OptPath\src)
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\CodingTools\Azure-DevOpsCloneRepositories\Azure-DevOpsCloneRepositories.ps1" -CloneAll:$true

# Non-interactive clone all to a custom destination path
pwsh.exe -NoProfile -File "C:\opt\src\DedgePsh\DevTools\CodingTools\Azure-DevOpsCloneRepositories\Azure-DevOpsCloneRepositories.ps1" -CloneAll:$true -TargetPath "C:\opt\src"
```

**Use case:** New developer onboarding

### Time Saved
- **Time:** 2-3 hours manual → 15 min automated
- **Onboarding:** ~30 developers/year
- **Time Saved per execution:** ~5 minutes (manual work eliminated)

---

**Status:** ✅ Active

