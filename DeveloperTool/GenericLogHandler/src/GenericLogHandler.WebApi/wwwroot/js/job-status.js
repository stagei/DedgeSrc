/**
 * Job Status Page JavaScript
 * Handles job status display, filtering, and history
 */
(function() {
    'use strict';

    const fromDateInput = document.getElementById('fromDate');
    const toDateInput = document.getElementById('toDate');
    const statusFilter = document.getElementById('statusFilter');
    const jobNameFilter = document.getElementById('jobNameFilter');
    const refreshBtn = document.getElementById('refreshBtn');
    const historyModal = document.getElementById('historyModal');
    const closeHistory = document.getElementById('closeHistory');

    /**
     * Initialize page
     */
    function init() {
        // Set default dates (last 24 hours)
        const now = new Date();
        const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
        toDateInput.value = now.toISOString().slice(0, 16);
        fromDateInput.value = yesterday.toISOString().slice(0, 16);

        // Event listeners
        refreshBtn.addEventListener('click', refresh);
        closeHistory.addEventListener('click', () => historyModal.classList.remove('show'));
        historyModal.addEventListener('click', (e) => {
            if (e.target === historyModal) historyModal.classList.remove('show');
        });

        // Keyboard shortcut for closing modal
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && historyModal.classList.contains('show')) {
                historyModal.classList.remove('show');
            }
        });

        // Initialize view tabs
        initViewTabs();

        // Initial load
        refresh();
        loadDatabaseStats();

        // Auto-refresh job data every 30 seconds
        setInterval(refresh, 30000);
        
        // Refresh database stats every 10 minutes
        setInterval(loadDatabaseStats, 600000);
    }

    /**
     * Get CSS class for status badge
     */
    function getStatusClass(status) {
        if (!status) return 'unknown';
        const s = status.toLowerCase();
        if (s === 'timedout' || s === 'timed out') return 'timedout';
        if (s.includes('start') || s.includes('running')) return 'started';
        if (s.includes('complet') || s.includes('success')) return 'completed';
        if (s.includes('fail') || s.includes('error')) return 'failed';
        return 'unknown';
    }
    
    /**
     * Initialize view tabs
     */
    function initViewTabs() {
        const tabs = document.querySelectorAll('.view-tab');
        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                // Remove active from all tabs
                tabs.forEach(t => t.classList.remove('active'));
                // Hide all views
                document.querySelectorAll('.view-section').forEach(v => v.classList.remove('active'));
                
                // Activate clicked tab
                tab.classList.add('active');
                const viewId = tab.dataset.view + 'View';
                document.getElementById(viewId).classList.add('active');
                
                // Load data for the view
                if (tab.dataset.view === 'executions') {
                    loadExecutions();
                } else if (tab.dataset.view === 'orphaned') {
                    loadOrphaned();
                }
            });
        });
    }

    /**
     * Load job status summary
     */
    async function loadSummary() {
        try {
            const params = new URLSearchParams();
            if (fromDateInput.value) params.append('fromDate', fromDateInput.value);
            if (toDateInput.value) params.append('toDate', toDateInput.value);
            if (jobNameFilter.value) params.append('jobName', jobNameFilter.value);

            const response = await Api.get('/api/JobStatus/summary?' + params.toString());
            if (response && response.Success) {
                const data = response.Data;
                document.getElementById('totalJobs').textContent = data.TotalJobs.toLocaleString();
                document.getElementById('startedCount').textContent = data.StartedCount.toLocaleString();
                document.getElementById('completedCount').textContent = data.CompletedCount.toLocaleString();
                document.getElementById('failedCount').textContent = data.FailedCount.toLocaleString();
            }
        } catch (err) {
            console.error('Error loading summary:', err);
            Toast.error('Failed to load job summary');
        }
    }

    /**
     * Group flat job events by name and determine overall state
     */
    function groupJobEvents(events) {
        const groups = {};
        for (const ev of events) {
            if (!groups[ev.JobName]) {
                groups[ev.JobName] = { name: ev.JobName, events: [], computer: ev.ComputerName };
            }
            groups[ev.JobName].events.push(ev);
            if (new Date(ev.LastSeen) > new Date(groups[ev.JobName].events[0]?.LastSeen || 0)) {
                groups[ev.JobName].computer = ev.ComputerName;
            }
        }

        return Object.values(groups).map(g => {
            const statuses = g.events.map(e => (e.JobStatus || '').toLowerCase());
            const hasFailed = statuses.some(s => s.includes('fail') || s.includes('error'));
            const hasCompleted = statuses.some(s => s.includes('complet') || s.includes('success'));
            const hasStarted = statuses.some(s => s.includes('start'));

            let overall = 'unknown';
            if (hasFailed) overall = 'failed';
            else if (hasCompleted) overall = 'completed';
            else if (hasStarted) overall = 'in-progress';

            const startEv = g.events.find(e => (e.JobStatus || '').toLowerCase().includes('start'));
            const endEv = g.events.find(e => {
                const s = (e.JobStatus || '').toLowerCase();
                return s.includes('complet') || s.includes('fail') || s.includes('error');
            });
            let durationSec = null;
            if (startEv && endEv) {
                durationSec = (new Date(endEv.LastSeen) - new Date(startEv.LastSeen)) / 1000;
            }

            const lastSeen = g.events.reduce((max, e) =>
                new Date(e.LastSeen) > new Date(max) ? e.LastSeen : max, g.events[0].LastSeen);

            return { ...g, overall, durationSec, lastSeen };
        }).sort((a, b) => {
            const order = { 'failed': 0, 'in-progress': 1, 'completed': 2, 'unknown': 3 };
            return (order[a.overall] ?? 9) - (order[b.overall] ?? 9);
        });
    }

    /**
     * Load jobs list with grouped expandable rows
     */
    async function loadJobs() {
        try {
            const params = new URLSearchParams();
            if (fromDateInput.value) params.append('fromDate', fromDateInput.value);
            if (toDateInput.value) params.append('toDate', toDateInput.value);
            if (statusFilter.value) params.append('status', statusFilter.value);
            params.append('limit', '100');

            const response = await Api.get('/api/JobStatus/jobs?' + params.toString());
            const tbody = document.getElementById('jobsBody');
            
            if (response && response.Success && response.Data.length > 0) {
                let filtered = response.Data;
                if (jobNameFilter.value) {
                    const filter = jobNameFilter.value.toLowerCase();
                    filtered = filtered.filter(j => j.JobName.toLowerCase().includes(filter));
                }

                const grouped = groupJobEvents(filtered);
                let html = '';

                for (const job of grouped) {
                    const rowClass = 'job-' + job.overall;
                    const statusLabel = job.overall === 'in-progress' ? 'Running' :
                        job.overall.charAt(0).toUpperCase() + job.overall.slice(1);
                    const progressClass = job.overall === 'in-progress' ? 'in-progress' : job.overall;

                    html += `<tr class="job-row-parent ${rowClass}" data-group="${escapeHtml(job.name)}">
                        <td class="job-name">${escapeHtml(job.name)}</td>
                        <td><span class="status-badge ${getStatusClass(statusLabel)}">${escapeHtml(statusLabel)}</span></td>
                        <td><div class="job-progress"><div class="job-progress-fill ${progressClass}"></div></div></td>
                        <td class="job-duration${job.durationSec !== null && job.durationSec > 300 ? ' slow' : ''}">${formatDuration(job.durationSec)}</td>
                        <td>${escapeHtml(job.computer)}</td>
                        <td>${formatDate(job.lastSeen)}</td>
                        <td><button class="btn btn-sm btn-history" data-job="${escapeHtml(job.name)}">History</button></td>
                    </tr>`;

                    for (const ev of job.events) {
                        html += `<tr class="job-row-child" data-parent="${escapeHtml(job.name)}">
                            <td>↳ ${escapeHtml(ev.JobStatus)}</td>
                            <td><span class="status-badge ${getStatusClass(ev.JobStatus)}">${escapeHtml(ev.JobStatus)}</span></td>
                            <td colspan="2">${escapeHtml(ev.ComputerName)}</td>
                            <td colspan="2">${formatDate(ev.LastSeen)}</td>
                            <td>×${ev.OccurrenceCount}</td>
                        </tr>`;
                    }
                }

                tbody.innerHTML = html;

                tbody.querySelectorAll('.job-row-parent').forEach(row => {
                    row.addEventListener('click', (e) => {
                        if (e.target.closest('.btn-history')) return;
                        const group = row.dataset.group;
                        const isExpanded = row.classList.toggle('expanded');
                        tbody.querySelectorAll(`.job-row-child[data-parent="${group}"]`).forEach(child => {
                            child.classList.toggle('visible', isExpanded);
                        });
                    });
                });

                tbody.querySelectorAll('.btn-history').forEach(btn => {
                    btn.addEventListener('click', (e) => {
                        e.stopPropagation();
                        showHistory(e.target.dataset.job);
                    });
                });
            } else {
                tbody.innerHTML = '<tr><td colspan="7" style="text-align: center; padding: 2rem; color: var(--text-secondary);">No job status entries found.</td></tr>';
            }
        } catch (err) {
            console.error('Error loading jobs:', err);
            document.getElementById('jobsBody').innerHTML = '<tr><td colspan="7" style="text-align: center; padding: 2rem; color: var(--error-color);">Error loading jobs</td></tr>';
            Toast.error('Failed to load jobs');
        }
    }

    /**
     * Show job history modal
     */
    async function showHistory(jobName) {
        try {
            document.getElementById('historyTitle').textContent = 'Job History: ' + jobName;
            historyModal.classList.add('show');

            const params = new URLSearchParams();
            if (fromDateInput.value) params.append('fromDate', fromDateInput.value);
            if (toDateInput.value) params.append('toDate', toDateInput.value);
            params.append('limit', '50');

            const response = await Api.get('/api/JobStatus/history/' + encodeURIComponent(jobName) + '?' + params.toString());
            const tbody = document.getElementById('historyBody');

            if (response && response.Success && response.Data.length > 0) {
                tbody.innerHTML = response.Data.map(exec => `
                    <tr>
                        <td>${formatDateTime(exec.Timestamp)}</td>
                        <td><span class="status-badge ${getStatusClass(exec.JobStatus)}">${escapeHtml(exec.JobStatus)}</span></td>
                        <td>${escapeHtml(exec.ComputerName)}</td>
                        <td>${escapeHtml(exec.UserName)}</td>
                        <td title="${escapeHtml(exec.Message)}">${escapeHtml(truncate(exec.Message, 100))}</td>
                    </tr>
                `).join('');
            } else {
                tbody.innerHTML = '<tr><td colspan="5" style="text-align: center;">No history found</td></tr>';
            }
        } catch (err) {
            console.error('Error loading history:', err);
            Toast.error('Failed to load job history');
        }
    }

    /**
     * Load database statistics
     */
    async function loadDatabaseStats() {
        try {
            const response = await Api.get('/api/Dashboard/database-stats');
            if (response && response.Success) {
                const data = response.Data;
                document.getElementById('dbServerValue').textContent = data.ServerName || '--';
                document.getElementById('dbSizeValue').textContent = data.DatabaseSizeGb.toFixed(2);
                document.getElementById('logCountValue').textContent = data.TotalLogEntries.toLocaleString();
                const updated = new Date(data.LastUpdated);
                document.getElementById('dbStatsUpdated').textContent = 
                    'Updated: ' + updated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            }
        } catch (err) {
            console.error('Error loading database stats:', err);
            document.getElementById('dbStatsUpdated').textContent = 'Error loading stats';
        }
    }

    /**
     * Load tracked job executions
     */
    async function loadExecutions() {
        try {
            const params = new URLSearchParams();
            if (fromDateInput.value) params.append('fromDate', fromDateInput.value);
            if (toDateInput.value) params.append('toDate', toDateInput.value);
            if (statusFilter.value) params.append('status', statusFilter.value);
            if (jobNameFilter.value) params.append('jobName', jobNameFilter.value);
            params.append('limit', '100');

            const response = await Api.get('/api/JobStatus/executions?' + params.toString());
            const tbody = document.getElementById('executionsBody');
            
            if (response && response.Success && response.Data.length > 0) {
                tbody.innerHTML = response.Data.map(exec => `
                    <tr>
                        <td>${formatDateTime(exec.StartedAt)}</td>
                        <td class="job-name">${escapeHtml(exec.JobName)}</td>
                        <td><span class="status-badge ${getStatusClass(exec.Status)}">${escapeHtml(exec.Status)}</span></td>
                        <td class="duration-cell">${formatDuration(exec.DurationSeconds)}</td>
                        <td>${escapeHtml(exec.ComputerName)}</td>
                        <td title="${escapeHtml(exec.SourceFile)}">${escapeHtml(truncate(exec.SourceFile || '', 40))}</td>
                    </tr>
                `).join('');
            } else {
                tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; padding: 2rem; color: var(--text-secondary);">No job executions found.</td></tr>';
            }
        } catch (err) {
            console.error('Error loading executions:', err);
            document.getElementById('executionsBody').innerHTML = '<tr><td colspan="6" style="text-align: center; padding: 2rem; color: var(--error-color);">Error loading executions</td></tr>';
        }
    }

    /**
     * Load orphaned/timed out jobs
     */
    async function loadOrphaned() {
        try {
            const response = await Api.get('/api/JobStatus/orphaned?limit=50');
            const tbody = document.getElementById('orphanedBody');
            
            if (response && response.Success && response.Data.length > 0) {
                tbody.innerHTML = response.Data.map(exec => `
                    <tr>
                        <td>${formatDateTime(exec.StartedAt)}</td>
                        <td class="job-name">${escapeHtml(exec.JobName)}</td>
                        <td>
                            <span class="status-badge ${getStatusClass(exec.Status)}">${escapeHtml(exec.Status)}</span>
                            ${exec.Status === 'Started' ? '<span class="orphan-warning" title="Running longer than expected">⚠️</span>' : ''}
                        </td>
                        <td>${escapeHtml(exec.ComputerName)}</td>
                        <td title="${escapeHtml(exec.ErrorMessage || '')}">${escapeHtml(truncate(exec.ErrorMessage || '-', 50))}</td>
                        <td>
                            <button class="btn btn-sm btn-resolve" data-id="${exec.Id}" data-name="${escapeHtml(exec.JobName)}">Resolve</button>
                        </td>
                    </tr>
                `).join('');
                
                // Add event listeners for resolve buttons
                tbody.querySelectorAll('.btn-resolve').forEach(btn => {
                    btn.addEventListener('click', () => {
                        resolveOrphanedJob(btn.dataset.id, btn.dataset.name);
                    });
                });
            } else {
                tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; padding: 2rem; color: var(--text-secondary);">No orphaned jobs found. All jobs completed successfully!</td></tr>';
            }
        } catch (err) {
            console.error('Error loading orphaned jobs:', err);
            document.getElementById('orphanedBody').innerHTML = '<tr><td colspan="6" style="text-align: center; padding: 2rem; color: var(--error-color);">Error loading orphaned jobs</td></tr>';
        }
    }

    /**
     * Resolve an orphaned job
     */
    async function resolveOrphanedJob(id, jobName) {
        const resolution = prompt(`Resolve job "${jobName}"?\nEnter resolution notes (or leave blank):`);
        if (resolution === null) return; // Cancelled
        
        try {
            const response = await Api.post(`/api/JobStatus/resolve/${id}`, {
                Status: 'Completed',
                Resolution: resolution || 'Manually resolved'
            });
            
            if (response && response.Success) {
                Toast.success('Job marked as resolved');
                loadOrphaned();
                loadExecutionSummary();
            } else {
                Toast.error(response?.Error || 'Failed to resolve job');
            }
        } catch (err) {
            console.error('Error resolving job:', err);
            Toast.error('Failed to resolve job');
        }
    }

    /**
     * Load execution summary (for timed out count)
     */
    async function loadExecutionSummary() {
        try {
            const params = new URLSearchParams();
            if (fromDateInput.value) params.append('fromDate', fromDateInput.value);
            if (toDateInput.value) params.append('toDate', toDateInput.value);

            const response = await Api.get('/api/JobStatus/executions/summary?' + params.toString());
            if (response && response.Success) {
                const data = response.Data;
                const timedoutEl = document.getElementById('timedoutCount');
                if (timedoutEl) {
                    timedoutEl.textContent = data.TimedOutCount.toLocaleString();
                }
            }
        } catch (err) {
            console.error('Error loading execution summary:', err);
        }
    }

    /**
     * Format duration in seconds to readable format
     */
    function formatDuration(seconds) {
        if (seconds === null || seconds === undefined) return '-';
        if (seconds < 60) return Math.round(seconds) + 's';
        if (seconds < 3600) {
            const mins = Math.floor(seconds / 60);
            const secs = Math.round(seconds % 60);
            return `${mins}m ${secs}s`;
        }
        const hours = Math.floor(seconds / 3600);
        const mins = Math.floor((seconds % 3600) / 60);
        return `${hours}h ${mins}m`;
    }

    /**
     * Refresh all data
     */
    function refresh() {
        loadSummary();
        loadJobs();
        loadExecutionSummary();
        
        // Also refresh active view if not events
        const activeTab = document.querySelector('.view-tab.active');
        if (activeTab && activeTab.dataset.view === 'executions') {
            loadExecutions();
        } else if (activeTab && activeTab.dataset.view === 'orphaned') {
            loadOrphaned();
        }
    }

    // Utility functions
    function escapeHtml(str) {
        if (!str) return '';
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    function formatDate(dateStr) {
        if (!dateStr) return '-';
        const d = new Date(dateStr);
        if (isNaN(d.getTime())) return '-';
        // Format: YYYY-MM-DD HH:mm:ss
        const year = d.getFullYear();
        const month = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        const hours = String(d.getHours()).padStart(2, '0');
        const minutes = String(d.getMinutes()).padStart(2, '0');
        const seconds = String(d.getSeconds()).padStart(2, '0');
        return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
    }

    function formatDateTime(dateStr) {
        return formatDate(dateStr);
    }

    function truncate(str, maxLen) {
        if (!str) return '';
        return str.length > maxLen ? str.substring(0, maxLen) + '...' : str;
    }

    // Make showHistory available globally for backward compatibility
    window.showHistory = showHistory;

    // Initialize on DOM ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
