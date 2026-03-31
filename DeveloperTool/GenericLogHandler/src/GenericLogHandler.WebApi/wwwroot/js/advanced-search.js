// Advanced Search JavaScript - Query Builder

const FIELDS = [
    { value: 'ComputerName', label: 'Computer Name', type: 'text' },
    { value: 'UserName', label: 'User Name', type: 'text' },
    { value: 'Level', label: 'Log Level', type: 'select', options: ['TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'] },
    { value: 'MessageText', label: 'Message', type: 'text' },
    { value: 'FunctionName', label: 'Function Name', type: 'text' },
    { value: 'SourceFile', label: 'Source File', type: 'text' },
    { value: 'SourceType', label: 'Source Type', type: 'text' },
    { value: 'ExceptionText', label: 'Exception', type: 'text' },
    { value: 'RegexPattern', label: 'Regex Pattern', type: 'text' },
    { value: 'FromDate', label: 'From Date', type: 'datetime' },
    { value: 'ToDate', label: 'To Date', type: 'datetime' },
    // Business identifiers (indexed fields)
    { value: 'Ordrenr', label: 'Order Number (ordrenr)', type: 'text' },
    { value: 'Avdnr', label: 'Department (avdnr)', type: 'text' },
    { value: 'JobName', label: 'Job Name', type: 'text' },
    { value: 'AlertId', label: 'Alert ID', type: 'text' }
];

const OPERATORS = [
    { value: 'equals', label: 'equals' },
    { value: 'contains', label: 'contains' },
    { value: 'startsWith', label: 'starts with' },
    { value: 'endsWith', label: 'ends with' },
    { value: 'regex', label: 'matches regex' },
    { value: 'gt', label: '>' },
    { value: 'lt', label: '<' },
    { value: 'gte', label: '>=' },
    { value: 'lte', label: '<=' }
];

let queryRows = [];
let rowIdCounter = 0;

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
    initTheme();
    initQueryBuilder();
    loadSavedFilters();
    setupEventListeners();
});

function initTheme() {
    const savedTheme = localStorage.getItem('loghandler-theme') || 'light';
    document.documentElement.setAttribute('data-theme', savedTheme);
    updateThemeIcon(savedTheme);

    document.getElementById('themeToggle')?.addEventListener('click', () => {
        const current = document.documentElement.getAttribute('data-theme');
        const next = current === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', next);
        localStorage.setItem('loghandler-theme', next);
        updateThemeIcon(next);
    });
}

function updateThemeIcon(theme) {
    const icon = document.querySelector('.theme-icon');
    if (icon) icon.textContent = theme === 'dark' ? '☀️' : '🌙';
}

function initQueryBuilder() {
    // Add initial row
    addQueryRow();
}

function setupEventListeners() {
    document.getElementById('addRowBtn')?.addEventListener('click', addQueryRow);
    document.getElementById('clearAllBtn')?.addEventListener('click', clearAllRows);
    document.getElementById('previewBtn')?.addEventListener('click', previewResults);
    document.getElementById('saveFilterBtn')?.addEventListener('click', showSaveModal);
    document.getElementById('exportJsonBtn')?.addEventListener('click', exportJson);
    document.getElementById('refreshFiltersBtn')?.addEventListener('click', loadSavedFilters);
    document.getElementById('cancelSaveBtn')?.addEventListener('click', hideSaveModal);
    document.getElementById('saveFilterForm')?.addEventListener('submit', saveFilter);

    // Close modal on background click
    document.getElementById('saveFilterModal')?.addEventListener('click', (e) => {
        if (e.target.id === 'saveFilterModal') hideSaveModal();
    });
}

function addQueryRow() {
    const rowId = rowIdCounter++;
    const row = {
        id: rowId,
        field: FIELDS[0].value,
        operator: 'contains',
        value: '',
        conjunction: 'AND'
    };
    queryRows.push(row);
    renderQueryRows();
}

function removeQueryRow(rowId) {
    queryRows = queryRows.filter(r => r.id !== rowId);
    if (queryRows.length === 0) addQueryRow();
    else renderQueryRows();
}

function clearAllRows() {
    queryRows = [];
    rowIdCounter = 0;
    addQueryRow();
}

