/**
 * ServerMonitor Dashboard - Main Application
 */

class DashboardApp {
    constructor() {
        this.servers = [];
        this.selectedServer = null;
        this.currentSnapshot = null;
        
        // Load saved settings from localStorage (with defaults)
        const savedSettings = this.loadSettings();
        this.autoRefresh = savedSettings.autoRefresh;
        this.refreshInterval = savedSettings.refreshInterval;
        
        this.minRefreshInterval = 5;
        this.refreshTimer = null;
        this.countdownTimer = null;
        this.countdownValue = 0;
        this.isLoading = false;
        this.triggerStatusTimer = null;
        this.triggerStatusInterval = 30000;  // 30 seconds for background polling
        this.controlPanelPollTimer = null;
        this.controlPanelPollInterval = 3000;  // 3 seconds when control panel is open
        this.serverListRefreshTimer = null;
        this.serverListRefreshInterval = 30000;  // 30 seconds for server list refresh
        
        // SQL Error Log Viewer
        this.sqlErrorLogFiles = [];
        this.monacoEditor = null;
        this.monacoInitialized = false;
        this.sqlErrorLogLanguageRegistered = false;
        
        // DB2 Dashboard config (fetched from agent)
        this.db2DashboardConfig = { enablePopout: true }; // Default: enabled
        
        // IIS Dashboard config (fetched from agent)
        this.iisDashboardConfig = { enablePopout: true }; // Default: enabled
        
        // Active Alerts Polling
        this.alertPollingTimer = null;
        this.alertPollingInterval = 30000; // 30 seconds default, updated from config
        this.activeAlerts = [];
        this.alertDropdownOpen = false;
        
        // Production filter settings (from config)
        this.productionPatterns = ['^p-no1']; // Default, updated from API
        this.showOnlyProduction = true; // Default, updated from API/user preference
        this.lastAlertData = null; // Cache for re-rendering on filter change
    }

    async init() {
        console.log('Dashboard initializing...');
        
        // Initialize theme
        this.themeManager = new ThemeManager();
        
        // Setup event listeners
        this.setupEventListeners();
        
        // IMPORTANT: Determine target server BEFORE loadServers() to prevent auto-selection
        // Priority: 1. URL parameter  2. localStorage  3. Auto-select first online
        const targetServer = this.getTargetServerFromUrlOrStorage();
        if (targetServer) {
            console.log(`Target server from URL/storage: ${targetServer}`);
            this.selectedServer = targetServer; // Pre-set to prevent auto-selection
        }
        
        // Load initial data (won't auto-select because selectedServer is already set)
        await this.loadServers();
        
        // Now properly select and load the server
        if (this.selectedServer) {
            // Verify server exists in list and select it
            const serverExists = this.servers.some(s => 
                s.name.toLowerCase() === this.selectedServer.toLowerCase()
            );
            if (serverExists) {
                // Find the correct case version of the server name
                const correctName = this.servers.find(s => 
                    s.name.toLowerCase() === this.selectedServer.toLowerCase()
                )?.name || this.selectedServer;
                
                await this.selectServer(correctName, true);
            } else {
                console.warn(`Server from URL/storage not found: ${this.selectedServer}`);
                this.selectedServer = null;
                // Let auto-selection happen
                const firstOnline = this.servers.find(s => s.isAlive);
                if (firstOnline) {
                    await this.selectServer(firstOnline.name, true);
                } else if (this.servers.length > 0) {
                    await this.selectServer(this.servers[0].name, true);
                }
            }
        }
        
        // Handle alertId from URL if present (for deep linking to specific alert)
        this.handleAlertIdFromUrl();
        
        // Start auto-refresh if enabled
        if (this.autoRefresh) {
            this.startAutoRefresh();
        }
        
        // Check trigger file status on load and start periodic checking
        await this.checkTriggerStatus();
        this.startTriggerStatusTimer();
        
        // Start live server status updates via SSE
        this.startServerStatusStream();
        
        // Setup and start active alerts polling
        this.setupAlertDropdown();
        this.startAlertPolling();
        
        console.log('Dashboard initialized');
    }
    
    /**
     * Connect to Server-Sent Events stream for live server status updates.
     * Falls back to polling if SSE is not available.
     */
    startServerStatusStream() {
        if (typeof EventSource === 'undefined') {
            console.log('SSE not supported, falling back to polling');
            this.startServerListRefresh();
            return;
        }
        
        console.log('Connecting to server status stream...');
        this.statusEventSource = new EventSource('api/servers/stream');
        
        this.statusEventSource.onopen = () => {
            console.log('SSE connection established');
        };
        
        this.statusEventSource.onmessage = (event) => {
            try {
                const data = JSON.parse(event.data);
                this.handleServerStatusEvent(data);
            } catch (e) {
                console.warn('Failed to parse SSE message:', e);
            }
        };
        
        this.statusEventSource.onerror = (error) => {
            console.warn('SSE connection error, will reconnect automatically');
        };
    }
    
    /**
     * Handle server status events from SSE stream
     */
    handleServerStatusEvent(data) {
        switch (data.type) {
            case 'init':
                // Initial state - replace all servers
                if (data.servers) {
                    this.servers = data.servers;
                    this.renderServerDropdown();
                    this.updateStatusSummary();
                    console.log(`SSE init: received ${data.servers.length} servers`);
                }
                break;
                
            case 'checking':
            case 'status':
                // Single server update
                if (data.server) {
                    const index = this.servers.findIndex(s => s.name === data.server.name);
                    if (index >= 0) {
                        this.servers[index] = data.server;
                    } else {
                        this.servers.push(data.server);
                    }
                    
                    // Update dropdown for this server only (more efficient)
                    this.updateServerInDropdown(data.server);
                    this.updateStatusSummary();
                }
                break;
                
            case 'heartbeat':
                // Heartbeat - no action needed
                break;
                
            default:
                console.log('Unknown SSE event type:', data.type);
        }
    }
    
    /**
     * Update a single server in the dropdown without re-rendering everything
     */
    updateServerInDropdown(server) {
        const select = document.getElementById('serverSelect');
        if (!select) return;
        
        // Find existing option
        let option = Array.from(select.options).find(o => o.value === server.name);
        
        // Determine icon and status text
        const status = server.statusText || (server.isAlive ? 'online' : 'offline');
        let icon, statusText;
        switch (status) {
            case 'online':
                icon = '🟢';
                statusText = '';
                break;
            case 'checking':
                icon = '🟡';
                statusText = ' (checking...)';
                break;
            case 'unknown':
                icon = '🟠';
                statusText = ' (unknown)';
                break;
            case 'offline':
            default:
                icon = '🟣';
                statusText = ' (OFFLINE)';
                break;
        }
        
        const newText = `${icon} ${server.name}${statusText}`;
        
        if (option) {
            option.textContent = newText;
            option.dataset.status = status;
        }
    }
    
    /**
     * Get target server from URL parameter or localStorage
     * Priority: URL parameter > localStorage
     * @returns {string|null} Server name or null if not found
     */
    getTargetServerFromUrlOrStorage() {
        const urlParams = new URLSearchParams(window.location.search);
        const serverFromUrl = urlParams.get('server');
        
        if (serverFromUrl) {
            console.log(`Server from URL parameter: ${serverFromUrl}`);
            // Save to localStorage for next visit
            this.saveLastServer(serverFromUrl);
            return serverFromUrl;
        }
        
        // Check localStorage for last used server
        const lastServer = this.getLastServer();
        if (lastServer) {
            console.log(`Server from localStorage: ${lastServer}`);
            return lastServer;
        }
        
        return null;
    }
    
    /**
     * Handle alertId from URL for deep linking
     */
    handleAlertIdFromUrl() {
        const urlParams = new URLSearchParams(window.location.search);
        const alertId = urlParams.get('alertId');
        
        if (alertId) {
            console.log(`URL parameter: alertId=${alertId}`);
            this.focusAlertId = alertId;
            
            // Remove alertId from URL (one-time use, keep server)
            const url = new URL(window.location.href);
            url.searchParams.delete('alertId');
            window.history.replaceState({}, document.title, url.toString());
        }
    }
    
    /**
     * Save last used server to localStorage
     */
    saveLastServer(serverName) {
        try {
            localStorage.setItem('servermonitor_lastServer', serverName);
        } catch (e) {
            console.warn('Could not save last server to localStorage:', e);
        }
    }
    
    /**
     * Get last used server from localStorage
     */
    getLastServer() {
        try {
            return localStorage.getItem('servermonitor_lastServer');
        } catch (e) {
            console.warn('Could not read last server from localStorage:', e);
            return null;
        }
    }
    
    /**
     * Start the 30-second timer to periodically check trigger file status
     * This ensures the UI stays in sync when files are added/removed by other dashboards
     */
    startTriggerStatusTimer() {
        // Clear any existing timer
        if (this.triggerStatusTimer) {
            clearInterval(this.triggerStatusTimer);
        }
        
        // Check every 30 seconds
        this.triggerStatusTimer = setInterval(() => {
            this.checkTriggerStatus();
        }, this.triggerStatusInterval);
        
        console.log('Trigger status timer started (30s interval)');
    }
    
    /**
     * Stop the trigger status timer
     */
    stopTriggerStatusTimer() {
        if (this.triggerStatusTimer) {
            clearInterval(this.triggerStatusTimer);
            this.triggerStatusTimer = null;
        }
    }
    
    /**
     * Start the 30-second timer to refresh the server list
     * This ensures the dropdown shows current online/offline status
     */
    startServerListRefresh() {
        // Clear any existing timer
        if (this.serverListRefreshTimer) {
            clearInterval(this.serverListRefreshTimer);
        }
        
        // Refresh server list every 30 seconds
        this.serverListRefreshTimer = setInterval(() => {
            this.refreshServerListQuiet();
        }, this.serverListRefreshInterval);
        
        console.log('Server list refresh timer started (30s interval)');
    }
    
    /**
     * Stop the server list refresh timer
     */
    stopServerListRefresh() {
        if (this.serverListRefreshTimer) {
            clearInterval(this.serverListRefreshTimer);
            this.serverListRefreshTimer = null;
        }
    }
    
    /**
     * Refresh server list quietly (no UI blocking)
     * Preserves the current selection in the dropdown
     */
    async refreshServerListQuiet() {
        try {
            // Store current selection and scroll position
            const select = document.getElementById('serverSelect');
            const previousSelection = this.selectedServer;
            const previousScrollTop = select?.scrollTop || 0;
            
            // Fetch fresh server data (use GET for cached, faster response)
            const response = await fetch('api/servers');
            if (!response.ok) return;
            
            const data = await response.json();
            const newServers = data.servers || [];
            
            // Check if there are any actual changes in status
            let hasChanges = newServers.length !== this.servers.length;
            if (!hasChanges) {
                for (const newServer of newServers) {
                    const oldServer = this.servers.find(s => s.name === newServer.name);
                    if (!oldServer || oldServer.isAlive !== newServer.isAlive) {
                        hasChanges = true;
                        break;
                    }
                }
            }
            
            // Only update UI if there are changes
            if (hasChanges) {
                console.log('Server status changed, updating dropdown...');
                this.servers = newServers;
                this.currentAgentVersion = data.currentAgentVersion;
                
                // Re-render the dropdown
                this.renderServerDropdown();
                this.updateStatusSummary();
                
                // Restore selection
                if (previousSelection && this.servers.some(s => s.name === previousSelection)) {
                    if (select) {
                        select.value = previousSelection;
                        this.selectedServer = previousSelection;
                    }
                }
                
                // Restore scroll position (for long dropdown lists)
                if (select) {
                    select.scrollTop = previousScrollTop;
                }
            }
        } catch (error) {
            console.error('Error refreshing server list:', error);
        }
    }

    /**
     * Check if stop/start/reinstall/disable trigger files exist and update header indicators
     */
    async checkTriggerStatus() {
        try {
            const response = await fetch('api/trigger-status');
            if (!response.ok) return;
            
            const status = await response.json();
            
            // Update disable file indicator
            const disableIndicator = document.getElementById('disableFileIndicator');
            if (disableIndicator) {
                if (status.disableFileExists) {
                    disableIndicator.classList.remove('hidden');
                    const reason = status.disableReason || 'No reason specified';
                    const created = status.disableFileCreated ? new Date(status.disableFileCreated).toLocaleString() : 'Unknown';
                    disableIndicator.title = `Agents DISABLED since ${created}\nReason: ${reason}\nClick to enable`;
                } else {
                    disableIndicator.classList.add('hidden');
                }
            }
            
            // Update stop file indicator
            const stopIndicator = document.getElementById('stopFileIndicator');
            if (stopIndicator) {
                if (status.stopFileExists) {
                    stopIndicator.classList.remove('hidden');
                    const created = status.stopFileCreated ? new Date(status.stopFileCreated).toLocaleString() : 'Unknown';
                    stopIndicator.title = `Stop file active since ${created}\nClick to remove`;
                } else {
                    stopIndicator.classList.add('hidden');
                }
            }
            
            // Update start file indicator
            const startIndicator = document.getElementById('startFileIndicator');
            if (startIndicator) {
                if (status.startFileExists) {
                    startIndicator.classList.remove('hidden');
                    const created = status.startFileCreated ? new Date(status.startFileCreated).toLocaleString() : 'Unknown';
                    startIndicator.title = `Start file active since ${created}\nClick to remove`;
                } else {
                    startIndicator.classList.add('hidden');
                }
            }
            
            // Update reinstall file indicator
            const reinstallIndicator = document.getElementById('reinstallFileIndicator');
            if (reinstallIndicator) {
                if (status.reinstallFileExists) {
                    reinstallIndicator.classList.remove('hidden');
                    const version = status.reinstallVersion || 'Unknown';
                    const created = status.reinstallFileCreated ? new Date(status.reinstallFileCreated).toLocaleString() : 'Unknown';
                    reinstallIndicator.textContent = `📦 v${version}`;
                    reinstallIndicator.title = `Reinstall v${version} pending since ${created}\nClick to remove`;
                } else {
                    reinstallIndicator.classList.add('hidden');
                }
            }
            
            // Also update control panel if it's open
            const modal = document.getElementById('controlPanelModal');
            if (modal && !modal.classList.contains('hidden')) {
                this.updateControlPanelStatus();
            }
        } catch (error) {
            console.error('Error checking trigger status:', error);
        }
    }

    /**
     * Remove the global stop trigger file
     */
    async removeStopTrigger() {
        if (!confirm('Remove the stop trigger file?\n\nThis will cancel the pending stop command for all agents.')) {
            return;
        }
        
        try {
            const response = await fetch('api/stop', { method: 'DELETE' });
            const result = await response.json();
            
            if (result.success) {
                await this.checkTriggerStatus();
            } else {
                alert(`❌ Failed to remove stop trigger: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }

    /**
     * Remove the global reinstall trigger file
     */
    async removeReinstallTrigger() {
        if (!confirm('Remove the reinstall trigger file?\n\nThis will cancel the pending update for agents that haven\'t processed it yet.')) {
            return;
        }
        
        try {
            const response = await fetch('api/reinstall', { method: 'DELETE' });
            const result = await response.json();
            
            if (result.success) {
                await this.checkTriggerStatus();
            } else {
                alert(`❌ Failed to remove reinstall trigger: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Remove the global start trigger file
     */
    async removeStartTrigger() {
        if (!confirm('Remove the start trigger file?\n\nThis will cancel the pending start command for agents that haven\'t processed it yet.')) {
            return;
        }
        
        try {
            const response = await fetch('api/start', { method: 'DELETE' });
            const result = await response.json();
            
            if (result.success) {
                await this.checkTriggerStatus();
            } else {
                alert(`❌ Failed to remove start trigger: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Toggle disable/enable for all agents
     * If disabled, removes the disable file. If enabled, creates the disable file.
     */
    async toggleDisable() {
        try {
            // First check current status
            const statusResponse = await fetch('api/trigger-status');
            const status = await statusResponse.json();
            
            if (status.disableFileExists) {
                // Currently disabled - enable agents
                await this.removeDisableTrigger();
            } else {
                // Currently enabled - disable agents
                await this.createDisableTrigger();
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Create the disable trigger file to prevent all agents from starting
     */
    async createDisableTrigger() {
        const reason = prompt('Enter reason for disabling all agents:', 'Maintenance');
        if (reason === null) return; // User cancelled
        
        try {
            const response = await fetch('api/disable', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ reason: reason || 'Disabled via Dashboard' })
            });
            const result = await response.json();
            
            if (result.success) {
                await this.checkTriggerStatus();
                alert('⛔ All ServerMonitor agents are now DISABLED.\n\nAgents will not run until this is removed.');
            } else {
                alert(`❌ Failed to create disable trigger: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Remove the disable trigger file to allow agents to start
     */
    async removeDisableTrigger() {
        if (!confirm('Enable all ServerMonitor agents?\n\nThis will allow agents to start running again.')) {
            return;
        }
        
        try {
            const response = await fetch('api/disable', { method: 'DELETE' });
            const result = await response.json();
            
            if (result.success) {
                await this.checkTriggerStatus();
            } else {
                alert(`❌ Failed to enable agents: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }

    /**
     * Open the config folder in Windows Explorer
     */
    openConfigFolder() {
        const configPath = '\\dedge-server\\DedgeCommon\\Software\\Config\\ServerMonitor';
        
        // Create a link element that will trigger the folder open
        // Note: This only works if the browser allows shell: protocol or if we use an API
        try {
            // Try to copy path to clipboard as fallback
            navigator.clipboard.writeText(configPath).then(() => {
                alert(`📂 Config folder path copied to clipboard:\n\n${configPath}\n\nPaste in File Explorer to open.`);
            }).catch(() => {
                // If clipboard fails, just show the path
                alert(`📂 Config folder:\n\n${configPath}\n\nCopy this path and paste in File Explorer.`);
            });
        } catch (error) {
            alert(`📂 Config folder:\n\n${configPath}\n\nCopy this path and paste in File Explorer.`);
        }
    }

    /**
     * Create a stop file directly (prompts for server selection)
     */
    async createStopFileDirect() {
        const serverName = prompt(
            '🛑 Create Stop Trigger File\n\n' +
            'Enter server name to stop a specific server,\n' +
            'or leave empty / enter "*" to stop ALL agents:',
            '*'
        );
        
        if (serverName === null) {
            return; // User cancelled
        }
        
        const target = serverName.trim() || '*';
        const isGlobal = target === '*' || target.toUpperCase() === 'ALL';
        
        const confirmMsg = isGlobal 
            ? '⚠️ Create GLOBAL stop file?\n\nThis will stop ALL running agents on ALL servers!'
            : `🛑 Create stop file for ${target}?\n\nThis will stop the agent on that server.`;
        
        if (!confirm(confirmMsg)) {
            return;
        }
        
        try {
            const response = await fetch('api/stop', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ 
                    serverName: target,
                    reason: 'Created via Dashboard Control Panel'
                })
            });
            
            const result = await response.json();
            
            if (result.success) {
                await this.checkTriggerStatus();
                alert(`✅ Stop trigger file created!\n\n${result.message}`);
            } else {
                alert(`❌ Failed to create stop file: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }

    /**
     * Update the browser URL to include the selected server for bookmarking
     * Uses replaceState to avoid page reload and update history
     * 
     * Example URLs:
     * - http://localhost:8998/?server=t-no1inltst-db
     * - http://dashboard:8998/?server=p-no1fkmprd-db
     */
    updateUrl(serverName) {
        const url = new URL(window.location.href);
        
        if (serverName) {
            url.searchParams.set('server', serverName);
            // Update page title for better bookmarks
            document.title = `${serverName} - ServerMonitor Dashboard`;
        } else {
            url.searchParams.delete('server');
            document.title = 'ServerMonitor Dashboard';
        }
        
        // Remove alertId if present (one-time use)
        url.searchParams.delete('alertId');
        
        // Update URL without reloading
        window.history.replaceState({}, document.title, url.toString());
    }

    setupEventListeners() {
        // Apply saved settings to UI controls
        const autoRefreshCheckbox = document.getElementById('autoRefresh');
        if (autoRefreshCheckbox) {
            autoRefreshCheckbox.checked = this.autoRefresh;
        }
        
        const refreshIntervalSelect = document.getElementById('refreshInterval');
        if (refreshIntervalSelect) {
            refreshIntervalSelect.value = this.refreshInterval.toString();
        }
        
        // Server dropdown
        document.getElementById('serverSelect')?.addEventListener('change', (e) => {
            this.selectServer(e.target.value);
        });

        // Auto-refresh toggle
        document.getElementById('autoRefresh')?.addEventListener('change', (e) => {
            this.autoRefresh = e.target.checked;
            this.saveSettings(); // Persist to localStorage
            if (this.autoRefresh) {
                this.startAutoRefresh();
            } else {
                this.stopAutoRefresh();
            }
        });

        // Refresh interval
        document.getElementById('refreshInterval')?.addEventListener('change', (e) => {
            let interval = parseInt(e.target.value);
            
            // Check role-based restrictions
            if (window.RolePermissions) {
                const role = window.RolePermissions.getCurrentRole();
                if (role === 'User') {
                    // User role: only allow 5/10/30/60 min intervals
                    const allowedIntervals = [300, 600, 1800, 3600];
                    if (!allowedIntervals.includes(interval)) {
                        interval = 300; // Default to 5 minutes
                        e.target.value = '300';
                    }
                }
            }
            
            this.refreshInterval = Math.max(interval, this.minRefreshInterval);
            this.saveSettings(); // Persist to localStorage
            if (this.autoRefresh) {
                this.startAutoRefresh();
            }
        });

        // Manual refresh button
        const refreshBtn = document.getElementById('refreshBtn');
        if (refreshBtn) {
            refreshBtn.addEventListener('click', (e) => {
                e.preventDefault();
                console.log('Refresh button clicked');
                this.manualRefresh();
            });
        }

        // Theme toggle (checkbox-based)
        const themeToggle = document.getElementById('themeToggle');
        if (themeToggle) {
            // Set initial checkbox state based on current theme
            themeToggle.checked = this.themeManager.theme === 'dark';
            themeToggle.addEventListener('change', () => {
                this.themeManager.setTheme(themeToggle.checked ? 'dark' : 'light');
            });
        }

        // Reinstall button
        document.getElementById('reinstallBtn')?.addEventListener('click', () => {
            this.triggerReinstall();
        });

        // Control Panel
        this.setupControlPanel();
        
        // Tools Panel
        this.setupToolsPanel();
        
        // Log Viewer Modal
        this.setupLogViewer();
    }
    
    /**
     * Setup the Log Viewer modal with Monaco editor
     */
    setupLogViewer() {
        const modal = document.getElementById('logViewerModal');
        const closeBtn = document.getElementById('closeLogViewer');
        const copyBtn = document.getElementById('logViewerCopyBtn');
        
        if (!modal) return;
        
        // Close button
        closeBtn?.addEventListener('click', () => {
            this.closeLogViewer();
        });
        
        // Copy button
        copyBtn?.addEventListener('click', () => {
            this.copyLogContent();
        });
        
        // Close on overlay click
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                this.closeLogViewer();
            }
        });
        
        // Close on Escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && !modal.classList.contains('hidden')) {
                this.closeLogViewer();
            }
        });
    }
    
    /**
     * Setup the Tools Panel modal for config editors
     */
    setupToolsPanel() {
        const openBtn = document.getElementById('toolsPanelBtn');
        const modal = document.getElementById('toolsPanelModal');
        const closeBtn = document.getElementById('closeToolsPanel');
        
        if (!openBtn || !modal) return;
        
        // Open tools panel in popout window
        openBtn.addEventListener('click', () => {
            this.openToolsPopout();
        });
        
        // Close tools panel
        closeBtn?.addEventListener('click', () => {
            modal.classList.add('hidden');
        });
        
        // Close on overlay click
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                modal.classList.add('hidden');
            }
        });
        
        // Close on Escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && !modal.classList.contains('hidden')) {
                modal.classList.add('hidden');
            }
        });
        
