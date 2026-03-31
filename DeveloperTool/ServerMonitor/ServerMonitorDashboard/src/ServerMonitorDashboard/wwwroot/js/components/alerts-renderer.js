/**
 * AlertsRenderer - Shared component for rendering alerts in dashboard and pop-out windows
 * 
 * Usage:
 *   const renderer = new AlertsRenderer({ maxAlerts: 50, showCopyButtons: true });
 *   renderer.render(tbodyElement, alertsArray);
 */
class AlertsRenderer {
    constructor(options = {}) {
        this.maxAlerts = options.maxAlerts || 50;
        this.showCopyButtons = options.showCopyButtons !== false;
        this.showExpandable = options.showExpandable !== false;
        this.showModal = options.showModal !== false;
        this.showCategory = options.showCategory !== false;
        
        // Callback for opening modal (should be set by parent)
        this.onOpenModal = options.onOpenModal || null;
        this.onCopyMarkdown = options.onCopyMarkdown || null;
        this.onCopyJson = options.onCopyJson || null;
    }
    
    /**
     * Normalizes severity from string or number to consistent lowercase string
     */
    normalizeSeverity(sev) {
        if (typeof sev === 'string') return sev.toLowerCase();
        // Fallback for numeric values (legacy)
        const names = ['informational', 'warning', 'critical'];
        return names[sev] || 'unknown';
    }
    
    /**
     * Gets CSS class for severity badge
     */
    getSeverityClass(sev) {
        const name = this.normalizeSeverity(sev);
        if (name === 'critical') return 'critical';
        if (name === 'warning') return 'warning';
        return 'info';
    }
    
    /**
     * Gets emoji icon for severity
     */
    getSeverityIcon(sev) {
        const name = this.normalizeSeverity(sev);
        if (name === 'critical') return '🔴';
        if (name === 'warning') return '🟡';
        return '🔵';
    }
    
    /**
     * Sorts alerts by severity (critical first), then timestamp (newest first)
     */
    sortAlerts(alerts) {
        const severityOrder = { critical: 0, warning: 1, informational: 2 };
        return [...alerts].sort((a, b) => {
            const aSev = severityOrder[this.normalizeSeverity(a.severity)] ?? 3;
            const bSev = severityOrder[this.normalizeSeverity(b.severity)] ?? 3;
            if (aSev !== bSev) return aSev - bSev;
            return new Date(b.timestamp) - new Date(a.timestamp);
        });
    }
    
    /**
     * Extracts display context from alert metadata
     */
    extractContext(alert) {
        const meta = alert.metadata || {};
        const parts = [];
        
        // DB2 alerts
        if (meta.Db2Instance) {
            parts.push(`<span class="context-tag db2">📊 ${this.escapeHtml(meta.Db2Instance)}</span>`);
            if (meta.Db2Level) {
                parts.push(`<span class="context-value">${this.escapeHtml(meta.Db2Level)}</span>`);
            }
        }
        
        // Database name
        if (meta.Database || meta.DatabaseName_DB) {
            const dbName = meta.Database || meta.DatabaseName_DB;
            parts.push(`<span class="context-tag database">🗄️ ${this.escapeHtml(dbName)}</span>`);
        }
        
        // Instance name
        if (meta.Instance && !meta.Db2Instance) {
            parts.push(`<span class="context-tag instance">🖥️ ${this.escapeHtml(meta.Instance)}</span>`);
        }
        
        // Event Log alerts
        if (meta.EventId) {
            parts.push(`<span class="context-tag event">📋 Event ${meta.EventId}</span>`);
        }
        if ((meta.Source || meta.EventSource) && !meta.Db2Instance) {
            const source = meta.Source || meta.EventSource;
            parts.push(`<span class="context-value">${this.escapeHtml(source)}</span>`);
        }
        
        // Scheduled Task alerts
        if (meta.TaskName) {
            parts.push(`<span class="context-tag task">📅 ${this.escapeHtml(meta.TaskName)}</span>`);
        }
        
        return parts.join(' ');
    }
    
    /**
     * Formats time for display
     */
    formatTime(timestamp) {
        if (!timestamp) return '-';
        const date = new Date(timestamp);
        return date.toLocaleTimeString();
    }
    
