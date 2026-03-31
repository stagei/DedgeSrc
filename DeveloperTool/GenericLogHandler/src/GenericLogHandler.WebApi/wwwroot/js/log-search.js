/**
 * Generic Log Handler - Log Search page
 * Features: search, pagination, open in new window, expandable rows, modal with copy
 */

(function () {
  // DOM elements
  const loadingOverlay = document.getElementById('loadingOverlay');
  const authBadge = document.getElementById('authBadge');
  const themeToggle = document.getElementById('themeToggle');
  const fromDate = document.getElementById('fromDate');
  const toDate = document.getElementById('toDate');
  const levelsSelect = document.getElementById('levels');
  const computerName = document.getElementById('computerName');
  const userName = document.getElementById('userName');
  const messageText = document.getElementById('messageText');
  const regexPattern = document.getElementById('regexPattern');
  const searchBtn = document.getElementById('searchBtn');
  const searchNewWindowBtn = document.getElementById('searchNewWindowBtn');
  const exportCsvBtn = document.getElementById('exportCsvBtn');
  const exportExcelBtn = document.getElementById('exportExcelBtn');
  const resultsBody = document.getElementById('resultsBody');
  const resultsEmpty = document.getElementById('resultsEmpty');
  const resultsError = document.getElementById('resultsError');
  const resultsSummary = document.getElementById('resultsSummary');
  const paginationBar = document.getElementById('paginationBar');
  const prevPage = document.getElementById('prevPage');
  const nextPage = document.getElementById('nextPage');
  const pageInfo = document.getElementById('pageInfo');

  let currentPage = 1;
  const pageSize = 50;
  let totalCount = 0;
  let currentResults = [];
  let currentModalLog = null;
  let logsRenderer = null;
  const MAX_SEARCH_HISTORY = 10;

  // Search history functions
  function getSearchHistory() {
    try {
      const saved = localStorage.getItem('loghandler-search-history');
      return saved ? JSON.parse(saved) : [];
    } catch (e) {
      return [];
    }
  }

  function saveSearchToHistory() {
    var params = buildSearchParams(1);
    var description = buildSearchDescription(params);
    if (!description) return;

    var history = getSearchHistory();
    // Remove duplicate if exists
    history = history.filter(function(h) { return h.description !== description; });
    // Add to front
    history.unshift({
      description: description,
      params: params,
      timestamp: new Date().toISOString()
    });
    // Keep only MAX_SEARCH_HISTORY items
    history = history.slice(0, MAX_SEARCH_HISTORY);
    localStorage.setItem('loghandler-search-history', JSON.stringify(history));
    renderSearchHistory();
  }

  function buildSearchDescription(params) {
    var parts = [];
    if (params.Levels && params.Levels.length > 0) parts.push(params.Levels.join('/'));
    if (params.ComputerName) parts.push('Computer: ' + params.ComputerName);
    if (params.UserName) parts.push('User: ' + params.UserName);
    if (params.MessageText) parts.push('"' + params.MessageText.substring(0, 30) + (params.MessageText.length > 30 ? '...' : '') + '"');
    if (params.RegexPattern) parts.push('Regex: ' + params.RegexPattern.substring(0, 20));
    return parts.length > 0 ? parts.join(', ') : null;
  }

  function applySearchFromHistory(historyItem) {
    if (historyItem.params.Levels && historyItem.params.Levels.length > 0) {
      Array.from(levelsSelect.options).forEach(function(opt) {
        opt.selected = historyItem.params.Levels.includes(opt.value);
      });
    }
    if (historyItem.params.ComputerName && computerName) computerName.value = historyItem.params.ComputerName;
    if (historyItem.params.UserName && userName) userName.value = historyItem.params.UserName;
    if (historyItem.params.MessageText && messageText) messageText.value = historyItem.params.MessageText;
    if (historyItem.params.RegexPattern && regexPattern) regexPattern.value = historyItem.params.RegexPattern;
    // Use 24h preset for dates
    applyDatePreset('24h');
    // Run the search
    runSearch(1);
    // Close dropdown
    closeSearchHistoryDropdown();
  }

  function clearSearchHistory() {
    localStorage.removeItem('loghandler-search-history');
    renderSearchHistory();
  }

  function renderSearchHistory() {
    var container = document.getElementById('searchHistoryDropdown');
    if (!container) return;

    var history = getSearchHistory();
    if (history.length === 0) {
      container.innerHTML = '<div class="search-history-empty">No recent searches</div>';
      return;
    }

    var html = history.map(function(h, i) {
      var ago = getRelativeTime(h.timestamp);
      return '<div class="search-history-item" data-index="' + i + '">' +
        '<span class="search-history-text">' + escapeHtml(h.description) + '</span>' +
        '<span class="search-history-time">' + ago + '</span>' +
      '</div>';
    }).join('');
    html += '<div class="search-history-clear" id="clearSearchHistory">Clear history</div>';
    container.innerHTML = html;

    // Add click handlers
    container.querySelectorAll('.search-history-item').forEach(function(item) {
      item.addEventListener('click', function() {
        var index = parseInt(this.dataset.index);
        applySearchFromHistory(history[index]);
      });
    });
    var clearBtn = document.getElementById('clearSearchHistory');
    if (clearBtn) {
      clearBtn.addEventListener('click', clearSearchHistory);
    }
  }

  function getRelativeTime(timestamp) {
    var date = new Date(timestamp);
    var now = new Date();
    var diff = Math.floor((now - date) / 1000);
    if (diff < 60) return 'just now';
    if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
    if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
    return Math.floor(diff / 86400) + 'd ago';
  }

  function toggleSearchHistoryDropdown() {
    var dropdown = document.getElementById('searchHistoryDropdown');
    if (dropdown) {
      dropdown.classList.toggle('hidden');
      if (!dropdown.classList.contains('hidden')) {
        renderSearchHistory();
      }
    }
  }

  function closeSearchHistoryDropdown() {
    var dropdown = document.getElementById('searchHistoryDropdown');
    if (dropdown) dropdown.classList.add('hidden');
  }

  function showLoading(show) {
    if (loadingOverlay) loadingOverlay.classList.toggle('hidden', !show);
  }

  function formatDateTimeLocal(d) {
    var y = d.getFullYear();
    var m = String(d.getMonth() + 1).padStart(2, '0');
    var day = String(d.getDate()).padStart(2, '0');
    var h = String(d.getHours()).padStart(2, '0');
    var min = String(d.getMinutes()).padStart(2, '0');
    return y + '-' + m + '-' + day + 'T' + h + ':' + min;
  }

  function setDefaultDates() {
    var now = new Date();
    var to = new Date(now);
    to.setMinutes(to.getMinutes() - to.getTimezoneOffset());
    var from = new Date(now);
    from.setDate(from.getDate() - 1);
    from.setMinutes(from.getMinutes() - from.getTimezoneOffset());
    if (fromDate && !fromDate.value) fromDate.value = formatDateTimeLocal(from);
    if (toDate && !toDate.value) toDate.value = formatDateTimeLocal(to);
  }

  function applyDatePreset(preset) {
    var now = new Date();
    var from = new Date(now);
    var to = new Date(now);
    
    switch (preset) {
      case '1h':
        from.setHours(from.getHours() - 1);
        break;
      case 'today':
        from.setHours(0, 0, 0, 0);
        break;
      case '24h':
        from.setHours(from.getHours() - 24);
        break;
      case '7d':
        from.setDate(from.getDate() - 7);
        break;
      case '30d':
        from.setDate(from.getDate() - 30);
        break;
      default:
        return;
    }
    
    if (fromDate) fromDate.value = formatDateTimeLocal(from);
    if (toDate) toDate.value = formatDateTimeLocal(to);
    
    // Update active state on preset buttons
    document.querySelectorAll('.btn-preset').forEach(function(btn) {
      btn.classList.toggle('active', btn.dataset.preset === preset);
    });
  }

  function buildSearchParams(page) {
    var p = {
      Page: page || currentPage,
      PageSize: pageSize,
      SortBy: 'Timestamp',
      SortDescending: true
    };
    if (fromDate && fromDate.value) p.FromDate = fromDate.value;
    if (toDate && toDate.value) p.ToDate = toDate.value;
    var lev = levelsSelect && levelsSelect.selectedOptions ? Array.from(levelsSelect.selectedOptions).map(function (o) { return o.value; }).filter(Boolean) : [];
    if (lev.length) p.Levels = lev;
    if (computerName && computerName.value.trim()) p.ComputerName = computerName.value.trim();
    if (userName && userName.value.trim()) p.UserName = userName.value.trim();
    if (messageText && messageText.value.trim()) p.MessageText = messageText.value.trim();
    if (regexPattern && regexPattern.value.trim()) p.RegexPattern = regexPattern.value.trim();
    return p;
  }

  function updateAuthBadge(authenticated, errorMessage) {
    if (!authBadge) return;
    var icon = authBadge.querySelector('.auth-badge-icon');
    var text = authBadge.querySelector('.auth-badge-text');
    var role = authBadge.querySelector('.auth-badge-role');
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
    var date = typeof d === 'string' ? new Date(d) : d;
    if (isNaN(date.getTime())) return '–';
    // Format: YYYY-MM-DD HH:mm:ss
    var year = date.getFullYear();
    var month = String(date.getMonth() + 1).padStart(2, '0');
    var day = String(date.getDate()).padStart(2, '0');
    var hours = String(date.getHours()).padStart(2, '0');
    var minutes = String(date.getMinutes()).padStart(2, '0');
    var seconds = String(date.getSeconds()).padStart(2, '0');
    return year + '-' + month + '-' + day + ' ' + hours + ':' + minutes + ':' + seconds;
  }

  function escapeHtml(s) {
    if (s == null) return '';
    var div = document.createElement('div');
    div.textContent = s;
    return div.innerHTML;
  }

  function renderResults(data) {
    if (!resultsBody) return;
    
    if (resultsEmpty) resultsEmpty.classList.add('hidden');
    if (resultsError) { resultsError.classList.add('hidden'); resultsError.textContent = ''; }

    var items = data && data.Items ? data.Items : [];
    currentResults = items;
    totalCount = data && data.TotalCount !== undefined ? data.TotalCount : 0;

    if (resultsSummary) resultsSummary.textContent = totalCount + ' total';

    if (items.length === 0) {
      resultsBody.innerHTML = '';
      if (resultsEmpty) resultsEmpty.classList.remove('hidden');
      if (paginationBar) paginationBar.classList.add('hidden');
      return;
    }

    // Use LogsRenderer
    if (logsRenderer) {
      logsRenderer.render(resultsBody, items);
    }

    var totalPages = Math.ceil(totalCount / pageSize) || 1;
    if (paginationBar) {
      paginationBar.classList.remove('hidden');
      if (pageInfo) pageInfo.textContent = 'Page ' + currentPage + ' of ' + totalPages;
      if (prevPage) prevPage.disabled = currentPage <= 1;
      if (nextPage) nextPage.disabled = currentPage >= totalPages;
    }
  }

  function showError(msg) {
    if (resultsBody) resultsBody.innerHTML = '';
    if (resultsEmpty) resultsEmpty.classList.add('hidden');
    if (resultsError) {
      resultsError.textContent = msg;
      resultsError.classList.remove('hidden');
    }
    if (paginationBar) paginationBar.classList.add('hidden');
    if (resultsSummary) resultsSummary.textContent = '';
  }

  async function runSearch(page) {
    if (page !== undefined) currentPage = page;
    setDefaultDates();
    var params = buildSearchParams(currentPage);
    showLoading(true);
    try {
      var response = await Api.post('/api/Logs/search', params);
      if (response && response.Success) {
        updateAuthBadge(true);
        renderResults(response.Data);
        // Save to search history on first page only
        if (currentPage === 1) {
          saveSearchToHistory();
        }
      } else {
        updateAuthBadge(false, response && response.Error ? response.Error : 'Search failed');
        showError(response && response.Error ? response.Error : 'Search failed');
      }
    } catch (err) {
      var msg = err && err.message ? err.message : 'Request failed';
      updateAuthBadge(false, msg);
      showError(msg);
    } finally {
      showLoading(false);
    }
  }

  // Open search in new window
  function openSearchInNewWindow() {
    setDefaultDates();
    var params = buildSearchParams(1);
    var baseHref = window.location.origin + (Api.baseUrl || '');
    var theme = document.documentElement.getAttribute('data-theme') || 'light';
    
    // Create a new window with search results
    var newWindow = window.open('', '_blank', 'width=1200,height=800');
    if (!newWindow) {
      alert('Please allow popups for this site');
      return;
    }
    
    // Build the HTML for the new window
    var html = `
<!DOCTYPE html>
<html lang="en" data-theme="${theme}">
<head>
    <meta charset="UTF-8">
    <title>Search Results - Generic Log Handler</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="${baseHref}/api/DedgeAuth/ui/common.css">
    <link rel="stylesheet" href="${baseHref}/css/dashboard.css">
    <style>
        body { padding: 1rem; }
        .search-info { 
            background: var(--bg-card); 
            padding: 1rem; 
            border-radius: var(--radius); 
            margin-bottom: 1rem;
            border: 1px solid var(--border-color);
        }
        .search-info h2 { margin: 0 0 0.5rem 0; font-size: 1.2rem; }
        .search-criteria { font-size: 0.9rem; color: var(--text-secondary); }
    </style>
</head>
<body>
    <div class="search-info">
        <h2>🔍 Search Results</h2>
        <div class="search-criteria" id="searchCriteria">Loading...</div>
    </div>
    <div class="panel">
        <div class="panel-header">
            <span class="panel-title">Results</span>
            <span class="panel-summary" id="resultCount"></span>
        </div>
        <div class="panel-body">
            <table class="data-table logs-table">
                <thead>
                    <tr>
                        <th style="width: 160px;">Timestamp</th>
                        <th style="width: 80px;">Level</th>
                        <th style="width: 140px;">Computer</th>
                        <th>Message</th>
                        <th style="width: 180px;">Context</th>
                    </tr>
                </thead>
                <tbody id="resultsBody"></tbody>
            </table>
        </div>
    </div>
    <script src="${baseHref}/js/api.js"></script>
    <script src="${baseHref}/js/components/logs-renderer.js"></script>
    <script>
        var searchParams = ${JSON.stringify(params)};
        
        // Show search criteria
        var criteriaEl = document.getElementById('searchCriteria');
        var parts = [];
        if (searchParams.FromDate) parts.push('From: ' + searchParams.FromDate);
        if (searchParams.ToDate) parts.push('To: ' + searchParams.ToDate);
        if (searchParams.Levels) parts.push('Levels: ' + searchParams.Levels.join(', '));
        if (searchParams.ComputerName) parts.push('Computer: ' + searchParams.ComputerName);
        if (searchParams.MessageText) parts.push('Message: ' + searchParams.MessageText);
        criteriaEl.textContent = parts.length ? parts.join(' | ') : 'All logs';
        
        // Run search
        Api.post('/api/Logs/search', searchParams).then(function(response) {
            var items = response && response.Data && response.Data.Items ? response.Data.Items : [];
            document.getElementById('resultCount').textContent = items.length + ' entries';
            
            if (items.length === 0) {
                document.getElementById('resultsBody').innerHTML = '<tr><td colspan="5" class="empty-state">No results found</td></tr>';
                return;
            }
            
            var renderer = new LogsRenderer({
                maxEntries: 500,
                showCopyButtons: true,
                showExpandable: true,
                showModal: false
            });
            renderer.render(document.getElementById('resultsBody'), items);
        }).catch(function(err) {
            document.getElementById('resultsBody').innerHTML = '<tr><td colspan="5" class="empty-state" style="color: var(--error-color);">' + (err.message || 'Error') + '</td></tr>';
        });
    </script>
</body>
</html>`;
    
    newWindow.document.write(html);
    newWindow.document.close();
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
    let toast = document.getElementById('search-toast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'search-toast';
      toast.className = 'toast-notification';
      document.body.appendChild(toast);
    }
    toast.textContent = message;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 2000);
  }

  async function exportFile(endpoint, filenamePrefix) {
    setDefaultDates();
    var body = buildSearchParams(1);
    showLoading(true);
    try {
      var res = await fetch(Api.baseUrl + '/api/Logs/export/' + endpoint, {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      if (res.status === 401) {
        updateAuthBadge(false, 'Access denied');
        return;
      }
      if (!res.ok) {
        var text = await res.text();
        showError('Export failed: ' + (text || res.status));
        return;
      }
      var blob = await res.blob();
      var disp = res.headers.get('Content-Disposition');
      var filename = filenamePrefix + '_' + new Date().toISOString().slice(0, 19).replace(/[-:T]/g, '').replace(/\..*/, '') + (endpoint === 'csv' ? '.csv' : '.xlsx');
      if (disp) {
        var m = disp.match(/filename="?([^";]+)"?/);
        if (m && m[1]) filename = m[1];
      }
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = filename;
      a.click();
      URL.revokeObjectURL(a.href);
    } catch (err) {
      showError(err && err.message ? err.message : 'Export failed');
    } finally {
      showLoading(false);
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
    var icon = document.querySelector('#themeToggle .theme-icon');
    if (icon) icon.textContent = this.theme === 'dark' ? '☀️' : '🌙';
  };

  function init() {
    var themeManager = new ThemeManager();
    if (themeToggle) themeToggle.addEventListener('click', function () { themeManager.toggle(); });
    
    // Initialize LogsRenderer
    if (typeof LogsRenderer !== 'undefined') {
      logsRenderer = new LogsRenderer({
        maxEntries: 100,
        showCopyButtons: true,
        showExpandable: true,
        showModal: true,
        onOpenModal: openModal
      });
    }
    
    // Date preset buttons
    document.querySelectorAll('.btn-preset').forEach(function(btn) {
      btn.addEventListener('click', function() {
        applyDatePreset(this.dataset.preset);
      });
    });

    // Search buttons
    if (searchBtn) searchBtn.addEventListener('click', function () { runSearch(1); });
    if (searchNewWindowBtn) searchNewWindowBtn.addEventListener('click', openSearchInNewWindow);
    
    // Search history
    var searchHistoryBtn = document.getElementById('searchHistoryBtn');
    if (searchHistoryBtn) {
      searchHistoryBtn.addEventListener('click', toggleSearchHistoryDropdown);
    }
    // Close dropdown when clicking outside
    document.addEventListener('click', function(e) {
      if (!e.target.closest('.search-history-container')) {
        closeSearchHistoryDropdown();
      }
    });
    
    // Pagination
    if (prevPage) prevPage.addEventListener('click', function () { if (currentPage > 1) runSearch(currentPage - 1); });
    if (nextPage) nextPage.addEventListener('click', function () { if (currentPage < Math.ceil(totalCount / pageSize)) runSearch(currentPage + 1); });
    
    // Export buttons
    if (exportCsvBtn) exportCsvBtn.addEventListener('click', function () { exportFile('csv', 'logs_export'); });
    if (exportExcelBtn) exportExcelBtn.addEventListener('click', function () { exportFile('excel', 'logs_export'); });
    
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

    setDefaultDates();
    if (resultsEmpty) resultsEmpty.classList.remove('hidden');
    if (resultsError) resultsError.classList.add('hidden');
    if (paginationBar) paginationBar.classList.add('hidden');
    updateAuthBadge(false, 'Run a search to verify access');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
