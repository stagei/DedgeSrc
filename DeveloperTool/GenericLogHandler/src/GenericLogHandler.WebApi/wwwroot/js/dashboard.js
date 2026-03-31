/**
 * Generic Log Handler - Dashboard page
 * Uses Api (credentials: 'include') for Windows auth. API returns PascalCase.
 * Features: auto-refresh, recent logs panel, expandable rows, modal view
 */

(function () {
  // DOM elements
  const loadingOverlay = document.getElementById('loadingOverlay');
  const authBadge = document.getElementById('authBadge');
  const refreshBtn = document.getElementById('refreshBtn');
  const themeToggle = document.getElementById('themeToggle');
  const loadingSpinner = document.getElementById('loadingSpinner');
  const countdownEl = document.getElementById('countdown');
  const autoRefreshCheckbox = document.getElementById('autoRefresh');
  const refreshIntervalSelect = document.getElementById('refreshInterval');
  const sourceFilterSelect = document.getElementById('sourceFilter');
  const dashboardDateNote = document.getElementById('dashboardDateNote');
  
  // State
  let autoRefresh = true;
  let refreshInterval = 30;
  let sourcePath = '';
  let refreshTimer = null;
  let countdownValue = 0;
  let countdownTimer = null;
  let currentModalLog = null;
  let logsRenderer = null;
  
  // Load settings from localStorage
  function loadSettings() {
    try {
      const saved = localStorage.getItem('loghandler-dashboard-settings');
      if (saved) {
        const parsed = JSON.parse(saved);
        autoRefresh = typeof parsed.autoRefresh === 'boolean' ? parsed.autoRefresh : true;
        refreshInterval = typeof parsed.refreshInterval === 'number' ? parsed.refreshInterval : 30;
        if (typeof parsed.sourcePath === 'string') sourcePath = parsed.sourcePath;
      }
    } catch (e) {
      console.warn('Failed to load settings', e);
    }
  }
  
  function saveSettings() {
    try {
      localStorage.setItem('loghandler-dashboard-settings', JSON.stringify({
        autoRefresh: autoRefresh,
        refreshInterval: refreshInterval,
        sourcePath: sourcePath
      }));
    } catch (e) {
      console.warn('Failed to save settings', e);
    }
  }
  
  function getSourcePathForRequest() {
    if (!sourceFilterSelect) return '';
    const val = sourceFilterSelect.value;
    return val == null ? '' : val;
  }

  async function loadSourceFilters() {
    if (!sourceFilterSelect) return;
    try {
      const resp = await Api.get('/api/ImportSources');
      if (!resp || !resp.Success || !Array.isArray(resp.Data)) return;

      const sources = resp.Data.filter(function(s) { return s.Enabled; });
      sources.sort(function(a, b) { return (a.Priority || 0) - (b.Priority || 0); });

      sources.forEach(function(src) {
        var filterValue = deriveFilterValue(src.Path || '');
        if (!filterValue) return;
        var opt = document.createElement('option');
        opt.value = filterValue;
        opt.textContent = src.Name + ' (' + filterValue + ')';
        sourceFilterSelect.appendChild(opt);
      });

      if (sourcePath) {
        sourceFilterSelect.value = sourcePath;
      }
    } catch (e) {
      console.warn('Failed to load source filters', e);
    }
  }

  function deriveFilterValue(path) {
    if (!path) return '';
    var clean = path.replace(/[\\/]+$/, '');
    var lastSegment = clean.split(/[\\/]/).pop() || '';
    if (/[*?]/.test(lastSegment)) {
      clean = clean.substring(0, clean.length - lastSegment.length).replace(/[\\/]+$/, '');
    }
    return clean;
  }
  
  function updateDashboardDateNote(activeFilter) {
    if (!dashboardDateNote) return;
    if (activeFilter) {
      dashboardDateNote.textContent = "Today's stats use server local date. Filtered by source: " + activeFilter + ".";
    } else {
      dashboardDateNote.textContent = "Today's stats use server local date. Showing all import sources.";
    }
  }

  function showLoading(show) {
    if (loadingSpinner) loadingSpinner.classList.toggle('hidden', !show);
  }

  function hideInitialLoading() {
    if (loadingOverlay) loadingOverlay.classList.add('hidden');
  }

  function updateAuthBadge(authenticated, errorMessage) {
    if (!authBadge) return;
    const icon = authBadge.querySelector('.auth-badge-icon');
    const text = authBadge.querySelector('.auth-badge-text');
    const role = authBadge.querySelector('.auth-badge-role');
    authBadge.className = 'auth-badge';
    if (authenticated) {
      authBadge.classList.add('auth-full');
      if (icon) icon.textContent = '✓';
      if (text) text.textContent = 'Authenticated';
      if (role) role.textContent = '';
      authBadge.title = 'Windows authentication';
    } else {
      authBadge.classList.add('auth-none');
      if (icon) icon.textContent = '🔒';
      if (text) text.textContent = 'Access denied';
      if (role) role.textContent = errorMessage || '';
      authBadge.title = errorMessage || 'Windows authentication required';
    }
    authBadge.style.display = 'flex';
  }

  function formatDate(d) {
    if (!d) return '–';
    const date = typeof d === 'string' ? new Date(d) : d;
    if (isNaN(date.getTime())) return '–';
    // Format: YYYY-MM-DD HH:mm:ss
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const seconds = String(date.getSeconds()).padStart(2, '0');
    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
  }
  
  function formatTime(d) {
    return formatDate(d); // Use full date/time format
    // Legacy fallback for time-only display
    const date = typeof d === 'string' ? new Date(d) : d;
    return isNaN(date.getTime()) ? '–' : date.toLocaleTimeString();
  }

  function renderSummary(data) {
    const totalLogsToday = document.getElementById('totalLogsToday');
    const errorsToday = document.getElementById('errorsToday');
    const warningsToday = document.getElementById('warningsToday');
    const activeComputers = document.getElementById('activeComputers');
    if (totalLogsToday) totalLogsToday.textContent = (data.TotalLogsToday ?? 0).toLocaleString();
    if (errorsToday) errorsToday.textContent = (data.ErrorsToday ?? 0).toLocaleString();
    if (warningsToday) warningsToday.textContent = (data.WarningsToday ?? 0).toLocaleString();
    if (activeComputers) activeComputers.textContent = (data.ActiveComputers ?? 0).toLocaleString();
  }

  function renderTopComputers(items) {
    const tbody = document.querySelector('#topComputersTable tbody');
    const empty = document.getElementById('topComputersEmpty');
    if (!tbody) return;
    tbody.innerHTML = '';
    if (!items || items.length === 0) {
      if (empty) empty.classList.remove('hidden');
      return;
    }
    if (empty) empty.classList.add('hidden');
    items.forEach(function (row) {
      const tr = document.createElement('tr');
      tr.innerHTML =
        '<td>' + escapeHtml(row.ComputerName || '') + '</td>' +
        '<td>' + (row.TotalLogs ?? 0).toLocaleString() + '</td>' +
        '<td>' + (row.ErrorCount ?? 0).toLocaleString() + '</td>' +
        '<td>' + (row.WarningCount ?? 0).toLocaleString() + '</td>' +
        '<td>' + formatDate(row.LastActivity) + '</td>';
      tbody.appendChild(tr);
    });
  }

  function renderTopErrors(items) {
    const tbody = document.querySelector('#topErrorsTable tbody');
    const empty = document.getElementById('topErrorsEmpty');
    if (!tbody) return;
    tbody.innerHTML = '';
    if (!items || items.length === 0) {
      if (empty) empty.classList.remove('hidden');
      return;
    }
    if (empty) empty.classList.add('hidden');
    items.forEach(function (row) {
      const tr = document.createElement('tr');
      const computers = Array.isArray(row.AffectedComputers) ? row.AffectedComputers.join(', ') : '';
      tr.innerHTML =
        '<td>' + escapeHtml(row.ErrorId || '') + '</td>' +
        '<td>' + escapeHtml(row.ExceptionType || '') + '</td>' +
        '<td>' + (row.Count ?? 0).toLocaleString() + '</td>' +
        '<td>' + formatDate(row.LastOccurrence) + '</td>' +
        '<td>' + escapeHtml(computers) + '</td>';
      tbody.appendChild(tr);
    });
  }

  function escapeHtml(s) {
    if (s == null) return '';
    const div = document.createElement('div');
    div.textContent = s;
    return div.innerHTML;
  }
  
  // Recent logs rendering using LogsRenderer
  function renderRecentLogs(items) {
    const tbody = document.getElementById('recentLogsBody');
    const empty = document.getElementById('recentLogsEmpty');
    const summary = document.getElementById('recentLogsSummary');
    
    if (!tbody) return;
    
    if (!items || items.length === 0) {
      tbody.innerHTML = '';
      if (empty) empty.classList.remove('hidden');
      if (summary) summary.textContent = '';
      return;
    }
    
    if (empty) empty.classList.add('hidden');
    if (summary) summary.textContent = `(${items.length} entries)`;
    
    // Use LogsRenderer for rendering
    if (logsRenderer) {
      logsRenderer.render(tbody, items);
    }
  }
  
  // Modal functions
  function openModal(log) {
    currentModalLog = log;
    const modal = document.getElementById('logModal');
    if (!modal) return;
    
    // Set level badge
    const levelBadge = document.getElementById('modalLevelBadge');
    if (levelBadge) {
      const level = (log.Level || 'INFO').toUpperCase();
      levelBadge.textContent = level;
      levelBadge.className = 'severity-badge ' + getLevelClass(level);
    }
    
    // Set basic info
    setText('modalLogId', log.Id || '-');
    setText('modalComputer', log.ComputerName || '-');
    setText('modalTimestamp', formatDate(log.Timestamp));
    setText('modalUser', log.UserName || '-');
    setText('modalFunction', log.FunctionName || '-');
    setText('modalSource', (log.SourceType || '') + (log.SourceFile ? ' (' + log.SourceFile + ')' : ''));
    setText('modalMessage', log.Message || '-');
    
    // Business identifiers section
    const businessSection = document.getElementById('modalBusinessIds');
    const businessTable = document.getElementById('modalBusinessTable');
    if (businessSection && businessTable) {
      const ids = [];
      if (log.AlertId) ids.push({ key: 'Alert ID', value: log.AlertId });
      if (log.Ordrenr) ids.push({ key: 'Order Number', value: log.Ordrenr });
      if (log.Avdnr) ids.push({ key: 'Department', value: log.Avdnr });
      if (log.JobName) ids.push({ key: 'Job Name', value: log.JobName });
      
      if (ids.length > 0) {
        businessSection.style.display = 'block';
        businessTable.innerHTML = ids.map(id => 
          `<div class="metadata-row"><span class="metadata-key">${escapeHtml(id.key)}:</span><span class="metadata-value">${escapeHtml(id.value)}</span></div>`
        ).join('');
      } else {
        businessSection.style.display = 'none';
      }
    }
    
    // Exception section
    const exceptionSection = document.getElementById('modalExceptionSection');
    const exceptionEl = document.getElementById('modalException');
    if (exceptionSection && exceptionEl) {
      if (log.ExceptionType || log.StackTrace) {
        exceptionSection.style.display = 'block';
        exceptionEl.textContent = (log.ExceptionType || '') + '\n' + (log.StackTrace || '');
      } else {
        exceptionSection.style.display = 'none';
      }
    }
    
    // Raw JSON
    const rawJson = document.getElementById('modalRawJson');
    if (rawJson) {
      rawJson.textContent = JSON.stringify(log, null, 2);
    }
    
    modal.classList.remove('hidden');
  }
  
  function closeModal() {
    const modal = document.getElementById('logModal');
    if (modal) modal.classList.add('hidden');
    currentModalLog = null;
  }
  
  function setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value || '-';
  }
  
  function getLevelClass(level) {
    if (level === 'FATAL' || level === 'ERROR') return 'error';
    if (level === 'WARN') return 'warning';
    if (level === 'DEBUG' || level === 'TRACE') return 'debug';
    return 'info';
  }
  
  function copyModalAsMarkdown() {
    if (!currentModalLog) return;
    const log = currentModalLog;
    const lines = [
      `## Log Entry`,
      '',
      `- **Level**: ${(log.Level || 'INFO').toUpperCase()}`,
      `- **Computer**: ${log.ComputerName || 'N/A'}`,
      `- **Time**: ${formatDate(log.Timestamp)}`,
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
    
    navigator.clipboard.writeText(lines.join('\n')).then(() => showToast('Copied as Markdown'));
  }
  
  function copyModalAsJson() {
    if (!currentModalLog) return;
    navigator.clipboard.writeText(JSON.stringify(currentModalLog, null, 2)).then(() => showToast('Copied as JSON'));
  }
  
  function showToast(message) {
    let toast = document.getElementById('dashboard-toast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'dashboard-toast';
      toast.className = 'toast-notification';
      document.body.appendChild(toast);
    }
    toast.textContent = message;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 2000);
  }

  // Auto-refresh functions
  function startAutoRefresh() {
    stopAutoRefresh();
    if (!autoRefresh) return;
    
    countdownValue = refreshInterval;
    updateCountdown();
    
    countdownTimer = setInterval(function() {
      countdownValue--;
      updateCountdown();
    }, 1000);
    
    refreshTimer = setInterval(loadData, refreshInterval * 1000);
  }
  
  function stopAutoRefresh() {
    if (refreshTimer) {
      clearInterval(refreshTimer);
      refreshTimer = null;
    }
    if (countdownTimer) {
      clearInterval(countdownTimer);
      countdownTimer = null;
    }
  }
  
  function updateCountdown() {
    if (!countdownEl) return;
    if (!autoRefresh) {
      countdownEl.textContent = '--';
    } else if (countdownValue >= 60) {
      const mins = Math.floor(countdownValue / 60);
      countdownEl.textContent = mins + 'm';
    } else {
      countdownEl.textContent = countdownValue + 's';
    }
    
    // Reset countdown when it reaches 0
    if (countdownValue <= 0) {
      countdownValue = refreshInterval;
    }
  }

  function updateLastUpdated() {
    const el = document.getElementById('lastUpdatedTime');
    if (el) {
      const now = new Date();
      const hours = String(now.getHours()).padStart(2, '0');
      const minutes = String(now.getMinutes()).padStart(2, '0');
      const seconds = String(now.getSeconds()).padStart(2, '0');
      el.textContent = `${hours}:${minutes}:${seconds}`;
    }
  }

  async function loadData() {
    showLoading(true);
    countdownValue = refreshInterval;
    sourcePath = getSourcePathForRequest();
    
    try {
      // Load summary (optional sourcePath filters today's stats by SourceFile containing that path)
      const summaryUrl = sourcePath
        ? '/api/Dashboard/summary?sourcePath=' + encodeURIComponent(sourcePath)
        : '/api/Dashboard/summary';
      const summaryResponse = await Api.get(summaryUrl);
      if (summaryResponse && summaryResponse.Success && summaryResponse.Data) {
        updateAuthBadge(true);
        renderSummary(summaryResponse.Data);
        renderTopComputers(summaryResponse.Data.TopComputers || []);
        renderTopErrors(summaryResponse.Data.TopErrors || []);
        updateDashboardDateNote(summaryResponse.Data.SourceFilter || null);
      } else {
        updateAuthBadge(false, summaryResponse && summaryResponse.Error ? summaryResponse.Error : 'Failed to load summary');
        updateDashboardDateNote(sourcePath || null);
      }
      
      // Load recent logs
      const logsResponse = await Api.post('/api/Logs/search', {
        PageSize: 50,
        SortBy: 'Timestamp',
        SortDescending: true
      });
      
      if (logsResponse && logsResponse.Success && logsResponse.Data) {
        renderRecentLogs(logsResponse.Data.Items || []);
      }
      
      // Update last updated timestamp
      updateLastUpdated();
      
    } catch (err) {
      const msg = err && err.message ? err.message : 'Request failed';
      updateAuthBadge(false, msg);
      renderSummary({ TotalLogsToday: 0, ErrorsToday: 0, WarningsToday: 0, ActiveComputers: 0 });
      renderTopComputers([]);
      renderTopErrors([]);
      renderRecentLogs([]);
      updateDashboardDateNote(sourcePath || null);
    } finally {
      showLoading(false);
      hideInitialLoading();
    }
  }

  function ThemeManager() {
    this.theme = localStorage.getItem('dashboard-theme') ||
      (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    this.apply();
  }
  ThemeManager.prototype.toggle = function () {
    this.theme = this.theme === 'dark' ? 'light' : 'dark';
    this.apply();
    localStorage.setItem('dashboard-theme', this.theme);
  };
  ThemeManager.prototype.apply = function () {
    document.documentElement.setAttribute('data-theme', this.theme);
    const icon = document.querySelector('#themeToggle .theme-icon');
    if (icon) icon.textContent = this.theme === 'dark' ? '☀️' : '🌙';
  };

  function init() {
    // Load settings
    loadSettings();
    
    // Initialize theme
    var themeManager = new ThemeManager();
    if (themeToggle) themeToggle.addEventListener('click', function () { themeManager.toggle(); });
    
    // Initialize LogsRenderer
    if (typeof LogsRenderer !== 'undefined') {
      logsRenderer = new LogsRenderer({
        maxEntries: 50,
        showCopyButtons: true,
        showExpandable: true,
        showModal: true,
        onOpenModal: openModal
      });
    }
    
    // Apply settings to UI
    if (autoRefreshCheckbox) autoRefreshCheckbox.checked = autoRefresh;
    if (refreshIntervalSelect) refreshIntervalSelect.value = refreshInterval.toString();
    if (sourceFilterSelect) {
      sourceFilterSelect.value = sourcePath || '';
      updateDashboardDateNote(sourcePath || null);
    }
    
    // Event listeners
    if (refreshBtn) refreshBtn.addEventListener('click', loadData);
    
    if (sourceFilterSelect) {
      sourceFilterSelect.addEventListener('change', function () {
        sourcePath = getSourcePathForRequest();
        saveSettings();
        loadData();
      });
    }
    
    if (autoRefreshCheckbox) {
      autoRefreshCheckbox.addEventListener('change', function(e) {
        autoRefresh = e.target.checked;
        saveSettings();
        if (autoRefresh) {
          startAutoRefresh();
        } else {
          stopAutoRefresh();
          updateCountdown();
        }
      });
    }
    
    if (refreshIntervalSelect) {
      refreshIntervalSelect.addEventListener('change', function(e) {
        refreshInterval = parseInt(e.target.value) || 30;
        saveSettings();
        if (autoRefresh) {
          startAutoRefresh();
        }
      });
    }
    
    // Modal event listeners
    const modalClose = document.getElementById('modalClose');
    if (modalClose) modalClose.addEventListener('click', closeModal);
    
    const modalCopyMd = document.getElementById('modalCopyMd');
    if (modalCopyMd) modalCopyMd.addEventListener('click', copyModalAsMarkdown);
    
    const modalCopyJson = document.getElementById('modalCopyJson');
    if (modalCopyJson) modalCopyJson.addEventListener('click', copyModalAsJson);
    
    // Close modal on overlay click
    const modalOverlay = document.getElementById('logModal');
    if (modalOverlay) {
      modalOverlay.addEventListener('click', function(e) {
        if (e.target === modalOverlay) closeModal();
      });
    }
    
    // Close modal on Escape key
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') closeModal();
    });
    
    // Shortcuts button
    const shortcutsBtn = document.getElementById('shortcutsBtn');
    if (shortcutsBtn && typeof Shortcuts !== 'undefined') {
      shortcutsBtn.addEventListener('click', function() { Shortcuts.showHelp(); });
    }

    // Load source filters dynamically, then initial data load
    loadSourceFilters().then(function() {
      loadData();
      if (autoRefresh) {
        startAutoRefresh();
      }
    });
    
    // Initialize SSE for real-time updates
    initSSE();
  }
  
  function initSSE() {
    if (typeof SSE === 'undefined') {
      console.warn('SSE module not available');
      return;
    }
    
    // Initialize SSE connection
    SSE.init(true);
    
    // Handle connection status
    SSE.on('connection', function(data) {
      console.log('[Dashboard] SSE connection:', data.status);
      if (data.status === 'connected') {
        Toast.info('Real-time updates connected');
      } else if (data.status === 'error') {
        Toast.warning('Real-time connection lost, retrying...');
      }
    });
    
    // Handle log imports - refresh dashboard when new logs arrive
    SSE.on('log-imported', function(data) {
      console.log('[Dashboard] Log imported:', data);
      Toast.info(`${data.count} logs imported from ${data.sourceName}`);
      // Refresh data to show new logs
      loadData();
    });
    
    // Handle database stats updates
    SSE.on('database-stats', function(data) {
      console.log('[Dashboard] Database stats update:', data);
      // Could update stats in real-time if displayed on dashboard
    });
    
    // Handle alert triggered events
    SSE.on('alert-triggered', function(data) {
      console.log('[Dashboard] Alert triggered:', data);
      Toast.warning(`Alert: ${data.filterName} matched ${data.matchCount} entries`);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
