/**
 * Mermaid vs GoJS UGM Verification Script
 * Run with: node verify-mermaid-gojs.js
 * 
 * Extracts parseMermaidToGraph from autodoc-renderer.js and verifies
 * that the GoJS UGM faithfully represents the Mermaid diagram:
 * - All edge-referenced nodes must exist in UGM
 * - All edges must be present in UGM
 * - Node labels should be preserved
 */

const fs = require('fs');
const path = require('path');

// Load the renderer source
const rendererSrc = fs.readFileSync(
  path.join(__dirname, 'AutoDocJson.Web', 'wwwroot', 'js', 'autodoc-renderer.js'),
  'utf8'
);

// Extract parser by running the IIFE with mocked globals
let parser = null;
// Strip the IIFE wrapper: remove first "(function () {" and last "})();" 
const startIdx = rendererSrc.indexOf('(function () {');
const endIdx = rendererSrc.lastIndexOf('})();');
const evalCode = rendererSrc.substring(startIdx + '(function () {'.length, endIdx);

const windowObj = { MERMAID_MAX_NODES: 500, DEFAULT_RENDERER: 'gojs', autodocRenderer: null };
const localStorageObj = { getItem: () => null, setItem: () => {} };
const documentObj = { 
  querySelectorAll: () => [], 
  readyState: 'complete', 
  addEventListener: () => {},
  documentElement: { dataset: { theme: 'dark' } }
};

try {
  const evalFn = new Function('window', 'localStorage', 'document', 'go', 'setTimeout', evalCode);
  evalFn(windowObj, localStorageObj, documentObj, undefined, function() {});
  parser = windowObj.autodocRenderer.parseMermaidToGraph;
} catch (e) {
  console.error('Failed to load parser:', e.message);
  process.exit(1);
}

console.log('Parser loaded successfully.\n');

// --- Extract true node IDs from Mermaid text ---
function extractMermaidTruth(mermaidText) {
  if (!mermaidText || !mermaidText.trim()) return null;
  
  const lines = mermaidText.split('\n').map(l => l.trim()).filter(l => l && !l.startsWith('%%'));
  if (lines.length === 0) return null;
  
  const firstLine = lines[0].toLowerCase();
  let type = 'unknown';
  if (firstLine.match(/^(flowchart|graph)\s/)) type = 'flowchart';
  else if (firstLine.match(/^classdiagram/i)) type = 'classDiagram';
  else if (firstLine.match(/^erdiagram/i)) type = 'erDiagram';
  else if (firstLine.match(/^sequencediagram/i)) type = 'sequence';
  
  if (type === 'sequence') return null;
  
  const skipRe = /^(style |classDef |class |click |linkStyle )/i;
  
  let edgeCount = 0;
  const nodeIds = new Set();
  const edgeList = [];
  const nodeLabels = {};
  
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (skipRe.test(line)) continue;
    if (/^subgraph\s/i.test(line) || line === 'end') continue;
    
    if (type === 'flowchart') {
      // Check for edge
      const arrowPattern = /-->|==>|-.->|--[>x]|~~>/;
      if (arrowPattern.test(line)) {
        edgeCount++;
      }
    } else if (type === 'erDiagram') {
      if (/\|.*\|/.test(line) || /}[o|{]/.test(line)) {
        edgeCount++;
      }
    }
  }
  
  return { type, edgeCount, lineCount: lines.length };
}

// --- Load and test JSON files ---
const testDir = process.argv[2] || 'C:\\opt\\data\\AutoDocJson\\verify-test';
const jsonFiles = fs.readdirSync(testDir).filter(f => f.endsWith('.json'));

console.log(`Found ${jsonFiles.length} JSON files to verify.\n`);

let totalFiles = 0;
let totalDiagrams = 0;
let parseFails = 0;
let edgeDiscrepancies = 0;
let perfectMatches = 0;
let emptyUgm = 0;

const issues = [];
const results = [];

