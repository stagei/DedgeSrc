/**
 * IIS Detail Window - Pop-out window for IIS server monitoring
 * Uses shared AlertsRenderer component for consistent alert display
 */
class IisDetailWindow {
    constructor() {
        const params = new URLSearchParams(window.location.search);
        this.serverUrl = params.get('server') || '';
        
        const autoRefreshParam = params.get('autorefresh');
        this.autoRefreshDisabledByRole = autoRefreshParam === 'false';
        
        this.refreshInterval = 10000;
        this.autoRefresh = false;
        this.refreshTimer = null;
        this.currentState = null;
        this.isLoading = false;
        
        this.alertsRenderer = new AlertsRenderer({
            maxAlerts: 50,
            showCopyButtons: true,
            showExpandable: true,
            showModal: false,
            showCategory: false
        });
        
        this.initializeDarkMode();
    }
    
    initializeDarkMode() {
        const savedTheme = localStorage.getItem('dashboard-theme');
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        if (savedTheme === 'dark' || (!savedTheme && prefersDark)) {
            document.documentElement.setAttribute('data-theme', 'dark');
        } else {
            document.documentElement.removeAttribute('data-theme');
        }
    }
    
    async initialize() {
        document.title = `IIS: ${this.serverUrl || 'Local'}`;
        document.getElementById('iis-title').textContent = `IIS @ ${this.serverUrl || 'localhost'}`;
        
        this.bindEvents();
        await this.refreshAllData();
        
        if (this.autoRefresh) {
            this.startAutoRefresh();
        }
    }
    
    bindEvents() {
        document.getElementById('btn-refresh')?.addEventListener('click', () => {
            this.refreshAllData();
        });
        
        const toggle = document.getElementById('auto-refresh-toggle');
        if (toggle) {
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
    
    startAutoRefresh() {
        this.stopAutoRefresh();
        if (this.autoRefresh) {
            this.refreshTimer = setInterval(() => this.refreshAllData(), this.refreshInterval);
        }
    }
    
    stopAutoRefresh() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = null;
        }
    }
    
    setLoadingState(isLoading) {
        this.isLoading = isLoading;
        const overlay = document.getElementById('loading-overlay');
        if (overlay) {
            overlay.classList.toggle('visible', isLoading);
        }
    }
    
    async refreshAllData() {
        if (this.isLoading) return;
        this.setLoadingState(true);
        
        try {
            const state = await this.fetchIisState();
            this.currentState = state;
            
            this.renderHeader(state);
            this.renderSummaryPanel(state);
            this.renderPoolsPanel(state);
            this.renderSitesPanel(state);
            this.renderAlertsPanel(state.recentAlerts || []);
            this.updateLastRefreshTime();
        } catch (error) {
            console.error('Failed to refresh IIS data:', error);
            this.showError(`Failed to load data: ${error.message}`);
        } finally {
            this.setLoadingState(false);
        }
    }
    
