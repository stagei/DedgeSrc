# RunExternal User Guide

**Class:** `DedgeCommon.RunExternal`  
**Version:** 1.5.22  
**Purpose:** Execute external programs and capture output

---

## 🎯 Quick Start

```csharp
using DedgeCommon;

string output = RunExternal.RunCommand("cmd.exe", "/c dir");
Console.WriteLine(output);
```

---

## 📋 Common Usage Patterns

### Pattern 1: Run Command and Capture Output
```csharp
string result = RunExternal.RunCommand("powershell.exe", "-Command Get-Date");
Console.WriteLine($"Output: {result}");
```

---

## 📚 Key Members

### Static Methods
- **RunCommand(executable, arguments)** - Execute and return output

---

**Last Updated:** 2025-12-16  
**Included in Package:** Yes