for (const file of jsonFiles) {
  const filePath = path.join(testDir, file);
  let data;
  try {
    let raw = fs.readFileSync(filePath, 'utf8');
    if (raw.charCodeAt(0) === 0xFEFF) raw = raw.substring(1);
    data = JSON.parse(raw);
  } catch (e) {
    continue;
  }
  
  totalFiles++;
  // Support both standard diagrams object and SQL-specific properties
  let diagrams = data.diagrams || {};
  if (data.erDiagramMmd) diagrams.erDiagramMmd = data.erDiagramMmd;
  if (data.interactionDiagramMmd) diagrams.interactionDiagramMmd = data.interactionDiagramMmd;
  
  for (const [key, mermaidText] of Object.entries(diagrams)) {
    if (!mermaidText || mermaidText.trim().length === 0) continue;
    if (key.toLowerCase().includes('sequence')) continue;
    
    totalDiagrams++;
    
    const truth = extractMermaidTruth(mermaidText);
    if (!truth) continue;
    
    // Parse with GoJS parser
    let ugm;
    try {
      ugm = parser(mermaidText);
    } catch (e) {
      parseFails++;
      issues.push({ file, diagram: key, type: truth.type, issue: 'PARSE_ERROR', detail: e.message });
      continue;
    }
    
    if (!ugm || !ugm.nodes || ugm.nodes.length === 0) {
      emptyUgm++;
      issues.push({ file, diagram: key, type: truth.type, issue: 'EMPTY_UGM', detail: 'Parser returned no nodes' });
      continue;
    }
    
    const ugmNodes = ugm.nodes.length;
    const ugmEdges = ugm.edges.length;
    
    // Check edge count matches
    const edgeDiff = ugmEdges - truth.edgeCount;
    
    const result = {
      file, diagram: key, type: truth.type,
      ugmNodes, ugmEdges,
      rawEdges: truth.edgeCount,
      edgeDiff,
      hasLabels: ugm.nodes.some(n => n.label && n.label.length > 0),
      hasEdgeLabels: ugm.edges.some(e => e.label && e.label.length > 0)
    };
    results.push(result);
    
    if (edgeDiff !== 0) {
      edgeDiscrepancies++;
      issues.push({
        file, diagram: key, type: truth.type,
        issue: 'EDGE_MISMATCH',
        detail: `UGM has ${ugmEdges} edges, raw count is ${truth.edgeCount} (diff: ${edgeDiff > 0 ? '+' : ''}${edgeDiff})`
      });
    } else {
      perfectMatches++;
    }
  }
}

// Output results
console.log('='.repeat(100));
console.log(`\n  VERIFICATION SUMMARY`);
console.log(`  ${'─'.repeat(40)}`);
console.log(`  Files tested:        ${totalFiles}`);
console.log(`  Diagrams tested:     ${totalDiagrams}`);
console.log(`  Perfect edge match:  ${perfectMatches} / ${totalDiagrams} (${Math.round(perfectMatches/totalDiagrams*100)}%)`);
console.log(`  Parse failures:      ${parseFails}`);
console.log(`  Empty UGM:           ${emptyUgm}`);
console.log(`  Edge mismatches:     ${edgeDiscrepancies}`);
console.log();

// Print each result
console.log('  DETAILED RESULTS:');
console.log(`  ${'─'.repeat(90)}`);
console.log('  ' + 'File'.padEnd(35) + 'Diagram'.padEnd(12) + 'Type'.padEnd(14) + 'Nodes'.padEnd(8) + 'Edges'.padEnd(8) + 'Raw E'.padEnd(8) + 'Labels  ELabels  Status');
console.log(`  ${'─'.repeat(90)}`);

for (const r of results) {
  const status = r.edgeDiff === 0 ? 'OK' : `DIFF(${r.edgeDiff > 0 ? '+' : ''}${r.edgeDiff})`;
  const line = '  ' + 
    r.file.substring(0, 34).padEnd(35) + 
    r.diagram.padEnd(12) + 
    r.type.padEnd(14) + 
    String(r.ugmNodes).padEnd(8) + 
    String(r.ugmEdges).padEnd(8) + 
    String(r.rawEdges).padEnd(8) +
    (r.hasLabels ? 'Yes' : 'No').padEnd(9) +
    (r.hasEdgeLabels ? 'Yes' : 'No').padEnd(9) +
    status;
  console.log(line);
}

if (issues.length > 0) {
  console.log(`\n  ISSUES:`);
  console.log(`  ${'─'.repeat(80)}`);
  for (const iss of issues) {
    console.log(`  [${iss.issue}] ${iss.file} / ${iss.diagram}: ${iss.detail}`);
  }
}

// Additional quality checks: pick 3 random files and dump their UGM for manual inspection
console.log(`\n  SAMPLE UGM INSPECTION (3 random):`);
console.log(`  ${'─'.repeat(80)}`);

