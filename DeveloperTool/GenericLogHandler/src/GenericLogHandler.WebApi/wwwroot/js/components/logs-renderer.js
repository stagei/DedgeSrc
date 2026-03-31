/**
 * LogsRenderer - Shared component for rendering log entries in dashboard and pop-out windows
 * Based on ServerMonitor's AlertsRenderer pattern
 * 
 * Usage:
 *   const renderer = new LogsRenderer({ maxEntries: 50, showCopyButtons: true });
 *   renderer.render(tbodyElement, logsArray);
 */
class LogsRenderer {
    constructor(options = {}) {
        this.maxEntries = options.maxEntries || 50;
        this.showCopyButtons = options.showCopyButtons !== false;
        this.showExpandable = options.showExpandable !== false;
        this.showModal = options.showModal !== false;
        
        // Callback for opening modal (should be set by parent)
        this.onOpenModal = options.onOpenModal || null;
        this.onCopyMarkdown = options.onCopyMarkdown || null;
        this.onCopyJson = options.onCopyJson || null;
    }
    
    /**
     * Normalizes log level to consistent uppercase string
     */
    normalizeLevel(level) {
        if (typeof level === 'string') return level.toUpperCase();
        return 'INFO';
    }
    
    /**
     * Gets CSS class for severity badge
     */
    getLevelClass(level) {
        const name = this.normalizeLevel(level);
        if (name === 'FATAL' || name === 'ERROR') return 'error';
        if (name === 'WARN') return 'warning';
        if (name === 'DEBUG' || name === 'TRACE') return 'debug';
        return 'info';
    }
    
    /**
     * Gets emoji icon for level
     */
    getLevelIcon(level) {
        const name = this.normalizeLevel(level);
        if (name === 'FATAL') return '💀';
        if (name === 'ERROR') return '🔴';
        if (name === 'WARN') return '🟡';
        if (name === 'INFO') return '🔵';
        if (name === 'DEBUG') return '🟣';
        return '⚪';
    }
    
    /**
     * Sorts logs by timestamp (newest first)
     */
    sortLogs(logs) {
        return [...logs].sort((a, b) => {
            return new Date(b.Timestamp || b.timestamp) - new Date(a.Timestamp || a.timestamp);
        });
    }
    
    /**
     * Extracts display context from log entry metadata
     */
    extractContext(log) {
        const parts = [];
        
        if (log.JobName) {
            parts.push(`<span class="context-tag job">📋 ${this.escapeHtml(log.JobName)}</span>`);
        }
        
        if (log.Ordrenr) {
            parts.push(`<span class="context-tag order">📦 ${this.escapeHtml(log.Ordrenr)}</span>`);
        }
        
        if (log.Avdnr) {
            parts.push(`<span class="context-tag dept">🏢 ${this.escapeHtml(log.Avdnr)}</span>`);
        }
        
        if (log.AlertId) {
            parts.push(`<span class="context-tag alert">⚠️ ${this.escapeHtml(log.AlertId)}</span>`);
        }
        
        if (log.FunctionName) {
            parts.push(`<span class="context-value">${this.escapeHtml(log.FunctionName)}</span>`);
        }
        
        return parts.join(' ') || '<span class="context-none">-</span>';
    }
    
    /**
     * Formats full date and time for display (primary format for all grids)
     */
    formatTime(timestamp) {
        if (!timestamp) return '-';
        const date = new Date(timestamp);
        // Format: YYYY-MM-DD HH:mm:ss
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        const hours = String(date.getHours()).padStart(2, '0');
        const minutes = String(date.getMinutes()).padStart(2, '0');
        const seconds = String(date.getSeconds()).padStart(2, '0');
        return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
    }
    
