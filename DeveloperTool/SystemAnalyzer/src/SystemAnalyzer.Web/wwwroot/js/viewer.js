import { initAliasSelect, getAliasFromUrl, setAliasInLink } from "./shared.js";

const mermaid = window.mermaid;
if (mermaid) {
  const mermaidTheme = document.documentElement.getAttribute("data-theme") === "light" ? "default" : "dark";
  mermaid.initialize({
    startOnLoad: false, theme: mermaidTheme, securityLevel: "loose",
    flowchart: { useMaxWidth: true, htmlLabels: true, curve: "basis" },
    suppressErrorRendering: true
  });
} else {
  console.warn("[viewer] Mermaid library not loaded");
}

let alias = "";
const DATA = { progs: null, sql: null, copy: null, call: null, fio: null, master: null, verify: null, excl: null, db2: null };
const masterIndex = {};

let activeTab = "summary";
let globalFilter = "";
let sortState = {};

function esc(s) { return s == null ? "" : String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
function mmdId(name) { return name.replace(/[^a-zA-Z0-9_]/g, "_"); }

function tag(text, cls) { return `<span class="tag tag-${cls}">${esc(text)}</span>`; }
function sourceTag(s) {
  if (s === "original") return tag("original", "original");
  if (s === "call-expansion") return tag("call", "call");
  if (s === "table-reference") return tag("table", "table");
  return tag(s || "?", "original");
}
function sourceTypeTag(s) { return s ? (s.startsWith("local") ? tag(s, "local") : tag(s, "rag")) : ""; }
function boolTag(v) { return v === true ? tag("Yes", "yes") : v === false ? tag("No", "no") : '<span style="color:var(--text2)">—</span>'; }
function candidateTag(v) { return v ? tag("CANDIDATE", "candidate") : ""; }
function deprecatedTag(v) { return v ? tag("UTGATT", "no") : ""; }
function classTag(v) {
  if (!v) return '<span style="color:var(--text2)">—</span>';
  return `<span class="tag tag-table">${esc(v)}</span>`;
}
function fileLink(path, label) {
  if (!path) return '<span class="mono" style="color:var(--text2)">—</span>';
  const normalized = path.replace(/\\/g, "/");
  return `<a href="vscode://file/${encodeURI(normalized)}" class="file-link" title="Open in Cursor/VS Code">${esc(label || path)}</a>`;
}

async function fetchJson(fileName) {
  try { const r = await fetch(`api/data/${encodeURIComponent(alias)}/${fileName}`); if (r.ok) return r.json(); } catch (e) { /* ignore */ }
  return null;
}

const autoDocExtensions = [".CBL.json", ".BAT.json", ".PS1.json", ".REX.json"];
const autoDocCache = {};

function checkAutoDocAvailable(programName, defaultJsonFile) {
  if (autoDocCache[programName] !== undefined) {
    if (autoDocCache[programName]) {
      const badge = document.getElementById(`autodocBadge_${programName}`);
      if (badge) badge.style.display = "inline-block";
      const link = document.querySelector(`a.autodoc-link-btn[href*="${encodeURIComponent(defaultJsonFile)}"]`);
      if (link && autoDocCache[programName] !== defaultJsonFile) {
        link.href = `doc.html?file=${encodeURIComponent(autoDocCache[programName])}`;
      }
    }
    return;
  }

  (async () => {
    for (const ext of autoDocExtensions) {
      const candidate = programName + ext;
      try {
        const r = await fetch(`api/autodoc/${encodeURIComponent(candidate)}`, { method: "HEAD" });
        if (r.ok) {
          autoDocCache[programName] = candidate;
          const badge = document.getElementById(`autodocBadge_${programName}`);
          if (badge) badge.style.display = "inline-block";
          const link = document.querySelector(`a.autodoc-link-btn`);
          if (link) link.href = `doc.html?file=${encodeURIComponent(candidate)}`;
          return;
        }
      } catch { /* ignore */ }
    }
    autoDocCache[programName] = false;
  })();
}

async function loadAllData() {
  const [progs, sql, copy, call, fio, master, verify, excl, db2] = await Promise.all([
    fetchJson("all_total_programs.json"), fetchJson("all_sql_tables.json"),
    fetchJson("all_copy_elements.json"), fetchJson("all_call_graph.json"),
    fetchJson("all_file_io.json"), fetchJson("dependency_master.json"),
    fetchJson("source_verification.json"), fetchJson("applied_exclusions.json"),
    fetchJson("db2_table_validation.json")
  ]);
  Object.assign(DATA, { progs, sql, copy, call, fio, master, verify, excl, db2 });
  if (DATA.master?.programs) DATA.master.programs.forEach(p => { masterIndex[p.program] = p; });
}

// ═══════════════════════════════════════════════════════════════════════
//  TABS
// ═══════════════════════════════════════════════════════════════════════
const tabs = [
  { id: "summary", label: "Summary" },
  { id: "graph", label: "Dependency Graph", href: "graph.html" },
  { id: "programs", label: "Programs" },
  { id: "sql", label: "SQL Tables" },
  { id: "copy", label: "Copy Elements" },
  { id: "call", label: "Call Graph" },
  { id: "fio", label: "File I/O" }
];

function getTabCount(id) {
  if (id === "programs") return DATA.progs?.totalPrograms ?? 0;
  if (id === "sql") return DATA.sql?.totalReferences ?? 0;
  if (id === "copy") return DATA.copy?.totalCopyElements ?? 0;
  if (id === "call") return DATA.call?.totalEdges ?? 0;
  if (id === "fio") return DATA.fio?.totalFileReferences ?? 0;
  return null;
}

function renderTabs() {
  const bar = document.getElementById("tabBar");
  const aliasEnc = encodeURIComponent(alias);
  bar.innerHTML = tabs.map(t => {
    if (t.href) return `<a class="tab" href="${t.href}?alias=${aliasEnc}" style="text-decoration:none">${esc(t.label)}</a>`;
    const cnt = getTabCount(t.id);
    return `<div class="tab${t.id === activeTab ? " active" : ""}" data-tab="${t.id}">${esc(t.label)}${cnt != null ? `<span class="badge">${cnt.toLocaleString()}</span>` : ""}</div>`;
  }).join("");
  bar.querySelectorAll(".tab[data-tab]").forEach(el => {
    el.addEventListener("click", () => { activeTab = el.dataset.tab; render(); });
  });
}

// ═══════════════════════════════════════════════════════════════════════
//  FILTERING & SORTING
// ═══════════════════════════════════════════════════════════════════════
function matchesFilter(row, cols) {
  if (!globalFilter) return true;
  const lf = globalFilter.toLowerCase();
  return cols.some(c => {
    const v = row[c];
    if (v == null) return false;
    if (Array.isArray(v)) return v.some(x => String(x).toLowerCase().includes(lf));
    return String(v).toLowerCase().includes(lf);
  });
}
function sortRows(rows, tabId) {
  const ss = sortState[tabId]; if (!ss) return rows;
  const { col, dir } = ss;
  return [...rows].sort((a, b) => {
    let va = a[col] ?? "", vb = b[col] ?? "";
    if (typeof va === "number" && typeof vb === "number") return dir * (va - vb);
    return dir * String(va).localeCompare(String(vb), undefined, { numeric: true });
  });
}
function headerClick(tabId, col) {
  const ss = sortState[tabId];
  sortState[tabId] = ss && ss.col === col ? { col, dir: -ss.dir } : { col, dir: 1 };
  render();
}
function sortArrow(tabId, col) {
  const ss = sortState[tabId];
  if (!ss || ss.col !== col) return "";
  return `<span class="sort-arrow">${ss.dir === 1 ? "&#9650;" : "&#9660;"}</span>`;
}

// ═══════════════════════════════════════════════════════════════════════
//  SUMMARY
// ═══════════════════════════════════════════════════════════════════════
function statCard(label, value, color) {
  const c = color ? ` style="color:var(--${color})"` : "";
  return `<div class="stat-card"><div class="label">${esc(label)}</div><div class="value"${c}>${value}</div></div>`;
}

function renderSummary() {
  const p = DATA.progs, s = DATA.sql, co = DATA.copy, ca = DATA.call, f = DATA.fio, v = DATA.verify;
  let h = '<div class="stats-grid">';
  if (p) {
    h += statCard("Total Programs", p.totalPrograms);
    if (p.breakdown) {
      h += statCard("Original", p.breakdown.original, "accent");
      h += statCard("CALL Expansion", p.breakdown.callExpansion, "green");
      h += statCard("Table Reference", p.breakdown.tableReference, "purple");
    }
    if (p.dataSources) {
      h += statCard("Local Source", p.dataSources.localSource, "green");
      h += statCard("RAG Source", p.dataSources.rag, "orange");
    }
  }
  if (s) { h += statCard("SQL References", s.totalReferences?.toLocaleString()); h += statCard("Unique Tables", s.uniqueTables); }
  if (co) h += statCard("Copy Elements", co.totalCopyElements);
  if (ca) h += statCard("Call Edges", ca.totalEdges);
  if (f) { h += statCard("File I/O Refs", f.totalFileReferences); h += statCard("Unique Files", f.uniqueFiles); }
  if (v?.summary) {
    const pct = v.summary.programFoundPct || v.summary.programFoundPctReal || 0;
    h += statCard("Source Found %", pct + "%", "green");
    h += statCard("Truly Missing", v.summary.programsTrulyMissing, "red");
  }
  if (p?.deprecatedCount > 0) h += statCard("Deprecated", p.deprecatedCount, "red");
  if (DATA.excl?.totalCandidates > 0) h += statCard("Excl. Candidates", DATA.excl.totalCandidates, "yellow");
  h += "</div>";

  if (v?.summary) {
    h += '<h3 style="font-size:14px;margin-bottom:10px">Source Verification</h3>';
    h += '<table class="sub-table viewer-table" style="max-width:500px"><thead><tr><th>Status</th><th style="text-align:right">Count</th></tr></thead><tbody>';
    const sv = v.summary;
    [["CBL exact", sv.programsCblFound], ["U/V fuzzy", sv.programsUvFuzzyMatch],
     ["Uncertain", sv.programsUncertainFound], ["Other type", sv.programsOtherType],
     ["Noise filtered", sv.programsNoise], ["Truly missing", sv.programsTrulyMissing]
    ].forEach(([l, c]) => { if (c != null) h += `<tr><td>${esc(l)}</td><td style="text-align:right">${c}</td></tr>`; });
    h += "</tbody></table>";
  }
  return h;
}

// ═══════════════════════════════════════════════════════════════════════
//  PROGRAMS TAB
// ═══════════════════════════════════════════════════════════════════════
function renderPrograms() {
  if (!DATA.progs) return "<p>No data</p>";
  let h = '<div class="filter-row">';
  const sources = [...new Set(DATA.progs.programs.map(p => p.source))].sort();
  const areas = [...new Set(DATA.progs.programs.map(p => p.area))].filter(Boolean).sort();
  const systems = [...new Set(DATA.progs.programs.map(p => p.cobdokSystem))].filter(Boolean).sort();
  const classifications = [...new Set(DATA.progs.programs.map(p => p.classification))].filter(Boolean).sort();
  h += `<label>Source</label><select id="fltSource"><option value="">All</option>${sources.map(s => `<option>${esc(s)}</option>`).join("")}</select>`;
  h += `<label>Area</label><select id="fltArea"><option value="">All</option>${areas.map(s => `<option>${esc(s)}</option>`).join("")}</select>`;
  h += `<label>System</label><select id="fltSystem"><option value="">All</option>${systems.map(s => `<option>${esc(s)}</option>`).join("")}</select>`;
  h += `<label>Classification</label><select id="fltClassification"><option value="">All</option>${classifications.map(s => `<option>${esc(s)}</option>`).join("")}</select>`;
  h += '<label class="toggle-candidates"><input type="checkbox" id="fltDeprecatedOnly"> Deprecated only</label>';
  h += "</div>";
  h += '<div class="result-count" id="progCount"></div>';
  h += '<div style="overflow-x:auto"><table class="viewer-table"><thead><tr>';
  const headers = [["program","Program"],["classification","Class."],["cobdokSystem","System"],["cobdokDelsystem","Subsys"],["source","Source"],["sourceType","Data"],["area","Area"],
    ["description","Description"],["copyCount","COPY"],["sqlOpCount","SQL"],["callCount","CALL"],["fileIOCount","File"],["isDeprecated","Depr."]];
  headers.forEach(([k, l]) => { h += `<th onclick="window._headerClick('programs','${k}')">${esc(l)}${sortArrow("programs", k)}</th>`; });
  h += '</tr></thead><tbody id="progBody"></tbody></table></div>';
  return h;
}

function fillPrograms() {
  if (!DATA.progs) return;
  const fltSource = document.getElementById("fltSource")?.value || "";
  const fltArea = document.getElementById("fltArea")?.value || "";
  const fltSystem = document.getElementById("fltSystem")?.value || "";
  const fltClassification = document.getElementById("fltClassification")?.value || "";
  const fltDeprecated = document.getElementById("fltDeprecatedOnly")?.checked || false;

  let rows = DATA.progs.programs.filter(r => {
    if (!matchesFilter(r, ["program","source","sourceType","area","description","cobdokSystem","cobdokDelsystem","classification"])) return false;
    if (fltSource && r.source !== fltSource) return false;
    if (fltArea && r.area !== fltArea) return false;
    if (fltSystem && r.cobdokSystem !== fltSystem) return false;
    if (fltClassification && r.classification !== fltClassification) return false;
    if (fltDeprecated && !r.isDeprecated) return false;
    return true;
  });
  rows = sortRows(rows, "programs");
  const countEl = document.getElementById("progCount");
  if (countEl) countEl.textContent = `${rows.length} of ${DATA.progs.programs.length} programs`;

  const body = document.getElementById("progBody");
  if (!body) return;
  body.innerHTML = rows.map(r =>
    `<tr class="clickable${r.isDeprecated ? " candidate" : ""}" onclick="window._showProgramDetail('${esc(r.program)}')">` +
    `<td class="mono">${esc(r.program)}</td>` +
    `<td>${classTag(r.classification)}</td>` +
    `<td>${esc(r.cobdokSystem || "")}</td>` +
    `<td>${esc(r.cobdokDelsystem || "")}</td>` +
    `<td>${sourceTag(r.source)}</td>` +
    `<td>${sourceTypeTag(r.sourceType)}</td>` +
    `<td>${esc(r.area || "")}</td>` +
    `<td>${esc(r.description || "")}</td>` +
    `<td style="text-align:right">${r.copyCount || 0}</td>` +
    `<td style="text-align:right">${r.sqlOpCount || 0}</td>` +
    `<td style="text-align:right">${r.callCount || 0}</td>` +
    `<td style="text-align:right">${r.fileIOCount || 0}</td>` +
    `<td>${deprecatedTag(r.isDeprecated)}</td></tr>`
  ).join("");
}

// ═══════════════════════════════════════════════════════════════════════
//  SQL TAB
// ═══════════════════════════════════════════════════════════════════════
function renderSql() {
  if (!DATA.sql) return "<p>No data</p>";
  let h = '<div class="filter-row">';
  const schemas = [...new Set(DATA.sql.tableReferences.map(r => r.schema))].sort();
  const ops = [...new Set(DATA.sql.tableReferences.map(r => r.operation))].sort();
  h += `<label>Schema</label><select id="fltSchema"><option value="">All</option>${schemas.map(s => `<option>${esc(s)}</option>`).join("")}</select>`;
  h += `<label>Operation</label><select id="fltOp"><option value="">All</option>${ops.map(s => `<option>${esc(s)}</option>`).join("")}</select>`;
  h += '<label>Table</label><input id="fltTable" placeholder="filter table...">';
  h += "</div>";
  h += '<div class="result-count" id="sqlCount"></div>';
  h += '<div style="overflow-x:auto"><table class="viewer-table"><thead><tr>';
  [["program","Program"],["schema","Schema"],["tableName","Table"],["operation","Operation"],["existsInDb2","DB2"]].forEach(([k, l]) => {
    h += `<th onclick="window._headerClick('sql','${k}')">${esc(l)}${sortArrow("sql", k)}</th>`;
  });
  h += '</tr></thead><tbody id="sqlBody"></tbody></table></div>';
  return h;
}

function fillSql() {
  if (!DATA.sql) return;
  const fltSchema = document.getElementById("fltSchema")?.value || "";
  const fltOp = document.getElementById("fltOp")?.value || "";
  const fltTable = (document.getElementById("fltTable")?.value || "").toLowerCase();
  let rows = DATA.sql.tableReferences.filter(r => {
    if (!matchesFilter(r, ["program","schema","tableName","operation"])) return false;
    if (fltSchema && r.schema !== fltSchema) return false;
    if (fltOp && r.operation !== fltOp) return false;
    if (fltTable && !r.tableName.toLowerCase().includes(fltTable)) return false;
    return true;
  });
  rows = sortRows(rows, "sql");
  const countEl = document.getElementById("sqlCount");
  if (countEl) countEl.textContent = `${rows.length} of ${DATA.sql.tableReferences.length} references`;
  const body = document.getElementById("sqlBody");
  if (!body) return;
  body.innerHTML = rows.map(r =>
    `<tr class="clickable" onclick="window._showProgramDetail('${esc(r.program)}')">` +
    `<td class="mono">${esc(r.program)}</td><td>${esc(r.schema)}</td>` +
    `<td class="mono">${esc(r.tableName)}</td><td>${esc(r.operation)}</td>` +
    `<td>${boolTag(r.existsInDb2)}</td></tr>`
  ).join("");
}

// ═══════════════════════════════════════════════════════════════════════
//  COPY TAB
// ═══════════════════════════════════════════════════════════════════════
function renderCopy() {
  if (!DATA.copy) return "<p>No data</p>";
  let h = '<div class="result-count" id="copyCount"></div>';
  h += '<div style="overflow-x:auto"><table class="viewer-table"><thead><tr>';
  [["name","Name"],["type","Type"],["localPath","Local Path"],["usedByCount","Used By"]].forEach(([k, l]) => {
    h += `<th onclick="window._headerClick('copy','${k}')">${esc(l)}${sortArrow("copy", k)}</th>`;
  });
  h += '</tr></thead><tbody id="copyBody"></tbody></table></div>';
  return h;
}

function fillCopy() {
  if (!DATA.copy) return;
  let rows = DATA.copy.copyElements.map(r => ({ ...r, usedByCount: (r.usedBy || []).length }));
  rows = rows.filter(r => matchesFilter(r, ["name","type","localPath"]));
  rows = sortRows(rows, "copy");
  const countEl = document.getElementById("copyCount");
  if (countEl) countEl.textContent = `${rows.length} of ${DATA.copy.copyElements.length} elements`;
  const body = document.getElementById("copyBody");
  if (!body) return;
  body.innerHTML = rows.map(r =>
    `<tr class="clickable" onclick="window._showCopyDetail('${esc(r.name)}')">` +
    `<td class="mono">${esc(r.name)}</td><td>${esc(r.type)}</td>` +
    `<td>${fileLink(r.localPath)}</td><td style="text-align:right">${r.usedByCount}</td></tr>`
  ).join("");
}

// ═══════════════════════════════════════════════════════════════════════
//  CALL TAB
// ═══════════════════════════════════════════════════════════════════════
function renderCall() {
  if (!DATA.call) return "<p>No data</p>";
  let h = '<div class="filter-row"><label>Program</label><input id="fltCallProg" placeholder="filter caller or callee..."></div>';
  h += '<div class="result-count" id="callCount"></div>';
  h += '<div style="overflow-x:auto"><table class="viewer-table"><thead><tr>';
  [["caller","Caller"],["callee","Callee"]].forEach(([k, l]) => {
    h += `<th onclick="window._headerClick('call','${k}')">${esc(l)}${sortArrow("call", k)}</th>`;
  });
  h += '</tr></thead><tbody id="callBody"></tbody></table></div>';
  return h;
}

function fillCall() {
  if (!DATA.call) return;
  const fltProg = (document.getElementById("fltCallProg")?.value || "").toLowerCase();
  let rows = DATA.call.edges.filter(r => {
    if (!matchesFilter(r, ["caller","callee"])) return false;
    if (fltProg && !r.caller.toLowerCase().includes(fltProg) && !r.callee.toLowerCase().includes(fltProg)) return false;
    return true;
  });
  rows = sortRows(rows, "call");
  const countEl = document.getElementById("callCount");
  if (countEl) countEl.textContent = `${rows.length} of ${DATA.call.edges.length} edges`;
  const body = document.getElementById("callBody");
  if (!body) return;
  body.innerHTML = rows.map(r =>
    `<tr><td><a href="#" class="mono" onclick="event.preventDefault();window._showProgramDetail('${esc(r.caller)}')">${esc(r.caller)}</a></td>` +
    `<td><a href="#" class="mono" onclick="event.preventDefault();window._showProgramDetail('${esc(r.callee)}')">${esc(r.callee)}</a></td></tr>`
  ).join("");
}

// ═══════════════════════════════════════════════════════════════════════
//  FILE I/O TAB
// ═══════════════════════════════════════════════════════════════════════
function renderFio() {
  if (!DATA.fio) return "<p>No data</p>";
  let h = '<div class="result-count" id="fioCount"></div>';
  h += '<div style="overflow-x:auto"><table class="viewer-table"><thead><tr>';
  [["program","Program"],["logicalName","Logical"],["physicalName","Physical"],["assignType","Assign"],["operations","Operations"]].forEach(([k, l]) => {
    h += `<th onclick="window._headerClick('fio','${k}')">${esc(l)}${sortArrow("fio", k)}</th>`;
  });
  h += '</tr></thead><tbody id="fioBody"></tbody></table></div>';
  return h;
}

function fillFio() {
  if (!DATA.fio) return;
  let rows = DATA.fio.fileReferences.filter(r => matchesFilter(r, ["program","logicalName","physicalName","assignType"]));
  rows = sortRows(rows, "fio");
  const countEl = document.getElementById("fioCount");
  if (countEl) countEl.textContent = `${rows.length} of ${DATA.fio.fileReferences.length} references`;
  const body = document.getElementById("fioBody");
  if (!body) return;
  body.innerHTML = rows.map(r =>
    `<tr class="clickable" onclick="window._showProgramDetail('${esc(r.program)}')">` +
    `<td class="mono">${esc(r.program)}</td><td class="mono">${esc(r.logicalName)}</td>` +
    `<td class="mono">${esc(r.physicalName)}</td><td>${esc(r.assignType)}</td>` +
    `<td>${(r.operations || []).join(", ")}</td></tr>`
  ).join("");
}

// ═══════════════════════════════════════════════════════════════════════
//  DETAIL OVERLAY — PROGRAM
// ═══════════════════════════════════════════════════════════════════════
function showProgramDetail(name) {
  const m = masterIndex[name];
  const p = DATA.progs?.programs?.find(x => x.program === name);
  if (!m && !p) return;

  document.getElementById("detailTitle").textContent = name;
  let h = '';

  h += '<div class="detail-section"><h3>Properties</h3><div class="detail-grid">';
  if (p) {
    h += `<div class="dk">Source</div><div class="dv">${sourceTag(p.source)}</div>`;
    h += `<div class="dk">Data Source</div><div class="dv">${sourceTypeTag(p.sourceType)}</div>`;
    if (p.area) h += `<div class="dk">Area</div><div class="dv">${esc(p.area)}</div>`;
    if (p.type) h += `<div class="dk">Type</div><div class="dv">${esc(p.type)}</div>`;
    if (p.description) h += `<div class="dk">Description</div><div class="dv">${esc(p.description)}</div>`;
    if (p.descriptionNorwegian) h += `<div class="dk">Beskrivelse</div><div class="dv">${esc(p.descriptionNorwegian)}</div>`;
    if (p.cobdokSystem) h += `<div class="dk">COBDOK System</div><div class="dv">${esc(p.cobdokSystem)}</div>`;
    if (p.cobdokDelsystem) h += `<div class="dk">Delsystem</div><div class="dv">${esc(p.cobdokDelsystem)}</div>`;
    if (p.isDeprecated) h += `<div class="dk">Status</div><div class="dv">${tag("DEPRECATED / UTGATT", "no")}</div>`;
    if (p.classification) {
      h += `<div class="dk">Classification</div><div class="dv">${classTag(p.classification)}</div>`;
      if (p.classificationConfidence) h += `<div class="dk">Confidence</div><div class="dv">${esc(p.classificationConfidence)}</div>`;
      if (p.classificationEvidence) h += `<div class="dk">Evidence</div><div class="dv">${esc(p.classificationEvidence)}</div>`;
    }
  }
  if (m?.futureProjectName) h += `<div class="dk">Future C# Name</div><div class="dv">${tag(m.futureProjectName, "future")}</div>`;
  if (m?.sourcePath) h += `<div class="dk">Source File</div><div class="dv">${fileLink(m.sourcePath)}</div>`;
  h += "</div>";

  const autoDocFile = name + ".CBL.json";
  const adExists = m?.autoDocExists !== false;
  h += `<div style="margin-top:10px;display:flex;align-items:center;gap:8px">`;
  if (adExists) {
    h += `<a class="autodoc-link-btn" href="doc.html?file=${encodeURIComponent(autoDocFile)}" target="_blank" rel="noopener">View Full Documentation</a>`;
  } else {
    h += `<span class="autodoc-link-btn" style="opacity:.35;pointer-events:none;cursor:default">View Full Documentation</span>`;
  }
  h += `<span class="autodoc-badge" id="autodocBadge_${esc(name)}" style="display:${adExists ? 'inline-block' : 'none'}">AutoDoc</span>`;
  h += `</div>`;
  h += "</div>";

  if (adExists) checkAutoDocAvailable(name, autoDocFile);

  if (m?.copyElements?.length) {
    h += `<div class="detail-section"><h3>Copy Elements (${m.copyElements.length})</h3>`;
    h += '<table class="sub-table viewer-table"><thead><tr><th>Name</th><th>Type</th><th>Local Path</th></tr></thead><tbody>';
    m.copyElements.forEach(c => {
      const ce = DATA.copy?.copyElements?.find(x => x.name === c.name);
      h += `<tr><td class="mono">${esc(c.name)}</td><td>${esc(c.type)}</td><td>${fileLink(ce?.localPath)}</td></tr>`;
    });
    h += "</tbody></table></div>";
  }

  if (m?.sqlOperations?.length) {
    h += `<div class="detail-section"><h3>SQL Operations (${m.sqlOperations.length})</h3>`;
    h += '<table class="sub-table viewer-table"><thead><tr><th>Schema</th><th>Table</th><th>Future Name</th><th>Operation</th></tr></thead><tbody>';
    m.sqlOperations.forEach(s => {
      const fn = s.futureTableName ? tag(s.futureTableName, "future") : '—';
      h += `<tr><td>${esc(s.schema)}</td><td class="mono">${esc(s.tableName)}</td><td>${fn}</td><td>${esc(s.operation)}</td></tr>`;
    });
    h += "</tbody></table></div>";
  }

  if (m?.callTargets?.length) {
    h += `<div class="detail-section"><h3>CALL Targets (${m.callTargets.length})</h3>`;
    h += '<div style="display:flex;flex-wrap:wrap;gap:6px">';
    m.callTargets.forEach(c => { h += `<a href="#" class="mono tag tag-call" onclick="event.preventDefault();window._showProgramDetail('${esc(c)}')">${esc(c)}</a>`; });
    h += "</div></div>";
  }

  if (DATA.call) {
    const callers = DATA.call.edges.filter(e => e.callee === name).map(e => e.caller);
    if (callers.length) {
      h += `<div class="detail-section"><h3>Called By (${callers.length})</h3>`;
      h += '<div style="display:flex;flex-wrap:wrap;gap:6px">';
      callers.forEach(c => { h += `<a href="#" class="mono tag tag-original" onclick="event.preventDefault();window._showProgramDetail('${esc(c)}')">${esc(c)}</a>`; });
      h += "</div></div>";
    }
  }

  if (m?.fileIO?.length) {
    h += `<div class="detail-section"><h3>File I/O (${m.fileIO.length})</h3>`;
    h += '<table class="sub-table viewer-table"><thead><tr><th>Logical</th><th>Physical</th><th>Assign</th><th>Operations</th></tr></thead><tbody>';
    m.fileIO.forEach(f => {
      h += `<tr><td class="mono">${esc(f.logicalName)}</td><td class="mono">${esc(f.physicalName)}</td>` +
           `<td>${esc(f.assignType)}</td><td>${(f.operations || []).join(", ")}</td></tr>`;
    });
    h += "</tbody></table></div>";
  }

  const mmd = buildProgramDiagram(name, m);
  if (mmd) {
    h += '<div class="detail-section"><h3>Dependency Diagram</h3>';
    h += '<div class="diagram-container" id="mermaidTarget"></div></div>';
  }

  document.getElementById("detailBody").innerHTML = h;
  document.getElementById("detailOverlay").classList.add("open");

  if (mmd) renderMermaid("mermaidTarget", mmd);
}

function showCopyDetail(name) {
  const ce = DATA.copy?.copyElements?.find(x => x.name === name);
  if (!ce) return;
  document.getElementById("detailTitle").textContent = ce.name;
  let h = '<div class="detail-section"><h3>Properties</h3><div class="detail-grid">';
  h += `<div class="dk">Type</div><div class="dv">${esc(ce.type)}</div>`;
  h += `<div class="dk">Local Path</div><div class="dv">${fileLink(ce.localPath)}</div>`;
  h += `<div class="dk">Used By</div><div class="dv">${(ce.usedBy || []).length} programs</div>`;
  h += "</div></div>";
  if (ce.usedBy?.length) {
    h += `<div class="detail-section"><h3>Used By Programs</h3><div style="display:flex;flex-wrap:wrap;gap:6px">`;
    ce.usedBy.forEach(p => { h += `<a href="#" class="mono tag tag-original" onclick="event.preventDefault();window._showProgramDetail('${esc(p)}')">${esc(p)}</a>`; });
    h += "</div></div>";
  }
  document.getElementById("detailBody").innerHTML = h;
  document.getElementById("detailOverlay").classList.add("open");
}

// ═══════════════════════════════════════════════════════════════════════
//  MERMAID PER-PROGRAM DIAGRAM
// ═══════════════════════════════════════════════════════════════════════
function buildProgramDiagram(name, m) {
  if (!m) return null;
  const hasCalls = m.callTargets?.length > 0;
  const hasSql = m.sqlOperations?.length > 0;
  const hasFiles = m.fileIO?.length > 0;
  const callers = DATA.call ? DATA.call.edges.filter(e => e.callee === name).map(e => e.caller) : [];
  if (!hasCalls && !hasSql && !hasFiles && callers.length === 0) return null;

  const lines = ['%%{ init: { "flowchart": { "curve": "basis" } } }%%', "flowchart LR"];
  const pid = mmdId(name);
  lines.push(`  ${pid}[[${name}]]`);
  lines.push(`  style ${pid} stroke:#4f8cff,stroke-width:3px,fill:#1a2744,color:#e2e4ea`);

  const callerSet = new Set();
  callers.forEach(c => {
    if (callerSet.has(c)) return;
    callerSet.add(c);
    const cid = mmdId(c) + "_caller";
    lines.push(`  ${cid}[[${c}]]`);
    lines.push(`  ${cid} --"calls"--> ${pid}`);
    lines.push(`  style ${cid} stroke:#8b90a5,fill:#242838,color:#e2e4ea`);
  });

  if (hasCalls) {
    const callSet = new Set();
    m.callTargets.forEach(c => {
      const cn = typeof c === "string" ? c : String(c);
      if (callSet.has(cn)) return;
      callSet.add(cn);
      const cid = mmdId(cn) + "_call";
      lines.push(`  ${cid}[[${cn}]]`);
      lines.push(`  ${pid} --"call"--> ${cid}`);
      lines.push(`  style ${cid} stroke:#34d399,fill:#1a2d27,color:#e2e4ea`);
    });
  }

  if (hasSql) {
    const tableOps = {};
    m.sqlOperations.forEach(s => {
      const tkey = s.schema && s.schema !== "(unqualified)" && s.schema !== "(UNQUALIFIED)" ? s.schema + "." + s.tableName : s.tableName;
      if (!tableOps[tkey]) tableOps[tkey] = new Set();
      tableOps[tkey].add(s.operation);
    });
    Object.entries(tableOps).forEach(([tbl, ops]) => {
      const tid = "sql_" + mmdId(tbl);
      lines.push(`  ${tid}[(${tbl})]`);
      lines.push(`  ${pid} --"${[...ops].join(", ")}"--> ${tid}`);
      lines.push(`  style ${tid} stroke:#a78bfa,fill:#2a1f44,color:#e2e4ea`);
    });
  }

  if (hasFiles) {
    const fileSet = {};
    m.fileIO.forEach(f => {
      const fname = f.physicalName || f.logicalName;
      if (!fileSet[fname]) fileSet[fname] = new Set();
      (f.operations || []).forEach(op => fileSet[fname].add(op));
    });
    Object.entries(fileSet).forEach(([fname, ops]) => {
      const fid = "file_" + mmdId(fname);
      lines.push(`  ${fid}[/${fname}/]`);
      lines.push(`  ${pid} --"${[...ops].join(", ")}"--> ${fid}`);
      lines.push(`  style ${fid} stroke:#fb923c,fill:#2d1f0f,color:#e2e4ea`);
    });
  }

  return lines.join("\n");
}

async function renderMermaid(targetId, code) {
  const el = document.getElementById(targetId);
  if (!el) return;
  try {
    const id = "mmd_" + Date.now();
    const { svg } = await mermaid.render(id, code);
    el.innerHTML = svg;
  } catch (e) {
    el.innerHTML = `<pre style="color:var(--red);font-size:12px">Diagram error: ${e.message}</pre>`;
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  RENDER / EVENTS
// ═══════════════════════════════════════════════════════════════════════
function closeDetail() { document.getElementById("detailOverlay").classList.remove("open"); }

function render() {
  renderTabs();
  const area = document.getElementById("contentArea");
  const fillMap = { programs: fillPrograms, sql: fillSql, copy: fillCopy, call: fillCall, fio: fillFio };

  if (activeTab === "summary") { area.innerHTML = `<div class="panel active">${renderSummary()}</div>`; return; }

  const renderers = { programs: renderPrograms, sql: renderSql, copy: renderCopy, call: renderCall, fio: renderFio };
  const renderFn = renderers[activeTab];
  if (!renderFn) return;

  area.innerHTML = `<div class="panel active">${renderFn()}</div>`;

  const fillFn = fillMap[activeTab];
  if (fillFn) {
    setTimeout(() => {
      area.querySelectorAll(".filter-row select, .filter-row input[type='text'], .filter-row input[type='checkbox']").forEach(el => {
        el.addEventListener(el.type === "checkbox" ? "change" : "input", fillFn);
      });
      fillFn();
    }, 0);
  }
}

document.getElementById("detailClose").addEventListener("click", closeDetail);
document.getElementById("detailOverlay").addEventListener("click", e => {
  if (e.target === document.getElementById("detailOverlay")) closeDetail();
});
document.addEventListener("keydown", e => { if (e.key === "Escape") closeDetail(); });

let searchTimer;
document.getElementById("globalSearch").addEventListener("input", e => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => { globalFilter = e.target.value; render(); }, 200);
});

window._headerClick = headerClick;
window._showProgramDetail = showProgramDetail;
window._showCopyDetail = showCopyDetail;

// ═══════════════════════════════════════════════════════════════════════
//  INIT
// ═══════════════════════════════════════════════════════════════════════
async function init() {
  alias = await initAliasSelect("aliasSelect");
  setAliasInLink("graphLink", "graph.html", alias);
  await loadAllData();
  render();
}

init().catch(e => {
  document.getElementById("contentArea").innerHTML = `<div class="panel active"><p style="color:var(--red)">${String(e)}</p></div>`;
});
