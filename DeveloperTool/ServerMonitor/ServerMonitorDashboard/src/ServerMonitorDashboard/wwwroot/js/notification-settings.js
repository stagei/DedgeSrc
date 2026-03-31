/**
 * Notification Settings Form Editor
 * Form-based UI for editing NotificationRecipients.json
 */

class NotificationSettingsEditor {
    constructor() {
        this.data = null;
        this.originalData = null;
        this.hasUnsavedChanges = false;
        this.deleteCallback = null;
        this.tooltip = null;
        
        this.apiEndpoint = 'api/config/notification-recipients';
        
        // Apply theme from localStorage
        this.applyTheme();
        
        // Create tooltip element
        this.createTooltip();
    }
    
    applyTheme() {
        const savedTheme = localStorage.getItem('theme') || 'light';
        document.documentElement.setAttribute('data-theme', savedTheme);
        document.body.setAttribute('data-theme', savedTheme);
    }
    
    createTooltip() {
        this.tooltip = document.createElement('div');
        this.tooltip.className = 'json-path-tooltip';
        this.tooltip.style.display = 'none';
        document.body.appendChild(this.tooltip);
    }
    
    showPathTooltip(e) {
        const target = e.target.closest('[data-json-path]');
        if (!target) return;
        
        const path = target.getAttribute('data-json-path');
        if (!path) return;
        
        this.tooltip.textContent = path;
        this.tooltip.style.display = 'block';
        
        // Position tooltip near cursor
        const x = e.clientX + 10;
        const y = e.clientY + 10;
        
        // Keep tooltip on screen
        const rect = this.tooltip.getBoundingClientRect();
        const maxX = window.innerWidth - rect.width - 20;
        const maxY = window.innerHeight - rect.height - 20;
        
        this.tooltip.style.left = Math.min(x, maxX) + 'px';
        this.tooltip.style.top = Math.min(y, maxY) + 'px';
    }
    
    hidePathTooltip() {
        this.tooltip.style.display = 'none';
    }
    
    async init() {
        this.bindEvents();
        await this.loadData();
    }
    
    bindEvents() {
        // Tab switching
        document.querySelectorAll('.tab-btn').forEach(btn => {
            btn.addEventListener('click', (e) => this.switchTab(e.target.dataset.tab));
        });
        
        // Header buttons
        document.getElementById('reloadBtn').addEventListener('click', () => this.loadData());
        document.getElementById('saveBtn').addEventListener('click', () => this.showSaveModal());
        document.getElementById('editJsonBtn').addEventListener('click', () => this.showJsonEditor());
        
        // Add buttons
        document.getElementById('addEnvironmentBtn').addEventListener('click', () => this.addEnvironment());
        document.getElementById('addPersonBtn').addEventListener('click', () => this.addPerson());
        
        // JSON modal
        document.getElementById('closeJsonModal').addEventListener('click', () => this.hideJsonModal());
        document.getElementById('cancelJsonBtn').addEventListener('click', () => this.hideJsonModal());
        document.getElementById('applyJsonBtn').addEventListener('click', () => this.applyJsonChanges());
        
        // Save modal
        document.getElementById('closeSaveModal').addEventListener('click', () => this.hideSaveModal());
        document.getElementById('cancelSaveBtn').addEventListener('click', () => this.hideSaveModal());
        document.getElementById('confirmSaveBtn').addEventListener('click', () => this.saveData());
        
        // Delete modal
        document.getElementById('closeDeleteModal').addEventListener('click', () => this.hideDeleteModal());
        document.getElementById('cancelDeleteBtn').addEventListener('click', () => this.hideDeleteModal());
        document.getElementById('confirmDeleteBtn').addEventListener('click', () => this.confirmDelete());
        
        // JSON editor validation
        document.getElementById('jsonEditor').addEventListener('input', () => this.validateJson());
        
        // Close modals on overlay click
        document.querySelectorAll('.modal-overlay').forEach(overlay => {
            overlay.addEventListener('click', (e) => {
                if (e.target === overlay) {
                    overlay.classList.add('hidden');
                }
            });
        });
        
        // JSON path tooltip
        document.addEventListener('mouseover', (e) => this.showPathTooltip(e));
        document.addEventListener('mouseout', (e) => {
            if (e.target.closest('[data-json-path]')) {
                this.hidePathTooltip();
            }
        });
    }
    