        // Configuration editor buttons - both button and card are clickable
        const alertRoutingBtn = document.getElementById('ctrlAlertRoutingBtn');
        const alertRoutingCard = document.getElementById('actionAlertRouting');
        const alertSettingsBtn = document.getElementById('ctrlEditAlertSettingsBtn');
        const alertSettingsCard = document.getElementById('actionEditAlertSettings');
        const notificationSettingsBtn = document.getElementById('ctrlEditNotificationSettingsBtn');
        const notificationSettingsCard = document.getElementById('actionEditNotificationSettings');
        const dashboardSettingsBtn = document.getElementById('ctrlEditDashboardSettingsBtn');
        const dashboardSettingsCard = document.getElementById('actionEditDashboardSettings');
        
        const openAlertRouting = (e) => {
            e.preventDefault();
            e.stopPropagation();
            this.openConfigEditor('alert-routing');
        };
        
        const openAlertSettings = (e) => {
            e.preventDefault();
            e.stopPropagation();
            this.openConfigEditor('alert-settings');
        };
        
        const openNotificationSettings = (e) => {
            e.preventDefault();
            e.stopPropagation();
            this.openConfigEditor('notification-settings');
        };
        
        const openDashboardSettings = (e) => {
            e.preventDefault();
            e.stopPropagation();
            this.openConfigEditor('dashboard-settings');
        };
        
        alertRoutingBtn?.addEventListener('click', openAlertRouting);
        alertRoutingCard?.addEventListener('click', openAlertRouting);
        alertSettingsBtn?.addEventListener('click', openAlertSettings);
        alertSettingsCard?.addEventListener('click', openAlertSettings);
        notificationSettingsBtn?.addEventListener('click', openNotificationSettings);
        notificationSettingsCard?.addEventListener('click', openNotificationSettings);
        dashboardSettingsBtn?.addEventListener('click', openDashboardSettings);
        dashboardSettingsCard?.addEventListener('click', openDashboardSettings);
        
        // Script Runner button (admin only - shown via URL param)
        const scriptRunnerBtn = document.getElementById('ctrlScriptRunnerBtn');
        const scriptRunnerCard = document.getElementById('actionScriptRunner');
        const scriptRunnerSection = document.getElementById('scriptRunnerSection');
        
        // Check if user param is in URL to show script runner section
        const urlParams = new URLSearchParams(window.location.search);
        const user = urlParams.get('user');
        const authorizedUsers = ['FKSVEERI', 'FKGEISTA'];
        
        if (user && authorizedUsers.includes(user.toUpperCase())) {
            scriptRunnerSection?.style.setProperty('display', 'block');
        }
        
        const openScriptRunner = (e) => {
            e.preventDefault();
            e.stopPropagation();
            const currentUser = urlParams.get('user') || '';
            window.open(`script-runner.html?user=${encodeURIComponent(currentUser)}`, '_blank');
        };
        
        scriptRunnerBtn?.addEventListener('click', openScriptRunner);
        scriptRunnerCard?.addEventListener('click', openScriptRunner);
        
        // Access Management button
        const accessManagementBtn = document.getElementById('ctrlAccessManagementBtn');
        const accessManagementCard = document.getElementById('actionAccessManagement');
        
        const openAccessManagement = (e) => {
            e.preventDefault();
            e.stopPropagation();
            this.openAccessManagementModal();
        };
        