    /**
     * Formats full date and time (alias for formatTime)
     */
    formatDateTime(timestamp) {
        return this.formatTime(timestamp);
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
     * Format log details for inline display
     */
    formatDetails(log) {
        let html = '<div class="log-metadata">';
        
        // Log ID first
        if (log.Id || log.id) {
            html += `<div class="metadata-item log-id-inline">
                <span class="metadata-key">Log ID:</span> 
                <span class="metadata-val log-id-val">${this.escapeHtml(log.Id || log.id)}</span>
            </div>`;
        }
        
        // Details section
        html += '<div class="metadata-label">Details</div>';
        html += '<div class="metadata-grid">';
        
        const fields = [
            { key: 'ComputerName', label: 'Computer' },
            { key: 'UserName', label: 'User' },
            { key: 'FunctionName', label: 'Function' },
            { key: 'SourceFile', label: 'Source File' },
            { key: 'SourceType', label: 'Source Type' },
            { key: 'ErrorId', label: 'Error ID' },
            { key: 'ExceptionType', label: 'Exception Type' },
            { key: 'AlertId', label: 'Alert ID' },
            { key: 'Ordrenr', label: 'Order Number' },
            { key: 'Avdnr', label: 'Department' },
            { key: 'JobName', label: 'Job Name' },
            { key: 'Location', label: 'Location' }
        ];
        
        for (const field of fields) {
            const value = log[field.key];
            if (value) {
                html += `<div class="metadata-item">
                    <span class="metadata-key">${field.label}:</span>
                    <span class="metadata-val">${this.escapeHtml(value)}</span>
                </div>`;
            }
        }
        
        html += '</div>';
        
        // Full message
        if (log.Message) {
            html += `<div class="metadata-section">
                <div class="metadata-label">Full Message</div>
                <pre class="log-message-full">${this.escapeHtml(log.Message)}</pre>
            </div>`;
        }
        
        // Exception details
        if (log.ExceptionType || log.StackTrace) {
            html += `<div class="metadata-section">
                <div class="metadata-label">Exception</div>
                <pre class="log-exception">${this.escapeHtml(log.ExceptionType || '')}\n${this.escapeHtml(log.StackTrace || '')}</pre>
            </div>`;
        }
        
        html += '</div>';
        return html;
    }
    
    /**
     * Renders logs to a container element
     * @param {HTMLElement} container - The tbody element to render into
     * @param {Array} logs - Array of log entry objects
     */
    render(container, logs) {
        if (!container || !logs) return;
        
        const sorted = this.sortLogs(logs).slice(0, this.maxEntries);
        
        // Store for event handlers
        container._renderedLogs = sorted;
        
        if (sorted.length === 0) {
            container.innerHTML = '<tr><td colspan="5" class="empty-state">No log entries found</td></tr>';
            return;
        }
        
        container.innerHTML = sorted.map((log, idx) => {
            const level = this.normalizeLevel(log.Level);
            const levelClass = this.getLevelClass(level);
            const hasDetails = this.showExpandable;
            const context = this.extractContext(log);
            const message = log.Message || '-';
            const truncatedMessage = message.length > 100 ? message.substring(0, 100) + '...' : message;
            
            let html = `
                <tr class="log-row ${hasDetails ? 'expandable' : ''}" data-log-idx="${idx}">
                    <td class="log-time-cell">${this.formatTime(log.Timestamp)}</td>
                    <td><span class="severity-badge ${levelClass}">${level}</span></td>
                    <td>${this.escapeHtml(log.ComputerName || '-')}</td>
                    <td class="log-message-cell">
                        ${this.escapeHtml(truncatedMessage)}
                        ${hasDetails ? '<span class="expand-indicator">▶</span>' : ''}
                    </td>
                    <td class="log-context-cell">${context}`;
            
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
                <tr class="log-details-row hidden" data-log-details-idx="${idx}">
                    <td colspan="5">
                        <div class="log-details-content">
                            ${this.formatDetails(log)}
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
        const logs = container._renderedLogs || [];
        
        // Expandable rows
        if (this.showExpandable) {
            container.querySelectorAll('.log-row.expandable').forEach(row => {
                row.addEventListener('click', (e) => {
                    if (e.target.closest('.btn-icon')) return;
                    
                    const idx = row.dataset.logIdx;
                    const detailsRow = container.querySelector(`[data-log-details-idx="${idx}"]`);
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
                    const row = btn.closest('.log-row');
                    const idx = parseInt(row.dataset.logIdx);
                    const log = logs[idx];
                    if (log && this.onOpenModal) {
                        this.onOpenModal(log);
                    }
                });
            });
        }
        
        // Copy markdown buttons
        if (this.showCopyButtons) {
            container.querySelectorAll('.btn-copy-md').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    const row = btn.closest('.log-row');
                    const idx = parseInt(row.dataset.logIdx);
                    const log = logs[idx];
                    if (log) {
                        if (this.onCopyMarkdown) {
                            this.onCopyMarkdown(log);
                        } else {
                            this.copyAsMarkdown(log);
                        }
                    }
                });
            });
            
            container.querySelectorAll('.btn-copy-json').forEach(btn => {
                btn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    const row = btn.closest('.log-row');
                    const idx = parseInt(row.dataset.logIdx);
                    const log = logs[idx];
                    if (log) {
                        if (this.onCopyJson) {
                            this.onCopyJson(log);
                        } else {
                            this.copyAsJson(log);
                        }
                    }
                });
            });
        }
    }
    
    /**
     * Default copy as markdown implementation
     */
    copyAsMarkdown(log) {
        const lines = [
            `## Log Entry: ${(log.Message || 'No message').substring(0, 50)}`,
            '',
            `- **Level**: ${this.normalizeLevel(log.Level)}`,
            `- **Computer**: ${log.ComputerName || 'N/A'}`,
            `- **Time**: ${this.formatDateTime(log.Timestamp)}`,
        ];
        
        if (log.Id) lines.push(`- **Log ID**: ${log.Id}`);
        if (log.UserName) lines.push(`- **User**: ${log.UserName}`);
        if (log.FunctionName) lines.push(`- **Function**: ${log.FunctionName}`);
        if (log.JobName) lines.push(`- **Job**: ${log.JobName}`);
        if (log.Ordrenr) lines.push(`- **Order Number**: ${log.Ordrenr}`);
        if (log.Avdnr) lines.push(`- **Department**: ${log.Avdnr}`);
        if (log.AlertId) lines.push(`- **Alert ID**: ${log.AlertId}`);
        
        if (log.Message) {
            lines.push('', '### Message', '', '```', log.Message, '```');
        }
        
        if (log.ExceptionType) {
            lines.push('', '### Exception', '', `**Type**: ${log.ExceptionType}`);
            if (log.StackTrace) {
                lines.push('', '```', log.StackTrace, '```');
            }
        }
        
        navigator.clipboard.writeText(lines.join('\n')).then(() => {
            this.showToast('Copied as Markdown');
        });
    }
    
    /**
     * Default copy as JSON implementation
     */
    copyAsJson(log) {
        navigator.clipboard.writeText(JSON.stringify(log, null, 2)).then(() => {
            this.showToast('Copied as JSON');
        });
    }
    
    /**
     * Shows a toast notification
     */
    showToast(message) {
        let toast = document.getElementById('logs-renderer-toast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'logs-renderer-toast';
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
    module.exports = LogsRenderer;
} else {
    window.LogsRenderer = LogsRenderer;
}
