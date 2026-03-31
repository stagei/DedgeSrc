/**
 * Search Enhancements - Date presets, search history, and additional search features
 */
const SearchEnhancements = (function() {
    'use strict';

    const HISTORY_KEY = 'loghandler-search-history';
    const MAX_HISTORY = 10;

    /**
     * Date preset configurations
     */
    const datePresets = {
        'last-hour': {
            label: 'Last Hour',
            getRange: () => ({
                from: new Date(Date.now() - 60 * 60 * 1000),
                to: new Date()
            })
        },
        'last-24h': {
            label: 'Last 24 Hours',
            getRange: () => ({
                from: new Date(Date.now() - 24 * 60 * 60 * 1000),
                to: new Date()
            })
        },
        'today': {
            label: 'Today',
            getRange: () => {
                const now = new Date();
                const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
                return { from: start, to: now };
            }
        },
        'yesterday': {
            label: 'Yesterday',
            getRange: () => {
                const now = new Date();
                const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
                const end = new Date(now.getFullYear(), now.getMonth(), now.getDate());
                return { from: start, to: end };
            }
        },
        'this-week': {
            label: 'This Week',
            getRange: () => {
                const now = new Date();
                const day = now.getDay();
                const diff = now.getDate() - day + (day === 0 ? -6 : 1);
                const start = new Date(now.setDate(diff));
                start.setHours(0, 0, 0, 0);
                return { from: start, to: new Date() };
            }
        },
        'last-7-days': {
            label: 'Last 7 Days',
            getRange: () => ({
                from: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
                to: new Date()
            })
        },
        'this-month': {
            label: 'This Month',
            getRange: () => {
                const now = new Date();
                const start = new Date(now.getFullYear(), now.getMonth(), 1);
                return { from: start, to: now };
            }
        },
        'last-30-days': {
            label: 'Last 30 Days',
            getRange: () => ({
                from: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000),
                to: new Date()
            })
        }
    };

    /**
     * Initialize date presets for a form
     * @param {Object} options - Configuration
     */
    function initDatePresets(options = {}) {
        const {
            containerId,
            fromInputId = 'fromDate',
            toInputId = 'toDate',
            presets = ['last-hour', 'last-24h', 'last-7-days', 'last-30-days'],
            onPresetSelected = null
        } = options;

        const container = document.getElementById(containerId);
        if (!container) return;

        const buttonsHtml = presets.map(key => {
            const preset = datePresets[key];
            if (!preset) return '';
            return `<button type="button" class="btn btn-sm btn-secondary date-preset" data-preset="${key}">${preset.label}</button>`;
        }).join('');

        container.innerHTML = buttonsHtml;

        container.addEventListener('click', function(e) {
            const btn = e.target.closest('.date-preset');
            if (!btn) return;

            const presetKey = btn.dataset.preset;
            const preset = datePresets[presetKey];
            if (!preset) return;

            const range = preset.getRange();
            
            const fromInput = document.getElementById(fromInputId);
            const toInput = document.getElementById(toInputId);

            if (fromInput) {
                fromInput.value = formatDateTimeLocal(range.from);
            }
            if (toInput) {
                toInput.value = formatDateTimeLocal(range.to);
            }

            // Update active state
            container.querySelectorAll('.date-preset').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');

            if (onPresetSelected) {
                onPresetSelected(presetKey, range);
            }
        });
    }

    /**
     * Format date for datetime-local input
     */
    function formatDateTimeLocal(date) {
        const pad = n => n.toString().padStart(2, '0');
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
    }

    /**
     * Initialize search history
     * @param {Object} options - Configuration
     */
    function initSearchHistory(options = {}) {
        const {
            inputId,
            historyContainerId,
            onHistorySelect = null
        } = options;

        const input = document.getElementById(inputId);
        const container = document.getElementById(historyContainerId);
        
        if (!input) return;

        // Create dropdown if container doesn't exist
        let dropdown = container;
        if (!dropdown) {
            dropdown = document.createElement('div');
            dropdown.id = historyContainerId || 'searchHistory';
            dropdown.className = 'search-history-dropdown';
            dropdown.style.cssText = 'display: none; position: absolute; background: var(--bg-primary); border: 1px solid var(--border-color); border-radius: 4px; max-height: 200px; overflow-y: auto; z-index: 1000; width: 100%;';
            input.parentElement.style.position = 'relative';
            input.parentElement.appendChild(dropdown);
        }

        // Show history on focus
        input.addEventListener('focus', () => showHistory(dropdown));
        input.addEventListener('blur', () => {
            setTimeout(() => hideHistory(dropdown), 200);
        });

        // Handle history item click
        dropdown.addEventListener('click', function(e) {
            const item = e.target.closest('.history-item');
            if (!item) return;

            const value = item.dataset.value;
            input.value = value;
            hideHistory(dropdown);

            if (onHistorySelect) {
                onHistorySelect(value);
            }
        });

        function showHistory(dropdown) {
            const history = getHistory();
            if (history.length === 0) {
                dropdown.style.display = 'none';
                return;
            }

            dropdown.innerHTML = history.map(item => 
                `<div class="history-item" data-value="${escapeHtml(item)}" 
                     style="padding: 0.5rem; cursor: pointer; border-bottom: 1px solid var(--border-color);">
                    ${escapeHtml(truncate(item, 50))}
                </div>`
            ).join('');
            dropdown.style.display = 'block';
        }

        function hideHistory(dropdown) {
            dropdown.style.display = 'none';
        }
    }

    /**
     * Add a search term to history
     */
    function addToHistory(searchTerm) {
        if (!searchTerm || searchTerm.trim().length === 0) return;

        let history = getHistory();
        
        // Remove if already exists
        history = history.filter(h => h !== searchTerm);
        
        // Add to front
        history.unshift(searchTerm);
        
        // Limit size
        history = history.slice(0, MAX_HISTORY);
        
        try {
            localStorage.setItem(HISTORY_KEY, JSON.stringify(history));
        } catch (e) {
            console.warn('[SearchHistory] Failed to save:', e);
        }
    }

    /**
     * Get search history
     */
    function getHistory() {
        try {
            const saved = localStorage.getItem(HISTORY_KEY);
            return saved ? JSON.parse(saved) : [];
        } catch (e) {
            return [];
        }
    }

    /**
     * Clear search history
     */
    function clearHistory() {
        localStorage.removeItem(HISTORY_KEY);
    }

    /**
     * Create case-insensitive toggle
     * @param {Object} options - Configuration
     */
    function createCaseToggle(options = {}) {
        const {
            containerId,
            initialValue = true,
            onChange = null
        } = options;

        const container = document.getElementById(containerId);
        if (!container) return null;

        let caseInsensitive = initialValue;

        container.innerHTML = `
            <label class="toggle-label" style="display: flex; align-items: center; gap: 0.5rem; cursor: pointer;">
                <input type="checkbox" id="caseInsensitiveToggle" ${caseInsensitive ? 'checked' : ''}>
                <span>Case Insensitive</span>
            </label>
        `;

        const checkbox = container.querySelector('#caseInsensitiveToggle');
        checkbox.addEventListener('change', function() {
            caseInsensitive = this.checked;
            if (onChange) {
                onChange(caseInsensitive);
            }
        });

        return {
            getValue: () => caseInsensitive,
            setValue: (val) => {
                caseInsensitive = val;
                checkbox.checked = val;
            }
        };
    }

    /**
     * Escape HTML
     */
    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    /**
     * Truncate text
     */
    function truncate(text, maxLen) {
        if (!text || text.length <= maxLen) return text;
        return text.substring(0, maxLen) + '...';
    }

    // Public API
    return {
        initDatePresets,
        initSearchHistory,
        addToHistory,
        getHistory,
        clearHistory,
        createCaseToggle,
        datePresets
    };
})();

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = SearchEnhancements;
}
