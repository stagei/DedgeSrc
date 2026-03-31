/**
 * DedgeAuth Theme Manager
 * Unified dark/light mode toggle for all DedgeAuth-integrated apps
 * 
 * Usage:
 * 1. Include this script in your HTML
 * 2. Add the theme toggle HTML (use .theme-toggle classes)
 * 3. Call DedgeAuthTheme.init() on DOMContentLoaded
 */
const DedgeAuthTheme = (function() {
    const STORAGE_KEY = 'gk-theme';
    
    let currentTheme = 'dark'; // Default to dark mode
    let toggleElement = null;

    /**
     * Initialize theme from localStorage or system preference
     */
    function init(toggleSelector = '#themeToggle, .theme-toggle__input') {
        // Get saved theme or detect system preference
        const savedTheme = localStorage.getItem(STORAGE_KEY);
        if (savedTheme) {
            currentTheme = savedTheme;
        } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
            currentTheme = 'light';
        }

        // Apply theme immediately
        applyTheme(currentTheme);

        // Setup toggle element
        toggleElement = document.querySelector(toggleSelector);
        if (toggleElement) {
            // Sync initial state
            if (toggleElement.type === 'checkbox') {
                toggleElement.checked = currentTheme === 'dark';
            }
            
            // Listen for changes
            toggleElement.addEventListener('change', () => {
                setTheme(toggleElement.checked ? 'dark' : 'light');
            });
        }

        // Listen for system theme changes
        if (window.matchMedia) {
            window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
                if (!localStorage.getItem(STORAGE_KEY)) {
                    setTheme(e.matches ? 'dark' : 'light');
                }
            });
        }

        return currentTheme;
    }

    /**
     * Apply theme to document
     */
    function applyTheme(theme) {
        if (theme === 'dark') {
            document.documentElement.setAttribute('data-theme', 'dark');
        } else {
            document.documentElement.setAttribute('data-theme', 'light');
        }
    }

    /**
     * Set a specific theme
     */
    function setTheme(theme) {
        currentTheme = theme;
        localStorage.setItem(STORAGE_KEY, theme);
        applyTheme(theme);
        
        // Sync toggle state
        if (toggleElement && toggleElement.type === 'checkbox') {
            toggleElement.checked = theme === 'dark';
        }
        
        // Dispatch event for other components
        document.dispatchEvent(new CustomEvent('gk-themechange', { detail: { theme } }));
    }

    /**
     * Toggle between dark and light themes
     */
    function toggle() {
        setTheme(currentTheme === 'dark' ? 'light' : 'dark');
    }

    /**
     * Get current theme
     */
    function getTheme() {
        return currentTheme;
    }

    /**
     * Check if dark mode is active
     */
    function isDark() {
        return currentTheme === 'dark';
    }

    return {
        init,
        toggle,
        setTheme,
        getTheme,
        isDark
    };
})();

// Auto-initialize if DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => DedgeAuthTheme.init());
} else {
    DedgeAuthTheme.init();
}
