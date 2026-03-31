/**
 * Keyboard Shortcuts Manager
 * Global keyboard shortcuts with help modal
 */
const Shortcuts = (function() {
    'use strict';

    const shortcuts = new Map();
    let enabled = true;
    let helpModalShowing = false;

    // Default shortcuts
    const defaultShortcuts = [
        { key: '?', description: 'Show keyboard shortcuts help', handler: showHelp },
        { key: 'Escape', description: 'Close modals / Cancel', handler: handleEscape },
        { key: 'r', description: 'Refresh current data', handler: handleRefresh },
        { key: '/', description: 'Focus search input', handler: handleSearch },
        { key: 'g h', description: 'Go to Dashboard (Home)', handler: () => navigate((typeof Api !== 'undefined' ? Api.baseUrl : '') + '/index.html') },
        { key: 'g s', description: 'Go to Log Search', handler: () => navigate((typeof Api !== 'undefined' ? Api.baseUrl : '') + '/log-search.html') },
        { key: 'g j', description: 'Go to Job Status', handler: () => navigate((typeof Api !== 'undefined' ? Api.baseUrl : '') + '/job-status.html') },
        { key: 'g a', description: 'Go to Analytics', handler: () => navigate((typeof Api !== 'undefined' ? Api.baseUrl : '') + '/analytics.html') },
        { key: 'g m', description: 'Go to Maintenance', handler: () => navigate((typeof Api !== 'undefined' ? Api.baseUrl : '') + '/maintenance.html') },
        { key: 'j', description: 'Next row in table', handler: () => navigateTable(1) },
        { key: 'k', description: 'Previous row in table', handler: () => navigateTable(-1) },
        { key: 'Enter', description: 'Open selected row', handler: handleEnter },
        { key: 'Ctrl+s', description: 'Save (in editors)', handler: handleSave, preventDefault: true }
    ];

    let pendingKey = null;
    let pendingTimeout = null;

    /**
     * Initialize shortcuts
     */
    function init() {
        // Register default shortcuts
        defaultShortcuts.forEach(s => register(s.key, s.handler, s));

        // Listen for keydown
        document.addEventListener('keydown', handleKeyDown);

        console.log('[Shortcuts] Initialized with', shortcuts.size, 'shortcuts');
    }

    /**
     * Register a shortcut
     * @param {string} key - Key combination (e.g., 'g h', 'Ctrl+s', '?')
     * @param {Function} handler - Handler function
     * @param {Object} options - Additional options
     */
    function register(key, handler, options = {}) {
        shortcuts.set(key.toLowerCase(), {
            key,
            handler,
            description: options.description || '',
            preventDefault: options.preventDefault || false,
            scope: options.scope || 'global'
        });
    }

    /**
     * Unregister a shortcut
     */
    function unregister(key) {
        shortcuts.delete(key.toLowerCase());
    }

    /**
     * Handle keydown event
     */
    function handleKeyDown(e) {
        if (!enabled) return;

        // Ignore if typing in input/textarea
        const target = e.target;
        if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable) {
            // Allow Escape and some special keys
            if (e.key !== 'Escape') return;
        }

        const keyCombo = getKeyCombo(e);
        
        // Handle two-key sequences (e.g., 'g h')
        if (pendingKey) {
            const fullKey = `${pendingKey} ${keyCombo}`.toLowerCase();
            clearTimeout(pendingTimeout);
            pendingKey = null;

            const shortcut = shortcuts.get(fullKey);
            if (shortcut) {
                if (shortcut.preventDefault) e.preventDefault();
                shortcut.handler(e);
                return;
            }
        }

        // Check for single key shortcut
        const shortcut = shortcuts.get(keyCombo.toLowerCase());
        if (shortcut) {
            if (shortcut.preventDefault) e.preventDefault();
            shortcut.handler(e);
            return;
        }

        // Check if this could be start of a sequence
        const isSequenceStart = Array.from(shortcuts.keys()).some(k => k.startsWith(keyCombo.toLowerCase() + ' '));
        if (isSequenceStart) {
            pendingKey = keyCombo;
            pendingTimeout = setTimeout(() => {
                pendingKey = null;
            }, 1000);
        }
    }

    /**
     * Get key combination string from event
     */
    function getKeyCombo(e) {
        const parts = [];
        if (e.ctrlKey || e.metaKey) parts.push('Ctrl');
        if (e.altKey) parts.push('Alt');
        if (e.shiftKey && e.key.length > 1) parts.push('Shift');
        
        let key = e.key;
        if (key === ' ') key = 'Space';
        
        parts.push(key);
        return parts.join('+');
    }

    /**
     * Show help modal
     */
    function showHelp() {
        if (helpModalShowing) return;
        helpModalShowing = true;

        const categories = {
            'Navigation': [],
            'Actions': [],
            'Table': [],
            'Other': []
        };

        shortcuts.forEach((shortcut) => {
            if (shortcut.key.startsWith('g ')) {
                categories['Navigation'].push(shortcut);
            } else if (['j', 'k', 'Enter'].includes(shortcut.key)) {
                categories['Table'].push(shortcut);
            } else if (['r', '/', 'Ctrl+s'].includes(shortcut.key)) {
                categories['Actions'].push(shortcut);
            } else {
                categories['Other'].push(shortcut);
            }
        });

        const content = document.createElement('div');
        content.className = 'shortcuts-help';
        content.innerHTML = Object.entries(categories)
            .filter(([_, shortcuts]) => shortcuts.length > 0)
            .map(([category, shortcuts]) => `
                <div class="shortcut-category">
                    <h4 style="margin: 1rem 0 0.5rem; color: var(--accent-color);">${category}</h4>
                    <div class="shortcut-list">
                        ${shortcuts.map(s => `
                            <div class="shortcut-item" style="display: flex; justify-content: space-between; padding: 0.4rem 0; border-bottom: 1px solid var(--border-color);">
                                <span class="shortcut-desc">${escapeHtml(s.description)}</span>
                                <kbd class="shortcut-key" style="background: var(--bg-secondary); padding: 0.2rem 0.5rem; border-radius: 4px; font-family: monospace;">${escapeHtml(s.key)}</kbd>
                            </div>
                        `).join('')}
                    </div>
                </div>
            `).join('');

        if (typeof Modal !== 'undefined') {
            Modal.show({
                title: 'Keyboard Shortcuts',
                content: content,
                size: 'md',
                onClose: () => { helpModalShowing = false; }
            });
        } else {
            // Fallback
            const overlay = document.createElement('div');
            overlay.className = 'modal-overlay active';
            overlay.innerHTML = `
                <div class="modal" style="max-width: 500px;">
                    <div class="modal-header">
                        <h3>Keyboard Shortcuts</h3>
                        <button class="modal-close">&times;</button>
                    </div>
                    <div class="modal-body"></div>
                </div>
            `;
            overlay.querySelector('.modal-body').appendChild(content);
            overlay.querySelector('.modal-close').addEventListener('click', () => {
                overlay.remove();
                helpModalShowing = false;
            });
            overlay.addEventListener('click', (e) => {
                if (e.target === overlay) {
                    overlay.remove();
                    helpModalShowing = false;
                }
            });
            document.body.appendChild(overlay);
        }
    }

    /**
     * Handle Escape key
     */
    function handleEscape() {
        if (typeof Modal !== 'undefined') {
            Modal.closeTop();
        }
        // Close any open dropdowns, menus, etc.
        document.querySelectorAll('.dropdown.open, .menu.open').forEach(el => el.classList.remove('open'));
    }

    /**
     * Handle refresh
     */
    function handleRefresh() {
        const refreshBtn = document.querySelector('#refreshBtn, [data-action="refresh"], .btn-refresh');
        if (refreshBtn) {
            refreshBtn.click();
        } else if (typeof loadData === 'function') {
            loadData();
        }
    }

    /**
     * Handle search focus
     */
    function handleSearch(e) {
        e.preventDefault();
        const searchInput = document.querySelector('#searchInput, #messageSearch, [type="search"], input[name="search"]');
        if (searchInput) {
            searchInput.focus();
            searchInput.select();
        }
    }

    /**
     * Navigate to URL
     */
    function navigate(url) {
        window.location.href = url;
    }

    /**
     * Navigate table rows
     */
    function navigateTable(direction) {
        const table = document.querySelector('table.data-table, .log-table, #logsTable');
        if (!table) return;

        const rows = table.querySelectorAll('tbody tr');
        if (rows.length === 0) return;

        let currentIndex = Array.from(rows).findIndex(r => r.classList.contains('selected'));
        let newIndex = currentIndex + direction;

        if (newIndex < 0) newIndex = 0;
        if (newIndex >= rows.length) newIndex = rows.length - 1;

        rows.forEach(r => r.classList.remove('selected'));
        rows[newIndex].classList.add('selected');
        rows[newIndex].scrollIntoView({ block: 'nearest' });
    }

    /**
     * Handle Enter on selected row
     */
    function handleEnter() {
        const selectedRow = document.querySelector('tr.selected');
        if (selectedRow) {
            selectedRow.click();
        }
    }

    /**
     * Handle Save
     */
    function handleSave(e) {
        const saveBtn = document.querySelector('#saveBtn, [data-action="save"], .btn-save');
        if (saveBtn) {
            e.preventDefault();
            saveBtn.click();
        }
    }

    /**
     * Enable/disable shortcuts
     */
    function setEnabled(value) {
        enabled = value;
    }

    /**
     * Escape HTML
     */
    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    // Public API
    return {
        init,
        register,
        unregister,
        showHelp,
        setEnabled
    };
})();

// Auto-initialize when DOM ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', Shortcuts.init);
} else {
    Shortcuts.init();
}

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = Shortcuts;
}
