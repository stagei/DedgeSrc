/**
 * AutoDoc Diagram Controls
 * Handles pan-zoom, fullscreen, and diagram switching functionality
 * This file is separate to avoid template placeholder collisions with [type]
 */

// Store diagram content and pan-zoom instances
const diagramContent = {};
const panZoomInstances = {};
let fullscreenPanZoom = null;
let currentFullscreenDiagramType = null;

// Theme management
function getPreferredTheme() {
  const stored = localStorage.getItem('autodoc-theme');
  if (stored) return stored;
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function setTheme(theme) {
  document.documentElement.setAttribute('data-theme', theme);
  localStorage.setItem('autodoc-theme', theme);
  updateThemeButtons(theme);
  // Re-render mermaid diagrams when theme changes
  if (typeof reRenderMermaid === 'function') {
    reRenderMermaid();
  }
  // Apply dark mode line styling
  applyDarkModeLineStyles();
  // Update GoJS diagrams theme
  if (window.autodocRenderer && typeof window.autodocRenderer.updateAllGoJSThemes === 'function') {
    window.autodocRenderer.updateAllGoJSThemes();
  }
}

// Apply bright blue lines in dark mode for better visibility
function applyDarkModeLineStyles() {
  const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
  const lineColor = isDark ? '#64b5f6' : '';
  const lineWidth = isDark ? '2px' : '';
  // For dark mode: make nodes dark with bright text for better visibility
  const brightText = isDark ? '#f5f5f5' : '';  // Bright text for all labels
  const darkNodeFill = isDark ? '#3a3a5c' : '';  // Dark node fill to match theme
  
  // Mermaid 11 flowchart edge paths - multiple selectors for compatibility
  const edgeSelectors = [
    'svg path.flowchart-link',
    'svg .edgePath path',
    'svg .edgePath path.path',
    'svg .edge-thickness-normal',
    'svg .edge-pattern-solid',
    'svg .transition',
    'svg .relation',
    'svg path[class*="flowchart"]',
    'svg path[style*="stroke-width"]'
  ];
  
  edgeSelectors.forEach(selector => {
    document.querySelectorAll(selector).forEach(path => {
      if (isDark) {
        path.style.stroke = lineColor;
        path.style.strokeWidth = lineWidth;
      } else {
        path.style.stroke = '';
        path.style.strokeWidth = '';
      }
    });
  });
  
  // Arrow markers and arrowheads
  const arrowSelectors = [
    'svg .arrowMarkerPath',
    'svg .arrowheadPath',
    'svg marker path',
    'svg .marker',
    'svg #arrowhead path',
    'svg [id*="arrowhead"] path',
    'svg [id*="arrow"] path'
  ];
  
  arrowSelectors.forEach(selector => {
    document.querySelectorAll(selector).forEach(arrow => {
      if (isDark) {
        arrow.style.stroke = lineColor;
        arrow.style.fill = lineColor;
      } else {
        arrow.style.stroke = '';
        arrow.style.fill = '';
      }
    });
  });
  
  // Node borders
  const nodeSelectors = [
    'svg .node rect',
    'svg .node polygon',
    'svg .node circle',
    'svg .node ellipse',
    'svg .basic.label-container',
    'svg .nodeLabel',
    'svg .cluster rect',
    'svg .cluster polygon'
  ];
  
  nodeSelectors.forEach(selector => {
    document.querySelectorAll(selector).forEach(node => {
      if (isDark) {
        node.style.stroke = lineColor;
        if (node.tagName === 'rect' || node.tagName === 'polygon' || node.tagName === 'circle' || node.tagName === 'ellipse') {
          node.style.setProperty('fill', darkNodeFill, 'important');
        }
      } else {
        node.style.stroke = '';
        node.style.fill = '';
      }
    });
  });
  
  // Also style ALL rect/polygon/circle elements that might be nodes (more aggressive)
  document.querySelectorAll('svg rect, svg polygon, svg circle, svg ellipse').forEach(shape => {
    // Skip markers, defs, and background elements
    if (!shape.closest('marker') && !shape.closest('defs') && !shape.classList.contains('background')) {
      if (isDark) {
        // Only apply to shapes that look like nodes (have stroke or are inside .node)
        const isNode = shape.closest('.node') || shape.closest('.basic') || 
                       shape.closest('.cluster') || shape.classList.contains('label-container');
        if (isNode) {
          shape.style.setProperty('fill', darkNodeFill, 'important');
          shape.style.stroke = lineColor;
        }
      } else {
        shape.style.removeProperty('fill');
        shape.style.stroke = '';
      }
    }
  });
  
  // ALL text should be bright in dark mode (since nodes are now dark)
  // Target ALL text elements
  document.querySelectorAll('svg text, svg tspan').forEach(text => {
    if (isDark) {
      text.style.setProperty('fill', brightText, 'important');
    } else {
      text.style.removeProperty('fill');
    }
  });
  
  // Target foreignObject HTML content (Mermaid uses this for labels)
  document.querySelectorAll('svg foreignObject, svg foreignObject *').forEach(elem => {
    if (isDark) {
      elem.style.setProperty('color', brightText, 'important');
    } else {
      elem.style.removeProperty('color');
    }
  });
  
  // Edge labels background
  document.querySelectorAll('svg .edgeLabel rect, svg .labelBkg').forEach(label => {
    if (isDark) {
      label.style.fill = '#2d2d4a';
      label.style.stroke = lineColor;
    } else {
      label.style.fill = '';
      label.style.stroke = '';
    }
  });
  
  // Sequence diagram lines
  document.querySelectorAll('svg .messageLine0, svg .messageLine1, svg .actor-line, svg .loopLine').forEach(line => {
    if (isDark) {
      line.style.stroke = lineColor;
      line.style.strokeWidth = '1.5px';
    } else {
      line.style.stroke = '';
      line.style.strokeWidth = '';
    }
  });
  
  // Class diagram specific
  document.querySelectorAll('svg .relation, svg .classGroup rect, svg .classGroup line').forEach(elem => {
    if (isDark) {
      elem.style.stroke = lineColor;
    } else {
      elem.style.stroke = '';
    }
  });
  
  console.log('Applied dark mode line styles, isDark:', isDark);
}

function updateThemeButtons(theme) {
  const lightBtn = document.getElementById('theme-light');
  const darkBtn = document.getElementById('theme-dark');
  if (lightBtn) lightBtn.classList.toggle('active', theme === 'light');
  if (darkBtn) darkBtn.classList.toggle('active', theme === 'dark');
}

// Diagram tab switching
function showDiagram(diagramType, btn) {
  document.querySelectorAll('.diagram-tab').forEach(t => t.classList.remove('active'));
  btn.classList.add('active');
  
  document.querySelectorAll('.diagram-content').forEach(c => c.classList.remove('active'));
  const contentEl = document.getElementById(diagramType + '-content');
  if (contentEl) contentEl.classList.add('active');
  
  // Initialize pan-zoom for the newly visible diagram if needed
  const container = document.getElementById(diagramType + '-container');
  if (container) {
    // If GoJS is active for this diagram, request an update
    if (window.autodocRenderer && window.autodocRenderer.isGoJSActive(diagramType)) {
      var goDiag = window.autodocRenderer.getActiveDiagram(diagramType);
      if (goDiag) goDiag.requestUpdate();
      return;
    }

    // Deferred GoJS render: if wrapper wasn't rendered at init (hidden tab), render now
    if (window.autodocRenderer && container.classList.contains('diagram-wrapper')) {
      var renderTarget = container.querySelector('.diagram-render-target');
      var mermaidSrc = container.querySelector('.mermaid-source');
      if (renderTarget && mermaidSrc && renderTarget.innerHTML.trim() === '') {
        var preferred = window.autodocRenderer.getPreferredRenderer();
        var forced = container.getAttribute('data-force-renderer');
        setTimeout(function () {
          window.autodocRenderer.renderDiagramEl(container, forced || preferred);
          // GoJS needs a visible container to calculate dimensions correctly.
          // Schedule zoomToFit after the diagram has had time to render.
          setTimeout(function () {
            var diag = window.autodocRenderer.getActiveDiagram(diagramType);
            if (diag && diag.div) { diag.requestUpdate(); diag.zoomToFit(); }
          }, 300);
        }, 50);
        return;
      }
    }
    const svg = container.querySelector('svg');
    if (svg) {
      // Apply fixes before initializing pan-zoom
      fixForeignObjectDimensions(svg);
      fixInvalidTransforms(svg);
      applyDarkModeLinesToSvg(svg);
      removeMermaidErrorDisplay(svg);
      
      // Delayed error removal to catch async Mermaid rendering
      setTimeout(function() { removeMermaidErrorDisplay(svg); }, 500);
      setTimeout(function() { removeMermaidErrorDisplay(svg); }, 1000);
      
      // Initialize or reinitialize pan-zoom
      if (!panZoomInstances[diagramType]) {
        initPanZoom(diagramType);
      } else {
        // Reset zoom/pan to show the full diagram
        try {
          panZoomInstances[diagramType].fit();
          panZoomInstances[diagramType].center();
        } catch(e) {}
      }
      
      // Delayed fit to ensure diagram is fully visible after rendering
      setTimeout(function() {
        if (panZoomInstances[diagramType]) {
          try {
            panZoomInstances[diagramType].fit();
            panZoomInstances[diagramType].center();
          } catch(e) {}
        }
      }, 300);
    }
  }
}

// Initialize svg-pan-zoom for a container
function initPanZoom(diagramType) {
  const container = document.getElementById(diagramType + '-container');
  if (!container) return null;
  
  const svgElement = container.querySelector('svg');
  if (!svgElement) return null;

  // Destroy existing instance if any
  if (panZoomInstances[diagramType]) {
    try { panZoomInstances[diagramType].destroy(); } catch(e) {}
    delete panZoomInstances[diagramType];
  }

  // Ensure SVG has an ID
  if (!svgElement.getAttribute('id')) {
    svgElement.setAttribute('id', 'svg-' + diagramType);
  }

  // Make SVG fill container
  svgElement.style.width = '100%';
  svgElement.style.height = '100%';
  svgElement.style.maxWidth = 'none';
  
  // Fix viewBox if missing or invalid - Mermaid sometimes doesn't set it properly
  try {
    const existingViewBox = svgElement.getAttribute('viewBox');
    if (!existingViewBox || existingViewBox.includes('NaN') || existingViewBox.includes('undefined')) {
      // Get the bounding box of the SVG content
      const bbox = svgElement.getBBox();
      if (bbox && bbox.width > 0 && bbox.height > 0) {
        // Add padding around the content
        const padding = 20;
        const viewBoxStr = `${bbox.x - padding} ${bbox.y - padding} ${bbox.width + padding * 2} ${bbox.height + padding * 2}`;
        svgElement.setAttribute('viewBox', viewBoxStr);
        console.log(`Set viewBox for ${diagramType}: ${viewBoxStr}`);
      }
    }
  } catch(e) {
    console.warn('Could not calculate viewBox:', e);
  }

  try {
    panZoomInstances[diagramType] = svgPanZoom(svgElement, {
      zoomEnabled: true,
      controlIconsEnabled: false,
      fit: true,
      center: true,
      minZoom: 0.1,
      maxZoom: 20,
      zoomScaleSensitivity: 0.3,
      onZoom: function(level) {
        updateZoomIndicator(diagramType, level);
      }
    });
    updateZoomIndicator(diagramType, panZoomInstances[diagramType].getZoom());
    return panZoomInstances[diagramType];
  } catch(e) {
    console.error('Error initializing pan-zoom:', e);
    return null;
  }
}

function updateZoomIndicator(diagramType, level) {
  const indicator = document.getElementById(diagramType + '-zoom');
  if (indicator) {
    indicator.textContent = Math.round(level * 100) + '%';
  }
}

// Zoom controls -- branch on active renderer
function zoomIn(diagramType) {
  if (window.autodocRenderer && window.autodocRenderer.isGoJSActive(diagramType)) {
    window.autodocRenderer.goJSZoomIn(diagramType);
    var zoomEl = document.getElementById(diagramType + '-zoom');
    if (zoomEl) zoomEl.textContent = window.autodocRenderer.goJSGetZoomPercent(diagramType) + '%';
    return;
  }
  if (panZoomInstances[diagramType]) {
    panZoomInstances[diagramType].zoomIn();
  }
}

function zoomOut(diagramType) {
  if (window.autodocRenderer && window.autodocRenderer.isGoJSActive(diagramType)) {
    window.autodocRenderer.goJSZoomOut(diagramType);
    var zoomEl = document.getElementById(diagramType + '-zoom');
    if (zoomEl) zoomEl.textContent = window.autodocRenderer.goJSGetZoomPercent(diagramType) + '%';
    return;
  }
  if (panZoomInstances[diagramType]) {
    panZoomInstances[diagramType].zoomOut();
  }
}

function resetZoom(diagramType) {
  if (window.autodocRenderer && window.autodocRenderer.isGoJSActive(diagramType)) {
    window.autodocRenderer.goJSZoomReset(diagramType);
    var zoomEl = document.getElementById(diagramType + '-zoom');
    if (zoomEl) zoomEl.textContent = window.autodocRenderer.goJSGetZoomPercent(diagramType) + '%';
    return;
  }
  if (panZoomInstances[diagramType]) {
    panZoomInstances[diagramType].resetZoom();
    panZoomInstances[diagramType].center();
  }
}

function fitToScreen(diagramType) {
  if (window.autodocRenderer && window.autodocRenderer.isGoJSActive(diagramType)) {
    window.autodocRenderer.goJSZoomFit(diagramType);
    var zoomEl = document.getElementById(diagramType + '-zoom');
    if (zoomEl) zoomEl.textContent = window.autodocRenderer.goJSGetZoomPercent(diagramType) + '%';
    return;
  }
  if (panZoomInstances[diagramType]) {
    panZoomInstances[diagramType].fit();
    panZoomInstances[diagramType].center();
  }
}

// Fit the currently active diagram to view
function fitActiveDiagram() {
  const activeContent = document.querySelector('.diagram-content.active');
  if (activeContent) {
    const containerId = activeContent.id.replace('-content', '');
    if (panZoomInstances[containerId]) {
      panZoomInstances[containerId].fit();
      panZoomInstances[containerId].center();
    }
  }
}

// Diagram name mapping for titles
const diagramTypeNames = {
  'flow': 'Flow Diagram',
  'sequence': 'Sequence Diagram',
  'class': 'Class Diagram',
  'namespace': 'Namespace Diagram',
  'rest': 'REST API Diagram',
  'process': 'Process Diagram',
  'ecosystem': 'Ecosystem Diagram',
  'project': 'Project Diagram',
  'execution': 'Execution Diagram',
  'er': 'ER Diagram'
};

var diagramI18nKeys = {
  'flow': 'diagram.flow',
  'sequence': 'diagram.sequence',
  'class': 'diagram.class',
  'namespace': 'diagram.namespace',
  'rest': 'diagram.rest',
  'process': 'diagram.process',
  'ecosystem': 'diagram.ecosystem',
  'project': 'diagram.project',
  'execution': 'diagram.execution',
  'er': 'diagram.er'
};

function _dt(key, fallback) {
  if (typeof DedgeAuth !== 'undefined' && typeof DedgeAuth.t === 'function') {
    return DedgeAuth.t(key, fallback);
  }
  return fallback;
}

function getDiagramTitle(diagramType) {
  var key = diagramI18nKeys[diagramType];
  if (key) return _dt(key, diagramTypeNames[diagramType] || diagramType);
  return diagramTypeNames[diagramType] || diagramType;
}

// Open diagram in new window (diagram only, no info panel)
function openInNewWindow(diagramType) {
  if (window.autodocRenderer && window.autodocRenderer.isGoJSActive(diagramType)) {
    var diagram = window.autodocRenderer.getActiveDiagram(diagramType);
    if (diagram) {
      var svgData = diagram.makeSvg({ scale: 1, background: 'transparent' });
      if (svgData) {
        const goSvgContent = new XMLSerializer().serializeToString(svgData);
        const goTitle = document.title + ' - ' + getDiagramTitle(diagramType) + ' (GoJS)';
        const goWindow = window.open('', '_blank');
        goWindow.document.write('<!DOCTYPE html><html><head><title>' + goTitle + '</title></head><body style="margin:0;background:#0f1117;">' + goSvgContent + '</body></html>');
        goWindow.document.close();
      }
    }
    return;
  }
  const container = document.getElementById(diagramType + '-container');
  if (!container) return;
  
  const svg = container.querySelector('svg');
  if (!svg) return;

  const svgContent = svg.outerHTML;
  const theme = document.documentElement.getAttribute('data-theme');
  const title = document.title + ' - ' + getDiagramTitle(diagramType);
  
  const newWindow = window.open('', '_blank');
  newWindow.document.write(`
<!DOCTYPE html>
<html lang="en" data-theme="${theme}">
<head>
  <meta charset="utf-8">
  <title>${title}</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.1/font/bootstrap-icons.css" rel="stylesheet">
  <script src="https://cdn.jsdelivr.net/npm/svg-pan-zoom@3.6.1/dist/svg-pan-zoom.min.js"><\/script>
  <style>
    :root {
      --bg-primary: #f8fafc;
      --bg-secondary: #e2e8f0;
      --bg-card: #ffffff;
      --text-primary: #0f172a;
      --text-secondary: #475569;
      --border-color: #cbd5e1;
      --accent-primary: #0891b2;
    }
    [data-theme="dark"] {
      --bg-primary: #0f1419;
      --bg-secondary: #1a1f2e;
      --bg-card: #1e2433;
      --text-primary: #e6edf3;
      --text-secondary: #8b949e;
      --border-color: #30363d;
      --accent-primary: #58a6ff;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { 
      font-family: 'Outfit', sans-serif; 
      background: var(--bg-primary); 
      color: var(--text-primary); 
      display: flex; 
      flex-direction: column; 
      height: 100vh; 
    }
    .toolbar { 
      display: flex; 
      gap: 0.5rem; 
      padding: 0.75rem 1rem; 
      background: var(--bg-secondary); 
      border-bottom: 1px solid var(--border-color); 
      align-items: center; 
    }
    .toolbar-title { font-weight: 600; flex: 1; }
    .btn { 
      display: inline-flex; 
      align-items: center; 
      justify-content: center; 
      width: 36px; 
      height: 36px; 
      background: var(--bg-card); 
      border: 1px solid var(--border-color); 
      border-radius: 6px; 
      color: var(--text-secondary); 
      cursor: pointer; 
      font-size: 1rem; 
      transition: all 0.2s ease; 
    }
    .btn:hover { 
      background: var(--accent-primary); 
      border-color: var(--accent-primary); 
      color: var(--bg-primary); 
    }
    .btn-group { display: flex; gap: 0; }
    .btn-group .btn { border-radius: 0; }
    .btn-group .btn:first-child { border-radius: 6px 0 0 6px; }
    .btn-group .btn:last-child { border-radius: 0 6px 6px 0; }
    .btn-group .btn:not(:first-child) { margin-left: -1px; }
    .zoom-indicator { 
      font-size: 0.75rem; 
      color: var(--text-secondary); 
      padding: 0 0.5rem; 
      min-width: 50px; 
      text-align: center; 
    }
    .diagram-area { 
      flex: 1; 
      overflow: hidden; 
      display: flex; 
      align-items: center; 
      justify-content: center; 
    }
    .diagram-area svg { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div class="toolbar">
    <span class="toolbar-title">${title}</span>
    <div class="btn-group">
      <button class="btn" onclick="pz.zoomIn()" title="${_dt('diagram.zoomIn', 'Zoom In')}"><i class="bi bi-zoom-in"></i></button>
      <button class="btn" onclick="pz.zoomOut()" title="${_dt('diagram.zoomOut', 'Zoom Out')}"><i class="bi bi-zoom-out"></i></button>
      <button class="btn" onclick="pz.resetZoom(); pz.center();" title="${_dt('diagram.resetZoom', 'Reset')}"><i class="bi bi-arrows-angle-contract"></i></button>
    </div>
    <span class="zoom-indicator" id="zoom">100%</span>
    <button class="btn" onclick="pz.fit(); pz.center();" title="${_dt('diagram.fitToScreen', 'Fit')}"><i class="bi bi-arrows-fullscreen"></i></button>
  </div>
  <div class="diagram-area" id="diagram">${svgContent}</div>
  <script>
    let pz;
    document.addEventListener('DOMContentLoaded', function() {
      const svg = document.querySelector('#diagram svg');
      if (svg) {
        svg.style.width = '100%'; 
        svg.style.height = '100%';
        pz = svgPanZoom(svg, { 
          zoomEnabled: true, 
          controlIconsEnabled: false, 
          fit: true, 
          center: true, 
          minZoom: 0.1, 
          maxZoom: 20, 
          zoomScaleSensitivity: 0.3,
          onZoom: function(level) { 
            document.getElementById('zoom').textContent = Math.round(level * 100) + '%'; 
          }
        });
      }
    });
  <\/script>
</body>
</html>
  `);
  newWindow.document.close();
}

// Apply dark mode styles to a specific SVG element (used for fullscreen clones)
function applyDarkModeLinesToSvg(svgElement) {
  if (!svgElement) return;
  
  const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
  const lineColor = isDark ? '#64b5f6' : '';
  const lineWidth = isDark ? '2px' : '';
  const brightText = isDark ? '#f5f5f5' : '';
  const darkNodeFill = isDark ? '#3a3a5c' : '';
  
  // Edge paths
  const edgeSelectors = [
    'path.flowchart-link', '.edgePath path', '.edge-thickness-normal',
    '.edge-pattern-solid', '.transition', '.relation', 'path[class*="flowchart"]'
  ];
  edgeSelectors.forEach(selector => {
    svgElement.querySelectorAll(selector).forEach(path => {
      if (isDark) {
        path.style.stroke = lineColor;
        path.style.strokeWidth = lineWidth;
      } else {
        path.style.stroke = '';
        path.style.strokeWidth = '';
      }
    });
  });
  
  // Arrow markers
  const arrowSelectors = ['.arrowMarkerPath', '.arrowheadPath', 'marker path', '[id*="arrow"] path'];
  arrowSelectors.forEach(selector => {
    svgElement.querySelectorAll(selector).forEach(arrow => {
      if (isDark) {
        arrow.style.stroke = lineColor;
        arrow.style.fill = lineColor;
      } else {
        arrow.style.stroke = '';
        arrow.style.fill = '';
      }
    });
  });
  
  // Node shapes - apply dark fill
  svgElement.querySelectorAll('rect, polygon, circle, ellipse').forEach(shape => {
    if (!shape.closest('marker') && !shape.closest('defs') && !shape.classList.contains('background')) {
      const isNode = shape.closest('.node') || shape.closest('.basic') || 
                     shape.closest('.cluster') || shape.classList.contains('label-container');
      if (isNode) {
        if (isDark) {
          shape.style.setProperty('fill', darkNodeFill, 'important');
          shape.style.stroke = lineColor;
        } else {
          shape.style.removeProperty('fill');
          shape.style.stroke = '';
        }
      }
    }
  });
  
  // All text should be bright in dark mode
  svgElement.querySelectorAll('text, tspan').forEach(text => {
    if (isDark) {
      text.style.setProperty('fill', brightText, 'important');
    } else {
      text.style.removeProperty('fill');
    }
  });
  
  // ForeignObject content (Mermaid labels)
  svgElement.querySelectorAll('foreignObject, foreignObject *').forEach(elem => {
    if (isDark) {
      elem.style.setProperty('color', brightText, 'important');
    } else {
      elem.style.removeProperty('color');
    }
  });
  
  // Edge labels
  svgElement.querySelectorAll('.edgeLabel rect, .labelBkg').forEach(label => {
    if (isDark) {
      label.style.fill = '#2d2d4a';
      label.style.stroke = lineColor;
    } else {
      label.style.fill = '';
      label.style.stroke = '';
    }
  });
  
  console.log('Applied dark mode styles to fullscreen SVG, isDark:', isDark);
}

// Fix foreignObject dimensions (Mermaid 11 sometimes has 0x0 foreignObjects)
// This must be called AFTER the SVG is added to the DOM
function fixForeignObjectDimensions(svgElement) {
  if (!svgElement) return;
  
  const fos = svgElement.querySelectorAll('foreignObject');
  fos.forEach((fo) => {
    const width = parseFloat(fo.getAttribute('width') || '0');
    const height = parseFloat(fo.getAttribute('height') || '0');
    
    // If dimensions are 0 or too small, force visible dimensions
    if (width < 10 || height < 10) {
      // Force dimensions - generous to ensure content is visible
      fo.setAttribute('width', '300');
      fo.setAttribute('height', '50');
      fo.style.overflow = 'visible';
      
      // Style the inner content for visibility
      const innerElements = fo.querySelectorAll('div, span, p');
      innerElements.forEach(el => {
        el.style.overflow = 'visible';
        el.style.width = 'auto';
        el.style.height = 'auto';
        el.style.whiteSpace = 'nowrap';
      });
    }
  });
  
  console.log('Fixed foreignObject dimensions for', fos.length, 'elements');
}

// Toggle fullscreen mode
function toggleFullscreen(diagramType) {
  const overlay = document.getElementById('fullscreen-overlay');
  const content = document.getElementById('fullscreen-content');
  const title = document.getElementById('fullscreen-title');
  const container = document.getElementById(diagramType + '-container');
  
  if (!overlay || !content || !container) return;

  if (window.autodocRenderer && window.autodocRenderer.isGoJSActive(diagramType)) {
    var diagram = window.autodocRenderer.getActiveDiagram(diagramType);
    if (diagram) {
      currentFullscreenDiagramType = diagramType;
      if (title) title.textContent = getDiagramTitle(diagramType) + ' (GoJS)';
      var svgData = diagram.makeSvg({ scale: 1, background: 'transparent' });
      if (svgData) {
        content.innerHTML = '';
        svgData.style.width = '100%';
        svgData.style.height = '100%';
        content.appendChild(svgData);
        overlay.classList.add('active');
        document.body.style.overflow = 'hidden';
        setTimeout(function() {
          if (fullscreenPanZoom) { try { fullscreenPanZoom.destroy(); } catch(e) {} }
          try {
            fullscreenPanZoom = svgPanZoom(svgData, {
              zoomEnabled: true, controlIconsEnabled: false, fit: true, center: true,
              minZoom: 0.1, maxZoom: 20, zoomScaleSensitivity: 0.3,
              onZoom: function(level) { var z = document.getElementById('fullscreen-zoom'); if (z) z.textContent = Math.round(level * 100) + '%'; }
            });
          } catch(e) { console.error('GoJS fullscreen pan-zoom error:', e); }
        }, 100);
      }
    }
    return;
  }
  
  const svg = container.querySelector('svg');
  if (!svg) return;
  
  currentFullscreenDiagramType = diagramType;
  if (title) title.textContent = getDiagramTitle(diagramType);
  
  // Clone SVG to fullscreen
  const svgClone = svg.cloneNode(true);
  svgClone.id = 'fullscreen-svg';
  svgClone.style.width = '100%';
  svgClone.style.height = '100%';
  svgClone.style.maxWidth = 'none';
  
  content.innerHTML = '';
  content.appendChild(svgClone);
  
  // Fix foreignObject dimensions AFTER adding to DOM (required for Mermaid 11)
  fixForeignObjectDimensions(svgClone);
  
  // Apply dark mode styles to the cloned SVG
  applyDarkModeLinesToSvg(svgClone);
  
  overlay.classList.add('active');
  document.body.style.overflow = 'hidden';
  
  // Initialize pan-zoom on fullscreen SVG
  setTimeout(function() {
    if (fullscreenPanZoom) {
      try { fullscreenPanZoom.destroy(); } catch(e) {}
    }
    try {
      fullscreenPanZoom = svgPanZoom(svgClone, {
        zoomEnabled: true,
        controlIconsEnabled: false,
        fit: true,
        center: true,
        minZoom: 0.1,
        maxZoom: 20,
        zoomScaleSensitivity: 0.3,
        onZoom: function(level) {
          const zoomEl = document.getElementById('fullscreen-zoom');
          if (zoomEl) zoomEl.textContent = Math.round(level * 100) + '%';
        }
      });
      // Update zoom indicator with initial zoom level
      const zoomEl = document.getElementById('fullscreen-zoom');
      if (zoomEl && fullscreenPanZoom) {
        zoomEl.textContent = Math.round(fullscreenPanZoom.getZoom() * 100) + '%';
      }
      // Re-apply dark mode styles after pan-zoom init (it may reset some styles)
      setTimeout(function() { applyDarkModeLinesToSvg(svgClone); }, 50);
    } catch(e) {
      console.error('Error initializing fullscreen pan-zoom:', e);
    }
  }, 100);
}

function closeFullscreen() {
  const overlay = document.getElementById('fullscreen-overlay');
  if (overlay) overlay.classList.remove('active');
  document.body.style.overflow = '';
  
  if (fullscreenPanZoom) {
    try { fullscreenPanZoom.destroy(); } catch(e) {}
    fullscreenPanZoom = null;
  }
  currentFullscreenDiagramType = null;
}

// Fullscreen zoom controls
function zoomInFullscreen() {
  if (fullscreenPanZoom) fullscreenPanZoom.zoomIn();
}

function zoomOutFullscreen() {
  if (fullscreenPanZoom) fullscreenPanZoom.zoomOut();
}

function resetZoomFullscreen() {
  if (fullscreenPanZoom) {
    fullscreenPanZoom.resetZoom();
    fullscreenPanZoom.center();
  }
}

function fitToScreenFullscreen() {
  if (fullscreenPanZoom) {
    fullscreenPanZoom.fit();
    fullscreenPanZoom.center();
  }
}

// Fix foreignObject dimensions for all SVGs on the page
// Mermaid 11 often renders foreignObject elements with 0x0 dimensions
function fixAllForeignObjects() {
  document.querySelectorAll('svg').forEach(function(svg) {
    fixForeignObjectDimensions(svg);
    fixInvalidTransforms(svg);
    removeMermaidErrorDisplay(svg);
  });
}

// Remove Mermaid "Syntax error in text" overlays
// Mermaid v11.12.x sometimes shows false-positive syntax errors even when diagrams render correctly
// All AutoDoc diagrams pass mmdc CLI validation, so these errors are cosmetic browser rendering artifacts
function removeMermaidErrorDisplay(svgElement) {
  if (!svgElement) return;
  
  // Remove error icon and error text elements inside SVG
  const errorSelectors = [
    '.error-icon',
    '.error-text',
    'g.error-icon',
    'g.error-text',
    '[class*="error-"]'
  ];
  
  errorSelectors.forEach(selector => {
    svgElement.querySelectorAll(selector).forEach(elem => {
      elem.remove();
    });
  });
  
  // Mermaid creates error display as g elements containing text with "Syntax error"
  // These are inside the SVG as sibling g elements to the main diagram content
  svgElement.querySelectorAll('g').forEach(g => {
    const text = g.textContent || '';
    if (text.includes('Syntax error') || text.includes('mermaid version')) {
      g.style.display = 'none';
      g.style.visibility = 'hidden';
      g.style.opacity = '0';
      // Also try removing it
      try { g.remove(); } catch(e) {}
    }
  });
  
  // Also check foreignObject elements which Mermaid uses for HTML content
  svgElement.querySelectorAll('foreignObject').forEach(fo => {
    const text = fo.textContent || '';
    if (text.includes('Syntax error') || text.includes('mermaid version')) {
      fo.style.display = 'none';
      fo.style.visibility = 'hidden';
      try { fo.remove(); } catch(e) {}
    }
  });
}

// Fix invalid transforms caused by Mermaid layout calculation errors
// Mermaid 11 sometimes produces translate(undefined, NaN) which breaks rendering
function fixInvalidTransforms(svgElement) {
  if (!svgElement) return;
  
  const gs = svgElement.querySelectorAll('g[transform]');
  gs.forEach(function(g) {
    const transform = g.getAttribute('transform');
    if (transform && (transform.includes('undefined') || transform.includes('NaN'))) {
      // Replace invalid transform with identity transform
      g.setAttribute('transform', 'translate(0, 0)');
      console.log('Fixed invalid transform:', transform);
    }
  });
  
  // Set viewBox if missing to ensure proper display
  if (!svgElement.getAttribute('viewBox')) {
    try {
      const bbox = svgElement.getBBox();
      if (bbox.width > 0 && bbox.height > 0) {
        svgElement.setAttribute('viewBox', 
          `${bbox.x - 20} ${bbox.y - 20} ${bbox.width + 40} ${bbox.height + 40}`);
      }
    } catch (e) {
      // getBBox may fail on hidden elements
    }
  }
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
  // Preserve original Mermaid source text so hidden-tab re-renders can restore it.
  // Mermaid replaces <pre> content with <svg>, which otherwise leaves nothing to re-run.
  document.querySelectorAll('pre.mermaid').forEach(function(el) {
    if (!el.dataset.mermaidSource) {
      var src = (el.textContent || '').trim();
      if (src.length > 0) {
        el.dataset.mermaidSource = src;
      }
    }
  });

  // Set initial theme
  const theme = getPreferredTheme();
  setTheme(theme);
  
  // Listen for system theme changes
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function(e) {
    if (!localStorage.getItem('autodoc-theme')) {
      setTheme(e.matches ? 'dark' : 'light');
    }
  });
  
  // Initialize pan-zoom for the first visible diagram
  setTimeout(function() {
    const activeContent = document.querySelector('.diagram-content.active');
    if (activeContent) {
      const containerId = activeContent.id.replace('-content', '');
      initPanZoom(containerId);
      // Explicit fit after initialization
      fitToScreen(containerId);
    }
    // Apply dark mode line styles and fix foreignObject dimensions after Mermaid renders
    applyDarkModeLineStyles();
    fixAllForeignObjects();
  }, 500);
  
  // Retry applying styles, fixes, and fit to catch async Mermaid rendering
  setTimeout(function() { 
    applyDarkModeLineStyles(); 
    fixAllForeignObjects();
    fitActiveDiagram();
  }, 1000);
  setTimeout(function() { 
    applyDarkModeLineStyles(); 
    fixAllForeignObjects();
    fitActiveDiagram();
  }, 2000);
  setTimeout(function() { 
    applyDarkModeLineStyles(); 
    fixAllForeignObjects();
    fitActiveDiagram();
  }, 3000);
  
  // Watch for Mermaid SVG changes and reapply styles + fix dimensions + fit
  // Re-entrancy guard: prevent infinite loop where style changes trigger observer
  let isApplyingFixes = false;
  const observer = new MutationObserver(function(mutations) {
    if (isApplyingFixes) return;
    let hasSvgChange = false;
    mutations.forEach(function(mutation) {
      if (mutation.addedNodes.length) {
        mutation.addedNodes.forEach(function(node) {
          if (node.nodeName === 'svg' || (node.querySelector && node.querySelector('svg'))) {
            hasSvgChange = true;
          }
        });
      }
    });
    if (hasSvgChange) {
      isApplyingFixes = true;
      setTimeout(function() {
        applyDarkModeLineStyles();
        fixAllForeignObjects();
        fitActiveDiagram();
        // Release guard after a short delay to let DOM settle
        setTimeout(function() { isApplyingFixes = false; }, 200);
      }, 100);
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });
  
  // Close fullscreen on Escape
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
      closeFullscreen();
    }
  });

  // Re-render Mermaid diagrams when Bootstrap tabs become visible.
  // Mermaid renders to 0 dimensions inside hidden tab panes (display:none).
  document.querySelectorAll('[data-bs-toggle="tab"]').forEach(function(tabEl) {
    tabEl.addEventListener('shown.bs.tab', function(event) {
      var targetId = event.target.getAttribute('data-bs-target');
      if (!targetId) return;
      var pane = document.querySelector(targetId);
      if (!pane) return;

      var mermaidEls = pane.querySelectorAll('pre.mermaid');
      if (mermaidEls.length === 0) return;

      var needsRender = [];
      mermaidEls.forEach(function(el) {
        var svg = el.querySelector('svg');
        if (!svg || svg.getBoundingClientRect().height < 10) {
          var currentSrc = (el.textContent || '').trim();
          if (!el.dataset.mermaidSource && currentSrc.length > 0) {
            el.dataset.mermaidSource = currentSrc;
          }

          if (svg) svg.remove();

          // If Mermaid already consumed text content, restore from preserved source.
          if ((el.textContent || '').trim().length === 0 && el.dataset.mermaidSource) {
            el.textContent = el.dataset.mermaidSource;
          }

          el.removeAttribute('data-processed');
          needsRender.push(el);
        }
      });

      if (needsRender.length === 0) return;
      if (window.mermaidInstance && typeof window.mermaidInstance.run === 'function') {
        window.mermaidInstance.run({ nodes: needsRender }).then(function() {
          setTimeout(function() {
            applyDarkModeLineStyles();
            fixAllForeignObjects();
          }, 300);
        }).catch(function(err) {
          // Keep UI resilient and preserve text source for next retry.
          console.warn('Mermaid tab re-render failed:', err);
        });
      }
    });
  });
});
