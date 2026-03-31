(function () {
  'use strict';

  // ── State ────────────────────────────────────────────
  let currentUser = null;
  let rags = [];
  const rebuildPollers = {};

  const $ = (sel, ctx) => (ctx || document).querySelector(sel);
  const $$ = (sel, ctx) => [...(ctx || document).querySelectorAll(sel)];
  const mainContent = () => $('#mainContent');

  // ── Init ─────────────────────────────────────────────
  document.addEventListener('DOMContentLoaded', async () => {
    await loadUser();
    handleRoute();
    window.addEventListener('hashchange', handleRoute);
    $('#logoutBtn').addEventListener('click', logout);
    $('#sidebarToggle')?.addEventListener('click', () =>
      $('#sidebar').classList.toggle('open'));
  });

  // ── Auth ─────────────────────────────────────────────
  async function loadUser() {
    try {
      const res = await fetch('api/DedgeAuth/me');
      if (res.status === 401) {
        // Not logged in — redirect to DedgeAuth with the current full URL as returnUrl
        window.location.href = '/DedgeAuth/login.html?returnUrl=' + encodeURIComponent(window.location.href);
        return;
      }
      if (res.ok) {
        currentUser = await res.json();
        $('#userName').textContent = currentUser.name || currentUser.email || 'User';
        $('#userAvatar').textContent = (currentUser.name || 'U')[0].toUpperCase();
        const role = getAppRole();
        $('#userRole').textContent = role || `Level ${currentUser.globalAccessLevel ?? '?'}`;
        updateAdminVisibility();
      }
    } catch { /* auth disabled or offline */ }
  }

  function getAppRole() {
    if (!currentUser) return null;
    const perms = currentUser.appPermissions;
    if (perms && perms.AiDocNew) return perms.AiDocNew;
    if (perms && perms.AiDoc) return perms.AiDoc;
    const level = currentUser.globalAccessLevel ?? 0;
    if (level >= 3) return 'Admin';
    if (level >= 1) return 'User';
    return 'ReadOnly';
  }

  function isAdmin() {
    const role = getAppRole();
    return role === 'Admin';
  }

  function updateAdminVisibility() {
    $$('.admin-only').forEach(el => {
      el.classList.toggle('visible', isAdmin());
    });
  }

  async function logout() {
    try {
      await fetch('api/DedgeAuth/logout', { method: 'POST' });
    } catch { /* ignore */ }
    window.location.href = '/DedgeAuth/login.html';
  }

  // ── Router ───────────────────────────────────────────
  function handleRoute() {
    const hash = location.hash || '#/';
    const path = hash.slice(1);

    $$('.nav-item').forEach(el => {
      const route = el.getAttribute('data-route');
      el.classList.toggle('active', route === path);
    });

    if (path === '/' || path === '') return renderDashboard();
    if (path === '/rags') return renderDashboard();
    if (path === '/rags/new') return renderCreateRag();
    if (path.startsWith('/rags/')) return renderRagDetail(path.split('/rags/')[1]);
    if (path.startsWith('/integration/')) return renderIntegration(path.split('/integration/')[1]);
    if (path === '/environment') return renderEnvironment();
    if (path === '/services') return renderServices();
    if (path === '/backup') return renderBackup();
    if (path === '/ollama') return renderOllamaPlayground();

    renderDashboard();
  }

  // ── API ──────────────────────────────────────────────
  async function api(url, options = {}) {
    const res = await fetch(url, {
      headers: { 'Content-Type': 'application/json', ...options.headers },
      ...options
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: res.statusText }));
      throw new Error(err.error || res.statusText);
    }
    if (res.status === 204) return null;
    return res.json();
  }

  async function fetchRags() {
    rags = await api('api/rags');
    return rags;
  }

  // ── Views ────────────────────────────────────────────

  // Dashboard
  async function renderDashboard() {
    const mc = mainContent();
    mc.innerHTML = '<div class="page-loading"><div class="spinner"></div><p>Loading RAG indexes...</p></div>';

    try {
      await fetchRags();
    } catch (e) {
      mc.innerHTML = `<div class="empty-state"><h3>Could not load RAG indexes</h3><p>${esc(e.message)}</p></div>`;
      return;
    }

    let html = `
      <div class="page-header">
        <div class="page-header-actions">
          <div>
            <h1>RAG Indexes</h1>
            <p>${rags.length} index${rags.length !== 1 ? 'es' : ''} registered</p>
          </div>
          ${isAdmin() ? '<a href="#/rags/new" class="btn btn-primary">+ Create New RAG</a>' : ''}
        </div>
      </div>`;

    if (rags.length === 0) {
      html += `<div class="empty-state">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/></svg>
        <h3>No RAG indexes yet</h3>
        <p>Create your first RAG index to get started.</p>
      </div>`;
    } else {
      html += '<div class="card-grid">';
      for (const rag of rags) {
        html += renderRagCard(rag);
      }
      html += '</div>';
    }

    mc.innerHTML = html;

    $$('[data-action="rebuild"]', mc).forEach(btn =>
      btn.addEventListener('click', (e) => confirmRebuild(e.target.closest('[data-action]').dataset.name)));
    $$('[data-action="cancel-rebuild"]', mc).forEach(btn =>
      btn.addEventListener('click', (e) => cancelRebuild(e.target.closest('[data-action]').dataset.name)));
    $$('[data-action="delete"]', mc).forEach(btn =>
      btn.addEventListener('click', (e) => confirmDelete(e.target.closest('[data-action]').dataset.name)));

    for (const rag of rags) {
      if (rag.status === 'building') startRebuildPoller(rag.name);
    }
  }

  function renderRagCard(rag) {
    const statusClass = `badge-${rag.status}`;
    const statusLabel = rag.status === 'no-index' ? 'No Index' :
                         rag.status === 'building' ? 'Building...' :
                         rag.status.charAt(0).toUpperCase() + rag.status.slice(1);
    const builtAt = rag.builtAt ? new Date(rag.builtAt).toLocaleString() : 'Never';
    const sizeStr = formatBytes(rag.totalSizeBytes);
    const isBuilding = rag.status === 'building';

    return `
      <div class="card ${isBuilding ? 'card-building' : ''}" id="card-${esc(rag.name)}">
        <div class="card-header">
          <div>
            <div class="card-title">${esc(rag.name)}</div>
            <div class="card-description">${esc(rag.description)}</div>
          </div>
          <span class="badge ${statusClass}">${isBuilding ? '<span class="spinner-sm"></span>' : ''}${statusLabel}</span>
        </div>
        <div class="rebuild-progress" id="rebuild-progress-${esc(rag.name)}" ${isBuilding ? '' : 'style="display:none"'}>
          <div class="rebuild-progress-bar-bg"><div class="rebuild-progress-bar" style="width:0%"></div></div>
          <div class="rebuild-progress-text">Starting build...</div>
        </div>
        <div class="card-stats">
          <div class="stat">
            <span class="stat-label">Port</span>
            <span class="stat-value">${rag.port}</span>
          </div>
          <div class="stat">
            <span class="stat-label">Sources</span>
            <span class="stat-value">${rag.sourceFileCount.toLocaleString()} files</span>
          </div>
          <div class="stat">
            <span class="stat-label">Size</span>
            <span class="stat-value">${sizeStr}</span>
          </div>
          <div class="stat">
            <span class="stat-label">Last Built</span>
            <span class="stat-value" style="font-size:13px">${builtAt}</span>
          </div>
        </div>
        <div class="card-actions">
          <a href="#/rags/${esc(rag.name)}" class="btn btn-secondary btn-sm" ${isBuilding ? 'tabindex="-1" style="pointer-events:none;opacity:.5"' : ''}>View Details</a>
          ${isAdmin() ? `
            <button class="btn btn-success btn-sm" data-action="rebuild" data-name="${esc(rag.name)}" ${isBuilding ? 'disabled' : ''}>Rebuild</button>
            ${isBuilding ? `<button class="btn btn-warning btn-sm" data-action="cancel-rebuild" data-name="${esc(rag.name)}">Cancel</button>` : ''}
            <button class="btn btn-danger btn-sm" data-action="delete" data-name="${esc(rag.name)}" ${isBuilding ? 'disabled' : ''}>Delete</button>
          ` : ''}
        </div>
      </div>`;
  }

  // RAG Detail
  async function renderRagDetail(name) {
    const mc = mainContent();
    mc.innerHTML = '<div class="page-loading"><div class="spinner"></div><p>Loading RAG details...</p></div>';

    let rag, sources;
    try {
      [rag, sources] = await Promise.all([
        api(`api/rags/${encodeURIComponent(name)}`),
        api(`api/rags/${encodeURIComponent(name)}/sources`)
      ]);
    } catch (e) {
      mc.innerHTML = `<div class="empty-state"><h3>RAG not found</h3><p>${esc(e.message)}</p><a href="#/" class="btn btn-secondary mt-4">Back to Dashboard</a></div>`;
      return;
    }

    const statusClass = `badge-${rag.status}`;
    const statusLabel = rag.status === 'no-index' ? 'No Index' : rag.status.charAt(0).toUpperCase() + rag.status.slice(1);
    const builtAt = rag.builtAt ? new Date(rag.builtAt).toLocaleString() : 'Never';

    const isBuilding = rag.status === 'building';

    let html = `
      <div class="page-header">
        <div class="page-header-actions">
          <div>
            <h1>${esc(rag.name)}</h1>
            <p>${esc(rag.description)}</p>
          </div>
          <div style="display:flex;gap:8px;align-items:center">
            <span class="badge ${statusClass}">${statusLabel}</span>
            ${isAdmin() ? `
              <button class="btn btn-success btn-sm" id="rebuildBtn" ${isBuilding ? 'disabled' : ''}>Rebuild Index</button>
              <button class="btn btn-danger btn-sm" id="deleteBtn">Delete RAG</button>
            ` : ''}
          </div>
        </div>
      </div>

      ${isBuilding ? `<div class="detail-card" style="margin-bottom:20px">
        <h3>Build in Progress</h3>
        <div class="rebuild-progress" id="rebuild-progress-${esc(rag.name)}">
          <div class="rebuild-progress-bar-bg"><div class="rebuild-progress-bar" style="width:0%"></div></div>
          <div class="rebuild-progress-text">Loading status...</div>
        </div>
      </div>` : ''}

      <div class="detail-grid">
        <div class="detail-card">
          <h3>Index Information</h3>
          <table class="data-table">
            <tr><td>Port</td><td><strong>${rag.port}</strong></td></tr>
            <tr><td>Status</td><td><span class="badge ${statusClass}">${statusLabel}</span></td></tr>
            <tr><td>Last Built</td><td>${builtAt}</td></tr>
            <tr><td>Source Hash</td><td><code>${esc(rag.sourceHash || 'N/A')}</code></td></tr>
          </table>
        </div>

        <div class="detail-card">
          <h3>Statistics</h3>
          <table class="data-table">
            <tr><td>Source Files</td><td><strong>${rag.sourceFileCount.toLocaleString()}</strong></td></tr>
            <tr><td>Total Size</td><td>${formatBytes(rag.totalSizeBytes)}</td></tr>
            <tr><td>Source Folders</td><td>${rag.sourceFolders.length}</td></tr>
          </table>
        </div>

        ${rag.uncPath ? `<div class="detail-card full-width">
          <h3>Network Path</h3>
          <div class="unc-path-box">
            <span>${esc(rag.uncPath)}</span>
            <button class="copy-unc-btn" onclick="navigator.clipboard.writeText('${esc(rag.uncPath).replace(/\\/g, '\\\\')}').then(()=>{this.textContent='Copied!';setTimeout(()=>this.textContent='Copy',2000)})">Copy</button>
          </div>
          <p class="form-help" style="margin-top:6px">Copy files to this path and rebuild the index</p>
        </div>` : ''}

        <div class="detail-card full-width">
          <h3>Source Folders</h3>
          ${sources.length > 0 ? `
            <ul class="source-list">
              ${sources.map(s => `
                <li class="source-item">
                  <div class="source-name">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
                    ${esc(s.relativePath)}
                  </div>
                  <span class="source-meta">${formatBytes(s.sizeBytes)}</span>
                </li>
              `).join('')}
            </ul>
          ` : '<p class="text-muted">No source folders found. Add markdown files to the library folder.</p>'}
        </div>
      </div>

      <!-- Query test -->
      <div class="query-panel">
        <h3 style="margin-bottom:12px">Test Query</h3>
        <div class="query-input-row">
          <input type="text" id="queryInput" placeholder="Ask a question..." />
          <button class="btn btn-primary" id="queryBtn">Search</button>
        </div>
        <div class="query-results" id="queryResults"></div>
      </div>

      <div style="margin-top:20px"><a href="#/" class="btn btn-secondary">Back to Dashboard</a></div>`;

    mc.innerHTML = html;

    $('#queryBtn', mc)?.addEventListener('click', () => runQuery(name));
    $('#queryInput', mc)?.addEventListener('keydown', (e) => { if (e.key === 'Enter') runQuery(name); });
    $('#rebuildBtn', mc)?.addEventListener('click', () => confirmRebuild(name));
    $('#deleteBtn', mc)?.addEventListener('click', () => confirmDelete(name));

    if (isBuilding) startRebuildPoller(name);
  }

  async function runQuery(ragName) {
    const input = $('#queryInput');
    const results = $('#queryResults');
    const query = input.value.trim();
    if (!query) return;

    results.innerHTML = '<div class="page-loading" style="height:auto;padding:20px"><div class="spinner"></div></div>';

    try {
      const data = await api(`api/rags/${encodeURIComponent(ragName)}/query?q=${encodeURIComponent(query)}&n=5`);
      if (!data || (Array.isArray(data) && data.length === 0)) {
        results.innerHTML = '<p class="text-muted mt-4">No results found.</p>';
        return;
      }

      const items = data.results || data.documents?.[0] || data;
      if (Array.isArray(items) && items.length > 0) {
        results.innerHTML = items.map((item, i) => {
          const content = typeof item === 'string' ? item : (item.content || item.document || JSON.stringify(item));
          const source = item.source || item.metadata?.source || `Result ${i + 1}`;
          return `<div class="query-result-item"><div class="source">${esc(String(source))}</div><div class="content">${esc(String(content).substring(0, 500))}</div></div>`;
        }).join('');
      } else {
        results.innerHTML = `<pre style="background:#f8fafc;padding:12px;border-radius:8px;font-size:12px;overflow:auto">${esc(JSON.stringify(data, null, 2))}</pre>`;
      }
    } catch (e) {
      results.innerHTML = `<p style="color:var(--color-danger)" class="mt-4">${esc(e.message)}</p>`;
    }
  }

  // Create RAG (two-step wizard)
  function renderCreateRag() {
    if (!isAdmin()) {
      mainContent().innerHTML = '<div class="empty-state"><h3>Access Denied</h3><p>Admin role required to create RAG indexes.</p></div>';
      return;
    }

    let createdRag = null;
    let selectedFiles = [];

    mainContent().innerHTML = `
      <div class="page-header"><h1>Create New RAG Index</h1><p>Register a new RAG knowledge base</p></div>

      <!-- Step 1: Create -->
      <div class="wizard-step active" id="wizardStep1">
        <div class="form-card">
          <form id="createForm">
            <div class="form-group">
              <label for="ragName">RAG Name</label>
              <input type="text" id="ragName" placeholder="e.g. my-docs" required pattern="[a-z0-9][a-z0-9\\-]*[a-z0-9]" />
              <span class="form-help">Lowercase letters, numbers, and hyphens only (2-64 chars)</span>
            </div>
            <div class="form-group">
              <label for="ragDesc">Description</label>
              <input type="text" id="ragDesc" placeholder="e.g. My project documentation" required />
            </div>
            <div class="form-group">
              <label for="ragPort">Port</label>
              <input type="number" id="ragPort" placeholder="e.g. 8487" min="1024" max="65535" required />
              <span class="form-help">HTTP port for this RAG server (must be unique)</span>
            </div>
            <div style="display:flex;gap:8px;margin-top:24px">
              <button type="submit" class="btn btn-primary">Create RAG</button>
              <a href="#/" class="btn btn-secondary">Cancel</a>
            </div>
          </form>
        </div>
      </div>

      <!-- Step 2: Add files -->
      <div class="wizard-step" id="wizardStep2">
        <div class="form-card" style="max-width:700px">
          <div class="success-icon">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6L9 17l-5-5"/></svg>
          </div>
          <h3 style="margin-bottom:4px">RAG Created Successfully</h3>
          <p class="text-muted" style="margin-bottom:20px">Now add source files to your RAG index.</p>

          <div class="form-group">
            <label>Copy files via network path</label>
            <div class="unc-path-box">
              <span id="uncPathText"></span>
              <button class="copy-unc-btn" id="copyUncBtn">Copy</button>
            </div>
            <span class="form-help">Open this path in File Explorer and paste your documents</span>
          </div>

          <div class="form-group">
            <label>Or upload files directly</label>
            <div class="drop-zone" id="dropZone">
              <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
              <div class="drop-zone-title">Drop files here or click to browse</div>
              <div class="drop-zone-hint">Supported: .md, .txt, .pdf, .docx</div>
            </div>
            <input type="file" id="fileInput" multiple accept=".md,.txt,.pdf,.docx" style="display:none" />
          </div>

          <ul class="file-list" id="fileList" style="display:none"></ul>

          <div class="upload-progress" id="uploadProgress" style="display:none">
            <div class="upload-progress-bar-bg"><div class="upload-progress-bar" id="uploadBar"></div></div>
            <div class="upload-progress-text" id="uploadText">Uploading...</div>
          </div>

          <div style="display:flex;gap:8px;margin-top:20px;flex-wrap:wrap">
            <button class="btn btn-primary" id="uploadBtn" disabled>Upload Files</button>
            <button class="btn btn-success" id="rebuildAfterUploadBtn" style="display:none">Rebuild Index</button>
            <a href="#/" class="btn btn-secondary">Go to Dashboard</a>
          </div>
        </div>
      </div>`;

    $('#createForm').addEventListener('submit', async (e) => {
      e.preventDefault();
      const btn = e.target.querySelector('[type="submit"]');
      btn.disabled = true;
      btn.textContent = 'Creating...';

      try {
        createdRag = await api('api/rags', {
          method: 'POST',
          body: JSON.stringify({
            name: $('#ragName').value.trim(),
            description: $('#ragDesc').value.trim(),
            port: parseInt($('#ragPort').value)
          })
        });
        showToast('RAG index created successfully', 'success');
        $('#wizardStep1').classList.remove('active');
        $('#wizardStep2').classList.add('active');
        $('#uncPathText').textContent = createdRag.uncPath || '';
        setupUploadHandlers();
      } catch (err) {
        showToast(err.message, 'error');
        btn.disabled = false;
        btn.textContent = 'Create RAG';
      }
    });

    function setupUploadHandlers() {
      const dropZone = $('#dropZone');
      const fileInput = $('#fileInput');

      $('#copyUncBtn').addEventListener('click', () => {
        navigator.clipboard.writeText($('#uncPathText').textContent)
          .then(() => { $('#copyUncBtn').textContent = 'Copied!'; setTimeout(() => { $('#copyUncBtn').textContent = 'Copy'; }, 2000); });
      });

      dropZone.addEventListener('click', () => fileInput.click());
      dropZone.addEventListener('dragover', (e) => { e.preventDefault(); dropZone.classList.add('dragover'); });
      dropZone.addEventListener('dragleave', () => dropZone.classList.remove('dragover'));
      dropZone.addEventListener('drop', (e) => {
        e.preventDefault();
        dropZone.classList.remove('dragover');
        addFiles(e.dataTransfer.files);
      });
      fileInput.addEventListener('change', () => { addFiles(fileInput.files); fileInput.value = ''; });

      $('#uploadBtn').addEventListener('click', () => uploadFiles());
      $('#rebuildAfterUploadBtn').addEventListener('click', () => {
        confirmRebuild(createdRag.name);
      });
    }

    function addFiles(fileListInput) {
      const allowed = ['.md', '.txt', '.pdf', '.docx'];
      for (const f of fileListInput) {
        const ext = '.' + f.name.split('.').pop().toLowerCase();
        if (allowed.includes(ext)) selectedFiles.push(f);
        else showToast(`Skipped unsupported file: ${f.name}`, 'error');
      }
      renderFileList();
    }

    function renderFileList() {
      const ul = $('#fileList');
      if (selectedFiles.length === 0) { ul.style.display = 'none'; $('#uploadBtn').disabled = true; return; }
      ul.style.display = 'block';
      ul.innerHTML = selectedFiles.map((f, i) =>
        `<li><span>${esc(f.name)}</span><span>${formatBytes(f.size)}</span></li>`
      ).join('');
      $('#uploadBtn').disabled = false;
      $('#uploadBtn').textContent = `Upload ${selectedFiles.length} file${selectedFiles.length > 1 ? 's' : ''}`;
    }

    async function uploadFiles() {
      if (!createdRag || selectedFiles.length === 0) return;
      const btn = $('#uploadBtn');
      btn.disabled = true;

      const progress = $('#uploadProgress');
      const bar = $('#uploadBar');
      const text = $('#uploadText');
      progress.style.display = 'block';

      const batchSize = 10;
      let uploaded = 0;
      let totalSaved = 0, totalConverted = 0, totalFailed = 0;

      for (let i = 0; i < selectedFiles.length; i += batchSize) {
        const batch = selectedFiles.slice(i, i + batchSize);
        const formData = new FormData();
        for (const f of batch) formData.append('files', f);

        try {
          const res = await fetch(`api/rags/${encodeURIComponent(createdRag.name)}/upload`, {
            method: 'POST',
            body: formData
          });
          if (!res.ok) {
            const err = await res.json().catch(() => ({ error: res.statusText }));
            throw new Error(err.error || res.statusText);
          }
          const result = await res.json();
          totalSaved += result.saved || 0;
          totalConverted += result.converted || 0;
          totalFailed += result.failed || 0;
        } catch (e) {
          totalFailed += batch.length;
          showToast(`Batch upload error: ${e.message}`, 'error');
        }

        uploaded += batch.length;
        const pct = Math.round((uploaded / selectedFiles.length) * 100);
        bar.style.width = `${pct}%`;
        text.textContent = `${uploaded} / ${selectedFiles.length} files (${pct}%)`;
      }

      const summary = [];
      if (totalSaved > 0) summary.push(`${totalSaved} saved`);
      if (totalConverted > 0) summary.push(`${totalConverted} converted`);
      if (totalFailed > 0) summary.push(`${totalFailed} failed`);
      text.textContent = `Done: ${summary.join(', ')}`;
      showToast(`Upload complete: ${summary.join(', ')}`, totalFailed > 0 ? 'error' : 'success');

      selectedFiles = [];
      renderFileList();
      btn.textContent = 'Upload Files';
      $('#rebuildAfterUploadBtn').style.display = 'inline-flex';
    }
  }

  // Integration guides
  async function renderIntegration(platform) {
    const mc = mainContent();
    mc.innerHTML = '<div class="page-loading"><div class="spinner"></div><p>Loading integration guide...</p></div>';

    try {
      const config = await api(`api/integration/${encodeURIComponent(platform)}`);
      let html = `
        <div class="guide-container">
          <div class="page-header">
            <h1>${esc(config.title)}</h1>
            <p>${esc(config.description)}</p>
          </div>
          <ol class="step-list">`;

      for (const step of config.steps) {
        html += `
          <li class="step">
            <span class="step-number">${step.order}</span>
            <h4>${esc(step.title)}</h4>
            <p>${esc(step.description)}</p>
            ${step.code ? `<pre><button class="copy-btn" onclick="navigator.clipboard.writeText(this.parentElement.querySelector('code').textContent).then(()=>this.textContent='Copied!')">Copy</button><code>${esc(step.code)}</code></pre>` : ''}
          </li>`;
      }

      html += `</ol>
        <div style="margin-top:24px"><a href="#/" class="btn btn-secondary">Back to Dashboard</a></div>
        </div>`;

      mc.innerHTML = html;
    } catch (e) {
      mc.innerHTML = `<div class="empty-state"><h3>Could not load guide</h3><p>${esc(e.message)}</p></div>`;
    }
  }

  // ── Environment ─────────────────────────────────────
  async function renderEnvironment() {
    const mc = mainContent();
    mc.innerHTML = '<div class="page-loading"><div class="spinner"></div><p>Loading environment status...</p></div>';

    let status;
    try {
      status = await api('api/environment/status');
    } catch (e) {
      mc.innerHTML = `<div class="empty-state"><h3>Could not load environment</h3><p>${esc(e.message)}</p></div>`;
      return;
    }

    let html = `
      <div class="page-header">
        <div class="page-header-actions">
          <div>
            <h1>Environment Status</h1>
            <p>System configuration and runtime information</p>
          </div>
          ${isAdmin() ? '<button class="btn btn-primary" id="initEnvBtn">Initialize Environment</button>' : ''}
        </div>
      </div>
      <div class="detail-grid">`;

    const sections = Object.entries(status);
    if (sections.length === 0) {
      html += '<div class="detail-card full-width"><p class="text-muted">No environment data available.</p></div>';
    } else {
      for (const [key, value] of sections) {
        if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
          html += `<div class="detail-card"><h3>${esc(key)}</h3><table class="data-table">`;
          for (const [k, v] of Object.entries(value)) {
            const display = typeof v === 'boolean'
              ? `<span class="badge ${v ? 'badge-ready' : 'badge-no-index'}">${v ? 'Yes' : 'No'}</span>`
              : esc(String(v ?? 'N/A'));
            html += `<tr><td>${esc(k)}</td><td>${display}</td></tr>`;
          }
          html += '</table></div>';
        } else {
          html += `<div class="detail-card"><h3>${esc(key)}</h3><p>${esc(String(value))}</p></div>`;
        }
      }
    }

    html += '</div>';
    mc.innerHTML = html;

    $('#initEnvBtn', mc)?.addEventListener('click', () => {
      showModal('Initialize Environment',
        'This will run environment initialization. Existing settings may be reset. Continue?',
        async () => {
          try {
            await api('api/environment/initialize', { method: 'POST' });
            showToast('Environment initialized successfully', 'success');
            renderEnvironment();
          } catch (e) {
            showToast(e.message, 'error');
          }
        });
    });
  }

  // ── Services ───────────────────────────────────────
  let servicesPoller = null;

  async function renderServices() {
    if (!isAdmin()) {
      mainContent().innerHTML = '<div class="empty-state"><h3>Access Denied</h3><p>Admin role required to manage services.</p></div>';
      return;
    }

    const mc = mainContent();
    mc.innerHTML = '<div class="page-loading"><div class="spinner"></div><p>Loading services...</p></div>';

    let services;
    try {
      services = await api('api/services');
    } catch (e) {
      mc.innerHTML = `<div class="empty-state"><h3>Could not load services</h3><p>${esc(e.message)}</p></div>`;
      return;
    }

    let html = `
      <div class="page-header">
        <div class="page-header-actions">
          <div>
            <h1>Services</h1>
            <p>${services.length} service${services.length !== 1 ? 's' : ''} registered</p>
          </div>
          <button class="btn btn-secondary" id="refreshServicesBtn">Refresh</button>
        </div>
      </div>`;

    if (services.length === 0) {
      html += '<div class="empty-state"><h3>No services found</h3><p>No managed services are registered.</p></div>';
    } else {
      html += '<div class="card-grid">';
      for (const svc of services) {
        const statusBadge = svc.status === 'running' ? 'badge-ready'
          : svc.status === 'stopped' ? 'badge-no-index'
          : 'badge-building';
        const statusLabel = (svc.status || 'unknown').charAt(0).toUpperCase() + (svc.status || 'unknown').slice(1);

        html += `
          <div class="card">
            <div class="card-header">
              <div>
                <div class="card-title">${esc(svc.name)}</div>
                <div class="card-description">${esc(svc.description || '')}</div>
              </div>
              <span class="badge ${statusBadge}">${statusLabel}</span>
            </div>
            <div class="card-stats">
              ${svc.port ? `<div class="stat"><span class="stat-label">Port</span><span class="stat-value">${svc.port}</span></div>` : ''}
              ${svc.pid ? `<div class="stat"><span class="stat-label">PID</span><span class="stat-value">${svc.pid}</span></div>` : ''}
              ${svc.uptime ? `<div class="stat"><span class="stat-label">Uptime</span><span class="stat-value">${esc(svc.uptime)}</span></div>` : ''}
            </div>
            <div class="card-actions">
              <button class="btn btn-success btn-sm" data-svc-action="start" data-svc-name="${esc(svc.name)}" ${svc.status === 'running' ? 'disabled' : ''}>Start</button>
              <button class="btn btn-danger btn-sm" data-svc-action="stop" data-svc-name="${esc(svc.name)}" ${svc.status === 'stopped' ? 'disabled' : ''}>Stop</button>
              <button class="btn btn-secondary btn-sm" data-svc-action="restart" data-svc-name="${esc(svc.name)}">Restart</button>
            </div>
          </div>`;
      }
      html += '</div>';
    }

    mc.innerHTML = html;

    $$('[data-svc-action]', mc).forEach(btn => {
      btn.addEventListener('click', () => {
        const action = btn.dataset.svcAction;
        const name = btn.dataset.svcName;
        const actionLabel = action.charAt(0).toUpperCase() + action.slice(1);
        showModal(`${actionLabel} Service`,
          `Are you sure you want to ${action} "${name}"?`,
          async () => {
            try {
              await api(`api/services/${encodeURIComponent(name)}/${action}`, { method: 'POST' });
              showToast(`${actionLabel} command sent to ${name}`, 'success');
              setTimeout(() => renderServices(), 1500);
            } catch (e) {
              showToast(e.message, 'error');
            }
          });
      });
    });

    $('#refreshServicesBtn', mc)?.addEventListener('click', () => renderServices());
  }

  // ── Backup ────────────────────────────────────────
  async function renderBackup() {
    if (!isAdmin()) {
      mainContent().innerHTML = '<div class="empty-state"><h3>Access Denied</h3><p>Admin role required to manage backups.</p></div>';
      return;
    }

    const mc = mainContent();
    mc.innerHTML = '<div class="page-loading"><div class="spinner"></div><p>Loading backup history...</p></div>';

    let history;
    try {
      history = await api('api/backup/history');
    } catch (e) {
      mc.innerHTML = `<div class="empty-state"><h3>Could not load backup history</h3><p>${esc(e.message)}</p></div>`;
      return;
    }

    const items = Array.isArray(history) ? history : (history.backups || []);

    let html = `
      <div class="page-header">
        <div class="page-header-actions">
          <div>
            <h1>Backup Management</h1>
            <p>${items.length} backup${items.length !== 1 ? 's' : ''} recorded</p>
          </div>
          <div style="display:flex;gap:8px">
            <button class="btn btn-primary" id="triggerBackupBtn">Trigger Backup</button>
            <button class="btn btn-secondary" id="refreshBackupBtn">Refresh</button>
          </div>
        </div>
      </div>`;

    if (items.length === 0) {
      html += '<div class="empty-state"><h3>No backups yet</h3><p>Trigger a backup to create the first snapshot.</p></div>';
    } else {
      html += `
        <div class="detail-card full-width">
          <table class="data-table" style="width:100%">
            <thead>
              <tr><th>Date</th><th>Name</th><th>Size</th><th>Status</th><th></th></tr>
            </thead>
            <tbody>`;
      for (const b of items) {
        const date = b.createdAt ? new Date(b.createdAt).toLocaleString() : 'Unknown';
        const sizeFmt = formatBytes(b.sizeBytes || 0);
        const statusBadge = b.status === 'completed' ? 'badge-ready'
          : b.status === 'failed' ? 'badge-no-index'
          : 'badge-building';
        const statusLabel = (b.status || 'unknown').charAt(0).toUpperCase() + (b.status || 'unknown').slice(1);

        html += `
          <tr>
            <td>${date}</td>
            <td><strong>${esc(b.name || b.id || '')}</strong></td>
            <td>${sizeFmt}</td>
            <td><span class="badge ${statusBadge}">${statusLabel}</span></td>
            <td><button class="btn btn-danger btn-sm" data-backup-delete="${esc(b.id || b.name || '')}">Delete</button></td>
          </tr>`;
      }
      html += '</tbody></table></div>';
    }

    mc.innerHTML = html;

    $('#triggerBackupBtn', mc)?.addEventListener('click', () => {
      showModal('Trigger Backup',
        'Start a new backup now? This may take a few minutes depending on index sizes.',
        async () => {
          try {
            await api('api/backup/trigger', { method: 'POST' });
            showToast('Backup triggered successfully', 'success');
            setTimeout(() => renderBackup(), 2000);
          } catch (e) {
            showToast(e.message, 'error');
          }
        });
    });

    $('#refreshBackupBtn', mc)?.addEventListener('click', () => renderBackup());

    $$('[data-backup-delete]', mc).forEach(btn => {
      btn.addEventListener('click', () => {
        const id = btn.dataset.backupDelete;
        showModal('Delete Backup',
          `Are you sure you want to delete backup "${id}"? This cannot be undone.`,
          async () => {
            try {
              await api(`api/backup/${encodeURIComponent(id)}`, { method: 'DELETE' });
              showToast('Backup deleted', 'success');
              renderBackup();
            } catch (e) {
              showToast(e.message, 'error');
            }
          });
      });
    });
  }

  // ── Ollama Playground ─────────────────────────────
  async function renderOllamaPlayground() {
    const mc = mainContent();
    mc.innerHTML = '<div class="page-loading"><div class="spinner"></div><p>Loading Ollama status...</p></div>';

    let health, models;
    try {
      [health, models] = await Promise.all([
        api('api/ollama/health').catch(() => null),
        api('api/ollama/models').catch(() => [])
      ]);
    } catch {
      health = null;
      models = [];
    }

    const modelList = Array.isArray(models) ? models : (models.models || []);
    const isHealthy = health && (health.status === 'ok' || health.healthy === true);

    let html = `
      <div class="page-header">
        <div class="page-header-actions">
          <div>
            <h1>Ollama Playground</h1>
            <p>Query local Ollama models with RAG context</p>
          </div>
          <span class="badge ${isHealthy ? 'badge-ready' : 'badge-no-index'}">${isHealthy ? 'Connected' : 'Unavailable'}</span>
        </div>
      </div>

      <div class="detail-grid">
        <div class="detail-card">
          <h3>Health</h3>
          <table class="data-table">
            <tr><td>Status</td><td><span class="badge ${isHealthy ? 'badge-ready' : 'badge-no-index'}">${isHealthy ? 'Healthy' : 'Unhealthy'}</span></td></tr>
            ${health?.version ? `<tr><td>Version</td><td>${esc(health.version)}</td></tr>` : ''}
            ${health?.url ? `<tr><td>Endpoint</td><td><code>${esc(health.url)}</code></td></tr>` : ''}
          </table>
        </div>
        <div class="detail-card">
          <h3>Available Models</h3>
          ${modelList.length > 0 ? `
            <ul class="source-list">
              ${modelList.map(m => {
                const name = typeof m === 'string' ? m : (m.name || m.model || JSON.stringify(m));
                const size = m.size ? formatBytes(m.size) : '';
                return `<li class="source-item"><div class="source-name">${esc(name)}</div>${size ? `<span class="source-meta">${size}</span>` : ''}</li>`;
              }).join('')}
            </ul>
          ` : '<p class="text-muted">No models available.</p>'}
        </div>
      </div>`;

    if (isAdmin()) {
      html += `
      <div class="query-panel" style="margin-top:24px">
        <h3 style="margin-bottom:12px">Query</h3>
        <div style="display:flex;gap:8px;margin-bottom:12px;flex-wrap:wrap;align-items:end">
          <div class="form-group" style="flex:1;min-width:200px;margin-bottom:0">
            <label for="ollamaModel" style="font-size:13px">Model</label>
            <select id="ollamaModel" style="width:100%;padding:8px 12px;border:1px solid var(--color-border);border-radius:8px;background:var(--color-bg);color:var(--color-text)">
              ${modelList.length > 0
                ? modelList.map(m => {
                    const name = typeof m === 'string' ? m : (m.name || m.model || '');
                    return `<option value="${esc(name)}">${esc(name)}</option>`;
                  }).join('')
                : '<option value="">No models</option>'}
            </select>
          </div>
          <div class="form-group" style="flex:1;min-width:200px;margin-bottom:0">
            <label for="ollamaRag" style="font-size:13px">RAG Index (optional)</label>
            <select id="ollamaRag" style="width:100%;padding:8px 12px;border:1px solid var(--color-border);border-radius:8px;background:var(--color-bg);color:var(--color-text)">
              <option value="">None</option>
            </select>
          </div>
        </div>
        <div class="query-input-row">
          <input type="text" id="ollamaInput" placeholder="Ask a question..." />
          <button class="btn btn-primary" id="ollamaQueryBtn" ${modelList.length === 0 ? 'disabled' : ''}>Send</button>
        </div>
        <div class="query-results" id="ollamaResults"></div>
      </div>`;
    }

    mc.innerHTML = html;

    if (isAdmin()) {
      try {
        const ragList = rags.length > 0 ? rags : await fetchRags();
        const ragSelect = $('#ollamaRag', mc);
        if (ragSelect) {
          for (const r of ragList) {
            const opt = document.createElement('option');
            opt.value = r.name;
            opt.textContent = r.name;
            ragSelect.appendChild(opt);
          }
        }
      } catch { /* rags unavailable */ }

      $('#ollamaQueryBtn', mc)?.addEventListener('click', () => runOllamaQuery());
      $('#ollamaInput', mc)?.addEventListener('keydown', (e) => { if (e.key === 'Enter') runOllamaQuery(); });
    }
  }

  async function runOllamaQuery() {
    const input = $('#ollamaInput');
    const results = $('#ollamaResults');
    const question = input.value.trim();
    if (!question) return;

    const model = $('#ollamaModel')?.value || '';
    const ragName = $('#ollamaRag')?.value || '';

    results.innerHTML = '<div class="page-loading" style="height:auto;padding:20px"><div class="spinner"></div><p>Querying Ollama...</p></div>';

    try {
      const body = { question, model };
      if (ragName) body.ragName = ragName;

      const data = await api('api/ollama/query', {
        method: 'POST',
        body: JSON.stringify(body)
      });

      const answer = data.answer || data.response || data.text || JSON.stringify(data, null, 2);
      const sources = data.sources || data.context || [];

      let responseHtml = `<div class="query-result-item"><div class="source">Answer</div><div class="content" style="white-space:pre-wrap">${esc(String(answer))}</div></div>`;

      if (Array.isArray(sources) && sources.length > 0) {
        responseHtml += '<div style="margin-top:12px"><strong style="font-size:13px">Sources:</strong></div>';
        responseHtml += sources.map(s => {
          const src = typeof s === 'string' ? s : (s.source || s.file || JSON.stringify(s));
          return `<div class="query-result-item" style="margin-top:4px"><div class="source">${esc(String(src))}</div></div>`;
        }).join('');
      }

      results.innerHTML = responseHtml;
    } catch (e) {
      results.innerHTML = `<p style="color:var(--color-danger)" class="mt-4">${esc(e.message)}</p>`;
    }
  }

  // ── Actions ──────────────────────────────────────────

  async function cancelRebuild(name) {
    showModal(
      'Cancel Rebuild',
      `Cancel the running rebuild for "${name}"? This will kill the build process.`,
      async () => {
        try {
          await api(`api/rags/${encodeURIComponent(name)}/rebuild-cancel`, { method: 'POST' });
          showToast(`Rebuild cancelled for ${name}`, 'info');
          if (rebuildPollers[name]) {
            clearInterval(rebuildPollers[name]);
            delete rebuildPollers[name];
          }
          handleRoute();
        } catch (e) {
          showToast(e.message, 'error');
        }
      }
    );
  }

  function confirmRebuild(name) {
    showModal(
      'Rebuild Index',
      `Are you sure you want to rebuild the index for "${name}"? This will re-process all source files and may take several minutes.`,
      async () => {
        try {
          await api(`api/rags/${encodeURIComponent(name)}/rebuild`, { method: 'POST' });
          showToast(`Rebuild started for ${name}`, 'info');
          markCardAsBuilding(name);
          startRebuildPoller(name);
        } catch (e) {
          showToast(e.message, 'error');
        }
      }
    );
  }

  function markCardAsBuilding(name) {
    const card = $(`#card-${name}`);
    if (!card) return;

    card.classList.add('card-building');

    const badge = card.querySelector('.badge');
    if (badge) {
      badge.className = 'badge badge-building';
      badge.innerHTML = '<span class="spinner-sm"></span>Building...';
    }

    const progressEl = $(`#rebuild-progress-${name}`);
    if (progressEl) {
      progressEl.style.display = '';
      const bar = progressEl.querySelector('.rebuild-progress-bar');
      const text = progressEl.querySelector('.rebuild-progress-text');
      if (bar) bar.style.width = '0%';
      if (text) text.textContent = 'Starting build...';
    }

    card.querySelectorAll('.card-actions .btn').forEach(btn => {
      btn.disabled = true;
      if (btn.tagName === 'A') { btn.style.pointerEvents = 'none'; btn.style.opacity = '.5'; }
    });
  }

  function startRebuildPoller(name) {
    if (rebuildPollers[name]) return;

    const poll = async () => {
      try {
        const status = await api(`api/rags/${encodeURIComponent(name)}/rebuild-status`);
        if (!status.building) {
          clearInterval(rebuildPollers[name]);
          delete rebuildPollers[name];
          showToast(`Rebuild complete for ${name}`, 'success');
          handleRoute();
          return;
        }
        updateRebuildProgress(name, status);
      } catch {
        clearInterval(rebuildPollers[name]);
        delete rebuildPollers[name];
      }
    };

    poll();
    rebuildPollers[name] = setInterval(poll, 3000);
  }

  function updateRebuildProgress(name, status) {
    const el = $(`#rebuild-progress-${name}`);
    if (!el) return;

    el.style.display = '';

    const pct = status.percentage ?? 0;
    const indexed = status.indexed ?? 0;
    const total = status.total ?? 0;
    const bar = el.querySelector('.rebuild-progress-bar');
    const text = el.querySelector('.rebuild-progress-text');
    if (bar) bar.style.width = `${Math.min(pct, 100)}%`;
    if (text) {
      if (total > 0) {
        text.textContent = `${indexed.toLocaleString()} / ${total.toLocaleString()} chunks (${pct.toFixed(1)}%)`;
      } else {
        text.textContent = `Building... started ${status.startedAt || ''}`;
      }
    }
  }

  function confirmDelete(name) {
    showModal(
      'Delete RAG',
      `Are you sure you want to delete "${name}"? This will remove the index and registry entry. Source files will be preserved unless you also remove the library folder.`,
      async () => {
        try {
          await api(`api/rags/${encodeURIComponent(name)}`, { method: 'DELETE' });
          showToast(`${name} deleted`, 'success');
          location.hash = '#/';
          handleRoute();
        } catch (e) {
          showToast(e.message, 'error');
        }
      }
    );
  }

  // ── UI helpers ───────────────────────────────────────

  function showToast(message, type = 'info') {
    const container = $('#toastContainer');
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    container.appendChild(toast);
    setTimeout(() => { toast.style.opacity = '0'; setTimeout(() => toast.remove(), 300); }, 4000);
  }

  let modalCallback = null;
  function showModal(title, message, onConfirm) {
    $('#modalTitle').textContent = title;
    $('#modalMessage').textContent = message;
    $('#modalOverlay').classList.add('active');
    modalCallback = onConfirm;
  }

  $('#modalCancel')?.addEventListener('click', () => {
    $('#modalOverlay').classList.remove('active');
    modalCallback = null;
  });

  $('#modalConfirm')?.addEventListener('click', () => {
    $('#modalOverlay').classList.remove('active');
    if (modalCallback) modalCallback();
    modalCallback = null;
  });

  // ── Utilities ────────────────────────────────────────

  function esc(str) {
    const div = document.createElement('div');
    div.textContent = str || '';
    return div.innerHTML;
  }

  function formatBytes(bytes) {
    if (!bytes || bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return (bytes / Math.pow(1024, i)).toFixed(i > 0 ? 1 : 0) + ' ' + units[i];
  }
})();
