/**
 * AutoDoc Mermaid Configuration
 * Centralized Mermaid initialization with theme-aware styling.
 * Uses theme 'base' so themeVariables are applied (only base is modifiable).
 * Author: Geir Helge Starholm, www.dEdge.no
 */

// Get current theme from document
function getMermaidTheme() {
  return document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'default';
}

// Dark mode: base theme + darkMode true + high-contrast node fill vs text
const darkThemeVars = {
  darkMode: true,
  fontFamily: '"Courier New", Courier, monospace',
  fontSize: '14px',
  lineColor: '#7cc4fa',
  primaryTextColor: '#e8edf4',
  primaryColor: '#1e2d3d',
  primaryBorderColor: '#7cc4fa',
  secondaryTextColor: '#e8edf4',
  secondaryColor: '#253548',
  secondaryBorderColor: '#5fa8d9',
  tertiaryTextColor: '#e8edf4',
  tertiaryColor: '#1a2940',
  tertiaryBorderColor: '#5fa8d9',
  mainBkg: '#1e2d3d',
  nodeTextColor: '#e8edf4',
  textColor: '#e8edf4',
  edgeLabelBackground: '#1e3048',
  clusterBkg: '#1a2940',
  clusterBorder: '#7cc4fa',
  titleColor: '#e8edf4',
  noteBkgColor: '#1e2d3d',
  noteTextColor: '#e8edf4',
  noteBorderColor: '#5fa8d9',
  actorTextColor: '#e8edf4',
  actorBkg: '#1e2d3d',
  actorBorder: '#7cc4fa',
  signalColor: '#e8edf4',
  labelBoxBkgColor: '#1e3048',
  labelBoxBorderColor: '#7cc4fa',
  labelTextColor: '#e8edf4'
};

// Light mode: base theme + darkMode false + high-contrast node fill vs text
const lightThemeVars = {
  darkMode: false,
  fontFamily: '"Courier New", Courier, monospace',
  fontSize: '14px',
  lineColor: '#333333',
  primaryTextColor: '#1a1a1a',
  primaryColor: '#e8f4fc',
  primaryBorderColor: '#0891b2',
  secondaryTextColor: '#1a1a1a',
  secondaryColor: '#dbeafe',
  secondaryBorderColor: '#2563eb',
  tertiaryTextColor: '#1a1a1a',
  tertiaryColor: '#f0f9ff',
  tertiaryBorderColor: '#0ea5e9',
  mainBkg: '#e8f4fc',
  nodeTextColor: '#1a1a1a',
  textColor: '#1a1a1a',
  edgeLabelBackground: '#f1f5f9',
  clusterBkg: '#f0f9ff',
  clusterBorder: '#0891b2',
  titleColor: '#1a1a1a',
  noteBkgColor: '#fef9c3',
  noteTextColor: '#1a1a1a',
  noteBorderColor: '#ca8a04',
  actorTextColor: '#1a1a1a',
  actorBkg: '#e8f4fc',
  actorBorder: '#0891b2',
  signalColor: '#1a1a1a',
  labelBoxBkgColor: '#f1f5f9',
  labelBoxBorderColor: '#0891b2',
  labelTextColor: '#1a1a1a'
};

// Get theme variables based on current theme
function getThemeVariables() {
  return getMermaidTheme() === 'dark' ? darkThemeVars : lightThemeVars;
}

// Initialize Mermaid with current theme. Use theme 'base' so themeVariables apply (only base is modifiable).
function initMermaidWithTheme() {
  const themeVars = getThemeVariables();
  
  mermaid.initialize({
    startOnLoad: true,
    theme: 'base',
    securityLevel: 'loose',
    suppressErrorRendering: true,
    maxTextSize: 5000000,
    maxEdges: 5000,
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
  const themeVars = getThemeVariables();
  
  if (window.mermaidInstance) {
    window.mermaidInstance.initialize({
      startOnLoad: false,
      theme: 'base',
      securityLevel: 'loose',
      suppressErrorRendering: true,
      maxTextSize: 5000000,
      maxEdges: 5000,
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