    /**
     * Formats full date and time
     */
    formatDateTime(timestamp) {
        if (!timestamp) return '-';
        const date = new Date(timestamp);
        return date.toLocaleString();
    }
    
    /**
     * Escapes HTML special characters
     */
    escapeHtml(text) {
        if (text == null) return '';
        const div = document.createElement('div');
        div.textContent = String(text);
        return div.innerHTML;
    }
    
    /**
     * Format alert details for inline display
     */
    formatDetails(alert) {
        let html = '<div class="alert-metadata">';
        
        // Alert ID first
        if (alert.id) {
            html += `<div class="metadata-item alert-id-inline">
                <span class="metadata-key">Alert ID:</span> 
                <span class="metadata-val alert-id-val">${this.escapeHtml(alert.id)}</span>
            </div>`;
        }
        
        // Details text
        if (alert.details) {
            html += `<div class="metadata-section">
                <div class="metadata-label">Details</div>
                <div class="metadata-value">${this.escapeHtml(alert.details)}</div>
            </div>`;
        }
        
        // Timestamp
        if (alert.timestamp) {
            html += `<div class="metadata-item">
                <span class="metadata-key">Timestamp:</span> 
                <span class="metadata-val">${this.formatDateTime(alert.timestamp)}</span>
            </div>`;
        }
        
        // Distribution history
        if (alert.distributionHistory && alert.distributionHistory.length > 0) {
            html += `<div class="metadata-section">
                <div class="metadata-label">Distribution History</div>
                <div class="distribution-list">`;
            alert.distributionHistory.forEach(d => {
                const icon = d.success ? '✅' : '❌';
                html += `<div class="distribution-item">${icon} ${d.channelType} → ${d.destination || 'N/A'} (${this.formatTime(d.timestamp)})</div>`;
            });
            html += '</div></div>';
        }
        
        // Metadata (exclude Db2RawBlock)
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
        
        // Db2RawBlock (if present)
        if (alert.metadata?.Db2RawBlock) {
            html += `<div class="metadata-section">
                <div class="metadata-label">DB2 Diagnostic Block</div>
                <pre class="db2-raw-block">${this.escapeHtml(alert.metadata.Db2RawBlock)}</pre>
            </div>`;
        }
        
        html += '</div>';
        return html;
    }
    
    /**
     * Renders alerts to a container element
     * @param {HTMLElement} container - The tbody element to render into
     * @param {Array} alerts - Array of alert objects
     * @param {Object} options - Additional render options
     */
    render(container, alerts, options = {}) {
        if (!container || !alerts) return;
        
        const sorted = this.sortAlerts(alerts).slice(0, this.maxAlerts);
        
        // Store for event handlers
        container._renderedAlerts = sorted;
        
        container.innerHTML = sorted.map((alert, idx) => {
            const sevName = this.normalizeSeverity(alert.severity);
            const sevClass = this.getSeverityClass(alert.severity);
            const displayName = sevName.charAt(0).toUpperCase() + sevName.slice(1);
            const hasMetadata = alert.metadata && Object.keys(alert.metadata).length > 0;
            const hasDetails = (alert.details || hasMetadata) && this.showExpandable;
            const context = this.extractContext(alert);
            
            let html = `
                <tr class="alert-row ${hasDetails ? 'expandable' : ''}" data-alert-idx="${idx}">
                    <td><span class="severity-badge ${sevClass}">${displayName}</span></td>`;
            
            if (this.showCategory) {
                html += `<td>${this.escapeHtml(alert.category || '-')}</td>`;
            }
            
            html += `
                    <td class="alert-message-cell">
                        ${this.escapeHtml(alert.message || '-')}
                        ${hasDetails ? '<span class="expand-indicator">▶</span>' : ''}
                    </td>
                    <td class="alert-context-cell">${context}</td>
                    <td class="alert-time-cell">
                        ${this.formatTime(alert.timestamp)}`;
            
            if (this.showCopyButtons) {
                html += `
                        <button class="btn-icon btn-copy-md" title="Copy as Markdown">📝</button>
                        <button class="btn-icon btn-copy-json" title="Copy as JSON">📋</button>`;
            }
            
            if (hasDetails && this.showModal) {
                html += `<button class="btn-icon btn-open-modal" title="Open in modal">🔍</button>`;
            }
            
            html += `
                    </td>
                </tr>`;
            
            if (hasDetails) {
                html += `
                <tr class="alert-details-row hidden" data-alert-details-idx="${idx}">
                    <td colspan="${this.showCategory ? 5 : 4}">
                        <div class="alert-details-content">
                            ${this.formatDetails(alert)}
                        </div>
                    </td>
                </tr>`;
            }
            
            return html;
        }).join('');
        
        // Bind event handlers
        this.bindEventHandlers(container);
    }
    