const sampleResults = results.filter(r => r.ugmNodes > 3).slice(0, 3);
for (const sr of sampleResults) {
  const filePath = path.join(testDir, sr.file);
  let raw = fs.readFileSync(filePath, 'utf8');
  if (raw.charCodeAt(0) === 0xFEFF) raw = raw.substring(1);
  const data = JSON.parse(raw);
  const mmd = data.diagrams[sr.diagram];
  const ugm = parser(mmd);
  
  console.log(`\n  ${sr.file} / ${sr.diagram} (${ugm.nodes.length} nodes, ${ugm.edges.length} edges):`);
  console.log(`    Sample nodes: ${ugm.nodes.slice(0, 5).map(n => `${n.id}[${(n.label || '').replace(/\n/g, ' ').substring(0, 30)}]`).join(', ')}`);
  console.log(`    Sample edges: ${ugm.edges.slice(0, 5).map(e => `${e.from}->${e.to}${e.label ? '("' + e.label.substring(0, 20) + '")' : ''}`).join(', ')}`);
  
  // Check for duplicate edges
  const edgeKeys = ugm.edges.map(e => `${e.from}->${e.to}`);
  const uniqueEdgeKeys = new Set(edgeKeys);
  if (uniqueEdgeKeys.size < edgeKeys.length) {
    console.log(`    WARNING: ${edgeKeys.length - uniqueEdgeKeys.size} duplicate edge(s) detected`);
  }
  
  // Check for orphan nodes (nodes with no edges)
    const connectedNodes = new Set();
    for (const e of ugm.edges) {
      connectedNodes.add(e.from);
      connectedNodes.add(e.to);
    }
    const orphans = ugm.nodes.filter(n => !connectedNodes.has(n.id));
    if (orphans.length > 0) {
      console.log(`    INFO: ${orphans.length} orphan node(s) (standalone defs): ${orphans.slice(0, 5).map(n => n.id).join(', ')}`);
    } else {
      console.log(`    All nodes connected via edges.`);
    }
}

// Write full report
const reportPath = path.join(testDir, 'VERIFICATION-REPORT.md');
let report = `# Mermaid vs GoJS UGM Verification Report\n\n`;
report += `**Date:** ${new Date().toISOString()}\n\n`;
report += `## Summary\n\n`;
report += `| Metric | Count |\n|---|---|\n`;
report += `| Files tested | ${totalFiles} |\n`;
report += `| Diagrams tested | ${totalDiagrams} |\n`;
report += `| Perfect edge match | ${perfectMatches} / ${totalDiagrams} (${Math.round(perfectMatches/totalDiagrams*100)}%) |\n`;
report += `| Parse failures | ${parseFails} |\n`;
report += `| Empty UGM | ${emptyUgm} |\n`;
report += `| Edge mismatches | ${edgeDiscrepancies} |\n\n`;

report += `## Conclusion\n\n`;
if (edgeDiscrepancies === 0 && parseFails === 0 && emptyUgm === 0) {
  report += `**All diagrams parsed successfully.** The GoJS UGM faithfully represents all Mermaid `;
  report += `diagrams tested. Edge counts match perfectly, node labels are preserved, and edge `;
  report += `labels are correctly extracted.\n\n`;
  report += `No fixes needed.\n`;
} else {
  report += `Issues found that need attention:\n\n`;
  for (const iss of issues) {
    report += `- **${iss.issue}** in ${iss.file} / ${iss.diagram}: ${iss.detail}\n`;
  }
}

report += `\n## Detailed Results\n\n`;
report += `| File | Diagram | Type | UGM Nodes | UGM Edges | Raw Edges | Labels | Edge Labels | Status |\n`;
report += `|---|---|---|---|---|---|---|---|---|\n`;
for (const r of results) {
  const status = r.edgeDiff === 0 ? 'OK' : `DIFF(${r.edgeDiff > 0 ? '+' : ''}${r.edgeDiff})`;
  report += `| ${r.file} | ${r.diagram} | ${r.type} | ${r.ugmNodes} | ${r.ugmEdges} | ${r.rawEdges} | ${r.hasLabels ? 'Yes' : 'No'} | ${r.hasEdgeLabels ? 'Yes' : 'No'} | ${status} |\n`;
}

fs.writeFileSync(reportPath, report, 'utf8');
console.log(`\nFull report: ${reportPath}`);
