/**
 * DB2 Detail Window - Pop-out window for database-specific monitoring
 * Uses shared AlertsRenderer component for consistent alert display
 */
class Db2DetailWindow {
    constructor() {
        // Parse URL parameters
        const params = new URLSearchParams(window.location.search);
        this.instanceName = params.get('instance') || '';
        this.databaseName = params.get('database') || '';
        this.serverUrl = params.get('server') || '';
        
        // Check if auto-refresh is explicitly disabled via URL parameter (for User role)
        const autoRefreshParam = params.get('autorefresh');
        this.autoRefreshDisabledByRole = autoRefreshParam === 'false';
        
        // Refresh settings - OFF by default as requested
        this.refreshInterval = 10000; // 10 seconds
        this.autoRefresh = false;
        this.refreshTimer = null;
        
        // Current state
        this.currentState = null;
        this.isLoading = false;
        
        // Initialize shared AlertsRenderer
        this.alertsRenderer = new AlertsRenderer({
            maxAlerts: 25,
            showCopyButtons: true,
            showExpandable: true,
            showModal: false, // No modal in pop-out
            showCategory: false // Save space
        });
        
        // Inherit dark mode from parent/localStorage
        this.initializeDarkMode();
    }
    
    /**
     * Initialize dark mode based on parent window or localStorage
     * Dashboard uses data-theme="dark" attribute on document element
     */
    initializeDarkMode() {
        // Check localStorage for dark mode preference (shared with main dashboard)
        const savedTheme = localStorage.getItem('dashboard-theme');
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        
        // Apply dark mode if saved or system prefers it
        // Dashboard uses data-theme attribute on document element
        if (savedTheme === 'dark' || (!savedTheme && prefersDark)) {
            document.documentElement.setAttribute('data-theme', 'dark');
        } else {
            document.documentElement.removeAttribute('data-theme');
        }
    }
    
    /**
     * Initialize the pop-out window
     */
    async initialize() {
        // Validate parameters
        if (!this.instanceName || !this.databaseName) {
            this.showError('Missing instance or database parameter in URL');
            return;
        }
        
        // Set page title
        document.title = `DB2: ${this.databaseName} (${this.instanceName})`;
        document.getElementById('db-title').textContent = 
            `${this.databaseName} @ ${this.instanceName}`;
        
        // Bind UI events
        this.bindEvents();
        
        // Initial data load
        await this.refreshAllData();
        
        // Only start auto-refresh if enabled (OFF by default)
        if (this.autoRefresh) {
            this.startAutoRefresh();
        }
    }
    
    /**
     * Bind UI event handlers
     */
    bindEvents() {
        // Refresh button
        document.getElementById('btn-refresh')?.addEventListener('click', () => {
            this.refreshAllData();
        });
        
        // Auto-refresh toggle
        const toggle = document.getElementById('auto-refresh-toggle');
        if (toggle) {
            // Check if auto-refresh is disabled by role
            if (this.autoRefreshDisabledByRole) {
                toggle.checked = false;
                toggle.disabled = true;
                toggle.title = 'Auto-refresh disabled for your role';
                this.autoRefresh = false;
            } else {
                toggle.checked = this.autoRefresh;
                toggle.addEventListener('change', (e) => {
                    this.autoRefresh = e.target.checked;
                    if (this.autoRefresh) {
                        this.startAutoRefresh();
                    } else {
                        this.stopAutoRefresh();
                    }
                });
            }
        }
    }
    
    /**
     * Start auto-refresh timer
     */
    startAutoRefresh() {
        this.stopAutoRefresh();
        if (this.autoRefresh) {
            this.refreshTimer = setInterval(() => this.refreshAllData(), this.refreshInterval);
        }
    }
    
