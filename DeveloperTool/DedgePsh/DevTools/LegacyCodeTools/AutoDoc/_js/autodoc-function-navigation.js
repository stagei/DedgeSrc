/**
 * AutoDoc Function Navigation
 * Handles hash fragment navigation to function anchors and highlights/zooms to function nodes in Mermaid diagrams
 */

(function() {
    'use strict';

    /**
     * Scrolls to function anchor and highlights the corresponding Mermaid node
     */
    function navigateToFunction(functionName) {
        if (!functionName) {
            return;
        }

        // Normalize function name (remove # if present, convert to lowercase)
        const normalizedName = functionName.replace(/^#/, '').toLowerCase();
        const anchorId = `function-${normalizedName}`;

        // Scroll to anchor in HTML
        const anchorElement = document.getElementById(anchorId);
        if (anchorElement) {
            anchorElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
            // Highlight anchor temporarily
            anchorElement.style.backgroundColor = 'var(--accent-primary)';
            anchorElement.style.transition = 'background-color 0.3s';
            setTimeout(() => {
                anchorElement.style.backgroundColor = '';
            }, 2000);
        }

        // Find and highlight corresponding Mermaid node
        highlightMermaidNode(normalizedName);
    }

    /**
     * Highlights a function node in the Mermaid diagram
     */
    function highlightMermaidNode(functionName) {
        // Wait for Mermaid to render
        setTimeout(() => {
            const mermaidContainer = document.querySelector('.mermaid');
            if (!mermaidContainer) {
                return;
            }

            const svg = mermaidContainer.querySelector('svg');
            if (!svg) {
                return;
            }

            // Find node by text content (function name)
            const nodes = svg.querySelectorAll('.nodeLabel, .node-label, text');
            let targetNode = null;
            let targetGroup = null;

            nodes.forEach(node => {
                const text = node.textContent || node.innerText || '';
                const normalizedText = text.toLowerCase().trim();
                
                // Match function name (exact match or contains)
                if (normalizedText === functionName || 
                    normalizedText.includes(functionName) ||
                    normalizedText.replace(/[^a-z0-9]/g, '') === functionName.replace(/[^a-z0-9]/g, '')) {
                    targetNode = node;
                    // Find parent group element
                    let parent = node.parentElement;
                    while (parent && parent.tagName !== 'g') {
                        parent = parent.parentElement;
                    }
                    if (parent) {
                        targetGroup = parent;
                    }
                }
            });

            if (targetGroup) {
                // Highlight the node
                const rect = targetGroup.querySelector('rect, polygon, ellipse, circle');
                if (rect) {
                    const originalFill = rect.getAttribute('fill');
                    const originalStroke = rect.getAttribute('stroke') || rect.getAttribute('stroke-width');
                    
                    // Add highlight style
                    rect.setAttribute('fill', 'var(--accent-primary)');
                    rect.setAttribute('stroke', 'var(--accent-primary)');
                    rect.setAttribute('stroke-width', '3');
                    rect.style.transition = 'all 0.3s';
                    
                    // Remove highlight after 3 seconds
                    setTimeout(() => {
                        if (originalFill) {
                            rect.setAttribute('fill', originalFill);
                        }
                        if (originalStroke) {
                            rect.setAttribute('stroke', originalStroke);
                        }
                        rect.setAttribute('stroke-width', '1');
                    }, 3000);

                    // Scroll diagram to show the node (if pan-zoom is available)
                    scrollToNode(targetGroup);
                }
            }
        }, 500); // Wait for Mermaid rendering
    }

    /**
     * Scrolls the diagram to show a specific node
     */
    function scrollToNode(nodeElement) {
        if (!nodeElement) {
            return;
        }

        // Get node position
        const bbox = nodeElement.getBoundingClientRect();
        const container = document.getElementById('flow-container');
        
        if (!container) {
            return;
        }

        const containerRect = container.getBoundingClientRect();
        
        // Calculate scroll position to center the node
        const scrollLeft = container.scrollLeft + (bbox.left - containerRect.left) - (containerRect.width / 2) + (bbox.width / 2);
        const scrollTop = container.scrollTop + (bbox.top - containerRect.top) - (containerRect.height / 2) + (bbox.height / 2);

        // Smooth scroll
        container.scrollTo({
            left: scrollLeft,
            top: scrollTop,
            behavior: 'smooth'
        });

        // If pan-zoom is available, use it
        if (window.svgPanZoomInstances && window.svgPanZoomInstances['flow']) {
            try {
                const svg = container.querySelector('svg');
                if (svg) {
                    const svgRect = svg.getBoundingClientRect();
                    const nodeRect = nodeElement.getBoundingClientRect();
                    
                    // Calculate center point relative to SVG
                    const centerX = (nodeRect.left - svgRect.left + nodeRect.width / 2) / svgRect.width;
                    const centerY = (nodeRect.top - svgRect.top + nodeRect.height / 2) / svgRect.height;
                    
                    // Pan to center
                    window.svgPanZoomInstances['flow'].panTo({ x: centerX, y: centerY });
                    window.svgPanZoomInstances['flow'].zoomAtPoint(1.5, { x: centerX, y: centerY });
                }
            } catch (e) {
                console.warn('Error using pan-zoom:', e);
            }
        }
    }

    /**
     * Handle hash change events
     */
    function handleHashChange() {
        const hash = window.location.hash;
        if (hash && hash.startsWith('#function-')) {
            const functionName = hash.replace('#function-', '');
            navigateToFunction(functionName);
        }
    }

    /**
     * Initialize function navigation
     */
    function initFunctionNavigation() {
        // Handle initial hash on page load
        if (window.location.hash) {
            handleHashChange();
        }

        // Listen for hash changes
        window.addEventListener('hashchange', handleHashChange);

        // Also listen for Mermaid render events
        if (window.mermaidInstance) {
            const originalRender = window.mermaidInstance.render;
            if (originalRender) {
                window.mermaidInstance.render = function(...args) {
                    const result = originalRender.apply(this, args);
                    // After rendering, check if we need to navigate
                    setTimeout(() => {
                        if (window.location.hash) {
                            handleHashChange();
                        }
                    }, 100);
                    return result;
                };
            }
        }
    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initFunctionNavigation);
    } else {
        initFunctionNavigation();
    }

})();
