/**
 * Table Component - Sortable, filterable data tables
 * Provides client-side sorting and filtering for data tables
 */
const DataTable = (function() {
    const tables = new Map();

    /**
     * Initialize a data table
     * @param {string} tableId - Table element ID
     * @param {Object} options - Configuration options
     */
    function init(tableId, options = {}) {
        const table = document.getElementById(tableId);
        if (!table) return null;

        const config = {
            sortable: true,
            filterable: false,
            selectable: false,
            pageSize: 50,
            onSort: null,
            onSelect: null,
            onRowClick: null,
            ...options
        };

        const state = {
            sortColumn: null,
            sortDirection: 'asc',
            selectedRows: new Set(),
            data: []
        };

        tables.set(tableId, { table, config, state });

        // Setup sortable headers
        if (config.sortable) {
            setupSorting(tableId);
        }

        // Setup row selection
        if (config.selectable) {
            setupSelection(tableId);
        }

        // Setup row click
        if (config.onRowClick) {
            setupRowClick(tableId);
        }

        return {
            sort: (column, direction) => sort(tableId, column, direction),
            getSelected: () => getSelected(tableId),
            clearSelection: () => clearSelection(tableId),
            selectAll: () => selectAll(tableId),
            refresh: () => refresh(tableId)
        };
    }

    /**
     * Setup sortable column headers
     */
    function setupSorting(tableId) {
        const { table, config, state } = tables.get(tableId);
        const headers = table.querySelectorAll('th[data-sortable]');

        headers.forEach(th => {
            th.style.cursor = 'pointer';
            th.classList.add('sortable-header');
            
            // Add sort indicator
            const indicator = document.createElement('span');
            indicator.className = 'sort-indicator';
            indicator.innerHTML = ' ↕';
            th.appendChild(indicator);

            th.addEventListener('click', () => {
                const column = th.dataset.column || th.cellIndex;
                const newDirection = state.sortColumn === column && state.sortDirection === 'asc' ? 'desc' : 'asc';
                sort(tableId, column, newDirection);
            });
        });
    }

    /**
     * Sort table by column
     */
    function sort(tableId, column, direction = 'asc') {
        const { table, config, state } = tables.get(tableId);
        
        state.sortColumn = column;
        state.sortDirection = direction;

        // Update header indicators
        table.querySelectorAll('th .sort-indicator').forEach(ind => {
            ind.innerHTML = ' ↕';
            ind.parentElement.classList.remove('sort-asc', 'sort-desc');
        });

        const header = table.querySelector(`th[data-column="${column}"]`) || 
                       table.querySelectorAll('th')[column];
        if (header) {
            const indicator = header.querySelector('.sort-indicator');
            if (indicator) {
                indicator.innerHTML = direction === 'asc' ? ' ↑' : ' ↓';
            }
            header.classList.add(`sort-${direction}`);
        }

        // If callback provided, let caller handle sorting (server-side)
        if (config.onSort) {
            config.onSort(column, direction);
            return;
        }

        // Client-side sorting
        const tbody = table.querySelector('tbody');
        if (!tbody) return;

        const rows = Array.from(tbody.querySelectorAll('tr'));
        const columnIndex = typeof column === 'number' ? column : 
            Array.from(table.querySelectorAll('th')).findIndex(th => th.dataset.column === column);

        rows.sort((a, b) => {
            const aCell = a.cells[columnIndex];
            const bCell = b.cells[columnIndex];
            if (!aCell || !bCell) return 0;

            let aVal = aCell.dataset.sortValue || aCell.textContent.trim();
            let bVal = bCell.dataset.sortValue || bCell.textContent.trim();

            // Try numeric comparison
            const aNum = parseFloat(aVal);
            const bNum = parseFloat(bVal);
            if (!isNaN(aNum) && !isNaN(bNum)) {
                return direction === 'asc' ? aNum - bNum : bNum - aNum;
            }

            // Try date comparison
            const aDate = Date.parse(aVal);
            const bDate = Date.parse(bVal);
            if (!isNaN(aDate) && !isNaN(bDate)) {
                return direction === 'asc' ? aDate - bDate : bDate - aDate;
            }

            // String comparison
            return direction === 'asc' 
                ? aVal.localeCompare(bVal) 
                : bVal.localeCompare(aVal);
        });

        // Re-append rows in sorted order
        rows.forEach(row => tbody.appendChild(row));
    }

    /**
     * Setup row selection with checkboxes
     */
    function setupSelection(tableId) {
        const { table, config, state } = tables.get(tableId);
        
        // Add select-all checkbox to header
        const headerRow = table.querySelector('thead tr');
        if (headerRow) {
            const selectAllTh = document.createElement('th');
            selectAllTh.innerHTML = '<input type="checkbox" class="select-all-checkbox" aria-label="Select all">';
            headerRow.insertBefore(selectAllTh, headerRow.firstChild);

            selectAllTh.querySelector('input').addEventListener('change', (e) => {
                if (e.target.checked) {
                    selectAll(tableId);
                } else {
                    clearSelection(tableId);
                }
            });
        }

        // Add checkboxes to each row
        table.querySelectorAll('tbody tr').forEach(row => {
            addRowCheckbox(row, tableId);
        });
    }

    /**
     * Add checkbox to a table row
     */
    function addRowCheckbox(row, tableId) {
        const { config, state } = tables.get(tableId);
        
        const checkboxTd = document.createElement('td');
        checkboxTd.innerHTML = '<input type="checkbox" class="row-checkbox" aria-label="Select row">';
        row.insertBefore(checkboxTd, row.firstChild);

        const checkbox = checkboxTd.querySelector('input');
        const rowId = row.dataset.id || row.rowIndex;

        checkbox.addEventListener('change', (e) => {
            if (e.target.checked) {
                state.selectedRows.add(rowId);
                row.classList.add('row-selected');
            } else {
                state.selectedRows.delete(rowId);
                row.classList.remove('row-selected');
            }

            if (config.onSelect) {
                config.onSelect(Array.from(state.selectedRows));
            }
        });
    }

    /**
     * Setup row click handler
     */
    function setupRowClick(tableId) {
        const { table, config } = tables.get(tableId);

        table.addEventListener('click', (e) => {
            const row = e.target.closest('tr');
            if (!row || row.parentElement.tagName === 'THEAD') return;
            if (e.target.type === 'checkbox') return; // Don't trigger on checkbox clicks

            const rowData = getRowData(row);
            config.onRowClick(rowData, row);
        });
    }

    /**
     * Get data from a row
     */
    function getRowData(row) {
        const data = {};
        if (row.dataset.entry) {
            try {
                return JSON.parse(row.dataset.entry);
            } catch {}
        }
        
        // Fall back to cell content
        Array.from(row.cells).forEach((cell, i) => {
            data[`col${i}`] = cell.textContent.trim();
        });
        data.id = row.dataset.id;
        return data;
    }

    /**
     * Get selected row IDs
     */
    function getSelected(tableId) {
        const { state } = tables.get(tableId);
        return Array.from(state.selectedRows);
    }

    /**
     * Clear all selections
     */
    function clearSelection(tableId) {
        const { table, state, config } = tables.get(tableId);
        state.selectedRows.clear();
        
        table.querySelectorAll('.row-checkbox').forEach(cb => cb.checked = false);
        table.querySelectorAll('tbody tr').forEach(row => row.classList.remove('row-selected'));
        
        const selectAll = table.querySelector('.select-all-checkbox');
        if (selectAll) selectAll.checked = false;

        if (config.onSelect) config.onSelect([]);
    }

    /**
     * Select all rows
     */
    function selectAll(tableId) {
        const { table, state, config } = tables.get(tableId);
        
        table.querySelectorAll('tbody tr').forEach(row => {
            const rowId = row.dataset.id || row.rowIndex;
            state.selectedRows.add(rowId);
            row.classList.add('row-selected');
            const checkbox = row.querySelector('.row-checkbox');
            if (checkbox) checkbox.checked = true;
        });

        const selectAll = table.querySelector('.select-all-checkbox');
        if (selectAll) selectAll.checked = true;

        if (config.onSelect) config.onSelect(Array.from(state.selectedRows));
    }

    /**
     * Refresh table (re-apply selection to new rows)
     */
    function refresh(tableId) {
        const tableData = tables.get(tableId);
        if (!tableData) return;

        const { table, config, state } = tableData;

        // Re-add checkboxes to new rows if selectable
        if (config.selectable) {
            table.querySelectorAll('tbody tr').forEach(row => {
                if (!row.querySelector('.row-checkbox')) {
                    addRowCheckbox(row, tableId);
                }
            });
        }
    }

    return {
        init,
        sort,
        getSelected,
        clearSelection,
        selectAll,
        refresh
    };
})();