    async fetchIisState() {
        const agentUrl = this.serverUrl ? `http://${this.serverUrl}:8999` : '';
        const url = `${agentUrl}/api/iis/state`;
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`API returned ${response.status}: ${response.statusText}`);
        }
        return await response.json();
    }
    
    renderHeader(state) {
        const indicator = document.getElementById('status-indicator');
        if (indicator) {
            if (!state.isActive) {
                indicator.textContent = '🔴';
                indicator.title = 'IIS not active';
            } else if (state.stoppedAppPools > 0 || state.stoppedSites > 0) {
                indicator.textContent = '🟡';
                indicator.title = 'Some pools or sites are stopped';
            } else {
                indicator.textContent = '🟢';
                indicator.title = 'All sites and pools running';
            }
        }
    }
    
    renderSummaryPanel(state) {
        const container = document.getElementById('summary-stats');
        if (!container) return;
        
        const stoppedPoolsClass = state.stoppedAppPools > 0 ? 'critical' : 'success';
        const stoppedSitesClass = state.stoppedSites > 0 ? 'critical' : 'success';
        
        container.innerHTML = `
            <div class="stat-card">
                <div class="stat-value">${state.totalSites || 0}</div>
                <div class="stat-label">Total Sites</div>
            </div>
            <div class="stat-card ${stoppedSitesClass}">
                <div class="stat-value">${state.runningSites || 0}</div>
                <div class="stat-label">Running Sites</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${state.totalAppPools || 0}</div>
                <div class="stat-label">App Pools</div>
            </div>
            <div class="stat-card ${stoppedPoolsClass}">
                <div class="stat-value">${state.stoppedAppPools || 0}</div>
                <div class="stat-label">Stopped Pools</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">${state.totalWorkerProcesses || 0}</div>
                <div class="stat-label">Workers</div>
            </div>
        `;
        
        // Version info
        const panel = document.getElementById('summary-panel');
        let versionEl = panel?.querySelector('.iis-version-info');
        if (!versionEl && panel) {
            versionEl = document.createElement('div');
            versionEl.className = 'iis-version-info';
            panel.querySelector('.panel-body').appendChild(versionEl);
        }
        if (versionEl) {
            versionEl.textContent = `IIS ${state.iisVersion || '?'} | Collected: ${state.collectedAt ? new Date(state.collectedAt).toLocaleString() : '-'}`;
        }
    }
    
    renderPoolsPanel(state) {
        const body = document.getElementById('pools-body');
        const countBadge = document.getElementById('pools-count');
        const pools = state.appPools || [];
        
        if (countBadge) countBadge.textContent = pools.length;
        if (!body) return;
        
        if (pools.length === 0) {
            body.innerHTML = '<div class="no-data">No application pools found</div>';
            return;
        }
        
        let html = `<table class="data-table">
            <thead><tr>
                <th style="width:25px"></th>
                <th>Name</th>
                <th>State</th>
                <th>Pipeline</th>
                <th>Runtime</th>
                <th>Identity</th>
                <th>Workers</th>
                <th>Memory</th>
            </tr></thead><tbody>`;
        
        for (const pool of pools) {
            const stateIcon = pool.state === 'Started' ? '🟢' : '🔴';
            const stateClass = pool.state === 'Started' ? 'status-running' : 'status-stopped';
            const runtime = pool.managedRuntimeVersion || 'No Managed Code';
            const wps = pool.workerProcesses || [];
            const totalMem = wps.reduce((s, w) => s + (w.privateMemoryMB || 0), 0);
            const poolId = this.escapeHtml(pool.name).replace(/[^a-zA-Z0-9]/g, '_');
            
            html += `
                <tr class="expandable" onclick="iisDetail.toggleRow(this, '${poolId}')">
                    <td><span class="expand-indicator">▶</span></td>
                    <td><strong>${this.escapeHtml(pool.name)}</strong></td>
                    <td><span class="${stateClass}">${stateIcon} ${pool.state}</span></td>
                    <td>${this.escapeHtml(pool.pipelineMode || 'Integrated')}</td>
                    <td>${this.escapeHtml(runtime)}</td>
                    <td>${this.escapeHtml(pool.identityType || '')}${pool.identityUsername ? ' (' + this.escapeHtml(pool.identityUsername) + ')' : ''}</td>
                    <td>${wps.length}</td>
                    <td>${totalMem > 0 ? totalMem.toFixed(0) + ' MB' : '-'}</td>
                </tr>
                <tr class="detail-row hidden" data-detail-id="${poolId}">
                    <td colspan="8">
                        <div class="detail-content">
                            <div class="detail-grid">
                                <div class="detail-item"><span class="detail-label">AUTO START</span><span class="detail-value">${pool.autoStart ? 'Yes' : 'No'}</span></div>
                                <div class="detail-item"><span class="detail-label">32-BIT</span><span class="detail-value">${pool.enable32BitAppOnWin64 ? 'Yes' : 'No'}</span></div>
                                <div class="detail-item"><span class="detail-label">CPU LIMIT</span><span class="detail-value">${pool.cpuLimit > 0 ? pool.cpuLimit + '%' : 'None'}</span></div>
                                <div class="detail-item"><span class="detail-label">MEMORY LIMIT</span><span class="detail-value">${pool.privateMemoryLimitKB > 0 ? Math.round(pool.privateMemoryLimitKB / 1024) + ' MB' : 'None'}</span></div>
                                <div class="detail-item"><span class="detail-label">RECYCLE INTERVAL</span><span class="detail-value">${pool.recyclingTimeIntervalMinutes > 0 ? pool.recyclingTimeIntervalMinutes + ' min' : 'None'}</span></div>
                            </div>
                            ${wps.length > 0 ? `
                            <table class="data-table wp-table">
                                <thead><tr><th>PID</th><th>State</th><th>Memory</th><th>Started</th></tr></thead>
                                <tbody>
                                    ${wps.map(w => `<tr>
                                        <td>${w.processId}</td>
                                        <td>${w.state || 'Running'}</td>
                                        <td>${(w.privateMemoryMB || 0).toFixed(0)} MB</td>
                                        <td>${w.startTime ? new Date(w.startTime).toLocaleString() : '-'}</td>
                                    </tr>`).join('')}
                                </tbody>
                            </table>` : ''}
                        </div>
                    </td>
                </tr>`;
        }
        
        html += '</tbody></table>';
        body.innerHTML = html;
    }
    
    renderSitesPanel(state) {
        const body = document.getElementById('sites-body');
        const countBadge = document.getElementById('sites-count');
        const sites = state.sites || [];
        
        if (countBadge) countBadge.textContent = sites.length;
        if (!body) return;
        
        if (sites.length === 0) {
            body.innerHTML = '<div class="no-data">No sites found</div>';
            return;
        }
        
        let html = `<table class="data-table">
            <thead><tr>
                <th style="width:25px"></th>
                <th>Site Name</th>
                <th>State</th>
                <th>App Pool</th>
                <th>Bindings</th>
                <th>Virtual Apps</th>
            </tr></thead><tbody>`;
        
        for (const site of sites) {
            const stateIcon = site.state === 'Started' ? '🟢' : '🔴';
            const stateClass = site.state === 'Started' ? 'status-running' : 'status-stopped';
            const bindings = (site.bindings || []).map(b => `${b.protocol}://${b.host || '*'}:${b.port}`).join(', ');
            const vapps = site.virtualApps || [];
            const siteId = 'site_' + site.id;
            
            html += `
                <tr class="expandable" onclick="iisDetail.toggleRow(this, '${siteId}')">
                    <td><span class="expand-indicator">▶</span></td>
                    <td><strong>${this.escapeHtml(site.name)}</strong></td>
                    <td><span class="${stateClass}">${stateIcon} ${site.state}</span></td>
                    <td>${this.escapeHtml(site.appPoolName || '')}</td>
                    <td>${this.escapeHtml(bindings)}</td>
                    <td>${vapps.length}</td>
                </tr>
                <tr class="detail-row hidden" data-detail-id="${siteId}">
                    <td colspan="6">
                        <div class="detail-content">
                            <div class="detail-grid">
                                <div class="detail-item"><span class="detail-label">PHYSICAL PATH</span><span class="detail-value" style="font-family:monospace;font-size:0.85em">${this.escapeHtml(site.physicalPathUnc || site.physicalPath || '-')}</span></div>
                                <div class="detail-item"><span class="detail-label">SITE ID</span><span class="detail-value">${site.id}</span></div>
                            </div>
                            ${vapps.length > 0 ? `
                            <table class="data-table wp-table" style="margin-top:0.75rem">
                                <thead><tr><th>Path</th><th>Type</th><th>App Pool</th><th>Install Path (UNC)</th><th>Log Path</th><th>Output Path</th></tr></thead>
                                <tbody>
                                    ${vapps.map(v => `<tr>
                                        <td>${this.escapeHtml(v.path)}</td>
                                        <td>${v.isAspNetCore ? `<span class="badge-aspnet" title="${this.escapeHtml(v.dotNetDll || '')}">ASP.NET Core</span>` : '<span class="badge-static">Static</span>'}</td>
                                        <td>${this.escapeHtml(v.appPoolName || '')}</td>
                                        <td style="max-width:350px;overflow:hidden;text-overflow:ellipsis;font-family:monospace;font-size:0.85em" title="${this.escapeHtml(v.physicalPathUnc || v.physicalPath || '')}">${this.escapeHtml(v.physicalPathUnc || v.physicalPath || '')}</td>
                                        <td style="max-width:300px;overflow:hidden;text-overflow:ellipsis;font-family:monospace;font-size:0.85em" title="${this.escapeHtml(v.logPath || '')}">${v.logPath ? this.escapeHtml(v.logPath) : '<span style="opacity:0.4">-</span>'}</td>
                                        <td style="max-width:300px;overflow:hidden;text-overflow:ellipsis;font-family:monospace;font-size:0.85em" title="${this.escapeHtml(v.outputPath || '')}">${v.outputPath ? this.escapeHtml(v.outputPath) : '<span style="opacity:0.4">-</span>'}</td>
                                    </tr>`).join('')}
                                </tbody>
                            </table>` : ''}
                        </div>
                    </td>
                </tr>`;
        }
        
        html += '</tbody></table>';
        body.innerHTML = html;
    }
    
    renderAlertsPanel(alerts) {
        const body = document.getElementById('alerts-body');
        const countBadge = document.getElementById('alerts-count');
        
        if (countBadge) {
            countBadge.textContent = alerts.length;
            countBadge.className = `badge${alerts.length > 0 ? ' has-alerts' : ''}`;
            if (alerts.some(a => (a.severity || '').toLowerCase() === 'critical' || a.severity === 2)) {
                countBadge.className = 'badge critical';
            }
        }
        
        if (!body) return;
        
        if (alerts.length === 0) {
            body.innerHTML = '<div class="no-data">No IIS alerts in the last 24 hours</div>';
            return;
        }
        
        this.alertsRenderer.render(body, alerts);
    }
    
    toggleRow(rowElement, id) {
        const tbody = rowElement.closest('tbody');
        const detailRow = tbody.querySelector(`tr[data-detail-id="${id}"]`);
        if (detailRow) {
            detailRow.classList.toggle('hidden');
            rowElement.classList.toggle('expanded');
            const indicator = rowElement.querySelector('.expand-indicator');
            if (indicator) {
                indicator.textContent = detailRow.classList.contains('hidden') ? '▶' : '▼';
            }
        }
    }
    
    updateLastRefreshTime() {
        const el = document.getElementById('last-refresh');
        if (el) {
            el.textContent = `Last updated: ${new Date().toLocaleTimeString()}`;
        }
    }
    
    showError(message) {
        const container = document.querySelector('.popout-container');
        if (container) {
            const existing = container.querySelector('.error-message');
            if (existing) existing.remove();
            
            const errorDiv = document.createElement('div');
            errorDiv.className = 'error-message';
            errorDiv.textContent = message;
            container.insertBefore(errorDiv, container.children[1]);
        }
    }
    
    escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
}

const iisDetail = new IisDetailWindow();
document.addEventListener('DOMContentLoaded', () => iisDetail.initialize());
