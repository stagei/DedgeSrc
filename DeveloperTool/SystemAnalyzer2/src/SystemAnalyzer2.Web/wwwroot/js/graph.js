import { initAliasSelect, getAliasFromUrl, setAliasInLink } from "./shared.js";

const mermaid = window.mermaid;
if (mermaid) {
  const mermaidTheme = document.documentElement.getAttribute("data-theme") === "light" ? "default" : "dark";
  mermaid.initialize({
    startOnLoad: false, theme: mermaidTheme, securityLevel: "loose",
    flowchart: { useMaxWidth: false, htmlLabels: true, curve: "basis" },
    suppressErrorRendering: true, maxTextSize: 500000, maxEdges: 10000
  });
} else {
  console.warn("[graph] Mermaid library not loaded — Mermaid renderer will be unavailable");
}

function setProgress(pct, text) {
  const bar = document.getElementById("progressBar");
  const pctEl = document.getElementById("progressPct");
  const textEl = document.getElementById("loadingText");
  if (bar) bar.style.width = pct + "%";
  if (pctEl) pctEl.textContent = Math.round(pct) + "%";
  if (textEl && text) textEl.textContent = text;
}
function yieldToUI(ms) { return new Promise(r => setTimeout(r, ms || 30)); }

const DATA = {
  master: null, progs: null, call: null, sql: null, fio: null, copy: null, verify: null,
  seedAll: null, businessAreas: null,
  db2TableValidation: null, appliedExclusions: null, standardCobolFiltered: null
};

const masterIndex = {};
const progIndex = {};
const classIndex = {};
const categorySet = new Set();
const verifyIndex = {};
const calledByIndex = {};
const copyByProgram = {};
const copyIndex = {};
const businessAreaIndex = {};
const businessAreaSet = new Set();
const autoDocCache = new Map();
const expandedPrograms = new Map();
let isolationMode = false;
let isolationSet = new Set();

let currentNodes = [];
let currentEdges = [];
let currentGroupData = [];
let activeRenderer = null;
let gojsDiagram = null;
let mermaidPanZoom = null;
let initialized = false;
let alias = "";

function autoDocQuerySuffix() {
  return alias ? `?alias=${encodeURIComponent(alias)}` : "";
}

/** Per-analysis AutoDoc under alias/autodoc when alias is set; else central store only. */
function autodocUrl(fileName) {
  return `api/autodoc/${encodeURIComponent(fileName)}${autoDocQuerySuffix()}`;
}

