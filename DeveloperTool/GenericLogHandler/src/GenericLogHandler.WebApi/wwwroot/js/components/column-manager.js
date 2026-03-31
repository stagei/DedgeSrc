/**
 * Column Manager - Visibility toggle and column reordering for tables
 * Stores preferences in localStorage per table
 */
const ColumnManager = (function() {
    'use strict';

    const STORAGE_PREFIX = 'loghandler-columns-';
    const instances = new Map();

    /**
     * Initialize column manager for a table
     * @param {string} tableId - Table element ID
     * @param {Object} options - Configuration options
     */
    function init(tableId, options = {}) {
        const table = document.getElementById(tableId);
        if (!table) {
            console.warn(`[ColumnManager] Table not found: ${tableId}`);
            return null;
        }

        const config = {
            storageKey: STORAGE_PREFIX + tableId,
            allowReorder: options.allowReorder !== false,
            allowHide: options.allowHide !== false,
            columns: options.columns || detectColumns(table),
            onColumnChange: options.onColumnChange || null,
            toggleButtonId: options.toggleButtonId || null
        };

        // Load saved preferences
        const savedState = loadState(config.storageKey);
        if (savedState) {
            config.columns = mergeColumnsState(config.columns, savedState);
        }

        const instance = {
            tableId,
            config,
            table
        };

        instances.set(tableId, instance);

        // Apply initial state
        applyColumnState(instance);

        // Setup toggle button if specified
        if (config.toggleButtonId) {
            setupToggleButton(instance, config.toggleButtonId);
        }

        return {
            show: (columnId) => showColumn(instance, columnId),
            hide: (columnId) => hideColumn(instance, columnId),
            toggle: (columnId) => toggleColumn(instance, columnId),
            isVisible: (columnId) => isColumnVisible(instance, columnId),
            getColumns: () => [...instance.config.columns],
            reset: () => resetColumns(instance),
            showManager: () => showManagerModal(instance)
        };
    }

    /**
     * Detect columns from table headers
     */
    function detectColumns(table) {
        const headers = table.querySelectorAll('thead th, thead td');
        return Array.from(headers).map((th, index) => ({
            id: th.dataset.columnId || `col-${index}`,
            name: th.textContent.trim(),
            visible: true,
            index: index
        }));
    }

    /**
     * Merge saved state with current columns
     */
    function mergeColumnsState(columns, savedState) {
        return columns.map(col => {
            const saved = savedState.find(s => s.id === col.id);
            if (saved) {
                return { ...col, visible: saved.visible, index: saved.index ?? col.index };
            }
            return col;
        }).sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
    }

    /**
     * Apply column visibility to table
     */
    function applyColumnState(instance) {
        const { table, config } = instance;
        
        config.columns.forEach((col, idx) => {
            const cells = table.querySelectorAll(`th:nth-child(${col.index + 1}), td:nth-child(${col.index + 1})`);
            cells.forEach(cell => {
                cell.style.display = col.visible ? '' : 'none';
            });
        });
    }

    /**
     * Show a column
     */
    function showColumn(instance, columnId) {
        const col = instance.config.columns.find(c => c.id === columnId);
        if (col) {
            col.visible = true;
            applyColumnState(instance);
            saveState(instance);
            if (instance.config.onColumnChange) {
                instance.config.onColumnChange(instance.config.columns);
            }
        }
    }

    /**
     * Hide a column
     */
    function hideColumn(instance, columnId) {
        const col = instance.config.columns.find(c => c.id === columnId);
        if (col) {
            col.visible = false;
            applyColumnState(instance);
            saveState(instance);
            if (instance.config.onColumnChange) {
                instance.config.onColumnChange(instance.config.columns);
            }
        }
    }

    /**
     * Toggle column visibility
     */
    function toggleColumn(instance, columnId) {
        const col = instance.config.columns.find(c => c.id === columnId);
        if (col) {
            col.visible = !col.visible;
            applyColumnState(instance);
            saveState(instance);
            if (instance.config.onColumnChange) {
                instance.config.onColumnChange(instance.config.columns);
            }
        }
    }

    /**
     * Check if column is visible
     */
    function isColumnVisible(instance, columnId) {
        const col = instance.config.columns.find(c => c.id === columnId);
        return col ? col.visible : false;
    }

    /**
     * Reset columns to default
     */
    function resetColumns(instance) {
        instance.config.columns.forEach((col, idx) => {
            col.visible = true;
            col.index = idx;
        });
        localStorage.removeItem(instance.config.storageKey);
        applyColumnState(instance);
    }

    /**
     * Save state to localStorage
     */
    function saveState(instance) {
        const state = instance.config.columns.map(c => ({
            id: c.id,
            visible: c.visible,
            index: c.index
        }));
        try {
            localStorage.setItem(instance.config.storageKey, JSON.stringify(state));
        } catch (e) {
            console.warn('[ColumnManager] Failed to save state:', e);
        }
    }

    /**
     * Load state from localStorage
     */
    function loadState(storageKey) {
        try {
            const saved = localStorage.getItem(storageKey);
            return saved ? JSON.parse(saved) : null;
        } catch (e) {
            console.warn('[ColumnManager] Failed to load state:', e);
            return null;
        }
    }

    /**
     * Setup toggle button to show column manager
     */
    function setupToggleButton(instance, buttonId) {
        const btn = document.getElementById(buttonId);
        if (btn) {
            btn.addEventListener('click', () => showManagerModal(instance));
        }
    }

    /**
     * Show column manager modal
     */
    function showManagerModal(instance) {
        const columns = instance.config.columns;
        
        const content = document.createElement('div');
        content.className = 'column-manager-content';
        content.innerHTML = `
            <p style="margin-bottom: 1rem; color: var(--text-secondary);">
                Toggle column visibility. Changes are saved automatically.
            </p>
            <div class="column-list" style="max-height: 400px; overflow-y: auto;">
                ${columns.map(col => `
                    <label class="column-item" style="display: flex; align-items: center; padding: 0.5rem; cursor: pointer; border-bottom: 1px solid var(--border-color);">
                        <input type="checkbox" data-column-id="${col.id}" ${col.visible ? 'checked' : ''} 
                            style="margin-right: 0.75rem; width: 18px; height: 18px;">
                        <span>${escapeHtml(col.name)}</span>
                    </label>
                `).join('')}
            </div>
            <div style="margin-top: 1rem; display: flex; gap: 0.5rem; justify-content: flex-end;">
                <button type="button" class="btn btn-secondary" id="colMgrReset">Reset to Default</button>
            </div>
        `;

        // Add event listeners
        content.querySelectorAll('input[type="checkbox"]').forEach(cb => {
            cb.addEventListener('change', function() {
                toggleColumn(instance, this.dataset.columnId);
            });
        });

        content.querySelector('#colMgrReset').addEventListener('click', function() {
            resetColumns(instance);
            // Update checkboxes
            content.querySelectorAll('input[type="checkbox"]').forEach(cb => {
                cb.checked = true;
            });
            if (typeof Toast !== 'undefined') {
                Toast.info('Columns reset to default');
            }
        });

        // Show modal
        if (typeof Modal !== 'undefined') {
            Modal.show({
                title: 'Manage Columns',
                content: content,
                size: 'sm'
            });
        } else {
            // Fallback: create simple modal
            const overlay = document.createElement('div');
            overlay.className = 'modal-overlay active';
            overlay.innerHTML = `
                <div class="modal" style="max-width: 400px;">
                    <div class="modal-header">
                        <h3>Manage Columns</h3>
                        <button class="modal-close">&times;</button>
                    </div>
                    <div class="modal-body"></div>
                </div>
            `;
            overlay.querySelector('.modal-body').appendChild(content);
            overlay.querySelector('.modal-close').addEventListener('click', () => overlay.remove());
            overlay.addEventListener('click', (e) => {
                if (e.target === overlay) overlay.remove();
            });
            document.body.appendChild(overlay);
        }
    }

    /**
     * Escape HTML to prevent XSS
     */
    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    /**
     * Get instance by table ID
     */
    function getInstance(tableId) {
        return instances.get(tableId);
    }

    // Public API
    return {
        init,
        getInstance
    };
})();

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = ColumnManager;
}