    switchTab(tabName) {
        document.querySelectorAll('.tab-btn').forEach(btn => {
            btn.classList.toggle('active', btn.dataset.tab === tabName);
        });
        document.querySelectorAll('.tab-panel').forEach(panel => {
            panel.classList.toggle('active', panel.id === `tab-${tabName}`);
        });
    }
    
    async loadData() {
        this.setStatus('Loading configuration...', 'loading');
        
        try {
            const response = await fetch(this.apiEndpoint);
            const result = await response.json();
            
            if (!result.success) {
                throw new Error(result.error || 'Failed to load configuration');
            }
            
            this.data = JSON.parse(result.content);
            this.originalData = JSON.parse(result.content);
            this.hasUnsavedChanges = false;
            
            // Update file info
            const fileInfo = document.getElementById('fileInfo');
            if (result.lastModified) {
                const date = new Date(result.lastModified);
                const sizeKb = (result.fileSize / 1024).toFixed(2);
                fileInfo.textContent = `Last modified: ${date.toLocaleString()} (${sizeKb} KB)`;
            }
            
            this.renderEnvironments();
            this.renderPeople();
            this.setStatus('Ready', 'success');
            
        } catch (error) {
            console.error('Failed to load data:', error);
            this.setStatus(`Error: ${error.message}`, 'error');
        }
    }
    
    setStatus(message, type = '') {
        const statusBar = document.getElementById('statusBar');
        const statusMessage = document.getElementById('statusMessage');
        
        statusBar.className = 'status-bar';
        if (type) statusBar.classList.add(type);
        statusMessage.textContent = message;
    }
    
    markAsChanged() {
        this.hasUnsavedChanges = true;
        const saveBtn = document.getElementById('saveBtn');
        saveBtn.classList.add('pulse');
        this.setStatus('Unsaved changes', 'warning');
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // ENVIRONMENTS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    renderEnvironments() {
        const container = document.getElementById('environmentsContainer');
        
        if (!this.data.environments || this.data.environments.length === 0) {
            container.innerHTML = `
                <div class="empty-state">
                    <div class="empty-icon">🌍</div>
                    <h3>No Environments Configured</h3>
                    <p>Add an environment to define alert channel settings for different server groups.</p>
                </div>
            `;
            return;
        }
        
        container.innerHTML = this.data.environments.map((env, index) => this.renderEnvironmentCard(env, index)).join('');
        
        // Bind environment card events
        this.bindEnvironmentEvents();
    }
    