    /**
     * Binds click handlers for expand, modal, copy buttons
     */
    bindEventHandlers(container) {
        const alerts = container._renderedAlerts || [];
        
        // Expandable rows
        if (this.showExpandable) {
            container.querySelectorAll('.alert-row.expandable').forEach(row => {
                row.addEventListener('click', (e) => {
                    if (e.target.closest('.btn-icon')) return;
                    
                    const idx = row.dataset.alertIdx;
                    const detailsRow = container.querySelector(`[data-alert-details-idx="${idx}"]`);
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
        
        // Modal buttons
        if (this.showModal) {
            container.querySelectorAll('.btn-open-modal').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    const row = btn.closest('.alert-row');
                    const idx = parseInt(row.dataset.alertIdx);
                    const alert = alerts[idx];
                    if (alert && this.onOpenModal) {
                        this.onOpenModal(alert);
                    }
                });
            });
        }
        
        // Copy markdown buttons
        if (this.showCopyButtons) {
            container.querySelectorAll('.btn-copy-md').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    const row = btn.closest('.alert-row');
                    const idx = parseInt(row.dataset.alertIdx);
                    const alert = alerts[idx];
                    if (alert) {
                        if (this.onCopyMarkdown) {
                            this.onCopyMarkdown(alert);
                        } else {
                            this.copyAsMarkdown(alert);
                        }
                    }
                });
            });
            
            container.querySelectorAll('.btn-copy-json').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    const row = btn.closest('.alert-row');
                    const idx = parseInt(row.dataset.alertIdx);
                    const alert = alerts[idx];
                    if (alert) {
                        if (this.onCopyJson) {
                            this.onCopyJson(alert);
                        } else {
                            this.copyAsJson(alert);
                        }
                    }
                });
            });
        }
    }
    
    /**
     * Default copy as markdown implementation
     */
    copyAsMarkdown(alert) {
        const lines = [
            `## Alert: ${alert.message || 'No message'}`,
            '',
            `- **Severity**: ${this.normalizeSeverity(alert.severity)}`,
            `- **Category**: ${alert.category || 'N/A'}`,
            `- **Time**: ${this.formatDateTime(alert.timestamp)}`,
        ];
        
        if (alert.id) {
            lines.push(`- **Alert ID**: ${alert.id}`);
        }
        
        if (alert.details) {
            lines.push('', '### Details', '', alert.details);
        }
        
        if (alert.metadata && Object.keys(alert.metadata).length > 0) {
            lines.push('', '### Metadata', '');
            for (const [key, value] of Object.entries(alert.metadata)) {
                if (key !== 'Db2RawBlock') {
                    const displayValue = typeof value === 'object' ? JSON.stringify(value) : value;
                    lines.push(`- **${key}**: ${displayValue}`);
                }
            }
        }
        
        navigator.clipboard.writeText(lines.join('\n')).then(() => {
            this.showToast('Copied as Markdown');
        });
    }
    
    /**
     * Default copy as JSON implementation
     */
    copyAsJson(alert) {
        navigator.clipboard.writeText(JSON.stringify(alert, null, 2)).then(() => {
            this.showToast('Copied as JSON');
        });
    }
    
    /**
     * Shows a toast notification
     */
    showToast(message) {
        let toast = document.getElementById('alert-renderer-toast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'alert-renderer-toast';
            toast.className = 'toast-notification';
            document.body.appendChild(toast);
        }
        toast.textContent = message;
        toast.classList.add('show');
        setTimeout(() => toast.classList.remove('show'), 2000);
    }
}

// Export for both module and global use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = AlertsRenderer;
} else {
    window.AlertsRenderer = AlertsRenderer;
}