function renderQueryRows() {
    const container = document.getElementById('queryRows');
    if (!container) return;

    container.innerHTML = queryRows.map((row, index) => `
        <div class="query-row" data-row-id="${row.id}">
            ${index > 0 ? `
                <select class="conjunction-select" data-field="conjunction" data-row-id="${row.id}">
                    <option value="AND" ${row.conjunction === 'AND' ? 'selected' : ''}>AND</option>
                    <option value="OR" ${row.conjunction === 'OR' ? 'selected' : ''}>OR</option>
                </select>
            ` : '<div style="width: 80px;"></div>'}
            <select class="field-select" data-field="field" data-row-id="${row.id}">
                ${FIELDS.map(f => `<option value="${f.value}" ${row.field === f.value ? 'selected' : ''}>${f.label}</option>`).join('')}
            </select>
            <select class="operator-select" data-field="operator" data-row-id="${row.id}">
                ${OPERATORS.map(o => `<option value="${o.value}" ${row.operator === o.value ? 'selected' : ''}>${o.label}</option>`).join('')}
            </select>
            ${renderValueInput(row)}
            <button class="remove-row-btn" onclick="removeQueryRow(${row.id})" title="Remove">×</button>
        </div>
    `).join('');

    // Add event listeners to inputs
    container.querySelectorAll('select, input').forEach(el => {
        el.addEventListener('change', (e) => {
            const rowId = parseInt(e.target.dataset.rowId);
            const field = e.target.dataset.field;
            const row = queryRows.find(r => r.id === rowId);
            if (row) {
                row[field] = e.target.value;
                if (field === 'field') renderQueryRows(); // Re-render if field type changes
            }
        });
    });
}

function renderValueInput(row) {
    const fieldDef = FIELDS.find(f => f.value === row.field);
    
    if (fieldDef?.type === 'select' && fieldDef.options) {
        return `
            <select class="value-input" data-field="value" data-row-id="${row.id}">
                ${fieldDef.options.map(o => `<option value="${o}" ${row.value === o ? 'selected' : ''}>${o}</option>`).join('')}
            </select>
        `;
    } else if (fieldDef?.type === 'datetime') {
        return `<input type="datetime-local" class="value-input" data-field="value" data-row-id="${row.id}" value="${row.value}">`;
    } else {
        return `<input type="text" class="value-input" data-field="value" data-row-id="${row.id}" value="${row.value}" placeholder="Enter value...">`;
    }
}

function buildFilterJson() {
    const filter = {
        Page: 1,
        PageSize: 50,
        SortBy: 'Timestamp',
        SortDescending: true
    };

    // Group by field and combine values
    const levels = [];
    
    for (const row of queryRows) {
        if (!row.value && row.field !== 'Level') continue;

        switch (row.field) {
            case 'FromDate':
                if (row.value) filter.FromDate = new Date(row.value).toISOString();
                break;
            case 'ToDate':
                if (row.value) filter.ToDate = new Date(row.value).toISOString();
                break;
            case 'Level':
                if (row.value) levels.push(row.value);
                break;
            case 'RegexPattern':
                filter.RegexPattern = row.value;
                break;
            case 'ComputerName':
                filter.ComputerName = row.value;
                break;
            case 'UserName':
                filter.UserName = row.value;
                break;
            case 'MessageText':
                filter.MessageText = row.value;
                break;
            case 'FunctionName':
                filter.FunctionName = row.value;
                break;
            case 'SourceFile':
                filter.SourceFile = row.value;
                break;
            case 'SourceType':
                filter.SourceType = row.value;
                break;
            case 'ExceptionText':
                filter.ExceptionText = row.value;
                break;
            case 'Ordrenr':
                filter.Ordrenr = row.value;
                break;
            case 'Avdnr':
                filter.Avdnr = row.value;
                break;
            case 'JobName':
                filter.JobName = row.value;
                break;
            case 'AlertId':
                filter.AlertId = row.value;
                break;
            default:
                // For unknown fields, add to message text search
                if (row.value) {
                    filter.MessageText = (filter.MessageText || '') + ' ' + row.value;
                }
        }
    }

    if (levels.length > 0) filter.Levels = levels;
    
    return filter;
}

