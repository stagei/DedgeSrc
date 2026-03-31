/**
 * Virtual Scroll - Efficiently render large datasets by only rendering visible rows
 * Uses IntersectionObserver for scroll detection
 */
const VirtualScroll = (function() {
    'use strict';

    const instances = new Map();

    /**
     * Initialize virtual scrolling for a container
     * @param {string} containerId - Container element ID
     * @param {Object} options - Configuration options
     */
    function init(containerId, options = {}) {
        const container = document.getElementById(containerId);
        if (!container) {
            console.warn(`[VirtualScroll] Container not found: ${containerId}`);
            return null;
        }

        const config = {
            rowHeight: options.rowHeight || 40,
            bufferSize: options.bufferSize || 10,
            renderRow: options.renderRow || defaultRenderRow,
            onLoadMore: options.onLoadMore || null,
            threshold: options.threshold || 200, // pixels from bottom to trigger load more
            data: options.data || [],
            totalCount: options.totalCount || 0
        };

        // Create virtual scroll wrapper
        const wrapper = document.createElement('div');
        wrapper.className = 'virtual-scroll-wrapper';
        wrapper.style.cssText = `
            position: relative;
            overflow-y: auto;
            height: ${options.height || '500px'};
        `;

        // Create spacer for total height
        const spacer = document.createElement('div');
        spacer.className = 'virtual-scroll-spacer';
        spacer.style.cssText = `
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            pointer-events: none;
        `;

        // Create content container for visible rows
        const content = document.createElement('div');
        content.className = 'virtual-scroll-content';
        content.style.cssText = `
            position: relative;
        `;

        wrapper.appendChild(spacer);
        wrapper.appendChild(content);
        container.appendChild(wrapper);

        const instance = {
            containerId,
            container,
            wrapper,
            spacer,
            content,
            config,
            visibleStart: 0,
            visibleEnd: 0,
            lastScrollTop: 0,
            isLoading: false,
            rafId: null
        };

        instances.set(containerId, instance);

        // Setup scroll handler
        wrapper.addEventListener('scroll', () => handleScroll(instance), { passive: true });

        // Initial render
        updateSpacer(instance);
        render(instance);

        return {
            setData: (data, totalCount) => setData(instance, data, totalCount),
            scrollToIndex: (index) => scrollToIndex(instance, index),
            refresh: () => render(instance),
            destroy: () => destroy(instance)
        };
    }

    /**
     * Set data for virtual scroll
     */
    function setData(instance, data, totalCount) {
        instance.config.data = data;
        instance.config.totalCount = totalCount || data.length;
        updateSpacer(instance);
        render(instance);
    }

    /**
     * Update spacer height based on total count
     */
    function updateSpacer(instance) {
        const totalHeight = instance.config.totalCount * instance.config.rowHeight;
        instance.spacer.style.height = `${totalHeight}px`;
    }

    /**
     * Handle scroll event
     */
    function handleScroll(instance) {
        // Cancel any pending render
        if (instance.rafId) {
            cancelAnimationFrame(instance.rafId);
        }

        // Schedule render on next frame
        instance.rafId = requestAnimationFrame(() => {
            render(instance);
            checkLoadMore(instance);
        });
    }

    /**
     * Render visible rows
     */
    function render(instance) {
        const { wrapper, content, config } = instance;
        const scrollTop = wrapper.scrollTop;
        const viewportHeight = wrapper.clientHeight;

        // Calculate visible range
        const startIndex = Math.max(0, Math.floor(scrollTop / config.rowHeight) - config.bufferSize);
        const endIndex = Math.min(
            config.data.length,
            Math.ceil((scrollTop + viewportHeight) / config.rowHeight) + config.bufferSize
        );

        // Only re-render if range changed significantly
        if (startIndex === instance.visibleStart && endIndex === instance.visibleEnd) {
            return;
        }

        instance.visibleStart = startIndex;
        instance.visibleEnd = endIndex;

        // Build visible rows
        const fragment = document.createDocumentFragment();
        
        for (let i = startIndex; i < endIndex; i++) {
            const item = config.data[i];
            if (!item) continue;

            const row = config.renderRow(item, i);
            if (row) {
                row.style.position = 'absolute';
                row.style.top = `${i * config.rowHeight}px`;
                row.style.left = '0';
                row.style.right = '0';
                row.style.height = `${config.rowHeight}px`;
                fragment.appendChild(row);
            }
        }

        // Clear and append
        content.innerHTML = '';
        content.appendChild(fragment);
    }

    /**
     * Check if we need to load more data
     */
    function checkLoadMore(instance) {
        if (!instance.config.onLoadMore || instance.isLoading) return;

        const { wrapper, config } = instance;
        const scrollBottom = wrapper.scrollHeight - wrapper.scrollTop - wrapper.clientHeight;

        if (scrollBottom < config.threshold) {
            if (config.data.length < config.totalCount) {
                instance.isLoading = true;
                config.onLoadMore()
                    .then(() => {
                        instance.isLoading = false;
                    })
                    .catch(() => {
                        instance.isLoading = false;
                    });
            }
        }
    }

    /**
     * Scroll to a specific index
     */
    function scrollToIndex(instance, index) {
        const scrollTop = index * instance.config.rowHeight;
        instance.wrapper.scrollTop = scrollTop;
    }

    /**
     * Default row renderer
     */
    function defaultRenderRow(item, index) {
        const row = document.createElement('div');
        row.className = 'virtual-scroll-row';
        row.textContent = JSON.stringify(item);
        return row;
    }

    /**
     * Destroy virtual scroll instance
     */
    function destroy(instance) {
        if (instance.rafId) {
            cancelAnimationFrame(instance.rafId);
        }
        instance.wrapper.remove();
        instances.delete(instance.containerId);
    }

    /**
     * Get instance by container ID
     */
    function getInstance(containerId) {
        return instances.get(containerId);
    }

    // Public API
    return {
        init,
        getInstance
    };
})();

