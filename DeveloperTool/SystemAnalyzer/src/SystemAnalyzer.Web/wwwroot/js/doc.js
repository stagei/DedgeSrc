/**
 * doc.js — SystemAnalyzer program documentation viewer.
 * Fetches AutoDocJson per-program JSON files and renders metadata + diagrams.
 */
const mermaid = window.mermaid;
if (mermaid) {
  const mermaidTheme = document.documentElement.getAttribute("data-theme") === "light" ? "default" : "dark";
  mermaid.initialize({
    startOnLoad: false, theme: mermaidTheme, securityLevel: "loose",
    flowchart: { useMaxWidth: true, htmlLabels: true, curve: "basis" },
    sequence: { useMaxWidth: true },
    suppressErrorRendering: true
  });
}

function esc(s) { return s == null ? "" : String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }

function docLink(jsonFile, label) {
  if (!jsonFile) return esc(label || "");
  const safe = jsonFile.replace(/^\.\//, "").replace(/\.html$/, ".json");
  return `<a href="doc.html?file=${encodeURIComponent(safe)}">${esc(label || safe)}</a>`;
}

function boolCheckbox(v) {
  return `<input type="checkbox" ${v ? "checked" : ""} onclick="return false" style="accent-color:var(--accent)" />`;
}

// ═══════════════════════════════════════════════════════════════════════
//  FETCH
// ═══════════════════════════════════════════════════════════════════════
async function fetchDoc(fileName) {
  const resp = await fetch(`api/autodoc/${encodeURIComponent(fileName)}`);
  if (!resp.ok) {
    if (resp.status === 404) return null;
    throw new Error(`HTTP ${resp.status}`);
  }
  return resp.json();
}

// ═══════════════════════════════════════════════════════════════════════
//  MERMAID RENDERING
// ═══════════════════════════════════════════════════════════════════════
let mmdCounter = 0;

async function renderMermaid(targetEl, code) {
  if (!mermaid || !code) { targetEl.innerHTML = '<p style="color:var(--text2)">No diagram data.</p>'; return; }
  try {
    const id = "doc_mmd_" + (++mmdCounter);
    const { svg } = await mermaid.render(id, code);
    targetEl.innerHTML = svg;
  } catch (e) {
    targetEl.innerHTML = `<pre style="color:var(--red);font-size:12px">Diagram error: ${esc(e.message)}</pre>`;
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  BUILD INFO PANEL
// ═══════════════════════════════════════════════════════════════════════
function buildCblInfo(doc) {
  const m = doc.metadata || {};
  let h = '<div class="doc-info-card"><table class="doc-info-table">';
  h += `<tr><td>Filename</td><td><a href="https://Dedge.visualstudio.com/Dedge/_search?action=contents&text=${encodeURIComponent(doc.sourceFile || doc.fileName)}&type=code" target="_blank">${esc(doc.title || doc.fileName)}</a></td></tr>`;
  if (m.typeLabel) h += `<tr><td>Type</td><td>${esc(m.typeLabel)}</td></tr>`;
  if (doc.description) h += `<tr><td>Description</td><td>${esc(doc.description)}</td></tr>`;
  if (m.system) h += `<tr><td>System</td><td>${esc(m.system)}</td></tr>`;
  h += `<tr><td>Dialog System</td><td>${boolCheckbox(m.usesDialogSystem)}</td></tr>`;
  if (m.screenLink) h += `<tr><td>Screen Layout</td><td><a href="${esc(m.screenLink)}" target="_blank">${esc(m.screenLinkText || "Screen")}</a></td></tr>`;
  h += `<tr><td>Uses SQL</td><td>${boolCheckbox(m.usesSql)}</td></tr>`;
  if (m.created) h += `<tr><td>Created</td><td>${esc(m.created)}</td></tr>`;
  if (m.lastProduction) h += `<tr><td>Production</td><td>${esc(m.lastProduction)}</td></tr>`;
  if (doc.generatedAt) h += `<tr><td>Generated</td><td>${esc(doc.generatedAt)}</td></tr>`;
  h += '</table></div>';

  if (doc.sqlTables?.length) {
    h += `<details><summary>SQL Tables <span class="doc-count">${doc.sqlTables.length}</span></summary>`;
    h += '<table class="doc-detail-table"><tr><th>Table</th><th>Op</th><th>Description</th></tr>';
    doc.sqlTables.forEach(t => {
      const link = t.link ? t.link.replace("./", "").replace(".html", ".json") : "";
      h += `<tr><td>${link ? docLink(link, t.table) : esc(t.table)}</td><td>${esc(t.operation)}</td><td>${esc(t.description)}</td></tr>`;
    });
    h += '</table></details>';
  }

  if (doc.calledSubprograms?.length) {
    h += `<details><summary>Called Subprograms <span class="doc-count">${doc.calledSubprograms.length}</span></summary>`;
    h += '<table class="doc-detail-table"><tr><th>Module</th><th>Description</th></tr>';
    doc.calledSubprograms.forEach(c => {
      const link = c.link ? c.link.replace("./", "").replace(".html", ".json") : "";
      h += `<tr><td>${link ? docLink(link, c.module) : esc(c.module)}</td><td>${esc(c.description)}</td></tr>`;
    });
    h += '</table></details>';
  }

  if (doc.copyElements?.length) {
    h += `<details><summary>Copy Elements <span class="doc-count">${doc.copyElements.length}</span></summary>`;
    h += '<table class="doc-detail-table"><tr><th>Filename</th></tr>';
    doc.copyElements.forEach(c => {
      h += `<tr><td>${c.link ? `<a href="${esc(c.link)}" target="_blank">${esc(c.name)}</a>` : esc(c.name)}</td></tr>`;
    });
    h += '</table></details>';
  }

  if (doc.changeLog?.length) {
    h += `<details><summary>Change Log <span class="doc-count">${doc.changeLog.length}</span></summary>`;
    h += '<table class="doc-detail-table"><tr><th>Date</th><th>User</th><th>Comment</th></tr>';
    doc.changeLog.forEach(e => {
      h += `<tr><td style="white-space:nowrap">${esc(e.date)}</td><td>${esc(e.user)}</td><td>${esc(e.comment)}</td></tr>`;
    });
    h += '</table></details>';
  }

  if (doc.productionLog?.length) {
    h += `<details><summary>Production Log <span class="doc-count">${doc.productionLog.length}</span></summary>`;
    h += '<table class="doc-detail-table"><tr><th>Date</th><th>User</th></tr>';
    doc.productionLog.forEach(e => {
      h += `<tr><td style="white-space:nowrap">${esc(e.date)}</td><td>${esc(e.user)}</td></tr>`;
    });
    h += '</table></details>';
  }

  if (doc.gitHistory) {
    const g = doc.gitHistory;
    h += '<details><summary>Git History</summary>';
    h += '<table class="doc-info-table">';
    if (g.lastChanged) h += `<tr><td>Last Changed</td><td>${esc(g.lastChanged)}</td></tr>`;
    if (g.changedBy) h += `<tr><td>Changed By</td><td>${esc(g.changedBy)}</td></tr>`;
    if (g.totalChanges) h += `<tr><td>Total Changes</td><td>${g.totalChanges}</td></tr>`;
    if (g.firstAdded) h += `<tr><td>First Added</td><td>${esc(g.firstAdded)}</td></tr>`;
    if (g.contributors) h += `<tr><td>Contributors</td><td>${g.contributors}</td></tr>`;
    h += '</table></details>';
  }

  return h;
}

function buildScriptInfo(doc) {
  const m = doc.metadata || {};
  let h = '<div class="doc-info-card"><table class="doc-info-table">';
  h += `<tr><td>Filename</td><td>${esc(doc.title || doc.fileName)}</td></tr>`;
  if (doc.description) h += `<tr><td>Description</td><td>${esc(doc.description)}</td></tr>`;
  if (m.system) h += `<tr><td>System</td><td>${esc(m.system)}</td></tr>`;
  if (doc.generatedAt) h += `<tr><td>Generated</td><td>${esc(doc.generatedAt)}</td></tr>`;
  h += '</table></div>';

  if (doc.functions?.length) {
    h += `<details><summary>Functions <span class="doc-count">${doc.functions.length}</span></summary>`;
    h += '<table class="doc-detail-table"><tr><th>Name</th></tr>';
    doc.functions.forEach(f => { h += `<tr><td class="mono">${esc(typeof f === "string" ? f : f.name || f)}</td></tr>`; });
    h += '</table></details>';
  }

  if (doc.calledScripts?.length) {
    h += `<details><summary>Called Scripts <span class="doc-count">${doc.calledScripts.length}</span></summary>`;
    h += '<table class="doc-detail-table"><tr><th>Name</th></tr>';
    doc.calledScripts.forEach(s => {
      const link = s.link ? s.link.replace("./", "").replace(".html", ".json") : "";
      h += `<tr><td>${link ? docLink(link, s.name) : esc(s.name)}</td></tr>`;
    });
    h += '</table></details>';
  }

  return h;
}

function buildSqlInfo(doc) {
  const m = doc.metadata || {};
  let h = '<div class="doc-info-card"><table class="doc-info-table">';
  if (m.fullName) h += `<tr><td>Full Name</td><td class="mono">${esc(m.fullName)}</td></tr>`;
  if (m.schema) h += `<tr><td>Schema</td><td>${esc(m.schema)}</td></tr>`;
  if (m.tableName) h += `<tr><td>Table</td><td class="mono">${esc(m.tableName)}</td></tr>`;
  if (doc.description) h += `<tr><td>Description</td><td>${esc(doc.description)}</td></tr>`;
  if (doc.generatedAt) h += `<tr><td>Generated</td><td>${esc(doc.generatedAt)}</td></tr>`;
  h += '</table></div>';

  if (doc.columns?.length) {
    h += `<details open><summary>Columns <span class="doc-count">${doc.columns.length}</span></summary>`;
    h += '<table class="doc-detail-table"><tr><th>Name</th><th>Type</th><th>Nullable</th></tr>';
    doc.columns.forEach(c => {
      h += `<tr><td class="mono">${esc(c.name)}</td><td>${esc(c.type || c.dataType)}</td><td>${c.nullable ? "Yes" : "No"}</td></tr>`;
    });
    h += '</table></details>';
  }

  if (doc.usedBy?.length) {
    h += `<details><summary>Used By <span class="doc-count">${doc.usedBy.length}</span></summary>`;
    h += '<table class="doc-detail-table"><tr><th>Program</th><th>Type</th></tr>';
    doc.usedBy.forEach(u => {
      const link = u.filePath ? u.filePath.replace("./", "").replace(".html", ".json") : "";
      h += `<tr><td>${link ? docLink(link, u.programName) : esc(u.programName)}</td><td>${esc(u.fileType)}</td></tr>`;
    });
    h += '</table></details>';
  }

  return h;
}

function buildCSharpInfo(doc) {
  const m = doc.metadata || {};
  let h = '<div class="doc-info-card"><table class="doc-info-table">';
  h += `<tr><td>Solution</td><td>${esc(doc.title || doc.fileName)}</td></tr>`;
  if (doc.description) h += `<tr><td>Description</td><td>${esc(doc.description)}</td></tr>`;
  if (doc.generatedAt) h += `<tr><td>Generated</td><td>${esc(doc.generatedAt)}</td></tr>`;
  h += '</table></div>';

  if (doc.projects?.length) {
    h += `<details open><summary>Projects <span class="doc-count">${doc.projects.length}</span></summary>`;
    h += '<table class="doc-detail-table"><tr><th>Name</th><th>Type</th></tr>';
    doc.projects.forEach(p => { h += `<tr><td>${esc(p.name)}</td><td>${esc(p.type || p.projectType || "")}</td></tr>`; });
    h += '</table></details>';
  }

  if (doc.restEndpoints?.length) {
    h += `<details><summary>REST Endpoints <span class="doc-count">${doc.restEndpoints.length}</span></summary>`;
    h += '<table class="doc-detail-table"><tr><th>Method</th><th>Route</th></tr>';
    doc.restEndpoints.forEach(r => { h += `<tr><td>${esc(r.method || r.httpMethod)}</td><td class="mono">${esc(r.route || r.path)}</td></tr>`; });
    h += '</table></details>';
  }

  return h;
}

// ═══════════════════════════════════════════════════════════════════════
//  COLLECT DIAGRAM TABS FOR EACH TYPE
// ═══════════════════════════════════════════════════════════════════════
function getDiagramTabs(doc) {
  const tabs = [];
  const type = (doc.type || "").toUpperCase();

  if (type === "CBL" || type === "BAT" || type === "PS1" || type === "REX") {
    const d = doc.diagrams || {};
    if (d.flowMmd) tabs.push({ id: "flow", label: "Flow Diagram", mmd: d.flowMmd });
    if (d.sequenceMmd) tabs.push({ id: "sequence", label: "Sequence Diagram", mmd: d.sequenceMmd });
    if (d.processMmd) tabs.push({ id: "process", label: "Process Diagram", mmd: d.processMmd });
  } else if (type === "SQL") {
    if (doc.erDiagramMmd) tabs.push({ id: "er", label: "ER Diagram", mmd: doc.erDiagramMmd });
    if (doc.interactionDiagramMmd) tabs.push({ id: "interaction", label: "Interactions", mmd: doc.interactionDiagramMmd });
  } else if (type === "CSHARP") {
    const d = doc.diagrams || {};
    const diagramFields = [
      ["flowDiagramMmd", "Flow"],
      ["classDiagramMmd", "Class"],
      ["projectDiagramMmd", "Projects"],
      ["namespaceDiagramMmd", "Namespaces"],
      ["ecosystemDiagramMmd", "Ecosystem"],
      ["processDiagramMmd", "Process"],
      ["executionPathDiagramMmd", "Execution Path"],
      ["restDiagramMmd", "REST"]
    ];
    diagramFields.forEach(([key, label]) => {
      if (d[key]) tabs.push({ id: key, label, mmd: d[key] });
    });
  }

  return tabs;
}

// ═══════════════════════════════════════════════════════════════════════
//  RENDER PAGE
// ═══════════════════════════════════════════════════════════════════════
async function renderDoc(doc) {
  const main = document.getElementById("docMain");
  const type = (doc.type || "").toUpperCase();

  document.getElementById("docTitle").textContent = doc.title || doc.fileName || "Document";
  const badge = document.getElementById("typeBadge");
  const badgeMap = { CBL: "COBOL", PS1: "PowerShell", SQL: "SQL", BAT: "Batch", REX: "Object-Rexx", CSHARP: "C#" };
  badge.textContent = badgeMap[type] || type;
  badge.className = "doc-type-badge " + type;
  badge.style.display = "inline-block";
  document.title = `${doc.title || doc.fileName} — SystemAnalyzer`;

  let infoHtml;
  switch (type) {
    case "CBL": infoHtml = buildCblInfo(doc); break;
    case "BAT": case "PS1": case "REX": infoHtml = buildScriptInfo(doc); break;
    case "SQL": infoHtml = buildSqlInfo(doc); break;
    case "CSHARP": infoHtml = buildCSharpInfo(doc); break;
    default: infoHtml = `<div class="doc-info-card"><p>Type: ${esc(type)}</p></div>`;
  }

  const diagramTabs = getDiagramTabs(doc);

  let diagramTabsHtml = "";
  let diagramContentHtml = "";

  if (diagramTabs.length === 0) {
    diagramContentHtml = '<div class="doc-diagram-content active"><div class="doc-diagram-render" style="display:flex;align-items:center;justify-content:center;color:var(--text2)">No diagrams available for this document.</div></div>';
  } else {
    diagramTabsHtml = '<div class="doc-diagram-tabs">';
    diagramTabs.forEach((tab, i) => {
      diagramTabsHtml += `<button class="doc-diagram-tab${i === 0 ? " active" : ""}" data-tab="${tab.id}">${esc(tab.label)}</button>`;
    });
    diagramTabsHtml += '</div>';

    diagramContentHtml = '<div class="doc-diagram-toolbar">';
    diagramContentHtml += '<button class="btn" id="btnFullscreen" title="Fullscreen">Fullscreen</button>';
    diagramContentHtml += '</div>';

    diagramTabs.forEach((tab, i) => {
      diagramContentHtml += `<div class="doc-diagram-content${i === 0 ? " active" : ""}" data-content="${tab.id}">`;
      diagramContentHtml += `<div class="doc-diagram-render" id="diagram-${tab.id}"></div>`;
      diagramContentHtml += '</div>';
    });
  }

  main.innerHTML =
    `<div class="doc-info-panel">${infoHtml}</div>` +
    `<div class="doc-diagram-panel">${diagramTabsHtml}${diagramContentHtml}</div>`;

  // Render first visible diagram
  if (diagramTabs.length > 0) {
    const firstTarget = document.getElementById(`diagram-${diagramTabs[0].id}`);
    if (firstTarget) await renderMermaid(firstTarget, diagramTabs[0].mmd);
  }

  // Tab switching
  main.querySelectorAll(".doc-diagram-tab").forEach(btn => {
    btn.addEventListener("click", async () => {
      main.querySelectorAll(".doc-diagram-tab").forEach(b => b.classList.remove("active"));
      btn.classList.add("active");

      main.querySelectorAll(".doc-diagram-content").forEach(c => c.classList.remove("active"));
      const content = main.querySelector(`.doc-diagram-content[data-content="${btn.dataset.tab}"]`);
      if (content) {
        content.classList.add("active");
        const target = content.querySelector(".doc-diagram-render");
        if (target && !target.querySelector("svg")) {
          const tab = diagramTabs.find(t => t.id === btn.dataset.tab);
          if (tab) await renderMermaid(target, tab.mmd);
        }
      }
    });
  });

  // Fullscreen
  const fsBtn = document.getElementById("btnFullscreen");
  if (fsBtn) {
    fsBtn.addEventListener("click", () => {
      const activeTab = main.querySelector(".doc-diagram-tab.active");
      const tabId = activeTab?.dataset.tab;
      const tab = diagramTabs.find(t => t.id === tabId);
      if (!tab) return;
      openFullscreen(tab.label, tab.mmd);
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  FULLSCREEN
// ═══════════════════════════════════════════════════════════════════════
let fsScale = 1;

function openFullscreen(title, mmd) {
  const overlay = document.getElementById("fullscreenOverlay");
  const body = document.getElementById("fullscreenBody");
  document.getElementById("fullscreenTitle").textContent = title;
  fsScale = 1;
  updateFsZoom();
  overlay.classList.add("open");

  renderMermaid(body, mmd);
}

function closeFullscreen() {
  document.getElementById("fullscreenOverlay").classList.remove("open");
  document.getElementById("fullscreenBody").innerHTML = "";
}

function updateFsZoom() {
  document.getElementById("fsZoomPct").textContent = Math.round(fsScale * 100) + "%";
  const body = document.getElementById("fullscreenBody");
  const svg = body.querySelector("svg");
  if (svg) { svg.style.transform = `scale(${fsScale})`; svg.style.transformOrigin = "top left"; }
}

document.getElementById("fsZoomIn").addEventListener("click", () => { fsScale = Math.min(fsScale * 1.25, 5); updateFsZoom(); });
document.getElementById("fsZoomOut").addEventListener("click", () => { fsScale = Math.max(fsScale / 1.25, 0.1); updateFsZoom(); });
document.getElementById("fsFit").addEventListener("click", () => { fsScale = 1; updateFsZoom(); });
document.getElementById("fsClose").addEventListener("click", closeFullscreen);
document.addEventListener("keydown", e => { if (e.key === "Escape") closeFullscreen(); });

// ═══════════════════════════════════════════════════════════════════════
//  INIT
// ═══════════════════════════════════════════════════════════════════════
async function init() {
  const params = new URLSearchParams(window.location.search);
  const fileName = params.get("file");

  if (!fileName) {
    document.getElementById("docMain").innerHTML = '<div class="doc-error">No file specified. Use ?file=PROGRAM.CBL.json</div>';
    return;
  }

  try {
    const doc = await fetchDoc(fileName);
    if (!doc) {
      document.getElementById("docMain").innerHTML =
        `<div class="doc-loading" style="flex-direction:column;gap:12px">` +
        `<div style="font-size:16px;color:var(--text2)">Documentation not yet available</div>` +
        `<div style="font-size:13px;color:var(--text2)">File: ${esc(fileName)}</div>` +
        `<div style="font-size:12px;color:var(--text2)">AutoDocJson documentation for this program has not been generated yet.<br>It should be available after the next AutoDocJson batch run.</div>` +
        `</div>`;
      return;
    }
    await renderDoc(doc);
  } catch (e) {
    document.getElementById("docMain").innerHTML = `<div class="doc-error">Error loading documentation: ${esc(e.message)}</div>`;
  }
}

init();
