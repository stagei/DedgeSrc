/**
 * AutoDoc Mermaid Configuration
 * Centralized Mermaid initialization with theme-aware styling
 * Author: Geir Helge Starholm, www.dEdge.no
 */

// Get current theme from document
function getMermaidTheme() {
  return document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'default';
}

// Theme variables for dark mode - bright blue lines for visibility
const darkThemeVars = {
  fontFamily: '"Courier New", Courier, monospace',
  fontSize: '14px',
  lineColor: '#64b5f6',
  primaryTextColor: '#f5f5f5',
  primaryColor: '#3a3a5c',
  primaryBorderColor: '#64b5f6',
  secondaryColor: '#2d2d4a',
  tertiaryColor: '#252542',
  edgeLabelBackground: '#2d2d4a',
  clusterBkg: '#252542',
  clusterBorder: '#64b5f6',
  titleColor: '#f5f5f5',
  nodeTextColor: '#f5f5f5'
};

// Theme variables for light mode
const lightThemeVars = {
  fontFamily: '"Courier New", Courier, monospace',
  fontSize: '14px'
};

// Get theme variables based on current theme
function getThemeVariables() {
  return getMermaidTheme() === 'dark' ? darkThemeVars : lightThemeVars;
}

// Initialize Mermaid with current theme
function initMermaidWithTheme() {
  const theme = getMermaidTheme();
  const themeVars = getThemeVariables();
  
  mermaid.initialize({
    startOnLoad: true,
    theme: theme,
    securityLevel: 'loose',
    suppressErrorRendering: true,  // Suppress "Syntax error in text" overlay - diagrams still render
    maxTextSize: 5000000,  // 5 million chars (default: 50,000) - for very large diagrams
    maxEdges: 5000,        // 5000 edges (default: 500) - for complex graphs with many connections
    themeVariables: themeVars,
    flowchart: {
      useMaxWidth: true,
      htmlLabels: true,
      curve: 'basis'
    },
    sequence: {
      useMaxWidth: true
    },
    classDiagram: {
      useMaxWidth: true
    }
  });
}

// Re-initialize Mermaid when theme changes (called from autodoc-diagram-controls.js)
function reinitMermaidTheme() {
  const theme = getMermaidTheme();
  const themeVars = getThemeVariables();
  
  if (window.mermaidInstance) {
    window.mermaidInstance.initialize({
      startOnLoad: false,
      theme: theme,
      securityLevel: 'loose',
      suppressErrorRendering: true,  // Suppress "Syntax error in text" overlay - diagrams still render
      maxTextSize: 5000000,  // 5 million chars (default: 50,000) - for very large diagrams
      maxEdges: 5000,        // 5000 edges (default: 500) - for complex graphs with many connections
      themeVariables: themeVars,
      flowchart: {
        useMaxWidth: true,
        htmlLabels: true,
        curve: 'basis'
      },
      sequence: {
        useMaxWidth: true
      },
      classDiagram: {
        useMaxWidth: true
      }
    });
  }
}

// Export for use by other scripts
window.getMermaidTheme = getMermaidTheme;
window.getThemeVariables = getThemeVariables;
window.reinitMermaidTheme = reinitMermaidTheme;
