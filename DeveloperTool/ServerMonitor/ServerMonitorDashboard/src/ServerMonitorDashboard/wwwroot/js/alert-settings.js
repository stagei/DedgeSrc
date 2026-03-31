/**
 * Alert Settings Form Editor
 * Form-based UI for editing appsettings.ServerMonitorAgent.json
 */

class AlertSettingsEditor {
    constructor() {
        this.data = null;
        this.originalData = null;
        this.hasUnsavedChanges = false;
        this.tooltip = null;
        
        this.apiEndpoint = 'api/config/agent-settings';
        
        this.channelTypes = [
            { key: 'SMS', icon: '📱', name: 'SMS' },
            { key: 'Email', icon: '📧', name: 'Email' },
            { key: 'EventLog', icon: '📋', name: 'Event Log' },
            { key: 'File', icon: '📁', name: 'File' },
            { key: 'WKMonitor', icon: '🔔', name: 'WKMonitor' }
        ];
        
        this.severityOptions = ['Informational', 'Warning', 'Critical'];
        
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
        
        // JSON modal
        document.getElementById('closeJsonModal').addEventListener('click', () => this.hideJsonModal());
        document.getElementById('cancelJsonBtn').addEventListener('click', () => this.hideJsonModal());
        document.getElementById('applyJsonBtn').addEventListener('click', () => this.applyJsonChanges());
        
        // Save modal
        document.getElementById('closeSaveModal').addEventListener('click', () => this.hideSaveModal());
        document.getElementById('cancelSaveBtn').addEventListener('click', () => this.hideSaveModal());
        document.getElementById('confirmSaveBtn').addEventListener('click', () => this.saveData());
        
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
            
            this.renderChannels();
            this.renderThrottling();
            this.renderExportSettings();
            this.renderPerformanceScaling();
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
    
    escapeHtml(str) {
        if (!str) return '';
        return String(str).replace(/&/g, '&amp;')
                  .replace(/</g, '&lt;')
                  .replace(/>/g, '&gt;')
                  .replace(/"/g, '&quot;')
                  .replace(/'/g, '&#039;');
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // ALERT CHANNELS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    renderChannels() {
        const container = document.getElementById('channelsContainer');
        const alerting = this.data.Alerting || {};
        const channels = alerting.Channels || [];
        
        // Add master enable toggle
        let html = `
            <div class="form-card" style="margin-bottom: 1rem;">
                <div class="card-body">
                    <div class="form-group">
                        <label>
                            <div class="toggle-switch">
                                <input type="checkbox" id="alertingEnabled" ${alerting.Enabled ? 'checked' : ''}>
                                <span class="toggle-slider"></span>
                                <span class="toggle-label"><strong>Enable Alerting System</strong></span>
                            </div>
                        </label>
                    </div>
                </div>
            </div>
        `;
        
        html += channels.map((channel, index) => this.renderChannelCard(channel, index)).join('');
        
        container.innerHTML = html;
        this.bindChannelEvents();
    }
    
    renderChannelCard(channel, index) {
        const type = channel.Type || 'Unknown';
        const iconInfo = this.channelTypes.find(c => c.key === type) || { icon: '📢', name: type };
        const settings = channel.Settings || {};
        
        let settingsHtml = '';
        
        // Channel-specific settings
        switch(type) {
            case 'SMS':
                settingsHtml = `
                    <div class="form-grid">
                        <div class="form-group">
                            <label>API URL</label>
                            <input type="text" class="form-control channel-setting" data-index="${index}" data-setting="ApiUrl" value="${this.escapeHtml(settings.ApiUrl || '')}">
                        </div>
                        <div class="form-group">
                            <label>Sender</label>
                            <input type="text" class="form-control channel-setting" data-index="${index}" data-setting="Sender" value="${this.escapeHtml(settings.Sender || '')}">
                        </div>
                        <div class="form-group">
                            <label>Client</label>
                            <input type="text" class="form-control channel-setting" data-index="${index}" data-setting="Client" value="${this.escapeHtml(settings.Client || '')}">
                        </div>
                        <div class="form-group">
                            <label>Default Country Code</label>
                            <input type="text" class="form-control channel-setting" data-index="${index}" data-setting="DefaultCountryCode" value="${this.escapeHtml(settings.DefaultCountryCode || '+47')}">
                        </div>
                        <div class="form-group">
                            <label>Max Message Length</label>
                            <input type="number" class="form-control channel-setting" data-index="${index}" data-setting="MaxMessageLength" value="${settings.MaxMessageLength || 1000}">
                        </div>
                    </div>
                `;
                break;
                
            case 'Email':
                settingsHtml = `
                    <div class="form-grid">
                        <div class="form-group">
                            <label>SMTP Server</label>
                            <input type="text" class="form-control channel-setting" data-index="${index}" data-setting="SmtpServer" value="${this.escapeHtml(settings.SmtpServer || '')}">
                        </div>
                        <div class="form-group">
                            <label>SMTP Port</label>
                            <input type="number" class="form-control channel-setting" data-index="${index}" data-setting="SmtpPort" value="${settings.SmtpPort || 25}">
                        </div>
                        <div class="form-group">
                            <label>From Address</label>
                            <input type="text" class="form-control channel-setting" data-index="${index}" data-setting="From" value="${this.escapeHtml(settings.From || '')}">
                        </div>
                        <div class="form-group">
                            <label>
                                <div class="toggle-switch">
                                    <input type="checkbox" class="channel-setting-bool" data-index="${index}" data-setting="EnableSsl" ${settings.EnableSsl ? 'checked' : ''}>
                                    <span class="toggle-slider"></span>
                                    <span class="toggle-label">Enable SSL/TLS</span>
                                </div>
                            </label>
                        </div>
                    </div>
                `;
                break;
                
            case 'File':
                settingsHtml = `
                    <div class="form-group">
                        <label>Log Path</label>
                        <input type="text" class="form-control channel-setting" data-index="${index}" data-setting="LogPath" value="${this.escapeHtml(settings.LogPath || '')}">
                        <span class="help-text">Use {Date} placeholder for date-based filenames</span>
                    </div>
                `;
                break;
                
            case 'WKMonitor':
                settingsHtml = `
                    <div class="form-grid">
                        <div class="form-group">
                            <label>Production Path</label>
                            <input type="text" class="form-control channel-setting" data-index="${index}" data-setting="ProductionPath" value="${this.escapeHtml(settings.ProductionPath || '')}">
                        </div>
                        <div class="form-group">
                            <label>Test Path</label>
                            <input type="text" class="form-control channel-setting" data-index="${index}" data-setting="TestPath" value="${this.escapeHtml(settings.TestPath || '')}">
                        </div>
                        <div class="form-group">
                            <label>Program Name</label>
                            <input type="text" class="form-control channel-setting" data-index="${index}" data-setting="ProgramName" value="${this.escapeHtml(settings.ProgramName || '')}">
                        </div>
                    </div>
                `;
                break;
                
            default:
                settingsHtml = '<p class="help-text">No additional settings for this channel.</p>';
        }
        
        return `
            <div class="form-card" data-channel-index="${index}">
                <div class="card-header" onclick="editor.toggleCard(this)">
                    <div class="card-title">
                        <h3>${iconInfo.icon} ${iconInfo.name}</h3>
                        <span class="badge ${channel.Enabled ? 'badge-enabled' : 'badge-disabled'}">
                            ${channel.Enabled ? 'Enabled' : 'Disabled'}
                        </span>
                    </div>
                    <div class="card-actions">
                        <span class="card-toggle">▼</span>
                    </div>
                </div>
                <div class="card-body">
                    <div class="form-grid">
                        <div class="form-group">
                            <label>
                                <div class="toggle-switch">
                                    <input type="checkbox" class="channel-enabled" data-index="${index}" ${channel.Enabled ? 'checked' : ''}>
                                    <span class="toggle-slider"></span>
                                    <span class="toggle-label">Channel Enabled</span>
                                </div>
                            </label>
                        </div>
                        <div class="form-group">
                            <label>Minimum Severity</label>
                            <select class="form-control channel-severity" data-index="${index}">
                                ${this.severityOptions.map(s => `
                                    <option value="${s}" ${channel.MinSeverity === s ? 'selected' : ''}>${s}</option>
                                `).join('')}
                            </select>
                        </div>
                    </div>
                    
                    <div class="section-divider">
                        <h4>Channel Settings</h4>
                    </div>
                    ${settingsHtml}
                </div>
            </div>
        `;
    }
    
    bindChannelEvents() {
        // Master enable
        document.getElementById('alertingEnabled')?.addEventListener('change', (e) => {
            this.data.Alerting.Enabled = e.target.checked;
            this.markAsChanged();
        });
        
        // Channel enabled toggles
        document.querySelectorAll('.channel-enabled').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                this.data.Alerting.Channels[index].Enabled = e.target.checked;
                
                // Update badge
                const card = e.target.closest('.form-card');
                const badge = card.querySelector('.badge');
                badge.className = `badge ${e.target.checked ? 'badge-enabled' : 'badge-disabled'}`;
                badge.textContent = e.target.checked ? 'Enabled' : 'Disabled';
                
                this.markAsChanged();
            });
        });
        
