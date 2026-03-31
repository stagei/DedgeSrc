# Tray App REST API Implementation - Task List

## Overview
Implement REST API on ServerMonitorTrayIcon (port 8997) for direct control of agents from the Dashboard.

---

## Phase 1: Tray App API Implementation

- [x] **1.1** Create `TrayApiServer.cs` - HTTP listener on port 8997
- [x] **1.2** Implement `GET /api/isalive` - Check if tray app is running
- [x] **1.3** Implement `GET /api/status` - Get agent service status and version
- [x] **1.4** Implement `POST /api/agent/start` - Start the agent service
- [x] **1.5** Implement `POST /api/agent/stop` - Stop the agent service
- [x] **1.6** Implement `POST /api/agent/restart` - Restart the agent service
- [x] **1.7** Implement `POST /api/agent/reinstall` - Trigger reinstall from source
- [x] **1.8** Add API server initialization to `TrayIconApplicationContext`
- [x] **1.9** Add proper disposal/cleanup of API server

---

## Phase 2: Firewall Configuration

- [x] **2.1** Update `ServerMonitorAgent` - Open port 8997 for Tray API
- [x] **2.2** Configure URL ACL for HttpListener (non-admin access)
- [ ] **2.3** Deploy updated install scripts via `_deploy.ps1`

---

## Phase 3: Dashboard Backend Changes

- [x] **3.1** Create `TrayApiService.cs` - HTTP client to call Tray APIs
- [x] **3.2** Create `TrayApiController.cs` - Endpoints for Dashboard to call Tray API
- [x] **3.3** Register TrayApiService in DI container
- [x] **3.4** Add HTTP client factory for Tray API

---

## Phase 4: Dashboard Frontend Changes

- [x] **4.1** Update `startServer()` - Use Tray API instead of trigger files
- [x] **4.2** Update `reinstallServer()` - Use Tray API instead of trigger files
- [x] **4.3** Add `restartServer()` function - New capability via Tray API
- [x] **4.4** Add `stopServer()` function - New capability via Tray API
- [x] **4.5** Update offline server buttons to include restart option
- [x] **4.6** Add fallback to trigger files if Tray API is unreachable

---

## Phase 5: Manual Trigger File Menu

- [x] **5.1** Add "Manual Override" dropdown menu to Dashboard header
- [x] **5.2** Add options: Create/Remove global Stop file
- [x] **5.3** Add options: Create/Remove global Start file
- [x] **5.4** Add options: Create/Remove global Reinstall file
- [x] **5.5** CSS styling for dropdown menu

---

## Phase 6: Testing & Cleanup

- [ ] **6.1** Test Tray API locally
- [ ] **6.2** Test firewall rules on remote server
- [ ] **6.3** Test Dashboard → Tray API communication
- [ ] **6.4** Build and publish all applications
- [ ] **6.5** Deploy install scripts via `_deploy.ps1`
- [ ] **6.6** Commit and push changes

---

## Progress Log

| Date | Task | Status |
|------|------|--------|
| 2026-01-15 | Phase 1: Tray App API Implementation | ✅ Complete |
| 2026-01-15 | Phase 2: Firewall Configuration | ✅ Complete |
| 2026-01-15 | Phase 3: Dashboard Backend Changes | ✅ Complete |
| 2026-01-15 | Phase 4: Dashboard Frontend Changes | ✅ Complete |
| 2026-01-15 | Phase 5: Manual Trigger File Menu | ✅ Complete |
| 2026-01-15 | Phase 6: Testing & Cleanup | 🔄 Pending |

