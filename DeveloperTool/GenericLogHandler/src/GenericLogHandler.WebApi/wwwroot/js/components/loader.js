/**
 * Loader Component - Loading overlay and spinners
 */
const Loader = (function() {
    let overlayElement = null;
    let activeCount = 0;

    /**
     * Initialize loader overlay
     */
    function init() {
        if (!document.getElementById('loader-overlay')) {
            overlayElement = document.createElement('div');
            overlayElement.id = 'loader-overlay';
            overlayElement.className = 'loader-overlay';
            overlayElement.innerHTML = `
                <div class="loader-content">
                    <div class="loader-spinner"></div>
                    <div class="loader-text" id="loader-text">Loading...</div>
                </div>
            `;
            document.body.appendChild(overlayElement);
        } else {
            overlayElement = document.getElementById('loader-overlay');
        }
    }

    /**
     * Show loading overlay
     * @param {string} message - Optional loading message
     */
    function show(message = 'Loading...') {
        if (!overlayElement) init();
        
        activeCount++;
        const textEl = document.getElementById('loader-text');
        if (textEl) textEl.textContent = message;
        
        overlayElement.classList.add('visible');
    }

    /**
     * Hide loading overlay
     */
    function hide() {
        activeCount = Math.max(0, activeCount - 1);
        
        if (activeCount === 0 && overlayElement) {
            overlayElement.classList.remove('visible');
        }
    }

    /**
     * Force hide all loaders
     */
    function hideAll() {
        activeCount = 0;
        if (overlayElement) {
            overlayElement.classList.remove('visible');
        }
    }

    /**
     * Show inline loader in an element
     * @param {HTMLElement|string} element - Element or selector
     * @param {string} size - 'small', 'medium', 'large'
     */
    function inline(element, size = 'medium') {
        const el = typeof element === 'string' ? document.querySelector(element) : element;
        if (!el) return;

        const loader = document.createElement('div');
        loader.className = `inline-loader loader-${size}`;
        loader.innerHTML = '<div class="loader-spinner"></div>';
        
        el.appendChild(loader);
        return loader;
    }

    /**
     * Remove inline loader
     */
    function removeInline(loader) {
        if (loader && loader.parentNode) {
            loader.remove();
        }
    }

    /**
     * Show button loading state
     * @param {HTMLButtonElement} button - Button element
     * @param {boolean} loading - Whether to show loading
     */
    function button(btn, loading = true) {
        if (!btn) return;

        if (loading) {
            btn.dataset.originalText = btn.textContent;
            btn.disabled = true;
            btn.classList.add('btn-loading');
            btn.innerHTML = '<span class="btn-spinner"></span> Loading...';
        } else {
            btn.disabled = false;
            btn.classList.remove('btn-loading');
            btn.textContent = btn.dataset.originalText || 'Submit';
        }
    }

    /**
     * Wrap an async function with loading state
     * @param {Function} fn - Async function to wrap
     * @param {string} message - Loading message
     */
    function wrap(fn, message = 'Loading...') {
        return async (...args) => {
            show(message);
            try {
                return await fn(...args);
            } finally {
                hide();
            }
        };
    }

    // Initialize on load
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    return {
        show,
        hide,
        hideAll,
        inline,
        removeInline,
        button,
        wrap
    };
})();