        // Severity selects
        document.querySelectorAll('.channel-severity').forEach(select => {
            select.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                this.data.Alerting.Channels[index].MinSeverity = e.target.value;
                this.markAsChanged();
            });
        });
        
        // Channel settings (text/number inputs)
        document.querySelectorAll('.channel-setting').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                const setting = e.target.dataset.setting;
                let value = e.target.value;
                
                // Convert to number if it's a number input
                if (e.target.type === 'number') {
                    value = parseInt(value) || 0;
                }
                
                if (!this.data.Alerting.Channels[index].Settings) {
                    this.data.Alerting.Channels[index].Settings = {};
                }
                this.data.Alerting.Channels[index].Settings[setting] = value;
                this.markAsChanged();
            });
        });
        
        // Channel settings (boolean inputs)
        document.querySelectorAll('.channel-setting-bool').forEach(input => {
            input.addEventListener('change', (e) => {
                const index = parseInt(e.target.dataset.index);
                const setting = e.target.dataset.setting;
                
                if (!this.data.Alerting.Channels[index].Settings) {
                    this.data.Alerting.Channels[index].Settings = {};
                }
                this.data.Alerting.Channels[index].Settings[setting] = e.target.checked;
                this.markAsChanged();
            });
        });
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // THROTTLING
    // ═══════════════════════════════════════════════════════════════════════════════
    
    renderThrottling() {
        const alerting = this.data.Alerting || {};
        const throttling = alerting.Throttling || {};
        
        // Set values
        document.getElementById('throttlingEnabled').checked = throttling.Enabled !== false;
        document.getElementById('maxAlertsPerHour').value = throttling.MaxAlertsPerHour || 100;
        document.getElementById('infoSuppression').value = throttling.InformationalSuppressionMinutes || 60;
        document.getElementById('warningSuppression').value = throttling.WarningSuppressionMinutes || 15;
        document.getElementById('errorSuppression').value = throttling.ErrorSuppressionMinutes || 5;
        
        // Render global suppressions
        const suppressions = alerting.SuppressedChannels || [];
        const container = document.getElementById('globalSuppressions');
        
        container.innerHTML = this.channelTypes.map(ch => `
            <div class="channel-toggle ${suppressions.includes(ch.key) ? '' : 'enabled'}">
                <input type="checkbox" class="global-suppression" data-channel="${ch.key}" ${suppressions.includes(ch.key) ? '' : 'checked'}>
                <span class="channel-icon">${ch.icon}</span>
                <span class="channel-name">${ch.name}</span>
            </div>
        `).join('');
        
        this.bindThrottlingEvents();
    }
    
    bindThrottlingEvents() {
        // Throttling enabled
        document.getElementById('throttlingEnabled').addEventListener('change', (e) => {
            if (!this.data.Alerting.Throttling) this.data.Alerting.Throttling = {};
            this.data.Alerting.Throttling.Enabled = e.target.checked;
            this.markAsChanged();
        });
        
        // Number inputs
        ['maxAlertsPerHour', 'infoSuppression', 'warningSuppression', 'errorSuppression'].forEach(id => {
            document.getElementById(id)?.addEventListener('change', (e) => {
                if (!this.data.Alerting.Throttling) this.data.Alerting.Throttling = {};
                
                const fieldMap = {
                    'maxAlertsPerHour': 'MaxAlertsPerHour',
                    'infoSuppression': 'InformationalSuppressionMinutes',
                    'warningSuppression': 'WarningSuppressionMinutes',
                    'errorSuppression': 'ErrorSuppressionMinutes'
                };
                
                this.data.Alerting.Throttling[fieldMap[id]] = parseInt(e.target.value) || 0;
                this.markAsChanged();
            });
        });
        
        // Global suppressions (inverted logic - checked = enabled, unchecked = suppressed)
        document.querySelectorAll('.global-suppression').forEach(input => {
            input.addEventListener('change', (e) => {
                const channel = e.target.dataset.channel;
                if (!this.data.Alerting.SuppressedChannels) {
                    this.data.Alerting.SuppressedChannels = [];
                }
                
                const idx = this.data.Alerting.SuppressedChannels.indexOf(channel);
                if (e.target.checked && idx > -1) {
                    // Remove from suppressed (enable)
                    this.data.Alerting.SuppressedChannels.splice(idx, 1);
                } else if (!e.target.checked && idx === -1) {
                    // Add to suppressed (disable)
                    this.data.Alerting.SuppressedChannels.push(channel);
                }
                
                e.target.parentElement.classList.toggle('enabled', e.target.checked);
                this.markAsChanged();
            });
        });
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // EXPORT SETTINGS
    // ═══════════════════════════════════════════════════════════════════════════════
    
    renderExportSettings() {
        const exportSettings = this.data.ExportSettings || {};
        const intervals = exportSettings.ExportIntervals || {};
        const retention = exportSettings.Retention || {};
        
        document.getElementById('exportEnabled').checked = exportSettings.Enabled !== false;
        document.getElementById('outputDirectory').value = exportSettings.OutputDirectory || '';
        document.getElementById('fileNamePattern').value = exportSettings.FileNamePattern || '';
        document.getElementById('exportIntervalMinutes').value = intervals.IntervalMinutes || 5;
        document.getElementById('exportOnAlert').checked = intervals.OnAlertTrigger !== false;
        document.getElementById('exportOnDemand').checked = intervals.OnDemand !== false;
        document.getElementById('maxAgeHours').value = retention.MaxAgeHours || 720;
        document.getElementById('maxFileCount').value = retention.MaxFileCount || 1000;
        document.getElementById('compressionEnabled').checked = retention.CompressionEnabled !== false;
        
        this.bindExportEvents();
    }
    
    bindExportEvents() {
        const self = this;
        
        document.getElementById('exportEnabled').addEventListener('change', function(e) {
            self.data.ExportSettings.Enabled = e.target.checked;
            self.markAsChanged();
        });
        
        document.getElementById('outputDirectory').addEventListener('change', function(e) {
            self.data.ExportSettings.OutputDirectory = e.target.value;
            self.markAsChanged();
        });
        
        document.getElementById('fileNamePattern').addEventListener('change', function(e) {
            self.data.ExportSettings.FileNamePattern = e.target.value;
            self.markAsChanged();
        });
        
        document.getElementById('exportIntervalMinutes').addEventListener('change', function(e) {
            if (!self.data.ExportSettings.ExportIntervals) self.data.ExportSettings.ExportIntervals = {};
            self.data.ExportSettings.ExportIntervals.IntervalMinutes = parseInt(e.target.value) || 5;
            self.markAsChanged();
        });
        
        document.getElementById('exportOnAlert').addEventListener('change', function(e) {
            if (!self.data.ExportSettings.ExportIntervals) self.data.ExportSettings.ExportIntervals = {};
            self.data.ExportSettings.ExportIntervals.OnAlertTrigger = e.target.checked;
            self.markAsChanged();
        });
        
        document.getElementById('exportOnDemand').addEventListener('change', function(e) {
            if (!self.data.ExportSettings.ExportIntervals) self.data.ExportSettings.ExportIntervals = {};
            self.data.ExportSettings.ExportIntervals.OnDemand = e.target.checked;
            self.markAsChanged();
        });
        
        document.getElementById('maxAgeHours').addEventListener('change', function(e) {
            if (!self.data.ExportSettings.Retention) self.data.ExportSettings.Retention = {};
            self.data.ExportSettings.Retention.MaxAgeHours = parseInt(e.target.value) || 720;
            self.markAsChanged();
        });
        
        document.getElementById('maxFileCount').addEventListener('change', function(e) {
            if (!self.data.ExportSettings.Retention) self.data.ExportSettings.Retention = {};
            self.data.ExportSettings.Retention.MaxFileCount = parseInt(e.target.value) || 1000;
            self.markAsChanged();
        });
        
        document.getElementById('compressionEnabled').addEventListener('change', function(e) {
            if (!self.data.ExportSettings.Retention) self.data.ExportSettings.Retention = {};
            self.data.ExportSettings.Retention.CompressionEnabled = e.target.checked;
            self.markAsChanged();
        });
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // PERFORMANCE SCALING
    // ═══════════════════════════════════════════════════════════════════════════════
    
    renderPerformanceScaling() {
        const scaling = this.data.PerformanceScaling || {};
        
        document.getElementById('scalingEnabled').checked = scaling.Enabled !== false;
        document.getElementById('lowCapacityPattern').value = scaling.LowCapacityServerPattern || '-app$';
        document.getElementById('intervalMultiplier').value = scaling.IntervalMultiplier || 4;
        document.getElementById('startupDelayMultiplier').value = scaling.StartupDelayMultiplier || 4;
        document.getElementById('applyToExportIntervals').checked = scaling.ApplyToExportIntervals !== false;
        document.getElementById('applyToCleanupIntervals').checked = scaling.ApplyToCleanupIntervals !== false;
        document.getElementById('minIntervalSeconds').value = scaling.MinimumIntervalSeconds || 30;
        document.getElementById('maxIntervalSeconds').value = scaling.MaximumIntervalSeconds || 86400;
        
        this.bindScalingEvents();
    }
    
    bindScalingEvents() {
        const self = this;
        
        const ensureScaling = () => {
            if (!self.data.PerformanceScaling) self.data.PerformanceScaling = {};
        };
        
        document.getElementById('scalingEnabled').addEventListener('change', function(e) {
            ensureScaling();
            self.data.PerformanceScaling.Enabled = e.target.checked;
            self.markAsChanged();
        });
        
        document.getElementById('lowCapacityPattern').addEventListener('change', function(e) {
            ensureScaling();
            self.data.PerformanceScaling.LowCapacityServerPattern = e.target.value;
            self.markAsChanged();
        });
        
        document.getElementById('intervalMultiplier').addEventListener('change', function(e) {
            ensureScaling();
            self.data.PerformanceScaling.IntervalMultiplier = parseFloat(e.target.value) || 4;
            self.markAsChanged();
        });
        
        document.getElementById('startupDelayMultiplier').addEventListener('change', function(e) {
            ensureScaling();
            self.data.PerformanceScaling.StartupDelayMultiplier = parseFloat(e.target.value) || 4;
            self.markAsChanged();
        });
        
        document.getElementById('applyToExportIntervals').addEventListener('change', function(e) {
            ensureScaling();
            self.data.PerformanceScaling.ApplyToExportIntervals = e.target.checked;
            self.markAsChanged();
        });
        
        document.getElementById('applyToCleanupIntervals').addEventListener('change', function(e) {
            ensureScaling();
            self.data.PerformanceScaling.ApplyToCleanupIntervals = e.target.checked;
            self.markAsChanged();
        });
        
        document.getElementById('minIntervalSeconds').addEventListener('change', function(e) {
            ensureScaling();
            self.data.PerformanceScaling.MinimumIntervalSeconds = parseInt(e.target.value) || 30;
            self.markAsChanged();
        });
        
        document.getElementById('maxIntervalSeconds').addEventListener('change', function(e) {
            ensureScaling();
            self.data.PerformanceScaling.MaximumIntervalSeconds = parseInt(e.target.value) || 86400;
            self.markAsChanged();
        });
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // COMMON UI
    // ═══════════════════════════════════════════════════════════════════════════════
    
    toggleCard(header) {
        const card = header.closest('.form-card');
        card.classList.toggle('collapsed');
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
            this.renderChannels();
            this.renderThrottling();
            this.renderExportSettings();
            this.renderPerformanceScaling();
            this.hideJsonModal();
            this.setStatus('JSON changes applied', 'success');
        } catch (e) {
            this.setStatus(`Error applying JSON: ${e.message}`, 'error');
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════════════
    // SAVE MODAL
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
}

// Initialize editor
const editor = new AlertSettingsEditor();
editor.init();
