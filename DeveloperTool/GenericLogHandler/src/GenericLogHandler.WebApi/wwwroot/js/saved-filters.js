/**
 * Saved Filters Maintenance Page JavaScript
 * Displays and manages saved search filters
 */
(function() {
    'use strict';

    /**
     * Initialize page
     */
    function init() {
        loadFilters();
    }

    /**
     * Escape HTML
     */
    function escapeHtml(s) {
        if (s == null) return '';
        const div = document.createElement('div');
        div.textContent = s;
        return div.innerHTML;
    }

    /**
     * Format date
     */
    function formatDate(d) {
        if (!d) return '-';
        const date = typeof d === 'string' ? new Date(d) : d;
        return isNaN(date.getTime()) ? '-' : date.toLocaleString();
    }

    /**
     * Load saved filters
     */
    async function loadFilters() {
        const tbody = document.getElementById('filtersBody');
        const empty = document.getElementById('filtersEmpty');
        const errEl = document.getElementById('filtersError');
        
        empty.classList.add('hidden');
        errEl.classList.add('hidden');
        tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;padding:2rem;">Loading...</td></tr>';
        
        try {
            const response = await Api.get('/api/filters');
            if (!response.Success) {
                errEl.textContent = response.Error || 'Failed to load';
                errEl.classList.remove('hidden');
                tbody.innerHTML = '';
                return;
            }
            
            const items = response.Data || [];
            if (items.length === 0) {
                tbody.innerHTML = '';
                empty.classList.remove('hidden');
                return;
            }
            
            tbody.innerHTML = items.map(row => {
                const alertBadge = row.IsAlertEnabled 
                    ? '<span class="severity-badge warning">Alert</span>' 
                    : '-';
                return `
                    <tr data-id="${row.Id}">
                        <td>${escapeHtml(row.Name)}</td>
                        <td>${escapeHtml(row.Category || '-')}</td>
                        <td>${alertBadge}</td>
                        <td>${formatDate(row.CreatedAt)}</td>
                        <td>
                            <button class="btn btn-sm btn-outline btn-delete" 
                                    data-id="${row.Id}" 
                                    data-name="${escapeHtml(row.Name)}">Delete</button>
                        </td>
                    </tr>
                `;
            }).join('');
            
            // Add event listeners using event delegation
            tbody.addEventListener('click', handleTableClick);
            
        } catch (e) {
            errEl.textContent = 'Error: ' + e.message;
            errEl.classList.remove('hidden');
            tbody.innerHTML = '';
            Toast.error('Failed to load saved filters');
        }
    }

    /**
     * Handle table click events
     */
    function handleTableClick(e) {
        const deleteBtn = e.target.closest('.btn-delete');
        if (deleteBtn) {
            const id = deleteBtn.dataset.id;
            const name = deleteBtn.dataset.name;
            confirmDelete(id, name);
        }
    }

    /**
     * Confirm and delete filter
     */
    async function confirmDelete(id, name) {
        const confirmed = await Modal.confirm(
            `Delete filter "${name}"?`,
            { title: 'Confirm Delete', danger: true }
        );
        if (!confirmed) return;
        
        try {
            const response = await Api.delete('/api/filters/' + id);
            if (response.Success !== true) {
                Toast.error('Delete failed: ' + (response.Error || 'Unknown'));
                return;
            }
            Toast.success('Filter deleted successfully');
            loadFilters();
        } catch (e) {
            Toast.error('Error: ' + e.message);
        }
    }

    // Initialize on DOM ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
