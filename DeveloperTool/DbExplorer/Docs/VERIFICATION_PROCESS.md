# Pre-Implementation Verification Process

**Added to .cursorrules:** November 19, 2025

---

## 🔍 MANDATORY VERIFICATION BEFORE ANY IMPLEMENTATION

### Step 1: Check if Functionality Already Exists

**Before creating ANY new file, class, or feature:**

```bash
# Search for existing service
grep -r "ServiceName" Services/

# Find existing model
grep -r "ModelName" Models/

# Find existing UI component
glob_file_search "*ComponentName*.xaml" Controls/

# List all services
list_dir Services/

# Check TASKLIST.md for completion status
grep "Feature #X" TASKLIST.md
```

### Step 2: Decision Tree

```
Is the functionality already implemented?
│
├─ YES → DO NOT create duplicate
│   ├─ Update TASKLIST.md to mark as complete
│   ├─ Enhance existing code if needed
│   └─ Move to next task
│
└─ NO → Proceed with implementation
    ├─ Create new files in correct folders
    ├─ Follow all naming conventions
    ├─ Add comprehensive logging
    ├─ Update TASKLIST.md when done
    └─ Build and test
```

---

## 🐛 BUG TRACKING PROCESS

### When User Reports a Bug:

**DO:**
1. ✅ Add bug to "🐛 BUGS & ISSUES" section at END of TASKLIST.md
2. ✅ Create detailed subtasks with checkboxes `- [ ]`
3. ✅ Mark as "❌ NOT STARTED"
4. ✅ Add note: "Pending verification of all preceding features"
5. ✅ Document the problem clearly
6. ✅ Outline implementation steps
7. ✅ Estimate effort and priority

**DO NOT:**
- ❌ Implement the bug fix immediately
- ❌ Start working on it without user instruction
- ❌ Interrupt current feature implementation
- ❌ Skip verification of existing functionality

**WHEN TO IMPLEMENT:**
- Wait for user to say: "Fix BUG #X" or "Implement all bugs"
- Only after all preceding features are verified complete
- Follow normal development workflow once started

---

## 📋 UPDATED .CURSORRULES SECTIONS

### 1. Prohibited Patterns (Added)
```
- ❌ Create duplicate functionality without checking if it already exists
```

### 2. Pre-Implementation Verification Process (NEW SECTION)
Complete checklist for verifying existing code before creating new implementations.

### 3. Questions to Ask Before Implementing (Updated)
```
1. CRITICAL: Have I verified this functionality doesn't already exist?
   (Now the FIRST question, marked as CRITICAL)
```

### 4. Development Workflow (Updated)
```
Step 2: VERIFY functionality doesn't already exist
Step 3: If exists: Update TASKLIST.md, enhance if needed
Step 4: If doesn't exist: Proceed with implementation
```

### 5. Bug Tracking Process (NEW SECTION)
Complete workflow for handling bug reports during development.

---

## 🎯 WHY THIS MATTERS

### Prevents:
- ❌ Duplicate code
- ❌ Wasted effort reimplementing existing features
- ❌ Inconsistent implementations
- ❌ Merge conflicts
- ❌ Code bloat

### Ensures:
- ✅ Single source of truth for each feature
- ✅ Consistent code quality
- ✅ Accurate progress tracking
- ✅ No duplicate services/models
- ✅ Clean codebase

---

## 📖 EXAMPLE: How to Verify Before Implementing

### Scenario: Asked to implement "Lock Monitor Service"

**Step 1: Search for existing code**
```bash
grep -r "LockMonitor" Services/
# Result: Services/LockMonitorService.cs found!
```

**Step 2: Check TASKLIST.md**
```bash
grep "Lock Monitor" TASKLIST.md
# Result: Feature #8 shows Service Layer COMPLETE
```

**Step 3: Decision**
```
Functionality EXISTS → DO NOT recreate
Action: Update TASKLIST.md if not marked, enhance if needed
```

### Scenario: Asked to implement "Performance Analyzer"

**Step 1: Search**
```bash
grep -r "Performance" Services/
# Result: No matches
```

**Step 2: Check TASKLIST.md**
```bash
grep "Performance" TASKLIST.md
# Result: Not found
```

**Step 3: Decision**
```
Functionality DOES NOT exist → Proceed with implementation
Action: Create new service, add to TASKLIST.md
```

---

## 🐛 EXAMPLE: Bug Reporting Workflow

### User Reports: "TableDetailsDialog only shows DDL"

**Step 1: Add to TASKLIST.md**
```markdown
## 🐛 BUGS & ISSUES

### 🐛 BUG #1: TableDetailsDialog Enhancement
**Reported:** November 19, 2025
**Status:** ❌ NOT STARTED (Pending verification of all preceding features)

#### BUG-1.1: Create Service
- [ ] Create Services/TableRelationshipService.cs
- [ ] Implement GetIncomingForeignKeysAsync()
...etc
```

**Step 2: Do NOT implement yet**
- Wait for user instruction
- Continue with current task
- Add to bug backlog

**Step 3: When user says "Fix bug #1"**
- Verify all preceding features complete
- Change status to "IN PROGRESS"
- Implement all subtasks
- Update checkboxes as completed
- Change status to "✅ COMPLETE"

---

## ✅ CURRENT STATUS

**Updates Applied:**
- ✅ .cursorrules updated with verification process
- ✅ Memory updated with new workflow
- ✅ TASKLIST.md has bug tracking section
- ✅ BUG #1 (TableDetailsDialog) added to end of TASKLIST.md
- ✅ BUG #1 marked as NOT STARTED

**Next Actions:**
- ⏸️ BUG #1 will wait until all preceding features are verified
- ⏸️ User will instruct when to implement bugs
- ✅ Verification process now mandatory before any new implementation

---

**Process Owner:** AI Assistant (Claude Sonnet 4.5)  
**Documented:** November 19, 2025  
**Status:** Active and enforced

