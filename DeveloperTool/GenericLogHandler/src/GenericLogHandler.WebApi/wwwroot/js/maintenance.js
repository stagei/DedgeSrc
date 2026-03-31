/**
 * Maintenance Page JavaScript
 * Handles service control, database health, and maintenance operations
 */
(function() {
    'use strict';

    // Load initial data on DOM ready
    document.addEventListener('DOMContentLoaded', () => {
        loadServiceStatus();
        loadDbHealth();
        loadSanitationPreview();
        loadBackupList();
        
        // Auto-refresh service status every 10 seconds
        setInterval(loadServiceStatus, 10000);
    });

    /**
     * Load Windows service status
     */
    async function loadServiceStatus() {
        try {
            const resp = await Api.get('/api/maintenance/services');
            if (resp && resp.Success) {
                updateServiceCard('import', resp.Data.Import);
                updateServiceCard('agent', resp.Data.Agent);
            }
        } catch (e) {
            console.error('Error loading service status:', e);
        }
    }

    /**
     * Update service card UI
     */
    function updateServiceCard(service, data) {
        const statusEl = document.getElementById(`${service}Status`);
        if (statusEl) {
            const status = data?.Status || 'Unknown';
            statusEl.textContent = status;
            statusEl.className = 'stat-value status-' + status.toLowerCase();
        }
    }

    /**
     * Control a Windows service (start/stop)
     */
    window.controlService = async function(service, action) {
        const btn = event?.target;
        if (btn) Loader.button(btn, true);
        
        try {
            const resp = await Api.post(`/api/maintenance/services/${service}/${action}`);
            if (resp && resp.Success) {
                Toast.success(`Service ${action} successful`);
                await loadServiceStatus();
            } else {
                Toast.error(resp?.Error || `Failed to ${action} service`);
            }
        } catch (e) {
            Toast.error(e.message || `Failed to ${action} service`);
        } finally {
            if (btn) Loader.button(btn, false);
        }
    };

    /**
     * Load database health statistics
     */
    async function loadDbHealth() {
        try {
            // Load database stats
            const statsResp = await Api.get('/api/Dashboard/database-stats');
            if (statsResp && statsResp.Success) {
                document.getElementById('dbSize').textContent = 
                    statsResp.Data.DatabaseSizeGb.toFixed(2) + ' GB';
                document.getElementById('totalEntries').textContent = 
                    statsResp.Data.TotalLogEntries.toLocaleString();
            }

            // Load protected count
            const protResp = await Api.get('/api/maintenance/sanitation/protected-count');
            if (protResp && protResp.Success) {
                document.getElementById('protectedEntries').textContent = 
                    protResp.Data.ProtectedEntries.toLocaleString();
            }

            // Load DB health details
            const healthResp = await Api.get('/api/maintenance/db-health');
            if (healthResp && healthResp.Success) {
                document.getElementById('autovacuum').textContent = 
                    healthResp.Data.AutovacuumEnabled ? 'ON' : 'OFF';
                
                renderTableHealth(healthResp.Data.Tables);
            }
        } catch (e) {
            console.error('Error loading DB health:', e);
            Toast.error('Failed to load database health');
        }
    }

    /**
     * Render table health details
     */
    function renderTableHealth(tables) {
        if (!tables || !tables.length) return;
        
        let html = `
            <table class="table-health data-table">
                <thead>
                    <tr>
                        <th>Table</th>
                        <th>Live</th>
                        <th>Dead</th>
                        <th>Size</th>
                        <th>Last Autovacuum</th>
                    </tr>
                </thead>
                <tbody>
        `;
        
        for (const t of tables) {
            const lastVac = t.LastAutovacuum 
                ? new Date(t.LastAutovacuum).toLocaleString() 
                : 'Never';
            html += `
                <tr>
                    <td>${escapeHtml(t.TableName)}</td>
                    <td>${t.LiveTuples.toLocaleString()}</td>
                    <td>${t.DeadTuples.toLocaleString()}</td>
                    <td>${escapeHtml(t.TotalSize)}</td>
                    <td>${lastVac}</td>
                </tr>
            `;
        }
        
        html += '</tbody></table>';
        document.getElementById('tableHealthContainer').innerHTML = html;
    }

    /**
     * Run a maintenance operation
     */
    window.runMaintenance = async function(type, option) {
        const resultId = type + 'Result';
        const btn = event?.target;
        if (btn) Loader.button(btn, true);
        
        try {
            let url = '/api/maintenance/' + type;
            if (type === 'vacuum-analyze' && option === true) url += '?full=true';
            if (type === 'reindex' && option === false) url += '?concurrent=false';
            
            const resp = await Api.post(url);
            if (resp && resp.Success) {
                showResult(resultId, `${resp.Data.Operation}: ${resp.Data.Message}`, true);
                Toast.success('Maintenance operation completed');
                await loadDbHealth();
            } else {
                showResult(resultId, resp?.Error || 'Operation failed', false);
                Toast.error(resp?.Error || 'Operation failed');
            }
        } catch (e) {
            showResult(resultId, e.message, false);
            Toast.error(e.message || 'Operation failed');
        } finally {
            if (btn) Loader.button(btn, false);
        }
    };

    /**
     * Load sanitation preview
     */
    async function loadSanitationPreview() {
        try {
            const resp = await Api.get('/api/maintenance/sanitation/preview');
            if (resp && resp.Success) {
                document.getElementById('toDeleteCount').textContent = 
                    resp.Data.EntriesToDelete.toLocaleString();
                document.getElementById('protectedSafe').textContent = 
                    resp.Data.ProtectedEntries.toLocaleString();
                document.getElementById('retentionDays').textContent = 
                    resp.Data.RetentionDays;
            }
        } catch (e) {
            console.error('Error loading sanitation preview:', e);
        }
    }

    /**
     * Preview sanitation
     */
    window.previewSanitation = async function() {
        await loadSanitationPreview();
        showResult('sanitationResult', 'Preview refreshed. See counts above.', true);
        Toast.info('Sanitation preview refreshed');
    };

    /**
     * Run sanitation
     */
    window.runSanitation = async function() {
        const confirmed = await Modal.confirm(
            'This will delete old unprotected log entries. Continue?',
            { title: 'Confirm Sanitation', danger: true }
        );
        if (!confirmed) return;
        
        const btn = event?.target;
        if (btn) Loader.button(btn, true);
        
        try {
            const resp = await Api.post('/api/maintenance/sanitation/run');
            if (resp && resp.Success) {
                showResult('sanitationResult', 
                    `Deleted ${resp.Data.DeletedCount.toLocaleString()} entries in ${resp.Data.DurationMs}ms`, 
                    true
                );
                Toast.success(`Deleted ${resp.Data.DeletedCount.toLocaleString()} entries`);
                await loadDbHealth();
                await loadSanitationPreview();
            } else {
                showResult('sanitationResult', resp?.Error || 'Failed', false);
                Toast.error(resp?.Error || 'Sanitation failed');
            }
        } catch (e) {
            showResult('sanitationResult', e.message, false);
            Toast.error(e.message || 'Sanitation failed');
        } finally {
            if (btn) Loader.button(btn, false);
        }
    };

    /**
     * Confirm dangerous operation
     */
    window.confirmDanger = async function(type) {
        const messages = {
            truncate: 'This will DELETE ALL log entries. This cannot be undone!',
            recreate: 'This will DROP ALL TABLES and recreate them. ALL DATA WILL BE LOST!'
        };
        const confirms = { truncate: 'DELETE', recreate: 'DESTROY' };
        
        const input = prompt(`${messages[type]}\n\nType "${confirms[type]}" to confirm:`);
        if (input !== confirms[type]) {
            Toast.warning('Confirmation failed. Operation cancelled.');
            return;
        }
        
        await executeDanger(type);
    };

    /**
     * Execute dangerous operation
     */
    async function executeDanger(type) {
        let truncateUrl = '/api/maintenance/truncate-log-entries';
        if (type === 'truncate') {
            const resetTracking = document.getElementById('resetImportTracking')?.checked;
            if (resetTracking) {
                truncateUrl += '?resetImportTracking=true';
            }
        }
        const endpoints = {
            truncate: truncateUrl,
            recreate: '/api/maintenance/recreate-schema'
        };
        const resultId = type + 'Result';
        
        Loader.show('Executing operation...');
        
        try {
            const resp = await Api.post(endpoints[type]);
            if (resp && resp.Success) {
                showResult(resultId, 'Operation completed successfully', true);
                Toast.success('Operation completed successfully');
                await loadDbHealth();
            } else {
                showResult(resultId, resp?.Error || 'Failed', false);
                Toast.error(resp?.Error || 'Operation failed');
            }
        } catch (e) {
            showResult(resultId, e.message, false);
            Toast.error(e.message || 'Operation failed');
        } finally {
            Loader.hide();
        }
    }

    /**
     * Create a database backup
     */
    window.runBackup = async function() {
        const btn = document.getElementById('backupBtn');
        if (btn) Loader.button(btn, true);

        try {
            const resp = await Api.post('/api/maintenance/backup');
            if (resp && resp.Success) {
                const d = resp.Data;
                showResult('backupResult',
                    `Backup created: ${d.FileName}\nSize: ${d.FileSize}\nDuration: ${d.DurationMs}ms\nPath: ${d.FilePath}`,
                    true);
                Toast.success(`Backup created: ${d.FileName} (${d.FileSize})`);
                await loadBackupList();
            } else {
                showResult('backupResult', resp?.Error || 'Backup failed', false);
                Toast.error(resp?.Error || 'Backup failed');
            }
        } catch (e) {
            showResult('backupResult', e.message, false);
            Toast.error(e.message || 'Backup failed');
        } finally {
            if (btn) Loader.button(btn, false);
        }
    };

    /**
     * Load and render list of existing backups
     */
    async function loadBackupList() {
        const container = document.getElementById('backupList');
        if (!container) return;

        try {
            const resp = await Api.get('/api/maintenance/backups');
            if (!resp || !resp.Success || !resp.Data || resp.Data.length === 0) {
                container.innerHTML = '<p style="font-size:0.82rem;color:var(--text-muted);margin:0;">No backups found.</p>';
                return;
            }

            let html = '<table class="table-health data-table"><thead><tr>' +
                '<th>File</th><th>Size</th><th>Created</th><th></th>' +
                '</tr></thead><tbody>';

            for (const b of resp.Data) {
                const created = new Date(b.CreatedAt).toLocaleString();
                html += `<tr>
                    <td style="font-family:monospace;font-size:0.82rem;">${escapeHtml(b.FileName)}</td>
                    <td>${escapeHtml(b.FileSize)}</td>
                    <td>${created}</td>
                    <td><button class="btn btn-danger" style="padding:0.25rem 0.5rem;font-size:0.75rem;" onclick="deleteBackup('${escapeHtml(b.FileName)}')">Delete</button></td>
                </tr>`;
            }

            html += '</tbody></table>';
            container.innerHTML = html;
        } catch (e) {
            container.innerHTML = '';
        }
    }

    /**
     * Delete a backup file
     */
    window.deleteBackup = async function(fileName) {
        if (!confirm(`Delete backup "${fileName}"?`)) return;

        try {
            const resp = await Api.delete('/api/maintenance/backups/' + encodeURIComponent(fileName));
            if (resp && resp.Success) {
                Toast.success('Backup deleted');
                await loadBackupList();
            } else {
                Toast.error(resp?.Error || 'Delete failed');
            }
        } catch (e) {
            Toast.error(e.message || 'Delete failed');
        }
    };

    /**
     * Show result in result box
     */
    function showResult(id, message, success) {
        const el = document.getElementById(id);
        if (el) {
            el.textContent = message;
            el.className = 'result-box show ' + (success ? 'success' : 'error');
        }
    }

    /**
     * Escape HTML
     */
    function escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
})();
