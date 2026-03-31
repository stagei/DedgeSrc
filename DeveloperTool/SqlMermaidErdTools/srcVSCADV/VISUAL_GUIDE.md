# Visual Guide - SQL ↔ Mermaid Split Editor

## 📐 Interface Layout

### Main Components

```
┌────────────────────────────────────────────────────────────────────────┐
│                         TOOLBAR (42px)                                 │
│  ⇄ Mode Toggle | Dialect Selector | 👁 Preview | ▶ Convert | 💾 Save  │
├─────────────────────────┬──────────────────────────────────────────────┤
│                         │                                              │
│   LEFT PANEL            │   RIGHT PANEL                                │
│   ────────────          │   ─────────────                              │
│                         │                                              │
│   PANEL HEADER (40px)   │   PANEL HEADER (40px)                        │
│   "SQL Input"           │   "Mermaid Output"                           │
│   + Line count          │   + Copy/Export buttons                      │
│                         │                                              │
│   ┌─────────────────┐   │   ┌────────────────────────┐                 │
│   │                 │   │   │  LIVE PREVIEW          │                 │
│   │  CODE EDITOR    │   │   │  (Mermaid Diagram)     │                 │
│   │  (SQL/Mermaid)  │   │   │                        │                 │
│   │                 │   │   │  Toggleable (50% max)  │                 │
│   │  Editable       │   │   └────────────────────────┘                 │
│   │  Auto-saves     │   │                                              │
│   │  Syntax aware   │   │   ┌────────────────────────┐                 │
│   │                 │   │   │  OUTPUT EDITOR         │                 │
│   │                 │   │   │  (Converted Code)      │                 │
│   │                 │   │   │                        │                 │
│   │                 │   │   │  Read-only             │                 │
│   │                 │   │   │  Copyable              │                 │
│   │                 │   │   │                        │                 │
│   └─────────────────┘   │   └────────────────────────┘                 │
│                         │                                              │
│                         │   [ERROR CONTAINER]                          │
│                         │   (Shown only when error occurs)             │
├─────────────────────────┴──────────────────────────────────────────────┤
│                      STATUS BAR (24px)                                 │
│  "Ready" | "Converting..." | "Converted in 45ms"       [45ms]         │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🎨 Mode 1: SQL → Mermaid

### Interface State

```
┌────────────────────────────────────────────────────────────────────────┐
│ ⇄ SQL → Mermaid  ┊  👁 Preview ✓  ┊  ▶ Convert  ┊  💾 Save           │
├─────────────────────────┬──────────────────────────────────────────────┤
│ SQL INPUT               │ MERMAID OUTPUT                               │
│ 25 lines                │ 📋 📄                                         │
├─────────────────────────┼──────────────────────────────────────────────┤
│                         │ ╔═══════════════════════════════════╗        │
│ CREATE TABLE customers  │ ║   LIVE PREVIEW (Mermaid Diagram)  ║        │
│ (                       │ ║                                   ║        │
│   id INT PRIMARY KEY,   │ ║   ┌─────────────┐                ║        │
│   name VARCHAR(100),    │ ║   │ customers   │                ║        │
│   email VARCHAR(255)    │ ║   │ ─────────   │                ║        │
│     UNIQUE              │ ║   │ • id PK     │                ║        │
│ );                      │ ║   │ • name      │                ║        │
│                         │ ║   │ • email UK  │                ║        │
│ CREATE TABLE orders (   │ ║   └─────┬───────┘                ║        │
│   id INT PRIMARY KEY,   │ ║         │ 1:N                    ║        │
│   customer_id INT,      │ ║         │                        ║        │
│   order_date DATE,      │ ║   ┌─────▼───────┐                ║        │
│   FOREIGN KEY (...)     │ ║   │   orders    │                ║        │
│ );                      │ ║   │ ─────────   │                ║        │
│                         │ ║   │ • id PK     │                ║        │
│                         │ ║   │ • cust_id   │                ║        │
│                         │ ║   │ • date      │                ║        │
│                         │ ║   └─────────────┘                ║        │
│                         │ ╚═══════════════════════════════════╝        │
│                         ├──────────────────────────────────────────────┤
│                         │ erDiagram                                    │
│                         │     customers ||--o{ orders : "customer_id"  │
│                         │                                              │
│                         │     customers {                              │
│                         │         int id PK                            │
│                         │         varchar name                         │
│                         │         varchar email UK                     │
│                         │     }                                        │
│                         │                                              │
│                         │     orders {                                 │
│                         │         int id PK                            │
│                         │         int customer_id FK                   │
│                         │         date order_date                      │
│                         │     }                                        │
├─────────────────────────┴──────────────────────────────────────────────┤
│ Converted in 52ms                                           52ms       │
└────────────────────────────────────────────────────────────────────────┘
```

**Key Features in This Mode:**
- ✅ Live diagram preview in top-right
- ✅ Mermaid code output in bottom-right
- ✅ No dialect selector (not needed)
- ✅ Preview toggle button active

---

## 🎨 Mode 2: Mermaid → SQL

### Interface State

```
┌────────────────────────────────────────────────────────────────────────┐
│ ⇄ Mermaid → SQL  ┊  [PostgreSQL ▼]  ┊  ▶ Convert  ┊  💾 Save         │
├─────────────────────────┬──────────────────────────────────────────────┤
│ MERMAID INPUT           │ SQL OUTPUT (PostgreSQL)                      │
│ 18 lines                │ 📋 📄                                         │
├─────────────────────────┼──────────────────────────────────────────────┤
│                         │                                              │
│ erDiagram               │ -- Generated SQL for PostgreSQL              │
│     users {             │ -- Dialect: PostgreSQL                       │
│         int id PK       │                                              │
│         varchar username│ CREATE TABLE users (                         │
│         varchar email   │     id INT PRIMARY KEY,                      │
│     }                   │     username VARCHAR UNIQUE,                 │
│                         │     email VARCHAR                            │
│     posts {             │ );                                           │
│         int id PK       │                                              │
│         int user_id FK  │ CREATE TABLE posts (                         │
│         varchar title   │     id INT PRIMARY KEY,                      │
│         text content    │     user_id INT,                             │
│     }                   │     title VARCHAR,                           │
│                         │     content TEXT,                            │
│     users ||--o{ posts  │     FOREIGN KEY (user_id)                    │
│                         │         REFERENCES users(id)                 │
│                         │ );                                           │
│                         │                                              │
│                         │                                              │
│                         │                                              │
│                         │                                              │
│                         │                                              │
│                         │                                              │
├─────────────────────────┴──────────────────────────────────────────────┤
│ Converted in 38ms                                           38ms       │
└────────────────────────────────────────────────────────────────────────┘
```

**Key Features in This Mode:**
- ✅ SQL dialect selector visible
- ✅ No preview panel (Mermaid input, not output)
- ✅ Full-height SQL output on right
- ✅ Mode indicator shows "Mermaid → SQL"

---

## 🎛️ Toolbar Components

### Mode Toggle Button
```
┌──────────────────────┐
│ ⇄  SQL → Mermaid     │  ← Click to switch modes
└──────────────────────┘

After click:
┌──────────────────────┐
│ ⇄  Mermaid → SQL     │  ← Now in opposite mode
└──────────────────────┘
```

### Dialect Selector (Mermaid → SQL mode only)
```
┌─────────────────┐
│ AnsiSql      ▼ │
├─────────────────┤
│ AnsiSql         │
│ SqlServer       │  ← Choose target SQL dialect
│ PostgreSql      │
│ MySql           │
└─────────────────┘
```

### Preview Toggle (SQL → Mermaid mode only)
```
┌──────────────┐
│ 👁 Preview  │  ← Active (preview shown)
└──────────────┘

After click:
┌──────────────┐
│ 👁 Preview  │  ← Inactive (preview hidden)
└──────────────┘
```

### Action Buttons
```
┌─────────┐  ┌─────┐
│ ▶ Convert│  │ 💾  │  ← Primary and utility actions
└─────────┘  └─────┘
  (Ctrl+Enter) (Ctrl+S)
```

---

## 📊 Status Bar States

### Idle State
```
┌──────────────────────────────────────────────────────┐
│ Ready                                                │
└──────────────────────────────────────────────────────┘
```

### Converting State
```
┌──────────────────────────────────────────────────────┐
│ Converting...                                        │
└──────────────────────────────────────────────────────┘
```

### Success State
```
┌──────────────────────────────────────────────────────┐
│ Converted in 45ms                              45ms  │
└──────────────────────────────────────────────────────┘
```

### Error State
```
┌──────────────────────────────────────────────────────┐
│ Conversion failed                                    │
└──────────────────────────────────────────────────────┘
```

---

## ⚠️ Error Display

When a conversion error occurs:

```
┌────────────────────────────────────────────────────────────────┐
│ ╔══════════════════════════════════════════════════════════╗   │
│ ║  ⚠️  Conversion Error                                     ║   │
│ ║                                                           ║   │
│ ║  ┌────────────────────────────────────────────────────┐   ║   │
│ ║  │ Invalid SQL syntax: Unexpected token 'CRETE'       │   ║   │
│ ║  │ Expected: 'CREATE'                                 │   ║   │
│ ║  │                                                    │   ║   │
│ ║  │ Line 1:                                            │   ║   │
│ ║  │   CRETE TABLE users (...)                          │   ║   │
│ ║  │   ^~~~~                                            │   ║   │
│ ║  └────────────────────────────────────────────────────┘   ║   │
│ ╚══════════════════════════════════════════════════════════╝   │
└────────────────────────────────────────────────────────────────┘
```

---

## 🎨 Theme Integration

The editor automatically adapts to your VS Code theme:

### Dark Theme
- Background: Dark gray (`--vscode-editor-background`)
- Text: Light gray (`--vscode-editor-foreground`)
- Accent: Blue/Purple (`--vscode-button-background`)
- Preview: White background (for diagram visibility)

### Light Theme
- Background: White (`--vscode-editor-background`)
- Text: Dark gray (`--vscode-editor-foreground`)
- Accent: Blue (`--vscode-button-background`)
- Preview: White background with border

---

## ⌨️ Keyboard Shortcuts Reference

```
┌─────────────────┬──────────────────────────────────┐
│ Shortcut        │ Action                           │
├─────────────────┼──────────────────────────────────┤
│ Ctrl+S          │ Save file                        │
│ Ctrl+Enter      │ Convert now                      │
│ Ctrl+M          │ Toggle SQL ↔ Mermaid mode        │
├─────────────────┼──────────────────────────────────┤
│ Ctrl+C          │ Copy selection                   │
│ Ctrl+V          │ Paste                            │
│ Ctrl+Z          │ Undo                             │
│ Ctrl+Y          │ Redo                             │
└─────────────────┴──────────────────────────────────┘
```

---

## 📱 Responsive Layout

On smaller screens, the layout adapts:

```
┌────────────────────────────────────┐
│         TOOLBAR                    │
│ (wraps to multiple rows)           │
├────────────────────────────────────┤
│                                    │
│      LEFT PANEL                    │
│      (Stacks on top)               │
│                                    │
├────────────────────────────────────┤
│                                    │
│      RIGHT PANEL                   │
│      (Stacks below)                │
│                                    │
├────────────────────────────────────┤
│         STATUS BAR                 │
└────────────────────────────────────┘
```

---

## 🎯 User Flow Examples

### Example 1: Quick SQL → Mermaid

1. Open `schema.sql`
2. Right-click → "Open in Split Editor"
3. ✨ **Instantly see preview and code!**
4. Click `📋` to copy Mermaid code
5. Paste into your documentation

### Example 2: Design New Schema

1. Create `new_schema.mmd`
2. Open in Split Editor
3. Draw ERD in Mermaid syntax
4. Click `⇄` to switch to Mermaid → SQL
5. Select "PostgreSQL" dialect
6. Click `▶ Convert`
7. Click `💾` to save SQL

### Example 3: Compare Dialects

1. Open `.mmd` file in Split Editor
2. Select "AnsiSql" → Click Convert → See result
3. Select "SqlServer" → Click Convert → See differences
4. Select "PostgreSql" → Click Convert → Compare again
5. Choose your favorite dialect!

---

**This visual guide helps you understand the interface at a glance!** 🎨