        accessManagementBtn?.addEventListener('click', openAccessManagement);
        accessManagementCard?.addEventListener('click', openAccessManagement);
    }
    
    /**
     * Open the Access Management modal and load current configuration
     */
    async openAccessManagementModal() {
        const modal = document.getElementById('accessManagementModal');
        if (!modal) return;
        
        modal.classList.remove('hidden');
        
        // Setup tab switching
        this.setupAccessManagementTabs();
        
        // Load configuration tab
        await this.loadAccessConfig();
        
        // Setup close button
        const closeBtn = document.getElementById('closeAccessManagement');
        const closeHandler = () => modal.classList.add('hidden');
        closeBtn?.removeEventListener('click', closeHandler);
        closeBtn?.addEventListener('click', closeHandler);
        
        // Close on overlay click
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                modal.classList.add('hidden');
            }
        });
        
        // Setup refresh button for access log
        const refreshBtn = document.getElementById('refreshAccessLogBtn');
        refreshBtn?.addEventListener('click', () => this.loadAccessLog());
    }
    
    /**
     * Setup tab switching for Access Management modal
     */
    setupAccessManagementTabs() {
        const tabs = document.querySelectorAll('.access-tab');
        const contents = document.querySelectorAll('.access-tab-content');
        
        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                // Remove active from all tabs and contents
                tabs.forEach(t => t.classList.remove('active'));
                contents.forEach(c => c.classList.remove('active'));
                
                // Activate clicked tab
                tab.classList.add('active');
                const tabId = tab.dataset.tab + 'Tab';
                document.getElementById(tabId)?.classList.add('active');
                
                // Load access log when switching to that tab
                if (tab.dataset.tab === 'accesslog') {
                    this.loadAccessLog();
                }
            });
        });
    }
    
    /**
     * Load access configuration (FullAccess, Standard, Blocked)
     */
    
    /**
     * Setup the Control Panel modal for managing agent triggers
     */
    setupControlPanel() {
        const openBtn = document.getElementById('controlPanelBtn');
        const modal = document.getElementById('controlPanelModal');
        const closeBtn = document.getElementById('closeControlPanel');
        
        if (!openBtn || !modal) return;
        
        // Open control panel in popout window
        openBtn.addEventListener('click', () => {
            this.openControlPanelPopout();
        });
        
        // Close control panel
        closeBtn?.addEventListener('click', () => {
            modal.classList.add('hidden');
            this.stopControlPanelPolling();
        });
        
        // Close on overlay click
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                modal.classList.add('hidden');
                this.stopControlPanelPolling();
            }
        });
        
        // Close on Escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && !modal.classList.contains('hidden')) {
                modal.classList.add('hidden');
                this.stopControlPanelPolling();
            }
        });
        
        // Enable/Disable toggle
        const toggle = document.getElementById('agentsEnabledToggle');
        toggle?.addEventListener('change', async () => {
            if (toggle.checked) {
                // Enable agents (remove disable file)
                await this.removeDisableTrigger();
            } else {
                // Disable agents (create disable file)
                const reason = prompt('Enter reason for disabling all agents:', 'Maintenance');
                if (reason === null) {
                    // User cancelled - revert toggle
                    toggle.checked = true;
                    return;
                }
                await this.createDisableTriggerWithReason(reason || 'Disabled via Dashboard');
            }
            this.updateControlPanelStatus();
        });
        
        // Action buttons
        document.getElementById('ctrlStopAllBtn')?.addEventListener('click', async () => {
            if (confirm('Stop all running ServerMonitor agents?\n\nThis will gracefully shut down all agents.')) {
                await this.stopAllAgents();
                this.updateControlPanelStatus();
            }
        });
        
        document.getElementById('ctrlStartAllBtn')?.addEventListener('click', async () => {
            await this.startAllAgents();
            this.updateControlPanelStatus();
        });
        
        document.getElementById('ctrlUpdateAllBtn')?.addEventListener('click', async () => {
            if (confirm('Update all ServerMonitor agents to the latest version?\n\nAgents will restart automatically.')) {
                await this.reinstallAllAgents();
                this.updateControlPanelStatus();
            }
        });
        
        document.getElementById('ctrlGlobalStopFileBtn')?.addEventListener('click', async () => {
            if (confirm('🛑 Create GLOBAL stop file?\n\nThis will stop ALL agents on ALL servers.\n\nThis is a failover method that works even when Tray API is unreachable.')) {
                await this.createGlobalStopFile();
                this.updateControlPanelStatus();
            }
        });
        
        // Remove trigger buttons
        document.getElementById('removeDisableBtn')?.addEventListener('click', async () => {
            await this.removeDisableTrigger();
            this.updateControlPanelStatus();
        });
        
        document.getElementById('removeStopBtn')?.addEventListener('click', async () => {
            await this.removeStopTrigger();
            this.updateControlPanelStatus();
        });
        
        document.getElementById('removeStartBtn')?.addEventListener('click', async () => {
            await this.removeStartTrigger();
            this.updateControlPanelStatus();
        });
        
        document.getElementById('removeReinstallBtn')?.addEventListener('click', async () => {
            await this.removeReinstallTrigger();
            this.updateControlPanelStatus();
        });
        
        // Quick Links buttons
        document.getElementById('openConfigFolderBtn')?.addEventListener('click', () => {
            this.openConfigFolder();
        });
        
        document.getElementById('createStopFileBtn')?.addEventListener('click', async () => {
            await this.createStopFileDirect();
            this.updateControlPanelStatus();
        });
        
        // Header indicator click handlers (to remove triggers)
        document.getElementById('disableFileIndicator')?.addEventListener('click', async () => {
            if (confirm('Enable all agents?\n\nThis will remove the disable file and allow agents to start.')) {
                await this.removeDisableTrigger();
            }
        });
        
        document.getElementById('stopFileIndicator')?.addEventListener('click', async () => {
            if (confirm('Remove the stop trigger file?\n\nThis will cancel the pending stop command.')) {
                await this.removeStopTrigger();
            }
        });
        
        document.getElementById('startFileIndicator')?.addEventListener('click', async () => {
            if (confirm('Remove the start trigger file?\n\nThis will cancel the pending start command.')) {
                await this.removeStartTrigger();
            }
        });
        
        document.getElementById('reinstallFileIndicator')?.addEventListener('click', async () => {
            if (confirm('Remove the reinstall trigger file?\n\nThis will cancel the pending update.')) {
                await this.removeReinstallTrigger();
            }
        });
    }
    
    /**
     * Update the control panel status display
     */
    async updateControlPanelStatus() {
        try {
            const response = await fetch('api/trigger-status');
            if (!response.ok) return;
            
            const status = await response.json();
            
            // Update toggle switch
            const toggle = document.getElementById('agentsEnabledToggle');
            const label = document.getElementById('agentsEnabledLabel');
            const hint = document.getElementById('agentsEnabledHint');
            const section = toggle?.closest('.control-section');
            
            if (toggle) {
                toggle.checked = !status.disableFileExists;
            }
            if (label) {
                label.textContent = status.disableFileExists ? 'Agents Disabled' : 'Agents Enabled';
                label.classList.toggle('disabled', status.disableFileExists);
            }
            if (hint) {
                hint.textContent = status.disableFileExists 
                    ? `Disabled: ${status.disableReason || 'No reason specified'}`
                    : 'When disabled, agents cannot start. Running agents will continue until stopped.';
            }
            if (section) {
                section.classList.toggle('disabled-state', status.disableFileExists);
            }
            
            // Update action buttons based on state
            const startBtn = document.getElementById('ctrlStartAllBtn');
            const stopBtn = document.getElementById('ctrlStopAllBtn');
            const updateBtn = document.getElementById('ctrlUpdateAllBtn');
            const actionStartCard = document.getElementById('actionStartAll');
            const actionStopCard = document.getElementById('actionStopAll');
            const actionUpdateCard = document.getElementById('actionUpdateAll');
            
            // Start button - disabled when agents are disabled or start file already exists
            if (startBtn && actionStartCard) {
                const canStart = !status.disableFileExists && !status.startFileExists;
                startBtn.disabled = !canStart;
                actionStartCard.classList.toggle('disabled', !canStart);
                const startDesc = actionStartCard.querySelector('p');
                if (startDesc) {
                    if (status.disableFileExists) {
                        startDesc.textContent = 'Cannot start while agents are disabled';
                    } else if (status.startFileExists) {
                        startDesc.textContent = 'Start trigger already active';
                    } else {
                        startDesc.textContent = 'Start agents on all servers via tray apps';
                    }
                }
            }
            
            // Stop button - disabled when stop file already exists
            if (stopBtn && actionStopCard) {
                const canStop = !status.stopFileExists;
                stopBtn.disabled = !canStop;
                actionStopCard.classList.toggle('disabled', !canStop);
                const stopDesc = actionStopCard.querySelector('p');
                if (stopDesc) {
                    if (status.stopFileExists) {
                        stopDesc.textContent = 'Stop trigger already active';
                    } else {
                        stopDesc.textContent = 'Gracefully shut down all running agents';
                    }
                }
            }
            
            // Update button - disabled when reinstall file already exists
            if (updateBtn && actionUpdateCard) {
                const canUpdate = !status.reinstallFileExists;
                updateBtn.disabled = !canUpdate;
                actionUpdateCard.classList.toggle('disabled', !canUpdate);
                const updateDesc = actionUpdateCard.querySelector('p');
                if (updateDesc) {
                    if (status.reinstallFileExists) {
                        updateDesc.textContent = `Update to v${status.reinstallVersion || '?'} already pending`;
                    } else {
                        updateDesc.textContent = 'Install latest version on all servers';
                    }
                }
            }
            
            // Update trigger status list
            this.updateTriggerStatusItem('statusDisable', 'statusDisableValue', 'removeDisableBtn', 
                status.disableFileExists, status.disableReason, status.disableFileCreated, 'danger');
            this.updateTriggerStatusItem('statusStop', 'statusStopValue', 'removeStopBtn', 
                status.stopFileExists, 'Active', status.stopFileCreated, 'warning');
            this.updateTriggerStatusItem('statusStart', 'statusStartValue', 'removeStartBtn', 
                status.startFileExists, 'Active', status.startFileCreated, 'active');
            this.updateTriggerStatusItem('statusReinstall', 'statusReinstallValue', 'removeReinstallBtn', 
                status.reinstallFileExists, status.reinstallVersion ? `v${status.reinstallVersion}` : 'Active', 
                status.reinstallFileCreated, 'active');
                
        } catch (error) {
            console.error('Error updating control panel status:', error);
        }
    }
    
    /**
     * Helper to update a trigger status item
     */
    updateTriggerStatusItem(itemId, valueId, removeId, exists, text, created, colorClass) {
        const value = document.getElementById(valueId);
        const removeBtn = document.getElementById(removeId);
        
        if (value) {
            if (exists) {
                const createdDate = created ? new Date(created).toLocaleString() : '';
                value.textContent = `${text}${createdDate ? ` (${createdDate})` : ''}`;
                value.className = `status-value ${colorClass}`;
            } else {
                value.textContent = 'Not present';
                value.className = 'status-value';
            }
        }
        
        if (removeBtn) {
            removeBtn.classList.toggle('hidden', !exists);
        }
    }
    
    /**
     * Start fast polling for control panel (every 3 seconds)
     * This allows detecting changes made by other dashboards quickly
     */
    startControlPanelPolling() {
        this.stopControlPanelPolling(); // Clear any existing timer
        
        this.controlPanelPollTimer = setInterval(() => {
            this.updateControlPanelStatus();
            this.checkTriggerStatus(); // Also update header indicators
        }, this.controlPanelPollInterval);
        
        console.log('Control panel fast polling started (3s interval)');
    }
    
    /**
     * Stop fast polling when control panel is closed
     */
    stopControlPanelPolling() {
        if (this.controlPanelPollTimer) {
            clearInterval(this.controlPanelPollTimer);
            this.controlPanelPollTimer = null;
            console.log('Control panel fast polling stopped');
        }
    }
    
    /**
     * Create disable trigger with a specific reason
     */
    async createDisableTriggerWithReason(reason) {
        try {
            const response = await fetch('api/disable', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ reason: reason })
            });
            const result = await response.json();
            
            if (result.success) {
                await this.checkTriggerStatus();
            } else {
                alert(`Failed to disable agents: ${result.message}`);
            }
        } catch (error) {
            alert(`Error: ${error.message}`);
        }
    }
    
    /**
     * Create a global trigger file (manual override)
     */
    async createGlobalTrigger(type) {
        try {
            let endpoint;
            switch (type) {
                case 'stop':
                    endpoint = 'api/stop';
                    break;
                case 'reinstall':
                    endpoint = 'api/reinstall';
                    break;
                case 'start':
                    endpoint = 'api/start';
                    break;
                default:
                    throw new Error(`Unknown trigger type: ${type}`);
            }
            
            const response = await fetch(endpoint, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({}) // Empty = global trigger
            });
            
            const result = await response.json();
            
            if (result.success) {
                alert(`✅ Global ${type.toUpperCase()} trigger created!\n\nPath: ${result.triggerFilePath || 'N/A'}`);
                await this.checkTriggerStatus();
            } else {
                alert(`❌ Failed to create ${type} trigger: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Remove a global trigger file (manual override)
     */
    async removeGlobalTrigger(type) {
        try {
            let endpoint;
            switch (type) {
                case 'stop':
                    endpoint = 'api/stop';
                    break;
                case 'reinstall':
                    endpoint = 'api/reinstall';
                    break;
                case 'start':
                    endpoint = 'api/start';
                    break;
                default:
                    throw new Error(`Unknown trigger type: ${type}`);
            }
            
            const response = await fetch(endpoint, { method: 'DELETE' });
            const result = await response.json();
            
            if (result.success) {
                alert(`✅ Global ${type.toUpperCase()} trigger removed!`);
                await this.checkTriggerStatus();
            } else {
                alert(`❌ Failed to remove ${type} trigger: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }

    /**
     * Stop all agents by calling the Tray API on each running server.
     * Polls each server every second until stopped or timeout.
     */
    async stopAllAgents() {
        const onlineServers = this.servers.filter(s => s.isAlive);
        
        if (onlineServers.length === 0) {
            alert('No online servers to stop.');
            return;
        }

        const serverList = onlineServers.map(s => s.name).join('\n  • ');
        const confirmMsg = `🛑 Stop ALL agents?\n\nThis will send stop commands to:\n  • ${serverList}\n\nTotal: ${onlineServers.length} server(s)`;
        
        if (!confirm(confirmMsg)) {
            return;
        }

        // Track which servers are still running
        const pendingServers = new Set(onlineServers.map(s => s.name));
        const stoppedServers = [];
        const failedServers = [];
        const timeoutMs = 10000;
        const pollIntervalMs = 1000;
        const startTime = Date.now();

        console.log(`🛑 Stopping ${pendingServers.size} servers...`);

        // Step 1: Send stop command to all servers in parallel
        const stopPromises = onlineServers.map(async (server) => {
            try {
                const response = await fetch(`api/trayapi/${server.name}/stop`, {
                    method: 'POST'
                });
                const result = await response.json();
                
                if (result.success) {
                    console.log(`✅ Stop command sent to ${server.name}`);
                    return { server: server.name, sent: true };
                } else {
                    console.warn(`⚠️ Failed to send stop to ${server.name}: ${result.message}`);
                    return { server: server.name, sent: false, error: result.message };
                }
            } catch (error) {
                console.error(`❌ Error sending stop to ${server.name}:`, error);
                return { server: server.name, sent: false, error: error.message };
            }
        });

        // Wait for all stop commands to be sent
        const stopResults = await Promise.all(stopPromises);
        
        // Remove servers where we couldn't send the stop command from pending
        for (const result of stopResults) {
            if (!result.sent) {
                pendingServers.delete(result.server);
                failedServers.push({ name: result.server, error: result.error });
            }
        }

        // Step 2: Poll each server every second until stopped or timeout
        while (pendingServers.size > 0 && (Date.now() - startTime) < timeoutMs) {
            await new Promise(resolve => setTimeout(resolve, pollIntervalMs));
            
            // Check status of all pending servers in parallel
            const statusPromises = [...pendingServers].map(async (serverName) => {
                try {
                    const response = await fetch(`api/trayapi/${serverName}/status`);
                    const result = await response.json();
                    
                    // Check if agent is stopped
                    const isAgentRunning = result.success && result.agent?.running === true;
                    
                    return { 
                        server: serverName, 
                        running: isAgentRunning,
                        reachable: result.success
                    };
                } catch (error) {
                    // If we can't reach the server, assume it's stopped
                    return { server: serverName, running: false, reachable: false };
                }
            });

            const statusResults = await Promise.all(statusPromises);
            
            for (const status of statusResults) {
                if (!status.running) {
                    // Server has stopped - update UI immediately
                    console.log(`🔴 ${status.server} has stopped`);
                    pendingServers.delete(status.server);
                    stoppedServers.push(status.server);
                    
                    // Update dropdown to show offline (live update)
                    this.updateServerDropdownStatus(status.server, false);
                }
            }
            
            console.log(`⏳ Waiting... ${pendingServers.size} servers still running (${Math.round((Date.now() - startTime) / 1000)}s elapsed)`);
        }

        // Step 3: Handle any servers that didn't stop in time
        if (pendingServers.size > 0) {
            for (const serverName of pendingServers) {
                failedServers.push({ name: serverName, error: 'Timeout - still running after 10s' });
                // Still mark as potentially offline for UI purposes
                this.updateServerDropdownStatus(serverName, false);
            }
        }

        // Step 4: Show summary
        const elapsed = Math.round((Date.now() - startTime) / 1000);
        let message = `Stop All completed in ${elapsed}s:\n\n`;
        
        if (stoppedServers.length > 0) {
            message += `✅ Stopped (${stoppedServers.length}):\n  • ${stoppedServers.join('\n  • ')}\n\n`;
        }
        
        if (failedServers.length > 0) {
            message += `❌ Failed (${failedServers.length}):\n`;
            for (const f of failedServers) {
                message += `  • ${f.name}: ${f.error}\n`;
            }
        }

        alert(message);
        
        // Update status summary
        this.updateStatusSummary();
        
        // Failover: If any servers failed, offer to create global stop file
        if (failedServers.length > 0) {
            const failedNames = failedServers.map(f => f.name).join(', ');
            const useGlobalStop = confirm(
                `⚠️ Some servers failed to stop via Tray API:\n${failedNames}\n\n` +
                `Would you like to create a GLOBAL stop file as failover?\n\n` +
                `This will ensure all agents (including failed ones) receive the stop signal.`
            );
            
            if (useGlobalStop) {
                await this.createGlobalStopFile();
            }
        }
    }
    
    /**
     * Create a global stop file directly (no prompts, just creates it)
     */
    async createGlobalStopFile() {
        try {
            const response = await fetch('api/stop', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ 
                    serverName: '*',
                    reason: 'Global stop via Dashboard'
                })
            });
            
            const result = await response.json();
            
            if (result.success) {
                await this.checkTriggerStatus();
                this.showToast('🛑 Global stop file created!');
                return true;
            } else {
                alert(`❌ Failed to create global stop file: ${result.message}`);
                return false;
            }
        } catch (error) {
            alert(`❌ Error creating global stop file: ${error.message}`);
            return false;
        }
    }

    /**
     * Open configuration editor in a popup window
     */
    openConfigEditor(editorType) {
        console.log('Opening config editor:', editorType);
        
        let url;
        switch (editorType) {
            case 'alert-settings':
                url = 'alert-settings.html';
                break;
            case 'notification-settings':
                url = 'notification-settings.html';
                break;
            case 'alert-routing':
                url = 'alert-routing.html';
                break;
            case 'dashboard-settings':
                url = 'dashboard-settings.html';
                break;
            default:
                url = 'alert-settings.html';
        }
        
        const width = 1560;
        const height = 800;
        const left = Math.max(0, (screen.width - width) / 2);
        const top = Math.max(0, (screen.height - height) / 2);
        
        const popup = window.open(
            url,
            `configEditor_${editorType}`,
            `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes`
        );
        
        // If popup was blocked, open in new tab instead
        if (!popup || popup.closed || typeof popup.closed === 'undefined') {
            console.log('Popup blocked, opening in new tab');
            window.open(url, '_blank');
        }
    }

    /**
     * Trigger reinstall for all agents (creates global trigger file)
     */
    async reinstallAllAgents() {
        if (!confirm('📦 Install latest version on ALL agents?\n\nThis will create a global reinstall trigger that all tray applications will detect and process.')) {
            return;
        }

        try {
            this.showLoading();
            
            const response = await fetch('api/reinstall', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({}) // Empty = global trigger
            });
            
            const result = await response.json();
            
            this.hideLoading();
            
            if (result.success) {
                alert(`✅ Global reinstall trigger created!\n\nVersion: ${result.version}\nPath: ${result.triggerFilePath}\n\nAll tray applications will detect this and reinstall the agent.`);
                await this.checkTriggerStatus();
            } else {
                alert(`❌ Failed to create trigger:\n${result.message}`);
            }
        } catch (error) {
            this.hideLoading();
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    async startAllAgents() {
        const offlineServers = this.servers.filter(s => !s.isAlive);
        
        if (offlineServers.length === 0) {
            alert('All servers are already online.');
            return;
        }

        const serverList = offlineServers.map(s => s.name).join('\n  • ');
        const confirmMsg = `▶️ Start ALL offline agents?\n\nThis will create a GLOBAL start trigger file for:\n  • ${serverList}\n\nTotal: ${offlineServers.length} offline server(s)`;
        
        if (!confirm(confirmMsg)) {
            return;
        }

        try {
            this.showLoading();
            
            const response = await fetch('api/start', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ 
                    serverName: '*'  // Global start - creates StartServerMonitor.txt
                })
            });
            
            const result = await response.json();
            this.hideLoading();
            
            if (result.success) {
                alert(`✅ Global start trigger created!\n\nPath: ${result.triggerFilePath}\n\nAll tray applications will detect this and start their agents.`);
                await this.checkTriggerStatus();
            } else {
                alert(`❌ Failed to create start trigger:\n${result.message}`);
            }
        } catch (error) {
            this.hideLoading();
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Start the agent on a specific server using the Tray API (port 8997).
     * Falls back to trigger file if Tray API is not available.
     */
    async startServer(serverName) {
        try {
            // Try Tray API first (direct, immediate)
            const response = await fetch(`api/TrayApi/${encodeURIComponent(serverName)}/start`, {
                method: 'POST'
            });
            
            const result = await response.json();
            
            if (result.success) {
                alert(`✅ Agent started on ${serverName}!\n\n${result.message}`);
                
                // Refresh after a short delay to let agent initialize
                setTimeout(() => {
                    this.loadSnapshot(serverName);
                }, 3000);
            } else {
                // Tray API failed - offer to use trigger file as fallback
                if (confirm(`⚠️ Tray API not reachable on ${serverName}\n\nError: ${result.message}\n\nWould you like to create a trigger file instead? (requires tray app polling)`)) {
                    await this.startServerViaTriggerFile(serverName);
                }
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Fallback: Start agent using trigger file
     */
    async startServerViaTriggerFile(serverName) {
        try {
            const response = await fetch('api/start', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ serverName })
            });
            
            const result = await response.json();
            
            if (result.success) {
                alert(`✅ Start trigger created for ${serverName}!\n\nThe tray application on this server will start the agent when it detects the trigger file.`);
                await this.checkTriggerStatus();
                this.monitorTriggerFileDeletion(serverName, 'start');
            } else {
                alert(`❌ Failed: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Stop the agent on a specific server using the Tray API (port 8997).
     */
    async stopServer(serverName) {
        if (!confirm(`Stop the agent on ${serverName}?`)) {
            return;
        }
        
        try {
            const response = await fetch(`api/TrayApi/${encodeURIComponent(serverName)}/stop`, {
                method: 'POST'
            });
            
            const result = await response.json();
            
            if (result.success) {
                alert(`✅ Agent stopped on ${serverName}!\n\n${result.message}`);
                
                // Refresh after a short delay
                setTimeout(() => {
                    this.loadSnapshot(serverName);
                }, 2000);
            } else {
                alert(`❌ Failed to stop agent: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Restart the agent on a specific server using the Tray API (port 8997).
     */
    async restartServer(serverName) {
        if (!confirm(`Restart the agent on ${serverName}?`)) {
            return;
        }
        
        try {
            const response = await fetch(`api/TrayApi/${encodeURIComponent(serverName)}/restart`, {
                method: 'POST'
            });
            
            const result = await response.json();
            
            if (result.success) {
                alert(`✅ Agent restarting on ${serverName}!\n\n${result.message}`);
                
                // Refresh after a delay to let agent restart
                setTimeout(() => {
                    this.loadSnapshot(serverName);
                }, 5000);
            } else {
                alert(`❌ Failed to restart agent: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Reinstall the agent on a specific server using the Tray API (port 8997).
     * Falls back to trigger file if Tray API is not available.
     */
    async reinstallServer(serverName) {
        if (!confirm(`Reinstall the agent on ${serverName}?\n\nThis will download and install the latest version.`)) {
            return;
        }
        
        try {
            // Try Tray API first (direct, immediate)
            const response = await fetch(`api/TrayApi/${encodeURIComponent(serverName)}/reinstall`, {
                method: 'POST'
            });
            
            const result = await response.json();
            
            if (result.success) {
                alert(`✅ Reinstall initiated on ${serverName}!\n\n${result.message}\n\nThe dashboard will refresh in 2 minutes when the reinstall completes.`);
                
                // Refresh after 2 minutes to let reinstall complete
                setTimeout(() => {
                    this.loadSnapshot(serverName);
                }, 120000);
            } else {
                // Tray API failed - offer to use trigger file as fallback
                if (confirm(`⚠️ Tray API not reachable on ${serverName}\n\nError: ${result.message}\n\nWould you like to create a trigger file instead? (requires tray app polling)`)) {
                    await this.reinstallServerViaTriggerFile(serverName);
                }
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Fallback: Reinstall agent using trigger file
     */
    async reinstallServerViaTriggerFile(serverName) {
        try {
            const response = await fetch('api/reinstall', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ serverName })
            });
            
            const result = await response.json();
            
            if (result.success) {
                alert(`✅ Reinstall trigger created for ${serverName}!\n\nVersion: ${result.version}\n\nThe dashboard will refresh automatically when the trigger is processed.`);
                await this.checkTriggerStatus();
                this.monitorTriggerFileDeletion(serverName, 'reinstall');
            } else {
                alert(`❌ Failed: ${result.message}`);
            }
        } catch (error) {
            alert(`❌ Error: ${error.message}`);
        }
    }
    
    /**
     * Monitors for a server-specific trigger file to be deleted by the tray app.
     * Once deleted, waits 3 seconds and then refreshes the server data.
     * @param {string} serverName - The server name
     * @param {string} type - The trigger type ('start' or 'reinstall')
     */
    async monitorTriggerFileDeletion(serverName, type) {
        const maxAttempts = 60; // Poll for up to 60 seconds
        const pollInterval = 1000; // Check every 1 second
        let attempts = 0;
        
        console.log(`Monitoring ${type} trigger file deletion for ${serverName}...`);
        
        const checkFile = async () => {
            attempts++;
            
            try {
                const response = await fetch(`api/trigger-file-exists/${encodeURIComponent(serverName)}?type=${type}`);
                const result = await response.json();
                
                if (!result.exists) {
                    // File has been deleted by tray app
                    console.log(`${type} trigger file for ${serverName} was deleted. Waiting 3 seconds before refresh...`);
                    
                    // Wait 3 seconds for service to fully start
                    setTimeout(async () => {
                        console.log(`Refreshing data for ${serverName}...`);
                        
                        // Reload servers to get updated status
                        await this.loadServers();
                        
                        // If this server is still selected, reload its snapshot
                        if (this.selectedServer === serverName) {
                            await this.loadSnapshot(serverName);
                        }
                        
                        // Update trigger status
                        await this.checkTriggerStatus();
                    }, 3000);
                    
                    return; // Stop polling
                }
                
                // File still exists, continue polling
                if (attempts < maxAttempts) {
                    setTimeout(checkFile, pollInterval);
                } else {
                    console.log(`Stopped monitoring ${type} trigger file for ${serverName} after ${maxAttempts} seconds`);
                }
            } catch (error) {
                console.error(`Error checking trigger file: ${error.message}`);
                // Continue polling on error
                if (attempts < maxAttempts) {
                    setTimeout(checkFile, pollInterval);
                }
            }
        };
        
        // Start polling after a brief delay
        setTimeout(checkFile, 500);
    }

    async loadServers(forceRefresh = false) {
        try {
            this.showLoading();
            
            // Use POST to /api/servers/refresh for force refresh (re-pings all servers)
            // Use GET to /api/servers for cached status (faster)
            let response;
            if (forceRefresh) {
                response = await fetch('api/servers/refresh', { method: 'POST' });
            } else {
                response = await fetch('api/servers');
            }
            const data = await response.json();
            
            this.servers = data.servers || [];
            this.currentAgentVersion = data.currentAgentVersion;
            
            // Store current selection before re-rendering
            const previousSelection = this.selectedServer;
            
            this.renderServerDropdown();
            this.updateStatusSummary();
            
            // Check if previously selected server is still in the list
            const previousServerStillExists = previousSelection && 
                this.servers.some(s => s.name === previousSelection);
            
            if (previousServerStillExists) {
                // Restore the previous selection (even if offline)
                const select = document.getElementById('serverSelect');
                if (select) {
                    select.value = previousSelection;
                    this.selectedServer = previousSelection;
                }
            } else if (!this.selectedServer) {
                // Only auto-select if no server is currently selected or previous was removed
                const firstOnline = this.servers.find(s => s.isAlive);
                if (firstOnline) {
                    this.selectServer(firstOnline.name);
                } else if (this.servers.length > 0) {
                    this.selectServer(this.servers[0].name);
                }
            }
        } catch (error) {
            console.error('Error loading servers:', error);
            this.showError('Failed to load server list');
        } finally {
            this.hideLoading();
        }
    }

    renderServerDropdown() {
        const select = document.getElementById('serverSelect');
        if (!select) return;

        select.innerHTML = '<option value="">-- Select Server --</option>';
        
        // Sort: online first, then checking, then offline, then alphabetically
        const statusOrder = { online: 0, checking: 1, unknown: 2, offline: 3 };
        const sorted = [...this.servers].sort((a, b) => {
            const aStatus = a.statusText || (a.isAlive ? 'online' : 'offline');
            const bStatus = b.statusText || (b.isAlive ? 'online' : 'offline');
            const aOrder = statusOrder[aStatus] ?? 2;
            const bOrder = statusOrder[bStatus] ?? 2;
            if (aOrder !== bOrder) return aOrder - bOrder;
            return a.name.localeCompare(b.name);
        });

        for (const server of sorted) {
            const option = document.createElement('option');
            option.value = server.name;
            
            // Status-based icon and text:
            // 🟢 Green = Online (responding)
            // 🟡 Yellow = Checking (currently being polled)
            // 🟠 Orange = Unknown (not yet checked)
            // 🟣 Magenta = Offline (not responding)
            const status = server.statusText || (server.isAlive ? 'online' : 'offline');
            let icon, statusText;
            switch (status) {
                case 'online':
                    icon = '🟢';
                    statusText = '';
                    break;
                case 'checking':
                    icon = '🟡';
                    statusText = ' (checking...)';
                    break;
                case 'unknown':
                    icon = '🟠';
                    statusText = ' (unknown)';
                    break;
                case 'offline':
                default:
                    icon = '🟣';
                    statusText = ' (OFFLINE)';
                    break;
            }
            
            option.textContent = `${icon} ${server.name}${statusText}`;
            option.dataset.status = status;
            select.appendChild(option);
        }

        if (this.selectedServer) {
            select.value = this.selectedServer;
        }
    }

    updateStatusSummary() {
        // Count by statusText (from SSE) or fallback to isAlive boolean
        const online = this.servers.filter(s => s.statusText === 'online' || (!s.statusText && s.isAlive)).length;
        const checking = this.servers.filter(s => s.statusText === 'checking' || s.statusText === 'unknown').length;
        const offline = this.servers.filter(s => s.statusText === 'offline' || (!s.statusText && !s.isAlive && s.statusText !== 'checking')).length;
        
        const summary = document.getElementById('statusSummary');
        if (summary) {
            let html = `<span class="status-badge online"><span class="status-dot online"></span>${online} Online</span>`;
            
            if (checking > 0) {
                html += `<span class="status-badge checking"><span class="status-dot checking"></span>${checking} Checking</span>`;
            }
            
            html += `<span class="status-badge offline"><span class="status-dot offline"></span>${offline} Offline</span>`;
            
            summary.innerHTML = html;
        }
    }

    /**
     * Select a server and load its snapshot
     * @param {string} serverName - The server name to select
     * @param {boolean} updateUrl - Whether to update the browser URL (default: true)
     *                              Set to false when loading from URL to avoid redundant update
     */
    async selectServer(serverName, updateUrl = true) {
        if (!serverName) return;
        
        this.selectedServer = serverName;
        const select = document.getElementById('serverSelect');
        if (select) select.value = serverName;

        // Persist selection to localStorage for browser refresh
        this.saveSelectedServer(serverName);

        // Update browser URL for bookmarking
        if (updateUrl) {
            this.updateUrl(serverName);
        }

        await this.loadSnapshot(serverName);
        
        // Show/hide reinstall button based on status
        const server = this.servers.find(s => s.name === serverName);
        const reinstallBtn = document.getElementById('reinstallBtn');
        if (reinstallBtn) {
            reinstallBtn.style.display = server && !server.isAlive ? 'inline-flex' : 'none';
        }
    }

    /**
     * Load all dashboard settings from localStorage
     * @returns {Object} Settings object with defaults
     */
    loadSettings() {
        const defaults = {
            autoRefresh: true,
            refreshInterval: 120,
            selectedServer: null
        };
        
        try {
            const saved = localStorage.getItem('servermonitor_settings');
            if (saved) {
                const parsed = JSON.parse(saved);
                return {
                    autoRefresh: typeof parsed.autoRefresh === 'boolean' ? parsed.autoRefresh : defaults.autoRefresh,
                    refreshInterval: typeof parsed.refreshInterval === 'number' && parsed.refreshInterval >= 5 
                        ? parsed.refreshInterval : defaults.refreshInterval,
                    selectedServer: parsed.selectedServer || defaults.selectedServer
                };
            }
        } catch (e) {
            console.warn('Could not load settings from localStorage:', e);
        }
        return defaults;
    }

    /**
     * Save all dashboard settings to localStorage for persistence across browser refresh
     */
    saveSettings() {
        try {
            const settings = {
                autoRefresh: this.autoRefresh,
                refreshInterval: this.refreshInterval,
                selectedServer: this.selectedServer
            };
            localStorage.setItem('servermonitor_settings', JSON.stringify(settings));
        } catch (e) {
            console.warn('Could not save settings to localStorage:', e);
        }
    }

    /**
     * Save selected server (convenience method that calls saveSettings and saveLastServer)
     */
    saveSelectedServer(serverName) {
        this.saveSettings();
        this.saveLastServer(serverName); // Also save to dedicated key for reliable retrieval
    }

    async loadSnapshot(serverName) {
        try {
            this.showSpinner();
            const url = `api/snapshot/${serverName}`;
            const response = await fetch(url);
            
            if (!response.ok) {
                throw new Error(`Failed to load snapshot: ${response.statusText}`);
            }
            
            this.currentSnapshot = await response.json();
            
            // Update server status in dropdown to show it's responding
            this.updateServerDropdownStatus(serverName, true);
            
            // Fetch dashboard configs from agent (non-blocking)
            this.loadDb2DashboardConfig(serverName);
            this.loadIisDashboardConfig(serverName);
            
            this.renderDashboard();
        } catch (error) {
            console.error('Error loading snapshot:', error);
            this.showError(`Failed to load data from ${serverName}`);
            this.currentSnapshot = null;
            
            // Update server status in dropdown to show it's not responding
            this.updateServerDropdownStatus(serverName, false);
            
            this.renderEmptyState();
        } finally {
            this.hideSpinner();
        }
    }
    
    /**
     * Load DB2 dashboard configuration from the agent
     * This determines whether features like pop-out buttons should be shown
     */
    async loadDb2DashboardConfig(serverName) {
        try {
            // Get the server's agent port (8999)
            const server = this.servers.find(s => s.name === serverName);
            const baseUrl = server?.baseUrl || `http://${serverName}:8999`;
            
            const response = await fetch(`${baseUrl}/api/db2/config`);
            if (response.ok) {
                this.db2DashboardConfig = await response.json();
                console.log('DB2 Dashboard config loaded:', this.db2DashboardConfig);
            } else {
                // Default to enabled if config endpoint not available
                this.db2DashboardConfig = { enablePopout: true };
            }
        } catch (error) {
            console.warn('Could not load DB2 dashboard config, using defaults:', error.message);
            this.db2DashboardConfig = { enablePopout: true };
        }
    }

    /**
     * Load IIS dashboard configuration from the agent
     */
    async loadIisDashboardConfig(serverName) {
        try {
            const server = this.servers.find(s => s.name === serverName);
            const baseUrl = server?.baseUrl || `http://${serverName}:8999`;
            
            const response = await fetch(`${baseUrl}/api/iis/config`);
            if (response.ok) {
                this.iisDashboardConfig = await response.json();
            } else {
                this.iisDashboardConfig = { enablePopout: true };
            }
        } catch (error) {
            console.warn('Could not load IIS dashboard config, using defaults:', error.message);
            this.iisDashboardConfig = { enablePopout: true };
        }
    }
    
    /**
     * Updates the dropdown option for a server to show current status
     */
    updateServerDropdownStatus(serverName, isOnline) {
        const select = document.getElementById('serverSelect');
        if (!select) return;
        
        // Find and update the option for this server
        for (const option of select.options) {
            if (option.value === serverName) {
                const icon = isOnline ? '🟢' : '🔴';
                const status = isOnline ? '' : ' (NOT RESPONDING)';
                option.textContent = `${icon} ${serverName}${status}`;
                break;
            }
        }
        
        // Also update the servers array for consistency
        const server = this.servers.find(s => s.name === serverName);
        if (server) {
            server.isAlive = isOnline;
            this.updateStatusSummary();
        }
    }

    renderDashboard() {
        if (!this.currentSnapshot) {
            this.renderEmptyState();
            return;
        }

        this.renderAgentInfo();
        this.renderMetrics();
        this.renderWindowsUpdates();
        this.renderAlerts();
        this.renderTopProcesses();
        this.renderDb2Panel();
        this.renderIisPanel();
        this.renderScheduledTasks();
    }

    /**
     * Renders the agent info bar showing version and update button
     */
    renderAgentInfo() {
        let infoBar = document.getElementById('agentInfoBar');
        if (!infoBar) {
            // Create the info bar after controls bar
            const controlsBar = document.querySelector('.controls-bar');
            if (controlsBar) {
                infoBar = document.createElement('div');
                infoBar.id = 'agentInfoBar';
                infoBar.className = 'agent-info-bar';
                controlsBar.parentNode.insertBefore(infoBar, controlsBar.nextSibling);
            }
        }
        if (!infoBar) return;

        const agentVersionRaw = this.currentSnapshot?.metadata?.toolVersion ||
                             this.currentSnapshot?.toolVersion ||
                             this.currentSnapshot?.agentVersion ||
                             'Unknown';
        const latestVersionRaw = this.currentAgentVersion || 'Unknown';
        // Format both versions consistently (remove trailing .0)
        const agentVersion = this.formatVersion(agentVersionRaw);
        const latestVersion = this.formatVersion(latestVersionRaw);
        const serverName = this.selectedServer || '';
        
        // Check if server is online
        const server = this.servers.find(s => s.name === serverName);
        const isOnline = server?.isAlive || false;
        
        // Compare versions - button enabled if:
        // 1. Version is unknown (allow updating to be safe)
        // 2. Version differs from latest (needs update)
        // Button disabled only when version is known AND matches latest (confirmed up to date)
        const isVersionUnknown = agentVersion === 'Unknown';
        const isOutdated = !isVersionUnknown && latestVersion !== 'Unknown' && agentVersion !== latestVersion;
        const isUpToDate = !isVersionUnknown && latestVersion !== 'Unknown' && agentVersion === latestVersion;
        const canUpdate = isOnline && (isVersionUnknown || isOutdated);
        
        // Get memory info from metadata
        const processMemoryMB = this.currentSnapshot?.metadata?.processMemoryMB || 0;
        const snapshotSizeMB = this.currentSnapshot?.metadata?.snapshotSizeMB || 0;
        const memoryWarning = processMemoryMB > 1024; // Warn if over 1 GB
        const memoryCritical = processMemoryMB > 2048; // Critical if over 2 GB
        const logFileUncPath = this.currentSnapshot?.metadata?.logFileUncPath || '';
        
        infoBar.innerHTML = `
            <div class="agent-info-content">
                <div class="agent-info-item">
                    <span class="agent-info-label">🖥️ Server:</span>
                    <span class="agent-info-value">${serverName}</span>
                </div>
                <div class="agent-info-item">
                    <span class="agent-info-label">📦 Agent Version:</span>
                    <span class="agent-info-value ${isOutdated || isVersionUnknown ? 'outdated' : ''}">${agentVersion}</span>
                </div>
                <div class="agent-info-item">
                    <span class="agent-info-label">🆕 Latest available:</span>
                    <span class="agent-info-value">${latestVersion}</span>
                </div>
                <div class="agent-info-item" title="ServerMonitor.exe process memory usage">
                    <span class="agent-info-label">💾 Agent Memory:</span>
                    <span class="agent-info-value ${memoryCritical ? 'memory-critical' : memoryWarning ? 'memory-warning' : ''}">${processMemoryMB > 0 ? processMemoryMB.toFixed(0) + ' MB' : 'N/A'}</span>
                </div>
                <div class="agent-info-item" title="Estimated in-memory snapshot data size">
                    <span class="agent-info-label">📊 Snapshot:</span>
                    <span class="agent-info-value">${snapshotSizeMB > 0 ? snapshotSizeMB.toFixed(2) + ' MB' : 'N/A'}</span>
                </div>
                <div class="agent-info-item agent-info-logfile" title="Click to copy log file UNC path">
                    <span class="agent-info-label">📄 Log:</span>
                    <span class="agent-info-value log-path" id="logFilePath">${logFileUncPath || 'N/A'}</span>
                    <button id="copyLogPathBtn" class="btn-copy" title="Copy UNC path to clipboard" ${logFileUncPath ? '' : 'disabled'}>📋</button>
                </div>
                <button id="updateAgentBtn" class="btn btn-update ${canUpdate ? '' : 'disabled'}" 
                        ${canUpdate ? '' : 'disabled'}
                        title="${isVersionUnknown ? 'Version unknown - click to update' : isOutdated ? 'Push update to this server' : 'Already on latest version'}">
                    ${isUpToDate ? '✅ Up to date' : isVersionUnknown ? '❓ Update (version unknown)' : '⬆️ Update'}
                </button>
                <button id="stopAgentBtn" class="btn btn-stop ${isOnline ? '' : 'disabled'}" 
                        ${isOnline ? '' : 'disabled'}
                        title="${isOnline ? 'Stop the ServerMonitor agent on this server' : 'Server is offline'}">
                    🛑 Stop Agent
                </button>
                <button id="clearSnapshotBtn" class="btn btn-clear-snapshot ${isOnline ? '' : 'disabled'}" 
                        ${isOnline ? '' : 'disabled'}
                        data-require-role="Admin"
                        title="${isOnline ? 'Clear snapshot: resets in-memory data and deletes persisted file. Agent will re-accumulate from scratch.' : 'Server is offline'}">
                    🗑️ Clear Snapshot
                </button>
            </div>
        `;
        
        // Add click handler for update button
        const updateBtn = document.getElementById('updateAgentBtn');
        if (updateBtn && canUpdate) {
            updateBtn.addEventListener('click', () => this.triggerServerUpdate(serverName));
        }
        
        // Add click handler for stop button
        const stopBtn = document.getElementById('stopAgentBtn');
        if (stopBtn && isOnline) {
            stopBtn.addEventListener('click', () => this.triggerServerStop(serverName));
        }
        
        // Add click handler for clear snapshot button (admin only)
        const clearBtn = document.getElementById('clearSnapshotBtn');
        if (clearBtn && isOnline) {
            clearBtn.addEventListener('click', () => this.triggerClearSnapshot(serverName));
        }
        
        // Re-apply role restrictions so the clear snapshot button is hidden for non-admins
        if (window.RolePermissions) {
            RolePermissions.applyRoleRestrictions();
        }
        
        // Add click handler for copy log path button
        const copyLogPathBtn = document.getElementById('copyLogPathBtn');
        if (copyLogPathBtn && logFileUncPath) {
            copyLogPathBtn.addEventListener('click', async (e) => {
                e.stopPropagation();
                try {
                    await navigator.clipboard.writeText(logFileUncPath);
                    copyLogPathBtn.textContent = '✅';
                    setTimeout(() => {
                        copyLogPathBtn.textContent = '📋';
                    }, 1500);
                } catch (err) {
                    console.error('Failed to copy log path:', err);
                    copyLogPathBtn.textContent = '❌';
                    setTimeout(() => {
                        copyLogPathBtn.textContent = '📋';
                    }, 1500);
                }
            });
        }
    }

    /**
     * Trigger stop for a specific server
     */
    async triggerServerStop(serverName) {
        if (!confirm(`🛑 Stop ServerMonitor agent on ${serverName}?\n\nThis will gracefully shut down the agent. The agent will restart if the Windows service is configured to auto-restart.`)) {
            return;
        }

        try {
            const response = await fetch('api/stop', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ serverName: serverName, reason: 'Stopped via Dashboard' })
            });
            
            const result = await response.json();
            
            if (result.success) {
                alert(`🛑 Stop signal sent to ${serverName}!\n\n${result.message}`);
                setTimeout(() => this.manualRefresh(), 3000);
            } else {
                alert(`❌ Failed to stop ${serverName}:\n${result.message}`);
            }
        } catch (error) {
            console.error('Error stopping server:', error);
            alert(`❌ Error stopping ${serverName}`);
        }
    }

    /**
     * Clear snapshot for a specific server (Admin only).
     * Resets the agent's in-memory snapshot and deletes the persisted snapshot file.
     */
    async triggerClearSnapshot(serverName) {
        if (!confirm(`🗑️ Clear snapshot on ${serverName}?\n\nThis will:\n• Reset all in-memory monitoring data\n• Delete the persisted snapshot file\n• Force garbage collection\n\nThe agent will start accumulating data from scratch.\nAlerts and history will be lost.`)) {
            return;
        }

        const btn = document.getElementById('clearSnapshotBtn');
        if (btn) {
            btn.disabled = true;
            btn.textContent = '⏳ Clearing...';
        }

        try {
            const response = await fetch(`api/snapshot/${encodeURIComponent(serverName)}/clear`, {
                method: 'POST'
            });
            
            const result = await response.json();
            
            if (result.success) {
                const agent = result.agentResponse;
                const freed = agent?.memoryFreedMB ?? 0;
                const after = agent?.memoryAfterMB ?? 0;
                alert(`✅ Snapshot cleared on ${serverName}!\n\nMemory freed: ${freed} MB\nCurrent memory: ${after} MB\n\nThe agent will re-accumulate data from scratch.`);
                setTimeout(() => this.manualRefresh(), 2000);
            } else {
                alert(`❌ Failed to clear snapshot on ${serverName}:\n${result.message}`);
            }
        } catch (error) {
            console.error('Error clearing snapshot:', error);
            alert(`❌ Error clearing snapshot on ${serverName}`);
        } finally {
            if (btn) {
                btn.disabled = false;
                btn.textContent = '🗑️ Clear Snapshot';
            }
        }
    }
    
    /**
     * Trigger update for a specific server
     */
    async triggerServerUpdate(serverName) {
        if (!confirm(`Push update to ${serverName}?\n\nThis will create a server-specific reinstall trigger file.`)) {
            return;
        }

        try {
            const response = await fetch('api/reinstall', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ serverName: serverName })
            });
            
            const result = await response.json();
            
            if (result.success) {
                alert(`✅ Update triggered for ${serverName}!\n\nVersion: ${result.version}\nTrigger: ${result.triggerFilePath}`);
                // Refresh to show updated status
                setTimeout(() => this.manualRefresh(), 2000);
            } else {
                alert(`❌ Failed to trigger update:\n${result.message}`);
            }
        } catch (error) {
            console.error('Error triggering update:', error);
            alert('❌ Error triggering update');
        }
    }

    renderMetrics() {
        const snapshot = this.currentSnapshot;
        const container = document.getElementById('metricsGrid');
        if (!container) return;

        // Extract metrics from snapshot - mapping API property names
        // API uses: processor.overallUsagePercent, memory.usedPercent, memory.totalGB, memory.availableGB
        const cpu = snapshot.processor?.overallUsagePercent || snapshot.processor?.currentCpuPercent || 0;
        const memory = snapshot.memory?.usedPercent || snapshot.memory?.memoryUsedPercent || 0;
        const memoryTotalGb = snapshot.memory?.totalGB || snapshot.memory?.totalMemoryGb || 0;
        const memoryAvailableGb = snapshot.memory?.availableGB || 0;
        const memoryUsedGb = memoryTotalGb - memoryAvailableGb;
        
        // Get ALL disks - API uses disks.space[] with:
        //   drive, totalGB, availableGB, usedPercent, fileSystem
        const diskDrives = snapshot.disks?.space || snapshot.diskSpace?.drives || [];
        
        // API uses currentUptimeDays (new) or totalDays (old)
        const uptimeRaw = snapshot.uptime?.currentUptimeDays ?? snapshot.uptime?.totalDays ?? null;
        const uptime = uptimeRaw ?? 0;
        const uptimeFormatted = uptimeRaw !== null ? this.formatUptime(uptime) : '-';
        const hasUptime = uptimeRaw !== null;

        // Disk data will be rendered separately in renderDisksSection()

        container.innerHTML = `
            <div class="metric-card gauge-card">
                <div class="metric-card-header">
                    <span class="metric-card-title">CPU Usage</span>
                </div>
                ${this.createGaugeSVG(cpu, 'cpu')}
                <div class="gauge-value">${cpu.toFixed(1)}%</div>
            </div>
            
            <div class="metric-card gauge-card">
                <div class="metric-card-header">
                    <span class="metric-card-title">Memory Usage</span>
                </div>
                ${this.createGaugeSVG(memory, 'memory')}
                <div class="gauge-value">${memory.toFixed(1)}%</div>
                <div class="metric-detail">${memoryUsedGb.toFixed(1)} / ${memoryTotalGb.toFixed(1)} GB</div>
            </div>
            
            <div class="metric-card uptime-card">
                <div class="metric-card-header">
                    <span class="metric-card-title">System Uptime</span>
                </div>
                <div class="uptime-display">
                    <div class="uptime-icon">🖥️</div>
                    <div class="uptime-value">${uptimeFormatted}</div>
                    <div class="uptime-detail">${hasUptime ? `${uptime.toFixed(1)} days running` : 'Uptime data not available'}</div>
                </div>
            </div>
        `;

        // Render disks in separate section
        this.renderDisksSection(diskDrives);
    }

    /**
     * Renders the Windows Updates section
     * Always visible - shows pending updates or "No updates pending" if none
     */
    renderWindowsUpdates() {
        const container = document.getElementById('windowsUpdatesPanel');
        if (!container) return;

        const updates = this.currentSnapshot?.windowsUpdates;
        const content = container.querySelector('.updates-content');
        if (!content) return;

        // If no server selected, show empty state
        if (!this.currentSnapshot) {
            content.innerHTML = `
                <div class="updates-empty-state">
                    <span class="updates-icon">📊</span>
                    <span>Select a server to view update status</span>
                </div>
            `;
            return;
        }

        // If no Windows Update data available, show "no data" state
        if (!updates) {
            content.innerHTML = `
                <div class="updates-status info">
                    <div class="updates-status-icon">ℹ️</div>
                    <div class="updates-status-text">Windows Update data not available</div>
                </div>
                <div class="updates-grid">
                    <div class="update-stat">
                        <div class="update-stat-value">-</div>
                        <div class="update-stat-label">Pending</div>
                    </div>
                    <div class="update-stat">
                        <div class="update-stat-value">-</div>
                        <div class="update-stat-label">Security</div>
                    </div>
                    <div class="update-stat">
                        <div class="update-stat-value">-</div>
                        <div class="update-stat-label">Critical</div>
                    </div>
                    <div class="update-stat last-update">
                        <div class="update-stat-value">-</div>
                        <div class="update-stat-label">Last Install</div>
                    </div>
                </div>
            `;
            return;
        }

        const pendingCount = updates?.pendingCount || 0;
        const securityUpdates = updates?.securityUpdates || 0;
        const criticalUpdates = updates?.criticalUpdates || 0;
        const lastInstallDate = updates?.lastInstallDate;

        // Format last install date
        let lastInstallFormatted = 'Never';
        if (lastInstallDate) {
            const date = new Date(lastInstallDate);
            if (!isNaN(date.getTime())) {
                lastInstallFormatted = date.toLocaleDateString();
            }
        }

        // Calculate days since last update
        let daysSinceUpdate = null;
        if (lastInstallDate) {
            const date = new Date(lastInstallDate);
            if (!isNaN(date.getTime())) {
                daysSinceUpdate = Math.floor((Date.now() - date.getTime()) / (1000 * 60 * 60 * 24));
            }
        }

        // Determine status
        const hasSecurityUpdates = securityUpdates > 0;
        const hasCriticalUpdates = criticalUpdates > 0;
        const hasPendingUpdates = pendingCount > 0;

        // Status class and icon
        let statusClass = 'success';
        let statusIcon = '✅';
        let statusText = 'No updates pending';

        if (hasCriticalUpdates || hasSecurityUpdates) {
            statusClass = 'critical';
            statusIcon = '⚠️';
            statusText = 'Security updates required';
        } else if (hasPendingUpdates) {
            statusClass = 'warning';
            statusIcon = '🔄';
            statusText = `${pendingCount} update(s) pending`;
        }

        // Get pending update names
        const pendingUpdateNames = updates?.pendingUpdateNames || [];
        
        // Build pending updates table HTML (always visible)
        let pendingUpdatesTableHtml = '';
        if (pendingUpdateNames.length > 0) {
            const updateRows = pendingUpdateNames.map(name => {
                // Try to extract KB number if present
                const kbMatch = name.match(/KB\d+/i);
                const kbNumber = kbMatch ? kbMatch[0] : '';
                return `<tr><td class="pending-update-name" title="${this.escapeHtml(name)}">${this.escapeHtml(name)}</td></tr>`;
            }).join('');
            
            pendingUpdatesTableHtml = `
                <div class="pending-updates-table-container">
                    <table class="pending-updates-table">
                        <thead>
                            <tr><th>Pending Updates (${pendingUpdateNames.length})</th></tr>
                        </thead>
                        <tbody>
                            ${updateRows}
                        </tbody>
                    </table>
                </div>
            `;
        }

        content.innerHTML = `
            <div class="updates-status ${statusClass}">
                <div class="updates-status-icon">${statusIcon}</div>
                <div class="updates-status-text">${statusText}</div>
            </div>
            
            <div class="updates-grid">
                <div class="update-stat ${hasPendingUpdates ? 'has-updates' : ''}">
                    <div class="update-stat-value">${pendingCount}</div>
                    <div class="update-stat-label">Pending</div>
                </div>
                <div class="update-stat ${hasSecurityUpdates ? 'critical' : ''}">
                    <div class="update-stat-value">${securityUpdates}</div>
                    <div class="update-stat-label">Security</div>
                </div>
                <div class="update-stat ${hasCriticalUpdates ? 'critical' : ''}">
                    <div class="update-stat-value">${criticalUpdates}</div>
                    <div class="update-stat-label">Critical</div>
                </div>
                <div class="update-stat last-update ${daysSinceUpdate > 30 ? 'warning' : ''}">
                    <div class="update-stat-value">${lastInstallFormatted}</div>
                    <div class="update-stat-label">Last Install${daysSinceUpdate !== null ? ` (${daysSinceUpdate}d ago)` : ''}</div>
                </div>
            </div>
            ${pendingUpdatesTableHtml}
        `;
    }

    /**
     * Renders the disks section with all drives
     */
    renderDisksSection(diskDrives) {
        // Find or create disks panel
        let disksPanel = document.getElementById('disksPanel');
        if (!disksPanel) {
            // Create the disks panel after metrics grid
            const metricsGrid = document.getElementById('metricsGrid');
            if (metricsGrid) {
                disksPanel = document.createElement('div');
                disksPanel.id = 'disksPanel';
                disksPanel.className = 'panel disks-panel';
                metricsGrid.parentNode.insertBefore(disksPanel, metricsGrid.nextSibling);
            }
        }
        
        if (!disksPanel || !diskDrives || diskDrives.length === 0) return;

        const diskCardsHtml = diskDrives.map((disk, index) => {
            const diskPercent = disk.usedPercent || disk.percentUsed || 0;
            const diskTotalGb = disk.totalGB || disk.totalGb || 0;
            const diskAvailableGb = disk.availableGB || disk.freeGB || disk.freeGb || 0;
            const diskUsedGb = disk.usedGB || disk.usedGb || (diskTotalGb - diskAvailableGb);
            const driveLetter = disk.drive || `Drive ${index + 1}`;
            
            return `
                <div class="disk-card-item">
                    <div class="disk-header">
                        <span class="disk-drive">💾 ${driveLetter}</span>
                        <span class="disk-fs-badge">${disk.fileSystem || 'NTFS'}</span>
                    </div>
                    <div class="disk-bar-wrapper">
                        <div class="disk-bar-bg">
                            <div class="disk-bar-fill" style="width: ${diskPercent}%; background: ${this.getDiskColor(diskPercent)}"></div>
                        </div>
                        <span class="disk-percent-label">${diskPercent.toFixed(1)}%</span>
                    </div>
                    <div class="disk-info">
                        <span class="disk-used">${diskUsedGb.toFixed(0)} / ${diskTotalGb.toFixed(0)} GB used</span>
                        <span class="disk-free">${diskAvailableGb.toFixed(0)} GB free</span>
                    </div>
                </div>
            `;
        }).join('');

        disksPanel.innerHTML = `
            <div class="panel-header">
                <span class="panel-title">💿 Storage Drives</span>
                <span class="panel-badge">${diskDrives.length}</span>
            </div>
            <div class="disks-grid">
                ${diskCardsHtml}
            </div>
        `;
    }

    /**
     * Gets color for disk usage bar based on percentage
     */
    getDiskColor(percent) {
        if (percent >= 90) return 'var(--error-color)';
        if (percent >= 75) return 'var(--warning-color)';
        return 'var(--success-color)';
    }

    /**
     * Creates an SVG speedometer/gauge visualization
     */
    createGaugeSVG(percent, type) {
        const radius = 60;
        const strokeWidth = 12;
        const normalizedPercent = Math.min(100, Math.max(0, percent));
        
        // Calculate the arc (180 degrees = half circle, like a speedometer)
        const circumference = Math.PI * radius; // Half circle
        const offset = circumference - (normalizedPercent / 100) * circumference;
        
        // Determine color based on value
        let color;
        if (normalizedPercent >= 90) {
            color = 'var(--error-color)';
        } else if (normalizedPercent >= 75) {
            color = 'var(--warning-color)';
        } else {
            color = 'var(--success-color)';
        }

        // Create gradient colors for visual appeal
        const gradientId = `gauge-gradient-${type}-${Date.now()}`;
        
        return `
            <div class="gauge-container">
                <svg viewBox="0 0 140 80" class="gauge-svg">
                    <defs>
                        <linearGradient id="${gradientId}" x1="0%" y1="0%" x2="100%" y2="0%">
                            <stop offset="0%" style="stop-color: var(--success-color)"/>
                            <stop offset="50%" style="stop-color: var(--warning-color)"/>
                            <stop offset="100%" style="stop-color: var(--error-color)"/>
                        </linearGradient>
                    </defs>
                    <!-- Background arc -->
                    <path
                        d="M 10 70 A ${radius} ${radius} 0 0 1 130 70"
                        fill="none"
                        stroke="var(--gauge-bg)"
                        stroke-width="${strokeWidth}"
                        stroke-linecap="round"
                    />
                    <!-- Value arc -->
                    <path
                        d="M 10 70 A ${radius} ${radius} 0 0 1 130 70"
                        fill="none"
                        stroke="${color}"
                        stroke-width="${strokeWidth}"
                        stroke-linecap="round"
                        stroke-dasharray="${circumference}"
                        stroke-dashoffset="${offset}"
                        class="gauge-value-arc"
                    />
                    <!-- Tick marks -->
                    <line x1="10" y1="70" x2="18" y2="70" stroke="var(--text-muted)" stroke-width="2"/>
                    <line x1="70" y1="10" x2="70" y2="18" stroke="var(--text-muted)" stroke-width="2"/>
                    <line x1="130" y1="70" x2="122" y2="70" stroke="var(--text-muted)" stroke-width="2"/>
                    <!-- Labels -->
                    <text x="10" y="78" font-size="8" fill="var(--text-muted)" text-anchor="middle">0</text>
                    <text x="70" y="8" font-size="8" fill="var(--text-muted)" text-anchor="middle">50</text>
                    <text x="130" y="78" font-size="8" fill="var(--text-muted)" text-anchor="middle">100</text>
                </svg>
            </div>
        `;
    }

    renderAlerts() {
        const alerts = this.currentSnapshot?.alerts || [];
        const container = document.getElementById('alertsPanel');
        if (!container) return;

        if (alerts.length === 0) {
            container.classList.add('hidden');
            return;
        }

        container.classList.remove('hidden');
        const tbody = container.querySelector('tbody');
        if (!tbody) return;

        // Helper to normalize severity (handles both string from agent and number fallback)
        const normalizeSeverity = (sev) => {
            // Agent now sends strings like "critical", "warning", "informational"
            if (typeof sev === 'string') return sev;
            // Fallback for numeric values (legacy)
            const names = ['informational', 'warning', 'critical'];
            return names[sev] || 'unknown';
        };

        const getSeverityClass = (sev) => {
            const name = normalizeSeverity(sev).toLowerCase();
            if (name === 'critical') return 'critical';
            if (name === 'warning') return 'warning';
            return 'info';
        };

        // Sort by severity, then timestamp desc
        const severityOrder = { critical: 0, warning: 1, informational: 2 };
        const sorted = [...alerts].sort((a, b) => {
            const aSev = severityOrder[normalizeSeverity(a.severity)] ?? 3;
            const bSev = severityOrder[normalizeSeverity(b.severity)] ?? 3;
            if (aSev !== bSev) return aSev - bSev;
            return new Date(b.timestamp) - new Date(a.timestamp);
        });

        // Store alerts for click handlers
        this._displayedAlerts = sorted;

        tbody.innerHTML = sorted.map((alert, idx) => {
            const sevName = normalizeSeverity(alert.severity);
            const sevClass = getSeverityClass(alert.severity);
            const displayName = sevName.charAt(0).toUpperCase() + sevName.slice(1);
            const hasMetadata = alert.metadata && Object.keys(alert.metadata).length > 0;
            const hasDetails = alert.details || hasMetadata;
            
            // Extract relevant context from metadata
            const context = this.extractAlertContext(alert);
            
            return `
                <tr class="alert-row ${hasDetails ? 'expandable' : ''}" data-alert-idx="${idx}">
                    <td><span class="severity-badge ${sevClass}">${displayName}</span></td>
                    <td>${alert.category || '-'}</td>
                    <td class="alert-message-cell">
                        ${alert.message || '-'}
                        ${hasDetails ? '<span class="expand-indicator">▶</span>' : ''}
                    </td>
                    <td class="alert-context-cell">${context}</td>
                    <td class="alert-time-cell">
                        ${this.formatTime(alert.timestamp)}
                        <button class="btn-icon btn-copy-md" title="Copy as Markdown">📝</button>
                        <button class="btn-icon btn-copy-json" title="Copy as JSON">📋</button>
                        ${hasDetails ? '<button class="btn-icon btn-open-modal" title="Open in modal">🔍</button>' : ''}
                    </td>
                </tr>
                <tr class="alert-details-row hidden" data-alert-details-idx="${idx}">
                    <td colspan="5">
                        <div class="alert-details-content">
                            ${this.formatAlertDetails(alert)}
                        </div>
                    </td>
                </tr>
            `;
        }).join('');

        // Add click handlers for expandable rows
        tbody.querySelectorAll('.alert-row.expandable').forEach(row => {
            row.addEventListener('click', (e) => {
                // Don't expand if clicking the modal button
                if (e.target.closest('.btn-open-modal')) return;
                
                const idx = row.dataset.alertIdx;
                const detailsRow = tbody.querySelector(`[data-alert-details-idx="${idx}"]`);
                const indicator = row.querySelector('.expand-indicator');
                
                if (detailsRow) {
                    detailsRow.classList.toggle('hidden');
                    row.classList.toggle('expanded');
                    if (indicator) {
                        indicator.textContent = detailsRow.classList.contains('hidden') ? '▶' : '▼';
                    }
                }
            });
        });

        // Add click handlers for modal buttons
        tbody.querySelectorAll('.btn-open-modal').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const row = btn.closest('.alert-row');
                const idx = parseInt(row.dataset.alertIdx);
                const alert = this._displayedAlerts[idx];
                if (alert) {
                    this.showAlertModal(alert);
                }
            });
        });

        // Add click handlers for copy markdown buttons
        tbody.querySelectorAll('.btn-copy-md').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const row = btn.closest('.alert-row');
                const idx = parseInt(row.dataset.alertIdx);
                const alert = this._displayedAlerts[idx];
                if (alert) {
                    this.copyAlertAsMarkdown(alert);
                }
            });
        });

        // Add click handlers for copy JSON buttons
        tbody.querySelectorAll('.btn-copy-json').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const row = btn.closest('.alert-row');
                const idx = parseInt(row.dataset.alertIdx);
                const alert = this._displayedAlerts[idx];
                if (alert) {
                    this.copyAlertAsJson(alert);
                }
            });
        });

        // Update count in header
        const countBadge = container.querySelector('.alert-count');
        if (countBadge) countBadge.textContent = alerts.length;
    }

    /**
     * Format alert details for inline display
     */
    formatAlertDetails(alert) {
        let html = '<div class="alert-metadata">';
        
        // Alert ID first (most important for reference)
        if (alert.id) {
            html += `<div class="metadata-item alert-id-inline"><span class="metadata-key">Alert ID:</span> <span class="metadata-val alert-id-val">${alert.id}</span></div>`;
        }
        
        // Basic details
        if (alert.details) {
            html += `<div class="metadata-section">
                <div class="metadata-label">Details</div>
                <div class="metadata-value">${this.escapeHtml(alert.details)}</div>
            </div>`;
        }
        
        if (alert.timestamp) {
            html += `<div class="metadata-item"><span class="metadata-key">Timestamp:</span> <span class="metadata-val">${new Date(alert.timestamp).toLocaleString()}</span></div>`;
        }
        
        // Distribution history
        if (alert.distributionHistory && alert.distributionHistory.length > 0) {
            html += `<div class="metadata-section">
                <div class="metadata-label">Distribution History</div>
                <div class="distribution-list">`;
            alert.distributionHistory.forEach(d => {
                const icon = d.success ? '✅' : '❌';
                html += `<div class="distribution-item">${icon} ${d.channelType} → ${d.destination || 'N/A'} (${new Date(d.timestamp).toLocaleTimeString()})</div>`;
            });
            html += '</div></div>';
        }
        
        // Metadata object (exclude Db2RawBlock - shown separately)
        const metadataEntries = alert.metadata ? 
            Object.entries(alert.metadata).filter(([key]) => key !== 'Db2RawBlock') : [];
        
        if (metadataEntries.length > 0) {
            html += `<div class="metadata-section">
                <div class="metadata-label">Metadata</div>
                <div class="metadata-grid">`;
            for (const [key, value] of metadataEntries) {
                const displayValue = typeof value === 'object' ? JSON.stringify(value, null, 2) : value;
                html += `<div class="metadata-item">
                    <span class="metadata-key">${this.escapeHtml(key)}:</span>
                    <span class="metadata-val">${this.escapeHtml(String(displayValue))}</span>
                </div>`;
            }
            html += '</div></div>';
        }
        
        // Db2RawBlock shown separately in full width
        if (alert.metadata?.Db2RawBlock) {
            html += `<div class="metadata-section">
                <div class="metadata-label">DB2 Raw Log Block</div>
                <pre class="db2-raw-message">${this.escapeHtml(alert.metadata.Db2RawBlock)}</pre>
            </div>`;
        }
        
        html += '</div>';
        return html;
    }

    /**
     * Show alert in a modal dialog
     */
    showAlertModal(alert) {
        // Remove existing modal if any
        const existingModal = document.getElementById('alertModal');
        if (existingModal) existingModal.remove();
        
        const sevName = typeof alert.severity === 'string' ? alert.severity : 'unknown';
        const sevClass = sevName.toLowerCase() === 'critical' ? 'critical' : 
                        sevName.toLowerCase() === 'warning' ? 'warning' : 'info';
        
        const modal = document.createElement('div');
        modal.id = 'alertModal';
        modal.className = 'modal-overlay';
        modal.innerHTML = `
            <div class="modal-container">
                <div class="modal-header">
                    <h3>
                        <span class="severity-badge ${sevClass}">${sevName}</span>
                        Alert Details
                    </h3>
                    <div class="modal-actions">
                        ${!this.isStandardAccess ? `<button class="btn btn-sm btn-open-window" title="Open in new window">🔗 New Window</button>` : ''}
                        <button class="btn btn-sm btn-copy-markdown" title="Copy as Markdown">📝 Copy MD</button>
                        <button class="btn btn-sm btn-copy-json" title="Copy as JSON">📋 Copy JSON</button>
                        <button class="modal-close" title="Close">&times;</button>
                    </div>
                </div>
                <div class="modal-body">
                    <div class="alert-modal-content">
                        <div class="alert-main-info">
                            ${alert.id ? `
                            <div class="alert-info-row alert-id-row">
                                <span class="alert-info-label">Alert ID:</span>
                                <span class="alert-info-value alert-id-value">${this.escapeHtml(alert.id)}</span>
                            </div>` : ''}
                            <div class="alert-info-row">
                                <span class="alert-info-label">Category:</span>
                                <span class="alert-info-value">${this.escapeHtml(alert.category || '-')}</span>
                            </div>
                            <div class="alert-info-row">
                                <span class="alert-info-label">Message:</span>
                                <span class="alert-info-value">${this.escapeHtml(alert.message || '-')}</span>
                            </div>
                            <div class="alert-info-row">
                                <span class="alert-info-label">Time:</span>
                                <span class="alert-info-value">${new Date(alert.timestamp).toLocaleString()}</span>
                            </div>
                            ${alert.details ? `
                            <div class="alert-info-row">
                                <span class="alert-info-label">Details:</span>
                                <span class="alert-info-value">${this.escapeHtml(alert.details)}</span>
                            </div>` : ''}
                        </div>
                        
                        ${alert.distributionHistory && alert.distributionHistory.length > 0 ? `
                        <div class="modal-section">
                            <h4>📤 Distribution History</h4>
                            <table class="modal-table">
                                <thead>
                                    <tr>
                                        <th>Status</th>
                                        <th>Channel</th>
                                        <th>Destination</th>
                                        <th>Time</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    ${alert.distributionHistory.map(d => `
                                    <tr>
                                        <td>${d.success ? '✅' : '❌'}</td>
                                        <td>${this.escapeHtml(d.channelType)}</td>
                                        <td>${this.escapeHtml(d.destination || '-')}</td>
                                        <td>${new Date(d.timestamp).toLocaleTimeString()}</td>
                                    </tr>`).join('')}
                                </tbody>
                            </table>
                        </div>` : ''}
                        
                        ${alert.metadata && Object.keys(alert.metadata).length > 0 ? `
                        <div class="modal-section">
                            <h4>📊 Metadata</h4>
                            <div class="metadata-table">
                                ${Object.entries(alert.metadata)
                                    .filter(([key]) => key !== 'Db2RawBlock')
                                    .map(([key, value]) => `
                                <div class="metadata-row">
                                    <div class="metadata-key">${this.escapeHtml(key)}</div>
                                    <div class="metadata-value">${this.escapeHtml(typeof value === 'object' ? JSON.stringify(value, null, 2) : String(value))}</div>
                                </div>`).join('')}
                            </div>
                        </div>` : ''}
                        
                        ${alert.metadata?.Db2RawBlock ? `
                        <div class="modal-section">
                            <h4>📋 DB2 Raw Log Block</h4>
                            <pre class="db2-raw-message">${this.escapeHtml(alert.metadata.Db2RawBlock)}</pre>
                        </div>` : ''}
                        
                        <div class="modal-section">
                            <h4>📝 Raw JSON</h4>
                            <pre class="json-display">${this.escapeHtml(JSON.stringify(alert, null, 2))}</pre>
                        </div>
                    </div>
                </div>
            </div>
        `;
        
        document.body.appendChild(modal);
        
        // Close handlers
        modal.querySelector('.modal-close').addEventListener('click', () => modal.remove());
        modal.addEventListener('click', (e) => {
            if (e.target === modal) modal.remove();
        });
        
        // Copy JSON handler
        modal.querySelector('.btn-copy-json').addEventListener('click', async () => {
            try {
                await navigator.clipboard.writeText(JSON.stringify(alert, null, 2));
                this.showToast('📋 Alert JSON copied to clipboard!');
            } catch (err) {
                // Fallback for non-HTTPS contexts
                this.copyToClipboardFallback(JSON.stringify(alert, null, 2));
                this.showToast('📋 Alert JSON copied to clipboard!');
            }
        });
        
        // Copy Markdown handler
        modal.querySelector('.btn-copy-markdown').addEventListener('click', async () => {
            try {
                const markdown = this.formatAlertAsMarkdown(alert);
                await navigator.clipboard.writeText(markdown);
                this.showToast('📝 Alert Markdown copied to clipboard!');
            } catch (err) {
                // Fallback for non-HTTPS contexts
                const markdown = this.formatAlertAsMarkdown(alert);
                this.copyToClipboardFallback(markdown);
                this.showToast('📝 Alert Markdown copied to clipboard!');
            }
        });
        
        // Open in new window handler (only if button exists - not for Standard access)
        const openWindowBtn = modal.querySelector('.btn-open-window');
        if (openWindowBtn) openWindowBtn.addEventListener('click', () => {
            const alertJson = JSON.stringify(alert, null, 2);
            const alertMarkdown = this.formatAlertAsMarkdown(alert);
            const newWindow = window.open('', '_blank', 'width=1170,height=700');
            newWindow.document.write(`
                <!DOCTYPE html>
                <html>
                <head>
                    <title>Alert Details - ${alert.category || 'Alert'}</title>
                    <style>
                        body { 
                            font-family: 'Consolas', monospace; 
                            background: #1a1a1a; 
                            color: #e0e0e0; 
                            padding: 20px; 
                            margin: 0;
                        }
                        h1 { color: #F7DE00; margin-bottom: 20px; display: flex; align-items: center; gap: 10px; }
                        .section { margin-bottom: 20px; }
                        .section h2 { color: #008942; font-size: 1.1rem; border-bottom: 1px solid #333; padding-bottom: 5px; }
                        .row { display: grid; grid-template-columns: minmax(200px, auto) 1fr; gap: 1rem; padding: 5px 0; border-bottom: 1px solid #2a2a2a; }
                        .key { color: #888; white-space: nowrap; font-size: 0.9rem; }
                        .value { color: #fff; word-break: break-word; }
                        pre { background: #0a0a0a; padding: 15px; border-radius: 5px; overflow-x: auto; font-size: 12px; white-space: pre-wrap; word-wrap: break-word; }
                        .badge { 
                            display: inline-block; 
                            padding: 3px 8px; 
                            border-radius: 4px; 
                            font-size: 0.8rem;
                            font-weight: bold;
                        }
                        .critical { background: #dc2626; }
                        .warning { background: #d97706; }
                        .info { background: #0369a1; }
                        .copy-btn {
                            padding: 8px 16px;
                            border: none;
                            border-radius: 6px;
                            cursor: pointer;
                            font-size: 0.85rem;
                            font-weight: 600;
                            transition: all 0.2s;
                        }
                        .copy-md { background: #8b5cf6; color: white; }
                        .copy-md:hover { background: #7c3aed; }
                        .copy-json { background: #3b82f6; color: white; }
                        .copy-json:hover { background: #2563eb; }
                        .btn-group { display: flex; gap: 8px; margin-left: auto; }
                        .toast {
                            position: fixed;
                            bottom: 20px;
                            left: 50%;
                            transform: translateX(-50%);
                            background: #22c55e;
                            color: white;
                            padding: 10px 20px;
                            border-radius: 6px;
                            font-weight: 600;
                            opacity: 0;
                            transition: opacity 0.3s;
                        }
                        .toast.show { opacity: 1; }
                    </style>
                </head>
                <body>
                    <h1>
                        <span class="badge ${sevClass}">${sevName}</span> 
                        Alert Details
                        <div class="btn-group">
                            <button class="copy-btn copy-md" onclick="copyMarkdown()">📝 Copy MD</button>
                            <button class="copy-btn copy-json" onclick="copyJson()">📋 Copy JSON</button>
                        </div>
                    </h1>
                    
                    <div class="section">
                        <h2>Basic Information</h2>
                        ${alert.id ? `<div class="row"><span class="key">Alert ID:</span><span class="value" style="font-family: monospace; color: #F7DE00;">${alert.id}</span></div>` : ''}
                        <div class="row"><span class="key">Category:</span><span class="value">${this.escapeHtml(alert.category || '-')}</span></div>
                        <div class="row"><span class="key">Message:</span><span class="value">${this.escapeHtml(alert.message || '-')}</span></div>
                        <div class="row"><span class="key">Timestamp:</span><span class="value">${new Date(alert.timestamp).toLocaleString()}</span></div>
                        ${alert.details ? `<div class="row"><span class="key">Details:</span><span class="value">${this.escapeHtml(alert.details)}</span></div>` : ''}
                    </div>
                    
                    ${alert.metadata && Object.keys(alert.metadata).length > 0 ? `
                    <div class="section">
                        <h2>Metadata</h2>
                        ${Object.entries(alert.metadata).map(([k, v]) => `
                        <div class="row">
                            <span class="key">${this.escapeHtml(k)}:</span>
                            <span class="value">${this.escapeHtml(typeof v === 'object' ? JSON.stringify(v) : String(v))}</span>
                        </div>`).join('')}
                    </div>` : ''}
                    
                    <div class="section">
                        <h2>Raw JSON</h2>
                        <pre>${this.escapeHtml(alertJson)}</pre>
                    </div>
                    
                    <div id="toast" class="toast"></div>
                    
                    <script>
                        const alertJson = ${JSON.stringify(alertJson)};
                        const alertMarkdown = ${JSON.stringify(alertMarkdown)};
                        
                        function showToast(msg) {
                            const toast = document.getElementById('toast');
                            toast.textContent = msg;
                            toast.classList.add('show');
                            setTimeout(() => toast.classList.remove('show'), 2000);
                        }
                        
                        function copyToClipboard(text) {
                            if (navigator.clipboard) {
                                navigator.clipboard.writeText(text).then(() => {}).catch(() => fallbackCopy(text));
                            } else {
                                fallbackCopy(text);
                            }
                        }
                        
                        function fallbackCopy(text) {
                            const ta = document.createElement('textarea');
                            ta.value = text;
                            ta.style.position = 'fixed';
                            ta.style.left = '-9999px';
                            document.body.appendChild(ta);
                            ta.select();
                            document.execCommand('copy');
                            document.body.removeChild(ta);
                        }
                        
                        function copyJson() {
                            copyToClipboard(alertJson);
                            showToast('📋 JSON copied to clipboard!');
                        }
                        
                        function copyMarkdown() {
                            copyToClipboard(alertMarkdown);
                            showToast('📝 Markdown copied to clipboard!');
                        }
                    <\/script>
                </body>
                </html>
            `);
            newWindow.document.close();
        });
        
        // ESC to close
        const escHandler = (e) => {
            if (e.key === 'Escape') {
                modal.remove();
                document.removeEventListener('keydown', escHandler);
            }
        };
        document.addEventListener('keydown', escHandler);
    }

    /**
     * Escape HTML to prevent XSS
     */
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    /**
     * Format alert data as pretty Markdown for copying
     */
    formatAlertAsMarkdown(alert) {
        const serverName = this.currentServer || 'Unknown Server';
        const timestamp = new Date(alert.timestamp).toLocaleString();
        const severity = (alert.severity || 'Unknown').toUpperCase();
        const severityEmoji = severity === 'CRITICAL' ? '🔴' : severity === 'WARNING' ? '🟠' : '🔵';
        
        let md = [];
        
        // Header
        md.push(`# ${severityEmoji} Alert: ${alert.category || 'System Alert'}`);
        md.push('');
        
        // Basic Info Table
        md.push('## Summary');
        md.push('');
        md.push('| Field | Value |');
        md.push('|-------|-------|');
        md.push(`| **Server** | ${serverName} |`);
        md.push(`| **Severity** | ${severity} |`);
        md.push(`| **Category** | ${alert.category || '-'} |`);
        md.push(`| **Timestamp** | ${timestamp} |`);
        if (alert.id) md.push(`| **Alert ID** | ${alert.id} |`);
        md.push('');
        
        // Message
        md.push('## Message');
        md.push('');
        md.push('```');
        md.push(alert.message || 'No message');
        md.push('```');
        md.push('');
        
        // Details (if present)
        if (alert.details) {
            md.push('## Details');
            md.push('');
            md.push(alert.details);
            md.push('');
        }
        
        // Metadata
        if (alert.metadata && Object.keys(alert.metadata).length > 0) {
            md.push('## Metadata');
            md.push('');
            md.push('| Key | Value |');
            md.push('|-----|-------|');
            
            for (const [key, value] of Object.entries(alert.metadata)) {
                if (key === 'Db2RawBlock') continue; // Handle separately
                const displayValue = typeof value === 'object' ? JSON.stringify(value) : String(value);
                // Escape pipe characters in values for Markdown tables
                const escapedValue = displayValue.replace(/\|/g, '\\|').replace(/\n/g, ' ');
                md.push(`| ${key} | ${escapedValue} |`);
            }
            md.push('');
            
            // DB2 Raw Block (if present)
            if (alert.metadata.Db2RawBlock) {
                md.push('### DB2 Raw Log Block');
                md.push('');
                md.push('```');
                md.push(alert.metadata.Db2RawBlock);
                md.push('```');
                md.push('');
            }
        }
        
        // Distribution History
        if (alert.distributionHistory && alert.distributionHistory.length > 0) {
            md.push('## Distribution History');
            md.push('');
            md.push('| Status | Channel | Destination | Time |');
            md.push('|--------|---------|-------------|------|');
            
            for (const d of alert.distributionHistory) {
                const status = d.success ? '✅ Success' : '❌ Failed';
                const time = new Date(d.timestamp).toLocaleTimeString();
                md.push(`| ${status} | ${d.channelType || '-'} | ${d.destination || '-'} | ${time} |`);
            }
            md.push('');
        }
        
        // Raw JSON (collapsible in some Markdown renderers)
        md.push('<details>');
        md.push('<summary>Raw JSON</summary>');
        md.push('');
        md.push('```json');
        md.push(JSON.stringify(alert, null, 2));
        md.push('```');
        md.push('');
        md.push('</details>');
        md.push('');
        
        // Footer
        md.push('---');
        md.push(`*Generated from ServerMonitor Dashboard on ${new Date().toLocaleString()}*`);
        
        return md.join('\n');
    }

    /**
     * Show a temporary toast notification
     */
    showToast(message, duration = 2000) {
        // Remove existing toast if any
        const existingToast = document.getElementById('dashboardToast');
        if (existingToast) existingToast.remove();
        
        const toast = document.createElement('div');
        toast.id = 'dashboardToast';
        toast.style.cssText = `
            position: fixed;
            bottom: 20px;
            left: 50%;
            transform: translateX(-50%);
            background: var(--bg-card, #1a1a1a);
            color: var(--text-primary, #fff);
            padding: 12px 24px;
            border-radius: 8px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
            border: 1px solid var(--border-color, #333);
            font-size: 0.9rem;
            z-index: 10000;
            animation: toastSlideUp 0.3s ease;
        `;
        toast.textContent = message;
        
        // Add animation keyframes if not already present
        if (!document.getElementById('toastAnimations')) {
            const style = document.createElement('style');
            style.id = 'toastAnimations';
            style.textContent = `
                @keyframes toastSlideUp {
                    from { opacity: 0; transform: translateX(-50%) translateY(20px); }
                    to { opacity: 1; transform: translateX(-50%) translateY(0); }
                }
                @keyframes toastFadeOut {
                    from { opacity: 1; }
                    to { opacity: 0; }
                }
            `;
            document.head.appendChild(style);
        }
        
        document.body.appendChild(toast);
        
        // Remove after duration
        setTimeout(() => {
            toast.style.animation = 'toastFadeOut 0.3s ease forwards';
            setTimeout(() => toast.remove(), 300);
        }, duration);
    }

    /**
     * Fallback copy to clipboard for non-HTTPS contexts
     */
    copyToClipboardFallback(text) {
        const textArea = document.createElement('textarea');
        textArea.value = text;
        textArea.style.position = 'fixed';
        textArea.style.left = '-9999px';
        textArea.style.top = '0';
        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();
        try {
            document.execCommand('copy');
        } catch (err) {
            console.error('Fallback copy failed:', err);
        }
        document.body.removeChild(textArea);
    }

    /**
     * Copy alert as JSON to clipboard
     */
    async copyAlertAsJson(alert) {
        const json = JSON.stringify(alert, null, 2);
        try {
            await navigator.clipboard.writeText(json);
        } catch (err) {
            this.copyToClipboardFallback(json);
        }
        this.showToast('📋 Alert JSON copied to clipboard!');
    }

    /**
     * Copy alert as Markdown to clipboard
     */
    async copyAlertAsMarkdown(alert) {
        const markdown = this.formatAlertAsMarkdown(alert);
        try {
            await navigator.clipboard.writeText(markdown);
        } catch (err) {
            this.copyToClipboardFallback(markdown);
        }
        this.showToast('📝 Alert Markdown copied to clipboard!');
    }

    /**
     * Extract the most relevant context from alert metadata for display in table
     */
    extractAlertContext(alert) {
        const meta = alert.metadata || {};
        const parts = [];
        
        // Priority order for different alert types
        // DB2 alerts
        if (meta.Db2Instance) {
            parts.push(`<span class="context-tag db2">📊 ${this.escapeHtml(meta.Db2Instance)}</span>`);
            if (meta.Db2Level) {
                parts.push(`<span class="context-value">${this.escapeHtml(meta.Db2Level)}</span>`);
            }
        }
        
        // Event Log alerts
        if (meta.EventId) {
            parts.push(`<span class="context-tag event">📋 Event ${meta.EventId}</span>`);
        }
        if (meta.Source || meta.EventSource) {
            const source = meta.Source || meta.EventSource;
            parts.push(`<span class="context-value">${this.escapeHtml(source)}</span>`);
        }
        
        // Scheduled Task alerts
        if (meta.TaskName) {
            parts.push(`<span class="context-tag task">📅 ${this.escapeHtml(meta.TaskName)}</span>`);
        }
        if (meta.TaskPath) {
            parts.push(`<span class="context-value">${this.escapeHtml(meta.TaskPath)}</span>`);
        }
        
        // Process alerts
        if (meta.ProcessName) {
            parts.push(`<span class="context-tag process">⚙️ ${this.escapeHtml(meta.ProcessName)}</span>`);
        }
        if (meta.ProcessId || meta.PID) {
            parts.push(`<span class="context-value">PID: ${meta.ProcessId || meta.PID}</span>`);
        }
        
        // Disk alerts
        if (meta.DriveLetter || meta.Drive) {
            const drive = meta.DriveLetter || meta.Drive;
            parts.push(`<span class="context-tag disk">💾 ${this.escapeHtml(drive)}</span>`);
        }
        
        // Network alerts
        if (meta.HostName || meta.Host) {
            const host = meta.HostName || meta.Host;
            parts.push(`<span class="context-tag network">🌐 ${this.escapeHtml(host)}</span>`);
        }
        
        // Service alerts
        if (meta.ServiceName) {
            parts.push(`<span class="context-tag service">🔧 ${this.escapeHtml(meta.ServiceName)}</span>`);
        }
        
        // Windows Update alerts
        if (meta.UpdateTitle || meta.KBNumber) {
            const update = meta.UpdateTitle || `KB${meta.KBNumber}`;
            parts.push(`<span class="context-tag update">📦 ${this.escapeHtml(update)}</span>`);
        }
        
        // CPU/Memory alerts
        if (meta.CpuPercent !== undefined) {
            parts.push(`<span class="context-value">CPU: ${meta.CpuPercent}%</span>`);
        }
        if (meta.MemoryPercent !== undefined) {
            parts.push(`<span class="context-value">Mem: ${meta.MemoryPercent}%</span>`);
        }
        
        // Fallback: show first few metadata keys if nothing matched
        if (parts.length === 0 && Object.keys(meta).length > 0) {
            const keys = Object.keys(meta).slice(0, 2);
            for (const key of keys) {
                const value = meta[key];
                if (value !== null && value !== undefined && typeof value !== 'object') {
                    const displayValue = String(value).length > 20 ? String(value).substring(0, 20) + '...' : String(value);
                    parts.push(`<span class="context-value">${this.escapeHtml(key)}: ${this.escapeHtml(displayValue)}</span>`);
                }
            }
        }
        
        return parts.length > 0 ? parts.join(' ') : '<span class="context-none">-</span>';
    }

    renderTopProcesses() {
        // API returns top processes in memory.topProcesses (sorted by memory usage)
        // Fall back to processor.topProcesses for compatibility
        const processes = this.currentSnapshot?.memory?.topProcesses || 
                          this.currentSnapshot?.processor?.topProcesses || [];
        const container = document.getElementById('processesPanel');
        if (!container) return;

        if (processes.length === 0) {
            container.classList.add('hidden');
            return;
        }

        container.classList.remove('hidden');
        const body = container.querySelector('.panel-body');
        if (!body) return;

        // Find max memory for scaling
        const maxMemory = Math.max(...processes.map(p => p.memoryMB || 0), 100);

        // API uses: name, memoryMB, cpuPercent
        body.innerHTML = `
            <table class="process-table">
                <colgroup>
                    <col style="width: 40%;">
                    <col style="width: 35%;">
                    <col style="width: 25%;">
                </colgroup>
                <thead>
                    <tr>
                        <th>Process</th>
                        <th>Memory</th>
                        <th>CPU</th>
                    </tr>
                </thead>
                <tbody>
                    ${processes.slice(0, 8).map((proc, idx) => {
                        const memoryMB = proc.memoryMB || 0;
                        const cpuPercent = proc.cpuPercent || 0;
                        const processName = proc.name || proc.processName || 'Unknown';
                        const memPercent = (memoryMB / maxMemory) * 100;
                        const cpuClass = cpuPercent > 50 ? 'critical' : cpuPercent > 25 ? 'warning' : 'success';
                        return `
                            <tr class="${idx < 3 ? 'top-process' : ''}">
                                <td class="process-name-cell">
                                    <span class="process-rank">${idx + 1}</span>
                                    <span class="process-name">${processName}</span>
                                </td>
                                <td>
                                    <div class="process-bar">
                                        <div class="process-bar-fill" style="width: ${memPercent}%"></div>
                                        <span class="process-bar-label">${memoryMB.toLocaleString()} MB</span>
                                    </div>
                                </td>
                                <td class="process-cpu ${cpuClass}">${cpuPercent.toFixed(1)}%</td>
                            </tr>
                        `;
                    }).join('')}
                </tbody>
            </table>
        `;
    }

    async renderDb2Panel() {
        const db2Diag = this.currentSnapshot?.db2Diagnostics;
        const db2Instance = this.currentSnapshot?.db2Instance;
        const container = document.getElementById('db2Panel');
        if (!container) return;

        // Check if this is a DB2 server
        const isDb2Server = this.selectedServer?.toLowerCase().includes('-db') || 
                            this.selectedServer?.toLowerCase().includes('db2') ||
                            db2Diag?.isActive === true ||
                            db2Instance != null;
        
        if (!isDb2Server) {
            container.classList.add('hidden');
            return;
        }

        container.classList.remove('hidden');
        
        // Get database data from instance monitoring + diag entries
        const databases = db2Instance?.databases || [];
        const recentEntries = db2Diag?.recentEntries || [];
        const diagSummary = db2Instance?.diagSummary;
        
        // Group diag entries by database
        const diagEntriesByDb = this.groupEntriesByDatabase(recentEntries);
        
        // Hide the stats container - we'll show stats per-database now
        const statsContainer = container.querySelector('.db2-stats');
        if (statsContainer) {
            statsContainer.innerHTML = '';
            statsContainer.style.display = 'none';
        }

        // Body container with per-database STATE panels
            const bodyContainer = container.querySelector('.panel-body');
            if (bodyContainer) {
            let html = '';
            
            // Build a merged list of all databases (from instance data + diag entries)
            const allDatabases = new Map();
            
            // Add from instance monitoring
            // Also pass isInstanceRunning from parent snapshot (for service status indicator)
            const isInstanceRunning = db2Instance?.isInstanceRunning !== false;
            
            for (const db of databases) {
                const key = `${db.databaseName}|${db.instanceName || db2Instance?.instanceName || 'DB2'}`;
                allDatabases.set(key, {
                    databaseName: db.databaseName,
                    instanceName: db.instanceName || db2Instance?.instanceName || 'DB2',
                    instanceData: db,
                    isInstanceRunning: isInstanceRunning,
                    diagEntries: []
                });
            }
            
            // Add/merge from diag entries
            for (const [key, data] of Object.entries(diagEntriesByDb)) {
                if (allDatabases.has(key)) {
                    allDatabases.get(key).diagEntries = data.entries;
                } else {
                    allDatabases.set(key, {
                        databaseName: data.databaseName,
                        instanceName: data.instanceName,
                        instanceData: null,
                        diagEntries: data.entries
                    });
                }
            }
            
            // Sort databases: those with issues first, then by sessions
            const sortedDatabases = Array.from(allDatabases.values()).sort((a, b) => {
                const aBlocking = a.instanceData?.blockingSessions?.length || 0;
                const bBlocking = b.instanceData?.blockingSessions?.length || 0;
                if (aBlocking !== bBlocking) return bBlocking - aBlocking;
                
                const aLongOps = a.instanceData?.longRunningQueries?.length || 0;
                const bLongOps = b.instanceData?.longRunningQueries?.length || 0;
                if (aLongOps !== bLongOps) return bLongOps - aLongOps;
                
                const aSessions = a.instanceData?.totalSessions || 0;
                const bSessions = b.instanceData?.totalSessions || 0;
                return bSessions - aSessions;
            });
            
            // Fetch SQL error log files once for all databases
            const sqlErrorLogFiles = await this.fetchSqlErrorLogFiles();
            
            // Render each database STATE panel
            for (const dbData of sortedDatabases) {
                // Filter SQL error logs for this database
                const dbLogFiles = sqlErrorLogFiles.filter(f => 
                    f.fileName.toLowerCase().includes(`_${dbData.databaseName.toLowerCase()}_`)
                );
                html += this.renderDb2DatabaseStatePanel(dbData, diagSummary, dbLogFiles);
            }
            
            // Empty state if no databases
            if (!html) {
                html = `
                    <div class="db2-empty-state">
                        <div class="db2-empty-icon">🗄️</div>
                        <div class="db2-empty-text">No DB2 State Data</div>
                        <div class="db2-empty-hint">${db2Diag?.inactiveReason || 'DB2 instance monitoring may be disabled or no active databases'}</div>
                    </div>
                `;
            }
            
            bodyContainer.innerHTML = html;
            
            // Add click handlers for SQL error log files
            bodyContainer.querySelectorAll('.db2-log-file-item').forEach(item => {
                item.addEventListener('click', () => {
                    const fileName = item.dataset.filename;
                    this.openLogFileViewer(fileName);
                });
            });
        }
    }
    
    /**
     * Fetch SQL error log files for the current server
     */
    async fetchSqlErrorLogFiles() {
        if (!this.selectedServer) return [];
        
        try {
            const response = await fetch(`api/logfiles/sqlerrors/${this.selectedServer}`);
            if (!response.ok) {
                return [];
            }
            return await response.json();
        } catch (error) {
            console.error('Failed to fetch SQL error log files:', error);
            return [];
        }
    }
    
    /**
     * Render a single database state panel
     */
    renderDb2DatabaseStatePanel(dbData, globalDiagSummary, sqlErrorLogFiles = []) {
        const { databaseName, instanceName, instanceData, isInstanceRunning, diagEntries } = dbData;
        
        // Use per-database diag summary if available, otherwise fallback to global
        const diagSummary = instanceData?.diagSummary || globalDiagSummary;
        
        // Extract metrics
        const sessions = instanceData?.totalSessions || 0;
        const users = instanceData?.uniqueUsers || 0;
        const bpHitRatio = instanceData?.bufferPoolHitRatio;
        const dbSizeGb = instanceData?.databaseSizeGb;
        const blockingSessions = instanceData?.blockingSessions || [];
        const longRunningQueries = instanceData?.longRunningQueries || [];
        
        const diagLogSizeMb = instanceData?.db2DiagLogSizeMb;
        const healthCounters = instanceData?.healthCounters;
        const transactionLog = instanceData?.transactionLog;
        
        // Count diag errors/warnings from entries
        const diagErrors = diagEntries.filter(e => 
            e.level === 'Error' || e.level === 'Critical' || e.level === 'Severe'
        ).length;
        const diagWarnings = diagEntries.filter(e => e.level === 'Warning').length;
        
        // Check for issues (used for counter styling, not status indicator)
        const hasBlocking = blockingSessions.length > 0;
        const hasLongOps = longRunningQueries.length > 0;
        
        // Determine panel status
        // Red = instance service is down (from Windows service check)
        // Green = instance service is running
        // (Diag issues are shown via counters, not the status indicator)
        const isServiceRunning = isInstanceRunning !== false; // From parent snapshot
        const isDbActive = instanceData?.isActive !== false;
        
        let statusClass = 'ok';
        let statusIndicator = '🟢';
        if (!isServiceRunning || !isDbActive) {
            // Red only when DB2 instance service is down
            statusClass = 'critical';
            statusIndicator = '🔴';
        }
        // No yellow state - only red (down) or green (up)
        // Issues are shown via the counters (blocking, long ops, diag issues)
        
        // Build gauge for BP Hit Ratio
        const bpGaugeHtml = bpHitRatio != null ? this.renderGauge(bpHitRatio, 100, 'BP Hit %', 
            bpHitRatio >= 95 ? 'var(--success-color)' : bpHitRatio >= 90 ? 'var(--warning-color)' : 'var(--critical-color)'
        ) : '';
        
        // Build sessions gauge
        const sessionMax = 100;
        const sessionGaugeHtml = this.renderGauge(sessions, sessionMax, 'Sessions',
            sessions < 50 ? 'var(--success-color)' : sessions < 80 ? 'var(--warning-color)' : 'var(--critical-color)'
        );

        // Build transaction log utilization gauge
        const logPct = transactionLog?.logUtilizationPercent;
        const logGaugeHtml = logPct != null ? this.renderGauge(logPct, 100, 'Log Util %',
            logPct < 70 ? 'var(--success-color)' : logPct < 90 ? 'var(--warning-color)' : 'var(--critical-color)'
        ) : '';
        
        return `
            <div class="db2-state-panel ${statusClass}">
                <div class="db2-state-header" onclick="this.parentElement.classList.toggle('collapsed')">
                    <div class="db2-state-title">
                        <span class="db2-state-indicator">${statusIndicator}</span>
                        <span>🗄️ Db2 State Information: <strong>${this.escapeHtml(databaseName)}</strong> (${this.escapeHtml(instanceName)})</span>
                </div>
                    <div class="db2-state-actions">
                        ${(this.db2DashboardConfig.enablePopout !== false && !this.isStandardAccess && (!window.RolePermissions || window.RolePermissions.canUsePopouts())) ? `
                        <button class="btn-popout" 
                                onclick="event.stopPropagation(); dashboard.openDb2PopOutWindow('${this.escapeHtml(instanceName)}', '${this.escapeHtml(databaseName)}')"
                                title="Open in new window"
                                data-popout-link>
                            🔲 Pop Out
                        </button>
                        ` : ''}
                        <span class="db2-expand-icon">▼</span>
                </div>
                        </div>
                <div class="db2-state-body">
                    <!-- GAUGES ROW -->
                    <div class="db2-gauges-row">
                        ${sessionGaugeHtml}
                        <div class="db2-counter-tile">
                            <div class="db2-counter-icon">👥</div>
                            <div class="db2-counter-value">${users}</div>
                            <div class="db2-counter-label">Users</div>
                    </div>
                        ${bpGaugeHtml}
                        ${logGaugeHtml}
                        </div>
                    
                    <!-- COUNTERS ROW -->
                    <div class="db2-counters-row">
                        <div class="db2-counter-tile ${hasBlocking ? 'critical' : ''}">
                            <div class="db2-counter-icon">🔒</div>
                            <div class="db2-counter-value">${blockingSessions.length}</div>
                            <div class="db2-counter-label">Blocking</div>
                    </div>
                        <div class="db2-counter-tile ${hasLongOps ? 'warning' : ''}">
                            <div class="db2-counter-icon">⏱️</div>
                            <div class="db2-counter-value">${longRunningQueries.length}</div>
                            <div class="db2-counter-label">Long Ops</div>
                        </div>
                        ${dbSizeGb != null ? `
                        <div class="db2-counter-tile">
                            <div class="db2-counter-icon">💾</div>
                            <div class="db2-counter-value">${dbSizeGb.toFixed(1)}</div>
                            <div class="db2-counter-label">GB</div>
                    </div>
                        ` : ''}
                        ${diagLogSizeMb != null ? `
                        <div class="db2-counter-tile ${diagLogSizeMb >= 500 ? 'critical' : diagLogSizeMb >= 100 ? 'warning' : ''}">
                            <div class="db2-counter-icon">📋</div>
                            <div class="db2-counter-value">${diagLogSizeMb >= 1024 ? (diagLogSizeMb / 1024).toFixed(1) : diagLogSizeMb.toFixed(0)}</div>
                            <div class="db2-counter-label">${diagLogSizeMb >= 1024 ? 'Diag GB' : 'Diag MB'}</div>
                        </div>
                        ` : ''}
                        <div class="db2-counter-tile ${diagErrors > 0 ? 'critical' : diagWarnings > 0 ? 'warning' : ''}">
                            <div class="db2-counter-icon">⚠️</div>
                            <div class="db2-counter-value">${diagErrors + diagWarnings}</div>
                            <div class="db2-counter-label">Diag Issues</div>
                        </div>
                        ${healthCounters ? `
                        <div class="db2-counter-tile ${healthCounters.deadlocks > 0 ? 'critical' : ''}">
                            <div class="db2-counter-icon">💀</div>
                            <div class="db2-counter-value">${this.formatLargeNumber(healthCounters.deadlocks)}</div>
                            <div class="db2-counter-label">Deadlocks</div>
                        </div>
                        <div class="db2-counter-tile ${healthCounters.lockTimeouts > 0 ? 'warning' : ''}">
                            <div class="db2-counter-icon">⏳</div>
                            <div class="db2-counter-value">${this.formatLargeNumber(healthCounters.lockTimeouts)}</div>
                            <div class="db2-counter-label">Lock T/O</div>
                        </div>
                        <div class="db2-counter-tile ${healthCounters.lockEscalations > 0 ? 'warning' : ''}">
                            <div class="db2-counter-icon">📈</div>
                            <div class="db2-counter-value">${this.formatLargeNumber(healthCounters.lockEscalations)}</div>
                            <div class="db2-counter-label">Lock Esc</div>
                        </div>
                        <div class="db2-counter-tile ${healthCounters.totalSorts > 0 && healthCounters.sortOverflows / Math.max(healthCounters.totalSorts, 1) > 0.05 ? 'warning' : ''}">
                            <div class="db2-counter-icon">🔀</div>
                            <div class="db2-counter-value">${this.formatLargeNumber(healthCounters.sortOverflows)}</div>
                            <div class="db2-counter-label">Sort Ovf</div>
                        </div>
                        ` : ''}
                    </div>
                    
                    ${longRunningQueries.length > 0 ? `
                    <!-- LONG OPERATIONS TABLE -->
                    <div class="db2-section">
                        <div class="db2-section-title">⏱️ Long Operations (> threshold)</div>
                        <table class="db2-table">
                            <thead><tr><th>User</th><th>Duration</th><th>SQL</th></tr></thead>
                            <tbody>
                                ${longRunningQueries.slice(0, 5).map(q => {
                                    const durationClass = q.elapsedSeconds >= 1800 ? 'critical-row' : q.elapsedSeconds >= 300 ? 'warning-row' : '';
                                    return `
                                        <tr class="${durationClass}">
                                            <td class="db2-user">${this.escapeHtml(q.userId || 'N/A')}</td>
                                            <td class="db2-duration">${this.formatDuration(q.elapsedSeconds)}</td>
                                            <td class="db2-sql" title="${this.escapeHtml(q.sqlText || '')}">${this.escapeHtml((q.sqlText || '').substring(0, 60))}...</td>
                            </tr>
                                    `;
                                }).join('')}
                            </tbody>
                        </table>
                        ${longRunningQueries.length > 5 ? `<div class="db2-more-entries">+ ${longRunningQueries.length - 5} more</div>` : ''}
                    </div>
                    ` : ''}
                    
                    ${blockingSessions.length > 0 ? `
                    <!-- LOCK WAITS TABLE -->
                    <div class="db2-section">
                        <div class="db2-section-title">🔒 Lock Waits</div>
                        <table class="db2-table">
                            <thead><tr><th>Blocked</th><th>Blocker</th><th>Wait</th><th>Object</th></tr></thead>
                        <tbody>
                                ${blockingSessions.slice(0, 5).map(b => {
                                    const waitClass = b.waitTimeSeconds >= 300 ? 'critical-row' : b.waitTimeSeconds >= 30 ? 'warning-row' : '';
                                return `
                                        <tr class="${waitClass}">
                                            <td class="db2-user">${this.escapeHtml(b.blockedUser || 'N/A')}</td>
                                            <td class="db2-user">${this.escapeHtml(b.blockerUser || 'N/A')}</td>
                                            <td class="db2-duration">${this.formatDuration(b.waitTimeSeconds)}</td>
                                            <td class="db2-object">${this.escapeHtml(b.tableSchema || '')}${b.tableSchema && b.tableName ? '.' : ''}${this.escapeHtml(b.tableName || 'N/A')} (${this.escapeHtml(b.lockMode || 'X')})</td>
                                    </tr>
                                `;
                            }).join('')}
                        </tbody>
                    </table>
                        ${blockingSessions.length > 5 ? `<div class="db2-more-entries">+ ${blockingSessions.length - 5} more</div>` : ''}
                    </div>
                    ` : ''}
                    
                    <!-- TODAY'S DIAG SUMMARY -->
                    <div class="db2-diag-summary-row">
                        <div class="db2-diag-badge critical" title="Critical + Severe">
                            <span class="badge-icon">🔴</span>
                            <span class="badge-value">${diagSummary?.criticalCount || 0}</span>
                            <span class="badge-label">Critical</span>
                        </div>
                        <div class="db2-diag-badge error" title="Errors">
                            <span class="badge-icon">🟠</span>
                            <span class="badge-value">${diagSummary?.errorCount || diagErrors}</span>
                            <span class="badge-label">Errors</span>
                        </div>
                        <div class="db2-diag-badge warning" title="Warnings">
                            <span class="badge-icon">🟡</span>
                            <span class="badge-value">${diagSummary?.warningCount || diagWarnings}</span>
                            <span class="badge-label">Warn</span>
                        </div>
                        <div class="db2-diag-badge info" title="Events">
                            <span class="badge-icon">🔵</span>
                            <span class="badge-value">${diagSummary?.eventCount || 0}</span>
                            <span class="badge-label">Events</span>
                        </div>
                    </div>
                    
                    ${sqlErrorLogFiles.length > 0 ? `
                    <!-- SQL ERROR LOGS FOR THIS DATABASE -->
                    <div class="db2-section sql-error-logs-section">
                        <div class="db2-section-title">📄 SQL Error Logs (${sqlErrorLogFiles.length})</div>
                        <div class="db2-log-files-list">
                            ${sqlErrorLogFiles.slice(0, 5).map(file => `
                                <div class="db2-log-file-item" data-filename="${file.fileName}">
                                    <div class="db2-log-file-info">
                                        <span class="db2-log-file-name">${file.fileName}</span>
                                        <span class="db2-log-file-meta">
                                            ${this.formatFileSize(file.sizeBytes)} • ${file.lineCount} lines • ${this.formatDateTime(file.lastModified)}
                                        </span>
                                    </div>
                                    <span class="db2-log-file-open">Open →</span>
                                </div>
                            `).join('')}
                        </div>
                        ${sqlErrorLogFiles.length > 5 ? `<div class="db2-more-entries">+ ${sqlErrorLogFiles.length - 5} more files</div>` : ''}
                    </div>
                    ` : ''}
                </div>
            </div>
        `;
    }
    
    /**
     * Render a semi-arc gauge
     */
    renderGauge(value, max, label, color) {
        const percent = Math.min((value / max) * 100, 100);
        const arcLength = percent * 1.26; // 126 is the arc path length
        
        return `
            <div class="db2-gauge-container">
                <svg viewBox="0 0 100 55" class="db2-gauge-svg">
                    <path d="M10,50 A40,40 0 0,1 90,50" fill="none" stroke="var(--bg-tertiary)" stroke-width="8" stroke-linecap="round"/>
                    <path d="M10,50 A40,40 0 0,1 90,50" fill="none" stroke="${color}" stroke-width="8" stroke-linecap="round"
                          stroke-dasharray="${arcLength} 126" class="db2-gauge-fill"/>
                </svg>
                <div class="db2-gauge-value">${typeof value === 'number' ? (value % 1 === 0 ? value : value.toFixed(1)) : value}</div>
                <div class="db2-gauge-label">${label}</div>
            </div>
        `;
    }
    
    /**
     * Group DB2 diagnostic entries by database + instance
     */
    groupEntriesByDatabase(entries) {
        const groups = {};
        for (const entry of entries) {
            const dbName = entry.databaseName || 'Unknown';
            const instName = entry.instanceName || 'DB2';
            const key = `${dbName}|${instName}`;
            
            if (!groups[key]) {
                groups[key] = {
                    databaseName: dbName,
                    instanceName: instName,
                    entries: []
                };
            }
            groups[key].entries.push(entry);
        }
        
        // Sort entries within each group by timestamp (newest first)
        for (const key of Object.keys(groups)) {
            groups[key].entries.sort((a, b) => 
                new Date(b.timestampParsed || b.timestamp) - new Date(a.timestampParsed || a.timestamp)
            );
        }
        
        return groups;
    }
    
    /**
     * Format duration in seconds to human-readable string
     */
    formatDuration(seconds) {
        if (!seconds || seconds < 0) return '0s';
        if (seconds < 60) return `${seconds}s`;
        if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
        const hours = Math.floor(seconds / 3600);
        const mins = Math.floor((seconds % 3600) / 60);
        return `${hours}h ${mins}m`;
    }
    
    /**
     * Fetches and renders SQL error log files for the current server
     */
    async renderSqlErrorLogFiles(container) {
        if (!this.selectedServer) return;
        
        try {
            const response = await fetch(`api/logfiles/sqlerrors/${this.selectedServer}`);
            if (!response.ok) {
                this.sqlErrorLogFiles = [];
                return;
            }
            
            this.sqlErrorLogFiles = await response.json();
            
            // Only show section if there are log files
            if (this.sqlErrorLogFiles.length === 0) return;
            
            const logFilesHtml = `
                <div class="db2-log-files">
                    <div class="db2-log-files-title">
                        📄 SQL Error Logs
                        <span style="font-weight: normal; font-size: 0.75rem; color: var(--text-muted);">
                            (${this.sqlErrorLogFiles.length} files)
                        </span>
                    </div>
                    <div class="db2-log-files-list">
                        ${this.sqlErrorLogFiles.slice(0, 10).map(file => `
                            <div class="db2-log-file-item" data-filename="${file.fileName}">
                                <div class="db2-log-file-info">
                                    <span class="db2-log-file-name">${file.fileName}</span>
                                    <span class="db2-log-file-meta">
                                        ${this.formatFileSize(file.sizeBytes)} • ${file.lineCount} lines • ${this.formatDateTime(file.lastModified)}
                                    </span>
                                </div>
                                <span class="db2-log-file-open">Open →</span>
                            </div>
                        `).join('')}
                    </div>
                </div>
                `;
            
            container.insertAdjacentHTML('beforeend', logFilesHtml);
            
            // Add click handlers
            container.querySelectorAll('.db2-log-file-item').forEach(item => {
                item.addEventListener('click', () => {
                    const fileName = item.dataset.filename;
                    this.openLogFileViewer(fileName);
                });
            });
            
        } catch (error) {
            console.error('Failed to fetch SQL error log files:', error);
            this.sqlErrorLogFiles = [];
        }
    }
    
    /**
     * Format file size to human readable format
     */
    formatFileSize(bytes) {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
    }

    formatLargeNumber(n) {
        if (n == null) return '0';
        if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
        if (n >= 10_000) return (n / 1_000).toFixed(1) + 'K';
        return n.toLocaleString();
    }

    /**
     * Open DB2 database details in a pop-out window
     * @param {string} instanceName - DB2 instance name (e.g., DB2, DB2FED)
     * @param {string} databaseName - Database name (e.g., FKMPRD, XFKMPRD)
     */
    openDb2PopOutWindow(instanceName, databaseName) {
        // Check role-based restrictions
        if (window.RolePermissions) {
            if (window.RolePermissions.isReadOnly()) {
                window.RolePermissions.showAccessDenied('Pop-out windows are not available for read-only access.');
                return;
            }
        }
        
        const windowName = `db2_${instanceName}_${databaseName}`.replace(/[^a-zA-Z0-9_]/g, '_');
        const width = 1300;
        const height = 850;
        const left = (screen.width - width) / 2;
        const top = (screen.height - height) / 2;
        
        // Build URL with parameters
        const params = new URLSearchParams({
            instance: instanceName,
            database: databaseName,
            server: this.selectedServer || ''
        });
        
        // User role gets pop-out but without auto-refresh
        if (window.RolePermissions && window.RolePermissions.getCurrentRole() === 'User') {
            params.set('autorefresh', 'false');
        }
        
        const url = `db2-detail.html?${params.toString()}`;
        
        // Open pop-out window
        const popOut = window.open(
            url,
            windowName,
            `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes`
        );
        
        if (popOut) {
            popOut.focus();
        } else {
            // Popup was blocked
            console.warn('Popup blocked - opening in new tab');
            window.open(url, '_blank');
        }
    }
    
    /**
     * Opens the Tools panel in a popout window
     */
    openToolsPopout() {
        const windowName = 'tools_panel';
        const width = 1040;
        const height = 700;
        const left = (screen.width - width) / 2;
        const top = (screen.height - height) / 2;
        
        const params = new URLSearchParams({
            server: this.selectedServer || ''
        });
        
        const url = `tools.html?${params.toString()}`;
        
        const popOut = window.open(
            url,
            windowName,
            `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes`
        );
        
        if (popOut) {
            popOut.focus();
        } else {
            console.warn('Popup blocked - opening in new tab');
            window.open(url, '_blank');
        }
    }
    
    /**
     * Opens the Control Panel in a popout window
     */
    openControlPanelPopout() {
        const windowName = 'control_panel';
        const width = 1040;
        const height = 700;
        const left = (screen.width - width) / 2;
        const top = (screen.height - height) / 2;
        
        const params = new URLSearchParams({
            server: this.selectedServer || ''
        });
        
        const url = `control-panel.html?${params.toString()}`;
        
        const popOut = window.open(
            url,
            windowName,
            `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes`
        );
        
        if (popOut) {
            popOut.focus();
        } else {
            console.warn('Popup blocked - opening in new tab');
            window.open(url, '_blank');
        }
    }
    
    /**
     * Opens the log file viewer modal with Monaco editor
     */
    async openLogFileViewer(fileName) {
        const modal = document.getElementById('logViewerModal');
        const titleEl = document.getElementById('logViewerTitle');
        const statusEl = document.getElementById('logViewerStatus');
        const container = document.getElementById('monacoContainer');
        
        if (!modal) return;
        
        // Show modal
        modal.classList.remove('hidden');
        titleEl.textContent = fileName;
        statusEl.textContent = 'Loading...';
        
        // Fetch file content
        try {
            const response = await fetch(`api/logfiles/sqlerrors/${this.selectedServer}/${encodeURIComponent(fileName)}`);
            if (!response.ok) {
                throw new Error(`Failed to load file: ${response.statusText}`);
            }
            
            const content = await response.text();
            const lineCount = content.split('\n').length;
            statusEl.textContent = `${lineCount} lines • ${this.formatFileSize(content.length)}`;
            
            // Initialize Monaco editor
            await this.initMonacoEditor(container, content);
            
        } catch (error) {
            console.error('Failed to load log file:', error);
            statusEl.textContent = `Error: ${error.message}`;
            container.innerHTML = `<div style="padding: 2rem; color: var(--error-color);">Failed to load file: ${error.message}</div>`;
        }
    }
    
    /**
     * Initializes or updates the Monaco editor
     */
    async initMonacoEditor(container, content) {
        // If Monaco isn't loaded yet, wait for it
        if (typeof require === 'undefined') {
            console.error('Monaco loader not available');
            container.innerHTML = `<pre style="padding: 1rem; overflow: auto; height: 100%;">${this.escapeHtml(content)}</pre>`;
            return;
        }
        
        return new Promise((resolve) => {
            require(['vs/editor/editor.main'], (monaco) => {
                // Dispose existing editor if any
                if (this.monacoEditor) {
                    this.monacoEditor.dispose();
                }
                
                // Register custom language for SQL error logs (once)
                if (!this.sqlErrorLogLanguageRegistered) {
                    this.registerSqlErrorLogLanguage(monaco);
                    this.sqlErrorLogLanguageRegistered = true;
                }
                
                // Determine theme based on current app theme
                const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
                const monacoTheme = isDark ? 'sqlerror-dark' : 'sqlerror-light';
                
                // Create editor
                this.monacoEditor = monaco.editor.create(container, {
                    value: content,
                    language: 'sqlerrorlog',
                    theme: monacoTheme,
                    readOnly: true,
                    automaticLayout: true,
                    minimap: { enabled: true },
                    lineNumbers: 'on',
                    renderWhitespace: 'selection',
                    scrollBeyondLastLine: false,
                    wordWrap: 'on',
                    wrappingStrategy: 'advanced',
                    fontSize: 12,
                    fontFamily: "'JetBrains Mono', 'Fira Code', Consolas, monospace"
                });
                
                this.monacoInitialized = true;
                resolve();
            });
        });
    }
    
    /**
     * Registers custom Monaco language for SQL error logs with syntax highlighting
     */
    registerSqlErrorLogLanguage(monaco) {
        // Register the language
        monaco.languages.register({ id: 'sqlerrorlog' });
        
        // Define tokenizer for SQL error log format:
        // 2026-01-25 10:23:45 | XFKMPRD | DBUSER | SQL0911N | Message text...
        monaco.languages.setMonarchTokensProvider('sqlerrorlog', {
            tokenizer: {
                root: [
                    // Timestamp at the start of line: 2026-01-25 10:23:45
                    [/^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}/, 'date'],
                    
                    // SQL error codes: SQL0911N, SQL0204N, etc.
                    [/SQL\d{4,5}[A-Z]?/, 'error-code'],
                    
                    // SQLSTATE codes: SQLSTATE=23503
                    [/SQLSTATE[=:]\s*\d{5}/, 'sqlstate'],
                    
                    // Database names (typically all caps in pipes)
                    [/\|\s*[A-Z][A-Z0-9_]{2,}\s*\|/, 'database'],
                    
                    // Pipe separators
                    [/\|/, 'delimiter'],
                    
                    // Keywords
                    [/\b(ERROR|WARNING|CRITICAL|SEVERE|INFO|DEBUG)\b/i, 'keyword'],
                    
                    // Numbers
                    [/\b\d+\b/, 'number'],
                    
                    // Quoted strings
                    [/"[^"]*"/, 'string'],
                    [/'[^']*'/, 'string'],
                    
                    // Everything else
                    [/./, 'text']
                ]
            }
        });
        
        // Define light theme
        monaco.editor.defineTheme('sqlerror-light', {
            base: 'vs',
            inherit: true,
            rules: [
                { token: 'date', foreground: '0369a1', fontStyle: 'bold' },
                { token: 'error-code', foreground: 'dc2626', fontStyle: 'bold' },
                { token: 'sqlstate', foreground: 'd97706' },
                { token: 'database', foreground: '059669', fontStyle: 'bold' },
                { token: 'delimiter', foreground: '94a3b8' },
                { token: 'keyword', foreground: '7c3aed', fontStyle: 'bold' },
                { token: 'number', foreground: '0284c7' },
                { token: 'string', foreground: '16a34a' },
                { token: 'text', foreground: '475569' }
            ],
            colors: {
                'editor.background': '#f8fafc',
                'editor.lineHighlightBackground': '#f1f5f9'
            }
        });
        
        // Define dark theme
        monaco.editor.defineTheme('sqlerror-dark', {
            base: 'vs-dark',
            inherit: true,
            rules: [
                { token: 'date', foreground: '60a5fa', fontStyle: 'bold' },
                { token: 'error-code', foreground: 'f87171', fontStyle: 'bold' },
                { token: 'sqlstate', foreground: 'fbbf24' },
                { token: 'database', foreground: '34d399', fontStyle: 'bold' },
                { token: 'delimiter', foreground: '71717a' },
                { token: 'keyword', foreground: 'a78bfa', fontStyle: 'bold' },
                { token: 'number', foreground: '38bdf8' },
                { token: 'string', foreground: '4ade80' },
                { token: 'text', foreground: 'a1a1aa' }
            ],
            colors: {
                'editor.background': '#0a0a0a',
                'editor.lineHighlightBackground': '#171717'
            }
        });
    }
    
    /**
     * Closes the log viewer modal
     */
    closeLogViewer() {
        const modal = document.getElementById('logViewerModal');
        if (modal) {
            modal.classList.add('hidden');
        }
        
        // Dispose Monaco editor to free memory
        if (this.monacoEditor) {
            this.monacoEditor.dispose();
            this.monacoEditor = null;
        }
    }
    
    /**
     * Copies all content from the Monaco editor to clipboard
     */
    copyLogContent() {
        if (this.monacoEditor) {
            const content = this.monacoEditor.getValue();
            navigator.clipboard.writeText(content).then(() => {
                const btn = document.getElementById('logViewerCopyBtn');
                if (btn) {
                    const originalText = btn.textContent;
                    btn.textContent = '✓ Copied!';
                    setTimeout(() => {
                        btn.textContent = originalText;
                    }, 2000);
                }
            }).catch(err => {
                console.error('Failed to copy:', err);
            });
        }
    }

    /**
     * Renders the IIS Web Server panel with sites, app pools, and worker processes
     */
    renderIisPanel() {
        const iisData = this.currentSnapshot?.iis;
        const container = document.getElementById('iisPanel');
        if (!container) return;

        const isIisServer = this.selectedServer?.toLowerCase().includes('-app') ||
                            iisData?.isActive === true;

        if (!isIisServer || !iisData || !iisData.isActive) {
            container.classList.add('hidden');
            return;
        }

        container.classList.remove('hidden');

        // Update summary in header
        const summaryEl = container.querySelector('.iis-summary');
        if (summaryEl) {
            summaryEl.textContent = `(${iisData.sites?.length || 0} sites, ${iisData.appPools?.length || 0} pools, ${iisData.appPools?.reduce((sum, p) => sum + (p.workerProcesses?.length || 0), 0) || 0} workers)`;
        }

        const statsContainer = container.querySelector('.iis-stats');
        if (!statsContainer) return;

        // Summary tiles
        const sites = iisData.sites || [];
        const pools = iisData.appPools || [];
        const totalWorkers = pools.reduce((sum, p) => sum + (p.workerProcesses?.length || 0), 0);
        const runningSites = sites.filter(s => s.state === 'Started').length;
        const stoppedPools = pools.filter(p => p.state !== 'Started').length;

        let html = `
            <div class="iis-overview">
                <div class="iis-tiles">
                    <div class="counter-tile">
                        <div class="counter-value">${sites.length}</div>
                        <div class="counter-label">Sites</div>
                    </div>
                    <div class="counter-tile ${runningSites === sites.length ? 'tile-success' : 'tile-warning'}">
                        <div class="counter-value">${runningSites}</div>
                        <div class="counter-label">Running Sites</div>
                    </div>
                    <div class="counter-tile">
                        <div class="counter-value">${pools.length}</div>
                        <div class="counter-label">App Pools</div>
                    </div>
                    <div class="counter-tile ${stoppedPools > 0 ? 'tile-error' : 'tile-success'}">
                        <div class="counter-value">${stoppedPools}</div>
                        <div class="counter-label">Stopped Pools</div>
                    </div>
                    <div class="counter-tile">
                        <div class="counter-value">${totalWorkers}</div>
                        <div class="counter-label">Workers</div>
                    </div>
                </div>
                ${(this.iisDashboardConfig.enablePopout !== false && !this.isStandardAccess && (!window.RolePermissions || window.RolePermissions.canUsePopouts())) ? `
                <button class="btn-popout" 
                        onclick="event.stopPropagation(); dashboard.openIisPopOutWindow()"
                        title="Open IIS details in new window"
                        data-popout-link>
                    🔲 Pop Out
                </button>
                ` : ''}
            </div>`;

        // App Pools table with expandable rows
        if (pools.length > 0) {
            html += `
            <div class="iis-section">
                <h4 class="iis-section-title">Application Pools</h4>
                <table class="iis-table">
                    <thead>
                        <tr>
                            <th style="width:30px"></th>
                            <th>Name</th>
                            <th>State</th>
                            <th>Pipeline</th>
                            <th>Runtime</th>
                            <th>Workers</th>
                            <th>Memory</th>
                        </tr>
                    </thead>
                    <tbody>`;

            for (const pool of pools) {
                const stateClass = pool.state === 'Started' ? 'status-running' : 'status-stopped';
                const stateIcon = pool.state === 'Started' ? '🟢' : '🔴';
                const runtime = pool.managedRuntimeVersion || 'No Managed Code';
                const workerCount = pool.workerProcesses?.length || 0;
                const totalMemory = pool.workerProcesses?.reduce((sum, w) => sum + (w.privateMemoryMB || 0), 0) || 0;
                const poolId = this.escapeHtml(pool.name).replace(/[^a-zA-Z0-9]/g, '_');

                html += `
                        <tr class="iis-row expandable" data-pool-id="${poolId}" onclick="dashboard.toggleIisRow(this, '${poolId}')">
                            <td><span class="expand-indicator">▶</span></td>
                            <td><strong>${this.escapeHtml(pool.name)}</strong></td>
                            <td><span class="${stateClass}">${stateIcon} ${pool.state}</span></td>
                            <td>${this.escapeHtml(pool.pipelineMode || 'Integrated')}</td>
                            <td>${this.escapeHtml(runtime)}</td>
                            <td>${workerCount}</td>
                            <td>${totalMemory > 0 ? totalMemory.toFixed(0) + ' MB' : '-'}</td>
                        </tr>
                        <tr class="iis-details-row hidden" data-pool-details-id="${poolId}">
                            <td colspan="7">
                                <div class="iis-details-content">
                                    <div class="iis-detail-grid">
                                        <div class="iis-detail-item"><span class="detail-label">IDENTITY</span><span class="detail-value">${this.escapeHtml(pool.identityType || 'ApplicationPoolIdentity')}${pool.identityUsername ? ' (' + this.escapeHtml(pool.identityUsername) + ')' : ''}</span></div>
                                        <div class="iis-detail-item"><span class="detail-label">AUTO START</span><span class="detail-value">${pool.autoStart ? 'Yes' : 'No'}</span></div>
                                        <div class="iis-detail-item"><span class="detail-label">32-BIT</span><span class="detail-value">${pool.enable32BitAppOnWin64 ? 'Yes' : 'No'}</span></div>
                                        <div class="iis-detail-item"><span class="detail-label">CPU LIMIT</span><span class="detail-value">${pool.cpuLimit > 0 ? pool.cpuLimit + '%' : 'None'}</span></div>
                                        <div class="iis-detail-item"><span class="detail-label">MEMORY LIMIT</span><span class="detail-value">${pool.privateMemoryLimitKB > 0 ? Math.round(pool.privateMemoryLimitKB / 1024) + ' MB' : 'None'}</span></div>
                                        <div class="iis-detail-item"><span class="detail-label">RECYCLE INTERVAL</span><span class="detail-value">${pool.recyclingTimeIntervalMinutes > 0 ? pool.recyclingTimeIntervalMinutes + ' min' : 'None'}</span></div>
                                    </div>`;

                if (workerCount > 0) {
                    html += `
                                    <div class="iis-worker-list">
                                        <strong>Worker Processes:</strong>
                                        <table class="iis-subtable">
                                            <thead><tr><th>PID</th><th>State</th><th>Memory</th><th>Started</th></tr></thead>
                                            <tbody>`;
                    for (const wp of pool.workerProcesses) {
                        html += `<tr>
                                    <td>${wp.processId}</td>
                                    <td>${wp.state || 'Running'}</td>
                                    <td>${wp.privateMemoryMB?.toFixed(0) || 0} MB</td>
                                    <td>${wp.startTime ? new Date(wp.startTime).toLocaleString() : '-'}</td>
                                </tr>`;
                    }
                    html += `       </tbody></table>
                                    </div>`;
                }

                html += `
                                </div>
                            </td>
                        </tr>`;
            }

            html += `
                    </tbody>
                </table>
            </div>`;
        }

        // Sites table with expandable rows
        if (sites.length > 0) {
            html += `
            <div class="iis-section">
                <h4 class="iis-section-title">Sites</h4>
                <table class="iis-table">
                    <thead>
                        <tr>
                            <th style="width:30px"></th>
                            <th>Site Name</th>
                            <th>State</th>
                            <th>App Pool</th>
                            <th>Bindings</th>
                            <th>Virtual Apps</th>
                        </tr>
                    </thead>
                    <tbody>`;

            for (const site of sites) {
                const stateClass = site.state === 'Started' ? 'status-running' : 'status-stopped';
                const stateIcon = site.state === 'Started' ? '🟢' : '🔴';
                const bindingsStr = (site.bindings || []).map(b => `${b.protocol}://${b.host || '*'}:${b.port}`).join(', ');
                const vappCount = site.virtualApps?.length || 0;
                const siteId = 'site_' + String(site.id);

                html += `
                        <tr class="iis-row expandable" data-site-id="${siteId}" onclick="dashboard.toggleIisRow(this, '${siteId}', true)">
                            <td><span class="expand-indicator">▶</span></td>
                            <td><strong>${this.escapeHtml(site.name)}</strong></td>
                            <td><span class="${stateClass}">${stateIcon} ${site.state}</span></td>
                            <td>${this.escapeHtml(site.appPoolName || '')}</td>
                            <td>${this.escapeHtml(bindingsStr)}</td>
                            <td>${vappCount}</td>
                        </tr>
                        <tr class="iis-details-row hidden" data-site-details-id="${siteId}">
                            <td colspan="6">
                                <div class="iis-details-content">
                                    <div class="iis-detail-grid">
                                        <div class="iis-detail-item"><span class="detail-label">PHYSICAL PATH</span><span class="detail-value" style="font-family:monospace;font-size:0.85em">${this.escapeHtml(site.physicalPathUnc || site.physicalPath || '-')}</span></div>
                                        <div class="iis-detail-item"><span class="detail-label">SITE ID</span><span class="detail-value">${site.id}</span></div>
                                    </div>`;

                if (vappCount > 0) {
                    html += `
                                    <div class="iis-vapp-list">
                                        <strong>Virtual Applications:</strong>
                                        <table class="iis-subtable">
                                            <thead><tr><th>Path</th><th>Type</th><th>App Pool</th><th>Install Path (UNC)</th><th>Log Path</th><th>Output Path</th></tr></thead>
                                            <tbody>`;
                    for (const vapp of site.virtualApps) {
                        const typeBadge = vapp.isAspNetCore
                            ? `<span class="iis-badge-aspnet" title="${this.escapeHtml(vapp.dotNetDll || '')}">ASP.NET Core</span>`
                            : '<span class="iis-badge-static">Static</span>';
                        html += `<tr>
                                    <td>${this.escapeHtml(vapp.path)}</td>
                                    <td>${typeBadge}</td>
                                    <td>${this.escapeHtml(vapp.appPoolName || '')}</td>
                                    <td style="max-width:350px;overflow:hidden;text-overflow:ellipsis;font-family:monospace;font-size:0.85em" title="${this.escapeHtml(vapp.physicalPathUnc || vapp.physicalPath || '')}">${this.escapeHtml(vapp.physicalPathUnc || vapp.physicalPath || '')}</td>
                                    <td style="max-width:250px;overflow:hidden;text-overflow:ellipsis;font-family:monospace;font-size:0.85em" title="${this.escapeHtml(vapp.logPath || '')}">${vapp.logPath ? this.escapeHtml(vapp.logPath) : '<span style="opacity:0.4">-</span>'}</td>
                                    <td style="max-width:250px;overflow:hidden;text-overflow:ellipsis;font-family:monospace;font-size:0.85em" title="${this.escapeHtml(vapp.outputPath || '')}">${vapp.outputPath ? this.escapeHtml(vapp.outputPath) : '<span style="opacity:0.4">-</span>'}</td>
                                </tr>`;
                    }
                    html += `       </tbody></table>
                                    </div>`;
                }

                html += `
                                </div>
                            </td>
                        </tr>`;
            }

            html += `
                    </tbody>
                </table>
            </div>`;
        }

        // IIS version footer
        if (iisData.iisVersion) {
            html += `<div class="iis-footer">IIS Version: ${this.escapeHtml(iisData.iisVersion)} | Last collected: ${iisData.collectedAt ? new Date(iisData.collectedAt).toLocaleString() : '-'}</div>`;
        }

        statsContainer.innerHTML = html;
    }

    /**
     * Toggle IIS expandable row
     */
    toggleIisRow(rowElement, id, isSite = false) {
        const detailsAttr = isSite ? `data-site-details-id` : `data-pool-details-id`;
        const tbody = rowElement.closest('tbody');
        const detailsRow = tbody.querySelector(`tr[${detailsAttr}="${id}"]`);
        if (detailsRow) {
            detailsRow.classList.toggle('hidden');
            rowElement.classList.toggle('expanded');
            const indicator = rowElement.querySelector('.expand-indicator');
            if (indicator) {
                indicator.textContent = detailsRow.classList.contains('hidden') ? '▶' : '▼';
            }
        }
    }

    /**
     * Opens IIS details in a pop-out window
     */
    openIisPopOutWindow() {
        if (window.RolePermissions) {
            if (window.RolePermissions.isReadOnly()) {
                window.RolePermissions.showAccessDenied('Pop-out windows are not available for read-only access.');
                return;
            }
        }

        const windowName = `iis_${(this.selectedServer || 'local').replace(/[^a-zA-Z0-9_]/g, '_')}`;
        const width = 1430;
        const height = 850;
        const left = (screen.width - width) / 2;
        const top = (screen.height - height) / 2;

        const params = new URLSearchParams({
            server: this.selectedServer || ''
        });

        if (window.RolePermissions && window.RolePermissions.getCurrentRole() === 'User') {
            params.set('autorefresh', 'false');
        }

        const url = `iis-detail.html?${params.toString()}`;
        const popOut = window.open(
            url,
            windowName,
            `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes`
        );

        if (popOut) {
            popOut.focus();
        } else {
            console.warn('Popup blocked - opening in new tab');
            window.open(url, '_blank');
        }
    }

    /**
     * Opens the Snapshot History Analysis page in a pop-out window
     */
    openSnapshotAnalysisWindow() {
        const width = 1200;
        const height = 900;
        const left = (screen.width - width) / 2;
        const top = (screen.height - height) / 2;

        const popOut = window.open(
            'snapshot-analysis.html',
            'snapshot_analysis',
            `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes`
        );

        if (popOut) {
            popOut.focus();
        } else {
            window.open('snapshot-analysis.html', '_blank');
        }
    }

    /**
     * Renders the Scheduled Tasks panel showing all monitored tasks
     */
    renderScheduledTasks() {
        const tasksData = this.currentSnapshot?.scheduledTasks;
        const container = document.getElementById('scheduledTasksPanel');
        if (!container) return;

        // Check if there are any scheduled tasks
        const hasTasks = tasksData && tasksData.length > 0;

        if (!hasTasks) {
            container.classList.add('hidden');
            return;
        }

        container.classList.remove('hidden');

        // Update task count in header
        const countEl = container.querySelector('.task-count');
        if (countEl) {
            countEl.textContent = `(${tasksData.length} tasks)`;
        }

        const tbody = container.querySelector('.tasks-table tbody');
        if (!tbody) return;

        // Build table rows
        tbody.innerHTML = tasksData.map(task => {
            // Determine status icon and class
            let statusIcon = '❓';
            let statusClass = 'unknown';
            let statusText = task.state || 'Unknown';

            if (!task.isEnabled) {
                statusIcon = '⏸️';
                statusClass = 'disabled';
                statusText = 'Disabled';
            } else {
                switch ((task.state || '').toLowerCase()) {
                    case 'running':
                        statusIcon = '▶️';
                        statusClass = 'running';
                        break;
                    case 'ready':
                        statusIcon = '✅';
                        statusClass = 'ready';
                        break;
                    case 'queued':
                        statusIcon = '⏳';
                        statusClass = 'queued';
                        break;
                    case 'disabled':
                        statusIcon = '⏸️';
                        statusClass = 'disabled';
                        break;
                    default:
                        statusIcon = '❓';
                        statusClass = 'unknown';
                }
            }

            // Format last run result
            let resultIcon = '';
            let resultClass = '';
            let resultText = '-';
            
            if (task.lastRunResult !== null && task.lastRunResult !== undefined) {
                if (task.lastRunResult === 0) {
                    resultIcon = '✅';
                    resultClass = 'success';
                    resultText = 'Success (0)';
                } else if (task.lastRunResult === 267009) {
                    resultIcon = '🏃';
                    resultClass = 'running';
                    resultText = 'Running';
                } else if (task.lastRunResult === 267011) {
                    resultIcon = '⏭️';
                    resultClass = 'warning';
                    resultText = 'Terminated';
                } else {
                    resultIcon = '❌';
                    resultClass = 'error';
                    resultText = `Error (${task.lastRunResult})`;
                }
            }

            // Extract just the task name from the full path
            const taskName = task.taskName || task.taskPath?.split('\\').pop() || 'Unknown';
            
            // All tasks are expandable - we always show Command, Arguments, Working Dir
            const hasDetails = true;

            return `
                <tr class="task-row ${hasDetails ? 'expandable' : ''}" data-task-path="${task.taskPath}">
                    <td class="task-name" title="${task.description || taskName}">
                        ${taskName}
                        ${hasDetails ? '<span class="expand-indicator">▶</span>' : ''}
                    </td>
                    <td class="task-path" title="${task.taskPath}">${task.taskPath}</td>
                    <td class="task-status ${statusClass}">
                        <span class="status-icon">${statusIcon}</span>
                        <span class="status-text">${statusText}</span>
                    </td>
                    <td class="task-time">${this.formatDateTime(task.nextRunTime)}</td>
                    <td class="task-time">${this.formatDateTime(task.lastRunTime)}</td>
                    <td class="task-result ${resultClass}">
                        <span class="result-icon">${resultIcon}</span>
                        <span class="result-text">${resultText}</span>
                    </td>
                </tr>
                <tr class="task-details-row hidden" data-task-details-path="${task.taskPath}">
                    <td colspan="6">
                        <div class="task-details-content">
                            <div class="task-detail-item"><span class="detail-label">COMMAND:</span><span class="detail-value mono${task.command ? '' : ' empty-value'}">${task.command ? this.escapeHtml(task.command) : '(none)'}</span></div>
                            <div class="task-detail-item"><span class="detail-label">ARGUMENTS:</span><span class="detail-value mono${task.arguments ? '' : ' empty-value'}">${task.arguments ? this.escapeHtml(task.arguments) : '(none)'}</span></div>
                            <div class="task-detail-item"><span class="detail-label">WORKING DIR:</span><span class="detail-value mono${task.workingDirectory ? '' : ' empty-value'}">${task.workingDirectory ? this.escapeHtml(task.workingDirectory) : '(none)'}</span></div>
                            <div class="task-detail-item"><span class="detail-label">RUN AS:</span><span class="detail-value${task.runAsUser ? '' : ' empty-value'}">${task.runAsUser ? this.escapeHtml(task.runAsUser) : '(none)'}</span></div>
                            <div class="task-detail-item"><span class="detail-label">LOGON:</span><span class="detail-value">${task.runOnlyIfLoggedOn ? '🧑 Run only when user is logged on' : '⚙️ Run whether user is logged on or not'}</span></div>
                            ${task.description ? `<div class="task-detail-item"><span class="detail-label">DESCRIPTION:</span><span class="detail-value">${this.escapeHtml(task.description)}</span></div>` : ''}
                        </div>
                    </td>
                </tr>
            `;
        }).join('');
        
        // Add click handlers for expandable task rows
        tbody.querySelectorAll('.task-row.expandable').forEach(row => {
            row.addEventListener('click', () => {
                const taskPath = row.dataset.taskPath;
                // Use CSS.escape to handle backslashes and special characters in task paths
                const escapedPath = CSS.escape(taskPath);
                const detailsRow = tbody.querySelector(`tr[data-task-details-path="${escapedPath}"]`);
                const indicator = row.querySelector('.expand-indicator');
                
                if (detailsRow) {
                    detailsRow.classList.toggle('hidden');
                    row.classList.toggle('expanded');
                    if (indicator) {
                        indicator.textContent = detailsRow.classList.contains('hidden') ? '▶' : '▼';
                    }
                }
            });
        });
    }
    
    /**
     * Escapes HTML entities in a string
     */
    escapeHtml(str) {
        if (!str) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    /**
     * Formats a datetime for display
     */
    formatDateTime(dateStr) {
        if (!dateStr) return '-';
        try {
            const date = new Date(dateStr);
            if (isNaN(date.getTime())) return '-';
            
            const now = new Date();
            const isToday = date.toDateString() === now.toDateString();
            const isTomorrow = date.toDateString() === new Date(now.getTime() + 86400000).toDateString();
            
            if (isToday) {
                return `Today ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
            } else if (isTomorrow) {
                return `Tomorrow ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
            } else {
                return date.toLocaleDateString([], { month: 'short', day: 'numeric' }) + 
                       ' ' + date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            }
        } catch {
            return '-';
        }
    }

    renderEmptyState() {
        const container = document.getElementById('metricsGrid');
        
        // Check if we have a selected server that is offline or has no data
        const server = this.selectedServer ? this.servers.find(s => s.name === this.selectedServer) : null;
        const isOfflineByStatus = server && !server.isAlive;
        
        // Show action buttons if: server is explicitly offline OR we have a selected server but no snapshot data
        const hasNoData = this.selectedServer && !this.currentSnapshot;
        const showActionButtons = isOfflineByStatus || hasNoData;
        
        if (container) {
            if (showActionButtons && this.selectedServer) {
                // Show offline/no-data state with action buttons
                const statusIcon = isOfflineByStatus ? '🔴' : '⚠️';
                const statusText = isOfflineByStatus 
                    ? 'is currently offline' 
                    : 'is not returning data';
                const subText = isOfflineByStatus 
                    ? 'The agent is not responding. You can try to start it or reinstall.'
                    : 'The agent may be stopped or unreachable. You can try to start it or reinstall.';
                
                container.innerHTML = `
                    <div class="empty-state" style="grid-column: 1 / -1;">
                        <div class="empty-state-icon">${statusIcon}</div>
                        <p><strong>${this.selectedServer}</strong> ${statusText}</p>
                        <p style="color: var(--text-muted); margin-bottom: 1rem;">${subText}</p>
                        <div class="offline-server-actions">
                            <button class="server-action-btn btn-start-server" onclick="dashboard.startServer('${this.selectedServer}')">
                                ▶️ Start Agent
                            </button>
                            <button class="server-action-btn btn-restart-server" onclick="dashboard.restartServer('${this.selectedServer}')">
                                🔄 Restart Agent
                            </button>
                            <button class="server-action-btn btn-reinstall-server" onclick="dashboard.reinstallServer('${this.selectedServer}')">
                                📦 Reinstall Agent
                            </button>
                        </div>
                    </div>
                `;
            } else {
                container.innerHTML = `
                    <div class="empty-state" style="grid-column: 1 / -1;">
                        <div class="empty-state-icon">📊</div>
                        <p>Select a server to view metrics</p>
                    </div>
                `;
            }
        }
        
        // Remove agent info bar when clearing state
        const agentInfoBar = document.getElementById('agentInfoBar');
        if (agentInfoBar) {
            agentInfoBar.remove();
        }
        
        // Reset Windows Updates panel to empty state
        const updatesContent = document.querySelector('#windowsUpdatesPanel .updates-content');
        if (updatesContent) {
            if (showActionButtons && this.selectedServer) {
                const statusIcon = isOfflineByStatus ? '🔴' : '⚠️';
                updatesContent.innerHTML = `
                    <div class="updates-empty-state">
                        <span class="updates-icon">${statusIcon}</span>
                        <span>Server not responding - no data available</span>
                    </div>
                `;
            } else {
                updatesContent.innerHTML = `
                    <div class="updates-empty-state">
                        <span class="updates-icon">📊</span>
                        <span>Select a server to view update status</span>
                    </div>
                `;
            }
        }
        
        // Hide all detail panels
        document.getElementById('alertsPanel')?.classList.add('hidden');
        document.getElementById('processesPanel')?.classList.add('hidden');
        document.getElementById('db2Panel')?.classList.add('hidden');
        document.getElementById('scheduledTasksPanel')?.classList.add('hidden');
        
        // Remove disks panel when clearing state
        const disksPanel = document.getElementById('disksPanel');
        if (disksPanel) {
            disksPanel.remove();
        }
    }

    async triggerReinstall() {
        const serverName = this.selectedServer;
        const message = serverName 
            ? `Create reinstall trigger for ${serverName}?\n\nThis will trigger a reinstall on this specific server.`
            : 'Create global reinstall trigger?\n\nThis will cause ALL tray applications to reinstall the ServerMonitor agent.';
            
        if (!confirm(message)) {
            return;
        }

        try {
            const response = await fetch('api/reinstall', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ serverName: serverName })
            });
            
            const result = await response.json();
            
            if (result.success) {
                const targetMsg = result.serverName ? `for ${result.serverName}` : 'for ALL servers';
                alert(`✅ Reinstall trigger created ${targetMsg}!\n\nVersion: ${result.version}\nPath: ${result.triggerFilePath}`);
            } else {
                alert(`❌ Failed to create trigger:\n${result.message}`);
            }
        } catch (error) {
            console.error('Error triggering reinstall:', error);
            alert('❌ Error creating reinstall trigger');
        }
    }

    // Auto-refresh
    startAutoRefresh() {
        this.stopAutoRefresh();
        
        // Check role-based restrictions for auto-refresh
        if (window.RolePermissions) {
            const role = window.RolePermissions.getCurrentRole();
            if (role === 'ReadOnly') {
                // ReadOnly users cannot use auto-refresh
                console.log('Auto-refresh disabled for ReadOnly role');
                const autoRefreshCheckbox = document.getElementById('autoRefresh');
                if (autoRefreshCheckbox) {
                    autoRefreshCheckbox.checked = false;
                    autoRefreshCheckbox.disabled = true;
                    autoRefreshCheckbox.title = 'Auto-refresh not available for read-only access';
                }
                this.autoRefresh = false;
                return;
            }
            
            // User role: validate refresh interval is within allowed range (5/10/30/60 min)
            if (role === 'User') {
                const allowedIntervals = [300, 600, 1800, 3600]; // 5,10,30,60 min in seconds
                if (!allowedIntervals.includes(this.refreshInterval)) {
                    // Set to minimum allowed (5 minutes)
                    this.refreshInterval = 300;
                    const refreshSelect = document.getElementById('refreshInterval');
                    if (refreshSelect) refreshSelect.value = '300';
                }
            }
        }
        
        this.countdownValue = this.refreshInterval;
        this.updateCountdown();
        
        this.countdownTimer = setInterval(() => {
            this.countdownValue--;
            this.updateCountdown();
            
            if (this.countdownValue <= 0) {
                this.countdownValue = this.refreshInterval;
                this.manualRefresh();
            }
        }, 1000);
    }

    stopAutoRefresh() {
        if (this.countdownTimer) {
            clearInterval(this.countdownTimer);
            this.countdownTimer = null;
        }
        this.updateCountdown();
    }

    updateCountdown() {
        const el = document.getElementById('countdown');
        if (el) {
            if (!this.autoRefresh) {
                el.textContent = '--';
            } else if (this.countdownValue >= 60) {
                const mins = Math.floor(this.countdownValue / 60);
                const secs = this.countdownValue % 60;
                el.textContent = secs > 0 ? `${mins}m ${secs}s` : `${mins}m`;
            } else {
                el.textContent = `${this.countdownValue}s`;
            }
        }
    }

    async manualRefresh() {
        console.log('manualRefresh called');
        
        // Refresh header settings and current server data without blocking the UI
        // Only show spinner (not full loading overlay) to keep data visible during refresh
        this.showSpinner();
        
        // Disable button during refresh to show it's working
        const refreshBtn = document.getElementById('refreshBtn');
        if (refreshBtn) {
            refreshBtn.disabled = true;
            refreshBtn.textContent = '⟳ Refreshing...';
        }
        
        try {
            // Reset countdown immediately for visual feedback
            this.countdownValue = this.refreshInterval;
            this.updateCountdown();
            
            // Fetch all data in parallel without blocking UI
            const [serversResult, triggerResult] = await Promise.allSettled([
                this.refreshServersInBackground(),
                this.checkTriggerStatus()
            ]);
            
            // If we have a selected server, refresh its snapshot
            if (this.selectedServer) {
                await this.loadSnapshotQuiet(this.selectedServer);
            }
            
            console.log('manualRefresh completed successfully');
        } catch (error) {
            console.error('Error during manual refresh:', error);
        } finally {
            this.hideSpinner();
            
            // Re-enable button
            if (refreshBtn) {
                refreshBtn.disabled = false;
                refreshBtn.textContent = '🔄 Refresh';
            }
        }
    }

    /**
     * Refresh server list in background without showing loading overlay
     * Updates the UI immediately when data is available
     */
    async refreshServersInBackground() {
        try {
            const response = await fetch('api/servers/refresh', { method: 'POST' });
            const data = await response.json();

            this.servers = data.servers || [];
            this.currentAgentVersion = data.currentAgentVersion;

            // Store current selection before re-rendering
            const previousSelection = this.selectedServer;

            // Update UI immediately
            this.renderServerDropdown();
            this.updateStatusSummary();

            // Restore selection if server still exists
            if (previousSelection && this.servers.some(s => s.name === previousSelection)) {
                const select = document.getElementById('serverSelect');
                if (select) select.value = previousSelection;
            }
        } catch (error) {
            console.error('Error refreshing servers:', error);
        }
    }

    /**
     * Load snapshot without showing spinner (for background refresh)
     * Updates dashboard immediately when data is available
     */
    async loadSnapshotQuiet(serverName) {
        try {
            const url = `api/snapshot/${serverName}`;
            const response = await fetch(url);

            if (!response.ok) {
                throw new Error(`Failed to load snapshot: ${response.statusText}`);
            }

            this.currentSnapshot = await response.json();

            // Update server status in dropdown to show it's responding
            this.updateServerDropdownStatus(serverName, true);

            // Update dashboard immediately
            this.renderDashboard();
        } catch (error) {
            console.error('Error loading snapshot:', error);
            this.updateServerDropdownStatus(serverName, false);
        }
    }

    // Helpers
    getStatusClass(percent) {
        if (percent >= 90) return 'critical';
        if (percent >= 75) return 'warning';
        return 'success';
    }

    formatUptime(days) {
        if (days >= 1) return `${Math.floor(days)}d`;
        const hours = days * 24;
        if (hours >= 1) return `${Math.floor(hours)}h`;
        return `${Math.floor(hours * 60)}m`;
    }

    formatTime(timestamp) {
        if (!timestamp) return '-';
        const date = new Date(timestamp);
        return date.toLocaleTimeString();
    }

    formatVersion(version) {
        // Normalize version format: remove trailing .0 for consistency
        // e.g., "1.0.76.0" -> "1.0.76", "1.0.76" stays "1.0.76"
        if (!version || version === 'Unknown') return version;
        return version.replace(/\.0$/, '');
    }

    showLoading() {
        document.getElementById('loadingOverlay')?.classList.remove('hidden');
    }

    hideLoading() {
        document.getElementById('loadingOverlay')?.classList.add('hidden');
    }

    showSpinner() {
        document.getElementById('refreshSpinner')?.classList.add('spinning');
        document.getElementById('refreshSpinner')?.classList.remove('hidden');
    }

    hideSpinner() {
        document.getElementById('refreshSpinner')?.classList.remove('spinning');
    }

    showError(message) {
        console.error(message);
        // Could show a toast notification here
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Active Alerts Polling and Dropdown
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Setup alert dropdown event listeners
     */
    setupAlertDropdown() {
        const dropdownBtn = document.getElementById('alertDropdownBtn');
        const dropdownMenu = document.getElementById('alertDropdownMenu');
        const productionFilter = document.getElementById('productionOnlyFilter');
        
        if (!dropdownBtn || !dropdownMenu) return;
        
        // Toggle dropdown on button click
        dropdownBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            this.alertDropdownOpen = !this.alertDropdownOpen;
            dropdownMenu.classList.toggle('hidden', !this.alertDropdownOpen);
        });
        
        // Close dropdown when clicking outside
        document.addEventListener('click', (e) => {
            if (!dropdownBtn.contains(e.target) && !dropdownMenu.contains(e.target)) {
                this.alertDropdownOpen = false;
                dropdownMenu.classList.add('hidden');
            }
        });
        
        // Close on Escape key
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.alertDropdownOpen) {
                this.alertDropdownOpen = false;
                dropdownMenu.classList.add('hidden');
            }
        });
        
        // Production filter checkbox
        if (productionFilter) {
            productionFilter.addEventListener('change', (e) => {
                this.showOnlyProduction = e.target.checked;
                // Save preference to localStorage
                localStorage.setItem('alertProductionOnly', this.showOnlyProduction);
                // Re-render with cached data
                if (this.lastAlertData) {
                    this.renderAlertDropdown(this.lastAlertData);
                }
            });
            
            // Restore from localStorage if available
            const savedPref = localStorage.getItem('alertProductionOnly');
            if (savedPref !== null) {
                this.showOnlyProduction = savedPref === 'true';
                productionFilter.checked = this.showOnlyProduction;
            }
        }
    }

    /**
     * Start polling for active alerts
     */
    startAlertPolling() {
        // Poll immediately
        this.pollActiveAlerts();
        
        // Then poll periodically
        this.alertPollingTimer = setInterval(() => {
            this.pollActiveAlerts();
        }, this.alertPollingInterval);
    }

    /**
     * Stop alert polling
     */
    stopAlertPolling() {
        if (this.alertPollingTimer) {
            clearInterval(this.alertPollingTimer);
            this.alertPollingTimer = null;
        }
    }

    /**
     * Poll the API for active alerts
     */
    async pollActiveAlerts() {
        try {
            const response = await fetch('api/alerts/active');
            if (!response.ok) {
                console.warn('Failed to fetch active alerts:', response.status);
                return;
            }
            
            const data = await response.json();
            this.activeAlerts = data.servers || [];
            this.lastAlertData = data; // Cache for filter re-render
            
            // Update production patterns from config
            if (data.productionPatterns && data.productionPatterns.length > 0) {
                this.productionPatterns = data.productionPatterns;
            }
            
            // Update default filter state from config (only on first load)
            if (localStorage.getItem('alertProductionOnly') === null && data.showOnlyProductionDefault !== undefined) {
                this.showOnlyProduction = data.showOnlyProductionDefault;
                const checkbox = document.getElementById('productionOnlyFilter');
                if (checkbox) checkbox.checked = this.showOnlyProduction;
            }
            
            // Update polling interval from config
            if (data.pollingIntervalSeconds) {
                const newInterval = data.pollingIntervalSeconds * 1000;
                if (newInterval !== this.alertPollingInterval) {
                    this.alertPollingInterval = newInterval;
                    // Restart polling with new interval
                    this.stopAlertPolling();
                    this.alertPollingTimer = setInterval(() => {
                        this.pollActiveAlerts();
                    }, this.alertPollingInterval);
                }
            }
            
            // Render the dropdown
            this.renderAlertDropdown(data);
            
        } catch (error) {
            console.error('Error polling active alerts:', error);
        }
    }
    
    /**
     * Check if a server name matches any production pattern
     */
    isProductionServer(serverName) {
        return this.productionPatterns.some(pattern => {
            try {
                const regex = new RegExp(pattern, 'i');
                return regex.test(serverName);
            } catch (e) {
                console.warn('Invalid production pattern:', pattern);
                return false;
            }
        });
    }

    /**
     * Render the alert dropdown with current data
     */
    renderAlertDropdown(data) {
        const container = document.getElementById('alertDropdownContainer');
        const dropdownBtn = document.getElementById('alertDropdownBtn');
        const dropdownList = document.getElementById('alertDropdownList');
        const alertBadge = document.getElementById('alertBadge');
        const lastPollSpan = document.getElementById('alertLastPoll');
        
        if (!container || !dropdownBtn || !dropdownList) return;
        
        let servers = data.servers || [];
        
        // Show/hide container based on whether there are alerts and polling is enabled
        if (!data.pollingEnabled) {
            container.classList.add('hidden');
            return;
        }
        
        // Filter: Only show servers with errors from today (based on latestAlertTimestamp)
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        servers = servers.filter(s => {
            if (!s.latestAlertTimestamp) return false;
            const alertDate = new Date(s.latestAlertTimestamp);
            return alertDate >= today;
        });
        
        // Filter: Only show servers with errors (Critical or Error count > 0)
        // Skip Warning and Info for the dropdown display
        servers = servers.filter(s => s.criticalCount > 0 || (s.errorCount || 0) > 0);
        
        // Sort: Production servers first, then by critical count, then by name
        servers = servers.map(s => ({
            ...s,
            isProduction: this.isProductionServer(s.serverName)
        })).sort((a, b) => {
            // Production servers first
            if (a.isProduction && !b.isProduction) return -1;
            if (!a.isProduction && b.isProduction) return 1;
            // Then by critical count
            if (b.criticalCount !== a.criticalCount) return b.criticalCount - a.criticalCount;
            // Then by error count
            const aError = a.errorCount || 0;
            const bError = b.errorCount || 0;
            if (bError !== aError) return bError - aError;
            // Then alphabetically
            return a.serverName.localeCompare(b.serverName);
        });
        
        // Apply production filter if enabled
        if (this.showOnlyProduction) {
            servers = servers.filter(s => s.isProduction);
        }
        
        // Calculate totals for filtered servers
        const totalCritical = servers.reduce((sum, s) => sum + s.criticalCount, 0);
        const totalError = servers.reduce((sum, s) => sum + (s.errorCount || 0), 0);
        const totalAlerts = totalCritical + totalError;
        
        // Hide container if no servers with errors today
        if (servers.length === 0) {
            container.classList.add('hidden');
            return;
        }
        
        container.classList.remove('hidden');
        
        // Update badge with filtered count
        alertBadge.textContent = totalAlerts;
        
        // Update button styling based on severity
        dropdownBtn.classList.remove('has-critical', 'has-warning');
        if (totalCritical > 0) {
            dropdownBtn.classList.add('has-critical');
        } else if (totalError > 0) {
            dropdownBtn.classList.add('has-warning'); // Use warning style for errors
        }
        
        // Update last poll time
        if (lastPollSpan && data.lastPolled) {
            const pollDate = new Date(data.lastPolled);
            lastPollSpan.textContent = `Updated ${this.formatTimeAgo(pollDate)}`;
        }
        
        // Render server list
        dropdownList.innerHTML = servers.map(server => {
            const highlight = server.criticalCount > 0 ? 'critical-highlight' : 
                              (server.errorCount || 0) > 0 ? 'warning-highlight' : 'info-highlight';
            const prodBadge = server.isProduction ? '<span class="prod-badge">PROD</span>' : '';
            
            return `
                <div class="alert-dropdown-item ${highlight}" data-server="${server.serverName}">
                    <span class="alert-server-name">${prodBadge}${server.serverName}</span>
                    <div class="alert-severity-badges">
                        ${server.criticalCount > 0 ? `<span class="alert-severity-bullet critical">${server.criticalCount}</span>` : ''}
                        ${(server.errorCount || 0) > 0 ? `<span class="alert-severity-bullet error">${server.errorCount}</span>` : ''}
                    </div>
                </div>
            `;
        }).join('');
        
        // Add click handlers to each item
        dropdownList.querySelectorAll('.alert-dropdown-item').forEach(item => {
            item.addEventListener('click', async () => {
                const serverName = item.dataset.server;
                await this.handleAlertClick(serverName);
            });
        });
    }

    /**
     * Handle click on an alert item - navigate to server and acknowledge
     */
    async handleAlertClick(serverName) {
        // Close dropdown
        this.alertDropdownOpen = false;
        document.getElementById('alertDropdownMenu')?.classList.add('hidden');
        
        // Acknowledge the alert (remove from list)
        try {
            await fetch(`api/alerts/acknowledge/${encodeURIComponent(serverName)}`, {
                method: 'POST'
            });
        } catch (error) {
            console.warn('Failed to acknowledge alert:', error);
        }
        
        // Navigate to the server
        await this.selectServer(serverName);
        
        // Refresh alerts immediately
        await this.pollActiveAlerts();
    }

    /**
     * Format a date as "X ago" string
     */
    formatTimeAgo(date) {
        const seconds = Math.floor((new Date() - date) / 1000);
        
        if (seconds < 60) return 'just now';
        if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
        if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
        return `${Math.floor(seconds / 86400)}d ago`;
    }
}

/**
 * Theme Manager
 */
class ThemeManager {
    constructor() {
        this.theme = localStorage.getItem('dashboard-theme') || 
                     (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
        this.apply();
    }

    toggle() {
        this.setTheme(this.theme === 'dark' ? 'light' : 'dark');
    }

    setTheme(theme) {
        this.theme = theme;
        this.apply();
        localStorage.setItem('dashboard-theme', this.theme);
    }

    apply() {
        document.documentElement.setAttribute('data-theme', this.theme);
        // Sync checkbox toggle state
        const toggle = document.getElementById('themeToggle');
        if (toggle && toggle.type === 'checkbox') {
            toggle.checked = this.theme === 'dark';
        }
    }
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
    window.dashboardApp = new DashboardApp();
    window.dashboard = window.dashboardApp; // Alias for onclick handlers
    window.dashboardApp.init();
});