async function previewResults() {
    const filterJson = JSON.stringify(buildFilterJson());
    showLoading(true);

    try {
        const response = await Api.post('/api/filters/preview', { FilterJson: filterJson, Limit: 10 });
        
        if (response.Success) {
            document.getElementById('previewCount').textContent = `${response.Data.TotalCount.toLocaleString()} matches`;
            renderPreviewResults(response.Data.SampleEntries);
        } else {
            alert('Error: ' + response.Error);
        }
    } catch (error) {
        console.error('Preview error:', error);
        alert('Error previewing results: ' + error.message);
    } finally {
        showLoading(false);
    }
}

function renderPreviewResults(entries) {
    const tbody = document.getElementById('previewBody');
    if (!tbody) return;

    if (!entries || entries.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4" class="empty-state">No matching entries found</td></tr>';
        return;
    }

    tbody.innerHTML = entries.map(entry => `
        <tr>
            <td>${formatDate(entry.Timestamp)}</td>
            <td><span class="level-badge level-${entry.Level.toLowerCase()}">${entry.Level}</span></td>
            <td>${escapeHtml(entry.ComputerName)}</td>
            <td class="message-cell">${escapeHtml(truncate(entry.Message, 100))}</td>
        </tr>
    `).join('');
}

function showSaveModal() {
    document.getElementById('saveFilterModal')?.classList.add('active');
    document.getElementById('filterName')?.focus();
}

function hideSaveModal() {
    document.getElementById('saveFilterModal')?.classList.remove('active');
    document.getElementById('saveFilterForm')?.reset();
}

async function saveFilter(e) {
    e.preventDefault();
    showLoading(true);

    try {
        const request = {
            Name: document.getElementById('filterName').value,
            Description: document.getElementById('filterDescription').value || null,
            Category: document.getElementById('filterCategory').value || null,
            IsShared: document.getElementById('filterShared').checked,
            IsAlertEnabled: document.getElementById('filterAlertEnabled').checked,
            FilterJson: JSON.stringify(buildFilterJson())
        };

        const response = await Api.post('/api/filters', request);
        
        if (response.Success) {
            hideSaveModal();
            loadSavedFilters();
            alert('Filter saved successfully!');
        } else {
            alert('Error saving filter: ' + response.Error);
        }
    } catch (error) {
        console.error('Save error:', error);
        alert('Error saving filter: ' + error.message);
    } finally {
        showLoading(false);
    }
}

async function loadSavedFilters() {
    const container = document.getElementById('filterList');
    if (!container) return;

    try {
        const response = await Api.get('/api/filters');
        
        if (response.Success && response.Data) {
            if (response.Data.length === 0) {
                container.innerHTML = '<div class="empty-state">No saved filters yet</div>';
                return;
            }

            container.innerHTML = response.Data.map(filter => `
                <div class="filter-item" data-filter-id="${filter.Id}">
                    <div class="filter-item-info" onclick="loadFilter('${filter.Id}')">
                        <div class="filter-item-name">
                            ${escapeHtml(filter.Name)}
                            ${filter.IsAlertEnabled ? '<span class="alert-badge">ALERT</span>' : ''}
                        </div>
                        <div class="filter-item-meta">
                            ${filter.Category ? filter.Category + ' • ' : ''}
                            Created ${formatDate(filter.CreatedAt)}
                            ${filter.CreatedBy ? 'by ' + filter.CreatedBy : ''}
                        </div>
                    </div>
                    <div class="filter-item-actions">
                        <button class="btn btn-outline" onclick="loadFilter('${filter.Id}')" title="Load">📥</button>
                        <button class="btn btn-outline" onclick="deleteFilter('${filter.Id}')" title="Delete" style="color: var(--error-color);">🗑️</button>
                    </div>
                </div>
            `).join('');
        } else {
            container.innerHTML = '<div class="empty-state">Error loading filters</div>';
        }
    } catch (error) {
        console.error('Load filters error:', error);
        container.innerHTML = '<div class="empty-state">Error loading filters</div>';
    }
}

