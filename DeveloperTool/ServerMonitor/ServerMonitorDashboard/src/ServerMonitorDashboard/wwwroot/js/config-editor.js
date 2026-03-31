/**
 * ServerMonitor Config Editor
 * Provides a JSON editor with validation, formatting, and section navigation
 */

class ConfigEditor {
    constructor(options) {
        this.configType = options.configType;
        this.apiEndpoint = options.apiEndpoint;
        this.title = options.title;
        this.originalContent = '';
        this.hasUnsavedChanges = false;
        this.isValid = true;
    }

    async init() {
        console.log(`Initializing ConfigEditor for ${this.configType}`);
        
        // Apply theme from localStorage
        this.applyTheme();
        
        // Setup event listeners
        this.setupEventListeners();
        
        // Load configuration
        await this.loadConfig();
    }

    applyTheme() {
        const savedTheme = localStorage.getItem('theme') || 'light';
        document.documentElement.setAttribute('data-theme', savedTheme);
    }

    setupEventListeners() {
        // Editor change detection
        const editor = document.getElementById('jsonEditor');
        editor.addEventListener('input', () => this.onEditorChange());
        editor.addEventListener('scroll', () => this.syncLineNumbers());
        editor.addEventListener('keydown', (e) => this.handleKeyDown(e));

        // Toolbar buttons
        document.getElementById('formatBtn').addEventListener('click', () => this.formatJson());
        document.getElementById('collapseAllBtn').addEventListener('click', () => this.collapseAll());
        document.getElementById('expandAllBtn').addEventListener('click', () => this.expandAll());
        
        // Header buttons
        document.getElementById('reloadBtn').addEventListener('click', () => this.reloadConfig());
        document.getElementById('saveBtn').addEventListener('click', () => this.showSaveModal());
        
        // Save modal
        document.getElementById('confirmSaveBtn').addEventListener('click', () => this.saveConfig());

        // Warn before leaving with unsaved changes
        window.addEventListener('beforeunload', (e) => {
            if (this.hasUnsavedChanges) {
                e.preventDefault();
                e.returnValue = '';
            }
        });
    }

    async loadConfig() {
        this.setStatus('Loading configuration...', 'info');
        
        try {
            const response = await fetch(this.apiEndpoint);
            const data = await response.json();
            
            if (!data.success) {
                this.setStatus(`Error: ${data.error}`, 'error');
                return;
            }

            const editor = document.getElementById('jsonEditor');
            editor.value = data.content;
            this.originalContent = data.content;
            this.hasUnsavedChanges = false;
            
            // Update file info
            this.updateFileInfo(data);
            
            // Update line numbers
            this.updateLineNumbers();
            
            // Build section navigation
            this.buildSectionNav(data.content);
            
            // Validate JSON
            this.validateJson();
            
            this.setStatus('Configuration loaded successfully', 'success');
            
        } catch (error) {
            console.error('Error loading config:', error);
            this.setStatus(`Failed to load configuration: ${error.message}`, 'error');
        }
    }

    async reloadConfig() {
        if (this.hasUnsavedChanges) {
            if (!confirm('You have unsaved changes. Reload anyway?')) {
                return;
            }
        }
        await this.loadConfig();
    }

