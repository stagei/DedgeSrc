# WkMonitor User Guide

**Class:** `DedgeCommon.WkMonitor`  
**Version:** 1.5.22  
**Purpose:** Integration with WKMon monitoring system

---

## 🎯 Quick Start

```csharp
using DedgeCommon;

WkMonitor.SendAlert("Database backup completed", WkMonitor.AlertLevel.Info);
```

---

## 📋 Common Usage Patterns

### Pattern 1: Send Alert
```csharp
if (backupSuccess)
{
    WkMonitor.SendAlert("Backup successful", WkMonitor.AlertLevel.Info);
}
else
{
    WkMonitor.SendAlert("Backup failed!", WkMonitor.AlertLevel.Error);
}
```

---

## 📚 Key Members

### Static Methods
- **SendAlert(message, level)** - Send alert to WKMon system

---

**Last Updated:** 2025-12-16  
**Included in Package:** Yes
