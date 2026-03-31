# Phase 5: Additional Languages (Norwegian, French) - Task List

**Goal:** Add multi-language support for Norwegian and French  
**Estimated Duration:** 2 weeks  
**Priority:** 🔵 LOW (Future)

---

## Status Summary
- **Total Tasks:** 15
- **Completed:** 0
- **In Progress:** 0
- **Pending:** 15

---

## Tasks

### Week 12: Norwegian Translation

#### 5.1 Create db2_12.1_no-NO_texts.json
- [ ] Create `ConfigFiles/db2_12.1_no-NO_texts.json`
- [ ] Add provider, version, language fields
- [ ] Add translator and last_updated metadata
- [ ] Translate MainFormTitle
- [ ] Translate all ui.menu.* entries
- [ ] Translate all ui.toolbar.* entries
- [ ] Translate all ui.object_browser.* entries
- [ ] Translate all messages.errors.* entries
- [ ] Translate all messages.warnings.* entries
- [ ] Translate all messages.success.* entries
- [ ] Translate all common.buttons.* entries
- [ ] Validate JSON syntax
- [ ] Test file loads successfully

#### 5.2 Implement Language Selector in Settings
- [ ] Update SettingsDialog.xaml with language ComboBox
- [ ] Add Label "Application Language:"
- [ ] Populate ComboBox with GetAllDistinctLanguages()
- [ ] Display: "English (United States)", "Norsk (Norge)"
- [ ] Bind to UserPreferences.LanguageCode
- [ ] Implement language change on save
- [ ] Add restart notice
- [ ] Test language selection

#### 5.3 Test Norwegian Language
- [ ] Change language to no-NO in settings
- [ ] Restart application
- [ ] Verify menu items display Norwegian text
- [ ] Verify toolbar displays Norwegian text
- [ ] Verify object browser categories display Norwegian
- [ ] Verify error messages display Norwegian
- [ ] Test fallback to English for missing keys
- [ ] Test CLI execution still works

### Week 13: French Translation

#### 5.4 Create db2_12.1_fr-FR_texts.json
- [ ] Create `ConfigFiles/db2_12.1_fr-FR_texts.json`
- [ ] Add provider, version, language fields
- [ ] Add translator and last_updated metadata
- [ ] Translate MainFormTitle
- [ ] Translate all ui.menu.* entries
- [ ] Translate all ui.toolbar.* entries
- [ ] Translate all ui.object_browser.* entries
- [ ] Translate all messages.errors.* entries
- [ ] Translate all messages.warnings.* entries
- [ ] Translate all messages.success.* entries
- [ ] Translate all common.buttons.* entries
- [ ] Validate JSON syntax
- [ ] Test file loads successfully

#### 5.5 Test French Language
- [ ] Change language to fr-FR in settings
- [ ] Restart application
- [ ] Verify menu items display French text
- [ ] Verify toolbar displays French text
- [ ] Verify object browser categories display French
- [ ] Verify error messages display French
- [ ] Test fallback to English for missing keys
- [ ] Test CLI execution still works

#### 5.6 Multi-Language Testing
- [ ] Test switching from English to Norwegian
- [ ] Test switching from Norwegian to French
- [ ] Test switching from French to English
- [ ] Verify all text updates correctly
- [ ] Test missing translation fallback
- [ ] Test parameter replacement in translated text
- [ ] Test CLI execution in all languages

---

**Status:** ⏳ NOT STARTED (Future Work)  
**Next Milestone:** Full Norwegian and French support  
**Blockers:** Phase 4 must be complete

---

**Last Updated:** 2025-11-20