async function loadFilter(filterId) {
    showLoading(true);

    try {
        const response = await Api.get(`/api/filters/${filterId}`);
        
        if (response.Success && response.Data) {
            const filterJson = JSON.parse(response.Data.FilterJson);
            applyFilterToBuilder(filterJson);
            alert(`Loaded filter: ${response.Data.Name}`);
        } else {
            alert('Error loading filter: ' + response.Error);
        }
    } catch (error) {
        console.error('Load filter error:', error);
        alert('Error loading filter: ' + error.message);
    } finally {
        showLoading(false);
    }
}

function applyFilterToBuilder(filter) {
    queryRows = [];
    rowIdCounter = 0;

    // Convert filter object back to query rows
    if (filter.FromDate) {
        queryRows.push({ id: rowIdCounter++, field: 'FromDate', operator: 'equals', value: filter.FromDate.slice(0, 16), conjunction: 'AND' });
    }
    if (filter.ToDate) {
        queryRows.push({ id: rowIdCounter++, field: 'ToDate', operator: 'equals', value: filter.ToDate.slice(0, 16), conjunction: 'AND' });
    }
    if (filter.Levels && filter.Levels.length > 0) {
        for (const level of filter.Levels) {
            queryRows.push({ id: rowIdCounter++, field: 'Level', operator: 'equals', value: level, conjunction: 'OR' });
        }
    }
    if (filter.ComputerName) {
        queryRows.push({ id: rowIdCounter++, field: 'ComputerName', operator: 'contains', value: filter.ComputerName, conjunction: 'AND' });
    }
    if (filter.UserName) {
        queryRows.push({ id: rowIdCounter++, field: 'UserName', operator: 'contains', value: filter.UserName, conjunction: 'AND' });
    }
    if (filter.MessageText) {
        queryRows.push({ id: rowIdCounter++, field: 'MessageText', operator: 'contains', value: filter.MessageText, conjunction: 'AND' });
    }
    if (filter.FunctionName) {
        queryRows.push({ id: rowIdCounter++, field: 'FunctionName', operator: 'contains', value: filter.FunctionName, conjunction: 'AND' });
    }
    if (filter.RegexPattern) {
        queryRows.push({ id: rowIdCounter++, field: 'RegexPattern', operator: 'regex', value: filter.RegexPattern, conjunction: 'AND' });
    }
    if (filter.Ordrenr) {
        queryRows.push({ id: rowIdCounter++, field: 'Ordrenr', operator: 'contains', value: filter.Ordrenr, conjunction: 'AND' });
    }
    if (filter.Avdnr) {
        queryRows.push({ id: rowIdCounter++, field: 'Avdnr', operator: 'contains', value: filter.Avdnr, conjunction: 'AND' });
    }
    if (filter.JobName) {
        queryRows.push({ id: rowIdCounter++, field: 'JobName', operator: 'contains', value: filter.JobName, conjunction: 'AND' });
    }
    if (filter.AlertId) {
        queryRows.push({ id: rowIdCounter++, field: 'AlertId', operator: 'contains', value: filter.AlertId, conjunction: 'AND' });
    }

    if (queryRows.length === 0) addQueryRow();
    else renderQueryRows();
}

async function deleteFilter(filterId) {
    if (!confirm('Are you sure you want to delete this filter?')) return;

    showLoading(true);

    try {
        const response = await Api.delete(`/api/filters/${filterId}`);
        
        if (response.Success) {
            loadSavedFilters();
        } else {
            alert('Error deleting filter: ' + response.Error);
        }
    } catch (error) {
        console.error('Delete filter error:', error);
        alert('Error deleting filter: ' + error.message);
    } finally {
        showLoading(false);
    }
}

function exportJson() {
    const filterJson = JSON.stringify(buildFilterJson(), null, 2);
    const blob = new Blob([filterJson], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'filter-export.json';
    a.click();
    URL.revokeObjectURL(url);
}

// Utility functions
function showLoading(show) {
    const overlay = document.getElementById('loadingOverlay');
    if (overlay) overlay.style.display = show ? 'flex' : 'none';
}

function formatDate(dateStr) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return '';
    // Format: YYYY-MM-DD HH:mm:ss
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const hours = String(d.getHours()).padStart(2, '0');
    const minutes = String(d.getMinutes()).padStart(2, '0');
    const seconds = String(d.getSeconds()).padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
}

function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function truncate(str, len) {
    if (!str) return '';
    return str.length > len ? str.slice(0, len) + '...' : str;
}
