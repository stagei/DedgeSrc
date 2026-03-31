(function () {
    'use strict';

    let allSources = [];
    let currentViewId = null;

    function init() {
        if (typeof ThemeManager !== 'undefined') ThemeManager.init();
        loadSources();

        document.getElementById('editModal').addEventListener('click', function (e) {
            if (e.target === this) closeEditModal();
        });
        document.getElementById('viewModal').addEventListener('click', function (e) {
            if (e.target === this) closeViewModal();
        });
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape') {
                closeEditModal();
                closeViewModal();
            }
        });
    }

    async function loadSources() {
        try {
            var resp = await Api.get('/api/ImportSources');
            if (resp && resp.Success && Array.isArray(resp.Data)) {
                allSources = resp.Data;
                renderGrid(allSources);
                updateStats(allSources);
            }
        } catch (err) {
            document.getElementById('sourcesContainer').innerHTML =
                '<div class="empty-state" style="color:var(--error-color);">Error loading import sources</div>';
        }
    }

    function updateStats(sources) {
        var active = sources.filter(function (s) { return s.Enabled; }).length;
        document.getElementById('totalCount').textContent = sources.length;
        document.getElementById('activeCount').textContent = active;
        document.getElementById('disabledCount').textContent = sources.length - active;
    }

    function renderGrid(sources) {
        var container = document.getElementById('sourcesContainer');
        if (!sources || sources.length === 0) {
            container.innerHTML =
                '<div class="empty-state">' +
                '<h3>No import sources configured</h3>' +
                '<p>Add an import source to start collecting logs.</p>' +
                '</div>';
            return;
        }

        var html = '<table class="sources-table"><thead><tr>' +
            '<th>Status</th>' +
            '<th>Name</th>' +
            '<th>Path</th>' +
            '<th>Type</th>' +
            '<th>Format</th>' +
            '<th>Priority</th>' +
            '<th>Last Import</th>' +
            '<th style="text-align:right;">Actions</th>' +
            '</tr></thead><tbody>';

        sources.forEach(function (s) {
            var rowClass = s.Enabled ? '' : ' class="disabled-row"';
            html += '<tr' + rowClass + '>' +
                '<td><span class="status-dot ' + (s.Enabled ? 'active' : 'inactive') + '"></span>' +
                    (s.Enabled ? 'Active' : 'Disabled') + '</td>' +
                '<td class="source-name-cell">' +
                    '<a href="#" onclick="viewSource(\'' + s.Id + '\');return false;" style="color:var(--text-primary);text-decoration:none;" title="View details">' +
                    esc(s.Name) + '</a></td>' +
                '<td class="source-path-cell" title="' + esc(s.Path) + '">' + truncatePath(s.Path, 55) + '</td>' +
                '<td><span class="badge badge-' + s.Type + '">' + s.Type + '</span></td>' +
                '<td><span class="badge badge-' + s.Format + '">' + s.Format + '</span></td>' +
                '<td>' + s.Priority + '</td>' +
                '<td class="last-import-cell">' + formatLastImport(s) + '</td>' +
                '<td class="actions-cell">' +
                    '<button onclick="viewSource(\'' + s.Id + '\')" title="View details">👁️</button>' +
                    '<button onclick="editSource(\'' + s.Id + '\')" title="Edit">✏️</button>' +
                    '<button onclick="toggleSource(\'' + s.Id + '\')" title="' + (s.Enabled ? 'Disable' : 'Enable') + '">' +
                        (s.Enabled ? '⏸️' : '▶️') + '</button>' +
                    '<button onclick="testSourceById(\'' + s.Id + '\')" title="Test connection">🔍</button>' +
                    '<button class="btn-danger" onclick="deleteSource(\'' + s.Id + '\',\'' + esc(s.Name).replace(/'/g, "\\'") + '\')" title="Delete">🗑️</button>' +
                '</td></tr>';
        });

        html += '</tbody></table>';
        container.innerHTML = html;
    }

    function formatLastImport(s) {
        if (s.LastError) {
            return '<span class="error-text" title="' + esc(s.LastError) + '">⚠️ ' + esc(s.LastError.substring(0, 40)) + '</span>';
        }
        if (!s.LastImportAt) return '<span style="color:var(--text-secondary);">—</span>';
        return formatDate(s.LastImportAt) + '<br><span style="font-size:0.78rem;">' + s.LastImportCount + ' records</span>';
    }

    function truncatePath(path, max) {
        if (!path) return '';
        if (path.length <= max) return esc(path);
        return esc('…' + path.substring(path.length - max + 1));
    }

    // ----- Create / Edit -----

    window.openCreateModal = function () {
        document.getElementById('editModalTitle').textContent = 'Add Import Source';
        document.getElementById('fld_id').value = '';
        document.getElementById('sourceForm').reset();
        document.getElementById('fld_priority').value = '100';
        document.getElementById('fld_poll').value = '30';
        document.getElementById('fld_maxage').value = '30';
        document.getElementById('fld_enabled').checked = true;
        document.getElementById('fld_process').checked = true;
        hideTestResult();
        document.getElementById('editModal').classList.add('show');
    };

    window.editSource = async function (id) {
        try {
            var resp = await Api.get('/api/ImportSources/' + id);
            if (!resp || !resp.Success) { Toast.error('Source not found'); return; }
            var s = resp.Data;
            document.getElementById('editModalTitle').textContent = 'Edit: ' + s.Name;
            document.getElementById('fld_id').value = s.Id;
            document.getElementById('fld_name').value = s.Name;
            document.getElementById('fld_path').value = s.Path;
            document.getElementById('fld_type').value = s.Type;
            document.getElementById('fld_format').value = s.Format;
            document.getElementById('fld_encoding').value = s.Encoding;
            document.getElementById('fld_priority').value = s.Priority;
            document.getElementById('fld_poll').value = s.PollInterval;
            document.getElementById('fld_maxage').value = s.MaxFileAgeDays;
            document.getElementById('fld_enabled').checked = s.Enabled;
            document.getElementById('fld_watch').checked = s.WatchDirectory;
            document.getElementById('fld_process').checked = s.ProcessExistingFiles;
            document.getElementById('fld_append').checked = s.IsAppendOnly;
            document.getElementById('fld_description').value = s.Description || '';
            hideTestResult();
            document.getElementById('editModal').classList.add('show');
        } catch (err) {
            Toast.error('Error loading source');
        }
    };

    window.closeEditModal = function () {
        document.getElementById('editModal').classList.remove('show');
    };

    window.saveSource = async function (event) {
        event.preventDefault();
        var id = document.getElementById('fld_id').value;
        var data = {
            Name: document.getElementById('fld_name').value,
            Path: document.getElementById('fld_path').value,
            Type: document.getElementById('fld_type').value,
            Format: document.getElementById('fld_format').value,
            Encoding: document.getElementById('fld_encoding').value,
            Priority: parseInt(document.getElementById('fld_priority').value) || 100,
            PollInterval: parseInt(document.getElementById('fld_poll').value) || 30,
            MaxFileAgeDays: parseInt(document.getElementById('fld_maxage').value) || 30,
            Enabled: document.getElementById('fld_enabled').checked,
            WatchDirectory: document.getElementById('fld_watch').checked,
            ProcessExistingFiles: document.getElementById('fld_process').checked,
            IsAppendOnly: document.getElementById('fld_append').checked,
            Description: document.getElementById('fld_description').value || null
        };

        try {
            var resp;
            if (id) {
                resp = await Api.put('/api/ImportSources/' + id, data);
            } else {
                resp = await Api.post('/api/ImportSources', data);
            }
            if (resp && resp.Success) {
                Toast.success(id ? 'Source updated' : 'Source created');
                closeEditModal();
                loadSources();
            } else {
                Toast.error(resp && resp.Error ? resp.Error : 'Save failed');
            }
        } catch (err) {
            Toast.error('Error saving source');
        }
    };

    // ----- View -----

    window.viewSource = async function (id) {
        try {
            var resp = await Api.get('/api/ImportSources/' + id);
            if (!resp || !resp.Success) { Toast.error('Source not found'); return; }
            var s = resp.Data;
            currentViewId = id;

            document.getElementById('viewModalTitle').textContent = s.Name;

            var html = '<div class="detail-grid">' +
                row('Status', s.Enabled ? '<span class="status-dot active"></span> Active' : '<span class="status-dot inactive"></span> Disabled') +
                row('Source Type', '<span class="badge badge-' + s.Type + '">' + s.Type + '</span>') +
                row('Format', '<span class="badge badge-' + s.Format + '">' + s.Format + '</span>') +
                row('Path', '<span class="mono">' + esc(s.Path) + '</span>') +
                row('Priority', s.Priority) +
                row('Encoding', s.Encoding) +
                row('Poll Interval', s.PollInterval + 's') +
                row('Max File Age', s.MaxFileAgeDays + ' days') +
                row('Watch Directory', s.WatchDirectory ? 'Yes' : 'No') +
                row('Process Existing', s.ProcessExistingFiles ? 'Yes' : 'No') +
                row('Append-Only', s.IsAppendOnly ? 'Yes' : 'No');

            if (s.Description) html += row('Description', esc(s.Description));
            if (s.LastImportAt) html += row('Last Import', formatDate(s.LastImportAt) + ' (' + s.LastImportCount + ' records)');
            if (s.LastError) html += row('Last Error', '<span class="error-text">' + esc(s.LastError) + '</span>');
            html += row('Created', formatDate(s.CreatedAt) + (s.CreatedBy ? ' by ' + esc(s.CreatedBy) : ''));
            html += row('Updated', formatDate(s.UpdatedAt));
            html += '</div>';

            document.getElementById('viewModalBody').innerHTML = html;

            document.getElementById('viewEditBtn').onclick = function () { closeViewModal(); editSource(id); };
            document.getElementById('viewTestBtn').onclick = function () { testSourceById(id); };

            document.getElementById('viewModal').classList.add('show');
        } catch (err) {
            Toast.error('Error loading source details');
        }
    };

    window.closeViewModal = function () {
        document.getElementById('viewModal').classList.remove('show');
        currentViewId = null;
    };

    function row(label, value) {
        return '<div class="detail-label">' + label + '</div><div class="detail-value">' + value + '</div>';
    }

    // ----- Toggle / Delete / Test -----

    window.toggleSource = async function (id) {
        try {
            var resp = await Api.post('/api/ImportSources/' + id + '/toggle');
            if (resp && resp.Success) {
                Toast.success(resp.Data.Enabled ? 'Source enabled' : 'Source disabled');
                loadSources();
            }
        } catch (err) {
            Toast.error('Error toggling source');
        }
    };

    window.deleteSource = async function (id, name) {
        if (!confirm('Delete import source "' + name + '"?\n\nThis will NOT delete any already-imported log entries.')) return;
        try {
            var resp = await Api.delete('/api/ImportSources/' + id);
            if (resp && resp.Success) {
                Toast.success('Source deleted');
                loadSources();
            }
        } catch (err) {
            Toast.error('Error deleting source');
        }
    };

    window.testSourceById = async function (id) {
        try {
            Toast.info('Testing connection...');
            var resp = await Api.post('/api/ImportSources/' + id + '/test');
            if (resp && resp.Success) {
                var r = resp.Data;
                if (r.IsAccessible) {
                    Toast.success(r.Message + (r.FileCount > 0 ? ' (' + r.FileCount + ' files)' : ''));
                } else {
                    Toast.error(r.Message);
                }
                showTestResult(r);
            }
        } catch (err) {
            Toast.error('Test failed');
        }
    };

    window.testCurrentSource = async function () {
        var id = document.getElementById('fld_id').value;
        if (!id) {
            Toast.info('Save the source first, then test');
            return;
        }
        await testSourceById(id);
    };

    function showTestResult(result) {
        var box = document.getElementById('testResultBox');
        if (!box) return;
        box.className = 'test-result-box ' + (result.IsAccessible ? 'success' : 'error');
        var html = '<strong>' + (result.IsAccessible ? '✓ Success' : '✗ Failed') + '</strong>: ' + esc(result.Message);
        if (result.FileCount > 0) html += '<br>Found ' + result.FileCount + ' file(s)';
        if (result.SampleFiles && result.SampleFiles.length > 0) {
            html += '<br>Sample: ' + result.SampleFiles.map(esc).join(', ');
        }
        box.innerHTML = html;
        box.style.display = 'block';
    }

    function hideTestResult() {
        var box = document.getElementById('testResultBox');
        if (box) { box.style.display = 'none'; box.innerHTML = ''; }
    }

    // ----- Helpers -----

    function esc(text) {
        if (text == null) return '';
        var div = document.createElement('div');
        div.textContent = String(text);
        return div.innerHTML;
    }

    function formatDate(dateStr) {
        if (!dateStr) return '—';
        var d = new Date(dateStr);
        if (isNaN(d.getTime())) return '—';
        var y = d.getFullYear();
        var m = String(d.getMonth() + 1).padStart(2, '0');
        var day = String(d.getDate()).padStart(2, '0');
        var h = String(d.getHours()).padStart(2, '0');
        var min = String(d.getMinutes()).padStart(2, '0');
        return y + '-' + m + '-' + day + ' ' + h + ':' + min;
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
