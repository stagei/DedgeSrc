# Role-Based Access Control & Bug Tracking Process - Implementation Guide

**Date:** November 19, 2025  
**Status:** ✅ DOCUMENTED (Not yet implemented)

---

## ✅ WHAT WAS UPDATED

### 1. `.cursorrules` - Enhanced with Security & Verification Requirements

**New Sections Added:**

#### A) Security & Access Control (NEW - Lines ~620-760)
- Complete RBAC specification
- Three access levels: DBA, Middle, Low
- SYSCAT.DBAUTH query requirements
- Username parsing rules (remove domain)
- Menu item tagging requirements
- Permission validation requirements
- Access level UI indicators

#### B) Pre-Implementation Verification Process (NEW)
- Mandatory search before creating new code
- Commands to use (grep, glob_file_search, list_dir)
- Decision tree (exists vs. doesn't exist)
- Example verification commands

#### C) Bug Tracking Process (NEW)
- When bugs are reported: Add to end of TASKLIST.md
- Do NOT implement immediately
- Wait for all preceding features verified
- Only implement when instructed

#### D) Updated Prohibited Patterns
- Added: ❌ Create duplicate functionality without checking if it already exists

#### E) Updated Questions to Ask Before Implementing
- Made verification FIRST and CRITICAL question
- Added access level questions

#### F) Updated Development Workflow
- Added verification step before implementation
- Added TASKLIST.md update requirements

---

### 2. `TASKLIST.md` - Complete Feature Checklist Created

**Structure:**
- All 19 features from NEXTSTEPS.md
- 275 total subtasks with checkboxes
- Each feature has detailed subtasks
- Current completion status: 152/275 (55%)
- Service layer: 100% ✅
- UI components: 22% ❌

**Bug Section at End:**
- 🐛 BUG #1: Role-Based Access Control (HIGH - Security)
  - 22 subtasks detailed
  - NOT STARTED - waiting for verification
  
- 🐛 BUG #2: TableDetailsDialog Enhancement (MEDIUM)
  - 22 subtasks detailed
  - NOT STARTED - waiting for verification

---

### 3. `NEXTSTEPS.md` - Added Feature #20 (RBAC)

**New Section:** Feature #20: Role-Based Access Control
- Complete specification
- SQL queries for DBAUTH
- Access level definitions
- Permission matrices
- Implementation steps
- Testing criteria
- Feature categorization (DBA/Middle/Low)

---

### 4. Memory & Verification Process

**Updated AI Memory:**
- Always verify existing functionality first
- Bug tracking workflow documented
- RBAC requirements noted

**New Document:** `VERIFICATION_PROCESS.md`
- Complete verification workflow
- Bug tracking process
- Decision trees
- Examples

---

## 🔐 ROLE-BASED ACCESS CONTROL (RBAC) SPECIFICATION

### Access Level Determination

**SQL Query:**
```sql
SELECT * FROM SYSCAT.DBAUTH 
WHERE GRANTEE = '<username_without_domain>'
```

**Username Parsing:**
- "DOMAIN\username" → "username"
- "username@domain.com" → "username"  
- "username" → "username"

**Classification Logic:**
```
Query DBAUTH for user
│
├─ No rows found
│  └─ LOW Level (Read-Only)
│     └─ SELECT only, no modifications
│
├─ Row found, DBADMAUTH = 'Y'
│  └─ DBA Level (Full Access)
│     └─ All operations allowed
│
└─ Row found, DBADMAUTH ≠ 'Y'
   └─ MIDDLE Level (Standard User)
      └─ DML allowed, DDL blocked
```

### Permission Matrix

| Operation | DBA | Middle | Low |
|-----------|-----|--------|-----|
| SELECT | ✅ | ✅ | ✅ |
| INSERT/UPDATE/DELETE | ✅ | ✅ | ❌ |
| CREATE/DROP/ALTER | ✅ | ❌ | ❌ |
| Force Disconnect | ✅ | ❌ | ❌ |
| Execute RUNSTATS | ✅ | ❌ | ❌ |
| Modify CDC | ✅ | ❌ | ❌ |
| View Monitoring | ✅ | ✅ (read-only) | ✅ (read-only) |
| Export Data | ✅ | ✅ | ✅ (SELECT only) |
| Generate DDL | ✅ | ✅ (no execute) | ✅ (no execute) |

### Menu Item Tagging

**DBA Only Features:**
```xml
<MenuItem Header="Lock Monitor" Tag="AccessLevel:DBA"/>
<MenuItem Header="Force Disconnect Sessions" Tag="AccessLevel:DBA"/>
<MenuItem Header="Execute RUNSTATS" Tag="AccessLevel:DBA"/>
<MenuItem Header="Enable/Disable CDC" Tag="AccessLevel:DBA"/>
<MenuItem Header="Drop Unused Objects" Tag="AccessLevel:DBA"/>
<MenuItem Header="Execute Migration" Tag="AccessLevel:DBA"/>
```

**Middle Level Features:**
```xml
<MenuItem Header="Database Load Monitor" Tag="AccessLevel:Middle"/>
<MenuItem Header="Statistics Manager" Tag="AccessLevel:Middle"/>
<MenuItem Header="Source Code Browser" Tag="AccessLevel:Middle"/>
<MenuItem Header="Dependency Analyzer" Tag="AccessLevel:Middle"/>
<MenuItem Header="Comment Manager" Tag="AccessLevel:Middle"/>
```

**Low Level Features:**
```xml
<MenuItem Header="Table Properties" Tag="AccessLevel:Low"/>
<MenuItem Header="Execute Query (SELECT)" Tag="AccessLevel:Low"/>
<MenuItem Header="Export Results" Tag="AccessLevel:Low"/>
<MenuItem Header="View Metadata" Tag="AccessLevel:Low"/>
```

### UI Indicators

**Access Level Badge:**
- 🛡️ DBA (Green background)
- 👤 USER (Orange background)
- 🔒 READ-ONLY (Red background)

**Placement:** Status bar or toolbar in MainWindow

---

## 🐛 BUG TRACKING WORKFLOW

### When You Report a Bug:

**Step 1: I Add to TASKLIST.md**
```markdown
### 🐛 BUG #X: Bug Title

**Reported:** Date
**Priority:** HIGH/MEDIUM/LOW
**Status:** ❌ NOT STARTED (Pending verification of all preceding features)

**Problem:** Clear description

#### BUGX-1: Subtask Category
- [ ] Specific task
- [ ] Another task
...
```

**Step 2: I Do NOT Implement**
- Bug is documented
- All tasks unchecked
- Status: NOT STARTED
- Waiting for your instruction

**Step 3: When You Say "Implement Bug #X"**
- I verify all preceding tasks complete
- Change status to "IN PROGRESS"
- Implement all subtasks
- Check off boxes as completed
- Change status to "✅ COMPLETE"

---

## 📋 CURRENT BUG LIST

### 🐛 BUG #1: Role-Based Access Control (RBAC)
- **Priority:** HIGH (Security Critical)
- **Status:** ❌ NOT STARTED
- **Subtasks:** 22
- **Implementation Time:** 4-6 hours
- **Impact:** All features affected

**What It Does:**
- Queries SYSCAT.DBAUTH to determine user privileges
- Assigns DBA/Middle/Low access level
- Shows/hides menu items based on level
- Validates permissions before operations
- Displays access level badge in UI

### 🐛 BUG #2: TableDetailsDialog Enhancement
- **Priority:** MEDIUM
- **Status:** ❌ NOT STARTED
- **Subtasks:** 22
- **Implementation Time:** 2-3 hours
- **Impact:** TableDetailsDialog only

**What It Does:**
- Shows incoming foreign keys
- Shows packages that use table
- Shows views that use table
- Shows procedures/functions that use table
- Adds tabbed interface to organize info

---

## 🎯 IMPLEMENTATION PRIORITIES

### Immediate (When Instructed):
1. **BUG #1: RBAC** - Security is critical, should be implemented before UI panels
2. **BUG #2: TableDetails** - Enhancement to existing dialog

### After Bugs Fixed:
3. Create remaining UI panels for Features #6-#18
4. Add snapshot interval UI to Feature #19
5. Add commit/rollback toolbar buttons

---

## 📊 UPDATED TOTALS

### Features in TASKLIST.md: 19
- Fully complete: 5
- Service layer complete: 14
- Total tasks: 275
- Completed tasks: 152 (55%)
- Pending UI: 123 tasks

### Bugs in TASKLIST.md: 2
- BUG #1: RBAC (22 tasks)
- BUG #2: TableDetails (22 tasks)
- Total bug tasks: 44
- Completed: 0
- **Grand total tasks:** 319 (275 features + 44 bugs)

---

## ✅ FILES UPDATED

1. **`.cursorrules`** 
   - Added Security & Access Control section
   - Added Pre-Implementation Verification Process
   - Added Bug Tracking Process
   - Updated AI Assistant Instructions
   - Updated Questions to Ask Before Implementing
   - Updated Development Workflow
   - Updated Prohibited Patterns

2. **`TASKLIST.md`**
   - Created complete task list for all 19 features
   - Added BUG #1: RBAC (at end)
   - Added BUG #2: TableDetails (at end)
   - Added bug reporting process documentation
   - Added summary statistics

3. **`NEXTSTEPS.md`**
   - Added Feature #20: Role-Based Access Control
   - Complete RBAC specification
   - Access level definitions
   - Permission matrices
   - Testing criteria

4. **`VERIFICATION_PROCESS.md`**
   - Created new documentation file
   - Verification workflow
   - Bug tracking workflow
   - Examples and decision trees

---

## 🎊 SUMMARY FOR USER

I've completed your requests:

### ✅ Pre-Implementation Verification
**Added to `.cursorrules`:**
- Mandatory search for existing functionality before creating new code
- Use grep/glob_file_search to check Services/, Models/, Controls/
- Only create new code if it doesn't exist
- Update TASKLIST.md if already exists

### ✅ Bug Tracking Process  
**Added to `.cursorrules` and `TASKLIST.md`:**
- When you report bugs → I add to end of TASKLIST.md
- All tasks marked unchecked
- Status: NOT STARTED
- **I will NOT implement until you instruct**
- All preceding features must be verified first

### ✅ Role-Based Access Control (RBAC)
**Added as BUG #1 in TASKLIST.md (HIGH PRIORITY):**
- Query SYSCAT.DBAUTH to determine user level
- Three access levels: DBA, Middle, Low
- Menu items tagged with required level
- Show/hide based on user permissions
- Access level badge in UI
- Complete specification in NEXTSTEPS.md Feature #20

**Access Levels:**
- **DBA:** Full access (DBADMAUTH = 'Y')
- **Middle:** DML only (in DBAUTH, not DBA)
- **Low:** Read-only (not in DBAUTH)

### ✅ TableDetailsDialog Enhancement
**Added as BUG #2 in TASKLIST.md (MEDIUM PRIORITY):**
- Show incoming foreign keys
- Show packages that use table
- Show views that use table
- Show procedures/functions that use table

---

## 🔒 IMPORTANT NOTES

**Going Forward:**

1. **Before I implement anything new:**
   - I'll search for existing code
   - I'll check TASKLIST.md
   - I'll verify it doesn't already exist

2. **When you report bugs:**
   - I'll add them to end of TASKLIST.md
   - I'll mark them NOT STARTED
   - I'll wait for your instruction

3. **When you say "Implement BUG #X":**
   - I'll verify all preceding features complete
   - I'll implement all subtasks
   - I'll update checkboxes as I go
   - I'll mark complete when done

4. **RBAC is now documented as critical:**
   - All new features must respect access levels
   - All menu items must be tagged
   - All operations must validate permissions

---

**Build Status:** ✅ SUCCESS  
**Application Status:** ✅ RUNNING  
**Documentation Status:** ✅ COMPLETE

**Ready for next phase when you instruct!**

