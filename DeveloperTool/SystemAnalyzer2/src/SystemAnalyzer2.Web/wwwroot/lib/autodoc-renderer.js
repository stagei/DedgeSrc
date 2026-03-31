/**
 * AutoDoc Dual Renderer: Mermaid / GoJS
 * Parses machine-generated Mermaid text into a Universal Graph Model (UGM),
 * then dispatches to either Mermaid or GoJS renderer.
 */
(function () {
  'use strict';

  const RENDERER_KEY = 'autodoc-diagram-renderer';
  const MAX_NODES = window.MERMAID_MAX_NODES || 500;

  var DARK_NODE_COLORS = {
    stadium:       { fill: '#1e3a5f', stroke: '#4f8cff', text: '#c8ddf8' },
    circle:        { fill: '#1a3a2e', stroke: '#34d399', text: '#b8edd8' },
    rounded:       { fill: '#2a2d35', stroke: '#8b95a8', text: '#d0d4dc' },
    cylinder:      { fill: '#2a2544', stroke: '#a78bfa', text: '#d4c8f8' },
    parallelogram: { fill: '#3a2a1a', stroke: '#fb923c', text: '#f0d0a8' },
    rectangle:     { fill: '#252830', stroke: '#8b95a8', text: '#d0d4dc' },
    hexagon:       { fill: '#1a3a2e', stroke: '#34d399', text: '#b8edd8' },
    subroutine:    { fill: '#2a1f44', stroke: '#8b5cf6', text: '#cbb8f8' },
    database:      { fill: '#2a2544', stroke: '#a78bfa', text: '#d4c8f8' },
    doubleBracket: { fill: '#1e3a5f', stroke: '#4f8cff', text: '#c8ddf8' }
  };

  var LIGHT_NODE_COLORS = {
    stadium:       { fill: '#dbeafe', stroke: '#3b82f6', text: '#1e3a5f' },
    circle:        { fill: '#d1fae5', stroke: '#10b981', text: '#064e3b' },
    rounded:       { fill: '#e2e8f0', stroke: '#64748b', text: '#1e293b' },
    cylinder:      { fill: '#ede9fe', stroke: '#8b5cf6', text: '#3b1f7a' },
    parallelogram: { fill: '#ffedd5', stroke: '#f97316', text: '#7c2d12' },
    rectangle:     { fill: '#f1f5f9', stroke: '#94a3b8', text: '#1e293b' },
    hexagon:       { fill: '#d1fae5', stroke: '#10b981', text: '#064e3b' },
    subroutine:    { fill: '#ede9fe', stroke: '#7c3aed', text: '#3b1f7a' },
    database:      { fill: '#ede9fe', stroke: '#8b5cf6', text: '#3b1f7a' },
    doubleBracket: { fill: '#dbeafe', stroke: '#3b82f6', text: '#1e3a5f' }
  };

  var DARK_THEME = {
    bg: '#0f1117', text: '#e2e4ea', linkLabelBg: '#242838',
    linkLabelText: '#b0b6c8', linkStroke: '#5a6280', border: '#2e3348'
  };

  var LIGHT_THEME = {
    bg: '#ffffff', text: '#1a1a2e', linkLabelBg: '#f0f0f5',
    linkLabelText: '#555555', linkStroke: '#94a3b8', border: '#d0d0d8'
  };

  function getNodeColors() {
    return isDarkMode() ? DARK_NODE_COLORS : LIGHT_NODE_COLORS;
  }

  const DIRECTION_MAP = { TD: 90, TB: 90, LR: 0, RL: 180, BT: 270 };

  const SHAPE_TO_FIGURE = {
    stadium: 'RoundedRectangle', circle: 'Circle', rounded: 'RoundedRectangle',
    cylinder: 'Database', parallelogram: 'Document', rectangle: 'Rectangle',
    hexagon: 'Hexagon2', subroutine: 'RoundedRectangle', database: 'Database',
    doubleBracket: 'RoundedRectangle'
  };

  var LAYOUT_KEY = 'autodoc-diagram-layout';
  var activeDiagrams = {};

  var LAYOUT_CONFIGS = {
    layeredTD: function (nodeCount) {
      return new go.LayeredDigraphLayout({ direction: 90, layerSpacing: 50, columnSpacing: 30, setsPortSpots: false });
    },
    layeredLR: function (nodeCount) {
      return new go.LayeredDigraphLayout({ direction: 0, layerSpacing: 60, columnSpacing: 30, setsPortSpots: false });
    },
    force: function (nodeCount) {
      var iter = nodeCount > 500 ? 20 : nodeCount > 200 ? 50 : 200;
      var spring = nodeCount > 500 ? 40 : 60;
      return new go.ForceDirectedLayout({ maxIterations: iter, defaultSpringLength: spring, epsilonDistance: 1 });
    },
    tree: function (nodeCount) {
      return new go.TreeLayout({ angle: 90, layerSpacing: 80, nodeSpacing: 25 });
    },
    circular: function (nodeCount) {
      return new go.CircularLayout({ spacing: 40 });
    },
    grid: function (nodeCount) {
      var wrap = Math.max(800, Math.ceil(Math.sqrt(nodeCount)) * 180);
      return new go.GridLayout({ wrappingWidth: wrap, cellSize: new go.Size(1, 1), spacing: new go.Size(10, 10) });
    }
  };

  function getPreferredRenderer() {
    return localStorage.getItem(RENDERER_KEY) || window.DEFAULT_RENDERER || 'mermaid';
  }

  function setPreferredRenderer(v) {
    localStorage.setItem(RENDERER_KEY, v);
  }

  function getPreferredLayout() {
    return localStorage.getItem(LAYOUT_KEY) || 'layeredTD';
  }

  function setPreferredLayout(v) {
    localStorage.setItem(LAYOUT_KEY, v);
  }

  function updateLayoutVisibility(renderer) {
    document.querySelectorAll('.diagram-layout-select').forEach(function (sel) {
      sel.style.display = renderer === 'gojs' ? '' : 'none';
    });
    document.querySelectorAll('.diagram-layout-label').forEach(function (el) {
      el.style.display = renderer === 'gojs' ? '' : 'none';
    });
  }

  function isDarkMode() {
    return document.documentElement.getAttribute('data-theme') === 'dark';
  }

  function getTheme() {
    return isDarkMode() ? DARK_THEME : LIGHT_THEME;
  }

  function shadeColor(color, percent) {
    const num = parseInt(color.replace('#', ''), 16);
    const amt = Math.round(2.55 * percent);
    const R = Math.max(0, Math.min(255, (num >> 16) + amt));
    const G = Math.max(0, Math.min(255, (num >> 8 & 0x00FF) + amt));
    const B = Math.max(0, Math.min(255, (num & 0x0000FF) + amt));
    return '#' + (0x1000000 + R * 0x10000 + G * 0x100 + B).toString(16).slice(1);
  }

  // ── Mermaid Text Parser ──────────────────────────────────────────────

  /*
   * Node shape patterns (ordered most-specific first to avoid ambiguity):
   *   id[["label"]]  or  id[[label]]    → stadium / doubleBracket
   *   id(("label"))  or  id((label))    → circle
   *   id{{"label"}}  or  id{{label}}    → hexagon
   *   id(["label"])  or  id([label])    → subroutine
   *   id[("label")]  or  id[(label)]    → cylinder (database)
   *   id[/"label"/]  or  id[/label/]    → parallelogram (file)
   *   id("label")    or  id(label)      → rounded
   *   id["label"]    or  id[label]      → rectangle
   */
  const NODE_PATTERNS = [
    { re: /\[\["?([^\]"]*)"?\]\]/, shape: 'stadium' },
    { re: /\(\("?([^)"]*)"?\)\)/, shape: 'circle' },
    { re: /\{\{"?([^}"]*)"?\}\}/, shape: 'hexagon' },
    { re: /\(\["?([^\]"]*)"?\]\)/, shape: 'subroutine' },
    { re: /\[\("?([^)"]*)"?\)\]/, shape: 'cylinder' },
    { re: /\[\/"?([^\/"]*)"?\/\]/, shape: 'parallelogram' },
    { re: /\("?([^)"]*)"?\)/, shape: 'rounded' },
    { re: /\["?([^\]"]*)"?\]/, shape: 'rectangle' }
  ];

  function parseNodeDef(text) {
    const trimmed = text.trim();
    // Match: nodeId + shape
    // nodeId can contain word chars, dots, hyphens, colons
    const idMatch = trimmed.match(/^([\w.\-:]+)/);
    if (!idMatch) return null;
    const id = idMatch[1];
    const rest = trimmed.substring(id.length);
    if (!rest) return { id, label: id, shape: 'rounded' };

    for (const pat of NODE_PATTERNS) {
      const m = rest.match(pat.re);
      if (m) {
        let label = m[1].replace(/<br\s*\/?>/gi, '\n').replace(/\\n/g, '\n').trim();
        if (!label) label = id;
        return { id, label, shape: pat.shape };
      }
    }
    return { id, label: id, shape: 'rounded' };
  }

  /*
   * Edge patterns — from/to parts use (.+?) to support inline node
   * definitions with brackets, e.g.:
   *   allrexx[[allrexx]] --initiated--> proc((proc))
   *
   * Patterns tested in order of specificity (most specific first):
   *   A -."label".-> B              dotted with inline label
   *   A -.->|"label"| B             dotted with pipe label
   *   A -.-> B                      dotted (no label)
   *   A ==>|"label"| B              thick with pipe label
   *   A ===> B                      thick (no label)
   *   A -->|"label"| B              pipe-delimited label
   *   A --"label"--> B              quoted inline label
   *   A --label--> B                unquoted inline label
   *   A --> B                       plain arrow
   */
  function splitEdge(line) {
    var m;

    // Dotted with inline label:  A -."label".-> B
    m = line.match(/^(.+?)\s*-\."([^"]*)"\.+->\s*(.+)$/);
    if (m) return { fromRaw: m[1].trim(), label: m[2], toRaw: m[3].trim(), dashed: true };

    // Dotted with pipe label:  A -.->|"label"| B
    m = line.match(/^(.+?)\s*-\.+->\|"?([^"|]*)"?\|\s*(.+)$/);
    if (m) return { fromRaw: m[1].trim(), label: m[2], toRaw: m[3].trim(), dashed: true };

    // Dotted no label:  A -.-> B
    m = line.match(/^(.+?)\s*-\.+->\s*(.+)$/);
    if (m) return { fromRaw: m[1].trim(), label: '', toRaw: m[2].trim(), dashed: true };

    // Thick with pipe label:  A ==>|label| B
    m = line.match(/^(.+?)\s*=+>\|"?([^"|]*)"?\|\s*(.+)$/);
    if (m) return { fromRaw: m[1].trim(), label: m[2], toRaw: m[3].trim(), thick: true };

    // Thick no label:  A ===> B
    m = line.match(/^(.+?)\s*=+>\s*(.+)$/);
    if (m) return { fromRaw: m[1].trim(), label: '', toRaw: m[2].trim(), thick: true };

    // Pipe-delimited label:  A -->|"label"| B
    m = line.match(/^(.+?)\s*-+>\|"?([^"|]*)"?\|\s*(.+)$/);
    if (m) return { fromRaw: m[1].trim(), label: m[2], toRaw: m[3].trim() };

    // Quoted inline label:  A --"label"--> B
    m = line.match(/^(.+?)\s*--"([^"]*)"-+>\s*(.+)$/);
    if (m) return { fromRaw: m[1].trim(), label: m[2], toRaw: m[3].trim() };

    // Unquoted inline label:  A --label--> B
    // [\w\s] ensures label starts with word char or space (not dash)
    m = line.match(/^(.+?)\s*--([\w\s][^"]*?)-+>\s*(.+)$/);
    if (m) return { fromRaw: m[1].trim(), label: m[2].trim(), toRaw: m[3].trim() };

    // Plain arrow:  A --> B  or A ----> B
    m = line.match(/^(.+?)\s*-+>\s*(.+)$/);
    if (m) return { fromRaw: m[1].trim(), label: '', toRaw: m[2].trim() };

    return null;
  }

  function parseMermaidFlowchart(text) {
    const nodes = new Map();
    const edges = [];
    const subgraphs = [];
    let direction = 'TD';
    let currentSubgraph = null;

    function ensureNode(raw) {
      const parsed = parseNodeDef(raw);
      if (!parsed) return raw.trim();
      if (!nodes.has(parsed.id)) {
        nodes.set(parsed.id, {
          id: parsed.id, label: parsed.label, shape: parsed.shape,
          goFigure: SHAPE_TO_FIGURE[parsed.shape] || 'Rectangle',
          group: currentSubgraph
        });
      } else {
        const existing = nodes.get(parsed.id);
        if (parsed.label !== parsed.id && existing.label === existing.id) {
          existing.label = parsed.label;
          existing.shape = parsed.shape;
          existing.goFigure = SHAPE_TO_FIGURE[parsed.shape] || 'Rectangle';
        }
      }
      return parsed.id;
    }

    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i].trim();
      if (!line) continue;

      // Skip non-graph lines
      if (line.startsWith('%%')) continue;
      if (line.startsWith('classDef ')) continue;
      if (line.startsWith('class ')) continue;
      if (line.startsWith('style ')) continue;
      if (line.startsWith('click ')) continue;
      if (line.startsWith('participant ')) continue;
      if (line.startsWith('linkStyle ')) continue;

      // Direction
      const dirMatch = line.match(/^flowchart\s+(LR|TD|RL|BT|TB)/i);
      if (dirMatch) { direction = dirMatch[1].toUpperCase(); continue; }

      // Subgraph
      const subMatch = line.match(/^subgraph\s+(\S+)(?:\["?([^"\]]*)"?\])?/);
      if (subMatch) {
        currentSubgraph = subMatch[1];
        subgraphs.push({ id: subMatch[1], label: subMatch[2] || subMatch[1] });
        continue;
      }
      if (line === 'end') { currentSubgraph = null; continue; }

      // Strip sequence numbers: (#N)
      line = line.replace(/\(#\d+\)/g, '');

      // Try edge
      const edge = splitEdge(line);
      if (edge) {
        const fromId = ensureNode(edge.fromRaw);
        const toId = ensureNode(edge.toRaw);
        const edgeObj = {
          from: fromId, to: toId,
          label: edge.label.replace(/<br\s*\/?>/gi, '\n').replace(/\\n/g, '\n')
        };
        if (edge.dashed) edgeObj.dashed = true;
        if (edge.thick) edgeObj.thick = true;
        edges.push(edgeObj);
        continue;
      }

      // Standalone node
      const nodeDef = parseNodeDef(line);
      if (nodeDef && nodeDef.id) {
        ensureNode(line);
      }
    }

    return { nodes: [...nodes.values()], edges, direction, subgraphs };
  }

  function parseMermaidErDiagram(text) {
    const entities = [];
    const relationships = [];
    let currentEntity = null;

    for (const rawLine of text.split('\n')) {
      const line = rawLine.trim();
      if (!line || line === 'erDiagram') continue;

      // Entity start: ENTITY_NAME {
      const entityStart = line.match(/^(\S+)\s*\{$/);
      if (entityStart) {
        currentEntity = { id: entityStart[1], label: entityStart[1], attributes: [] };
        entities.push(currentEntity);
        continue;
      }

      if (line === '}') { currentEntity = null; continue; }

      // Attribute inside entity: TYPE NAME "constraint"
      if (currentEntity) {
        const attrMatch = line.match(/^(\S+)\s+(\S+)(?:\s+"([^"]*)")?/);
        if (attrMatch) {
          currentEntity.attributes.push({
            type: attrMatch[1], name: attrMatch[2], constraint: attrMatch[3] || ''
          });
        }
        continue;
      }

      // Relationship: A }o--|| B : "label"
      const relMatch = line.match(/^(\S+)\s+([|}o{]+--[|}o{|]+)\s+(\S+)\s*:\s*"?([^"]*)"?/);
      if (relMatch) {
        relationships.push({
          from: relMatch[1], to: relMatch[3],
          cardinality: relMatch[2], label: relMatch[4]
        });
      }
    }

    const nodes = entities.map(e => ({
      id: e.id, label: e.label + '\n' + e.attributes.map(a => a.name).join('\n'),
      shape: 'cylinder', goFigure: 'Database'
    }));

    const edges = relationships.map(r => ({
      from: r.from, to: r.to, label: r.label
    }));

    return { nodes, edges, direction: 'TD', subgraphs: [] };
  }

  // ── Mermaid Sequence Diagram Parser ──────────────────────────────────

  function parseMermaidSequenceDiagram(text) {
    var participants = [];
    var participantSet = {};
    var messages = [];
    var hasAutonumber = false;

    function ensureParticipant(name) {
      if (!participantSet[name]) {
        participantSet[name] = true;
        participants.push({ id: name, label: name });
      }
    }

    var lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (!line || line === 'sequenceDiagram') continue;
      if (line === 'autonumber') { hasAutonumber = true; continue; }

      // participant X as "Label"  or  participant X
      var partMatch = line.match(/^participant\s+(\S+)(?:\s+as\s+"?([^"]*)"?)?$/);
      if (partMatch) {
        var pid = partMatch[1];
        if (!participantSet[pid]) {
          participantSet[pid] = true;
          participants.push({ id: pid, label: partMatch[2] || pid });
        } else if (partMatch[2]) {
          for (var p = 0; p < participants.length; p++) {
            if (participants[p].id === pid) participants[p].label = partMatch[2];
          }
        }
        continue;
      }

      // actor X as "Label"
      var actorMatch = line.match(/^actor\s+(\S+)(?:\s+as\s+"?([^"]*)"?)?$/);
      if (actorMatch) {
        var aid = actorMatch[1];
        if (!participantSet[aid]) {
          participantSet[aid] = true;
          participants.push({ id: aid, label: actorMatch[2] || aid, isActor: true });
        }
        continue;
      }

      // Note over A,B: text  or  Note right of A: text
      var noteMatch = line.match(/^Note\s+(over|left of|right of)\s+([^:]+):\s*(.*)$/i);
      if (noteMatch) {
        var targets = noteMatch[2].split(',').map(function (s) { return s.trim(); });
        targets.forEach(ensureParticipant);
        messages.push({ type: 'note', position: noteMatch[1], targets: targets, text: noteMatch[3] });
        continue;
      }

      // loop / alt / opt / par / rect / critical blocks
      var blockStart = line.match(/^(loop|alt|else|opt|par|rect|critical|break)\s*(.*)?$/i);
      if (blockStart) {
        messages.push({ type: 'block-start', block: blockStart[1].toLowerCase(), label: (blockStart[2] || '').trim() });
        continue;
      }
      if (line.toLowerCase() === 'end') {
        messages.push({ type: 'block-end' });
        continue;
      }

      // Messages: A->>B: label, A-->>B: label, A->>+B: label, A-xB: label, etc.
      /*
       * Mermaid sequence arrow patterns:
       *   ->>   solid arrow (async)
       *   -->>  dashed arrow (async)
       *   ->    solid line
       *   -->   dashed line
       *   -x    solid cross (lost message)
       *   --x   dashed cross
       *   -)    solid open arrow (async)
       *   --)   dashed open arrow
       *   + / - after arrow head = activate/deactivate
       */
      var msgMatch = line.match(/^(\S+?)\s*(--?>>?|--?x|--?\))\s*([+-]?)(\S+?)\s*:\s*(.*)$/);
      if (msgMatch) {
        var from = msgMatch[1];
        var arrow = msgMatch[2];
        var activation = msgMatch[3];
        var to = msgMatch[4];
        var label = msgMatch[5].trim();

        ensureParticipant(from);
        ensureParticipant(to);

        messages.push({
          type: 'message',
          from: from, to: to, label: label,
          dashed: arrow.indexOf('--') === 0,
          arrowType: arrow.indexOf('>>') >= 0 ? 'filled' : arrow.indexOf('x') >= 0 ? 'cross' : 'open',
          activate: activation === '+',
          deactivate: activation === '-'
        });
        continue;
      }
    }

    return { participants: participants, messages: messages, hasAutonumber: hasAutonumber };
  }

  function parseMermaidToGraph(text) {
    if (!text || !text.trim()) return null;
    const trimmed = text.trim();

    if (trimmed.startsWith('erDiagram')) return parseMermaidErDiagram(trimmed);
    if (trimmed.startsWith('sequenceDiagram')) return { _isSequence: true, _seqData: parseMermaidSequenceDiagram(trimmed) };
    if (trimmed.startsWith('classDiagram')) return parseMermaidFlowchart(trimmed);
    return parseMermaidFlowchart(trimmed);
  }

  // ── GoJS Renderer ────────────────────────────────────────────────────

  function buildNodeData(ugm) {
    var nc = getNodeColors();
    var defaultColors = nc.rounded;
    return ugm.nodes.map(function (n) {
      var c = nc[n.shape] || defaultColors;
      return {
        key: n.id, label: n.label, goFigure: n.goFigure,
        fill: c.fill, stroke: c.stroke, textColor: c.text,
        isGroup: false,
        group: n.group || undefined
      };
    });
  }

  function createGoJSDiagram(containerEl, ugm, layoutKey) {
    if (typeof go === 'undefined') {
      console.warn('GoJS not loaded');
      return null;
    }

    var theme = getTheme();
    var nodeCount = ugm.nodes ? ugm.nodes.length : 0;
    var chosenLayout = layoutKey || getPreferredLayout();
    var layoutFactory = LAYOUT_CONFIGS[chosenLayout] || LAYOUT_CONFIGS.layeredTD;

    containerEl.style.backgroundColor = theme.bg;

    var diagram = new go.Diagram(containerEl, {
      layout: layoutFactory(nodeCount),
      initialAutoScale: go.AutoScale.Uniform,
      padding: 30,
      scrollMode: go.ScrollMode.Infinite,
      'animationManager.isEnabled': false,
      'undoManager.isEnabled': false
    });

    diagram.toolManager.mouseWheelBehavior = go.WheelMode.Zoom;

    diagram.nodeTemplate = new go.Node('Auto', {
      toolTip: go.GraphObject.build('ToolTip').add(
        new go.TextBlock({ margin: 6, font: '12px Segoe UI' }).bind('text', 'label')
      )
    }).add(
      new go.Shape({
        strokeWidth: 2, portId: '', fromLinkable: false, toLinkable: false
      })
        .bind('figure', 'goFigure')
        .bind('fill', 'fill')
        .bind('stroke', 'stroke'),
      new go.TextBlock({
        margin: new go.Margin(6, 10, 6, 10),
        font: '11px "Segoe UI", sans-serif',
        maxSize: new go.Size(200, NaN),
        wrap: go.Wrap.Fit,
        textAlign: 'center'
      }).bind('text', 'label')
        .bind('stroke', 'textColor')
    );

    diagram.groupTemplate = new go.Group('Auto', {
      layout: new go.LayeredDigraphLayout({
        direction: 90, layerSpacing: 40, columnSpacing: 20
      }),
      isSubGraphExpanded: true
    }).add(
      new go.Shape('RoundedRectangle', {
        fill: shadeColor(theme.bg, 10), stroke: theme.border,
        strokeWidth: 1, parameter1: 8
      }),
      new go.Panel('Vertical').add(
        new go.TextBlock({
          font: 'bold 12px Segoe UI', stroke: theme.text,
          margin: new go.Margin(6, 8, 4, 8), alignment: go.Spot.Left
        }).bind('text', 'label'),
        new go.Placeholder({ padding: 10 })
      )
    );

    diagram.linkTemplate = new go.Link({
      routing: go.Routing.AvoidsNodes, corner: 8
    }).add(
      new go.Shape({ strokeWidth: 1.2, stroke: theme.linkStroke })
        .bind('strokeDashArray', 'dashed', function (d) { return d ? [4, 3] : null; })
        .bind('strokeWidth', 'thick', function (t) { return t ? 2.5 : 1.2; }),
      new go.Shape({ toArrow: 'Standard', scale: 1, fill: theme.linkStroke, stroke: theme.linkStroke }),
      new go.Panel('Auto', {
        visible: true
      }).add(
        new go.Shape({ fill: theme.linkLabelBg, stroke: null, opacity: 0.9 }),
        new go.TextBlock({
          font: '10px "Segoe UI", sans-serif', stroke: theme.linkLabelText,
          margin: 2, maxSize: new go.Size(150, NaN), wrap: go.Wrap.Fit,
          textAlign: 'center'
        }).bind('text', 'label')
          .bind('visible', 'label', function (l) { return !!l; })
      ).bind('visible', 'label', function (l) { return !!l; })
    );

    var nodeDataArray = buildNodeData(ugm);

    var groupDataArray = (ugm.subgraphs || []).map(function (sg) {
      return { key: sg.id, label: sg.label, isGroup: true };
    });

    var linkDataArray = ugm.edges.map(function (e) {
      return {
        from: e.from, to: e.to, label: e.label || '',
        dashed: e.dashed || false, thick: e.thick || false
      };
    });

    diagram.model = new go.GraphLinksModel({
      nodeKeyProperty: 'key',
      nodeIsGroupProperty: 'isGroup',
      nodeGroupKeyProperty: 'group',
      nodeDataArray: groupDataArray.concat(nodeDataArray),
      linkDataArray: linkDataArray
    });

    diagram._ugm = ugm;
    return diagram;
  }

  function updateGoJSTheme(diagram) {
    if (!diagram || !diagram.div) return;
    var isSequence = !!diagram._seqData;
    if (!isSequence && !diagram._ugm) return;

    var container = diagram.div;
    var parentEl = container.parentElement;
    if (!parentEl) return;

    diagram.div = null;
    container.remove();

    var newDiv = document.createElement('div');
    newDiv.className = 'gojs-diagram-container';
    newDiv.style.width = '100%';
    newDiv.style.height = '100%';
    newDiv.style.minHeight = '400px';
    parentEl.appendChild(newDiv);

    var diagramType = parentEl.closest('.diagram-wrapper')
      ? parentEl.closest('.diagram-wrapper').getAttribute('data-diagram-type')
      : null;

    var newDiagram = isSequence
      ? createGoJSSequenceDiagram(newDiv, diagram._seqData)
      : createGoJSDiagram(newDiv, diagram._ugm, getPreferredLayout());
    if (newDiagram && diagramType) {
      activeDiagrams[diagramType] = newDiagram;
    }
  }

  // ── GoJS Sequence Diagram Renderer ──────────────────────────────────

  function createGoJSSequenceDiagram(containerEl, seqData) {
    if (typeof go === 'undefined') { console.warn('GoJS not loaded'); return null; }

    var theme = getTheme();
    var nc = getNodeColors();
    var participants = seqData.participants;
    var allMessages = seqData.messages;

    // Adaptive spacing based on participant count
    var colSpacing = participants.length > 40 ? 80
      : participants.length > 20 ? 120
      : participants.length > 10 ? 150 : 180;
    var rowSpacing = 36;
    var headerHeight = 40;

    // Build message rows (only actual messages get waypoints)
    var msgRows = [];
    var msgNumber = 0;
    var blockDepth = 0;
    for (var mi = 0; mi < allMessages.length; mi++) {
      var m = allMessages[mi];
      if (m.type === 'message') {
        msgNumber++;
        msgRows.push({
          from: m.from, to: m.to,
          label: (seqData.hasAutonumber ? msgNumber + '. ' : '') + m.label,
          dashed: m.dashed, arrowType: m.arrowType, blockDepth: blockDepth
        });
      } else if (m.type === 'block-start') {
        blockDepth++;
        msgRows.push({ type: 'block-start', block: m.block, label: m.label, blockDepth: blockDepth });
      } else if (m.type === 'block-end') {
        blockDepth = Math.max(0, blockDepth - 1);
        msgRows.push({ type: 'block-end', blockDepth: blockDepth });
      } else if (m.type === 'note') {
        msgRows.push({ type: 'note', targets: m.targets, text: m.text, blockDepth: blockDepth });
      }
    }

    var participantIndex = {};
    for (var pi = 0; pi < participants.length; pi++) {
      participantIndex[participants[pi].id] = pi;
    }

    var totalRows = msgRows.length;

    containerEl.style.backgroundColor = theme.bg;

    var diagram = new go.Diagram(containerEl, {
      initialAutoScale: go.AutoScale.Uniform,
      padding: 30,
      scrollMode: go.ScrollMode.Infinite,
      'animationManager.isEnabled': false,
      'undoManager.isEnabled': false
    });

    diagram.toolManager.mouseWheelBehavior = go.WheelMode.Zoom;

    // ── Templates ──

    diagram.nodeTemplateMap.add('participant',
      new go.Node('Auto', { locationSpot: go.Spot.Top, movable: false, selectable: true })
        .add(
          new go.Shape('RoundedRectangle', { strokeWidth: 2, parameter1: 6 })
            .bind('fill', 'fill').bind('stroke', 'stroke'),
          new go.TextBlock({
            margin: new go.Margin(6, 10, 6, 10),
            font: 'bold 11px "Segoe UI", sans-serif',
            textAlign: 'center',
            maxSize: new go.Size(colSpacing - 10, NaN),
            overflow: go.TextOverflow.Ellipsis,
            wrap: go.Wrap.Fit
          }).bind('text', 'label').bind('stroke', 'textColor')
        )
        .bind('location', 'loc', go.Point.parse)
    );

    diagram.nodeTemplateMap.add('waypoint',
      new go.Node('Spot', { locationSpot: go.Spot.Center, movable: false, selectable: false, pickable: false })
        .add(new go.Shape('Circle', { width: 1, height: 1, fill: null, stroke: null }))
        .bind('location', 'loc', go.Point.parse)
    );

    diagram.nodeTemplateMap.add('block-label',
      new go.Node('Auto', { locationSpot: go.Spot.TopLeft, movable: false, selectable: false })
        .add(
          new go.Shape('Rectangle', {
            fill: isDarkMode() ? '#1e2540' : '#eef2ff',
            stroke: isDarkMode() ? '#4f6090' : '#a0b0d8',
            strokeWidth: 1, strokeDashArray: [4, 2]
          }),
          new go.TextBlock({
            margin: new go.Margin(2, 6, 2, 6),
            font: 'italic 10px "Segoe UI", sans-serif',
            stroke: isDarkMode() ? '#90a8d0' : '#4a5a80'
          }).bind('text', 'text')
        )
        .bind('location', 'loc', go.Point.parse)
    );

    diagram.nodeTemplateMap.add('note',
      new go.Node('Auto', { locationSpot: go.Spot.Center, movable: false })
        .add(
          new go.Shape('Rectangle', {
            fill: isDarkMode() ? '#3a3520' : '#fffbe6',
            stroke: isDarkMode() ? '#b8960a' : '#e6c200', strokeWidth: 1
          }),
          new go.TextBlock({
            margin: new go.Margin(4, 8, 4, 8),
            font: '10px "Segoe UI", sans-serif',
            stroke: isDarkMode() ? '#f0e0a0' : '#6b5900',
            maxSize: new go.Size(200, NaN), wrap: go.Wrap.Fit, textAlign: 'center'
          }).bind('text', 'text')
        )
        .bind('location', 'loc', go.Point.parse)
    );

    diagram.linkTemplateMap.add('lifeline',
      new go.Link({ routing: go.Routing.Normal, selectable: false, pickable: false })
        .add(new go.Shape({ strokeWidth: 1, strokeDashArray: [3, 3] }).bind('stroke', 'stroke'))
    );

    diagram.linkTemplateMap.add('message',
      new go.Link({
        routing: go.Routing.Normal, selectable: true,
        toolTip: go.GraphObject.build('ToolTip').add(
          new go.TextBlock({ margin: 6, font: '12px Segoe UI' }).bind('text', 'fullLabel')
        )
      }).add(
        new go.Shape({ strokeWidth: 1.4 })
          .bind('stroke', 'stroke')
          .bind('strokeDashArray', 'dashed', function (d) { return d ? [5, 3] : null; }),
        new go.Shape({ scale: 1.1 })
          .bind('toArrow', 'arrowType', function (t) { return t === 'cross' ? 'X' : t === 'open' ? 'OpenTriangle' : 'Standard'; })
          .bind('fill', 'stroke').bind('stroke', 'stroke'),
        new go.Panel('Auto').add(
          new go.Shape({ fill: theme.bg, stroke: null, opacity: 0.85 }),
          new go.TextBlock({
            font: '10px "Segoe UI", sans-serif',
            margin: new go.Margin(1, 4, 1, 4),
            maxSize: new go.Size(colSpacing - 20, NaN),
            wrap: go.Wrap.Fit, textAlign: 'center'
          }).bind('text', 'label').bind('stroke', 'labelColor')
        )
      )
    );

    diagram.linkTemplateMap.add('self-message',
      new go.Link({
        routing: go.Routing.Normal, selectable: true,
        fromEndSegmentLength: 30, toEndSegmentLength: 30,
        curve: go.Curve.Bezier, curviness: 30
      }).add(
        new go.Shape({ strokeWidth: 1.4 })
          .bind('stroke', 'stroke')
          .bind('strokeDashArray', 'dashed', function (d) { return d ? [5, 3] : null; }),
        new go.Shape({ toArrow: 'Standard', scale: 1.1 })
          .bind('fill', 'stroke').bind('stroke', 'stroke'),
        new go.Panel('Auto').add(
          new go.Shape({ fill: theme.bg, stroke: null, opacity: 0.85 }),
          new go.TextBlock({
            font: '10px "Segoe UI", sans-serif',
            margin: new go.Margin(1, 4, 1, 4),
            maxSize: new go.Size(140, NaN), wrap: go.Wrap.Fit
          }).bind('text', 'label').bind('stroke', 'labelColor')
        )
      )
    );

    // ── Build data arrays (sparse waypoints: only where needed) ──

    var nodeDataArray = [];
    var linkDataArray = [];
    var participantColors = nc.stadium;
    var lifelineColor = isDarkMode() ? '#3a4060' : '#c0c8d8';
    var msgColors = isDarkMode()
      ? { stroke: '#6b8fc8', label: '#b0c8e8' }
      : { stroke: '#3b6ea0', label: '#1e3a5f' };
    var dottedMsgColors = isDarkMode()
      ? { stroke: '#8888aa', label: '#a0a0c0' }
      : { stroke: '#7080a0', label: '#405070' };
    var topY = headerHeight + 20;

    // Determine which rows each participant is involved in
    var participantRows = {};
    for (pi = 0; pi < participants.length; pi++) {
      participantRows[participants[pi].id] = [];
    }
    for (var ri = 0; ri < msgRows.length; ri++) {
      var msg = msgRows[ri];
      if (msg.from && participantRows[msg.from]) participantRows[msg.from].push(ri);
      if (msg.to && msg.to !== msg.from && participantRows[msg.to]) participantRows[msg.to].push(ri);
    }

    // Participant headers
    for (var ci = 0; ci < participants.length; ci++) {
      var x = ci * colSpacing;
      nodeDataArray.push({
        key: 'p_' + participants[ci].id,
        category: 'participant',
        label: participants[ci].label,
        fill: participantColors.fill,
        stroke: participantColors.stroke,
        textColor: participantColors.text,
        loc: x + ' 0'
      });
    }

    // Sparse waypoints and lifeline links per participant
    var waypointMap = {};
    for (ci = 0; ci < participants.length; ci++) {
      var pid = participants[ci].id;
      var px = ci * colSpacing;
      var rows = participantRows[pid];
      if (!rows || rows.length === 0) {
        // No messages: just a short lifeline stub
        var stubKey = 'wp_' + ci + '_end';
        nodeDataArray.push({ key: stubKey, category: 'waypoint', loc: px + ' ' + (topY + 20) });
        linkDataArray.push({ from: 'p_' + pid, to: stubKey, category: 'lifeline', stroke: lifelineColor });
        continue;
      }

      // Sort rows and add top + bottom anchors
      rows.sort(function (a, b) { return a - b; });
      var uniqueRows = [rows[0]];
      for (var k = 1; k < rows.length; k++) {
        if (rows[k] !== uniqueRows[uniqueRows.length - 1]) uniqueRows.push(rows[k]);
      }

      var prevKey = 'p_' + pid;
      for (k = 0; k < uniqueRows.length; k++) {
        var row = uniqueRows[k];
        var wy = topY + row * rowSpacing;
        var wpKey = 'wp_' + ci + '_' + row;
        nodeDataArray.push({ key: wpKey, category: 'waypoint', loc: px + ' ' + wy });
        if (!waypointMap[pid]) waypointMap[pid] = {};
        waypointMap[pid][row] = wpKey;

        linkDataArray.push({ from: prevKey, to: wpKey, category: 'lifeline', stroke: lifelineColor });
        prevKey = wpKey;
      }

      // Final stub to extend lifeline to bottom
      var bottomY = topY + (totalRows + 1) * rowSpacing;
      var endKey = 'wp_' + ci + '_end';
      nodeDataArray.push({ key: endKey, category: 'waypoint', loc: px + ' ' + bottomY });
      linkDataArray.push({ from: prevKey, to: endKey, category: 'lifeline', stroke: lifelineColor });
    }

    // Message links and block labels
    for (ri = 0; ri < msgRows.length; ri++) {
      msg = msgRows[ri];

      if (msg.type === 'block-start') {
        nodeDataArray.push({
          key: 'bl_' + ri, category: 'block-label',
          text: msg.block.toUpperCase() + (msg.label ? ' [' + msg.label + ']' : ''),
          loc: '-30 ' + (topY + ri * rowSpacing - rowSpacing / 3)
        });
        continue;
      }
      if (msg.type === 'block-end' || !msg.from) continue;

      if (msg.type === 'note') {
        var tidx = (msg.targets && msg.targets[0]) ? (participantIndex[msg.targets[0]] || 0) : 0;
        nodeDataArray.push({
          key: 'note_' + ri, category: 'note', text: msg.text,
          loc: (tidx * colSpacing + colSpacing / 2) + ' ' + (topY + ri * rowSpacing)
        });
        continue;
      }

      var fromIdx = participantIndex[msg.from];
      var toIdx = participantIndex[msg.to];
      if (fromIdx === undefined || toIdx === undefined) continue;

      var fromWP = waypointMap[msg.from] && waypointMap[msg.from][ri];
      var toWP = waypointMap[msg.to] && waypointMap[msg.to][ri];
      if (!fromWP || (!toWP && msg.from !== msg.to)) continue;

      var isSelf = msg.from === msg.to;
      var colors = msg.dashed ? dottedMsgColors : msgColors;

      linkDataArray.push({
        from: fromWP, to: isSelf ? fromWP : toWP,
        category: isSelf ? 'self-message' : 'message',
        label: msg.label, fullLabel: msg.label,
        stroke: colors.stroke, labelColor: colors.label,
        dashed: msg.dashed || false,
        arrowType: msg.arrowType || 'filled'
      });
    }

    diagram.model = new go.GraphLinksModel({
      nodeKeyProperty: 'key',
      nodeDataArray: nodeDataArray,
      linkDataArray: linkDataArray
    });

    diagram._seqData = seqData;
    return diagram;
  }

  // ── GoJS Zoom API ────────────────────────────────────────────────────

  function goJSZoomIn(diagram) {
    if (!diagram) return;
    diagram.commandHandler.increaseZoom(1.2);
  }

  function goJSZoomOut(diagram) {
    if (!diagram) return;
    diagram.commandHandler.decreaseZoom(0.8);
  }

  function goJSZoomFit(diagram) {
    if (!diagram) return;
    diagram.zoomToFit();
  }

  function goJSZoomReset(diagram) {
    if (!diagram) return;
    diagram.scale = 1.0;
    diagram.scrollToRect(diagram.documentBounds);
  }

  function goJSGetZoomPercent(diagram) {
    if (!diagram) return 100;
    return Math.round(diagram.scale * 100);
  }

  // ── Renderer Switching ───────────────────────────────────────────────

  function renderDiagram(wrapper, renderer, layoutKey) {
    var source = wrapper.querySelector('.mermaid-source');
    var target = wrapper.querySelector('.diagram-render-target');
    var diagramType = wrapper.getAttribute('data-diagram-type') || 'flow';

    if (!source || !target) return;

    var mermaidText = source.textContent;

    if (renderer === 'gojs') {
      var ugm = parseMermaidToGraph(mermaidText);

      // Sequence diagram: use dedicated GoJS sequence renderer
      if (ugm && ugm._isSequence) {
        target.innerHTML = '';
        var seqDiv = document.createElement('div');
        seqDiv.className = 'gojs-diagram-container';
        seqDiv.style.width = '100%';
        seqDiv.style.height = '100%';
        seqDiv.style.minHeight = '400px';
        target.appendChild(seqDiv);

        var seqDiagram = createGoJSSequenceDiagram(seqDiv, ugm._seqData);
        if (seqDiagram) {
          activeDiagrams[diagramType] = seqDiagram;
          target.style.display = '';
          source.style.display = 'none';
          var seqMermaid = wrapper.querySelector('pre.mermaid');
          if (seqMermaid) seqMermaid.style.display = 'none';
        }
        updateLayoutVisibility('gojs');
        return;
      }

      // Standard graph diagrams
      if (!ugm || (ugm.nodes && ugm.nodes.length < 3)) {
        console.warn('GoJS: UGM parse returned ' + (ugm ? ugm.nodes.length : 0) + ' nodes, falling back to Mermaid');
        renderer = 'mermaid';
      } else {
        target.innerHTML = '';
        var gojsDiv = document.createElement('div');
        gojsDiv.className = 'gojs-diagram-container';
        gojsDiv.style.width = '100%';
        gojsDiv.style.height = '100%';
        gojsDiv.style.minHeight = '400px';
        target.appendChild(gojsDiv);

        var diagram = createGoJSDiagram(gojsDiv, ugm, layoutKey);
        if (diagram) {
          activeDiagrams[diagramType] = diagram;
          target.style.display = '';
          source.style.display = 'none';
          var mermaidSvg = wrapper.querySelector('.mermaid svg, pre.mermaid');
          if (mermaidSvg) mermaidSvg.style.display = 'none';
        }
        updateLayoutVisibility('gojs');
        return;
      }
    }

    // Mermaid rendering
    delete activeDiagrams[diagramType];
    target.style.display = 'none';
    target.innerHTML = '';
    updateLayoutVisibility('mermaid');

    var mermaidPre = wrapper.querySelector('pre.mermaid');
    if (mermaidPre) {
      mermaidPre.style.display = '';
      setTimeout(function () {
        var svg = mermaidPre.querySelector('svg');
        var hasError = mermaidPre.querySelector('.error') || mermaidPre.closest('.diagram-wrapper').querySelector('.mermaid-error');
        var mermaidNodeCount = svg ? svg.querySelectorAll('.node, .nodeLabel').length : 0;
        if (hasError || (svg && mermaidNodeCount < 3)) {
          console.warn('Mermaid rendering issue detected (error=' + !!hasError + ', nodes=' + mermaidNodeCount + '), switching to GoJS');
          renderDiagram(wrapper, 'gojs');
          document.querySelectorAll('.diagram-renderer-select').forEach(function (sel) { sel.value = 'gojs'; });
          updateLayoutVisibility('gojs');
        }
      }, 1500);
    } else {
      var pre = document.createElement('pre');
      pre.className = 'mermaid';
      pre.setAttribute('data-diagram-type', diagramType);
      pre.textContent = mermaidText;
      wrapper.insertBefore(pre, target);
      if (window.mermaidInstance) {
        window.mermaidInstance.run({ nodes: [pre] }).catch(function () {
          console.warn('Mermaid render failed, switching to GoJS');
          renderDiagram(wrapper, 'gojs');
          document.querySelectorAll('.diagram-renderer-select').forEach(function (sel) { sel.value = 'gojs'; });
          updateLayoutVisibility('gojs');
        });
      }
    }
  }

  function switchRenderer(diagramType, renderer) {
    setPreferredRenderer(renderer);
    updateLayoutVisibility(renderer);

    document.querySelectorAll('.diagram-wrapper').forEach(function (wrapper) {
      var wType = wrapper.getAttribute('data-diagram-type');
      var forceRenderer = wrapper.getAttribute('data-force-renderer');
      renderDiagram(wrapper, forceRenderer || renderer);
    });

    document.querySelectorAll('.diagram-renderer-select').forEach(function (sel) {
      sel.value = renderer;
    });

    if (renderer === 'gojs') {
      Object.keys(activeDiagrams).forEach(function (key) {
        var zoomEl = document.getElementById(key + '-zoom');
        if (zoomEl) zoomEl.textContent = goJSGetZoomPercent(activeDiagrams[key]) + '%';
      });
    }
  }

  function switchLayout(layoutKey) {
    setPreferredLayout(layoutKey);
    document.querySelectorAll('.diagram-layout-select').forEach(function (sel) {
      sel.value = layoutKey;
    });
    document.querySelectorAll('.diagram-wrapper').forEach(function (wrapper) {
      var wType = wrapper.getAttribute('data-diagram-type');
      if (!activeDiagrams[wType]) return;
      renderDiagram(wrapper, 'gojs', layoutKey);
    });
  }

  function initDiagrams() {
    var preferred = getPreferredRenderer();
    var preferredLayout = getPreferredLayout();
    var wrappers = document.querySelectorAll('.diagram-wrapper');

    wrappers.forEach(function (wrapper) {
      var diagramType = wrapper.getAttribute('data-diagram-type') || 'flow';

      var source = wrapper.querySelector('.mermaid-source');
      if (!source) return;

      // Skip GoJS rendering for wrappers in hidden tabs (GoJS needs visible container)
      var contentParent = wrapper.closest('.diagram-content');
      var isVisible = !contentParent || contentParent.classList.contains('active');

      var mermaidText = source.textContent || '';
      var forceRenderer = wrapper.getAttribute('data-force-renderer');
      var serverCount = parseInt(wrapper.getAttribute('data-node-count') || '0', 10);
      var nodeCount = serverCount > 0 ? serverCount
        : (mermaidText.match(/^\s*[\w.\-:]+[\[({"]/gm) || []).length;

      var effectiveRenderer = forceRenderer || preferred;
      if (!forceRenderer && effectiveRenderer === 'mermaid' && nodeCount > MAX_NODES) {
        effectiveRenderer = 'gojs';
      }

      // Hide renderer dropdown and label when renderer is forced
      if (forceRenderer) {
        var toolbar = wrapper.closest('.diagram-content');
        if (toolbar) {
          var select = toolbar.querySelector('.diagram-renderer-select');
          if (select) select.style.display = 'none';
          var rendererLabel = toolbar.querySelector('.diagram-renderer-label');
          if (rendererLabel) rendererLabel.style.display = 'none';
        }
      }

      if (!isVisible && effectiveRenderer === 'gojs') {
        // Defer: tab-switch handler will trigger renderDiagramEl
        return;
      }

      renderDiagram(wrapper, effectiveRenderer, preferredLayout);
    });

    // Set up renderer dropdowns
    document.querySelectorAll('.diagram-renderer-select').forEach(function (sel) {
      sel.value = preferred;
      sel.addEventListener('change', function () {
        switchRenderer(sel.getAttribute('data-target'), sel.value);
      });
    });

    // Set up layout dropdowns
    document.querySelectorAll('.diagram-layout-select').forEach(function (sel) {
      sel.value = preferredLayout;
      sel.addEventListener('change', function () {
        switchLayout(sel.value);
      });
    });

    updateLayoutVisibility(preferred);

    // GoJS needs the container to have computed CSS dimensions.
    // At DOMContentLoaded the layout may not be settled yet, so
    // schedule a delayed requestUpdate + zoomToFit for all active diagrams.
    setTimeout(function () {
      Object.keys(activeDiagrams).forEach(function (key) {
        var d = activeDiagrams[key];
        if (d && d.div) {
          d.requestUpdate();
          d.zoomToFit();
        }
      });
    }, 400);
    setTimeout(function () {
      Object.keys(activeDiagrams).forEach(function (key) {
        var d = activeDiagrams[key];
        if (d && d.div) {
          d.requestUpdate();
          d.zoomToFit();
        }
      });
    }, 1000);
  }

  // ── GoJS Node Navigation ─────────────────────────────────────────────

  function goJSFindAndHighlightNode(diagram, nodeId) {
    if (!diagram) return false;
    const node = diagram.findNodeForKey(nodeId);
    if (!node) {
      // Try case-insensitive search
      let found = null;
      diagram.nodes.each(function (n) {
        if (n.key && n.key.toLowerCase() === nodeId.toLowerCase()) found = n;
      });
      if (!found) return false;
      diagram.centerRect(found.actualBounds);
      diagram.select(found);
      return true;
    }
    diagram.centerRect(node.actualBounds);
    diagram.select(node);
    return true;
  }

  // ── Public API ───────────────────────────────────────────────────────

  window.autodocRenderer = {
    parseMermaidToGraph: parseMermaidToGraph,
    getPreferredRenderer: getPreferredRenderer,
    setPreferredRenderer: setPreferredRenderer,
    getPreferredLayout: getPreferredLayout,
    setPreferredLayout: setPreferredLayout,
    switchRenderer: switchRenderer,
    switchLayout: switchLayout,
    initDiagrams: initDiagrams,
    renderDiagramEl: renderDiagram,
    updateAllGoJSThemes: function () {
      Object.values(activeDiagrams).forEach(updateGoJSTheme);
    },
    getActiveDiagram: function (diagramType) {
      return activeDiagrams[diagramType] || null;
    },
    goJSZoomIn: function (diagramType) {
      goJSZoomIn(activeDiagrams[diagramType]);
    },
    goJSZoomOut: function (diagramType) {
      goJSZoomOut(activeDiagrams[diagramType]);
    },
    goJSZoomFit: function (diagramType) {
      goJSZoomFit(activeDiagrams[diagramType]);
    },
    goJSZoomReset: function (diagramType) {
      goJSZoomReset(activeDiagrams[diagramType]);
    },
    goJSGetZoomPercent: function (diagramType) {
      return goJSGetZoomPercent(activeDiagrams[diagramType]);
    },
    goJSFindAndHighlightNode: function (diagramType, nodeId) {
      return goJSFindAndHighlightNode(activeDiagrams[diagramType], nodeId);
    },
    isGoJSActive: function (diagramType) {
      return !!activeDiagrams[diagramType];
    },
    activeDiagrams: activeDiagrams
  };

  // Auto-init when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initDiagrams);
  } else {
    setTimeout(initDiagrams, 100);
  }
})();
