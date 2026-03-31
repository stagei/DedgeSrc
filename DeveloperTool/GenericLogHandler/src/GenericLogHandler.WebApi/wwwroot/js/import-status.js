/**
 * Import Status Page JavaScript
 * Displays import job status for each source with auto-refresh
 */
(function() {
    'use strict';

    let autoRefreshTimer = null;
    const AUTO_REFRESH_INTERVAL = 10000;

    function init() {
        document.getElementById('refreshBtn').addEventListener('click', () => loadStatus(true));
        
        const autoCheck = document.getElementById('autoRefreshCheck');
        autoCheck.addEventListener('change', toggleAutoRefresh);
        
        loadStatus(true);
        
        if (autoCheck.checked) {
            startAutoRefresh();
        }
    }

    function toggleAutoRefresh() {
        const checked = document.getElementById('autoRefreshCheck').checked;
        if (checked) {
            startAutoRefresh();
        } else {
            stopAutoRefresh();
        }
    }

    function startAutoRefresh() {
        stopAutoRefresh();
        autoRefreshTimer = setInterval(() => loadStatus(false), AUTO_REFRESH_INTERVAL);
    }

    function stopAutoRefresh() {
        if (autoRefreshTimer) {
            clearInterval(autoRefreshTimer);
            autoRefreshTimer = null;
        }
    }

    function escapeHtml(s) {
        if (s == null) return '';
        const div = document.createElement('div');
        div.textContent = s;
        return div.innerHTML;
    }

    function formatDate(d) {
        if (!d) return '-';
        const date = typeof d === 'string' ? new Date(d) : d;
        if (isNaN(date.getTime())) return '-';
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        const hours = String(date.getHours()).padStart(2, '0');
        const minutes = String(date.getMinutes()).padStart(2, '0');
        const seconds = String(date.getSeconds()).padStart(2, '0');
        return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
    }

    function formatTimeAgo(d) {
        if (!d) return '';
        const date = typeof d === 'string' ? new Date(d) : d;
        if (isNaN(date.getTime())) return '';
        const diffMs = Date.now() - date.getTime();
        const diffSec = Math.floor(diffMs / 1000);
        if (diffSec < 60) return `${diffSec}s ago`;
        const diffMin = Math.floor(diffSec / 60);
        if (diffMin < 60) return `${diffMin}m ago`;
        const diffHr = Math.floor(diffMin / 60);
        if (diffHr < 24) return `${diffHr}h ${diffMin % 60}m ago`;
        const diffDay = Math.floor(diffHr / 24);
        return `${diffDay}d ago`;
    }

    function formatFileSize(bytes) {
        if (!bytes || bytes <= 0) return '-';
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
        return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
    }

    function formatDuration(ms) {
        if (!ms || ms <= 0) return '-';
        if (ms < 1000) return ms + 'ms';
        if (ms < 60000) return (ms / 1000).toFixed(1) + 's';
        const min = Math.floor(ms / 60000);
        const sec = Math.floor((ms % 60000) / 1000);
        return `${min}m ${sec}s`;
    }

    function getStatusClass(status) {
        if (!status) return '';
        const s = status.toLowerCase();
        if (s === 'completed') return 'status-completed';
        if (s === 'failed') return 'status-failed';
        if (s === 'processing') return 'status-processing';
        return '';
    }

    function getStatusBadgeClass(status) {
        if (!status) return 'warning';
        const s = status.toLowerCase();
        if (s === 'completed') return 'info';
        if (s === 'failed') return 'error';
        return 'warning';
    }

    function getStatusIcon(status) {
        if (!status) return '⏳';
        const s = status.toLowerCase();
        if (s === 'completed') return '✅';
        if (s === 'failed') return '❌';
        if (s === 'processing') return '⏳';
        return '⏳';
    }

    async function loadStatus(showLoadingIndicator) {
        const container = document.getElementById('importCards');
        const empty = document.getElementById('statusEmpty');
        const errEl = document.getElementById('statusError');
        const spinner = document.getElementById('refreshSpinner');
        const refreshLabel = document.getElementById('refreshLabel');
        const summaryBar = document.getElementById('summaryBar');

        empty.classList.add('hidden');
        errEl.classList.add('hidden');

        spinner.classList.remove('hidden');
        refreshLabel.textContent = 'Refreshing...';

        if (showLoadingIndicator && container.children.length === 0) {
            container.innerHTML = '<div style="text-align:center;padding:2rem;color:var(--text-muted);">Loading...</div>';
        }

        try {
            const response = await Api.get('/api/maintenance/import-status');
            if (!response.Success) {
                errEl.textContent = response.Error || 'Failed to load';
                errEl.classList.remove('hidden');
                container.innerHTML = '';
                summaryBar.classList.add('hidden');
                return;
            }

            const items = response.Data || [];
            if (items.length === 0) {
                container.innerHTML = '';
                summaryBar.classList.add('hidden');
                empty.classList.remove('hidden');
                return;
            }

            renderSummary(items, summaryBar);
            renderCards(items, container);

            document.getElementById('lastRefreshTime').textContent = 
                'Updated ' + new Date().toLocaleTimeString();

        } catch (e) {
            errEl.textContent = 'Error: ' + e.message;
            errEl.classList.remove('hidden');
            container.innerHTML = '';
            summaryBar.classList.add('hidden');
            Toast.error('Failed to load import status');
        } finally {
            spinner.classList.add('hidden');
            refreshLabel.textContent = '🔄 Refresh';
        }
    }

    function renderSummary(items, summaryBar) {
        const total = items.length;
        const completed = items.filter(i => i.Status === 'Completed').length;
        const failed = items.filter(i => i.Status === 'Failed').length;
        const processing = items.filter(i => i.Status === 'Processing').length;
        const totalRecords = items.reduce((sum, i) => sum + (i.RecordsProcessed || 0), 0);
        const totalFailed = items.reduce((sum, i) => sum + (i.RecordsFailed || 0), 0);

        summaryBar.innerHTML = `
            <div class="summary-stat">
                <span class="summary-stat-value">${total}</span>
                <span class="summary-stat-label">Sources</span>
            </div>
            <div class="summary-stat">
                <span class="summary-stat-value" style="color: var(--success-color, #22c55e);">${completed}</span>
                <span class="summary-stat-label">Completed</span>
            </div>
            ${failed > 0 ? `<div class="summary-stat">
                <span class="summary-stat-value" style="color: var(--error-color, #ef4444);">${failed}</span>
                <span class="summary-stat-label">Failed</span>
            </div>` : ''}
            ${processing > 0 ? `<div class="summary-stat">
                <span class="summary-stat-value" style="color: var(--warning-color, #f59e0b);">${processing}</span>
                <span class="summary-stat-label">Processing</span>
            </div>` : ''}
            <div class="summary-stat">
                <span class="summary-stat-value">${totalRecords.toLocaleString()}</span>
                <span class="summary-stat-label">Records Imported</span>
            </div>
            ${totalFailed > 0 ? `<div class="summary-stat">
                <span class="summary-stat-value" style="color: var(--error-color, #ef4444);">${totalFailed.toLocaleString()}</span>
                <span class="summary-stat-label">Records Failed</span>
            </div>` : ''}
        `;
        summaryBar.classList.remove('hidden');
    }

    function renderCards(items, container) {
        container.innerHTML = items.map(row => {
            const statusIcon = getStatusIcon(row.Status);
            const statusClass = getStatusClass(row.Status);
            const badgeClass = getStatusBadgeClass(row.Status);
            const timeAgo = formatTimeAgo(row.LastImportTimestamp);
            const hasError = row.Status === 'Failed' && row.ErrorMessage;

            return `
            <div class="import-card ${statusClass}">
                <div class="import-card-header">
                    <div class="import-card-title">
                        <span>${statusIcon}</span>
                        <span>${escapeHtml(row.SourceName)}</span>
                        <span class="source-type">${escapeHtml(row.SourceType || 'file')}</span>
                    </div>
                    <span class="severity-badge ${badgeClass}">${escapeHtml(row.Status)}</span>
                </div>
                <div class="import-card-filepath">${escapeHtml(row.FilePath || '-')}</div>
                <div class="import-card-grid">
                    <div class="import-meta">
                        <span class="import-meta-label">Last Import</span>
                        <span class="import-meta-value" title="${formatDate(row.LastImportTimestamp)}">${timeAgo || formatDate(row.LastImportTimestamp)}</span>
                    </div>
                    <div class="import-meta">
                        <span class="import-meta-label">Last Processed</span>
                        <span class="import-meta-value">${formatDate(row.LastProcessedTimestamp)}</span>
                    </div>
                    <div class="import-meta">
                        <span class="import-meta-label">Records (OK / Failed)</span>
                        <span class="import-meta-value mono">${(row.RecordsProcessed ?? 0).toLocaleString()} / ${(row.RecordsFailed ?? 0).toLocaleString()}</span>
                    </div>
                    <div class="import-meta">
                        <span class="import-meta-label">Last Line</span>
                        <span class="import-meta-value mono">${(row.LastProcessedLine ?? 0).toLocaleString()}</span>
                    </div>
                    <div class="import-meta">
                        <span class="import-meta-label">File Size</span>
                        <span class="import-meta-value mono">${formatFileSize(row.LastFileSize)}</span>
                    </div>
                    <div class="import-meta">
                        <span class="import-meta-label">Duration</span>
                        <span class="import-meta-value mono">${formatDuration(row.ProcessingDurationMs)}</span>
                    </div>
                    <div class="import-meta">
                        <span class="import-meta-label">File Created</span>
                        <span class="import-meta-value">${formatDate(row.FileCreationDate)}</span>
                    </div>
                    ${row.FileHash ? `<div class="import-meta">
                        <span class="import-meta-label">File Hash</span>
                        <span class="import-meta-value mono" title="${escapeHtml(row.FileHash)}">${escapeHtml((row.FileHash || '').substring(0, 12))}…</span>
                    </div>` : ''}
                </div>
                ${hasError ? `<div class="error-message-row">${escapeHtml(row.ErrorMessage)}</div>` : ''}
            </div>`;
        }).join('');
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
