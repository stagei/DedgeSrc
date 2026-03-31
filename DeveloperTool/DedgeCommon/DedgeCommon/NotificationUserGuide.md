# Notification User Guide

**Class:** `DedgeCommon.Notification`  
**Version:** 1.5.22  
**Purpose:** Send email and SMS notifications

---

## 🎯 Quick Start

```csharp
using DedgeCommon;

// Send email
Notification.SendHtmlEmail("user@company.com", "Subject", "<p>HTML content</p>");

// Send SMS (PowerShell only - requires Send-Sms function)
```

---

## 📋 Common Usage Patterns

### Pattern 1: HTML Email
```csharp
string to = "admin@company.com";
string subject = "Report Ready";
string htmlBody = "<h1>Report</h1><p>Your report is ready.</p>";

Notification.SendHtmlEmail(to, subject, htmlBody);
```

---

## 📚 Key Members

### Static Methods
- **SendHtmlEmail(to, subject, htmlBody)** - Send HTML email

---

**Last Updated:** 2025-12-16  
**Included in Package:** Yes
