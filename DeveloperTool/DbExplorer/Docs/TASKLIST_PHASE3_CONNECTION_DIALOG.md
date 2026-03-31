# Phase 3: Connection Dialog with Provider Selection - Task List

**Goal:** Enable users to select database provider at connection time  
**Estimated Duration:** 1 week  
**Priority:** 🟡 HIGH

---

## Status Summary
- **Total Tasks:** 15
- **Completed:** 0
- **In Progress:** 0
- **Pending:** 15

---

## Tasks

### Week 5: Provider Selection UI

#### 3.1 Update DbConnectionProfile Model
- [ ] Rename `Models/DB2Connection.cs` to `Models/DbConnectionProfile.cs`
- [ ] Rename class `DB2Connection` to `DbConnectionProfile`
- [ ] Add property: `ProviderCode` (string)
- [ ] Add property: `ProviderVersion` (string)
- [ ] Update all references in codebase
- [ ] Add migration logic for old profiles
- [ ] Test profile save/load

#### 3.2 Update ConnectionDialog XAML
- [ ] Open `Dialogs/ConnectionDialog.xaml`
- [ ] Change window title to "Database Connection Settings"
- [ ] Add provider selection ComboBox at top
  - [ ] Add Label "Database Provider:"
  - [ ] Add ComboBox with icon + display name template
  - [ ] Bind to Providers list
- [ ] Add version selection ComboBox
  - [ ] Add Label "Version:"
  - [ ] Bind to SelectedProvider.SupportedVersions
- [ ] Update port TextBox to bind to SelectedProvider.DefaultPort
- [ ] Test XAML compiles

#### 3.3 Update ConnectionDialog Code-Behind
- [ ] Inject MetadataHandler into constructor
- [ ] Add field: `private List<Provider> _providers`
- [ ] Implement LoadProviders() method
  - [ ] Call _metadataHandler.GetSupportedProviders()
  - [ ] Set ProviderComboBox.ItemsSource
  - [ ] Default to DB2 if available
- [ ] Implement ProviderComboBox_SelectionChanged
  - [ ] Update port to provider default
  - [ ] Populate version dropdown
  - [ ] Select latest version by default
- [ ] Update Connect_Click handler
  - [ ] Get selected provider and version
  - [ ] Create DbConnectionProfile with provider info
  - [ ] Create DbConnectionManager
  - [ ] Test connection
- [ ] Add comprehensive DEBUG logging
- [ ] Test dialog opens and displays providers

#### 3.4 Update Connection Profile Storage
- [ ] Update profile JSON to include provider and version
- [ ] Add default provider="DB2", version="12.1" for existing profiles
- [ ] Test profile save includes new fields
- [ ] Test profile load reads new fields
- [ ] Test CLI with ILOGTST profile (add provider if missing)

#### 3.5 Update Recent Connections
- [ ] Update WelcomePanel to show provider icon
- [ ] Update connection list display format
- [ ] Test recent connections display correctly

#### 3.6 Testing
- [ ] Test selecting DB2 provider
- [ ] Test version dropdown populates
- [ ] Test port auto-fills to 50000
- [ ] Test connection succeeds
- [ ] Test profile saves with provider info
- [ ] Test profile loads and displays provider
- [ ] Verify CLI execution with ILOGTST still works
- [ ] Test build succeeds

---

**Status:** ⏳ NOT STARTED  
**Next Milestone:** Users can select provider in connection dialog  
**Blockers:** Phase 2 must be complete

---

**Last Updated:** 2025-11-20