    renderEnvironmentCard(env, index) {
        const channels = env.channels || {};
        const channelsList = [
            { key: 'sms', name: 'SMS', icon: '📱' },
            { key: 'email', name: 'Email', icon: '📧' },
            { key: 'eventLog', name: 'Event Log', icon: '📋' },
            { key: 'file', name: 'File', icon: '📁' },
            { key: 'wkMonitor', name: 'WKMonitor', icon: '🔔' }
        ];
        
        return `
            <div class="form-card" data-env-index="${index}">
                <div class="card-header" onclick="editor.toggleCard(this)">
                    <div class="card-title">
                        <h3>🌍 ${this.escapeHtml(env.name)}</h3>
                        ${env.isDefault ? '<span class="badge badge-default">Default</span>' : ''}
                    </div>
                    <div class="card-actions">
                        <button class="btn btn-icon btn-outline btn-delete-env" data-index="${index}" title="Delete environment" onclick="event.stopPropagation()">
                            🗑️
                        </button>
                        <span class="card-toggle">▼</span>
                    </div>
                </div>
                <div class="card-body">
                    <div class="form-grid">
                        <div class="form-group" data-json-path="environments[${index}].name">
                            <label>Name <span class="required">*</span></label>
                            <input type="text" class="form-control env-name" value="${this.escapeHtml(env.name)}" data-index="${index}">
                        </div>
                        <div class="form-group" data-json-path="environments[${index}].description">
                            <label>Description</label>
                            <input type="text" class="form-control env-description" value="${this.escapeHtml(env.description || '')}" data-index="${index}">
                        </div>
                    </div>
                    
                    <div class="form-group" style="margin-top: 1rem;" data-json-path="environments[${index}].isDefault">
                        <label>
                            <div class="toggle-switch">
                                <input type="checkbox" class="env-default" ${env.isDefault ? 'checked' : ''} data-index="${index}">
                                <span class="toggle-slider"></span>
                                <span class="toggle-label">Default Environment (catch-all for unmatched servers)</span>
                            </div>
                        </label>
                    </div>
                    
                    <div class="section-divider">
                        <h4>Server Name Patterns</h4>
                    </div>
                    <div class="form-group" data-json-path="environments[${index}].computerNamePatterns">
                        <div class="tags-container env-patterns" data-index="${index}">
                            ${(env.computerNamePatterns || []).map(p => `
                                <span class="tag">
                                    ${this.escapeHtml(p)}
                                    <button class="tag-remove" onclick="editor.removePattern(${index}, '${this.escapeHtml(p)}')">&times;</button>
                                </span>
                            `).join('')}
                            <input type="text" class="tag-input" placeholder="Add pattern (press Enter)" 
                                   onkeydown="editor.handlePatternKeydown(event, ${index})">
                        </div>
                        <span class="help-text">Wildcard patterns to match server names (e.g., *PRD*, *-app, PROD-*)</span>
                    </div>
                    
                    <div class="section-divider">
                        <h4>Alert Channels</h4>
                    </div>
                    <div class="channels-grid" data-json-path="environments[${index}].channels">
                        ${channelsList.map(ch => `
                            <div class="channel-toggle ${channels[ch.key] ? 'enabled' : ''}" data-json-path="environments[${index}].channels.${ch.key}">
                                <input type="checkbox" class="env-channel" 
                                       data-index="${index}" 
                                       data-channel="${ch.key}" 
                                       ${channels[ch.key] ? 'checked' : ''}>
                                <span class="channel-icon">${ch.icon}</span>
                                <span class="channel-name">${ch.name}</span>
                            </div>
                        `).join('')}
                    </div>
                </div>
            </div>
        `;
    }
    
