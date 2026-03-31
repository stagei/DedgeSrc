# Grant-LogonRightsToCurrentUser

**Category:** AdminTools | **Time Saved:** ~10 min/run

---

## 🎯 Business Value

**Function:** Grant "Log on as batch job" and "Log on as a service" rights to current user  
**Purpose:** Required for Task Scheduler jobs and Windows Services  
**Value:** Enables scheduled tasks and services running as specific user

### Functionality
Adds both `SeBatchLogonRight` and `SeServiceLogonRight` to current user

**Windows Security Policy:**
- User Rights Assignment → Log on as batch job
- User Rights Assignment → Log on as a service

**Required for:**
- Scheduled tasks running as user
- Windows services running as user
- Service accounts
- SQL Server service accounts
- IIS Application Pool identities
- Batch jobs

### Time Saved
- **Automation:** Enables user-context scheduled tasks and services
- **Time saved:** Manual policy configuration → automated
- **Time Saved per execution:** ~10 minutes (manual work eliminated)

---

## 📋 Usage

```powershell
# Run as Administrator
.\Grant-LogonRightsToCurrentUser.ps1
```

Or via deployment:
```powershell
.\_install.ps1
```

---

**Status:** ✅ Active  
**Critical for:** Scheduled task setup and Windows service configuration  
**Author:** Geir Helge Starholm, www.dEdge.no