function esc(s) {
  if (s == null) return "";
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
function escJs(s) { return String(s).replace(/\\/g, "\\\\").replace(/'/g, "\\'"); }
function mmdId(name) { return name.replace(/[^a-zA-Z0-9_]/g, "_"); }

async function fetchJson(fileName) {
  try {
    const r = await fetch(`api/data/${encodeURIComponent(alias)}/${fileName}`);
    if (r.ok) return await r.json();
    console.warn(`[graph] ${fileName}: HTTP ${r.status}`);
  } catch (e) {
    console.warn(`[graph] ${fileName}: ${e.message}`);
  }
  return null;
}

async function loadCoreData() {
  const badge = document.getElementById("rendererBadge");
  if (badge) badge.textContent = "Loading…";

  setProgress(15, "Loading program list…");
  await yieldToUI(100);
  DATA.progs = await fetchJson("all_total_programs.json");

  setProgress(30, "Loading call graph…");
  await yieldToUI(100);
  DATA.call = await fetchJson("all_call_graph.json");

  if (!DATA.progs && !DATA.call) {
    const msg = `No data files found for alias "${alias}". Run an analysis first.`;
    setProgress(0, msg);
    throw new Error(msg);
  }

  const progCount = DATA.progs?.programs?.length || 0;
  const edgeCount = DATA.call?.edges?.length || 0;
  setProgress(40, `Building indices (${progCount} programs, ${edgeCount} edges)…`);
  await yieldToUI(150);
  buildIndices();
  setProgress(50, "Preparing graph…");
  await yieldToUI(100);
}

async function loadSupplementalData() {
  const files = [
    ["dependency_master.json", "master"],
    ["all_sql_tables.json", "sql"],
    ["all_file_io.json", "fio"],
    ["all_copy_elements.json", "copy"],
    ["source_verification.json", "verify"],
    ["all.json", "seedAll"],
    ["db2_table_validation.json", "db2TableValidation"],
    ["applied_exclusions.json", "appliedExclusions"],
    ["standard_cobol_filtered.json", "standardCobolFiltered"],
    ["business_areas.json", "businessAreas"]
  ];
  const missing = [];
  for (let i = 0; i < files.length; i++) {
    const [file, key] = files[i];
    DATA[key] = await fetchJson(file);
    if (!DATA[key]) missing.push(file);
  }
  if (missing.length > 0) console.warn("[graph] Missing supplemental files:", missing.join(", "));
  buildIndices();
  fetch("api/autodoc/status").then(r => r.json()).then(s => {
    if (s.available && s.jsonFileCount > 0) warmAutoDocCache();
    else console.log("[graph] AutoDocJson not available — flowchart on demand only", s);
  }).catch(() => console.log("[graph] AutoDocJson status check failed — flowchart on demand only"));
}

function buildIndices() {
  if (DATA.master?.programs) DATA.master.programs.forEach(p => { masterIndex[p.program] = p; });
  if (DATA.progs?.programs) DATA.progs.programs.forEach(p => { progIndex[p.program] = p; });
  if (DATA.progs?.programs) {
    DATA.progs.programs.forEach(p => {
      if (p.classification) {
        classIndex[p.program] = { classification: p.classification, confidence: p.classificationConfidence, evidence: p.classificationEvidence };
        categorySet.add(p.classification);
      }
    });
  }
  if (DATA.verify) {
    ["programsCblFound", "programsUncertainFound", "programsUvFuzzyMatch", "programsOtherType"].forEach(key => {
      (DATA.verify[key] || []).forEach(p => { verifyIndex[p.program] = p; });
    });
  }
  if (DATA.call?.edges) {
    DATA.call.edges.forEach(e => {
      if (!calledByIndex[e.callee]) calledByIndex[e.callee] = [];
      calledByIndex[e.callee].push(e.caller);
    });
  }
  if (DATA.businessAreas?.programAreaMap) {
    Object.keys(businessAreaIndex).forEach(k => delete businessAreaIndex[k]);
    businessAreaSet.clear();
    Object.entries(DATA.businessAreas.programAreaMap).forEach(([prog, areaId]) => {
      businessAreaIndex[prog] = areaId;
      if (typeof areaId === "string") businessAreaSet.add(areaId);
      else if (Array.isArray(areaId)) areaId.forEach(a => businessAreaSet.add(a));
    });
  }
  if (DATA.copy?.copyElements) {
    DATA.copy.copyElements.forEach(ce => {
      copyIndex[ce.name] = ce;
      (ce.usedBy || []).forEach(prog => {
        if (!copyByProgram[prog]) copyByProgram[prog] = [];
        copyByProgram[prog].push(ce);
      });
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  FILTER PANEL
// ═══════════════════════════════════════════════════════════════════════

const DEFAULT_BOX_ORDER = ["elementTypes", "classifications", "businessAreas", "sqlOperations", "programs", "tables", "files"];
const DEFAULT_OPERATORS = ["and", "and", "and", "and", "and", "and"];

class FilterPanel {
  constructor() {
    this.overlay = document.getElementById("filterPanelOverlay");
    this.body = document.getElementById("fpBody");
    this.applied = this._defaultState();
    this.working = null;
  }

  _defaultState() {
    return {
      boxOrder: [...DEFAULT_BOX_ORDER],
      operators: [...DEFAULT_OPERATORS],
      selections: {
        elementTypes: { programs: true, tables: false, inputFiles: false, outputFiles: false, callLinks: true, copyElements: false, vsamStorage: false, crossTechLinks: true },
        classifications: null,
        sqlOperations: null,
        programs: null,
        tables: null,
        files: null
      },
      searches: { programs: "", tables: "", files: "" }
    };
  }

  _cloneState(st) {
    return JSON.parse(JSON.stringify(st));
  }

  setApplied(st) {
    if (st) this.applied = this._cloneState(st);
  }

  getApplied() { return this.applied; }

  open() {
    this.working = this._cloneState(this.applied);
    this._render();
    this.overlay.classList.add("open");
  }

  close() {
    this.overlay.classList.remove("open");
    this.working = null;
  }

  async apply() {
    this._syncWorkingFromDom();
    this.applied = this._cloneState(this.working);
    this.close();
    document.getElementById("loadingMsg").style.display = "flex";
    setProgress(50, "Applying filters…");
    await yieldToUI();
    await buildGraph();
    saveState();
  }

  cancel() {
    this.close();
  }

  reset() {
    this.working = this._defaultState();
    this._populateDefaultSelections();
    this._render();
  }

  _populateDefaultSelections() {
    const st = this.working;
    if (!st.selections.classifications && categorySet.size > 0) {
      st.selections.classifications = {};
      categorySet.forEach(c => { st.selections.classifications[c] = true; });
    }
    if (!st.selections.businessAreas && businessAreaSet.size > 0) {
      st.selections.businessAreas = {};
      businessAreaSet.forEach(a => { st.selections.businessAreas[a] = true; });
    }
    if (!st.selections.sqlOperations) {
      const ops = this._allSqlOperations();
      if (ops.length > 0) {
        st.selections.sqlOperations = {};
        ops.forEach(op => { st.selections.sqlOperations[op] = true; });
      }
    }
  }

  // ── Gather all possible items for each box from DATA ──────────────
  _allPrograms() {
    const src = DATA.progs?.programs || DATA.master?.programs || [];
    return src.map(p => p.program).sort();
  }

  _allCategories() {
    const counts = {};
    Object.values(classIndex).forEach(c => { counts[c.classification] = (counts[c.classification] || 0) + 1; });
    return [...categorySet].sort((a, b) => (counts[b] || 0) - (counts[a] || 0)).map(cat => ({ name: cat, count: counts[cat] || 0 }));
  }

  _allBusinessAreas() {
    const counts = {};
    Object.values(businessAreaIndex).forEach(a => {
      const id = typeof a === "string" ? a : a[0];
      counts[id] = (counts[id] || 0) + 1;
    });
    const areas = DATA.businessAreas?.areas || [];
    return [...businessAreaSet].sort((a, b) => (counts[b] || 0) - (counts[a] || 0)).map(areaId => {
      const areaObj = areas.find(x => x.id === areaId);
      return { id: areaId, name: areaObj?.name || areaId, count: counts[areaId] || 0 };
    });
  }

  _programsByBusinessAreas(selected) {
    const progs = new Set();
    Object.entries(businessAreaIndex).forEach(([prog, areaId]) => {
      const id = typeof areaId === "string" ? areaId : areaId[0];
      if (selected[id]) progs.add(prog);
    });
    return progs;
  }

  _allSqlOperations() {
    const ops = new Set();
    (DATA.sql?.tableReferences || []).forEach(r => {
      if (r.operation) ops.add(r.operation);
    });
    return [...ops].sort();
  }

  _programsBySqlOperations(selectedOps) {
    if (!selectedOps || Object.keys(selectedOps).length === 0) return null;
    const activeOps = new Set(Object.entries(selectedOps).filter(([, v]) => v).map(([k]) => k));
    if (activeOps.size === 0) return new Set();
    const progs = new Set();
    (DATA.sql?.tableReferences || []).forEach(r => {
      if (r.operation && activeOps.has(r.operation)) progs.add(r.program);
    });
    return progs;
  }

  _allTableOps() {
    const map = {};
    (DATA.sql?.tableReferences || []).forEach(r => {
      const tkey = r.schema && r.schema !== "(unqualified)" && r.schema !== "(UNQUALIFIED)" ? r.schema + "." + r.tableName : r.tableName;
      if (!map[tkey]) map[tkey] = new Set();
      map[tkey].add(r.operation);
    });
    const items = [];
    Object.entries(map).sort((a, b) => a[0].localeCompare(b[0])).forEach(([tbl, ops]) => {
      items.push({ label: `${tbl} (*)`, table: tbl, op: "*" });
      [...ops].sort().forEach(op => {
        items.push({ label: `${tbl} (${op})`, table: tbl, op });
      });
    });
    return items;
  }

  _allFiles() {
    const set = new Set();
    (DATA.fio?.fileReferences || []).forEach(r => {
      set.add(r.physicalName || r.logicalName);
    });
    return [...set].sort();
  }

  _programsByCategories(selectedCats) {
    if (!selectedCats || Object.keys(selectedCats).length === 0) return null;
    const activeCats = new Set(Object.entries(selectedCats).filter(([, v]) => v).map(([k]) => k));
    if (activeCats.size === 0) return new Set();
    const progs = new Set();
    Object.entries(classIndex).forEach(([prog, info]) => {
      if (activeCats.has(info.classification)) progs.add(prog);
    });
    return progs;
  }

  _tablesByPrograms(progSet) {
    if (!progSet) return null;
    const tblOps = new Set();
    (DATA.sql?.tableReferences || []).forEach(r => {
      if (!progSet.has(r.program)) return;
      const tkey = r.schema && r.schema !== "(unqualified)" && r.schema !== "(UNQUALIFIED)" ? r.schema + "." + r.tableName : r.tableName;
      tblOps.add(`${tkey} (*)`);
      tblOps.add(`${tkey} (${r.operation})`);
    });
    return tblOps;
  }

  _filesByPrograms(progSet) {
    if (!progSet) return null;
    const files = new Set();
    (DATA.fio?.fileReferences || []).forEach(r => {
      if (!progSet.has(r.program)) return;
      files.add(r.physicalName || r.logicalName);
    });
    return files;
  }

  // ── Cascade: compute visible items for each box based on upstream ──
  _computeCascade() {
    const w = this.working;
    const cascade = {};
    let upstreamPrograms = null;

    for (let i = 0; i < w.boxOrder.length; i++) {
      const boxType = w.boxOrder[i];
      const op = i > 0 ? w.operators[i - 1] : "initial";

      if (op === "none") {
        cascade[boxType] = { visible: null, dimmed: true };
        continue;
      }

      cascade[boxType] = { visible: null, dimmed: false };

      if (boxType === "classifications") {
        const selected = w.selections.classifications;
        if (selected && op !== "none") {
          const catProgs = this._programsByCategories(selected);
          upstreamPrograms = this._combine(upstreamPrograms, catProgs, op);
        }
      } else if (boxType === "businessAreas") {
        const selected = w.selections.businessAreas;
        if (selected && op !== "none") {
          const baProgs = this._programsByBusinessAreas(selected);
          upstreamPrograms = this._combine(upstreamPrograms, baProgs, op);
        }
      } else if (boxType === "sqlOperations") {
        const selected = w.selections.sqlOperations;
        if (selected && op !== "none") {
          const opProgs = this._programsBySqlOperations(selected);
          upstreamPrograms = this._combine(upstreamPrograms, opProgs, op);
        }
      } else if (boxType === "programs") {
        if (upstreamPrograms) {
          cascade[boxType].visible = upstreamPrograms;
        }
        const selected = w.selections.programs;
        if (selected) {
          const selSet = new Set(Object.entries(selected).filter(([, v]) => v).map(([k]) => k));
          if (selSet.size > 0) {
            upstreamPrograms = this._combine(upstreamPrograms, selSet, op);
          }
        }
      } else if (boxType === "tables") {
        if (upstreamPrograms) {
          cascade[boxType].visible = this._tablesByPrograms(upstreamPrograms);
        }
      } else if (boxType === "files") {
        if (upstreamPrograms) {
          cascade[boxType].visible = this._filesByPrograms(upstreamPrograms);
        }
      }
    }
    return cascade;
  }

  _combine(existing, incoming, op) {
    if (!incoming) return existing;
    if (op === "initial" || op === "and") {
      return existing ? this._intersect(existing, incoming) : incoming;
    }
    if (op === "or") {
      return existing ? this._union(existing, incoming) : incoming;
    }
    return existing;
  }

  _intersect(a, b) { return new Set([...a].filter(x => b.has(x))); }
  _union(a, b) { return new Set([...a, ...b]); }

  // ── Sync working state from current DOM checkboxes ────────────────
  _syncWorkingFromDom() {
    if (!this.working) return;
    const w = this.working;

    this.body.querySelectorAll(".fp-operator").forEach(opEl => {
      const idx = parseInt(opEl.dataset.opIdx);
      const checked = opEl.querySelector("input[type='radio']:checked");
      if (checked && !isNaN(idx)) w.operators[idx] = checked.value;
    });

    this.body.querySelectorAll(".fp-box").forEach(boxEl => {
      const boxType = boxEl.dataset.boxType;
      if (!boxType) return;

      if (boxType === "elementTypes") {
        if (!w.selections.elementTypes) w.selections.elementTypes = {};
        boxEl.querySelectorAll("input[type='checkbox']").forEach(cb => {
          w.selections.elementTypes[cb.dataset.key] = cb.checked;
        });
      } else {
        const searchInput = boxEl.querySelector(".fp-box-search input");
        if (searchInput) w.searches[boxType] = searchInput.value;

        const allCbs = boxEl.querySelectorAll("input[type='checkbox']");
        if (allCbs.length > 0) {
          if (!w.selections[boxType]) w.selections[boxType] = {};
          allCbs.forEach(cb => {
            w.selections[boxType][cb.dataset.key] = cb.checked;
          });
        }
      }
    });

    const orderedTypes = [];
    this.body.querySelectorAll(".fp-box").forEach(boxEl => {
      if (boxEl.dataset.boxType) orderedTypes.push(boxEl.dataset.boxType);
    });
    if (orderedTypes.length === w.boxOrder.length) {
      w.boxOrder = orderedTypes;
    }
  }

  // ── Render the panel ──────────────────────────────────────────────
  _render() {
    const w = this.working;
    if (!w) return;
    this.body.innerHTML = "";

    const cascade = this._computeCascade();

    for (let i = 0; i < w.boxOrder.length; i++) {
      if (i > 0) {
        this.body.appendChild(this._renderOperator(i - 1, w.operators[i - 1]));
      }
      const boxType = w.boxOrder[i];
      const casc = cascade[boxType] || { visible: null, dimmed: false };
      this.body.appendChild(this._renderBox(boxType, casc));
    }

    this._setupDragDrop();
  }

  _renderOperator(idx, value) {
    const div = document.createElement("div");
    div.className = "fp-operator";
    div.dataset.opIdx = idx;
    const name = `fp_op_${idx}`;
    ["none", "and", "or"].forEach(opt => {
      const lbl = document.createElement("label");
      const radio = document.createElement("input");
      radio.type = "radio"; radio.name = name; radio.value = opt;
      if (opt === value) radio.checked = true;
      radio.addEventListener("change", () => this._onOperatorChange());
      lbl.appendChild(radio);
      lbl.appendChild(document.createTextNode(opt.charAt(0).toUpperCase() + opt.slice(1)));
      div.appendChild(lbl);
    });
    return div;
  }

  _onOperatorChange() {
    this._syncWorkingFromDom();
    this._render();
  }

  _renderBox(boxType, cascade) {
    const w = this.working;
    const box = document.createElement("div");
    box.className = "fp-box" + (cascade.dimmed ? " dimmed" : "");
    box.dataset.boxType = boxType;
    box.draggable = true;

    const header = document.createElement("div");
    header.className = "fp-box-header";
    header.innerHTML = `<div class="fp-grip"><span></span><span></span><span></span></div>`;

    const title = document.createElement("span");
    title.className = "fp-box-title";
    title.textContent = this._boxLabel(boxType);
    header.appendChild(title);

    const countSpan = document.createElement("span");
    countSpan.className = "fp-box-count";
    header.appendChild(countSpan);

    const toggleDiv = document.createElement("div");
    toggleDiv.className = "fp-box-toggle";
    const btnAll = document.createElement("button"); btnAll.textContent = "All";
    const btnNone = document.createElement("button"); btnNone.textContent = "None";
    btnAll.addEventListener("click", () => { box.querySelectorAll(".fp-box-list input[type='checkbox']").forEach(cb => { if (!cb.closest("label").classList.contains("hidden")) cb.checked = true; }); this._updateBoxCount(box); });
    btnNone.addEventListener("click", () => { box.querySelectorAll(".fp-box-list input[type='checkbox']").forEach(cb => { if (!cb.closest("label").classList.contains("hidden")) cb.checked = false; }); this._updateBoxCount(box); });
    toggleDiv.appendChild(btnAll);
    toggleDiv.appendChild(btnNone);
    header.appendChild(toggleDiv);
    box.appendChild(header);

    const needsSearch = ["programs", "tables", "files", "classifications", "businessAreas"].includes(boxType);
    if (needsSearch) {
      const searchDiv = document.createElement("div");
      searchDiv.className = "fp-box-search";
      const searchInput = document.createElement("input");
      searchInput.type = "text";
      searchInput.placeholder = "Search...";
      searchInput.value = w.searches[boxType] || "";
      searchInput.addEventListener("input", () => this._filterBoxItems(box, searchInput.value));
      searchDiv.appendChild(searchInput);
      box.appendChild(searchDiv);
    }

    const listDiv = document.createElement("div");
    listDiv.className = "fp-box-list";
    this._populateBoxItems(listDiv, boxType, cascade, w);
    box.appendChild(listDiv);

    this._updateBoxCount(box);
    if (needsSearch && (w.searches[boxType] || "").length > 0) {
      this._filterBoxItems(box, w.searches[boxType]);
    }

    return box;
  }

  _boxLabel(type) {
    const map = { elementTypes: "Element Types", classifications: "Classifications", businessAreas: "Business Areas", sqlOperations: "SQL Operations", programs: "Programs", tables: "Tables x Operation", files: "Files" };
    return map[type] || type;
  }

  _populateBoxItems(listDiv, boxType, cascade, w) {
    if (boxType === "elementTypes") {
      const items = [
        { key: "programs", label: "Programs" },
        { key: "tables", label: "Tables" },
        { key: "inputFiles", label: "Input Files" },
        { key: "outputFiles", label: "Output Files" },
        { key: "callLinks", label: "Call Links" },
        { key: "copyElements", label: "Copy Elements" },
        { key: "vsamStorage", label: "VSAM storage" },
        { key: "crossTechLinks", label: "Cross-tech links" }
      ];
      const sel = w.selections.elementTypes || {};
      items.forEach(item => {
        const lbl = document.createElement("label");
        const cb = document.createElement("input");
        cb.type = "checkbox"; cb.dataset.key = item.key;
        cb.checked = sel[item.key] !== false;
        lbl.appendChild(cb);
        lbl.appendChild(document.createTextNode(item.label));
        listDiv.appendChild(lbl);
      });
    } else if (boxType === "classifications") {
      const cats = this._allCategories();
      const sel = w.selections.classifications;
      cats.forEach(cat => {
        const lbl = document.createElement("label");
        const cb = document.createElement("input");
        cb.type = "checkbox"; cb.dataset.key = cat.name;
        cb.checked = sel ? (sel[cat.name] !== false) : true;
        cb.addEventListener("change", () => this._updateBoxCount(lbl.closest(".fp-box")));
        lbl.appendChild(cb);
        const textNode = document.createTextNode(cat.name);
        lbl.appendChild(textNode);
        const cntSpan = document.createElement("span");
        cntSpan.className = "fp-item-count";
        cntSpan.textContent = cat.count;
        lbl.appendChild(cntSpan);
        listDiv.appendChild(lbl);
      });
    } else if (boxType === "businessAreas") {
      const areas = this._allBusinessAreas();
      const sel = w.selections.businessAreas;
      if (areas.length === 0) {
        const hint = document.createElement("span");
        hint.style.cssText = "color:var(--text2);font-size:11px;padding:4px";
        hint.textContent = "No business areas data available (run Phase 8g)";
        listDiv.appendChild(hint);
      }
      areas.forEach(area => {
        const lbl = document.createElement("label");
        const cb = document.createElement("input");
        cb.type = "checkbox"; cb.dataset.key = area.id;
        cb.checked = sel ? (sel[area.id] !== false) : true;
        cb.addEventListener("change", () => this._updateBoxCount(lbl.closest(".fp-box")));
        lbl.appendChild(cb);
        const dot = document.createElement("span");
        dot.style.cssText = `display:inline-block;width:8px;height:8px;border-radius:50%;background:${getAreaColor(area.id)};margin-right:4px`;
        lbl.appendChild(dot);
        lbl.appendChild(document.createTextNode(area.name));
        const cntSpan = document.createElement("span");
        cntSpan.className = "fp-item-count";
        cntSpan.textContent = area.count;
        lbl.appendChild(cntSpan);
        listDiv.appendChild(lbl);
      });
    } else if (boxType === "sqlOperations") {
      const allOps = this._allSqlOperations();
      const sel = w.selections.sqlOperations;
      const opCounts = {};
      (DATA.sql?.tableReferences || []).forEach(r => {
        if (r.operation) {
          if (!opCounts[r.operation]) opCounts[r.operation] = new Set();
          opCounts[r.operation].add(r.program);
        }
      });
      allOps.forEach(opName => {
        const lbl = document.createElement("label");
        const cb = document.createElement("input");
        cb.type = "checkbox"; cb.dataset.key = opName;
        cb.checked = sel ? (sel[opName] !== false) : true;
        cb.addEventListener("change", () => this._updateBoxCount(lbl.closest(".fp-box")));
        lbl.appendChild(cb);
        lbl.appendChild(document.createTextNode(opName));
        const cntSpan = document.createElement("span");
        cntSpan.className = "fp-item-count";
        cntSpan.textContent = opCounts[opName]?.size || 0;
        lbl.appendChild(cntSpan);
        listDiv.appendChild(lbl);
      });
    } else if (boxType === "programs") {
      const allProgs = this._allPrograms();
      const sel = w.selections.programs;
      const visible = cascade.visible;
      allProgs.forEach(prog => {
        if (visible && !visible.has(prog)) return;
        const lbl = document.createElement("label");
        const cb = document.createElement("input");
        cb.type = "checkbox"; cb.dataset.key = prog;
        cb.checked = sel ? (sel[prog] !== false) : true;
        cb.addEventListener("change", () => this._updateBoxCount(lbl.closest(".fp-box")));
        lbl.appendChild(cb);
        lbl.appendChild(document.createTextNode(prog));
        listDiv.appendChild(lbl);
      });
    } else if (boxType === "tables") {
      const allTblOps = this._allTableOps();
      const sel = w.selections.tables;
      const visible = cascade.visible;
      allTblOps.forEach(item => {
        if (visible && !visible.has(item.label)) return;
        const lbl = document.createElement("label");
        const cb = document.createElement("input");
        cb.type = "checkbox"; cb.dataset.key = item.label;
        cb.dataset.table = item.table; cb.dataset.op = item.op;
        cb.checked = sel ? (sel[item.label] !== false) : true;
        cb.addEventListener("change", () => this._updateBoxCount(lbl.closest(".fp-box")));
        lbl.appendChild(cb);
        lbl.appendChild(document.createTextNode(item.label));
        listDiv.appendChild(lbl);
      });
    } else if (boxType === "files") {
      const allFiles = this._allFiles();
      const sel = w.selections.files;
      const visible = cascade.visible;
      allFiles.forEach(fname => {
        if (visible && !visible.has(fname)) return;
        const lbl = document.createElement("label");
        const cb = document.createElement("input");
        cb.type = "checkbox"; cb.dataset.key = fname;
        cb.checked = sel ? (sel[fname] !== false) : true;
        cb.addEventListener("change", () => this._updateBoxCount(lbl.closest(".fp-box")));
        lbl.appendChild(cb);
        lbl.appendChild(document.createTextNode(fname));
        listDiv.appendChild(lbl);
      });
    }
  }

  _filterBoxItems(box, searchText) {
    const term = searchText.toLowerCase();
    box.querySelectorAll(".fp-box-list label").forEach(lbl => {
      const text = lbl.textContent.toLowerCase();
      lbl.classList.toggle("hidden", term.length > 0 && !text.includes(term));
    });
    this._updateBoxCount(box);
  }

  _updateBoxCount(box) {
    if (!box) return;
    const countSpan = box.querySelector(".fp-box-count");
    if (!countSpan) return;
    const allCbs = box.querySelectorAll(".fp-box-list input[type='checkbox']");
    const visibleCbs = [...allCbs].filter(cb => !cb.closest("label").classList.contains("hidden"));
    const checked = visibleCbs.filter(cb => cb.checked).length;
    countSpan.textContent = `${checked} / ${visibleCbs.length}`;
  }

  // ── Drag and Drop ─────────────────────────────────────────────────
  _setupDragDrop() {
    let draggedBox = null;
    this.body.querySelectorAll(".fp-box").forEach(box => {
      box.addEventListener("dragstart", e => {
        draggedBox = box;
        e.dataTransfer.effectAllowed = "move";
        setTimeout(() => box.style.opacity = "0.4", 0);
      });
      box.addEventListener("dragend", () => {
        box.style.opacity = "";
        this.body.querySelectorAll(".fp-box").forEach(b => b.classList.remove("drag-over"));
        draggedBox = null;
      });
      box.addEventListener("dragover", e => {
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        if (box !== draggedBox) box.classList.add("drag-over");
      });
      box.addEventListener("dragleave", () => {
        box.classList.remove("drag-over");
      });
      box.addEventListener("drop", e => {
        e.preventDefault();
        box.classList.remove("drag-over");
        if (!draggedBox || draggedBox === box) return;
        this._syncWorkingFromDom();
        const fromType = draggedBox.dataset.boxType;
        const toType = box.dataset.boxType;
        const order = this.working.boxOrder;
        const fromIdx = order.indexOf(fromType);
        const toIdx = order.indexOf(toType);
        if (fromIdx === -1 || toIdx === -1) return;
        order.splice(fromIdx, 1);
        order.splice(toIdx, 0, fromType);
        this._render();
      });
    });
  }

  // ── Build the effective filter set from applied state ─────────────
  getEffectiveFilters() {
    const st = this.applied;
    const elTypes = st.selections.elementTypes || {};
    let programSet = null;
    let tableOpSet = null;
    let fileSet = null;

    for (let i = 0; i < st.boxOrder.length; i++) {
      const boxType = st.boxOrder[i];
      const op = i > 0 ? st.operators[i - 1] : "initial";
      if (op === "none") continue;

      if (boxType === "classifications") {
        const sel = st.selections.classifications;
        if (sel) {
          const catProgs = this._programsByCategories(sel);
          programSet = this._combine(programSet, catProgs, op);
        }
      } else if (boxType === "businessAreas") {
        const sel = st.selections.businessAreas;
        if (sel) {
          const baProgs = this._programsByBusinessAreas(sel);
          programSet = this._combine(programSet, baProgs, op);
        }
      } else if (boxType === "sqlOperations") {
        const sel = st.selections.sqlOperations;
        if (sel) {
          const opProgs = this._programsBySqlOperations(sel);
          programSet = this._combine(programSet, opProgs, op);
        }
      } else if (boxType === "programs") {
        const sel = st.selections.programs;
        if (sel) {
          const selSet = new Set(Object.entries(sel).filter(([, v]) => v).map(([k]) => k));
          if (selSet.size > 0) programSet = this._combine(programSet, selSet, op);
        }
      } else if (boxType === "tables") {
        const sel = st.selections.tables;
        if (sel) {
          const selSet = new Set(Object.entries(sel).filter(([, v]) => v).map(([k]) => k));
          if (selSet.size > 0) tableOpSet = this._combine(tableOpSet, selSet, op);
        }
      } else if (boxType === "files") {
        const sel = st.selections.files;
        if (sel) {
          const selSet = new Set(Object.entries(sel).filter(([, v]) => v).map(([k]) => k));
          if (selSet.size > 0) fileSet = this._combine(fileSet, selSet, op);
        }
      }
    }

    return { elementTypes: elTypes, programSet, tableOpSet, fileSet };
  }

  _tableOpMatches(tableOpSet, tableName, operation) {
    if (!tableOpSet) return true;
    if (tableOpSet.has(`${tableName} (*)`)) return true;
    return tableOpSet.has(`${tableName} (${operation})`);
  }

  _tableNodeAllowed(tableOpSet, tableName) {
    if (!tableOpSet) return true;
    for (const entry of tableOpSet) {
      // Regex: match "TABLENAME (*)" or "TABLENAME (OP)" where TABLENAME matches
      const paren = entry.lastIndexOf(" (");
      if (paren === -1) continue;
      const tbl = entry.substring(0, paren);
      if (tbl === tableName) return true;
    }
    return false;
  }
}

let filterPanel;

// ═══════════════════════════════════════════════════════════════════════
//  LOCALSTORAGE PERSISTENCE
// ═══════════════════════════════════════════════════════════════════════
const STORAGE_KEY = "saGraph.state";
const STATE_VERSION = 7;

function saveTechFilterState() {
  const o = {};
  ["cobol", "powershell", "csharp", "python", "node", "go"].forEach(id => {
    const el = document.getElementById("techShow_" + id);
    if (el) o[id] = !!el.checked;
  });
  return o;
}

function applyTechFilterState(o) {
  if (!o || typeof o !== "object") return;
  Object.keys(o).forEach(id => {
    const el = document.getElementById("techShow_" + id);
    if (el) el.checked = !!o[id];
  });
}

function saveState() {
  const state = {
    version: STATE_VERSION,
    filterPanel: filterPanel.getApplied(),
    renderer: document.getElementById("selRenderer").value,
    layout: document.getElementById("selLayout").value,
    mermaidDir: document.getElementById("selMermaidDir").value,
    threshold: parseInt(document.getElementById("inpThreshold").value) || 200,
    iconProfile: document.getElementById("selIconProfile").value,
    linkStyle: document.getElementById("selLinkStyle")?.value || "avoids",
    groupByArea: document.getElementById("chkGroupByArea")?.checked || false,
    techFilters: saveTechFilterState()
  };
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch (e) { /* ignore */ }
}

function loadState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const state = JSON.parse(raw);
    if (!state.version || state.version < STATE_VERSION) {
      localStorage.removeItem(STORAGE_KEY);
      return null;
    }
    return state;
  } catch (e) { /* ignore */ }
  return null;
}

function applyState(state) {
  if (!state) return;
  if (state.filterPanel) filterPanel.setApplied(state.filterPanel);
  if (state.renderer) document.getElementById("selRenderer").value = state.renderer;
  if (state.layout) document.getElementById("selLayout").value = state.layout;
  if (state.mermaidDir) document.getElementById("selMermaidDir").value = state.mermaidDir;
  if (state.threshold) document.getElementById("inpThreshold").value = state.threshold;
  if (state.iconProfile) document.getElementById("selIconProfile").value = state.iconProfile;
  if (state.linkStyle) { const sel = document.getElementById("selLinkStyle"); if (sel) sel.value = state.linkStyle; }
  const chk = document.getElementById("chkGroupByArea");
  if (chk) chk.checked = !!state.groupByArea;
  applyTechFilterState(state.techFilters);
}

function resetDefaults() { localStorage.removeItem(STORAGE_KEY); location.reload(); }

// ═══════════════════════════════════════════════════════════════════════
//  GRAPH BUILDING
// ═══════════════════════════════════════════════════════════════════════
const NODE_COLORS = {
  program: "#4f8cff", programCall: "#34d399", programDeprecated: "#f87171",
  table: "#a78bfa", inputFile: "#fb923c", outputFile: "#fbbf24", copy: "#64748b"
};

/** Fill / stroke / label text for dependency graph technology nodes */
const techColors = {
  cobol: { fill: "#4A90D9", stroke: "#2E5F8A", text: "#FFFFFF" },
  powershell: { fill: "#012456", stroke: "#5391FE", text: "#FFFFFF" },
  csharp: { fill: "#68217A", stroke: "#9B4DCA", text: "#FFFFFF" },
  python: { fill: "#306998", stroke: "#FFD43B", text: "#FFFFFF" },
  node: { fill: "#339933", stroke: "#66CC33", text: "#FFFFFF" },
  go: { fill: "#00ADD8", stroke: "#007D9C", text: "#FFFFFF" },
  vsam: { fill: "#FF8C00", stroke: "#CC7000", text: "#FFFFFF" },
  sql: { fill: "#CC2927", stroke: "#A41E1E", text: "#FFFFFF" },
  unknown: { fill: "#888888", stroke: "#666666", text: "#FFFFFF" }
};

function isTechToolbarVisible(techId) {
  const id = (techId || "cobol").toLowerCase();
  const el = document.getElementById("techShow_" + id);
  return !el || el.checked;
}

const ICON_PROFILES = {
  standard: {
    program: "RoundedRectangle",
    table: "Database",
    inputFile: "Document",
    outputFile: "Document",
    copy: "Rectangle",
    vsam: "Hexagon"
  },
  custom1: {
    program: "RoundedRectangle",
    table: "Database",
    inputFile: "Download",
    outputFile: "Upload",
    copy: "Rectangle",
    vsam: "Cylinder1"
  }
};

function getIconProfile() {
  const sel = document.getElementById("selIconProfile");
  const id = sel ? sel.value : "standard";
  return ICON_PROFILES[id] || ICON_PROFILES.standard;
}

async function buildGraph() {
  const eff = filterPanel.getEffectiveFilters();
  const elTypes = eff.elementTypes;
  const threshold = parseInt(document.getElementById("inpThreshold").value) || 200;
  const iconProfile = getIconProfile();

  const nodes = [], edges = [];
  const nodeSet = new Set(), programSet = new Set();

  const programSource = DATA.progs?.programs || DATA.master?.programs || [];
  if (elTypes.programs !== false && programSource.length) {
    programSource.forEach(mp => {
      const name = mp.program;
      if (eff.programSet && !eff.programSet.has(name)) return;
      const p = progIndex[name];
      const techId = String((masterIndex[name]?.technology ?? p?.technology) || "cobol").toLowerCase();
      if (!isTechToolbarVisible(techId)) return;
      const tc = techColors[techId] || techColors.unknown;
      let color = tc.fill, textColor = tc.text, nodeType = "program";
      if (p?.isDeprecated) { color = NODE_COLORS.programDeprecated; textColor = "#FFFFFF"; nodeType = "program-deprecated"; }
      else if (p?.source === "call-expansion") { color = NODE_COLORS.programCall; textColor = "#e2e4ea"; nodeType = "program-call"; }
      const ba = businessAreaIndex[name];
      const baColor = ba ? getAreaColor(typeof ba === "string" ? ba : ba[0]) : null;
      const displayText = p?.futureProjectName ? `${name}\n(${p.futureProjectName})` : name;
      nodes.push({
        key: name, text: displayText, type: nodeType, technology: techId,
        color: baColor || color, textColor: baColor ? "#e2e4ea" : textColor,
        figure: iconProfile.program, progCategory: classIndex[name]?.classification || null, businessArea: ba || null
      });
      nodeSet.add(name); programSet.add(name);
    });
  }

  if (elTypes.callLinks !== false && DATA.call?.edges) {
    DATA.call.edges.forEach(e => {
      if (programSet.has(e.caller) && programSet.has(e.callee))
        edges.push({ from: e.caller, to: e.callee, label: "call", type: "call", color: "#8b90a5" });
    });
  }

  if (elTypes.tables !== false && DATA.sql?.tableReferences) {
    const tableOps = {};
    DATA.sql.tableReferences.forEach(r => {
      if (!programSet.has(r.program)) return;
      const tkey = r.schema && r.schema !== "(unqualified)" && r.schema !== "(UNQUALIFIED)" ? r.schema + "." + r.tableName : r.tableName;
      if (eff.tableOpSet && !filterPanel._tableOpMatches(eff.tableOpSet, tkey, r.operation)) return;
      if (!tableOps[tkey]) tableOps[tkey] = { programs: {}, exists: r.existsInDb2 };
      if (!tableOps[tkey].programs[r.program]) tableOps[tkey].programs[r.program] = new Set();
      tableOps[tkey].programs[r.program].add(r.operation);
    });
    Object.entries(tableOps).forEach(([tbl, info]) => {
      if (!nodeSet.has("tbl:" + tbl)) {
        nodes.push({ key: "tbl:" + tbl, text: tbl, type: "table", color: NODE_COLORS.table, figure: iconProfile.table, existsInDb2: info.exists });
        nodeSet.add("tbl:" + tbl);
      }
      Object.entries(info.programs).forEach(([prog, ops]) => {
        edges.push({ from: prog, to: "tbl:" + tbl, label: [...ops].join(","), type: "sql", color: "#a78bfa" });
      });
    });
  }

  if ((elTypes.inputFiles !== false || elTypes.outputFiles !== false) && DATA.fio?.fileReferences) {
    const fileOps = {};
    DATA.fio.fileReferences.forEach(r => {
      if (!programSet.has(r.program)) return;
      const fname = r.physicalName || r.logicalName;
      if (eff.fileSet && !eff.fileSet.has(fname)) return;
      if (!fileOps[fname]) fileOps[fname] = { programs: {}, ops: new Set() };
      if (!fileOps[fname].programs[r.program]) fileOps[fname].programs[r.program] = new Set();
      (r.operations || []).forEach(op => { fileOps[fname].programs[r.program].add(op); fileOps[fname].ops.add(op); });
    });
    Object.entries(fileOps).forEach(([fname, info]) => {
      const hasRead = [...info.ops].some(op => /READ|INPUT|OPEN.*INPUT/i.test(op));
      const hasWrite = [...info.ops].some(op => /WRITE|OUTPUT|OPEN.*OUTPUT/i.test(op));
      if (!(hasRead && elTypes.inputFiles !== false) && !(hasWrite && elTypes.outputFiles !== false)) return;
      const fileType = hasWrite ? "output-file" : "input-file";
      const color = hasWrite ? NODE_COLORS.outputFile : NODE_COLORS.inputFile;
      if (!nodeSet.has("file:" + fname)) {
        nodes.push({ key: "file:" + fname, text: fname, type: fileType, color, figure: fileType === "input-file" ? iconProfile.inputFile : iconProfile.outputFile });
        nodeSet.add("file:" + fname);
      }
      Object.entries(info.programs).forEach(([prog, ops]) => {
        edges.push({ from: prog, to: "file:" + fname, label: [...ops].join(","), type: "fio", color });
      });
    });
  }

  if (elTypes.copyElements && DATA.master?.programs) {
    DATA.master.programs.forEach(mp => {
      if (!programSet.has(mp.program)) return;
      (mp.copyElements || []).forEach(ce => {
        const ceKey = "copy:" + ce.name;
        if (!nodeSet.has(ceKey)) {
          nodes.push({ key: ceKey, text: ce.name, type: "copy", color: NODE_COLORS.copy, figure: iconProfile.copy });
          nodeSet.add(ceKey);
        }
        edges.push({ from: mp.program, to: ceKey, label: ce.type || "", type: "copy", color: "#64748b" });
      });
    });
  }

  if (elTypes.vsamStorage !== false && DATA.master?.programs) {
    const vc = techColors.vsam;
    const vsamSeen = new Set();
    DATA.master.programs.forEach(mp => {
      if (!programSet.has(mp.program)) return;
      const techMp = String(mp.technology || "cobol").toLowerCase();
      if (!isTechToolbarVisible(techMp)) return;
      (mp.vsamFiles || []).forEach(v => {
        const logical = String(v.logicalName || v.ddName || "VSAM").trim();
        const vk = "vsam:" + logical;
        if (!vsamSeen.has(vk)) {
          vsamSeen.add(vk);
          nodes.push({
            key: vk, text: logical + "\n(VSAM)", type: "vsam-storage", color: vc.fill, textColor: vc.text,
            figure: iconProfile.vsam || "Hexagon"
          });
          nodeSet.add(vk);
        }
        edges.push({ from: mp.program, to: vk, label: v.organization || "VSAM", type: "vsam", color: vc.stroke });
      });
    });
  }

  if (elTypes.crossTechLinks !== false && DATA.master?.crossTechLinks?.length) {
    DATA.master.crossTechLinks.forEach(link => {
      const plist = (link.programs || []).map(x => (x && typeof x === "object" ? x.program : null)).filter(Boolean);
      const kind = link.kind || link.table || link.pathKey || "cross-tech";
      for (let i = 0; i < plist.length; i++) {
        for (let j = i + 1; j < plist.length; j++) {
          const a = plist[i], b = plist[j];
          if (programSet.has(a) && programSet.has(b))
            edges.push({ from: a, to: b, label: String(kind).slice(0, 24), type: "crosstech", color: "#9CA3AF" });
        }
      }
    });
  }

  currentNodes = nodes; currentEdges = edges;
  currentGroupData = [];

  const groupByArea = document.getElementById("chkGroupByArea")?.checked || false;
  if (groupByArea && businessAreaSet.size > 0) {
    const progAreaSingle = {};
    nodes.forEach(n => {
      if (n.type === "program" || n.type === "program-call" || n.type === "program-deprecated") {
        const ba = businessAreaIndex[n.key];
        if (typeof ba === "string") progAreaSingle[n.key] = ba;
      }
    });

    const tablePrograms = {};
    edges.forEach(e => {
      if (e.type === "sql") {
        if (!tablePrograms[e.to]) tablePrograms[e.to] = new Set();
        tablePrograms[e.to].add(e.from);
      }
    });

    const tableAreaSingle = {};
    Object.entries(tablePrograms).forEach(([tblKey, progs]) => {
      const areas = new Set();
      progs.forEach(p => {
        const a = progAreaSingle[p];
        if (a) areas.add(a); else areas.add(null);
      });
      if (areas.size === 1 && !areas.has(null)) {
        tableAreaSingle[tblKey] = [...areas][0];
      }
    });

    const activeAreas = new Set([...Object.values(progAreaSingle), ...Object.values(tableAreaSingle)]);
    const areas = DATA.businessAreas?.areas || [];
    currentGroupData = [...activeAreas].map(areaId => {
      const areaObj = areas.find(a => a.id === areaId);
      return {
        key: "group:" + areaId,
        label: areaObj?.name || areaId,
        isGroup: true,
        color: getAreaColor(areaId)
      };
    });

    nodes.forEach(n => {
      const excl = progAreaSingle[n.key] || tableAreaSingle[n.key];
      if (excl) n.group = "group:" + excl;
    });
  }

  const renderer = "gojs";
  activeRenderer = renderer;

  document.getElementById("rendererBadge").textContent =
    renderer.charAt(0).toUpperCase() + renderer.slice(1) + " (" + nodes.length.toLocaleString() + " nodes)";

  saveState();
  setProgress(65, `Rendering ${renderer.toUpperCase()} (${nodes.length} nodes, ${edges.length} edges)…`);
  await yieldToUI(200);
  await renderGraph(renderer);
}

// ═══════════════════════════════════════════════════════════════════════
//  GOJS RENDERER
// ═══════════════════════════════════════════════════════════════════════
function shadeColor(color, percent) {
  const num = parseInt(color.replace("#", ""), 16);
  const r = Math.min(255, Math.max(0, (num >> 16) + percent));
  const g = Math.min(255, Math.max(0, ((num >> 8) & 0x00FF) + percent));
  const b = Math.min(255, Math.max(0, (num & 0x0000FF) + percent));
  return "#" + (0x1000000 + (r << 16) + (g << 8) + b).toString(16).slice(1);
}

function renderGoJS() {
  const graphDiv = document.getElementById("graphContainer");
  const mermaidDiv = document.getElementById("mermaidContainer");
  mermaidDiv.style.display = "none";
  graphDiv.style.display = "block";

  if (gojsDiagram) { gojsDiagram.div = null; gojsDiagram = null; }

  const parent = graphDiv.parentElement;
  graphDiv.style.width = parent.clientWidth + "px";
  graphDiv.style.height = parent.clientHeight + "px";

  let layoutChoice = document.getElementById("selLayout").value;
  const nodeCount = currentNodes.length;
  const edgeCount = currentEdges.length;
  const isLarge = nodeCount > 300 || edgeCount > 2000;

  const forceIter = nodeCount > 500 ? 20 : nodeCount > 200 ? 50 : 200;
  const springLen = nodeCount > 500 ? 40 : 60;
  const layoutConfig = {
    layered:   { class: go.LayeredDigraphLayout, opts: { direction: 0, layerSpacing: 60, columnSpacing: 25 } },
    layeredTD: { class: go.LayeredDigraphLayout, opts: { direction: 90, layerSpacing: 50, columnSpacing: 25 } },
    force:     { class: go.ForceDirectedLayout,  opts: { maxIterations: forceIter, defaultSpringLength: springLen, epsilonDistance: 1 } },
    tree:      { class: go.TreeLayout,           opts: { angle: 0, layerSpacing: 80, nodeSpacing: 25 } },
    circular:  { class: go.CircularLayout,       opts: { spacing: 40 } },
    grid:      { class: go.GridLayout,            opts: { wrappingWidth: Math.max(800, Math.ceil(Math.sqrt(nodeCount)) * 180), cellSize: new go.Size(1, 1), spacing: new go.Size(10, 10) } },
  };
  if (isLarge && (layoutChoice === "force" || layoutChoice === "circular"))
    layoutChoice = "grid";
  const lc = layoutConfig[layoutChoice] || layoutConfig.grid;

  console.log(`[graph] renderGoJS: ${nodeCount} nodes, ${edgeCount} edges, layout=${layoutChoice}`);

  const autoScale = nodeCount <= 300 ? go.AutoScale.Uniform : go.AutoScale.None;

  const linkStyleChoice = document.getElementById("selLinkStyle")?.value || "avoids";
  const LINK_STYLES = {
    straight:    { routing: go.Routing.Normal,      curve: undefined,       corner: 0 },
    orthogonal:  { routing: go.Routing.Orthogonal,  curve: undefined,       corner: 8 },
    avoids:      { routing: go.Routing.AvoidsNodes,  curve: undefined,       corner: 8 },
    bezier:      { routing: go.Routing.Normal,       curve: go.Curve.Bezier, corner: 0 },
    jumpOver:    { routing: go.Routing.AvoidsNodes,  curve: go.Curve.JumpOver, corner: 8 },
    jumpGap:     { routing: go.Routing.AvoidsNodes,  curve: go.Curve.JumpGap,  corner: 8 },
  };
  const ls = LINK_STYLES[linkStyleChoice] || LINK_STYLES.avoids;
  if (isLarge && ls.routing === go.Routing.AvoidsNodes) ls.routing = go.Routing.Normal;

  const diagram = new go.Diagram(graphDiv, {
    layout: new lc.class(lc.opts),
    initialAutoScale: autoScale,
    initialScale: isLarge ? 0.3 : 1,
    padding: 40, scrollMode: go.ScrollMode.Infinite,
  });
  diagram.toolManager.mouseWheelBehavior = go.WheelMode.Zoom;
  diagram.animationManager.isEnabled = false;
  diagram.undoManager.isEnabled = false;

  const ctxMenuAdornment = new go.HTMLInfo();
  ctxMenuAdornment.show = (obj, diagram, tool) => {
    const node = obj.part;
    if (!node || !node.data) return;
    const e = diagram.lastInput;
    const pt = e.viewPoint;
    const rect = diagram.div.getBoundingClientRect();
    showContextMenu(rect.left + pt.x, rect.top + pt.y, node.data);
  };
  ctxMenuAdornment.hide = () => hideContextMenu();

  diagram.nodeTemplate = new go.Node("Auto", {
    click: (_e, node) => showNodeDetail(node.data),
    contextMenu: ctxMenuAdornment
  }).add(
    new go.Shape({ strokeWidth: 2 }).bind("figure", "figure").bind("fill", "color").bind("stroke", "color", c => shadeColor(c, -30)),
    new go.TextBlock({ margin: 8, font: "12px Segoe UI", maxSize: new go.Size(160, NaN), wrap: go.Wrap.Fit })
      .bind("text", "text")
      .bind("stroke", "textColor", c => c || "#e2e4ea")
  );

  diagram.groupTemplate = new go.Group("Auto", {
    layout: new go.LayeredDigraphLayout({ direction: 90, layerSpacing: 30, columnSpacing: 20 }),
    isSubGraphExpanded: true,
    computesBoundsAfterDrag: true
  }).add(
    new go.Shape("RoundedRectangle", {
      fill: "rgba(30,32,48,0.6)",
      strokeWidth: 2
    }).bind("stroke", "color"),
    new go.Panel("Vertical").add(
      new go.TextBlock({
        font: "bold 13px Segoe UI",
        stroke: "#c0c4e0",
        margin: new go.Margin(8, 10, 4, 10)
      }).bind("text", "label"),
      new go.Placeholder({ padding: 12 })
    )
  );

  const fcGroupCtx = new go.HTMLInfo();
  fcGroupCtx.show = (obj, diag, tool) => {
    const grp = obj.part;
    if (!grp || !grp.data) return;
    const e = diag.lastInput;
    const pt = e.viewPoint;
    const rect = diag.div.getBoundingClientRect();
    showContextMenu(rect.left + pt.x, rect.top + pt.y, grp.data);
  };
  fcGroupCtx.hide = () => hideContextMenu();

  diagram.groupTemplateMap.add("flowchartGroup", new go.Group("Auto", {
    layout: new go.LayeredDigraphLayout({ direction: 90, layerSpacing: 25, columnSpacing: 15 }),
    isSubGraphExpanded: true,
    computesBoundsAfterDrag: true,
    contextMenu: fcGroupCtx
  }).add(
    new go.Shape("RoundedRectangle", {
      fill: "rgba(40,45,70,0.7)",
      strokeWidth: 2,
      strokeDashArray: [6, 3]
    }).bind("stroke", "color"),
    new go.Panel("Vertical").add(
      new go.TextBlock({
        font: "bold 14px Segoe UI",
        stroke: "#e0c870",
        margin: new go.Margin(8, 12, 4, 12)
      }).bind("text", "label"),
      new go.Placeholder({ padding: 14 })
    )
  ));

  const linkLabel = isLarge ? [] : [
    new go.Panel("Auto").add(
      new go.Shape({ fill: "#242838", stroke: null }),
      new go.TextBlock({ font: "9px Segoe UI", stroke: "#8b90a5", margin: 2, maxSize: new go.Size(100, NaN) }).bind("text", "label")
    )
  ];
  const linkOpts = { routing: ls.routing, corner: ls.corner };
  if (ls.curve) linkOpts.curve = ls.curve;
  diagram.linkTemplate = new go.Link(linkOpts).add(
    new go.Shape({ strokeWidth: 1.2 }).bind("stroke", "color"),
    new go.Shape({ toArrow: "Standard", scale: 1 }).bind("fill", "color").bind("stroke", "color"),
    ...linkLabel
  );

  const maxEdgesForRender = isLarge ? 500 : edgeCount;
  const edgesToRender = edgeCount <= maxEdgesForRender ? currentEdges : currentEdges.slice(0, maxEdgesForRender);
  if (edgeCount > maxEdgesForRender) {
    console.log(`[graph] Limiting edges: showing ${maxEdgesForRender} of ${edgeCount} (use filters to reduce node count)`);
  }

  const allNodeData = currentGroupData.length > 0
    ? [...currentGroupData, ...currentNodes]
    : currentNodes;

  diagram.model = new go.GraphLinksModel({
    nodeKeyProperty: "key", linkFromKeyProperty: "from", linkToKeyProperty: "to",
    nodeDataArray: allNodeData, linkDataArray: edgesToRender
  });

  gojsDiagram = diagram;
  diagram.addDiagramListener("ViewportBoundsChanged", () => updateZoomPct());
  updateZoomPct();

  window.addEventListener("resize", () => {
    if (!gojsDiagram) return;
    const p = graphDiv.parentElement;
    graphDiv.style.width = p.clientWidth + "px";
    graphDiv.style.height = p.clientHeight + "px";
    gojsDiagram.requestUpdate();
  });

  if (expandedPrograms.size > 0) {
    const toReExpand = [...expandedPrograms.keys()];
    expandedPrograms.clear();
    toReExpand.forEach(prog => {
      if (gojsDiagram.model.findNodeDataForKey(prog)) {
        expandProgramToFlowchart(prog);
      }
    });
  }

  restoreSavedNodePositions();
}

function restoreSavedNodePositions() {
  const positions = DATA.master?.nodePositions;
  if (!positions || !gojsDiagram) return;
  let restored = 0;
  gojsDiagram.startTransaction("restore saved positions");
  gojsDiagram.nodes.each(node => {
    const pos = positions[node.key];
    if (pos) {
      node.location = new go.Point(pos.x, pos.y);
      restored++;
    }
  });
  gojsDiagram.commitTransaction("restore saved positions");
  if (restored > 0) {
    console.log(`[graph] Restored ${restored} saved node positions from dependency_master.json`);
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  MERMAID RENDERER
// ═══════════════════════════════════════════════════════════════════════
async function renderMermaidGraph() {
  const graphDiv = document.getElementById("graphContainer");
  const mermaidDiv = document.getElementById("mermaidContainer");
  graphDiv.style.display = "none";
  mermaidDiv.style.display = "block";

  const dir = document.getElementById("selMermaidDir").value;
  const lines = ['%%{ init: { "flowchart": { "curve": "basis" } } }%%', "flowchart " + dir];

  const shapeMap = { "program": "[[", "program-call": "[[", "program-deprecated": "[[", "table": "[(", "input-file": "[/", "output-file": "[/", "copy": "[", "vsam-storage": "{{" };
  const shapeCloseMap = { "program": "]]", "program-call": "]]", "program-deprecated": "]]", "table": ")]", "input-file": "/]", "output-file": "/]", "copy": "]", "vsam-storage": "}}" };

  currentNodes.forEach(n => {
    const id = mmdId(n.key);
    lines.push("  " + id + (shapeMap[n.type] || "[") + n.text + (shapeCloseMap[n.type] || "]"));
  });
  currentEdges.forEach(e => {
    const from = mmdId(e.from), to = mmdId(e.to);
    lines.push(e.label ? `  ${from} --"${e.label}"--> ${to}` : `  ${from} --> ${to}`);
  });

  lines.push("  classDef prog stroke:#4f8cff,fill:#1a2744,color:#e2e4ea");
  lines.push("  classDef progCall stroke:#34d399,fill:#1a2d27,color:#e2e4ea");
  lines.push("  classDef progDepr stroke:#f87171,fill:#2d1a1a,color:#e2e4ea");
  lines.push("  classDef tbl stroke:#a78bfa,fill:#2a1f44,color:#e2e4ea");
  lines.push("  classDef fileIn stroke:#fb923c,fill:#2d1f0f,color:#e2e4ea");
  lines.push("  classDef fileOut stroke:#fbbf24,fill:#2d270f,color:#e2e4ea");
  lines.push("  classDef cp stroke:#64748b,fill:#1e2330,color:#e2e4ea");
  lines.push("  classDef vsam stroke:#CC7000,fill:#3d2600,color:#ffe0b0");

  const classAssign = { prog: [], progCall: [], progDepr: [], tbl: [], fileIn: [], fileOut: [], cp: [], vsam: [] };
  currentNodes.forEach(n => {
    const id = mmdId(n.key);
    if (n.type === "program") classAssign.prog.push(id);
    else if (n.type === "program-call") classAssign.progCall.push(id);
    else if (n.type === "program-deprecated") classAssign.progDepr.push(id);
    else if (n.type === "table") classAssign.tbl.push(id);
    else if (n.type === "input-file") classAssign.fileIn.push(id);
    else if (n.type === "output-file") classAssign.fileOut.push(id);
    else if (n.type === "copy") classAssign.cp.push(id);
    else if (n.type === "vsam-storage") classAssign.vsam.push(id);
  });
  if (classAssign.prog.length) lines.push("  class " + classAssign.prog.join(",") + " prog");
  if (classAssign.progCall.length) lines.push("  class " + classAssign.progCall.join(",") + " progCall");
  if (classAssign.progDepr.length) lines.push("  class " + classAssign.progDepr.join(",") + " progDepr");
  if (classAssign.tbl.length) lines.push("  class " + classAssign.tbl.join(",") + " tbl");
  if (classAssign.fileIn.length) lines.push("  class " + classAssign.fileIn.join(",") + " fileIn");
  if (classAssign.fileOut.length) lines.push("  class " + classAssign.fileOut.join(",") + " fileOut");
  if (classAssign.cp.length) lines.push("  class " + classAssign.cp.join(",") + " cp");
  if (classAssign.vsam.length) lines.push("  class " + classAssign.vsam.join(",") + " vsam");

  const code = lines.join("\n");
  const renderId = "mmd_" + Date.now();
  mermaid.render(renderId, code).then(({ svg }) => {
    mermaidDiv.innerHTML = svg;
    mermaidDiv.querySelectorAll(".node").forEach(node => {
      node.style.cursor = "pointer";
      node.addEventListener("click", () => {
        const nodeId = node.id.replace(/^flowchart-/, "").replace(/-\d+$/, "");
        const found = currentNodes.find(n => mmdId(n.key) === nodeId);
        if (found) showNodeDetail(found);
      });
      node.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        e.stopPropagation();
        const nodeId = node.id.replace(/^flowchart-/, "").replace(/-\d+$/, "");
        const found = currentNodes.find(n => mmdId(n.key) === nodeId);
        if (found) showContextMenu(e.clientX, e.clientY, found);
      });
    });
    setTimeout(() => initMermaidPanZoom(), 100);
  }).catch(err => {
    mermaidDiv.innerHTML = `<pre style="color:var(--red);font-size:12px;padding:20px">${esc(err.message)}</pre>`;
  });
}

function initMermaidPanZoom() {
  if (typeof svgPanZoom === "undefined") return;
  const container = document.getElementById("mermaidContainer");
  const svgEl = container?.querySelector("svg");
  if (!svgEl) return;
  if (mermaidPanZoom) { try { mermaidPanZoom.destroy(); } catch (e) { /* ignore */ } mermaidPanZoom = null; }

  svgEl.removeAttribute("height");
  svgEl.style.width = "100%";
  svgEl.style.height = "100%";

  mermaidPanZoom = svgPanZoom(svgEl, {
    zoomEnabled: true, panEnabled: true, controlIconsEnabled: false,
    fit: true, center: true, minZoom: 0.05, maxZoom: 30,
    zoomScaleSensitivity: 0.3,
    onZoom: () => updateZoomPct()
  });
  updateZoomPct();
}

// ═══════════════════════════════════════════════════════════════════════
//  ZOOM
// ═══════════════════════════════════════════════════════════════════════
function updateZoomPct() {
  let pct = 100;
  if (activeRenderer === "gojs" && gojsDiagram) pct = Math.round(gojsDiagram.scale * 100);
  else if (activeRenderer === "mermaid" && mermaidPanZoom) pct = Math.round(mermaidPanZoom.getZoom() * 100);
  const el = document.getElementById("zoomPct");
  if (el) el.textContent = pct + "%";
}

function handleZoomIn() {
  if (activeRenderer === "gojs" && gojsDiagram) gojsDiagram.commandHandler.increaseZoom();
  else if (activeRenderer === "mermaid" && mermaidPanZoom) mermaidPanZoom.zoomIn();
  updateZoomPct();
}
function handleZoomOut() {
  if (activeRenderer === "gojs" && gojsDiagram) gojsDiagram.commandHandler.decreaseZoom();
  else if (activeRenderer === "mermaid" && mermaidPanZoom) mermaidPanZoom.zoomOut();
  updateZoomPct();
}
function handleZoomFit() {
  if (activeRenderer === "gojs" && gojsDiagram) gojsDiagram.zoomToFit();
  else if (activeRenderer === "mermaid" && mermaidPanZoom) { mermaidPanZoom.fit(); mermaidPanZoom.center(); }
  updateZoomPct();
}

// ═══════════════════════════════════════════════════════════════════════
//  SVG EXPORT
// ═══════════════════════════════════════════════════════════════════════
function cloneJson(obj) {
  if (obj === undefined) return undefined;
  try {
    return JSON.parse(JSON.stringify(obj));
  } catch {
    return null;
  }
}

function tableKeyFromSqlRef(r) {
  return r.schema && r.schema !== "(unqualified)" && r.schema !== "(UNQUALIFIED)"
    ? `${r.schema}.${r.tableName}`
    : r.tableName;
}

function effectiveFiltersSerializable(eff) {
  return {
    elementTypes: eff.elementTypes ? { ...eff.elementTypes } : {},
    programSet: eff.programSet ? [...eff.programSet].sort() : null,
    tableOpSet: eff.tableOpSet ? [...eff.tableOpSet].sort() : null,
    fileSet: eff.fileSet ? [...eff.fileSet].sort() : null
  };
}

function db2RowMatchesGraphTables(row, tableKeys) {
  if (!row || !row.tableName) return false;
  const tn = row.tableName;
  if (tableKeys.has(tn)) return true;
  for (const k of tableKeys) {
    if (k === tn || k.endsWith(`.${tn}`)) return true;
  }
  return false;
}

function sliceSourceVerificationForGraph(verify, progKeys, copyKeys) {
  if (!verify) return null;
  const byProg = arr => (Array.isArray(arr) ? arr.filter(x => x && typeof x.program === "string" && progKeys.has(x.program)) : []);
  const byProgStr = arr => (Array.isArray(arr) ? arr.filter(s => typeof s === "string" && progKeys.has(s)) : []);
  return {
    title: verify.title,
    generated: verify.generated,
    sourceRoot: verify.sourceRoot,
    summary: verify.summary,
    programsCblFound: byProg(verify.programsCblFound),
    programsUncertainFound: byProg(verify.programsUncertainFound),
    programsUvFuzzyMatch: byProg(verify.programsUvFuzzyMatch),
    programsOtherType: byProg(verify.programsOtherType),
    programsNoiseFiltered: byProg(verify.programsNoiseFiltered),
    programsTrulyMissing: byProgStr(verify.programsTrulyMissing),
    copyMissing: Array.isArray(verify.copyMissing) ? verify.copyMissing.filter(c => copyKeys.has(c)) : [],
    onDiskNotInMaster: verify.onDiskNotInMaster
  };
}

function buildFilteredExportPayload() {
  const progKeys = new Set(currentNodes.filter(n => n.type && n.type.startsWith("program")).map(n => n.key));
  const tableKeys = new Set(currentNodes.filter(n => n.type === "table").map(n => n.key.replace(/^tbl:/, "")));
  const fileKeys = new Set(
    currentNodes.filter(n => n.type === "input-file" || n.type === "output-file").map(n => n.key.replace(/^file:/, ""))
  );
  const copyKeys = new Set(currentNodes.filter(n => n.type === "copy").map(n => n.key.replace(/^copy:/, "")));

  const programs = {};
  for (const name of progKeys) {
    const m = masterIndex[name];
    const p = progIndex[name];
    const callersAll = calledByIndex[name] || [];
    programs[name] = {
      graphNode: cloneJson(currentNodes.find(n => n.key === name)) || null,
      fromAllTotalPrograms: cloneJson(p),
      fromDependencyMaster: cloneJson(m),
      classification: cloneJson(classIndex[name]) || null,
      sourceVerification: cloneJson(verifyIndex[name]) || null,
      calledByInGraph: callersAll.filter(c => progKeys.has(c)),
      calledByAll: [...callersAll],
      callTargetsInGraph: (m?.callTargets || []).filter(t => progKeys.has(t)),
      callTargetsAll: m?.callTargets ? [...m.callTargets] : []
    };
  }

  const tables = {};
  for (const tk of tableKeys) {
    const sqlRefs = (DATA.sql?.tableReferences || []).filter(r => {
      if (!progKeys.has(r.program)) return false;
      return tableKeyFromSqlRef(r) === tk;
    }).map(cloneJson);
    const db2Rows = (DATA.db2TableValidation?.tables || []).filter(row => db2RowMatchesGraphTables(row, new Set([tk])));
    tables[tk] = {
      graphNode: cloneJson(currentNodes.find(n => n.key === `tbl:${tk}`)) || null,
      sqlTableReferences: sqlRefs,
      db2ValidationRows: db2Rows.map(cloneJson)
    };
  }

  const files = {};
  for (const fk of fileKeys) {
    const refs = (DATA.fio?.fileReferences || []).filter(r => {
      const fname = r.physicalName || r.logicalName;
      return progKeys.has(r.program) && fname === fk;
    }).map(cloneJson);
    files[fk] = {
      graphNode: cloneJson(currentNodes.find(n => n.key === `file:${fk}`)) || null,
      fileReferences: refs
    };
  }

  const copybooks = {};
  for (const ck of copyKeys) {
    copybooks[ck] = {
      graphNode: cloneJson(currentNodes.find(n => n.key === `copy:${ck}`)) || null,
      copyElement: cloneJson(copyIndex[ck]) || null,
      usedByInGraph: (copyIndex[ck]?.usedBy || []).filter(p => progKeys.has(p))
    };
  }

  const callEdgesBetweenGraphPrograms = (DATA.call?.edges || []).filter(
    e => progKeys.has(e.caller) && progKeys.has(e.callee)
  ).map(cloneJson);

  const sqlTableReferencesAll = (DATA.sql?.tableReferences || []).filter(r => progKeys.has(r.program)).map(cloneJson);
  const fileReferencesAll = (DATA.fio?.fileReferences || []).filter(r => progKeys.has(r.program)).map(cloneJson);

  const allTotalProgramsSlice = (DATA.progs?.programs || []).filter(p => progKeys.has(p.program)).map(cloneJson);

  let seedAllDocument = null;
  if (DATA.seedAll) {
    seedAllDocument = cloneJson(DATA.seedAll);
    if (seedAllDocument?.entries) {
      seedAllDocument.entries = seedAllDocument.entries.filter(e => e && e.program && progKeys.has(e.program));
    }
  }

  const excl = DATA.appliedExclusions;
  const exclusionsForGraph = excl
    ? {
      title: excl.title,
      generated: excl.generated,
      description: excl.description,
      exclusionConfig: excl.exclusionConfig,
      candidateProgramSetInGraph: (excl.candidateProgramSet || []).filter(p => progKeys.has(p)),
      candidates: (excl.candidates || []).filter(c => c && progKeys.has(c.program)).map(cloneJson)
    }
    : null;

  const std = DATA.standardCobolFiltered;
  const stdCobolForGraph = std
    ? {
      title: std.title,
      generated: std.generated,
      totalChecked: std.totalChecked,
      totalRemoved: std.totalRemoved,
      totalRetained: std.totalRetained,
      removed: (std.removed || []).filter(x => x && progKeys.has(x.program)).map(cloneJson),
      retained: (std.retained || []).filter(x => x && progKeys.has(x.program)).map(cloneJson)
    }
    : null;

  const db2Full = DATA.db2TableValidation;
  const db2ForGraph = db2Full
    ? {
      title: db2Full.title,
      generated: db2Full.generated,
      dsn: db2Full.dsn,
      totalTablesInReport: db2Full.totalTables,
      validated: db2Full.validated,
      notFound: db2Full.notFound,
      tablesMatchingGraph: (db2Full.tables || []).filter(row => db2RowMatchesGraphTables(row, tableKeys)).map(cloneJson)
    }
    : null;

  return {
    exportVersion: 1,
    exportedAt: new Date().toISOString(),
    analysisAlias: alias || null,
    ui: {
      activeRenderer: activeRenderer || null,
      rendererSelect: document.getElementById("selRenderer")?.value || null,
      layout: document.getElementById("selLayout")?.value || null,
      linkStyle: document.getElementById("selLinkStyle")?.value || "avoids",
      mermaidDir: document.getElementById("selMermaidDir")?.value || null,
      threshold: parseInt(document.getElementById("inpThreshold")?.value, 10) || 200
    },
    filters: {
      applied: cloneJson(filterPanel.getApplied()),
      effective: effectiveFiltersSerializable(filterPanel.getEffectiveFilters())
    },
    graph: {
      nodeCount: currentNodes.length,
      edgeCount: currentEdges.length,
      nodes: cloneJson(currentNodes),
      edges: cloneJson(currentEdges)
    },
    index: {
      programKeys: [...progKeys].sort(),
      tableKeys: [...tableKeys].sort(),
      fileKeys: [...fileKeys].sort(),
      copyKeys: [...copyKeys].sort()
    },
    entities: { programs, tables, files, copybooks },
    crossReferences: {
      allCallGraphEdgesBetweenGraphPrograms: callEdgesBetweenGraphPrograms,
      allSqlTableReferencesForGraphPrograms: sqlTableReferencesAll,
      allFileReferencesForGraphPrograms: fileReferencesAll,
      fileMetadata: {
        allSqlTablesJson: DATA.sql
          ? { title: DATA.sql.title, generated: DATA.sql.generated, totalReferences: DATA.sql.totalReferences, uniqueTables: DATA.sql.uniqueTables, db2Validated: DATA.sql.db2Validated }
          : null,
        allFileIoJson: DATA.fio
          ? {
            title: DATA.fio.title,
            generated: DATA.fio.generated,
            totalFileReferences: DATA.fio.totalFileReferences,
            uniqueFiles: DATA.fio.uniqueFiles,
            defaultPath: DATA.fio.defaultPath
          }
          : null,
        allCallGraphJson: DATA.call
          ? { title: DATA.call.title, generated: DATA.call.generated, totalEdges: DATA.call.edges?.length }
          : null,
        allCopyElementsJson: DATA.copy
          ? { title: DATA.copy.title, generated: DATA.copy.generated, totalCopyElements: DATA.copy.totalCopyElements }
          : null,
        dependencyMasterJson: DATA.master ? { title: DATA.master.title, generated: DATA.master.generated } : null,
        allTotalProgramsJson: DATA.progs ? { title: DATA.progs.title, generated: DATA.progs.generated, totalPrograms: DATA.progs.totalPrograms } : null
      }
    },
    programListSlice: { allTotalPrograms: allTotalProgramsSlice },
    seedAllJson: seedAllDocument,
    reports: {
      sourceVerificationFull: cloneJson(DATA.verify),
      sourceVerificationGraphSlice: sliceSourceVerificationForGraph(DATA.verify, progKeys, copyKeys),
      db2TableValidationFull: cloneJson(DATA.db2TableValidation),
      db2TableValidationGraphSlice: db2ForGraph,
      appliedExclusionsFull: cloneJson(DATA.appliedExclusions),
      appliedExclusionsGraphSlice: exclusionsForGraph,
      standardCobolFilteredFull: cloneJson(DATA.standardCobolFiltered),
      standardCobolFilteredGraphSlice: stdCobolForGraph
    },
    copyCatalog: {
      copyElementsForGraphCopyNodes: [...copyKeys].map(k => cloneJson(copyIndex[k])).filter(Boolean)
    }
  };
}

function buildSimplifiedPayload() {
  const progKeys = new Set(currentNodes.filter(n => n.type && n.type.startsWith("program")).map(n => n.key));
  const tableKeys = new Set(currentNodes.filter(n => n.type === "table").map(n => n.key.replace(/^tbl:/, "")));
  const fileKeys = new Set(
    currentNodes.filter(n => n.type === "input-file" || n.type === "output-file").map(n => n.key.replace(/^file:/, ""))
  );
  const copyKeys = new Set(currentNodes.filter(n => n.type === "copy").map(n => n.key.replace(/^copy:/, "")));

  const programs = [...progKeys].sort().map(name => {
    const p = progIndex[name];
    const m = masterIndex[name];
    return {
      program: name,
      type: p?.type || null,
      area: p?.area || null,
      menuChoice: p?.menuChoice || null,
      description: p?.description || null,
      descriptionNorwegian: p?.descriptionNorwegian || null,
      classification: p?.classification || null,
      source: p?.source || null,
      sourceType: p?.sourceType || m?.sourceType || null,
      cobdokSystem: p?.cobdokSystem || null,
      cobdokDelsystem: p?.cobdokDelsystem || null,
      isDeprecated: p?.isDeprecated || false,
      callTargets: (m?.callTargets || []).filter(t => progKeys.has(t)),
      sqlTables: [...new Set((m?.sqlOperations || []).map(s => s.tableName).filter(Boolean))].filter(t => tableKeys.has(t)),
      copyElements: (copyByProgram[name] || []).map(c => c.name).filter(c => copyKeys.has(c)),
      fileIo: (DATA.fio?.fileReferences || []).filter(r => r.program === name).map(r => r.physicalName || r.logicalName).filter(f => fileKeys.has(f))
    };
  });

  const tables = [...tableKeys].sort().map(tk => {
    const refs = (DATA.sql?.tableReferences || []).filter(r => progKeys.has(r.program) && tableKeyFromSqlRef(r) === tk);
    const ops = [...new Set(refs.map(r => r.operation))].sort();
    const usedBy = [...new Set(refs.map(r => r.program))].sort();
    return { table: tk, operations: ops, usedByPrograms: usedBy };
  });

  const files = [...fileKeys].sort().map(fk => {
    const refs = (DATA.fio?.fileReferences || []).filter(r => progKeys.has(r.program) && (r.physicalName || r.logicalName) === fk);
    const usedBy = [...new Set(refs.map(r => r.program))].sort();
    const direction = refs.some(r => r.openMode?.match(/output|extend/i)) ? "output" : "input";
    return { file: fk, direction, usedByPrograms: usedBy };
  });

  const copybooks = [...copyKeys].sort().map(ck => {
    const ce = copyIndex[ck];
    const usedBy = (ce?.usedBy || []).filter(p => progKeys.has(p)).sort();
    return { name: ck, usedByPrograms: usedBy };
  });

  return {
    exportVersion: 2,
    exportType: "simplified",
    exportedAt: new Date().toISOString(),
    analysisAlias: alias || null,
    summary: {
      programs: programs.length,
      tables: tables.length,
      files: files.length,
      copybooks: copybooks.length,
      callEdges: currentEdges.filter(e => e.type === "call").length
    },
    programs,
    tables,
    files,
    copybooks,
    callEdges: currentEdges.filter(e => e.type === "call").map(e => ({ from: e.from, to: e.to }))
  };
}

function downloadJsonBlob(payload, filename) {
  const json = JSON.stringify(payload, null, 2);
  const blob = new Blob([json], { type: "application/json;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function exportFilteredJson() {
  const btn = document.getElementById("btnExportJson");
  const origText = btn.textContent;
  btn.textContent = "Exporting…";
  btn.disabled = true;

  setTimeout(() => {
    try {
      const ts = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
      const safeAlias = (alias || "graph").replace(/[^\w\-]+/g, "_");

      const full = buildFilteredExportPayload();
      full.exportVersion = 2;
      full.exportType = "full";
      downloadJsonBlob(full, `${safeAlias}_graph_full_${ts}.json`);

      const simple = buildSimplifiedPayload();
      downloadJsonBlob(simple, `${safeAlias}_graph_simple_${ts}.json`);
    } catch (e) {
      console.error("[graph] JSON export failed:", e);
      alert("JSON export failed: " + e.message);
    } finally {
      btn.textContent = origText;
      btn.disabled = false;
    }
  }, 50);
}

function exportSvg() {
  const btn = document.getElementById("btnExportSvg");
  const origText = btn.textContent;
  btn.textContent = "Exporting…";
  btn.disabled = true;

  setTimeout(() => {
    try {
      let svgContent = null;

      if (activeRenderer === "gojs" && gojsDiagram) {
        const svgEl = gojsDiagram.makeSvg({ scale: 1, background: "#1a1d2e" });
        svgContent = new XMLSerializer().serializeToString(svgEl);
      } else if (activeRenderer === "mermaid") {
        const container = document.getElementById("mermaidContainer");
        const svgEl = container?.querySelector("svg");
        if (svgEl) {
          const clone = svgEl.cloneNode(true);
          clone.setAttribute("xmlns", "http://www.w3.org/2000/svg");
          if (!clone.getAttribute("width")) clone.setAttribute("width", svgEl.getBoundingClientRect().width);
          if (!clone.getAttribute("height")) clone.setAttribute("height", svgEl.getBoundingClientRect().height);
          svgContent = new XMLSerializer().serializeToString(clone);
        }
      }

      if (!svgContent) {
        alert("No graph rendered to export.");
        return;
      }

      const blob = new Blob([svgContent], { type: "image/svg+xml;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `${alias || "graph"}_${activeRenderer}_${new Date().toISOString().slice(0,10)}.svg`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (e) {
      console.error("[graph] SVG export failed:", e);
      alert("SVG export failed: " + e.message);
    } finally {
      btn.textContent = origText;
      btn.disabled = false;
    }
  }, 50);
}

async function renderGraph(renderer) {
  if (mermaidPanZoom) { try { mermaidPanZoom.destroy(); } catch (e) { /* ignore */ } mermaidPanZoom = null; }
  if (renderer === "gojs") {
    if (typeof go === "undefined") {
      setProgress(0, "GoJS library not loaded. Try Mermaid renderer.");
      return;
    }
    setProgress(75, "Creating GoJS diagram…");
    await yieldToUI(150);
    renderGoJS();
    setProgress(95, "Finalizing layout…");
    await yieldToUI(200);
    setProgress(100, "Complete!");
    await yieldToUI(400);
    document.getElementById("loadingMsg").style.display = "none";
  }
  else {
    setProgress(75, "Rendering Mermaid diagram…");
    await yieldToUI(150);
    await renderMermaidGraph();
    setProgress(100, "Complete!");
    await yieldToUI(400);
    document.getElementById("loadingMsg").style.display = "none";
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  DETAIL PANEL
// ═══════════════════════════════════════════════════════════════════════
function prop(label, value) { return `<div class="dk">${esc(label)}</div><div class="dv">${value}</div>`; }
function tagHtml(text, cls) { return `<span class="tag tag-${cls}">${esc(text)}</span>`; }

function showNodeDetail(nodeData) {
  const panel = document.getElementById("detailPanel");
  const content = document.getElementById("detailContent");
  panel.classList.remove("collapsed");

  const key = nodeData.key, type = nodeData.type;
  let h = "";
  if (type.startsWith("program")) h = buildProgramDetail(key);
  else if (type === "vsam-storage") h = buildVsamDetail(key.replace(/^vsam:/, ""));
  else if (type === "table") h = buildTableDetail(key.replace("tbl:", ""));
  else if (type === "input-file" || type === "output-file") h = buildFileDetail(key.replace("file:", ""));
  else if (type === "copy") h = buildCopyDetail(key.replace("copy:", ""));
  content.innerHTML = h;

  if (gojsDiagram && activeRenderer === "gojs") {
    const node = gojsDiagram.findNodeForKey(key);
    if (node) { gojsDiagram.select(node); gojsDiagram.centerRect(node.actualBounds); }
  }
}

function buildProgramDetail(name) {
  const m = masterIndex[name], p = progIndex[name], cl = classIndex[name], v = verifyIndex[name];
  let h = `<h2>${esc(name)}</h2>`;
  h += '<div class="section"><h3>Properties</h3><div class="prop-grid">';
  if (m?.technology) h += prop("Technology", tagHtml(m.technology, "program"));
  if (p) {
    h += prop("Source", tagHtml(p.source === "original" ? "Original" : p.source === "call-expansion" ? "Call Exp." : p.source, p.source === "original" ? "program" : "call"));
    h += prop("Data", p.sourceType || "—");
    if (p.area) h += prop("Area", p.area);
    const ba = businessAreaIndex[name];
    if (ba) {
      const areaObj = DATA.businessAreas?.areas?.find(a => a.id === (typeof ba === "string" ? ba : ba[0]));
      h += prop("Business Area", `<span class="ba-tag" style="background:${getAreaColor(typeof ba === "string" ? ba : ba[0])};color:#fff">${esc(areaObj?.name || ba)}</span>`);
    }
    if (p.type) h += prop("Type", p.type);
    if (p.description) h += prop("Description", p.description);
    if (p.cobdokSystem) h += prop("COBDOK Sys", p.cobdokSystem);
    if (p.cobdokDelsystem) h += prop("Subsystem", p.cobdokDelsystem);
    if (p.isDeprecated) h += prop("Status", tagHtml("DEPRECATED", "deprecated"));
  }
  if (m?.futureProjectName) h += prop("Future C# Name", tagHtml(m.futureProjectName, "future"));
  if (cl) {
    h += prop("Classification", tagHtml(cl.classification, "table"));
    if (cl.confidence) h += prop("Confidence", cl.confidence);
    if (cl.evidence) h += prop("Evidence", `<span style="font-size:10px">${esc(cl.evidence)}</span>`);
  }
  if (m?.sourcePath) h += prop("Source File", `<span style="font-size:10px;word-break:break-all">${esc(m.sourcePath)}</span>`);
  h += "</div>";
  if (m?.sourcePath) {
    const normalized = m.sourcePath.replace(/\\/g, "/");
    h += `<a class="open-btn" href="vscode://file/${encodeURI(normalized)}" target="_blank">Open in Editor</a>`;
  }
  h += "</div>";

  if (m?.callTargets?.length) {
    h += `<div class="section"><h3>Call Targets (${m.callTargets.length})</h3><ul class="item-list">`;
    m.callTargets.forEach(c => { h += `<li><a data-nav="${esc(c)}">${esc(c)}</a></li>`; });
    h += "</ul></div>";
  }
  const callers = calledByIndex[name] || [];
  if (callers.length) {
    h += `<div class="section"><h3>Called By (${callers.length})</h3><ul class="item-list">`;
    callers.forEach(c => { h += `<li><a data-nav="${esc(c)}">${esc(c)}</a></li>`; });
    h += "</ul></div>";
  }
  if (m?.sqlOperations?.length) {
    const tableOps = {};
    const tableFutureNames = {};
    m.sqlOperations.forEach(s => {
      const tkey = s.schema && s.schema !== "(unqualified)" ? s.schema + "." + s.tableName : s.tableName;
      if (!tableOps[tkey]) tableOps[tkey] = new Set();
      tableOps[tkey].add(s.operation);
      if (s.futureTableName && !tableFutureNames[tkey]) tableFutureNames[tkey] = s.futureTableName;
    });
    h += `<div class="section"><h3>SQL Tables (${Object.keys(tableOps).length})</h3><ul class="item-list">`;
    Object.entries(tableOps).forEach(([tbl, ops]) => {
      const fn = tableFutureNames[tbl];
      const futureLabel = fn ? ` ${tagHtml(fn, "future")}` : '';
      h += `<li><a data-nav="tbl:${esc(tbl)}">${esc(tbl)}</a>${futureLabel} <span style="color:var(--text2);font-size:10px">${[...ops].join(", ")}</span></li>`;
    });
    h += "</ul></div>";
  }
  if (m?.fileIO?.length) {
    h += `<div class="section"><h3>File I/O (${m.fileIO.length})</h3><ul class="item-list">`;
    m.fileIO.forEach(f => {
      const fname = f.physicalName || f.logicalName;
      h += `<li><a data-nav="file:${esc(fname)}">${esc(fname)}</a> <span style="color:var(--text2);font-size:10px">${(f.operations || []).join(", ")}</span></li>`;
    });
    h += "</ul></div>";
  }
  if (m?.copyElements?.length) {
    h += `<div class="section"><h3>Copy Elements (${m.copyElements.length})</h3><ul class="item-list">`;
    m.copyElements.forEach(ce => { h += `<li><a data-nav="copy:${esc(ce.name)}">${esc(ce.name)}</a></li>`; });
    h += "</ul></div>";
  }
  if (m?.vsamFiles?.length) {
    h += `<div class="section"><h3>VSAM (${m.vsamFiles.length})</h3><ul class="item-list">`;
    m.vsamFiles.forEach(v => {
      const logical = v.logicalName || v.ddName || "—";
      h += `<li><a data-nav="vsam:${esc(logical)}">${esc(logical)}</a> <span style="color:var(--text2);font-size:10px">${esc(v.organization || "")}</span></li>`;
    });
    h += "</ul></div>";
  }
  if (p?.source === "original") {
    h += `<div class="section"><p><a class="open-btn" href="present.html?alias=${encodeURIComponent(alias)}" target="_blank" rel="noopener">View Business Docs (presentation)</a></p></div>`;
  }
  return h;
}

function buildVsamDetail(logicalName) {
  const progs = (DATA.master?.programs || []).filter(mp =>
    (mp.vsamFiles || []).some(v => (v.logicalName || v.ddName) === logicalName));
  let h = `<h2>${esc(logicalName)}</h2><div class="section"><h3>VSAM</h3><div class="prop-grid">`;
  h += prop("Logical name", esc(logicalName));
  h += "</div></div>";
  if (progs.length) {
    h += `<div class="section"><h3>Programs (${progs.length})</h3><ul class="item-list">`;
    progs.forEach(mp => { h += `<li><a data-nav="${esc(mp.program)}">${esc(mp.program)}</a></li>`; });
    h += "</ul></div>";
  }
  return h;
}

function buildTableDetail(tableName) {
  const bareTable = tableName.includes('.') ? tableName.split('.').pop() : tableName;
  const tn = DATA.master?.tableNaming?.[bareTable];
  let h = `<h2>${esc(tableName)}</h2>`;
  h += '<div class="section"><h3>Table Info</h3><div class="prop-grid">';
  h += prop("Type", tagHtml("DB2 Table", "table"));
  if (tn?.futureName) h += prop("Future C# Name", tagHtml(tn.futureName, "future"));
  if (tn?.namespace) h += prop("Namespace", tn.namespace);
  if (tn?.tableRemarks) h += prop("Comment", tn.tableRemarks);
  const refs = (DATA.sql?.tableReferences || []).filter(r => {
    const tkey = r.schema && r.schema !== "(unqualified)" && r.schema !== "(UNQUALIFIED)" ? r.schema + "." + r.tableName : r.tableName;
    return tkey === tableName;
  });
  if (refs.length && refs[0].existsInDb2 !== undefined) h += prop("Exists in DB2", refs[0].existsInDb2 ? "Yes" : "No");
  h += "</div></div>";

  if (tn?.columns?.length) {
    h += `<div class="section"><h3>Columns (${tn.columns.length})</h3>`;
    h += '<table class="col-grid"><thead><tr><th>Original</th><th>Future Name</th><th>Type</th><th>Description</th></tr></thead><tbody>';
    tn.columns.forEach(c => {
      const fkBadge = c.foreignKey
        ? ` <span class="tag tag-fk${c.foreignKey.confidence === 'high' ? ' tag-fk-high' : ''}"
             title="${esc(c.foreignKey.evidence || '')}">FK → ${esc(c.foreignKey.targetTable)}</span>`
        : '';
      h += `<tr><td>${esc(c.name)}</td><td>${esc(c.futureName || '—')}${fkBadge}</td><td>${esc(c.dataType || '—')}</td><td>${esc(c.description || '—')}</td></tr>`;
    });
    h += '</tbody></table></div>';
  }

  const progOps = {};
  refs.forEach(r => { if (!progOps[r.program]) progOps[r.program] = new Set(); progOps[r.program].add(r.operation); });
  if (Object.keys(progOps).length) {
    h += `<div class="section"><h3>Used By (${Object.keys(progOps).length} programs)</h3><ul class="item-list">`;
    Object.entries(progOps).forEach(([prog, ops]) => {
      h += `<li><a data-nav="${esc(prog)}">${esc(prog)}</a> <span style="color:var(--text2);font-size:10px">${[...ops].join(", ")}</span></li>`;
    });
    h += "</ul></div>";
  }
  return h;
}

function buildFileDetail(fileName) {
  let h = `<h2>${esc(fileName)}</h2>`;
  h += '<div class="section"><h3>File Info</h3><div class="prop-grid">';
  const refs = (DATA.fio?.fileReferences || []).filter(r => (r.physicalName || r.logicalName) === fileName);
  if (refs.length) {
    h += prop("Logical", refs[0].logicalName);
    h += prop("Physical", refs[0].physicalName);
    if (refs[0].fullPath) h += prop("Full Path", `<span style="font-size:10px;word-break:break-all">${esc(refs[0].fullPath)}</span>`);
    if (refs[0].assignType) h += prop("Assign Type", refs[0].assignType);
  }
  h += "</div></div>";
  const progOps = {};
  refs.forEach(r => { if (!progOps[r.program]) progOps[r.program] = new Set(); (r.operations || []).forEach(op => progOps[r.program].add(op)); });
  if (Object.keys(progOps).length) {
    h += `<div class="section"><h3>Used By (${Object.keys(progOps).length} programs)</h3><ul class="item-list">`;
    Object.entries(progOps).forEach(([prog, ops]) => {
      h += `<li><a data-nav="${esc(prog)}">${esc(prog)}</a> <span style="color:var(--text2);font-size:10px">${[...ops].join(", ")}</span></li>`;
    });
    h += "</ul></div>";
  }
  return h;
}

function buildCopyDetail(copyName) {
  const ce = copyIndex[copyName];
  let h = `<h2>${esc(copyName)}</h2>`;
  h += '<div class="section"><h3>Copy Element</h3><div class="prop-grid">';
  if (ce) {
    h += prop("Type", ce.type || "—");
    h += prop("Local Path", ce.localPath ? `<span style="font-size:10px;word-break:break-all">${esc(ce.localPath)}</span>` : "—");
  }
  h += "</div>";
  if (ce?.localPath) {
    const normalized = ce.localPath.replace(/\\/g, "/");
    h += `<a class="open-btn" href="vscode://file/${encodeURI(normalized)}" target="_blank">Open in Editor</a>`;
  }
  h += "</div>";
  if (ce?.usedBy?.length) {
    h += `<div class="section"><h3>Used By (${ce.usedBy.length} programs)</h3><ul class="item-list">`;
    ce.usedBy.forEach(p => { h += `<li><a data-nav="${esc(p)}">${esc(p)}</a></li>`; });
    h += "</ul></div>";
  }
  return h;
}

function navigateToNode(key) {
  const nodeData = currentNodes.find(n => n.key === key);
  if (nodeData) showNodeDetail(nodeData);
  if (gojsDiagram && activeRenderer === "gojs") {
    const node = gojsDiagram.findNodeForKey(key);
    if (node) { gojsDiagram.select(node); gojsDiagram.centerRect(node.actualBounds); }
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  CONTEXT MENU + DRILL-DOWN
// ═══════════════════════════════════════════════════════════════════════

const drillStack = [];

function pushDrillState(label) {
  drillStack.push({
    label,
    filterState: JSON.parse(JSON.stringify(filterPanel.getApplied()))
  });
  renderBreadcrumb();
}

function popDrillState() {
  if (drillStack.length === 0) return;
  const prev = drillStack.pop();
  filterPanel.setApplied(prev.filterState);
  renderBreadcrumb();
  scheduleRebuild();
}

function resetDrillState() {
  if (drillStack.length === 0) return;
  const first = drillStack[0];
  drillStack.length = 0;
  filterPanel.setApplied(first.filterState);
  renderBreadcrumb();
  scheduleRebuild();
}

function renderBreadcrumb() {
  const bar = document.getElementById("drillBreadcrumb");
  const crumbs = document.getElementById("drillCrumbs");
  if (drillStack.length === 0) {
    bar.style.display = "none";
    return;
  }
  bar.style.display = "flex";
  let html = `<span class="drill-crumb">${esc(alias || "Root")}</span>`;
  drillStack.forEach(d => {
    html += `<span class="drill-sep">&rsaquo;</span><span class="drill-crumb">${esc(d.label)}</span>`;
  });
  crumbs.innerHTML = html;
}

// ── Quick Filter: programmatically set FilterPanel and rebuild ──────

async function applyQuickFilter(programNames, options = {}) {
  pushDrillState(options.label || "Drill");

  const st = JSON.parse(JSON.stringify(filterPanel.getApplied()));

  const elTypes = st.selections.elementTypes || {};
  elTypes.programs = true;
  elTypes.callLinks = true;
  if (options.showTables !== undefined) elTypes.tables = options.showTables;
  if (options.showInputFiles !== undefined) elTypes.inputFiles = options.showInputFiles;
  if (options.showOutputFiles !== undefined) elTypes.outputFiles = options.showOutputFiles;
  if (options.showCopy !== undefined) elTypes.copyElements = options.showCopy;
  st.selections.elementTypes = elTypes;

  if (options.mode === "union" && st.selections.programs) {
    const existing = st.selections.programs;
    programNames.forEach(p => { existing[p] = true; });
  } else {
    const progSel = {};
    programNames.forEach(p => { progSel[p] = true; });
    st.selections.programs = progSel;
  }

  st.selections.classifications = null;
  st.selections.businessAreas = null;
  st.selections.sqlOperations = null;

  if (options.tableOpSet) st.selections.tables = options.tableOpSet;
  if (options.fileSet) st.selections.files = options.fileSet;

  filterPanel.setApplied(st);

  document.getElementById("loadingMsg").style.display = "flex";
  setProgress(50, "Applying drill-down…");
  await yieldToUI();
  await buildGraph();
  saveState();
}

// ── Graph traversal helpers ─────────────────────────────────────────

function collectCallChain(startName, direction) {
  const visited = new Set([startName]);
  const queue = [startName];
  const edges = DATA.call?.edges || [];
  while (queue.length > 0) {
    const current = queue.shift();
    edges.forEach(e => {
      const next = direction === "downstream" ? (e.caller === current ? e.callee : null)
                                               : (e.callee === current ? e.caller : null);
      if (next && !visited.has(next)) {
        visited.add(next);
        queue.push(next);
      }
    });
  }
  return visited;
}

function getDirectNeighbors(name) {
  const neighbors = new Set([name]);
  const m = masterIndex[name];
  (m?.callTargets || []).forEach(t => neighbors.add(t));
  (calledByIndex[name] || []).forEach(c => neighbors.add(c));
  return neighbors;
}

function getProgramsForTable(tableName, opFilter) {
  const progs = new Set();
  (DATA.sql?.tableReferences || []).forEach(r => {
    const tkey = r.schema && r.schema !== "(unqualified)" && r.schema !== "(UNQUALIFIED)" ? r.schema + "." + r.tableName : r.tableName;
    if (tkey !== tableName) return;
    if (opFilter && r.operation !== opFilter) return;
    progs.add(r.program);
  });
  return progs;
}

function getTableOpsForProgram(name) {
  const m = masterIndex[name];
  if (!m?.sqlOperations?.length) return [];
  return m.sqlOperations.map(s => {
    const tkey = s.schema && s.schema !== "(unqualified)" ? s.schema + "." + s.tableName : s.tableName;
    return { table: tkey, operation: s.operation };
  });
}

function getProgramsForFile(fileName) {
  const progs = new Set();
  (DATA.fio?.fileReferences || []).forEach(r => {
    if ((r.physicalName || r.logicalName) === fileName) progs.add(r.program);
  });
  return progs;
}

function getProgramsForCopy(copyName) {
  const ce = copyIndex[copyName];
  return new Set(ce?.usedBy || []);
}

function getTableRefsForTable(tableName) {
  const refs = (DATA.sql?.tableReferences || []).filter(r => {
    const tkey = r.schema && r.schema !== "(unqualified)" && r.schema !== "(UNQUALIFIED)" ? r.schema + "." + r.tableName : r.tableName;
    return tkey === tableName;
  });
  const hasSelect = refs.some(r => r.operation === "SELECT");
  const hasWrite = refs.some(r => /INSERT|UPDATE|DELETE/.test(r.operation));
  return { refs, hasSelect, hasWrite };
}

// ── Drill-down action functions ─────────────────────────────────────

async function drillDownToProgram(name) {
  const neighbors = getDirectNeighbors(name);
  await applyQuickFilter([...neighbors], {
    label: `Drill: ${name}`,
    showTables: true, showInputFiles: true, showOutputFiles: true, showCopy: true
  });
}

async function showCallChainDown(name) {
  const chain = collectCallChain(name, "downstream");
  await applyQuickFilter([...chain], {
    label: `Calls from ${name}`,
    showTables: false, showInputFiles: false, showOutputFiles: false, showCopy: false
  });
}

async function showCallChainUp(name) {
  const chain = collectCallChain(name, "upstream");
  await applyQuickFilter([...chain], {
    label: `Callers of ${name}`,
    showTables: false, showInputFiles: false, showOutputFiles: false, showCopy: false
  });
}

async function showProgramTables(name) {
  await applyQuickFilter([name], {
    label: `Tables: ${name}`,
    showTables: true, showInputFiles: false, showOutputFiles: false, showCopy: false
  });
}

async function showProgramFiles(name) {
  await applyQuickFilter([name], {
    label: `Files: ${name}`,
    showTables: false, showInputFiles: true, showOutputFiles: true, showCopy: false
  });
}

async function showProgramCopies(name) {
  await applyQuickFilter([name], {
    label: `Copies: ${name}`,
    showTables: false, showInputFiles: false, showOutputFiles: false, showCopy: true
  });
}

async function expandNeighbors(name) {
  const neighbors = getDirectNeighbors(name);
  await applyQuickFilter([...neighbors], {
    label: `Expand: ${name}`,
    mode: "union",
    showTables: true, showInputFiles: true, showOutputFiles: true, showCopy: true
  });
}

async function hideNode(key) {
  pushDrillState(`Hide: ${key.replace(/^(tbl:|file:|copy:)/, "")}`);

  const st = JSON.parse(JSON.stringify(filterPanel.getApplied()));
  if (key.startsWith("tbl:") || key.startsWith("file:") || key.startsWith("copy:")) {
    // non-program: rebuild without it (handled by removing from graph post-build)
  } else {
    if (!st.selections.programs) {
      const allProgs = (DATA.progs?.programs || []).map(p => p.program);
      st.selections.programs = {};
      allProgs.forEach(p => { st.selections.programs[p] = true; });
    }
    st.selections.programs[key] = false;
  }
  filterPanel.setApplied(st);

  document.getElementById("loadingMsg").style.display = "flex";
  setProgress(50, "Hiding node…");
  await yieldToUI();
  await buildGraph();
  saveState();
}

async function showProgramsUsingTable(tableName, opFilter) {
  const progs = getProgramsForTable(tableName, opFilter);
  if (progs.size === 0) return;
  await applyQuickFilter([...progs], {
    label: opFilter ? `${tableName} (${opFilter})` : `Users of ${tableName}`,
    showTables: true, showInputFiles: false, showOutputFiles: false, showCopy: false
  });
}

async function showProgramsUsingFile(fileName) {
  const progs = getProgramsForFile(fileName);
  if (progs.size === 0) return;
  await applyQuickFilter([...progs], {
    label: `Users of ${fileName}`,
    showTables: false, showInputFiles: true, showOutputFiles: true, showCopy: false
  });
}

async function showProgramsUsingCopy(copyName) {
  const progs = getProgramsForCopy(copyName);
  if (progs.size === 0) return;
  await applyQuickFilter([...progs], {
    label: `Users of ${copyName}`,
    showTables: false, showInputFiles: false, showOutputFiles: false, showCopy: true
  });
}

// ── Context menu builder ────────────────────────────────────────────

function buildContextMenuItems(nodeData) {
  const items = [];
  const key = nodeData.key, type = nodeData.type;

  if (nodeData._isExpandedFlowchart) {
    const progName = key;
    items.push({ type: "header", text: progName + " (expanded)" });
    items.push({ icon: "\u{1F4E5}", label: "Collapse Flowchart", action: () => collapseProgramFlowchart(progName) });
    const m = masterIndex[progName];
    const adFile = progName + ".CBL.json";
    items.push({ icon: "\u{1F4D6}", label: "Open AutoDoc", action: () => window.open(`doc.html?file=${encodeURIComponent(adFile)}`, "_blank") });
    items.push({ type: "sep" });

  } else if (type && type.startsWith("program")) {
    const name = key;
    const m = masterIndex[name];
    const hasCallTargets = m?.callTargets?.length > 0;
    const hasCallers = (calledByIndex[name] || []).length > 0;
    const hasTables = m?.sqlOperations?.length > 0;
    const hasFiles = m?.fileIO?.length > 0;
    const hasCopies = m?.copyElements?.length > 0;

    items.push({ type: "header", text: name });
    items.push({ icon: "\u{1F50D}", label: "Drill Down", action: () => drillDownToProgram(name) });
    items.push({ icon: "\u{1F30D}", label: "Isolate + Expand", action: () => isolateAndExpand(name) });
    items.push({ icon: "\u2B07", label: "Call Chain (downstream)", action: () => showCallChainDown(name), disabled: !hasCallTargets });
    items.push({ icon: "\u2B06", label: "Call Chain (upstream)", action: () => showCallChainUp(name), disabled: !hasCallers });
    items.push({ type: "sep" });
    items.push({ icon: "\u{1F4CA}", label: "Show Flowchart", action: () => showProgramFlowchart(name), disabled: m?.autoDocExists === false });
    items.push({ icon: "\u{1F4E6}", label: "Expand to Flowchart", action: () => expandProgramToFlowchart(name), disabled: m?.autoDocExists === false || expandedPrograms.has(name) });
    items.push({ icon: "\u{1F5C4}", label: "Show Only Tables", action: () => showProgramTables(name), disabled: !hasTables });
    items.push({ icon: "\u{1F4C4}", label: "Show Only Files", action: () => showProgramFiles(name), disabled: !hasFiles });
    items.push({ icon: "\u{1F4CB}", label: "Show Only Copies", action: () => showProgramCopies(name), disabled: !hasCopies });
    items.push({ type: "sep" });
    items.push({ icon: "\u{1F517}", label: "Expand Neighbors", action: () => expandNeighbors(name) });
    if (isolationMode) {
      items.push({ icon: "\u2795", label: "Expand from Here", action: () => expandInIsolation(name) });
    }
    items.push({ icon: "\u{1F6AB}", label: "Hide This Program", action: () => hideNode(name) });
    items.push({ icon: "\u{1F3F7}", label: "Reassign Business Area", action: () => showReassignBusinessAreaDialog(name) });

    items.push({ type: "sep" });
    const adFile = name + ".CBL.json";
    items.push({ icon: "\u{1F4D6}", label: "Open AutoDoc", action: () => window.open(`doc.html?file=${encodeURIComponent(adFile)}`, "_blank"), disabled: m?.autoDocExists === false });
    if (type === "program") {
      items.push({ icon: "\u{1F4F9}", label: "Business Docs (slides)", action: () => window.open(`present.html?alias=${encodeURIComponent(alias)}`, "_blank", "noopener") });
    }
    if (m?.sourcePath) {
      const normalized = m.sourcePath.replace(/\\/g, "/");
      items.push({ icon: "\u{1F4DD}", label: "Open in Editor", action: () => { window.open(`vscode://file/${encodeURI(normalized)}`, "_blank"); } });
    }

  } else if (type === "vsam-storage") {
    const logical = key.replace(/^vsam:/, "");
    items.push({ type: "header", text: logical + " (VSAM)" });
    items.push({ icon: "\u2139", label: "View Details", action: () => showNodeDetail(nodeData) });
    items.push({ type: "sep" });
    items.push({ icon: "\u{1F6AB}", label: "Hide This VSAM Node", action: () => hideNode(key) });

  } else if (type === "table") {
    const tableName = key.replace("tbl:", "");
    const info = getTableRefsForTable(tableName);

    items.push({ type: "header", text: tableName });
    items.push({ icon: "\u{1F50D}", label: "Show All Programs", action: () => showProgramsUsingTable(tableName) });
    items.push({ icon: "R", label: "Show SELECT Only", action: () => showProgramsUsingTable(tableName, "SELECT"), disabled: !info.hasSelect });
    items.push({ icon: "W", label: "Show INSERT/UPDATE/DELETE", action: () => showProgramsUsingTable(tableName, null), disabled: !info.hasWrite });
    items.push({ type: "sep" });
    items.push({ icon: "\u{1F6AB}", label: "Hide This Table", action: () => hideNode(key) });

  } else if (type === "input-file" || type === "output-file") {
    const fileName = key.replace("file:", "");

    items.push({ type: "header", text: fileName });
    items.push({ icon: "\u{1F50D}", label: "Show All Programs", action: () => showProgramsUsingFile(fileName) });
    items.push({ type: "sep" });
    items.push({ icon: "\u{1F6AB}", label: "Hide This File", action: () => hideNode(key) });

  } else if (type === "copy") {
    const copyName = key.replace("copy:", "");

    items.push({ type: "header", text: copyName });
    items.push({ icon: "\u{1F50D}", label: "Show All Programs", action: () => showProgramsUsingCopy(copyName) });
    items.push({ type: "sep" });
    items.push({ icon: "\u{1F6AB}", label: "Hide This Copy", action: () => hideNode(key) });
  }

  items.push({ type: "sep" });
  if (activeRenderer === "gojs" && gojsDiagram) {
    items.push({ icon: "\u{1F3AF}", label: "Center on This Node", action: () => {
      const node = gojsDiagram.findNodeForKey(key);
      if (node) { gojsDiagram.select(node); gojsDiagram.centerRect(node.actualBounds); }
    }});
  }
  items.push({ icon: "\u2139", label: "View Details", action: () => showNodeDetail(nodeData) });

  return items;
}

// ── Show / hide context menu ────────────────────────────────────────

function showContextMenu(x, y, nodeData) {
  const menu = document.getElementById("nodeContextMenu");
  const items = buildContextMenuItems(nodeData);

  let html = "";
  items.forEach(item => {
    if (item.type === "sep") { html += '<div class="ctx-sep"></div>'; return; }
    if (item.type === "header") { html += `<div class="ctx-header">${esc(item.text)}</div>`; return; }
    const cls = item.disabled ? "ctx-item disabled" : "ctx-item";
    html += `<div class="${cls}" data-idx="${items.indexOf(item)}">`;
    html += `<span class="ctx-icon">${item.icon || ""}</span>`;
    html += `<span>${esc(item.label)}</span>`;
    html += `</div>`;
  });
  menu.innerHTML = html;

  menu.style.display = "block";
  menu.style.left = x + "px";
  menu.style.top = y + "px";

  requestAnimationFrame(() => {
    const rect = menu.getBoundingClientRect();
    if (rect.right > window.innerWidth) menu.style.left = Math.max(0, x - rect.width) + "px";
    if (rect.bottom > window.innerHeight) menu.style.top = Math.max(0, y - rect.height) + "px";
  });

  menu.querySelectorAll(".ctx-item:not(.disabled)").forEach(el => {
    el.addEventListener("click", () => {
      const idx = parseInt(el.dataset.idx);
      hideContextMenu();
      if (items[idx]?.action) items[idx].action();
    }, { once: true });
  });
}

function hideContextMenu() {
  const menu = document.getElementById("nodeContextMenu");
  menu.style.display = "none";
  menu.innerHTML = "";
}

document.addEventListener("click", (e) => {
  if (!e.target.closest("#nodeContextMenu")) hideContextMenu();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") hideContextMenu();
});

// ═══════════════════════════════════════════════════════════════════════
//  ISOLATE + EXPAND MODE
// ═══════════════════════════════════════════════════════════════════════

async function isolateAndExpand(name) {
  const neighbors = getDirectNeighbors(name);
  isolationMode = true;
  isolationSet = new Set(neighbors);
  updateIsolationBadge();
  await applyQuickFilter([...neighbors], {
    label: `Isolate: ${name}`,
    showTables: true, showInputFiles: true, showOutputFiles: true, showCopy: true
  });
}

async function expandInIsolation(name) {
  const neighbors = getDirectNeighbors(name);
  neighbors.forEach(n => isolationSet.add(n));
  updateIsolationBadge();
  await applyQuickFilter([...isolationSet], {
    label: `+${name}`,
    mode: "union",
    showTables: true, showInputFiles: true, showOutputFiles: true, showCopy: true
  });
}

function exitIsolation() {
  isolationMode = false;
  isolationSet.clear();
  updateIsolationBadge();
  resetDrillState();
}

function updateIsolationBadge() {
  let badge = document.getElementById("isolationBadge");
  if (isolationMode) {
    if (!badge) {
      badge = document.createElement("div");
      badge.id = "isolationBadge";
      badge.className = "isolation-badge";
      badge.addEventListener("click", exitIsolation);
      document.body.appendChild(badge);
    }
    badge.textContent = `Isolated: ${isolationSet.size} nodes (click to exit)`;
    badge.style.display = "block";
  } else if (badge) {
    badge.style.display = "none";
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  EXPAND PROGRAM TO FLOWCHART GROUP
// ═══════════════════════════════════════════════════════════════════════

function fcKey(prog, internalId) { return `fc:${prog}:${internalId}`; }

function matchInternalTableToMainGraph(internalId) {
  // sql_dbm_tilganalyse -> DBM.TILGANALYSE
  if (!internalId.startsWith("sql_")) return null;
  const raw = internalId.slice(4).replace(/_/g, ".").toUpperCase();
  if (gojsDiagram.model.findNodeDataForKey("tbl:" + raw)) return "tbl:" + raw;
  const shortName = raw.includes(".") ? raw.split(".").pop() : raw;
  if (gojsDiagram.model.findNodeDataForKey("tbl:" + shortName)) return "tbl:" + shortName;
  return null;
}

async function expandProgramToFlowchart(programName) {
  if (!gojsDiagram || expandedPrograms.has(programName)) return;
  const renderer = window.autodocRenderer;
  if (!renderer?.parseMermaidToGraph) { console.warn("autodoc-renderer.js not loaded"); return; }

  const fileName = await resolveAutoDocFile(programName);
  if (!fileName) { console.warn(`No AutoDoc file for ${programName}`); return; }

  let doc;
  try {
    doc = await fetch(autodocUrl(fileName)).then(r => r.json());
  } catch (e) { console.warn(`Failed to fetch AutoDoc for ${programName}:`, e); return; }

  const flowMmd = doc?.diagrams?.flowMmd;
  if (!flowMmd) { console.warn(`No flowMmd in AutoDoc for ${programName}`); return; }

  const ugm = renderer.parseMermaidToGraph(flowMmd);
  if (!ugm || !ugm.nodes?.length) { console.warn(`Could not parse flowchart for ${programName}`); return; }

  const origNode = gojsDiagram.model.findNodeDataForKey(programName);
  if (!origNode) return;
  const origColor = origNode.color || "#e06060";

  expandedPrograms.set(programName, { ugm, origNode: { ...origNode } });

  gojsDiagram.model.commit(m => {
    m.set(origNode, "isGroup", true);
    m.set(origNode, "category", "flowchartGroup");
    m.set(origNode, "label", programName);
    m.set(origNode, "_isExpandedFlowchart", true);

    const SHAPE_COLORS = {
      rounded: { fill: "#3a4060", stroke: "#6a7090" },
      circle: { fill: "#4a3060", stroke: "#8a60a0" },
      rectangle: { fill: "#304050", stroke: "#5080a0" },
      cylinder: { fill: "#2a4a3a", stroke: "#50a070" },
      hexagon: { fill: "#504030", stroke: "#a08050" },
      stadium: { fill: "#3a4060", stroke: "#6a7090" },
      subroutine: { fill: "#403050", stroke: "#7060a0" },
      diamond: { fill: "#504030", stroke: "#a08050" },
    };

    ugm.nodes.forEach(n => {
      const iKey = fcKey(programName, n.id);
      const isTable = n.id.startsWith("sql_");
      const sc = SHAPE_COLORS[n.shape] || SHAPE_COLORS.rounded;
      m.addNodeData({
        key: iKey,
        text: n.label || n.id,
        group: programName,
        figure: n.goFigure || "RoundedRectangle",
        color: isTable ? "#50a070" : sc.stroke,
        fill: isTable ? "#2a4a3a" : sc.fill,
        _fcInternal: true,
        _fcProg: programName
      });
    });

    ugm.edges.forEach(e => {
      m.addLinkData({
        from: fcKey(programName, e.from),
        to: fcKey(programName, e.to),
        label: e.label || "",
        color: "#6a7090",
        _fcInternal: true,
        _fcProg: programName
      });
    });

    // Cross-link internal SQL table nodes to main graph table nodes
    ugm.nodes.forEach(n => {
      if (!n.id.startsWith("sql_")) return;
      const mainKey = matchInternalTableToMainGraph(n.id);
      if (!mainKey) return;
      m.addLinkData({
        from: fcKey(programName, n.id),
        to: mainKey,
        label: "",
        color: "#50a070",
        _fcCrossLink: true,
        _fcProg: programName
      });
    });
  }, "expand flowchart");
}

function collapseProgramFlowchart(programName) {
  if (!gojsDiagram || !expandedPrograms.has(programName)) return;
  const saved = expandedPrograms.get(programName);

  gojsDiagram.model.commit(m => {
    const toRemoveNodes = [];
    const toRemoveLinks = [];

    m.nodeDataArray.forEach(nd => {
      if (nd._fcProg === programName && nd._fcInternal) toRemoveNodes.push(nd);
    });
    m.linkDataArray.forEach(ld => {
      if (ld._fcProg === programName) toRemoveLinks.push(ld);
    });

    toRemoveLinks.forEach(ld => m.removeLinkData(ld));
    toRemoveNodes.forEach(nd => m.removeNodeData(nd));

    const groupNode = m.findNodeDataForKey(programName);
    if (groupNode) {
      m.set(groupNode, "isGroup", false);
      m.set(groupNode, "category", "");
      m.set(groupNode, "_isExpandedFlowchart", undefined);
      m.set(groupNode, "figure", saved.origNode.figure || "RoundedRectangle");
      m.set(groupNode, "text", saved.origNode.text);
      m.set(groupNode, "color", saved.origNode.color);
      m.set(groupNode, "label", undefined);
    }
  }, "collapse flowchart");

  expandedPrograms.delete(programName);
}

// ═══════════════════════════════════════════════════════════════════════
//  AUTODOC FLOWCHART
// ═══════════════════════════════════════════════════════════════════════

const autoDocExtensions = [".cbl.json", ".bat.json", ".ps1.json", ".rex.json"];
let flowchartDiagram = null;

// Background cache warmup (optional, populates autoDocCache for faster repeat access)
// Kept as opt-in — the "Show Flowchart" menu item works without it via on-demand fetch.
function warmAutoDocCache() {
  const programs = Object.keys(masterIndex);
  let idx = 0;
  function checkNext() {
    if (idx >= programs.length) return;
    const batch = programs.slice(idx, idx + 5);
    idx += 5;
    batch.forEach(prog => {
      if (autoDocCache.has(prog)) return;
      (async () => {
        for (const ext of autoDocExtensions) {
          const candidate = prog + ext;
          try {
            const r = await fetch(autodocUrl(candidate), { method: "HEAD" });
            if (r.ok) { autoDocCache.set(prog, candidate); return; }
          } catch { /* ignore */ }
        }
      })();
    });
    setTimeout(checkNext, 100);
  }
  checkNext();
}

async function resolveAutoDocFile(programName) {
  const cached = autoDocCache.get(programName);
  if (cached) return cached;
  for (const ext of autoDocExtensions) {
    const candidate = programName + ext;
    try {
      const r = await fetch(autodocUrl(candidate), { method: "HEAD" });
      if (r.ok) { autoDocCache.set(programName, candidate); return candidate; }
    } catch { /* ignore */ }
  }
  return null;
}

async function showProgramFlowchart(programName) {
  const overlay = document.getElementById("flowchartOverlay");
  const container = document.getElementById("flowchartContainer");
  const title = document.getElementById("flowchartTitle");
  overlay.style.display = "flex";
  title.textContent = `Flowchart: ${programName}`;
  container.innerHTML = '<div style="padding:40px;text-align:center;color:var(--text2)">Loading...</div>';

  const fileName = await resolveAutoDocFile(programName);
  if (!fileName) {
    container.innerHTML = '<div style="padding:40px;text-align:center;color:var(--text2)">No AutoDocJson documentation found for ' + esc(programName) + '.<br><small style="opacity:.6">Checked this analysis <code>autodoc/</code> folder (when an analysis is selected) and central AutoDocJsonPath.</small></div>';
    return;
  }

  try {
    const doc = await fetch(autodocUrl(fileName)).then(r => r.json());
    const flowMmd = doc?.diagrams?.flowMmd;
    if (!flowMmd) {
      container.innerHTML = '<div style="padding:40px;text-align:center;color:var(--text2)">No flowchart diagram in this document</div>';
      return;
    }
    container.dataset.mermaidSource = flowMmd;
    renderFlowchartGoJS(container, flowMmd);
  } catch (e) {
    container.innerHTML = `<div style="padding:40px;text-align:center;color:#f44">${esc(e.message)}</div>`;
  }
}

function renderFlowchartGoJS(container, mermaidText) {
  container.innerHTML = "";
  const renderer = window.autodocRenderer;
  if (!renderer?.parseMermaidToGraph) {
    container.innerHTML = '<div style="padding:40px;text-align:center;color:#f44">autodoc-renderer.js not loaded</div>';
    return;
  }

  const ugm = renderer.parseMermaidToGraph(mermaidText);
  if (!ugm || ugm._isSequence) {
    container.innerHTML = '<div style="padding:40px;text-align:center;color:var(--text2)">Could not parse flowchart (or is a sequence diagram)</div>';
    return;
  }

  const layoutKey = document.getElementById("flowchartLayout").value || "layeredTD";

  if (flowchartDiagram) { flowchartDiagram.div = null; flowchartDiagram = null; }

  const div = document.createElement("div");
  div.style.width = "100%";
  div.style.height = "100%";
  container.appendChild(div);

  const nodeCount = ugm.nodes ? ugm.nodes.length : 0;
  const LAYOUTS = {
    layeredTD: () => new go.LayeredDigraphLayout({ direction: 90, layerSpacing: 50, columnSpacing: 30 }),
    layered: () => new go.LayeredDigraphLayout({ direction: 0, layerSpacing: 50, columnSpacing: 30 }),
    force: () => new go.ForceDirectedLayout({ maxIterations: Math.min(300, 100 + nodeCount * 2) }),
    tree: () => new go.TreeLayout({ angle: 90, layerSpacing: 50, nodeSpacing: 20 })
  };

  const isDark = document.documentElement.getAttribute("data-theme") !== "light";
  const theme = {
    bg: isDark ? "#161825" : "#ffffff",
    text: isDark ? "#e2e4ea" : "#1a1a2e",
    nodeFill: isDark ? "#242838" : "#f0f4ff",
    nodeStroke: isDark ? "#4f8cff" : "#3b6de0",
    linkStroke: isDark ? "#555872" : "#999",
    linkLabelBg: isDark ? "#1e2030" : "#f8f9fc"
  };

  div.style.backgroundColor = theme.bg;

  const diagram = new go.Diagram(div, {
    layout: (LAYOUTS[layoutKey] || LAYOUTS.layeredTD)(),
    initialAutoScale: go.AutoScale.Uniform,
    padding: 30,
    scrollMode: go.ScrollMode.Infinite,
    "animationManager.isEnabled": false,
    "undoManager.isEnabled": false
  });
  diagram.toolManager.mouseWheelBehavior = go.WheelMode.Zoom;

  const SHAPE_MAP = {
    roundRect: "RoundedRectangle", rect: "Rectangle", diamond: "Diamond",
    circle: "Circle", hexagon: "Hexagon", stadium: "RoundedRectangle",
    parallelogram: "Parallelogram", trapezoid: "Trapezoid",
    cylinder: "Cylinder1", subroutine: "Procedure"
  };

  diagram.nodeTemplate = new go.Node("Auto", {
    toolTip: go.GraphObject.build("ToolTip").add(
      new go.TextBlock({ margin: 6, font: "12px Segoe UI" }).bind("text", "label")
    )
  }).add(
    new go.Shape({ strokeWidth: 2 })
      .bind("figure", "shape", s => SHAPE_MAP[s] || "RoundedRectangle")
      .bind("fill", "", d => d.fill || theme.nodeFill)
      .bind("stroke", "", d => d.stroke || theme.nodeStroke),
    new go.TextBlock({
      margin: new go.Margin(6, 10, 6, 10),
      font: '11px "Segoe UI", sans-serif',
      stroke: theme.text,
      maxSize: new go.Size(200, NaN),
      wrap: go.Wrap.Fit,
      textAlign: "center"
    }).bind("text", "label")
  );

  diagram.groupTemplate = new go.Group("Auto", {
    layout: new go.LayeredDigraphLayout({ direction: 90, layerSpacing: 40, columnSpacing: 20 }),
    isSubGraphExpanded: true
  }).add(
    new go.Shape("RoundedRectangle", {
      fill: isDark ? "#1e2030" : "#eef1f8",
      stroke: isDark ? "#2e3148" : "#c0c8e0",
      strokeWidth: 1
    }),
    new go.Panel("Vertical").add(
      new go.TextBlock({ font: "bold 12px Segoe UI", stroke: theme.text, margin: new go.Margin(6, 8, 4, 8) }).bind("text", "label"),
      new go.Placeholder({ padding: 10 })
    )
  );

  diagram.linkTemplate = new go.Link({ routing: go.Routing.AvoidsNodes, corner: 8 }).add(
    new go.Shape({ strokeWidth: 1.2, stroke: theme.linkStroke }),
    new go.Shape({ toArrow: "Standard", scale: 1, fill: theme.linkStroke, stroke: theme.linkStroke }),
    new go.Panel("Auto").add(
      new go.Shape({ fill: theme.linkLabelBg, stroke: null, opacity: 0.9 }),
      new go.TextBlock({ font: '10px "Segoe UI"', stroke: theme.text, margin: 2, maxSize: new go.Size(150, NaN) }).bind("text", "label")
    )
  );

  const nodeDataArray = ugm.nodes.map(n => ({
    key: n.id,
    label: n.label || n.id,
    shape: n.shape || "roundRect",
    fill: n.fill || null,
    stroke: n.stroke || null,
    group: n.group || undefined
  }));

  const groupDataArray = (ugm.subgraphs || []).map(sg => ({
    key: sg.id,
    label: sg.label || sg.id,
    isGroup: true,
    group: sg.parent || undefined
  }));

  const linkDataArray = ugm.edges.map(e => ({
    from: e.from,
    to: e.to,
    label: e.label || ""
  }));

  diagram.model = new go.GraphLinksModel({
    nodeKeyProperty: "key",
    linkFromKeyProperty: "from",
    linkToKeyProperty: "to",
    nodeDataArray: [...groupDataArray, ...nodeDataArray],
    linkDataArray
  });

  flowchartDiagram = diagram;
}

function closeFlowchart() {
  document.getElementById("flowchartOverlay").style.display = "none";
  if (flowchartDiagram) { flowchartDiagram.div = null; flowchartDiagram = null; }
}

// ═══════════════════════════════════════════════════════════════════════
//  SAVE / LOAD LAYOUT
// ═══════════════════════════════════════════════════════════════════════

function captureNodePositions() {
  if (!gojsDiagram || activeRenderer !== "gojs") return null;
  const positions = {};
  gojsDiagram.nodes.each(node => {
    if (node.key && node.location && node.location.isReal()) {
      positions[node.key] = { x: Math.round(node.location.x * 10) / 10, y: Math.round(node.location.y * 10) / 10 };
    }
  });
  return positions;
}

function getVisibleProgramKeys() {
  return currentNodes.filter(n => n.type?.startsWith("program")).map(n => n.key);
}

async function savePositionsToMaster() {
  const positions = captureNodePositions();
  if (!positions || Object.keys(positions).length === 0) {
    showToast("No node positions to save");
    return;
  }

  const btn = document.getElementById("btnSavePositions");
  const origText = btn.innerHTML;
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> Saving…';

  try {
    const r = await fetch(`api/data/${encodeURIComponent(alias)}/save-node-positions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ nodePositions: positions })
    });
    const result = await r.json();
    if (r.ok) {
      showToast(`Positions saved: ${result.nodeCount} nodes in ${result.saved} file(s)`);
      if (DATA.master) DATA.master.nodePositions = positions;
    } else {
      alert("Save failed: " + (result.error || r.statusText));
    }
  } catch (e) {
    alert("Save positions failed: " + e.message);
  } finally {
    btn.disabled = false;
    btn.innerHTML = origText;
  }
}

async function saveLayoutToServer() {
  const modal = document.getElementById("saveLayoutModal");
  modal.style.display = "flex";
  document.getElementById("saveLayoutComment").value = "";
  document.getElementById("saveLayoutComment").focus();
}

async function doSaveLayout() {
  const comment = document.getElementById("saveLayoutComment").value.trim() || "layout";
  document.getElementById("saveLayoutModal").style.display = "none";

  const payload = {
    layoutVersion: 1,
    comment,
    analysisAlias: alias,
    savedAt: new Date().toISOString(),
    ui: {
      renderer: document.getElementById("selRenderer").value,
      layout: document.getElementById("selLayout").value,
      linkStyle: document.getElementById("selLinkStyle")?.value || "avoids",
      mermaidDir: document.getElementById("selMermaidDir").value,
      threshold: parseInt(document.getElementById("inpThreshold").value) || 200
    },
    filters: { applied: filterPanel.getApplied() },
    nodePositions: captureNodePositions(),
    visiblePrograms: getVisibleProgramKeys(),
    drillStack: drillStack.map(d => ({ label: d.label })),
    isolationMode,
    isolationSet: isolationMode ? [...isolationSet] : []
  };

  try {
    const r = await fetch(`api/layout/${encodeURIComponent(alias)}/save`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    const result = await r.json();
    if (r.ok) {
      showToast(`Layout saved: ${result.fileName}`);
    } else {
      alert("Save failed: " + (result.error || r.statusText));
    }
  } catch (e) {
    alert("Save failed: " + e.message);
  }
}

async function openLoadLayoutModal() {
  const modal = document.getElementById("loadLayoutModal");
  const list = document.getElementById("loadLayoutList");
  modal.style.display = "flex";
  list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text2)">Loading...</div>';

  try {
    const r = await fetch(`api/layout/${encodeURIComponent(alias)}/list`);
    const data = await r.json();
    if (!data.layouts?.length) {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text2)">No saved layouts for this analysis</div>';
      return;
    }
    list.innerHTML = data.layouts.map(l => `
      <div class="layout-item" data-file="${esc(l.fileName)}">
        <div>
          <div class="layout-comment">${esc(l.comment || l.fileName)}</div>
          <div class="layout-meta">${esc(l.savedBy)} &middot; ${new Date(l.lastModified).toLocaleString()}</div>
        </div>
        <button class="btn" style="font-size:11px;padding:2px 8px" data-delete="${esc(l.fileName)}">Del</button>
      </div>
    `).join("");

    list.querySelectorAll(".layout-item").forEach(el => {
      el.addEventListener("click", async (e) => {
        if (e.target.closest("[data-delete]")) return;
        modal.style.display = "none";
        await loadLayoutFromServer(el.dataset.file);
      });
    });
    list.querySelectorAll("[data-delete]").forEach(btn => {
      btn.addEventListener("click", async (e) => {
        e.stopPropagation();
        if (!confirm("Delete this layout?")) return;
        await fetch(`api/layout/${encodeURIComponent(alias)}/${encodeURIComponent(btn.dataset.delete)}`, { method: "DELETE" });
        openLoadLayoutModal();
      });
    });
  } catch (e) {
    list.innerHTML = `<div style="padding:20px;color:#f44">${esc(e.message)}</div>`;
  }
}

async function loadLayoutFromServer(fileName) {
  document.getElementById("loadingMsg").style.display = "flex";
  setProgress(10, "Loading layout...");
  await yieldToUI(100);

  try {
    const r = await fetch(`api/layout/${encodeURIComponent(alias)}/load?file=${encodeURIComponent(fileName)}`);
    const layout = await r.json();

    if (layout.filters?.applied) {
      filterPanel.setApplied(layout.filters.applied);
    }
    if (layout.ui) {
      if (layout.ui.renderer) document.getElementById("selRenderer").value = layout.ui.renderer;
      if (layout.ui.layout) document.getElementById("selLayout").value = layout.ui.layout;
      if (layout.ui.linkStyle) { const sel = document.getElementById("selLinkStyle"); if (sel) sel.value = layout.ui.linkStyle; }
      if (layout.ui.mermaidDir) document.getElementById("selMermaidDir").value = layout.ui.mermaidDir;
      if (layout.ui.threshold) document.getElementById("inpThreshold").value = layout.ui.threshold;
    }

    if (layout.isolationMode) {
      isolationMode = true;
      isolationSet = new Set(layout.isolationSet || []);
      updateIsolationBadge();
    }

    setProgress(50, "Rebuilding graph...");
    await yieldToUI(100);
    await buildGraph();

    if (layout.nodePositions && gojsDiagram && activeRenderer === "gojs") {
      gojsDiagram.startTransaction("restore positions");
      gojsDiagram.nodes.each(node => {
        const pos = layout.nodePositions[node.key];
        if (pos) node.location = new go.Point(pos.x, pos.y);
      });
      gojsDiagram.commitTransaction("restore positions");
    }

    saveState();
    showToast(`Layout loaded: ${fileName}`);
  } catch (e) {
    alert("Load failed: " + e.message);
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  FOCUSED PROFILE
// ═══════════════════════════════════════════════════════════════════════

function openFocusedProfileModal() {
  const progs = getVisibleProgramKeys();
  document.getElementById("fpInfo").textContent = `Create a new analysis profile with the ${progs.length} programs currently visible in the graph. Source: ${alias}`;
  document.getElementById("fpNewAlias").value = alias ? alias + "_focused" : "";
  document.getElementById("fpComment").value = "";
  document.getElementById("focusedProfileModal").style.display = "flex";
}

async function doCreateFocusedProfile() {
  const newAlias = document.getElementById("fpNewAlias").value.trim();
  const comment = document.getElementById("fpComment").value.trim();
  if (!newAlias) { alert("Profile name is required"); return; }

  document.getElementById("focusedProfileModal").style.display = "none";
  const progs = getVisibleProgramKeys();

  try {
    const r = await fetch("api/profile/create-focused", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sourceAlias: alias, newAlias, comment, programs: progs })
    });
    const result = await r.json();
    if (r.ok) {
      showToast(`Profile "${result.alias}" created with ${result.programCount} programs`);
    } else {
      alert("Failed: " + (result.error || r.statusText));
    }
  } catch (e) {
    alert("Failed: " + e.message);
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  BUSINESS AREA HELPERS
// ═══════════════════════════════════════════════════════════════════════

const AREA_COLORS = [
  "#4f8cff", "#ff6b6b", "#51cf66", "#fcc419", "#cc5de8",
  "#20c997", "#ff922b", "#845ef7", "#339af0", "#f06595",
  "#22b8cf", "#fab005", "#7950f2", "#e64980", "#12b886"
];

function getAreaColor(areaId) {
  const areas = [...businessAreaSet];
  const idx = areas.indexOf(areaId);
  return idx >= 0 ? AREA_COLORS[idx % AREA_COLORS.length] : "#666";
}

// ═══════════════════════════════════════════════════════════════════════
//  REASSIGN BUSINESS AREA DIALOG
// ═══════════════════════════════════════════════════════════════════════

function showReassignBusinessAreaDialog(programName) {
  let overlay = document.getElementById("baOverlay");
  if (overlay) overlay.remove();

  overlay = document.createElement("div");
  overlay.id = "baOverlay";
  overlay.style.cssText = "position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:10000;display:flex;align-items:center;justify-content:center";

  const areas = DATA.businessAreas?.areas || [];
  const currentAreaId = businessAreaIndex[programName] || "";
  const currentId = typeof currentAreaId === "string" ? currentAreaId : currentAreaId[0];

  let optionsHtml = areas.map(a =>
    `<option value="${esc(a.id)}" ${a.id === currentId ? "selected" : ""}>${esc(a.name || a.id)}</option>`
  ).join("");
  optionsHtml += `<option value="__new__">+ Add New Area...</option>`;

  const dialog = document.createElement("div");
  dialog.style.cssText = "background:#1e2030;border:1px solid #2e3148;border-radius:12px;padding:24px 28px;min-width:340px;max-width:460px;color:#e2e4ea;font-family:'Segoe UI',sans-serif;box-shadow:0 8px 32px rgba(0,0,0,.5)";
  dialog.innerHTML = `
    <div style="font-size:16px;font-weight:600;margin-bottom:16px">Reassign Business Area</div>
    <div style="font-size:13px;color:#9ea0b0;margin-bottom:12px">Program: <strong style="color:#e2e4ea">${esc(programName)}</strong></div>
    <label style="font-size:12px;color:#9ea0b0;display:block;margin-bottom:4px">Select business area:</label>
    <select id="baSelect" style="width:100%;padding:8px 10px;border-radius:6px;border:1px solid #3a3d56;background:#282a3a;color:#e2e4ea;font-size:13px;margin-bottom:12px;outline:none">${optionsHtml}</select>
    <div id="baNewFields" style="display:none;margin-bottom:12px">
      <label style="font-size:12px;color:#9ea0b0;display:block;margin-bottom:4px">New Area ID (lowercase, dashes):</label>
      <input id="baNewId" type="text" placeholder="e.g. grain-logistics" style="width:100%;padding:7px 10px;border-radius:6px;border:1px solid #3a3d56;background:#282a3a;color:#e2e4ea;font-size:13px;margin-bottom:8px;outline:none;box-sizing:border-box">
      <label style="font-size:12px;color:#9ea0b0;display:block;margin-bottom:4px">Display Name:</label>
      <input id="baNewName" type="text" placeholder="e.g. Grain Logistics" style="width:100%;padding:7px 10px;border-radius:6px;border:1px solid #3a3d56;background:#282a3a;color:#e2e4ea;font-size:13px;margin-bottom:8px;outline:none;box-sizing:border-box">
      <label style="font-size:12px;color:#9ea0b0;display:block;margin-bottom:4px">Description (optional):</label>
      <input id="baNewDesc" type="text" placeholder="" style="width:100%;padding:7px 10px;border-radius:6px;border:1px solid #3a3d56;background:#282a3a;color:#e2e4ea;font-size:13px;outline:none;box-sizing:border-box">
    </div>
    <div id="baError" style="color:#f66;font-size:12px;margin-bottom:8px;display:none"></div>
    <div style="display:flex;gap:10px;justify-content:flex-end;margin-top:16px">
      <button id="baCancelBtn" style="padding:7px 18px;border-radius:6px;border:1px solid #3a3d56;background:transparent;color:#9ea0b0;cursor:pointer;font-size:13px">Cancel</button>
      <button id="baSaveBtn" style="padding:7px 18px;border-radius:6px;border:none;background:#3a7bd5;color:#fff;cursor:pointer;font-size:13px;font-weight:500">Save</button>
    </div>`;

  overlay.appendChild(dialog);
  document.body.appendChild(overlay);

  const select = document.getElementById("baSelect");
  const newFields = document.getElementById("baNewFields");
  const errorEl = document.getElementById("baError");

  select.addEventListener("change", () => {
    newFields.style.display = select.value === "__new__" ? "block" : "none";
    errorEl.style.display = "none";
  });

  overlay.addEventListener("click", e => { if (e.target === overlay) overlay.remove(); });
  document.getElementById("baCancelBtn").addEventListener("click", () => overlay.remove());

  document.getElementById("baSaveBtn").addEventListener("click", async () => {
    errorEl.style.display = "none";
    let areaId = select.value;
    let newArea = null;

    if (areaId === "__new__") {
      const nid = document.getElementById("baNewId").value.trim();
      const nname = document.getElementById("baNewName").value.trim();
      const ndesc = document.getElementById("baNewDesc").value.trim();
      if (!nid || !nname) {
        errorEl.textContent = "ID and Name are required for a new area.";
        errorEl.style.display = "block";
        return;
      }
      if (!/^[a-z0-9-]+$/.test(nid)) {
        errorEl.textContent = "ID must be lowercase letters, digits, and dashes only.";
        errorEl.style.display = "block";
        return;
      }
      areaId = nid;
      newArea = { id: nid, name: nname, description: ndesc || "" };
    }

    const saveBtn = document.getElementById("baSaveBtn");
    saveBtn.disabled = true;
    saveBtn.textContent = "Saving...";

    try {
      const body = { program: programName, areaId, newArea };
      const resp = await fetch(`api/data/${encodeURIComponent(alias)}/business-area-override`, {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body)
      });
      if (!resp.ok) {
        const err = await resp.json().catch(() => ({}));
        throw new Error(err.error || `HTTP ${resp.status}`);
      }
      const merged = await resp.json();

      DATA.businessAreas = merged;
      Object.keys(businessAreaIndex).forEach(k => delete businessAreaIndex[k]);
      businessAreaSet.clear();
      if (merged.programAreaMap) {
        Object.entries(merged.programAreaMap).forEach(([prog, aid]) => {
          businessAreaIndex[prog] = aid;
          if (typeof aid === "string") businessAreaSet.add(aid);
          else if (Array.isArray(aid)) aid.forEach(a => businessAreaSet.add(a));
        });
      }

      overlay.remove();
      showToast(`${programName} reassigned to "${newArea?.name || areaId}"`);
      await buildGraph();
    } catch (err) {
      errorEl.textContent = "Save failed: " + err.message;
      errorEl.style.display = "block";
      saveBtn.disabled = false;
      saveBtn.textContent = "Save";
    }
  });
}

// ═══════════════════════════════════════════════════════════════════════
//  TOAST NOTIFICATION
// ═══════════════════════════════════════════════════════════════════════

function showToast(message, duration = 3000) {
  let toast = document.getElementById("saToast");
  if (!toast) {
    toast = document.createElement("div");
    toast.id = "saToast";
    toast.style.cssText = "position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#242838;color:#e2e4ea;padding:10px 24px;border-radius:8px;font-size:13px;box-shadow:0 4px 16px rgba(0,0,0,.4);z-index:9999;transition:opacity .3s;border:1px solid #2e3148";
    document.body.appendChild(toast);
  }
  toast.textContent = message;
  toast.style.opacity = "1";
  toast.style.display = "block";
  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => { toast.style.opacity = "0"; setTimeout(() => { toast.style.display = "none"; }, 300); }, duration);
}

// ═══════════════════════════════════════════════════════════════════════
//  EVENT WIRING
// ═══════════════════════════════════════════════════════════════════════
let rebuildTimer;
function scheduleRebuild() {
  if (!initialized) return;
  clearTimeout(rebuildTimer);
  rebuildTimer = setTimeout(async () => {
    document.getElementById("loadingMsg").style.display = "flex";
    setProgress(30, "Rebuilding graph…");
    await yieldToUI(100);
    await buildGraph();
    saveState();
  }, 150);
}

// ═══════════════════════════════════════════════════════════════════════
//  LOAD CUSTOM ANALYSIS FROM EXPORTED JSON
// ═══════════════════════════════════════════════════════════════════════
let previousAlias = null;

function addCustomOption() {
  const sel = document.getElementById("aliasSelect");
  if (!sel.querySelector('option[value="__custom__"]')) {
    const opt = document.createElement("option");
    opt.value = "__custom__";
    opt.textContent = "Custom";
    sel.appendChild(opt);
  }
  previousAlias = alias;
  sel.value = "__custom__";
}

function restoreFromCustom() {
  const sel = document.getElementById("aliasSelect");
  const customOpt = sel.querySelector('option[value="__custom__"]');
  if (customOpt) sel.removeChild(customOpt);
  if (previousAlias && sel.querySelector(`option[value="${previousAlias}"]`)) {
    sel.value = previousAlias;
  }
  previousAlias = null;
}

async function loadCustomAnalysis(file) {
  document.getElementById("loadingMsg").style.display = "flex";
  setProgress(5, "Reading file…");
  await yieldToUI(100);

  let payload;
  try {
    const text = await file.text();
    payload = JSON.parse(text);
  } catch (e) {
    setProgress(0, "Invalid JSON file: " + e.message);
    return;
  }

  if (!payload.exportVersion || !payload.graph?.nodes) {
    setProgress(0, "This file is not a full graph export (missing graph.nodes).");
    return;
  }

  setProgress(20, "Applying imported data…");
  await yieldToUI(100);

  Object.keys(masterIndex).forEach(k => delete masterIndex[k]);
  Object.keys(progIndex).forEach(k => delete progIndex[k]);
  Object.keys(classIndex).forEach(k => delete classIndex[k]);
  categorySet.clear();
  Object.keys(verifyIndex).forEach(k => delete verifyIndex[k]);
  Object.keys(calledByIndex).forEach(k => delete calledByIndex[k]);
  Object.keys(copyByProgram).forEach(k => delete copyByProgram[k]);
  Object.keys(copyIndex).forEach(k => delete copyIndex[k]);

  const ents = payload.entities || {};
  const progs = [];
  if (ents.programs) {
    for (const [name, data] of Object.entries(ents.programs)) {
      if (data.fromAllTotalPrograms) progs.push(data.fromAllTotalPrograms);
      if (data.fromDependencyMaster) masterIndex[name] = data.fromDependencyMaster;
    }
  }
  DATA.progs = { programs: progs };

  const callEdges = payload.crossReferences?.allCallGraphEdgesBetweenGraphPrograms ||
                    payload.graph?.edges?.filter(e => e.type === "call").map(e => ({ caller: e.from, callee: e.to })) || [];
  DATA.call = { edges: callEdges };

  const sqlRefs = payload.crossReferences?.allSqlTableReferencesForGraphPrograms || [];
  DATA.sql = { tableReferences: sqlRefs };

  const fioRefs = payload.crossReferences?.allFileReferencesForGraphPrograms || [];
  DATA.fio = { fileReferences: fioRefs };

  if (payload.copyCatalog?.copyElementsForGraphCopyNodes) {
    DATA.copy = { copyElements: payload.copyCatalog.copyElementsForGraphCopyNodes };
  }

  DATA.master = null;
  DATA.verify = payload.reports?.sourceVerificationFull || null;
  DATA.db2TableValidation = payload.reports?.db2TableValidationFull || null;
  DATA.appliedExclusions = payload.reports?.appliedExclusionsFull || null;
  DATA.standardCobolFiltered = payload.reports?.standardCobolFilteredFull || null;
  DATA.seedAll = payload.seedAllJson || null;

  setProgress(40, "Building indices…");
  await yieldToUI(100);
  buildIndices();

  if (payload.filters?.applied) {
    filterPanel.setApplied(payload.filters.applied);
  }

  if (payload.ui) {
    if (payload.ui.rendererSelect) document.getElementById("selRenderer").value = payload.ui.rendererSelect;
    if (payload.ui.layout) document.getElementById("selLayout").value = payload.ui.layout;
    if (payload.ui.linkStyle) { const sel = document.getElementById("selLinkStyle"); if (sel) sel.value = payload.ui.linkStyle; }
    if (payload.ui.mermaidDir) document.getElementById("selMermaidDir").value = payload.ui.mermaidDir;
    if (payload.ui.threshold) document.getElementById("inpThreshold").value = payload.ui.threshold;
  }

  alias = payload.analysisAlias || "Custom";
  addCustomOption();

  setProgress(60, "Building graph…");
  await yieldToUI(150);
  await buildGraph();
  saveState();
}

document.getElementById("btnLoadAnalysis").addEventListener("click", () => {
  document.getElementById("fileLoadAnalysis").click();
});
document.getElementById("fileLoadAnalysis").addEventListener("change", async (e) => {
  const file = e.target.files?.[0];
  if (!file) return;
  await loadCustomAnalysis(file);
  e.target.value = "";
});

document.getElementById("aliasSelect").addEventListener("change", (e) => {
  if (e.target.value === "__custom__") return;
  if (previousAlias !== null) restoreFromCustom();
});

document.getElementById("selRenderer").addEventListener("change", scheduleRebuild);
document.getElementById("selLayout").addEventListener("change", scheduleRebuild);
document.getElementById("selMermaidDir").addEventListener("change", scheduleRebuild);
document.getElementById("selIconProfile").addEventListener("change", scheduleRebuild);
document.getElementById("selLinkStyle").addEventListener("change", scheduleRebuild);
document.getElementById("chkGroupByArea").addEventListener("change", scheduleRebuild);
document.getElementById("inpThreshold").addEventListener("change", scheduleRebuild);
document.querySelectorAll("#toolbarTech input[type=checkbox]").forEach(cb => {
  cb.addEventListener("change", () => { scheduleRebuild(); saveState(); });
});
document.getElementById("btnReset").addEventListener("click", resetDefaults);
document.getElementById("btnExportSvg").addEventListener("click", exportSvg);
document.getElementById("btnExportJson").addEventListener("click", exportFilteredJson);
document.getElementById("btnZoomIn").addEventListener("click", handleZoomIn);
document.getElementById("btnZoomOut").addEventListener("click", handleZoomOut);
document.getElementById("btnZoomFit").addEventListener("click", handleZoomFit);

document.getElementById("detailPanel").addEventListener("click", e => {
  const link = e.target.closest("a[data-nav]");
  if (link) { e.preventDefault(); navigateToNode(link.dataset.nav); }
});

document.getElementById("btnOpenFilters").addEventListener("click", () => filterPanel.open());
document.getElementById("fpApply").addEventListener("click", () => filterPanel.apply());
document.getElementById("fpCancel").addEventListener("click", () => filterPanel.cancel());
document.getElementById("fpReset").addEventListener("click", () => filterPanel.reset());

document.getElementById("btnDrillBack").addEventListener("click", () => popDrillState());
document.getElementById("btnDrillReset").addEventListener("click", () => resetDrillState());

document.getElementById("btnSavePositions").addEventListener("click", savePositionsToMaster);
document.getElementById("btnSaveLayout").addEventListener("click", saveLayoutToServer);
document.getElementById("saveLayoutConfirm").addEventListener("click", doSaveLayout);
document.getElementById("saveLayoutCancel").addEventListener("click", () => { document.getElementById("saveLayoutModal").style.display = "none"; });
document.getElementById("saveLayoutComment").addEventListener("keydown", (e) => { if (e.key === "Enter") doSaveLayout(); });

document.getElementById("btnLoadLayout").addEventListener("click", openLoadLayoutModal);
document.getElementById("loadLayoutCancel").addEventListener("click", () => { document.getElementById("loadLayoutModal").style.display = "none"; });

document.getElementById("btnFocusedProfile").addEventListener("click", openFocusedProfileModal);
document.getElementById("fpCreate").addEventListener("click", doCreateFocusedProfile);
document.getElementById("fpCancel2").addEventListener("click", () => { document.getElementById("focusedProfileModal").style.display = "none"; });

document.getElementById("flowchartClose").addEventListener("click", closeFlowchart);
document.getElementById("flowchartZoomIn").addEventListener("click", () => { if (flowchartDiagram) flowchartDiagram.commandHandler.increaseZoom(); });
document.getElementById("flowchartZoomOut").addEventListener("click", () => { if (flowchartDiagram) flowchartDiagram.commandHandler.decreaseZoom(); });
document.getElementById("flowchartZoomFit").addEventListener("click", () => { if (flowchartDiagram) flowchartDiagram.zoomToFit(); });
document.getElementById("flowchartLayout").addEventListener("change", () => {
  if (!flowchartDiagram) return;
  const container = document.getElementById("flowchartContainer");
  const source = container.dataset.mermaidSource;
  if (source) renderFlowchartGoJS(container, source);
});
document.addEventListener("keydown", (e) => { if (e.key === "Escape" && document.getElementById("flowchartOverlay").style.display !== "none") closeFlowchart(); });

document.getElementById("filterPanelOverlay").addEventListener("click", e => {
  if (e.target === e.currentTarget) filterPanel.cancel();
});

// ═══════════════════════════════════════════════════════════════════════
//  TECHNOLOGY CATALOG (supported-technologies.json + profile from all.json)
// ═══════════════════════════════════════════════════════════════════════
function buildTechnologyCatalogHtml(data) {
  if (!data?.supportedCatalog?.technologies) return "<p>No catalog.</p>";
  const pt = data.profileTechnologies || [];
  const active = new Set(
    pt.map(p => `${String(p.technologyId || "").toLowerCase()}|${String(p.vendor || "").toLowerCase()}|${String(p.product || "").toLowerCase()}`)
  );
  let h = "";
  if (data.profileDatabases?.length) {
    h += "<h3 class=\"tech-cat-h3\">Profile databases (all.json)</h3><ul class=\"tech-cat-ul\">";
    data.profileDatabases.forEach(d => {
      const bits = [d.type, d.alias || d.connectionName, d.database || d.dsn].filter(Boolean).join(" · ");
      h += `<li>${esc(bits || JSON.stringify(d))}</li>`;
    });
    h += "</ul>";
  }
  if (pt.length) {
    h += "<h3 class=\"tech-cat-h3\">Technologies in this profile</h3><ul class=\"tech-cat-ul\">";
    pt.forEach(p => {
      let imp = " — no catalog match";
      if (p.matchedCatalogProduct?.implemented === true) imp = " — implemented in analyzer";
      else if (p.matchedCatalogProduct) imp = " — catalog match";
      h += `<li><strong>${esc(p.technologyId)}</strong> — ${esc(p.vendor)}/${esc(p.product)} — ${p.entryCount} entries${imp}</li>`;
    });
    h += "</ul>";
  }
  h += "<h3 class=\"tech-cat-h3\">Full supported-technologies catalog</h3>";
  for (const tech of data.supportedCatalog.technologies) {
    const tid = tech.technologyId || "";
    h += `<details class="tech-cat-tech"><summary>${esc(tid)}</summary>`;
    for (const v of tech.vendors || []) {
      h += `<div class="tech-cat-vendor"><strong>${esc(v.vendorName || v.vendorId)}</strong>`;
      for (const prod of v.products || []) {
        const key = `${String(tid).toLowerCase()}|${String(v.vendorId || "").toLowerCase()}|${String(prod.productId || "").toLowerCase()}`;
        const inProf = active.has(key) ? " tech-cat-in-profile" : "";
        const impl = prod.implemented ? "implemented" : "not implemented";
        h += `<div class="tech-cat-prod${inProf}"><span class="tech-cat-name">${esc(prod.productName || prod.productId)}</span> `;
        h += `<span class="tech-cat-meta">${esc(impl)}</span>`;
        if (prod.versions?.length) h += ` <span class="tech-cat-ver">${esc(prod.versions.join(", "))}</span>`;
        if (prod.platforms?.length) h += ` <span class="tech-cat-plat">${esc(prod.platforms.join(", "))}</span>`;
        if (prod.note) h += `<div class="tech-cat-note">${esc(prod.note)}</div>`;
        if (prod.notes) h += `<div class="tech-cat-note">${esc(prod.notes)}</div>`;
        h += "</div>";
      }
      h += "</div>";
    }
    h += "</details>";
  }
  return h;
}

async function openTechnologyCatalog() {
  const overlay = document.getElementById("techCatalogOverlay");
  const body = document.getElementById("techCatalogBody");
  if (!overlay || !body) return;
  overlay.style.display = "flex";
  body.innerHTML = "<div style=\"padding:20px;color:var(--text2)\">Loading…</div>";
  try {
    const r = await fetch(`api/technology/analysis/${encodeURIComponent(alias)}`);
    if (!r.ok) {
      body.innerHTML = `<div class="doc-error">HTTP ${r.status}</div>`;
      return;
    }
    const data = await r.json();
    body.innerHTML = buildTechnologyCatalogHtml(data);
  } catch (e) {
    body.innerHTML = `<div class="doc-error">${esc(e.message)}</div>`;
  }
}

function closeTechnologyCatalog() {
  const overlay = document.getElementById("techCatalogOverlay");
  if (overlay) overlay.style.display = "none";
}

const btnTechCatalog = document.getElementById("btnTechCatalog");
if (btnTechCatalog) btnTechCatalog.addEventListener("click", () => openTechnologyCatalog());
const techCatalogClose = document.getElementById("techCatalogClose");
if (techCatalogClose) techCatalogClose.addEventListener("click", () => closeTechnologyCatalog());
const techCatalogOverlay = document.getElementById("techCatalogOverlay");
if (techCatalogOverlay) {
  techCatalogOverlay.addEventListener("click", e => {
    if (e.target === techCatalogOverlay) closeTechnologyCatalog();
  });
}

// ═══════════════════════════════════════════════════════════════════════
//  INIT
// ═══════════════════════════════════════════════════════════════════════
async function init() {
  setProgress(5, "Loading analysis list…");
  await yieldToUI(100);

  filterPanel = new FilterPanel();

  alias = await initAliasSelect("aliasSelect");
  setAliasInLink("viewerLink", "viewer.html", alias);
  setAliasInLink("presentLink", "present.html", alias);

  setProgress(10, "Loading core data…");
  await yieldToUI(100);
  await loadCoreData();

  setProgress(55, "Applying saved state…");
  await yieldToUI(100);

  const saved = loadState();
  applyState(saved);

  setProgress(60, "Building graph…");
  await yieldToUI(150);

  await buildGraph();
  initialized = true;

  await loadSupplementalData();
  await buildGraph();
}

init().catch(e => {
  console.error("[graph] init FAILED:", e);
  setProgress(0, "Error: " + String(e));
  document.getElementById("loadingMsg").style.display = "flex";
});