    bindEnvironmentEvents() {
        // Name changes
        document.querySelectorAll('.env-name').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                this.data.environments[index].name = e.target.value;
                this.markAsChanged();
            });
        });
        
        // Description changes
        document.querySelectorAll('.env-description').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                this.data.environments[index].description = e.target.value;
                this.markAsChanged();
            });
        });
        
        // Default toggle
        document.querySelectorAll('.env-default').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                // Only one can be default
                if (e.target.checked) {
                    this.data.environments.forEach((env, i) => {
                        env.isDefault = (i === index);
                    });
                } else {
                    this.data.environments[index].isDefault = false;
                }
                this.markAsChanged();
                this.renderEnvironments();
            });
        });
        
        // Channel toggles
        document.querySelectorAll('.env-channel').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                const channel = e.target.dataset.channel;
                if (!this.data.environments[index].channels) {
                    this.data.environments[index].channels = {};
                }
                this.data.environments[index].channels[channel] = e.target.checked;
                e.target.parentElement.classList.toggle('enabled', e.target.checked);
                this.markAsChanged();
            });
        });
        
        // Delete buttons
        document.querySelectorAll('.btn-delete-env').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const index = parseInt(e.target.dataset.index);
                this.showDeleteModal('environment', () => {
                    this.data.environments.splice(index, 1);
                    this.markAsChanged();
                    this.renderEnvironments();
                });
            });
        });
    }
    
    handlePatternKeydown(event, envIndex) {
        if (event.key === 'Enter') {
            event.preventDefault();
            const input = event.target;
            const pattern = input.value.trim();
            if (pattern) {
                if (!this.data.environments[envIndex].computerNamePatterns) {
                    this.data.environments[envIndex].computerNamePatterns = [];
                }
                if (!this.data.environments[envIndex].computerNamePatterns.includes(pattern)) {
                    this.data.environments[envIndex].computerNamePatterns.push(pattern);
                    this.markAsChanged();
                    this.renderEnvironments();
                }
            }
        }
    }
    
    removePattern(envIndex, pattern) {
        const patterns = this.data.environments[envIndex].computerNamePatterns;
        const idx = patterns.indexOf(pattern);
        if (idx > -1) {
            patterns.splice(idx, 1);
            this.markAsChanged();
            this.renderEnvironments();
        }
    }
    
    addEnvironment() {
        const newEnv = {
            name: 'New Environment',
            description: '',
            computerNamePatterns: [],
            isDefault: false,
            channels: {
                sms: false,
                email: false,
                eventLog: false,
                file: true,
                wkMonitor: false
            }
        };
        this.data.environments.push(newEnv);
        this.markAsChanged();
        this.renderEnvironments();
        
        // Scroll to new card
        setTimeout(() => {
            const cards = document.querySelectorAll('.form-card[data-env-index]');
            if (cards.length > 0) {
                cards[cards.length - 1].scrollIntoView({ behavior: 'smooth' });
            }
        }, 100);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // PEOPLE
    // ═══════════════════════════════════════════════════════════════════════════════
    
    renderPeople() {
        const container = document.getElementById('peopleContainer');
        
        if (!this.data.people || this.data.people.length === 0) {
            container.innerHTML = `
                <div class="empty-state">
                    <div class="empty-icon">👥</div>
                    <h3>No Recipients Configured</h3>
                    <p>Add a person to receive alert notifications.</p>
                </div>
            `;
            return;
        }
        
        container.innerHTML = this.data.people.map((person, index) => this.renderPersonCard(person, index)).join('');
        
        // Bind person card events
        this.bindPersonEvents();
    }
    
    renderPersonCard(person, index) {
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        const environments = this.data.environments || [];
        
        return `
            <div class="form-card" data-person-index="${index}">
                <div class="card-header" onclick="editor.toggleCard(this)">
                    <div class="card-title">
                        <h3>👤 ${this.escapeHtml(person.name)}</h3>
                        <span class="badge ${person.enabled ? 'badge-enabled' : 'badge-disabled'}">
                            ${person.enabled ? 'Enabled' : 'Disabled'}
                        </span>
                    </div>
                    <div class="card-actions">
                        <button class="btn btn-icon btn-outline btn-delete-person" data-index="${index}" title="Delete person" onclick="event.stopPropagation()">
                            🗑️
                        </button>
                        <span class="card-toggle">▼</span>
                    </div>
                </div>
                <div class="card-body">
                    <div class="form-grid">
                        <div class="form-group" data-json-path="people[${index}].name">
                            <label>Name <span class="required">*</span></label>
                            <input type="text" class="form-control person-name" value="${this.escapeHtml(person.name)}" data-index="${index}">
                        </div>
                        <div class="form-group" data-json-path="people[${index}].id">
                            <label>ID</label>
                            <input type="text" class="form-control person-id" value="${this.escapeHtml(person.id)}" data-index="${index}">
                        </div>
                    </div>
                    
                    <div class="form-grid">
                        <div class="form-group" data-json-path="people[${index}].email">
                            <label>Email</label>
                            <input type="email" class="form-control person-email" value="${this.escapeHtml(person.email || '')}" data-index="${index}">
                        </div>
                        <div class="form-group" data-json-path="people[${index}].phone">
                            <label>Phone</label>
                            <input type="tel" class="form-control person-phone" value="${this.escapeHtml(person.phone || '')}" data-index="${index}" placeholder="+47...">
                        </div>
                    </div>
                    
                    <div class="form-group" style="margin-top: 1rem;" data-json-path="people[${index}].enabled">
                        <label>
                            <div class="toggle-switch">
                                <input type="checkbox" class="person-enabled" ${person.enabled ? 'checked' : ''} data-index="${index}">
                                <span class="toggle-slider"></span>
                                <span class="toggle-label">Enabled (receives notifications)</span>
                            </div>
                        </label>
                    </div>
                    
                    ${environments.map(env => this.renderPersonSchedule(person, index, env.name)).join('')}
                </div>
            </div>
        `;
    }
    
    renderPersonSchedule(person, personIndex, envName) {
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        const schedule = person.environments?.[envName] || {};
        
        return `
            <div class="section-divider">
                <h4>🌍 ${this.escapeHtml(envName)} Schedule</h4>
            </div>
            <table class="schedule-table">
                <thead>
                    <tr>
                        <th>Day</th>
                        <th>📧 Email</th>
                        <th>📱 SMS</th>
                    </tr>
                </thead>
                <tbody>
                    ${days.map(day => {
                        const daySchedule = schedule[day] || {};
                        const emailTime = daySchedule.email;
                        const smsTime = daySchedule.sms;
                        
                        return `
                            <tr>
                                <td class="day-cell">${day}</td>
                                <td>
                                    ${emailTime ? `
                                        <span class="time-range">${emailTime.from} - ${emailTime.to}</span>
                                    ` : `
                                        <span class="time-range disabled">Off</span>
                                    `}
                                </td>
                                <td>
                                    ${smsTime ? `
                                        <span class="time-range">${smsTime.from} - ${smsTime.to}</span>
                                    ` : `
                                        <span class="time-range disabled">Off</span>
                                    `}
                                </td>
                            </tr>
                        `;
                    }).join('')}
                </tbody>
            </table>
            <p class="help-text" style="margin-top: 0.5rem;">
                To edit detailed schedules, use the JSON editor.
            </p>
        `;
    }
    
    bindPersonEvents() {
        // Name changes
        document.querySelectorAll('.person-name').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                this.data.people[index].name = e.target.value;
                this.markAsChanged();
            });
        });
        
        // ID changes
        document.querySelectorAll('.person-id').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                this.data.people[index].id = e.target.value;
                this.markAsChanged();
            });
        });
        
        // Email changes
        document.querySelectorAll('.person-email').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                this.data.people[index].email = e.target.value;
                this.markAsChanged();
            });
        });
        
        // Phone changes
        document.querySelectorAll('.person-phone').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                this.data.people[index].phone = e.target.value;
                this.markAsChanged();
            });
        });
        
        // Enabled toggle
        document.querySelectorAll('.person-enabled').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                this.data.people[index].enabled = e.target.checked;
                this.markAsChanged();
                // Update badge
                const card = e.target.closest('.form-card');
                const badge = card.querySelector('.badge');
                badge.className = `badge ${e.target.checked ? 'badge-enabled' : 'badge-disabled'}`;
                badge.textContent = e.target.checked ? 'Enabled' : 'Disabled';
            });
        });
        
        // Delete buttons
        document.querySelectorAll('.btn-delete-person').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const index = parseInt(e.target.dataset.index);
                this.showDeleteModal('person', () => {
                    this.data.people.splice(index, 1);
                    this.markAsChanged();
                    this.renderPeople();
                });
            });
        });
    }
    
    addPerson() {
        // Create default schedule for all environments
        const environments = {};
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        
        (this.data.environments || []).forEach(env => {
            environments[env.name] = {};
            days.forEach(day => {
                environments[env.name][day] = {
                    email: day === 'Saturday' || day === 'Sunday' ? null : { from: '08:00', to: '17:00' },
                    sms: null
                };
            });
        });
        
        const newPerson = {
            id: `person${(this.data.people?.length || 0) + 1}`,
            name: 'New Person',
            email: '',
            phone: '',
            enabled: true,
            environments: environments,
            absences: []
        };
        
        if (!this.data.people) {
            this.data.people = [];
        }
        this.data.people.push(newPerson);
        this.markAsChanged();
        this.renderPeople();
        
        // Switch to people tab and scroll to new card
        this.switchTab('people');
        setTimeout(() => {
            const cards = document.querySelectorAll('.form-card[data-person-index]');
            if (cards.length > 0) {
                cards[cards.length - 1].scrollIntoView({ behavior: 'smooth' });
            }
        }, 100);
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // COMMON UI
    // ═══════════════════════════════════════════════════════════════════════════════
    
    toggleCard(header) {
        const card = header.closest('.form-card');
        card.classList.toggle('collapsed');
    }
    
    escapeHtml(str) {
        if (!str) return '';
        return str.replace(/&/g, '&amp;')
                  .replace(/</g, '&lt;')
                  .replace(/>/g, '&gt;')
                  .replace(/"/g, '&quot;')
                  .replace(/'/g, '&#039;');
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // JSON EDITOR MODAL
    // ═══════════════════════════════════════════════════════════════════════════════
    
    showJsonEditor() {
        const jsonEditor = document.getElementById('jsonEditor');
        jsonEditor.value = JSON.stringify(this.data, null, 2);
        document.getElementById('jsonModal').classList.remove('hidden');
        this.validateJson();
    }
    
    hideJsonModal() {
        document.getElementById('jsonModal').classList.add('hidden');
    }
    
    validateJson() {
        const jsonEditor = document.getElementById('jsonEditor');
        const validation = document.getElementById('jsonValidation');
        
        try {
            JSON.parse(jsonEditor.value);
            validation.innerHTML = '<span class="validation-status">✅ Valid JSON</span>';
            return true;
        } catch (e) {
            validation.innerHTML = `<span class="validation-status invalid">❌ Invalid JSON: ${e.message}</span>`;
            return false;
        }
    }
    
    applyJsonChanges() {
        if (!this.validateJson()) {
            return;
        }
        
        try {
            const jsonEditor = document.getElementById('jsonEditor');
            this.data = JSON.parse(jsonEditor.value);
            this.markAsChanged();
            this.renderEnvironments();
            this.renderPeople();
            this.hideJsonModal();
            this.setStatus('JSON changes applied', 'success');
        } catch (e) {
            this.setStatus(`Error applying JSON: ${e.message}`, 'error');
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // SAVE & DELETE MODALS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    showSaveModal() {
        if (!this.hasUnsavedChanges) {
            this.setStatus('No changes to save', 'warning');
            return;
        }
        document.getElementById('saveModal').classList.remove('hidden');
    }
    
    hideSaveModal() {
        document.getElementById('saveModal').classList.add('hidden');
    }
    
    async saveData() {
        this.hideSaveModal();
        this.setStatus('Saving...', 'loading');
        
        // Update lastUpdated
        this.data.lastUpdated = new Date().toISOString();
        
        try {
            const response = await fetch(this.apiEndpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    content: JSON.stringify(this.data, null, 2),
                    editedBy: 'Dashboard User'
                })
            });
            
            const result = await response.json();
            
            if (!result.success) {
                throw new Error(result.error || 'Failed to save');
            }
            
            this.originalData = JSON.parse(JSON.stringify(this.data));
            this.hasUnsavedChanges = false;
            this.setStatus('Saved successfully!', 'success');
            
            // Update file info
            document.getElementById('fileInfo').textContent = `Last modified: ${new Date().toLocaleString()}`;
            
        } catch (error) {
            console.error('Failed to save:', error);
            this.setStatus(`Error saving: ${error.message}`, 'error');
        }
    }
    
    showDeleteModal(itemType, callback) {
        this.deleteCallback = callback;
        document.getElementById('deleteMessage').textContent = 
            `Are you sure you want to delete this ${itemType}?`;
        document.getElementById('deleteModal').classList.remove('hidden');
    }
    
    hideDeleteModal() {
        document.getElementById('deleteModal').classList.add('hidden');
        this.deleteCallback = null;
    }
    
    confirmDelete() {
        if (this.deleteCallback) {
            this.deleteCallback();
        }
        this.hideDeleteModal();
    }
}

// Initialize editor
const editor = new NotificationSettingsEditor();
editor.init();