/**
 * Virtual Table - Extension for table-based virtual scrolling
 */
const VirtualTable = (function() {
    'use strict';

    /**
     * Initialize virtual table
     * @param {string} tableId - Table element ID
     * @param {Object} options - Configuration options
     */
    function init(tableId, options = {}) {
        const table = document.getElementById(tableId);
        if (!table) {
            console.warn(`[VirtualTable] Table not found: ${tableId}`);
            return null;
        }

        const config = {
            rowHeight: options.rowHeight || 40,
            bufferSize: options.bufferSize || 20,
            columns: options.columns || detectColumns(table),
            renderCell: options.renderCell || defaultRenderCell,
            onRowClick: options.onRowClick || null,
            onLoadMore: options.onLoadMore || null,
            height: options.height || '500px',
            data: [],
            totalCount: 0
        };

        // Get tbody and prepare for virtual scrolling
        const thead = table.querySelector('thead');
        const tbody = table.querySelector('tbody') || document.createElement('tbody');
        
        // Create wrapper around tbody
        const wrapper = document.createElement('div');
        wrapper.className = 'virtual-table-wrapper';
        wrapper.style.cssText = `
            overflow-y: auto;
            max-height: ${config.height};
        `;

        // Create spacer row for maintaining scroll height
        const spacer = document.createElement('tr');
        spacer.className = 'virtual-table-spacer';
        spacer.style.cssText = 'height: 0; visibility: hidden;';
        spacer.innerHTML = `<td colspan="${config.columns.length}"></td>`;

        tbody.innerHTML = '';
        tbody.appendChild(spacer);

        const instance = {
            tableId,
            table,
            thead,
            tbody,
            wrapper,
            spacer,
            config,
            visibleStart: 0,
            visibleEnd: 0,
            rafId: null,
            isLoading: false
        };

        // Wrap tbody in scrollable container
        table.parentNode.insertBefore(wrapper, table);
        wrapper.appendChild(table);

        // Setup scroll handler
        wrapper.addEventListener('scroll', () => handleScroll(instance), { passive: true });

        return {
            setData: (data, totalCount) => setData(instance, data, totalCount),
            refresh: () => render(instance),
            scrollToRow: (index) => scrollToRow(instance, index),
            destroy: () => destroy(instance)
        };
    }

    /**
     * Detect columns from table headers
     */
    function detectColumns(table) {
        const headers = table.querySelectorAll('thead th');
        return Array.from(headers).map((th, index) => ({
            key: th.dataset.key || `col${index}`,
            name: th.textContent.trim()
        }));
    }

    /**
     * Set data for virtual table
     */
    function setData(instance, data, totalCount) {
        instance.config.data = data;
        instance.config.totalCount = totalCount || data.length;
        updateSpacer(instance);
        render(instance);
    }

    /**
     * Update spacer height
     */
    function updateSpacer(instance) {
        const totalHeight = instance.config.totalCount * instance.config.rowHeight;
        instance.spacer.style.height = `${totalHeight}px`;
    }

    /**
     * Handle scroll event
     */
    function handleScroll(instance) {
        if (instance.rafId) {
            cancelAnimationFrame(instance.rafId);
        }
        instance.rafId = requestAnimationFrame(() => {
            render(instance);
            checkLoadMore(instance);
        });
    }

    /**
     * Render visible rows
     */
    function render(instance) {
        const { wrapper, tbody, spacer, config } = instance;
        const scrollTop = wrapper.scrollTop;
        const viewportHeight = wrapper.clientHeight;

        const startIndex = Math.max(0, Math.floor(scrollTop / config.rowHeight) - config.bufferSize);
        const endIndex = Math.min(
            config.data.length,
            Math.ceil((scrollTop + viewportHeight) / config.rowHeight) + config.bufferSize
        );

        if (startIndex === instance.visibleStart && endIndex === instance.visibleEnd) {
            return;
        }

        instance.visibleStart = startIndex;
        instance.visibleEnd = endIndex;

        // Clear tbody except spacer
        const rows = tbody.querySelectorAll('tr:not(.virtual-table-spacer)');
        rows.forEach(row => row.remove());

        // Add visible rows
        const fragment = document.createDocumentFragment();
        
        // Add top padding row
        if (startIndex > 0) {
            const topPadding = document.createElement('tr');
            topPadding.className = 'virtual-padding-top';
            topPadding.innerHTML = `<td colspan="${config.columns.length}" style="height: ${startIndex * config.rowHeight}px; padding: 0; border: none;"></td>`;
            fragment.appendChild(topPadding);
        }

        for (let i = startIndex; i < endIndex; i++) {
            const item = config.data[i];
            if (!item) continue;

            const row = document.createElement('tr');
            row.style.height = `${config.rowHeight}px`;
            row.dataset.index = i;

            config.columns.forEach(col => {
                const td = document.createElement('td');
                td.innerHTML = config.renderCell(item, col.key, i);
                row.appendChild(td);
            });

            if (config.onRowClick) {
                row.style.cursor = 'pointer';
                row.addEventListener('click', () => config.onRowClick(item, i));
            }

            fragment.appendChild(row);
        }

        // Add bottom padding row
        const bottomPadding = (config.totalCount - endIndex) * config.rowHeight;
        if (bottomPadding > 0) {
            const bottomRow = document.createElement('tr');
            bottomRow.className = 'virtual-padding-bottom';
            bottomRow.innerHTML = `<td colspan="${config.columns.length}" style="height: ${bottomPadding}px; padding: 0; border: none;"></td>`;
            fragment.appendChild(bottomRow);
        }

        // Insert after spacer
        tbody.insertBefore(fragment, spacer.nextSibling);
    }

    /**
     * Check if more data needs to be loaded
     */
    function checkLoadMore(instance) {
        if (!instance.config.onLoadMore || instance.isLoading) return;

        const { wrapper, config } = instance;
        const scrollBottom = wrapper.scrollHeight - wrapper.scrollTop - wrapper.clientHeight;

        if (scrollBottom < 200 && config.data.length < config.totalCount) {
            instance.isLoading = true;
            config.onLoadMore()
                .then(() => {
                    instance.isLoading = false;
                    render(instance);
                })
                .catch(() => {
                    instance.isLoading = false;
                });
        }
    }

    /**
     * Scroll to specific row
     */
    function scrollToRow(instance, index) {
        instance.wrapper.scrollTop = index * instance.config.rowHeight;
    }

    /**
     * Default cell renderer
     */
    function defaultRenderCell(item, key) {
        const value = item[key];
        if (value === null || value === undefined) return '';
        if (typeof value === 'object') return JSON.stringify(value);
        return String(value);
    }

    /**
     * Destroy virtual table
     */
    function destroy(instance) {
        if (instance.rafId) {
            cancelAnimationFrame(instance.rafId);
        }
        // Unwrap table
        const parent = instance.wrapper.parentNode;
        parent.insertBefore(instance.table, instance.wrapper);
        instance.wrapper.remove();
    }

    return {
        init,
        detectColumns
    };
})();

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { VirtualScroll, VirtualTable };
}