    async saveConfig() {
        this.closeSaveModal();
        this.setStatus('Saving configuration...', 'info');
        
        const editor = document.getElementById('jsonEditor');
        const content = editor.value;
        
        // Validate before saving
        if (!this.validateJson()) {
            this.setStatus('Cannot save: Invalid JSON format', 'error');
            return;
        }
        
        try {
            const response = await fetch(this.apiEndpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    content: content,
                    editedBy: 'dashboard'
                })
            });
            
            const data = await response.json();
            
            if (!data.success) {
                this.setStatus(`Save failed: ${data.error}`, 'error');
                return;
            }
            
            this.originalContent = content;
            this.hasUnsavedChanges = false;
            this.updateHeader();
            
            // Update file info
            this.updateFileInfo(data);
            
            const backupInfo = data.backupPath ? ` (backup created)` : '';
            this.setStatus(`Configuration saved successfully${backupInfo}`, 'success');
            
        } catch (error) {
            console.error('Error saving config:', error);
            this.setStatus(`Save failed: ${error.message}`, 'error');
        }
    }

    onEditorChange() {
        const editor = document.getElementById('jsonEditor');
        this.hasUnsavedChanges = editor.value !== this.originalContent;
        this.updateHeader();
        this.updateLineNumbers();
        this.validateJson();
    }

    validateJson() {
        const editor = document.getElementById('jsonEditor');
        const validationStatus = document.getElementById('validationStatus');
        
        try {
            JSON.parse(editor.value);
            validationStatus.textContent = '✅ Valid JSON';
            validationStatus.classList.remove('invalid');
            this.isValid = true;
            return true;
        } catch (error) {
            validationStatus.textContent = `❌ ${error.message}`;
            validationStatus.classList.add('invalid');
            this.isValid = false;
            return false;
        }
    }

    formatJson() {
        const editor = document.getElementById('jsonEditor');
        
        try {
            const parsed = JSON.parse(editor.value);
            editor.value = JSON.stringify(parsed, null, 2);
            this.onEditorChange();
            this.setStatus('JSON formatted', 'success');
        } catch (error) {
            this.setStatus('Cannot format: Invalid JSON', 'error');
        }
    }

    collapseAll() {
        // For now, just format with minimal indentation
        const editor = document.getElementById('jsonEditor');
        try {
            const parsed = JSON.parse(editor.value);
            editor.value = JSON.stringify(parsed, null, 2);
            this.onEditorChange();
        } catch (error) {
            // Ignore if invalid
        }
    }

    expandAll() {
        // Format with full indentation
        this.formatJson();
    }

    handleKeyDown(e) {
        const editor = e.target;
        
        // Tab key - insert spaces instead of tab
        if (e.key === 'Tab') {
            e.preventDefault();
            const start = editor.selectionStart;
            const end = editor.selectionEnd;
            editor.value = editor.value.substring(0, start) + '  ' + editor.value.substring(end);
            editor.selectionStart = editor.selectionEnd = start + 2;
            this.onEditorChange();
        }
        
        // Ctrl+S - save
        if (e.ctrlKey && e.key === 's') {
            e.preventDefault();
            this.showSaveModal();
        }
        
        // Ctrl+Shift+F - format
        if (e.ctrlKey && e.shiftKey && e.key === 'F') {
            e.preventDefault();
            this.formatJson();
        }
    }

    updateLineNumbers() {
        const editor = document.getElementById('jsonEditor');
        const lineNumbers = document.getElementById('lineNumbers');
        
        const lines = editor.value.split('\n');
        const lineCount = lines.length;
        
        let html = '';
        for (let i = 1; i <= lineCount; i++) {
            html += `${i}\n`;
        }
        
        lineNumbers.textContent = html;
    }

    syncLineNumbers() {
        const editor = document.getElementById('jsonEditor');
        const lineNumbers = document.getElementById('lineNumbers');
        lineNumbers.scrollTop = editor.scrollTop;
    }

    buildSectionNav(content) {
        const sectionList = document.getElementById('sectionList');
        
        try {
            const parsed = JSON.parse(content);
            const sections = Object.keys(parsed);
            
            if (sections.length === 0) {
                sectionList.innerHTML = '<li class="loading">No sections found</li>';
                return;
            }
            
            const icons = {
                'version': '📌',
                'lastUpdated': '🕐',
                'environments': '🌍',
                'people': '👥',
                'Kestrel': '🌐',
                'Logging': '📝',
                'NLog': '📝',
                'ExportSettings': '📤',
                'Alerting': '🚨',
                'General': '⚙️',
                'Runtime': '⏱️',
                'RestApi': '🔌',
                'PerformanceScaling': '🐢',
                'Surveillance': '📊'
            };
            
            sectionList.innerHTML = sections.map((section, index) => {
                const icon = icons[section] || '📁';
                return `<li data-section="${section}" data-index="${index}">
                    <span class="section-icon">${icon}</span>
                    <span>${section}</span>
                </li>`;
            }).join('');
            
            // Add click handlers for navigation
            sectionList.querySelectorAll('li').forEach(item => {
                item.addEventListener('click', () => this.navigateToSection(item.dataset.section));
            });
            
        } catch (error) {
            sectionList.innerHTML = '<li class="loading">Parse error</li>';
        }
    }

    navigateToSection(sectionName) {
        const editor = document.getElementById('jsonEditor');
        const content = editor.value;
        
        // Find the section in the JSON
        const pattern = new RegExp(`"${sectionName}"\\s*:`, 'g');
        const match = pattern.exec(content);
        
        if (match) {
            // Calculate line number
            const textBefore = content.substring(0, match.index);
            const lineNumber = textBefore.split('\n').length;
            
            // Scroll to line
            const lines = content.split('\n');
            let charPosition = 0;
            for (let i = 0; i < lineNumber - 1; i++) {
                charPosition += lines[i].length + 1;
            }
            
            editor.focus();
            editor.setSelectionRange(match.index, match.index + match[0].length);
            
            // Scroll editor to show the selection
            const lineHeight = 21; // Approximate line height
            editor.scrollTop = (lineNumber - 5) * lineHeight;
            
            // Update active state in nav
            document.querySelectorAll('.section-list li').forEach(li => li.classList.remove('active'));
            document.querySelector(`.section-list li[data-section="${sectionName}"]`)?.classList.add('active');
        }
    }

    updateFileInfo(data) {
        const fileInfo = document.getElementById('fileInfo');
        
        if (data.lastModified) {
            const date = new Date(data.lastModified);
            const formatted = date.toLocaleString();
            const size = data.fileSize ? ` (${this.formatBytes(data.fileSize)})` : '';
            fileInfo.textContent = `Last modified: ${formatted}${size}`;
        } else {
            fileInfo.textContent = 'File loaded';
        }
    }

    formatBytes(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    updateHeader() {
        const header = document.querySelector('.editor-header');
        if (this.hasUnsavedChanges) {
            header.classList.add('unsaved');
            document.title = `* ${this.title} - ServerMonitor`;
        } else {
            header.classList.remove('unsaved');
            document.title = `${this.title} - ServerMonitor`;
        }
    }

    setStatus(message, type = 'info') {
        const statusBar = document.getElementById('statusBar');
        const statusMessage = document.getElementById('statusMessage');
        
        statusBar.className = 'status-bar';
        if (type === 'success') statusBar.classList.add('success');
        if (type === 'error') statusBar.classList.add('error');
        if (type === 'warning') statusBar.classList.add('warning');
        
        statusMessage.textContent = message;
        
        // Auto-clear success messages after 5 seconds
        if (type === 'success') {
            setTimeout(() => {
                if (statusMessage.textContent === message) {
                    this.setStatus('Ready', 'info');
                }
            }, 5000);
        }
    }

    showSaveModal() {
        if (!this.isValid) {
            this.setStatus('Cannot save: Please fix JSON errors first', 'error');
            return;
        }
        
        if (!this.hasUnsavedChanges) {
            this.setStatus('No changes to save', 'info');
            return;
        }
        
        document.getElementById('saveModal').classList.remove('hidden');
    }

    closeSaveModal() {
        document.getElementById('saveModal').classList.add('hidden');
    }
}

// Global function for modal close button
function closeSaveModal() {
    document.getElementById('saveModal').classList.add('hidden');
}
