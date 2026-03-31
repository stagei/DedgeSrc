/**
 * Script Runner - Execute predefined scripts on remote servers
 */

class ScriptRunner {
    constructor() {
        this.servers = [];
        this.selectedServers = new Set();
        this.typePatterns = [];
        this.envPatterns = [];
        this.activeTypeFilters = new Set();
        this.activeEnvFilters = new Set();
        this.results = [];
        this.username = '';
        
        this.init();
    }
    
    async init() {
        // Apply theme from localStorage
        this.applyTheme();
        
        // Get username from URL params
        const params = new URLSearchParams(window.location.search);
        this.username = params.get('user') || 'Unknown';
        document.getElementById('userInfo').textContent = `User: ${this.username}`;
        
        // Setup event listeners
        this.setupEventListeners();
        
        // Load server list
        await this.loadServers();
        
        this.updateStatus('Ready', '');
    }
    
    applyTheme() {
        const theme = localStorage.getItem('theme') || 'dark';
        document.documentElement.setAttribute('data-theme', theme);
        document.body.setAttribute('data-theme', theme);
    }
    
    setupEventListeners() {
        // Theme toggle
        document.getElementById('themeToggle').addEventListener('click', () => {
            const current = document.documentElement.getAttribute('data-theme');
            const newTheme = current === 'dark' ? 'light' : 'dark';
            document.documentElement.setAttribute('data-theme', newTheme);
            document.body.setAttribute('data-theme', newTheme);
            localStorage.setItem('theme', newTheme);
        });
        
        // Select/Clear all buttons
        document.getElementById('selectAllBtn').addEventListener('click', () => this.selectAllVisible());
        document.getElementById('clearAllBtn').addEventListener('click', () => this.clearAllSelections());
        
        // Script name input
        const scriptInput = document.getElementById('scriptName');
        scriptInput.addEventListener('input', () => this.updateExecuteButton());
        scriptInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                document.getElementById('executeBtn').click();
            }
        });
        
        // Execute button
        document.getElementById('executeBtn').addEventListener('click', () => this.showConfirmation());
        
        // Clear results button
        document.getElementById('clearResultsBtn').addEventListener('click', () => this.clearResults());
        
        // Confirmation modal
        document.getElementById('closeConfirmModal').addEventListener('click', () => this.hideConfirmation());
        document.getElementById('cancelConfirmBtn').addEventListener('click', () => this.hideConfirmation());
        document.getElementById('confirmExecuteBtn').addEventListener('click', () => this.executeScript());
        
        // Close modal on overlay click
        document.getElementById('confirmModal').addEventListener('click', (e) => {
            if (e.target.classList.contains('modal-overlay')) {
                this.hideConfirmation();
            }
        });
    }
    
    async loadServers() {
        this.updateStatus('Loading servers...', '');
        
        try {
            const response = await fetch('api/script/servers');
            if (!response.ok) {
                throw new Error(`Failed to load servers: ${response.status}`);
            }
            
            const data = await response.json();
            this.servers = data.servers || [];
            this.typePatterns = data.typePatterns || [];
            this.envPatterns = data.envPatterns || [];
            
            this.renderFilters();
            this.renderServerList();
            this.updateStatus(`Loaded ${this.servers.length} servers`, 'success');
        } catch (error) {
            console.error('Failed to load servers:', error);
            this.updateStatus(`Error: ${error.message}`, 'error');
            
            // Show error in filters area
            document.getElementById('typeFilters').innerHTML = 
                '<span class="loading-text" style="color: var(--danger-color);">Failed to load servers</span>';
        }
    }
    
    renderFilters() {
        // Render type filters
        const typeContainer = document.getElementById('typeFilters');
        typeContainer.innerHTML = this.typePatterns.map(p => `
            <span class="filter-chip" data-filter="type" data-value="${p.pattern}">
                ${p.pattern} <span class="chip-count">(${p.count})</span>
            </span>
        `).join('');
        
        // Render env filters
        const envContainer = document.getElementById('envFilters');
        envContainer.innerHTML = this.envPatterns.map(p => `
            <span class="filter-chip" data-filter="env" data-value="${p.pattern}">
                ${p.pattern} <span class="chip-count">(${p.count})</span>
            </span>
        `).join('');
        
        // Add click handlers
        document.querySelectorAll('.filter-chip').forEach(chip => {
            chip.addEventListener('click', () => this.toggleFilter(chip));
        });
    }
    
    toggleFilter(chip) {
        const filterType = chip.dataset.filter;
        const value = chip.dataset.value;
        
        const activeSet = filterType === 'type' ? this.activeTypeFilters : this.activeEnvFilters;
        
        if (activeSet.has(value)) {
            activeSet.delete(value);
            chip.classList.remove('active');
        } else {
            activeSet.add(value);
            chip.classList.add('active');
        }
        
        this.renderServerList();
    }
    
    getFilteredServers() {
        return this.servers.filter(server => {
            // If no type filters active, show all types
            const matchesType = this.activeTypeFilters.size === 0 || 
                this.activeTypeFilters.has(server.typePattern);
            
            // If no env filters active, show all envs
            const matchesEnv = this.activeEnvFilters.size === 0 || 
                this.activeEnvFilters.has(server.envPattern);
            
            return matchesType && matchesEnv;
        });
    }
    
    renderServerList() {
        const container = document.getElementById('serverList');
        const filtered = this.getFilteredServers();
        
        document.getElementById('matchingServerCount').textContent = 
            `${filtered.length} server${filtered.length !== 1 ? 's' : ''} match filters`;
        
        if (filtered.length === 0) {
            container.innerHTML = '<div class="empty-state" style="padding: 1rem;"><p>No servers match the selected filters</p></div>';
            return;
        }
        
        container.innerHTML = filtered.map(server => `
            <label class="server-item ${this.selectedServers.has(server.name) ? 'selected' : ''}">
                <input type="checkbox" 
                       ${this.selectedServers.has(server.name) ? 'checked' : ''} 
                       data-server="${server.name}">
                <span class="server-name">${server.name}</span>
            </label>
        `).join('');
        
        // Add change handlers
        container.querySelectorAll('input[type="checkbox"]').forEach(cb => {
            cb.addEventListener('change', (e) => {
                const serverName = e.target.dataset.server;
                const item = e.target.closest('.server-item');
                
                if (e.target.checked) {
                    this.selectedServers.add(serverName);
                    item.classList.add('selected');
                } else {
                    this.selectedServers.delete(serverName);
                    item.classList.remove('selected');
                }
                
                this.updateSelectedCount();
                this.updateExecuteButton();
            });
        });
        
        this.updateSelectedCount();
    }
    
    selectAllVisible() {
        const filtered = this.getFilteredServers();
        filtered.forEach(s => this.selectedServers.add(s.name));
        this.renderServerList();
        this.updateExecuteButton();
    }
    
    clearAllSelections() {
        this.selectedServers.clear();
        this.renderServerList();
        this.updateExecuteButton();
    }
    
    updateSelectedCount() {
        const count = this.selectedServers.size;
        const badge = document.getElementById('selectedServerCount');
        badge.textContent = `${count} selected`;
        badge.className = 'badge ' + (count > 0 ? 'badge-enabled' : 'badge-default');
    }
    
    updateExecuteButton() {
        const scriptName = document.getElementById('scriptName').value.trim();
        const hasServers = this.selectedServers.size > 0;
        document.getElementById('executeBtn').disabled = !scriptName || !hasServers;
    }
    
    showConfirmation() {
        const scriptName = document.getElementById('scriptName').value.trim();
        const mode = document.querySelector('input[name="mode"]:checked').value;
        const servers = Array.from(this.selectedServers).sort();
        
        document.getElementById('confirmMode').textContent = mode === 'run' ? 'run-psh' : 'inst-psh';
        document.getElementById('confirmScript').textContent = scriptName;
        document.getElementById('confirmServerCount').textContent = `${servers.length} server${servers.length !== 1 ? 's' : ''}`;
        document.getElementById('confirmServerList').textContent = servers.join('\n');
        
        document.getElementById('confirmModal').classList.remove('hidden');
    }
    
    hideConfirmation() {
        document.getElementById('confirmModal').classList.add('hidden');
    }
    
    async executeScript() {
        this.hideConfirmation();
        
        const scriptName = document.getElementById('scriptName').value.trim();
        const mode = document.querySelector('input[name="mode"]:checked').value;
        const servers = Array.from(this.selectedServers).sort();
        const timestamp = new Date();
        
        // Hide empty state
        document.getElementById('emptyState')?.remove();
        
        // Add pending rows for all servers
        const resultsGrid = document.getElementById('resultsGrid');
        const batchId = Date.now();
        
        servers.forEach(server => {
            const resultId = `result-${batchId}-${server}`;
            const row = this.createResultRow(resultId, server, scriptName, mode, timestamp);
            resultsGrid.insertBefore(row, resultsGrid.firstChild);
        });
        
        this.updateStatus(`Executing ${scriptName} on ${servers.length} servers...`, 'warning');
        
        // Track pending executions for polling
        this.pendingExecutions = this.pendingExecutions || new Map();
        
        // Execute on all servers in parallel (start scripts)
        const startPromises = servers.map(async (server) => {
            const resultId = `result-${batchId}-${server}`;
            try {
                const response = await fetch('api/script/execute', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        server,
                        mode,
                        scriptName,
                        requestedBy: this.username
                    })
                });
                
                const data = await response.json();
                
                // If we got an executionId, start polling
                if (data.executionId) {
                    this.pendingExecutions.set(resultId, {
                        server,
                        executionId: data.executionId,
                        startTime: Date.now()
                    });
                    this.updateResultRowPolling(resultId, 'Script started, waiting for completion...');
                } else if (data.success === false) {
                    // Immediate error (e.g., script not found)
                    this.updateResultRow(resultId, data);
                }
                
                return { server, resultId, ...data };
            } catch (error) {
                const errorResult = {
                    success: false,
                    error: error.message,
                    durationSeconds: 0
                };
                this.updateResultRow(resultId, errorResult);
                return { server, resultId, ...errorResult };
            }
        });
        
        await Promise.all(startPromises);
        
        // Start polling for pending executions
        if (this.pendingExecutions.size > 0) {
            this.updateStatus(`Scripts started on ${this.pendingExecutions.size} servers. Polling for results...`, 'warning');
            this.startPolling();
        } else {
            // All failed immediately
            this.updateStatus('All scripts failed to start', 'error');
            this.updateResultsSummary(0, servers.length, 0);
        }
    }
    
    updateResultRowPolling(id, message) {
        const row = document.getElementById(id);
        if (!row) return;
        
        const outputContent = row.querySelector('.output-content');
        if (outputContent) {
            outputContent.textContent = message;
        }
    }
    
    startPolling() {
        // Poll every 30 seconds
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
        }
        
        // Do an initial poll immediately
        this.pollPendingExecutions();
        
        // Then poll every 30 seconds
        this.pollingInterval = setInterval(() => {
            this.pollPendingExecutions();
        }, 30000);
    }
    
    async pollPendingExecutions() {
        if (!this.pendingExecutions || this.pendingExecutions.size === 0) {
            this.stopPolling();
            return;
        }
        
        const pollPromises = Array.from(this.pendingExecutions.entries()).map(async ([resultId, info]) => {
            try {
                const url = `api/script/status/${info.server}/${info.executionId}?requestedBy=${encodeURIComponent(this.username)}`;
                const response = await fetch(url);
                const data = await response.json();
                
                if (data.isRunning) {
                    // Still running - update output if available
                    const elapsed = ((Date.now() - info.startTime) / 1000).toFixed(0);
                    let message = `Running for ${elapsed}s...`;
                    if (data.output) {
                        message = data.output;
                    }
                    this.updateResultRowPolling(resultId, message);
                    
                    // Update duration display
                    const row = document.getElementById(resultId);
                    if (row) {
                        const duration = row.querySelector('.result-duration');
                        if (duration) {
                            duration.textContent = `${elapsed}s`;
                        }
                    }
                } else {
                    // Completed - update final result
                    this.updateResultRow(resultId, {
                        success: data.success ?? data.exitCode === 0,
                        output: data.output,
                        error: data.exitCode !== 0 ? `Exit code: ${data.exitCode}` : null,
                        durationSeconds: data.durationSeconds
                    });
                    this.pendingExecutions.delete(resultId);
                }
            } catch (error) {
                console.error(`Error polling ${info.server}:`, error);
                // Keep trying
            }
        });
        
        await Promise.all(pollPromises);
        
        // Update summary
        this.updatePollingSummary();
        
        // Stop polling if all done
        if (this.pendingExecutions.size === 0) {
            this.stopPolling();
        }
    }
    
    updatePollingSummary() {
        const rows = document.querySelectorAll('.result-row');
        let success = 0, error = 0, pending = 0;
        
        rows.forEach(row => {
            if (row.classList.contains('pending')) {
                pending++;
            } else {
                const indicator = row.querySelector('.status-indicator');
                if (indicator?.textContent === '🟢') {
                    success++;
                } else {
                    error++;
                }
            }
        });
        
        this.updateResultsSummary(success, error, pending);
        
        if (pending === 0) {
            this.updateStatus(`Completed: ${success} success, ${error} error`, 
                error > 0 ? 'error' : 'success');
        } else {
            this.updateStatus(`Running: ${pending} pending, ${success} success, ${error} error`, 'warning');
        }
    }
    
    stopPolling() {
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            this.pollingInterval = null;
        }
        this.updatePollingSummary();
    }
    
    createResultRow(id, server, script, mode, timestamp) {
        const row = document.createElement('div');
        row.className = 'result-row pending';
        row.id = id;
        row.innerHTML = `
            <div class="result-header" onclick="scriptRunner.toggleResultRow('${id}')">
                <div class="status-indicator status-pending">🟡</div>
                <div class="result-server">${server}</div>
                <div class="result-timestamp">${timestamp.toLocaleTimeString()}</div>
                <div class="result-script">${script}</div>
                <div class="result-mode ${mode}">${mode}</div>
                <div class="result-duration">...</div>
            </div>
            <div class="result-output">
                <div class="output-content">Executing...</div>
            </div>
        `;
        return row;
    }
    
    updateResultRow(id, result) {
        const row = document.getElementById(id);
        if (!row) return;
        
        row.classList.remove('pending');
        
        const statusIndicator = row.querySelector('.status-indicator');
        const outputContent = row.querySelector('.output-content');
        const duration = row.querySelector('.result-duration');
        
        if (result.success) {
            statusIndicator.textContent = '🟢';
            statusIndicator.className = 'status-indicator status-success';
            outputContent.textContent = result.output || 'Script executed successfully (no output)';
            outputContent.classList.add('success');
            outputContent.classList.remove('error');
        } else {
            statusIndicator.textContent = '🔴';
            statusIndicator.className = 'status-indicator status-error';
            outputContent.textContent = result.error || 'Unknown error';
            outputContent.classList.add('error');
            outputContent.classList.remove('success');
        }
        
        if (result.durationSeconds !== undefined) {
            duration.textContent = `${result.durationSeconds.toFixed(1)}s`;
        }
    }
    
    toggleResultRow(id) {
        const row = document.getElementById(id);
        if (row) {
            row.classList.toggle('expanded');
        }
    }
    
    updateResultsSummary(success, error, pending) {
        const badge = document.getElementById('resultsSummary');
        const total = success + error + pending;
        
        if (total === 0) {
            badge.textContent = '';
            badge.className = 'badge';
            return;
        }
        
        badge.textContent = `${success} ✓ ${error} ✗ ${pending} ⏳`;
        
        if (pending > 0) {
            badge.className = 'badge badge-pending';
        } else if (error > 0 && success > 0) {
            badge.className = 'badge badge-mixed';
        } else if (error > 0) {
            badge.className = 'badge badge-error';
        } else {
            badge.className = 'badge badge-success';
        }
    }
    
    clearResults() {
        const resultsGrid = document.getElementById('resultsGrid');
        resultsGrid.innerHTML = `
            <div class="empty-state" id="emptyState">
                <div class="empty-icon">📋</div>
                <h3>No Executions Yet</h3>
                <p>Select servers and run a script to see results here.</p>
            </div>
        `;
        this.updateResultsSummary(0, 0, 0);
    }
    
    updateStatus(message, type) {
        const statusBar = document.getElementById('statusBar');
        const statusMessage = document.getElementById('statusMessage');
        
        statusMessage.textContent = message;
        statusBar.className = 'status-bar' + (type ? ` ${type}` : '');
    }
}

// Card collapse toggle
function toggleCard(header) {
    const card = header.closest('.form-card');
    card.classList.toggle('collapsed');
}

// Initialize
let scriptRunner;
document.addEventListener('DOMContentLoaded', () => {
    scriptRunner = new ScriptRunner();
});