    /**
     * Stop auto-refresh timer
     */
    stopAutoRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = null;
        }
    }
    
    /**
     * Set loading state
     */
    setLoadingState(isLoading) {
        this.isLoading = isLoading;
        const overlay = document.getElementById('loading-overlay');
        if (overlay) {
            overlay.classList.toggle('visible', isLoading);
        }
    }
    
    /**
     * Refresh all data from server
     */
    async refreshAllData() {
        if (this.isLoading) return;
        
        this.setLoadingState(true);
        
        try {
            // Fetch database state (includes alerts)
            const state = await this.fetchDatabaseState();
            this.currentState = state;
            
            // Render all panels
            this.renderHeader(state);
            this.renderSessionsPanel(state);
            this.renderPerformancePanel(state);
            this.renderHealthPanel(state);
            this.renderTxLogPanel(state);
            this.renderMemoryPanel(state);
            this.renderTopSqlPanel(state);
            this.renderTablespacePanel(state);
            this.renderAlertsPanel(state.recentAlerts || []);
            this.renderBlockingPanel(state);
            this.renderLongOpsPanel(state);
            this.renderDiagPanel(state);
            
            // Update last refresh time
            this.updateLastRefreshTime();
            
        } catch (error) {
            console.error('Failed to refresh data:', error);
            this.showError(`Failed to load data: ${error.message}`);
        } finally {
            this.setLoadingState(false);
        }
    }
    
    /**
     * Fetch database state from API
     * The API runs on the ServerMonitor agent (port 8999), not the dashboard
     */
    async fetchDatabaseState() {
        // Build URL to agent API (port 8999)
        const agentUrl = this.serverUrl ? `http://${this.serverUrl}:8999` : '';
        const url = `${agentUrl}/api/db2/${encodeURIComponent(this.instanceName)}/${encodeURIComponent(this.databaseName)}/state`;
        
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`API returned ${response.status}: ${response.statusText}`);
        }
        return await response.json();
    }
    
    /**
     * Render header with status indicator
     */
    renderHeader(state) {
        const indicator = document.getElementById('status-indicator');
        const title = document.getElementById('db-title');
        
        if (indicator) {
            if (!state.isInstanceRunning) {
                indicator.textContent = '🔴';
                indicator.title = 'Instance not running';
            } else if (!state.isActive) {
                indicator.textContent = '🟡';
                indicator.title = 'Database not active';
            } else {
                indicator.textContent = '🟢';
                indicator.title = 'Database active';
            }
        }
        
        if (title) {
            title.textContent = `${this.databaseName} @ ${this.instanceName}`;
        }
    }
    
    /**
     * Render sessions panel
     */
    renderSessionsPanel(state) {
        const container = document.getElementById('sessions-stats');
        if (!container) return;
        
        const sessions = state.totalSessions || 0;
        const users = state.uniqueUsers || 0;
        const executing = state.executingSessions || 0;
        const idle = state.idleSessions || 0;
        const waiting = state.waitingSessions || 0;
        
        container.innerHTML = `
            <div class="stat-card">
                <div class="stat-value">${sessions}</div>
                <div class="stat-label">Total Sessions</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${users}</div>
                <div class="stat-label">Unique Users</div>
            </div>
            <div class="stat-card ${executing > 10 ? 'warning' : ''}">
                <div class="stat-value">${executing}</div>
                <div class="stat-label">Executing</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${idle}</div>
                <div class="stat-label">Idle</div>
            </div>
            <div class="stat-card ${waiting > 5 ? 'warning' : ''}">
                <div class="stat-value">${waiting}</div>
                <div class="stat-label">Waiting</div>
            </div>
        `;
    }
    
    /**
     * Render performance panel
     */
    renderPerformancePanel(state) {
        const container = document.getElementById('performance-stats');
        if (!container) return;
        
        const bpRatio = state.bufferPoolHitRatio;
        const dbSize = state.databaseSizeGb;
        const diagLogMb = state.db2DiagLogSizeMb;
        
        const bpClass = bpRatio == null ? '' : 
                        bpRatio >= 95 ? 'success' : 
                        bpRatio >= 90 ? 'warning' : 'critical';
        
        const diagLogClass = diagLogMb == null ? '' :
                             diagLogMb >= 500 ? 'critical' :
                             diagLogMb >= 100 ? 'warning' : '';
        
        const diagLogDisplay = diagLogMb == null ? 'N/A' :
                               diagLogMb >= 1024 ? (diagLogMb / 1024).toFixed(1) + ' GB' :
                               diagLogMb.toFixed(0) + ' MB';
        
        container.innerHTML = `
            <div class="stat-card ${bpClass}">
                <div class="stat-value">${bpRatio != null ? bpRatio.toFixed(1) + '%' : 'N/A'}</div>
                <div class="stat-label">Buffer Pool Hit Ratio</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${dbSize != null ? dbSize.toFixed(1) + ' GB' : 'N/A'}</div>
                <div class="stat-label">Database Size</div>
            </div>
            <div class="stat-card ${diagLogClass}">
                <div class="stat-value">${diagLogDisplay}</div>
                <div class="stat-label">db2diag.log</div>
            </div>
        `;
    }
    
    /**
     * Render alerts panel using shared AlertsRenderer
     */
    renderAlertsPanel(alerts) {
        const body = document.getElementById('alerts-body');
        const countBadge = document.getElementById('alerts-count');
        
        if (countBadge) {
            countBadge.textContent = alerts.length;
            countBadge.classList.toggle('has-alerts', alerts.length > 0);
            countBadge.classList.toggle('critical', 
                alerts.some(a => a.severity?.toLowerCase() === 'critical'));
        }
        
        if (!body) return;
        
        if (alerts.length === 0) {
            body.innerHTML = '<div class="no-data">✅ No alerts in the last 24 hours</div>';
            return;
        }
        
        // Create table structure
        body.innerHTML = `
            <table class="data-table alerts-table">
                <thead>
                    <tr>
                        <th>Severity</th>
                        <th>Message</th>
                        <th>Context</th>
                        <th>Time</th>
                    </tr>
                </thead>
                <tbody id="alerts-tbody"></tbody>
            </table>
            ${alerts.length > 25 ? `<div class="show-more">Showing 25 of ${alerts.length} alerts</div>` : ''}
        `;
        
        // Use shared renderer
        const tbody = document.getElementById('alerts-tbody');
        if (tbody) {
            this.alertsRenderer.render(tbody, alerts);
        }
    }
    
    /**
     * Render blocking sessions panel
     */
    renderBlockingPanel(state) {
        const body = document.getElementById('blocking-body');
        const countBadge = document.getElementById('blocking-count');
        const blocking = state.blockingSessions || [];
        
        if (countBadge) {
            countBadge.textContent = blocking.length;
            countBadge.classList.toggle('critical', blocking.length > 0);
        }
        
        if (!body) return;
        
        if (blocking.length === 0) {
            body.innerHTML = '<div class="no-data">✅ No blocking sessions</div>';
            return;
        }
        
        body.innerHTML = `
            <table class="data-table">
                <thead>
                    <tr>
                        <th>Blocker Handle</th>
                        <th>Blocker User</th>
                        <th>Blocked</th>
                        <th>Lock Wait (s)</th>
                    </tr>
                </thead>
                <tbody>
                    ${blocking.map(b => `
                        <tr>
                            <td>${this.escapeHtml(b.blockerHandle || '-')}</td>
                            <td>${this.escapeHtml(b.blockerUser || '-')}</td>
                            <td>${this.escapeHtml(b.blockedHandle || '-')}</td>
                            <td>${b.lockWaitSeconds || '-'}</td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        `;
    }
    
    /**
     * Render long running queries panel
     */
    renderLongOpsPanel(state) {
        const body = document.getElementById('longops-body');
        const countBadge = document.getElementById('longops-count');
        const longOps = state.longRunningQueries || [];
        
        if (countBadge) {
            countBadge.textContent = longOps.length;
            countBadge.classList.toggle('warning', longOps.length > 0);
        }
        
        if (!body) return;
        
        if (longOps.length === 0) {
            body.innerHTML = '<div class="no-data">✅ No long running queries</div>';
            return;
        }
        
        body.innerHTML = `
            <table class="data-table">
                <thead>
                    <tr>
                        <th>Handle</th>
                        <th>User</th>
                        <th>Duration (s)</th>
                        <th>State</th>
                    </tr>
                </thead>
                <tbody>
                    ${longOps.map(q => `
                        <tr>
                            <td>${this.escapeHtml(q.applicationHandle || '-')}</td>
                            <td>${this.escapeHtml(q.authId || '-')}</td>
                            <td>${q.elapsedSeconds || '-'}</td>
                            <td>${this.escapeHtml(q.state || '-')}</td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        `;
    }
    
    /**
     * Render diagnostic summary panel
     */
    renderDiagPanel(state) {
        const container = document.getElementById('diag-stats');
        if (!container) return;
        
        const diag = state.diagSummary || {};
        const critical = diag.criticalCount || 0;
        const errors = diag.errorCount || 0;
        const warnings = diag.warningCount || 0;
        const events = diag.eventCount || 0;
        
        container.innerHTML = `
            <div class="stat-card ${critical > 0 ? 'critical' : ''}">
                <div class="stat-value">${critical}</div>
                <div class="stat-label">Critical</div>
            </div>
            <div class="stat-card ${errors > 0 ? 'critical' : ''}">
                <div class="stat-value">${errors}</div>
                <div class="stat-label">Errors</div>
            </div>
            <div class="stat-card ${warnings > 0 ? 'warning' : ''}">
                <div class="stat-value">${warnings}</div>
                <div class="stat-label">Warnings</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${events}</div>
                <div class="stat-label">Events</div>
            </div>
        `;
    }
    
    /**
     * Render database health counters panel
     */
    renderHealthPanel(state) {
        const container = document.getElementById('health-stats');
        if (!container) return;

        const h = state.healthCounters;
        if (!h) {
            container.innerHTML = '<div class="no-data">No health counter data available</div>';
            return;
        }

        const sortRatio = h.totalSorts > 0
            ? ((h.sortOverflows / h.totalSorts) * 100).toFixed(2) + '%'
            : '0%';

        container.innerHTML = `
            <div class="stat-card ${h.deadlocks > 0 ? 'critical' : ''}">
                <div class="stat-value">${this.fmtNum(h.deadlocks)}</div>
                <div class="stat-label">Deadlocks</div>
            </div>
            <div class="stat-card ${h.lockTimeouts > 0 ? 'warning' : ''}">
                <div class="stat-value">${this.fmtNum(h.lockTimeouts)}</div>
                <div class="stat-label">Lock Timeouts</div>
            </div>
            <div class="stat-card ${h.lockEscalations > 0 ? 'warning' : ''}">
                <div class="stat-value">${this.fmtNum(h.lockEscalations)}</div>
                <div class="stat-label">Lock Escalations</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${this.fmtNum(h.totalSorts)}</div>
                <div class="stat-label">Total Sorts</div>
            </div>
            <div class="stat-card ${(h.totalSorts > 0 && h.sortOverflows / h.totalSorts > 0.05) ? 'warning' : ''}">
                <div class="stat-value">${this.fmtNum(h.sortOverflows)}</div>
                <div class="stat-label">Sort Overflows (${sortRatio})</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${this.fmtNum(h.rowsRead)}</div>
                <div class="stat-label">Rows Read</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${this.fmtNum(h.rowsReturned)}</div>
                <div class="stat-label">Rows Returned</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${this.fmtMs(h.totalCpuTimeMs)}</div>
                <div class="stat-label">Total CPU</div>
            </div>
        `;
    }

    /**
     * Render transaction log panel
     */
    renderTxLogPanel(state) {
        const container = document.getElementById('txlog-stats');
        if (!container) return;

        const tl = state.transactionLog;
        if (!tl) {
            container.innerHTML = '<div class="no-data">No transaction log data</div>';
            return;
        }

        const pct = tl.logUtilizationPercent || 0;
        const barColor = pct < 70 ? 'var(--success-color)' : pct < 90 ? 'var(--warning-color)' : 'var(--error-color)';
        const pctClass = pct >= 90 ? 'critical' : pct >= 70 ? 'warning' : 'success';

        container.innerHTML = `
            <div class="stat-card ${pctClass}" style="grid-column: span 2;">
                <div class="stat-value">${pct.toFixed(1)}%</div>
                <div class="stat-label">Log Utilization</div>
                <div class="util-bar-container" style="margin-top:0.5rem;">
                    <div class="util-bar" style="width:${pct}%;background:${barColor};"></div>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${this.fmtKb(tl.totalLogUsedKb)}</div>
                <div class="stat-label">Used</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${this.fmtKb(tl.totalLogAvailableKb)}</div>
                <div class="stat-label">Available</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${this.fmtNum(tl.logReads)}</div>
                <div class="stat-label">Log Reads</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${this.fmtNum(tl.logWrites)}</div>
                <div class="stat-label">Log Writes</div>
            </div>
        `;
    }

    /**
     * Render memory pools panel
     */
    renderMemoryPanel(state) {
        const body = document.getElementById('memory-body');
        if (!body) return;

        const pools = state.memoryPools || [];
        if (pools.length === 0) {
            body.innerHTML = '<div class="no-data">No memory pool data</div>';
            return;
        }

        const totalUsed = pools.reduce((s, p) => s + (p.usedKb || 0), 0);

        body.innerHTML = `
            <div class="memory-total">
                <span>Total DB Memory Used</span>
                <span>${this.fmtKb(totalUsed)}</span>
            </div>
            <table class="data-table">
                <thead><tr><th>Pool Type</th><th>Used</th><th>HWM</th></tr></thead>
                <tbody>
                    ${pools.map(p => `
                        <tr>
                            <td>${this.escapeHtml(p.poolType)}</td>
                            <td>${this.fmtKb(p.usedKb)}</td>
                            <td>${this.fmtKb(p.highWatermarkKb)}</td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        `;
    }

    /**
     * Render top SQL panel
     */
    renderTopSqlPanel(state) {
        const body = document.getElementById('topsql-body');
        const badge = document.getElementById('topsql-count');
        const entries = state.topSql || [];

        if (badge) badge.textContent = entries.length;

        if (!body) return;

        if (entries.length === 0) {
            body.innerHTML = '<div class="no-data">No top SQL data</div>';
            return;
        }

        body.innerHTML = `
            <table class="data-table">
                <thead>
                    <tr>
                        <th>SQL</th>
                        <th>Execs</th>
                        <th>Avg Time</th>
                        <th>Rows Read</th>
                        <th>Total CPU</th>
                    </tr>
                </thead>
                <tbody>
                    ${entries.map(e => `
                        <tr>
                            <td class="sql-text-cell" title="${this.escapeHtml(e.sqlText)}">${this.escapeHtml(e.sqlText)}</td>
                            <td>${this.fmtNum(e.numExecutions)}</td>
                            <td>${this.fmtMs(e.avgExecTimeMs)}</td>
                            <td>${this.fmtNum(e.rowsRead)}</td>
                            <td>${this.fmtMs(e.totalCpuMs)}</td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        `;
    }

    /**
     * Render tablespace utilization panel
     */
    renderTablespacePanel(state) {
        const body = document.getElementById('tablespace-body');
        if (!body) return;

        const tbsp = state.tablespaces || [];
        if (tbsp.length === 0) {
            body.innerHTML = '<div class="no-data">No tablespace data</div>';
            return;
        }

        body.innerHTML = `
            <table class="data-table">
                <thead>
                    <tr>
                        <th>Tablespace</th>
                        <th>Type</th>
                        <th>Used</th>
                        <th>Total</th>
                        <th>Util %</th>
                    </tr>
                </thead>
                <tbody>
                    ${tbsp.map(t => {
                        const pct = t.utilizationPercent || 0;
                        const barColor = pct < 80 ? 'var(--success-color)' : pct < 95 ? 'var(--warning-color)' : 'var(--error-color)';
                        return `
                            <tr>
                                <td>${this.escapeHtml(t.name)}</td>
                                <td>${this.escapeHtml(t.type)}</td>
                                <td>${this.fmtKb(t.usedSizeKb)}</td>
                                <td>${this.fmtKb(t.totalSizeKb)}</td>
                                <td style="min-width:120px;">
                                    <span>${pct.toFixed(1)}%</span>
                                    <div class="util-bar-container" style="margin-top:2px;">
                                        <div class="util-bar" style="width:${pct}%;background:${barColor};"></div>
                                    </div>
                                </td>
                            </tr>
                        `;
                    }).join('')}
                </tbody>
            </table>
        `;
    }

    fmtNum(n) {
        if (n == null) return '0';
        if (n >= 1_000_000_000) return (n / 1_000_000_000).toFixed(1) + 'B';
        if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
        if (n >= 10_000) return (n / 1_000).toFixed(1) + 'K';
        return n.toLocaleString();
    }

    fmtKb(kb) {
        if (kb == null || kb === 0) return '0 KB';
        if (kb >= 1_048_576) return (kb / 1_048_576).toFixed(1) + ' GB';
        if (kb >= 1_024) return (kb / 1_024).toFixed(1) + ' MB';
        return kb.toLocaleString() + ' KB';
    }

    fmtMs(ms) {
        if (ms == null || ms === 0) return '0 ms';
        if (ms >= 3_600_000) return (ms / 3_600_000).toFixed(1) + ' h';
        if (ms >= 60_000) return (ms / 60_000).toFixed(1) + ' min';
        if (ms >= 1_000) return (ms / 1_000).toFixed(1) + ' s';
        return ms.toLocaleString() + ' ms';
    }

    /**
     * Update last refresh time display
     */
    updateLastRefreshTime() {
        const el = document.getElementById('last-refresh');
        if (el) {
            el.textContent = `Last updated: ${new Date().toLocaleTimeString()}`;
        }
    }
    
    /**
     * Show error message
     */
    showError(message) {
        const container = document.querySelector('.popout-container');
        if (!container) return;
        
        // Remove existing error
        const existing = container.querySelector('.error-message');
        if (existing) existing.remove();
        
        // Add error message
        const errorDiv = document.createElement('div');
        errorDiv.className = 'error-message';
        errorDiv.textContent = message;
        container.insertBefore(errorDiv, container.firstChild.nextSibling);
    }
    
    /**
     * Escape HTML special characters
     */
    escapeHtml(text) {
        if (text == null) return '';
        const div = document.createElement('div');
        div.textContent = String(text);
        return div.innerHTML;
    }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    const detailWindow = new Db2DetailWindow();
    detailWindow.initialize();
});
