# AddFkUserAsLocalAdmin

**Category:** AdminTools  
**Complexity:** 🟢 Low  
**Time Saved:** ~30 min/run

---

## 🎯 Business Value

**Function:** Add current user to local Administrators group  
**Value:** Quick admin rights for developers/admins

### Functionality
```powershell
# Finds local admin group (English/Norwegian)
$adminGroupNames = @("Administrators", "Administratorer")

# Adds current user
$currentUser = "$env:USERDOMAIN\$env:USERNAME"
$adminGroup.Add("WinNT://$currentUser")
```

**Auto-detects:** English or Norwegian Windows

### Time Saved
- **Time saved:** 10 min per setup → instant
- **Self-service:** Users can add themselves
- **Time Saved per execution:** ~30 minutes (manual work eliminated)

---

**Status:** ✅ Active  
**Use case:** Developer workstation setup

